--!strict
-- Motion CURVES (ADR-0033; fusion-comparison.md §5 G-1): the named
-- `{ duration, style, direction }` registry that gives the motion authority a
-- duration that means what it says.
--
-- WHY THIS EXISTS AT ALL, given springs. A spring approaches its target
-- asymptotically: `response` is a feel dial and settle time is emergent, so a
-- cooldown sweep, a bar that must empty as an audio cue lands, or a designer's
-- "over 400 ms, quad ease-out" cannot be commanded. `clock:timer` and
-- `clock:glide` already own DURATION — but both are strictly LINEAR, and the
-- shape between the two endpoints is the half that was missing.
--
-- (A CLAIM THIS HEADER USED TO MAKE, WITHDRAWN 2026-08-15 by the RascalRally
-- consumer rider: that the game's `CommitBeatModel` `p^1.6` ramp had been
-- FLATTENED to a linear `clock:timer` in its Facet port for want of a curve.
-- It had not. That exponent shapes a blink FREQUENCY, is integrated closed-form,
-- and is called only by the legacy modules; the port's linear timer faithfully
-- matches the linear plate ramp legacy actually paints, and the blink was removed
-- by a director ruling rather than lost. No shipped consumer had a curve taken
-- away from it. The primitive stands on what it makes possible — a duration that
-- arrives on time — not on a regression that turned out not to exist.)
--
-- THE ENGINE OWNS THE CURVE (director ruling 2026-08-15, "use Roblox's animation
-- system wherever possible"). `TweenService:GetValue(alpha, style, direction)` is
-- a PURE evaluator — it takes a number and returns a number, touching no Instance
-- — so unlike `TweenService:Create` it can drive a value Facet owns. On Roblox
-- it IS the evaluator: `src/client/motion_driver.luau` installs it on the
-- presenter's clock at the one bind every client already makes, so a game gets
-- the engine's own easing with no wiring. `Enum.EasingStyle` therefore defines
-- the vocabulary, and a style Roblox adds later is one line in `STYLES` away.
--
-- ...AND WHY A PURE FALLBACK STILL SHIPS. Lune has no `TweenService`, and
-- `clock:step(dt)` under a scripted clock is the entire reason the motion
-- authority is testable (ADR-0022 Decision 1: engine-free, no globals). So the
-- evaluator is INJECTED exactly the way `now` is, and this module carries a pure
-- twin for the headless suite. The twin is not a second opinion: it is pinned to
-- the engine by a differential oracle over a dense generated corpus
-- (`tools/lune/oracle_easing.luau` + the Studio probe recorded in
-- `artifacts/time-based-easing/engine-oracle.md`), and any style whose twin
-- drifts is a red check, not a rounding difference someone lives with.
--
-- A CURVE IS A NAME, never an inline spec — the same refusal `classes.luau`
-- makes, for the same reason: a library gets forty slightly different feels one
-- call site at a time, and `{ duration = 0.4, style = "quad" }` typed at a call
-- site is a feel nobody reviewed. The registry SHIPS EMPTY on purpose. There is
-- no defensible built-in duration: 400 ms is a decision about a specific
-- surface, where `classes.luau`'s four shapes are decisions about physics that
-- generalize. Registering a curve IS the act of choosing, once, with a name.

local curves = {}

export type Curve = {
	duration: number,
	style: string,
	direction: string,
}

-- `Enum.EasingStyle:GetEnumItems()`, read live from the engine 2026-08-15 (all
-- eleven). Stored as data because this module may not touch an engine global;
-- `tests/motion_tween.spec.luau` pins the list and the Studio oracle re-reads the
-- enum, so an engine addition surfaces as a failing oracle rather than silence.
local STYLES: { string } = {
	"linear",
	"sine",
	"back",
	"quad",
	"quart",
	"quint",
	"bounce",
	"elastic",
	"exponential",
	"circular",
	"cubic",
}

local DIRECTIONS: { string } = { "in", "out", "inOut" }

-- the engine spells them capitalized; the adapter needs the exact enum name and
-- an author should not have to. `"quad"` -> `"Quad"`, `"inOut"` -> `"InOut"`.
local ENGINE_STYLE: { [string]: string } = {}
for _, name in STYLES do
	ENGINE_STYLE[name] = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
end
local ENGINE_DIRECTION: { [string]: string } = { ["in"] = "In", out = "Out", inOut = "InOut" }

local STYLE_SET: { [string]: boolean } = {}
for _, name in STYLES do
	STYLE_SET[name] = true
end
local DIRECTION_SET: { [string]: boolean } = {}
for _, name in DIRECTIONS do
	DIRECTION_SET[name] = true
end

-- Authored-range validation, mirroring `classes.luau`'s reasoning. Under 50 ms
-- reads as a hard cut (use `snap`); over 2 s reads as a stall. A ZERO duration is
-- legal here where it is not for a class, because a curve is also how a caller
-- says "arrive instantly on this beat" in a data-driven table.
local MIN_DURATION = 0
local MAX_DURATION = 2

curves.STYLES = table.freeze(STYLES)
curves.DIRECTIONS = table.freeze(DIRECTIONS)

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- ===== the pure twin =======================================================
-- Penner's canonical set, which is what `TweenService` implements. Every entry
-- is the "in" form; `out` and `inOut` are DERIVED from it below, so a style can
-- only be wrong in one place. Constants are the standard ones and are pinned
-- against the engine by the oracle, not by belief.
local BACK_S = 1.70158
-- NOT Penner's 0.3, and this is exactly the kind of thing belief gets wrong:
-- the pure twin was written with 0.3 and the differential oracle reddened
-- `elastic` in all three directions at max |err| 0.0248 while the other eight
-- styles agreed to < 1e-4. Fitting the period against `TweenService:GetValue`
-- over 201 alphas landed on 1/p = 3.250024, i.e. p = 1/3.25 exactly, which drops
-- the error to 7.4e-6 (measured live 2026-08-15; recorded in
-- docs/research/2026-08-15-roblox-easing-engine-facts.md).
local ELASTIC_PERIOD = 1 / 3.25

local easeIn: { [string]: (number) -> number } = {
	linear = function(t: number): number
		return t
	end,
	sine = function(t: number): number
		return 1 - math.cos((t * math.pi) / 2)
	end,
	quad = function(t: number): number
		return t * t
	end,
	cubic = function(t: number): number
		return t * t * t
	end,
	quart = function(t: number): number
		return t * t * t * t
	end,
	quint = function(t: number): number
		return t * t * t * t * t
	end,
	exponential = function(t: number): number
		return if t == 0 then 0 else math.pow(2, 10 * (t - 1))
	end,
	circular = function(t: number): number
		return 1 - math.sqrt(math.max(0, 1 - t * t))
	end,
	back = function(t: number): number
		return t * t * ((BACK_S + 1) * t - BACK_S)
	end,
	elastic = function(t: number): number
		if t == 0 or t == 1 then
			return t
		end
		local p = ELASTIC_PERIOD
		return -(math.pow(2, 10 * (t - 1)) * math.sin(((t - 1) - p / 4) * (2 * math.pi) / p))
	end,
	bounce = function(t: number): number
		-- bounce is authored OUT-first (the ball falls and rebounds); the `in`
		-- form is its mirror, which is why this one entry inverts twice.
		local u = 1 - t
		local v: number
		if u < 1 / 2.75 then
			v = 7.5625 * u * u
		elseif u < 2 / 2.75 then
			u -= 1.5 / 2.75
			v = 7.5625 * u * u + 0.75
		elseif u < 2.5 / 2.75 then
			u -= 2.25 / 2.75
			v = 7.5625 * u * u + 0.9375
		else
			u -= 2.625 / 2.75
			v = 7.5625 * u * u + 0.984375
		end
		return 1 - v
	end,
}

-- The pure evaluator: `(alpha, style, direction) -> eased alpha`. Signature is
-- deliberately identical to the engine's `TweenService:GetValue`, so the two are
-- swappable and the oracle can compare them argument for argument.
function curves.evaluate(alpha: number, style: string, direction: string): number
	local f = easeIn[style]
	if f == nil then
		return alpha -- unreachable through `resolve`, which validates the style
	end
	local t = if alpha < 0 then 0 elseif alpha > 1 then 1 else alpha
	local r: number
	if direction == "in" then
		r = f(t)
	elseif direction == "out" then
		r = 1 - f(1 - t)
	elseif t < 0.5 then
		-- inOut: the `in` half compressed into [0, .5], mirrored into [.5, 1]
		r = f(t * 2) / 2
	else
		r = 1 - f((1 - t) * 2) / 2
	end
	-- NEGATIVE ZERO IS NOT ZERO TO EVERY READER, and `back`/`in` produces one at
	-- t = 0 (`0 * 0 * -1.70158`). It compares equal, so the write gate upstream
	-- lets it through as "unchanged" — but it formats as "-0.000000" and, in a
	-- property a dump or a golden capture reads back, it is a diff nobody caused.
	-- Caught by the both-ends anchor check, which is exactly what that check is
	-- for. `r == 0` is true for -0, so this normalises without a branch on sign.
	return if r == 0 then 0 else r
end

-- the engine's own enum NAMES for a resolved curve, for the adapter edge that
-- builds `Enum.EasingStyle[...]`. Kept here so the mapping lives beside the
-- vocabulary it mirrors rather than in the client module that spends it.
function curves.engineNames(curve: Curve): (string, string)
	return ENGINE_STYLE[curve.style], ENGINE_DIRECTION[curve.direction]
end

-- ===== the registry ========================================================

local registry: { [string]: Curve } = {}

-- Bounded Levenshtein, the same shape `classes.luau` uses (kept local for the
-- same reason: motion owes nothing to the blueprint layer).
local function distance(a: string, b: string): number
	local la, lb = #a, #b
	if la == 0 then
		return lb
	end
	if lb == 0 then
		return la
	end
	local prev = table.create(lb + 1, 0)
	local cur = table.create(lb + 1, 0)
	for j = 0, lb do
		prev[j + 1] = j
	end
	for i = 1, la do
		cur[1] = i
		local ca = string.byte(a, i)
		for j = 1, lb do
			local cost = if ca == string.byte(b, j) then 0 else 1
			cur[j + 1] = math.min(cur[j] + 1, prev[j + 1] + 1, prev[j] + cost)
		end
		prev, cur = cur, prev
	end
	return prev[lb + 1]
end

function curves.names(): { string }
	local out: { string } = {}
	for name in registry do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

function curves.isRegistered(name: string): boolean
	return registry[name] ~= nil
end

local function nameList(): string
	local list = curves.names()
	if #list == 0 then
		return "(none yet — the curve registry ships EMPTY, by decision)"
	end
	return table.concat(list, ", ")
end

local function suggestion(bad: string): string?
	local best: string? = nil
	local bestDistance = math.huge
	local lowerBad = string.lower(bad)
	for _, name in curves.names() do
		local d = distance(lowerBad, string.lower(name))
		if d < bestDistance then
			best, bestDistance = name, d
		end
	end
	if best ~= nil and bestDistance <= math.max(2, math.floor(#best / 3)) then
		return best
	end
	return nil
end

local function styleList(): string
	return table.concat(STYLES, ", ")
end

-- Register (or re-tune) a curve. Validation is authoring-time and loud, exactly
-- as `registerClass` is: an out-of-range duration or a misspelled style would
-- ship a feel nobody chose, and a silent fallback to linear is the worst of the
-- available outcomes (it looks like it worked).
function curves.registerCurve(name: string, spec: Curve): Curve
	if type(name) ~= "string" or name == "" then
		error(`Facet motion.registerCurve: a curve name must be a non-empty string, got {typeof(name)}`, 0)
	end
	if type(spec) ~= "table" then
		error(`Facet motion.registerCurve('{name}'): spec must be a table \{ duration, style, direction? }`, 0)
	end
	local duration = spec.duration
	if not isFinite(duration) or duration < MIN_DURATION or duration > MAX_DURATION then
		error(
			`Facet motion.registerCurve('{name}'): duration must be a number of seconds in `
				.. `[{MIN_DURATION}, {MAX_DURATION}], got {tostring(duration)}. A duration is the whole point of a curve `
				.. `— under ~50 ms it reads as a hard cut (use snap) and over 2 s it reads as a stall.`,
			0
		)
	end
	local style = spec.style
	if type(style) ~= "string" or not STYLE_SET[style] then
		error(
			`Facet motion.registerCurve('{name}'): unknown easing style '{tostring(style)}'. `
				.. `The vocabulary is Roblox's own Enum.EasingStyle, spelled lower-camel: {styleList()}.`,
			0
		)
	end
	local direction = spec.direction
	if direction == nil then
		direction = "out" -- the overwhelmingly common UI shape: fast, then settle
	end
	if type(direction) ~= "string" or not DIRECTION_SET[direction] then
		error(
			`Facet motion.registerCurve('{name}'): unknown easing direction '{tostring(spec.direction)}'. `
				.. `Use "in", "out" (the default) or "inOut".`,
			0
		)
	end
	local curve = table.freeze({ duration = duration, style = style, direction = direction :: string })
	registry[name] = curve
	return curve
end

-- Resolve a curve NAME to its spec. Refuses an inline spec table (see the
-- header): one vocabulary, one place to tune it.
function curves.resolve(name: any): Curve
	if type(name) == "table" then
		error(
			`Facet motion: a motion curve is a NAME, not an inline spec table (zero per-call magic numbers). `
				.. `Registered curves: {nameList()}. Register yours with `
				.. `Facet.motion.registerCurve("banner", \{ duration = 0.4, style = "quad", direction = "out" }) `
				.. `and cite that name.`,
			0
		)
	end
	if type(name) ~= "string" then
		error(`Facet motion: a motion curve name must be a string, got {typeof(name)}. Registered: {nameList()}.`, 0)
	end
	local curve = registry[name]
	if curve == nil then
		local did = suggestion(name)
		local hint = if did ~= nil then ` Did you mean '{did}'?` else ""
		error(
			`Facet motion: unknown motion curve '{name}'.{hint} Registered curves: {nameList()}. `
				.. `Register one with Facet.motion.registerCurve before citing it (never a silent fallback). `
				.. `A curve is \{ duration, style, direction? } — a motion CLASS ({"a spring"}) is the other vocabulary, `
				.. `and clock:spring is where those live.`,
			0
		)
	end
	return curve
end

-- Drop everything registered. The teardown seam for tests and for a studio tool
-- that reloads a design system — and unlike `classes.reset` it restores nothing,
-- because there is nothing built in to restore.
function curves.reset()
	registry = {}
end

return curves
