'use strict';
var whenTriggered = require('./trigger');

var stages = process.argv.slice(2);

function nextStage () {
    if (!stages.length) return;
    var text = Buffer.from(stages[1], 'hex').toString();
    whenTriggered(stages[0], function () {
        process.stdout.write(text, nextStage);
    });
    stages = stages.slice(2);
}

nextStage();
