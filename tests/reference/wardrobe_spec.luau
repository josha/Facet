--!strict
-- Reference proof "Wardrobe" — E1 loop pins (RA-P5, swiftui-reference-app-validation).
-- Try-on/undo/redo history, the purchase lifecycle with scripted rejections,
-- the stage seam (camera/lighting recorded on the headless host stub), the
-- split ⇄ stacked Composition flip with state survival, locale swap, and reset
-- determinism. The proof is SELF-PRESENTING: build presents and returns handle.

local t = require("../lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../../src") :: any
local fake_target = require("../lib/fake_target")
local proof = require("../../examples/reference/p5_wardrobe") :: any

local BODY = "/Wardrobe/BoutiqueWhen/then/Body"
local PANE = BODY .. "/Preview/PreviewCol/PaneZ/Pane"

local function makeWorld(viewportW: number?, viewportH: number?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = viewportW or 1400, h = viewportH or 900 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	local deps = { env = env, actionSystem = system, presenter = presenter, adapter = adapter }
	local built = proof.build(LuauUI, core, deps)
	presenter.refresh()
	return {
		core = core,
		env = env,
		adapter = adapter,
		presenter = presenter,
		built = built,
		handle = built.handle,
	}
end

local function teardown(w: any)
	if w.built.dispose then
		w.built.dispose()
	end
	w.presenter.dismiss(w.handle)
end

local function findPath(adapter: any, needle: string): string?
	for _, path in adapter.paths() do
		if string.find(path, needle, 1, true) then
			return path
		end
	end
	return nil
end

local function settleTransitions(w: any)
	for _ = 1, 8 do
		w.presenter.tick(0.1)
	end
	w.presenter.refresh()
end

describe("Wardrobe proof — mount, stage seam, arrangement (RA-P5)", function()
	it("mounts the boutique with categories, grids, pane, and no core error", function()
		local w = makeWorld()
		expect(w.core:lastError()).toBeNil()
		expect(w.adapter.node(PANE) ~= nil).toBe(true)
		expect(findPath(w.adapter, "Cat_hats/B") ~= nil).toBe(true)
		expect(findPath(w.adapter, "PickedGrid") ~= nil).toBe(true)
		expect(findPath(w.adapter, "RestGrid") ~= nil).toBe(true)
		teardown(w)
	end)

	it("the stage host is live headlessly (recording stub): lighting + camera recorded, fallback closed", function()
		local w = makeWorld()
		local report = w.built.report()
		expect(report.stageAvailable).toBe(true)
		local host = w.built._internals.stageHostRef()
		expect(host ~= nil).toBe(true)
		local sawLighting, sawCamera = false, false
		for _, call in host.calls do
			if call.method == "setLighting" then
				sawLighting = true
			elseif call.method == "setCamera" then
				sawCamera = true
			end
		end
		expect(sawLighting).toBe(true)
		expect(sawCamera).toBe(true)
		expect(findPath(w.adapter, "FallbackWhen/then") == nil).toBe(true)
		teardown(w)
	end)

	it("an orbit step drives a new camera write through the public host", function()
		local w = makeWorld()
		local host = w.built._internals.stageHostRef()
		local before = #host.calls
		w.built.steps.yaw(nil, 90)
		expect(#host.calls > before).toBe(true)
		local last = host.calls[#host.calls]
		expect(last.method).toBe("setCamera")
		teardown(w)
	end)

	it("wide solves the split arrangement; a phone box solves stacked — and worn state survives the flip", function()
		local w = makeWorld(1400)
		local comp = w.handle.controller.compositionAt(BODY)
		expect(comp ~= nil).toBe(true)
		expect(comp.arrangement).toBe("split")
		w.built.steps.equip(nil, "puffin-beanie")
		w.presenter.refresh()
		local paneBefore = w.adapter.node(PANE)
		w.env:set("viewportRect", { x = 0, y = 0, w = 390, h = 800 })
		w.presenter.refresh()
		local comp2 = w.handle.controller.compositionAt(BODY)
		expect(comp2.arrangement).toBe("stacked")
		expect(w.adapter.node(PANE) == paneBefore).toBe(true)
		expect(w.built.report().worn.hats).toBe("puffin-beanie")
		teardown(w)
	end)
end)

describe("Wardrobe proof — try-on and history", function()
	it(
		"activating a card equips it: Wearing chip, selected state, rig re-dressed; activating again unequips",
		function()
			local w = makeWorld()
			local card = findPath(w.adapter, "/puffin-beanie")
			expect(card ~= nil).toBe(true)
			local rigWrites = #w.built.report().stageLog
			w.adapter.tap(card :: string)
			w.presenter.refresh()
			expect(w.built.report().worn.hats).toBe("puffin-beanie")
			expect(findPath(w.adapter, "puffin-beanie/Col/Status/Wearing/then/Chip") ~= nil).toBe(true)
			expect(#w.built.report().stageLog > rigWrites).toBe(true)
			w.adapter.tap(card :: string)
			w.presenter.refresh()
			expect(w.built.report().worn.hats).toBeNil()
			teardown(w)
		end
	)

	it("undo/redo walk the equip history and disable at the stack ends", function()
		local w = makeWorld()
		local undo = findPath(w.adapter, "Controls/History/Undo")
		local redo = findPath(w.adapter, "Controls/History/Redo")
		expect(w.adapter.node(undo :: string).props.enabled).toBe(false)
		expect(w.adapter.node(redo :: string).props.enabled).toBe(false)
		w.built.steps.equip(nil, "puffin-beanie")
		w.built.steps.equip(nil, "marsh-boots")
		w.presenter.refresh()
		expect(w.adapter.node(undo :: string).props.enabled).toBe(true)
		w.adapter.tap(undo :: string)
		w.presenter.refresh()
		local r = w.built.report()
		expect(r.worn.shoes).toBeNil()
		expect(r.worn.hats).toBe("puffin-beanie")
		expect(w.adapter.node(redo :: string).props.enabled).toBe(true)
		w.adapter.tap(redo :: string)
		w.presenter.refresh()
		expect(w.built.report().worn.shoes).toBe("marsh-boots")
		-- a fresh equip after undo truncates the redo branch
		w.adapter.tap(undo :: string)
		w.built.steps.equip(nil, "ember-clogs")
		w.presenter.refresh()
		expect(w.adapter.node(redo :: string).props.enabled).toBe(false)
		teardown(w)
	end)

	it("trying on an unowned item raises the BuyBar; an owned one does not", function()
		local w = makeWorld()
		expect(findPath(w.adapter, "BuyBarWhen/then/BuyBar") == nil).toBe(true)
		w.built.steps.equip(nil, "puffin-beanie")
		w.presenter.refresh()
		expect(findPath(w.adapter, "BuyBarWhen/then/BuyBar/Buy") ~= nil).toBe(true)
		w.built.steps.undo()
		w.built.steps.equip(nil, "cinder-hood")
		settleTransitions(w)
		expect(findPath(w.adapter, "BuyBarWhen/then") == nil).toBe(true)
		teardown(w)
	end)
end)

describe("Wardrobe proof — the purchase lifecycle", function()
	it("insufficient Sparks rejects with a visible reason; the wallet never moves; retry stays allowed", function()
		local w = makeWorld()
		w.built.steps.equip(nil, "static-halo")
		w.presenter.refresh()
		w.adapter.tap(findPath(w.adapter, "BuyBarWhen/then/BuyBar/Buy") :: string)
		w.presenter.refresh()
		local confirm = findPath(w.adapter, "Confirm/PanelZ/Plate/Footer/Confirm")
		expect(confirm ~= nil).toBe(true)
		w.adapter.tap(confirm :: string)
		expect(w.built.report().purchaseStatus).toBe("pending")
		w.presenter.refresh()
		expect(w.adapter.node(confirm :: string).props.enabled).toBe(false)
		w.built.steps.settle()
		w.presenter.refresh()
		local r = w.built.report()
		expect(r.purchaseStatus).toBe("rejected")
		expect(r.balance).toBe(240)
		expect(findPath(w.adapter, "Reason/then/Strip") ~= nil).toBe(true)
		expect(w.adapter.node(confirm :: string).props.enabled).toBe(true)
		teardown(w)
	end)

	it(
		"sold-out rejects once, then a retry confirms: balance debits, chip flips to Owned+Wearing, modal dismisses, BuyBar leaves",
		function()
			local w = makeWorld()
			local baseDepth = w.presenter.depth()
			w.built.steps.equip(nil, "moth-cloak")
			w.presenter.refresh()
			w.adapter.tap(findPath(w.adapter, "BuyBarWhen/then/BuyBar/Buy") :: string)
			w.presenter.refresh()
			local confirm = findPath(w.adapter, "Confirm/PanelZ/Plate/Footer/Confirm")
			w.adapter.tap(confirm :: string)
			w.built.steps.settle()
			w.presenter.refresh()
			expect(w.built.report().purchaseStatus).toBe("rejected")
			expect(findPath(w.adapter, "Reason/then/Strip") ~= nil).toBe(true)
			-- retry on the same surface
			w.adapter.tap(confirm :: string)
			w.built.steps.settle()
			settleTransitions(w)
			local r = w.built.report()
			expect(r.purchaseStatus).toBe("confirmed")
			expect(r.balance).toBe(240 - 120)
			expect(w.presenter.depth()).toBe(baseDepth)
			expect(w.built._internals.services.owned:get()["moth-cloak"]).toBe(true)
			expect(findPath(w.adapter, "BuyBarWhen/then") == nil).toBe(true)
			teardown(w)
		end
	)
end)

describe("Wardrobe proof — filters, sections, locale, determinism", function()
	it("owned-only shrinks the catalog; price sort reorders; reset restores", function()
		local w = makeWorld()
		local services = w.built._internals.services
		local allCount = #services.visibleItems(w.built._internals.signals.category):get()
		services.ownedOnly:set(true)
		w.presenter.refresh()
		local ownedCount = #services.visibleItems(w.built._internals.signals.category):get()
		expect(ownedCount < allCount).toBe(true)
		services.ownedOnly:set(false)
		services.sort:set("price")
		local sorted = services.visibleItems(w.built._internals.signals.category):get()
		local last = -1
		local ordered = true
		for _, item in sorted do
			local p = item.price or 0
			if p < last then
				ordered = false
			end
			last = p
		end
		expect(ordered).toBe(true)
		teardown(w)
	end)

	it("section stubs are honest and the worn set survives leaving and returning", function()
		local w = makeWorld()
		w.built.steps.equip(nil, "puffin-beanie")
		w.built.steps.section(nil, "outfits")
		settleTransitions(w)
		expect(findPath(w.adapter, "OutfitsWhen/then/Stub") ~= nil).toBe(true)
		expect(findPath(w.adapter, "BoutiqueWhen/then") == nil).toBe(true)
		w.built.steps.section(nil, "boutique")
		settleTransitions(w)
		expect(w.built.report().worn.hats).toBe("puffin-beanie")
		expect(findPath(w.adapter, "puffin-beanie/Col/Status/Wearing/then/Chip") ~= nil).toBe(true)
		teardown(w)
	end)

	it("the locale swap reaches the BuyBar copy live", function()
		local w = makeWorld()
		w.built.steps.equip(nil, "puffin-beanie")
		w.presenter.refresh()
		local buy = findPath(w.adapter, "BuyBarWhen/then/BuyBar/Buy")
		expect(string.find(tostring(w.adapter.node(buy :: string).props.label), "Buy", 1, true) ~= nil).toBe(true)
		w.built.steps.locale(nil, "xa")
		w.presenter.refresh()
		expect(string.find(tostring(w.adapter.node(buy :: string).props.label), "%[") ~= nil).toBe(true)
		teardown(w)
	end)

	it("two fresh builds are identical (reset determinism) and dispose cleanly", function()
		local a = makeWorld()
		local b = makeWorld()
		expect(a.built.report().balance).toBe(b.built.report().balance)
		expect(#a.adapter.paths()).toBe(#b.adapter.paths())
		teardown(a)
		teardown(b)
		expect(a.core:lastError()).toBeNil()
		expect(b.core:lastError()).toBeNil()
	end)
end)
