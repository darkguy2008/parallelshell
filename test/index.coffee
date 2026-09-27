chai = require "chai"
signals = require "constants"
should = chai.should()
childProcess = require("child_process")
fs = require("fs")
os = require("os")
path = require("path")

WINDOWS = process.platform == "win32"
SEQUENTIAL_PROCESS_STARTS = 3
startupBegan = Date.now()
childProcess.spawnSync process.execPath, ["-e", ""]
NODE_STARTUP_MS = Date.now() - startupBegan
onPosix = if WINDOWS then it.skip else it
failingProcess = if WINDOWS then "exit 1" else "false"
succeedingProcess = if WINDOWS then "exit 0" else "true"
FAILURE_EXIT_CODE = 3
LATER_FAILURE_EXIT_CODE = 5
SIGNAL_EXIT_CODE_BASE = 128
FORWARDED_SIGNALS = ["SIGINT", "SIGTERM", "SIGHUP"]
READY_PREFIX = "ready "
DONE_LINE = "done"
SUCCESS_SUFFIX = " ended successfully"
CLOSING_SUFFIX = " will now be closed"
ERRORED_SUFFIX = " errored"
PARALLELSHELL_PATH = path.join __dirname, "..", "index.js"
FIXTURES_DIR = path.join __dirname, "fixtures"
ENV_NAME = "PARALLELSHELL_TEST_ENV"
ENV_VALUE = "passed-through"
QUOTED_TEXT = "two  spaces"
fixture = (name, args...) -> [process.execPath, path.join(FIXTURES_DIR, name)].concat(args).join " "
waitingProcess = fixture "waiting.js"
exitProcess = (code) -> fixture "exit.js", code
exitWhenFileProcess = (file, code) -> fixture "exit-when-file.js", file, code
triggerFile = -> path.join os.tmpdir(), "parallelshell-trigger-#{process.pid}-#{Date.now()}"
printCwdProcess = fixture "print-cwd.js"
printEnvProcess = fixture "print-env.js", ENV_NAME

usageInfo = """
-h, --help         output usage information
-v, --verbose      verbose logging
-w, --wait         will not close sibling processes on error
""" + "\n"

spawned = []

spawnParallelshellWith = (options, args...) ->
  ps = childProcess.spawn process.execPath, [PARALLELSHELL_PATH].concat(args), Object.assign({detached: not WINDOWS}, options)
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

spawnParallelshell = (args...) -> spawnParallelshellWith {}, args...

outputLines = (ps) -> ps.output.split(/\r?\n/)

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
      childProcess.spawnSync "taskkill", ["/T", "/F", "/PID", String ps.pid]
    else if isAlive -ps.pid
      process.kill -ps.pid, "SIGKILL"

describe "parallelshell", ->
  @timeout @timeout() + SEQUENTIAL_PROCESS_STARTS * NODE_STARTUP_MS

  it "should print on -h and --help", ->
    Promise.all ["-h", "--help"].map (flag) ->
      ps = spawnParallelshell flag
      ps.exited.then -> ps.output.should.equal usageInfo

  it "should close with exitCode 1 on child error", ->
    spawnParallelshell(failingProcess).exited.then (result) ->
      result.code.should.equal 1

  onPosix "should close sibling processes on child error", ->
    spawnParallelshell(waitingProcess, failingProcess, waitingProcess).exited.then (result) ->
      result.code.should.equal 1

  ["-w", "--wait"].forEach (flag) ->
    onPosix "should wait for sibling processes on child error when called with #{flag}", ->
      ps = spawnParallelshell flag, "-v", waitingProcess, failingProcess, waitingProcess
      Promise.all [waitForReady(ps, 2), waitForOutput(ps, hasLineEndingWith ERRORED_SUFFIX)]
      .then ([pids]) ->
        process.kill pid, "SIGUSR2" for pid in pids
        ps.exited
      .then ->
        doneCount(ps).should.equal 2

  onPosix "should close on CTRL+C / SIGINT", ->
    ps = spawnParallelshell "-w", waitingProcess, failingProcess, waitingProcess
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

  onPosix "should exit with a failing child's code after a sibling already succeeded", ->
    ps = spawnParallelshell "-v", succeedingProcess, "#{waitingProcess} #{FAILURE_EXIT_CODE}"
    Promise.all [waitForReady(ps, 1), waitForOutput(ps, hasLineEndingWith SUCCESS_SUFFIX)]
    .then ([[pid]]) ->
      process.kill pid, "SIGUSR2"
      ps.exited
    .then (result) ->
      result.code.should.equal FAILURE_EXIT_CODE
      hasLineEndingWith(CLOSING_SUFFIX)(ps).should.be.false

  onPosix "should exit with the first failing child's code after waiting when called with -w", ->
    ps = spawnParallelshell "-w", "-v", failingProcess, "#{waitingProcess} #{LATER_FAILURE_EXIT_CODE}"
    Promise.all [waitForReady(ps, 1), waitForOutput(ps, hasLineEndingWith ERRORED_SUFFIX)]
    .then ([[pid]]) ->
      process.kill pid, "SIGUSR2"
      ps.exited
    .then (result) ->
      doneCount(ps).should.equal 1
      result.code.should.equal 1

  onPosix "should close sibling processes and exit with 128 + signal number when a child is killed by a signal", ->
    ps = spawnParallelshell "-v", waitingProcess, waitingProcess
    waitForReady(ps, 2).then ([pid]) ->
      process.kill pid, "SIGKILL"
      Promise.all [ps.exited, waitForOutput(ps, hasLineEndingWith ERRORED_SUFFIX)]
    .then ([result]) ->
      result.code.should.equal SIGNAL_EXIT_CODE_BASE + signals.SIGKILL

  FORWARDED_SIGNALS.forEach (signal) ->
    onPosix "should stop its children with #{signal} and die by #{signal} without crashing", ->
      ps = spawnParallelshell waitingProcess, waitingProcess
      waitForReady(ps, 2).then (pids) ->
        ps.kill signal
        ps.exited.then (result) ->
          ps.errorOutput.should.equal ""
          result.should.deep.equal {code: null, signal}
          pids.filter(isAlive).should.be.empty

  onPosix "should die by SIGINT when CTRL+C interrupts its whole process group", ->
    ps = spawnParallelshell waitingProcess, waitingProcess
    waitForReady(ps, 2).then ->
      process.kill -ps.pid, "SIGINT"
      ps.exited.then (result) ->
        ps.errorOutput.should.equal ""
        result.should.deep.equal {code: null, signal: "SIGINT"}

  FORWARDED_SIGNALS.forEach (signal) ->
    onPosix "should stop its siblings and die by #{signal} when a child is stopped by #{signal}", ->
      ps = spawnParallelshell waitingProcess, waitingProcess
      waitForReady(ps, 2).then ([interruptedPid, siblingPid]) ->
        process.kill interruptedPid, signal
        ps.exited.then (result) ->
          result.should.deep.equal {code: null, signal}
          isAlive(siblingPid).should.be.false

  onPosix "should stop its siblings and die by SIGINT when a child exits with the interrupted status", ->
    interruptedProcess = "#{waitingProcess} #{SIGNAL_EXIT_CODE_BASE + signals.SIGINT}"
    ps = spawnParallelshell interruptedProcess, interruptedProcess
    waitForReady(ps, 2).then ([interruptedPid, siblingPid]) ->
      process.kill interruptedPid, "SIGUSR2"
      ps.exited.then (result) ->
        result.should.deep.equal {code: null, signal: "SIGINT"}
        isAlive(siblingPid).should.be.false

  onPosix "should keep siblings running and exit with the interrupted status when a child is interrupted with -w", ->
    ps = spawnParallelshell "-w", "-v", waitingProcess, waitingProcess
    waitForReady(ps, 2).then ([interruptedPid, siblingPid]) ->
      process.kill interruptedPid, "SIGINT"
      waitForOutput(ps, hasLineEndingWith ERRORED_SUFFIX).then ->
        process.kill siblingPid, "SIGUSR2"
        ps.exited
    .then (result) ->
      doneCount(ps).should.equal 1
      result.code.should.equal SIGNAL_EXIT_CODE_BASE + signals.SIGINT

  it "should print every command's output", ->
    ps = spawnParallelshell "echo first", "echo second"
    ps.exited.then (result) ->
      result.code.should.equal 0
      outputLines(ps).should.include.members ["first", "second"]

  it "should exit with a failing child's code", ->
    spawnParallelshell(exitProcess FAILURE_EXIT_CODE).exited.then (result) ->
      result.code.should.equal FAILURE_EXIT_CODE

  it "should exit with the failing child's code after waiting when called with -w", ->
    spawnParallelshell("-w", exitProcess(FAILURE_EXIT_CODE), exitProcess(0)).exited.then (result) ->
      result.code.should.equal FAILURE_EXIT_CODE

  it "should exit with a failing child's code when it fails after a sibling succeeded", ->
    file = triggerFile()
    ps = spawnParallelshell "-v", exitProcess(0), exitWhenFileProcess(file, FAILURE_EXIT_CODE)
    Promise.all [waitForReady(ps, 1), waitForOutput(ps, hasLineEndingWith SUCCESS_SUFFIX)]
    .then ->
      fs.writeFileSync file, ""
      ps.exited
    .then (result) ->
      fs.unlinkSync file
      result.code.should.equal FAILURE_EXIT_CODE

  it "should run a command containing double quotes as written", ->
    ps = spawnParallelshell "#{process.execPath} -e \"console.log('#{QUOTED_TEXT}')\""
    ps.exited.then (result) ->
      result.code.should.equal 0
      outputLines(ps)[0].should.equal QUOTED_TEXT

  it "should run commands when PATH does not contain the shell", ->
    env = {}
    env[name] = value for name, value of process.env when name.toUpperCase() != "PATH"
    env.PATH = path.dirname process.execPath
    ps = spawnParallelshellWith {env}, exitProcess(0)
    ps.exited.then (result) ->
      ps.errorOutput.should.equal ""
      result.code.should.equal 0
