#!/usr/bin/env node

'use strict';
var spawn = require('child_process').spawn;
var fs = require('fs');
var path = require('path');
var signals = require('constants');
var SIGNAL_EXIT_CODE_BASE = 128;
var FORWARDED_SIGNALS = ['SIGINT', 'SIGTERM', 'SIGHUP'];
var WINDOWS_CONTROL_C_EXIT = 0xC000013A;
var TIMEOUT_EXIT_CODE = 124;
var MILLISECONDS_PER_SECOND = 1000;
var MAX_TIMEOUT_MS = Math.pow(2, 31) - 1;
var SCRIPT_PATTERN_OPTIONS = { dot: true, nocomment: true, nonegate: true, allowWindowsEscape: true };

var WINDOWS = process.platform === 'win32';
var commandPrefix = WINDOWS ? '' : 'exec ';
var children, args, wait, cmds, verbose, timeout, timer, scripts, i ,len;
cmds = [];
args = process.argv.slice(2);
for (i = 0, len = args.length; i < len; i++) {
    if (args[i][0] === '-') {
        switch (args[i]) {
            case '-n':
            case '--npm':
                try {
                    matchingScripts(args[++i]).forEach(function (name) {
                        cmds.push({ cmd: 'npm run -- ' + name, script: name });
                    });
                } catch (error) {
                    console.error('--npm: ' + error.message);
                    process.exit(1);
                }
                break;
            case '-t':
            case '--timeout':
                timeout = Number(args[++i]);
                if (!(timeout > 0 && timeout * MILLISECONDS_PER_SECOND <= MAX_TIMEOUT_MS)) {
                    console.error('--timeout requires positive seconds no greater than ' + MAX_TIMEOUT_MS / MILLISECONDS_PER_SECOND);
                    process.exit(1);
                }
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
                process.exit();
                break;
        }
    } else {
        cmds.push({ cmd: commandPrefix + args[i] });
    }
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

function isRunning (child) {
    return child.exitCode === null && child.signalCode === null;
}

function childClose (code, signal) {
    code = signal ? SIGNAL_EXIT_CODE_BASE + signals[signal] : code;
    if (verbose) {
        if (code > 0) {
            console.error('`' + this.cmd + '` failed with exit code ' + code);
        } else {
            console.log('`' + this.cmd + '` ended successfully');
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

function status () {
    if (verbose) {
        var i, len;
        console.log('\n');
        console.log('### Status ###');
        for (i = 0, len = children.length; i < len; i++) {
            if (isRunning(children[i])) {
                console.log('`' + children[i].cmd + '` is still running');
            } else if (children[i].exitCode !== 0) {
                console.log('`' + children[i].cmd + '` errored');
            } else {
                console.log('`' + children[i].cmd + '` finished');
            }
        }
        console.log('\n');
    }
}

function close (signal) {
    clearTimeout(timer);
    var running = children.filter(isRunning);
    var remaining = running.length;
    if (remaining === 0) return exit(signal);
    running.forEach(function (child) {
        child.removeAllListeners('close');
        if (verbose) console.log('`' + child.cmd + '` will now be closed');
        child.on('close', function () {
            remaining--;
            if (remaining === 0) exit(signal);
        });
    });
    stop(running, signal || 'SIGINT');
}

function stop (running, signal) {
    if (WINDOWS) {
        spawn(path.join(process.env.SystemRoot, 'System32', 'taskkill.exe'), running.reduce(function (taskkillArgs, child) {
            return taskkillArgs.concat('/PID', String(child.pid));
        }, ['/T', '/F']), { stdio: 'ignore' });
    } else {
        running.forEach(function (child) {
            child.kill(signal);
        });
    }
}

function exit (signal) {
    if (signal && WINDOWS) {
        process.exit(WINDOWS_CONTROL_C_EXIT);
    } else if (signal) {
        process.removeAllListeners(signal);
        process.kill(process.pid, signal);
    } else {
        process.exit();
    }
}

FORWARDED_SIGNALS.forEach(function (signal) {
    process.once(signal, function () { close(signal); });
});

children = cmds.map(function (cmd) {
    var stdio = ['pipe', process.stdout, process.stderr];
    var child = cmd.script === undefined
        ? spawn(cmd.cmd, { shell: true, stdio: stdio })
        : require('cross-spawn')('npm', ['run', '--', cmd.script], { stdio: stdio });
    child.on('error', function (error) {
        console.error(error.message);
        this.removeListener('close', childClose);
        childClose.call(this, 1);
    }).on('close', childClose);
    child.cmd = cmd.cmd;
    return child;
});

if (timeout) {
    timer = setTimeout(function () {
        console.error('parallelshell timed out after ' + timeout + ' seconds');
        process.exitCode = process.exitCode || TIMEOUT_EXIT_CODE;
        close();
    }, timeout * MILLISECONDS_PER_SECOND);
    timer.unref();
}
