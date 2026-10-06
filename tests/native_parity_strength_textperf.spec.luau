--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local nativeApp = require("../bench/native_app")
	local perfRunner = require("../bench/perf_runner")
	local perfProfiles = require("../bench/perf_profiles")
	local lab = require("../examples/performance/lab/perf_lab")
	local textDegrade = require("../examples/gallery/scenarios/text_degrade")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

	local function find(root: any, name: string): any
		if root.Name == name then
			return root
		end
		for _, child in root:GetChildren() do
			local found = find(child, name)
			if found then
				return found
			end
		end
		return nil
	end

	local function world(options: { [string]: any }?): (any, any, any, any)
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local config: { [string]: any } = {
			types = engine.types,
			motionLevel = "none",
			guiService = gui,
			userInputService = input,
			services = { GuiService = gui, UserInputService = input },
		}
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config :: any)
		return engine, runtime, UI, input
	end

	local function labModules(failing: string?): { [string]: any }
		local workloads = require("../examples/performance/lab/workloads")
		local wrapped = table.clone(workloads)
		wrapped.create = function(context: any, scene: string, dataset: any)
			local workload: any = workloads.create(context, scene, dataset)
			if failing and scene == failing then
				workload.step = function()
					error("injected workload failure")
				end
			end
			return workload
		end
		return {
			sensory = require("../examples/performance/lab/sensory"),
			dataset = require("../examples/performance/lab/dataset"),
			rows = require("../examples/performance/lab/rows"),
			capture = require("../examples/performance/lab/capture"),
			workloads = wrapped,
		}
	end

	local function labFixture(failing: string?): (any, any, any)
		local app = nativeApp()
		local probe
		app.heartbeat = app.engine.heartbeat
		app.captureFacts = function()
			return {
				evidenceClass = "lune",
				capturedAtIso = "2026-09-23T00:00:00Z",
				sourceStamp = "test",
				placeName = "headless",
				viewport = "800x600",
				orientation = "landscape" :: "landscape",
				graphicsQualityLevel = "n/a",
				frameTarget = "n/a",
				studioVersion = "n/a",
				deviceLabel = "lune",
				thermalNote = "n/a",
			}
		end
		app.probe = function(value)
			probe = value
		end
		local root
		app.runtime.mount(function()
			root = app.Host.ScreenGui({ lab.build(app, labModules(failing)) })
			return root
		end, app.target)
		return app, probe, root
	end

	local function workloadNode(mounted: any): any
		local found = nil
		for _, child in mounted:GetChildren() do
			if child.ClassName ~= "UIFlexItem" then
				assert(found == nil, "more than one workload is mounted")
				found = child
			end
		end
		return found
	end

	local function readout(root: any): string
		local labels = {}
		for _, node in root:GetDescendants() do
			if node.ClassName == "TextLabel" then
				table.insert(labels, node.Text)
			end
		end
		return table.concat(labels, "\n")
	end

	verifyHarness:suite("performance lab evidence", function()
		verifyHarness:case("feedback is off by default, event driven, and says so in its status line", {
			id = "native_parity_strength_textperf::performance lab evidence::feedback is off by default, event driven, and says so in its status line",
			run = function()
				local app, probe, root = labFixture()
				probe.select("sensory-cascade", 120)
				local active = probe.state().active
				Verify.expect(string.find(readout(root), "Haptics off; no effects constructed", 1, true) ~= nil)
					:toBe(true)
				active.setEnabled(true)
				for _ = 1, 30 do
					app.frame()
				end
				Verify.expect(active.counters.built):toBe(0)
				Verify.expect(active.counters.requests):toBe(0)
				Verify.expect(active.counters.presses):toBe(0)
				Verify.expect(string.find(readout(root), "Haptics off; no effects constructed", 1, true) ~= nil)
					:toBe(true)
				active.step()
				Verify.expect(active.counters.requests):toBe(16)
				Verify.expect(active.counters.arms.undeclared.requests):toBe(0)
				Verify.expect(active.counters.arms.undeclaredRepeat.requests):toBe(0)
				Verify.expect(active.counters.arms.sharedEffect.requests)
					:toBe(active.counters.arms.sharedEffect.pressesDriven)
				Verify.expect(active.counters.arms.perLeafEffect.requests)
					:toBe(active.counters.arms.perLeafEffect.pressesDriven)
				Verify.expect(
					string.find(readout(root), "32 presses · 121 effects built · 16 playback requests", 1, true)
						~= nil
				)
					:toBe(true)
				active.setEnabled(false)
				active.step()
				Verify.expect(
					string.find(readout(root), "32 presses · 0 effects built · 0 playback requests", 1, true) ~= nil
				)
					:toBe(true)
				app.dispose()
			end,
		})

		verifyHarness:case("selecting a workload restores the settings it does not declare", {
			id = "native_parity_strength_textperf::performance lab evidence::selecting a workload restores the settings it does not declare",
			run = function()
				local app, probe = labFixture()
				probe.select("sensory-cascade", 120)
				local first = probe.state().active
				first.setEnabled(true)
				first.step()
				Verify.expect(first.counters.built):toBe(121)
				probe.select("dense-scroll", 100)
				probe.select("sensory-cascade", 120)
				local second = probe.state().active
				Verify.expect(second ~= first):toBe(true)
				second.step()
				Verify.expect(second.counters.enabled):toBe(false)
				Verify.expect(second.counters.built):toBe(0)
				Verify.expect(probe.state().iterations):toBe(0)
				app.dispose()
			end,
		})

		verifyHarness:case("a full resize pass leaves the workload mounted", {
			id = "native_parity_strength_textperf::performance lab evidence::a full resize pass leaves the workload mounted",
			run = function()
				local app, probe = labFixture()
				probe.select("resize-relayout", 100)
				local active = probe.state().active
				local mounted = app.target:FindFirstChild("Workload", true)
				local node = workloadNode(mounted)
				for _ = 1, 40 do
					probe.step(1 / 60)
				end
				Verify.expect(probe.state().active):toBe(active)
				Verify.expect((node:isDestroyed())):toBe(false)
				Verify.expect(node.Parent):toBe(mounted)
				Verify.expect(probe.state().iterations):toBe(40)
				app.dispose()
			end,
		})

		verifyHarness:case("run all continues past a failing workload and ends with the dump instruction", {
			id = "native_parity_strength_textperf::performance lab evidence::run all continues past a failing workload and ends with the dump instruction",
			run = function()
				local app, probe, root = labFixture("collection-mutation")
				probe.select("idle-baseline", 100)
				probe.sweep()
				Verify.expect(probe.state().playing):toBe(true)
				for _ = 1, #lab.WORKLOADS do
					app.frame()
				end
				Verify.expect(probe.state().queued):toBe(0)
				Verify.expect(probe.state().playing):toBe(false)
				Verify.expect(probe.state().captures):toBe(#lab.WORKLOADS - 1)
				Verify.expect(probe.state().selected):toBe(lab.WORKLOADS[#lab.WORKLOADS].id)
				Verify.expect(
					string.find(readout(root), `Captured {#lab.WORKLOADS - 1} · JSON written to the output`, 1, true)
						~= nil
				):toBe(true)
				app.dispose()
			end,
		})

		verifyHarness:case("stop halts run all between workloads and reset unmounts the workload", {
			id = "native_parity_strength_textperf::performance lab evidence::stop halts run all between workloads and reset unmounts the workload",
			run = function()
				local app, probe = labFixture()
				probe.select("idle-baseline", 100)
				probe.sweep()
				app.frame()
				app.frame()
				app.frame()
				probe.stop()
				local captured = probe.state().captures
				Verify.expect(captured):toBe(3)
				for _ = 1, 10 do
					app.frame()
				end
				Verify.expect(probe.state().captures):toBe(captured)
				Verify.expect(probe.state().queued):toBe(0)
				probe.select("dense-scroll", 200)
				local mounted = app.target:FindFirstChild("Workload", true)
				local node = workloadNode(mounted)
				probe.reset()
				Verify.expect((node:isDestroyed())):toBe(true)
				Verify.expect(probe.state().selected):toBe("idle-baseline")
				Verify.expect(probe.state().iterations):toBe(0)
				local replacement = workloadNode(mounted)
				Verify.expect(replacement ~= nil):toBe(true)
				Verify.expect(replacement ~= node):toBe(true)
				app.dispose()
			end,
		})

		verifyHarness:case("the perf runner counts live native connections for an engine scene", {
			id = "native_parity_strength_textperf::performance lab evidence::the perf runner counts live native connections for an engine scene",
			run = function()
				local scene = {
					name = "engine-connections",
					requirement = "UI-PERF-001",
					dataset = "one button",
					setup = function()
						local app = nativeApp()
						local label = Compose.cell("Go")
						app.runtime.mount(function()
							return app.Host.ScreenGui({
								app.UI.Button({ label = label, onActivate = function() end }) :: unknown,
								app.UI.Button({ label = "Other", onActivate = function() end }),
							})
						end, app.target)
						return { engine = app.engine, target = app.target, app = app, label = label, n = 0 }
					end,
					run = function(state: any)
						state.n += 1
						state.label:set(`Go {state.n}`)
						return nil
					end,
					teardown = function(state: any)
						state.app.dispose()
					end,
				}
				local record =
					perfRunner.runScene(scene, perfProfiles.get(perfProfiles.REFERENCE), { warmup = 1, samples = 3 })
				Verify.expect((type(record.liveConnections))):toBe("number")
				Verify.expect(record.liveConnections >= 2):toBe(true)
				Verify.expect((type(record.metrics.instances))):toBe("number")
				Verify.expect(record.metrics.instances >= 2):toBe(true)
				Verify.expect(record.liveRegistry.registrations.measured):toBe(false)
			end,
		})
	end)

	verifyHarness:suite("fine-grained cost at any collection size", function()
		local function metered(count: number, grid: boolean)
			local engine = engineLib.new({ recordCreated = false })
			local metrics = { writes = 0, creates = 0, destroys = 0 }
			local make, destroy = engine.new, engine.destroy
			engine.new = function(className)
				local node = make(className)
				metrics.creates += 1
				local meta = getmetatable(node)
				local write = meta.__newindex
				meta.__newindex = function(self, key, value)
					metrics.writes += 1
					write(self, key, value)
				end
				return node
			end
			engine.destroy = function(node)
				metrics.destroys += 1
				destroy(node)
			end
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local Host = (runtime.constructors :: unknown) :: RobloxHost
			local UI = Facet.controls(runtime, { types = engine.types })
			local D2, V2 = engine.types.UDim2, engine.types.Vector2
			local items = {}
			for index = 1, count do
				items[index] = { id = tostring(index), value = Compose.cell(index) }
			end
			local target = engine.new("Folder")
			local list
			local spec = {
				from = items,
				key = function(item)
					return item.id
				end,
				itemSize = 56,
				columns = if grid then 4 else nil,
				render = function(current): GuiObject
					local item = current:peek()
					return Host.Frame({
						Size = D2.new(1, 0, 0, 56),
						Host.TextLabel({
							Text = function(use: Use)
								return tostring(use(item.value))
							end,
						}),
					})
				end,
				Size = D2.fromScale(1, 1),
			}
			local stop = runtime.mount(function()
				list = if grid then UI.VirtualGrid(spec) else UI.VirtualList(spec)
				return Host.ScreenGui({ list :: unknown })
			end, target)
			list.AbsoluteSize = V2.new(480, 640)
			list.AbsoluteWindowSize = V2.new(480, 640)
			local function delta(action: () -> ()): { writes: number, creates: number, destroys: number }
				metrics.writes, metrics.creates, metrics.destroys = 0, 0, 0
				action()
				return { writes = metrics.writes, creates = metrics.creates, destroys = metrics.destroys }
			end
			return {
				items = items,
				runtime = runtime,
				delta = delta,
				dispose = function()
					stop()
					runtime:dispose()
					Verify.expect(#target:GetChildren()):toBe(0)
				end,
			}
		end

		verifyHarness:case(
			"one visible change, one off-window change and a burst cost the same at 200, 2000 and 20000 rows",
			{
				id = "native_parity_strength_textperf::fine-grained cost at any collection size::one visible change, one off-window change and a burst cost the same at 200, 2000 and 20000 rows",
				run = function()
					for _, grid in { false, true } do
						for _, count in { 200, 2000, 20000 } do
							local state = metered(count, grid)
							local visible = state.delta(function()
								state.items[3].value:set(-3)
							end)
							Verify.expect(visible.writes):toBe(1)
							Verify.expect(visible.creates):toBe(0)
							Verify.expect(visible.destroys):toBe(0)
							local offWindow = state.delta(function()
								state.items[count].value:set(-1)
								state.items[count - 1].value:set(-2)
							end)
							Verify.expect(offWindow.writes):toBe(0)
							Verify.expect(offWindow.creates):toBe(0)
							Verify.expect(offWindow.destroys):toBe(0)
							local burst = state.delta(function()
								for write = 1, 50 do
									state.items[2].value:set(1000 + write)
								end
							end)
							Verify.expect(burst.writes):toBe(50)
							Verify.expect(burst.creates):toBe(0)
							local batched = state.delta(function()
								state.runtime:batch(function()
									for write = 1, 50 do
										state.items[2].value:set(2000 + write)
									end
								end)
							end)
							Verify.expect(batched.writes):toBe(1)
							Verify.expect(batched.creates):toBe(0)
							state.dispose()
						end
					end
				end,
			}
		)
	end)

	verifyHarness:suite("compact text before truncation", function()
		local function compactButton(options: { [string]: any }?): (any, any, any, () -> ())
			local engine, runtime, UI = world()
			local spec: { [string]: any } = { label = "Continue to checkout", compactLabel = "Continue" }
			for key, value in (options or {}) :: { [string]: any } do
				spec[key] = value
			end
			local stop, node: any = runtime.mount(function()
				return UI.Button(spec)
			end, engine.new("ScreenGui"))
			return engine, node, find(node, "FullLabelMeasure"), function()
				stop()
				runtime:dispose()
			end
		end

		verifyHarness:case("keeps the full label while it fits and swaps to the compact form at every narrower width", {
			id = "native_parity_strength_textperf::compact text before truncation::keeps the full label while it fits and swaps to the compact form at every narrower width",
			run = function()
				local engine, node, measure, stop = compactButton()
				local V2 = engine.types.Vector2
				Verify.expect(measure.TextWrapped):toBe(false)
				Verify.expect(measure.Visible):toBe(false)
				Verify.expect(measure.Text):toBe("Continue to checkout")
				measure.TextBounds = V2.new(180, 20)
				Verify.expect(node.Text):toBe("Continue to checkout")
				for _, case in
					{
						{ 400 :: unknown, false },
						{ 205 :: unknown, false },
						{ 204 :: unknown, false },
						{ 203 :: unknown, true },
						{ 150 :: unknown, true },
						{ 60 :: unknown, true },
					}
				do
					node.AbsoluteSize = V2.new(case[1], 44)
					Verify.expect(node.Text):toBe(if case[2] then "Continue" else "Continue to checkout")
				end
				node.AbsoluteSize = V2.new(240, 44)
				Verify.expect(node.Text):toBe("Continue to checkout")
				measure.TextBounds = V2.new(230, 20)
				Verify.expect(node.Text):toBe("Continue")
				measure.TextBounds = V2.new(100, 20)
				Verify.expect(node.Text):toBe("Continue to checkout")
				stop()
			end,
		})

		verifyHarness:case("follows reactive full and compact labels and measures the full label only", {
			id = "native_parity_strength_textperf::compact text before truncation::follows reactive full and compact labels and measures the full label only",
			run = function()
				local label, compact = Compose.cell("Continue to checkout"), Compose.cell("Continue")
				local engine, node, measure, stop = compactButton({ label = label, compactLabel = compact })
				local V2 = engine.types.Vector2
				measure.TextBounds = V2.new(180, 20)
				node.AbsoluteSize = V2.new(120, 44)
				Verify.expect(node.Text):toBe("Continue")
				compact:set("Pay")
				Verify.expect(node.Text):toBe("Pay")
				label:set("Pay now")
				Verify.expect(measure.Text):toBe("Pay now")
				measure.TextBounds = V2.new(60, 20)
				Verify.expect(node.Text):toBe("Pay now")
				stop()
			end,
		})

		verifyHarness:case("an author-pinned label without a compact form is never replaced", {
			id = "native_parity_strength_textperf::compact text before truncation::an author-pinned label without a compact form is never replaced",
			run = function()
				local engine, runtime, UI = world()
				local stop, node: any = runtime.mount(function()
					return UI.Button({ label = "Continue to checkout" })
				end, engine.new("ScreenGui"))
				Verify.expect((find(node, "FullLabelMeasure"))):toBeNil()
				for _, width in { 400, 120, 40 } do
					node.AbsoluteSize = engine.types.Vector2.new(width, 44)
					Verify.expect(node.Text):toBe("Continue to checkout")
				end
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("the text degrade demo declares a compact sort label and binds each width stop", {
			id = "native_parity_strength_textperf::compact text before truncation::the text degrade demo declares a compact sort label and binds each width stop",
			run = function()
				local engine, runtime, UI = world()
				local built = textDegrade.build({
					UI = UI,
					Compose = Compose,
					Host = (runtime.constructors :: unknown) :: RobloxHost,
					types = engine.types,
				})
				local stop, screen: any = runtime.mount(built.screen, engine.new("ScreenGui"))
				local row = find(screen, "Row")
				local sort = find(row, "Sort")
				local measure = find(sort, "FullLabelMeasure")
				Verify.expect(measure ~= nil):toBe(true)
				Verify.expect(sort.Text):toBe(textDegrade.copy.sortLabel)
				measure.TextBounds = engine.types.Vector2.new(70, 20)
				for _, entry in textDegrade.stops do
					built.steps.setStop(built, entry.value)
					if entry.width then
						Verify.expect(row.Size.X.Scale):toBe(0)
						Verify.expect(row.Size.X.Offset):toBe(entry.width)
					else
						Verify.expect(row.Size.X.Scale):toBe(1)
					end
				end
				sort.AbsoluteSize = engine.types.Vector2.new(120, 40)
				Verify.expect(sort.Text):toBe(textDegrade.copy.sortLabel)
				sort.AbsoluteSize = engine.types.Vector2.new(60, 40)
				Verify.expect(sort.Text):toBe(textDegrade.sortCompact)
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("preferred text size and disclosure", function()
		verifyHarness:case("a text size swing in any order matches a surface born at that size", {
			id = "native_parity_strength_textperf::preferred text size and disclosure::a text size swing in any order matches a surface born at that size",
			run = function()
				local function surface(initial: number)
					local app = nativeApp()
					local T = app.types
					local size, text = Compose.cell(initial), Compose.cell("Value")
					local package = Compose.cell(themes.neutralPackage())
					local UI = Facet.controls(app.runtime, { types = T, theme = package })
					local records = {}
					for index = 1, 40 do
						records[index] = { id = index, label = tostring(index) }
					end
					local field, button, list
					app.runtime.mount(function()
						field = UI.TextInput({ value = text, TextSize = size })
						button = UI.Button({ label = "Save", TextSize = size })
						list = UI.VirtualList({
							from = records,
							key = function(row)
								return row.id
							end,
							itemSize = 56,
							render = function(current): GuiObject
								return UI.Text({
									text = function(use: Use)
										return use(current).label
									end,
									TextSize = size,
								})
							end,
						})
						return app.Host.ScreenGui({ field :: unknown, button, list })
					end, app.target)
					list.AbsoluteWindowSize = T.Vector2.new(320, 400)
					return { app = app, size = size, package = package, field = field, button = button, list = list }
				end
				local function shape(state: any): { string }
					local out = {}
					for _, node in state.app.target:GetDescendants() do
						local text = if node:IsA("TextLabel")
								or node:IsA("TextButton")
								or node:IsA("TextBox")
							then `{node.Text}:{(node :: TextBox).TextSize}`
							else ""
						table.insert(out, `{node.ClassName}:{node.Name}:{text}`)
					end
					return out
				end
				local born = surface(40)
				local expected = shape(born)
				table.sort(expected)
				for _, order in { { 28, 40 }, { 16, 28, 40 }, { 40, 16, 40 } } do
					local swung = surface(16)
					local nodes = swung.app.target:GetDescendants()
					for _, value in order do
						swung.size:set(value)
					end
					local current = swung.app.target:GetDescendants()
					Verify.expect(#current):toBe(#nodes)
					for index, node in nodes do
						Verify.expect(current[index]):toBe(node)
					end
					local actual = shape(swung)
					table.sort(actual)
					Verify.expect(#actual):toBe(#expected)
					for index, line in expected do
						Verify.expect(actual[index]):toBe(line)
					end
					local updated = themes.neutralPackage()
					updated.metrics.controlSizes.regular.height = 52
					swung.package:set(updated)
					Verify.expect((swung.field :: TextBox).TextSize):toBe(40)
					Verify.expect(swung.button.TextSize):toBe(40)
					swung.app.dispose()
				end
				born.app.dispose()
			end,
		})

		verifyHarness:case("segmented pickers, tabs and menu triggers keep the full label available", {
			id = "native_parity_strength_textperf::preferred text size and disclosure::segmented pickers, tabs and menu triggers keep the full label available",
			run = function()
				local engine, runtime, UI = world()
				local long = "An identity value much longer than its slot"
				local selected, tab = Compose.cell("a"), Compose.cell("first")
				local stop, root: any = runtime.mount(function()
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Picker "IdentitySegments" {
							selected = selected,
							style = "segmented" :: "segmented",
							options = {
								{ value = "a", label = long } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Short" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						} :: unknown,
						UI.Picker "MenuPicker" {
							Size = engine.types.UDim2.fromOffset(120, 40),
							selected = selected,
							style = "menu" :: "menu",
							options = {
								{ value = "a", label = long } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Short" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						},
						UI.TabView "Tabs" {
							selection = tab,
							tabs = {
								{
									id = "first",
									label = long,
									content = function(): Instance
										return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
									end,
								} :: FixtureNavigationTypes.Tab,
								{
									id = "second",
									label = "Second",
									content = function(): Instance
										return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
									end,
								} :: FixtureNavigationTypes.Tab,
							},
						},
					})
				end, engine.new("ScreenGui"))
				Verify.expect((find(find(root, "IdentitySegments"), "a"):GetAttribute("FacetLabel"))):toBe(long)
				local trigger = find(find(root, "MenuPicker"), "Trigger")
				Verify.expect((trigger:GetAttribute("FacetLabel"))):toBe(long)
				Verify.expect(trigger.TextTruncate):toBe(engine.types.Enum.TextTruncate.AtEnd)
				local disclosed = 0
				for _, node in find(root, "Tabs"):GetDescendants() do
					if node:GetAttribute("FacetLabel") == long then
						disclosed += 1
					end
				end
				Verify.expect(disclosed >= 1):toBe(true)
				selected:set("b")
				Verify.expect((trigger:GetAttribute("FacetLabel"))):toBe("Short")
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("a pinned table row still rises to fit one line of text", {
			id = "native_parity_strength_textperf::preferred text size and disclosure::a pinned table row still rises to fit one line of text",
			run = function()
				local engine, runtime, UI, input = world()
				local controls: FixtureComposeTypes.OrderedCollectionControls<any> = {}
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = { { id = 1, label = "One" }, { id = 2, label = "Two" } },
						key = function(item)
							return item.id
						end,
						itemSize = 24,
						controls = controls,
						columns = { { id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any> },
					})
				end, engine.new("ScreenGui"))
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				local row = body:FindFirstChild("1", true)
				local value = row:FindFirstChild("Value", true)
				value.TextBounds = engine.types.Vector2.new(100, 8)
				Verify.expect(assert(controls.placementOf)(2).offset):toBe(24)
				value.TextBounds = engine.types.Vector2.new(100, 60)
				local risen = assert(controls.placementOf)(2).offset
				Verify.expect(risen > 60):toBe(true)
				input.PreferredInput = engine.types.Enum.PreferredInput.Touch
				value.TextBounds = engine.types.Vector2.new(100, 8)
				Verify.expect(assert(controls.placementOf)(2).offset):toBe(24)
				value.TextBounds = engine.types.Vector2.new(100, 60)
				Verify.expect(assert(controls.placementOf)(2).offset):toBe(risen)
				Verify.expect((body:FindFirstChild("1", true))):toBe(row)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("picker textSize reaches every segment reactively and is left to the theme when absent", {
			id = "native_parity_strength_textperf::preferred text size and disclosure::picker textSize reaches every segment reactively and is left to the theme when absent",
			run = function()
				local engine, runtime, UI = world()
				local selected, size = Compose.cell("one"), Compose.cell(16)
				local options = {
					{ value = "one", label = "One" },
					{ value = "two", label = "Two" },
					{ value = "three", label = "Three" },
				}
				local stop, root: any = runtime.mount(function()
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.Picker "Sized" {
							selected = selected,
							textSize = size,
							style = "segmented" :: "segmented",
							options = options,
						} :: unknown,
						UI.Picker "Themed" { selected = selected, style = "segmented" :: "segmented", options = options },
					})
				end, engine.new("ScreenGui"))
				local sized, themed = find(root, "Sized"), find(root, "Themed")
				local default = engine.new("TextButton").TextSize
				for _, value in { 16, 22, 30 } do
					size:set(value)
					for _, option in options do
						Verify.expect(find(sized, option.value).TextSize):toBe(value)
						Verify.expect(find(themed, option.value).TextSize):toBe(default)
					end
				end
				selected:set("three")
				Verify.expect(find(sized, "three").TextSize):toBe(30)
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("decoration cost", function()
		verifyHarness:case("a circular arc uses the same control points at every diameter", {
			id = "native_parity_strength_textperf::decoration cost::a circular arc uses the same control points at every diameter",
			run = function()
				local engine, runtime, UI = world()
				for _, diameter in { 24, 32, 96, 400 } do
					local value = Compose.cell(0.25)
					local stop, node: any = runtime.mount(function()
						return UI.ProgressView({
							presentation = "circular" :: "circular",
							value = value,
							diameter = diameter,
						})
					end, engine.new("Folder"))
					local circle = node:FindFirstChild("Indicator", true)
					local fill, track = circle:FindFirstChild("RingFill"), circle:FindFirstChild("RingTrack")
					Verify.expect(#track:GetControlPoints()):toBe(9)
					Verify.expect(#fill:GetControlPoints()):toBe(3)
					value:set(0.5)
					Verify.expect(#fill:GetControlPoints()):toBe(5)
					value:set(1)
					Verify.expect(#fill:GetControlPoints()):toBe(9)
					stop()
				end
				runtime:dispose()
			end,
		})

		verifyHarness:case("flat recipes add no decoration and a nine-slice recipe adds one image per skinned node", {
			id = "native_parity_strength_textperf::decoration cost::flat recipes add no decoration and a nine-slice recipe adds one image per skinned node",
			run = function()
				local calls: { { slot: string, target: any } } = {}
				local mutable: any = themes
				local original = mutable.skin
				local function fixture(theme: any): (any, () -> ())
					local engine, runtime, UI = world({ theme = theme })
					local stop, root: any = runtime.mount(function()
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							UI.Button({ label = "Save" }) :: unknown,
							UI.Toggle({ value = Compose.cell(false), label = "Ready" }),
							UI.TextInput({ value = Compose.cell("Text") }),
							UI.Slider({ value = Compose.cell(0.5) }),
							UI.Stepper({ value = Compose.cell(1) }),
							UI.Chip({ label = "Chip", selected = Compose.cell(false) }),
							UI.Picker({
								selected = Compose.cell("a"),
								style = "segmented" :: "segmented",
								options = {
									{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							}),
							UI.ProgressView({ value = 0.5 }),
						})
					end, engine.new("ScreenGui"))
					return root, function()
						stop()
						runtime:dispose()
					end
				end
				local ok, err = pcall(function()
					local depth = 0
					mutable.skin = function(runtime: any, theme: any, slot: string, options: any)
						if depth == 0 then
							table.insert(calls, { slot = slot, target = options.target })
						end
						depth += 1
						local ok, result = pcall(original, runtime, theme, slot, options)
						depth -= 1
						if not ok then
							error(result, 0)
						end
						return result
					end
					local flatRoot, stopFlat = fixture(themes.neutralPackage())
					Verify.expect(#calls):toBe(0)
					local flatImages = 0
					for _, node in flatRoot:GetDescendants() do
						if node.ClassName == "ImageLabel" then
							flatImages += 1
						end
					end
					stopFlat()
					local _, stopProbe = fixture(Compose.cell(themes.neutralPackage()))
					local slots: { [string]: boolean? } = {}
					for _, call in calls do
						slots[call.slot] = true
					end
					stopProbe()
					Verify.expect(next(slots) ~= nil):toBe(true)
					local art = themes.neutralPackage()
					assert(art.assets).slice = { content = "rbxassetid://30" }
					slots.barCap, slots.barCenter = nil, nil
					for slot in slots do
						assert(art.chrome)[slot] = { kind = "nineSlice" :: "nineSlice", asset = "slice" }
					end
					table.clear(calls)
					local artRoot, stopArt = fixture(art)
					Verify.expect(#calls > 0):toBe(true)
					local skinned: { [any]: string } = {}
					for _, call in calls do
						Verify.expect(skinned[call.target]):toBeNil()
						skinned[call.target] = call.slot
					end
					local boxes = 0
					for target, slot in skinned do
						local expected = if target.ClassName == "TextBox" then 0 else 1
						boxes += 1 - expected
						local images = 0
						for _, child in target:GetDescendants() do
							if child.ClassName == "ImageLabel" and child.Name == slot .. "1" then
								images += 1
								Verify.expect(child.Image):toBe("rbxassetid://30")
							end
						end
						Verify.expect(images):toBe(expected)
					end
					local artImages = 0
					for _, node in artRoot:GetDescendants() do
						if node.ClassName == "ImageLabel" then
							artImages += 1
						end
					end
					Verify.expect(artImages):toBe(flatImages + #calls - boxes)
					stopArt()
				end)
				mutable.skin = original
				if not ok then
					error(err, 0)
				end
			end,
		})
	end)
end
