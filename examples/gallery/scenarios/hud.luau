--!strict
-- Scenario 'hud' (ADR-0025): THE SCREEN-ANCHORED HUD, and the thing it refuses
-- to do.
--
-- The commissioning case is two screenshots of a shipped mobile FPS. Fullscreen
-- the HUD is right. Open a browser URL bar — SAME WIDTH, ~200px LESS HEIGHT — and
-- it collapses into itself: the task panel climbs into the round buttons above
-- it, the weapon rail runs into the fps/ping readout, and the action buttons land
-- on each other.
--
-- This fixture is that HUD, built on `composition.HUD` — corner clusters, a task
-- panel down the middle-left, a weapon rail top-right — plus the ONE control that
-- makes the point: **URL BAR**, which takes 200px of height off the HUD's box
-- exactly the way a browser chrome bar does. Turn it on and nothing overlaps;
-- what happens instead is that the least important zone in the column that ran
-- out gives up its richest form, and then drops.
--
-- WHY THE TOGGLE AND NOT "JUST RESIZE THE WINDOW". Resizing works too — the HUD
-- measures the box it received, so the emulator, a window drag and this toggle
-- are the same event to it. The toggle exists because the DEFECT is a comparison
-- between two states of one screen, and a still screenshot flattens a comparison
-- into one picture (`flow_wrap`'s wrapping switch is here for the same reason).
--
-- ===== IT ALSO HAS TO LOOK LIKE A GAME HUD (director round 2026-08-14) =======
-- *"for the showcase based on rivals, let's make it pretty conceptually similar
-- to rivals."* The first cut proved the BEHAVIOUR and looked like a test
-- harness: text pills in nine boxes. The reference screenshots are a specific
-- shape and this now builds that shape out of the library's real controls —
--
--   top-left      a strip of round dark-glass ICON buttons (`shape = "circle"`,
--                 the shipped semantic icon set: no art is invented here)
--   top-centre    two team-score pills flanking a round timer, and the timer is
--                 a CIRCULAR ProgressView — a ring reads as time remaining, which
--                 is exactly the shape the screenshots use
--   top-right     a weapon rail of chips, each with its ammo count, over a small
--                 fps/ping readout
--   middle-left   "Beginner tasks": rows of mark + label + `newProgressView` bar
--                 + reward chip
--   bottom-left   the health bar, with its figure in the `numeral` type role
--   bottom-right  a cluster of LARGE round action buttons, under the weapon name
--
-- ONE PLATE, ONE RECIPE (`glass` below). Every surface here is the same
-- construction — a tinted `UI.Box` under the content, rounded once — because
-- Roblox cannot blur UI behind UI. So the "dark glass" is a STATED translucent
-- plate (the `p3_sipworks` idiom) and is never called a blur anywhere. It is
-- also THEME-COLOURED rather than literally dark: the plate tints toward the
-- theme's own `surface`, so this HUD is smoked glass under Studio Neutral and
-- waxed paper under Parchment, which is what "themeable" has to mean.
--
-- AND THE PLATFORM'S OWN ROW (ADR-0027, director 2026-08-14: *"we should be able
-- to have things at top that are aligned with the controls but don't overlap"*).
-- Roblox's chrome does NOT own the whole top band — measured live at 735x413 it
-- occupies x 0..164 of a 58px band and the rest of that band is the developer's
-- (`GuiService.TopbarInset`). `deviceSafeContent` spends the whole band because a
-- rect inset is a bounding box, so nothing could ever sit level with the platform's
-- buttons. This surface therefore presents `edgeToEdge` and insets itself from the
-- ONE fact that knows the difference — `platformChrome` — which is still a single
-- authority, just one that can state an L:
--
--   riding the band   margin.top = platformChrome.bandInsets.top (0 here), and the
--                     `topbar` zone is the row LEVEL WITH the platform's controls
--   not riding        margin.top = platformChrome.insets.top — byte-identical to
--                     what `deviceSafeContent` applied, which is what a platform
--                     reporting NO strip (desktop, or an engine without
--                     `GetInsetArea`) gets automatically
--
-- THE ZONES, and the RANK LADDER the fixture exists to show (rank 1 is the last
-- thing to give way; 9 is the first). The ladder is on screen, under the HUD, so
-- a viewer watching a zone step down can see WHY that zone was the one chosen:
--   1 topLeft      the round-button strip — and the THIRD disc in it is the
--                  overflow sink (D7.3), so the one affordance that recovers
--                  everything else lives in the one zone that never gives way
--   2 top          the round timer and the two team scores
--   3 bottomRight  the action buttons
--   4 topRight     the weapon rail
--   5 bottomLeft   the health bar
--   6 bottomRight  the weapon name (droppable)
--   7 left         "Beginner tasks" — three forms: full / one task / chip
--   8 bottomLeft   the kill feed (droppable)
--   9 topRight     the fps/ping readout (droppable)
--   + topbar       the objective chip, in the free strip beside Roblox's own
--                  buttons — RESERVED while riding, never dropped
--
-- ===== AND WHAT HAPPENS TO WHAT A ZONE STOPS SHOWING (D7) ===================
-- The ladder above was never broken: it steps a zone down and then drops it,
-- exactly as declared. What it had no vocabulary for was WHERE the content went,
-- so "step down" and "delete" were the same operation from the player's side.
-- Measured on this very fixture before the repair
-- (artifacts/navigation-and-menus/d7-hud-baseline.md): 39 elided-or-dropped
-- occurrences across nine viewports and two states, every one a dead end.
--
-- Every multi-form zone here now states its route, and the framework refuses a
-- declaration that does not (`recover`, src/layout/composition.luau):
--   Rounds   "none"      — one form, wrapped: every disc is on screen at every
--                          width, so nothing is ever lost. Stated, not assumed
--   Tasks    "self"      — the chip it steps down to is a BUTTON that opens the
--                          full task list, so what is left can be tapped
--   Clock,   "overflow"  — the scores, the ammo counts and the two spare action
--   Rail,                  discs go to the ··· sink, which reads the framework's
--   Actions,               own `resolution.unshown` list rather than re-deriving
--   Health                 elision by hand
-- ...and every DROPPED zone (Feed, Readout, Weapon, and Tasks/Health/Rail when
-- the ladder runs out of steps) is in that same list by construction: `mayDrop`
-- now means "moves to the sink", never "is deleted".

-- EVERY PLAYER-VISIBLE STRING, in one table and exported, so the localization
-- case can expand all of them ~1.4x. All of it must fit and wrap, never clip.
local COPY = {
	tasksTitle = "Beginner tasks",
	task1 = "Win a round",
	task2 = "Land 25 hits",
	task3 = "Open a crate",
	reward1 = "+50",
	reward2 = "+120",
	reward3 = "+300",
	tasksChip = "Tasks 1/3",
	timer = "2:14",
	scoreHome = "12",
	scoreAway = "9",
	weapon1 = "Rifle",
	weapon2 = "Pistol",
	weapon3 = "Knife",
	ammo1 = "24/90",
	ammo2 = "7/21",
	ammo3 = "--",
	weaponName = "Ranger rifle",
	readout = "60 FPS · 42 ms",
	health = "84",
	healthLabel = "Health",
	-- the round buttons' semantic names. A circle Button does NOT draw a
	-- multi-character label — the icon is the face and the label is the
	-- accessible name — so these are the words a screen reader says.
	action1 = "Shop",
	action2 = "Squad",
	action3 = "Menu",
	round1 = "Menu",
	round2 = "Report",
	-- THE OVERFLOW SINK'S OWN NAME (D7.3). It is the third disc in the round
	-- strip, and it is what "dropping stops meaning deleting" is made of.
	round3 = "Show what's hidden",
	overflowTitle = "Hidden right now",
	-- the half the ladder line has no room for: the ladder decides WHICH zone gives
	-- way, and this says what happens to what it gave up
	overflowNote = "Nothing is deleted. A zone that gives way is listed here.",
	overflowEmpty = "Nothing is hidden — every zone is showing everything it has.",
	overflowClose = "Close",
	feed = "Ravi eliminated Mo",
	urlBarOn = "URL bar",
	-- the pseudo browser chrome the switch now DRAWS (director 2026-08-15, item 5)
	urlBarField = "example.com/play",
	rideOn = "Topbar strip",
	objective = "Round 3 · Capture",
	objectiveShort = "R3",
	--[[ THE MECHANISM, IN TWO LINES, ON THE SCREEN THAT DEMONSTRATES IT.
		The ladder moved (D7.4). It used to read "feed, tasks, fps, ..." — the fps
		readout surviving longer than the kill feed and the task panel, which is a
		developer's telemetry outliving two pieces of player information. Measured on
		the live screen (artifacts/navigation-and-menus/d7-hud-baseline.md): with the
		URL bar open, `60 FPS · 42 ms` was still on screen while all three tasks,
		their rewards and the feed were gone.

		AND THE SCORES ARE A RE-RANK THAT COULD NOT WORK, which is why the second
		line exists. `12` and `9` are lost when the Clock steps down, and the Clock is
		in the CENTRE lane while the fps readout is in the RIGHT one — rule 3 only
		ever spends the currency of the lane that does not fit, so no rank on earth
		makes the right lane pay for the centre lane's deficit. The scoreboard's
		recovery is the DISCLOSURE route, not the ladder: `recover = "overflow"`. ]]
	--[[ ONE LINE, AND IT MAY NOT GROW. The disclosure half arrived as a SECOND
		caption line and the always-on sweep refused it the same day: at 320x640 with
		`preferredTextOffset = +14` the Screen's own column went over by 5px under
		classic-desktop and by up to 268px under the ornate packages — the caption was
		already at its limit and a second sentence had nowhere to go. So both facts
		ride ONE line, and this one is SHORTER than the ladder line it replaces (98
		characters against 100). The fuller sentence lives on the panel the ··· opens,
		which is the one place on this screen that has room for it. ]]
	ladder = "Gives way first: fps, feed, tasks, weapon, health, rail, actions, clock, buttons. ··· has the rest.",
	--[[ THE PAINT PROBE'S OWN WORDS (NM-H4a). Sentences only — the NODE NAMES it
		lists are identifiers of source nodes, the way a build sha is, and
		translating them would break the one thing the reader has to type back into
		a bug report. Everything here is short because it is read on a phone held at
		arm's length, in whatever orientation the failure appeared in. ]]
	probeFreeze = "Freeze",
	probeArm = "Live again",
	probeTitle = "Paint probe",
	probeSolve = "solve",
	probeOf = "of",
	probePainting = "painting",
	probeNotPainted = "NOT PAINTED",
	probeFirstPainted = "first painted:",
	probeHiddenUnder = "hidden under:",
	probeHeldTag = "HELD",
	--[[ AND THE THREE THAT REPLACED A FALSE VERDICT (2026-08-16). The plate used
		to print a paint count it had not measured and quietly shrink its own
		denominator; the words below are what it says instead. `probeNoEngine`
		is shouted because it appears in place of the count rather than beside
		it — a reader who skims and sees a number has been told a fact, and this
		is the line that has to stop them. ]]
	probeUnmeasured = "UNMEASURED",
	probeNoEngine = "ENGINE SIDE UNAVAILABLE — MODEL ONLY",
	probeRows = "rows wanted",
	probeSkipped = "skipped:",
	probeSizeDiffers = "size differs:",
	-- the solver's own findings, which outrank every paint verdict below them: a
	-- layout the framework is already complaining about is not a paint defect
	probeSolver = "SOLVER SAYS",
	probeWaiting = "waiting for the first solve",
	--[[ WHY A ROW IS SKIPPED, WHEN THE REASON IS A PLATFORM FACT (director, device,
		2026-08-17). The plate reported `13 of 14 rows wanted / skipped: Objective`
		and nothing else, and the reason took a 36 624-state sweep to find: that row
		lives behind `UI.When{ condition = riding }`, and `riding` is false exactly
		when `platformChrome.band` is nil — which the engine can do at any moment,
		because it owns the inset that band is derived from.

		A skipped row with no reason is a number a reader cannot act on. These two
		lines put the INPUT on the plate beside the verdict, so the next photograph
		of a wrong screen carries what decided it. ]]
	-- SHORT ENOUGH TO READ ON A PHONE. The plate is a 168px column, so a
	-- sentence wraps to four lines and the director photographed a cut-off one.
	probeNotRiding = "NOT RIDING ·",
	probeNoBand = "no platform band",
	probeRideOff = "strip switch off",
	probeBandInput = "coreTop=",
}

--[[ ── THE URL BAR IS TWO FACTS, AND IT USED TO BE ONE NUMBER (D7.5) ──────────
	`URL_BAR_PX = 200` was commented as *"a fact about the SCREENSHOT"* — which is
	to say it was never measured — and it did two jobs at once: the height the
	browser chrome STEALS from the page, and the height this fixture DRAWS its
	pseudo bar at. One number for two facts means an over-stated steal also paints
	an absurd box: measured at 749x380 the bar came out 733x158, 42% of the
	viewport, a near-empty slab with one line of grey text adrift in it.

	RE-MEASURED AGAINST A REAL BROWSER, 2026-08-16 — Chrome 151.0.0.0 on macOS
	(this machine), a local page reporting its own `outerHeight - innerHeight`:

	  | window                                    | outer | inner | chrome |
	  | normal window (tab strip + toolbar)       |  1274 |  1131 | 143 px |
	  | popup window (location bar, NO tab strip) |   486 |   419 |  67 px |

	THE FIXTURE MODELS THE 67, and that choice is the point: a tab strip does not
	APPEAR — it is always there. What appears and disappears, which is the whole
	event this toggle exists to model, is the location-bar row. 200 was three times
	it.

	AND THE SECOND JOB IS NOW A THEME METRIC, NOT A CONSTANT. The bar is still
	drawn at exactly the height it takes (director 2026-08-15, item 5: the picture
	and the geometry are one number and cannot drift), but the FIELD inside it is a
	control, so its box comes from the control-size ladder — which is what stops an
	over-stated band from ever painting an empty slab again, whatever the band's
	height turns out to be. ]]
local URL_BAR_STEAL_PX = 67

-- ...and the same kind of constant for the OTHER commissioning fact: the width of
-- Roblox's own control cluster, measured live at 735x413 on 2026-08-14. It is used
-- for ONE thing — modelling a platform in the headless suite and the always-on
-- sweep, which have no engine to ask — and never by the layout, which reads
-- `platformChrome`. A fixture that could not model the platform would leave the
-- mechanism unexercised by every sweep, which is how a feature becomes decoration.
local MODELLED_CLUSTER_PX = 164
local MODELLED_STRIP_PX = 58

--[[ ...AND THE FLOOR THE SIMULATED BAR MAY NEVER EAT THROUGH.
	A simulated chrome bar cannot take more room than the screen has. Without
	this the demo silently stopped being a demo on a short window: the driver
	profile the director's own screenshot describes is 735x213 — a window that
	ALREADY has a URL bar open — so opening this fixture's bar too left the
	composition 0px, no arrangement was legal, and the declared fallback painted
	the whole HUD at the origin (measured 2026-08-14: "no declared arrangement is
	legal in 735x0"). A 0px HUD is not a degradation, it is an absence: nothing
	steps down, nothing drops, and the one thing the fixture exists to show is
	the one thing that cannot happen. It also put a weapon chip inside Roblox's
	own button cluster, which is how it was found.

	160 IS DERIVED, NOT PICKED: the platform's reserved row is 58px, one
	target-sized zone per lane is 44, this fixture's own driver row is another 44,
	and the Screen's gaps are the rest. Below that total nothing can step down
	because there was never a step. Above it — every viewport the director
	actually opens — the bar still takes its full 200px and nothing about the demo
	changes. ]]
local HUD_FLOOR_PX = 160

-- HOW SEE-THROUGH THE GLASS IS. One number, used by every plate, so the whole HUD
-- reads as one material rather than as nine panels that each guessed. 0.28 is far
-- enough from 0 to read as glass over a moving world and far enough from 1 that
-- the theme's own contrast gate still means something for the text on top of it.
local GLASS = 0.28

-- ...and the height below which this fixture drops its own caption (see the
-- `UI.When` at the bottom of the Screen). A HUD is what this surface is FOR, so
-- on a screen shorter than this the explanation yields to the thing it explains.
local CAPTION_FLOOR = 360

--[[ ══ THE PAINT PROBE'S WATCH LIST (NM-H4a) ══════════════════════════
	Fourteen rows, IN DOCUMENT ORDER, spanning the boundary the reported failure
	stops at. The director's photograph (`h.jpeg`, 2026-08-16) shows a contiguous
	document-order PREFIX of this HUD not painting after a real phone is rotated
	with the URL bar toggled — objective chip, round strip, tasks, health, feed,
	`ScoreHome`, the timer's plate — and then everything from the timer's RING
	onward painting normally. The ring is the fixture's first `Path` node, and
	that boundary is what `TimerPlate` / `TimerRing` / `TimerText` are here to
	resolve: three rows inside one pod, on either side of it.

	EACH ROW NAMES SEVERAL PATHS BECAUSE THE LADDER IS ALLOWED TO CHOOSE. `Tasks`
	is three forms and `Rail` is two, so only ONE of them is on screen at a time
	and the other paths have no solved box at all. THE MODEL PICKS, AND THE
	ENGINE IS THEN HELD TO EVERY PATH THE MODEL PICKED — a row is painting only
	when every path the framework says should be painting is painting.

	THAT RULE USED TO BE AN `ANY`, and the difference is `Rounds` (2026-08-16).
	A row of alternate FORMS reads the same either way, because the model wants
	exactly one of them; a row of SIBLINGS does not. The round strip is three
	discs that are all on screen at once, and R3 is the ··· sink — the recovery
	route for everything the ladder has taken away. Under an `any`, R3 could go
	dark while R1 and R2 painted and the row still reported healthy: partial loss
	inside the one zone no ladder is permitted to remove, reported as fine.

	EVERY PATH IS A NON-ELIDABLE CLASS (Box / Text / Button / Path), never a bare
	stack, and that is a requirement rather than a preference: an ELIDED container
	has no Instance at all, so "no Instance" would otherwise mean both "elided and
	fine" and "gone", which is the one ambiguity this instrument may not have. ]]
local PROBE_HUD = "/HudScreen/Hud"
local PROBE_CLOCK = PROBE_HUD .. "/Clock/ClockStack"
local PROBE_ROWS: { { name: string, paths: { string } } } = {
	{
		name = "Objective",
		paths = {
			PROBE_HUD .. "/Strip/StripRow/StripFree/StripChip/then/StripFit/Objective/Plate",
			PROBE_HUD .. "/Strip/StripRow/StripFree/StripChip/then/StripFit/ObjectiveShort/Plate",
		},
	},
	-- ALL THREE DISCS, not just the first: they are siblings rather than forms,
	-- so each one is a separate claim the engine has to honour, and the third is
	-- the overflow sink every dropped zone recovers through
	{
		name = "Rounds",
		paths = {
			PROBE_HUD .. "/Rounds/RoundStrip/R1",
			PROBE_HUD .. "/Rounds/RoundStrip/R2",
			PROBE_HUD .. "/Rounds/RoundStrip/R3",
		},
	},
	{
		name = "Tasks",
		paths = {
			PROBE_HUD .. "/Tasks/TasksFull/Plate",
			PROBE_HUD .. "/Tasks/TasksOne/Plate",
			PROBE_HUD .. "/Tasks/TasksChip",
		},
	},
	{
		name = "Health",
		paths = { PROBE_HUD .. "/Health/HealthPod/Plate", PROBE_HUD .. "/Health/HealthOnly/Plate" },
	},
	{ name = "Feed", paths = { PROBE_HUD .. "/Feed/FeedLine" } },
	{ name = "ScoreHome", paths = { PROBE_CLOCK .. "/ScoreHome/Plate" } },
	{
		name = "TimerPlate",
		paths = { PROBE_CLOCK .. "/TimerPod/Plate", PROBE_HUD .. "/Clock/TimerOnlyPod/Plate" },
	},
	-- the fixture's FIRST `Path` node, and the exact node the reported prefix
	-- stops before. If this one paints while the rows above it do not, the
	-- photograph and the instrument are describing the same event.
	{ name = "TimerRing", paths = { PROBE_CLOCK .. "/TimerPod/TimerRow/TimerRingBox/TimerRing/Ring/Track" } },
	{
		name = "TimerText",
		paths = {
			PROBE_CLOCK .. "/TimerPod/TimerRow/TimerText",
			PROBE_HUD .. "/Clock/TimerOnlyPod/TimerOnlyRow/TimerOnlyText",
		},
	},
	{ name = "ScoreAway", paths = { PROBE_CLOCK .. "/ScoreAway/Plate" } },
	{ name = "Rail", paths = { PROBE_HUD .. "/Rail/RailTall/W1/Plate", PROBE_HUD .. "/Rail/W1c/Plate" } },
	{ name = "Readout", paths = { PROBE_HUD .. "/Readout/ReadoutText" } },
	{ name = "Actions", paths = { PROBE_HUD .. "/Actions/ActionsCol/A1", PROBE_HUD .. "/Actions/A1r" } },
	{ name = "Weapon", paths = { PROBE_HUD .. "/Weapon/WeaponText" } },
}

-- every strict ancestor of `path`, NEAREST FIRST. Both sides of the probe walk
-- this: the framework's `hiddenRoots()` answers the hidden ROOT set rather than
-- an inherited per-node verdict, and the engine has no `AbsoluteVisible`.
local function probeAncestors(path: string): { string }
	local out: { string } = {}
	local p = path
	while true do
		local cut = string.find(p, "/[^/]*$")
		if cut == nil then
			break
		end
		p = string.sub(p, 1, (cut :: number) - 1)
		if p == "" then
			break
		end
		table.insert(out, p)
	end
	return out
end

-- ...and the deduplicated path set the engine seam is asked for, built ONCE at
-- module load rather than per sample. Ancestors are in it deliberately: a
-- visibility walk that stopped part-way leaves an ancestor hidden with its own
-- descendants still flagged visible, and reading only the leaves would report
-- that screen as healthy — the exact false negative this instrument exists to
-- avoid.
local PROBE_QUERY: { string } = (function(): { string }
	local seen: { [string]: boolean } = {}
	local list: { string } = {}
	local function add(path: string)
		if seen[path] then
			return
		end
		seen[path] = true
		table.insert(list, path)
	end
	for _, row in PROBE_ROWS do
		for _, path in row.paths do
			add(path)
			for _, up in probeAncestors(path) do
				add(up)
			end
		end
	end
	return list
end)()

return {
	title = "Screen-anchored HUD (ADR-0025)",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local LuauUI = ctx.LuauUI
		local UI = LuauUI.UI
		local core = ctx.core
		local scope = core:scope("hud")

		local urlBar = scope:own(core:signal(false))
		-- the author's own decision, and the demo's second comparison: a HUD that
		-- RIDES the platform's free strip against the same HUD that does not
		local ride = scope:own(core:signal(true))

		local env = ctx.env
		local chromeFact = env:get("platformChrome")
		local viewportFact = env:get("viewportRect")

		--[[ MODELLING A PLATFORM THAT IS NOT THERE (headless only). The engine
			publishes `topbarInset` through `roblox_env`; a Lune suite and the
			always-on overflow sweep have no engine, so `platformChrome.band` is nil
			and every rung below would be the no-strip one — the mechanism would ship
			unexercised by the sweep that is supposed to be watching it. So when, and
			only when, the platform reports NO strip, this fixture states one the way
			the live engine states it. On any real client the fact is already there
			and this branch never runs.

			`flags.noTopbarStrip` opts out, which is how a test drives the OTHER
			platform — the one with no strip at all — through this same fixture. ]]
		local modelStrip = (ctx.flags == nil or ctx.flags.noTopbarStrip ~= true)
			and (chromeFact:get() :: any).band == nil
		if modelStrip then
			local vp = viewportFact:get()
			local coreTop = (env:get("coreSafeInsets"):get() or {}).top or 0
			if coreTop > 0 and vp.w > MODELLED_CLUSTER_PX * 2 then
				env:set("topbarInset", {
					x = MODELLED_CLUSTER_PX,
					y = 0,
					w = vp.w - MODELLED_CLUSTER_PX,
					h = math.min(MODELLED_STRIP_PX, coreTop),
				})
			end
		end

		-- ONE fact, read four ways. Nothing below knows 164, or 58, or a device.
		local riding = scope:own(core:memo(function(use)
			return use(ride) == true and (use(chromeFact) :: any).band ~= nil
		end))
		-- the surface is edgeToEdge, so the HUD spends the insets itself — from the
		-- fact, and the fact alone. Riding the band spends the top down to where the
		-- band starts; not riding spends the whole band, which is exactly what
		-- `deviceSafeContent` used to apply here.
		local margin = scope:own(core:memo(function(use)
			local chrome = use(chromeFact) :: any
			local insets = if use(riding) then chrome.bandInsets else chrome.insets
			return {
				top = insets.top,
				-- THE SIMULATED BAR IS A THING ON THE SCREEN NOW, not a margin
				-- (director 2026-08-15, item 5). It is the LAST child of the Screen
				-- below, so the height it takes is taken by a box a viewer can see —
				-- and the HUD, which is `fill`, is left with exactly what a real
				-- browser bar would leave it. A margin took the same pixels and drew
				-- nothing in them, which is why "turn the URL bar on" read as
				-- "controls disappear for no reason".
				right = 0,
				bottom = 0,
				left = 0,
			}
		end))
		-- everything the HUD is NOT allowed to reach, on the other three edges. The
		-- top is the HUD's own margin above, because the top is the edge with a hole
		-- in it.
		--[[ ...AND CONTENT NEVER TOUCHES THE PHYSICAL EDGE (director 2026-08-15,
			round 2: *"the circular controls are still getting cut off"*).

			This used to be the safe-area inset alone, which on this platform is ZERO
			laterally — the engine pre-excludes the notch from the camera rather than
			reporting it as an in-canvas inset (docs/lessons/device-emulator-truths).
			So every right-anchored zone was laid out flush against the camera's own
			edge. Measured live through a parallel real-engine mount, iPhone 16 Pro
			portrait: every right-anchored node's right edge is 401.0 against a 401px
			canvas — over by 0.0px, nothing overflowing, zero collisions — and a
			rounded control whose rim ends exactly on the boundary reads as one that
			was cut there. With `ClipToDeviceSafeArea` on, a theme that paints a rim
			or a shadow OUTSIDE the box really does lose it.

			IT IS ALSO WHY THE TWO ORIENTATIONS LOOKED LIKE OPPOSITE DEFECTS. The
			platform's exclusion is wildly asymmetric on this device: portrait leaves
			1px of glass beyond the 401px camera, landscape leaves 125px beyond the
			749px one. One rule — "anchor to the camera's edge" — therefore reads as
			"over the edge" in portrait and "pulled inward" in landscape. There was
			never a wrong width; there was no gutter.

			So the padding is the per-edge MAX of what the platform says must be
			cleared and what the theme calls a gap. The step is the theme's own
			`space.s` — the same one a compact control uses to clear its own frame —
			so a themed package that breathes more moves this with it and this
			fixture learns no number. The TOP stays the HUD's own margin's business:
			the topbar row has to sit level with the platform's buttons, and a gutter
			there would be the one thing ADR-0027 exists to prevent. ]]
		local screenPadding = scope:own(core:memo(function(use)
			local insets = (use(chromeFact) :: any).insets
			local metrics = use(env:get("themeMetrics"))
			local space = (if type(metrics) == "table" then (metrics :: any).space else nil) or {}
			local gutter = if type(space.s) == "number" then space.s else 8
			return {
				top = 0,
				right = math.max(insets.right, gutter),
				bottom = math.max(insets.bottom, gutter),
				left = math.max(insets.left, gutter),
			}
		end))
		-- the topbar row: as tall as the band the platform left free, and inset to
		-- START where that band starts — so the chip is level with Roblox's own
		-- buttons and cannot be over them.
		--[[ THE ROW IS THE PLATFORM'S OWN BAND, NOT EVERYTHING RESERVED ABOVE THE HUD
			(director 2026-08-15, item 4, and the measured cause of the rotation
			report). This used to be `insets.top - bandInsets.top` — the whole top
			reservation — and in the showcase that reservation is the platform's 58px
			row PLUS the demo picker's own 62px chip strip. One full-width 120px row
			is 32% of a 380px landscape phone, so the top-centre cluster landed a third
			of the way down the screen and the "upper right" cluster with it. Measured
			live 2026-08-15, iPhone 16 Pro landscape (749x380): clock at y=120, i.e.
			32% down, identical whether the tree was mounted there or rotated into it.

			The row is now the band the PLATFORM actually owns, and the app's own
			chrome is reserved PER COLUMN below (`columnReserve`) — so a column the
			chrome does not cover starts level with it instead of below it, which is
			exactly what the director asked for. ]]
		local stripHeight = scope:own(core:memo(function(use)
			local chrome = use(chromeFact) :: any
			if not use(riding) then
				return { type = "fixed", px = 0 }
			end
			local band = chrome.band
			local bottom = if band ~= nil then band.y + band.h else chrome.insets.top
			return { type = "fixed", px = math.max(0, bottom - chrome.bandInsets.top) }
		end))

		--[[ ...AND THE APP'S OWN CHROME, RESERVED IN THE COLUMNS IT ACTUALLY COVERS.

			`appChromeRects` is the general mechanism (src/env/environment.luau): a
			surface that draws a persistent chrome row DECLARES the rect it occupies,
			the same way the platform's own cluster is declared, and `platformChrome`
			merges both into `rects`. The showcase host publishes its demo/settings
			chip row through it (examples/gallery/client/init.client.luau).

			A composition's lane band is a RECTANGLE — every lane starts at the same
			y — so the framework itself cannot yet make the band's top edge an L. The
			author can, with the vocabulary that already exists: a reserve REGION at
			the head of the column, which is SPACE rather than an offset (the same
			idiom `stripLead` uses for the platform's cluster one row up). Making the
			solver take a per-lane top inset is the general fix and is FLAGGED, not
			smuggled in here (ENGINEERING.md, "flag refactors; don't smuggle them").

			NOTHING DECLARED = TODAY'S ANSWER, BYTE FOR BYTE. A host that reserves its
			chrome the old way (a bigger `coreSafeInsets.top` and no declaration) has
			told us only a bounding box, so every column reserves the whole of it —
			which is what this fixture has always spent. ]]
		--[[ A COLUMN RESERVES WHEN THE CHROME COVERS MOST OF IT, not when it clips
			the far end.

			Measured live 2026-08-15, iPhone 16 Pro landscape (749x380): the
			showcase's two chips run x 8..267 and the HUD's columns are 250px each, so
			the row covers 97% of the left column and 7% of the centre one. A rule
			that reserved on ANY overlap would push the centre column down for 17px
			the centred clock (x 294..453) never comes near — which is precisely the
			thing the director asked to stop happening. A rule that probed only the
			column's anchored EDGE was tried first and is worse: the chips start at
			x=8 because the chrome pads itself, so the left column's x=0 anchor is not
			covered and the round buttons landed UNDER the chips (measured, same
			session).

			Majority coverage is a judgement and it is stated as one. It is safe to
			make because it is not the last line of defence: a zone whose content
			reaches into the chrome anyway is a region painting outside its own box,
			and `resolution.collisions` is the alarm that already names that
			(ADR-0025 Decision 3). ]]
		local appChromeFact = env:get("appChromeRects")
		local function columnReserve(index: number, _anchor: string): any
			return scope:own(core:memo(function(use)
				local chrome = use(chromeFact) :: any
				local vp = use(viewportFact) :: any
				local insets = chrome.insets
				-- what the HUD has already spent at the top: the band row when it is
				-- riding, the whole inset when it is not
				local spent = if use(riding)
					then (if chrome.band ~= nil then chrome.band.y + chrome.band.h else insets.top)
					else insets.top
				local declared = use(appChromeFact)
				if type(declared) ~= "table" or #(declared :: any) == 0 then
					return { type = "fixed", px = math.max(0, insets.top - spent) }
				end
				-- the columns are thirds of the box the composition ACTUALLY gets, which
				-- is the viewport less the Screen's own padding — not less the raw
				-- insets. Since the gutter joined that padding the two differ by 8px a
				-- side, and a reservation computed against the wrong box is the
				-- "measured one box, painted another" family this repo keeps meeting.
				local pad = use(screenPadding) :: any
				local W = math.max(0, vp.w - pad.left - pad.right)
				local x0 = pad.left + (index - 1) * W / 3
				local x1 = pad.left + index * W / 3
				local span = math.max(1, x1 - x0)
				local bottom = spent
				for _, r in declared :: any do
					if type(r) ~= "table" then
						continue
					end
					local covered = math.max(0, math.min(r.x + r.w, x1) - math.max(r.x, x0))
					if covered / span > 0.5 then
						bottom = math.max(bottom, r.y + r.h)
					end
				end
				return { type = "fixed", px = math.max(0, bottom - spent) }
			end))
		end
		-- the same three alignments `composition.HUD_GROUPS` gives the three columns
		local reserveLeft = columnReserve(1, "start")
		local reserveCentre = columnReserve(2, "center")
		local reserveRight = columnReserve(3, "end")
		--[[ ...AND THE FLOOR THE SIMULATED BAR MAY NEVER EAT THROUGH — WHICH THE
			APP'S OWN CHROME IS A TERM OF (measured 2026-08-15).
		
			`HUD_FLOOR_PX` is a SUM, and its own note names the terms: the platform's
			reserved row (58), one target-sized zone per lane (44), this fixture's own
			driver row (44), and the Screen's gaps. `appChromeRects` added a term to
			that sum after it was written — a column the app's chrome covers has that
			much less room before its first zone can start — and the constant did not
			know. Measured at 749x380 with the showcase's 62px chip row declared: the
			bar took its full 200px, the left lane was left 78px and needed 98, and
			the demo was showing an IMPOSSIBLE screen instead of the ladder. An
			instrument that eats the thing it measures is what this floor exists to
			stop, and it was doing it again with one term missing.
		
			It takes the WORST column's reservation: the lane band is a rectangle, so
			the column the chrome covers is the one that runs out first. A host that
			reserves nothing above the platform's own band reserves 0 in every
			column, and this is then `HUD_FLOOR_PX` exactly — byte for byte what
			such a host has always had (the control is in
			tests/hud_chrome_rotation.spec.luau). ]]
		local function urlBarPx(use: any): number
			if not use(urlBar) then
				return 0
			end
			local reserved = 0
			for _, r in { reserveLeft, reserveCentre, reserveRight } do
				reserved = math.max(reserved, (use(r) :: any).px or 0)
			end
			return math.min(URL_BAR_STEAL_PX, math.max(0, (use(viewportFact) :: any).h - HUD_FLOOR_PX - reserved))
		end
		-- ...and the platform's own cluster is held open as SPACE inside that row —
		-- a leading spacer as wide as the distance from the HUD's own left edge to
		-- where the free band begins, and a trailing one for the platforms that put
		-- something on the right too. Space, not an offset, so the row's content is
		-- laid out INSIDE what is left rather than positioned over what is not.
		local function edgeSpacer(pick: (any, any) -> number): any
			return scope:own(core:memo(function(use)
				local chrome = use(chromeFact) :: any
				local band = chrome.band
				if not use(riding) or band == nil then
					return { type = "fixed", px = 0 }
				end
				return { type = "fixed", px = math.max(0, pick(chrome, use(viewportFact))) }
			end))
		end
		-- ...and whether this screen has room for the fixture's own caption (see the
		-- `UI.When` at the bottom). It reads the SAME two facts the HUD's margin
		-- does — the viewport and the simulated URL bar — so "the instrument yields
		-- first" is derived from the demo's own state rather than from a second
		-- guess about screen size.
		local roomForCaption = scope:own(core:memo(function(use)
			return ((use(viewportFact) :: any).h - urlBarPx(use)) >= CAPTION_FLOOR
		end))
		-- the DRAWN bar's box, and it is the same number the HUD lost — one memo,
		-- so the picture and the geometry cannot disagree (item 5)
		local barHeight = scope:own(core:memo(function(use)
			return { type = "fixed", px = urlBarPx(use) }
		end))

		local stripLead = edgeSpacer(function(chrome, _vp)
			return chrome.band.x - chrome.insets.left
		end)
		local stripTrail = edgeSpacer(function(chrome, vp)
			return (vp.w - chrome.insets.right) - (chrome.band.x + chrome.band.w)
		end)

		-- ---- the material ------------------------------------------------
		--[[ THE HUD'S ONE PLATE. Everything a player sees here sits on this
			construction and on no other, which is what makes nine independently
			degrading zones read as one interface:

			  a `UI.Box` — the one container-shaped class that takes the continuous
			  tint channel — filling the stack behind the content, tinted to the
			  theme's own `surface` at a single shared transparency, and rounded
			  ONCE (on the plate, because the ZStack itself paints nothing and a
			  square plate inside a rounded stack would just paint the corners back).

			The plate is `fill` on both axes inside a HUGGING stack, which is exactly
			the case tests/zstack_fill_diagnostic pins as legal: `measure` answers a
			fill child with its content (nothing), so the stack hugs the CONTENT
			child, and `arrange` then grants the plate the box that produced. So the
			glass is always exactly as big as what is on it, at every text
			preference and in every theme, with nobody sizing it. ]]
		--
		-- `width` is the ONE thing a caller may state: a plate that has to SPAN
		-- something (the health bar's lane) cannot hug, and a ZStack that hugs would
		-- measure a `fill` child as nothing and collapse it. Everything else about
		-- the construction is fixed here on purpose.
		-- `height` joins `width` for the one caller that has to STATE a box rather
		-- than hug one: the pseudo URL bar is as tall as the height it is taking,
		-- and a hugging stack is capped by what the parent had left over — which
		-- drew a 171px bar for a 200px loss (measured 2026-08-15).
		local function glass(id: string, radius: string, content: any, width: any?, height: any?): any
			return UI.ZStack({
				id = id,
				width = width,
				height = height,
				children = {
					UI.corners(
						UI.Box({
							id = "Plate",
							width = { type = "fill", weight = 1 },
							height = { type = "fill", weight = 1 },
							surface = "raised",
							tint = { role = "surface", blend = 1, transparency = GLASS },
						}),
						radius
					),
					content,
				},
			})
		end

		-- a glass PILL of one line of text: the HUD's smallest unit, used for the
		-- objective chip, the scores, the readout and every caption that needs to
		-- lift off the world behind it
		local function pill(id: string, text: any, size: string): any
			return glass(
				id,
				"pill",
				UI.HStack({
					id = id .. "Row",
					padding = { top = 4, right = 10, bottom = 4, left = 10 },
					align = "center",
					children = { UI.Text({ id = id .. "T", text = text, textSize = size }) },
				})
			)
		end

		-- THE ROUND ICON BUTTON, the face of both clusters. `shape = "circle"` +
		-- `icon` is the only icon affordance in the library that takes a SEMANTIC
		-- NAME rather than an asset (a package that ships art for that name paints
		-- it; every other package draws the framework's own ASCII-safe glyph) — so
		-- this HUD invents no art at all. The `label` is the accessible name and is
		-- deliberately not drawn on a circle.
		--
		-- `size` is a theme metric NAME, never a number: the bottom-right cluster is
		-- the thumb-sized one and the top-left strip is the compact one, and both
		-- follow whatever the installed package thinks those two sizes are.
		local function roundButton(id: string, label: string, icon: string, size: string, onActivate: any?): any
			return UI.Button({
				id = id,
				label = label,
				icon = icon,
				shape = "circle",
				surface = "chip",
				-- a circle takes at most ONE of width/height, and the other follows
				height = { type = "fixed", px = size },
				-- THE SINK'S TRIGGER RIDES THIS (D7.3). Optional, so the two clusters
				-- that are pure decoration stay exactly what they were.
				onActivate = onActivate,
			})
		end

		-- ---- the task panel ------------------------------------------------
		-- each row: a mark, the task, its bar, and what it pays. The MARK is a small
		-- accent disc rather than an icon, and that is a decision rather than an
		-- omission: the shipped icon set has no "task" glyph, the only icon
		-- affordance is a Button (which would put three focus stops in a HUD that
		-- has none), and this fixture is not allowed to invent art.
		local taskBars = {}
		local taskRows = {}
		for i, key in { "task1", "task2", "task3" } do
			--[[ THE ROW IS THE CONTROL'S OWN ROW, and that is the second thing the
				sweep decided. The reference screenshot stacks the label ABOVE the bar,
				so the first cut did too — and a stacked label WRAPS: it measured as
				one line where the lane is unbounded and arranged as three where the
				lane is 142px, so `TasksFull` came out up to 93px taller than the box
				the ladder had granted it, on every tablet-landscape pass. Measure said
				it fit; arrange disagreed.

				`newProgressView`'s own `label` is the arrangement that already solved
				this: label and track on ONE line, with the label carrying
				`shrinkWeight = 1` so it gives up pixels instead of lines (O-23). A
				task row is therefore the control plus a mark and a reward, and the one
				thing on it that can grow is the one thing that is allowed to. ]]
			local view = LuauUI.newProgressView(LuauUI, core, {
				id = `Task{i}`,
				value = scope:own(core:signal(0.2 * i)),
			})
			table.insert(taskBars, view)
			table.insert(
				taskRows,
				UI.HStack({
					id = `TaskRow{i}`,
					gap = 8,
					align = "center",
					width = { type = "fill", weight = 1 },
					children = {
						--[[ THE MARK IS PAINT, NOT A SURFACE, and the sweep is why.
							`surface = "accent"` subscribes a node to the accent surface's
							whole chrome recipe, and a themed package's `control` insets are
							16-28px of border — on a dot the theme itself sized at 5-12px.
							Every package with a skinned control reported it ("this control
							is smaller than its theme expects",
							docs/lessons/a-fixed-box-cannot-hold-a-themes-frame.md). A mark
							is a COLOUR, so it takes the one continuous channel and no
							recipe at all: `tint` at full blend to the accent role, which
							re-themes exactly as far as it should and no further.

							It is a mark and not an icon deliberately: the shipped icon set
							has no task glyph, the only icon affordance is a Button (three
							focus stops in a HUD that has none), and this fixture is not
							allowed to invent art. ]]
						UI.corners(
							UI.Box({
								id = `Mark{i}`,
								width = { type = "fixed", px = "controls.progress.spinnerDotSize" },
								height = { type = "fixed", px = "controls.progress.spinnerDotSize" },
								tint = { role = "accent", blend = 1 },
							}),
							"pill"
						),
						--[[ THE NAME IS THIS ROW'S OWN TEXT, AND IT NEVER WRAPS.
							`newProgressView`'s built-in `label` shrinks (O-23) but a Text
							that has shrunk to its floor WRAPS, and a wrap is what broke
							this panel: measured at an unbounded width every label is one
							line, so the rank ladder was told the full form fits in 191px
							and arrange then wrapped three labels inside a 142px tablet lane
							and needed 267. Measure and arrange have to agree about height,
							and `lineLimit = 1` is what makes them: this label gives up
							pixels, then characters, and never lines. ]]
						UI.Text({
							id = `TaskName{i}`,
							text = (COPY :: any)[key],
							textSize = "caption",
							lineLimit = 1,
							shrinkWeight = 1,
						}),
						view.blueprint,
						UI.Text({
							id = `Reward{i}`,
							text = (COPY :: any)[`reward{i}`],
							textSize = "caption",
							surface = "chip",
							padding = { top = 2, right = 6, bottom = 2, left = 6 },
						}),
					},
				})
			)
		end

		-- ---- the round timer -------------------------------------------------
		-- A RING IS A CLOCK. `presentation = "circular"` over the fraction of the
		-- round still to run — the shape the reference screenshots use, and the one
		-- the theme packages now size themselves (`controls.progress.circularSize` /
		-- `circularThickness`, authored by all eight since 2026-08-14).
		--
		-- NO `label` and NO `showValue`: the ring's own row would put the text
		-- BEFORE the ring, and `showValue` is refused on this shape outright (the
		-- ring is theme-sized and small, so a readout has no size it is guaranteed
		-- to fit). The time therefore sits beside it as this fixture's own Text, in
		-- the `numeral` role — the type role that exists for a figure that has to
		-- read at a glance.
		local roundLeft = scope:own(core:signal(0.62))
		local timerRing = LuauUI.newProgressView(LuauUI, core, {
			id = "TimerRing",
			value = roundLeft,
			presentation = "circular",
		})

		local health = scope:own(core:signal(0.84))
		local healthBar = LuauUI.newProgressView(LuauUI, core, { id = "HealthBar", value = health })

		-- ---- the weapon rail -------------------------------------------------
		local function weaponChip(id: string, name: string, ammo: string): any
			return glass(
				id,
				"control",
				UI.HStack({
					id = id .. "Row",
					gap = 8,
					align = "center",
					padding = { top = 4, right = 8, bottom = 4, left = 8 },
					children = {
						UI.Text({ id = id .. "Name", text = name, textSize = "caption", shrinkWeight = 1 }),
						UI.Text({
							id = id .. "Ammo",
							text = ammo,
							textSize = "caption",
							surface = "badge",
							padding = { top = 1, right = 5, bottom = 1, left = 5 },
						}),
					},
				})
			)
		end

		--[[ ── EVERY ZONE'S RICHEST FORM, BUILT ONCE AND NAMED ────────────────────
			(director device review 2026-08-16, second finding: *"I'd expect when I
			press on 'win a round' to see the same contents I see in landscape when it's
			expanded."*)

			These seven locals ARE the richest form of the seven zones that have content
			to lose, and they are hoisted for one reason: the recovery panel below mounts
			THE SAME BLUEPRINT OBJECTS. Before this the panel carried a hand-written
			transcription beside them — `"Win a round  +50"` as one flat caption where
			the rich form shows a mark, the task's name, its progress bar and its reward
			chip — so the route reached a different, lesser thing than the form it was
			disclosing, and the two copies could drift apart with nothing to notice.

			ONE OBJECT, NOT TWO EQUAL ONES, is what makes drift impossible rather than
			merely unlikely: there is no second construction to keep in step, and a zone
			whose rich form gains a row gains it on the route in the same edit. The same
			blueprint standing at two PATHS is the idiom `TasksOne` already used for
			`taskBars[1]` — a blueprint is a frozen descriptor and its identity in the
			tree is its path, so mounting one twice is two nodes, not one shared node.

			The bars are the live `newProgressView` blueprints, so the disclosed bar
			reads the same signal the HUD's does and cannot show a stale figure. ]]
		local clockStack = UI.HStack({
			id = "ClockStack",
			gap = 6,
			align = "center",
			children = {
				pill("ScoreHome", COPY.scoreHome, "numeral"),
				glass(
					"TimerPod",
					"pill",
					UI.HStack({
						id = "TimerRow",
						gap = 6,
						align = "center",
						padding = { top = 4, right = 12, bottom = 4, left = 12 },
						children = {
							-- THE RING NEEDS A BOX, for the reason the health bar does one
							-- zone over: `newProgressView`'s row is `fill` on purpose, so
							-- inside a HUGGING pod it measures as nothing and the ring inside
							-- it overflows by exactly its own diameter (measured: "content
							-- overflows this hstack by 24px"). The box is the THEME's ring
							-- metric, so a package that draws a 44px ring gets a 44px box and
							-- this fixture never learns a number.
							UI.HStack({
								id = "TimerRingBox",
								width = { type = "fixed", px = "controls.progress.circularSize" },
								children = { timerRing.blueprint },
							}),
							UI.Text({ id = "TimerText", text = COPY.timer, textSize = "numeral" }),
						},
					})
				),
				pill("ScoreAway", COPY.scoreAway, "numeral"),
			},
		})
		local healthPod = glass(
			"HealthPod",
			"pill",
			UI.HStack({
				id = "HealthRow",
				gap = 8,
				align = "center",
				padding = { top = 4, right = 12, bottom = 4, left = 12 },
				children = {
					UI.Text({ id = "HealthNum", text = COPY.health, textSize = "numeral" }),
					--[[ THE BAR NEEDS A BOX, and this pod HUGS.
						`newProgressView`'s row is `fill` by construction — a bar spans
						whatever it is given — so inside a hugging pod it measures as
						nothing and vanishes.

						`sizing = "fill"` on the region was tried first and is wrong here:
						it makes the zone's own box the pod's, and the bottom-left zone's
						granted HEIGHT then capped the pod 5px under what its content needs
						— the sweep reported the pod overflowing its own plate on every
						compact-phone pass. A fixed 96px box is an app-level decision (a
						health bar you can read without eating the corner), which is exactly
						the kind of literal an app is allowed and a framework control is not
						— and inside a DROPPED region it costs nothing, because the adapter
						writes `Visible = false` down the whole subtree (proved in
						tests/hud_composition.spec). ]]
					UI.HStack({
						id = "HealthBarBox",
						width = { type = "fixed", px = 96 },
						children = { healthBar.blueprint },
					}),
				},
			})
		)
		local railTall = UI.VStack({
			id = "RailTall",
			gap = 4,
			align = "end",
			children = {
				weaponChip("W1", COPY.weapon1, COPY.ammo1),
				weaponChip("W2", COPY.weapon2, COPY.ammo2),
				weaponChip("W3", COPY.weapon3, COPY.ammo3),
			},
		})
		local actionsCol = UI.VStack({
			id = "ActionsCol",
			gap = 8,
			align = "end",
			children = {
				roundButton("A1", COPY.action1, "more", "controlSizes.large.height"),
				roundButton("A2", COPY.action2, "menu", "controlSizes.large.height"),
				roundButton("A3", COPY.action3, "checkmark", "controlSizes.large.height"),
			},
		})
		local feedLine = UI.Text({ id = "FeedLine", text = COPY.feed, textSize = "caption" })
		local readoutText = UI.Text({ id = "ReadoutText", text = COPY.readout, textSize = "caption" })
		local weaponText = UI.Text({ id = "WeaponText", text = COPY.weaponName, textSize = "caption" })

		--[[ ── THE OVERFLOW SINK (D7.3) ─────────────────────────────────────────
			DROPPING STOPS MEANING DELETING. Every zone that is not showing everything
			it has is listed here, and the list is the FRAMEWORK's
			(`resolution.unshown`, D7.1) rather than this fixture's own re-derivation
			of it — which is the whole point of the seam: three rules (a dropped region
			is not `form > 1`; a `recover = "none"` region is not missing anything; a
			one-form region can only be missing by being dropped) re-implemented per
			consumer is how "adaptation deleted the player's information" ships.

			IT IS A CONTENT PANEL, NOT A MENU OF VERBS, and that is D2's own ruling
			read the right way round: a menu item RUNS something, and "the score is
			12-9" runs nothing. So the recovery is D1's `presentAnchored` — the
			content is simply THERE the moment the panel opens, with no second
			navigation step that could itself be adapted away.

			THE HOST IS THE THIRD DISC IN THE ROUND STRIP, and that is the repair to
			the defect the baseline found: the `...` affordance used to live in
			`RoundColumn`, a FORM the ladder never chose, so it measured 36x36 and was
			`Visible = false` at every viewport this fixture has ever been swept at —
			the one control that recovers everything else was the one control nobody
			could reach. It now lives in a rank-1 region with ONE form, so there is no
			losing form for it to sit in and no rank below it to be dropped for. ]]
		--[[ ...AND WHAT THE ROUTE REACHES IS THE FORM ITSELF (director round 2,
			2026-08-16). Each entry is the zone's RICHEST form, by object identity —
			the same blueprints the HUD mounts, hoisted above. It used to be a table
			of hand-written strings, and that is the defect this closes: a route that
			reaches a lesser thing than the form it discloses is a second elision
			wearing a disclosure's clothes.

			`Health` carries the label the pod does not have room for, because the pod
			IS a bare figure beside a bar on a HUD where its position says what it is,
			and on a panel of eight zones it needs a name. That is the one addition;
			nothing is subtracted anywhere. ]]
		local RECOVERED: { [string]: () -> { any } } = {
			Tasks = function()
				return {
					UI.Text({ id = "RecoveredTasksTitle", text = COPY.tasksTitle, textSize = "label" }),
					taskRows[1],
					taskRows[2],
					taskRows[3],
				}
			end,
			Health = function()
				return {
					UI.Text({
						id = "RecoveredHealthLabel",
						text = COPY.healthLabel,
						textSize = "caption",
						role = "secondary",
					}),
					healthPod,
				}
			end,
			-- the SCORES, which is the case no re-rank could have fixed: the Clock is
			-- in the centre lane and the readout it is compared against is in the
			-- right one, and rule 3 only ever spends the currency of the lane that
			-- does not fit
			Clock = function()
				return { clockStack }
			end,
			Rail = function()
				return { railTall }
			end,
			Actions = function()
				return { actionsCol }
			end,
			Feed = function()
				return { feedLine }
			end,
			Readout = function()
				return { readoutText }
			end,
			Weapon = function()
				return { weaponText }
			end,
		}

		-- the last solve's resolution, through the runner's own accessor (the same
		-- one `composition` uses) — nil before anything has solved
		local function state(): any
			return if ctx.composition ~= nil then ctx.composition("/HudScreen/Hud") else nil
		end

		--[[ WHAT IS HIDDEN, FROM THE FRAMEWORK'S OWN LIST. The ids on a resolution
			are NODE PATHS (`/HudScreen/Hud/Tasks`), because that is what addresses a
			rect, a form and a focus ring; the leaf is what this fixture named its
			zones. Splitting it here rather than storing paths in `RECOVERED` keeps
			the recovery table readable and independent of where the HUD is mounted. ]]
		local function hiddenNow(): { { id: string, reason: string, route: string } }
			local dump = state()
			local out = {}
			for _, entry in (if dump ~= nil then dump.unshown else nil) or {} do
				local leaf = string.match(entry.id, "([^/]+)$") or entry.id
				table.insert(out, { id = leaf, reason = entry.reason, route = entry.route })
			end
			return out
		end

		local overflowHandle: any = nil
		local overflowOpen = scope:own(core:signal(false))

		local function closeOverflow()
			if overflowHandle ~= nil and ctx.presenter ~= nil and ctx.presenter.dismiss ~= nil then
				ctx.presenter.dismiss(overflowHandle)
			end
			overflowHandle = nil
			overflowOpen:set(false)
		end

		local function overflowPanel(): any
			local rows: { any } = {
				UI.Text({ id = "OverflowTitle", text = COPY.overflowTitle, textSize = "label" }),
				UI.Text({
					id = "OverflowNote",
					text = COPY.overflowNote,
					textSize = "caption",
					role = "secondary",
				}),
			}
			local hidden = hiddenNow()
			if #hidden == 0 then
				-- ...AND THE EMPTY STATE IS NOT AN EMPTY PANEL. A sink that opens onto
				-- nothing reads as broken; a sink that says "nothing is hidden" is the
				-- demonstration finishing its own sentence.
				table.insert(
					rows,
					UI.Text({
						id = "OverflowEmpty",
						text = COPY.overflowEmpty,
						textSize = "caption",
						role = "secondary",
					})
				)
			end
			for _, entry in hidden do
				local build = RECOVERED[entry.id]
				if build == nil then
					continue
				end
				--[[ THE FORM ITSELF, not a description of it. Every child here is a
					blueprint the HUD mounts too, so the panel cannot show less than the
					zone it is disclosing and cannot drift from it. The rows are `fill`
					width and their labels already shrink (O-23 / `lineLimit = 1`), so a
					240px plate holds them at 1.4x exactly as a HUD lane does. ]]
				for _, view in build() do
					table.insert(rows, view)
				end
			end
			table.insert(
				rows,
				UI.Button({
					id = "OverflowClose",
					label = COPY.overflowClose,
					surface = "chip",
					onActivate = function()
						closeOverflow()
					end,
				})
			)
			--[[ A TAP AWAY CLOSES IT, through the shipped contribution seam rather than
				a presenter option: `outsideDismiss.dismiss` is THIS fixture's own
				`closeOverflow`, so the handle, the signal and the screen can never
				disagree about whether the sink is open. `consume = false` is the
				row-actions mode — the tap still reaches whatever it landed on — because
				a HUD's own controls stay live while a disclosure plate is up. ]]
			return LuauUI.contribution.attach(
				glass(
					"OverflowPanel",
					"panel",
					UI.VStack({
						id = "OverflowBody",
						padding = 12,
						gap = 6,
						width = { type = "fill", weight = 1 },
						children = rows,
					}),
					-- a fixed panel width is an APP-level decision (a plate a thumb can
					-- read without covering the screen), which is the kind of literal an
					-- app is allowed and a framework control is not — and it is what gives
					-- every line above something to wrap inside
					{ type = "fixed", px = 240 }
				),
				{
					outsideDismiss = {
						active = scope:own(core:memo(function(use)
							return use(overflowOpen) == true
						end)),
						dismiss = function()
							closeOverflow()
						end,
						consume = false,
					},
				}
			)
		end

		local function openOverflow()
			if overflowHandle ~= nil then
				closeOverflow()
				return
			end
			if ctx.presenter == nil or ctx.presenter.presentAnchored == nil then
				return
			end
			overflowHandle = ctx.presenter.presentAnchored(overflowPanel(), {
				id = "HudOverflow",
				anchor = {
					source = { path = "/HudScreen/Hud/Rounds/RoundStrip/R3" },
					edge = "bottom",
					align = "start",
					gap = "s",
					tail = true,
				},
				-- EDGE TO EDGE because an anchored surface is placed in WINDOW space and
				-- anything else is refused; the placement honours the safe area itself
				rootPolicy = "edgeToEdge",
			})
			overflowOpen:set(true)
		end

		--[[ ══ THE PAINT PROBE, ON A SURFACE OF ITS OWN (NM-H4a) ══════════════

			WHAT IT IS FOR. A device-only defect no instrument in this repository can
			see: on a real phone, opening this demo in portrait, toggling the URL bar on
			and off, then rotating to landscape leaves a contiguous document-order
			PREFIX of the HUD not painting, and it never comes back (`h.jpeg`). 288
			headless replays of that sequence, 144 ordered viewport pairs, 36 live Studio
			combinations and a Studio device-emulator rotation all diverged by ZERO
			against a fresh mount. Neither headless nor the emulator performs a true
			orientation change, and every one of those instruments reads the framework's
			OWN MODEL — rects, `hiddenRoots`, the composition resolution. If the model is
			right and the engine write never landed, all of them agree and all of them
			are wrong. So this probe reads BOTH SIDES and reports the DISAGREEMENT.

			WHY IT IS A SEPARATE SURFACE, and it is the whole design. The failure has
			the signature of a visibility walk that did not finish — `pushVisible` is one
			recursive document-order walk per surface, and a prefix that stopped painting
			with the suffix untouched is what an abandoned walk leaves behind. A readout
			drawn by that same walk would go out with everything else it was supposed to
			describe. `presenter.present` gives this plate its own screen, its own render
			controller, its own solve and its own visibility walk, none of which the
			HUD's walk can reach; `setDisplayOrder(SURFACE_LAYER.toast + 100)` puts it in
			a declared band above, which is also what keeps the cross-surface overlap
			alarm quiet about a pair that is deliberately layered (ADR-0028). The
			photograph is the corroboration: the showcase chrome, a different surface,
			painted perfectly while this HUD did not.

			`responder = "passive"` because a debug overlay may never take the Tab ring
			from the screen it is watching. THE CONSEQUENCE IS WHY THE HOLD SWITCH IS
			NOT ON THIS PLATE: measured headless, a second base surface's focusables are
			in NEITHER surface's traversal ring, in either responder mode — so a control
			here would be reachable by touch and pointer and by nothing else, and this
			repository's floor is four inputs. The switch is therefore the third driver
			in `Drivers` below, where it is an ordinary `UI.Toggle` at the target floor.

			AND THE CAPTURE DOES NOT WAIT FOR THE SWITCH. The failure is transient and
			the next tap may clear it, so the probe LATCHES ITSELF the first frame it
			sees a disagreement: it records that frame, sets `Hold`, and stops sampling.
			Pressing `Hold` off re-arms it. That ordering matters — a manual freeze
			captures the state AFTER the press, and a press on this fixture's own screen
			re-solves the very surface under diagnosis. ]]
		local probeHeld = scope:own(core:signal(false))
		--[[ AN UPVALUE AND NOT A FIELD ON `probeReport`, because that table is
			REPLACED wholesale on every sample — a flag written onto it is gone by the
			next one, which is how this rule silently did nothing the first time it was
			written. ]]
		local probeEverHealthy = false
		local probeHead = scope:own(core:signal(COPY.probeTitle))
		--[[ THE PLATE COLLAPSES, because at full height there is nowhere on this HUD it
			does not cover something (see the note beside `ProbeSlot`). Closed it is the
			head and the counts — the verdict a reader needs to know something is wrong.
			Open it is every line, which is a thing the reader asked for. ]]
		local probeExpanded = scope:own(core:signal(false))
		local probeHeadLabel = scope:own(core:memo(function(use)
			return `{use(probeHead)}{if use(probeExpanded) then " -" else " +"}`
		end))
		local probeBody = scope:own(core:signal(COPY.probeWaiting))
		--[[ ONE TEXT NODE PER LINE, AND THAT IS THE ANSWER TO "WHY IS IT CUT OFF"
			(director, 2026-08-17: *"why isn't luauui handling the overlap in the popup
			so that it's not cutoff right?"*).

			The plate used to hand the framework ONE `UI.Text` carrying five lines
			joined with `\n`. That is a single opaque box: the solver measures it once,
			reserves that height, and everything below it — the button — is placed
			against that one number. When the engine's own text metrics disagree with
			the measurement even slightly, the block draws taller than the box it was
			given, and the sibling under it is drawn over the overflow. Headless the
			measurement agrees with itself and the plate is perfect; on a device it is
			the engine that decides, and three photographs in a row lost the line that
			mattered.

			LuauUI was not failing to lay this out. It was laying out exactly what it
			was given: one box. A VStack of one Text per line is what lets it do the
			job — each line is measured, wrapped and placed on its own, the column's
			height is the sum of what the lines actually need, and a line that grows
			pushes the button down instead of disappearing under it.

			A FIXED SLOT COUNT rather than a `ForEach`: the plate is a diagnostic that
			must not churn the tree it is diagnosing, and the line count is bounded by
			construction (`probeSampleBody` emits at most six). An absent line is a
			`When` that mounts nothing, so an empty slot costs no height and no node. ]]
		--[[ A PATH'S LAST TWO SEGMENTS, plus whatever suffix the verdict attached
			(`@dx,dy`, `off screen`). Every node here lives under `/HudScreen/Hud/`, so
			the head is shared by all of them and the tail is the only part that names
			one. Spending 208px on the shared prefix is how four photographs arrived
			truncated at the answer. ]]
		local function probeTail(path: string): string
			local body, suffix = string.match(path, "^(%S+)(%s.*)$")
			local p = body or path
			local segs = string.split(p, "/")
			local out = if #segs >= 2 then `…/{segs[#segs - 1]}/{segs[#segs]}` else p
			return out .. (suffix or "")
		end

		-- head aside, the plate can emit: wanted, skipped, the NOT PAINTED count, two
		-- culprits, a culprit overflow, the capped roll-call, and the first painted row
		local PROBE_LINE_SLOTS = 9
		--[[ CLOSED, THE PLATE KEEPS THE LINES A READER NEEDS TO KNOW SOMETHING IS
			WRONG: the denominator it watched and the count that failed. `probeBody`
			always carries every line — `report().paintProbe.plate` is the full readout
			for a scripted driver either way — and this decides only what the SURFACE
			shows. ]]
		-- head + the denominator + whatever anomaly line follows it. A closed plate
		-- that showed only counts is what let `14 of 14 painting` be the whole story.
		local PROBE_CLOSED_LINES = 3
		local probeLine: { any } = {}
		for i = 1, PROBE_LINE_SLOTS do
			probeLine[i] = scope:own(core:memo(function(use)
				if i > PROBE_CLOSED_LINES and not use(probeExpanded) then
					return nil
				end
				local body = use(probeBody) :: string
				return string.split(body, "\n")[i]
			end))
		end
		-- the switch says which way it goes, because a button labelled with its own
		-- state reads as a claim about now rather than as an action
		local probeButtonLabel = scope:own(core:memo(function(use)
			return if use(probeHeld) then COPY.probeArm else COPY.probeFreeze
		end))
		-- THE HANDLE THIS FIXTURE IS PRESENTED ON, which the fixture does not own:
		-- the HOST presents `screen` and writes `handle` back onto the table returned
		-- below (`scenarios/runner.luau`, the showcase host, and the sweep all do).
		-- Forward-declared and read LAZILY for that reason — `row_actions` reaches its
		-- own controller the same way.
		local result: any
		local probeReport: any = {
			lost = {},
			unmeasured = {},
			skipped = {},
			mismatched = {},
			firstPainted = nil,
			hiddenUnder = nil,
			painting = 0,
			wanted = 0,
			declared = #PROBE_ROWS,
			expected = 0,
			latches = 0,
			samples = 0,
			engine = false,
			solves = 0,
			viewport = "",
			head = COPY.probeTitle,
			plate = COPY.probeWaiting,
		}

		--[[ RE-ENTRANCY, because this now runs from TWO clocks (below) and it writes
			the signals that paint its own surface. A sample taken inside a sample
			would read the same frame twice and could recur. ]]
		local probeSampling = false
		--[[ THE TWO-SAMPLE RULE FOR POSITION (see `enginePaints`). `driftHeld` is what
			the LAST CONFIRMING sample saw drifting; `driftNow` is what this one sees. A
			path in both has stood still through a whole tick of the clock that belongs
			to neither surface, which no frame of engine lag can do. Only a confirming
			sample rolls one into the other, so two solves in the same frame cannot
			promote each other. ]]
		local driftHeld: { [string]: string } = {}
		local driftNow: { [string]: string } = {}
		local function probeSampleBody(confirming: boolean)
			table.clear(driftNow)
			local handle = if result ~= nil then result.handle else nil
			local ctrl = if handle ~= nil then handle.controller else nil
			if ctrl == nil or ctrl.screenRectOf == nil or ctrl.hiddenRoots == nil then
				return
			end
			--[[ THE MODEL SIDE: what the framework BELIEVES it is painting. A node
				paints when it has a real solved rect and neither it nor any ancestor is
				a hidden root — `hiddenRoots()` is documented as the ROOT set (the solver
				marks candidate roots and the renderer carries the verdict down), so the
				prefix walk here is how a caller consumes it. ]]
			local hiddenRoots = ctrl.hiddenRoots()
			local function modelPaints(path: string): boolean
				local rect = ctrl.screenRectOf(path)
				if rect == nil or rect.w < 1 or rect.h < 1 then
					return false
				end
				if hiddenRoots[path] == true then
					return false
				end
				for _, up in probeAncestors(path) do
					if hiddenRoots[up] == true then
						return false
					end
				end
				return true
			end
			--[[ THE ENGINE SIDE, through the host's own seam — the fixture never touches
				an Instance.

				IT IS TRI-STATE, AND THE FIRST CUT OF THIS PROBE WAS NOT. With no seam it
				used to answer `true` for every path: "could not measure" published as
				"measured yes", which is precisely the collapse
				docs/lessons/capability-probes-must-be-tri-state.md exists for — and it
				is what let a plate read `13 of 13 painting` on a phone that was missing
				six things. There is no engine verdict at all below; there is a verdict
				for the paths that were READ, and a separate `unmeasured` state for the
				rows nobody could read. A count is a claim, and this instrument may only
				make claims it measured.

				A SEAM THAT ANSWERED NOTHING IS NOT A SCREEN WITH NOTHING ON IT. The
				shipped host reads `adapter.getInstance`; an adapter without it, or a
				path map that has moved on, returns `{}` — forty paths asked, zero
				answered. That is the seam failing, and calling forty rows LOST would be
				the same false verdict pointing the other way.

				OUTERMOST ANCESTOR FIRST, deliberately: when a walk stops part-way the
				ancestor is the node that was actually hidden and the leaf still says
				`Visible = true`, so reading the leaf alone would report the screen
				healthy. The name it returns is the one thing worth typing into a bug
				report — seven rows all lost UNDER ONE node is a different defect from
				seven rows each hidden on their own. ]]
			local geo = if ctx.geometry ~= nil then ctx.geometry(PROBE_QUERY) else nil
			local answered = 0
			if geo ~= nil then
				for _ in geo do
					answered += 1
				end
			end

			--[[ THE TWO SIDES ARE NOT IN THE SAME COORDINATE SPACE, AND THAT COST TWO
				DEVICE ROUNDS (director, 2026-08-17: `@0,-58` on every row of a screen
				that was WORKING).

				`screenRectOf` answers in WINDOW space. The engine seam answers off the
				live GuiObject, and a LuauUI ScreenGui is `IgnoreGuiInset = true`, so its
				descendants' `AbsolutePosition` reads back with the GUI inset SUBTRACTED
				— on that phone, 58px, which is exactly the number the plate printed for
				every node it accused. Comparing the two directly makes a constant
				space difference look like a defect on every row at once, and it latched
				the probe at solve 3 on a healthy screen twice running.

				SO CALIBRATE, DO NOT ASSUME. The offset is whatever the host's seam is
				doing, and this fixture must not know a number: take the MODAL delta
				across every measured row and treat that as the space. A node whose own
				delta matches the surface's is where the solver put it; a node that
				differs from its own neighbours is misplaced, and THAT is the defect this
				check was added for. Self-calibrating, so it survives a host that answers
				in window space (offset zero) and one that does not.

				Refused below three measured rows: a mode over two samples is not a mode,
				and a check that cannot calibrate must not accuse. ]]
			local spaceDX, spaceDY = 0, 0
			local spaceKnown = false
			if geo ~= nil then
				local tally: { [string]: number } = {}
				local counted = 0
				for path, own in geo do
					local want = ctrl.screenRectOf(path)
					if want ~= nil then
						local key = `{math.floor(own.x - want.x + 0.5)}|{math.floor(own.y - want.y + 0.5)}`
						tally[key] = (tally[key] or 0) + 1
						counted += 1
					end
				end
				local bestKey, bestN = nil, 0
				for key, n in tally do
					if n > bestN then
						bestKey, bestN = key, n
					end
				end
				if bestKey ~= nil and counted >= 3 then
					local sx, sy = string.match(bestKey, "^(-?%d+)|(-?%d+)$")
					spaceDX, spaceDY = tonumber(sx) or 0, tonumber(sy) or 0
					spaceKnown = true
				end
			end
			local engineRead = geo ~= nil and answered > 0

			local mismatched: { string } = {}
			local culprits: { string } = {}
			--[[ ...AND `Visible` IS NOT "PAINTING", which is the other half the first
				cut collected and never read. The seam has always answered
				`AbsoluteSize`; the verdict looked only at the paint bit. A node the
				engine is drawing at zero pixels — a parked corpse still in the path
				map, a node that was never materialised, a box that collapsed — is
				`Visible = true` and occupies nothing, and that is exactly the "the
				decision was right and the write never landed" class this whole
				instrument exists for.

				THE SIZE COMPARISON IS A NOTE AND NEVER A VERDICT. `screenRectOf` and
				`AbsoluteSize` are two spaces that agree today, and an instrument that
				cried wolf over a rounding difference would be as useless as one that
				never fires — so a disagreement is REPORTED, by name, and the row still
				counts as painting. Zero pixels is the unambiguous half, and that one
				is a loss. ]]
			local function enginePaints(path: string): (boolean, string?)
				local own = geo[path]
				if own == nil then
					-- every watched leaf is a non-elidable class, so "no Instance" here is
					-- "not materialised", never "elided and fine"
					return false, path
				end
				local chain = probeAncestors(path)
				for i = #chain, 1, -1 do
					local up = geo[chain[i]]
					if up ~= nil then
						-- a SURFACE ROOT is `ScreenGui.Enabled`, not `GuiObject.Visible`, and
						-- every watched path is a GuiObject: without this a whole screen goes
						-- dark with all fourteen rows still reporting `Visible = true`
						if up.enabled == false then
							return false, chain[i]
						end
						if up.visible == false then
							return false, chain[i]
						end
						if up.groupAlpha ~= nil and up.groupAlpha >= 1 - 1e-6 then
							return false, `{chain[i]} faded`
						end
						if up.clippedBy ~= nil then
							return false, `{chain[i]} clipped by {up.clippedBy}`
						end
					end
				end
				if own.enabled == false or own.visible == false then
					return false, path
				end
				--[[ THE TWO WAYS A PERFECT RECT PAINTS NOTHING (`IMG_3759`, 2026-08-17:
					`14 of 14 painting` over a screen missing six zones, every rect, size,
					`Visible` and `Enabled` correct). A `CanvasGroup` ancestor faded to
					nothing renders its whole subtree into a buffer drawn at nothing; an
					ancestor that CLIPS and does not contain this node simply never draws
					it. Neither touches a single property this probe was reading. ]]
				if own.groupAlpha ~= nil and own.groupAlpha >= 1 - 1e-6 then
					return false, `{path} faded`
				end
				if own.clippedBy ~= nil then
					return false, `{path} clipped by {own.clippedBy}`
				end
				if own.w < 1 or own.h < 1 then
					return false, path
				end
				local want = ctrl.screenRectOf(path)
				--[[ WHERE, NOT JUST HOW BIG (director, device, 2026-08-17: `a1.jpeg`).
					The plate read `14 of 14 painting` over a screen missing its whole left
					column. This function had the engine's `x`/`y` in hand the entire time
					and compared only `w`/`h` — so a node the engine draws at a STALE
					POSITION, or off the edge of a rotated window, reported painting at full
					size for as long as it stayed wrong.

					A POSITION IS A VERDICT WHERE A SIZE IS A NOTE, and the asymmetry is
					deliberate. `screenRectOf` and `AbsoluteSize` are two spaces that can
					round against each other by a pixel, which is why a size difference is
					reported and forgiven. A box sitting somewhere the solver never put it
					is not rounding: `applyRect` is the only writer of `Position`, so the
					two can only disagree when a write did not land. The threshold is 2px —
					above any rounding, below any real move.

					OFF THE VIEWPORT IS THE SAME DEFECT WEARING ITS WORST CASE, and it is
					checked separately because a node can be exactly where the solver put it
					while the solver's own box is off-screen. ]]
				if want ~= nil then
					if
						(math.abs(own.w - want.w) > 1 or math.abs(own.h - want.h) > 1)
						and table.find(mismatched, path) == nil
					then
						table.insert(mismatched, path)
					end
					local dx, dy = own.x - want.x - spaceDX, own.y - want.y - spaceDY
					if spaceKnown and (math.abs(dx) > 2 or math.abs(dy) > 2) then
						--[[ A DRIFT IS NOT A LOSS UNTIL A SECOND SAMPLE AGREES, and shipping
							it as one broke this instrument for a whole device pass
							(`b.jpeg`: latched at solve 2 on a plate that then read a portrait
							viewport forever). `present.onGeometry` fires from the HUD's own
							SOLVE — before the engine has laid the new positions out — so on the
							frame of any layout change the engine's rect is legitimately last
							frame's, and every rotation would latch.

							The confirming clock is `presenter.onTick` at 4Hz, which belongs to
							neither surface: a quarter second is far longer than the engine
							needs to catch up, so a drift still standing on the next tick is a
							write that never landed rather than a frame of lag. Recorded on
							every sample, promoted only by the tick. ]]
						driftNow[path] = `{math.floor(dx + 0.5)},{math.floor(dy + 0.5)}`
						if driftHeld[path] ~= nil then
							return false, `{path} @{driftNow[path]}`
						end
						return true, nil
					end
				end
				local vp = viewportFact:get() :: any
				local wx, wy = own.x - spaceDX, own.y - spaceDY
				if spaceKnown and (wx + own.w <= 0 or wy + own.h <= 0 or wx >= vp.w or wy >= vp.h) then
					driftNow[path] = "off screen"
					if driftHeld[path] ~= nil then
						return false, `{path} off screen`
					end
					return true, nil
				end
				return true, nil
			end

			local lost: { string } = {}
			local unmeasured: { string } = {}
			local skipped: { string } = {}
			local firstPainted: string? = nil
			local hiddenUnder: string? = nil
			local painting = 0
			local wanted = 0
			for _, row in PROBE_ROWS do
				local wants: { string } = {}
				for _, path in row.paths do
					if modelPaints(path) then
						table.insert(wants, path)
					end
				end
				if #wants == 0 then
					--[[ NOT A DEFECT AND NOT A PASS EITHER. This row has no form the
						framework expects on screen at this size, so there is nothing here to
						hold the engine to — but it used to `continue`, which took the row out
						of the denominator with nothing said. That is how `13 of 13 painting`
						was printed over fourteen declared rows, and it is the same false
						negative as an unmeasurable verdict: a row nobody proved is NAMED,
						never omitted. `report().unshown` is the framework's own half of it. ]]
					table.insert(skipped, row.name)
					continue
				end
				wanted += 1
				if not engineRead then
					table.insert(unmeasured, row.name)
					continue
				end
				--[[ EVERY PATH THE MODEL WANTS, not any of them. Alternate forms read the
					same either way (the model picks exactly one); siblings do not, and
					`Rounds` is three of them. ]]
				local painted = true
				local culprit: string? = nil
				for _, path in wants do
					local ok, where = enginePaints(path)
					if not ok then
						painted = false
						if culprit == nil then
							culprit = where
						end
					end
				end
				if painted then
					painting += 1
					if #lost > 0 and firstPainted == nil then
						firstPainted = row.name
					end
				else
					table.insert(lost, row.name)
					-- ...and the question is "what is the first painted row AFTER the run",
					-- so a later loss re-opens it
					firstPainted = nil
					if hiddenUnder == nil then
						hiddenUnder = culprit
					end
					--[[ AND EVERY DISTINCT ONE, because that is the whole reason this line
						exists: six rows lost under ONE node is a different defect from six
						lost separately, and a plate that names only the first cannot tell
						them apart (`c4.jpeg`, 2026-08-17 — `hidden under:` named Objective's
						culprit while Rounds, Feed and Readout were lost somewhere else
						entirely, and nothing on the plate said so). ]]
					if culprit ~= nil and table.find(culprits, culprit) == nil then
						table.insert(culprits, culprit)
					end
				end
			end

			local stats = if ctrl.stats ~= nil then ctrl.stats() else nil
			local vp = viewportFact:get() :: any
			--[[ THE HEAD HAS TO FIT ONE LINE OF THE COLUMN. `Paint probe · 393x759 ·
				solve 2 · HELD` wrapped to two and pushed the verdict down the plate on
				three of the director's photographs running. The words are the reader's,
				the space is not negotiable, so the words go. ]]
			local head = `{math.floor(vp.w + 0.5)}x{math.floor(vp.h + 0.5)}`
				.. ` s{if stats ~= nil then stats.solves else 0}`
				.. (if #lost > 0 then ` {COPY.probeHeldTag}` else "")

			--[[ THE PLATE. The denominator it actually watched comes FIRST and always,
				because a count over a shrinking denominator is the defect this readout
				shipped; and when the engine side could not be read the count is
				REPLACED, not annotated. A reader who skims and finds a number has been
				told a fact. ]]
			--[[ THE SOLVER'S OWN COMPLAINT, WHICH THIS PLATE HAS NEVER SHOWN
				(director, 2026-08-17: `f.jpeg` — `14 of 14 painting` over a broken screen,
				with a dark sliver drawn in the left safe-area gutter where no zone
				belongs).

				This probe asks ONE question: does the engine agree with the model. It
				cannot ask whether the model is SANE, and it only ever asks about the
				fourteen paths it was written with — so a screen whose layout is wrong,
				consistently, in both halves, reads as perfectly healthy on every line
				above.

				`controller.diagnostics()` is the framework's own answer to that, and it
				has been sitting there the whole time
				(docs/lessons/the-solver-already-told-you.md). It goes on the plate, in
				the CLOSED set, because a reader who is told "14 of 14 painting" and
				nothing else has been told the wrong thing. ]]
			local findings = if ctrl.diagnostics ~= nil then ctrl.diagnostics() else {}
			local lines: { string } = { `{wanted} {COPY.probeOf} {#PROBE_ROWS} {COPY.probeRows}` }
			if #findings > 0 then
				local first = findings[1]
				table.insert(lines, `{COPY.probeSolver} {#findings}: {probeTail(tostring(first.node or "?"))}`)
			end
			if #skipped > 0 then
				table.insert(lines, `{COPY.probeSkipped} {table.concat(skipped, " · ")}`)
			end
			--[[ ...AND WHY, WHEN THE ANSWER IS A PLATFORM FACT RATHER THAN THE LADDER.
				`Objective` is behind `UI.When{ condition = riding }`, and `riding` is
				`ride AND platformChrome.band ~= nil`. A band the engine has not published
				(or has withdrawn) takes that row out of the denominator with nothing said,
				and the two states are indistinguishable on a photograph — which is exactly
				what happened on 2026-08-17. The INPUT goes on the plate beside the
				verdict. ]]
			local platformBand = (chromeFact:get() :: any).band
			if not riding:get() then
				local why = if ride:get() ~= true then COPY.probeRideOff else COPY.probeNoBand
				local coreTop = ((env:get("coreSafeInsets"):get() or {}) :: any).top or 0
				table.insert(lines, `{COPY.probeNotRiding} {why} · {COPY.probeBandInput}{math.floor(coreTop + 0.5)}`)
			end
			if not engineRead then
				table.insert(lines, COPY.probeNoEngine)
			else
				if #lost == 0 then
					table.insert(lines, `{painting} {COPY.probeOf} {wanted} {COPY.probePainting}`)
				else
					table.insert(lines, `{#lost} {COPY.probeOf} {wanted} {COPY.probeNotPainted}`)
					--[[ THE CULPRIT LINE COMES BEFORE THE NAMES, and that ordering is a
						device finding rather than taste (`b3.jpeg`, 2026-08-17). The plate
						read `6 of 14 NOT PAINTED / Objective · Rounds · Tasks · Feed ·…` and
						the ONE line that says why — the node they are lost under, or the
						offset the engine is drawing them at — was below the fold. The names
						say WHICH; this says WHAT HAPPENED, and only one of those can be
						guessed from the screen itself. ]]
					--[[ THE TAIL, NOT THE HEAD. Every path on this surface begins
						`/HudScreen/Hud/`, which carries no information and ate the column
						four photographs running — `hidden under: /HudScreen/Hud/Strip/Stri…`
						truncated exactly where the answer starts. The last two segments are
						what identify a node to a reader, so those are what the plate spends
						its width on. ]]
					for i, one in culprits do
						if i > 2 then
							table.insert(lines, `+{#culprits - 2} more`)
							break
						end
						table.insert(lines, `{COPY.probeHiddenUnder} {probeTail(one)}`)
					end
					--[[ ...AND THE NAMES ARE CAPPED. Six row names is two wrapped lines that
						push everything after them off a plate a phone can show, and the
						fourth name has never once changed what the reader does next. ]]
					local shown = if #lost > 4 then 4 else #lost
					local names: { string } = {}
					for i = 1, shown do
						table.insert(names, lost[i])
					end
					if #lost > shown then
						table.insert(names, `+{#lost - shown}`)
					end
					table.insert(lines, table.concat(names, " · "))
					if firstPainted ~= nil then
						table.insert(lines, `{COPY.probeFirstPainted} {firstPainted}`)
					end
				end
				if #mismatched > 0 then
					table.insert(lines, `{COPY.probeSizeDiffers} {mismatched[1]}`)
				end
			end
			local plate = table.concat(lines, "\n")

			probeReport = {
				lost = lost,
				unmeasured = unmeasured,
				skipped = skipped,
				-- the two platform facts the `skipped` list can turn on, published so a
				-- scripted driver reads the same reason a reader sees on the plate
				riding = riding:get(),
				band = platformBand,
				mismatched = mismatched,
				firstPainted = firstPainted,
				culprits = culprits,
				hiddenUnder = hiddenUnder,
				painting = painting,
				wanted = wanted,
				declared = #PROBE_ROWS,
				-- the old name for `wanted`, kept so a driver written against the first
				-- cut still reads the number it was reading
				expected = wanted,
				latches = probeReport.latches,
				samples = probeReport.samples + 1,
				engine = engineRead,
				solves = if stats ~= nil then stats.solves else 0,
				viewport = `{math.floor(vp.w + 0.5)}x{math.floor(vp.h + 0.5)}`,
				head = head,
				plate = plate,
			}

			-- ...and the HEAD carries the hold state, because the switch beside the
			-- URL-bar toggle is an icon-only circle: a state nobody can read is a
			-- state nobody has
			probeHead:set(head)
			probeBody:set(plate)
			--[[ A LOSS IS ONLY A LOSS AGAINST A SCREEN THAT ONCE WORKED (director,
				device, 2026-08-17: `c3.jpeg`, `11 of 11 NOT PAINTED` latched at solve 3
				and froze the plate on a portrait frame for the rest of the session).

				At startup the surface has not painted yet: the tree is mounting, the
				engine has not laid it out, and every watched row is legitimately
				invisible. That is indistinguishable from the defect by inspection, and
				it is not the defect — so the probe now needs to have SEEN THE SCREEN
				HEALTHY once before it is allowed to latch on losing it. With no
				baseline there is nothing to have lost.

				It still REPORTS, on every sample: the plate says what it sees from the
				first frame. What it will not do is spend its one capture on a screen
				that had not been built yet. ]]
			if #lost == 0 and #unmeasured == 0 and wanted > 0 then
				probeEverHealthy = true
			end
			if #lost > 0 and not probeEverHealthy then
				return
			end
			if #lost > 0 then
				-- THE LATCH. Recorded first, held second: the plate is already showing
				-- the failing frame before anything on this screen can move.
				--
				-- IT DOES NOT LATCH ON `unmeasured`: a host with no engine seam is in
				-- that state permanently and for a reason the plate already shouts, so
				-- freezing there would spend the one capture on a known limitation.
				probeReport.latches += 1
				probeHeld:set(true)
			end
		end

		local function probeSample(confirming: boolean?)
			if probeHeld:get() or probeSampling then
				return
			end
			probeSampling = true
			probeSampleBody(confirming == true)
			probeSampling = false
			if confirming == true then
				table.clear(driftHeld)
				for path, delta in driftNow do
					driftHeld[path] = delta
				end
			end
		end

		--[[ THE SLOTS, BUILT ONCE. A `When` per line: an absent line mounts nothing,
			so an empty slot costs no node and no height, and the count is bounded by
			what `probeSampleBody` can emit. ]]
		local probeLineViews: { any } = {}
		for i = 1, PROBE_LINE_SLOTS do
			local readable = probeLine[i]
			table.insert(
				probeLineViews,
				UI.When({
					id = `ProbeLine{i}`,
					condition = scope:own(core:memo(function(use)
						return use(readable) ~= nil
					end)),
					thenView = function()
						return UI.Text({
							id = "Line",
							text = readable,
							textSize = "caption",
							width = { type = "fill", weight = 1 },
						})
					end,
				})
			)
		end

		local function probeScreen(): any
			return UI.Screen({
				id = "PaintProbe",
				--[[ THE RIGHT INSET CLEARS THE HUD'S ACTION RAIL, and it is a MEASURED
					number rather than a margin of taste. `Actions` is a 56px column of
					discs pinned to the right edge with the weapon caption under it; a plate
					anchored hard right sits exactly on top of them, which is how a working
					rail was reported as a regression (`IMG_3759`, 2026-08-17). 104 = the
					rail's 56, the caption that overhangs it, and a gap wide enough that the
					two never touch — measured, not guessed. The plate's own 164px is set
					with the same measurement in mind: at 176 the pair is clean only at
					exactly this inset, and a one-pixel margin is a constant waiting to go
					stale. `tests/hud_paint_probe.spec` holds the property in BOTH
					orientations rather than the numbers.

					The probe surface is describing THIS HUD, so knowing where this HUD
					keeps its controls is the fixture's business and not a leak. ]]
				padding = { top = 8, right = 104, bottom = 8, left = 8 },
				children = {
					UI.Anchor({
						id = "ProbeField",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							--[[ SMALL BY DEFAULT, AND THAT IS THE FIX (director, 2026-08-17:
							*"this round seems to have regressed as the buttons on the right
							disappeared"* — `IMG_3759`). They had not. The plate had grown a
							line at a time until it covered them: the action rail and the
							weapon caption were painting perfectly, underneath it.

							"The one band that is empty" was true of a THREE-LINE plate and
							stopped being true without anyone re-checking — the same stale
							reasoning this whole round has been about. Measured: at eight lines
							there is nowhere on a 734x393 HUD it does not cover something. Hard
							right covers the action rail; centred covers the clock.

							So it collapses. The head is a button: closed, the plate is the
							head and the counts, which is what the band actually has room for;
							open, it is everything, and covering the screen is then a thing the
							reader ASKED for rather than a thing the instrument did to them.
							An instrument that hides the screen it is describing is not an
							instrument. ]]
							UI.HStack({
								id = "ProbeSlot",
								anchor = "right",
								children = {
									glass(
										"ProbePlate",
										"panel",
										UI.VStack({
											id = "ProbeBody",
											padding = 8,
											gap = 2,
											width = { type = "fill", weight = 1 },
											children = {
												-- COMPACT: the head is the toggle, so it must not cost a control's
												-- full chrome height on a plate that has to stay out of the way
												UI.Button({
													id = "ProbeHead",
													label = probeHeadLabel,
													surface = "plain",
													textSize = "caption",
													padding = 0,
													width = { type = "fill", weight = 1 },
													onActivate = function()
														probeExpanded:set(not probeExpanded:get())
													end,
												}),
												--[[ ONE TEXT PER LINE (see `probeLine` above). Each line is
													measured, wrapped and placed on its own, so a line that grows
													pushes the button DOWN instead of being drawn under it. ]]
												UI.VStack({
													id = "ProbeLines",
													gap = 1,
													width = { type = "fill", weight = 1 },
													children = probeLineViews,
												}),
												--[[ RELEASE / RE-ARM, and never the capture itself. On the
													plate's own surface it costs the HUD nothing — this
													surface has room the HUD does not — and it is an ordinary
													`UI.Button`, so the 44px target floor is the framework's
													to enforce. Touch and pointer reach it; keyboard and
													gamepad reach the same signal through `steps.holdProbe`
													and `steps.armProbe` until cross-surface traversal exists. ]]
												UI.Button({
													id = "ProbeHold",
													label = probeButtonLabel,
													surface = "chip",
													width = { type = "fill", weight = 1 },
													onActivate = function()
														if probeHeld:get() then
															probeHeld:set(false)
															probeSample()
														else
															probeHeld:set(true)
														end
													end,
												}),
											},
										}),
										--[[ a plate a thumb can read without covering the screen it is
											describing. WIDENED from 168 (director, 2026-08-17): at 168 the
											skipped list truncated to `ScoreHome · TimerRing…` and the line
											that names the defect never reached the photograph. 208 is still
											under a third of the narrowest landscape window this fixture
											declares, and the plate sits in the one band that is empty in
											both of the director's captures. ]]
										{ type = "fixed", px = 164 }
									),
								},
							}),
						},
					}),
				},
			})
		end

		local probeHandle: any = nil
		local function dropProbe()
			if probeHandle ~= nil and ctx.presenter ~= nil and ctx.presenter.dismiss ~= nil then
				ctx.presenter.dismiss(probeHandle)
			end
			probeHandle = nil
		end
		local function raiseProbe()
			if ctx.presenter == nil or ctx.presenter.present == nil then
				return
			end
			dropProbe()
			probeHandle = ctx.presenter.present(probeScreen(), {
				responder = "passive",
				-- content, not decoration: it must clear a notch and a home indicator in
				-- both orientations, which is the whole point of reading it on a phone
				rootPolicy = "deviceSafeContent",
			})
			local controller = probeHandle.controller
			if controller ~= nil and controller.setDisplayOrder ~= nil and ctx.presenter.SURFACE_LAYER ~= nil then
				controller.setDisplayOrder(ctx.presenter.SURFACE_LAYER.toast + 100)
			end
		end
		raiseProbe()

		--[[ THE SECOND CLOCK, AND IT IS PART OF THE HONESTY (2026-08-16).
			`present.onGeometry` below fires from the HUD's OWN solve — which is the
			responsive clock, and which is also the thing under diagnosis. A surface
			that stops solving stops sampling, and the plate then displays its last
			healthy reading with a solve number nobody can date: a stale verdict, worn
			as a current one. That is the same false negative as an unmeasured verdict
			and it is invisible in a photograph.

			So the probe also rides the presenter's frame clock, which belongs to
			NEITHER surface. Quarter-second, because this walks ~forty paths through
			the engine seam and the failure it watches for persists — it does not need
			to be caught within a frame, it needs to be caught at all. `report()`
			publishes `samples` beside `solves` so a driver can see the two clocks
			disagree.

			The presenter's tick is absent headlessly (the suite has no frame clock and
			drives `steps.sampleProbe` instead), so this is the shipped host's half. ]]
		local unbindProbeTick: (() -> ())? = nil
		if ctx.presenter ~= nil and ctx.presenter.onTick ~= nil then
			local since = 0
			unbindProbeTick = ctx.presenter.onTick(function(dt: number)
				since += dt
				if since < 0.25 then
					return
				end
				since = 0
				probeSample(true)
			end)
		end

		-- ---- the HUD -----------------------------------------------------
		local hud = UI.Composition({
			id = "Hud",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			margin = margin,
			groups = LuauUI.composition.HUD_GROUPS,
			arrangements = { LuauUI.composition.HUD },
			children = {
				-- THE PLATFORM'S OWN ROW (ADR-0027). A `span = "above"` group, so it
				-- is one full-width row above every lane in every arrangement — which
				-- is what makes the nine anchored zones start BELOW the platform's
				-- band instead of being told to avoid it. Its content is inset to the
				-- free band's own left edge, so it sits level with Roblox's buttons
				-- and cannot be on them; when nothing is riding, `UI.When` closes the
				-- row entirely and the composition is byte-identical to the HUD that
				-- never had the zone.
				UI.Region({
					id = "Strip",
					group = "topbar",
					rank = 6,
					--[[ RESERVED, AND THIS IS THE ONE THAT WAS FOUND BY THE CHECK.
						With `mayDrop` the row was droppable, so on a 213px-tall window
						the ladder dropped it (rank 6, 58px bought) — and every lane then
						climbed into the space it left, which is THE PLATFORM'S BAND. The
						band is not the HUD's to reclaim: it belongs to Roblox whether or
						not this HUD has anything to put in it. `reserved` is rule 7's own
						word for exactly that, and it is live, so the row reserves nothing
						at all on the rung that is not riding. ]]
					reserved = riding,
					-- the floor a reserved region owes: content-expressed, like every
					-- floor. The row's real height is the band's (a platform fact the
					-- form carries); this is only what it may never fall below.
					floor = { targets = 1 },
					children = {
						UI.HStack({
							id = "StripRow",
							width = { type = "fill", weight = 1 },
							height = stripHeight,
							align = "center",
							children = {
								UI.Spacer({ id = "StripLead", width = stripLead }),
								UI.HStack({
									id = "StripFree",
									width = { type = "fill", weight = 1 },
									align = "center",
									distribute = "center",
									children = {
										UI.When({
											id = "StripChip",
											condition = riding,
											thenView = function()
												-- the band can be narrow (a 320px phone has ~156px
												-- of it), so the fit is the framework's decision
												-- and not an authored width guess
												return UI.ViewThatFits({
													id = "StripFit",
													children = {
														pill("Objective", COPY.objective, "caption"),
														pill("ObjectiveShort", COPY.objectiveShort, "caption"),
													},
												})
											end,
										}),
									},
								}),
								UI.Spacer({ id = "StripTrail", width = stripTrail }),
							},
						}),
					},
				}),
				--[[ THE APP CHROME'S OWN SPACE, one region per column, declared FIRST
					in its group so it sits above the zone it protects.

					`columnReserve` is 0px in every column the chrome does not cover, and
					a 0px region is not mounted at all — it takes no space, no gap and no
					place in the output. So this costs nothing to a host with no chrome
					of its own, and in the showcase it keeps the round buttons clear of
					the demo/settings chips while the clock and the weapon rail rise to
					sit LEVEL with them.

					NOT DROPPABLE, AND THAT IS A RULE RATHER THAN A PREFERENCE (measured
					2026-08-15). It WAS `mayDrop = true`, on the reasoning that "a
					reservation is worth less than the controls it was protecting" — and
					that reasoning is the defect. Measured at 749x380 with the pseudo URL
					bar open and the showcase's chip row declared: the left lane is offered
					78px and needs 62 (this reservation) + 36 (the round strip) = 98. The
					ladder stepped and dropped everything else in that lane — correctly —
					then took the only lever it had left and dropped the reservation,
					buying 62px and landing both round buttons INSIDE the chip row, 36x36
					each.
					
					IT IS THE ONE PURCHASE THE LADDER MUST NOT MAKE. Rule 3's own principle
					is that a candidate has to BUY A PIXEL — never degrade something that
					cannot help the failure it is being asked to fix. Dropping an EXCLUSION
					buys pixels that are not the composition's to spend: they are occupied
					by somebody else's chrome. It is a false purchase, which is that same
					principle one level out. A reservation is not low-ranked content; it is
					the shape of the box, and the ladder's currency is content.
					
					WHAT HAPPENS INSTEAD when the lane still cannot fit is the DEFINED
					FLOOR, pinned in tests/hud_chrome_rotation.spec.luau: the exclusion
					holds, every droppable zone in the lane is gone, and the top-ranked
					zone that is left is placed BELOW the exclusion and runs past the
					composition's own bottom edge — with `fallback = true` on the
					resolution saying so. Content over the app's own chrome is never it. ]]
				UI.Region({
					id = "ChromeLeft",
					group = "topLeft",
					rank = 1,
					children = { UI.Spacer({ id = "ChromeLeftGap", height = reserveLeft }) },
				}),
				UI.Region({
					id = "ChromeTop",
					group = "top",
					rank = 1,
					children = { UI.Spacer({ id = "ChromeTopGap", height = reserveCentre }) },
				}),
				UI.Region({
					id = "ChromeRight",
					group = "topRight",
					rank = 1,
					children = { UI.Spacer({ id = "ChromeRightGap", height = reserveRight }) },
				}),
				--[[ UPPER LEFT — the round-button strip, AND THE SINK THAT LIVES IN IT.
					ONE FORM, and that is the D7 repair rather than a simplification.

					It used to be two: a two-across `RoundStrip` and a three-down
					`RoundColumn`. Two things were wrong with that, and the first one had
					shipped invisibly since the fixture was written:

					  * THE COLUMN FORM WAS NEVER CHOSEN. Measured across nine viewports
					    x two states before this change: `Rounds` resolved to form 1 at
					    every single one. So the third disc — `R3c`, the `...` — was
					    `Visible = false` everywhere, and the round strip had been
					    silently showing two of its three buttons for the fixture's whole
					    life. A form below the richest that holds MORE content than the
					    richest is a ladder pointing the wrong way.
					  * A REGION WITH TWO FORMS CAN ELIDE, and the overflow sink may not
					    live anywhere that can. `recover` is refused on a one-form region
					    precisely because such a region cannot elide — which is the
					    structural guarantee this zone now carries.

					`wrap = true` is what makes one form enough, and it is the framework's
					own answer to the measurement the old comment recorded (three compact
					discs plus their gaps are 120px in a 119px lane on a 359px phone): the
					row wraps to two lines where the lane is narrow and stays one line
					where it is not, at every width, with no ladder and no device branch.
					Height is what it spends, and height is what a narrow portrait phone
					has. ]]
				UI.Region({
					id = "Rounds",
					group = "topLeft",
					rank = 1,
					children = {
						UI.HStack({
							id = "RoundStrip",
							gap = 6,
							wrap = true,
							children = {
								roundButton("R1", COPY.round1, "menu", "controlSizes.compact.height"),
								roundButton("R2", COPY.round2, "flag", "controlSizes.compact.height"),
								-- THE SINK'S HOST. Rank 1, one form, never dropped, wrapped
								-- rather than elided — the four things that make "a host always
								-- exists" true in code instead of true in a comment. Its 36px
								-- disc still delivers a 44px hit rect: `Button` carries a
								-- `minHitSize` clamped up to `targetSizes.minimum`, which is the
								-- three-axes floor this affordance owes on touch.
								roundButton("R3", COPY.round3, "more", "controlSizes.compact.height", openOverflow),
							},
						}),
					},
				}),
				-- MIDDLE LEFT — the task panel, three forms richest first. This is
				-- the panel that landed on the round buttons in the screenshot.
				UI.Region({
					id = "Tasks",
					group = "left",
					-- RE-RANKED 8 -> 7 (D7.4): the fps readout below used to survive
					-- longer than three tasks and their rewards, which is a developer's
					-- telemetry outliving the player's progression
					rank = 7,
					mayDrop = true,
					--[[ "SELF" — THE CHIP IT STEPS DOWN TO IS THE ROUTE (D7.2). While this
						zone is standing in a reduced form, the reduced form is what the player
						is looking at, and the thing left behind has to be reachable FROM
						there: an overflow sink is for when a zone is GONE, not an excuse for a
						dead end that is on screen. The framework refuses the declaration
						unless the last form really does contain something focusable, which is
						what turned `TasksChip` from a glass pill of two `UI.Text` into a
						Button. When the ladder runs out of steps and drops this zone entirely,
						the sink carries it — `mayDrop` now means "moves to the sink". ]]
					recover = "self",
					floor = { lines = 1 },
					children = {
						glass(
							"TasksFull",
							"panel",
							UI.VStack({
								id = "TasksFullBody",
								padding = 10,
								gap = 6,
								width = { type = "fill", weight = 1 },
								children = {
									UI.Text({ id = "TasksTitle", text = COPY.tasksTitle, textSize = "label" }),
									taskRows[1],
									taskRows[2],
									taskRows[3],
								},
							})
						),
						--[[ ONE TASK, AND NOTHING AROUND IT. Two measurements chose this
							form, in order:

							  * the HEADING went first. With the panel title kept over a
							    single row this form was 14px taller than the middle-left
							    zone can grant on an 812x375 window. A heading over one row
							    is the least informative line on it — the row already says
							    what it is.
							  * then the MARK and the REWARD. A HUD lane is a third of the
							    screen: 93px inside this panel's padding on a 359px phone.
							    A mark, a task row and a reward chip do not fit that, so the
							    row's label wrapped instead of shrinking and the panel came
							    out 38-65px taller than its own plate at every preference.
							    `ViewThatFits` on the reward was tried and is the wrong
							    tool — it asks "do I fit the proposal", and inside an HStack
							    the proposal is the whole width rather than what is left
							    after its siblings, so the chip always "fit" and the bar got
							    zero.

							What survives is the control's own row, whose label shrinks by
							construction (O-23). The rich row is what the FULL form is for,
							and the full form is what a screen with room gets. ]]
						--[[ ...AND IT IS ALSO A ROUTE, because a MIDDLE rung is a rung
							(D7.2). `recover = "self"` is checked against every form below the
							richest, not only the last one: this form is what a mid-sized screen is
							left with, and two tasks plus their rewards are missing from it exactly
							as they are from the chip below. A dead end on the device nobody
							fixtures is the whole defect class.

							`surface = "plain"` is what lets the Button be the ROUTE without being a
							second plate: the glass is already painted behind it, and a chip surface
							here would put a control frame inside a panel frame. ]]
						glass(
							"TasksOne",
							"panel",
							--[[ THE ROW IS THE BUTTON'S OWN ROW, and that is not a
								simplification — it is the same measurement the comment below
								records, met a second time. A Button lays its children out as ONE
								row and measures THAT row, so an inner `fill` HStack between them
								contributes nothing to the Button's own measure: the plate hugged
								to 16px and the solver said so ("content box collapses to 0px on x:
								padding 8 + 8 on a 16px width", measured pseudo-localized at
								320x640). The children go straight on the Button. ]]
							UI.Button({
								id = "TasksOneBody",
								label = COPY.tasksTitle,
								surface = "plain",
								onActivate = openOverflow,
								padding = 8,
								gap = 8,
								align = "center",
								width = { type = "fill", weight = 1 },
								children = {
									-- THE NAME IS ALSO WHAT GIVES THIS PANEL A WIDTH. With the row
									-- alone the plate hugged to 16px — a bar is `fill`, so it
									-- measures as nothing and there was nothing else in here to
									-- measure. One non-fill child is what a hugging panel needs,
									-- and the task's name is the one worth having.
									UI.Text({
										id = "TasksOneName",
										text = COPY.task1,
										textSize = "caption",
										lineLimit = 1,
										shrinkWeight = 1,
									}),
									taskBars[1].blueprint,
								},
							})
						),
						--[[ THE TERMINAL FORM, AND IT IS A BUTTON (D7.2). It was `pill(...)`
							— `glass` wrapping an HStack of `UI.Text` — so the ladder's last rung
							for this zone was three tasks and their rewards replaced by an
							untappable label reading "Tasks 1/3". That is the dead end
							`recover = "self"` exists to refuse, and the framework now refuses it
							at construction: a `self` route whose last form holds nothing
							focusable is an authoring error, named at the call site.

							It opens the same panel the ··· sink does, which is deliberate: the
							recovery for "this zone is reduced" and the recovery for "this zone
							is gone" are the same content, and two panels would be two things to
							keep in step. ]]
						UI.Button({
							id = "TasksChip",
							label = COPY.tasksChip,
							surface = "chip",
							textSize = "caption",
							onActivate = openOverflow,
						}),
					},
				}),
				-- LOWER LEFT — the health bar, and under it the kill feed.
				UI.Region({
					id = "Health",
					group = "bottomLeft",
					rank = 5,
					-- ITS REDUCED FORM LOSES THE BAR, and a pill with a figure on it is not
					-- something to tap, so the sink is the honest route rather than "self"
					recover = "overflow",
					-- DROPPABLE, and the measurement is why. The left lane's irreducible
					-- floor is the round-button strip (rank 1, never dropped) plus
					-- whatever else in that lane cannot leave; with the health pod pinned
					-- that floor was 66px and a 735x213 window offers the lanes 30.
					-- Nothing could give, so the whole arrangement went illegal and rule 8
					-- showed the declared fallback — the same shape the weapon rail's own
					-- `mayDrop` note records, one lane over. A health read-out is worth
					-- more than a kill feed (rank 5 vs 9) and less than the buttons the
					-- player is reaching for (rank 1), and saying so is what lets the
					-- ladder finish.
					mayDrop = true,
					children = {
						-- the RICH form, hoisted above and shared with the recovery panel
						healthPod,
						-- the bar ALONE is the compact form: the figure is what a player
						-- reads in a glance and the bar is what they read in a fight, so
						-- when the pod cannot have both the FIGURE is what survives
						pill("HealthOnly", COPY.health, "numeral"),
					},
				}),
				-- LOWER LEFT — the kill feed, droppable: the first thing a real HUD
				-- gives up, and the least missed.
				UI.Region({
					id = "Feed",
					group = "bottomLeft",
					-- RE-RANKED 9 -> 8 (D7.4): a kill feed is thin, but it is something that
					-- happened in the match, and the fps readout is not
					rank = 8,
					mayDrop = true,
					children = { feedLine },
				}),
				-- UPPER CENTRE — the round clock and the two team scores.
				UI.Region({
					id = "Clock",
					group = "top",
					rank = 2,
					--[[ THE SCORES ARE THE CASE NO RE-RANK COULD HAVE FIXED (D7.4). This
						zone's second form is deliberately "the clock and the ring, WITHOUT the
						scores", so `12` and `9` cease to exist the moment the centre lane runs
						short — while the fps readout, a whole region, is still standing in the
						RIGHT lane. Rule 3 spends only the currency of the lane that does not
						fit, so no ranking makes the right lane pay the centre lane's deficit.
						The scoreboard's recovery is the disclosure route, which is exactly
						what "tap for detail" is for. ]]
					recover = "overflow",
					children = {
						-- the RICH form, hoisted above and shared with the recovery panel
						clockStack,
						-- the clock and the ring, WITHOUT the scores: the Studio canary
						-- is why this exists. With the URL bar open on a 735x413 window
						-- the centre column has 61px and the full row needs more. What a
						-- real HUD gives up on a squeezed screen is the score, not the
						-- clock.
						glass(
							"TimerOnlyPod",
							"pill",
							UI.HStack({
								id = "TimerOnlyRow",
								gap = 6,
								align = "center",
								padding = { top = 4, right = 12, bottom = 4, left = 12 },
								children = {
									UI.Text({ id = "TimerOnlyText", text = COPY.timer, textSize = "numeral" }),
								},
							})
						),
					},
				}),
				-- UPPER RIGHT — the weapon rail, two forms, and the readout beside
				-- it. In the screenshot these two are what ran into each other.
				UI.Region({
					id = "Rail",
					group = "topRight",
					rank = 4,
					-- the compact form is ONE weapon name with no ammo count, so two
					-- weapons and three counts are what it stops showing
					recover = "overflow",
					-- DROPPABLE, and the Studio canary is why. On a 735x413 window with
					-- the URL bar open the right column has 61px and holds a 31px rail
					-- over a 46px button: neither could give any more, so the whole
					-- arrangement went illegal and rule 8 showed the DECLARED FALLBACK —
					-- correct by contract, and 16px of HUD painted below its own box. A
					-- weapon rail is more expendable than the action buttons (rank 4 vs
					-- 3), so saying so is what lets the ladder finish instead of falling
					-- back.
					mayDrop = true,
					children = {
						-- the RICH form, hoisted above and shared with the recovery panel
						railTall,
						-- the compact form is NARROWER, not merely shorter: a HUD column
						-- is a third of the screen, so a horizontal compact form is the
						-- wrong ladder in a column (the sweep found this at 320px)
						pill("W1c", COPY.weapon1, "caption"),
					},
				}),
				UI.Region({
					id = "Readout",
					group = "topRight",
					--[[ RE-RANKED 7 -> 9, THE FIRST THING TO GIVE WAY (D7.4). Measured live
						with the URL bar open at 749x380: `60 FPS · 42 ms` was on screen while
						all three tasks, their rewards, the health figure and the kill feed were
						gone. A frame counter is what the developer wants and what the player
						never asked for; it goes first. ]]
					rank = 9,
					mayDrop = true,
					children = { readoutText },
				}),
				-- LOWER RIGHT — the action buttons, two forms (column, then one), at
				-- the thumb size the theme names.
				UI.Region({
					id = "Actions",
					group = "bottomRight",
					rank = 3,
					-- its compact form is ONE disc where the full form is three, so two
					-- actions are what it stops showing
					recover = "overflow",
					children = {
						-- the RICH form, hoisted above and shared with the recovery panel
						actionsCol,
						roundButton("A1r", COPY.action1, "more", "controlSizes.regular.height"),
					},
				}),
				-- ...and the weapon name over them, which is where the screenshot puts
				-- it. Droppable: a player who cannot see the name of the gun in their
				-- own hands has lost the least of everything on this screen.
				UI.Region({
					id = "Weapon",
					group = "bottomRight",
					rank = 6,
					mayDrop = true,
					children = { weaponText },
				}),
			},
		})

		-- The switches are the FIXTURE'S DRIVERS, not HUD content, so they sit under
		-- the HUD rather than in a zone: a Toggle does not fit a third of a 320px
		-- phone, and putting the instrument inside the thing it measures would have
		-- made the narrowest swept viewport a test of the instrument.
		--
		-- The screen is `edgeToEdge` (the HUD needs the top band), so the three edges
		-- with no hole in them are spent HERE, once, from the same fact — which is
		-- also what keeps these two drivers off a home indicator.
		local screen = UI.Screen({
			id = "HudScreen",
			padding = screenPadding,
			gap = 4,
			children = {
				hud,
				-- two switches WRAP rather than run off a 320px phone at the largest
				-- text preference — found by the always-on sweep the moment the second
				-- one was added, which is the sweep doing its job on the instrument
				UI.HStack({
					id = "Drivers",
					gap = 12,
					wrap = true,
					children = {
						UI.Toggle({ id = "UrlBar", label = COPY.urlBarOn, value = urlBar }),
						UI.Toggle({ id = "RideStrip", label = COPY.rideOn, value = ride }),
						--[[ AND THE PAINT PROBE'S HOLD SWITCH IS NOT HERE, WHICH IS A
							MEASUREMENT AND A REPORTED FRAMEWORK GAP (NM-H4a).

							It belongs here on the four-input rule: a second base surface's
							focusables are in NEITHER surface's traversal ring (measured
							headless, in both responder modes — `tests/hud_paint_probe.spec.luau`
							pins it), so a control on the probe's own plate is reachable by touch
							and pointer and by nothing else. LuauUI has no cross-surface
							traversal, and that is the capability this fixture cannot supply for
							itself.

							IT CANNOT COME HERE EITHER, and that half is measured too. This Screen
							has UNDER 8px of headroom at 320x640 with `preferredTextOffset = +14`:
							a third labelled `UI.Toggle` overflowed it by 17-31px under all four
							ornate packages (the row takes a third line), a 36px circle by 6-8px
							(a circle is 8px taller than a Toggle's 28px floor and sets its line's
							height), and a 28px circle is smaller than an ornate package's own
							control chrome — Pixel Quest spends 16+16 of contentInset on it and
							the content box collapses to 0px. An instrument that eats the screen
							it measures is exactly what the comment above this Screen warns about.

							So the plate carries the switch, `steps.holdProbe`/`armProbe` carry the
							scripted route — and neither is the capture. The probe LATCHES ITSELF
							on the frame the disagreement appears, so no input class can miss the
							evidence; what the switch buys is releasing and re-arming it. ]]
					},
				}),
				--[[ THE LADDER, ON THE SCREEN THAT DEMONSTRATES IT. Watching a zone
					step down is only a demonstration if the viewer can see why THAT
					zone was the one chosen, and the rank is otherwise only in the source
					and in `report()`.

					AND IT IS THE FIRST THING TO YIELD, which is the same rule the HUD
					itself runs on, applied to the instrument: this caption is chrome
					ABOUT the demo, so on a screen with no room to spare it goes before
					any zone does. Measured, not guessed — with the caption
					unconditional the 735x213 profile (the director's own URL-bar
					screenshot, with the fixture's URL bar ALSO open) offered the
					composition 0px instead of 13, no arrangement was legal, and the
					declared fallback painted a weapon chip into Roblox's own button
					cluster. An instrument that eats the thing it measures is exactly
					what the comment above this Screen warns about, one level up. ]]
				--[[ THE URL BAR, DRAWN (director 2026-08-15, item 5: *"when we enable
					url bar, we should show a pseudo url bar"*).

					It used to be a `margin.bottom` on the HUD: the height went away and
					nothing appeared in its place, so the only visible effect of the
					switch was content vanishing — which is precisely why the switch read
					as a bug rather than as the demonstration it is. Now the bar is a real
					box at the bottom of the screen, exactly as tall as the height it
					takes, so the cause of the adaptation is on screen beside its effect.

					Its height is the SAME `urlBarPx` memo the caption floor reads, so the
					drawn bar and the room the HUD lost are one number and cannot drift —
					including the short-screen cap (a simulated bar may not eat more than
					the screen has, see HUD_FLOOR_PX). ]]
				UI.When({
					id = "UrlBarWhen",
					condition = scope:own(core:memo(function(use)
						return use(urlBar) == true
					end)),
					thenView = function()
						--[[ ONE LINE THAT SHRINKS, and the sweep is why it is not two.
							The bar's height is capped on a short window (HUD_FLOOR_PX), so
							at 735x213 with the switch on it is 53px — and a field over a
							caption, pseudo-localized at 1.4x, needed 7px more than that.
							A demo's own chrome may not be the thing that overflows the
							screen it is explaining. The field carries `lineLimit = 1` and
							`shrinkWeight` for the same reason every other row in this
							fixture does: it gives up pixels, then characters, never lines. ]]
						--[[ THE BAND IS THE BROWSER'S FACT; THE FIELD IS THE THEME'S (D7.5).
							The band still spans exactly the height the HUD lost — one memo, so
							the picture and the geometry cannot drift (2026-08-15, item 5) — but
							the FIELD inside it is a control, so its box is the control-size
							ladder's, centred in whatever the band turned out to be. That is the
							half that was doing a second job as a pixel constant: with the two
							welded together, an over-stated steal painted a near-empty slab
							(measured 733x158 at 749x380, 42% of the viewport). Now the slab
							cannot happen at any band height, because the field never grows to
							fill one. ]]
						return glass(
							"UrlBarChrome",
							"control",
							UI.HStack({
								id = "UrlBarBody",
								width = { type = "fill", weight = 1 },
								height = { type = "fill", weight = 1 },
								padding = { top = 4, right = 10, bottom = 4, left = 10 },
								align = "center",
								children = {
									glass(
										"UrlBarFieldPlate",
										"control",
										UI.HStack({
											id = "UrlBarFieldRow",
											width = { type = "fill", weight = 1 },
											height = { type = "fill", weight = 1 },
											padding = { top = 2, right = 8, bottom = 2, left = 8 },
											align = "center",
											children = {
												UI.Text({
													id = "UrlBarField",
													text = COPY.urlBarField,
													textSize = "caption",
													role = "secondary",
													lineLimit = 1,
													shrinkWeight = 1,
												}),
											},
										}),
										{ type = "fill", weight = 1 },
										{ type = "fixed", px = "controlSizes.compact.height" }
									),
								},
							}),
							{ type = "fill", weight = 1 },
							barHeight
						)
					end,
				}),
				UI.When({
					id = "LadderWhen",
					condition = roomForCaption,
					thenView = function()
						return UI.VStack({
							id = "LadderLines",
							gap = 2,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({
									id = "Ladder",
									text = COPY.ladder,
									textSize = "caption",
									role = "secondary",
								}),
							},
						})
					end,
				}),
			},
		})

		result = {
			screen = screen,
			-- EDGE TO EDGE, and the insets come from `platformChrome` above — still
			-- ONE authority, and the only one that can say "the top band is an L".
			-- `deviceSafeContent` would spend the whole band and put the topbar row
			-- out of reach; every other edge is spent identically (pinned in
			-- tests/adaptive.spec.luau).
			--[[ ...AND THE PAINT PROBE'S SAMPLE CLOCK RIDES THE SAME OPTS (NM-H4a).
				`onGeometry` is fed once per frame from `refreshBody` AND from this
				surface's own `onSolved`, and `onSolved` is announced AFTER the
				visibility walk has run — so a sample always reads the writes the solve
				just made rather than last frame's. It is the framework's one declarative
				live-geometry seam, which is why the probe needs no clock of its own and
				no second RunService connection. Every host passes `present` through, so
				the sample runs in the runner, in the sweep and in the shipped showcase. ]]
			present = {
				rootPolicy = "edgeToEdge",
				onGeometry = function(_rectOf: (string) -> any)
					probeSample()
				end,
			},
			steps = {
				openUrlBar = function()
					urlBar:set(true)
					-- the EFFECTIVE loss, not the constant: on a screen shorter than
					-- `URL_BAR_STEAL_PX + HUD_FLOOR_PX` the simulated bar is capped, and a
					-- driver reading this number has to be told what actually happened
					return { urlBar = true, lostPx = urlBarPx(function(r)
						return r:get()
					end) }
				end,
				closeUrlBar = function()
					urlBar:set(false)
					return { urlBar = false, lostPx = 0 }
				end,
				rideStrip = function()
					ride:set(true)
					return { riding = riding:get(), band = (chromeFact:get() :: any).band }
				end,
				leaveStrip = function()
					ride:set(false)
					return { riding = false }
				end,
				-- the two live values a driver can watch move: the round clock's ring
				-- and the health bar. Both are ordinary ProgressViews, so this is the
				-- fixture proving its own indicators are bound rather than painted.
				takeDamage = function()
					health:set(math.max(0, health:get() - 0.25))
					return { health = health:get(), fraction = healthBar.dump().fraction }
				end,
				tickRound = function()
					roundLeft:set(math.max(0, roundLeft:get() - 0.2))
					return { roundLeft = roundLeft:get(), fraction = timerRing.dump().fraction }
				end,
				-- THE RECOVERY ROUTE, DRIVEN (D7.3). A driver opens the sink and reads
				-- back exactly what it is disclosing, so "the content is reachable" is
				-- an observation rather than a claim about a button existing.
				openOverflow = function()
					if overflowHandle == nil then
						openOverflow()
					end
					return { open = overflowOpen:get(), hidden = hiddenNow() }
				end,
				closeOverflow = function()
					closeOverflow()
					return { open = overflowOpen:get() }
				end,
				--[[ THE PROBE, DRIVEN (NM-H4a). The switch and these two are one signal,
					so a scripted sweep and a thumb reach the same state — and `probeSample`
					is exposed because a headless caller has no frame clock to wait for. ]]
				holdProbe = function()
					probeHeld:set(true)
					return { held = true, probe = probeReport }
				end,
				armProbe = function()
					probeHeld:set(false)
					probeSample()
					return { held = probeHeld:get(), probe = probeReport }
				end,
				sampleProbe = function()
					-- the scripted stand-in for the 4Hz tick: a headless caller has no
					-- frame clock, so its own sample is the confirming one
					probeSample(true)
					return { held = probeHeld:get(), probe = probeReport }
				end,
			},
			report = function()
				local dump = state()
				local forms: { [string]: number } = {}
				local dropped: { string } = {}
				if dump ~= nil then
					for _, r in dump.regions do
						forms[r.id] = r.form
						if r.dropped then
							table.insert(dropped, r.id)
						end
					end
				end
				local elided: { string } = {}
				if dump ~= nil then
					for _, r in dump.regions do
						if r.elided then
							table.insert(elided, r.id)
						end
					end
				end
				local chrome = chromeFact:get() :: any
				return {
					urlBar = urlBar:get(),
					arrangement = if dump ~= nil then dump.arrangement else nil,
					fallback = if dump ~= nil then dump.fallback else nil,
					-- the whole point, in one number: a HUD that adapted has ZERO
					-- collisions at every size, and the ones that gave way are named
					collisions = if dump ~= nil then #dump.collisions else nil,
					forms = forms,
					dropped = dropped,
					--[[ AND THE D7 HALF: what this screen has stopped showing, and where
						the rest is. `unshown` is the FRAMEWORK's list, verbatim — a driver
						that re-derived it from `forms` and `dropped` would be re-implementing
						the three rules the seam exists to hold in one place. `elided` beside
						`dropped` is the other half of the same fact. ]]
					elided = elided,
					unshown = if dump ~= nil then dump.unshown else nil,
					overflowOpen = overflowOpen:get(),
					-- ...and the OTHER whole point, in three: what the platform kept,
					-- what it left free, and whether this HUD is using it. The rects
					-- nothing may touch are `chromeRects`; the regression check that
					-- nothing does is tests/hud_composition.spec.luau.
					riding = riding:get(),
					band = chrome.band,
					chromeRects = chrome.rects,
					-- the two bound indicators, so a canary can assert the ring and the
					-- bar are reading their signals rather than sitting at a constant
					roundLeft = timerRing.dump().fraction,
					health = healthBar.dump().fraction,
					--[[ AND THE PAINT PROBE'S OWN ANSWER (NM-H4a), so a scripted device
						sweep reads the same disagreement the plate is showing rather than
						re-deriving it. `held` is the latch; `latches` counts how many times
						it has fired since this fixture mounted, which is the difference
						between "it happened once" and "it happens every rotation". ]]
					--[[ ...AND ALL THREE STATES, plus the rows nobody could hold the engine
						to. `painting + #lost + #unmeasured` is `wanted`, and
						`wanted + #skipped` is `declared` — a driver that reads only
						`painting` can no longer be told a screen is healthy by a
						denominator that quietly moved. `plate` is the readout VERBATIM, so
						a scripted device sweep asserts what a thumb is actually reading
						rather than re-deriving it and agreeing with itself. ]]
					paintProbe = {
						held = probeHeld:get(),
						lost = probeReport.lost,
						unmeasured = probeReport.unmeasured,
						skipped = probeReport.skipped,
						-- ...and WHY a row was skipped, when the answer is a platform fact
						-- rather than the ladder: `Objective` leaves the denominator exactly
						-- when the engine publishes no top band (NM-H4a round 2)
						riding = probeReport.riding,
						band = probeReport.band,
						-- has this probe ever seen the screen healthy? Until it has, a loss
						-- is a screen that has not been built yet, and it may not latch
						everHealthy = probeEverHealthy,
						culprits = probeReport.culprits,
						mismatched = probeReport.mismatched,
						firstPainted = probeReport.firstPainted,
						hiddenUnder = probeReport.hiddenUnder,
						painting = probeReport.painting,
						wanted = probeReport.wanted,
						declared = probeReport.declared,
						expected = probeReport.expected,
						latches = probeReport.latches,
						samples = probeReport.samples,
						engine = probeReport.engine,
						solves = probeReport.solves,
						viewport = probeReport.viewport,
						head = probeReport.head,
						plate = probeReport.plate,
					},
				}
			end,
			dispose = function()
				-- the sink is a SURFACE of this fixture's own, so teardown retires it
				-- before the scope goes: a live anchored panel outliving the screen it
				-- discloses is the leak class this fixture would otherwise ship
				closeOverflow()
				-- ...and so is the probe, for exactly the same reason — its surface AND
				-- the frame clock it rides, which is owned by the presenter and would
				-- otherwise keep sampling a disposed controller
				if unbindProbeTick ~= nil then
					unbindProbeTick()
					unbindProbeTick = nil
				end
				dropProbe()
				for _, view in taskBars do
					view.dispose()
				end
				timerRing.dispose()
				healthBar.dispose()
				scope:dispose()
			end,
		}
		return result
	end,
}
