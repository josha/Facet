--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local gallery = require("../examples/gallery/client/screen")
local Compose = Facet.Compose

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
	local ok, failure = pcall(body)
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
			reducedMotion = ctx.reducedMotion,
		} :: any
	)
	return ctx
end

local function exampleContext(engine: any, extra: { [string]: any }?): any
	local runtime = Facet.Roblox.createRuntime(engine)
	local viewport = Compose.cell({ width = 1280, height = 720 })
	local target = engine.new("Folder")
	local guiService = engine.new("GuiService")
	local ctx: { [string]: any } = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
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
	local runtime = Facet.Roblox.createRuntime(engine)
	local UI = Facet.controls(
		runtime,
		{
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			reducedMotion = not animated,
		} :: any
	)
	return {
		engine = engine,
		gui = gui,
		input = input,
		runtime = runtime,
		UI = UI,
		Host = runtime.constructors,
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
	local runtime = Facet.Roblox.createRuntime(engine)
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
		reducedMotion = true,
	}
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	return {
		engine = engine,
		runtime = runtime,
		UI = UI,
		Host = runtime.constructors,
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
		kind = "layered",
		layers = {
			{ kind = "fill", asset = "rest" },
			{ kind = "corners", asset = "corner", topLeft = "corner", topRight = "corner", size = 12 },
			{
				kind = "plaque",
				asset = "plate",
				edge = "top",
				overhang = 6,
				size = { w = 80, h = 24 },
				text = true,
				textInsets = { left = 4, right = 4 },
			},
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

t.describe("lifetime parity strength", function()
	t.it("returns every game to its instance connection and owner baseline after play", function()
		local plays: { [string]: (any, any) -> () } = {
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
				t.expect(#ctx.target:GetChildren()).toBe(0)
				t.expect(engine.heartbeat.count()).toBe(0)
				same(before, census(engine), `{name} teardown`)
			end)
		end
	end)
	t.it("resets the match-three machine mid-cascade without a retiring tile or frame hook", function()
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
			t.expect(game.phase()).toBe("remove")
			engine.heartbeat.fire(0.04)
			t.expect(retiring.isDestroyed()).toBe(false)
			t.expect(retiring.GroupTransparency > 0 and retiring.GroupTransparency < 1).toBe(true)
			t.expect(game.tickHookActive()).toBe(true)
			t.expect(engine.heartbeat.count() > 0).toBe(true)
			find(node, "Reset").Activated.fire()
			t.expect(game.phase()).toBe("idle")
			t.expect(#game.phaseLog()).toBe(0)
			t.expect(game.isResolving()).toBe(false)
			t.expect(game.tickHookActive()).toBe(false)
			t.expect(game.score()).toBe(0)
			t.expect(game.moves()).toBe(0)
			for _ = 1, 180 do
				engine.heartbeat.fire(1 / 60)
			end
			t.expect(engine.heartbeat.count()).toBe(0)
			t.expect(retiring.isDestroyed()).toBe(true)
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
			t.expect(mounted).toBe(36)
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
			t.expect(game.moves()).toBe(1)
			game.swap(1, 1, 1, 2)
			engine.heartbeat.fire(0.05)
			t.expect(game.tickHookActive()).toBe(true)
			close()
			t.expect(game.tickHookActive()).toBe(false)
			for _ = 1, 60 do
				engine.heartbeat.fire(1 / 60)
			end
			t.expect(engine.heartbeat.count()).toBe(0)
			same(before, census(engine), "match-three teardown")
		end)
	end)

	t.it("lands every outpost exit reason in one exited state and stays usable after exits", function()
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
				t.expect(request.sent).toBe(true)
				t.expect(built.report().status).toBe("pending")
				t.expect(built.steps.exit(reason)).toBe(true)
				local state = built.report()
				t.expect(state.phase).toBe("exited")
				t.expect(state.exitReason).toBe(reason)
				t.expect(state.status).toBe("idle")
				t.expect(exits).toBe(1)
				t.expect(built.steps.exit("teardown")).toBe(false)
				t.expect(built.report().exitReason).toBe(reason)
				t.expect(exits).toBe(1)
				t.expect(built.steps.apply().reason).toBe("exited")
				t.expect(#sent).toBe(1)
				t.expect(built.steps.confirm(request.requestId, { revision = 9, allocation = request.allocation }))
					.toBe(false)
				t.expect(built.report().revision).toBe(0)
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
		t.expect(built.steps.apply().reason).toBe("exited")
		t.expect(#sent).toBe(0)
		for cycle = 1, 20 do
			built.steps.engage({ door = 2, beacon = 1, workshop = 2 })
			if cycle % 2 == 0 then
				built.steps.setValue("door", 3)
			end
			t.expect(built.steps.exit("cancel")).toBe(true)
		end
		built.steps.engage(rules.START)
		local state = built.report()
		t.expect(state.phase).toBe("engaged")
		t.expect(state.draft.door).toBe(rules.START.door)
		t.expect(state.status).toBe("idle")
		t.expect(built.steps.apply().sent).toBe(true)
		t.expect(#sent).toBe(1)
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
		t.expect(result.sent).toBe(false)
		t.expect(result.reason).toBe("no-transport")
		t.expect(lone.report().message).toBe(rules.refusal("session"))
		t.expect(lone.report().status).toBe("rejected")
		t.expect(lone.report().phase).toBe("engaged")
		lone.steps.setValue("door", 1)
		t.expect(lone.report().outcome).toBeNil()
		stop()
	end)

	t.it("disposes the playlist surface cleanly after sorting filtering reordering and selecting", function()
		inspected(function()
			local engine = engineLib.new()
			local ctx = exampleContext(engine)
			local before = census(engine)
			local built, node, close = mountModule(ctx, example("02_playlist_table"))
			local header = find(node, "Header")
			t.expect(header ~= nil).toBe(true)
			find(node, "Body").AbsoluteWindowSize = engine.types.Vector2.new(600, 400)
			built.ratingFor("neon"):set(5)
			built.sort:set({ column = "rating", direction = "descending" })
			built.filterText:set("Drift")
			t.expect(#built.from:peek()).toBe(1)
			built.filterText:set("")
			built.reorder({ "apex" }, 0)
			built.removeTrack("neon")
			built.columnWidths:set({ name = 290, artist = 150 })
			find(node, "RowHit").Activated.fire({
				UserInputType = engine.types.Enum.UserInputType.MouseButton1,
				KeyCode = engine.types.Enum.KeyCode.Unknown,
			}, 2)
			t.expect(built.nowPlaying:peek() ~= nil).toBe(true)
			built.restore()
			local mounted = census(engine)
			assert(mounted.live > before.live + 40, "the playlist surface was not standing")
			close()
			t.expect(header.isDestroyed()).toBe(true)
			t.expect(#ctx.target:GetChildren()).toBe(0)
			t.expect(engine.heartbeat.count()).toBe(0)
			same(before, census(engine), "playlist teardown")
		end)
	end)

	t.it("returns the toast lab to one baseline through twenty cycles in one runtime", function()
		inspected(function()
			local engine = engineLib.new()
			local ctx =
				exampleContext(engine, { reducedMotion = Compose.cell(false), pageVisible = Compose.cell(true) })
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
				t.expect(built.report().visible > 0).toBe(true)
				built.dismiss(first)
				engine.heartbeat.fire(0.05)
				find(node, "Burst").Activated.fire()
				t.expect(built.report().queued > 0).toBe(true)
				stop()
				t.expect(#ctx.target:GetChildren()).toBe(0)
				t.expect(engine.heartbeat.count()).toBe(0)
				same(baseline, census(engine), `toast cycle {cycle}`)
			end
			ctx.runtime:dispose()
		end)
	end)
	t.it("fires a radial callback that disposes its own menu exactly once", function()
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
						distribution = "compass",
						items = {
							{
								id = "N",
								slot = "N",
								label = "Go",
								onSelect = function()
									calls += 1
									stop()
								end,
							},
						},
					}),
				})
			end, w.target)
			local sector = find(node, "N")
			local press = touch(w.engine, 320, 110)
			t.expect(w.input.InputEnded.count() > 0).toBe(true)
			sector.InputBegan.fire(press)
			w.input.InputEnded.fire(press)
			t.expect(calls).toBe(1)
			t.expect(node.isDestroyed()).toBe(true)
			t.expect(sector.isDestroyed()).toBe(true)
			t.expect(w.input.InputEnded.count()).toBe(0)
			sector.Activated.fire(press)
			sector.InputBegan.fire(press)
			w.input.InputEnded.fire(press)
			sector.Activated.fire()
			t.expect(calls).toBe(1)
			w.runtime:dispose()
			same(before, census(w.engine), "radial self-disposal")
		end)
		inspected(function()
			local w = radialWorld(false)
			local shown, calls = Compose.cell(true), 0
			local stop, node = w.runtime.mount(function()
				return w.Host.ScreenGui({
					w.Host.Frame "Base" {},
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
								},
							},
						})
					end),
				})
			end, w.target)
			local open = census(w.engine)
			local item = find(node, "Go")
			item.Activated.fire()
			t.expect(calls).toBe(1)
			t.expect(item.isDestroyed()).toBe(true)
			item.Activated.fire()
			t.expect(calls).toBe(1)
			t.expect(w.input.InputEnded.count()).toBe(0)
			t.expect(census(w.engine).live < open.live).toBe(true)
			stop()
			w.runtime:dispose()
		end)
	end)

	t.it("leaves nothing of an open radial menu swapped or dismissed mid-animation", function()
		inspected(function()
			local w = radialWorld(true)
			local which, presented = Compose.cell("a"), {}
			local stop, node = w.runtime.mount(function()
				return w.Host.ScreenGui({
					Compose.keyed({
						from = function(use)
							return { { id = use(which) } }
						end,
						key = function(row)
							return row.id
						end,
						render = function(current)
							local opened = Compose.cell(false)
							presented[current:peek().id] = opened
							return w.UI.RadialMenu({
								label = "Quick",
								isPresented = opened,
								items = { { id = "One", label = "One" }, { id = "Two", label = "Two" } },
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
			t.expect(panel ~= nil).toBe(true)
			t.expect(census(w.engine).live > closed.live).toBe(true)
			which:set("b")
			w.step(0.6)
			t.expect(panel.isDestroyed()).toBe(true)
			t.expect(find(node, "RadialPanel")).toBeNil()
			t.expect(find(node, "One")).toBeNil()
			local swapped = census(w.engine)
			t.expect(swapped.live).toBe(closed.live)
			t.expect(swapped.connections).toBe(closed.connections)
			t.expect(swapped.owners).toBe(closed.owners)
			t.expect(swapped.holding).toBe(closed.holding)
			t.expect(w.engine.heartbeat.count()).toBe(0)
			presented.b:set(true)
			w.step(0.3)
			t.expect(find(node, "RadialPanel") ~= nil).toBe(true)
			t.expect(find(node, "One") ~= nil).toBe(true)
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
						center = "empty",
						items = {
							{
								id = "Gear",
								label = "Gear",
								navigation = "expand",
								children = { { id = "Tool", label = "Tool", onSelect = function() end } },
							},
						},
					}),
				})
			end, w.target)
			opened:set(true)
			w.step(0.04)
			find(node, "Gear").Activated.fire()
			w.step(0.04)
			local tool = find(node, "Tool")
			t.expect(tool ~= nil).toBe(true)
			opened:set(false)
			w.step(1 / 60)
			t.expect(w.engine.heartbeat.count() > 0).toBe(true)
			stop()
			stop()
			t.expect(tool.isDestroyed()).toBe(true)
			t.expect(w.engine.heartbeat.count()).toBe(0)
			w.runtime:dispose()
			same(before, census(w.engine), "radial dismissed mid-animation")
		end)
	end)
	t.it("returns counters to baseline when an open popup is dismissed or disposed", function()
		inspected(function()
			local w = controlWorld()
			local before = census(w.engine)
			local shown = Compose.cell(true)
			local picked, menuOpen, pickerOpen = Compose.cell("easy"), Compose.cell(false), Compose.cell(false)
			local stop = w.runtime.mount(function()
				return w.Host.Frame({
					w.Host.Frame "Base" {},
					Compose.show(shown, function()
						return w.Host.Frame "Surface" {
							w.UI.Picker({
								selected = picked,
								style = "menu",
								isPresented = pickerOpen,
								options = {
									{ value = "easy", label = "Easy" },
									{ value = "normal", label = "Normal" },
									{ value = "hard", label = "Hard" },
								},
							}),
							w.UI.Menu({
								label = "More",
								isPresented = menuOpen,
								items = {
									{
										id = "Nested",
										label = "Nested",
										children = { { id = "Run", label = "Run", onSelect = function() end } },
									},
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
				t.expect(pickerOpen:peek()).toBe(true)
				find(find(w.root, "MenuPanel"), "hard").Activated.fire()
				t.expect(picked:peek()).toBe("hard")
				find(w.root, "Trigger").Activated.fire()
				t.expect(find(w.root, "MenuPanel") ~= nil).toBe(true)
				menuOpen:set(true)
				find(w.root, "Nested").Activated.fire()
				t.expect(find(w.root, "Run") ~= nil).toBe(true)
				shown:set(false)
				t.expect(find(w.root, "MenuPanel")).toBeNil()
				t.expect(find(w.root, "Run")).toBeNil()
				same(hidden, census(w.engine), `popup dismissed while open {cycle}`)
				picked:set("easy")
				pickerOpen:set(false)
				menuOpen:set(false)
			end
			shown:set(true)
			pickerOpen:set(true)
			menuOpen:set(true)
			t.expect(find(w.root, "MenuPanel") ~= nil).toBe(true)
			stop()
			w.runtime:dispose()
			t.expect(#w.root:GetChildren()).toBe(0)
			same(before, census(w.engine), "popup disposed while open")
		end)
	end)

	t.it("leaves no instance connection or owner after the HUD rotation and URL bar sequence", function()
		inspected(function()
			local hud = require("../examples/gallery/scenarios/hud") :: any
			local engine = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local viewport = Compose.cell({ width = 1079, height = 809 })
			local target = engine.new("ScreenGui")
			local ctx = {
				Facet = Facet,
				Compose = Compose,
				runtime = runtime,
				Host = runtime.constructors,
				UI = Facet.controls(runtime, { types = engine.types, viewport = viewport } :: any),
				types = engine.types,
				viewport = viewport,
			}
			local before = census(engine)
			local built
			local stop, root = runtime.mount(function()
				built = hud.build(ctx)
				return built.screen()
			end, target)
			local body = find(root, "HudBody")
			local signal = body:GetPropertyChangedSignal("AbsoluteSize")
			built.steps.openUrlBar()
			viewport:set({ width = 360, height = 691 })
			body.AbsoluteSize = engine.types.Vector2.new(360, 560)
			built.steps.closeUrlBar()
			built.steps.openOverflow()
			built.steps.closeOverflow()
			viewport:set({ width = 1079, height = 809 })
			body.AbsoluteSize = engine.types.Vector2.new(1079, 700)
			find(root, "Overflow").Activated.fire()
			t.expect(built.report().overflowOpen).toBe(true)
			built.steps.closeOverflow()
			t.expect(census(engine).live > before.live + 50).toBe(true)
			t.expect(signal.count() > 0).toBe(true)
			stop()
			runtime:dispose()
			t.expect(signal.count()).toBe(0)
			t.expect(#target:GetChildren()).toBe(0)
			t.expect(body.isDestroyed()).toBe(true)
			same(before, census(engine), "HUD teardown")
		end)
	end)

	t.it("releases RowActions observers through twenty engaged branch removals", function()
		inspected(function()
			local w = controlWorld({ reducedMotion = false })
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
								},
							},
						}
					end),
				})
			end, w.root)
			local baseline = census(w.engine)
			for cycle = 1, 20 do
				shown:set(true)
				local row = find(node, "Row")
				t.expect(row ~= nil).toBe(true)
				row.AbsoluteSize = w.engine.types.Vector2.new(300, 40)
				open:set("trailing")
				w.engine.heartbeat.fire(0.3)
				local action = find(row, "Delete")
				t.expect(action ~= nil).toBe(true)
				t.expect(census(w.engine).connections > baseline.connections).toBe(true)
				open:set(nil)
				shown:set(false)
				w.engine.heartbeat.fire(0.5)
				t.expect(row.isDestroyed()).toBe(true)
				action.Activated.fire()
				t.expect(invoked).toBe(0)
				t.expect(w.engine.heartbeat.count()).toBe(0)
				same(baseline, census(w.engine), `RowActions removal {cycle}`)
			end
			stop()
			w.runtime:dispose()
			same(before, census(w.engine), "RowActions teardown")
		end)
	end)

	t.it("cancels Table reorder on capability loss and disposes to the registry baseline", function()
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
					columns = { { id = "label", label = "Label", width = 100 } },
				})
			end, w.root)
			local body = node:FindFirstChild("Body")
			body.AbsoluteWindowSize = w.engine.types.Vector2.new(200, 100)
			local handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
			handle.Activated.fire()
			t.expect(w.gui.SelectedObject.Name).toBe("Drop")
			local down = w.root:FindFirstChild("FacetReorderDown"):FindFirstChild("ReorderDown")
			down.Pressed.fire()
			down.Pressed.fire()
			t.expect(find(node, "Drop") ~= nil).toBe(true)
			w.input.KeyboardEnabled = false
			w.input.GamepadEnabled = false
			t.expect(find(node, "Drop")).toBeNil()
			w.root:FindFirstChild("FacetReorderDrop"):FindFirstChild("ReorderDrop").Pressed.fire()
			t.expect(#requests).toBe(0)
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
			t.expect(node:FindFirstChild("DropLine", true) ~= nil).toBe(true)
			w.input.MouseEnabled = false
			t.expect(node:FindFirstChild("DropLine", true)).toBeNil()
			w.input.InputEnded.fire(pointer)
			t.expect(#requests).toBe(0)
			t.expect(w.engine.heartbeat.count()).toBe(0)
			stop()
			w.runtime:dispose()
			t.expect(node.isDestroyed()).toBe(true)
			same(before, census(w.engine), "Table flip teardown")
		end)
	end)

	t.it("returns a list row to its closed shape after every RowActions engagement", function()
		inspected(function()
			local w = controlWorld({ reducedMotion = false })
			local before = census(w.engine)
			local opens = {}
			local stop, node = w.runtime.mount(function()
				return w.UI.VirtualList({
					from = records(100),
					key = byId,
					itemSize = 40,
					overscan = 0,
					render = function(current)
						local id = current:peek().id
						opens[id] = opens[id] or Compose.cell(nil :: string?)
						return w.UI.RowActions "Actions" {
							open = opens[id],
							content = w.UI.Text({
								text = function(use)
									return use(current).label
								end,
							}),
							trailing = {
								{ id = "Archive", label = "Archive", onActivate = function() end },
								{ id = "Delete", label = "Delete", role = "destructive", onActivate = function() end },
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
				t.expect(tray.Visible).toBe(true)
				t.expect(tray.Size.X.Offset > 0).toBe(true)
				t.expect(find(tray, "Delete") ~= nil).toBe(true)
				opens[2]:set(nil)
				settle(w.engine, 1)
				t.expect(tray.Visible).toBe(false)
				t.expect(shape(node)).toEqual(closedShape)
				same(closed, census(w.engine), `row engagement {cycle}`)
			end
			stop()
			w.runtime:dispose()
			same(before, census(w.engine), "row engagement teardown")
		end)
	end)
	t.it("returns a Table and TextInput screen to baseline after interaction and a mid-edit dispose", function()
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
					},
					w.UI.Table "Rows" {
						from = rows,
						key = byId,
						columns = { { id = "label", label = "Label" } },
						selection = selection,
						selectionMode = "single",
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
				KeyCode = w.engine.types.Enum.KeyCode.Unknown,
			}, 1)
			t.expect(next(selection:peek()) ~= nil).toBe(true)
			editing:set(true)
			local field = find(node, "Filter")
			field:CaptureFocus()
			field.Text = "ab"
			t.expect(value:peek()).toBe("ab")
			t.expect(field:IsFocused()).toBe(true)
			local text = field:GetPropertyChangedSignal("Text")
			stop()
			w.runtime:dispose()
			t.expect(field.isDestroyed()).toBe(true)
			t.expect(text.count()).toBe(0)
			t.expect(field.FocusLost.count()).toBe(0)
			t.expect(#w.root:GetChildren()).toBe(0)
			same(before, census(w.engine), "Table and TextInput teardown")
		end)
	end)

	t.it("releases a dismissed surface's button keys and held repeat before another surface binds them", function()
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
					end),
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
			t.expect(oldAction ~= nil).toBe(true)
			oldAction.Pressed.fire()
			t.expect(oldCalls).toBe(1)
			oldButton.InputBegan.fire({
				UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
				KeyCode = w.engine.types.Enum.KeyCode.Unknown,
			})
			w.engine.heartbeat.fire(0.4)
			t.expect(oldCalls).toBe(2)
			oldShown:set(false)
			t.expect(oldButton.isDestroyed()).toBe(true)
			t.expect(oldAction.Pressed.count()).toBe(0)
			t.expect(w.engine.heartbeat.count()).toBe(0)
			settle(w.engine, 1)
			oldAction.Pressed.fire()
			t.expect(oldCalls).toBe(2)
			newShown:set(true)
			local newAction = find(w.root, "Shortcut")
			t.expect(newAction ~= oldAction).toBe(true)
			newAction.Pressed.fire()
			t.expect(newCalls).toBe(1)
			t.expect(oldCalls).toBe(2)
			stop()
			w.runtime:dispose()
			t.expect(newAction.Pressed.count()).toBe(0)
			same(before, census(w.engine), "button key teardown")
		end)
	end)

	t.it("edits TextInput without remounting and disposes mid-edit to the registry baseline", function()
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
				t.expect(value:peek()).toBe(typed)
			end
			t.expect(edits).toBe(5)
			t.expect(#w.engine.made).toBe(created)
			local typing = census(w.engine)
			t.expect(typing.live).toBe(mounted.live)
			t.expect(typing.owners).toBe(mounted.owners)
			t.expect(field:IsFocused()).toBe(true)
			local text = field:GetPropertyChangedSignal("Text")
			stop()
			w.runtime:dispose()
			t.expect(commits).toBe(0)
			t.expect(field.isDestroyed()).toBe(true)
			t.expect(text.count()).toBe(0)
			t.expect(field.FocusLost.count()).toBe(0)
			same(before, census(w.engine), "TextInput mid-edit teardown")
		end)
	end)

	t.it("disposes owner trees once, contains a throwing cleanup, and survives repeated disposal", function()
		inspected(function()
			local source, seen = Compose.cell(1), 0
			local parent = Compose.createOwner()
			local base = parent.size()
			local child = parent.createChild()
			local unwatch = child.watch(function(use)
				use(source)
				seen += 1
			end)
			t.expect(parent.size()).toBe(base + 1)
			source:set(2)
			t.expect(seen).toBe(2)
			unwatch()
			unwatch()
			source:set(3)
			t.expect(seen).toBe(2)
			child.dispose()
			t.expect(parent.size()).toBe(base)
			local second, runs = parent.createChild(), 0
			second.watch(function(use)
				use(source)
				runs += 1
			end)
			parent.dispose()
			parent.dispose()
			t.expect(second.isDisposed()).toBe(true)
			source:set(4)
			t.expect(runs).toBe(1)
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
			t.expect(released).toBe(2)
			t.expect(scope.isDisposed()).toBe(true)
			pcall(scope.dispose)
			t.expect(released).toBe(2)
			local count, holding = owners()
			t.expect(count).toBe(0)
			t.expect(holding).toBe(0)
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
				Compose.watch(function(use)
					use(source)
					calls += 1
				end)
				local child = Compose.currentOwner().createChild()
				child.own(function()
					released += 1
				end)
				return w.Host.Frame({ w.UI.Text({ text = "Owned" }) })
			end, w.root)
			source:set(1)
			t.expect(calls).toBe(2)
			pcall(stop)
			pcall(stop)
			t.expect(released).toBe(2)
			t.expect(node.isDestroyed()).toBe(true)
			source:set(2)
			t.expect(calls).toBe(2)
			local again = Compose.cell("a")
			local stopAgain, label = w.runtime.mount(function()
				return w.UI.Text({ text = again })
			end, w.root)
			again:set("b")
			t.expect(label.Text).toBe("b")
			stopAgain()
			w.runtime:dispose()
			w.runtime:dispose()
			same(before, census(w.engine), "throwing cleanup teardown")
		end)
	end)

	t.it("stops mounted watches and child cleanups with the mount and tolerates repeated disposal", function()
		inspected(function()
			local w = controlWorld()
			local before = census(w.engine)
			local source, watched, cleaned = Compose.cell(0), 0, 0
			local node
			local stop = w.runtime.mount(function()
				Compose.watch(function(use)
					use(source)
					watched += 1
				end)
				local child = Compose.currentOwner().createChild()
				child.own(function()
					cleaned += 1
				end)
				node = w.Host.Frame({ w.UI.Button({ label = "Live" }) })
				return node
			end, w.root)
			source:set(1)
			t.expect(watched).toBe(2)
			t.expect(Compose.outstandingMounts()).toBe(before.mounts + 1)
			stop()
			t.expect(Compose.outstandingMounts()).toBe(before.mounts)
			t.expect(cleaned).toBe(1)
			t.expect(node.isDestroyed()).toBe(true)
			source:set(2)
			t.expect(watched).toBe(2)
			stop()
			w.runtime:dispose()
			w.runtime:dispose()
			t.expect(cleaned).toBe(1)
			source:set(3)
			t.expect(watched).toBe(2)
			same(before, census(w.engine), "runtime dispose")
		end)
	end)

	t.it("disposes a mount from inside an observer without a fault in either order", function()
		for _, observerFirst in { true, false } do
			inspected(function()
				local w = controlWorld()
				local before = census(w.engine)
				local flag = Compose.cell(false)
				local observer = Compose.createOwner()
				local stop: () -> ()
				local stopped = 0
				local function watch()
					observer.watch(function(use)
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
				t.expect(stopped).toBe(1)
				t.expect(node.isDestroyed()).toBe(true)
				t.expect(#w.root:GetChildren()).toBe(0)
				stop()
				flag:set(false)
				flag:set(true)
				t.expect(#w.root:GetChildren()).toBe(0)
				observer.dispose()
				w.runtime:dispose()
				same(before, census(w.engine), `observer disposal first={observerFirst}`)
			end)
		end
	end)

	t.it("releases several pending exits at once when the runtime shuts down", function()
		for _, reduced in { false, true } do
			inspected(function()
				local w = controlWorld({ reducedMotion = reduced })
				local before = census(w.engine)
				local leaving, staying, present = Compose.cell(true), Compose.cell(true), Compose.cell(true)
				local cleaned = {}
				local function region(name)
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
							actions = { { id = "ok", label = "OK" } },
							transition = { seconds = 0.4 },
						}),
						w.UI.Alert({
							isPresented = staying,
							title = "Staying",
							actions = { { id = "ok", label = "OK" } },
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
				t.expect(region ~= nil).toBe(true)
				leaving:set(false)
				present:set(false)
				w.engine.heartbeat.fire(1 / 60)
				t.expect(region.isDestroyed()).toBe(reduced)
				t.expect(cleaned.Region or 0).toBe(if reduced then 1 else 0)
				stop()
				w.runtime:dispose()
				t.expect(region.isDestroyed()).toBe(true)
				t.expect(cleaned.Region).toBe(1)
				t.expect(w.engine.heartbeat.count()).toBe(0)
				t.expect(#w.root:GetChildren()).toBe(0)
				same(before, census(w.engine), `shutdown reduced={reduced}`)
				settle(w.engine, 1)
				t.expect(cleaned.Region).toBe(1)
			end)
		end
	end)

	t.it("sweeps the old subtree when a branch puts a different node at the same position", function()
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
					Compose.show(flag, slot("Alpha"), slot("Beta")),
					w.Host.Frame "Keyed" {
						Compose.keyed({
							from = function(use)
								return { { id = use(which) } }
							end,
							key = byId,
							render = function(current)
								return w.Host.Frame "Slot" { w.Host.TextLabel(current:peek().id) { Text = "row" } }
							end,
						}),
					},
				})
			end, w.root)
			local mounted = census(w.engine)
			for cycle = 1, 20 do
				local alphaSlot, alpha = find(node, "Slot"), find(node, "Alpha")
				local keyedSlot, a = find(find(node, "Keyed"), "Slot"), find(node, "a")
				t.expect(alpha ~= nil and a ~= nil).toBe(true)
				flag:set(false)
				which:set("b")
				t.expect(alphaSlot.isDestroyed()).toBe(true)
				t.expect(alpha.isDestroyed()).toBe(true)
				t.expect(keyedSlot.isDestroyed()).toBe(true)
				t.expect(a.isDestroyed()).toBe(true)
				t.expect(find(node, "Alpha")).toBeNil()
				t.expect(find(node, "a")).toBeNil()
				t.expect(find(node, "Beta") ~= nil).toBe(true)
				t.expect(find(node, "b") ~= nil).toBe(true)
				t.expect(#find(node, "Keyed"):GetChildren()).toBe(1)
				flag:set(true)
				which:set("a")
				t.expect(find(node, "Beta")).toBeNil()
				t.expect(find(node, "b")).toBeNil()
				same(mounted, census(w.engine), `replaced occupant {cycle}`)
			end
			stop()
			w.runtime:dispose()
			same(before, census(w.engine), "replaced occupant teardown")
		end)
	end)
	t.it("releases evicted image buttons and their hover observers with the branch", function()
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
				t.expect(calls).toBe(cycle)
				t.expect(card:connectionCount() > 0).toBe(true)
				shown:set(false)
				settle(w.engine, 1)
				t.expect(card.isDestroyed()).toBe(true)
				t.expect(card:connectionCount()).toBe(0)
				card.MouseEnter.fire()
				card.MouseLeave.fire()
				card.Activated.fire()
				t.expect(calls).toBe(cycle)
				same(hidden, census(w.engine), `image button eviction {cycle}`)
			end
			stop()
			w.runtime:dispose()
			same(before, census(w.engine), "image button teardown")
		end)
	end)

	t.it("releases every NavigationStack page when disposal lands mid-transition", function()
		for _, reduced in { false, true } do
			inspected(function()
				local w = controlWorld({ reducedMotion = reduced })
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
				t.expect(built >= 3).toBe(true)
				t.expect(built - disposed >= 2).toBe(true)
				if not reduced then
					t.expect(w.engine.heartbeat.count() > 0).toBe(true)
				end
				stop()
				w.runtime:dispose()
				t.expect(disposed).toBe(built)
				t.expect(node.isDestroyed()).toBe(true)
				t.expect(w.engine.heartbeat.count()).toBe(0)
				same(before, census(w.engine), `stack mid-flight reduced={reduced}`)
				settle(w.engine, 1)
				t.expect(disposed).toBe(built)
			end)
		end
	end)

	t.it(
		"remounts one NavigationStack without accumulating observers and ignores path writes after disposal",
		function()
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
				t.expect(built).toBe(builds)
				t.expect(disposed).toBe(built)
				t.expect(#w.root:GetChildren()).toBe(0)
				same(after, census(w.engine), "stack path writes after disposal")
				w.runtime:dispose()
				same(before, census(w.engine), "stack teardown")
			end)
		end
	)

	t.it("disposes icon-only vertical indicated segmented pickers to the registry baseline after switching", function()
		for _, indicator in { "pill", "underline" } do
			inspected(function()
				local w = controlWorld({ reducedMotion = false })
				local before = census(w.engine)
				local selected, changes = Compose.cell("grid"), 0
				local stop, node = w.runtime.mount(function()
					return w.UI.Picker({
						selected = selected,
						style = "segmented",
						axis = "y",
						iconOnly = true,
						indicator = indicator,
						options = {
							{ value = "grid", label = "Grid", icon = "edit" },
							{ value = "list", label = "Listing", icon = "edit" },
							{ value = "cards", label = "Cards", icon = "edit" },
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
					t.expect(selected:peek()).toBe("list")
					find(node, "cards").Activated.fire()
					w.engine.heartbeat.fire(1 / 60)
					selected:set("grid")
					settle(w.engine, 0.5)
					same(warm, census(w.engine), `{indicator} indicator round trip {cycle}`)
				end
				t.expect(changes).toBe(12)
				t.expect(w.engine.heartbeat.count()).toBe(0)
				stop()
				w.runtime:dispose()
				t.expect(node.isDestroyed()).toBe(true)
				same(before, census(w.engine), `{indicator} picker teardown`)
			end)
		end
	end)

	t.it("returns a menu picker to baseline after open select reopen and cancel", function()
		inspected(function()
			local w = controlWorld()
			local before = census(w.engine)
			local selected, opened, changes = Compose.cell("normal"), Compose.cell(false), 0
			local stop = w.runtime.mount(function()
				return w.Host.Frame({
					w.UI.Picker "Difficulty" {
						selected = selected,
						style = "menu",
						isPresented = opened,
						options = {
							{ value = "easy", label = "Easy" },
							{ value = "normal", label = "Normal" },
							{ value = "hard", label = "Hard" },
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
				t.expect(opened:peek()).toBe(true)
				find(find(w.root, "MenuPanel"), "hard").Activated.fire()
				t.expect(selected:peek()).toBe("hard")
				t.expect(opened:peek()).toBe(false)
				find(w.root, "Trigger").Activated.fire()
				local catcher = find(w.root, "DismissOutside")
				t.expect(catcher ~= nil).toBe(true)
				catcher.Activated.fire({ Position = w.engine.types.Vector2.new(0, 0) })
				t.expect(opened:peek()).toBe(false)
				t.expect(find(w.root, "MenuPanel")).toBeNil()
				t.expect(selected:peek()).toBe("hard")
				selected:set("normal")
				same(closed, census(w.engine), `menu picker cycle {cycle}`)
			end
			t.expect(changes).toBe(3)
			stop()
			w.runtime:dispose()
			same(before, census(w.engine), "menu picker teardown")
		end)
	end)

	t.it("reopens a bound Sheet with fresh content and disposes it to baseline", function()
		inspected(function()
			local w = controlWorld({ reducedMotion = false })
			local before = census(w.engine)
			local shown, detent, live, visits = Compose.cell(false), Compose.cell("medium"), 0, 0
			local stop = w.runtime.mount(function()
				return w.Host.Frame({
					w.UI.Sheet({
						title = "Details",
						isPresented = shown,
						detent = detent,
						content = function()
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
			t.expect(live).toBe(1)
			local body = find(w.root, "Body")
			find(w.root, "Close").Activated.fire()
			t.expect(shown:peek()).toBe(false)
			settle(w.engine, 1.5)
			t.expect(live).toBe(0)
			t.expect(body.isDestroyed()).toBe(true)
			same(closed, census(w.engine), "sheet closed")
			shown:set(true)
			settle(w.engine, 1.5)
			t.expect(live).toBe(1)
			t.expect(visits).toBe(2)
			t.expect(find(w.root, "Body") ~= body).toBe(true)
			detent:set("large")
			settle(w.engine, 1.5)
			stop()
			w.runtime:dispose()
			t.expect(live).toBe(0)
			t.expect(w.engine.heartbeat.count()).toBe(0)
			same(before, census(w.engine), "sheet teardown")
		end)
	end)

	t.it("keeps model state outside a top-retention TabView across page disposal", function()
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
							content = function()
								entries += 1
								for _ = 1, 5 do
									local memo = Compose.formula(function(use)
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
						},
						{
							id = "feed",
							label = "Feed",
							content = function()
								return w.Host.TextLabel "FeedBody" { Text = "feed" }
							end,
						},
					},
				})
			end, w.root)
			local body = find(node, "HomeBody")
			t.expect(body.Text).toBe("half typed")
			selection:set("feed")
			t.expect(disposed).toBe(1)
			t.expect(released).toBe(5)
			t.expect(body.isDestroyed()).toBe(true)
			draft:set("typed while away")
			selection:set("home")
			t.expect(entries).toBe(2)
			t.expect(released).toBe(5)
			t.expect(find(node, "HomeBody").Text).toBe("typed while away")
			stop()
			t.expect(disposed).toBe(2)
			t.expect(released).toBe(10)
			t.expect(draft:peek()).toBe("typed while away")
			w.runtime:dispose()
			same(before, census(w.engine), "top retention teardown")
		end)
	end)

	t.it("keeps a badged sidebar TabView registry-neutral through twenty switches and disposal", function()
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
			local function page(name)
				return function()
					return w.Host.TextLabel(name .. "Body") { Text = name }
				end
			end
			local stop, node = w.runtime.mount(function()
				return w.UI.TabView({
					selection = selection,
					style = "sidebarAdaptable",
					placement = "sidebar",
					transition = false,
					sections = { { id = "main", label = "Main", tabs = { "a", "b", "c" } } },
					accessories = { head = accessory, foot = accessory },
					tabs = {
						{ id = "a", label = "A", badge = "2", content = page("a") },
						{ id = "b", label = "B", content = page("b") },
						{ id = "c", label = "C", content = page("c") },
					},
				})
			end, w.root)
			find(node, "TabView").AbsoluteSize = w.engine.types.Vector2.new(1200, 800)
			for _, id in { "b", "c", "a" } do
				selection:set(id)
			end
			local warm = census(w.engine)
			t.expect(built > 0).toBe(true)
			for cycle = 1, 20 do
				selection:set(if cycle % 2 == 0 then "b" else "c")
				selection:set("a")
				same(warm, census(w.engine), `tab switch {cycle}`)
			end
			stop()
			w.runtime:dispose()
			t.expect(retired).toBe(built)
			same(before, census(w.engine), "tab view teardown")
		end)
	end)

	t.it("disposes a tab accessory at the moment it is re-homed", function()
		inspected(function()
			local w = controlWorld()
			local before = census(w.engine)
			local retired, built = 0, 0
			local stop, node = w.runtime.mount(function()
				return w.UI.TabView({
					selection = Compose.cell("one"),
					style = "sidebarAdaptable",
					tabs = {
						{
							id = "one",
							label = "One",
							content = function()
								return w.Host.Frame({})
							end,
						},
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
			t.expect(wordmark ~= nil).toBe(true)
			t.expect(retired).toBe(0)
			root.AbsoluteSize = w.engine.types.Vector2.new(390, 700)
			t.expect(retired).toBe(1)
			t.expect(wordmark.isDestroyed()).toBe(true)
			root.AbsoluteSize = w.engine.types.Vector2.new(1200, 800)
			t.expect(built).toBe(2)
			t.expect(find(node, "Wordmark") ~= wordmark).toBe(true)
			stop()
			w.runtime:dispose()
			t.expect(retired).toBe(built)
			same(before, census(w.engine), "accessory teardown")
		end)
	end)
	t.it("keeps decorations through palette-only swaps and destroys every one it created", function()
		inspected(function()
			local theme = Compose.cell(skinnedPackage())
			local w = controlWorld({ theme = theme })
			local before = census(w.engine)
			local stop = w.runtime.mount(function()
				return w.Host.Frame({ w.UI.Button "First" { label = "One" }, w.UI.Button "Second" { label = "Two" } })
			end, w.root)
			local initial = images(w.root)
			t.expect(#initial >= 8).toBe(true)
			local created = #w.engine.made
			for step = 1, 50 do
				theme:set(skinnedPackage({ r = step / 50, g = 0.2, b = 0.3 }))
				t.expect(#w.engine.made).toBe(created)
				local current = images(w.root)
				t.expect(#current).toBe(#initial)
				for _, image in initial do
					t.expect(image.isDestroyed()).toBe(false)
					t.expect(table.find(current, image) ~= nil).toBe(true)
				end
			end
			theme:set(Facet.themes.neutralPackage())
			for _, image in initial do
				t.expect(image.Visible).toBe(false)
			end
			theme:set(skinnedPackage())
			t.expect(#w.engine.made).toBe(created)
			for _, image in initial do
				t.expect(image.Visible).toBe(true)
			end
			stop()
			w.runtime:dispose()
			local made = 0
			for _, instance in w.engine.made do
				if instance.ClassName == "ImageLabel" then
					made += 1
					t.expect(instance.isDestroyed()).toBe(true)
				end
			end
			t.expect(made).toBe(#initial)
			same(before, census(w.engine), "decoration teardown")
		end)
	end)

	t.it("drops the skin ladder lifted caption and state observers with the decorated node", function()
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
				t.expect(caption ~= nil).toBe(true)
				t.expect(caption.Text).toBe("Play")
				t.expect(button:HasTag("facet-skin-caption")).toBe(true)
				local state = button:GetPropertyChangedSignal("GuiState")
				local text = button:GetPropertyChangedSignal("Text")
				t.expect(state.count() > 0).toBe(true)
				button.GuiState = w.engine.types.Enum.GuiState.Press
				local ladder = images(button)
				t.expect(#ladder >= 6).toBe(true)
				theme:set(Facet.themes.neutralPackage())
				t.expect(button:HasTag("facet-skin-caption")).toBe(false)
				t.expect(caption.Parent.Visible).toBe(false)
				theme:set(skinnedPackage())
				t.expect(find(button, "PlaqueCaption")).toBe(caption)
				t.expect(caption.Parent.Visible).toBe(true)
				shown:set(false)
				t.expect(button.isDestroyed()).toBe(true)
				t.expect(caption.isDestroyed()).toBe(true)
				for _, image in ladder do
					t.expect(image.isDestroyed()).toBe(true)
				end
				t.expect(state.count()).toBe(0)
				t.expect(text.count()).toBe(0)
				same(hidden, census(w.engine), `skin teardown {cycle}`)
			end
			stop()
			w.runtime:dispose()
		end)
	end)

	t.it("sizes bar skin art from unscaled pixels under a UIScale and tears the bar down", function()
		inspected(function()
			local package = Facet.themes.neutralPackage() :: any
			package.assets = {
				fill = { content = "rbxassetid://1" },
				start = { content = "rbxassetid://2" },
				finish = { content = "rbxassetid://3" },
			}
			package.chrome.barFill = { kind = "nineSlice", asset = "fill" }
			package.chrome.barCap =
				{ kind = "nineSlice", startAsset = "start", endAsset = "finish", size = { w = 28, h = 36 } }
			local w = controlWorld({ theme = package })
			local before = census(w.engine)
			local value = Compose.cell(0.25)
			local stop, root = w.runtime.mount(function()
				return w.UI.ProgressView({ value = value })
			end, w.root)
			local fill = root:FindFirstChild("Fill1", true)
			local boundary = fill:FindFirstChild("SkinBoundary")
			local bounds = fill:FindFirstChild("SkinBounds", true)
			for _, case in { { factor = 2, width = 25 }, { factor = 0.5, width = 25 }, { factor = 2, width = 50 } } do
				if case.width == 50 then
					value:set(0.5)
				end
				boundary.AbsoluteSize = w.engine.types.Vector2.new(case.factor, case.factor)
				fill.AbsoluteSize = w.engine.types.Vector2.new(case.width * case.factor, 6 * case.factor)
				t.expect(bounds.Size.X.Offset).toBe(case.width)
				t.expect(bounds.Size.Y.Offset).toBe(6)
			end
			local sized = fill:GetPropertyChangedSignal("AbsoluteSize")
			local scaled = boundary:GetPropertyChangedSignal("AbsoluteSize")
			t.expect(sized.count() > 0 and scaled.count() > 0).toBe(true)
			local art = images(root)
			t.expect(#art >= 3).toBe(true)
			stop()
			w.runtime:dispose()
			t.expect(sized.count()).toBe(0)
			t.expect(scaled.count()).toBe(0)
			t.expect(fill.ChildAdded.count()).toBe(0)
			for _, image in art do
				t.expect(image.isDestroyed()).toBe(true)
			end
			same(before, census(w.engine), "bar skin teardown")
		end)
	end)

	t.it("rewires reused row containers to the current item without stale connections", function()
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
					render = function(current)
						return w.UI.Button "Action" {
							label = function(use)
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
				t.expect(count).toBe(perContainer)
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
					t.expect(count).toBe(perContainer)
					local button = row:FindFirstChild("Action", true)
					if row.Visible ~= false and button then
						table.clear(activated)
						button.Activated.fire()
						t.expect(#activated).toBe(1)
						t.expect(tostring(activated[1])).toBe(button.Text)
						t.expect(row.Name).toBe(button.Text)
					end
				end
				same(mounted, census(w.engine), `row reuse {cycle}`)
			end
			t.expect(reused).toBe(true)
			stop()
			w.runtime:dispose()
			same(before, census(w.engine), "row reuse teardown")
		end)
	end)

	t.it("returns the performance lab to its floor through repeated mount ramp laps", function()
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
			local engine = engineLib.new({ cacheDefaults = true })
			local runtime = Facet.Roblox.createRuntime(engine)
			local target = engine.new("Folder")
			local probe
			local world = {
				Facet = Facet,
				Compose = Compose,
				runtime = runtime,
				Host = runtime.constructors,
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
						orientation = "landscape",
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
					t.expect(probe.state().rows).toBe(modules.dataset.RAMP_STEPS[rung])
				end
				t.expect(probe.state().queued).toBe(0)
				t.expect(probe.state().playing).toBe(false)
			end
			lap()
			lap()
			local floor = census(engine)
			local captures = probe.state().captures
			for index = 1, 3 do
				lap()
				t.expect(probe.state().captures).toBe(captures + index * #modules.dataset.RAMP_STEPS)
				same(floor, census(engine), `ramp lap {index}`)
			end
			stop()
			runtime:dispose()
			t.expect(#target:GetChildren()).toBe(0)
			t.expect(engine.heartbeat.count()).toBe(0)
			same(before, census(engine), "lab teardown")
		end)
	end)
end)
