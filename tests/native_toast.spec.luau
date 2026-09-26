--!strict
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

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

describe("toast schedule: showing, queueing and timing out", function()
	it("shows up to maxVisible and queues the rest, newest last", function()
		local f = fixture()
		for i = 1, 5 do
			f.schedule.push({ data = `t{i}` })
		end
		expect(f.keys()).toBe("t1,t2,t3")
		expect(f.schedule.counts().queued).toBe(2)
	end)

	it("a toast times out after its duration and the queue promotes in that frame", function()
		local f = fixture()
		f.schedule.push({ data = "a", duration = 2 })
		f.schedule.push({ data = "b", duration = 2 })
		f.schedule.push({ data = "c", duration = 2 })
		f.schedule.push({ data = "d", duration = 2 })
		expect(f.keys()).toBe("a,b,c")
		f.advance(1.9)
		expect(f.keys()).toBe("a,b,c")
		f.advance(0.2)
		expect(f.keys()).toBe("d")
		expect(#f.events).toBe(3)
		expect(f.events[1].reason).toBe("timeout")
	end)

	it("durations and read floors are per-toast, not global", function()
		local f = fixture()
		f.schedule.push({ data = "short", duration = 1 })
		f.schedule.push({ data = "long", duration = 6 })
		f.advance(1.5)
		expect(f.keys()).toBe("long")
	end)

	it("the defaults are the ratified numbers", function()
		expect(toast_schedule.DEFAULTS.maxVisible).toBe(3)
		expect(toast_schedule.DEFAULTS.queueCap).toBe(8)
		expect(toast_schedule.DEFAULTS.duration).toBe(4)
		expect(toast_schedule.DEFAULTS.readFloor).toBe(2.5)
	end)
end)

describe("toast schedule: priority", function()
	it("the queue is priority-ordered, FIFO within a priority", function()
		local f = fixture({ maxVisible = 1 })
		f.schedule.push({ data = "first", duration = 10 })
		f.schedule.push({ data = "low", priority = 0 })
		f.schedule.push({ data = "high", priority = 5 })
		f.schedule.push({ data = "low2", priority = 0 })
		local queued = f.schedule.queued()
		expect(queued[1].data).toBe("high")
		expect(queued[2].data).toBe("low")
		expect(queued[3].data).toBe("low2")
	end)

	it("a more urgent toast NEVER truncates a showing toast's read floor", function()
		local f = fixture({ maxVisible = 1 })
		f.schedule.push({ data = "reading", duration = 10, readFloor = 1.5 })
		f.schedule.push({ data = "urgent", priority = 10 })
		-- the floor is not up: the urgent toast waits, however urgent it is
		f.advance(1.4)
		expect(f.keys()).toBe("reading")
		expect(#f.events).toBe(0)
		-- the moment the floor is met, it takes the slot
		f.advance(0.2)
		expect(f.keys()).toBe("urgent")
		expect(#f.events).toBe(1)
		expect(f.events[1].reason).toBe("preempt")
	end)

	it("preemption takes the WEAKEST showing toast, not the oldest", function()
		local f = fixture({ maxVisible = 2 })
		f.schedule.push({ data = "important", priority = 5, duration = 10 })
		f.schedule.push({ data = "trivial", priority = 0, duration = 10 })
		f.schedule.push({ data = "urgent", priority = 9 })
		f.advance(3) -- past the 2.5 s read floor, so the weakest is preemptable
		expect(f.keys()).toBe("important,urgent")
	end)

	it("a queued toast no more urgent than the weakest showing one just waits", function()
		local f = fixture({ maxVisible = 1 })
		f.schedule.push({ data = "showing", priority = 5, duration = 10 })
		f.schedule.push({ data = "same", priority = 5 })
		f.advance(5)
		expect(f.keys()).toBe("showing")
		expect(#f.events).toBe(0)
	end)
end)

describe("toast schedule: supersede and capacity", function()
	it("a same-key toast replaces its QUEUED predecessor immediately", function()
		local f = fixture({ maxVisible = 1 })
		f.schedule.push({ data = "hold", duration = 10 })
		f.schedule.push({ data = "lap 1", key = "lap" })
		f.schedule.push({ data = "lap 2", key = "lap" })
		expect(f.schedule.counts().queued).toBe(1)
		expect(f.schedule.queued()[1].data).toBe("lap 2")
		expect(#f.events).toBe(1)
		expect(f.events[1].reason).toBe("supersede")
	end)

	it("a same-key toast replaces a SHOWING one only once its floor is met", function()
		local f = fixture({ maxVisible = 3 })
		f.schedule.push({ data = "lap 1", key = "lap", duration = 10, readFloor = 1.5 })
		f.schedule.push({ data = "lap 2", key = "lap", duration = 10 })
		expect(f.keys()).toBe("lap 1")
		f.advance(1.0)
		expect(f.keys()).toBe("lap 1")
		f.advance(0.6)
		expect(f.keys()).toBe("lap 2")
		expect(f.events[1].reason).toBe("supersede")
	end)

	it("at the queue cap the LOWEST-priority queued toast is dropped, with a reason", function()
		local f = fixture({ maxVisible = 1, queueCap = 3 })
		f.schedule.push({ data = "showing", duration = 10 })
		f.schedule.push({ data = "q1", priority = 3 })
		f.schedule.push({ data = "q2", priority = 2 })
		f.schedule.push({ data = "q3", priority = 1 })
		expect(f.schedule.counts().queued).toBe(3)
		expect(#f.events).toBe(0)
		f.schedule.push({ data = "q4", priority = 4 })
		expect(f.schedule.counts().queued).toBe(3)
		expect(#f.events).toBe(1)
		expect(f.events[1].reason).toBe("capacity")
		local queued = f.schedule.queued()
		expect(queued[1].data).toBe("q4")
		expect(queued[3].data).toBe("q2")
	end)

	it("a newcomer that IS the least urgent thing drops itself, and says so", function()
		local f = fixture({ maxVisible = 1, queueCap = 1 })
		f.schedule.push({ data = "showing", duration = 10 })
		f.schedule.push({ data = "kept", priority = 5 })
		f.schedule.push({ data = "dropped", priority = 1 })
		expect(f.schedule.queued()[1].data).toBe("kept")
		expect(#f.events).toBe(1)
		expect(f.events[1].reason).toBe("capacity")
	end)

	it("a SHOWING toast is never dropped for capacity", function()
		local f = fixture({ maxVisible = 2, queueCap = 1 })
		f.schedule.push({ data = "a", duration = 10 })
		f.schedule.push({ data = "b", duration = 10 })
		for i = 1, 6 do
			f.schedule.push({ data = `flood{i}`, priority = -1 })
		end
		expect(f.keys()).toBe("a,b")
		for _, event in f.events do
			expect(event.reason).toBe("capacity")
		end
	end)

	it("a burst never stacks unbounded", function()
		local f = fixture()
		for i = 1, 200 do
			f.schedule.push({ data = `spam{i}` })
		end
		local counts = f.schedule.counts()
		expect(counts.visible).toBe(3)
		expect(counts.queued).toBe(8)
	end)
end)

describe("toast schedule: explicit dismissal", function()
	it("dismiss retires a showing toast and promotes the queue in the same call", function()
		local f = fixture({ maxVisible = 1 })
		local id = f.schedule.push({ data = "a", duration = 10 })
		f.schedule.push({ data = "b", duration = 10 })
		expect(f.schedule.dismiss(id)).toBe(true)
		expect(f.keys()).toBe("b")
		expect(f.events[1].reason).toBe("manual")
	end)

	it("dismiss finds a QUEUED toast too, and an unknown id is a false, not an error", function()
		local f = fixture({ maxVisible = 1 })
		f.schedule.push({ data = "a", duration = 10 })
		local queued = f.schedule.push({ data = "b" })
		expect(f.schedule.dismiss(queued)).toBe(true)
		expect(f.schedule.counts().queued).toBe(0)
		expect(f.schedule.dismiss(9999)).toBe(false)
	end)
end)

type Toasts = { world: any, shown: { any }, reasons: { string } }

local function toasts(specs: { { [string]: any } }, options: any?): Toasts
	local reasons: { string } = {}
	local shown: { any } = {}
	for index, spec in specs do
		shown[index] = Compose.cell(true)
		spec.onDismiss = function(reason: string)
			table.insert(reasons, `{spec.message or "content"}:{reason}`)
		end
	end
	local world = overlay.new(function(UI, Host)
		local children = { UI.Button "Under" { label = "Under" } }
		for index, spec in specs do
			table.insert(
				children,
				Compose.show(function(use)
					return use(shown[index])
				end, function()
					return UI.Toast(`T{index}`)(spec)
				end)
			)
		end
		return Host.Frame({ Name = "S", table.unpack(children) })
	end, options or { reducedMotion = true })
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

describe("UI.Toast: presentation", function()
	it("shows three, queues the rest, and retires each on schedule with its reason", function()
		local f = toasts({
			{ message = "a", duration = 2 },
			{ message = "b", duration = 2 },
			{ message = "c", duration = 2 },
			{ message = "d", duration = 2 },
		})
		f.world.advance(0.1)
		expect(messages(f.world)).toBe("a,b,c")
		f.world.advance(2, 4)
		expect(messages(f.world)).toBe("d")
		expect(table.concat(f.reasons, " ")).toBe("a:timeout b:timeout c:timeout")
		f.world.stop()
	end)

	it("is input-transparent and never takes the selection", function()
		local f = toasts({ { message = "Saved" } })
		local under = f.world.find("Under")
		f.world.gui.SelectedObject = under
		f.world.advance(0.1)
		local row = rows(f.world)[1]
		expect(row.Interactable).toBe(false)
		expect(row.Active).toBe(false)
		for _, node in row:GetDescendants() do
			if node:IsA("GuiObject") then
				expect(node.Selectable).toBe(false)
			end
			expect(node:IsA("InputContext")).toBe(false)
		end
		expect(f.world.gui.SelectedObject).toBe(under)
		expect(row.ZIndex > 1 and row.ZIndex < 100).toBe(true)
		f.world.stop()
	end)

	it("stacks down from the top edge and the survivors close a vacated slot", function()
		local f = toasts({ { message = "a", duration = 10 }, { message = "b", duration = 10 } })
		f.world.advance(0.1)
		local list = rows(f.world)
		for _, row in list do
			row.AbsoluteSize = Vector2.new(300, 40)
		end
		f.world.advance(0.1)
		list = rows(f.world)
		expect(list[1].AnchorPoint.Y).toBe(0)
		expect(list[1].Position.Y.Offset).toBe(8)
		expect(list[2].Position.Y.Offset).toBe(56)
		f.shown[1]:set(false)
		f.world.advance(0.3)
		expect(messages(f.world)).toBe("b")
		expect(rows(f.world)[1].Position.Y.Offset).toBe(8)
		expect(f.reasons[1]).toBe("a:manual")
		f.world.stop()
	end)

	it("a bottom-docked stack grows upward from its own edge", function()
		local f = toasts({ { message = "a", position = "bottom" } })
		f.world.advance(0.1)
		local row = rows(f.world)[1]
		expect(row.AnchorPoint.Y).toBe(1)
		expect(row.Position.Y.Scale).toBe(1)
		expect(row.Position.Y.Offset).toBe(-8)
		f.world.stop()
	end)

	it("docks clear of the app's reserved chrome on its edge, in its own or a sibling ScreenGui", function()
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
		expect(offsets()).toBe("a:-68 b:38")
		other.Enabled = false
		f.world.advance(0.1)
		expect(offsets()).toBe("a:-8 b:38")
		other.Enabled = true
		reservations.clear(other, bar)
		reservations.clear(f.world.screen, notice)
		f.world.advance(0.1)
		expect(offsets()).toBe("a:-8 b:8")
		f.world.stop()
	end)

	it("a TabView bottom bar reserves its band on its layer, and a top bar does not", function()
		for _, case in { { "bottomBar", 44 }, { "topBar", 0 } } do
			local world = overlay.new(function(UI, Host)
				local tabs = {}
				for _, id in { "home", "feed" } do
					table.insert(tabs, {
						id = id,
						label = id,
						content = function()
							return Host.Frame({ Name = "Page-" .. id })
						end,
					})
				end
				return UI.TabView({ selection = Compose.cell("home"), placement = case[1], tabs = tabs })
			end, { reducedMotion = true })
			local bar = world.find("Tabs")
			bar.AbsolutePosition = Vector2.new(0, if case[2] > 0 then 556 else 0)
			bar.AbsoluteSize = Vector2.new(800, 44)
			expect(`{case[1]}: {world.screen:GetAttribute("FacetInsetBottom") or 0}`).toBe(`{case[1]}: {case[2]}`)
			world.stop()
			expect(`{case[1]} after: {world.screen:GetAttribute("FacetInsetBottom") or 0}`).toBe(`{case[1]} after: 0`)
		end
	end)

	it("a same-key toast replaces the showing one after its read floor", function()
		local f = toasts({ { message = "lap 1", key = "lap", duration = 10 }, { message = "lap 2", key = "lap" } })
		f.world.advance(1)
		expect(messages(f.world)).toBe("lap 1")
		f.world.advance(2, 4)
		expect(messages(f.world)).toBe("lap 2")
		expect(f.reasons[1]).toBe("lap 1:supersede")
		f.world.stop()
	end)

	it("fill spans the layer less the margins; hug fits the text, centred, up to 560", function()
		local f = toasts({ { message = "a" }, { message = "b", width = "hug" } }, { reducedMotion = true })
		f.world.advance(0.1)
		local list = rows(f.world)
		expect(list[1].Size.X.Offset).toBe(800 - 32)
		expect(list[1].Position.X.Scale).toBe(0.5)
		expect(list[2].AutomaticSize).toBe(f.world.Enum.AutomaticSize.XY)
		expect(overlay.find(list[2], "WidthCap").MaxSize.X).toBe(560)
		f.world.stop()
	end)

	it("slides in with native text by default; fade = true also fades it in and out", function()
		local plain = toasts({ { message = "a", duration = 1, readFloor = 0 } }, { reducedMotion = false })
		plain.world.advance(0.05, 3)
		local row = rows(plain.world)[1]
		expect(row.Position.Y.Offset < 8).toBe(true)
		expect(row:FindFirstChild("Fade")).toBeNil()
		plain.world.advance(1, 60)
		row = rows(plain.world)[1]
		expect(row ~= nil and row.Position.Y.Offset < 8).toBe(true)
		expect(row:FindFirstChild("Fade")).toBeNil()
		plain.world.stop()
		local faded = toasts({ { message = "a", duration = 1, readFloor = 0, fade = true } }, { reducedMotion = false })
		faded.world.advance(0.05, 3)
		local group = rows(faded.world)[1]:FindFirstChild("Fade")
		expect(group ~= nil and group.GroupTransparency > 0).toBe(true)
		faded.world.advance(0.5, 30)
		expect(rows(faded.world)[1]:FindFirstChild("Fade")).toBeNil()
		faded.world.advance(0.55, 33)
		group = rows(faded.world)[1]:FindFirstChild("Fade")
		expect(group ~= nil and group.GroupTransparency > 0).toBe(true)
		faded.world.stop()
	end)

	it("refuses a malformed toast by name", function()
		for index, bad in
			{
				{} :: any,
				{ message = "a", content = function() end },
				{ message = "a", position = "left" },
				{ message = "a", width = 300 },
				{ message = "a", duration = -1 },
				{ message = "a", extra = true },
				{ message = "a", fade = "yes" },
			}
		do
			local ok = pcall(function()
				toasts({ bad }).world.stop()
			end)
			expect(`case {index}: {ok}`).toBe(`case {index}: false`)
		end
	end)
end)

describe("app.presentToast", function()
	local Facet = require("../src") :: any
	local engineLib = require("./lib/native_engine")
	it("owns its body, returns an id and dismiss, and releases the layer when it retires", function()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		local target = engine.new("PlayerGui")
		local app = Facet.app({
			runtime = runtime,
			types = engine.types,
			parent = target,
			services = { GuiService = gui, UserInputService = input },
			reducedMotion = true,
		} :: any)
		local live = 0
		local toast = app.presentToast(function(UI)
			live += 1
			Compose.cleanup(function()
				live -= 1
			end)
			return UI.Text "Line" { text = "Saved" }
		end, { key = "save", duration = 20 })
		expect(type(toast.id)).toBe("number")
		expect(live).toBe(1)
		expect(#target:GetChildren()).toBe(1)
		for index = 2, 4 do
			app.presentToast(function(UI)
				return UI.Text { text = `Saved {index}` }
			end, { duration = 20 })
		end
		expect(#target:GetChildren()).toBe(1)
		expect(#overlay.findAll(target, "ToastRow")).toBe(3)
		expect(toast.dismiss()).toBe(true)
		expect(live).toBe(0)
		expect(#overlay.findAll(target, "ToastRow")).toBe(3)
		expect(toast.dismiss()).toBe(false)
		expect(pcall(app.presentToast, "no" :: any, {})).toBe(false)
		app.dispose()
	end)
end)
