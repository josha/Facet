--!strict
local FixtureRoblox = require("../tools/vendor/verify/src/roblox")
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
local Facet = require("../src")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	local nativeDrag = require("./lib/native_drag")

	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type TextBoxConstructor = typeof(require("@repo/tools/typecheck/aliases").TextBoxConstructor)
	type TextLabelConstructor = typeof(require("@repo/tools/typecheck/aliases").TextLabelConstructor)
	type UIScaleConstructor = typeof(require("@repo/tools/typecheck/aliases").UIScaleConstructor)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	local FixtureCollectionProps = require("../src/ui/collection_props")
	local FixtureEnvironmentTypes = require("../src/ui/environment_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	local FixtureEngineTypes = require("../src/ui/engine_types")
	type Use = FixtureComposeTypes.Use
	type Record = { id: number, label: string }
	local SharedTypes = require("../src/ui/control_types")

	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local context = require("../src/ui/context")
	local registerInputs = require("../src/ui/inputs")
	local registerCollections = require("../src/ui/collections")
	local registerRowActions = require("../src/ui/collection_row_actions")
	local registerTable = require("../src/ui/collection_table")
	local engineLib = require("./lib/native_engine")
	local function idleInput(engine: engineLib.Engine, input: VerifyRoblox.Instance)
		for _, name in { "GetKeysPressed", "GetMouseButtonsPressed", "GetGamepadState", "GetNavigationGamepads" } do
			engine.environment.fakeOn(VerifyRoblox.assertInstance(input), name, function()
				return {}
			end)
		end
		engine.environment.fakeOn(VerifyRoblox.assertInstance(input), "IsGamepadButtonDown", function()
			return false
		end)
		engine.environment.fakeOn(VerifyRoblox.assertInstance(input), "GetLastInputType", function()
			local E = engine.types.Enum
			return if input.PreferredInput == E.PreferredInput.Touch
				then E.UserInputType.Touch
				elseif input.PreferredInput == E.PreferredInput.Gamepad then E.UserInputType.Gamepad1
				else E.UserInputType.MouseMovement
		end)
	end

	local function setup(options: { [string]: any }?)
		local engine, fixture = engineLib.new(options and options.engine)
		local clock: (() -> number)? = options and options.clock
		if clock then
			engine.clock = clock
		end
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local gui = (engine.new("GuiService") :: unknown) :: GuiService
		gui.TouchControlsEnabled = true
		local root = engine.new("ScreenGui")
		engine.environment.fakeOn(VerifyRoblox.assertInstance(gui), "GetInsetArea", function()
			return engine.types.Rect.new(0, 0, 800, 600)
		end)
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui },
			inputParent = root,
			motionLevel = "none",
		}
		for field, value in (options or {}) :: { [string]: any } do
			if field ~= "engine" then
				config[field] = value
			end
		end
		if config.userInputService and config.userInputService.GetPropertyChangedSignal == nil then
			local service: any = (engine.new("UserInputService") :: unknown) :: UserInputService
			engine.environment.fakeOn(service, "IsKeyDown", function()
				return false
			end)
			idleInput(engine, service)
			for key, value in config.userInputService do
				if type(value) == "function" then
					engine.environment.fakeOn(service, key, value)
				else
					engine.environment.poke(service, key, value)
				end
			end
			config.userInputService = service
			config.services.UserInputService = service
		end
		local ctx = context(Compose, runtime, config :: SharedTypes.Config)
		local UI = ({} :: unknown) :: SharedTypes.Controls
		registerInputs(ctx, UI)
		local surfaces = require("../src/ui/nav_modal")(ctx)
		require("../src/ui/nav_menu")(ctx, UI, surfaces)
		require("../src/ui/nav_surfaces")(ctx, UI, surfaces)
		require("../src/ui/nav_popover")(ctx, UI, surfaces)
		require("../src/ui/nav_pages")(ctx, UI, surfaces)
		require("../src/ui/nav_radial")(ctx, UI, surfaces)
		local buildList = registerCollections(ctx, UI)
		registerRowActions(ctx, UI)
		registerTable(ctx, UI, buildList)
		return engine, runtime, UI, root, gui, ctx, fixture
	end

	local function records(count: number): { Record }
		local values = {}
		for index = 1, count do
			values[index] = { id = index, label = tostring(index) }
		end
		return values
	end
	it("rows recycle across keys as the list scrolls", {
		id = "native_collections::rows recycle across keys as the list scrolls",
		run = function()
			local engine, runtime, UI, target = setup()
			local selection: FixtureComposeTypes.Value<{ [string]: boolean }> = Compose.cell({})
			local renders = 0
			local activated = nil
			local stop, mounted = runtime.mount(function()
				local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, string> = {
					from = records(100),
					key = "id",
					itemSize = 20,
					overscan = 0,
					selection = selection,
					selectionMode = "single",
					onActivate = function(_item, key)
						activated = key
					end,
					render = function(current: Compose.ReadOnlyValue<Record>): GuiObject
						renders += 1
						return UI.Button {
							Name = "Label",
							label = function(use)
								return use(current).label
							end,
						}
					end,
				}
				return UI.VirtualList(listSpec)
			end, target)
			local list = (mounted :: unknown) :: ScrollingFrame
			engine.environment.poke(
				VerifyRoblox.assertInstance(list),
				"AbsoluteWindowSize",
				engine.types.Vector2.new(200, 95)
			)
			local before = renders
			expect(before > 0):toBe(true)
			list.CanvasPosition = engine.types.Vector2.new(0, 1000)
			expect(renders):toBe(before)
			local row: Instance? = nil
			for _, node in list:GetDescendants() do
				if node.Name == "51" and node:FindFirstChild("Content") then
					row = node
				end
			end
			expect(row ~= nil):toBe(true)
			local shown = false
			for _, node in assert(row):GetDescendants() do
				shown = shown or (node.Name == "Label" and node:IsA("TextButton") and node.Text == "51")
			end
			expect(shown):toBe(true)
			engine.environment.fire(
				VerifyRoblox.assertInstance(assert(assert(row):FindFirstChild("RowHit", true))),
				"Activated"
			)
			expect(activated):toBe("51")
			expect(selection:peek()["51"]):toBe(true)
			stop()
			runtime:dispose()
		end,
	})
	it("selection indicators keep sole, multiple and recycled row state", {
		id = "native_collections::selection indicators keep sole, multiple and recycled row state",
		run = function(_own, t)
			local createHighlight = require("../src/ui/collection_highlight")
			local owner = Compose.createOwner()
			t:defer(function()
				Compose.owner.dispose(owner)
			end)
			local selected = Compose.cell({ a = true } :: FixtureCollectionTypes.Selection<string>)
			local bind = Compose.withOwner(owner, function()
				return createHighlight(Compose, selected, true)
			end)
			local states: { string } = {}
			local calls = { 0, 0, 0 }
			local keys = { Compose.cell("a"), Compose.cell("b"), Compose.cell("c") }
			local rowOwners: { FixtureComposeTypes.Owner } = {}
			for index, key in keys do
				local rowOwner = Compose.owner.createChild(owner)
				rowOwners[index] = rowOwner
				Compose.withOwner(rowOwner, function()
					bind(key, function(state)
						states[index] = state
						calls[index] += 1
					end)
				end)
			end
			expect(states):toEqual({ "only", "none", "none" })
			selected:set({ b = true, c = false })
			expect(states):toEqual({ "none", "only", "none" })
			expect(calls[3]):toBe(1)
			selected:set({ a = true, b = true })
			expect(states):toEqual({ "selected", "selected", "none" })
			keys[3]:set("a")
			expect(states):toEqual({ "selected", "selected", "selected" })
			Compose.owner.dispose(rowOwners[1])
			local stopped = calls[1]
			selected:set({})
			expect(states):toEqual({ "selected", "none", "none" })
			expect(calls[1]):toBe(stopped)
			selected:set({ a = true })
			expect(states):toEqual({ "selected", "none", "only" })
			local offscreen: FixtureCollectionTypes.Selection<string> = { a = true }
			for index = 1, 10000 do
				offscreen[tostring(index)] = true
			end
			selected:set(offscreen)
			expect(states):toEqual({ "selected", "none", "selected" })
			selected:set({ absent = true })
			expect(states):toEqual({ "selected", "none", "none" })
			keys[3]:set("absent")
			expect(states):toEqual({ "selected", "none", "only" })
		end,
	})
	it("a failing selection painter does not skip another changed row", {
		id = "native_collections::a failing selection painter does not skip another changed row",
		run = function(_own, t)
			local createHighlight = require("../src/ui/collection_highlight")
			local owner = Compose.createOwner()
			t:defer(function()
				Compose.owner.dispose(owner)
			end)
			local selected = Compose.cell({ a = true } :: FixtureCollectionTypes.Selection<string>)
			local failing = false
			local state = "none"
			Compose.withOwner(owner, function()
				local bind = createHighlight(Compose, selected, true)
				bind(Compose.cell("a"), function(nextState)
					if failing and nextState == "none" then
						error("highlight failed", 0)
					end
				end)
				bind(Compose.cell("b"), function(nextState)
					state = nextState
				end)
			end)
			failing = true
			expect(function()
				selected:set({ b = true })
			end):toThrow("highlight failed")
			expect(state):toBe("only")
		end,
	})
	it("selection changes reuse membership until its reactive source changes", {
		id = "native_collections::selection changes reuse membership until its reactive source changes",
		run = function(_own, t)
			local createSelection = require("../src/ui/collection_selection")
			local engine, runtime, _, target, _, ctx = setup()
			t:defer(function()
				runtime:dispose()
			end)
			type Row = { id: number }
			local initial: { Row } = {}
			for index = 1, 128 do
				initial[index] = { id = index }
			end
			local all = Compose.cell(initial, function(): boolean
				return false
			end)
			local visible = Compose.cell({ initial[1] })
			local selected: FixtureComposeTypes.Value<FixtureCollectionTypes.Selection<number>> =
				Compose.cell({ [2] = true })
			local calls = 0
			local stop = runtime.mount(function()
				local spec: FixtureCollectionTypes.SelectionOptions<Row, number> = { selectionFrom = all }
				local controls: FixtureComposeTypes.OrderedCollectionControls<number> = {}
				createSelection(ctx, spec, visible, function(item: Row): number
					calls += 1
					return item.id
				end, controls, selected, "multiple")
				return ctx.Host.Frame {}
			end, target)
			calls = 0
			selected:set({ [3] = true, [128] = true })
			expect(selected:peek()):toEqual({ [3] = true, [128] = true })
			expect(calls):toBe(0)
			all:set({ initial[1], initial[128] })
			expect(selected:peek()):toEqual({ [128] = true })
			expect(calls):toBe(2)
			calls = 0
			selected:set({ [128] = true, [99] = false })
			expect(selected:peek()):toEqual({ [128] = true })
			expect(calls):toBe(0)
			local same = all:peek()
			table.remove(same, 2)
			all:set(same)
			expect(selected:peek()):toEqual({})
			expect(calls):toBe(1)
			stop()
			calls = 0
			all:set({ initial[5] })
			selected:set({ [5] = true })
			expect(calls):toBe(0)
		end,
	})
	it("multiple selection keeps distinct equal table keys", {
		id = "native_collections::multiple selection keeps distinct equal table keys",
		run = function(_own, t)
			local createSelection = require("../src/ui/collection_selection")
			local shift = false
			local _, runtime, _, target, _, ctx = setup({
				userInputService = {
					IsKeyDown = function(_service: unknown, key: unknown): boolean
						return shift and tostring(key) == "Enum.KeyCode.LeftShift"
					end,
				},
			})
			t:defer(function()
				runtime:dispose()
			end)
			local equality = {
				__eq = function(_left: unknown, _right: unknown): boolean
					return true
				end,
			}
			type Key = typeof(setmetatable({}, equality))
			local keys: { Key } = { setmetatable({}, equality), setmetatable({}, equality) }
			local selected: FixtureComposeTypes.Value<FixtureCollectionTypes.Selection<Key>> =
				Compose.cell({ [keys[1]] = true, [keys[2]] = true })
			local editing = Compose.cell(true)
			local choose: ((Key, Key, InputObject?) -> ())? = nil
			local extend: ((Key?, Key) -> ())? = nil
			local stop = runtime.mount(function()
				local controls: FixtureComposeTypes.OrderedCollectionControls<Key> = {
					indexOfKey = function(key: Key): number?
						return if rawequal(key, keys[1]) then 1 elseif rawequal(key, keys[2]) then 2 else nil
					end,
				}
				choose, extend = createSelection(ctx, { editing = editing }, keys, function(key: Key): Key
					return key
				end, controls, selected, "multiple")
				return ctx.Host.Frame {}
			end, target)
			assert(choose)(keys[2], keys[2], nil)
			expect(selected:peek()[keys[1]]):toBe(true)
			expect(selected:peek()[keys[2]]):toBe(nil)
			editing:set(false)
			shift = true
			assert(extend)(keys[1], keys[2])
			expect(selected:peek()[keys[1]]):toBe(true)
			expect(selected:peek()[keys[2]]):toBe(true)
			stop()
		end,
	})
	it("Table data updates skip key validation for an empty height cache", {
		id = "native_collections::Table data updates skip key validation for an empty height cache",
		run = function(_own, t)
			local engine, runtime, UI, target, _, ctx = setup()
			local fixtureTarget: VerifyRoblox.Instance = target
			t:defer(function()
				runtime:dispose()
			end)
			type Row = { id: number, label: string }
			local rows = records(128)
			local source = Compose.cell(rows)
			local calls = 0
			local controls: FixtureComposeTypes.OrderedCollectionControls<number> = {}
			local Host = ctx.Host
			local column: FixtureCollectionTypes.TableColumn<Row, number> = {
				id = "label",
				render = function(_current, _placement, key): Frame
					return Host.Frame { Name = `HeightProbe{key:peek()}`, Size = engine.types.UDim2.fromOffset(100, 0) }
				end,
			}
			runtime.mount(function()
				local spec: FixtureCollectionProps.KeyedTableSpec<Row, number> = {
					from = source,
					key = function(item: Row): number
						calls += 1
						return item.id
					end,
					columns = { column },
					Name = "MeasuredTable",
					itemSize = 20,
					controls = controls,
				}
				return UI.Table(spec)
			end, target)
			local tableNode = assert(fixtureTarget:FindFirstChild("MeasuredTable"))
			local body = assert(tableNode:FindFirstChild("Body"))
			engine.environment.poke(body, "AbsoluteWindowSize", engine.types.Vector2.new(200, 100))
			calls = 0
			source:set(table.clone(rows))
			expect(calls):toBe(256)
			engine.environment.poke(
				assert(tableNode:FindFirstChild("HeightProbe1", true)),
				"AbsoluteSize",
				engine.types.Vector2.new(100, 60)
			)
			expect(assert(controls.placementOf)(2).offset):toBe(76)
			local remaining = table.clone(rows)
			table.remove(remaining, 1)
			source:set(remaining)
			source:set(rows)
			expect(assert(controls.placementOf)(2).offset):toBe(20)
		end,
	})
	describe("Table sort scrolling", function()
		it("extracts sort values once per row while preserving stable ties", {
			id = "native_collections::Table sort scrolling::extracts sort values once per row while preserving stable ties",
			run = function(_own, t)
				local engine, runtime, UI, target, _, ctx = setup()
				local fixtureTarget: VerifyRoblox.Instance = target
				t:defer(function()
					runtime:dispose()
				end)
				type Row = { id: number, rank: number? }
				local rows: { Row } = {}
				for index = 1, 128 do
					rows[index] = { id = index, rank = if index % 4 == 0 then nil else index % 4 }
				end
				local source = Compose.cell(rows)
				local initialSort: FixtureCollectionTypes.Sort? = nil
				local sort = Compose.cell(initialSort)
				local controls: FixtureComposeTypes.OrderedCollectionControls<number> = {}
				local calls = 0
				local Host = ctx.Host
				local column: FixtureCollectionTypes.TableColumn<Row, number> = {
					id = "rank",
					value = function(item: Row): number?
						calls += 1
						return item.rank
					end,
					render = function(): Frame
						return Host.Frame {}
					end,
				}
				runtime.mount(function()
					local spec: FixtureCollectionProps.KeyedTableSpec<Row, number> = {
						from = source,
						key = function(item: Row): number
							return item.id
						end,
						columns = { column },
						Name = "MeasuredTable",
						itemSize = 20,
						sort = sort,
						controls = controls,
					}
					return UI.Table(spec)
				end, target)
				local tableNode = assert(fixtureTarget:FindFirstChild("MeasuredTable"))
				local body = assert(tableNode:FindFirstChild("Body"))
				engine.environment.poke(body, "AbsoluteWindowSize", engine.types.Vector2.new(200, 100))
				calls = 0
				sort:set({ column = "rank", direction = "ascending" })
				expect(calls):toBe(128)
				expect(assert(controls.indexOfKey)(4)):toBe(1)
				expect(assert(controls.indexOfKey)(8)):toBe(2)
				expect(assert(controls.indexOfKey)(1)):toBe(33)
				calls = 0
				sort:set({ column = "rank", direction = "descending" })
				expect(calls):toBe(0)
				expect(assert(controls.indexOfKey)(3)):toBe(1)
				expect(assert(controls.indexOfKey)(7)):toBe(2)
				expect(assert(controls.indexOfKey)(4)):toBe(97)
				local changed = table.clone(rows)
				changed[1] = { id = 1, rank = 9 }
				calls = 0
				source:set(changed)
				expect(calls):toBe(128)
				expect(assert(controls.indexOfKey)(1)):toBe(1)
				expect(assert(controls.indexOfKey)(3)):toBe(2)
			end,
		})
		it("resets sorting and reveals a selected row without changing list anchoring", {
			id = "native_collections::Table sort scrolling::resets sorting and reveals a selected row without changing list anchoring",
			run = function()
				local engine, runtime, UI, target = setup()
				local rows = records(20)
				local sort = Compose.cell(nil :: FixtureCollectionTypes.Sort?)
				local selection = Compose.cell({} :: FixtureCollectionTypes.Selection<number>)
				local controls: FixtureComposeTypes.OrderedCollectionControls<number> = {}
				local stop, mounted = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = rows,
						key = function(item: { id: number, label: string }): number
							return item.id
						end,
						columns = { { id = "id" } },
						itemSize = 20,
						sort = sort,
						selection = selection,
						controls = controls,
					}
					return UI.Table(tableSpec)
				end, target)
				local node = (mounted :: unknown) :: Frame
				local body = assert(node:FindFirstChild("Body")) :: ScrollingFrame
				local geometry = (body :: unknown) :: { AbsoluteWindowSize: Vector2 }
				engine.environment.poke(
					VerifyRoblox.assertInstance(geometry),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 95)
				)
				local function expectTop(key: number)
					for _, height in { 96, 95 } do
						engine.environment.poke(
							VerifyRoblox.assertInstance(geometry),
							"AbsoluteWindowSize",
							engine.types.Vector2.new(200, height)
						)
						expect(body.CanvasPosition.Y):toBe(0)
						expect(assert(body:FindFirstChild("Items")):FindFirstChild(tostring(key)) ~= nil):toBe(true)
					end
				end
				sort:set({ column = "id", direction = "descending" })
				expect(body.CanvasPosition.Y):toBe(0)
				expectTop(20)
				local header = assert(node:FindFirstChild("Sort", true))
				local signal = (header :: unknown) :: { Activated: { Fire: (unknown) -> () } }
				signal.Activated:Fire()
				expect(body.CanvasPosition.Y):toBe(0)
				expectTop(1)
				selection:set({ [1] = true })
				sort:set({ column = "id", direction = "descending" })
				local placement = assert(controls.placementOf)(assert(controls.indexOfKey)(1) :: number)
				expect(body.CanvasPosition.Y <= placement.offset):toBe(true)
				expect(body.CanvasPosition.Y + 95 >= placement.offset + placement.size):toBe(true)
				expect(body.CanvasPosition.Y):toBe(placement.offset + placement.size - 95)
				signal.Activated:Fire()
				expect(body.CanvasPosition.Y):toBe(0)
				selection:set({ [999] = true })
				sort:set({ column = "id", direction = "descending" })
				expect(body.CanvasPosition.Y):toBe(0)
				stop()
				local source = Compose.cell(rows)
				local stopList, mountedList = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, string> = {
						from = source,
						key = "id",
						itemSize = 20,
						render = function(): GuiObject
							return UI.Button { label = "Row" }
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				local list = (mountedList :: unknown) :: ScrollingFrame
				local listGeometry = (list :: unknown) :: { AbsoluteWindowSize: Vector2 }
				engine.environment.poke(
					VerifyRoblox.assertInstance(listGeometry),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 95)
				)
				local reversed = table.clone(rows)
				table.sort(reversed, function(a: Record, b: Record): boolean
					return a.id > b.id
				end)
				source:set(reversed)
				expect(list.CanvasPosition.Y):toBe(305)
				stopList()
				runtime:dispose()
			end,
		})
		it("resets a list at the top through a permutation and later reflows", {
			id = "native_collections::Table sort scrolling::resets a list at the top through a permutation and later reflows",
			run = function()
				local engine, runtime, UI, target = setup()
				local rows = records(20)
				local source = Compose.cell(rows)
				local reset = Compose.cell("initial")
				local stop, mounted = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, string> = {
						from = source,
						key = "id",
						itemSize = 20,
						scrollReset = reset,
						render = function(): GuiObject
							return UI.Button { label = "Row" }
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				local list = (mounted :: unknown) :: ScrollingFrame
				local geometry = (list :: unknown) :: { AbsoluteWindowSize: Vector2 }
				engine.environment.poke(
					VerifyRoblox.assertInstance(geometry),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 95)
				)
				local reversed = table.clone(rows)
				table.sort(reversed, function(a: Record, b: Record): boolean
					return a.id > b.id
				end)
				runtime:batch(function()
					source:set(reversed)
					reset:set("reversed")
				end)
				expect(list.CanvasPosition.Y):toBe(0)
				for _, height in { 96, 95 } do
					engine.environment.poke(
						VerifyRoblox.assertInstance(geometry),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(200, height)
					)
					expect(list.CanvasPosition.Y):toBe(0)
					expect(assert(list:FindFirstChild("Items")):FindFirstChild("20") ~= nil):toBe(true)
				end
				stop()
				runtime:dispose()
			end,
		})
	end)
	describe("collection geometry publication", function()
		it("does not correct a native end scroll into the reserved Card lift gutter", {
			id = "native_collections::collection geometry publication::does not correct a native end scroll into the reserved Card lift gutter",
			run = function()
				local engine, runtime, UI, target = setup()
				local Host = (
					runtime.constructors :: unknown
				) :: typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
				local status = Compose.cell(nil :: FixtureComposeTypes.OrderedCollectionStatus?)
				local corrections = 0
				local checking = false
				local stop, mounted = runtime.mount(function()
					Compose.watch(function(use)
						local current = use(status)
						if checking and current and current.desiredOffset ~= nil then
							corrections += 1
						end
					end)
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, string> = {
						from = records(60),
						key = "id",
						columns = 4,
						itemSize = 268,
						gap = 16,
						status = status,
						render = function(): GuiObject
							return Host.Frame {
								Name = "Card",
								Size = engine.types.UDim2.fromScale(1, 1),
								Attributes = { FacetBody = "button" },
							}
						end,
					}
					return UI.VirtualGrid(listSpec)
				end, target)
				local grid = (mounted :: unknown) :: ScrollingFrame
				local geometry = (grid :: unknown) :: { AbsoluteWindowSize: Vector2 }
				engine.environment.poke(
					VerifyRoblox.assertInstance(geometry),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(1242, 648)
				)
				checking = true
				grid.CanvasPosition = engine.types.Vector2.new(0, grid.CanvasSize.Y.Offset - 648)
				expect(corrections):toBe(0)
				stop()
			end,
		})
		it("settles derived glyph and form geometry without property notifications", {
			id = "native_collections::collection geometry publication::settles derived glyph and form geometry without property notifications",
			run = function()
				local engine, runtime, _, target = setup()
				local node = engine.new("TextLabel")
				local V2 = engine.types.Vector2
				local derived = { TextBounds = V2.new(97, 12), AbsoluteSize = V2.new(43, 20) }
				local observation = assert(runtime.host.observation)
				local readProperty = observation.readProperty
				observation.readProperty = function(instance, property)
					if instance == node and derived[property] then
						return derived[property]
					end
					return readProperty(instance, property)
				end

				local settled: FixtureComposeTypes.ReadOnlyValue<boolean>? = nil
				local glyphs: FixtureComposeTypes.ReadOnlyValue<unknown>? = nil
				local box: FixtureComposeTypes.ReadOnlyValue<unknown>? = nil
				local stop = runtime.mountFragment(function()
					glyphs = runtime.observe(node, "TextBounds")
					box = runtime.observe(node, "AbsoluteSize")
					settled = runtime.settled {
						sample = function(): string
							return `{observation.readProperty(node, "TextBounds")}:{observation.readProperty(
								node,
								"AbsoluteSize"
							)}`
						end,
					}
					return {}
				end, target)
				engine.heartbeat:Fire(0)
				derived.TextBounds = V2.new(87, 12)
				derived.AbsoluteSize = V2.new(40, 20)
				engine.heartbeat:Fire(0)
				expect(assert(settled):peek()):toBe(false)
				engine.heartbeat:Fire(0)
				expect(assert(settled):peek()):toBe(true)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "TextBounds", derived.TextBounds)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", derived.AbsoluteSize)
				expect(assert(glyphs):peek()):toBe(V2.new(87, 12))
				expect(assert(box):peek()):toBe(V2.new(40, 20))
				stop()
			end,
		})
		it("publishes the complete native geometry snapshot before paint", {
			id = "native_collections::collection geometry publication::publishes the complete native geometry snapshot before paint",
			run = function()
				local engine, runtime, _, target = setup()
				local node = engine.new("Frame")
				local V2 = engine.types.Vector2
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.new(390, 200))
				node.Parent = target

				local beforePaint = engine.heartbeat
				local size: FixtureComposeTypes.ReadOnlyValue<unknown>? = nil
				local stop = runtime.mountFragment(function()
					size = runtime.observe(node, "AbsoluteSize")
					return {}
				end, target)
				local observed = assert(size)
				expect(observed:peek()):toBe(V2.new(390, 200))
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.new(320, 160))
				expect(observed:peek()):toBe(V2.new(320, 160))
				beforePaint:Fire(0)
				expect(observed:peek()):toBe(V2.new(320, 160))
				stop()
			end,
		})
	end)
	describe("collection viewport coherence", function()
		it("selected tabs reveal native content before the next frame", function(_own, t)
			local engine, runtime, UI, target, _, ctx = setup()
			local V2 = engine.types.Vector2
			local stale = Compose.cell(V2.zero)
			ctx.observe.AbsoluteContentSize = function()
				return stale
			end
			local selected = Compose.cell("b")
			local tabs: { FixtureNavigationTypes.Tab } = {
				{
					id = "a",
					label = "One",
					content = function(): Instance
						return UI.Button { label = "One" }
					end,
				},
				{
					id = "b",
					label = "Two",
					content = function(): Instance
						return UI.Button { label = "Two" }
					end,
				},
			}
			local stop, root = runtime.mount(function()
				return UI.TabView {
					selection = selected,
					placement = "topBar",
					tabs = tabs,
				}
			end, target)
			local bar = assert((root :: Frame):FindFirstChild("Tabs", true)) :: ScrollingFrame
			local strip = assert(bar:FindFirstChild("Strip"))
			local button = assert(strip:FindFirstChild("b")) :: TextButton
			local layout = assert(strip:FindFirstChildWhichIsA("UIListLayout"))
			local scroll = bar:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
				engine.environment.poke(
					VerifyRoblox.assertInstance(button),
					"AbsolutePosition",
					V2.new(160 - bar.CanvasPosition.X, 0)
				)
			end)
			engine.environment.poke(VerifyRoblox.assertInstance(bar), "AbsoluteSize", V2.new(100, 44))
			engine.environment.poke(VerifyRoblox.assertInstance(button), "AbsoluteSize", V2.new(80, 44))
			engine.environment.poke(VerifyRoblox.assertInstance(button), "AbsolutePosition", V2.new(160, 0))
			engine.environment.poke(VerifyRoblox.assertInstance(layout), "AbsoluteContentSize", V2.new(240, 44))
			expect(bar.CanvasPosition.X):toBe(140)
			expect(selected:peek()):toBe("b")
			scroll:Disconnect()
			stop()
			runtime:dispose()
			expect(engine.census().connections):toBe(0)
		end)

		it("row widths follow the native scrolling window before the next frame", function(_own, t)
			local engine, runtime, UI, target, _, ctx = setup()
			local V2 = engine.types.Vector2
			local stale = Compose.cell(V2.new(200, 100))
			ctx.observe.AbsoluteWindowSize = function(_node: Instance)
				return stale
			end
			local list: ScrollingFrame? = nil
			local stop = runtime.mount(function()
				local listSpec: FixtureCollectionProps.KeyedCollectionSpec<{ id: string, label: string }, string> = {
					from = { { id = "one", label = "One" } },
					key = "id",
					itemSize = 44,
					render = function(): GuiObject
						return UI.Button { label = "One" }
					end,
				}
				list = UI.VirtualList(listSpec)
				return list
			end, target)
			local node = assert(list)
			engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(200, 100))
			stale:set(V2.new(200, 120))
			local row = assert(assert(node:FindFirstChild("Items")):FindFirstChild("one")) :: Frame
			expect(row.Size.X.Offset):toBe(200)
			engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(194, 100))
			expect(row.Size.X.Offset):toBe(194)
			engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(200, 100))
			expect(row.Size.X.Offset):toBe(200)
			stop()
			runtime:dispose()
			expect(engine.census().connections):toBe(0)
		end)

		it("keeps end-follow when native clamping precedes the size observation", {
			id = "native_collections::collection viewport coherence::keeps end-follow when native clamping precedes the size observation",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup()
				local V2 = engine.types.Vector2
				local observedSize = Compose.cell(V2.zero)
				ctx.observe.AbsoluteWindowSize = function(_node: Instance)
					return observedSize
				end
				local status = Compose.cell<<Compose.OrderedCollectionStatus>> {
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
				}
				local list: ScrollingFrame? = nil
				local function Conversation(): ScrollingFrame
					local spec: Facet.KeyedCollectionSpec<Record, number> = {
						from = records(10),
						key = "id",
						itemSize = 50,
						follow = "end",
						status = status,
						render = function(current): GuiObject
							return UI.Button { label = current:peek().label }
						end,
					}
					local node = UI.VirtualList(spec)
					list = node
					return node
				end
				local stop = runtime.mount(Conversation, target)
				local node = assert(list)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(200, 600))
				observedSize:set(V2.new(200, 600))
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(200, 60))
				observedSize:set(V2.new(200, 60))
				expect(node.CanvasPosition.Y):toBe(440)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(200, 380))
				node.CanvasPosition = V2.new(0, 120)
				expect(status:peek().following):toBe(true)
				observedSize:set(V2.new(200, 380))
				expect(status:peek().following):toBe(true)
				expect(node.CanvasPosition.Y):toBe(120)
				node.CanvasPosition = V2.new(0, 20)
				expect(status:peek().following):toBe(false)
				stop()
				runtime:dispose()
			end,
		})
	end)
	describe("collection prepared paint", function()
		it("waits for a text row's own measurement before paint", {
			id = "native_collections::collection prepared paint::waits for a text row's own measurement before paint",
			run = function()
				local engine, runtime, _, target, _, ctx = setup()
				local node = engine.new("TextLabel")
				node.Text = "Pending text row"
				node.Parent = target
				local label = VerifyRoblox.assertInstance(node)
				engine.environment.poke(label, "AbsoluteSize", engine.types.Vector2.new(240, 44))
				engine.environment.poke(label, "TextBounds", engine.types.Vector2.new(180, 20))
				local release = require("../src/ui/text_measure").hold(node)
				local ready: FixtureComposeTypes.ReadOnlyValue<boolean>? = nil
				local stop = runtime.mountFragment(function()
					ready = require("../src/ui/collection_paint")(ctx, node)
					return {}
				end, target)
				expect(assert(ready):peek()):toBe(false)
				release()
				engine.heartbeat:Fire(0)
				expect(assert(ready):peek()):toBe(true)
				stop()
				node:Destroy()
			end,
		})
		it("waits for row bounds before observing descendant readiness", {
			id = "native_collections::collection prepared paint::waits for row bounds before observing descendant readiness",
			run = function()
				local engine, runtime, _, target, _, ctx = setup()
				local V2 = engine.types.Vector2
				local node = engine.new("Frame")
				local text = engine.new("TextLabel")
				text.Text = "Ready later"
				text.Parent = node
				node.Parent = target
				local frame = VerifyRoblox.assertInstance(node)
				local label = VerifyRoblox.assertInstance(text)
				engine.environment.poke(frame, "AbsoluteSize", V2.zero)
				engine.environment.poke(label, "AbsoluteSize", V2.zero)
				engine.environment.poke(label, "TextBounds", V2.zero)
				local ready: FixtureComposeTypes.ReadOnlyValue<boolean>? = nil
				local stop = runtime.mountFragment(function()
					ready = require("../src/ui/collection_paint")(ctx, node)
					return {}
				end, target)
				expect(assert(ready):peek()):toBe(false)
				expect(engine.environment.connectionsOfInstance(label)):toBe(0)
				engine.environment.poke(frame, "AbsoluteSize", V2.new(240, 44))
				expect(assert(ready):peek()):toBe(false)
				engine.environment.poke(label, "AbsoluteSize", V2.new(200, 24))
				engine.environment.poke(label, "TextBounds", V2.new(100, 20))
				expect(assert(ready):peek()):toBe(true)
				expect(engine.environment.connectionsOfInstance(label)):toBe(0)
				engine.environment.poke(frame, "AbsoluteSize", V2.zero)
				expect(assert(ready):peek()):toBe(false)
				expect(engine.environment.connectionsOfInstance(label)):toBe(0)
				engine.environment.poke(frame, "AbsoluteSize", V2.new(240, 44))
				expect(assert(ready):peek()):toBe(true)
				stop()
				expect(engine.environment.connectionsOfInstance(frame)):toBe(0)
				node:Destroy()
			end,
		})
		it("the first paint of an unprepared measured cell uses its completed extent", {
			id = "native_collections::collection prepared paint::the first paint of an unprepared measured cell uses its completed extent",
			run = function()
				local engine, runtime, _, target, _, ctx = setup()
				local V2 = engine.types.Vector2
				local node = engine.new("Frame")
				local text = engine.new("TextLabel")
				text.Text = "Measured caption"
				engine.environment.poke(VerifyRoblox.assertInstance(text), "AbsoluteSize", V2.new(200, 24))
				engine.environment.poke(VerifyRoblox.assertInstance(text), "TextBounds", V2.new(180, 20))
				text.Parent = node
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.zero)
				node.Parent = target
				local ready: FixtureComposeTypes.ReadOnlyValue<boolean>? = nil
				local stop = runtime.mountFragment(function()
					ready = require("../src/ui/collection_paint")(ctx, node, nil, true)
					return {}
				end, target)
				local painted: { number } = {}
				local function frame()
					engine.heartbeat:Fire(0)
					if assert(ready):peek() then
						table.insert(painted, node.AbsoluteSize.Y)
					end
				end
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.new(240, 40))
				frame()
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.new(240, 44))
				for _ = 1, 4 do
					frame()
				end
				expect(#painted > 0):toBe(true)
				for _, height in painted do
					expect(height):toBe(44)
				end
				stop()
			end,
		})
		it("prepares measured content while its scroll position keeps changing", {
			id = "native_collections::collection prepared paint::prepares measured content while its scroll position keeps changing",
			run = function()
				local engine, runtime, _, target, _, ctx = setup()
				local V2 = engine.types.Vector2
				local node = engine.new("Frame")
				local text = engine.new("TextLabel")
				text.Text = "Measured caption"
				engine.environment.poke(VerifyRoblox.assertInstance(text), "AbsoluteSize", V2.new(200, 24))
				engine.environment.poke(VerifyRoblox.assertInstance(text), "TextBounds", V2.new(180, 20))
				text.Parent = node
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.zero)
				node.Parent = target
				local ready: FixtureComposeTypes.ReadOnlyValue<boolean>? = nil
				local stop = runtime.mountFragment(function()
					ready = require("../src/ui/collection_paint")(ctx, node, nil, true)
					return {}
				end, target)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.new(240, 44))
				for index = 1, 4 do
					engine.environment.poke(
						VerifyRoblox.assertInstance(node),
						"AbsolutePosition",
						V2.new(0, -index * 20)
					)
					engine.heartbeat:Fire(0)
				end
				expect(assert(ready):peek()):toBe(true)
				stop()
			end,
		})
		it("keeps already measured cells immediate when layout preparation is requested", {
			id = "native_collections::collection prepared paint::keeps already measured cells immediate when layout preparation is requested",
			run = function()
				local engine, runtime, _, target, _, ctx = setup()
				local node = engine.new("Frame")
				local text = engine.new("TextLabel")
				text.Text = "Measured caption"
				text.TextWrapped = true
				text.AutomaticSize = engine.types.Enum.AutomaticSize.Y
				engine.environment.poke(VerifyRoblox.assertInstance(text), "TextFits", false)
				engine.environment.poke(
					VerifyRoblox.assertInstance(text),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 24)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(text),
					"TextBounds",
					engine.types.Vector2.new(180, 20)
				)
				text.Parent = node
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteSize",
					engine.types.Vector2.new(240, 44)
				)
				node.Parent = target
				local ready: FixtureComposeTypes.ReadOnlyValue<boolean>? = nil
				local stop = runtime.mountFragment(function()
					ready = require("../src/ui/collection_paint")(ctx, node, nil, true)
					return {}
				end, target)
				expect(assert(ready):peek()):toBe(true)
				stop()
			end,
		})
		it("keeps a cell hidden while its text measurement is pending", {
			id = "native_collections::collection prepared paint::keeps a cell hidden while its text measurement is pending",
			run = function()
				local engine, runtime, _, target, _, ctx = setup()
				local node = engine.new("Frame")
				local text = engine.new("TextLabel")
				text.Text = "Measured caption"
				engine.environment.poke(
					VerifyRoblox.assertInstance(text),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 24)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(text),
					"TextBounds",
					engine.types.Vector2.new(180, 20)
				)
				text.Parent = node
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteSize",
					engine.types.Vector2.new(240, 44)
				)
				node.Parent = target
				local release = require("../src/ui/text_measure").hold(text)
				local ready: FixtureComposeTypes.ReadOnlyValue<boolean>? = nil
				local stop = runtime.mountFragment(function()
					ready = require("../src/ui/collection_paint")(ctx, node)
					return {}
				end, target)
				expect(assert(ready):peek()):toBe(false)
				release()
				engine.heartbeat:Fire(0)
				expect(assert(ready):peek()):toBe(true)
				stop()
			end,
		})
		it("paints an already measured cell without waiting for another render callback", {
			id = "native_collections::collection prepared paint::paints an already measured cell without waiting for another render callback",
			run = function()
				local engine, runtime, _, target, _, ctx = setup()
				local node = engine.new("Frame")
				local text = engine.new("TextLabel")
				text.Text = "Measured caption"
				engine.environment.poke(
					VerifyRoblox.assertInstance(text),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 24)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(text),
					"TextBounds",
					engine.types.Vector2.new(180, 20)
				)
				text.Parent = node
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteSize",
					engine.types.Vector2.new(240, 44)
				)
				node.Parent = target
				local ready: FixtureComposeTypes.ReadOnlyValue<boolean>? = nil
				local stop = runtime.mountFragment(function()
					ready = require("../src/ui/collection_paint")(ctx, node)
					return {}
				end, target)
				expect(assert(ready):peek()):toBe(true)
				stop()
			end,
		})
	end)
	describe("Table first column layout", function()
		it("checks first row layout before a deferred root-size observation publishes", {
			id = "native_collections::Table first column layout::checks first row layout before a deferred root-size observation publishes",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local ctx = context(Compose, runtime, { types = engine.types })
				local Host = Facet.host(runtime)
				local stale = Compose.cell(engine.types.Vector2.zero)
				ctx.observe.AbsoluteSize = function(_node: Instance)
					return stale
				end
				local root: Frame? = nil
				local ready: FixtureComposeTypes.ReadOnlyValue<boolean>? = nil
				local stop = runtime.mount(function()
					local frame = Host.Frame { Host.TextLabel "Name" { Text = "Material" } }
					root = frame
					ready = require("../src/ui/collection_paint")(ctx, frame)
					return frame
				end, engine.new("ScreenGui"))
				local node = assert(root)
				expect(assert(ready):peek()):toBe(false)
				local geometry = (node :: unknown) :: { AbsoluteSize: Vector2 }
				engine.environment.poke(
					VerifyRoblox.assertInstance(geometry),
					"AbsoluteSize",
					engine.types.Vector2.new(390, 44)
				)
				local text = (assert(node:FindFirstChild("Name"))) :: { AbsoluteSize: Vector2, TextBounds: Vector2 }
				engine.environment.poke(
					VerifyRoblox.assertInstance(text),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 44)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(text),
					"TextBounds",
					engine.types.Vector2.new(100, 20)
				)
				expect(assert(ready):peek()):toBe(true)
				engine.heartbeat:Fire(1 / 60)
				expect(assert(ready):peek()):toBe(true)
				expect(stale:peek()):toBe(engine.types.Vector2.zero)
				stop()
				runtime:dispose()
			end,
		})

		it("allocates every Table column before its first native viewport sample after a branch swap", {
			id = "native_collections::Table first column layout::allocates every Table column before its first native viewport sample after a branch swap",
			run = function()
				local engine, runtime, UI, target = setup()
				local container = engine.new("Frame")
				engine.environment.poke(
					VerifyRoblox.assertInstance(container),
					"AbsoluteSize",
					engine.types.Vector2.new(390, 200)
				)
				container.Parent = target
				local Host = Facet.host(runtime)
				local mode = Compose.cell("grid")
				type Row = { id: string, name: string, kind: string }
				local rows: { Row } =
					{ { id = "one", name = "One", kind = "Material" }, { id = "two", name = "Two", kind = "Image" } }
				local stop, mounted = runtime.mount(function()
					return Host.Frame {
						Compose.keyed {
							from = function(use)
								return { use(mode) }
							end,
							render = function(current): GuiObject
								if current:peek() == "table" then
									local tableSpec: FixtureCollectionProps.KeyedTableSpec<Row, string> = {
										Name = "Data",
										from = rows,
										key = "id",
										columns = {
											{ id = "name", label = "Name" },
											{ id = "kind", label = "Kind", width = 100 },
										},
									}
									return UI.Table(tableSpec)
								end
								local spec: FixtureCollectionProps.KeyedCollectionSpec<Row, string> = {
									Name = "Data",
									from = rows,
									key = "id",
									render = function(current: FixtureComposeTypes.ReadOnlyValue<Row>): GuiObject
										return Host.TextLabel { Text = current:peek().name }
									end,
								}
								return if current:peek() == "grid" then UI.VirtualGrid(spec) else UI.VirtualList(spec)
							end,
						},
					}
				end, container)
				local root = (mounted :: unknown) :: GuiObject
				for _, value in { "grid", "list", "table", "grid", "table", "list", "table" } do
					mode:set(value)
					if value ~= "table" then
						continue
					end
					local data = assert(root:FindFirstChild("Data", true))
					local items = assert(data:FindFirstChild("Items", true))
					local header = assert(data:FindFirstChild("Header", true))
					for _, row in items:GetChildren() do
						for _, id in { "name", "kind" } do
							local cell = assert(row:FindFirstChild(id, true)) :: GuiObject
							local heading = assert(header:FindFirstChild(id)) :: GuiObject
							expect(cell.Size.X.Offset > 0):toBe(true)
							expect(cell.Size.X.Offset):toBe(heading.Size.X.Offset)
						end
					end
					for _, node in data:GetDescendants() do
						if node:IsA("GuiObject") then
							local geometry = (node :: unknown) :: { AbsoluteSize: Vector2, TextBounds: Vector2 }
							engine.environment.poke(
								VerifyRoblox.assertInstance(geometry),
								"AbsoluteSize",
								engine.types.Vector2.new(math.max(1, node.Size.X.Offset), 44)
							)
							if node:IsA("TextLabel") or node:IsA("TextButton") then
								engine.environment.poke(
									VerifyRoblox.assertInstance(geometry),
									"TextBounds",
									engine.types.Vector2.new(40, 20)
								)
							end
						end
					end
					engine.heartbeat:Fire(0)
					local painted = 0
					for _, row in items:GetChildren() do
						local content = row:FindFirstChild("Content") :: CanvasGroup
						expect(content.GroupTransparency):toBe(0)
						painted += 1
					end
					expect(painted):toBe(2)
				end
				stop()
			end,
		})
	end)
	describe("collection first layout", function()
		it("reserves the native automatic button height in a list row", {
			id = "native_collections::automatic-button-extent",
			run = function()
				local engine, runtime, UI, target = setup()
				local Host = Facet.host(runtime)
				local controls: FixtureComposeTypes.OrderedCollectionControls<string> = {}
				local spec: FixtureCollectionProps.KeyedCollectionSpec<string, string> = {
					from = { "all", "motors" },
					key = function(item)
						return item
					end,
					itemSize = 48,
					mode = "all",
					controls = controls,
					render = function()
						return Host.TextButton "Category" { AutomaticSize = engine.types.Enum.AutomaticSize.XY }
					end,
				}
				local stop, node = runtime.mount(function()
					return UI.VirtualList(spec)
				end, target)
				local button = assert((node :: Instance):FindFirstChild("Category", true))
				local geometry = (button :: unknown) :: { AbsoluteSize: Vector2 }
				engine.environment.poke(
					VerifyRoblox.assertInstance(geometry),
					"AbsoluteSize",
					engine.types.Vector2.new(90, 66)
				)
				expect(assert(controls.placementOf)(2).offset):toBe(66)
				stop()
				runtime:dispose()
			end,
		})
		it("grows automatic list layouts past the estimate without shrinking fixed rows", {
			id = "native_collections::automatic-row-extent",
			run = function()
				for _, measure in { "default", "fixed" } do
					local engine, runtime, UI, target = setup()
					local Host = Facet.host(runtime)
					local controls: FixtureComposeTypes.OrderedCollectionControls<string> = {}
					local spec: FixtureCollectionProps.KeyedCollectionSpec<string, string> = {
						from = { "one", "two" },
						key = function(item)
							return item
						end,
						itemSize = 64,
						mode = "all",
						controls = controls,
						measure = if measure == "fixed" then false else nil,
						render = function()
							return Host.Frame "Row" {
								Size = engine.types.UDim2.new(1, 0, 0, 0),
								AutomaticSize = engine.types.Enum.AutomaticSize.Y,
								Host.UIListLayout {},
							}
						end,
					}
					local stop, node = runtime.mount(function()
						return UI.VirtualList(spec)
					end, target)
					local row = assert((node :: Instance):FindFirstChild("Row", true)) :: GuiObject
					local geometry = (row :: unknown) :: { AbsoluteSize: Vector2 }
					engine.environment.poke(
						VerifyRoblox.assertInstance(geometry),
						"AbsoluteSize",
						engine.types.Vector2.new(300, 140)
					)
					expect(assert(controls.placementOf)(2).offset):toBe(if measure == "fixed" then 64 else 140)
					engine.environment.poke(
						VerifyRoblox.assertInstance(geometry),
						"AbsoluteSize",
						engine.types.Vector2.new(300, 32)
					)
					expect(assert(controls.placementOf)(2).offset):toBe(64)
					stop()
					runtime:dispose()
				end
			end,
		})
		it("paints complete rows on the first layout of an ordinary grid list table branch", {
			id = "native_collections::collection first layout::paints complete rows on the first layout of an ordinary grid list table branch",
			run = function()
				local engine, runtime, UI, target = setup()
				local V2 = engine.types.Vector2
				local container = engine.new("Frame")
				engine.environment.poke(VerifyRoblox.assertInstance(container), "AbsoluteSize", V2.new(390, 200))
				container.Parent = target
				local Host = Facet.host(runtime)
				local mode = Compose.cell("grid")
				local rows = { { id = "one", label = "One" }, { id = "two", label = "Two" } }
				local function text(
					current: FixtureComposeTypes.ReadOnlyValue<{ id: string, label: string }>
				): GuiObject
					return Host.TextLabel "Name" { Text = current:peek().label } :: GuiObject
				end
				local stop, mountedRoot = runtime.mount(function()
					local contents: FixtureEngineTypes.FrameNativeProps = {
						UI.Picker "Selector" {
							selected = mode,
							style = "segmented" :: "segmented",
							options = {
								{ value = "grid", label = "Grid" },
								{ value = "list", label = "List" },
								{ value = "table", label = "Table" },
							},
						},
						Compose.keyed {
							from = function(use)
								return { use(mode) }
							end,
							render = function(current: Compose.ReadOnlyValue<string>): GuiObject
								if current:peek() == "table" then
									local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: string, label: string }, string> =
										{
											Name = "Data",
											from = rows,
											key = "id",
											itemSize = 44,
											columns = {
												{ id = "name", label = "Name", width = 180, render = text },
												{
													id = "kind",
													label = "Kind",
													width = 100,
													render = function(
														_current: FixtureComposeTypes.ReadOnlyValue<{ id: string, label: string }>
													): GuiObject
														return Host.TextLabel "Kind" { Text = "Material" }
													end,
												},
											},
										}
									return UI.Table(tableSpec)
								end
								local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: string, label: string }, string> =
									{
										Name = "Data",
										from = rows,
										key = "id",
										itemSize = 44,
										columns = 2,
										render = text,
									}
								return if current:peek() == "grid" then UI.VirtualGrid(props) else UI.VirtualList(props)
							end,
						},
					}
					return Host.Frame(contents)
				end, container)
				local root = (mountedRoot :: unknown) :: Frame
				local function layout()
					local data = assert(root:FindFirstChild("Data", true))
					for _ = 1, 2 do
						local nodes = data:GetDescendants()
						table.insert(nodes, data)
						for _, node in nodes do
							if node:IsA("GuiObject") then
								engine.environment.poke(
									VerifyRoblox.assertInstance(node),
									"AbsoluteSize",
									engine.types.Vector2.new(390, 200)
								)
								if node:IsA("ScrollingFrame") then
									engine.environment.poke(
										VerifyRoblox.assertInstance(node),
										"AbsoluteWindowSize",
										engine.types.Vector2.new(390, 200)
									)
								end
								if node:IsA("TextLabel") or node:IsA("TextButton") then
									engine.environment.poke(
										VerifyRoblox.assertInstance(node),
										"TextBounds",
										engine.types.Vector2.new(60, 20)
									)
								end
							end
						end
					end
				end
				for _, value in
					{ "grid", "list", "table", "grid", "table", "list", "grid", "list", "table", "list", "grid" }
				do
					local selector = (
						assert(assert(root:FindFirstChild("Selector", true)):FindFirstChild(value, true))
					) :: TextButton
					local activationSignal = (selector.Activated :: unknown) :: { Fire: (unknown) -> () }
					activationSignal:Fire()
					expect(mode:peek()):toBe(value)
					expect(selector:HasTag("facet-selected")):toBe(true)
					local mounted = assert(root:FindFirstChild("Data", true)):FindFirstChild("Items", true)
					expect(`{value} Items mounted {mounted ~= nil}`):toBe(`{value} Items mounted true`)
					expect(#assert(mounted):GetChildren() >= 2):toBe(true)
					layout()
					for _ = 1, 4 do
						engine.heartbeat:Fire(1 / 60)
						local painted = 0
						local data = assert(root:FindFirstChild("Data", true))
						for _, node in data:GetDescendants() do
							if
								node:IsA("CanvasGroup")
								and node:GetAttribute("FacetCollectionRow")
								and node.GroupTransparency == 0
							then
								local name = (assert(node:FindFirstChild("Name", true)) :: unknown) :: TextLabel
								expect(name.AbsoluteSize.X > 0 and name.TextBounds.X > 0):toBe(true)
								if value == "table" then
									local kind = (assert(node:FindFirstChild("Kind", true)) :: unknown) :: TextLabel
									expect(kind.AbsoluteSize.X > 0 and kind.TextBounds.X > 0):toBe(true)
									expect(data:FindFirstChild("Header", true) ~= nil):toBe(true)
								end
								painted += 1
							end
						end
						expect(`{value} painted rows {painted}`):toBe(`{value} painted rows 2`)
					end
				end
				stop()
				runtime:dispose()
			end,
		})
	end)
	describe("collection data presentation", function()
		it("paints filtered roots at full extent without an expansion entrance", {
			id = "native_collections::collection data presentation::paints filtered roots at full extent without an expansion entrance",
			run = function()
				type Row = { id: string, label: string }
				for _, kind in { "Outline", "Table" } do
					local engine, runtime, UI, target = setup({ motionLevel = "normal" })
					local Host = Facet.host(runtime)
					local children: { Row } = { { id = "two", label = "Two" }, { id = "three", label = "Three" } }
					local rows = Compose.cell({ { id = "folder", label = "Folder" } } :: { Row })
					local status = Compose.cell({} :: FixtureComposeTypes.OrderedCollectionStatus)
					local controls: FixtureComposeTypes.OrderedCollectionControls<string> = {}
					local stop = runtime.mount(function(): GuiObject
						local spec: FixtureCollectionProps.KeyedOutlineSpec<Row, string> = {
							from = rows,
							key = function(item: Row): string
								return item.id
							end,
							mode = "all" :: "all",
							itemSize = 44,
							status = status,
							controls = controls,
							children = function(item: Row): { Row }?
								return if item.id == "folder" then children else nil
							end,
							render = function(current: FixtureComposeTypes.ReadOnlyValue<Row>): GuiObject
								return (Host.TextLabel { Text = current:peek().label } :: unknown) :: TextLabel
							end,
						}
						if kind == "Outline" then
							return UI.Outline(spec)
						end
						local tableSpec: FixtureCollectionProps.KeyedTableSpec<Row, string> = {
							from = rows,
							key = function(item: Row): string
								return item.id
							end,
							mode = "all" :: "all",
							itemSize = 44,
							status = status,
							controls = controls,
							children = spec.children,
							columns = {
								{
									id = "label",
									label = "Name",
									value = function(item: Row): string
										return item.label
									end,
								},
							},
						}
						return UI.Table(tableSpec)
					end, target)
					expect(status:peek().retained):toBe(1)
					for _, nextRows in { children, { children[2], children[1] }, { { id = "new", label = "New" } } } do
						rows:set(nextRows)
						expect(status:peek().retained):toBe(#nextRows)
						for index = 1, #nextRows do
							expect(assert(controls.placementOf)(index).size):toBe(44)
						end
						engine.heartbeat:Fire(1 / 60)
						expect(status:peek().retained):toBe(#nextRows)
					end
					stop()
					runtime:dispose()
				end
			end,
		})
	end)
	describe("collection retirement", function()
		it("removes a painted deleted row when surviving rows need no replacement paint", {
			id = "native_collections::collection retirement::removes a painted deleted row when surviving rows need no replacement paint",
			run = function()
				type Row = { id: string, title: string }
				for _, kind in { "list", "grid", "table" } do
					local engine, runtime, UI, target = setup()
					local Host = Facet.host(runtime)
					local first: Row = { id = "A", title = "Alpha" }
					local second: Row = { id = "B", title = "Beta" }
					local rows = Compose.cell({ first, second })
					local stop, mountedRoot = runtime.mount(function(): GuiObject
						local spec: FixtureCollectionProps.KeyedCollectionSpec<Row, string> = {
							from = rows,
							key = "id",
							mode = "all" :: "all",
							itemSize = 44,
							render = function(current: FixtureComposeTypes.ReadOnlyValue<Row>): GuiObject
								return Host.TextLabel "Caption" { Text = current:peek().title }
							end,
						}
						if kind == "table" then
							local tableSpec: FixtureCollectionProps.KeyedTableSpec<Row, string> = {
								from = rows,
								key = "id",
								mode = "all" :: "all",
								columns = { { id = "name", label = "Name", render = spec.render } },
							}
							return UI.Table(tableSpec)
						end
						return if kind == "grid" then UI.VirtualGrid(spec) else UI.VirtualList(spec)
					end, target)
					local root = (mountedRoot :: unknown) :: GuiObject
					local V2 = engine.types.Vector2
					for _, node in root:GetDescendants() do
						if node:IsA("GuiObject") then
							local geometry = (node :: unknown) :: { AbsoluteSize: Vector2, TextBounds: Vector2 }
							engine.environment.poke(
								VerifyRoblox.assertInstance(geometry),
								"AbsoluteSize",
								V2.new(100, 44)
							)
							if node:IsA("TextLabel") then
								engine.environment.poke(
									VerifyRoblox.assertInstance(geometry),
									"TextBounds",
									V2.new(60, 20)
								)
							end
						end
					end
					for _ = 1, 4 do
						engine.heartbeat:Fire(1 / 60)
					end
					local items = assert(root:FindFirstChild("Items", true))
					local kept = assert(items:FindFirstChild("B"))
					expect(items:FindFirstChild("A") ~= nil):toBe(true)
					expect((assert(kept:FindFirstChild("Content")) :: CanvasGroup).GroupTransparency):toBe(0)
					rows:set({ second })
					for frame = 0, 12 do
						expect(`{kind} frame {frame} deleted A {items:FindFirstChild("A") ~= nil}`):toBe(
							`{kind} frame {frame} deleted A false`
						)
						expect(items:FindFirstChild("B")):toBe(kept)
						expect((assert(kept:FindFirstChild("Content")) :: CanvasGroup).GroupTransparency):toBe(0)
						engine.heartbeat:Fire(1 / 60)
					end
					stop()
					runtime:dispose()
				end
			end,
		})
	end)
	describe("collection retired content", function()
		it("rebinds a replaced row in place and keeps it reactive", {
			id = "native_collections::collection retired content::rebinds a replaced row in place and keeps it reactive",
			run = function()
				type Row = { id: string, title: string }
				for _, kind in { "list", "grid" } do
					local engine, runtime, UI, target = setup()
					local Host = Facet.host(runtime)
					local rows =
						Compose.cell({ { id = "A", title = "Alpha" }, { id = "B", title = "Beta" } } :: { Row })
					local revision = Compose.cell(1)
					local stop, mountedRoot = runtime.mount(function(): GuiObject
						local spec: FixtureCollectionProps.KeyedCollectionSpec<Row, string> = {
							from = rows,
							key = "id",
							mode = "all" :: "all",
							itemSize = 44,
							render = function(current: FixtureComposeTypes.ReadOnlyValue<Row>): GuiObject
								return Host.TextLabel "Caption" {
									Text = function(use: FixtureComposeTypes.Use): string
										return `{use(current).title} {use(revision)}`
									end,
								}
							end,
						}
						return if kind == "grid" then UI.VirtualGrid(spec) else UI.VirtualList(spec)
					end, target)
					local root = (mountedRoot :: unknown) :: GuiObject
					local V2 = engine.types.Vector2
					local function size()
						for _, node in root:GetDescendants() do
							if node:IsA("GuiObject") then
								local geometry = (node :: unknown) :: { AbsoluteSize: Vector2, TextBounds: Vector2 }
								engine.environment.poke(
									VerifyRoblox.assertInstance(geometry),
									"AbsoluteSize",
									V2.new(100, 44)
								)
								if node:IsA("TextLabel") then
									engine.environment.poke(
										VerifyRoblox.assertInstance(geometry),
										"TextBounds",
										V2.new(60, 20)
									)
								end
							end
						end
					end
					size()
					for _ = 1, 4 do
						engine.heartbeat:Fire(1 / 60)
					end
					local items = assert(root:FindFirstChild("Items", true))
					local slot = assert(items:FindFirstChild("A"))
					local caption = assert(slot:FindFirstChild("Caption", true)) :: TextLabel
					rows:set({ { id = "C", title = "Gamma" }, { id = "D", title = "Delta" } })
					revision:set(2)
					expect(caption.Text):toBe("Gamma 2")
					expect(slot.Name):toBe("C")
					for _ = 1, 12 do
						size()
						engine.heartbeat:Fire(1 / 60)
					end
					expect(items:FindFirstChild("A")):toBeNil()
					expect(items:FindFirstChild("C") ~= nil):toBe(true)
					stop()
					runtime:dispose()
				end
			end,
		})
	end)
	describe("collection cell paint readiness", function()
		for _, kind in { "list", "grid", "table" } do
			it(`keeps painted {kind} rows through filter Clear and late text`, {
				id = `native_collections::collection cell paint readiness::keeps painted {kind} rows through filter Clear and late text`,
				run = function()
					local engine, runtime, UI, target = setup()
					local Host = Facet.host(runtime)
					type Row = { id: string, title: string }
					local rows = Compose.cell({ { id = "old", title = "Old" } } :: { Row })
					local stop, root: any = runtime.mount(function()
						local props: FixtureCollectionProps.KeyedCollectionSpec<Row, string> = {
							from = rows,
							key = "id",
							mode = "all" :: "all",
							render = function(current: FixtureComposeTypes.ReadOnlyValue<Row>)
								return Host.TextLabel "Caption" {
									Text = function(use)
										return use(current).title
									end,
								} :: GuiObject
							end,
						}
						if kind == "table" then
							local tableSpec: FixtureCollectionProps.KeyedTableSpec<Row, string> = {
								from = rows,
								key = "id",
								mode = "all" :: "all",
								columns = { { id = "file", label = "File", render = props.render } },
							}
							return UI.Table(tableSpec)
						end
						return if kind == "grid" then UI.VirtualGrid(props) else UI.VirtualList(props)
					end, target)
					local V2 = engine.types.Vector2
					local function layout(late: boolean)
						engine.environment.poke(VerifyRoblox.assertInstance(root), "AbsoluteSize", V2.new(390, 500))
						if root:IsA("ScrollingFrame") then
							engine.environment.poke(
								VerifyRoblox.assertInstance(root),
								"AbsoluteWindowSize",
								V2.new(390, 500)
							)
						end
						for _, node in root:GetDescendants() do
							if node:IsA("GuiObject") then
								local row = node.Parent
								while row and not row:GetAttribute("FacetCollectionRow") do
									row = row.Parent
								end
								engine.environment.poke(
									VerifyRoblox.assertInstance(node),
									"AbsoluteSize",
									if late
											and node.Name == "Caption"
											and row ~= nil
											and row.Parent.Name == rows:peek()[1].id
										then V2.new(0, 44)
										else V2.new(100, 44)
								)
								if node:IsA("TextLabel") then
									engine.environment.poke(
										VerifyRoblox.assertInstance(node),
										"TextBounds",
										V2.new(60, 20)
									)
								end
							end
						end
					end
					local function painted(): number
						local count = 0
						for _, node in root:GetDescendants() do
							if node:GetAttribute("FacetCollectionRow") then
								local visible = not node:IsA("CanvasGroup") or node.GroupTransparency == 0
								if visible then
									local label = node:FindFirstChild("Caption", true)
									expect(`{label.Text} width {label.AbsoluteSize.X} bounds {label.TextBounds.X}`):toBe(
										`{label.Text} width 100 bounds 60`
									)
									count += 1
								end
							end
						end
						return count
					end
					layout(false)
					for _ = 1, 4 do
						engine.heartbeat:Fire(1 / 60)
					end
					expect(`painted {rows:peek()[1].id}: {painted()}`):toBe(`painted {rows:peek()[1].id}: 1`)
					for _, data in { { { id = "new", title = "New" } }, { { id = "old", title = "Old" } } } do
						rows:set(data)
						layout(true)
						for _ = 1, 4 do
							engine.heartbeat:Fire(1 / 60)
							for _, label in root:GetDescendants() do
								if label.Name == "Caption" then
									expect((label :: TextLabel).Text):toBe(data[1].title)
								end
							end
						end
						layout(false)
						for _ = 1, 4 do
							engine.heartbeat:Fire(1 / 60)
							expect(`painted {rows:peek()[1].id}: {painted()}`):toBe(`painted {rows:peek()[1].id}: 1`)
						end
					end
					rows:set({})
					engine.heartbeat:Fire(1 / 60)
					expect(painted()):toBe(0)
					stop()
					expect(#target:GetChildren()):toBe(0)
					runtime:dispose()
				end,
			})
		end
	end)

	describe("collection content boundary", function()
		it("keeps a visible Close command in a desktop row menu without changing row data", {
			id = "native_collections::collection content boundary::keeps a visible Close command in a desktop row menu without changing row data",
			run = function()
				local engine, runtime, UI, target = setup({ motionLevel = "none" })
				local Host = Facet.host(runtime)
				local actions = 0
				local stop, node: any = runtime.mount(function()
					local spec: FixtureCollectionProps.RowActionsSpec = {
						content = Host.Frame {} :: GuiObject,
						trailing = {
							{
								id = "Delete",
								label = "Delete",
								onActivate = function()
									actions += 1
								end,
							},
						},
					}
					return UI.RowActions(spec)
				end, target)
				node:FindFirstChild("SwipeGrip", true).TouchLongPress:Fire({}, engine.types.Enum.UserInputState.Begin)
				local command = target:FindFirstChild("CloseCommand", true)
				expect(command ~= nil and command.Visible):toBe(true)
				expect(command:GetAttribute("label")):toBe("Close")
				command.Activated:Fire()
				expect(actions):toBe(0)
				expect(target:FindFirstChild("MenuPanel", true)):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		it("does not open a row context menu from a touch hold behind a modal", {
			id = "native_collections::collection content boundary::does not open a row context menu from a touch hold behind a modal",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup()
				local Host = Facet.host(runtime)
				local stop, node: any = runtime.mount(function()
					local spec: FixtureCollectionProps.RowActionsSpec = {
						content = Host.Frame {} :: GuiObject,
						trailing = { { id = "Delete", label = "Delete", onActivate = function() end } },
					}
					return UI.RowActions(spec)
				end, target)
				local modal = engine.new("Frame")
				modal.Parent = target
				ctx.modalScopes:set({ modal })
				node:FindFirstChild("SwipeGrip", true).TouchLongPress:Fire({}, engine.types.Enum.UserInputState.Begin)
				expect(target:FindFirstChild("MenuPanel", true)):toBeNil()
				ctx.modalScopes:set({})
				node:FindFirstChild("SwipeGrip", true).TouchLongPress:Fire({}, engine.types.Enum.UserInputState.Begin)
				expect(target:FindFirstChild("MenuPanel", true) ~= nil):toBe(true)
				stop()
				modal:Destroy()
				runtime:dispose()
			end,
		})
		it("keeps nested row controls above the swipe grip and accepts its touch context gesture", {
			id = "native_collections::collection content boundary::keeps nested row controls above the swipe grip and accepts its touch context gesture",
			run = function()
				local engine, runtime, UI, target = setup()
				local activated = 0
				local Host = Facet.host(runtime)
				local stop, node: any = runtime.mount(function()
					local spec: FixtureCollectionProps.RowActionsSpec = {
						content = Host.Frame {
							UI.Button "Details" {
								label = "Details",
								onActivate = function()
									activated += 1
								end,
							},
						} :: GuiObject,
						trailing = { { id = "Delete", label = "Delete", onActivate = function() end } },
					}
					return UI.RowActions(spec)
				end, target)
				local grip, button = node:FindFirstChild("SwipeGrip", true), node:FindFirstChild("Details", true)
				expect(grip.ZIndex):toBeLessThan(button.ZIndex)
				button.Activated:Fire()
				expect(activated):toBe(1)
				grip.TouchLongPress:Fire({}, engine.types.Enum.UserInputState.Begin)
				expect(target:FindFirstChild("MenuPanel", true) ~= nil):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		it("clips oversized rendered content only when the cell policy requests it", {
			id = "native_collections::collection content boundary::clips oversized rendered content only when the cell policy requests it",
			run = function()
				local engine, runtime, UI, root = setup()
				local choice = Compose.cell("clip" :: "clip" | "visible")
				local stop, grid: any = runtime.mount(function()
					local gridSpec: FixtureCollectionProps.KeyedCollectionSpec<number, number> = {
						from = { 1, 2 },
						key = function(item)
							return item
						end,
						columns = 2,
						itemSize = 44,
						mode = "all" :: "all",
						contentOverflow = (choice :: unknown) :: FixtureComposeTypes.ReadOnlyValue<"clip" | "visible">,
						render = function(): GuiObject
							return (
								UI.Button { label = "2W", Size = engine.types.UDim2.fromOffset(66, 66) }
							) :: GuiObject
						end,
					}
					return UI.VirtualGrid(gridSpec)
				end, root)
				local cells = 0
				for _, node in grid:GetDescendants() do
					if node:GetAttribute("FacetCollectionRow") then
						cells += 1
						expect(node.ClipsDescendants):toBe(true)
					end
				end
				expect(cells):toBe(2)
				choice:set("visible")
				for _, node in grid:GetDescendants() do
					if node:GetAttribute("FacetCollectionRow") then
						expect(node.ClipsDescendants):toBe(false)
					end
				end
				stop()
				runtime:dispose()
			end,
		})
		it("restores the grid initial offset after native canvas bounds arrive", {
			id = "native_collections::collection content boundary::restores the grid initial offset after native canvas bounds arrive",
			run = function()
				local engine, runtime, UI, root = setup()
				local V2 = engine.types.Vector2
				local stop, grid: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, string> = {
						from = records(169),
						key = "id",
						columns = 13,
						itemSize = 46,
						mode = "all" :: "all",
						CanvasPosition = V2.new(0, 200),
						render = function(): GuiObject
							return (UI.Button { label = "2W" } :: unknown) :: GuiObject
						end,
					}
					return UI.VirtualGrid(listSpec)
				end, root)
				grid.CanvasPosition = V2.zero
				engine.environment.poke(VerifyRoblox.assertInstance(grid), "AbsoluteWindowSize", V2.new(624, 205))
				engine.environment.poke(VerifyRoblox.assertInstance(grid), "AbsoluteCanvasSize", V2.new(624, 598))
				expect(grid.CanvasPosition):toBe(V2.new(0, 200))
				stop()
				runtime:dispose()
			end,
		})
	end)

	type KeyedRecord = { read id: number }
	local function key(item: KeyedRecord): number
		return item.id
	end

	local function button(UI: SharedTypes.Controls, current: Compose.ReadOnlyValue<Record>): GuiObject
		return UI.Button "Action" {
			label = function(use: Use)
				return use(current).label
			end,
		}
	end

	describe("Compose native collections", function()
		it("selects on mouse click one and activates on click two", {
			id = "native_collections::Compose native collections::selects on mouse click one and activates on click two",
			run = function()
				for _, activating in { false, true } do
					local engine, runtime, UI, target = setup()
					local selected = Compose.cell({} :: { [number]: boolean })
					local calls = 0
					local stop, node: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = records(2),
							key = key,
							columns = 2,
							itemSize = 56,
							mode = "all" :: "all",
							selection = selected,
							selectionMode = "multiple" :: "multiple",
							render = function(current)
								return button(UI, current)
							end,
							onActivate = if activating
								then function()
									calls += 1
								end
								else nil,
						}
						return UI.VirtualGrid(listSpec)
					end, target)
					local hit = node:FindFirstChild("1", true):FindFirstChild("RowHit", true)
					local input = { UserInputType = engine.types.Enum.UserInputType.MouseButton1 }
					hit.Activated:Fire(input, 1)
					expect(selected:peek()[1]):toBe(true)
					expect(calls):toBe(0)
					hit.Activated:Fire(input, 2)
					expect(selected:peek()[1]):toBe(true)
					expect(calls):toBe(if activating then 1 else 0)
					stop()
					runtime:dispose()
				end
			end,
		})
		it("honors optional tap pickup on touch-only collection sources", {
			id = "native_collections::Compose native collections::honors optional tap pickup on touch-only collection sources",
			run = function()
				for _, enabled in { false, true } do
					local engine, runtime, UI, target, _, ctx = setup({
						userInputService = {
							TouchEnabled = true,
							KeyboardEnabled = false,
							MouseEnabled = false,
							GamepadEnabled = false,
						},
					})
					local stop, node: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = records(2),
							key = key,
							mode = "all" :: "all",
							itemSize = 80,
							columns = 2,
							drag = function(items): FixtureEnvironmentTypes.DraggableSpec
								return { payload = items[1], armOnTap = enabled }
							end,
							render = function(): GuiObject
								return Facet.host(runtime).Frame({})
							end,
						}
						return UI.VirtualGrid(listSpec)
					end, target)
					local session = require("../src/ui/drag_session")(ctx)
					local tap = {
						UserInputType = engine.types.Enum.UserInputType.Touch,
						UserInputState = engine.types.Enum.UserInputState.End,
					}
					node:FindFirstChild("1", true):FindFirstChild("RowHit", true).Activated:Fire(tap, 1)
					local state = session.state:peek()
					expect(state ~= nil):toBe(enabled)
					if enabled then
						assert(state)
						expect(state.mode):toBe("armed")
						expect((state.payload :: { id: number }).id):toBe(1)
						engine.environment.poke(
							VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
							"TouchEnabled",
							false
						)
						expect(session.state:peek()):toBe(nil)
					end
					stop()
					runtime:dispose()
				end
			end,
		})
		it("paints list and grid selection on the cell owner and clears recycled state", {
			id = "native_collections::Compose native collections::paints list and grid selection on the cell owner and clears recycled state",
			run = function()
				for _, kind in { "VirtualList", "VirtualGrid" } do
					local engine, runtime, UI, target = setup()
					local selected = Compose.cell({})
					local stop, node: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = Compose.cell(records(20)),
							key = key,
							selection = selected,
							selectionMode = "multiple" :: "multiple",
							itemSize = 40,
							overscan = 0,
							render = function(): GuiObject
								return Facet.host(runtime).Frame({
									BackgroundTransparency = 1,
								})
							end,
						}
						return (if kind == "VirtualList" then UI.VirtualList else UI.VirtualGrid)(listSpec)
					end, target)
					engine.environment.poke(
						VerifyRoblox.assertInstance(node),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(200, 80)
					)
					local hit = node:FindFirstChild("1", true):FindFirstChild("RowHit", true)
					local painted = hit.Parent
					expect((painted:HasTag("facet-tablerow"))):toBe(true)
					expect(painted.BackgroundTransparency):toBe(0)
					expect(hit.BackgroundTransparency):toBe(1)
					hit.Activated:Fire()
					expect((painted:HasTag("facet-selected"))):toBe(true)
					selected:set({ [2] = true })
					expect((painted:HasTag("facet-selected"))):toBe(false)
					expect(
						(node:FindFirstChild("2", true):FindFirstChild("RowHit", true).Parent:HasTag("facet-selected"))
					):toBe(true)
					node.CanvasPosition = engine.types.Vector2.new(0, 400)
					for _, child in node:GetDescendants() do
						expect((child:HasTag("facet-selected"))):toBe(false)
					end
					stop()
					runtime:dispose()
				end
			end,
		})

		it("selects on click one and activates on click two for lists and grids", {
			id = "native_collections::Compose native collections::selects on click one and activates on click two for lists and grids",
			run = function()
				for _, kind in { "VirtualList", "VirtualGrid" } :: { "VirtualGrid" | "VirtualList" } do
					local engine, runtime, UI, target = setup()
					local selected = Compose.cell({})
					local activated = 0
					local stop, list: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = records(2),
							key = key,
							mode = "all" :: "all",
							selection = selected,
							onActivate = function()
								activated += 1
							end,
							render = function(): GuiObject
								return (Facet.host(runtime).Frame :: FrameConstructor) {
									Size = engine.types.UDim2.fromScale(1, 1),
								}
							end,
						}
						return (if kind == "VirtualList" then UI.VirtualList else UI.VirtualGrid)(listSpec)
					end, target)
					local hit = list:FindFirstChild("1", true):FindFirstChild("RowHit", true)
					local mouse = { UserInputType = engine.types.Enum.UserInputType.MouseButton1 }
					hit.Activated:Fire(mouse, 1)
					expect(selected:peek()[1]):toBe(true)
					expect(activated):toBe(0)
					hit.Activated:Fire(mouse, 2)
					expect(activated):toBe(1)
					stop()
				end
			end,
		})

		it("moves a handle across the next row with a nonzero top bar inset", {
			id = "native_collections::Compose native collections::moves a handle across the next row with a nonzero top bar inset",
			run = function()
				local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				engine.environment.fakeOn(VerifyRoblox.assertInstance(gui), "GetGuiInset", function()
					return V2.new(0, 58), V2.zero
				end)
				local moved = {}
				local stop, list: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(3),
						key = key,
						mode = "all" :: "all",
						itemSize = 44,
						reorderable = true,
						editing = true,
						onReorder = function(keys: { number }, slot: number)
							table.insert(moved, { keys = keys, slot = slot })
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(VerifyRoblox.assertInstance(list), "AbsolutePosition", V2.new(20, 200))
				engine.environment.poke(VerifyRoblox.assertInstance(list), "AbsoluteWindowSize", V2.new(320, 264))
				engine.environment.poke(
					VerifyRoblox.assertInstance(list:FindFirstChild("LayoutUnit")),
					"AbsoluteSize",
					V2.new(1, 1)
				)
				local row = list:FindFirstChild("2", true):FindFirstChild("Reorderable", true)
				engine.environment.poke(VerifyRoblox.assertInstance(row), "AbsolutePosition", V2.new(20, 244))
				engine.environment.poke(VerifyRoblox.assertInstance(row), "AbsoluteSize", V2.new(314, 44))
				local handle = row:FindFirstChild("Move")
				engine.environment.poke(VerifyRoblox.assertInstance(handle), "AbsolutePosition", V2.new(290, 244))
				engine.environment.poke(VerifyRoblox.assertInstance(handle), "AbsoluteSize", V2.new(44, 44))
				local input = assert(ctx.config.userInputService)
				nativeDrag.press(handle, {
					UserInputType = E.UserInputType.MouseButton1,
					UserInputState = E.UserInputState.Begin,
					Position = V3.new(312, 266, 0),
				})
				nativeDrag.move(input, {
					UserInputType = E.UserInputType.MouseMovement,
					Position = V3.new(312, 314, 0),
				})
				expect(row:GetAttribute("FacetDragging")):toBe(true)
				nativeDrag.finish(input, {
					UserInputType = E.UserInputType.MouseButton1,
					UserInputState = E.UserInputState.End,
					Position = V3.new(312, 314, 0),
				})
				expect(moved):toEqual({ { keys = { 2 }, slot = 2 } })
				expect(row:GetAttribute("FacetDragging")):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		it("uses native whole-row dragging in plugin windows without global mouse events", {
			id = "native_collections::Compose native collections::uses native whole-row dragging in plugin windows without global mouse events",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V2 = engine.types.Enum, engine.types.Vector2
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					E.PreferredInput.KeyboardAndMouse
				)
				local widget = engine.new("DockWidgetPluginGui")
				ctx.config.inputParent = (widget :: unknown) :: DockWidgetPluginGui
				local reorders = {}
				local stop, list: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(3),
						key = key,
						mode = "all" :: "all",
						itemSize = 40,
						reorderable = true,
						onReorder = function(keys: { number }, slot: number)
							table.insert(reorders, { keys = keys, slot = slot })
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(VerifyRoblox.assertInstance(list), "AbsoluteWindowSize", V2.new(200, 120))
				local row = list:FindFirstChild("1", true):FindFirstChild("Action", true)
				local V3 = engine.types.Vector3
				local press = {
					UserInputType = E.UserInputType.MouseButton1,
					UserInputState = E.UserInputState.End,
					Position = V3.new(35, 0, 0),
				}
				row.MouseButton1Down:Fire(97, 20)
				row.InputBegan:Fire(press)
				press.Position = V3.new(35, 2, 0)
				row.InputEnded:Fire(press)
				expect(#reorders):toBe(0)
				press.Position = V3.new(35, 0, 0)
				row.MouseButton1Down:Fire(97, 20)
				row.InputBegan:Fire(press)
				press.Position = V3.new(35, 90, 0)
				row.InputEnded:Fire(press)
				expect(reorders):toEqual({ { keys = { 1 }, slot = 2 } })
				press.Position = V3.new(35, 0, 0)
				press.UserInputState = E.UserInputState.Begin
				row.MouseButton1Down:Fire(97, 20)
				row.InputBegan:Fire(press)
				list.MouseMoved:Fire(97, 110)
				engine.environment.fire(widget, "WindowFocusReleased")
				press.UserInputState = E.UserInputState.End
				row.InputEnded:Fire(press)
				expect(#reorders):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		it("reuses row containers, replaces reactive items and anchors native scrolling", {
			id = "native_collections::Compose native collections::reuses row containers, replaces reactive items and anchors native scrolling",
			run = function()
				local engine, runtime, UI, target, _, _, fixture = setup()
				local tracking = fixture.track()
				local rows = records(100)
				local source, status =
					Compose.cell(rows), Compose.cell({
						mode = "windowed" :: "windowed",
						direction = "vertical" :: "vertical",
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
					} :: Compose.OrderedCollectionStatus)
				local rendered, disposed = 0, 0
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = source,
						key = key,
						itemSize = 20,
						overscan = 0,
						status = status,
						render = function(current): GuiObject
							rendered += 1
							Compose.cleanup(function()
								disposed += 1
							end)
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				expect(status:peek().retained):toBe(5)
				local initialContainers = {}
				for _, row in node:FindFirstChild("Items"):GetChildren() do
					initialContainers[row] = true
				end
				local original = node:FindFirstChild("1", true):FindFirstChild("Action", true)
				local changed = table.clone(rows)
				changed[1] = { id = 1, label = "Updated" }
				source:set(changed)
				expect((node:FindFirstChild("1", true):FindFirstChild("Action", true))):toBe(original)
				expect(original.Text):toBe("Updated")
				node.CanvasPosition = engine.types.Vector2.new(0, 400)
				expect(status:peek().first):toBe(21)
				local before = node:FindFirstChild("21", true)
				local nextRows = table.clone(changed)
				table.remove(nextRows, 1)
				source:set(nextRows)
				expect(node.CanvasPosition.Y):toBe(380)
				expect(status:peek().first):toBe(20)
				expect((node:FindFirstChild("21", true))):toBe(before)
				node.CanvasPosition = engine.types.Vector2.new(0, 800)
				local reused = false
				for _, row in node:FindFirstChild("Items"):GetChildren() do
					reused = reused or initialContainers[row] == true
				end
				expect(reused):toBe(true)
				for index = 1, 10 do
					node.CanvasPosition = engine.types.Vector2.new(0, index * 100)
				end
				stop()
				expect(disposed):toBe(rendered)
				for _, made in tracking.created do
					if
						VerifyRoblox.isInstance(made)
						and (
							(VerifyRoblox.assertInstance(made)).Name == "Content"
							or (VerifyRoblox.assertInstance(made)).Name == "Action"
						)
					then
						expect(engine.environment.isAlive(made)):toBe(false)
					end
				end
				tracking.stop()
				runtime:dispose()
			end,
		})

		it("accepts a field name as the collection key", {
			id = "native_collections::Compose native collections::accepts a field name as the collection key",
			run = function()
				local engine, runtime, UI, target = setup()
				local source = Compose.cell({ { id = 7, label = "Seven" }, { id = 9, label = "Nine" } })
				local keys: { string } = {}
				local stopList, list: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, string> =
						{
							from = source,
							key = "id",
							itemSize = 20,
							render = function(current, _placement, rowKey): GuiObject
								table.insert(keys, rowKey:peek())
								return button(UI, current)
							end,
						}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(list),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				expect(list:FindFirstChild("7", true) ~= nil):toBe(true)
				expect(keys[1]):toBe("7")
				stopList()
				local stopTable, tableNode: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: number, label: string }, string> = {
						from = source,
						key = "id",
						columns = {
							{
								id = "label",
								label = "Name",
								render = function(current): GuiObject
									return button(UI, current)
								end,
							} :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(tableNode:FindFirstChild("Body")),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				expect(tableNode:FindFirstChild("Body"):FindFirstChild("9", true) ~= nil):toBe(true)
				stopTable()
				local ok, message = pcall(function()
					local stopBad = runtime.mount(function()
						local build: (FixtureCollectionProps.KeyedCollectionSpec<Record, number>, string?) -> ScrollingFrame =
							UI.VirtualList
						return build({
							from = source,
							key = 3,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						} :: any)
					end, target)
					stopBad()
				end)
				expect(ok):toBe(false)
				expect(string.find(tostring(message), "key must be a function or a field name", 1, true) ~= nil):toBe(
					true
				)
				runtime:dispose()
			end,
		})

		it("defers initial offscreen focus until native geometry and suppresses navigation while editing", {
			id = "native_collections::Compose native collections::defers initial offscreen focus until native geometry and suppresses navigation while editing",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local focus: FixtureCollectionTypes.FocusControls<any> = {}
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(100),
						key = key,
						itemSize = 20,
						overscan = 0,
						focus = focus,
						initialFocus = 50,
						disabled = function(item)
							return item.id == 51
						end,
						render = function(current): GuiObject
							return Facet.host(runtime).TextBox({
								Text = function(use: Use)
									return use(current).label
								end,
								Selectable = true,
							}, "Editor")
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				expect(gui.SelectedObject):toBeNil()
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				expect((assert(gui.SelectedObject) :: TextLabel).Text):toBe("50")
				local down = target:FindFirstChild("FacetCollectionDown"):FindFirstChild("CollectionDown")
				local focusedBox = assert(gui.SelectedObject) :: TextBox
				focusedBox:CaptureFocus()
				down.Pressed:Fire()
				expect((assert(focus.current):peek())):toBe(50)
				focusedBox:ReleaseFocus()
				down.Pressed:Fire()
				expect((assert(focus.current):peek())):toBe(52)
				expect((assert(gui.SelectedObject) :: TextLabel).Text):toBe("52")
				stop()
				runtime:dispose()
			end,
		})

		it("wraps arrow and D-pad focus at both ends when wrapFocus is set", {
			id = "native_collections::Compose native collections::wraps arrow and D-pad focus at both ends when wrapFocus is set",
			run = function()
				for _, wrap in { true, false } do
					local engine, runtime, UI, target, gui = setup()
					local focus: FixtureCollectionTypes.FocusControls<any> = {}
					local stop, node: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = records(5),
							key = key,
							itemSize = 20,
							focus = focus,
							wrapFocus = wrap,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						}
						return UI.VirtualList(listSpec)
					end, target)
					engine.environment.poke(
						VerifyRoblox.assertInstance(node),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(200, 100)
					)
					assert(focus.focus)(5)
					expect((assert(gui.SelectedObject) :: TextLabel).Text):toBe("5")
					target:FindFirstChild("FacetCollectionDown"):FindFirstChild("CollectionDown").Pressed:Fire()
					expect((assert(focus.current):peek())):toBe(if wrap then 1 else 5)
					assert(focus.focus)(1)
					target:FindFirstChild("FacetCollectionUp"):FindFirstChild("CollectionUp").Pressed:Fire()
					expect((assert(focus.current):peek())):toBe(if wrap then 5 else 1)
					target:FindFirstChild("FacetCollectionRight"):FindFirstChild("CollectionRight").Pressed:Fire()
					expect((assert(focus.current):peek())):toBe(if wrap then 5 else 1)
					stop()
					runtime:dispose()
				end
			end,
		})

		it("uses measured extents and column placements for both scroll directions", {
			id = "native_collections::Compose native collections::uses measured extents and column placements for both scroll directions",
			run = function()
				for _, direction in { "vertical", "horizontal" } :: { "horizontal" | "vertical" } do
					local engine, runtime, UI, target = setup()
					local measured, columns, gap = Compose.cell({ [1] = 60 }), Compose.cell(2), Compose.cell(5)
					local controls: FixtureComposeTypes.OrderedCollectionControls<any>, status =
						{}, Compose.cell({
							mode = "windowed" :: "windowed",
							direction = "vertical" :: "vertical",
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
						} :: Compose.OrderedCollectionStatus)
					local stop, node: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = records(10),
							key = key,
							columns = columns,
							direction = direction :: "horizontal" | "vertical",
							measured = measured,
							itemSize = 20,
							gap = gap,
							crossGap = 10,
							overscan = 0,
							status = status,
							controls = controls,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						}
						return UI.VirtualGrid(listSpec)
					end, target)
					engine.environment.poke(
						VerifyRoblox.assertInstance(node),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(200, 100)
					)
					expect(assert(controls.placementOf)(3).offset):toBe(65)
					expect(status:peek().extent):toBe(160)
					measured:set({ [1] = 40 })
					expect(assert(controls.placementOf)(3).offset):toBe(45)
					columns:set(1)
					expect(assert(controls.placementOf)(2).offset):toBe(45)
					local second = node:FindFirstChild("2", true)
					expect(if direction == "horizontal" then second.Position.X.Offset else second.Position.Y.Offset):toBe(
						45
					)
					gap:set(9)
					expect(assert(controls.placementOf)(2).offset):toBe(49)
					expect((node:FindFirstChild("2", true))):toBe(second)
					stop()
					runtime:dispose()
				end
			end,
		})

		it("observes automatic row sizes without overwriting content geometry", {
			id = "native_collections::Compose native collections::observes automatic row sizes without overwriting content geometry",
			run = function()
				local engine, runtime, UI, target = setup()
				local status = Compose.cell({
					mode = "windowed" :: "windowed",
					direction = "vertical" :: "vertical",
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
				} :: Compose.OrderedCollectionStatus)
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(5),
						key = key,
						itemSize = 20,
						measure = true,
						status = status,
						render = function(): GuiObject
							return (Facet.host(runtime).Frame :: FrameConstructor)({
								AutomaticSize = engine.types.Enum.AutomaticSize.Y,
								Size = engine.types.UDim2.new(1, 0, 0, 0),
							}, "Measured")
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				local content = node:FindFirstChild("1", true):FindFirstChild("Measured", true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(content),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 60)
				)
				expect(status:peek().extent):toBe(140)
				expect(content.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
				expect(content.Size.Y.Offset):toBe(0)
				stop()
				runtime:dispose()
			end,
		})

		it("measures original content through action and selection wrappers", {
			id = "native_collections::Compose native collections::measures original content through action and selection wrappers",
			run = function()
				local engine, runtime, UI, target = setup()
				local status = Compose.cell({
					mode = "windowed" :: "windowed",
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
				} :: Compose.OrderedCollectionStatus)
				local stop, node: any = runtime.mount(function()
					local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = records(5),
						key = key,
						itemSize = 20,
						measure = true,
						selectionMode = "multiple" :: "multiple",
						editing = true,
						rowActions = function(): FixtureCollectionProps.RowActionsOptions
							return { trailing = { { id = "open", label = "Open", onActivate = function() end } } }
						end,
						status = status,
						render = function(): GuiObject
							return Facet.host(runtime).Frame({
								AutomaticSize = engine.types.Enum.AutomaticSize.Y,
								Size = engine.types.UDim2.new(1, 0, 0, 0),
							}, "Measured")
						end,
					}
					return UI.VirtualList(props)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				local content = node:FindFirstChild("1", true):FindFirstChild("Measured", true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(content),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 60)
				)
				expect(status:peek().extent):toBe(140)
				expect(content.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
				expect(content.Size.Y.Offset):toBe(0)
				stop()
				runtime:dispose()
			end,
		})

		it("measures a row at its unscaled size while a lift scale grows it", {
			id = "native_collections::Compose native collections::measures a row at its unscaled size while a lift scale grows it",
			run = function()
				local engine, runtime, UI, target = setup()
				local status = Compose.cell({
					mode = "windowed" :: "windowed",
					direction = "vertical" :: "vertical",
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
				} :: Compose.OrderedCollectionStatus)
				local lift = Compose.cell(1)
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(5),
						key = key,
						itemSize = 20,
						measure = true,
						status = status,
						render = function(): GuiObject
							return (Facet.host(runtime).Frame :: FrameConstructor)({
								AutomaticSize = engine.types.Enum.AutomaticSize.Y,
								Size = engine.types.UDim2.new(1, 0, 0, 0),
								Facet.host(runtime).UIScale({
									Name = "Lift",
									Scale = lift,
								}),
							}, "Measured")
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				local slot = node:FindFirstChild("1", true)
				local content = slot:FindFirstChild("Measured", true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(content),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 60)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(slot),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 60)
				)
				expect(status:peek().extent):toBe(140)
				lift:set(1.5)
				engine.environment.poke(
					VerifyRoblox.assertInstance(content),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 90)
				)
				expect(status:peek().extent):toBe(140)
				expect(slot.Size.Y.Offset):toBe(60)
				engine.environment.poke(
					VerifyRoblox.assertInstance(content),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 90.6)
				)
				expect(slot.Size.Y.Offset):toBe(60)
				engine.environment.poke(
					VerifyRoblox.assertInstance(content),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 135)
				)
				expect(slot.Size.Y.Offset):toBe(90)
				expect(status:peek().extent):toBe(170)
				engine.environment.poke(
					VerifyRoblox.assertInstance(content),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 90)
				)
				expect(slot.Size.Y.Offset):toBe(60)
				engine.environment.poke(
					VerifyRoblox.assertInstance(slot),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 60)
				)
				expect(status:peek().extent):toBe(140)
				lift:set(1)
				engine.environment.poke(
					VerifyRoblox.assertInstance(content),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 60)
				)
				expect(slot.Size.Y.Offset):toBe(60)
				expect(status:peek().extent):toBe(140)
				stop()
				runtime:dispose()
			end,
		})

		it("reserves Card lift paint in list rows and at both viewport edges", {
			run = function()
				for _, direction in { "vertical", "horizontal" } do
					local engine, runtime, UI, target, _, ctx = setup {
						motionLevel = "normal",
						theme = { metrics = { motion = { materialize = { lift = 1.06 } } } },
					}
					require("../src/ui/card")(ctx, UI)
					local stop, mounted = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<{ id: string }, string> = {
							from = { { id = "first" }, { id = "last" } },
							key = "id",
							mode = "all",
							direction = direction :: "vertical" | "horizontal",
							itemSize = 132,
							gap = 16,
							render = function(): GuiObject
								return UI.Card { Name = "Card", title = "Upgrade" }
							end,
						}
						return UI.VirtualList(listSpec)
					end, target)
					local list = (mounted :: unknown) :: ScrollingFrame
					local horizontal = direction == "horizontal"
					engine.environment.poke(
						FixtureRoblox.assertInstance(list),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(if horizontal then 280 else 700, if horizontal then 700 else 280)
					)
					local items = assert(list:FindFirstChild("Items"))
					local padding = assert(items:FindFirstChildWhichIsA("UIPadding")) :: UIPadding
					local crossEdge = if horizontal then padding.PaddingTop.Offset else padding.PaddingLeft.Offset
					local mainEdge = if horizontal then padding.PaddingLeft.Offset else padding.PaddingTop.Offset
					expect(crossEdge >= 700 * 0.06 / 2):toBe(true)
					expect(mainEdge >= 132 * 0.06 / 2):toBe(true)
					local extent = if horizontal then list.CanvasSize.X.Offset else list.CanvasSize.Y.Offset
					expect(extent):toBe(2 * 132 + 16 + 2 * mainEdge)
					for _, key in { "first", "last" } do
						local slot = assert(items:FindFirstChild(key)) :: Frame
						local card = assert(slot:FindFirstChild("Card", true)) :: Frame
						local group = assert(card:FindFirstAncestor("Content")) :: CanvasGroup
						local inset = assert(group:FindFirstChildWhichIsA("UIPadding")) :: UIPadding
						local surface = assert(card.Parent) :: Frame
						local mainAxis = if horizontal
							then engine.types.Enum.AutomaticSize.X
							else engine.types.Enum.AutomaticSize.Y
						expect(surface.AutomaticSize):toBe(mainAxis)
						expect(group.AutomaticSize):toBe(mainAxis)
						expect(group.Position.X.Offset + inset.PaddingLeft.Offset):toBe(0)
						expect(group.Position.Y.Offset + inset.PaddingTop.Offset):toBe(0)
						expect(group.Size.X.Offset):toBe(2 * inset.PaddingLeft.Offset)
						expect(group.Size.Y.Offset):toBe(2 * inset.PaddingTop.Offset)
						expect(inset.PaddingLeft.Offset > 0):toBe(true)
						expect(inset.PaddingTop.Offset > 0):toBe(true)
						expect(if horizontal then slot.Size.X.Offset else slot.Size.Y.Offset):toBe(132)
						local restSize, restPosition = slot.Size, slot.Position
						local paintSize, paintPosition = group.Size, group.Position
						local scale = assert(card:FindFirstChild("Lift")) :: UIScale
						local events = (card :: unknown) :: {
							MouseEnter: { Fire: (unknown) -> () },
							MouseLeave: { Fire: (unknown) -> () },
						}
						for _, active in { true, false } do
							if active then
								events.MouseEnter:Fire()
							else
								events.MouseLeave:Fire()
							end
							for _ = 1, 120 do
								engine.heartbeat:Fire(1 / 60)
							end
							expect(math.abs(scale.Scale - (if active then 1.06 else 1)) < 0.001):toBe(true)
							expect(slot.Size):toBe(restSize)
							expect(slot.Position):toBe(restPosition)
							expect(group.Size):toBe(paintSize)
							expect(group.Position):toBe(paintPosition)
							expect(if horizontal then list.CanvasSize.X.Offset else list.CanvasSize.Y.Offset):toBe(
								extent
							)
						end
					end
					local endOffset = extent - 280
					list.CanvasPosition = engine.types.Vector2.new(
						if horizontal then endOffset else 0,
						if horizontal then 0 else endOffset
					)
					expect(if horizontal then list.CanvasPosition.X else list.CanvasPosition.Y):toBe(endOffset)
					list.CanvasPosition = engine.types.Vector2.zero
					expect(list.CanvasPosition):toBe(engine.types.Vector2.zero)
					stop()
					runtime:dispose()
				end
			end,
		})

		it("keeps explicit Card list clipping without reserving lift overflow", {
			run = function()
				local engine, runtime, UI, target, _, ctx = setup()
				require("../src/ui/card")(ctx, UI)
				local stop, mounted = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<number, number> = {
						from = { 1 },
						key = function(value: number): number
							return value
						end,
						mode = "all",
						itemSize = 132,
						contentOverflow = "clip",
						render = function(): GuiObject
							return UI.Card { Name = "Card", title = "Upgrade" }
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				local list = (mounted :: unknown) :: ScrollingFrame
				local card = assert(list:FindFirstChild("Card", true))
				local group = assert(card:FindFirstAncestor("Content")) :: CanvasGroup
				expect(group.ClipsDescendants):toBe(true)
				expect(group:FindFirstChildWhichIsA("UIPadding")):toBe(nil)
				expect(list.CanvasSize.Y.Offset):toBe(132)
				stop()
				runtime:dispose()
			end,
		})

		it("reserves both paint edges for an unmeasured Card without changing the row estimate", {
			run = function()
				local engine, runtime, UI, target, _, ctx = setup { motionLevel = "normal" }
				require("../src/ui/card")(ctx, UI)
				local stop, mounted = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<{ id: string }, string> = {
						from = { { id = "card" } },
						key = "id",
						columns = 1,
						itemSize = 132,
						render = function(): GuiObject
							return UI.Card {
								Name = "Card",
								title = "Upgrade",
								caption = "Details",
								primaryAction = { label = "Buy", onActivate = function() end },
							}
						end,
					}
					return UI.VirtualGrid(listSpec)
				end, target)
				local grid = (mounted :: unknown) :: ScrollingFrame
				engine.environment.poke(
					VerifyRoblox.assertInstance(grid),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(320, 280)
				)
				local card = assert(grid:FindFirstChild("Card", true)) :: Frame
				(assert(card:FindFirstChild("Lift")) :: UIScale).Scale = 1.04
				engine.environment.poke(
					VerifyRoblox.assertInstance(card),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 520)
				)
				local group = assert(card:FindFirstAncestor("Content")) :: CanvasGroup
				local padding = assert(group:FindFirstChildWhichIsA("UIPadding")) :: UIPadding
				expect(padding.PaddingTop.Offset >= 20):toBe(true)
				expect(padding.PaddingBottom.Offset):toBe(padding.PaddingTop.Offset)
				expect(group.Position.Y.Offset + padding.PaddingTop.Offset):toBe(0)
				expect(group.Size.Y.Offset - padding.PaddingTop.Offset - padding.PaddingBottom.Offset):toBe(0)
				expect(group:GetAttribute("FacetCollectionRow")):toBe(true)
				local paintRoots = 0
				for _, node in group:GetDescendants() do
					if node:GetAttribute("FacetCollectionRow") then
						paintRoots += 1
					end
				end
				expect(paintRoots):toBe(0)
				expect((assert(group.Parent) :: Frame).Size.Y.Offset):toBe(132)
				stop()
				runtime:dispose()
			end,
		})

		it("reserves the themed Card lift envelope at every grid corner and the canvas end", {
			id = "native_collections::Compose native collections::reserves the themed Card lift envelope at every grid corner and the canvas end",
			run = function()
				local engine, runtime, UI, target = setup({
					motionLevel = "normal",
					theme = { metrics = { motion = { materialize = { lift = 1.06 } } } },
				})
				local Host = (
					runtime.constructors :: unknown
				) :: typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
				local stop, mounted = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, string> = {
						from = records(60),
						key = "id",
						columns = 4,
						itemSize = 320,
						mode = "all" :: "all",
						measure = true,
						gap = 16,
						crossGap = 16,
						onActivate = function() end,
						render = function(): GuiObject
							return Host.Frame {
								Name = "Card",
								Size = engine.types.UDim2.fromScale(1, 0),
								Attributes = { FacetBody = "button" },
								Host.UIScale { Name = "Lift", Scale = 1.06 },
								Host.Frame { Name = "LayoutUnit", Size = engine.types.UDim2.fromOffset(1, 1) },
							}
						end,
					}
					return UI.VirtualGrid(listSpec)
				end, target)
				local grid = (mounted :: unknown) :: ScrollingFrame
				local geometry = (grid :: unknown) :: { AbsoluteWindowSize: Vector2 }
				engine.environment.poke(
					VerifyRoblox.assertInstance(geometry),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(1242, 648)
				)
				local items = assert(grid:FindFirstChild("Items"))
				local padding = assert(items:FindFirstChildWhichIsA("UIPadding")) :: UIPadding
				for _, slot in items:GetChildren() do
					local card = slot:FindFirstChild("Card", true)
					if card then
						local unit = (card:FindFirstChild("LayoutUnit") :: unknown) :: { AbsoluteSize: Vector2 }
						engine.environment.poke(
							VerifyRoblox.assertInstance(unit),
							"AbsoluteSize",
							engine.types.Vector2.new(1.06, 1.06)
						)
						local bounds = (card :: unknown) :: { AbsoluteSize: Vector2 }
						local index = assert(tonumber(slot.Name))
						local height = if index <= 4 or index >= 57
							then 280.47
							elseif index <= 8 then 282 * 1.06
							else 280 * 1.06
						engine.environment.poke(
							VerifyRoblox.assertInstance(bounds),
							"AbsoluteSize",
							engine.types.Vector2.new(311.88, height)
						)
					end
				end
				expect(grid.CanvasSize.Y.Offset):toBe(4412 - 16 + 2 * padding.PaddingTop.Offset)
				local endOffset = grid.CanvasSize.Y.Offset - 648
				grid.CanvasPosition = engine.types.Vector2.new(0, endOffset)
				expect(grid.CanvasPosition.Y):toBe(endOffset)
				for _, index in { 1, 4, 57, 60 } do
					local slot = assert(items:FindFirstChild(tostring(index))) :: Frame
					local scroll = if index > 4 then grid.CanvasSize.Y.Offset - 648 else 0
					local x = 16 + padding.PaddingLeft.Offset + slot.Position.X.Offset
					local y = 40 + padding.PaddingTop.Offset + slot.Position.Y.Offset - scroll
					local width, height = slot.Size.X.Offset, slot.Size.Y.Offset
					for _, restHeight in { height, height + (282.57 - 280.47) / 1.06 } do
						local left, top = x - width * 0.06 / 2, y - restHeight * 0.06 / 2
						expect(left >= 16):toBe(true)
						expect(top >= 40):toBe(true)
						expect(left + width * 1.06 <= 1258):toBe(true)
						expect(top + restHeight * 1.06 <= 688):toBe(true)
					end
				end
				stop()
				runtime:dispose()
			end,
		})

		it("measures a slot-filling row in layout units under a scaled ancestor", {
			id = "native_collections::Compose native collections::measures a slot-filling row in layout units under a scaled ancestor",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(3),
						key = key,
						itemSize = 20,
						measure = true,
						render = function(): GuiObject
							return (Facet.host(runtime).Frame :: FrameConstructor)({
								Size = engine.types.UDim2.fromScale(1, 1),
							}, "Fill")
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node:FindFirstChild("LayoutUnit")),
					"AbsoluteSize",
					engine.types.Vector2.new(1.25, 1.25)
				)
				local slot = node:FindFirstChild("1", true)
				local fill = slot:FindFirstChild("Fill", true)
				local writes = 0
				local function relayout()
					writes += 1
					if writes > 40 then
						return
					end
					local size = engine.types.Vector2.new(200 * 1.25, slot.Size.Y.Offset * 1.25)
					engine.environment.poke(VerifyRoblox.assertInstance(slot), "AbsoluteSize", size)
					engine.environment.poke(VerifyRoblox.assertInstance(fill), "AbsoluteSize", size)
				end
				slot:GetPropertyChangedSignal("Size"):Connect(relayout)
				relayout()
				expect(slot.Size.Y.Offset):toBe(20)
				expect(writes):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		it("follows a readable follow policy while the viewport stays at the end", {
			id = "native_collections::Compose native collections::follows a readable follow policy while the viewport stays at the end",
			run = function()
				local engine, runtime, UI, target = setup()
				local source, follow = Compose.cell(records(10)), Compose.cell("none" :: "end" | "none")
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = source,
						key = key,
						itemSize = 20,
						overscan = 0,
						follow = follow,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				expect(node.CanvasPosition.Y):toBe(0)
				node.CanvasPosition = engine.types.Vector2.new(0, 100)
				source:set(records(11))
				expect(node.CanvasPosition.Y):toBe(100)
				node.CanvasPosition = engine.types.Vector2.new(0, 120)
				follow:set("end")
				expect(node.CanvasPosition.Y):toBe(120)
				source:set(records(12))
				expect(node.CanvasPosition.Y):toBe(140)
				follow:set("none")
				source:set(records(13))
				expect(node.CanvasPosition.Y):toBe(140)
				stop()
				expect(function()
					runtime.mount(function()
						local build: (FixtureCollectionProps.KeyedCollectionSpec<Record, number>, string?) -> ScrollingFrame =
							UI.VirtualList
						return build({
							from = source,
							key = key,
							follow = "bottom",
							render = function(current): GuiObject
								return button(UI, current)
							end,
						} :: any)
					end, target)
				end):toThrow()
				runtime:dispose()
			end,
		})

		it("follows appended rows only while native viewport stays at the end", {
			id = "native_collections::Compose native collections::follows appended rows only while native viewport stays at the end",
			run = function()
				local engine, runtime, UI, target = setup()
				local source, status =
					Compose.cell(records(10)), Compose.cell({
						mode = "windowed" :: "windowed",
						direction = "vertical" :: "vertical",
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
					} :: Compose.OrderedCollectionStatus)
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = source,
						key = key,
						itemSize = 20,
						overscan = 0,
						follow = "end" :: "end",
						status = status,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				expect(node.CanvasPosition.Y):toBe(100)
				source:set(records(11))
				expect(node.CanvasPosition.Y):toBe(120)
				node.CanvasPosition = engine.types.Vector2.new(0, 0)
				source:set(records(12))
				expect(node.CanvasPosition.Y):toBe(0)
				expect(status:peek().following):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		it("defers keyed selection while its row is outside an ancestor clipping window", {
			id = "native_collections::Compose native collections::defers keyed selection while its row is outside an ancestor clipping window",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local clip = engine.new("Frame")
				clip.Parent = target
				clip.ClipsDescendants = true
				engine.environment.poke(
					VerifyRoblox.assertInstance(clip),
					"AbsolutePosition",
					engine.types.Vector2.zero
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(clip),
					"AbsoluteSize",
					engine.types.Vector2.new(430, 874)
				)
				local focus: FixtureCollectionTypes.FocusControls<number> = {}
				local stop, mounted = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(10),
						key = key,
						itemSize = 44,
						focus = focus,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, clip)
				local node = mounted :: ScrollingFrame
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(280, 204)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteSize",
					engine.types.Vector2.new(280, 204)
				)
				assert(focus.focus)(2)
				local row = assert(gui.SelectedObject)
				assert(focus.clear)()
				gui.SelectedObject = nil
				engine.environment.poke(
					VerifyRoblox.assertInstance(row),
					"AbsolutePosition",
					engine.types.Vector2.new(-113, 5873.6)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(row),
					"AbsoluteSize",
					engine.types.Vector2.new(61, 44)
				)
				assert(focus.focus)(2)
				expect(gui.SelectedObject):toBeNil()
				expect(assert(focus.current):peek()):toBe(2)
				engine.environment.poke(
					VerifyRoblox.assertInstance(row),
					"AbsolutePosition",
					engine.types.Vector2.new(32, 100)
				)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", engine.types.Vector2.zero)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsolutePosition",
					engine.types.Vector2.new(16, 80)
				)
				engine.heartbeat:Fire(1 / 60)
				expect(gui.SelectedObject):toBeNil()
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteSize",
					engine.types.Vector2.new(280, 204)
				)
				engine.heartbeat:Fire(1 / 60)
				expect(gui.SelectedObject):toBe(row)
				stop()
				runtime:dispose()
			end,
		})

		it("restores the keyed native focus target when virtualization remounts it", {
			id = "native_collections::Compose native collections::restores the keyed native focus target when virtualization remounts it",
			run = function()
				local engine, runtime, UI, target, gui, _, fixture = setup()
				local tracking = fixture.track()
				local focus: FixtureCollectionTypes.FocusControls<any> = {}
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(100),
						key = key,
						itemSize = 20,
						overscan = 0,
						focus = focus,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				assert(focus.focus)(50)
				expect((assert(gui.SelectedObject) :: TextLabel).Text):toBe("50")
				expect(node.CanvasPosition.Y):toBe(900)
				local action
				for _, object in tracking.created do
					if not VerifyRoblox.isInstance(object) then
						continue
					end
					local native = VerifyRoblox.assertInstance(object)
					local parent = native.Parent
					if
						native.Name == "Activate"
						and engine.environment.isAlive(native)
						and parent
						and parent.Enabled
					then
						action = native
					end
				end
				expect(action ~= nil):toBe(true)
				node.CanvasPosition = engine.types.Vector2.new(0, 0)
				expect(gui.SelectedObject):toBeNil()
				local fifty = node:FindFirstChild("50", true)
				expect(fifty == nil or not fifty:IsAncestorOf(assert(action))):toBe(true)
				node.CanvasPosition = engine.types.Vector2.new(0, 900)
				expect((assert(gui.SelectedObject) :: TextLabel).Text):toBe("50")
				stop()
				tracking.stop()
				expect(gui.SelectedObject):toBeNil()
				runtime:dispose()
			end,
		})

		it("waits for a PlayerGui before it restores the keyed focus target", {
			id = "native_collections::Compose native collections::waits for a PlayerGui before it restores the keyed focus target",
			run = function()
				local engine, runtime, UI, target, gui = setup({ engine = { selectionNeedsPlayerGui = true } })
				local focus: FixtureCollectionTypes.FocusControls<any> = {}
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(100),
						key = key,
						itemSize = 20,
						overscan = 0,
						focus = focus,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				expect((pcall(assert(focus.focus), 50))):toBe(true)
				expect(gui.SelectedObject):toBeNil()
				target.Parent = (engine.new("PlayerGui") :: unknown) :: PlayerGui
				assert(focus.focus)(51)
				expect((assert(gui.SelectedObject) :: TextLabel).Text):toBe("51")
				stop()
				runtime:dispose()
			end,
		})

		it("keeps table cells alive across sort and native column resize and prunes selection", {
			id = "native_collections::Compose native collections::keeps table cells alive across sort and native column resize and prunes selection",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local source = Compose.cell({ { id = 1, label = "Z" }, { id = 2, label = "A" } })
				local sort, widths, selection =
					Compose.cell(nil :: { column: string, direction: "ascending" | "descending" }?),
					Compose.cell({} :: { [string]: number }),
					Compose.cell({ [1] = true })
				local builds = 0
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: number, label: string }, number> = {
						from = source,
						key = key,
						sort = sort,
						widths = widths,
						selection = selection,
						columns = {
							{
								id = "label",
								label = "Name",
								width = 100,
								minWidth = 60,
								maxWidth = 160,
								render = function(current): GuiObject
									builds += 1
									return button(UI, current)
								end,
							} :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				local body, header = node:FindFirstChild("Body"), node:FindFirstChild("Header")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local original = body:FindFirstChild("1", true):FindFirstChild("Action", true)
				local column = header:FindFirstChild("label")
				column:FindFirstChild("Sort").Activated:Fire()
				expect((sort:peek())):toEqual({ column = "label", direction = "ascending" :: "ascending" })
				expect((body:FindFirstChild("1", true):FindFirstChild("Action", true))):toBe(original)
				engine.environment.poke(
					VerifyRoblox.assertInstance(column),
					"AbsoluteSize",
					engine.types.Vector2.new(100, 40)
				)
				local grip = column:FindFirstChild("Resize")
				expect(grip.AnchorPoint):toBe(engine.types.Vector2.new(0.5, 0))
				expect(grip.Position):toBe(engine.types.UDim2.fromScale(1, 0))
				expect(grip.Size.X.Offset):toBe(12)
				expect(header.Size.Y.Offset):toBe(40)
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					engine.types.Enum.PreferredInput.Touch
				)
				expect(grip.Size.X.Offset):toBe(44)
				expect(header.Size.Y.Offset):toBe(44)
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					engine.types.Enum.PreferredInput.KeyboardAndMouse
				)
				expect(grip.Size.X.Offset):toBe(12)
				expect(header.Size.Y.Offset):toBe(40)
				local detector = column:FindFirstChildWhichIsA("UIDragDetector", true)
				detector.DragStart:Fire(engine.types.Vector2.new(100, 10))
				detector.DragContinue:Fire(engine.types.Vector2.new(180, 10))
				expect(widths:peek().label):toBe(160)
				engine.environment.poke(
					VerifyRoblox.assertInstance(column:FindFirstChild("LayoutUnit")),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 2)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(column),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 80)
				)
				detector.DragStart:Fire(engine.types.Vector2.new(100, 10))
				detector.DragContinue:Fire(engine.types.Vector2.new(180, 10))
				expect(widths:peek().label):toBe(140)
				widths:set({ label = 160 })
				column:FindFirstChild("Resize").SelectionGained:Fire()
				target:FindFirstChild("FacetNarrowColumn"):FindFirstChild("NarrowColumn").Pressed:Fire()
				expect(widths:peek().label):toBe(152)
				expect(builds):toBe(2)
				source:set({ { id = 2, label = "A" } })
				expect(selection:peek()[1]):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		it("glides the rows that follow a deleted row into place and snaps under reduced motion", {
			id = "native_collections::Compose native collections::glides the rows that follow a deleted row into place and snaps under reduced motion",
			run = function()
				for _, reduced in { false, true } do
					local engine, runtime, UI, target = setup({ motionLevel = if reduced then "none" else "normal" })
					local source = Compose.cell(records(5))
					local stop, node: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = source,
							key = key,
							itemSize = 20,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						}
						return UI.VirtualList(listSpec)
					end, target)
					engine.environment.poke(
						VerifyRoblox.assertInstance(node),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(200, 100)
					)
					local second = node:FindFirstChild("2", true)
					expect(second.Position.Y.Offset):toBe(20)
					local remaining = records(5)
					table.remove(remaining, 1)
					source:set(remaining)
					expect(second.Position.Y.Offset):toBe(if reduced then 0 else 20)
					for _ = 1, 30 do
						engine.heartbeat:Fire(1 / 60)
					end
					expect(second.Position.Y.Offset):toBe(0)
					stop()
					runtime:dispose()
				end
			end,
		})

		it("snaps a moving reorder row when its layout changes without changing its target", {
			id = "native_collections::Compose native collections::snaps a moving reorder row when its layout changes without changing its target",
			run = function()
				local engine, runtime, UI, target = setup({ motionLevel = "normal" })
				local original = records(3)
				local source = Compose.cell(original)
				local itemSize = Compose.cell(20)
				local reduced = Compose.cell(false)
				local stop, mounted = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = source,
						key = key,
						itemSize = itemSize,
						reorderable = true,
						reducedMotion = reduced,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				local node = VerifyRoblox.assertInstance(mounted)
				engine.environment.poke(node, "AbsoluteWindowSize", engine.types.Vector2.new(200, 200))
				local row = (assert(node:FindFirstChild("2", true)) :: unknown) :: GuiObject
				expect(row.Position.Y.Offset):toBe(20)
				source:set({ original[2], original[1], original[3] })
				expect(row.Position.Y.Offset):toBe(20)
				engine.heartbeat:Fire(1 / 60)
				expect(row.Position.Y.Offset > 0 and row.Position.Y.Offset < 20):toBe(true)
				itemSize:set(30)
				expect(row.Position.Y.Offset):toBe(0)
				source:set(original)
				engine.heartbeat:Fire(1 / 60)
				expect(row.Position.Y.Offset > 0 and row.Position.Y.Offset < 30):toBe(true)
				reduced:set(true)
				expect(row.Position.Y.Offset):toBe(30)
				reduced:set(false)
				source:set({ original[2], original[1], original[3] })
				engine.heartbeat:Fire(1 / 60)
				expect(row.Position.Y.Offset > 0 and row.Position.Y.Offset < 30):toBe(true)
				stop()
				runtime:dispose()
				expect(engine.census().connections):toBe(0)
			end,
		})

		it("raises a row whose key arrives after mount into place and shows mounted rows at once", {
			id = "native_collections::Compose native collections::raises a row whose key arrives after mount into place and shows mounted rows at once",
			run = function()
				for _, case in
					{
						{ reduced = false, recycle = false },
						{ reduced = false, recycle = true },
						{ reduced = true, recycle = false },
					}
				do
					local engine, runtime, UI, target =
						setup({ motionLevel = if case.reduced then "none" else "normal" })
					local source = Compose.cell(records(3))
					local stop, mounted = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = source,
							key = key,
							itemSize = 20,
							recycle = case.recycle,
							arrival = "rise" :: "rise",
							render = function(current): GuiObject
								return button(UI, current)
							end,
						}
						return UI.VirtualList(listSpec)
					end, target)
					local node = VerifyRoblox.assertInstance(mounted)
					local function row(name: string): GuiObject
						return (assert(node:FindFirstChild(name, true)) :: unknown) :: GuiObject
					end
					local function content(name: string): CanvasGroup
						return (assert(row(name):FindFirstChild("Content")) :: unknown) :: CanvasGroup
					end
					engine.environment.poke(
						VerifyRoblox.assertInstance(node),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(200, 200)
					)
					local function paint()
						for _, painted in assert(node:FindFirstChild("Items")):GetDescendants() do
							if painted:IsA("GuiObject") then
								engine.environment.poke(
									VerifyRoblox.assertInstance(painted),
									"AbsoluteSize",
									engine.types.Vector2.new(200, 20)
								)
								if painted:IsA("TextLabel") or painted:IsA("TextButton") then
									engine.environment.poke(
										VerifyRoblox.assertInstance(painted),
										"TextBounds",
										engine.types.Vector2.new(40, 20)
									)
								end
							end
						end
						for _ = 1, 4 do
							engine.heartbeat:Fire(1 / 60)
						end
					end
					paint()
					local first = row("1")
					expect(first.Position.Y.Offset):toBe(0)
					expect(content("1").GroupTransparency):toBe(0)
					source:set(records(4))
					paint()
					local fourth = row("4")
					local rising = fourth.Position.Y.Offset
					expect(rising >= 60 and rising <= 72):toBe(true)
					if not case.reduced then
						expect(rising > 60):toBe(true)
						expect(content("4").GroupTransparency > 0):toBe(true)
					end
					for _ = 1, 30 do
						engine.heartbeat:Fire(1 / 60)
					end
					expect(fourth.Position.Y.Offset):toBe(60)
					expect(content("4").GroupTransparency):toBe(0)
					expect(first.Position.Y.Offset):toBe(0)
					stop()
					runtime:dispose()
				end
			end,
		})

		it("lays rows out in layout units under a scaled ancestor, as in a ten-foot preview", {
			id = "native_collections::Compose native collections::lays rows out in layout units under a scaled ancestor, as in a ten-foot preview",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(20),
						key = key,
						itemSize = 20,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node:FindFirstChild("LayoutUnit")),
					"AbsoluteSize",
					engine.types.Vector2.new(0.8, 0.8)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(160, 80)
				)
				expect(node:FindFirstChild("1", true).Size.X.Offset):toBe(200)
				expect(node:FindFirstChild("5", true) ~= nil):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		it("resolves a card rail to one card with a peek on compact touch and to whole cards elsewhere", {
			id = "native_collections::Compose native collections::resolves a card rail to one card with a peek on compact touch and to whole cards elsewhere",
			run = function()
				local distance = Compose.cell("near")
				local engine, runtime, UI, target, _, ctx = setup({
					userInputService = {},
					environment = { viewingDistance = distance },
				})
				local E, V2 = engine.types.Enum, engine.types.Vector2
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					E.PreferredInput.KeyboardAndMouse
				)
				local distant: any
				local stop, node: any = runtime.mount(function()
					distant = ctx.tenFoot()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(20),
						key = key,
						direction = "horizontal" :: "horizontal",
						itemSize = "cards" :: "cards",
						gap = 8,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(1000, 200))
				expect(node:FindFirstChild("1", true).Size.X.Offset):toBe(244)
				distance:set("ten-foot")
				expect(distant()):toBe(true)
				expect(node:FindFirstChild("1", true).Size.X.Offset):toBe(244)
				expect(node:FindFirstChild("2", true).Position.X.Offset):toBe(252)
				distance:set("near")
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					E.PreferredInput.Touch
				)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(400, 200))
				expect(node:FindFirstChild("1", true).Size.X.Offset):toBe(352)
				expect(node:FindFirstChild("2", true).Position.X.Offset):toBe(360)
				stop()
				runtime:dispose()
				expect((pcall(function()
					runtime.mount(function()
						local build: (FixtureCollectionProps.KeyedCollectionSpec<Record, number>, string?) -> ScrollingFrame =
							UI.VirtualList
						return build({ from = {}, render = button, cards = { perView = 2 } } :: any)
					end, target)
				end))):toBe(false)
			end,
		})

		it("withholds a table row's destructive actions from every route when rowDeletable refuses it", {
			id = "native_collections::Compose native collections::withholds a table row's destructive actions from every route when rowDeletable refuses it",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(3),
						key = key,
						itemSize = 20,
						deletable = true,
						rowDeletable = function(item)
							return item.id ~= 1
						end,
						onDelete = function() end,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
						rowActions = function(): FixtureCollectionProps.RowActionsOptions?
							return {
								trailing = {
									{ id = "delete", label = "Delete", role = "destructive" :: "destructive" } :: FixtureCollectionTypes.RowAction,
									{ id = "flag", label = "Flag" } :: FixtureCollectionTypes.RowAction,
								},
							}
						end,
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(300, 100)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local first, second = body:FindFirstChild("1", true), body:FindFirstChild("2", true)
				expect((first:FindFirstChild("trailing", true):FindFirstChild("delete"))):toBeNil()
				expect(first:FindFirstChild("trailing", true):FindFirstChild("flag") ~= nil):toBe(true)
				expect(second:FindFirstChild("trailing", true):FindFirstChild("delete") ~= nil):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		it("a bare modifier press does not flip a touch table to its pointer layout; a real key does", {
			id = "native_collections::Compose native collections::a bare modifier press does not flip a touch table to its pointer layout; a real key does",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E = engine.types.Enum
				local input: any = assert(ctx.config.userInputService)
				local pressed = {}
				engine.environment.fakeOn(VerifyRoblox.assertInstance(input), "GetKeysPressed", function()
					return pressed
				end)
				engine.environment.fakeOn(VerifyRoblox.assertInstance(input), "GetMouseButtonsPressed", function()
					return {}
				end)
				engine.environment.poke(input, "PreferredInput", E.PreferredInput.Touch)
				engine.environment.poke(input, "TouchEnabled", true)
				engine.environment.poke(input, "MouseEnabled", true)
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(3),
						key = key,
						deletable = true,
						onDelete = function() end,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				local function shown()
					return node:FindFirstChild("Toolbar") ~= nil
				end
				expect((shown())):toBe(true)
				for _, modifier in { E.KeyCode.LeftSuper, E.KeyCode.LeftControl, E.KeyCode.LeftShift } do
					pressed = { { KeyCode = modifier } }
					input.InputBegan:Fire({ UserInputType = E.UserInputType.Keyboard, KeyCode = modifier })
					engine.environment.poke(
						VerifyRoblox.assertInstance(input),
						"PreferredInput",
						E.PreferredInput.KeyboardAndMouse
					)
					expect((shown())):toBe(true)
					pressed = {}
					engine.environment.poke(
						VerifyRoblox.assertInstance(input),
						"PreferredInput",
						E.PreferredInput.Touch
					)
				end
				pressed = { { KeyCode = E.KeyCode.LeftSuper } }
				engine.environment.poke(
					VerifyRoblox.assertInstance(input),
					"PreferredInput",
					E.PreferredInput.KeyboardAndMouse
				)
				expect((shown())):toBe(true)
				pressed = { { KeyCode = E.KeyCode.LeftSuper }, { KeyCode = E.KeyCode.C } }
				input.InputBegan:Fire({ UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.C })
				expect((shown())):toBe(false)
				pressed = {}
				engine.environment.poke(VerifyRoblox.assertInstance(input), "PreferredInput", E.PreferredInput.Touch)
				expect((shown())):toBe(true)
				pressed = { { KeyCode = E.KeyCode.A } }
				engine.environment.poke(
					VerifyRoblox.assertInstance(input),
					"PreferredInput",
					E.PreferredInput.KeyboardAndMouse
				)
				expect((shown())):toBe(false)
				pressed = {}
				engine.environment.poke(VerifyRoblox.assertInstance(input), "PreferredInput", E.PreferredInput.Touch)
				pressed = { { KeyCode = E.KeyCode.LeftShift } }
				engine.environment.poke(
					VerifyRoblox.assertInstance(input),
					"PreferredInput",
					E.PreferredInput.KeyboardAndMouse
				)
				expect((shown())):toBe(true)
				pressed = {}
				input.InputChanged:Fire({ UserInputType = E.UserInputType.MouseMovement })
				expect((shown())):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		it("keeps a gap under its Edit toolbar and paints the header band across the persistent scrollbar", {
			id = "native_collections::Compose native collections::keeps a gap under its Edit toolbar and paints the header band across the persistent scrollbar",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E = engine.types.Enum
				local input: any = assert(ctx.config.userInputService)
				engine.environment.poke(input, "PreferredInput", E.PreferredInput.Touch)
				engine.environment.poke(input, "MouseEnabled", false)
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(3),
						key = key,
						reorderable = true,
						onReorder = function() end,
						columns = {
							{ id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node:FindFirstChild("Body")),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(347, 240)
				)
				local toolbar, header, band =
					node:FindFirstChild("Toolbar"), node:FindFirstChild("Header"), node:FindFirstChild("HeaderBand")
				expect(header.Position.Y.Offset - toolbar.Size.Y.Offset):toBe(8)
				expect(band.Position.Y.Offset):toBe(header.Position.Y.Offset)
				expect(band.Size.X.Scale):toBe(1)
				expect(band.Size.X.Offset):toBe(0)
				stop()
				runtime:dispose()
			end,
		})

		it("holds a custom cell's content in the themed inset a text value uses", {
			id = "native_collections::Compose native collections::holds a custom cell's content in the themed inset a text value uses",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(1),
						key = key,
						columns = {
							{ id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any>,
							{
								id = "mark",
								label = "Mark",
								width = 120,
								render = function(): GuiObject
									return (Facet.host(runtime).Frame :: FrameConstructor)({ Name = "Mark" })
								end,
							} :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node:FindFirstChild("Body")),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(300, 200)
				)
				local mark = node:FindFirstChild("Mark", true)
				expect(mark.Parent.Name):toBe("Inset")
				expect((mark.Parent:HasTag("facet-tablecellinset"))):toBe(true)
				expect((mark.Parent.Parent:HasTag("facet-tablecell"))):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		it("sizes table rows by viewing distance: dense pointer, two-line touch, one large line at ten feet", {
			id = "native_collections::Compose native collections::sizes table rows by viewing distance: dense pointer, two-line touch, one large line at ten feet",
			run = function()
				local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
				local E = engine.types.Enum
				local input: any = assert(ctx.config.userInputService)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "PreferredInput", E.PreferredInput.Gamepad)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "MouseEnabled", false)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "TouchEnabled", false)
				engine.environment.poke(VerifyRoblox.assertInstance(gui), "ViewportDisplaySize", E.DisplaySize.Large)
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(3),
						key = key,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node:FindFirstChild("Body")),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(300, 400)
				)
				local function height()
					return node:FindFirstChild("1", true).Size.Y.Offset
				end
				local function wraps()
					return node:FindFirstChild("1", true):FindFirstChild("Value", true).TextWrapped
				end
				for _, label in node:GetDescendants() do
					if label.Name == "LongestWord" then
						engine.environment.poke(VerifyRoblox.assertInstance(label), "TextFits", true)
					end
				end
				expect((height())):toBe(84)
				expect((wraps())):toBe(false)
				engine.environment.poke(VerifyRoblox.assertInstance(gui), "ViewportDisplaySize", E.DisplaySize.Medium)
				expect((height())):toBe(44)
				engine.environment.poke(input, "PreferredInput", E.PreferredInput.Touch)
				engine.environment.poke(input, "TouchEnabled", true)
				expect((height())):toBe(56)
				expect((wraps())):toBe(true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(input),
					"PreferredInput",
					E.PreferredInput.KeyboardAndMouse
				)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "MouseEnabled", true)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "TouchEnabled", false)
				expect((height())):toBe(44)
				expect((wraps())):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		it("marks each row's selection in the leading gutter while a selectable table is editing", {
			id = "native_collections::Compose native collections::marks each row's selection in the leading gutter while a selectable table is editing",
			run = function()
				local engine, runtime, UI, target = setup()
				local editing, selection = Compose.cell(false), Compose.cell({ [2] = true })
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(3),
						key = key,
						editing = editing,
						selection = selection,
						selectionMode = "multiple" :: "multiple",
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node:FindFirstChild("Body")),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(300, 400)
				)
				local function mark(row)
					return node:FindFirstChild("Body")
						:FindFirstChild(tostring(row), true)
						:FindFirstChild("SelectMark", true)
				end
				expect(mark(1) == nil or mark(1).Visible == false):toBe(true)
				editing:set(true)
				expect(mark(1).Visible):toBe(true)
				expect((mark(1):HasTag("facet-radio-mark"))):toBe(true)
				expect(mark(1).Selectable):toBe(false)
				expect(mark(1):FindFirstChild("Check").Visible):toBe(false)
				expect(mark(2):FindFirstChild("Check").Visible):toBe(true)
				expect(node:FindFirstChild("Header").Position.X.Offset):toBe(44)
				selection:set({ [1] = true })
				expect(mark(1):FindFirstChild("Check").Visible):toBe(true)
				expect(mark(2):FindFirstChild("Check").Visible):toBe(false)
				editing:set(false)
				expect(mark(1).Visible):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		it("resizes and sorts a column from the keyboard or pad and releases the grip to its heading", {
			id = "native_collections::Compose native collections::resizes and sorts a column from the keyboard or pad and releases the grip to its heading",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local sort, widths = Compose.cell<<FixtureCollectionTypes.Sort?>>(nil), Compose.cell({})
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(3),
						key = key,
						sort = sort,
						widths = widths,
						columns = {
							{ id = "label", label = "Name", width = 100, minWidth = 60 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				local column = node:FindFirstChild("Header"):FindFirstChild("label")
				engine.environment.poke(
					VerifyRoblox.assertInstance(column),
					"AbsoluteSize",
					engine.types.Vector2.new(100, 40)
				)
				local heading, grip = column:FindFirstChild("Sort"), column:FindFirstChild("Resize")
				local function press(name: string)
					for _, context in target:GetChildren() do
						if context.Name == "Facet" .. name and context.Enabled then
							context:FindFirstChild(name).Pressed:Fire()
							return true
						end
					end
					return false
				end
				heading.SelectionGained:Fire()
				expect((press("NarrowColumnKey"))):toBe(true)
				expect(widths:peek().label):toBe(92)
				heading.SelectionLost:Fire()
				grip.SelectionGained:Fire()
				expect((press("WidenColumnKey"))):toBe(true)
				expect(widths:peek().label):toBe(100)
				expect((press("SortColumn"))):toBe(true)
				expect((sort:peek())):toEqual({ column = "label", direction = "ascending" :: "ascending" })
				gui.SelectedObject = grip
				expect((press("ReleaseColumn"))):toBe(true)
				expect(gui.SelectedObject):toBe(heading)
				stop()
				runtime:dispose()
			end,
		})

		it("resizes a touch column from its authored minimum without changing the width contract", {
			id = "native_collections::Compose native collections::resizes a touch column from its authored minimum without changing the width contract",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V2 = engine.types.Enum, engine.types.Vector2
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					E.PreferredInput.Touch
				)
				local widths = Compose.cell({} :: { [string]: number })
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(1),
						key = key,
						widths = widths,
						columns = {
							{ id = "label", minWidth = 180 },
							{ id = "kind", width = 100 },
						} :: { FixtureCollectionTypes.TableColumn<any, any> },
					}
					return UI.Table(tableSpec)
				end, target)
				local header = node:FindFirstChild("Header")
				local column = header:FindFirstChild("label")
				engine.environment.poke(VerifyRoblox.assertInstance(column), "AbsoluteSize", V2.new(180, 44))
				local detector = column:FindFirstChild("Resize"):FindFirstChildWhichIsA("UIDragDetector")
				expect(column.ZIndex > header:FindFirstChild("kind").ZIndex):toBe(true)
				detector.DragStart:Fire(V2.new(180, 0))
				detector.DragContinue:Fire(V2.new(190, 0))
				expect(widths:peek().label):toBe(190)
				detector.DragContinue:Fire(V2.new(80, 0))
				expect(widths:peek().label):toBe(180)
				detector.DragEnd:Fire()
				stop()
			end,
		})

		it("leaves the cross-axis D-pad to the engine so focus can leave a rail for the next shelf", {
			id = "native_collections::Compose native collections::leaves the cross-axis D-pad to the engine so focus can leave a rail for the next shelf",
			run = function()
				for _, direction in { "horizontal", "vertical" } :: { "horizontal" | "vertical" } do
					local engine, runtime, UI, target, gui = setup()
					local stop, node: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = records(6),
							key = key,
							itemSize = 40,
							direction = direction :: "horizontal" | "vertical",
							render = function(current): GuiObject
								return button(UI, current)
							end,
						}
						return UI.VirtualList(listSpec)
					end, target)
					engine.environment.poke(
						VerifyRoblox.assertInstance(node),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(200, 200)
					)
					gui.SelectedObject = node:FindFirstChild("1", true):FindFirstChild("Action", true)
					local enabled = {}
					for _, context in target:GetChildren() do
						if context:IsA("InputContext") and context.Enabled then
							enabled[context.Name] = true
						end
					end
					local along = if direction == "horizontal" then "Right" else "Down"
					local across = if direction == "horizontal" then "Down" else "Right"
					expect(
						`{direction} {enabled["FacetCollection" .. along] == true} {enabled["FacetCollection" .. across] == true}`
					):toBe(`{direction} true false`)
					stop()
					runtime:dispose()
				end
			end,
		})

		it("keeps focus on the item by default and on the slot with focusPolicy index", {
			id = "native_collections::Compose native collections::keeps focus on the item by default and on the slot with focusPolicy index",
			run = function()
				for _, policyName in { "key", "index" } do
					local engine, runtime, UI, target = setup()
					local source, focus: FixtureCollectionTypes.FocusControls<any> = Compose.cell(records(6)), {}
					local stop, node: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = source,
							key = key,
							itemSize = 20,
							focus = focus,
							focusPolicy = policyName :: "index" | "key",
							render = function(current): GuiObject
								return button(UI, current)
							end,
						}
						return UI.VirtualList(listSpec)
					end, target)
					engine.environment.poke(
						VerifyRoblox.assertInstance(node),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(200, 120)
					)
					assert(focus.focus)(2)
					local reversed = records(6)
					for index = 1, 3 do
						reversed[index], reversed[7 - index] = reversed[7 - index], reversed[index]
					end
					source:set(reversed)
					expect((assert(focus.current):peek())):toBe(if policyName == "index" then 5 else 2)
					source:set(records(6))
					expect((assert(focus.current):peek())):toBe(2)
					stop()
					runtime:dispose()
				end
				local _, runtime, UI, target = setup()
				expect((pcall(function()
					runtime.mount(function()
						local build: (FixtureCollectionProps.KeyedCollectionSpec<Record, number>, string?) -> ScrollingFrame =
							UI.VirtualList
						return build({ from = {}, render = button, focusPolicy = "slot" } :: any)
					end, target)
				end))):toBe(false)
			end,
		})

		it("picks a row up from a held finger anywhere on it and leaves a moving finger to the scroll", {
			id = "native_collections::Compose native collections::picks a row up from a held finger anywhere on it and leaves a moving finger to the scroll",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V3 = engine.types.Enum, engine.types.Vector3
				local reorders = 0
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(6),
						key = key,
						itemSize = 20,
						reorderable = true,
						onReorder = function()
							reorders += 1
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 120)
				)
				local input: any = assert(ctx.config.userInputService)
				local action = node:FindFirstChild("1", true):FindFirstChild("Action", true)
				local swipe = { UserInputType = E.UserInputType.Touch, Position = V3.new(50, 10, 0) }
				action.InputBegan:Fire(swipe)
				swipe.Position = V3.new(50, 40, 0)
				input.InputChanged:Fire(swipe)
				for _ = 1, 30 do
					engine.heartbeat:Fire(1 / 60)
				end
				expect((node:FindFirstChild("DragImage", true))):toBeNil()
				local hold = { UserInputType = E.UserInputType.Touch, Position = V3.new(50, 10, 0) }
				action.InputBegan:Fire(hold)
				engine.heartbeat:Fire(0.2)
				expect((node:FindFirstChild("DragImage", true))):toBeNil()
				node:FindFirstChild("1", true)
					:FindFirstChild("Reorderable", true).TouchLongPress
					:Fire({ engine.types.Vector2.new(50, 10) }, E.UserInputState.Begin)
				expect(node:FindFirstChild("DragImage", true) ~= nil):toBe(true)
				expect(node.ScrollingEnabled):toBe(false)
				hold.Position = V3.new(50, 70, 0)
				input.InputChanged:Fire(hold)
				hold.UserInputState = E.UserInputState.End
				input.InputEnded:Fire(hold)
				expect(reorders):toBe(1)
				expect(node.ScrollingEnabled):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		it("scrolls a dragged row at the list's edge unless autoscroll is off", {
			id = "native_collections::Compose native collections::scrolls a dragged row at the list's edge unless autoscroll is off",
			run = function()
				for _, autoscroll in { true, false } do
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E, V3 = engine.types.Enum, engine.types.Vector3
					local stop, node: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = records(20),
							key = key,
							itemSize = 20,
							reorderable = true,
							autoscroll = autoscroll,
							onReorder = function() end,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						}
						return UI.VirtualList(listSpec)
					end, target)
					engine.environment.poke(
						VerifyRoblox.assertInstance(node),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(200, 100)
					)
					nativeDrag.press(node:FindFirstChild("1", true):FindFirstChild("Action", true), {
						UserInputType = E.UserInputType.MouseButton1,
						Position = V3.new(50, 10, 0),
					})
					nativeDrag.move(ctx.config.userInputService, {
						UserInputType = E.UserInputType.MouseMovement,
						Position = V3.new(50, 98, 0),
					})
					for _ = 1, 10 do
						engine.heartbeat:Fire(1 / 60)
					end
					expect(node.CanvasPosition.Y > 0):toBe(autoscroll)
					stop()
					runtime:dispose()
				end
			end,
		})

		it("hands edge autoscroll to the enclosing scroller once the list can travel no further", {
			id = "native_collections::Compose native collections::hands edge autoscroll to the enclosing scroller once the list can travel no further",
			run = function()
				local engine, runtime, UI, _, _, ctx = setup({ userInputService = {} })
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				local page = engine.new("ScrollingFrame")
				engine.environment.poke(VerifyRoblox.assertInstance(page), "AbsoluteWindowSize", V2.new(200, 110))
				engine.environment.poke(VerifyRoblox.assertInstance(page), "AbsoluteCanvasSize", V2.new(200, 600))
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(20),
						key = key,
						itemSize = 20,
						reorderable = true,
						onReorder = function() end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, page)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(200, 100))
				nativeDrag.press(node:FindFirstChild("1", true):FindFirstChild("Action", true), {
					UserInputType = E.UserInputType.MouseButton1,
					Position = V3.new(50, 10, 0),
				})
				nativeDrag.move(ctx.config.userInputService, {
					UserInputType = E.UserInputType.MouseMovement,
					Position = V3.new(50, 98, 0),
				})
				engine.heartbeat:Fire(1 / 60)
				expect(node.CanvasPosition.Y > 0):toBe(true)
				expect(page.CanvasPosition.Y):toBe(0)
				node.CanvasPosition = V2.new(0, 300)
				engine.heartbeat:Fire(1 / 60)
				expect(node.CanvasPosition.Y):toBe(300)
				expect(page.CanvasPosition.Y > 0):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		it("scrolls a horizontal rail by a mouse drag and keeps the press from activating a card", {
			id = "native_collections::Compose native collections::scrolls a horizontal rail by a mouse drag and keeps the press from activating a card",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(20),
						key = key,
						direction = "horizontal" :: "horizontal",
						itemSize = 100,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(300, 100))
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.new(300, 100))
				local input: any = assert(ctx.config.userInputService)
				local function mouse(kind, x)
					return { UserInputType = kind, Position = V3.new(x, 50, 0) }
				end
				input.InputBegan:Fire(mouse(E.UserInputType.MouseButton1, 250))
				input.InputChanged:Fire(mouse(E.UserInputType.MouseMovement, 247))
				expect(node.CanvasPosition.X):toBe(0)
				input.InputChanged:Fire(mouse(E.UserInputType.MouseMovement, 150))
				expect(node.CanvasPosition.X):toBe(100)
				expect(node:FindFirstChild("Items").Interactable):toBe(false)
				input.InputChanged:Fire(mouse(E.UserInputType.MouseMovement, 400))
				expect(node.CanvasPosition.X):toBe(0)
				input.InputEnded:Fire(mouse(E.UserInputType.MouseButton1, 400))
				engine.heartbeat:Fire(1 / 60)
				expect(node:FindFirstChild("Items").Interactable):toBe(true)
				input.InputBegan:Fire(mouse(E.UserInputType.MouseButton1, 900))
				input.InputChanged:Fire(mouse(E.UserInputType.MouseMovement, 700))
				expect(node.CanvasPosition.X):toBe(0)
				stop()
				runtime:dispose()
			end,
		})

		it("carries a released mouse drag on a horizontal rail with decaying momentum", {
			id = "native_collections::Compose native collections::carries a released mouse drag on a horizontal rail with decaying momentum",
			run = function()
				local now = 0
				local engine, runtime, UI, target, _, ctx = setup({
					userInputService = {},
					clock = function()
						return now
					end,
				})
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(40),
						key = key,
						direction = "horizontal" :: "horizontal",
						itemSize = 100,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(300, 100))
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.new(300, 100))
				local input: any = assert(ctx.config.userInputService)
				local function mouse(kind, x)
					return { UserInputType = kind, Position = V3.new(x, 50, 0) }
				end
				input.InputBegan:Fire(mouse(E.UserInputType.MouseButton1, 280))
				for x = 260, 180, -20 do
					now += 1 / 60
					input.InputChanged:Fire(mouse(E.UserInputType.MouseMovement, x))
				end
				now += 1 / 120
				input.InputChanged:Fire(mouse(E.UserInputType.MouseMovement, 180))
				local released = node.CanvasPosition.X
				expect(released):toBe(100)
				input.InputEnded:Fire(mouse(E.UserInputType.MouseButton1, 180))
				local previous, step = released, 0
				for _ = 1, 20 do
					now += 1 / 60
					engine.heartbeat:Fire(1 / 60)
					local at = node.CanvasPosition.X
					expect(at >= previous):toBe(true)
					step, previous = at - previous, at
				end
				expect(previous > released + 100):toBe(true)
				for _ = 1, 600 do
					now += 1 / 60
					engine.heartbeat:Fire(1 / 60)
				end
				local rest = node.CanvasPosition.X
				now += 1 / 60
				engine.heartbeat:Fire(1 / 60)
				expect(node.CanvasPosition.X):toBe(rest)
				expect(step > 0):toBe(true)
				input.InputBegan:Fire(mouse(E.UserInputType.MouseButton1, 200))
				input.InputEnded:Fire(mouse(E.UserInputType.MouseButton1, 200))
				now += 1 / 60
				engine.heartbeat:Fire(1 / 60)
				expect(node.CanvasPosition.X):toBe(rest)
				stop()
				runtime:dispose()
			end,
		})

		it("places a dragged row and its image in layout units under a scaled ancestor, as in a ten-foot preview", {
			id = "native_collections::Compose native collections::places a dragged row and its image in layout units under a scaled ancestor, as in a ten-foot preview",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				local moved
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(20),
						key = key,
						itemSize = 20,
						reorderable = true,
						onReorder = function(keys: { number }, slot: number)
							moved = `{table.concat(keys, ",")}@{slot}`
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node:FindFirstChild("LayoutUnit")),
					"AbsoluteSize",
					V2.new(2, 2)
				)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(400, 400))
				local input: any = assert(ctx.config.userInputService)
				nativeDrag.press(node:FindFirstChild("1", true):FindFirstChild("Action", true), {
					UserInputType = E.UserInputType.MouseButton1,
					Position = V3.new(50, 20, 0),
				})

				nativeDrag.move(input, { UserInputType = E.UserInputType.MouseMovement, Position = V3.new(50, 130, 0) })
				expect(node:FindFirstChild("DragImage", true).Position.Y.Offset):toBe(65 - 10)
				nativeDrag.finish(
					input,
					{ UserInputType = E.UserInputType.MouseButton1, Position = V3.new(50, 130, 0) }
				)
				expect(moved):toBe("1@2")
				stop()
				runtime:dispose()
			end,
		})

		it("keeps grid drag cards at cell size and picks insertion slots across both axes", {
			id = "native_collections::Compose native collections::keeps grid drag cards at cell size and picks insertion slots across both axes",
			run = function()
				for _, horizontal in { false, true } do
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
					local requests = {}
					local stop, node: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> =
							{
								from = records(6),
								key = key,
								columns = 3,
								itemSize = 80,
								gap = 10,
								direction = if horizontal
									then "horizontal" :: "horizontal"
									else "vertical" :: "vertical",
								selection = Compose.cell({ [1] = true, [4] = true }),
								selectionMode = "multiple" :: "multiple",
								reorderable = true,
								onReorder = function(keys: { number }, slot: number)
									table.insert(requests, { keys = keys, slot = slot })
								end,
								render = function(current): GuiObject
									return button(UI, current)
								end,
							}
						return UI.VirtualGrid(listSpec)
					end, target)
					engine.environment.poke(
						VerifyRoblox.assertInstance(node),
						"AbsoluteSize",
						if horizontal then V2.new(300, 330) else V2.new(330, 300)
					)
					engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", node.AbsoluteSize)
					local row = node:FindFirstChild("1", true)
					engine.environment.poke(
						VerifyRoblox.assertInstance(row:FindFirstChild("Reorderable", true)),
						"AbsoluteSize",
						if horizontal then V2.new(80, 100) else V2.new(100, 80)
					)
					local press = { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(20, 20, 0) }
					nativeDrag.press(row:FindFirstChild("RowHit", true), press)
					nativeDrag.move(ctx.config.userInputService, {
						UserInputType = E.UserInputType.MouseMovement,
						Position = if horizontal then V3.new(20, 300, 0) else V3.new(300, 20, 0),
					})
					local image = node:FindFirstChild("DragImage", true)
					expect(image.Size):toBe(
						if horizontal
							then engine.types.UDim2.fromOffset(86, 106)
							else engine.types.UDim2.fromOffset(106, 86)
					)
					local labels: { string } = {}
					for _, layer in image:GetChildren() do
						if layer.Name == "Reorderable" then
							local label = layer:FindFirstChild("Action", true):GetAttribute("label")
							assert(type(label) == "string")
							table.insert(labels, label)
							expect(layer.Size):toBe(
								if horizontal
									then engine.types.UDim2.fromOffset(80, 100)
									else engine.types.UDim2.fromOffset(100, 80)
							)
						end
					end
					table.sort(labels)
					expect(labels):toEqual({ "1", "4" })
					local marker = node:FindFirstChild("DropLine", true)
					expect(marker.Size):toBe(
						if horizontal
							then engine.types.UDim2.fromOffset(80, 2)
							else engine.types.UDim2.fromOffset(2, 80)
					)
					nativeDrag.finish(ctx.config.userInputService, press)
					expect(requests):toEqual({ { keys = { 1, 4 }, slot = 2 } })
					stop()
					runtime:dispose()
				end
			end,
		})

		it("drags an image of the row, stacked two or three deep for a selection, from a press anywhere on it", {
			id = "native_collections::Compose native collections::drags an image of the row, stacked two or three deep for a selection, from a press anywhere on it",
			run = function()
				for _, count in { 1, 2, 4 } do
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E, V3 = engine.types.Enum, engine.types.Vector3
					local chosen = {}
					for index = 1, count do
						chosen[index] = true
					end
					local stop, node: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = records(6),
							key = key,
							itemSize = 20,
							selection = Compose.cell(chosen),
							selectionMode = "multiple" :: "multiple",
							reorderable = true,
							onReorder = function() end,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						}
						return UI.VirtualList(listSpec)
					end, target)
					engine.environment.poke(
						VerifyRoblox.assertInstance(node),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(200, 120)
					)
					local row = node:FindFirstChild("1", true)
					local reorderable = row:FindFirstChild("Reorderable", true)
					engine.environment.poke(
						VerifyRoblox.assertInstance(reorderable),
						"AbsoluteSize",
						engine.types.Vector2.new(200, 20)
					)
					local press = { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(50, 10, 0) }
					nativeDrag.press(row:FindFirstChild("Action", true), press)
					nativeDrag.move(ctx.config.userInputService, {
						UserInputType = E.UserInputType.MouseMovement,
						Position = V3.new(50, 40, 0),
					})
					local image = node:FindFirstChild("DragImage", true)
					expect(image ~= nil):toBe(true)
					expect(image.Interactable):toBe(false)
					local layers = {}
					for _, child in image:GetChildren() do
						if child.Name == "Reorderable" then
							table.insert(layers, child.Position.X.Offset)
						end
					end
					table.sort(layers)
					expect((table.concat(layers, ","))):toBe(
						if count == 1 then "0" elseif count == 2 then "0,6" else "0,6,12"
					)
					expect(reorderable.Interactable):toBe(true)
					expect(image:FindFirstChild("DragLabel").Visible):toBe(count > 1)
					local ghost = target:FindFirstChild("DragGhost")
					local stack = math.min(count - 1, 2) * 6
					expect(math.abs(ghost.AnchorPoint.X * ghost.Size.X.Offset - (200 - stack) / 4) < 0.001):toBe(true)
					expect(math.abs(ghost.AnchorPoint.Y * ghost.Size.Y.Offset - 10) < 0.001):toBe(true)
					expect(ghost.Position):toBe(engine.types.UDim2.fromOffset(50, 40))
					stop()
					runtime:dispose()
				end
			end,
		})

		it("draws icon actions at a fixed width and arms the first action past a 0.6 full swipe", {
			id = "native_collections::Compose native collections::draws icon actions at a fixed width and arms the first action past a 0.6 full swipe",
			run = function()
				local engine, runtime, UI, target = setup()
				local deleted = 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions {
						fullSwipe = true,
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						trailing = {
							{
								id = "delete",
								label = "Delete",
								icon = "trash",
								role = "destructive" :: "destructive",
								onActivate = function()
									deleted += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
							{ id = "flag", label = "Flag", icon = "flag" } :: FixtureCollectionTypes.RowAction,
						},
					}
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 40)
				)
				local tray = node:FindFirstChild("trailing")
				local delete, flag = tray:FindFirstChild("delete"), tray:FindFirstChild("flag")
				expect((delete:GetAttribute("label"))):toBe("Delete")
				expect(delete:FindFirstChild("LeadingIcon", true) ~= nil):toBe(true)
				local caption = delete:FindFirstChild("Title", true)
				expect(caption == nil or caption.Visible == false or caption.Text == ""):toBe(true)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(250, 20))
				detector.DragContinue:Fire(engine.types.Vector2.new(200, 20))
				expect(tray.Size.X.Offset):toBe(50)
				expect(`{delete.Size.X.Scale} {delete.Size.X.Offset}`):toBe("0 64")
				detector.DragContinue:Fire(engine.types.Vector2.new(170, 20))
				expect(`{delete.Size.X.Scale} {delete.Size.X.Offset}`):toBe("0 64")
				detector.DragContinue:Fire(engine.types.Vector2.new(100, 20))
				expect(tray.Size.X.Offset):toBe(150)
				expect(delete.Size.X.Offset + flag.Size.X.Offset):toBe(150)
				expect(flag.Size.X.Offset):toBe(64)
				expect(flag.Visible):toBe(true)
				detector.DragContinue:Fire(engine.types.Vector2.new(65, 20))
				expect(delete.Size):toEqual(engine.types.UDim2.fromScale(1, 1))
				expect(flag.Visible):toBe(false)
				expect(tray.Size.X.Offset):toBe(185)
				detector.DragEnd:Fire()
				expect(deleted):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		it("uses native drag to reveal and invoke row actions with cancellation and coordination", {
			id = "native_collections::Compose native collections::uses native drag to reveal and invoke row actions with cancellation and coordination",
			run = function()
				local engine, runtime, UI, target = setup()
				local open: FixtureComposeTypes.Value<("leading" | "trailing")?>, coordinator =
					Compose.cell(nil :: ("leading" | "trailing")?), Compose.cell(nil :: {}?)
				local invoked = 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions {
						open = open,
						coordinator = coordinator,
						fullSwipe = true,
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						trailing = {
							{
								id = "Delete",
								label = "Delete",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					}
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 40)
				)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(200, 20))
				detector.DragContinue:Fire(engine.types.Vector2.new(120, 20))
				detector.DragEnd:Fire()
				expect((open:peek())):toBe("trailing")
				coordinator:set({})
				expect((open:peek())):toBeNil()
				detector.DragStart:Fire(engine.types.Vector2.new(250, 20))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 20))
				detector.DragEnd:Fire()
				expect(invoked):toBe(1)
				expect((open:peek())):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		it("swipes a Button row from a grip over the content and forwards a tap to the Button", {
			id = "native_collections::Compose native collections::swipes a Button row from a grip over the content and forwards a tap to the Button",
			run = function()
				local engine, runtime, UI, target = setup()
				local open: FixtureComposeTypes.Value<("leading" | "trailing")?>, activated =
					Compose.cell(nil :: ("leading" | "trailing")?), 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions {
						open = open,
						content = UI.Button "Mail" {
							label = "Mail",
							onActivate = function()
								activated += 1
							end,
						} :: GuiObject,
						trailing = {
							{ id = "Delete", label = "Delete", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
						},
					}
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 40)
				)
				local content = node:FindFirstChild("Content")
				local grip = content:FindFirstChild("SwipeGrip")
				local mail = content:FindFirstChild("Mail", true)
				expect((grip:IsA("GuiButton"))):toBe(true)
				expect(grip.Selectable):toBe(false)
				expect(grip.Visible):toBe(true)
				expect(grip.BackgroundTransparency):toBe(1)
				expect(grip.Size):toEqual(engine.types.UDim2.fromScale(1, 1))
				expect(grip.ZIndex > mail.ZIndex):toBe(true)
				expect(mail.Selectable):toBe(true)
				local detector = grip:FindFirstChildWhichIsA("UIDragDetector")
				expect((node:FindFirstChildWhichIsA("UIDragDetector"))):toBeNil()
				detector.DragStart:Fire(engine.types.Vector2.new(150, 20))
				detector.DragContinue:Fire(engine.types.Vector2.new(153, 22))
				detector.DragEnd:Fire()
				expect(activated):toBe(1)
				expect((open:peek())):toBeNil()
				detector.DragStart:Fire(engine.types.Vector2.new(200, 20))
				detector.DragContinue:Fire(engine.types.Vector2.new(120, 20))
				detector.DragEnd:Fire()
				expect((open:peek())):toBe("trailing")
				expect(activated):toBe(1)
				open:set(nil)
				detector.DragStart:Fire(engine.types.Vector2.new(150, 20))
				detector.DragContinue:Fire(engine.types.Vector2.new(150, 60))
				detector.DragEnd:Fire()
				expect(activated):toBe(1)
				expect((open:peek())):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		it("hands touch swipes to the native pan gesture so a vertical pan stays with the scroller", {
			id = "native_collections::Compose native collections::hands touch swipes to the native pan gesture so a vertical pan stays with the scroller",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E = engine.types.Enum
				local V2 = engine.types.Vector2
				local open: FixtureComposeTypes.Value<("leading" | "trailing")?>, activated =
					Compose.cell(nil :: ("leading" | "trailing")?), 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions {
						open = open,
						content = UI.Button "Mail" {
							label = "Mail",
							onActivate = function()
								activated += 1
							end,
						} :: GuiObject,
						trailing = {
							{ id = "Delete", label = "Delete", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
						},
					}
				end, target)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.new(300, 40))
				local grip = node:FindFirstChild("SwipeGrip", true)
				local detector = grip:FindFirstChildWhichIsA("UIDragDetector")
				expect(detector.Enabled):toBe(true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					E.PreferredInput.Touch
				)
				expect(detector.Enabled):toBe(false)
				local function pan(to: any, state: any)
					grip.TouchPan:Fire({ to }, to - V2.new(200, 20), V2.zero, state)
				end
				pan(V2.new(190, 20), E.UserInputState.Begin)
				pan(V2.new(120, 20), E.UserInputState.Change)
				pan(V2.new(120, 20), E.UserInputState.End)
				grip.Activated:Fire()
				expect((open:peek())):toBe("trailing")
				expect(activated):toBe(0)
				open:set(nil)
				pan(V2.new(200, 10), E.UserInputState.Begin)
				pan(V2.new(200, -60), E.UserInputState.Change)
				pan(V2.new(200, -60), E.UserInputState.End)
				grip.Activated:Fire()
				expect((open:peek())):toBeNil()
				expect(activated):toBe(0)
				engine.heartbeat:Fire(1 / 60)
				grip.Activated:Fire()
				expect(activated):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		it("commits a touch row action from the final pan distance or native release velocity", {
			id = "native_collections::Compose native collections::commits a touch row action from the final pan distance or native release velocity",
			run = function()
				local samples: { { distance: number, speed: number, expected: number, fullSwipe: boolean?, cancel: boolean? } } =
					{
						{ distance = -220, speed = 0, expected = 1 },
						{ distance = -80, speed = -1400, expected = 1 },
						{ distance = -80, speed = 0, expected = 0 },
						{ distance = -80, speed = -1400, expected = 0, fullSwipe = false },
						{ distance = -220, speed = 0, expected = 0, cancel = true },
					}
				for _, sample in samples do
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E, V2 = engine.types.Enum, engine.types.Vector2
					engine.environment.poke(
						VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
						"PreferredInput",
						E.PreferredInput.Touch
					)
					local open: FixtureComposeTypes.Value<("leading" | "trailing")?>, invoked =
						Compose.cell(nil :: ("leading" | "trailing")?), 0
					local stop, node: any = runtime.mount(function()
						return UI.RowActions {
							open = open,
							fullSwipe = sample.fullSwipe,
							content = UI.Button { label = "Track" } :: GuiObject,
							trailing = {
								{
									id = "remove",
									label = "Remove",
									role = "destructive" :: "destructive",
									onActivate = function()
										invoked += 1
									end,
								} :: FixtureCollectionTypes.RowAction,
							},
						}
					end, target)
					engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", V2.new(300, 44))
					local grip = node:FindFirstChild("SwipeGrip", true)
					grip.TouchPan:Fire({ V2.new(280, 20) }, V2.new(-20, 0), V2.zero, E.UserInputState.Begin)
					grip.TouchPan:Fire({ V2.new(220, 20) }, V2.new(-80, 0), V2.zero, E.UserInputState.Change)
					grip.TouchPan:Fire(
						{},
						V2.new(sample.distance, 0),
						V2.new(sample.speed, 0),
						if sample.cancel then E.UserInputState.Cancel else E.UserInputState.End
					)
					expect(invoked):toBe(sample.expected)
					expect((open:peek())):toBe(if sample.expected == 1 or sample.cancel then nil else "trailing")
					grip.TouchPan:Fire({}, V2.new(sample.distance, 0), V2.new(sample.speed, 0), E.UserInputState.End)
					expect(invoked):toBe(sample.expected)
					stop()
					runtime:dispose()
				end
			end,
		})

		it("a horizontal touch pan holds Facet's enclosing scrollers until release; a vertical one leaves them", {
			id = "native_collections::Compose native collections::a horizontal touch pan holds Facet's enclosing scrollers until release; a vertical one leaves them",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local Host = Facet.host(runtime)
				local E = engine.types.Enum
				local V2 = engine.types.Vector2
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					E.PreferredInput.Touch
				)
				local open: FixtureComposeTypes.Value<("leading" | "trailing")?> =
					Compose.cell(nil :: ("leading" | "trailing")?)
				local stop, page: any = runtime.mount(function()
					return Host.ScrollingFrame "Page" {
						Host.ScrollingFrame "Body" {
							UI.RowActions {
								Name = "Row",
								open = open,
								content = UI.Button "Mail" { label = "Mail" } :: GuiObject,
								trailing = {
									{ id = "Delete", label = "Delete", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
								},
							},
						},
					}
				end, target)
				local scrollLock = require("../src/ui/scroll_lock")
				local body = page:FindFirstChild("Body")
				scrollLock.own(body)
				local row = body:FindFirstChild("Row")
				engine.environment.poke(VerifyRoblox.assertInstance(row), "AbsoluteSize", V2.new(300, 40))
				local grip = row:FindFirstChild("SwipeGrip", true)
				local function pan(to: any, from: any, state: any)
					grip.TouchPan:Fire({ to }, to - from, V2.zero, state)
				end
				local function held(): string
					return `{page.ScrollingEnabled} {body.ScrollingEnabled}`
				end
				pan(V2.new(186, 22), V2.new(200, 20), E.UserInputState.Begin)
				expect((held())):toBe("true false")
				pan(V2.new(120, 24), V2.new(200, 20), E.UserInputState.Change)
				pan(V2.new(120, 24), V2.new(200, 20), E.UserInputState.End)
				expect((held())):toBe("true true")
				expect((open:peek())):toBe("trailing")
				local sheet = engine.new("Frame")
				sheet.Parent = target
				pan(V2.new(186, 22), V2.new(200, 20), E.UserInputState.Begin)
				scrollLock.acquire(target, sheet)
				pan(V2.new(186, 22), V2.new(200, 20), E.UserInputState.End)
				expect((held())):toBe("false false")
				scrollLock.release(target, sheet)
				expect((held())):toBe("true true")
				open:set(nil)
				engine.heartbeat:Fire(1 / 60)
				pan(V2.new(202, 6), V2.new(200, 20), E.UserInputState.Begin)
				pan(V2.new(204, -60), V2.new(200, 20), E.UserInputState.Change)
				expect((held())):toBe("true true")
				pan(V2.new(204, -60), V2.new(200, 20), E.UserInputState.End)
				expect((open:peek())):toBeNil()
				pan(V2.new(186, 20), V2.new(200, 20), E.UserInputState.Begin)
				pan(V2.new(186, 20), V2.new(200, 20), E.UserInputState.Cancel)
				expect((held())):toBe("true true")
				stop()
				runtime:dispose()
			end,
		})

		it("selects ranges across unmounted rows while honoring row capability policies", {
			id = "native_collections::Compose native collections::selects ranges across unmounted rows while honoring row capability policies",
			run = function()
				local shifted = false
				local engine, runtime, UI, target = setup({
					userInputService = {
						IsKeyDown = function()
							return shifted
						end,
						GetFocusedTextBox = function()
							return nil
						end,
					},
				})
				local selected = Compose.cell({})
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(100),
						key = key,
						selection = selected,
						selectionMode = "multiple" :: "multiple",
						itemSize = 20,
						overscan = 0,
						selectable = function(item)
							return item.id ~= 4
						end,
						disabled = function(item)
							return item.id == 5
						end,
						columns = { { id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any> },
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 60)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				body:FindFirstChild("2", true):FindFirstChild("RowHit", true).Activated:Fire()
				shifted = true
				body.CanvasPosition = engine.types.Vector2.new(0, 180)
				body:FindFirstChild("10", true):FindFirstChild("RowHit", true).Activated:Fire()
				for index = 2, 10 do
					expect(selected:peek()[index] == true):toBe(index ~= 4 and index ~= 5)
				end
				expect(selected:peek()[1]):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		it("reorders selected blocks with native drag and cancels stale or keyboard moves", {
			id = "native_collections::Compose native collections::reorders selected blocks with native drag and cancels stale or keyboard moves",
			run = function()
				local engine, runtime, UI, target = setup()
				local source, selected = Compose.cell(records(5)), Compose.cell({ [1] = true, [3] = true })
				local requests: { { keys: { number }, slot: number } } = {}
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = source,
						key = key,
						selection = selected,
						selectionMode = "multiple" :: "multiple",
						itemSize = 20,
						reorderable = true,
						movable = function(item)
							return item.id ~= 4
						end,
						onReorder = function(keys: { number }, slot: number)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local handle = body:FindFirstChild("3", true):FindFirstChild("Move", true)
				local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(10, 40))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 35))
				expect(node:FindFirstChild("DropLine", true).Position.Y.Offset):toBe(100)
				expect(node:FindFirstChild("DragLabel", true).Text):toBe("2 selected")
				detector.DragEnd:Fire()
				expect(requests):toEqual({ { keys = { 1, 3 }, slot = 1 } })
				expect(body:FindFirstChild("4", true):FindFirstChild("Move", true).Interactable):toBe(false)
				detector.DragStart:Fire(engine.types.Vector2.new(10, 40))
				source:set(records(5))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 100))
				detector.DragEnd:Fire()
				expect(#requests):toBe(1)
				handle.SelectionGained:Fire()
				handle.Activated:Fire()
				expect(handle:FindFirstChild("ReorderIcon").Image):toBe("rbxassetid://108245103349446")
				local cancel
				for _, contextNode in target:GetChildren() do
					if contextNode.Name == "FacetReorderCancel" and contextNode.Enabled then
						cancel = contextNode:FindFirstChild("ReorderCancel")
					end
				end
				assert(cancel)
				cancel.Pressed:Fire()
				expect(handle.Text):toBe("")
				expect(handle:FindFirstChild("ReorderIcon").Image):toBe("rbxassetid://119066409501208")
				expect(handle:FindFirstChild("ReorderIcon").Position):toBe(engine.types.UDim2.fromScale(0.5, 0.5))
				expect(#requests):toBe(1)
				handle.Activated:Fire()
				for _, contextNode in target:GetChildren() do
					if contextNode.Name == "FacetReorderDown" and contextNode.Enabled then
						contextNode:FindFirstChild("ReorderDown").Pressed:Fire()
					end
				end
				handle.Activated:Fire()
				expect(requests[2]):toEqual({ keys = { 1, 3 }, slot = 1 })
				expect((node:FindFirstChild("DropLine", true))):toBeNil()
				local stationary = body:FindFirstChild("2", true):FindFirstChild("Move", true)
				stationary.Activated:Fire()
				stationary.Activated:Fire()
				expect(#requests):toBe(2)
				stop()
				runtime:dispose()
			end,
		})

		it("keeps touch handle drags active with a focused handle and moves a non-adjacent selection", {
			id = "native_collections::Compose native collections::keeps touch handle drags active with a focused handle and moves a non-adjacent selection",
			run = function()
				local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					E.PreferredInput.Touch
				)
				local selected, requests = Compose.cell({ [1] = true, [3] = true }), {}
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(5),
						key = key,
						itemSize = 20,
						selection = selected,
						selectionMode = "multiple" :: "multiple",
						editing = true,
						reorderable = true,
						onReorder = function(keys, slot)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						columns = { { id = "label", width = 100 } },
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(VerifyRoblox.assertInstance(body), "AbsoluteWindowSize", V2.new(200, 100))
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				body.ScrollingEnabled = true
				local handle = body:FindFirstChild("3", true):FindFirstChild("Move", true)
				gui.SelectedObject = handle
				local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
				expect(detector.Enabled):toBe(true)
				local input = {
					UserInputType = E.UserInputType.Touch,
					UserInputState = E.UserInputState.Begin,
					Position = V3.new(10, 40, 0),
				}
				detector.DragStart:Fire(V2.new(10, 40))
				handle.InputBegan:Fire(input)
				expect(body.ScrollingEnabled):toBe(false)
				detector.DragContinue:Fire(V2.new(10, 35))
				detector.DragEnd:Fire()
				expect(requests):toEqual({ { keys = { 1, 3 }, slot = 1 } })
				expect(body.ScrollingEnabled):toBe(true)
				expect((selected:peek())):toEqual({ [1] = true, [3] = true })
				stop()
			end,
		})

		it("arms a move on a detector tap and commits it on the next tap", {
			id = "native_collections::Compose native collections::arms a move on a detector tap and commits it on the next tap",
			run = function()
				local engine, runtime, UI, target = setup()
				local source = Compose.cell(records(5))
				local requests = {}
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = source,
						key = key,
						itemSize = 20,
						reorderable = true,
						onReorder = function(keys: { number }, slot: number)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local handle = body:FindFirstChild("2", true):FindFirstChild("Move", true)
				local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
				local reorderable = handle.Parent
				detector.DragStart:Fire(engine.types.Vector2.new(10, 30))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 31))
				detector.DragEnd:Fire()
				handle.Activated:Fire({ UserInputType = engine.types.Enum.UserInputType.MouseButton1 })
				expect((reorderable:GetAttribute("FacetDragging"))):toBe(true)
				expect(#requests):toBe(0)
				for _, contextNode in target:GetChildren() do
					if contextNode.Name == "FacetReorderDown" and contextNode.Enabled then
						contextNode:FindFirstChild("ReorderDown").Pressed:Fire()
					end
				end
				detector.DragStart:Fire(engine.types.Vector2.new(10, 30))
				detector.DragEnd:Fire()
				handle.Activated:Fire({ UserInputType = engine.types.Enum.UserInputType.MouseButton1 })
				expect((reorderable:GetAttribute("FacetDragging"))):toBe(false)
				expect(requests):toEqual({ { keys = { 2 }, slot = 2 } })
				stop()
				runtime:dispose()
			end,
		})

		it("hides departing row content before collapsing its layout extent", {
			id = "native_collections::Compose native collections::hides departing row content before collapsing its layout extent",
			run = function()
				local edges: { FixtureCollectionTypes.RowEdge } = { "leading", "trailing" }
				for _, edge in edges do
					local engine, runtime, UI, target, _, ctx = setup({ motionLevel = "normal" })
					local invoked = 0
					local open = Compose.cell<<FixtureCollectionTypes.RowEdge?>>(edge)
					local action: FixtureCollectionTypes.RowAction = {
						id = "Delete",
						label = "Delete",
						role = "destructive",
						onActivate = function()
							invoked += 1
						end,
					}
					local stop, node = runtime.mount(function()
						return UI.RowActions {
							open = open,
							Size = engine.types.UDim2.fromOffset(300, 40),
							content = UI.Button "Body" { label = "Row" } :: GuiObject,
							leading = if edge == "leading" then { action } else nil,
							trailing = if edge == "trailing" then { action } else nil,
						}
					end, target)
					local root = (node :: unknown) :: Frame
					local geometry = (root :: unknown) :: { AbsoluteSize: Vector2 }
					engine.environment.poke(
						VerifyRoblox.assertInstance(geometry),
						"AbsoluteSize",
						engine.types.Vector2.new(300, 40)
					)
					local content = assert(root:FindFirstChild("Content")) :: Frame
					local button = assert(root:FindFirstChild("Delete", true))
					local signal = (button :: unknown) :: { Activated: { Fire: (unknown) -> () } }
					local duration = ctx.metric("motion.durations.rowDeparture")
					engine.heartbeat:Fire(duration)
					signal.Activated:Fire()
					engine.heartbeat:Fire(duration * 0.6)
					expect(content.Visible):toBe(true)
					expect(root.Size.Y.Offset):toBe(40)
					engine.heartbeat:Fire(duration * 0.15)
					expect(root.Size.Y.Offset < 40):toBe(true)
					expect(content.Visible):toBe(false)
					expect(invoked):toBe(0)
					engine.heartbeat:Fire(duration)
					expect(invoked):toBe(1)
					open:set((edge :: unknown) :: FixtureCollectionTypes.RowEdge)
					expect(content.Visible):toBe(true)
					stop()
					runtime:dispose()
				end
			end,
		})

		it("commits a destructive action once after Compose departure and cancels on disposal", {
			id = "native_collections::Compose native collections::commits a destructive action once after Compose departure and cancels on disposal",
			run = function()
				local engine, runtime, UI, target = setup({ motionLevel = "normal" })
				local invoked = 0
				local function mount()
					return runtime.mount(function()
						return UI.RowActions {
							open = Compose.cell("trailing" :: "leading" | "trailing" | nil) :: FixtureComposeTypes.Value<FixtureCollectionTypes.RowEdge?>,
							content = UI.Button "Action" { label = "Row" } :: GuiObject,
							trailing = {
								{
									id = "Delete",
									label = "Delete",
									role = "destructive" :: "destructive",
									onActivate = function()
										invoked += 1
									end,
								} :: FixtureCollectionTypes.RowAction,
							},
						}
					end, target)
				end
				local stop, node: any = mount()
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 40)
				)
				engine.heartbeat:Fire(0.3)
				local action = node:FindFirstChild("Delete", true)
				action.Activated:Fire()
				action.Activated:Fire()
				expect(invoked):toBe(0)
				engine.heartbeat:Fire(0.3)
				expect(invoked):toBe(1)
				expect(node.Size.Y.Offset):toBe(0)
				action.Activated:Fire()
				expect(invoked):toBe(1)
				stop()
				local cancel, pending: any = mount()
				engine.environment.poke(
					VerifyRoblox.assertInstance(pending),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 40)
				)
				engine.heartbeat:Fire(0.3)
				pending:FindFirstChild("Delete", true).Activated:Fire()
				cancel()
				engine.heartbeat:Fire(1)
				expect(invoked):toBe(1)
				runtime:dispose()
			end,
		})

		it("never commits or opens a full swipe on an unmeasured row", {
			id = "native_collections::Compose native collections::never commits or opens a full swipe on an unmeasured row",
			run = function()
				local engine, runtime, UI, target = setup()
				local invoked, open: FixtureComposeTypes.Value<("leading" | "trailing")?> =
					0, Compose.cell(nil :: ("leading" | "trailing")?)
				local stop, node: any = runtime.mount(function()
					return UI.RowActions {
						open = open,
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						trailing = {
							{
								id = "Archive",
								label = "Archive",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					}
				end, target)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(100, 0))
				detector.DragContinue:Fire(engine.types.Vector2.new(85, 0))
				detector.DragEnd:Fire()
				expect(invoked):toBe(0)
				expect((open:peek())):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		it("restores a kept row after a destructive action so it can commit again", {
			id = "native_collections::Compose native collections::restores a kept row after a destructive action so it can commit again",
			run = function()
				local engine, runtime, UI, target = setup()
				local invoked, open: FixtureComposeTypes.Value<("leading" | "trailing")?> =
					0, Compose.cell("trailing" :: ("leading" | "trailing")?)
				local stop, node: any = runtime.mount(function()
					return UI.RowActions {
						open = open,
						reducedMotion = true,
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						trailing = {
							{
								id = "Delete",
								label = "Delete",
								role = "destructive" :: "destructive",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					}
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 40)
				)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				node:FindFirstChild("Delete", true).Activated:Fire()
				expect(invoked):toBe(1)
				expect(node.Size.Y.Offset):toBe(0)
				expect(detector.Enabled):toBe(false)
				open:set("trailing")
				expect(node.Size.Y.Offset):toBe(44)
				expect(detector.Enabled):toBe(true)
				expect(node:FindFirstChild("trailing").Visible):toBe(true)
				node:FindFirstChild("Delete", true).Activated:Fire()
				expect(invoked):toBe(2)
				stop()
				runtime:dispose()
			end,
		})

		it("respects edge full-swipe policy, edit affordances and focused destructive input", {
			id = "native_collections::Compose native collections::respects edge full-swipe policy, edit affordances and focused destructive input",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local editing, open: FixtureComposeTypes.Value<("leading" | "trailing")?> =
					Compose.cell(false), Compose.cell(nil :: ("leading" | "trailing")?)
				local invoked = 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions {
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						editing = editing,
						open = open,
						fullSwipe = { trailing = false },
						trailing = {
							{
								id = "Erase",
								label = "Delete",
								role = "destructive" :: "destructive",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					}
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 40)
				)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(280, 0))
				detector.DragContinue:Fire(engine.types.Vector2.new(0, 0))
				detector.DragEnd:Fire()
				expect(invoked):toBe(0)
				expect((open:peek())):toBe("trailing")
				open:set(nil)
				expect((node:FindFirstChild("Delete"))):toBeNil()
				editing:set(true)
				expect(detector.Enabled):toBe(false)
				editing:set(false)
				expect(detector.Enabled):toBe(true)
				editing:set(true)
				expect(node:FindFirstChild("Delete") ~= nil):toBe(true)
				gui.SelectedObject = node:FindFirstChild("Action", true)
				local contextNode = target:FindFirstChild("FacetRowActionsDelete")
				expect(contextNode.Enabled):toBe(true)
				contextNode:FindFirstChild("RowActionsDelete").Pressed:Fire()
				expect(invoked):toBe(1)
				node:FindFirstChild("Delete").Activated:Fire()
				expect(invoked):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		it("uses the shared native menu for all actions and restores focus after cancellation", {
			id = "native_collections::Compose native collections::uses the shared native menu for all actions and restores focus after cancellation",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local invoked = 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions {
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						leading = {
							{
								id = "Read",
								label = "Read",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
						trailing = {
							{
								id = "Save",
								label = "Save",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					}
				end, target)
				local original = node:FindFirstChild("Action", true)
				gui.SelectedObject = original
				node.InputBegan:Fire({
					UserInputType = engine.types.Enum.UserInputType.MouseButton2,
					Position = engine.types.Vector3.new(50, 50, 0),
				})
				local panel = target:FindFirstChild("MenuPanel", true)
				expect(panel ~= nil):toBe(true)
				expect(panel.SelectionBehaviorDown):toBe(engine.types.Enum.SelectionBehavior.Stop)
				expect(target:FindFirstChild("leading:Read", true) ~= nil):toBe(true)
				expect(target:FindFirstChild("trailing:Save", true) ~= nil):toBe(true)
				target:FindFirstChild("FacetModalBack"):FindFirstChild("ModalBack").Pressed:Fire()
				expect((target:FindFirstChild("MenuPanel", true))):toBeNil()
				expect(gui.SelectedObject):toBe(original)
				expect(invoked):toBe(0)
				node.InputBegan:Fire({
					UserInputType = engine.types.Enum.UserInputType.MouseButton2,
					Position = engine.types.Vector3.new(70, 80, 0),
				})
				target:FindFirstChild("leading:Read", true).Activated:Fire()
				expect(invoked):toBe(1)
				expect((target:FindFirstChild("MenuPanel", true))):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		it("lets domain callbacks reject table selection, sorting and resize requests", {
			id = "native_collections::Compose native collections::lets domain callbacks reject table selection, sorting and resize requests",
			run = function()
				local engine, runtime, UI, target = setup()
				local selection, sort, widths =
					Compose.cell({}), Compose.cell<<FixtureCollectionTypes.Sort?>>(nil), Compose.cell({})
				local requests = 0
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(5),
						key = key,
						selection = selection,
						sort = sort,
						widths = widths,
						onSelectionChange = function()
							requests += 1
						end,
						onSortChange = function()
							requests += 1
						end,
						onWidthsChange = function()
							requests += 1
						end,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				body:FindFirstChild("1", true):FindFirstChild("RowHit", true).Activated:Fire()
				node:FindFirstChild("Sort", true).Activated:Fire()
				local resize = node:FindFirstChild("Resize", true):FindFirstChildWhichIsA("UIDragDetector")
				resize.DragStart:Fire(engine.types.Vector2.new(10, 10))
				resize.DragContinue:Fire(engine.types.Vector2.new(50, 10))
				expect(requests):toBe(3)
				expect((selection:peek())):toEqual({})
				expect((sort:peek())):toBeNil()
				expect((widths:peek())):toEqual({})
				stop()
				runtime:dispose()
			end,
		})

		it("keeps block tables fully mounted and discloses collapsed columns without losing cell state", {
			id = "native_collections::Compose native collections::keeps block tables fully mounted and discloses collapsed columns without losing cell state",
			run = function()
				local engine, runtime, UI, target = setup()
				local builds = 0
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<
						{ id: number, first: string, second: string, third: string },
						number
					> =
						{
							from = { { id = 1, first = "One", second = "Two", third = "Full hidden value" } },
							key = key,
							scrolls = false,
							itemSize = 40,
							columns = {
								{ id = "first", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
								{ id = "second", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
								{
									id = "third",
									label = "Third",
									width = 100,
									priority = 3,
									render = function(): GuiObject
										builds += 1
										return Facet.host(runtime).TextBox({
											Text = "Local edit",
										})
									end,
								} :: FixtureCollectionTypes.TableColumn<any, any>,
							},
						}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				expect(body.ScrollingEnabled):toBe(false)
				expect(node.Size.Y.Offset):toBe(80)
				local row = body:FindFirstChild("1", true)
				local cell = row:FindFirstChild("third", true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(250, 40)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				expect(cell.Visible):toBe(false)
				local menu = row:FindFirstChild("Details", true)
				menu.Activated:Fire()
				local fullValue = target:FindFirstChild("Popup", true):FindFirstChild("third", true)
				expect(fullValue ~= nil):toBe(true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(400, 40)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				expect((row:FindFirstChild("third", true))):toBe(cell)
				expect(cell.Visible):toBe(true)
				expect(builds):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		it("uses new grid neighbors when responsive columns change without changing total extent", {
			id = "native_collections::Compose native collections::uses new grid neighbors when responsive columns change without changing total extent",
			run = function()
				local engine, runtime, UI, target = setup()
				local columns, focus: FixtureCollectionTypes.FocusControls<any> = Compose.cell(4), {}
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(12),
						key = key,
						itemSize = 20,
						columns = columns,
						focus = focus,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualGrid(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				assert(focus.focus)(2)
				columns:set(5)
				assert(focus.move)("down")
				expect((assert(focus.current):peek())):toBe(7)
				stop()
				runtime:dispose()
			end,
		})

		it("drops removed measurements and refreshes current-item row actions under stable keys", {
			id = "native_collections::Compose native collections::drops removed measurements and refreshes current-item row actions under stable keys",
			run = function()
				local engine, runtime, UI, target = setup()
				local source, status =
					Compose.cell(records(2)), Compose.cell({
						mode = "windowed" :: "windowed",
						direction = "vertical" :: "vertical",
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
					} :: Compose.OrderedCollectionStatus)
				local invoked = ""
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = source,
						key = key,
						itemSize = 20,
						status = status,
						measure = true,
						render = function(current): GuiObject
							return UI.RowActions {
								open = Compose.cell("trailing" :: "leading" | "trailing" | nil) :: FixtureComposeTypes.Value<FixtureCollectionTypes.RowEdge?>,
								content = button(UI, current),
								trailing = function(use: Use): { FixtureCollectionTypes.RowAction }
									local item = use(current)
									return {
										{
											id = "Save",
											label = item.label,
											onActivate = function()
												invoked = item.label
											end,
										},
									}
								end,
							}
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				local row = node:FindFirstChild("1", true):FindFirstChild("Content"):GetChildren()[1]
				engine.environment.poke(
					VerifyRoblox.assertInstance(row),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 60)
				)
				expect(status:peek().extent):toBe(80)
				local action = row:FindFirstChild("Save", true)
				source:set({ { id = 1, label = "Latest" }, { id = 2, label = "Second" } })
				expect((row:FindFirstChild("Save", true))):toBe(action)
				expect(action.Text):toBe("Latest")
				action.Activated:Fire()
				expect(invoked):toBe("Latest")
				source:set({ { id = 2, label = "Second" } })
				source:set(records(2))
				expect(status:peek().extent):toBe(40)
				stop()
				runtime:dispose()
			end,
		})

		it("locks vertical gestures, opens short velocity flicks and cancels disabled drags", {
			id = "native_collections::Compose native collections::locks vertical gestures, opens short velocity flicks and cancels disabled drags",
			run = function()
				local now = 0
				local engine, runtime, UI, target = setup({
					clock = function()
						return now
					end,
				})
				local enabled, open: FixtureComposeTypes.Value<("leading" | "trailing")?>, invoked =
					Compose.cell(true), Compose.cell(nil :: ("leading" | "trailing")?), 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions {
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						open = open,
						enabled = enabled,
						trailing = {
							{
								id = "Save",
								icon = "rbxassetid://1",
								label = "Save",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					}
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 40)
				)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(200, 0))
				now = 0.1
				detector.DragContinue:Fire(engine.types.Vector2.new(195, 60))
				detector.DragEnd:Fire()
				expect((open:peek())):toBeNil()
				detector.DragStart:Fire(engine.types.Vector2.new(200, 0))
				now = 0.11
				detector.DragContinue:Fire(engine.types.Vector2.new(188, 0))
				expect(node:FindFirstChild("trailing").Size.X.Offset):toBe(12)
				expect(node:FindFirstChild("LeadingIcon", true).Image):toBe("rbxassetid://1")
				detector.DragEnd:Fire()
				expect((open:peek())):toBe("trailing")
				open:set(nil)
				detector.DragStart:Fire(engine.types.Vector2.new(200, 0))
				now = 0.3
				detector.DragContinue:Fire(engine.types.Vector2.new(-100, 0))
				enabled:set(false)
				detector.DragEnd:Fire()
				expect((open:peek())):toBeNil()
				expect(invoked):toBe(0)
				expect(detector.Enabled):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		it("ignores stale zero table cell bounds and accepts a real zero height", {
			id = "native_collections::Compose native collections::ignores stale zero table cell bounds and accepts a real zero height",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup()
				local Host = Facet.host(runtime)
				local observed = Compose.cell(engine.types.Vector2.zero)
				local original = ctx.observe.AbsoluteSize
				ctx.observe.AbsoluteSize = function(node: GuiBase2d)
					return if node.Name == "DelayedHeight" then observed else original(node)
				end
				local controls: FixtureComposeTypes.OrderedCollectionControls<number> = {}
				local function delayed(): GuiObject
					return Host.Frame {
						Name = "DelayedHeight",
						Size = engine.types.UDim2.fromOffset(200, 60),
					}
				end
				local column: FixtureCollectionTypes.TableColumn<{ id: number }, number> = {
					id = "content",
					render = delayed,
				}
				local stop, mounted = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: number }, number> = {
						from = { { id = 1 }, { id = 2 } },
						key = function(item: { id: number }): number
							return item.id
						end,
						controls = controls,
						columns = { column },
					}
					return UI.Table(tableSpec)
				end, target)
				local node = (mounted :: unknown) :: Frame
				local body = (assert(node:FindFirstChild("Body")) :: unknown) :: { AbsoluteWindowSize: Vector2 }
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 200)
				)
				local minimum = assert(controls.placementOf)(2).offset
				local measured = (assert(node:FindFirstChild("DelayedHeight", true))) :: { AbsoluteSize: Vector2 }
				engine.environment.poke(
					VerifyRoblox.assertInstance(measured),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 60)
				)
				observed:set(engine.types.Vector2.new(200, 60))
				expect(assert(controls.placementOf)(2).offset):toBe(76)
				observed:set(engine.types.Vector2.zero)
				expect(assert(controls.placementOf)(2).offset):toBe(76)
				engine.environment.poke(
					VerifyRoblox.assertInstance(measured),
					"AbsoluteSize",
					engine.types.Vector2.zero
				)
				observed:set(engine.types.Vector2.new(200, 0))
				engine.heartbeat:Fire(1 / 60)
				engine.heartbeat:Fire(1 / 60)
				expect(assert(controls.placementOf)(2).offset):toBe(minimum)
				stop()
				runtime:dispose()
			end,
		})
		it("adapts table row and header height from native text bounds and preferred input", {
			id = "native_collections::Compose native collections::adapts table row and header height from native text bounds and preferred input",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({
					userInputService = {},
					theme = {
						identity = { rendering = "smooth" },
						metrics = { controlSizes = { regular = { height = 32 } } },
					},
				})
				local controls: FixtureComposeTypes.OrderedCollectionControls<any> = {}
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(2),
						key = key,
						controls = controls,
						columns = { { id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any> },
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local row = body:FindFirstChild("1", true)
				expect(assert(controls.placementOf)(2).offset):toBe(40)
				engine.environment.poke(
					VerifyRoblox.assertInstance(row:FindFirstChild("Value", true)),
					"TextBounds",
					engine.types.Vector2.new(100, 60)
				)
				expect(assert(controls.placementOf)(2).offset):toBe(76)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node:FindFirstChild("Sort", true)),
					"TextBounds",
					engine.types.Vector2.new(100, 70)
				)
				expect(body.Position.Y.Offset):toBe(86)

				engine.environment.poke(
					VerifyRoblox.assertInstance(node:FindFirstChild("LayoutUnit")),
					"AbsoluteSize",
					engine.types.Vector2.new(2, 2)
				)
				expect(body.Position.Y.Offset):toBe(51)
				expect(assert(controls.placementOf)(2).offset):toBe(46)
				local header = node:FindFirstChild("Header")
				engine.environment.poke(
					VerifyRoblox.assertInstance(header:FindFirstChildWhichIsA("UIListLayout")),
					"AbsoluteContentSize",
					engine.types.Vector2.new(800, 102)
				)
				for _, label in node:GetDescendants() do
					if label.Name == "Undisclosed" then
						engine.environment.poke(VerifyRoblox.assertInstance(label), "TextFits", true)
					end
				end
				expect(body.CanvasSize.X.Offset):toBe(400)
				body.CanvasPosition = engine.types.Vector2.new(80, 0)
				expect(header.Position.X.Offset):toBe(0)
				expect(header:IsA("ScrollingFrame")):toBe(true)
				expect(header.CanvasPosition.X):toBe(80)
				expect(header.CanvasSize.X.Offset):toBe(400)
				header.CanvasPosition = engine.types.Vector2.new(60, 0)
				expect(body.CanvasPosition.X):toBe(60)
				body.CanvasPosition = engine.types.Vector2.zero
				engine.environment.poke(
					VerifyRoblox.assertInstance(node:FindFirstChild("LayoutUnit")),
					"AbsoluteSize",
					engine.types.Vector2.one
				)

				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					engine.types.Enum.PreferredInput.Touch
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(row:FindFirstChild("Value", true)),
					"TextBounds",
					engine.types.Vector2.new(100, 8)
				)
				expect(assert(controls.placementOf)(2).offset):toBe(56)
				engine.environment.poke(
					VerifyRoblox.assertInstance(row:FindFirstChild("Value", true)),
					"TextBounds",
					engine.types.Vector2.new(100, 60)
				)
				expect(assert(controls.placementOf)(2).offset):toBe(76)
				expect((body:FindFirstChild("1", true))):toBe(row)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node:FindFirstChild("Sort", true)),
					"TextBounds",
					engine.types.Vector2.new(100, 20)
				)
				expect(body.Position.Y.Offset):toBe(44)
				local value = row:FindFirstChild("Value", true)
				value.Text = ""
				engine.environment.poke(VerifyRoblox.assertInstance(value), "TextBounds", engine.types.Vector2.zero)
				expect(assert(controls.placementOf)(2).offset):toBe(56)
				value.Text = "Restored"
				engine.environment.poke(
					VerifyRoblox.assertInstance(value),
					"TextBounds",
					engine.types.Vector2.new(100, 60)
				)
				expect(assert(controls.placementOf)(2).offset):toBe(76)
				stop()
				runtime:dispose()
			end,
		})
		it("measures localized row action labels and reveals truncated visible table values", {
			id = "native_collections::Compose native collections::measures localized row action labels and reveals truncated visible table values",
			run = function()
				local engine, runtime, UI, target = setup()
				local open: FixtureComposeTypes.Value<("leading" | "trailing")?>, editing =
					Compose.cell("trailing" :: ("leading" | "trailing")?), Compose.cell(true)
				local stopActions, actions: any = runtime.mount(function()
					return UI.RowActions {
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						open = open,
						editing = editing,
						trailing = {
							{
								id = "Remove",
								label = "Localized destructive action",
								role = "destructive" :: "destructive",
							} :: FixtureCollectionTypes.RowAction,
						},
					}
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(actions),
					"AbsoluteSize",
					engine.types.Vector2.new(500, 40)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(actions:FindFirstChild("Remove", true)),
					"TextBounds",
					engine.types.Vector2.new(210.667, 20)
				)
				expect(actions:FindFirstChild("trailing").Size.X.Offset):toBe(243)
				engine.environment.poke(
					VerifyRoblox.assertInstance(actions:FindFirstChild("Delete", true)),
					"TextBounds",
					engine.types.Vector2.new(190.667, 20)
				)
				expect(actions:FindFirstChild("Content").Position.X.Offset):toBe(-20)
				engine.environment.poke(
					VerifyRoblox.assertInstance(actions:FindFirstChild("Remove", true)),
					"TextBounds",
					engine.types.Vector2.new(30, 20)
				)
				expect(actions:FindFirstChild("trailing").Size.X.Offset):toBe(88)
				stopActions()
				local source = Compose.cell({ { id = 1, label = "Long value that should be disclosed" } })
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: number, label: string }, number> = {
						from = source,
						key = key,
						columns = {
							{ id = "label", label = "Label", width = 180 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(250, 100)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local row = body:FindFirstChild("1", true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(row:FindFirstChild("Undisclosed", true)),
					"TextFits",
					true
				)
				expect((row:FindFirstChild("Details", true))):toBeNil()
				engine.environment.poke(
					VerifyRoblox.assertInstance(row:FindFirstChild("Undisclosed", true)),
					"TextFits",
					false
				)
				row:FindFirstChild("Details", true).Activated:Fire()
				local expanded = target:FindFirstChild("Popup", true)
				expect(expanded:FindFirstChild("FullValue", true).Text):toBe("Long value that should be disclosed")
				source:set({ { id = 1, label = "Updated entire value" } })
				expect(expanded:FindFirstChild("FullValue", true).Text):toBe("Updated entire value")
				engine.environment.poke(
					VerifyRoblox.assertInstance(row:FindFirstChild("Undisclosed", true)),
					"TextFits",
					true
				)
				expect((target:FindFirstChild("Popup", true))):toBeNil()
				expect((body:FindFirstChild("1", true))):toBe(row)
				stop()
				runtime:dispose()
			end,
		})

		it("keeps table disclosure while a truncated row scrolls out", {
			id = "native_collections::Compose native collections::keeps table disclosure while a truncated row scrolls out",
			run = function()
				local engine, runtime, UI, target = setup()
				local rows: { Record } = {}
				for index = 1, 60 do
					rows[index] = { id = index, label = "Value " .. index }
				end
				local stop, node = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = rows,
						key = key,
						columns = {
							{ id = "label", label = "Label", width = 180 } :: FixtureCollectionTypes.TableColumn<{ id: number, label: string }, number>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				local body = assert(VerifyRoblox.assertInstance(node):FindFirstChild("Body"))
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(250, 100)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local function fitAll()
					for _, item in body:GetDescendants() do
						if item:IsA("TextLabel") and item.Name == "Undisclosed" and item.TextFits ~= true then
							engine.environment.poke(VerifyRoblox.assertInstance(item), "TextFits", true)
						end
					end
				end
				fitAll()
				local first = assert(body:FindFirstChild("1", true))
				expect((first:FindFirstChild("Details", true))):toBeNil()
				engine.environment.poke(
					VerifyRoblox.assertInstance(first:FindFirstChild("Undisclosed", true)),
					"TextFits",
					false
				)
				expect(first:FindFirstChild("Details", true) ~= nil):toBe(true)
				body.CanvasPosition = engine.types.Vector2.new(0, 2000)
				local function mounted(name: string): boolean
					for _, item in body:GetDescendants() do
						if item.Name == name and item:FindFirstChild("DisclosingRow", true) then
							return true
						end
					end
					return false
				end
				expect(mounted("1")):toBe(false)
				fitAll()
				local shown: VerifyRoblox.Instance? = nil
				for _, item in body:GetDescendants() do
					if item.Name == "DisclosingRow" then
						shown = item
						break
					end
				end
				expect(shown ~= nil):toBe(true)
				expect((assert(shown):FindFirstChild("Details", true)) ~= nil):toBe(true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(400, 100)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				expect((assert(shown):FindFirstChild("Details", true))):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		it("keeps native reorder capture and keyboard drop alive across offscreen autoscroll", {
			id = "native_collections::Compose native collections::keeps native reorder capture and keyboard drop alive across offscreen autoscroll",
			run = function()
				local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
				local requests: { { keys: { number }, slot: number } } = {}
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(100),
						key = key,
						itemSize = 20,
						overscan = 0,
						reorderable = true,
						onReorder = function(keys: { number }, slot: number)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
				local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
				local input = {
					UserInputType = engine.types.Enum.UserInputType.MouseButton1,
					Position = engine.types.Vector3.new(10, 10, 0),
				}
				handle.InputBegan:Fire(input)
				detector.DragStart:Fire(engine.types.Vector2.new(10, 10))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 99))
				for _ = 1, 40 do
					engine.heartbeat:Fire(1 / 60)
				end
				expect(body.CanvasPosition.Y > 200):toBe(true)
				expect((body:FindFirstChild("1", true))):toBeNil()
				local injectedInputChanged = assert(ctx.config.userInputService).InputChanged :: any
				injectedInputChanged:Fire({
					UserInputType = engine.types.Enum.UserInputType.MouseMovement,
					Position = engine.types.Vector3.new(10, 80, 0),
				})
				local injectedInputEnded = assert(ctx.config.userInputService).InputEnded :: any
				injectedInputEnded:Fire(input)
				expect(#requests):toBe(1)
				expect(requests[1].keys):toEqual({ 1 })
				expect(requests[1].slot > 10):toBe(true)
				body.CanvasPosition = engine.types.Vector2.zero
				handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
				handle.Activated:Fire()
				expect(assert(gui.SelectedObject).Name):toBe("Drop")
				for _, part in node:FindFirstChild("DragImage", true):GetDescendants() do
					if part:IsA("GuiObject") or part:IsA("Path2D") then
						expect(assert(gui.SelectedObject).ZIndex > part.ZIndex):toBe(true)
					end
				end
				local action = target:FindFirstChild("FacetReorderDown"):FindFirstChild("ReorderDown")
				for _ = 1, 25 do
					action.Pressed:Fire()
				end
				expect((body:FindFirstChild("1", true))):toBeNil()
				expect(assert(gui.SelectedObject).Name):toBe("Drop")
				target:FindFirstChild("FacetReorderDrop"):FindFirstChild("ReorderDrop").Pressed:Fire()
				expect(requests[2]):toEqual({ keys = { 1 }, slot = 25 })
				expect(body.CanvasPosition.Y):toBe(0)
				handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
				expect(gui.SelectedObject):toBe(handle)
				handle.Activated:Fire()
				for _ = 1, 25 do
					action.Pressed:Fire()
				end
				target:FindFirstChild("FacetReorderCancel"):FindFirstChild("ReorderCancel").Pressed:Fire()
				expect(body.CanvasPosition.Y):toBe(0)
				handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
				expect(gui.SelectedObject):toBe(handle)
				detector = handle:FindFirstChildWhichIsA("UIDragDetector")
				handle.InputBegan:Fire(input)
				detector.DragStart:Fire(engine.types.Vector2.new(10, 10))
				engine.environment.poke(VerifyRoblox.assertInstance(ctx.config.userInputService), "MouseEnabled", false)
				expect((node:FindFirstChild("DropLine", true))):toBeNil()
				local injectedInputEnded = assert(ctx.config.userInputService).InputEnded :: any
				injectedInputEnded:Fire(input)
				expect(#requests):toBe(2)
				stop()
				runtime:dispose()
			end,
		})
		it("shares list selection and reorder policies and fails closed for protected rows", {
			id = "native_collections::Compose native collections::shares list selection and reorder policies and fails closed for protected rows",
			run = function()
				local engine, runtime, UI, target = setup()
				local selected, requests = Compose.cell({}), {}
				local source = Compose.cell(records(4))
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = source,
						key = key,
						itemSize = 20,
						overscan = 0,
						selection = selected,
						selectionMode = "multiple" :: "multiple",
						selectable = function(item)
							if item.id == 2 then
								error("rejected")
							end
							return true
						end,
						movable = function(item)
							if item.id == 2 then
								error("rejected")
							end
							return true
						end,
						reorderable = true,
						onReorder = function(keys: { number }, slot: number)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				node:FindFirstChild("1", true):FindFirstChild("RowHit", true).Activated:Fire()
				node:FindFirstChild("2", true):FindFirstChild("RowHit", true).Activated:Fire()
				expect((selected:peek())):toEqual({ [1] = true })
				expect((node:FindFirstChild("1", true):FindFirstChild("RowHit", true):GetAttribute("FacetSelected"))):toBe(
					true
				)
				expect(node:FindFirstChild("2", true):FindFirstChild("Move", true).Interactable):toBe(false)
				local detector = node:FindFirstChild("1", true):FindFirstChildWhichIsA("UIDragDetector", true)
				detector.DragStart:Fire(engine.types.Vector2.new(10, 10))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 90))
				detector.DragEnd:Fire()
				expect(#requests):toBe(0)
				local remaining = records(4)
				table.remove(remaining, 1)
				source:set(remaining)
				expect((selected:peek())):toEqual({})
				stop()
				runtime:dispose()
			end,
		})

		it("snaps native scrolling to Compose measured boundaries and yields animation to input", {
			id = "native_collections::Compose native collections::snaps native scrolling to Compose measured boundaries and yields animation to input",
			run = function()
				local now = 0
				local engine, runtime, UI, target = setup({
					clock = function()
						return now
					end,
					motionLevel = "normal",
				})
				local function advance(seconds: number)
					for _ = 1, math.ceil(seconds * 60) do
						now += 1 / 60
						engine.heartbeat:Fire(1 / 60)
					end
				end
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(20),
						key = key,
						itemSize = 40,
						snap = "item" :: "item",
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				now = 1
				node.CanvasPosition = engine.types.Vector2.new(0, 26)
				advance(0.14)
				expect(node.CanvasPosition.Y >= 26 and node.CanvasPosition.Y < 40):toBe(true)
				local input = { UserInputType = engine.types.Enum.UserInputType.MouseButton1 }
				node.InputBegan:Fire(input)
				local interrupted = node.CanvasPosition.Y
				advance(0.5)
				expect(node.CanvasPosition.Y):toBe(interrupted)
				node.InputEnded:Fire(input)
				advance(0.4)
				expect(node.CanvasPosition.Y):toBe(40)
				stop()
				local stopMeasured, measured: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(20),
						key = key,
						itemSize = 20,
						measured = { [1] = 35 },
						snap = "item" :: "item",
						reducedMotion = true,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(measured),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				now += 1
				measured.CanvasPosition = engine.types.Vector2.new(0, 23)
				advance(0.2)
				expect(measured.CanvasPosition.Y):toBe(35)
				stopMeasured()
				local stopGrid, grid: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(20),
						key = key,
						itemSize = 40,
						columns = 2,
						direction = "horizontal" :: "horizontal",
						snap = "item" :: "item",
						reducedMotion = true,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualGrid(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(grid),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(100, 200)
				)
				grid.InputBegan:Fire(input)
				now += 0.01
				grid.CanvasPosition = engine.types.Vector2.new(5, 0)
				grid.InputEnded:Fire(input)
				advance(0.15)
				expect(grid.CanvasPosition.X):toBe(40)
				stopGrid()
				local stopLarge, large: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(5),
						key = key,
						itemSize = 120,
						snap = "item" :: "item",
						reducedMotion = true,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(large),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				now += 1
				large.CanvasPosition = engine.types.Vector2.new(0, 23)
				advance(0.2)
				expect(large.CanvasPosition.Y):toBe(23)
				stopLarge()
				stop, node = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(20),
						key = key,
						itemSize = 40,
						snap = "item" :: "item",
						reducedMotion = true,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteCanvasSize",
					engine.types.Vector2.new(200, 800)
				)
				now += 1
				node.CanvasPosition = engine.types.Vector2.new(0, 80)
				now += 0.001
				node.CanvasPosition = engine.types.Vector2.new(0, 40)
				advance(0.2)
				expect(node.CanvasPosition.Y):toBe(40)
				stop()
				runtime:dispose()
			end,
		})
		it("a list that opts into motion still lands its snap when the device asks for reduced motion", {
			id = "native_collections::Compose native collections::a list that opts into motion still lands its snap when the device asks for reduced motion",
			run = function()
				local now = 0
				local engine, runtime, UI, target = setup({
					clock = function()
						return now
					end,
					motionLevel = "none",
				})
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(20),
						key = key,
						itemSize = 40,
						snap = "item" :: "item",
						reducedMotion = false,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				now = 1
				node.CanvasPosition = engine.types.Vector2.new(0, 26)
				for _ = 1, 60 do
					now += 1 / 60
					engine.heartbeat:Fire(1 / 60)
				end
				expect(node.CanvasPosition.Y):toBe(40)
				stop()
				runtime:dispose()
			end,
		})
		it("a snap starts gently from rest and lands flush", {
			id = "native_collections::Compose native collections::a snap starts gently from rest and lands flush",
			run = function()
				local now = 0
				local engine, runtime, UI, target = setup({
					clock = function()
						return now
					end,
					motionLevel = "normal",
				})
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(20),
						key = key,
						itemSize = 40,
						snap = "item" :: "item",
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				now = 1
				node.CanvasPosition = engine.types.Vector2.new(0, 26)
				local offsets: { number } = {}
				for _ = 1, 40 do
					now += 1 / 60
					engine.heartbeat:Fire(1 / 60)
					table.insert(offsets, node.CanvasPosition.Y)
				end
				local moves: { number } = {}
				for index = 2, #offsets do
					if offsets[index] ~= offsets[index - 1] then
						table.insert(moves, offsets[index] - offsets[index - 1])
					end
				end
				expect(#moves >= 4):toBe(true)
				expect(moves[1] < moves[4]):toBe(true)
				expect(offsets[#offsets]):toBe(40)
				stop()
				runtime:dispose()
			end,
		})
		it("cancels native row gestures and keeps destructive opt-outs behind every action route", {
			id = "native_collections::Compose native collections::cancels native row gestures and keeps destructive opt-outs behind every action route",
			run = function()
				local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
				local enabled, open: FixtureComposeTypes.Value<("leading" | "trailing")?>, invoked =
					Compose.cell(false), Compose.cell(nil :: ("leading" | "trailing")?), 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions {
						content = UI.Button "Action" { label = "Protected" } :: GuiObject,
						open = open,
						editing = Compose.cell(true),
						trailing = {
							{
								id = "Remove",
								label = "Remove",
								role = "destructive" :: "destructive",
								enabled = enabled,
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					}
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 40)
				)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				local pointer = {
					UserInputType = engine.types.Enum.UserInputType.Touch,
					UserInputState = engine.types.Enum.UserInputState.Begin,
				}
				node.InputBegan:Fire(pointer)
				detector.DragStart:Fire(engine.types.Vector2.new(280, 0))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 0))
				detector.DragEnd:Fire()
				expect(invoked):toBe(0)
				open:set("trailing")
				node:FindFirstChild("Remove", true).Activated:Fire()
				expect(invoked):toBe(0)
				expect((node:FindFirstChild("Delete", true))):toBeNil()
				gui.SelectedObject = node:FindFirstChild("Action", true)
				open:set(nil)
				expect(target:FindFirstChild("FacetRowActionsDelete").Enabled):toBe(false)
				node.InputBegan:Fire({
					UserInputType = engine.types.Enum.UserInputType.MouseButton2,
					Position = engine.types.Vector3.new(50, 50, 0),
				})
				local menuButton = target:FindFirstChild("trailing:Remove", true)
				expect(menuButton.Interactable):toBe(false)
				menuButton.Activated:Fire()
				expect(invoked):toBe(0)
				target:FindFirstChild("FacetModalBack"):FindFirstChild("ModalBack").Pressed:Fire()
				enabled:set(true)
				node.InputBegan:Fire(pointer)
				detector.DragStart:Fire(engine.types.Vector2.new(280, 0))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 0))
				pointer.UserInputState = engine.types.Enum.UserInputState.Cancel
				local injectedInputChanged = assert(ctx.config.userInputService).InputChanged :: any
				injectedInputChanged:Fire(pointer)
				detector.DragEnd:Fire()
				expect(invoked):toBe(0)
				expect((open:peek())):toBeNil()
				stop()
				runtime:dispose()
			end,
		})
		it("enters native focus after unfocused collection churn and reaches offscreen keys", {
			id = "native_collections::Compose native collections::enters native focus after unfocused collection churn and reaches offscreen keys",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local source = Compose.cell(records(100))
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = source,
						key = key,
						itemSize = 20,
						overscan = 0,
						disabled = function(item)
							return item.id == 2
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				local replaced = records(100)
				replaced[1] = { id = 101, label = "101" }
				source:set(replaced)
				local first = node:FindFirstChild("101", true):FindFirstChild("Action", true)
				gui.SelectedObject = first
				first.SelectionGained:Fire()
				target:FindFirstChild("FacetCollectionDown"):FindFirstChild("CollectionDown").Pressed:Fire()
				expect((assert(gui.SelectedObject) :: TextLabel).Text):toBe("3")
				target:FindFirstChild("FacetCollectionLast"):FindFirstChild("CollectionLast").Pressed:Fire()
				expect((assert(gui.SelectedObject) :: TextLabel).Text):toBe("100")
				expect(node.CanvasPosition.Y):toBe(1900)
				stop()
				runtime:dispose()
			end,
		})
		it("pages a list by the viewport with the triggers and skips disabled rows", {
			id = "native_collections::Compose native collections::pages a list by the viewport with the triggers and skips disabled rows",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(12),
						key = key,
						itemSize = 20,
						overscan = 0,
						disabled = function(item)
							return item.id == 5
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				local first = node:FindFirstChild("1", true):FindFirstChild("Action", true)
				gui.SelectedObject = first
				first.SelectionGained:Fire()
				local function press(name: string)
					target:FindFirstChild("Facet" .. name):FindFirstChild(name).Pressed:Fire()
				end
				local function selected(): string
					return (assert(gui.SelectedObject) :: TextLabel).Text
				end
				local pageDown = target:FindFirstChild("FacetCollectionPageDown")
				expect(pageDown ~= nil):toBe(true)
				press("CollectionPageDown")
				expect(selected()):toBe("4")
				press("CollectionPageDown")
				expect(selected()):toBe("8")
				press("CollectionPageDown")
				expect(selected()):toBe("12")
				press("CollectionPageDown")
				expect(selected()):toBe("12")
				press("CollectionPageUp")
				expect(selected()):toBe("8")
				press("CollectionPageUp")
				expect(selected()):toBe("4")
				stop()
				runtime:dispose()
			end,
		})
		it("pages an outline through its visible children", {
			id = "native_collections::Compose native collections::pages an outline through its visible children",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local kids = {}
				for index = 1, 10 do
					table.insert(kids, { id = 100 + index, label = `{100 + index}` })
				end
				local roots = { { id = 1, label = "1" }, { id = 2, label = "2" }, { id = 3, label = "3" } }
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedOutlineSpec<{ id: number, label: string }, number> = {
						from = roots,
						key = key,
						itemSize = 20,
						overscan = 0,
						expanded = Compose.cell({ [1] = true }),
						children = function(item)
							return if item.id == 1 then kids else nil
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.Outline(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				local first = node:FindFirstChild("1", true):FindFirstChild("Action", true)
				gui.SelectedObject = first
				first.SelectionGained:Fire()
				local function press(name: string)
					target:FindFirstChild("Facet" .. name):FindFirstChild(name).Pressed:Fire()
				end
				local function selected(): string
					return (assert(gui.SelectedObject) :: TextLabel).Text
				end
				press("CollectionPageDown")
				expect(selected()):toBe("104")
				press("CollectionPageDown")
				expect(selected()):toBe("108")
				press("CollectionPageDown")
				expect(selected()):toBe("3")
				press("CollectionPageUp")
				expect(selected()):toBe("108")
				stop()
				runtime:dispose()
			end,
		})
		it("pages a grid within its column and reaches a short last row", {
			id = "native_collections::Compose native collections::pages a grid within its column and reaches a short last row",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(20),
						key = key,
						columns = 3,
						itemSize = 20,
						overscan = 0,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualGrid(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(60, 60)
				)
				local third = node:FindFirstChild("3", true):FindFirstChild("Action", true)
				gui.SelectedObject = third
				third.SelectionGained:Fire()
				local function press(name: string)
					target:FindFirstChild("Facet" .. name):FindFirstChild(name).Pressed:Fire()
				end
				local function selected(): string
					return (assert(gui.SelectedObject) :: TextLabel).Text
				end
				press("CollectionPageDown")
				expect(selected()):toBe("9")
				press("CollectionPageDown")
				expect(selected()):toBe("15")
				press("CollectionPageDown")
				expect(selected()):toBe("18")
				press("CollectionPageDown")
				expect(selected()):toBe("20")
				press("CollectionPageUp")
				expect(selected()):toBe("14")
				stop()
				runtime:dispose()
			end,
		})
	end)

	describe("Table compact width", function()
		it("prepares shared column geometry before the first table paint", {
			id = "native_collections::Table compact width::prepares shared column geometry before the first table paint",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup()
				ctx.config.services.RunService = ({ Heartbeat = engine.heartbeat } :: unknown) :: RunService
				local stop, mounted = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: string, name: string }, string> = {
						from = { { id = "a", name = "Alpha" } },
						key = "id",
						columns = { { id = "name", label = "Name" } },
					}
					return UI.Table(tableSpec)
				end, target)
				local node = (mounted :: unknown) :: Frame
				local geometry = (node :: unknown) :: { AbsoluteSize: Vector2 }
				engine.environment.poke(
					VerifyRoblox.assertInstance(geometry),
					"AbsoluteSize",
					engine.types.Vector2.new(300, 200)
				)
				local header = assert(node:FindFirstChild("Header", true)) :: Frame
				for _, child in node:GetDescendants() do
					if child:IsA("GuiObject") then
						local box = (child :: unknown) :: { AbsoluteSize: Vector2, TextBounds: Vector2 }
						engine.environment.poke(
							VerifyRoblox.assertInstance(box),
							"AbsoluteSize",
							engine.types.Vector2.new(100, 20)
						)
						if child:IsA("TextLabel") or child:IsA("TextButton") then
							engine.environment.poke(
								VerifyRoblox.assertInstance(box),
								"TextBounds",
								engine.types.Vector2.new(50, 16)
							)
						end
					end
				end
				engine.heartbeat:Fire(1 / 60)
				expect(node:FindFirstChild("FadePaint") ~= nil):toBe(true)
				local columns = (header :: unknown) :: { AbsoluteSize: Vector2 }
				engine.environment.poke(
					VerifyRoblox.assertInstance(columns),
					"AbsoluteSize",
					engine.types.Vector2.new(200, 20)
				)
				engine.heartbeat:Fire(1 / 60)
				expect(node:FindFirstChild("FadePaint") ~= nil):toBe(true)
				for _ = 1, 8 do
					engine.heartbeat:Fire(1 / 60)
				end
				expect(node:FindFirstChild("FadePaint") == nil):toBe(true)
				stop()
				runtime:dispose()
				expect(engine.census().connections):toBe(0)
			end,
		})
		it("keeps every column in a narrow table and paints the header band across its columns", {
			id = "native_collections::Table compact width::keeps every column in a narrow table and paints the header band across its columns",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<
						{ id: number, name: string, artist: string, rating: number },
						number
					> =
						{
							from = { { id = 1, name = "Neon Straightaway", artist = "Chrome Coyote", rating = 4 } },
							key = key,
							reorderable = true,
							onReorder = function() end,
							columns = {
								{ id = "name", label = "Name", minWidth = 90 } :: FixtureCollectionTypes.TableColumn<any, any>,
								{ id = "artist", label = "Artist", minWidth = 72 } :: FixtureCollectionTypes.TableColumn<any, any>,
								{ id = "rating", label = "Rating", width = 144, resizable = false } :: FixtureCollectionTypes.TableColumn<any, any>,
							},
						}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(300, 200)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local row = body:FindFirstChild("1", true)
				for _, id in { "name", "artist", "rating" } do
					expect(row:FindFirstChild(id, true).Visible):toBe(true)
					expect(node:FindFirstChild("Header"):FindFirstChild(id).Visible):toBe(true)
				end
				local band = node:FindFirstChild("HeaderBand")
				local gutter = node:FindFirstChild("Header").Position.X.Offset
				expect(band.Position.X.Offset):toBe(gutter)
				expect(band.Size):toBe(engine.types.UDim2.new(1, 0, 0, node:FindFirstChild("Header").Size.Y.Offset))
				expect((band:HasTag("facet-tablehead"))):toBe(true)
				expect(node:FindFirstChild("Header").BackgroundTransparency):toBe(1)
				engine.environment.poke(
					VerifyRoblox.assertInstance(row:FindFirstChild("Undisclosed", true)),
					"TextFits",
					false
				)
				local more = row:FindFirstChild("Details", true)
				expect(more:FindFirstChild("Title", true) == nil or not more:FindFirstChild("Title", true).Visible):toBe(
					true
				)
				expect(more:FindFirstChild("LeadingIcon", true) ~= nil):toBe(true)
				expect((more:GetAttribute("label"))):toBe("Show details")
				expect((more:HasTag("facet-appearance-utility"))):toBe(true)
				stop()
				runtime:dispose()
			end,
		})
	end)

	describe("Table under a scaled ancestor", function()
		it("sizes its header in layout units when a UIScale shrinks the rendered window", {
			id = "native_collections::Table under a scaled ancestor::sizes its header in layout units when a UIScale shrinks the rendered window",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: number, name: string }, number> = {
						from = { { id = 1, name = "Neon" } },
						key = key,
						columns = {
							{ id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any>,
							{ id = "rating", label = "Rating", width = 144 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				local unit = node:FindFirstChild("LayoutUnit")
				expect(unit ~= nil):toBe(true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(unit),
					"AbsoluteSize",
					engine.types.Vector2.new(0.8, 0.8)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(800, 200)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				for _, label in node:GetDescendants() do
					if label.Name == "Undisclosed" then
						engine.environment.poke(VerifyRoblox.assertInstance(label), "TextFits", true)
					end
				end
				expect(node:FindFirstChild("Header").Size.X.Offset):toBe(1000)
				stop()
				runtime:dispose()
			end,
		})
		it("matches the header to the body scroll window while no vertical scrollbar shows", {
			id = "native_collections::Table under a scaled ancestor::matches the header to the body scroll window while no vertical scrollbar shows",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, mounted = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: number, name: string }, number> = {
						from = { { id = 1, name = "Neon" } },
						key = key,
						columns = {
							{ id = "name", label = "Name", width = 260 },
							{ id = "rating", label = "Rating", width = 140 },
						},
					}
					return UI.Table(tableSpec)
				end, target)
				local node = mounted :: Instance
				type Probe = {
					ScrollBarThickness: number,
					AbsoluteSize: Vector2,
					AbsoluteWindowSize: Vector2,
					Parent: { AbsoluteSize: Vector2 },
				}
				local body = (assert(node:FindFirstChild("Body")) :: unknown) :: Probe
				local header = assert(node:FindFirstChild("Header")) :: GuiObject
				body.ScrollBarThickness = 6
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteSize",
					engine.types.Vector2.new(180, 200)
				)
				engine.environment.poke(VerifyRoblox.assertInstance(body), "AbsoluteWindowSize", body.AbsoluteSize)
				engine.environment.poke(VerifyRoblox.assertInstance(body.Parent), "AbsoluteSize", body.AbsoluteSize)
				for _, label in node:GetDescendants() do
					if label.Name == "Undisclosed" then
						engine.environment.poke(VerifyRoblox.assertInstance(label), "TextFits", true)
					end
				end
				expect(header.Size.X.Offset):toBe(180)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(174, 200)
				)
				expect(header.Size.X.Offset):toBe(174)
				stop()
				runtime:dispose()
			end,
		})
	end)

	describe("Table row tap", function()
		it("a tap on a swipeable reorderable row selects it with a band and never starts a move", {
			id = "native_collections::Table row tap::a tap on a swipeable reorderable row selects it with a band and never starts a move",
			run = function()
				local engine, runtime, UI, target = setup()
				local E = engine.types.Enum
				local selection = Compose.cell({})
				local rating = 0
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: number, name: string }, number> = {
						from = { { id = 1, name = "Neon" }, { id = 2, name = "Drift" } },
						key = key,
						selection = selection,
						selectionMode = "multiple" :: "multiple",
						reorderable = true,
						onReorder = function() end,
						columns = {
							{ id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any>,
							{
								id = "rating",
								label = "Rating",
								width = 100,
								render = function(): GuiObject
									return UI.Button "Star" {
										label = "*",
										onActivate = function()
											rating += 1
										end,
									}
								end,
							} :: FixtureCollectionTypes.TableColumn<any, any>,
						},
						rowActions = function(): FixtureCollectionProps.RowActionsOptions?
							return {
								trailing = {
									{ id = "remove", label = "Remove", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
								},
							}
						end,
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(400, 200)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local function tap(rowKey: string, input: any?)
					local rowNode = body:FindFirstChild("Items"):FindFirstChild(rowKey)
					local grip = rowNode:FindFirstChild("SwipeGrip", true)
					if input then
						grip.InputBegan:Fire(input)
					end
					local detector = grip:FindFirstChildWhichIsA("UIDragDetector")
					detector.DragStart:Fire(engine.types.Vector2.new(150, 20))
					detector.DragEnd:Fire()
					return rowNode
				end
				local mouse = { UserInputType = E.UserInputType.MouseButton1, UserInputState = E.UserInputState.Begin }
				local first = tap("1", mouse)
				expect((selection:peek())):toEqual({ [1] = true })
				expect(rating):toBe(0)
				expect((node:FindFirstChild("DropFeedback", true))):toBeNil()
				expect((first:FindFirstChild("Reorderable", true):HasTag("facet-selected"))):toBe(true)
				local second = tap("2", mouse)
				expect((selection:peek())):toEqual({ [2] = true })
				expect((first:FindFirstChild("Reorderable", true):HasTag("facet-selected"))):toBe(false)
				expect((second:FindFirstChild("Reorderable", true):HasTag("facet-selected"))):toBe(true)
				stop()
				runtime:dispose()
			end,
		})
	end)

	describe("Row actions under a reorder drag", function()
		it("keeps horizontal swipes separate from reorder and disables the grip with owned Edit", {
			id = "native_collections::Row actions under a reorder drag::keeps horizontal swipes separate from reorder and disables the grip with owned Edit",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: number, name: string }, number> = {
						from = { { id = 1, name = "Neon" }, { id = 2, name = "Drift" } },
						key = key,
						itemSize = 40,
						reorderable = true,
						onReorder = function() end,
						columns = { { id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any> },
						rowActions = function(): FixtureCollectionProps.RowActionsOptions
							return { trailing = { { id = "remove", label = "Remove" } } }
						end,
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(VerifyRoblox.assertInstance(body), "AbsoluteWindowSize", V2.new(400, 200))
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local row = body:FindFirstChild("Items"):FindFirstChild("1")
				local grip = row:FindFirstChild("SwipeGrip", true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(grip.Parent.Parent),
					"AbsoluteSize",
					V2.new(400, 40)
				)
				engine.heartbeat:Fire(1)
				local press = { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(100, 20, 0) }
				nativeDrag.press(grip, press)
				local activation = require("../src/ui/activation")
				activation.drag(grip, "start", V2.new(100, 20))
				expect(activation.drag(grip, "move", V2.new(50, 22))):toBe(false)
				expect(node:FindFirstChild("DragImage", true)):toBeNil()
				nativeDrag.move(
					assert(ctx.config.userInputService),
					{ UserInputType = E.UserInputType.MouseMovement, Position = V3.new(50, 22, 0) }
				)
				expect(node:FindFirstChild("DragImage", true)):toBeNil()
				nativeDrag.finish(assert(ctx.config.userInputService), press)
				engine.environment.poke(
					VerifyRoblox.assertInstance(ctx.config.userInputService),
					"PreferredInput",
					E.PreferredInput.Touch
				)
				local edit = node:FindFirstChild("Edit", true)
				edit.Activated:Fire()
				expect(grip.Visible):toBe(false)
				edit.Activated:Fire()
				expect(grip.Visible):toBe(true)
				stop()
				runtime:dispose()
			end,
		})
		it("the drag image carries the row content without its open action tray", {
			id = "native_collections::Row actions under a reorder drag::the drag image carries the row content without its open action tray",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V3 = engine.types.Enum, engine.types.Vector3
				local opened = Compose.cell(nil :: ("leading" | "trailing")?)
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: number, name: string }, number> = {
						from = { { id = 1, name = "Neon" }, { id = 2, name = "Drift" }, { id = 3, name = "Apex" } },
						key = key,
						itemSize = 40,
						reorderable = true,
						onReorder = function() end,
						columns = { { id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any> },
						rowActions = function(_, rowKey): FixtureCollectionProps.RowActionsOptions?
							return {
								open = if rowKey == 1 then opened else nil,
								trailing = {
									{ id = "remove", label = "Remove", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
								},
							}
						end,
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(400, 200)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local rowNode = body:FindFirstChild("Items"):FindFirstChild("1")
				local grip = rowNode:FindFirstChild("SwipeGrip", true)
				local content = grip.Parent
				engine.environment.poke(
					VerifyRoblox.assertInstance(content.Parent),
					"AbsoluteSize",
					engine.types.Vector2.new(400, 40)
				)
				engine.heartbeat:Fire(1)
				opened:set("trailing")
				engine.heartbeat:Fire(1)
				expect(content.Parent:FindFirstChild("trailing").Visible):toBe(true)
				expect(content.Position.X.Offset < 0):toBe(true)
				local press = { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(100, 20, 0) }
				local dismiss = content:FindFirstChild("DismissTray")
				expect(dismiss.Visible):toBe(true)
				nativeDrag.press(dismiss, press)
				expect((opened:peek())):toBeNil()
				local input: any = assert(ctx.config.userInputService)
				nativeDrag.move(input, { UserInputType = E.UserInputType.MouseMovement, Position = V3.new(100, 60, 0) })
				local image = node:FindFirstChild("DragImage", true)
				expect(image ~= nil):toBe(true)
				local ghost = image:FindFirstChild("SwipeGrip", true).Parent
				expect((ghost.Parent:FindFirstChild("trailing"))):toBeNil()
				expect(ghost.Position.X.Offset):toBe(0)
				stop()
				runtime:dispose()
			end,
		})
	end)

	describe("Table selection after a pointer reorder", function()
		it("a plain click on another row after a drop selects only that row", {
			id = "native_collections::Table selection after a pointer reorder::a plain click on another row after a drop selects only that row",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				local rows =
					Compose.cell({ { id = 1, name = "Neon" }, { id = 2, name = "Drift" }, { id = 3, name = "Apex" } })
				local selection = Compose.cell({})
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: number, name: string }, number> = {
						from = rows,
						key = key,
						itemSize = 40,
						selection = selection,
						selectionMode = "multiple" :: "multiple",
						reorderable = true,
						onReorder = function(keys, slot: number)
							local list = {}
							for _, item in rows:peek() do
								if item.id ~= keys[1] then
									table.insert(list, item)
								end
							end
							table.insert(list, slot + 1, { id = keys[1], name = "moved" })
							rows:set(list)
						end,
						columns = { { id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any> },
						rowActions = function(): FixtureCollectionProps.RowActionsOptions?
							return {
								trailing = {
									{ id = "remove", label = "Remove", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
								},
							}
						end,
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(VerifyRoblox.assertInstance(body), "AbsoluteWindowSize", V2.new(400, 200))
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local input: any = assert(ctx.config.userInputService)
				local function grip(rowKey)
					return body:FindFirstChild("Items"):FindFirstChild(rowKey):FindFirstChild("SwipeGrip", true)
				end
				local function click(rowKey, y)
					local press = {
						UserInputType = E.UserInputType.MouseButton1,
						UserInputState = E.UserInputState.Begin,
						Position = V3.new(100, y, 0),
					}
					local g = grip(rowKey)
					g.InputBegan:Fire(press)
					local detector = g:FindFirstChildWhichIsA("UIDragDetector")
					detector.DragStart:Fire(V2.new(100, y))
					detector.DragEnd:Fire()
					press.UserInputState = E.UserInputState.End
					input.InputEnded:Fire(press)
				end
				click("3", 100)
				expect((selection:peek())):toEqual({ [3] = true })
				local press = {
					UserInputType = E.UserInputType.MouseButton1,
					UserInputState = E.UserInputState.Begin,
					Position = V3.new(100, 100, 0),
				}
				local g = grip("3")
				g.InputBegan:Fire(press)
				local detector = g:FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(V2.new(100, 100))
				for y = 90, 10, -20 do
					input.InputChanged:Fire({
						UserInputType = E.UserInputType.MouseMovement,
						Position = V3.new(100, y, 0),
					})
					detector.DragContinue:Fire(V2.new(100, y))
				end
				press.UserInputState = E.UserInputState.End
				press.Position = V3.new(100, 10, 0)
				input.InputEnded:Fire(press)
				detector.DragEnd:Fire()
				engine.heartbeat:Fire(1)
				expect(rows:peek()[1].id):toBe(3)
				click("2", 100)
				expect((selection:peek())):toEqual({ [2] = true })
				stop()
				runtime:dispose()
			end,
		})
	end)

	describe("live pointer reorder displacement", function()
		for _, layout in
			{
				"list",
				"horizontal list",
				"variable list",
				"horizontal variable list",
				"grid",
				"horizontal grid",
				"slotted rack",
				"horizontal slotted rack",
				"slotted grid",
				"horizontal slotted grid",
			}
		do
			for _, cancel in { false, true } do
				local name =
					`displaces two neighbours in a {layout} and settles after {if cancel then "cancel" else "drop"}`
				it(name, {
					id = `native_collections::live pointer reorder displacement::{name}`,
					run = function()
						for _, motion in { "normal", "none", "collection" } do
							local engine, runtime, UI, target =
								setup({ motionLevel = if motion == "none" then "none" else "normal" })
							local reduced = motion ~= "normal"
							local V2 = engine.types.Vector2
							local source = Compose.cell(records(4))
							local slots = Compose.cell({ 1, 9, 2, 3, 4 })
							local horizontal = string.find(layout, "horizontal", 1, true) ~= nil
							local variable = string.find(layout, "variable", 1, true) ~= nil
							local grid = string.find(layout, "grid", 1, true) ~= nil
							local slotted = string.find(layout, "slotted", 1, true) ~= nil
							local calls, requestSlot = 0, -1
							local requestKeys: { number } = {}
							local mounted: ScrollingFrame? = nil
							local stop = runtime.mount(function(): ScrollingFrame
								local spec: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> =
									{
										from = source,
										key = function(item: { id: number, label: string }): number
											return item.id
										end,
										itemSize = 20,
										measured = if variable then { [1] = 20, [2] = 40, [3] = 20, [4] = 20 } else nil,
										columns = if grid then 2 else nil,
										direction = if horizontal then "horizontal" else "vertical",
										slots = if slotted then slots else nil,
										reorderable = true,
										reducedMotion = motion == "collection",
										onReorder = function(keys: { number }, slot: number)
											calls += 1
											requestSlot, requestKeys = slot, keys

											local rows = table.clone(source:peek())
											local held = assert(table.remove(rows, 1))
											table.insert(rows, slot + 1, held)
											source:set(rows)
											if slotted then
												slots:set({ 2, 9, 3, 1, 4 })
											end
										end,
										render = function(): GuiObject
											return UI.Button { label = "Row" }
										end,
									}
								local collection = if grid then UI.VirtualGrid(spec) else UI.VirtualList(spec)
								mounted = collection
								return collection
							end, target)
							local node = assert(mounted)
							engine.environment.poke(
								VerifyRoblox.assertInstance(node),
								"AbsoluteWindowSize",
								V2.new(200, 200)
							)
							nativeDrag.measure(node, engine.environment)
							local first = assert(node:FindFirstChild("1", true))
							assert(first:IsA("GuiObject"))
							local second = assert(node:FindFirstChild("2", true))
							assert(second:IsA("GuiObject"))
							local third = assert(node:FindFirstChild("3", true))
							assert(third:IsA("GuiObject"))
							local fourth = assert(node:FindFirstChild("4", true))
							assert(fourth:IsA("GuiObject"))
							local firstRest, secondRest, thirdRest, fourthRest =
								first.Position, second.Position, third.Position, fourth.Position
							local thirdGoal = if variable
								then engine.types.UDim2.fromOffset(
									secondRest.X.Offset + (if horizontal then 20 else 0),
									secondRest.Y.Offset + (if horizontal then 0 else 20)
								)
								else secondRest
							local function point(position: UDim2): Vector2
								return V2.new(
									position.X.Offset + (if horizontal then 10 else if grid then 75 else 10),
									position.Y.Offset + (if horizontal and grid then 75 else 10)
								)
							end
							local detector = VerifyRoblox.assertInstance(
								assert(first:FindFirstChild("Move", true)):FindFirstChildWhichIsA("UIDragDetector")
							)
							engine.environment.fire(detector, "DragStart", point(firstRest))
							engine.environment.fire(detector, "DragContinue", point(thirdRest))
							expect(calls):toBe(0)
							expect(source:peek()[1].id):toBe(1)
							if reduced then
								expect(second.Position):toBe(firstRest)
								expect(third.Position):toBe(thirdGoal)
							else
								expect(second.Position):toBe(secondRest)
								expect(third.Position):toBe(thirdRest)
								engine.heartbeat:Fire(1 / 60)
								expect(second.Position ~= secondRest and second.Position ~= firstRest):toBe(true)
								expect(third.Position ~= thirdRest and third.Position ~= thirdGoal):toBe(true)
							end
							for _ = 1, 90 do
								engine.heartbeat:Fire(1 / 60)
							end
							expect(second.Position):toBe(firstRest)
							expect(third.Position):toBe(thirdGoal)
							expect(fourth.Position):toBe(fourthRest)
							if cancel then
								engine.environment.fire(
									VerifyRoblox.assertInstance(
										assert(target:FindFirstChild("FacetReorderCancel")):FindFirstChild(
											"ReorderCancel"
										)
									),
									"Pressed"
								)
							else
								engine.environment.fire(detector, "DragEnd")
							end
							if reduced then
								expect(second.Position):toBe(if cancel then secondRest else firstRest)
							elseif cancel then
								engine.heartbeat:Fire(1 / 60)
								expect(second.Position ~= firstRest and second.Position ~= secondRest):toBe(true)
							end
							for _ = 1, 90 do
								engine.heartbeat:Fire(1 / 60)
							end
							expect(calls):toBe(if cancel then 0 else 1)
							expect(requestSlot):toBe(if cancel then -1 else 2)
							expect(requestKeys):toEqual(if cancel then {} else { 1 })
							local order = {}
							for _, item in source:peek() do
								table.insert(order, item.id)
							end
							expect(order):toEqual(if cancel then { 1, 2, 3, 4 } else { 2, 3, 1, 4 })
							expect(first.Position):toBe(if cancel then firstRest else thirdRest)
							expect(second.Position):toBe(if cancel then secondRest else firstRest)
							expect(third.Position):toBe(if cancel then thirdRest else thirdGoal)
							expect(fourth.Position):toBe(fourthRest)
							stop()
							runtime:dispose()
						end
					end,
				})
			end
		end
	end)

	describe("Table keyed reorder motion", function()
		it("a Table glides its rows to a reversed order like VirtualList", {
			id = "native_collections::Table keyed reorder motion::a Table glides its rows to a reversed order like VirtualList",
			run = function()
				local engine, runtime, UI, target = setup({ motionLevel = "normal" })
				local rows = Compose.cell({ { id = 1, name = "A" }, { id = 2, name = "B" }, { id = 3, name = "C" } })
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: number, name: string }, number> = {
						from = rows,
						key = key,
						itemSize = 40,
						columns = { { id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any> },
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(400, 300)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				engine.heartbeat:Fire(1 / 60)
				local first = body:FindFirstChild("Items"):FindFirstChild("1")
				local before = first.Position.Y.Offset
				rows:set({ rows:peek()[3], rows:peek()[2], rows:peek()[1] })
				engine.heartbeat:Fire(0.05)
				local during = first.Position.Y.Offset
				for _ = 1, 30 do
					engine.heartbeat:Fire(1 / 60)
				end
				local after = first.Position.Y.Offset
				expect(after > before):toBe(true)
				expect(during > before and during < after):toBe(true)
				stop()
				runtime:dispose()
			end,
		})
	end)

	describe("Row action tray width", function()
		it("an icon action's tray fits its painted icon and keeps the label as its name", {
			id = "native_collections::Row action tray width::an icon action's tray fits its painted icon and keeps the label as its name",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, actions: any = runtime.mount(function()
					return UI.RowActions {
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						open = Compose.cell("trailing" :: "leading" | "trailing" | nil) :: FixtureComposeTypes.Value<FixtureCollectionTypes.RowEdge?>,
						trailing = {
							{ id = "remove", label = "Remove", icon = "trash", role = "destructive" :: "destructive" } :: FixtureCollectionTypes.RowAction,
						},
					}
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(actions),
					"AbsoluteSize",
					engine.types.Vector2.new(500, 40)
				)
				local remove = actions:FindFirstChild("remove", true)
				expect((remove:GetAttribute("label"))):toBe("Remove")
				expect((remove:HasTag("facet-row-action"))):toBe(true)
				expect(actions:FindFirstChild("trailing").Size.X.Offset):toBe(math.max(64, 32 + 20 + 8))
				stop()
				runtime:dispose()
			end,
		})
	end)

	describe("editable collections: reorderable and deletable on every input", function()
		local function editableWorld(input: string, spec: { [string]: any }, list: boolean?)
			local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
			local service: any = assert(ctx.config.userInputService)
			engine.environment.poke(
				VerifyRoblox.assertInstance(service),
				"PreferredInput",
				engine.types.Enum.PreferredInput:FromName(input)
			)
			local reorders, deletes = {}, {}
			local selection = Compose.cell(spec.selected or {})
			local base: { [any]: any } = {
				from = records(4),
				key = key,
				itemSize = 40,
				selection = selection,
				selectionMode = "multiple" :: "multiple",
				onReorder = function(keys: { number }, slot: number)
					table.insert(reorders, { keys = keys, slot = slot })
				end,
				onDelete = function(keys: { number })
					table.insert(deletes, keys)
				end,
			}
			for field, value in spec do
				if field ~= "selected" then
					base[field] = value
				end
			end
			if list then
				base.render = function(current): GuiObject
					return button(UI, current)
				end
			else
				base.columns = { { id = "label", label = "Label", width = 100 } }
			end
			local stop, node: any = runtime.mount(function()
				local buildList: (FixtureCollectionProps.KeyedCollectionSpec<Record, number>, string?) -> ScrollingFrame =
					UI.VirtualList
				local buildTable: (FixtureCollectionProps.KeyedTableSpec<Record, number>, string?) -> Frame = UI.Table
				return if list then buildList(base) else buildTable(base)
			end, target)
			local body = if list then node else node:FindFirstChild("Body")
			engine.environment.poke(
				VerifyRoblox.assertInstance(body),
				"AbsoluteWindowSize",
				engine.types.Vector2.new(300, 200)
			)
			engine.environment.poke(VerifyRoblox.assertInstance(body.Parent), "AbsoluteSize", body.AbsoluteWindowSize)
			local function pressed(name: string)
				target:FindFirstChild("Facet" .. name):FindFirstChild(name).Pressed:Fire()
			end
			local function row(rowKey)
				return body:FindFirstChild(tostring(rowKey), true)
			end
			return {
				engine = engine,
				gui = gui,
				service = service,
				node = node,
				body = body,
				row = row,
				pressed = pressed,
				reorders = reorders,
				deletes = deletes,
				selection = selection,
				stop = function()
					stop()
					runtime:dispose()
				end,
			}
		end

		it("a pointer drags a row (or the selected rows) to reorder with no handle on show", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a pointer drags a row (or the selected rows) to reorder with no handle on show",
			run = function()
				for _, list in { false, true } do
					local w = editableWorld("KeyboardAndMouse", { reorderable = true }, list)
					local V2 = w.engine.types.Vector2
					expect((w.row(2):FindFirstChild("Move", true))):toBeNil()
					expect(w.row(2):FindFirstChild("Cells", true).Position.X.Offset):toBe(0)
					local hit = w.row(2):FindFirstChild("RowHit", true)
					nativeDrag.press(hit, {
						UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
						Position = V2.new(10, 50),
					})
					nativeDrag.move(w.service, {
						UserInputType = w.engine.types.Enum.UserInputType.MouseMovement,
						UserInputState = w.engine.types.Enum.UserInputState.Change,
						Position = V2.new(10, 52),
					})
					expect((w.node:FindFirstChild("DropLine", true))):toBeNil()
					nativeDrag.move(w.service, {
						UserInputType = w.engine.types.Enum.UserInputType.MouseMovement,
						UserInputState = w.engine.types.Enum.UserInputState.Change,
						Position = V2.new(10, 150),
					})
					expect(w.node:FindFirstChild("DropLine", true) ~= nil):toBe(true)
					local image = w.node:FindFirstChild("DragImage", true)
					local copy = image:FindFirstChild("Reorderable")
					expect(copy ~= nil):toBe(true)
					local original = w.row(2):FindFirstChild("Reorderable", true)
					for _, part in copy:GetDescendants() do
						if part:IsA("GuiObject") then
							expect(part.ZIndex > original.ZIndex):toBe(true)
							expect(part.Interactable or part.Active or part.Selectable):toBe(false)
						end
					end
					expect(w.node:FindFirstChild("ReorderFeedback", true).ZIndex > w.row(2).ZIndex):toBe(true)
					if list then
						expect(copy:FindFirstChild("Action", true).Text):toBe("2")
						expect((copy:FindFirstChild("Action", true):HasTag("facet-button"))):toBe(true)
					end
					nativeDrag.finish(w.service, {
						UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
						UserInputState = w.engine.types.Enum.UserInputState.End,
					})
					expect(#w.reorders):toBe(1)
					expect(w.reorders[1].keys):toEqual({ 2 })
					w.stop()
				end
			end,
		})

		it("completes a fast native row drag without an intermediate drag event", {
			id = "native_collections::editable collections: reorderable and deletable on every input::completes a fast native row drag without an intermediate drag event",
			run = function()
				local w = editableWorld("KeyboardAndMouse", { reorderable = true }, true)
				local V2 = w.engine.types.Vector2
				local detector = w.row(2):FindFirstChild("FacetCollectionDrag", true)
				detector.DragStart:Fire(V2.new(10, 50))
				detector.DragEnd:Fire(V2.new(10, 150))
				expect(#w.reorders):toBe(1)
				expect(w.reorders[1].keys):toEqual({ 2 })
				w.stop()
			end,
		})

		it("a row dragged away and back to its own slot keeps the selection and activates nothing", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a row dragged away and back to its own slot keeps the selection and activates nothing",
			run = function()
				local w = editableWorld(
					"KeyboardAndMouse",
					{ reorderable = true, selected = { [1] = true, [2] = true } },
					false
				)
				local V2, E = w.engine.types.Vector2, w.engine.types.Enum
				local hit = w.row(2):FindFirstChild("RowHit", true)
				local press = { UserInputType = E.UserInputType.MouseButton1, Position = V2.new(10, 50) }
				nativeDrag.press(hit, press)
				for _, y in { 150, 50 } do
					nativeDrag.move(w.service, {
						UserInputType = E.UserInputType.MouseMovement,
						UserInputState = E.UserInputState.Change,
						Position = V2.new(10, y),
					})
				end
				nativeDrag.finish(w.service, press)
				hit.Activated:Fire(press, 0)
				expect((w.selection:peek())):toEqual({ [1] = true, [2] = true })
				nativeDrag.press(w.service, press)
				hit.Activated:Fire(press, 0)
				expect((w.selection:peek())):toEqual({ [2] = true })
				w.stop()
			end,
		})

		it("Delete, Backspace and the X button remove the selected deletable rows through onDelete", {
			id = "native_collections::editable collections: reorderable and deletable on every input::Delete, Backspace and the X button remove the selected deletable rows through onDelete",
			run = function()
				for _, list in { false, true } do
					local w = editableWorld(
						"KeyboardAndMouse",
						{ deletable = true, selected = { [3] = true, [1] = true } },
						list
					)
					w.pressed("DeleteRows")
					expect(w.deletes):toEqual({ { 1, 3 } })
					w.stop()
					local fixed = editableWorld("KeyboardAndMouse", { selected = { [2] = true } }, list)
					local engine = fixed.engine
					expect((fixed.node.Parent:FindFirstChild("FacetDeleteRows"))):toBeNil()
					fixed.stop()
					local _ = engine
				end
			end,
		})

		it("in edit mode X deletes the row that holds the pad selection when nothing is selected", {
			id = "native_collections::editable collections: reorderable and deletable on every input::in edit mode X deletes the row that holds the pad selection when nothing is selected",
			run = function()
				for _, list in { false, true } do
					local w = editableWorld("Gamepad", { deletable = true, editing = Compose.cell(true) }, list)
					local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
					local target = if hit.Selectable then hit else hit:FindFirstChildWhichIsA("GuiButton", true)
					w.gui.SelectedObject = target
					expect(w.gui.SelectedObject ~= nil):toBe(true)
					w.pressed("DeleteRows")
					expect(w.deletes):toEqual({ { 2 } })
					w.stop()
				end
			end,
		})

		it("touch and gamepad multi-select in Edit: marks, a tap or A toggles a row, Delete removes them", {
			id = "native_collections::editable collections: reorderable and deletable on every input::touch and gamepad multi-select in Edit: marks, a tap or A toggles a row, Delete removes them",
			run = function()
				for _, input in { "Touch", "Gamepad" } do
					local activated = {}
					local w = editableWorld(input, {
						reorderable = true,
						deletable = true,
						onActivate = function(_, rowKey)
							table.insert(activated, rowKey)
						end,
					}, false)
					local E = w.engine.types.Enum
					local press = if input == "Touch"
						then { UserInputType = E.UserInputType.Touch }
						else { UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }
					local edit = w.node:FindFirstChild("Edit", true)
					expect(edit ~= nil and edit.Text == "Edit"):toBe(true)
					expect((edit:HasTag("facet-appearance-utility"))):toBe(false)
					expect((w.row(1):FindFirstChild("Move", true))):toBeNil()
					expect((w.row(1):FindFirstChild("Minus", true))):toBeNil()
					expect(w.row(1):FindFirstChild("SelectMark", true).Visible):toBe(false)
					edit.Activated:Fire()
					expect(edit.Text):toBe("Done")
					local move, mark =
						w.row(1):FindFirstChild("Move", true), w.row(1):FindFirstChild("SelectMark", true)
					expect(move.Visible and move.AnchorPoint.X == 1 and move.Position.X.Scale == 1):toBe(true)
					expect(mark.Visible and mark.Position.X.Scale == 0):toBe(true)
					local cells = w.row(1):FindFirstChild("Cells", true)
					expect(cells.Position.X.Offset):toBe(44)
					expect(cells.Size.X.Offset):toBe(-88)
					expect((cells.Parent:HasTag("facet-tablerow"))):toBe(true)
					local delete = w.node:FindFirstChild("DeleteSelected", true)
					expect(delete.Visible):toBe(input == "Touch")
					expect(w.node:FindFirstChild("PadHints", true).Visible):toBe(input == "Gamepad")
					expect(delete.Interactable):toBe(false)
					w.row(1):FindFirstChild("RowHit", true).Activated:Fire(press, 1)
					w.row(3):FindFirstChild("RowHit", true).Activated:Fire(press, 1)
					expect((w.selection:peek())):toEqual({ [1] = true, [3] = true })
					expect(mark:FindFirstChild("Check").Visible):toBe(true)
					w.row(3):FindFirstChild("RowHit", true).Activated:Fire(press, 1)
					w.row(4):FindFirstChild("RowHit", true).Activated:Fire(press, 1)
					expect((w.selection:peek())):toEqual({ [1] = true, [4] = true })
					expect(activated):toEqual({})
					if input == "Touch" then
						expect(delete.Interactable):toBe(true)
						delete.Activated:Fire(press)
					else
						w.pressed("DeleteRows")
					end
					expect(w.deletes):toEqual({ { 1, 4 } })
					edit.Activated:Fire()
					expect(mark.Visible):toBe(false)
					w.row(2):FindFirstChild("RowHit", true).Activated:Fire(press, 1)
					expect(activated):toEqual({ 2 })
					w.stop()
				end
				local pointer = editableWorld("KeyboardAndMouse", { reorderable = true, deletable = true }, false)
				expect((pointer.node:FindFirstChild("Edit", true))):toBeNil()
				pointer.stop()
			end,
		})

		it("a List in edit mode marks its rows and a tap toggles one without activating it", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a List in edit mode marks its rows and a tap toggles one without activating it",
			run = function()
				local activated, editing = {}, Compose.cell(true)
				local w = editableWorld("Touch", {
					deletable = true,
					editing = editing,
					onActivate = function(_, rowKey)
						table.insert(activated, rowKey)
					end,
				}, true)
				local touch = { UserInputType = w.engine.types.Enum.UserInputType.Touch }
				expect(w.row(2):FindFirstChild("SelectMark", true).Visible):toBe(true)
				expect((w.row(2):FindFirstChild("Minus", true))):toBeNil()
				w.row(2):FindFirstChild("RowHit", true).Activated:Fire(touch, 1)
				w.row(3):FindFirstChild("RowHit", true).Activated:Fire(touch, 1)
				expect((w.selection:peek())):toEqual({ [2] = true, [3] = true })
				expect(activated):toEqual({})
				w.pressed("DeleteRows")
				expect(w.deletes):toEqual({ { 2, 3 } })
				editing:set(false)
				w.row(1):FindFirstChild("RowHit", true).Activated:Fire(touch, 1)
				expect(activated):toEqual({ 1 })
				w.stop()
			end,
		})

		it("the focused-row fallback for Delete looks only inside its own collection", {
			id = "native_collections::editable collections: reorderable and deletable on every input::the focused-row fallback for Delete looks only inside its own collection",
			run = function()
				local w = editableWorld("KeyboardAndMouse", { deletable = true, editing = Compose.cell(true) }, false)
				local crowd = w.engine.new("Frame")
				local outside = w.engine.new("TextButton")
				outside.Parent = crowd
				crowd.Parent = w.node.Parent
				w.gui.SelectedObject = outside
				w.pressed("DeleteRows")
				expect(w.deletes):toEqual({})
				w.gui.SelectedObject = w.row(2):FindFirstChildWhichIsA("GuiButton", true) or w.row(2)
				w.pressed("DeleteRows")
				expect(w.deletes):toEqual({ { 2 } })
				w.stop()
			end,
		})

		it("the toolbar Delete acts on the selection only; the focused-row fallback belongs to the key", {
			id = "native_collections::editable collections: reorderable and deletable on every input::the toolbar Delete acts on the selection only; the focused-row fallback belongs to the key",
			run = function()
				local w = editableWorld("Touch", { reorderable = true, deletable = true }, false)
				w.node:FindFirstChild("Edit", true).Activated:Fire()
				local delete = w.node:FindFirstChild("DeleteSelected", true)
				local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
				w.gui.SelectedObject = if hit.Selectable then hit else hit:FindFirstChildWhichIsA("GuiButton", true)
				expect(w.gui.SelectedObject):toBeNil()
				expect(delete.Interactable):toBe(false)
				delete.Activated:Fire({ UserInputType = w.engine.types.Enum.UserInputType.Touch })
				expect(w.deletes):toEqual({})
				w.engine.environment.poke(
					VerifyRoblox.assertInstance(w.service),
					"PreferredInput",
					w.engine.types.Enum.PreferredInput.KeyboardAndMouse
				)
				w.gui.SelectedObject = if hit.Selectable then hit else hit:FindFirstChildWhichIsA("GuiButton", true)
				expect(w.gui.SelectedObject ~= nil):toBe(true)
				expect(delete.Interactable):toBe(false)
				w.pressed("DeleteRows")
				expect(w.deletes):toEqual({ { 2 } })
				w.stop()
			end,
		})

		it("a single-selection List in edit mode toggles its one row: a tap on the chosen row clears it", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a single-selection List in edit mode toggles its one row: a tap on the chosen row clears it",
			run = function()
				local activated = {}
				local w = editableWorld("Touch", {
					selectionMode = "single" :: "single",
					editing = Compose.cell(true),
					onActivate = function(_, rowKey)
						table.insert(activated, rowKey)
					end,
				}, true)
				local touch = { UserInputType = w.engine.types.Enum.UserInputType.Touch }
				w.row(2):FindFirstChild("RowHit", true).Activated:Fire(touch, 1)
				expect((w.selection:peek())):toEqual({ [2] = true })
				w.row(3):FindFirstChild("RowHit", true).Activated:Fire(touch, 1)
				expect((w.selection:peek())):toEqual({ [3] = true })
				w.row(3):FindFirstChild("RowHit", true).Activated:Fire(touch, 1)
				expect((w.selection:peek())):toEqual({})
				expect(activated):toEqual({})
				w.stop()
			end,
		})

		it("a handle drag always drops on DragEnd, even when the detector starts before the handle's press", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a handle drag always drops on DragEnd, even when the detector starts before the handle's press",
			run = function()
				local w = editableWorld("Touch", { reorderable = true, editing = Compose.cell(true) }, false)
				local E, V2, V3 = w.engine.types.Enum, w.engine.types.Vector2, w.engine.types.Vector3
				local function drag(rowKey, from, to, pressFirst)
					local handle = w.row(rowKey):FindFirstChild("Move", true)
					local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
					local touch = {
						UserInputType = E.UserInputType.Touch,
						UserInputState = E.UserInputState.Begin,
						Position = V3.new(280, from, 0),
					}
					if pressFirst then
						handle.InputBegan:Fire(touch)
					end
					detector.DragStart:Fire(V2.new(280, from))
					if not pressFirst then
						handle.InputBegan:Fire(touch)
					end
					detector.DragContinue:Fire(V2.new(280, to))
					detector.DragEnd:Fire()
					touch.UserInputState = E.UserInputState.End
					w.service.InputEnded:Fire(touch)
				end
				drag(1, 20, 100, true)
				expect(#w.reorders):toBe(1)
				drag(4, 140, 20, false)
				expect(#w.reorders):toBe(2)
				expect((w.node:FindFirstChild("DragImage", true))):toBeNil()
				expect((w.row(4):FindFirstChild("Reorderable", true):GetAttribute("FacetDragging"))):toBe(false)
				w.stop()
			end,
		})

		it("the drag image stays over the rows, never over the Edit toolbar or the header", {
			id = "native_collections::editable collections: reorderable and deletable on every input::the drag image stays over the rows, never over the Edit toolbar or the header",
			run = function()
				local w = editableWorld("Touch", { reorderable = true }, false)
				local V2 = w.engine.types.Vector2
				w.node:FindFirstChild("Edit", true).Activated:Fire()
				local detector = w.row(3):FindFirstChild("Move", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(V2.new(280, 100))
				detector.DragContinue:Fire(V2.new(280, -200))
				local image = w.node:FindFirstChild("DragImage", true)
				local top = w.body.Position.Y.Offset
				expect(top > 0):toBe(true)
				expect(image.Position.Y.Offset):toBe(top)
				detector.DragContinue:Fire(V2.new(280, 900))
				expect(image.Position.Y.Offset):toBe(top + 200 - 40)
				detector.DragEnd:Fire()
				w.stop()
			end,
		})

		it("a held finger on a Table row that has an Edit mode scrolls instead of picking the row up", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a held finger on a Table row that has an Edit mode scrolls instead of picking the row up",
			run = function()
				local w = editableWorld("Touch", { reorderable = true }, false)
				local E, V3 = w.engine.types.Enum, w.engine.types.Vector3
				local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
				hit.InputBegan:Fire({ UserInputType = E.UserInputType.Touch, Position = V3.new(50, 60, 0) })
				for _ = 1, 30 do
					w.engine.heartbeat:Fire(1 / 60)
				end
				expect((w.node:FindFirstChild("DragImage", true))):toBeNil()
				expect(w.body.ScrollingEnabled):toBe(true)
				w.stop()
			end,
		})

		it("a list handed editing = false keeps touch hold-to-reorder", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a list handed editing = false keeps touch hold-to-reorder",
			run = function()
				local w = editableWorld("Touch", { reorderable = true, editing = false }, true)
				local E, V3 = w.engine.types.Enum, w.engine.types.Vector3
				local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
				hit.InputBegan:Fire({ UserInputType = E.UserInputType.Touch, Position = V3.new(50, 60, 0) })
				for _ = 1, 30 do
					w.engine.heartbeat:Fire(1 / 60)
				end
				w.row(2)
					:FindFirstChild("Reorderable", true).TouchLongPress
					:Fire({ w.engine.types.Vector2.new(50, 60) }, E.UserInputState.Begin)
				expect(w.node:FindFirstChild("DragImage", true) ~= nil):toBe(true)
				w.stop()
			end,
		})

		it("columns that cannot fit beside the edit controls scroll inside a pinned lane, never clip", {
			id = "native_collections::editable collections: reorderable and deletable on every input::columns that cannot fit beside the edit controls scroll inside a pinned lane, never clip",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local V2 = engine.types.Vector2
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					engine.types.Enum.PreferredInput.Touch
				)
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> = {
						from = records(3),
						key = key,
						itemSize = 44,
						reorderable = true,
						deletable = true,
						onReorder = function() end,
						onDelete = function() end,
						columns = {
							{ id = "name", label = "Name", minWidth = 90 } :: FixtureCollectionTypes.TableColumn<any, any>,
							{ id = "artist", label = "Artist", minWidth = 72 } :: FixtureCollectionTypes.TableColumn<any, any>,
							{ id = "rating", label = "Rating", width = 144 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(VerifyRoblox.assertInstance(body), "AbsoluteWindowSize", V2.new(359, 200))
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local header = node:FindFirstChild("Header")
				for _, label in node:GetDescendants() do
					if label.Name == "Undisclosed" then
						engine.environment.poke(VerifyRoblox.assertInstance(label), "TextFits", true)
					end
				end
				expect(header.Size.X.Offset):toBe(359)
				node:FindFirstChild("Edit", true).Activated:Fire()
				expect(header.Size.X.Offset):toBe(271)
				expect(header:FindFirstChild("name"):FindFirstChildWhichIsA("UISizeConstraint").MinSize.X):toBe(90)
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					engine.types.Enum.PreferredInput.KeyboardAndMouse
				)
				expect(header.Size.X.Offset):toBe(271)
				engine.environment.poke(
					VerifyRoblox.assertInstance(header:FindFirstChildWhichIsA("UIListLayout")),
					"AbsoluteContentSize",
					V2.new(306, 44)
				)
				expect(header.CanvasSize.X.Offset):toBe(306)
				expect(body.CanvasSize.X.Offset):toBe(306 + 88)
				local lane = body:FindFirstChild("1", true):FindFirstChild("Row", true)
				local painted = lane:FindFirstAncestorWhichIsA("Frame")
				while not painted:HasTag("facet-tablerow") do
					painted = painted.Parent
				end
				expect(lane.Size.X.Offset):toBe(306)
				body.CanvasPosition = V2.new(35, 0)
				expect(header.CanvasPosition.X):toBe(35)
				expect(lane.Position.X.Offset):toBe(-35)
				expect(painted.Position.X.Offset):toBe(35)
				expect(lane.Parent.ClipsDescendants):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		it("a touch cell wraps only at word boundaries and truncates when one word cannot fit", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a touch cell wraps only at word boundaries and truncates when one word cannot fit",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					engine.types.Enum.PreferredInput.Touch
				)
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: number, name: string }, number> = {
						from = { { id = 1, name = "Neon Straightaway MMMM illlllll" } },
						key = key,
						columns = { { id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any> },
					}
					return UI.Table(tableSpec)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(300, 200)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(body.Parent),
					"AbsoluteSize",
					body.AbsoluteWindowSize
				)
				local cell = body:FindFirstChild("1", true):FindFirstChild("name", true)
				local value, word = cell:FindFirstChild("Value"), cell:FindFirstChild("LongestWord")
				expect(word.Text):toBe("Neon\nStraightaway\nMMMM\nilllllll")
				expect(word.TextWrapped):toBe(false)
				expect(word.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
				expect(value.TextTruncate):toBe(engine.types.Enum.TextTruncate.AtEnd)
				engine.environment.poke(VerifyRoblox.assertInstance(word), "TextFits", true)
				expect(value.TextWrapped):toBe(true)
				engine.environment.poke(VerifyRoblox.assertInstance(word), "TextFits", false)
				expect(value.TextWrapped):toBe(false)
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					engine.types.Enum.PreferredInput.KeyboardAndMouse
				)
				engine.environment.poke(VerifyRoblox.assertInstance(word), "TextFits", true)
				expect(value.TextWrapped):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		it("touch flexible columns keep their column minimum and scroll sideways instead of shrinking to nothing", {
			id = "native_collections::editable collections: reorderable and deletable on every input::touch flexible columns keep their column minimum and scroll sideways instead of shrinking to nothing",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local V2 = engine.types.Vector2
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					engine.types.Enum.PreferredInput.Touch
				)
				local columns: { FixtureCollectionTypes.TableColumn<Record, number> } = {}
				for index = 1, 6 do
					table.insert(columns, { id = `c{index}`, label = `Column {index}` })
				end
				local stop, node: any = runtime.mount(function()
					local tableSpec: FixtureCollectionProps.KeyedTableSpec<Record, number> =
						{ from = records(3), key = key, itemSize = 44, columns = columns }
					return UI.Table(tableSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node:FindFirstChild("Body")),
					"AbsoluteWindowSize",
					V2.new(200, 200)
				)
				local header = node:FindFirstChild("Header")
				for _, label in node:GetDescendants() do
					if label.Name == "Undisclosed" then
						engine.environment.poke(VerifyRoblox.assertInstance(label), "TextFits", true)
					end
				end
				expect(header.Size.X.Offset):toBe(200)
				engine.environment.poke(
					VerifyRoblox.assertInstance(header:FindFirstChildWhichIsA("UIListLayout")),
					"AbsoluteContentSize",
					V2.new(6 * 48, 44)
				)
				expect(header.CanvasSize.X.Offset):toBe(6 * 48)
				for index = 1, 6 do
					expect(header:FindFirstChild(`c{index}`):FindFirstChildWhichIsA("UISizeConstraint").MinSize.X):toBe(
						48
					)
				end
				stop()
				runtime:dispose()
			end,
		})

		it("the shoulder buttons move the selected rows by one slot", {
			id = "native_collections::editable collections: reorderable and deletable on every input::the shoulder buttons move the selected rows by one slot",
			run = function()
				local w = editableWorld("Gamepad", { reorderable = true, selected = { [2] = true } }, false)
				w.pressed("MoveRowsLater")
				expect(w.reorders):toEqual({ { keys = { 2 }, slot = 2 } })
				w.pressed("MoveRowsEarlier")
				expect(w.reorders[2]):toEqual({ keys = { 2 }, slot = 0 })
				w.stop()
			end,
		})

		it("a shoulder move in edit mode keeps the pad selection on the moved row", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a shoulder move in edit mode keeps the pad selection on the moved row",
			run = function()
				for _, list in { false, true } do
					local w = editableWorld("Gamepad", { reorderable = true, editing = Compose.cell(true) }, list)
					local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
					local target = if hit.Selectable then hit else hit:FindFirstChildWhichIsA("GuiButton", true)
					w.gui.SelectedObject = target
					w.pressed("MoveRowsLater")
					expect(#w.reorders):toBe(1)
					expect(w.gui.SelectedObject):toBe(target)
					w.stop()
				end
			end,
		})
	end)

	describe("shared container editing", function()
		it("replaces plain selection and toggles only in explicit edit mode across all containers", {
			id = "native_collections::shared container editing::replaces plain selection and toggles only in explicit edit mode across all containers",
			run = function()
				for _, kind in { "VirtualList", "VirtualGrid", "Table" } do
					local engine, runtime, UI, target = setup()
					local selection, editing = Compose.cell({}), Compose.cell(false)
					local stop, node: any = runtime.mount(function()
						local spec: any = {
							from = records(3),
							key = key,
							selection = selection,
							selectionMode = "multiple",
							editing = editing,
							mode = "all" :: "all",
							render = function(): GuiObject
								return Facet.host(runtime).Frame({})
							end,
						}
						if kind == "Table" then
							spec.columns = { { id = "label", label = "Label", width = 100 } }
							spec.mode, spec.render = nil, nil
						end
						if kind == "Table" then
							local build: (FixtureCollectionProps.KeyedTableSpec<Record, number>, string?) -> Frame =
								UI.Table
							return build(spec)
						end
						if kind == "VirtualGrid" then
							local build: (FixtureCollectionProps.KeyedCollectionSpec<Record, number>, string?) -> ScrollingFrame =
								UI.VirtualGrid
							return build(spec)
						end
						local build: (FixtureCollectionProps.KeyedCollectionSpec<Record, number>, string?) -> ScrollingFrame =
							UI.VirtualList
						return build(spec)
					end, target)
					local body = if kind == "Table" then node:FindFirstChild("Body") else node
					engine.environment.poke(
						VerifyRoblox.assertInstance(body),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(300, 200)
					)
					local inputs: { Enum.UserInputType | boolean } = {
						engine.types.Enum.UserInputType.Touch,
						engine.types.Enum.UserInputType.Gamepad1,
						engine.types.Enum.UserInputType.Keyboard,
						engine.types.Enum.UserInputType.MouseButton1,
						false,
					}
					for _, inputType in inputs do
						local input = if inputType then { UserInputType = inputType } else nil
						local function tap(id: number)
							body:FindFirstChild(tostring(id), true)
								:FindFirstChild("RowHit", true).Activated
								:Fire(input, 0)
						end
						selection:set({})
						tap(1)
						tap(2)
						expect((selection:peek())):toEqual({ [2] = true })
						tap(2)
						expect((selection:peek())):toEqual({ [2] = true })
						editing:set(true)
						tap(1)
						expect((selection:peek())):toEqual({ [1] = true, [2] = true })
						tap(2)
						expect((selection:peek())):toEqual({ [1] = true })
						editing:set(false)
						expect((selection:peek())):toEqual({ [1] = true })
						tap(3)
						expect((selection:peek())):toEqual({ [3] = true })
					end
					stop()
					runtime:dispose()
				end
			end,
		})

		it("keeps rejected drafts through remount and cancels to the latest model value", {
			id = "native_collections::shared container editing::keeps rejected drafts through remount and cancels to the latest model value",
			run = function()
				local engine, runtime, UI, target = setup()
				local value, draft = Compose.cell("Alpha"), Compose.cell(nil :: FixtureCollectionTypes.CellDraft?)
				local accept, commits = false, 0
				local function mount()
					local stop, node: any = runtime.mount(function()
						return UI.CellEditor {
							editor = "text" :: "text",
							value = value,
							draft = draft,
							validate = function(v)
								return if v == "" then "Required" else nil
							end,
							onChange = function(v: any)
								commits += 1
								if accept then
									value:set(v)
								end
							end,
						}
					end, target)
					require("../src/ui/activation").edits(node)[1].onActivate()
					return stop, node:FindFirstChildWhichIsA("TextBox", true)
				end
				local stop, field = mount()
				field.Focused:Fire()
				field.Text = "Beta"
				field.FocusLost:Fire(true)
				expect(commits):toBe(1)
				expect((value:peek())):toBe("Alpha")
				expect(assert(draft:peek()).text):toBe("Beta")
				expect(assert(draft:peek()).error ~= nil):toBe(true)
				stop()
				stop, field = mount()
				expect(field.Text):toBe("Beta")
				value:set("Remote")
				expect(field.Text):toBe("Beta")
				field.Focused:Fire()
				field.FocusLost:Fire(false, { KeyCode = engine.types.Enum.KeyCode.Escape })
				expect((draft:peek())):toBe(nil)
				expect(field.Text):toBe("Remote")
				accept = true
				field.Focused:Fire()
				field.Text = "Saved"
				field.FocusLost:Fire(true)
				expect((value:peek())):toBe("Saved")
				expect((draft:peek())):toBe(nil)
				stop()
			end,
		})

		it("does not focus an editing field outside its ancestor clipping window", {
			id = "native_collections::shared container editing::does not focus an editing field outside its ancestor clipping window",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local clip = engine.new("Frame")
				clip.Parent = target
				clip.ClipsDescendants = true
				engine.environment.poke(
					VerifyRoblox.assertInstance(clip),
					"AbsolutePosition",
					engine.types.Vector2.zero
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(clip),
					"AbsoluteSize",
					engine.types.Vector2.new(430, 874)
				)
				local editing = Compose.cell(false)
				local stop, mounted = runtime.mount(function()
					return UI.CellEditor {
						editor = "text" :: "text",
						value = "Coast",
						editing = editing,
						onChange = function() end,
					}
				end, clip)
				local node = mounted :: Frame
				editing:set(true)
				local field = assert(node:FindFirstChildWhichIsA("TextBox", true)) :: TextBox
				editing:set(false)
				gui.SelectedObject = nil
				engine.environment.poke(
					VerifyRoblox.assertInstance(field),
					"AbsolutePosition",
					engine.types.Vector2.new(-121.67, 837)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(field),
					"AbsoluteSize",
					engine.types.Vector2.new(20, 30)
				)
				editing:set(true)
				expect(field:IsFocused()):toBe(false)
				expect(gui.SelectedObject):toBeNil()
				engine.environment.poke(
					VerifyRoblox.assertInstance(field),
					"AbsolutePosition",
					engine.types.Vector2.new(32, 100)
				)
				engine.heartbeat:Fire(1 / 60)
				expect(field:IsFocused()):toBe(true)
				expect(gui.SelectedObject):toBe(field)
				local hit = assert(node:FindFirstChild("EditLabel", true)) :: TextButton
				engine.environment.poke(
					VerifyRoblox.assertInstance(hit),
					"AbsolutePosition",
					engine.types.Vector2.new(32, 100)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(hit),
					"AbsoluteSize",
					engine.types.Vector2.new(61, 44)
				)
				editing:set(false)
				expect(gui.SelectedObject):toBe(hit)
				editing:set(true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(field),
					"AbsolutePosition",
					engine.types.Vector2.new(-121.67, 837)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(hit),
					"AbsolutePosition",
					engine.types.Vector2.new(-121.67, 837)
				)
				editing:set(false)
				expect(gui.SelectedObject):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		it("keeps inline editors compact on pointer input and enlarges their input target for touch", {
			id = "native_collections::shared container editing::keeps inline editors compact on pointer input and enlarges their input target for touch",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = { MouseEnabled = true } })
				local enabled = Compose.cell(true)
				local stop, node: any = runtime.mount(function()
					return UI.CellEditor {
						editor = "text" :: "text",
						value = "Alpha",
						enabled = enabled,
						onChange = function() end,
					}
				end, target)
				require("../src/ui/activation").edits(node)[1].onActivate()
				local hit = node:FindFirstChild("Input+target", true)
				local compactHeight = hit.Size.Y.Offset
				local input = assert(ctx.config.userInputService)
				expect(compactHeight < 44):toBe(true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(input),
					"PreferredInput",
					engine.types.Enum.PreferredInput.Touch
				)
				expect(hit.Size.Y.Offset >= 44):toBe(true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(input),
					"PreferredInput",
					engine.types.Enum.PreferredInput.Gamepad
				)
				expect(hit.Size.Y.Offset >= 44):toBe(true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(input),
					"PreferredInput",
					engine.types.Enum.PreferredInput.KeyboardAndMouse
				)
				expect(hit.Size.Y.Offset):toBe(compactHeight)
				enabled:set(false)
				require("../src/ui/activation").edits(node)[1].onActivate()
				local field = node:FindFirstChildWhichIsA("TextBox", true)
				expect(field.TextEditable):toBe(false)
				expect(field.Selectable):toBe(false)
				expect(field.Interactable):toBe(false)
				expect((field:GetAttribute("readOnly"))):toBe(true)
				expect(hit.Size.Y.Offset):toBe(compactHeight)
				stop()
				runtime:dispose()
			end,
		})

		it("does not save an unfinished draft when its cell is removed", {
			id = "native_collections::shared container editing::does not save an unfinished draft when its cell is removed",
			run = function()
				local _, runtime, UI, target = setup()
				local draft, commits = Compose.cell(nil :: FixtureCollectionTypes.CellDraft?), 0
				local stop, node: any = runtime.mount(function()
					return UI.CellEditor {
						editor = "text" :: "text",
						value = "Alpha",
						draft = draft,
						onChange = function()
							commits += 1
						end,
					}
				end, target)
				require("../src/ui/activation").edits(node)[1].onActivate()
				local field = node:FindFirstChildWhichIsA("TextBox", true)
				field.Focused:Fire()
				field.Text = "Unfinished"
				stop()
				expect(commits):toBe(0)
				expect(assert(draft:peek()).text):toBe("Unfinished")
			end,
		})

		it("commits clamped numbers and keeps pending text until the model confirms it", {
			id = "native_collections::shared container editing::commits clamped numbers and keeps pending text until the model confirms it",
			run = function()
				local _, runtime, UI, target = setup()
				local value, draft, busy =
					Compose.cell(5), Compose.cell(nil :: FixtureCollectionTypes.CellDraft?), Compose.cell(false)
				local proposed
				local stop, node: any = runtime.mount(function()
					return UI.CellEditor {
						editor = "number" :: "number",
						value = value,
						draft = draft,
						busy = busy,
						min = 0,
						max = 10,
						onChange = function(v: any)
							proposed = v
							busy:set(true)
						end,
					}
				end, target)
				require("../src/ui/activation").edits(node)[1].onActivate()
				local field = node:FindFirstChildWhichIsA("TextBox", true)
				field.Focused:Fire()
				field.Text = "25"
				field.FocusLost:Fire(true)
				expect(proposed):toBe(10)
				expect((value:peek())):toBe(5)
				expect(assert(draft:peek()).text):toBe("10")
				value:set(10)
				busy:set(false)
				expect((draft:peek())):toBe(nil)
				stop()
			end,
		})
	end)

	describe("container presentation and shared cells", function()
		it("reflows minimum-width tiles as the viewport and bound size change", {
			id = "native_collections::container presentation and shared cells::reflows minimum-width tiles as the viewport and bound size change",
			run = function()
				local engine, runtime, UI, target = setup()
				local controls: any = {}
				local minimum = Compose.cell(150)
				local stop, grid: any = runtime.mount(function()
					local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = records(10),
						key = key,
						minColumnWidth = minimum,
						gap = 10,
						itemSize = 80,
						controls = controls,
						render = function(): GuiObject
							return Facet.host(runtime).Frame({})
						end,
					}
					return UI.VirtualGrid(props)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(grid),
					"AbsoluteSize",
					engine.types.Vector2.new(500, 300)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(grid),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(500, 300)
				)
				expect(controls.placementOf(3).offset):toBe(0)
				expect(controls.placementOf(4).offset > 0):toBe(true)
				engine.environment.poke(
					VerifyRoblox.assertInstance(grid),
					"AbsoluteSize",
					engine.types.Vector2.new(320, 300)
				)
				engine.environment.poke(
					VerifyRoblox.assertInstance(grid),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(320, 300)
				)
				expect(controls.placementOf(3).offset > 0):toBe(true)
				expect(controls.placementOf(2).offset):toBe(0)
				minimum:set(240)
				expect(controls.placementOf(2).offset > 0):toBe(true)
				minimum:set(150)
				expect(controls.placementOf(2).offset):toBe(0)
				stop()
			end,
		})

		it("hug sizes an all-rows grid to its rows, so it lays out in a panel without measuring", {
			id = "native_collections::container presentation and shared cells::hug sizes an all-rows grid to its rows, so it lays out in a panel without measuring",
			run = function()
				local engine, runtime, UI, target = setup()
				local D2, V2 = engine.types.UDim2, engine.types.Vector2
				local stop = runtime.mount(function()
					local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = records(6),
						key = key,
						mode = "all" :: "all",
						hug = true,
						minColumnWidth = 150,
						gap = 10,
						itemSize = 80,
						Name = "Hugged",
						render = function(): GuiObject
							return Facet.host(runtime).Frame({})
						end,
					}
					return UI.VirtualGrid(props)
				end, target)
				local grid = target:FindFirstChild("Hugged", true)
				engine.environment.poke(grid, "AbsoluteSize", V2.new(500, 300))
				engine.environment.poke(grid, "AbsoluteWindowSize", V2.new(500, 300))
				local wide = grid.CanvasSize.Y.Offset
				expect(wide > 0):toBe(true)
				expect(grid.Size):toBe(D2.new(1, 0, 0, wide))
				engine.environment.poke(grid, "AbsoluteSize", V2.new(320, 300))
				engine.environment.poke(grid, "AbsoluteWindowSize", V2.new(320, 300))
				local narrow = grid.CanvasSize.Y.Offset
				expect(narrow > wide):toBe(true)
				expect(grid.Size):toBe(D2.new(1, 0, 0, narrow))
				stop()
			end,
		})

		it("hug leaves no empty columns: a few peer items share the whole width", {
			id = "native_collections::container presentation and shared cells::hug leaves no empty columns: a few peer items share the whole width",
			run = function()
				local engine, runtime, UI, target = setup()
				local V2 = engine.types.Vector2
				local stops = {}
				local function grid(hug: boolean): (number) -> FixtureComposeTypes.Placement
					local controls: FixtureComposeTypes.OrderedCollectionControls<number> = {}
					local name = if hug then "Fitted" else "Filled"
					local stop = runtime.mount(function()
						local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> =
							{
								from = records(3),
								key = key,
								mode = "all" :: "all",
								hug = hug,
								minColumnWidth = 150,
								itemSize = 80,
								controls = controls,
								Name = name,
								render = function(): GuiObject
									return Facet.host(runtime).Frame({})
								end,
							}
						return UI.VirtualGrid(props)
					end, target)
					table.insert(stops, assert(stop))
					local node = target:FindFirstChild(name, true)
					engine.environment.poke(node, "AbsoluteSize", V2.new(800, 300))
					engine.environment.poke(node, "AbsoluteWindowSize", V2.new(800, 300))
					return assert(controls.placementOf)
				end
				local fitted, filled = grid(true), grid(false)
				expect(fitted(3).offset):toBe(0)
				expect(fitted(1).crossSize > 250):toBe(true)
				expect(filled(1).crossSize < 170):toBe(true)
				for _, stop in stops do
					stop()
				end
			end,
		})

		it("minColumns keeps two even columns on a phone where minColumnWidth alone fits one", {
			id = "native_collections::container presentation and shared cells::minColumns keeps two even columns on a phone where minColumnWidth alone fits one",
			run = function()
				local engine, runtime, UI, target = setup()
				local V2 = engine.types.Vector2
				local stops = {}
				local function grid(name: string, width: number, least: number?)
					local controls: FixtureComposeTypes.OrderedCollectionControls<number> = {}
					local stop = runtime.mount(function()
						local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> =
							{
								from = records(6),
								key = key,
								minColumnWidth = 180,
								minColumns = least,
								gap = 10,
								itemSize = 80,
								controls = controls,
								Name = name,
								render = function(): GuiObject
									return Facet.host(runtime).Frame({})
								end,
							}
						return UI.VirtualGrid(props)
					end, target)
					table.insert(stops, assert(stop))
					local node = target:FindFirstChild(name, true)
					engine.environment.poke(
						(node :: unknown) :: VerifyRoblox.Instance,
						"AbsoluteSize",
						V2.new(width, 300)
					)
					engine.environment.poke(
						(node :: unknown) :: VerifyRoblox.Instance,
						"AbsoluteWindowSize",
						V2.new(width, 300)
					)
					return assert(controls.placementOf)
				end
				local single, paired = grid("Single", 360, nil), grid("Paired", 360, 2)
				expect(single(2).offset > 0):toBe(true)
				expect(single(1).crossSize):toBe(350)
				expect(paired(2).offset):toBe(0)
				expect(paired(3).offset > 0):toBe(true)
				expect(paired(1).crossSize):toBe(170)
				expect(paired(2).crossSize):toBe(170)
				expect(paired(2).crossOffset):toBe(180)
				local wide, floored = grid("Wide", 800, nil), grid("Floored", 800, 2)
				for index = 1, 6 do
					expect(floored(index)):toEqual(wide(index))
				end
				expect(floored(4).offset):toBe(0)
				expect(floored(5).offset > 0):toBe(true)
				expect(floored(1).crossSize):toBe(190)
				for _, stop in stops do
					stop()
				end
			end,
		})

		it("minColumns follows a bound count, and hug still makes no more columns than items", {
			id = "native_collections::container presentation and shared cells::minColumns follows a bound count, and hug still makes no more columns than items",
			run = function()
				local engine, runtime, UI, target = setup()
				local V2 = engine.types.Vector2
				local stops = {}
				local function grid(name: string, count: number, hug: boolean, least: FixtureEngineTypes.ValueNumber)
					local controls: FixtureComposeTypes.OrderedCollectionControls<number> = {}
					local stop = runtime.mount(function()
						local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> =
							{
								from = records(count),
								key = key,
								mode = "all" :: "all",
								hug = hug,
								minColumnWidth = 180,
								minColumns = least,
								gap = 10,
								itemSize = 80,
								controls = controls,
								Name = name,
								render = function(): GuiObject
									return Facet.host(runtime).Frame({})
								end,
							}
						return UI.VirtualGrid(props)
					end, target)
					table.insert(stops, assert(stop))
					local node = target:FindFirstChild(name, true)
					engine.environment.poke(node, "AbsoluteSize", V2.new(360, 300))
					engine.environment.poke(node, "AbsoluteWindowSize", V2.new(360, 300))
					return assert(controls.placementOf)
				end
				local least = Compose.cell(2)
				local bound = grid("Bound", 6, false, least)
				expect(bound(2).offset):toBe(0)
				expect(bound(3).offset > 0):toBe(true)
				least:set(3)
				expect(bound(3).offset):toBe(0)
				expect(bound(4).offset > 0):toBe(true)
				expect(bound(1).crossSize):toBe(110)
				least:set(1)
				expect(bound(2).offset > 0):toBe(true)
				expect(bound(1).crossSize):toBe(350)
				local alone, three = grid("Alone", 1, true, 2), grid("Three", 3, true, 2)
				expect(alone(1).crossSize):toBe(350)
				expect(three(2).offset):toBe(0)
				expect(three(3).offset > 0):toBe(true)
				expect(three(1).crossSize):toBe(170)
				for _, stop in stops do
					stop()
				end
			end,
		})

		it("minColumns needs minColumnWidth, a positive whole number and no columns", {
			id = "native_collections::container presentation and shared cells::minColumns needs minColumnWidth, a positive whole number and no columns",
			run = function()
				local function refused(columns: number?, minColumnWidth: number?, least: number): boolean
					local _, runtime, UI, target = setup()
					local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = records(3),
						key = key,
						mode = "all" :: "all",
						columns = columns,
						minColumnWidth = minColumnWidth,
						minColumns = least,
						itemSize = 40,
						render = function(): GuiObject
							return Facet.host(runtime).Frame({})
						end,
					}
					local ok, problem = pcall(function()
						local stop = runtime.mount(function()
							return UI.VirtualGrid(props)
						end, target)
						stop()
					end)
					local message = tostring(problem)
					return not ok and string.find(message, "Facet minColumns needs minColumnWidth", 1, true) ~= nil
				end
				expect(refused(2, nil, 2)):toBe(true)
				expect(refused(2, 150, 2)):toBe(true)
				expect(refused(nil, nil, 2)):toBe(true)
				expect(refused(nil, 150, 0)):toBe(true)
				expect(refused(nil, 150, 1.5)):toBe(true)
				expect(refused(nil, 150, 2)):toBe(false)
			end,
		})

		it("grid focus wraps by the columns that minColumnWidth and minColumns fit", {
			id = "native_collections::container presentation and shared cells::grid focus wraps by the columns that minColumnWidth and minColumns fit",
			run = function()
				local closers = {}
				local function grid(width: number, columns: number?, minimum: number?, least: number?)
					local engine, runtime, UI, target = setup()
					local focus: FixtureCollectionTypes.FocusControls<number> = {}
					local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = records(6),
						key = key,
						columns = columns,
						minColumnWidth = minimum,
						minColumns = least,
						gap = 10,
						itemSize = 40,
						focus = focus,
						wrapFocus = true,
						Name = "Wrapped",
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					local stop = runtime.mount(function()
						return UI.VirtualGrid(props)
					end, target)
					engine.environment.poke(
						(target:FindFirstChild("Wrapped", true) :: unknown) :: VerifyRoblox.Instance,
						"AbsoluteWindowSize",
						engine.types.Vector2.new(width, 300)
					)
					table.insert(closers, function()
						stop()
						runtime:dispose()
					end)
					return function(from: number, direction: string): number?
						assert(focus.focus)(from)
						local context = target:FindFirstChild("FacetCollection" .. direction)
						context:FindFirstChild("Collection" .. direction).Pressed:Fire()
						return assert(focus.current):peek()
					end
				end
				local fitted = grid(800, nil, 180, nil)
				expect(fitted(4, "Right")):toBe(1)
				expect(fitted(5, "Left")):toBe(6)
				expect(fitted(1, "Up")):toBe(5)
				expect(fitted(6, "Down")):toBe(2)
				local paired = grid(360, nil, 180, 2)
				expect(paired(2, "Right")):toBe(1)
				expect(paired(3, "Left")):toBe(4)
				expect(paired(1, "Up")):toBe(5)
				expect(paired(6, "Down")):toBe(2)
				local single = grid(360, nil, 180, nil)
				expect(single(2, "Right")):toBe(2)
				expect(single(6, "Down")):toBe(1)
				local fixed = grid(800, 3, nil, nil)
				expect(fixed(3, "Right")):toBe(1)
				expect(fixed(6, "Down")):toBe(3)
				for _, close in closers do
					close()
				end
			end,
		})

		it("hug needs every row: a windowed collection rejects it", {
			id = "native_collections::container presentation and shared cells::hug needs every row: a windowed collection rejects it",
			run = function()
				local _, runtime, UI, target = setup()
				local ok, problem = pcall(function()
					local stop = runtime.mount(function()
						local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> =
							{
								from = records(3),
								key = key,
								hug = true,
								itemSize = 40,
								render = function(): GuiObject
									return Facet.host(runtime).Frame({})
								end,
							}
						return UI.VirtualList(props)
					end, target)
					stop()
				end)
				expect(ok):toBe(false)
				expect(string.find(tostring(problem), "hug needs mode", 1, true) ~= nil):toBe(true)
			end,
		})

		it("keeps grid edit controls above full-width content and measures their height", {
			id = "native_collections::container presentation and shared cells::keeps grid edit controls above full-width content and measures their height",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V2, D2 = engine.types.Enum, engine.types.Vector2, engine.types.UDim2
				engine.environment.poke(
					VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
					"PreferredInput",
					E.PreferredInput.Touch
				)
				local editing, controls: any = Compose.cell(true), {}
				local stop, grid: any = runtime.mount(function()
					local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = records(4),
						key = key,
						mode = "all" :: "all",
						columns = 2,
						itemSize = 80,
						measure = true,
						controls = controls,
						editing = editing,
						selectionMode = "multiple" :: "multiple",
						reorderable = true,
						onReorder = function() end,
						render = function(): GuiObject
							return Facet.host(runtime).Frame { Name = "Tile" }
						end,
					}
					return UI.VirtualGrid(props)
				end, target)
				engine.environment.poke(VerifyRoblox.assertInstance(grid), "AbsoluteSize", V2.new(320, 300))
				engine.environment.poke(VerifyRoblox.assertInstance(grid), "AbsoluteWindowSize", V2.new(320, 300))
				local row = grid:FindFirstChild("1", true)
				local tile = row:FindFirstChild("Tile", true)
				engine.environment.poke(VerifyRoblox.assertInstance(tile), "AbsoluteSize", V2.new(160, 80))
				local cells = row:FindFirstChild("Cells", true)
				expect(cells.Position):toBe(D2.fromOffset(0, 44))
				expect(cells.Size):toBe(D2.new(1, 0, 1, -44))
				expect(controls.placementOf(1).size):toBe(124)
				local handle = row:FindFirstChild("Move", true)
				expect(handle.Size):toBe(D2.fromOffset(44, 44))
				expect(handle:FindFirstChildWhichIsA("UIDragDetector").DragStyle):toBe(
					E.UIDragDetectorDragStyle.TranslatePlane
				)
				expect(row:FindFirstChild("SelectMark", true).Position):toBe(D2.fromOffset(22, 22))
				editing:set(false)
				expect(cells.Position):toBe(D2.fromOffset(0, 44))
				expect(cells.Size):toBe(D2.new(1, 0, 1, -44))
				expect(controls.placementOf(1).size):toBe(124)
				expect((row:FindFirstChild("Move", true))):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		it("shares one draft between two native fields without duplicate proposals", {
			id = "native_collections::container presentation and shared cells::shares one draft between two native fields without duplicate proposals",
			run = function()
				local _, runtime, UI, target = setup()
				local value, draft, commits =
					Compose.cell("Alpha"), Compose.cell(nil :: FixtureCollectionTypes.CellDraft?), 0
				local fields: {
					{
						Text: string,
						Focused: { Fire: (unknown) -> () },
						FocusLost: { Fire: (unknown, boolean) -> () },
					}
				} =
					{}
				local stops: { () -> () } = {}
				for _ = 1, 2 do
					local stop, node: any = runtime.mount(function()
						return UI.CellEditor {
							editor = "text" :: "text",
							value = value,
							draft = draft,
							onChange = function(v: any)
								commits += 1
								value:set(v)
							end,
						}
					end, target)
					table.insert(stops, assert(stop))
					require("../src/ui/activation").edits(node)[1].onActivate()
					local field = node:FindFirstChildWhichIsA("TextBox", true)
					assert(field ~= nil)
					fields[#fields + 1] = field
				end
				fields[1].Focused:Fire()
				fields[1].Text = "Shared"
				expect(fields[2].Text):toBe("Shared")
				expect((value:peek())):toBe("Alpha")
				fields[1].FocusLost:Fire(true)
				expect(commits):toBe(1)
				expect((value:peek())):toBe("Shared")
				expect((draft:peek())):toBe(nil)
				for _, stop in stops do
					stop()
				end
			end,
		})

		it("keeps toggle and menu cells on their native controls", {
			id = "native_collections::container presentation and shared cells::keeps toggle and menu cells on their native controls",
			run = function()
				local _, runtime, UI, target = setup()
				local value = Compose.cell(false)
				local stop, node: any = runtime.mount(function()
					return UI.CellEditor {
						editor = "toggle" :: "toggle",
						value = value,
						onChange = function(v: any)
							value:set(v)
						end,
					}
				end, target)
				local toggle = node:FindFirstChild("Editor")
				expect((toggle:IsA("TextButton"))):toBe(true)
				toggle.Activated:Fire()
				expect((value:peek())):toBe(true)
				stop()
				local selected = Compose.cell("Blue")
				stop, node = runtime.mount(function()
					return UI.CellEditor {
						editor = "menu" :: "menu",
						value = selected,
						options = { { value = "Blue", label = "Blue" }, { value = "Red", label = "Red" } },
						onChange = function(v: any)
							selected:set(v)
						end,
					}
				end, target)
				expect(node:FindFirstChild("Trigger", true) ~= nil):toBe(true)
				expect((node:FindFirstChildWhichIsA("TextBox", true))):toBe(nil)
				stop()
			end,
		})
	end)

	describe("input-aware collection commands", function()
		it("routes a shared selection delete including hidden records only through the focused collection", {
			id = "native_collections::input-aware collection commands::routes a shared selection delete including hidden records only through the focused collection",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local rows, selection = Compose.cell(records(3)), Compose.cell({ [2] = true, [3] = true })
				local proposals: { { view: number, keys: { number } } } = {}
				local nodes, stops = {}, {}
				for index = 1, 2 do
					local stop, node: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> =
							{
								from = { rows:peek()[1], rows:peek()[2] },
								selectionFrom = rows,
								key = key,
								mode = "all" :: "all",
								selection = selection,
								selectionMode = "multiple" :: "multiple",
								editing = true,
								deletable = true,
								onDelete = function(keys: { number })
									table.insert(proposals, { view = index, keys = keys })
								end,
								render = function(): GuiObject
									return Facet.host(runtime).Frame({})
								end,
							}
						return UI.VirtualList(listSpec)
					end, target)
					table.insert(nodes, node)
					table.insert(stops, assert(stop))
				end
				gui.SelectedObject = nodes[1]:FindFirstChild("2", true):FindFirstChild("RowHit", true)
				for _, child in target:GetChildren() do
					if child.Name == "FacetDeleteRows" then
						child:FindFirstChild("DeleteRows").Pressed:Fire()
					end
				end
				expect(#proposals):toBe(1)
				expect(proposals[1].view):toBe(1)
				expect(proposals[1].keys):toEqual({ 2, 3 })
				for _, stop in stops do
					stop()
				end
			end,
		})
	end)

	describe("spatial grid reordering", function()
		it("moves across cells and between rows for both grid directions, including a short last row", {
			id = "native_collections::spatial grid reordering::moves across cells and between rows for both grid directions, including a short last row",
			run = function()
				for _, horizontal in { false, true } do
					local engine, runtime, UI, target, _, ctx = setup()
					local requests = {}
					local stop, node: any = runtime.mount(function()
						local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> =
							{
								from = records(8),
								key = key,
								mode = "all" :: "all",
								columns = 3,
								itemSize = 40,
								direction = if horizontal
									then "horizontal" :: "horizontal"
									else "vertical" :: "vertical",
								reorderable = true,
								collectionId = "spatial-test",
								drag = function(
									_: { { id: number, label: string } },
									keys: { number }
								): FixtureEnvironmentTypes.DraggableSpec
									return {
										payload = { collection = "spatial-test", keys = keys },
										operations = { "move" } :: { "copy" | "move" | "apply" },
									}
								end,
								onReorder = function(keys: { number }, slot: number)
									table.insert(requests, { keys = keys, slot = slot })
								end,
								render = function(current): GuiObject
									return button(UI, current)
								end,
							}
						return UI.VirtualGrid(props)
					end, target)
					engine.environment.poke(
						VerifyRoblox.assertInstance(node),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(300, 300)
					)
					engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", node.AbsoluteWindowSize)
					local function press(name: string)
						local action = target:FindFirstChild("Facet" .. name)
						expect(action.Enabled):toBe(true)
						action:FindFirstChild(name).Pressed:Fire()
					end
					local handle = node:FindFirstChild("1", true):FindFirstChild("Move", true)
					engine.environment.poke(
						VerifyRoblox.assertInstance(handle.Parent),
						"AbsoluteSize",
						engine.types.Vector2.new(100, 40)
					)
					handle.Activated:Fire()
					expect(assert(require("../src/ui/drag_session")(ctx).state:peek()).pickupSize):toBe(
						handle.Parent.AbsoluteSize
					)
					press("ChooseDropDestination")
					expect(target:FindFirstChild("Drop", true).Visible):toBe(false)
					expect(target:FindFirstChild("FacetReorderCrossLater").Enabled):toBe(false)
					press("ChooseDropDestination")
					expect(target:FindFirstChild("FacetReorderCrossLater").Enabled):toBe(true)
					press("ReorderCrossLater")
					press("ReorderDown")
					press("ReorderDown")
					press("ReorderDown")
					press("ReorderUp")
					press("ReorderDrop")
					expect(requests):toEqual({ { keys = { 1 }, slot = 4 } })
					handle.Activated:Fire()
					press("ReorderCrossEarlier")
					press("ReorderUp")
					press("ReorderCancel")
					expect(#requests):toBe(1)
					stop()
					runtime:dispose()
				end
			end,
		})
		it("uses the current column count for selected blocks and permits cancelling an all-selected grid", {
			id = "native_collections::spatial grid reordering::uses the current column count for selected blocks and permits cancelling an all-selected grid",
			run = function()
				local engine, runtime, UI, target = setup()
				local columns = Compose.cell(3)
				local selection = Compose.cell({ [1] = true, [2] = true })
				local requests = {}
				local stop, node: any = runtime.mount(function()
					local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = records(8),
						key = key,
						mode = "all" :: "all",
						columns = columns,
						itemSize = 40,
						selection = selection,
						selectionMode = "multiple" :: "multiple",
						reorderable = true,
						onReorder = function(keys: { number }, slot: number)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualGrid(props)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(300, 300)
				)
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteSize", node.AbsoluteWindowSize)
				local function press(name: string)
					target:FindFirstChild("Facet" .. name):FindFirstChild(name).Pressed:Fire()
				end
				node:FindFirstChild("1", true):FindFirstChild("Move", true).Activated:Fire()
				columns:set(2)
				press("ReorderDown")
				press("ReorderDrop")
				expect(requests):toEqual({ { keys = { 1, 2 }, slot = 2 } })
				selection:set({
					[1] = true,
					[2] = true,
					[3] = true,
					[4] = true,
					[5] = true,
					[6] = true,
					[7] = true,
					[8] = true,
				})
				node:FindFirstChild("1", true):FindFirstChild("Move", true).Activated:Fire()
				press("ReorderDown")
				press("ReorderCrossLater")
				press("ReorderCancel")
				expect(#requests):toBe(1)
				stop()
				runtime:dispose()
			end,
		})
	end)

	describe("collection transfer sessions", function()
		it("keyboard pickup carries selected hidden items and calls the source lifecycle once", {
			id = "native_collections::collection transfer sessions::keyboard pickup carries selected hidden items and calls the source lifecycle once",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup()
				local all = records(3)
				local carried, starts, ends = nil, 0, 0
				local stop, node: any = runtime.mount(function()
					local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = { all[1], all[3] },
						selectionFrom = all,
						key = key,
						selection = Compose.cell({ [1] = true, [2] = true }),
						selectionMode = "multiple" :: "multiple",
						itemSize = 40,
						columns = 2,
						drag = function(
							items: { { id: number, label: string } },
							keys: { number }
						): FixtureEnvironmentTypes.DraggableSpec
							carried = keys
							return {
								payload = items,
								onStart = function(_: any, mode: "armed" | "pointer")
									starts += 1
									expect(mode):toBe("armed")
								end,
								onEnd = function()
									ends += 1
								end,
							}
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualGrid(props)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 100)
				)
				local hit = node:FindFirstChild("1", true):FindFirstChild("RowHit", true)
				hit.Activated:Fire({
					UserInputType = engine.types.Enum.UserInputType.Keyboard,
					KeyCode = engine.types.Enum.KeyCode.Return,
				})
				expect(carried):toEqual({ 1, 2 })
				expect((node:FindFirstChild("FacetDropOutline"))):toBe(nil)
				expect(node:FindFirstChild("DropLine", true).Visible):toBe(false)
				expect(starts):toBe(1)
				require("../src/ui/drag_session")(ctx).finish(false)
				expect(ends):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		it("bounds placement queries while dragging through ten thousand rows", {
			id = "native_collections::collection transfer sessions::bounds placement queries while dragging through ten thousand rows",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup()
				local rows = Compose.cell(records(10000))
				local controls: FixtureComposeTypes.OrderedCollectionControls<any> = {}
				local insertion: FixtureEnvironmentTypes.DropInsertion? = nil
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = rows,
						key = key,
						controls = controls,
						itemSize = 40,
						drop = {
							operation = "copy" :: "copy",
							onDrop = function(_: unknown, info: FixtureEnvironmentTypes.DropInfo): boolean
								insertion = info.insertion
								return true
							end,
						},
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 200)
				)
				nativeDrag.measure(node, engine.environment)
				local queries = 0
				local placement = assert(controls.placementOf)
				controls.placementOf = function(index)
					queries += 1
					return placement(index)
				end
				local session = require("../src/ui/drag_session")(ctx)
				local source = engine.new("TextButton")
				source.Parent = target
				session.begin(source, { payload = "new", operations = { "copy" :: "copy" } }, "pointer", nil, false)
				for _, y in { 45, 85, 125 } do
					queries = 0
					session.update(engine.types.Vector2.new(100, y))
					expect(queries > 0 and queries < 100):toBe(true)
				end
				local changed = records(10000)
				table.insert(changed, 1, { id = 10001, label = "New" })
				rows:set(changed)
				node.CanvasPosition = engine.types.Vector2.zero
				session.update(engine.types.Vector2.new(100, 45))
				session.commit(node)
				expect(assert(insertion).beforeKey):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		it("rebases pending insertion against surviving neighbors and rejects removed neighbors", {
			id = "native_collections::collection transfer sessions::rebases pending insertion against surviving neighbors and rejects removed neighbors",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup()
				local rows = Compose.cell(records(3))
				local pending: FixtureEnvironmentTypes.DropInfo? = nil
				local stop, node: any = runtime.mount(function()
					local props: FixtureCollectionProps.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = rows,
						key = key,
						itemSize = 40,
						drop = {
							operation = "copy" :: "copy",
							onDrop = function(_: unknown, info: FixtureEnvironmentTypes.DropInfo): "pending"
								pending = info
								return "pending"
							end,
						},
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(props)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(200, 200)
				)
				nativeDrag.measure(node, engine.environment)
				local session = require("../src/ui/drag_session")(ctx)
				local source = engine.new("TextButton")
				source.Parent = target
				local function drop(): FixtureEnvironmentTypes.DropInfo
					session.begin(source, { payload = "new", operations = { "copy" :: "copy" } }, "pointer", nil, false)
					session.update(engine.types.Vector2.new(100, 45))
					session.commit(node)
					return assert(pending)
				end
				local delivered = drop()
				expect(assert(delivered.insertion).beforeKey):toBe(2)
				local changed = records(3)
				table.insert(changed, 1, { id = 4, label = "New" })
				rows:set(changed)
				expect((delivered.complete(true))):toBe(true)
				expect(assert(delivered.insertion).slot):toBe(2)
				expect((delivered.complete(true))):toBe(false)
				rows:set(records(3))
				delivered = drop()
				rows:set({ { id = 3, label = "Only survivor" } })
				expect((delivered.complete(true))):toBe(false)
				stop()
				runtime:dispose()
			end,
		})
	end)

	describe("native collection detector taps", function()
		it("selects a frame-backed card before and after a drag without selecting on the drop", {
			id = "native_collections::native collection detector taps::selects a frame-backed card before and after a drag without selecting on the drop",
			run = function()
				for _, kind in { "VirtualGrid", "VirtualList" } do
					local now = 0
					local engine, runtime, UI, target, _, ctx = setup({
						userInputService = {},
						clock = function()
							return now
						end,
					})
					local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
					local selection = Compose.cell({})
					local opened = {}
					local stop, list: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = records(3),
							key = key,
							mode = "all" :: "all",
							selection = selection,
							reorderable = true,
							onReorder = function() end,
							onActivate = function(_, id)
								table.insert(opened, id)
							end,
							render = function(): GuiObject
								return Facet.host(runtime).Frame { Name = "Card" }
							end,
						}
						return (if kind == "VirtualList" then UI.VirtualList else UI.VirtualGrid)(listSpec)
					end, target)
					local input: any = assert(ctx.config.userInputService)
					local press = { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(20, 20, 0) }
					local function tap(id: number, cancelled: boolean?)
						press.UserInputState = E.UserInputState.Begin
						input.InputBegan:Fire(press)
						local card = list:FindFirstChild(tostring(id), true):FindFirstChild("Card", true)
						card.InputBegan:Fire(press)
						local detector = card:FindFirstChild("FacetCollectionDrag")
						detector.DragStart:Fire(V2.new(20, 20))
						press.UserInputState = if cancelled then E.UserInputState.Cancel else E.UserInputState.End
						input.InputEnded:Fire(press)
						detector.DragEnd:Fire()
					end
					tap(1)
					expect((selection:peek())):toEqual({ [1] = true })
					expect(#opened):toBe(0)
					tap(1)
					expect(opened):toEqual({ 1 })
					local card = list:FindFirstChild("1", true):FindFirstChild("Card", true)
					press.UserInputState = E.UserInputState.Begin
					input.InputBegan:Fire(press)
					card.InputBegan:Fire(press)
					local detector = card:FindFirstChild("FacetCollectionDrag")
					engine.environment.poke(
						VerifyRoblox.assertInstance(input),
						"PreferredInput",
						E.PreferredInput.Gamepad
					)
					expect(detector.Enabled):toBe(false)
					engine.environment.poke(
						VerifyRoblox.assertInstance(input),
						"PreferredInput",
						E.PreferredInput.Touch
					)
					expect(detector.Enabled):toBe(false)
					engine.environment.poke(
						VerifyRoblox.assertInstance(input),
						"PreferredInput",
						E.PreferredInput.KeyboardAndMouse
					)
					expect(detector.Enabled):toBe(true)
					detector.DragStart:Fire(V2.new(20, 20))
					detector.DragContinue:Fire(V2.new(20, 140))
					press.UserInputState = E.UserInputState.End
					input.InputEnded:Fire(press)
					detector.DragEnd:Fire()
					expect((selection:peek())):toEqual({ [1] = true })
					tap(2)
					expect((selection:peek())):toEqual({ [2] = true })
					expect(opened):toEqual({ 1 })
					now += 0.6
					engine.heartbeat:Fire(0.6)
					tap(2)
					expect(opened):toEqual({ 1 })
					tap(3, true)
					expect((selection:peek())):toEqual({ [2] = true })
					stop()
					runtime:dispose()
				end
			end,
		})

		it("activates a Button row once on a detector tap and not after a drag", {
			id = "native_collections::native collection detector taps::activates a Button row once on a detector tap and not after a drag",
			run = function()
				for _, editing in { false, true } do
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
					local activated, reorders = {}, 0
					local stop, list: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = records(4),
							key = key,
							itemSize = 20,
							editing = editing,
							reorderable = true,
							onReorder = function()
								reorders += 1
							end,
							render = function(current): GuiObject
								return UI.Button "Action" {
									label = "Row",
									onActivate = function()
										table.insert(activated, current:peek().id)
									end,
								}
							end,
						}
						return UI.VirtualList(listSpec)
					end, target)
					engine.environment.poke(VerifyRoblox.assertInstance(list), "AbsoluteWindowSize", V2.new(200, 100))
					local input: any = assert(ctx.config.userInputService)
					local row = list:FindFirstChild("2", true):FindFirstChild("Action", true)
					local detector = row:FindFirstChild("FacetCollectionDrag")
					expect(detector.Enabled):toBe(true)
					local press = { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(20, 30, 0) }
					local function gesture(to: number?)
						press.UserInputState = E.UserInputState.Begin
						input.InputBegan:Fire(press)
						detector.DragStart:Fire(V2.new(20, 30))
						row.InputBegan:Fire(press)
						if to then
							detector.DragContinue:Fire(V2.new(20, to))
						end
						press.UserInputState = E.UserInputState.End
						input.InputEnded:Fire(press)
						detector.DragEnd:Fire()
					end
					gesture()
					expect(activated):toEqual({ 2 })
					expect(reorders):toBe(0)
					gesture(75)
					expect(activated):toEqual({ 2 })
					expect(reorders):toBe(1)
					gesture()
					expect(activated):toEqual({ 2, 2 })
					stop()
					runtime:dispose()
				end
			end,
		})

		it("continues a mouse drag from a selected Move handle with the captured pointer", {
			id = "native_collections::native collection detector taps::continues a mouse drag from a selected Move handle with the captured pointer",
			run = function()
				local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				local requests = {}
				local stop, list: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(5),
						key = key,
						itemSize = 20,
						editing = true,
						reorderable = true,
						onReorder = function(keys: { number }, slot: number)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(listSpec)
				end, target)
				engine.environment.poke(VerifyRoblox.assertInstance(list), "AbsoluteWindowSize", V2.new(200, 100))
				local input: any = assert(ctx.config.userInputService)
				local handle = list:FindFirstChild("2", true):FindFirstChild("Move", true)
				local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
				local reorderable = handle.Parent
				local press = { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(10, 30, 0) }
				local function tap()
					press.UserInputState = E.UserInputState.Begin
					input.InputBegan:Fire(press)
					detector.DragStart:Fire(V2.new(10, 30))
					handle.InputBegan:Fire(press)
					press.UserInputState = E.UserInputState.End
					input.InputEnded:Fire(press)
					detector.DragEnd:Fire()
				end
				tap()
				expect((reorderable:GetAttribute("FacetDragging"))):toBe(true)
				expect(assert(gui.SelectedObject).Name):toBe("Drop")
				tap()
				expect((reorderable:GetAttribute("FacetDragging"))):toBe(false)
				expect(gui.SelectedObject):toBe(handle)
				expect(detector.Enabled):toBe(true)
				expect(#requests):toBe(0)
				press.UserInputState = E.UserInputState.Begin
				input.InputBegan:Fire(press)
				detector.DragStart:Fire(V2.new(10, 30))
				handle.InputBegan:Fire(press)
				input.InputChanged:Fire({
					UserInputType = E.UserInputType.MouseMovement,
					UserInputState = E.UserInputState.Change,
					Position = V3.new(10, 75, 0),
				})
				expect((reorderable:GetAttribute("FacetDragging"))):toBe(true)
				expect(list:FindFirstChild("DragImage", true) ~= nil):toBe(true)
				press.UserInputState = E.UserInputState.End
				input.InputEnded:Fire(press)
				detector.DragEnd:Fire()
				expect(requests):toEqual({ { keys = { 2 }, slot = 3 } })
				expect((reorderable:GetAttribute("FacetDragging"))):toBe(false)
				expect(gui.SelectedObject):toBe(handle)
				stop()
				runtime:dispose()
			end,
		})
	end)

	describe("independent cell editing", function()
		it("keeps table field permissions separate from collection editing and rechecks changed records", {
			id = "native_collections::independent cell editing::keeps table field permissions separate from collection editing and rechecks changed records",
			run = function()
				local engine, runtime, UI, target = setup({ userInputService = {} })
				local rows = Compose.cell({ { id = 1, name = "Alpha", checked = false, locked = false } })
				local editing, changes = Compose.cell(false), {}
				local stop, node: any = runtime.mount(function()
					local props: FixtureCollectionProps.KeyedTableSpec<
						{ id: number, name: string, checked: boolean, locked: boolean },
						number
					> =
						{
							from = rows,
							key = "id",
							editing = editing,
							columns = {
								{
									id = "name",
									editor = "text",
									editLabel = "Edit title",
									editable = function()
										return false
									end,
								} :: FixtureCollectionTypes.TableColumn<any, any>,
								{
									id = "checked",
									editor = "toggle",
									editable = function(item)
										return not item.locked
									end,
								} :: FixtureCollectionTypes.TableColumn<any, any>,
							},
							onCellChange = function(_: number, column: string, value: unknown)
								table.insert(changes, { column = column, value = value })
							end,
						}
					return UI.Table(props)
				end, target)
				local body = node:FindFirstChild("Body")
				engine.environment.poke(
					VerifyRoblox.assertInstance(body),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(400, 200)
				)
				local row = node:FindFirstChild("1", true)
				local name = row:FindFirstChild("name", true)
				local toggle = row:FindFirstChild("checked", true):FindFirstChild("Editor", true)
				local edits = require("../src/ui/activation").edits(row)
				expect(edits[1].label):toBe("Edit title")
				expect((edits[1].enabled())):toBe(false)
				edits[1].onActivate()
				expect((name:FindFirstChildWhichIsA("TextBox", true))):toBe(nil)
				toggle.Activated:Fire()
				expect(#changes):toBe(1)
				editing:set(true)
				expect((edits[1].enabled())):toBe(false)
				edits[1].onActivate()
				expect((name:FindFirstChildWhichIsA("TextBox", true))):toBe(nil)
				rows:set({ { id = 1, name = "Alpha", checked = false, locked = true } })
				toggle.Activated:Fire()
				expect(#changes):toBe(1)
				editing:set(false)
				toggle.Activated:Fire()
				expect(#changes):toBe(1)
				stop()
			end,
		})

		it("selects before mouse rename and exposes the same field action on nested outline rows", {
			id = "native_collections::independent cell editing::selects before mouse rename and exposes the same field action on nested outline rows",
			run = function()
				for _, kind in { "VirtualList", "VirtualGrid", "Outline", "Table" } do
					local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
					local E = engine.types.Enum
					local selected, editing, allowed = Compose.cell({}), Compose.cell(false), Compose.cell(true)
					local values = Compose.cell("Child")
					local stop, node: any = runtime.mount(function()
						local render = function(_current, _placement, key)
							local fieldEditing: FixtureComposeTypes.Value<boolean> = if key:peek() == "parent"
								then Compose.cell(false)
								else editing
							return UI.CellEditor {
								editor = "text" :: "text",
								value = values,
								editing = fieldEditing,
								enabled = allowed,
								editLabel = "Edit title",
								onChange = function(v: any)
									values:set(v)
								end,
							}
						end
						local spec: any = {
							from = { { id = "child" } },
							key = "id",
							selection = selected,
							selectionMode = "multiple",
							render = render,
							mode = "all" :: "all",
						}
						if kind == "Outline" then
							spec.from = { { id = "parent", children = { { id = "child" } } } }
							spec.children, spec.expanded = "children", Compose.cell({ parent = true })
						elseif kind == "Table" then
							spec.render = nil
							spec.columns = { { id = "name", render = render } }
						end
						if kind == "Table" then
							local build: (FixtureCollectionProps.KeyedTableSpec<{ id: string }, string>, string?) -> Frame =
								UI.Table
							return build(spec)
						end
						if kind == "Outline" then
							local build: (
								FixtureCollectionProps.KeyedOutlineSpec<{ id: string }, string>,
								string?
							) -> ScrollingFrame =
								UI.Outline
							return build(spec)
						end
						if kind == "VirtualGrid" then
							local build: (
								FixtureCollectionProps.KeyedCollectionSpec<{ id: string }, string>,
								string?
							) -> ScrollingFrame =
								UI.VirtualGrid
							return build(spec)
						end
						local build: (
							FixtureCollectionProps.KeyedCollectionSpec<{ id: string }, string>,
							string?
						) -> ScrollingFrame =
							UI.VirtualList
						return build(spec)
					end, target)
					local body = if kind == "Table" then node:FindFirstChild("Body") else node
					engine.environment.poke(
						VerifyRoblox.assertInstance(body),
						"AbsoluteSize",
						engine.types.Vector2.new(400, 300)
					)
					engine.environment.poke(
						VerifyRoblox.assertInstance(body),
						"AbsoluteWindowSize",
						engine.types.Vector2.new(400, 300)
					)
					local row = node:FindFirstChild("child", true)
					local actionButtons = 0
					for _, child in row:GetDescendants() do
						if child.Name == "CellActions" then
							actionButtons += 1
						end
					end
					expect(actionButtons):toBe(1)
					local hit = row:FindFirstChild("EditLabel", true)
					local function click(inputType)
						hit.Activated:Fire({ UserInputType = inputType })
					end
					click(E.UserInputType.MouseButton1)
					expect((selected:peek())):toEqual({ child = true })
					expect((editing:peek())):toBe(false)
					click(E.UserInputType.Touch)
					expect((editing:peek())):toBe(false)
					click(E.UserInputType.MouseButton1)
					expect((editing:peek())):toBe(true)
					editing:set(false)
					engine.environment.fakeOn(
						VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
						"IsKeyDown",
						function(_, code)
							return code == E.KeyCode.LeftControl
						end
					)
					click(E.UserInputType.MouseButton1)
					expect((editing:peek())):toBe(false)
					engine.environment.fakeOn(
						VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
						"IsKeyDown",
						function()
							return false
						end
					)
					selected:set({ child = true })
					gui.SelectedObject = row:FindFirstChild("RowHit", true)
					local rename = target:FindFirstChild("RenameCell", true)
					expect(rename.Parent.Enabled):toBe(true)
					rename.Pressed:Fire()
					expect((editing:peek())):toBe(true)
					editing:set(false)
					local edits = require("../src/ui/activation").edits(row)
					expect(edits[1].label):toBe("Edit title")
					edits[1].onActivate()
					expect((editing:peek())):toBe(true)
					editing:set(false)
					engine.environment.poke(
						VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
						"PreferredInput",
						E.PreferredInput.Gamepad
					)
					gui.SelectedObject = row:FindFirstChild("RowHit", true)
					edits[1].onActivate()
					local field = row:FindFirstChildWhichIsA("TextBox", true)
					expect(gui.SelectedObject):toBe(field)
					field.FocusLost:Fire(false, { KeyCode = E.KeyCode.ButtonB })
					expect((editing:peek())):toBe(false)
					expect(gui.SelectedObject):toBe(row:FindFirstChild("RowHit", true))
					engine.environment.poke(
						VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
						"PreferredInput",
						E.PreferredInput.Touch
					)
					local assigned = 0
					engine.onWrite(function(node, property, value)
						if node == gui and property == "SelectedObject" and value ~= nil then
							assigned += 1
						end
					end)
					edits[1].onActivate()
					expect(assigned):toBe(0)
					expect((editing:peek())):toBe(true)
					expect(field:IsFocused()):toBe(true)
					expect(gui.SelectedObject):toBeNil()
					field.FocusLost:Fire(false, { KeyCode = E.KeyCode.ButtonB })
					expect((editing:peek())):toBe(false)
					expect(gui.SelectedObject):toBeNil()
					allowed:set(false)
					edits[1].onActivate()
					expect((editing:peek())):toBe(false)
					engine.environment.poke(
						VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
						"PreferredInput",
						E.PreferredInput.Touch
					)
					expect(row:FindFirstChild("CellActions", true).Visible):toBe(true)
					local actions = row:FindFirstChild("CellActions", true)
					engine.environment.poke(
						VerifyRoblox.assertInstance(actions),
						"AbsoluteSize",
						engine.types.Vector2.new(70, 46)
					)
					expect(actions.Parent:FindFirstChild("Content").Size.X.Offset):toBe(
						if kind == "VirtualGrid" then 0 else -70
					)
					expect(actions.Parent:FindFirstChild("Content").Size.Y.Offset):toBe(
						if kind == "VirtualGrid" then -46 else 0
					)
					expect(actions.AnchorPoint.Y):toBe(if kind == "VirtualGrid" then 1 else 0.5)

					expect(row:FindFirstChild("SwipeGrip", true).Visible):toBe(false)
					engine.environment.poke(
						VerifyRoblox.assertInstance(assert(ctx.config.userInputService)),
						"PreferredInput",
						E.PreferredInput.KeyboardAndMouse
					)
					expect(row:FindFirstChild("CellActions", true).Visible):toBe(false)
					stop()
				end
			end,
		})
	end)

	type OutlineRecord = { id: string, label: string?, children: { OutlineRecord }? }

	describe("outline collections", function()
		it("resolves content height from external overrides observed sizes and the minimum", {
			id = "native_collections::outline collections::resolves content height from external overrides observed sizes and the minimum",
			run = function(_own, t)
				local engine, runtime, UI, target, _, ctx = setup()
				local fixtureTarget: VerifyRoblox.Instance = target
				t:defer(function()
					runtime:dispose()
				end)
				local external: FixtureComposeTypes.Value<{ [string]: number }> = Compose.cell({ child = 90 })
				local minimum = Compose.cell(20)
				local Host = ctx.Host
				runtime.mount(function()
					local spec: FixtureCollectionProps.KeyedOutlineSpec<OutlineRecord, string> = {
						Name = "MeasuredOutline",
						from = { { id = "folder", children = { { id = "child" } } } },
						key = "id",
						children = "children",
						expanded = Compose.cell({ folder = true }),
						mode = "all",
						itemSize = minimum,
						measure = true,
						measured = external,
						render = function(): Frame
							return Host.Frame { Size = engine.types.UDim2.fromOffset(100, 35) }
						end,
					}
					return UI.Outline(spec)
				end, target)
				local root = assert(fixtureTarget:FindFirstChild("MeasuredOutline"))
				local row = assert(root:FindFirstChild("child", true))
				local content = assert(row:FindFirstChild("Content"))
				local function height(): number
					local size = content.Size
					assert(typeof(size) == "UDim2")
					return size.Y.Offset
				end
				local observed = assert(row:FindFirstChild("OutlineRow", true))
				expect(height()):toBe(90)
				engine.environment.poke(observed, "AbsoluteSize", engine.types.Vector2.new(100, 70))
				expect(height()):toBe(90)
				external:set({ child = 0 })
				expect(height()):toBe(20)
				external:set({})
				expect(height()):toBe(70)
				minimum:set(80)
				expect(height()):toBe(80)
				external:set({ child = 100 })
				expect(height()):toBe(100)
				expect(root:FindFirstChild("child", true) == row):toBe(true)
			end,
		})
		it("shares hierarchy, selection and controlled expansion across lists and tables", {
			id = "native_collections::outline collections::shares hierarchy, selection and controlled expansion across lists and tables",
			run = function()
				for _, kind in { "Outline", "VirtualList", "Table" } do
					local engine, runtime, UI, target = setup()
					local rows: Compose.Value<{ OutlineRecord }> = Compose.cell({
						{ id = "folder", label = "Folder", children = { { id = "child", label = "Child" } } },
						{ id = "empty", label = "Empty", children = {} },
						{ id = "leaf", label = "Leaf" },
					} :: { OutlineRecord })
					local expanded, selection = Compose.cell({}), Compose.cell({ child = true })
					local requests = 0
					local focus: any = {}
					local stop, node: any = runtime.mount(function()
						local spec: any = {
							from = rows,
							key = "id",
							children = "children",
							expanded = expanded,
							selection = selection,
							selectionMode = "multiple",
							focus = focus,
							mode = "all" :: "all",
							itemSize = 60,
							onExpansionChange = function(value)
								requests += 1
								expanded:set(value)
							end,
							render = function(current)
								return runtime.constructors.TextLabel {
									Text = function(use)
										return use(current).label
									end,
									Size = engine.types.UDim2.new(1, 0, 0, 40),
								}
							end,
						}
						if kind == "Table" then
							spec.columns = { { id = "label", label = "Name", width = 240 } }
							spec.render = nil
						end
						return (UI :: any)[kind](spec)
					end, target)
					local function row(key)
						return node:FindFirstChild(key, true)
					end
					expect((row("child"))):toBe(nil)
					expect(selection:peek().child):toBe(true)
					expect(row("empty"):FindFirstChild("Disclosure", true).Visible):toBe(true)
					local leafDisclosure = row("leaf"):FindFirstChild("Disclosure", true)
					expect(leafDisclosure == nil or not leafDisclosure.Visible):toBe(true)
					row("folder"):FindFirstChild("Disclosure", true).Activated:Fire()
					expect(requests):toBe(1)
					expect(row("child") ~= nil):toBe(true)
					expect((row("child"):FindFirstChild("OutlineRow", true):GetAttribute("FacetOutlineDepth"))):toBe(1)
					focus.focus("child")
					expect((focus.current:peek())):toBe("child")
					row("folder"):FindFirstChild("Disclosure", true).Activated:Fire()
					expect((row("child"))):toBe(nil)
					expect(selection:peek().child):toBe(true)
					expect((focus.current:peek())):toBe("folder")
					stop()
					runtime:dispose()
				end
			end,
		})
		it("keeps large animated branches windowed and preserves extent when expansion reverses", {
			id = "native_collections::outline collections::keeps large animated branches windowed and preserves extent when expansion reverses",
			run = function()
				local now = 0
				local engine, runtime, UI, target = setup({
					motionLevel = "normal",
					clock = function()
						return now
					end,
				})
				local children: { OutlineRecord } = {}
				for index = 1, 1000 do
					table.insert(children, { id = tostring(index) })
				end
				local expanded = Compose.cell({})
				local status: any = Compose.cell(nil)
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedOutlineSpec<OutlineRecord, string> = {
						from = { { id = "folder", children = children }, { id = "last" } } :: { OutlineRecord },
						key = "id",
						children = "children",
						expanded = expanded,
						itemSize = 40,
						status = status,
						render = function(): GuiObject
							return Facet.host(runtime).Frame {
								Size = engine.types.UDim2.new(1, 0, 0, 40),
							}
						end,
					}
					return UI.Outline(listSpec)
				end, target)
				engine.environment.poke(
					VerifyRoblox.assertInstance(node),
					"AbsoluteWindowSize",
					engine.types.Vector2.new(400, 240)
				)
				expanded:set({ folder = true })
				for _ = 1, 4 do
					now += 0.01
					engine.heartbeat:Fire(0.01)
					expect(status:peek().retained <= 12):toBe(true)
				end
				local before = status:peek().extent
				expanded:set({})
				expect(math.abs(status:peek().extent - before) < 0.001):toBe(true)
				for _ = 1, 20 do
					now += 0.02
					engine.heartbeat:Fire(0.02)
					expect(status:peek().retained <= 12):toBe(true)
				end
				expect(status:peek().total):toBe(2)
				stop()
				runtime:dispose()
			end,
		})

		it("prepares new outline rows before opening their space", function(_own, t)
			local now = 0
			local engine, runtime, UI, target, _, ctx = setup({
				motionLevel = "normal",
				clock = function()
					return now
				end,
			})
			ctx.config.services.RunService = (
				{ PreRender = engine.heartbeat, Heartbeat = engine.heartbeat } :: unknown
			) :: RunService
			local expanded = Compose.cell({} :: { [string]: boolean })
			local controls: FixtureComposeTypes.OrderedCollectionControls<string> = {}
			local release: (() -> ())? = nil
			local stop, root = runtime.mount(function()
				local listSpec: FixtureCollectionProps.KeyedOutlineSpec<OutlineRecord, string> = {
					from = { { id = "folder", children = { { id = "child" } } }, { id = "last" } } :: { OutlineRecord },
					key = "id",
					children = "children",
					expanded = expanded,
					mode = "all",
					itemSize = 80,
					controls = controls,
					render = function(current): GuiObject
						local caption = Facet.host(runtime).TextLabel {
							Text = current:peek().id,
							Size = engine.types.UDim2.new(1, 0, 0, 40),
						}
						if current:peek().id == "child" then
							release = require("../src/ui/text_measure").hold(caption)
						end
						return caption
					end,
				}
				return UI.Outline(listSpec)
			end, target)
			t:defer(function()
				stop()
				runtime:dispose()
			end)
			local function step()
				for _, node in ((root :: unknown) :: ScrollingFrame):GetDescendants() do
					if node:IsA("GuiObject") then
						engine.environment.poke(
							VerifyRoblox.assertInstance(node),
							"AbsoluteSize",
							engine.types.Vector2.new(400, 40)
						)
					end
					if node:IsA("TextLabel") then
						engine.environment.poke(
							VerifyRoblox.assertInstance(node),
							"TextBounds",
							engine.types.Vector2.new(80, 20)
						)
					end
				end
				now += 1 / 60
				engine.heartbeat:Fire(1 / 60)
			end
			for _ = 1, 4 do
				step()
			end
			expanded:set({ folder = true })
			for _ = 1, 8 do
				step()
				expect(assert(controls.placementOf)(2).size):toBe(0)
				expect(assert(controls.placementOf)(3).offset):toBe(80)
			end
			assert(release)()
			for _ = 1, 20 do
				step()
			end
			expect(assert(controls.placementOf)(2).size):toBe(80)
		end)

		it("animates row extent on expansion and collapse and honors reduced motion", {
			id = "native_collections::outline collections::animates row extent on expansion and collapse and honors reduced motion",
			run = function()
				for _, reduced in { false, true } do
					local now = 0
					local engine, runtime, UI, target = setup({
						motionLevel = if reduced then "none" else "normal",
						clock = function()
							return now
						end,
					})
					local expanded = Compose.cell({})
					local controls: any = {}
					local stop, node: any = runtime.mount(function()
						local listSpec: FixtureCollectionProps.KeyedOutlineSpec<OutlineRecord, string> = {
							from = { { id = "folder", children = { { id = "child" } } }, { id = "last" } } :: { OutlineRecord },
							key = "id",
							children = "children",
							expanded = expanded,
							mode = "all" :: "all",
							itemSize = 80,
							controls = controls,
							render = function(): GuiObject
								return Facet.host(runtime).Frame {
									Size = engine.types.UDim2.new(1, 0, 0, 40),
								}
							end,
						}
						return UI.Outline(listSpec)
					end, target)
					expanded:set({ folder = true })
					if not reduced then
						now += 0.025
						engine.heartbeat:Fire(0.025)
						local size = controls.placementOf(2).size
						expect(size > 0 and size < 80):toBe(true)
					end
					now += 1
					engine.heartbeat:Fire(1)
					expect(controls.placementOf(2).size):toBe(80)
					expanded:set({})
					if not reduced then
						now += 0.025
						engine.heartbeat:Fire(0.025)
						local size = controls.placementOf(2).size
						expect(size > 0 and size < 80):toBe(true)
						expect(node:FindFirstChild("child", true).Interactable):toBe(false)
					end
					now += 1
					engine.heartbeat:Fire(1)
					expect((node:FindFirstChild("child", true))):toBe(nil)
					stop()
					runtime:dispose()
				end
			end,
		})
	end)

	describe("collection row destinations", function()
		it("routes row centers to item drops, edges to insertion, and armed focus to collapsed folders", {
			id = "native_collections::collection row destinations::routes row centers to item drops, edges to insertion, and armed focus to collapsed folders",
			run = function()
				for _, kind in { "VirtualList", "VirtualGrid", "Outline", "Table" } do
					local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
					local drops, reorders = {}, {}
					local stop, node = runtime.mount(function()
						local spec: any = {
							from = {
								{ id = 1, label = "File" },
								{ id = 2, label = "Folder", children = { { id = 4, label = "Child" } } },
								{ id = 3, label = "File" },
							},
							key = function(item)
								return item.id
							end,
							itemSize = 60,
							editing = true,
							reorderable = true,
							collectionId = "library",
							drag = function(items, keys)
								return {
									payload = { collection = "library", items = items, keys = keys },
									operations = {
										"move",
									},
								}
							end,
							onReorder = function(keys, slot)
								table.insert(reorders, { keys, slot })
							end,
							rowDrop = function(current, key): FixtureEnvironmentTypes.DropTargetSpec?
								if key ~= 2 then
									return nil
								end
								return {
									accepts = function(payload)
										return (payload :: { kind: string? }).kind ~= "blocked",
											"Cannot put this in a folder"
									end,
									onDrop = function(payload)
										table.insert(drops, { key, payload })
										return true
									end,
								}
							end,
							render = function(current)
								return button(UI, current)
							end,
						}
						if kind == "Table" then
							spec.render = nil
							spec.columns = { { id = "label", label = "Name" } }
						end
						if kind == "Outline" then
							spec.children = "children"
						end
						return (UI :: any)[kind](spec)
					end, target)
					local root = node :: any
					local body = if kind == "Table" then root:FindFirstChild("Body") else root
					local V2 = engine.types.Vector2
					engine.environment.poke(VerifyRoblox.assertInstance(body), "AbsolutePosition", V2.new(0, 0))
					engine.environment.poke(VerifyRoblox.assertInstance(body), "AbsoluteWindowSize", V2.new(300, 240))
					nativeDrag.measure(body, engine.environment)
					local outer = body:FindFirstChild("2", true)
					engine.environment.poke(VerifyRoblox.assertInstance(outer), "AbsolutePosition", V2.new(0, 60))
					engine.environment.poke(VerifyRoblox.assertInstance(outer), "AbsoluteSize", V2.new(300, 60))
					local row = outer:FindFirstChild("Content")
					engine.environment.poke(VerifyRoblox.assertInstance(row), "AbsolutePosition", V2.new(0, 60))
					engine.environment.poke(VerifyRoblox.assertInstance(row), "AbsoluteSize", V2.new(300, 60))
					local session = require("../src/ui/drag_session")(ctx)
					local source = engine.new("TextButton")
					source.Parent = target
					session.begin(source, { payload = { collection = "library", keys = { 1 } } }, "pointer", nil, false)
					session.update(V2.new(150, 90))
					expect(assert(session.state:peek()).target):toBe(row)
					expect((row:GetAttribute("FacetDropState"))):toBe("accepted")
					session.update(if kind == "VirtualGrid" then V2.new(5, 90) else V2.new(150, 61))
					expect(assert(session.state:peek()).target):toBe(body)
					expect((row:GetAttribute("FacetDropState"))):toBeNil()
					session.update(V2.new(150, 90))
					session.commit(nil)
					expect(#drops):toBe(1)
					expect(#reorders):toBe(0)
					session.begin(source, { payload = { kind = "blocked" } }, "pointer", nil, false)
					session.update(V2.new(150, 90))
					expect((row:GetAttribute("FacetDropState"))):toBe("rejected")
					expect((row:GetAttribute("FacetDropReason"))):toBe("Cannot put this in a folder")
					session.commit(nil)
					expect(#drops):toBe(1)
					session.begin(source, { payload = { kind = "file" } }, "armed", nil, false)
					local hit = row:FindFirstChild("RowHit", true)
					expect((session.targetOf(hit))):toBe(row)
					hit.Activated:Fire({ UserInputType = engine.types.Enum.UserInputType.Touch }, 1)
					expect(#drops):toBe(2)
					expect((session.state:peek())):toBeNil()
					stop()
					runtime:dispose()
				end
			end,
		})
	end)
	local function registerRowActionScenarios(verifyHarness: Verify.Harness): ()
		local nativeDrag = require("./lib/native_drag")

		type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
		type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
		type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
		type RowActions = typeof(require("@repo/tools/typecheck/aliases").RowActions)
		local FixtureComposeTypes = require("../src/vendor/compose/core")
		local FixtureCollectionTypes = require("../src/ui/collection_types")
		local FixtureCollectionProps = require("../src/ui/collection_props")
		type Use = FixtureComposeTypes.Use

		local engineLib = require("./lib/native_engine")
		local playlistExample = require("../examples/gallery/examples/02_playlist_table")
		local Compose: ComposeModule = Facet.Compose

		type Stage = {
			engine: any,
			runtime: any,
			UI: any,
			Host: any,
			gui: any,
			input: any,
			screen: any,
			node: any,
			stop: () -> (),
		}

		local function services(engine: any): (any, any)
			local gui = (engine.new("GuiService") :: unknown) :: GuiService
			gui.TouchControlsEnabled = true
			engine.environment.fakeOn(VerifyRoblox.assertInstance(gui), "GetInsetArea", function()
				return engine.types.Rect.new(0, 0, 800, 600)
			end)
			local input = (engine.new("UserInputService") :: unknown) :: UserInputService
			engine.environment.fakeOn(VerifyRoblox.assertInstance(input), "IsKeyDown", function()
				return false
			end)
			idleInput(engine, VerifyRoblox.assertInstance(input))
			return gui, input
		end

		local function stage(
			build: (Facet.Controls, RobloxHost) -> GuiObject,
			config: Facet.ControlOptions?,
			clock: (() -> number)?
		): Stage
			local engine: any = engineLib.new()
			if clock then
				engine.clock = clock
			end
			local runtime: Facet.Runtime = Facet.Roblox.createRuntime(engine)
			local gui, input = services(engine)
			local options: Facet.ControlOptions = {
				types = engine.types,
				guiService = gui,
				userInputService = input,
				services = { GuiService = gui, UserInputService = input },
				motionLevel = if config and config.motionLevel then config.motionLevel else "none",
				theme = if config then config.theme else nil,
			}
			local UI = Facet.controls(runtime, options)
			local Host = Facet.host(runtime)
			local stop, screen: any = runtime.mount(function()
				return Host.ScreenGui { build(UI, Host) }
			end, engine.new("Folder"))
			return {
				engine = engine,
				runtime = runtime,
				UI = UI,
				Host = Host,
				gui = gui,
				input = input,
				screen = screen,
				node = screen:FindFirstChildWhichIsA("Frame"),
				stop = function()
					stop()
					runtime:dispose()
				end,
			}
		end

		local function records(count: number): { any }
			local values = {}
			for index = 1, count do
				values[index] = { id = index, label = tostring(index) }
			end
			return values
		end

		local function id(item: any): any
			return item.id
		end

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

		local function key(root: any, engine: any, code: string): string?
			local wanted = engine.types.Enum.KeyCode[code]
			local best, bestPriority = nil, -math.huge
			for _, context in root:GetDescendants() do
				if context.ClassName == "InputContext" and context.Enabled == true then
					for _, action in context:GetChildren() do
						if action.ClassName == "InputAction" then
							for _, binding in action:GetChildren() do
								if
									binding.ClassName == "InputBinding"
									and binding.KeyCode == wanted
									and context.Priority > bestPriority
								then
									best, bestPriority = action, context.Priority
								end
							end
						end
					end
				end
			end
			if best == nil then
				return nil
			end
			best.Pressed:Fire()
			return best.Name
		end

		local function focus(gui: any, node: any)
			local previous = gui.SelectedObject
			gui.SelectedObject = node
			if previous and previous ~= node then
				previous.SelectionLost:Fire()
			end
			if node and previous ~= node then
				node.SelectionGained:Fire()
			end
		end

		local function span(rowNode: any, target: any, canvasX: number): (number, number)
			local path = {}
			local cursor = target
			while cursor and cursor ~= rowNode do
				table.insert(path, 1, cursor)
				cursor = cursor.Parent
			end
			assert(cursor == rowNode, "target is not inside the row")
			local x, width = rowNode.Position.X.Offset - canvasX, rowNode.Size.X.Offset
			for _, node in path do
				local nextWidth = node.Size.X.Scale * width + node.Size.X.Offset
				x += node.Position.X.Scale * width + node.Position.X.Offset - node.AnchorPoint.X * nextWidth
				width = nextWidth
			end
			return x, width
		end

		local function cellRow(rowNode: any): any
			return assert(rowNode:FindFirstChild("DisclosingRow", true)):FindFirstChild("Row")
		end

		local function expectSameColumns(header: any, row: any, columns: { string })
			for _, column in columns do
				local top, cell = header:FindFirstChild(column), row:FindFirstChild(column)
				expect(top.Size):toBe(cell.Size)
				expect(top.LayoutOrder):toBe(cell.LayoutOrder)
				expect(top.Visible):toBe(cell.Visible)
				expect(top:FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(
					cell:FindFirstChildWhichIsA("UIFlexItem").FlexMode
				)
				local topLimit, cellLimit =
					top:FindFirstChildWhichIsA("UISizeConstraint"), cell:FindFirstChildWhichIsA("UISizeConstraint")
				expect(topLimit.MinSize):toBe(cellLimit.MinSize)
				expect(topLimit.MaxSize):toBe(cellLimit.MaxSize)
			end
		end

		local function expectAligned(table_: any, key_: string, columns: { string })
			local header, body = table_:FindFirstChild("Header"), table_:FindFirstChild("Body")
			local rowNode = body:FindFirstChild("Items"):FindFirstChild(key_)
			local row = cellRow(rowNode)
			local x, width = span(rowNode, row, body.CanvasPosition.X)
			expect(x):toBe(header.Position.X.Offset)
			expect(width):toBe(header.Size.X.Offset)
			expectSameColumns(header, row, columns)
		end

		type Playlist = {
			built: any,
			node: any,
			engine: any,
			gui: any,
			input: any,
			target: any,
			tracks: any,
			stop: () -> (),
		}

		describe("native parity weaker tables", function() end)
		describe("Table edit layout frames", function()
			for _, width in { 390, 320 } do
				it(`keeps header and body cell rectangles together through Edit and Done at {width}`, {
					id = `native_collections::Table edit layout frames::keeps header and body cell rectangles together through Edit and Done at {width}`,
					run = function()
						local editing = Compose.cell(false)
						local now = 0
						local w = stage(function(UI, Host)
							local tableSpec: FixtureCollectionProps.KeyedTableSpec<
								{ id: string, name: string, artist: string },
								string
							> =
								{
									from = { { id = "neon", name = "Neon Straightaway", artist = "Chrome Coyote" } },
									key = "id",
									editing = editing,
									selectionMode = "multiple",
									reorderable = true,
									deletable = true,
									onReorder = function() end,
									onDelete = function() end,
									columns = {
										{ id = "name", minWidth = 90, wrap = false },
										{ id = "artist", minWidth = 72, priority = 1, wrap = false },
										{ id = "rating", width = 144, priority = 2 },
									} :: { any },
								}
							return UI.Table(tableSpec)
						end, { motionLevel = "normal" }, function()
							return now
						end)
						w.engine.environment.poke(
							VerifyRoblox.assertInstance(w.input),
							"PreferredInput",
							w.engine.types.Enum.PreferredInput.Touch
						)
						local body = w.node:FindFirstChild("Body")
						w.engine.environment.poke(
							VerifyRoblox.assertInstance(body),
							"AbsoluteWindowSize",
							w.engine.types.Vector2.new(width, 240)
						)
						local row = body:FindFirstChild("Items"):FindFirstChild("neon")
						row.Size = w.engine.types.UDim2.fromOffset(width, 44)
						for _, label in row:GetDescendants() do
							if label.Name == "Undisclosed" then
								w.engine.environment.poke(VerifyRoblox.assertInstance(label), "TextFits", true)
							end
						end
						local function sample()
							expectAligned(w.node, "neon", { "name", "artist", "rating" })
							local header, cells = w.node:FindFirstChild("Header"), cellRow(row)
							local left, lane = span(row, cells, 0)
							local offset = 0
							for _, column in { "name", "artist", "rating" } do
								local top, value = header:FindFirstChild(column), cells:FindFirstChild(column)
								if top.Visible then
									local topWidth = top.Size.X.Scale * header.Size.X.Offset + top.Size.X.Offset
									local cellWidth = value.Size.X.Scale * lane + value.Size.X.Offset
									expect(left + offset):toBe(header.Position.X.Offset + offset)
									expect(cellWidth):toBe(topWidth)
									offset += topWidth
								end
							end
							expect(offset <= lane):toBe(true)
							expect(left + lane <= width):toBe(true)
							local mark = row:FindFirstChild("SelectMark", true)
							if mark and mark.Visible then
								expect(left >= 44):toBe(true)
							end
						end
						for _, mode in { false, true, false } do
							editing:set(mode)
							sample()
							for _ = 1, 30 do
								now += 1 / 30
								w.engine.heartbeat:Fire(1 / 30)
								sample()
							end
						end
						w.stop()
					end,
				})
			end
		end)
		describe("Table narrow column policy", function()
			type NarrowRow = { id: string, name: string, artist: string, rating: string }
			it("keeps fitting secondary columns beside bounded primary text", {
				id = "native_collections::Table narrow column policy::keeps fitting secondary columns beside bounded primary text",
				run = function()
					for _, mode in { "fixed", "resized", "flexible" } do
						local widths = Compose.cell(if mode == "resized" then { name = 120 } else {})
						local w = stage(function(UI)
							local spec: FixtureCollectionProps.KeyedTableSpec<NarrowRow, string> = {
								from = {
									{
										id = "row",
										name = string.rep("Long name ", 200),
										artist = "Artist",
										rating = "Five",
									},
								},
								key = "id",
								widths = widths,
								columns = {
									{
										id = "name",
										width = if mode == "fixed" then 100 else nil,
										minWidth = 48,
										maxWidth = 160,
									},
									{ id = "artist", width = 100, priority = 1 },
									{ id = "rating", width = 100, priority = 1 },
								},
							}
							return UI.Table(spec)
						end)
						local body = w.node:FindFirstChild("Body")
						w.engine.environment.poke(
							VerifyRoblox.assertInstance(body),
							"AbsoluteWindowSize",
							w.engine.types.Vector2.new(1000, 240)
						)
						local cells = cellRow(body:FindFirstChild("Items"):FindFirstChild("row"))
						w.engine.environment.poke(
							VerifyRoblox.assertInstance(
								cells:FindFirstChild("name"):FindFirstChild("Undisclosed", true)
							),
							"TextBounds",
							w.engine.types.Vector2.new(2000, 16)
						)
						local header = w.node:FindFirstChild("Header")
						for _, id_ in { "name", "artist", "rating" } do
							expect(header:FindFirstChild(id_).Visible):toBe(true)
							expect(cells:FindFirstChild(id_).Visible):toBe(true)
						end
						expect(cells:FindFirstChild("name").Size.X.Offset):toBe(
							if mode == "fixed" then 100 elseif mode == "resized" then 120 else 160
						)
						expectSameColumns(header, cells, { "name", "artist", "rating" })
						w.stop()
					end
				end,
			})

			it("publishes collapsed columns only when membership changes during resizing", {
				id = "native_collections::Table narrow column policy::publishes collapsed columns only when membership changes during resizing",
				run = function()
					local createMetrics = require("../src/ui/collection_table_metrics")
					local createColumns = require("../src/ui/collection_table_columns")
					local engine, runtime, _, target, _, ctx = setup()
					local widths: FixtureComposeTypes.Value<{ [string]: number }> = Compose.cell({ name = 120 })
					local definitions: { FixtureCollectionTypes.TableColumn<string, string> } = {
						{ id = "name", minWidth = 80 },
						{ id = "artist", width = 100, priority = 1 },
						{ id = "rating", width = 100, priority = 2 },
					}
					local columns = Compose.cell(definitions)
					local spec: FixtureCollectionProps.IdentityTableSpec<string> = { from = {}, columns = columns }
					local changes = 0
					local prepared: createColumns.Columns<string, string>? = nil
					local stop = runtime.mount(function()
						local unitScale = Compose.cell(1)
						local metrics = createMetrics(ctx, spec, false, unitScale, Compose.cell({}))
						local layout = createColumns(
							ctx,
							spec,
							widths,
							Compose.cell({}),
							metrics,
							Compose.cell({}),
							function(item: string)
								return item
							end,
							function()
								return nil
							end,
							unitScale
						)
						prepared = layout
						Compose.watch(function(use)
							use(layout.collapsed)
							changes += 1
						end)
						return metrics.textInsets
					end, target)
					local layout = assert(prepared)
					layout.viewportWidth:set(400)
					for _, width in { 160, 200 } do
						widths:set({ name = width })
						expect((next(layout.collapsed:peek()))):toBeNil()
						expect(changes):toBe(1)
					end
					widths:set({ name = 220 })
					local previous = layout.collapsed:peek()
					expect(previous.rating):toBe(true)
					expect(previous.artist):toBeNil()
					expect(changes):toBe(2)
					widths:set({ name = 230 })
					expect(changes):toBe(2)
					columns:set({
						{ id = "name", minWidth = 80 },
						{ id = "artist", width = 100, priority = 2 },
						{ id = "rating", width = 100, priority = 1 },
					})
					expect(layout.collapsed:peek().artist):toBe(true)
					expect(layout.collapsed:peek().rating):toBeNil()
					expect(changes):toBe(3)
					expect(previous.rating):toBe(true)
					expect(previous.artist):toBeNil()
					layout.viewportWidth:set(800)
					expect((next(layout.collapsed:peek()))):toBeNil()
					expect(changes):toBe(4)
					layout.viewportWidth:set(250)
					expect(layout.collapsed:peek().artist):toBe(true)
					expect(layout.collapsed:peek().rating):toBe(true)
					expect(changes):toBe(5)
					layout.viewportWidth:set(260)
					expect(changes):toBe(5)
					layout.viewportWidth:set(800)
					expect((next(layout.collapsed:peek()))):toBeNil()
					expect(changes):toBe(6)
					stop()
					runtime:dispose()
					expect(engine.census().connections):toBe(0)
				end,
			})

			it("bounds fixed and controlled widths through reactive column limits", {
				id = "native_collections::Table narrow column policy::bounds fixed and controlled widths through reactive column limits",
				run = function()
					local widths = Compose.cell({})
					local definitions: { FixtureCollectionTypes.TableColumn<{ id: string, name: string }, string> } =
						{ { id = "name", width = 300, minWidth = 48, maxWidth = 160 } }
					local columns = Compose.cell(definitions)
					local w = stage(function(UI)
						local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: string, name: string }, string> = {
							from = { { id = "row", name = "Name" } },
							key = "id",
							widths = widths,
							columns = columns,
						}
						return UI.Table(tableSpec)
					end)
					local body = w.node:FindFirstChild("Body")
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(body),
						"AbsoluteWindowSize",
						w.engine.types.Vector2.new(1000, 240)
					)
					local cells = cellRow(body:FindFirstChild("Items"):FindFirstChild("row"))
					local header = w.node:FindFirstChild("Header")
					local function sample(expected: number)
						for _, row_ in { header, cells } do
							local cell = row_:FindFirstChild("name")
							local constraint = cell:FindFirstChildWhichIsA("UISizeConstraint")
							expect(cell.Size.X.Offset):toBe(expected)
							expect(constraint.MaxSize.X <= columns:peek()[1].maxWidth):toBe(true)
							expect(constraint.MinSize.X):toBe(columns:peek()[1].minWidth)
						end
						expectSameColumns(header, cells, { "name" })
					end
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(body),
						"AbsoluteWindowSize",
						w.engine.types.Vector2.new(1000, 240)
					)
					sample(160)
					widths:set({ name = 600 })
					sample(160)
					columns:set({ { id = "name", width = 300, minWidth = 48, maxWidth = 96 } })
					sample(96)
					widths:set({ name = 20 })
					sample(48)
					columns:set({ { id = "name", width = 300, minWidth = 80, maxWidth = 96 } })
					sample(80)
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(body),
						"AbsoluteWindowSize",
						w.engine.types.Vector2.new(0, 240)
					)
					sample(80)
					w.stop()
				end,
			})

			it("protects primary text and retains a collapsed rendered cell while Details opens", {
				id = "native_collections::Table narrow column policy::protects primary text and retains a collapsed rendered cell while Details opens",
				run = function()
					local editing, builds, detailChanges = Compose.cell(true), 0, 0
					local w = stage(function(UI, Host)
						local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: string, name: string, artist: string }, string> =
							{
								from = { { id = "neon", name = "Neon Straightaway", artist = "Chrome Coyote" } },
								key = "id",
								editing = editing,
								selectionMode = "multiple",
								reorderable = true,
								onReorder = function() end,
								columns = {
									{ id = "name", minWidth = 90, wrap = false },
									{ id = "artist", minWidth = 72, priority = 1, wrap = false },
									{
										id = "rating",
										width = 144,
										priority = 2,
										detailRender = function()
											return UI.Button "DetailRating" {
												onActivate = function()
													detailChanges += 1
												end,
											}
										end,
										render = function()
											builds += 1
											return Host.TextBox { Name = "LocalRating", Text = "Local edit" }
										end,
									},
								} :: { any },
							}
						return UI.Table(tableSpec)
					end)
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(w.input),
						"PreferredInput",
						w.engine.types.Enum.PreferredInput.Touch
					)
					local body = w.node:FindFirstChild("Body")
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(body),
						"AbsoluteWindowSize",
						w.engine.types.Vector2.new(390, 240)
					)
					local row = body:FindFirstChild("Items"):FindFirstChild("neon")
					local cells, header = cellRow(row), w.node:FindFirstChild("Header")
					local primary = cells:FindFirstChild("name")
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(primary:FindFirstChild("Undisclosed", true)),
						"TextBounds",
						w.engine.types.Vector2.new(172, 16)
					)
					expect(header:FindFirstChild("name").Visible):toBe(true)
					expect(header:FindFirstChild("rating").Visible):toBe(false)
					expect(primary.Size.X.Offset >= 188):toBe(true)
					expect(primary:FindFirstChild("Value", true).TextWrapped):toBe(false)
					expect(cells:FindFirstChild("artist"):FindFirstChild("Value", true).TextWrapped):toBe(false)
					local rating = cells:FindFirstChild("rating"):FindFirstChild("LocalRating", true)
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(rating),
						"AbsoluteSize",
						w.engine.types.Vector2.new(144, 100)
					)
					expect(row.Size.Y.Offset):toBe(44)
					row:FindFirstChild("Details", true).Activated:Fire()
					expect(cells:FindFirstChild("rating"):FindFirstChild("LocalRating", true)):toBe(rating)
					expect(w.screen:FindFirstChild("Popup", true):FindFirstChild("rating", true) ~= nil):toBe(true)
					find(w.screen, "DetailRating").Activated:Fire()
					expect(detailChanges):toBe(1)
					expect(builds):toBe(1)
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(body),
						"AbsoluteWindowSize",
						w.engine.types.Vector2.new(800, 240)
					)
					expect(cells:FindFirstChild("rating"):FindFirstChild("LocalRating", true)):toBe(rating)
					expect(rating.Text):toBe("Local edit")
					expect(builds):toBe(1)
					w.stop()
				end,
			})

			it("includes native pseudo padding in primary text space", {
				id = "native_collections::Table narrow column policy::includes native pseudo padding in primary text space",
				run = function()
					local w = stage(function(UI)
						local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: string, name: string, artist: string }, string> =
							{
								from = { { id = "neon", name = "Neon Straightaway", artist = "Chrome Coyote" } },
								key = "id",
								editing = true,
								selectionMode = "multiple",
								reorderable = true,
								onReorder = function() end,
								columns = {
									{ id = "name", minWidth = 90, wrap = false },
									{ id = "artist", minWidth = 72, priority = 1, wrap = false },
									{ id = "rating", width = 144, priority = 2 },
								} :: { FixtureCollectionTypes.TableColumn<any, string> },
							}
						return UI.Table(tableSpec)
					end)
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(w.input),
						"PreferredInput",
						w.engine.types.Enum.PreferredInput.Touch
					)
					local body = w.node:FindFirstChild("Body")
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(body),
						"AbsoluteWindowSize",
						w.engine.types.Vector2.new(353, 240)
					)
					local cells = cellRow(body:FindFirstChild("Items"):FindFirstChild("neon"))
					local primary = cells:FindFirstChild("name")
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(primary:FindFirstChild("Undisclosed", true)),
						"TextBounds",
						w.engine.types.Vector2.new(116, 16)
					)
					local inset = assert(w.node:FindFirstChild("CellTextInsets"))
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(inset),
						"AbsoluteSize",
						w.engine.types.Vector2.new(24, 16)
					)
					expect(primary.Size.X.Offset >= 140):toBe(true)
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(inset),
						"AbsoluteSize",
						w.engine.types.Vector2.new(40, 16)
					)
					expect(primary.Size.X.Offset >= 156):toBe(true)
					expect(w.node:FindFirstChild("Header"):FindFirstChild("artist").Visible):toBe(false)
					w.stop()
				end,
			})

			it("retains a measured column width while its row is outside the viewport", {
				id = "native_collections::Table narrow column policy::retains a measured column width while its row is outside the viewport",
				run = function()
					local wide = { id = "wide", name = "A long name" }
					local short = { id = "short", name = "Short" }
					local rows = Compose.cell({ wide, short })
					local w = stage(function(UI)
						local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: string, name: string }, string> = {
							from = rows,
							key = "id",
							itemSize = 40,
							overscan = 0,
							columns = {
								{ id = "name", minWidth = 90 },
								{ id = "artist", minWidth = 72, priority = "always" },
							},
						}
						return UI.Table(tableSpec)
					end)
					local body = w.node:FindFirstChild("Body")
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(body),
						"AbsoluteWindowSize",
						w.engine.types.Vector2.new(400, 40)
					)
					local items = body:FindFirstChild("Items")
					local row = assert(items:FindFirstChild("wide"))
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(
							cellRow(row):FindFirstChild("name"):FindFirstChild("Undisclosed", true)
						),
						"TextBounds",
						w.engine.types.Vector2.new(200, 16)
					)
					local header = w.node:FindFirstChild("Header"):FindFirstChild("name")
					local widest = header.Size.X.Offset
					body.CanvasPosition = w.engine.types.Vector2.new(0, 40)
					expect(items:FindFirstChild("wide") == nil):toBe(true)
					expect(header.Size.X.Offset):toBe(widest)
					rows:set({ short })
					expect(header.Size.X.Offset < widest):toBe(true)
					w.stop()
				end,
			})
			it("restores measured text widths after an empty filter and rejects changed text", {
				id = "native_collections::Table narrow column policy::restores measured text widths after an empty filter and rejects changed text",
				run = function()
					local wide = { id = "wide", name = "A long name" }
					local rows = Compose.cell({ wide })
					local w = stage(function(UI)
						local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: string, name: string }, string> = {
							from = rows,
							key = "id",
							columns = {
								{ id = "name", minWidth = 90 },
								{ id = "artist", minWidth = 72, priority = "always" },
							},
						}
						return UI.Table(tableSpec)
					end)
					local body = w.node:FindFirstChild("Body")
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(body),
						"AbsoluteWindowSize",
						w.engine.types.Vector2.new(400, 240)
					)
					local function label()
						return cellRow(body:FindFirstChild("Items"):FindFirstChild("wide"))
							:FindFirstChild("name")
							:FindFirstChild("Undisclosed", true)
					end
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(label()),
						"TextBounds",
						w.engine.types.Vector2.new(200, 16)
					)
					local header = w.node:FindFirstChild("Header"):FindFirstChild("name")
					local width = header.Size.X.Offset
					rows:set({})
					expect(header.Size.X.Offset < width):toBe(true)
					rows:set({ wide })
					expect(header.Size.X.Offset):toBe(width)
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(label()),
						"TextBounds",
						w.engine.types.Vector2.zero
					)
					expect(header.Size.X.Offset):toBe(width)
					rows:set({ { id = "wide", name = "Different" } })
					expect(header.Size.X.Offset < width):toBe(true)
					rows:set({ wide })
					expect(header.Size.X.Offset):toBe(width)
					w.node:FindFirstChild("CellTextInsets").TextSize = 24
					expect(header.Size.X.Offset < width):toBe(true)
					w.stop()
				end,
			})
			it("releases removed text measurements and keeps the remaining widest row", {
				id = "native_collections::Table narrow column policy::releases removed text measurements and keeps the remaining widest row",
				run = function()
					local wide = { id = "wide", name = "A long name" }
					local twin = { id = "twin", name = "Another long name" }
					local short = { id = "short", name = "Short" }
					local rows = Compose.cell({ wide, twin, short })
					local w = stage(function(UI)
						local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: string, name: string }, string> = {
							from = rows,
							key = "id",
							columns = {
								{ id = "name", minWidth = 90 },
								{ id = "artist", minWidth = 72, priority = "always" },
							},
						}
						return UI.Table(tableSpec)
					end)
					local body = w.node:FindFirstChild("Body")
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(body),
						"AbsoluteWindowSize",
						w.engine.types.Vector2.new(400, 240)
					)
					for _, key in { "wide", "twin", "short" } do
						local row = body:FindFirstChild("Items"):FindFirstChild(key)
						w.engine.environment.poke(
							VerifyRoblox.assertInstance(
								cellRow(row):FindFirstChild("name"):FindFirstChild("Undisclosed", true)
							),
							"TextBounds",
							w.engine.types.Vector2.new(if key == "short" then 100 else 200, 16)
						)
					end
					local header = w.node:FindFirstChild("Header"):FindFirstChild("name")
					local widest = header.Size.X.Offset
					rows:set({ twin, short })
					expect(header.Size.X.Offset):toBe(widest)
					rows:set({ short })
					expect(header.Size.X.Offset < widest):toBe(true)
					w.stop()
				end,
			})
			it("crossfades Edit Done and Delete with theme timing while layout changes together", {
				id = "native_collections::Table narrow column policy::crossfades Edit Done and Delete with theme timing while layout changes together",
				run = function()
					local now = 0
					local theme = Compose.cell(nil :: any)
					local w = stage(function(UI)
						local tableSpec: FixtureCollectionProps.KeyedTableSpec<{ id: string, name: string }, string> = {
							from = { { id = "1", name = "One" } },
							key = "id",

							deletable = true,
							onDelete = function() end,
							columns = { { id = "name" } },
						}
						return UI.Table(tableSpec)
					end, { motionLevel = "normal", theme = theme }, function()
						return now
					end)
					w.engine.environment.poke(
						VerifyRoblox.assertInstance(w.input),
						"PreferredInput",
						w.engine.types.Enum.PreferredInput.Touch
					)
					local edit, done, fade =
						find(w.node, "EditCaption"), find(w.node, "DoneCaption"), find(w.node, "DeleteFade")
					expect(edit.TextTransparency):toBe(0)
					expect(done.TextTransparency):toBe(1)
					for _, mode in { true, false } do
						find(w.node, "Edit").Activated:Fire()
						now += 1 / 30
						w.engine.heartbeat:Fire(1 / 30)
						expect(edit.TextTransparency > 0 and edit.TextTransparency < 1):toBe(true)
						expect(edit.TextTransparency + done.TextTransparency):toBe(1)
						expect(fade:FindFirstChild("FadePaint").Transparency.Keypoints[1].Value):toBeCloseTo(
							done.TextTransparency,
							5
						)
						for _ = 1, 30 do
							now += 1 / 30
							w.engine.heartbeat:Fire(1 / 30)
						end
						expect(done.TextTransparency):toBe(if mode then 0 else 1)
					end
					local package = require("../examples/themes/glossy_touch").build(Facet.themes)
					theme:set(package)
					local label = find(w.node, "Edit"):FindFirstChild("Label", true)
					expect(label.TextTransparency):toBe(1)
					w.stop()
				end,
			})
		end)
	end
	registerRowActionScenarios(verifyHarness)
end
