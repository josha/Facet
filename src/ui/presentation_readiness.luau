--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")
local fontReadiness = require("./font_readiness")
local textMeasure = require("./text_measure")

local TEXT: { [string]: true } = { TextLabel = true, TextButton = true, TextBox = true }

local function inWindow(row: GuiObject): boolean
	local at: Instance? = row.Parent
	while at and not at:IsA("ScrollingFrame") do
		at = at.Parent
	end
	if not at or not at:IsA("ScrollingFrame") then
		return true
	end
	local position, size = row.AbsolutePosition, row.AbsoluteSize
	local origin, window = at.AbsolutePosition, at.AbsoluteWindowSize
	return position.X < origin.X + window.X
		and position.X + size.X > origin.X
		and position.Y < origin.Y + window.Y
		and position.Y + size.Y > origin.Y
end

return function(ctx: Types.Context, roots: { GuiObject }): ComposeTypes.ReadOnlyValue<boolean>
	local fontsReady = fontReadiness(ctx, roots)
	local snapshot = ""
	local limit = math.ceil(math.max(1, ctx.metric("motion.restLimit")) * 60)
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
				if
					visible
					and child:IsA("GuiObject")
					and child:GetAttribute("FacetCollectionRow") == true
					and child.AbsoluteSize.X > 0
					and child.AbsoluteSize.Y > 0
					and inWindow(child)
				then
					measured = measured
						and child:GetAttribute("FacetCollectionReady") ~= false
						and child.Visible
						and (not child:IsA("CanvasGroup") or child.GroupTransparency < 1)
				end
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
		local settling = false
		for _, root in roots do
			local at: Instance? = root.Parent
			while at and not settling do
				settling = at:GetAttribute("FacetSettling") == true
				at = at.Parent
			end
		end
		return attached and measured and not settling and fontsReady(texts)
	end
	local graced = false
	return ctx.runtime.settled {
		ready = function(): boolean
			if prepared() then
				local first = not graced and ctx.metric("motion.frameLimit") > 0
				graced = true
				return not first
			end
			waiting += 1
			return waiting >= limit
		end,
		sample = function(): string
			return snapshot
		end,
		timeout = ctx.metric("motion.restLimit"),
	}
end
