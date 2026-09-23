--!strict
--[[ UI.Popover — a caller-owned presentation fact, rendered as an anchored panel
	or, on a compact touch screen, a sheet. Every case drives a real route
	(adapter.tap, deviceKey, the catcher, a sheet's Close/drag) and asserts what
	is mounted, never a callback's argument alone. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local world = require("./lib/world")
local fake = require("./lib/fake_target")
local Facet = require("../src") :: any
local Compose = Facet.Compose

local SURFACE = "/Popover-Tip/Layer/Surface"
local PANEL = `{SURFACE}/Popup/Panel`
local BODY = `{PANEL}/Body`
local POINTER = {
	capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false },
	preferredInput = "KeyboardAndMouse",
}

type Log = { changes: { boolean }, dismissed: { string } }

-- a caller that owns `open`, accepting (or refusing) every proposal
local function caller(accept: boolean?): (any, Log, (boolean) -> ())
	local open = Compose.cell(false)
	local log: Log = { changes = {}, dismissed = {} }
	local accepting = accept ~= false
	return open,
		log,
		function(next: boolean)
			table.insert(log.changes, next)
			if accepting then
				open:set(next)
			end
		end
end

local function mount(spec: any, opts: any?): any
	local o = opts or {}
	local w = world.new({
		viewport = { x = 0, y = 0, w = o.w or 800, h = o.h or 600 },
		reducedMotion = true,
		-- the live reserve: the solver keeps content off an overflowing body's bar
		newAdapter = function()
			local a = fake.new()
			a.scrollBarThickness = fake.SCROLL_BAR_RESERVE
			return a
		end,
	})
	if o.classes ~= nil then
		w.env:set("capabilities", o.classes.capabilities)
		w.env:set("preferredInput", o.classes.preferredInput)
	end
	local UI = w.UI
	w.present(function()
		local children: { any } = {
			UI.Popover("Tip")(spec(UI)),
			UI.Button("Other")({ label = "Other" }),
		}
		for _, extra in o.extra or {} do
			table.insert(children, extra(UI))
		end
		return UI.Screen("S")({ padding = 0, table.unpack(children) })
	end)
	w.settle(2)
	return w
end

local function content(UI: any): any
	return UI.VStack("Card")({
		UI.Text("Line")({ text = "Popover body" }),
		UI.Button("Inner")({ label = "Inner" }),
	})
end

describe("Popover: the caller's fact decides, proposals ask", function()
	it("a trigger press proposes, and an accepted fact presents an anchored panel", function()
		local open, log, change = caller()
		local w = mount(function(UI)
			return {
				isPresented = open,
				onPresentedChange = change,
				trigger = UI.Button("Open")({ label = "Open" }),
				content = function()
					return content(UI)
				end,
			}
		end)
		expect(w.adapter.node(PANEL)).toBeNil()
		for _, p in w.adapter.paths() do
			if string.find(p, "Open") then
				print("PATH", p, w.adapter.node(p).onActivate ~= nil)
			end
		end
		w.adapter.tap("/S/Open")
		w.settle(2)
		expect(#log.changes).toBe(1)
		expect(log.changes[1]).toBe(true)
		expect(w.adapter.node(`{BODY}/Card/Line`).props.text).toBe("Popover body")
		expect(w.record("Tip").dump().route).toBe("popover")
	end)

	it("a refused proposal presents nothing, and a refused close keeps the same surface and focus", function()
		local open, log, change = caller(false)
		local w = mount(function(UI)
			return {
				isPresented = open,
				onPresentedChange = change,
				trigger = UI.Button("Open")({ label = "Open" }),
				content = function()
					return content(UI)
				end,
			}
		end)
		w.adapter.tap("/S/Open")
		w.settle(2)
		expect(w.adapter.node(PANEL)).toBeNil()
		-- the caller opens it itself, then refuses every close
		open:set(true)
		w.settle(2)
		local panelNode = w.adapter.node(PANEL)
		expect(panelNode ~= nil).toBe(true)
		w.pres.focus.focusOn(`{BODY}/Card/Inner`)
		w.press("Escape")
		w.settle(2)
		w.press("ButtonB")
		w.settle(2)
		w.adapter.tap(w.pres.topScrimPath() :: string, { x = 790, y = 590 })
		w.settle(2)
		expect(w.adapter.node(PANEL) == panelNode).toBe(true)
		expect(w.pres.focus.focused:peek()).toBe(`{BODY}/Card/Inner`)
		expect(#log.dismissed).toBe(0)
		expect(log.changes[#log.changes]).toBe(false)
	end)

	it("Cancel, an outside tap and a press on the trigger each close with their own reason, once", function()
		-- an open popover is modal, so a press on its trigger lands OUTSIDE it
		for _, case in { "cancel", "outside", "trigger" } do
			local open, log, change = caller()
			local w = mount(function(UI)
				return {
					isPresented = open,
					onPresentedChange = change,
					onDismiss = function(reason: string)
						table.insert(log.dismissed, reason)
					end,
					trigger = UI.Button("Open")({ label = "Open" }),
					content = function()
						return content(UI)
					end,
				}
			end)
			open:set(true)
			w.settle(2)
			expect(w.adapter.node(PANEL) ~= nil).toBe(true)
			if case == "cancel" then
				w.press("ButtonB")
			elseif case == "outside" then
				w.adapter.tap(w.pres.topScrimPath() :: string, { x = 790, y = 590 })
			else
				w.adapter.tap("/S/Open")
			end
			w.settle(2)
			expect(`{case}: {tostring(w.adapter.node(PANEL) == nil)}`).toBe(`{case}: true`)
			expect(open:peek()).toBe(false)
			expect(table.concat(log.dismissed, ",")).toBe(if case == "trigger" then "outside" else case)
		end
	end)

	it("without onPresentedChange nothing interactive opens or closes it; the fact still does", function()
		local open = Compose.cell(false)
		local w = mount(function(UI)
			return {
				isPresented = open,
				trigger = UI.Button("Open")({ label = "Open" }),
				content = function()
					return content(UI)
				end,
			}
		end)
		w.adapter.tap("/S/Open")
		w.settle(2)
		expect(w.adapter.node(PANEL)).toBeNil()
		open:set(true)
		w.settle(2)
		expect(w.adapter.node(PANEL) ~= nil).toBe(true)
		w.press("ButtonB")
		w.settle(2)
		expect(w.adapter.node(PANEL) ~= nil).toBe(true)
		open:set(false)
		w.settle(2)
		expect(w.adapter.node(PANEL)).toBeNil()
	end)
end)

describe("Popover: every input class opens and closes it through a real route", function()
	local function triggered(classes: any?): (any, any, Log)
		local open, log, change = caller()
		local w = mount(function(UI)
			return {
				isPresented = open,
				onPresentedChange = change,
				onDismiss = function(reason: string)
					table.insert(log.dismissed, reason)
				end,
				trigger = UI.Button("Open")({ label = "Open" }),
				content = function()
					return content(UI)
				end,
			}
		end, { classes = classes })
		return w, open, log
	end

	it("pointer: a click on the trigger opens it and a click outside closes it", function()
		local w, open, log = triggered(POINTER)
		w.adapter.tap("/S/Open", { source = "pointer", x = 20, y = 20 })
		w.settle(2)
		expect(w.adapter.node(PANEL) ~= nil).toBe(true)
		w.adapter.tap(w.pres.topScrimPath() :: string, { x = 790, y = 590 })
		w.settle(2)
		expect(open:peek()).toBe(false)
		expect(table.concat(log.dismissed, ",")).toBe("outside")
	end)

	it("keyboard: Return on the focused trigger opens it into the content, and closing returns focus", function()
		-- Escape belongs to the engine's own menu, so a keyboard close is the
		-- caller's content action or a click outside; the ring comes home either way
		local w, open, log = triggered()
		w.pres.focus.setFocusOrigin("navigation")
		expect(w.pres.focus.focusOn("/S/Open")).toBe(true)
		w.press("Return")
		w.settle(2)
		expect(open:peek()).toBe(true)
		expect(string.find(w.pres.focus.focused:peek() or "", BODY, 1, true) ~= nil).toBe(true)
		open:set(false)
		w.settle(2)
		expect(table.concat(log.dismissed, ",")).toBe("cancel")
		expect(w.pres.focus.focused:peek()).toBe("/S/Open")
	end)

	it("gamepad: ButtonA on the focused trigger opens it, and ButtonB proposes the close", function()
		local w, open, log = triggered({
			capabilities = { keyboard = false, mouse = false, touch = false, gamepad = true },
			preferredInput = "Gamepad",
		})
		expect(w.pres.focus.focusOn("/S/Open")).toBe(true)
		w.press("ButtonA")
		w.settle(2)
		expect(open:peek()).toBe(true)
		w.press("ButtonB")
		w.settle(2)
		expect(open:peek()).toBe(false)
		expect(table.concat(log.dismissed, ",")).toBe("cancel")
	end)
end)

describe("Popover: sources, anchor loss and bounds", function()
	it("a path source follows its node; removing it releases at once and reports anchorLost once", function()
		local open, log, change = caller()
		local present = Compose.cell(true)
		local w = mount(function(UI)
			return {
				isPresented = open,
				onPresentedChange = change,
				onDismiss = function(reason: string)
					table.insert(log.dismissed, reason)
				end,
				source = { path = "/S/Gate/then/Target" },
				content = function()
					return content(UI)
				end,
			}
		end, {
			extra = {
				function(UI)
					return UI.When("Gate")({
						condition = present,
						thenView = function()
							return UI.Button("Target")({ label = "Target" })
						end,
					})
				end,
			},
		})
		open:set(true)
		w.settle(2)
		expect(w.adapter.node(PANEL) ~= nil).toBe(true)
		present:set(false)
		w.settle(2)
		expect(w.adapter.node(PANEL)).toBeNil()
		expect(table.concat(log.dismissed, ",")).toBe("anchorLost")
		-- the source returns while the caller's fact is still false: nothing reopens
		present:set(true)
		w.settle(2)
		expect(w.adapter.node(PANEL)).toBeNil()
		-- a new false -> true request presents against the new node
		open:set(true)
		w.settle(2)
		expect(w.adapter.node(PANEL) ~= nil).toBe(true)
	end)

	it("a caller who refuses the anchorLost proposal keeps its fact, and nothing reopens", function()
		local open, log, change = caller(false)
		local present = Compose.cell(true)
		local w = mount(function(UI)
			return {
				isPresented = open,
				onPresentedChange = change,
				onDismiss = function(reason: string)
					table.insert(log.dismissed, reason)
				end,
				source = { path = "/S/Gate/then/Target" },
				content = function()
					return content(UI)
				end,
			}
		end, {
			extra = {
				function(UI)
					return UI.When("Gate")({
						condition = present,
						thenView = function()
							return UI.Button("Target")({ label = "Target" })
						end,
					})
				end,
			},
		})
		open:set(true)
		w.settle(2)
		present:set(false)
		w.settle(2)
		present:set(true)
		w.settle(3)
		expect(open:peek()).toBe(true)
		expect(w.adapter.node(PANEL)).toBeNil()
		expect(table.concat(log.dismissed, ",")).toBe("anchorLost")
		expect(w.record("Tip").dump().anchorLost).toBe(true)
	end)

	it("a source that has not mounted yet waits instead of being lost", function()
		local open = Compose.cell(true)
		local present = Compose.cell(false)
		local w = mount(function(UI)
			return {
				isPresented = open,
				source = { path = "/S/Gate/then/Target" },
				content = function()
					return content(UI)
				end,
			}
		end, {
			extra = {
				function(UI)
					return UI.When("Gate")({
						condition = present,
						thenView = function()
							return UI.Button("Target")({ label = "Target" })
						end,
					})
				end,
			},
		})
		expect(w.adapter.node(PANEL)).toBeNil()
		present:set(true)
		w.settle(2)
		expect(w.adapter.node(PANEL) ~= nil).toBe(true)
	end)

	it("a rect source never draws a tail; crossOffset and edge reach the placement", function()
		local open = Compose.cell(true)
		local w = mount(function(UI)
			return {
				isPresented = open,
				source = { rect = { x = 300, y = 200, w = 40, h = 40 } },
				edge = "trailing",
				align = "start",
				crossOffset = 10,
				tail = true,
				content = function()
					return content(UI)
				end,
			}
		end)
		local dump = w.pres.anchoredSurfaces().surfaces[1]
		expect(dump.tail).toBe(false)
		expect(dump.edge).toBe("right")
		expect(dump.y).toBe(210)
	end)

	it("maxWidth and maxHeight bound the whole panel inside the live safe box, and the body scrolls", function()
		local open = Compose.cell(false)
		local w = mount(function(UI)
			return {
				isPresented = open,
				source = { rect = { x = 100, y = 20, w = 40, h = 40 } },
				maxWidth = 220,
				maxHeight = 180,
				content = function()
					local rows = {}
					for i = 1, 30 do
						table.insert(rows, UI.Button(`Row{i}`)({ label = `Row {i}` }))
					end
					return UI.VStack("Rows")(rows)
				end,
			}
		end)
		-- the body's bar gutter is measured after a solve and paid a frame later
		open:set(true)
		w.settle(3)
		local r = w.adapter.node(SURFACE).rect
		expect(`w={r.w <= 220} h={r.h <= 180}`).toBe("w=true h=true")
		expect(w.adapter.node(BODY).class).toBe("ScrollView")
		w.env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 700 })
		w.settle(3)
		local after = w.adapter.node(SURFACE).rect
		expect(after.x + after.w <= 100 + 1).toBe(true)
	end)
end)

describe("Popover: the compact sheet and the live route switch", function()
	local TOUCH = {
		capabilities = { keyboard = false, mouse = false, touch = true, gamepad = false },
		preferredInput = "Touch",
	}
	local SHEET_CLOSE = "/Popover-Tip/Layer/Panel/Header/Close"

	it("a compact touch screen presents it as a sheet; compact = popover suppresses that", function()
		local open = Compose.cell(true)
		local w = mount(function(UI)
			return {
				isPresented = open,
				source = { rect = { x = 10, y = 10, w = 40, h = 40 } },
				content = function()
					return content(UI)
				end,
			}
		end, { w = 390, h = 700, classes = TOUCH })
		expect(w.record("Tip").dump().route).toBe("sheet")
		expect(w.adapter.node("/Popover-Tip/Layer/Panel/Body/Card/Line") ~= nil).toBe(true)
		local w2 = mount(function(UI)
			return {
				isPresented = Compose.cell(true),
				compact = "popover",
				source = { rect = { x = 10, y = 10, w = 40, h = 40 } },
				content = function()
					return content(UI)
				end,
			}
		end, { w = 390, h = 700, classes = TOUCH })
		expect(w2.record("Tip").dump().route).toBe("popover")
	end)

	it("the sheet's Close asks first: refused keeps it, accepted closes with cancel", function()
		for _, accept in { false, true } do
			local open, log, change = caller(accept)
			open:set(true)
			local w = mount(function(UI)
				return {
					isPresented = open,
					onPresentedChange = change,
					onDismiss = function(reason: string)
						table.insert(log.dismissed, reason)
					end,
					source = { rect = { x = 10, y = 10, w = 40, h = 40 } },
					content = function()
						return content(UI)
					end,
				}
			end, { w = 390, h = 700, classes = TOUCH })
			w.adapter.tap(SHEET_CLOSE)
			w.settle(3)
			expect(`accept={accept} open={w.adapter.node(SHEET_CLOSE) ~= nil}`).toBe(
				`accept={accept} open={not accept}`
			)
			expect(table.concat(log.dismissed, ",")).toBe(if accept then "cancel" else "")
		end
	end)

	it("a live class change switches the route silently, with one content owner", function()
		local open, log, change = caller()
		open:set(true)
		local w = mount(function(UI)
			return {
				isPresented = open,
				onPresentedChange = change,
				onDismiss = function(reason: string)
					table.insert(log.dismissed, reason)
				end,
				source = { rect = { x = 10, y = 10, w = 40, h = 40 } },
				content = function()
					return content(UI)
				end,
			}
		end, { w = 390, h = 700, classes = POINTER })
		expect(w.record("Tip").dump().route).toBe("popover")
		w.pres.focus.focusOn(`{BODY}/Card/Inner`)
		w.env:set("capabilities", TOUCH.capabilities)
		w.env:set("preferredInput", TOUCH.preferredInput)
		w.settle(3)
		expect(w.record("Tip").dump().route).toBe("sheet")
		expect(w.adapter.node(PANEL)).toBeNil()
		local lines = 0
		for _, path in w.adapter.paths() do
			if string.match(path, "/Card/Line$") then
				lines += 1
			end
		end
		expect(lines).toBe(1)
		expect(#log.changes).toBe(0)
		expect(#log.dismissed).toBe(0)
		expect(w.pres.focus.focused:peek()).toBe("/Popover-Tip/Layer/Panel/Body/Card/Inner")
	end)
end)

describe("Popover: callbacks that throw or re-enter, and branch cycles", function()
	it("a throwing onPresentedChange changes nothing, and a throwing onDismiss still closes once", function()
		local open = Compose.cell(true)
		local closes = 0
		local w = mount(function(UI)
			return {
				isPresented = open,
				onPresentedChange = function()
					error("caller bug")
				end,
				onDismiss = function()
					closes += 1
					error("caller bug in onDismiss")
				end,
				source = { rect = { x = 10, y = 10, w = 40, h = 40 } },
				content = function()
					return content(UI)
				end,
			}
		end)
		local node = w.adapter.node(PANEL)
		-- raised to the caller, never swallowed (Alert's contract)
		local ok, err = pcall(w.press, "ButtonB")
		expect(`{ok} {string.find(tostring(err), "caller bug", 1, true) ~= nil}`).toBe("false true")
		w.settle(2)
		expect(w.adapter.node(PANEL) == node).toBe(true)
		pcall(open.set, open, false)
		w.settle(2)
		expect(w.adapter.node(PANEL)).toBeNil()
		expect(closes).toBe(1)
	end)

	it("a caller that re-opens inside its own close callback keeps one live surface", function()
		local open = Compose.cell(true)
		local w = mount(function(UI)
			return {
				isPresented = open,
				onPresentedChange = function(next: boolean)
					open:set(next)
					if not next then
						open:set(true)
					end
				end,
				source = { rect = { x = 10, y = 10, w = 40, h = 40 } },
				content = function()
					return content(UI)
				end,
			}
		end)
		w.press("ButtonB")
		w.settle(3)
		local surfaces = 0
		for _, path in w.adapter.paths() do
			if path == SURFACE then
				surfaces += 1
			end
		end
		expect(surfaces).toBe(1)
		expect(w.pres.anchoredSurfaces().count).toBe(1)
	end)

	it("open/close/branch cycles return the presenter to its baseline", function()
		local open = Compose.cell(false)
		local shown = Compose.cell(true)
		local w = mount(function(UI)
			return {
				isPresented = open,
				source = { rect = { x = 10, y = 10, w = 40, h = 40 } },
				content = function()
					return content(UI)
				end,
			}
		end)
		local depth = w.pres.depth()
		for _ = 1, 3 do
			open:set(true)
			w.settle(2)
			expect(w.pres.depth()).toBe(depth + 1)
			open:set(false)
			w.settle(2)
			expect(w.pres.depth()).toBe(depth)
		end
		expect(w.pres.anchoredSurfaces().count).toBe(0)
		local _ = shown
	end)

	it("a refused drag on the compact sheet goes back to the accepted detent", function()
		local open, log, change = caller(false)
		open:set(true)
		local w = mount(function(UI)
			return {
				isPresented = open,
				onPresentedChange = change,
				source = { rect = { x = 10, y = 10, w = 40, h = 40 } },
				content = function()
					return content(UI)
				end,
			}
		end, {
			w = 390,
			h = 700,
			classes = {
				capabilities = { keyboard = false, mouse = false, touch = true, gamepad = false },
				preferredInput = "Touch",
			},
		})
		local handle = "/Popover-Tip/Layer/Panel/Drag/Handle"
		local before = w.adapter.node("/Popover-Tip/Layer/Panel").rect.h
		local r = w.adapter.node(handle).rect
		w.adapter.pointerDown(handle, r.x + r.w / 2, r.y + r.h / 2, "touch")
		w.adapter.pointerMove(r.x + r.w / 2, r.y + r.h / 2 + 600)
		w.adapter.pointerUp(r.x + r.w / 2, r.y + r.h / 2 + 600)
		w.settle(6)
		expect(log.changes[#log.changes]).toBe(false)
		expect(w.adapter.node("/Popover-Tip/Layer/Panel").rect.h).toBe(before)
	end)
end)

describe("Popover: lifetime", function()
	it("owner disposal releases physically and reports cancel once; two apps stay apart", function()
		local a, logA, changeA = caller()
		local b, _, changeB = caller()
		local present = Compose.cell(true)
		local w1 = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, reducedMotion = true })
		local w2 = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, reducedMotion = true })
		local function screen(w: any, open: any, change: any, gated: boolean): any
			local UI = w.UI
			return function()
				local pop = function()
					return UI.Popover("Tip")({
						isPresented = open,
						onPresentedChange = change,
						onDismiss = function(reason: string)
							table.insert(logA.dismissed, reason)
						end,
						source = { rect = { x = 10, y = 10, w = 40, h = 40 } },
						content = function()
							return content(UI)
						end,
					})
				end
				return UI.Screen("S")({
					if gated then UI.When("Gate")({ condition = present, thenView = pop }) else pop(),
				})
			end
		end
		w1.present(screen(w1, a, changeA, true))
		w2.present(screen(w2, b, changeB, false))
		a:set(true)
		b:set(true)
		w1.settle(2)
		w2.settle(2)
		expect(w1.adapter.node(PANEL) ~= nil and w2.adapter.node(PANEL) ~= nil).toBe(true)
		present:set(false)
		w1.settle(2)
		w2.settle(2)
		expect(w1.adapter.node(PANEL)).toBeNil()
		expect(table.concat(logA.dismissed, ",")).toBe("cancel")
		expect(w2.adapter.node(PANEL) ~= nil).toBe(true)
	end)

	it("the spec is closed and the contract is refused by name", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local UI = w.UI
		local open = Compose.cell(false)
		local good = function()
			return UI.Text("C")({ text = "c" })
		end
		local cases: { () -> any } = {
			function()
				return { content = good }
			end,
			function()
				return { isPresented = open, content = good }
			end,
			function()
				return {
					isPresented = open,
					content = good,
					source = { path = "/S/A" },
					trigger = UI.Text("T")({ text = "T" }),
				}
			end,
			function()
				return { isPresented = open, content = UI.Text("C")({ text = "c" }), source = { path = "/S/A" } }
			end,
			function()
				return {
					isPresented = open,
					content = good,
					source = { path = "/S/A", rect = { x = 0, y = 0, w = 1, h = 1 } },
				}
			end,
			function()
				return { isPresented = open, content = good, source = { path = "/S/A" }, maxWidth = 0 }
			end,
			function()
				return { isPresented = open, content = good, source = { path = "/S/A" }, compact = "drawer" }
			end,
			function()
				return { isPresented = open, content = good, source = { path = "/S/A" }, anchor = {} }
			end,
		}
		for index, make in cases do
			local ok = pcall(function()
				w.scoped(function()
					return UI.Popover(make())
				end)
			end)
			expect(`case {index} refused: {not ok}`).toBe(`case {index} refused: true`)
		end
		-- ...and a well-formed one builds
		w.scoped(function()
			return UI.Popover({ isPresented = open, content = good, source = { path = "/S/A" } })
		end)
	end)
end)

describe("Popover: the Overlays showcase drives its own steps", function()
	it("opens the about and source popovers from its steps, shows the rich tour, and resets", function()
		local scenario = require("../examples/gallery/scenarios/overlays") :: any
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 900 }, reducedMotion = true })
		local built = scenario.build({
			Facet = Facet,
			UI = w.UI,
			Compose = Compose,
			core = w.core,
			env = w.env,
			adapter = w.adapter,
			presenter = w.pres,
		})
		w.present(function()
			return built.screen()
		end)
		w.settle(2)
		built.steps.openAbout()
		w.settle(2)
		expect(w.adapter.node("/Popover-About/Layer/Surface/Popup/Panel/Body/Body").props.text).toBe(
			scenario.copy.aboutBody
		)
		built.steps.reset()
		w.settle(2)
		built.steps.openSource()
		w.settle(2)
		local row = w.adapter.node("/Overlays/Content/Sections/SourceRow").rect
		local panel = w.adapter.node("/Popover-Source/Layer/Surface").rect
		expect(panel.y >= row.y + row.h).toBe(true)
		built.steps.reset()
		w.settle(2)
		expect(w.adapter.node("/Popover-Source/Layer/Surface")).toBeNil()
		w.adapter.tap("/Overlays/Content/Sections/TourButton")
		w.settle(3)
		expect(w.adapter.node("/Tour/Layer/Surface/Plate/Header/Title").props.text).toBe(scenario.copy.coachTitle)
	end)
end)
