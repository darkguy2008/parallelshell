## Parallel Shell

This is a super simple npm module to run shell commands in parallel. All
processes will share the same stdout/stderr, optionally with every line labelled,
and if any command exits with a non-zero exit status, the rest are stopped and
the exit code carries through.

### Maintenance has been resumed by [@darkguy2008](https://github.com/darkguy2008) and it's compatible with Node 4 and later on Linux and Windows (Node 16 and later on macOS).

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
-p, --prefix             prefix each output line with its command's label
-l, --label <name>       label the next command, implies --prefix
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
command that ignores SIGTERM can outlive the deadline.

### Prefixed output

Use `-p` (or `--prefix`) to start every line with the command it came from, like
`docker compose` does. Put `-l` (or `--label`) before a command to name it, which
turns on `--prefix` by itself:

```bash
parallelshell -l api "node server.js" -l web "npm run watch"
```

```
api | listening on port 3000
web | compiled in 120ms
```

npm scripts are labelled with their name, other commands with their text
shortened to 10 characters. A label names one command, so it can't go before an
`-n` pattern matching several scripts. Labels are padded to the same width, each
command gets its own color and stderr lines stay on stderr. A line that isn't
finished yet shows up right away. If another command prints in the meantime, it
carries on in a new line with its label.

Colors are used when the output is a terminal. `NO_COLOR` turns them off and
`FORCE_COLOR` turns them on (`FORCE_COLOR=0` turns them off).

To label lines parallelshell reads each command's output through a pipe, so
commands no longer see a terminal:

* When the labels are colored, commands get `FORCE_COLOR` and `CLICOLOR_FORCE`
  (unless you set them) so chalk based tools, npm, jest or macOS `ls` stay
  colored. Tools that ignore both, like git or cargo, need their own flag such as
  `--color=always`. Everything a command starts sees these variables too, so
  output written to a file can end up with color codes: set `FORCE_COLOR=0` to
  avoid that.
* Progress bars, spinners and interactive modes that need a terminal are turned
  off by the tools themselves.
* Python and Ruby buffer their output when it isn't a terminal, so it can show up
  late. Set `PYTHONUNBUFFERED=1` for Python and `$stdout.sync = true` in Ruby.

### Stopping commands

On Unix every command runs in its own process group and parallelshell stops the
whole group. Ctrl+C, SIGTERM and SIGHUP are passed on as they are. A failing
command, the `--timeout` deadline or closed output stop the others with SIGTERM.
Background processes a command left behind get SIGTERM too. That reaches the
commands behind `npm run` as well. Commands can use any shell syntax, like
`export PORT=3000 && cd api && npm start`.

* parallelshell exits once everything it stopped is gone, even when a command's
  shell ends before the processes it started. Only daemons that close every
  inherited file descriptor aren't waited for.
* Ctrl+Z pauses every command and `fg` resumes them.
* If parallelshell is killed with SIGKILL, a small helper stops the commands.
* When every command finishes by itself, background processes they started keep
  running.
* Commands can't read from the terminal, so password prompts fail right away
  instead of hanging. Use the non-interactive options instead: `sudo -A` with
  `SUDO_ASKPASS` for sudo. `SSH_ASKPASS` with `SSH_ASKPASS_REQUIRE=force` or
  ssh-agent for ssh. `GIT_ASKPASS` or a credential helper for git.

On Windows parallelshell stops each command's process tree with `taskkill`. A
process started with `start /b` by a command that already exited is outside that
tree and keeps running. With `--prefix` parallelshell stops waiting for its
output.
