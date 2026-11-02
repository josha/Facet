--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")
local textMeasure = require("./text_measure")

type Poll = { steps: { [() -> ()]: boolean }, queue: { () -> () }, count: number, stop: (() -> ())? }
local polls: { [unknown]: Poll } = setmetatable({}, { __mode = "k" })

return function(
	ctx: Types.Context,
	root: GuiObject,
	measure: ((ComposeTypes.Use, Vector2) -> ())?,
	rest: boolean?
): ComposeTypes.ReadOnlyValue<boolean>
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
		return painted(root)
	end
	if rest and ctx.runtime.host.frames and not sample() then
		local size = ctx.observe.AbsoluteSize(root)
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
	local render = ctx.config.services.RunService and ctx.config.services.RunService.PreRender
	local frames = ctx.runtime.host.frames
	local waiting, closed = false, false
	local poll: Poll? = nil
	local geometry: { RBXScriptConnection } = {}
	local prepare: () -> ()
	local function listen(node: Instance)
		if node:IsA("GuiObject") then
			if node ~= root then
				table.insert(geometry, node:GetPropertyChangedSignal("AbsoluteSize"):Connect(prepare))
			end
			table.insert(geometry, node:GetPropertyChangedSignal("Visible"):Connect(prepare))
			if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
				table.insert(geometry, node:GetPropertyChangedSignal("TextBounds"):Connect(prepare))
			end
		end
	end
	local function halt()
		for _, connection in geometry do
			connection:Disconnect()
		end
		table.clear(geometry)
		local held = poll
		if not waiting or held == nil then
			return
		end
		waiting = false
		held.steps[prepare] = nil
		held.count -= 1
		local stop = held.stop
		if held.count == 0 and stop then
			held.stop = nil
			stop()
		end
	end
	local function arm()
		if waiting or (not render and not frames) then
			return
		end
		local key: unknown = ctx.runtime
		local found = polls[key]
		if found == nil then
			local created: Poll = { steps = {}, queue = {}, count = 0 }
			found = created
			polls[key] = found
		end
		local held = found
		poll = held
		waiting = true
		held.steps[prepare] = true
		held.count += 1
		if held.stop then
			return
		end
		local function run()
			for step in held.steps do
				table.insert(held.queue, step)
			end
			for _, step in held.queue do
				if held.steps[step] then
					step()
				end
			end
			table.clear(held.queue)
		end
		if render then
			local connection = render:Connect(run)
			held.stop = function()
				connection:Disconnect()
			end
		else
			held.stop = assert(frames).onFrame(run)
		end
	end
	prepare = function()
		if closed then
			return
		end
		local box = root.AbsoluteSize
		if box.X <= 0 or box.Y <= 0 then
			halt()
			ready:set(false)
			return
		end
		if ready:peek() then
			return
		end
		if sample() then
			halt()
			ready:set(true)
			return
		end
		if #geometry == 0 then
			listen(root)
			for _, node in root:GetDescendants() do
				listen(node)
			end
		end
		arm()
	end
	local changed = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(prepare)
	ctx.Compose.cleanup(function()
		closed = true
		changed:Disconnect()
		halt()
	end)
	if measure then
		local size = ctx.observe.AbsoluteSize(root)
		ctx.Compose.watch(function(use: ComposeTypes.Use)
			measure(use, use(size))
			prepare()
		end)
	else
		prepare()
	end
	return ready
end
