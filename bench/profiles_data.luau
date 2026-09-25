--!strict

local device_profiles = {}

export type Profile = {
	name: string,
	title: string,
	viewport: { w: number, h: number },
	insets: { top: number, bottom: number, left: number, right: number },

	facts: { [string]: any },
}

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

		name = "phone",
		title = "Phone portrait (389×762 camera)",
		viewport = { w = 389, h = 762 },
		insets = { top = 58, bottom = 0, left = 0, right = 0 },
		facts = TOUCH_FACTS,
	},
	phoneLandscape = {
		name = "phoneLandscape",
		title = "Phone landscape (749×368 camera)",
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

function device_profiles.apply(env: any, name: string): Profile
	local profile = PROFILES[name]
	assert(profile ~= nil, `unknown device profile '{name}' (have: {table.concat(ORDER, ", ")})`)
	env:set("viewportRect", { x = 0, y = 0, w = profile.viewport.w, h = profile.viewport.h })
	env:set("coreSafeInsets", table.clone(profile.insets))

	env:set("deviceSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })

	for key, value in profile.facts do
		env:set(key, if type(value) == "table" then table.clone(value) else value)
	end
	return profile
end

return device_profiles
