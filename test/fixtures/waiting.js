'use strict';
var whenTriggered = require('./trigger');

var trigger = process.argv[2];
var code = Number(process.argv[3]);
var ignoredSignal = process.argv[4];

if (ignoredSignal) process.on(ignoredSignal, function () {});
console.log('ready ' + process.pid);
whenTriggered(trigger, function () {
    console.log('done');
    process.exit(code);
});
