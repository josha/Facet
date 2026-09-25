--!strict

local device_profiles = require("./profiles_data")

export type Profile = {
	name: string,
	title: string,
	viewport: { w: number, h: number },
	insets: { top: number, bottom: number, left: number, right: number },
	preferredInput: string,
	capabilities: { keyboard: boolean, mouse: boolean, touch: boolean, gamepad: boolean },
	displaySize: string,
	overscanInsets: { top: number, bottom: number, left: number, right: number },

	frameTargetHz: number,
	reference: boolean,
}

local perf_profiles = {}

local NO_OVERSCAN = { top = 0, bottom = 0, left = 0, right = 0 }

local FLOOR: Profile = {
	name = "floorAndroid",
	title = "Floor low-end Android (360×640, touch)",
	viewport = { w = 360, h = 640 },
	insets = { top = 24, bottom = 0, left = 0, right = 0 },
	preferredInput = "Touch",
	capabilities = { keyboard = false, mouse = false, touch = true, gamepad = false },
	displaySize = "Small",
	overscanInsets = NO_OVERSCAN,
	frameTargetHz = 30,
	reference = true,
}

perf_profiles.REFERENCE = FLOOR.name

local function fromDevice(deviceName: string, preferredInput: string, caps, frameTargetHz: number): Profile
	local base = device_profiles.get(deviceName)
	assert(base ~= nil, `perf_profiles: unknown device_profiles class '{deviceName}'`)
	local facts = (base :: any).facts
	assert(type(facts) == "table", `perf_profiles: device profile '{deviceName}' declares no facts`)
	assert(type(facts.displaySize) == "string", `perf_profiles: device profile '{deviceName}' declares no displaySize`)
	return {
		name = base.name,
		title = base.title,
		viewport = table.clone(base.viewport),
		insets = table.clone(base.insets),
		preferredInput = preferredInput,
		capabilities = caps,
		displaySize = facts.displaySize,
		overscanInsets = table.clone(facts.overscanInsets or NO_OVERSCAN),
		frameTargetHz = frameTargetHz,
		reference = false,
	}
end

local PROFILES: { [string]: Profile } = {
	floorAndroid = FLOOR,
	phone = fromDevice("phone", "Touch", { keyboard = false, mouse = false, touch = true, gamepad = false }, 60),
	tablet = fromDevice("tablet", "Touch", { keyboard = false, mouse = false, touch = true, gamepad = false }, 60),
	desktop = fromDevice(
		"desktop",
		"KeyboardAndMouse",
		{ keyboard = true, mouse = true, touch = false, gamepad = false },
		60
	),

	consoleTenFoot = fromDevice(
		"console",
		"Gamepad",
		{ keyboard = false, mouse = false, touch = false, gamepad = true },
		60
	),
}

PROFILES.consoleTenFoot.name = "consoleTenFoot"

local ORDER = { "floorAndroid", "phone", "tablet", "desktop", "consoleTenFoot" }

function perf_profiles.list(): { string }
	return table.clone(ORDER)
end

function perf_profiles.get(name: string): Profile
	local p = PROFILES[name]
	assert(p ~= nil, `perf_profiles: unknown profile '{name}' (have: {table.concat(ORDER, ", ")})`)
	return p
end

return perf_profiles
