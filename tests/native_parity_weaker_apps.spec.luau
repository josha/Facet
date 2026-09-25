--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local glade = require("../examples/reference/p1_glade")
local gladeSeed = require("../examples/reference/p1_glade/content/seed")
local gladeStrings = require("../examples/reference/p1_glade/content/strings")
local cartwheel = require("../examples/reference/p2_cartwheel")
local sipworks = require("../examples/reference/p3_sipworks")
local sipStrings = require("../examples/reference/p3_sipworks/content/strings")
local sipTask = require("../examples/reference/p3_sipworks/services/task")
local sipOrder = require("../examples/reference/p3_sipworks/services/order")
local sipUnlock = require("../examples/reference/p3_sipworks/services/recipe_unlock")
local foyer = require("../examples/reference/p4_foyer")
local foyerSeed = require("../examples/reference/p4_foyer/content/seed")
local foyerStrings = require("../examples/reference/p4_foyer/content/strings")
local gallery = require("../examples/gallery/client/screen")
local scaffold = require("../tools/lune/scaffold")
local checkLinks = require("../tools/lune/check_links")
local luau = require("@lune/luau")
local process = require("@lune/process")
local catalogue = require("../examples/gallery/client/demo_picker")
local Compose = Facet.Compose

type World = {
	built: any,
	root: any,
	screen: any,
	engine: any,
	input: any,
	baseline: any,
	stop: () -> (),
}

local function world(module: any): World
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local screen = engine.new("ScreenGui")
	local baseline = engine.census()
	local built
	local stop, root = runtime.mount(function()
		built = module.build({
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = runtime.constructors,
			UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					guiService = gui,
					services = { GuiService = gui, UserInputService = input },
				} :: any
			),
			types = engine.types,
			viewport = Compose.cell({ width = 1000, height = 720 }),
			heartbeat = engine.heartbeat,
		})
		return built.screen()
	end, screen)
	return {
		built = built,
		root = root,
		screen = screen,
		engine = engine,
		input = input,
		baseline = baseline,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
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

local function within(node: any, ...: string): any
	local at = node
	for _, name in { ... } do
		at = find(at, name)
		if at == nil then
			return nil
		end
	end
	return at
end

local function texts(node: any): { string }
	local out = {}
	for _, child in node:GetDescendants() do
		if child.ClassName == "TextLabel" or child.ClassName == "TextButton" or child.ClassName == "TextBox" then
			if child.Text ~= "" then
				table.insert(out, child.Text)
			end
		end
	end
	return out
end

local function hasText(node: any, text: string): boolean
	return table.find(texts(node), text) ~= nil
end

local function modal(screen: any): any
	for _, child in screen:GetDescendants() do
		if child.Name == "SheetPanel" or child.Name == "AlertPanel" then
			return child
		end
	end
	return nil
end

local function press(node: any, ...: string)
	local target = assert(within(node, ...), `no {table.concat({ ... }, "/")}`)
	target.Activated.fire()
end

local function type_(node: any, name: string, value: string)
	local box = assert(find(node, name), `no text input {name}`)
	box:CaptureFocus()
	box.Text = value
	box:ReleaseFocus(true)
end

local function rows(node: any): { string }
	local children = {}
	for _, child in node:GetChildren() do
		if child.ClassName == "Frame" then
			table.insert(children, child)
		end
	end
	table.sort(children, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local out = {}
	for _, child in children do
		table.insert(out, child.Name)
	end
	return out
end

local function pick(w: World, picker: any, value: string)
	press(picker, "Trigger")
	press(assert(find(w.screen, "MenuPanel"), "no open menu"), value)
end

local function same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not same(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function pages(w: World): any
	return assert(within(w.root, "Destinations", "Content"))
end

local function tabs(w: World): any
	return assert(within(w.root, "Destinations", "Tabs"))
end

local function released(w: World)
	t.expect(w.root.isDestroyed()).toBe(true)
	t.expect(w.engine.heartbeat.count()).toBe(0)
	t.expect(w.engine.census().live).toBe(w.baseline.live)
	t.expect(w.engine.census().connections).toBe(w.baseline.connections)
end

local function shell(demo: any, load: (string, string) -> any): (any, any, () -> ())
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local target, gui = engine.new("Folder"), engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
	input.GetFocusedTextBox = function()
		return nil
	end
	local ctx: { [string]: any } = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = Compose.cell({ width = 1280, height = 720 }),
		inputTarget = target,
		guiService = gui,
		runService = { Heartbeat = engine.heartbeat },
		heartbeat = engine.heartbeat,
		selection = Compose.cell(demo.id),
		theme = Compose.cell(Facet.themes.neutralPackage()),
		themeMode = Compose.cell("light"),
		demos = { demo },
		load = load,
	}
	ctx.packages = { Neutral = ctx.theme:peek() }
	local stop, root = runtime.mount(function()
		gallery.configure(ctx)
		ctx.UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				viewport = ctx.viewport,
				inputParent = target,
				services = { GuiService = gui, UserInputService = input },
				theme = ctx.theme,
				reducedMotion = ctx.reducedMotion,
			} :: any
		)
		return ctx.Host.ScreenGui "GalleryTest" { gallery.build(ctx) }
	end, target)
	return ctx, root, function()
		stop()
		runtime:dispose()
	end
end

local REFERENCE = { "p1_glade", "p2_cartwheel", "p3_sipworks", "p4_foyer" }

local function bootsOneModule(scenario: string, module: string, title: string, expected: any)
	local source = fs.readFile(`examples/gallery/scenarios/{scenario}.luau`)
	t.expect(string.find(source, `ctx.load("reference", "{module}")`, 1, true) ~= nil).toBe(true)
	for _, other in REFERENCE do
		if other ~= module then
			t.expect(`{other}: {string.find(source, other, 1, true) ~= nil}`).toBe(`{other}: false`)
		end
	end
	local place = fs.readFile("tools/build_reference_places.sh")
	t.expect(string.find(place, `"{scenario}|Facet-Ref-{title}"`, 1, true) ~= nil).toBe(true)
	local folders = { FacetScenarios = "gallery/scenarios", FacetReference = "reference" }
	for folder, path in folders do
		t.expect(string.find(place, `"{folder}": \{ "\\$path": "{path}" }`, 1, true) ~= nil).toBe(true)
		for _, project in { "examples/gallery.project.json", "examples/showcase.project.json" } do
			local tree = serde.decode("json", fs.readFile(project)).tree
			t.expect(`{project} {folder}: {tree.ReplicatedStorage[folder]["$path"]}`).toBe(`{project} {folder}: {path}`)
		end
	end
	local hits = {}
	for _, entry in fs.readDir("examples/reference") do
		local init = `examples/reference/{entry}/init.luau`
		if
			fs.isDir(`examples/reference/{entry}`)
			and fs.isFile(init)
			and string.find(fs.readFile(init), `{title}.build`, 1, true)
		then
			table.insert(hits, entry)
		end
	end
	t.expect(table.concat(hits, ",")).toBe(module)
	local id, demo = catalogue.boot(nil, scenario, nil)
	t.expect(id).toBe(scenario)
	local loads = {}
	local scenarios: { [string]: any } = {
		ref_glade = require("../examples/gallery/scenarios/ref_glade"),
		ref_sipworks = require("../examples/gallery/scenarios/ref_sipworks"),
	}
	local references: { [string]: any } = {
		p1_glade = glade,
		p3_sipworks = sipworks,
	}
	local ctx, root, stop = shell(demo, function(kind, name)
		table.insert(loads, `{kind}:{name}`)
		return if kind == "reference" then references[name] else scenarios[name]
	end)
	t.expect(table.concat(loads, ",")).toBe(`fixture:{scenario},reference:{module}`)
	t.expect(references[module]).toBe(expected)
	t.expect(ctx.errorMessage:peek()).toBeNil()
	t.expect(ctx.active:peek()).toBe(scenario)
	t.expect(find(root, "DemoFailure")).toBeNil()
	local app = assert(find(root, title), `no mounted {title}`)
	t.expect(app.ClassName).toBe("Frame")
	t.expect(find(app, "Destinations") ~= nil).toBe(true)
	stop()
	t.expect(app.isDestroyed()).toBe(true)
end

t.describe("Glade", function()
	t.it(
		"apps-01 builds and mounts without an error, reports identically for two builds and releases everything",
		function()
			t.expect(type(glade.build)).toBe("function")
			t.expect(glade.title).toBe("Glade")
			local ok, a = pcall(world, glade)
			t.expect(ok).toBe(true)
			local b = world(glade)
			t.expect(a.root.ClassName).toBe("Frame")
			t.expect(a.root.Name).toBe("Glade")
			t.expect(find(a.root, "Destinations") ~= nil).toBe(true)
			t.expect(within(pages(a), "glades", "Glades") ~= nil).toBe(true)
			t.expect(same(a.built.report(), b.built.report())).toBe(true)
			local function drive(target: World)
				local steps = target.built.steps
				steps.advance(120)
				steps.open("mossholm")
				steps.refill("mossholm")
				steps.choose("mossholm", "starlight")
				steps.buy("starlightSingle")
				steps.advance(gladeSeed.COMMAND_SECONDS)
				steps.charm("ember")
				steps.advance(gladeSeed.COMMAND_SECONDS)
			end
			drive(a)
			drive(b)
			t.expect(same(a.built.report(), b.built.report())).toBe(true)
			t.expect(same(a.built.report(), a.built.report())).toBe(true)
			t.expect(a.built.report().commerce.attempts.pack).toBe(1)
			t.expect(modal(a.screen) ~= nil).toBe(true)
			a.engine.heartbeat.fire(0.5)
			a.engine.heartbeat.fire(0.5)
			t.expect(a.engine.heartbeat.count()).toBe(1)
			a.engine.heartbeat.fire(0.5)
			a.stop()
			b.stop()
			released(a)
			released(b)
		end
	)

	t.it(
		"apps-03 assigns and refills nectar, consumes a premium satchel, finishes the task in either order and keeps every destination",
		function()
			local w = world(glade)
			local model, steps = w.built.model, w.built.model.supply
			local held = model.commerce.satchelOf("starlight")
			press(pages(w), "glades", "mossholm", "Open")
			local sheet = assert(modal(w.screen))
			t.expect(hasText(sheet, "Mossholm")).toBe(true)
			local nectarPicker = assert(within(sheet, "GladeDetail", "Nectar"))
			t.expect(held:peek()).toBe(gladeSeed.SATCHEL.starlight)
			pick(w, nectarPicker, "starlight")
			t.expect(steps.nectarOf("mossholm"):peek()).toBe("starlight")
			t.expect(held:peek()).toBe(gladeSeed.SATCHEL.starlight - 1)
			t.expect(find(nectarPicker, "Trigger").Text).toBe(gladeStrings.get("en", "nectar.starlight"))
			w.built.steps.advance(gladeSeed.DRAIN.nectar.empty)
			t.expect(steps.state("mossholm", "nectar"):peek()).toBe("empty")
			t.expect(steps.level("mossholm", "nectar"):peek()).toBe(0)
			t.expect(hasText(sheet, "Nectar: empty")).toBe(true)
			pick(w, nectarPicker, "fern")
			t.expect(steps.nectarOf("mossholm"):peek()).toBe("fern")
			t.expect(steps.level("mossholm", "nectar"):peek()).toBe(1)
			t.expect(steps.state("mossholm", "nectar"):peek()).toBe("full")
			t.expect(hasText(sheet, "Nectar: full")).toBe(true)
			t.expect(held:peek()).toBe(gladeSeed.SATCHEL.starlight - 1)
			t.expect(steps.state("mossholm", "dew"):peek()).toBe("empty")
			t.expect(model.complete:peek()).toBe(false)
			press(sheet, "GladeDetail", "Refill")
			t.expect(steps.state("mossholm", "dew"):peek()).toBe("full")
			t.expect(steps.level("mossholm", "dew"):peek()).toBe(1)
			t.expect(hasText(sheet, "Dew: full")).toBe(true)
			t.expect(hasText(w.root, gladeStrings.get("en", "toast.refill", { glade = "Mossholm" }))).toBe(true)
			t.expect(model.complete:peek()).toBe(false)
			pick(w, nectarPicker, gladeSeed.TASK_NECTAR)
			t.expect(model.complete:peek()).toBe(true)
			t.expect(hasText(w.root, "Mossholm is ready. Your visiting wisp has a home.")).toBe(true)
			press(sheet, "Close")
			t.expect(modal(w.screen)).toBeNil()
			local report = w.built.report()
			local pages_ = {
				glades = "Glades",
				favorites = "Glades",
				wisps = "Wisps",
				flora = "Flora",
				keeper = "Keeper",
			}
			for _, id in { "favorites", "wisps", "flora", "keeper", "glades" } do
				press(tabs(w), id)
				t.expect(model.section:peek()).toBe(id)
				t.expect(`{id}: {within(pages(w), id, pages_[id]) ~= nil}`).toBe(`{id}: true`)
				t.expect(model.complete:peek()).toBe(true)
			end
			t.expect(same(w.built.report(), report)).toBe(true)
			w.stop()

			local other = world(glade)
			local supply = other.built.model.supply
			press(pages(other), "glades", "Task")
			local detail = assert(modal(other.screen))
			pick(other, assert(within(detail, "GladeDetail", "Nectar")), gladeSeed.TASK_NECTAR)
			t.expect(supply.nectarOf("mossholm"):peek()).toBe(gladeSeed.TASK_NECTAR)
			t.expect(supply.state("mossholm", "nectar"):peek()).toBe("full")
			t.expect(supply.state("mossholm", "dew"):peek()).toBe("low")
			t.expect(other.built.model.complete:peek()).toBe(false)
			press(detail, "GladeDetail", "Refill")
			t.expect(other.built.model.complete:peek()).toBe(true)
			other.stop()
		end
	)

	t.it("apps-34 boots the showcase scenario from the one reference module and maps the same folders", function()
		bootsOneModule("ref_glade", "p1_glade", "Glade", glade)
	end)
end)

t.describe("Cartwheel", function()
	local LATENCY = 0.25

	local function statsLine(w: World, timeframe: string): string
		local row = w.built.model.stats.topFive(timeframe)[1]
		return `{row.potion.name} · {row.bottles} bottles`
	end

	t.it(
		"apps-35 builds and mounts without an error, opens on the dashboard and releases everything on stop",
		function()
			t.expect(type(cartwheel.build)).toBe("function")
			t.expect(cartwheel.title).toBe("Cartwheel")
			local ok, w = pcall(world, cartwheel)
			t.expect(ok).toBe(true)
			t.expect(w.root.ClassName).toBe("Frame")
			t.expect(w.root.Name).toBe("Cartwheel")
			t.expect(w.built.model.section:peek()).toBe("dashboard")
			t.expect(within(pages(w), "dashboard", "Dashboard") ~= nil).toBe(true)
			t.expect(hasText(pages(w), "Cartwheel")).toBe(true)
			t.expect(modal(w.screen)).toBeNil()
			t.expect(w.engine.heartbeat.count()).toBe(1)
			w.engine.heartbeat.fire(LATENCY)
			w.stop()
			released(w)
		end
	)

	t.it("apps-40 mounts every section through its tab button with its own content", function()
		local w = world(cartwheel)
		local expected = {
			dashboard = { "Dashboard", "TopFive" },
			brews = { "Brews", "BrewList" },
			workbench = { "Workbench", "Potions" },
			ledger = { "Ledger", "LedgerTimeframe" },
			chatter = { "Chatter", "Posts" },
			plazas = { "Plazas", "MarketScene" },
		}
		local count = 0
		for _, id in { "brews", "workbench", "ledger", "chatter", "plazas", "dashboard" } do
			local ok = pcall(press, tabs(w), id)
			t.expect(`{id}: {ok}`).toBe(`{id}: true`)
			t.expect(w.built.model.section:peek()).toBe(id)
			local page = within(pages(w), id, expected[id][1])
			t.expect(`{id}: {page ~= nil}`).toBe(`{id}: true`)
			t.expect(`{id}: {find(page, expected[id][2]) ~= nil}`).toBe(`{id}: true`)
			count += 1
		end
		t.expect(count).toBe(6)
		t.expect(#texts(assert(within(pages(w), "dashboard", "TopFive")))).toBe(5)
		w.stop()
	end)

	t.it("apps-43 collects a seeded Ready brew to Done and carries its bottles into Top Five", function()
		local w = world(cartwheel)
		local model = w.built.model
		local orders, stats = model.orders, model.stats
		local leaders = {}
		for _, row in stats.topFive("today") do
			leaders[row.potion.id] = true
		end
		local brew
		for _, row in orders.brews:peek() do
			local leads = false
			for _, item in row.items do
				leads = leads or leaders[item.potion] == true
			end
			if row.status == "ready" and leads then
				brew = row
				break
			end
		end
		assert(brew, "no seeded ready brew with a Top Five potion")
		local before = stats.totalBottles("today")
		local potions = {}
		for _, item in brew.items do
			potions[item.potion] = (potions[item.potion] or stats.bottlesFor(item.potion, "today")) + item.bottles
		end
		w.built.steps.openBrew(brew.id)
		local sheet = assert(modal(w.screen))
		t.expect(hasText(sheet, "Status: ready")).toBe(true)
		local collect = assert(within(sheet, "Brew", "Collect"))
		t.expect(collect.Interactable).toBe(true)
		collect.Activated.fire()
		w.built.steps.advance(LATENCY)
		t.expect(orders.statusOf(brew.id)).toBe("done")
		t.expect(hasText(sheet, "Status: done")).toBe(true)
		t.expect(collect.Interactable).toBe(false)
		t.expect(stats.dump().collected).toBe(brew.bottles)
		t.expect(stats.totalBottles("today")).toBe(before + brew.bottles)
		for potion, bottles in potions do
			t.expect(stats.bottlesFor(potion, "today")).toBe(bottles)
		end
		local alert = assert(find(w.screen, "AlertPanel"))
		press(alert, "done")
		local dashboard = assert(within(pages(w), "dashboard", "Dashboard"))
		t.expect(hasText(dashboard, `{orders.count()} brews · {brew.bottles} bottles collected`)).toBe(true)
		local shown = texts(assert(find(dashboard, "TopFive")))
		local top = stats.topFive("today")
		t.expect(#shown).toBe(#top)
		for index, row in top do
			t.expect(shown[index]).toBe(`{row.potion.name} · {row.bottles} bottles`)
		end
		local reached = 0
		for _, row in top do
			if potions[row.potion.id] then
				reached += 1
				t.expect(row.bottles).toBe(potions[row.potion.id])
			end
		end
		t.expect(reached > 0).toBe(true)
		w.stop()
	end)

	t.it(
		"apps-51 resolves the unwired timeframe picker as a menu on touch and pointer and a strip on gamepad",
		function()
			local w = world(cartwheel)
			local E, V2 = w.engine.types.Enum, w.engine.types.Vector2
			local picker = assert(within(pages(w), "dashboard", "Timeframe"))
			t.expect(find(picker, "Trigger")).toBeNil()
			t.expect(find(picker, "week") ~= nil).toBe(true)
			picker.AbsoluteSize = V2.new(300, 44)
			w.input.PreferredInput = E.PreferredInput.Touch
			t.expect(find(picker, "Trigger") ~= nil).toBe(true)
			t.expect(find(picker, "week")).toBeNil()
			pick(w, picker, "month")
			local top = statsLine(w, "month")
			t.expect(texts(assert(within(pages(w), "dashboard", "TopFive")))[1]).toBe(top)
			w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
			t.expect(find(picker, "Trigger") ~= nil).toBe(true)
			t.expect(find(picker, "Trigger").Text).toBe("Month")
			w.input.PreferredInput = E.PreferredInput.Gamepad
			t.expect(find(picker, "Trigger")).toBeNil()
			local week = assert(find(picker, "week"))
			t.expect(find(picker, "month") ~= nil).toBe(true)
			t.expect(within(pages(w), "dashboard", "Timeframe")).toBe(picker)
			t.expect(texts(assert(within(pages(w), "dashboard", "TopFive")))[1]).toBe(top)
			week.Activated.fire()
			t.expect(texts(assert(within(pages(w), "dashboard", "TopFive")))[1]).toBe(statsLine(w, "week"))
			w.input.PreferredInput = E.PreferredInput.Touch
			t.expect(find(picker, "Trigger").Text).toBe("Week")
			picker.AbsoluteSize = V2.new(600, 44)
			t.expect(find(picker, "Trigger")).toBeNil()
			t.expect(find(picker, "week") ~= nil).toBe(true)
			w.stop()
		end
	)
end)

t.describe("Sipworks", function()
	local CONFIRMED = "Your order is confirmed. Your stamp is on the card."
	local REFUSED = "The counter is closed. Your stamps are unchanged; try again."

	local function recipeColumn(sheet: any): any
		for _, node in sheet:GetDescendants() do
			if node.Name == "Recipe" and node.ClassName == "Frame" then
				return node
			end
		end
		return nil
	end

	local function resetServices(w: World)
		local model = w.built.model
		model.favorites.reset()
		model.rewards.reset()
		model.order.reset()
		model.unlock.reset()
		model.task.reset()
	end

	local function stampsLine(n: number): string
		return `{n} stamps · ten stamps earn a free pour`
	end

	t.it("apps-69 builds and mounts without an error with the whole menu visible and releases everything", function()
		t.expect(type(sipworks.build)).toBe("function")
		t.expect(sipworks.title).toBe("Sipworks")
		local ok, w = pcall(world, sipworks)
		t.expect(ok).toBe(true)
		t.expect(w.root.ClassName).toBe("Frame")
		t.expect(w.root.Name).toBe("Sipworks")
		t.expect(w.built.model.section:peek()).toBe("menu")
		local shown = rows(assert(within(pages(w), "menu", "Blends")))
		t.expect(#shown).toBe(#w.built.model.catalog.blends)
		table.sort(shown)
		local all = {}
		for _, blend in w.built.model.catalog.blends do
			table.insert(all, blend.id)
		end
		table.sort(all)
		t.expect(table.concat(shown, ",")).toBe(table.concat(all, ","))
		t.expect(w.engine.heartbeat.count()).toBe(1)
		w.engine.heartbeat.fire(0.1)
		w.stop()
		released(w)
	end)

	t.it(
		"apps-77 shows the pending label, refuses a second press, explains the rejection and reports the pour ready",
		function()
			local w = world(sipworks)
			local model, steps = w.built.model, w.built.steps
			press(pages(w), "menu", "Blends", "lantern-oolong", "Open")
			local sheet = assert(modal(w.screen))
			local order = assert(within(sheet, "BlendDetail", "Order"))
			t.expect(order.Text).toBe("Order · " .. model.order.price)
			order.Activated.fire()
			t.expect(model.order.status:peek()).toBe("pending")
			t.expect(model.order.blendId:peek()).toBe("lantern-oolong")
			t.expect(order.Text).toBe("Confirming…")
			t.expect(order.Interactable).toBe(false)
			t.expect(steps.order("lantern-oolong", "paid")).toBe(false)
			steps.advance(sipOrder.RESOLVE_AFTER - 0.1)
			t.expect(model.order.status:peek()).toBe("pending")
			steps.advance(0.2)
			t.expect(model.order.attempts()).toBe(1)
			t.expect(model.order.status:peek()).toBe("rejected")
			t.expect(model.order.reason:peek()).toBe("counterClosed")
			t.expect(hasText(w.root, REFUSED)).toBe(true)
			t.expect(order.Text).toBe("Order · " .. model.order.price)
			t.expect(order.Interactable).toBe(true)
			t.expect(model.rewards.unspent()).toBe(9)
			order.Activated.fire()
			t.expect(order.Text).toBe("Confirming…")
			steps.advance(sipOrder.RESOLVE_AFTER + 0.1)
			t.expect(model.order.status:peek()).toBe("confirmed")
			t.expect(hasText(w.root, CONFIRMED)).toBe(true)
			t.expect(model.order.isReady:peek()).toBe(false)
			t.expect(order.Interactable).toBe(true)
			steps.advance(sipOrder.READY_AFTER - 0.2)
			t.expect(model.order.isReady:peek()).toBe(false)
			t.expect(hasText(w.root, CONFIRMED)).toBe(true)
			steps.advance(0.3)
			t.expect(model.order.isReady:peek()).toBe(true)
			t.expect(hasText(w.root, "Your pour is ready.")).toBe(true)
			t.expect(model.order.attempts()).toBe(2)
			w.stop()
		end
	)

	t.it("apps-79 earns one stamp per confirmed order and redeems a flat ten with the redeem verb", function()
		local w = world(sipworks)
		local model, steps = w.built.model, w.built.steps
		local rewards = model.rewards
		press(tabs(w), "rewards")
		local page = assert(within(pages(w), "rewards", "Rewards"))
		local redeem = assert(find(page, "Redeem"))
		t.expect(redeem.Text).toBe("Redeem a free " .. model.catalog.blend(sipTask.FREE_POUR_BLEND).title)
		t.expect(hasText(page, stampsLine(9))).toBe(true)
		t.expect(redeem.Interactable).toBe(false)
		t.expect(steps.redeem()).toBe(false)
		t.expect(model.order.status:peek()).toBe("idle")
		local earned = {}
		for _ = 1, 3 do
			steps.order("amber-harvest", "paid")
			steps.advance(sipOrder.RESOLVE_AFTER + 0.1)
			table.insert(earned, rewards.earned:peek())
		end
		t.expect(table.concat(earned, ",")).toBe("9,10,11")
		t.expect(rewards.spent:peek()).toBe(0)
		t.expect(hasText(page, stampsLine(11))).toBe(true)
		t.expect(redeem.Interactable).toBe(true)
		t.expect(within(pages(w), "rewards", "Rewards")).toBe(page)
		redeem.Activated.fire()
		t.expect(model.order.mode:peek()).toBe("redeem")
		t.expect(model.order.blendId:peek()).toBe(sipTask.FREE_POUR_BLEND)
		t.expect(redeem.Interactable).toBe(false)
		steps.advance(sipOrder.RESOLVE_AFTER + 0.1)
		t.expect(rewards.spent:peek()).toBe(10)
		t.expect(rewards.earned:peek()).toBe(11)
		t.expect(rewards.unspent()).toBe(1)
		t.expect(hasText(page, stampsLine(1))).toBe(true)
		t.expect(redeem.Interactable).toBe(false)
		t.expect(hasText(w.root, sipStrings.byLocale.en["order.redeemed"])).toBe(true)
		w.stop()
	end)

	t.it("apps-81 keeps locked recipes behind the Blend Book until the second purchase confirms", function()
		local w = world(sipworks)
		local model, steps = w.built.model, w.built.steps
		local locked = model.catalog.blend("lantern-oolong")
		t.expect(locked.free == true).toBe(false)
		press(tabs(w), "book")
		local book = assert(within(pages(w), "book", "BlendBook"))
		local listed = rows(assert(find(book, "Recipes")))
		t.expect(#listed).toBe(0)
		local buttons = {}
		for _, child in assert(find(book, "Recipes")):GetChildren() do
			if child.ClassName == "TextButton" then
				table.insert(buttons, child.Name)
			end
		end
		t.expect(#buttons).toBe(#model.catalog.blends)
		local function openRow(): any
			press(book, "Recipes", "lantern-oolong")
			local sheet = assert(modal(w.screen))
			t.expect(model.selected:peek()).toBe("lantern-oolong")
			return sheet
		end
		local sheet = openRow()
		t.expect(recipeColumn(sheet)).toBeNil()
		t.expect(within(sheet, "Unlock") ~= nil).toBe(true)
		t.expect(within(sheet, "Unlock", "Buy")).toBeNil()
		press(sheet, "Close")
		steps.advance(sipUnlock.AVAILABLE_AFTER)
		local buy = assert(find(book, "Buy"))
		t.expect(buy.Interactable).toBe(true)
		buy.Activated.fire()
		t.expect(model.unlock.status:peek()).toBe("pending")
		t.expect(buy.Interactable).toBe(false)
		steps.advance(sipUnlock.RESOLVE_AFTER + 0.1)
		t.expect(model.unlock.unlocked:peek()).toBe(false)
		t.expect(hasText(w.root, "The purchase was declined. Try again.")).toBe(true)
		t.expect(find(book, "Buy")).toBe(buy)
		sheet = openRow()
		t.expect(recipeColumn(sheet)).toBeNil()
		t.expect(within(sheet, "Unlock", "Buy") ~= nil).toBe(true)
		press(sheet, "Close")
		buy.Activated.fire()
		steps.advance(sipUnlock.RESOLVE_AFTER + 0.1)
		t.expect(model.unlock.unlocked:peek()).toBe(true)
		t.expect(hasText(w.root, "Your Blend Book is unlocked.")).toBe(true)
		t.expect(find(book, "Buy")).toBeNil()
		t.expect(buy.isDestroyed()).toBe(true)
		sheet = openRow()
		local recipe = assert(recipeColumn(sheet))
		t.expect(find(sheet, "Unlock")).toBeNil()
		for _, measure in model.catalog.recipeMeasures("lantern-oolong") do
			local toggle = assert(find(recipe, measure.botanicalId))
			t.expect(toggle.Text).toBe(
				model.catalog.botanical(measure.botanicalId).name
					.. " · "
					.. model.i18n.measureAt("en", measure.value, measure.unit)
			)
		end
		w.stop()
	end)

	t.it("apps-82 mounts no Blend Book page Buy button until the price loads", function()
		local w = world(sipworks)
		local model, steps = w.built.model, w.built.steps
		press(tabs(w), "book")
		local book = assert(within(pages(w), "book", "BlendBook"))
		t.expect(model.unlock.availability:peek()).toBe("pending")
		t.expect(find(book, "Buy")).toBeNil()
		t.expect(steps.buyBook()).toBe(false)
		t.expect(model.unlock.status:peek()).toBe("idle")
		steps.advance(sipUnlock.AVAILABLE_AFTER - 0.1)
		t.expect(find(book, "Buy")).toBeNil()
		t.expect(model.unlock.attempts()).toBe(0)
		steps.advance(0.1)
		t.expect(model.unlock.availability:peek()).toBe("available")
		local buy = assert(find(book, "Buy"))
		t.expect(buy.Interactable).toBe(true)
		t.expect(buy.Text).toBe("Unlock · " .. model.unlock.product.price)
		buy.Activated.fire()
		t.expect(model.unlock.status:peek()).toBe("pending")
		t.expect(buy.Interactable).toBe(false)
		steps.advance(sipUnlock.RESOLVE_AFTER + 0.1)
		t.expect(model.unlock.attempts()).toBe(1)
		t.expect(model.unlock.status:peek()).toBe("rejected")
		w.stop()
	end)

	t.it("apps-85 returns every service to its seeded report on reset and replays the loop identically", function()
		local w = world(sipworks)
		local steps = w.built.steps
		local function drive()
			steps.favorite("tidepool")
			steps.order("amber-harvest", "paid")
			steps.advance(0.7)
			steps.order("amber-harvest", "paid")
			steps.advance(0.7)
			steps.redeem()
			steps.advance(5)
			steps.buyBook()
			steps.advance(0.7)
			steps.buyBook()
			steps.advance(0.7)
		end
		local fresh = w.built.report()
		drive()
		local played = w.built.report()
		t.expect(same(played, fresh)).toBe(false)
		t.expect(played.task).toBe("done/0/true/true/false")
		resetServices(w)
		t.expect(same(w.built.report(), fresh)).toBe(true)
		t.expect(w.built.model.order.attempts()).toBe(0)
		t.expect(w.built.model.unlock.attempts()).toBe(0)
		steps.advance(1)
		drive()
		t.expect(same(w.built.report(), played)).toBe(true)
		w.stop()
	end)

	t.it(
		"apps-93 opens one stamp short, explains a refusal, earns the free pour, completes it and keeps every destination",
		function()
			local w = world(sipworks)
			local model, steps = w.built.model, w.built.steps
			local menu = assert(within(pages(w), "menu", "Menu"))
			local task = assert(find(menu, "Task"))
			t.expect(hasText(menu, "Today's order: order · 9 of 10 stamps")).toBe(true)
			t.expect(task.Text).toBe("Order Amber Harvest")
			t.expect(model.rewards.unspent()).toBe(9)
			task.Activated.fire()
			t.expect(model.task.phase:peek()).toBe("placing")
			t.expect(task.Interactable).toBe(false)
			steps.advance(sipOrder.RESOLVE_AFTER + 0.1)
			t.expect(hasText(menu, "Today's order: rejected · 9 of 10 stamps")).toBe(true)
			t.expect(hasText(w.root, REFUSED)).toBe(true)
			t.expect(model.rewards.unspent()).toBe(9)
			t.expect(model.task.served:peek()).toBe(false)
			t.expect(task.Text).toBe("Order Amber Harvest")
			t.expect(task.Interactable).toBe(true)
			task.Activated.fire()
			t.expect(model.task.refused:peek()).toBe(false)
			steps.advance(sipOrder.RESOLVE_AFTER + 0.1)
			t.expect(hasText(menu, "Today's order: redeem · 10 of 10 stamps")).toBe(true)
			t.expect(model.task.served:peek()).toBe(true)
			t.expect(task.Text).toBe("Redeem a Mistral Mint")
			t.expect(model.task.ctaBlendId:peek()).toBe(sipTask.FREE_POUR_BLEND)
			task.Activated.fire()
			t.expect(model.order.mode:peek()).toBe("redeem")
			steps.advance(sipOrder.RESOLVE_AFTER + 0.1)
			t.expect(model.task.phase:peek()).toBe("done")
			t.expect(model.task.redeemed:peek()).toBe(true)
			t.expect(hasText(menu, "Today's order: done · 0 of 10 stamps")).toBe(true)
			t.expect(hasText(w.root, sipStrings.byLocale.en["order.redeemed"])).toBe(true)
			t.expect(task.Interactable).toBe(false)
			local expected = { menu = "Menu", favorites = "Menu", rewards = "Rewards", book = "BlendBook" }
			for _, id in { "favorites", "rewards", "book", "menu" } do
				press(tabs(w), id)
				t.expect(model.section:peek()).toBe(id)
				t.expect(`{id}: {within(pages(w), id, expected[id]) ~= nil}`).toBe(`{id}: true`)
			end
			t.expect(#rows(assert(within(pages(w), "menu", "Blends")))).toBe(#model.catalog.blends)
			t.expect(within(pages(w), "menu", "Search") ~= nil).toBe(true)
			t.expect(model.task.phase:peek()).toBe("done")
			w.stop()
		end
	)

	t.it(
		"apps-94 opens the named task blend through its own row and resets every observable after the free pour",
		function()
			local w = world(sipworks)
			local model, steps = w.built.model, w.built.steps
			local fresh = w.built.report()
			local task = assert(within(pages(w), "menu", "Menu", "Task"))
			local open = assert(within(pages(w), "menu", "Blends", sipTask.FIRST_BLEND, "Open"))
			t.expect(task.Text).toBe("Order " .. open.Text)
			open.Activated.fire()
			t.expect(model.selected:peek()).toBe(sipTask.FIRST_BLEND)
			local sheet = assert(modal(w.screen))
			t.expect(hasText(sheet, open.Text)).toBe(true)
			press(sheet, "BlendDetail", "Order")
			t.expect(model.order.blendId:peek()).toBe(sipTask.FIRST_BLEND)
			t.expect(model.order.mode:peek()).toBe("paid")
			steps.advance(0.7)
			press(sheet, "BlendDetail", "Order")
			steps.advance(0.7)
			press(sheet, "Close")
			t.expect(modal(w.screen)).toBeNil()
			task.Activated.fire()
			steps.advance(0.7)
			t.expect(model.task.phase:peek()).toBe("done")
			t.expect(task.Interactable).toBe(false)
			resetServices(w)
			t.expect(same(w.built.report(), fresh)).toBe(true)
			t.expect(task.Text).toBe("Order " .. open.Text)
			t.expect(task.Interactable).toBe(true)
			t.expect(hasText(pages(w), "Today's order: order · 9 of 10 stamps")).toBe(true)
			w.stop()
		end
	)

	t.it("apps-97 boots the showcase scenario from the one reference module and maps the same folders", function()
		bootsOneModule("ref_sipworks", "p3_sipworks", "Sipworks", sipworks)
	end)
end)

t.describe("Foyer", function()
	local function sectionTiles(w: World): { [string]: string }
		local out = {}
		local list = assert(within(pages(w), "home", "Sections"))
		for _, id in rows(list) do
			out[id] = table.concat(rows(assert(within(list, id, "Tiles"))), ",")
		end
		return out
	end

	local function seeded(page: number): { [string]: string }
		local out = {}
		for _, section in foyerSeed.sections(page) do
			local ids = {}
			for _, tile in section.tiles do
				table.insert(ids, tile.id)
			end
			out[section.id] = table.concat(ids, ",")
		end
		return out
	end

	t.it("apps-99 mounts the home body with all four sections and their tiles without an error", function()
		t.expect(type(foyer.build)).toBe("function")
		local ok, w = pcall(world, foyer)
		t.expect(ok).toBe(true)
		t.expect(w.root.ClassName).toBe("Frame")
		t.expect(w.root.Name).toBe("Foyer")
		t.expect(w.built.model.destination:peek()).toBe("home")
		local list = assert(within(pages(w), "home", "Sections"))
		t.expect(table.concat(rows(list), ",")).toBe("picked,continue,new,friends")
		for _, id in rows(list) do
			t.expect(hasText(assert(find(list, id)), foyerStrings.get("en", "section." .. id))).toBe(true)
		end
		t.expect(same(sectionTiles(w), seeded(0))).toBe(true)
		local feed = assert(within(pages(w), "home", "FeedSelection"))
		t.expect(find(feed, "forYou") ~= nil).toBe(true)
		t.expect(find(feed, "charts") ~= nil).toBe(true)
		press(tabs(w), "crews")
		local friends = rows(assert(within(pages(w), "crews", "Friends")))
		local expected = {}
		for _, friend in foyerSeed.friends do
			table.insert(expected, friend.id)
		end
		t.expect(table.concat(friends, ",")).toBe(table.concat(expected, ","))
		w.stop()
		released(w)
	end)

	local function matching(query: string): string
		local out, seen = {}, {}
		for _, section in foyerSeed.sections(0) do
			for _, tile in section.tiles do
				local hit = string.find(string.lower(tile.title), query, 1, true)
					or string.find(string.lower(tile.creator), query, 1, true)
				if not seen[tile.id] and hit then
					table.insert(out, tile.id)
				end
				seen[tile.id] = true
			end
		end
		return table.concat(out, ",")
	end

	t.it("apps-103 filters by title and creator, says when nothing matches and restores the feed on clear", function()
		local w = world(foyer)
		local home = assert(within(pages(w), "home", "Feed"))
		local list = assert(find(home, "Sections"))
		type_(home, "Search", "moss")
		t.expect(w.built.model.query:peek()).toBe("moss")
		t.expect(find(home, "Sections")).toBeNil()
		t.expect(list.isDestroyed()).toBe(true)
		local results = assert(find(home, "SearchResults"))
		t.expect(table.concat(rows(results), ",")).toBe(matching("moss"))
		t.expect(table.concat(rows(results), ",")).toBe("moss-kingdom")
		type_(home, "Search", "LATCHKEY")
		results = assert(find(home, "SearchResults"))
		t.expect(table.concat(rows(results), ",")).toBe(matching("latchkey"))
		t.expect(table.find(rows(results), "signal-lost") ~= nil).toBe(true)
		t.expect(#rows(results) >= 2).toBe(true)
		t.expect(hasText(results, foyerStrings.get("en", "search.none"))).toBe(false)
		type_(home, "Search", "zzzz")
		results = assert(find(home, "SearchResults"))
		t.expect(#rows(results)).toBe(0)
		t.expect(hasText(results, foyerStrings.get("en", "search.none"))).toBe(true)
		type_(home, "Search", "")
		t.expect(find(home, "SearchResults")).toBeNil()
		t.expect(table.concat(rows(assert(find(home, "Sections"))), ",")).toBe("picked,continue,new,friends")
		t.expect(same(sectionTiles(w), seeded(0))).toBe(true)
		w.stop()
	end)

	t.it("apps-106 disables Refresh while pending, reseeds on confirm and keeps the feed on a rejection", function()
		local w = world(foyer)
		local steps, services = w.built.steps, w.built.model.services
		local refresh = assert(within(pages(w), "home", "Refresh"))
		t.expect(refresh.Interactable).toBe(true)
		refresh.Activated.fire()
		t.expect(services.refreshStatus:peek()).toBe("pending")
		t.expect(refresh.Interactable).toBe(false)
		refresh.Activated.fire()
		t.expect(services.pendingSettles()).toBe(1)
		t.expect(same(sectionTiles(w), seeded(0))).toBe(true)
		steps.settle()
		t.expect(services.refreshStatus:peek()).toBe("confirmed")
		t.expect(w.built.report().page).toBe(1)
		t.expect(refresh.Interactable).toBe(true)
		t.expect(same(sectionTiles(w), seeded(1))).toBe(true)
		t.expect(same(seeded(1), seeded(0))).toBe(false)
		t.expect(hasText(w.root, foyerStrings.get("en", "toast.refreshed"))).toBe(true)
		steps.reject("refresh", "err.feed.refresh.offline")
		refresh.Activated.fire()
		t.expect(refresh.Interactable).toBe(false)
		steps.settle()
		t.expect(services.refreshStatus:peek()).toBe("rejected")
		t.expect(w.built.report().page).toBe(1)
		t.expect(refresh.Interactable).toBe(true)
		t.expect(same(sectionTiles(w), seeded(1))).toBe(true)
		t.expect(hasText(w.root, foyerStrings.get("en", "err.feed.refresh.offline"))).toBe(true)
		w.stop()
	end)

	t.it("apps-107 presents the tile detail, visits into Keep playing and dismisses the detail", function()
		local w = world(foyer)
		local steps, services = w.built.steps, w.built.model.services
		t.expect(modal(w.screen)).toBeNil()
		press(pages(w), "home", "Sections", "picked", "moss-kingdom", "Open")
		local sheet = assert(modal(w.screen))
		local tile = services.tileById("moss-kingdom")
		for _, line in { tile.title, tile.creator, tile.blurb, `{tile.approval}% approval` } do
			t.expect(`{line}: {hasText(sheet, line)}`).toBe(`{line}: true`)
		end
		local visit = assert(within(sheet, "World", "Visit"))
		visit.Activated.fire()
		t.expect(services.visitStatus:peek()).toBe("pending")
		t.expect(visit.Interactable).toBe(false)
		t.expect(visit.Text).toBe(foyerStrings.get("en", "detail.visiting"))
		t.expect((next(w.built.report().continued))).toBeNil()
		steps.settle()
		t.expect(services.visitStatus:peek()).toBe("confirmed")
		t.expect(w.built.report().continued["moss-kingdom"]).toBe(true)
		t.expect(visit.Interactable).toBe(true)
		t.expect(visit.Text).toBe(foyerStrings.get("en", "detail.visit"))
		t.expect(hasText(w.root, foyerStrings.get("en", "toast.visited"))).toBe(true)
		press(sheet, "Close")
		t.expect(modal(w.screen)).toBeNil()
		t.expect(visit.isDestroyed()).toBe(true)
		t.expect(w.built.report().continued["moss-kingdom"]).toBe(true)
		press(pages(w), "home", "Sections", "picked", "moss-kingdom", "Open")
		t.expect(modal(w.screen) ~= nil).toBe(true)
		w.stop()
	end)
end)

t.describe("Documentation and tooling", function()
	local function snippet(file: string, index: number): string
		local found = 0
		for code in string.gmatch(fs.readFile(file), "```luau\n(.-)```") do
			found += 1
			if found == index then
				return code
			end
		end
		error(`no snippet {index} in {file}`)
	end

	local function button(node: any, text: string): any
		for _, child in node:GetDescendants() do
			if child.ClassName == "TextButton" and child.Text == text then
				return child
			end
		end
		return nil
	end

	local function run(code: string, suffix: string): (any, any, any, any, any)
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local facade = table.clone(Facet) :: any
		facade.Roblox = table.clone(Facet.Roblox)
		facade.themes = table.clone(Facet.themes)
		facade.Roblox.createRuntime = function()
			return runtime
		end
		facade.controls = function(rt, options)
			local settings = table.clone(options or {})
			settings.types = engine.types
			return Facet.controls(rt, settings)
		end
		local sheets = {}
		facade.themes.createStyleSheet = function(rt, package, options)
			local settings = table.clone(options or {})
			settings.types = engine.types
			local sheet = Facet.themes.createStyleSheet(rt, package, settings)
			table.insert(sheets, sheet)
			return sheet
		end
		local playerGui = engine.new("PlayerGui")
		facade.app = function(options)
			local settings = table.clone(options or {})
			settings.types = engine.types
			settings.parent = settings.parent or playerGui
			return Facet.bind(Facet.Compose, facade.Roblox).app(settings)
		end
		local host = engine.new("ScreenGui")
		local destroying = engineLib.new().heartbeat
		local env = table.clone(engine.types) :: any
		env.Facet = facade
		env.Compose = Compose
		env.Host = runtime.constructors
		env.UI = facade.controls(runtime)
		env.script = { Destroying = destroying }
		env.require = function()
			return facade
		end
		env.game = {
			ReplicatedStorage = {
				WaitForChild = function()
					return "Facet"
				end,
			},
			Players = {
				LocalPlayer = {
					WaitForChild = function()
						return playerGui
					end,
				},
			},
		}
		local bindings = {}
		for key in env do
			table.insert(bindings, `local {key}=env[{string.format("%q", key)}]`)
		end
		local baseline = engine.census()
		local factory =
			luau.load("return function(env)\n" .. table.concat(bindings, "\n") .. "\n" .. code .. suffix .. "\nend")()
		return factory,
			env,
			engine,
			runtime,
			{ baseline = baseline, playerGui = playerGui, host = host, sheets = sheets }
	end

	t.it(
		"mech1-76 runs the README and getting-started counters and closes every resource on script teardown",
		function()
			for _, file in { "README.md", "docs/guide/03-getting-started.md" } do
				local factory, env, engine, _, state = run(snippet(file, 1), "")
				factory(env)
				local counter = assert(find(state.playerGui, "Counter"), `{file}: no Counter`)
				t.expect(counter.ClassName).toBe("ScreenGui")
				t.expect(counter.ResetOnSpawn).toBe(false)
				local sheets = {}
				for _, node in state.playerGui:GetDescendants() do
					if node.ClassName == "StyleSheet" then
						table.insert(sheets, node)
					end
				end
				t.expect(#state.sheets + #sheets).toBe(1)
				local sheet = state.sheets[1] or sheets[1]
				t.expect(sheet.Parent).toBe(counter)
				t.expect(counter:FindFirstChildWhichIsA("StyleLink").StyleSheet).toBe(sheet)
				t.expect(`{file}: {hasText(counter, "Clicked 0 times")}`).toBe(`{file}: true`)
				local add = assert(button(counter, "Add one"))
				add.Activated.fire()
				add.Activated.fire()
				t.expect(`{file}: {hasText(counter, "Clicked 2 times")}`).toBe(`{file}: true`)
				t.expect(env.script.Destroying.count()).toBe(1)
				env.script.Destroying.fire()
				t.expect(counter.isDestroyed()).toBe(true)
				t.expect(sheet.isDestroyed()).toBe(true)
				t.expect(engine.census().live).toBe(state.baseline.live)
				t.expect(engine.census().connections).toBe(state.baseline.connections)
			end
		end
	)

	t.it("mech1-76 runs both component guide snippets and releases their Compose state and nodes", function()
		local factory, env, engine, runtime, state =
			run(snippet("docs/guide/15-components.md", 1), "\nreturn Settings()")
		local stop, root = runtime.mount(function()
			return factory(env)
		end, state.host)
		local toggle = assert(button(root, "Notifications"))
		t.expect(hasText(root, "Notifications are on")).toBe(true)
		toggle.Activated.fire()
		t.expect(hasText(root, "Notifications are off")).toBe(true)
		toggle.Activated.fire()
		t.expect(hasText(root, "Notifications are on")).toBe(true)
		stop()
		t.expect(root.isDestroyed()).toBe(true)
		runtime:dispose()
		t.expect(engine.census().live).toBe(state.baseline.live)
		t.expect(engine.census().connections).toBe(state.baseline.connections)

		local detailFactory, detailEnv, detailEngine, detailRuntime, detailState =
			run(snippet("docs/guide/15-components.md", 2), "")
		local stopDetail, frame = detailRuntime.mount(function()
			return detailFactory(detailEnv)
		end, detailState.host)
		local show = assert(button(frame, "Show details"))
		t.expect(hasText(frame, "Changes are saved to this session.")).toBe(false)
		show.Activated.fire()
		local label
		for _, child in frame:GetDescendants() do
			if child.ClassName == "TextLabel" and child.Text == "Changes are saved to this session." then
				label = child
			end
		end
		assert(label, "details did not appear")
		show.Activated.fire()
		t.expect(label.isDestroyed()).toBe(true)
		t.expect(hasText(frame, "Changes are saved to this session.")).toBe(false)
		show.Activated.fire()
		t.expect(hasText(frame, "Changes are saved to this session.")).toBe(true)
		stopDetail()
		detailRuntime:dispose()
		t.expect(frame.isDestroyed()).toBe(true)
		t.expect(detailEngine.census().live).toBe(detailState.baseline.live)
		t.expect(detailEngine.census().connections).toBe(detailState.baseline.connections)
	end)

	t.it("apps2-78 rejects unsafe names and unknown kinds and stamps formatter-clean code for a long name", function()
		for _, name in { "Bad Name/../x", "PopupButton", "popupButton", "1probe", "_probe", "a-b", "", "x/../y", "a b" } do
			t.expect(`{name}: {pcall(scaffold.plan, "control", name)}`).toBe(`{name}: false`)
		end
		for _, kind in { "wizard", "adapter", "primitive", "target", "mode", "Control" } do
			t.expect(`{kind}: {pcall(scaffold.plan, kind, "probe")}`).toBe(`{kind}: false`)
		end
		local plan = scaffold.plan("control", "extremely_long_probe_name_for_width")
		t.expect(plan.files[1].path).toBe("src/ui/extremely_long_probe_name_for_width.luau")
		t.expect(string.find(plan.files[1].content, "UI.ExtremelyLongProbeNameForWidth =", 1, true) ~= nil).toBe(true)
		local sources = { plan.files[1].content }
		for _, edit in plan.edits do
			local shipped = fs.readFile(edit.path)
			local _, anchors = string.gsub(shipped, string.gsub(edit.before, "%p", "%%%0"), "")
			t.expect(`{edit.path}: {anchors}`).toBe(`{edit.path}: 1`)
			local applied = scaffold.applyEdit(shipped, edit)
			t.expect(string.find(applied, edit.insert, 1, true) ~= nil).toBe(true)
			t.expect(scaffold.applyEdit(applied, edit)).toBe(applied)
			table.insert(sources, applied)
		end
		for index, source in sources do
			local result = process.exec("stylua", { "--check", "-" }, { stdio = { stdin = source } })
			t.expect(`{index}: {result.ok}`).toBe(`{index}: true`)
			for number, line in string.split(source, "\n") do
				local width = #line + select(2, string.gsub(line, "\t", "")) * 3
				t.expect(`{index}:{number} {width <= 120}`).toBe(`{index}:{number} true`)
			end
		end
		local targets = {}
		for _, edit in plan.edits do
			targets[edit.path] = fs.readFile(edit.path)
		end
		local refused = process.exec("lune", { "run", "tools/lune/scaffold_cli", "control", "collections" })
		t.expect(refused.ok).toBe(false)
		t.expect(
			string.find(refused.stderr .. refused.stdout, "Refusing to overwrite src/ui/collections.luau", 1, true)
				~= nil
		)
			.toBe(true)
		local unsafe = process.exec("lune", { "run", "tools/lune/scaffold_cli", "control", "Bad/../name" })
		t.expect(unsafe.ok).toBe(false)
		for path, before in targets do
			t.expect(`{path}: {fs.readFile(path) == before}`).toBe(`{path}: true`)
		end
		t.expect(fs.isFile("src/ui/Bad/../name.luau")).toBe(false)
	end)

	t.it(
		"paint-139 reports a dead link or heading in each theme and skinning document and passes the shipped ones",
		function()
			local documents = {
				"docs/guide/05-styling.md",
				"docs/guide/09-custom-themes.md",
				"docs/guide/10-rich-skinning.md",
				"docs/guide/13-theme-catalog.md",
				"docs/extending/new-theme.md",
				"docs/extending/skinned-control.md",
			}
			local clean = checkLinks.check()
			for _, document in documents do
				t.expect(fs.isFile(document)).toBe(true)
				for _, problem in clean.problems do
					t.expect((string.find(problem, document, 1, true))).toBeNil()
				end
				local source = fs.readFile(document)
				local planted = checkLinks.check({
					fileOverrides = {
						[document] = source
							.. "\n\nSee [gone](../guide/99-nonexistent.md) and [nowhere](#no-such-heading-here).\n",
					},
				})
				t.expect(`{document}: {planted.ok}`).toBe(`{document}: false`)
				local dead, heading = 0, 0
				for _, problem in planted.problems do
					if string.find(problem, document .. ":", 1, true) == 1 then
						if string.find(problem, "docs/guide/99-nonexistent.md", 1, true) then
							dead += 1
						elseif string.find(problem, "#no-such-heading-here", 1, true) then
							heading += 1
						end
					end
				end
				t.expect(`{document}: {dead} {heading}`).toBe(`{document}: 1 1`)
				t.expect(#planted.problems).toBe(#clean.problems + 2)
			end
		end
	)
end)
