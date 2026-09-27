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

fixture = (name, args...) -> [process.execPath, path.join(FIXTURES_DIR, name)].concat(args).join " "
exitProcess = (code) -> fixture "exit.js", code
failingProcess = exitProcess 1
succeedingProcess = exitProcess 0
printCwdProcess = "#{process.execPath} -p \"process.cwd()\""
printEnvProcess = "#{process.execPath} -p process.env.#{ENV_NAME}"

usageInfo = """
-h, --help         output usage information
-v, --verbose      verbose logging
-w, --wait         will not close sibling processes on error
""" + "\n"

spawned = []
triggerDirectories = []

newTrigger = ->
  directory = path.join os.tmpdir(), "parallelshell-#{process.pid}-#{Date.now()}-#{triggerDirectories.length}"
  fs.mkdirSync directory
  triggerDirectories.push directory
  path.join directory, TRIGGER_NAME

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

afterEach ->
  for ps in spawned.splice(0)
    if WINDOWS
      childProcess.spawnSync "taskkill", ["/T", "/F", "/PID", String ps.pid] if ps.exitCode == null and ps.signalCode == null
    else if isAlive -ps.pid
      process.kill -ps.pid, "SIGKILL"
  for directory in triggerDirectories.splice(0)
    trigger = path.join directory, TRIGGER_NAME
    fs.unlinkSync trigger if fs.existsSync trigger
    fs.rmdirSync directory

describe "parallelshell", ->
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
      ps = spawnParallelshell waitingProcess(), waitingProcess()
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
