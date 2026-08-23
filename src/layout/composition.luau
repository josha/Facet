--!strict
-- DECLARED-CONTENT ADAPTIVE COMPOSITION (ADR-0023) — the pure half.
--
-- `AdaptiveStack` resolves an AXIS. `ViewThatFits` resolves ONE container's
-- candidate. Neither can answer the screen-level question a results/summary/
-- inspector surface actually asks: "here is everything I have to say, ranked;
-- put it somewhere legible on whatever box you gave me." Every screen that has
-- tried has written the same thing by hand — a ladder of viewport-height
-- guesses that is wrong on the next device (the commissioning case re-derived
-- `vpH < 520` in game code and got it wrong twice).
--
-- This module is that decision, and it is PURE: a declaration plus an offer
-- plus a `measure` callback in, a full resolution out. No engine, no theme, no
-- reactive core, no rects owned by anybody else. That is what makes it
-- headlessly sweepable — a test can drive a hundred offers and assert the
-- arrangement, the per-region form and the reason every losing candidate lost,
-- with no mount at all.
--
-- THE VOCABULARY
--   region       one thing the screen has to say. Carries a RANK (adaptation
--                priority, 1 = most important), an ordered list of FORMS
--                (richest -> minimum-viable), and its flags.
--   group        a set of regions that always travel together and is the unit
--                a lane holds. Declares a LANE AFFINITY ("lead"/"main"/"trail"
--                — any name), its sizing (hug or fill) and its in-lane
--                placement.
--   arrangement  an ordered list of LANES, each lane an ordered list of the
--                affinities it absorbs. Lanes sit side by side; a lane stacks
--                its groups down the cross axis. So `column` is ONE lane
--                holding every affinity, `threeLane` is three lanes of one,
--                and `twoLane` is the field beside a stacked ceremony+next.
--                One vocabulary; the three named presets are just data.
--   SPAN         a group that declares `span = "above" | "below"` instead of a
--                lane affinity. It is not in the lane vocabulary at all: it is
--                its own full-width ROW in the composition's flow, above or
--                below the band of lanes, IN EVERY ARRANGEMENT. That is the
--                whole point — a masthead or a caption that spans is the one
--                thing an arrangement change must not move (RascalRally S16.4's
--                "spans the composition, above the body"), and giving it an
--                affinity would oblige every arrangement to find it a lane and
--                let one of them silently drop it into a column.
--
-- THE ORDERED RULES (the commissioning spec's §S16.3, implemented as ONE
-- procedure rather than as a legality pre-test plus a separate solve — two
-- procedures could disagree, and the second one is the one that ships):
--
--   1. arrangements are tried in DECLARED order, richest first;
--   2. an arrangement whose hug lanes do not fit the offered width, or whose
--      fill lane falls under its declared `minWidth`, is illegal;
--   3. inside an arrangement, regions STEP DOWN to their next form before
--      anything is DROPPED, both in DESCENDING RANK (least important first),
--      and only among the regions in the lane that does not fit — stepping
--      down a region in a lane that already fits degrades the screen without
--      buying a pixel;
--   4. nothing is ever squeezed: a region is dropped, never shrunk past its
--      floor, and a floor is content ("one line", "two targets") or the
--      minimum-viable form's own measure — never an authored pixel count;
--   5. an arrangement that still does not fit after every step-down and every
--      legal drop is ILLEGAL and the next one is tried. This is also the
--      "exactly one scroll" rule: a lane that overflows and holds no
--      scrollable region cannot be made to fit, and no region ever becomes a
--      scroller implicitly, so a second scroll region cannot appear;
--   6. slack flows to `fill` — to the fill LANES on the main axis and to the
--      fill REGIONS inside a lane on the cross axis. No author-side spacer
--      whose only job is to hold something down. A SPAN row never takes slack:
--      it is a band that hugs its content, and the height it does not use is
--      the lane band's;
--   7. a `reserved` region holds its box WHILE ITS SCHEDULE IS RUNNING (it can
--      never be dropped and its contribution never falls below its floor), so
--      nothing jumps under a thumb between two pieces of one sequence. The
--      guarantee is MID-SEQUENCE stability, not a permanent claim on the box:
--      `reserved` is a boolean the caller re-answers per solve, and a
--      declaration that answers `false` — "this schedule is provably done, or
--      never started" — leaves the region as empty as any other. A round with
--      nothing to celebrate is not a round that must look like one;
--   8. when NO arrangement is legal the LAST one is the declared fallback and
--      the resolution says so (`fallback = true`) — the same contract
--      `ViewThatFits` makes about its last candidate. A screen degrades; it
--      never blanks;
--   9. EMPTY-LANE RELEASE: a lane whose every region resolves to nothing
--      paintable — empty, at-rest-invisible, or dropped — COLLAPSES. It takes
--      no width, it takes no lane gap, and the width it would have held goes to
--      the `fill` lanes by rule 6's own weights (with no fill lane the
--      composition simply measures narrower). The lane is still REPORTED, with
--      `collapsed = true` and a zero-width rect at the x it would have started
--      at, because "the left column is empty" and "the left column is not
--      there" look identical in a screenshot and have to be told apart in a
--      dump. This is what stops a reserved slot from spending a third of a
--      landscape phone on a round that has nothing to say (RascalRally S16 v2,
--      director visual round 6).
--
-- Re-solve, never rebuild, is a property of the OUTPUT: a resolution is rects
-- and form indices, so an arrangement change is an arrange pass. Every form of
-- every region stays mounted (ViewThatFits' bargain, at composition scale) and
-- the losers are hidden, which is what takes them out of focus order.
--
-- THE ONE DEPENDENCY, and why it does not cost the purity claim above: `floorPx`
-- resolves a CONTENT floor ("one line") to pixels, and that is text arithmetic
-- the solver already owns. `text_fit` is pure (no engine, no reactive core, no
-- theme of its own — it reads the snapshot it is handed), so a device matrix
-- here is still a headless sweep.

local textFit = require("./text_fit")
local rectLib = require("../rect")
local num = require("../num")
-- bound at module scope: `solver.luau` records that a per-call allocation on
-- the measure path is a bench regression this repository has already paid for
local roundPx = num.roundPx

local composition = {}

-- ===== declaration types ===================================================

export type Floor = {
	-- n LINES of the named typography role (default "body") — the honest way to
	-- say "one row" / "one line" without an authored pixel count
	lines: number?,
	role: string?,
	-- n minimum touch targets tall — "two buttons must fit"
	targets: number?,
}

export type GroupDecl = {
	id: string,
	-- EITHER an affinity an arrangement's lanes absorb, OR `span` — never both
	lane: string?,
	-- "above" | "below": this group is its OWN full-width row, in that position
	-- relative to the band of lanes, in every arrangement
	span: string?,
	sizing: string?, -- "hug" (default) | "fill"
	weight: number?, -- fill weight (default 1)
	place: (string | number)?, -- "start" (default) | "center" | "end" | 0..1
	-- ACROSS the lane, where `place` is DOWN it (ADR-0025 Decision 1). Absent, a
	-- region takes the whole lane width, which is what it has always done and what
	-- "a region is an allotment" means. Declared, the region takes its own measured
	-- width and sits at that end of the lane — alignment of a full-width box would
	-- mean nothing, so stating it is what asks for the content width.
	align: string?, -- "start" | "center" | "end"
	-- RULE 9'S DECLARED COUNTERPART (ADR-0025 Decision 2). Rule 9 releases a lane
	-- whose every region resolves to nothing paintable and gives its width away.
	-- That is right for a content flow and exactly wrong for a layout whose lane
	-- POSITIONS are the coordinate system — a HUD's right-hand column must stay on
	-- the right edge on the round where the middle column has nothing to say.
	holdsLane: boolean?,
	minWidth: number?, -- resolved px; a fill lane under this is illegal
	--[[ THE MEASURE'S CEILING, and the exact twin of `minWidth` above it (B-6e,
		controller ruling R14, 2026-08-21). A `fill` group's lane width is a SHARE of
		the slack, so on a very wide offer it is simply whatever is left — which at
		three metres is a reading line nobody can track back to its own start: the
		layout paradigm matrix measured a ten-foot main lane at 1316px against the
		regular-touch tablet's 600.

		`maxWidth` caps that share. What it frees is offered to the OTHER fill lanes,
		and what none of them will take becomes the resolution's centring offset
		rather than being spent on width.

		IT IS NOT `maxMeasure`. That caps the whole BOX — "full width, but no wider
		than this" — and every lane then divides what is left, hug lanes included.
		This caps THE MEASURE: the reading width of one fill lane, with the hug lanes
		left exactly the widths their content asked for. ]]
	maxWidth: number?, -- resolved px; a fill lane never exceeds this
	gap: number?, -- between this group's regions
}

export type RegionDecl = {
	id: string,
	group: string,
	rank: number, -- 1 = most important; drop/step-down go DESCENDING
	forms: number, -- how many forms this region declares (>= 1)
	sizing: string?, -- "hug" (default) | "fill"
	weight: number?,
	floor: Floor?,
	mayScroll: boolean?,
	mayDrop: boolean?,
	reserved: boolean?,
	--[[ WHERE THE CONTENT A REDUCED FORM STOPS SHOWING WENT (D7, 2026-08-16).
		Required on a region with more than one form, refused on a region with one:
		see RECOVERS below for the three routes and why the one-form case has no
		choice to make. `nil` here is only ever the one-form case. ]]
	recover: string?,
	--[[ ...AND HOW THE PLAYER GETS IT BACK WITHOUT LEAVING (wave REVEAL, D7's
		other half). "auto" (the default, and what `nil` means here) = the framework
		presents this region's RICHEST form in a transient plate at the region's own
		anchor whenever a poorer one is standing; "none" = the author states there is
		nothing to disclose, or is disclosing it themselves; "custom" = a handler at
		the blueprint boundary replaces the presentation and this module records only
		that one exists. The pure decision needs the THREE-WAY answer and nothing
		else — a function is not a fact a layout pass can hold. ]]
	expand: string?,
	--[[ WHICH FORMS CARRY A CONTROL, INDEXED LIKE `forms` (wave REVEAL). Read off
		the class contract at the blueprint boundary — never guessed here — because
		the answer decides WHICH gesture opens the expansion: a form that contributes no
		focus stop and no semantic action can BE the target, and a form that does
		must keep its own meanings and take a chevron beside it instead. Absent, every
		form is taken as passive, which is what a declaration driven straight from a
		test means when it says nothing. ]]
	formInteractive: { boolean }?,
}

export type Arrangement = {
	name: string,
	lanes: { { string } }, -- lane i absorbs these affinities, in this order
	-- DECLARED, VALIDATED, READ — and until now untyped (F-29). `arrangementOf`
	-- type-checks this field and names it in its legal-fields error; `resolve`
	-- reads it and reports an `ineligible` rejection. At the blueprint boundary a
	-- Readable<boolean> is accepted and resolves to one boolean per solve, so what
	-- reaches this type is always the resolved boolean.
	eligible: boolean?,
}

export type Declaration = {
	id: string?,
	groups: { GroupDecl },
	regions: { RegionDecl },
	arrangements: { Arrangement },
	laneGap: number?, -- between lanes
	groupGap: number?, -- between groups inside a lane
	maxMeasure: number?, -- cap both axes of the box we resolve in, and centre
	--[[ THE CONTENT LANE'S OWN CAP (B-6e, controller ruling R14, 2026-08-21), and
		it is a DIFFERENT question from `maxMeasure` rather than a second spelling
		of it. `maxMeasure` caps the BOX — "full width, but no wider than this" —
		and every lane divides what is left. `measureCap` caps THE MEASURE: the
		reading width of a `fill` lane, which is the number a player's eye actually
		tracks, and it leaves the hug lanes exactly the widths their content asked
		for.

		It is not a public prop. It arrives already in px from the caller that
		knows the display class (`render/layout_node.luau`, from
		`adaptive.laneMeasureFor(metrics.metricScale)`), the same way `floorOf` and
		`expandGutter` arrive as numbers with the theme's NAMES left outside this
		module. An author who declared `maxMeasure` has made the measure decision
		themselves and no default is set beside it. ]]
	measureCap: number?,
}

export type Offer = { w: number, h: number }
export type Rect = { x: number, y: number, w: number, h: number }

-- measure(regionId, formIndex, availW, availH) -> (w, h)
export type MeasureFn = (string, number, number, number) -> (number, number)
export type ResolveCtx = {
	measure: MeasureFn,
	--[[ THE GUTTER A EXPAND PLATE MUST LEAVE on each side of the viewport, in px
		(wave REVEAL). A theme spacing step, resolved by the caller — this module
		owns no theme, so the NUMBER arrives and the NAME never does. Absent, the
		plate may use the whole offer, which is what a pure test means when it says
		nothing. ]]
	expandGutter: number?,
	expandPlateInset: number?,
	expandPlateStraddle: number?,
	expandPlateDiscHalf: number?,
	-- the AUTHORED floor in px, when the declaration expressed one. Absent, a
	-- region's floor is its minimum-viable form's own measured height, which is
	-- the honest default: the smallest thing the author was willing to show.
	floorOf: ((RegionDecl) -> number?)?,
	--[[ THE RECTS A SOLVED LANE MAY NOT START INSIDE (framework-gaps §8), in THIS
		composition's own box — the caller subtracts its origin, exactly as it
		resolves a metric NAME to a number before handing it over.

		A lane band is one rectangle: every lane starts at the same y, so a host's
		own chrome row covering SOME columns and not others could not be reserved
		around declaratively at all, and the HUD demo spent ~150 lines plus a sampled
		monotone latch and a hand-built dependency token doing it by hand. `src/env/
		environment.luau` documents the punt in as many words: *"which is what lets a
		consumer reserve around it per column"*.

		THE RULE IS THE MEASUREMENT, NOT A FRACTION. Three coverage-fraction rules
		were each measured wrong on a case this repository has recorded — ANY overlap
		pushes a centre column down for pixels its content never comes near, MAJORITY
		misses a 46%-covered column whose `end`-anchored rail is inside the row, and
		the ANCHOR POINT misses both. Every one of them is a guess about the WIDTH OF
		THE CONTENT, and the content's width is a thing this module MEASURES. So a
		lane starts below an exclusion when the lane's own regions occupy an x range
		the exclusion also occupies, at the RICHEST forms — decided once, from the
		first pass, and never re-decided. That is what makes it a fixed point rather
		than a 2-cycle: giving way shrinks the budget, the budget steps a region down
		to a narrower form, the narrower form no longer reaches the chrome — and a
		rule that re-asked would put the richer form back. The consumer's version had
		to bound that with an epoch token and a latch because it was sampling SOLVED
		rects through a geometry feedback loop; inside one resolve there is no loop
		to bound. ]]
	exclusions: { Rect }?,
	--[[ THE PLATFORM'S OWN TOPBAR BAND (framework-gaps §9), in this composition's
		box, supplied only under `rootPolicy = "bandSafeContent"` and only to a
		composition sitting at the surface's own content origin.

		  `x` / `w`  where the FREE strip is — the part of the band the platform's
		             own control cluster does not occupy. The `topbar` span row is
		             laid out inside exactly this, so its content is level with the
		             engine's buttons and cannot be on them (ADR-0027).
		  `h`        the row's height: down to the band's own bottom edge.
		  `reserve`  what the composition owes the platform's WHOLE top reservation
		             when it declares no `topbar` region — which makes the policy
		             byte-identical to `deviceSafeContent` for such a composition.

		Absent, nothing here changes, which is what every composition outside a
		band-riding surface gets. ]]
	band: { x: number, w: number, h: number, reserve: number }?,
}

export type RegionResolution = {
	id: string,
	rank: number,
	group: string,
	lane: number?, -- physical lane index, nil when dropped OR when it spans
	span: string?, -- "above" | "below" when this region rides a spanning row
	form: number, -- 1-based index into the region's forms
	mounted: boolean,
	dropped: boolean,
	--[[ A FORM BELOW THE RICHEST WAS CHOSEN (D7.1). Derivable from `form > 1` and
		reported anyway, beside `dropped`, because the two are the SAME event to a
		player — content this screen has stopped showing — and a consumer that has
		to remember one is a boolean and the other is arithmetic gets it subtly
		wrong. A dropped region is `elided = false`: it is not showing a poorer
		form, it is showing nothing. ]]
	elided: boolean,
	floor: number,
	rect: Rect?,
	--[[ ── THE EXPAND FACTS (wave REVEAL, 2026-08-18) ──────────────────────────
		`form` above is the index into the region's forms and stays exactly what it
		was. These five are the answer to a DIFFERENT question — "is the player
		looking at less than this region has, and can they ask for the rest right
		here" — and they are reported rather than left to arithmetic for the reason
		`elided` already is: a consumer who has to remember that a drop is not a
		step-down, that form 1 is the richest, and that a form index survives a drop
		gets one of the three wrong.

		  activeForm       the form STANDING, or 0 when nothing is (dropped, or
		                   resolved to nothing). `form` keeps the ladder's last rung
		                   either way; this says whether anyone can see it.
		  richestForm      1. Stated, not assumed: "forms are declared richest-first"
		                   is the vocabulary's own rule and this is the one place a
		                   consumer should have to read it.
		  formInteractive  whether the ACTIVE form contributes a focus stop or a
		                   semantic action — the declaration's own answer, indexed by
		                   `activeForm`, false when nothing is standing.
		  expand           the declared mode, never nil ("auto" is what silence
		                   means).
		  expandable       activeForm > 1 and expand ~= "none". The predicate the
		                   overflow census and the dead-end sweep both read.
		  plate            present only when expandable: the box form 1 wants at this
		                   offer, and whether it can be a plate at all. ]]
	activeForm: number,
	richestForm: number,
	formInteractive: boolean,
	expand: string,
	expandable: boolean,
	plate: { w: number, h: number, sheet: boolean, max: number }?,
}

--[[ ONE ENTRY PER THING THE SCREEN HAS STOPPED SHOWING (D7.1) — the seam.
	`reason` is which of the two events happened; `route` is where the content
	went, resolved from the region's `recover` and its drop state rather than
	re-derived by the consumer. ]]
export type Unshown = {
	id: string,
	reason: string, -- "dropped" | "elided"
	route: string, -- "overflow" | "self"
}

export type Resolution = {
	arrangement: string,
	legal: boolean,
	fallback: boolean, -- true when NO candidate was legal and the last one is showing
	offer: Offer,
	origin: { x: number, y: number }, -- maxMeasure centring offset
	used: { w: number, h: number },
	-- EVERY lane of the chosen arrangement, in order — including the ones rule 9
	-- collapsed, which report `collapsed = true`, no groups and a zero-width rect
	lanes: {
		{
			index: number,
			affinities: { string },
			groups: { string },
			rect: Rect,
			collapsed: boolean,
			-- §8: how far below the lane band this lane starts because a declared
			-- exclusion occupies an x range its own content does. Absent when none did
			-- — so a composition that declares no exclusions reports what it always did
			exclusion: number?,
		}
	},
	-- the spanning rows, in flow order (above rows, then below rows)
	spans: { { id: string, side: string, rect: Rect } },
	groups: { { id: string, lane: number?, span: string?, rect: Rect } },
	regions: { RegionResolution },
	regionById: { [string]: RegionResolution },
	scroller: string?, -- the one region allowed to scroll, when it is mounted
	rejected: { { arrangement: string, rule: string, detail: string } },
	-- AUTHORING DIAGNOSTIC, emitted by every resolve and dumped by `dump` — and
	-- until now absent from this type (F-29). Sorted region ids whose chosen form
	-- measured the WHOLE offer inside a HUG lane; see the note at its assignment.
	hugOverflow: { string },
	-- WHO IS ON TOP OF WHOM (ADR-0025 Decision 3). Regions cannot overlap as
	-- BOXES — lanes sit side by side and a lane stacks its groups down — but a
	-- region whose chosen form measures bigger than the box it was allotted paints
	-- outside it, and if a neighbour is there it is painting on that neighbour.
	-- Every unordered pair, sorted by id, with the overlap extent in px.
	collisions: { { a: string, b: string, dx: number, dy: number } },
	--[[ WHAT THIS SCREEN IS NOT SHOWING RIGHT NOW (D7.1), in DECLARATION order —
		the same order `regions` is in, so the two read together.

		This is the list an overflow surface is populated FROM. Without it every
		consumer re-derives elision by hand out of `dropped` and `form`, and gets it
		subtly wrong: a dropped region is not `form > 1`, a region whose every form
		is lossless (`recover = "none"`) is not missing anything, and a one-form
		region can only ever be missing by being dropped. Three rules, re-implemented
		per consumer, is how "adaptation deleted the player's information" ships.

		A region appears here when it is DROPPED, or when it is elided and its
		`recover` is not "none". It does not appear when `recover = "none"`: the
		author has stated, explicitly, that the reduced form still shows everything. ]]
	unshown: { Unshown },
}

-- ===== the built-in arrangement presets ====================================
-- Data, not code. An author may pass any of these NAMES or a table of the same
-- shape; the vocabulary is the table, and these three are the ones the
-- commissioning spec names.

composition.ARRANGEMENTS = table.freeze({
	-- one lane holding everything, in affinity order: the tall offer
	column = table.freeze({ name = "column", lanes = table.freeze({ table.freeze({ "lead", "main", "trail" }) }) }),
	-- the field beside a stacked ceremony+next: the short, narrow offer
	twoLane = table.freeze({
		name = "twoLane",
		lanes = table.freeze({ table.freeze({ "main" }), table.freeze({ "lead", "trail" }) }),
	}),
	-- ceremony | field | actions: the short, wide offer (landscape phone up)
	threeLane = table.freeze({
		name = "threeLane",
		lanes = table.freeze({
			table.freeze({ "lead" }),
			table.freeze({ "main" }),
			table.freeze({ "trail" }),
		}),
	}),
}) :: { [string]: Arrangement }

-- ===== the screen-anchored HUD preset (ADR-0025) ===========================
-- DATA, exactly like `ARRANGEMENTS` above. A HUD is not a new vocabulary and not
-- a sibling module: the three screen COLUMNS are three lanes (lanes sit side by
-- side and never overlap — that IS the partition), the three vertical BANDS are
-- the `place` a lane already distributes its groups by, and the nine zone names
-- are the same nine words `anchor` uses. So the whole mechanism is the rank /
-- step-down-before-drop ladder above, reused literally.
--
-- Per column there are FOUR groups and the first one holds no regions: it is the
-- COLUMN, `fill` so the lane takes its third of the band and `holdsLane` so the
-- third survives a round with nothing in it. The three zone groups stay `hug` so
-- that `place` still runs the top/middle/bottom spacer — `sizing` would otherwise
-- have to do both jobs at once and the vertical one would win.
--
-- An author who wants a different split copies this table and edits it; the
-- lane's share is the sum of its `fill` groups' weights.

-- ...and a TENTH zone that is not one of the nine anchors, because it is not in
-- the box the anchors partition: `topbar` is the row LEVEL WITH THE PLATFORM'S
-- OWN CONTROLS (ADR-0027, director 2026-08-14 — "things at top that are aligned
-- with the controls but don't overlap"). It is a `span = "above"` group, which is
-- the vocabulary the composition already has for "its own full-width row above
-- the band of lanes, in every arrangement", so the lanes start BELOW it and the
-- top-left cluster is clear of the platform's cluster by construction rather than
-- by an authored offset.
--
-- It costs nothing to a HUD that does not use it: a span group with no regions is
-- inactive, takes no height and appears in no output (pinned as an additivity
-- test in tests/hud_composition.spec.luau). The band's GEOMETRY — where the row
-- sits and how wide the free part of it is — is the `platformChrome` env fact,
-- never a number in here.
composition.ZONES = table.freeze({
	"topbar",
	"topLeft",
	"left",
	"bottomLeft",
	"top",
	"center",
	"bottom",
	"topRight",
	"right",
	"bottomRight",
}) :: { string }

--[[ ...AND THE ONE OF THE TEN THAT IS NOT AN ANCHOR IS THE ONE THE PLATFORM OWNS
	(§9). `ZONES[1]` is `topbar`, and this is the name the band branch below tests
	for — written once, derived from the list, so the vocabulary and the mechanism
	cannot drift into two spellings. A group with this id and `span = "above"` is
	the row a `bandSafeContent` surface lays into `platformChrome.band`. ]]
local BAND_ZONE = composition.ZONES[1]

local function hudColumn(lane: string, align: string, zones: { string }): { GroupDecl }
	local out: { GroupDecl } = {
		table.freeze({
			id = lane .. "Column",
			lane = lane,
			sizing = "fill",
			holdsLane = true,
		}) :: any,
	}
	for i, id in zones do
		table.insert(
			out,
			table.freeze({
				id = id,
				lane = lane,
				place = (if i == 1 then "start" elseif i == 2 then "center" else "end"),
				align = align,
			}) :: any
		)
	end
	return out
end

do
	local groups: { GroupDecl } = {
		-- the platform's own row, above every lane and in every arrangement
		table.freeze({ id = "topbar", span = "above" }) :: any,
	}
	for _, g in hudColumn("left", "start", { "topLeft", "left", "bottomLeft" }) do
		table.insert(groups, g)
	end
	for _, g in hudColumn("center", "center", { "top", "center", "bottom" }) do
		table.insert(groups, g)
	end
	for _, g in hudColumn("right", "end", { "topRight", "right", "bottomRight" }) do
		table.insert(groups, g)
	end
	composition.HUD_GROUPS = table.freeze(groups) :: { GroupDecl }
end

composition.HUD = table.freeze({
	name = "hud",
	lanes = table.freeze({ table.freeze({ "left" }), table.freeze({ "center" }), table.freeze({ "right" }) }),
}) :: Arrangement

-- ===== floors ==============================================================

--[[ floorPx(floor, metrics) -> number? — the CONTENT-expressed floor in pixels,
	resolved against the live theme snapshot so a bigger type scale raises every
	floor by itself. Returns nil when nothing was declared: the caller then falls
	back to the minimum-viable form's own measure.

	THIS FUNCTION WAS WRONG THREE WAYS UNTIL 2026-08-15, and it is public, so
	every caller trusted it. It computed `lines * role.size * role.lineHeight`:

	  1. NO `ceil`. The solver's box is `ceil(...)`; a floor of 16.8 against a
	     measured 17 lets a region hold one line "legally" in a box that cannot
	     draw it.
	  2. NO SCALE. `role.size` is the AUTHORED size. The measure seam reserves at
	     `max(typographyScale, typographyPaintScale)`, so on a ten-foot display
	     (whose Large class multiplies the whole ladder by 1.5) and at any raised
	     accessibility preference the floor was short by up to 3x — the "bigger
	     type scale raises every floor by itself" the comment promised only ever
	     happened when the THEME's authored numbers moved, never when the PLAYER's
	     preference did.
	  3. NO TEXT OFFSET. `preferredTextOffset` is additive px the engine adds to
	     every painted line, and the four measured offsets this project binds
	     itself to are {0, 4, 10, 14}: at +14 a one-line floor was short by 16.8px
	     and a four-line floor by 67.2px.

	It now spends `text.lineBox`, so it is the same arithmetic as the solve that
	measures the region — see docs/plans/variable-item-extents.md. The FACTS come
	from the snapshot itself (`text.facts { metrics = ... }`), which carries the
	three platform facts it was resolved from; this module still touches no env
	and stays headlessly sweepable. ]]
function composition.floorPx(floor: Floor?, metrics: any): number?
	if floor == nil then
		return nil
	end
	local px: number? = nil
	if type(floor.lines) == "number" then
		-- the role is resolved HERE rather than by `lineBox`'s strict lookup: a
		-- `floor.role` naming something this theme does not carry has always fallen
		-- back to `body`, and tightening that is a separate decision from fixing the
		-- arithmetic. `nil` = neither role exists, and `lineBox` then reserves at the
		-- measurer's own default factor, exactly as this used to.
		local roles = (if type(metrics) == "table" then metrics.type else nil) or {}
		local named = floor.role or "body"
		local role: string? = if roles[named] ~= nil then named elseif roles.body ~= nil then "body" else nil
		local facts = textFit.facts({ metrics = metrics })
		px = textFit.lineBox({
			facts = facts,
			-- 14px is the neutral `body` size, and the fallback this has always used
			-- when the snapshot carries no typography at all
			size = role or 14,
			lines = floor.lines :: number,
			role = role,
		})
	end
	if type(floor.targets) == "number" then
		local targets = (if type(metrics) == "table" then metrics.targetSizes else nil) or {}
		local minimum = (if type(targets) == "table" then targets.minimum else nil) or 44
		local want = (floor.targets :: number) * minimum
		px = if px == nil then want else math.max(px :: number, want)
	end
	return px
end

-- ===== declaration validation ==============================================
-- Loud and at DECLARATION time. Every message names the offending id and the
-- legal set: an accepted-and-ignored field is the exact failure the strict
-- blueprint boundary exists to remove, and a composition is the worst place for
-- one — a silently-ignored `mayDrop` is a region that never leaves the screen
-- on the device you did not test.

local FLOOR_KEYS: { [string]: boolean } = { lines = true, role = true, targets = true }
local GROUP_KEYS: { [string]: boolean } = {
	id = true,
	maxWidth = true,
	lane = true,
	span = true,
	sizing = true,
	weight = true,
	place = true,
	align = true,
	holdsLane = true,
	minWidth = true,
	gap = true,
}
local REGION_KEYS: { [string]: boolean } = {
	id = true,
	group = true,
	rank = true,
	forms = true,
	sizing = true,
	weight = true,
	floor = true,
	mayScroll = true,
	mayDrop = true,
	reserved = true,
	recover = true,
	expand = true,
	formInteractive = true,
}
--[[ ── THE RECOVERY CONTRACT (D7.1) ───────────────────────────────────────────
	ADAPTATION MAY CHANGE HOW MUCH OF SOMETHING IS SHOWN, AND WHAT IT COSTS TO
	REACH IT. IT MAY NOT CHANGE WHETHER IT CAN BE REACHED AT ALL.

	The rank ladder above is not missing and is not broken — it steps a region down
	and then drops it, exactly as declared. What it never had is any notion of where
	the content the reduced form stopped showing WENT, so "step down" and "delete"
	were the same operation from the player's side. Measured on this repo's own HUD
	showcase (artifacts/navigation-and-menus/d7-hud-baseline.md): 39 elided-or-
	dropped occurrences across nine viewports, every one of them a dead end.

	So a region with more than one form must say which of three things is true:

	  "none"      every form below the richest still shows everything that matters.
	              A poorer LAYOUT of the same content, not less content. It has to
	              be written: silence is not consent, and a declaration that says
	              nothing is exactly the state this contract exists to remove.
	  "self"      the reduced form IS the route — the player taps what is left to
	              get the rest. The blueprint boundary checks that the last form
	              actually contains something focusable, because a route nobody can
	              reach is the defect wearing the fix's clothes (D7.2).
	  "overflow"  the reduced form carries no route of its own, so the screen's
	              overflow surface is the route. It reads `Resolution.unshown`.

	WHY A ONE-FORM REGION MAY NOT DECLARE IT. Such a region can only ever stop
	showing content by being DROPPED, and a dropped region has no form left to be
	its own route — the sink is the only possible answer, so there is nothing here
	for the author to choose and a key with one legal value is ceremony. `mayDrop`
	is already that declaration.

	WHY "none" AND `mayDrop` CANNOT BOTH BE TRUE. Dropping shows nothing at all, so
	"nothing is lost" is not a claim the author can make about it. ]]
local RECOVERS: { [string]: boolean } = { none = true, self = true, overflow = true }
--[[ ── THE EXPAND CONTRACT (wave REVEAL, 2026-08-18) ──────────────────────────
	D7 made every step-down state where its content WENT. This states how the
	player gets it back, and the default is that the framework does it:

	  "auto"    (the default) a region standing on a form below its richest gains an
	            EXPANSION — activation presents form 1 in a transient plate at the
	            region's own anchor. The region declares nothing; `forms` and `rank`
	            stay the whole collapse-customization surface.
	  "none"    there is nothing to disclose, or the author is disclosing it
	            themselves. It is the authored escape the dead-end sweep exempts,
	            and stating it is what makes that exemption reviewable.
	  "custom"  a handler replaces both the passive and the interactive
	            presentations. The pure pass records that a route EXISTS (so the
	            sweep can see it) and nothing about what it does.

	A ONE-FORM REGION NEVER SIMPLIFIES, so an `expand` on one can never fire. The
	refusal lives at the blueprint boundary rather than here, for the same
	measurement `recover`'s mirror rule records: the count reaching this function is
	the count of MOUNTED forms, and a form behind a `UI.When` is absent while its
	condition reads false. ]]
local EXPANDS: { [string]: boolean } = { auto = true, none = true, custom = true }
local SIZINGS: { [string]: boolean } = { hug = true, fill = true }
local PLACES: { [string]: boolean } = { start = true, center = true, ["end"] = true }
local ALIGNS: { [string]: boolean } = { start = true, center = true, ["end"] = true }
local SPANS: { [string]: boolean } = { above = true, below = true }

local function fail(msg: string): never
	error(`Facet composition: {msg}`, 0)
end

local function keyList(set: { [string]: boolean }): string
	local names = {}
	for k in set do
		table.insert(names, k)
	end
	table.sort(names)
	return table.concat(names, ", ")
end

local function checkKeys(what: string, t: { [string]: any }, allowed: { [string]: boolean })
	for k in t do
		if type(k) ~= "string" or not allowed[k] then
			fail(`{what} does not accept '{tostring(k)}' — legal fields: {keyList(allowed)}`)
		end
	end
end

-- arrangementOf(value) -> Arrangement. A NAME resolves to a preset; a table is
-- taken as a custom arrangement and validated to the same shape.
--[[ ── ELIGIBILITY: a candidate may be gated on a fact the OFFER cannot show ──
	Rule 2 asks "does this arrangement FIT?", which is the only question geometry
	can answer — and it is not always the whole question.

	Found live (RascalRally results, 2026-08-02). A one-column layout was wanted on
	a tablet or desktop and NOT on a landscape phone. Ordering `column` first does
	not express that: the field is a SCROLL region, so every other region takes its
	space and the field simply scrolls in what is left. Column therefore FITS every
	offer, including a 375 px phone where it costs the list its own lane. The
	author's real rule was "only where the screen is roomy" — a SIZE CLASS, which
	`adaptive.conditions` already produces and which rule 2 has no way to consult.

	So a candidate may carry `eligible`: a plain boolean, resolved once per solve
	exactly as `reserved` is. False = skip this candidate entirely and try the next
	one, WITHOUT marking the resolution a fallback — an ineligible arrangement was
	never a candidate for this offer, which is different from one that lost.

	It cannot make a screen blank: the LAST arrangement is the declared fallback
	and is used whatever it says, so `eligible = false` on every candidate still
	resolves. That is checked below rather than trusted. ]]
function composition.arrangementOf(value: any): Arrangement
	if type(value) == "string" then
		local preset = composition.ARRANGEMENTS[value]
		if preset == nil then
			local names = {}
			for name in composition.ARRANGEMENTS do
				table.insert(names, name)
			end
			table.sort(names)
			fail(
				`unknown arrangement '{value}' — the built-in names are {table.concat(names, ", ")}, `
					.. 'or pass a table { name = "...", lanes = { { "lead" }, { "main" } } }'
			)
		end
		return preset
	end
	if type(value) ~= "table" then
		fail("an arrangement is a preset NAME or a table { name, lanes }, got " .. typeof(value))
	end
	local name = (value :: any).name
	if type(name) ~= "string" or name == "" then
		fail("a custom arrangement needs a non-empty `name` (it is what the resolution reports and tests assert)")
	end
	local eligible = (value :: any).eligible
	if eligible ~= nil and type(eligible) ~= "boolean" then
		fail(
			`arrangement '{name}' eligible must be a boolean (or a Readable<boolean> at the blueprint `
				.. `boundary, which resolves to one per solve), got {typeof(eligible)}`
		)
	end
	local lanes = (value :: any).lanes
	if type(lanes) ~= "table" or #lanes == 0 then
		fail(`arrangement '{name}' needs at least one lane (lanes is an array of affinity arrays)`)
	end
	for i, lane in lanes do
		if type(lane) ~= "table" or #lane == 0 then
			fail(`arrangement '{name}' lane {i} must be a non-empty array of lane-affinity names`)
		end
		for _, affinity in lane do
			if type(affinity) ~= "string" or affinity == "" then
				fail(`arrangement '{name}' lane {i} holds a non-string affinity`)
			end
		end
	end
	for k in value :: any do
		if k ~= "name" and k ~= "lanes" and k ~= "eligible" then
			fail(`arrangement '{name}' does not accept '{tostring(k)}' — legal fields: eligible, lanes, name`)
		end
	end
	return value :: Arrangement
end

-- normalize(decl) -> Declaration. Validates EVERYTHING and returns a frozen,
-- defaulted declaration. Idempotent: a declaration that came out of here is
-- returned unchanged, so calling it per solve is free.
function composition.normalize(decl: any): Declaration
	if type(decl) ~= "table" then
		fail("a declaration is a table { groups, regions, arrangements }, got " .. typeof(decl))
	end
	if (decl :: any).__normalized == true then
		return decl :: Declaration
	end

	local groups = (decl :: any).groups
	if type(groups) ~= "table" or #groups == 0 then
		fail("`groups` must be a non-empty array — a region needs a group, and a group is what a lane holds")
	end
	local byGroup: { [string]: GroupDecl } = {}
	local outGroups: { GroupDecl } = {}
	for i, g in groups do
		if type(g) ~= "table" then
			fail(`groups[{i}] must be a table`)
		end
		checkKeys(`groups[{i}]`, g, GROUP_KEYS)
		if type(g.id) ~= "string" or g.id == "" then
			fail(`groups[{i}] needs a non-empty string id`)
		end
		if byGroup[g.id] ~= nil then
			fail(`two groups share the id '{g.id}' — group ids address lanes and must be unique`)
		end
		-- A GROUP EITHER RIDES A LANE OR SPANS. `lane` is an affinity an
		-- arrangement absorbs; `span` takes the group OUT of the lane vocabulary
		-- and gives it its own full-width row above or below the lanes, in every
		-- arrangement. Both together would be two answers to "where does this go",
		-- and neither leaves the group with no home at all.
		if g.span ~= nil then
			if not (type(g.span) == "string" and SPANS[g.span]) then
				fail(`group '{g.id}' span must be "above" or "below" (its row's position relative to the lanes)`)
			end
			if g.lane ~= nil then
				fail(
					`group '{g.id}' declares BOTH lane '{tostring(g.lane)}' and span '{tostring(g.span)}' — a `
						.. "spanning group is its own full-width row in every arrangement, so it has no lane "
						.. "affinity to absorb"
				)
			end
			-- A SPAN ROW HAS NO LANE TO HOLD (ADR-0025 Decision 2). `holdsLane` is
			-- rule 9's counterpart and rule 9 is a rule about LANES; a spanning row
			-- is outside the lane vocabulary by construction, and its own
			-- "empty ⇒ absent" is what it guarantees instead.
			if g.holdsLane ~= nil then
				fail(
					`group '{g.id}' spans, so 'holdsLane' means nothing to it — holdsLane keeps a LANE in `
						.. "the band when nothing in it is paintable, and a spanning row has no lane (an "
						.. "empty span row is simply absent)"
				)
			end
			-- Everything below would be accepted and ignored: a span row is as wide
			-- as the composition (no `minWidth` to fail, no fill share to weigh) and
			-- as tall as its content (no slack to place in). Slack belongs to the
			-- lane band, which is rule 6.
			for _, field in { "sizing", "minWidth", "maxWidth", "place", "weight", "align" } do
				if (g :: any)[field] ~= nil and not (field == "sizing" and g.sizing == "hug") then
					fail(
						`group '{g.id}' spans, so '{field}' means nothing to it — a spanning row is the `
							.. "composition's full width and its content's own height, and the slack it does not "
							.. "take belongs to the lane band (rule 6)"
					)
				end
			end
		elseif type(g.lane) ~= "string" or g.lane == "" then
			fail(
				`group '{g.id}' needs a lane affinity (the name an arrangement's lanes absorb) or `
					.. 'span = "above" | "below" (its own full-width row in every arrangement)'
			)
		end
		if g.maxWidth ~= nil and type(g.maxWidth) ~= "string" then
			if type(g.maxWidth) ~= "number" or g.maxWidth ~= g.maxWidth or g.maxWidth <= 0 then
				fail(`group '{g.id}' maxWidth is a positive px cap on a fill lane's reading width`)
			end
			if type(g.minWidth) == "number" and (g.maxWidth :: number) < (g.minWidth :: number) then
				fail(
					`group '{g.id}' declares maxWidth {g.maxWidth} below its own minWidth {g.minWidth} — `
						.. "a lane cannot be both illegal under one number and capped beneath it"
				)
			end
		end
		local sizing = g.sizing or "hug"
		if not SIZINGS[sizing] then
			fail(`group '{g.id}' sizing must be "hug" or "fill", got '{tostring(g.sizing)}'`)
		end
		if g.place ~= nil then
			if type(g.place) == "number" then
				if g.place < 0 or g.place > 1 or g.place ~= g.place then
					fail(`group '{g.id}' place as a number is a fraction 0..1, got {g.place}`)
				end
			elseif not (type(g.place) == "string" and PLACES[g.place]) then
				fail(`group '{g.id}' place must be "start" | "center" | "end" or a fraction 0..1`)
			end
		end
		if g.align ~= nil and not (type(g.align) == "string" and ALIGNS[g.align]) then
			fail(
				`group '{g.id}' align must be "start" | "center" | "end" — it places this group's regions `
					.. "ACROSS the lane (`place` is DOWN it), and stating it is what asks for the content "
					.. "width instead of the whole lane"
			)
		end
		if g.holdsLane ~= nil and type(g.holdsLane) ~= "boolean" then
			fail(
				`group '{g.id}' holdsLane must be a boolean — it is rule 9's counterpart ("keep this lane `
					.. `in the band even when nothing in it is paintable"), got {typeof(g.holdsLane)}`
			)
		end
		if g.weight ~= nil and (type(g.weight) ~= "number" or g.weight <= 0) then
			fail(`group '{g.id}' weight must be a positive number`)
		end
		-- a THEME METRIC NAME is legal here exactly as it is on every other
		-- theme-owned number; the renderer resolves it to px before the solver
		-- ever calls `resolve`, so the arithmetic below only ever sees numbers
		if g.minWidth ~= nil and type(g.minWidth) ~= "string" and (type(g.minWidth) ~= "number" or g.minWidth < 0) then
			fail(`group '{g.id}' minWidth must be a non-negative px number or a theme metric name`)
		end
		if g.gap ~= nil and type(g.gap) ~= "string" and (type(g.gap) ~= "number" or g.gap < 0) then
			fail(`group '{g.id}' gap must be a non-negative px number or a theme metric name`)
		end
		local norm: GroupDecl = {
			id = g.id,
			lane = g.lane,
			span = g.span,
			sizing = sizing,
			weight = g.weight or 1,
			place = g.place or "start",
			align = g.align,
			-- NIL, not `false`, when it was not declared. It is read exactly once,
			-- as `g.holdsLane == true`, so nil and false are the same answer — but
			-- storing `false` adds a ninth key to every normalized group and pushes
			-- the table's hash part to the next power of two, which slows EVERY
			-- field read on it. Measured 2026-08-14 on the off-path legacy
			-- declaration: +2.5% per resolve with the key present, +0.3% without —
			-- the whole of this feature's off-path cost was one always-present key.
			holdsLane = if g.holdsLane == true then true else nil,
			minWidth = g.minWidth,
			-- nil when it was not declared, for the reason `holdsLane` states above:
			-- an always-present key costs +2.5% per resolve, measured
			maxWidth = g.maxWidth,
			gap = g.gap,
		}
		byGroup[g.id] = norm
		table.insert(outGroups, norm)
	end

	local regions = (decl :: any).regions
	if type(regions) ~= "table" or #regions == 0 then
		fail("`regions` must be a non-empty array — a composition with nothing to say has nothing to adapt")
	end
	local seen: { [string]: boolean } = {}
	local outRegions: { RegionDecl } = {}
	local scroller: string? = nil
	for i, r in regions do
		if type(r) ~= "table" then
			fail(`regions[{i}] must be a table`)
		end
		checkKeys(`regions[{i}]`, r, REGION_KEYS)
		if type(r.id) ~= "string" or r.id == "" then
			fail(`regions[{i}] needs a non-empty string id`)
		end
		if seen[r.id] then
			fail(`two regions share the id '{r.id}' — region ids address forms, rects and focus`)
		end
		seen[r.id] = true
		if byGroup[r.group] == nil then
			fail(`region '{r.id}' names group '{tostring(r.group)}', which is not declared`)
		end
		if type(r.rank) ~= "number" or r.rank ~= r.rank or r.rank < 1 or math.floor(r.rank) ~= r.rank then
			fail(`region '{r.id}' needs an integer rank >= 1 (1 = most important; drops go descending)`)
		end
		if type(r.forms) ~= "number" or r.forms < 1 or math.floor(r.forms) ~= r.forms then
			fail(`region '{r.id}' needs at least one form (richest -> minimum-viable)`)
		end
		local sizing = r.sizing or "hug"
		if not SIZINGS[sizing] then
			fail(`region '{r.id}' sizing must be "hug" or "fill", got '{tostring(r.sizing)}'`)
		end
		if r.weight ~= nil and (type(r.weight) ~= "number" or r.weight <= 0) then
			fail(`region '{r.id}' weight must be a positive number`)
		end
		if r.floor ~= nil then
			if type(r.floor) ~= "table" then
				fail("region '" .. r.id .. "' floor is a content expression such as { lines = 1 } or { targets = 2 }")
			end
			checkKeys(`region '{r.id}' floor`, r.floor, FLOOR_KEYS)
			if r.floor.lines == nil and r.floor.targets == nil then
				fail(`region '{r.id}' floor must state lines or targets — a floor is CONTENT, never a pixel count`)
			end
		end
		-- `reserved` REACHES THE SOLVER AS A BOOLEAN, ALWAYS. The declaration may
		-- express it as a live "is this schedule still running" read (rule 7) —
		-- the renderer resolves that read once per solve, exactly as it resolves a
		-- reactive width — so anything else here is a truthy table that would have
		-- reserved the box forever and never released it.
		if r.reserved ~= nil and type(r.reserved) ~= "boolean" then
			fail(
				`region '{r.id}' reserved must be a boolean (or a Readable<boolean> at the blueprint `
					.. `boundary, which resolves to one per solve), got {typeof(r.reserved)}`
			)
		end
		-- THE FLOOR IS THE RESERVED BOX. `reserved` without one reserves nothing:
		-- at rest a region's content measures zero, so the only thing that can
		-- hold the box open is a floor, and a floor is content ("this slot is
		-- always two lines tall"). A `reserved` flag with no floor is a promise
		-- the mechanism cannot keep, which is exactly the accepted-and-ignored
		-- class this boundary exists to remove.
		if r.reserved == true and r.floor == nil then
			fail(
				`region '{r.id}' is reserved but declares no floor — the FLOOR is what holds a reserved `
					.. "box open when its content rests (the content measures nothing then), so state it: "
					.. "floor = { lines = n } or { targets = n }"
			)
		end
		if r.reserved == true and r.mayDrop == true then
			fail(
				`region '{r.id}' is both reserved and mayDrop — a reserved region holds its box so `
					.. `nothing jumps under a thumb, which is precisely what dropping it would do`
			)
		end
		--[[ THE RECOVERY CONTRACT, ENFORCED WHERE EVERY OTHER CLOSED SPEC IS (D7.1).
			Required where it means something, refused where it does not — see RECOVERS
			above for all three rulings and the reasoning behind each. ]]
		if r.recover ~= nil and not (type(r.recover) == "string" and RECOVERS[r.recover]) then
			fail(
				`region '{r.id}' recover must be "none" | "self" | "overflow", got '{tostring(r.recover)}' — `
					.. '"none" = every form still shows everything, "self" = the reduced form is the route '
					.. '(its last form must contain something focusable), "overflow" = the screen\'s overflow '
					.. "surface is the route (it reads resolution.unshown)"
			)
		end
		if r.forms > 1 and r.recover == nil then
			fail(
				`region '{r.id}' declares {r.forms} forms but no 'recover' — a form below the richest shows `
					.. 'LESS, and this declaration does not say where the rest went. State recover = "none" '
					.. '(every form shows everything), "self" (the reduced form is the route) or "overflow" '
					.. "(the screen's overflow surface is). Adaptation may change how much is shown and what "
					.. "it costs to reach; it may not change whether it can be reached at all"
			)
		end
		--[[ THE MIRROR RULE — "refused on a one-form region" — IS THE BLUEPRINT
			BOUNDARY'S, not this function's, and the reason is a measurement.
			`forms` reaching the solver is the count of MOUNTED forms, and a form
			gated behind a `UI.When` contributes nothing while its condition reads
			false: the composition showcase declares two `When` forms per region and
			solves with ONE of them for most of its states. Refusing `recover` here
			would therefore reject a perfectly good declaration on the frame a
			condition flipped. `UI.Region` knows the DECLARED count and refuses it
			there, once, where the author is standing. ]]
		if r.recover == "none" and r.mayDrop == true then
			fail(
				`region '{r.id}' declares recover = "none" and mayDrop — dropping shows NOTHING, so "every `
					.. "form still shows everything\" cannot be true of it. A droppable region's reduced form "
					.. 'is either its own route ("self") or the overflow surface\'s ("overflow")'
			)
		end
		if r.expand ~= nil and not (type(r.expand) == "string" and EXPANDS[r.expand]) then
			fail(
				`region '{r.id}' expand must be "auto" | "none" | "custom", got '{tostring(r.expand)}' — `
					.. '"auto" = the framework discloses the richest form from the one standing, "none" = '
					.. 'nothing to disclose (the authored escape), "custom" = an authored handler replaces it'
			)
		end
		if r.formInteractive ~= nil and type(r.formInteractive) ~= "table" then
			fail(
				`region '{r.id}' formInteractive is an ARRAY indexed like the forms — one boolean per form, `
					.. `stating whether that form contributes a focus stop or a semantic action`
			)
		end
		if r.mayScroll == true then
			if scroller ~= nil then
				fail(
					`regions '{scroller}' and '{r.id}' both declare mayScroll — a composition resolves `
						.. `EXACTLY ONE scroll region, so two of them is a declaration error, not a `
						.. `layout outcome (rule 5)`
				)
			end
			scroller = r.id
		end
		table.insert(outRegions, {
			id = r.id,
			group = r.group,
			rank = r.rank,
			forms = r.forms,
			sizing = sizing,
			weight = r.weight or 1,
			floor = r.floor,
			mayScroll = r.mayScroll == true,
			mayDrop = r.mayDrop == true,
			reserved = r.reserved == true,
			-- NIL on a one-form region and a string on every other, which is exactly
			-- what the two rules above have already guaranteed
			recover = r.recover,
			--[[ ...and the expand is NEVER nil past here, resolved once so no consumer
				has to know the rule (wave REVEAL). "auto" is what silence means —
				EXCEPT on a region whose author has already stated that nothing is
				missing: `recover = "none"` is exactly that statement, and disclosing a
				form that holds nothing more would be a plate repeating the screen.

				THE BLUEPRINT BOUNDARY REFUSES the contradiction outright (an explicit
				`expand` beside `recover = "none"`), and this is the same rule for the
				half that never passes through a constructor: a declaration driven
				straight from a test, or from `composition.resolve`, resolves the same
				way it would have on a screen. Two boundaries stating one rule
				differently is how a headless sweep stops predicting the device. ]]
			expand = r.expand or (if r.recover == "none" then "none" else "auto"),
			formInteractive = r.formInteractive,
		})
	end

	local arrangements = (decl :: any).arrangements
	if type(arrangements) ~= "table" or #arrangements == 0 then
		fail("`arrangements` must be a non-empty array, richest first — the last one is the declared fallback")
	end
	local outArrangements: { Arrangement } = {}
	for _, a in arrangements do
		local arr = composition.arrangementOf(a)
		-- EVERY affinity must have a home in EVERY arrangement, or a group
		-- silently vanishes on one device and nowhere else — the single worst
		-- failure mode this mechanism can have.
		local homes: { [string]: boolean } = {}
		for _, lane in arr.lanes do
			for _, affinity in lane do
				homes[affinity] = true
			end
		end
		for _, g in outGroups do
			-- a spanning group is outside the lane vocabulary by construction: it
			-- has the SAME row in every arrangement, which is the guarantee it exists
			-- for, so there is nothing here to have a home in
			if g.span == nil and not homes[g.lane :: string] then
				fail(
					`arrangement '{arr.name}' has no lane for affinity '{g.lane}' (group '{g.id}') — `
						.. `every group must have a home in every arrangement or it would disappear on `
						.. `exactly the devices that resolve there`
				)
			end
		end
		table.insert(outArrangements, arr)
	end

	local maxMeasure = (decl :: any).maxMeasure
	if maxMeasure ~= nil and type(maxMeasure) ~= "string" and (type(maxMeasure) ~= "number" or maxMeasure <= 0) then
		fail("`maxMeasure` is a positive px cap on both axes of the box the composition resolves in")
	end
	local measureCap = (decl :: any).measureCap
	if measureCap ~= nil and (type(measureCap) ~= "number" or measureCap ~= measureCap or measureCap <= 0) then
		fail("`measureCap` is a positive px cap on the reading width of a `fill` lane")
	end

	local normalized: any = {
		__normalized = true,
		id = (decl :: any).id,
		groups = table.freeze(outGroups),
		regions = table.freeze(outRegions),
		arrangements = table.freeze(outArrangements),
		laneGap = (decl :: any).laneGap,
		groupGap = (decl :: any).groupGap,
		maxMeasure = maxMeasure,
		measureCap = measureCap,
	}
	return table.freeze(normalized) :: Declaration
end

-- ===== resolution ==========================================================

local function placeWeights(place: any): (number, number)
	if type(place) == "number" then
		return place, 1 - place
	elseif place == "center" then
		return 1, 1
	elseif place == "end" then
		return 1, 0
	end
	return 0, 1 -- "start"
end

local function definite(v: number): boolean
	return v == v and v ~= math.huge and v >= 0
end

--[[ ...AND THE SAME TEST WITHOUT THE `>= 0`, which `definite` carries because
	every extent it guards is a LENGTH. An exclusion rect is a POSITION, and a
	position may legitimately be negative: the rects arrive in the composition's
	own box, and a host's chrome row that starts left of where the composition does
	is at a negative x. Using `definite` on one of those silently discarded every
	exclusion on a composition inset from the window origin — which is every
	composition under a policy with a gutter, i.e. all of them. ]]
local function finitePos(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

type Attempt = {
	legal: boolean,
	rule: string?,
	detail: string?,
	collisions: { { a: string, b: string, dx: number, dy: number } }?,
	capped: boolean?,
	used: { w: number, h: number },
	lanes: { any },
	spans: { any },
	groups: { any },
	regions: { RegionResolution },
}

-- The whole procedure for ONE arrangement: measure, step down, drop, place.
local function solveArrangement(
	decl: Declaration,
	arr: Arrangement,
	offerW: number,
	offerH: number,
	ctx: ResolveCtx,
	force: boolean
): Attempt
	local measureFn = ctx.measure
	-- memo: a region form is measured many times across the step-down loop, and
	-- a form is a whole subtree. Key on the box too — a hug lane's width changes
	-- as neighbours step down, and a measure at the wrong width is the classic
	-- "measured one box, painted another" defect this library keeps meeting.
	local memo: { [string]: { w: number, h: number } } = {}
	local function measure(id: string, form: number, availW: number, availH: number): (number, number)
		local key = `{id}|{form}|{availW}|{availH}`
		local hit = memo[key]
		if hit == nil then
			local w, h = measureFn(id, form, availW, availH)
			hit = {
				w = if type(w) == "number" and w == w then math.max(0, w) else 0,
				h = if type(h) == "number" and h == h then math.max(0, h) else 0,
			}
			memo[key] = hit
		end
		return hit.w, hit.h
	end

	-- METRIC NAMES ARE ALREADY PX HERE. The renderer resolves them per solve;
	-- a declaration driven straight from a test may still carry a name, and a
	-- string in an arithmetic slot must degrade to "no minimum" rather than to a
	-- runtime error inside a layout pass.
	local function px(v: any): number?
		return if type(v) == "number" and v == v then v else nil
	end
	local groupOf: { [string]: GroupDecl } = {}
	for _, g in decl.groups do
		groupOf[g.id] = g
	end
	local groupMinWidth: { [string]: number } = {}
	local groupMaxWidth: { [string]: number? } = {}
	local groupGapOf: { [string]: number } = {}
	for _, g in decl.groups do
		groupMinWidth[g.id] = px(g.minWidth) or 0
		-- B-6e: the measure's ceiling. `px` degrades an unresolved metric NAME to
		-- "no cap" exactly as `minWidth` degrades to "no minimum" — a string in an
		-- arithmetic slot must never reach a layout pass.
		groupMaxWidth[g.id] = px((g :: any).maxWidth)
		groupGapOf[g.id] = px(g.gap) or 0
	end

	-- lane index -> ordered group ids; and the affinities it absorbs
	local laneGroups: { { string } } = {}
	local laneAffinities: { { string } } = {}
	local laneOfGroup: { [string]: number } = {}
	-- ADR-0025 Decision 2: does any group in this lane pin it against rule 9?
	local laneHolds: { boolean } = {}
	for i, lane in arr.lanes do
		local ids: { string } = {}
		local holds = false
		for _, affinity in lane do
			for _, g in decl.groups do
				if g.lane == affinity then
					table.insert(ids, g.id)
					laneOfGroup[g.id] = i
					holds = holds or g.holdsLane == true
				end
			end
		end
		laneGroups[i] = ids
		laneAffinities[i] = lane
		laneHolds[i] = holds
	end

	-- THE SPANNING ROWS, in flow order: the `above` rows (declaration order),
	-- then the lane band, then the `below` rows. One group per row — two spanning
	-- groups are two bands, never one band with two columns, because a span's
	-- whole contract is "the full width of the composition".
	local spanRows: { { id: string, side: string } } = {}
	local spanOfGroup: { [string]: string } = {}
	for _, side in { "above", "below" } do
		for _, g in decl.groups do
			if g.span == side then
				table.insert(spanRows, { id = g.id, side = side })
				spanOfGroup[g.id] = side
			end
		end
	end

	-- regions per group, in declaration order
	local regionsOfGroup: { [string]: { RegionDecl } } = {}
	for _, r in decl.regions do
		local list = regionsOfGroup[r.group]
		if list == nil then
			list = {}
			regionsOfGroup[r.group] = list
		end
		table.insert(list, r)
	end

	local laneGap = px(decl.laneGap) or 0
	local groupGap = px(decl.groupGap) or 0
	--[[ THE PLATFORM'S BAND, ALREADY IN THIS COMPOSITION'S BOX (§9). `nil` on every
		composition outside a band-riding surface, which is what makes the whole
		branch below cost one nil check to a screen that never heard of it. ]]
	local bandBox = (ctx :: any).band
	--[[ ...AND THE RECTS A LANE MAY NOT START INSIDE (§8), decided ONCE. `nil` until
		the first pass has measured; from then on the same answer for every pass of
		this attempt, which is what makes the reservation a fixed point instead of a
		2-cycle (see `ResolveCtx.exclusions`). Absolute local y of the lowest
		exclusion each lane meets, so a span row changing height re-derives the INSET
		from it rather than remembering one. ]]
	local excludeBottom: { number }? = nil

	local forms: { [string]: number } = {}
	local dropped: { [string]: boolean } = {}
	for _, r in decl.regions do
		forms[r.id] = 1
	end

	local floorOf = ctx.floorOf
	local function floorFor(r: RegionDecl, availW: number, availH: number): number
		local declared = if floorOf ~= nil then floorOf(r) else nil
		if declared ~= nil then
			return math.max(0, declared)
		end
		-- the honest default: the smallest thing the author was willing to show
		local _, h = measure(r.id, r.forms, availW, availH)
		return h
	end

	-- ---- one full measurement of the current (forms, dropped) state --------
	type Pass = {
		widthFail: string?,
		laneW: { number },
		laneX: { number },
		-- §8: how far below the lane band this lane starts, because a declared
		-- exclusion occupies an x range its own content does. 0 for every lane of
		-- every composition that declares none.
		laneInset: { number },
		laneIntrinsic: { number },
		laneNeed: { number },
		laneOver: { number },
		-- HOW FAR THE WIDEST REGION IN THIS LANE PAINTS PAST IT (ADR-0025). A HUG
		-- lane is as wide as its content by construction, so this is only ever
		-- non-zero in a FILL lane, where the lane's width is a share of the box
		-- rather than a measure — and where, before this, a region too wide for its
		-- share simply painted over the lane next door with nothing to say so.
		laneWide: { number },
		active: { boolean },
		-- the spanning band: per-row need + y, the height the lanes are left with,
		-- and where that band starts. With no spanning group declared these are
		-- `{}` / `offerH` / `0`, which is arithmetically the pre-span solve.
		spanNeed: { [string]: number },
		spanY: { [string]: number },
		spanActive: { [string]: boolean },
		spanTotal: number,
		laneBudget: number,
		laneBandY: number,
		contribution: { [string]: number },
		-- measured in the lane the region ACTUALLY got (the height fact)
		measured: { [string]: { w: number, h: number } },
		-- measured against the whole offer (the width fact a hug lane is made of)
		natural: { [string]: { w: number, h: number } },
		mounted: { [string]: boolean },
		floor: { [string]: number },
		groupNeed: { [string]: number },
		usedW: number,
		capped: boolean?,
	}

	-- regions whose form filled the offer inside a HUG lane (see the note in
	-- `pass`); accumulated across passes and reported once on the resolution
	local hugOverflow: { [string]: boolean } = {}

	local function pass(): Pass
		local contribution: { [string]: number } = {}
		local measured: { [string]: { w: number, h: number } } = {}
		local natural: { [string]: { w: number, h: number } } = {}
		local mounted: { [string]: boolean } = {}
		local floors: { [string]: number } = {}
		local groupNeed: { [string]: number } = {}
		local active: { boolean } = {}

		-- WIDTH: a hug lane is as wide as its widest mounted content (and never
		-- narrower than a group's declared minWidth); the fill lanes share what
		-- is left. Measured at the FULL offer, so a lane's intrinsic width is its
		-- natural width capped by the box, exactly like `hug`.
		local laneIntrinsic: { number } = {}
		local laneMinWidth: { number } = {}
		local laneFill: { number } = {} -- summed weight, 0 = hug lane
		local anyActive = false
		for i, ids in laneGroups do
			local intrinsic, minW, fillWeight = 0, 0, 0
			local laneActive = false
			for _, gid in ids do
				local g = groupOf[gid]
				for _, r in regionsOfGroup[gid] or {} do
					if dropped[r.id] then
						continue
					end
					local w, h = measure(r.id, forms[r.id], offerW, offerH)
					natural[r.id] = { w = w, h = h }
					measured[r.id] = { w = w, h = h }
					local isMounted = w > 0 or h > 0 or r.reserved
					mounted[r.id] = isMounted
					if isMounted then
						laneActive = true
						intrinsic = math.max(intrinsic, w)
						--[[ ── A HUG REGION THAT MEASURES THE WHOLE OFFER IS NOT HUGGING ──
							Found live (RascalRally, 2026-08-02): a form in a hug group was
							authored `width = FILL`, so it measured the entire offer. Its lane's
							intrinsic width became the whole box, every lane arrangement became
							illegal on rule 2, and the composition fell to the column fallback —
							which looks, from the outside, exactly like the region VANISHING.
							No error, no diagnostic, an hour to find.

							The signature is exact and free: this is the natural measure at the
							full offer, so a hug region returning `offerW` cannot be stating an
							intrinsic width. It is reported rather than fatal because the offer
							really can be narrower than the content on a small enough screen —
							the author needs to be told, not stopped. ]]
						if g.sizing ~= "fill" and offerW > 0 and w >= offerW - 0.5 then
							hugOverflow[r.id] = true
						end
					end
				end
				minW = math.max(minW, groupMinWidth[gid])
				if g.sizing == "fill" then
					fillWeight += g.weight or 1
				end
			end
			-- RULE 9'S OPT-OUT (ADR-0025 Decision 2): a lane one of whose groups
			-- declares `holdsLane` is ACTIVE whether or not anything in it paints, so
			-- it keeps its width, its gap and its x — and every lane after it keeps
			-- the x it had. `anyActive` is deliberately NOT raised by a held lane: a
			-- composition holding three empty columns still has nothing to say.
			active[i] = laneActive or laneHolds[i]
			anyActive = anyActive or laneActive
			laneIntrinsic[i] = math.max(intrinsic, if fillWeight > 0 then 0 else minW)
			laneMinWidth[i] = minW
			laneFill[i] = fillWeight
		end

		local nActive = 0
		for i in laneGroups do
			if active[i] then
				nActive += 1
			end
		end
		local gapsW = if nActive > 1 then laneGap * (nActive - 1) else 0
		local hugTotal, fillWeightTotal = 0, 0
		for i in laneGroups do
			if not active[i] then
				continue
			end
			if laneFill[i] > 0 then
				fillWeightTotal += laneFill[i]
			else
				hugTotal += laneIntrinsic[i]
			end
		end

		local laneW: { number } = {}
		-- which fill lanes have reached `measureCap` and are out of the water-fill
		local laneCapped: { [number]: boolean } = {}
		local widthFail: string? = nil
		local slack = offerW - hugTotal - gapsW
		--[[ FRACTIONAL FILL SHARES ARE A KNOWN, SCOPED DEFECT — not fixed here.

			Three lanes of a 359px box are 119.666px each, and a row shrunk to fill
			one of them lands ~0.0004px past its own edge, which the solver reports
			as "overflows by 0px". Rounding the shares to whole pixels (remainder to
			the last fill lane) removes it — and, measured on 2026-08-14, also
			removes SIX waived findings across `composition` and `p2_cartwheel`,
			because a fractional lane box is what several of them are made of.

			That is a corpus-wide geometry change with its own waiver-list edits, so
			it is FLAGGED rather than smuggled into a HUD mission (ENGINEERING.md,
			"Flag refactors; don't smuggle them"). Recorded in ADR-0025's
			Consequences as stage-2 work. ]]
		if slack < 0 then
			widthFail = string.format(
				"the hug lanes need %dpx plus %dpx of gaps but the composition was offered %dpx",
				roundPx(hugTotal),
				roundPx(gapsW),
				roundPx(offerW)
			)
		end
		--[[ THE MEASURE CAP, AND THE SLACK IT FREES (B-6e, ruling R14, 2026-08-21).

			A `fill` lane's width is a SHARE of the slack, and a share of a
			television is a reading line nobody can track back to its own start:
			the audit measured a ten-foot main lane at 1316px against the
			regular-touch tablet's 600, which is the desktop answer with more
			pixels rather than a distance answer at all.

			`measureCap` caps that share. What it frees is offered back to the
			OTHER fill lanes — "the lanes re-absorb the slack per the arrangement's
			own rules" — by water-filling: every uncapped fill lane divides the
			freed width by its own weight, bounded by the cap in its turn, until
			nothing is left to give or every lane is at the cap. Bounded by the
			lane count, so an arrangement of N lanes costs at most N passes.

			WHAT IS STILL LEFT OVER IS NOT SPENT ON WIDTH. It becomes the centring
			offset the resolution already carries for `maxMeasure` (see `resolve`),
			because widening a lane past the ruled measure is the thing the cap
			exists to prevent, and parking a capped band against the left edge is a
			worse answer than the one it replaced. ]]
		-- A LANE'S CAP IS THE TIGHTEST ITS OWN FILL GROUPS ASKED FOR. Groups share a
		-- lane's width, so two caps in one lane are one lane cap, and the smaller is
		-- the only reading that honours both.
		local laneCap: { [number]: number } = {}
		for i, ids in laneGroups do
			for _, gid in ids do
				local g = groupOf[gid]
				local cap = if g ~= nil and g.sizing == "fill" then groupMaxWidth[gid] else nil
				if cap ~= nil then
					laneCap[i] = if laneCap[i] == nil then cap else math.min(laneCap[i], cap)
				end
			end
		end
		local anyCap = next(laneCap) ~= nil
		local function fillShares(pool: number)
			local remaining = math.max(0, pool)
			local openWeight = fillWeightTotal
			for _ = 1, #laneGroups do
				if remaining <= 0 or openWeight <= 0 then
					break
				end
				local spent, closedWeight = 0, 0
				for i in laneGroups do
					if not active[i] or laneFill[i] <= 0 or laneCapped[i] then
						continue
					end
					local cap = laneCap[i]
					local share = (laneW[i] or 0) + remaining * (laneFill[i] / openWeight)
					if cap ~= nil and share > cap then
						spent += cap - (laneW[i] or 0)
						laneW[i] = cap
						laneCapped[i] = true
						closedWeight += laneFill[i]
					else
						spent += share - (laneW[i] or 0)
						laneW[i] = share
					end
				end
				remaining -= spent
				openWeight -= closedWeight
				if closedWeight <= 0 then
					break
				end
			end
		end
		for i in laneGroups do
			if not active[i] then
				laneW[i] = 0
				continue
			end
			if laneFill[i] > 0 and fillWeightTotal > 0 then
				laneW[i] = 0
			else
				laneW[i] = laneIntrinsic[i]
			end
		end
		fillShares(slack)
		for i in laneGroups do
			if not active[i] then
				continue
			end
			if laneFill[i] > 0 and fillWeightTotal > 0 then
				laneW[i] = math.max(laneW[i], 0)
				if widthFail == nil and laneW[i] < laneMinWidth[i] then
					widthFail = string.format(
						"lane %d (%s) resolved to %dpx but its group declares a %dpx minimum",
						i,
						table.concat(laneAffinities[i], "+"),
						roundPx(laneW[i]),
						roundPx(laneMinWidth[i])
					)
				end
			end
		end
		-- THE SPANNING BAND, before the lanes: a span row is the composition's full
		-- width by definition, so it is measured once at the offer's width and its
		-- height is simply what its content needs. What is left is the lane band's
		-- budget — which is how a spanning row participates in the SAME height
		-- economy as every lane instead of being a free band that overflows the box.
		local spanNeed: { [string]: number } = {}
		local spanY: { [string]: number } = {}
		local spanActive: { [string]: boolean } = {}
		local spanIntrinsic = 0
		local spanTotal = 0
		local spanRowCount = 0
		for _, row in spanRows do
			local gid = row.id
			local gGap = groupGapOf[gid]
			local need = 0
			local n = 0
			--[[ THE BAND ROW IS MEASURED AGAINST THE FREE STRIP, NOT THE COMPOSITION
				(§9). A span row is the composition's full width by definition — except
				this one, whose width is a PLATFORM FACT: the part of the top band the
				engine's own control cluster leaves. Measuring it at the offer would
				let a chip that fits the screen but not the strip choose its richest
				form and then paint over the platform's buttons. On a 320px phone the
				free band is ~156px, so the difference is the whole feature. ]]
			local rowW = if gid == BAND_ZONE and bandBox ~= nil then (bandBox :: any).w else offerW
			for _, r in regionsOfGroup[gid] or {} do
				if dropped[r.id] then
					continue
				end
				local w, h = measure(r.id, forms[r.id], rowW, offerH)
				natural[r.id] = { w = w, h = h }
				measured[r.id] = { w = w, h = h }
				local isMounted = w > 0 or h > 0 or r.reserved
				mounted[r.id] = isMounted
				if not isMounted then
					continue
				end
				spanIntrinsic = math.max(spanIntrinsic, w)
				local fl = floorFor(r, offerW, offerH)
				floors[r.id] = fl
				local c = if r.sizing == "fill" then fl else h
				if r.reserved then
					c = math.max(c, fl)
				end
				contribution[r.id] = c
				need += c
				n += 1
			end
			if n > 1 then
				need += gGap * (n - 1)
			end
			--[[ ...AND ITS HEIGHT IS THE BAND'S, not its content's (§9). The row IS
				the platform's strip: it reaches the band's own bottom edge whatever it
				holds, so the lanes below start exactly where the platform's row ends
				and a taller chip cannot push them down. The floor a `reserved` region
				declares still applies to the CONTENT inside it, exactly as before. ]]
			if gid == BAND_ZONE and bandBox ~= nil and n > 0 then
				need = math.max(0, (bandBox :: any).h)
			end
			groupNeed[gid] = need
			spanNeed[gid] = need
			spanActive[gid] = n > 0
			if n > 0 then
				spanRowCount += 1
				spanTotal += need
				anyActive = true
			end
		end
		if not anyActive then
			widthFail = widthFail or "every region resolved to nothing — the composition has no content to place"
		end
		-- rows are separated by the composition's own vertical rhythm, exactly like
		-- two groups stacked inside one lane
		local bandRows = spanRowCount + (if nActive > 0 then 1 else 0)
		local spanGaps = if bandRows > 1 then groupGap * (bandRows - 1) else 0
		--[[ THE LANE BAND NEVER STARTS INSIDE THE PLATFORM'S OWN RESERVATION (§9).

			`bandSafeContent`'s content rect starts where the FREE STRIP starts, which
			is above the platform's whole top reservation — so without this the top
			lane would begin at the band's bottom edge and, on a host that reserves
			more than the strip (a showcase with a chip row of its own inflating
			`coreSafeInsets.top`, which is a BOUNDING BOX and all such a host has
			said), it would begin inside that reservation.

			So the `topbar` row rides the strip and the LANES start at the whole
			reservation, which are two different edges and coincide on a platform whose
			CoreGui inset is exactly its topbar band. That is the arrangement the HUD
			demo reached by hand with a fixed-height row plus a per-column reserve of
			`insets.top - spent`, and it is what makes the policy additive in risk: a
			composition that declares no `topbar` region gets exactly the lane band
			`deviceSafeContent` would have given it. ]]
		--[[ ...AND A HOST THAT HAS SAID WHERE ITS CHROME IS GETS THE PLATFORM'S OWN
			ROW INSTEAD OF THE BOUNDING BOX (§9 x §8, the director's item 4).

			`reserve` is the whole top inset, and on a host with a persistent chrome
			row of its own that inset is INFLATED by it — a bounding box, which is all
			such a host has said. Reserving it in every lane is the defect ADR-0027
			exists to remove: it pushes a column the chrome does not cover down for
			pixels nothing occupies, which is the director's *"things at top that are
			aligned with the controls but don't overlap"* refused.

			A composition that declares `exclusions` HAS said where its chrome is, per
			column, so the bounding box is no longer the best available answer: the
			lanes start at the platform's OWN row and the declared rects push down only
			the lanes whose content meets them. Declaring nothing keeps the bounding
			box, byte for byte — which is what a host that never adopted the
			declaration has always had. ]]
		local hasExclusions = type((ctx :: any).exclusions) == "table" and #((ctx :: any).exclusions :: any) > 0
		--[[ ...AND ONLY A COMPOSITION THAT IS ACTUALLY RIDING THE STRIP GETS THE
			SHORTER FLOOR. A `topbar` row that resolved to nothing is a surface not
			riding the band at all — the demo's ride switch, or a platform that
			reported no strip — and such a surface owes the platform's whole row
			whatever else it has declared. So the short floor needs BOTH: a row in the
			strip, and a host that has said where its own chrome is. ]]
		local bandReserve = if bandBox == nil
			then 0
			elseif hasExclusions and spanActive[BAND_ZONE] == true then math.max(0, (bandBox :: any).h)
			else math.max(0, (bandBox :: any).reserve)
		-- what the `above` rows have already spent, so the reservation is a FLOOR on
		-- where the lanes start rather than a second thing added to them
		local aboveSpent = 0
		do
			local n = 0
			for _, row in spanRows do
				if row.side == "above" and spanActive[row.id] then
					aboveSpent += groupNeed[row.id] or 0
					n += 1
				end
			end
			if n > 0 then
				aboveSpent += groupGap * n
			end
		end
		local bandGap = math.max(0, bandReserve - aboveSpent)
		local laneBudget = offerH - spanTotal - spanGaps - bandGap
		-- one cursor down the flow: every `above` row, then the lane band, then
		-- every `below` row. `spanRows` is already in that order.
		local laneBandY = 0
		do
			local y = 0
			local bandPlaced = nActive == 0
			for _, row in spanRows do
				if not spanActive[row.id] then
					continue
				end
				if row.side == "below" and not bandPlaced then
					bandPlaced = true
					y += bandGap
					laneBandY = y
					y += math.max(0, laneBudget) + groupGap
				end
				spanY[row.id] = y
				y += (groupNeed[row.id] or 0) + groupGap
			end
			if not bandPlaced then
				-- every span row was `above`; the band closes the flow
				laneBandY = y + bandGap
			end
		end

		-- HEIGHT: re-measure inside the lane the region actually got, then a
		-- lane's need is its hug content plus the FLOORS of its fill content.
		-- A fill region takes slack above its floor; it never sinks below it.
		local laneNeed: { number } = {}
		local laneOver: { number } = {}
		local laneWide: { number } = {}
		local laneX: { number } = {}
		local cursor = 0
		for i, ids in laneGroups do
			laneX[i] = cursor
			if active[i] then
				cursor += laneW[i] + laneGap
			end
			local need = 0
			local mountedGroups = 0
			-- ...and the WIDTH sibling of `laneOver`, accumulated in this same walk
			-- rather than in a second one (the off-path cost of a feature nobody
			-- declared has to be ~zero). Rule 2 asks whether the HUG lanes fit the
			-- offer, which is the only width question a lane whose width IS its
			-- content can fail; a `fill` lane's width is a SHARE, so a region wider
			-- than its share used to overflow silently onto its neighbour. It is an
			-- overflow like any other and goes to the same ladder (rule 3).
			local wide = 0
			for _, gid in ids do
				local g = groupOf[gid]
				local gGap = groupGapOf[gid]
				local gNeed = 0
				local n = 0
				for _, r in regionsOfGroup[gid] or {} do
					if dropped[r.id] or not mounted[r.id] then
						continue
					end
					local w, h = measure(r.id, forms[r.id], laneW[i], offerH)
					measured[r.id] = { w = w, h = h }
					if not r.mayScroll and w > laneW[i] then
						wide = math.max(wide, w - laneW[i])
					end
					local fl = floorFor(r, laneW[i], offerH)
					floors[r.id] = fl
					local c: number
					if r.sizing == "fill" then
						c = fl
					else
						c = h
					end
					if r.reserved then
						-- rule 7: a rested reserved region never falls below its floor,
						-- so a transient finishing cannot move its neighbours
						c = math.max(c, fl)
					end
					contribution[r.id] = c
					gNeed += c
					n += 1
				end
				if n > 1 then
					gNeed += gGap * (n - 1)
				end
				groupNeed[gid] = gNeed
				if n > 0 then
					mountedGroups += 1
					need += gNeed
				end
			end
			if mountedGroups > 1 then
				need += groupGap * (mountedGroups - 1)
			end
			laneNeed[i] = need
			laneWide[i] = if active[i] then wide else 0
		end

		--[[ ── WHICH LANES GIVE WAY TO THE HOST'S OWN CHROME (§8) ─────────────────
			Decided on the FIRST pass and never re-decided, from the richest forms and
			the widths they measured — see `ResolveCtx.exclusions` for why re-asking
			is a 2-cycle rather than a refinement, and why a coverage fraction is a
			guess about a width this module already knows.

			The x range a lane occupies is the range its own REGIONS occupy, which is
			the lane's box unless the group declares an `align` — and when it does, it
			is the width the region MEASURED at that end of the lane. That is the same
			arithmetic the placement pass below runs, and it is the difference between
			"the right column is 46% covered" and "the right column's `end`-anchored
			rail is inside the chrome row". ]]
		local exclusions = (ctx :: any).exclusions
		if excludeBottom == nil then
			local decided: { number } = {}
			for i, ids in laneGroups do
				local bottom = -math.huge
				if type(exclusions) == "table" and active[i] then
					for _, gid in ids do
						local g = groupOf[gid]
						for _, r in regionsOfGroup[gid] or {} do
							if dropped[r.id] or not mounted[r.id] then
								continue
							end
							local rx, rw = laneX[i], laneW[i]
							if g.align ~= nil then
								local m = measured[r.id]
								rw = math.min(if m ~= nil then m.w else rw, laneW[i])
								local f = if g.align == "center" then 0.5 elseif g.align == "end" then 1 else 0
								rx = laneX[i] + roundPx((laneW[i] - rw) * f)
							end
							for _, ex in exclusions :: any do
								--[[ A MALFORMED RECT IS SKIPPED, NEVER CLAMPED. This module is
									PURE and drivable straight from a test, so it cannot assume the
									caller normalized: a rect with no width is not an exclusion, and
									clamping one to zero would put it at the origin, where it would
									exclude the first column of every lane. Same refuse-don't-guess
									rule the env fact's own merge applies to a declared chrome row. ]]
								if
									type(ex) ~= "table"
									or not finitePos(ex.x)
									or not finitePos(ex.y)
									or not finitePos(ex.w)
									or not finitePos(ex.h)
									or ex.w <= 0
									or ex.h <= 0
								then
									continue
								end
								if math.min(rx + rw, ex.x + ex.w) - math.max(rx, ex.x) > 0.5 then
									bottom = math.max(bottom, ex.y + ex.h)
								end
							end
						end
					end
				end
				decided[i] = bottom
			end
			excludeBottom = decided
		end
		local laneInset: { number } = {}
		for i in laneGroups do
			local bottom = (excludeBottom :: { number })[i]
			laneInset[i] = if bottom > -math.huge then math.max(0, bottom - laneBandY) else 0
		end
		for i in laneGroups do
			-- the lanes are short of what the SPANS left them, not of the whole
			-- offer — with no spans declared `laneBudget` IS `offerH` — and short by
			-- the exclusion this lane gave way to on top of that
			laneOver[i] = if active[i] then laneNeed[i] - (laneBudget - laneInset[i]) else 0
		end

		local usedW = 0
		for i in laneGroups do
			if active[i] then
				usedW += laneW[i]
			end
		end
		usedW += gapsW
		-- a span row PAINTS the full width but MEASURES its content: a `hug`-width
		-- composition must not report "I need the whole offer" just because it has
		-- a band (the same lie the uniform Grid cell used to tell)
		usedW = math.max(usedW, spanIntrinsic)

		return {
			widthFail = widthFail,
			laneW = laneW,
			laneX = laneX,
			laneInset = laneInset,
			laneIntrinsic = laneIntrinsic,
			laneNeed = laneNeed,
			laneOver = laneOver,
			laneWide = laneWide,
			active = active,
			contribution = contribution,
			measured = measured,
			natural = natural,
			mounted = mounted,
			floor = floors,
			groupNeed = groupNeed,
			usedW = usedW,
			-- B-6e: did a lane cap actually bite in this attempt? `resolve` centres
			-- on it, and asking the ATTEMPT rather than re-deriving from the
			-- declaration is what keeps one owner for the arithmetic.
			capped = anyCap,
			spanNeed = spanNeed,
			spanY = spanY,
			spanActive = spanActive,
			spanTotal = spanTotal + spanGaps,
			laneBudget = laneBudget,
			laneBandY = laneBandY,
		}
	end

	-- ---- the step-down / drop loop (rules 3-5) -----------------------------
	-- Candidates come from the lane(s) that do NOT fit — degrading a region in a
	-- lane that already fits costs legibility and buys nothing. On a WIDTH
	-- failure the hug lanes are what has to give, because they are what the
	-- width is made of.
	local function candidates(p: Pass): { RegionDecl }
		local wanted: { [number]: boolean } = {}
		-- A SPANNING ROW IS A CANDIDATE ON A HEIGHT FAILURE, NEVER ON A WIDTH ONE.
		-- Its width is the composition's, so narrowing it buys no lane a pixel;
		-- its height comes out of the SAME budget every lane shares, so shortening
		-- it relieves every overflowing lane at once (rule 3's "must buy a pixel",
		-- applied to a row instead of a lane).
		local wantSpans = false
		if p.widthFail ~= nil then
			for i in laneGroups do
				local isFill = false
				for _, gid in laneGroups[i] do
					if groupOf[gid].sizing == "fill" then
						isFill = true
					end
				end
				if p.active[i] and not isFill then
					wanted[i] = true
				end
			end
		else
			for i in laneGroups do
				if p.active[i] and (p.laneOver[i] > 0 or p.laneWide[i] > 0) then
					wanted[i] = true
					wantSpans = true
				end
			end
			-- spans alone can overflow a composition with no lane content at all
			if p.spanTotal > offerH then
				wantSpans = true
			end
		end
		local out: { RegionDecl } = {}
		for _, r in decl.regions do
			if dropped[r.id] or not p.mounted[r.id] then
				continue
			end
			local span = spanOfGroup[r.group]
			if if span ~= nil then wantSpans else wanted[laneOfGroup[r.group]] then
				table.insert(out, r)
			end
		end
		return out
	end

	-- ...AND IT MUST BUY A PIXEL. "Descending rank until everything fits" taken
	-- literally degrades six regions to save one: on a width failure the only
	-- thing that narrows a hug lane is the region that SETS its intrinsic width,
	-- and stepping the other five down changes nothing while visibly cheapening
	-- the screen. So a candidate also has to be able to help the failure it is
	-- being asked to fix — which is what makes the resolution match the
	-- commissioning spec's own worked case ("the CTAs drop to their column
	-- candidate before anything else moves"), from the general rule rather than
	-- from a special case.
	local EPS = 0.5
	-- can this region give the lane any width at all — a strictly narrower next
	-- form, or a legal drop? (`reserved` never drops, rule 7.)
	local function canNarrow(r: RegionDecl, p: Pass): boolean
		if r.mayDrop and not r.reserved then
			return true
		end
		if forms[r.id] < r.forms then
			local cur = p.natural[r.id]
			local nw = select(1, measure(r.id, forms[r.id] + 1, offerW, offerH))
			return cur ~= nil and nw < cur.w - EPS
		end
		return false
	end
	-- ...AND THE LANE HAS TO BE ABLE TO COME DOWN AT ALL. Being AT the lane's
	-- intrinsic is necessary but not sufficient: when a region that CANNOT
	-- narrow (its last form, and not droppable) sits at the same width, the
	-- lane's width is PINNED by that region, and degrading anything else in the
	-- lane cheapens the screen without buying a pixel — the same failure the
	-- filter above exists to remove, one step further out. A group's declared
	-- `minWidth` pins its lane the same way.
	--
	-- Found consuming the mechanism (RascalRally S16 v2, 2026-07-31): the
	-- ceremony lane held a hero plate at the lane's own measure (last form, no
	-- drop) and a rivalry callout (rank 7, `mayDrop`) at the same measure, so
	-- every landscape phone dropped the callout and the lane stayed exactly as
	-- wide as before. With the lane pinned the arrangement is simply illegal,
	-- and the next candidate is tried with every region intact.
	local function lanePinned(lane: number, p: Pass): number
		local pinned = 0
		for _, gid in laneGroups[lane] or {} do
			pinned = math.max(pinned, groupMinWidth[gid])
			for _, r in regionsOfGroup[gid] or {} do
				if dropped[r.id] or not p.mounted[r.id] then
					continue
				end
				if not canNarrow(r, p) then
					pinned = math.max(pinned, (p.natural[r.id] or { w = 0 }).w)
				end
			end
		end
		return pinned
	end
	local function narrows(r: RegionDecl, p: Pass): boolean
		local lane = laneOfGroup[r.group]
		local cur = p.natural[r.id]
		local intrinsic = p.laneIntrinsic[lane] or 0
		if cur == nil or cur.w < intrinsic - EPS then
			return false -- not what this lane's width is made of
		end
		return lanePinned(lane, p) < intrinsic - EPS
	end
	-- how far past its own lane this region paints. It is what makes a width
	-- candidate "buy a pixel" in a FILL lane: the region that is over is the only
	-- one narrowing anything, exactly as the region that SETS a hug lane's
	-- intrinsic is the only one narrowing that.
	local function overWidth(r: RegionDecl, p: Pass): number
		local lane = laneOfGroup[r.group]
		if lane == nil or r.mayScroll then
			return 0
		end
		local m = p.measured[r.id]
		if m == nil then
			return 0
		end
		return m.w - (p.laneW[lane] or 0)
	end
	local function stepHelps(r: RegionDecl, p: Pass): boolean
		if forms[r.id] >= r.forms then
			return false
		end
		local lane = laneOfGroup[r.group]
		if p.widthFail ~= nil then
			-- a span never narrows a lane (`candidates` never offers one here)
			if lane == nil or not narrows(r, p) then
				return false
			end
			local nw = select(1, measure(r.id, forms[r.id] + 1, offerW, offerH))
			return nw < (p.natural[r.id] :: any).w - EPS
		end
		-- a spanning region's box IS the offer's width
		local nw, nh = measure(r.id, forms[r.id] + 1, if lane == nil then offerW else p.laneW[lane], offerH)
		if r.reserved then
			nh = math.max(nh, p.floor[r.id] or 0)
		end
		-- ...and the WIDTH half: when this region is the one painting past its
		-- lane, a next form that is narrower buys exactly those pixels back
		if lane ~= nil and p.laneWide[lane] > EPS and overWidth(r, p) > EPS then
			local m = p.measured[r.id]
			if m ~= nil and nw < m.w - EPS then
				return true
			end
		end
		return nh < (p.contribution[r.id] or 0) - EPS
	end
	local function dropHelps(r: RegionDecl, p: Pass): boolean
		if not r.mayDrop or r.reserved then
			return false
		end
		if p.widthFail ~= nil then
			return laneOfGroup[r.group] ~= nil and narrows(r, p)
		end
		local lane = laneOfGroup[r.group]
		if lane ~= nil and p.laneWide[lane] > EPS and overWidth(r, p) > EPS then
			return true
		end
		return (p.contribution[r.id] or 0) > EPS
	end

	-- DESCENDING RANK, then descending declaration index. The tie-break is
	-- declared and testable on purpose: "predict every device from the table
	-- alone" is only true if ties are not resolved by table iteration order.
	local declIndex: { [string]: number } = {}
	for i, r in decl.regions do
		declIndex[r.id] = i
	end
	local function worst(list: { RegionDecl }, ok: (RegionDecl) -> boolean): RegionDecl?
		local best: RegionDecl? = nil
		for _, r in list do
			if not ok(r) then
				continue
			end
			if
				best == nil
				or r.rank > (best :: RegionDecl).rank
				or (r.rank == (best :: RegionDecl).rank and declIndex[r.id] > declIndex[(best :: RegionDecl).id])
			then
				best = r
			end
		end
		return best
	end

	local p = pass()
	local guard = 0
	local budget = #decl.regions * 2
	for _, r in decl.regions do
		budget += r.forms
	end
	while true do
		local overflowing = false
		for i in laneGroups do
			if p.active[i] and (p.laneOver[i] > 0.5 or p.laneWide[i] > 0.5) then
				overflowing = true
			end
		end
		-- a composition that is nothing BUT spanning rows still has to fit
		if p.spanTotal > offerH + 0.5 then
			overflowing = true
		end
		if p.widthFail == nil and not overflowing then
			break
		end
		guard += 1
		if guard > budget then
			break -- structurally impossible; the bound is the proof, not a hope
		end
		local cands = candidates(p)
		-- rule 3: STEP DOWN before DROP, both descending rank
		local step = worst(cands, function(r)
			return stepHelps(r, p)
		end)
		if step ~= nil then
			forms[step.id] += 1
			p = pass()
			continue
		end
		local drop = worst(cands, function(r)
			return dropHelps(r, p)
		end)
		if drop ~= nil then
			dropped[drop.id] = true
			p = pass()
			continue
		end
		-- rule 5: nothing left to give. A lane that overflows and holds no
		-- scrollable region cannot be made legal by this arrangement.
		if not force then
			local rule = if p.widthFail ~= nil then "laneWidth" else "overflow"
			local detail = p.widthFail
			if detail == nil then
				for i in laneGroups do
					if p.active[i] and p.laneWide[i] > 0.5 then
						detail = string.format(
							"lane %d (%s) is %dpx wide but its widest region measures %dpx, and no region in "
								.. "it can step down or drop",
							i,
							table.concat(laneAffinities[i], "+"),
							roundPx(p.laneW[i]),
							roundPx(p.laneW[i] + p.laneWide[i])
						)
						break
					end
					if p.active[i] and p.laneOver[i] > 0.5 then
						detail = string.format(
							"lane %d (%s) needs %dpx but the composition was offered %dpx%s, and no region in "
								.. "it can step down, drop or scroll",
							i,
							table.concat(laneAffinities[i], "+"),
							roundPx(p.laneNeed[i]),
							roundPx(offerH),
							if p.spanTotal > 0.5
								then string.format(" (%dpx of it spanning rows)", roundPx(p.spanTotal))
								else ""
						)
						break
					end
				end
			end
			if detail == nil and p.spanTotal > offerH + 0.5 then
				detail = string.format(
					"the spanning rows need %dpx but the composition was offered %dpx, and no region in them "
						.. "can step down or drop",
					roundPx(p.spanTotal),
					roundPx(offerH)
				)
			end
			return {
				legal = false,
				rule = rule,
				hugOverflow = hugOverflow,
				collisions = {},
				detail = detail or "the offer cannot hold this arrangement",
				used = { w = 0, h = 0 },
				lanes = {},
				spans = {},
				groups = {},
				regions = {},
			}
		end
		break
	end

	-- ---- placement (rule 6: slack flows to `fill`) -------------------------
	local lanes: { any } = {}
	local groups: { any } = {}
	local regionResolutions: { RegionResolution } = {}
	local byId: { [string]: RegionResolution } = {}
	local laneUsedH = 0

	for _, r in decl.regions do
		local res: RegionResolution = {
			id = r.id,
			rank = r.rank,
			group = r.group,
			lane = nil,
			form = forms[r.id],
			mounted = false,
			dropped = dropped[r.id] == true,
			-- D7.1: a form below the richest was chosen. A dropped region is showing
			-- nothing rather than showing less, so the two are never both true.
			elided = dropped[r.id] ~= true and forms[r.id] > 1,
			floor = p.floor[r.id] or 0,
			rect = nil,
			-- the expand facts are filled in by `resolve` once an arrangement has
			-- been CHOSEN (see the block there); a candidate that lost never had a
			-- standing form to describe
			activeForm = 0,
			richestForm = 1,
			formInteractive = false,
			expand = (r :: any).expand or "auto",
			expandable = false,
			plate = nil,
		}
		regionResolutions[#regionResolutions + 1] = res
		byId[r.id] = res
	end

	-- the spanning rows first: each is one full-width band at its own cursor, and
	-- its regions stack inside it exactly like a group's regions inside a lane
	local spans: { any } = {}
	for _, row in spanRows do
		local gid = row.id
		if not p.spanActive[gid] then
			continue
		end
		--[[ THE BAND ROW IS THE ONE SPAN THAT IS NOT FULL WIDTH (§9). Every other
			span row paints the composition's whole width by definition; this one
			paints the part of the platform's top band the engine's own control
			cluster leaves free, so its content sits LEVEL with the platform's buttons
			and cannot be over them (ADR-0027) — which is the placement a consumer
			previously reached with two hand-computed spacers and a fixed height. ]]
		local rowX = if gid == BAND_ZONE and bandBox ~= nil then (bandBox :: any).x else 0
		local rowW = if gid == BAND_ZONE and bandBox ~= nil then (bandBox :: any).w else offerW
		local rowRect: Rect = { x = rowX, y = p.spanY[gid] or 0, w = rowW, h = p.spanNeed[gid] or 0 }
		table.insert(spans, { id = gid, side = row.side, rect = rowRect })
		table.insert(groups, { id = gid, lane = nil, span = row.side, rect = rowRect })
		local gGap = groupGapOf[gid]
		--[[ A SPAN ROW'S SLACK GOES TO ITS `fill` REGIONS — rule 6, applied to a row
			instead of a lane (§9). Until the band existed a span row was EXACTLY as
			tall as its content, so there was never any slack to give and this is inert
			on every composition that declares no `topbar` region: `rowSlack` is 0 and
			the loop below is what it always was. The band row is the first row whose
			height is a PLATFORM FACT rather than a measurement, so a region that says
			`sizing = "fill"` in it means what it means everywhere else in this module
			— take the box, so the content can centre in the strip rather than sitting
			at the top of it. ]]
		local rowFill = 0
		local rowContent = 0
		local rowMounted = 0
		for _, r in regionsOfGroup[gid] or {} do
			if dropped[r.id] or not p.mounted[r.id] then
				continue
			end
			rowMounted += 1
			rowContent += p.contribution[r.id] or 0
			if r.sizing == "fill" then
				rowFill += r.weight or 1
			end
		end
		if rowMounted > 1 then
			rowContent += gGap * (rowMounted - 1)
		end
		local rowSlack = math.max(0, rowRect.h - rowContent)
		local ry = rowRect.y
		for _, r in regionsOfGroup[gid] or {} do
			if dropped[r.id] or not p.mounted[r.id] then
				continue
			end
			local h = p.contribution[r.id] or 0
			if rowFill > 0 and r.sizing == "fill" then
				h += rowSlack * ((r.weight or 1) / rowFill)
			end
			local res = byId[r.id]
			res.mounted = true
			res.span = row.side
			res.rect = { x = rowX, y = ry, w = rowW, h = h }
			ry += h + gGap
		end
	end

	for i, ids in laneGroups do
		if not p.active[i] then
			-- RULE 9, EMPTY-LANE RELEASE. `pass()` already took this lane out of
			-- `hugTotal` and out of the gap count, so its width has ALREADY gone to
			-- the fill lanes; what is left is to SAY so. A collapsed lane is reported
			-- at the x it would have started at with a zero-width rect and no groups,
			-- which is the one difference a dump can state and a screenshot cannot.
			table.insert(lanes, {
				index = i,
				affinities = laneAffinities[i],
				groups = {},
				rect = { x = p.laneX[i], y = p.laneBandY, w = 0, h = math.max(0, p.laneBudget) },
				collapsed = true,
			})
			continue
		end
		--[[ ...AND THE LANE BAND IS A RECTANGLE NO LONGER (§8). A lane that gave way
			to a declared exclusion starts below it and is shorter by exactly that,
			which is the L a host's own chrome row makes of the band's top edge. Every
			lane of every composition that declares no exclusions has an inset of 0
			here and is byte-identical to what it was. ]]
		local inset = math.max(0, (p.laneInset[i] or 0))
		local laneRect: Rect =
			{ x = p.laneX[i], y = p.laneBandY + inset, w = p.laneW[i], h = math.max(0, p.laneBudget - inset) }
		local mountedGroups: { string } = {}
		for _, gid in ids do
			for _, r in regionsOfGroup[gid] or {} do
				if not dropped[r.id] and p.mounted[r.id] then
					table.insert(mountedGroups, gid)
					break
				end
			end
		end
		table.insert(lanes, {
			index = i,
			affinities = laneAffinities[i],
			groups = mountedGroups,
			rect = laneRect,
			collapsed = false,
			-- §8: reported only when it bit, so a dump of a composition that declares
			-- no exclusions is byte-identical to the one it printed before the feature
			exclusion = if inset > 0 then inset else nil,
		})
		laneUsedH = math.max(laneUsedH, inset + p.laneNeed[i])

		local slack = math.max(0, p.laneBudget - p.laneNeed[i])
		local fillWeight = 0
		for _, gid in mountedGroups do
			if groupOf[gid].sizing == "fill" then
				fillWeight += groupOf[gid].weight or 1
			end
		end
		-- when no group in this lane fills, the leftover becomes the lane's
		-- spacer run, weighted by each group's declared placement
		local spacerWeights: { number } = {}
		local spacerTotal = 0
		if fillWeight == 0 and #mountedGroups > 0 then
			local prevAfter = 0
			for idx, gid in mountedGroups do
				local before, after = placeWeights(groupOf[gid].place)
				spacerWeights[idx] = prevAfter + before
				prevAfter = after
				if idx == #mountedGroups then
					spacerWeights[idx + 1] = after
				end
			end
			for _, w in spacerWeights do
				spacerTotal += w
			end
		end

		local y = laneRect.y
		if spacerTotal > 0 then
			y += slack * (spacerWeights[1] / spacerTotal)
		end
		for idx, gid in mountedGroups do
			local g = groupOf[gid]
			local gh = p.groupNeed[gid] or 0
			if fillWeight > 0 and g.sizing == "fill" then
				gh += slack * ((g.weight or 1) / fillWeight)
			end
			table.insert(groups, { id = gid, lane = i, rect = { x = laneRect.x, y = y, w = laneRect.w, h = gh } })

			-- inside a group: hug regions take their measure, fill regions take
			-- their floor plus their share of what is left
			local gGap = groupGapOf[gid]
			local mountedRegions: { RegionDecl } = {}
			local regionFill = 0
			for _, r in regionsOfGroup[gid] or {} do
				if dropped[r.id] or not p.mounted[r.id] then
					continue
				end
				table.insert(mountedRegions, r)
				if r.sizing == "fill" then
					regionFill += r.weight or 1
				end
			end
			local rSlack = math.max(0, gh - (p.groupNeed[gid] or 0))
			local ry = y
			for _, r in mountedRegions do
				local h = p.contribution[r.id] or 0
				if regionFill > 0 and r.sizing == "fill" then
					h += rSlack * ((r.weight or 1) / regionFill)
				end
				local res = byId[r.id]
				res.mounted = true
				res.lane = i
				-- ACROSS the lane (ADR-0025 Decision 1). Absent `align`, a region takes
				-- the whole lane width — the allotment contract, unchanged. Declared, it
				-- takes the width it MEASURED in this lane and sits at that end:
				-- aligning a box that already fills its lane would mean nothing, so
				-- asking for the alignment is what asks for the content width.
				local rx, rw = laneRect.x, laneRect.w
				if g.align ~= nil then
					local m = p.measured[r.id]
					rw = math.min(if m ~= nil then m.w else rw, laneRect.w)
					local f = if g.align == "center" then 0.5 elseif g.align == "end" then 1 else 0
					rx = laneRect.x + roundPx((laneRect.w - rw) * f)
				end
				res.rect = { x = rx, y = ry, w = rw, h = h }
				ry += h + gGap
			end

			y += gh + groupGap
			if spacerTotal > 0 then
				y += slack * ((spacerWeights[idx + 1] or 0) / spacerTotal)
			end
		end
	end

	--[[ ── WHO IS ON TOP OF WHOM (ADR-0025 Decision 3) ─────────────────────────
		Regions cannot overlap as BOXES: lanes sit side by side and a lane stacks
		its groups down, which is the whole reason a HUD built on this mechanism
		cannot produce the commissioning screenshot. What a partition cannot stop is
		a region whose chosen form MEASURES bigger than the box it was allotted — a
		row of five controls that cannot shrink is still 60px wider than the column
		it was given, and nothing in Roblox clips it. Then it is not merely
		overflowing; it is drawing on top of the region next door, and the
		composition is perfectly LEGAL while it happens, so no fallback finding
		fires and the inner stack's own overflow sentence never says whose screen
		it landed on.

		TWO EXCLUSIONS, both because the extent is granted rather than claimed:
		  * the SCROLL region — its content is meant to be bigger than its box and
		    a ScrollView clips it (rule 5's "exactly one scroll region");
		  * a `fill` region on the HEIGHT axis — the framework chose that extent
		    from the slack (rule 6), so its content running past it is the inner
		    stack's finding, not a claim this region ever made.
		Width is never author-chosen (a region's width IS its lane's), so the width
		axis is always compared. ]]
	local collisions: { { a: string, b: string, dx: number, dy: number } } = {}
	do
		-- THE CHEAP PRECONDITION FIRST. A collision needs a region painting OUTSIDE
		-- its own box: the regions themselves partition the composition, so with
		-- every one inside its allotment there is nothing to intersect. This loop
		-- is `#regions` comparisons and it is the whole cost on the overwhelming
		-- majority of solves — the pairwise scan and its two tables are never built
		-- at all. (Measured 2026-08-14: with the scan unconditional the off-path
		-- legacy declaration paid +3.5% per resolve; with this gate the delta is
		-- inside the harness's own 0.4% spread.)
		local anyOver = false
		for _, r in decl.regions do
			local res = byId[r.id]
			local rect = if res ~= nil then res.rect else nil
			if rect == nil or not res.mounted or r.mayScroll then
				continue
			end
			local m = p.measured[r.id]
			if m == nil then
				continue
			end
			if m.w - rect.w > EPS or (r.sizing ~= "fill" and m.h - rect.h > EPS) then
				anyOver = true
				break
			end
		end
		if anyOver then
			type Painted = { id: string, x: number, y: number, w: number, h: number, excess: number }
			local painted: { Painted } = {}
			for _, r in decl.regions do
				local res = byId[r.id]
				local rect = if res ~= nil then res.rect else nil
				if rect == nil or not res.mounted then
					continue
				end
				local m = p.measured[r.id]
				local w, h = rect.w, rect.h
				if m ~= nil and not r.mayScroll then
					w = math.max(w, m.w)
					if r.sizing ~= "fill" then
						h = math.max(h, m.h)
					end
				end
				table.insert(painted, {
					id = r.id,
					x = rect.x,
					y = rect.y,
					w = w,
					h = h,
					-- how far OUTSIDE its own box this one paints. It is what names the
					-- offender in the pair: a finding that said "Timer paints over Rail"
					-- when the Timer fits perfectly and the Rail is 60px too wide points
					-- an author at the wrong node, and a diagnostic that misnames the
					-- culprit is worse than none.
					excess = (w - rect.w) + (h - rect.h),
				})
			end
			for i = 1, #painted do
				for j = i + 1, #painted do
					local a, b = painted[i], painted[j]
					local dx, dy = rectLib.intersection(a, b)
					if dx > EPS and dy > EPS then
						local first, second = a.id, b.id
						-- the one painting outside its box is `a`; ties break by id, so the
						-- report is deterministic when both are over
						if b.excess > a.excess or (b.excess == a.excess and second < first) then
							first, second = second, first
						end
						table.insert(collisions, {
							a = first,
							b = second,
							dx = roundPx(dx),
							dy = roundPx(dy),
						})
					end
				end
			end
			table.sort(collisions, function(x, y)
				if x.a ~= y.a then
					return x.a < y.a
				end
				return x.b < y.b
			end)
		end
	end

	return {
		legal = true,
		rule = nil,
		detail = nil,
		hugOverflow = hugOverflow,
		collisions = collisions,
		-- the flow's own extent: every spanning band plus the tallest lane
		used = { w = p.usedW, h = p.spanTotal + laneUsedH },
		-- B-6e: did a lane cap bite? `resolve` centres the band on it, and asking
		-- the pass rather than re-deriving from the declaration keeps one owner
		capped = p.capped,
		lanes = lanes,
		spans = spans,
		groups = groups,
		regions = regionResolutions,
	}
end

-- resolve(decl, offer, ctx) -> Resolution
--
-- The whole decision, deterministically, from a box and a measure callback.
-- Nothing here reads a viewport, a device name or a breakpoint: the offer IS
-- the fact, on both axes, which is the half `adaptive.conditions` structurally
-- cannot answer (it is viewport-relative and width-only).
function composition.resolve(decl: any, offer: Offer, ctx: ResolveCtx): Resolution
	local d = composition.normalize(decl)
	if type(ctx) ~= "table" or type(ctx.measure) ~= "function" then
		fail("resolve needs ctx.measure(regionId, formIndex, availW, availH) -> (w, h)")
	end
	local offerW = if type(offer) == "table" and definite(offer.w) then offer.w else 0
	local offerH = if type(offer) == "table" and definite(offer.h) then offer.h else 0
	local originX, originY = 0, 0
	if type(d.maxMeasure) == "number" then
		local cap = d.maxMeasure :: number
		if offerW > cap then
			originX = math.floor((offerW - cap) / 2)
			offerW = cap
		end
		if offerH > cap then
			originY = math.floor((offerH - cap) / 2)
			offerH = cap
		end
	end

	--[[ ...AND THE TWO SPATIAL INPUTS MOVE WITH THAT CENTRING (§8/§9). `maxMeasure`
		caps the box and centres the result, so every rect `solveArrangement` produces
		is relative to the CENTRED box — and an exclusion or a band expressed against
		the composition's outer box would be off by exactly the offset above. The
		caller cannot make this correction because the offset is decided here; so it
		is made here, once, and everything below reads one space. ]]
	if originX ~= 0 or originY ~= 0 then
		local shifted = table.clone(ctx :: any)
		if type((ctx :: any).exclusions) == "table" then
			local out: { Rect } = {}
			for _, r in (ctx :: any).exclusions :: any do
				table.insert(out, { x = r.x - originX, y = r.y - originY, w = r.w, h = r.h })
			end
			shifted.exclusions = out
		end
		local band = (ctx :: any).band
		if type(band) == "table" then
			shifted.band = {
				x = (band :: any).x - originX,
				w = (band :: any).w,
				h = math.max(0, (band :: any).h - originY),
				reserve = math.max(0, (band :: any).reserve - originY),
			}
		end
		ctx = shifted :: any
	end

	local scroller: string? = nil
	for _, r in d.regions do
		if r.mayScroll then
			scroller = r.id
		end
	end

	local rejected: { { arrangement: string, rule: string, detail: string } } = {}
	local chosen: Attempt? = nil
	local chosenArr: Arrangement = d.arrangements[#d.arrangements]
	for i, arr in d.arrangements do
		--[[ ELIGIBILITY comes before geometry, and it is never applied to the LAST
			candidate: that one is the declared fallback and rule 8 promises a screen
			always resolves. A skipped candidate is REPORTED as rejected — with its
			own rule name, so a resolution dump distinguishes "this did not fit" from
			"this was not offered here", which are different bugs. ]]
		if (arr :: any).eligible == false and i < #d.arrangements then
			table.insert(rejected, {
				arrangement = arr.name,
				rule = "ineligible",
				detail = "the declaration gated this arrangement out for this offer",
			})
			continue
		end
		local attempt = solveArrangement(d, arr, offerW, offerH, ctx, false)
		if attempt.legal then
			chosen = attempt
			chosenArr = arr
			break
		end
		table.insert(rejected, {
			arrangement = arr.name,
			rule = attempt.rule or "illegal",
			detail = attempt.detail or "",
		})
	end
	local fallback = false
	if chosen == nil then
		-- rule 8: the last arrangement is the declared fallback, forced. A screen
		-- degrades; it never blanks, and the resolution says which it is.
		fallback = true
		chosen = solveArrangement(d, chosenArr, offerW, offerH, ctx, true)
	end
	local attempt = chosen :: Attempt

	local byId: { [string]: RegionResolution } = {}
	for _, r in attempt.regions do
		byId[r.id] = r
	end
	if scroller ~= nil and (byId[scroller] == nil or not byId[scroller].mounted) then
		scroller = nil
	end

	--[[ THE UNSHOWN LIST (D7.1). Built from the DECLARATION, in declaration order,
		so the seam a consumer reads is the same order as `regions` and cannot depend
		on hash iteration.

		The route is resolved here, once, rather than left for the consumer:
		  * DROPPED — there is no form standing, so whatever `recover` says about a
		    reduced form is moot and the overflow surface is the only route there can
		    be. This is the half `mayDrop` has always implied and never stated.
		  * ELIDED with recover "none" — nothing is missing; it does not appear.
		  * ELIDED otherwise — the author's declared route, verbatim. ]]
	--[[ THE EXPAND FACTS (wave REVEAL), resolved HERE rather than inside
		`solveArrangement`, because `mounted` is only final once an arrangement has
		been chosen — and because the plate MEASURE below must run exactly once per
		solve rather than once per attempted candidate.

		THE PLATE'S SIZE IS THIS MODULE'S DECISION, and that is deliberate. It is the
		one place that holds both the `measure` seam and the offer, so "how wide is
		the disclosure, and can it be a plate at all" stays a headless sweep instead
		of becoming a screenshot review — the same argument that put the whole ladder
		here. The rule: form 1 at min(its natural width, the offer minus a gutter on
		each side); a form that comes back WIDER than that cap cannot meet its floor
		in a plate, and the caller falls back to the full-width sheet. ]]
	local gutter = if type((ctx :: any).expandGutter) == "number" then (ctx :: any).expandGutter :: number else 0
	--[[ THE PLATE'S OWN CHROME, RESERVED BEFORE THE FORM IS MEASURED (2026-08-21).
		`expandGutter` is what the plate leaves at the SCREEN edges; this is what it
		spends on ITSELF, and the two are not the same subtraction. Absent, it is 0
		and the arithmetic below is exactly what it was — which is what a pure test
		means when it says nothing, and it keeps every `resolve()` call that hands
		this module a bare `measure` working unchanged. ]]
	local plateInset = if type((ctx :: any).expandPlateInset) == "number"
		then (ctx :: any).expandPlateInset :: number
		else 0
	local plateStraddle = if type((ctx :: any).expandPlateStraddle) == "number"
		then (ctx :: any).expandPlateStraddle :: number
		else 0
	--[[ HALF THE CLOSE DISC, carried straight back out on the plate record: the
		declaration's straddle margin is `CLOSE_INSET + this`, and the metric
		vocabulary it is written in cannot halve a name. This module neither
		resolves it nor spends it — it is the courier, exactly as it is for
		`max`. ]]
	local plateDiscHalf = if type((ctx :: any).expandPlateDiscHalf) == "number"
		then (ctx :: any).expandPlateDiscHalf :: number
		else 0
	for _, r in d.regions do
		local res = byId[r.id]
		if res == nil then
			continue
		end
		local active = if res.dropped or not res.mounted then 0 else res.form
		res.activeForm = active
		res.richestForm = 1
		res.expand = (r :: any).expand or "auto"
		res.formInteractive = active > 0 and ((r :: any).formInteractive or {})[active] == true
		res.expandable = active > 1 and res.expand ~= "none"
		if res.expandable then
			--[[ THREE CAPS, AND THE DIFFERENCES ARE THE WHOLE FIX. `allowW` is the box
				the PANEL has to fit in — the offer minus a gutter each side.
				`plateMax` is the widest the plate's own box may be declared, which is
				that minus the straddle the disc sits half-out on, because the panel is
				the box PLUS that margin. `maxW` is the box the FORM has to fit in,
				which is `plateMax` minus the plate's own padding. Measuring the form
				against `allowW` and calling the answer a plate is what produced a
				panel wider than the allowance it had just been chosen against, for
				every form inside the last `inset + straddle` px of the range (DIR5
				item 3, contested there). ]]
			local allowW = math.max(0, offerW - gutter * 2)
			local plateMax = math.max(0, allowW - plateStraddle)
			local maxW = math.max(0, plateMax - plateInset)
			local maxH = math.max(0, offerH - gutter * 2)
			local w, h = ctx.measure(r.id, 1, maxW, maxH)
			--[[ `max` IS THE CAP THIS MEASURE WAS TAKEN AGAINST (fix round 2), reported
				beside the answer because the caller has a correction to make that this
				module cannot: a form declaring `width = fill` measures its CONTENT here
				and has actually asked for the whole offer, and only the layer holding
				the declaration can tell those apart. Without the cap it would have to
				re-derive the gutter arithmetic, which is the second source of truth
				this seam exists to prevent. ]]
			--[[ `max` IS THE PLATE BOX'S OWN CAP, not the form's — and that is a
				change of meaning, made deliberately and in one place. Its only reader
				spends it as a DECLARED OUTER width on the plate (a `fill` form asked
				for the whole offer and only the layer holding the declaration can tell
				that apart), and an outer width has to be an outer number or the fix is
				the same defect one level up. `sheet` still asks the honest question —
				did form 1 fit the box it will actually get? — which is the CONTENT
				cap, `maxW`. ]]
			res.plate = {
				w = math.min(w, maxW),
				h = h,
				sheet = roundPx(w) > roundPx(maxW),
				max = plateMax,
				discHalf = plateDiscHalf,
			}
		end
	end

	local unshown: { Unshown } = {}
	for _, r in d.regions do
		local res = byId[r.id]
		if res == nil then
			continue
		end
		if res.dropped then
			table.insert(unshown, { id = r.id, reason = "dropped", route = "overflow" })
		elseif res.elided and r.recover ~= nil and r.recover ~= "none" then
			table.insert(unshown, { id = r.id, reason = "elided", route = r.recover :: string })
		end
	end

	--[[ A CAPPED MEASURE IS CENTRED, not parked against the left edge (B-6e,
		ruling R14). `maxMeasure` already promises "cap and centre", and the lane
		cap is the same promise made about the measure rather than about the box —
		so it reaches the SAME offset the resolution already carries, computed from
		what the chosen arrangement actually used. It fires only when the band came
		out narrower than its offer, which on every near combo it does not: the cap
		is nil there, the fill lanes spend the whole slack, and `originX` keeps the
		value `maxMeasure` gave it (usually 0). ]]
	if attempt ~= nil and (attempt :: any).capped == true then
		local used = if type(attempt.used) == "table" then attempt.used.w else nil
		if type(used) == "number" and used == used and used < offerW then
			originX += math.floor((offerW - used) / 2)
		end
	end

	return {
		arrangement = chosenArr.name,
		legal = not fallback,
		fallback = fallback,
		offer = { w = offerW, h = offerH },
		origin = { x = originX, y = originY },
		used = attempt.used,
		lanes = attempt.lanes,
		spans = attempt.spans,
		groups = attempt.groups,
		regions = attempt.regions,
		regionById = byId,
		scroller = scroller,
		rejected = rejected,
		--[[ ADDITIVE (ADR-0025 Decision 3): every unordered pair of regions whose
			PAINTED boxes intersect. Empty on every declaration that resolved cleanly
			before this shipped, which is what makes it additive. ]]
		collisions = attempt.collisions or {},
		--[[ ADDITIVE (D7.1, 2026-08-16): what this screen has stopped showing, and
			where the rest is. Empty on every declaration whose regions all fit at
			their richest form, which is what makes it additive. ]]
		unshown = unshown,
		--[[ AUTHORING DIAGNOSTICS. Sorted region ids whose chosen form measured the
			WHOLE offer inside a HUG lane — the signature of a form authored
			`width = FILL` where the lane's whole contract is "as wide as my
			content". Left as a report rather than an error because a genuinely
			narrow offer can produce it honestly; a spec asserts it is empty. ]]
		hugOverflow = (function(): { string }
			local ids = {}
			for id in attempt.hugOverflow or {} do
				table.insert(ids, id)
			end
			table.sort(ids)
			return ids
		end)(),
	}
end

-- ===== the dump ============================================================
-- Follows the library's dump idiom (`facet-<thing>-dump/N`, deterministic
-- ordering, two calls equal). This is the diagnosability half of the contract:
-- WHICH arrangement, WHICH form per region, and WHY every richer candidate
-- lost — by name of the rule it broke.

local function roundRect(r: Rect?): any
	if r == nil then
		return nil
	end
	return {
		x = roundPx(r.x),
		y = roundPx(r.y),
		w = roundPx(r.w),
		h = roundPx(r.h),
	}
end

function composition.dump(resolution: Resolution): any
	local lanes = {}
	for _, lane in resolution.lanes do
		table.insert(lanes, {
			index = lane.index,
			affinities = table.concat(lane.affinities, "+"),
			groups = table.concat(lane.groups, ","),
			rect = roundRect(lane.rect),
			-- ADDITIVE (rule 9, 2026-07-31): every lane that used to be reported is
			-- reported byte-unchanged with `collapsed = false`, and the ones that used
			-- to be OMITTED now appear with `collapsed = true` — so a reader that
			-- never heard of the rule sees the same active lanes it always did
			collapsed = lane.collapsed == true,
			-- ADDITIVE (§8): 0 on every lane of every composition that declares no
			-- exclusions, so a reader that never heard of them reads what it always
			-- did. It is the ONE number that says why a lane did not start at the top
			-- of the band, which a rect alone cannot distinguish from a span row.
			exclusion = roundPx(lane.exclusion or 0),
		})
	end
	local spans = {}
	for _, row in resolution.spans or {} do
		table.insert(spans, { id = row.id, side = row.side, rect = roundRect(row.rect) })
	end
	local regions = {}
	for _, r in resolution.regions do
		table.insert(regions, {
			id = r.id,
			rank = r.rank,
			group = r.group,
			lane = r.lane,
			span = r.span,
			form = r.form,
			mounted = r.mounted,
			dropped = r.dropped,
			-- ADDITIVE (D7.1): `false` on every region that used to be dumped without
			-- it, so a reader that never heard of elision reads what it always did
			elided = r.elided == true,
			floor = roundPx(r.floor),
			rect = roundRect(r.rect),
			--[[ ADDITIVE (wave REVEAL, 2026-08-18): which form is STANDING, which one
				is the richest, whether the standing one carries controls of its own, and
				the declared route back. `activeForm` is 0 on a dropped region and equal
				to `form` on every other, so a reader that only ever knew `form` reads
				exactly what it always did. ]]
			activeForm = r.activeForm or 0,
			richestForm = r.richestForm or 1,
			formInteractive = r.formInteractive == true,
			expand = r.expand or "auto",
			expandable = r.expandable == true,
			plate = if r.plate ~= nil
				then {
					w = roundPx(r.plate.w),
					h = roundPx(r.plate.h),
					sheet = r.plate.sheet,
					max = roundPx(r.plate.max),
					--[[ THE ONE FIELD THIS DUMP DOES NOT ROUND, and the reason is what
						the field is: it is a HALF by definition — the offset a disc
						centred on the plate's corner sits at — so rounding it is
						precisely the operation that would move the disc off the corner
						on a package whose compact control size is odd. Every other
						number here is a box a reader compares against a pixel grid;
						this one is an arithmetic term the declaration adds. ]]
					discHalf = r.plate.discHalf,
				}
				else nil,
		})
	end
	local rejected = {}
	for _, entry in resolution.rejected do
		table.insert(rejected, { arrangement = entry.arrangement, rule = entry.rule, detail = entry.detail })
	end
	local collisions = {}
	for _, c in resolution.collisions or {} do
		table.insert(collisions, { a = c.a, b = c.b, dx = c.dx, dy = c.dy })
	end
	local unshown = {}
	for _, u in resolution.unshown or {} do
		table.insert(unshown, { id = u.id, reason = u.reason, route = u.route })
	end
	return {
		schema = "facet-composition-dump/1",
		arrangement = resolution.arrangement,
		legal = resolution.legal,
		fallback = resolution.fallback,
		offer = { w = roundPx(resolution.offer.w), h = roundPx(resolution.offer.h) },
		used = { w = roundPx(resolution.used.w), h = roundPx(resolution.used.h) },
		scroller = resolution.scroller,
		lanes = lanes,
		-- ADDITIVE (2026-07-31): a declaration with no spanning group dumps `spans
		-- = {}` and every other key byte-unchanged, so the schema stays /1 and a
		-- reader that never heard of a span reads exactly what it always did
		spans = spans,
		regions = regions,
		rejected = rejected,
		-- ADDITIVE (2026-08-02): the authoring diagnostic. Empty on a well-formed
		-- declaration, so a reader that never heard of it reads what it always did.
		hugOverflow = resolution.hugOverflow or {},
		-- ADDITIVE (ADR-0025, 2026-08-14): who is painting on top of whom. Already
		-- sorted by (a, b) on the resolution, so two calls are equal.
		collisions = collisions,
		--[[ ADDITIVE (D7.1, 2026-08-16): what this screen has stopped showing and
			where the rest is, in declaration order. This is the row a reviewer reads to
			answer "did adaptation delete anything" without re-deriving it from `form`
			and `dropped` — and the row the D7.6 device sweep asserts a route for. ]]
		unshown = unshown,
	}
end

return composition
