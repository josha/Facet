--!strict
-- Reference proof "Glade" — E1 loop pins (reference-app-validation).
--
-- These are the headless half of RA-P1: every state transition the representative
-- loop passes through, both commerce outcomes, the drain/low/empty derivations,
-- the toast schedule, focus order, the pseudo-locale's expansion contract, and
-- the determinism pin (same seed + same steps ⇒ identical dump).
--
-- The proof is driven the way a client drives it — mounted through the public
-- presenter over the headless FakeTarget, and ACTIVATED THROUGH THE SAME NODES A
-- FINGER WOULD HIT (`adapter.tap` on the real path). A test that called the
-- proof's own verbs would prove the services and nothing about whether the
-- screen can reach them, which is exactly the class of defect the stage exists
-- to catch, so `tap` is the default here and `steps`/`api` appear only where a
-- headless run genuinely has no on-screen equivalent (advancing the clock).

local fs = require("@lune/fs")

local t = require("../lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../../src") :: any
local fake_target = require("../lib/fake_target")
local adapter_source = require("../lib/adapter_source")
local seedData = require("../../examples/reference/p1_glade/content/seed") :: any
local strings = require("../../examples/reference/p1_glade/content/strings") :: any

local parchment = require("../../examples/themes/fantasy_parchment")

local proof = require("../../examples/reference/p1_glade") :: any

local FRAME = 1 / 60

-- A complete headless stack plus the two helpers every case below uses: `find`
-- resolves a node by the tail of its path (the proof's ids are stable; the tree
-- above them is the framework's business), and `tap` drives the real activation
-- closure the engine would call.
local function world(width: number?, height: number?): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = width or 1200, h = height or 800 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
	local built = proof.build(Facet, core, {
		env = env,
		actionSystem = system,
		presenter = presenter,
		adapter = adapter,
	})
	local handle = presenter.present(built.screen, built.present)
	built.api.bindHandle(handle)
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
	function self.find(tail: string): string?
		for _, path in adapter.paths() do
			if string.sub(path, -#tail) == tail then
				return path
			end
		end
		return nil
	end
	function self.node(tail: string): any
		local path = self.find(tail)
		return if path ~= nil then adapter.node(path) else nil
	end
	function self.textOf(tail: string): string?
		local node = self.node(tail)
		return if node ~= nil then tostring(node.props.text) else nil
	end
	function self.tap(tail: string)
		local path = self.find(tail)
		if path == nil then
			error(`no mounted node whose path ends '{tail}'`, 2)
		end
		adapter.tap(path, { source = "pointer", pointer = "mouse" })
		presenter.refresh()
	end
	-- run real frames: transitions, springs, the toast schedule and the proof's
	-- own injected clock all ride the presenter's one tick
	function self.tick(frames: number?)
		for _ = 1, (frames or 30) do
			presenter.tick(FRAME)
		end
		presenter.refresh()
	end
	function self.report(): any
		return built.report()
	end
	function self.toastTexts(): { string }
		local out: { string } = {}
		for _, path in adapter.paths() do
			if string.find(path, "/__toast__/", 1, true) ~= nil then
				local node = adapter.node(path)
				if node ~= nil and node.class == "Text" then
					table.insert(out, tostring(node.props.text))
				end
			end
		end
		table.sort(out)
		return out
	end
	return self
end

--[[ THE NAV, AFTER §6. The shell is `Facet.Controls.TabView` now
	(framework-gaps-phase2 §6, the accessory-slot round): a section's button is a
	SEGMENT of the construct's one strip rather than a `Nav_<section>` Button this
	proof declared four times over. Two things follow, and both are why these are
	helpers rather than literals:

	  * the segment's own id is the strip's (`Opt<n>`), so a section is addressed
	    by its INDEX in the proof's own `SECTIONS` order — the one part of the nav
	    this file still owns;
	  * the path ABOVE it is the placement policy's business and changes with the
	    home, so every case below resolves a tail rather than a full path. ]]
local SECTION_ORDER = { "glades", "wisps", "flora", "keeper" }
local function navTail(section: string): string
	for index, name in SECTION_ORDER do
		if name == section then
			return `/Strip/Indicator/Options/Opt{index}`
		end
	end
	error(`no such section '{section}'`, 2)
end
-- ...and the reverse, for the ring walks: which section a focused path IS, or nil
local function navSection(path: string): string?
	if string.find(path, "/Nav/", 1, true) == nil or string.find(path, "/Strip/", 1, true) == nil then
		return nil
	end
	for index, name in SECTION_ORDER do
		local tail = `/Opt{index}`
		if string.sub(path, -#tail) == tail then
			return name
		end
	end
	return nil
end
local function isNavPath(path: string): boolean
	return navSection(path) ~= nil
end
-- the four homes the construct mounts its strip in, by tail
local RAIL = "/Nav/RailHome/then/RailShell/Rail"
local TOP_BAND = "/Nav/TopHome/then/TopBandCenter/TopBand"
-- the thumb-zone band is the CENTRED, hugging shape this proof declares
-- (`sizing = "hug"`), not the framework's default full-width one
local BOTTOM_BAND = "/Nav/BottomHome/then/BottomBandCenter/BottomBand"
local COMPACT_BAND = "/Nav/CompactHome/then/CompactBandCenter/CompactBand"

-- resolve a purchase command without also advancing thirty frames of motion
local function settle(w: any)
	w.built.api.advance(seedData.COMMAND_SECONDS + 0.01)
	w.presenter.refresh()
end

describe("Glade reference proof — module contract", function()
	it("exposes the scenario build contract", function()
		expect(type(proof.build)).toBe("function")
	end)

	it("mounts headlessly through the public presenter with no core error", function()
		local w = world()
		expect(w.find("/Glade/Nav") ~= nil).toBe(true)
		expect(w.core:lastError()).toBeNil()
		expect(w.report().proof).toBe("p1_glade")
		expect(w.report().seed).toBe(seedData.WORLD)
	end)

	it("publishes its spec substitutions in the report rather than only in comments", function()
		local subs = world().report().substitutions
		expect(type(subs.supplyGlow)).toBe("string")
		expect(string.find(subs.supplyGlow, "accent", 1, true) ~= nil).toBe(true)
		expect(string.find(subs.supplyGlow, "contentStrong", 1, true) ~= nil).toBe(true)
	end)
end)

describe("Glade S1: the overview grid (spec §7)", function()
	it("mounts one card per seeded glade, in creation order", function()
		local w = world()
		for _, glade in seedData.GLADES do
			expect(w.find("/GladeCard_" .. glade.id) ~= nil).toBe(true)
		end
		local order = w.report().supply
		expect(order[1].glade).toBe("mossholm")
		expect(order[5].glade).toBe("stillpond")
	end)

	it("shows all three supply states on the first frame — full, low and empty", function()
		local states: { [string]: boolean } = {}
		for _, row in world().report().supply do
			states[row.nectarState] = true
			states[row.dewState] = true
		end
		expect(states.full).toBe(true)
		expect(states.low).toBe(true)
		expect(states.empty).toBe(true)
	end)

	it("the favourite star is a SIBLING of the card, not inside its activation surface", function()
		local w = world()
		local card = w.find("/GladeCard_mossholm") :: string
		local star = w.find("/Fav_mossholm") :: string
		-- a focusable inside a Button's children is refused at construction; the
		-- star living beside the card is what keeps both verbs reachable
		expect(string.find(star, card .. "/", 1, true)).toBeNil()
		expect(w.report().favourites[1]).toBe("mossholm")
		w.tap("/Fav_mossholm")
		expect(#w.report().favourites).toBe(0)
		w.tap("/Fav_mossholm")
		expect(w.report().favourites[1]).toBe("mossholm")
	end)

	it("search filters case-insensitively and says so when nothing matches", function()
		local w = world()
		w.built.steps.search(nil, "MOSS")
		w.tick(40) -- a filtered-out row RETIRES rather than vanishing; let it finish
		expect(#w.built.api.state.filtered:get()).toBe(1)
		expect(w.find("/GladeCard_mossholm") ~= nil).toBe(true)
		expect(w.find("/GladeCard_stillpond")).toBeNil()

		w.built.steps.search(nil, "zzz")
		w.tick(40)
		expect(#w.built.api.state.filtered:get()).toBe(0)
		local copy = w.textOf("/NoMatchesBody/Copy") :: string
		expect(string.find(copy, "zzz", 1, true) ~= nil).toBe(true)
		-- and the empty state offers its own way out
		w.tap("/ClearSearch")
		expect(w.report().search).toBe("")
		w.tick(40)
		expect(w.find("/GladeCard_stillpond") ~= nil).toBe(true)
	end)

	it("a visit suggestion fills the filter with that glade's name", function()
		local w = world()
		-- v2 is the seeded current visit: Emberwisp at Mossholm
		expect(w.find("/Suggest_v2") ~= nil).toBe(true)
		w.tap("/Suggest_v2")
		expect(w.report().search).toBe("Mossholm")
		expect(#w.built.api.state.filtered:get()).toBe(1)
	end)

	it("the charm offer card is present while the tier is none and leaves on Dismiss", function()
		local w = world()
		expect(w.find("/OfferSee") ~= nil).toBe(true)
		w.tap("/OfferDismiss")
		w.tick(40)
		expect(w.find("/OfferSee")).toBeNil()
		expect(w.report().offerDismissed).toBe(true)
	end)
end)

describe("Glade: supply drain, low and empty (spec §1, §6)", function()
	it("nectar crosses low at 7.5 minutes and empty at 9, on the injected clock alone", function()
		local w = world()
		local supply = w.built.api.supply
		expect(supply.state("mossholm", "nectar"):get()).toBe("full")
		w.built.api.advance(seedData.DRAIN.nectar.low - 1)
		expect(supply.state("mossholm", "nectar"):get()).toBe("full")
		w.built.api.advance(2)
		expect(supply.state("mossholm", "nectar"):get()).toBe("low")
		w.built.api.advance(seedData.DRAIN.nectar.empty - seedData.DRAIN.nectar.low)
		expect(supply.state("mossholm", "nectar"):get()).toBe("empty")
		expect(supply.level("mossholm", "nectar"):get()).toBe(0)
	end)

	it("dew uses its own constants, and the two never share a threshold", function()
		local w = world()
		local supply = w.built.api.supply
		-- mossholm's dew is seeded 120s in, so it reaches low 660s later
		w.built.api.advance(seedData.DRAIN.dew.low - 120 - 1)
		expect(supply.state("mossholm", "dew"):get()).toBe("full")
		w.built.api.advance(2)
		expect(supply.state("mossholm", "dew"):get()).toBe("low")
		expect(seedData.DRAIN.dew.empty > seedData.DRAIN.nectar.empty).toBe(true)
	end)

	it("a refill stamps the clock, restores the level, and the ring drains again", function()
		local w = world()
		local supply = w.built.api.supply
		w.built.api.advance(seedData.DRAIN.dew.empty)
		expect(supply.state("mossholm", "dew"):get()).toBe("empty")
		supply.refill("mossholm", "dew")
		expect(supply.level("mossholm", "dew"):get()).toBe(1)
		w.built.api.advance(seedData.DRAIN.dew.low + 1)
		expect(supply.state("mossholm", "dew"):get()).toBe("low")
	end)
end)

describe("Glade S2: the detail, in both of its hosts (spec §8)", function()
	it("regular and wide mount the detail in the shell's own lane", function()
		local w = world(1200, 800)
		expect(w.built.api.conditions.isCompact:get()).toBe(false)
		w.tap("/GladeCard_mossholm")
		expect(w.report().selectedGlade).toBe("mossholm")
		expect(#w.report().surfaces).toBe(0) -- no modal: the lane is the host
		expect(w.find("/SupplyRow_dew") ~= nil).toBe(true)
		expect(w.find("/SupplyRow_nectar") ~= nil).toBe(true)
		-- GEOMETRY, not an arrangement NAME: the detail pane is mounted BESIDE the
		-- section content (its box starts to the right of the section's, and both
		-- share the row), which is what "the shell's own lane" means on screen
		local sections = w.node("/Panes/Section/Body_glades")
		local pane = w.node("/DetailLane/[mossholm]/Pane")
		expect(sections ~= nil and sections.rect ~= nil).toBe(true)
		expect(pane ~= nil and pane.rect ~= nil).toBe(true)
		expect(pane.rect.w > 0).toBe(true)
		expect(pane.rect.x >= sections.rect.x + sections.rect.w - 1).toBe(true)
	end)

	it("compact presents the same body as a modal with a Back button", function()
		local w = world(390, 844)
		expect(w.built.api.conditions.isCompact:get()).toBe(true)
		w.tap("/GladeCard_mossholm")
		expect(w.report().surfaces[1]).toBe("detail")
		expect(w.find("/Back") ~= nil).toBe(true)
		expect(w.find("/SupplyRow_dew") ~= nil).toBe(true)
		w.tap("/Back")
		expect(#w.report().surfaces).toBe(0)
		expect(w.report().selectedGlade).toBeNil()
	end)

	it("the dew row is an instant refill: no confirmation, a commit event and a keyed toast", function()
		local w = world()
		w.built.api.advance(seedData.DRAIN.dew.empty)
		w.tap("/GladeCard_mossholm")
		expect(w.built.api.supply.state("mossholm", "dew"):get()).toBe("empty")
		w.tap("/SupplyRow_dew")
		expect(w.built.api.supply.level("mossholm", "dew"):get()).toBe(1)
		expect(w.report().toasts[#w.report().toasts]).toBe("refill:mossholm")
		-- `commit` is emitted inside the effect the press caused; the framework's
		-- own `activate` follows it, because activate fires AFTER the effect
		local feedback = w.report().feedback
		expect(feedback[#feedback - 1]).toBe("commit")
		expect(feedback[#feedback]).toBe("activate")
		w.tick(10)
		local toasts = w.toastTexts()
		expect(#toasts).toBe(1)
		expect(string.find(toasts[1], "Mossholm", 1, true) ~= nil).toBe(true)
	end)

	it("a glade with no seeded visits shows the empty state, and one with visits lists them", function()
		local w = world()
		w.tap("/GladeCard_brambleRest")
		w.tick(40)
		expect(w.find("/NoVisitors/then/None") ~= nil).toBe(true)
		w.tap("/GladeCard_mossholm")
		w.tick(40) -- the departing pane retires in place before it disposes
		expect(w.find("/Visitor_v1") ~= nil).toBe(true)
		expect(w.find("/NoVisitors/then/None")).toBeNil()
	end)

	it("the low and empty chips are FORM, not a second hue: same ring tint in every state", function()
		local w = world()
		w.tap("/GladeCard_stillpond")
		-- stillpond's nectar is seeded low
		expect(w.built.api.supply.state("stillpond", "nectar"):get()).toBe("low")
		local chip = w.textOf("/StateChip/then/ChipGroup/Chip")
		expect(chip).toBe("Low")
		local arc = w.node("/SupplyRow_nectar/Row/Ring/Arc/then/Fill")
		expect(arc ~= nil).toBe(true)
		expect(arc.props.tint.role).toBe("accent")
		w.built.api.advance(seedData.DRAIN.nectar.empty)
		w.presenter.refresh()
		expect(w.textOf("/StateChip/then/ChipGroup/Chip")).toBe("Empty")
	end)
end)

--[[ THE STRAY CORNER STROKE AND THE CIRCLE DOCTRINE (task PAINT, director
	items 11 + 12). glade-corner.png, OddOverlapNotRound.png and whatisthis.png,
	root-caused from the Glade source rather than guessed from the photographs
	(the brief's own instruction): item 11 was an unsurfaced Button's default
	`control` chrome (a phantom fill + corner) peeking past its own full-bleed,
	more-rounded content; item 12's "double-draw" was never two ring paints —
	one `Track`+`Arc` ring plus one identity dot, the dot pinned to the ZStack's
	default top-left alignment instead of its centre; and whatisthis.png is the
	deliberate "glance-only rings, bottom-trailing on their own plate"
	(`overview.luau`'s own comment), not a leaked mount — it carries the exact
	same dot defect at a smaller size, which is what made it unrecognisable. ]]
describe("Glade: the stray corner stroke and the circle doctrine (task PAINT, director items 11/12)", function()
	local chrome_slots = require("../../src/tokens/chrome_slots")

	-- CENTRED, WITHIN A PIXEL — not exact equality, because a mark whose
	-- floor-derived size is ODD against its ring (e.g. `floor(56 * 0.46)` = 25
	-- inside a 56px ring) centres at a HALF pixel, which the solver's own
	-- pixel-snapping (`layout/solver.luau`'s `roundPx`) resolves to one whole
	-- pixel or the other. The claim under test is "centred", not "centred to a
	-- sub-pixel this engine cannot paint" — the same tolerance this file's own
	-- `centered()` helper (the nav-placement describe block, above) already
	-- uses for exactly this reason.
	local function centeredAxis(markPos: number, markSize: number, ringPos: number, ringSize: number)
		local wantMid = ringPos + ringSize / 2
		local gotMid = markPos + markSize / 2
		expect(math.abs(gotMid - wantMid) <= 1).toBe(true)
	end

	it("item 11: the card's activation Button classifies to NO chrome slot at all — surface = plain", function()
		local w = world()
		local button = w.node("/Card_mossholm/GladeCard_mossholm")
		expect(button ~= nil).toBe(true)
		expect(button.props.surface).toBe("plain")
		-- the root cause, named: an unsurfaced Button classifies "control" BY
		-- CLASS ALONE and gets a phantom fill+corner of its own — GetStyled-level
		-- (a property probe on BackgroundColor3/CornerRadius cannot see sheet
		-- paint; `chrome_slots.classify` is the decision that produces it).
		expect(chrome_slots.classify({ class = "Button" })).toBe("control")
		expect(chrome_slots.classify({ class = "Button", surface = button.props.surface })).toBeNil()
	end)

	--[[ ITEM 11's OWN FIX ROUND 1 (RED-TEAM finding 1, 2026-08-28):
		`surface = "plain"` silenced ALL pointer/touch interaction feedback on
		gladeCard's Button, not merely its decorative chrome — `applySurface`/
		`applySurfaceNative`'s `plain` branch used to bundle "no fill/corner/
		hairline" with "no press-dip, no hover/pressed tint" as one flag
		(`suppressStates`), and nothing distinguished the two. The two live
		instruments below are GetStyled-level (the pre-paint DECISION, not a
		property probe on the live/unstyled value) for exactly the reason
		`chrome_slots.classify` was the right instrument for item 11's root
		cause: `screen_target.luau` cannot load headlessly (it reaches engine
		globals at load time — `tests/lib/adapter_source.luau`'s own header),
		so its and `screen_paint.luau`'s ACTUAL shipped source is read as text
		and the exact branch a Button reaches is isolated by name — the same
		technique `tests/button_shape.spec.luau`'s paint section already uses
		for this exact pair of files. ]]
	local adapterSource = adapter_source.live()

	it(
		"item 11 fix round 1: a plain surface no longer bundles chrome suppression with interaction suppression (native)",
		function()
			local body = adapter_source.bodyOf(adapterSource, "local function applySurfaceNative(")
			expect(body ~= "").toBe(true)
			-- the OLD, now-wrong bundling this round removed
			expect(string.find(body, 'surface == "plain" or surface == "scrim"', 1, true)).toBeNil()
			-- ONLY scrim (a backdrop dismiss-catcher, never a control the player
			-- means to feel pressed) still suppresses both flags
			local scrimAt = string.find(body, 'if surface == "scrim" then', 1, true)
			expect(scrimAt ~= nil).toBe(true)
			local scrimBranch =
				string.sub(body, scrimAt :: number, (string.find(body, "else", scrimAt :: number, true) :: number) - 1)
			expect(string.find(scrimBranch, "handle.suppressStates = true", 1, true) ~= nil).toBe(true)
			expect(string.find(scrimBranch, "handle.nativeInteractive = false", 1, true) ~= nil).toBe(true)
			-- and `plain` now falls into the SAME branch every genuinely interactive
			-- surface does: suppressStates false, nativeInteractive true for a
			-- Button/Toggle -- a chrome-less Button is still a Button
			local elseAt = string.find(body, "else", scrimAt :: number, true) :: number
			local generalBranch =
				string.sub(body, elseAt, string.find(body, "syncTags(handle)", elseAt, true) :: number)
			expect(string.find(generalBranch, "handle.suppressStates = false", 1, true) ~= nil).toBe(true)
			expect(
				string.find(
					generalBranch,
					'handle.nativeInteractive = handle.class == "Button" or handle.class == "Toggle"',
					1,
					true
				) ~= nil
			).toBe(true)
		end
	)

	it(
		"item 11 fix round 1: a plain surface no longer bundles chrome suppression with interaction suppression (fallback)",
		function()
			local surfaceBody = adapter_source.bodyOf(adapterSource, "local function applySurface(")
			expect(surfaceBody ~= "").toBe(true)
			local plainAt = string.find(surfaceBody, 'elseif surface == "plain" then', 1, true) :: number
			expect(plainAt ~= nil).toBe(true)
			local nextBranchAt = string.find(surfaceBody, 'elseif surface == "accent" then', plainAt, true) :: number
			local plainBranch = string.sub(surfaceBody, plainAt, nextBranchAt - 1)
			-- the fix: this branch must NEVER suppress interaction feedback
			expect(string.find(plainBranch, "handle.suppressStates = true", 1, true)).toBeNil()
			-- explicit false, not merely absent (a reactive scrim -> plain flip
			-- must not inherit scrim's suppression by omission)
			expect(string.find(plainBranch, "handle.suppressStates = false", 1, true) ~= nil).toBe(true)
			-- the chrome removal itself is UNCHANGED — still no fill, no corner,
			-- no hairline
			expect(string.find(plainBranch, "instance.BackgroundTransparency = 1", 1, true) ~= nil).toBe(true)
			expect(string.find(plainBranch, 'IsA("UICorner")', 1, true) ~= nil).toBe(true)
			-- the regression guard: scrim is UNTOUCHED by this fix — a backdrop
			-- dismiss-catcher still gets zero interaction feedback, on purpose
			local scrimAt = string.find(surfaceBody, 'elseif surface == "scrim" then', 1, true) :: number
			expect(scrimAt ~= nil).toBe(true)
			local scrimBranch = string.sub(surfaceBody, scrimAt, #surfaceBody)
			expect(string.find(scrimBranch, "handle.suppressStates = true", 1, true) ~= nil).toBe(true)
		end
	)

	it(
		"item 11 fix round 1: the press-dip and the hover/pressed fill are the mechanism this restores — both gate on exactly the flag the branches above now leave false for `plain`",
		function()
			-- proves the fix is EFFECTIVE, not merely present: every consumer of
			-- `suppressStates` gates on that SAME field, so flipping it in the
			-- branches above is sufficient — no second flag anywhere silently
			-- re-suppresses the dip or the tint for a chrome-less control. Counted
			-- rather than found-once: `wireNativePressDip`'s press+recover pair (2),
			-- fallback `wireInteractiveStates`'s press+recover pair (2) and
			-- `setFill`'s early return (1) — five call sites, one flag.
			local count = 0
			local at = 1
			while true do
				local found = string.find(adapterSource, "suppressStates", at, true)
				if found == nil then
					break
				end
				count += 1
				at = found + 1
			end
			expect(count >= 6).toBe(true) -- 5 reads + the branches' own writes
			expect(string.find(adapterSource, "if handle.suppressStates then", 1, true) ~= nil).toBe(true)
			expect(string.find(adapterSource, "not handle.suppressStates then", 1, true) ~= nil).toBe(true)
		end
	)

	it("item 12: the supply ring is a TRUE 1:1 box via shape = circle, byte-identical geometry to before", function()
		local w = world()
		w.tap("/GladeCard_mossholm")
		local ring = w.node("/SupplyRow_dew/Row/Ring")
		expect(ring ~= nil).toBe(true)
		expect(ring.props.shape).toBe("circle")
		expect(ring.rect.w).toBe(seedData.METRICS.ringLarge)
		expect(ring.rect.h).toBe(seedData.METRICS.ringLarge)
		expect(ring.rect.w).toBe(ring.rect.h) -- the guarantee: it cannot NOT be square
	end)

	it("item 12: the dew ring's identity dot is CENTRED, not pinned to the top-left corner", function()
		local w = world()
		w.tap("/GladeCard_mossholm")
		local ring = w.node("/SupplyRow_dew/Row/Ring")
		local drop = w.node("/SupplyRow_dew/Row/Ring/Drop")
		expect(ring ~= nil and drop ~= nil).toBe(true)
		-- the pre-fix defect, stated as the assertion it must NOT satisfy: a
		-- top-left dot has drop.rect.x == ring.rect.x (offset 0), which is
		-- exactly what `child.alignH or node.alignH or "start"` produced before
		-- this ring declared its own alignment
		centeredAxis(drop.rect.x, drop.rect.w, ring.rect.x, ring.rect.w)
		centeredAxis(drop.rect.y, drop.rect.h, ring.rect.y, ring.rect.h)
		-- and it is still exactly the drawn size the art spec names (0.40 of the
		-- ring), unmoved by the alignment fix
		expect(drop.rect.w).toBe(math.floor(seedData.METRICS.ringLarge * 0.40))
	end)

	it("item 12: the nectar ring's identity mark (the Jar swap) is centred the same way", function()
		local w = world()
		w.tap("/GladeCard_mossholm")
		local ring = w.node("/SupplyRow_nectar/Row/Ring")
		expect(ring ~= nil).toBe(true)
		local swapPath: string? = nil
		for _, path in w.adapter.paths() do
			if
				string.find(path, "/SupplyRow_nectar/Row/Ring/Jar/", 1, true) ~= nil
				and string.sub(path, -5) == "/Swap"
			then
				swapPath = path
			end
		end
		expect(swapPath ~= nil).toBe(true)
		local swap = w.adapter.node(swapPath :: string)
		centeredAxis(swap.rect.x, swap.rect.w, ring.rect.x, ring.rect.w)
		centeredAxis(swap.rect.y, swap.rect.h, ring.rect.y, ring.rect.h)
	end)

	it("item 12: whatisthis.png IS the deliberate glance plate, not a leaked mount — same rings, same fix", function()
		-- the overview grid's OWN small rings (`sceneLib.ring(..., size =
		-- METRICS.ringSmall)`), never navigated into a detail — proving the
		-- centring fix is the SHARED composite's, not something the supply
		-- row's own wrapper adds
		local w = world()
		local glance = w.node("/Card_mossholm/GladeCard_mossholm/Body/Glance")
		expect(glance ~= nil).toBe(true)
		local nectarRing = w.node("/Card_mossholm/GladeCard_mossholm/Body/Glance/GlanceNectar")
		expect(nectarRing ~= nil).toBe(true)
		expect(nectarRing.props.shape).toBe("circle")
		expect(nectarRing.rect.w).toBe(seedData.METRICS.ringSmall)
		expect(nectarRing.rect.h).toBe(seedData.METRICS.ringSmall)
		local dewRing = w.node("/Card_mossholm/GladeCard_mossholm/Body/Glance/GlanceDew")
		local drop = w.node("/Card_mossholm/GladeCard_mossholm/Body/Glance/GlanceDew/Drop")
		expect(dewRing ~= nil and drop ~= nil).toBe(true)
		centeredAxis(drop.rect.x, drop.rect.w, dewRing.rect.x, dewRing.rect.w)
		centeredAxis(drop.rect.y, drop.rect.h, dewRing.rect.y, dewRing.rect.h)
	end)
end)

describe("Glade S3/S4: the purchase command's four phases (spec §9)", function()
	local function openShop(w: any)
		w.tap("/GladeCard_mossholm")
		w.tap("/SupplyRow_nectar")
		w.tap("/ShopRow")
	end

	it("premium with stock offers Use 1 and decrements the satchel; standard offers Choose", function()
		local w = world()
		w.tap("/GladeCard_mossholm")
		w.tap("/SupplyRow_nectar")
		expect(w.node("/Act_starlight").props.label).toBe("Use 1")
		expect(w.node("/Act_meadow").props.label).toBe("Choose")
		expect(w.node("/Act_moonpetal").props.label).toBe("Shop")
		w.tap("/Act_starlight")
		expect(w.built.api.supply.nectarOf("mossholm"):get()).toBe("starlight")
		expect(w.built.api.commerce.satchelOf("starlight"):get()).toBe(2)
		expect(#w.report().surfaces).toBe(0) -- the picker dismissed itself
	end)

	it("a premium nectar with nothing in the satchel opens the shop instead of using one", function()
		local w = world()
		w.tap("/GladeCard_mossholm")
		w.tap("/SupplyRow_nectar")
		w.tap("/Act_moonpetal")
		expect(w.report().surfaces[2]).toBe("shop")
		expect(w.built.api.commerce.satchelOf("moonpetal"):get()).toBe(0)
	end)

	it("a standard nectar assigns and refills in one act", function()
		local w = world()
		w.built.api.advance(seedData.DRAIN.nectar.empty)
		w.tap("/GladeCard_mossholm")
		w.tap("/SupplyRow_nectar")
		w.tap("/Act_fern")
		expect(w.built.api.supply.nectarOf("mossholm"):get()).toBe("fern")
		expect(w.built.api.supply.level("mossholm", "nectar"):get()).toBe(1)
	end)

	it("idle → pending → confirmed: the button says Confirming…, then the count counts up", function()
		local w = world()
		openShop(w)
		expect(w.node("/Buy_starlightBundle").props.label).toBe("Buy")
		w.tap("/Buy_starlightBundle")
		expect(w.built.api.commerce.status("starlightBundle"):get()).toBe("pending")
		expect(w.node("/Buy_starlightBundle").props.label).toBe("Confirming…")
		expect(w.node("/Buy_starlightBundle").props.enabled).toBe(false)
		-- PENDING IS NOT SUCCESS: nothing has moved yet
		expect(w.built.api.commerce.satchelOf("starlight"):get()).toBe(3)
		settle(w)
		expect(w.built.api.commerce.status("starlightBundle"):get()).toBe("confirmed")
		expect(w.built.api.commerce.satchelOf("starlight"):get()).toBe(8)
		expect(w.node("/Buy_starlightBundle").props.label).toBe("Buy")
		expect(w.report().toasts[#w.report().toasts]).toBe("purchase")
	end)

	it("the second attempt is the scripted `declined` rejection, with its copy under the card", function()
		local w = world()
		openShop(w)
		w.tap("/Buy_starlightBundle")
		settle(w)
		local before = w.built.api.commerce.satchelOf("starlight"):get()
		w.tap("/Buy_starlightBundle")
		settle(w)
		expect(w.built.api.commerce.status("starlightBundle"):get()).toBe("rejected")
		expect(w.built.api.commerce.reason("starlightBundle"):get()).toBe("declined")
		-- nothing reverted invisibly, and nothing was granted
		expect(w.built.api.commerce.satchelOf("starlight"):get()).toBe(before)
		local notice = w.textOf("/Reject_starlightBundle/then/Notice/Plate/Why")
		expect(notice).toBe("The purchase didn't go through. You weren't charged.")
		-- the control came back
		expect(w.node("/Buy_starlightBundle").props.enabled).toBe(true)
		local feedback = w.report().feedback
		expect(feedback[#feedback]).toBe("reject")
	end)

	it("every declared rejection reason has player-facing copy, including the fallback", function()
		for _, reason in { "declined", "offline", "owned", "fallback" } do
			local copy = strings.get("en", "reject." .. reason)
			expect(copy ~= "reject." .. reason).toBe(true)
			expect(#copy > 20).toBe(true)
		end
	end)

	it("while a purchase is pending, the picker's card for that nectar refuses to pretend", function()
		local w = world()
		w.tap("/GladeCard_mossholm")
		w.tap("/SupplyRow_nectar")
		w.tap("/ShopRow")
		w.tap("/Buy_starlightSingle")
		-- S3 is still mounted under S4: its Starlight card must not read "Use 1",
		-- and it must not fall back to a compact word that reads as an offer —
		-- the defect this case caught on 2026-08-08
		expect(w.node("/Act_starlight").props.label).toBe("Confirming…")
		expect(w.node("/Act_starlight").props.enabled).toBe(false)
		settle(w)
		expect(w.node("/Act_starlight").props.label).toBe("Use 1")
	end)

	it("the price is a service string the UI never composes", function()
		local w = world()
		expect(w.built.api.commerce.priceOf("starlightBundle")).toBe(strings.PRICE_MARK .. " 299")
		openShop(w)
		expect(w.textOf("/Pack_starlightBundle/Price")).toBe(strings.PRICE_MARK .. " 299")
	end)
end)

describe("Glade S5: the Keeper's Charm and its upgrade-only mode (spec §10)", function()
	it("buying a tier removes it from the offer and toasts the new standing", function()
		local w = world()
		w.tap(navTail("keeper"))
		w.tap("/OpenCharm")
		expect(w.find("/BuyCharm_ember") ~= nil).toBe(true)
		w.tap("/BuyCharm_ember")
		expect(w.built.api.commerce.status("ember"):get()).toBe("pending")
		settle(w)
		w.tick(40)
		expect(w.report().commerce.charm).toBe("ember")
		expect(w.find("/BuyCharm_ember")).toBeNil()
		expect(w.find("/BuyCharm_lumen") ~= nil).toBe(true)
		local toasts = w.toastTexts()
		expect(#toasts).toBe(1)
		expect(string.find(toasts[1], "Ember", 1, true) ~= nil).toBe(true)
	end)

	it("the scripted `owned` rejection shows its own copy and the retry then confirms", function()
		local w = world()
		w.tap(navTail("keeper"))
		w.tap("/OpenCharm")
		w.tap("/BuyCharm_ember")
		settle(w)
		w.tap("/BuyCharm_grove")
		settle(w)
		expect(w.built.api.commerce.reason("grove"):get()).toBe("owned")
		expect(w.textOf("/RejectCharm_grove/then/Notice/Plate/Why")).toBe("You already have this charm tier.")
		expect(w.report().commerce.charm).toBe("ember")
		w.tap("/BuyCharm_grove")
		settle(w)
		expect(w.report().commerce.charm).toBe("grove")
	end)

	it("a tier at or below the one held can never be sold again, whatever the fixture says next", function()
		local w = world()
		w.built.api.commerce.buyCharm("grove")
		settle(w)
		expect(w.report().commerce.charm).toBe("grove")
		w.built.api.commerce.buyCharm("ember")
		settle(w)
		expect(w.built.api.commerce.reason("ember"):get()).toBe("owned")
		expect(w.report().commerce.charm).toBe("grove")
	end)

	it("Lumen drops the Frostwisp gate AND opens its early arrival window", function()
		local w = world()
		w.tap(navTail("wisps"))
		expect(w.find("/WispCard_frostwisp/Body/Gate/then/LumenOnly") ~= nil).toBe(true)
		-- the seeded Frostwisp window starts at 480s, or 60s for a Lumen keeper
		w.built.api.advance(100)
		expect(w.built.api.visits.current("lanternDell"):get()).toBeNil()
		w.built.api.commerce.buyCharm("lumen")
		settle(w)
		w.tick(40)
		expect(w.report().commerce.charm).toBe("lumen")
		expect(w.find("/WispCard_frostwisp/Body/Gate/then/LumenOnly")).toBeNil()
		local live = w.built.api.visits.current("lanternDell"):get()
		expect(live ~= nil and live.wisp).toBe("frostwisp")
	end)

	it("the offer card leaves S1 the moment a tier is held", function()
		local w = world()
		expect(w.find("/OfferSee") ~= nil).toBe(true)
		w.built.api.commerce.buyCharm("ember")
		settle(w)
		w.tick(40)
		expect(w.find("/OfferSee")).toBeNil()
	end)
end)

describe("Glade S6/S7: wisp info, restore, the edit form and Fresh Start (spec §10)", function()
	it("a visitor row opens the wisp modal, which offers the charm while gated", function()
		local w = world()
		w.tap(navTail("wisps"))
		w.tap("/WispCard_frostwisp")
		expect(w.report().surfaces[1]).toBe("wisp")
		expect(w.find("/LumenGate/then/GateGroup/GateBody/SeeCharm") ~= nil).toBe(true)
		w.tap("/SeeCharm")
		expect(w.report().surfaces[2]).toBe("charm")
	end)

	it("the wisp modal states when and where a species was last seen", function()
		local w = world()
		w.tap("/GladeCard_mossholm")
		w.tap("/Visitor_v1")
		-- task POP restructured `shop.wisp`'s `Panel` into a plate (never inside
		-- the fade group) wrapping `PanelContent`'s `PanelBody` (the content that
		-- actually fades) — `Seen` moved one level in with the rest of the body
		local seen = w.textOf("/PanelBody/Seen") :: string
		expect(string.find(seen, "Mossholm", 1, true) ~= nil).toBe(true)
		expect(string.find(seen, "ago", 1, true) ~= nil).toBe(true)
	end)

	it("restore runs the same three-phase command and toasts on confirm", function()
		local w = world()
		w.tap(navTail("keeper"))
		expect(w.node("/Restore").props.label).toBe("Restore provisions")
		w.tap("/Restore")
		expect(w.node("/Restore").props.label).toBe("Confirming…")
		expect(w.node("/Restore").props.enabled).toBe(false)
		settle(w)
		expect(w.built.api.commerce.status("restore"):get()).toBe("confirmed")
		expect(w.report().toasts[#w.report().toasts]).toBe("restore")
		-- the second attempt is the scripted `offline` rejection
		w.tap("/Restore")
		settle(w)
		expect(w.built.api.commerce.reason("restore"):get()).toBe("offline")
		expect(w.textOf("/RestoreReject/then/Notice/Plate/Why")).toBe(
			"Can't reach the shop right now. Try again in a moment."
		)
	end)

	it("the edit form commits on Done and discards on Cancel", function()
		local w = world()
		w.tap(navTail("keeper"))
		w.tap("/EditKeeper")
		expect(w.report().surfaces[1]).toBe("edit")
		w.built.api.state.draftName:set("Alder of Stillpond")
		w.tap("/SaveKeeper")
		expect(w.report().keeper.name).toBe("Alder of Stillpond")
		expect(#w.report().surfaces).toBe(0)

		w.tap("/EditKeeper")
		w.built.api.state.draftName:set("discarded")
		w.tap("/CancelKeeper")
		expect(w.report().keeper.name).toBe("Alder of Stillpond")
	end)

	it("Fresh Start asks first, keeps the world on Keep, and reseeds it on Start over", function()
		local w = world()
		w.built.api.commerce.buyCharm("lumen")
		settle(w)
		w.tap(navTail("keeper"))
		w.tap("/FreshStart")
		expect(w.find("/KeepGlades") ~= nil).toBe(true)
		w.tap("/KeepGlades")
		expect(w.report().commerce.charm).toBe("lumen")

		w.tap("/FreshStart")
		w.tap("/StartOver")
		expect(w.report().commerce.charm).toBe("none")
		expect(w.report().section).toBe("glades")
		expect(#w.report().surfaces).toBe(0)
	end)
end)

describe("Glade: determinism — same seed, same steps, same dump", function()
	local function drive(w: any)
		w.built.api.advance(120)
		w.tap("/GladeCard_mossholm")
		w.tap("/SupplyRow_dew")
		w.tap("/SupplyRow_nectar")
		w.tap("/Act_starlight")
		w.tap("/SupplyRow_nectar")
		w.tap("/ShopRow")
		w.tap("/Buy_starlightBundle")
		settle(w)
		w.tap("/Buy_starlightBundle")
		settle(w)
		w.tap("/Close")
		w.tap("/Done")
		w.tap(navTail("keeper"))
		w.tap("/OpenCharm")
		w.tap("/BuyCharm_ember")
		settle(w)
	end

	it("two independent worlds driven identically produce identical dumps", function()
		local a = world()
		local b = world()
		drive(a)
		drive(b)
		expect(a.built.dump()).toBe(b.built.dump())
		expect(#a.built.dump() > 200).toBe(true)
	end)

	it("Fresh Start returns a played world to its opening dump, byte for byte", function()
		local w = world()
		local opening = w.built.dump()
		drive(w)
		expect(w.built.dump()).never().toBe(opening)
		w.built.api.reset()
		expect(w.built.dump()).toBe(opening)
	end)

	it("the dump is stable across repeated reads with nothing changed in between", function()
		local w = world()
		expect(w.built.dump()).toBe(w.built.dump())
	end)
end)

describe("Glade: toasts (spec §12)", function()
	it("a refill toast is keyed per glade, so the same subject never doubles up", function()
		local w = world()
		w.tap("/GladeCard_mossholm")
		w.tap("/SupplyRow_dew")
		w.tick(10)
		expect(#w.toastTexts()).toBe(1)
		w.tap("/SupplyRow_dew")
		w.tick(100) -- past the read floor: the supersede lands
		expect(#w.toastTexts()).toBe(1)
	end)

	it("two different glades are two different subjects", function()
		local w = world()
		w.tap("/GladeCard_mossholm")
		w.tap("/SupplyRow_dew")
		w.tick(10)
		w.tap("/GladeCard_fernhollow")
		w.tap("/SupplyRow_dew")
		w.tick(10)
		expect(#w.toastTexts()).toBe(2)
	end)

	it("nothing in the loop depends on reading a toast: the state is visible in place", function()
		local w = world()
		w.built.api.advance(seedData.DRAIN.dew.empty)
		w.tap("/GladeCard_brambleRest")
		expect(w.built.api.supply.state("brambleRest", "dew"):get()).toBe("empty")
		w.tap("/SupplyRow_dew")
		-- the ring is full again with no tick at all, i.e. before any toast painted
		expect(w.built.api.supply.level("brambleRest", "dew"):get()).toBe(1)
	end)
end)

describe("Glade: adaptation, one tree (spec §4)", function()
	-- THE NAV'S HOME IS A POLICY, NOT A FIT (adaptive.navPlacement). Every case
	-- here reads GEOMETRY — which band the tabs are painted in, how wide they
	-- are, where their midpoint is — because a name-based pin survives a shell
	-- that mounts the right node in the wrong place, which is the defect class
	-- these proofs exist to catch.
	local function centered(node: any, bandW: number, tolerance: number): boolean
		local mid = node.rect.x + node.rect.w / 2
		return math.abs(mid - bandW / 2) < tolerance
	end

	it("navPlacement gives every canvas its home: sidebar / bottom tabs / inline tabs / top tabs", function()
		-- pointer desktop (the headless default input): the vertical rail, no band
		local w = world(1400, 900)
		expect(w.find(RAIL) ~= nil).toBe(true)
		expect(w.find(BOTTOM_BAND)).toBeNil()
		expect(w.find(TOP_BAND)).toBeNil()
		local rail = w.node(RAIL)
		local links = w.node(RAIL .. "/Strip")
		-- VERTICAL: the four tabs stack, so the group is taller than one tab
		expect(links.rect.h > w.node(navTail("glades")).rect.h * 3).toBe(true)
		expect(rail.rect.x < 1400 * 0.2).toBe(true)

		-- phone portrait: the thumb-zone band, rail gone
		local phone = world(390, 844)
		expect(phone.find(RAIL)).toBeNil()
		expect(phone.find(BOTTOM_BAND) ~= nil).toBe(true)
		local band = phone.node(BOTTOM_BAND .. "/Strip")
		expect(band ~= nil and band.rect.w > 0).toBe(true)
		expect(centered(band, 390, 60)).toBe(true)

		-- phone landscape (roomy width, SHORT height): the inline form — a
		-- CENTERED cluster that hugs its tabs, never a full-width stretch
		local land = world(720, 360)
		local inline = land.node(COMPACT_BAND .. "/Strip")
		expect(inline ~= nil and inline.rect ~= nil).toBe(true)
		expect(land.find(BOTTOM_BAND)).toBeNil()
		expect(inline.rect.w < 720 * 0.7).toBe(true)
		expect(centered(inline, 720, 100)).toBe(true)

		-- tablet shape (roomy short side + touch primary): the top bar
		local tablet = world(1080, 810)
		tablet.env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		tablet.env:set("preferredInput", "Touch")
		tablet.presenter.refresh()
		expect(tablet.find(TOP_BAND) ~= nil).toBe(true)
		expect(tablet.find(RAIL)).toBeNil()
		expect(tablet.find(BOTTOM_BAND)).toBeNil()

		--[[ ...and the same canvas on the display fact the engine really sends for
			a tablet (`Small` — "Most tablet/mobile/handheld devices") is the same
			tablet and the same top bar. RE-PINNED from the bottom band (ADAPT-2,
			audit 2026-08-18): a 1280x720 touch canvas has a 720px short side, and
			asserting it stays a phone is how every prior tablet row came to measure
			one. ]]
		local small = world(1280, 720)
		small.env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		small.env:set("preferredInput", "Touch")
		small.env:set("displaySize", "Small")
		small.presenter.refresh()
		expect(small.find(TOP_BAND) ~= nil).toBe(true)
		expect(small.find(BOTTOM_BAND)).toBeNil()
		expect(small.core:lastError()).toBeNil()
	end)

	it("the top bar HUGS its tabs, centered — never full width (tablet / ten-foot shape)", function()
		local w = world(1080, 810)
		w.env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		w.env:set("preferredInput", "Touch")
		w.presenter.refresh()
		local row = w.node(TOP_BAND .. "/Strip")
		expect(row ~= nil and row.rect ~= nil).toBe(true)
		-- hugging: decisively narrower than the band it sits in...
		expect(row.rect.w < 1080 * 0.7).toBe(true)
		-- ...and centered in it
		expect(centered(row, 1080, 120)).toBe(true)
		expect(w.core:lastError()).toBeNil()
	end)

	it("compact puts the TAB BAND BELOW the content, never over it", function()
		-- the old fit-driven rail could be seated wherever an arrangement put it
		-- (a live report once had it ON TOP, under the engine topbar). This is the
		-- GEOMETRY of the placement scaffold, in both bottom shapes.
		for _, canvas in { { 390, 844 }, { 720, 360 } } do
			local w = world(canvas[1], canvas[2])
			-- the construct's own content region is what the band must sit below
			local middle = w.node("/Nav/Content")
			local tabs = w.node(BOTTOM_BAND .. "/Strip") or w.node(COMPACT_BAND .. "/Strip")
			expect(middle ~= nil and middle.rect ~= nil).toBe(true)
			expect(tabs ~= nil and tabs.rect ~= nil).toBe(true)
			expect(tabs.rect.y >= middle.rect.y + middle.rect.h - 1).toBe(true)
			expect(w.core:lastError()).toBeNil()
		end
	end)

	it("no VISIBLE bottom tab is cut off in the normal text range", function()
		-- THE POINT OF THE TERSE VOCABULARY (director 2026-08-09: "I see a lot of
		-- cutoff text"). Facts survive hiding, so the pin still reads only what is
		-- on screen — and after §6 the tabs it reads are the construct's segments.
		local canvases = { { 320, 640 }, { 360, 691 }, { 390, 844 }, { 480, 800 }, { 678, 339 }, { 720, 360 } }
		local cut: { string } = {}
		for _, canvas in canvases do
			for _, offset in { 0, 4, 10 } do
				local w = world(canvas[1], canvas[2])
				w.env:set("preferredTextOffset", offset)
				w.presenter.refresh()
				local hidden = w.handle.controller.hiddenRoots()
				local function onScreen(path: string): boolean
					for root in hidden do
						if string.sub(path, 1, #root) == root then
							return false
						end
					end
					return true
				end
				for path, facts in w.handle.controller.textAt() do
					if facts.truncated == true and isNavPath(path) and onScreen(path) then
						table.insert(cut, `{canvas[1]}x{canvas[2]} +{offset} {facts.text}`)
					end
				end
			end
		end
		table.sort(cut)
		expect(table.concat(cut, ", ")).toBe("")
	end)

	--[[ THE NEGATIVE CONTROL FOR THE CASE ABOVE, re-aimed by §6. The step-down has
		to be REACHABLE or "nothing is cut off" only proves that the first rung was
		pinned — but the step-down is no longer a ViewThatFits between two bars this
		proof authored. It is the TERSE VOCABULARY itself, carried as a bound
		`Option.label`: a thumb-zone home takes the short localized string and every
		roomier home takes the full one. So the control is that the two homes really
		do read different words, on the same world, from the same strip. ]]
	it("the terse vocabulary is REAL: the thumb-zone band reads a different word than the rail", function()
		local phone = world(390, 844)
		local desk = world(1400, 900)
		-- `keeper` is the section whose short form is a DIFFERENT word ("You"); the
		-- other three read the same in both vocabularies on purpose
		local phoneLabel = phone.node(navTail("keeper")).props.label
		local deskLabel = desk.node(navTail("keeper")).props.label
		expect(tostring(phoneLabel) ~= "").toBe(true)
		expect(tostring(phoneLabel) ~= tostring(deskLabel)).toBe(true)
		-- ...and the SAME world flips it live, which a construction-time compact
		-- form could not have done
		desk.env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		desk.presenter.refresh()
		expect(tostring(desk.node(navTail("keeper")).props.label)).toBe(tostring(phoneLabel))
		expect(desk.core:lastError()).toBeNil()
	end)

	it("a live resize moves the nav between homes and the world survives the move", function()
		local w = world(1400, 900)
		local card = w.find("/GladeCard_mossholm")
		w.tap(navTail("wisps"))
		expect(w.find(RAIL) ~= nil).toBe(true)
		w.env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		w.presenter.refresh()
		-- the rail is gone, the band is up, and the SECTION the player chose came
		-- with it — a placement change is a re-solve of the same world
		expect(w.find(RAIL)).toBeNil()
		expect(w.find(BOTTOM_BAND .. "/Strip") ~= nil).toBe(true)
		expect(w.report().section).toBe("wisps")
		w.tap(navTail("glades"))
		expect(w.report().section).toBe("glades")
		-- the CONTENT never remounted across the move
		expect(w.find("/GladeCard_mossholm")).toBe(card)
		expect(w.core:lastError()).toBeNil()
	end)

	it("the four sections are reachable from the nav in every home", function()
		for _, size in { { 1400, 900 }, { 390, 844 }, { 720, 360 } } do
			local w = world(size[1], size[2])
			for _, section in { "wisps", "flora", "keeper", "glades" } do
				w.tap(navTail(section))
				expect(w.report().section).toBe(section)
			end
		end
	end)

	it("the detail panes still adapt by MEASUREMENT: beside, then folded under", function()
		-- the Composition kept the job it is actually good at — the two content
		-- panes — while the nav left it for a policy. Both of its arrangements
		-- are reachable, which is what makes the declared fallback honest.
		local wide = world(1400, 900)
		wide.tap("/GladeCard_mossholm")
		expect(wide.handle.controller.compositionAt(wide.find("/Panes") :: string).arrangement).toBe("detailBeside")
		local sections = wide.node("/Panes/Section/Body_glades")
		local pane = wide.node("/DetailLane/[mossholm]/Pane")
		expect(pane.rect.x >= sections.rect.x + sections.rect.w - 1).toBe(true)

		-- a 620px window: the rail takes its share and the two panes can no
		-- longer sit side by side, so the detail folds UNDER the section
		local narrow = world(620, 900)
		narrow.tap("/GladeCard_mossholm")
		local resolved = narrow.handle.controller.compositionAt(narrow.find("/Panes") :: string)
		expect(resolved.arrangement).toBe("detailBelow")
		-- reached by being LEGAL, not by exhausting the list
		expect(resolved.fallback).toBe(false)
		local nSections = narrow.node("/Panes/Section/Body_glades")
		local nPane = narrow.node("/DetailLane/[mossholm]/Pane")
		expect(nPane.rect.w > 0).toBe(true)
		expect(nPane.rect.y >= nSections.rect.y + nSections.rect.h - 1).toBe(true)
		expect(narrow.core:lastError()).toBeNil()
	end)
end)

describe("Glade: focus and reachability (spec §4, §14)", function()
	it("the base surface opens on the first glade card, not on the search field", function()
		local w = world()
		local focused = tostring(w.presenter.focus.focused:get())
		expect(string.find(focused, "GladeCard_mossholm", 1, true) ~= nil).toBe(true)
	end)

	it("focus order follows the nav's PLACEMENT: a leading rail leads the ring, a bottom band trails it", function()
		-- Declaration order is focus order, and the nav is now declared where it
		-- is PAINTED — so the ring reads the screen the way an eye does rather
		-- than the way the old composition's ranks happened to fall. Inside the
		-- content the spec's own order (search before the cards) is untouched.
		local function indices(w: any): (number?, number?, number?)
			local order = w.handle.focusOrder()
			expect(order.present).toBe(true)
			local searchAt, firstCardAt, navAt = nil, nil, nil
			for index, entry in order.traversal do
				if searchAt == nil and string.find(entry.path, "/Search/Field", 1, true) ~= nil then
					searchAt = index
				end
				if firstCardAt == nil and string.find(entry.path, "GladeCard_mossholm", 1, true) ~= nil then
					firstCardAt = index
				end
				if navAt == nil and navSection(entry.path) == "glades" then
					navAt = index
				end
			end
			return searchAt, firstCardAt, navAt
		end

		local desktop = world(1400, 900)
		local dSearch, dCard, dNav = indices(desktop)
		expect(dSearch ~= nil and dCard ~= nil and dNav ~= nil).toBe(true)
		expect((dSearch :: number) < (dCard :: number)).toBe(true)
		-- the rail is painted on the LEADING edge, so it is first in the ring
		expect((dNav :: number) < (dSearch :: number)).toBe(true)

		local phone = world(390, 844)
		local pSearch, pCard, pNav = indices(phone)
		expect(pSearch ~= nil and pCard ~= nil and pNav ~= nil).toBe(true)
		expect((pSearch :: number) < (pCard :: number)).toBe(true)
		-- ...and the bottom band is painted last, so it is last in the ring
		expect((pCard :: number) < (pNav :: number)).toBe(true)
	end)

	it("the linear and directional readings cover the same nodes", function()
		local w = world()
		local order = w.handle.focusOrder()
		local inGroups: { [string]: boolean } = {}
		for _, group in order.navigation do
			for _, path in group.order do
				inGroups[if type(path) == "table" then (path :: any).id else path] = true
			end
		end
		for _, entry in order.traversal do
			expect(inGroups[entry.path] == true).toBe(true)
		end
	end)

	it("every modal can reach its own dismissal control from its focus map", function()
		local w = world()
		w.tap("/GladeCard_mossholm")
		w.tap("/SupplyRow_nectar")
		local surfaces = w.built.api.surfaces()
		expect(surfaces[1]).toBe("picker")
		-- the picker's Done is in the ring, and Cancel/outside-tap resolve the same way
		expect(w.find("/Done") ~= nil).toBe(true)
		w.presenter.back()
		w.tick(40)
		expect(w.find("/NectarPicker")).toBeNil()
	end)

	it("the charm sheet opens on the recommended tier, and never on a card that is gone", function()
		local w = world()
		w.tap(navTail("keeper"))
		w.tap("/OpenCharm")
		expect(string.find(tostring(w.presenter.focus.focused:get()), "BuyCharm_ember", 1, true) ~= nil).toBe(true)
		w.tap("/BuyCharm_ember")
		settle(w)
		w.tap("/Close")
		w.tick(40)
		-- Ember's card no longer exists; a fixed initialFocus id would have been
		-- refused at present time here
		w.tap("/OpenCharm")
		expect(string.find(tostring(w.presenter.focus.focused:get()), "BuyCharm_grove", 1, true) ~= nil).toBe(true)
		expect(w.core:lastError()).toBeNil()
	end)

	it("the picker opens on the first premium card's action button", function()
		local w = world()
		w.tap("/GladeCard_mossholm")
		w.tap("/SupplyRow_nectar")
		local focused = tostring(w.presenter.focus.focused:get())
		expect(string.find(focused, "Act_starlight", 1, true) ~= nil).toBe(true)
	end)
end)

describe("Glade nav — every placement is traversable (enter, through, away, action)", function()
	-- A tab bar you can reach but not LEAVE is a trap, and a tab bar you cannot
	-- reach is decoration. Each home is walked with the ring the action system
	-- routes both Tab and pad navigation through; the last case drives a REAL
	-- pad, in a world with no keyboard at all.
	local function pressTab(w: any)
		w.system.deviceKey("Tab", true)
		w.system.deviceKey("Tab", false)
		w.presenter.refresh()
	end

	local function ringPaths(w: any): { [string]: boolean }
		local seen: { [string]: boolean } = {}
		local start = w.presenter.focus.focused:get()
		if start == nil then
			pressTab(w)
			start = w.presenter.focus.focused:get()
		end
		local guard = 0
		local at = start
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

	local function assertNavTraversable(w: any)
		local seen = ringPaths(w)
		-- (enter / through) every section is a stop on the ring
		for _, section in { "glades", "wisps", "flora", "keeper" } do
			local hit = false
			for path in seen do
				if navSection(path) == section then
					hit = true
				end
			end
			expect(`{section}:{hit}`).toBe(`{section}:true`)
		end
		-- (away) the ring holds MORE than the bar: content stops exist too
		local outside = false
		for path in seen do
			if not isNavPath(path) then
				outside = true
			end
		end
		expect(outside).toBe(true)
		-- (action) activating a tab through the engine's own activation path works
		w.tap(navTail("wisps"))
		expect(w.report().section).toBe("wisps")
		expect(w.core:lastError()).toBeNil()
	end

	it("sidebar (pointer desktop)", function()
		assertNavTraversable(world(1400, 900))
	end)

	it("bottom tabs (phone portrait)", function()
		assertNavTraversable(world(390, 844))
	end)

	it("inline bottom tabs (phone landscape)", function()
		assertNavTraversable(world(720, 360))
	end)

	it("top tabs, driven as a PAD drives them: DPad to the bar, across it, ButtonA, DPad away", function()
		-- this world has NO keyboard (capabilities.keyboard = false), so Tab is
		-- honestly inert; the pad path is DPad navigation + ButtonA activation
		local w = world(1920, 1080)
		w.env:set("capabilities", { touch = false, mouse = false, keyboard = false, gamepad = true })
		w.env:set("preferredInput", "Gamepad")
		w.env:set("displaySize", "Large")
		w.presenter.refresh()
		expect(w.find(TOP_BAND) ~= nil).toBe(true)
		local function pad(key: string)
			w.system.deviceKey(key, true)
			w.system.deviceKey(key, false)
			w.presenter.refresh()
		end
		local function focused(): string
			return tostring(w.presenter.focus.focused:get())
		end
		-- the surface opens on the first glade card (spec §3), so (enter) is a
		-- real walk UP out of the content and into the band above it
		expect(string.find(focused(), "GladeCard_", 1, true) ~= nil).toBe(true)
		local guard = 0
		while not isNavPath(focused()) and guard < 12 do
			pad("DPadUp")
			guard += 1
		end
		expect(isNavPath(focused())).toBe(true)
		-- (through) a pad enters a band wherever it is spatially NEAREST, so the
		-- walk goes to the leading edge first and then all the way across, with
		-- the step counts taken from the tab it actually landed on — a walk that
		-- only ever pressed Right would prove nothing about the tabs behind it
		local ORDER = { "glades", "wisps", "flora", "keeper" }
		local function tabAt(): number?
			for index, section in ORDER do
				if navSection(focused()) == section then
					return index
				end
			end
			return nil
		end
		local entry = tabAt()
		expect(entry ~= nil).toBe(true)
		local seen: { [string]: boolean } = { [focused()] = true }
		for _ = 1, (entry :: number) - 1 do
			pad("DPadLeft")
			seen[focused()] = true
		end
		expect(tabAt()).toBe(1)
		for _ = 1, #ORDER - 1 do
			pad("DPadRight")
			seen[focused()] = true
		end
		expect(tabAt()).toBe(#ORDER)
		for _, section in ORDER do
			local hit = false
			for path in seen do
				if navSection(path) == section then
					hit = true
				end
			end
			expect(`{section}:{hit}`).toBe(`{section}:true`)
		end
		-- (away) DPadDown leaves the band for the content below it
		pad("DPadDown")
		expect(isNavPath(focused())).toBe(false)
		-- (action) walk back up and press A on whatever tab took focus
		local back = 0
		while not isNavPath(focused()) and back < 20 do
			pad("DPadUp")
			back += 1
		end
		local landed = tabAt()
		expect(landed ~= nil).toBe(true)
		pad("ButtonA")
		expect(w.report().section).toBe(ORDER[landed :: number])
		expect(w.core:lastError()).toBeNil()
	end)
end)

describe("Glade: localization and the expansion locale (spec §13)", function()
	it("every key exists in both locales and `xa` expands by exactly 1.4×", function()
		local keys = strings.keys()
		expect(#keys > 80).toBe(true)
		for _, key in keys do
			local en = strings.TABLES.en[key]
			local xa = strings.TABLES.xa[key]
			expect(type(xa)).toBe("string")
			expect(#xa).toBe(math.ceil(#en * 1.4))
		end
	end)

	it("expansion never eats a placeholder", function()
		local filled = strings.get("xa", "toast.refill", { glade = "Mossholm" })
		expect(string.find(filled, "Mossholm", 1, true) ~= nil).toBe(true)
		expect(string.find(filled, "{glade}", 1, true)).toBeNil()
	end)

	it("a locale swap relabels the live tree without a remount", function()
		local w = world()
		local before = w.find("/GladeCard_mossholm")
		local plate = w.find("/Card_mossholm/GladeCard_mossholm/Body/Plate/Name") :: string
		expect(w.adapter.node(plate).props.text).toBe("Mossholm")
		w.built.steps.setLocale(nil, "xa")
		w.presenter.refresh()
		expect(w.adapter.node(plate).props.text).toBe(strings.TABLES.xa["glade.mossholm"])
		expect(w.find("/GladeCard_mossholm")).toBe(before)
		expect(w.core:lastError()).toBeNil()
	end)

	it("an unknown locale falls back rather than blanking the screen", function()
		expect(strings.get("qq", "picker.done")).toBe("Done")
	end)

	it("remaining and relative times are proof-owned and single-unit", function()
		local w = world()
		expect(w.built.api.fmt.duration(400)).toBe("6m")
		expect(w.built.api.fmt.duration(40)).toBe("40s")
		expect(w.built.api.fmt.duration(4000)).toBe("1h")
		expect(w.built.api.fmt.relative(10)).toBe("just now")
		expect(w.built.api.fmt.relative(720)).toBe("12m ago")
	end)
end)

describe("Glade: motion (spec §11)", function()
	it("the wisp fly-in runs once per visit and completes", function()
		local w = world(390, 844)
		expect(#w.report().flyIns).toBe(0)
		w.tap("/GladeCard_mossholm")
		expect(w.report().flyIns[1]).toBe("v2")
		w.tick(200)
		local log = w.report().flyIns
		expect(log[#log]).toBe("complete")
		-- and it never runs a second time for the same visit
		w.tap("/Back")
		w.tap("/GladeCard_mossholm")
		local after = w.report().flyIns
		local starts = 0
		for _, entry in after do
			if entry == "v2" then
				starts += 1
			end
		end
		expect(starts).toBe(1)
	end)

	it("reduced motion places the same states and fires the same events", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		env:set("reducedMotion", true)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		local built = proof.build(Facet, core, {
			env = env,
			actionSystem = system,
			presenter = presenter,
			adapter = adapter,
		})
		local handle = presenter.present(built.screen, built.present)
		built.api.bindHandle(handle)
		presenter.refresh()
		built.api.nav.openGlade("mossholm")
		presenter.refresh()
		local log = built.report().flyIns
		-- every beat fired immediately and `onDone` reported the reduced form
		expect(log[1]).toBe("v2")
		expect(log[#log]).toBe("reduced")
		expect(core:lastError()).toBeNil()
	end)

	it("the ring's painted arc chases the level and lands on it", function()
		local w = world()
		w.tap("/GladeCard_mossholm")
		w.built.api.advance(seedData.DRAIN.dew.empty)
		w.tick(180)
		expect(w.find("/SupplyRow_dew/Row/Ring/Arc/then/Fill")).toBeNil() -- empty: no arc at all
		w.tap("/SupplyRow_dew")
		w.tick(180)
		local fill = w.node("/SupplyRow_dew/Row/Ring/Arc/then/Fill")
		expect(fill ~= nil).toBe(true)
		expect(#fill.props.points > 2).toBe(true)
	end)
end)

describe("Glade: the responsibility ledger's forbidden list", function()
	local FILES = {
		"init.luau",
		"content/seed.luau",
		"content/strings.luau",
		"services/supply.luau",
		"services/commerce.luau",
		"services/visits.luau",
		"ui/parts.luau",
		"ui/scene.luau",
		"ui/overview.luau",
		"ui/detail.luau",
		"ui/shop.luau",
		"ui/keeper.luau",
	}
	local ROOT = "examples/reference/p1_glade/"

	local function sourceLines(): { { file: string, line: number, text: string } }
		local out: { { file: string, line: number, text: string } } = {}
		for _, file in FILES do
			local source = fs.readFile(ROOT .. file)
			local number = 0
			for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
				number += 1
				local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
				if string.sub(trimmed, 1, 2) ~= "--" then
					table.insert(out, { file = file, line = number, text = line })
				end
			end
		end
		return out
	end

	it("scans the whole proof, and there is a whole proof to scan", function()
		local lines = sourceLines()
		expect(#lines > 1500).toBe(true)
	end)

	it("no wall clock and no random anywhere in the proof", function()
		for _, entry in sourceLines() do
			for _, banned in { "os%.clock", "os%.time", "os%.date", "math%.random", "tick%s*%(%s*%)" } do
				if string.find(entry.text, banned) ~= nil then
					error(`{entry.file}:{entry.line} uses a forbidden time/random source: {entry.text}`)
				end
			end
		end
	end)

	it("no engine reach-around: no Instance, no service, no input listener, no adapter write", function()
		for _, entry in sourceLines() do
			for _, banned in
				{
					"Instance%s*%.%s*new",
					"game%s*:%s*GetService",
					"UserInputService",
					"TweenService",
					"ContextActionService",
					"workspace%s*[:%.]",
					"adapter%s*%.%s*setProp",
				}
			do
				if string.find(entry.text, banned) ~= nil then
					error(`{entry.file}:{entry.line} reaches around the framework: {entry.text}`)
				end
			end
		end
	end)

	it("no device-name or platform-name branch: facts and size classes only", function()
		for _, entry in sourceLines() do
			for _, banned in { "UserInputType", "Enum%.Platform", "IsA%s*%(", "PlatformService" } do
				if string.find(entry.text, banned) ~= nil then
					error(`{entry.file}:{entry.line} branches on a platform name: {entry.text}`)
				end
			end
		end
	end)

	it("no raw colour reaches a role's place: identity hues ride the declared tint form", function()
		for _, entry in sourceLines() do
			if string.find(entry.text, "Color3%s*%.") ~= nil then
				error(`{entry.file}:{entry.line} builds a raw Color3: {entry.text}`)
			end
			if string.find(entry.text, '"#%x%x%x%x%x%x"') ~= nil then
				error(`{entry.file}:{entry.line} uses a hex colour literal: {entry.text}`)
			end
		end
	end)

	it("the bite is real: the scanner sees the patterns it bans when they are present", function()
		-- a lint nobody has watched fail is a lint nobody knows works
		local injected = "local x = math.random(1, 5)"
		expect(string.find(injected, "math%.random") ~= nil).toBe(true)
		local clean = "local x = use(now)"
		expect(string.find(clean, "math%.random")).toBeNil()
	end)
end)

describe("Glade: the stage axes it can answer headlessly (RA-M3/M4/M5)", function()
	it("a theme-package swap re-solves the same tree — no remount, no source edit", function()
		local w = world()
		local before = w.find("/GladeCard_mossholm")
		local package = (parchment :: any).build(Facet.themes)
		expect(package ~= nil).toBe(true)
		local snapshot = Facet.themes.resolve(package, nil, {})
		w.env:set("themeMetrics", snapshot)
		w.presenter.refresh()
		-- same node identity, same semantic tree, and the geometry moved with the
		-- package rather than with an edit here
		expect(w.find("/GladeCard_mossholm")).toBe(before)
		expect(w.find("/SupplyRow_dew") == nil).toBe(true) -- nothing selected yet
		w.tap("/GladeCard_mossholm")
		expect(w.find("/SupplyRow_dew") ~= nil).toBe(true)
		expect(w.core:lastError()).toBeNil()
	end)

	it("every preferred-text step re-solves without an error or a lost selection", function()
		local w = world(390, 844)
		w.tap("/GladeCard_mossholm")
		for _, offset in { 0, 4, 10, 14 } do
			w.env:set("preferredTextOffset", offset)
			w.presenter.refresh()
			expect(w.report().selectedGlade).toBe("mossholm")
			expect(w.find("/SupplyRow_dew") ~= nil).toBe(true)
		end
		expect(w.core:lastError()).toBeNil()
	end)

	it("the expansion locale reflows the whole loop with no error and no lost state", function()
		local w = world(390, 844)
		w.built.steps.setLocale(nil, "xa")
		w.tap("/GladeCard_mossholm")
		w.tap("/SupplyRow_nectar")
		expect(w.report().surfaces[2]).toBe("picker")
		expect(w.textOf("/NectarCard_starlight/Name")).toBe(strings.TABLES.xa["nectar.starlight"])
		w.tap("/Act_starlight")
		expect(w.built.api.supply.nectarOf("mossholm"):get()).toBe("starlight")
		expect(w.core:lastError()).toBeNil()
	end)
end)

describe("Glade: the scenario surface", function()
	it("every step the scenario runner exposes is callable and answers something", function()
		local w = world()
		local names: { string } = {}
		for name in w.built.steps do
			table.insert(names, name)
		end
		table.sort(names)
		expect(#names > 15).toBe(true)
		-- the drives the loop needs, by name, so a rename is a failing test
		for _, required in
			{
				"advanceClock",
				"selectGlade",
				"refillDew",
				"openPicker",
				"chooseNectar",
				"openShop",
				"buyPack",
				"openCharm",
				"buyCharm",
				"openWisp",
				"restore",
				"freshStart",
				"confirmFreshStart",
				"setLocale",
				"reset",
				"dump",
			}
		do
			expect(w.built.steps[required] ~= nil).toBe(true)
		end
		expect(w.built.steps.advanceClock(w.built, 90).now).toBe(90)
		expect(w.built.steps.selectGlade(w.built, "stillpond").selected).toBe("stillpond")
		expect(w.built.steps.selectSection(w.built, "flora").section).toBe("flora")
	end)

	it("Flora is browse-only: cards with a name and a species line, and no modal", function()
		local w = world()
		w.tap(navTail("flora"))
		expect(w.find("/FloraCard_mosscap") ~= nil).toBe(true)
		expect(w.textOf("/FloraCard_dewfern/Name")).toBe("Dewfern")
		expect(w.textOf("/FloraCard_dewfern/Species")).toBe("Shade fern — catches the morning")
		expect(#w.report().surfaces).toBe(0)
	end)

	it("the shop's hero card is the declared best value, with its own chip", function()
		local w = world()
		w.tap("/GladeCard_mossholm")
		w.tap("/SupplyRow_nectar")
		w.tap("/ShopRow")
		expect(w.textOf("/Pack_starlightBundle/BestValue")).toBe("Best value")
		-- and every premium shelf is present, packs ascending by quantity
		for _, nectar in { "starlight", "moonpetal", "gilded" } do
			expect(w.find("/Shelf_" .. nectar) ~= nil).toBe(true)
			local packs = seedData.packsFor(nectar)
			expect(packs[1].quantity < packs[2].quantity).toBe(true)
		end
	end)

	it("two fresh builds are identical (reset determinism) and dispose cleanly", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1200, h = 800 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		local before = core:counters()
		local built = proof.build(Facet, core, {
			env = env,
			actionSystem = system,
			presenter = presenter,
			adapter = adapter,
		})
		local handle = presenter.present(built.screen, built.present)
		built.api.bindHandle(handle)
		presenter.refresh()
		built.api.nav.openGlade("mossholm")
		built.api.nav.openPicker("mossholm")
		presenter.refresh()
		built.dispose()
		presenter.refresh()
		local after = core:counters()
		-- the proof owns one scope and gives it all back: signals and memos return
		-- to the baseline the core started from
		expect(after.signals <= before.signals + 4).toBe(true)
		expect(after.memos <= before.memos + 4).toBe(true)
		expect(core:lastError()).toBeNil()
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
			(adapter :: any).scrollBarThickness = 8
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
end)

describe("Glade detail — the locale x width x selection sweep the matrix pin could not see", function()
	it("an OPEN detail is diagnostic-clean in both locales at every canonical width", function()
		-- agent flag, 2026-08-09: the five-shape matrix pin drives neither the
		-- locale nor a selection, so the detail pane's xa overflows (a name, a
		-- caption and the trailing verb all asking natural width — lineLimit
		-- caps LINES, never the width a text asks for) lived outside every
		-- automated control. This sweep is the missing coverage.
		local w = world()
		for _, loc in { "en", "xa" } do
			w.built.steps.setLocale(w.built, loc)
			for _, width in { 360, 678, 1080, 1280, 1920 } do
				w.env:set("viewportRect", { x = 0, y = 0, w = width, h = if width < 400 then 691 else 810 })
				w.presenter.refresh()
				w.built.steps.selectGlade(w.built, "mossholm")
				w.presenter.refresh()
				local d = w.handle.controller.diagnostics()
				expect(`{loc}/{width}: {#d}`).toBe(`{loc}/{width}: 0`)
				w.built.steps.closeDetail(w.built)
				w.presenter.refresh()
			end
		end
		w.built.steps.setLocale(w.built, "en")
		w.built.dispose()
	end)
end)
