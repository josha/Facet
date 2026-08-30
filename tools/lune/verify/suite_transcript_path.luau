--!strict
--[[ Is there already a trustworthy full-suite run for THIS tree?

	`lune run tools/lune/verify/suite_transcript_path` prints the path of the
	recorded human transcript of a stored, valid, full-tier suite result whose
	identity matches the current source — and exits non-zero, printing nothing,
	when there is not one.

	It exists so that `tools/test.sh` and the verification graph share ONE suite
	run. During the parity period both systems are live: gate rows still in the
	old manifest reach the suite through `tools/suite_transcript.sh` ->
	`tools/test.sh`, and the graph reaches it through the result store. Without
	this seam that is two full runs of a 260-second suite for one tree state.

	IT REUSES THE STORE'S OWN REFUSALS. Nothing is re-judged here: the identity
	comes from the same producer declaration the coordinator uses, and the
	acceptance comes from `results.read`, which refuses a stale, incomplete,
	failed, edited, wrong-toolchain, wrong-class, fast-tier, truncated or partial
	result. A second opinion about when a transcript may be trusted is exactly
	what this repository has spent a stage removing. ]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local graphMod = require("./graph")
local identity = require("./identity")
local results = require("./results")

local g = graphMod.load()
local producers = graphMod.producerById(g)
local suite = producers["suite"]
if suite == nil then
	process.exit(1)
end

local computed = identity.compute(suite, identity.toolchain())
local record = results.read("suite", computed.hash, {
	requiredClass = suite.environmentClass,
	toolchain = identity.toolchainString(identity.toolchain()),
	suite = true,
})
if record == nil then
	process.exit(1)
end
local transcript = (record.payload :: any).transcript
if type(transcript) ~= "string" or not fs.isFile(transcript) then
	process.exit(1)
end
print(transcript)
