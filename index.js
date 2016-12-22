#!/usr/bin/env node

'use strict';
var spawn = require('child_process').spawn;

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
                console.log('-w, --wait         will not close sibling processes on error')
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
    var i, len, closed = 0, opened = 0;

    for (i = 0, len = children.length; i < len; i++) {
        if (!children[i].exitCode) {
            opened++;
            children[i].removeAllListeners('close');
            children[i].kill("SIGINT");
            if (verbose) console.log('`' + children[i].cmd + '` will now be closed');
            children[i].on('close', function() {
                closed++;
                if (opened == closed) {
                    process.exit(code);
                }
            });
        }
    }
    if (opened == closed) {process.exit(code);}

}

// start the children
children = [];
cmds.forEach(function (cmd) {
    if (process.platform != 'win32') {
      cmd = "exec "+cmd;
    }
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



/*
 * START Workaround for incorrect double quote handling on Windows:
 * https://github.com/joyent/node/issues/25339
 */
 
function fixArgsOnWindows (args) {
    // Detect faulty arguments, return if not found
    if (!hasFaultyArg(args)) return args;
    
    var notQuoteOrSpaceAtEndRe = /[^\s"]+$/;
    var whitespaceRe = /\s+/g;
    var argsJoined = args.join(' ');
    var level = -1;
    var quotesForLevel = getQuotesForLevel(level);
    var quotesForNextLevel = getQuotesForLevel(level + 1);
    var index = 0;
    var levelQuoteIndex = -1;
    var nextLevelQuoteIndex = -1;
    var result = [];
    var argsSlice;
    
    while (true) {
        // Iterate on quote occurrences
        
        levelQuoteIndex = quotesForLevel ? argsJoined.indexOf(quotesForLevel, index) : -1;
        nextLevelQuoteIndex = argsJoined.indexOf(quotesForNextLevel, index);
        
        if (nextLevelQuoteIndex > -1 && nextLevelQuoteIndex == levelQuoteIndex) {
            // Level is being increased
            argsSlice = argsJoined.slice(index, nextLevelQuoteIndex);
            if (level == -1) {
                // Level was root level
                // Root level arguments are split on space
                result = result.concat(argsSlice.split(whitespaceRe));
                // Only start a new argument when coming from root level
                result.push(quotesForNextLevel);
            } else {
                // Level was deeper than root: append to last item
                if (result[result.length - 1].match(notQuoteOrSpaceAtEndRe)) result[result.length - 1] += ' ';
                result[result.length - 1] += argsSlice + quotesForNextLevel;
            }
            index = nextLevelQuoteIndex + quotesForNextLevel.length;
            // Increase level
            level++;
            quotesForLevel = quotesForNextLevel;
            quotesForNextLevel = getQuotesForLevel(level + 1);
        } else if (levelQuoteIndex > -1) {
            // Level is being decreased: can only happen when not root
            argsSlice = argsJoined.slice(index, levelQuoteIndex + quotesForLevel.length);
            if (result[result.length - 1].match(notQuoteOrSpaceAtEndRe)) result[result.length - 1] += ' ';
            result[result.length - 1] += argsSlice;
            index = levelQuoteIndex + quotesForLevel.length;
            // Decrease level
            level--;
            quotesForNextLevel = quotesForLevel;
            quotesForLevel = getQuotesForLevel(level);
        } else {
            // This is the last slice
            argsSlice = argsJoined.slice(index);
            if (level == -1) {
                result = result.concat(argsSlice.split(whitespaceRe));
                break;
            } else {
                throw 'parallelshell: Invalid quote nesting.';
            }
        }
    };
    
    for (var i = result.length - 1; i >= 0; i--) {
        var arg = result[i].replace(/"+/g, function(match) {
            // Remove one level of quotes
            if (match.length == 1) {
                return '';
            } else {
                return match.slice(0, match.length / 2);
            }
        });
        if (arg) {
            result[i] = arg;
        } else {
            // Remove empty arguments
            result.splice(i, 1);
        }
    }
    
    return result;
}

function hasFaultyArg (args) {
    var re = /^\s*".*[^"]\s*$/;
    for (var i = 0, n = args.length; i < n; i++) {
        var arg = args[i];
        if (re.test(arg)) {
            return true;
        }
    }
    return false;
}

function getQuotesForLevel (level) {
    var count = Math.pow(2, level);
    var result = '';
    for (var i = 0; i < count; i++) {
        result += '"';
    }
    return result;
}

/*
 * END Workaround
 */
