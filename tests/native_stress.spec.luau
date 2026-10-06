--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T
	local process = require("@lune/process")

	local cells = require("./lib/cells")
	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local terminal = require("../examples/gallery/examples/outpost_terminal")
	local Compose: ComposeModule = Facet.Compose

	local function world()
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local root = engine.new("ScreenGui")
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		local UI = Facet.controls(runtime, {
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			motionLevel = "none",
		})
		return engine, runtime, root, UI, input, gui
	end

	local function find(node: any, name: string): any
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
		assert(
			now.connections == baseline.connections,
			`{label}: connections {baseline.connections} -> {now.connections}`
		)
	end

	local function random(seed: number)
		return function(low: number, high: number)
			seed = (seed * 48271) % 2147483647
			return low + seed % (high - low + 1)
		end
	end

	verifyHarness:suite("native stress invariants", function()
		verifyHarness:case("detects detached instance and service connection leaks in the census", {
			id = "native_stress::native stress invariants::detects detached instance and service connection leaks in the census",
			run = function()
				local engine = engineLib.new()
				local service = engine.new("GuiService")
				local baseline = engine.census()
				local orphan = engine.new("Frame")
				Verify.expect((pcall(sameCensus, engine, baseline, "orphan"))):toBe(false)
				orphan:Destroy()
				local connection = service:GetPropertyChangedSignal("SelectedObject"):Connect(function() end)
				Verify.expect((pcall(sameCensus, engine, baseline, "connection"))):toBe(false)
				connection:Disconnect()
				sameCensus(engine, baseline, "cleaned")
			end,
		})

		verifyHarness:case(
			"collects disposed runtimes and disposed controls contexts whose reactive motion level closes over them",
			{
				id = "native_stress::native stress invariants::collects disposed runtimes and disposed controls contexts whose reactive motion level closes over them",
				run = function()
					local result = process.exec("lune", { "run", "tests/lib/motion_level_leak" })
					Verify.expect(result.stdout):toBe("retained 0\npublished 0 contexts 0\n")
				end,
			}
		)

		verifyHarness:case("lets a disposed runtime's engine be collected", {
			id = "native_stress::native stress invariants::lets a disposed runtime's engine be collected",
			run = function()
				local result = process.exec("lune", { "run", "tests/lib/disposed_engine" })
				Verify.expect(result.stdout):toBe("collected\n")
			end,
		})

		verifyHarness:case("returns all instances and connections to baseline through 200 modal cycles twice", {
			id = "native_stress::native stress invariants::returns all instances and connections to baseline through 200 modal cycles twice",
			run = function()
				for replay = 1, 2 do
					local engine, runtime, root, UI = world()
					local before = engine.census()
					local shown = Compose.cell(false)
					local stop = runtime.mount(function()
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							UI.Button "Base" { label = "Open" } :: unknown,
							UI.Alert({
								isPresented = shown,
								title = "Confirm",
								actions = { { id = "ok", label = "OK" } :: FixtureNavigationTypes.AlertAction<any> },
							}),
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
			end,
		})

		verifyHarness:case("reclaims detached and pooled rows through 100 structural cycles twice", {
			id = "native_stress::native stress invariants::reclaims detached and pooled rows through 100 structural cycles twice",
			run = function()
				for replay = 1, 2 do
					local engine, runtime, root, UI = world()
					local before = engine.census()
					local initial = { { id = "a" }, { id = "b" }, { id = "c" } }
					local source = Compose.cell(initial)
					local stop, node: any = runtime.mount(function()
						return UI.VirtualList({
							from = source,
							key = function(item)
								return item.id
							end,
							itemSize = 20,
							overscan = 0,
							render = function(current): GuiObject
								return UI.Button({
									label = function(use: Use)
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
			end,
		})

		verifyHarness:case("preserves keyed row content and bounded retention across 400 replayable mutation seeds", {
			id = "native_stress::native stress invariants::preserves keyed row content and bounded retention across 400 replayable mutation seeds",
			run = function()
				for seed = 1, 400 do
					local rng = random(260720 + seed)
					local engine, runtime, root, UI = world()
					local before = engine.census()
					local rows = {}
					for index = 1, 80 do
						rows[index] = { id = index, label = tostring(index) }
					end
					local nextId, source, status = 80, Compose.cell(rows), cells.collectionStatus()
					local stop, node: any = runtime.mount(function()
						return UI.VirtualList({
							from = source,
							key = function(item)
								return item.id
							end,
							itemSize = 20,
							overscan = 0,
							status = status,
							render = function(current): GuiObject
								return UI.Button "Value" {
									label = function(use: Use)
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
			end,
		})

		verifyHarness:case(
			"converges authoritative snapshots under 400 seeded delayed duplicated reordered deliveries",
			{
				id = "native_stress::native stress invariants::converges authoritative snapshots under 400 seeded delayed duplicated reordered deliveries",
				run = function()
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
								Host = (runtime.constructors :: unknown) :: RobloxHost,
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
							assert(
								built.model.revision:peek() == highest,
								`seed={seed} step={step}: revision regressed`
							)
							assert(
								built.model.confirmed:peek().door == highest % 3,
								`seed={seed} step={step}: authority diverged`
							)
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
				end,
			}
		)
		verifyHarness:case("rejects stale async completions and cancels exactly once through 200 seeded fault storms", {
			id = "native_stress::native stress invariants::rejects stale async completions and cancels exactly once through 200 seeded fault storms",
			run = function()
				for seed = 1, 200 do
					local rng = random(611001 + seed)
					local engine, runtime, root, UI = world()
					local before = engine.census()
					local source, requests, changes = Compose.cell("initial" :: string?), {}, 0
					local stop, node: any = runtime.mount(function()
						return UI.AsyncImage({
							source = source,
							loader = function(content: string, resolve: (string?) -> (), reject: (unknown) -> ())
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
			end,
		})

		verifyHarness:case(
			"preserves UTF8 edit state and gates actions through 200 seeded preference and visibility storms",
			{
				id = "native_stress::native stress invariants::preserves UTF8 edit state and gates actions through 200 seeded preference and visibility storms",
				run = function()
					local labels =
						{ "保存", "مرحبا", "Café", "👩‍🚀", "é", "Long translated label with spaces" }
					for seed = 1, 200 do
						local rng = random(845101 + seed)
						local engine, runtime, root, UI = world()
						local before = engine.census()
						local text, size, enabled = Compose.cell("Initial"), Compose.cell(16), Compose.cell(true)
						local activations, field, button = 0, nil, nil
						local stop, panel: any = runtime.mount(function()
							field = UI.TextInput({ value = text, TextSize = size }) :: TextBox
							button = UI.Button({
								label = text,
								TextSize = size,
								enabled = enabled,
								onActivate = function()
									activations += 1
								end,
							})
							return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
								field :: unknown,
								button,
							})
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
							assert(
								field.TextSize == size:peek() and button.TextSize == size:peek(),
								`seed={seed}: stale text size`
							)
							enabled:set(rng(0, 1) == 1)
							panel.Visible = rng(0, 1) == 1
							root.Enabled = rng(0, 1) == 1
							local prior = activations
							local activated = button.Activated :: any
							activated:Fire()
							local expected = if enabled:peek() and panel.Visible and root.Enabled then 1 else 0
							assert(activations == prior + expected, `seed={seed} step={step}: action eligibility stale`)
						end
						stop()
						runtime:dispose()
						sameCensus(engine, before, `preference seed={seed} teardown`)
					end
				end,
			}
		)

		verifyHarness:case("keeps mounted controls and activation through 200 seeded preferred input storms", {
			id = "native_stress::native stress invariants::keeps mounted controls and activation through 200 seeded preferred input storms",
			run = function()
				for seed = 1, 200 do
					local rng = random(917359 + seed)
					local engine, runtime, root, UI, input, gui = world()
					local before = engine.census()
					local builds, activations, value = 0, 0, Compose.cell(3)
					local stop, panel: any = runtime.mount(function()
						builds += 1
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							UI.Button "A" {
								label = "A",
								onActivate = function()
									activations += 1
								end,
							} :: unknown,
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
							a.Activated:Fire()
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
			end,
		})

		verifyHarness:case("disposes with pending changes, twice, and from inside a change notification", {
			id = "native_stress::native stress invariants::disposes with pending changes, twice, and from inside a change notification",
			run = function()
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
				local stopNotify, panel: any = runtime.mount(function()
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
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
				Verify.expect(disposed >= 1):toBe(true)
				Verify.expect(panel.Parent):toBe(nil)
				stopNotify()
				runtime:dispose()
				sameCensus(engine, before, "dispose from a notification")
			end,
		})

		verifyHarness:case("keeps the top modal active and selected when a covered modal dismisses, 50 times", {
			id = "native_stress::native stress invariants::keeps the top modal active and selected when a covered modal dismisses, 50 times",
			run = function()
				local engine, runtime, root, UI, _, gui = world()
				local before = engine.census()
				local sheet, alert = Compose.cell(false), Compose.cell(false)
				local stop = runtime.mount(function()
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Button "Base" { label = "Base" } :: unknown,
						UI.Sheet({
							isPresented = sheet,
							detent = Compose.cell("medium"),
							content = function(): Instance
								return UI.Button "SheetAction" { label = "Sheet" }
							end,
						}),
						UI.Alert({
							isPresented = alert,
							title = "Confirm",
							actions = {
								{ id = "ok", label = "OK" } :: FixtureNavigationTypes.AlertAction<any>,
								{ id = "cancel", label = "Cancel", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						}),
					})
				end, root)
				for cycle = 1, 50 do
					gui.SelectedObject = find(root, "Base")
					sheet:set(true)
					alert:set(true)
					local alertPanel = find(root, "AlertPanel")
					assert(alertPanel ~= nil, `cycle {cycle}: the alert is presented`)
					assert(
						within(gui.SelectedObject, alertPanel),
						`cycle {cycle}: the selection is not in the top alert`
					)
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
			end,
		})
	end)
end
