chai = require "chai"
chai.should()
spawn = require("child_process").spawn
Promise = require("bluebird")

waitingProcess = "node test/fixtures/waiting.js"
failingProcess = "node test/fixtures/failing.js"
READY_PREFIX = "ready "
DONE_LINE = "done"
ERRORED_SUFFIX = " errored"

usageInfo = """
-h, --help         output usage information
-v, --verbose      verbose logging
-w, --wait         will not close sibling processes on error
""" + "\n"

spawned = []
childPids = []

spawnParallelshell = (args...) ->
  ps = spawn process.execPath, ["index.js"].concat(args)
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

outputLines = (ps) -> ps.output.split("\n")

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
  waitForOutput(ps, -> readyPids(ps).length >= count).then ->
    pids = readyPids ps
    childPids.push pids...
    pids

doneCount = (ps) ->
  outputLines(ps).filter((line) -> line == DONE_LINE).length

afterEach ->
  for ps in spawned.splice(0) when ps.exitCode == null and ps.signalCode == null
    ps.kill "SIGKILL"
  for pid in childPids.splice(0)
    try process.kill pid, "SIGKILL"

describe "parallelshell", ->
  it "should print on -h and --help", ->
    Promise.all ["-h", "--help"].map (flag) ->
      ps = spawnParallelshell flag
      ps.exited.then -> ps.output.should.equal usageInfo

  it "should close with exitCode 1 on child error", ->
    spawnParallelshell(failingProcess).exited.then (result) ->
      result.code.should.equal 1

  it "should close sibling processes on child error", ->
    spawnParallelshell(waitingProcess, failingProcess, waitingProcess).exited.then (result) ->
      result.code.should.equal 1

  ["-w", "--wait"].forEach (flag) ->
    it "should wait for sibling processes on child error when called with #{flag}", ->
      ps = spawnParallelshell flag, "-v", waitingProcess, failingProcess, waitingProcess
      failureHandled = -> outputLines(ps).some (line) -> line.endsWith ERRORED_SUFFIX
      Promise.all [waitForReady(ps, 2), waitForOutput(ps, failureHandled)]
      .then ([pids]) ->
        process.kill pid, "SIGUSR2" for pid in pids
        ps.exited
      .then ->
        doneCount(ps).should.equal 2
