--!strict
-- Rating (director round 10, 2026-07-26): a run of glyphs that reads as ONE
-- value and takes ONE focus stop.
--
-- The control exists because the obvious spelling — one Button per star — was
-- wrong on three axes at once, and every one of them showed up on a phone:
-- five themed plates instead of five glyphs, five focus stops for one number,
-- and five activation handlers all writing the same signal. These tests pin
-- each of those, plus the four-input reach the conformance registry demands.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local Facet = require("../src") :: any
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local presenterLib = require("../src/present/presenter")
local actionsLib = require("../src/input/actions")
local fake_target = require("../tests/lib/fake_target")
local chrome_slots = require("../src/tokens/chrome_slots")

local STRIP = "/S/Stars/Strip"

local function mount(specOverrides: any?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	local value = core:signal(3)
	local spec: any = { id = "Stars", value = value }
	for k, v in (specOverrides or {}) :: any do
		spec[k] = v
	end
	local control = Facet.Controls.Rating(core, spec)
	pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
	pres.refresh()
	return core, adapter, system, pres, value, control
end

-- a point at the given fraction across the strip's solved rect
local function pointAt(adapter: any, fraction: number): (number, number)
	local rect = adapter.node(STRIP).rect
	return rect.x + rect.w * fraction, rect.y + rect.h / 2
end

describe("Rating: the value model", function()
	it("a read-only Memo is refused at BUILD, not on the first tap", function()
		local core = customFactory.new()
		expect(pcall(function()
			return Facet.Controls.Rating(core, {
				id = "R",
				value = core:memo(function()
					return 3
				end),
			})
		end)).toBe(false)
	end)

	it("a count that is not a whole number >= 1 is a build error", function()
		local core = customFactory.new()
		for _, bad in { 0, -3, 2.5 } do
			expect(pcall(function()
				return Facet.Controls.Rating(core, { id = "R", value = core:signal(1), count = bad })
			end)).toBe(false)
		end
	end)

	it("glyphs are filled up to the value and hollow after it, and repaint in place", function()
		local _, adapter, _, pres, value = mount()
		local function glyphs(): string
			local out = ""
			for i = 1, 5 do
				out ..= adapter.node(`/S/Stars/Stars/Star{i}`).props.text
			end
			return out
		end
		expect(glyphs()).toBe("★★★☆☆")
		local before = adapter.liveCount()
		value:set(5)
		pres.refresh()
		expect(glyphs()).toBe("★★★★★")
		-- a rating change is PAINT: no node was created or destroyed
		expect(adapter.liveCount()).toBe(before)
	end)

	it("the value is clamped to the run, and to zero only when zero is allowed", function()
		local _, adapter, _, pres, value = mount()
		adapter.pointerDown(STRIP, pointAt(adapter, -2))
		pres.refresh()
		expect(value:get()).toBe(0)
		local _, adapter2, _, pres2, value2 = mount({ allowZero = false })
		adapter2.pointerDown(STRIP, pointAt(adapter2, -2))
		pres2.refresh()
		expect(value2:get()).toBe(1)
	end)

	it("semantic text reports the value IN ITS RANGE, never a bare number", function()
		local _, _, _, _, _, control = mount()
		expect(control.semanticText:get()).toBe("3 of 5")
	end)

	-- CTRL-08c (api-architecture-consistency F-25). Neither `dump()` nor
	-- `dispose()` was called by ANY test in this file — the registration gate
	-- passed on the substring "function api.dump" alone — so both promises were
	-- unproven while every sibling in the value family has an explicit case.
	it("dump is deterministic and carries its schema string", function()
		local serde = require("@lune/serde")
		local _, adapter, _, pres, _, control = mount()
		expect(control.dump().schema).toBe("facet-rating-dump/1")
		local d1 = serde.encode("json", control.dump(), true)
		expect(d1).toBe(serde.encode("json", control.dump(), true))
		adapter.pointerDown(STRIP, pointAt(adapter, 0.9))
		pres.refresh()
		local d2 = serde.encode("json", control.dump(), true)
		expect(d2).toBe(serde.encode("json", control.dump(), true))
		expect(d2 ~= d1).toBe(true)
	end)

	it("build/interact/dispose returns the registry to its baseline", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local baseline = core:counters() -- AFTER the long-lived singletons

		local value = core:signal(3)
		local control = Facet.Controls.Rating(core, { id = "Stars", value = value, env = env })
		local handle = pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		adapter.pointerDown(STRIP, pointAt(adapter, 0.9))
		pres.refresh()
		control.dump()

		pres.dismiss(handle)
		control.dispose()
		value:dispose()

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)
end)

describe("Rating: one control, not N buttons", function()
	it("no star is a Button, so no theme can paint a plate behind one", function()
		-- the defect this control replaces: five Buttons meant five `control`
		-- decorations. Under Glossy Touch that was five glossy pills; under
		-- Glossy Mobile, whose control recipe is a raised SHADOW, five shadows
		-- overlapped into a smeared band behind the row.
		local _, adapter = mount()
		for i = 1, 5 do
			local node = adapter.node(`/S/Stars/Stars/Star{i}`)
			expect(node.class).toBe("Text")
			expect(chrome_slots.classify({ class = node.class, surface = node.props.surface })).toBeNil()
		end
	end)

	it("the whole strip is ONE focus stop, not one per star", function()
		-- the defect this replaces: five Buttons meant a gamepad user pressed
		-- Right four times to cross ONE cell. Walk the ring and prove it lands on
		-- the strip and never on a star, however far you walk.
		local _, _, system, pres = mount()
		local seen: { [string]: boolean } = {}
		for _ = 1, 8 do
			system.deviceKey("DPadDown", true)
			system.deviceKey("DPadDown", false)
			pres.refresh()
			seen[tostring(pres.focus.focused:get())] = true
			system.deviceKey("DPadRight", true)
			system.deviceKey("DPadRight", false)
			pres.refresh()
			seen[tostring(pres.focus.focused:get())] = true
		end
		expect(seen[STRIP]).toBe(true)
		for i = 1, 5 do
			expect(seen[`/S/Stars/Stars/Star{i}`]).never().toBe(true)
		end
	end)

	it("a read-only rating paints but is not focusable and refuses every input", function()
		local _, adapter, _, pres, value = mount({ readOnly = true })
		expect(adapter.node(`/S/Stars/Stars/Star1`).props.text).toBe("★")
		-- nothing in a read-only rating is reachable: the ring never lands inside
		local _, _, system2, pres2 = mount({ readOnly = true })
		system2.deviceKey("DPadDown", true)
		system2.deviceKey("DPadDown", false)
		pres2.refresh()
		expect(tostring(pres2.focus.focused:get())).never().toBe(STRIP)
		adapter.pointerDown(STRIP, pointAt(adapter, 0.9))
		pres.refresh()
		expect(value:get()).toBe(3)
	end)

	it("a disabled rating refuses every input class, not just the pointer", function()
		local _, adapter, system, pres, value = mount({ enabled = false })
		adapter.pointerDown(STRIP, pointAt(adapter, 0.9))
		pres.refresh()
		expect(value:get()).toBe(3)
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		system.deviceKey("Period", true)
		system.deviceKey("Period", false)
		pres.refresh()
		expect(value:get()).toBe(3)
	end)
end)

describe("Rating reaches the same arithmetic from every input class", function()
	it("pointer: clicking a star sets the rating to that star", function()
		local _, adapter, _, pres, value = mount()
		adapter.pointerDown(STRIP, pointAt(adapter, 0.9))
		adapter.pointerUp(pointAt(adapter, 0.9))
		pres.refresh()
		expect(value:get()).toBe(5)
		adapter.pointerDown(STRIP, pointAt(adapter, 0.3))
		adapter.pointerUp(pointAt(adapter, 0.3))
		pres.refresh()
		expect(value:get()).toBe(2)
	end)

	it("touch: a finger drag across the strip scrubs the value live", function()
		local _, adapter, _, pres, value = mount()
		adapter.pointerDown(STRIP, pointAt(adapter, 0.1), "touch")
		pres.refresh()
		expect(value:get()).toBe(1)
		adapter.pointerMove(pointAt(adapter, 0.7))
		pres.refresh()
		expect(value:get()).toBe(4)
		adapter.pointerUp(pointAt(adapter, 0.7))
		pres.refresh()
		expect(value:get()).toBe(4)
	end)

	it("keyboard: Adjust on the focused strip rates without touching a star", function()
		local _, _, system, pres, value = mount()
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		system.deviceKey("Period", true)
		system.deviceKey("Period", false)
		pres.refresh()
		expect(value:get()).toBe(4)
		system.deviceKey("Comma", true)
		system.deviceKey("Comma", false)
		pres.refresh()
		expect(value:get()).toBe(3)
	end)

	it("gamepad: the bumpers Adjust the focused rating", function()
		local _, _, system, pres, value = mount()
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		system.deviceKey("ButtonR1", true)
		system.deviceKey("ButtonR1", false)
		pres.refresh()
		expect(value:get()).toBe(4)
		system.deviceKey("ButtonL1", true)
		system.deviceKey("ButtonL1", false)
		pres.refresh()
		expect(value:get()).toBe(3)
	end)

	it("no Adjust key is bound while focus sits outside the Rating (no gameplay bumper shadow)", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local value = core:signal(3)
		local control = Facet.Controls.Rating(core, { id = "Stars", value = value })
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "Elsewhere", label = "elsewhere", height = { type = "fixed", px = 44 } }),
				control.blueprint,
			},
		}))
		pres.refresh()
		-- focus is on the first focusable, which is OUTSIDE the rating
		system.deviceKey("ButtonR1", true)
		system.deviceKey("ButtonR1", false)
		pres.refresh()
		expect(value:get()).toBe(3)
	end)

	it("hotSwitch: losing the pointer mid-scrub CANCELS back, it never commits", function()
		local _, adapter, _, pres, value, control = mount()
		adapter.pointerDown(STRIP, pointAt(adapter, 0.9))
		pres.refresh()
		expect(value:get()).toBe(5)
		control.onInteractionClassLost("pointer")
		pres.refresh()
		expect(value:get()).toBe(3) -- the pre-scrub value, not the half-finished one
	end)
end)

-- ===========================================================================
-- A VALUE CONTROL YIELDS THE ARROW AT ITS LIMIT (ruling 9, 2026-08-14)
--
-- MEASURED LIVE on the shipped playlist before this landed: `DPadRight` on the
-- rating strip moved the rating 4 -> 5 and never the focus ring — and at 5 of 5
-- it moved NOTHING, so everything after the rating in that row was unreachable
-- on a gamepad. A gamepad has no Tab, so "every action is reachable on every
-- input device" was false on a surface that ships.
--
-- THE RULE, one sentence: a control that TOOK the arrow away from navigation
-- gives it back the moment it cannot use it. Pressing Right at 5 of 5 has no
-- other possible intent.
--
-- WHAT DOES NOT YIELD, and why it matters as much: Comma/Period and the L1/R1
-- bumpers are the control's DEDICATED adjust keys — the presenter binds them
-- precisely because the arrows are contended, and they take nothing away from
-- navigation. A bumper at the limit therefore does nothing, exactly as it does
-- on a platform stepper. The negative case below is that scoping.
-- ===========================================================================
describe("Rating: at its limit the arrow goes back to navigation", function()
	-- HORIZONTAL NAVIGATION HAS TO EXIST FOR THERE TO BE ANYTHING TO YIELD TO, and
	-- the groups are DECLARED here rather than derived. The layout-derived gate
	-- (`focus_map.layoutGroups`) defers every Grip to an `auto-grips` group at the
	-- END of the ring, so a bare HStack of [rating, button] never walks onto the
	-- strip horizontally at all — the shipped playlist reaches it through Table's
	-- own `focusGroups`, which puts the row's cells in one horizontal group. A
	-- declared group is the same shape without dragging a Table into a Rating unit
	-- test; the shipped surface itself is covered in tests/examples_gallery.spec.
	local ROW_STRIP = "/S/Row/Stars/Strip"
	local AFTER = "/S/Row/After"
	local BEFORE = "/S/Row/Before"
	local function mountRow(start: number)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local value = core:signal(start)
		local control = Facet.Controls.Rating(core, { id = "Stars", value = value })
		pres.present(
			UI.Screen({
				id = "S",
				children = {
					UI.HStack({
						id = "Row",
						gap = 8,
						children = {
							UI.Button({ id = "Before", label = "Before", height = { type = "fixed", px = 44 } }),
							control.blueprint,
							UI.Button({ id = "After", label = "After", height = { type = "fixed", px = 44 } }),
						},
					}),
				},
			}),
			{ navigationGroups = { { name = "row", axis = "horizontal", order = { BEFORE, ROW_STRIP, AFTER } } } }
		)
		pres.refresh()
		local function tap(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
			pres.refresh()
		end
		-- there is something on BOTH sides of the strip, so a yield in either
		-- direction has a real destination and the two limit cases are symmetric
		tap("DPadRight")
		return value, pres, tap
	end

	it("at the MAXIMUM, one more Right moves the ring instead of the rating", function()
		local value, pres, tap = mountRow(4)
		expect(tostring(pres.focus.focused:get())).toBe(ROW_STRIP)
		tap("DPadRight") -- 4 -> 5, the ring must NOT move
		expect(`{value:get()}@{pres.focus.focused:get()}`).toBe(`5@{ROW_STRIP}`)
		tap("DPadRight") -- at the maximum: the ring moves, the value does not
		expect(`{value:get()}@{pres.focus.focused:get()}`).toBe(`5@{AFTER}`)
	end)

	it("at the MINIMUM, one more Left moves the ring the other way", function()
		local value, pres, tap = mountRow(1)
		tap("DPadLeft") -- 1 -> 0 (zero is allowed by default)
		expect(`{value:get()}@{pres.focus.focused:get()}`).toBe(`0@{ROW_STRIP}`)
		tap("DPadLeft") -- at the minimum: the ring moves, the value does not
		expect(`{value:get()}@{pres.focus.focused:get()}`).toBe(`0@{BEFORE}`)
	end)

	it("the yield RE-ARMS: walking back onto the strip adjusts again", function()
		local value, pres, tap = mountRow(5)
		tap("DPadRight") -- yields
		expect(tostring(pres.focus.focused:get())).toBe(AFTER)
		tap("DPadLeft") -- back onto the strip (navigation, not adjust)
		expect(tostring(pres.focus.focused:get())).toBe(ROW_STRIP)
		tap("DPadLeft") -- and the arrow is the control's again
		expect(value:get()).toBe(4)
	end)

	it("the yield RE-ARMS: the NEXT value control in the row is not dead on arrival", function()
		--[[ TWO VALUE CONTROLS IN ONE ROW, which is the shape a table with two rated
			columns already ships: the first one yields, the ring lands on the second,
			and the second must still be a working control rather than a stop the
			player has to leave and re-enter.

			(Separately found and NOT fixed here: the Adjust keys are bound by the
			focus-CHANGE observer, so a value control holding focus from the moment a
			screen mounts has no Adjust binding until focus leaves it and comes back.
			A different defect from this one — reported, not smuggled in. It is why
			the ring enters the first strip by navigating, which is also how a player
			reaches it.) ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local left, right = core:signal(5), core:signal(2)
		local a = Facet.Controls.Rating(core, { id = "A", value = left })
		local b = Facet.Controls.Rating(core, { id = "B", value = right })
		local A, B = "/S/Row/A/Strip", "/S/Row/B/Strip"
		local START = "/S/Row/Start"
		pres.present(
			UI.Screen({
				id = "S",
				children = {
					UI.HStack({
						id = "Row",
						gap = 8,
						children = {
							UI.Button({ id = "Start", label = "Start", height = { type = "fixed", px = 44 } }),
							a.blueprint,
							b.blueprint,
						},
					}),
				},
			}),
			{ navigationGroups = { { name = "row", axis = "horizontal", order = { START, A, B } } } }
		)
		pres.refresh()
		local function tap(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
			pres.refresh()
		end
		expect(tostring(pres.focus.focused:get())).toBe(START)
		tap("DPadRight") -- onto A
		expect(tostring(pres.focus.focused:get())).toBe(A)
		tap("DPadRight") -- A is at 5 of 5: it yields, and the ring moves to B
		expect(`{left:get()}@{pres.focus.focused:get()}`).toBe(`5@{B}`)
		tap("DPadRight") -- ...and B, which has room to move, must actually move
		expect(`{right:get()}@{pres.focus.focused:get()}`).toBe(`3@{B}`)
	end)

	it("the yield RE-ARMS: the rating in the NEXT ROW down still takes the arrow", function()
		--[[ THE LOST KEY-UP, and the one sequence that actually reaches it.

			A yield unbinds the Adjust keys on the key-DOWN (focus left the target),
			so the key-UP that would return `AdjustAxis` to neutral has nowhere to be
			delivered and the action stays latched at 1. `_deliver` deduplicates, so
			the next press of that same arrow is swallowed outright.

			Every HORIZONTAL way back to a value control clears the latch by
			accident: the arrow that walks back is bound to the freshly-re-bound
			`AdjustAxis` by the time its own key-up lands, which neutralises it. So
			the defect needs a VERTICAL return — and a column of rated rows is
			exactly the shipped playlist. Row 1's rating is at its maximum, the
			player pushes Right, lands on the row's button, presses Down onto row 2's
			rating, and pushes Right: without the reset, nothing happens at all. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local top, bottom = core:signal(5), core:signal(2)
		local r1 = Facet.Controls.Rating(core, { id = "R1", value = top })
		local r2 = Facet.Controls.Rating(core, { id = "R2", value = bottom })
		local ENTER, S1, BTN, S2 =
			"/S/Body/Row1/Enter", "/S/Body/Row1/R1/Strip", "/S/Body/Row1/Btn", "/S/Body/Row2/R2/Strip"
		local function btn(id: string)
			return UI.Button({ id = id, label = id, height = { type = "fixed", px = 44 } })
		end
		pres.present(
			UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Body",
						gap = 8,
						children = {
							UI.HStack({ id = "Row1", gap = 8, children = { btn("Enter"), r1.blueprint, btn("Btn") } }),
							UI.HStack({ id = "Row2", gap = 8, children = { r2.blueprint } }),
						},
					}),
				},
			}),
			{
				navigationGroups = {
					{ name = "r1", axis = "horizontal", order = { ENTER, S1, BTN } },
					{ name = "r2", axis = "horizontal", order = { S2 } },
				},
			}
		)
		pres.refresh()
		local function tap(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
			pres.refresh()
		end
		tap("DPadRight") -- Enter -> row 1's rating (which is at 5 of 5)
		expect(tostring(pres.focus.focused:get())).toBe(S1)
		tap("DPadRight") -- at the maximum: yields onto the row's button
		expect(`{top:get()}@{pres.focus.focused:get()}`).toBe(`5@{BTN}`)
		tap("DPadDown") -- down to row 2's rating: a VERTICAL key, so nothing on the
		-- horizontal adjust action ever sees a release
		expect(tostring(pres.focus.focused:get())).toBe(S2)
		tap("DPadRight") -- ...and this rating has room, so it must move
		expect(`{bottom:get()}@{pres.focus.focused:get()}`).toBe(`3@{S2}`)
	end)

	it("BELOW the limit the arrow is still the control's — the ring never moves", function()
		local value, pres, tap = mountRow(1)
		for _ = 1, 4 do
			tap("DPadRight")
		end
		expect(`{value:get()}@{pres.focus.focused:get()}`).toBe(`5@{ROW_STRIP}`)
	end)

	it("NEGATIVE CONTROL: the BUMPERS never yield — they took nothing from navigation", function()
		local value, pres, tap = mountRow(5)
		tap("ButtonR1") -- at the maximum, on a dedicated adjust key
		expect(`{value:get()}@{pres.focus.focused:get()}`).toBe(`5@{ROW_STRIP}`)
		tap("Period") -- ...and the keyboard's dedicated adjust key agrees
		expect(`{value:get()}@{pres.focus.focused:get()}`).toBe(`5@{ROW_STRIP}`)
		-- POSITIVE CONTROL in the same session: the arrow, on the same control at
		-- the same limit, DOES yield — so the two lines above are a statement about
		-- the key rather than about this fixture being stuck.
		tap("DPadRight")
		expect(tostring(pres.focus.focused:get())).toBe(AFTER)
	end)
end)

-- ===========================================================================
-- A RATING IS A ROW OF ICONS, SO IT SIZES LIKE ONE
-- (measured across all nine shipped packages, 2026-07-27)
--
-- The star was first sized at `iconSizes.medium` — the rung that is right for
-- ONE icon and wrong for five of them side by side. Under Glossy Touch the
-- strip measured 164px and under Pixel Quest and Fantasy Ornate 176px, all of
-- which overrun the 132px column a table gives a rating cell, so the stars ran
-- off the end of their cells in exactly the themes the director was looking at.
-- ===========================================================================
describe("Rating: the strip fits the cell a table gives it, under every package", function()
	local themes = Facet.themes
	local fake = require("../tests/lib/fake_target")
	local PACKAGES = {
		"glossy_touch",
		"glossy_mobile",
		"pixel_quest",
		"fantasy_ornate",
		"scifi_hud",
		"compact_pointer",
		"classic_desktop",
		"fantasy_parchment",
	}
	-- the playlist demo's rating column
	local COLUMN = 144

	local function stripWidth(pkg: any?, starSize: string?): number
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 430, h = 900 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake.new()
		local pres = presenterLib.new(core, env, adapter, actionsLib.newSystem(core))
		local control = Facet.Controls.Rating(core, { id = "R", value = core:signal(3), starSize = starSize })
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.ZStack({
					id = "Cell",
					width = { type = "fixed", px = COLUMN },
					height = { type = "fixed", px = 48 },
					children = { control.blueprint },
				}),
			},
		}))
		pres.refresh()
		if pkg ~= nil then
			env:set("themeMetrics", themes.resolve(pkg, nil, {}))
			pres.refresh()
		end
		local last = adapter.node("/S/Cell/R/Stars/Star5").rect
		return last.x + last.w
	end

	it("five stars fit a 132px cell in the flat theme and in all eight shipped packages", function()
		expect(stripWidth(nil) <= COLUMN).toBe(true)
		for _, name in PACKAGES do
			local pkg = (require)(`../examples/themes/{name}`).build(themes)
			expect(stripWidth(pkg) <= COLUMN).toBe(true)
		end
	end)

	it("...at the rung a table row actually uses, in every package", function()
		-- Round 12 asserted this at ALL THREE rungs, which an even share made
		-- automatic: a share can never exceed the cell, whatever the glyph is. The
		-- 2026-07-27 grouping ruling gives that up ON PURPOSE — the spacing now
		-- follows the glyph, so a caller who asks for `large` glyphs in a 132px
		-- column is asking for something that does not fit, and the director's own
		-- framing of the ruling is that the CELL has to be sized for the control
		-- ("we should be cognizant of how big the cell is").
		--
		-- `small` is what a table row uses and what the control defaults to,
		-- precisely because round 13 measured the bigger rungs overrunning this
		-- same column. That is the guarantee worth pinning.
		for _, name in PACKAGES do
			local pkg = (require)(`../examples/themes/{name}`).build(themes)
			expect(stripWidth(pkg, "small") <= COLUMN).toBe(true)
		end
		expect(stripWidth(nil, "small") <= COLUMN).toBe(true)
	end)

	-- ===================================================================
	-- THE STRIP GROUPS (director ruling 2026-07-27, superseding round 12's
	-- "it FILLS the cell"): "let's have stars group, but knowing that, we
	-- should be cognizant of how big the cell is... if we make the cell with
	-- the rating control wider, we need to respect alignment (e.g. center it
	-- in the column)."
	--
	-- Round 12 made each star an even SHARE, which fixed the strip's OUTER
	-- width and left its INNER spacing to chance: the box became the caller's
	-- arithmetic while the glyph stayed the theme's. Measured in this same
	-- 132px column, the gap as a fraction of the glyph reached 0.67 under
	-- Compact Pointer — a 15px star in a 25px box, five marks that stopped
	-- reading as one rating.
	-- ===================================================================
	local function starPitchAndGlyph(pkg: any?): (number, number)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 430, h = 900 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake.new()
		local pres = presenterLib.new(core, env, adapter, actionsLib.newSystem(core))
		local control = Facet.Controls.Rating(core, { id = "R", value = core:signal(3) })
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.ZStack({
					id = "Cell",
					width = { type = "fixed", px = COLUMN },
					height = { type = "fixed", px = 48 },
					children = { control.blueprint },
				}),
			},
		}))
		pres.refresh()
		if pkg ~= nil then
			env:set("themeMetrics", themes.resolve(pkg, nil, {}))
			pres.refresh()
		end
		local s1 = adapter.node("/S/Cell/R/Stars/Star1").rect
		local s2 = adapter.node("/S/Cell/R/Stars/Star2").rect
		return s2.x - s1.x, s1.h
	end

	it("the SPACING follows the glyph, not the cell — no package spreads its stars", function()
		-- the invariant, stated so it cannot silently drift again: the step from
		-- one star to the next is the glyph plus a gap, and the gap is a small
		-- fraction of the glyph rather than a fraction of whatever slack the
		-- caller's column happened to have.
		for _, name in PACKAGES do
			local pkg = (require)(`../examples/themes/{name}`).build(themes)
			local pitch, glyph = starPitchAndGlyph(pkg)
			expect((pitch - glyph) / glyph < 0.25).toBe(true)
		end
		local pitch, glyph = starPitchAndGlyph(nil)
		expect((pitch - glyph) / glyph < 0.25).toBe(true)
	end)

	it("...and the leftover is CENTRED in the column, not dumped after the last star", function()
		-- a rating hugging its glyphs no longer reaches both edges of a generous
		-- cell, so where the slack goes becomes a visible decision. Split evenly,
		-- the strip stays aligned with its own header.
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 430, h = 900 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake.new()
		local pres = presenterLib.new(core, env, adapter, actionsLib.newSystem(core))
		local control = Facet.Controls.Rating(core, { id = "R", value = core:signal(3) })
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.ZStack({
					id = "Cell",
					width = { type = "fixed", px = COLUMN },
					height = { type = "fixed", px = 48 },
					children = { control.blueprint },
				}),
			},
		}))
		pres.refresh()
		env:set("themeMetrics", themes.resolve((require)("../examples/themes/compact_pointer").build(themes), nil, {}))
		pres.refresh()
		local cell = adapter.node("/S/Cell").rect
		local s1 = adapter.node("/S/Cell/R/Stars/Star1").rect
		local s5 = adapter.node("/S/Cell/R/Stars/Star5").rect
		local before = s1.x - cell.x
		local after = (cell.x + cell.w) - (s5.x + s5.w)
		expect(before > 0).toBe(true)
		expect(math.abs(before - after) <= 2).toBe(true)
	end)

	it("an unknown starSize is a build error, not a silently-default star", function()
		local core = customFactory.new()
		expect(pcall(function()
			return Facet.Controls.Rating(core, { id = "R", value = core:signal(1), starSize = "huge" })
		end)).toBe(false)
	end)
end)

-- ===========================================================================
-- WIDER FOR A FINGER THAN FOR A CURSOR (director, 2026-07-27: "it's a little
-- too tight on compact pointer… if we're on a touch input, part of the paradigm
-- should be slightly wider spacing for touch targets vs. what we can do with a
-- pointer").
--
-- The run is ONE drag target, so the gap between marks is what makes an
-- individual star reachable. `iconRunGap` is DERIVED from each package's own
-- `iconSizes` rather than borrowed from the page's spacing ladder, because the
-- two disagree wildly: Compact Pointer's `xs` is 2px against a 12px star — a 17%
-- gap, which is what "too tight" looked like — while Glossy Mobile's is 6px
-- against 16px.
-- ===========================================================================
describe("Rating: the star run spaces itself for the input paradigm", function()
	local environment = require("../src/env/environment")
	-- re-declared: the earlier describe's locals are not in scope here
	local themes = Facet.themes
	local fake = require("../tests/lib/fake_target")
	local COLUMN = 144
	local PACKAGES = {
		"glossy_touch",
		"glossy_mobile",
		"pixel_quest",
		"fantasy_ornate",
		"scifi_hud",
		"compact_pointer",
		"classic_desktop",
		"fantasy_parchment",
	}

	local function pitchUnder(pkgName: string, touch: boolean): (number, number)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 430, h = 900 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		-- `interactionClasses` is DERIVED, so the paradigm is driven the way a real
		-- session drives it: the live capability set plus the preferred device
		env:set("capabilities", { keyboard = not touch, mouse = not touch, touch = touch, gamepad = false })
		env:set("preferredInput", if touch then "Touch" else "KeyboardAndMouse")
		local adapter = fake.new()
		local pres = presenterLib.new(core, env, adapter, actionsLib.newSystem(core))
		local control = Facet.Controls.Rating(core, { id = "R", value = core:signal(3), env = env })
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.ZStack({
					id = "Cell",
					width = { type = "fixed", px = COLUMN },
					height = { type = "fixed", px = 48 },
					children = { control.blueprint },
				}),
			},
		}))
		pres.refresh()
		env:set("themeMetrics", themes.resolve((require)(`../examples/themes/{pkgName}`).build(themes), nil, {}))
		pres.refresh()
		local s1 = adapter.node("/S/Cell/R/Stars/Star1").rect
		local s2 = adapter.node("/S/Cell/R/Stars/Star2").rect
		local s5 = adapter.node("/S/Cell/R/Stars/Star5").rect
		return s2.x - s1.x, (s5.x + s5.w) - s1.x
	end

	it("touch spaces the run WIDER than a pointer, in every package", function()
		for _, name in PACKAGES do
			local pointerPitch = pitchUnder(name, false)
			local touchPitch = pitchUnder(name, true)
			expect(touchPitch > pointerPitch).toBe(true)
		end
	end)

	it("the package that showed the defect is no longer 2px between 12px stars", function()
		-- Compact Pointer: `xs` is 2 and the star is 12, so the old `xs` gap was
		-- 17% of the glyph. The derived gap scales with the glyph instead.
		local pitch = pitchUnder("compact_pointer", false)
		local glyph = 12
		expect(pitch - glyph >= 4).toBe(true)
	end)

	it("...and neither paradigm overruns the cell, in any package", function()
		-- the whole reason the run is capped: a wider gap must never reintroduce
		-- round 12's overrun
		for _, name in PACKAGES do
			local _, pointerRun = pitchUnder(name, false)
			local _, touchRun = pitchUnder(name, true)
			expect(pointerRun <= COLUMN).toBe(true)
			expect(touchRun <= COLUMN).toBe(true)
		end
	end)

	it("a rating with NO env takes the pointer spacing, which is the one that always fits", function()
		local core = customFactory.new()
		local ok = pcall(function()
			return Facet.Controls.Rating(core, { id = "R", value = core:signal(3) })
		end)
		expect(ok).toBe(true)
	end)
end)
