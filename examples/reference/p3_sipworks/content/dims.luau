--!strict
-- Sipworks' DIMENSION CONSTRUCTORS — one spelling for each shape a box takes.
--
-- WHAT MOVED OUT OF HERE (ADR-0042). This file used to be `content/metrics.luau`
-- and carried the proof's structural NUMBERS as well, under a comment saying
-- what they wanted to be: *"The spec states these as dotted theme-metric names
-- (`metrics.sip.rowArt`). They cannot be."* They can now — they are declared in
-- `init.luau` as the `app.sip.*` namespace and spelled by NAME at every call
-- site — so nothing here holds a dimension any more. What is left is the shape
-- vocabulary: seven constructors, each with the reason it exists rather than its
-- neighbour.

local dims = {}

function dims.fixed(px: number): { [string]: any }
	return { type = "fixed", px = px }
end

dims.fill = { type = "fill", weight = 1 }

function dims.aspect(ratio: number): { [string]: any }
	return { type = "aspect", ratio = ratio }
end

function dims.minMax(min: number, preferred: number, max: number): { [string]: any }
	return { type = "minMax", min = min, preferred = preferred, max = max }
end

-- A FLOOR WITH NO PREFERENCE: at least `min`, otherwise as tall as the content
-- needs. This is the shape a band takes when the THEME owns the height of what
-- stands in it — a `control`'s size plus whatever content insets its chrome
-- reserves (Fantasy Parchment reserves 20px per side, and a band pinned to the
-- spec's 64px left the CTA's label a 12px box).
function dims.atLeast(min: number, max: number): { [string]: any }
	return { type = "minMax", min = min, max = max }
end

function dims.percent(fraction: number): { [string]: any }
	return { type = "percent", fraction = fraction }
end

-- A CAP, NOT A SIZE. Every fixed card box in §4 is a DESKTOP size, and a fixed
-- box is the defect class a device pass finds: the botanical card asked for
-- 360x460 on a 320x640 phone and painted 40px outside the viewport (found by
-- `controller.diagnostics()`, not by a screenshot). These boxes take a share of
-- what they were given and stop growing at the spec's number.
function dims.percentMax(fraction: number, max: number): { [string]: any }
	return { type = "percent", fraction = fraction, max = max }
end

return dims
