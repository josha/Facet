--!strict
local guard = require("../spec_guard")
local contract = require("../class_contract")
local selection = require("../selection_model")
local chrome = require("../tokens/chrome_slots")
local themePackage = require("../themes/package")
local split = {}
local KEYS = guard.keySet({ "id", "label", "onActivate", "items", "enabled", "busy", "shortcut", "env", "menuLabel" })
function split.build(Facet, core, spec)
	guard.assertKnownKeys("Controls.SplitButton", spec, KEYS, "spec")
	local scope = core:scope("split-button")
	local UI = Facet.UI
	local enabled = scope:own(core:memo(function(use)
		return contract.enabledIn(use, spec.enabled) and selection.read(spec.busy, use) ~= true
	end))
	local primary = Facet.Controls.Button(core, {
		id = "Primary",
		label = spec.label,
		width = UI.fill(),
		onActivate = spec.onActivate,
		enabled = spec.enabled,
		busy = spec.busy,
		shortcut = spec.shortcut,
	})
	scope:own(primary)
	local menu = Facet.Controls.Menu(core, {
		id = spec.id or "SplitButton",
		trigger = UI.Button({
			id = "Menu",
			label = spec.menuLabel or "More options",
			width = { type = "minMax", min = "targetSizes.minimum" },
			height = { type = "minMax", min = "targetSizes.minimum" },
			children = {
				chrome.attachHint(
					UI.Text({ text = themePackage.iconGlyph("chevron.down") or "v", textSize = "control" }),
					{ icon = "chevron.down" }
				),
			},
			enabled = enabled,
		}),
		items = spec.items,
		env = spec.env,
	})
	scope:own(menu)
	local blueprint = UI.HStack({
		id = spec.id or "SplitButton",
		gap = "xs",
		width = UI.fill(),
		children = { primary.blueprint, UI.Divider({ height = { type = "fill", weight = 1 } }), menu.blueprint },
	})
	local function dump()
		return { schema = "facet-split_button-dump/1", primary = primary.dump(), menu = menu.dump() }
	end
	return {
		blueprint = blueprint,
		dump = dump,
		dispose = function()
			scope:dispose()
		end,
	}
end
return split
