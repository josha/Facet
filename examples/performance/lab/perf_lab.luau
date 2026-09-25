--!strict
local lab = {}
lab.VERSION = "native-performance-lab/1"
lab.WORKLOADS = {
	{ id = "idle-baseline", label = "Idle baseline", scene = "hud-binding-storm" },
	{ id = "mount-ramp", label = "Mount ramp", scene = "screen-lifecycle-churn" },
	{ id = "dense-scroll", label = "Dense scrolling", scene = "lab-dense-scroll" },
	{ id = "dense-scroll-native", label = "Native fully mounted list", scene = "lab-dense-scroll" },
	{ id = "collection-churn", label = "Collection churn", scene = "lab-collection-churn" },
	{ id = "layout-style-churn", label = "Layout and style churn", scene = "stylesheet-state-churn" },
	{ id = "resize-relayout", label = "Resize and relayout", scene = "lab-dense-scroll" },
	{ id = "large-text-overflow", label = "Large text and locale", scene = "locale-textsize-change" },
	{ id = "async-image-churn", label = "Async image churn", scene = "async-image-grid" },
	{ id = "motion-flight", label = "Motion flight", scene = "dense-motion" },
	{ id = "sensory-cascade", label = "Native feedback requests", scene = "stylesheet-state-churn" },
	{ id = "variable-extents", label = "Variable row extents", scene = "lab-dense-scroll" },
	{ id = "table-unified", label = "Table", scene = "collection-mutation" },
	{ id = "arrange-shapes", label = "Native layout shapes", scene = "dense-hud" },
	{ id = "edit-locality", label = "Text editing locality", scene = "control-motion" },
	{ id = "host-move", label = "Host movement", scene = "lab-dense-scroll" },
	{ id = "lifecycle-soak", label = "Lifecycle soak", scene = "screen-lifecycle-churn" },
	{ id = "adaptive-navigation", label = "Adaptive navigation", scene = "adaptive-navigation-images" },
	{ id = "transient-surfaces", label = "Transient surfaces", scene = "alert-present-dismiss" },
}

function lab.build(ctx, modules)
	local Compose, Host, UI, T = ctx.Facet.Compose, ctx.Host, ctx.UI, ctx.types
	local selected, playing, rowCount = Compose.cell("dense-scroll"), Compose.cell(false), Compose.cell(2000)
	local captures, readout, active = {}, Compose.cell("Ready"), nil
	local sequence = Compose.cell(0)
	local byId, choices = {}, {}
	for _, entry in lab.WORKLOADS do
		byId[entry.id] = entry
		table.insert(choices, { value = entry.id, label = entry.label })
	end
	local samples, frameSamples, elapsed, iterations, queue = {}, {}, 0, 0, {}
	local clean, cleanSamples = Compose.cell(false), false
	local function resetSamples()
		samples, frameSamples, elapsed, iterations = {}, {}, 0, 0
		cleanSamples = clean:peek()
	end
	local function reset()
		resetSamples()
		sequence:update(function(value)
			return value + 1
		end)
	end
	local function sample(dt)
		if not active or selected:peek() == "idle-baseline" or active.ready == false then
			return
		end
		if not clean:peek() then
			cleanSamples = false
		end
		local before = os.clock()
		active.step()
		table.insert(samples, (os.clock() - before) * 1000)
		table.insert(frameSamples, dt * 1000)
		if #samples > 1500 then
			table.remove(samples, 1)
			table.remove(frameSamples, 1)
		end
		elapsed += dt
		iterations += 1
		if iterations % 15 == 0 then
			local ordered = table.clone(samples)
			table.sort(ordered)
			readout:set(
				`{iterations} iterations · p50 {string.format("%.3f", ordered[math.ceil(#ordered * 0.5)])} ms · p95 {string.format(
					"%.3f",
					ordered[math.ceil(#ordered * 0.95)]
				)} ms`
			)
		end
	end
	local function capture()
		local row = table.clone(ctx.captureFacts())
		row.schema = modules.capture.SCHEMA
		row.frameworkVersion = ctx.Facet.VERSION
		row.scenarioVersion = lab.VERSION
		row.datasetVersion = modules.dataset.VERSION
		row.rowVersion = modules.rows.VERSION
		row.scenario = selected:peek()
		row.rows, row.seed, row.content = rowCount:peek(), 1, "normal"
		row.implementation = if selected:peek() == "dense-scroll-native" then "native-all" else "compose-native"
		row.theme, row.resourceState = if ctx.themeName then ctx.themeName:peek() else "facet-neutral", "mixed"
		row.datasetDigest = modules.dataset.digest(modules.dataset.build({ count = row.rows, seed = 1 }))
		row.repeat_, row.warmupFrames, row.captureFrames = #captures + 1, 0, #frameSamples
		row.cleanCapture, row.profilerScopes = cleanSamples and #frameSamples > 0, false
		row.frame = {
			measured = #frameSamples > 0,
			samplesMs = table.clone(frameSamples),
			instrument = "Heartbeat intervals; not CPU or render work",
		}
		row.counters = {
			iterations = iterations,
			elapsedSeconds = elapsed,
			feedback = if active then active.counters else nil,
			preferredTextSize = row.preferredTextSize,
		}
		row.scopes = { measured = true, controlStepMs = table.clone(samples) }
		local problems = modules.capture.problems(row)
		assert(#problems == 0, table.concat(problems, "; "))
		table.insert(captures, row)
		if ctx.emitCapture then
			ctx.emitCapture(row)
		end
		readout:set(`Captured {#captures} · JSON written to the output`)
		return row
	end
	local function stop()
		playing:set(false)
		table.clear(queue)
	end
	local function sweep()
		stop()
		for _, entry in lab.WORKLOADS do
			table.insert(queue, { id = entry.id, rows = rowCount:peek() })
		end
		playing:set(true)
	end
	local function ramp()
		stop()
		for _, count in modules.dataset.RAMP_STEPS do
			table.insert(queue, { id = "mount-ramp", rows = count })
		end
		playing:set(true)
	end
	local function idle()
		stop()
		selected:set("idle-baseline")
		reset()
	end
	local toolbar = Host.Frame "Toolbar" {
		LayoutOrder = 1,
		Visible = function(use)
			return not use(clean)
		end,
		Size = T.UDim2.new(1, 0, 0, 0),
		AutomaticSize = T.Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Host.UIListLayout({ FillDirection = T.Enum.FillDirection.Horizontal, Padding = T.UDim.new(0, 8), Wraps = true }),
		UI.Picker({
			label = "Workload",
			Size = T.UDim2.fromOffset(210, 40),
			selected = selected,
			options = choices,
			style = "menu",
			onChange = function(value)
				selected:set(value)
				reset()
			end,
		}),
		UI.Picker({
			label = "Rows",
			Size = T.UDim2.fromOffset(130, 40),
			selected = rowCount,
			options = {
				{ value = 100, label = "100 rows" },
				{ value = 500, label = "500 rows" },
				{ value = 2000, label = "2000 rows" },
				{ value = 10000, label = "10000 rows" },
				{ value = 40000, label = "40000 rows" },
			},
			style = "menu",
			onChange = function(value)
				rowCount:set(value)
				reset()
			end,
		}),
		UI.Button({
			Size = T.UDim2.fromOffset(70, 40),
			label = function(use)
				return if use(playing) then "Pause" else "Run"
			end,
			onActivate = function()
				playing:set(not playing:peek())
			end,
		}),
		UI.Button({
			label = "Step",
			Size = T.UDim2.fromOffset(70, 40),
			onActivate = function()
				sample(1 / 60)
			end,
		}),
		UI.Button({ label = "Reset", Size = T.UDim2.fromOffset(80, 40), onActivate = idle }),
		UI.Button({ label = "Run all", Size = T.UDim2.fromOffset(80, 40), onActivate = sweep }),
		UI.Button({ label = "Ramp", Size = T.UDim2.fromOffset(80, 40), onActivate = ramp }),
		UI.Button({ label = "Stop", Size = T.UDim2.fromOffset(80, 40), onActivate = stop }),
		UI.Button({ label = "Capture", Size = T.UDim2.fromOffset(80, 40), onActivate = capture }),
	}
	local mount = Host.Frame "Workload" {
		Size = T.UDim2.new(1, 0, 0, 0),
		LayoutOrder = 3,
		Host.UIFlexItem({ FlexMode = T.Enum.UIFlexMode.Fill }),
		BackgroundTransparency = 1,
		Compose.keyed({
			from = function(use)
				return { { id = `{use(selected)}:{use(sequence)}`, workload = use(selected), count = use(rowCount) } }
			end,
			key = function(item)
				return item.id
			end,
			render = function(current)
				local item = current:peek()
				local data = modules.dataset.build({ count = item.count, seed = 1 })
				local context = table.clone(ctx)
				context.rowCount = item.count
				context.rowBuilder = modules.rows.build
				context.rowSize = modules.rows.estimate(context)
				context.frame = nil
				local workload = modules.workloads.create(context, byId[item.workload].scene, modules.dataset)
				local node
				if item.workload == "sensory-cascade" then
					workload = modules.sensory(context)
					node = workload.build()
				elseif item.workload == "dense-scroll-native" or item.workload == "mount-ramp" then
					local progressive = item.workload == "dense-scroll-native" and ctx.heartbeat ~= nil
					local rows = Compose.cell(if progressive then {} else data)
					local function fullList()
						return Host.ScrollingFrame({
							Size = T.UDim2.fromScale(1, 1),
							AutomaticCanvasSize = T.Enum.AutomaticSize.Y,
							Host.UIListLayout({ Padding = T.UDim.new(0, 4) }),
							workload.disclosure(),
							Compose.keyed({
								from = rows,
								key = function(row)
									return row.id
								end,
								render = function(row)
									return modules.rows.build(context, row)
								end,
							}),
						})
					end
					if item.workload == "mount-ramp" then
						node = Host.Frame({ Size = T.UDim2.fromScale(1, 1) })
						workload.step = function()
							local stop = ctx.runtime.mount(fullList, node)
							stop()
						end
					else
						node = fullList()
						workload.step = function()
							node.CanvasPosition += T.Vector2.new(0, 61)
						end
						if progressive then
							workload.ready = false
							local filling
							filling = ctx.heartbeat:Connect(function()
								local current = rows:peek()
								local nextRows = table.clone(current)
								for index = #current + 1, math.min(#data, #current + 100) do
									table.insert(nextRows, data[index])
								end
								rows:set(nextRows)
								if #nextRows >= #data then
									workload.ready = true
									filling:Disconnect()
								end
							end)
							Compose.cleanup(function()
								filling:Disconnect()
							end)
						end
					end
				elseif item.workload == "variable-extents" or item.workload == "edit-locality" then
					local rows, extents, values = Compose.cell(data), Compose.cell({}), {}
					for _, row in data do
						values[row.id] = Compose.cell(row.name)
					end
					local status = Compose.cell({
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
					})
					node = UI.VirtualList({
						from = rows,
						key = function(row)
							return row.id
						end,
						itemSize = 56,
						measured = extents,
						status = status,
						render = function(current)
							if item.workload == "edit-locality" then
								local value = values[current:peek().id]
								return UI.TextInput({
									value = value,
									onChange = function(next)
										value:set(next)
									end,
									Size = T.UDim2.new(1, 0, 0, 56),
								})
							end
							return Host.Frame({
								Size = function(use)
									return T.UDim2.new(1, 0, 0, use(extents)[use(current).id] or 56)
								end,
								modules.rows.build(context, current),
							})
						end,
						Size = T.UDim2.fromScale(1, 1),
						if item.workload == "variable-extents" then workload.disclosure() else nil,
					})
					if ctx.engine then
						node.AbsoluteWindowSize = T.Vector2.new(800, 400)
					end
					workload.list, workload.status, workload.extents, workload.values = node, status, extents, values
					workload.step = function()
						workload.n += 1
						local at = math.clamp(status:peek().first or 1, 1, #data)
						if item.workload == "edit-locality" then
							values[data[at].id]:set(`Edited {workload.n}`)
						else
							local changed = table.clone(extents:peek())
							changed[data[at].id] = if workload.n % 2 == 0 then 56 else 112
							extents:set(changed)
							node.CanvasPosition += T.Vector2.new(0, 61)
						end
					end
				elseif item.workload == "arrange-shapes" then
					local children = { Host.UIGridLayout({ CellSize = T.UDim2.new(0.5, -4, 0.5, -4) }) }
					for shape = 1, 4 do
						local properties = {
							Host.UIListLayout({
								FillDirection = if shape % 2 == 0
									then T.Enum.FillDirection.Horizontal
									else T.Enum.FillDirection.Vertical,
								Wraps = shape > 2,
							}),
						}
						for index = 1, math.min(item.count, 1000) do
							table.insert(
								properties,
								UI.Label({ text = `Row {index}`, Size = T.UDim2.fromOffset(60, 24) })
							)
						end
						table.insert(children, Host.Frame(properties))
					end
					children.Size = T.UDim2.fromScale(1, 1)
					node = Host.Frame(children)
					workload.step = function()
						workload.n += 1
						node.Size = T.UDim2.new(1, if workload.n % 2 == 0 then 0 else -100, 1, 0)
					end
				else
					node = workload.build()
					if item.workload == "host-move" then
						workload.step = function()
							workload.n += 1
							node.Position = T.UDim2.fromOffset(workload.n % 40, workload.n % 20)
						end
					elseif item.workload == "resize-relayout" then
						workload.step = function()
							workload.n += 1
							node.Size = T.UDim2.new(1, if workload.n % 2 == 0 then 0 else -180, 1, 0)
						end
					end
				end
				active = workload
				Compose.cleanup(function()
					if active == workload then
						active = nil
					end
				end)
				return node
			end,
		}),
	}
	if ctx.probe then
		ctx.probe({
			select = function(id, count)
				assert(byId[id], "Unknown workload")
				stop()
				selected:set(id)
				if count then
					rowCount:set(math.clamp(count, 1, modules.dataset.MAX_ROWS))
				end
				reset()
			end,
			step = sample,
			run = function()
				playing:set(true)
			end,
			stop = stop,
			reset = idle,
			capture = capture,
			clean = function(value)
				clean:set(value == true)
				resetSamples()
			end,
			theme = function(name)
				assert(ctx.setTheme, "this place has no theme packages")
				ctx.setTheme(name)
				resetSamples()
			end,
			sweep = sweep,
			ramp = ramp,
			state = function()
				return {
					selected = selected:peek(),
					playing = playing:peek(),
					rows = rowCount:peek(),
					iterations = iterations,
					queued = #queue,
					captures = #captures,
					active = active,
					ready = active ~= nil and active.ready ~= false,
				}
			end,
		})
	end
	local connection = ctx.heartbeat:Connect(function(dt)
		if playing:peek() then
			if #queue > 0 then
				local entry = table.remove(queue, 1)
				selected:set(entry.id)
				rowCount:set(entry.rows)
				reset()
				local ok, err = pcall(sample, dt)
				if ok then
					capture()
				else
					readout:set(tostring(err))
				end
				if #queue == 0 then
					playing:set(false)
				end
			else
				sample(dt)
			end
		end
	end)
	Compose.cleanup(function()
		connection:Disconnect()
	end)
	local root = Host.Frame "PerformanceLab" {
		Size = T.UDim2.fromScale(1, 1),
		Host.UIPadding({
			PaddingTop = T.UDim.new(0, 8),
			PaddingBottom = T.UDim.new(0, 8),
			PaddingLeft = T.UDim.new(0, 8),
			PaddingRight = T.UDim.new(0, 8),
		}),
		Host.UIListLayout({ SortOrder = T.Enum.SortOrder.LayoutOrder, Padding = T.UDim.new(0, 8) }),
		toolbar,
		UI.Label({
			text = readout,
			LayoutOrder = 2,
			Size = T.UDim2.new(1, 0, 0, 40),
			TextWrapped = true,
			Visible = function(use)
				return not use(clean)
			end,
		}),
		mount,
	}
	root:AddTag("facet-surface")
	return root
end
return lab
