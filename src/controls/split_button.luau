--!strict
--[[ SPLIT BUTTON — a primary action with a menu of alternatives, in the form
	the primary interaction class wants (picker round, 2026-09-11).

	  pointer / gamepad   ONE plate, two focus stops: the primary Button and a
	                      chevron segment joined edge to edge across a hairline
	                      (the desktop split button). Opening the menu never
	                      runs the primary action.
	  touch               ONE button. A tap runs the primary action; a LONG
	                      PRESS opens the menu (the phone's own `Menu` with a
	                      primary action). No chevron cell: a thumb-sized
	                      secondary segment beside a full-width action is the
	                      desktop control transplanted, and it read as one on
	                      every phone screenshot that led here.

	The two forms are two `UI.When` branches over the surface's live interaction
	class, so a hybrid that gains a mouse mid-session gets the split and loses it
	again on the next touch. Both forms share the Menu's anchored surfaces, focus
	restoration and dismissal policy; the touch form's menu also keeps the
	right-click, context-key and gamepad triggers, so a hybrid never loses a way
	in. `busy` and `shortcut` ride `Controls.Button` in the split form; the touch
	form's button is a plain `UI.Button` (a long-press trigger and a control's own
	contribution cannot both own one node), so it takes `enabled`/`busy` as one
	memo and no shortcut. ]]
local guard = require("../spec_guard")
local contract = require("../class_contract")
local selection = require("../selection_model")
local chrome = require("../tokens/chrome_slots")
local themePackage = require("../themes/package")
local surfaceEnv = require("../env/surface_env")
local menuRecipe = require("./menu_recipe")
local split = {}
local KEYS = guard.keySet({ "id", "label", "onActivate", "items", "enabled", "busy", "shortcut", "env", "menuLabel" })
-- the four triggers a touch form keeps: everything but the tap, which is the action
local TOUCH_TRIGGERS = table.freeze({ "longPress", "secondary", "keyboard", "gamepad" })
function split.build(Facet, core, spec)
	guard.assertKnownKeys("Controls.SplitButton", spec, KEYS, "spec")
	local scope = core:scope("split-button")
	local UI = Facet.UI
	local id = spec.id or "SplitButton"
	local enabled = scope:own(core:memo(function(use)
		return contract.enabledIn(use, spec.enabled) and selection.read(spec.busy, use) ~= true
	end))
	local env = surfaceEnv.resolve(
		"Controls.SplitButton",
		id,
		core,
		spec.env,
		"the touch form is one button with a long-press menu; the pointer form is a split"
	)
	local touchPrimary = scope:own(core:memo(function(use)
		return menuRecipe.touchPrimary(use(env:get("interactionClasses")))
	end))
	local pointerForm = scope:own(core:memo(function(use)
		return not use(touchPrimary)
	end))
	local live: any = nil
	local function splitForm(branchScope: any): any
		local primary = branchScope:own(Facet.Controls.Button(core, {
			id = "Primary",
			label = spec.label,
			width = UI.fill(),
			onActivate = spec.onActivate,
			enabled = spec.enabled,
			busy = spec.busy,
			shortcut = spec.shortcut,
		}))
		local menu = branchScope:own(Facet.Controls.Menu(core, {
			id = "Menu",
			trigger = UI.Button({
				id = "Menu",
				label = spec.menuLabel or "More options",
				width = { type = "minMax", min = "targetSizes.minimum" },
				height = { type = "fill", weight = 1 },
				children = {
					chrome.attachHint(
						UI.Text({ text = themePackage.iconGlyph("chevron.down") or "v", textSize = "control" }),
						{ icon = "chevron.down", iconSize = "small" }
					),
				},
				enabled = enabled,
			}),
			items = spec.items,
			env = spec.env,
		}))
		live = { primary = primary, menu = menu, form = "split" }
		branchScope:own(function()
			if live ~= nil and live.menu == menu then
				live = nil
			end
		end)
		-- the two segments share ONE silhouette: square where they meet, the
		-- theme's radius everywhere else (`UI.corners` is the modifier, so the
		-- primary keeps every contribution `Controls.Button` attached)
		return UI.HStack({
			id = "Split",
			gap = 0,
			width = UI.fill(),
			children = {
				UI.corners(primary.blueprint, { topRight = 0, bottomRight = 0 }),
				UI.Divider({ height = { type = "fill", weight = 1 } }),
				UI.corners(menu.blueprint, { topLeft = 0, bottomLeft = 0 }),
			},
		})
	end
	local function touchForm(branchScope: any): any
		local menu = branchScope:own(Facet.Controls.Menu(core, {
			id = "Menu",
			trigger = UI.Button({
				id = "Primary",
				label = spec.label,
				width = UI.fill(),
				onActivate = spec.onActivate,
				enabled = enabled,
			}),
			triggers = table.clone(TOUCH_TRIGGERS),
			items = spec.items,
			env = spec.env,
		}))
		live = { menu = menu, form = "single" }
		branchScope:own(function()
			if live ~= nil and live.menu == menu then
				live = nil
			end
		end)
		return menu.blueprint
	end
	local blueprint = UI.VStack({
		id = id,
		width = UI.fill(),
		children = {
			UI.When({ id = "Split", condition = pointerForm, thenView = splitForm }),
			UI.When({ id = "Single", condition = touchPrimary, thenView = touchForm }),
		},
	})
	local function dump()
		return {
			schema = "facet-split_button-dump/1",
			form = if live ~= nil then live.form else (if touchPrimary:get() then "single" else "split"),
			primary = if live ~= nil and live.primary ~= nil then live.primary.dump() else nil,
			menu = if live ~= nil then live.menu.dump() else nil,
		}
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
