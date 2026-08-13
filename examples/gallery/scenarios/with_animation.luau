--!strict
--[[ Scenario 'with_animation' — THE MOTION DEMO, AND THE ACCESSIBILITY CLAIM
	IT EXISTS TO TEACH (game-director requirement 2026-08-12;
	docs/plans/swiftui-parity-round2.md §Phase 4 "The motion demo and the global
	reduced-motion toggle").

	At least one showcase surface has to demonstrate animation, and has to let a
	player SEE what reduced motion does to it. This is that surface.

	ONE BUTTON, ONE SPRING, THREE CONSEQUENCES. "Animate" makes exactly one
	`presenter.withAnimation("container", …)` call, and inside it three unrelated
	state changes land together:

	  1. a puck MOVES — its `anchor` flips end to end across its lane;
	  2. a detail panel APPEARS beside it — a `UI.When` branch turning on;
	  3. four chips RE-ORDER — one keyed `ForEach`, its array reversed.

	They share ONE progress spring, which is the behaviour worth showing rather
	than describing: the puck, the displaced chips and everything the panel
	pushed down travel on the same curve and arrive on the same frame. Three
	independent springs would drift apart, and a screenshot cannot tell you they
	did not.

	WHAT `withAnimation` DOES AND DOES NOT OWN, visible here on purpose. The
	appearing panel installs NO record of its own — a structural insert belongs
	to the transition system (`src/render/transitions.luau`), and `withAnimation`
	animates surviving paths only. What flies is the panel's SIBLINGS, which it
	displaced. The solver, meanwhile, is exact and instant throughout: every
	rect is its final rect on the frame the call returns, and only the PAINT
	travels. Hit-testing and focus therefore never chase a moving pixel.

	=== THE CONTROL IS "Full | Reduced", AND NEVER "on/off" ===

	The environment fact is binary (`src/env/environment.luau:47`, `:166-167`);
	the EFFECT is not. `src/motion/motion.luau:31-42` is the authority:

	  · DECORATIVE motion (the default, and what `withAnimation` is) SNAPS. The
	    exact layout already carries every fact and the travel was pure
	    continuity, so deleting the travel deletes nothing.
	  · INFORMATIONAL motion (bars, rings, countdowns) KEEPS RUNNING to the same
	    wall-clock terminus and QUANTIZES its output to 250 ms steps. Nothing is
	    skipped — skipping is how reduced motion would delete information.

	A control labelled "Motion: Off" teaches the opposite of that, so the two
	categories sit SIDE BY SIDE here under the one button: the decorative column
	stops travelling entirely while the informational bar next to it goes on
	filling, in steps you can count. That contrast is the whole point of the
	fixture; a demo that only showed the decorative half would make "reduced
	motion" look like "no motion", which is the misconception this is against.

	=== WHY THE CONTROL IS INLINE, AND WHAT IT IS NOT ===

	An adversarial review (`[SHOWCASE-CHROME]: CONCERNS 16`, 2026-08-12) ruled
	that the showcase chrome carries exactly TWO targets forever — "which demo"
	and "settings" — and that a global motion switch belongs in the settings
	surface, not in a third chip (at 320px the two existing chips already use
	~284 of ~304px; a third needs ninety). That settings surface is a separate,
	larger piece of work and is NOT this fixture. What lives here is the demo
	teaching its own subject, which the same ruling explicitly keeps.

	CONSEQUENCE, AND IT IS DELIBERATE: this control writes the REAL environment
	fact (`env:set("reducedMotion", …)`), because a fixture that faked it would
	prove nothing about the framework — and it RESTORES whatever it found on
	dispose. The persistent, place-wide toggle is the settings surface's job when
	it ships; a demo that silently left every OTHER demo in reduced motion after
	you walked away from it would be a trap, not a setting.

	=== TWO HOSTS MOUNT THIS FILE ===

	  1. THE SCENARIO RUNNER (`scenarios/runner.luau`, workspace attribute
	     `LuauUI_Scenario`): full ctx, `_G.LuauUIScenario` drives the steps below
	     by name.
	  2. THE SHOWCASE DEMO PICKER (`examples/gallery/client/init.client.luau`,
	     `mountDemo`, `kind == "fixture"`): the MINIMAL ctx
	     `{LuauUI, core, env, actionSystem, presenter}`, and NO step ever runs —
	     a player presses the buttons. Everything below therefore has to work
	     with no scripted help, which is why the whole demonstration is reachable
	     from two controls and both of them are four-input reachable Buttons.

	Both hosts advance the motion clock the same way — `presenter.tick(dt)`, bound
	once by `src/client/motion_driver.luau` in the bootstrap, ahead of either
	branch. Nothing in this file owns a clock, a frame connection or a tween.
]]

-- The four chips whose order flips. Short, deliberately: they are the RE-ORDER
-- subject, and a re-order reads as a re-order only when you can still tell the
-- chips apart at a glance on a 320px phone.
local CHIPS = { "Alpha", "Bravo", "Cairo", "Delta" }

-- How wide the "wide enough for two columns" branch needs the viewport to be.
-- Below it the two motion categories stack instead, which keeps them both
-- legible on a narrow phone; the page scrolls either way.
local TWO_COLUMN_MIN_WIDTH = 520

-- The informational ramp's duration. Long enough that the 250 ms reduced-motion
-- quantum produces steps a human can COUNT (about five of them) — a ramp
-- shorter than a couple of quanta would look like a snap and teach the wrong
-- thing about the informational policy.
local CHARGE_SECONDS = 1.4

--[[ EVERY PLAYER-VISIBLE STRING ON THIS SURFACE, in one table, EXPORTED as the
	module's `copy` field — same reason as `card_rail.luau`'s: the localization
	case in `tests/examples_gallery.spec.luau` re-runs the fixture with all of
	them expanded ~1.4x, and a check that cannot reach the strings cannot make
	that claim. Everything here is `policy = "none"` text (§15.3): it must fit,
	wrapping where it has to, and never clip.

	`full` and `reduced` are the segmented control's two option labels, and they
	are here rather than inline for a second reason as well: they are the two
	words this whole fixture argues about. Anyone tempted to shorten them to
	"On"/"Off" has to walk past the header first. ]]
local COPY = {
	title = "withAnimation — one spring, three effects",
	motionLabel = "Motion",
	full = "Full",
	reduced = "Reduced",
	run = "Animate",
	decorative = "Decorative — reduced motion removes the travel",
	informational = "Informational — keeps running, in 250 ms steps",
	-- the two indeterminate shapes (§3.1). Player-facing copy, so it has to
	-- survive ~1.4x pseudo-localization without clipping like every other string
	-- in this file — both labels wrap inside the progress row rather than truncate.
	busyLabel = "No terminus",
	spinnerLabel = "Spinner",
	detailHead = "Detail panel",
	detailBody = "Appearing is the transition system's job; its neighbours fly.",
	chargeLabel = "Charge",
}

return {
	title = "withAnimation + reduced motion",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local LuauUI = ctx.LuauUI
		local UI = LuauUI.UI
		local core = ctx.core
		local env = ctx.env
		local pres = ctx.presenter
		local scope = core:scope("with-animation")
		local clock = pres.motionClock

		-- ===== state ========================================================
		local laneRight = scope:own(core:signal(false)) -- (1) the thing that MOVES
		local detailOpen = scope:own(core:signal(false)) -- (2) the thing that APPEARS
		local chipOrder = scope:own(core:signal(CHIPS)) -- (3) the thing that RE-ORDERS
		local runs = scope:own(core:signal(0))

		-- THE INFORMATIONAL HALF. A glide rather than a spring, because what it
		-- models is a job with a duration — and `kind = "informational"` is the
		-- declaration that reduced motion must not delete it. Under `full` it is a
		-- smooth ramp; under `reduced` it runs the same 1.4 s and publishes in
		-- 250 ms steps (the default quantum, `motion.luau` DEFAULT_QUANTUM).
		local charge = scope:own(clock:glide(0, { duration = CHARGE_SECONDS, kind = "informational" }))
		local chargeTarget = 0

		-- ===== the reduced-motion control ===================================
		-- The value the fixture FOUND, so dispose can put it back (see the header).
		local inheritedReduced = env:get("reducedMotion"):get() == true
		local motionMode = scope:own(core:signal(if inheritedReduced then "reduced" else "full"))

		local function applyMotionMode(value: string)
			-- `motionPolicy` is DERIVED from this fact and refuses a direct write,
			-- which is the right refusal: there is one source of truth and this is it.
			env:set("reducedMotion", value == "reduced")
		end

		local motionPicker = LuauUI.newPicker(LuauUI, core, {
			id = "MotionMode",
			label = COPY.motionLabel,
			-- SEGMENTED, declared rather than adaptive: two short labels shown side
			-- by side ARE the teaching — "Full" and "Reduced" as peers, neither of
			-- them an off switch.
			presentation = "segmented",
			options = {
				{ value = "full", label = COPY.full },
				{ value = "reduced", label = COPY.reduced },
			},
			selected = motionMode,
			-- NO `onChange`. `selected` is a Signal this fixture owns, and the
			-- observe below is the ONE place the environment fact is written — so
			-- the picker press and the scripted `setMotion` step take the identical
			-- route. An `onChange` here would be a second writer for one of them
			-- only, which is how the two paths quietly stop agreeing.
		})

		-- ===== the one animated mutation ====================================
		local function animate()
			-- ONE CALL, THREE CHANGES, ONE SPRING. `withAnimation` needs its own
			-- flush boundary — it refuses to run inside an already-open core
			-- transaction, during a core commit, or nested inside another
			-- `withAnimation` — so this is the mutation site itself, not a wrapper
			-- around one.
			pres.withAnimation("container", function()
				laneRight:set(not laneRight:get())
				detailOpen:set(not detailOpen:get())
				local order = chipOrder:get() :: { string }
				local reversed = {}
				for i = #order, 1, -1 do
					table.insert(reversed, order[i])
				end
				chipOrder:set(reversed)
				runs:set(runs:get() + 1)
			end)
			-- ...and the informational value is aimed OUTSIDE the call, on purpose.
			-- It is not a layout consequence of `fn`, it is a second motion running
			-- beside it — and under reduced motion `setTarget` settles synchronously,
			-- which has no business happening inside another call's transaction.
			chargeTarget = if chargeTarget >= 1 then 0 else 1
			charge:setTarget(chargeTarget)
		end

		-- ===== the two columns ==============================================
		local decorative = UI.VStack({
			id = "Decorative",
			gap = 4,
			width = { type = "fill", weight = 1 },
			children = {
				UI.Text({
					id = "Caption",
					text = COPY.decorative,
					textSize = 12,
					role = "secondary",
				}),
				-- (1) THE MOVE. `anchor` is an arrange-only prop, so flipping it
				-- re-arranges one node without re-measuring it; the rect changes,
				-- which is exactly what `withAnimation` records.
				UI.Anchor({
					id = "Lane",
					surface = "control",
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = 40 },
					children = {
						UI.Box({
							id = "Puck",
							surface = "accent",
							anchor = scope:own(core:memo(function(use)
								return if use(laneRight) then "topRight" else "topLeft"
							end)),
							width = { type = "fixed", px = 40 },
							height = { type = "fill", weight = 1 },
						}),
					},
				}),
				-- (2) THE APPEARANCE. The panel itself belongs to the transition
				-- system and installs no record; what flies is the chips below it,
				-- which it pushes down.
				UI.When({
					id = "Detail",
					condition = detailOpen,
					thenView = function()
						return UI.VStack({
							id = "Panel",
							surface = "raised",
							padding = 8,
							gap = 2,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "Head", text = COPY.detailHead, textSize = 13 }),
								UI.Text({
									id = "Body",
									text = COPY.detailBody,
									textSize = 12,
									role = "secondary",
								}),
							},
						})
					end,
				}),
				-- (3) THE RE-ORDER. One keyed ForEach: the chips keep their identity
				-- (and their paths) while their slots swap, so each one travels to
				-- its new place instead of being destroyed and rebuilt there.
				UI.HStack({
					id = "Chips",
					gap = 4,
					width = { type = "fill", weight = 1 },
					children = {
						UI.ForEach({
							id = "Order",
							items = chipOrder,
							key = function(name: any)
								return name
							end,
							row = function(name: any)
								return UI.VStack({
									id = "Chip",
									surface = "raised",
									padding = 6,
									width = { type = "fill", weight = 1 },
									children = {
										UI.Text({
											id = "Label",
											text = name,
											textSize = 12,
											textAlign = "center",
											lineLimit = 1,
										}),
									},
								})
							end,
						}),
					},
				}),
			},
		})

		local chargeBar = LuauUI.newProgressView(LuauUI, core, {
			id = "Charge",
			label = COPY.chargeLabel,
			value = charge,
			min = 0,
			max = 1,
			showValue = true,
			format = function(value: number): string
				return string.format("%d%%", math.floor(value * 100 + 0.5))
			end,
		})

		-- THE INDETERMINATE PAIR (parity round 2 §3.1). The charge bar above is
		-- informational motion with a KNOWN terminus; these two are informational
		-- motion with NO terminus at all — the only thing on the screen saying
		-- "work is still happening". They belong in this demo precisely because
		-- the reduced-motion picker above is what proves the claim: flip it to
		-- Reduced and the puck stops travelling while these two go on sweeping,
		-- four steps a second instead of sixty. A demo that showed the decorative
		-- half alone would teach that reduced motion means no motion.
		-- ...and each names its OWNER. An indeterminate view runs a motion cycle
		-- for as long as it exists, so `scope` is required exactly as it is for
		-- newAsyncImage's provider handle: this scenario's scope already retires
		-- everything else it built, and now retires these two cycles with it.
		local busyBar = LuauUI.newProgressView(LuauUI, core, {
			id = "Busy",
			label = COPY.busyLabel,
			motionClock = clock,
			scope = scope,
		})
		local busySpinner = LuauUI.newProgressView(LuauUI, core, {
			id = "Working",
			label = COPY.spinnerLabel,
			presentation = "spinner",
			motionClock = clock,
			scope = scope,
		})

		local informational = UI.VStack({
			id = "Informational",
			gap = 4,
			width = { type = "fill", weight = 1 },
			children = {
				UI.Text({
					id = "Caption",
					text = COPY.informational,
					textSize = 12,
					role = "secondary",
				}),
				chargeBar.blueprint,
				busyBar.blueprint,
				busySpinner.blueprint,
			},
		})

		-- ONE declaration, two arrangements (A-AL2): an AdaptiveStack re-solves in
		-- place on a rotation instead of remounting the subtree the way a
		-- VStack/HStack swap behind `UI.When` would — which matters here, because
		-- a remount mid-flight would throw away the very motion under observation.
		local stageAxis = scope:own(core:memo(function(use)
			local vp: any = use(env:get("viewportRect"))
			local w = if type(vp) == "table" and type(vp.w) == "number" then vp.w else 800
			return if w >= TWO_COLUMN_MIN_WIDTH then "x" else "y"
		end))

		local statusLine = scope:own(core:memo(function(use)
			local mode = use(motionMode)
			return `Motion: {mode} · runs: {use(runs)}`
		end))

		local screen = UI.Screen({
			id = "MotionDemo",
			padding = 12,
			gap = 6,
			children = {
				-- THE PAGE SCROLLS. Two motion categories, a picker, a button and a
				-- status line do not fit in the ~200px a 640x320 landscape phone has
				-- left after the showcase reserves its chip strip — and the named
				-- recurring defect in this repo is content that overflows with
				-- nothing to scroll it. A scroll host is the framework's own answer
				-- and costs the wide viewports nothing.
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = 8,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({
							id = "Title",
							text = COPY.title,
							textSize = 18,
						}),
						motionPicker.blueprint,
						UI.Button({
							id = "Run",
							label = COPY.run,
							width = { type = "fill", weight = 1 },
							onActivate = animate,
						}),
						UI.AdaptiveStack({
							id = "Stage",
							axis = stageAxis,
							gap = 8,
							width = { type = "fill", weight = 1 },
							children = { decorative, informational },
						}),
						UI.Text({ id = "Status", text = statusLine, textSize = 12, role = "secondary" }),
					},
				}),
			},
		})

		-- the mode signal and the environment fact are one fact with two readers;
		-- keep them together whichever way the change arrived (a picker press, or
		-- the `setMotion` step below)
		scope:own(core:observe(motionMode, function(value: any)
			applyMotionMode(tostring(value))
		end))
		applyMotionMode(motionMode:get())

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the signals a test drives and the
			-- one it reads back, rather than a re-implementation of them
			motionMode = motionMode,
			laneRight = laneRight,
			detailOpen = detailOpen,
			chipOrder = chipOrder,
			charge = charge,
			animate = animate,

			steps = {
				-- the whole demonstration, as the player's button fires it
				animate = function()
					animate()
					return {
						runs = runs:get(),
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
				-- flight land rather than only its endpoints. There is no second
				-- clock here: this is the same `tick` the bootstrap drives.
				advance = function(_built: any, payload: string?)
					local frames = tonumber(payload or "") or 30
					for _ = 1, math.clamp(math.floor(frames), 1, 600) do
						pres.tick(1 / 60)
					end
					return { charge = charge:get(), records = pres.animationRecordCount() }
				end,
			},

			report = function()
				return {
					motion = motionMode:get(),
					reduced = clock:isReduced(),
					runs = runs:get(),
					records = pres.animationRecordCount(),
					laneRight = laneRight:get(),
					detailOpen = detailOpen:get(),
					chipOrder = table.clone(chipOrder:get() :: { string }),
					charge = charge:get(),
					chargeTarget = chargeTarget,
					busyPhase = busyBar.dump().phase,
					spinnerPhase = busySpinner.dump().phase,
				}
			end,

			dispose = function()
				-- PUT THE WORLD BACK (see the header): the persistent place-wide
				-- toggle is the settings surface's job, not this demo's side effect
				env:set("reducedMotion", inheritedReduced)
				busyBar.dispose()
				busySpinner.dispose()
				chargeBar.dispose()
				scope:dispose()
			end,
		}
	end,
}
