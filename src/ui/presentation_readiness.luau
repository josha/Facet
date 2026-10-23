--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")
local fontReadiness = require("./font_readiness")
local textMeasure = require("./text_measure")

return function(ctx: Types.Context, roots: { GuiObject }): ComposeTypes.Readable<boolean>
	local fontsReady = fontReadiness(ctx, roots)
	local snapshot = ""
	local limit = math.ceil(math.max(1, ctx.metric("motion.restLimit")) * 60)
	local laidOut = false
	local waiting = 0
	local function prepared(): boolean
		local parts: { string } = {}
		local measured, attached = true, false
		for _, root in roots do
			attached = attached or root.Parent ~= nil and root.AbsoluteSize.X > 0 and root.AbsoluteSize.Y > 0
			table.insert(parts, `{root.AbsolutePosition}:{root.AbsoluteSize}:{root.Visible}`)
			for _, node in root:GetDescendants() do
				if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
					measured = measured and not textMeasure.pending(node)
					local visible = true
					local at: Instance? = node
					while at do
						if at:IsA("GuiObject") and not at.Visible then
							visible = false
							break
						end
						if at == root then
							break
						end
						at = at.Parent
					end
					if visible then
						table.insert(parts, `{node.AbsolutePosition}:{node.AbsoluteSize}:{node.TextBounds}:{node.Text}`)
					end
				end
			end
		end
		snapshot = table.concat(parts, ";")
		laidOut = laidOut or attached
		return attached and measured and fontsReady()
	end
	return ctx.runtime.settled {
		ready = function(): boolean
			if prepared() then
				return true
			end
			if laidOut then
				return false
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
