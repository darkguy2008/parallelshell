#!/usr/bin/env node

'use strict';
var spawn = require('child_process').spawn;
var fs = require('fs');
var path = require('path');
var signals = require('constants');
var SIGNAL_EXIT_CODE_BASE = 128;
var FORWARDED_SIGNALS = ['SIGINT', 'SIGTERM', 'SIGHUP'];
var STOP_SIGNAL = 'SIGTERM';
var UNSIGNALABLE_GROUP_ERRORS = ['ESRCH', 'EPERM'];
var CLOSED_READER_ERRORS = ['EPIPE', 'ECONNRESET'];
var LIFETIME_FD = 3;
var LABEL_USAGE = '--label requires a name followed by a command';
var WINDOWS_CONTROL_C_EXIT = 0xC000013A;
var TIMEOUT_EXIT_CODE = 124;
var MILLISECONDS_PER_SECOND = 1000;
var MAX_TIMEOUT_MS = Math.pow(2, 31) - 1;
var SCRIPT_PATTERN_OPTIONS = { dot: true, nocomment: true, nonegate: true, allowWindowsEscape: true };
var CONCURRENTLY_PREFIX_LENGTH = 10;
var LABEL_ELLIPSIS = '..';
var PREFIX_SEPARATOR = ' | ';
var DOCKER_COMPOSE_COLORS = ['36', '33', '32', '35', '34', '36;1', '33;1', '32;1', '35;1', '34;1'];
var BASIC_COLOR_LEVEL = '1';
var FORCE_COLOR_ENABLED = ['', BASIC_COLOR_LEVEL, '2', '3', 'true'];
var FORCE_COLOR_LEVELS = { 4: '1', 8: '2', 24: '3' };
var LINE_ENDINGS = /(\r\n|\r|\n)/;
var CARRIAGE_RETURN = '\r';
var WATCHDOG_ADD = 'add';
var WATCHDOG_FORGET = 'forget';
var WATCHDOG_RELEASE = 'release';
var WATCHDOG_SCRIPT = [
    "trap '' INT TERM HUP",
    'groups=',
    'while read -r action group; do',
    '    case $action in',
    '        ' + WATCHDOG_ADD + ') groups="$groups $group" ;;',
    '        ' + WATCHDOG_FORGET + ') kept=; for tracked in $groups; do [ "$tracked" = "$group" ] || kept="$kept $tracked"; done; groups=$kept ;;',
    '        ' + WATCHDOG_RELEASE + ') exit ;;',
    '    esac',
    'done',
    'for group in $groups; do kill -' + STOP_SIGNAL.slice('SIG'.length) + ' -$group; done'
].join('\n');

var WINDOWS = process.platform === 'win32';
var children, args, wait, cmds, verbose, timeout, timer, scripts, prefix, label, stopping, stopSignal, watchdog, i ,len;
var groups = [];
cmds = [];
args = process.argv.slice(2);
for (i = 0, len = args.length; i < len; i++) {
    if (args[i][0] === '-') {
        switch (args[i]) {
            case '-n':
            case '--npm':
                var pattern = args[++i];
                var names;
                try {
                    names = matchingScripts(pattern);
                } catch (error) {
                    usageError('--npm: ' + error.message);
                }
                if (label !== undefined && names.length > 1) usageError('--label names one command but ' + JSON.stringify(pattern) + ' matches ' + names.length + ' npm scripts');
                names.forEach(function (name) {
                    cmds.push({ cmd: 'npm run -- ' + name, script: name, label: takeLabel(name) });
                });
                break;
            case '-t':
            case '--timeout':
                timeout = Number(args[++i]);
                if (!(timeout > 0 && timeout * MILLISECONDS_PER_SECOND <= MAX_TIMEOUT_MS)) {
                    usageError('--timeout requires positive seconds no greater than ' + MAX_TIMEOUT_MS / MILLISECONDS_PER_SECOND);
                }
                break;
            case '-p':
            case '--prefix':
                prefix = true;
                break;
            case '-l':
            case '--label':
                if (label !== undefined || !args[i + 1] || args[i + 1][0] === '-') usageError(LABEL_USAGE);
                label = args[++i];
                prefix = true;
                break;
            case '-w':
            case '--wait':
                wait = true;
                break;
            case '-v':
            case '--verbose':
                verbose = true;
                break;
            case '-h':
            case '--help':
                console.log('-h, --help               output usage information');
                console.log('-v, --verbose            verbose logging');
                console.log('-w, --wait               will not close sibling processes on error');
                console.log('-t, --timeout <seconds>  stop remaining commands after the deadline');
                console.log('-n, --npm <pattern>      run matching npm scripts from package.json');
                console.log('-p, --prefix             prefix each output line with its command\'s label');
                console.log('-l, --label <name>       label the next command, implies --prefix');
                process.exit();
                break;
        }
    } else {
        cmds.push({ cmd: args[i], label: takeLabel(shorten(args[i])) });
    }
}
if (label !== undefined) usageError(LABEL_USAGE);

function usageError (message) {
    console.error(message);
    process.exit(1);
}

function rethrowUnless (codes, error) {
    if (codes.indexOf(error.code) === -1) throw error;
}

function takeLabel (fallback) {
    var taken = label === undefined ? fallback : label;
    label = undefined;
    return taken;
}

function shorten (text) {
    if (text.length <= CONCURRENTLY_PREFIX_LENGTH) return text;
    var kept = CONCURRENTLY_PREFIX_LENGTH - LABEL_ELLIPSIS.length;
    return text.slice(0, Math.ceil(kept / 2)) + LABEL_ELLIPSIS + text.slice(text.length - Math.floor(kept / 2));
}

function matchingScripts (pattern) {
    if (!pattern || pattern[0] === '-') throw new Error('requires a script name or pattern');
    scripts = scripts || JSON.parse(fs.readFileSync('package.json', 'utf8')).scripts;
    if (!scripts || typeof scripts !== 'object' || Array.isArray(scripts)) throw new Error('package.json must contain a scripts object');
    var matches = Object.prototype.hasOwnProperty.call(scripts, pattern) ? [pattern] : require('minimatch').match(Object.keys(scripts), pattern, SCRIPT_PATTERN_OPTIONS);
    if (!matches.length) throw new Error('no npm scripts match ' + JSON.stringify(pattern));
    matches.forEach(function (name) {
        if (typeof scripts[name] !== 'string') throw new Error('npm script ' + JSON.stringify(name) + ' must be a string');
    });
    return matches;
}

function colorsEnabled (stream) {
    if (process.env.FORCE_COLOR !== undefined) return FORCE_COLOR_ENABLED.indexOf(process.env.FORCE_COLOR) !== -1;
    return !process.env.NO_COLOR && Boolean(stream.isTTY) && (!stream.hasColors || stream.hasColors());
}

function childEnvironment () {
    var env = Object.assign({}, process.env);
    if (env.FORCE_COLOR === undefined && !env.NO_COLOR && outputs.stdout.colored) {
        env.FORCE_COLOR = process.stdout.getColorDepth ? FORCE_COLOR_LEVELS[process.stdout.getColorDepth()] : BASIC_COLOR_LEVEL;
        if (env.CLICOLOR_FORCE === undefined) env.CLICOLOR_FORCE = BASIC_COLOR_LEVEL;
    }
    return env;
}

function output (stream) {
    var target = { stream: stream, colored: colorsEnabled(stream), writer: null, lineOpen: false, paused: [], broken: false };
    stream.on('error', function (error) {
        rethrowUnless(CLOSED_READER_ERRORS, error);
        target.broken = true;
        process.exitCode = process.exitCode || SIGNAL_EXIT_CODE_BASE + signals.SIGPIPE;
        close();
    });
    return target;
}

var outputs = { stdout: output(process.stdout), stderr: output(process.stderr) };

function labelFor (cmd, index, target) {
    var text = cmd.label + ' '.repeat(labelWidth - cmd.label.length) + PREFIX_SEPARATOR;
    return target.colored ? '\x1b[' + DOCKER_COMPOSE_COLORS[index % DOCKER_COMPOSE_COLORS.length] + 'm' + text + '\x1b[0m' : text;
}

function write (target, writer, linePrefix, text, source) {
    if (!text || target.broken) return;
    var result = '';
    if (target.lineOpen && target.writer !== writer) {
        result = '\n';
        target.lineOpen = false;
    }
    text.split(LINE_ENDINGS).forEach(function (piece, position) {
        if (!piece) return;
        var ending = position % 2 === 1;
        if (!target.lineOpen && piece !== CARRIAGE_RETURN) result += linePrefix;
        result += piece;
        target.lineOpen = !ending;
    });
    target.writer = writer;
    if (!target.stream.write(result) && source) {
        source.pause();
        if (target.paused.push(source) === 1) target.stream.once('drain', function () {
            target.paused.splice(0).forEach(function (paused) { paused.resume(); });
        });
    }
}

function relay (source, target, writer, linePrefix) {
    var pendingReturn = '';
    source.setEncoding('utf8');
    source.on('data', function (text) {
        text = pendingReturn + text;
        pendingReturn = text[text.length - 1] === CARRIAGE_RETURN ? CARRIAGE_RETURN : '';
        write(target, writer, linePrefix, text.slice(0, text.length - pendingReturn.length), source);
    }).on('end', function () {
        write(target, writer, linePrefix, pendingReturn, source);
    });
}

function say (target, message) {
    write(target, null, '', message + '\n');
}

function isClosed (child) {
    return child.closed;
}

function hasExited (child) {
    return child.exitCode !== null || child.signalCode !== null;
}

function isRunning (child) {
    return !isClosed(child) && !hasExited(child);
}

function childClose (code, signal) {
    code = signal ? SIGNAL_EXIT_CODE_BASE + signals[signal] : code;
    if (verbose) {
        if (code > 0) {
            say(outputs.stderr, '`' + this.cmd + '` failed with exit code ' + code);
        } else {
            say(outputs.stdout, '`' + this.cmd + '` ended successfully');
        }
    }
    if (code > 0) {
        process.exitCode = process.exitCode || code;
        if (!wait) close(FORWARDED_SIGNALS.find(function (forwarded) {
            return code === SIGNAL_EXIT_CODE_BASE + signals[forwarded];
        }));
    }
    status();
}

function childClosed () {
    this.closed = true;
    if (groups.indexOf(this) !== -1) forgetGroup(this);
    settle();
}

function settle () {
    if (!children.every(isClosed)) return;
    if (stopping) {
        exit(stopSignal);
    } else {
        release(function () {});
    }
}

function status () {
    if (verbose) {
        var i, len;
        say(outputs.stdout, '\n');
        say(outputs.stdout, '### Status ###');
        for (i = 0, len = children.length; i < len; i++) {
            if (!isClosed(children[i])) {
                say(outputs.stdout, '`' + children[i].cmd + '` is still running');
            } else if (children[i].exitCode !== 0) {
                say(outputs.stdout, '`' + children[i].cmd + '` errored');
            } else {
                say(outputs.stdout, '`' + children[i].cmd + '` finished');
            }
        }
        say(outputs.stdout, '\n');
    }
}

function close (signal) {
    clearTimeout(timer);
    if (signal) stopSignal = signal;
    if (!stopping) {
        stopping = true;
        children.forEach(function (child) {
            child.removeListener('close', childClose);
            if (verbose && !isClosed(child)) say(outputs.stdout, '`' + child.cmd + '` will now be closed');
        });
    }
    stop(signal || STOP_SIGNAL);
    settle();
}

function stop (signal) {
    if (WINDOWS) {
        var running = children.filter(isRunning);
        if (running.length) spawn(path.join(process.env.SystemRoot, 'System32', 'taskkill.exe'), running.reduce(function (taskkillArgs, child) {
            return taskkillArgs.concat('/PID', String(child.pid));
        }, ['/T', '/F']), { stdio: 'ignore' });
        children.filter(function (child) { return !isClosed(child) && hasExited(child) && child.stdout; }).forEach(function (child) {
            child.stdout.destroy();
            child.stderr.destroy();
        });
    } else {
        groups.forEach(function (child) {
            signalGroup(child, hasExited(child) ? STOP_SIGNAL : signal);
        });
    }
}

function signalGroup (child, signal) {
    try {
        process.kill(-child.pid, signal);
    } catch (error) {
        rethrowUnless(UNSIGNALABLE_GROUP_ERRORS, error);
    }
}

function forgetGroup (child) {
    try {
        process.kill(-child.pid, 0);
    } catch (error) {
        rethrowUnless(UNSIGNALABLE_GROUP_ERRORS, error);
        if (error.code === 'EPERM') return;
        groups.splice(groups.indexOf(child), 1);
        watchdog.stdin.write(WATCHDOG_FORGET + ' ' + child.pid + '\n');
    }
}

function release (callback) {
    if (!watchdog || hasExited(watchdog)) return callback();
    watchdog.ref();
    watchdog.once('exit', callback);
    if (watchdog.stdin.writable) watchdog.stdin.end(WATCHDOG_RELEASE + '\n');
}

function flush (target, callback) {
    if (target.broken) return callback();
    target.stream.write('', callback);
}

function exit (signal) {
    release(function () {
        flush(outputs.stdout, function () {
            flush(outputs.stderr, function () {
                if (signal && WINDOWS) {
                    process.exit(WINDOWS_CONTROL_C_EXIT);
                } else if (signal) {
                    process.removeAllListeners(signal);
                    process.kill(process.pid, signal);
                } else {
                    process.exit();
                }
            });
        });
    });
}

FORWARDED_SIGNALS.forEach(function (signal) {
    process.once(signal, function () { close(signal); });
});

if (!WINDOWS && cmds.length) {
    watchdog = spawn(WATCHDOG_SCRIPT, { shell: true, stdio: ['pipe', 'ignore', 'ignore'] });
    watchdog.unref();
    watchdog.stdin.on('error', function (error) {
        rethrowUnless(CLOSED_READER_ERRORS, error);
    });
    process.on('SIGTSTP', function () {
        groups.forEach(function (child) { signalGroup(child, 'SIGSTOP'); });
        process.kill(process.pid, 'SIGSTOP');
    });
    process.on('SIGCONT', function () {
        groups.forEach(function (child) { signalGroup(child, 'SIGCONT'); });
    });
}

var env = prefix ? childEnvironment() : process.env;
var labelWidth = cmds.reduce(function (longest, cmd) { return Math.max(longest, cmd.label.length); }, 0);
children = cmds.map(function (cmd, index) {
    var options = {
        stdio: (prefix ? ['pipe', 'pipe', 'pipe'] : ['pipe', process.stdout, process.stderr]).concat(WINDOWS ? [] : ['pipe']),
        detached: !WINDOWS,
        env: env,
        shell: cmd.script === undefined
    };
    var child = cmd.script === undefined
        ? spawn(cmd.cmd, options)
        : require('cross-spawn')('npm', ['run', '--', cmd.script], options);
    child.on('error', function (error) {
        say(outputs.stderr, error.message);
        this.removeListener('close', childClose);
        childClose.call(this, 1);
    }).on('close', childClosed).on('close', childClose);
    child.cmd = cmd.cmd;
    if (prefix) {
        relay(child.stdout, outputs.stdout, child, labelFor(cmd, index, outputs.stdout));
        relay(child.stderr, outputs.stderr, child, labelFor(cmd, index, outputs.stderr));
    }
    if (watchdog && child.pid) {
        groups.push(child);
        watchdog.stdin.write(WATCHDOG_ADD + ' ' + child.pid + '\n');
        child.stdio[LIFETIME_FD].resume();
        child.on('exit', function () {
            if (stopping) {
                signalGroup(this, STOP_SIGNAL);
            } else {
                this.stdio[LIFETIME_FD].destroy();
            }
        });
    }
    return child;
});

if (timeout) {
    timer = setTimeout(function () {
        say(outputs.stderr, 'parallelshell timed out after ' + timeout + ' seconds');
        process.exitCode = process.exitCode || TIMEOUT_EXIT_CODE;
        close();
    }, timeout * MILLISECONDS_PER_SECOND);
    timer.unref();
}
