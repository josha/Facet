--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")
local textMeasure = require("./text_measure")

return function(
	ctx: Types.Context,
	root: GuiObject,
	measure: ((ComposeTypes.Use, Vector2) -> ())?,
	rest: boolean?
): ComposeTypes.ReadOnlyValue<boolean>
	local size = ctx.observe.AbsoluteSize(root)
	local function painted(node: Instance): boolean
		if node:IsA("GuiObject") then
			if not node.Visible then
				return true
			end
			if node:GetAttribute("FacetBuilt") == false then
				return false
			end
			if node:IsA("ViewportFrame") and node:GetAttribute("FacetMediaReady") == false then
				return false
			end
			if
				(node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox"))
				and node.Text ~= ""
				and node.TextTransparency < 1
			then
				if textMeasure.pending(node) then
					return false
				end
				local box, bounds = node.AbsoluteSize, node.TextBounds
				if box.X <= 0 or box.Y <= 0 or bounds.X <= 0 or bounds.Y <= 0 then
					return false
				end
			end
		end
		for _, child in node:GetChildren() do
			if not painted(child) then
				return false
			end
		end
		return true
	end
	local function sample(): boolean
		local box = root.AbsoluteSize
		if box.X <= 0 or box.Y <= 0 then
			return false
		end
		for _, child in root:GetChildren() do
			if not painted(child) then
				return false
			end
		end
		return true
	end
	if rest and ctx.runtime.host.frames and not sample() then
		return ctx.runtime.settled {
			restart = function(use: ComposeTypes.Use): boolean
				local box = use(size)
				if measure then
					measure(use, box)
				end
				return box.X > 0 and box.Y > 0
			end,
			ready = sample,
			sample = function(): { number }
				local values: { number } = {}
				local function add(vector: Vector2)
					table.insert(values, vector.X)
					table.insert(values, vector.Y)
				end
				add(root.AbsoluteSize)
				local parent = root.Parent
				if parent and parent:IsA("GuiObject") then
					add(parent.AbsoluteSize)
				end
				for _, node in root:GetDescendants() do
					if node:IsA("GuiObject") then
						add(node.AbsoluteSize)
						if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
							add(node.TextBounds)
						end
					end
				end
				return values
			end,
			equals = function(left: { number }, right: { number }): boolean
				if #left ~= #right then
					return false
				end
				for index, value in left do
					if right[index] ~= value then
						return false
					end
				end
				return true
			end,
		}
	end
	local ready = ctx.Compose.cell(false)
	local owner = assert(ctx.Compose.currentOwner())
	local scope: ComposeTypes.Owner? = nil
	ctx.Compose.watch(function(use: ComposeTypes.Use)
		local box = use(size)
		if measure then
			measure(use, box)
		end
		if box.X <= 0 or box.Y <= 0 then
			if scope then
				ComposeTypes.owner.dispose(scope)
				scope = nil
			end
			ready:set(false)
		end
		if scope then
			return
		end
		local nextScope = ComposeTypes.owner.createChild(owner)
		scope = nextScope
		ctx.Compose.withOwner(nextScope, function()
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
