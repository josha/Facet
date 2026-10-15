--!strict

local Check = require("../../../../tools/play/host/check")
local Play = require("../../../../tools/play/host/play")
local S = require("../../extended/hidden/support")
local cases: { Play.Case } = {
	{
		id = "upgrades-insufficient",
		tier = "spec",
		screen = "upgrades",
		run = function(qa, context)
			qa:admin("wallet", { coins = 1000, gems = 0 })
			S.tap(qa, context, "Upgrades")
			Check.text(qa, context, "speed level 0", "base level is visible")
			qa:reveal({ role = "button", exact = "upgrade speed" })
			local buy =
				Check.visible(qa, context, { role = "button", exact = "upgrade speed" }, "upgrade has an action")
			Check.that(context, not buy.interactable, "missing Gems disables purchase even with Coins")
			Check.text(qa, context, "100 coins %+ 5 gems", "both costs are visible")
			S.capture(qa, context, "upgrades")
			S.back(qa, context, "Upgrades")
		end,
	},
	{
		id = "upgrades-confirm-cancel-purchase",
		tier = "spec",
		screen = "upgrade-confirm",
		run = function(qa, context)
			qa:admin("wallet", { coins = 1000, gems = 50 })
			S.tap(qa, context, "Upgrades")
			S.tap(qa, context, "Upgrade Speed")
			S.target(qa, context, "Cancel")
			S.capture(qa, context, "upgrade-confirm")
			S.tap(qa, context, "Cancel")
			Check.that(context, Check.number(S.state(qa), "wallet", "Coins") == 1000, "Cancel spends nothing")
			S.tap(qa, context, "Upgrade Speed")
			S.tap(qa, context, "Confirm")
			Check.that(
				context,
				Check.number(S.state(qa), "wallet", "Coins") == 900
					and Check.number(S.state(qa), "wallet", "Gems") == 45,
				"purchase charges both currencies once"
			)
			Check.text(qa, context, "speed level 1 / 3 / 60%%", "stat bar readout updates")
			Check.text(qa, context, "200 coins %+ 10 gems", "next upgrade price follows its level")
			S.tap(qa, context, "Aero Kart")
			Check.text(qa, context, "speed level 0", "another kart has separate levels")
			S.tap(qa, context, "Rookie Kart")
			Check.text(qa, context, "speed level 1", "first kart keeps its level")
			S.back(qa, context, "Upgrades")
		end,
	},
}
return cases
