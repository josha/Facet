--!strict
--[[ Scenario 'with_animation' — THE MOTION DEMO, AND THE ACCESSIBILITY CLAIM
	IT EXISTS TO TEACH (game-director requirement 2026-08-12;
	docs/plans/parity-round2.md §Phase 4 "The motion demo and the global
	reduced-motion toggle").

	At least one showcase surface has to demonstrate animation, and has to let a
	player SEE what reduced motion does to it. This is that surface.

	ONE BUTTON, ONE SPRING, FOUR CONSEQUENCES. "Animate" makes exactly one
	`presenter.withAnimation("container", …)` call, and inside it four unrelated
	state changes land together:

	  1. a puck MOVES — its `anchor` flips end to end across its lane;
	  2. a card GROWS — its height doubles, and the box travels to the new size
	     instead of jumping to it;
	  3. a detail panel APPEARS beside it — a `UI.When` branch turning on;
	  4. four chips RE-ORDER — one keyed `ForEach`, its array reversed.

	THE CARD IS THE NEWEST ONE AND IT TEACHES THE ODD HALF (2026-08-14). Until
	round 3 `withAnimation` moved things and SNAPPED their size, so a card like
	this one appeared at its final height while everything under it slid — the
	one thing on screen that did not travel. It now travels, and the card is
	built to show the rule that makes it safe: its label is pinned to the TOP,
	and it does not move while the box grows underneath it. A position delta
	accumulates down a subtree, a size delta does not, and that is why the words
	inside a growing box do not stretch with it.

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
	~284 of ~304px; a third needs ninety). THAT SETTINGS SURFACE NOW SHIPS
	(`examples/gallery/client/settings_panel.luau`, parity round 3 item E). What
	lives here is the demo teaching its own subject, which the same ruling
	explicitly keeps.

	CONSEQUENCE, AND IT IS DELIBERATE: this control writes the REAL environment
	fact (`env:set("reducedMotion", …)`), because a fixture that faked it would
	prove nothing about the framework — and it RESTORES whatever it found on
	dispose, because a demo that silently left every OTHER demo in reduced motion
	after you walked away from it would be a trap, not a setting.

	AND IT NOW READS THE FACT BACK, so the two controls compose instead of
	disagreeing: one fact, two editors, this one a LOCAL OVERRIDE for as long as
	this demo is on screen and the settings one the place-wide PREFERENCE the host
	re-applies after every demo mount. The full rule is written beside the
	observer in `build` below.

	=== TWO HOSTS MOUNT THIS FILE ===

	  1. THE SCENARIO RUNNER (`scenarios/runner.luau`, workspace attribute
	     `Facet_Scenario`): full ctx, `_G.FacetScenario` drives the steps below
	     by name.
	  2. THE SHOWCASE DEMO PICKER (`examples/gallery/client/init.client.luau`,
	     `mountDemo`, `kind == "fixture"`): the MINIMAL ctx
	     `{Facet, core, env, actionSystem, presenter}`, and NO step ever runs —
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
	title = "withAnimation — one spring, five effects",
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
	-- (2) THE GROW. Player-facing, so both survive ~1.4x pseudo-localization by
	-- wrapping inside the card rather than truncating — the card is deliberately
	-- the narrow column's full width so there is room for the expansion.
	cardLabel = "The card below grows — the pip inside it does not",
	-- (5) THE PAINT. Player-facing, and it names all three effects because the
	-- point is that they are ONE call: a reader who sees only "fades" will not
	-- look for the turn.
	effectsLabel = "The badge fades, shrinks and turns — same spring",
	-- (5b) THE WRAP. A leaf cannot take an `opacity` — it would have to write a
	-- transparency the theme's stylesheet owns, and one such write makes the
	-- sheet's value unreadable for good (ADR-0029). The spelling that works is one
	-- fade group around the subtree, and this row is it, on the same spring.
	-- Player-facing, so it wraps rather than truncates at ~1.4x.
	wrapLabel = "A label cannot fade itself — wrap it, and the group fades",
	wrapText = "Faded",
	wrapButton = "Locked",
}

return {
	title = "withAnimation + reduced motion",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local env = ctx.env
		local pres = ctx.presenter
		local scope = core:scope("with-animation")
		local clock = pres.motionClock

		-- ===== state ========================================================
		local laneRight = scope:own(core:signal(false)) -- (1) the thing that MOVES
		local cardTall = scope:own(core:signal(false)) -- (2) the thing that GROWS
		local detailOpen = scope:own(core:signal(false)) -- (3) the thing that APPEARS
		local chipOrder = scope:own(core:signal(CHIPS)) -- (4) the thing that RE-ORDERS
		local runs = scope:own(core:signal(0))
		-- (5) THE PAINT, shared by the badge and the wrapped row below it. ONE memo
		-- rather than two identical ones, because the two rows arriving at the same
		-- alpha on the same frame is the thing they are together to show: the badge
		-- is a node that CAN carry an opacity, the row is a subtree that cannot and
		-- is wrapped instead, and both are the same authored term on the same spring.
		local paintOpacity = scope:own(core:memo(function(use)
			return if use(laneRight) then 0.3 else 1
		end))

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
			if (env:get("reducedMotion"):get() == true) ~= (value == "reduced") then
				env:set("reducedMotion", value == "reduced")
			end
		end

		--[[ ...AND IT READS THE FACT BACK, which is new (parity round 3 item E).

			The place now carries a PERSISTENT motion control in its settings surface
			(`examples/gallery/client/settings_panel.luau`), and both write this ONE
			fact. Without this observer the two would disagree on screen the moment the
			player used the other one: open Settings over this demo, flip to Reduced,
			and this fixture's own segmented control would still read "Full" while the
			puck beside it had stopped travelling.

			So the composition is ONE FACT, TWO EDITORS, and flipping either moves both
			controls in the same frame. This demo's control remains a LOCAL OVERRIDE:
			the restore-on-dispose below is unchanged and still stops a demo leaving
			every other demo in reduced motion, and the showcase host re-applies the
			place-wide PREFERENCE after every demo mount, so leaving this demo returns
			the place to the setting whichever control was touched last. ]]
		scope:own(core:observe(env:get("reducedMotion"), function(value: any)
			local live = if value == true then "reduced" else "full"
			if motionMode:get() ~= live then
				motionMode:set(live)
			end
		end))

		local motionPicker = Facet.Controls.Picker(core, {
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
				cardTall:set(not cardTall:get())
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
				--[[ (2) THE GROW — the consequence round 3 added, and the one this
					fixture exists to make legible.

					`height` is bound to a memo, so flipping `cardTall` changes this
					node's SOLVED rect. The solver lands it exactly and instantly, as
					it always did; what is new is that the painted box now travels
					from the old height to the new one on the same spring the puck
					and the chips are riding — so the card finishes growing on the
					very frame the chips finish sliding.

					THE PIP IS PINNED TO THE TOP ON PURPOSE, AND IT IS NOT TEXT.
					A size delta belongs to ONE node and does not accumulate into its
					children, so the pip sits still at its own 24x20 while the box
					opens underneath it. If it crept downward, or stretched, that rule
					would have broken — and you can see that here without a debugger.

					IT HOLDS NO STRING, AND THAT IS THE POINT OF THE SHAPE. A fixed px
					height around text is this repo's named device-only defect class:
					the box is pinned and the content is not, so the Largest text
					preference or a 1.4x localized string overflows a box that looked
					fine on the author's desktop. The first draft of this card put two
					labels inside it and the sweep caught exactly that (9px past its
					own box at 320x640, +0 offset, before any text growth at all). The
					caption above carries the words; the box carries the motion. ]]
				UI.Text({
					id = "CardCaption",
					text = COPY.cardLabel,
					textSize = 12,
					role = "secondary",
				}),
				UI.VStack({
					id = "Card",
					surface = "raised",
					padding = 8,
					gap = 2,
					width = { type = "fill", weight = 1 },
					height = scope:own(core:memo(function(use)
						return { type = "fixed", px = if use(cardTall) then 76 else 40 }
					end)),
					children = {
						UI.Box({
							id = "Pip",
							surface = "accent",
							width = { type = "fixed", px = 24 },
							height = { type = "fixed", px = 20 },
						}),
					},
				}),
				--[[ (5) THE PAINT — opacity, scale and rotation, authored (ADR-0026).

					These are the consequence the director asked for: *"should opacity,
					transparency, and scale get owned/influenced by facet? it seems
					like we should be able to animate those."* Until this round the
					only values `withAnimation` could interpolate were the solver's
					four rect numbers, because they were the only values a commit
					produced — the presentation channel had no authored prop in it at
					all. Now it has three, and this badge binds every one of them to
					the same `laneRight` signal the puck above is riding.

					SO THE THING TO WATCH IS NOT THE FADE, IT IS THE SYNCHRONY. The
					badge's alpha, its size and its angle are all at the same fraction
					of their journey as the puck's position and the card's height, on
					every frame, because there is one progress spring for the whole
					call. Four independent tweens would look almost right and drift.

					AND THE BOX DOES NOT MOVE. Scale and rotation are paint: the
					solver never sees them, so the badge's layout box, its tap target
					and its focus position are the unrotated, unscaled ones. That is
					the standing rule for a paint-only scale or rotation, and it is why
					the lane below it does not reflow when the badge turns.

					THE BADGE IS 40px BECAUSE THE SWEEP SAID SO. The first draft made
					it 28, and `tests/overflow_sweep.spec.luau` filed 40 findings on it
					at once: a `control`-chrome package (fantasy-ornate, glossy-touch,
					pixel-quest) wants 28-32px of border on each axis, so a 28px plate
					could not spend its own theme's insets and drew smaller than the
					theme expects. Studio Neutral said nothing, which is the whole
					reason that sweep runs every shipped package. 40px is the size the
					puck above already proves.

					The lane is 60px for that 40px badge: a square turned 45 degrees is
					56.6px across its diagonal, and paint leaving its own plate would be
					a defect rather than a demo. Scale stays at or below 1 for the same
					reason — this fixture shrinks rather than grows.

					Under REDUCED MOTION all three land instantly at their
					destination, exactly as the puck's travel does: the flight is
					decorative, the end state carries every fact, and a scale is NOT
					substituted by a cross-fade (deleting the zoom is strictly less
					motion than replacing it with another animation — ADR-0026
					Decision 8). ]]
				UI.Text({
					id = "EffectsCaption",
					text = COPY.effectsLabel,
					textSize = 12,
					role = "secondary",
				}),
				UI.Anchor({
					id = "Effects",
					surface = "control",
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = 60 },
					children = {
						UI.Box({
							id = "Badge",
							surface = "accent",
							anchor = "center",
							width = { type = "fixed", px = 40 },
							height = { type = "fixed", px = 40 },
							opacity = paintOpacity,
							scale = scope:own(core:memo(function(use)
								return if use(laneRight) then 0.6 else 1
							end)),
							rotation = scope:own(core:memo(function(use)
								return if use(laneRight) then 45 else 0
							end)),
						}),
					},
				}),
				--[[ (5b) THE WRAP — the spelling for everything the badge is not
					(ADR-0029, director round 2026-08-15).

					`opacity` is offered on `Box` and `ZStack` and REFUSED by name
					everywhere else, and the badge above is a Box, so it gets to
					declare its own. The row here is a label and a control, and
					neither can: a leaf fade would have to write `TextTransparency`
					or `BackgroundTransparency`, which the theme's native stylesheet
					owns. That is not a lost frame — measured in Studio, one explicit
					write makes `GetStyled` return the write instead of the rule's
					value from then on, so the sheet's own number stops being
					readable and the disabled dimming dies with it.

					SO THE FADE MOVES UP ONE NODE and the leaves stay untouched. The
					`ZStack` is a real `CanvasGroup`, its `GroupTransparency` is the
					one alpha property no rule owns, and everything inside it is
					composited at that alpha by the engine — which is also the declarative
					answer, and why `compositingGroup()` exists there.

					THE LOCKED BUTTON IS THE POINT, not decoration. It is disabled,
					so the sheet's `:NonInteractable` rule is painting its dimming —
					and it goes on doing that underneath the group fade, because
					nothing here ever wrote its transparency. Measured live on this
					same framework build: with the group at `GroupTransparency` 0.5,
					the button's `GetStyled("TextTransparency")` still moved 0.4 ->
					0 -> 0.4 as it was disabled, enabled and disabled again, with its
					raw property at 0 the whole time.

					It rides `paintOpacity`, the badge's own memo, so the two rows
					reach the same alpha on the same frame — one authored term, one
					spring, two nodes that had to spell it differently. ]]
				UI.Text({
					id = "WrapCaption",
					text = COPY.wrapLabel,
					textSize = 12,
					role = "secondary",
				}),
				--[[ IT HUGS AND IT WRAPS, and the sweep is why (2026-08-15). The first
					draft copied the badge's shape — a fixed 60px `UI.Anchor` lane with
					a centred, content-sized group inside it — and
					`tests/overflow_sweep.spec.luau` filed 16 findings at once: at
					320x640 with the +14 text preference, a `control`-chrome package
					(classic-desktop, compact-pointer, fantasy-ornate, glossy-touch)
					needs 570-620px for a label beside a button, and nothing clips a
					ZStack, so the row painted over its neighbours. The badge can hold
					a fixed lane because a 40px square is 40px in every package; a row
					of TEXT is not. So this one fills the column, wraps to a second
					line when it must, and takes its height from its content. ]]
				UI.ZStack({
					id = "Wrapped",
					surface = "control",
					padding = 8,
					width = { type = "fill", weight = 1 },
					opacity = paintOpacity,
					children = {
						UI.HStack({
							id = "Row",
							gap = 8,
							align = "center",
							wrap = true,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "Label", text = COPY.wrapText, textSize = 13 }),
								UI.Button({ id = "Locked", label = COPY.wrapButton, enabled = false }),
							},
						}),
					},
				}),
				-- (3) THE APPEARANCE. The panel itself belongs to the transition
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
				-- (4) THE RE-ORDER. One keyed ForEach: the chips keep their identity
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

		local chargeBar = Facet.Controls.ProgressView(core, {
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
		local busyBar = Facet.Controls.ProgressView(core, {
			id = "Busy",
			label = COPY.busyLabel,
			motionClock = clock,
			scope = scope,
		})
		local busySpinner = Facet.Controls.ProgressView(core, {
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
			cardTall = cardTall,
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
					cardTall = cardTall:get(),
					detailOpen = detailOpen:get(),
					chipOrder = table.clone(chipOrder:get() :: { string }),
					-- the authored presentation triple this run is aimed at, so a
					-- headless spec reads the DECLARED destination rather than
					-- re-deriving it (ADR-0026)
					badgeOpacity = if laneRight:get() then 0.3 else 1,
					badgeScale = if laneRight:get() then 0.6 else 1,
					badgeRotation = if laneRight:get() then 45 else 0,
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
