--!strict
-- The performance lab's CAPTURE ROW (roadmap Step 9, acceptance PL-9; PLN-3).
--
-- A frame time with no conditions attached is not evidence — it cannot be
-- compared with anything, including the next capture of the same workload. This
-- module owns the row schema and, more importantly, owns what makes a row
-- INADMISSIBLE, so a capture missing its conditions is refused here rather than
-- discovered months later in a comparison that quietly meant nothing.
--
-- FIVE EVIDENCE CLASSES, NEVER INTERCHANGEABLE. `lune`, `studio`, `emulator`,
-- `desktop-retail` and `phone-physical` are labels with different authority:
--   * `lune`      — headless trend screening. No engine, no frame, no device.
--   * `studio`    — the real adapter on the development host. Development
--                   evidence and regression signal; faster than every supported
--                   device, so it cannot establish a floor.
--   * `emulator`  — a Studio device SIMULATOR row. Proves layout and operability
--                   at that viewport. Proves NOTHING about that device's speed.
--   * `desktop-retail` — the shipped client on a desktop.
--   * `phone-physical` — the shipped client on named Android hardware. The only
--                   class that can close the low-end budget.
-- The class is stamped on the ROW, not merely on the file that holds it: the
-- existing perf gate learned that lesson the hard way (a relabelled container
-- once relabelled its contents), and `tools/check_perf_captures.py` re-checks
-- both ends independently.
--
-- ENGINE-FREE: everything engine-shaped arrives as a plain table from the caller.

local capture = {}

capture.SCHEMA = "facet-perf-capture/1"

capture.CLASSES = {
	lune = { device = false, note = "headless Lune; no engine, no frame, no device" },
	studio = { device = false, note = "the real adapter in a Studio Play session on the development host" },
	emulator = {
		device = false,
		note = "Studio device simulator; layout and operability only — never that device's performance",
	},
	["desktop-retail"] = { device = true, note = "the shipped desktop client" },
	["phone-physical"] = { device = true, note = "the shipped mobile client on named hardware" },
}

-- Every field a row MUST carry, grouped by the question it answers. Kept as data
-- so the in-place export, the headless test, and the Python checker all read one
-- list instead of three drifting ones.
capture.REQUIRED = {
	identity = { "schema", "evidenceClass", "capturedAtIso", "repeat_" },
	-- what was measured
	workload = {
		"scenario",
		"scenarioVersion",
		"datasetVersion",
		"rowVersion",
		"implementation",
		"rows",
		"seed",
		"content",
		"theme",
		"datasetDigest",
		"resourceState",
	},
	-- what it was measured on
	conditions = {
		"frameworkVersion",
		"sourceStamp",
		"placeName",
		"viewport",
		"orientation",
		"graphicsQualityLevel",
		"frameTarget",
		"studioVersion",
		"deviceLabel",
		"thermalNote",
	},
	-- how it was measured
	method = { "warmupFrames", "captureFrames", "cleanCapture", "profilerScopes" },
	-- what came out
	measured = { "frame", "counters", "scopes" },
}

-- Rows whose class is a DEVICE class additionally have to carry the things a
-- host session structurally cannot supply. Without this, a Studio row plus one
-- edited string is a device row, which is exactly the laundering the existing
-- perf gate already refuses on ingest.
capture.REQUIRED_DEVICE = { "deviceModel", "osVersion", "clientVersion", "powerState" }

-- "UNKNOWN" IS NOT A RECORDED CONDITION. A default string makes every row look
-- complete, which is worse than an obviously empty field: it produces a capture
-- that passes admissibility and still cannot be compared with anything.
--
-- `"n/a"` and `"not recorded"` are DIFFERENT and are accepted: they are explicit
-- declarations that the quantity does not exist for this class (a retail client
-- has no Studio version) or was deliberately not taken. `"unknown"` is the answer
-- of a harness that did not look.
local function missingFrom(row: any, keys: { string }, prefix: string?): { string }
	local missing: { string } = {}
	for _, key in keys do
		local value = row[key]
		-- CONTAINS, not equals (phase-gate review F-7). `"uncapped/unknown"` and
		-- `"unknown device"` are the same non-answer as `"unknown"` and slipped past an
		-- equality test. `"n/a"` and `"not recorded"` remain explicit declarations and
		-- still pass.
		if
			value == nil
			or value == ""
			or (type(value) == "string" and string.find(value, "unknown", 1, true) ~= nil)
		then
			table.insert(missing, (prefix or "") .. key)
		end
	end
	return missing
end

-- The admissibility judgement. Returns the list of problems; empty means the row
-- may be compared with another row of the same workload identity.
function capture.problems(row: any): { string }
	local problems: { string } = {}
	if type(row) ~= "table" then
		return { "row is not a table" }
	end
	if row.schema ~= capture.SCHEMA then
		table.insert(problems, `schema is '{tostring(row.schema)}', expected '{capture.SCHEMA}'`)
	end
	local class = capture.CLASSES[tostring(row.evidenceClass)]
	if class == nil then
		table.insert(problems, `unknown evidenceClass '{tostring(row.evidenceClass)}'`)
	end
	for group, keys in capture.REQUIRED do
		for _, key in missingFrom(row, keys) do
			table.insert(problems, `missing {group}.{key}`)
		end
	end
	if class ~= nil and class.device then
		for _, key in missingFrom(row, capture.REQUIRED_DEVICE) do
			table.insert(problems, `a device-class row is missing {key}`)
		end
		-- a device row taken in Studio is a contradiction, however it is labelled
		if row.studioVersion ~= nil and row.studioVersion ~= "" and row.studioVersion ~= "n/a" then
			table.insert(problems, "a device-class row carries a studioVersion; a retail client has none")
		end
	end
	-- the workload identity has to be COMPLETE or the row cannot be paired with
	-- anything: two captures agree only when scenario+versions+dataset+digest match
	if row.datasetDigest ~= nil and #tostring(row.datasetDigest) ~= 8 then
		table.insert(problems, "datasetDigest is not the 8-hex-digit fingerprint dataset.digest produces")
	end
	if type(row.measured) == "table" then
		table.insert(problems, "measured must be flattened into frame/counters/scopes, not nested")
	end
	table.sort(problems)
	return problems
end

-- Two rows describe the SAME workload when every identity field agrees. Used by
-- the comparison guidance and by the repeat-capture check: a "before/after" pair
-- that disagrees here is comparing two different things.
capture.IDENTITY_FIELDS = {
	"scenario",
	"scenarioVersion",
	"datasetVersion",
	"rowVersion",
	"implementation",
	"rows",
	"seed",
	"content",
	"theme",
	"datasetDigest",
	"resourceState",
	"cleanCapture",
}

function capture.sameWorkload(a: any, b: any): (boolean, { string })
	local differences: { string } = {}
	for _, key in capture.IDENTITY_FIELDS do
		if tostring(a[key]) ~= tostring(b[key]) then
			table.insert(differences, `{key}: {tostring(a[key])} vs {tostring(b[key])}`)
		end
	end
	return #differences == 0, differences
end

return capture
