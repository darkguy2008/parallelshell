## Parallel Shell

This is a super simple npm module to run shell commands in parallel. All
processes will share the same stdout/stderr, and if any command exits with a
non-zero exit status, the rest are stopped and the exit code carries through.

### Version compatibility notes

* Tested on Node 4 and later on Linux, macOS and Windows.

### Maintenance has been resumed by [@darkguy2008](https://github.com/darkguy2008). However, there are also better options, see [Consolidation of multiple similar libraries](https://github.com/mysticatea/npm-run-all/issues/10).

### Motivation

**How is this different than:**

    $ cmd1 & cmd2 & cmd3

* Cross platform -- works on Unix or Windows.

* `&` creates a background process, which only exits if you kill it or it ends. `parallelshell` will autokill processes if one of the others dies.

* `command1 & command2 & command3` only waits until command3 ends. Adding `& wait` at the end (`command1 & command2 & command3 & wait`) waits for all 3! But Ctrl+C or a failing command still won't stop the others. parallelshell waits for all 3 and stops them all when it needs to.

* If command1 or command2 exit with non-zero exit code, then this will not effect the outcome of your shell (i.e. they can fail and npm/bash/whatever will ignore it). `parallelshell` will not ignore it, and will exit with the first non-zero exit code.

* Pressing Ctrl+C will exit command3 but not 1 or 2. `parallelshell` will exit all 3

* `parallelshell` outputs all jobs stdout/err to its stdout/err. background jobs do that... kind of coincidentally (read: unreliably)

**So what's the difference between GNU parallel and this?**

The biggest difference is that parallelshell is an npm module and GNU parallel isn't. While they probably do similar things, albeit (GNU) parallel being more advanced, parallelshell is an easier option to work with when using npm (because it's an npm module).

If you have GNU parallel installed on all the machines you project will be on, then by all means use it! :)

### Install

Simply run the following to install this to your project:

```bash
npm i --save-dev parallelshell
```

Or, to install it globally, run:

```bash
npm i -g parallelshell
```

### Usage

To use the command, simply call it with a set of strings - which correspond to
shell arguments, for example:

```bash
parallelshell "echo 1" "echo 2" "echo 3"
```

This will execute the commands `echo 1` `echo 2` and `echo 3` simultaneously.

Note that on Windows, you need to use double-quotes to avoid confusing the
argument parser.

Available options:
```
-h, --help               output usage information
-v, --verbose            verbose logging
-w, --wait               will not close sibling processes on error
-t, --timeout <seconds>  stop remaining commands after the deadline
-n, --npm <pattern>      run matching npm scripts from package.json
```

Use `-n` (or `--npm`) before each npm script name or
[minimatch](https://github.com/isaacs/minimatch) pattern, mixed freely with
ordinary commands:

```bash
parallelshell -n "build:*" "echo ordinary command" -n "test:{unit,integration}"
```

Scripts come from `package.json` in the current directory and run through
`npm run`, so pre/post scripts still apply. Exact names win over patterns.
Patterns match names starting with `.` and treat a leading `#` or `!` literally.
Every selection is checked before anything starts: a missing value, an unmatched
pattern or an unreadable `package.json` exits with code 1.

Use `-t` (or `--timeout`) to stop everything still running after a number of
seconds, including with `--wait`:

```bash
parallelshell --timeout 10 "node server.js" "node request.js"
```

On timeout parallelshell exits with code 124, or with an earlier failure's code
under `--wait`. Commands are stopped the same way as on failure, so on Unix a
command that ignores SIGINT can outlive the deadline.
