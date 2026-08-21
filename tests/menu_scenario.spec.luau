--!strict
--[[ THE SHOWCASE SURFACE FOR `newMenu` — `examples/gallery/scenarios/menu.luau`.

	`tests/menu.spec.luau` proves the CONSTRUCT against hand-built worlds. This
	file proves the thing a person holding a phone actually opens, which D2
	shipped without: that the five triggers are each reachable from the surface,
	through the routes a finger, a mouse, a key and a pad really take; that both
	presentation idioms are reachable in ONE session on ONE machine; and that the
	card whose every item is unavailable still opens.

	WHY THE SPLIT ACROSS FIVE CARDS IS THE LOAD-BEARING CASE. `newMenu` refuses a
	`triggers` set that drops `activate` unless it declares BOTH chords, so a
	fixture that put all five routes on one trigger could not tell a tester which
	one worked — and one that put the chords on two cards would open two menus on
	one press, because equal-priority contexts do not sink each other. The five
	sets below are the smallest partition that isolates every route and leaves
	exactly one owner for the global chord, and that is asserted rather than
	described: the union is the five, and the chord count is one.

	AND ONE THING THIS FILE DOES NOT CLAIM. It cannot prove that the readout names
	the trigger that fired, because the framework does not report one — `onOpen`
	takes no argument and `dump().triggers` is the DECLARED set. What is asserted
	instead is the honest version: each route opens ITS OWN card, and the fixture
	prints that card's name. See the `honest` copy on the surface itself.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local focus_map = require("../src/present/focus_map")
local demo_picker = require("../examples/gallery/client/demo_picker") :: any
local module = require("../examples/gallery/scenarios/menu") :: any

local PHONE = { w = 320, h = 640 }
local LANDSCAPE = { w = 640, h = 320 }
local DESKTOP = { w = 1200, h = 900 }

local CARDS = { "Tap", "Chord", "Secondary", "Hold", "Blocked" }
local TRIGGER: { [string]: string } = {}
for _, id in CARDS do
	TRIGGER[id] = `/MenuDemo/Page/Cards/Card{id}/{id}Trigger`
end

local function panelRow(card: string, level: number, itemId: string): string
	local surface = if level == 0 then `Menu-{card}` else `Menu-{card}-L{level}`
	return `/{surface}/Layer/Surface/Panel/Item:{itemId}`
end
local function sheetRow(card: string, itemId: string): string
	return `/Menu-{card}/Layer/Panel/Item:{itemId}`
end

local function world(view: { w: number, h: number })
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local built = module.build({
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		actionSystem = system,
	})
	built.handle = pres.present(built.screen, built.present)
	local w: any = { core = core, env = env, adapter = adapter, pres = pres, system = system, built = built }
	function w.settle(frames: number?)
		for _ = 1, frames or 6 do
			pres.tick(1 / 60)
			pres.refresh()
		end
	end
	function w.text(path: string): string?
		local facts = built.handle.controller.textAt()[path]
		return if facts ~= nil then facts.text else nil
	end
	function w.openCount(): number
		local n = 0
		for _, d in built.report().cards do
			if d.open then
				n += 1
			end
		end
		return n
	end
	w.settle()
	return w
end

describe("scenario 'menu': the surface D2 shipped without", function()
	it("is registered in BOTH places a player reaches it through, and names a root screen", function()
		local listed: any = nil
		for _, demo in demo_picker.list() do
			if demo.id == "menu" then
				listed = demo
			end
		end
		expect(listed ~= nil).toBe(true)
		expect(listed.kind).toBe("fixture")
		expect(listed.module).toBe("menu")
		local w = world(PHONE)
		-- the id the catalogue sweep looks for, read off the MOUNTED tree rather
		-- than off the blueprint: a demo whose root never materializes is exactly
		-- the failure `gallery_demo_picker.spec`'s negative control is named after
		expect(w.adapter.node("/MenuDemo") ~= nil).toBe(true)
		expect(w.core:lastError()).toBeNil()
	end)

	--[[ THE PARTITION, and it is the fixture's whole shape rather than a layout
		choice. `activate` may only be dropped by a card that declares BOTH chords,
		so the five routes cannot be five one-trigger cards — and two cards owning
		the chord would both open on one press, since `deviceKey` only breaks on a
		STRICTLY lower priority (`src/input/actions.luau`). ]]
	it("the five routes are partitioned across five cards, with exactly ONE owner of the chords", function()
		local w = world(PHONE)
		local seen: { [string]: number } = {}
		local chordOwners = 0
		local dumps = w.built.report().cards
		expect(#dumps).toBe(5)
		for _, d in dumps do
			local keyboard, gamepad = false, false
			for _, name in d.triggers do
				seen[name] = (seen[name] or 0) + 1
				keyboard = keyboard or name == "keyboard"
				gamepad = gamepad or name == "gamepad"
			end
			if keyboard or gamepad then
				chordOwners += 1
				-- the authoring rule itself: a chord card carries both, never one
				expect(`{d.id}: keyboard {keyboard} gamepad {gamepad}`).toBe(`{d.id}: keyboard true gamepad true`)
			end
		end
		local missing: { string } = {}
		for _, name in { "activate", "secondary", "longPress", "keyboard", "gamepad" } do
			if (seen[name] or 0) < 1 then
				table.insert(missing, name)
			end
		end
		expect(`routes no card offers: {table.concat(missing, ",")}`).toBe("routes no card offers: ")
		expect(chordOwners).toBe(1)
	end)

	it("every card's trigger is a focusable Button at the 44px floor, in document order", function()
		local w = world(PHONE)
		local paths: { string } = {}
		focus_map.collectFocusables(w.built.handle.root.node, paths)
		-- five triggers, then the three Idiom segments — the strip is painted below
		-- the cards and is read where it is painted
		expect(#paths).toBe(8)
		for index, id in CARDS do
			expect(paths[index]).toBe(TRIGGER[id])
			local node = w.adapter.node(TRIGGER[id])
			expect(node.class).toBe("Button")
			expect(`{id} is {node.rect.h}px tall, under 44? {node.rect.h < 44}`).toBe(
				`{id} is {node.rect.h}px tall, under 44? false`
			)
			--[[ NO DECLARATION CHECK FOR `onActivate` HERE, and its absence is
				deliberate. A trigger that declared one would silently stop opening its
				menu — the presenter tries a leaf's own `props.onActivate` BEFORE any
				contribution — but the adapter does not mirror function props onto its
				nodes, so `expect(node.props.onActivate).toBeNil()` is a check that
				proves nothing: it was written, the defect was injected, and it stayed
				green. What DOES bite is the tap case below, verified by the same
				injection. ]]
		end
	end)

	--[[ THE OTHER HALF OF THE 44px FLOOR, AND THE ONE THAT REACHED A DEVICE
		(device review 2026-08-16, F1). Director, on a phone: *"I would expect that
		I could do the action in each thing on the entire row, not just the text."*

		The floor work above asks whether a target is tall enough and never asks
		whether it is WIDE enough, which is how a card that reads as a full-width
		row shipped with a trigger the width of its own label — 58px of press on a
		312px row, and 254px of dead band that looks identical to it. Every route
		case in this file taps by PATH (`adapter.tap(TRIGGER[id])`), and a
		path-addressed tap lands on the node whatever its rect is, so the entire
		route suite stayed green over a target four fifths of which was not there.

		The measurement is the DEAD BAND rather than a pinned width, because the
		card's own padding is a theme token: whatever inset the card gives the
		trigger on the leading side it must give on the trailing side too, and the
		trigger owns everything between. Asserted at both a phone and a desktop —
		a row that hugs its label is narrow at every size, but only the phone makes
		it a defect a thumb can find. ]]
	it("every card's trigger fills the card's row — the press is the ROW, not the word", function()
		for _, view in { PHONE, DESKTOP } do
			local w = world(view)
			for _, id in CARDS do
				local card = w.adapter.node(`/MenuDemo/Page/Cards/Card{id}`).rect
				local trigger = w.adapter.node(TRIGGER[id]).rect
				-- the inset the card gave the trigger on its leading side, whatever
				-- the theme's `s` token happens to be
				local inset = trigger.x - card.x
				local dead = (card.x + card.w - inset) - (trigger.x + trigger.w)
				expect(`{view.w}x{view.h} {id}: {math.floor(dead + 0.5)}px of the row takes no press`).toBe(
					`{view.w}x{view.h} {id}: 0px of the row takes no press`
				)
			end
		end
	end)
end)

describe("scenario 'menu': each route opens ITS OWN card, through the real seam", function()
	it("primary activate — a tap, and Return on the focused trigger", function()
		local w = world(PHONE)
		w.adapter.tap(TRIGGER.Tap)
		w.settle()
		expect(w.openCount()).toBe(1)
		expect(string.find(w.built.report().lastOpen, "routes: activate —") ~= nil).toBe(true)
		w.built.steps.close(w.built)
		w.settle()
		-- ...and the keyboard half of the same route, on the focus ring the screen
		-- puts on that trigger at mount
		expect(w.pres.focus.focused:get()).toBe(TRIGGER.Tap)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		w.settle()
		expect(w.openCount()).toBe(1)
	end)

	it("pointer secondary — a right-click, through the adapter's own MouseButton2 seam", function()
		local w = world(DESKTOP)
		w.adapter.driveSecondaryActivate(TRIGGER.Secondary)
		w.settle()
		expect(w.openCount()).toBe(1)
		expect(w.built.report().cards[3].open).toBe(true)
		expect(string.find(w.built.report().lastOpen, "secondary") ~= nil).toBe(true)
	end)

	it("touch long-press — the NORMALIZED gesture, at `began`, not at the release", function()
		local w = world(PHONE)
		w.adapter.driveTouchGesture(TRIGGER.Hold, { kind = "longPress", state = "began" })
		w.settle()
		expect(w.openCount()).toBe(1)
		expect(w.built.report().cards[4].open).toBe(true)
		-- and it is `began` that did it: an `ended` on a closed menu opens nothing,
		-- which is what makes the on-screen claim ("it opens before you lift") true
		w.built.steps.close(w.built)
		w.settle()
		w.adapter.driveTouchGesture(TRIGGER.Hold, { kind = "longPress", state = "ended" })
		w.settle()
		expect(w.openCount()).toBe(0)
	end)

	it("the two chords — and the card a TAP deliberately does not open", function()
		local w = world(PHONE)
		-- the refusal first, because it is the thing that makes this card a test:
		-- press it like a button and nothing happens
		w.adapter.tap(TRIGGER.Chord)
		w.settle()
		expect(w.openCount()).toBe(0)
		for _, key in { "Menu", "ButtonY" } do
			w.system.deviceKey(key, true)
			w.system.deviceKey(key, false)
			w.settle()
			expect(`{key} opened {w.openCount()} menu(s)`).toBe(`{key} opened 1 menu(s)`)
			expect(w.built.report().cards[2].open).toBe(true)
			w.built.steps.close(w.built)
			w.settle()
		end
		-- ...and the laptop chord for the keyboards that dropped the Menu key
		w.system.deviceKey("LeftShift", true)
		w.system.deviceKey("F10", true)
		w.system.deviceKey("F10", false)
		w.system.deviceKey("LeftShift", false)
		w.settle()
		expect(w.openCount()).toBe(1)
	end)
end)

describe("scenario 'menu': the list, and what the framework says about it", function()
	it("icons per group, a divider, and the destructive verb last", function()
		local w = world(DESKTOP)
		w.built.steps.open(w.built, "Tap")
		w.settle()
		local items = w.built.report().cards[1].items
		-- group 1 (above the rule) all carry an icon, group 2 (below it) both do
		local icons: { string } = {}
		local dividerAt: number? = nil
		for index, item in items do
			if item.divider then
				dividerAt = index
			else
				table.insert(icons, tostring(item.icon))
			end
		end
		expect(dividerAt).toBe(4)
		expect(table.concat(icons, ",")).toBe("edit,more,edit,flag,trash")
		expect(items[#items].role).toBe("destructive")
		for _, id in { "accessory", "layering", "skin", "report", "reset" } do
			expect(w.adapter.node(panelRow("Tap", 0, id)) ~= nil).toBe(true)
		end
	end)

	it("a submenu two levels deep, and the standing advice PRINTED rather than swallowed", function()
		local w = world(DESKTOP)
		w.built.steps.open(w.built, "Tap")
		w.built.steps.enter(w.built, "layering")
		w.settle()
		expect(w.adapter.node(panelRow("Tap", 1, "makeup")) ~= nil).toBe(true)
		w.built.steps.enter(w.built, "makeup")
		w.settle()
		expect(w.adapter.node(panelRow("Tap", 2, "lips")) ~= nil).toBe(true)
		expect(string.find(w.built.report().state, "depth 2") ~= nil).toBe(true)
		-- the advice is the framework's sentence, on the screen, verbatim
		local diags = w.built.report().diagnostics
		expect(#diags).toBe(1)
		expect(w.text("/MenuDemo/Page/Diag/Body")).toBe(diags[1])
		expect(string.find(diags[1], "nests 2 levels deep") ~= nil).toBe(true)
		-- Left leaves a level, which is the keyboard half of the same claim
		w.built.steps.back(w.built)
		w.settle()
		expect(string.find(w.built.report().state, "depth 1") ~= nil).toBe(true)
	end)

	--[[ THE REFUSAL WITH A CARD OF ITS OWN. The guidance: if all of a menu's items are
		unavailable, the menu itself needs to remain available so people can open it
		and learn about the commands it contains." A trigger that swallowed itself
		here would be indistinguishable from a dead button on a device. ]]
	it("a menu whose every item is disabled OPENS, paints them disabled, and runs nothing", function()
		local w = world(DESKTOP)
		w.adapter.tap(TRIGGER.Blocked)
		w.settle()
		expect(w.openCount()).toBe(1)
		for _, id in { "save", "share", "delete" } do
			expect(w.adapter.node(panelRow("Blocked", 0, id)).props.enabled).toBe(false)
		end
		local before = w.built.report().ran
		w.built.steps.enter(w.built, "save")
		w.settle()
		expect(w.built.report().ran).toBe(before)
		-- ...and it did not close under the player either: nothing happened, visibly
		expect(w.openCount()).toBe(1)
	end)
end)

describe("scenario 'menu': both idioms, from one control, on one machine", function()
	it("panel stacks a surface per level; sheet REPLACES and grows a Back row", function()
		local w = world(PHONE)
		w.built.steps.idiom(w.built, "panel")
		w.built.steps.open(w.built, "Tap")
		w.built.steps.enter(w.built, "layering")
		w.settle()
		expect(w.built.report().presentation).toBe("menu")
		expect(w.built.report().cards[1].surfaces).toBe(2)
		expect(w.adapter.node(panelRow("Tap", 1, "clothing")) ~= nil).toBe(true)
		expect(w.adapter.node(sheetRow("Tap", "clothing"))).toBeNil()
		w.built.steps.close(w.built)
		w.settle()

		w.built.steps.idiom(w.built, "sheet")
		w.built.steps.open(w.built, "Tap")
		w.settle()
		expect(w.built.report().presentation).toBe("sheet")
		expect(w.adapter.node("/Menu-Tap/Layer/Panel/Back")).toBeNil()
		w.built.steps.enter(w.built, "layering")
		w.settle()
		-- ONE surface at depth 1, and the way back is a row rather than a second
		-- panel — the only thing that tells the two idioms apart without looking
		expect(w.built.report().cards[1].surfaces).toBe(1)
		local back = w.adapter.node("/Menu-Tap/Layer/Panel/Back")
		expect(back ~= nil).toBe(true)
		expect(`Back is {back.rect.h}px tall, under 44? {back.rect.h < 44}`).toBe(
			`Back is {back.rect.h}px tall, under 44? false`
		)
		expect(w.adapter.node(sheetRow("Tap", "clothing")) ~= nil).toBe(true)
		expect(w.adapter.node(panelRow("Tap", 1, "clothing"))).toBeNil()
	end)

	it("a live idiom flip REBUILDS an open chain in place, at the depth the player reached", function()
		local w = world(PHONE)
		w.built.steps.idiom(w.built, "panel")
		w.built.steps.open(w.built, "Tap")
		w.built.steps.enter(w.built, "layering")
		w.built.steps.enter(w.built, "makeup")
		w.settle()
		expect(w.built.report().cards[1].surfaces).toBe(3)
		w.built.steps.idiom(w.built, "sheet")
		w.settle()
		-- still open, still two levels down, and now ONE surface: cancelling the
		-- chain instead would close a menu under a player who changed nothing
		expect(w.openCount()).toBe(1)
		expect(w.built.report().cards[1].depth).toBe(2)
		expect(w.built.report().cards[1].surfaces).toBe(1)
	end)

	it("`automatic` is the environment's own answer, and it is not a device name", function()
		local w = world(PHONE)
		w.built.steps.idiom(w.built, "auto")
		w.settle()
		-- headless capabilities are pointer+keyboard, so the automatic answer here
		-- is the panel; the claim is that it FOLLOWS the fact rather than a branch
		expect(w.built.report().presentation).toBe("menu")
		w.env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		w.env:set("preferredInput", "Touch")
		w.settle()
		expect(w.built.report().presentation).toBe("sheet")
	end)
end)

describe("scenario 'menu': it holds together where a phone squeezes it", function()
	it("the solver reports NOTHING at any swept viewport, closed or open", function()
		for _, view in { PHONE, LANDSCAPE, DESKTOP } do
			local w = world(view)
			local closed = w.built.handle.controller.diagnostics()
			expect(`{view.w}x{view.h} closed: {#closed} finding(s)`).toBe(`{view.w}x{view.h} closed: 0 finding(s)`)
			w.built.steps.open(w.built, "Tap")
			w.built.steps.enter(w.built, "layering")
			w.settle()
			local open = w.built.handle.controller.diagnostics()
			expect(`{view.w}x{view.h} open: {#open} finding(s)`).toBe(`{view.w}x{view.h} open: 0 finding(s)`)
			w.built.dispose()
		end
	end)

	it("every player-visible string is in the exported `copy`, so the localization sweep can reach it", function()
		local w = world(DESKTOP)
		local strings: { [string]: boolean } = {}
		for _, value in module.copy do
			if type(value) == "string" then
				strings[value] = true
			end
		end
		local painted = 0
		for path, facts in w.built.handle.controller.textAt() do
			-- the menu's own rows are the CONTROL's text, not this fixture's, and a
			-- submenu row paints no label at all (a content button's label is
			-- semantics); what this case pins is the fixture's own page.
			--
			-- A READOUT IS COMPOSED, so "is in copy" is the wrong question for half
			-- of them: the counts line is five copy strings and five numbers, and it
			-- still moves under an expansion because the pieces do. The rule that
			-- covers both shapes is that every painted string either IS a copy value
			-- or CONTAINS one — which a hard-coded literal on this page would fail.
			--[[ THE ONE EXEMPTION, AND IT IS A CATEGORY RATHER THAN A WAIVER: the
				diagnostics plate prints the FRAMEWORK's own advice verbatim, which is
				developer text in a developer showcase and belongs to `api.diagnostics()`
				rather than to this fixture. `callout.luau` prints `dump().text` on the
				same footing. It is pinned character-for-character by the submenu case
				above, so it is asserted here too — just against the other source. ]]
			local frameworkEcho = path == "/MenuDemo/Page/Diag/Body"
			if
				string.find(path, "^/MenuDemo/") ~= nil
				and not frameworkEcho
				and type(facts.text) == "string"
				and facts.text ~= ""
			then
				painted += 1
				local reached = strings[facts.text] == true
				if not reached then
					for value in strings do
						if #value > 3 and string.find(facts.text, value, 1, true) ~= nil then
							reached = true
							break
						end
					end
				end
				expect(`{path}: "{facts.text}" is reachable by the localization sweep? {reached}`).toBe(
					`{path}: "{facts.text}" is reachable by the localization sweep? true`
				)
			end
		end
		expect(painted > 12).toBe(true)
	end)
end)
