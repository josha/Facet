--!strict
-- TAB TRAVERSES IN DOCUMENT ORDER, AND THE FOCUS CHAIN IS INSPECTABLE
-- (roadmap Step 8 follow-up; docs/plans/traversal-document-order.md; acceptance
-- rows TD-1..TD-12 in artifacts/traversal-document-order/acceptance.md).
--
-- THE DEFECT THIS FILE EXISTS FOR. A focusable `UI.Grip` was deferred to the end
-- of the focus order, correctly for the ARROWS (arrowing down a table should land
-- on rows, not on a value control's grab zone) and wrongly for TAB, which means
-- document order on every platform that has ever had a Tab key. A Slider's focus
-- stop is a Grip, so a Slider sitting between a button row and a list traversed
-- after the whole list — found by the director in a playtest, under a green suite
-- and three fresh-context reviews.
--
-- WHY THE SUITE WAS BLIND, AND WHAT THIS FILE DOES ABOUT IT. Every Step 8 fixture
-- put its value control on a screen ALONE or at the END, where a deferred Grip
-- and a document-ordered one produce the identical order. So the discipline here
-- is: a Grip-bearing control always sits BETWEEN ordinary controls, and every
-- traversal assertion has a companion asserting the arrows did NOT move.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local UI = LuauUI.UI
local customFactory = require("../src/core/custom")
local focus_graph = require("../src/focus/focus_graph")
local fake_target = require("../tests/lib/fake_target")

local function harnessWithAdapter(presenterOpts: any?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local opts = if presenterOpts ~= nil then table.clone(presenterOpts) else {}
	if opts.keyboardNavigation == nil then
		opts.keyboardNavigation = true
	end
	local pres = LuauUI.newPresenter(core, env, adapter, system, opts)
	pres.adapter = adapter -- test-local convenience, never a framework field
	return core, env, system, pres
end

local function harness(presenterOpts: any?)
	local core, env, system, pres = harnessWithAdapter(presenterOpts)
	return core, env, system, pres
end

-- which of `paths` is currently wearing the adapter's focus ring
local function focusedPath(adapter: any, paths: { string }): string?
	for _, p in paths do
		local node = adapter.node(p)
		if node ~= nil and node.focused == true then
			return p
		end
	end
	return nil
end

local function slider(core: any, id: string)
	return LuauUI.newSlider(LuauUI, core, { id = id, value = core:signal(0.5), min = 0, max = 1, step = 0.1 })
end

local function button(id: string, extra: any?)
	local spec: any = { id = id, label = id }
	if extra ~= nil then
		for k, v in extra do
			spec[k] = v
		end
	end
	return UI.Button(spec)
end

-- the order `handle.focusOrder()` reports for each reading
local function traversalOf(handle: any): { string }
	local out = {}
	for _, e in handle.focusOrder().traversal do
		table.insert(out, e.path)
	end
	return out
end

local function navigationOf(handle: any): { string }
	local out = {}
	for _, g in handle.focusOrder().navigation do
		for _, p in g.order do
			table.insert(out, p)
		end
	end
	return out
end

-- walk the WHOLE ring by pressing Tab, so the assertion is about what pressing
-- Tab actually does and not only about what the dump says it will do
local function tabRing(graph: any, n: number): { string }
	local seen = { graph.focused:get() }
	for _ = 2, n do
		graph.traverse(1)
		table.insert(seen, graph.focused:get())
	end
	return seen
end

--[[ PRESS TAB FOR REAL, AND RECORD WHERE FOCUS WENT.

	`handle.focusOrder()` and `graph.traverse` both read the rank, but by DIFFERENT
	code paths (`focusMap` sorts for the dump; `traverse` sorts for the move). A
	suite that only asserts the dump therefore cannot see a traversal that is wired
	wrong — proved by deleting the sort from `traverse` and watching every
	dump-based case here stay green while only three went red.

	So every ordering claim below is made twice: once against `mounted()` (the dump
	— cheap, and it is also the public API under test) and once against this (the
	behavior). `opts.onFocusNav` is the presenter's own focus-move report, driven
	from the arbitrated `system.deviceKey` path, and unlike the adapter's focus ring
	it sees a Slider's track (which declares `focusVisual = "none"`). ]]
local function tabPresses(build: (core: any) -> any, n: number, presentOpts: any?): { string }
	local core, _, system, pres = harness()
	local moves: { string } = {}
	local opts: any = if presentOpts ~= nil then table.clone(presentOpts) else {}
	opts.onFocusNav = function(path)
		table.insert(moves, path)
	end
	pres.present(build(core), opts)
	pres.refresh()
	for _ = 1, n do
		system.deviceKey("Tab", true)
		system.deviceKey("Tab", false)
	end
	return moves
end

-- =========================================================================
-- TD-1 / TD-2 / TD-3: the two readings, one set
-- =========================================================================

describe("a Grip-bearing control BETWEEN ordinary controls (TD-1, TD-2)", function()
	-- the exact shape the director tabbed through: something above the slider,
	-- and a list below it. A fixture with the slider last cannot fail.
	local function screenWithSliderInTheMiddle(core: any)
		return UI.Screen({
			id = "S",
			children = {
				button("Reset"),
				slider(core, "Volume").blueprint,
				button("Row1"),
				button("Row2"),
				button("Row3"),
			},
		})
	end

	it("Tab visits the Slider's track in DOCUMENT position, not last", function()
		local core, _, _, pres = harness()
		local handle = pres.present(screenWithSliderInTheMiddle(core))
		expect(table.concat(traversalOf(handle), " ")).toBe(
			"/S/Reset /S/Volume/TrackHost/Track /S/Row1 /S/Row2 /S/Row3"
		)
	end)

	it("...and the ARROWS still defer it to the end, exactly as before", function()
		local core, _, _, pres = harness()
		local handle = pres.present(screenWithSliderInTheMiddle(core))
		expect(table.concat(navigationOf(handle), " ")).toBe(
			"/S/Reset /S/Row1 /S/Row2 /S/Row3 /S/Volume/TrackHost/Track"
		)
	end)

	it("the two readings cover the SAME SET — traversal reorders, never adds or drops", function()
		local core, _, _, pres = harness()
		local handle = pres.present(screenWithSliderInTheMiddle(core))
		local a, b = traversalOf(handle), navigationOf(handle)
		table.sort(a)
		table.sort(b)
		expect(#a).toBe(5)
		expect(table.concat(a, " ")).toBe(table.concat(b, " "))
	end)

	-- THE DUMP MUST NOT BE THE ONLY WITNESS. `focusOrder()` and `traverse` read the
	-- same rank, so a dump-only assertion stays green if the rank is right and the
	-- traversal is wired wrong. This one presses the real key through the arbitrated
	-- device path and records `opts.onFocusNav`, the presenter's own focus-move
	-- report.
	--
	-- NOT the adapter's focus ring, which was the first thing tried here and is
	-- BLIND to the node under test: a Slider's track declares `focusVisual = "none"`
	-- so it can paint its own focused treatment, so the one path this test exists
	-- to catch never wears the adapter ring at all.
	it("pressing Tab really moves focus in that order (onFocusNav, not the dump)", function()
		local core, _, system, pres = harness()
		local moves: { string } = {}
		local handle = pres.present(screenWithSliderInTheMiddle(core), {
			onFocusNav = function(path)
				table.insert(moves, path)
			end,
		})
		pres.refresh()
		for _ = 1, 4 do
			system.deviceKey("Tab", true)
			system.deviceKey("Tab", false)
		end
		expect(table.concat(moves, " ")).toBe("/S/Volume/TrackHost/Track /S/Row1 /S/Row2 /S/Row3")
		expect(handle.focusOrder().traversal[2].path).toBe("/S/Volume/TrackHost/Track")
	end)
end)

describe("every focusable Grip traverses in document position — no exceptions (TD-4)", function()
	-- decision TDN-1: the rule is "a focusable Grip", never "a Grip used for X".
	-- The shipped ones are newSlider's track and newRating's strip, both value
	-- controls; a BARE Grip is the general case those two are instances of, so it
	-- is what this pins. (Table's resize grip is focusable = false — pointer only.)
	local function gripBetweenButtons(_core: any)
		return UI.Screen({
			id = "S",
			children = {
				button("Before"),
				UI.Grip({ id = "Resize", focusable = true }),
				button("After"),
			},
		})
	end

	it("a bare focusable Grip declared between buttons traverses between them", function()
		local core, _, _, pres = harness()
		local handle = pres.present(gripBetweenButtons(core))
		expect(table.concat(traversalOf(handle), " ")).toBe("/S/Before /S/Resize /S/After")
		expect(table.concat(navigationOf(handle), " ")).toBe("/S/Before /S/After /S/Resize")
	end)

	it("...and pressing Tab really lands on it there", function()
		expect(table.concat(tabPresses(gripBetweenButtons, 2), " ")).toBe("/S/Resize /S/After")
	end)

	-- BOTH shipped focusable Grips, not just the one the defect was reported
	-- against. `newSlider`'s track is covered above; `newRating`'s strip is the
	-- other, and a rule that happened to work for one control and not the other
	-- would be the same purpose-derived special case TDN-1 refused.
	it("newRating's strip Grip traverses in document position too", function()
		local core, _, _, pres = harness()
		local rating = LuauUI.newRating(LuauUI, core, { id = "Stars", value = core:signal(3), count = 5 })
		local handle = pres.present(UI.Screen({
			id = "S",
			children = { button("Before"), rating.blueprint, button("After") },
		}))
		expect(traversalOf(handle)[2]).toBe("/S/Stars/Strip")
		expect(navigationOf(handle)[3]).toBe("/S/Stars/Strip") -- arrows: still last
	end)
end)

-- =========================================================================
-- TD-5 / TD-6: traversalPriority
-- =========================================================================

describe("traversalPriority is a sort TIER, not an index (TD-5, TD-6)", function()
	local function tiered(_core: any)
		return UI.Screen({
			id = "S",
			children = { button("A"), button("Submit", { traversalPriority = 1 }), button("B"), button("C") },
		})
	end

	it("a positive tier pushes one control to the back without moving the others", function()
		local _, _, _, pres = harness()
		expect(table.concat(traversalOf(pres.present(tiered(nil))), " ")).toBe("/S/A /S/B /S/C /S/Submit")
	end)

	it("...and pressing Tab really reaches Submit last", function()
		expect(table.concat(tabPresses(tiered, 3), " ")).toBe("/S/B /S/C /S/Submit")
	end)

	it("a negative tier pulls one to the front", function()
		local _, _, _, pres = harness()
		local handle = pres.present(UI.Screen({
			id = "S",
			children = { button("A"), button("B"), button("Skip", { traversalPriority = -1 }) },
		}))
		expect(table.concat(traversalOf(handle), " ")).toBe("/S/Skip /S/A /S/B")
	end)

	it("within one tier, DOCUMENT order always wins", function()
		local _, _, _, pres = harness()
		local handle = pres.present(UI.Screen({
			id = "S",
			children = {
				button("A", { traversalPriority = 2 }),
				button("B", { traversalPriority = 2 }),
				button("C", { traversalPriority = 2 }),
			},
		}))
		expect(table.concat(traversalOf(handle), " ")).toBe("/S/A /S/B /S/C")
	end)

	it("the tier does NOT reach the arrows", function()
		local _, _, _, pres = harness()
		local handle = pres.present(UI.Screen({
			id = "S",
			children = { button("A"), button("Submit", { traversalPriority = 1 }), button("B") },
		}))
		expect(table.concat(navigationOf(handle), " ")).toBe("/S/A /S/Submit /S/B")
	end)

	it("a tier moves a GRIP relative to document order too", function()
		local core, _, _, pres = harness()
		local handle = pres.present(UI.Screen({
			id = "S",
			children = {
				button("Before"),
				slider(core, "Volume").blueprint,
				button("After"),
			},
		}))
		expect(traversalOf(handle)[2]).toBe("/S/Volume/TrackHost/Track")
	end)
end)

describe("traversalPriority refuses what it cannot honour (TD-8)", function()
	local function refusal(fn: () -> ()): string
		local ok, err = pcall(fn)
		expect(ok).toBe(false)
		return tostring(err)
	end

	it("a non-number is refused, naming the property", function()
		local err = refusal(function()
			UI.Button({ id = "B", label = "B", traversalPriority = "first" })
		end)
		expect(string.find(err, "traversalPriority") ~= nil).toBe(true)
	end)

	it("a BOUND value is refused: the prop is construction-only", function()
		local core = LuauUI.newCore()
		local err = refusal(function()
			UI.Button({ id = "B", label = "B", traversalPriority = core:signal(1) })
		end)
		expect(string.find(err, "traversalPriority") ~= nil).toBe(true)
	end)

	it("an unknown neighbour is still refused by name (the guard is live)", function()
		local err = refusal(function()
			UI.Button({ id = "B", label = "B", traversalPriorty = 1 })
		end)
		expect(string.find(err, "traversalPriorty") ~= nil).toBe(true)
	end)
end)

-- =========================================================================
-- TD-7: a consumer-declared map keeps its declared order verbatim
-- =========================================================================

describe("an explicit navigationGroups map is NOT re-ranked (TD-7)", function()
	it("the declared order survives exactly, grips and all", function()
		local core, _, _, pres = harness()
		local s = slider(core, "Volume")
		local handle = pres.present(
			UI.Screen({
				id = "S",
				children = { button("A"), s.blueprint, button("B") },
			}),
			{
				navigationGroups = {
					{
						name = "mine",
						axis = "vertical",
						order = { "/S/B", "/S/Volume/TrackHost/Track", "/S/A" },
					},
				},
			}
		)
		expect(table.concat(traversalOf(handle), " ")).toBe("/S/B /S/Volume/TrackHost/Track /S/A")
		expect(handle.focusOrder().ranked).toBe(false)
	end)

	it("...and pressing Tab really follows the DECLARED order, not document order", function()
		local groups = {
			{ name = "mine", axis = "vertical", order = { "/S/B", "/S/Volume/TrackHost/Track", "/S/A" } },
		}
		local moves = tabPresses(function(core)
			return UI.Screen({
				id = "S",
				children = { button("A"), slider(core, "Volume").blueprint, button("B") },
			})
		end, 2, { navigationGroups = groups })
		expect(table.concat(moves, " ")).toBe("/S/Volume/TrackHost/Track /S/A")
	end)

	it("navigationGroups = false is NOT a declared map: the flat ring is still ranked", function()
		local core, _, _, pres = harness()
		local handle = pres.present(
			UI.Screen({
				id = "S",
				children = { button("A"), slider(core, "Volume").blueprint, button("B") },
			}),
			{ navigationGroups = false }
		)
		expect(handle.focusOrder().ranked).toBe(true)
		expect(table.concat(traversalOf(handle), " ")).toBe("/S/A /S/Volume/TrackHost/Track /S/B")
	end)
end)

-- =========================================================================
-- TD-9 / TD-10: the inspection dump
-- =========================================================================

describe("handle.focusOrder() (TD-9, TD-10)", function()
	it("carries its schema and both readings", function()
		local core, _, _, pres = harness()
		local dump = pres.present(UI.Screen({
			id = "S",
			children = { button("A"), slider(core, "V").blueprint },
		})).focusOrder()
		expect(dump.schema).toBe("luauui-focus-order/1")
		expect(dump.scope).toBe("S")
		expect(dump.present).toBe(true)
		expect(#dump.traversal > 0).toBe(true)
		expect(#dump.navigation > 0).toBe(true)
	end)

	it("is deterministic: two calls with nothing changed are equal", function()
		local core, _, _, pres = harness()
		local handle = pres.present(UI.Screen({
			id = "S",
			children = { button("A"), slider(core, "V").blueprint, button("B") },
		}))
		expect(table.concat(traversalOf(handle), " ")).toBe(table.concat(traversalOf(handle), " "))
	end)

	it("is frozen — an inspector cannot mutate the map it is inspecting", function()
		local _, _, _, pres = harness()
		local dump = pres.present(UI.Screen({ id = "S", children = { button("A") } })).focusOrder()
		expect(pcall(function()
			(dump :: any).traversal = {}
		end)).toBe(false)
	end)

	it("reports the AUTHORED tier per entry", function()
		local _, _, _, pres = harness()
		local dump = pres.present(UI.Screen({
			id = "S",
			children = { button("A"), button("Late", { traversalPriority = 3 }) },
		})).focusOrder()
		local byPath: { [string]: number } = {}
		for _, e in dump.traversal do
			byPath[e.path] = e.priority
		end
		expect(byPath["/S/A"]).toBe(0)
		expect(byPath["/S/Late"]).toBe(3)
	end)

	it("survives dispose: an overlay outliving its surface gets an empty map, not a throw", function()
		local _, _, _, pres = harness()
		local handle = pres.present(UI.Screen({ id = "S", children = { button("A") } }))
		pres.dismiss(handle)
		local dump = handle.focusOrder()
		expect(dump.schema).toBe("luauui-focus-order/1")
		expect(dump.present).toBe(false)
		expect(#dump.traversal).toBe(0)
	end)
end)

-- =========================================================================
-- TD-3 / TD-11: the same exclusions, and churn
-- =========================================================================

describe("traversal skips exactly what the arrows skip (TD-3)", function()
	it("a disabled control leaves BOTH readings", function()
		local core, _, _, pres = harness()
		local handle = pres.present(UI.Screen({
			id = "S",
			children = {
				button("A"),
				slider(core, "V").blueprint,
				button("Off", { enabled = false }),
				button("B"),
			},
		}))
		expect(string.find(table.concat(traversalOf(handle), " "), "/S/Off")).toBe(nil)
		expect(string.find(table.concat(navigationOf(handle), " "), "/S/Off")).toBe(nil)
	end)

	it("focusable = false leaves both readings", function()
		local core, _, _, pres = harness()
		local handle = pres.present(UI.Screen({
			id = "S",
			children = {
				button("A"),
				slider(core, "V").blueprint,
				button("Hidden", { focusable = false }),
			},
		}))
		expect(string.find(table.concat(traversalOf(handle), " "), "/S/Hidden")).toBe(nil)
		expect(string.find(table.concat(navigationOf(handle), " "), "/S/Hidden")).toBe(nil)
	end)
end)

describe("structural churn re-ranks on the next press (TD-11)", function()
	it("a row mounted after present() takes its document position, not the end", function()
		local core, _, _, pres = harness()
		local show = core:signal(false)
		local handle = pres.present(UI.Screen({
			id = "S",
			children = {
				button("A"),
				UI.When({
					id = "W",
					condition = show,
					thenView = function()
						return button("Late")
					end,
				}),
				slider(core, "V").blueprint,
				button("B"),
			},
		}))
		expect(table.concat(traversalOf(handle), " ")).toBe("/S/A /S/V/TrackHost/Track /S/B")
		show:set(true)
		pres.refresh()
		local after = table.concat(traversalOf(handle), " ")
		expect(string.find(after, "/S/W/then/Late") ~= nil).toBe(true)
		-- the new row sits BEFORE the slider, where it was declared — a rank that
		-- was computed once at present() would have appended it instead
		expect(string.find(after, "/S/W/then/Late") < string.find(after, "/S/V/TrackHost/Track")).toBe(true)
	end)
end)

-- =========================================================================
-- TD-12: modal and transient scopes
-- =========================================================================

describe("a modal traverses in document order too, and still traps (TD-12)", function()
	it("a Grip inside a modal takes its document position within the modal", function()
		local core, _, _, pres = harness()
		pres.present(UI.Screen({ id = "Base", children = { button("BaseBtn") } }))
		local modal = pres.presentModal(UI.Screen({
			id = "M",
			children = { button("Yes"), slider(core, "V").blueprint, button("No") },
		}))
		expect(table.concat(traversalOf(modal), " ")).toBe("/M/Yes /M/V/TrackHost/Track /M/No")
		expect(modal.focusOrder().trap).toBe(true)
		-- and nothing from the covered screen is reachable
		expect(string.find(table.concat(traversalOf(modal), " "), "BaseBtn")).toBe(nil)
	end)
end)

-- =========================================================================
-- the graph contract underneath, driven directly
-- =========================================================================

describe("graph.traverse sorts by rank without changing membership (TDN-2)", function()
	local function ranked(order: { any }, rank: { [string]: number }?)
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		graph.pushScope({ name = "S", trap = false, order = order, traversalRank = rank })
		return graph
	end

	it("no rank means the pre-stage reading, byte for byte", function()
		local graph = ranked({ "a", "b", "c" })
		expect(table.concat(tabRing(graph, 3), " ")).toBe("a b c")
	end)

	-- the rank is chosen so the RING differs from the unranked one. {a=3,b=1,c=2}
	-- would not: entry focus is `allIds` first ("a", see the entry-focus case
	-- below), and walking [b,c,a] from "a" wraps to b then c — the same sequence
	-- an unranked scope produces, so that rank could not fail.
	it("a rank reorders the SAME members", function()
		local graph = ranked({ "a", "b", "c" }, { a = 1, b = 3, c = 2 })
		expect(table.concat(tabRing(graph, 3), " ")).toBe("a c b")
	end)

	-- PINNED, NOT FIXED. Entry focus is where a scope is ENTERED, which is a
	-- directional concern shared with the arrows, so it reads `allIds` and is
	-- deliberately left alone by this stage. It only diverges when a scope's very
	-- first document-order node is a Grip; the ledger records it as not claimed.
	it("ENTRY focus still reads the unranked order, by design", function()
		local graph = ranked({ "a", "b", "c" }, { a = 3, b = 1, c = 2 })
		expect(graph.focused:get()).toBe("a")
	end)

	it("an INCOMPLETE rank is ignored entirely rather than applied to half the ring", function()
		-- a partial map cannot be sorted: mixing ranked and unranked entries and
		-- falling back to index order for the mixed pairs is intransitive, which
		-- Luau's sort may reject or answer with garbage. Falling back to the
		-- unranked reading is at worst old; a half-applied one is unpredictable.
		local graph = ranked({ "a", "b", "c" }, { a = 3, c = 1 })
		expect(table.concat(tabRing(graph, 3), " ")).toBe("a b c")
	end)

	it("the arrows never read the rank", function()
		local graph = ranked({ "a", "b", "c" }, { a = 3, b = 1, c = 2 })
		expect(graph.focused:get()).toBe("a")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("b")
	end)

	it("the graph keeps its OWN copy of the rank (F-14)", function()
		local mine = { a = 1, b = 3, c = 2 }
		local graph = ranked({ "a", "b", "c" }, mine)
		mine.b = 0 -- reach back in after the push; the live scope must not move
		expect(table.concat(tabRing(graph, 3), " ")).toBe("a c b")
	end)
end)
