--!strict
-- ProgressView: linear progress, determinate and INDETERMINATE
-- (docs/plans/swiftui-parity-next.md investment 7; acceptance row B-DSP1;
-- swiftui-parity-round2.md §3.1). A track with a filled portion, over the SHARED
-- value model, so its clamping and formatting are the same arithmetic Slider and
-- Stepper use.
--
-- NON-INTERACTIVE by design: progress reports, it does not accept input. It has
-- no focus role and no semantic action, and it declares that explicitly rather
-- than being silently absent from conformance.
--
-- INDETERMINATE IS SELECTED BY `value = nil` — SwiftUI's own rule (`ProgressView()`
-- with no value is indeterminate). There is deliberately no second flag: a
-- `indeterminate = true` beside a `value = 0.4` is a contradiction the framework
-- would have to arbitrate, and the value already carries the answer. `min`/`max`/
-- `format`/`showValue` all describe a value, so declaring one WITHOUT a value is
-- an authoring error rather than a silent no-op (constitution §4).
--
-- `presentation = "bar" | "spinner"` picks the shape. `"spinner"` is
-- indeterminate-only: a determinate spinner is an ARC, and the blueprint has no
-- rotation or trim channel to draw one with — offering it would mean inventing a
-- styling system this control is explicitly not allowed to grow (§3.1: "No new
-- styling system"). Refused with that reason, not silently degraded.
--
-- `height` IS THE BAR'S TRACK, AND ONLY THE BAR'S. A spinner has no track, and
-- reinterpreting the number as the dot's size was the silent-reinterpretation
-- twin of the refusals above: `presentation = "spinner", height = 40` painted
-- five 40x40 dots in a 216px-wide row, so a caller who asked for a chunky bar and
-- then switched presentation got something else entirely, with no diagnostic.
-- Refused for the same reason `min` on an indeterminate view is refused — the dot
-- is a THEME metric (`controls.progress.spinnerDotSize`), which is where a size
-- that every spinner should agree on belongs.
--
-- ===== AN INDETERMINATE VIEW OWNS A LIVE CLOCK ENTRY, SO IT NAMES AN OWNER ====
-- `scope` is REQUIRED when `value = nil`, exactly as `newAsyncImage` requires one
-- for the provider handle it acquires, and for exactly the same reason: this is
-- the one control in the family that keeps DOING something after it is built.
-- Measured before the requirement existed: a view presented and then dismissed,
-- and a view built and never presented at all, both kept one clock entry active
-- and wrote their phase signal 121 times over 120 steps — forever, because the
-- only thing that stops the cycle is `dispose()` and nothing called it. Every
-- other control in this library is inert the moment you drop it; this one was not.
--
-- The alternatives were measured, not weighed in the abstract:
--   * "release it when the value's consumers unmount" needs an unmount event, and
--     there is none — after `presenter.dismiss` the phase memos are simply never
--     pulled again (0 adapter ops over 10 frames), and re-presenting the SAME
--     blueprint recomputes nothing (measured: computes stays 1). So a cycle that
--     parked itself on "nobody read me" could never learn it was back on screen —
--     a frozen spinner, which is the one lie this control must not tell.
--   * a `stop()`/`resume()` keyed off surface visibility needs a per-node
--     lifecycle seam the framework deliberately does not have.
-- Naming the owner at construction makes the leak unrepresentable instead, with
-- no new machinery: `scope` is the library's existing ownership idiom, the
-- presenter's own `handle.scope` is the surface-lifetime one to hand it, and
-- `dispose()` stays public and idempotent for a caller who owns it directly.
--
-- ===== REDUCED MOTION, AND IT IS THE OPPOSITE OF THE USUAL DECISION ==========
-- Everything else this framework animates is decoration: under reduced motion it
-- snaps, and nothing is lost because the information was in the end state all
-- along. A loading indicator is not that. It is the ONE piece of motion on the
-- screen that CARRIES the information — it is the only thing saying "work is
-- still happening", and a frozen spinner and a hung process look identical.
--
-- So the indeterminate indicator registers `kind = "informational"`
-- (motion.luau:31-42). Under reduced motion an informational value KEEPS RUNNING
-- to the same wall-clock terminus and merely QUANTIZES its writes onto the
-- authority's 250 ms tick: decorative motion snaps, informational motion steps,
-- and nothing is ever deleted. The indicator therefore still visibly progresses
-- for a player who asked for less motion — four steps a second instead of sixty
-- — rather than freezing (a lie) or vanishing (the information deleted).
-- Both policies are proved in tests/display_controls.spec.luau.
--
-- The clock arrives as `motionClock` (the presenter's own — `presenter.motionClock`),
-- exactly as `newVirtualList` takes it, and NOT through an input contribution:
-- attaching one would make this control "interactive" to the conformance checker
-- and oblige a four-input proof for a control that accepts no input. With no
-- clock the indeterminate indicator holds its rest pose and reports
-- `animating = false` in its dump — honest, and the same "degrade where the seam
-- is absent" shape row_actions takes when no clock is bound.
--
-- Paint is style-owned, and since ADR-0020 R3 it is owned through the BAR FAMILY
-- rather than through borrowed public surfaces. The track used to declare
-- `surface = "control"` and the fill `surface = "accent"`, which subscribed both
-- to treatments meant for buttons and panels: an ornate package stretched a
-- BUTTON plate across the track, and a panel gradient's alpha made the fill
-- see-through — the same defect the slider's rail and thumb had, one control
-- down (the Step 3.5 progress-Bar cosmetic deferral). They now DECLARE their
-- slots on the blueprint's internal meta channel, exactly as the Slider does, so
-- `barTrack` / `barFill` are their whole paint identity: solid `luau-slot-*`
-- rules when no package skins them, and a package's own track/fill/cap/centre
-- art when one does. The spinner's dots declare the one slot this round adds,
-- `spinner` — same rule, same own-paint guarantee, no new styling system.

local chrome_slots = require("../tokens/chrome_slots")
local value_model = require("./value_model")
local specGuard = require("../spec_guard")

local progress_view = {}

-- theme metrics (ADR-0019 §2), resolved on every solve
local TRACK_HEIGHT = "controls.progress.trackHeight"
-- even, so an even track centres exactly; see the note on the row below
local ROW_MIN_HEIGHT = "controls.progress.rowMinHeight"
-- the spinner's dot, square at full pulse (optional in a package: snapshot
-- resolve fills it from the theme's own space scale, so no existing package's
-- authored metrics — and therefore no package's content stamp — move for it)
local SPINNER_DOT = "controls.progress.spinnerDotSize"

-- ===== the indeterminate cycle ==============================================
-- ONE sawtooth phase, 0 -> 1, restarting: both presentations are pure functions
-- of it, so there is one motion value, one reduced-motion policy, and no way for
-- the two shapes to drift apart on either.
local CYCLE_S = 1
-- the travelling segment's share of the track. Wide enough to read as a bar
-- rather than a dot, narrow enough that its travel is obvious.
local SEGMENT = 0.3
local SPINNER_DOTS = 5
-- a dot at the far side of the ring is still a DOT, not a gap: the trough is a
-- visible resting blend, so the ring never looks like it lost a member
local DOT_TROUGH = 0.15

-- phase 0..1 -> 0..1..0. The sawtooth restarts with a jump; the bar must not, so
-- its travel folds the phase into a triangle and the segment sweeps back.
local function triangle(phase: number): number
	return if phase <= 0.5 then phase * 2 else (1 - phase) * 2
end

-- how LIT dot `index` is at `phase` (0 = resting, 1 = the head of the pulse): a
-- bump travelling around the ring. Distance is measured on the WRAPPED ring, so
-- the dot before the head and the dot after it are lit symmetrically and the
-- travel has no seam.
local function dotFraction(index: number, phase: number): number
	local home = (index - 1) / SPINNER_DOTS
	local raw = math.abs(phase - home)
	local wrapped = math.min(raw, 1 - raw)
	local lit = math.max(0, 1 - wrapped * 2)
	return DOT_TROUGH + (1 - DOT_TROUGH) * lit
end

export type Spec = {
	id: string?,
	-- nil (the whole key absent) = INDETERMINATE; a number or Readable<number> =
	-- determinate. Construction-fixed, exactly as SwiftUI's two initializers are
	-- two different views — a Readable that happens to yield nil is still a
	-- determinate bar reading a broken value, never a mode switch.
	value: any?, -- number | Readable<number> | nil
	label: string?,
	min: number?, -- default 0
	max: number?, -- default 1
	format: ((value: number) -> string)?,
	showValue: boolean?, -- render the formatted value beside the bar
	height: number?, -- the BAR's track thickness; refused for a spinner
	presentation: string?, -- "bar" (default) | "spinner" (indeterminate only)
	-- REQUIRED when `value = nil`: the owner of the indeterminate cycle's clock
	-- entry (see the header). Optional for a determinate view, which acquires
	-- nothing beyond memos and takes the clock entry no one.
	scope: any?,
	-- the surface's motion clock (`presenter.motionClock`). Read only by the
	-- indeterminate cycle; a determinate bar never touches it.
	motionClock: any?,
}

-- CLOSED SPEC (constitution §4; ARCH-1). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local PROGRESS_VIEW_KEYS = specGuard.keySet({
	"format",
	"height",
	"id",
	"label",
	"max",
	"min",
	"motionClock",
	"presentation",
	"scope",
	"showValue",
	"value",
})

local PRESENTATIONS: { [string]: boolean } = { bar = true, spinner = true }

function progress_view.build(LuauUI: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newProgressView", spec, PROGRESS_VIEW_KEYS, "spec")
	local UI = LuauUI.UI
	local id = spec.id or "Progress"
	local presentation = spec.presentation or "bar"
	if not PRESENTATIONS[presentation] then
		error(
			`LuauUI newProgressView: unknown presentation '{tostring(presentation)}'. Use "bar" (default) or `
				.. '"spinner" (indeterminate only).',
			0
		)
	end
	local indeterminate = spec.value == nil
	if not indeterminate and presentation == "spinner" then
		error(
			'LuauUI newProgressView: presentation = "spinner" is indeterminate only — drop `value` for a '
				.. "spinner, or keep the value and use the default bar. A determinate spinner is an arc, and the "
				.. "blueprint has no rotation or trim channel to draw one with.",
			0
		)
	end
	if presentation == "spinner" and spec.height ~= nil then
		error(
			"LuauUI newProgressView: `height` is the BAR's track thickness, and a spinner has no track — it "
				.. "would silently become the DOT's size, and the ring's whole width with it. Drop it (the dot "
				.. "is the theme metric `controls.progress.spinnerDotSize`), or use the default "
				.. '`presentation = "bar"`.',
			0
		)
	end
	if indeterminate then
		for _, key in { "min", "max", "format", "showValue" } do
			if (spec :: any)[key] ~= nil then
				error(
					`LuauUI newProgressView: '{key}' describes a value, and this ProgressView has none `
						.. "(`value = nil` is indeterminate). Drop it, or give the view a value.",
					0
				)
			end
		end
		-- AN OWNER, NAMED AT CONSTRUCTION (see the header). This is the one control
		-- in the family that keeps running after it is built, and the only thing
		-- that stops it is disposal — so it refuses to exist without something that
		-- will do the disposing.
		-- ONLY "is there one" here; WHAT it must be is the shape guard below,
		-- which runs for a determinate view too (`:child` is called on any scope
		-- that is passed, whatever the presentation).
		if spec.scope == nil then
			error(
				"LuauUI newProgressView: an indeterminate view (`value = nil`) runs a motion cycle for as long "
					.. "as it exists, so it needs `scope` — the Scope that owns it, exactly as newAsyncImage "
					.. "does. Pass the surface's own scope (`handle.scope` retires it with the surface), or any "
					.. "scope you dispose. `dispose()` is still there for a caller who owns it directly.",
				0
			)
		end
	end
	--[[ A SCOPE HAS TO BE ONE, and the guard names BOTH methods this control
		uses (redteam follow-up, 2026-08-13). The refusal above asked only for
		`own`, while the very next statement calls `:child(...)` — so a
		scope-like object carrying an `own` and no `child` walked past the
		authored refusal and died three lines later on "attempt to call a nil
		value", which tells a caller nothing about what they got wrong. HERE
		rather than inside the indeterminate branch, because `:child` is called
		on ANY scope that is passed and a determinate view had no shape check on
		`scope` at all. ]]
	if
		spec.scope ~= nil
		and (
			type(spec.scope) ~= "table"
			or type((spec.scope :: any).own) ~= "function"
			or type((spec.scope :: any).child) ~= "function"
		)
	then
		error(
			"LuauUI newProgressView: `scope` must be a LuauUI Scope — what `core:scope(...)` returns, or a "
				.. "presented surface's own `handle.scope`. This control asks it for `own` and `child`, and the "
				.. "value passed answers neither.",
			0
		)
	end
	-- a CHILD of the caller's scope when there is one, so disposing theirs disposes
	-- this whole control — memos, motion value and all — with no second call
	local scope = if spec.scope ~= nil
		then (spec.scope :: any):child("progress-" .. tostring(id))
		else core:scope("progress-" .. tostring(id))

	-- ===== the indeterminate cycle ==========================================
	-- One informational sawtooth on the surface's clock (see the header's
	-- reduced-motion note). `phase` is a plain Readable<number> either way, so
	-- every dim below is written once and does not care whether it is animating.
	local phaseValue: any = nil
	local settleRelease: (() -> ())? = nil
	-- THE CYCLE'S RELEASE IS A SCOPE RESOURCE, not something only `dispose()`
	-- reaches. Owned FIRST, so the scope's reverse-order walk runs it LAST: every
	-- memo that reads the phase is released before the phase itself is, and no
	-- write can land on a disposed reader.
	local function releaseCycle()
		if settleRelease ~= nil then
			settleRelease()
			settleRelease = nil
		end
		if phaseValue ~= nil then
			phaseValue:dispose()
			phaseValue = nil
		end
	end
	scope:own(releaseCycle)
	if indeterminate and spec.motionClock ~= nil then
		local clock = spec.motionClock
		-- a GLIDE, not a spring: an indicator's whole job is a CONSTANT sweep, and
		-- a spring eases out at each end, which reads as the loader stalling.
		phaseValue = clock:glide(0, { duration = CYCLE_S, kind = "informational" })
		settleRelease = phaseValue:onSettle(function()
			-- restart the sawtooth. `snap` is a PLACEMENT (it announces no arrival),
			-- so re-aiming from inside a settle handler cannot re-enter this
			-- callback — the cycle is a loop in time, never in the call stack.
			phaseValue:snap(0)
			phaseValue:setTarget(1)
		end)
		phaseValue:setTarget(1)
	end
	local function phase(use: any?): number
		if phaseValue == nil then
			return 0
		end
		return if use ~= nil then use(phaseValue) else phaseValue:get()
	end

	local model = value_model.new({
		min = spec.min or 0,
		max = if spec.max ~= nil then spec.max else 1,
		format = spec.format,
	})
	local isReadable = type(spec.value) == "table" and (spec.value :: any).get ~= nil
	local function read(use: any?): number
		if isReadable then
			return if use ~= nil then use(spec.value) else (spec.value :: any):get()
		end
		return spec.value :: number
	end

	local children: { any } = {}
	local api = {}

	if spec.label ~= nil then
		table.insert(children, UI.Text({ id = "Label", text = spec.label, textSize = "label" }))
	end

	if presentation == "spinner" then
		-- ===== THE SPINNER =====================================================
		-- DOTS, NOT AN ARC, and that is a platform fact rather than a taste: the
		-- blueprint has no rotation channel and no path trim, so a rotating gear of
		-- lines is not expressible without inventing a styling system this control
		-- is explicitly not allowed to grow. A pulse travelling around a fixed ring
		-- of dots reads unambiguously as "working" and costs five inert Boxes.
		--
		-- THE PULSE IS PAINT, NOT GEOMETRY, and that was measured rather than
		-- assumed. The first shape here sized each dot as a PERCENT of the row, and
		-- the solver said what it always says: "percent size on an unbounded axis
		-- (inside scroll axis?)" — because a vertical ScrollView is exactly where a
		-- loading indicator lives, and a fraction of an unbounded axis is not a
		-- size (docs/lessons/the-solver-already-told-you.md). So the dots are FIXED
		-- squares and the travelling bump rides the `tint` channel, which is
		-- `dirty = { "paint" }`: the ring animates for zero re-solves, and it can be
		-- dropped into any container without asking what its parent's axis is.
		--
		-- The slot rules still own the dot's SHAPE (round, hairline, solid) and the
		-- tint claims only its colour — the exact layering the tint channel exists
		-- for (screen_target.luau: "everything the tint did not claim keeps its").
		local dots: { any } = {}
		for index = 1, SPINNER_DOTS do
			local pulse = scope:own(core:memo(function(use)
				return { role = "accent", from = "control", blend = dotFraction(index, phase(use)) }
			end))
			table.insert(
				dots,
				chrome_slots.attachHint(
					UI.Box({
						id = `Dot{index}`,
						-- THE THEME METRIC, FULL STOP (redteam follow-up,
						-- 2026-08-13). `spec.height or SPINNER_DOT` was dead
						-- code only because the refusal above rejects
						-- `presentation = "spinner"` WITH a height — so the
						-- silent reinterpretation the refusal exists to
						-- prevent (five 40x40 dots for a caller who asked for
						-- a chunky BAR) was sitting here waiting for the day
						-- somebody relaxed that refusal. A dot's size is a
						-- theme metric, and this is now the only thing it can be.
						width = { type = "fixed", px = SPINNER_DOT },
						height = { type = "fixed", px = SPINNER_DOT },
						tint = pulse,
					}),
					{ slot = "spinner" }
				)
			)
		end
		table.insert(
			children,
			UI.HStack({
				id = "Spinner",
				gap = "xs",
				align = "center",
				height = { type = "fixed", px = SPINNER_DOT },
				children = dots,
			})
		)
	else
		-- ===== THE BAR =========================================================
		local barChildren: { any }
		if indeterminate then
			-- THE SEGMENT SWEEPS; THE TRACK DOES NOT MOVE. Both dims are percents,
			-- so the whole travel is solver-owned and reflows with the container
			-- for exactly the reason the determinate fill's percent does.
			local leadDim = scope:own(core:memo(function(use)
				return { type = "percent", fraction = triangle(phase(use)) * (1 - SEGMENT) }
			end))
			barChildren = {
				UI.HStack({
					id = "Sweep",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Spacer({ id = "Lead", width = leadDim, height = { type = "fill", weight = 1 } }),
						chrome_slots.attachHint(
							UI.Box({
								id = "Fill",
								width = { type = "percent", fraction = SEGMENT },
								height = { type = "fill", weight = 1 },
							}),
							{ slot = "barFill" }
						),
					},
				}),
			}
		else
			-- the filled portion is a PERCENT dim, so the bar reflows with its
			-- container without the control recomputing pixels on every resize
			local fillDim = scope:own(core:memo(function(use)
				return { type = "percent", fraction = model.fraction(read(use)) }
			end))
			barChildren = {
				-- THE FILL IS THE CLIP WINDOW (ADR-0020 R3, probe rs-m4). The solver
				-- keeps sizing this node to the percent — that is what a flat bar's
				-- accent block IS — and a package that skins the bar has the adapter
				-- parent a ClipsDescendants window over it holding a FULL-TRACK-size
				-- image. So the art never re-derives its nine-patch as the value
				-- moves, and the geometry stays exactly where it was: solver-owned.
				chrome_slots.attachHint(
					UI.Box({
						id = "Fill",
						alignH = "start",
						width = fillDim,
						height = { type = "fill", weight = 1 },
					}),
					{ slot = "barFill" }
				),
			}
		end
		table.insert(
			children,
			chrome_slots.attachHint(
				UI.ZStack({
					id = "Bar",
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = spec.height or TRACK_HEIGHT },
					children = barChildren,
				}),
				{ slot = "barTrack" }
			)
		)
	end

	local readout: any = nil
	local semantic: any = nil
	if not indeterminate then
		readout = scope:own(core:memo(function(use)
			return model.format(read(use))
		end))
		semantic = scope:own(core:memo(function(use)
			return model.semanticText(read(use))
		end))
		if spec.showValue == true then
			table.insert(children, UI.Text({ id = "Value", text = readout, textSize = "label" }))
		end
	else
		-- AN INDETERMINATE VIEW STILL OWES A SCREEN READER A SENTENCE, and the
		-- only true one is that the work is running. Static: nothing about it
		-- changes as the phase sweeps, and re-announcing "loading" sixty times a
		-- second is exactly what a live region must not do.
		semantic = scope:own(core:memo(function()
			return "Loading"
		end))
	end

	-- ROW HEIGHT IS EVEN ON PURPOSE (director review 2026-07-24). The track is an
	-- even 6px; the row's content height came out of the text measure as 17, and an
	-- even bar cannot be pixel-centred in an odd row — alignOffset floors, so the
	-- bar sat half a logical pixel high, which is a full pixel on a 2x display and
	-- the director saw it twice. Flooring an even row instead removes the parity
	-- mismatch by construction rather than moving the error to the other side.
	api.blueprint = UI.HStack({
		id = id,
		gap = "s",
		align = "center",
		width = { type = "fill", weight = 1 },
		height = { type = "minMax", min = ROW_MIN_HEIGHT },
		children = children,
	})
	api.model = model
	api.semanticText = semantic
	api.phase = phaseValue

	function api.dump()
		if indeterminate then
			return {
				schema = "luauui-progress-dump/1",
				id = id,
				indeterminate = true,
				presentation = presentation,
				-- the live cycle position a bug report needs: "stuck" and "running"
				-- are the only two states this control has, and they differ by this
				-- number moving
				phase = phase(nil),
				animating = phaseValue ~= nil,
				semanticText = "Loading",
			}
		end
		local v = read(nil)
		return {
			schema = "luauui-progress-dump/1",
			id = id,
			-- ADDITIVE (parity round 2 §3.1): every key below this pair carries the
			-- exact value it carried before indeterminate existed, so the determinate
			-- path is unchanged for a consumer reading any of them.
			indeterminate = false,
			presentation = presentation,
			value = v,
			fraction = model.fraction(v),
			formatted = model.format(v),
			semanticText = model.semanticText(v),
			min = model.min,
			max = model.max,
			showValue = spec.showValue == true,
		}
	end

	-- IDEMPOTENT, because there are now two ways in: this call, and the owning
	-- scope disposing its child. A caller who does both must not trip the core's
	-- double-disposal detector for being careful.
	function api.dispose()
		if scope:isDisposed() then
			return
		end
		scope:dispose() -- runs releaseCycle last (owned first)
	end

	return api
end

return progress_view
