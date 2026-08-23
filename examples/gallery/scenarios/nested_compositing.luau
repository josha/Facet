--!strict
--[[ Scenario 'nested_compositing' — TWO THINGS A REAL PARENT BUYS (ADR-0032).

	ADR-0032 switches Facet from a flat instance tree to a nested one: a
	container registered as a real engine parent (a "host") lets the ENGINE
	compose a presentation term for its whole subtree instead of the framework
	computing it per descendant. Two terms already prove that live this round —
	`docs/adr/ADR-0032-nested-instance-tree.md` Decision 4 and
	`artifacts/nested-instance-tree/live-probes.md` §1/§3 — and this fixture is
	the first surface a player can select that puts BOTH on screen at once:

	  (a) GROUP OPACITY. `canvasGroup`/`opacity` were already the flat tree's one
	      documented exception (ADR-0022 D2) — `canvas_group.luau` is the
	      existing picker entry for it. After ADR-0032 the exception becomes the
	      rule, so this fixture restates the same tell on a SMALLER, differently
	      shaped pair (two plates offset on top of each other rather than three
	      concentric ones), to keep it legible next to the capability that is new
	      this round rather than duplicating that fixture's screen.
	  (b) A CONTAINER CARRYING ITS CONTENTS. Measured live (probes §1/§3): a
	      plain `Frame` host with authored `scale`/`rotation` composes BOTH terms
	      for its subtree — no CanvasGroup, no buffer, and the descendant's own
	      `Rotation`/`UIScale` stay framework-untouched (Decision 5). Before this
	      round a rotated container left its contents sitting bolt upright beside
	      it; this fixture puts the fixed shape and the still-broken shape on
	      screen together, so the difference reads without a caption.

	WHY A PLATE-PLUS-MARKER PAIR, NOT A SINGLE ROTATED BOX. A single leaf rotating
	in place looks identical whether or not anything "carries" it — rotation
	about one's own centre needs no parent. The tell needs a SECOND element whose
	POSITION is only correct if a shared pivot moved it there: `Marker` sits at
	the `Plate`'s far corner, so turning the pair as a rigid group keeps the
	marker glued to that corner, while giving the marker the SAME rotation/scale
	as a bare leaf (no shared container) spins it in place on top of a `Plate`
	that never moves — visibly the container-detachment defect Decision 4 closes.
	Both panels are driven by the SAME two signals, so every frame is an
	apples-to-apples comparison rather than two demos that happen to agree at
	rest.

	CONTROLS. A real `UI.Slider` drives the fade continuously (the task asks for
	"a slider or a toggle" on the opacity half specifically, and a slider makes
	the double-darken patch sweep through its worst case rather than jumping
	between a few stops); a `UI.Button` toggle turns the carry pair, because a
	discrete on/off reads the "before/after" contrast (0°/1x vs 30°/1.5x, the
	exact pair ADR-0032's own live probe measured) more legibly than a continuum
	would for a two-element shape.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT, same discipline as
	`canvas_group.luau`: every cluster is a small fixed-px shape (deterministic
	corner alignment needs a known frame — see `cluster()` below) sitting inside
	a page that scrolls, and the two panel pairs sit in `AdaptiveStack`s that
	stack to a column on a narrow phone.

	TWO HOSTS MOUNT THIS FILE, same pair `canvas_group.luau` and `branch_scope.luau`
	document: the scenario runner drives `steps` by name, and the showcase demo
	picker mounts it with a minimal ctx and no step ever runs — every control
	here is an ordinary Slider/Button, so a player drives all of it by hand.

	WHAT THIS FIXTURE DOES NOT CLAIM. It is built and swept headlessly. Whether a
	descendant's `AbsoluteRotation`/`AbsoluteSize` actually compose on the real
	engine is a Studio/device claim already recorded in `live-probes.md` §1/§3 —
	this fixture puts the SAME shapes a player can select on the SAME picker the
	rest of the catalogue uses; a fresh Studio capture of THIS surface (not just
	the probe) is still owed before this round's device pass closes.
]]

-- the fade's resting stop: low enough that a doubled overlap is unmistakable,
-- high enough that both plates are still on screen (the same reasoning
-- `canvas_group.luau`'s STOPS[3] = 0.4 documents for its own resting value)
local FADE_DEFAULT = 40

-- the "turned" pose, verbatim the pair ADR-0032's own live probe measured
-- (`live-probes.md` §1: "carry `Rotation = 30` and a `UIScale` of `1.5`"),
-- so this fixture's default state is the exact case the ADR's numbers describe
local TURN_ROTATION = 30
local TURN_SCALE = 1.5

-- Two plates, offset rather than concentric (canvas_group.luau's three plates
-- ARE concentric): a diagonal offset makes the doubled-overlap patch its own
-- clearly bordered rectangle in the middle, rather than a shape wholly covered
-- by the shape in front of it — a second way to see the same tell.
local BACK = { id = "Back", w = 120, h = 74, role = "accent" }
local FRONT = { id = "Front", w = 64, h = 40, role = "danger" }

-- the carry-pair cluster's frame and its two shapes. FIXED, not `fill`: the
-- corner alignment below (`alignH = "end", alignV = "start"`) only reads as "the
-- marker sits at the plate's far corner" against a KNOWN frame — a `fill` frame
-- would put the marker at a different screen offset on every viewport, which is
-- not what this fixture is measuring.
local CLUSTER_W, CLUSTER_H = 100, 70
--[[ THE SLOT THE TURNED PAIR NEEDS, AND WHY THIS DEMO HAS TO RESERVE IT ITSELF.

	`scale` is PAINT-ONLY by definition — "paint-only uniform scale about the node's
	centre" — so the solver reserves a node's UNSCALED box and the engine draws the
	scaled one. That is correct and deliberate: a paint term that moved layout would
	re-solve the page every frame of an animation. It also means a container that
	scales overflows its own slot, and the parent has to leave room.

	FOUND ON A DEVICE (director, 2026-08-17): this cluster reserved 100x70 and, at
	1.5x and 30 degrees, painted a 182x166 footprint into it — over the caption above
	and past the panel's left edge. The screenshots read as "the first press is
	broken"; it was the opposite, the press was RIGHT and the box was too small. (The
	state that looked correct was a separate defect that dropped the scale entirely —
	`screen_presentation`'s UIScale corpse, fixed the same day.)

	So the footprint is COMPUTED from the same three constants that produce it,
	rather than pinned as a number somebody has to remember to update: change the
	scale or the angle and the reservation follows. ]]
-- ...plus a few pixels of slack. The exact footprint at 1.5x / 30 degrees is
-- 182.40 x 165.93, and reserving the ceiling of that centres a 165.93 box inside a
-- 166 one — 0.03px a side, which is one rounding difference away from clipping a
-- hairline off an edge nobody would think to look at. Slack is cheaper than a
-- device round.
-- PROBE-EXEMPT BEGIN: TRANSCRIBED TRIGONOMETRY — a workaround, not a lesson.
-- api.md:325 records a real 2026-08-17 device defect (a 100x70 box at scale 1.5
-- and rotation 30 painted 182.4x165.9 into its 100x70 slot and spilled onto its
-- neighbours) and then hands the consumer this formula as prose. So this file
-- transcribes it, plus a slack constant, and every future consumer combining
-- `scale` with `rotation` beside a sibling is one copy-paste from correct and
-- one omission from reproducing the original bug. The framework owes a
-- reserved-footprint API here (purity audit teaches-wrong §12); until it has
-- one, copy this at your own risk rather than as the house style.
local FOOTPRINT_SLACK = 6
local function turnedFootprint(w: number, h: number, scale: number, deg: number): (number, number)
	local r = math.rad(deg)
	local sw, sh = w * scale, h * scale
	local c, s = math.abs(math.cos(r)), math.abs(math.sin(r))
	return math.ceil(sw * c + sh * s) + FOOTPRINT_SLACK, math.ceil(sw * s + sh * c) + FOOTPRINT_SLACK
	-- PROBE-EXEMPT END
end
local STAGE_W, STAGE_H = turnedFootprint(CLUSTER_W, CLUSTER_H, TURN_SCALE, TURN_ROTATION)
local PLATE_W, PLATE_H = 70, 40
local MARKER = 20

--[[ EVERY PLAYER-VISIBLE STRING, flat keys only, exported as `copy` — the same
	contract `canvas_group.luau`/`branch_scope.luau`/`flow_wrap.luau` carry,
	because `tests/overflow_sweep.spec.luau`'s locale axis and
	`tests/examples_gallery.spec.luau`'s pseudo-localization case both re-run a
	fixture through a ~1.4x expansion by reading this table, and a check that
	cannot reach the strings cannot make that claim. ]]
local COPY = {
	title = "Two things a real parent buys",
	intro = "ADR-0032: a container registered as a real engine parent lets the engine compose a term for its "
		.. "whole subtree — group opacity, and rotation with scale.",
	opacityTitle = "Group opacity, composited once",
	opacityIntro = "Both panels hold the same two plates and the same fade. At 100% they are identical.",
	oneTitle = "One group — UI.ZStack{ opacity = f }",
	oneNote = "Painted once, then faded. The small plate stays solid on top of the big one.",
	manyTitle = "Two groups — the same fade on each plate",
	manyNote = "Each plate fades against what is behind it, so the overlap composes twice.",
	fadeLabel = "Fade",
	fadeStatusPrefix = "Opacity: ",
	carryTitle = "A container that carries its contents",
	carryIntro = "Turn the switch. The left pair rotates and scales as one rigid group. The right marker is a "
		.. "leaf with no contents to carry, so it spins alone while its own plate never moves.",
	carriesTitle = "Carries — the container turns",
	carriesNote = "scale and rotation on the ZStack: the engine composes both for its subtree (ADR-0032 D4).",
	aloneTitle = "Alone — a leaf rotates on its own",
	aloneNote = "The marker carries its own rotation and scale; the plate beside it is untouched.",
	turnLabelOff = "Turn",
	turnLabelOn = "Reset",
	turnStatusOff = "at rest — 0°, 1x",
	turnStatusOn = "turned — 30°, 1.5x",
}

return {
	title = "Nested containers: a shared fade, and a container that carries its contents (ADR-0032)",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("nested-compositing")
		-- ADAPT-L4: both comparisons below say "side by side where there is room, a
		-- column where there is not", and until 2026-08-21 neither ever went side by
		-- side — `UI.AdaptiveStack` defaulted to a column forever. The axis is the
		-- surface's own fact now, and the class refuses without it. `scope` owns the
		-- memos `conditions` builds (RR-8).
		local conditions = Facet.adaptive.conditions(core, ctx.env, { scope = scope })

		-- ── the two drivers, shared by both halves of each comparison ────────
		local fade = scope:own(core:signal(FADE_DEFAULT))
		local opacityValue = scope:own(core:memo(function(use)
			return use(fade) / 100
		end))
		local turned = scope:own(core:signal(false))
		local carryRotation = scope:own(core:memo(function(use)
			return if use(turned) then TURN_ROTATION else 0
		end))
		local carryScale = scope:own(core:memo(function(use)
			return if use(turned) then TURN_SCALE else 1
		end))

		local fadeStatus = scope:own(core:memo(function(use)
			return `{COPY.fadeStatusPrefix}{math.floor(use(fade) + 0.5)}%`
		end))
		local turnStatus = scope:own(core:memo(function(use)
			return if use(turned) then COPY.turnStatusOn else COPY.turnStatusOff
		end))
		local turnLabel = scope:own(core:memo(function(use)
			return if use(turned) then COPY.turnLabelOn else COPY.turnLabelOff
		end))

		local fadeSlider = Facet.Controls.Slider(core, {
			id = "FadeSlider",
			label = COPY.fadeLabel,
			value = fade,
			min = 0,
			max = 100,
			step = 5,
		})

		-- ── (a) group opacity: one fade group, or two ────────────────────────
		local function plate(spec: any, opacityProp: any?): any
			return UI.Box({
				id = spec.id,
				width = { type = "fixed", px = spec.w },
				height = { type = "fixed", px = spec.h },
				alignH = "center",
				alignV = "center",
				tint = { role = spec.role, blend = 1 },
				opacity = opacityProp,
			})
		end

		-- ONE fade group over both plates: the opacity is on the STACK.
		local oneGroup = UI.ZStack({
			id = "OneGroup",
			opacity = opacityValue,
			width = UI.fill(),
			height = { type = "fixed", px = BACK.h },
			children = { plate(BACK), plate(FRONT) },
		})

		-- TWO fade groups over one plate each: the same value, one wrap lower —
		-- the shape an author gets reaching for "fade the plate" instead of "fade
		-- the picture" (ADR-0029: `opacity` lives on Box and ZStack, so a leaf can
		-- declare its own without a wrap, and every leaf that does becomes its own
		-- tiny CanvasGroup).
		local twoGroups = UI.ZStack({
			id = "TwoGroups",
			width = UI.fill(),
			height = { type = "fixed", px = BACK.h },
			children = { plate(BACK, opacityValue), plate(FRONT, opacityValue) },
		})

		-- ── (b) a container that carries its contents, or does not ──────────
		-- ONE builder for both panels: `plateTransform` authored on the ZSTACK
		-- ITSELF is what registers it as an instance host (ADR-0032 Decision 4 —
		-- `src/render/instance_boundary.luau`'s `(scale or rotation) and children`
		-- rule); `markerTransform` authored on the LEAF is the case that rule
		-- explicitly excludes (a leaf has no subtree to carry anything down), so
		-- calling this once with each set of arguments builds both the "carries"
		-- and the "alone" cluster from one declaration, exactly the way
		-- `canvas_group.luau`'s `plate()` builds both its panels' plates.
		local function cluster(id: string, plateTransform: any?, markerTransform: any?): any
			local pt = plateTransform or {}
			local mt = markerTransform or {}
			return UI.ZStack({
				id = id,
				rotation = pt.rotation,
				scale = pt.scale,
				alignH = "center",
				alignV = "center",
				width = { type = "fixed", px = CLUSTER_W },
				height = { type = "fixed", px = CLUSTER_H },
				children = {
					UI.Box({
						id = "Plate",
						width = { type = "fixed", px = PLATE_W },
						height = { type = "fixed", px = PLATE_H },
						alignH = "center",
						alignV = "center",
						tint = { role = "accent", blend = 1 },
					}),
					-- the far corner: the position a rigid-group carry keeps correct
					-- and an independent leaf transform does not
					UI.Box({
						id = "Marker",
						width = { type = "fixed", px = MARKER },
						height = { type = "fixed", px = MARKER },
						alignH = "end",
						alignV = "start",
						tint = { role = "danger", blend = 1 },
						rotation = mt.rotation,
						scale = mt.scale,
					}),
				},
			})
		end

		-- CARRIES: the container itself is authored `rotation`/`scale`, so it is
		-- a real instance host (ADR-0032 D4) and the engine composes both terms
		-- for the whole pair — the marker rides the plate's corner as it turns.
		local carried = cluster("Carried", { rotation = carryRotation, scale = carryScale }, nil)
		-- ALONE: the container declares NEITHER prop (stays flat and elidable —
		-- ADR-0032 D2), so it earns no host; the SAME rotation/scale is authored
		-- on the marker leaf instead, which always rotates correctly on its own
		-- and therefore spins in place, detached from the plate beside it — the
		-- pre-ADR-0032 defect, reproduced on purpose as the control.
		local alone = cluster("Static", nil, { rotation = carryRotation, scale = carryScale })

		local turnToggle = UI.Button({
			id = "TurnToggle",
			label = turnLabel,
			onActivate = function()
				turned:set(not turned:get())
			end,
		})

		-- THE RESERVATION, and it must sit OUTSIDE the node that scales — a box that
		-- scales with its contents reserves nothing. Fill-width so a narrow phone's
		-- stacked panels give it the whole column; fixed height because the vertical
		-- overflow is what ran over the caption.
		local function stage(body: any): any
			return UI.ZStack({
				id = "Stage",
				width = UI.fill(),
				height = { type = "fixed", px = STAGE_H },
				children = { body },
			})
		end

		local function panel(id: string, title: string, note: string, body: any): any
			return UI.VStack({
				id = id,
				surface = "control",
				padding = "s",
				gap = "tight",
				width = UI.fill(),
				children = {
					UI.Text({ id = "Title", text = title, textSize = "caption" }),
					body,
					UI.Text({ id = "Note", text = note, textSize = "caption", role = "secondary" }),
				},
			})
		end

		local screen = UI.Screen({
			id = "NestedCompositing",
			padding = 12,
			gap = "s",
			children = {
				-- THE PAGE SCROLLS, same reason as every multi-section fixture here:
				-- two comparison rows, two controls and four caption blocks do not fit
				-- the ~200px a 640x320 landscape phone has left under the showcase's
				-- own chrome strip.
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "control" }),
						UI.Text({ id = "Intro", text = COPY.intro, textSize = "caption", role = "secondary" }),

						UI.VStack({
							id = "Opacity",
							gap = "s",
							width = UI.fill(),
							children = {
								UI.Text({ id = "SectionTitle", text = COPY.opacityTitle, textSize = "label" }),
								UI.Text({
									id = "SectionIntro",
									text = COPY.opacityIntro,
									textSize = "caption",
									role = "secondary",
								}),
								fadeSlider.blueprint,
								UI.Text({
									id = "FadeStatus",
									text = fadeStatus,
									textSize = "caption",
									role = "secondary",
								}),
								-- side by side where there is room, a column where there is
								-- not — the comparison only means anything while both panels
								-- are visible at once
								UI.AdaptiveStack({
									id = "Panels",
									axis = conditions.axis,
									gap = "s",
									width = UI.fill(),
									children = {
										panel("One", COPY.oneTitle, COPY.oneNote, oneGroup),
										panel("Two", COPY.manyTitle, COPY.manyNote, twoGroups),
									},
								}),
							},
						}),

						UI.VStack({
							id = "Carry",
							gap = "s",
							width = UI.fill(),
							children = {
								UI.Text({ id = "SectionTitle", text = COPY.carryTitle, textSize = "label" }),
								UI.Text({
									id = "SectionIntro",
									text = COPY.carryIntro,
									textSize = "caption",
									role = "secondary",
								}),
								turnToggle,
								UI.Text({
									id = "TurnStatus",
									text = turnStatus,
									textSize = "caption",
									role = "secondary",
								}),
								UI.AdaptiveStack({
									id = "Panels",
									axis = conditions.axis,
									gap = "s",
									width = UI.fill(),
									children = {
										panel("Carries", COPY.carriesTitle, COPY.carriesNote, stage(carried)),
										panel("Alone", COPY.aloneTitle, COPY.aloneNote, stage(alone)),
									},
								}),
							},
						}),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the live drivers, rather than a
			-- re-implementation of either
			fade = fade,
			opacity = opacityValue,
			turned = turned,
			carryRotation = carryRotation,
			carryScale = carryScale,

			steps = {
				setFade = function(_built: any, payload: string?)
					local value = tonumber(payload or "") or FADE_DEFAULT
					fade:set(value)
					return { fade = fade:get() }
				end,
				toggleTurn = function()
					turned:set(not turned:get())
					return { turned = turned:get() }
				end,
			},

			report = function()
				return {
					fade = fade:get(),
					opacity = opacityValue:get(),
					turned = turned:get(),
				}
			end,

			dispose = function()
				fadeSlider.dispose()
				scope:dispose()
			end,
		}
	end,
}
