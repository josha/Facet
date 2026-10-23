--!strict
local CatalogTypes = require("./catalog_types")
type Context = CatalogTypes.Context
type Properties = CatalogTypes.Properties
type PageDefinition = CatalogTypes.PageDefinition

export type Shared = { sizes: CatalogTypes.Axis, none: Properties }
export type Pages = {
	ShortcutHint: PageDefinition,
	ButtonGuide: PageDefinition,
	sheetGuide: CatalogTypes.Builder,
}

local function properties(values: Properties): Properties
	return values
end

local function action(c: Context, name: string, key: Enum.KeyCode, enabled: boolean): InputAction
	return c.Host.InputAction({
		Name = name,
		Enabled = enabled,
		c.Host.InputBinding({ KeyCode = key }),
	})
end

local function entries(c: Context, buyEnabled: boolean): { Properties }
	return {
		{ action = action(c, "LabGuideBuy", Enum.KeyCode.ButtonA, buyEnabled), label = "Buy" },
		{ action = action(c, "LabGuideBack", Enum.KeyCode.ButtonB, true), label = "Back" },
		{ keys = { { "LB" }, { "RB" } }, label = "Tabs" },
	}
end

return function(shared: Shared): Pages
	local NONE = shared.none
	local ShortcutHint: PageDefinition = {
		family = "actions",
		alias = "Shortcut",
		purpose = "Shows the key or button for an action, adapting to the live input device.",
		alternatives = "Button.shortcut to bind the key on the action itself.",
		scenarios = { "shortcut_hint" },
		snippet = 'UI.ShortcutHint { keys = { { "Ctrl", "S" } } }',
		base = function()
			return { keys = { { "Ctrl", "S" } } }
		end,
		axes = { shared.sizes },
		states = {
			{
				name = "action (device-adaptive)",
				props = function(c: Context)
					local hinted = c.Host.InputAction({
						Name = "LabSave",
						c.Host.InputBinding({ KeyCode = Enum.KeyCode.F2, UIButton = nil }),
					})
					return { keys = NONE, action = hinted }
				end,
			},
			{ name = "alternatives", props = properties { keys = { { "Ctrl", "S" }, { "F2" } }, separator = " or " } },
			{ name = "label after", props = properties { label = "Save" } },
			{ name = "label before", props = properties { label = "Save", labelPosition = "start" } },
			{ name = "no cap", props = properties { cap = false } },
		},
		valid = function(p: Properties)
			return not (p.action ~= nil and p.keys ~= nil)
		end,
	}
	local ButtonGuide: PageDefinition = {
		family = "actions",
		alias = "ButtonGuide · button legend",
		purpose = "A console legend for commands without a control of their own; a readout, never a focus stop.",
		alternatives = "ShortcutHint with cap = false on a control that carries its own command.",
		snippet = 'UI.ButtonGuide { entries = { { action = buy, label = "Buy" } } }',
		base = function(c: Context)
			return { inputs = { "Gamepad", "KeyboardAndMouse" }, entries = entries(c, true) }
		end,
		axes = { shared.sizes },
		states = {
			{ name = "gamepad only (the default)", props = properties { inputs = NONE } },
			{
				name = "Buy disabled: the entry hides",
				props = function(c: Context)
					return { entries = entries(c, false) }
				end,
			},
		},
	}
	local function sheetGuide(c: Context): Properties
		return { guide = { inputs = { "Gamepad", "KeyboardAndMouse" }, entries = entries(c, true) } }
	end
	return { ShortcutHint = ShortcutHint, ButtonGuide = ButtonGuide, sheetGuide = sheetGuide }
end
