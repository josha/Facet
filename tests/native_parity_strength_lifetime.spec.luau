--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureRadialTypes = require("../src/ui/radial_types")
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	local FixtureThemeTypes = require("../src/ui/theme_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local gallery = require("../examples/gallery/client/screen")
	local Compose: ComposeModule = Facet.Compose
	local InspectState = require("../src/vendor/compose/core/ownership/inspect")

	type Census = { live: number, connections: number, owners: number, holding: number, mounts: number }

	local function owners(): (number, number)
		local report = Compose.inspect.snapshot()
		assert(report.active and report.droppedOwners == 0, "the owner census is incomplete")
		local count, holding = 0, 0
		local function walk(entry: any)
			if not entry.disposed and entry.holding > 0 then
				count += 1
				holding += entry.holding
			end
			for _, child in entry.children do
				walk(child)
			end
		end
		for _, entry in report.mounts do
			walk(entry)
		end
		for _, entry in report.detached do
			walk(entry)
		end
		return count, holding
	end

	local function census(engine: any): Census
		local now = engine.census()
		local count, holding = owners()
		return {
			live = now.live,
			connections = now.connections,
			owners = count,
			holding = holding,
			mounts = Compose.outstandingMounts(),
		}
	end

	local function same(before: Census, after: Census, label: string)
		for _, field in { "live", "connections", "owners", "holding", "mounts" } do
			local was, now = (before :: any)[field], (after :: any)[field]
			assert(was == now, `{label}: {field} {was} -> {now}`)
		end
	end

	local function inspected(body: () -> ())
		Compose.inspect.start({ maxOwners = 1000000, maxNodes = 1000000 })

		setmetatable((InspectState.__state() :: any).records, nil)
		local ok, failure = pcall(function(): boolean
			body()
			return true
		end)
		Compose.inspect.stop()
		if not ok then
			error(failure, 0)
		end
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

	local function controlsFor(ctx: any): any
		ctx.UI = Facet.controls(
			ctx.runtime,
			{
				types = ctx.types,
				viewport = ctx.viewport,
				guiService = ctx.guiService,
				services = { GuiService = ctx.guiService },
				motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
					return if ctx.reducedMotion and use(ctx.reducedMotion) then "none" else "normal"
				end) :: unknown) :: MotionLevel,
			} :: any
		)
		return ctx
	end

	local function exampleContext(engine: any, extra: { [string]: any }?): any
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local viewport = Compose.cell({ width = 1280, height = 720 })
		local target = engine.new("Folder")
		local guiService = engine.new("GuiService")
		local ctx: { [string]: any } = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			types = engine.types,
			viewport = viewport,
			inputTarget = target,
			worldTarget = engine.new("Folder"),
			guiService = guiService,
			runService = { Heartbeat = engine.heartbeat },
			target = target,
			engine = engine,
		}
		for key, value in (extra or {}) :: { [string]: any } do
			ctx[key] = value
		end
		return controlsFor(ctx)
	end

	local function mountModule(ctx: any, module: any, wrap: boolean?): (any, any, () -> ())
		local built
		local stop, node = ctx.runtime.mount(function()
			if ctx.reducedMotion == nil then
				gallery.configure(ctx)
				controlsFor(ctx)
			end
			built = module.build(ctx)
			if built.dispose then
				Compose.cleanup(built.dispose)
			end
			if wrap then
				return ctx.Host.ScreenGui({ built.screen() })
			end
			return built.screen()
		end, ctx.target)
		return built, node, function()
			stop()
			ctx.runtime:dispose()
		end
	end

	local function example(name: string): any
		return require("../examples/gallery/examples/" .. name) :: any
	end

	local function radialWorld(animated: boolean): any
		local engine, now = engineLib.new(), 0
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		engine.clock = function()
			return now
		end
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				services = { GuiService = gui, UserInputService = input },
				motionLevel = if not animated then "none" else "normal",
			} :: any
		)
		return {
			engine = engine,
			gui = gui,
			input = input,
			runtime = runtime,
			UI = UI,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			target = engine.new("Folder"),
			step = function(seconds: number)
				for _ = 1, math.ceil(seconds * 60) do
					now += 1 / 60
					engine.heartbeat.fire(1 / 60)
				end
			end,
		}
	end

	local function touch(engine: any, x: number, y: number): any
		return {
			UserInputType = engine.types.Enum.UserInputType.Touch,
			UserInputState = engine.types.Enum.UserInputState.Begin,
			Position = engine.types.Vector3.new(x, y, 0),
		}
	end

	local function controlWorld(options: { [string]: any }?): any
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local root = engine.new("ScreenGui")
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui, UserInputService = input },
			userInputService = input,
			inputParent = root,
			motionLevel = "none",
		}
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config :: any)
		return {
			engine = engine,
			runtime = runtime,
			UI = UI,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			gui = gui,
			input = input,
			root = root,
		}
	end

	local function settle(engine: any, seconds: number)
		for _ = 1, math.ceil(seconds * 60) do
			engine.heartbeat.fire(1 / 60)
		end
	end

	local function records(count: number): { any }
		local values = {}
		for index = 1, count do
			values[index] = { id = index, label = tostring(index) }
		end
		return values
	end

	local function byId(item: any): any
		return item.id
	end

	local function shape(root: any): { string }
		local paths = {}
		local function walk(node: any, prefix: string)
			for _, child in node:GetChildren() do
				local path = prefix .. "/" .. child.Name
				table.insert(paths, path)
				walk(child, path)
			end
		end
		walk(root, "")
		table.sort(paths)
		return paths
	end

	local function skinnedPackage(content: any?): any
		local package = Facet.themes.neutralPackage() :: any
		package.assets = {
			rest = { content = "rbxassetid://1" },
			corner = { content = "rbxassetid://3" },
			plate = { content = "rbxassetid://5" },
		}
		package.chrome.control = {
			kind = "layered" :: "layered",
			layers = {
				{ kind = "fill" :: "fill", asset = "rest" } :: FixtureThemeTypes.SkinLayer,
				{ kind = "corners" :: "corners", asset = "corner", topLeft = "corner", topRight = "corner", size = 12 } :: FixtureThemeTypes.SkinLayer,
				{
					kind = "plaque" :: "plaque",
					asset = "plate",
					edge = "top" :: "top",
					overhang = 6,
					size = { w = 80, h = 24 },
					text = true,
					textInsets = { left = 4, right = 4 },
				} :: FixtureThemeTypes.SkinLayer,
			},
		}
		if content then
			package.style.themes[1].colors.content = content
		end
		return package
	end

	local function images(root: any): { any }
		local found = {}
		for _, node in root:GetDescendants() do
			if node.ClassName == "ImageLabel" then
				table.insert(found, node)
			end
		end
		return found
	end

	verifyHarness:suite("lifetime parity strength", function()
		verifyHarness:case("returns every game to its instance connection and owner baseline after play", {
			id = "native_parity_strength_lifetime::lifetime parity strength::returns every game to its instance connection and owner baseline after play",
			run = function()
				local plays: { [string]: (any, any, any) -> () } = {
					["05_word_game"] = function(game)
						game.restart(1)
						for _, key in { "R", "E", "A", "C", "T", "Return", "R", "U", "L", "E", "S", "Return" } do
							game.press(key)
						end
					end,
					["06_tile_game"] = function(game, node)
						local letter = game.rackLetter(1)
						find(node, "rt1").Activated.fire()
						find(find(node, "cell4_4"), "tap").Activated.fire()
						assert(game.pendingAt(4, 4) == letter, "the crossword did not place a rack tile")
						game.submit()
					end,
					["07_match3"] = function(game, _, ctx)
						game.swap(1, 1, 1, 2)
						for _ = 1, 600 do
							ctx.engine.heartbeat.fire(1 / 60)
						end
						assert(not game.isResolving(), "the match-three board did not settle")
					end,
				}
				for name, play in plays do
					inspected(function()
						local engine = engineLib.new()
						local ctx = exampleContext(engine)
						local before = census(engine)
						local game, node, close = mountModule(ctx, example(name), true)
						local mounted = census(engine)
						assert(mounted.live > before.live + 20, `{name}: the game did not mount`)
						assert(mounted.owners > before.owners, `{name}: the game owned no Compose owner`)
						play(game, node, ctx)
						close()
						Verify.expect(#ctx.target:GetChildren()):toBe(0)
						Verify.expect((engine.heartbeat.count())):toBe(0)
						same(before, census(engine), `{name} teardown`)
					end)
				end
			end,
		})
		verifyHarness:case("resets the match-three machine mid-cascade without a retiring tile or frame hook", {
			id = "native_parity_strength_lifetime::lifetime parity strength::resets the match-three machine mid-cascade without a retiring tile or frame hook",
			run = function()
				inspected(function()
					local engine = engineLib.new()
					local ctx = exampleContext(engine)
					local before = census(engine)
					local game, node, close = mountModule(ctx, example("07_match3"), true)
					game.debugSetBoard({
						{ "b", "c", "d", "e", "a", "b" },
						{ "c", "d", "e", "a", "b", "c" },
						{ "a", "a", "b", "d", "e", "a" },
						{ "d", "e", "a", "b", "c", "d" },
						{ "e", "a", "b", "c", "d", "e" },
						{ "a", "b", "c", "d", "e", "a" },
					})
					local retiring = find(node, "tile" .. game.tileIdAt(3, 1))
					game.swap(3, 3, 4, 3)
					for _ = 1, 2400 do
						if game.phase() == "remove" then
							break
						end
						engine.heartbeat.fire(0.01)
					end
					Verify.expect((game.phase())):toBe("remove")
					engine.heartbeat.fire(0.04)
					Verify.expect((retiring.isDestroyed())):toBe(false)
					Verify.expect(retiring.GroupTransparency > 0 and retiring.GroupTransparency < 1):toBe(true)
					Verify.expect((game.tickHookActive())):toBe(true)
					Verify.expect(engine.heartbeat.count() > 0):toBe(true)
					find(node, "Reset").Activated.fire()
					Verify.expect((game.phase())):toBe("idle")
					Verify.expect(#game.phaseLog()):toBe(0)
					Verify.expect((game.isResolving())):toBe(false)
					Verify.expect((game.tickHookActive())):toBe(false)
					Verify.expect((game.score())):toBe(0)
					Verify.expect((game.moves())):toBe(0)
					for _ = 1, 180 do
						engine.heartbeat.fire(1 / 60)
					end
					Verify.expect((engine.heartbeat.count())):toBe(0)
					Verify.expect((retiring.isDestroyed())):toBe(true)
					local live = {}
					for _, id in game.tileIds() do
						live[id] = true
					end
					local mounted = 0
					for _, child in find(node, "board"):GetDescendants() do
						local id = tonumber(string.match(child.Name, "^tile(%d+)$"))
						if id ~= nil then
							mounted += 1
							assert(live[id], `a retired tile {id} survived the reset`)
						end
					end
					Verify.expect(mounted):toBe(36)
					game.debugSetBoard({
						{ "a", "a", "b", "c", "d", "e" },
						{ "c", "d", "a", "e", "b", "c" },
						{ "e", "b", "c", "d", "a", "b" },
						{ "b", "c", "d", "e", "c", "a" },
						{ "d", "e", "b", "a", "e", "d" },
						{ "a", "c", "e", "b", "d", "c" },
					})
					game.swap(1, 3, 2, 3)
					for _ = 1, 2400 do
						if not game.isResolving() then
							break
						end
						engine.heartbeat.fire(0.01)
					end
					Verify.expect((game.moves())):toBe(1)
					game.swap(1, 1, 1, 2)
					engine.heartbeat.fire(0.05)
					Verify.expect((game.tickHookActive())):toBe(true)
					close()
					Verify.expect((game.tickHookActive())):toBe(false)
					for _ = 1, 60 do
						engine.heartbeat.fire(1 / 60)
					end
					Verify.expect((engine.heartbeat.count())):toBe(0)
					same(before, census(engine), "match-three teardown")
				end)
			end,
		})

		verifyHarness:case("lands every outpost exit reason in one exited state and stays usable after exits", {
			id = "native_parity_strength_lifetime::lifetime parity strength::lands every outpost exit reason in one exited state and stays usable after exits",
			run = function()
				local terminal = require("../examples/gallery/examples/outpost_terminal") :: any
				local rules = terminal.rules
				local reasons = {
					"cancel",
					"exit-control",
					"out-of-range",
					"line-of-sight",
					"character-removed",
					"adornee-lost",
					"scenario-switch",
					"teardown",
				}
				for _, reason in reasons do
					inspected(function()
						local engine = engineLib.new()
						local ctx = exampleContext(engine)
						local sent, exits = {}, 0
						local before = census(engine)
						local built, _, close = mountModule(ctx, {
							build = function(context)
								return terminal.build(context, {
									send = function(envelope)
										table.insert(sent, envelope)
									end,
									onExit = function()
										exits += 1
									end,
								})
							end,
						})
						built.steps.engage(rules.START)
						built.steps.setValue("door", 2)
						local request = built.steps.apply()
						Verify.expect(request.sent):toBe(true)
						Verify.expect(built.report().status):toBe("pending")
						Verify.expect((built.steps.exit(reason))):toBe(true)
						local state = built.report()
						Verify.expect(state.phase):toBe("exited")
						Verify.expect(state.exitReason):toBe(reason)
						Verify.expect(state.status):toBe("idle")
						Verify.expect(exits):toBe(1)
						Verify.expect((built.steps.exit("teardown"))):toBe(false)
						Verify.expect(built.report().exitReason):toBe(reason)
						Verify.expect(exits):toBe(1)
						Verify.expect(built.steps.apply().reason):toBe("exited")
						Verify.expect(#sent):toBe(1)
						Verify.expect(
							(built.steps.confirm(request.requestId, { revision = 9, allocation = request.allocation }))
						)
							:toBe(false)
						Verify.expect(built.report().revision):toBe(0)
						close()
						same(before, census(engine), `outpost exit {reason} teardown`)
					end)
				end
				local engine = engineLib.new()
				local ctx = exampleContext(engine)
				local sent = {}
				local built, _, close = mountModule(ctx, {
					build = function(context)
						return terminal.build(context, {
							send = function(envelope)
								table.insert(sent, envelope)
							end,
						})
					end,
				})
				built.steps.engage(rules.START)
				built.steps.exit("cancel")
				Verify.expect(built.steps.apply().reason):toBe("exited")
				Verify.expect(#sent):toBe(0)
				for cycle = 1, 20 do
					built.steps.engage({ door = 2, beacon = 1, workshop = 2 })
					if cycle % 2 == 0 then
						built.steps.setValue("door", 3)
					end
					Verify.expect((built.steps.exit("cancel"))):toBe(true)
				end
				built.steps.engage(rules.START)
				local state = built.report()
				Verify.expect(state.phase):toBe("engaged")
				Verify.expect(state.draft.door):toBe(rules.START.door)
				Verify.expect(state.status):toBe("idle")
				Verify.expect(built.steps.apply().sent):toBe(true)
				Verify.expect(#sent):toBe(1)
				close()
				local offline = exampleContext(engineLib.new())
				local lone, _, stop = mountModule(offline, {
					build = function(context)
						return terminal.build(context, {})
					end,
				})
				lone.steps.engage(rules.START)
				lone.steps.setValue("door", 2)
				local result = lone.steps.apply()
				Verify.expect(result.sent):toBe(false)
				Verify.expect(result.reason):toBe("no-transport")
				Verify.expect(lone.report().message):toBe(rules.refusal("session"))
				Verify.expect(lone.report().status):toBe("rejected")
				Verify.expect(lone.report().phase):toBe("engaged")
				lone.steps.setValue("door", 1)
				Verify.expect(lone.report().outcome):toBeNil()
				stop()
			end,
		})

		verifyHarness:case("disposes the playlist surface cleanly after sorting filtering reordering and selecting", {
			id = "native_parity_strength_lifetime::lifetime parity strength::disposes the playlist surface cleanly after sorting filtering reordering and selecting",
			run = function()
				inspected(function()
					local engine = engineLib.new()
					local ctx = exampleContext(engine)
					local before = census(engine)
					local built, node, close = mountModule(ctx, example("02_playlist_table"))
					local header = find(node, "Header")
					Verify.expect(header ~= nil):toBe(true)
					find(node, "Body").AbsoluteWindowSize = engine.types.Vector2.new(600, 400)
					built.ratingFor("neon"):set(5)
					built.sort:set({ column = "rating", direction = "descending" :: "descending" })
					built.filterText:set("Drift")
					Verify.expect(#built.from:peek()):toBe(1)
					built.filterText:set("")
					built.reorder({ "apex" }, 0)
					built.removeTrack("neon")
					built.columnWidths:set({ name = 290, artist = 150 })
					find(node, "RowHit").Activated.fire({
						UserInputType = engine.types.Enum.UserInputType.MouseButton1,
						KeyCode = engine.types.Enum.KeyCode:FromValue(0),
					}, 2)
					Verify.expect(built.nowPlaying:peek() ~= nil):toBe(true)
					built.restore()
					local mounted = census(engine)
					assert(mounted.live > before.live + 40, "the playlist surface was not standing")
					close()
					Verify.expect((header.isDestroyed())):toBe(true)
					Verify.expect(#ctx.target:GetChildren()):toBe(0)
					Verify.expect((engine.heartbeat.count())):toBe(0)
					same(before, census(engine), "playlist teardown")
				end)
			end,
		})

		verifyHarness:case("returns the toast lab to one baseline through twenty cycles in one runtime", {
			id = "native_parity_strength_lifetime::lifetime parity strength::returns the toast lab to one baseline through twenty cycles in one runtime",
			run = function()
				inspected(function()
					local engine = engineLib.new()
					local ctx = exampleContext(
						engine,
						{ reducedMotion = Compose.cell(false), pageVisible = Compose.cell(true) }
					)
					local scenario = require("../examples/gallery/scenarios/sponsor_toast") :: any
					local baseline = census(engine)
					for cycle = 1, 20 do
						local built
						local stop, node = ctx.runtime.mount(function()
							built = scenario.build(ctx)
							return ctx.Host.ScreenGui({ built.screen() })
						end, ctx.target)
						local first = built.show("Cycle " .. cycle, "Reading", { duration = 8, readFloor = 0.5 })
						built.show("Second", "Queued behind", { duration = 8 })
						built.show("Subject", "v1", { subject = "lap" })
						built.show("Subject", "v2", { subject = "lap" })
						engine.heartbeat.fire(0.1)
						Verify.expect(built.report().visible > 0):toBe(true)
						built.dismiss(first)
						engine.heartbeat.fire(0.05)
						find(node, "Burst").Activated.fire()
						Verify.expect(built.report().queued > 0):toBe(true)
						stop()
						Verify.expect(#ctx.target:GetChildren()):toBe(0)
						Verify.expect((engine.heartbeat.count())):toBe(0)
						same(baseline, census(engine), `toast cycle {cycle}`)
					end
					ctx.runtime:dispose()
				end)
			end,
		})
		verifyHarness:case("fires a radial callback that disposes its own menu exactly once", {
			id = "native_parity_strength_lifetime::lifetime parity strength::fires a radial callback that disposes its own menu exactly once",
			run = function()
				inspected(function()
					local w = radialWorld(false)
					local before = census(w.engine)
					local calls = 0
					local stop: () -> ()
					local node
					stop, node = w.runtime.mount(function()
						return w.Host.ScreenGui({
							w.UI.RadialMenu({
								isPresented = Compose.cell(true),
								distribution = "compass" :: "compass",
								items = {
									{
										id = "N",
										slot = "N" :: "N",
										label = "Go",
										onSelect = function()
											calls += 1
											stop()
										end,
									} :: FixtureRadialTypes.RadialItem<any>,
								},
							}),
						})
					end, w.target)
					local sector = find(node, "N")
					local press = touch(w.engine, 320, 110)
					Verify.expect(w.input.InputEnded.count() > 0):toBe(true)
					sector.InputBegan.fire(press)
					w.input.InputEnded.fire(press)
					Verify.expect(calls):toBe(1)
					Verify.expect((node.isDestroyed())):toBe(true)
					Verify.expect((sector.isDestroyed())):toBe(true)
					Verify.expect((w.input.InputEnded.count())):toBe(0)
					sector.Activated.fire(press)
					sector.InputBegan.fire(press)
					w.input.InputEnded.fire(press)
					sector.Activated.fire()
					Verify.expect(calls):toBe(1)
					w.runtime:dispose()
					same(before, census(w.engine), "radial self-disposal")
				end)
				inspected(function()
					local w = radialWorld(false)
					local shown, calls = Compose.cell(true), 0
					local stop, node = w.runtime.mount(function()
						return w.Host.ScreenGui({
							w.Host.Frame "Base" {} :: unknown,
							Compose.show(shown, function()
								return w.UI.RadialMenu({
									isPresented = Compose.cell(true),
									items = {
										{
											id = "Go",
											label = "Go",
											onSelect = function()
												calls += 1
												shown:set(false)
											end,
										} :: FixtureRadialTypes.RadialItem<any>,
									},
								})
							end),
						})
					end, w.target)
					local open = census(w.engine)
					local item = find(node, "Go")
					item.Activated.fire()
					Verify.expect(calls):toBe(1)
					Verify.expect((item.isDestroyed())):toBe(true)
					item.Activated.fire()
					Verify.expect(calls):toBe(1)
					Verify.expect((w.input.InputEnded.count())):toBe(0)
					Verify.expect(census(w.engine).live < open.live):toBe(true)
					stop()
					w.runtime:dispose()
				end)
			end,
		})

		verifyHarness:case("leaves nothing of an open radial menu swapped or dismissed mid-animation", {
			id = "native_parity_strength_lifetime::lifetime parity strength::leaves nothing of an open radial menu swapped or dismissed mid-animation",
			run = function()
				inspected(function()
					local w = radialWorld(true)
					local which, presented = Compose.cell("a"), {}
					local stop, node = w.runtime.mount(function()
						return w.Host.ScreenGui({
							Compose.keyed({
								from = function(use: Use)
									return { { id = use(which) } }
								end,
								key = function(row)
									return row.id
								end,
								render = function(current): GuiObject
									local opened = Compose.cell(false)
									presented[current:peek().id] = opened
									return w.UI.RadialMenu({
										label = "Quick",
										isPresented = opened,
										items = {
											{ id = "One", label = "One" } :: FixtureRadialTypes.RadialItem<any>,
											{ id = "Two", label = "Two" } :: FixtureRadialTypes.RadialItem<any>,
										},
									})
								end,
							}),
						})
					end, w.target)
					w.step(0.3)
					local closed = census(w.engine)
					presented.a:set(true)
					w.step(0.3)
					local panel = find(node, "RadialPanel")
					Verify.expect(panel ~= nil):toBe(true)
					Verify.expect(census(w.engine).live > closed.live):toBe(true)
					which:set("b")
					w.step(0.6)
					Verify.expect((panel.isDestroyed())):toBe(true)
					Verify.expect((find(node, "RadialPanel"))):toBeNil()
					Verify.expect((find(node, "One"))):toBeNil()
					local swapped = census(w.engine)
					Verify.expect(swapped.live):toBe(closed.live)
					Verify.expect(swapped.connections):toBe(closed.connections)
					Verify.expect(swapped.owners):toBe(closed.owners)
					Verify.expect(swapped.holding):toBe(closed.holding)
					Verify.expect((w.engine.heartbeat.count())):toBe(0)
					presented.b:set(true)
					w.step(0.3)
					Verify.expect(find(node, "RadialPanel") ~= nil):toBe(true)
					Verify.expect(find(node, "One") ~= nil):toBe(true)
					stop()
					w.runtime:dispose()
				end)
				inspected(function()
					local w = radialWorld(true)
					local before = census(w.engine)
					local opened = Compose.cell(false)
					local stop, node = w.runtime.mount(function()
						return w.Host.ScreenGui({
							w.UI.RadialMenu({
								isPresented = opened,
								center = "empty" :: "empty",
								items = {
									{
										id = "Gear",
										label = "Gear",
										navigation = "expand" :: "expand",
										children = { { id = "Tool", label = "Tool", onSelect = function() end } },
									} :: FixtureRadialTypes.RadialItem<any>,
								},
							}),
						})
					end, w.target)
					opened:set(true)
					w.step(0.04)
					find(node, "Gear").Activated.fire()
					w.step(0.04)
					local tool = find(node, "Tool")
					Verify.expect(tool ~= nil):toBe(true)
					opened:set(false)
					w.step(1 / 60)
					Verify.expect(w.engine.heartbeat.count() > 0):toBe(true)
					stop()
					stop()
					Verify.expect((tool.isDestroyed())):toBe(true)
					Verify.expect((w.engine.heartbeat.count())):toBe(0)
					w.runtime:dispose()
					same(before, census(w.engine), "radial dismissed mid-animation")
				end)
			end,
		})
		verifyHarness:case("returns counters to baseline when an open popup is dismissed or disposed", {
			id = "native_parity_strength_lifetime::lifetime parity strength::returns counters to baseline when an open popup is dismissed or disposed",
			run = function()
				inspected(function()
					local w = controlWorld()
					local before = census(w.engine)
					local shown = Compose.cell(true)
					local picked, menuOpen, pickerOpen = Compose.cell("easy"), Compose.cell(false), Compose.cell(false)
					local stop = w.runtime.mount(function()
						return w.Host.Frame({
							w.Host.Frame "Base" {} :: unknown,
							Compose.show(shown, function()
								return w.Host.Frame "Surface" {
									w.UI.Picker({
										selected = picked,
										style = "menu" :: "menu",
										isPresented = pickerOpen,
										options = {
											{ value = "easy", label = "Easy" } :: FixtureNavigationTypes.PickerOption<any>,
											{ value = "normal", label = "Normal" } :: FixtureNavigationTypes.PickerOption<any>,
											{ value = "hard", label = "Hard" } :: FixtureNavigationTypes.PickerOption<any>,
										},
									}) :: unknown,
									w.UI.Menu({
										label = "More",
										isPresented = menuOpen,
										items = {
											{
												id = "Nested",
												label = "Nested",
												children = { { id = "Run", label = "Run", onSelect = function() end } },
											} :: FixtureNavigationTypes.MenuItem<any>,
										},
									}),
								}
							end),
						})
					end, w.root)
					shown:set(false)
					local hidden = census(w.engine)
					for cycle = 1, 5 do
						shown:set(true)
						find(w.root, "Trigger").Activated.fire()
						Verify.expect((pickerOpen:peek())):toBe(true)
						find(find(w.root, "MenuPanel"), "hard").Activated.fire()
						Verify.expect((picked:peek())):toBe("hard")
						find(w.root, "Trigger").Activated.fire()
						Verify.expect(find(w.root, "MenuPanel") ~= nil):toBe(true)
						menuOpen:set(true)
						find(w.root, "Nested").Activated.fire()
						Verify.expect(find(w.root, "Run") ~= nil):toBe(true)
						shown:set(false)
						Verify.expect((find(w.root, "MenuPanel"))):toBeNil()
						Verify.expect((find(w.root, "Run"))):toBeNil()
						same(hidden, census(w.engine), `popup dismissed while open {cycle}`)
						picked:set("easy")
						pickerOpen:set(false)
						menuOpen:set(false)
					end
					shown:set(true)
					pickerOpen:set(true)
					menuOpen:set(true)
					Verify.expect(find(w.root, "MenuPanel") ~= nil):toBe(true)
					stop()
					w.runtime:dispose()
					Verify.expect(#w.root:GetChildren()):toBe(0)
					same(before, census(w.engine), "popup disposed while open")
				end)
			end,
		})

		verifyHarness:case("leaves no instance connection or owner after the HUD rotation and URL bar sequence", {
			id = "native_parity_strength_lifetime::lifetime parity strength::leaves no instance connection or owner after the HUD rotation and URL bar sequence",
			run = function()
				inspected(function()
					local hud = require("../examples/gallery/scenarios/hud") :: any
					local engine = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local viewport = Compose.cell({ width = 1079, height = 809 })
					local target = engine.new("ScreenGui")
					local ctx = {
						Facet = Facet,
						Compose = Compose,
						runtime = runtime,
						Host = (runtime.constructors :: unknown) :: RobloxHost,
						UI = Facet.controls(runtime, { types = engine.types, viewport = viewport } :: any),
						types = engine.types,
						viewport = viewport,
					}
					local before = census(engine)
					local built
					local stop, root: any = runtime.mount(function()
						built = hud.build(ctx)
						return built.screen()
					end, target)
					local body = find(root, "Zones")
					local signal = body:GetPropertyChangedSignal("AbsoluteSize")
					built.steps.openUrlBar()
					viewport:set({ width = 360, height = 691 })
					body.AbsoluteSize = engine.types.Vector2.new(360, 560)
					built.steps.closeUrlBar()
					built.steps.openOverflow()
					built.steps.closeOverflow()
					viewport:set({ width = 1079, height = 809 })
					body.AbsoluteSize = engine.types.Vector2.new(1079, 700)
					built.steps.openOverflow()
					Verify.expect(built.report().overflowOpen):toBe(true)
					built.steps.closeOverflow()
					Verify.expect(census(engine).live > before.live + 50):toBe(true)
					Verify.expect(signal.count() > 0):toBe(true)
					stop()
					runtime:dispose()
					Verify.expect((signal.count())):toBe(0)
					Verify.expect(#target:GetChildren()):toBe(0)
					Verify.expect((body.isDestroyed())):toBe(true)
					same(before, census(engine), "HUD teardown")
				end)
			end,
		})

		verifyHarness:case("releases RowActions observers through twenty engaged branch removals", {
			id = "native_parity_strength_lifetime::lifetime parity strength::releases RowActions observers through twenty engaged branch removals",
			run = function()
				inspected(function()
					local w = controlWorld({ motionLevel = "normal" })
					local before = census(w.engine)
					local shown, open, invoked = Compose.cell(false), Compose.cell(nil :: string?), 0
					local stop, node = w.runtime.mount(function()
						return w.Host.Frame({
							Compose.show(shown, function()
								return w.UI.RowActions "Row" {
									open = open,
									content = w.UI.Text({ text = "Message" }),
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
							end),
						})
					end, w.root)
					local baseline = census(w.engine)
					for cycle = 1, 20 do
						shown:set(true)
						local row = find(node, "Row")
						Verify.expect(row ~= nil):toBe(true)
						row.AbsoluteSize = w.engine.types.Vector2.new(300, 40)
						open:set("trailing")
						w.engine.heartbeat.fire(0.3)
						local action = find(row, "Delete")
						Verify.expect(action ~= nil):toBe(true)
						Verify.expect(census(w.engine).connections > baseline.connections):toBe(true)
						open:set(nil)
						shown:set(false)
						w.engine.heartbeat.fire(0.5)
						Verify.expect((row.isDestroyed())):toBe(true)
						action.Activated.fire()
						Verify.expect(invoked):toBe(0)
						Verify.expect((w.engine.heartbeat.count())):toBe(0)
						same(baseline, census(w.engine), `RowActions removal {cycle}`)
					end
					stop()
					w.runtime:dispose()
					same(before, census(w.engine), "RowActions teardown")
				end)
			end,
		})

		verifyHarness:case("cancels Table reorder on capability loss and disposes to the registry baseline", {
			id = "native_parity_strength_lifetime::lifetime parity strength::cancels Table reorder on capability loss and disposes to the registry baseline",
			run = function()
				inspected(function()
					local w = controlWorld()
					w.input.MouseEnabled = true
					w.input.KeyboardEnabled = true
					w.input.GamepadEnabled = true
					local before = census(w.engine)
					local requests = {}
					local stop, node = w.runtime.mount(function()
						return w.UI.Table({
							from = records(20),
							key = byId,
							itemSize = 20,
							overscan = 0,
							reorderable = true,
							onReorder = function(keys, slot)
								table.insert(requests, { keys = keys, slot = slot })
							end,
							columns = {
								{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
							},
						})
					end, w.root)
					local body = node:FindFirstChild("Body")
					body.AbsoluteWindowSize = w.engine.types.Vector2.new(200, 100)
					local handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
					handle.Activated.fire()
					Verify.expect(w.gui.SelectedObject.Name):toBe("Drop")
					local down = w.root:FindFirstChild("FacetReorderDown"):FindFirstChild("ReorderDown")
					down.Pressed.fire()
					down.Pressed.fire()
					Verify.expect(find(node, "Drop") ~= nil):toBe(true)
					w.input.KeyboardEnabled = false
					w.input.GamepadEnabled = false
					Verify.expect((find(node, "Drop"))):toBeNil()
					w.root:FindFirstChild("FacetReorderDrop"):FindFirstChild("ReorderDrop").Pressed.fire()
					Verify.expect(#requests):toBe(0)
					body.CanvasPosition = w.engine.types.Vector2.zero
					local pointer = {
						UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
						Position = w.engine.types.Vector3.new(10, 10, 0),
					}
					handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
					local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
					handle.InputBegan.fire(pointer)
					detector.DragStart.fire(w.engine.types.Vector2.new(10, 10))
					detector.DragContinue.fire(w.engine.types.Vector2.new(10, 60))
					Verify.expect(node:FindFirstChild("DropLine", true) ~= nil):toBe(true)
					w.input.MouseEnabled = false
					Verify.expect((node:FindFirstChild("DropLine", true))):toBeNil()
					w.input.InputEnded.fire(pointer)
					Verify.expect(#requests):toBe(0)
					Verify.expect((w.engine.heartbeat.count())):toBe(0)
					stop()
					w.runtime:dispose()
					Verify.expect((node.isDestroyed())):toBe(true)
					same(before, census(w.engine), "Table flip teardown")
				end)
			end,
		})

		verifyHarness:case("returns a list row to its closed shape after every RowActions engagement", {
			id = "native_parity_strength_lifetime::lifetime parity strength::returns a list row to its closed shape after every RowActions engagement",
			run = function()
				inspected(function()
					local w = controlWorld({ motionLevel = "normal" })
					local before = census(w.engine)
					local opens = {}
					local stop, node = w.runtime.mount(function()
						return w.UI.VirtualList({
							from = records(100),
							key = byId,
							itemSize = 40,
							overscan = 0,
							render = function(current): GuiObject
								local id = current:peek().id
								opens[id] = opens[id] or Compose.cell(nil :: string?)
								return w.UI.RowActions "Actions" {
									open = opens[id],
									content = w.UI.Text({
										text = function(use: Use)
											return use(current).label
										end,
									}),
									trailing = {
										{ id = "Archive", label = "Archive", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
										{
											id = "Delete",
											label = "Delete",
											role = "destructive" :: "destructive",
											onActivate = function() end,
										} :: FixtureCollectionTypes.RowAction,
									},
								}
							end,
						})
					end, w.root)
					node.AbsoluteWindowSize = w.engine.types.Vector2.new(300, 400)
					local row = node:FindFirstChild("2", true)
					find(row, "Actions").AbsoluteSize = w.engine.types.Vector2.new(300, 40)
					settle(w.engine, 1)
					local closed, closedShape = census(w.engine), shape(node)
					for cycle = 1, 5 do
						opens[2]:set("trailing")
						settle(w.engine, 1)
						local tray = find(row, "trailing")
						Verify.expect(tray.Visible):toBe(true)
						Verify.expect(tray.Size.X.Offset > 0):toBe(true)
						Verify.expect(find(tray, "Delete") ~= nil):toBe(true)
						opens[2]:set(nil)
						settle(w.engine, 1)
						Verify.expect(tray.Visible):toBe(false)
						Verify.expect((shape(node))):toEqual(closedShape)
						same(closed, census(w.engine), `row engagement {cycle}`)
					end
					stop()
					w.runtime:dispose()
					same(before, census(w.engine), "row engagement teardown")
				end)
			end,
		})
		verifyHarness:case(
			"returns a Table and TextInput screen to baseline after interaction and a mid-edit dispose",
			{
				id = "native_parity_strength_lifetime::lifetime parity strength::returns a Table and TextInput screen to baseline after interaction and a mid-edit dispose",
				run = function()
					inspected(function()
						local w = controlWorld()
						local before = census(w.engine)
						local value, selection, editing = Compose.cell(""), Compose.cell({}), Compose.cell(false)
						local rows = Compose.cell(records(2))
						local stop, node = w.runtime.mount(function()
							return w.Host.Frame({
								w.UI.TextInput "Filter" {
									value = value,
									onChange = function(text)
										value:set(text)
									end,
								} :: unknown,
								w.UI.Table "Rows" {
									from = rows,
									key = byId,
									columns = {
										{ id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any>,
									},
									selection = selection,
									selectionMode = "single" :: "single",
									editing = editing,
									reorderable = true,
									onReorder = function() end,
								},
							})
						end, w.root)
						find(node, "Body").AbsoluteWindowSize = w.engine.types.Vector2.new(300, 200)
						rows:set(records(3))
						find(node, "RowHit").Activated.fire({
							UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
							KeyCode = w.engine.types.Enum.KeyCode:FromValue(0),
						}, 0)
						Verify.expect(next(selection:peek()) ~= nil):toBe(true)
						editing:set(true)
						local field = find(node, "Filter")
						field:CaptureFocus()
						field.Text = "ab"
						Verify.expect((value:peek())):toBe("ab")
						Verify.expect((field:IsFocused())):toBe(true)
						local text = field:GetPropertyChangedSignal("Text")
						stop()
						w.runtime:dispose()
						Verify.expect((field.isDestroyed())):toBe(true)
						Verify.expect((text.count())):toBe(0)
						Verify.expect((field.FocusLost.count())):toBe(0)
						Verify.expect(#w.root:GetChildren()):toBe(0)
						same(before, census(w.engine), "Table and TextInput teardown")
					end)
				end,
			}
		)

		verifyHarness:case(
			"releases a dismissed surface's button keys and held repeat before another surface binds them",
			{
				id = "native_parity_strength_lifetime::lifetime parity strength::releases a dismissed surface's button keys and held repeat before another surface binds them",
				run = function()
					inspected(function()
						local w = controlWorld()
						local before = census(w.engine)
						local oldShown, newShown, oldCalls, newCalls = Compose.cell(true), Compose.cell(false), 0, 0
						local stop, node = w.runtime.mount(function()
							return w.Host.Frame({
								Compose.show(oldShown, function()
									return w.UI.Button "Old" {
										label = "Old",
										shortcut = { keyCode = "Return" },
										dialogAction = "default",
										repeatDelay = 0.4,
										onActivate = function()
											oldCalls += 1
										end,
									}
								end) :: unknown,
								Compose.show(newShown, function()
									return w.UI.Button "New" {
										label = "New",
										shortcut = { keyCode = "Return" },
										onActivate = function()
											newCalls += 1
										end,
									}
								end),
							})
						end, w.root)
						local oldButton = find(node, "Old")
						local oldAction = find(w.root, "Shortcut")
						Verify.expect(oldAction ~= nil):toBe(true)
						oldAction.Pressed.fire()
						Verify.expect(oldCalls):toBe(1)
						oldButton.InputBegan.fire({
							UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
							KeyCode = w.engine.types.Enum.KeyCode:FromValue(0),
						})
						w.engine.heartbeat.fire(0.4)
						Verify.expect(oldCalls):toBe(2)
						oldShown:set(false)
						Verify.expect((oldButton.isDestroyed())):toBe(true)
						Verify.expect((oldAction.Pressed.count())):toBe(0)
						Verify.expect((w.engine.heartbeat.count())):toBe(0)
						settle(w.engine, 1)
						oldAction.Pressed.fire()
						Verify.expect(oldCalls):toBe(2)
						newShown:set(true)
						local newAction = find(w.root, "Shortcut")
						Verify.expect(newAction ~= oldAction):toBe(true)
						newAction.Pressed.fire()
						Verify.expect(newCalls):toBe(1)
						Verify.expect(oldCalls):toBe(2)
						stop()
						w.runtime:dispose()
						Verify.expect((newAction.Pressed.count())):toBe(0)
						same(before, census(w.engine), "button key teardown")
					end)
				end,
			}
		)

		verifyHarness:case("edits TextInput without remounting and disposes mid-edit to the registry baseline", {
			id = "native_parity_strength_lifetime::lifetime parity strength::edits TextInput without remounting and disposes mid-edit to the registry baseline",
			run = function()
				inspected(function()
					local w = controlWorld()
					local before = census(w.engine)
					local value, edits, commits = Compose.cell(""), 0, 0
					local stop, field = w.runtime.mount(function()
						return w.UI.TextInput({
							value = value,
							placeholder = "Name",
							clearButton = true,
							maxLength = 10,
							onChange = function(text)
								edits += 1
								value:set(text)
							end,
							onCommit = function()
								commits += 1
							end,
						})
					end, w.root)
					field:CaptureFocus()
					local created, mounted = #w.engine.made, census(w.engine)
					local typed = ""
					for _, letter in { "a", "b", "c", "d", "e" } do
						typed ..= letter
						field.Text = typed
						Verify.expect((value:peek())):toBe(typed)
					end
					Verify.expect(edits):toBe(5)
					Verify.expect(#w.engine.made):toBe(created)
					local typing = census(w.engine)
					Verify.expect(typing.live):toBe(mounted.live)
					Verify.expect(typing.owners):toBe(mounted.owners)
					Verify.expect((field:IsFocused())):toBe(true)
					local text = field:GetPropertyChangedSignal("Text")
					stop()
					w.runtime:dispose()
					Verify.expect(commits):toBe(0)
					Verify.expect((field.isDestroyed())):toBe(true)
					Verify.expect((text.count())):toBe(0)
					Verify.expect((field.FocusLost.count())):toBe(0)
					same(before, census(w.engine), "TextInput mid-edit teardown")
				end)
			end,
		})

		verifyHarness:case("disposes owner trees once, contains a throwing cleanup, and survives repeated disposal", {
			id = "native_parity_strength_lifetime::lifetime parity strength::disposes owner trees once, contains a throwing cleanup, and survives repeated disposal",
			run = function()
				inspected(function()
					local source, seen = Compose.cell(1), 0
					local parent = Compose.createOwner()
					local base = parent.size()
					local child = parent.createChild()
					local unwatch = child.watch(function(use: Use)
						use(source)
						seen += 1
					end)
					Verify.expect((parent.size())):toBe(base + 1)
					source:set(2)
					Verify.expect(seen):toBe(2)
					unwatch()
					unwatch()
					source:set(3)
					Verify.expect(seen):toBe(2)
					child.dispose()
					Verify.expect((parent.size())):toBe(base)
					local second, runs = parent.createChild(), 0
					second.watch(function(use: Use)
						use(source)
						runs += 1
					end)
					parent.dispose()
					parent.dispose()
					Verify.expect((second.isDisposed())):toBe(true)
					source:set(4)
					Verify.expect(runs):toBe(1)
					local released = 0
					local scope = Compose.createOwner()
					Compose.withOwner(scope, function()
						Compose.cleanup(function()
							released += 1
						end)
						Compose.cleanup(function()
							error("bad cleanup")
						end)
						Compose.cleanup(function()
							released += 1
						end)
					end)
					pcall(scope.dispose)
					Verify.expect(released):toBe(2)
					Verify.expect((scope.isDisposed())):toBe(true)
					pcall(scope.dispose)
					Verify.expect(released):toBe(2)
					local count, holding = owners()
					Verify.expect(count):toBe(0)
					Verify.expect(holding):toBe(0)
				end)
				inspected(function()
					local w = controlWorld()
					local before = census(w.engine)
					local source, calls, released = Compose.cell(0), 0, 0
					local stop, node = w.runtime.mount(function()
						Compose.cleanup(function()
							released += 1
						end)
						Compose.cleanup(function()
							error("component cleanup failed")
						end)
						Compose.watch(function(use: Use)
							use(source)
							calls += 1
						end)
						local child = assert(Compose.currentOwner()).createChild()
						child.own(function()
							released += 1
						end)
						return w.Host.Frame({ w.UI.Text({ text = "Owned" }) })
					end, w.root)
					source:set(1)
					Verify.expect(calls):toBe(2)
					pcall(stop)
					pcall(stop)
					Verify.expect(released):toBe(2)
					Verify.expect((node.isDestroyed())):toBe(true)
					source:set(2)
					Verify.expect(calls):toBe(2)
					local again = Compose.cell("a")
					local stopAgain, label = w.runtime.mount(function()
						return w.UI.Text({ text = again })
					end, w.root)
					again:set("b")
					Verify.expect(label.Text):toBe("b")
					stopAgain()
					w.runtime:dispose()
					w.runtime:dispose()
					same(before, census(w.engine), "throwing cleanup teardown")
				end)
			end,
		})

		verifyHarness:case("stops mounted watches and child cleanups with the mount and tolerates repeated disposal", {
			id = "native_parity_strength_lifetime::lifetime parity strength::stops mounted watches and child cleanups with the mount and tolerates repeated disposal",
			run = function()
				inspected(function()
					local w = controlWorld()
					local before = census(w.engine)
					local source, watched, cleaned = Compose.cell(0), 0, 0
					local node
					local stop = w.runtime.mount(function()
						Compose.watch(function(use: Use)
							use(source)
							watched += 1
						end)
						local child = assert(Compose.currentOwner()).createChild()
						child.own(function()
							cleaned += 1
						end)
						node = w.Host.Frame({ w.UI.Button({ label = "Live" }) })
						return node
					end, w.root)
					source:set(1)
					Verify.expect(watched):toBe(2)
					Verify.expect((Compose.outstandingMounts())):toBe(before.mounts + 1)
					stop()
					Verify.expect((Compose.outstandingMounts())):toBe(before.mounts)
					Verify.expect(cleaned):toBe(1)
					Verify.expect((node.isDestroyed())):toBe(true)
					source:set(2)
					Verify.expect(watched):toBe(2)
					stop()
					w.runtime:dispose()
					w.runtime:dispose()
					Verify.expect(cleaned):toBe(1)
					source:set(3)
					Verify.expect(watched):toBe(2)
					same(before, census(w.engine), "runtime dispose")
				end)
			end,
		})

		verifyHarness:case("disposes a mount from inside an observer without a fault in either order", {
			id = "native_parity_strength_lifetime::lifetime parity strength::disposes a mount from inside an observer without a fault in either order",
			run = function()
				for _, observerFirst in { true, false } do
					inspected(function()
						local w = controlWorld()
						local before = census(w.engine)
						local flag = Compose.cell(false)
						local observer = Compose.createOwner()
						local stop: () -> ()
						local stopped = 0
						local function watch()
							observer.watch(function(use: Use)
								if use(flag) then
									stopped += 1
									stop()
								end
							end)
						end
						if observerFirst then
							stop = function() end
							watch()
						end
						local actual, node = w.runtime.mount(function()
							return w.Host.Frame({
								Compose.show(flag, function()
									return w.Host.TextLabel "T" { Text = "on" }
								end),
							})
						end, w.root)
						stop = actual
						if not observerFirst then
							watch()
						end
						flag:set(true)
						Verify.expect(stopped):toBe(1)
						Verify.expect((node.isDestroyed())):toBe(true)
						Verify.expect(#w.root:GetChildren()):toBe(0)
						stop()
						flag:set(false)
						flag:set(true)
						Verify.expect(#w.root:GetChildren()):toBe(0)
						observer.dispose()
						w.runtime:dispose()
						same(before, census(w.engine), `observer disposal first={observerFirst}`)
					end)
				end
			end,
		})

		verifyHarness:case("releases several pending exits at once when the runtime shuts down", {
			id = "native_parity_strength_lifetime::lifetime parity strength::releases several pending exits at once when the runtime shuts down",
			run = function()
				for _, reduced in { false, true } do
					inspected(function()
						local w = controlWorld({ motionLevel = if reduced then "none" else "normal" })
						local before = census(w.engine)
						local leaving, staying, present = Compose.cell(true), Compose.cell(true), Compose.cell(true)
						local cleaned = {}
						local function region(name: string)
							return function()
								Compose.cleanup(function()
									cleaned[name] = (cleaned[name] or 0) + 1
								end)
								return w.Host.TextLabel(name) { Text = name }
							end
						end
						local stop = w.runtime.mount(function()
							return w.Host.Frame({
								w.UI.Alert({
									isPresented = leaving,
									title = "Leaving",
									actions = { { id = "ok", label = "OK" } :: FixtureNavigationTypes.AlertAction<any> },
									transition = { seconds = 0.4 },
								}) :: unknown,
								w.UI.Alert({
									isPresented = staying,
									title = "Staying",
									actions = { { id = "ok", label = "OK" } :: FixtureNavigationTypes.AlertAction<any> },
									transition = { seconds = 0.4 },
								}),
								Compose.presence(present, region("Region"), {
									exit = function()
										if reduced then
											return { completed = Compose.cell(true) }
										end
										return { completed = w.runtime.timeline({ duration = 0.5 }).completed }
									end,
								}),
							})
						end, w.root)
						settle(w.engine, 0.6)
						local region = find(w.root, "Region")
						Verify.expect(region ~= nil):toBe(true)
						leaving:set(false)
						present:set(false)
						w.engine.heartbeat.fire(1 / 60)
						Verify.expect((region.isDestroyed())):toBe(reduced)
						Verify.expect(cleaned.Region or 0):toBe(if reduced then 1 else 0)
						stop()
						w.runtime:dispose()
						Verify.expect((region.isDestroyed())):toBe(true)
						Verify.expect(cleaned.Region):toBe(1)
						Verify.expect((w.engine.heartbeat.count())):toBe(0)
						Verify.expect(#w.root:GetChildren()):toBe(0)
						same(before, census(w.engine), `shutdown reduced={reduced}`)
						settle(w.engine, 1)
						Verify.expect(cleaned.Region):toBe(1)
					end)
				end
			end,
		})

		verifyHarness:case("sweeps the old subtree when a branch puts a different node at the same position", {
			id = "native_parity_strength_lifetime::lifetime parity strength::sweeps the old subtree when a branch puts a different node at the same position",
			run = function()
				inspected(function()
					local w = controlWorld()
					local before = census(w.engine)
					local flag, which = Compose.cell(true), Compose.cell("a")
					local function slot(name: string)
						return function()
							return w.Host.Frame "Slot" { w.Host.TextLabel(name) { Text = name } }
						end
					end
					local stop, node = w.runtime.mount(function()
						return w.Host.Frame({
							Compose.show(flag, slot("Alpha"), slot("Beta")) :: unknown,
							w.Host.Frame "Keyed" {
								Compose.keyed({
									from = function(use: Use)
										return { { id = use(which) } }
									end,
									key = byId,
									render = function(current): GuiObject
										return w.Host.Frame "Slot" {
											w.Host.TextLabel(current:peek().id) { Text = "row" },
										}
									end,
								}),
							},
						})
					end, w.root)
					local mounted = census(w.engine)
					for cycle = 1, 20 do
						local alphaSlot, alpha = find(node, "Slot"), find(node, "Alpha")
						local keyedSlot, a = find(find(node, "Keyed"), "Slot"), find(node, "a")
						Verify.expect(alpha ~= nil and a ~= nil):toBe(true)
						flag:set(false)
						which:set("b")
						Verify.expect((alphaSlot.isDestroyed())):toBe(true)
						Verify.expect((alpha.isDestroyed())):toBe(true)
						Verify.expect((keyedSlot.isDestroyed())):toBe(true)
						Verify.expect((a.isDestroyed())):toBe(true)
						Verify.expect((find(node, "Alpha"))):toBeNil()
						Verify.expect((find(node, "a"))):toBeNil()
						Verify.expect(find(node, "Beta") ~= nil):toBe(true)
						Verify.expect(find(node, "b") ~= nil):toBe(true)
						Verify.expect(#find(node, "Keyed"):GetChildren()):toBe(1)
						flag:set(true)
						which:set("a")
						Verify.expect((find(node, "Beta"))):toBeNil()
						Verify.expect((find(node, "b"))):toBeNil()
						same(mounted, census(w.engine), `replaced occupant {cycle}`)
					end
					stop()
					w.runtime:dispose()
					same(before, census(w.engine), "replaced occupant teardown")
				end)
			end,
		})
		verifyHarness:case("releases evicted image buttons and their hover observers with the branch", {
			id = "native_parity_strength_lifetime::lifetime parity strength::releases evicted image buttons and their hover observers with the branch",
			run = function()
				inspected(function()
					local w = controlWorld()
					local before = census(w.engine)
					local shown, calls = Compose.cell(false), 0
					local stop, node = w.runtime.mount(function()
						return w.Host.Frame({
							Compose.show(shown, function()
								return w.UI.Button "Card" {
									label = "Driver",
									image = "rbxassetid://7",
									imageFraming = "crop",
									onActivate = function()
										calls += 1
									end,
								}
							end),
						})
					end, w.root)
					local hidden = census(w.engine)
					for cycle = 1, 10 do
						shown:set(true)
						local card = find(node, "Card")
						card.MouseEnter.fire()
						card.Activated.fire()
						Verify.expect(calls):toBe(cycle)
						Verify.expect(card:connectionCount() > 0):toBe(true)
						shown:set(false)
						settle(w.engine, 1)
						Verify.expect((card.isDestroyed())):toBe(true)
						Verify.expect((card:connectionCount())):toBe(0)
						card.MouseEnter.fire()
						card.MouseLeave.fire()
						card.Activated.fire()
						Verify.expect(calls):toBe(cycle)
						same(hidden, census(w.engine), `image button eviction {cycle}`)
					end
					stop()
					w.runtime:dispose()
					same(before, census(w.engine), "image button teardown")
				end)
			end,
		})

		verifyHarness:case("releases every NavigationStack page when disposal lands mid-transition", {
			id = "native_parity_strength_lifetime::lifetime parity strength::releases every NavigationStack page when disposal lands mid-transition",
			run = function()
				for _, reduced in { false, true } do
					inspected(function()
						local w = controlWorld({ motionLevel = if reduced then "none" else "normal" })
						local before = census(w.engine)
						local path, built, disposed = Compose.cell({}), 0, 0
						local stop, node = w.runtime.mount(function()
							local function content(entry)
								built += 1
								Compose.cleanup(function()
									disposed += 1
								end)
								return w.UI.Button({ label = if entry then "Detail" else "Root" })
							end
							return w.UI.NavigationStack({
								path = path,
								transition = { seconds = 0.3 },
								root = { title = "Root", content = content },
								destinations = { detail = { title = "Detail", content = content } },
							})
						end, w.root)
						path:set({ { id = "detail", value = 1 } })
						w.engine.heartbeat.fire(0.05)
						path:set({ { id = "detail", value = 1 }, { id = "detail", value = 2 } })
						w.engine.heartbeat.fire(0.05)
						Verify.expect(built >= 3):toBe(true)
						Verify.expect(built - disposed >= 2):toBe(true)
						if not reduced then
							Verify.expect(w.engine.heartbeat.count() > 0):toBe(true)
						end
						stop()
						w.runtime:dispose()
						Verify.expect(disposed):toBe(built)
						Verify.expect((node.isDestroyed())):toBe(true)
						Verify.expect((w.engine.heartbeat.count())):toBe(0)
						same(before, census(w.engine), `stack mid-flight reduced={reduced}`)
						settle(w.engine, 1)
						Verify.expect(disposed):toBe(built)
					end)
				end
			end,
		})

		verifyHarness:case(
			"remounts one NavigationStack without accumulating observers and ignores path writes after disposal",
			{
				id = "native_parity_strength_lifetime::lifetime parity strength::remounts one NavigationStack without accumulating observers and ignores path writes after disposal",
				run = function()
					inspected(function()
						local w = controlWorld()
						local before = census(w.engine)
						local path, built, disposed = Compose.cell({}), 0, 0
						local function mount()
							return w.runtime.mount(function()
								local function content(entry)
									built += 1
									Compose.cleanup(function()
										disposed += 1
									end)
									return w.UI.Button({ label = if entry then "Detail" else "Root" })
								end
								return w.UI.NavigationStack({
									path = path,
									root = { title = "Root", content = content },
									destinations = { detail = { title = "Detail", content = content } },
								})
							end, w.root)
						end
						local stop = mount()
						local mounted = census(w.engine)
						for cycle = 1, 3 do
							stop()
							same(before, census(w.engine), `stack unmount {cycle}`)
							stop = mount()
							same(mounted, census(w.engine), `stack remount {cycle}`)
						end
						stop()
						local after, builds = census(w.engine), built
						path:set({ { id = "detail", value = 1 } })
						path:set({})
						path:set({ { id = "detail", value = 2 } })
						Verify.expect(built):toBe(builds)
						Verify.expect(disposed):toBe(built)
						Verify.expect(#w.root:GetChildren()):toBe(0)
						same(after, census(w.engine), "stack path writes after disposal")
						w.runtime:dispose()
						same(before, census(w.engine), "stack teardown")
					end)
				end,
			}
		)

		verifyHarness:case(
			"disposes icon-only vertical indicated segmented pickers to the registry baseline after switching",
			{
				id = "native_parity_strength_lifetime::lifetime parity strength::disposes icon-only vertical indicated segmented pickers to the registry baseline after switching",
				run = function()
					for _, indicator in { "pill", "underline" } :: { "pill" | "underline" } do
						inspected(function()
							local w = controlWorld({ motionLevel = "normal" })
							local before = census(w.engine)
							local selected, changes = Compose.cell("grid"), 0
							local stop, node = w.runtime.mount(function()
								return w.UI.Picker({
									selected = selected,
									style = "segmented" :: "segmented",
									axis = "y" :: "y",
									iconOnly = true,
									indicator = indicator :: "pill" | "underline",
									options = {
										{ value = "grid", label = "Grid", icon = "edit" } :: FixtureNavigationTypes.PickerOption<any>,
										{ value = "list", label = "Listing", icon = "edit" } :: FixtureNavigationTypes.PickerOption<any>,
										{ value = "cards", label = "Cards", icon = "edit" } :: FixtureNavigationTypes.PickerOption<any>,
									},
									onChange = function()
										changes += 1
									end,
								})
							end, w.root)
							find(node, "list").Activated.fire()
							settle(w.engine, 0.5)
							find(node, "grid").Activated.fire()
							settle(w.engine, 0.5)
							local warm = census(w.engine)
							for cycle = 1, 5 do
								find(node, "list").Activated.fire()
								settle(w.engine, 0.5)
								Verify.expect((selected:peek())):toBe("list")
								find(node, "cards").Activated.fire()
								w.engine.heartbeat.fire(1 / 60)
								selected:set("grid")
								settle(w.engine, 0.5)
								same(warm, census(w.engine), `{indicator} indicator round trip {cycle}`)
							end
							Verify.expect(changes):toBe(12)
							Verify.expect((w.engine.heartbeat.count())):toBe(0)
							stop()
							w.runtime:dispose()
							Verify.expect((node.isDestroyed())):toBe(true)
							same(before, census(w.engine), `{indicator} picker teardown`)
						end)
					end
				end,
			}
		)

		verifyHarness:case("returns a menu picker to baseline after open select reopen and cancel", {
			id = "native_parity_strength_lifetime::lifetime parity strength::returns a menu picker to baseline after open select reopen and cancel",
			run = function()
				inspected(function()
					local w = controlWorld()
					local before = census(w.engine)
					local selected, opened, changes = Compose.cell("normal"), Compose.cell(false), 0
					local stop = w.runtime.mount(function()
						return w.Host.Frame({
							w.UI.Picker "Difficulty" {
								selected = selected,
								style = "menu" :: "menu",
								isPresented = opened,
								options = {
									{ value = "easy", label = "Easy" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "normal", label = "Normal" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "hard", label = "Hard" } :: FixtureNavigationTypes.PickerOption<any>,
								},
								onChange = function()
									changes += 1
								end,
							},
						})
					end, w.root)
					local closed = census(w.engine)
					for cycle = 1, 3 do
						find(w.root, "Trigger").Activated.fire()
						Verify.expect((opened:peek())):toBe(true)
						find(find(w.root, "MenuPanel"), "hard").Activated.fire()
						Verify.expect((selected:peek())):toBe("hard")
						Verify.expect((opened:peek())):toBe(false)
						find(w.root, "Trigger").Activated.fire()
						local catcher = find(w.root, "DismissOutside")
						Verify.expect(catcher ~= nil):toBe(true)
						catcher.Activated.fire({ Position = w.engine.types.Vector2.new(0, 0) })
						Verify.expect((opened:peek())):toBe(false)
						Verify.expect((find(w.root, "MenuPanel"))):toBeNil()
						Verify.expect((selected:peek())):toBe("hard")
						selected:set("normal")
						same(closed, census(w.engine), `menu picker cycle {cycle}`)
					end
					Verify.expect(changes):toBe(3)
					stop()
					w.runtime:dispose()
					same(before, census(w.engine), "menu picker teardown")
				end)
			end,
		})

		verifyHarness:case("reopens a bound Sheet with fresh content and disposes it to baseline", {
			id = "native_parity_strength_lifetime::lifetime parity strength::reopens a bound Sheet with fresh content and disposes it to baseline",
			run = function()
				inspected(function()
					local w = controlWorld({ motionLevel = "normal" })
					local before = census(w.engine)
					local shown, detent, live, visits = Compose.cell(false), Compose.cell("medium"), 0, 0
					local stop = w.runtime.mount(function()
						return w.Host.Frame({
							w.UI.Sheet({
								title = "Details",
								isPresented = shown,
								detent = detent,
								content = function(): Instance
									live += 1
									visits += 1
									Compose.cleanup(function()
										live -= 1
									end)
									return w.UI.Button "Body" { label = "Briefing" }
								end,
							}),
						})
					end, w.root)
					local closed = census(w.engine)
					shown:set(true)
					settle(w.engine, 1.5)
					Verify.expect(live):toBe(1)
					local body = find(w.root, "Body")
					find(w.root, "ModalBack").Pressed.fire()
					Verify.expect((shown:peek())):toBe(false)
					settle(w.engine, 1.5)
					Verify.expect(live):toBe(0)
					Verify.expect((body.isDestroyed())):toBe(true)
					same(closed, census(w.engine), "sheet closed")
					shown:set(true)
					settle(w.engine, 1.5)
					Verify.expect(live):toBe(1)
					Verify.expect(visits):toBe(2)
					Verify.expect(find(w.root, "Body") ~= body):toBe(true)
					detent:set("large")
					settle(w.engine, 1.5)
					stop()
					w.runtime:dispose()
					Verify.expect(live):toBe(0)
					Verify.expect((w.engine.heartbeat.count())):toBe(0)
					same(before, census(w.engine), "sheet teardown")
				end)
			end,
		})

		verifyHarness:case("keeps model state outside a top-retention TabView across page disposal", {
			id = "native_parity_strength_lifetime::lifetime parity strength::keeps model state outside a top-retention TabView across page disposal",
			run = function()
				inspected(function()
					local w = controlWorld()
					local before = census(w.engine)
					local selection, draft = Compose.cell("home"), Compose.cell("half typed")
					local entries, released, disposed = 0, 0, 0
					local stop, node = w.runtime.mount(function()
						return w.UI.TabView({
							selection = selection,
							retention = "top",
							transition = false,
							tabs = {
								{
									id = "home",
									label = "Home",
									content = function(): Instance
										entries += 1
										for _ = 1, 5 do
											local memo = Compose.formula(function(use: Use)
												return use(draft) .. "!"
											end)
											Compose.cleanup(function()
												memo:dispose()
												released += 1
											end)
										end
										Compose.cleanup(function()
											disposed += 1
										end)
										return w.Host.TextLabel "HomeBody" { Text = draft }
									end,
								} :: FixtureNavigationTypes.Tab,
								{
									id = "feed",
									label = "Feed",
									content = function(): Instance
										return w.Host.TextLabel "FeedBody" { Text = "feed" }
									end,
								} :: FixtureNavigationTypes.Tab,
							},
						})
					end, w.root)
					local body = find(node, "HomeBody")
					Verify.expect(body.Text):toBe("half typed")
					selection:set("feed")
					Verify.expect(disposed):toBe(1)
					Verify.expect(released):toBe(5)
					Verify.expect((body.isDestroyed())):toBe(true)
					draft:set("typed while away")
					selection:set("home")
					Verify.expect(entries):toBe(2)
					Verify.expect(released):toBe(5)
					Verify.expect(find(node, "HomeBody").Text):toBe("typed while away")
					stop()
					Verify.expect(disposed):toBe(2)
					Verify.expect(released):toBe(10)
					Verify.expect((draft:peek())):toBe("typed while away")
					w.runtime:dispose()
					same(before, census(w.engine), "top retention teardown")
				end)
			end,
		})

		verifyHarness:case("keeps a badged sidebar TabView registry-neutral through twenty switches and disposal", {
			id = "native_parity_strength_lifetime::lifetime parity strength::keeps a badged sidebar TabView registry-neutral through twenty switches and disposal",
			run = function()
				inspected(function()
					local w = controlWorld()
					local before = census(w.engine)
					local selection, retired, built = Compose.cell("a"), 0, 0
					local function accessory()
						built += 1
						Compose.cleanup(function()
							retired += 1
						end)
						return w.Host.Frame({})
					end
					local function page(name: string)
						return function()
							return w.Host.TextLabel(name .. "Body") { Text = name }
						end
					end
					local stop, node = w.runtime.mount(function()
						return w.UI.TabView({
							selection = selection,
							style = "sidebarAdaptable" :: "sidebarAdaptable",
							placement = "sidebar" :: "sidebar",
							transition = false,
							sections = { { id = "main", label = "Main", tabs = { "a", "b", "c" } } },
							accessories = { head = accessory, foot = accessory },
							tabs = {
								{ id = "a", label = "A", badge = "2", content = page("a") } :: FixtureNavigationTypes.Tab,
								{ id = "b", label = "B", content = page("b") } :: FixtureNavigationTypes.Tab,
								{ id = "c", label = "C", content = page("c") } :: FixtureNavigationTypes.Tab,
							},
						})
					end, w.root)
					find(node, "TabView").AbsoluteSize = w.engine.types.Vector2.new(1200, 800)
					for _, id in { "b", "c", "a" } do
						selection:set(id)
					end
					local warm = census(w.engine)
					Verify.expect(built > 0):toBe(true)
					for cycle = 1, 20 do
						selection:set(if cycle % 2 == 0 then "b" else "c")
						selection:set("a")
						same(warm, census(w.engine), `tab switch {cycle}`)
					end
					stop()
					w.runtime:dispose()
					Verify.expect(retired):toBe(built)
					same(before, census(w.engine), "tab view teardown")
				end)
			end,
		})

		verifyHarness:case("disposes a tab accessory at the moment it is re-homed", {
			id = "native_parity_strength_lifetime::lifetime parity strength::disposes a tab accessory at the moment it is re-homed",
			run = function()
				inspected(function()
					local w = controlWorld()
					local before = census(w.engine)
					local retired, built = 0, 0
					local stop, node = w.runtime.mount(function()
						return w.UI.TabView({
							selection = Compose.cell("one"),
							style = "sidebarAdaptable" :: "sidebarAdaptable",
							tabs = {
								{
									id = "one",
									label = "One",
									content = function(): Instance
										return w.Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
							},
							accessories = {
								head = function()
									built += 1
									Compose.cleanup(function()
										retired += 1
									end)
									return w.Host.TextLabel "Wordmark" { Text = "glade" }
								end,
							},
						})
					end, w.root)
					local root = find(node, "TabView")
					root.AbsoluteSize = w.engine.types.Vector2.new(1200, 800)
					local wordmark = find(node, "Wordmark")
					Verify.expect(wordmark ~= nil):toBe(true)
					Verify.expect(retired):toBe(0)
					root.AbsoluteSize = w.engine.types.Vector2.new(390, 700)
					Verify.expect(retired):toBe(1)
					Verify.expect((wordmark.isDestroyed())):toBe(true)
					root.AbsoluteSize = w.engine.types.Vector2.new(1200, 800)
					Verify.expect(built):toBe(2)
					Verify.expect(find(node, "Wordmark") ~= wordmark):toBe(true)
					stop()
					w.runtime:dispose()
					Verify.expect(retired):toBe(built)
					same(before, census(w.engine), "accessory teardown")
				end)
			end,
		})
		verifyHarness:case("keeps decorations through palette-only swaps and destroys every one it created", {
			id = "native_parity_strength_lifetime::lifetime parity strength::keeps decorations through palette-only swaps and destroys every one it created",
			run = function()
				inspected(function()
					local theme = Compose.cell(skinnedPackage())
					local w = controlWorld({ theme = theme })
					local before = census(w.engine)
					local stop = w.runtime.mount(function()
						return w.Host.Frame({
							w.UI.Button "First" { label = "One" } :: unknown,
							w.UI.Button "Second" { label = "Two" },
						})
					end, w.root)
					local initial = images(w.root)
					Verify.expect(#initial >= 8):toBe(true)
					local created = #w.engine.made
					for step = 1, 50 do
						theme:set(skinnedPackage({ r = step / 50, g = 0.2, b = 0.3 }))
						Verify.expect(#w.engine.made):toBe(created)
						local current = images(w.root)
						Verify.expect(#current):toBe(#initial)
						for _, image in initial do
							Verify.expect((image.isDestroyed())):toBe(false)
							Verify.expect(table.find(current, image) ~= nil):toBe(true)
						end
					end
					theme:set(Facet.themes.neutralPackage())
					for _, image in initial do
						Verify.expect(image.Visible):toBe(false)
					end
					theme:set(skinnedPackage())
					Verify.expect(#w.engine.made):toBe(created)
					for _, image in initial do
						Verify.expect(image.Visible):toBe(true)
					end
					stop()
					w.runtime:dispose()
					local made = 0
					for _, instance in w.engine.made do
						if instance.ClassName == "ImageLabel" then
							made += 1
							Verify.expect((instance.isDestroyed())):toBe(true)
						end
					end
					Verify.expect(made):toBe(#initial)
					same(before, census(w.engine), "decoration teardown")
				end)
			end,
		})

		verifyHarness:case("drops the skin ladder lifted caption and state observers with the decorated node", {
			id = "native_parity_strength_lifetime::lifetime parity strength::drops the skin ladder lifted caption and state observers with the decorated node",
			run = function()
				inspected(function()
					local theme = Compose.cell(skinnedPackage())
					local w = controlWorld({ theme = theme })
					local shown = Compose.cell(false)
					local stop = w.runtime.mount(function()
						return w.Host.Frame({
							Compose.show(shown, function()
								return w.UI.Button "Plaque" { label = "Play" }
							end),
						})
					end, w.root)
					local hidden = census(w.engine)
					for cycle = 1, 3 do
						shown:set(true)
						local button = find(w.root, "Plaque")
						local caption = find(button, "PlaqueCaption")
						Verify.expect(caption ~= nil):toBe(true)
						Verify.expect(caption.Text):toBe("Play")
						Verify.expect((button:HasTag("facet-skin-caption"))):toBe(true)
						local state = button:GetPropertyChangedSignal("GuiState")
						local text = button:GetPropertyChangedSignal("Text")
						Verify.expect(state.count() > 0):toBe(true)
						button.GuiState = w.engine.types.Enum.GuiState.Press
						local ladder = images(button)
						Verify.expect(#ladder >= 6):toBe(true)
						theme:set(Facet.themes.neutralPackage())
						Verify.expect((button:HasTag("facet-skin-caption"))):toBe(false)
						Verify.expect(caption.Parent.Visible):toBe(false)
						theme:set(skinnedPackage())
						Verify.expect((find(button, "PlaqueCaption"))):toBe(caption)
						Verify.expect(caption.Parent.Visible):toBe(true)
						shown:set(false)
						Verify.expect((button.isDestroyed())):toBe(true)
						Verify.expect((caption.isDestroyed())):toBe(true)
						for _, image in ladder do
							Verify.expect((image.isDestroyed())):toBe(true)
						end
						Verify.expect((state.count())):toBe(0)
						Verify.expect((text.count())):toBe(0)
						same(hidden, census(w.engine), `skin teardown {cycle}`)
					end
					stop()
					w.runtime:dispose()
				end)
			end,
		})

		verifyHarness:case("sizes bar skin art from unscaled pixels under a UIScale and tears the bar down", {
			id = "native_parity_strength_lifetime::lifetime parity strength::sizes bar skin art from unscaled pixels under a UIScale and tears the bar down",
			run = function()
				inspected(function()
					local package = Facet.themes.neutralPackage() :: any
					package.assets = {
						fill = { content = "rbxassetid://1" },
						start = { content = "rbxassetid://2" },
						finish = { content = "rbxassetid://3" },
					}
					package.chrome.barFill = { kind = "nineSlice" :: "nineSlice", asset = "fill" }
					package.chrome.barCap = {
						kind = "nineSlice" :: "nineSlice",
						startAsset = "start",
						endAsset = "finish",
						size = { w = 6, h = 6 },
					}
					local w = controlWorld({ theme = package })
					local before = census(w.engine)
					local value = Compose.cell(0.25)
					local stop, root = w.runtime.mount(function()
						return w.UI.ProgressView({ value = value })
					end, w.root)
					local fill = root:FindFirstChild("Fill1", true)
					local boundary = fill:FindFirstChild("SkinBoundary")
					local bounds = fill:FindFirstChild("SkinBounds", true)
					for _, case in
						{ { factor = 2, width = 25 }, { factor = 0.5, width = 25 }, { factor = 2, width = 50 } }
					do
						if case.width == 50 then
							value:set(0.5)
						end
						boundary.AbsoluteSize = w.engine.types.Vector2.new(case.factor, case.factor)
						fill.AbsoluteSize = w.engine.types.Vector2.new(case.width * case.factor, 6 * case.factor)
						Verify.expect(bounds.Size.X.Offset):toBe(case.width)
						Verify.expect(bounds.Size.Y.Offset):toBe(6)
					end
					local sized = fill:GetPropertyChangedSignal("AbsoluteSize")
					local scaled = boundary:GetPropertyChangedSignal("AbsoluteSize")
					Verify.expect(sized.count() > 0 and scaled.count() > 0):toBe(true)
					local art = images(root)
					Verify.expect(#art >= 3):toBe(true)
					stop()
					w.runtime:dispose()
					Verify.expect((sized.count())):toBe(0)
					Verify.expect((scaled.count())):toBe(0)
					Verify.expect((fill.ChildAdded.count())):toBe(0)
					for _, image in art do
						Verify.expect((image.isDestroyed())):toBe(true)
					end
					same(before, census(w.engine), "bar skin teardown")
				end)
			end,
		})

		verifyHarness:case("rewires reused row containers to the current item without stale connections", {
			id = "native_parity_strength_lifetime::lifetime parity strength::rewires reused row containers to the current item without stale connections",
			run = function()
				inspected(function()
					local w = controlWorld()
					local before = census(w.engine)
					local activated = {}
					local stop, node = w.runtime.mount(function()
						return w.UI.VirtualList({
							from = records(100),
							key = byId,
							itemSize = 20,
							overscan = 0,
							render = function(current): GuiObject
								return w.UI.Button "Action" {
									label = function(use: Use)
										return use(current).label
									end,
									onActivate = function()
										table.insert(activated, current:peek().id)
									end,
								}
							end,
						})
					end, w.root)
					node.AbsoluteWindowSize = w.engine.types.Vector2.new(200, 100)
					local items = node:FindFirstChild("Items")
					local containers, perContainer = {}, nil
					for _, row in items:GetChildren() do
						containers[row] = true
						local count = 0
						for _, descendant in row:GetDescendants() do
							count += descendant:connectionCount()
						end
						perContainer = perContainer or count
						Verify.expect(count):toBe(perContainer)
					end
					local mounted = census(w.engine)
					local reused = false
					for cycle, offset in { 400, 800, 1200, 0, 1600, 400, 0 } do
						node.CanvasPosition = w.engine.types.Vector2.new(0, offset)
						for _, row in items:GetChildren() do
							reused = reused or containers[row] == true
							local count = 0
							for _, descendant in row:GetDescendants() do
								count += descendant:connectionCount()
							end
							Verify.expect(count):toBe(perContainer)
							local button = row:FindFirstChild("Action", true)
							if row.Visible ~= false and button then
								table.clear(activated)
								button.Activated.fire()
								Verify.expect(#activated):toBe(1)
								Verify.expect((tostring(activated[1]))):toBe(button.Text)
								Verify.expect(row.Name):toBe(button.Text)
							end
						end
						same(mounted, census(w.engine), `row reuse {cycle}`)
					end
					Verify.expect(reused):toBe(true)
					stop()
					w.runtime:dispose()
					same(before, census(w.engine), "row reuse teardown")
				end)
			end,
		})

		verifyHarness:case("returns the performance lab to its floor through repeated mount ramp laps", {
			id = "native_parity_strength_lifetime::lifetime parity strength::returns the performance lab to its floor through repeated mount ramp laps",
			run = function()
				inspected(function()
					local lab = require("../examples/performance/lab/perf_lab") :: any
					local dataset = require("../examples/performance/lab/dataset") :: any
					local modules = {
						sensory = require("../examples/performance/lab/sensory"),
						dataset = setmetatable({ RAMP_STEPS = { 40, 80, 120 } }, { __index = dataset }),
						rows = require("../examples/performance/lab/rows"),
						capture = require("../examples/performance/lab/capture"),
						workloads = require("../examples/performance/lab/workloads"),
					}
					local engine = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local target = engine.new("Folder")
					local probe
					local world = {
						Facet = Facet,
						Compose = Compose,
						runtime = runtime,
						Host = (runtime.constructors :: unknown) :: RobloxHost,
						UI = Facet.controls(runtime, { types = engine.types } :: any),
						engine = engine,
						target = target,
						types = engine.types,
						viewport = { w = 800, h = 600 },
						heartbeat = engine.heartbeat,
						captureFacts = function()
							return {
								evidenceClass = "lune",
								capturedAtIso = "2026-09-24T00:00:00Z",
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
						end,
						probe = function(value)
							probe = value
						end,
					}
					local before = census(engine)
					local stop = runtime.mount(function()
						return world.Host.ScreenGui({ lab.build(world, modules) })
					end, target)
					local function lap()
						probe.ramp()
						for rung = 1, #modules.dataset.RAMP_STEPS do
							engine.heartbeat.fire(1 / 60)
							Verify.expect(probe.state().rows):toBe(modules.dataset.RAMP_STEPS[rung])
						end
						Verify.expect(probe.state().queued):toBe(0)
						Verify.expect(probe.state().playing):toBe(false)
					end
					lap()
					lap()
					local floor = census(engine)
					local captures = probe.state().captures
					for index = 1, 3 do
						lap()
						Verify.expect(probe.state().captures):toBe(captures + index * #modules.dataset.RAMP_STEPS)
						same(floor, census(engine), `ramp lap {index}`)
					end
					stop()
					runtime:dispose()
					Verify.expect(#target:GetChildren()):toBe(0)
					Verify.expect((engine.heartbeat.count())):toBe(0)
					same(before, census(engine), "lab teardown")
				end)
			end,
		})
	end)
end
