--!strict
local motion = {}

function motion.create(ctx, name, _dataset)
	local Compose, runtime, Host, UI, types = ctx.Facet.Compose, ctx.runtime, ctx.Host, ctx.UI, ctx.types
	local D2, E = types.UDim2, types.Enum
	local state = {
		n = 0,
		name = name,
		observed = {},
		nodes = {},
		controls = {},
		status = Compose.cell({
			mode = "windowed",
			direction = "vertical",
			total = 0,
			retained = 0,
			first = 0,
			last = 0,
			firstRow = 0,
			lastRow = 0,
			rowCount = 0,
			extent = 0,
			following = false,
			measured = 0,
		}),
		motionSteps = 0,
	}
	local function label(text, size, name)
		return Host.TextLabel({
			Name = name or "Text",
			Text = text,
			TextSize = size,
			Size = D2.new(1, 0, 0, size + 4),
			BackgroundTransparency = 1,
			TextXAlignment = E.TextXAlignment.Left,
		})
	end
	local function screen(children)
		local properties = {
			Name = "Motion",
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.UIListLayout({ Padding = types.UDim.new(0, 4), SortOrder = E.SortOrder.LayoutOrder }),
			Host.UIPadding({ PaddingLeft = types.UDim.new(0, 6), PaddingTop = types.UDim.new(0, 6) }),
		}
		for index, node in children do
			runtime.decorate(node, { LayoutOrder = index })
			table.insert(properties, node)
		end
		state.root = Host.Frame(properties)
		return state.root
	end
	local function frame()
		if state.countWork then
			Compose.resetWorkCounters()
		end
		if ctx.frame then
			ctx.frame(1 / 60)
		end
		if state.countWork then
			local work = Compose.readWorkCounters()
			if work.cellWrites > 0 then
				state.motionSteps += 1
				state.motionTransactions += work.drains
			end
		else
			state.motionSteps += 1
		end
	end
	if name == "dense-motion" or name == "dense-motion-churn" then
		local items = table.create(600)
		for index = 1, 600 do
			items[index] = { id = `chip{index}`, name = `Racer {index}` }
		end
		state.rows, state.banner = Compose.cell(items), Compose.cell("ready")
		state.springs, state.targets = {}, {}
		state.beats, state.beatCallbacks = 0, 0
		function state.build()
			local chips = { Name = "Chips", Size = D2.new(1, 0, 0, 24), BackgroundTransparency = 1 }
			for index = 1, 24 do
				local target = Compose.cell(0)
				local spring = runtime.spring(function(use)
					return use(target)
				end, {
					period = if index % 2 == 0 then 0.28 else 0.18,
					damping = if index % 2 == 0 then 1 else 0.7,
				})
				state.targets[index], state.springs[index] = target, spring
				local chip = Host.Frame({
					Name = `Chip{index}`,
					Size = D2.fromOffset(24, 24),
					Position = function(use)
						return D2.new(0, (index - 1) * 28, use(spring) / 24, 0)
					end,
					BorderSizePixel = 0,
				})
				table.insert(state.nodes, chip)
				table.insert(chips, chip)
			end
			state.timeline = runtime.timeline({ duration = 0.3, autoplay = false })
			state.beatIndex = -1
			Compose.watch(function(use)
				local elapsed = use(state.timeline.elapsed)
				if state.beats == 0 then
					return
				end
				local reached = math.min(3, math.floor(elapsed * 10 + 1e-8))
				for index = state.beatIndex + 1, reached do
					state.beatCallbacks += 1
					if index == 1 then
						state.banner:set(`beat {state.beats}`)
					end
					if index == 3 then
						state.banner:set(`done {state.beats}`)
					end
				end
				state.beatIndex = reached
			end)
			local height = math.max(120, math.floor(ctx.viewport.h * 0.5))
			state.list = UI.VirtualList({
				Name = "Roster",
				from = state.rows,
				key = function(item)
					return item.id
				end,
				itemSize = 44,
				gap = 0,
				overscan = 2,
				status = state.status,
				controls = state.controls,
				Size = D2.new(1, 0, 0, height),
				render = function(current)
					return label(function(use)
						return use(current).name
					end, 15, "Name")
				end,
			})
			if ctx.engine then
				state.list.AbsoluteSize = types.Vector2.new(ctx.viewport.w, height)
				state.list.AbsoluteWindowSize = types.Vector2.new(ctx.viewport.w, height)
			end
			return screen({ label(state.banner, 18, "Banner"), Host.Frame(chips), state.list })
		end
		function state.step()
			state.n += 1
			local started = os.clock()
			local nextRows = table.clone(state.rows:peek())
			table.insert(nextRows, table.remove(nextRows, 1))
			state.rows:set(nextRows)
			for index, target in state.targets do
				target:set(if (state.n + index) % 2 == 0 then 12 else -12)
			end
			if state.beats == 0 or state.timeline.completed:peek() then
				state.beats += 1
				state.beatIndex = -1
				state.timeline:restart()
				if state.beatIndex < 0 then
					state.beatIndex = 0
					state.beatCallbacks += 1
				end
			end
			local mutate = os.clock() - started
			started = os.clock()
			frame()
			return { mutate = mutate, motion = os.clock() - started }
		end
		return state
	end
	assert(name == "control-motion" or name == "control-motion-census", "unknown motion workload")
	state.generation, state.rekeys, state.flips, state.pulses, state.pops = 0, 0, 0, 0, 0
	state.staggerHeld, state.flipsSeen, state.shakesSeen, state.popsSeen = 0, 0, 0, 0
	state.countWork, state.motionTransactions = true, 0
	Compose.setWorkCounters(true)
	Compose.cleanup(function()
		Compose.setWorkCounters(false)
	end)
	state.contentUp = false
	state.groups = {}
	function state.batch()
		state.generation += 1
		local records = table.create(30)
		for index = 1, 30 do
			records[index] = { id = `g{state.generation}-{index}`, index = index }
		end
		return records
	end
	state.items = Compose.cell(state.batch())
	state.rows = state.items
	state.invalid, state.expanded = Compose.cell(false), Compose.cell(false)
	function state.popsRef()
		return state.pops
	end
	function state.genRef()
		return state.generation
	end
	function state.build()
		state.entry = runtime.timeline({ duration = 29 * 0.02 + 0.2 })
		local entered = state.items:peek()
		Compose.watch(function(use)
			local current = use(state.items)
			if current ~= entered then
				entered = current
				state.entry:restart()
			end
		end)
		state.field = UI.TextInput({ Name = "Name", value = Compose.cell(""), invalid = state.invalid })
		state.button = UI.Button({
			Name = "Go",
			label = "Go",
			pop = true,
			onActivate = function()
				state.pops += 1
			end,
		})
		state.disclosure = UI.DisclosureGroup({
			Name = "Adv",
			label = "Advanced",
			expanded = state.expanded,
			onToggle = function(value)
				state.expanded:set(value)
			end,
			content = function()
				return label("body", 14, "Body")
			end,
		})
		local list = Host.Frame({
			Name = "List",
			Size = D2.new(1, 0, 0, 600),
			BackgroundTransparency = 1,
			Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
			Compose.keyed({
				from = state.items,
				key = function(item)
					return item.id
				end,
				render = function(current)
					local record = current:peek()
					local hold = (record.index - 1) * 0.02
					local group = Host.CanvasGroup({
						Name = `Row-{record.id}`,
						Size = D2.new(1, 0, 0, 20),
						LayoutOrder = record.index,
						BackgroundTransparency = 1,
						GroupTransparency = function(use)
							return 1 - math.clamp((use(state.entry.elapsed) - hold) / 0.2, 0, 1)
						end,
						label(record.id, 14, "T"),
					})
					state.groups[record.id] = group
					Compose.cleanup(function()
						state.groups[record.id] = nil
					end)
					return group
				end,
			}),
		})
		return screen({ state.field, state.button, state.disclosure, list })
	end
	function state.step()
		state.n += 1
		local started = os.clock()
		if state.n % 30 == 0 then
			state.items:set(state.batch())
			state.rekeys += 1
		end
		if state.n % 20 == 0 then
			state.expanded:set(not state.expanded:peek())
			state.flips += 1
		end
		if state.n % 15 == 0 then
			state.invalid:set(state.n % 30 ~= 0)
			state.pulses += 1
		end
		if state.n % 10 == 0 then
			if ctx.engine then
				state.button.Activated.fire()
			else
				game:GetService("GuiService").SelectedObject = state.button
				local parent = state.button.Parent
				local context
				while parent and not context do
					context = parent:FindFirstChild("FacetActivate")
					parent = parent.Parent
				end
				local action = context and context:FindFirstChild("Activate")
				assert(action and action:IsA("InputAction"), "native Button activation action is unavailable")
				local binding = action:FindFirstChildWhichIsA("InputBinding")
				assert(binding, "native Button activation binding is unavailable")
				binding:Fire(true)
				binding:Fire(false)
			end
		end
		local mutate = os.clock() - started
		started = os.clock()
		frame()
		return { mutate = mutate, motion = os.clock() - started }
	end
	function state.afterRun()
		local up = state.disclosure:FindFirstChild("Body", true) ~= nil
		if up ~= state.contentUp then
			state.contentUp = up
			state.flipsSeen += 1
		end
		local pulse = state.field:FindFirstChild("ValidationPulse", true)
		if pulse and math.abs(pulse.Scale - 1) > 0.000001 then
			state.shakesSeen += 1
		end
		local pop = state.button:FindFirstChild("Pop", true)
		if pop and math.abs(pop.Scale - 1) > 0.000001 then
			state.popsSeen += 1
		end
		if state.n % 30 == 0 then
			local first, last = state.groups[`g{state.generation}-1`], state.groups[`g{state.generation}-30`]
			if first and last and first.GroupTransparency < last.GroupTransparency then
				state.staggerHeld += 1
			end
		end
	end
	return state
end

return motion
