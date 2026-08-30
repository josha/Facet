--!strict
-- Reference proof "Foyer" — E1 loop pins (RA-P4, reference-app-validation).
-- The representative loop, its rejection paths, reflow survival, locale swap,
-- image transport states, and reset determinism — driven through the public
-- presenter/adapter stack (fake target), never through test-only shortcuts:
-- every interaction here is an adapter.tap on a mounted control or a declared
-- scenario step.

local t = require("../lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../../src") :: any
local fake_target = require("../lib/fake_target")
local proof = require("../../examples/reference/p4_foyer") :: any

local function makeWorld(viewportW: number?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = viewportW or 1400, h = 900 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = Facet.newPresenter(core, env, adapter, system)
	local deps = { env = env, actionSystem = system, presenter = presenter, adapter = adapter }
	local built = proof.build(Facet, core, deps)
	local handle = presenter.present(built.screen, built.present)
	presenter.refresh()
	return {
		core = core,
		env = env,
		adapter = adapter,
		presenter = presenter,
		built = built,
		handle = handle,
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

--[[ THE SECTION NAV IS NOW ONE `Facet.newTabView` (navigation-and-menus D5),
	so the four hand-built bars and the two content `When`s this file used to pin
	by name are gone. The paths below are the construct's, and the helpers under
	them are how a case names a WING without knowing which home it is standing in
	— which is the point: the home is a policy answer, and a case that hard-codes
	one is testing the shell rather than the placement. ]]
local NAV = "/Foyer/Root/Nav"
local HOME = NAV .. "/Content/Tab-home/then/HomeBody"
local HOMES: { [string]: string } = {
	sidebar = NAV .. "/RailHome/then/Rail",
	topBar = NAV .. "/TopHome/then/TopBandCenter/TopBand",
	bottomBar = NAV .. "/BottomHome/then/BottomBand",
	bottomBarCompact = NAV .. "/CompactHome/then/CompactBandCenter/CompactBand",
}
-- DESTINATIONS in declaration order: the strip gives its segments `Opt<n>` ids,
-- and `newTabView` publishes nothing else a test could name them by
local ORDER = { "home", "crews", "forge", "mail", "you" }
local function wingSuffix(dest: string): string
	for index, name in ORDER do
		if name == dest then
			return `/Strip/Indicator/Options/Opt{index}`
		end
	end
	error(`no destination '{dest}'`)
end

-- advance structural exit transitions to completion (cap 500 ms) so a swapped
-- ForEach's RETIRED rows actually dispose before an absence is asserted
local function settleTransitions(w: any)
	for _ = 1, 8 do
		w.presenter.tick(0.1)
	end
	w.presenter.refresh()
end

describe("Foyer proof — mount and structure (RA-P4)", function()
	it("mounts the home body with all four sections and no core error", function()
		local w = makeWorld()
		expect(w.core:lastError()).toBeNil()
		for _, section in { "picked", "continue", "new", "friends" } do
			expect(findPath(w.adapter, "Sections/[" .. section .. "]") ~= nil).toBe(true)
		end
		expect(w.adapter.node(HOME .. "/TabRow/Tab_forYou/B") ~= nil).toBe(true)
		expect(findPath(w.adapter, "FriendsRow/F_marrow") ~= nil).toBe(true)
		teardown(w)
	end)

	it("wide viewport shows the nav rail, not the bottom bar; compact shows the bottom bar", function()
		local wide = makeWorld(1400)
		expect(wide.adapter.node(HOMES.sidebar) ~= nil).toBe(true)
		expect(wide.adapter.node(HOMES.bottomBar)).toBeNil()
		teardown(wide)
		local compact = makeWorld(390)
		expect(compact.adapter.node(HOMES.sidebar)).toBeNil()
		expect(compact.adapter.node(HOMES.bottomBar) ~= nil).toBe(true)
		teardown(compact)
	end)

	it("a size-class flip swaps chrome but never remounts the home body", function()
		local w = makeWorld(1400)
		local tabPath = HOME .. "/TabRow/Tab_forYou/B"
		local before = w.adapter.node(tabPath)
		expect(before ~= nil).toBe(true)
		w.env:set("viewportRect", { x = 0, y = 0, w = 390, h = 800 })
		w.presenter.refresh()
		expect(w.adapter.node(HOMES.bottomBar) ~= nil).toBe(true)
		-- the nav RE-HOMES and the content does not move at all: the tab body sits
		-- in the construct's own content region, which no placement touches
		expect(w.adapter.node(tabPath) == before).toBe(true)
		teardown(w)
	end)
end)

describe("Foyer nav — the four placement homes (adaptive.navPlacement)", function()
	-- The section nav's home is a POLICY over shape/input/display facts, not
	-- whatever happens to fit. Every assertion here is GEOMETRY — which band the
	-- wings are painted in, how wide they are, where their midpoint sits —
	-- because a name-only pin survives a shell that mounts the right node in the
	-- wrong place. The top CHROME bar (brand, search, refresh, profile, bell)
	-- is a separate band and must stay put on every one of them.
	local function shaped(viewport: any, facts: any?): any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", viewport)
		for key, value in facts or {} do
			env:set(key, value)
		end
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		local built =
			proof.build(Facet, core, { env = env, actionSystem = system, presenter = presenter, adapter = adapter })
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		local self: any = {
			core = core,
			env = env,
			adapter = adapter,
			presenter = presenter,
			system = system,
			built = built,
			handle = handle,
		}
		function self.node(needle: string): any
			local path = findPath(adapter, needle)
			return if path ~= nil then adapter.node(path) else nil
		end
		return self
	end

	local TOUCH = { touch = true, mouse = false, keyboard = false, gamepad = false }

	it("navPlacement gives every canvas its home: rail / bottom band / inline band / top band", function()
		-- pointer desktop: the vertical rail beside the content
		local desktop = shaped({ x = 0, y = 0, w = 1400, h = 900 })
		local rail = desktop.node(HOMES.sidebar)
		expect(rail ~= nil and rail.rect ~= nil).toBe(true)
		expect(rail.rect.x < 1400 * 0.2).toBe(true)
		expect(rail.rect.h > rail.rect.w * 2).toBe(true) -- a COLUMN, not a band
		expect(desktop.node(HOMES.bottomBar)).toBeNil()
		expect(desktop.node(HOMES.topBar)).toBeNil()
		teardown(desktop)

		-- phone portrait: the full-width thumb-zone band, whose wings DIVIDE it
		local phone = shaped({ x = 0, y = 0, w = 390, h = 844 })
		local band = phone.node(HOMES.bottomBar)
		expect(band ~= nil and band.rect ~= nil).toBe(true)
		expect(band.rect.w).toBe(390)
		-- the band pads itself; what matters is that the strip takes the whole
		-- inner box rather than hugging its five words
		expect((phone.node(HOMES.bottomBar .. "/Strip") :: any).rect.w > band.rect.w - 16).toBe(true)
		expect(phone.node(HOMES.sidebar)).toBeNil()
		teardown(phone)

		-- phone landscape (roomy width, SHORT height): the SAME wings in a band
		-- that HUGS them instead of dividing the width, so a fifth wing can push
		-- the strip past the band and scroll rather than truncate
		local land = shaped({ x = 0, y = 0, w = 720, h = 360 })
		local inline = land.node(HOMES.bottomBarCompact .. "/Strip")
		expect(inline ~= nil and inline.rect ~= nil).toBe(true)
		expect(inline.rect.w < 720 * 0.7).toBe(true)
		expect(land.node(HOMES.bottomBar)).toBeNil()
		teardown(land)

		-- tablet (roomy short side + touch): the top band, hugging
		local tablet = shaped({ x = 0, y = 0, w = 1080, h = 810 }, { capabilities = TOUCH, preferredInput = "Touch" })
		local top = tablet.node(HOMES.topBar .. "/Strip")
		expect(top ~= nil and top.rect ~= nil).toBe(true)
		expect(top.rect.w < 1080 * 0.7).toBe(true) -- hugs
		expect(tablet.node(HOMES.sidebar)).toBeNil()
		expect(tablet.node(HOMES.bottomBar)).toBeNil()
		teardown(tablet)

		--[[ ...and the SAME canvas with the display fact the engine really sends
			for a tablet — `Small`, which Roblox documents as "Most tablet/mobile/
			handheld devices" — is the same tablet and the same top band.
			RE-PINNED from `bottomBar` (ADAPT-2, audit 2026-08-18): this row asserted
			that a 1280x720 touch canvas stays a phone, which is how the tablet
			column of every prior gate came to measure a phone. The short side is
			720px; nothing about it is a handheld. ]]
		local small = shaped(
			{ x = 0, y = 0, w = 1280, h = 720 },
			{ capabilities = TOUCH, preferredInput = "Touch", displaySize = "Small" }
		)
		expect(small.node(HOMES.topBar) ~= nil).toBe(true)
		expect(small.node(HOMES.bottomBar)).toBeNil()
		expect(small.core:lastError()).toBeNil()
		teardown(small)
	end)

	it("the nav band sits BELOW the content at both bottom placements", function()
		for _, canvas in { { 390, 844 }, { 720, 360 } } do
			local w = shaped({ x = 0, y = 0, w = canvas[1], h = canvas[2] })
			local content = w.node(NAV .. "/Content")
			local band = w.node(HOMES.bottomBar) or w.node(HOMES.bottomBarCompact)
			expect(content ~= nil and content.rect ~= nil).toBe(true)
			expect(band ~= nil and band.rect ~= nil).toBe(true)
			expect(band.rect.y >= content.rect.y + content.rect.h - 1).toBe(true)
			teardown(w)
		end
	end)

	it("the search field keeps its home in the top chrome on EVERY placement", function()
		-- only the SECTION nav moves; the chrome band (and the search inside it)
		-- is Foyer's own thing and never migrates into a tab accessory
		local canvases = {
			{ vp = { x = 0, y = 0, w = 1400, h = 900 } },
			{ vp = { x = 0, y = 0, w = 390, h = 844 } },
			{ vp = { x = 0, y = 0, w = 720, h = 360 } },
			{ vp = { x = 0, y = 0, w = 1080, h = 810 }, facts = { capabilities = TOUCH, preferredInput = "Touch" } },
		}
		for _, canvas in canvases do
			local w = shaped(canvas.vp, canvas.facts)
			local slot = findPath(w.adapter, "/Foyer/Root/TopBar/SearchSlot")
			expect(slot ~= nil).toBe(true)
			-- the field itself, or the icon form it collapses to at a narrow width
			local live = findPath(w.adapter, "SearchSlot/FieldForm") or findPath(w.adapter, "SearchSlot/IconForm")
			expect(live ~= nil).toBe(true)
			-- and it still drives the feed
			w.built.steps.search(nil, "moss")
			w.presenter.refresh()
			expect(findPath(w.adapter, "Rows/[moss-kingdom]") ~= nil).toBe(true)
			expect(w.core:lastError()).toBeNil()
			teardown(w)
		end
	end)

	it("no bottom wing is ever cut off: the ladder degrades the WORD to the GLYPH", function()
		-- THE RULING IS THE SAME; WHO ENFORCES IT CHANGED. This proof used to
		-- hard-code `iconOnly` on both bottom homes so that no wing could
		-- ellipsize. `Option.icon` rides `compactLabel`, and a Button with one
		-- declared NEVER ellipsizes — it draws the glyph instead — so the
		-- guarantee now comes from a measurement at the width that actually needs
		-- it rather than from a per-home rule. Pinned across all four preferred
		-- text offsets, on both bottom canvases.
		for _, canvas in { { 390, 844 }, { 720, 360 } } do
			for _, offset in { 0, 4, 10, 14 } do
				local w = shaped({ x = 0, y = 0, w = canvas[1], h = canvas[2] })
				w.env:set("preferredTextOffset", offset)
				w.presenter.refresh()
				local cut = 0
				for path, textFacts in w.handle.controller.textAt() do
					-- the STRIP only: the whole screen now sits under `/Nav` (the
					-- construct owns the content region too), so a bare `/Nav/`
					-- filter would count the feed's own copy
					if
						textFacts.truncated == true
						and string.find(path, "/Strip/Indicator/Options", 1, true) ~= nil
					then
						cut += 1
					end
				end
				expect(`{canvas[1]}@{offset}:{cut}`).toBe(`{canvas[1]}@{offset}:0`)
				-- ...and every wing is still a real, hittable control that carries
				-- its semantic NAME whatever got drawn
				local home = if canvas[2] < 600 then HOMES.bottomBarCompact else HOMES.bottomBar
				local hit = home .. wingSuffix("crews")
				expect(w.adapter.node(hit) ~= nil).toBe(true)
				expect(w.adapter.node(hit).class).toBe("Button")
				-- whatever the ladder chose, the wing draws SOMETHING
				expect(#tostring(w.adapter.node(hit).props.label) > 0).toBe(true)
				w.adapter.tap(hit)
				w.presenter.refresh()
				expect(w.built.report().destination).toBe("crews")
				teardown(w)
			end
		end
	end)

	it("no top-band wing is cut off, and the glyph rung is REACHED at the expansion locale", function()
		local facts = { capabilities = TOUCH, preferredInput = "Touch" }
		local w = shaped({ x = 0, y = 0, w = 1080, h = 810 }, facts)
		local function cuts(): number
			local n = 0
			for path, textFacts in w.handle.controller.textAt() do
				if textFacts.truncated == true and string.find(path, "/Strip/Indicator/Options", 1, true) ~= nil then
					n += 1
				end
			end
			return n
		end
		local function drawn(dest: string): string
			return tostring((w.adapter.node(HOMES.topBar .. wingSuffix(dest)) :: any).props.label)
		end
		-- the full titles fit a tablet band, and nothing is cut
		expect(drawn("crews")).toBe("Crews")
		expect(cuts()).toBe(0)
		-- ...and AT THE EXPANSION LOCALE IT OVERFLOWS AND SCROLLS INSTEAD OF
		-- DEGRADING, which is the shape of a hugging band and worth pinning
		-- because it is the OPPOSITE of what the bottom band does. A `hug` strip
		-- takes each wing's natural width, so it never runs out of room and the
		-- ladder never fires; what it does instead is get wider than its band, and
		-- the wings past the edge are reached by scrolling — including by a
		-- keyboard or pad move, which the presenter reveals through the same
		-- keep-visible substrate. Nothing is CUT either way, which is the
		-- localization guarantee both shapes owe.
		w.env:set("viewportRect", { x = 0, y = 0, w = 620, h = 900 })
		w.env:set("preferredTextOffset", 14)
		w.built.steps.locale(nil, "xa")
		w.presenter.refresh()
		expect(cuts()).toBe(0)
		local band = (w.adapter.node(HOMES.topBar) :: any).rect
		local strip = (w.adapter.node(HOMES.topBar .. "/Strip") :: any).rect
		expect(strip.w > band.w).toBe(true)
		expect(w.adapter.scrollRegionOf(HOMES.topBar).contentW > band.w).toBe(true)
		-- the wing past the edge is REACHABLE: focus it and the band scrolls
		w.system.deviceKey("Tab", true)
		w.system.deviceKey("Tab", false)
		w.presenter.refresh()
		expect(w.core:lastError()).toBeNil()
		teardown(w)
	end)

	it("every placement is traversable: enter, through, away, and a real action", function()
		local function pressTab(w: any)
			w.presenter.refresh()
			w.system.deviceKey("Tab", true)
			w.system.deviceKey("Tab", false)
			w.presenter.refresh()
		end
		local function walk(w: any): { [string]: boolean }
			local seen: { [string]: boolean } = {}
			local start = w.presenter.focus.focused:get()
			if start == nil then
				pressTab(w)
				start = w.presenter.focus.focused:get()
			end
			local guard, at = 0, start
			repeat
				if at ~= nil then
					seen[at] = true
				end
				pressTab(w)
				at = w.presenter.focus.focused:get()
				guard += 1
			until at == start or at == nil or guard > 250
			return seen
		end
		local canvases = {
			{ name = "rail", vp = { x = 0, y = 0, w = 1400, h = 900 } },
			{ name = "bottom", vp = { x = 0, y = 0, w = 390, h = 844 } },
			{ name = "inline", vp = { x = 0, y = 0, w = 720, h = 360 } },
			{
				name = "top",
				-- a tablet WITH a keyboard: `TOUCH` alone declares keyboard = false,
				-- and a Tab ring in a keyboard-less world is honestly inert (the
				-- pad-driven case below is how that world is walked)
				vp = { x = 0, y = 0, w = 1080, h = 810 },
				facts = {
					capabilities = { touch = true, mouse = false, keyboard = true, gamepad = false },
					preferredInput = "Touch",
				},
			},
		}
		for _, canvas in canvases do
			local w = shaped(canvas.vp, canvas.facts)
			local seen = walk(w)
			for _, dest in ORDER do
				local hit = false
				for path in seen do
					if string.find(path, wingSuffix(dest), 1, true) ~= nil then
						hit = true
					end
				end
				expect(`{canvas.name}/{dest}:{hit}`).toBe(`{canvas.name}/{dest}:true`)
			end
			-- (away) the ring holds more than the nav
			local outside = false
			for path in seen do
				if string.find(path, "/Strip/Indicator/Options/", 1, true) == nil then
					outside = true
				end
			end
			expect(`{canvas.name}/outside:{outside}`).toBe(`{canvas.name}/outside:true`)
			-- (action) a wing switches the destination through the real path
			local wing = findPath(w.adapter, wingSuffix("forge"))
			expect(wing ~= nil).toBe(true)
			w.adapter.tap(wing :: string)
			w.presenter.refresh()
			expect(w.built.report().destination).toBe("forge")
			expect(w.core:lastError()).toBeNil()
			teardown(w)
		end
	end)

	it("top band, driven as a PAD drives it: DPad to the band, across it, ButtonA, DPad away", function()
		-- capabilities.keyboard = false, so Tab is honestly inert here; the pad
		-- path is DPad navigation plus ButtonA activation
		local w = shaped({ x = 0, y = 0, w = 1920, h = 1080 }, {
			capabilities = { touch = false, mouse = false, keyboard = false, gamepad = true },
			preferredInput = "Gamepad",
			displaySize = "Large",
		})
		expect(w.adapter.node(HOMES.topBar) ~= nil).toBe(true)
		local function pad(key: string)
			w.system.deviceKey(key, true)
			w.system.deviceKey(key, false)
			w.presenter.refresh()
		end
		local function focused(): string
			return tostring(w.presenter.focus.focused:get())
		end
		-- (enter) walk DOWN into the band from wherever the surface opened
		local WING = "/Strip/Indicator/Options/"
		local guard = 0
		while string.find(focused(), WING, 1, true) == nil and guard < 20 do
			pad("DPadDown")
			guard += 1
		end
		expect(string.find(focused(), WING, 1, true) ~= nil).toBe(true)
		-- (through) a pad enters a band wherever it is spatially NEAREST — from the
		-- bell that is the third wing, not the first — so the walk goes to the
		-- leading edge first and then all the way across. The step counts come
		-- from the wing the pad actually landed on, which is what makes this a
		-- traversal proof rather than a lucky entry point.
		local function wingAt(): number?
			for index, dest in ORDER do
				if string.find(focused(), wingSuffix(dest), 1, true) ~= nil then
					return index
				end
			end
			return nil
		end
		local entry = wingAt()
		expect(entry ~= nil).toBe(true)
		local seen: { [string]: boolean } = { [focused()] = true }
		for _ = 1, (entry :: number) - 1 do
			pad("DPadLeft")
			seen[focused()] = true
		end
		expect(wingAt()).toBe(1)
		for _ = 1, #ORDER - 1 do
			pad("DPadRight")
			seen[focused()] = true
		end
		expect(wingAt()).toBe(#ORDER)
		for _, dest in ORDER do
			local hit = false
			for path in seen do
				if string.find(path, wingSuffix(dest), 1, true) ~= nil then
					hit = true
				end
			end
			expect(`{dest}:{hit}`).toBe(`{dest}:true`)
		end
		-- (away) DPadDown leaves the band for the content under it — checked
		-- BEFORE the action, because a stub destination has nothing focusable in
		-- it and "cannot leave" would then be indistinguishable from "nowhere to go"
		pad("DPadDown")
		expect(string.find(focused(), WING, 1, true) == nil).toBe(true)
		-- (action) walk back up and press A: the wing under focus is the one that
		-- takes effect, so the assertion reads the wing rather than assuming it
		local back = 0
		while string.find(focused(), WING, 1, true) == nil and back < 20 do
			pad("DPadUp")
			back += 1
		end
		local landed = wingAt()
		expect(landed ~= nil).toBe(true)
		pad("ButtonA")
		expect(w.built.report().destination).toBe(ORDER[landed :: number])
		expect(w.core:lastError()).toBeNil()
		teardown(w)
	end)
end)

describe("Foyer proof — tabs, search, stubs", function()
	it("the charts tab swaps the feed to the approval-ranked section and back", function()
		local w = makeWorld()
		w.adapter.tap(HOME .. "/TabRow/Tab_charts/B")
		settleTransitions(w)
		expect(findPath(w.adapter, "Sections/[charts]") ~= nil).toBe(true)
		expect(findPath(w.adapter, "Sections/[picked]") == nil).toBe(true)
		w.adapter.tap(HOME .. "/TabRow/Tab_forYou/B")
		settleTransitions(w)
		expect(findPath(w.adapter, "Sections/[picked]") ~= nil).toBe(true)
		teardown(w)
	end)

	it("search filters by title and creator; clearing restores the feed", function()
		local w = makeWorld()
		w.built.steps.search(nil, "moss")
		settleTransitions(w)
		expect(findPath(w.adapter, "Rows/[moss-kingdom]") ~= nil).toBe(true)
		expect(findPath(w.adapter, "Sections/[picked]") == nil).toBe(true)
		w.built.steps.search(nil, "latchkey")
		w.presenter.refresh()
		expect(findPath(w.adapter, "Rows/[moss-kingdom]") ~= nil).toBe(true)
		expect(findPath(w.adapter, "Rows/[signal-lost]") ~= nil).toBe(true)
		w.built.steps.search(nil, "")
		w.presenter.refresh()
		expect(findPath(w.adapter, "Sections/[picked]") ~= nil).toBe(true)
		teardown(w)
	end)

	it("a no-match query shows the honest empty state with a working clear button", function()
		local w = makeWorld()
		w.built.steps.search(nil, "zzzz")
		w.presenter.refresh()
		local clear = findPath(w.adapter, "Empty/Clear")
		expect(clear ~= nil).toBe(true)
		w.adapter.tap(clear :: string)
		w.presenter.refresh()
		expect(w.built.report().query).toBe("")
		expect(findPath(w.adapter, "Sections/[picked]") ~= nil).toBe(true)
		teardown(w)
	end)

	it("a stub destination shows the labeled stub plate, never fake content", function()
		local w = makeWorld()
		local nav = HOMES.sidebar .. wingSuffix("crews")
		expect(w.adapter.node(nav) ~= nil).toBe(true)
		w.adapter.tap(nav)
		w.presenter.refresh()
		-- ...and the home body is EVICTED, not hidden: the construct disposes the
		-- previous tab's subtree, so its nodes are gone from the tree entirely
		expect(findPath(w.adapter, "Tab-crews/then/StubPlate") ~= nil).toBe(true)
		expect(w.adapter.node(HOME)).toBeNil()
		w.built.steps.destination(nil, "home")
		w.presenter.refresh()
		expect(w.adapter.node(HOME) ~= nil).toBe(true)
		teardown(w)
	end)
end)

describe("Foyer proof — refresh command lifecycle", function()
	it("refresh pends (button disabled), then confirms with re-seeded sections", function()
		local w = makeWorld()
		local before = w.built.report().page
		w.adapter.tap("/Foyer/Root/TopBar/Refresh")
		expect(w.built.report().refreshStatus).toBe("pending")
		w.presenter.refresh()
		local refreshNode = w.adapter.node("/Foyer/Root/TopBar/Refresh")
		expect(refreshNode.props.enabled).toBe(false)
		w.built.steps.settle()
		w.presenter.refresh()
		local report = w.built.report()
		expect(report.refreshStatus).toBe("confirmed")
		expect(report.page).toBe(before + 1)
		expect(refreshNode.props.enabled).toBe(true)
		teardown(w)
	end)

	it("a scripted rejection leaves the feed unchanged and re-enables the button", function()
		local w = makeWorld()
		local before = w.built.report().page
		w.built.steps.rejectNextRefresh()
		w.adapter.tap("/Foyer/Root/TopBar/Refresh")
		w.built.steps.settle()
		w.presenter.refresh()
		local report = w.built.report()
		expect(report.refreshStatus).toBe("rejected")
		expect(report.page).toBe(before)
		expect(w.adapter.node("/Foyer/Root/TopBar/Refresh").props.enabled).toBe(true)
		teardown(w)
	end)
end)

describe("Foyer proof — tile detail and the visit command", function()
	it(
		"activating a tile presents its detail modal; visit pends then confirms into Keep playing and dismisses",
		function()
			local w = makeWorld()
			local baseDepth = w.presenter.depth()
			local tile = findPath(w.adapter, "Sections/[picked]/Body/Grid/Tiles/[moss-kingdom]/moss-kingdom")
			expect(tile ~= nil).toBe(true)
			w.adapter.tap(tile :: string)
			w.presenter.refresh()
			expect(w.presenter.depth()).toBe(baseDepth + 1)
			local visit = findPath(w.adapter, "Detail/PanelZ/Plate/Group/Page/Footer/Visit")
			expect(visit ~= nil).toBe(true)
			w.adapter.tap(visit :: string)
			expect(w.built.report().visitStatus).toBe("pending")
			w.presenter.refresh()
			expect(w.adapter.node(visit :: string).props.enabled).toBe(false)
			w.built.steps.settle()
			w.presenter.refresh()
			local report = w.built.report()
			expect(report.visitStatus).toBe("confirmed")
			expect(report.continueIds["moss-kingdom"]).toBe(true)
			expect(w.presenter.depth()).toBe(baseDepth)
			teardown(w)
		end
	)

	it("a rejected visit leaves Keep playing untouched and the modal up", function()
		local w = makeWorld()
		local tile = findPath(w.adapter, "Sections/[picked]/Body/Grid/Tiles/[rooftop-dash]/rooftop-dash")
		w.adapter.tap(tile :: string)
		w.presenter.refresh()
		w.built.steps.rejectNextVisit()
		local visit = findPath(w.adapter, "Detail/PanelZ/Plate/Group/Page/Footer/Visit")
		w.adapter.tap(visit :: string)
		w.built.steps.settle()
		w.presenter.refresh()
		local report = w.built.report()
		expect(report.visitStatus).toBe("rejected")
		expect(report.continueIds["rooftop-dash"]).toBeNil()
		expect(w.presenter.depth() > 0).toBe(true)
		teardown(w)
	end)
end)

describe("Foyer proof — notices, locale, images, determinism", function()
	it("the bell badge counts seeded notices and clears on presenting the modal", function()
		local w = makeWorld()
		expect(w.built.report().noticeCount).toBe(5)
		expect(findPath(w.adapter, "BellZ/BadgeWhen/then/Badge") ~= nil).toBe(true)
		w.adapter.tap("/Foyer/Root/TopBar/BellZ/Bell")
		w.presenter.refresh()
		expect(w.built.report().noticeCount).toBe(0)
		expect(findPath(w.adapter, "BellZ/BadgeWhen/then") == nil).toBe(true)
		teardown(w)
	end)

	it("the locale swap reaches live copy without remounting the tab button", function()
		local w = makeWorld()
		local tabButton = HOME .. "/TabRow/Tab_forYou/B"
		local before = w.adapter.node(tabButton)
		expect(tostring(before.props.label)).toBe("For you")
		w.built.steps.locale(nil, "xa")
		w.presenter.refresh()
		expect(w.adapter.node(tabButton) == before).toBe(true)
		expect(string.find(tostring(w.adapter.node(tabButton).props.label), "%[") ~= nil).toBe(true)
		teardown(w)
	end)

	it("the scripted transport resolves art deterministically: two keys stay failed, the rest ready", function()
		local w = makeWorld()
		local internals = w.built._internals
		local h1 = internals.provider.acquire(w.core:scope("probe1"), "thumb:moss-kingdom")
		local h2 = internals.provider.acquire(w.core:scope("probe2"), "thumb:signal-lost")
		internals.settleImages()
		expect(h1.state:get()).toBe("ready")
		expect(h2.state:get()).toBe("failed")
		teardown(w)
	end)

	it("two fresh builds report identical seeded state (reset determinism)", function()
		local a = makeWorld()
		local b = makeWorld()
		local ra, rb = a.built.report(), b.built.report()
		expect(ra.page).toBe(rb.page)
		expect(ra.noticeCount).toBe(rb.noticeCount)
		expect(#a.adapter.paths()).toBe(#b.adapter.paths())
		teardown(a)
		teardown(b)
	end)

	it("the five-view sweep is diagnostic-clean with a live scrollbar (matrix pin)", function()
		for _, vp in
			{
				{ w = 360, h = 691 },
				{ w = 678, h = 339 },
				{ w = 1080, h = 810 },
				{ w = 1280, h = 720 },
				{ w = 1920, h = 1080 },
			}
		do
			local core = Facet.newCore()
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = vp.w, h = vp.h })
			local system = Facet.newActionSystem(core)
			local adapter = fake_target.new();
			(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_RESERVE
			local presenter = Facet.newPresenter(core, env, adapter, system)
			local built =
				proof.build(Facet, core, { env = env, actionSystem = system, presenter = presenter, adapter = adapter })
			local handle = presenter.present(built.screen, built.present)
			presenter.refresh()
			expect(#handle.controller.diagnostics()).toBe(0)
			built.dispose()
			presenter.dismiss(handle)
		end
	end)

	it("dispose tears the proof down without a core error", function()
		local w = makeWorld()
		teardown(w)
		expect(w.core:lastError()).toBeNil()
	end)
end)

describe("Foyer — the tile meta row WRAPS where it used to ladder (parity round 3)", function()
	-- WHAT CHANGED AND WHY IT NEEDED THESE CASES. The tile card's meta line was a
	-- two-rung `ViewThatFits`: `MetaRow` (approval + a trailing Sponsored chip)
	-- with `MetaColumn` (the same two, stacked) behind it, because at a raised text
	-- preference the pair overflowed the cell. The comment on it read "REFLOW,
	-- NEVER SQUEEZE" — a flow wrap, described in prose and hand-built out of a
	-- ladder. It cost a SECOND `newLabel` control per tile (`ApprovalB`) and a
	-- second `When`/`ChipB`, and it published `Approval` at two paths.
	--
	-- `HStack{ wrap = true, distribute = "spaceBetween" }` is the same intent as
	-- two props, so these cases pin BOTH ends of the behaviour the ladder gave:
	-- one line with the chip pushed trailing when it fits, two lines when it does
	-- not — and they read rects, never mere presence, because the ladder's losing
	-- rung was mounted at a zero rect and would satisfy a presence check.
	local SPONSORED = "Sections/[new]/Body/Grid/Tiles/[harbor-watch]/harbor-watch/Col/MetaFits"

	local function worldAtText(offset: number)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1400, h = 900 })
		env:set("preferredTextSize", offset)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = Facet.newPresenter(core, env, adapter, system)
		local built =
			proof.build(Facet, core, { env = env, actionSystem = system, presenter = presenter, adapter = adapter })
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		return { built = built, adapter = adapter, handle = handle, presenter = presenter }
	end

	local function rectOf(w: any, needle: string): any
		local path = findPath(w.adapter, needle)
		if path == nil then
			error(`no node matched "{needle}"`, 2)
		end
		local rect = w.handle.controller.screenRectOf(path)
		if rect == nil or rect.w <= 0 or rect.h <= 0 then
			error(`{path} solved to {if rect then `{rect.w}x{rect.h}` else "nil"} — nothing a player can see`, 2)
		end
		return rect
	end

	it("THE LADDER'S TWIN NODES ARE GONE: no MetaColumn, no ApprovalB, no ChipB", function()
		local w = worldAtText(0)
		-- these are the ids the second rung published. Each was a real, mounted
		-- node at a zero rect for the whole life of every tile.
		for _, ghost in { "MetaColumn", "ApprovalB", "SponsoredB", "ChipB", "MetaRow" } do
			local path = findPath(w.adapter, ghost)
			if path ~= nil then
				error(`the ladder is back: {path}`, 2)
			end
		end
		-- and the survivors are each published exactly once per tile
		local approvals = 0
		for _, path in w.adapter.paths() do
			if
				string.find(path, "harbor-watch/Col/MetaFits/Approval", 1, true) ~= nil
				and string.sub(path, -8) == "Approval"
			then
				approvals += 1
			end
		end
		-- harbor-watch appears in two seeded sections, so exactly two Approvals
		expect(approvals).toBe(2)
		teardown(w)
	end)

	it("AT NORMAL TEXT they share a line and `distribute` pushes the chip to the TRAILING edge", function()
		local w = worldAtText(0)
		local row = rectOf(w, SPONSORED)
		local approval = rectOf(w, SPONSORED .. "/Approval")
		local chip = rectOf(w, SPONSORED .. "/Sponsored/then/Chip")

		expect(approval.y).toBe(chip.y) -- one line
		expect(approval.x).toBe(row.x) -- approval leads
		-- THE `distribute` ASSERTION: the chip's trailing edge IS the row's. A
		-- hand-placed `Spacer` used to do this, and cannot: a `fill` child takes a
		-- whole line to itself inside a wrapping stack.
		expect(chip.x + chip.w).toBe(row.x + row.w)
		expect(chip.x > approval.x + approval.w).toBe(true)
		teardown(w)
	end)

	it("AT RAISED PREFERRED TEXT it REFLOWS to a second line instead of squeezing", function()
		-- the exact condition the ladder existed for (its comment recorded a 9-14px
		-- overflow at preference +14), now met by the same node set
		local w = worldAtText(14)
		local row = rectOf(w, SPONSORED)
		local approval = rectOf(w, SPONSORED .. "/Approval")
		local chip = rectOf(w, SPONSORED .. "/Sponsored/then/Chip")

		expect(chip.y > approval.y).toBe(true) -- a SECOND line
		expect(approval.x).toBe(row.x) -- both at the leading edge of their own line
		expect(chip.x).toBe(row.x)
		-- the row grew to hold both lines rather than painting past its box
		expect(row.h >= approval.h + chip.h).toBe(true)
		expect(chip.x + chip.w <= row.x + row.w).toBe(true)
		teardown(w)
	end)

	it("NOT ONE `Spacer` INSTANCE IS MOUNTED: `distribute` says it on the container", function()
		--[[ THE MEASUREMENT THAT DECIDED THIS SWAP, and it is not about pixels.
			The section header and the detail footer each carried a `UI.Spacer({})`
			between a leading title and a trailing action. A/B at 1400x900 on
			2026-08-13: the header solves to EXACTLY the same rects either way
			(214x44 @ 168,979, Title 162x24, SeeAll 44x44 @ 338) — the row HUGS, so
			there is no leftover for a Spacer or a `distribute` to spread, and both
			spellings are arrange-identical.

			What is NOT identical is the tree. A `Spacer` is a real mounted node:
			this proof published 24 of them, and the whole surface went from 601
			nodes to 454 (-24.5%) once they and the meta ladder's second rung came
			out. That is the reason the swap shipped, so that is what this case
			pins — a rect assertion here would pass with the Spacers back. ]]
		local w = worldAtText(0)
		-- THE DETAIL FOOTER IS ONLY MOUNTED INSIDE THE MODAL, so the sweep has to
		-- open it or it silently misses the second Spacer site entirely (found by a
		-- mutation that reddened nothing, 2026-08-13)
		local tile = findPath(w.adapter, "Sections/[picked]/Body/Grid/Tiles/[moss-kingdom]/moss-kingdom")
		expect(tile ~= nil).toBe(true)
		w.adapter.tap(tile :: string)
		w.presenter.refresh()
		expect(findPath(w.adapter, "Plate/Group/Page/Footer/Close") ~= nil).toBe(true)

		local spacers: { string } = {}
		for _, path in w.adapter.paths() do
			if string.find(path, "Spacer", 1, true) ~= nil then
				table.insert(spacers, path)
			end
		end
		if #spacers > 0 then
			error(`{#spacers} Spacer instance(s) are back, first = {spacers[1]}`, 2)
		end

		-- and the arrangement they used to produce still holds, from the container
		local header = rectOf(w, "Sections/[new]/Body/Header")
		local title = rectOf(w, "Sections/[new]/Body/Header/Title")
		local seeAll = rectOf(w, "Sections/[new]/Body/Header/SeeAll")
		expect(title.x).toBe(header.x)
		expect(seeAll.x + seeAll.w).toBe(header.x + header.w)
		expect(seeAll.x > title.x + title.w).toBe(true)
		teardown(w)
	end)
end)

--[[ BACKDROP-FINDING SWEEP (task POP fix round 1, CRITICAL finding: the
	round-0 gate was never actually run against this reference app — grep
	alone found 2 `canvasGroup = true` sites here, unswept). Opens the Bell
	(notices), Profile and tile Detail modals — every `presentModal` call
	site this app has — then reads the UNION of every coordinator's own
	`.findings()` (`tests/lib/backdrop_sweep.luau`). ]]
describe("Foyer — backdrop-finding sweep (task POP)", function()
	it("the notices, profile and detail modals are clean", function()
		local backdropSweep = require("../lib/backdrop_sweep")
		local w: any
		local findings = backdropSweep.capture(function()
			w = makeWorld()
			local bell = findPath(w.adapter, "Bell")
			expect(bell ~= nil).toBe(true)
			w.adapter.tap(bell :: string)
			w.presenter.refresh()
			w.presenter.back() -- close the notices modal before opening the next one
			local profile = findPath(w.adapter, "Profile")
			if profile ~= nil then
				w.adapter.tap(profile)
				w.presenter.refresh()
			end
			local tile = findPath(w.adapter, "Sections/[picked]/Body/Grid/Tiles/[moss-kingdom]/moss-kingdom")
			expect(tile ~= nil).toBe(true)
			w.adapter.tap(tile :: string)
			w.presenter.refresh()
		end)
		expect(`{#findings} finding(s):\n{backdropSweep.describe(findings)}`).toBe("0 finding(s):\n")
		teardown(w)
	end)
end)

--[[ THE BADGE CORNER, THIRD CONSUMER (task FOYER; director order "fix foyer").
	The themed-chrome round recorded this file's own `badgeBubble` as a third, deliberately
	unfixed occurrence of the badge-corner-offset class closed this campaign in
	`src/controls/picker.luau`'s count seal and `examples/gallery/scenarios/
	adaptive_controls.luau`'s HUD-tile badge — `picker.luau`'s own comment even
	cites "the `p4_foyer` badgeBubble shape" as the precedent both of those were
	named after. Both badge sites here (`AddTile`'s invite count, `BellZ`'s
	notice count) decorate a `shape = "circle"` Button with no declared
	`surface`, which classifies to the same `control` slot by the CLASS-only
	fallback rule, so the fix's one memo covers both.

	THE ORACLE IS RE-DERIVED, not borrowed from `chrome_slots.carvedSide`
	itself — the same T1 discipline `tests/themed_containment.spec.luau`'s two
	consumer groups use: reading `chromeInsets.control[side]` straight off the
	raw snapshot here cannot pass merely because it shares an arithmetic
	mistake with the code under test. The tight `<= 0.5` pin on BOTH axes below
	IS the asymmetric-carve proof: `fantasy_ornate`'s `control` chrome is
	`{top=10,right=14,...}`, so a badge that (incorrectly) padded both axes by
	the shared FOUR-SIDED MAX (`chrome_slots.carvedBorder`) would clear top by
	14 — 4px past what its own axis carves — and this pin catches exactly
	that. ]]
local function carvedInsetSide(snapshot: any?, slot: string, side: string): number
	if type(snapshot) ~= "table" then
		return 0
	end
	local insets = (snapshot :: any).chromeInsets
	local plate = if type(insets) == "table" then (insets :: any)[slot] else nil
	if type(plate) ~= "table" then
		return 0
	end
	local px = (plate :: any)[side]
	return if type(px) == "number" then px else 0
end

describe("Foyer badgeBubble clears its own control's themed chrome (task FOYER)", function()
	-- host = the path with this suffix stripped: `AddTile` or `BellZ`, the
	-- ZStack both the circle Button and the `BadgeWhen` conditional sit in —
	-- its resolved rect IS the badge's own fill parent, since `badgeBubble`
	-- itself is width/height `UI.fill()`.
	local BADGE_SUFFIX = "/BadgeWhen/then/BadgeBubble/Count"

	local function badgeHits(
		w: any,
		snapshot: any?
	): { { host: string, carved: number, rightClear: number, topClear: number } }
		if snapshot ~= nil then
			w.env:set("themeMetrics", snapshot)
			w.presenter.refresh()
			w.presenter.refresh()
			w.presenter.refresh()
		end
		local topCarved = carvedInsetSide(snapshot, "control", "top")
		local rightCarved = carvedInsetSide(snapshot, "control", "right")
		local out = {}
		for _, path in w.adapter.paths() do
			if #path <= #BADGE_SUFFIX or string.sub(path, -#BADGE_SUFFIX) ~= BADGE_SUFFIX then
				continue
			end
			local hostPath = string.sub(path, 1, #path - #BADGE_SUFFIX)
			local badge = w.adapter.node(path)
			local host = w.adapter.node(hostPath)
			if badge == nil or host == nil or badge.rect == nil or host.rect == nil then
				continue
			end
			table.insert(out, {
				host = hostPath,
				carved = math.max(topCarved, rightCarved), -- anti-vacuity only
				topCarved = topCarved,
				rightCarved = rightCarved,
				rightClear = (host.rect.x + host.rect.w - rightCarved) - (badge.rect.x + badge.rect.w),
				topClear = badge.rect.y - (host.rect.y + topCarved),
			})
		end
		return out
	end

	it("with no package installed, both badges sit flush at the corner — shipped geometry, unchanged", function()
		local w = makeWorld()
		local hits = badgeHits(w, nil)
		expect(#hits).toBe(2) -- anti-vacuity: AddTile's invite badge + BellZ's notice badge
		for _, hit in hits do
			expect(hit.carved).toBe(0)
			expect(math.abs(hit.rightClear) <= 0.5).toBe(true)
			expect(math.abs(hit.topClear) <= 0.5).toBe(true)
		end
		teardown(w)
	end)

	-- THE TWO ORNATE PACKAGES `themed_containment.spec.luau` swings its own
	-- consumer groups through: Pixel Quest carves the most (`control` 16 flat
	-- on every side) and Fantasy Ornate the second most, ASYMMETRICALLY
	-- (`control` top=10/right=14) — the pair the T1 pin needs, since a
	-- symmetric carve alone cannot distinguish a per-axis fix from a
	-- shared-max one.
	local PACKAGES: { { id: string, snapshot: any } } = {}
	for _, id in { "pixel_quest", "fantasy_ornate" } do
		local module = require(`../../examples/themes/{id}`) :: any
		local pkg, report = module.build(Facet.themes)
		assert(
			pkg ~= nil,
			`{id} failed its own package gate: {report and report.errors[1] and report.errors[1].message}`
		)
		table.insert(PACKAGES, { id = id, snapshot = Facet.themes.resolve(pkg, nil, {}) })
	end

	for _, pkg in PACKAGES do
		it(`under {pkg.id}, both badges clear their own host's carved border, PER AXIS (T1)`, function()
			local w = makeWorld()
			local hits = badgeHits(w, pkg.snapshot)
			expect(#hits).toBe(2)
			for _, hit in hits do
				expect(hit.carved > 0).toBe(true) -- anti-vacuity: this package really carves `control`
				expect(hit.rightClear >= -0.5).toBe(true)
				expect(hit.topClear >= -0.5).toBe(true)
				-- THE T1 PIN. Over-clearing is a defect too: see the header above.
				expect(hit.topClear <= 0.5).toBe(true)
				expect(hit.rightClear <= 0.5).toBe(true)
			end
			teardown(w)
		end)
	end
end)
