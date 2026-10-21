--!strict

local Core = require("../tools/vendor/verify/src/core")
local Lute = require("../tools/vendor/verify/src/lute")
local Evidence = require("../tools/vendor/verify/src/evidence")
local Files = require("../tools/facet/lib/files")
local Hash = require("../tools/facet/lib/hash")
local Json = require("../tools/facet/lib/json")

local function read(directory: string): Core.Report
	local envelope = Lute.parse(Files.read(directory .. "/submission.verify.json"))
	return Core.decode(Json.field(envelope, "report"))
end

local function subject(report: Core.Report): Core.ArtifactProvenance
	assert(report.total == 1 and report.passed == 1, "submission capture did not pass")
	local evidence = report.results[1].evidence
	assert(evidence and #evidence.checkpoints == 1, "submission checkpoint is missing")
	local artifact = evidence.checkpoints[1].artifacts[1]
	assert(artifact and artifact.provenance, "submission provenance is missing")
	return artifact.provenance
end

local function validate(place: string?, directory: string): Core.Report
	return Core.runCases({
		{
			id = "submission/unchanged",
			name = "submission/unchanged",
			timeoutSeconds = 120,
			run = function(t: Core.Context)
				local saved = read(directory)
				local provenance = subject(saved)
				local verified = Lute.evidenceStore.validate(saved, {
					runId = provenance.runId,
					build = { digest = provenance.build.digest },
					requireClean = false,
					directory = directory .. "/objects",
					maxAgeSeconds = 30 * 24 * 60 * 60,
					required = {
						{
							caseId = "submission/capture",
							actors = { "author" },
							checkpoints = { "place" },
							devices = { "studio" },
						},
					},
				})
				t:expect(verified.ok):toBeTrueWith(Evidence.explain(verified))
				t:expect(Hash.sha256(Files.read(directory .. "/game.rbxl"))):toBe(provenance.build.digest)
				if place ~= nil then
					t:expect(Hash.sha256(Files.read(place))):toBe(provenance.build.digest)
				end
			end,
		},
	}, { executor = "submission-integrity" }, os.clock)
end

local function capture(place: string, directory: string, runId: string): Core.Report
	place, directory = Files.absolute(place), Files.absolute(directory)
	assert(Files.isFile(place), "save the authored Studio place before capturing it")
	assert(
		string.sub(string.lower(place), 1, #directory + 1) ~= string.lower(directory) .. "/",
		"capture needs the saved original place"
	)
	if Files.exists(directory .. "/submission.verify.json") then
		return validate(place, directory)
	end
	assert(not Files.exists(directory), "an incomplete snapshot already exists; do not replace submitted bytes")
	local bytes = Files.read(place)
	assert(
		string.sub(bytes, 1, 8) == "<roblox!" or string.find(bytes, "<roblox", 1, true) ~= nil,
		"submission is not a Roblox place"
	)
	local digest = Hash.sha256(bytes)
	local report = Core.runCases({
		{
			id = "submission/capture",
			name = "submission/capture",
			run = function(t: Core.Context)
				t:checkpoint("author", "place")
			end,
		},
	}, {
		executor = "submission-place",
		capabilities = { "capture" },
		bind = function(): Core.CaseHost
			return {
				name = "submission-place",
				capabilities = { "capture" },
				environment = {},
				now = os.clock,
				invoke = function(): unknown
					return nil
				end,
				capture = function(): { Core.Artifact }
					return { { name = "game.rbxl", reference = place, mediaType = "application/octet-stream" } }
				end,
			}
		end,
	}, os.clock)
	local sealed = Lute.evidenceStore.seal(report, {
		runId = runId,
		device = "studio",
		directory = directory .. "/objects",
		build = { commit = "unversioned", tree = digest, clean = false, digest = digest },
	})
	assert(#sealed.issues == 0, "Verify could not seal the place: " .. Lute.encode(sealed.issues))
	local evidence = assert(sealed.report.results[1].evidence)
	local store = Lute.evidenceStore.localDirectory(directory .. "/objects")
	local frozen, problem = store.get(evidence.checkpoints[1].artifacts[1].reference)
	assert(frozen, problem or "sealed place is unavailable")
	assert(Hash.sha256(Files.read(place)) == digest, "the place changed while capturing the submission")
	assert(Hash.sha256(frozen) == digest, "the frozen place differs from the submission")
	Files.write(directory .. "/game.rbxl", frozen)
	Lute.gate.writeReport(directory .. "/submission.verify.json", runId, sealed.report)
	return validate(place, directory)
end

return { capture = capture, validate = validate }
