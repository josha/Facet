--!strict

local process = require("@std/process")
local Eval = require("../../tools/vendor/verify/src/agent-eval")
local Headline = require("./headline")

local evidence = process.args[2]
if evidence == nil or (#process.args ~= 2 and not (#process.args == 4 and process.args[3] == "--suite")) then
	print("usage: lute run eval/tools/report.luau <evidence directory> [--suite eval/extended-spec.json]")
	process.exit(2)
end
local binding = Eval.lute
local suite = Headline.manifest(process.args[4])
local thresholds = Eval.report.decodeThresholds(binding.decode(binding.files.read("eval/thresholds.json")))
local overhead = binding.decode(binding.files.read("eval/overhead.json")) :: Headline.Overhead
local output = Headline.write(binding.absolute(evidence :: string), suite, thresholds, overhead)
print(output.markdown)
process.exit(if output.passed then 0 else 1)
