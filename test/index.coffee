require("chai").should()
signals = require "constants"
childProcess = require "child_process"
fs = require "fs"
os = require "os"
path = require "path"

WINDOWS = process.platform == "win32"
onPosix = if WINDOWS then it.skip else it
onWindows = if WINDOWS then it else it.skip
WINDOWS_CONTROL_C_EXIT = 0xC000013A
FAILURE_EXIT_CODE = 3
LATER_FAILURE_EXIT_CODE = 5
SIGNAL_EXIT_CODE_BASE = 128
FORWARDED_SIGNALS = ["SIGINT", "SIGTERM", "SIGHUP"]
READY_PREFIX = "ready "
DONE_LINE = "done"
SUCCESS_SUFFIX = " ended successfully"
CLOSING_SUFFIX = " will now be closed"
ERRORED_SUFFIX = " errored"
LINE_BREAK = /\r?\n/
TRIGGER_NAME = "go"
PARALLELSHELL_PATH = path.join __dirname, "..", "index.js"
FIXTURES_DIR = path.join __dirname, "fixtures"
CTRL_C_HELPER = path.join FIXTURES_DIR, "ctrl-c.ps1"
POWERSHELL_ARGS = ["-NoProfile", "-ExecutionPolicy", "Bypass"]
ENV_NAME = "PARALLELSHELL_TEST_ENV"
ENV_VALUE = "passed-through"
QUOTED_TEXT = "two  spaces"
TIMEOUT_SECONDS = "2"
TIMEOUT_EXIT_CODE = 124
COMPLETION_TIMEOUT_SECONDS = "60"
FRACTIONAL_TIMEOUT_SECONDS = "0.001"
PACKAGE_FILES = ["package.json", "npm-debug.log"]

fixture = (name, args...) -> [process.execPath, path.join(FIXTURES_DIR, name)].concat(args).join " "
exitProcess = (code) -> fixture "exit.js", code
failingProcess = exitProcess 1
succeedingProcess = exitProcess 0
printCwdProcess = "#{process.execPath} -p \"process.cwd()\""
printEnvProcess = "#{process.execPath} -p process.env.#{ENV_NAME}"

usageInfo = """
-h, --help               output usage information
-v, --verbose            verbose logging
-w, --wait               will not close sibling processes on error
-t, --timeout <seconds>  stop remaining commands after the deadline
-n, --npm <pattern>      run matching npm scripts from package.json
""" + "\n"

spawned = []
directories = []

newDirectory = ->
  directory = path.join os.tmpdir(), "parallelshell-#{process.pid}-#{Date.now()}-#{directories.length}"
  fs.mkdirSync directory
  directories.push directory
  directory

newTrigger = -> path.join newDirectory(), TRIGGER_NAME

release = (trigger) -> fs.writeFileSync trigger, ""

waitingProcess = (trigger = newTrigger(), code = 0) -> fixture "waiting.js", trigger, code

track = (ps) ->
  ps.output = ""
  ps.errorOutput = ""
  ps.stdout.setEncoding "utf8"
  ps.stderr.setEncoding "utf8"
  ps.stdout.on "data", (data) -> ps.output += data
  ps.stderr.on "data", (data) -> ps.errorOutput += data
  ps.exited = new Promise (resolve) ->
    ps.on "close", (code, signal) -> resolve {code, signal}
  spawned.push ps
  ps

spawnParallelshellWith = (options, args...) ->
  track childProcess.spawn process.execPath, [PARALLELSHELL_PATH].concat(args), Object.assign({detached: not WINDOWS}, options)

spawnParallelshell = (args...) -> spawnParallelshellWith {}, args...

outputLines = (ps) -> ps.output.split LINE_BREAK

waitForOutput = (ps, predicate) ->
  new Promise (resolve, reject) ->
    check = -> resolve() if predicate ps
    ps.stdout.on "data", check
    ps.on "close", ->
      reject new Error "parallelshell exited before expected output:\n" + ps.output + ps.errorOutput
    check()

readyPids = (ps) ->
  outputLines(ps)
    .filter (line) -> line.indexOf(READY_PREFIX) == 0
    .map (line) -> Number line.slice READY_PREFIX.length

waitForReady = (ps, count) ->
  waitForOutput(ps, -> readyPids(ps).length >= count).then -> readyPids ps

hasLineEndingWith = (suffix) -> (ps) ->
  outputLines(ps).some (line) -> line.endsWith suffix

isAlive = (pid) ->
  try
    process.kill pid, 0
    true
  catch error
    error.code != "ESRCH"

doneCount = (ps) ->
  outputLines(ps).filter((line) -> line == DONE_LINE).length

shouldRejectBeforeLaunch = (ps, message) ->
  ps.exited.then (result) ->
    result.code.should.equal 1
    ps.output.should.equal ""
    ps.errorOutput.should.contain message

afterEach ->
  for ps in spawned.splice(0)
    if WINDOWS
      childProcess.spawnSync "taskkill", ["/T", "/F", "/PID", String ps.pid] if ps.exitCode == null and ps.signalCode == null
    else if isAlive -ps.pid
      process.kill -ps.pid, "SIGKILL"
  for directory in directories.splice(0)
    for name in [TRIGGER_NAME].concat PACKAGE_FILES
      file = path.join directory, name
      fs.unlinkSync file if fs.existsSync file
    fs.rmdirSync directory

describe "parallelshell", ->
  describe "npm scripts", ->
    literalNames = ["literal*", "#hash", "!bang", "two words", "quote\"name", "amp&name", "percent%PATH%"]
    scriptNames = ["build:js", "build:css", "build:html", "test:js", ".hidden", "nested/build/js"].concat literalNames

    project = (scripts) ->
      directory = newDirectory()
      fs.writeFileSync path.join(directory, "package.json"), JSON.stringify {name: "parallelshell-fixture", version: "1.0.0", scripts}
      directory

    npmProject = ->
      scripts = {}
      for name in scriptNames
        scripts[name] = "node -e \"console.log('script '+process.env.npm_lifecycle_event)\""
      project scripts

    runScripts = (args...) -> spawnParallelshellWith {cwd: npmProject()}, args...

    scriptLines = (ps) -> outputLines(ps).filter((line) -> line.indexOf("script ") == 0).sort()

    ["-n", "--npm"].forEach (flag) ->
      it "should run an exact npm script with #{flag}", ->
        ps = runScripts flag, "build:js"
        ps.exited.then (result) ->
          result.code.should.equal 0, ps.output + ps.errorOutput
          outputLines(ps).should.include "script build:js"

    patterns = {
      "build:*": ["build:js", "build:css", "build:html"]
      "*:js": ["build:js", "test:js"]
      "b*:j?": ["build:js"]
      "build:{js,css}": ["build:js", "build:css"]
      "build:[ch]*": ["build:css", "build:html"]
      "build:+(js|css)": ["build:js", "build:css"]
      ".*": [".hidden"]
      "#h*": ["#hash"]
      "!b*": ["!bang"]
      "nested/**": ["nested/build/js"]
    }
    Object.keys(patterns).forEach (pattern) ->
      it "should expand #{pattern} against script names", ->
        ps = runScripts "-n", pattern
        ps.exited.then (result) ->
          result.code.should.equal 0, ps.output + ps.errorOutput
          scriptLines(ps).should.deep.equal patterns[pattern].map((name) -> "script #{name}").sort()

    it "should run script names containing pattern and shell characters literally", ->
      args = []
      args.push "-n", name for name in literalNames
      ps = runScripts args...
      ps.exited.then (result) ->
        result.code.should.equal 0, ps.output + ps.errorOutput
        scriptLines(ps).should.deep.equal literalNames.map((name) -> "script #{name}").sort()

    it "should mix repeated npm options with ordinary commands and existing options", ->
      ps = runScripts "-w", "-n", "build:js", "echo ordinary", "--npm", "build:css", "-t", COMPLETION_TIMEOUT_SECONDS
      ps.exited.then (result) ->
        result.code.should.equal 0
        outputLines(ps).should.include.members ["ordinary", "script build:js", "script build:css"]

    it "should preserve explicitly repeated scripts", ->
      ps = runScripts "-n", "build:js", "-n", "build:js"
      ps.exited.then (result) ->
        result.code.should.equal 0
        outputLines(ps).filter((line) -> line == "script build:js").length.should.equal 2

    it "should preserve npm pre and post lifecycle scripts", ->
      ps = spawnParallelshellWith {cwd: project({prebuild: "echo lifecycle-pre", build: "echo lifecycle-main", postbuild: "echo lifecycle-post"})}, "-n", "build"
      ps.exited.then (result) ->
        result.code.should.equal 0
        outputLines(ps).filter((line) -> line.indexOf("lifecycle-") == 0).should.deep.equal ["lifecycle-pre", "lifecycle-main", "lifecycle-post"]

    it "should preserve npm failure status", ->
      ps = spawnParallelshellWith {cwd: project({fail: exitProcess(FAILURE_EXIT_CODE)})}, "-n", "fail"
      ps.exited.then (result) -> result.code.should.not.equal 0

    it "should fail once when npm is not on PATH", ->
      env = {}
      env[name] = value for name, value of process.env when name.toUpperCase() != "PATH"
      env.PATH = newDirectory()
      ps = spawnParallelshellWith {cwd: npmProject(), env}, "-w", "-v", "-n", "build:js"
      ps.exited.then (result) ->
        result.code.should.equal 1
        hasLineEndingWith(SUCCESS_SUFFIX)(ps).should.be.false

    [undefined, "", "-w", "missing", "missing:*"].forEach (pattern) ->
      it "should reject #{pattern} before launching any command", ->
        args = ["echo ordinary", "-n", "build:js", "-n"]
        args.push pattern if pattern != undefined
        shouldRejectBeforeLaunch runScripts(args...), "--npm"

    [null, [], {bad: 42}].forEach (scripts) ->
      it "should reject missing or invalid script definitions #{JSON.stringify scripts}", ->
        shouldRejectBeforeLaunch spawnParallelshellWith({cwd: project(scripts)}, "echo ordinary", "-n", "bad"), "--npm"

    it "should reject invalid package JSON before launching commands", ->
      directory = project {}
      fs.writeFileSync path.join(directory, "package.json"), "{"
      shouldRejectBeforeLaunch spawnParallelshellWith({cwd: directory}, "echo ordinary", "-n", "build"), "--npm"

    it "should reject a missing package.json before launching commands", ->
      shouldRejectBeforeLaunch spawnParallelshellWith({cwd: newDirectory()}, "echo ordinary", "-n", "build"), "--npm"

  it "should stop running commands at the deadline", ->
    ps = spawnParallelshell "--timeout", TIMEOUT_SECONDS, succeedingProcess, waitingProcess(), waitingProcess()
    waitForReady(ps, 2).then (pids) ->
      ps.exited.then (result) ->
        result.should.deep.equal {code: TIMEOUT_EXIT_CODE, signal: null}
        ps.errorOutput.should.contain "timed out after #{TIMEOUT_SECONDS} seconds"
        pids.filter(isAlive).should.be.empty

  ["-t", "--timeout"].forEach (flag) ->
    it "should accept fractional timeout seconds with #{flag}", ->
      spawnParallelshell(flag, FRACTIONAL_TIMEOUT_SECONDS, waitingProcess()).exited.then (result) -> result.code.should.equal TIMEOUT_EXIT_CODE

  it "should time out with --wait and preserve an earlier failure", ->
    ps = spawnParallelshell "--wait", "-v", "--timeout", TIMEOUT_SECONDS, exitProcess(FAILURE_EXIT_CODE), waitingProcess()
    Promise.all [waitForReady(ps, 1), waitForOutput(ps, hasLineEndingWith ERRORED_SUFFIX)]
    .then ([pids]) ->
      ps.exited.then (result) ->
        result.code.should.equal FAILURE_EXIT_CODE
        ps.errorOutput.should.contain "timed out"
        pids.filter(isAlive).should.be.empty

  it "should time out successful commands that remain running with --wait", ->
    ps = spawnParallelshell "--wait", "--timeout", FRACTIONAL_TIMEOUT_SECONDS, waitingProcess()
    ps.exited.then (result) -> result.code.should.equal TIMEOUT_EXIT_CODE

  completions = {
    "every command finishes": [[succeedingProcess, succeedingProcess], 0]
    "a command fails": [[exitProcess FAILURE_EXIT_CODE], FAILURE_EXIT_CODE]
    "all commands finish with --wait after a failure": [["--wait", exitProcess(FAILURE_EXIT_CODE), succeedingProcess], FAILURE_EXIT_CODE]
    "there are no commands": [[], 0]
  }
  Object.keys(completions).forEach (description) ->
    [args, code] = completions[description]
    it "should exit without timing out when #{description}", ->
      ps = spawnParallelshell "--timeout", COMPLETION_TIMEOUT_SECONDS, args...
      ps.exited.then (result) ->
        result.code.should.equal code
        ps.errorOutput.should.equal ""

  [undefined, "0", "-1", "nope", "Infinity", "2147483.648", "--wait"].forEach (value) ->
    it "should reject invalid timeout #{value} before launching commands", ->
      args = [succeedingProcess, "--timeout"]
      args.push value if value != undefined
      shouldRejectBeforeLaunch spawnParallelshell(args...), "--timeout requires positive seconds"

  it "should print on -h and --help", ->
    Promise.all ["-h", "--help"].map (flag) ->
      ps = spawnParallelshell flag
      ps.exited.then -> ps.output.should.equal usageInfo

  it "should print every command's output", ->
    ps = spawnParallelshell "echo first", "echo second"
    ps.exited.then (result) ->
      result.code.should.equal 0
      outputLines(ps).should.include.members ["first", "second"]

  it "should exit with a failing child's code", ->
    spawnParallelshell(exitProcess FAILURE_EXIT_CODE).exited.then (result) ->
      result.code.should.equal FAILURE_EXIT_CODE

  it "should close sibling processes on child error", ->
    trigger = newTrigger()
    ps = spawnParallelshell waitingProcess(), waitingProcess(trigger, FAILURE_EXIT_CODE), waitingProcess()
    waitForReady(ps, 3).then (pids) ->
      release trigger
      ps.exited.then (result) ->
        result.code.should.equal FAILURE_EXIT_CODE
        pids.filter(isAlive).should.be.empty

  ["-w", "--wait"].forEach (flag) ->
    it "should wait for sibling processes on child error when called with #{flag}", ->
      triggers = [newTrigger(), newTrigger()]
      ps = spawnParallelshell flag, "-v", waitingProcess(triggers[0]), failingProcess, waitingProcess(triggers[1])
      Promise.all [waitForReady(ps, 2), waitForOutput(ps, hasLineEndingWith ERRORED_SUFFIX)]
      .then ->
        triggers.forEach release
        ps.exited
      .then ->
        doneCount(ps).should.equal 2

  onPosix "should close on CTRL+C / SIGINT", ->
    ps = spawnParallelshell "-w", waitingProcess(), failingProcess, waitingProcess()
    waitForReady(ps, 2).then ->
      ps.kill "SIGINT"
      ps.exited
    .then (result) ->
      result.signal.should.equal "SIGINT"

  it "should run children in its working directory", ->
    ps = spawnParallelshellWith {cwd: FIXTURES_DIR}, printCwdProcess
    ps.exited.then (result) ->
      result.code.should.equal 0
      outputLines(ps)[0].should.equal FIXTURES_DIR

  it "should pass its environment to children", ->
    env = Object.assign {}, process.env
    env[ENV_NAME] = ENV_VALUE
    ps = spawnParallelshellWith {env}, printEnvProcess
    ps.exited.then (result) ->
      result.code.should.equal 0
      outputLines(ps)[0].should.equal ENV_VALUE

  it "should exit with a failing child's code after a sibling already succeeded", ->
    trigger = newTrigger()
    ps = spawnParallelshell "-v", succeedingProcess, waitingProcess(trigger, FAILURE_EXIT_CODE)
    Promise.all [waitForReady(ps, 1), waitForOutput(ps, hasLineEndingWith SUCCESS_SUFFIX)]
    .then ->
      release trigger
      ps.exited
    .then (result) ->
      result.code.should.equal FAILURE_EXIT_CODE
      hasLineEndingWith(CLOSING_SUFFIX)(ps).should.be.false

  it "should exit with the first failing child's code after waiting when called with -w", ->
    trigger = newTrigger()
    ps = spawnParallelshell "-w", "-v", failingProcess, waitingProcess(trigger, LATER_FAILURE_EXIT_CODE)
    Promise.all [waitForReady(ps, 1), waitForOutput(ps, hasLineEndingWith ERRORED_SUFFIX)]
    .then ->
      release trigger
      ps.exited
    .then (result) ->
      doneCount(ps).should.equal 1
      result.code.should.equal 1

  onPosix "should close sibling processes and exit with 128 + signal number when a child is killed by a signal", ->
    ps = spawnParallelshell "-v", waitingProcess(), waitingProcess()
    waitForReady(ps, 2).then ([pid]) ->
      process.kill pid, "SIGKILL"
      Promise.all [ps.exited, waitForOutput(ps, hasLineEndingWith ERRORED_SUFFIX)]
    .then ([result]) ->
      result.code.should.equal SIGNAL_EXIT_CODE_BASE + signals.SIGKILL

  FORWARDED_SIGNALS.forEach (signal) ->
    onPosix "should stop its children with #{signal} and die by #{signal} without crashing", ->
      ps = spawnParallelshell "--timeout", COMPLETION_TIMEOUT_SECONDS, waitingProcess(), waitingProcess()
      waitForReady(ps, 2).then (pids) ->
        ps.kill signal
        ps.exited.then (result) ->
          ps.errorOutput.should.equal ""
          result.should.deep.equal {code: null, signal}
          pids.filter(isAlive).should.be.empty

  onPosix "should die by SIGINT when CTRL+C interrupts its whole process group", ->
    ps = spawnParallelshell waitingProcess(), waitingProcess()
    waitForReady(ps, 2).then ->
      process.kill -ps.pid, "SIGINT"
      ps.exited.then (result) ->
        ps.errorOutput.should.equal ""
        result.should.deep.equal {code: null, signal: "SIGINT"}

  FORWARDED_SIGNALS.forEach (signal) ->
    onPosix "should stop its siblings and die by #{signal} when a child is stopped by #{signal}", ->
      ps = spawnParallelshell waitingProcess(), waitingProcess()
      waitForReady(ps, 2).then ([interruptedPid, siblingPid]) ->
        process.kill interruptedPid, signal
        ps.exited.then (result) ->
          result.should.deep.equal {code: null, signal}
          isAlive(siblingPid).should.be.false

  onPosix "should stop its siblings and die by SIGINT when a child exits with the interrupted status", ->
    trigger = newTrigger()
    ps = spawnParallelshell waitingProcess(trigger, SIGNAL_EXIT_CODE_BASE + signals.SIGINT), waitingProcess()
    waitForReady(ps, 2).then (pids) ->
      release trigger
      ps.exited.then (result) ->
        result.should.deep.equal {code: null, signal: "SIGINT"}
        pids.filter(isAlive).should.be.empty

  onPosix "should keep siblings running and exit with the interrupted status when a child is interrupted with -w", ->
    triggers = [newTrigger(), newTrigger()]
    ps = spawnParallelshell "-w", "-v", waitingProcess(triggers[0]), waitingProcess(triggers[1])
    waitForReady(ps, 2).then ([interruptedPid]) ->
      process.kill interruptedPid, "SIGINT"
      waitForOutput(ps, hasLineEndingWith ERRORED_SUFFIX).then ->
        triggers.forEach release
        ps.exited
    .then (result) ->
      doneCount(ps).should.equal 1
      result.code.should.equal SIGNAL_EXIT_CODE_BASE + signals.SIGINT

  it "should run a command containing double quotes as written", ->
    ps = spawnParallelshell "#{process.execPath} -e \"console.log('#{QUOTED_TEXT}')\""
    ps.exited.then (result) ->
      result.code.should.equal 0
      outputLines(ps)[0].should.equal QUOTED_TEXT

  it "should run commands when PATH does not contain the shell", ->
    env = {}
    env[name] = value for name, value of process.env when name.toUpperCase() != "PATH"
    env.PATH = path.dirname process.execPath
    ps = spawnParallelshellWith {env}, succeedingProcess
    ps.exited.then (result) ->
      ps.errorOutput.should.equal ""
      result.code.should.equal 0

  onWindows "should stop its children and exit with the Ctrl+C status on Ctrl+C", ->
    ps = track childProcess.spawn "powershell", POWERSHELL_ARGS.concat ["-File", CTRL_C_HELPER, process.execPath, PARALLELSHELL_PATH, waitingProcess(), waitingProcess()]
    waitForReady(ps, 2).then (pids) ->
      ps.stdin.write "\n"
      ps.exited.then (result) ->
        ps.errorOutput.should.not.contain "Error"
        result.code.should.equal WINDOWS_CONTROL_C_EXIT
        pids.filter(isAlive).should.be.empty
