--!strict

local Check = require("../../../../tools/play/host/check")
local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")

type Case = Play.Case

export type Values = {
	musicVolume: number,
	effectsVolume: number,
	showDamageNumbers: boolean,
	cameraShake: boolean,
	graphics: string,
}

local function values(qa: QA.QA): Values
	local raw = qa:admin("state")
	return {
		musicVolume = tonumber(Check.field(raw, "values", "musicVolume")) or -1,
		effectsVolume = tonumber(Check.field(raw, "values", "effectsVolume")) or -1,
		showDamageNumbers = Check.field(raw, "values", "showDamageNumbers") == true,
		cameraShake = Check.field(raw, "values", "cameraShake") == true,
		graphics = tostring(Check.field(raw, "values", "graphics")),
	}
end

local function open(qa: QA.QA, context: Core.Context)
	Check.visible(qa, context, { role = "button", text = "settings" }, "the HUD shows a Settings button", 20)
	Check.tap(qa, context, { role = "button", text = "settings" }, "open the settings")
	Check.visible(qa, context, { text = "Music", clipped = true }, "the settings show the Music slider", 5)
end

local function close(qa: QA.QA, context: Core.Context)
	Check.tap(qa, context, { role = "button", text = "close" }, "close the settings")
	Check.gone(qa, context, { text = "Sound Effects" }, "the settings close", 4)
end

local function toggleState(qa: QA.QA, name: string, wanted: string): boolean
	local other = if wanted == "on" then "off" else "on"
	return Check.closer(
		qa,
		{ pattern = "^" .. wanted .. "$", near = name, clipped = true },
		{ pattern = "^" .. other .. "$", near = name, clipped = true }
	)
end

local function musicLowered(qa: QA.QA): boolean
	local now = values(qa).musicVolume
	return now >= 18 and now <= 42
end

local behavior: { Case } = {
	{
		id = "hud-settings-button",
		tier = "spec",
		run = function(qa, context)
			Check.visible(qa, context, { role = "button", text = "settings" }, "the HUD shows a Settings button", 20)
			qa:capture("1-hud")
		end,
	},
	{
		id = "opens-with-saved-values",
		tier = "spec",
		screen = "settings",
		shot = "2-settings",
		run = function(qa, context)
			open(qa, context)
			Check.text(qa, context, Check.count("60") .. "%%", "the Music slider shows the saved 60%", 4)
			Check.text(qa, context, Check.count("80") .. "%%", "the Sound Effects slider shows the saved 80%", 4)
			Check.that(context, toggleState(qa, "Camera Shake", "off"), "Camera Shake shows the saved Off state")
			Check.that(context, toggleState(qa, "Damage Numbers", "on"), "Damage Numbers shows the saved On state")
			qa:capture("2-settings")
			qa:dump("settings")
		end,
	},
	{
		id = "shows-controls",
		tier = "spec",
		run = function(qa, context)
			for _, words in { "Sprint", "Left Shift", "Interact", "Inventory" } do
				Check.that(
					context,
					qa:first({ text = words, clipped = true }) ~= nil,
					"the Controls section shows " .. words
				)
			end
		end,
	},
	{
		id = "moves-music-slider",
		tier = "spec",
		run = function(qa, context)
			if qa.device.mode == "gamepad" then
				local selected, detail = qa:gamepadSelect({ role = "selectable", near = "Music" })
				Check.that(context, selected, detail)
				for _ = 1, 6 do
					qa:press("DPadLeft")
				end
				Check.that(
					context,
					Check.eventually(4, function()
						return musicLowered(qa)
					end),
					"D-pad steps lower Music near 30 percent"
				)
			else
				qa:reveal({ text = "Music" })
				local slid, detail = qa:slide("Music", 0.3)
				Check.that(context, slid, "drag the Music slider: " .. detail)
				Check.text(qa, context, "%f[%d][234]%d%%", "the Music slider shows a value near 30%", 3)
			end
		end,
	},
	{
		id = "toggles-camera-shake",
		tier = "spec",
		run = function(qa, context)
			qa:reveal({ text = "Camera Shake" })
			Check.tap(qa, context, { role = "button", near = "Camera Shake" }, "turn on Camera Shake")
			Check.that(
				context,
				Check.eventually(3, function()
					return toggleState(qa, "Camera Shake", "on")
				end),
				"Camera Shake shows On"
			)
		end,
	},
	{
		id = "chooses-graphics",
		tier = "spec",
		screen = "changed",
		shot = "3-changed",
		run = function(qa, context)
			qa:reveal({ text = "High" })
			Check.tap(qa, context, { role = "button", exact = "high" }, "choose High graphics")
			qa:capture("3-changed")
			qa:dump("changed")
		end,
	},
	{
		id = "saves-to-server",
		tier = "spec",
		run = function(qa, context)
			close(qa, context)
			Check.that(
				context,
				Check.eventually(5, function()
					local now = values(qa)
					return now.cameraShake and now.graphics == "High" and musicLowered(qa)
				end),
				"the server saved Music near 30, Camera Shake On and High graphics"
			)
		end,
	},
	{
		id = "reopens-with-saved-values",
		tier = "spec",
		run = function(qa, context)
			open(qa, context)
			Check.text(qa, context, "%f[%d][234]%d%%", "the Music slider shows the saved value near 30%", 4)
			Check.that(context, toggleState(qa, "Camera Shake", "on"), "Camera Shake shows the saved On state")
		end,
	},
	{
		id = "follows-server-change",
		tier = "spec",
		run = function(qa, context)
			qa:admin("push", { effectsVolume = 25 })
			Check.text(
				qa,
				context,
				Check.count("25") .. "%%",
				"the Sound Effects slider follows a server change to 25%",
				4
			)
		end,
	},
	{
		id = "closes-settings",
		tier = "spec",
		run = function(qa, context)
			close(qa, context)
		end,
	},
}

return behavior
