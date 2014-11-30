## Parallel Shell

This is a super simple npm moudle to run shell commands in parallel. All
processes will share the same stdout/stderr, and if any command exits with a
non-zero exit status, the rest are stopped and the exit code carries through.

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
parallelshell 'echo 1' 'echo 2' 'echo 3'
```

This will execute the commands `echo 1` `echo 2` and `echo 3` simultaneously.
