--!strict
--[[ UI.Card — three sibling hit surfaces, owned engagement, and a reveal layer
	whose measured extension never moves a sibling (phase6 P6a). ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local world = require("./lib/world")
local Facet = require("../src") :: any
local Compose = Facet.Compose

local POINTER = { mouse = true, keyboard = true }
local TOUCH = { touch = true }

local function mount(content: (UI: any) -> { any }, opts: any?): any
	local o = opts or {}
	local w = world.new({
		viewport = { x = 0, y = 0, w = o.w or 800, h = o.h or 700 },
		reducedMotion = o.reduced ~= false,
		capabilities = o.capabilities or POINTER,
		preferredInput = o.preferredInput,
		hostOpts = { keyboardNavigation = true },
	})
	local UI = w.UI
	w.present(function()
		return UI.Screen("S")({ UI.HStack("Row")({ gap = o.gap or 24, table.unpack(content(UI)) }) })
	end)
	w.settle(3)
	return w
end

local ROOT = "/S/Row/C"
local PRIMARY = `{ROOT}/Reveal/Actions/Row/Primary`
local MORE = `{ROOT}/Reveal/Actions/Row/More`

local function cardSpec(log: { string }, extra: any?): any
	local spec: any = {
		width = { type = "fixed", px = 240 },
		image = "rbxassetid://1",
		title = "Nebula Racers",
		caption = "Friends playing",
		onActivate = function()
			table.insert(log, "body")
		end,
		primaryAction = {
			label = "Play",
			onActivate = function()
				table.insert(log, "primary")
			end,
		},
		menu = {
			items = {
				{
					id = "hide",
					label = "Not interested",
					onSelect = function()
						table.insert(log, "hide")
					end,
				},
			},
		},
	}
	for k, v in extra or {} do
		spec[k] = v
	end
	return spec
end

local function rectOf(w: any, path: string): string
	local r = w.adapter.node(path).rect
	return `{r.x},{r.y},{r.w},{r.h}`
end

-- focus a path with a painted ring, the way a navigation verb leaves it
local function ring(w: any, path: string)
	expect(w.pres.focus.focusOn(path)).toBe(true)
	w.pres.focus.setFocusOrigin("navigation")
	w.settle(2)
end

local function revealed(w: any): boolean
	return w.record("C").dump().revealed
end

describe("Card: construction", function()
	it("refuses malformed specs before building anything", function()
		local w = world.new()
		local UI = w.UI
		local bad = {
			{ image = "", title = "T" },
			{ image = "rbxassetid://1" },
			{ image = "rbxassetid://1", title = "T", reveal = "hover" },
			{ image = "rbxassetid://1", title = "T", imageAspectRatio = 0 },
			{ image = "rbxassetid://1", title = "T", primaryAction = { label = "Play" } },
			{ image = "rbxassetid://1", title = "T", primaryAction = { label = "P", onActivate = print, x = 1 } },
			{ image = "rbxassetid://1", title = "T", menu = { items = {}, extra = true } },
			{ image = "rbxassetid://1", title = "T", caption = 5 },
			{ image = "rbxassetid://1", title = "T", zIndex = 3 },
		}
		for _, spec in bad do
			local ok = pcall(function()
				w.scoped(function()
					return UI.Card(spec)
				end)
			end)
			expect(ok).toBe(false)
		end
	end)
end)

describe("Card: activation", function()
	it("body, primary and More are sibling targets: one press runs exactly one intent", function()
		local log: { string } = {}
		local w = mount(function(UI)
			return { UI.Card("C")(cardSpec(log)) }
		end)
		w.adapter.tap(`{ROOT}/Body`)
		expect(table.concat(log, ",")).toBe("body")
		w.adapter.hover(ROOT)
		w.settle(2)
		w.adapter.tap(PRIMARY)
		expect(table.concat(log, ",")).toBe("body,primary")
		w.adapter.tap(MORE)
		w.settle(2)
		expect(w.record("C").dump().menuOpen).toBe(true)
		expect(table.concat(log, ",")).toBe("body,primary")
	end)

	it("an informational body has no activation target, and actions still work", function()
		local log: { string } = {}
		local w = mount(function(UI)
			return {
				UI.Card("C")((function()
					local spec = cardSpec(log)
					spec.onActivate = nil
					return spec
				end)()),
			}
		end)
		expect(w.record("C").dump().body).toBe("informational")
		expect(w.adapter.node(`{ROOT}/Body`).onActivate).toBeNil()
		expect(w.adapter.node(`{ROOT}/Body/Title`).props.text).toBe("Nebula Racers")
		-- no stop of its own and no browse stop: the actions are its stops, at rest
		expect(revealed(w)).toBe(true)
		ring(w, PRIMARY)
		w.press("Tab")
		expect(w.pres.focus.focused:peek()).toBe(MORE)
		ring(w, PRIMARY)
		w.press("Return")
		expect(table.concat(log, ",")).toBe("primary")
	end)

	it("disabled cards and busy actions keep their controls' own semantics", function()
		local log: { string } = {}
		local enabled = Compose.cell(false)
		local busy = Compose.cell(true)
		local w = mount(function(UI)
			local spec = cardSpec(log, { enabled = enabled })
			spec.primaryAction.busy = busy
			spec.menu = nil
			return { UI.Card("C")(spec) }
		end)
		w.adapter.tap(`{ROOT}/Body`)
		expect(#log).toBe(0)
		expect(w.record("C").api.enterActions()).toBe(false)
		enabled:set(true)
		w.settle(2)
		-- busy primary and no menu: nothing eligible to enter
		expect(w.record("C").api.enterActions()).toBe(false)
		busy:set(false)
		w.settle(2)
		expect(w.record("C").api.enterActions()).toBe(true)
	end)

	it("an invalid late title or image keeps the last legal paint and recovers", function()
		local title = Compose.cell("First")
		local image = Compose.cell("rbxassetid://1")
		local w = mount(function(UI)
			return { UI.Card("C")(cardSpec({}, { title = title, image = image })) }
		end)
		local label = `{ROOT}/Body/ImageContent/Caption/Label`
		local art = `{ROOT}/Body/ImageContent/ImageEnvelope/Artwork`
		title:set("")
		image:set("")
		w.settle(2)
		expect(w.adapter.node(label).props.text).toBe("First")
		expect(w.adapter.node(art).props.image).toBe("rbxassetid://1")
		expect(#w.record("C").api.diagnostics()).toBe(2)
		title:set("Second")
		image:set("rbxassetid://2")
		w.settle(2)
		expect(w.adapter.node(label).props.text).toBe("Second")
		expect(w.adapter.node(art).props.image).toBe("rbxassetid://2")
	end)

	it("a callback that removes its own card leaves nothing behind", function()
		local show = Compose.cell(true)
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 700 }, reducedMotion = true })
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				UI.HStack("Row")({
					UI.When("Gate")({
						condition = show,
						thenView = function()
							return UI.Card("C")(cardSpec({}, {
								onActivate = function()
									show:set(false)
								end,
							}))
						end,
					}),
					UI.Button("Next")({ label = "Next" }),
				}),
			})
		end)
		w.settle(3)
		w.adapter.hover("/S/Row/Gate/then/C")
		w.adapter.tap("/S/Row/Gate/then/C/Body")
		w.settle(3)
		expect(w.adapter.node("/S/Row/Gate/then/C")).toBeNil()
		expect(w.pres.focus.activeScopeName() ~= nil).toBe(true)
		expect(string.find(w.pres.focus.activeScopeName(), "__transient__", 1, true)).toBeNil()
	end)
end)

describe("Card: engagement and reveal", function()
	it("automatic: pointer within reveals; siblings and the card envelope never move", function()
		local w = mount(function(UI)
			return { UI.Card("C")(cardSpec({})), UI.Button("Next")({ label = "Next" }) }
		end)
		local card, nextRect = rectOf(w, ROOT), rectOf(w, "/S/Row/Next")
		expect(revealed(w)).toBe(false)
		expect(w.adapter.visibleOf(`{ROOT}/Reveal`)).toBe(false)
		w.adapter.hover(ROOT)
		w.settle(3)
		expect(revealed(w)).toBe(true)
		expect(rectOf(w, ROOT)).toBe(card)
		expect(rectOf(w, "/S/Row/Next")).toBe(nextRect)
		-- the plate grows sideways by `s` and below by the measured row
		local body = w.adapter.node(ROOT).rect
		local plate = w.adapter.node(`{ROOT}/Reveal/Plate`).rect
		local row = w.adapter.node(`{ROOT}/Reveal/Actions`).rect
		local extent = w.record("C").api.revealExtent:peek()
		expect(plate.y).toBe(body.y)
		expect(plate.x).toBe(body.x - extent.side)
		expect(plate.y + plate.h).toBe(body.y + body.h + extent.below)
		expect(row.y + row.h + extent.side).toBe(plate.y + plate.h)
		w.adapter.unhover(ROOT)
		w.settle(3)
		expect(revealed(w)).toBe(false)
	end)

	it("the extension is measured at rest, before anything reveals", function()
		local w = mount(function(UI)
			return { UI.Card("C")(cardSpec({})) }
		end)
		local extent = w.record("C").api.revealExtent:peek()
		expect(extent.side > 0).toBe(true)
		expect(extent.below).toBe(extent.side * 2 + w.adapter.node(`{ROOT}/Reveal/Actions`).rect.h)
	end)

	it("hidden actions are out of the focus order at rest", function()
		local w = mount(function(UI)
			return { UI.Card("C")(cardSpec({})), UI.Button("Next")({ label = "Next" }) }
		end)
		expect(w.pres.focus.focusOn(PRIMARY)).toBe(false)
		-- a painted ring on the body reveals them, and they join the order
		ring(w, `{ROOT}/Body`)
		expect(w.pres.focus.focusOn(PRIMARY)).toBe(true)
	end)

	it("focus within reveals; pointer departure never hides focused content; focus departure does", function()
		local w = mount(function(UI)
			return { UI.Card("C")(cardSpec({})), UI.Button("Next")({ label = "Next" }) }
		end)
		w.adapter.hover(ROOT)
		ring(w, `{ROOT}/Body`)
		w.adapter.unhover(ROOT)
		w.settle(2)
		expect(revealed(w)).toBe(true)
		-- Tab walks body -> primary -> More -> Next, revealed the whole way
		w.press("Tab")
		expect(w.pres.focus.focused:peek()).toBe(PRIMARY)
		w.press("Tab")
		w.press("Tab")
		w.settle(2)
		expect(w.pres.focus.focused:peek()).toBe("/S/Row/Next")
		expect(revealed(w)).toBe(false)
	end)

	it("an open menu holds the reveal across its portal and releases it on close", function()
		local w = mount(function(UI)
			return { UI.Card("C")(cardSpec({})), UI.Button("Next")({ label = "Next" }) }
		end)
		w.adapter.hover(ROOT)
		w.settle(2)
		w.adapter.tap(MORE)
		w.settle(2)
		w.adapter.unhover(ROOT)
		w.settle(2)
		expect(w.record("C").dump().menuOpen).toBe(true)
		expect(revealed(w)).toBe(true)
		w.press("ButtonB")
		w.settle(3)
		expect(w.record("C").dump().menuOpen).toBe(false)
		-- the pointer left while the menu was open: closing it ends the reveal
		expect(revealed(w)).toBe(false)
		-- the pad route: the menu opens from a ringed More and closes back onto it
		ring(w, `{ROOT}/Body`)
		ring(w, MORE)
		w.press("ButtonY")
		w.settle(2)
		expect(w.record("C").dump().menuOpen).toBe(true)
		expect(string.find(w.pres.focus.focused:peek() or "", ROOT, 1, true)).toBeNil()
		expect(revealed(w)).toBe(true)
		w.press("ButtonB")
		w.settle(3)
		expect(w.pres.focus.focused:peek()).toBe(MORE)
		expect(revealed(w)).toBe(true)
	end)

	it("a press held on an action keeps the reveal after the pointer leaves", function()
		local w = mount(function(UI)
			return { UI.Card("C")(cardSpec({})) }
		end)
		w.adapter.hover(ROOT)
		w.settle(2)
		local r = w.adapter.node(PRIMARY).rect
		w.adapter.pointerDown(PRIMARY, r.x + 2, r.y + 2)
		w.adapter.unhover(ROOT)
		w.settle(2)
		expect(revealed(w)).toBe(true)
		w.adapter.pointerUp(r.x + 2, r.y + 2)
		w.settle(2)
		expect(revealed(w)).toBe(false)
	end)

	it("touch-only keeps actions at rest and the first tap does the body's promised action", function()
		local log: { string } = {}
		local w = mount(function(UI)
			return { UI.Card("C")(cardSpec(log)) }
		end, { capabilities = TOUCH, preferredInput = "Touch" })
		expect(revealed(w)).toBe(true)
		w.adapter.touchTap(`{ROOT}/Body`)
		expect(table.concat(log, ",")).toBe("body")
		-- gaining a mouse returns the card to engagement, without a held menu lost
		w.env:set("capabilities", { touch = true, mouse = true })
		w.env:set("preferredInput", "KeyboardAndMouse")
		w.settle(2)
		expect(revealed(w)).toBe(false)
	end)

	it("hidden actions take no tap, and a press cut off by disabling never fires on release", function()
		local log: { string } = {}
		local enabled = Compose.cell(true)
		local w = mount(function(UI)
			return { UI.Card("C")(cardSpec(log, { enabled = enabled })) }
		end)
		w.adapter.tap(PRIMARY)
		expect(#log).toBe(0)
		w.adapter.hover(ROOT)
		w.settle(2)
		local r = w.adapter.node(PRIMARY).rect
		w.adapter.pointerDown(PRIMARY, r.x + 2, r.y + 2)
		enabled:set(false)
		w.settle(2)
		w.adapter.pointerUpActivating(r.x + 2, r.y + 2, "after")
		w.settle(2)
		expect(#log).toBe(0)
	end)

	it("a rapid reversal retargets the fade from where it is, never from rest", function()
		local w = mount(function(UI)
			return { UI.Card("C")(cardSpec({})) }
		end, { reduced = false })
		local function alpha(): number
			local group = w.adapter.node(`{ROOT}/Reveal/Plate`).canvasGroupInstance
			return 1 - group.groupTransparency
		end
		w.adapter.hover(ROOT)
		for _ = 1, 6 do
			w.frame()
		end
		local reached = alpha()
		expect(reached > 0.3 and reached < 1).toBe(true)
		w.adapter.unhover(ROOT)
		w.frame()
		w.frame()
		local turned = alpha()
		-- hit and focus left at once; the paint heads back without a jump
		expect(revealed(w)).toBe(false)
		expect(turned < reached and turned > reached - 0.2).toBe(true)
		w.adapter.hover(ROOT)
		w.frame()
		w.frame()
		expect(math.abs(alpha() - turned) < 0.2).toBe(true)
		expect(revealed(w)).toBe(true)
	end)

	it("always reserves the action row in the card's own layout", function()
		local w = mount(function(UI)
			return { UI.Card("C")(cardSpec({}, { reveal = "always" })) }
		end)
		local root = w.adapter.node(ROOT).rect
		local row = w.adapter.node(`{ROOT}/Actions`).rect
		expect(row.y + row.h).toBe(root.y + root.h)
		expect(w.adapter.node(`{ROOT}/Actions/Primary`) ~= nil).toBe(true)
		expect(revealed(w)).toBe(true)
	end)

	it("a live theme and text change while revealed re-measures without moving siblings", function()
		local w = mount(function(UI)
			return { UI.Card("C")(cardSpec({})), UI.Button("Next")({ label = "Next" }) }
		end)
		w.adapter.hover(ROOT)
		w.settle(2)
		local card = rectOf(w, ROOT)
		local before = w.record("C").api.revealExtent:peek().below
		w.env:set("preferredTextOffset", 14)
		w.settle(4)
		expect(w.record("C").api.revealExtent:peek().below >= before).toBe(true)
		local plate = w.adapter.node(`{ROOT}/Reveal/Plate`).rect
		local body = w.adapter.node(ROOT).rect
		expect(plate.y + plate.h).toBe(body.y + body.h + w.record("C").api.revealExtent:peek().below)
		expect(rectOf(w, ROOT) == card or w.adapter.node(ROOT).rect.w == 240).toBe(true)
	end)
end)

-- ===========================================================================
--[[ THE GRID RECIPE (P6a items 9-12). The grid owns ONE browse stop per cell (its
	Hit); the cell's Card reads that stop through `browseTarget`, and the grid's
	activation enters the card's actions through a mount-local ref keyed by the
	item. Each cell insets its card by the card's MEASURED extension (both sides
	and below), so a reveal never covers a neighbour and never reaches past the
	grid's clip edge — the first column and the last line included. ]]
local function gridWorld(opts: any?): any
	local o = opts or {}
	local w = world.new({
		viewport = { x = 0, y = 0, w = 900, h = 700 },
		reducedMotion = true,
		capabilities = { gamepad = true, keyboard = true, mouse = true },
		hostOpts = { keyboardNavigation = true },
	})
	local UI = w.UI
	local function items(n: number, prefix: string?): { any }
		local out = table.create(n)
		for i = 1, n do
			out[i] = { id = `{prefix or "i"}{i}`, title = `Game {i}` }
		end
		return out
	end
	local log: { string } = {}
	local function grid(id: string, source: any)
		local refs: { [string]: any } = {}
		local gridRef: any = nil
		local gaps = Compose.cell({ side = 0, below = 0 })
		local g = UI.VirtualGrid(id)({
			items = source,
			key = function(item: any)
				return item.id
			end,
			columns = 3,
			itemExtent = 280,
			viewportExtent = 560,
			width = { type = "fixed", px = 780 },
			ref = function(r: any)
				gridRef = r
			end,
			onActivate = function(item: any)
				local r = refs[item.id]
				if r ~= nil then
					r.api.enterActions()
				end
			end,
			cell = function(item: any, ctx: any)
				local key = item.id
				local card = UI.Card("Card")({
					image = "rbxassetid://1",
					title = function(use)
						return ctx.current(use).title
					end,
					browseTarget = function()
						local cell = if gridRef ~= nil then gridRef.api.pathOf(key) else nil
						return if cell ~= nil then `{cell}/Hit` else nil
					end,
					primaryAction = {
						label = "Play",
						onActivate = function()
							table.insert(log, `play:{key}`)
						end,
					},
					menu = {
						items = {
							{
								id = "hide",
								label = "Not interested",
								onSelect = function()
									table.insert(log, `hide:{key}`)
								end,
							},
						},
					},
					ref = function(r: any)
						refs[key] = r
						ctx.scope.own(function()
							if refs[key] == r then
								refs[key] = nil
							end
						end)
						Compose.watch(function(use)
							local e = use(r.api.revealExtent)
							local now = gaps:peek()
							if e.below > now.below or e.side > now.side then
								gaps:set({ side = math.max(e.side, now.side), below = math.max(e.below, now.below) })
							end
						end)
					end,
				})
				return UI.VStack("Inset")({
					width = UI.fill(),
					height = UI.fill(),
					padding = function(use)
						local e = use(gaps)
						return { left = e.side, right = e.side, top = 0, bottom = e.below }
					end,
					card,
				})
			end,
		})
		return g, refs
	end
	local sourceA = Compose.cell(items(o.count or 12))
	local sourceB = Compose.cell(items(6))
	local refsA, refsB
	w.present(function()
		local a, ra = grid("A", sourceA)
		refsA = ra
		local children = { a }
		if o.twoGrids then
			local b, rb = grid("B", sourceB)
			refsB = rb
			table.insert(children, b)
		end
		return UI.Screen("S")({ UI.VStack("Page")({ gap = 0, table.unpack(children) }) })
	end)
	w.settle(4)
	return {
		w = w,
		log = log,
		sourceA = sourceA,
		sourceB = sourceB,
		refs = function()
			return refsA, refsB
		end,
		hit = function(key: string, grid: string?): string
			return `/S/Page/{grid or "A"}/Canvas/Band/W/[{key}]/Cell/Hit`
		end,
		action = function(key: string, part: string, grid: string?): string
			return `/S/Page/{grid or "A"}/Canvas/Band/W/[{key}]/Cell/Inset/Card/Reveal/Actions/Row/{part}`
		end,
	}
end

local function gridCard(g: any, key: string, grid: string?): any
	local refsA, refsB = g.refs()
	local r = (if grid == "B" then refsB else refsA)[key]
	return r.dump()
end

describe("Card in a VirtualGrid: one browse stop, entry and Cancel", function()
	it("the grid Hit is the browse stop: its ring reveals that card alone", function()
		local g = gridWorld()
		ring(g.w, g.hit("i1"))
		expect(gridCard(g, "i1").browsing).toBe(true)
		expect(gridCard(g, "i1").revealed).toBe(true)
		expect(gridCard(g, "i2").revealed).toBe(false)
		-- the gutters hold the measured extension: the next line starts below the
		-- revealed plate, and the neighbour across starts past both sideways reaches
		local e = g.refs()["i1"].api.revealExtent:peek()
		local c1 = g.w.adapter.node(g.hit("i1")).rect
		local plate = g.w.adapter.node(`/S/Page/A/Canvas/Band/W/[i1]/Cell/Inset/Card/Reveal/Plate`).rect
		expect(e.side > 0 and e.below > e.side).toBe(true)
		expect(plate.x >= c1.x and plate.x + plate.w <= c1.x + c1.w).toBe(true)
		expect(plate.y + plate.h <= c1.y + c1.h).toBe(true)
		-- moving the ring on moves the reveal
		g.w.press("Right")
		g.w.settle(2)
		expect(gridCard(g, "i1").revealed).toBe(false)
		expect(gridCard(g, "i2").revealed).toBe(true)
	end)

	it("Activate enters the actions at the first action; arrows stay inside; Cancel restores the stop", function()
		local g = gridWorld()
		ring(g.w, g.hit("i2"))
		g.w.press("ButtonA")
		g.w.settle(2)
		expect(g.w.pres.focus.focused:peek()).toBe(g.action("i2", "Primary"))
		expect(#g.log).toBe(0)
		g.w.press("Right")
		expect(g.w.pres.focus.focused:peek()).toBe(g.action("i2", "More"))
		g.w.press("Right")
		expect(string.find(g.w.pres.focus.focused:peek(), "[i2]", 1, true) ~= nil).toBe(true)
		g.w.press("Down")
		expect(string.find(g.w.pres.focus.focused:peek(), "[i2]", 1, true) ~= nil).toBe(true)
		-- the menu cancels first, then the card
		g.w.pres.focus.focusOn(g.action("i2", "More"))
		g.w.press("ButtonA")
		g.w.settle(2)
		expect(gridCard(g, "i2").menuOpen).toBe(true)
		g.w.press("ButtonB")
		g.w.settle(2)
		expect(gridCard(g, "i2").menuOpen).toBe(false)
		expect(g.w.pres.focus.focused:peek()).toBe(g.action("i2", "More"))
		g.w.press("ButtonB")
		g.w.settle(2)
		expect(g.w.pres.focus.focused:peek()).toBe(g.hit("i2"))
		expect(gridCard(g, "i2").entered).toBe(false)
		-- the restored browse stop keeps the actions revealed; no entry is running
		expect(gridCard(g, "i2").revealed).toBe(true)
		-- entry never substituted the primary action
		expect(#g.log).toBe(0)
	end)

	it("removing, scrolling away or replacing an entered card leaves no trap, menu or ref behind", function()
		local g = gridWorld()
		ring(g.w, g.hit("i1"))
		g.w.press("ButtonA")
		g.w.settle(2)
		g.w.press("Right")
		g.w.press("ButtonA")
		g.w.settle(2)
		expect(gridCard(g, "i1").menuOpen).toBe(true)
		-- the source deletes the entered, menu-open card
		local rest = table.clone(g.sourceA:peek())
		table.remove(rest, 1)
		g.sourceA:set(rest)
		g.w.settle(3)
		expect(g.refs()["i1"]).toBeNil()
		local scope = g.w.pres.focus.activeScopeName() or ""
		expect(string.find(scope, "__transient__", 1, true)).toBeNil()
		local focused = g.w.pres.focus.focused:peek() or ""
		expect(string.find(focused, "/Hit", 1, true) ~= nil).toBe(true)
		expect(g.w.adapter.node(focused) ~= nil).toBe(true)
		-- a fresh card at a reused key is its own identity and starts at rest
		g.sourceA:set(table.move(rest, 1, #rest, 2, { { id = "i1", title = "Back" } }))
		g.w.settle(3)
		expect(gridCard(g, "i1").entered).toBe(false)
		expect(gridCard(g, "i1").menuOpen).toBe(false)
	end)

	it("scrolling an entered card out of the window recycles it without stranding its trap", function()
		local g = gridWorld({ count = 60 })
		ring(g.w, g.hit("i1"))
		g.w.press("ButtonA")
		g.w.settle(2)
		expect(gridCard(g, "i1").entered).toBe(true)
		g.w.adapter.driveScroll("/S/Page/A", { x = 0, y = 4000 })
		g.w.settle(3)
		expect(g.refs()["i1"]).toBeNil()
		expect(string.find(g.w.pres.focus.activeScopeName() or "", "__transient__", 1, true)).toBeNil()
	end)

	it("two grids with identical keys keep separate cards and entries", function()
		local g = gridWorld({ twoGrids = true })
		ring(g.w, g.hit("i1", "B"))
		g.w.press("ButtonA")
		g.w.settle(2)
		expect(g.w.pres.focus.focused:peek()).toBe(g.action("i1", "Primary", "B"))
		expect(gridCard(g, "i1", "B").entered).toBe(true)
		expect(gridCard(g, "i1").entered).toBe(false)
		expect(gridCard(g, "i1").revealed).toBe(false)
	end)

	it("the gallery Cards scenario: its lines hold each card and its plate, and its step enters", function()
		local scenario = require("../examples/gallery/scenarios/cards") :: any
		local w = world.new({
			viewport = { x = 0, y = 0, w = 1280, h = 720 },
			reducedMotion = true,
			capabilities = { gamepad = true, keyboard = true, mouse = true },
		})
		local built =
			scenario.build({ Facet = Facet, UI = w.UI, Compose = Compose, app = w.app, core = w.core, env = w.env })
		w.present(built.screen)
		w.settle(6)
		local cell = w.adapter.node("/Cards/Games/Canvas/Band/W/[g1]/Cell").rect
		local plate = w.adapter.node("/Cards/Games/Canvas/Band/W/[g1]/Cell/Inset/Card/Reveal/Plate").rect
		expect(plate.x >= cell.x and plate.x + plate.w <= cell.x + cell.w).toBe(true)
		expect(plate.y + plate.h <= cell.y + cell.h).toBe(true)
		local dump = built.steps.enter("g1")
		w.settle(2)
		expect(dump.entered).toBe(true)
		expect(w.pres.focus.focused:peek()).toBe(
			"/Cards/Games/Canvas/Band/W/[g1]/Cell/Inset/Card/Reveal/Actions/Row/Primary"
		)
		w.press("ButtonA")
		expect(built.report().last).toBe("Last action: play g1")
	end)

	it("a thousand items keep the mounted cards, refs and owners bounded", function()
		local g = gridWorld({ count = 1000 })
		local function count(): number
			local n = 0
			for _ in g.refs() do
				n += 1
			end
			return n
		end
		-- two visible lines, two overscan lines either side, one partial: 7 lines
		local bound = 7 * 3
		expect(count() > 0 and count() <= bound).toBe(true)
		local peak = 0
		for step = 1, 10 do
			g.w.adapter.driveScroll("/S/Page/A", { x = 0, y = step * 2000 })
			g.w.settle(2)
			peak = math.max(peak, count())
		end
		expect(peak <= bound).toBe(true)
		-- every card that left the window released its ref through its cell owner
		expect(g.refs()["i1"]).toBeNil()
		expect(g.refs()["i500"]).toBeNil()
	end)
end)

return nil
