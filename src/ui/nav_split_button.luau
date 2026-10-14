--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local NavigationProps = require("./navigation_props")
local MenuItems = require("./nav_menu_items")

type Controls = {
	Menu: ControlTypes.MenuConstructor,
	SplitButton: ControlTypes.SplitButtonConstructor,
	Button: Types.Constructor<InputProps.ButtonProps, TextButton>,
}

return function(ctx: Types.Context, UI: Controls, surfaces: Nav.Surfaces, buildMenu: MenuItems.BuildMenu)
	local Host, Compose, read = ctx.Host, ctx.Compose, ctx.read
	local E, D2, D = ctx.types.Enum, ctx.types.UDim2, ctx.types.UDim
	UI.SplitButton = ctx.construct("SplitButton", function<V>(spec: NavigationProps.SplitButtonSpec<V>): Frame
		local input = surfaces.service("UserInputService")
		local preferred = if input
			then ctx.observe.PreferredInput(input) :: ComposeTypes.Readable<Enum.PreferredInput?>
			else Compose.cell(nil :: Enum.PreferredInput?)
		local touch = Compose.formula(function(use: ComposeTypes.Use)
			return use(preferred) == E.PreferredInput.Touch
		end)
		local opened = Compose.cell(false)
		local enabled = function(use: ComposeTypes.Use)
			return read(spec.enabled, use) ~= false and read(spec.busy, use) ~= true
		end
		local function primary()
			return UI.Button {
				Name = "Primary",
				appearance = "utility",
				label = spec.label,
				onActivate = spec.onActivate,
				enabled = spec.enabled,
				busy = spec.busy,
				shortcut = spec.shortcut,
			}
		end
		return Host.Frame(
			ctx.props(spec, { "label", "onActivate", "items", "enabled", "busy", "shortcut", "menuLabel" }, {
				Name = "SplitButton",
				BackgroundTransparency = 1,
				Size = D2.fromOffset(0, 0),
				AutomaticSize = E.AutomaticSize.XY,
				Compose.show(touch, function()
					local suppressEcho = false
					local trigger = UI.Button {
						Name = "Primary",
						Size = if spec.Size then D2.fromScale(1, 1) else nil,
						AutomaticSize = if spec.Size then E.AutomaticSize.None else nil,
						label = spec.label,
						trailingIcon = "chevron.down",
						enabled = spec.enabled,
						busy = spec.busy,
						onActivate = function()
							if suppressEcho then
								suppressEcho = false
								return
							end
							if spec.onActivate then
								spec.onActivate()
							end
						end,
					}
					return buildMenu({
						Name = "TouchAlternatives",
						Size = if spec.Size then D2.fromScale(1, 1) else nil,
						AutomaticSize = if spec.Size then E.AutomaticSize.None else nil,
						trigger = function(): GuiObject
							return trigger
						end,
						items = spec.items,
						enabled = enabled,
						isPresented = opened,
						triggers = { "longPress", "secondary", "keyboard", "gamepad" } :: { Nav.MenuTrigger },
						onOpen = function()
							suppressEcho = true
						end,
						onClose = function()
							suppressEcho = false
						end,
					}, true)
				end, function()
					local row = ctx.row({
						primary(),
						ctx.styled(
							Host.Frame "Divider" {
								BorderSizePixel = 0,
								Size = function(use: ComposeTypes.Use)
									return D2.fromOffset(ctx.metric("strokes.hairline", use), 0)
								end,
								Host.UIFlexItem({ ItemLineAlignment = E.ItemLineAlignment.Stretch }),
							},
							"divider"
						),
						UI.Menu {
							Name = "Alternatives",
							trigger = function(): GuiObject
								return UI.Button {
									Name = "Trigger",
									appearance = "utility",
									icon = "chevron.down",
									name = spec.menuLabel or "More options",
									help = spec.menuLabel or "More options",
									enabled = enabled,
									onActivate = function()
										opened:set(true)
									end,
								}
							end,
							items = spec.items,
							enabled = enabled,
							isPresented = opened,
						},
					}, { Name = "Split" })
					assert(row:FindFirstChildWhichIsA("UIListLayout")).Padding = D.new(0, 0)
					row:ResetPropertyToDefault("BackgroundTransparency")
					ctx.skin(ctx.styled(row, "control"), "control", {
						disabled = function(use: ComposeTypes.Use)
							return not enabled(use)
						end,
					})
					return row
				end),
			})
		)
	end)
end
