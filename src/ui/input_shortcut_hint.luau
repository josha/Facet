--!strict
local inputKit = require("./input_kit")
local keyGlyph = require("./input_key_glyph")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local ComposeTypes = require("../vendor/compose/core")

return function(ctx: Shared.Context, UI: ControlTypes.Controls, kit: inputKit.Kit): ()
	local runtime, Host, Compose = ctx.runtime, ctx.Host, ctx.Compose
	local read, props = ctx.read, ctx.props
	local D2, E = ctx.types.UDim2, ctx.types.Enum
	local glyph = keyGlyph(ctx, kit.noKey)
	UI.ShortcutHint = ctx.construct(
		"ShortcutHint",
		function(spec: InputTypes.ShortcutHintImplementationProps): TextLabel | Frame
			assert((spec.action == nil) ~= (spec.keys == nil), "Facet.ShortcutHint: supply action or keys")
			assert(spec.action == nil or spec.separator == nil, "Facet.ShortcutHint: separator applies only to keys")
			assert(spec.cap == nil or type(spec.cap) == "boolean", "Facet.ShortcutHint: cap must be a boolean")
			local semantic = { "action", "keys", "separator", "controlSize", "cap" }
			local function capped<N>(node: N & Instance): N & Instance
				local styled = ctx.styled(node, "shortcut-hint")
				if spec.cap == false then
					ctx.styled(styled, "shortcut-hint-bare")
				end
				return styled
			end
			if spec.label ~= nil then
				assert(
					spec.labelPosition == nil or spec.labelPosition == "start" or spec.labelPosition == "end",
					"Facet.ShortcutHint: labelPosition must be start or end"
				)
				local keysHint = (UI.ShortcutHint :: unknown) :: (InputProps.ShortcutHintProps) -> TextLabel | Frame
				local hint = keysHint(({
					Name = "Keys",
					action = spec.action,
					keys = spec.keys,
					separator = spec.separator,
					controlSize = spec.controlSize,
					cap = spec.cap,
				} :: unknown) :: InputProps.ShortcutHintProps)
				local caption = ctx.styled(
					ctx.text({ Name = "Label", Text = spec.label, AutomaticSize = E.AutomaticSize.XY }),
					"secondary"
				)
				return ctx.row(
					if spec.labelPosition == "start" then { caption, hint } else { hint, caption },
					props(
						spec :: Shared.GuiObjectNativeProps,
						{ "action", "keys", "separator", "controlSize", "label", "labelPosition", "cap" },
						{
							Name = "ShortcutHint",
							Size = D2.fromOffset(0, 0),
							AutomaticSize = E.AutomaticSize.XY,
							BackgroundTransparency = 1,
						}
					) :: Shared.FrameNativeProps
				)
			end
			if spec.keys then
				local cap = capped(ctx.styled(
					Host.TextLabel(props(spec, semantic, {
						Text = function(use: ComposeTypes.Use)
							local chords: { { string } } = read(assert(spec.keys), use)
							assert(
								type(chords) == "table" and #chords > 0,
								"Facet.ShortcutHint: keys must be a nonempty list of chords"
							)
							local parts: { string } = {}
							for _, chord in chords do
								assert(
									type(chord) == "table" and #chord > 0,
									"Facet.ShortcutHint: chords cannot be empty"
								)
								for _, key in chord do
									assert(
										type(key) == "string" and key ~= "",
										"Facet.ShortcutHint: key names must be nonempty strings"
									)
								end
								table.insert(parts, table.concat(chord, "+"))
							end
							local separator = read(spec.separator, use) or " / "
							assert(
								type(separator) == "string" and separator ~= "",
								"Facet.ShortcutHint: separator must be a nonempty string"
							)
							if string.find(separator, "^%a+$") then
								separator = ` {separator} `
							end
							return table.concat(parts, separator)
						end,
						Size = function(use: ComposeTypes.Use)
							local side = ctx.controlSize(spec.controlSize, "iconSize", use) + 8
							return D2.fromOffset(side, side)
						end,
						AutomaticSize = E.AutomaticSize.XY,
						BackgroundTransparency = if spec.cap == false then 1 else 0,
						BorderSizePixel = 0,
						TextXAlignment = E.TextXAlignment.Center,
						Host.UIPadding({}),
					})),
					"Text"
				))
				ctx.textLayout(cap, nil, true)
				if spec.Size == nil then
					local bounds = ctx.layoutBounds(cap, ctx.layoutUnit(cap, "CapUnit"))
					runtime.decorate(cap, {
						Size = function(use: ComposeTypes.Use): UDim2
							local side = math.max(ctx.controlSize(spec.controlSize, "iconSize", use), use(bounds).Y) + 8
							return D2.fromOffset(side, side)
						end,
					})
				end
				return cap
			end
			local action = spec.action
			assert(
				action and action.IsA and action:IsA("InputAction"),
				"Facet.ShortcutHint: action must be a native InputAction"
			)
			local binding = ctx.observe.PreferredBinding(action)
			local p = props(spec :: Shared.GuiObjectNativeProps, semantic, {
				Size = D2.fromOffset(0, 0),
				AutomaticSize = E.AutomaticSize.XY,
				BackgroundTransparency = if spec.cap == false then 1 else 0,
			})
			p[#p + 1] = Compose.keyed({
				from = function(use: ComposeTypes.Use)
					local value = use(binding)
					local list: { InputBinding } = if value then { value } else {}
					return list
				end,
				render = function(_, _, current: InputBinding)
					return glyph("PreferredBinding", spec.controlSize, {
						key = (ctx.observe.KeyCode(current) :: unknown) :: ComposeTypes.Readable<Enum.KeyCode?>,
						name = (ctx.observe.DisplayName(current) :: unknown) :: ComposeTypes.Readable<string?>,
						primary = (
								ctx.observe.PrimaryModifier(current) :: unknown
							) :: ComposeTypes.Readable<Enum.KeyCode?>,
						secondary = (
								ctx.observe.SecondaryModifier(current) :: unknown
							) :: ComposeTypes.Readable<Enum.KeyCode?>,
						image = (ctx.observe.DisplayImage(current) :: unknown) :: ComposeTypes.Readable<Content?>,
					})
				end,
			})
			return capped(Host.Frame(p :: Shared.FrameNativeProps))
		end
	)
end
