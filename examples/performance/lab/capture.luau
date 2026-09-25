--!strict

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

capture.REQUIRED = {
	identity = { "schema", "evidenceClass", "capturedAtIso", "repeat_" },

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

	method = { "warmupFrames", "captureFrames", "cleanCapture", "profilerScopes" },

	measured = { "frame", "counters", "scopes" },
}

capture.REQUIRED_DEVICE = { "deviceModel", "osVersion", "clientVersion", "powerState" }

local function missingFrom(row: any, keys: { string }, prefix: string?): { string }
	local missing: { string } = {}
	for _, key in keys do
		local value = row[key]

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

		if row.studioVersion ~= nil and row.studioVersion ~= "" and row.studioVersion ~= "n/a" then
			table.insert(problems, "a device-class row carries a studioVersion; a retail client has none")
		end
	end

	if row.datasetDigest ~= nil and #tostring(row.datasetDigest) ~= 8 then
		table.insert(problems, "datasetDigest is not the 8-hex-digit fingerprint dataset.digest produces")
	end
	if type(row.measured) == "table" then
		table.insert(problems, "measured must be flattened into frame/counters/scopes, not nested")
	end
	table.sort(problems)
	return problems
end

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
