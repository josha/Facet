--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local UI = Facet.View

t.describe("component authoring", function()
	t.it("does not retain a retired getter through a source that points back to it", function()
		local watched = setmetatable({}, { __mode = "k" })
		local canary = setmetatable({}, { __mode = "k" })
		local function build()
			local core = Facet.newCore()
			local Example = Facet.component(function(ui)
				local value, setValue = ui.state({})
				setValue({ read = value })
				watched[value] = true
				return UI.Text({
					text = function()
						return tostring(value().read == value)
					end,
				})
			end)
			local mounted = Facet.mount(core, Example())
			mounted.dispose()
		end
		build()
		canary[{}] = true
		-- Lune cannot force GC. Allocation pressure plus an independent canary
		-- distinguishes actual collection from an inconclusive witness.
		for i = 1, 4000 do
			local waste = table.create(20000, i)
		end
		if next(canary) == nil then
			t.expect(next(watched)).toBeNil()
		else
			print("component getter collection witness: inconclusive; GC canary still live")
		end
	end)
	t.it("keeps a shared binding for its live owner across collection", function()
		local tracking = require("../src/core/tracking")
		local core = Facet.newCore()
		local owner = core:scope("component")
		local child = owner:child("control")
		tracking.inheritBindings(child, owner)
		local source = owner:own(core:signal(1))
		local read = require("../src/authoring").context(core, owner, nil).read(source)
		local recipe = function()
			return read() * 2
		end
		local binding = tracking.bind(core, child, recipe)
		for i = 1, 4000 do
			local waste = table.create(20000, i)
		end
		t.expect(tracking.bind(core, child, recipe)).toBe(binding)
		t.expect(tracking.bind(core, owner, recipe)).toBe(binding)
		source:set(3)
		t.expect(binding:get()).toBe(6)
		owner:dispose()
		t.expect(core:counters().memos).toBe(0)
	end)
	t.it("owns AsyncImage leases and recipe bindings through the declaring scope", function()
		for _, explicit in { false, true } do
			local core = Facet.newCore()
			local provider = Facet.newResourceProvider(core)
			local owner = core:scope("images")
			local spec = {
				id = "Image",
				key = "image",
				provider = provider,
				dimmed = function()
					return false
				end,
			}
			local description
			if explicit then
				spec.scope = owner
				description = Facet.Controls.AsyncImage(core, spec).blueprint
			else
				description = UI.AsyncImage(spec)
			end
			local mounted = Facet.mount(core, description)
			local pending = provider.pendingRequests()
			t.expect(#pending).toBe(1)
			mounted.dispose()
			owner:dispose()
			t.expect(provider.complete(pending[1].key, pending[1].generation, "image")).toBe("stale")
			t.expect(core:counters().memos).toBe(0)
			t.expect(core:counters().observers).toBe(0)
			t.expect(core:counters().scopes).toBe(0)
		end
	end)
	t.it("binds draggable availability without invoking payload callbacks", function()
		local core = Facet.newCore()
		local before = core:counters()
		local setEnabled, payloadCalls = nil, 0
		local Card = Facet.component(function(ui)
			local enabled, set = ui.state(true)
			setEnabled = set
			return UI.draggable(UI.Box({ id = "Card" }), {
				enabled = enabled,
				payload = function()
					payloadCalls += 1
					return "card"
				end,
			})
		end)
		local mounted = Facet.mount(core, Card({}))
		local source = mounted.node.meta.dragSource
		t.expect(source.enabled:get()).toBe(true)
		setEnabled(false)
		t.expect(source.enabled:get()).toBe(false)
		t.expect(payloadCalls).toBe(0)
		t.expect(source.payload()).toBe("card")
		t.expect(payloadCalls).toBe(1)
		mounted.dispose()
		t.expect(core:counters().signals).toBe(before.signals)
		t.expect(core:counters().memos).toBe(before.memos)
	end)
	t.it("mounts once, updates only bindings, and owns cleanup", function()
		local core = Facet.newCore()
		local before = core:counters()
		local setups, cleaned = 0, 0
		local setCount
		local Card = Facet.component(function(ui)
			setups += 1
			local count, set = ui.state(0)
			setCount = set
			ui.own(function()
				cleaned += 1
			end)
			return UI.VStack({
				id = "Card",
				gap = "s",
				UI.Text("Counter"),
				UI.Text({
					id = "Value",
					text = function()
						return tostring(count())
					end,
				}),
			})
		end)
		local description = Card()
		t.expect(core:counters()).toEqual(before)
		local root = Facet.mount(core, description)
		local node = root.node.children[2]
		t.expect(node.props.text).toBe("0")
		setCount(4)
		t.expect(node.props.text).toBe("4")
		t.expect(root.node.children[2]).toBe(node)
		t.expect(setups).toBe(1)
		root.dispose()
		t.expect(cleaned).toBe(1)
		t.expect(core:counters()).toEqual(before)
	end)
	t.it("normalizes ordered Region forms before recovery validation", function()
		local rich, compact = UI.Text("A complete headline"), UI.Text("Headline")
		local region = UI.Region({ id = "News", group = "news", rank = 1, recover = "none", rich, compact })
		t.expect(region.children).toEqual({ rich, compact })
		t.expect(pcall(function()
			UI.Region({ id = "Bad", group = "news", rank = 1, [2] = compact })
		end)).toBe(false)
	end)

	t.it("rejects sparse or ambiguous children and preserves numeric order", function()
		local a, b = UI.Text("A"), UI.Text("B")
		local bp = UI.VStack({ gap = "s", a, b })
		t.expect(bp.children).toEqual({ a, b })
		for _, spec in
			{
				{ [2] = a },
				{ a, children = { b } },
				{ [0] = a },
				{ children = { [2] = a } },
				{ children = { bad = a } },
			}
		do
			t.expect(pcall(function()
				UI.VStack(spec)
			end)).toBe(false)
		end
	end)
end)

t.describe("reactive authoring lifetimes and commands", function()
	t.it("watches changes only; effects clean up before rerun and unmount", function()
		local core = Facet.newCore()
		local seen, effects = {}, {}
		local write
		local Screen = Facet.component(function(ui)
			local value, setValue = ui.state(1)
			write = setValue
			ui.watch(value, function(v)
				table.insert(seen, v)
			end)
			ui.effect(function()
				local v = value()
				table.insert(effects, `start {v}`)
				return function()
					table.insert(effects, `stop {v}`)
				end
			end)
			return UI.Text(function()
				return tostring(value())
			end)
		end)
		local root = Facet.mount(core, Screen())
		t.expect(seen).toEqual({})
		write(2)
		write(2)
		t.expect(seen).toEqual({ 2 })
		root.dispose()
		t.expect(effects).toEqual({ "start 1", "stop 1", "start 2", "stop 2" })
		t.expect(core:counters().effects).toBe(0)
	end)
	t.it("uses a controlled getter and sends the requested value to its handler", function()
		local core = Facet.newCore()
		local write, value, requested
		local Screen = Facet.component(function(ui)
			value, write = ui.state(false)
			return UI.Toggle({
				id = "Enabled",
				value = value,
				onChange = function(v)
					requested = v
				end,
			})
		end)
		local root = Facet.mount(core, Screen())
		root.node.props.onActivate()
		t.expect(requested).toBe(true)
		t.expect(value()).toBe(false) -- the model decides whether to accept
		write(true)
		t.expect(root.node.props.value).toBe(true)
		root.dispose()
		t.expect(core:counters().signals).toBe(0)
	end)
	t.it("keeps keyed row identity and gives handlers the latest item", function()
		local core = Facet.newCore()
		local items = core:signal({ { id = "a", label = "old" }, { id = "b", label = "B" } })
		local label, builds = nil, 0
		local Screen = Facet.component(function(ui)
			return UI.ForEach({
				items = ui.read(items),
				key = function(item)
					return item.id
				end,
				row = function(item)
					builds += 1
					return UI.Button({
						label = function()
							return item().label
						end,
						onActivate = function()
							label = item().label
						end,
					})
				end,
			})
		end)
		local root = Facet.mount(core, Screen())
		local first = root.node.children[1]
		items:set({ { id = "b", label = "B2" }, { id = "a", label = "new" } })
		t.expect(root.node.children[2]).toBe(first)
		t.expect(first.props.label).toBe("new")
		first.props.onActivate("path", { source = "action" })
		t.expect(label).toBe("new")
		t.expect(builds).toBe(2)
		root.dispose()
		items:dispose()
		t.expect(core:counters().signals).toBe(0)
	end)
	t.it("updates from an official Signals getter without mirroring its state", function()
		local core = Facet.newCore()
		local read, write = Facet.Signals.createSignal("first")
		local root = Facet.mount(core, UI.Text(read))
		t.expect(root.node.props.text).toBe("first")
		write("second")
		t.expect(root.node.props.text).toBe("second")
		t.expect(core:counters().signals).toBe(0)
		root.dispose()
		t.expect(core:counters().memos).toBe(0)
	end)
	t.it("releases partially constructed components after a setup error", function()
		local core = Facet.newCore()
		local before = core:counters()
		local Bad = Facet.component(function(ui)
			ui.state(1)
			error("failed setup")
		end)
		t.expect(pcall(function()
			Facet.mount(core, Bad())
		end)).toBe(false)
		t.expect(core:counters()).toEqual(before)
	end)
end)

t.describe("component presentation and virtualization", function()
	local world = require("./lib/world")
	t.it("mounts component content in navigation pages and alerts", function()
		local w = world.new({ reducedMotion = true })
		local mounted, cleaned = 0, 0
		local Content = Facet.component(function(ui)
			mounted += 1
			ui.own(function()
				cleaned += 1
			end)
			return UI.Text({ id = "ComponentContent", text = "Content" })
		end)
		local routes = w.core:signal({})
		w.present(UI.NavigationStack({
			id = "Nav",
			backLabel = "Back",
			path = routes,
			root = {
				content = function()
					return Content({})
				end,
			},
			destinations = {},
		}))
		t.expect(mounted).toBe(1)
		local alert = Facet.Controls.Alert(w.core, {
			title = "Details",
			content = function()
				return Content({})
			end,
			actions = { { id = "OK", label = "OK" } },
		})
		alert.present(w.pres)
		w.settle(3)
		t.expect(mounted).toBe(2)
		alert.dispose()
		w.pres.dismiss(w.handle)
		w.settle(60)
		t.expect(cleaned).toBe(2)
		t.expect(w.core:lastError()).toBe(nil)
		routes:dispose()
	end)
	t.it("owns progress cycles and supplies the presenter clock without caller plumbing", function()
		local w = world.new({ reducedMotion = false })
		local before = w.core:counters()
		local Activity = Facet.component(function()
			return UI.Screen({
				id = "Activity",
				UI.ProgressView({ id = "Busy", presentation = "circular" }),
			})
		end)
		w.present(Activity({}))
		local function head()
			return w.adapter.node("/Activity/Busy/Ring/Arc").props.points[1]
		end
		local first = head()
		w.settle(20)
		local next = head()
		t.expect(math.abs(first.x - next.x) + math.abs(first.y - next.y) > 0.01).toBe(true)
		w.pres.dismiss(w.handle)
		w.settle(60)
		local after = w.core:counters()
		t.expect(after.scopes).toBe(before.scopes)
		t.expect(after.observers).toBe(before.observers)
		t.expect(w.core:lastError()).toBe(nil)
	end)

	t.it("confirms through Alert and preserves the originating activation metadata", function()
		local w = world.new({ reducedMotion = true })
		local events = {}
		w.present(UI.Screen({
			id = "Page",
			UI.Button({
				id = "Delete",
				label = "Delete",
				confirm = { title = "Delete save?", destructive = true },
				onActivate = function(meta)
					table.insert(events, meta)
				end,
			}),
		}))
		local origin = { source = "pointer", pointer = "mouse", shift = true }
		w.adapter.tap("/Page/Delete", origin)
		w.settle(3)
		t.expect(#events).toBe(0)
		w.adapter.tap("/Alert/Center/Card/Actions/Order/[Cancel]/Cancel")
		w.settle(20)
		t.expect(#events).toBe(0)
		w.adapter.tap("/Page/Delete", origin)
		w.settle(3)
		w.adapter.tap("/Alert/Center/Card/Actions/Order/[Confirm]/Confirm")
		w.settle(20)
		t.expect(#events).toBe(1)
		t.expect(events[1].shift).toBe(true)
		t.expect(events[1].pointer).toBe("mouse")
		t.expect(w.core:lastError()).toBe(nil)
		w.pres.dismiss(w.handle)
	end)
	t.it("a bound modal has no inline copy and closes with its declaring component", function()
		local w = world.new({ reducedMotion = true })
		local show
		local Page = Facet.component(function(ui)
			local open, setOpen = ui.state(false)
			show = setOpen
			return UI.Screen({
				id = "Page",
				UI.Text("The page"),
				UI.Alert({
					id = "Decision",
					title = "Continue?",
					isPresented = open,
					onPresentedChange = setOpen,
					actions = { { id = "Cancel", label = "Cancel", role = "cancel" } },
				}),
			})
		end)
		w.present(Page({}))
		t.expect(w.adapter.node("/Decision/Center/Card")).toBe(nil)
		show(true)
		w.settle(3)
		t.expect(w.adapter.node("/Decision/Center/Card") ~= nil).toBe(true)
		t.expect(w.adapter.node("/Page/Decision/Center/Card")).toBe(nil)
		w.pres.dismiss(w.handle)
		w.settle(30)
		t.expect(w.adapter.node("/Decision/Center/Card")).toBe(nil)
		t.expect(w.core:lastError()).toBe(nil)
	end)
	for _, name in { "VirtualList", "VirtualGrid" } do
		t.it(name .. " keeps a current item getter without mounting the whole collection", function()
			local w = world.new({ reducedMotion = true })
			local items = {}
			for i = 1, 1000 do
				items[i] = { id = tostring(i), label = `Item {i}` }
			end
			local state = w.core:signal(items)
			local builds, latest = 0, nil
			local Page = Facet.component(function(ui)
				local spec = {
					id = "Items",
					items = ui.read(state),
					itemExtent = 48,
					viewportExtent = 160,
					key = function(item)
						return item.id
					end,
					row = function(item)
						builds += 1
						if item().id == "1" then
							latest = item
						end
						return UI.Text(function()
							return item().label
						end)
					end,
				}
				if name == "VirtualGrid" then
					spec.columns = 2
				end
				return UI.Screen({ id = "Page", UI[name](spec) })
			end)
			w.present(Page({}))
			w.settle(3)
			local initialBuilds = builds
			t.expect(builds < 30).toBe(true)
			local nextItems = table.clone(items)
			nextItems[1] = { id = "1", label = "Replaced" }
			state:set(nextItems)
			w.settle(2)
			t.expect(latest().label).toBe("Replaced")
			t.expect(builds).toBe(initialBuilds)
			t.expect(w.core:lastError()).toBe(nil)
			w.pres.dismiss(w.handle)
			state:dispose()
		end)
	end
end)

t.describe("authoring release and composition", function()
	t.it("stopping a watcher releases its private bindings before unmount", function()
		local core = Facet.newCore()
		local stop, saved, write
		local calls = 0
		local Card = Facet.component(function(ui)
			saved = ui
			local value, set = ui.state(0)
			write = set
			stop = ui.watch(function()
				return value() * 2
			end, function()
				calls += 1
			end)
			return UI.Text("Card")
		end)
		local root = Facet.mount(core, Card({}))
		write(1)
		stop()
		stop()
		t.expect(core:counters().memos).toBe(0)
		t.expect(core:counters().observers).toBe(0)
		write(2)
		t.expect(calls).toBe(1)
		root.dispose()
		local before = core:counters()
		t.expect(pcall(function()
			saved.state(42)
		end)).toBe(false)
		t.expect(pcall(function()
			saved.memo(function()
				return 42
			end)
		end)).toBe(false)
		t.expect(pcall(function()
			saved.effect(function() end)
		end)).toBe(false)
		t.expect(core:counters()).toEqual(before)
	end)
	t.it("applies layout and style modifiers to the mounted component root", function()
		local core = Facet.newCore()
		local calls = 0
		local Card = Facet.component(function()
			calls += 1
			return UI.VStack({ UI.Text("Card") })
		end)
		local description = UI.frame(UI.padding(Card({}), 8), { width = 200 })
		t.expect(calls).toBe(0)
		local root = Facet.mount(core, description)
		t.expect(root.node.props.width.px).toBe(200)
		t.expect(root.node.props.padding).toBe(8)
		t.expect(calls).toBe(1)
		root.dispose()
	end)
	t.it("a failing effect cleanup does not disconnect later updates", function()
		local core = Facet.newCore()
		local write
		local seen = {}
		local Card = Facet.component(function(ui)
			local value, set = ui.state(0)
			write = set
			ui.effect(function()
				table.insert(seen, value())
				return function()
					error("bad cleanup")
				end
			end)
			return UI.Text("Card")
		end)
		local root = Facet.mount(core, Card({}))
		write(1)
		write(2)
		t.expect(seen).toEqual({ 0, 1, 2 })
		t.expect(string.find(core:lastError(), "bad cleanup", 1, true) ~= nil).toBe(true)
		root.dispose()
		t.expect(core:counters().effects).toBe(0)
	end)
end)

t.describe("nested authoring recipes", function()
	t.it("updates semantic row text and icon from functions", function()
		local core = Facet.newCore()
		local write
		local Card = Facet.component(function(ui)
			local text, set = ui.state("Before")
			write = set
			return UI.Button({
				label = "Setting",
				row = {
					description = text,
					icon = function()
						return "check"
					end,
				},
				onActivate = function() end,
			})
		end)
		local root = Facet.mount(core, Card({}))
		write("After")
		local found = false
		local function visit(node)
			if node.props and node.props.text == "After" then
				found = true
			end
			for _, child in node.children or {} do
				visit(child)
			end
		end
		visit(root.node)
		t.expect(found).toBe(true)
		t.expect(core:lastError()).toBe(nil)
		root.dispose()
	end)
	t.it("binds Sheet presentation and closes it with the declaring screen", function()
		local w = require("./lib/world").new({ reducedMotion = true })
		local show
		local Page = Facet.component(function(ui)
			local open, setOpen = ui.state(false)
			show = setOpen
			local detent, setDetent = ui.state("medium")
			return UI.Screen({
				id = "Page",
				UI.Text("Page"),
				UI.Sheet({
					id = "Details",
					title = "Details",
					detent = detent,
					onDetentChange = setDetent,
					isPresented = open,
					onPresentedChange = setOpen,
					content = UI.Text("Sheet content"),
				}),
			})
		end)
		w.present(Page({}))
		show(true)
		w.settle(10)
		t.expect(w.adapter.node("/Details/Layer/Panel") ~= nil).toBe(true)
		w.pres.dismiss(w.handle)
		w.settle(20)
		t.expect(w.adapter.node("/Details/Layer/Panel")).toBe(nil)
		t.expect(w.core:lastError()).toBe(nil)
	end)
end)

t.describe("composition shortcuts", function()
	t.it("normalizes custom children, preserves named slots and snapshots the description", function()
		local core = Facet.newCore()
		local Card = Facet.component(function(_, props)
			return UI.VStack({ children = props.children, UI.Text("ambiguous") })
		end)
		t.expect(pcall(function()
			Facet.mount(core, Card({ UI.Text("A") }))
		end)).toBe(false)
		local Section = Facet.component(function(_, props)
			return UI.VStack({ UI.Text(props.title), UI.VStack({ children = props.children }), props.footer })
		end)
		local spec = { title = "Before", footer = UI.Text("Footer"), UI.Text("A"), UI.Text("B") }
		local description = Section(spec)
		spec.title = "After"
		spec[1] = UI.Text("Changed")
		local root = Facet.mount(core, description)
		t.expect(root.node.children[1].props.text).toBe("Before")
		t.expect(root.node.children[2].children[1].props.text).toBe("A")
		t.expect(root.node.children[2].children[2].props.text).toBe("B")
		t.expect(root.node.children[3].props.text).toBe("Footer")
		root.dispose()
	end)
	t.it("shares plain getters between controls and primitives only within each mount", function()
		local core = Facet.newCore()
		local value = core:signal(true)
		local calls = 0
		local enabled
		local Card = Facet.component(function(ui)
			local read = ui.read(value)
			enabled = enabled or function()
				calls += 1
				return read()
			end
			return UI.VStack({
				UI.Button({ label = "A", enabled = enabled, onActivate = function() end }),
				UI.Button({ label = "B", enabled = enabled, onActivate = function() end }),
				UI.Text({ text = "C", hidden = enabled }),
			})
		end)
		local first = Facet.mount(core, Card({}))
		t.expect(calls).toBe(1)
		local second = Facet.mount(core, Card({}))
		t.expect(calls).toBe(2)
		value:set(false)
		t.expect(calls).toBe(4)
		first.dispose()
		value:set(true)
		t.expect(calls).toBe(5)
		second.dispose()
		value:dispose()
		t.expect(core:counters().memos).toBe(0)
	end)
	t.it("accepts a key field and row component while retaining identity on replacement", function()
		local core = Facet.newCore()
		local items = core:signal({ { id = "a", name = "A" }, { id = "b", name = "B" } })
		local builds = 0
		local Row = Facet.component(function(_, item)
			builds += 1
			return UI.Text(function()
				return item().name
			end)
		end)
		local root = Facet.mount(core, UI.ForEach({ items = items, key = "id", row = Row }))
		local first = root.node.children[1]
		items:set({ { id = "b", name = "B2" }, { id = "a", name = "A2" } })
		t.expect(builds).toBe(2)
		t.expect(root.node.children[2]).toBe(first)
		t.expect(first.props.text).toBe("A2")
		root.dispose()
		items:dispose()
	end)
	t.it("validates a shared getter for each destination property", function()
		local core = Facet.newCore()
		local function value()
			return 2
		end
		t.expect(pcall(function()
			Facet.mount(core, UI.ZStack({ scale = value, opacity = value }))
		end)).toBe(false)
		t.expect(core:counters().memos).toBe(0)
	end)
	t.it("rejects ambiguous conditional children and malformed animation policies", function()
		local child = UI.Text("A")
		for _, spec in
			{
				{ condition = true, child, child },
				{
					condition = true,
					child,
					thenView = function()
						return child
					end,
				},
			}
		do
			t.expect(pcall(function()
				UI.When(spec)
			end)).toBe(false)
		end
		for _, spec in
			{
				{ animation = { skale = "object" } },
				{ animation = { scale = true } },
				{ animation = { scale = "missing" } },
			}
		do
			t.expect(pcall(function()
				UI.Box(spec)
			end)).toBe(false)
		end
		t.expect(pcall(function()
			UI.Text({ text = "A", animation = { opacity = "object" } })
		end)).toBe(false)
		local core = Facet.newCore()
		t.expect(pcall(function()
			Facet.mount(core, UI.Alert({ isPresented = core:signal(false), animation = { layout = "object" } }))
		end)).toBe(false)
		t.expect(core:counters().memos).toBe(0)
	end)
end)
