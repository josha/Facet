--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local expect = Verify.expect

	local toast_schedule = require("../src/ui/toast_schedule")
	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")
	local reservations = require("../src/ui/reservations")
	local Vector2 = require("@lune/roblox").Vector2

	type Fixture = {
		schedule: any,
		advance: (seconds: number) -> (),
		events: { { id: number, key: string?, reason: string } },
		keys: () -> string,
	}

	local function fixture(opts: any?): Fixture
		local now = 0
		local events: { { id: number, key: string?, reason: string } } = {}
		local options: any = opts or {}
		options.now = function()
			return now
		end
		options.onDismiss = function(entry: any, reason: string)
			table.insert(events, { id = entry.id, key = entry.key, reason = reason })
		end
		local schedule = toast_schedule.new(options)
		return {
			schedule = schedule,
			events = events,
			advance = function(seconds: number)
				now += seconds
				schedule.update()
			end,
			keys = function(): string
				local out: { string } = {}
				for _, entry in schedule.visible() do
					table.insert(out, tostring(entry.data))
				end
				return table.concat(out, ",")
			end,
		}
	end

	verifyHarness:suite("toast schedule: showing, queueing and timing out", function()
		verifyHarness:case("shows up to maxVisible and queues the rest, newest last", {
			id = "native_toast_schedule::toast schedule: showing, queueing and timing out::shows up to maxVisible and queues the rest, newest last",
			run = function()
				local f = fixture()
				for i = 1, 5 do
					f.schedule.push({ data = `t{i}` })
				end
				expect((f.keys())):toBe("t1,t2,t3")
				expect(f.schedule.counts().queued):toBe(2)
			end,
		})

		verifyHarness:case("a toast times out after its duration and the queue promotes in that frame", {
			id = "native_toast_schedule::toast schedule: showing, queueing and timing out::a toast times out after its duration and the queue promotes in that frame",
			run = function()
				local f = fixture()
				f.schedule.push({ data = "a", duration = 2 })
				f.schedule.push({ data = "b", duration = 2 })
				f.schedule.push({ data = "c", duration = 2 })
				f.schedule.push({ data = "d", duration = 2 })
				expect((f.keys())):toBe("a,b,c")
				f.advance(1.9)
				expect((f.keys())):toBe("a,b,c")
				f.advance(0.2)
				expect((f.keys())):toBe("d")
				expect(#f.events):toBe(3)
				expect(f.events[1].reason):toBe("timeout")
			end,
		})

		verifyHarness:case("durations and read floors are per-toast, not global", {
			id = "native_toast_schedule::toast schedule: showing, queueing and timing out::durations and read floors are per-toast, not global",
			run = function()
				local f = fixture()
				f.schedule.push({ data = "short", duration = 1 })
				f.schedule.push({ data = "long", duration = 6 })
				f.advance(1.5)
				expect((f.keys())):toBe("long")
			end,
		})
	end)

	verifyHarness:suite("toast schedule: priority", function()
		verifyHarness:case("a more urgent toast NEVER truncates a showing toast's read floor", {
			id = "native_toast_schedule::toast schedule: priority::a more urgent toast NEVER truncates a showing toast's read floor",
			run = function()
				local f = fixture({ maxVisible = 1 })
				f.schedule.push({ data = "reading", duration = 10, readFloor = 1.5 })
				f.schedule.push({ data = "urgent", priority = 10 })

				f.advance(1.4)
				expect((f.keys())):toBe("reading")
				expect(#f.events):toBe(0)

				f.advance(0.2)
				expect((f.keys())):toBe("urgent")
				expect(#f.events):toBe(1)
				expect(f.events[1].reason):toBe("preempt")
			end,
		})

		verifyHarness:case("preemption takes the WEAKEST showing toast, not the oldest", {
			id = "native_toast_schedule::toast schedule: priority::preemption takes the WEAKEST showing toast, not the oldest",
			run = function()
				local f = fixture({ maxVisible = 2 })
				f.schedule.push({ data = "important", priority = 5, duration = 10 })
				f.schedule.push({ data = "trivial", priority = 0, duration = 10 })
				f.schedule.push({ data = "urgent", priority = 9 })
				f.advance(3)
				expect((f.keys())):toBe("important,urgent")
			end,
		})

		verifyHarness:case("a queued toast no more urgent than the weakest showing one just waits", {
			id = "native_toast_schedule::toast schedule: priority::a queued toast no more urgent than the weakest showing one just waits",
			run = function()
				local f = fixture({ maxVisible = 1 })
				f.schedule.push({ data = "showing", priority = 5, duration = 10 })
				f.schedule.push({ data = "same", priority = 5 })
				f.advance(5)
				expect((f.keys())):toBe("showing")
				expect(#f.events):toBe(0)
			end,
		})
	end)

	verifyHarness:suite("toast schedule: supersede and capacity", function()
		verifyHarness:case("a same-key toast replaces a SHOWING one only once its floor is met", {
			id = "native_toast_schedule::toast schedule: supersede and capacity::a same-key toast replaces a SHOWING one only once its floor is met",
			run = function()
				local f = fixture({ maxVisible = 3 })
				f.schedule.push({ data = "lap 1", key = "lap", duration = 10, readFloor = 1.5 })
				f.schedule.push({ data = "lap 2", key = "lap", duration = 10 })
				expect((f.keys())):toBe("lap 1")
				f.advance(1.0)
				expect((f.keys())):toBe("lap 1")
				f.advance(0.6)
				expect((f.keys())):toBe("lap 2")
				expect(f.events[1].reason):toBe("supersede")
			end,
		})

		verifyHarness:case("a SHOWING toast is never dropped for capacity", {
			id = "native_toast_schedule::toast schedule: supersede and capacity::a SHOWING toast is never dropped for capacity",
			run = function()
				local f = fixture({ maxVisible = 2, queueCap = 1 })
				f.schedule.push({ data = "a", duration = 10 })
				f.schedule.push({ data = "b", duration = 10 })
				for i = 1, 6 do
					f.schedule.push({ data = `flood{i}`, priority = -1 })
				end
				expect((f.keys())):toBe("a,b")
				for _, event in f.events do
					expect(event.reason):toBe("capacity")
				end
			end,
		})
	end)

	verifyHarness:suite("toast schedule: held entries propose instead of retiring", function()
		verifyHarness:case("a held entry asks once per reason and stays until dismissed", {
			id = "native_toast_schedule::toast schedule: held entries propose instead of retiring::a held entry asks once per reason and stays until dismissed",
			run = function()
				local asked: { string } = {}
				local f = fixture({
					maxVisible = 1,
					onPropose = function(entry: any, reason: string)
						table.insert(asked, `{entry.data}:{reason}`)
					end,
				})
				f.schedule.push({ data = "held", duration = 2, held = true })
				f.advance(2.1)
				f.advance(5)
				expect((table.concat(asked, ","))):toBe("held:timeout")
				expect((f.keys())):toBe("held")
				f.schedule.push({ data = "urgent", priority = 5 })
				f.advance(1)
				expect((table.concat(asked, ","))):toBe("held:timeout,held:preempt")
				expect((f.keys())):toBe("held")
				f.schedule.dismiss(1, "action")
				expect((f.keys())):toBe("urgent")
				expect(f.events[1].reason):toBe("action")
			end,
		})

		verifyHarness:case("a queue cap below one still lets a toast show", {
			id = "native_toast_schedule::toast schedule: held entries propose instead of retiring::a queue cap below one still lets a toast show",
			run = function()
				local f = fixture({ queueCap = 0 })
				f.schedule.push({ data = "only" })
				expect((f.keys())):toBe("only")
			end,
		})

		verifyHarness:case("an infinite duration never times out", {
			id = "native_toast_schedule::toast schedule: held entries propose instead of retiring::an infinite duration never times out",
			run = function()
				local f = fixture()
				f.schedule.push({ data = "sticky", duration = math.huge })
				f.advance(1e6)
				expect((f.keys())):toBe("sticky")
			end,
		})
	end)

	verifyHarness:suite("toast schedule: explicit dismissal", function()
		verifyHarness:case("dismiss retires a showing toast and promotes the queue in the same call", {
			id = "native_toast_schedule::toast schedule: explicit dismissal::dismiss retires a showing toast and promotes the queue in the same call",
			run = function()
				local f = fixture({ maxVisible = 1 })
				local id = f.schedule.push({ data = "a", duration = 10 })
				f.schedule.push({ data = "b", duration = 10 })
				expect((f.schedule.dismiss(id))):toBe(true)
				expect((f.keys())):toBe("b")
				expect(f.events[1].reason):toBe("manual")
			end,
		})
	end)

	type Toasts = { world: any, shown: { any }, reasons: { string } }

	local function toasts(specs: { { [any]: any } }, options: any?): Toasts
		local reasons: { string } = {}
		local shown: { any } = {}
		for index, spec in specs do
			shown[index] = Compose.cell(true)
			spec.onDismiss = function(reason: string)
				table.insert(reasons, `{spec.message or "content"}:{reason}`)
			end
		end
		local world = overlay.new(function(UI: FacetControls, Host: RobloxHost)
			local children: { unknown } = { UI.Button "Under" { label = "Under" } }
			for index, spec in specs do
				table.insert(
					children,
					Compose.show(function(use: Use)
						return use(shown[index])
					end, function()
						return UI.Toast(`T{index}`)(spec)
					end)
				)
			end
			return Host.Frame({ Name = "S", table.unpack((children :: unknown) :: { unknown }) })
		end, options or { motionLevel = "none" })
		return { world = world, shown = shown, reasons = reasons }
	end

	local function rows(world: any): { any }
		local out = world.findAll("ToastRow")
		table.sort(out, function(a, b)
			return a.Position.Y.Offset < b.Position.Y.Offset
		end)
		return out
	end

	local function messages(world: any): string
		local out = {}
		for _, row in rows(world) do
			table.insert(out, overlay.find(row, "Message").Text)
		end
		return table.concat(out, ",")
	end

	verifyHarness:suite("UI.Toast: presentation", function()
		verifyHarness:case("is input-transparent and never takes the selection", {
			id = "native_toast_schedule::UI.Toast: presentation::is input-transparent and never takes the selection",
			run = function()
				local f = toasts({ { message = "Saved" } })
				local under = f.world.find("Under")
				f.world.gui.SelectedObject = under
				f.world.advance(0.1)
				local row = rows(f.world)[1]
				expect(row.Interactable):toBe(false)
				expect(row.Active):toBe(false)
				for _, node in row:GetDescendants() do
					if node:IsA("GuiObject") then
						expect(node.Selectable):toBe(false)
					end
					expect((node:IsA("InputContext"))):toBe(false)
				end
				expect(f.world.gui.SelectedObject):toBe(under)
				expect(row.ZIndex > 1 and row.ZIndex < 100):toBe(true)
				f.world.stop()
			end,
		})

		verifyHarness:case("stacks down from the top edge and the survivors close a vacated slot", {
			id = "native_toast_schedule::UI.Toast: presentation::stacks down from the top edge and the survivors close a vacated slot",
			run = function()
				local f = toasts({ { message = "a", duration = 10 }, { message = "b", duration = 10 } })
				f.world.advance(0.1)
				local list = rows(f.world)
				for _, row in list do
					row.AbsoluteSize = Vector2.new(300, 40)
				end
				f.world.advance(0.1)
				list = rows(f.world)
				expect(list[1].AnchorPoint.Y):toBe(0)
				expect(list[1].Position.Y.Offset):toBe(8)
				expect(list[2].Position.Y.Offset):toBe(56)
				f.shown[1]:set(false)
				f.world.advance(0.3)
				expect((messages(f.world))):toBe("b")
				expect(rows(f.world)[1].Position.Y.Offset):toBe(8)
				expect(f.reasons[1]):toBe("a:manual")
				f.world.stop()
			end,
		})

		verifyHarness:case("docks clear of the app's reserved chrome on its edge, in its own or a sibling ScreenGui", {
			id = "native_toast_schedule::UI.Toast: presentation::docks clear of the app's reserved chrome on its edge, in its own or a sibling ScreenGui",
			run = function()
				local f = toasts({ { message = "a", position = "bottom" }, { message = "b" } })
				f.world.advance(0.1)
				local other = f.world.engine.new("ScreenGui")
				other.Parent = f.world.screen.Parent
				other.AbsoluteSize = Vector2.new(800, 600)
				local bar, notice = {}, {}
				reservations.set(other, bar, "bottom", 540, 60)
				reservations.set(f.world.screen, notice, "top", 0, 30)
				f.world.advance(0.1)
				local function offsets(): string
					local out = {}
					for _, row in rows(f.world) do
						table.insert(out, `{overlay.find(row, "Message").Text}:{row.Position.Y.Offset}`)
					end
					table.sort(out)
					return table.concat(out, " ")
				end
				expect((offsets())):toBe("a:-68 b:38")
				other.Enabled = false
				f.world.advance(0.1)
				expect((offsets())):toBe("a:-8 b:38")
				other.Enabled = true
				reservations.clear(other, bar)
				reservations.clear(f.world.screen, notice)
				f.world.advance(0.1)
				expect((offsets())):toBe("a:-8 b:8")
				f.world.stop()
			end,
		})

		verifyHarness:case("a TabView bottom bar reserves its band on its layer, and a top bar does not", {
			id = "native_toast_schedule::UI.Toast: presentation::a TabView bottom bar reserves its band on its layer, and a top bar does not",
			run = function()
				for _, case in { { placement = "bottomBar", height = 44 }, { placement = "topBar", height = 0 } } do
					local world = overlay.new(function(UI: FacetControls, Host: RobloxHost)
						local tabs = {}
						for _, id in { "home", "feed" } do
							table.insert(tabs, {
								id = id,
								label = id,
								content = function(): Instance
									return Host.Frame({ Name = "Page-" .. id })
								end,
							})
						end
						return UI.TabView({
							selection = Compose.cell("home"),
							placement = case.placement :: "automatic" | "bottomBar" | "bottomBarCompact" | "none" | "sidebar" | "topBar",
							tabs = tabs,
						})
					end, { motionLevel = "none" })
					local bar = world.find("Tabs")
					bar.AbsolutePosition = Vector2.new(0, if case.height > 0 then 556 else 0)
					bar.AbsoluteSize = Vector2.new(800, 44)
					expect(`{case.placement}: {world.screen:GetAttribute("FacetInsetBottom") or 0}`):toBe(
						`{case.placement}: {case.height}`
					)
					world.stop()
					expect(`{case.placement} after: {world.screen:GetAttribute("FacetInsetBottom") or 0}`):toBe(
						`{case.placement} after: 0`
					)
				end
			end,
		})

		verifyHarness:case("fill spans the layer less the margins; hug fits the text, centred, up to 560", {
			id = "native_toast_schedule::UI.Toast: presentation::fill spans the layer less the margins; hug fits the text, centred, up to 560",
			run = function()
				local f = toasts(
					{ { message = "a" }, { message = "b", width = "hug" :: "hug" } },
					{ motionLevel = "none" }
				)
				f.world.advance(0.1)
				local list = rows(f.world)
				expect(list[1].Size.X.Offset):toBe(800 - 32)
				expect(list[1].Position.X.Scale):toBe(0.5)
				expect(list[2].AutomaticSize):toBe(f.world.Enum.AutomaticSize.Y)
				expect(overlay.find(list[2], "WidthCap").MaxSize.X):toBe(560)
				local probe = overlay.find(list[2], "MessageMeasure")
				probe.TextBounds = Vector2.new(100, 16)
				expect(list[2].Size.X.Offset):toBe(125)
				probe.TextBounds = Vector2.new(2000, 16)
				expect(list[2].Size.X.Offset):toBe(560)
				f.world.stop()
			end,
		})

		verifyHarness:case("fits the overlay that receives it and follows its resized width", {
			id = "native_toast_schedule::UI.Toast: presentation::fits the overlay that receives it and follows its resized width",
			run = function()
				local presentation
				local w = overlay.new(function(_, Host: RobloxHost, engine, _, runtime)
					presentation = Host.Frame "Presentation" {}
					local UI = require("../src/ui")(Compose, runtime, {
						types = engine.types,
						overlayParent = presentation :: Instance,
						motionLevel = "none",
					})
					return Host.Frame { presentation :: unknown, UI.Toast { message = "Ready" } }
				end)
				presentation.AbsoluteSize = Vector2.new(390, 720)
				w.advance(0.1)
				local row = w.find("ToastRow")
				expect((row:IsDescendantOf(presentation))):toBe(true)
				expect(row.Size.X.Offset):toBe(358)
				presentation.AbsoluteSize = Vector2.new(280, 720)
				w.advance(0.1)
				expect(row.Size.X.Offset):toBe(248)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("app.presentToast", function()
		local Facet = require("../src") :: any
		local engineLib = require("./lib/native_engine")
		verifyHarness:case("owns its body, returns an id and dismiss, and releases the layer when it retires", {
			id = "native_toast_schedule::app.presentToast::owns its body, returns an id and dismiss, and releases the layer when it retires",
			run = function()
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local gui, input = engine.new("GuiService"), engine.new("UserInputService")
				local target = engine.new("PlayerGui")
				local app = Facet.app({
					runtime = runtime,
					types = engine.types,
					parent = target,
					services = { GuiService = gui, UserInputService = input },
					motionLevel = "none",
				} :: any)
				local live = 0
				local toast = app.presentToast(function(UI: FacetControls)
					live += 1
					Compose.cleanup(function()
						live -= 1
					end)
					return UI.Text "Line" { text = "Saved" }
				end, { key = "save", duration = 20 })
				expect((type(toast.id))):toBe("number")
				expect(live):toBe(1)
				expect(#target:GetChildren()):toBe(1)
				for index = 2, 4 do
					app.presentToast(function(UI: FacetControls)
						return UI.Text { text = `Saved {index}` }
					end, { duration = 20 })
				end
				expect(#target:GetChildren()):toBe(1)
				expect(#overlay.findAll(target, "ToastRow")):toBe(3)
				expect((toast.dismiss())):toBe(true)
				expect(live):toBe(0)
				expect(#overlay.findAll(target, "ToastRow")):toBe(3)
				expect((toast.dismiss())):toBe(false)
				expect((pcall(app.presentToast, "no" :: any, {}))):toBe(false)
				app.dispose()
			end,
		})
	end)
end
