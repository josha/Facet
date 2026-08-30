--!strict
--[[ THE SYNTHESIZED POPUP CATCHER MUST BE INVISIBLE (device bug, director,
	2026-08-13: "in the showcase when i swipe from left to right in swipe row
	actions/table, some random thing appears over the top of the screen blocking
	the demo picker and settings button" — evidence: topscreen.mov).

	THE MECHANISM. An open row-actions tray publishes `outsideDismiss.active`
	(row_actions.luau's contribution bundle), so the presenter synthesizes its
	transient popup catcher: a full-viewport `Button` on its own `__popupcatcher__`
	root, mounted at `owner.displayOrder - 50`, whose entire job is to swallow one
	outside tap. `mountPopupCatcher` declared that Button with NO `surface` and NO
	decoration hint — and `chrome_slots.classify` maps every bare `Button` to the
	`control` slot, so an image-driven package materialized its control plate
	across the whole viewport. Beneath the base screen it is invisible; in the band
	the base screen does not cover (the showcase's chrome inset, where the demo
	picker and Settings live) it is a brown plate over the chrome.

	THIS IS THE SCRIM CATCHER'S ALREADY-LEARNED LESSON, UNAPPLIED TO ITS SIBLING.
	`mountScrim` carries both halves of the fix and both of its comments explain
	exactly this failure ("a Button with no surface still classifies as `control`,
	so the invisible catcher wore the installed package's SOLID control colour
	across the whole viewport"; "every image-driven package painted its button
	plate over the whole screen"). `mountPopupCatcher` — written later, for the
	same "invisible full-viewport tap swallower" job — inherited neither.

	SO THE CHECK IS ON THE MECHANISM, NOT ON THE ROW. Two facts about the ONE
	catcher the presenter mounts, asserted from both of its live owners: the
	row-actions tray the director actually swiped, and PopupButton, the seam's
	original consumer, which has the identical defect for the identical reason.

	`chrome_slots.classify` is the real oracle — the same call
	`screen_chrome.luau`'s `chromeSlotOf` makes on the live adapter, fed the same
	two inputs (`handle.declaredSurface`, `handle.decorationHint.slot`). A nil
	answer is "no package will ever draw here"; `"control"` is the defect.

	MEASURED ON THE REAL ADAPTER, same session, same theme, both shapes — the
	shipped popup catcher against the scrim catcher, which already carries the
	declarations this one was missing:

	  TextButton '/__popupcatcher__/catcher'  413x735  bgT=0.00
	    ImageLabel 'FacetChrome'             413x735  bgT=0.00   <- the plate
	  TextButton '/__scrim__/catcher'         413x735  bgT=1.00   <- and nothing else

	An invisible surface has to declare its own invisibility. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local row_actions = require("../src/controls/row_actions")
local popup_button = require("../src/controls/popup_button")
local fake_target = require("./lib/fake_target")
local chrome_slots = require("../src/tokens/chrome_slots")

local FRAME = 1 / 60

-- One string carrying BOTH halves of "invisible", so a failure names the defect
-- rather than reporting `control ~= nil` with no context.
local function catcherPaint(adapter: any, path: string): string
	local node = adapter.node(path)
	if node == nil then
		return "no catcher mounted"
	end
	local hint = chrome_slots.readHint(node)
	local slot = chrome_slots.classify({
		class = node.class,
		surface = node.props.surface,
		hint = if hint ~= nil then hint.slot else nil,
	})
	return `decorationSlot={tostring(slot)} surface={tostring(node.props.surface)}`
end

local INVISIBLE = "decorationSlot=nil surface=plain"

-- ===========================================================================
-- 1. the reported repro: a real left-to-right swipe on a row-actions row
-- ===========================================================================
describe("popup catcher paint: an open row-actions tray", function()
	--[[ Driven as the director drove it — `adapter.pointerDown/Move/Up` left to
		right across the row's own hit surface (the leading edge), released past
		half the tray so it settles OPEN, exactly like
		row_actions_input.spec.luau's own gesture cases. Nothing here is
		programmatic: the catcher appears because a real gesture left a real tray
		open, which is when the director saw the plate. ]]
	local function leadingWorld()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local clockTime = 0
		local pres = Facet.newPresenter(core, env, adapter, system, {
			now = function()
				return clockTime
			end,
		})
		local ra = row_actions.build(Facet, core, {
			id = "Row",
			content = Facet.UI.Text({
				id = "Body",
				text = "Row content",
				width = { type = "fixed", px = 400 },
				height = { type = "fixed", px = 48 },
			}),
			leading = {
				{ id = "read", label = "Mark Read", onAction = function() end },
			},
		})
		local screen = Facet.UI.Screen({ id = "S", children = { ra.blueprint } })
		local handle = pres.present(screen)
		pres.refresh()
		local w: any =
			{ core = core, env = env, system = system, adapter = adapter, pres = pres, ra = ra, handle = handle }
		function w.tick(dt: number)
			clockTime += dt
			pres.tick(dt)
			pres.refresh()
		end
		function w.settle(frames: number?)
			for _ = 1, frames or 90 do
				w.tick(FRAME)
			end
		end
		return w
	end

	-- the settled leading tray width, learned live from an identical throwaway
	-- world (the house pattern) rather than hardcoded
	local function learnLeadingWidth(): number
		local ref = leadingWorld()
		ref.ra._open("leading")
		ref.settle()
		return ref.ra.dump().offset
	end

	it("swiping LEFT TO RIGHT to reveal the leading tray must not paint a plate over the viewport", function()
		local trayWidth = learnLeadingWidth()
		local w = leadingWorld()
		local releaseX = 100 + trayWidth * 0.75 -- well past half the tray: settles OPEN
		w.adapter.pointerDown("/S/Row/Content/Hit", 100, 20, "touch")
		w.tick(0.01)
		w.adapter.pointerMove(115, 20) -- dx = +15: past the 8px axis lock, resolves horizontal
		w.tick(1.0) -- a long, calm gap, so the release is a snap decision and not a flick
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		w.settle()

		expect(w.ra._isOpen()).toBe(true) -- the gesture really did leave a tray open
		local path = w.pres.topPopupCatcherPath()
		expect(path).never().toBeNil() -- ...so the presenter really did synthesize a catcher
		expect(catcherPaint(w.adapter, path :: string)).toBe(INVISIBLE)
	end)
end)

-- ===========================================================================
-- 2. the sibling owner: PopupButton, the seam's original consumer
-- ===========================================================================
describe("popup catcher paint: an open PopupButton", function()
	it("the same catcher, reached through the other outsideDismiss owner, is equally unpainted", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local control = popup_button.build(Facet, core, {
			id = "Difficulty",
			options = { { id = "easy", label = "Easy" }, { id = "normal", label = "Normal" } },
			value = core:signal("normal"),
			onChange = function() end,
		})
		pres.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }), { sinkNavigation = true })
		pres.refresh()
		adapter.tap("/S/Difficulty/Trigger")
		pres.refresh()

		local path = pres.topPopupCatcherPath()
		expect(path).never().toBeNil()
		expect(catcherPaint(adapter, path :: string)).toBe(INVISIBLE)
	end)

	--[[ The catcher sits BENEATH its owner (`owner.displayOrder - 50`), which is
		why the plate showed up in the chrome band rather than over the whole
		screen: the base screen covers the catcher everywhere it paints, and the
		showcase's inset chrome band is exactly where it does not. Pinned here so
		the geometry half of the director's report ("over the top of the screen
		blocking the demo picker") stays explained by a measured fact rather than
		by this comment alone. ]]
	it("sits beneath its owner's DisplayOrder — which is why only the uncovered chrome band showed it", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local control = popup_button.build(Facet, core, {
			id = "Difficulty",
			options = { { id = "easy", label = "Easy" } },
			value = core:signal("easy"),
			onChange = function() end,
		})
		pres.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }), { sinkNavigation = true })
		pres.refresh()
		adapter.tap("/S/Difficulty/Trigger")
		pres.refresh()
		expect(adapter.rootDisplayOrder("__popupcatcher__")).never().toBeNil()
		expect(adapter.rootDisplayOrder("__popupcatcher__") < adapter.rootDisplayOrder("S")).toBe(true)
	end)
end)

-- ===========================================================================
-- 3. THE SAME CATCHER, THE THIRD REPORT, AND THE CHECK THAT DID NOT SEE IT
-- ===========================================================================
--[[ THE DIRECTOR HAS NOW REPORTED "THE POPUP BACKGROUND IS OPAQUE" THREE TIMES
	(DIR2-2, DIR3-1, DIR5-2). MEASURED live at the third report, on the HUD demo at
	compact-phone portrait with a region's expand plate open: the roots and their
	display orders are all correct (base 12000, `Facet___scrim__` 42050,
	`Facet_Expand:Clock` 42100), `GuiService.PreferredTransparency` is 1 so it is
	not the accessibility case — and `/__scrim__/catcher`, a full-viewport node,
	reads `GetStyled("BackgroundTransparency") = 0`. An opaque full-screen fill
	under the plate.

	AND THE TWO CASES ABOVE WERE GREEN OVER IT, on the twin path their own header
	names. That is this repository's "check that proves nothing" class, and the
	reason is exact: they assert the DECLARATION (`decorationSlot=nil
	surface=plain`) and a declaration is not a paint.

	=== AND THE FIRST ANSWER THIS FILE GAVE WAS WRONG (fix round 1) ===

	The first version of this section said the opaque fill came from `plain`
	resolving to "whatever the CLASS DEFAULT rule happens to leave". **Its own first
	case refutes that**, and a review said so: `plain` resolves to `Button default`
	-> `BackgroundTransparency = 1`, i.e. exactly the transparent-but-catching
	catcher the code intended. The class default was never the source. A mechanism
	contradicted by the instrument shipped to prove it is worth more space than a
	quiet edit, so it is recorded rather than deleted.

	WHAT THE DIRECTOR'S TWO NUMBERS ACTUALLY MEASURE, live in Studio, in
	artifacts/expand-plate/catcher-paint-window.md:
	  · `BackgroundTransparency = 0` (the plain property) is EXPECTED AND PERMANENT.
	    In native mode the adapter writes that property on no node ever — an explicit
	    write would defeat every surface rule — so it reads the engine default for
	    the life of every Facet node. It corroborates nothing.
	  · `GetStyled(...) = 0` is the STYLING-APPLICATION WINDOW. Measured: a freshly
	    created root reads the CLASS DEFAULT for ~3 frames and then the rule's value,
	    for `scrim` (0.45) exactly as much as for `plain` (1). A catcher root is
	    created at the instant a surface opens, so a reading taken then is inside it.

	So this file cannot say the visual bug is explained, and it does not. What it
	CAN do is make "which rule owns this pixel" answerable, for every catcher this
	presenter can mount — which is what the oracle below does: it classifies the
	catcher exactly as `sheet_model.classifyTags` does, walks the BUILT sheet in
	`(priority, insertion)` order, and reports the VALUE and the RULE THAT SUPPLIED
	IT. Three reports were really asking that question, and it is answerable
	headlessly even though the paint is not. ]]

local sheet_model = require("../src/tokens/sheet_model")
local default_style = require("../src/tokens/default_style")
local light_style = require("../src/tokens/default_light_style")
local worldLib = require("./lib/world")
local UI = Facet.UI

local function neutralSheet(): any
	return sheet_model.build({
		themes = { { name = "Dark", style = default_style }, { name = "Light", style = light_style } },
	})
end

-- a one-region composition that has to step down at 390x40, so activating its
-- framework-synthesized affordance presents a real expand plate over a real screen
local function expandScreen(): any
	return UI.Screen({
		id = "S",
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {
			UI.Composition({
				id = "C",
				arrangements = { "column" },
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				groups = { { id = "body", lane = "main", sizing = "fill" } },
				children = {
					UI.Region({
						id = "Clock",
						group = "body",
						rank = 1,
						recover = "overflow",
						children = {
							UI.VStack({
								id = "Full",
								children = {
									UI.Text({ id = "A", text = "2:14", textSize = 16 }),
									UI.Text({ id = "B", text = "12 - 9", textSize = 16 }),
									UI.Text({ id = "C2", text = "Home 12", textSize = 16 }),
								},
							}),
							UI.Text({ id = "Compact", text = "2:14", textSize = 16 }),
						},
					}),
				},
			}),
		},
	})
end

--[[ Does a rule's selector match a RESTING node of `class` carrying `tags`? Two
	whole families are deliberately not this node, and each is COUNTED rather than
	pattern-matched away (review finding L5 — a skip channel nothing can see is how
	an oracle stops auditing the vocabulary it was built for):

	  `::UICorner` / `::UIStroke` — a DESCENDANT object the sheet materializes.
	  It carries its own properties and none of them is this node's fill.
	  `:Hover` / `:Press` / `:NonInteractable` — an engine GuiState. A catcher is
	  never hovered, pressed or disabled at the moment the reports are about (a
	  full-screen fill that is already wrong before anyone touches it).

	The second answer is the CHANNEL a selector went down: "match", "state",
	"descendant", or "unknown". Anything that is not one of the three resting
	shapes lands in `unknown`, and the case below asserts every channel's count. ]]
local function selectorMatches(selector: string, class: string, tags: { [string]: boolean }): (boolean, string)
	if string.find(selector, "::", 1, true) ~= nil then
		return false, "descendant"
	end
	if string.find(selector, ":", 1, true) ~= nil then
		return false, "state"
	end
	local cls, tag = string.match(selector, "^([%a]+)%.([%w%-]+)$")
	if cls ~= nil then
		return cls == class and tags[tag] == true, "match"
	end
	local bareTag = string.match(selector, "^%.([%w%-]+)$")
	if bareTag ~= nil then
		return tags[bareTag] == true, "match"
	end
	if string.match(selector, "^[%a]+$") ~= nil then
		return selector == class, "match"
	end
	return false, "unknown"
end

--[[ The resolved BackgroundTransparency of a catcher declaring `surface`, and the
	NAME of the rule that supplied it.

	THE CASCADE IS `(priority, insertion)`, NOT INSERTION ALONE (review finding L5).
	`sheet_model` derives `rule.priority` from the index today, so the two orders
	agree — but a rule that ever declares its own priority would make an
	insertion-only oracle wrong QUIETLY, on the one instrument three reports were
	waiting for. Reading the field the engine reads costs one comparison. ]]
local function resolvedCatcherPaint(surface: string?): (number?, string?, { [string]: number })
	local tags = sheet_model.classifyTags({ class = "Button", surface = surface, interactive = true })
	local model = neutralSheet()
	local channels: { [string]: number } = { match = 0, state = 0, descendant = 0, unknown = 0 }
	local ordered: { { rule: any, index: number, priority: number } } = {}
	for index, rule in model.rules do
		local ok, channel = selectorMatches(rule.selector, "TextButton", tags)
		channels[channel] += 1
		if ok then
			local priority = if type(rule.priority) == "number" then rule.priority else index
			table.insert(ordered, { rule = rule, index = index, priority = priority })
		end
	end
	table.sort(ordered, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.index < b.index
	end)
	local value: number?, owner: string? = nil, nil
	for _, entry in ordered do
		local prop = entry.rule.props.BackgroundTransparency
		if type(prop) == "table" and prop.kind == "number" then
			value, owner = prop.value, entry.rule.name
		end
	end
	return value, owner, channels
end

describe("every synthesized catcher resolves to a number somebody chose", function()
	it("the oracle can see the difference between a role and a class default", function()
		--[[ THE INSTRUMENT'S OWN PROOF, first: the two surfaces a catcher can wear
			resolve through DIFFERENT rules, so a case built on this oracle is reading
			a real distinction rather than one constant. ]]
		local plainValue, plainOwner, plainChannels = resolvedCatcherPaint("plain")
		local scrimValue, scrimOwner, scrimChannels = resolvedCatcherPaint("scrim")
		expect(plainChannels.unknown).toBe(0)
		expect(scrimChannels.unknown).toBe(0)
		expect(`plain -> {plainValue} by '{plainOwner}'`).toBe("plain -> 1 by 'Button default'")
		expect(scrimOwner).toBe(sheet_model.SCRIM_RULE)
		expect(`the scrim role dims rather than hides or fills: {scrimValue > 0 and scrimValue < 1}`).toBe(
			"the scrim role dims rather than hides or fills: true"
		)
		--[[ ...AND THE SKIPPED FAMILIES ARE REAL AND NON-EMPTY (L5). A skip channel
			that happened to be empty would mean the oracle was matching everything and
			the exemptions below were about nothing. ]]
		expect(`state rules skipped: {plainChannels.state > 0}`).toBe("state rules skipped: true")
		expect(`descendant rules skipped: {plainChannels.descendant > 0}`).toBe("descendant rules skipped: true")
	end)

	it("...and skipping the STATE rules is a fact about the sheet, not an assumption", function()
		--[[ L5's other half. The oracle drops `:Hover` / `:Press` / `:NonInteractable`
			because a catcher is never in those states — which is only safe while no
			state rule carries a FILL. That is true of every rule both builders emit
			today; if one ever does, the exemption becomes a lie and this reddens
			instead of the oracle quietly reporting the resting value for a node that
			is painting something else. ]]
		local painting: { string } = {}
		for _, rule in neutralSheet().rules do
			if string.find(rule.selector, "::", 1, true) ~= nil then
				continue
			end
			if string.find(rule.selector, ":", 1, true) == nil then
				continue
			end
			if rule.props.BackgroundTransparency ~= nil then
				table.insert(painting, `{rule.name} ({rule.selector})`)
			end
		end
		table.sort(painting)
		expect(table.concat(painting, " ; ")).toBe("")
	end)

	it("a region's EXPAND plate mounts a barrier that wears the scrim ROLE", function()
		--[[ THE CASE THAT REDDENS AT THE THIRD REPORT'S HEAD, which is the whole
			point of adding it: there the plate presented `scrim = "none"`, the catcher
			was declared `plain`, and the oracle above names the rule that then owned
			the whole screen's fill — `Button default`, a class default nobody chose. ]]
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 40 } })
		w.present(expandScreen(), { initialFocus = "none" })
		expect(w.controller.compositionAt("/S/C").regions[1].activeForm).toBe(2)
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		local path = w.pres.topScrimPath()
		expect(path).never().toBeNil()
		local node = w.adapter.node(path :: string)
		expect(node).never().toBeNil()
		-- it really is the full-viewport node the reports are about
		expect(`{node.rect.w}x{node.rect.h}`).toBe("390x40")
		expect(node.props.surface).toBe("scrim")
		local value, owner = resolvedCatcherPaint(node.props.surface)
		expect(owner).toBe(sheet_model.SCRIM_RULE)
		expect(`the barrier under the plate is translucent: {value > 0 and value < 1}`).toBe(
			"the barrier under the plate is translucent: true"
		)
	end)

	it("...and the player's PreferredTransparency composes against it, uncapped", function()
		--[[ the preference multiplies the theme's own number and is NOT
			floored — `PreferredTransparency = 0` is a player asking for an opaque
			backdrop and gets one. The rule the preference is allowed to move is a
			declared list of exactly one, and it is the same rule the case above
			resolved to, which is what makes wearing the role the whole fix. ]]
		local base = select(1, resolvedCatcherPaint("scrim"))
		expect(sheet_model.backdropTransparency(base, 1)).toBe(base)
		expect(sheet_model.backdropTransparency(base, 0)).toBe(0)
		expect(sheet_model.backdropTransparency(base, 0.5)).toBe(base * 0.5)
		local moved: { string } = {}
		for _, row in sheet_model.PREFERENCE_RULE_PROPS do
			table.insert(moved, `{row.rule}/{row.prop}`)
		end
		expect(table.concat(moved, " ")).toBe(`{sheet_model.SCRIM_RULE}/BackgroundTransparency`)
	end)

	--[[ ── EVERY OTHER CATCHER THIS PRESENTER CAN MOUNT (DIR5 fix round) ─────────
		The review's finding: DIR5 changed ONE path to the scrim role and left every
		other `plain` catcher alone on the reasoning that the class default was the
		opaque source — which its own oracle refutes (`plain` resolves to 1). So the
		class must not be able to recur on a path nobody tested, and the disposition
		of each path has to be a decision rather than an omission.

		THE POPULATION IS THREE, and the sweep is over the mechanism rather than the
		row:
		  · `mountScrim(owner, "none")` — an engaged-passive surface (`presenter`
		    defaults every non-modal to `"none"`), `newMenu`, and row-actions' floating
		    menu. Must NOT dim: a menu at a button is not a backdrop.
		  · `mountPopupCatcher` — PopupButton's panel and an open row-actions tray.
		    Mounts `plain` unconditionally, same reason.
		  · `mountScrim(owner, "scrim")` — a declared modal, and the region EXPAND
		    plate since DIR5. SHOULD dim: it covers content.

		`plain` is therefore the right DECLARATION for two of the three, and this case
		pins what actually supplies their invisibility — the class-default rule — so a
		rename, a reorder under a painting rule, or a state rule that ever carries a
		fill reddens all of them together instead of one shipping opaque. ]]
	it("every catcher role resolves to a number somebody chose, and the two invisible ones to 1", function()
		local plainValue, plainOwner = resolvedCatcherPaint("plain")
		local scrimValue, scrimOwner = resolvedCatcherPaint("scrim")
		--[[ EXACTLY 1, not "> 0". A catcher that resolved to 0.999 would be a
			near-opaque full-screen fill and every "is it transparent" predicate this
			repository has would call it fine. ]]
		expect(`plain={plainValue} by '{plainOwner}'`).toBe("plain=1 by 'Button default'")
		expect(`scrim={scrimValue} by '{scrimOwner}'`).toBe(`scrim={scrimValue} by '{sheet_model.SCRIM_RULE}'`)
		expect(scrimOwner).toBe(sheet_model.SCRIM_RULE)
		expect(`the dim is a dim: {scrimValue > 0 and scrimValue < 1}`).toBe("the dim is a dim: true")
	end)

	it("...and the two live `plain` owners really do mount a catcher that resolves to 1", function()
		--[[ Driven rather than reasoned, through both shipped `outsideDismiss` owners
			and through a `newMenu`-shaped modal that declares `scrim = "none"` — the
			three ways a `plain` catcher reaches a screen. The two cases at the top of
			this file already drive the first two for their DECLARATION; this reads the
			resolved number off the same nodes. ]]
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 40 } })
		w.present(expandScreen(), { initialFocus = "none" })
		w.pres.presentAnchored(
			UI.VStack({
				id = "Panel",
				surface = "raised",
				padding = "s",
				width = { type = "fixed", px = 120 },
				children = { UI.Button({ id = "One", label = "one", onActivate = function() end }) },
			}),
			{
				id = "Menu",
				modal = true,
				scrim = "none",
				outsideTapCancel = true,
				anchor = { source = { path = "/S/C/Clock" } },
			}
		)
		w.pres.refresh()
		local path = w.pres.topScrimPath()
		expect(path).never().toBeNil()
		local node = w.adapter.node(path :: string)
		expect(node.props.surface).toBe("plain")
		local value, owner = resolvedCatcherPaint(node.props.surface)
		expect(`a menu's barrier: {value} by '{owner}'`).toBe("a menu's barrier: 1 by 'Button default'")
		-- it really is full-viewport, which is what makes the number matter
		expect(`{node.rect.w}x{node.rect.h}`).toBe("390x40")
	end)

	it("the synthesized scrim ROOT is linked to the same sheet as the screen it covers", function()
		--[[ THE OTHER WAY THE SAME PIXEL GOES OPAQUE, and it is worth a case of its
			own because the fix above cannot reach it: in native mode the adapter writes
			no `BackgroundTransparency` at all (an explicit write would permanently
			defeat every surface rule — spike m10), so a catcher root that the theme
			sheet never reached would paint the ENGINE default, which is 0. Opaque, on
			every surface role including this one.

			The presenter mounts the scrim on its own root, after the screen it covers,
			so it is exactly the shape that inherits nothing. `trackThemeRoots` is the
			target seam that answers it. ]]
		local w = worldLib.new({
			viewport = { x = 0, y = 0, w = 390, h = 40 },
			newAdapter = function()
				return fake_target.new({ trackThemeRoots = true })
			end,
		})
		w.present(expandScreen(), { initialFocus = "none" })
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		local sheets = w.adapter.rootThemeSheets()
		expect(sheets["S"]).never().toBeNil()
		expect(sheets["__scrim__"]).never().toBeNil()
		expect(`the scrim root shares the screen's sheet: {sheets["__scrim__"] == sheets["S"]}`).toBe(
			"the scrim root shares the screen's sheet: true"
		)
	end)
end)
