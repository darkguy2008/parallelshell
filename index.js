#!/usr/bin/env node

'use strict';
var spawn = require('child_process').spawn;

function potentialExit (childCmd, code) {
    code = code? (code.code || code) : code;
    if (code > 0) {
        console.error('`' + childCmd + '` failed with exit code ' + code);
        process.exit(code);
    }
}
var sh = 'sh';
var shFlag = '-c';

if (process.platform === 'win32') {
    sh = 'cmd';
    shFlag = '/c';
}
process.argv.slice(2).forEach(function (childCmd) {
    var child = spawn(sh,[shFlag,childCmd], {
        cwd: process.cwd,
        env: process.env,
        stdio: ['pipe', process.stdout, process.stderr]
    })
    .on('error', potentialExit.bind(null, childCmd))
    .on('exit', potentialExit.bind(null, childCmd));
});
