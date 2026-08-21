--!strict
-- Shared value model for the value-control family (docs/plans/parity-next.md
-- investment 4; acceptance row B-VAL1). Slider and Stepper are different
-- affordances over the SAME model, so bounds, stepping, rounding, formatting,
-- disabled rules and semantic value text exist exactly once and cannot disagree
-- at the edges.
--
-- Pure: no core, no environment, no Instances. The controls own the reactive
-- plumbing; this owns the arithmetic, which is where the off-by-one bugs live.
--
-- The owner holds the value Signal (the control never creates it — the same rule
-- Toggle and TextInput follow), so a value change is the caller's data model
-- changing, not hidden control state.

local specGuard = require("../spec_guard")
local num = require("../num")

local value_model = {}

export type Spec = {
	min: number,
	max: number,
	step: number?, -- nil = continuous; a Stepper defaults to 1
	-- format(value) -> string for the visible/semantic value text. Defaults to a
	-- trimmed decimal that never shows "-0" or a trailing ".0".
	format: ((value: number) -> string)?,
}

export type Model = {
	min: number,
	max: number,
	step: number?,
	clamp: (value: number) -> number,
	quantize: (value: number) -> number,
	stepped: (value: number, direction: number) -> number,
	fraction: (value: number) -> number,
	fromFraction: (fraction: number) -> number,
	format: (value: number) -> string,
	semanticText: (value: number) -> string,
	atMin: (value: number) -> boolean,
	atMax: (value: number) -> boolean,
}

local isFinite = num.isFinite

-- default formatting: integers print bare, fractions keep up to 2 decimals with
-- trailing zeros trimmed, and negative zero prints as "0"
local function defaultFormat(v: number): string
	if v == 0 then
		return "0"
	end
	if math.floor(v) == v then
		return string.format("%d", v)
	end
	local s = string.format("%.2f", v)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end
value_model.defaultFormat = defaultFormat

-- CLOSED SPEC (constitution §4). Exactly the four fields the model
-- reads — a misspelled `step` is a control that silently went continuous.
local VALUE_MODEL_KEYS = specGuard.keySet({ "format", "max", "min", "step" })

function value_model.new(spec: Spec): Model
	specGuard.assertKnownKeys("valueModel.new", spec, VALUE_MODEL_KEYS, "spec")
	if not isFinite(spec.min) or not isFinite(spec.max) then
		error("Facet value control: min and max must be finite numbers", 0)
	end
	if spec.max <= spec.min then
		error(`Facet value control: max ({spec.max}) must be greater than min ({spec.min})`, 0)
	end
	if spec.step ~= nil and (not isFinite(spec.step) or spec.step <= 0) then
		error(`Facet value control: step must be a positive number (got {tostring(spec.step)})`, 0)
	end
	local min, max, step = spec.min, spec.max, spec.step
	local authored = spec.format

	-- QUARANTINED (F-38): `spec.format` is the one user callback in this module,
	-- and it is called from the RENDER path of Slider and Stepper — a throwing
	-- formatter used to unwind a whole solve. The core quarantines its equivalent
	-- (`eq`) for exactly this reason. Containment here is the lowest-risk shape:
	-- this module owns no diagnostic channel, so a failed format degrades to the
	-- default formatting of the same value and the frame still paints.
	local function format(v: number): string
		if authored == nil then
			return defaultFormat(v)
		end
		local ok, out = pcall(authored, v)
		if not ok then
			return defaultFormat(v)
		end
		return out
	end

	local function clamp(v: number): number
		if not isFinite(v) then
			return min -- a NaN/inf value resolves to the low bound, never propagates
		end
		return math.clamp(v, min, max)
	end

	-- snap to the step grid measured FROM min (not from zero), so a range like
	-- 5..25 step 5 lands on 5/10/15/20/25 rather than on multiples of 5 that miss
	-- the bounds
	local function quantize(v: number): number
		local c = clamp(v)
		if step == nil then
			return c
		end
		local steps = math.floor((c - min) / step + 0.5)
		return clamp(min + steps * step)
	end

	local function stepped(v: number, direction: number): number
		local delta = (step or (max - min) / 100) * (if direction < 0 then -1 else 1)
		local next_ = quantize(clamp(v) + delta)
		-- guarantee forward progress: quantizing back onto the same grid point
		-- would make a keyboard press a no-op mid-grid
		if next_ == quantize(clamp(v)) and step ~= nil then
			next_ = clamp(next_ + delta)
		end
		return next_
	end

	local function fraction(v: number): number
		return math.clamp((clamp(v) - min) / (max - min), 0, 1)
	end

	local function fromFraction(f: number): number
		if not isFinite(f) then
			return min
		end
		return quantize(min + math.clamp(f, 0, 1) * (max - min))
	end

	local function semanticText(v: number): string
		-- what an assistive layer (or a ten-foot readout) should say: the value in
		-- its range, never a bare number with no context
		return `{format(clamp(v))} of {format(min)} to {format(max)}`
	end

	return {
		min = min,
		max = max,
		step = step,
		clamp = clamp,
		quantize = quantize,
		stepped = stepped,
		fraction = fraction,
		fromFraction = fromFraction,
		format = function(v: number)
			return format(clamp(v))
		end,
		semanticText = semanticText,
		atMin = function(v: number)
			return clamp(v) <= min
		end,
		atMax = function(v: number)
			return clamp(v) >= max
		end,
	}
end

return value_model
