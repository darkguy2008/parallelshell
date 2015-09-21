#!/usr/bin/env node

'use strict';
var spawn = require('child_process').spawn,
    debug = require('debug');

var verbose = debug('parallelshell:verbose'),
    dbg = debug('parallelshell:dbg');

var sh, shFlag, children, args, wait, first, cmds, i ,len;
// parsing argv
cmds = [];
args = process.argv.slice(2);
if (args.length === 0) printUseageExit();
for (i = 0, len = args.length; i < len; i++) {
    if (args[i][0] === '-') {
        switch (args[i]) {
            case '-w':
            case '--wait':
                wait = true;
                break;
            case '-f':
            case '--first':
                first = true;
                break;
            case '-v':
            case '--verbose':
                debug.enable('parallelshell:verbose');
                verbose = debug('parallelshell:verbose');
                break;
            case '-h':
            case '--help':
                printUseageExit();
                break;
        }
    } else {
        cmds.push(args[i]);
    }
}

if (wait && first) {
  console.error('--wait and --first cannot be used together');
  process.exit(1);
}

function printUseageExit() {
    console.log('Useage:');
    console.log('  -h, --help         output usage information');
    console.log('  -v, --verbose      verbose logging');
    console.log('  -w, --wait         will not close sibling processes on error');
    console.log('  -f, --first        close all sibling processes after first exits (succes/error)');
    process.exit();
}

// called on close of a child process
function childClose (code) {
    var actualCode = code ? (code.code || code) : code;
    dbg('In childClose, with code: %d', actualCode);
    if (actualCode > 0) {
        verbose('`%s` failed with exit code: %d', actualCode);
    } else {
        verbose('`%s` ended successfully');
    }
    if (first || actualCode > 0 && !wait) close(actualCode);
}

function status () {
    var i, len;
    if (verbose.enabled) {
        verbose('Status');
        for (i = 0, len = children.length; i < len; i++) {
            if (children[i].exitCode === null) {
                verbose('`%s` is still running', children[i].cmd);
            } else if (children[i].exitCode > 0) {
                verbose('`%s` errored', children[i].cmd);
            } else {
                verbose('`%s` finished', children[i].cmd);
            }
        }
    }
}

// closes all children and the process
function close (code) {
    dbg('In close with code: %d', code);
    var i, len, closeHandler, closed = 0, opened = 0;

    for (i = 0, len = children.length; i < len; i++) {
        if (!children[i].exitCode) {
            opened++;
            children[i].removeAllListeners('close');
            if (process.platform != "win32") {
                children[i].kill("SIGINT");
                spawn(sh, [shFlag, "kill -INT -"+children[i].pid]);
            } else {
                children[i].kill("SIGINT");
            }
            verbose('`' + children[i].cmd + '` will now be closed');
            closeHandler = function (child) {
                child.on('close', function() {
                    verbose('`' + child.cmd + '` closed successfully');
                    closed++;
                    dbg('opened: %d, closed: %d', opened, closed)
                    if (opened == closed) {
                        process.exit(code);
                    }
                });
            }(children[i])

        }
    }
    dbg('opened: %d, closed: %d', opened, closed)
    if (opened == closed) {process.exit(code);}

}

// cross platform compatibility
if (process.platform === 'win32') {
    sh = 'cmd';
    shFlag = '/c';
} else {
    sh = 'sh';
    shFlag = '-c';
}

// start the children
children = [];
cmds.forEach(function (cmd) {
    if (process.platform === 'win32') {
        cmd = cmd.replace(/'/g,"\"");
    }
    dbg("Spawning the cmd `%s`", cmd)
    var child = spawn(sh, [shFlag, cmd], {
        cwd: process.cwd,
        env: process.env,
        stdio: ['pipe', 1, 2],
        windowsVerbatimArguments: process.platform === 'win32',
        detached: process.platform != 'win32'
    })
    .on('close', childClose);
    child.cmd = cmd
    children.push(child)
});

// close all children on ctrl+c
process.on('SIGINT', function() {
    verbose('recieved SIGINT');
    close();
});

process.on('exit', function(code) {
    verbose('exit code: %d', code);
});
