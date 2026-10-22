--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Content = require("./content_types")
local ComposeTypes = require("../vendor/compose/core")
local layoutKit = require("./layout_kit")

return function(ctx: Types.Context, UI: ControlTypes.BuilderControls): ()
	local Host, Compose, read = ctx.Host, ctx.Compose, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local function words(value: Content.BadgeValue?): string
		if value == true then
			return "•"
		elseif type(value) == "number" then
			assert(
				value == value and value % 1 == 0 and value >= 0,
				"Facet UI.badged: a count must be a whole number of 0 or more"
			)
			return if value > 99 then "99+" elseif value == 0 then "" else tostring(value)
		elseif type(value) == "string" then
			return value
		end
		assert(value == nil or value == false, "Facet UI.badged: value must be a string, a count, true, false or nil")
		return ""
	end
	UI.badged = function(host: GuiObject, value: Types.Value<Content.BadgeValue?>, direction: ("ltr" | "rtl")?): Frame
		assert((host :: Instance?) and host:IsA("GuiObject"), "Facet UI.badged: host must be a GuiObject")
		assert(
			direction == nil or direction == "ltr" or direction == "rtl",
			"Facet UI.badged: direction must be ltr or rtl"
		)
		assert(Compose.currentOwner() ~= nil, "Facet UI.badged: build a badged host inside runtime.mount")
		words(read(value))
		local text = function(use: ComposeTypes.Use): string
			return words(read(value, use))
		end
		local list = Host.UIListLayout({
			FillDirection = E.FillDirection.Vertical,
			SortOrder = E.SortOrder.LayoutOrder,
			HorizontalFlex = E.UIFlexAlignment.Fill,
		})
		local wrapper = Host.Frame(host.Name .. "+badge")({
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = host.LayoutOrder,
			Size = D2.fromOffset(0, 0),
			AutomaticSize = E.AutomaticSize.XY,
			list :: Types.Child,
			host :: Types.Child,
			Host.Folder "Seal" {
				Host.Frame "Corner" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = D2.fromOffset(0, 0),
					Position = D2.fromScale(if direction == "rtl" then 0 else 1, 0),
					ZIndex = host.ZIndex + 2,
					Compose.show(function(use: ComposeTypes.Use): boolean
						return text(use) ~= ""
					end, function()
						return UI.Badge({
							Name = "CornerBadge",
							label = text,
							AnchorPoint = V2.new(0.5, 0.5),
							Position = D2.fromScale(0, 0),
							ZIndex = host.ZIndex + 2,
						})
					end),
				},
			} :: Types.Child,
		})
		layoutKit.of(ctx).regrow(wrapper, list)
		return wrapper
	end
end
