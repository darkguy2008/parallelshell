'use strict';
var fs = require('fs');
var path = require('path');

var trigger = process.argv[2];
var code = Number(process.argv[3]);

function exitIfTriggered () {
    if (fs.existsSync(trigger)) {
        console.log('done');
        process.exit(code);
    }
}

fs.watch(path.dirname(trigger), exitIfTriggered);
console.log('ready ' + process.pid);
exitIfTriggered();
