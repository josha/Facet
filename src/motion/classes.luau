--!strict
-- Motion classes (ADR-0022 Decision 1; ui-designer spec §1.1): the named
-- `{ dampingRatio, response }` registry that IS the motion vocabulary.
--
-- A feel-carrying call site cites a class NAME. A raw `{ dampingRatio = 1,
-- response = 0.3 }` literal at a `clock:spring` / `clock:chase` / timeline call
-- site is REFUSED with an authoring error that points at `registerClass` —
-- "zero per-call magic numbers", promoted from the ratified Sponsor motion
-- invariant to a framework rule. That is why `resolve` type-checks its argument
-- instead of accepting either shape: a silent inline-params path is how a
-- library ends up with forty slightly different feels.
--
-- The four built-ins are the shapes the Sponsor motion spec ratified, renamed
-- game-agnostically:
--
--   | class       | ζ   | response | owns (the shape, not the game meaning)   |
--   |-------------|-----|----------|------------------------------------------|
--   | container   | 1.0 | 0.35 s   | large surfaces materializing/minimizing  |
--   | object      | 1.0 | 0.28 s   | small manipulable things, flights, chips |
--   | reward      | 0.7 | 0.18 s   | arrival pops, celebration accents        |
--   | decay       | 1.0 | 0.5 s    | scalar feedback dying out on its own     |
--
-- OVERSHOOT IS EARNED: `reward` is the only under-damped class that ships, and
-- it is non-gestural by definition. Liveliness everywhere else comes from
-- inherited gesture velocity (`setVelocity`), never from decorative bounce — so
-- a new class that under-damps is a design decision someone has to make on
-- purpose, in one place, with a name.
--
-- All four are tunable ±30 % without re-gating, and re-registering a built-in
-- name is the sanctioned way to tune one: the registry is the only dial.

-- WHO OWNS THE REGISTRY (ARCH-24, stated 0.10.0). It is module-level and
-- therefore PROCESS-GLOBAL: every core and every surface in the VM shares one
-- vocabulary. That is the DESIGN, not an oversight — a motion name is a design
-- system decision and `registerClass` is the only dial, so a tuning pass has one
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
local textDistance = require("../text_distance")

local classes = {}

export type Class = {
	dampingRatio: number,
	response: number,
}

-- Authored-range validation (ui-designer spec §1.1). ζ > 2 is not a spring any
-- player perceives as motion (it crawls), ζ <= 0 never settles, a response
-- under 50 ms reads as a hard cut (use `snap`), and over 2 s reads as a stall.
local MIN_DAMPING = 0
local MAX_DAMPING = 2
local MIN_RESPONSE = 0.05
local MAX_RESPONSE = 2

local BUILT_IN: { [string]: Class } = {
	container = { dampingRatio = 1.0, response = 0.35 },
	object = { dampingRatio = 1.0, response = 0.28 },
	reward = { dampingRatio = 0.7, response = 0.18 },
	decay = { dampingRatio = 1.0, response = 0.5 },
}

local registry: { [string]: Class } = {}

local function seed()
	registry = {}
	for name, params in BUILT_IN do
		registry[name] = table.freeze({ dampingRatio = params.dampingRatio, response = params.response })
	end
end
seed()

local isFinite = num.isFinite

-- The matrix lives in `src/text_distance.luau` (ARCH-17) — a leaf with no
-- requires, so taking it costs `motion/` none of the independence the old "kept
-- local" note was protecting. THE THRESHOLD STAYS HERE, at the call site below,
-- because it is the half that was never agreed: this caller lowercases both
-- sides and accepts `d <= max(2, floor(#name / 3))`, where `spec_guard` and
-- `themes/package` accept 2 case-sensitively.
local distance = textDistance.distance

-- registered class names, sorted (a stable list for error messages and docs)
function classes.names(): { string }
	local out: { string } = {}
	for name in registry do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

function classes.isRegistered(name: string): boolean
	return registry[name] ~= nil
end

local function nameList(): string
	return table.concat(classes.names(), ", ")
end

local function suggestion(bad: string): string?
	local best: string? = nil
	local bestDistance = math.huge
	local lowerBad = string.lower(bad)
	for _, name in classes.names() do
		local d = distance(lowerBad, string.lower(name))
		if d < bestDistance then
			best, bestDistance = name, d
		end
	end
	-- only volunteer a name when it is genuinely close: a wrong guess is worse
	-- than the full list the message already carries
	if best ~= nil and bestDistance <= math.max(2, math.floor(#best / 3)) then
		return best
	end
	return nil
end

-- Register (or re-tune) a motion class. Validation is authoring-time and loud:
-- an out-of-range class would ship a feel nobody chose.
function classes.registerClass(name: string, params: Class): Class
	if type(name) ~= "string" or name == "" then
		error(`Facet motion.registerClass: a class name must be a non-empty string, got {typeof(name)}`, 0)
	end
	if type(params) ~= "table" then
		error(`Facet motion.registerClass('{name}'): params must be a table \{ dampingRatio, response }`, 0)
	end
	local zeta = params.dampingRatio
	local response = params.response
	if not isFinite(zeta) or zeta <= MIN_DAMPING or zeta > MAX_DAMPING then
		error(
			`Facet motion.registerClass('{name}'): dampingRatio must be a number in ({MIN_DAMPING}, {MAX_DAMPING}], `
				.. `got {tostring(zeta)}. 1.0 is critically damped (no overshoot); below 1.0 overshoots, and overshoot `
				.. `is earned — only 'reward' ships under-damped.`,
			0
		)
	end
	if not isFinite(response) or response <= MIN_RESPONSE or response > MAX_RESPONSE then
		error(
			`Facet motion.registerClass('{name}'): response must be a number of seconds in `
				.. `({MIN_RESPONSE}, {MAX_RESPONSE}], got {tostring(response)}. Below that reads as a hard cut (use `
				.. `snap); above it reads as a stall.`,
			0
		)
	end
	local class = table.freeze({ dampingRatio = zeta, response = response })
	registry[name] = class
	return class
end

-- Resolve a class NAME to its params. Refuses inline params (see the header):
-- one vocabulary, one place to tune it.
function classes.resolve(name: any): Class
	if type(name) == "table" then
		error(
			`Facet motion: a motion class is a NAME, not an inline params table (zero per-call magic numbers). `
				.. `Registered classes: {nameList()}. Register your own with `
				.. `Facet.motion.registerClass("myClass", \{ dampingRatio = 1, response = 0.3 }) and cite that name.`,
			0
		)
	end
	if type(name) ~= "string" then
		error(`Facet motion: a motion class name must be a string, got {typeof(name)}. Registered: {nameList()}.`, 0)
	end
	local class = registry[name]
	if class == nil then
		local did = suggestion(name)
		local hint = if did ~= nil then ` Did you mean '{did}'?` else ""
		error(
			`Facet motion: unknown motion class '{name}'.{hint} Registered classes: {nameList()}. `
				.. `Register a new one with Facet.motion.registerClass before citing it (never a silent fallback).`,
			0
		)
	end
	return class
end

-- Restore the built-in set, dropping everything a game registered. The teardown
-- seam for tests and for a studio tool that reloads a design system.
function classes.reset()
	seed()
end

return classes
