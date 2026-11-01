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
	buttonHint: CatalogTypes.Builder,
	circleHint: CatalogTypes.Builder,
}

local function properties(values: Properties): Properties
	return values
end

local function entries(): { Properties }
	return {
		{ keyCode = Enum.KeyCode.ButtonA, label = "Buy" },
		{ keyCode = Enum.KeyCode.ButtonB, label = "Back" },
		{ keyCode = { Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1 }, label = "Tabs" },
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
					local hinted = c.Host.InputAction {
						Name = "LabSave",
						c.Host.InputBinding { KeyCode = Enum.KeyCode.F2, UIButton = nil },
					}
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
			return { inputs = { "Gamepad", "KeyboardAndMouse" }, entries = entries() }
		end,
		axes = { shared.sizes },
		states = {
			{ name = "gamepad only (the default)", props = properties { inputs = NONE } },
			{
				name = "a disabled action hides",
				props = function(c: Context)
					local list = entries()
					list[1] = { action = c.Host.InputAction { Name = "LabGuideBuy", Enabled = false }, label = "Buy" }
					return { entries = list }
				end,
			},
			{
				name = "written keys",
				props = properties { entries = { { keys = { { "Ctrl", "S" } }, label = "Save" } } },
			},
		},
	}
	local function sheetGuide(): Properties
		return { guide = { inputs = { "Gamepad", "KeyboardAndMouse" }, entries = entries() }, guideAlignment = "start" }
	end
	local function boost(c: Context): unknown
		return c.Host.InputAction {
			Name = "LabBoost",
			c.Host.InputBinding { KeyCode = Enum.KeyCode.ButtonX, UIButton = nil },
			c.Host.InputBinding { KeyCode = Enum.KeyCode.B, UIButton = nil },
		}
	end
	local function buttonHint(c: Context): Properties
		return { label = "Boost", shortcutHint = boost(c) }
	end
	local function circleHint(c: Context): Properties
		return { shape = "circle", icon = "flag", caption = "Boost", shortcutHint = boost(c) }
	end
	return {
		ShortcutHint = ShortcutHint,
		ButtonGuide = ButtonGuide,
		sheetGuide = sheetGuide,
		buttonHint = buttonHint,
		circleHint = circleHint,
	}
end
