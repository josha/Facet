--!strict
-- Sipworks proof metrics — THE ONE PLACE A NUMBER LIVES (spec p3-sipworks §4).
--
-- The spec states these as dotted theme-metric names (`metrics.sip.rowArt`).
-- They cannot be: `snapshot.isMetricPath` validates a metric NAME against the
-- neutral snapshot, so a name no shipped package declares is a construction
-- error — and the proof must mount under Studio Neutral AND Fantasy Parchment
-- with zero source edits (build-decisions, proof obligation 4). So the table
-- keeps the spec's role — one sanctioned definition site, cited by name
-- everywhere else — as proof-owned data instead of theme data. Nothing outside
-- this file writes a raw dimension number.
--
-- Everything that CAN be theme-owned still is: spacing steps ("xs".."xl"),
-- radii, target sizes, typography roles and the hairline are named, never
-- numbered, so a package swap still moves them.

local metrics = {}

-- §4's table, verbatim
metrics.rowArt = 60 -- list-row thumbnail (square)
metrics.tileArt = 96 -- botanical tile art
metrics.cardW = 360 -- botanical card
metrics.cardH = 460
metrics.headerArtW = 220 -- wide-header image
metrics.headerArtH = 250
metrics.listPaneMin = 320 -- regular/wide list pane
metrics.listPaneMax = 420
metrics.seal = 44 -- stamp-seal cell
metrics.sealCompact = 32
metrics.orderCard = 300 -- order-placed flip disc (1:1)
metrics.ctaBand = 64 -- bottom action band height

-- Derived from the table above rather than stated again.
--
-- `headerTextMin` is what makes the wide header candidate LOSE on a phone: a
-- `fill` child inside a `ViewThatFits` candidate always fits (the candidate
-- takes whatever it is offered), so the wide card states a real width for its
-- text column instead. 260 + 220 + two `l` insets measures ≈ 520, which is
-- wider than any compact viewport and narrower than a tablet pane. It is a
-- FIXED width and not a band on purpose: with a `minMax` the candidate measured
-- its height at one width and was arranged at another, and the card ended 96px
-- shorter than the text inside it (the solver's overflow diagnostic, desktop).
metrics.headerTextMin = 260
-- THE ARRANGEMENT FLIP, and why these two numbers are what they are.
--
-- A group's `minWidth` is what makes the sidebar arrangement illegal on a phone
-- (rule 2), and the flip therefore lands at `navRailMin + laneGap +
-- contentLaneMin`. But a group minWidth is global to the DECLARATION, not to an
-- arrangement — so the column fallback is judged against the same numbers, and
-- a content minimum wider than the narrowest supported viewport makes even the
-- fallback illegal ("no declared arrangement is legal in 320x640", which the
-- solver's own diagnostic reported at the first sweep).
--
-- So: `contentLaneMin` stays under the narrowest device row (320) and the rail
-- carries the rest of the threshold. 260 + 12 + 300 = 572 — measured, not
-- guessed, and close under the framework's own compact/regular boundary.
metrics.contentLaneMin = 300
metrics.navRailMin = 260
-- ...and the rail's CAP. A hug lane is as wide as its content, so at a 1.4x
-- locale and the largest text preference the rail grew past 400px and squeezed
-- the two panes beside it until the recipe pane was 114px narrower than its own
-- row. A rail is a rail: it states its band and the labels adapt inside it.
metrics.navRailMax = 300
-- THE TWO-PANE THRESHOLD, and why it is not the compact boundary.
--
-- The list pane declares a 320px floor and the detail pane needs a readable
-- column beside it, so a two-pane split costs ~640px of CONTENT lane — and in
-- the sidebar arrangement the rail has already taken 260 of the window. Below
-- this width the section is a single list and the detail is a pushed surface,
-- which is the same answer a phone gets. Measured against the solver's own
-- overflow diagnostic at 600x800 and 640x320, where a split lane overflowed by
-- 28px and 5px respectively.
metrics.twoPaneMin = 900
-- the gathered check's own column: a `Toggle` draws its label on ONE line, so a
-- long localized label ("Gathered: Lemongrass", 1.4x) pushed the recipe row 92px
-- past its box. The column is capped and the label declares `disclose`, which is
-- the framework's own answer for bounded identity text.
metrics.gatherToggle = 96
-- the ambient steam backdrop (§12): eight wisps, and how far one drifts
metrics.wispCount = 8
metrics.wispSize = 18
metrics.wispTravel = 0.16 -- a fraction of the backdrop's height

--[[ …AND IT FOLLOWS THE TEN-FOOT LADDER (wave TEN-FOOT, ADAPT-8, 2026-08-20).
	The band is a cap on a CONTROL, and at ten-foot the control inside it grew:
	`controls.toggle.trackWidth` and `trackInset` scale with the rest of the metric
	ladder, so the toggle's own chrome reserved 108px of a 96px column and the
	gathered label had exactly nothing to draw in — measured by the solver on all
	four ten-foot rows of `tests/reference/sipworks_spec`.

	`metricScale` is the factor the snapshot publishes for precisely this: a
	consumer that must PREDICT geometry rather than resolve a metric name. (A name
	would be better — a dim's `px` takes one and re-resolves it every solve — but
	no single theme metric means "this band", and 96 is the sum of three.) The
	near answer is byte-identical, because the factor is 1 at every near display. ]]
function metrics.gatherToggleAt(app: any): number
	local env = if type(app) == "table" then app.env else nil
	if env == nil then
		return metrics.gatherToggle
	end
	local snap: any = env:get("themeMetrics"):get()
	local scale = if type(snap) == "table" and type(snap.metricScale) == "number" then snap.metricScale else 1
	return metrics.gatherToggle * scale
end

function metrics.fixed(px: number): { [string]: any }
	return { type = "fixed", px = px }
end

metrics.fill = { type = "fill", weight = 1 }

function metrics.aspect(ratio: number): { [string]: any }
	return { type = "aspect", ratio = ratio }
end

function metrics.minMax(min: number, preferred: number, max: number): { [string]: any }
	return { type = "minMax", min = min, preferred = preferred, max = max }
end

-- A FLOOR WITH NO PREFERENCE: at least `min`, otherwise as tall as the content
-- needs. This is the shape a band takes when the THEME owns the height of what
-- stands in it — a `control`'s size plus whatever content insets its chrome
-- reserves (Fantasy Parchment reserves 20px per side, and a band pinned to the
-- spec's 64px left the CTA's label a 12px box).
function metrics.atLeast(min: number, max: number): { [string]: any }
	return { type = "minMax", min = min, max = max }
end

function metrics.percent(fraction: number): { [string]: any }
	return { type = "percent", fraction = fraction }
end

-- A CAP, NOT A SIZE. Every fixed card box in §4 is a DESKTOP size, and a fixed
-- box is the defect class a device pass finds: the botanical card asked for
-- 360x460 on a 320x640 phone and painted 40px outside the viewport (found by
-- `controller.diagnostics()`, not by a screenshot). These boxes take a share of
-- what they were given and stop growing at the spec's number.
function metrics.percentMax(fraction: number, max: number): { [string]: any }
	return { type = "percent", fraction = fraction, max = max }
end

return metrics
