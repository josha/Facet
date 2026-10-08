--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")

return function(ctx: Types.Context, root: GuiObject): ComposeTypes.Readable<boolean>
	local size = ctx.observe.AbsoluteSize(root)
	local ready = ctx.Compose.cell(false)
	local owner = assert(ctx.Compose.currentOwner())
	local scope: ComposeTypes.Owner? = nil
	ctx.Compose.watch(function(use: ComposeTypes.Use)
		local box = use(size)
		if box.X <= 0 or box.Y <= 0 then
			if scope then
				scope.dispose()
				scope = nil
			end
			ready:set(false)
		end
		if scope then
			return
		end
		local nextScope = owner.createChild()
		scope = nextScope
		ctx.Compose.withOwner(nextScope, function()
			local function sample(): boolean
				local filled = root.AbsoluteSize.X > 0 and root.AbsoluteSize.Y > 0
				for _, node in root:GetDescendants() do
					if node:IsA("GuiObject") then
						local visible = node.Visible
						local parent = node.Parent
						while visible and parent and parent ~= root do
							if parent:IsA("GuiObject") then
								visible = parent.Visible
							end
							parent = parent.Parent
						end
						if visible then
							filled = filled
								and node:GetAttribute("FacetBuilt") ~= false
								and (not node:IsA("ViewportFrame") or node:GetAttribute("FacetMediaReady") ~= false)
							if
								(node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox"))
								and node.Text ~= ""
								and node.TextTransparency < 1
							then
								filled = filled
									and node.AbsoluteSize.X > 0
									and node.AbsoluteSize.Y > 0
									and node.TextBounds.X > 0
									and node.TextBounds.Y > 0
							end
						end
					end
				end
				return filled
			end
			local render = ctx.config.services.RunService and ctx.config.services.RunService.PreRender
			local frames = ctx.runtime.host.frames
			local stop: (() -> ())? = nil
			local geometry: { RBXScriptConnection } = {}
			local function halt()
				for _, connection in geometry do
					connection:Disconnect()
				end
				table.clear(geometry)
				local current = stop
				stop = nil
				if current then
					current()
				end
			end
			local function prepare()
				if not ready:peek() and sample() then
					halt()
					ready:set(true)
				end
			end
			ctx.Compose.cleanup(halt)
			prepare()
			if ready:peek() then
				return
			end
			local function listen(node: Instance)
				if node:IsA("GuiObject") then
					table.insert(geometry, node:GetPropertyChangedSignal("AbsoluteSize"):Connect(prepare))
					table.insert(geometry, node:GetPropertyChangedSignal("Visible"):Connect(prepare))
					if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
						table.insert(geometry, node:GetPropertyChangedSignal("TextBounds"):Connect(prepare))
					end
				end
			end
			listen(root)
			for _, node in root:GetDescendants() do
				listen(node)
			end
			if render then
				local connection = render:Connect(prepare)
				stop = function()
					connection:Disconnect()
				end
			elseif frames then
				stop = frames.onFrame(prepare)
			else
				prepare()
			end
		end)
	end)
	return ready
end
