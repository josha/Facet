--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local terminal = require("../examples/gallery/examples/outpost_terminal")
local Compose = Facet.Compose

local function world()
	local engine = engineLib.new({ cacheDefaults = true })
	local runtime = Facet.Roblox.createRuntime(engine)
	local root = engine.new("ScreenGui")
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local UI = Facet.controls(runtime, {
		types = engine.types,
		services = { GuiService = gui, UserInputService = input },
		reducedMotion = true,
	})
	return engine, runtime, root, UI, input, gui
end

local function find(node, name)
	if node.Name == name then
		return node
	end
	for _, child in node:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function within(node, ancestor)
	local current = node
	while current do
		if current == ancestor then
			return true
		end
		current = current.Parent
	end
	return false
end

local function sameCensus(engine, baseline, label)
	local now = engine.census()
	assert(now.live == baseline.live, `{label}: live instances {baseline.live} -> {now.live}`)
	assert(now.connections == baseline.connections, `{label}: connections {baseline.connections} -> {now.connections}`)
end

local function random(seed)
	return function(low, high)
		seed = (seed * 48271) % 2147483647
		return low + seed % (high - low + 1)
	end
end

t.describe("native stress invariants", function()
	t.it("detects detached instance and service connection leaks in the census", function()
		local engine = engineLib.new()
		local service = engine.new("GuiService")
		local baseline = engine.census()
		local orphan = engine.new("Frame")
		t.expect(pcall(sameCensus, engine, baseline, "orphan")).toBe(false)
		orphan:Destroy()
		local connection = service:GetPropertyChangedSignal("SelectedObject"):Connect(function() end)
		t.expect(pcall(sameCensus, engine, baseline, "connection")).toBe(false)
		connection:Disconnect()
		sameCensus(engine, baseline, "cleaned")
	end)

	t.it("returns all instances and connections to baseline through 200 modal cycles twice", function()
		for replay = 1, 2 do
			local engine, runtime, root, UI = world()
			local before = engine.census()
			local shown = Compose.cell(false)
			local stop = runtime.mount(function()
				return runtime.constructors.Frame({
					UI.Button "Base" { label = "Open" },
					UI.Alert({ isPresented = shown, title = "Confirm", actions = { { id = "ok", label = "OK" } } }),
				})
			end, root)
			local baseline = engine.census()
			for cycle = 1, 200 do
				shown:set(true)
				assert(engine.census().live > baseline.live, "alert must actually mount")
				shown:set(false)
				sameCensus(engine, baseline, `modal replay {replay} cycle {cycle}`)
			end
			stop()
			runtime:dispose()
			sameCensus(engine, before, "modal teardown")
		end
	end)

	t.it("reclaims detached and pooled rows through 100 structural cycles twice", function()
		for replay = 1, 2 do
			local engine, runtime, root, UI = world()
			local before = engine.census()
			local initial = { { id = "a" }, { id = "b" }, { id = "c" } }
			local source = Compose.cell(initial)
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = source,
					key = function(item)
						return item.id
					end,
					itemSize = 20,
					overscan = 0,
					render = function(current)
						return UI.Button({
							label = function(use)
								return use(current).id
							end,
						})
					end,
				})
			end, root)
			node.AbsoluteWindowSize = engine.types.Vector2.new(300, 100)
			local baseline = engine.census()
			for cycle = 1, 100 do
				source:set({ initial[2], initial[3], { id = `new{cycle}` } })
				source:set(initial)
				sameCensus(engine, baseline, `collection replay {replay} cycle {cycle}`)
			end
			stop()
			runtime:dispose()
			sameCensus(engine, before, "collection teardown")
		end
	end)

	t.it("preserves keyed row content and bounded retention across 400 replayable mutation seeds", function()
		for seed = 1, 400 do
			local rng = random(260720 + seed)
			local engine, runtime, root, UI = world()
			local before = engine.census()
			local rows = {}
			for index = 1, 80 do
				rows[index] = { id = index, label = tostring(index) }
			end
			local nextId, source, status = 80, Compose.cell(rows), Compose.cell({ total = 0 })
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = source,
					key = function(item)
						return item.id
					end,
					itemSize = 20,
					overscan = 0,
					status = status,
					render = function(current)
						return UI.Button "Value" {
							label = function(use)
								return use(current).label
							end,
						}
					end,
				})
			end, root)
			for step = 1, 40 do
				local operation = rng(1, 5)
				rows = table.clone(rows)
				if operation == 1 then
					nextId += 1
					table.insert(rows, rng(1, #rows + 1), { id = nextId, label = tostring(nextId) })
				elseif operation == 2 and #rows > 5 then
					table.remove(rows, rng(1, #rows))
				elseif operation == 3 then
					local index = rng(1, #rows)
					rows[index] = { id = rows[index].id, label = `seed{seed}step{step}` }
				elseif operation == 4 then
					local first, second = rng(1, #rows), rng(1, #rows)
					rows[first], rows[second] = rows[second], rows[first]
				end
				source:set(rows)
				local visible = rng(1, 12)
				node.AbsoluteWindowSize = engine.types.Vector2.new(300, visible * 20)
				node.CanvasPosition = engine.types.Vector2.new(0, rng(0, #rows - visible) * 20)
				local snapshot = status:peek()
				assert(snapshot.total == #rows, `seed={seed} step={step}: total`)
				assert(snapshot.retained <= visible + 1, `seed={seed} step={step}: unbounded retention`)
				for index = snapshot.first, snapshot.last do
					local item = rows[index]
					local row = node:FindFirstChild(tostring(item.id), true)
					assert(
						row and row:FindFirstChild("Value", true).Text == item.label,
						`seed={seed} step={step}: stale keyed row {item.id}`
					)
				end
			end
			stop()
			runtime:dispose()
			sameCensus(engine, before, `seed={seed} teardown`)
		end
	end)

	t.it("converges authoritative snapshots under 400 seeded delayed duplicated reordered deliveries", function()
		for seed = 1, 400 do
			local rng = random(471120 + seed)
			local engine, runtime, root, UI = world()
			local before = engine.census()
			local built
			local stop = runtime.mount(function()
				built = terminal.build({
					Facet = Facet,
					Compose = Compose,
					runtime = runtime,
					Host = runtime.constructors,
					UI = UI,
					types = engine.types,
				}, { send = function() end })
				return built.screen()
			end, root)
			built.steps.engage(terminal.rules.START, 0)
			local highest = 0
			for step = 1, 80 do
				local revision = rng(1, 100)
				local allocation = { door = revision % 3, beacon = revision % 2, workshop = revision % 4 }
				local accepted = built.steps.ingest(revision, allocation)
				assert(accepted == (revision > highest), `seed={seed} step={step}: revision acceptance`)
				highest = math.max(highest, revision)
				assert(built.model.revision:peek() == highest, `seed={seed} step={step}: revision regressed`)
				assert(built.model.confirmed:peek().door == highest % 3, `seed={seed} step={step}: authority diverged`)
			end
			built.steps.ingest(101, terminal.rules.START)
			assert(built.model.revision:peek() == 101, `seed={seed}: final snapshot did not converge`)
			for id, value in terminal.rules.START do
				assert(built.model.confirmed:peek()[id] == value)
			end
			stop()
			runtime:dispose()
			sameCensus(engine, before, `replication seed={seed} teardown`)
		end
	end)
	t.it("rejects stale async completions and cancels exactly once through 200 seeded fault storms", function()
		for seed = 1, 200 do
			local rng = random(611001 + seed)
			local engine, runtime, root, UI = world()
			local before = engine.census()
			local source, requests, changes = Compose.cell("initial"), {}, 0
			local stop, node = runtime.mount(function()
				return UI.AsyncImage({
					source = source,
					loader = function(content, resolve, reject)
						local request = { resolve = resolve, reject = reject, cancelled = 0 }
						table.insert(requests, request)
						return function()
							request.cancelled += 1
						end
					end,
					onStatus = function()
						changes += 1
					end,
				})
			end, root)
			for step = 1, rng(5, 25) do
				source:set(`seed{seed}step{step}`)
				local old = requests[rng(1, #requests - 1)]
				local image = node:FindFirstChild("Image")
				local prior, notifications = image.Image, changes
				old.resolve("stale")
				old.reject("stale failure")
				assert(
					image.Image == prior and changes == notifications,
					`seed={seed} step={step}: stale completion changed UI`
				)
				local current = requests[#requests]
				if rng(1, 2) == 1 then
					current.resolve(source:peek())
					assert(image.Visible and image.Image == source:peek(), `seed={seed}: latest result missing`)
				else
					current.reject("injected failure")
					assert(not image.Visible, `seed={seed}: failure still paints image`)
				end
			end
			stop()
			local notifications = changes
			for _, request in requests do
				request.resolve("after teardown")
				request.reject("after teardown")
				assert(request.cancelled == 1, `seed={seed}: cancellation count {request.cancelled}`)
			end
			assert(changes == notifications, `seed={seed}: late callback survived owner`)
			runtime:dispose()
			sameCensus(engine, before, `async seed={seed} teardown`)
		end
	end)

	t.it("preserves UTF8 edit state and gates actions through 200 seeded preference and visibility storms", function()
		local labels = { "保存", "مرحبا", "Café", "👩‍🚀", "é", "Long translated label with spaces" }
		for seed = 1, 200 do
			local rng = random(845101 + seed)
			local engine, runtime, root, UI = world()
			local before = engine.census()
			local text, size, enabled = Compose.cell("Initial"), Compose.cell(16), Compose.cell(true)
			local activations, field, button = 0, nil, nil
			local stop, panel = runtime.mount(function()
				field = UI.TextInput({ value = text, TextSize = size })
				button = UI.Button({
					label = text,
					TextSize = size,
					enabled = enabled,
					onActivate = function()
						activations += 1
					end,
				})
				return runtime.constructors.Frame({ field, button })
			end, root)
			field:CaptureFocus()
			for step = 1, 40 do
				panel.Visible = true
				root.Enabled = true
				field:CaptureFocus()
				local value = labels[rng(1, #labels)]
				field.Text = value
				size:set(rng(12, 48))
				assert(
					text:peek() == value and field.Text == value and button.Text == value,
					`seed={seed} step={step}: expected={value} model={text:peek()} editor={field.Text} button={button.Text}`
				)
				assert(field:IsFocused(), `seed={seed} step={step}: preference lost editing focus`)
				assert(field.TextSize == size:peek() and button.TextSize == size:peek(), `seed={seed}: stale text size`)
				enabled:set(rng(0, 1) == 1)
				panel.Visible = rng(0, 1) == 1
				root.Enabled = rng(0, 1) == 1
				local prior = activations
				button.Activated.fire()
				local expected = if enabled:peek() and panel.Visible and root.Enabled then 1 else 0
				assert(activations == prior + expected, `seed={seed} step={step}: action eligibility stale`)
			end
			stop()
			runtime:dispose()
			sameCensus(engine, before, `preference seed={seed} teardown`)
		end
	end)

	t.it("keeps mounted controls and activation through 200 seeded preferred input storms", function()
		for seed = 1, 200 do
			local rng = random(917359 + seed)
			local engine, runtime, root, UI, input, gui = world()
			local before = engine.census()
			local builds, activations, value = 0, 0, Compose.cell(3)
			local stop, panel = runtime.mount(function()
				builds += 1
				return runtime.constructors.Frame({
					UI.Button "A" {
						label = "A",
						onActivate = function()
							activations += 1
						end,
					},
					UI.Button "B" { label = "B" },
					UI.Stepper "Stepper" { value = value, max = 10 },
				})
			end, root)
			local a, b, stepper = find(panel, "A"), find(panel, "B"), find(panel, "Stepper")
			local inputs = {
				engine.types.Enum.PreferredInput.Touch,
				engine.types.Enum.PreferredInput.Gamepad,
				engine.types.Enum.PreferredInput.KeyboardAndMouse,
			}
			local pressed = 0
			for step = 1, rng(5, 40) do
				local choice = inputs[rng(1, #inputs)]
				if rng(1, 10) <= 3 then
					gui.SelectedObject = a
					input.PreferredInput = choice
					a.Activated.fire()
					pressed += 1
				else
					input.PreferredInput = choice
				end
				assert(builds == 1, `seed={seed} step={step}: the input switch rebuilt the screen`)
				assert(
					find(panel, "A") == a and find(panel, "B") == b and find(panel, "Stepper") == stepper,
					`seed={seed} step={step}: the input switch remounted a control`
				)
			end
			assert(activations == pressed, `seed={seed}: {pressed} presses produced {activations} activations`)
			gui.SelectedObject = b
			assert(gui.SelectedObject == b, `seed={seed}: selection is lost after the storm`)
			stop()
			runtime:dispose()
			sameCensus(engine, before, `input switch seed={seed} teardown`)
		end
	end)

	t.it("disposes with pending changes, twice, and from inside a change notification", function()
		local engine, runtime, root, UI = world()
		local before = engine.census()
		local text = Compose.cell("hello")
		local stop = runtime.mount(function()
			return UI.Text "Text" { text = text }
		end, root)
		text:set("dirty now")
		stop()
		stop()
		sameCensus(engine, before, "dispose with a pending change, then again")
		local flag = Compose.cell(false)
		local disposed = 0
		local stopNotify, panel = runtime.mount(function()
			return runtime.constructors.Frame({
				Compose.show(flag, function()
					return UI.Text "On" { text = "on" }
				end),
			})
		end, root)
		local connection = panel.ChildAdded:Connect(function()
			disposed += 1
			stopNotify()
		end)
		flag:set(true)
		connection:Disconnect()
		t.expect(disposed >= 1).toBe(true)
		t.expect(panel.Parent).toBe(nil)
		stopNotify()
		runtime:dispose()
		sameCensus(engine, before, "dispose from a notification")
	end)

	t.it("keeps the top modal active and selected when a covered modal dismisses, 50 times", function()
		local engine, runtime, root, UI, _, gui = world()
		local before = engine.census()
		local sheet, alert = Compose.cell(false), Compose.cell(false)
		local stop = runtime.mount(function()
			return runtime.constructors.Frame({
				UI.Button "Base" { label = "Base" },
				UI.Sheet({
					isPresented = sheet,
					detent = Compose.cell("medium"),
					content = function()
						return UI.Button "SheetAction" { label = "Sheet" }
					end,
				}),
				UI.Alert({
					isPresented = alert,
					title = "Confirm",
					actions = { { id = "ok", label = "OK" }, { id = "cancel", label = "Cancel", role = "cancel" } },
				}),
			})
		end, root)
		for cycle = 1, 50 do
			gui.SelectedObject = find(root, "Base")
			sheet:set(true)
			alert:set(true)
			local alertPanel = find(root, "AlertPanel")
			assert(alertPanel ~= nil, `cycle {cycle}: the alert is presented`)
			assert(within(gui.SelectedObject, alertPanel), `cycle {cycle}: the selection is not in the top alert`)
			sheet:set(false)
			assert(find(root, "SheetPanel") == nil, `cycle {cycle}: the covered sheet stayed`)
			assert(find(root, "AlertPanel") == alertPanel, `cycle {cycle}: the alert remounted`)
			assert(within(gui.SelectedObject, alertPanel), `cycle {cycle}: the selection left the top alert`)
			alert:set(false)
			assert(find(root, "AlertPanel") == nil, `cycle {cycle}: the alert stayed`)
		end
		stop()
		runtime:dispose()
		sameCensus(engine, before, "modal stack teardown")
	end)
end)
