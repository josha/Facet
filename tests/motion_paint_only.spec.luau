--!strict
--[[ THE PAINT-ONLY LAW for the transitions round (2026-09-12), spec §3.1/§3.3.

	Every motion this round added — the TextInput invalid shake, the Button pop,
	the DisclosureGroup caret turn, the RadialMenu candidate lift and commit pop,
	and the ForEach stagger — rides the PRESENTATION channel: an offset, a scale,
	a rotation, an alpha. None of them is allowed to reach the solver. That is not
	a style preference, it is the whole reason a 30-row list can enter in sequence
	on a phone: a paint frame costs a transform write per moving node, and a solve
	frame costs a layout pass over the tree. The two invariants below are the ones
	a future control cannot quietly break, because both are COUNTED:

	  1. A MOTION FRAME MOVES NOTHING THE SOLVER OWNS. Not "the rect ends up where
	     it started" — a rect that moves and comes back has already paid for the
	     solve. Four counters, each blind to a different way of cheating:

	       rectWrites   `rect …` ops — every `setRect` the renderer issued at all,
	                    equal-valued ones included. This is the literal claim: the
	                    solver did not write geometry. It is the counter that
	                    catches a control whose motion dirties layout even when the
	                    layout happens to re-solve to the same numbers.
	       moved        a before/after census of every node's rect. The belt for a
	                    rect that changed without an op this target logged.
	       engineWrites the target's own Position/Size write mirror, diff-gated
	                    exactly as the live `applyRect` is: the number of pairs the
	                    engine would actually have been handed.
	       stretched    nodes whose `presentedSize` differs from their solved size.
	                    A presentation transform carries a `w`/`h` half and the live
	                    adapter composes it straight into the engine `Size` — so a
	                    motion CAN write Size without ever touching a rect, and the
	                    three counters above are all blind to it. This one is not.
	                    Sampled on EVERY frame and kept as the maximum, because a
	                    stretch that grows and relaxes inside the window is back at
	                    zero by the time the window closes — measured, not assumed:
	                    a `w`-half mutation in the transition coordinator's
	                    `writeEntry` passed a close-time census and failed this one.

	  2. IDLE IS FREE. After a motion settles, sixty more frames cost nothing: zero
	     clock steps, zero clock writes, zero transactions, zero rect writes, and
	     `activeCount()` back at its pre-motion baseline. `steps` is the sharp end
	     of that — `clock:step` returns before it counts one when nothing is active,
	     so a single spring that forgot to detach reads here as sixty.

	EVERY CASE MEASURES A WINDOW THAT CONTAINS ONLY MOTION. Where a motion is
	triggered by a real structural change (the disclosure mounting its content, the
	radial commit closing the ring, thirty rows arriving) that change's own solve is
	a LEGITIMATE layout event and is deliberately spent BEFORE the window opens —
	the law is about the frames that follow, which must be paint and nothing else.
	Each case also witnesses that its motion really ran inside the window it
	measured; a zero counter over a window where nothing moved proves nothing.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local worldLib = require("./lib/world")
local Facet = require("../src") :: any
local UI = Facet.UI
local FRAME = 1 / 60

local function rectCensus(w: any): { [string]: any }
	local out: { [string]: any } = {}
	for _, path in w.adapter.paths() do
		local node = w.adapter.node(path)
		local r = if node ~= nil then node.rect else nil
		if r ~= nil then
			out[path] = { x = r.x, y = r.y, w = r.w, h = r.h }
		end
	end
	return out
end

-- nodes the engine would be handed a Size for that is not their solved size —
-- the presentation transform's `w`/`h` half (see the header)
local function stretchedCount(w: any): number
	local n = 0
	for _, path in w.adapter.paths() do
		local node = w.adapter.node(path)
		local size, rect = node.presentedSize, node.rect
		if size ~= nil and rect ~= nil and (size.w ~= rect.w or size.h ~= rect.h) then
			n += 1
		end
	end
	return n
end

type Window = { ops: number, engineWrites: number, rects: { [string]: any }, stretched: number }

-- one presenter frame: advance the motion clock, then commit what it dirtied.
-- Authored presentation props (the caret's `rotation`, the button's `scale`)
-- reach the adapter through the ordinary reactive walk, so a `tick` without a
-- `refresh` beside it advances a spring nobody ever paints.
local function frame(w: any, window: Window?)
	w.pres.tick(FRAME)
	w.pres.refresh()
	if window ~= nil then
		window.stretched = math.max(window.stretched, stretchedCount(w))
	end
end

local function openWindow(w: any): Window
	return {
		ops = #w.adapter.ops(),
		engineWrites = w.adapter.engineWrites(),
		rects = rectCensus(w),
		stretched = stretchedCount(w),
	}
end

-- the four counters, one string each so a failure PRINTS the number it measured
-- rather than only "expected 0"
local function closeWindow(w: any, opened: Window): { string }
	local rectWrites = 0
	local ops = w.adapter.ops()
	for i = opened.ops + 1, #ops do
		if string.sub(ops[i], 1, 5) == "rect " then
			rectWrites += 1
		end
	end
	local moved = 0
	local after = rectCensus(w)
	for path, a in after do
		local b = opened.rects[path]
		if b == nil or a.x ~= b.x or a.y ~= b.y or a.w ~= b.w or a.h ~= b.h then
			moved += 1
		end
	end
	for path in opened.rects do
		if after[path] == nil then
			moved += 1
		end
	end
	return {
		`rectWrites={rectWrites}`,
		`moved={moved}`,
		`engineWrites={w.adapter.engineWrites() - opened.engineWrites}`,
		`stretched={math.max(opened.stretched, stretchedCount(w))}`,
	}
end

local QUIET = { "rectWrites=0", "moved=0", "engineWrites=0", "stretched=0" }

local function expectPaintOnly(w: any, opened: Window)
	local measured = closeWindow(w, opened)
	for i, counter in QUIET do
		expect(measured[i]).toBe(counter)
	end
end

describe("motion is paint-only and idle is free", function()
	--[[ THREE CONTROLS, ONE WINDOW. The shake is a timeline writing an `offset`,
		the pop is a spring writing a `scale`, the caret is a spring writing a
		`rotation` — three different motion primitives on three different
		presentation props, so a solver write from any one of them lands in the
		same four counters. The disclosure is EXPANDED before the window opens:
		mounting its content is a real layout change and is allowed to solve; what
		may not solve is the half-second of caret travel that follows it. ]]
	it("a shake, a pop and a caret turn move zero solved rects", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 }, ops = true })
		local invalid = w.core:signal(false)
		local expanded = w.core:signal(false)
		local hits = 0
		local input = Facet.Controls.TextInput(w.core, {
			id = "Name",
			value = w.core:signal(""),
			invalid = invalid,
			env = w.env,
			actionSystem = w.system,
		})
		local button = Facet.Controls.Button(w.core, {
			id = "Go",
			label = "Go",
			pop = true,
			onActivate = function()
				hits += 1
			end,
		})
		local group = Facet.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return UI.Text({ id = "Body", text = "x" })
			end,
		})
		w.present(UI.Screen({ id = "S", gap = 8, children = { input.blueprint, button.blueprint, group.blueprint } }))
		w.settle(5)
		-- the one legitimate solve: the content mounts and the group grows
		expanded:set(true)
		w.pres.refresh()
		local caretBefore = w.adapter.node("/S/Adv/Header/Caret").rotation or 0

		local opened = openWindow(w)
		invalid:set(true)
		w.adapter.tap("/S/Go")
		local peakScale, sawLeft, sawRight = 1, false, false
		for _ = 1, 30 do
			frame(w, opened)
			local field = w.adapter.node("/S/Name")
			local shift = field.presentedPosition.x - field.rect.x
			sawLeft = sawLeft or shift < 0
			sawRight = sawRight or shift > 0
			local go = w.adapter.node("/S/Go")
			if go.motionScaleInstance ~= nil then
				peakScale = math.max(peakScale, go.motionScaleInstance.scale)
			end
		end
		expectPaintOnly(w, opened)

		-- ...and all three motions really happened inside that window
		expect(`shook={sawLeft and sawRight}`).toBe("shook=true")
		expect(`popped={peakScale > 1.03}`).toBe("popped=true")
		expect(hits).toBe(1)
		local caretAfter = w.adapter.node("/S/Adv/Header/Caret").rotation or 0
		expect(`caretTurned={caretAfter - caretBefore > 45}`).toBe("caretTurned=true")
		expect(w.core:lastError()).toBeNil()
		w.overflowGuard()
		w.pres.dismiss(w.handle)
		input.dispose()
		button.dispose()
	end)

	--[[ THE RADIAL'S TWO WEDGE MOTIONS, in their own world because the ring needs
		a gamepad and room to open. The LIFT is measured whole; the POP is measured
		from the frame AFTER the commit, because committing closes the menu and the
		close is a structural event with its own honest solve. ]]
	it("a radial candidate lift and its commit pop move zero solved rects", function()
		local w = worldLib.new({
			viewport = { x = 0, y = 0, w = 800, h = 650 },
			capabilities = { pointer = true, keyboard = true, gamepad = true, touch = true },
			ops = true,
		})
		local items = {}
		for _, id in { "a", "b", "c", "d", "e", "f" } do
			table.insert(items, { id = id, label = string.upper(id) })
		end
		local menu = Facet.Controls.RadialMenu(w.core, { id = "Ctl", distribution = "even", items = items })
		w.present(UI.Screen({ id = "S", children = { menu.blueprint } }))
		w.settle(2)
		local launcher: string? = nil
		for _, path in w.adapter.paths() do
			if string.match(path, "/Launcher$") then
				launcher = path
			end
		end
		assert(launcher ~= nil, "the radial must paint a launcher")
		w.adapter.tap(launcher)
		w.settle(60) -- the ring blooms open and comes fully to rest

		local function sectorOf(id: string): any
			for _, sector in menu.dump().sectors do
				if sector.id == id then
					return sector
				end
			end
			error(`missing sector {id}`)
		end
		-- resolved once: a committed wedge is read while the ring is CLOSING, and
		-- the dump stops naming its focus path the moment the ring lets go of it
		local wedge = string.match(sectorOf("b").path, "^(.-/Visual)")
		local function wedgeScale(): number
			local node = w.adapter.node(wedge)
			return if node ~= nil and node.motionScaleInstance ~= nil then node.motionScaleInstance.scale else 1
		end

		-- THE LIFT: aim the stick at sector b and let the wedge stand up
		local opened = openWindow(w)
		local dump = menu.dump()
		local sector = sectorOf("b")
		local dx, dy = sector.x - dump.centerX, sector.y - dump.centerY
		local mag = math.sqrt(dx * dx + dy * dy)
		w.system.deviceAxis("Thumbstick1", dx / mag, dy / mag)
		for _ = 1, 30 do
			frame(w, opened)
		end
		expectPaintOnly(w, opened)
		local lifted = wedgeScale()
		expect(`candidate={menu.dump().candidate}`).toBe("candidate=:b")
		expect(`lifted={lifted > 1.02}`).toBe("lifted=true")

		-- THE POP: the commit's own frame is the ring's structural close; every
		-- frame after it is the velocity kick riding that same lift spring
		menu.api.select("b")
		frame(w)
		local popWindow = openWindow(w)
		local peak = 0
		for _ = 1, 30 do
			frame(w, popWindow)
			peak = math.max(peak, wedgeScale())
		end
		expectPaintOnly(w, popWindow)
		expect(`popped={peak > lifted and peak > 1.05}`).toBe("popped=true")
		expect(w.core:lastError()).toBeNil()
	end)

	--[[ THIRTY ROWS ENTERING IN SEQUENCE. The rows mount together — one solve,
		outside the window — and then wait their turn at the ABSENT alpha rather
		than being mounted one at a time, which is the whole point: a staggered
		list costs one layout pass, not thirty. ]]
	it("a 30-row staggered enter moves zero solved rects", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 1400 }, ops = true })
		local on = w.core:signal(false)
		local rows = {}
		for i = 1, 30 do
			rows[i] = { id = `r{i}` }
		end
		local items = w.core:signal(rows)
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.When({
					id = "Gate",
					condition = on,
					thenView = function()
						return UI.ForEach({
							id = "List",
							items = items,
							key = function(row: any): string
								return row.id
							end,
							transition = { enter = "fade", stagger = 0.02 },
							row = function(row: any)
								return UI.ZStack({
									id = "Row",
									canvasGroup = true,
									children = { UI.Text({ id = "T", text = row.id }) },
								})
							end,
						})
					end,
				}),
			},
		}))
		w.settle(3)
		-- the one legitimate solve: thirty rows mount and are placed
		on:set(true)
		w.pres.refresh()
		local last = "/S/Gate/then/List/[r30]/Row"
		expect(`heldAbsent={w.adapter.node(last).canvasGroupInstance.groupTransparency}`).toBe("heldAbsent=1")

		local opened = openWindow(w)
		for _ = 1, 90 do
			frame(w, opened)
		end
		expectPaintOnly(w, opened)
		expect(`arrived={w.adapter.node(last).canvasGroupInstance.groupTransparency}`).toBe("arrived=0")
		expect(`atRest={w.pres.motionClock:activeCount()}`).toBe("atRest=0")
		w.overflowGuard()
	end)

	--[[ IDLE IS FREE. The same three controls, all three motions fired at once,
		then two windows: the motion window — which must show the clock doing real
		work, or the second window proves nothing — and sixty idle frames after it,
		which must cost literally nothing. ]]
	it("a settled surface writes nothing across 60 idle frames", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 }, ops = true })
		local invalid = w.core:signal(false)
		local expanded = w.core:signal(false)
		local input = Facet.Controls.TextInput(w.core, {
			id = "Name",
			value = w.core:signal(""),
			invalid = invalid,
			env = w.env,
			actionSystem = w.system,
		})
		local button = Facet.Controls.Button(w.core, {
			id = "Go",
			label = "Go",
			pop = true,
			onActivate = function() end,
		})
		local group = Facet.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return UI.Text({ id = "Body", text = "x" })
			end,
		})
		w.present(UI.Screen({ id = "S", gap = 8, children = { input.blueprint, button.blueprint, group.blueprint } }))
		w.settle(5)
		local baseline = w.pres.motionClock:activeCount()
		local atRest = w.pres.motionClock:stats()

		invalid:set(true)
		expanded:set(true)
		w.adapter.tap("/S/Go")
		local peakActive = 0
		for _ = 1, 120 do
			frame(w)
			peakActive = math.max(peakActive, w.pres.motionClock:activeCount())
		end
		local settled = w.pres.motionClock:stats()
		-- the motion window did real work, which is what makes the idle window a claim
		expect(`ranSteps={settled.steps > atRest.steps}`).toBe("ranSteps=true")
		expect(`ranWrites={settled.writes > atRest.writes}`).toBe("ranWrites=true")
		expect(`ranActive={peakActive > baseline}`).toBe("ranActive=true")

		local opened = openWindow(w)
		for _ = 1, 60 do
			frame(w, opened)
		end
		local idle = w.pres.motionClock:stats()
		expect(`idleSteps={idle.steps - settled.steps}`).toBe("idleSteps=0")
		expect(`idleWrites={idle.writes - settled.writes}`).toBe("idleWrites=0")
		expect(`idleTransactions={idle.transactions - settled.transactions}`).toBe("idleTransactions=0")
		expect(`active={w.pres.motionClock:activeCount()}`).toBe(`active={baseline}`)
		expectPaintOnly(w, opened)
		expect(w.pres.motionClock:lastError()).toBeNil()
		expect(w.core:lastError()).toBeNil()
		w.overflowGuard()
		w.pres.dismiss(w.handle)
		input.dispose()
		button.dispose()
	end)
end)
