'use strict';
var MAX_TIMER_DELAY_MS = 2147483647;
var exitCode = Number(process.argv[2] || 0);

process.on('SIGUSR2', function () {
    console.log('done');
    process.exit(exitCode);
});
console.log('ready ' + process.pid);
setInterval(function () {}, MAX_TIMER_DELAY_MS);
