--!strict
-- Motion CURVES: the named
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
-- authority is testable (engine-free, no globals). So the
-- evaluator is INJECTED exactly the way `now` is, and this module adapts Compose’s pure easing functions
-- for the headless suite. That adapter is pinned to
-- the engine by a differential oracle over a dense generated corpus — a LIVE
-- Studio session, recorded once in `artifacts/time-based-easing/engine-oracle.md`
-- (11 styles x 3 directions x 1,001 alphas; max |twin - engine| 4.73e-7), which
-- the suite then compares against at 50 sampled alphas. It is a RECORDED
-- session and not a headless comparison, because Lune never calls TweenService.
-- This comment used to cite `tools/lune/oracle_easing.luau`, a file that has
-- never existed (dead-code interim finding); the artifact is the oracle.
--
-- A CURVE IS A NAME, never an inline spec — the same refusal `classes.luau`
-- makes, for the same reason: a library gets forty slightly different feels one
-- call site at a time, and `{ duration = 0.4, style = "quad" }` typed at a call
-- site is a feel nobody reviewed. The registry SHIPS EMPTY on purpose. There is
-- no defensible built-in duration: 400 ms is a decision about a specific
-- surface, where `classes.luau`'s four shapes are decisions about physics that
-- generalize. Registering a curve IS the act of choosing, once, with a name.

-- WHO OWNS THE REGISTRY (stated 0.10.0). It is module-level and
-- therefore PROCESS-GLOBAL: every core and every surface in the VM shares one
-- vocabulary. That is the DESIGN, not an oversight — a motion name is a design
-- system decision and `registerCurve` is the only dial, so a tuning pass has one
-- place to change and every surface follows. The consequence, written down so
-- nobody has to discover it: two independent Facet consumers in one VM share
-- these names, and whoever registers a name LAST wins it. `reset` is the
-- teardown seam; `tests/process_globals.spec.luau` pins the sharing and the
-- last-writer rule as behaviour rather than leaving them to be found.
--
-- AND `reset` IS THE SHARP EDGE, not part of the dial (R5 review §4-6): it is
-- not a write to one name, it is a write to ALL of them, so one consumer
-- calling it deletes another consumer's vocabulary and the other consumer's
-- next motion call THROWS. It exists for tests and for a studio tool reloading
-- a design system — both single-consumer situations. A second Facet consumer in
-- the same VM should not call it.

local num = require("../num")
local Compose = require("../vendor/compose/core")
local textDistance = require("../text_distance")

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

local isFinite = num.isFinite

-- Compose owns the easing functions, and it owns all three DIRECTIONS of each
-- one: `outQuad` and `inOutQuad` are entries in its frozen table, not a
-- composition Facet has to redo. The one curve Facet overrides is elastic —
-- TweenService's period is 1/3.25 where Compose's canonical curve uses 0.3, and
-- the recorded engine oracle is what this evaluator is pinned to. See
-- docs/research/2026-08-15-roblox-easing-engine-facts.md.
local ELASTIC_PERIOD = 1 / 3.25
local function elasticIn(t: number): number
	if t == 0 or t == 1 then
		return t
	end
	local p = ELASTIC_PERIOD
	return -(math.pow(2, 10 * (t - 1)) * math.sin(((t - 1) - p / 4) * (2 * math.pi) / p))
end

-- `out` flips the `in` half; `inOut` compresses it into [0, .5] and mirrors it
-- into [.5, 1]. Compose spells both combinators, but does not export them, so
-- the elastic override composes its own. Every other style reads Compose's.
local easing = Compose.easing
local EASED: { [string]: { [string]: (number) -> number } } = {
	-- every direction of linear is the identity
	linear = { ["in"] = easing.linear, out = easing.linear, inOut = easing.linear },
	sine = { ["in"] = easing.inSine, out = easing.outSine, inOut = easing.inOutSine },
	quad = { ["in"] = easing.inQuad, out = easing.outQuad, inOut = easing.inOutQuad },
	cubic = { ["in"] = easing.inCubic, out = easing.outCubic, inOut = easing.inOutCubic },
	quart = { ["in"] = easing.inQuart, out = easing.outQuart, inOut = easing.inOutQuart },
	quint = { ["in"] = easing.inQuint, out = easing.outQuint, inOut = easing.inOutQuint },
	exponential = { ["in"] = easing.inExpo, out = easing.outExpo, inOut = easing.inOutExpo },
	circular = { ["in"] = easing.inCirc, out = easing.outCirc, inOut = easing.inOutCirc },
	back = { ["in"] = easing.inBack, out = easing.outBack, inOut = easing.inOutBack },
	bounce = { ["in"] = easing.inBounce, out = easing.outBounce, inOut = easing.inOutBounce },
	elastic = {
		["in"] = elasticIn,
		out = function(t: number): number
			return 1 - elasticIn(1 - t)
		end,
		inOut = function(t: number): number
			if t < 0.5 then
				return elasticIn(t * 2) / 2
			end
			return 1 - elasticIn((1 - t) * 2) / 2
		end,
	},
}

-- The pure evaluator: `(alpha, style, direction) -> eased alpha`. Signature is
-- deliberately identical to the engine's `TweenService:GetValue`, so the two are
-- swappable and the oracle can compare them argument for argument.
function curves.evaluate(alpha: number, style: string, direction: string): number
	local directions = EASED[style]
	local f = if directions ~= nil then directions[direction] else nil
	if f == nil then
		return alpha -- unreachable through `resolve`, which validates both names
	end
	local t = if alpha < 0 then 0 elseif alpha > 1 then 1 else alpha
	local r = f(t)
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
		local did = textDistance.nearestFolded(name, curves.names())
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
