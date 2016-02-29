#!/usr/bin/env node

'use strict';
var spawn = require('child_process').spawn;

var sh, shFlag, children, args, wait, first, cmds, verbose, i ,len;
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
            case '-f':
            case '--first':
                first = true;
                break;
            case '-v':
            case '--verbose':
                verbose = true;
                break;
            case '-h':
            case '--help':
                console.log('-h, --help         output usage information');
                console.log('-v, --verbose      verbose logging');
                console.log('-w, --wait         will not close sibling processes on error');
                console.log('-f, --first        close all sibling processes after first exits (succes/error)');
                process.exit();
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

// called on close of a child process
function childClose (code) {
    var i, len;
    code = code ? (code.code || code) : code;
    if (verbose) {
        if (code > 0) {
            console.error('parallelshell: `' + this.cmd + '` failed with exit code ' + code);
        } else {
            console.log('parallelshell: `' + this.cmd + '` ended successfully');
        }
    }
    if (first || code > 0 && !wait) close(code);
}

function status () {
    if (verbose) {
        var i, len;
        console.log('parallelshell: Status');
        for (i = 0, len = children.length; i < len; i++) {
            if (children[i].exitCode === null) {
                console.log('parallelshell: `' + children[i].cmd + '` is still running');
            } else if (children[i].exitCode > 0) {
                console.log('parallelshell: `' + children[i].cmd + '` errored');
            } else {
                console.log('parallelshell: `' + children[i].cmd + '` finished');
            }
        }
    }
}

// closes all children and the process
function close (code) {
    var i, len, closeHandler, closed = 0, opened = 0;

    for (i = 0, len = children.length; i < len; i++) {
        if (children[i].exitCode === null) {
            opened++;
            children[i].removeAllListeners('close');
            if (process.platform != "win32") {
                spawn(sh, [shFlag, "kill -INT -"+children[i].pid]);
            } else {
                children[i].kill("SIGINT");
            }
            if (verbose) console.log('parallelshell: `' + children[i].cmd + '` will now be closed');
            closeHandler = function (child) {
                child.on('close', function() {
                    if (verbose) console.log('parallelshell: `' + child.cmd + '` closed successfully');
                    closed++;
                    if (opened == closed) {
                        process.exit(code);
                    }
                });
            }(children[i])

        }
    }
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
    var child = spawn(sh,[shFlag,cmd], {
        cwd: process.cwd,
        env: process.env,
        stdio: ['pipe', process.stdout, process.stderr],
        windowsVerbatimArguments: process.platform === 'win32',
        detached: process.platform != 'win32'
    })
    .on('close', childClose);
    child.cmd = cmd
    children.push(child)
});

// close all children on ctrl+c
process.on('SIGINT', function() {
    if (verbose) console.log('parallelshell: recieved SIGINT');
    close();
});

process.on('exit', function(code) {
    if (verbose) console.log('parallelshell: exit code:', code);
});
