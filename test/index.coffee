chai = require "chai"
should = chai.should()
spawn = require("child_process").spawn
Promise = require("bluebird")

verbose = 0

# cross platform compatibility
if process.platform == "win32"
  sh = "cmd"
  shArg = "/c"
else
  sh = "sh"
  shArg = "-c"

# children
waitingProcess = (time=10000) ->
  return "\"node -e 'setTimeout(function(){},#{time});'\""
failingProcess = "\"node -e 'throw new Error();'\""

usageInfo = """
Useage:
  -h, --help         output usage information
  -v, --verbose      verbose logging
  -w, --wait         will not close sibling processes on error
""".split("\n")

cmdWrapper = (cmd) ->
  if verbose
    console.log "Calling: "+cmd
  return cmd

spawnParallelshell = (cmd) ->
  return spawn sh, [shArg, cmdWrapper("node ./index.js "+cmd )], {
    cwd: process.cwd
    windowsVerbatimArguments: process.platform == 'win32'
    detached: process.platform != 'win32'
  }

killPs = (ps) ->
  if verbose
    console.log "killing"
  if process.platform == "win32"
    killer = spawn sh, [shArg, "taskkill /F /T /PID "+ps.pid]
  else
    killer = spawn sh, [shArg, "kill -INT -"+ps.pid]
  spyOnPs killer, 3

spyOnPs = (ps, verbosity=1) ->
  if verbose >= verbosity
    ps.stdout.setEncoding("utf8")
    ps.stdout.on "data", (data) ->
      console.log data
    ps.stderr.setEncoding("utf8")
    ps.stderr.on "data", (data) ->
      console.log "err: "+data

testOutput = (cmd, expectedOutput, std="out") ->
  return new Promise (resolve) ->
    ps = spawnParallelshell(cmd)
    if std == "out"
      std = ps.stdout
    else
      std = ps.stderr
    spyOnPs ps, 3
    std.setEncoding("utf8")
    output = []
    std.on "data", (data) ->
      lines = data.split("\n")
      lines.pop() if lines[lines.length-1] == ""
      output = output.concat(lines)
    std.on "end", () ->
      for line,i in expectedOutput
        line.should.equal output[i]
      resolve()

describe "parallelshell", ->
  it "should print on -h and --help", (done) ->
    Promise.all([testOutput("-h", usageInfo), testOutput("--help", usageInfo)])
    .then -> done()
    .catch done

  it "should close with exitCode 1 on child error", (done) ->
    ps = spawnParallelshell(failingProcess)
    spyOnPs ps, 2
    ps.on "close", () ->
      ps.exitCode.should.equal 1
      done()

  it "should run with a normal child", (done) ->
    ps = spawnParallelshell(waitingProcess())
    spyOnPs ps, 1
    ps.on "close", () ->
      done()
    setTimeout (() ->
      should.not.exist(ps.signalCode)
      killPs(ps)
    ),150


  it "should close sibling processes on child error", (done) ->
    ps = spawnParallelshell([waitingProcess(),failingProcess].join(" "))
    spyOnPs ps,2
    ps.on "exit", () ->
      ps.exitCode.should.equal 1
      done()

  it "should wait for sibling processes on child error when called with -w or --wait", (done) ->
    ps = spawnParallelshell(["-w",waitingProcess(),failingProcess].join(" "))
    ps2 = spawnParallelshell(["--wait",waitingProcess(),failingProcess].join(" "))
    spyOnPs ps,2
    spyOnPs ps2,2
    setTimeout (() ->
      should.not.exist(ps.signalCode)
      should.not.exist(ps2.signalCode)
      killPs(ps)
      killPs(ps2)
    ),250
    Promise.all [new Promise((resolve) -> ps.on("close",resolve)),
      new Promise (resolve) -> ps2.on("close",resolve)]
    .then -> done()
    .catch done
  it "should close on CTRL+C / SIGINT", (done) ->
    ps = spawnParallelshell(["-w",waitingProcess()].join(" "))
    spyOnPs ps,2
    ps.on "close", () ->
      done()
    killPs(ps)
  it "should work with chained commands", (done) ->
    output = ["1","2"]
    if process.platform == "win32"
      output[0] += "\r"
      output[1] += "\r"
    testOutput("\"echo 1&& echo 2\"", output)
    .then done
    .catch done
  it "should work nested", (done) ->
    output = ["1","2"]
    if process.platform == "win32"
      output[0] += "\r"
      output[1] += "\r"
    testOutput("\"echo 1\" \"node ./index.js 'echo 2'\"", output)
    .then done
    .catch done

  it "should work with setting ENV", (done) ->
    output = ["test1"]
    if process.platform == "win32"
      setString = "set test=test1&"
    else
      setString = "test=test1 "
    testOutput("\"#{setString}node -e 'console.log(process.env.test);'\"", output)
    .then done
    .catch done

  it "should work with first", (done) ->
    ps = spawnParallelshell(["--first",waitingProcess(10),waitingProcess(10000)].join(" "))
    ps.on "exit", () ->
      ps.exitCode.should.equal 0
      done()

  it "should not work with first and wait", (done) ->
    testOutput("--wait --first", ["--wait and --first cannot be used together"], "err")
    .then done
    .catch done
