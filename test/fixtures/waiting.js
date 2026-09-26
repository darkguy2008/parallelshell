'use strict';
var MAX_TIMER_DELAY_MS = 2147483647;

process.on('SIGUSR2', function () {
    console.log('done');
    process.exit(0);
});
console.log('ready ' + process.pid);
setInterval(function () {}, MAX_TIMER_DELAY_MS);
