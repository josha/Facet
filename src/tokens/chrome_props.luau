--!strict
-- CHROME PROP KINDS.
-- The rule-property value kinds the Step 2 vocabulary did not need, plus the
-- ONE materialization ruling for them, so the pure model side and the client
-- materializer can never disagree about what a value means.
--
-- Step 2's `native_style.materializeProp` speaks color | udim | number | font |
-- enum, and a plain string passes through as a "$Token" reference. Nine-slice
-- chrome adds a Rect (`SliceCenter`) and gradients add sequences
-- (`UIGradient.Color`, `UIGradient.Transparency`) — three value shapes with no
-- existing kind. They live HERE rather than inside the client materializer
-- because the model that emits them is pure and headlessly tested, and because
-- a second copy of "what does kind='rect' mean" is exactly the drift this
-- module exists to prevent.
--
-- Public interface
--   chrome_props.rect(x0, y0, x1, y1)      -> { kind = "rect", ... }
--   chrome_props.colorSeq({ {t, r, g, b} }) -> { kind = "colorseq", stops }
--   chrome_props.numSeq({ {t, v} })         -> { kind = "numseq", stops }
--   chrome_props.KINDS                      the kinds THIS module owns
--   chrome_props.isChromeKind(v) -> boolean
--   chrome_props.describe(v) -> string      canonical serialization fragment
--                                           (content stamps cover these values)
--   chrome_props.materialize(v) -> (handled, value)
--
-- ENGINE SEAM. `materialize` is the only engine-aware function here, and it is
-- aware by ABSENCE: the datatype constructors are read from the script
-- environment at load, which under Lune simply yields nil. A headless caller
-- therefore gets `handled = false` instead of a crash, which is the right
-- answer — a headless test asserts the MODEL, never the engine value. The
-- client materializer's wiring is one branch:
--
--     local handled, value = chrome_props.materialize(v)
--     if handled then return value end
--
-- placed at the top of `native_style.materializeProp` (and beside the theme
-- token writer, so a sequence-valued token reaches SetAttribute intact).

local num = require("../num")

local chrome_props = {}

-- Engine datatype constructors. Present in Roblox, nil under Lune — see the
-- ENGINE SEAM note above. Read once at load so `materialize` stays a plain
-- table lookup on the hot path.
local ENGINE_RECT: any = Rect
local ENGINE_UDIM2: any = UDim2
local ENGINE_COLOR3: any = Color3
local ENGINE_COLOR_SEQUENCE: any = ColorSequence
local ENGINE_COLOR_SEQUENCE_KEYPOINT: any = ColorSequenceKeypoint
local ENGINE_NUMBER_SEQUENCE: any = NumberSequence
local ENGINE_NUMBER_SEQUENCE_KEYPOINT: any = NumberSequenceKeypoint

chrome_props.KINDS = table.freeze({ rect = true, colorseq = true, numseq = true, udim2 = true })

export type Rect = { kind: "rect", x0: number, y0: number, x1: number, y1: number }
export type ColorStop = { t: number, r: number, g: number, b: number }
export type ColorSeq = { kind: "colorseq", stops: { ColorStop } }
export type NumStop = { t: number, v: number }
export type NumSeq = { kind: "numseq", stops: { NumStop } }
export type UDim2Value = { kind: "udim2", xScale: number, xOffset: number, yScale: number, yOffset: number }

local isFinite = num.isFinite

-- rect(x0, y0, x1, y1): a `SliceCenter` in IMAGE pixels — the inner rectangle
-- that stretches, with everything outside it held at its authored size.
function chrome_props.rect(x0: number, y0: number, x1: number, y1: number): Rect
	assert(
		isFinite(x0) and isFinite(y0) and isFinite(x1) and isFinite(y1),
		"chrome_props.rect: every corner must be a finite number"
	)
	assert(
		x1 > x0 and y1 > y0,
		`chrome_props.rect: the slice centre must have positive extent (got {x0},{y0} -> {x1},{y1})`
	)
	return { kind = "rect", x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

-- colorSeq(stops): the gradient ramp. Stops are normalized 0..1 positions with
-- 0..1 channel values; they are SORTED here so the model is canonical and two
-- authorings of the same ramp stamp identically.
function chrome_props.colorSeq(stops: { ColorStop }): ColorSeq
	assert(type(stops) == "table" and #stops >= 2, "chrome_props.colorSeq: a gradient needs at least two stops")
	local out: { ColorStop } = {}
	for _, stop in stops do
		assert(
			isFinite(stop.t) and stop.t >= 0 and stop.t <= 1,
			`chrome_props.colorSeq: stop position must be within 0..1 (got {tostring(stop.t)})`
		)
		assert(
			isFinite(stop.r) and isFinite(stop.g) and isFinite(stop.b),
			"chrome_props.colorSeq: every stop needs finite r/g/b in 0..1"
		)
		table.insert(out, { t = stop.t, r = stop.r, g = stop.g, b = stop.b })
	end
	table.sort(out, function(a, b)
		return a.t < b.t
	end)
	return { kind = "colorseq", stops = out }
end

-- numSeq(stops): the matching alpha ramp (UIGradient.Transparency).
function chrome_props.numSeq(stops: { NumStop }): NumSeq
	assert(type(stops) == "table" and #stops >= 2, "chrome_props.numSeq: a sequence needs at least two stops")
	local out: { NumStop } = {}
	for _, stop in stops do
		assert(
			isFinite(stop.t) and stop.t >= 0 and stop.t <= 1,
			`chrome_props.numSeq: stop position must be within 0..1 (got {tostring(stop.t)})`
		)
		assert(isFinite(stop.v), "chrome_props.numSeq: every stop needs a finite value")
		table.insert(out, { t = stop.t, v = stop.v })
	end
	table.sort(out, function(a, b)
		return a.t < b.t
	end)
	return { kind = "numseq", stops = out }
end

-- udim2(...): a `TileSize` (the layer stack's `tile` kind). rs-m1 measured
-- both components: OFFSET is pixels and SCALE is a fraction of the LABEL's size,
-- not of the texture — so px offsets are the canonical authoring form and scale
-- is the deliberate "N tiles across" idiom.
function chrome_props.udim2(xScale: number, xOffset: number, yScale: number, yOffset: number): UDim2Value
	assert(
		isFinite(xScale) and isFinite(xOffset) and isFinite(yScale) and isFinite(yOffset),
		"chrome_props.udim2: every component must be a finite number"
	)
	return { kind = "udim2", xScale = xScale, xOffset = xOffset, yScale = yScale, yOffset = yOffset }
end

function chrome_props.isChromeKind(v: any): boolean
	return type(v) == "table" and type(v.kind) == "string" and (chrome_props.KINDS :: any)[v.kind] == true
end

-- describe(v): the canonical serialization fragment a content stamp folds in.
-- Returns nil for a value this module does not own, so a caller can fall
-- through to its own serializer.
function chrome_props.describe(v: any): string?
	if not chrome_props.isChromeKind(v) then
		return nil
	end
	if v.kind == "rect" then
		return string.format("rect(%.4f,%.4f,%.4f,%.4f)", v.x0, v.y0, v.x1, v.y1)
	elseif v.kind == "udim2" then
		return string.format("udim2(%.4f,%.4f,%.4f,%.4f)", v.xScale, v.xOffset, v.yScale, v.yOffset)
	elseif v.kind == "colorseq" then
		local parts: { string } = {}
		for _, stop in v.stops do
			table.insert(parts, string.format("%.4f:%.4f,%.4f,%.4f", stop.t, stop.r, stop.g, stop.b))
		end
		return "colorseq(" .. table.concat(parts, ";") .. ")"
	end
	local parts: { string } = {}
	for _, stop in v.stops do
		table.insert(parts, string.format("%.4f:%.4f", stop.t, stop.v))
	end
	return "numseq(" .. table.concat(parts, ";") .. ")"
end

-- materialize(v) -> (handled, value). `handled = false` means either "not a
-- kind this module owns" or "no engine here" — both are cases where the caller
-- keeps its existing behaviour, so this is safe to call unconditionally.
function chrome_props.materialize(v: any): (boolean, any)
	if not chrome_props.isChromeKind(v) then
		return false, nil
	end
	if v.kind == "rect" then
		if ENGINE_RECT == nil then
			return false, nil
		end
		return true, ENGINE_RECT.new(v.x0, v.y0, v.x1, v.y1)
	elseif v.kind == "udim2" then
		if ENGINE_UDIM2 == nil then
			return false, nil
		end
		return true, ENGINE_UDIM2.new(v.xScale, v.xOffset, v.yScale, v.yOffset)
	elseif v.kind == "colorseq" then
		if ENGINE_COLOR_SEQUENCE == nil or ENGINE_COLOR_SEQUENCE_KEYPOINT == nil or ENGINE_COLOR3 == nil then
			return false, nil
		end
		local keypoints = {}
		for _, stop in v.stops do
			table.insert(
				keypoints,
				ENGINE_COLOR_SEQUENCE_KEYPOINT.new(stop.t, ENGINE_COLOR3.new(stop.r, stop.g, stop.b))
			)
		end
		return true, ENGINE_COLOR_SEQUENCE.new(keypoints)
	end
	if ENGINE_NUMBER_SEQUENCE == nil or ENGINE_NUMBER_SEQUENCE_KEYPOINT == nil then
		return false, nil
	end
	local keypoints = {}
	for _, stop in v.stops do
		table.insert(keypoints, ENGINE_NUMBER_SEQUENCE_KEYPOINT.new(stop.t, stop.v))
	end
	return true, ENGINE_NUMBER_SEQUENCE.new(keypoints)
end

return chrome_props
