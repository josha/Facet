--!strict
local InputTypes = require("./input_types")
local Shared = require("./types")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local ComposeTypes = require("../vendor/compose/core")

type Entry = InputTypes.ButtonGuideEntry
type Shown = { [{}]: ComposeTypes.Readable<unknown> | boolean }

local KEYS = { "entries", "inputs", "controlSize", "Visible", "Selectable", "Active" }

return function(ctx: Shared.Context, UI: ControlTypes.Controls): ()
	local runtime, Host, Compose = ctx.runtime, ctx.Host, ctx.Compose
	local read, props = ctx.read, ctx.props
	local D2, E, UDim = ctx.types.UDim2, ctx.types.Enum, ctx.types.UDim
	local function check(entries: unknown): { Entry }
		assert(type(entries) == "table", "Facet.ButtonGuide: entries must be a list of entries")
		for _, entry in entries :: { unknown } do
			assert(type(entry) == "table", "Facet.ButtonGuide: each entry must be a table")
			local fields = entry :: { action: unknown, keys: unknown, label: unknown }
			assert((fields.action == nil) ~= (fields.keys == nil), "Facet.ButtonGuide: an entry takes action or keys")
			assert(fields.label ~= nil, "Facet.ButtonGuide: an entry needs a label")
			local action = fields.action :: Instance?
			assert(
				action == nil or (action.IsA and action:IsA("InputAction")),
				"Facet.ButtonGuide: an entry action must be a native InputAction"
			)
		end
		return entries :: { Entry }
	end
	UI.ButtonGuide = ctx.construct("ButtonGuide", function(spec: InputTypes.ButtonGuideImplementationProps): Frame
		assert(spec.entries ~= nil, "Facet.ButtonGuide: entries is required")
		local inputs = ((spec.inputs :: unknown) or { "Gamepad" }) :: { unknown }
		assert(type(inputs) == "table" and #inputs > 0, "Facet.ButtonGuide: inputs must be a nonempty list")
		local accepted: { [string]: boolean } = {}
		for _, input in inputs do
			assert(input ~= "Touch", "Facet.ButtonGuide: a guide never shows on touch, where glyphs mean nothing")
			assert(
				input == "Gamepad" or input == "KeyboardAndMouse",
				"Facet.ButtonGuide: inputs takes Gamepad and KeyboardAndMouse"
			)
			accepted[input :: string] = true
		end
		local effective = ctx.effectiveInput()
		local bare = Compose.formula(function(use: ComposeTypes.Use): boolean
			return effective(use) == "Gamepad"
		end)
		local entries = Compose.formula(function(use: ComposeTypes.Use): { Entry }
			return check(read(spec.entries, use))
		end)
		local shown = Compose.cell({} :: Shown)
		local placed = Compose.cell(0)
		local hint = (UI.ShortcutHint :: unknown) :: (InputProps.ShortcutHintProps) -> TextLabel | Frame
		local function render(value: ComposeTypes.Readable<Entry>, index: ComposeTypes.Readable<number>): GuiObject
			local entry = value:peek()
			local action = entry.action
			local enabled = if action then ctx.observe.Enabled(action) else nil
			local token = {}
			local present = table.clone(shown:peek())
			present[token] = enabled or true
			shown:set(present)
			Compose.cleanup(function()
				local remaining = table.clone(shown:peek())
				remaining[token] = nil
				shown:set(remaining)
			end)
			return hint(({
				Name = "Entry",
				action = action,
				keys = entry.keys,
				label = function(use: ComposeTypes.Use): string
					return read(use(value).label, use)
				end,
				controlSize = spec.controlSize,
				cap = not bare:peek(),
				LayoutOrder = function(use: ComposeTypes.Use): number
					return use(index)
				end,
				Visible = function(use: ComposeTypes.Use): boolean
					return enabled == nil or use(enabled) ~= false
				end,
			} :: unknown) :: InputProps.ShortcutHintProps)
		end
		local p = props(spec :: Shared.FrameNativeProps, KEYS, {
			Name = "ButtonGuide",
			Size = D2.fromOffset(0, 0),
			AutomaticSize = E.AutomaticSize.XY,
			BackgroundTransparency = 1,
		})
		p.Selectable = false
		p.Active = false
		p[#p + 1] = Compose.keyed({
			from = function(use: ComposeTypes.Use): { boolean }
				return { use(bare) }
			end,
			render = function(): Frame
				return Host.Frame "Entries" {
					Size = D2.fromOffset(0, 0),
					AutomaticSize = E.AutomaticSize.XY,
					BackgroundTransparency = 1,
					Selectable = false,
					Host.UIListLayout({
						FillDirection = E.FillDirection.Horizontal,
						VerticalAlignment = E.VerticalAlignment.Center,
						SortOrder = E.SortOrder.LayoutOrder,
						Padding = function(use: ComposeTypes.Use): UDim
							return UDim.new(0, ctx.metric("space.m", use))
						end,
					}),
					Compose.keyed({
						from = entries,
						key = function(entry: Entry): unknown
							return entry.action or entry
						end,
						render = render,
					}),
				}
			end,
		})
		local root = Host.Frame(p :: Shared.FrameNativeProps)
		runtime.connect(root, "AncestryChanged", function()
			placed:set(placed:peek() + 1)
		end)
		runtime.decorate(root, {
			Visible = function(use: ComposeTypes.Use): boolean
				if read(spec.Visible, use) == false or read(ctx.config.buttonGuides, use) == false then
					return false
				end
				if not accepted[effective(use)] then
					return false
				end
				use(placed)
				if not ctx.withinModal(root, use) then
					return false
				end
				for _, live in use(shown) do
					if live == true or use(live :: ComposeTypes.Readable<unknown>) ~= false then
						return true
					end
				end
				return false
			end,
		})
		return root
	end)
end
