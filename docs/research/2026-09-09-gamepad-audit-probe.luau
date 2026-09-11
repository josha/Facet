-- Audit characterization, 2026-09-09. Prints current behavior; not acceptance criteria.
-- Run from the Facet root: lune run docs/research/2026-09-09-gamepad-audit-probe
local Facet = require("../../src")
local fake = require("../../tests/lib/fake_target")
local core = Facet.newCore()
local env = Facet.newEnvironment(core)
env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
env:set("preferredInput", "Gamepad")
env:set("capabilities", { gamepad = true, keyboard = false, mouse = false, touch = false })
local system = Facet.newActionSystem(core)
local pres = Facet.newPresenter(core, env, fake.new(), system)
local UI = Facet.UI
local function button(id)
	return UI.Button({ id = id, label = id, width = { type = "fixed", px = 240 }, height = { type = "fixed", px = 66 } })
end
pres.present(UI.Screen({
	id = "S",
	children = {
		UI.HStack({
			id = "Panes",
			gap = 80,
			children = {
				UI.VStack({ id = "Sidebar", gap = 12, children = { button("A"), button("B") } }),
				UI.VStack({ id = "Detail", gap = 12, children = { button("C"), button("D") } }),
			},
		}),
	},
}))
local start = "/S/Panes/Sidebar/A"
for _, key in { "DPadDown", "DPadRight" } do
	pres.focus.focusOn(start)
	system.deviceKey(key, true)
	system.deviceKey(key, false)
	print(key .. ": " .. start .. " -> " .. tostring(pres.focus.focused:get()))
end
local adaptive = require("../../src/layout/adaptive")
local menu = require("../../src/controls/menu_recipe")
print("Large plus touch: " .. adaptive.effectiveDisplaySize("Large", true))
print(
	"Roomy TV nav: "
		.. adaptive.navPlacement({
			sizeClass = "regular",
			heightClass = "medium",
			distanceProfile = "ten-foot",
			primary = "gamepad",
			displaySize = "Large",
		})
)
print(
	"Short TV nav: "
		.. adaptive.navPlacement({
			sizeClass = "regular",
			heightClass = "short",
			distanceProfile = "ten-foot",
			primary = "gamepad",
			displaySize = "Large",
		})
)
print("Gamepad long popup: " .. menu.resolvePresentation(12, "regular", false))
