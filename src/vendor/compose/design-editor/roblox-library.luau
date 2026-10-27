--!strict

local UI = require "./ui"
local Environment = require "./environment"

local Compose = require "../core"
local Design = require "../design"

type Resolved = Design.Resolved
type Props = { [string]: Resolved }

return function(runtime: Compose.Runtime, environment: Environment.Environment): Design.Library
	local ui = UI.create(runtime, environment, true)
	local FONT = ui.values.font("rbxasset://fonts/families/BuilderSans.json", "Medium")

	local function color(text: string): unknown?
		if string.match(text, "^#%x%x%x%x%x%x$") then
			return ui.hex(text)
		end
		return nil
	end

	local function textOf(value: Design.Literal?): string?
		if type(value) == "string" then
			return value
		elseif type(value) == "number" or type(value) == "boolean" then
			return tostring(value)
		end
		return nil
	end

	local function numberOf(value: Design.Literal?): number?
		return if type(value) == "number" then value else nil
	end

	local function apply(property: Resolved?, set: (Design.Literal?) -> ())
		if property == nil then
			return
		end
		local readable = property.readable
		if readable then
			Compose.watch(function(use: Compose.Use)
				set(use(readable))
			end)
		else
			set(property.literal)
		end
	end

	local function parentChildren(container: Compose.Node, children: { unknown })
		for _, child in children do
			if child ~= nil then
				ui.set(child, "Parent", container)
			end
		end
	end

	local function sized(props: Props, instance: Compose.Node)
		ui.set(instance, "BackgroundTransparency", 1)
		local width, height = 0, 0
		local fillWidth, fillHeight = false, false
		apply(props.width, function(value: Design.Literal?)
			width = numberOf(value) or 0
		end)
		apply(props.height, function(value: Design.Literal?)
			height = numberOf(value) or 0
		end)
		apply(props.fillWidth, function(value: Design.Literal?)
			fillWidth = value == true
		end)
		apply(props.fillHeight, function(value: Design.Literal?)
			fillHeight = value == true
		end)
		ui.set(
			instance,
			"Size",
			ui.values.udim2(if fillWidth then 1 else 0, width, if fillHeight then 1 else 0, height)
		)
		if width == 0 and not fillWidth then
			ui.set(
				instance,
				"AutomaticSize",
				if height == 0 and not fillHeight
					then ui.values.enum("AutomaticSize", "XY")
					else ui.values.enum("AutomaticSize", "X")
			)
		elseif height == 0 and not fillHeight then
			ui.set(instance, "AutomaticSize", ui.values.enum("AutomaticSize", "Y"))
		end
		apply(props.background, function(value: Design.Literal?)
			local parsed = if type(value) == "string" then color(value) else nil
			if parsed then
				ui.set(instance, "BackgroundColor3", parsed)
				ui.set(instance, "BackgroundTransparency", 0)
			else
				ui.set(instance, "BackgroundTransparency", 1)
			end
		end)
		apply(props.Visible, function(value: Design.Literal?)
			ui.set(instance, "Visible", value ~= false)
		end)
	end

	local box: { [string]: Design.Field } = {
		width = { type = "number", tokens = true, group = "Layout", order = 1 },
		height = { type = "number", tokens = true, group = "Layout", order = 2 },
		fillWidth = { type = "boolean", group = "Layout", order = 3 },
		fillHeight = { type = "boolean", group = "Layout", order = 4 },
		background = { type = "color", group = "Fill", order = 1 },
		Visible = { type = "boolean", group = "Fill", order = 2, default = true },
	}

	local function with(extra: { [string]: Design.Field }): { [string]: Design.Field }
		local fields = table.clone(box)
		for key, field in extra do
			fields[key] = field
		end
		return fields
	end

	type TextSetters = { text: (string) -> (), size: (number) -> (), color: (unknown) -> () }

	local function textual(props: Props, set: TextSetters)
		apply(props.text, function(value: Design.Literal?)
			set.text(textOf(value) or "")
		end)
		apply(props.textSize, function(value: Design.Literal?)
			set.size(numberOf(value) or 16)
		end)
		apply(props.textColor, function(value: Design.Literal?)
			local parsed = if type(value) == "string" then color(value) else nil
			set.color(parsed or ui.rgb(235, 238, 242))
		end)
	end

	local stackDefaults: { [string]: Design.Literal } = { direction = "vertical", gap = 8, fillWidth = true }
	local textDefaults: { [string]: Design.Literal } = { text = "Text" }
	local buttonDefaults: { [string]: Design.Literal } = { text = "Button", background = "#3581F7" }
	local listDefaults: { [string]: Design.Literal } = { fillWidth = true, height = 240, gap = 4 }

	local library: Design.Library = {
		name = "Roblox",
		containerKind = "Stack",
		parameter = "Host",
		parameterType = "nil",
		prelude = {},
		returnType = "GuiObject",
		readable = "Compose.ReadOnlyValue",
		cell = "Compose.Cell",
		token = "tokens",
		kinds = {
			Frame = {
				fields = box,
				children = "list",
				call = "Design.Frame",
				build = function(props: Props, children: { unknown }): unknown
					local frame = ui.new "Frame"
					ui.set(frame, "BorderSizePixel", 0)
					sized(props, frame)
					parentChildren(frame, children)
					return frame
				end,
			},
			Stack = {
				fields = with {
					direction = {
						type = "choice",
						options = { "vertical", "horizontal" },
						group = "Auto layout",
						order = 1,
					},
					gap = { type = "number", tokens = true, group = "Auto layout", order = 2 },
					padding = { type = "number", tokens = true, group = "Auto layout", order = 3 },
				},
				defaults = stackDefaults,
				children = "list",
				call = "Design.Stack",
				build = function(props: Props, children: { unknown }): unknown
					local frame = ui.new "Frame"
					ui.set(frame, "BorderSizePixel", 0)
					sized(props, frame)
					local layout = ui.new "UIListLayout"
					ui.set(layout, "SortOrder", ui.values.enum("SortOrder", "LayoutOrder"))
					apply(props.direction, function(value: Design.Literal?)
						ui.set(
							layout,
							"FillDirection",
							if value == "horizontal"
								then ui.values.enum("FillDirection", "Horizontal")
								else ui.values.enum("FillDirection", "Vertical")
						)
					end)
					apply(props.gap, function(value: Design.Literal?)
						ui.set(layout, "Padding", ui.values.udim(0, numberOf(value) or 0))
					end)
					ui.set(layout, "Parent", frame)
					local padding = ui.new "UIPadding"
					apply(props.padding, function(value: Design.Literal?)
						local inset = ui.values.udim(0, numberOf(value) or 0)
						ui.set(padding, "PaddingTop", inset)
						ui.set(padding, "PaddingBottom", inset)
						ui.set(padding, "PaddingLeft", inset)
						ui.set(padding, "PaddingRight", inset)
					end)
					ui.set(padding, "Parent", frame)
					for order, child in children do
						if ui.isA(child, "GuiObject") then
							ui.set(child, "LayoutOrder", order)
						end
					end
					parentChildren(frame, children)
					return frame
				end,
			},
			Text = {
				fields = with {
					text = { type = "string", group = "Text", order = 1 },
					textSize = { type = "number", tokens = true, group = "Text", order = 2 },
					textColor = { type = "color", group = "Text", order = 3 },
				},
				defaults = textDefaults,
				children = "none",
				call = "Design.Text",
				build = function(props: Props): unknown
					local label = ui.new "TextLabel"
					sized(props, label)
					ui.set(label, "BackgroundTransparency", 1)
					ui.set(label, "FontFace", FONT)
					ui.set(label, "TextSize", 16)
					ui.set(label, "TextColor3", ui.rgb(235, 238, 242))
					textual(props, {
						text = function(text: string)
							ui.set(label, "Text", text)
						end,
						size = function(size: number)
							ui.set(label, "TextSize", size)
						end,
						color = function(value: unknown)
							ui.set(label, "TextColor3", value)
						end,
					})
					return label
				end,
			},
			Button = {
				fields = with {
					text = { type = "string", group = "Text", order = 1 },
					textSize = { type = "number", tokens = true, group = "Text", order = 2 },
					textColor = { type = "color", group = "Text", order = 3 },
					onActivate = { type = "event", group = "Interaction", order = 1 },
				},
				defaults = buttonDefaults,
				children = "none",
				call = "Design.Button",
				build = function(props: Props): unknown
					local button = ui.new "TextButton"
					ui.set(button, "AutoButtonColor", true)
					sized(props, button)
					ui.set(button, "FontFace", FONT)
					ui.set(button, "TextSize", 16)
					ui.set(button, "TextColor3", ui.rgb(255, 255, 255))
					ui.set(button, "BorderSizePixel", 0)
					local corner = ui.new "UICorner"
					ui.set(corner, "CornerRadius", ui.values.udim(0, 8))
					ui.set(corner, "Parent", button)
					local inset = ui.new "UIPadding"
					ui.set(inset, "PaddingLeft", ui.values.udim(0, 16))
					ui.set(inset, "PaddingRight", ui.values.udim(0, 16))
					ui.set(inset, "PaddingTop", ui.values.udim(0, 10))
					ui.set(inset, "PaddingBottom", ui.values.udim(0, 10))
					ui.set(inset, "Parent", button)
					textual(props, {
						text = function(text: string)
							ui.set(button, "Text", text)
						end,
						size = function(size: number)
							ui.set(button, "TextSize", size)
						end,
						color = function(value: unknown)
							ui.set(button, "TextColor3", value)
						end,
					})
					local activate = props.onActivate
					local callback = if activate then activate.callback else nil
					if callback then
						local run = callback
						local connection = ui.connect(button, "Activated", function()
							run()
						end)
						Compose.cleanup(function()
							connection:Disconnect()
						end)
					end
					return button
				end,
			},
			Image = {
				fields = with { image = { type = "string", group = "Image", order = 1 } },
				children = "none",
				call = "Design.Image",
				build = function(props: Props): unknown
					local image = ui.new "ImageLabel"
					sized(props, image)
					apply(props.image, function(value: Design.Literal?)
						ui.set(image, "Image", textOf(value) or "")
					end)
					return image
				end,
			},
			List = {
				fields = with { gap = { type = "number", tokens = true, group = "Auto layout", order = 1 } },
				defaults = listDefaults,
				children = "template",
				template = "render",
				source = "from",
				key = "key",
				call = "Design.List",
				build = function(props: Props): unknown
					local scroller = ui.new "ScrollingFrame"
					ui.set(scroller, "BorderSizePixel", 0)
					ui.set(scroller, "ScrollBarThickness", 6)
					ui.set(scroller, "AutomaticCanvasSize", ui.values.enum("AutomaticSize", "Y"))
					ui.set(scroller, "CanvasSize", ui.values.udim2(0, 0, 0, 0))
					sized(props, scroller)
					local layout = ui.new "UIListLayout"
					ui.set(layout, "SortOrder", ui.values.enum("SortOrder", "LayoutOrder"))
					apply(props.gap, function(value: Design.Literal?)
						ui.set(layout, "Padding", ui.values.udim(0, numberOf(value) or 0))
					end)
					ui.set(layout, "Parent", scroller)
					local source = props.from
					local templateProp = props.render
					local rows = if source then source.rows else nil
					local template = if templateProp then templateProp.template else nil
					if rows and template then
						local listRows, build = rows, template
						local owner: Compose.Owner? = nil
						Compose.watch(function(use: Compose.Use)
							local items = use(listRows)
							if owner then
								Compose.owner.dispose(owner)
							end
							local current = Compose.createOwner()
							owner = current
							Compose.withOwner(current, function()
								for order, item in items do
									local built = build(Compose.cell(item))
									if ui.isA(built, "GuiObject") then
										ui.set(built, "LayoutOrder", order)
										ui.set(built, "Parent", scroller)
									end
								end
							end)
						end)
						Compose.cleanup(function()
							if owner then
								Compose.owner.dispose(owner)
							end
						end)
					end
					return scroller
				end,
			},
		},
	}

	for _, kind in library.kinds do
		local build = kind.build
		kind.build = function(props: Props, children: { unknown }, name: string): unknown
			local built = build(props, children, name)
			if built ~= nil then
				ui.set(built, "Name", name)
			end
			return built
		end
	end

	return library
end
