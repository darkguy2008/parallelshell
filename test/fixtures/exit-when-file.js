'use strict';
var fs = require('fs');
var path = require('path');

var file = process.argv[2];
var code = Number(process.argv[3]);

function exitIfPresent () {
    if (fs.existsSync(file)) process.exit(code);
}

fs.watch(path.dirname(file), exitIfPresent);
console.log('ready ' + process.pid);
exitIfPresent();
