--!strict
-- A platform fact sink with reversible developer preview overrides. Keep feeding
-- source while previewing so Automatic restores current facts, not a boot snapshot.
local profiles = require("../preview/device_profiles")
local environment_preview = {}
local KEYS = {
	"viewportRect",
	"coreSafeInsets",
	"deviceSafeInsets",
	"topbarInset",
	"topbarSafeInsets",
	"displaySize",
	"overscanInsets",
	"preferredInput",
	"capabilities",
	"viewingDistance",
}
local INPUTS = {
	pointer = {
		preferredInput = "KeyboardAndMouse",
		capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false },
	},
	touch = {
		preferredInput = "Touch",
		capabilities = { keyboard = false, mouse = false, touch = true, gamepad = false },
	},
	gamepad = {
		preferredInput = "Gamepad",
		capabilities = { keyboard = false, mouse = false, touch = false, gamepad = true },
	},
}
local function copy(value: any): any
	return if type(value) == "table" then table.clone(value) else value
end

function environment_preview.new(env: any): any
	local live = {}
	for _, key in KEYS do
		live[key] = copy(env:get(key):peek())
	end
	local profile, orientation, input = "automatic", "portrait", "automatic"
	local depth = 0
	local pending = {}
	local function apply(onlyKeys: any?)
		env:batch(function()
			local facts = table.clone(live)
			if profile ~= "automatic" then
				local name = if profile == "tv" then "console" else profile
				if profile == "phone" and orientation == "landscape" then
					name = "phoneLandscape"
				end
				if profile == "tablet" and orientation == "portrait" then
					name = "tabletPortrait"
				end
				local preset = profiles.get(name) :: any
				for key, value in preset.facts do
					facts[key] = value
				end
				facts.viewingDistance = if profile == "tv" then "ten-foot" else "near"
				-- Keep window-space coordinates and native hit testing at 1:1. A
				-- small host limits the preview; it never hides the reset controls.
				if profile == "phone" or profile == "tablet" then
					local viewport = table.clone(live.viewportRect)
					viewport.w = math.min(viewport.w, preset.viewport.w)
					viewport.h = math.min(viewport.h, preset.viewport.h)
					facts.viewportRect = viewport
				end
				facts.coreSafeInsets = preset.insets
				facts.deviceSafeInsets = { top = 0, bottom = 0, left = 0, right = 0 }
				facts.topbarSafeInsets = { top = 0, bottom = 0, left = 0, right = 0 }
				facts.topbarInset = { x = 0, y = 0, w = 0, h = 0 }
			end
			if input ~= "automatic" then
				for key, value in INPUTS[input] do
					facts[key] = value
				end
			end
			for _, key in KEYS do
				if onlyKeys == nil or profile ~= "automatic" or onlyKeys[key] then
					env:set(key, copy(facts[key]))
				end
			end
		end)
	end
	local source = {}
	function source:set(key: string, value: any)
		if table.find(KEYS, key) then
			live[key] = copy(value)
			pending[key] = true
			if depth == 0 then
				apply(pending)
				pending = {}
			end
		else
			env:set(key, value)
		end
	end
	function source:batch(body: () -> ())
		env:batch(function()
			depth += 1
			local ok, err = pcall(body)
			depth -= 1
			if depth == 0 then
				apply(pending)
				pending = {}
			end
			if not ok then
				error(err, 0)
			end
		end)
	end
	return {
		source = source,
		apply = function()
			apply()
		end,
		setProfile = function(value: string): boolean
			if not table.find({ "automatic", "desktop", "phone", "tablet", "tv" }, value) then
				return false
			end
			profile = value
			apply()
			return true
		end,
		setOrientation = function(value: string): boolean
			if value ~= "portrait" and value ~= "landscape" then
				return false
			end
			orientation = value
			apply()
			return true
		end,
		setInput = function(value: string): boolean
			if value ~= "automatic" and INPUTS[value] == nil then
				return false
			end
			input = value
			apply()
			return true
		end,
		dispose = function()
			profile, input = "automatic", "automatic"
			apply()
		end,
	}
end
return environment_preview
