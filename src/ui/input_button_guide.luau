--!strict
local InputTypes = require("./input_types")
local Shared = require("./types")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local inputKit = require("./input_kit")
local keyGlyph = require("./input_key_glyph")
local ComposeTypes = require("../vendor/compose/core")

type Entry = InputTypes.ButtonGuideEntry
type Fields = { action: unknown, keys: unknown, keyCode: unknown, label: unknown }
type Shown = { [{}]: ComposeTypes.Readable<boolean> | boolean }

local KEYS = { "entries", "inputs", "controlSize", "Visible", "Selectable", "Active" }

return function(ctx: Shared.Context, UI: ControlTypes.Controls, kit: inputKit.Kit): ()
	local runtime, Host, Compose = ctx.runtime, ctx.Host, ctx.Compose
	local read, props = ctx.read, ctx.props
	local D2, E, UDim = ctx.types.UDim2, ctx.types.Enum, ctx.types.UDim
	local glyph = keyGlyph(ctx, kit.noKey)
	local function isKeyCode(value: unknown): boolean
		return (type(value) == "userdata" or type(value) == "table")
			and (value :: { EnumType: unknown }).EnumType == E.KeyCode
	end
	local function codesOf(value: unknown): { Enum.KeyCode }
		if isKeyCode(value) then
			return { value :: Enum.KeyCode }
		end
		assert(
			type(value) == "table" and #(value :: { unknown }) > 0,
			"Facet.ButtonGuide: keyCode must be a KeyCode or a nonempty list of KeyCodes"
		)
		for _, code in value :: { unknown } do
			assert(isKeyCode(code), "Facet.ButtonGuide: keyCode must be a KeyCode or a nonempty list of KeyCodes")
		end
		return value :: { Enum.KeyCode }
	end
	local function textOf(value: unknown): string
		if type(value) == "string" then
			return value
		end
		if type(value) == "table" and not Compose.isReadable(value) then
			local chords: { string } = {}
			for _, chord in value :: { unknown } do
				table.insert(chords, if type(chord) == "table" then table.concat(chord :: { string }, "+") else "?")
			end
			return table.concat(chords, "/")
		end
		return tostring(value)
	end
	local function keyOf(entry: Entry): unknown
		local fields = (entry :: unknown) :: Fields
		if fields.action ~= nil then
			return fields.action
		end
		if fields.keyCode ~= nil then
			local codes = codesOf(fields.keyCode)
			if #codes == 1 then
				return codes[1]
			end
			local names: { string } = {}
			for _, code in codes do
				table.insert(names, code.Name)
			end
			return "keyCode:" .. table.concat(names, ",")
		end
		return `keys:{textOf(fields.keys)}:{textOf(fields.label)}`
	end
	local function check(entries: unknown): { Entry }
		assert(type(entries) == "table", "Facet.ButtonGuide: entries must be a list of entries")
		local seen: { [unknown]: boolean } = {}
		for _, entry in entries :: { unknown } do
			assert(type(entry) == "table", "Facet.ButtonGuide: each entry must be a table")
			local fields = entry :: Fields
			local sources = (if fields.action ~= nil then 1 else 0)
				+ (if fields.keys ~= nil then 1 else 0)
				+ (if fields.keyCode ~= nil then 1 else 0)
			assert(sources == 1, "Facet.ButtonGuide: an entry takes one of action, keyCode or keys")
			assert(fields.label ~= nil, "Facet.ButtonGuide: an entry needs a label")
			local action = fields.action :: Instance?
			if action ~= nil then
				assert(
					action.IsA and action:IsA("InputAction"),
					"Facet.ButtonGuide: an entry action must be a native InputAction"
				)
				assert(not seen[action], "Facet.ButtonGuide: an action appears twice; list each command once")
				seen[action] = true
			elseif fields.keyCode ~= nil then
				for _, code in codesOf(fields.keyCode) do
					assert(not seen[code], "Facet.ButtonGuide: a key appears twice; list each command once")
					seen[code] = true
				end
			else
				local key = keyOf(entry :: Entry)
				assert(not seen[key], "Facet.ButtonGuide: an entry appears twice; list each command once")
				seen[key] = true
			end
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
		local function keyCodeHint(
			codes: { Enum.KeyCode },
			label: (ComposeTypes.Use) -> string,
			native: Shared.FrameNativeProps
		): Frame
			local capProps: Shared.FrameNativeProps = {
				Name = "Keys",
				Size = D2.fromOffset(0, 0),
				AutomaticSize = E.AutomaticSize.XY,
				BackgroundTransparency = if bare:peek() then 1 else 0,
				Host.UIListLayout({
					FillDirection = E.FillDirection.Horizontal,
					VerticalAlignment = E.VerticalAlignment.Center,
					SortOrder = E.SortOrder.LayoutOrder,
					Padding = function(use: ComposeTypes.Use): UDim
						return UDim.new(0, ctx.metric("space.xs", use))
					end,
				}),
			}
			for order, code in codes do
				local key = glyph("KeyCode", spec.controlSize, { key = code })
				runtime.decorate(key, { LayoutOrder = order })
				capProps[#capProps + 1] = key
			end
			local cap = ctx.styled(Host.Frame(capProps), "shortcut-hint")
			if bare:peek() then
				ctx.styled(cap, "shortcut-hint-bare")
			end
			local caption =
				ctx.styled(ctx.text({ Name = "Label", Text = label, AutomaticSize = E.AutomaticSize.XY }), "secondary")
			return ctx.row({ cap, caption }, native)
		end
		local function render(value: ComposeTypes.Readable<Entry>, index: ComposeTypes.Readable<number>): GuiObject
			local entry = value:peek()
			local fields = (entry :: unknown) :: Fields
			local action = entry.action
			local live: ComposeTypes.Readable<boolean>? = nil
			if action then
				local enabled, binding = ctx.observe.Enabled(action), ctx.observe.PreferredBinding(action)
				live = Compose.formula(function(use: ComposeTypes.Use): boolean
					return use(enabled) ~= false and use(binding) ~= nil
				end)
			end
			local token = {}
			local present = table.clone(shown:peek())
			present[token] = live or true
			shown:set(present)
			Compose.cleanup(function()
				local remaining = table.clone(shown:peek())
				remaining[token] = nil
				shown:set(remaining)
			end)
			local function label(use: ComposeTypes.Use): string
				return read(use(value).label, use)
			end
			local function order(use: ComposeTypes.Use): number
				return use(index)
			end
			local function visible(use: ComposeTypes.Use): boolean
				return live == nil or use(live)
			end
			if fields.keyCode ~= nil then
				return keyCodeHint(codesOf(fields.keyCode), label, {
					Name = "Entry",
					Size = D2.fromOffset(0, 0),
					AutomaticSize = E.AutomaticSize.XY,
					BackgroundTransparency = 1,
					LayoutOrder = order,
					Visible = visible,
				})
			end
			return hint(({
				Name = "Entry",
				action = action,
				keys = entry.keys,
				label = label,
				controlSize = spec.controlSize,
				cap = not bare:peek(),
				LayoutOrder = order,
				Visible = visible,
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
						key = keyOf,
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
					if live == true or use(live :: ComposeTypes.Readable<boolean>) then
						return true
					end
				end
				return false
			end,
		})
		return root
	end)
end
