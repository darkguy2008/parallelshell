#!/usr/bin/env node

'use strict';
var spawn = require('child_process').spawn;
var signals = require('constants');
var SIGNAL_EXIT_CODE_BASE = 128;
var FORWARDED_SIGNALS = ['SIGINT', 'SIGTERM', 'SIGHUP'];

var sh, shFlag, commandPrefix, children, args, wait, cmds, verbose, i ,len;
cmds = [];
args = process.argv.slice(2);
for (i = 0, len = args.length; i < len; i++) {
    if (args[i][0] === '-') {
        switch (args[i]) {
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
                process.exit();
                break;
        }
    } else {
        cmds.push(args[i]);
    }
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
    var running = children.filter(function (child) {
        return child.exitCode === null && child.signalCode === null;
    });
    var remaining = running.length;
    running.forEach(function (child) {
        child.removeAllListeners('close');
        child.kill(signal || 'SIGINT');
        if (verbose) console.log('`' + child.cmd + '` will now be closed');
        child.on('close', function () {
            remaining--;
            if (remaining === 0) exit(signal);
        });
    });
    if (remaining === 0) exit(signal);
}

function exit (signal) {
    if (signal) {
        process.removeAllListeners(signal);
        process.kill(process.pid, signal);
    } else {
        process.exit();
    }
}

if (process.platform === 'win32') {
    sh = 'cmd';
    shFlag = '/c';
    commandPrefix = '';
} else {
    sh = 'sh';
    shFlag = '-c';
    commandPrefix = 'exec ';
}

FORWARDED_SIGNALS.forEach(function (signal) {
    process.once(signal, function () { close(signal); });
});

children = cmds.map(function (cmd) {
    var child = spawn(sh, [shFlag, commandPrefix + cmd], {
        stdio: ['pipe', process.stdout, process.stderr]
    }).on('close', childClose);
    child.cmd = commandPrefix + cmd;
    return child;
});
