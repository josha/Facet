--!strict
local harness = require("./lib/harness")
--[[ THE PAINT-ONLY LAW for the transitions round (2026-09-12), spec §3.1/§3.3.

	Every motion this round added — the TextInput invalid shake, the Button pop,
	the DisclosureGroup caret turn, the RadialMenu candidate lift and commit pop,
	and the ForEach stagger — rides the PRESENTATION channel: an offset, a scale,
	a rotation, an alpha. None of them is allowed to reach the solver. That is not
	a style preference, it is the whole reason a 30-row list can enter in sequence
	on a phone: a paint frame costs a transform write per moving node, and a solve
	frame costs a layout pass over the tree. The two invariants below are the ones
	a future control cannot quietly break, because both are COUNTED:

	  1. A MOTION FRAME DOES NOT RUN THE SOLVER. The counter that carries that
	     claim is `solves`, and it has to be, because EVERY OTHER COUNTER IN THIS
	     FILE IS DIFF-GATED BY THE FRAMEWORK:

	       `src/render/rect_pass.luau:109` calls `adapter.setRect` — and bumps
	       `stats.rectWrites` — only `if not rectsEqual(lastRects[path], entry.rect)`.
	       `src/render/translate_lane.luau:349` is the same shape. The fake
	       target's `engineWrites` (`tests/lib/fake_target.luau:837-844`) gates on
	       its own last-written pair. So a control that forces a full re-solve on
	       every motion frame, whose geometry happens to net UNCHANGED, reads zero
	       on rectWrites, zero on moved, zero on engineWrites and zero on
	       stretched, and would sail through a gate built only from those.
	       `tests/host_rect_identity.spec.luau:195-221` is that exact shape written
	       down on purpose: `solves=5 … rectWrites=0`.

	     The other four are still here, because each catches something `solves`
	     alone does not — a solve that DOES move something, and how much:

	       rectWrites   the framework's own count of rects it actually wrote.
	       moved        a before/after census of every node's solved box
	                    (`tests/lib/rect_census.luau`), the belt for a rect that
	                    changed without the framework counting it.
	       engineWrites the target's diff-gated Position/Size mirror: the pairs the
	                    engine would really have been handed.
	       stretched    nodes whose `presentedSize` differs from their solved size.
	                    A presentation transform carries a `w`/`h` half and the live
	                    adapter composes it straight into the engine `Size` — so a
	                    motion CAN write Size without touching a rect or a solve,
	                    and every other counter here is blind to it. Sampled on
	                    EVERY frame and kept as the maximum, because a stretch that
	                    grows and relaxes inside the window is back at zero by the
	                    time the window closes (measured: a `w`-half mutation in the
	                    transition coordinator passed a close-time census).

	  2. IDLE IS FREE. After a motion settles, sixty more frames cost nothing: zero
	     clock steps, zero clock writes, zero transactions, zero solves, and
	     `activeCount()` back at its pre-motion baseline — asserted both before the
	     idle window opens and after it closes. `steps` is the sharp end of that:
	     `clock:step` returns before it counts one when nothing is active
	     (`src/motion/clock.luau:198`), so one spring that forgot to detach reads
	     here as sixty.

	EVERY CASE MEASURES A WINDOW THAT CONTAINS ONLY MOTION, AND ONE MOTION EACH, so
	a red counter names the control. Where a motion is triggered by a real state
	change (the disclosure mounting its content, a pointer naming a new candidate,
	thirty rows arriving) that change's own solve is a LEGITIMATE layout event and
	is spent BEFORE the window opens — the law is about the frames that follow.
	Each case also witnesses that its motion really ran inside the window it
	measured; a zero counter over a window where nothing moved proves nothing.

	ONE FIXTURE TRAP, MEASURED AND WORTH KEEPING (2026-09-13). The radial cases
	drive the candidate with a POINTER preview, not with a held thumbstick. A
	held `deviceAxis` is a REPEATING input: the first draft of this file held the
	stick for the whole window and read `solves=2` on the lift and `solves=5` on
	the pop — one solve at frame 24 and then one every sixth frame after it, which
	is 0.4 s of repeat delay followed by a 0.1 s interval, re-setting the candidate
	and re-emitting six props each time. Nothing to do with the lift. The ring at
	rest solves ZERO across sixty frames, and the discrete pointer route solves
	zero through the whole lift, which is what settled it. A motion gate driven by
	a held input measures the input. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local worldLib = require("./lib/harness_world")
local rectCensus = require("./lib/rect_census")
local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local UI = harness.UI
local FRAME = 1 / 60

-- nodes the engine would be handed a Size for that is not their solved size —
-- the presentation transform's `w`/`h` half (see the header)
local function stretchedCount(w: any, revealPath: string?): number
	local n = 0
	for _, path in w.adapter.paths() do
		local node = w.adapter.node(path)
		local size, rect = node.presentedSize, node.rect
		if path == revealPath and size ~= nil and rect ~= nil then
			-- Only the disclosure's clip may shrink; its children, width and solved
			-- geometry remain subject to the original paint-only checks.
			expect(size.w).toBe(rect.w)
			expect(size.h >= 0 and size.h <= rect.h).toBe(true)
		elseif size ~= nil and rect ~= nil and (size.w ~= rect.w or size.h ~= rect.h) then
			n += 1
		end
	end
	return n
end

type Window = {
	label: string,
	solves: number,
	rectWrites: number,
	engineWrites: number,
	rects: rectCensus.Census,
	stretched: number,
	revealPath: string?,
}

-- `label` names the control, so a red counter reads "TextInput shake solves=30"
-- rather than "solves=30"
local function openWindow(w: any, label: string, revealPath: string?): Window
	local stats = w.controller.stats()
	return {
		label = label,
		solves = stats.solves,
		rectWrites = stats.rectWrites,
		engineWrites = w.adapter.engineWrites(),
		rects = rectCensus.of(w.adapter),
		stretched = stretchedCount(w, revealPath),
		revealPath = revealPath,
	}
end

-- one presenter frame: advance the motion clock, then commit what it dirtied.
-- Authored presentation props (the caret's `rotation`, the button's `scale`)
-- reach the adapter through the ordinary reactive walk, so a `tick` without a
-- `refresh` beside it advances a spring nobody ever paints.
local function frame(w: any, window: Window?)
	w.pres.tick(FRAME)
	w.pres.refresh()
	if window ~= nil then
		window.stretched = math.max(window.stretched, stretchedCount(w, window.revealPath))
	end
end

local COUNTERS = { "solves", "rectWrites", "moved", "engineWrites", "stretched" }

-- every counter is asserted as its own labelled string, so a failure PRINTS the
-- number it measured and the control it measured it on
local function expectPaintOnly(w: any, opened: Window)
	local stats = w.controller.stats()
	local measured = {
		stats.solves - opened.solves,
		stats.rectWrites - opened.rectWrites,
		rectCensus.movedCount(opened.rects, rectCensus.of(w.adapter)),
		w.adapter.engineWrites() - opened.engineWrites,
		math.max(opened.stretched, stretchedCount(w, opened.revealPath)),
	}
	for i, name in COUNTERS do
		expect(`{opened.label} {name}={measured[i]}`).toBe(`{opened.label} {name}=0`)
	end
end

--[[ ONE SCREEN CARRYING ALL THREE Tier-2 CONTROLS, built per case so each case
	drives exactly one of them. The shake is a timeline writing an `offset`, the
	pop is a spring writing a `scale`, the caret is a spring writing a `rotation`:
	three different motion primitives on three different presentation props. ]]
local function controlsWorld()
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
	local invalid = Compose.cell(false)
	local expanded = Compose.cell(false)
	local hits = 0
	local input = harness.Controls.TextInput(w.core, {
		id = "Name",
		value = Compose.cell(""),
		invalid = invalid,
		env = w.env,
		actionSystem = w.system,
	})
	local button = harness.Controls.Button(w.core, {
		id = "Go",
		label = "Go",
		pop = true,
		onActivate = function()
			hits += 1
		end,
	})
	local group = harness.Controls.DisclosureGroup(w.core, {
		id = "Adv",
		label = "Advanced",
		expanded = expanded,
		content = function()
			return UI.Text({ id = "Body", text = "x" })
		end,
	})
	w.present(UI.Screen({ id = "S", gap = 8, children = { input.blueprint, button.blueprint, group.blueprint } }))
	w.settle(5)
	return {
		w = w,
		invalid = invalid,
		expanded = expanded,
		dispose = function()
			w.pres.dismiss(w.handle)
			input.dispose()
			button.dispose()
		end,
		hitCount = function(): number
			return hits
		end,
	}
end

describe("motion is paint-only and idle is free", function()
	it("the TextInput invalid shake moves nothing the solver owns", function()
		local f = controlsWorld()
		local w = f.w
		local opened = openWindow(w, "TextInput shake")
		f.invalid:set(true)
		local sawLeft, sawRight = false, false
		for _ = 1, 30 do
			frame(w, opened)
			local node = w.adapter.node("/S/Name")
			local shift = node.presentedPosition.x - node.rect.x
			sawLeft = sawLeft or shift < 0
			sawRight = sawRight or shift > 0
		end
		expectPaintOnly(w, opened)
		-- ...over a window the shake really crossed, both ways and back to rest
		expect(`TextInput shook={sawLeft and sawRight}`).toBe("TextInput shook=true")
		local rest = w.adapter.node("/S/Name")
		expect(`TextInput atRest={rest.presentedPosition.x - rest.rect.x}`).toBe("TextInput atRest=0")
		expect(w.core.lastError()).toBeNil()
		w.overflowGuard()
		f.dispose()
	end)

	it("the Button pop moves nothing the solver owns", function()
		local f = controlsWorld()
		local w = f.w
		local opened = openWindow(w, "Button pop")
		w.adapter.tap("/S/Go")
		local peakScale = 1
		for _ = 1, 30 do
			frame(w, opened)
			local go = w.adapter.node("/S/Go")
			if go.motionScaleInstance ~= nil then
				peakScale = math.max(peakScale, go.motionScaleInstance.scale)
			end
		end
		expectPaintOnly(w, opened)
		expect(`Button popped={peakScale > 1.03}`).toBe("Button popped=true")
		expect(`Button activations={f.hitCount()}`).toBe("Button activations=1")
		expect(w.core.lastError()).toBeNil()
		w.overflowGuard()
		f.dispose()
	end)

	it("the DisclosureGroup caret turn moves nothing the solver owns", function()
		local f = controlsWorld()
		local w = f.w
		-- the one legitimate solve: the content mounts and the group grows. The
		-- half-second of caret travel that FOLLOWS it is what may not solve.
		f.expanded:set(true)
		w.pres.refresh()
		local before = w.adapter.node("/S/Adv/Header/Caret").rotation or 0

		local revealPath = "/S/Adv/Reveal"
		local clip = w.adapter.node(revealPath)
		expect(clip.presentedSize.h < clip.rect.h).toBe(true)
		local opened = openWindow(w, "DisclosureGroup caret", revealPath)
		for _ = 1, 30 do
			frame(w, opened)
		end
		expectPaintOnly(w, opened)
		local after = w.adapter.node("/S/Adv/Header/Caret").rotation or 0
		expect(`DisclosureGroup caretTurned={after - before > 45}`).toBe("DisclosureGroup caretTurned=true")
		expect(clip.presentedSize.h).toBe(clip.rect.h)
		expect(w.core.lastError()).toBeNil()
		w.overflowGuard()
		f.dispose()
	end)

	--[[ THE RADIAL'S TWO WEDGE MOTIONS, in their own world because the ring needs
		room and a pointer. `completion = "stay"` so the COMMIT keeps the ring open:
		the pop is then a motion with no structural event anywhere near it, and the
		window can open before the pop's very first integration frame instead of
		after a close that would have had to be spent first. ]]
	local function radialWorld()
		local w = worldLib.new({
			viewport = { x = 0, y = 0, w = 800, h = 650 },
			capabilities = { pointer = true, keyboard = true, gamepad = true, touch = true },
		})
		local items = {}
		for _, id in { "a", "b", "c", "d", "e", "f" } do
			table.insert(items, { id = id, label = string.upper(id) })
		end
		local menu = harness.Controls.RadialMenu(w.core, {
			id = "Ctl",
			distribution = "even",
			completion = "stay",
			items = items,
		})
		w.present(UI.Screen({ id = "S", children = { menu.blueprint } }))
		w.settle(2)
		local launcher: string? = nil
		for _, path in w.adapter.paths() do
			if string.match(path, "/Launcher$") then
				launcher = path
			end
		end
		assert(launcher ~= nil, "the radial must paint a launcher")
		local centre = menu.dump()
		-- a pointer DOWN on the launcher opens the ring and holds the preview, so
		-- the candidate is named by a discrete move rather than by a repeating axis
		w.adapter.pointerDown(launcher, centre.centerX, centre.centerY, "mouse")
		w.settle(60) -- the ring blooms open and comes fully to rest

		local function sectorOf(id: string): any
			for _, sector in menu.dump().sectors do
				if sector.id == id then
					return sector
				end
			end
			error(`missing sector {id}`)
		end
		-- resolved once: a committed wedge is read after the choice, and the dump
		-- stops naming its focus path the moment the ring lets go of it
		local wedge = string.match(sectorOf("b").path, "^(.-/Visual)")
		local function wedgeScale(): number
			local node = w.adapter.node(wedge)
			return if node ~= nil and node.motionScaleInstance ~= nil then node.motionScaleInstance.scale else 1
		end
		return w, menu, sectorOf, wedgeScale
	end

	it("the RadialMenu candidate lift moves nothing the solver owns", function()
		local w, menu, sectorOf, wedgeScale = radialWorld()
		local sector = sectorOf("b")
		-- the one legitimate solve: a new candidate is a state change
		w.adapter.pointerMove(sector.x, sector.y)
		w.pres.refresh()
		expect(`RadialMenu candidate={menu.dump().candidate}`).toBe("RadialMenu candidate=:b")

		local opened = openWindow(w, "RadialMenu lift")
		for _ = 1, 30 do
			frame(w, opened)
		end
		expectPaintOnly(w, opened)
		expect(`RadialMenu lifted={wedgeScale() > 1.02}`).toBe("RadialMenu lifted=true")
		expect(w.core.lastError()).toBeNil()
	end)

	it("the RadialMenu commit pop moves nothing the solver owns", function()
		local w, menu, sectorOf, wedgeScale = radialWorld()
		local sector = sectorOf("b")
		w.adapter.pointerMove(sector.x, sector.y)
		w.settle(40) -- the lift is finished and at rest before the pop is measured
		local lifted = wedgeScale()

		-- `completion = "stay"`: the kick is seeded and NOTHING structural follows,
		-- so the window opens before the pop's first integration frame
		local opened = openWindow(w, "RadialMenu pop")
		menu.api.select("b")
		local peak = 0
		for _ = 1, 30 do
			frame(w, opened)
			peak = math.max(peak, wedgeScale())
		end
		expectPaintOnly(w, opened)
		expect(`RadialMenu popped={peak > lifted and peak > 1.05}`).toBe("RadialMenu popped=true")
		expect(`RadialMenu stillOpen={menu.dump().open}`).toBe("RadialMenu stillOpen=true")
		expect(w.core.lastError()).toBeNil()
	end)

	--[[ IDLE IS FREE. All three control motions fired at once, then two windows:
		the motion window — which must show the clock doing real work, or the second
		window proves nothing — and sixty idle frames after it, which must cost
		literally nothing. ]]
	it("a settled surface writes nothing across 60 idle frames", function()
		local f = controlsWorld()
		local w = f.w
		local baseline = w.pres.motionClock:activeCount()
		local caretBefore = w.adapter.node("/S/Adv/Header/Caret").rotation or 0

		f.invalid:set(true)
		f.expanded:set(true)
		w.adapter.tap("/S/Go")
		local peakScale = 1
		for _ = 1, 120 do
			frame(w)
			local go = w.adapter.node("/S/Go")
			if go.motionScaleInstance ~= nil then
				peakScale = math.max(peakScale, go.motionScaleInstance.scale)
			end
		end
		local settled = w.pres.motionClock:stats()
		local caretAfter = w.adapter.node("/S/Adv/Header/Caret").rotation or 0
		-- the motion window did real work, which is what makes the idle window a claim
		expect(`idle ranPop={peakScale > 1.03}`).toBe("idle ranPop=true")
		expect(`idle ranCaret={caretAfter - caretBefore > 45}`).toBe("idle ranCaret=true")
		-- ...and every motion has detached itself BEFORE the idle window opens, so
		-- a zero inside it cannot be a window that was never armed
		expect(`idle activeBefore={w.pres.motionClock:activeCount()}`).toBe(`idle activeBefore={baseline}`)

		local opened = openWindow(w, "idle")
		for _ = 1, 60 do
			frame(w, opened)
		end
		local idle = w.pres.motionClock:stats()
		expect(`idle steps={idle.steps - settled.steps}`).toBe("idle steps=0")
		expect(`idle writes={idle.writes - settled.writes}`).toBe("idle writes=0")
		expect(`idle transactions={idle.transactions - settled.transactions}`).toBe("idle transactions=0")
		expect(`idle activeAfter={w.pres.motionClock:activeCount()}`).toBe(`idle activeAfter={baseline}`)
		expectPaintOnly(w, opened)
		expect(w.pres.motionClock:lastError()).toBeNil()
		expect(w.core.lastError()).toBeNil()
		w.overflowGuard()
		f.dispose()
	end)
end)
