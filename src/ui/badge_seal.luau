--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Content = require("./content_types")
local Media = require("./media_types")
local ComposeTypes = require("../vendor/compose/core")

local SEAL_STATUS: Media.Status = "error"

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
	UI.badged = function(
		host: GuiObject,
		value: Types.Value<Content.BadgeValue?>,
		options: Content.BadgedOptions?
	): Frame
		assert((host :: Instance?) and host:IsA("GuiObject"), "Facet UI.badged: host must be a GuiObject")
		assert(
			options == nil or type(options) == "table",
			"Facet UI.badged: options must be a table with direction and status"
		)
		local settings: Content.BadgedOptions = options or {}
		for key in (settings :: unknown) :: { [unknown]: unknown } do
			assert(key == "direction" or key == "status", `Facet UI.badged: unknown option '{tostring(key)}'`)
		end
		local direction, status = settings.direction, settings.status
		assert(
			direction == nil or direction == "ltr" or direction == "rtl",
			"Facet UI.badged: direction must be ltr or rtl"
		)
		assert(Compose.currentOwner() ~= nil, "Facet UI.badged: build a badged host inside runtime.mount")
		local function tone(use: ComposeTypes.Use): Media.Status
			local current: Media.Status? = read(status, use)
			return current or SEAL_STATUS
		end
		words(read(value))
		local text = function(use: ComposeTypes.Use): string
			return words(read(value, use))
		end
		local list = Host.UIListLayout({
			FillDirection = E.FillDirection.Vertical,
			SortOrder = E.SortOrder.LayoutOrder,
		})
		local wrapper = Host.Frame(host.Name .. "+badge")({
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = host.LayoutOrder,
			Size = D2.fromOffset(0, 0),
			AutomaticSize = E.AutomaticSize.XY,
			list,
			host,
			Host.Folder "Seal" {
				Host.Frame "Corner" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = D2.fromOffset(0, 0),
					Position = D2.fromScale(if direction == "rtl" then 0 else 1, 0),
					ZIndex = host.ZIndex + 2,
					Compose.show(function(use: ComposeTypes.Use): boolean
						return read(value, use) == true
					end, function()
						return UI.StatusIndicator({
							Name = "CornerDot",
							form = "dot",
							status = tone,
							AnchorPoint = V2.new(0.5, 0.5),
							Position = D2.fromScale(0, 0),
							ZIndex = host.ZIndex + 2,
						})
					end),
					Compose.show(function(use: ComposeTypes.Use): boolean
						return read(value, use) ~= true and text(use) ~= ""
					end, function()
						return UI.Badge({
							Name = "CornerBadge",
							label = text,
							status = tone,
							AnchorPoint = V2.new(0.5, 0.5),
							Position = D2.fromScale(0, 0),
							ZIndex = host.ZIndex + 2,
						})
					end),
				},
			},
		})
		return wrapper
	end
end
