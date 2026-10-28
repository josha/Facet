--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")
local fontReadiness = require("./font_readiness")
local textMeasure = require("./text_measure")

local TEXT: { [string]: true } = { TextLabel = true, TextButton = true, TextBox = true }

return function(ctx: Types.Context, roots: { GuiObject }): ComposeTypes.ReadOnlyValue<boolean>
	local fontsReady = fontReadiness(ctx, roots)
	local snapshot = ""
	local limit = math.ceil(math.max(1, ctx.metric("motion.restLimit")) * 60)
	local laidOut = false
	local waiting = 0
	local function prepared(): boolean
		local parts: { string } = {}
		local texts: { fontReadiness.TextNode } = {}
		local measured, attached = true, false
		local function record(node: Instance, visible: boolean)
			if TEXT[node.ClassName] and (node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")) then
				table.insert(texts, node)
				measured = measured and not textMeasure.pending(node)
				if visible then
					local position, size, bounds = node.AbsolutePosition, node.AbsoluteSize, node.TextBounds
					table.insert(parts, `{position.X},{position.Y}:{size.X},{size.Y}:{bounds.X},{bounds.Y}:{node.Text}`)
				end
			end
		end
		local function visit(parent: Instance, visible: boolean)
			for _, child in parent:GetChildren() do
				local shown = visible and (not child:IsA("GuiObject") or child.Visible)
				record(child, shown)
				visit(child, shown)
			end
		end
		for _, root in roots do
			local size, position = root.AbsoluteSize, root.AbsolutePosition
			attached = attached or root.Parent ~= nil and size.X > 0 and size.Y > 0
			table.insert(parts, `{position.X},{position.Y}:{size.X},{size.Y}:{root.Visible}`)
			if TEXT[root.ClassName] and (root:IsA("TextLabel") or root:IsA("TextButton") or root:IsA("TextBox")) then
				table.insert(texts, root)
			end
			visit(root, root.Visible)
		end
		snapshot = table.concat(parts, ";")
		laidOut = laidOut or attached
		return attached and measured and fontsReady(texts)
	end
	local sampled = 0
	return ctx.runtime.settled {
		ready = function(): boolean
			if prepared() then
				sampled += 1
				return true
			end
			sampled = 0
			if laidOut then
				return false
			end
			waiting += 1
			return waiting >= limit
		end,
		sample = function(): string
			return if sampled > limit or waiting >= limit then "" else snapshot
		end,
	}
end
