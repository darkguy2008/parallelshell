### v4.0.0
 - [#46](https://github.com/darkguy2008/parallelshell/issues/46) Add
   `-p, --prefix` to label every output line with its command and
   `-l, --label <name>` to name a command, with colored labels like
   `docker compose`.
 - [#22](https://github.com/darkguy2008/parallelshell/issues/22) Stop the
   commands behind `npm run` too: on Unix each command runs in its own process
   group and parallelshell stops the whole group.
 - [#28](https://github.com/darkguy2008/parallelshell/issues/28) Run commands
   without `exec`, so `export`, `cd` and `a && b` work.
 - Stop background processes a command left behind and wait for every stopped
   process before exiting. Ctrl+Z and `fg` pause and resume commands. Commands
   are stopped even if parallelshell itself is killed.
 - Breaking: a failing command, `--timeout` and closed output now stop the
   others with SIGTERM instead of SIGINT. Commands can't read from the terminal
   anymore (use askpass or credential helpers for passwords).

### v3.2.1
 - [#31](https://github.com/darkguy2008/parallelshell/issues/31) Report a
   missing npm once instead of also marking the script as successful.
   Simplify `--npm` and `--timeout` handling and align `--help` output.

### v3.2.0
 - [#31](https://github.com/darkguy2008/parallelshell/issues/31) Add
   `-n, --npm <pattern>` to run npm scripts with wildcard matching,
   mixed with ordinary commands. Validate all selections before launching.

### v3.1.0
 - [#40](https://github.com/darkguy2008/parallelshell/issues/40) Add
   `-t, --timeout <seconds>` to stop remaining commands after a deadline,
   including with `--wait`.

### v3.0.4
 - [#41](https://github.com/darkguy2008/parallelshell/issues/41) Mention
   `& wait` in the README.
 - Published from GitHub Actions with npm provenance.
 ([@darkguy2008](https://github.com/darkguy2008))

### v3.0.3
 - [#64](https://github.com/darkguy2008/parallelshell/issues/64)
   [#67](https://github.com/darkguy2008/parallelshell/issues/67)
   [#71](https://github.com/darkguy2008/parallelshell/issues/71) Fix crash on
   Node >= 10 where it says that cwd is not a string.
 - [#55](https://github.com/darkguy2008/parallelshell/issues/55)
   [#36](https://github.com/darkguy2008/parallelshell/issues/36) Exit with the
   first failing child's code, also with `-w` and when a child is killed by a
   signal ([#68](https://github.com/darkguy2008/parallelshell/pull/68),
   [@hagaigold](https://github.com/hagaigold)).
 - Fix crash on Ctrl+C with Node >= 20: children are stopped and parallelshell
   dies by SIGINT, including during start-up.
 - [#39](https://github.com/darkguy2008/parallelshell/issues/39) Forward
   SIGTERM and SIGHUP to children.
 - [#74](https://github.com/darkguy2008/parallelshell/issues/74) Run commands
   through Node's shell option, fixing `spawn cmd ENOENT` and double-quoted
   commands on Windows.
 - Windows: stop a child's whole process tree, and exit with the Ctrl+C status
   on Ctrl+C.
 ([@darkguy2008](https://github.com/darkguy2008))

### v3.0.2
 - [#60](https://github.com/keithamus/parallelshell/pulls/60) < Node 8 fix
 - [#33](https://github.com/keithamus/parallelshell/issues/33) Readme fix
 ([@darkguy2008](https://github.com/darkguy2008))
 
### v3.0.1
 - [#58](https://github.com/keithamus/parallelshell/issues/58) Fix CRLF
 problem not allowing parallelshell to start up (shame on me!).
 ([@darkguy2008](https://github.com/darkguy2008))

### v3.0.0
 - [#56](https://github.com/keithamus/parallelshell/issues/56)
   [#57](https://github.com/keithamus/parallelshell/issues/57) Fix problem 
 with node >= 8 where it says that cwd is not a string.
   ([@darkguy2008](https://github.com/darkguy2008))

### v1.1.1

 - [#11](https://github.com/keithamus/parallelshell/pull/11) Fix regression
   where shebang went missing. Fixes issues with Mac finding binary.
   ([@eliias](https://github.com/eliias))

### v1.1.0

 - [#9](https://github.com/keithamus/parallelshell/pull/9) Add shell colour
   support (passing through colours from child shells). (Fixes #7)
   ([@paulpflug](https://github.com/paulpflug))
 - [#8](https://github.com/keithamus/parallelshell/pull/8) Fix examples in
   README to better support Windows.
   ([@jeffcharles](https://github.com/jeffcharles))

### v1.0.4

 - [#4](https://github.com/keithamus/parallelshell/pull/4) Ensure app doesn't
   crash if the exit code isn't present (on some windows machines)
   ([@jackysee](https://github.com/jackysee))

### v1.0.3

Fix deploy issues

### v1.0.2

Fix deploy issues

### v1.0.1

Fix deploy issues

### v1.0.0

Initial Release
