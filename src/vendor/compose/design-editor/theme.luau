--!strict

local UI = require "./ui"

local Compose = require "../core"

return function(ui: UI.UI)
	local Theme = {}

	Theme.color = {
		canvas = ui.rgb(30, 30, 32),
		grid = ui.rgb(58, 58, 62),
		panel = ui.rgb(44, 44, 46),
		raised = ui.rgb(56, 56, 59),
		hover = ui.rgb(64, 64, 68),
		divider = ui.rgb(26, 26, 28),
		field = ui.rgb(36, 36, 38),
		text = ui.rgb(240, 240, 242),
		secondary = ui.rgb(176, 176, 182),
		tertiary = ui.rgb(120, 120, 126),
		accent = ui.rgb(13, 153, 255),
		accentSoft = ui.rgb(26, 64, 96),
		danger = ui.rgb(242, 92, 84),
		white = ui.rgb(255, 255, 255),
		shadow = ui.rgb(0, 0, 0),
	}

	Theme.font = {
		regular = ui.values.font("rbxasset://fonts/families/BuilderSans.json", "Regular"),
		medium = ui.values.font("rbxasset://fonts/families/BuilderSans.json", "Medium"),
		bold = ui.values.font("rbxasset://fonts/families/BuilderSans.json", "SemiBold"),
		mono = ui.values.font("rbxasset://fonts/families/RobotoMono.json", "Regular"),
	}

	Theme.size = {
		toolbar = 48,
		status = 26,
		side = 300,
		row = 28,
		header = 40,
		radius = 6,
		gutter = 12,
		text = 12,
		small = 11,
		title = 13,
	}

	local glyph: { [string]: string } = {
		Frame = "▢",
		Stack = "☰",
		Text = "T",
		Button = "◉",
		Image = "◩",
		List = "≡",
		Model = "⬡",
		Part = "■",
	}
	Theme.glyph = glyph

	function Theme.corner(parent: Compose.Node, radius: number?)
		local corner = ui.call(parent, "FindFirstChildOfClass", "UICorner") or ui.new "UICorner"
		ui.set(corner, "CornerRadius", ui.values.udim(0, radius or Theme.size.radius))
		ui.set(corner, "Parent", parent)
	end

	function Theme.stroke(parent: Compose.Node, color: unknown, thickness: number?, transparency: number?): Compose.Node
		local stroke = ui.new "UIStroke"
		ui.set(stroke, "ApplyStrokeMode", ui.values.enum("ApplyStrokeMode", "Border"))
		ui.set(stroke, "Color", color)
		ui.set(stroke, "Thickness", thickness or 1)
		ui.set(stroke, "Transparency", transparency or 0)
		ui.set(stroke, "Parent", parent)
		return stroke
	end

	function Theme.pad(parent: Compose.Node, left: number, right: number?, top: number?, bottom: number?)
		local padding = ui.call(parent, "FindFirstChildOfClass", "UIPadding") or ui.new "UIPadding"
		ui.set(padding, "PaddingLeft", ui.values.udim(0, left))
		ui.set(padding, "PaddingRight", ui.values.udim(0, right or left))
		ui.set(padding, "PaddingTop", ui.values.udim(0, top or 0))
		ui.set(padding, "PaddingBottom", ui.values.udim(0, bottom or top or 0))
		ui.set(padding, "Parent", parent)
	end

	function Theme.list(parent: Compose.Node, direction: unknown, gap: number, align: unknown?): Compose.Node
		local layout = ui.new "UIListLayout"
		ui.set(layout, "FillDirection", direction)
		ui.set(layout, "SortOrder", ui.values.enum("SortOrder", "LayoutOrder"))
		ui.set(layout, "Padding", ui.values.udim(0, gap))
		ui.set(layout, "VerticalAlignment", align or ui.values.enum("VerticalAlignment", "Top"))
		ui.set(layout, "Parent", parent)
		return layout
	end

	function Theme.frame(name: string, color: unknown?): Compose.Node
		local frame = ui.new "Frame"
		ui.set(frame, "Name", name)
		ui.set(frame, "BorderSizePixel", 0)
		if color then
			ui.set(frame, "BackgroundColor3", color)
		else
			ui.set(frame, "BackgroundTransparency", 1)
		end
		return frame
	end

	function Theme.label(text: string, color: unknown, size: number?, font: unknown?): Compose.Node
		local label = ui.new "TextLabel"
		ui.set(label, "BackgroundTransparency", 1)
		ui.set(label, "BorderSizePixel", 0)
		ui.set(label, "Text", text)
		ui.set(label, "TextColor3", color)
		ui.set(label, "TextSize", size or Theme.size.text)
		ui.set(label, "FontFace", font or Theme.font.medium)
		ui.set(label, "TextXAlignment", ui.values.enum("TextXAlignment", "Left"))
		ui.set(label, "TextTruncate", ui.values.enum("TextTruncate", "AtEnd"))
		return label
	end

	function Theme.hover(button: Compose.Node, rest: unknown, over: unknown, transparency: number?): { UI.Connection }
		ui.set(button, "BackgroundColor3", rest)
		return {
			ui.connect(button, "MouseEnter", function()
				ui.set(button, "BackgroundColor3", over)
				ui.set(button, "BackgroundTransparency", 0)
			end),
			ui.connect(button, "MouseLeave", function()
				ui.set(button, "BackgroundColor3", rest)
				ui.set(button, "BackgroundTransparency", transparency or 0)
			end),
		}
	end

	function Theme.scroller(name: string): Compose.Node
		local scroller = ui.new "ScrollingFrame"
		ui.set(scroller, "Name", name)
		ui.set(scroller, "BackgroundTransparency", 1)
		ui.set(scroller, "BorderSizePixel", 0)
		ui.set(scroller, "ScrollBarThickness", 4)
		ui.set(scroller, "ScrollBarImageColor3", Theme.color.tertiary)
		ui.set(scroller, "ScrollBarImageTransparency", 0.3)
		ui.set(scroller, "AutomaticCanvasSize", ui.values.enum("AutomaticSize", "Y"))
		ui.set(scroller, "CanvasSize", ui.values.udim2(0, 0, 0, 0))
		ui.set(scroller, "ScrollingDirection", ui.values.enum("ScrollingDirection", "Y"))
		return scroller
	end

	function Theme.point(input: Compose.Node): UI.Point
		return ui.xy(input, "Position")
	end

	return Theme
end
