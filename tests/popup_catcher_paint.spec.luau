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

	Full write-up: docs/lessons/an-invisible-surface-declares-its-invisibility.md ]]

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
	surface=plain`) and a declaration is not a paint. `plain` earns no
	`facet-surface-*` tag at all, so nothing in the sheet's vocabulary can address
	that node and its transparency is whatever the CLASS DEFAULT rule happens to
	leave — a number the catcher neither states nor owns, on the one node in the
	framework that covers the entire screen.

	SO THE ORACLE BELOW RESOLVES THE PAINT instead of reading the declaration: it
	classifies the catcher exactly as `sheet_model.classifyTags` does, walks the
	BUILT sheet in cascade order, and reports the VALUE and the RULE THAT SUPPLIED
	IT. "Which rule owns this pixel" is the question the three reports were really
	about, and it is answerable headlessly. ]]

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
	whole families are deliberately not this node and are named rather than
	pattern-matched away:

	  `::UICorner` / `::UIStroke` — a DESCENDANT object the sheet materializes.
	  It carries its own properties and none of them is this node's fill.
	  `:Hover` / `:Press` / `:NonInteractable` — an engine GuiState. A catcher is
	  never hovered, pressed or disabled at the moment the reports are about (a
	  full-screen fill that is already wrong before anyone touches it).

	Anything else that is not one of the three resting shapes is REPORTED, so this
	oracle cannot quietly stop matching the vocabulary it is auditing. ]]
local function selectorMatches(selector: string, class: string, tags: { [string]: boolean }): (boolean, string?)
	if string.find(selector, ":", 1, true) ~= nil then
		return false, nil -- a descendant object or a non-resting state
	end
	local cls, tag = string.match(selector, "^([%a]+)%.([%w%-]+)$")
	if cls ~= nil then
		return cls == class and tags[tag] == true, nil
	end
	local bareTag = string.match(selector, "^%.([%w%-]+)$")
	if bareTag ~= nil then
		return tags[bareTag] == true, nil
	end
	if string.match(selector, "^[%a]+$") ~= nil then
		return selector == class, nil
	end
	return false, selector
end

-- the resolved BackgroundTransparency of a catcher declaring `surface`, and the
-- NAME of the rule that supplied it. Insertion order IS the cascade.
local function resolvedCatcherPaint(surface: string?): (number?, string?, { string })
	local tags = sheet_model.classifyTags({ class = "Button", surface = surface, interactive = true })
	local model = neutralSheet()
	local value: number?, owner: string?, unknown: { string } = nil, nil, {}
	for _, rule in model.rules do
		local ok, weird = selectorMatches(rule.selector, "TextButton", tags)
		if weird ~= nil then
			table.insert(unknown, weird)
		end
		if not ok then
			continue
		end
		local prop = rule.props.BackgroundTransparency
		if type(prop) == "table" and prop.kind == "number" then
			value, owner = prop.value, rule.name
		end
	end
	return value, owner, unknown
end

describe("the catcher's paint is OWNED, not inherited from a class default", function()
	it("the oracle can see the difference between a role and a class default", function()
		--[[ THE INSTRUMENT'S OWN PROOF, first: the two surfaces a catcher can wear
			resolve through DIFFERENT rules, so a case built on this oracle is reading
			a real distinction rather than one constant. ]]
		local plainValue, plainOwner, plainUnknown = resolvedCatcherPaint("plain")
		local scrimValue, scrimOwner, scrimUnknown = resolvedCatcherPaint("scrim")
		expect(#plainUnknown).toBe(0)
		expect(#scrimUnknown).toBe(0)
		expect(`plain -> {plainValue} by '{plainOwner}'`).toBe("plain -> 1 by 'Button default'")
		expect(scrimOwner).toBe(sheet_model.SCRIM_RULE)
		expect(`the scrim role dims rather than hides or fills: {scrimValue > 0 and scrimValue < 1}`).toBe(
			"the scrim role dims rather than hides or fills: true"
		)
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
		--[[ ADR-0035: the preference multiplies the theme's own number and is NOT
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
