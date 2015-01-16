#!/usr/bin/env node
'use strict';
var exec = require('child_process').exec;

function potentialExit (childCmd, code) {
    code = code? (code.code || code) : code;
    if (code > 0) {
        console.error('`' + childCmd + '` failed with exit code ' + code);
        process.exit(code);
    }
}

process.argv.slice(2).forEach(function (childCmd) {
    var child = exec(childCmd, {
        cwd: process.cwd(),
        env: process.env,
    })
    .on('error', potentialExit.bind(null, childCmd))
    .on('exit', potentialExit.bind(null, childCmd));
    child.stderr.pipe(process.stderr);
    child.stdout.pipe(process.stdout);
});
