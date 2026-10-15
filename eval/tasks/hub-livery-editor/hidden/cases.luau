--!strict

local Check = require("../../../../tools/play/host/check")
local Play = require("../../../../tools/play/host/play")
local S = require("../../extended/hidden/support")
local cases: { Play.Case } = {
	{
		id = "livery-preview-save",
		screen = "livery",
		run = function(qa, context)
			S.state(qa, "reset")
			S.tap(qa, context, "Livery")
			S.tap(qa, context, "Green", "Body color")
			S.tap(qa, context, "Violet", "Accent color")
			S.tap(qa, context, "Shade 50%")
			S.tap(qa, context, "Stars")
			Check.text(qa, context, "unsaved changes", "edits are dirty")
			Check.text(qa, context, "preview: body 120 accent 300 shade 50 stars", "preview follows all edits")
			Check.that(context, Check.field(S.state(qa), "livery", "decal") == "None", "preview has not saved")
			S.target(qa, context, "Save")
			qa:reveal({ exact = "car preview" })
			S.capture(qa, context, "livery")
			S.tap(qa, context, "Save")
			Check.that(context, Check.field(S.state(qa), "livery", "decal") == "Stars", "Save reaches game state")
			Check.that(context, Check.number(S.state(qa), "livery", "shade") == 0.5, "Save keeps shade")
			Check.that(
				context,
				math.abs(Check.number(S.state(qa), "livery", "body") - 1 / 3) < 0.001
					and math.abs(Check.number(S.state(qa), "livery", "accent") - 5 / 6) < 0.001,
				"Save keeps both colors"
			)
			S.back(qa, context, "Livery")
			S.tap(qa, context, "Livery")
			Check.text(qa, context, "preview: body 120 accent 300 shade 50 stars", "saved livery persists")
		end,
	},
	{
		id = "livery-discard-cancel",
		screen = "livery-discard",
		run = function(qa, context)
			S.tap(qa, context, "Flames")
			S.tap(qa, context, "Revert")
			Check.text(qa, context, "discard unsaved changes", "Revert asks first")
			S.target(qa, context, "Cancel")
			S.capture(qa, context, "livery-discard")
			S.tap(qa, context, "Cancel")
			Check.text(qa, context, "shade 50 flames", "Cancel keeps draft")
			S.tap(qa, context, "Revert")
			S.tap(qa, context, "Discard")
			Check.text(qa, context, "shade 50 stars", "Revert restores saved preview")
			S.tap(qa, context, "Checks")
			if qa.device.mode == "gamepad" then
				qa:press("Backspace")
			else
				S.tap(qa, context, "Close")
			end
			Check.text(qa, context, "discard unsaved changes", "leaving dirty editor asks first")
			S.tap(qa, context, "Discard")
			Check.gone(qa, context, { role = "button", exact = "save" }, "Discard returns to hub")
		end,
	},
}
return cases
