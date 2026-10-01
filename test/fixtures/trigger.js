'use strict';
var fs = require('fs');
var path = require('path');

module.exports = function whenTriggered (trigger, callback) {
    var watcher = fs.watch(path.dirname(trigger), check);
    function check () {
        if (!watcher || !fs.existsSync(trigger)) return;
        watcher.close();
        watcher = null;
        callback();
    }
    check();
};
