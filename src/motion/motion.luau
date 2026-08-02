--!strict
-- MotionValue — the public value API of the motion authority (ADR-0022
-- Decision 1). `clock:spring(0, "object")` hands back a value that IS a
-- `Readable<number>`: the returned table is the backing core signal itself,
-- augmented with the motion verbs. So `core:observe(value, …)`, `use(value)`
-- inside a memo, and a bound blueprint prop all work on it unchanged — motion
-- needs no second binding concept, and a screen cannot tell an animated number
-- from any other reactive number.
--
-- The verbs and their invariants:
--
--   * `setTarget(number)`      — aim; never touches value or velocity, so an
--                                interrupt continues from where it is at the
--                                speed it has (I-1).
--   * `setTarget(function)`    — LIVE TARGET: the function is re-read EVERY
--                                step, so a flight lands on a row that moved
--                                mid-flight (I-3). If the function returns nil
--                                (the row unmounted) the aim freezes on the last
--                                good read and the motion resolves by settle.
--   * `setVelocity(px/s)`      — the gesture→animation handoff; there is no
--                                "restart" verb anywhere in this module.
--   * `onSettle(fn)`           — fires EXACTLY ONCE per arrival, after the
--                                frame's writes have been committed, so a
--                                handler reads the terminus.
--   * `snap(v)`                — placement: value+target set, velocity zeroed,
--                                write committed immediately. NOT an arrival, so
--                                it fires no settle event (nothing was aimed at).
--   * `stop()`                 — abandon the aim where the value stands. Also
--                                not an arrival: no settle event.
--
-- REDUCED MOTION (I-4, information parity — an invariant of the authority, not a
-- caller's courtesy):
--
--   * decorative (the default): `setTarget` places the value at the terminal
--     value INSTANTLY and fires the same settle event on the same frame. The
--     write lands immediately rather than on the next step, because RM parity
--     must never depend on a clock driver being attached.
--   * informational (`kind = "informational"`: depleting rings, bars,
--     countdowns): the value KEEPS RUNNING to the same wall-clock terminus, but
--     its output writes quantize to `quantum` (250 ms default) ticks — the
--     stepped policy. Decorative motion snaps; informational motion steps.
--     Nothing is ever "skipped": that is how RM deletes information.
--   * `reducedMotion = "fade"` is a CALLER DECLARATION that the consumer pairs
--     the instant placement with a transparency fade at the destination. The
--     motion value itself still snaps; this module never paints.
--
-- AUTHORITY: this module drives signals only. It never writes solver geometry
-- and never writes a native-sheet-owned property — the renderer's presentation
-- channel is the only write site downstream (ADR-0022 Decision 2).

local springLib = require("./spring")
local classes = require("./classes")

local motion = {}

-- informational RM tick (ui-designer spec §1.5: 250 ms default, [100–500] ms)
local DEFAULT_QUANTUM = 0.25

local KINDS: { [string]: boolean } = { decorative = true, informational = true }
local REDUCED_FORMS: { [string]: boolean } = { snap = true, fade = true }

-- One participant in a clock step. Every hook is optional; an entry leaves the
-- active set by calling the detach function `attach` returned (nothing else
-- decides that a motion is finished).
export type Entry = {
	-- retargets and timeline beats, BEFORE integration, so a live-target read or
	-- a beat lands in the frame it was scheduled for
	pre: ((dt: number) -> ())?,
	advance: ((dt: number) -> ())?,
	-- the output write; runs inside the clock's single per-step transaction
	commit: (() -> ())?,
	-- post-commit events (settle, arrival, done): observers have already seen
	-- the committed values
	post: (() -> ())?,
	detached: boolean?,
}

-- The clock's private seam, handed to every motion it builds.
export type Internals = {
	core: any,
	attach: (entry: Entry) -> () -> (),
	isReduced: () -> boolean,
	countWrite: () -> (),
	-- hand the clock a resource to dispose with it; the returned function
	-- releases it early (a value disposed on its own must not hold a slot)
	own: (resource: any) -> () -> (),
	-- report a quarantined consumer-callback error onto the clock's lastError
	-- channel (settle fan-out runs outside the step pcall on the placeNow path)
	noteError: (message: string) -> (),
}

export type ValueOpts = {
	eps: number?,
	kind: string?, -- "decorative" (default) | "informational"
	quantum: number?, -- informational RM tick in seconds
	reducedMotion: string?, -- "snap" (default) | "fade" — a caller declaration
}

export type TimerSpec = {
	from: number,
	to: number,
	duration: number,
	-- a timer's content IS elapsed time, so it defaults to "informational": under
	-- reduced motion it keeps depleting (quantized) instead of jumping to its end
	kind: string?,
	quantum: number?,
}

export type MotionValue = {
	kind: string, -- "signal": a MotionValue IS a Readable<number>
	get: (self: MotionValue) -> number,
	set: (self: MotionValue, value: number) -> (),
	dispose: (self: MotionValue) -> (),
	setTarget: (self: MotionValue, target: number | (() -> number?)) -> (),
	setVelocity: (self: MotionValue, velocity: number) -> (),
	onSettle: (self: MotionValue, fn: () -> ()) -> () -> (),
	stop: (self: MotionValue) -> (),
	snap: (self: MotionValue, value: number) -> (),
	isSettled: (self: MotionValue) -> boolean,
	getTarget: (self: MotionValue) -> number,
	getVelocity: (self: MotionValue) -> number,
	motionKind: (self: MotionValue) -> string,
	reducedForm: (self: MotionValue) -> string,
}

-- The model under a MotionValue. Two exist: a spring and a linear timer. The
-- value layer (writes, quantization, settle events, RM substitution, lifetime)
-- is shared, so the two can never drift apart on any of it.
type Driver = {
	advance: (dt: number) -> boolean, -- integrate; returns settled
	place: (value: number) -> (), -- come to rest ON value (RM snap, stop, snap)
	value: () -> number,
	terminus: () -> number, -- what it is heading for (RM reads this)
	settled: () -> boolean,
	aim: ((value: number) -> ())?, -- springs only
	seed: ((velocity: number) -> ())?, -- springs only
	velocity: () -> number,
}

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function newValue(
	internals: Internals,
	initial: number,
	opts: ValueOpts?,
	driver: Driver,
	autoStart: boolean
): MotionValue
	local options: ValueOpts = opts or {}
	local motionKind = options.kind or "decorative"
	if not KINDS[motionKind] then
		error(
			`LuauUI motion: unknown motion kind '{tostring(motionKind)}'. Use "decorative" (default: reduced motion `
				.. `snaps it) or "informational" (reduced motion keeps it running, quantized to {DEFAULT_QUANTUM}s).`,
			0
		)
	end
	local reducedForm = options.reducedMotion or "snap"
	if not REDUCED_FORMS[reducedForm] then
		error(
			`LuauUI motion: unknown reducedMotion form '{tostring(reducedForm)}'. Use "snap" (default) or "fade" `
				.. `(a declaration that the caller pairs the instant placement with a transparency fade).`,
			0
		)
	end
	local quantum = if isFinite(options.quantum) and (options.quantum :: number) > 0
		then options.quantum :: number
		else DEFAULT_QUANTUM

	local core = internals.core
	-- the value IS the signal: augmented, not wrapped (see the header)
	local value = core:signal(initial)
	local signalDispose = value.dispose
	-- registered with the clock before the verbs are attached, so `release` is a
	-- real upvalue for dispose() below
	local release = internals.own(value)

	local sinceWrite = 0
	local settledNow = false
	local targetFn: (() -> number?)? = nil
	local detach: (() -> ())? = nil
	local disposed = false
	-- subscriptions are boxes so an unsubscribe during a fire is safe
	local subs: { { fn: (() -> ())? } } = {}

	-- The write gate compares against what the SIGNAL currently holds, not
	-- against the last value motion wrote: an unmoved motion writes nothing (rest
	-- costs zero), and a foreign write is corrected on the next frame the motion
	-- is ACTIVE (verifier RR-9: a settled motion has left the clock, so a foreign
	-- write while at rest STANDS until something re-targets — the signal is the
	-- consumer's to share; the gate exists so an active motion never yields to
	-- one, not to police writes while asleep).
	local function write()
		local v = driver.value()
		if v ~= value:get() then
			value:set(v)
			internals.countWrite()
		end
	end

	-- QUARANTINE, NEVER STARVE (verifier RR-12-R1): settle fires once per
	-- arrival, so a throwing subscriber must not cost the ones after it their
	-- only notification. Each call is pcall'ed; errors land on clock:lastError().
	local function fireSettle()
		local snapshot = table.clone(subs)
		for _, box in snapshot do
			local fn = box.fn
			if fn ~= nil then
				local ok, err = pcall(fn)
				if not ok then
					internals.noteError(`LuauUI motion: onSettle subscriber error: {tostring(err)}`)
				end
			end
		end
	end

	local function leave()
		if detach ~= nil then
			detach()
			detach = nil
		end
	end

	-- come to rest on `v` right now. `announce` distinguishes an arrival
	-- (reduced-motion substitution for a real flight) from a placement (snap).
	local function placeNow(v: number, announce: boolean)
		targetFn = nil
		leave()
		driver.place(v)
		settledNow = false
		sinceWrite = 0
		write()
		if announce then
			fireSettle()
		end
	end

	-- springs are re-aimable; a timer is not (setTarget raises there, so this is
	-- only ever a no-op on the timer path)
	local function aimAt(v: number)
		local aim = driver.aim
		if aim ~= nil then
			aim(v)
		end
	end

	local function advance(dt: number)
		if targetFn ~= nil then
			local read = targetFn()
			if isFinite(read) then
				aimAt(read :: number) -- live target, re-read every step (I-3)
			elseif read == nil then
				targetFn = nil -- the target vanished: settle on the last good aim
			end
		end
		sinceWrite += dt
		settledNow = driver.advance(dt)
	end

	local function commit()
		-- informational values under reduced motion write on `quantum` ticks
		-- instead of every frame — same terminus, coarser sweep (F10 stepped
		-- policy). The terminal write always lands.
		if not settledNow and motionKind == "informational" and internals.isReduced() and sinceWrite < quantum then
			return
		end
		sinceWrite = 0
		write()
	end

	local function post()
		if settledNow then
			leave()
			fireSettle()
		end
	end

	local function ensureActive()
		if disposed or detach ~= nil then
			return
		end
		settledNow = false
		sinceWrite = 0
		detach = internals.attach({ advance = advance, commit = commit, post = post })
	end

	function value.setTarget(_: any, target: any)
		if disposed then
			return
		end
		if driver.aim == nil then
			error(
				"LuauUI motion: this value is a timer — it has no target. A timer runs from `from` to `to` over "
					.. "`duration`; use clock:spring for a value you re-aim.",
				0
			)
		end
		local fn: (() -> number?)? = nil
		local aimed: number
		if type(target) == "function" then
			fn = target
			local read = target()
			if not isFinite(read) then
				return -- nothing to aim at yet; keep the current aim
			end
			aimed = read
		elseif isFinite(target) then
			aimed = target
		else
			return -- keep the last good aim (non-finite in, nothing out)
		end

		if internals.isReduced() and motionKind ~= "informational" then
			-- instant placement at the terminal value, and the SAME settle event
			-- on the same frame: information parity, zero duration (I-4)
			placeNow(aimed, true)
			return
		end
		targetFn = fn
		aimAt(aimed)
		ensureActive()
	end

	function value.setVelocity(_: any, velocity: number)
		if disposed then
			return
		end
		if driver.seed == nil then
			error("LuauUI motion: this value is a timer — there is no velocity to seed.", 0)
		end
		if not isFinite(velocity) then
			return
		end
		if internals.isReduced() and motionKind ~= "informational" then
			return -- nothing is animating under reduced motion: no seam to smooth
		end
		local seed = driver.seed
		if seed ~= nil then
			seed(velocity)
		end
		ensureActive()
	end

	function value.onSettle(_: any, fn: () -> ()): () -> ()
		local box: { fn: (() -> ())? } = { fn = fn }
		table.insert(subs, box)
		return function()
			-- remove the box, not just its fn (verifier RR-10): a long-lived value
			-- whose consumers churn subscriptions must not grow the list forever
			box.fn = nil
			local index = table.find(subs, box)
			if index ~= nil then
				table.remove(subs, index)
			end
		end
	end

	function value.stop(_: any)
		if disposed then
			return -- RR-11: stopping a disposed value is a no-op, never a revival
		end
		-- abandon the aim where the value stands: no settle event, because
		-- nothing was reached
		targetFn = nil
		leave()
		driver.place(driver.value())
		settledNow = false
		write()
	end

	function value.snap(_: any, v: number)
		if disposed or not isFinite(v) then
			return
		end
		placeNow(v, false) -- placement, not arrival
	end

	function value.isSettled(_: any): boolean
		return driver.settled()
	end

	function value.getTarget(_: any): number
		return driver.terminus()
	end

	function value.getVelocity(_: any): number
		return driver.velocity()
	end

	function value.motionKind(_: any): string
		return motionKind
	end

	function value.reducedForm(_: any): string
		return reducedForm
	end

	function value.dispose(_: any)
		if disposed then
			return
		end
		disposed = true
		leave()
		table.clear(subs)
		release()
		signalDispose(value)
	end

	if autoStart then
		-- a timer starts the moment it exists. Under reduced motion a decorative
		-- one is already over; an informational one steps (quantized).
		if driver.settled() or (internals.isReduced() and motionKind ~= "informational") then
			-- Already at its terminus before the caller has finished wiring: the
			-- STATE lands now, but the arrival is announced on the next step so a
			-- consumer subscribing on the very next line cannot miss the event.
			-- Information parity is about what the consumer can observe, not only
			-- about what the value reads.
			placeNow(driver.terminus(), false)
			detach = internals.attach({
				post = function()
					leave()
					fireSettle()
				end,
			})
		else
			ensureActive()
		end
	end

	return value :: any
end

-- clock:spring(initial, className, opts?) — the interruptible value.
function motion.newSpring(internals: Internals, initial: number, class: any, opts: ValueOpts?): MotionValue
	local params = classes.resolve(class)
	local options: ValueOpts = opts or {}
	local sp = springLib.new(initial, params, options.eps)
	local driver: Driver = {
		advance = function(dt: number): boolean
			local settled = sp:step(dt)
			if settled then
				-- land EXACTLY on the target on the settling frame (inside the
				-- solver epsilon, so it is invisible) — a resting value that
				-- reads 99.9997 is a rounding bug waiting to happen downstream
				sp:snap(sp:getTarget())
			end
			return settled
		end,
		place = function(v: number)
			sp:snap(v)
		end,
		value = function(): number
			return sp:get()
		end,
		terminus = function(): number
			return sp:getTarget()
		end,
		settled = function(): boolean
			return sp:isSettled()
		end,
		aim = function(v: number)
			sp:setTarget(v)
		end,
		seed = function(v: number)
			sp:setVelocity(v)
		end,
		velocity = function(): number
			return sp:getVelocity()
		end,
	}
	return newValue(internals, initial, options, driver, false)
end

-- clock:counter(initial, className, opts?) — a spring whose published value is a
-- WHOLE NUMBER, for the one thing a raw spring cannot drive honestly: a numeral
-- a player reads.
--
-- Two invariants a plain `clock:spring` + `math.floor` in a memo does not give
-- you, and both were defects before they were rules:
--
--   * IT NEVER OVERSHOOTS. A counter is a QUANTITY. A wallet that flashes 130 on
--     its way to 120 reads as a bug even when the physics is perfect, so the
--     published value is clamped to the side of the target it started on. The
--     class still owns the pacing (`reward`'s overshoot becomes "arrives early
--     and waits", which is what a numeral wants); only the numeral is clamped.
--   * IT WRITES ONCE PER CHANGED NUMERAL, not once per frame. The value layer's
--     write gate compares against what the signal holds, so a quantized value
--     costs one write per visible change — a text node re-measures on every
--     write, and a 60 Hz count-up that changes 30 times must cost 30, not 120.
--
-- Everything else is `clock:spring`: it IS a Readable<number>, it re-aims
-- without restarting, it lands EXACTLY on its target, and under reduced motion
-- (decorative by default — the number is a fact that is already on screen) it
-- places the final value instantly and fires the same settle event.
function motion.newCounter(internals: Internals, initial: number, class: any, opts: ValueOpts?): MotionValue
	local params = classes.resolve(class)
	local options: ValueOpts = opts or {}
	local function whole(v: number): number
		return math.floor(v + 0.5)
	end
	local sp = springLib.new(whole(initial), params, options.eps)
	-- the direction of travel, fixed at the aim: it is what "never overshoots"
	-- means without remembering a history the resolution would depend on
	local dir = 0
	local driver: Driver = {
		advance = function(dt: number): boolean
			local settled = sp:step(dt)
			if settled then
				sp:snap(sp:getTarget())
			end
			return settled
		end,
		place = function(v: number)
			sp:snap(whole(v))
			dir = 0
		end,
		value = function(): number
			local v = whole(sp:get())
			local t = whole(sp:getTarget())
			if dir > 0 then
				return math.min(v, t)
			elseif dir < 0 then
				return math.max(v, t)
			end
			return v
		end,
		terminus = function(): number
			return sp:getTarget()
		end,
		settled = function(): boolean
			return sp:isSettled()
		end,
		aim = function(v: number)
			-- the target is a numeral too, so the settling frame lands ON the number
			-- the counter shows rather than 0.4 away from it
			local target = whole(v)
			dir = if target > sp:get() then 1 elseif target < sp:get() then -1 else 0
			sp:setTarget(target)
		end,
		seed = function(v: number)
			sp:setVelocity(v)
		end,
		velocity = function(): number
			return sp:getVelocity()
		end,
	}
	return newValue(internals, whole(initial), options, driver, false)
end

-- clock:timer(spec) — the informational ramp: `from` → `to` over `duration`
-- seconds of clock time. It owes a WALL-CLOCK terminus, so it advances by raw dt
-- (a frame spike must not stretch a countdown); springs clamp dt because they
-- are target-seeking, not cadence-locked.
function motion.newTimer(internals: Internals, spec: TimerSpec): MotionValue
	if type(spec) ~= "table" then
		error(`LuauUI motion: clock:timer takes a spec table \{ from, to, duration }, got {typeof(spec)}`, 0)
	end
	local from, to, duration = spec.from, spec.to, spec.duration
	if not isFinite(from) or not isFinite(to) then
		error("LuauUI motion: clock:timer needs finite `from` and `to` values", 0)
	end
	if not isFinite(duration) or duration < 0 then
		error(`LuauUI motion: clock:timer needs a duration in seconds >= 0, got {tostring(duration)}`, 0)
	end

	local elapsed = 0
	local current = from
	local driver: Driver = {
		advance = function(dt: number): boolean
			elapsed += dt
			if elapsed >= duration then
				elapsed = duration
				current = to
				return true
			end
			current = from + (to - from) * (elapsed / duration)
			return false
		end,
		place = function(v: number)
			current = v
			elapsed = duration
		end,
		value = function(): number
			return current
		end,
		terminus = function(): number
			return to
		end,
		settled = function(): boolean
			return elapsed >= duration
		end,
		aim = nil,
		seed = nil,
		velocity = function(): number
			return if duration > 0 then (to - from) / duration else 0
		end,
	}
	local options: ValueOpts = {
		kind = spec.kind or "informational",
		quantum = spec.quantum,
	}
	return newValue(internals, from, options, driver, true)
end

return motion
