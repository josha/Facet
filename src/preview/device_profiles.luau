--!strict
-- Device-profile presets for the Edit-mode preview harness (director Part-2
-- ws2): each profile resolves to environment geometry (viewportRect +
-- coreSafeInsets) so the REAL solver renders exactly what that device class
-- would see. Engine-free — the Studio harness (src/client/edit_preview) and
-- the durable plugin apply these; tests/preview.spec.luau pins the contract.

local device_profiles = {}

export type Profile = {
	name: string,
	title: string,
	viewport: { w: number, h: number },
	insets: { top: number, bottom: number, left: number, right: number },
	-- the full input/display fact set for the device class (input-paradigms
	-- expansion): applying a profile must flip affordances and presentation,
	-- not geometry alone — previewing "phone" means touch affordances,
	-- previewing "console" means gamepad + ten-foot
	facts: { [string]: any },
}

-- Ground truth (measured 2026-07-20, Studio iPhone 13 Pro emulator, both
-- orientations): the engine CAMERA viewport already excludes the notch and
-- home-indicator zones — Camera.ViewportSize IS the device-safe canvas — so
-- profiles must NOT model lateral/bottom safe areas as in-canvas insets.
-- The only in-canvas reserved region is the 58px CoreGui topbar, which is
-- exactly what GetGuiInset reports and what roblox_env binds. Portrait
-- camera 389×762 (device 389×843, notch 47 + home 34 outside); landscape
-- camera 749×368 (device 843×389, 47 both sides + home 21 outside).
-- shared fact shapes (cloned per apply so profiles never alias env state)
local NO_OVERSCAN = { top = 0, bottom = 0, left = 0, right = 0 }
local TOUCH_FACTS = {
	preferredInput = "Touch",
	capabilities = { keyboard = false, mouse = false, touch = true, gamepad = false },
	displaySize = "Small",
	overscanInsets = NO_OVERSCAN,
}
local DESKTOP_FACTS = {
	preferredInput = "KeyboardAndMouse",
	capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false },
	displaySize = "Medium",
	overscanInsets = NO_OVERSCAN,
}

local PROFILES: { [string]: Profile } = {
	phone = {
		-- notched phone, PORTRAIT — the hard case (director 2026-07-20)
		name = "phone",
		title = "Phone portrait (iPhone 13 Pro, 389×762 camera)",
		viewport = { w = 389, h = 762 },
		insets = { top = 58, bottom = 0, left = 0, right = 0 },
		facts = TOUCH_FACTS,
	},
	phoneLandscape = {
		name = "phoneLandscape",
		title = "Phone landscape (iPhone 13 Pro, 749×368 camera)",
		viewport = { w = 749, h = 368 },
		insets = { top = 58, bottom = 0, left = 0, right = 0 },
		facts = TOUCH_FACTS,
	},
	tablet = {
		name = "tablet",
		title = "Tablet landscape (1024×768)",
		viewport = { w = 1024, h = 768 },
		insets = { top = 58, bottom = 0, left = 0, right = 0 },
		facts = TOUCH_FACTS,
	},
	tabletPortrait = {
		name = "tabletPortrait",
		title = "Tablet portrait (768×1024)",
		viewport = { w = 768, h = 1024 },
		insets = { top = 58, bottom = 0, left = 0, right = 0 },
		facts = TOUCH_FACTS,
	},
	desktop = {
		name = "desktop",
		title = "Desktop (1280×720)",
		viewport = { w = 1280, h = 720 },
		insets = { top = 58, bottom = 0, left = 0, right = 0 },
		facts = DESKTOP_FACTS,
	},
	phoneNotchLandscape = {
		-- SYNTHETIC notched-landscape profile (native-substrate NS-A1): the
		-- Studio emulator's camera PRE-EXCLUDES the notch (measured
		-- docs/lessons/device-emulator-truths.md), so this profile exists to
		-- exercise the deviceSafeContent solver path headlessly with REAL-shaped
		-- device insets (iOS landscape: notch side + home indicator). A physical
		-- device confirms the live values (ledger row NS-P2).
		name = "phoneNotchLandscape",
		title = "Phone landscape w/ device-safe insets (synthetic notch 47px + home 21px)",
		viewport = { w = 844, h = 390 },
		insets = { top = 58, bottom = 0, left = 0, right = 0 },
		facts = {
			preferredInput = "Touch",
			capabilities = { keyboard = false, mouse = false, touch = true, gamepad = false },
			displaySize = "Medium",
			overscanInsets = NO_OVERSCAN,
			deviceSafeInsets = { top = 0, bottom = 21, left = 47, right = 47 },
		},
	},
	console = {
		-- console 10-foot (input-paradigms expansion): 1080p TV canvas,
		-- gamepad-primary, Large display class. Overscan margins are the
		-- tvOS-equivalent safe-area numbers from the 10-foot research
		-- (60pt top/bottom, 90pt left/right at 1080p) — TVs clip edges, so
		-- the ten-foot presentation insets content on all four sides
		-- (distinct from the mobile notch, which the camera pre-excludes).
		name = "console",
		title = "Console 10-foot (1920×1080 TV, gamepad)",
		viewport = { w = 1920, h = 1080 },
		insets = { top = 58, bottom = 0, left = 0, right = 0 },
		facts = {
			preferredInput = "Gamepad",
			capabilities = { keyboard = false, mouse = false, touch = false, gamepad = true },
			displaySize = "Large",
			overscanInsets = { top = 60, bottom = 60, left = 90, right = 90 },
		},
	},
}

local ORDER = { "phone", "phoneLandscape", "phoneNotchLandscape", "tablet", "tabletPortrait", "desktop", "console" }

function device_profiles.list(): { string }
	return table.clone(ORDER)
end

function device_profiles.get(name: string): Profile?
	return PROFILES[name]
end

-- writes the profile's geometry AND its input/display facts into a LuauUI
-- environment; any attached renderer re-solves live (rect-only writes for a
-- pure geometry change; fact flips may re-derive input-adaptive structure —
-- that is the point of previewing another device class)
function device_profiles.apply(env: any, name: string): Profile
	local profile = PROFILES[name]
	assert(profile ~= nil, `unknown device profile '{name}' (have: {table.concat(ORDER, ", ")})`)
	env:set("viewportRect", { x = 0, y = 0, w = profile.viewport.w, h = profile.viewport.h })
	env:set("coreSafeInsets", table.clone(profile.insets))
	-- device-safe insets are zero unless the profile declares them (facts loop
	-- below overrides); prevents a previously-applied notched profile leaking
	env:set("deviceSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	for key, value in profile.facts do
		env:set(key, if type(value) == "table" then table.clone(value) else value)
	end
	return profile
end

return device_profiles
