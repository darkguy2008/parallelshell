#!/usr/bin/env node

'use strict';
var spawn = require('child_process').spawn;
var path = require('path');
var signals = require('constants');
var SIGNAL_EXIT_CODE_BASE = 128;
var FORWARDED_SIGNALS = ['SIGINT', 'SIGTERM', 'SIGHUP'];
var WINDOWS_CONTROL_C_EXIT = 0xC000013A;
var TIMEOUT_EXIT_CODE = 124;
var MILLISECONDS_PER_SECOND = 1000;
var MAX_TIMEOUT_MS = Math.pow(2, 31) - 1;

var WINDOWS = process.platform === 'win32';
var commandPrefix = WINDOWS ? '' : 'exec ';
var children, args, wait, cmds, verbose, timeout, timer, i ,len;
cmds = [];
args = process.argv.slice(2);
for (i = 0, len = args.length; i < len; i++) {
    if (args[i][0] === '-') {
        switch (args[i]) {
            case '-t':
            case '--timeout':
                timeout = Number(args[++i]) * MILLISECONDS_PER_SECOND;
                if (!isFinite(timeout) || timeout <= 0 || timeout > MAX_TIMEOUT_MS) {
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
                console.log('-h, --help         output usage information');
                console.log('-v, --verbose      verbose logging')
                console.log('-w, --wait         will not close sibling processes on error')
                console.log('-t, --timeout <seconds>  stop remaining commands after the deadline');
                process.exit();
                break;
        }
    } else {
        cmds.push(args[i]);
    }
}

function childClose (code, signal) {
    if (children.every(function (child) {
        return child.exitCode !== null || child.signalCode !== null;
    })) clearTimeout(timer);
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
            if (children[i].exitCode === null && children[i].signalCode === null) {
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
    var running = children.filter(function (child) {
        return child.exitCode === null && child.signalCode === null;
    });
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
    var command = commandPrefix + cmd;
    var child = spawn(command, {
        shell: true,
        stdio: ['pipe', process.stdout, process.stderr]
    }).on('close', childClose);
    child.cmd = command;
    return child;
});

if (timeout && children.length) {
    timer = setTimeout(function () {
        console.error('parallelshell timed out after ' + timeout / MILLISECONDS_PER_SECOND + ' seconds');
        process.exitCode = process.exitCode || TIMEOUT_EXIT_CODE;
        close();
    }, timeout);
}
