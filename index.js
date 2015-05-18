#!/usr/bin/env node

'use strict';
var spawn = require('child_process').spawn;
var fixArgsOnWindows = require('node_issue_25339_workaround');

var sh, shFlag, children, originalArgs, args, hasFixedArgs, wait, cmds, verbose, i, len;
// parsing argv
cmds = [];
args = originalArgs = process.argv.slice(2);

// cross platform compatibility
if (process.platform === 'win32') {
    sh = 'cmd';
    shFlag = '/c';
    
    args = fixArgsOnWindows(originalArgs);
    hasFixedArgs = true;
} else {
    sh = 'sh';
    shFlag = '-c';
}

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
                console.log('-w, --wait         will not close silbling processes on error')
                process.exit();
                break;
        }
    } else {
        cmds.push(args[i]);
    }
}

if (verbose && hasFixedArgs) {
    console.log('### Original arguments ###');
    console.log(originalArgs.join('\n'));
    console.log('\n');
    console.log('### Fixed arguments ###');
    console.log(args.join('\n'));
    console.log('\n');
}

// called on close of a child process
function childClose (code) {
    var i, len;
    code = code ? (code.code || code) : code;
    if (verbose) {
        if (code > 0) {
            console.error('`' + this.cmd + '` failed with exit code ' + code);
        } else {
            console.log('`' + this.cmd + '` ended successfully');
        }
    }
    if (code > 0 && !wait) close(code);
    status();
}

function status () {
    if (verbose) {
        var i, len;
        console.log('\n');
        console.log('### Status ###');
        for (i = 0, len = children.length; i < len; i++) {
            if (children[i].exitCode === null) {
                console.log('`' + children[i].cmd + '` is still running');
            } else if (children[i].exitCode > 0) {
                console.log('`' + children[i].cmd + '` errored');
            } else {
                console.log('`' + children[i].cmd + '` finished');
            }
        }
        console.log('\n');
    }
}

// closes all children and the process
function close (code) {
    var i, len;
    for (i = 0, len = children.length; i < len; i++) {
        if (!children[i].exitCode) {
            children[i].removeAllListeners('close');
            children[i].kill('SIGINT');
            if (verbose) console.log('`' + children[i].cmd + '` will now be closed');
        }
    }
    process.exit(code);
}

// start the children
children = [];
cmds.forEach(function (cmd) {
    var child = spawn(sh,[shFlag,cmd], {
        cwd: process.cwd,
        env: process.env,
        stdio: ['pipe', process.stdout, process.stderr]
    })
    .on('close', childClose);
    child.cmd = cmd
    children.push(child)
});

// close all children on ctrl+c
process.on('SIGINT', close)
