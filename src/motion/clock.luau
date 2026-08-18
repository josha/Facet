--!strict
-- The motion clock (ADR-0022 Decision 1): the one thing that advances time for
-- every motion in a surface, and the reason the whole authority is testable.
--
--   Facet.motion.newClock(core, { now?, motionPolicy? })   -- the motion clock
--                                                           -- ("newMotionClock"
--                                                           -- in ADR-0022 prose)
--
-- `clock:step(dt)` advances every ACTIVE motion and commits every output write
-- inside ONE core transaction — one flush per frame, however many springs moved,
-- so a dense frame costs one propagation instead of twenty. `step()` with no
-- argument derives dt from `now()`; the client driver (RunService.PreRender at
-- the adapter edge) passes the engine's dt straight through, and the headless
-- suite passes a scripted one. This module reads no clock of its own beyond the
-- injectable `now`, and touches no engine global.
--
-- REST COSTS ZERO. A settled motion detaches itself, so `activeCount()` returns
-- to 0 and a step with nothing active returns before it opens a transaction:
-- dozens of resting springs contribute no work and no writes (SF-M8). Nothing
-- else decides a motion is finished — each participant detaches itself.
--
-- Phase order inside a step, and why:
--   0. `pre`     — live-target retargets and timeline beats, BEFORE integration,
--                  so a target read or a beat lands in the frame it belongs to.
--   1. `advance` — integrate. Pure math; writes nothing.
--   2. `commit`  — the output writes, inside the single transaction.
--   3. `post`    — settle/arrival/done events, AFTER the flush, so a handler
--                  reading the value sees the terminus rather than the frame
--                  before it.
-- Each phase iterates the active set in attachment order, bounded by the count
-- at the phase's start: a callback that starts new motion joins from the next
-- phase onward and can never make one step loop.
--
-- Reduced motion is read LIVE from `motionPolicy` (the environment's derived
-- key), so a player toggling it mid-flight changes the next retarget without a
-- remount.

local motionValues = require("./motion")
local chaseLib = require("./chase")
local timelineLib = require("./timeline")
local curvesLib = require("./curves")
local specGuard = require("../spec_guard")

local clock = {}

export type Opts = {
	-- seconds, monotonic. Defaults to os.clock (standard Luau, no engine
	-- dependency); tests and the perf bench script it.
	now: (() -> number)?,
	-- Readable<string>: "full" | "reduced" (env:get("motionPolicy"))
	motionPolicy: any?,
}

export type Stats = {
	steps: number, -- steps that advanced work (a step at rest is not one)
	writes: number, -- backing-signal writes actually committed
	-- ONE transaction per stepped frame, and never more: this is the instrument
	-- that proves the commit phase batches. It equals `steps` on every healthy
	-- frame, and is the RIGHT number rather than the equal one on a quarantined
	-- frame — a `pre`/`advance` callback that throws (verifier RR-1) aborts the
	-- step before the commit phase, so that frame really did open no
	-- transaction, and counting one would report a flush that never happened.
	-- So the invariant is `transactions <= steps`, with equality exactly when no
	-- frame aborted BEFORE the commit phase. Measured 2026-07-28 (Step 5.5,
	-- verifier RR-1-R2): 30 steps under a persistently throwing live target -> 0
	-- transactions.
	--
	-- NOT "equality exactly when lastError() is nil" (the earlier wording, falsified
	-- by verifier RT-2): a POST-phase subscriber error — a throwing onSettle — is
	-- quarantined by fireSettle and sets `lastError` while every frame still
	-- commits, measured at steps 48 = transactions 48 with an error set. Only a
	-- `pre`/`advance` throw costs a transaction, because only it aborts the step
	-- before the commit phase opens one.
	transactions: number,
}

export type Clock = {
	step: (self: Clock, dt: number?) -> (),
	activeCount: (self: Clock) -> number,
	stats: (self: Clock) -> Stats,
	spring: (self: Clock, initial: number, class: any, opts: motionValues.ValueOpts?) -> motionValues.MotionValue,
	counter: (self: Clock, initial: number, class: any, opts: motionValues.ValueOpts?) -> motionValues.MotionValue,
	timer: (self: Clock, spec: motionValues.TimerSpec) -> motionValues.MotionValue,
	glide: (self: Clock, initial: number, spec: motionValues.GlideSpec) -> motionValues.MotionValue,
	tween: (self: Clock, initial: number, curveName: any, opts: motionValues.ValueOpts?) -> motionValues.MotionValue,
	setEasing: (self: Clock, evaluate: (number, string, string) -> number) -> (),
	chase: (self: Clock, opts: chaseLib.Opts) -> chaseLib.Chase,
	timeline: (self: Clock, spec: timelineLib.Spec) -> timelineLib.Timeline,
	isReduced: (self: Clock) -> boolean,
	dispose: (self: Clock) -> (),
	isDisposed: (self: Clock) -> boolean,
}

-- CLOSED OPTS (constitution §4; ARCH-1). `motionPolicy` misspelled means reduced
-- motion is never read and every accessibility toggle is ignored, silently.
local CLOCK_OPTS_KEYS = specGuard.keySet({ "motionPolicy", "now" })

function clock.new(core: any, opts: Opts?): Clock
	specGuard.assertKnownKeys("motion.newClock", opts, CLOCK_OPTS_KEYS, "opts")
	assert(type(core) == "table" and type(core.transaction) == "function", "Facet motion: newClock needs a core")
	local options: Opts = opts or {}
	local now = options.now or os.clock
	local policy = options.motionPolicy

	local active: { motionValues.Entry } = {}
	local values: { [any]: boolean } = {} -- MotionValues owned by this clock
	local lastNow = now()
	local stepping = false
	local disposeRequested = false
	local lastStepError: string? = nil
	local needsCompact = false
	local disposed = false
	-- THE EASING EVALUATOR (ADR-0033). Defaults to the pure twin so a clock is
	-- usable the moment it exists — including in Lune, which has no TweenService —
	-- and `setEasing` swaps in the engine's own `TweenService:GetValue` at the one
	-- bind every Roblox client already makes. It is read PER EVALUATION rather
	-- than captured per value, so installing it at bind time also upgrades values
	-- built before the bind.
	local easing: (number, string, string) -> number = curvesLib.evaluate
	local steps, writes, transactions = 0, 0, 0

	local function compact()
		if not needsCompact or stepping then
			return
		end
		local keep: { motionValues.Entry } = {}
		for _, entry in active do
			if entry.detached ~= true then
				table.insert(keep, entry)
			end
		end
		active = keep
		needsCompact = false
	end

	local internals: motionValues.Internals = {
		core = core,
		attach = function(entry: motionValues.Entry): () -> ()
			assert(not disposed, "Facet motion: cannot attach a motion to a disposed clock")
			entry.detached = false
			table.insert(active, entry)
			return function()
				if entry.detached == true then
					return
				end
				entry.detached = true
				needsCompact = true
				compact() -- deferred while stepping (the phase loops index `active`)
			end
		end,
		isReduced = function(): boolean
			return policy ~= nil and policy:get() == "reduced"
		end,
		countWrite = function()
			writes += 1
		end,
		-- A SET, not an array: a value released early (a row's motion dying with
		-- the row while the surface's clock lives on) must free its slot too, and
		-- motion values own nothing of each other, so disposal order carries no
		-- meaning here — unlike a scope, where reverse order is the contract.
		own = function(resource: any): () -> ()
			values[resource] = true
			return function()
				values[resource] = nil
			end
		end,
		noteError = function(message: string)
			lastStepError = message
		end,
		easing = function(alpha: number, style: string, direction: string): number
			return easing(alpha, style, direction)
		end,
	}

	local self = {}

	function self.step(_: any, dt: number?)
		if disposed then
			return
		end
		if stepping then
			-- a settle/arrival/beat handler called step() from inside a step. Two
			-- integrations for one frame is never what anyone meant, and the phase
			-- loops index a set the inner call would compact underneath them.
			return
		end
		-- refresh the reference time on EVERY step, so a driver that mixes engine
		-- dt with `nil` never sees the gap since the last derived step
		local t = now()
		local elapsed = if dt == nil then t - lastNow else dt
		lastNow = t

		if #active == 0 or not (elapsed > 0) then
			return -- rest, a stalled clock, or a rewound one: no transaction at all
		end
		steps += 1
		stepping = true

		-- QUARANTINE, NEVER WEDGE (verifier RR-1). Every phase runs USER code —
		-- live-target functions, onSettle handlers, timeline beats — and an
		-- escape from any of them used to strand `stepping = true`, turning every
		-- later step into a no-op at the re-entrancy guard: a permanently frozen
		-- clock, and with it every exit cap. The step body is pcall'ed and the
		-- flag ALWAYS clears; a throw costs the rest of that frame's motions one
		-- frame (they resume next step) and is recorded on `lastError`.
		local ok, err = pcall(function()
			local n = #active
			for i = 1, n do
				local entry = active[i]
				if entry ~= nil and entry.detached ~= true and entry.pre ~= nil then
					entry.pre(elapsed)
				end
			end

			n = #active
			for i = 1, n do
				local entry = active[i]
				if entry ~= nil and entry.detached ~= true and entry.advance ~= nil then
					entry.advance(elapsed)
				end
			end

			n = #active
			transactions += 1
			core:transaction(function()
				for i = 1, n do
					local entry = active[i]
					if entry ~= nil and entry.detached ~= true and entry.commit ~= nil then
						entry.commit()
					end
				end
			end)

			n = #active
			for i = 1, n do
				local entry = active[i]
				if entry ~= nil and entry.detached ~= true and entry.post ~= nil then
					entry.post()
				end
			end
		end)
		stepping = false
		if not ok then
			lastStepError = tostring(err)
		end
		compact()
		-- a dispose() that arrived MID-STEP (an onFeedback/onSettle handler tearing
		-- down the owning surface — verifier RR-2) deferred to here, where the
		-- phase loops no longer index the set it clears
		if disposeRequested then
			disposeRequested = false
			self.dispose(self)
		end
	end

	-- the last error a step quarantined, nil when healthy (RR-1's instrument —
	-- mirrors core:lastError so a wedged-motion report is diagnosable)
	function self.lastError(_: any): string?
		return lastStepError
	end

	function self.activeCount(_: any): number
		local n = 0
		for _, entry in active do
			if entry.detached ~= true then
				n += 1
			end
		end
		return n
	end

	function self.stats(_: any): Stats
		return { steps = steps, writes = writes, transactions = transactions }
	end

	function self.isReduced(_: any): boolean
		return internals.isReduced()
	end

	function self.spring(_: any, initial: number, class: any, valueOpts: motionValues.ValueOpts?)
		assert(not disposed, "Facet motion: cannot build a spring on a disposed clock")
		return motionValues.newSpring(internals, initial, class, valueOpts)
	end

	-- the numeral a player reads: a spring that publishes whole numbers and never
	-- overshoots the count it is heading for
	function self.counter(_: any, initial: number, class: any, valueOpts: motionValues.ValueOpts?)
		assert(not disposed, "Facet motion: cannot build a counter on a disposed clock")
		return motionValues.newCounter(internals, initial, class, valueOpts)
	end

	function self.timer(_: any, spec: motionValues.TimerSpec)
		assert(not disposed, "Facet motion: cannot build a timer on a disposed clock")
		return motionValues.newTimer(internals, spec)
	end

	-- the value a fixed cadence RESAMPLES: a re-aimable ramp that crosses every
	-- gap at constant speed. Reach for it whenever a stream of samples has to read
	-- as continuous motion — a spring re-aimed per sample eases out inside each
	-- gap, which the eye reads as stepping (see motion.newGlide's header).
	function self.glide(_: any, initial: number, spec: motionValues.GlideSpec)
		assert(not disposed, "Facet motion: cannot build a glide on a disposed clock")
		return motionValues.newGlide(internals, initial, spec)
	end

	-- DURATION AND A CURVE: the value that arrives ON TIME, in a shape a designer
	-- named. Reach for it when the duration IS the requirement (a spec in
	-- milliseconds, a beat that lands with an audio cue); reach for `spring` for
	-- anything a finger interrupts. The curve is a NAME —
	-- `motion.registerCurve("banner", { duration = 0.4, style = "quad" })` — and an
	-- inline spec table at the call site is refused, exactly as an inline spring
	-- params table is.
	function self.tween(_: any, initial: number, curveName: any, valueOpts: motionValues.ValueOpts?)
		assert(not disposed, "Facet motion: cannot build a tween on a disposed clock")
		return motionValues.newTween(internals, initial, curveName, valueOpts)
	end

	-- Install the easing evaluator. THE ENGINE OWNS THE CURVE (ADR-0033, director
	-- ruling 2026-08-15): on Roblox `src/client/motion_driver.luau` passes
	-- `TweenService:GetValue`, so a game gets the engine's own easing with no
	-- wiring of its own. Until then the pure twin serves, which is what makes the
	-- headless suite possible at all — and the twin is not a second opinion, it is
	-- pinned to the engine by a differential oracle over 33,033 samples
	-- (artifacts/time-based-easing/engine-oracle.md, max |err| 4.73e-7).
	function self.setEasing(_: any, evaluate: (number, string, string) -> number)
		assert(type(evaluate) == "function", "Facet motion: clock:setEasing needs a function (alpha, style, direction)")
		easing = evaluate
	end

	function self.chase(_: any, chaseOpts: chaseLib.Opts)
		assert(not disposed, "Facet motion: cannot build a chase on a disposed clock")
		return chaseLib.new(internals, chaseOpts)
	end

	function self.timeline(_: any, spec: timelineLib.Spec)
		assert(not disposed, "Facet motion: cannot build a timeline on a disposed clock")
		return timelineLib.new(internals, spec)
	end

	-- scope-owned: `scope:own(clock)` disposes it in reverse order with the rest
	-- of the surface. Every value the clock built is disposed here, so the core's
	-- signal counter returns to baseline across mount/reset churn.
	function self.dispose(_: any)
		if disposed then
			return
		end
		-- mid-step disposal defers to the step's own tail (RR-2): clearing
		-- `active` while the phase loops index it crashed out of presenter.tick
		if stepping then
			disposeRequested = true
			return
		end
		disposed = true
		-- snapshot first: each dispose releases its own slot, and modifying the set
		-- under generalized iteration is an error
		local owned: { any } = {}
		for value in values do
			table.insert(owned, value)
		end
		table.clear(values)
		for _, value in owned do
			value:dispose()
		end
		active = {}
		needsCompact = false
	end

	function self.isDisposed(_: any): boolean
		return disposed
	end

	return self :: any
end

return clock
