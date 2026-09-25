--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local glade = require("../examples/reference/p1_glade")
local gladeSeed = require("../examples/reference/p1_glade/content/seed")
local gladeStrings = require("../examples/reference/p1_glade/content/strings")
local cartwheel = require("../examples/reference/p2_cartwheel")
local cartData = require("../examples/reference/p2_cartwheel/content/data")
local cartArt = require("../examples/reference/p2_cartwheel/content/art")
local cartStrings = require("../examples/reference/p2_cartwheel/content/strings")
local cartOrders = require("../examples/reference/p2_cartwheel/services/order_service")
local cartClock = require("../examples/reference/p2_cartwheel/services/clock")
local cartAmbient = require("../examples/reference/p2_cartwheel/services/ambient_service")
local sipworks = require("../examples/reference/p3_sipworks")
local sipStrings = require("../examples/reference/p3_sipworks/content/strings")
local sipArt = require("../examples/reference/p3_sipworks/content/art")
local sipBlends = require("../examples/reference/p3_sipworks/content/blends")
local sipFavorites = require("../examples/reference/p3_sipworks/services/favorites")
local sipTask = require("../examples/reference/p3_sipworks/services/task")
local foyer = require("../examples/reference/p4_foyer")
local foyerSeed = require("../examples/reference/p4_foyer/content/seed")
local foyerStrings = require("../examples/reference/p4_foyer/content/strings")
local galleryAssets = require("../examples/gallery/examples/assets")
local fs = require("@lune/fs")
local gallery = require("../examples/gallery/client/screen")
local catalogue = require("../examples/gallery/client/demo_picker")
local process = require("@lune/process")
local scaffold = require("../tools/lune/scaffold")
local outpost = require("../examples/gallery/examples/outpost_terminal")
local nativeApp = require("../bench/native_app")
local perfLab = require("../examples/performance/lab/perf_lab")
local perfModules = {
	sensory = require("../examples/performance/lab/sensory"),
	dataset = require("../examples/performance/lab/dataset"),
	rows = require("../examples/performance/lab/rows"),
	capture = require("../examples/performance/lab/capture"),
	workloads = require("../examples/performance/lab/workloads"),
}
local playlistExample = require("../examples/gallery/examples/02_playlist_table")
local quickActions = require("../examples/gallery/scenarios/radial_menu")
local studioTree = require("../tools/lune/lib/studio_tree")
local themePackages = require("../tools/lune/theme_packages")
local ornateGauge = require("../examples/themes/ornate_gauge")
local customControl = require("../examples/themes/custom_control")
local fantasyOrnate = require("../examples/themes/fantasy_ornate")
local Compose = Facet.Compose

type World = {
	built: any,
	root: any,
	screen: any,
	engine: any,
	gui: any,
	runtime: any,
	stop: () -> (),
}

type Options = {
	reducedMotion: boolean?,
	heartbeat: boolean?,
	guiService: boolean?,
	viewport: any?,
	seed: number?,
}

local helpers: { [string]: boolean } = {
	fill = true,
	badged = true,
	environment = true,
	worldAnchor = true,
	scrollTo = true,
	scrollToVisible = true,
}

local function world(module: any, options: Options?): World
	local settings: Options = options or {}
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	gui.ReducedMotionEnabled = settings.reducedMotion == true
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local screen = engine.new("ScreenGui")
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
			viewport = settings.viewport or Compose.cell({ width = 1000, height = 720 }),
			guiService = if settings.guiService or settings.reducedMotion ~= nil then gui else nil,
			heartbeat = if settings.heartbeat then engine.heartbeat else nil,
		})
		return built.screen()
	end, screen)
	return {
		built = built,
		root = root,
		screen = screen,
		engine = engine,
		gui = gui,
		runtime = runtime,
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

local function containsText(node: any, fragment: string): boolean
	for _, value in texts(node) do
		if string.find(value, fragment, 1, true) then
			return true
		end
	end
	return false
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

local function placeholders(text: string): { string }
	local out = {}
	for name in string.gmatch(text, "{(%w+)}") do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

local JARGON = { "proof", "stage", "gate", "ledger", "spec", "clean%-room", "ra%-p" }

local function jargon(value: string): string?
	local lowered = string.lower(value)
	for _, pattern in JARGON do
		if string.find(lowered, pattern) then
			return pattern
		end
	end
	return nil
end

t.describe("native parity reference applications", function()
	t.describe("Glade", function()
		t.it(
			"opens the shop for an empty premium satchel and presents the wisp only when the glade is ready",
			function()
				local w = world(glade)
				local steps, model = w.built.steps, w.built.model
				local held = model.commerce.satchelOf("starlight")
				t.expect(held:peek()).toBe(gladeSeed.SATCHEL.starlight)
				for _ = 1, gladeSeed.SATCHEL.starlight do
					t.expect(steps.choose("mossholm", "starlight")).toBe(true)
				end
				t.expect(held:peek()).toBe(0)
				t.expect(modal(w.screen)).toBeNil()
				t.expect(steps.choose("mossholm", "starlight")).toBe(false)
				t.expect(held:peek()).toBe(0)
				t.expect(model.supply.nectarOf("mossholm"):peek()).toBe("starlight")
				t.expect(hasText(modal(w.screen), "Provisions")).toBe(true)
				w.stop()

				local fresh = world(glade)
				local report = fresh.built.report
				t.expect(fresh.built.model.visits.current("mossholm"):peek().wisp).toBe(gladeSeed.TASK.wisp)
				fresh.built.steps.open("mossholm")
				t.expect(#report().visits.presented).toBe(0)
				fresh.built.steps.refill("mossholm")
				t.expect(#report().visits.presented).toBe(0)
				t.expect(fresh.built.model.complete:peek()).toBe(false)
				t.expect(fresh.built.steps.choose("mossholm", gladeSeed.TASK_NECTAR)).toBe(true)
				t.expect(fresh.built.model.complete:peek()).toBe(true)
				t.expect(same(report().visits.presented, { "v2" })).toBe(true)
				t.expect(hasText(fresh.root, "Mossholm is ready. Your visiting wisp has a home.")).toBe(true)
				fresh.stop()
			end
		)

		t.it("drains nectar and dew on their own clock thresholds and restamps on refill", function()
			local w = world(glade)
			local steps, supply = w.built.steps, w.built.model.supply
			local nectar, dew = supply.state("mossholm", "nectar"), supply.state("lanternDell", "dew")
			t.expect(gladeSeed.DRAIN.nectar.low).toBe(7.5 * 60)
			t.expect(gladeSeed.DRAIN.nectar.empty).toBe(9 * 60)
			t.expect(gladeSeed.DRAIN.dew.low ~= gladeSeed.DRAIN.nectar.low).toBe(true)
			t.expect(gladeSeed.DRAIN.dew.empty ~= gladeSeed.DRAIN.nectar.empty).toBe(true)
			t.expect(nectar:peek()).toBe("full")
			steps.advance(449)
			t.expect(nectar:peek()).toBe("full")
			steps.advance(1)
			t.expect(nectar:peek()).toBe("low")
			steps.advance(89)
			t.expect(nectar:peek()).toBe("low")
			steps.advance(1)
			t.expect(nectar:peek()).toBe("empty")
			t.expect(supply.level("mossholm", "nectar"):peek()).toBe(0)
			steps.refill("lanternDell")
			t.expect(dew:peek()).toBe("full")
			t.expect(supply.level("lanternDell", "dew"):peek()).toBe(1)
			steps.advance(gladeSeed.DRAIN.dew.low - 1)
			t.expect(dew:peek()).toBe("full")
			t.expect(supply.level("lanternDell", "dew"):peek() < 1).toBe(true)
			steps.advance(1)
			t.expect(dew:peek()).toBe("low")
			steps.advance(gladeSeed.DRAIN.dew.empty - gladeSeed.DRAIN.dew.low - 1)
			t.expect(dew:peek()).toBe("low")
			steps.advance(1)
			t.expect(dew:peek()).toBe("empty")
			steps.refill("lanternDell")
			t.expect(dew:peek()).toBe("full")
			steps.advance(gladeSeed.DRAIN.dew.low)
			t.expect(dew:peek()).toBe("low")
			t.expect(steps.choose("mossholm", "clover")).toBe(true)
			t.expect(nectar:peek()).toBe("full")
			w.stop()
		end)

		t.it(
			"runs a provision purchase through pending, confirmed and the scripted decline on its Buy button",
			function()
				local w = world(glade)
				local steps, commerce = w.built.steps, w.built.model.commerce
				w.built.model.section:set("keeper")
				press(w.root, "Keeper", "Shop")
				local shop = assert(find(modal(w.screen), "Shop"))
				local row = assert(find(shop, "starlightSingle"))
				local buy = assert(find(row, "Buy"))
				t.expect(buy.Text).toBe(commerce.priceOf("starlightSingle"))
				t.expect(buy.Text).toBe(`{gladeStrings.PRICE_MARK} 79`)
				t.expect(find(find(shop, "moonpetalBundle"), "Buy").Text).toBe(commerce.priceOf("moonpetalBundle"))
				local before = commerce.satchelOf("starlight"):peek()
				buy.Activated.fire()
				t.expect(commerce.status("starlightSingle"):peek()).toBe("pending")
				t.expect(buy.Text).toBe("Confirming…")
				t.expect(buy.Interactable).toBe(false)
				t.expect(hasText(row, "pending")).toBe(true)
				buy.Activated.fire()
				t.expect(w.built.report().commerce.attempts.pack).toBe(1)
				steps.advance(gladeSeed.COMMAND_SECONDS - 0.01)
				t.expect(commerce.status("starlightSingle"):peek()).toBe("pending")
				steps.advance(0.01)
				t.expect(commerce.status("starlightSingle"):peek()).toBe("confirmed")
				t.expect(commerce.satchelOf("starlight"):peek()).toBe(before + 1)
				t.expect(buy.Interactable).toBe(true)
				t.expect(buy.Text).toBe(commerce.priceOf("starlightSingle"))
				buy.Activated.fire()
				steps.advance(gladeSeed.COMMAND_SECONDS)
				t.expect(commerce.status("starlightSingle"):peek()).toBe("rejected")
				t.expect(commerce.reason("starlightSingle"):peek()).toBe("declined")
				t.expect(commerce.satchelOf("starlight"):peek()).toBe(before + 1)
				t.expect(hasText(row, "rejected: declined")).toBe(true)
				w.stop()
			end
		)

		t.it(
			"refuses to resell an owned charm, confirms a retry and opens the Frostwisp early window with Lumen",
			function()
				local w = world(glade)
				local steps, commerce, visits = w.built.steps, w.built.model.commerce, w.built.model.visits
				steps.advance(60)
				t.expect(visits.current("lanternDell"):peek()).toBeNil()
				steps.charm("grove")
				steps.advance(gladeSeed.COMMAND_SECONDS)
				t.expect(commerce.charmTier():peek()).toBe("grove")
				for _, lower in { "ember", "grove" } do
					steps.charm(lower)
					steps.advance(gladeSeed.COMMAND_SECONDS)
					t.expect(commerce.status(lower):peek()).toBe("rejected")
					t.expect(commerce.reason(lower):peek()).toBe("owned")
					t.expect(commerce.charmTier():peek()).toBe("grove")
				end
				steps.charm("lumen")
				steps.advance(gladeSeed.COMMAND_SECONDS)
				t.expect(commerce.status("lumen"):peek()).toBe("rejected")
				t.expect(commerce.reason("lumen"):peek()).toBe("owned")
				t.expect(commerce.charmTier():peek()).toBe("grove")
				t.expect(visits.current("lanternDell"):peek()).toBeNil()
				steps.charm("lumen")
				steps.advance(gladeSeed.COMMAND_SECONDS)
				t.expect(commerce.status("lumen"):peek()).toBe("confirmed")
				t.expect(commerce.charmTier():peek()).toBe("lumen")
				local early = visits.current("lanternDell"):peek()
				t.expect(early.wisp).toBe("frostwisp")
				t.expect(early.start).toBe(60)
				steps.charm("ember")
				steps.advance(gladeSeed.COMMAND_SECONDS)
				t.expect(commerce.reason("ember"):peek()).toBe("owned")
				t.expect(commerce.charmTier():peek()).toBe("lumen")
				w.built.model.section:set("keeper")
				press(w.root, "Keeper", "Restore")
				t.expect(commerce.status("restore"):peek()).toBe("pending")
				steps.advance(gladeSeed.COMMAND_SECONDS)
				t.expect(commerce.status("restore"):peek()).toBe("confirmed")
				press(w.root, "Keeper", "Restore")
				steps.advance(gladeSeed.COMMAND_SECONDS)
				t.expect(commerce.status("restore"):peek()).toBe("rejected")
				t.expect(commerce.reason("restore"):peek()).toBe("offline")
				w.stop()
			end
		)

		t.it("states where a wisp was last seen and when it has not been seen", function()
			local w = world(glade)
			w.built.model.section:set("wisps")
			press(w.root, "Wisps", "emberwisp", "Open")
			local sheet = assert(modal(w.screen))
			t.expect(hasText(sheet, "Last seen in Mossholm")).toBe(true)
			press(sheet, "Close")
			t.expect(modal(w.screen)).toBeNil()
			press(w.root, "Wisps", "frostwisp", "Open")
			t.expect(hasText(assert(modal(w.screen)), "Not seen yet")).toBe(true)
			w.stop()
		end)

		t.it("commits a keeper edit on Save and discards it on Cancel", function()
			local w = world(glade)
			local model = w.built.model
			local name = gladeSeed.KEEPER.displayName
			model.section:set("keeper")
			press(w.root, "Keeper", "EditKeeper")
			local sheet = assert(modal(w.screen))
			type_(sheet, "DisplayName", "Rowan")
			t.expect(model.draftName:peek()).toBe("Rowan")
			press(sheet, "CancelKeeper")
			t.expect(modal(w.screen)).toBeNil()
			t.expect(model.keeperName:peek()).toBe(name)
			t.expect(hasText(w.root, name)).toBe(true)
			press(w.root, "Keeper", "EditKeeper")
			sheet = assert(modal(w.screen))
			t.expect(find(sheet, "DisplayName").Text).toBe(name)
			type_(sheet, "DisplayName", "Rowan")
			type_(sheet, "Contact", "rowan@glade")
			press(sheet, "SaveKeeper")
			t.expect(modal(w.screen)).toBeNil()
			t.expect(model.keeperName:peek()).toBe("Rowan")
			t.expect(model.keeperContact:peek()).toBe("rowan@glade")
			t.expect(hasText(w.root, "Rowan")).toBe(true)
			w.stop()
		end)

		t.it("asks before Fresh Start, keeps the world on Keep and reseeds it on Start over", function()
			local pristine = world(glade)
			local fresh = pristine.built.report()
			pristine.stop()
			local w = world(glade)
			local steps, model = w.built.steps, w.built.model
			steps.refill("fernhollow")
			steps.choose("mossholm", "starlight")
			steps.buy("starlightBundle")
			steps.charm("ember")
			steps.advance(30)
			type_(w.root, "Search", "moss")
			model.keeperName:set("Rowan")
			model.section:set("keeper")
			local changed = w.built.report()
			t.expect(same(changed, fresh)).toBe(false)
			press(w.root, "Keeper", "FreshStart")
			local alert = assert(modal(w.screen))
			t.expect(hasText(alert, gladeStrings.get("en", "keeper.confirmTitle"))).toBe(true)
			press(alert, "cancel")
			t.expect(modal(w.screen)).toBeNil()
			t.expect(same(w.built.report(), changed)).toBe(true)
			t.expect(model.keeperName:peek()).toBe("Rowan")
			press(w.root, "Keeper", "FreshStart")
			press(assert(modal(w.screen)), "reset")
			t.expect(modal(w.screen)).toBeNil()
			t.expect(same(w.built.report(), fresh)).toBe(true)
			t.expect(model.section:peek()).toBe("glades")
			t.expect(find(w.root, "Search").Text).toBe("")
			local cards = 0
			for _, child in within(w.root, "Glades", "Content", "Glades"):GetChildren() do
				if child.ClassName == "Frame" then
					cards += 1
				end
			end
			t.expect(cards).toBe(#gladeSeed.GLADES)
			t.expect(model.keeperName:peek()).toBe(gladeSeed.KEEPER.displayName)
			w.stop()
		end)

		t.it(
			"gives identical reports for identical worlds, keeps a report stable and makes every step callable",
			function()
				local function drive(target: World)
					local steps = target.built.steps
					steps.open("fernhollow")
					steps.refill("fernhollow")
					steps.choose("fernhollow", "meadow")
					steps.buy("gildedSingle")
					steps.charm("grove")
					steps.restore()
					steps.advance(120)
					steps.choose("mossholm", "starlight")
					steps.advance(400)
				end
				local a, b = world(glade), world(glade)
				drive(a)
				drive(b)
				local first = a.built.report()
				t.expect(same(first, b.built.report())).toBe(true)
				t.expect(same(first, a.built.report())).toBe(true)
				t.expect(first.commerce.charm).toBe("grove")
				local calls = {
					advance = { 1 },
					open = { "mossholm" },
					refill = { "mossholm" },
					choose = { "mossholm", "clover" },
					buy = { "moonpetalSingle" },
					charm = { "lumen" },
					restore = {},
					reset = {},
					saveKeeper = {},
				}
				for name, step in a.built.steps do
					local args = assert(calls[name], `unexpected step {name}`)
					t.expect(type(step)).toBe("function")
					step(table.unpack(args))
				end
				for name in calls do
					t.expect(type(a.built.steps[name])).toBe("function")
				end
				a.stop()
				b.stop()
			end
		)

		t.it("lists one overview entry per seeded glade in order with supply states and filters by search", function()
			local w = world(glade)
			local list = assert(within(w.root, "Glades", "Content", "Glades"))
			local function ids(): { string }
				local out = {}
				local children = {}
				for _, child in list:GetChildren() do
					if child.ClassName == "Frame" then
						table.insert(children, child)
					end
				end
				table.sort(children, function(x, y)
					return x.LayoutOrder < y.LayoutOrder
				end)
				for _, child in children do
					table.insert(out, child.Name)
				end
				return out
			end
			local seeded = {}
			for _, item in gladeSeed.GLADES do
				table.insert(seeded, item.id)
			end
			t.expect(table.concat(ids(), ",")).toBe(table.concat(seeded, ","))
			t.expect(hasText(find(list, "mossholm"), "Dew low · Nectar full")).toBe(true)
			t.expect(hasText(find(list, "lanternDell"), "Dew full · Nectar empty")).toBe(true)
			t.expect(hasText(find(list, "fernhollow"), "Dew low · Nectar low")).toBe(true)
			type_(w.root, "Search", "MOSS")
			t.expect(table.concat(ids(), ",")).toBe("mossholm")
			type_(w.root, "Search", "zzz")
			t.expect(#ids()).toBe(0)
			type_(w.root, "Search", "")
			t.expect(#ids()).toBe(#gladeSeed.GLADES)
			w.built.model.section:set("favorites")
			local favorites =
				assert(within(w.root, "Destinations", "Content", "favorites", "Glades", "Content", "Glades"))
			local shown = 0
			for _, child in favorites:GetChildren() do
				if child.ClassName == "Frame" then
					shown += 1
					t.expect(gladeSeed.GLADE_BY_ID[child.Name].favourite).toBe(true)
				end
			end
			t.expect(shown).toBe(1)
			w.stop()
		end)

		t.it("refills dew instantly from the detail with no confirmation and a toast", function()
			local w = world(glade)
			local supply = w.built.model.supply
			press(w.root, "Task")
			local sheet = assert(modal(w.screen))
			t.expect(supply.state("mossholm", "dew"):peek()).toBe("low")
			press(sheet, "GladeDetail", "Refill")
			t.expect(supply.state("mossholm", "dew"):peek()).toBe("full")
			t.expect(supply.level("mossholm", "dew"):peek()).toBe(1)
			t.expect(modal(w.screen)).toBe(sheet)
			t.expect(find(w.screen, "AlertPanel")).toBeNil()
			t.expect(hasText(w.root, gladeStrings.get("en", "toast.refill", { glade = "Mossholm" }))).toBe(true)
			t.expect(hasText(sheet, "Dew: full")).toBe(true)
			w.stop()
		end)

		t.it("moves its navigation between homes on a live resize and keeps the world and every section", function()
			local w = world(glade)
			local model = w.built.model
			local destinations = assert(find(w.root, "Destinations"))
			local V2 = w.engine.types.Vector2
			local E = w.engine.types.Enum
			model.supply.refill("fernhollow", "dew")
			type_(w.root, "Search", "fern")
			local report = w.built.report()
			local tabs = assert(find(destinations, "Tabs"))
			destinations.AbsoluteSize = V2.new(1000, 700)
			t.expect(tabs.ScrollingDirection).toBe(E.ScrollingDirection.Y)
			destinations.AbsoluteSize = V2.new(390, 800)
			t.expect(tabs.ScrollingDirection).toBe(E.ScrollingDirection.X)
			t.expect(tabs.Position.Y.Scale).toBe(1)
			destinations.AbsoluteSize = V2.new(1000, 700)
			t.expect(tabs.ScrollingDirection).toBe(E.ScrollingDirection.Y)
			t.expect(find(w.root, "Destinations")).toBe(destinations)
			t.expect(find(destinations, "Tabs")).toBe(tabs)
			t.expect(same(w.built.report(), report)).toBe(true)
			t.expect(find(w.root, "Search").Text).toBe("fern")
			for _, size in { V2.new(1000, 700), V2.new(390, 800), V2.new(800, 360) } do
				destinations.AbsoluteSize = size
				for _, id in { "glades", "favorites", "wisps", "flora", "keeper" } do
					find(tabs, id).Activated.fire()
					t.expect(model.section:peek()).toBe(id)
				end
			end
			w.stop()
		end)

		t.it(
			"keeps locale key parity, expands by 1.4 times, keeps placeholders, falls back and relabels live",
			function()
				local keys = gladeStrings.keys()
				t.expect(#keys > 80).toBe(true)
				for _, key in keys do
					local en, xa = gladeStrings.TABLES.en[key], gladeStrings.TABLES.xa[key]
					t.expect(type(xa)).toBe("string")
					t.expect(#xa).toBe(#en + math.max(1, math.ceil(#en * 0.4)))
					t.expect(table.concat(placeholders(xa), ",")).toBe(table.concat(placeholders(en), ","))
				end
				local filled = gladeStrings.get("xa", "toast.refill", { glade = "Mossholm" })
				t.expect(string.find(filled, "Mossholm", 1, true) ~= nil).toBe(true)
				t.expect(string.find(filled, "{glade}", 1, true)).toBeNil()
				t.expect(gladeStrings.get("qq", "keeper.cancel")).toBe("Cancel")
				t.expect(gladeStrings.get("qq", "task.open", { glade = "Mossholm" })).toBe("Open Mossholm")
				local w = world(glade)
				local task = assert(find(w.root, "Task"))
				local open = assert(within(w.root, "Glades", "mossholm", "Open"))
				t.expect(open.Text).toBe("Mossholm")
				w.built.model.section:set("keeper")
				press(w.root, "Keeper", "Locale", "xa")
				w.built.model.section:set("glades")
				t.expect(open.Text).toBe(gladeStrings.TABLES.xa["glade.mossholm"])
				t.expect(find(w.root, "Task")).toBe(task)
				t.expect(within(w.root, "Glades", "mossholm", "Open")).toBe(open)
				w.stop()
			end
		)

		t.it("keeps the same states and events under reduced motion and holds the wisp still", function()
			local function drive(target: World)
				local steps = target.built.steps
				steps.refill("mossholm")
				steps.choose("mossholm", gladeSeed.TASK_NECTAR)
				steps.buy("gildedSingle")
				steps.advance(3)
			end
			local moving = world(glade, { reducedMotion = false })
			local still = world(glade, { reducedMotion = true })
			local function wisp(target: World): any
				return assert(within(target.root, "Glades", "mossholm", "LivingGlade", gladeSeed.TASK.wisp))
			end
			local movingStart, stillStart = wisp(moving).Position, wisp(still).Position
			drive(moving)
			drive(still)
			t.expect(wisp(still).Position).toBe(stillStart)
			t.expect(wisp(moving).Position ~= movingStart).toBe(true)
			t.expect(same(moving.built.report(), still.built.report())).toBe(true)
			still.gui.ReducedMotionEnabled = false
			still.built.steps.advance(1)
			t.expect(wisp(still).Position ~= stillStart).toBe(true)
			moving.stop()
			still.stop()
		end)

		t.it("browses flora by name and species with no presented surface", function()
			local w = world(glade)
			w.built.model.section:set("flora")
			local page = assert(find(w.root, "Flora"))
			for _, item in gladeSeed.FLORA do
				local column = assert(find(page, item.id), item.id)
				t.expect(hasText(column, gladeStrings.get("en", "flora." .. item.id))).toBe(true)
				t.expect(hasText(column, gladeStrings.get("en", "flora.species." .. item.id))).toBe(true)
				for _, node in column:GetDescendants() do
					t.expect(node.ClassName ~= "TextButton").toBe(true)
				end
			end
			t.expect(modal(w.screen)).toBeNil()
			w.stop()
		end)

		t.it("keeps test vocabulary out of every string a player can read", function()
			local offenders = {}
			for _, locale in gladeStrings.LOCALES do
				for key, value in gladeStrings.TABLES[locale] do
					if jargon(value) then
						table.insert(offenders, `{locale}:{key}`)
					end
				end
			end
			local w = world(glade)
			for _, id in { "glades", "favorites", "wisps", "flora", "keeper" } do
				w.built.model.section:set(id)
				for _, value in texts(w.root) do
					if jargon(value) then
						table.insert(offenders, value)
					end
				end
			end
			t.expect(table.concat(offenders, "; ")).toBe("")
			t.expect(glade.title).toBe("Glade")
			w.stop()
		end)
	end)

	t.describe("Cartwheel", function()
		local LATENCY = 0.25

		local function pages(w: World): any
			return assert(within(w.root, "Destinations", "Content"))
		end

		local function brewList(w: World): any
			w.built.model.section:set("brews")
			local list = assert(find(pages(w), "BrewList"))
			list.AbsoluteSize = w.engine.types.Vector2.new(600, 4000)
			list.AbsoluteWindowSize = w.engine.types.Vector2.new(600, 4000)
			return list
		end

		local function rowKeys(list: any): { number }
			local out = {}
			for _, row in assert(find(list, "Items")):GetChildren() do
				local key = tonumber(row.Name)
				if key then
					table.insert(out, key)
				end
			end
			table.sort(out, function(a, b)
				return a > b
			end)
			return out
		end

		t.it("borrows only shipped framework art for its potion marks", function()
			local neutral = Facet.themes.neutralPackage()
			local count = 0
			for name, mark in cartArt.marks do
				count += 1
				t.expect(Facet.themes.resolveIcon(neutral, mark.iconName)).toBe(mark.image)
				t.expect(table.find(cartArt.cycle, name) ~= nil).toBe(true)
			end
			t.expect(count).toBe(#cartArt.cycle)
			for _, potion in cartData.potions do
				t.expect(Facet.themes.resolveIcon(neutral, potion.mark.iconName)).toBe(potion.mark.image)
			end
			local w = world(cartwheel)
			w.built.model.section:set("workbench")
			for _, potion in cartData.potions do
				t.expect(within(pages(w), "Potions", potion.id, "Potion").Image).toBe(potion.mark.image)
			end
			w.stop()
		end)

		t.it("selects each section through its tab button", function()
			local w = world(cartwheel)
			local tabs = assert(within(w.root, "Destinations", "Tabs"))
			for _, id in { "brews", "workbench", "ledger", "chatter", "plazas", "dashboard" } do
				press(tabs, id)
				t.expect(w.built.model.section:peek()).toBe(id)
			end
			press(tabs, "workbench")
			t.expect(find(pages(w), "Workbench") ~= nil).toBe(true)
			t.expect(find(pages(w), "PotionName") ~= nil).toBe(true)
			w.stop()
		end)

		t.it("matches a brew search on its number, its potions and their ingredients", function()
			local w = world(cartwheel)
			local list = brewList(w)
			local brews = w.built.model.orders.brews:peek()
			t.expect(#rowKeys(list)).toBe(#brews)
			local function expected(query: string): { number }
				local out = {}
				for _, brew in brews do
					if string.find(w.built.model.orders.searchText(brew), string.lower(query), 1, true) then
						table.insert(out, brew.id)
					end
				end
				table.sort(out, function(a, b)
					return a > b
				end)
				return out
			end
			type_(pages(w), "Search", "117")
			t.expect(table.concat(rowKeys(list), ",")).toBe("117")
			local sample = brews[1]
			local potion = assert(cartData.potionById(sample.items[1].potion))
			type_(pages(w), "Search", string.upper(potion.name))
			local byPotion = rowKeys(list)
			t.expect(table.find(byPotion, sample.id) ~= nil).toBe(true)
			t.expect(table.concat(byPotion, ",")).toBe(table.concat(expected(potion.name), ","))
			local base = assert(cartData.ingredientById(potion.base))
			type_(pages(w), "Search", base.name)
			local byIngredient = rowKeys(list)
			t.expect(table.find(byIngredient, sample.id) ~= nil).toBe(true)
			t.expect(table.concat(byIngredient, ",")).toBe(table.concat(expected(base.name), ","))
			type_(pages(w), "Search", "no such brew")
			t.expect(#rowKeys(list)).toBe(0)
			w.stop()
		end)

		t.it(
			"moves a brew through start, brewing and done, disables pending commands and rejects a second collect",
			function()
				local w = world(cartwheel)
				local model, steps = w.built.model, w.built.steps
				local orders, commands = model.orders, model.commands
				local list = brewList(w)
				local row = assert(within(list, "Items", "101"))
				local advance = assert(find(row, "Advance"))
				t.expect(orders.statusOf(101)).toBe("new")
				t.expect(advance.Text).toBe("Start brewing")
				advance.Activated.fire()
				t.expect(commands.status("start:101"):peek()).toBe("pending")
				t.expect(advance.Interactable).toBe(false)
				advance.Activated.fire()
				steps.advance(LATENCY)
				t.expect(#commands.dump()).toBe(1)
				t.expect(orders.statusOf(101)).toBe("brewing")
				t.expect(orders.remaining(101)).toBe(orders.brewSeconds())
				t.expect(advance.Interactable).toBe(false)
				steps.openBrew(101)
				local sheet = assert(modal(w.screen))
				t.expect(hasText(sheet, `Status: brewing · {orders.brewSeconds()} s`)).toBe(true)
				t.expect(find(sheet, "Start").Interactable).toBe(false)
				t.expect(find(sheet, "Collect").Interactable).toBe(false)
				steps.advance(orders.brewSeconds() / 2)
				t.expect(orders.remaining(101)).toBe(orders.brewSeconds() / 2)
				t.expect(hasText(sheet, `Status: brewing · {math.ceil(orders.brewSeconds() / 2)} s`)).toBe(true)
				steps.advance(orders.brewSeconds())
				t.expect(orders.remaining(101)).toBe(0)
				t.expect(orders.statusOf(101)).toBe("brewing")
				press(sheet, "Close")
				steps.collect(101)
				t.expect(commands.status("finish:101"):peek()).toBe("pending")
				steps.advance(LATENCY)
				t.expect(orders.statusOf(101)).toBe("done")
				t.expect(orders.remaining(101)).toBeNil()
				t.expect(commands.status("finish:101"):peek()).toBe("confirmed")
				press(assert(modal(w.screen)), "done")
				local ready = assert(within(list, "Items", "124", "Advance"))
				t.expect(ready.Text).toBe("Collect brew")
				ready.Activated.fire()
				t.expect(ready.Interactable).toBe(false)
				steps.advance(LATENCY)
				t.expect(orders.statusOf(124)).toBe("done")
				press(assert(modal(w.screen)), "done")
				t.expect(steps.collect(124)).toBe(true)
				steps.advance(LATENCY)
				t.expect(commands.status("finish:124"):peek()).toBe("rejected")
				t.expect(commands.reason("finish:124"):peek()).toBe("Brew already collected")
				t.expect(hasText(w.root, "Brew already collected")).toBe(true)
				t.expect(steps.start(124)).toBe(true)
				steps.advance(LATENCY)
				t.expect(commands.reason("start:124"):peek()).toBe("Brew already collected")
				t.expect(orders.statusOf(124)).toBe("done")
				w.stop()
			end
		)

		t.it("opens the completion celebration on a collected brew and closes it on its action", function()
			local w = world(cartwheel)
			local steps = w.built.steps
			t.expect(modal(w.screen)).toBeNil()
			steps.collect(120)
			t.expect(modal(w.screen)).toBeNil()
			steps.advance(LATENCY)
			local alert = assert(modal(w.screen))
			t.expect(alert.Name).toBe("AlertPanel")
			t.expect(hasText(alert, "Brew collected!")).toBe(true)
			local brew = w.built.model.orders.byId(120)
			t.expect(hasText(alert, `Brew #120 collected · {brew.bottles} bottles`)).toBe(true)
			press(alert, "done")
			t.expect(modal(w.screen)).toBeNil()
			t.expect(w.built.model.stats.collectedBottles() >= brew.bottles).toBe(true)
			w.stop()
		end)

		t.it(
			"delivers scripted arrivals in id order at seeded three to eight second gaps and re-keys the newest row",
			function()
				local w = world(cartwheel)
				local model, steps = w.built.model, w.built.steps
				local times = model.orders.arrivalTimes
				t.expect(#times).toBe(20)
				local previous = 0
				for _, at in times do
					t.expect(at - previous >= 3 and at - previous <= 8).toBe(true)
					previous = at
				end
				local list = brewList(w)
				t.expect(rowKeys(list)[1]).toBe(124)
				steps.advance(times[1] - 0.01)
				t.expect(#model.orders.arrivalLog()).toBe(0)
				steps.advance(0.01)
				t.expect(table.concat(model.orders.arrivalLog(), ",")).toBe("125")
				t.expect(model.orders.brews:peek()[1].id).toBe(125)
				t.expect(rowKeys(list)[1]).toBe(125)
				for _ = 1, 200 do
					steps.advance(1)
				end
				local report = w.built.report().orders
				t.expect(#report.arrivals).toBe(20)
				for index, id in report.arrivals do
					t.expect(id).toBe(124 + index)
				end
				t.expect(report.arrivalsRemaining).toBe(0)
				t.expect(report.first).toBe(144)
				list.CanvasPosition = w.engine.types.Vector2.zero
				t.expect(rowKeys(list)[1]).toBe(144)
				t.expect(model.orders.statusOf(144)).toBe("new")
				model.section:set("dashboard")
				t.expect(hasText(pages(w), `{#model.orders.brews:peek()} brews · 0 bottles collected`)).toBe(true)
				w.stop()
			end
		)

		t.it("opens the workbench on a potion, applies edits at once and keeps each draft after leaving", function()
			local w = world(cartwheel)
			local model, steps = w.built.model, w.built.steps
			model.section:set("workbench")
			press(pages(w), "Potions", "moonwell", "Mix")
			t.expect(model.selectedPotion:peek()).toBe("moonwell")
			t.expect(model.draftName:peek()).toBe("Moonwell")
			t.expect(model.base:peek()).toBe("springwater")
			t.expect(find(pages(w), "PotionName").Text).toBe("Moonwell")
			type_(pages(w), "PotionName", "Moonwell Reserve")
			t.expect(model.draftName:peek()).toBe("Moonwell Reserve")
			press(pages(w), "Base", "Trigger")
			local option = assert(find(w.screen, "hearthmilk"))
			option.Activated.fire()
			t.expect(model.base:peek()).toBe("hearthmilk")
			local attributes = cartData.attributesOf("hearthmilk", "skyveil", "swirl-skyveil")
			local summary = {}
			for index, name in cartData.ATTRIBUTES do
				table.insert(summary, name .. " " .. tostring(attributes[index]))
			end
			t.expect(hasText(pages(w), table.concat(summary, " · "))).toBe(true)
			model.section:set("ledger")
			model.section:set("workbench")
			t.expect(model.draftName:peek()).toBe("Moonwell Reserve")
			t.expect(find(pages(w), "PotionName").Text).toBe("Moonwell Reserve")
			steps.selectPotion("ashroot")
			t.expect(model.draftName:peek()).toBe("Ashroot")
			t.expect(model.base:peek()).toBe("emberoil")
			steps.selectPotion("moonwell")
			t.expect(model.draftName:peek()).toBe("Moonwell Reserve")
			t.expect(model.base:peek()).toBe("hearthmilk")
			press(pages(w), "NewPotion")
			t.expect(model.selectedPotion:peek()).toBe("scratch")
			t.expect(model.draftName:peek()).toBe("New potion")
			w.stop()
		end)

		t.it("locks the longer ledger and the chatter bonus until the second purchase is granted", function()
			local w = world(cartwheel)
			local model, steps = w.built.model, w.built.steps
			model.section:set("ledger")
			t.expect(find(pages(w), "Trading") ~= nil).toBe(true)
			press(pages(w), "LedgerTimeframe", "month")
			t.expect(model.ledgerTimeframe:peek()).toBe("month")
			t.expect(find(pages(w), "Trading")).toBeNil()
			local buy = assert(within(pages(w), "Unlock", "Buy"))
			buy.Activated.fire()
			t.expect(buy.Interactable).toBe(false)
			steps.advance(LATENCY)
			t.expect(model.entitlement.fullLedger:peek()).toBe(false)
			t.expect(hasText(w.root, "Purchase declined — nothing was charged")).toBe(true)
			t.expect(find(pages(w), "Trading")).toBeNil()
			press(pages(w), "Unlock", "Buy")
			steps.advance(LATENCY)
			t.expect(model.entitlement.fullLedger:peek()).toBe(true)
			t.expect(find(pages(w), "Unlock")).toBeNil()
			t.expect(within(pages(w), "Trading", "Markets", "gullsgate") ~= nil).toBe(true)
			model.section:set("chatter")
			local function posts(): number
				local count = 0
				for _, child in assert(find(pages(w), "Posts")):GetChildren() do
					if child.ClassName == "Frame" then
						count += 1
					end
				end
				return count
			end
			t.expect(posts()).toBe(#cartData.chatterPosts)
			press(pages(w), "Subscribe")
			steps.advance(LATENCY)
			t.expect(model.entitlement.chatterPlus:peek()).toBe(false)
			t.expect(posts()).toBe(#cartData.chatterPosts)
			press(pages(w), "Subscribe")
			steps.advance(LATENCY)
			t.expect(model.entitlement.chatterPlus:peek()).toBe(true)
			t.expect(posts()).toBe(#cartData.chatterPosts + #cartData.chatterBonusPosts)
			t.expect(find(pages(w), "Subscribe").Interactable).toBe(false)
			w.stop()
		end)

		t.it("rejects a taken guild name with its reason and signs in an accepted name", function()
			local w = world(cartwheel)
			local model, steps = w.built.model, w.built.steps
			press(w.root, "Guild")
			local sheet = assert(modal(w.screen))
			t.expect(find(sheet, "Submit").Interactable).toBe(false)
			type_(sheet, "GuildName", "  Cartwheel ")
			t.expect(find(sheet, "GuildName").Text).toBe("cartwheel")
			type_(sheet, "Watchword", "secret")
			local submit = assert(find(sheet, "Submit"))
			t.expect(submit.Interactable).toBe(true)
			submit.Activated.fire()
			t.expect(submit.Interactable).toBe(false)
			steps.advance(LATENCY)
			t.expect(model.identity.signedIn:peek()).toBe(false)
			t.expect(model.commands.status("signup"):peek()).toBe("rejected")
			t.expect(hasText(sheet, "That guild name is taken")).toBe(true)
			t.expect(modal(w.screen)).toBe(sheet)
			type_(sheet, "GuildName", "NewKeepers")
			press(sheet, "Submit")
			steps.advance(LATENCY)
			t.expect(model.identity.signedIn:peek()).toBe(true)
			t.expect(model.identity.guildName:peek()).toBe("newkeepers")
			t.expect(modal(w.screen)).toBeNil()
			t.expect(find(w.root, "Guild").Text).toBe("Sign out of newkeepers")
			w.stop()
		end)

		t.it("recommends the first plaza without a damp spell and mounts the market Stage", function()
			local ambient = cartAmbient.new({ seed = 1 })
			local recommended = ambient.recommendedPlaza()
			for _, plaza in cartData.plazas do
				if plaza == recommended then
					break
				end
				t.expect(ambient.hasDampSpell(plaza.id)).toBe(true)
			end
			t.expect(ambient.hasDampSpell(recommended.id)).toBe(false)
			local w = world(cartwheel)
			t.expect(hasText(pages(w), "Recommended pitch: " .. recommended.name)).toBe(true)
			w.built.model.section:set("plazas")
			local stage = assert(find(pages(w), "MarketScene"))
			t.expect(stage.ClassName).toBe("ViewportFrame")
			t.expect(stage.CurrentCamera ~= nil).toBe(true)
			local scene = assert(find(stage, cartData.plazas[1].name))
			t.expect(scene.ClassName).toBe("Model")
			t.expect(find(scene, "Cart").ClassName).toBe("Part")
			t.expect(find(scene, "Potion5") ~= nil).toBe(true)
			local weather = ambient.forPlaza(cartData.plazas[1].id)
			t.expect(hasText(pages(w), `Cloud cover {weather.cloud}%`)).toBe(true)
			w.stop()
		end)

		t.it("reports identically for one seed, differs for another and leaves nothing behind on dispose", function()
			local function drive(target: World)
				local steps = target.built.steps
				steps.start(101)
				steps.collect(115)
				steps.purchase("ledger")
				steps.advance(0.3)
				steps.purchase("ledger")
				steps.signup("cartwheel", "x")
				steps.advance(30)
			end
			local a, b = world(cartwheel), world(cartwheel)
			drive(a)
			drive(b)
			t.expect(same(a.built.report(), b.built.report())).toBe(true)
			t.expect(same(a.built.report(), a.built.report())).toBe(true)
			local function dump(seed: number): any
				local clock = cartClock.new(Compose, { start = 0 })
				local orders = cartOrders.new({ Compose = Compose, clock = clock, seed = seed })
				clock.advance(30)
				return orders.dump()
			end
			t.expect(same(dump(1), dump(1))).toBe(true)
			t.expect(same(dump(1).arrivals, a.built.report().orders.arrivals)).toBe(true)
			t.expect(same(dump(1), dump(2))).toBe(false)
			a.stop()
			b.stop()
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local host = engine.new("ScreenGui")
			local baseline = engine.census()
			local stop, root = runtime.mount(function()
				return cartwheel
					.build({
						Facet = Facet,
						Compose = Compose,
						runtime = runtime,
						Host = runtime.constructors,
						UI = Facet.controls(runtime, { types = engine.types } :: any),
						types = engine.types,
						viewport = Compose.cell({ width = 1000, height = 720 }),
						heartbeat = engine.heartbeat,
					})
					.screen()
			end, host)
			t.expect(engine.heartbeat.count()).toBe(1)
			engine.heartbeat.fire(LATENCY)
			stop()
			runtime:dispose()
			t.expect(root.isDestroyed()).toBe(true)
			t.expect(engine.heartbeat.count()).toBe(0)
			t.expect(engine.census().live).toBe(baseline.live)
			t.expect(engine.census().connections).toBe(baseline.connections)
		end)

		t.it("expands the pseudo-locale by at least 1.4 times and keeps every placeholder", function()
			t.expect(cartStrings.EXPANSION).toBe(1.4)
			local count = 0
			for key, en in cartStrings.locales.en do
				count += 1
				local xa = assert(cartStrings.locales.xa[key])
				t.expect(#xa >= math.ceil(#en * 1.4)).toBe(true)
				t.expect(string.sub(xa, 2, #en + 1)).toBe(en)
				t.expect(table.concat(placeholders(xa), ",")).toBe(table.concat(placeholders(en), ","))
			end
			for key in cartStrings.locales.xa do
				t.expect(cartStrings.locales.en[key] ~= nil).toBe(true)
			end
			t.expect(count > 40).toBe(true)
			local welcome = cartStrings.new("xa").t("guild.welcome", { name = "Ash" })
			t.expect(string.find(welcome, "Ash", 1, true) ~= nil).toBe(true)
			t.expect(string.find(welcome, "{name}", 1, true)).toBeNil()
			t.expect(cartStrings.new("zz").locale).toBe("en")
		end)

		t.it("mounts and drives identically with reduced motion", function()
			local function drive(target: World): any
				local steps = target.built.steps
				steps.start(102)
				steps.collect(111)
				steps.advance(0.3)
				steps.purchase("chatter")
				steps.advance(12)
				steps.openBrew(102)
				return target.built.report()
			end
			local moving = world(cartwheel, { reducedMotion = false })
			local still = world(cartwheel, { reducedMotion = true })
			t.expect(same(drive(moving), drive(still))).toBe(true)
			t.expect(modal(still.screen) ~= nil).toBe(true)
			moving.stop()
			still.stop()
		end)
	end)

	t.describe("Sipworks", function()
		local function pages(w: World): any
			return assert(within(w.root, "Destinations", "Content"))
		end

		local function blendRows(w: World, tab: string?): { string }
			local list = assert(within(pages(w), tab or "menu", "Blends"))
			local rows = {}
			for _, child in list:GetChildren() do
				if child.ClassName == "Frame" then
					table.insert(rows, child)
				end
			end
			table.sort(rows, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			local out = {}
			for _, row in rows do
				table.insert(out, row.Name)
			end
			return out
		end

		t.it("keeps search text, the open blend and the section across a shell flip", function()
			local w = world(sipworks)
			local model = w.built.model
			local destinations = assert(find(w.root, "Destinations"))
			local tabs = assert(find(destinations, "Tabs"))
			local V2, E = w.engine.types.Vector2, w.engine.types.Enum
			destinations.AbsoluteSize = V2.new(390, 800)
			type_(pages(w), "Search", "mint")
			press(tabs, "favorites")
			press(pages(w), "favorites", "Blends", "mistral-mint", "Open")
			local sheet = assert(modal(w.screen))
			local root = w.root
			t.expect(tabs.ScrollingDirection).toBe(E.ScrollingDirection.X)
			destinations.AbsoluteSize = V2.new(1100, 800)
			t.expect(tabs.ScrollingDirection).toBe(E.ScrollingDirection.Y)
			t.expect(model.search:peek()).toBe("mint")
			t.expect(within(pages(w), "favorites", "Search").Text).toBe("mint")
			t.expect(model.section:peek()).toBe("favorites")
			t.expect(model.selected:peek()).toBe("mistral-mint")
			t.expect(modal(w.screen)).toBe(sheet)
			t.expect(find(w.root, "Destinations")).toBe(destinations)
			t.expect(w.root).toBe(root)
			destinations.AbsoluteSize = V2.new(390, 800)
			t.expect(model.search:peek()).toBe("mint")
			t.expect(model.section:peek()).toBe("favorites")
			w.stop()
		end)

		t.it(
			"matches a title or a botanical, shares the query across sections and toggles a shared favorite",
			function()
				local w = world(sipworks)
				local model = w.built.model
				type_(pages(w), "Search", "lavender")
				t.expect(table.concat(blendRows(w), ",")).toBe("moonpetal,nightporch")
				type_(pages(w), "Search", "MOON")
				t.expect(table.concat(blendRows(w), ",")).toBe("moonpetal")
				type_(pages(w), "Search", "lavender")
				t.expect(model.favorites.isFavorite("moonpetal")).toBe(false)
				local favorite = assert(within(pages(w), "Blends", "moonpetal", "Favorite"))
				t.expect(favorite.Text).toBe("Save favorite")
				favorite.Activated.fire()
				t.expect(model.favorites.isFavorite("moonpetal")).toBe(true)
				t.expect(favorite.Text).toBe("Remove favorite")
				press(assert(within(w.root, "Destinations", "Tabs")), "favorites")
				t.expect(model.search:peek()).toBe("lavender")
				t.expect(find(pages(w), "Search").Text).toBe("lavender")
				t.expect(table.concat(blendRows(w, "favorites"), ",")).toBe("moonpetal")
				press(pages(w), "favorites", "Blends", "moonpetal", "Favorite")
				t.expect(model.favorites.isFavorite("moonpetal")).toBe(false)
				t.expect(#blendRows(w, "favorites")).toBe(0)
				type_(within(pages(w), "favorites"), "Search", "")
				local expected = {}
				for _, id in model.favorites.ids() do
					table.insert(expected, id)
				end
				local shown = blendRows(w, "favorites")
				table.sort(shown)
				t.expect(table.concat(shown, ",")).toBe(table.concat(expected, ","))
				w.stop()
			end
		)

		t.it("opens the botanical card from a tile with the facts for this blend", function()
			local w = world(sipworks)
			local catalog = w.built.model.catalog
			w.built.steps.open("lantern-oolong")
			press(assert(modal(w.screen)), "BlendDetail", "jasmine")
			local card = assert(find(w.screen, "BotanicalCard"))
			t.expect(hasText(card, "Jasmine")).toBe(true)
			t.expect(hasText(card, sipArt.of("botanical", "jasmine").mark)).toBe(true)
			t.expect(find(card, "MeasuredFacts")).toBeNil()
			press(card, "Flip")
			local facts = assert(find(card, "MeasuredFacts"))
			local i18n = w.built.model.i18n
			for _, fact in catalog.factsFor("lantern-oolong", "jasmine") do
				local line = i18n.t(fact.key) .. ": " .. i18n.t("facts." .. fact.kind, { value = fact.value })
				t.expect(hasText(facts, line)).toBe(true)
			end
			t.expect(#catalog.factsFor("lantern-oolong", "jasmine")).toBe(4)
			t.expect(#texts(facts)).toBe(4)
			w.stop()
		end)

		t.it("shows the guard reason and never starts an order when ordering is off", function()
			local w = world(sipworks)
			local model = w.built.model
			model.order.setPaymentsEnabled(false)
			w.built.steps.open("amber-harvest")
			press(assert(modal(w.screen)), "BlendDetail", "Order")
			t.expect(model.order.status:peek()).toBe("idle")
			t.expect(hasText(w.root, sipStrings.byLocale.en["guard.paymentsDisabled"])).toBe(true)
			t.expect(model.task.phase:peek()).toBe("order")
			w.built.steps.advance(5)
			t.expect(model.order.attempts()).toBe(0)
			t.expect(model.rewards.unspent()).toBe(9)
			w.stop()
		end)

		t.it("refuses the Blend Book while its price loads and rescales recipe measures with the batch", function()
			local w = world(sipworks)
			local model, steps = w.built.model, w.built.steps
			steps.open("lantern-oolong")
			local sheet = assert(modal(w.screen))
			press(sheet, "BlendDetail", "Recipe")
			t.expect(within(sheet, "Unlock") ~= nil).toBe(true)
			t.expect(model.unlock.availability:peek()).toBe("pending")
			t.expect(within(sheet, "Unlock", "Buy")).toBeNil()
			t.expect(steps.buyBook()).toBe(false)
			steps.advance(0.99)
			t.expect(within(sheet, "Unlock", "Buy")).toBeNil()
			steps.advance(0.01)
			local buy = assert(within(sheet, "Unlock", "Buy"))
			t.expect(buy.Interactable).toBe(true)
			buy.Activated.fire()
			t.expect(model.unlock.status:peek()).toBe("pending")
			t.expect(buy.Interactable).toBe(false)
			press(sheet, "Close")
			steps.open("amber-harvest")
			sheet = assert(modal(w.screen))
			press(sheet, "BlendDetail", "Recipe")
			local recipe
			for _, node in sheet:GetDescendants() do
				if node.Name == "Recipe" and node.ClassName == "Frame" then
					recipe = node
				end
			end
			assert(recipe, "no recipe column")
			t.expect(find(recipe, "Unlock")).toBeNil()
			local assam = assert(find(recipe, "assam"))
			local function label(node: any): string
				return node.Text
			end
			t.expect(label(assam)).toBe("Assam · 2 tsp")
			t.expect(label(find(recipe, "cinnamon"))).toBe("Cinnamon · 0.5 tsp")
			local increase = assert(within(recipe, "Batch", "Increase"))
			increase.Activated.fire()
			increase.Activated.fire()
			t.expect(model.batch:peek()).toBe(3)
			t.expect(label(assam)).toBe("Assam · 6 tsp")
			t.expect(label(find(recipe, "cinnamon"))).toBe("Cinnamon · 1.5 tsp")
			model.i18n.setLocale("xa")
			t.expect(label(find(recipe, "cinnamon"))).toBe(model.i18n.at("xa", "recipe.line", {
				name = model.i18n.nameAt("xa", "botanical", "cinnamon", "Cinnamon"),
				measure = model.i18n.measureAt("xa", 1.5, "tsp"),
			}))
			t.expect(string.find(label(find(recipe, "cinnamon")), "1,5", 1, true) ~= nil).toBe(true)
			w.stop()
		end)

		t.it(
			"keeps locale keys, expansion, placeholders, plurals and separators and relabels without a remount",
			function()
				local en, xa = sipStrings.byLocale.en, sipStrings.byLocale.xa
				local worst, measured = math.huge, 0
				for key, entry in en do
					local forms = if type(entry) == "table" then entry else { other = entry }
					for form, template in forms do
						local expanded = assert(xa[key])
						local text = if type(expanded) == "table" then expanded[form] else expanded
						t.expect(type(text)).toBe("string")
						local source = string.gsub(template, "{[%w_]+}", "")
						local target = string.gsub(text, "{[%w_]+}", "")
						if #string.gsub(source, "%s", "") >= 4 then
							measured += 1
							worst = math.min(worst, #target / #source)
						end
						t.expect(table.concat(placeholders(text), ",")).toBe(table.concat(placeholders(template), ","))
					end
				end
				t.expect(measured > 30).toBe(true)
				t.expect(worst >= sipStrings.EXPANSION).toBe(true)
				for key in xa do
					t.expect(en[key] ~= nil).toBe(true)
				end
				local w = world(sipworks)
				local i18n = w.built.model.i18n
				t.expect(i18n.at("en", "rewards.away", { n = 0 })).toBe("Your next pour is on the house!")
				t.expect(i18n.at("en", "rewards.away", { n = 1 })).toBe("You are 1 stamp from a free pour!")
				t.expect(i18n.at("en", "rewards.away", { n = 4 })).toBe("You are 4 stamps from a free pour!")
				t.expect(i18n.at("xa", "recipe.batches", { n = 1 })).toBe(xa["recipe.batches"].one)
				t.expect(i18n.at("xa", "recipe.batches", { n = 3 }))
					.toBe(string.gsub(xa["recipe.batches"].other, "{n}", "3"))
				t.expect(i18n.listAt("en", { "a", "b" })).toBe("a and b")
				t.expect(i18n.listAt("en", { "a", "b", "c" })).toBe("a, b, and c")
				t.expect(i18n.listAt("xa", { "a", "b" }) ~= "a and b").toBe(true)
				t.expect(i18n.measureAt("en", 1.5, "tsp")).toBe("1.5 tsp")
				t.expect(string.find(i18n.measureAt("xa", 1.5, "tsp"), "1,5", 1, true) ~= nil).toBe(true)
				t.expect(i18n.setLocale("zz")).toBe(false)
				t.expect(i18n.locale:peek()).toBe("en")
				local open = assert(within(pages(w), "Blends", "amber-harvest", "Open"))
				t.expect(open.Text).toBe("Amber Harvest")
				local root = w.root
				w.built.model.section:set("rewards")
				press(pages(w), "Locale", "xa")
				t.expect(i18n.locale:peek()).toBe("xa")
				w.built.model.section:set("menu")
				open = assert(within(pages(w), "Blends", "amber-harvest", "Open"))
				t.expect(open.Text).toBe(sipStrings.expand("Amber Harvest"))
				t.expect(w.root).toBe(root)
				w.built.steps.open("amber-harvest")
				local sheet = assert(modal(w.screen))
				local close = assert(find(sheet, "Close"))
				t.expect(close.Text).toBe(xa["common.done"])
				t.expect(close.Text ~= en["common.done"]).toBe(true)
				t.expect(i18n.setLocale("en")).toBe(true)
				t.expect(close.Text).toBe(en["common.done"])
				w.stop()
			end
		)

		t.it("reports identically for identical worlds and seeds favorites deterministically", function()
			local function drive(target: World)
				local steps = target.built.steps
				steps.favorite("tidepool")
				steps.order("amber-harvest", "paid")
				steps.advance(0.7)
				steps.order("amber-harvest", "paid")
				steps.advance(5)
				steps.buyBook()
				steps.advance(2)
			end
			local a, b = world(sipworks), world(sipworks)
			drive(a)
			drive(b)
			t.expect(same(a.built.report(), b.built.report())).toBe(true)
			t.expect(same(a.built.report(), a.built.report())).toBe(true)
			t.expect(a.built.report().task).toBe("redeem/10/true/false/false")
			local function seeded(seed: number): { string }
				local ids = {}
				for _, blend in sipBlends.list do
					table.insert(ids, blend.id)
				end
				return sipFavorites.new({ Compose = Compose, seed = seed, ids = ids }).ids()
			end
			t.expect(same(seeded(1), seeded(1))).toBe(true)
			t.expect(same(seeded(1), seeded(2))).toBe(false)
			a.stop()
			b.stop()
		end)

		t.it("fires the same events under reduced motion and leaves nothing behind on dispose", function()
			local function drive(target: World): any
				local steps = target.built.steps
				steps.order("amber-harvest", "paid")
				steps.advance(0.7)
				steps.order("amber-harvest", "paid")
				steps.advance(0.7)
				steps.redeem()
				steps.advance(5)
				return target.built.report()
			end
			local moving = world(sipworks, { reducedMotion = false })
			local still = world(sipworks, { reducedMotion = true })
			t.expect(same(drive(moving), drive(still))).toBe(true)
			t.expect(still.built.report().task).toBe("done/0/true/true/false")
			moving.stop()
			still.stop()
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local host = engine.new("ScreenGui")
			local baseline = engine.census()
			local built
			local stop, root = runtime.mount(function()
				built = sipworks.build({
					Facet = Facet,
					Compose = Compose,
					runtime = runtime,
					Host = runtime.constructors,
					UI = Facet.controls(runtime, { types = engine.types } :: any),
					types = engine.types,
					viewport = Compose.cell({ width = 1000, height = 720 }),
					heartbeat = engine.heartbeat,
				})
				return built.screen()
			end, host)
			built.steps.order("amber-harvest", "paid")
			engine.heartbeat.fire(0.7)
			t.expect(built.model.order.status:peek()).toBe("rejected")
			stop()
			runtime:dispose()
			t.expect(root.isDestroyed()).toBe(true)
			t.expect(engine.heartbeat.count()).toBe(0)
			t.expect(engine.census().live).toBe(baseline.live)
			t.expect(engine.census().connections).toBe(baseline.connections)
		end)

		t.it("names the task blend on its action, orders that blend and ends the task after the free pour", function()
			local w = world(sipworks)
			local model, steps = w.built.model, w.built.steps
			local task = assert(within(pages(w), "Menu", "Task"))
			t.expect(task.Text).toBe("Order " .. model.catalog.blend(sipTask.FIRST_BLEND).title)
			t.expect(within(pages(w), "Blends", sipTask.FIRST_BLEND, "Open").Text).toBe("Amber Harvest")
			task.Activated.fire()
			t.expect(model.order.blendId:peek()).toBe(sipTask.FIRST_BLEND)
			t.expect(model.order.mode:peek()).toBe("paid")
			t.expect(task.Interactable).toBe(false)
			steps.advance(0.7)
			t.expect(model.task.phase:peek()).toBe("rejected")
			task.Activated.fire()
			steps.advance(0.7)
			t.expect(model.task.phase:peek()).toBe("redeem")
			t.expect(task.Text).toBe("Redeem a " .. model.catalog.blend(sipTask.FREE_POUR_BLEND).title)
			task.Activated.fire()
			t.expect(model.order.blendId:peek()).toBe(sipTask.FREE_POUR_BLEND)
			t.expect(model.order.mode:peek()).toBe("redeem")
			steps.advance(0.7)
			t.expect(model.task.phase:peek()).toBe("done")
			t.expect(model.rewards.unspent()).toBe(0)
			t.expect(task.Interactable).toBe(false)
			t.expect(hasText(w.root, sipStrings.byLocale.en["order.redeemed"])).toBe(true)
			w.stop()
		end)

		t.it("titles the module Sipworks and keeps test vocabulary out of player strings", function()
			t.expect(sipworks.title).toBe("Sipworks")
			local offenders = {}
			for key, value in sipStrings.byLocale.en do
				local forms = if type(value) == "string" then { value } else value
				for _, text in forms do
					if jargon(text) then
						table.insert(offenders, key)
					end
				end
			end
			local w = world(sipworks)
			for _, id in { "menu", "favorites", "rewards", "book" } do
				w.built.model.section:set(id)
				for _, value in texts(w.root) do
					if jargon(value) then
						table.insert(offenders, value)
					end
				end
			end
			t.expect(table.concat(offenders, "; ")).toBe("")
			w.stop()
		end)
		t.it(
			"draws every player-facing string from the locale table and relabels all of them on a locale switch",
			function()
				local w = world(sipworks)
				local model, steps = w.built.model, w.built.steps
				local marks: { [string]: boolean } = {}
				for _, blend in model.catalog.blends do
					marks[sipArt.of("blend", blend.id).mark] = true
				end
				for _, item in model.catalog.botanicals do
					marks[sipArt.of("botanical", item.id).mark] = true
				end
				local function player(value: string): boolean
					return value ~= "" and not marks[value] and string.match(value, "^[%d%s%p]*$") == nil
				end
				local function chrome(node: any): boolean
					local at = node
					while at ~= nil do
						if at.Name == "Close" and at.Parent ~= nil and at.Parent.Name == "Header" then
							return true
						end
						at = at.Parent
					end
					return false
				end
				local function shown(): { [any]: { [string]: string } }
					local out: { [any]: { [string]: string } } = {}
					for _, node in w.screen:GetDescendants() do
						local class = node.ClassName
						if
							(class == "TextLabel" or class == "TextButton" or class == "TextBox") and not chrome(node)
						then
							local entry: { [string]: string } = {}
							if player(node.Text) and class ~= "TextBox" then
								entry.Text = node.Text
							end
							if class == "TextBox" and player(node.PlaceholderText) then
								entry.PlaceholderText = node.PlaceholderText
							end
							if next(entry) ~= nil then
								out[node] = entry
							end
						end
					end
					return out
				end
				local visited = 0
				local function check(state: string)
					local english = shown()
					local count = 0
					for node, entry in english do
						for property, value in entry do
							count += 1
							t.expect(`{state} {node.Name}.{property}: {string.find(value, "[", 1, true) == nil}`)
								.toBe(`{state} {node.Name}.{property}: true`)
						end
					end
					t.expect(count > 0).toBe(true)
					visited += count
					t.expect(steps.locale("xa")).toBe(true)
					local expanded = shown()
					for node, entry in english do
						for property, value in entry do
							local now = node[property]
							local wrapped = string.sub(now, 1, 1) == "[" and string.sub(now, -1) == "]"
							t.expect(`{state} {value} -> {wrapped and now ~= value}`).toBe(`{state} {value} -> true`)
						end
					end
					for node, entry in expanded do
						for property in entry do
							t.expect(`{state} {node.Name}.{property}: {english[node] ~= nil}`)
								.toBe(`{state} {node.Name}.{property}: true`)
						end
					end
					t.expect(steps.locale("en")).toBe(true)
					for node, entry in english do
						for property, value in entry do
							t.expect(node[property]).toBe(value)
						end
					end
				end
				steps.advance(1)
				t.expect(model.unlock.availability:peek()).toBe("available")
				for _, id in { "menu", "favorites", "rewards", "book" } do
					steps.section(id)
					check(id)
				end
				steps.section("menu")
				steps.open("lantern-oolong")
				press(assert(modal(w.screen)), "BlendDetail", "Recipe")
				t.expect(within(assert(modal(w.screen)), "Unlock", "Buy") ~= nil).toBe(true)
				check("locked recipe")
				press(assert(modal(w.screen)), "BlendDetail", "jasmine")
				local card = assert(find(w.screen, "BotanicalCard"))
				check("botanical card")
				press(card, "Flip")
				t.expect(find(card, "MeasuredFacts") ~= nil).toBe(true)
				check("brew facts")
				local panel = card
				while panel.Name ~= "SheetPanel" do
					panel = panel.Parent
				end
				press(panel, "Header", "Close")
				t.expect(find(w.screen, "BotanicalCard")).toBeNil()
				press(assert(modal(w.screen)), "Header", "Close")
				t.expect(modal(w.screen)).toBeNil()
				steps.open("amber-harvest")
				press(assert(modal(w.screen)), "BlendDetail", "Recipe")
				t.expect(find(assert(modal(w.screen)), "assam") ~= nil).toBe(true)
				check("recipe")
				steps.order("amber-harvest", "paid")
				steps.advance(0.7)
				t.expect(hasText(w.root, sipStrings.byLocale.en["notice.rejected"])).toBe(true)
				check("rejected notice")
				steps.order("amber-harvest", "paid")
				check("confirming")
				t.expect(visited > 60).toBe(true)
				w.stop()
			end
		)
	end)

	t.describe("Foyer", function()
		local function pages(w: World): any
			return assert(within(w.root, "Destinations", "Content"))
		end

		local function sectionIds(w: World): { string }
			local out = {}
			local list = assert(within(pages(w), "home", "Sections"))
			local children = {}
			for _, child in list:GetChildren() do
				if child.ClassName == "Frame" then
					table.insert(children, child)
				end
			end
			table.sort(children, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			for _, child in children do
				table.insert(out, child.Name)
			end
			return out
		end

		t.it("docks a wide rail or a compact bottom bar and never remounts the home body", function()
			local w = world(foyer)
			local destinations = assert(find(w.root, "Destinations"))
			local tabs = assert(find(destinations, "Tabs"))
			local V2, E = w.engine.types.Vector2, w.engine.types.Enum
			destinations.AbsoluteSize = V2.new(1200, 800)
			t.expect(tabs.ScrollingDirection).toBe(E.ScrollingDirection.Y)
			t.expect(tabs.Position.Y.Scale).toBe(0)
			local feed = assert(within(pages(w), "home", "Feed"))
			local search = assert(find(feed, "Search"))
			destinations.AbsoluteSize = V2.new(390, 800)
			t.expect(tabs.ScrollingDirection).toBe(E.ScrollingDirection.X)
			t.expect(tabs.Position.Y.Scale).toBe(1)
			t.expect(within(pages(w), "home", "Feed")).toBe(feed)
			t.expect(find(feed, "Search")).toBe(search)
			destinations.AbsoluteSize = V2.new(1200, 800)
			t.expect(within(pages(w), "home", "Feed")).toBe(feed)
			w.stop()
		end)

		t.it("swaps the feed for the charts and shows unopened destinations honestly", function()
			local w = world(foyer)
			local services = w.built.model.services
			local picked = {}
			for _, section in services.sections:peek() do
				table.insert(picked, section.id)
			end
			t.expect(table.concat(sectionIds(w), ",")).toBe(table.concat(picked, ","))
			press(pages(w), "home", "FeedSelection", "charts")
			t.expect(w.built.model.tab:peek()).toBe("charts")
			local charted = {}
			for _, section in services.charted do
				table.insert(charted, section.id)
			end
			t.expect(table.concat(sectionIds(w), ",")).toBe(table.concat(charted, ","))
			local first = services.charted[1]
			local tiles = assert(within(pages(w), "home", "Sections", first.id, "Tiles"))
			local shown = {}
			for _, child in tiles:GetChildren() do
				if child.ClassName == "Frame" then
					table.insert(shown, child)
				end
			end
			table.sort(shown, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			for index, tile in first.tiles do
				t.expect(shown[index].Name).toBe(tile.id)
			end
			press(pages(w), "home", "FeedSelection", "forYou")
			t.expect(table.concat(sectionIds(w), ",")).toBe(table.concat(picked, ","))
			press(assert(within(w.root, "Destinations", "Tabs")), "forge")
			t.expect(w.built.model.destination:peek()).toBe("forge")
			local forge = assert(within(pages(w), "forge", "Forge"))
			t.expect(hasText(forge, foyerStrings.get("en", "stub.honest"))).toBe(true)
			t.expect(find(forge, "Worlds")).toBeNil()
			t.expect(find(forge, "Artwork")).toBeNil()
			for _, node in forge:GetDescendants() do
				t.expect(node.ClassName ~= "TextButton").toBe(true)
			end
			w.stop()
		end)

		t.it("leaves Keep playing untouched and the world open after a rejected visit", function()
			local w = world(foyer)
			local steps, services = w.built.steps, w.built.model.services
			press(pages(w), "home", "Sections", "moss-kingdom", "Open")
			local sheet = assert(modal(w.screen))
			t.expect(hasText(sheet, "Moss Kingdom")).toBe(true)
			local visit = assert(within(sheet, "World", "Visit"))
			t.expect(visit.Text).toBe(foyerStrings.get("en", "detail.visit"))
			steps.reject("visit", "err.generic")
			visit.Activated.fire()
			t.expect(services.visitStatus:peek()).toBe("pending")
			t.expect(visit.Text).toBe(foyerStrings.get("en", "detail.visiting"))
			t.expect(visit.Interactable).toBe(false)
			steps.settle()
			t.expect(services.visitStatus:peek()).toBe("rejected")
			t.expect(next(w.built.report().continued)).toBeNil()
			t.expect(modal(w.screen)).toBe(sheet)
			t.expect(visit.Interactable).toBe(true)
			t.expect(visit.Text).toBe(foyerStrings.get("en", "detail.visit"))
			t.expect(hasText(w.root, foyerStrings.get("en", "err.generic"))).toBe(true)
			visit.Activated.fire()
			steps.settle()
			t.expect(w.built.report().continued["moss-kingdom"]).toBe(true)
			t.expect(hasText(w.root, foyerStrings.get("en", "toast.visited"))).toBe(true)
			w.stop()
		end)

		t.it(
			"clears the bell count, relabels on a locale swap, scripts image transport and stays deterministic",
			function()
				local w = world(foyer)
				local services = w.built.model.services
				local bell = assert(within(pages(w), "home", "Notifications"))
				t.expect(bell.Text).toBe(`{foyerStrings.get("en", "bell.label")} · {#foyerSeed.notices}`)
				t.expect(w.built.report().notices).toBe(#foyerSeed.notices)
				bell.Activated.fire()
				t.expect(services.noticeCount:peek()).toBe(0)
				t.expect(bell.Text).toBe(`{foyerStrings.get("en", "bell.label")} · 0`)
				local sheet = assert(modal(w.screen))
				for _, notice in foyerSeed.notices do
					t.expect(hasText(sheet, notice.bodyKeyless)).toBe(true)
				end
				press(sheet, "Close")
				t.expect(modal(w.screen)).toBeNil()

				local tiles = assert(within(pages(w), "home", "Sections", "picked", "Tiles"))
				local ready = assert(within(tiles, "moss-kingdom", "Artwork"))
				local _, asset = foyerSeed.assetFor("thumb:moss-kingdom")
				t.expect(find(ready, "Image").Visible).toBe(true)
				t.expect(find(ready, "Image").Image).toBe(asset)
				t.expect(find(ready, "Placeholder").Visible).toBe(false)
				local failed = assert(within(tiles, "signal-lost", "Artwork"))
				t.expect(foyerSeed.assetFor("thumb:signal-lost")).toBe(false)
				t.expect(find(failed, "Image").Visible).toBe(false)
				t.expect(find(failed, "Placeholder").Visible).toBe(true)
				t.expect(hasText(failed, "Artwork unavailable")).toBe(true)
				w.built.model.destination:set("crews")
				local friends = assert(within(pages(w), "crews", "Friends"))
				for _, friend in foyerSeed.friends do
					local portrait = assert(within(friends, friend.id, "Artwork"))
					t.expect(find(portrait, "Image").Visible).toBe(foyerSeed.assetFor(friend.portraitKey))
				end
				press(pages(w), "crews", "Invite")
				local invite = assert(modal(w.screen))
				t.expect(invite.Name).toBe("AlertPanel")
				t.expect(hasText(invite, foyerStrings.get("en", "invite.label"))).toBe(true)
				t.expect(hasText(invite, foyerStrings.get("en", "invite.stub"))).toBe(true)
				press(invite, "close")
				t.expect(modal(w.screen)).toBeNil()

				local root = w.root
				local homeTab = assert(within(w.root, "Destinations", "Tabs", "home"))
				local refresh = assert(within(pages(w), "home", "Refresh"))
				t.expect(refresh.Text).toBe(foyerStrings.get("en", "refresh.label"))
				w.built.model.destination:set("you")
				press(pages(w), "you", "Locale", "xa")
				t.expect(w.built.model.locale:peek()).toBe("xa")
				t.expect(refresh.Text).toBe(foyerStrings.get("xa", "refresh.label"))
				t.expect(within(pages(w), "home", "Refresh")).toBe(refresh)
				t.expect(homeTab:GetAttribute("FacetLabel")).toBe(foyerStrings.get("xa", "nav.home"))
				t.expect(w.root).toBe(root)
				t.expect(foyerStrings.get("qq", "nav.home")).toBe("Home")

				local function drive(target: World): any
					local steps = target.built.steps
					steps.search("moss")
					steps.refresh()
					steps.settle()
					steps.open("gloamwood")
					steps.visit("gloamwood")
					steps.settle()
					return target.built.report()
				end
				local a, b = world(foyer), world(foyer)
				t.expect(same(drive(a), drive(b))).toBe(true)
				t.expect(same(a.built.report(), a.built.report())).toBe(true)
				a.stop()
				b.stop()
				w.stop()
				t.expect(root.isDestroyed()).toBe(true)
				t.expect(refresh.isDestroyed()).toBe(true)
			end
		)
	end)

	t.describe("Gallery examples", function()
		local function nativeContext(): (any, any, any)
			local engine: any = engineLib.new()
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
			}
			return ctx, engine, target
		end

		local function mountGallery(kind: string, name: string): (any, any, () -> (), any, any)
			local ctx, engine = nativeContext()
			local path = if kind == "example" then "examples/" else "scenarios/"
			local built
			local host = engine.new("ScreenGui")
			local stop, node = ctx.runtime.mount(function()
				gallery.configure(ctx)
				ctx.UI = Facet.controls(
					ctx.runtime,
					{
						types = engine.types,
						viewport = ctx.viewport,
						guiService = ctx.guiService,
						reducedMotion = ctx.reducedMotion,
					} :: any
				)
				built = (require :: any)("../examples/gallery/" .. path .. name).build(ctx)
				if built.dispose then
					Compose.cleanup(built.dispose)
				end
				return built.screen()
			end, host)
			return built, node, function()
				stop()
				ctx.runtime:dispose()
			end, ctx, engine
		end

		t.it("converts only numeric Fahrenheit, previews live and commits on Enter or focus loss", function()
			local built, node, stop = mountGallery("example", "01_temperature_converter")
			local editor = assert(find(node, "Fahrenheit"))
			t.expect(editor.ClassName).toBe("TextBox")
			t.expect(find(node, "Preview").Text).toBe("Preview: —")
			t.expect(find(node, "Result").Text).toBe("Result: —")
			editor:CaptureFocus()
			editor.Text = "212"
			t.expect(built.fahrenheitText()).toBe("212")
			t.expect(find(node, "Preview").Text).toBe("Preview: 100 °C  (live, as you type)")
			t.expect(find(node, "Result").Text).toBe("Result: —")
			editor.Text = "21a"
			t.expect(editor.Text).toBe("212")
			t.expect(built.fahrenheitText()).toBe("212")
			t.expect(find(node, "Preview").Text).toBe("Preview: 100 °C  (live, as you type)")
			editor:ReleaseFocus(true)
			t.expect(find(node, "Result").Text).toBe("Result: 100 °C")
			editor:CaptureFocus()
			editor.Text = "-40"
			t.expect(find(node, "Result").Text).toBe("Result: 100 °C")
			t.expect(find(node, "Preview").Text).toBe("Preview: -40 °C  (live, as you type)")
			editor:ReleaseFocus(false)
			t.expect(find(node, "Result").Text).toBe("Result: -40 °C")
			press(node, "Clear")
			t.expect(editor.Text).toBe("")
			t.expect(find(node, "Preview").Text).toBe("Preview: —")
			t.expect(find(node, "Result").Text).toBe("Result: —")
			for _, child in node:GetDescendants() do
				t.expect(child.Name ~= "Convert" and child.Name ~= "Increase").toBe(true)
			end
			stop()
		end)

		t.it("reaches every sync state through its controls and keeps a bounded newest-first history", function()
			local built, node, stop = mountGallery("example", "03_settings_sync")
			local function history(): string
				return find(node, "History").Text
			end
			t.expect(find(node, "Status").Text).toBe("idle")
			press(node, "Deliver")
			t.expect(history()).toBe("Nothing to deliver. Send a change first.\nReady. Nothing sent yet.")
			t.expect(find(node, "Status").Text).toBe("idle")
			press(node, "Music")
			t.expect(find(node, "Status").Text).toBe("pending")
			t.expect(find(node, "Draft").Text).toBe("What you see now: music on, volume 10")
			t.expect(string.find(find(node, "Confirmed").Text, "music off", 1, true) ~= nil).toBe(true)
			press(node, "Music")
			t.expect(find(node, "Status").Text).toBe("pending")
			t.expect(string.sub(history(), 1, 45)).toBe("Already waiting for a reply. Deliver it first")
			t.expect(built.report().draft.music).toBe(true)
			press(node, "Deliver")
			t.expect(find(node, "Status").Text).toBe("confirmed")
			t.expect(find(node, "Confirmed").Text).toBe("Server confirmed: music on, volume 10 (revision 2)")
			press(node, "Invalid")
			t.expect(find(node, "Draft").Text).toBe("What you see now: music on, volume 99")
			press(node, "Deliver")
			t.expect(find(node, "Status").Text).toBe("rejected")
			t.expect(find(node, "Draft").Text).toBe("What you see now: music on, volume 10")
			t.expect(string.sub(history(), 1, 22)).toBe("Server rejected volume")
			local lines = string.split(history(), "\n")
			t.expect(#lines).toBe(3)
			t.expect(lines[2]).toBe("Sent settings. Waiting for the server.")
			press(node, "Volume", "Decrease")
			t.expect(find(node, "Status").Text).toBe("pending")
			press(node, "Reset")
			t.expect(find(node, "Status").Text).toBe("idle")
			t.expect(history()).toBe("Reset. Nothing sent yet.")
			t.expect(find(node, "Draft").Text).toBe("What you see now: music off, volume 10")
			press(node, "Deliver")
			t.expect(string.sub(history(), 1, 19)).toBe("Nothing to deliver.")
			for _ = 1, 10 do
				press(node, "Music")
				press(node, "Deliver")
			end
			t.expect(#string.split(history(), "\n")).toBe(3)
			t.expect(string.split(history(), "\n")[1]).toBe("Server accepted. Both readouts agree.")
			stop()
		end)

		t.it("confirms or keeps a deletion through one dialog and restores the save", function()
			local built, node, stop = mountGallery("example", "04_confirm_dialog")
			local host = node.Parent
			local function dialogs(): number
				local count = 0
				for _, child in host:GetDescendants() do
					if child.Name == "AlertPanel" then
						count += 1
					end
				end
				return count
			end
			local delete = assert(find(node, "Delete"))
			delete.Activated.fire()
			delete.Activated.fire()
			t.expect(dialogs()).toBe(1)
			press(host, "AlertPanel", "Cancel")
			t.expect(dialogs()).toBe(0)
			t.expect(find(node, "Outcome").Text).toBe("Kept. Nothing was deleted.")
			t.expect(built.hasSave()).toBe(true)
			delete.Activated.fire()
			press(host, "AlertPanel", "Confirm")
			t.expect(dialogs()).toBe(0)
			t.expect(find(node, "Outcome").Text).toBe("Deleted. The slot is empty now.")
			t.expect(find(node, "Title").Text).toBe("Save Slot 1 — empty")
			t.expect(delete.Interactable).toBe(false)
			delete.Activated.fire()
			t.expect(dialogs()).toBe(0)
			press(node, "Restore")
			t.expect(built.hasSave()).toBe(true)
			t.expect(find(node, "Outcome").Text).toBe("This slot holds a save. Deleting it cannot be undone.")
			t.expect(delete.Interactable).toBe(true)
			delete.Activated.fire()
			t.expect(dialogs()).toBe(1)
			stop()
		end)

		t.it("disables a spent rack slot instead of leaving a live blank button", function()
			local built, node, stop = mountGallery("example", "06_tile_game")
			local slot = assert(find(node, "rt1"))
			local letter = built.rackLetter(1)
			t.expect(slot.Text).toBe(letter)
			t.expect(slot.Interactable).toBe(true)
			slot.Activated.fire()
			press(node, "cell4_4", "tap")
			t.expect(built.pendingAt(4, 4)).toBe(letter)
			t.expect(slot.Text).toBe("·")
			t.expect(slot.Interactable).toBe(false)
			slot.Activated.fire()
			t.expect(built.selected()).toBeNil()
			built.undo()
			t.expect(slot.Text).toBe(letter)
			t.expect(slot.Interactable).toBe(true)
			stop()
		end)

		t.it("deals match-three boards with no opening run, a legal move and five distinct tile arts", function()
			local built, _, stop = mountGallery("example", "07_match3")
			local function runs(): number
				local found = 0
				for r = 1, built.rows do
					for c = 1, built.cols do
						local kind = built.kindAt(r, c)
						if
							c + 2 <= built.cols
							and built.kindAt(r, c + 1) == kind
							and built.kindAt(r, c + 2) == kind
						then
							found += 1
						end
						if
							r + 2 <= built.rows
							and built.kindAt(r + 1, c) == kind
							and built.kindAt(r + 2, c) == kind
						then
							found += 1
						end
					end
				end
				return found
			end
			local opening = table.concat(built.boardSnapshot(), ",")
			for _ = 1, 20 do
				t.expect(runs()).toBe(0)
				t.expect(next(built.findMatches()) == nil).toBe(true)
				t.expect(built.hasLegalMove()).toBe(true)
				built.reset()
				t.expect(table.concat(built.boardSnapshot(), ",")).toBe(opening)
			end
			local kinds, images = {}, {}
			for _, kind in built.boardSnapshot() do
				kinds[kind] = true
			end
			local count = 0
			for kind in kinds do
				count += 1
				local image = galleryAssets.match3Tiles[kind].image
				t.expect(type(image) == "string" and image ~= "").toBe(true)
				t.expect(images[image]).toBeNil()
				images[image] = true
			end
			t.expect(count).toBe(5)
			stop()
		end)

		t.it("explains a non-adjacent tap, refuses taps while resolving and resets to the opening values", function()
			local built, node, stop, _, engine = mountGallery("example", "07_match3")
			local function hit(r: number, c: number): any
				return assert(within(node, "tile" .. built.tileIdAt(r, c), "hit"))
			end
			local function picked(): number
				local count = 0
				for _, child in node:GetDescendants() do
					if child.Name == "Selection" and child.Transparency == 0 then
						count += 1
					end
				end
				return count
			end
			hit(1, 1).Activated.fire()
			t.expect(picked()).toBe(1)
			hit(3, 3).Activated.fire()
			t.expect(string.find(built.hintText(), "have to touch", 1, true) ~= nil).toBe(true)
			t.expect(picked()).toBe(1)
			t.expect(built.moves()).toBe(0)
			hit(3, 3).Activated.fire()
			t.expect(picked()).toBe(0)
			built.swap(1, 1, 1, 2)
			t.expect(built.isResolving()).toBe(true)
			local moves, score = built.moves(), built.score()
			hit(4, 4).Activated.fire()
			t.expect(built.hintText()).toBe("The board is still settling — wait for the tiles to land.")
			t.expect(picked()).toBe(0)
			t.expect(built.moves()).toBe(moves)
			t.expect(built.score()).toBe(score)
			press(node, "Reset")
			t.expect(built.isResolving()).toBe(false)
			t.expect(built.score()).toBe(0)
			t.expect(built.moves()).toBe(0)
			t.expect(built.tickHookActive()).toBe(false)
			t.expect(picked()).toBe(0)
			for index = 1, 30 do
				if index % 2 == 0 then
					press(node, "Reset")
				else
					hit(2, 2).Activated.fire()
				end
				engine.heartbeat.fire(1 / 60)
			end
			press(node, "Reset")
			t.expect(picked()).toBe(0)
			t.expect(built.moves()).toBe(0)
			t.expect(built.hintText())
				.toBe("Drag a tile onto a neighbor, or select two neighboring tiles. Three in a row clears.")
			stop()
		end)

		t.it("edits the consumer's caller-owned Sound value through its toggle", function()
			local ctx, _, target = nativeContext()
			local stop, node = ctx.runtime.mount(function()
				local UI = Facet.controls(ctx.runtime, { types = ctx.types })
				return require("../examples/consumer/src/screen").build(Facet, UI)
			end, target)
			local sound = assert(find(node, "Sound"))
			local indicator = assert(find(sound, "Indicator"))
			t.expect(indicator:GetAttribute("selected")).toBe(true)
			sound.Activated.fire()
			t.expect(indicator:GetAttribute("selected")).toBe(false)
			sound.Activated.fire()
			t.expect(indicator:GetAttribute("selected")).toBe(true)
			press(node, "Bump")
			press(node, "Bump")
			t.expect(find(node, "Count").Text).toBe("2 taps")
			t.expect(indicator:GetAttribute("selected")).toBe(true)
			stop()
			ctx.runtime:dispose()
		end)
	end)

	t.describe("Gallery shell", function()
		local function shell(demos: { any }, load: (string, string) -> any, native: boolean?): (any, any, () -> ())
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local target, gui = engine.new("Folder"), engine.new("GuiService")
			gui.ReducedMotionEnabled = native == true
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
				selection = Compose.cell(demos[1].id),
				theme = Compose.cell(Facet.themes.neutralPackage()),
				themeMode = Compose.cell("light"),
				demos = demos,
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

		local function two(): { any }
			return {
				{ id = "first", title = "First", kind = "fixture", module = "first" },
				{ id = "second", title = "Second", kind = "fixture", module = "second" },
			}
		end

		t.it("boots a scenario over an example over a demo and the default demo without attributes", function()
			t.expect(gallery.boot).toBe(catalogue.boot)
			local id, extra = catalogue.boot("hud", "outpost_terminal", 2)
			t.expect(id).toBe("outpost_terminal")
			t.expect(extra.kind).toBe("fixture")
			t.expect(extra.module).toBe("outpost_terminal")
			id, extra = catalogue.boot("hud", nil, 5)
			t.expect(id).toBe("05_word_game")
			t.expect(extra.kind).toBe("example")
			t.expect(extra.module).toBe("05_word_game")
			id, extra = catalogue.boot("hud", "", 2)
			t.expect(id).toBe("02_playlist_table")
			t.expect(extra.kind).toBe("example")
			id, extra = catalogue.boot("hud", nil, nil)
			t.expect(id).toBe("hud")
			t.expect(extra).toBeNil()
			id, extra = catalogue.boot(nil, nil, nil)
			t.expect(id).toBe("all-controls")
			t.expect(extra).toBeNil()
			id, extra = catalogue.boot(nil, nil, 99)
			t.expect(id).toBe("all-controls")
			t.expect(extra).toBeNil()
			for index, name in
				{
					"01_temperature_converter",
					"02_playlist_table",
					"03_settings_sync",
					"04_confirm_dialog",
					"05_word_game",
					"06_tile_game",
					"07_match3",
				}
			do
				t.expect((catalogue.boot(nil, nil, index))).toBe(name)
				t.expect(fs.isFile(`examples/gallery/examples/{name}.luau`)).toBe(true)
			end
			local client = fs.readFile("examples/gallery/client/init.client.luau")
			t.expect(string.find(client, "gallery.boot(", 1, true) ~= nil).toBe(true)
			for _, attribute in { "Facet_Demo", "Facet_Scenario", "Facet_Example" } do
				t.expect(string.find(client, `"{attribute}"`, 1, true) ~= nil).toBe(true)
			end
		end)

		t.it("stamps a demo that cannot build and does not report it mounted", function()
			local ctx, root, stop = shell(two(), function(_, name)
				if name == "second" then
					return {
						build = function()
							error("second is broken")
						end,
					}
				end
				return {
					build = function(page)
						return {
							screen = function()
								return page.Host.Frame({ Name = name })
							end,
							report = function()
								return { name = name }
							end,
						}
					end,
				}
			end)
			local first = gallery.dispatch(ctx, "report")
			t.expect(first.mounted).toBe("first")
			t.expect(first.error).toBeNil()
			t.expect(first.demo.name).toBe("first")
			local result = gallery.dispatch(ctx, "show", "second")
			t.expect(result.ok).toBe(true)
			t.expect(result.current).toBe("second")
			t.expect(result.mounted).toBeNil()
			t.expect(string.find(tostring(result.error), "second is broken", 1, true) ~= nil).toBe(true)
			t.expect(ctx.errorMessage:peek()).toBe(result.error)
			local failure = assert(find(root, "DemoFailure"))
			t.expect(string.find(failure.Text, "Second could not load", 1, true)).toBe(1)
			t.expect(gallery.dispatch(ctx, "report").demo).toBeNil()
			local back = gallery.dispatch(ctx, "show", "first")
			t.expect(back.mounted).toBe("first")
			t.expect(back.error).toBeNil()
			t.expect(find(root, "DemoFailure")).toBeNil()
			stop()
		end)

		t.it("keeps the chosen motion setting across a demo swap", function()
			local pages = {}
			local ctx, root, stop = shell(two(), function(_, name)
				return {
					build = function(page)
						pages[name] = page
						return {
							screen = function()
								return page.Host.Frame({ Name = name })
							end,
						}
					end,
				}
			end)
			t.expect(ctx.reducedMotion:peek()).toBe(false)
			press(root, "Settings")
			local motion = assert(find(root, "Motion"))
			press(motion, "reduced")
			t.expect(ctx.reducedMotion:peek()).toBe(true)
			t.expect(ctx.motionMode:peek()).toBe("reduced")
			t.expect(find(motion, "reduced"):GetAttribute("selected")).toBe(true)
			gallery.dispatch(ctx, "show", "second")
			t.expect(ctx.active:peek()).toBe("second")
			t.expect(ctx.reducedMotion:peek()).toBe(true)
			t.expect(pages.second.reducedMotion:peek()).toBe(true)
			t.expect(ctx.motionMode:peek()).toBe("reduced")
			t.expect(find(motion, "reduced"):GetAttribute("selected")).toBe(true)
			press(root, "FollowRobloxMotion")
			t.expect(ctx.reducedMotion:peek()).toBe(false)
			t.expect(pages.second.reducedMotion:peek()).toBe(false)
			stop()
		end)

		t.it("releases a presenting demo's resources after its tree and exactly once per build", function()
			local builds, disposals, order = 0, 0, {}
			local tree: any = nil
			local ctx, root, stop = shell(two(), function(_, name)
				return {
					build = function(page)
						if name ~= "first" then
							return {
								screen = function()
									return page.Host.Frame({ Name = name })
								end,
							}
						end
						builds += 1
						local panel
						return {
							screen = function()
								return page.Host.Frame "Presenting" {
									page.UI.Alert "Notice" {
										isPresented = Compose.cell(true),
										title = "Notice",
										message = "Presented by the demo",
										actions = { { id = "ok", label = "OK", role = "cancel" } },
										ref = function()
											panel = true
										end,
									},
								}
							end,
							dispose = function()
								disposals += 1
								local open = false
								for _, node in tree:GetDescendants() do
									if node.Name == "AlertPanel" then
										open = true
									end
								end
								table.insert(order, if open then "tree-alive" else "tree-gone")
								t.expect(panel).toBe(true)
							end,
						}
					end,
				}
			end)
			tree = root
			t.expect(find(root, "AlertPanel") ~= nil).toBe(true)
			gallery.dispatch(ctx, "show", "second")
			t.expect(find(root, "AlertPanel")).toBeNil()
			t.expect(disposals).toBe(1)
			gallery.dispatch(ctx, "show", "first")
			t.expect(builds).toBe(2)
			t.expect(find(root, "AlertPanel") ~= nil).toBe(true)
			stop()
			t.expect(disposals).toBe(2)
			t.expect(table.concat(order, ",")).toBe("tree-gone,tree-gone")
			t.expect(ctx.errorMessage:peek()).toBeNil()
		end)

		t.it("steps through the demo list in both directions and wraps", function()
			local list = catalogue.list()
			t.expect(#list > 2).toBe(true)
			t.expect(catalogue.next(list[#list].id)).toBe(list[1].id)
			t.expect(catalogue.next(list[1].id, -1)).toBe(list[#list].id)
			local at = list[1].id
			for _ = 1, #list do
				at = catalogue.next(at)
			end
			t.expect(at).toBe(list[1].id)
			for _ = 1, #list do
				at = catalogue.next(at, -1)
			end
			t.expect(at).toBe(list[1].id)
			local fallback = catalogue.next("missing")
			local listed = false
			for _, demo in list do
				listed = listed or demo.id == fallback
			end
			t.expect(listed).toBe(true)
			local ctx, _, stop = shell(two(), function(_, name)
				return {
					build = function(page)
						return {
							screen = function()
								return page.Host.Frame({ Name = name })
							end,
						}
					end,
				}
			end)
			t.expect(gallery.dispatch(ctx, "next", -1).current).toBe("second")
			t.expect(gallery.dispatch(ctx, "next").current).toBe("first")
			t.expect(gallery.dispatch(ctx, "next", 3).current).toBe("second")
			t.expect(ctx.active:peek()).toBe("second")
			stop()
		end)
	end)

	t.describe("Gallery recipes", function()
		local function recipe(name: string): (any, any, () -> (), any, any)
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local target, gui = engine.new("Folder"), engine.new("GuiService")
			local input = engine.new("UserInputService")
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
				worldTarget = engine.new("Folder"),
				guiService = gui,
				runService = { Heartbeat = engine.heartbeat },
			}
			local built
			local stop, node = runtime.mount(function()
				gallery.configure(ctx)
				ctx.UI = Facet.controls(
					runtime,
					{
						types = engine.types,
						viewport = ctx.viewport,
						guiService = gui,
						services = { GuiService = gui, UserInputService = input },
						reducedMotion = ctx.reducedMotion,
					} :: any
				)
				built = (require :: any)("../examples/gallery/scenarios/" .. name).build(ctx)
				if built.dispose then
					Compose.cleanup(built.dispose)
				end
				return built.screen()
			end, engine.new("ScreenGui"))
			return built, node, function()
				stop()
				runtime:dispose()
			end, ctx, engine
		end

		local function picker(node: any, name: string): any
			for _, child in node:GetDescendants() do
				if child.Name == name and child.ClassName == "Frame" and child:FindFirstChild("Presentation") then
					return child
				end
			end
			error(`no picker {name}`)
		end

		local function avatars(node: any): { [string]: any }
			local out = {}
			for _, child in node:GetDescendants() do
				if child:HasTag("facet-avatar") then
					out[child.Name] = child
				end
			end
			return out
		end

		t.it("drives the avatar recipe through pending, failure, presence and size rungs", function()
			local built, node, stop = recipe("avatar")
			local portrait = assert(avatars(node).Portrait)
			t.expect(built.report().state).toBe("ready")
			t.expect(built.report().imageMounted).toBe(true)
			local pending = built.steps.pending()
			t.expect(pending.state).toBe("loading")
			t.expect(pending.imageMounted).toBe(false)
			local failed = built.steps.fail()
			t.expect(failed.state).toBe("failed")
			t.expect(failed.imageMounted).toBe(false)
			t.expect(find(portrait, "Initials").Text).toBe("AQ")
			t.expect(built.steps.ready().state).toBe("ready")
			t.expect(find(portrait, "Image").Visible).toBe(true)
			t.expect(portrait:GetAttribute("AccessibleLabel")).toBe("Ada Quill, online")
			t.expect(built.steps.presence().presence).toBe("away")
			t.expect(portrait:GetAttribute("AccessibleLabel")).toBe("Ada Quill, away")
			t.expect(find(portrait, "Presence") ~= nil).toBe(true)
			t.expect(built.steps.busy().presence).toBe("busy")
			t.expect(built.steps.offline().presence).toBe("offline")
			t.expect(portrait:GetAttribute("AccessibleLabel")).toBe("Ada Quill, offline")
			t.expect(built.steps.compact().controlSize).toBe("compact")
			t.expect(portrait.Size.X.Offset).toBe(36)
			t.expect(avatars(node).Initials.Size.X.Offset).toBe(36)
			t.expect(built.steps.large().controlSize).toBe("large")
			t.expect(portrait.Size.X.Offset).toBe(56)
			t.expect(avatars(node).Initials:FindFirstChild("Initials").Text).toBe("ÉN")
			portrait.Activated.fire()
			t.expect(built.report().activations).toBe(1)
			built.reset()
			t.expect(same(built.report(), {
				state = "ready",
				imageMounted = true,
				presence = "online",
				controlSize = "regular",
				activations = 0,
			})).toBe(true)
			t.expect(portrait.Size.X.Offset > 36 and portrait.Size.X.Offset < 56).toBe(true)
			stop()
			t.expect(portrait.isDestroyed()).toBe(true)
		end)

		t.it("drives the avatar group recipe and resets the identity tab through its shared command", function()
			local built, node, stop = recipe("avatar_group")
			local function team(): any
				return assert(find(node, "Team"))
			end
			local function overflow(): string
				return find(team(), "Overflow").Text
			end
			t.expect(built.report().count).toBe(6)
			t.expect(built.report().hidden).toBe(2)
			t.expect(overflow()).toBe("+2")
			local bo = avatars(team()).bo
			built.steps.reorder()
			t.expect(avatars(team()).bo).toBe(bo)
			local fewer = built.steps.fewer()
			t.expect(fewer.count).toBe(5)
			t.expect(fewer.hidden).toBe(1)
			t.expect(overflow()).toBe("+1")
			t.expect(built.steps.compact().controlSize).toBe("compact")
			t.expect(avatars(team()).bo.Size.X.Offset).toBe(36)
			t.expect(built.steps.large().controlSize).toBe("large")
			t.expect(avatars(team()).bo.Size.X.Offset).toBe(56)
			t.expect(built.steps.spread().variant).toBe("spread")
			t.expect(built.steps.ellipsis().variant).toBe("ellipsis")
			t.expect(overflow() ~= "+1").toBe(true)
			find(team(), "Overflow").Activated.fire()
			t.expect(built.report().activations).toBe(1)
			local restored = built.steps.restore()
			t.expect(restored.count).toBe(6)
			t.expect(restored.hidden).toBe(2)
			stop()

			local identity, root, stopIdentity = recipe("identity")
			local report = identity.report()
			t.expect(report.avatar.presence).toBe("online")
			t.expect(report.group.count).toBe(6)
			press(picker(root, "Picture"), "failed")
			press(picker(root, "Presence"), "busy")
			press(root, "RosterActions", "Fewer")
			press(picker(root, "Layout"), "spread")
			local changed = identity.report()
			t.expect(changed.avatar.state).toBe("failed")
			t.expect(changed.avatar.presence).toBe("busy")
			t.expect(changed.group.count).toBe(5)
			t.expect(changed.group.variant).toBe("spread")
			local face = avatars(root).Portrait
			press(root, "Reset")
			local after = identity.report()
			t.expect(after.avatar.presence).toBe("online")
			t.expect(after.avatar.state).toBe("ready")
			t.expect(same(after.group, report.group)).toBe(true)
			t.expect(avatars(root).Portrait).toBe(face)
			stopIdentity()
		end)

		t.it("drives the badge recipe through its statuses and rungs and resets the status tab", function()
			local built, node, stop = recipe("badge")
			local standard = assert(find(node, "Standard"))
			local icon = assert(standard:FindFirstChildWhichIsA("ImageLabel"))
			t.expect(standard:HasTag("facet-status-neutral")).toBe(true)
			for _, word in { "warning", "error", "neutral" } do
				t.expect(built.steps[word]().status).toBe(word)
				t.expect(standard:HasTag("facet-status-" .. word)).toBe(true)
				t.expect(find(node, "Media"):HasTag("facet-status-" .. word)).toBe(true)
				t.expect(standard:FindFirstChildWhichIsA("ImageLabel")).toBe(icon)
			end
			t.expect(standard:HasTag("facet-status-warning")).toBe(false)
			t.expect(find(node, "Utility"):HasTag("facet-badge-utility")).toBe(true)
			t.expect(within(node, "Marked", "Status") ~= nil).toBe(true)
			local compact = standard.Size.Y.Offset
			press(picker(node, "Size"), "large")
			t.expect(built.report().controlSize).toBe("large")
			t.expect(standard.Size.Y.Offset > compact).toBe(true)
			stop()

			local family, root, stopFamily = recipe("status_family")
			local initial = family.report()
			press(picker(find(root, "BadgeRecipe"), "Status"), "error")
			press(root, "StatusRecipe", "More")
			t.expect(family.report().badge.status).toBe("error")
			t.expect(family.report().status.count).toBe(25)
			local count = assert(within(root, "Live", "Count"))
			press(root, "Content", "Reset")
			t.expect(same(family.report(), initial)).toBe(true)
			t.expect(within(root, "Live", "Count")).toBe(count)
			stopFamily()
		end)

		t.it("drives the skeleton recipe through silhouettes, branches and motion and releases its clock", function()
			local built, node, stop, ctx, engine = recipe("skeleton")
			local pending = assert(find(node, "Pending"))
			t.expect(find(pending, "Placeholders") ~= nil).toBe(true)
			t.expect(within(pending, "First", "Card") ~= nil).toBe(true)
			t.expect(find(pending, "Face") ~= nil).toBe(true)
			t.expect(find(pending, "Copy") ~= nil).toBe(true)
			t.expect(engine.heartbeat.count() > 0).toBe(true)
			t.expect(built.steps.removeFirst().first).toBe(false)
			t.expect(within(pending, "First", "Card")).toBeNil()
			t.expect(find(pending, "Face") ~= nil).toBe(true)
			t.expect(built.steps.restoreFirst().first).toBe(true)
			t.expect(within(pending, "First", "Card") ~= nil).toBe(true)
			t.expect(built.steps.reduced().reduced).toBe(true)
			t.expect(ctx.reducedMotion:peek()).toBe(true)
			press(node, "Animate")
			t.expect(built.report().reduced).toBe(false)
			press(node, "Reduce")
			t.expect(built.report().reduced).toBe(true)
			t.expect(built.steps.full().reduced).toBe(false)
			local loaded = built.steps.loaded()
			t.expect(loaded.loading).toBe(false)
			t.expect(find(pending, "Placeholders")).toBeNil()
			t.expect(hasText(pending, "Your next race is ready.")).toBe(true)
			t.expect(built.steps.loading().loading).toBe(true)
			built.reset()
			t.expect(same(built.report(), { loading = true, first = true, reduced = false })).toBe(true)
			stop()
			t.expect(engine.heartbeat.count()).toBe(0)
		end)

		t.it("drives the status indicator recipe through count caps and shapes", function()
			local built, node, stop = recipe("status_indicator")
			local count = assert(within(node, "Live", "Count"))
			local cutout = assert(within(node, "Live", "Cutout"))
			t.expect(same(built.report(), { count = 0, form = "dot", status = "neutral" })).toBe(true)
			press(node, "Live", "More")
			t.expect(built.report().count).toBe(25)
			t.expect(count.Text).toBe("25")
			t.expect(built.steps.capped().count > 99).toBe(true)
			t.expect(count.Text).toBe("99+")
			t.expect(cutout:HasTag("facet-status-hollow")).toBe(false)
			t.expect(built.steps.ring().form).toBe("ring")
			t.expect(cutout:HasTag("facet-status-hollow")).toBe(true)
			t.expect(within(node, "Shapes", "ring", "Mark"):HasTag("facet-status-hollow")).toBe(true)
			t.expect(within(node, "Shapes", "dot", "Mark"):HasTag("facet-status-hollow")).toBe(false)
			t.expect(built.steps.error().status).toBe("error")
			t.expect(count:HasTag("facet-status-error")).toBe(true)
			press(node, "Live", "Reset")
			t.expect(built.report().count).toBe(0)
			t.expect(count.Text ~= "99+").toBe(true)
			built.reset()
			t.expect(same(built.report(), { count = 0, form = "dot", status = "neutral" })).toBe(true)
			t.expect(count:HasTag("facet-status-neutral")).toBe(true)
			stop()
		end)

		t.it("drives the shortcut hint recipe through rungs, a localized separator and live rebinding", function()
			local built, node, stop, ctx = recipe("shortcut_hint")
			local explicit = assert(find(node, "Explicit"))
			t.expect(explicit.Text).toBe("K or F1")
			t.expect(built.steps.localize().binding).toBeNil()
			t.expect(explicit.Text).toBe("K ou F1")
			local regular = explicit.Size.Y.Offset
			t.expect(built.steps.compact().controlSize).toBe("compact")
			local compact = explicit.Size.Y.Offset
			t.expect(built.steps.large().controlSize).toBe("large")
			t.expect(compact < regular and regular < explicit.Size.Y.Offset).toBe(true)
			t.expect(built.steps.rename().title).toBe("Lap saved")
			t.expect(hasText(find(node, "BoundLabel"), "Lap saved") or find(node, "BoundLabel").Text == "Lap saved")
				.toBe(true)
			local custom = assert(find(ctx.inputTarget, "RecipeCommand"))
			local hint = assert(find(node, "Custom"))
			t.expect(custom:FindFirstChildWhichIsA("InputBinding")).toBeNil()
			t.expect(built.steps.rebind().binding).toBe("R")
			local binding = assert(custom:FindFirstChildWhichIsA("InputBinding"))
			t.expect(binding.KeyCode).toBe(ctx.types.Enum.KeyCode.R)
			custom.PreferredBinding = binding
			t.expect(within(hint, "PreferredBinding", "Key").Text).toBe("R")
			t.expect(built.steps.bind().binding).toBe("Return")
			t.expect(custom:FindFirstChildWhichIsA("InputBinding")).toBe(binding)
			t.expect(within(hint, "PreferredBinding", "Key").Text).toBe("Enter")
			press(node, "Bindings", "Rebind")
			t.expect(within(hint, "PreferredBinding", "Key").Text).toBe("R")
			press(node, "Bindings", "Unbind")
			t.expect(built.report().binding).toBeNil()
			t.expect(custom:FindFirstChildWhichIsA("InputBinding")).toBeNil()
			custom.PreferredBinding = nil
			t.expect(find(hint, "PreferredBinding")).toBeNil()
			press(node, "OpenGuide")
			t.expect(built.report().guideVisible).toBe(true)
			t.expect(find(node, "GuideText") ~= nil).toBe(true)
			built.reset()
			t.expect(explicit.Text).toBe("K or F1")
			t.expect(find(node, "GuideText")).toBeNil()
			stop()
		end)
	end)

	t.describe("Gallery layouts", function()
		local function scenario(name: string): (any, any, () -> (), any)
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local viewport = Compose.cell({ width = 1280, height = 720 })
			local ctx: { [string]: any } = {
				Facet = Facet,
				Compose = Compose,
				runtime = runtime,
				Host = runtime.constructors,
				types = engine.types,
				viewport = viewport,
				inputTarget = engine.new("Folder"),
				worldTarget = engine.new("Folder"),
				runService = { Heartbeat = engine.heartbeat },
				UI = Facet.controls(runtime, { types = engine.types, viewport = viewport } :: any),
			}
			local built
			local stop, node = runtime.mount(function()
				built = (require :: any)("../examples/gallery/scenarios/" .. name).build(ctx)
				return built.screen()
			end, engine.new("ScreenGui"))
			return built, node, function()
				stop()
				runtime:dispose()
			end, engine
		end

		t.it("slides the card rail window along X when the engine scrolls sideways", function()
			local built, node, stop, engine = scenario("card_rail")
			local V2 = engine.types.Vector2
			local rail = assert(find(node, "Rail"))
			rail.AbsoluteSize = V2.new(400, 300)
			rail.AbsoluteWindowSize = V2.new(400, 300)
			local weekend = built.report().rails.WeekendRail
			local before = built.report().rails.Rail
			t.expect(before.status.direction).toBe("horizontal")
			t.expect(before.status.first).toBe(1)
			t.expect(find(rail, "Card_c1") ~= nil).toBe(true)
			local extent = before.itemExtent + 8
			rail.CanvasPosition = V2.new(extent * 15, 0)
			local after = built.report().rails.Rail
			t.expect(after.offset).toBe(extent * 15)
			t.expect(after.status.first > before.status.first).toBe(true)
			t.expect(after.status.first <= 16 and after.status.last >= 16).toBe(true)
			t.expect(find(rail, "Card_c1")).toBeNil()
			t.expect(find(rail, "Card_c16") ~= nil).toBe(true)
			t.expect(after.status.retained < 12).toBe(true)
			t.expect(same(built.report().rails.WeekendRail, weekend)).toBe(true)
			press(rail, "Card_c16")
			t.expect(built.report().selectedKey).toBe("c16")
			t.expect(hasText(node, "Selected: Livery 016 · Rally")).toBe(true)
			stop()
		end)

		t.it("flips wrapping on the same tag nodes and aligns only the block", function()
			local built, node, stop, engine = scenario("flow_wrap")
			local E = engine.types.Enum
			local cloud = assert(find(node, "Cloud"))
			local block = assert(find(node, "AlignBox"))
			local tags = cloud:GetChildren()
			local shorts = block:GetChildren()
			local cloudLayout = assert(cloud:FindFirstChildWhichIsA("UIListLayout"))
			local blockLayout = assert(block:FindFirstChildWhichIsA("UIListLayout"))
			t.expect(cloudLayout.Wraps).toBe(true)
			press(node, "WrapToggle")
			t.expect(built.report().wrap).toBe(false)
			t.expect(cloudLayout.Wraps).toBe(false)
			t.expect(blockLayout.Wraps).toBe(true)
			local after = cloud:GetChildren()
			t.expect(#after).toBe(#tags)
			for index, child in tags do
				t.expect(after[index]).toBe(child)
			end
			press(node, "WrapToggle")
			t.expect(cloudLayout.Wraps).toBe(true)
			t.expect(blockLayout.HorizontalAlignment).toBe(E.HorizontalAlignment.Left)
			press(node, "BlockAlign", "end")
			t.expect(built.report().align).toBe("end")
			t.expect(blockLayout.HorizontalAlignment).toBe(E.HorizontalAlignment.Right)
			t.expect(cloudLayout.HorizontalAlignment).toBe(E.HorizontalAlignment.Left)
			press(node, "BlockAlign", "center")
			t.expect(blockLayout.HorizontalAlignment).toBe(E.HorizontalAlignment.Center)
			local now = block:GetChildren()
			for index, child in shorts do
				t.expect(now[index]).toBe(child)
			end
			stop()
		end)
	end)

	t.describe("Outpost terminal", function()
		local function terminalWorld(options: any): (any, any, () -> ())
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local ctx = {
				Facet = Facet,
				Compose = Compose,
				runtime = runtime,
				Host = runtime.constructors,
				UI = Facet.controls(runtime, { types = engine.types } :: any),
				types = engine.types,
			}
			local built
			local stop, node = runtime.mount(function()
				built = outpost.build(ctx, options)
				return built.screen()
			end, engine.new("ScreenGui"))
			return built, node, function()
				stop()
				runtime:dispose()
			end
		end

		t.it("sends nothing before engagement, updates the budget verdict and exits once", function()
			local sent, exits = {}, 0
			local built, node, stop = terminalWorld({
				send = function(envelope)
					table.insert(sent, envelope)
				end,
				onExit = function()
					exits += 1
				end,
			})
			local steps = built.steps
			t.expect(built.report().message).toBe(outpost.rules.OBJECTIVE)
			t.expect(find(node, "Message").Text).toBe(outpost.rules.OBJECTIVE)
			t.expect(find(node, "Apply").Interactable).toBe(false)
			local refused = steps.apply()
			t.expect(refused.sent).toBe(false)
			t.expect(refused.reason).toBe("idle")
			t.expect(#sent).toBe(0)
			steps.engage()
			t.expect(find(node, "Budget").Text).toBe(`3 of {outpost.rules.TOTAL} units allocated — 3 spare`)
			press(node, "workshopStep", "Increase")
			press(node, "workshopStep", "Increase")
			t.expect(built.report().draft.workshop).toBe(2)
			t.expect(find(node, "Budget").Text).toBe(`5 of {outpost.rules.TOTAL} units allocated — 1 spare`)
			t.expect(steps.setValue("workshop", 4).value).toBe(4)
			t.expect(find(node, "Budget").Text).toBe(`7 of {outpost.rules.TOTAL} units allocated — -1 spare`)
			local verdict = built.report().verdict
			t.expect(verdict.ok).toBe(false)
			t.expect(find(node, "Message").Text).toBe(verdict.message)
			t.expect(find(node, "Apply").Interactable).toBe(false)
			t.expect(steps.apply().sent).toBe(false)
			t.expect(#sent).toBe(0)
			steps.setValue("door", 2)
			steps.setValue("beacon", 1)
			steps.setValue("workshop", 2)
			t.expect(find(node, "Apply").Interactable).toBe(true)
			local request = steps.apply()
			t.expect(request.sent).toBe(true)
			t.expect(#sent).toBe(1)
			steps.confirm(request.requestId, { allocation = request.allocation })
			t.expect(built.report().outcome.ok).toBe(true)
			steps.setValue("door", 3)
			t.expect(built.report().outcome).toBeNil()
			t.expect(steps.exit("cancel")).toBe(true)
			t.expect(built.report().exitReason).toBe("cancel")
			t.expect(steps.exit("again")).toBe(false)
			t.expect(built.report().exitReason).toBe("cancel")
			t.expect(exits).toBe(1)
			t.expect(#sent).toBe(1)
			t.expect(steps.apply().sent).toBe(false)
			stop()
		end)

		t.it("needs only activation for every control and keeps its content module engine-free", function()
			local source = fs.readFile("examples/gallery/examples/outpost_terminal/init.luau")
			for _, banned in { "UIDragDetector", "DragStart", "game:GetService", "Instance.new", "workspace" } do
				t.expect(string.find(source, banned, 1, true)).toBeNil()
			end
			local rules = fs.readFile("examples/gallery/examples/outpost_terminal/rules.luau")
			for _, banned in { "game:GetService", "Instance.new", "Compose", "Host." } do
				t.expect(string.find(rules, banned, 1, true)).toBeNil()
			end
			local built, node, stop = terminalWorld({ send = function() end })
			built.steps.engage()
			local buttons = 0
			for _, child in node:GetDescendants() do
				t.expect(child.ClassName ~= "UIDragDetector").toBe(true)
				t.expect(child.Draggable ~= true).toBe(true)
				if child.ClassName == "TextButton" then
					buttons += 1
				end
			end
			t.expect(buttons >= 9).toBe(true)
			for _, consumer in outpost.rules.CONSUMERS do
				local before = built.report().draft[consumer.id]
				press(node, consumer.id .. "Step", if before > 0 then "Decrease" else "Increase")
				t.expect(built.report().draft[consumer.id] ~= before).toBe(true)
			end
			press(node, "Reset")
			t.expect(built.report().status).toBe("pending")
			stop()
		end)
	end)

	t.describe("Performance lab", function()
		local function lab(): (any, any)
			local world = nativeApp()
			local probe
			world.heartbeat = world.engine.heartbeat
			world.captureFacts = function()
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
			end
			world.probe = function(value)
				probe = value
			end
			world.runtime.mount(function()
				return world.Host.ScreenGui({ perfLab.build(world, perfModules) })
			end, world.target)
			return world, probe
		end

		t.it("clamps a requested row count to the dataset ceiling", function()
			local world, probe = lab()
			local ceiling = perfModules.dataset.MAX_ROWS
			probe.select("dense-scroll", ceiling * 10)
			t.expect(probe.state().rows).toBe(ceiling)
			t.expect(#probe.state().active.rows:peek()).toBe(ceiling)
			probe.select("dense-scroll", 0)
			t.expect(probe.state().rows).toBe(1)
			world.dispose()
		end)

		t.it("calls two captures the same workload only when every identity field agrees", function()
			local world, probe = lab()
			probe.select("dense-scroll", 200)
			local a = probe.capture()
			local b = table.clone(a)
			local same, differences = perfModules.capture.sameWorkload(a, b)
			t.expect(same).toBe(true)
			t.expect(#differences).toBe(0)
			t.expect(#perfModules.capture.IDENTITY_FIELDS >= 12).toBe(true)
			for _, field in perfModules.capture.IDENTITY_FIELDS do
				local changed = table.clone(a)
				changed[field] = tostring(a[field]) .. "-changed"
				local agreed, named = perfModules.capture.sameWorkload(a, changed)
				t.expect(agreed).toBe(false)
				t.expect(#named).toBe(1)
				t.expect(string.find(named[1], field .. ":", 1, true)).toBe(1)
			end
			local volatile = table.clone(a)
			volatile.capturedAtIso = "2027-01-01T00:00:00Z"
			t.expect((perfModules.capture.sameWorkload(a, volatile))).toBe(true)
			world.dispose()
		end)
	end)

	t.describe("Documentation and tooling", function()
		local function files(root: string, suffix: string, out: { string }): { string }
			for _, name in fs.readDir(root) do
				local path = root .. "/" .. name
				if fs.isDir(path) then
					files(path, suffix, out)
				elseif string.sub(name, -#suffix) == suffix then
					table.insert(out, path)
				end
			end
			return out
		end

		t.it("calls only Facet exports that exist from every shipped client entry point", function()
			local function missing(source: string): { string }
				local out = {}
				for name in string.gmatch(source, "Facet%.([%a_][%w_]*)") do
					if (Facet :: any)[name] == nil then
						table.insert(out, name)
					end
				end
				return out
			end
			local entries = files("examples", ".client.luau", {})
			t.expect(#entries >= 3).toBe(true)
			local calls = 0
			for _, path in entries do
				local source = fs.readFile(path)
				for _ in string.gmatch(source, "Facet%.([%a_][%w_]*)") do
					calls += 1
				end
				t.expect(`{path}: {table.concat(missing(source), ",")}`).toBe(`{path}: `)
			end
			t.expect(calls > 5).toBe(true)
			t.expect(table.concat(missing("Facet.controls(runtime) Facet.nonexistentExport()"), ","))
				.toBe("nonexistentExport")
			t.expect(#missing("local x = game.ReplicatedStorage.Facet")).toBe(0)
		end)

		t.it("keeps every shipped document from claiming virtual-reality support", function()
			local documents = files("docs", ".md", { "AGENTS.md", "README.md" })
			local claims, denials = {}, 0
			for _, path in documents do
				for line in string.gmatch(fs.readFile(path), "[^\n]+") do
					local lowered = string.lower(line)
					local mentions = string.find(lowered, "%f[%a]vr%f[%A]")
						or string.find(lowered, "virtual.reality")
						or string.find(lowered, "gaze")
					if mentions then
						local negated = string.find(lowered, "%f[%a]no%f[%A]")
							or string.find(lowered, "not")
							or string.find(lowered, "never")
							or string.find(lowered, "without")
						if negated then
							denials += 1
						else
							for _, claim in { "supports vr", "vr support", "vr-ready", "works in vr", "vr mode" } do
								if string.find(lowered, claim, 1, true) then
									table.insert(claims, `{path}: {line}`)
								end
							end
						end
					end
				end
			end
			t.expect(table.concat(claims, "\n")).toBe("")
			t.expect(denials >= 2).toBe(true)
		end)

		t.it("scaffolds formatter-clean control source", function()
			local plan = scaffold.plan("control", "proof_control")
			local sources = { plan.files[1].content }
			for _, edit in plan.edits do
				table.insert(sources, scaffold.applyEdit(fs.readFile(edit.path), edit))
			end
			for index, source in sources do
				local result = process.exec("stylua", { "--check", "-" }, { stdio = { stdin = source } })
				t.expect(`{index}: {result.ok}`).toBe(`{index}: true`)
				t.expect(string.find(source, "\n\n\n", 1, true)).toBeNil()
				local lines = string.split(source, "\n")
				for index = 2, #lines do
					t.expect(string.find(lines[index], "--", 1, true)).toBeNil()
				end
			end
			local bad = process.exec("stylua", { "--check", "-" }, { stdio = { stdin = "local x   =  1\n" } })
			t.expect(bad.ok).toBe(false)
		end)
	end)

	t.describe("Tables and radial menus", function()
		local function named(node: any, name: string): { any }
			local out = {}
			for _, child in node:GetDescendants() do
				if child.Name == name then
					table.insert(out, child)
				end
			end
			return out
		end

		local function controlsFor(engine: any, target: any, extra: { [string]: any }?): (any, any, any, any)
			local runtime = Facet.Roblox.createRuntime(engine)
			local gui, input = engine.new("GuiService"), engine.new("UserInputService")
			input.GetFocusedTextBox = function()
				return nil
			end
			input.IsKeyDown = function()
				return false
			end
			local config: { [string]: any } = {
				types = engine.types,
				guiService = gui,
				services = { GuiService = gui, UserInputService = input },
				inputParent = target,
				reducedMotion = true,
			}
			if extra then
				for key, value in extra do
					config[key] = value
				end
			end
			return runtime, Facet.controls(runtime, config :: any), gui, input
		end

		local function mountTable(spec: any): any
			local engine = engineLib.new()
			local target = engine.new("ScreenGui")
			local runtime, UI = controlsFor(engine, target)
			local stop, node = runtime.mount(function()
				return UI.Table(spec)
			end, target)
			return {
				engine = engine,
				target = target,
				node = node,
				body = node:FindFirstChild("Body"),
				header = node:FindFirstChild("Header"),
				stop = function()
					stop()
					runtime:dispose()
				end,
			}
		end

		local function mountGallery(module: any): any
			local engine = engineLib.new()
			local target = engine.new("Folder")
			local viewport = Compose.cell({ width = 1280, height = 720 })
			local runtime, UI, gui = controlsFor(engine, target, { viewport = viewport })
			local ctx = {
				Facet = Facet,
				Compose = Compose,
				runtime = runtime,
				Host = runtime.constructors,
				types = engine.types,
				viewport = viewport,
				guiService = gui,
				runService = { Heartbeat = engine.heartbeat },
				UI = UI,
			}
			local built
			local stop, node = runtime.mount(function()
				built = module.build(ctx)
				if built.dispose then
					Compose.cleanup(built.dispose)
				end
				return ctx.Host.ScreenGui "DemoScreen" { built.screen() }
			end, target)
			return {
				built = built,
				node = node,
				engine = engine,
				target = target,
				stop = function()
					stop()
					runtime:dispose()
				end,
			}
		end

		local function vector(engine: any, x: number, y: number): any
			return engine.types.Vector2.new(x, y)
		end

		local function ids(rows: { any }): string
			local out = {}
			for _, row in rows do
				table.insert(out, row.id)
			end
			return table.concat(out, ",")
		end

		local function records(count: number): { any }
			local out = {}
			for index = 1, count do
				out[index] = { id = index, first = `First {index}`, second = `Second {index}`, third = `Third {index}` }
			end
			return out
		end

		local function recordKey(item: any): number
			return item.id
		end

		t.describe("Table", function()
			t.it("gives a resizable column a grip and a locked column neither a grip nor adjust keys", function()
				local widths = Compose.cell({})
				local world = mountTable({
					from = records(3),
					key = recordKey,
					widths = widths,
					columns = {
						{ id = "first", width = 100 },
						{ id = "second", width = 100, resizable = false },
					},
				})
				world.body.AbsoluteWindowSize = vector(world.engine, 400, 200)
				local first, second = world.header:FindFirstChild("first"), world.header:FindFirstChild("second")
				first.AbsoluteSize = vector(world.engine, 100, 40)
				second.AbsoluteSize = vector(world.engine, 100, 40)
				t.expect(first:FindFirstChild("Resize") ~= nil).toBe(true)
				t.expect(first:FindFirstChildWhichIsA("UIDragDetector", true) ~= nil).toBe(true)
				t.expect(second:FindFirstChild("Resize")).toBeNil()
				t.expect(second:FindFirstChildWhichIsA("UIDragDetector", true)).toBeNil()
				t.expect(#named(world.target, "FacetNarrowColumn")).toBe(1)
				t.expect(#named(world.target, "FacetWidenColumn")).toBe(1)
				local narrow = within(world.target, "FacetNarrowColumn", "NarrowColumn")
				local widen = within(world.target, "FacetWidenColumn", "WidenColumn")
				second:FindFirstChild("Sort").SelectionGained.fire()
				narrow.Pressed.fire()
				widen.Pressed.fire()
				t.expect(widths:peek()).toEqual({})
				first:FindFirstChild("Resize").SelectionGained.fire()
				narrow.Pressed.fire()
				t.expect(widths:peek()).toEqual({ first = 92 })
				t.expect(second.Size.X.Offset).toBe(100)
				world.stop()
			end)

			t.it("stops adjusting a column width once its grip loses selection", function()
				local widths = Compose.cell({})
				local world = mountTable({
					from = records(3),
					key = recordKey,
					widths = widths,
					columns = { { id = "first", width = 100 }, { id = "second", width = 100 } },
				})
				world.body.AbsoluteWindowSize = vector(world.engine, 400, 200)
				local column = world.header:FindFirstChild("first")
				column.AbsoluteSize = vector(world.engine, 100, 40)
				local grip = column:FindFirstChild("Resize")
				local actions = named(world.target, "NarrowColumn")
				local wides = named(world.target, "WidenColumn")
				t.expect(#actions).toBe(2)
				local function pressAll(list: { any })
					for _, action in list do
						action.Pressed.fire()
					end
				end
				pressAll(actions)
				t.expect(widths:peek()).toEqual({})
				grip.SelectionGained.fire()
				pressAll(actions)
				t.expect(widths:peek()).toEqual({ first = 92 })
				pressAll(wides)
				pressAll(wides)
				t.expect(widths:peek()).toEqual({ first = 108 })
				grip.SelectionLost.fire()
				pressAll(actions)
				pressAll(wides)
				t.expect(widths:peek()).toEqual({ first = 108 })
				t.expect(column.Size.X.Offset).toBe(108)
				grip.SelectionGained.fire()
				pressAll(actions)
				t.expect(widths:peek()).toEqual({ first = 100 })
				world.stop()
			end)

			t.it("keeps a resized column on a 2000 row table bounded to the window at the new width", function()
				local widths = Compose.cell({})
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
				} :: any)
				local world = mountTable({
					from = records(2000),
					key = recordKey,
					widths = widths,
					itemSize = 40,
					status = status,
					columns = { { id = "first", width = 100 }, { id = "second", width = 120 } },
				})
				world.body.AbsoluteWindowSize = vector(world.engine, 400, 400)
				local function mountedCells(id: string): { any }
					local out = {}
					for _, row in named(world.body, "Row") do
						local cell = row:FindFirstChild(id)
						if cell then
							table.insert(out, cell)
						end
					end
					return out
				end
				local before = mountedCells("first")
				t.expect(#before > 0 and #before < 30).toBe(true)
				t.expect(#before).toBe(status:peek().retained)
				t.expect(status:peek().total).toBe(2000)
				for _, cell in before do
					t.expect(cell.Size.X.Offset).toBe(100)
				end
				local column = world.header:FindFirstChild("first")
				column.AbsoluteSize = vector(world.engine, 100, 40)
				local detector = column:FindFirstChildWhichIsA("UIDragDetector", true)
				detector.DragStart.fire(vector(world.engine, 100, 10))
				detector.DragContinue.fire(vector(world.engine, 180, 10))
				t.expect(widths:peek()).toEqual({ first = 180 })
				local after = mountedCells("first")
				t.expect(#after).toBe(#before)
				for index, cell in after do
					t.expect(cell).toBe(before[index])
					t.expect(cell.Size.X.Offset).toBe(180)
				end
				for _, cell in mountedCells("second") do
					t.expect(cell.Size.X.Offset).toBe(120)
				end
				t.expect(column.Size.X.Offset).toBe(180)
				world.body.CanvasPosition = vector(world.engine, 0, 40000)
				local far = mountedCells("first")
				t.expect(#far > 0 and #far < 30).toBe(true)
				t.expect(find(world.body, "1")).toBeNil()
				t.expect(find(world.body, "1001") ~= nil).toBe(true)
				for _, cell in far do
					t.expect(cell.Size.X.Offset).toBe(180)
				end
				world.stop()
			end)

			t.it("keeps header column boundaries on the body columns through resize scroll and a scrollbar", function()
				for _, reorderable in { false, true } do
					local widths = Compose.cell({})
					local world = mountTable({
						from = records(40),
						key = recordKey,
						widths = widths,
						itemSize = 40,
						reorderable = reorderable,
						columns = {
							{ id = "first", width = 120 },
							{ id = "second", width = 140 },
							{ id = "third", width = 160 },
						},
					})
					local gutter = if reorderable then 56 else 0
					world.body.AbsoluteSize = vector(world.engine, 600, 300)
					world.body.AbsoluteWindowSize = vector(world.engine, 600, 300)
					t.expect(world.body.CanvasSize.Y.Offset > 300).toBe(true)
					t.expect(world.body.CanvasSize.X.Offset)
						.toBe(world.header:FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize.X + gutter)
					local function check(windowWidth: number, scrollX: number, disclosure: number)
						local row = find(world.body, "1")
						local cells = find(row, "Row")
						local frame = if reorderable then find(row, "Cells") else nil
						t.expect(world.header.Position.X.Offset).toBe(gutter - scrollX)
						t.expect(if frame then frame.Position.X.Offset else 0).toBe(gutter)
						t.expect(world.header.Size.X.Offset).toBe(windowWidth - gutter - disclosure)
						t.expect(row.Size.X.Offset).toBe(windowWidth)
						t.expect(cells.Size.X.Scale).toBe(1)
						t.expect(cells.Size.X.Offset).toBe(-disclosure)
						local left = 0
						for _, id in { "first", "second", "third" } do
							local head, cell = world.header:FindFirstChild(id), cells:FindFirstChild(id)
							t.expect(head.Size).toBe(cell.Size)
							t.expect(head.LayoutOrder).toBe(cell.LayoutOrder)
							t.expect(head.Visible).toBe(cell.Visible)
							if cell.Visible then
								left += cell.Size.X.Offset
							end
						end
						return left
					end
					t.expect(check(600, 0, 0)).toBe(420)
					world.body.AbsoluteWindowSize = vector(world.engine, 594, 300)
					t.expect(check(594, 0, 0)).toBe(420)
					widths:set({ second = 200 })
					t.expect(check(594, 0, 0)).toBe(480)
					t.expect(world.header:FindFirstChild("second").Size.X.Offset).toBe(200)
					world.body.CanvasPosition = vector(world.engine, 30, 0)
					t.expect(check(594, 30, 0)).toBe(480)
					widths:set({ second = 360 })
					t.expect(world.header:FindFirstChild("third").Visible).toBe(false)
					t.expect(check(594, 30, 48)).toBe(480)
					world.stop()
				end
			end)
		end)

		t.describe("Playlist example", function()
			local function prepare(world: any): any
				local body = find(world.node, "Body")
				body.AbsoluteSize = vector(world.engine, 900, 288)
				body.AbsoluteWindowSize = vector(world.engine, 900, 288)
				return body
			end

			local function click(world: any, kind: string, count: number?): any
				local E = world.engine.types.Enum
				return {
					UserInputType = if kind == "mouse"
						then E.UserInputType.MouseButton1
						elseif kind == "touch" then E.UserInputType.Touch
						else E.UserInputType.Keyboard,
					KeyCode = if kind == "key" then E.KeyCode.Return else E.KeyCode.Unknown,
					UserInputState = E.UserInputState.End,
				},
					count or 1
			end

			t.it("aligns name artist and rating columns under their headers", function()
				local world = mountGallery(playlistExample)
				local body = prepare(world)
				local header = find(world.node, "Header")
				local row = find(body, "neon")
				local cells = find(row, "Row")
				t.expect(header.Position.X.Offset).toBe(find(row, "Cells").Position.X.Offset)
				t.expect(header.Size.X.Offset).toBe(900 - 56)
				local E = world.engine.types.Enum
				for id, width in { name = 0, artist = 0, rating = 144 } do
					t.expect(header:FindFirstChild(id).Size.X.Offset).toBe(width)
					t.expect(cells:FindFirstChild(id).Size).toBe(header:FindFirstChild(id).Size)
					t.expect(header:FindFirstChild(id):FindFirstChildWhichIsA("UIFlexItem").FlexMode)
						.toBe(if width == 0 then E.UIFlexMode.Fill else E.UIFlexMode.None)
				end
				world.built.columnWidths:set({ name = 290 })
				t.expect(header:FindFirstChild("name").Size.X.Offset).toBe(290)
				t.expect(cells:FindFirstChild("name").Size.X.Offset).toBe(290)
				t.expect(cells:FindFirstChild("rating").Size.X.Offset).toBe(144)
				t.expect(find(world.node, "Widths").Text).toBe("Name 290px · Artist auto · Rating locked")
				world.stop()
			end)

			t.it("plays on a double click Return or touch tap while a single or slow click only selects", function()
				local world = mountGallery(playlistExample)
				local body = prepare(world)
				local label = find(world.node, "NowPlaying")
				local function hit(id: string): any
					return find(find(body, id), "RowHit")
				end
				local function selected(id: string): boolean
					return find(find(body, id), "Row"):GetAttribute("FacetSelected") == true
				end
				t.expect(label.Text).toBe("Nothing playing — double-click a row, or press Return on a focused one")
				hit("neon").Activated.fire(click(world, "mouse", 1))
				t.expect(selected("neon")).toBe(true)
				t.expect(world.built.nowPlaying:peek()).toBeNil()
				t.expect(label.Text).toBe("Nothing playing — double-click a row, or press Return on a focused one")
				hit("neon").Activated.fire(click(world, "mouse", 2))
				t.expect(world.built.nowPlaying:peek()).toBe("Neon Straightaway")
				t.expect(label.Text).toBe("Now playing — Neon Straightaway")
				t.expect(selected("neon")).toBe(true)
				hit("drift").Activated.fire(click(world, "mouse", 1))
				hit("drift").Activated.fire(click(world, "mouse", 1))
				t.expect(label.Text).toBe("Now playing — Neon Straightaway")
				t.expect(selected("drift")).toBe(true)
				t.expect(selected("neon")).toBe(false)
				hit("turbo").Activated.fire(click(world, "touch", 1))
				t.expect(label.Text).toBe("Now playing — Turbo Cascade")
				hit("pit").Activated.fire(click(world, "key", 1))
				t.expect(label.Text).toBe("Now playing — Pit Lane Shuffle")
				press(world.node, "Restore")
				t.expect(world.built.nowPlaying:peek()).toBeNil()
				t.expect(label.Text).toBe("Nothing playing — double-click a row, or press Return on a focused one")
				world.stop()
			end)

			t.it("sorts rating by the live stars and artist by value with source order breaking ties", function()
				local world = mountGallery(playlistExample)
				local body = prepare(world)
				local header = find(world.node, "Header")
				press(header, "artist", "Sort")
				t.expect(world.built.sort:peek()).toEqual({ column = "artist", direction = "ascending" })
				t.expect(ids(world.built.sortedRows:peek())).toBe("photo,neon,drift,apex,turbo,pit")
				t.expect(find(header, "artist"):FindFirstChild("Sort").Text).toBe("Artist ↑")
				press(header, "artist", "Sort")
				t.expect(ids(world.built.sortedRows:peek())).toBe("pit,turbo,drift,apex,neon,photo")
				world.built.sort:set({ column = "rating", direction = "descending" })
				t.expect(ids(world.built.sortedRows:peek())).toBe("turbo,neon,drift,apex,pit,photo")
				local photo = find(body, "photo")
				local stars = find(photo, "Rating")
				t.expect(find(body, "photo").Position.Y.Offset > find(body, "neon").Position.Y.Offset).toBe(true)
				world.built.ratingFor("photo"):set(5)
				t.expect(ids(world.built.sortedRows:peek())).toBe("turbo,photo,neon,drift,apex,pit")
				t.expect(find(body, "photo")).toBe(photo)
				t.expect(find(photo, "Rating")).toBe(stars)
				t.expect(find(body, "photo").Position.Y.Offset < find(body, "neon").Position.Y.Offset).toBe(true)
				t.expect(find(body, "turbo").Position.Y.Offset < find(body, "photo").Position.Y.Offset).toBe(true)
				world.built.ratingFor("photo"):set(0)
				t.expect(ids(world.built.sortedRows:peek())).toBe("turbo,neon,drift,apex,pit,photo")
				world.stop()
			end)

			t.it("bakes the sort when Top moves a row and keeps the sort when a row is removed", function()
				local world = mountGallery(playlistExample)
				local body = prepare(world)
				local function swipe(id: string, distance: number)
					local actions = find(find(body, id), "leading").Parent
					actions.AbsoluteSize = vector(world.engine, 844, 44)
					local detector = actions:FindFirstChildWhichIsA("UIDragDetector")
					detector.DragStart.fire(vector(world.engine, 400, 20))
					detector.DragContinue.fire(vector(world.engine, 400 + distance, 20))
					detector.DragEnd.fire()
				end
				world.built.sort:set({ column = "name", direction = "descending" })
				t.expect(ids(world.built.sortedRows:peek())).toBe("turbo,pit,photo,neon,drift,apex")
				press(find(body, "neon"), "top")
				t.expect(world.built.sort:peek()).toEqual({ column = "name", direction = "descending" })
				swipe("neon", 120)
				press(find(body, "neon"), "top")
				t.expect(world.built.sort:peek()).toBeNil()
				t.expect(ids(world.built.baseRows:peek())).toBe("neon,turbo,pit,photo,drift,apex")
				t.expect(ids(world.built.from:peek())).toBe("neon,turbo,pit,photo,drift,apex")
				world.built.sort:set({ column = "name", direction = "descending" })
				world.built.nowPlaying:set("Pit Lane Shuffle")
				swipe("drift", -120)
				press(find(body, "drift"), "remove")
				t.expect(world.built.sort:peek()).toEqual({ column = "name", direction = "descending" })
				t.expect(ids(world.built.sortedRows:peek())).toBe("turbo,pit,photo,neon,apex")
				t.expect(world.built.nowPlaying:peek()).toBe("Pit Lane Shuffle")
				swipe("pit", -700)
				t.expect(world.built.sort:peek()).toEqual({ column = "name", direction = "descending" })
				t.expect(ids(world.built.sortedRows:peek())).toBe("turbo,photo,neon,apex")
				t.expect(world.built.nowPlaying:peek()).toBeNil()
				t.expect(find(body, "pit")).toBeNil()
				world.stop()
			end)
		end)

		local function openRadial(spec: any, extra: { [string]: any }?): any
			local engine = engineLib.new()
			local target = engine.new("Folder")
			local runtime, UI, gui, input = controlsFor(engine, target, extra)
			local opened = spec.isPresented or Compose.cell(true)
			spec.isPresented = opened
			local stop, screen = runtime.mount(function()
				return runtime.constructors.ScreenGui({ UI.RadialMenu(spec) })
			end, target)
			return {
				engine = engine,
				gui = gui,
				input = input,
				screen = screen,
				opened = opened,
				find = function(name: string): any
					return screen:FindFirstChild(name, true)
				end,
				stop = function()
					stop()
					runtime:dispose()
				end,
			}
		end

		local function touch(world: any, x: number, y: number): any
			local E = world.engine.types.Enum
			return {
				UserInputType = E.UserInputType.Touch,
				UserInputState = E.UserInputState.Begin,
				Position = world.engine.types.Vector3.new(x, y, 0),
			}
		end

		local function compassItems(record: { string }, enabled: any?): { any }
			local out = {}
			for _, id in { "N", "E", "S", "W" } do
				table.insert(out, {
					id = id,
					slot = id,
					label = id,
					completion = "stay",
					enabled = if id == "N" then enabled else nil,
					onSelect = function()
						table.insert(record, id)
					end,
				})
			end
			return out
		end

		local function centerOf(button: any): (number, number)
			return button.Position.X.Offset, button.Position.Y.Offset
		end

		local function distance(button: any, x: number, y: number): number
			local bx, by = centerOf(button)
			return math.sqrt((bx - x) ^ 2 + (by - y) ^ 2)
		end

		t.describe("RadialMenu", function()
			t.it("sizes the hole from the anchor clearance and keeps a fixed ring until it reopens", function()
				local function ring(clearance: number?, anchorClearance: number?): number
					local world = openRadial({
						anchor = Compose.cell({ x = 320, y = 240, clearance = anchorClearance }),
						clearance = clearance,
						follow = "fixed",
						distribution = "compass",
						items = compassItems({}),
					})
					local measured = distance(world.find("N"), 320, 240)
					world.stop()
					return measured
				end
				local plain, fifty, seventy = ring(nil, nil), ring(50, nil), ring(50, 70)
				t.expect(plain < fifty).toBe(true)
				t.expect(fifty < seventy).toBe(true)
				t.expect(ring(70, 50)).toBe(seventy)
				local anchor = Compose.cell({ x = 320, y = 240, clearance = 70 })
				local world = openRadial({
					anchor = anchor,
					clearance = 50,
					follow = "fixed",
					distribution = "compass",
					items = compassItems({}),
				})
				local north = world.find("N")
				local position = north.Position
				t.expect(position.X.Offset).toBe(320)
				t.expect(distance(north, 320, 240)).toBe(seventy)
				t.expect(distance(north, 320, 240) - north.Size.Y.Offset / 2 >= 70).toBe(true)
				anchor:set({ x = 400, y = 240, clearance = 90 })
				t.expect(world.find("N").Position).toBe(position)
				t.expect(world.find("E").Position.X.Offset - 320).toBe(seventy)
				world.opened:set(false)
				world.opened:set(true)
				local reopened = world.find("N")
				t.expect(reopened.Position.X.Offset).toBe(400)
				t.expect(distance(reopened, 400, 240) > seventy).toBe(true)
				t.expect(distance(reopened, 400, 240) - reopened.Size.Y.Offset / 2 >= 90).toBe(true)
				world.stop()
			end)

			t.it("freezes the idle ring center and hole during a pointer capture and follows after release", function()
				local picked = {}
				local anchor = Compose.cell({ x = 320, y = 240, clearance = 70 })
				local world = openRadial({
					anchor = anchor,
					distribution = "compass",
					items = compassItems(picked),
				})
				local north = world.find("N")
				local position = north.Position
				local radius = distance(north, 320, 240)
				local hold = touch(world, position.X.Offset, position.Y.Offset)
				world.find("RadialPanel").InputBegan.fire(hold)
				anchor:set({ x = 400, y = 240, clearance = 90 })
				t.expect(world.find("N").Position).toBe(position)
				t.expect(world.find("E").Position.X.Offset - 320).toBe(radius)
				world.input.InputEnded.fire(hold)
				t.expect(table.concat(picked, ",")).toBe("N")
				t.expect(world.find("N").Position.X.Offset).toBe(400)
				t.expect(distance(world.find("N"), 400, 240) > radius).toBe(true)
				world.stop()
			end)

			t.it("keeps corner rings of round buttons inside short and tall surfaces", function()
				for _, preset in { "bottom-left", "bottom-right", "top-right", "top-left" } do
					for _, size in { { 469, 209 }, { 800, 650 } } do
						local picked = {}
						local items = {}
						for _, id in { "look", "pack", "wave" } do
							table.insert(items, {
								id = id,
								label = id,
								onSelect = function()
									table.insert(picked, id)
								end,
							})
						end
						local world = openRadial({ preset = preset, appearance = "buttons", items = items })
						world.find("Modal").AbsoluteSize = vector(world.engine, size[1], size[2])
						t.expect(world.find("RadialPanel"):GetAttribute("Presentation")).toBe("radial")
						local boxes = {}
						for _, id in { "look", "pack", "wave" } do
							local button = world.find(id)
							local x, y = centerOf(button)
							local half = button.Size.X.Offset / 2
							t.expect(button.Size.X.Offset >= 44).toBe(true)
							t.expect(button.Size.Y.Offset).toBe(button.Size.X.Offset)
							t.expect(x - half >= 0 and x + half <= size[1]).toBe(true)
							t.expect(y - half >= 0 and y + half <= size[2]).toBe(true)
							table.insert(boxes, { x = x, y = y, half = half })
						end
						for first = 1, #boxes do
							for second = first + 1, #boxes do
								local a, b = boxes[first], boxes[second]
								local gap = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
								t.expect(gap >= a.half + b.half).toBe(true)
							end
						end
						world.find("look").Activated.fire()
						t.expect(table.concat(picked, ",")).toBe("look")
						t.expect(world.opened:peek()).toBe(false)
						world.stop()
					end
				end
			end)

			t.it("shows exactly one navigation control for each center policy and names it by depth", function()
				for _, center in { "back", "root", "close", "content", "empty" } do
					local world = openRadial({
						center = center,
						items = {
							{
								id = "Branch",
								label = "Branch",
								children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
							},
							{ id = "Other", label = "Other", onSelect = function() end },
						} :: { any },
					})
					world.find("Modal").AbsoluteSize = vector(world.engine, 180, 180)
					t.expect(world.find("RadialPanel"):GetAttribute("Presentation")).toBe("list")
					local function controls(): { any }
						local out = {}
						for _, node in world.screen:GetDescendants() do
							if (node.Name == "$navigation" or node.Name == "Center") and node:IsA("GuiButton") then
								local shown = true
								local at = node
								while at and at:IsA("GuiObject") do
									shown = shown and at.Visible ~= false
									at = at.Parent
								end
								if shown then
									table.insert(out, node)
								end
							end
						end
						return out
					end
					t.expect(#controls()).toBe(1)
					t.expect(controls()[1].Text).toBe("Close")
					world.find("Branch").Activated.fire()
					t.expect(world.find("Leaf") ~= nil).toBe(true)
					t.expect(#controls()).toBe(1)
					t.expect(controls()[1].Text).toBe("Back")
					controls()[1].Activated.fire()
					t.expect(world.opened:peek()).toBe(true)
					t.expect(world.find("Leaf")).toBeNil()
					t.expect(world.find("Branch") ~= nil).toBe(true)
					t.expect(#controls()).toBe(1)
					controls()[1].Activated.fire()
					t.expect(world.opened:peek()).toBe(false)
					world.stop()
				end
				for center, labels in
					{ back = { "Close", "Back" }, close = { "Close", "Close" }, root = { "Home", "Home" } } :: { [string]: { string } }
				do
					local world = openRadial({
						center = center,
						items = {
							{
								id = "Branch",
								label = "Branch",
								children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
							},
						},
					})
					local button = world.find("Center")
					t.expect(button.Visible).toBe(true)
					t.expect(button.Text).toBe(labels[1])
					world.find("Branch").Activated.fire()
					t.expect(button.Text).toBe(labels[2])
					button.Activated.fire()
					t.expect(world.opened:peek()).toBe(center ~= "close")
					t.expect(world.find("Leaf")).toBeNil()
					t.expect(world.find("Branch") ~= nil).toBe(center ~= "close")
					world.stop()
				end
				local world = openRadial({
					center = "empty",
					items = {
						{
							id = "Branch",
							label = "Branch",
							children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
						},
					},
				})
				world.find("Modal").AbsoluteSize = vector(world.engine, 180, 180)
				t.expect(world.find("$navigation").Text).toBe("Close")
				world.find("Branch").Activated.fire()
				t.expect(world.find("$navigation").Text).toBe("Back")
				world.find("$navigation").Activated.fire()
				t.expect(world.find("Branch") ~= nil).toBe(true)
				t.expect(world.find("Leaf")).toBeNil()
				t.expect(world.opened:peek()).toBe(true)
				t.expect(world.find("$navigation").Text).toBe("Close")
				world.find("$navigation").Activated.fire()
				t.expect(world.opened:peek()).toBe(false)
				world.stop()
			end)

			t.it("returns to the root when the open branch disappears from the items", function()
				local items = Compose.cell({
					{
						id = "gear",
						label = "Gear",
						children = { { id = "go", label = "Go", onSelect = function() end } },
					},
				} :: { any })
				local world = openRadial({ items = items })
				world.find("gear").Activated.fire()
				t.expect(world.find("go") ~= nil).toBe(true)
				t.expect(world.find("gear")).toBeNil()
				items:set({ { id = "other", label = "Other", onSelect = function() end } })
				t.expect(world.find("other") ~= nil).toBe(true)
				t.expect(world.find("go")).toBeNil()
				t.expect(world.opened:peek()).toBe(true)
				world.find("Center").Activated.fire()
				t.expect(world.opened:peek()).toBe(false)
				world.stop()
			end)

			t.it("does not fire an item disabled while its touch was held", function()
				for _, disable in { false, true } do
					local picked = {}
					local enabled = Compose.cell(true)
					local world = openRadial({ distribution = "compass", items = compassItems(picked, enabled) })
					local x, y = centerOf(world.find("N"))
					local hold = touch(world, x, y)
					world.find("RadialPanel").InputBegan.fire(hold)
					if disable then
						enabled:set(false)
					end
					world.input.InputEnded.fire(hold)
					t.expect(#picked).toBe(if disable then 0 else 1)
					world.stop()
				end
			end)

			t.it("leaves no built-in trigger when the launcher is off", function()
				local shown = openRadial({
					isPresented = Compose.cell(false),
					distribution = "compass",
					items = compassItems({}),
				})
				t.expect(shown.find("Launcher") ~= nil).toBe(true)
				shown.stop()
				local picked = {}
				local presented = Compose.cell(false)
				local world = openRadial({
					launcher = false,
					isPresented = presented,
					items = {
						{
							id = "N",
							label = "N",
							onSelect = function()
								table.insert(picked, "N")
							end,
						},
					},
				})
				t.expect(world.find("Launcher")).toBeNil()
				t.expect(world.find("N")).toBeNil()
				presented:set(true)
				world.find("N").Activated.fire()
				t.expect(table.concat(picked, ",")).toBe("N")
				t.expect(presented:peek()).toBe(false)
				t.expect(world.find("Launcher")).toBeNil()
				t.expect(world.find("N")).toBeNil()
				world.stop()
			end)

			t.it("lets input through an empty center while edge catchers dismiss around it", function()
				for _, passThrough in { false, true } do
					local picked = {}
					local world = openRadial({
						center = "empty",
						centerPassThrough = passThrough,
						distribution = "compass",
						items = compassItems(picked),
					})
					local panel = world.find("RadialPanel")
					t.expect(panel.Active).toBe(not passThrough)
					t.expect(world.find("DismissOutside").Visible).toBe(not passThrough)
					if passThrough then
						local covered = 0
						for _, edge in { "Top", "Bottom", "Left", "Right" } do
							local catcher = world.find("Dismiss" .. edge)
							t.expect(catcher.Visible).toBe(true)
							local x, y = catcher.Position.X.Offset, catcher.Position.Y.Offset
							local w, h = catcher.Size.X.Offset, catcher.Size.Y.Offset
							t.expect(320 >= x and 320 < x + w and 240 >= y and 240 < y + h).toBe(false)
							covered += w * h
						end
						t.expect(covered).toBe(640 * 480 - 80 * 80)
					else
						t.expect(world.find("DismissTop")).toBeNil()
					end
					local hold = touch(world, 320, 240)
					panel.InputBegan.fire(hold)
					local x, y = centerOf(world.find("N"))
					hold.Position = world.engine.types.Vector3.new(x, y, 0)
					world.input.InputChanged.fire(hold)
					world.input.InputEnded.fire(hold)
					t.expect(#picked).toBe(if passThrough then 0 else 1)
					t.expect(world.opened:peek()).toBe(true)
					if passThrough then
						world.find("DismissTop").Activated.fire()
						t.expect(world.opened:peek()).toBe(false)
					end
					world.stop()
				end
			end)
		end)

		t.describe("Quick actions example", function()
			local function stageExplorer(world: any, width: number, height: number, offsetX: number)
				world.node:FindFirstChild("Modal", true).AbsoluteSize = vector(world.engine, width, height)
				local explorer = find(world.node, "Explorer")
				explorer.AbsoluteSize = vector(world.engine, 76, 110)
				explorer.AbsolutePosition = vector(world.engine, width / 2 - 38 + offsetX, 310 - 55)
			end

			t.it("picks the character command ring or list from the viewport height", function()
				for _, case in
					{ { 1280, 720, "radial" }, { 960, 540, "radial" }, { 800, 600, "radial" }, { 677, 338, "list" } } :: { { any } }
				do
					local world = mountGallery(quickActions)
					world.built.steps.character()
					world.built.steps.open()
					t.expect(world.built.report().menu.isPresented).toBe(true)
					stageExplorer(world, case[1], case[2], 0)
					local panel = world.node:FindFirstChild("RadialPanel", true)
					t.expect(panel:GetAttribute("Presentation")).toBe(case[3])
					t.expect(panel.ScrollingEnabled).toBe(case[3] == "list")
					t.expect(find(panel, "equipment") ~= nil and find(panel, "wave") ~= nil).toBe(true)
					press(panel, "inspect")
					t.expect(world.built.report().status).toBe("Trail guide · explorer · lantern off")
					t.expect(world.built.report().menu.isPresented).toBe(true)
					world.stop()
				end
			end)

			t.it(
				"opens the quick actions at phone viewports with large text and keeps a wandering ring round",
				function()
					for _, size in { { 359, 718 }, { 844, 390 }, { 320, 568 }, { 600, 320 } } do
						for _, grow in { 0, 14 } do
							local world = mountGallery(quickActions)
							world.built.steps.open()
							t.expect(world.built.report().tab).toBe("corner")
							t.expect(world.built.report().menu.isPresented).toBe(true)
							world.node:FindFirstChild("Modal", true).AbsoluteSize =
								vector(world.engine, size[1], size[2])
							for _, id in { "look", "pack", "wave" } do
								find(world.node, id).TextBounds = vector(world.engine, 40 + grow * 4, 16 + grow)
							end
							t.expect(world.node:FindFirstChild("RadialPanel", true):GetAttribute("Presentation"))
								.toBe("radial")
							t.expect(world.built.report().menu.isPresented).toBe(true)
							world.built.steps.character()
							t.expect(world.built.report().tab).toBe("character")
							world.built.steps.open()
							t.expect(world.built.report().menu.isPresented).toBe(true)
							stageExplorer(world, size[1], size[2], 0)
							t.expect(find(world.node, "equipment") ~= nil).toBe(true)
							world.stop()
						end
					end
					local world = mountGallery(quickActions)
					world.built.steps.character()
					world.built.steps.open()
					stageExplorer(world, 359, 718, 0)
					local panel = world.node:FindFirstChild("RadialPanel", true)
					t.expect(panel:GetAttribute("Presentation")).toBe("radial")
					world.built.steps.move()
					local explorer = find(world.node, "Explorer")
					local moved = false
					for frame = 1, 240 do
						world.engine.heartbeat.fire(1 / 60)
						if frame % 6 == 0 then
							local offset = explorer.Position.X.Offset
							moved = moved or math.abs(offset) > 1
							stageExplorer(world, 359, 718, offset)
							t.expect(panel:GetAttribute("Presentation")).toBe("radial")
							t.expect(world.built.report().menu.isPresented).toBe(true)
						end
					end
					t.expect(moved).toBe(true)
					world.stop()
				end
			)
		end)
	end)

	t.describe("Public surface, catalog and theme corpus", function()
		local EXPECTED_SHIPPABLE = {
			"classic_desktop",
			"compact_pointer",
			"fantasy_ornate",
			"fantasy_parchment",
			"glossy_mobile",
			"glossy_touch",
			"pixel_quest",
			"scifi_hud",
		}

		local function controlNames(): { string }
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local names = {}
			for name in Facet.controls(runtime, { types = engine.types } :: any) do
				if not helpers[name] then
					table.insert(names, name :: string)
				end
			end
			table.sort(names)
			runtime:dispose()
			return names
		end

		t.it("exports the Props or Spec contract of every control and the documented Compose types", function()
			local source = fs.readFile("src/init.luau")
			local exported: { [string]: boolean } = {}
			for name in string.gmatch(source, "export type ([%a_][%w_]*)") do
				exported[name] = true
			end
			local shared = {
				VirtualList = "CollectionSpec",
				VirtualGrid = "CollectionSpec",
				VStack = "StackProps",
				HStack = "StackProps",
			}
			local names = controlNames()
			local published: { string } = {}
			for name in
				string.gmatch(fs.readFile("tools/public_surface.txt"), "controls%(runtime%)%.(%u[%w_]*) : function")
			do
				if name ~= "fill" and name ~= "badged" then
					table.insert(published, name)
				end
			end
			table.sort(published)
			t.expect(table.concat(names, " ")).toBe(table.concat(published, " "))
			for _, name in names do
				local contract = shared[name]
				local found = if contract
					then exported[contract] == true
					else exported[name .. "Props"] == true or exported[name .. "Spec"] == true
				t.expect(`{name}: {found}`).toBe(`{name}: true`)
			end
			for _, name in
				{ "Controls", "ControlOptions", "ThemePackage", "Cell", "Readable", "Runtime", "Owner", "Use" }
			do
				t.expect(`{name}: {exported[name] == true}`).toBe(`{name}: true`)
			end
			local reference = fs.readFile("docs/reference/api.md")
			for _, name in
				{ "Controls", "ControlOptions", "ThemePackage", "Cell<T>", "Readable<T>", "Runtime", "Owner", "Use" }
			do
				t.expect(string.find(reference, "`" .. name .. "`", 1, true) ~= nil).toBe(true)
			end
		end)

		t.it("documents every Facet.themes export and every capability in the guide catalog", function()
			local reference = fs.readFile("docs/reference/api.md")
			local section = string.sub(reference, (assert(string.find(reference, "\n## Themes\n", 1, true))))
			section = string.sub(section, 1, (string.find(section, "\n## ", 3, true) or #section))
			local function documented(name: string): boolean
				return string.find(section, "`" .. name, 1, true) ~= nil
					or string.find(section, "`themes." .. name, 1, true) ~= nil
			end
			local count = 0
			for name in Facet.themes do
				count += 1
				t.expect(`{name}: {documented(name :: string)}`).toBe(`{name}: true`)
			end
			t.expect(count >= 9).toBe(true)
			t.expect(documented("definitelyNotAnExport")).toBe(false)
			local guide = fs.readFile("docs/guide/README.md")
			local start = (assert(string.find(guide, "## Capability catalog", 1, true)))
			local catalog = string.sub(guide, start)
			local stop = string.find(catalog, "\n## ", 3, true)
			if stop then
				catalog = string.sub(catalog, 1, stop)
			end
			for _, name in controlNames() do
				t.expect(`UI.{name}: {string.find(catalog, "`UI." .. name .. "`", 1, true) ~= nil}`)
					.toBe(`UI.{name}: true`)
			end
			for name in Facet :: any do
				t.expect(`Facet.{name}: {string.find(catalog, "Facet." .. name, 1, true) ~= nil}`)
					.toBe(`Facet.{name}: true`)
			end
			local engine: any = engineLib.new()
			local UI = Facet.controls(Facet.Roblox.createRuntime(engine), { types = engine.types } :: any)
			for name in string.gmatch(catalog, "`UI%.([%a_][%w_]*)`") do
				t.expect(`UI.{name}: {(UI :: any)[name] ~= nil}`).toBe(`UI.{name}: true`)
			end
			for name in string.gmatch(catalog, "`Facet%.([%a_][%w_]*)") do
				t.expect(`Facet.{name}: {(Facet :: any)[name] ~= nil}`).toBe(`Facet.{name}: true`)
			end
			for _, file in fs.readDir("docs/extending") do
				t.expect(`{file}: {string.find(guide, "../extending/" .. file, 1, true) ~= nil}`).toBe(`{file}: true`)
			end
		end)

		t.it("syncs the gallery through one client-context bootstrap script", function()
			local found = 0
			for _, entry in studioTree.entries("gallery") do
				if entry.path == "ReplicatedStorage.Gallery" then
					found += 1
					t.expect(entry.className).toBe("Script")
					t.expect(entry.runContext).toBe("Client")
					t.expect(entry.file).toBe("examples/gallery/client/init.client.luau")
				end
				t.expect(string.find(entry.path, "StarterPlayerScripts.Gallery", 1, true)).toBeNil()
			end
			t.expect(found).toBe(1)
		end)

		t.it("gives every theme module a role and derives the eight shippable packages", function()
			local result = themePackages.check()
			t.expect(table.concat(result.problems, "\n")).toBe("")
			t.expect(result.ok).toBe(true)
			t.expect(#themePackages.files() >= 13).toBe(true)
			t.expect(#themePackages.byRole("reference")).toBe(9)
			t.expect(#themePackages.byRole("fixture") >= 2).toBe(true)
			t.expect(#themePackages.byRole("control") >= 2).toBe(true)
			t.expect(#themePackages.REFERENCE_ORDER).toBe(#themePackages.byRole("reference"))
			t.expect(table.concat(themePackages.shippable(), ",")).toBe(table.concat(EXPECTED_SHIPPABLE, ","))
			local excluded = 0
			for _ in themePackages.NOT_SHIPPABLE do
				excluded += 1
			end
			t.expect(#themePackages.shippable() + excluded).toBe(#themePackages.files())
			t.expect(themePackages.artifactName("fantasy_ornate")).toBe("FantasyOrnate")
			t.expect(themePackages.artifactName("classic_desktop")).toBe("ClassicDesktop")
			t.expect(themePackages.artifactName("scifi_hud")).toBe("ScifiHud")
			local seen = {}
			for _, name in themePackages.shippable() do
				local artifact = themePackages.artifactName(name)
				t.expect(seen[artifact]).toBeNil()
				seen[artifact] = name
			end
			local artifacts = fs.readFile("tools/lune/theme_artifacts.luau")
			t.expect(string.find(artifacts, "theme_packages.shippable()", 1, true) ~= nil).toBe(true)
		end)

		t.it("reports each kind of drift in the theme corpus", function()
			local function names(result: any, fragment: string): boolean
				for _, problem in result.problems do
					if string.find(problem, fragment, 1, true) then
						return true
					end
				end
				return false
			end
			local fresh = themePackages.check({ "brand_new_package" })
			t.expect(fresh.ok).toBe(false)
			t.expect(names(fresh, "brand_new_package.luau has no declared role")).toBe(true)
			local roles: any = themePackages.ROLES
			roles.a_package_that_moved = "reference"
			local moved = themePackages.check()
			roles.a_package_that_moved = nil
			t.expect(names(moved, "declares a role for 'a_package_that_moved'")).toBe(true)
			local excluded: any = themePackages.NOT_SHIPPABLE
			excluded.a_fixture_that_moved = "a reason long enough to satisfy the reason rule below it, and no more"
			local gone = themePackages.check()
			excluded.a_fixture_that_moved = nil
			t.expect(names(gone, "excludes 'a_fixture_that_moved'")).toBe(true)
			local reason = excluded.layered_test
			excluded.layered_test = "test"
			local short = themePackages.check()
			excluded.layered_test = reason
			t.expect(names(short, "NOT_SHIPPABLE['layered_test'] needs a REASON")).toBe(true)
			local control = excluded.custom_control
			excluded.custom_control = nil
			local leaked = themePackages.check()
			excluded.custom_control = control
			t.expect(names(leaked, "'custom_control' is shippable but its role is 'control'")).toBe(true)
			local order: any = themePackages.REFERENCE_ORDER
			local dropped = table.remove(order)
			local unordered = themePackages.check()
			table.insert(order, dropped)
			t.expect(names(unordered, `'{dropped}' is a reference package but is missing from REFERENCE_ORDER`))
				.toBe(true)
			t.expect(themePackages.check().ok).toBe(true)
		end)
	end)

	t.describe("Menu scenario copy", function()
		t.it("takes every player-visible string from its exported copy", function()
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			local input = engine.new("UserInputService")
			input.GetFocusedTextBox = function()
				return nil
			end
			local ctx = {
				Facet = Facet,
				Compose = Compose,
				runtime = runtime,
				Host = runtime.constructors,
				types = engine.types,
				viewport = Compose.cell({ width = 1280, height = 720 }),
				inputTarget = engine.new("Folder"),
				guiService = gui,
				UI = Facet.controls(
					runtime,
					{
						types = engine.types,
						guiService = gui,
						services = { GuiService = gui, UserInputService = input },
					} :: any
				),
			}
			local scenario = require("../examples/gallery/scenarios/menu")
			local host = engine.new("ScreenGui")
			local built
			local stop = runtime.mount(function()
				built = scenario.build(ctx)
				return built.screen()
			end, host)
			local function fromCopy(text: string): boolean
				for _, value in scenario.copy do
					if type(value) == "string" and value ~= "" and string.find(text, value, 1, true) then
						return true
					end
				end
				return false
			end
			local function strays(): { string }
				local out = {}
				for _, node in host:GetDescendants() do
					if (node.ClassName == "TextLabel" or node.ClassName == "TextButton") and node.Text ~= "" then
						if not fromCopy(node.Text) then
							table.insert(out, node.Text)
						end
					end
				end
				return out
			end
			t.expect(table.concat(strays(), " | ")).toBe("")
			local cards = 0
			for _, node in host:GetDescendants() do
				if node.Name == "Trigger" and node.ClassName == "TextButton" then
					cards += 1
				end
			end
			t.expect(cards).toBe(5)
			local trigger
			for _, node in host:GetDescendants() do
				if node.Name == "Trigger" and node.Text == scenario.copy.tap then
					trigger = node
				end
			end
			assert(trigger, "no Tap card").Activated.fire()
			t.expect(hasText(host, scenario.copy.accessory)).toBe(true)
			t.expect(table.concat(strays(), " | ")).toBe("")
			t.expect(fromCopy("A string the scenario never exported")).toBe(false)
			stop()
			runtime:dispose()
		end)
	end)

	t.describe("Collections", function()
		type Stage = {
			engine: any,
			UI: any,
			Host: any,
			gui: any,
			input: any,
			screen: any,
			writes: () -> number,
			stop: () -> (),
		}

		local function stage(build: (any, any) -> any, settings: { [string]: any }?): Stage
			local options: { [string]: any } = settings or {}
			local engine: any = engineLib.new()
			if options.clock then
				engine.clock = options.clock
			end
			local writes = 0
			if options.count then
				local make = engine.new
				engine.new = function(className)
					local node = make(className)
					local meta = getmetatable(node)
					local write = meta.__newindex
					meta.__newindex = function(self, key, value)
						writes += 1
						write(self, key, value)
					end
					return node
				end
			end
			local runtime = Facet.Roblox.createRuntime(engine)
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
				guiService = gui,
				services = { GuiService = gui, UserInputService = input },
			}
			for key, value in (options.config or {}) :: { [string]: any } do
				config[key] = value
			end
			local UI = Facet.controls(runtime, config :: any)
			local Host = runtime.constructors
			local stop, screen = runtime.mount(function()
				return Host.ScreenGui({ build(UI, Host) })
			end, engine.new("Folder"))
			return {
				engine = engine,
				UI = UI,
				Host = Host,
				gui = gui,
				input = input,
				screen = screen,
				writes = function()
					return writes
				end,
				stop = function()
					stop()
					runtime:dispose()
				end,
			}
		end

		local function records(count: number): { { id: number, label: string } }
			local values = {}
			for index = 1, count do
				values[index] = { id = index, label = tostring(index) }
			end
			return values
		end

		local function id(item: any): number
			return item.id
		end

		local function newStatus(): any
			return Compose.cell({
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
			} :: any)
		end

		local function labelled(UI: any): (any) -> any
			return function(current)
				return UI.Button("Action")({
					label = function(use)
						return use(current).label
					end,
				})
			end
		end

		local function plain(Host: any): () -> any
			return function()
				return Host.Frame({})
			end
		end

		local function collectionOf(w: Stage): any
			return w.screen:FindFirstChildWhichIsA("ScrollingFrame", true)
		end

		local function press(w: Stage, name: string)
			w.screen:FindFirstChild("Facet" .. name):FindFirstChild(name).Pressed.fire()
		end

		local function rowHit(list: any, key: string): any
			return list:FindFirstChild("Items"):FindFirstChild(key):FindFirstChild("RowHit", true)
		end

		local function mountFailure(build: (any, any) -> any): string?
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			local UI = Facet.controls(
				runtime,
				{ types = engine.types, guiService = gui, services = { GuiService = gui } } :: any
			)
			local ok, message = pcall(function()
				local stop = runtime.mount(function()
					return runtime.constructors.ScreenGui({ build(UI, runtime.constructors) })
				end, engine.new("Folder"))
				stop()
			end)
			runtime:dispose()
			return if ok then nil else tostring(message)
		end

		t.it(
			"resumes following within followThreshold and rejoins the tail after the reader returns to the end",
			function()
				local source, status = Compose.cell(records(10)), newStatus()
				local w = stage(function(UI, Host)
					return UI.VirtualList({
						from = source,
						key = id,
						itemSize = 20,
						overscan = 0,
						follow = "end",
						followThreshold = 30,
						status = status,
						render = plain(Host),
					})
				end)
				local V2 = w.engine.types.Vector2
				local list = collectionOf(w)
				list.AbsoluteWindowSize = V2.new(200, 100)
				t.expect(list.CanvasPosition.Y).toBe(100)
				list.CanvasPosition = V2.new(0, 80)
				t.expect(status:peek().following).toBe(true)
				source:set(records(11))
				t.expect(list.CanvasPosition.Y).toBe(120)
				t.expect(status:peek().following).toBe(true)
				list.CanvasPosition = V2.new(0, 0)
				source:set(records(12))
				t.expect(list.CanvasPosition.Y).toBe(0)
				t.expect(status:peek().following).toBe(false)
				list.CanvasPosition = V2.new(0, status:peek().extent - 100)
				t.expect(status:peek().following).toBe(true)
				source:set(records(13))
				t.expect(list.CanvasPosition.Y).toBe(160)
				w.stop()
				local strict, strictStatus = Compose.cell(records(10)), newStatus()
				local d = stage(function(UI, Host)
					return UI.VirtualList({
						from = strict,
						key = id,
						itemSize = 20,
						overscan = 0,
						follow = "end",
						status = strictStatus,
						render = plain(Host),
					})
				end)
				local defaultList = collectionOf(d)
				defaultList.AbsoluteWindowSize = V2.new(200, 100)
				defaultList.CanvasPosition = V2.new(0, 80)
				strict:set(records(11))
				t.expect(defaultList.CanvasPosition.Y).toBe(80)
				t.expect(strictStatus:peek().following).toBe(false)
				defaultList.CanvasPosition = V2.new(0, 116)
				strict:set(records(12))
				t.expect(defaultList.CanvasPosition.Y).toBe(140)
				t.expect(strictStatus:peek().following).toBe(true)
				d.stop()
			end
		)

		t.it("settles the last page to the end and leaves it only after a decisive drag back", function()
			local now = 0
			local w = stage(function(UI, Host)
				return UI.VirtualList({
					from = records(10),
					key = id,
					itemSize = 40,
					snap = "item",
					reducedMotion = true,
					render = plain(Host),
				})
			end, {
				clock = function()
					return now
				end,
			})
			local function advance(seconds: number)
				for _ = 1, math.ceil(seconds * 60) do
					now += 1 / 60
					w.engine.heartbeat.fire(1 / 60)
				end
			end
			local V2 = w.engine.types.Vector2
			local pointer = { UserInputType = w.engine.types.Enum.UserInputType.MouseButton1 }
			local list = collectionOf(w)
			list.AbsoluteWindowSize = V2.new(200, 100)
			now = 1
			list.CanvasPosition = V2.new(0, 290)
			advance(0.2)
			t.expect(list.CanvasPosition.Y).toBe(300)
			now += 1
			list.InputBegan.fire(pointer)
			now += 1
			list.CanvasPosition = V2.new(0, 290)
			w.input.InputEnded.fire(pointer)
			advance(0.2)
			t.expect(list.CanvasPosition.Y).toBe(300)
			now += 1
			list.InputBegan.fire(pointer)
			now += 0.01
			list.CanvasPosition = V2.new(0, 290)
			w.input.InputEnded.fire(pointer)
			advance(0.2)
			t.expect(list.CanvasPosition.Y).toBe(280)
			w.stop()
		end)

		t.it("releases the snap frame hook once settled and writes nothing while idle", function()
			local now = 0
			local w = stage(function(UI, Host)
				return UI.VirtualList({
					from = records(20),
					key = id,
					itemSize = 40,
					snap = "item",
					reducedMotion = false,
					render = plain(Host),
				})
			end, {
				count = true,
				clock = function()
					return now
				end,
			})
			local function advance(seconds: number)
				for _ = 1, math.ceil(seconds * 60) do
					now += 1 / 60
					w.engine.heartbeat.fire(1 / 60)
				end
			end
			local list = collectionOf(w)
			list.AbsoluteWindowSize = w.engine.types.Vector2.new(200, 100)
			advance(0.5)
			local resting = w.engine.heartbeat.count()
			now += 1
			list.CanvasPosition = w.engine.types.Vector2.new(0, 26)
			t.expect(w.engine.heartbeat.count()).toBeGreaterThan(resting)
			advance(0.6)
			t.expect(list.CanvasPosition.Y).toBe(40)
			t.expect(w.engine.heartbeat.count()).toBe(resting)
			local before = w.writes()
			advance(1)
			t.expect(w.writes() - before).toBe(0)
			t.expect(list.CanvasPosition.Y).toBe(40)
			w.stop()
		end)

		t.it("offsets the header by the reorder gutter and the scroll and matches the row cell span", function()
			local w = stage(function(UI)
				return UI.Table({
					from = records(3),
					key = id,
					itemSize = 40,
					reorderable = true,
					onReorder = function() end,
					columns = {
						{ id = "a", width = 100 },
						{ id = "b", width = 120 },
					},
				})
			end)
			local V2 = w.engine.types.Vector2
			local node = w.screen:FindFirstChildWhichIsA("Frame")
			local header, body = node:FindFirstChild("Header"), node:FindFirstChild("Body")
			body.AbsoluteWindowSize = V2.new(400, 200)
			local rowNode = body:FindFirstChild("Items"):FindFirstChild("1")
			local cells = rowNode:FindFirstChild("Cells", true)
			local row = cells:FindFirstChild("DisclosingRow"):FindFirstChild("Row")
			local function cellOrigin(): number
				return rowNode.Position.X.Offset + cells.Position.X.Offset - body.CanvasPosition.X
			end
			local function cellWidth(): number
				return rowNode.Size.X.Offset + cells.Size.X.Offset + row.Size.X.Offset
			end
			t.expect(header.Position.X.Offset).toBe(56)
			t.expect(cellOrigin()).toBe(56)
			t.expect(header.Size.X.Offset).toBe(344)
			t.expect(cellWidth()).toBe(344)
			for _, column in { "a", "b" } do
				t.expect(header:FindFirstChild(column).Size).toBe(row:FindFirstChild(column).Size)
			end
			body.CanvasPosition = V2.new(30, 0)
			t.expect(header.Position.X.Offset).toBe(26)
			t.expect(cellOrigin()).toBe(26)
			body.CanvasPosition = V2.new(0, 0)
			body.AbsoluteWindowSize = V2.new(250, 200)
			t.expect(header:FindFirstChild("b").Visible).toBe(false)
			t.expect(row:FindFirstChild("b").Visible).toBe(false)
			t.expect(header:FindFirstChild("a").Visible).toBe(true)
			t.expect(row:FindFirstChild("a").Visible).toBe(true)
			t.expect(rowNode:FindFirstChild("Details", true) ~= nil).toBe(true)
			t.expect(header.Size.X.Offset).toBe(146)
			t.expect(cellWidth()).toBe(146)
			t.expect(cellOrigin()).toBe(header.Position.X.Offset)
			w.stop()
		end)

		t.it("removes the header band and sizes a non-scrolling table to its rows when header is false", function()
			for _, shown in { false, true } do
				local status = newStatus()
				local w = stage(function(UI)
					return UI.Table({
						from = records(3),
						key = id,
						itemSize = 40,
						scrolls = false,
						header = if shown then nil else false,
						status = status,
						columns = { { id = "label", width = 100 } },
					})
				end)
				local node = w.screen:FindFirstChildWhichIsA("Frame")
				local header, body = node:FindFirstChild("Header"), node:FindFirstChild("Body")
				t.expect(status:peek().extent).toBe(120)
				t.expect(header.Visible).toBe(shown)
				t.expect(body.Position.Y.Offset).toBe(if shown then 40 else 0)
				t.expect(node.Size.Y.Offset).toBe(if shown then 160 else status:peek().extent)
				w.stop()
			end
		end)

		t.it("keeps every column when their widths exactly fill the room and collapses one pixel narrower", function()
			local w = stage(function(UI)
				return UI.Table({
					from = records(2),
					key = id,
					itemSize = 40,
					columns = {
						{ id = "a", width = 100 },
						{ id = "b", width = 100 },
						{ id = "c", width = 100 },
					},
				})
			end)
			local V2 = w.engine.types.Vector2
			local node = w.screen:FindFirstChildWhichIsA("Frame")
			local header, body = node:FindFirstChild("Header"), node:FindFirstChild("Body")
			body.AbsoluteWindowSize = V2.new(300, 200)
			local rowNode = body:FindFirstChild("Items"):FindFirstChild("1")
			t.expect(rowNode:FindFirstChild("Details", true)).toBeNil()
			for _, column in { "a", "b", "c" } do
				t.expect(header:FindFirstChild(column).Visible).toBe(true)
				t.expect(rowNode:FindFirstChild(column, true).Visible).toBe(true)
			end
			body.AbsoluteWindowSize = V2.new(299, 200)
			t.expect(rowNode:FindFirstChild("Details", true) ~= nil).toBe(true)
			t.expect(header:FindFirstChild("c").Visible).toBe(false)
			t.expect(header:FindFirstChild("b").Visible).toBe(true)
			w.stop()
		end)

		t.it("activates the keyboard or gamepad selected table row with that row key and input", function()
			local activated: { any } = {}
			local focus: any = {}
			local selection = Compose.cell({})
			local w = stage(function(UI)
				return UI.Table({
					from = records(5),
					key = id,
					itemSize = 40,
					focus = focus,
					selection = selection,
					columns = { { id = "label", width = 100 } },
					onActivate = function(item, key, input)
						table.insert(activated, { item = item, key = key, input = input })
					end,
				})
			end)
			local E = w.engine.types.Enum
			local body = w.screen:FindFirstChildWhichIsA("Frame"):FindFirstChild("Body")
			body.AbsoluteWindowSize = w.engine.types.Vector2.new(300, 200)
			focus.focus(2)
			t.expect(w.gui.SelectedObject).toBe(rowHit(body, "2"))
			t.expect(w.gui.SelectedObject.Selectable).toBe(true)
			press(w, "CollectionDown")
			t.expect(w.gui.SelectedObject).toBe(rowHit(body, "3"))
			local enter = { UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.Return }
			w.gui.SelectedObject.Activated.fire(enter, 1)
			t.expect(#activated).toBe(1)
			t.expect(activated[1].key).toBe(3)
			t.expect(activated[1].item.id).toBe(3)
			t.expect(activated[1].input).toBe(enter)
			t.expect(selection:peek()).toEqual({ [3] = true })
			press(w, "CollectionUp")
			local buttonA = { UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }
			w.gui.SelectedObject.Activated.fire(buttonA, 1)
			t.expect(#activated).toBe(2)
			t.expect(activated[2].key).toBe(2)
			t.expect(activated[2].input).toBe(buttonA)
			t.expect(selection:peek()).toEqual({ [2] = true })
			w.stop()
			local listActivated: { any } = {}
			local l = stage(function(UI, Host)
				return UI.VirtualList({
					from = records(5),
					key = id,
					itemSize = 20,
					onActivate = function(_, key, input)
						table.insert(listActivated, { key = key, input = input })
					end,
					render = plain(Host),
				})
			end)
			local list = collectionOf(l)
			list.AbsoluteWindowSize = l.engine.types.Vector2.new(200, 100)
			local hit = rowHit(list, "4")
			t.expect(hit.Selectable).toBe(true)
			l.gui.SelectedObject = hit
			l.gui.SelectedObject.Activated.fire(buttonA, 1)
			t.expect(#listActivated).toBe(1)
			t.expect(listActivated[1].key).toBe(4)
			t.expect(listActivated[1].input).toBe(buttonA)
			l.stop()
		end)

		t.it("gives header and body cells the same column span under the neutral and ornate packages", function()
			local ornate = fantasyOrnate.build(Facet.themes)
			t.expect(ornate.identity ~= nil).toBe(true)
			for _, package in { false, ornate } do
				local w = stage(function(UI)
					return UI.Table({
						from = records(2),
						key = id,
						itemSize = 40,
						reorderable = true,
						onReorder = function() end,
						columns = {
							{ id = "fixed", width = 120, minWidth = 80, maxWidth = 200 },
							{ id = "fill" },
						},
					})
				end, { config = if package then { theme = package } else {} })
				local E = w.engine.types.Enum
				local node = w.screen:FindFirstChildWhichIsA("Frame")
				local header, body = node:FindFirstChild("Header"), node:FindFirstChild("Body")
				body.AbsoluteWindowSize = w.engine.types.Vector2.new(400, 200)
				local rowNode = body:FindFirstChild("Items"):FindFirstChild("2")
				local cells = rowNode:FindFirstChild("Cells", true)
				local row = cells:FindFirstChild("DisclosingRow"):FindFirstChild("Row")
				t.expect(rowNode.Position.X.Offset + cells.Position.X.Offset - body.CanvasPosition.X)
					.toBe(header.Position.X.Offset)
				t.expect(rowNode.Size.X.Offset + cells.Size.X.Offset + row.Size.X.Offset).toBe(header.Size.X.Offset)
				for _, column in { "fixed", "fill" } do
					local top, cell = header:FindFirstChild(column), row:FindFirstChild(column)
					t.expect(top.Size).toBe(cell.Size)
					t.expect(top.LayoutOrder).toBe(cell.LayoutOrder)
					t.expect(top.Visible).toBe(cell.Visible)
					local topFlex, cellFlex =
						top:FindFirstChildWhichIsA("UIFlexItem"), cell:FindFirstChildWhichIsA("UIFlexItem")
					t.expect(topFlex.FlexMode).toBe(cellFlex.FlexMode)
					t.expect(topFlex.FlexMode).toBe(if column == "fill" then E.UIFlexMode.Fill else E.UIFlexMode.None)
					local topLimit, cellLimit =
						top:FindFirstChildWhichIsA("UISizeConstraint"), cell:FindFirstChildWhichIsA("UISizeConstraint")
					t.expect(topLimit.MinSize).toBe(cellLimit.MinSize)
					t.expect(topLimit.MaxSize).toBe(cellLimit.MaxSize)
				end
				t.expect(header:FindFirstChild("fixed").Size.X.Offset).toBe(120)
				w.stop()
			end
		end)

		local function shrinkAtEnd(useTable: boolean)
			local measured, status = Compose.cell({}), newStatus()
			local w = stage(function(UI, Host)
				if useTable then
					return UI.Table({
						from = records(20),
						key = id,
						itemSize = 40,
						measured = measured,
						status = status,
						columns = { { id = "label", width = 100 } },
					})
				end
				return UI.VirtualList({
					from = records(20),
					key = id,
					itemSize = 40,
					measured = measured,
					status = status,
					render = plain(Host),
				})
			end)
			local list = collectionOf(w)
			list.AbsoluteWindowSize = w.engine.types.Vector2.new(200, 100)
			list.CanvasPosition = w.engine.types.Vector2.new(0, 700)
			t.expect(status:peek().extent).toBe(800)
			local function every(size: number): { [number]: number }
				local sizes = {}
				for index = 1, 20 do
					sizes[index] = size
				end
				return sizes
			end
			measured:set(every(20))
			t.expect(status:peek().extent).toBe(400)
			t.expect(list.CanvasPosition.Y).toBe(status:peek().extent - 100)
			t.expect(list.CanvasPosition.Y).toBe(300)
			t.expect(status:peek().last).toBe(20)
			measured:set(every(40))
			t.expect(status:peek().extent).toBe(800)
			t.expect(list.CanvasPosition.Y).toBe(600)
			w.stop()
		end

		t.it("keeps a table flush with the end when its bottom rows shrink", function()
			shrinkAtEnd(true)
		end)

		t.it("corrects the native offset when the rows at the end of a list shrink", function()
			shrinkAtEnd(false)
		end)

		t.it("keeps the grid anchor item at the top when the column count and a line extent change", function()
			local columns, measured, controls = Compose.cell(4), Compose.cell({}), {} :: { [string]: any }
			local w = stage(function(UI, Host)
				return UI.VirtualGrid({
					from = records(100),
					key = id,
					itemSize = 20,
					columns = columns,
					measured = measured,
					controls = controls,
					render = plain(Host),
				})
			end)
			local grid = collectionOf(w)
			grid.AbsoluteWindowSize = w.engine.types.Vector2.new(200, 100)
			grid.CanvasPosition = w.engine.types.Vector2.new(0, 200)
			t.expect(controls.placementOf(controls.indexOfKey(41)).offset).toBe(200)
			columns:set(2)
			t.expect(controls.placementOf(controls.indexOfKey(41)).offset).toBe(400)
			t.expect(grid.CanvasPosition.Y).toBe(400)
			measured:set({ [1] = 60 })
			t.expect(controls.placementOf(controls.indexOfKey(41)).offset).toBe(440)
			t.expect(grid.CanvasPosition.Y).toBe(440)
			w.stop()
		end)

		t.it("gives grid cells a focus readable that follows the focus ring", function()
			local focus: any = {}
			local w = stage(function(UI)
				return UI.VirtualGrid({
					from = records(12),
					key = id,
					itemSize = 20,
					columns = 4,
					focus = focus,
					render = labelled(UI),
				})
			end)
			collectionOf(w).AbsoluteWindowSize = w.engine.types.Vector2.new(200, 100)
			local third, second = focus.isFocused(3), focus.isFocused(2)
			t.expect(third:peek()).toBe(false)
			focus.focus(3)
			t.expect(focus.current:peek()).toBe(3)
			t.expect(third:peek()).toBe(true)
			t.expect(second:peek()).toBe(false)
			t.expect(w.gui.SelectedObject.Text).toBe("3")
			focus.focus(2)
			t.expect(third:peek()).toBe(false)
			t.expect(second:peek()).toBe(true)
			t.expect(w.gui.SelectedObject.Text).toBe("2")
			w.stop()
		end)

		t.it("activates a vertical or horizontal grid cell from pointer and touch with its key", function()
			for _, direction in { "vertical", "horizontal" } do
				local activated: { any } = {}
				local w = stage(function(UI, Host)
					return UI.VirtualGrid({
						from = records(12),
						key = id,
						itemSize = 20,
						columns = 3,
						direction = direction,
						onActivate = function(item, key, input, clickCount)
							table.insert(activated, { item = item, key = key, input = input, clickCount = clickCount })
						end,
						render = plain(Host),
					})
				end)
				local E = w.engine.types.Enum
				local grid = collectionOf(w)
				grid.AbsoluteWindowSize = w.engine.types.Vector2.new(300, 300)
				local mouse = { UserInputType = E.UserInputType.MouseButton1 }
				local touch = { UserInputType = E.UserInputType.Touch }
				rowHit(grid, "3").Activated.fire(mouse, 1)
				rowHit(grid, "5").Activated.fire(touch, 1)
				t.expect(#activated).toBe(2)
				t.expect(activated[1].key).toBe(3)
				t.expect(activated[1].item.id).toBe(3)
				t.expect(activated[1].input).toBe(mouse)
				t.expect(activated[1].clickCount).toBe(1)
				t.expect(activated[2].key).toBe(5)
				t.expect(activated[2].input).toBe(touch)
				w.stop()
			end
		end)

		t.it("steps grid focus cell by cell with Left and Right and stops at the line edge", function()
			local focus: any = {}
			local w = stage(function(UI)
				return UI.VirtualGrid({
					from = records(12),
					key = id,
					itemSize = 20,
					columns = 4,
					focus = focus,
					render = labelled(UI),
				})
			end)
			collectionOf(w).AbsoluteWindowSize = w.engine.types.Vector2.new(200, 100)
			focus.focus(2)
			press(w, "CollectionRight")
			t.expect(focus.current:peek()).toBe(3)
			t.expect(w.gui.SelectedObject.Text).toBe("3")
			press(w, "CollectionLeft")
			t.expect(focus.current:peek()).toBe(2)
			focus.focus(4)
			press(w, "CollectionRight")
			t.expect(focus.current:peek()).toBe(4)
			press(w, "CollectionDown")
			t.expect(focus.current:peek()).toBe(8)
			w.stop()
		end)

		t.it("transposes horizontal grid navigation and scrolls a focused cell into view on X", function()
			local focus: any = {}
			local w = stage(function(UI)
				return UI.VirtualGrid({
					from = records(30),
					key = id,
					itemSize = 20,
					columns = 3,
					direction = "horizontal",
					focus = focus,
					render = labelled(UI),
				})
			end)
			local grid = collectionOf(w)
			grid.AbsoluteWindowSize = w.engine.types.Vector2.new(100, 300)
			focus.focus(1)
			press(w, "CollectionDown")
			t.expect(focus.current:peek()).toBe(2)
			press(w, "CollectionUp")
			t.expect(focus.current:peek()).toBe(1)
			press(w, "CollectionRight")
			t.expect(focus.current:peek()).toBe(4)
			t.expect(grid.CanvasPosition).toBe(w.engine.types.Vector2.new(0, 0))
			focus.focus(28)
			t.expect(grid.CanvasPosition).toBe(w.engine.types.Vector2.new(100, 0))
			t.expect(w.gui.SelectedObject.Text).toBe("28")
			w.stop()
		end)

		t.it("steps a horizontal list with Left and Right, ignores Up and Down and keeps focus visible on X", function()
			local focus: any = {}
			local w = stage(function(UI)
				return UI.VirtualList({
					from = records(20),
					key = id,
					itemSize = 20,
					direction = "horizontal",
					focus = focus,
					render = labelled(UI),
				})
			end)
			local V2 = w.engine.types.Vector2
			local list = collectionOf(w)
			list.AbsoluteWindowSize = V2.new(100, 50)
			focus.focus(3)
			press(w, "CollectionRight")
			t.expect(focus.current:peek()).toBe(4)
			press(w, "CollectionDown")
			t.expect(focus.current:peek()).toBe(4)
			press(w, "CollectionUp")
			t.expect(focus.current:peek()).toBe(4)
			press(w, "CollectionLeft")
			t.expect(focus.current:peek()).toBe(3)
			t.expect(list.CanvasPosition).toBe(V2.new(0, 0))
			focus.focus(7)
			t.expect(list.CanvasPosition).toBe(V2.new(40, 0))
			t.expect(w.gui.SelectedObject.Text).toBe("7")
			for name, keys in { CollectionRight = { "Right", "DPadRight" }, CollectionLeft = { "Left", "DPadLeft" } } do
				local bound = {}
				for _, binding in w.screen:FindFirstChild("Facet" .. name):FindFirstChild(name):GetChildren() do
					bound[binding.KeyCode.Name] = true
				end
				for _, keyName in keys do
					t.expect(bound[keyName]).toBe(true)
				end
			end
			w.stop()
		end)

		t.it("activates a horizontal list item from pointer and touch with its key", function()
			local activated: { any } = {}
			local w = stage(function(UI, Host)
				return UI.VirtualList({
					from = records(10),
					key = id,
					itemSize = 20,
					direction = "horizontal",
					onActivate = function(item, key, input)
						table.insert(activated, { item = item, key = key, input = input })
					end,
					render = plain(Host),
				})
			end)
			local E = w.engine.types.Enum
			local list = collectionOf(w)
			list.AbsoluteWindowSize = w.engine.types.Vector2.new(100, 50)
			local touch = { UserInputType = E.UserInputType.Touch }
			rowHit(list, "2").Activated.fire(touch, 1)
			t.expect(#activated).toBe(1)
			t.expect(activated[1].key).toBe(2)
			t.expect(activated[1].item.id).toBe(2)
			t.expect(activated[1].input).toBe(touch)
			w.stop()
		end)

		t.it("wraps arrow and D-pad focus at both ends only when wrapFocus is set", function()
			for _, wrap in { true, false } do
				local focus: any = {}
				local w = stage(function(UI)
					return UI.VirtualList({
						from = records(5),
						key = id,
						itemSize = 20,
						wrapFocus = wrap,
						focus = focus,
						render = labelled(UI),
					})
				end)
				collectionOf(w).AbsoluteWindowSize = w.engine.types.Vector2.new(200, 100)
				focus.focus(5)
				press(w, "CollectionDown")
				t.expect(focus.current:peek()).toBe(if wrap then 1 else 5)
				t.expect(w.gui.SelectedObject.Text).toBe(if wrap then "1" else "5")
				focus.focus(1)
				press(w, "CollectionUp")
				t.expect(focus.current:peek()).toBe(if wrap then 5 else 1)
				focus.focus(3)
				press(w, "CollectionDown")
				t.expect(focus.current:peek()).toBe(4)
				press(w, "CollectionRight")
				t.expect(focus.current:peek()).toBe(4)
				w.stop()
			end
			local gridFocus: any = {}
			local g = stage(function(UI)
				return UI.VirtualGrid({
					from = records(12),
					key = id,
					itemSize = 20,
					columns = 4,
					wrapFocus = true,
					focus = gridFocus,
					render = labelled(UI),
				})
			end)
			collectionOf(g).AbsoluteWindowSize = g.engine.types.Vector2.new(200, 100)
			gridFocus.focus(10)
			press(g, "CollectionDown")
			t.expect(gridFocus.current:peek()).toBe(2)
			press(g, "CollectionUp")
			t.expect(gridFocus.current:peek()).toBe(10)
			gridFocus.focus(4)
			press(g, "CollectionRight")
			t.expect(gridFocus.current:peek()).toBe(1)
			gridFocus.focus(5)
			press(g, "CollectionLeft")
			t.expect(gridFocus.current:peek()).toBe(8)
			g.stop()
			local rowFocus: any = {}
			local h = stage(function(UI)
				return UI.VirtualList({
					from = records(5),
					key = id,
					itemSize = 20,
					direction = "horizontal",
					wrapFocus = true,
					focus = rowFocus,
					render = labelled(UI),
				})
			end)
			collectionOf(h).AbsoluteWindowSize = h.engine.types.Vector2.new(100, 50)
			rowFocus.focus(5)
			press(h, "CollectionDown")
			t.expect(rowFocus.current:peek()).toBe(5)
			press(h, "CollectionRight")
			t.expect(rowFocus.current:peek()).toBe(1)
			press(h, "CollectionLeft")
			t.expect(rowFocus.current:peek()).toBe(5)
			h.stop()
		end)

		t.it(
			"wraps next and previous focus past disabled rows and enters automatically once geometry exists",
			function()
				for _, wrap in { true, false } do
					local focus: any = {}
					local w = stage(function(UI)
						return UI.VirtualList({
							from = records(5),
							key = id,
							itemSize = 20,
							wrapFocus = wrap,
							focus = focus,
							render = labelled(UI),
						})
					end)
					collectionOf(w).AbsoluteWindowSize = w.engine.types.Vector2.new(200, 100)
					focus.focus(5)
					focus.next()
					t.expect(focus.current:peek()).toBe(if wrap then 1 else 5)
					t.expect(w.gui.SelectedObject.Text).toBe(if wrap then "1" else "5")
					focus.previous()
					t.expect(focus.current:peek()).toBe(if wrap then 5 else 4)
					w.stop()
				end
				local skipFocus: any = {}
				local s = stage(function(UI)
					return UI.VirtualList({
						from = records(5),
						key = id,
						itemSize = 20,
						wrapFocus = true,
						focus = skipFocus,
						disabled = function(item)
							return item.id == 1
						end,
						render = labelled(UI),
					})
				end)
				collectionOf(s).AbsoluteWindowSize = s.engine.types.Vector2.new(200, 100)
				skipFocus.focus(5)
				skipFocus.next()
				t.expect(skipFocus.current:peek()).toBe(2)
				t.expect(s.gui.SelectedObject.Text).toBe("2")
				s.stop()
				for _, auto in { true, false } do
					local a = stage(function(UI)
						return UI.VirtualList({
							from = records(5),
							key = id,
							itemSize = 20,
							autoFocus = auto,
							render = labelled(UI),
						})
					end)
					t.expect(a.gui.SelectedObject).toBeNil()
					collectionOf(a).AbsoluteWindowSize = a.engine.types.Vector2.new(200, 100)
					if auto then
						t.expect(a.gui.SelectedObject.Text).toBe("1")
					else
						t.expect(a.gui.SelectedObject).toBeNil()
					end
					a.stop()
				end
			end
		)
	end)

	t.describe("NavigationStack and CollapsibleView", function()
		type StackWorld = {
			engine: any,
			runtime: any,
			gui: any,
			input: any,
			screen: any,
			baseline: { live: number, connections: number },
			stop: () -> (),
		}

		local function world(build: (any, any) -> any, options: { [string]: any }?): StackWorld
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
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
				guiService = gui,
				services = { GuiService = gui, UserInputService = input },
			}
			for key, value in (options or {}) :: { [string]: any } do
				config[key] = value
			end
			local target = engine.new("Folder")
			local baseline = engine.census()
			local UI = Facet.controls(runtime, config :: any)
			local Host = runtime.constructors
			local stop, screen = runtime.mount(function()
				return Host.ScreenGui({ build(UI, Host) })
			end, target)
			return {
				engine = engine,
				runtime = runtime,
				gui = gui,
				input = input,
				screen = screen,
				baseline = baseline,
				stop = function()
					stop()
					runtime:dispose()
				end,
			}
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

		local function layers(stack: any): { any }
			local found = {}
			for _, child in stack:GetChildren() do
				if child:IsA("GuiObject") then
					table.insert(found, child)
				end
			end
			return found
		end

		local function counted(Host: any, name: string, counts: { built: number, disposed: number })
			return function()
				counts.built += 1
				Compose.cleanup(function()
					counts.disposed += 1
				end)
				return Host.Frame({ Name = name })
			end
		end

		t.it("fades a pushed page in over its transition and swaps immediately under reduced motion", function()
			local path = Compose.cell({})
			local counts = { built = 0, disposed = 0 }
			local w = world(function(UI, Host)
				return UI.NavigationStack({
					path = path,
					transition = { seconds = 0.2 },
					root = { title = "Root", content = counted(Host, "RootBody", counts) },
					destinations = {
						detail = { title = "Detail", content = counted(Host, "DetailBody", counts) },
						more = { title = "More", content = counted(Host, "MoreBody", counts) },
					},
				})
			end)
			local root = find(w.screen, "@root")
			t.expect(root.ClassName).toBe("CanvasGroup")
			w.engine.heartbeat.fire(0.3)
			t.expect(root.GroupTransparency).toBe(0)
			t.expect(root.Visible).toBe(true)
			t.expect(root.Interactable).toBe(true)
			path:set({ { id = "detail" } })
			local detail = find(w.screen, "DetailBody").Parent.Parent
			t.expect(detail.Name).toBe("detail")
			t.expect(detail.ClassName).toBe("CanvasGroup")
			t.expect(detail.GroupTransparency).toBe(1)
			t.expect(detail.Interactable).toBe(true)
			t.expect(root.Interactable).toBe(false)
			w.engine.heartbeat.fire(0.1)
			t.expect(detail.GroupTransparency).toBeGreaterThan(0)
			t.expect(detail.GroupTransparency).toBeLessThan(1)
			t.expect(root.GroupTransparency).toBeGreaterThan(0)
			t.expect(root.GroupTransparency).toBeLessThan(1)
			t.expect(root.Visible).toBe(true)
			t.expect(root.Interactable).toBe(false)
			w.engine.heartbeat.fire(0.2)
			t.expect(detail.GroupTransparency).toBe(0)
			t.expect(detail.Visible).toBe(true)
			t.expect(root.Visible).toBe(false)
			t.expect(root.GroupTransparency).toBe(1)
			w.gui.ReducedMotionEnabled = true
			path:set({ path:peek()[1], { id = "more" } })
			local more = find(w.screen, "MoreBody").Parent.Parent
			t.expect(more.Name).toBe("more")
			t.expect(more.GroupTransparency).toBe(0)
			t.expect(more.Visible).toBe(true)
			t.expect(more.Interactable).toBe(true)
			t.expect(detail.Visible).toBe(false)
			t.expect(detail.Interactable).toBe(false)
			t.expect(counts.built).toBe(3)
			t.expect(counts.disposed).toBe(0)
			w.stop()
			t.expect(counts.disposed).toBe(3)
		end)

		t.it("leaves one opaque interactive root page after rapid pushes and pops under a fade", function()
			local path = Compose.cell({})
			local counts = { built = 0, disposed = 0 }
			local w = world(function(UI, Host)
				return UI.NavigationStack({
					path = path,
					transition = { seconds = 0.2 },
					root = { title = "Root", content = counted(Host, "RootBody", counts) },
					destinations = { detail = { title = "Detail", content = counted(Host, "DetailBody", counts) } },
				})
			end)
			local stack = find(w.screen, "NavigationStack")
			local root = find(w.screen, "@root")
			w.engine.heartbeat.fire(0.3)
			for _ = 1, 4 do
				path:set({ { id = "detail" } })
				w.engine.heartbeat.fire(1 / 120)
				t.expect(root.Interactable).toBe(false)
				path:set({})
				w.engine.heartbeat.fire(1 / 120)
				t.expect(root.Interactable).toBe(true)
			end
			t.expect(counts.built).toBe(5)
			t.expect(counts.disposed).toBe(4)
			w.engine.heartbeat.fire(1)
			local present = layers(stack)
			t.expect(#present).toBe(1)
			t.expect(present[1]).toBe(root)
			t.expect(root.Visible).toBe(true)
			t.expect(root.GroupTransparency).toBe(0)
			t.expect(root.Interactable).toBe(true)
			t.expect(find(w.screen, "DetailBody")).toBeNil()
			t.expect(counts.built - counts.disposed).toBe(1)
			w.stop()
			t.expect(counts.disposed).toBe(5)
		end)

		t.it("restores the remembered page focus when surviving chrome holds selection during a pop", function()
			local path = Compose.cell({})
			local w = world(function(UI, Host)
				return Host.Frame({
					UI.Button "Chrome" { label = "Chrome" },
					UI.NavigationStack({
						path = path,
						root = {
							content = function()
								return Host.Frame({
									UI.Button "First" { label = "First" },
									UI.Button "RootAction" { label = "Root" },
								})
							end,
						},
						destinations = {
							detail = {
								content = function()
									return UI.Button "DetailAction" { label = "Detail" }
								end,
							},
						},
					}),
				})
			end)
			local chrome, action = find(w.screen, "Chrome"), find(w.screen, "RootAction")
			w.gui.SelectedObject = action
			path:set({ { id = "detail" } })
			t.expect(w.gui.SelectedObject.Name).toBe("Back")
			w.gui.SelectedObject = chrome
			path:set({})
			t.expect(w.gui.SelectedObject).toBe(action)
			w.gui.SelectedObject = chrome
			path:set({ { id = "detail" } })
			path:set({})
			path:set({ { id = "detail" } })
			path:set({})
			t.expect(w.gui.SelectedObject).toBe(action)
			w.gui.SelectedObject = nil
			path:set({ { id = "detail" } })
			path:set({})
			t.expect(w.gui.SelectedObject).toBeNil()
			w.stop()
		end)

		t.it(
			"falls back to the first selectable control when the remembered control was disabled while away",
			function()
				local path, enabled = Compose.cell({}), Compose.cell(true)
				local w = world(function(UI, Host)
					return UI.NavigationStack({
						path = path,
						root = {
							content = function()
								return Host.Frame({
									UI.Button "First" { label = "First" },
									UI.Button "Remember" { label = "Remember", enabled = enabled },
								})
							end,
						},
						destinations = {
							detail = {
								content = function()
									return UI.Button "DetailAction" { label = "Detail" }
								end,
							},
						},
					})
				end)
				local remember = find(w.screen, "Remember")
				w.gui.SelectedObject = remember
				path:set({ { id = "detail" } })
				t.expect(w.gui.SelectedObject.Name).toBe("Back")
				path:set({})
				t.expect(w.gui.SelectedObject).toBe(remember)
				path:set({ { id = "detail" } })
				enabled:set(false)
				t.expect(remember.Interactable).toBe(false)
				path:set({})
				t.expect(w.gui.SelectedObject.Name).toBe("First")
				t.expect(w.gui.SelectedObject ~= remember).toBe(true)
				w.stop()
			end
		)

		t.it("refuses malformed specs, paths and transitions before building any page", function()
			local function attempt(mutate: (spec: { [string]: any }) -> ()): (string?, number)
				local built = 0
				local engine: any = engineLib.new()
				local runtime = Facet.Roblox.createRuntime(engine)
				local gui = engine.new("GuiService")
				local UI = Facet.controls(runtime, { types = engine.types, services = { GuiService = gui } } :: any)
				local function content()
					built += 1
					return runtime.constructors.Frame({})
				end
				local spec: { [string]: any } = {
					path = Compose.cell({}),
					root = { title = "Root", content = content },
					destinations = { detail = { title = "Detail", content = content } },
				}
				mutate(spec)
				local ok, message = pcall(function()
					local stop = runtime.mount(function()
						return UI.NavigationStack(spec)
					end, engine.new("ScreenGui"))
					stop()
				end)
				runtime:dispose()
				return if ok then nil else tostring(message), built
			end
			local accepted, acceptedBuilt = attempt(function() end)
			t.expect(accepted).toBeNil()
			t.expect(acceptedBuilt).toBe(1)
			local required = "NavigationStack requires path, root and destinations"
			local cases: { { mutate: (spec: { [string]: any }) -> (), expected: string } } = {
				{
					mutate = function(spec)
						spec.unknown = true
					end,
					expected = "unknown option 'unknown'",
				},
				{
					mutate = function(spec)
						spec.path = Compose.formula(function()
							return {}
						end)
					end,
					expected = required,
				},
				{
					mutate = function(spec)
						spec.path = Compose.cell({ { id = "missing" } })
					end,
					expected = "NavigationStack path has an undeclared destination",
				},
				{
					mutate = function(spec)
						spec.destinations = nil
					end,
					expected = required,
				},
				{
					mutate = function(spec)
						spec.root = nil
					end,
					expected = required,
				},
				{
					mutate = function(spec)
						spec.transition = { unknown = true }
					end,
					expected = "Navigation transition uses Compose tween options: seconds, ease",
				},
			}
			for _, case in cases do
				local message, built = attempt(case.mutate)
				t.expect(message ~= nil and string.find(message, case.expected, 1, true) ~= nil).toBe(true)
				t.expect(built).toBe(0)
			end
		end)

		t.it("keeps the mounted page through viewport theme input and reduced motion changes", function()
			local path = Compose.cell({})
			local counts = { built = 0, disposed = 0 }
			local theme = Compose.cell(Facet.themes.neutralPackage())
			local viewport = Compose.cell({ width = 1280, height = 720 })
			local w = world(function(UI, Host)
				return UI.NavigationStack({
					path = path,
					transition = { seconds = 0.2 },
					root = { title = "Root", content = counted(Host, "RootBody", counts) },
					destinations = { detail = { title = "Detail", content = counted(Host, "DetailBody", counts) } },
				})
			end, { theme = theme, viewport = viewport })
			local Enum, V2 = w.engine.types.Enum, w.engine.types.Vector2
			path:set({ { id = "detail" } })
			w.engine.heartbeat.fire(0.3)
			local body, stack = find(w.screen, "DetailBody"), find(w.screen, "NavigationStack")
			local page = body.Parent.Parent
			t.expect(counts.built).toBe(2)
			w.gui.ReducedMotionEnabled = true
			w.input.PreferredInput = Enum.PreferredInput.Gamepad
			w.input.PreferredInput = Enum.PreferredInput.Touch
			stack.AbsoluteSize = V2.new(400, 800)
			w.screen.AbsoluteSize = V2.new(400, 800)
			viewport:set({ width = 400, height = 800 })
			local evening = Facet.themes.neutralPackage()
			theme:set(evening)
			w.gui.ReducedMotionEnabled = false
			w.engine.heartbeat.fire(0.3)
			t.expect(find(w.screen, "DetailBody")).toBe(body)
			t.expect(find(w.screen, "detail")).toBe(page)
			t.expect(page.Visible).toBe(true)
			t.expect(page.GroupTransparency).toBe(0)
			t.expect(counts.built).toBe(2)
			t.expect(counts.disposed).toBe(0)
			w.stop()
			t.expect(counts.disposed).toBe(2)
		end)

		t.it("releases an expanded collapsible surface across open close cycles and on unmount", function()
			local expanded, image = Compose.cell(false), Compose.cell("rbxassetid://1")
			local w = world(function(UI)
				return UI.CollapsibleView "Summary" {
					label = "Summary",
					image = image,
					expanded = expanded,
					content = function()
						return UI.Button "DetailsAction" { label = "Details" }
					end,
				}
			end)
			local summary = find(w.screen, "Summary")
			w.gui.SelectedObject = summary
			local collapsed = w.engine.census()
			expanded:set(true)
			t.expect(find(w.screen, "Expanded") ~= nil).toBe(true)
			t.expect(w.engine.census().live).toBeGreaterThan(collapsed.live)
			expanded:set(false)
			t.expect(find(w.screen, "Expanded")).toBeNil()
			local settled = w.engine.census()
			for index = 1, 20 do
				expanded:set(true)
				t.expect(find(w.screen, "Expanded") ~= nil).toBe(true)
				image:set(if index % 2 == 0 then "rbxassetid://1" else "rbxassetid://2")
				expanded:set(false)
				t.expect(find(w.screen, "Expanded")).toBeNil()
				t.expect(w.gui.SelectedObject).toBe(summary)
			end
			image:set("rbxassetid://1")
			local after = w.engine.census()
			t.expect(after.live).toBe(settled.live)
			t.expect(after.connections).toBe(settled.connections)
			expanded:set(true)
			local panel, back = find(w.screen, "Expanded"), find(w.screen, "ModalBack")
			t.expect(panel ~= nil).toBe(true)
			t.expect(back ~= nil).toBe(true)
			t.expect(w.gui.SelectedObject ~= summary).toBe(true)
			w.stop()
			t.expect(panel:isDestroyed()).toBe(true)
			t.expect(back:isDestroyed()).toBe(true)
			t.expect(summary:isDestroyed()).toBe(true)
			local selected = w.gui.SelectedObject
			t.expect(selected).toBeNil()
			local final = w.engine.census()
			t.expect(final.live).toBe(w.baseline.live)
			t.expect(final.connections).toBe(w.baseline.connections)
		end)
	end)
end)
