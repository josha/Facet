--!strict
-- Progress is informational: no value selects an indeterminate indicator.
-- Native controls use Compose timelines; theme tokens define each presentation.
local Compose = require("../vendor/compose/core")
local selection = require("../selection_model")

local chrome_slots = require("../tokens/chrome_slots")
local path_shapes = require("./path_shapes")
local value_model = require("./value_model")
local specGuard = require("../spec_guard")
local surface_env = require("../env/surface_env")
local theme_snapshot = require("../themes/snapshot")
local text_fit = require("../layout/text_fit")
local progress_trail = require("./progress_trail")

local progress_view = {}

local TRACK_HEIGHT = "controls.progress.trackHeight"
local ROW_MIN_HEIGHT = "controls.progress.rowMinHeight"
local SPINNER_DOT = "controls.progress.spinnerDotSize"
local CIRCULAR_SIZE = "controls.progress.circularSize"
local CIRCULAR_THICKNESS = "controls.progress.circularThickness"

local CIRCULAR_RADIUS = 0.8
progress_view.CIRCULAR_RADIUS = CIRCULAR_RADIUS

local CYCLE_S = 1
--[[ REDUCED MOTION, AND IT IS THE OPPOSITE OF THE USUAL DECISION.

	Everything else this framework animates is decoration: under reduced motion it
	SNAPS to the end state, and nothing is lost because the information was in the
	end state all along (`src/render/transitions.luau` says exactly this and needs
	no branch at all). An indeterminate loading indicator is not that. It is the
	one piece of motion on the screen that CARRIES the information — the only
	thing saying "work is still happening" — and it has no end state to snap to.
	A frozen spinner and a hung process look identical.

	So this control does what `src/motion/motion.luau` calls the STEPPED policy
	for informational values: the cycle keeps running to the same wall clock and
	only its WRITES quantize, onto a coarse tick. Four steps a second instead of
	sixty. Nothing is skipped — skipping is how reduced motion deletes
	information — and `dump().animating` stays honest, because the indicator
	really is still advancing.

	A regression replaced that with `timeline:pause(); timeline:seek(0)`, which
	is a freeze wearing the word "reduced". `REDUCED_STEP` is `motion.luau`'s own
	`DEFAULT_QUANTUM` expressed as a fraction of this cycle, so both halves of the
	framework step the same informational tick. ]]
local REDUCED_QUANTUM_S = 0.25
local REDUCED_STEP = REDUCED_QUANTUM_S / CYCLE_S
progress_view.REDUCED_QUANTUM_S = REDUCED_QUANTUM_S
local SEGMENT = 0.3
local SPINNER_DOTS = 5
local SPIN_SWEEP = 90
local DOT_TROUGH = 0.15

local function triangle(phase: number): number
	return if phase <= 0.5 then phase * 2 else (1 - phase) * 2
end

local function dotFraction(index: number, phase: number): number
	local home = (index - 1) / SPINNER_DOTS
	local raw = math.abs(phase - home)
	local wrapped = math.min(raw, 1 - raw)
	local lit = math.max(0, 1 - wrapped * 2)
	return DOT_TROUGH + (1 - DOT_TROUGH) * lit
end

local specTypes = require("../spec_types/progress_view")
export type Spec = specTypes.Spec

local PROGRESS_VIEW_KEYS = specGuard.keySet({
	"segments",
	"trail",
	"diameter",
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

type Capability = specTypes.Capability

-- Validate presentation capabilities before allocating motion resources.
local PRESENTATIONS: { [string]: Capability } = {
	bar = {
		indeterminate = true,
		determinate = true,
		hasTrack = true,
		valueLabel = true,
	},
	circular = {
		indeterminate = true,
		determinate = true,
		hasTrack = false,
		valueLabel = false,
		sizeMetric = CIRCULAR_SIZE,
		valueLabelAlt = "the ring is theme-sized and small by construction, so a readout has no size it is "
			.. "guaranteed to fit inside it; put your own `UI.Text` beside the control, or use the default "
			.. '`presentation = "bar"`, whose `showValue` sits beside the track',
	},
	spinner = {
		indeterminate = true,
		determinate = false,
		hasTrack = false,
		valueLabel = false,
		sizeMetric = SPINNER_DOT,
		modeAlt = 'a determinate ring is `presentation = "circular"`, which draws exactly that arc on ' .. "`UI.Path`",
	},
}

local PRESENTATION_NAMES: { string } = {}
for name in PRESENTATIONS do
	table.insert(PRESENTATION_NAMES, name)
end
table.sort(PRESENTATION_NAMES)
local PRESENTATION_LIST = `"{table.concat(PRESENTATION_NAMES, '", "')}"`

function progress_view.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("UI.ProgressView", spec, PROGRESS_VIEW_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Progress"
	local presentation = spec.presentation or "bar"
	local caps = PRESENTATIONS[presentation]
	if caps == nil then
		error(
			`Facet UI.ProgressView: unknown presentation '{tostring(presentation)}'. Use one of `
				.. `{PRESENTATION_LIST} ("bar" is the default; "spinner" is indeterminate only).`,
			0
		)
	end
	local indeterminate = spec.value == nil
	local function nonnegative(v: any): boolean
		return type(v) == "number" and v == v and v >= 0 and v < math.huge
	end
	if spec.segments ~= nil then
		assert(not indeterminate and presentation == "bar", "UI.ProgressView.segments requires a determinate bar")
		assert(
			nonnegative(spec.segments) and spec.segments >= 1 and spec.segments <= 100 and spec.segments % 1 == 0,
			"UI.ProgressView.segments must be an integer from 1 to 100"
		)
	end
	if spec.diameter ~= nil then
		assert(presentation == "circular", "UI.ProgressView.diameter requires circular presentation")
		assert(
			(nonnegative(spec.diameter) and (spec.diameter :: any) > 0)
				or (type(spec.diameter) == "string" and #spec.diameter > 0),
			"UI.ProgressView.diameter must be a positive number or theme metric"
		)
	end
	if spec.trail ~= nil then
		assert(not indeterminate and presentation == "bar", "UI.ProgressView.trail requires a determinate bar")
		specGuard.assertKnownKeys("ProgressView.trail", spec.trail, specGuard.keySet({ "delay", "duration" }), "spec")
		assert(type(spec.trail) == "table", "UI.ProgressView.trail must be a table")
		assert(
			spec.trail.delay == nil or nonnegative(spec.trail.delay),
			"UI.ProgressView.trail.delay must be nonnegative seconds"
		)
		assert(
			spec.trail.duration == nil or (nonnegative(spec.trail.duration) and spec.trail.duration > 0),
			"UI.ProgressView.trail.duration must be positive seconds"
		)
	end
	if not (if indeterminate then caps.indeterminate else caps.determinate) then
		local mode = if indeterminate then "indeterminate" else "determinate"
		local other = if indeterminate then "determinate" else "indeterminate"
		error(
			`Facet UI.ProgressView: presentation = "{presentation}" is {other} only — `
				.. (if indeterminate
					then "give the view a `value`"
					else "drop `value` for it, or keep the value and use the default bar")
				.. `. {caps.modeAlt or `there is no {mode} form of this shape`}.`,
			0
		)
	end
	if spec.height ~= nil and not caps.hasTrack then
		error(
			`Facet UI.ProgressView: \`height\` is the BAR's track thickness, and a "{presentation}" has no `
				.. "track — it would silently become this shape's own size instead. Drop it (the size is the "
				.. `theme metric \`{tostring(caps.sizeMetric)}\`), or use the default \`presentation = "bar"\`.`,
			0
		)
	end
	if not indeterminate and spec.showValue ~= nil and not caps.valueLabel and spec.diameter == nil then
		error(
			`Facet UI.ProgressView: \`showValue\` has nowhere to go on a "{presentation}" — `
				.. `{tostring(caps.valueLabelAlt)}.`,
			0
		)
	end
	if indeterminate then
		for _, key in { "min", "max", "format", "showValue" } do
			if (spec :: any)[key] ~= nil then
				error(
					`Facet UI.ProgressView: '{key}' describes a value, and this ProgressView has none `
						.. "(`value = nil` is indeterminate). Drop it, or give the view a value.",
					0
				)
			end
		end
	end

	local scope = nil

	local phaseValue: any = nil
	local reducedPolicy: any = nil
	local settleRelease: (() -> ())? = nil
	-- The explicit-handle clock path releases its cycle when its owner closes.
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
	if scope then
		scope.own(releaseCycle)
	end
	if indeterminate then
		local timeline = Facet.runtime.timeline({ duration = CYCLE_S, repeats = math.huge, autoplay = false })
		local environment = surface_env.find(core)
		--[[ THE CLOCK NEVER STOPS; THE READ COARSENS (see REDUCED_STEP above).
			Quantizing at the read rather than at the timeline is what keeps the two
			policies ONE cycle: the sawtooth runs at the same wall-clock rate either
			way, so switching policy mid-cycle lands the indicator on the step it
			would already have been on instead of restarting it — and `api.phase`
			stays the raw cycle, which is what a caller asking for the phase means.
			Every presentation reads through `phase` below, so all three step
			together with no branch of their own. ]]
		phaseValue = timeline.progress
		reducedPolicy = if environment ~= nil then environment:get("motionPolicy") else nil
		timeline:play()
	end
	local function phase(use: any?): number
		if phaseValue == nil then
			return 0
		end
		local value = selection.read(phaseValue, use)
		if reducedPolicy ~= nil and selection.read(reducedPolicy, use) == "reduced" then
			-- four visible steps a second, no easing: "still loading" survives, the
			-- sixty-a-second sweep does not
			return math.floor(value / REDUCED_STEP) * REDUCED_STEP
		end
		return value
	end

	local model = value_model.new({
		min = spec.min or 0,
		max = if spec.max ~= nil then spec.max else 1,
		format = spec.format,
	})
	local function read(use: any?): number
		return selection.read(spec.value, use)
	end

	local children: { any } = {}
	local api = {}
	local fraction = if indeterminate or (spec.segments == nil and spec.trail == nil)
		then nil
		else Compose.formula(function(use)
			return model.fraction(read(use))
		end)
	local env = if spec.trail or (spec.showValue and spec.diameter) then surface_env.find(core) else nil
	local trailValue = if spec.trail
		then progress_trail.native(Facet.runtime, fraction, spec.trail, if env then env:get("motionPolicy") else nil)
		else nil
	local circularSize = spec.diameter or CIRCULAR_SIZE

	if spec.label ~= nil then
		table.insert(children, UI.Text({ id = "Label", text = spec.label, textSize = "label", shrinkWeight = 1 }))
	end

	-- Dot tint changes paint without invalidating layout.
	local function buildSpinner(): any
		local dots: { any } = {}
		for index = 1, SPINNER_DOTS do
			local pulse = function(use)
				return { role = "accent", from = "control", blend = dotFraction(index, phase(use)) }
			end
			table.insert(
				dots,
				chrome_slots.attachHint(
					UI.Box({
						id = `Dot{index}`,
						width = { type = "fixed", px = SPINNER_DOT },
						height = { type = "fixed", px = SPINNER_DOT },
						tint = pulse,
					}),
					{ slot = "spinner" }
				)
			)
		end
		return UI.HStack({
			id = "Spinner",
			gap = "xs",
			align = "center",
			height = { type = "fixed", px = SPINNER_DOT },
			children = dots,
		})
	end

	-- One arc describes a fixed sweep or a sweep proportional to the value.
	local function buildCircular(): any
		local ringChildren: { any } = {}
		if not indeterminate then
			table.insert(
				ringChildren,
				UI.Path({
					id = "Track",
					points = path_shapes.ring({ radius = CIRCULAR_RADIUS }),
					closed = true,
					thickness = CIRCULAR_THICKNESS,
					role = "secondary",
					width = { type = "fixed", px = circularSize },
					height = { type = "fixed", px = circularSize },
				})
			)
		end
		local arcPoints = function(use)
			if indeterminate then
				return path_shapes.arc(360 * phase(use), SPIN_SWEEP, { radius = CIRCULAR_RADIUS })
			end
			return path_shapes.arc(0, 360 * model.fraction(read(use)), { radius = CIRCULAR_RADIUS })
		end
		table.insert(
			ringChildren,
			UI.Path({
				id = "Arc",
				points = arcPoints,
				thickness = CIRCULAR_THICKNESS,
				role = "accent",
				width = { type = "fixed", px = circularSize },
				height = { type = "fixed", px = circularSize },
			})
		)
		local function ring(id, nodes)
			return UI.ZStack({
				id = id,
				width = { type = "fixed", px = circularSize },
				height = { type = "fixed", px = circularSize },
				children = nodes,
			})
		end
		if not spec.showValue then
			return ring("Ring", ringChildren)
		end
		local readout = function(use)
			return model.format(read(use))
		end
		local centered = function(use)
			local facts = if env
				then text_fit.facts({ env = env, use = use })
				else text_fit.facts({ metrics = theme_snapshot.neutral() })
			local diameter = theme_snapshot.resolveNumber(facts.metrics, circularSize)
			assert(diameter and diameter > 0, "UI.ProgressView.diameter must resolve to positive pixels")
			local role = facts.metrics.type.label
			local size = role.size * facts.scale
			return text_fit.fit({
				text = readout(use),
				font = role.fontKey or theme_snapshot.fontKey(role.font),
				cap = size,
				floor = size,
				offset = facts.offset,
				width = diameter * 0.6,
				height = diameter * 0.6,
				lines = 1,
				lineHeight = role.lineHeight,
			}).fits
		end
		table.insert(
			ringChildren,
			UI.When({
				id = "Readout",
				condition = centered,
				thenView = function()
					return UI.Text({
						id = "Value",
						text = readout,
						textSize = "label",
						lineLimit = 1,
						textAlign = "center",
						alignH = "center",
						alignV = "center",
						width = { type = "percent", fraction = 0.6 },
					})
				end,
			})
		)
		local below = function(use)
			return not centered(use)
		end
		return UI.VStack({
			id = "Gauge",
			width = UI.fill(),
			gap = "xs",
			align = "center",
			children = {
				ring("Ring", ringChildren),
				UI.When({
					id = "Below",
					condition = below,
					thenView = function()
						return UI.Text({
							id = "Value",
							text = readout,
							textSize = "label",
							width = UI.fill(),
							textAlign = "center",
							alignH = "center",
						})
					end,
				}),
			},
		})
	end

	local function buildBar(): any
		if not indeterminate and (spec.segments ~= nil or trailValue ~= nil) then
			local cells = {}
			local count = spec.segments or 1
			for index = 1, count do
				local function fill(id: string, source: any, trailing: boolean): any
					return chrome_slots.attachHint(
						UI.Box({
							id = id,
							alignH = "start",
							height = UI.fill(),
							width = function(use)
								return { type = "percent", fraction = math.clamp(use(source) * count - index + 1, 0, 1) }
							end,
							tint = if trailing then { role = "contentSecondary", blend = 1 } else nil,
						}),
						{ slot = "barFill" }
					)
				end
				local layers = {}
				if trailValue then
					table.insert(layers, fill("Trail", trailValue, true))
				end
				table.insert(layers, fill("Fill", fraction, false))
				table.insert(
					cells,
					UI.ZStack({
						id = `Segment{index}`,
						width = UI.fill(),
						height = UI.fill(),
						children = layers,
					})
				)
			end
			return chrome_slots.attachHint(
				UI.ZStack({
					id = "Bar",
					width = UI.fill(),
					height = { type = "fixed", px = spec.height or TRACK_HEIGHT },
					children = {
						UI.HStack({
							id = "Segments",
							width = UI.fill(),
							height = UI.fill(),
							gap = if count > 1 then "xs" else 0,
							children = cells,
						}),
					},
				}),
				{ slot = "barTrack" }
			)
		end
		local barChildren: { any }
		if indeterminate then
			local leadDim = function(use)
				return { type = "percent", fraction = triangle(phase(use)) * (1 - SEGMENT) }
			end
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
			local fillDim = function(use)
				return { type = "percent", fraction = model.fraction(read(use)) }
			end
			barChildren = {
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
		return chrome_slots.attachHint(
			UI.ZStack({
				id = "Bar",
				width = { type = "fill", weight = 1 },
				height = { type = "fixed", px = spec.height or TRACK_HEIGHT },
				children = barChildren,
			}),
			{ slot = "barTrack" }
		)
	end

	local SHAPES: { [string]: () -> any } = {
		bar = buildBar,
		circular = buildCircular,
		spinner = buildSpinner,
	}
	table.insert(children, SHAPES[presentation]())

	local readout: any = nil
	local semantic: any = nil
	if not indeterminate then
		readout = function(use)
			return model.format(read(use))
		end
		semantic = function(use)
			return model.semanticText(read(use))
		end
		if spec.showValue == true and presentation == "bar" then
			table.insert(children, UI.Text({ id = "Value", text = readout, textSize = "label" }))
		end
	else
		semantic = function()
			return "Loading"
		end
	end

	local layout = if presentation == "circular" and spec.diameter ~= nil then UI.VStack else UI.HStack
	api.blueprint = layout({
		id = id,
		gap = "s",
		align = "center",
		width = { type = "fill", weight = 1 },
		height = { type = "minMax", min = ROW_MIN_HEIGHT },
		children = children,
	})
	api.model = model
	api.semanticText = Compose.formula(semantic)
	api.phase = phaseValue

	function api.dump()
		if indeterminate then
			return {
				schema = "facet-progress-dump/1",
				id = id,
				indeterminate = true,
				presentation = presentation,
				phase = phase(nil),
				animating = phaseValue ~= nil,
				semanticText = "Loading",
			}
		end
		local v = read(nil)
		return {
			schema = "facet-progress-dump/1",
			id = id,
			indeterminate = false,
			presentation = presentation,
			value = v,
			fraction = model.fraction(v),
			trailFraction = if trailValue then selection.read(trailValue) else nil,
			segments = spec.segments,
			diameter = spec.diameter,
			formatted = model.format(v),
			semanticText = model.semanticText(v),
			min = model.min,
			max = model.max,
			showValue = spec.showValue == true,
		}
	end

	local disposed = false
	local function releaseDerived()
		if fraction then
			fraction:dispose()
		end
		api.semanticText:dispose()
	end
	if scope then
		scope.own(releaseDerived)
	end
	function api.dispose()
		if disposed or (scope and scope:isDisposed()) then
			return
		end
		disposed = true
		if scope then
			scope:dispose()
		else
			releaseDerived()
		end
	end

	return api
end

return progress_view
