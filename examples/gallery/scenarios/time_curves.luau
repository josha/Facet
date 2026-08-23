--!strict
--[[ Scenario 'time_curves' — TIME-BASED EASING, AND THE ONE THING A SPRING
	CANNOT DO (ADR-0033; fusion-comparison.md §5 G-1).

	`clock:spring` is the framework's default reach and stays that way: it is
	interruptible, it inherits gesture velocity, and its two numbers are a FEEL
	rather than a schedule. What it cannot do is promise a landing time. A spring
	approaches its target asymptotically — `response` is a dial, settle time is
	emergent — so "the cooldown ends in half a second", "the bar empties as the
	audio cue lands" and "over 400 ms, quad ease-out" are not expressible in that
	vocabulary at all. `clock:tween(initial, curveName)` is, and this surface is
	the place a player can watch the difference instead of reading about it.

	FOUR THINGS ARE ON SCREEN, and each one is a claim you can check:

	  1. THE RACE. One press aims a `clock:tween` (0.5 s, linear,
	     `kind = "informational"`) and a `clock:spring` (`decay`, whose response
	     is the same 0.5 s number a designer would have handed it) at the same
	     target. The tween is AT 1.0 when 0.5 s of clock time has elapsed. The
	     spring, measured headlessly at 60 Hz, is at 0.983 on that frame and does
	     not settle until 1.05 s — twice the number it was given. The stopwatch
	     line reports the elapsed seconds and stamps each arrival as it happens
	     (0.52 s against 1.05 s: a settle event fires on the frame AFTER the value
	     lands, so the stamp is one frame behind the arrival it records), so the
	     gap is a MEASUREMENT on the surface rather than an impression.
	  2. THE CURVE GALLERY. The same 400 ms trip under four registered curves,
	     launched on one press. They land on the same frame — that is what a
	     duration means — and they get there along visibly different paths:
	     `back · out` runs past its destination to ~1.10 and returns, `bounce ·
	     out` arrives, rebounds and re-arrives, `quad · out` is half-way at 82 ms
	     where `linear` is half-way at 200 ms. Four springs could not be made to
	     agree on a landing frame at all.
	  3. THE PANEL. `presenter.withAnimation` handed a registered CURVE NAME
	     rather than a motion class (ADR-0033: one dial, two vocabularies). The
	     flight is a stated 450 ms of `quint · inOut`, which is a shape no
	     critically damped spring has — a spring leaves fast and decays, this one
	     starts slow. Everything else about the call is unchanged: the solver is
	     exact and instant, only the paint travels.
	  4. FULL vs REDUCED, the same control `with_animation.luau` carries, for the
	     same reason. Reduced motion is not "no motion": the DECORATIVE halves
	     here (the gallery pucks, the panel flight) place their terminus
	     instantly, while the INFORMATIONAL cooldown keeps running to the same
	     wall-clock terminus with its writes quantized to 250 ms steps you can
	     count. A cooldown that skipped ahead would be deleting the one fact the
	     player needed.

	WHY THE CURVES ARE REGISTERED HERE, defensively. The registry SHIPS EMPTY by
	decision — there is no defensible built-in duration, so registering a curve IS
	the act of choosing one, once, with a name — and an inline
	`{ duration = 0.4, style = "quad" }` at a call site is refused. `build` may run
	more than once (a re-mount, or a headless spec that reset the registry between
	cases), so each registration is guarded by `isRegisteredCurve` rather than
	being unconditional: re-registering is legal and idempotent, but the guard is
	what documents that a second mount is not fighting the first one.

	...AND NO MOTION CLASS IS REGISTERED, deliberately. The registries are
	process-global and the suite runs every spec in one process, so a fixture that
	invented a class name would be editing the vocabulary another spec pins by
	value. The race spring is therefore a BUILT-IN — `decay`, ζ 1.0, response
	0.5 s — which also makes the comparison fairer: it is the shipped class whose
	own number matches the duration the tween was given.

	THE STOPWATCH IS A `clock:glide`, and it owns no frame loop. A linear ramp
	from 0 to N over N seconds IS elapsed time, re-aimable, driven by the same
	`presenter.tick` every other motion on this surface rides. Nothing in this
	file touches `game`, an Instance, `task.delay` or a frame connection.

	TWO HOSTS MOUNT IT, exactly as `with_animation.luau` documents: the scenario
	runner with the full ctx and `_G.FacetScenario` driving the steps below, and
	the showcase demo picker with the MINIMAL ctx `{Facet, core, env,
	actionSystem, presenter}` and NO step ever running. Everything here is
	therefore reachable from four controls, all of them four-input reachable.
]]

-- THE RACE'S NUMBER. One number, spent three ways: the tween's duration, the
-- built-in spring class whose response matches it (`decay`), and the caption
-- that tells the player what was asked for. 0.5 s is also two full reduced-motion
-- quanta, so the informational bar visibly STEPS rather than looking snapped.
local RACE_SECONDS = 0.5
-- How long the stopwatch runs after a press. The spring settles at ≈1.05 s, so
-- 2 s leaves the arrival stamp on screen with room to spare and then stops —
-- a stopwatch that ran forever would be motion with nothing left to report.
local STOPWATCH_SECONDS = 2

-- THE GALLERY'S TRIP. 400 ms is the classic UI handoff figure and it is long
-- enough that `bounce · out`'s rebounds are separable by eye at 60 Hz.
local GALLERY_SECONDS = 0.4

-- THE PANEL'S FLIGHT, and it is deliberately longer than the gallery's: the
-- point of the panel is that a LAYOUT change can be commanded in milliseconds,
-- and a slow-in shape is the readable proof that it is not a spring.
local PANEL_SECONDS = 0.45

--[[ THE PUCK IS THE THEME-OWNED DECORATIVE FLOOR NOW (gap 34, W3-B), and the
	number was never this fixture's to choose. The first cut drew an 18px puck
	in a 24px lane and `tests/overflow_sweep.spec.luau` filed eight findings on
	it immediately: a `control`-chrome package (fantasy-ornate,
	fantasy-parchment, glossy-touch, pixel-quest) wants 28px of border on x and
	20px on y, so an 18px plate cannot spend its own theme's insets and draws
	smaller than the theme expects. Studio Neutral said nothing at all, which
	is exactly why that sweep runs every shipped package. 40 was the size this
	fixture and `with_animation`'s puck each hardened by hand, independently,
	against the same sweep — the two fixtures gap 34 names — and it is now
	`controls.decorative.minimum`, `themes/snapshot.luau`'s theme-owned floor
	for exactly this shape (a non-text decorative box with nothing of its own
	to measure). A METRIC NAME, not a resolved number: the solver resolves it
	against the live snapshot on every solve, so it ten-foot-scales the way the
	raw 40 literal never could.

	...AND THE TRAVEL IS 0.72 OF THE LANE, FOR THE SAME KIND OF REASON. `back · out`
	peaks at 1.0999 (measured, not assumed), so the widest offset this fixture can
	ask for is 0.72 x 1.0999 = 0.79 of the lane — which leaves the puck inside
	its own box at the narrowest viewport swept here, with the OVERSHOOT itself
	still on screen. The overshoot is the half of that curve worth looking at; a
	puck that spent the whole lane would push it off the right edge. ]]
local LANE_SPAN = 0.72
local PUCK_PX = "controls.decorative.minimum"
local LANE_PX = "controls.decorative.minimum"

-- The registered curve NAMES. Namespaced, because the registry is process-wide
-- and a bare "linear" is a name another surface would reasonably want.
local COOLDOWN = "timeCurves.cooldown"
local PANEL = "timeCurves.panel"

--[[ EVERY PLAYER-VISIBLE STRING, in one table and EXPORTED as `copy` — the
	localization case re-runs a fixture with all of them expanded ~1.4x, and a
	check that cannot reach the strings cannot make that claim. Everything here is
	`policy = "none"` text (§15.3): it must fit, wrapping where it has to, and
	never clip, which is why no string on this surface sits inside a fixed-px box.

	The status lines are COMPOSED from these words rather than formatted through a
	template, so a pseudo-localized run expands words instead of eating a `%s`. ]]
local COPY = {
	title = "Time curves — a duration a spring cannot promise",
	motionLabel = "Motion",
	full = "Full",
	reduced = "Reduced",

	raceHead = "Cooldown: on time versus asymptotic",
	raceBody = "One press aims both at the same target. The tween is informational and lands ON its half second; the spring, given the same half-second number, is still approaching when it does.",
	raceRun = "Run the cooldown",
	tweenLabel = "Tween — 0.5 s, linear",
	springLabel = "Spring — decay, 0.5 s response",
	elapsed = "Elapsed",
	tweenShort = "Tween",
	springShort = "Spring",
	arrivedAt = "arrived at",
	approaching = "still approaching",
	idle = "Press the button to start the cooldown.",

	galleryHead = "One 400 ms trip, four curves",
	galleryBody = "Launched together, they land together — the whole difference is how they travel. Under reduced motion these four place their terminus instantly while the cooldown above keeps stepping.",
	galleryRun = "Launch all four",
	laneLinear = "linear — constant speed",
	laneQuad = "quad · out — fast, then settles",
	laneBack = "back · out — runs past, then returns",
	laneBounce = "bounce · out — arrives, rebounds, re-arrives",

	panelHead = "withAnimation, driven by a curve name",
	panelBody = "The same call the spring demo makes, handed a registered curve instead of a class: the puck and the card fly over 450 ms of quint · inOut. A spring leaves fast; this one starts slow.",
	panelRun = "Fly the panel",
	panelCard = "The plate below doubles its height on the same curve, in the same call",
	runs = "Runs",
	records = "Animated paths",
}

-- The gallery's four lanes: a registered curve name, the label that names its
-- shape, and the node id. Data rather than four hand-written subtrees, so the
-- lanes cannot drift apart in anything but the curve they are here to compare.
local LANES = {
	{ id = "Linear", curve = "timeCurves.linear400", label = COPY.laneLinear, style = "linear", direction = "out" },
	{ id = "Quad", curve = "timeCurves.quadOut400", label = COPY.laneQuad, style = "quad", direction = "out" },
	{ id = "Back", curve = "timeCurves.backOut400", label = COPY.laneBack, style = "back", direction = "out" },
	{
		id = "Bounce",
		curve = "timeCurves.bounceOut400",
		label = COPY.laneBounce,
		style = "bounce",
		direction = "out",
	},
}

return {
	title = "Time-based easing",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local env = ctx.env
		local pres = ctx.presenter
		local scope = core:scope("time-curves")
		local clock = pres.motionClock

		-- ===== the curves this surface spends ===============================
		-- Guarded, never unconditional (see the header): a re-mount, or a spec
		-- that reset the registry between cases, must find the same six curves
		-- rather than a refusal from `resolve`.
		local function ensureCurve(name: string, spec: any)
			if not Facet.motion.isRegisteredCurve(name) then
				Facet.motion.registerCurve(name, spec)
			end
		end
		-- LINEAR, and that is a decision rather than an omission: an informational
		-- bar is read as "how much time is left", so its fill has to be
		-- proportional to time. Shaping belongs to the gallery below, where the
		-- shape is the subject.
		ensureCurve(COOLDOWN, { duration = RACE_SECONDS, style = "linear" })
		ensureCurve(PANEL, { duration = PANEL_SECONDS, style = "quint", direction = "inOut" })
		for _, lane in LANES do
			ensureCurve(lane.curve, { duration = GALLERY_SECONDS, style = lane.style, direction = lane.direction })
		end

		-- ===== the race =====================================================
		-- THE STOPWATCH. A linear ramp from 0 to N over N seconds is elapsed time
		-- (see the header); `kind` is left at glide's own "informational" default,
		-- so under reduced motion the readout keeps counting in 250 ms steps
		-- instead of teleporting to the end of the race it is timing.
		local stopwatch = scope:own(clock:glide(0, { duration = STOPWATCH_SECONDS }))
		-- THE INFORMATIONAL HALF. `kind = "informational"` is the declaration that
		-- reduced motion must not delete this — a cooldown that jumped to full
		-- would be telling the player the wait is over when it is not.
		local cooldown = scope:own(clock:tween(0, COOLDOWN, { kind = "informational" }))
		-- ...and the spring it is racing, on a BUILT-IN class whose response is the
		-- same number the curve's duration is.
		local spring = scope:own(clock:spring(0, "decay"))

		-- -1 means "has not arrived on this run". Two signals rather than two
		-- booleans, because the interesting fact is WHEN, and the stamp is read off
		-- the same stopwatch the player is looking at.
		local tweenArrival = scope:own(core:signal(-1))
		local springArrival = scope:own(core:signal(-1))
		local raceRuns = scope:own(core:signal(0))

		-- onSettle fires EXACTLY ONCE per arrival, after the frame's writes are
		-- committed — so these read the terminus, and under reduced motion the
		-- spring's fires synchronously inside `setTarget` with the stopwatch still
		-- reading 0.00, which is precisely the fact that pass is meant to show.
		scope:own(cooldown:onSettle(function()
			tweenArrival:set(stopwatch:get())
		end))
		scope:own(spring:onSettle(function()
			springArrival:set(stopwatch:get())
		end))

		local function runRace()
			-- the stopwatch is zeroed and aimed FIRST, so an arrival that lands in
			-- the same breath (reduced motion places the spring inside `setTarget`)
			-- is stamped against a clock that has already been reset
			stopwatch:snap(0)
			stopwatch:setTarget(STOPWATCH_SECONDS)
			tweenArrival:set(-1)
			springArrival:set(-1)
			raceRuns:set(raceRuns:get() + 1)
			-- `snap` is a placement, not an arrival: it fires no settle event, so
			-- re-running the race cannot stamp an arrival nobody travelled to
			cooldown:snap(0)
			spring:snap(0)
			cooldown:setTarget(1)
			spring:setTarget(1)
		end

		local function percent(value: number): string
			return string.format("%.1f%%", value * 100)
		end
		local function stamp(seconds: number): string
			return string.format("%.2f", seconds) .. "s"
		end
		local function arrivalWord(at: number): string
			return if at >= 0 then `{COPY.arrivedAt} {stamp(at)}` else COPY.approaching
		end

		local raceStatus = scope:own(core:memo(function(use)
			if use(raceRuns) == 0 then
				return COPY.idle
			end
			local e = stamp(use(stopwatch))
			local tw = `{COPY.tweenShort} {percent(use(cooldown))} · {arrivalWord(use(tweenArrival))}`
			local sp = `{COPY.springShort} {percent(use(spring))} · {arrivalWord(use(springArrival))}`
			return `{COPY.elapsed} {e} — {tw} — {sp}`
		end))

		local cooldownBar = Facet.Controls.ProgressView(core, {
			id = "CooldownBar",
			label = COPY.tweenLabel,
			value = cooldown,
			min = 0,
			max = 1,
			showValue = true,
			format = percent,
		})
		local springBar = Facet.Controls.ProgressView(core, {
			id = "SpringBar",
			label = COPY.springLabel,
			value = spring,
			min = 0,
			max = 1,
			showValue = true,
			format = percent,
		})

		-- ===== the curve gallery ============================================
		-- One tween per lane, all DECORATIVE (the default): a puck sliding along a
		-- track carries no information the end state does not, so reduced motion is
		-- right to place it — and doing so beside the informational bar above is
		-- how this surface says that the two policies are different on purpose.
		local lanes: { any } = {}
		local laneValues: { [string]: any } = {}
		for _, lane in LANES do
			local value = scope:own(clock:tween(0, lane.curve))
			laneValues[lane.id] = value
			-- A FRACTION OF THE LANE, spent at ARRANGE (`offsetX` is arrange-only),
			-- so a moving puck re-measures nothing. Clamped at both ends because a
			-- curve is allowed to leave [0, 1] — `back · out` does, by design — and
			-- a negative scale would put the puck outside its own parent.
			local offsetX = scope:own(core:memo(function(use)
				return { scale = math.clamp(use(value), 0, 1.15) * LANE_SPAN }
			end))
			table.insert(
				lanes,
				UI.VStack({
					id = lane.id,
					gap = 2,
					width = UI.fill(),
					children = {
						UI.Text({
							id = "Label",
							text = lane.label,
							textSize = "caption",
							role = "secondary",
						}),
						UI.Anchor({
							id = "Lane",
							surface = "control",
							width = UI.fill(),
							height = { type = "fixed", px = LANE_PX },
							children = {
								-- the lane holds NO text, which is what makes a fixed px
								-- height safe here (the repo's named device-only defect
								-- class is a px box fixed against content that is not)
								UI.Box({
									id = "Puck",
									surface = "accent",
									anchor = "left",
									offsetX = offsetX,
									width = { type = "fixed", px = PUCK_PX },
									height = UI.fill(),
								}),
							},
						}),
					},
				})
			)
		end

		local galleryRuns = scope:own(core:signal(0))
		local function launchGallery()
			galleryRuns:set(galleryRuns:get() + 1)
			-- ONE PRESS, FOUR AIMS, NO COORDINATOR. They land together because they
			-- were given the same duration, not because anything synchronises them —
			-- which is the claim, and the thing four springs could not do.
			for _, lane in LANES do
				local value = laneValues[lane.id]
				value:snap(0)
				value:setTarget(1)
			end
		end

		-- ===== the withAnimation panel ======================================
		local panelRight = scope:own(core:signal(false))
		local panelTall = scope:own(core:signal(false))
		local panelRuns = scope:own(core:signal(0))

		local function flyPanel()
			-- ONE CALL, TWO CHANGES, ONE CURVE. `withAnimation` needs its own flush
			-- boundary — it refuses to run inside an open core transaction, during a
			-- commit, or nested inside another `withAnimation` — so this is the
			-- mutation site itself rather than a wrapper around one. The name it is
			-- handed is a CURVE, and everything downstream of that is unchanged.
			pres.withAnimation(PANEL, function()
				panelRight:set(not panelRight:get())
				panelTall:set(not panelTall:get())
				panelRuns:set(panelRuns:get() + 1)
			end)
		end

		local panelStatus = scope:own(core:memo(function(use)
			return `{COPY.runs} {use(panelRuns)} · {COPY.records} {pres.animationRecordCount()}`
		end))

		-- ===== the reduced-motion control ===================================
		-- Identical in shape to `with_animation.luau`'s, and for the identical
		-- reasons: it writes the REAL environment fact (a faked one would prove
		-- nothing about the framework), it READS the fact back so this control and
		-- the settings surface never disagree on screen, and it RESTORES whatever
		-- it found on dispose so a demo cannot leave every other demo in reduced
		-- motion after the player has walked away from it.
		local inheritedReduced = env:get("reducedMotion"):get() == true
		local motionMode = scope:own(core:signal(if inheritedReduced then "reduced" else "full"))

		local function applyMotionMode(value: string)
			if (env:get("reducedMotion"):get() == true) ~= (value == "reduced") then
				env:set("reducedMotion", value == "reduced")
			end
		end

		scope:own(core:observe(env:get("reducedMotion"), function(value: any)
			local live = if value == true then "reduced" else "full"
			if motionMode:get() ~= live then
				motionMode:set(live)
			end
		end))

		local motionPicker = Facet.Controls.Picker(core, {
			id = "MotionMode",
			label = COPY.motionLabel,
			-- SEGMENTED and declared: "Full" and "Reduced" as peers is the teaching.
			-- A control labelled "Off" would say the opposite of what the
			-- informational bar on this same surface is doing.
			presentation = "segmented",
			options = {
				{ value = "full", label = COPY.full },
				{ value = "reduced", label = COPY.reduced },
			},
			selected = motionMode,
		})

		local screen = UI.Screen({
			id = "TimeCurves",
			padding = 12,
			gap = "tight",
			children = {
				-- THE PAGE SCROLLS. Three demonstrations, a picker, three buttons and
				-- two status lines do not fit in the ~200px a 640x320 landscape phone
				-- has left after the showcase reserves its chip strip, and content
				-- that overflows with nothing to scroll it is this repo's named
				-- recurring defect.
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "control" }),
						motionPicker.blueprint,

						-- (1) THE RACE
						UI.Text({ id = "RaceHead", text = COPY.raceHead, textSize = "label" }),
						UI.Text({
							id = "RaceBody",
							text = COPY.raceBody,
							textSize = "caption",
							role = "secondary",
						}),
						UI.Button({
							id = "RunRace",
							label = COPY.raceRun,
							width = UI.fill(),
							onActivate = runRace,
						}),
						cooldownBar.blueprint,
						springBar.blueprint,
						UI.Text({
							id = "RaceStatus",
							text = raceStatus,
							textSize = "caption",
							role = "secondary",
						}),

						-- (2) THE CURVE GALLERY
						UI.Text({ id = "GalleryHead", text = COPY.galleryHead, textSize = "label" }),
						UI.Text({
							id = "GalleryBody",
							text = COPY.galleryBody,
							textSize = "caption",
							role = "secondary",
						}),
						UI.Button({
							id = "LaunchGallery",
							label = COPY.galleryRun,
							width = UI.fill(),
							onActivate = launchGallery,
						}),
						UI.VStack({
							id = "Lanes",
							gap = "tight",
							width = UI.fill(),
							children = lanes,
						}),

						-- (3) THE withAnimation PANEL
						UI.Text({ id = "PanelHead", text = COPY.panelHead, textSize = "label" }),
						UI.Text({
							id = "PanelBody",
							text = COPY.panelBody,
							textSize = "caption",
							role = "secondary",
						}),
						UI.Button({
							id = "FlyPanel",
							label = COPY.panelRun,
							width = UI.fill(),
							onActivate = flyPanel,
						}),
						-- the thing that MOVES: `anchor` is arrange-only, so flipping it
						-- re-arranges one node without re-measuring it — exactly the rect
						-- change `withAnimation` records and flies
						UI.Anchor({
							id = "PanelLane",
							surface = "control",
							width = UI.fill(),
							height = { type = "fixed", px = 40 },
							children = {
								UI.Box({
									id = "PanelPuck",
									surface = "accent",
									anchor = scope:own(core:memo(function(use)
										return if use(panelRight) then "topRight" else "topLeft"
									end)),
									width = { type = "fixed", px = 36 },
									height = UI.fill(),
								}),
							},
						}),
						UI.Text({
							id = "CardCaption",
							text = COPY.panelCard,
							textSize = "caption",
							role = "secondary",
						}),
						--[[ ...and the thing that GROWS: a box whose SOLVED height
							changes, so the flight has a size delta in it as well as a
							position one. The solver lands the new height exactly and
							instantly, as it always did; what the curve owns is the
							travel between the two.

							IT IS A BARE PLATE, HOLDING NOTHING, and both halves of that
							are the sweep's rulings rather than taste. A `raised` card
							with a pip inside it — `with_animation`'s shape — files three
							findings here at the DEFAULT preference: a `panel`-chrome
							package wants 60px of border on a 40px-high card, and the
							24x20 pip cannot spend the `control` insets either. Those are
							carried on that fixture's ledger rows; a new surface does not
							get to add more, so this one is shaped to be clean instead.
							It holds no string for the older reason: a px height around
							text is the device-only defect class this repo names. ]]
						UI.Box({
							id = "PanelCard",
							surface = "accent",
							width = UI.fill(),
							height = scope:own(core:memo(function(use)
								return { type = "fixed", px = if use(panelTall) then 88 else 40 }
							end)),
						}),
						UI.Text({
							id = "PanelStatus",
							text = panelStatus,
							textSize = "caption",
							role = "secondary",
						}),
					},
				}),
			},
		})

		-- one fact, two readers: keep the picker's signal and the environment fact
		-- together whichever way the change arrived (a press, or the `setMotion`
		-- step below)
		scope:own(core:observe(motionMode, function(value: any)
			applyMotionMode(tostring(value))
		end))
		applyMotionMode(motionMode:get())

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the values a spec drives and reads
			-- back, rather than a re-implementation of them
			motionMode = motionMode,
			stopwatch = stopwatch,
			cooldown = cooldown,
			spring = spring,
			laneValues = laneValues,
			panelRight = panelRight,
			panelTall = panelTall,
			runRace = runRace,
			launchGallery = launchGallery,
			flyPanel = flyPanel,

			steps = {
				race = function()
					runRace()
					return { runs = raceRuns:get(), reduced = clock:isReduced() }
				end,
				gallery = function()
					launchGallery()
					return { runs = galleryRuns:get(), reduced = clock:isReduced() }
				end,
				panel = function()
					flyPanel()
					return {
						runs = panelRuns:get(),
						reduced = clock:isReduced(),
						records = pres.animationRecordCount(),
					}
				end,
				setMotion = function(_built: any, payload: string?)
					local value = if payload == "reduced" then "reduced" else "full"
					motionMode:set(value)
					return { motion = value, reduced = clock:isReduced() }
				end,
				-- step the presenter's own clock, so a Studio driver can watch the
				-- flights land rather than only their endpoints. There is no second
				-- clock here: this is the same `tick` the bootstrap drives.
				advance = function(_built: any, payload: string?)
					local frames = tonumber(payload or "") or 30
					for _ = 1, math.clamp(math.floor(frames), 1, 600) do
						pres.tick(1 / 60)
					end
					return {
						elapsed = stopwatch:get(),
						cooldown = cooldown:get(),
						spring = spring:get(),
					}
				end,
			},

			report = function()
				local travel: { [string]: number } = {}
				for id, value in laneValues do
					travel[id] = value:get()
				end
				return {
					motion = motionMode:get(),
					reduced = clock:isReduced(),
					elapsed = stopwatch:get(),
					raceRuns = raceRuns:get(),
					cooldown = cooldown:get(),
					cooldownSettled = cooldown:isSettled(),
					cooldownKind = cooldown:motionKind(),
					spring = spring:get(),
					springSettled = spring:isSettled(),
					tweenArrival = tweenArrival:get(),
					springArrival = springArrival:get(),
					galleryRuns = galleryRuns:get(),
					travel = travel,
					panelRuns = panelRuns:get(),
					panelRight = panelRight:get(),
					panelTall = panelTall:get(),
					records = pres.animationRecordCount(),
					-- the registry this surface depends on, so a report says whether
					-- the six curves it cites are actually there
					curves = Facet.motion.curveNames(),
				}
			end,

			dispose = function()
				-- PUT THE WORLD BACK: the persistent place-wide toggle is the settings
				-- surface's job, not this demo's side effect
				env:set("reducedMotion", inheritedReduced)
				cooldownBar.dispose()
				springBar.dispose()
				motionPicker.dispose()
				scope:dispose()
			end,
		}
	end,
}
