--!strict

local Check = require("../../../../tools/play/host/check")
local Play = require("../../../../tools/play/host/play")
local S = require("../../extended/hidden/support")
local cases: { Play.Case } = {
	{
		id = "party-search-clear",
		tier = "spec",
		screen = "party-empty",
		run = function(qa, context)
			S.tap(qa, context, "Party")
			for _, presence in { "Online", "In race", "Offline" } do
				Check.text(qa, context, string.lower(presence), "presence is readable")
			end
			local ok, detail = qa:typeText({ role = "input" }, "MIRA")
			Check.that(context, ok, detail)
			Check.text(qa, context, "mira", "search ignores case")
			Check.gone(qa, context, { text = "Tess", clipped = true }, "search filters rows")
			ok, detail = qa:typeText({ role = "input" }, "zzzz")
			Check.that(context, ok, detail)
			Check.text(qa, context, "no friends match", "empty search explains result")
			S.target(qa, context, "Clear")
			S.capture(qa, context, "party-empty")
			S.tap(qa, context, "Clear")
			Check.visible(qa, context, { text = "Tess", clipped = true }, "Clear restores full list")
		end,
	},
	{
		id = "party-invite-outcomes",
		tier = "spec",
		screen = "party-invite",
		run = function(qa, context)
			local offline = Check.visible(
				qa,
				context,
				{ role = "button", exact = "invite", near = "Tess" },
				"offline friend has an action"
			)
			Check.that(context, not offline.interactable, "offline friend cannot be invited")
			S.tap(qa, context, "Invite", "Mira")
			Check.visible(qa, context, { exact = "pending", near = "Mira" }, "invite is pending")
			Check.visible(qa, context, { exact = "accepted", near = "Mira" }, "invite is accepted", 5)
			Check.text(qa, context, "party:.*mira", "accepted friend joins strip")
			S.tap(qa, context, "Invite", "Sol")
			Check.visible(qa, context, { exact = "pending", near = "Sol" }, "second invite is pending")
			Check.visible(qa, context, { exact = "declined", near = "Sol" }, "second invite is declined", 5)
			Check.absent(qa, context, "party:.*sol", "declined friend does not join")
			S.capture(qa, context, "party-invite")
			S.back(qa, context, "Party")
		end,
	},
}
return cases
