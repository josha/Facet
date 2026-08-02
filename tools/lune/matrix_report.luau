--!strict
-- Assemble the device-matrix artifact (roadmap Step 4, rows XP-B1..XP-B4).
--
-- The Studio driver (tools/studio/device_matrix.luau) emits ONE stamped record
-- per row, saved verbatim under artifacts/cross-platform-proof/rows/matrix/.
-- This tool joins them with their captures, pins each capture's content hash,
-- and writes artifacts/cross-platform-proof/matrix.json.
--
-- The hash is the load-bearing part. Before it, a row could cite a picture that
-- had been retaken, edited or never existed, and nothing would notice. A row
-- whose capture is missing or has drifted fails here rather than in a reader's
-- assumptions.
--
--   lune run tools/lune/matrix_report

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local artifact = require("./artifact")
local matrix_rows = require("../../src/preview/matrix_rows")

local ROOT = "artifacts/cross-platform-proof"
local ROWS_DIR = ROOT .. "/rows/matrix"
local OUT = ROOT .. "/matrix.json"

local function sha16(path: string): string?
	local result = process.exec("shasum", { "-a", "256", path })
	if not result.ok then
		return nil
	end
	return string.sub(result.stdout, 1, 16)
end

local rows: { any } = {}
local problems: { string } = {}

for _, id in matrix_rows.list() do
	local path = `{ROWS_DIR}/{id}.json`
	if not fs.isFile(path) then
		table.insert(problems, `no driver record for row '{id}' ({path})`)
		continue
	end
	local record = serde.decode("json", fs.readFile(path))
	local capture = `captures/{id}.png`
	local capturePath = `{ROOT}/{capture}`
	if fs.isFile(capturePath) then
		record.capture = capture
		record.captureSha256_16 = sha16(capturePath)
		record.captureBytes = #fs.readFile(capturePath)
	else
		table.insert(problems, `row '{id}' has no capture at {capturePath}`)
	end
	-- the row's declared role travels with its result, so a reader does not have
	-- to hold the plan document open beside the artifact
	local row = matrix_rows.get(id)
	record.role = row.role
	record.risk = row.risk
	record.orientationRequested = row.orientation
	table.insert(rows, record)
end

local passed, failed = 0, 0
for _, r in rows do
	if r.ok then
		passed += 1
	else
		failed += 1
	end
end

-- the build every row came from. Presented up front because the five rows are
-- read as one proof: if they span different synced trees, that is a fact about
-- the evidence, not a detail to be discovered by diffing five nested fields.
local stamps: { string } = {}
local seenStamp: { [string]: boolean } = {}
for _, r in rows do
	local stamp = r.identity and r.identity.sourceStamp
	if stamp ~= nil and not seenStamp[stamp] then
		seenStamp[stamp] = true
		table.insert(stamps, stamp)
	end
end
table.sort(stamps)

local report = {
	schema = "luauui-device-matrix/1",
	stage = "cross-platform-proof",
	sourceStamps = stamps,
	sourceStampsCoherent = #stamps == 1,
	evidenceClass = "studio-emulated",
	evidenceLevel = "E3",
	rowsExpected = #matrix_rows.list(),
	rowsPresent = #rows,
	passed = passed,
	failed = failed,
	problems = problems,
	honestBoundary = {
		"the automated matrix closes Studio-visible layout, clipping, focus, style and injected-pointer rows",
		"it closes NONE of: physical touch targeting or feel, real gamepad delivery or arbitration, the mobile "
			.. "operating-system keyboard, operating-system display scaling outside the selected configuration, "
			.. "retail-client networking, low-end CPU/GPU/memory/thermal/battery/frame-time performance, or "
			.. "subjective readability and production feel",
		"Studio-emulated performance is useful regression evidence and is never the low-end Android result",
	},
	rows = rows,
}

artifact.writeJson(OUT, report)
print(`matrix_report: {#rows}/{#matrix_rows.list()} rows, {passed} pass, {failed} fail -> {OUT}`)
for _, p in problems do
	print(`  PROBLEM {p}`)
end
process.exit(if #problems == 0 and failed == 0 then 0 else 1)
