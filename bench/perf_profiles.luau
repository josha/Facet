--!strict
-- Perf floor-device profiles (design §14.3 device matrix; §17 Phase 4
-- floor-device suite; roadmap Step 4 console/ten-foot coverage). REUSES
-- src/preview/device_profiles.luau geometry AND display/input facts for the
-- shared classes so nothing is duplicated, and ADDS the floor low-end-Android
-- reference the perf gate targets.
--
-- A profile is not just a viewport. `apply` writes the display class and
-- overscan margins too, because the ten-foot path (typography ×1.5, overscan
-- insets, focus strengthening) engages off `displaySize`, not off width — a
-- "console" profile that only set 1920×1080 would measure a large desktop and
-- silently claim console coverage.
--
-- Public interface:
--   perf_profiles.REFERENCE            -- name of the floor gate profile
--   perf_profiles.list() -> { string } -- stable order
--   perf_profiles.get(name) -> Profile
--   perf_profiles.apply(env, profile)  -- write geometry + display + input
--
-- Depends on: src/preview/device_profiles.

local device_profiles = require("../src/preview/device_profiles")

export type Profile = {
	name: string,
	title: string,
	viewport: { w: number, h: number },
	insets: { top: number, bottom: number, left: number, right: number },
	preferredInput: string, -- "Touch" | "KeyboardAndMouse" | "Gamepad"
	capabilities: { keyboard: boolean, mouse: boolean, touch: boolean, gamepad: boolean },
	displaySize: string, -- "Small" | "Medium" | "Large"
	overscanInsets: { top: number, bottom: number, left: number, right: number },
	-- the frame target this class of hardware is expected to hold. It is a
	-- PRODUCT target, not a measurement: it is what the frame-ceiling budget in
	-- bench/perf_budgets.json divides. The floor device targets 30 Hz; every
	-- other supported class targets 60 Hz.
	frameTargetHz: number,
	reference: boolean, -- true for the single profile the budget gate enforces
}

local perf_profiles = {}

local NO_OVERSCAN = { top = 0, bottom = 0, left = 0, right = 0 }

-- The floor device: a low-end Android reference (§14.3 "The floor device is a
-- low-end Android reference"). 360×640 dp is the common weak-Android canvas;
-- top inset models the status bar. Touch-only, no keyboard/mouse/gamepad. This
-- is the ONE profile the headless trend-budget gate checks against — a fixed
-- reference keeps the budget stable regardless of which classes are also run.
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

-- reuse a device_profiles class WHOLE (geometry + display facts) and annotate
-- the input class and frame target. A missing fact is an assertion, not a
-- silent default: the two files must not drift into disagreeing about what a
-- "console" is.
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
	-- console / ten-foot (roadmap Step 4): the ONLY profile whose display class
	-- is Large, so it is the only one that exercises the ×1.5 type floor, the
	-- overscan composition and the strengthened focus visual. Without it the
	-- headless matrix cannot see a regression that only a TV would show.
	consoleTenFoot = fromDevice(
		"console",
		"Gamepad",
		{ keyboard = false, mouse = false, touch = false, gamepad = true },
		60
	),
}
-- keep the console profile's own name distinct from the device_profiles class
-- id so a perf record never reads as if it came from the preview harness
PROFILES.consoleTenFoot.name = "consoleTenFoot"

-- floor first (it is the gate reference), then ascending capability
local ORDER = { "floorAndroid", "phone", "tablet", "desktop", "consoleTenFoot" }

function perf_profiles.list(): { string }
	return table.clone(ORDER)
end

function perf_profiles.get(name: string): Profile
	local p = PROFILES[name]
	assert(p ~= nil, `perf_profiles: unknown profile '{name}' (have: {table.concat(ORDER, ", ")})`)
	return p
end

-- write the profile into a LuauUI environment so the REAL solver renders what
-- that device sees, and input/display-sensitive views see the right facts.
-- Geometry + fact writes only — an attached renderer re-solves live (no
-- remount).
function perf_profiles.apply(env: any, profile: Profile): Profile
	env:set("viewportRect", { x = 0, y = 0, w = profile.viewport.w, h = profile.viewport.h })
	env:set("coreSafeInsets", table.clone(profile.insets))
	env:set("preferredInput", profile.preferredInput)
	env:set("capabilities", table.clone(profile.capabilities))
	env:set("displaySize", profile.displaySize)
	env:set("overscanInsets", table.clone(profile.overscanInsets))
	return profile
end

return perf_profiles
