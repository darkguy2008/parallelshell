#!/usr/bin/env node

'use strict';
var spawn = require('child_process').spawn;
var signals = require('constants');
var SIGNAL_EXIT_CODE_BASE = 128;
var FORWARDED_SIGNALS = ['SIGINT', 'SIGTERM', 'SIGHUP'];

var sh, shFlag, children, args, wait, cmds, verbose, i ,len;
// parsing argv
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

// called on close of a child process
function childClose (code, signal) {
    var i, len;
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
        if (!wait) close(process.exitCode, interruption(code));
    }
    status();
}

function interruption (code) {
    return FORWARDED_SIGNALS.filter(function (signal) {
        return code === SIGNAL_EXIT_CODE_BASE + signals[signal];
    })[0];
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

// closes all children and the process
function close (code, signal) {
    var i, len, closed = 0, opened = 0;

    for (i = 0, len = children.length; i < len; i++) {
        if (children[i].exitCode === null && children[i].signalCode === null) {
            opened++;
            children[i].removeAllListeners('close');
            children[i].kill(signal || "SIGINT");
            if (verbose) console.log('`' + children[i].cmd + '` will now be closed');
            children[i].on('close', function() {
                closed++;
                if (opened == closed) {
                    exit(code, signal);
                }
            });
        }
    }
    if (opened == closed) {exit(code, signal);}

}

function exit (code, signal) {
    if (signal) {
        process.removeAllListeners(signal);
        process.kill(process.pid, signal);
    } else {
        process.exit(code);
    }
}

// cross platform compatibility
if (process.platform === 'win32') {
    sh = 'cmd';
    shFlag = '/c';
} else {
    sh = 'sh';
    shFlag = '-c';
}

FORWARDED_SIGNALS.forEach(function (signal) {
    process.once(signal, function () { close(null, signal); });
});

// start the children
children = [];
cmds.forEach(function (cmd) {
    if (process.platform != 'win32') {
      cmd = "exec "+cmd;
    }
    var child = spawn(sh,[shFlag,cmd], {
        stdio: ['pipe', process.stdout, process.stderr]
    })
    .on('close', childClose);
    child.cmd = cmd
    children.push(child)
});
