require("chai").should()
childProcess = require "child_process"
fs = require "fs"
os = require "os"
path = require "path"

WINDOWS = process.platform == "win32"
onPosix = if WINDOWS then it.skip else it
FAILURE_EXIT_CODE = 3
READY_PREFIX = "ready "
DONE_LINE = "done"
ERRORED_SUFFIX = " errored"
LINE_BREAK = /\r?\n/
TRIGGER_NAME = "go"
PARALLELSHELL_PATH = path.join __dirname, "..", "index.js"
FIXTURES_DIR = path.join __dirname, "fixtures"
ENV_NAME = "PARALLELSHELL_TEST_ENV"
ENV_VALUE = "passed-through"

fixture = (name, args...) -> [process.execPath, path.join(FIXTURES_DIR, name)].concat(args).join " "
exitProcess = (code) -> fixture "exit.js", code
failingProcess = exitProcess 1
printCwdProcess = fixture "print-cwd.js"
printEnvProcess = fixture "print-env.js", ENV_NAME

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

spawnParallelshellWith = (options, args...) ->
  ps = childProcess.spawn process.execPath, [PARALLELSHELL_PATH].concat(args), Object.assign({detached: not WINDOWS}, options)
  ps.output = ""
  ps.errorOutput = ""
  ps.stdout.setEncoding "utf8"
  ps.stderr.setEncoding "utf8"
  ps.stdout.on "data", (data) -> ps.output += data
  ps.stderr.on "data", (data) -> ps.errorOutput += data
  ps.on "exit", -> stopLeftoverChildren ps
  ps.exited = new Promise (resolve) ->
    ps.on "close", (code, signal) -> resolve {code, signal}
  spawned.push ps
  ps

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

waitForReady = (ps, count) -> waitForOutput ps, -> readyPids(ps).length >= count

hasLineEndingWith = (suffix) -> (ps) ->
  outputLines(ps).some (line) -> line.endsWith suffix

isAlive = (pid) ->
  try
    process.kill pid, 0
    true
  catch error
    error.code != "ESRCH"

stopLeftoverChildren = (ps) ->
  process.kill pid, "SIGINT" for pid in readyPids(ps) when isAlive pid

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

  it "should exit with a failing child's code", ->
    spawnParallelshell(exitProcess FAILURE_EXIT_CODE).exited.then (result) ->
      result.code.should.equal FAILURE_EXIT_CODE

  onPosix "should run with a normal child until CTRL+C / SIGINT", ->
    ps = spawnParallelshell waitingProcess()
    waitForReady(ps, 1).then ->
      ps.kill "SIGINT"
      ps.exited
    .then (result) ->
      ps.errorOutput.should.equal ""
      result.signal.should.equal "SIGINT"

  it "should close sibling processes on child error", ->
    trigger = newTrigger()
    ps = spawnParallelshell waitingProcess(), waitingProcess(trigger, FAILURE_EXIT_CODE), waitingProcess()
    waitForReady(ps, 3).then ->
      release trigger
      ps.exited
    .then (result) ->
      result.code.should.equal FAILURE_EXIT_CODE

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
      ps.errorOutput.should.equal ""
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
