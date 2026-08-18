--!strict
-- Modal outside-tap dismissal — the two-zone spec
-- (docs/research/2026-07-21-modal-dismissal-spec.md; ADR-0014 §Drive-F1).
--
-- Zone A (no dismiss, forgiveness): the top modal's PAINTED panel rect(s) ⊕ a
-- 24px forgiveness ring (space.l token) ∪ every focusable's 44px hit rect.
-- Invisible containers contribute NOTHING; a VISIBLE fullscreen takeover has no
-- outside. Zone B (dismiss): a presenter-synthesized full-viewport scrim/catcher
-- beneath the top modal — so EVERY tap now hits something (closes Drive-F1's
-- empty-space gap). Dismissal resolves through the SAME path as Cancel/ButtonB.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")

local FILL = { type = "fill", weight = 1 }
local function FIXED(px: number)
	return { type = "fixed", px = px }
end

local function harness()
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	return core, env, system, adapter, pres
end

-- a base screen with a recorded button so "clickthrough" is observable
local function presentBase(pres: any): { string }
	local baseHits: { string } = {}
	local base = Facet.UI.Screen({
		id = "Base",
		children = {
			Facet.UI.Button({
				id = "B",
				label = "B",
				onActivate = function(path: string)
					table.insert(baseHits, path)
				end,
			}),
		},
	})
	pres.present(base)
	return baseHits
end

-- a small painted panel modal pinned top-left (surface="raised" => the ROOT is
-- the painted panel rect, so Zone geometry is deterministic)
local function paintedModal(id: string?)
	return Facet.UI.Screen({
		id = id or "M",
		surface = "raised",
		width = FIXED(200),
		height = FIXED(120),
		padding = 16,
		children = { Facet.UI.Button({ id = "OK", label = "OK" }) },
	})
end

-- ===========================================================================
-- (1) Drive-F1: a tap on truly empty viewport space dismisses the top modal.
-- ===========================================================================
describe("modal dismissal: empty-space tap dismisses (Drive-F1 scrim catcher)", function()
	it("tapping the scrim far outside the panel dismisses the top modal", function()
		local _, _, _, adapter, pres = harness()
		presentBase(pres)
		local bp = paintedModal()
		pres.presentModal(bp)
		pres.refresh()
		expect(pres.depth()).toBe(2)
		local scrim = pres.topScrimPath()
		expect(scrim).never().toBeNil()
		-- (500,400) is empty space — no rendered node was there before the scrim
		adapter.tap(scrim, { x = 500, y = 400 })
		expect(pres.depth()).toBe(1)
	end)
end)

-- ===========================================================================
-- (1b) The catcher is NOT a decoration surface (ADR-0020 R9, live-found P5).
-- ===========================================================================
describe("modal dismissal: the synthesized catcher is never a skin target", function()
	it("declares chrome_slots.NO_SLOT, so no package can paint over the screen it guards", function()
		-- The catcher is a full-viewport Button whose whole job is to be invisible
		-- and swallow a tap. Nothing generic can tell it apart from a real button:
		-- `classify` sees a Button and answers `control`, so under any image-driven
		-- package it wore that package's button plate AT FULL SCREEN SIZE and the
		-- surface beneath disappeared. Found live under the P5 reference packages;
		-- this is the headless half so it cannot come back.
		local chrome_slots = require("../src/tokens/chrome_slots")
		local _, _, _, adapter, pres = harness()
		presentBase(pres)
		pres.presentModal(paintedModal())
		pres.refresh()
		local scrim = pres.topScrimPath()
		expect(scrim).never().toBeNil()
		-- APPLIED, not merely declared: the hint has to travel blueprint -> mount
		-- -> renderer -> adapter, and `decorationHint` is the fourth argument the
		-- adapter received for this node
		local node = adapter.node(scrim :: string)
		expect(node ~= nil).toBe(true)
		expect(node.decorationHint ~= nil and node.decorationHint.slot).toBe(chrome_slots.NO_SLOT)
		-- ...and the classifier — the part that actually decides paint — agrees
		expect(chrome_slots.classify({ class = "Button", hint = chrome_slots.NO_SLOT })).toBeNil()
		-- while the SAME node without the hint is what the defect looked like
		expect(chrome_slots.classify({ class = "Button" })).toBe("control")
	end)
end)

-- ===========================================================================
-- (2)/(3) Forgiveness ring: within 24px of the edge = no dismiss; beyond = yes.
-- ===========================================================================
describe("modal dismissal: 24px forgiveness ring around the painted panel", function()
	it("a tap within 24px of the panel edge does NOT dismiss (near-miss forgiveness)", function()
		local _, _, _, adapter, pres = harness()
		presentBase(pres)
		local h = pres.presentModal(paintedModal())
		pres.refresh()
		local r = h.controller.rectOf("/M") -- painted panel rect (0,0,200,120)
		expect(r).never().toBeNil()
		-- 10px to the right of the panel's right edge, vertically centered
		adapter.tap(pres.topScrimPath(), { x = r.x + r.w + 10, y = r.y + r.h / 2 })
		expect(pres.depth()).toBe(2) -- still open: inside the 24px ring
	end)

	it("a tap beyond the 24px ring dismisses", function()
		local _, _, _, adapter, pres = harness()
		presentBase(pres)
		local h = pres.presentModal(paintedModal())
		pres.refresh()
		local r = h.controller.rectOf("/M")
		-- 30px to the right: past the 24px ring
		adapter.tap(pres.topScrimPath(), { x = r.x + r.w + 30, y = r.y + r.h / 2 })
		expect(pres.depth()).toBe(1)
	end)
end)

-- ===========================================================================
-- (4) An INVISIBLE fullscreen modal root does not swallow — only painted counts.
-- ===========================================================================
describe("modal dismissal: an invisible fullscreen root contributes nothing to Zone A", function()
	it("a tap outside the small painted panel still dismisses, despite the fill root", function()
		local _, _, _, adapter, pres = harness()
		presentBase(pres)
		-- fill root, TRANSPARENT (no surface); a small VISIBLE panel inside it
		local modal = Facet.UI.Screen({
			id = "M",
			width = FILL,
			height = FILL,
			children = {
				Facet.UI.VStack({
					id = "Panel",
					surface = "raised",
					width = FIXED(200),
					height = FIXED(120),
					children = { Facet.UI.Button({ id = "OK", label = "OK" }) },
				}),
			},
		})
		local h = pres.presentModal(modal)
		pres.refresh()
		local p = h.controller.rectOf("/M/Panel")
		expect(p).never().toBeNil()
		-- deep inside the fill root's geometry but well outside the painted panel
		adapter.tap(pres.topScrimPath(), { x = p.x + p.w + 200, y = p.y + p.h + 200 })
		expect(pres.depth()).toBe(1) -- dismissed: the invisible root did not swallow
	end)
end)

-- ===========================================================================
-- (5) A VISIBLE fullscreen takeover has no outside — nothing dismisses by tap.
-- ===========================================================================
describe("modal dismissal: a visible fullscreen takeover has no outside", function()
	it("a tap anywhere lands in Zone A (the painted fullscreen panel) — no dismiss", function()
		local _, _, _, adapter, pres = harness()
		presentBase(pres)
		local modal = Facet.UI.Screen({
			id = "M",
			surface = "raised", -- PAINTED and fill: the panel is the whole viewport
			width = FILL,
			height = FILL,
			children = { Facet.UI.Button({ id = "OK", label = "OK" }) },
		})
		pres.presentModal(modal)
		pres.refresh()
		adapter.tap(pres.topScrimPath(), { x = 400, y = 300 }) -- dead center
		expect(pres.depth()).toBe(2) -- fullscreen dialog: no outside exists
	end)
end)

-- ===========================================================================
-- (6) outsideTapCancel=false SWALLOWS: no dismiss, and no reach to lower surfaces.
-- ===========================================================================
describe("modal dismissal: outsideTapCancel=false is a true barrier (swallow)", function()
	it("a Zone-B scrim tap neither dismisses nor clicks through", function()
		local _, _, _, adapter, pres = harness()
		local baseHits = presentBase(pres)
		pres.presentModal(paintedModal("M"), { outsideTapCancel = false })
		pres.refresh()
		adapter.tap(pres.topScrimPath(), { x = 500, y = 400 }) -- Zone B
		expect(pres.depth()).toBe(2) -- NOT dismissed
		expect(#baseHits).toBe(0) -- NOT clicked through
	end)

	it("a direct tap on a lower node (path-outside) is also swallowed", function()
		local _, _, _, adapter, pres = harness()
		local baseHits = presentBase(pres)
		pres.presentModal(paintedModal("M"), { outsideTapCancel = false })
		pres.refresh()
		adapter.tap("/Base/B") -- the barrier eats it: spec §3.4 change vs legacy
		expect(pres.depth()).toBe(2)
		expect(#baseHits).toBe(0)
	end)
end)

-- ===========================================================================
-- (7) Stacked modals: an outside tap pops only the top modal (one level/tap).
-- ===========================================================================
describe("modal dismissal: stacked modals pop only the top", function()
	it("an empty-space scrim tap pops M2, then M1, one per tap", function()
		local _, _, _, adapter, pres = harness()
		presentBase(pres)
		pres.presentModal(paintedModal("M1"))
		pres.presentModal(paintedModal("M2"))
		pres.refresh()
		expect(pres.depth()).toBe(3)
		adapter.tap(pres.topScrimPath(), { x = 500, y = 400 })
		expect(pres.depth()).toBe(2) -- M2 popped
		adapter.tap(pres.topScrimPath(), { x = 500, y = 400 })
		expect(pres.depth()).toBe(1) -- M1 popped
	end)
end)

-- ===========================================================================
-- (8) The scrim is NOT focusable and absent from navigation groups.
-- ===========================================================================
describe("modal dismissal: the scrim is non-focusable and absent from navigation", function()
	it("focus stays inside the modal and never lands on the scrim", function()
		local _, _, system, _, pres = harness()
		presentBase(pres)
		local modal = Facet.UI.Screen({
			id = "M",
			surface = "raised",
			children = {
				Facet.UI.Button({ id = "Confirm", label = "Delete" }),
				Facet.UI.Button({ id = "Cancel", label = "Cancel" }),
			},
		})
		pres.presentModal(modal)
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/M/Confirm")
		-- navigate the whole ring: it must never reach the scrim catcher path
		local scrimRoot = "/__scrim__"
		for _ = 1, 4 do
			system.deviceKey("Down", true)
			system.deviceKey("Down", false)
			local f = pres.focus.focused:get()
			expect(f).never().toBeNil()
			expect(string.sub(f :: string, 1, #scrimRoot) == scrimRoot).toBe(false)
		end
	end)

	it("the scrim root's DisplayOrder is beneath the top modal", function()
		local _, _, _, adapter, pres = harness()
		presentBase(pres)
		pres.presentModal(paintedModal("M"))
		pres.refresh()
		expect(adapter.rootDisplayOrder("__scrim__")).never().toBeNil()
		expect(adapter.rootDisplayOrder("__scrim__") < adapter.rootDisplayOrder("M")).toBe(true)
	end)
end)

-- ===========================================================================
-- scrim="none": transparent-but-catching popover — still dismisses; no dim.
-- ===========================================================================
describe('modal dismissal: scrim="none" is transparent but still catches', function()
	it("a Zone-B tap still dismisses, and the catcher renders without a scrim surface", function()
		local _, _, _, adapter, pres = harness()
		presentBase(pres)
		pres.presentModal(paintedModal("M"), { scrim = "none" })
		pres.refresh()
		-- "plain", not nil (live-found P5): a Button with NO surface still
		-- classifies as `control`, so the invisible catcher wore the installed
		-- package's solid control colour across the whole viewport. `plain` is the
		-- suppressed surface `sheet_model.classifyTags` already paints nothing for
		-- — no fill, no interactive tag, no corner, no stroke — which is what
		-- "transparent but still catching" was always supposed to mean.
		expect(adapter.node("/__scrim__/catcher").props.surface).toBe("plain")
		local sheet_model = require("../src/tokens/sheet_model")
		local tags = sheet_model.classifyTags({ surface = "plain", interactive = true, pointerLive = true })
		expect(next(tags)).toBeNil() -- nothing to paint and nothing to hover
		-- ...against what the old shape produced, which is the defect itself
		expect(sheet_model.classifyTags({ interactive = true })["luau-interactive"]).toBe(true)
		adapter.tap(pres.topScrimPath(), { x = 500, y = 400 })
		expect(pres.depth()).toBe(1) -- still catches + dismisses
	end)
end)

-- ===========================================================================
-- (9) Registry neutrality across open/dismiss churn WITH the scrim.
-- ===========================================================================
describe("modal dismissal: scrim open/dismiss churn is registry-neutral", function()
	it("live node count returns to baseline after churn (scrim disposed with the modal)", function()
		local _, _, _, adapter, pres = harness()
		presentBase(pres)
		local baseline = adapter.liveCount()
		for _ = 1, 10 do
			local h = pres.presentModal(paintedModal("M"))
			pres.refresh()
			expect(adapter.liveCount() > baseline).toBe(true) -- scrim + panel added
			pres.dismiss(h)
		end
		expect(adapter.liveCount()).toBe(baseline)
		expect(pres.topScrimPath()).toBeNil() -- no scrim once no modal remains
	end)
end)

-- ===========================================================================
-- (10) `cancelPolicy` — the MANDATORY surface (parallel-sponsor S1 role pick).
--
-- A modal whose choice has no legal "not now" must not vanish on ButtonB. The
-- opt is deliberately ORTHOGONAL to `outsideTapCancel` (the pointer path) and
-- sits AFTER the contribution offer, so a control inside a mandatory modal
-- keeps its own cancel. Default is "dismiss", i.e. every pre-existing surface
-- behaves exactly as before.
-- ===========================================================================
describe("modal dismissal: cancelPolicy", function()
	it("the DEFAULT is unchanged — Cancel dismisses a modal and resigns an engaged HUD", function()
		local _, _, system, _, pres = harness()
		local hud = pres.present(
			Facet.UI.Screen({ id = "Hud", children = { Facet.UI.Button({ id = "Go", label = "Go" }) } }),
			{ responder = "passive" }
		)
		pres.presentModal(paintedModal("M"))
		expect(pres.depth()).toBe(2)
		system.deviceKey("ButtonB", true)
		system.deviceKey("ButtonB", false)
		expect(pres.depth()).toBe(1) -- modal dismissed
		hud.engage()
		expect(hud.responder:get()).toBe("engaged")
		system.deviceKey("ButtonB", true)
		system.deviceKey("ButtonB", false)
		expect(hud.responder:get()).toBe("passive") -- engaged HUD resigned
	end)

	it("cancelPolicy='none' makes Cancel a no-op on the modal, however many times it is pressed", function()
		local _, _, system, _, pres = harness()
		presentBase(pres)
		local modal = pres.presentModal(paintedModal("M"), { cancelPolicy = "none" })
		expect(pres.depth()).toBe(2)
		for _ = 1, 5 do
			system.deviceKey("ButtonB", true)
			system.deviceKey("ButtonB", false)
		end
		expect(pres.depth()).toBe(2) -- still up
		expect(modal.context.destroyed).toBe(false)
		expect(pres.focus.focused:get()).toBe("/M/OK") -- and still owns focus
		-- the surface's OWNER can always take it down deliberately
		pres.dismiss(modal)
		expect(pres.depth()).toBe(1)
	end)

	it("cancelPolicy='none' does NOT imply a pointer barrier — the two opts are orthogonal", function()
		local _, _, _, adapter, pres = harness()
		presentBase(pres)
		pres.presentModal(paintedModal("M"), { cancelPolicy = "none" })
		pres.refresh()
		adapter.tap(pres.topScrimPath(), { x = 500, y = 400 })
		expect(pres.depth()).toBe(1) -- outside tap still dismisses: that is outsideTapCancel's job
		-- a MANDATORY modal therefore sets both, and then nothing takes it down
		pres.presentModal(paintedModal("M"), { cancelPolicy = "none", outsideTapCancel = false })
		pres.refresh()
		adapter.tap(pres.topScrimPath(), { x = 500, y = 400 })
		expect(pres.depth()).toBe(2)
	end)

	it("cancelPolicy='none' still offers Cancel to the focused contribution first", function()
		local _, _, system, _, pres = harness()
		local consumed = 0
		local inner = Facet.contribution.attach(
			Facet.UI.VStack({ id = "Inner", children = { Facet.UI.Button({ id = "OK", label = "OK" }) } }),
			{
				handleCancel = function(_focused: string?): boolean
					consumed += 1
					return true
				end,
			}
		)
		local modal = pres.presentModal(
			Facet.UI.Screen({
				id = "M",
				surface = "raised",
				width = FIXED(200),
				height = FIXED(120),
				children = { inner },
			}),
			{ cancelPolicy = "none" }
		)
		system.deviceKey("ButtonB", true)
		system.deviceKey("ButtonB", false)
		expect(consumed).toBe(1) -- the control cancelled itself
		expect(pres.depth()).toBe(1) -- and the mandatory modal is still up
		pres.dismiss(modal)
	end)

	it("cancelPolicy='none' on a passive HUD keeps it engaged (Cancel no longer resigns)", function()
		local _, _, system, _, pres = harness()
		local hud = pres.present(
			Facet.UI.Screen({ id = "Hud", children = { Facet.UI.Button({ id = "Go", label = "Go" }) } }),
			{ responder = "passive", cancelPolicy = "none" }
		)
		hud.engage()
		system.deviceKey("ButtonB", true)
		system.deviceKey("ButtonB", false)
		expect(hud.responder:get()).toBe("engaged")
		hud.resign() -- the owner still resigns it explicitly
		expect(hud.responder:get()).toBe("passive")
	end)

	it("an unknown cancelPolicy is refused at present time, naming the set", function()
		local _, _, _, _, pres = harness()
		local ok, err = pcall(function()
			return pres.presentModal(paintedModal("M"), { cancelPolicy = "no" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "unknown cancelPolicy", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "dismiss, none", 1, true) ~= nil).toBe(true)
		expect(pres.depth()).toBe(0) -- nothing half-presented
	end)
end)
