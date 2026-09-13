--!strict
-- DisclosureGroup: the caret turns, the content slides, and — with a presenter
-- — the siblings it displaces glide (task 12, transitions round, spec 2I).
--
-- The two-region CaretOpen/CaretShut mount/unmount (display_controls.spec.luau,
-- theme_icons_applied.spec.luau) is replaced here by a single `chevron.trailing`
-- glyph whose paint-only `rotation` springs 0 -> 90: this file is the new
-- contract's home, not a rewrite of those two — they keep proving the header's
-- focus story and the icon-request story, which this task did not touch.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")
local Facet = require("../src") :: any

local FRAME = 1 / 60

local function makeWorld(opts: any?)
	local merged: any = { viewport = { x = 0, y = 0, w = 390, h = 844 } }
	for k, v in (opts or {}) :: any do
		merged[k] = v
	end
	return worldLib.new(merged)
end

describe("disclosure: caret turns, content slides", function()
	it("the caret rotates toward 90 on expand and back on collapse", function()
		local w = makeWorld()
		local expanded = w.core:signal(false)
		local group = Facet.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return Facet.UI.Text({ id = "Body", text = "hello" })
			end,
		})
		w.pres.present(Facet.UI.Screen({ id = "S", children = { group.blueprint } }))
		w.pres.refresh()
		local caret = w.adapter.node("/S/Adv/Header/Caret")
		expect(caret.rotation or 0).toBe(0)
		expanded:set(true)
		-- the caret's rotation is an AUTHORED presentation prop, not a
		-- withAnimation flight record: it reaches the adapter through the
		-- ordinary reactive-commit walk, so advancing the spring needs a
		-- `refresh()` alongside every `tick()` (button.luau's own "button: pop"
		-- test drives its lift/scale spring the identical way).
		for _ = 1, 60 do
			w.pres.tick(FRAME)
			w.pres.refresh()
		end
		expect(math.abs((caret.rotation or 0) - 90) < 0.5).toBe(true)
		expect(w.adapter.node("/S/Adv/Content/then/Body") ~= nil).toBe(true)
		expanded:set(false)
		for _ = 1, 60 do
			w.pres.tick(FRAME)
			w.pres.refresh()
		end
		expect(math.abs(caret.rotation or 0) < 0.5).toBe(true)
	end)
end)

-- ===== presenter-bound glide: the reason `presenter` exists on the spec =====
--
-- `spec.presenter` is ONLY for this: the caret and the content animate their
-- own paint off the ambient motion clock every mounted control gets for free
-- (see the describe block above, which never passes one). What a presenter
-- buys is `withAnimation("container", flip)` around the mutation itself, so
-- every OTHER node whose solved position the flip moves — a sibling below the
-- group, pushed down as the content claims its height — travels there instead
-- of jumping, exactly like `tests/with_animation.spec.luau`'s own header/body
-- pair proves for a plain layout change.
describe("disclosure: a presenter glides the sibling it displaces", function()
	it("with presenter given, a sibling below the group travels to its new place", function()
		local w = makeWorld()
		local expanded = w.core:signal(false)
		local group = Facet.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			presenter = w.pres,
			content = function()
				return Facet.UI.Box({ id = "Body", height = { type = "fixed", px = 80 } })
			end,
		})
		w.pres.present(Facet.UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				group.blueprint,
				Facet.UI.Box({ id = "Sibling", height = { type = "fixed", px = 40 } }),
			},
		}))
		w.pres.refresh()
		local before = w.adapter.node("/S/Sibling").rect.y

		-- the real path: a tap on the header, not a direct `expanded:set` — the
		-- withAnimation call lives inside `toggle()`, dispatched through the same
		-- contribution `handleActivate` every input class reaches
		w.adapter.tap("/S/Adv/Header")

		local moved = w.adapter.node("/S/Sibling")
		-- the solve is already exact and instant on the frame the tap resolves...
		expect(moved.rect.y > before).toBe(true)
		-- ...but the PAINT is still seeded at the old place — it has not jumped
		expect(moved.presentedPosition.y).toBe(before)

		for _ = 1, 30 do
			w.pres.tick(FRAME)
		end
		local mid = w.adapter.node("/S/Sibling").presentedPosition.y
		expect(mid > before).toBe(true)
		expect(mid < w.adapter.node("/S/Sibling").rect.y).toBe(true)

		for _ = 1, 90 do
			w.pres.tick(FRAME)
		end
		local settled = w.adapter.node("/S/Sibling")
		expect(settled.presentedPosition.y).toBe(settled.rect.y)
	end)

	it("with no presenter, the same sibling jumps instantly — no flight to compare against", function()
		local w = makeWorld()
		local expanded = w.core:signal(false)
		local group = Facet.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return Facet.UI.Box({ id = "Body", height = { type = "fixed", px = 80 } })
			end,
		})
		w.pres.present(Facet.UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				group.blueprint,
				Facet.UI.Box({ id = "Sibling", height = { type = "fixed", px = 40 } }),
			},
		}))
		w.pres.refresh()
		local before = w.adapter.node("/S/Sibling").rect.y
		w.adapter.tap("/S/Adv/Header")
		w.pres.refresh()
		local moved = w.adapter.node("/S/Sibling")
		expect(moved.rect.y > before).toBe(true)
		-- no presenter bound, so nothing armed a flight: the paint lands exactly
		-- where the solve did, on the same frame
		expect(moved.presentedPosition.y).toBe(moved.rect.y)
	end)
end)

-- ===== reduced motion: the caret is decorative, so it SNAPS ================
describe("disclosure: reduced motion snaps the caret instead of turning it", function()
	it("the caret reaches 90 on the very first frame, not gradually", function()
		local w = makeWorld({ reducedMotion = true })
		local expanded = w.core:signal(false)
		local group = Facet.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return Facet.UI.Text({ id = "Body", text = "hello" })
			end,
		})
		w.pres.present(Facet.UI.Screen({ id = "S", children = { group.blueprint } }))
		w.pres.refresh()
		local caret = w.adapter.node("/S/Adv/Header/Caret")
		expect(caret.rotation or 0).toBe(0)
		expanded:set(true)
		w.pres.tick(FRAME)
		w.pres.refresh()
		expect(math.abs((caret.rotation or 0) - 90) < 0.5).toBe(true)
	end)
end)
