--!strict

local Json = require("./json")

local function stringArray(list: { string }): Json.Array
	local array = Json.array()
	for _, item in list do
		table.insert(array, item)
	end
	return array
end

export type Outcome = {
	errors: { string },
	notes: { string },
	summary: string,
}

export type ScenePredicate = (extras: Json.Object) -> string?

export type ThemePredicate = {
	accepts: (swap: Json.Object) -> boolean,
	why: string,
}

local Evidence = {}

Evidence.PERF = "artifacts/phase-4/perf.json"
Evidence.BUDGETS = "bench/perf_budgets.json"
Evidence.DEVICE_DIRECTORY = "artifacts/cross-platform-proof/device"
Evidence.DEVICE_CLASSES = { "console-physical", "desktop-retail", "phone-physical" }
Evidence.HEADLESS_CLASS = "lute"
Evidence.METRICS =
	{ "frameWorkMs", "updateMs", "instances", "connections", "memoryKb", "inputToVisibleMs", "themeSwap" }
Evidence.REFERENCE = "floorAndroid"
Evidence.CONSOLE = "consoleTenFoot"

local EMPTY: Json.Object = Json.object()

local function quote(text: string): string
	local mark = if string.find(text, "'", 1, true) ~= nil and string.find(text, '"', 1, true) == nil then '"' else "'"
	local escaped = string.gsub(text, "[\\\n\r\t" .. mark .. "]", function(character: string): string
		if character == "\n" then
			return "\\n"
		elseif character == "\r" then
			return "\\r"
		elseif character == "\t" then
			return "\\t"
		end
		return "\\" .. character
	end)
	return mark .. escaped .. mark
end

local function number(value: number): string
	if value ~= value then
		return "nan"
	elseif value == math.huge then
		return "inf"
	elseif value == -math.huge then
		return "-inf"
	elseif value == math.floor(value) and math.abs(value) < 1e16 then
		return ("%d"):format(value)
	end
	return tostring(value)
end

function Evidence.repr(value: unknown): string
	if value == nil or Json.isNull(value) then
		return "None"
	elseif type(value) == "boolean" then
		return if value then "True" else "False"
	elseif type(value) == "number" then
		return number(value)
	elseif type(value) == "string" then
		return quote(value)
	end
	local array = Json.asArray(value)
	if array ~= nil then
		local parts: { string } = {}
		for _, item in array do
			table.insert(parts, Evidence.repr(item))
		end
		return "[" .. table.concat(parts, ", ") .. "]"
	end
	local object = Json.asObject(value)
	if object ~= nil then
		local parts: { string } = {}
		for _, key in Json.keys(object) do
			table.insert(parts, quote(key) .. ": " .. Evidence.repr(object[key]))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

function Evidence.text(value: unknown): string
	if type(value) == "string" then
		return value
	end
	return Evidence.repr(value)
end

function Evidence.truthy(value: unknown): boolean
	if value == nil or value == false or Json.isNull(value) then
		return false
	elseif type(value) == "number" then
		return value ~= 0
	elseif type(value) == "string" then
		return value ~= ""
	elseif type(value) == "table" then
		return next(value :: { [unknown]: unknown }) ~= nil
	end
	return true
end

local function field(value: unknown, key: string): unknown
	return Json.field(value, key)
end

local function object(value: unknown): Json.Object
	return Json.asObject(value) or EMPTY
end

local function objectOr(value: unknown): Json.Object
	if not Evidence.truthy(value) then
		return EMPTY
	end
	return object(value)
end

local function list(value: unknown): Json.Array
	local array = Json.asArray(value)
	if array == nil then
		return Json.array()
	end
	return array
end

local function isObject(value: unknown): boolean
	return Json.asObject(value) ~= nil
end

local function isNumber(value: unknown): boolean
	return type(value) == "number"
end

local function count(value: Json.Object, key: string): number
	local found = field(value, key)
	return if type(found) == "number" then found else 0
end

local function has(value: Json.Object, key: string): boolean
	return value[key] ~= nil
end

local function sortedRepr(values: { string }): string
	local copy = table.clone(values)
	table.sort(copy)
	return Evidence.repr(stringArray(copy))
end

local function keys(value: Json.Object): { string }
	return Json.keys(value)
end

local function sameSet(left: { [string]: boolean }, right: { [string]: boolean }): boolean
	for key in left do
		if not right[key] then
			return false
		end
	end
	for key in right do
		if not left[key] then
			return false
		end
	end
	return true
end

local function members(set: { [string]: boolean }): { string }
	local list: { string } = {}
	for key in set do
		table.insert(list, key)
	end
	table.sort(list)
	return list
end

function Evidence.budgets(budgets: unknown, report: unknown, deviceRows: (string) -> number): Outcome
	local errors: { string } = {}
	local function fail(message: string)
		table.insert(errors, message)
	end
	if field(budgets, "schema") ~= "facet-perf-budgets/2" then
		fail(("unexpected schema %s; expected facet-perf-budgets/2"):format(Evidence.repr(field(budgets, "schema"))))
	end
	if field(budgets, "evidenceClass") ~= Evidence.HEADLESS_CLASS then
		fail("the scene budgets must be labelled with the evidence class that produced them")
	end
	local ceiling = objectOr(field(budgets, "frameCeiling"))
	local share = field(ceiling, "uiShare")
	local fraction = if Evidence.truthy(share) then share else 0
	if not (type(fraction) == "number" and fraction > 0 and fraction <= 1) then
		fail(("frameCeiling.uiShare is not a fraction: %s"):format(Evidence.repr(share)))
	end
	if field(ceiling, "directionality") ~= "one-way" then
		fail("frameCeiling must declare its one-way directionality")
	end
	local note = field(ceiling, "note")
	if type(note) ~= "string" or string.find(note, "proves NOTHING about a device", 1, true) == nil then
		fail("frameCeiling.note must state that passing the ceiling proves nothing about a device")
	end
	local scenes = objectOr(field(budgets, "scenes"))
	local sceneNames = keys(scenes)
	if #sceneNames < 15 then
		fail(("only %d scene budgets; the Step-4 scene set is larger than that"):format(#sceneNames))
	end
	for _, name in sceneNames do
		local budget = object(scenes[name])
		if not isNumber(field(budget, "observed_p95_ms")) then
			fail(("%s: no measured baseline (observed_p95_ms)"):format(name))
		end
		if not isNumber(field(budget, "frameTargetHz")) then
			fail(("%s: no frame target"):format(name))
		end
		local ceilingMs = field(budget, "ceilingMs")
		if type(ceilingMs) ~= "number" then
			fail(("%s: no frame ceiling"):format(name))
		elseif ceilingMs <= 0 then
			fail(("%s: non-positive frame ceiling"):format(name))
		end
		if not Evidence.truthy(field(budget, "hint")) then
			fail(("%s: no actionable hint"):format(name))
		end
	end
	local device = objectOr(field(budgets, "deviceBudgets"))
	local missing: { string } = {}
	for _, class in Evidence.DEVICE_CLASSES do
		if not has(device, class) then
			table.insert(missing, class)
		end
	end
	if #missing > 0 then
		fail(("device budgets missing for %s"):format(sortedRepr(missing)))
	end
	for _, class in keys(device) do
		local budget = object(device[class])
		local measured = field(budget, "measured")
		if measured == true then
			if deviceRows(class) == 0 then
				fail(
					("device budget %s claims measured=true but no capture of that evidence class exists under %s/ with rows in it — that would be a fabricated device claim"):format(
						class,
						Evidence.DEVICE_DIRECTORY
					)
				)
			end
		elseif measured ~= false then
			fail(("device budget %s: measured must be true or false, not %s"):format(class, Evidence.repr(measured)))
		end
		local budgetMs = field(budget, "budgetMs")
		if type(budgetMs) ~= "number" or budgetMs <= 0 then
			fail(("device budget %s: no positive budgetMs"):format(class))
		end
		if not isNumber(field(budget, "frameTargetHz")) then
			fail(("device budget %s: no frame target"):format(class))
		end
	end
	local budgetBlock = objectOr(field(report, "budget"))
	if Evidence.truthy(field(budgetBlock, "checked")) then
		local skipped: { [string]: boolean } = {}
		for _, entry in list(field(budgetBlock, "skippedDeviceBudgets")) do
			local class = field(entry, "class")
			skipped[Evidence.text(class)] = true
		end
		local expected: { [string]: boolean } = {}
		for _, class in keys(device) do
			if field(device[class], "measured") ~= true then
				expected[class] = true
			end
		end
		if not sameSet(skipped, expected) then
			fail(
				("the last perf run recorded skipped device budgets %s but %s are declared unmeasured — an unreported skip reads as a pass"):format(
					sortedRepr(members(skipped)),
					sortedRepr(members(expected))
				)
			)
		end
	end
	local measuredClasses: { string } = {}
	local unmeasuredClasses: { string } = {}
	for _, class in keys(device) do
		if Evidence.truthy(field(device[class], "measured")) then
			table.insert(measuredClasses, class)
		else
			table.insert(unmeasuredClasses, class)
		end
	end
	table.sort(measuredClasses)
	table.sort(unmeasuredClasses)
	local deviceNote = if #unmeasuredClasses > 0
		then ("%d device budget(s) declared and unmeasured (PENDING_PHYSICAL: %s)"):format(
			#unmeasuredClasses,
			table.concat(unmeasuredClasses, ", ")
		)
		else "0 unmeasured device budgets"
	if #measuredClasses > 0 then
		deviceNote ..= ("; %d MEASURED and enforced (%s)"):format(#measuredClasses, table.concat(measuredClasses, ", "))
	end
	return {
		errors = errors,
		notes = {},
		summary = ("perf budgets ok: %d scene budgets carry baseline+frame target; %s"):format(#sceneNames, deviceNote),
	}
end

function Evidence.deviceRowCounter(documents: { unknown }): (string) -> number
	return function(class: string): number
		local total = 0
		for _, document in documents do
			if Json.asObject(document) ~= nil and field(document, "evidenceClass") == class then
				local rows = field(document, "rows")
				if Evidence.truthy(rows) then
					local array = Json.asArray(rows)
					local objectRows = Json.asObject(rows)
					if array ~= nil then
						total += #array
					elseif objectRows ~= nil then
						total += #keys(objectRows)
					elseif type(rows) == "string" then
						total += #rows
					end
				end
			end
		end
		return total
	end
end

local function isBlind(value: unknown): boolean
	return isObject(value) and field(value, "measured") == false and Evidence.truthy(field(value, "reason"))
end

local function isDeviceClass(value: unknown): boolean
	return type(value) == "string" and table.find(Evidence.DEVICE_CLASSES, value) ~= nil
end

local function deviceRun(run: Json.Object, class: string, where: string, fail: (string) -> ())
	local level = field(run, "evidenceLevel")
	if level ~= "E4" then
		fail(("%s: a %s row must carry E4, not %s"):format(where, class, Evidence.repr(level)))
	end
	local metrics = objectOr(field(run, "metrics"))
	local frameWork = field(metrics, "frameWorkMs")
	if not Evidence.truthy(frameWork) then
		frameWork = field(metrics, "M1_frameWorkMs")
	end
	if not isObject(frameWork) then
		fail(("%s: an ingested %s row carries no frame-work metric"):format(where, class))
	elseif field(frameWork, "measured") ~= true then
		fail(("%s: an ingested %s row's frame work is not measured"):format(where, class))
	else
		local p95 = field(frameWork, "p95_ms")
		if type(p95) ~= "number" or p95 ~= p95 or p95 < 0 then
			fail(("%s: an ingested %s row's M1 p95_ms is %s"):format(where, class, Evidence.repr(p95)))
		end
	end
	for _, entry in
		{
			{ name = "updateMs", aliases = { "updateMs", "M2_updateMs" } },
			{ name = "instances", aliases = { "instances", "M3_instances" } },
			{ name = "connections", aliases = { "connections", "M4_connections" } },
			{ name = "memoryKb", aliases = { "memoryKb", "M5_memory", "memory" } },
		}
	do
		local present = false
		for _, alias in entry.aliases do
			if has(metrics, alias) then
				present = true
			end
		end
		if not present then
			fail(("%s: an ingested %s row is missing metric %s"):format(where, class, entry.name))
		end
	end
	local identity = objectOr(field(run, "identity"))
	if field(identity, "studioVersion") ~= nil then
		fail(("%s: a %s row carries identity.studioVersion"):format(where, class))
	end
	local device = objectOr(field(run, "device"))
	local deviceValue = field(run, "device")
	local live = if isObject(deviceValue) then objectOr(field(device, "live")) else EMPTY
	if field(live, "deviceId") ~= nil then
		fail(("%s: a %s row carries a Studio device-simulator preset id"):format(where, class))
	end
	local scaling = field(live, "scalingMode")
	if string.find(Evidence.text(if Evidence.truthy(scaling) then scaling else ""), "DeviceSimulator", 1, true) then
		fail(("%s: a %s row carries a Studio device-simulator scaling mode"):format(where, class))
	end
	local provenance = field(run, "provenance")
	if not isObject(provenance) then
		fail(("%s: a %s row carries no provenance attestation"):format(where, class))
		return
	end
	if field(provenance, "isStudio") ~= false then
		fail(("%s: provenance.isStudio must be the boolean false, stated"):format(where))
	end
	local clientKind = field(provenance, "clientKind")
	if clientKind ~= "retail" then
		fail(("%s: provenance.clientKind is %s, expected 'retail'"):format(where, Evidence.repr(clientKind)))
	end
	for _, name in { "instrument", "deviceModel", "capturedAt", "attestedBy" } do
		local value = field(provenance, name)
		if type(value) ~= "string" or value == "" then
			fail(("%s: provenance.%s is missing or empty"):format(where, name))
		end
	end
	local model = field(provenance, "deviceModel")
	local name = if isObject(deviceValue) then field(device, "name") else nil
	if type(model) == "string" and model ~= "" and type(name) == "string" and name ~= "" and model ~= name then
		fail(
			("%s: provenance.deviceModel %s disagrees with device.name %s"):format(
				where,
				Evidence.repr(model),
				Evidence.repr(name)
			)
		)
	end
end

local function headlessRun(run: Json.Object, class: unknown, where: string, fail: (string) -> ())
	if class ~= Evidence.HEADLESS_CLASS then
		fail(
			("%s: evidenceClass %s; a headless Lute process may only emit %s"):format(
				where,
				Evidence.repr(class),
				Evidence.repr(Evidence.HEADLESS_CLASS)
			)
		)
	end
	local level = field(run, "evidenceLevel")
	if level ~= "E1" then
		fail(("%s: evidenceLevel %s, expected E1"):format(where, Evidence.repr(level)))
	end
	if field(run, "authoritative") ~= false or field(run, "deviceRun") ~= false then
		fail(("%s: a headless record must stay deviceRun=false / authoritative=false"):format(where))
	end
	local metrics = Json.asObject(field(run, "metrics"))
	if metrics == nil then
		fail(("%s: no metrics block"):format(where))
		return
	end
	for _, metric in Evidence.METRICS do
		if not has(metrics, metric) then
			fail(("%s: metric %s missing entirely (an absent metric reads as zero)"):format(where, metric))
			continue
		end
		local value = metrics[metric]
		if isObject(value) and field(value, "measured") == false and not Evidence.truthy(field(value, "reason")) then
			fail(("%s: metric %s is unmeasured but gives no reason"):format(where, metric))
		end
	end
	if not isBlind(field(metrics, "frameWorkMs")) then
		fail(("%s: frameWorkMs must be explicitly blind in a headless record"):format(where))
	end
	local update = field(metrics, "updateMs")
	if not (isObject(update) and Evidence.truthy(field(update, "measured"))) then
		fail(("%s: updateMs must be measured"):format(where))
	end
	local connections = field(metrics, "connections")
	if not (isObject(connections) and Evidence.truthy(field(connections, "measured"))) then
		if
			not (
				isBlind(connections)
				and isBlind(field(connections, "adapterHandlers"))
				and isBlind(field(connections, "reactiveRegistrations"))
			)
		then
			fail(
				("%s: connections require a measurement or explicit native ownership blind markers for both counts"):format(
					where
				)
			)
		end
	end
	local memory = field(metrics, "memoryKb")
	if not (isObject(memory) and Evidence.truthy(field(memory, "measured"))) then
		fail(("%s: memoryKb must be measured"):format(where))
	end
end

function Evidence.metrics(report: unknown): Outcome
	local errors: { string } = {}
	local notes: { string } = {}
	local function fail(message: string)
		table.insert(errors, message)
	end
	if Evidence.truthy(field(report, "injectedRegression")) then
		fail(
			"the committed perf artifact carries an injectedRegression stamp: it came from a deliberate falsification run and is not a valid measurement"
		)
	end
	local classOrder: { string } = {}
	local classes: { [string]: Json.Object } = {}
	for _, entry in list(field(report, "evidenceClasses")) do
		local id = Evidence.text(field(entry, "id"))
		if classes[id] == nil then
			table.insert(classOrder, id)
		end
		classes[id] = object(entry)
	end
	for _, class in Evidence.DEVICE_CLASSES do
		if classes[class] == nil then
			fail(
				"the evidence-class inventory does not declare every device class; absence must be stated, not inferred"
			)
			break
		end
	end
	local ingested: { [string]: boolean } = {}
	local ingestedRows = list(field(report, "ingestedDeviceRows"))
	for _, item in ingestedRows do
		local text = Evidence.text(item)
		ingested[string.split(text, ":")[1]] = true
	end
	for _, class in Evidence.DEVICE_CLASSES do
		local declared = classes[class]
		if declared ~= nil then
			local rows = declared["rows"]
			local value = if rows == nil then 0 else rows
			if value ~= 0 and not ingested[class] then
				fail(
					("class %s claims %s rows that were never ingested from a stored capture"):format(
						class,
						Evidence.text(value)
					)
				)
			end
		end
	end
	for _, rejected in list(field(report, "rejectedDeviceRows")) do
		table.insert(
			notes,
			("NOTE rejected row %s: file '%s' vs row '%s'"):format(
				Evidence.text(field(rejected, "scene")),
				Evidence.text(field(rejected, "fileClass")),
				Evidence.text(field(rejected, "rowClass"))
			)
		)
	end
	for _, id in classOrder do
		for _, name in { "level", "instrument", "proves", "cannotProve" } do
			if not Evidence.truthy(field(classes[id], name)) then
				fail(("class %s declares no %s"):format(id, name))
			end
		end
	end
	local runs = Json.asArray(field(report, "runs"))
	if runs == nil then
		fail("the perf artifact has no runs list")
		return { errors = errors, notes = notes, summary = "" }
	end
	for _, entry in runs do
		local run = object(entry)
		local where = ("%s@%s"):format(Evidence.text(field(run, "scene")), Evidence.text(field(run, "device")))
		local class = field(run, "evidenceClass")
		if isDeviceClass(class) then
			deviceRun(run, class :: string, where, fail)
		else
			headlessRun(run, class, where, fail)
		end
	end
	local measuredScenes: { [string]: boolean } = {}
	local measuredCount = 0
	for _, entry in runs do
		local latency = field(field(entry, "metrics"), "inputToVisibleMs")
		if isObject(latency) and Evidence.truthy(field(latency, "measured")) then
			measuredCount += 1
			measuredScenes[Evidence.text(field(entry, "scene"))] = true
		end
	end
	if measuredCount == 0 then
		fail("no scene measures input-to-visible latency (M6); the metric is declared but never taken")
	end
	local deviceRows = 0
	for _, entry in runs do
		if isDeviceClass(field(entry, "evidenceClass")) then
			deviceRows += 1
		end
	end
	local deviceNote = if deviceRows > 0
		then ("; %d ingested device row(s) held to the device contract (E4, measured M1, M2-M5 present, an affirmative provenance attestation that agrees with the row's own device, and no Studio fingerprint)"):format(
			deviceRows
		)
		else "; 0 ingested device rows"
	return {
		errors = errors,
		notes = notes,
		summary = ("perf metrics ok: %d headless record(s) carry all %d metric rows%s; M6 measured in %d scene(s)"):format(
			#runs - deviceRows,
			#Evidence.METRICS,
			deviceNote,
			#members(measuredScenes)
		),
	}
end

local function wrong(extras: Json.Object, message: string): string
	return (message:gsub("%%x", function(): string
		return Evidence.repr(extras)
	end))
end

Evidence.PRODUCTION_ORDER = {
	"virtual-list-scroll",
	"native-scroll-drag",
	"dense-hud",
	"stylesheet-state-churn",
	"async-image-grid",
	"screen-lifecycle-churn",
	"alert-present-dismiss",
	"picker-menu-open-close",
	"picker-segmented-textsize",
	"radial-menu-open-close",
	"dense-motion",
	"control-motion",
}

Evidence.PRODUCTION = {
	["virtual-list-scroll"] = function(x: Json.Object): string?
		local windowed = count(x, "windowedRows")
		if count(x, "logicalRows") >= 1000 and windowed > 0 and windowed < 100 then
			return nil
		end
		return wrong(x, "windowing looks wrong: %x (expect a small window over >=1000 rows)")
	end,
	["native-scroll-drag"] = function(x: Json.Object): string?
		if count(x, "dragMoves") > 0 and count(x, "drops") > 0 then
			return nil
		end
		return wrong(x, "the UIDragDetector path committed no drag: %x")
	end,
	["dense-hud"] = function(x: Json.Object): string?
		if
			count(x, "activationCount") > 0
			and field(x, "activationText") == "Boost x" .. Evidence.text(field(x, "activationCount"))
		then
			return nil
		end
		return wrong(x, "the activate chain did not reach the mounted text: %x")
	end,
	["stylesheet-state-churn"] = function(x: Json.Object): string?
		if count(x, "tagsPerPass") > 0 then
			return nil
		end
		return wrong(x, "no state tags classified: %x")
	end,
	["async-image-grid"] = function(_x: Json.Object): string?
		return nil
	end,
	["screen-lifecycle-churn"] = function(_x: Json.Object): string?
		return nil
	end,
	["alert-present-dismiss"] = function(x: Json.Object): string?
		if count(x, "opens") > 0 and field(x, "surfaceItems") == 3 and field(x, "settled") == field(x, "opens") then
			return nil
		end
		return wrong(x, "the alert did not present its three actions and settle dismissed each time: %x")
	end,
	["picker-menu-open-close"] = function(x: Json.Object): string?
		if
			count(x, "opens") > 0
			and field(x, "surfaceItems") == 6
			and field(x, "presentation") == "picker"
			and field(x, "settled") == field(x, "opens")
		then
			return nil
		end
		return wrong(x, "the picker menu did not open with six rows and settle closed each time: %x")
	end,
	["picker-segmented-textsize"] = function(x: Json.Object): string?
		local segmented = field(x, "segmented")
		if
			isObject(segmented)
			and field(segmented, "segments") == 3
			and field(segmented, "textSizeBefore") ~= nil
			and field(segmented, "textSizeBefore") ~= field(segmented, "textSizeAfter")
		then
			return nil
		end
		return wrong(x, "the segmented strip did not follow the preferred text size: %x")
	end,
	["radial-menu-open-close"] = function(x: Json.Object): string?
		if count(x, "opens") > 0 and field(x, "surfaceItems") == 6 and field(x, "settled") == field(x, "opens") then
			return nil
		end
		return wrong(x, "the radial did not open six sectors and settle closed each time: %x")
	end,
	["dense-motion"] = function(x: Json.Object): string?
		local windowed = count(x, "windowedRows")
		if
			count(x, "springs") >= 20
			and count(x, "springsMoving") >= 20
			and count(x, "beats") > 0
			and count(x, "beatCallbacks") > 0
			and windowed > 0
			and windowed < count(x, "logicalRows")
			and count(x, "motionSteps") > 0
		then
			return nil
		end
		return wrong(x, "the dense-motion frame did not do its work: %x")
	end,
	["control-motion"] = function(x: Json.Object): string?
		if
			count(x, "rekeys") > 0
			and count(x, "flips") > 0
			and count(x, "pulses") > 0
			and count(x, "pops") > 0
			and count(x, "staggerHeld") > 0
			and count(x, "flipsSeen") > 0
			and count(x, "shakesSeen") > 0
			and count(x, "popsSeen") > 0
			and count(x, "motionSteps") > 0
			and count(x, "motionTransactions") >= count(x, "motionSteps")
		then
			return nil
		end
		return wrong(x, "the control-motion frame did not do its work: %x")
	end,
} :: { [string]: ScenePredicate }

Evidence.THEME_ORDER = { "theme-swap-flat", "theme-swap-metrics", "theme-swap-assets" }

Evidence.THEMES = {
	["theme-swap-flat"] = {
		accepts = function(s: Json.Object): boolean
			return field(s, "metricChanges") == 0 and field(s, "imageChanges") == 0 and count(s, "paintChanges") > 0
		end,
		why = "a palette-only swap must change paint rules and no metric rule or skin image",
	},
	["theme-swap-metrics"] = {
		accepts = function(s: Json.Object): boolean
			return count(s, "metricChanges") > 0
		end,
		why = "a metric-changing swap must change metric rules",
	},
	["theme-swap-assets"] = {
		accepts = function(s: Json.Object): boolean
			return count(s, "metricChanges") > 0 and count(s, "imageChanges") > 0
		end,
		why = "an asset-backed swap must change metric rules and the skin images",
	},
} :: { [string]: ThemePredicate }

function Evidence.scenes(report: unknown, themes: boolean): Outcome
	local errors: { string } = {}
	local notes: { string } = {}
	local function fail(message: string)
		table.insert(errors, message)
	end
	local schema = field(report, "schema")
	if schema ~= "facet-perf/2" then
		fail(("unexpected schema %s; expected facet-perf/2"):format(Evidence.repr(schema)))
	end
	if field(report, "injectedRegression") ~= nil then
		fail("the artifact is an injected-regression run, not a workload record")
	end
	local byScene: { [string]: Json.Object } = {}
	local devices: { [string]: boolean } = {}
	for _, entry in list(field(report, "runs")) do
		local run = object(entry)
		if field(run, "evidenceClass") ~= Evidence.HEADLESS_CLASS then
			continue
		end
		local device = Evidence.text(field(run, "device"))
		devices[device] = true
		if device == Evidence.REFERENCE then
			byScene[Evidence.text(field(run, "scene"))] = run
		end
	end
	if not themes and not devices[Evidence.CONSOLE] then
		fail(("no %s runs: the ten-foot profile is missing from the matrix"):format(Evidence.CONSOLE))
	end
	local wanted: { string } = if themes then Evidence.THEME_ORDER else Evidence.PRODUCTION_ORDER
	for _, scene in wanted do
		local run = byScene[scene]
		if run == nil then
			fail(("%s: no %s run recorded"):format(scene, Evidence.REFERENCE))
			continue
		end
		if not Evidence.truthy(field(run, "dataset")) then
			fail(("%s: no dataset recorded"):format(scene))
		end
		local extras = objectOr(field(run, "extras"))
		if themes then
			local predicate = Evidence.THEMES[scene]
			local swap = field(extras, "themeSwap")
			if not isObject(swap) or not Evidence.truthy(field(swap, "measured")) then
				fail(("%s: no measured themeSwap in extras (%s)"):format(scene, Evidence.repr(extras)))
				continue
			end
			local swapObject = object(swap)
			if not Evidence.truthy(field(swapObject, "controlsRetained")) then
				fail(("%s: the swap rebuilt the mounted controls (%s)"):format(scene, Evidence.repr(swapObject)))
			end
			if not predicate.accepts(swapObject) then
				fail(("%s: %s (%s)"):format(scene, predicate.why, Evidence.repr(swapObject)))
			end
		else
			local problem = Evidence.PRODUCTION[scene](extras)
			if problem ~= nil and problem ~= "" then
				fail(("%s: %s"):format(scene, problem))
			end
		end
	end
	if not themes then
		local grid = byScene["async-image-grid"]
		if grid ~= nil then
			local stats = objectOr(field(grid, "async"))
			local completed = field(stats, "completed")
			if type(completed) ~= "number" or completed <= 0 then
				fail(("async-image-grid: the provider completed nothing (%s)"):format(Evidence.repr(stats)))
			end
		end
	end
	if #errors > 0 then
		local stamp = field(report, "generatedAt")
		if not Evidence.truthy(stamp) then
			stamp = field(report, "timestamp")
		end
		table.insert(
			notes,
			("note: read %s, recorded %s"):format(
				Evidence.PERF,
				if Evidence.truthy(stamp) then Evidence.text(stamp) else "unknown"
			)
		)
	end
	return {
		errors = errors,
		notes = notes,
		summary = ("perf scenes ok: %d %s scenes did their work at %s"):format(
			#wanted,
			if themes then "theme-swap" else "production",
			Evidence.REFERENCE
		),
	}
end

return table.freeze(Evidence)
