chai = require "chai"
should = chai.should()
spawn = require("child_process").spawn;
Promise = require("bluebird")

# cross platform compatibility
if process.platform == "win32"
  sh = "cmd";
  shFlag = "/c";
else
  sh = "sh";
  shFlag = "-c";


# children
waitingProcess = "\\\"node -e 'setTimeout(function(){},10000);'\\\""
failingProcess = "\\\"node -e 'throw new Error(\"someError\");'\\\""

usageInfo = """
-h, --help         output usage information
-v, --verbose      verbose logging
-w, --wait         will not close sibling processes on error
""".split("\n")

spawnParallelshell = (cmd) ->
	return spawn sh, [shFlag, "node './index.js' " + cmd], {
      cwd: process.cwd
    }

testOutput = (cmd, expectedOutput) ->
  return new Promise (resolve) ->
    ps = spawnParallelshell(cmd)
    ps.stdout.setEncoding("utf8")
    output = []
    ps.stdout.on "data", (data) ->
      lines = data.split("\n")
      lines.pop() if lines[lines.length-1] == ""
      output = output.concat(lines)
    ps.stdout.on "end", () ->
      for line,i in output
        line.should.equal expectedOutput[i]
      resolve()

describe "parallelshell", ->
  it "should print on -h and --help", (done) ->
    Promise.all([testOutput("-h", usageInfo), testOutput("-help", usageInfo)])
    .finally done

  it "should close with exitCode 2 on child error", (done) ->
    ps = spawnParallelshell(failingProcess)
    ps.on "close", () ->
      ps.exitCode.should.equal 2
      done()

  it "should run with a normal child", (done) ->
    ps = spawnParallelshell(waitingProcess)
    setTimeout (() ->
      should.not.exist(ps.signalCode)
      ps.kill()
      done()
    ),100

  it "should close sibling processes on child error", (done) ->
    ps = spawnParallelshell([waitingProcess,failingProcess,waitingProcess].join(" "))
    ps.on "close", () ->
      ps.exitCode.should.equal 2
      done()

  it "should wait for sibling processes on child error when called with -w or --wait", (done) ->
    ps = spawnParallelshell(["-w",waitingProcess,failingProcess,waitingProcess].join(" "))
    ps2 = spawnParallelshell(["--wait",waitingProcess,failingProcess,waitingProcess].join(" "))
    setTimeout (() ->
      should.not.exist(ps.signalCode)
      should.not.exist(ps2.signalCode)
      ps.kill()
      ps2.kill()
      done()
    ),100
  it "should close on CTRL+C / SIGINT", (done) ->
    ps = spawnParallelshell(["-w",waitingProcess,failingProcess,waitingProcess].join(" "))
    ps.on "close", () ->
      ps.signalCode.should.equal "SIGINT"
      done()
    ps.kill("SIGINT")
