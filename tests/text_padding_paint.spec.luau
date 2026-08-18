--!strict
-- A PADDED `UI.Text` IS DRAWN INSIDE ITS PADDING (device report 2026-08-12,
-- IMG_3691 — the all-controls fixture's S1..S12 stat tiles).
--
-- THE DEFECT. `UI.padding` is legal on a Text: `blueprint_schema`'s Text.padding
-- says so in as many words — "the solver's text measure adds padding to the
-- reserved box, so this is a real layout input on a label (it lets UI.padding
-- apply without wrapping)". The measure honoured it and the paint did not. A
-- CONTAINER spends its padding in `arrange` (children are placed at rect + pl/pt)
-- and a LEAF has no children to place, so `arrange` returned at the text leaf with
-- nothing inset; the renderer's padding seam only visited `Button`; and
-- `screen_target`'s `setProp("padding")` only had a `Button` branch. The result on
-- a phone: each stat plate came out label-width + 12 and the label was drawn from
-- the box's leading edge, sitting on — and past — the plate's own rounded corner.
-- Measured at a size nobody painted.
--
-- THE FIX, and what these cases pin: the renderer raises the same `padding` write
-- for a Text with an AUTHORED padding that it has always raised for a Button, and
-- both adapters materialize a four-sided inset from it. All four sides, not
-- Button's horizontal pair: a Button centres one line inside a box the solver
-- already reserved, while a Text can wrap and can be top/bottom aligned, and the
-- four numbers written are exactly the four `contentSize` measured with.
--
-- The instance budget is pinned too, in both directions — an unpadded label (every
-- Text on every shipped screen but these) raises no write and materializes no
-- modifier, and a steady padded one writes once.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")

local UI = Facet.UI

local function world(build: (any) -> any): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 300 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = Facet.newPresenter(core, env, adapter, system)
	local handle = presenter.present(build(core))
	presenter.refresh()
	return { core = core, env = env, adapter = adapter, presenter = presenter, handle = handle }
end

-- the showcase's stat tile, verbatim from examples/gallery/scenarios/adaptive_controls
local function statTile(id: string, label: string): any
	return UI.background(
		UI.padding(UI.Text({ id = id, text = label, textSize = 12 }), { top = 4, bottom = 4, left = 6, right = 6 }),
		UI.Box({ id = `{id}Plate`, surface = "control" })
	)
end

describe("padded Text: the inset the solver measured reaches paint", function()
	it("✓ a padded Text raises the padding write and materializes a four-sided inset", function()
		local w = world(function()
			return UI.Screen({ id = "S", children = { statTile("Stat1", "S1") } })
		end)
		local text = w.adapter.node("/S/Stat1+background/Stat1")
		expect(text).never().toBeNil()
		-- the WRITE reached the adapter...
		expect(text.props.padding).never().toBeNil()
		-- ...and the adapter APPLIED it (emission is not application)
		expect(text.textPadding).never().toBeNil()
		expect(text.textPadding.className).toBe("UIPadding")
		expect(text.textPadding.sides.left).toBe(6)
		expect(text.textPadding.sides.right).toBe(6)
		expect(text.textPadding.sides.top).toBe(4)
		expect(text.textPadding.sides.bottom).toBe(4)
	end)

	it("✓ the glyph box is the box the solver measured, minus the padding it measured with", function()
		local w = world(function()
			return UI.Screen({ id = "S", children = { statTile("Stat1", "S1") } })
		end)
		local text = w.adapter.node("/S/Stat1+background/Stat1")
		local plate = w.adapter.node("/S/Stat1+background/Stat1Plate")
		-- the plate backs the padded box, so the two rects agree — that is the
		-- shape that made the defect invisible in a rect dump
		expect(plate.rect.w).toBe(text.rect.w)
		expect(plate.rect.x).toBe(text.rect.x)
		-- and the label is drawn INSIDE it: the drawable width is the padded box
		-- less the two sides, which is the width `contentSize` reserved for
		local sides = text.textPadding.sides
		local drawable = text.rect.w - sides.left - sides.right
		expect(drawable > 0).toBe(true)
		expect(drawable).toBe(text.rect.w - 12)
		expect(text.rect.h - sides.top - sides.bottom).toBe(text.rect.h - 8)
	end)

	it("✓ an unpadded Text raises no padding write and materializes no modifier", function()
		local w = world(function()
			return UI.Screen({
				id = "S",
				children = { UI.Text({ id = "Plain", text = "no padding here", textSize = 12 }) },
			})
		end)
		local text = w.adapter.node("/S/Plain")
		expect(text.props.padding).toBeNil()
		expect(text.textPadding).toBeNil()
	end)

	it("✓ a per-side metric NAME resolves through the snapshot, like every other side", function()
		local w = world(function()
			return UI.Screen({
				id = "S",
				children = { UI.padding(UI.Text({ id = "Named", text = "metric", textSize = 12 }), { left = "m" }) },
			})
		end)
		local text = w.adapter.node("/S/Named")
		expect(text.textPadding).never().toBeNil()
		-- "m" is a space-ladder name, so it arrives as a resolved NUMBER > 0 and
		-- the sides nobody authored are zero — the same rule Button's pair follows
		expect(type(text.textPadding.sides.left)).toBe("number")
		expect(text.textPadding.sides.left > 0).toBe(true)
		expect(text.textPadding.sides.right).toBe(0)
	end)

	it("✓ minimal-write: a steady padded label costs one padding write, not one per refresh", function()
		local w = world(function()
			return UI.Screen({ id = "S", children = { statTile("Stat1", "S1") } })
		end)
		local before = w.adapter.node("/S/Stat1+background/Stat1").textPadding.creations
		expect(before).toBe(1)
		w.presenter.refresh()
		w.presenter.refresh()
		expect(w.adapter.node("/S/Stat1+background/Stat1").textPadding.creations).toBe(1)
	end)

	it("✓ the inset FOLLOWS its value: a padding that goes to zero un-insets the label", function()
		-- `padding` is a reactive prop, and the seam is minimal-write, so the case
		-- that matters is the one where the cached key changes. It is also the
		-- shape the recycler needs: `captureParkedProps`/`restoreParkedProps` carry
		-- `padding` across an adoption, so an adopted label whose new node declares
		-- none is un-padded by an explicit zero write rather than by being skipped
		-- (renderer `applyPadding`) — skipping would leave the previous row's inset
		-- on a modifier nothing visits again.
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 300 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = Facet.newPresenter(core, env, adapter, system)
		local sides = core:signal({ top = 4, bottom = 4, left = 6, right = 6 })
		local handle = presenter.present(UI.Screen({
			id = "S",
			children = { UI.padding(UI.Text({ id = "L", text = "S1", textSize = 12 }), sides :: any) },
		}))
		presenter.refresh()
		local wide = adapter.node("/S/L").rect.w
		expect(adapter.node("/S/L").textPadding.sides.left).toBe(6)

		sides:set({ top = 0, bottom = 0, left = 0, right = 0 })
		presenter.refresh()
		local node = adapter.node("/S/L")
		expect(node.textPadding.sides.left).toBe(0)
		expect(node.textPadding.sides.top).toBe(0)
		-- ...and the BOX shrank by exactly the padding the measure no longer adds,
		-- so paint and measure moved together
		expect(node.rect.w).toBe(wide - 12)
		presenter.dismiss(handle)
	end)

	it("✓ the fixture the device found it on: every adaptive_controls stat tile is inset", function()
		local scenario = require("../examples/gallery/scenarios/adaptive_controls") :: any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 402, h = 569 })
		env:set("coreSafeInsets", { top = 58, bottom = 0, left = 0, right = 0 })
		env:set("preferredInput", "Touch")
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = Facet.newPresenter(core, env, adapter, system)
		local built = scenario.build({
			Facet = Facet,
			core = core,
			env = env,
			adapter = adapter,
			presenter = presenter,
			actionSystem = system,
			record = function() end,
			flags = {},
			geometry = function()
				return {}
			end,
		})
		presenter.present(built.screen, built.present)
		presenter.refresh()
		local seen = 0
		for i = 1, 12 do
			local path = `/AdaptiveScreen/BodyScroll/Body/Hud/Stats/Stat{i}+background/Stat{i}`
			local node = adapter.node(path)
			expect(node).never().toBeNil()
			expect(node.textPadding).never().toBeNil()
			expect(node.textPadding.sides.left).toBe(6)
			expect(node.textPadding.sides.top).toBe(4)
			-- the plate it sits on is the padded box, and the label has room inside
			local plate = adapter.node(`/AdaptiveScreen/BodyScroll/Body/Hud/Stats/Stat{i}+background/StatPlate{i}`)
			expect(plate.rect.w).toBe(node.rect.w)
			expect(node.rect.w - 12 > 0).toBe(true)
			seen += 1
		end
		expect(seen).toBe(12)
	end)
end)
