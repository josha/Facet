--!strict
-- Timeline — choreographed sequences on the motion clock (ADR-0022 Decision 1;
-- ui-designer spec §1.6). A timeline is an ordered list of BEATS, each declaring
-- when it fires (`at`, seconds from the start), what it does (`run`), and the
-- clean end state it is responsible for (`terminal`).
--
-- WHY THIS EXISTS: sequences built on `task.delay` are untestable and
-- un-interruptible, and an interrupted one leaves orphan state on screen. Here
-- time comes from the injected clock (headlessly deterministic), and both ways
-- out of a running sequence are declared:
--
--   * `interrupt()` — something else took over. Runs the MID-PLAY beat's
--     `terminal` and then every remaining beat's, in order, on the interrupt
--     frame, so nothing is left
--     half-painted. It deliberately does NOT play the remaining content.
--   * `skip()` — the player asked to fast-forward. Delivers the remaining
--     content instantly: each remaining beat's `run` and then its `terminal`, in
--     order, with zero elapsed time. Same events, same end state, no waiting.
--
-- REDUCED MOTION (I-4): a timeline never drops a beat. Under `reduced` the whole
-- sequence fires immediately on start, in order, with its durations zeroed —
-- which is exactly `skip()` from the first beat, so there is one code path and
-- the events cannot diverge from the animated ones.
--
-- Beats fire on clock steps; a beat at `at = 0` fires on the first step.

local num = require("../num")

local timeline = {}

export type Beat = {
	at: number, -- seconds from the timeline's start
	run: (() -> ())?, -- the beat itself (its semantic events fire here)
	terminal: (() -> ())?, -- the clean end state this beat is responsible for
}

export type Spec = {
	beats: { Beat },
	-- fires exactly once: "complete" | "interrupt" | "skip" | "reduced"
	onDone: ((reason: string) -> ())?,
}

export type Timeline = {
	interrupt: (self: Timeline) -> (),
	skip: (self: Timeline) -> (),
	isDone: (self: Timeline) -> boolean,
	elapsed: (self: Timeline) -> number,
}

local isFinite = num.isFinite

function timeline.new(internals: any, spec: Spec): Timeline
	if type(spec) ~= "table" or type(spec.beats) ~= "table" then
		error(
			"Facet motion: clock:timeline takes { beats = { { at = seconds, run = fn, terminal = fn? } } }, "
				.. "declared in the order they fire",
			0
		)
	end
	local beats = spec.beats
	local onDone = spec.onDone
	local previousAt = 0
	for index, beat in beats do
		if type(beat) ~= "table" or not isFinite(beat.at) or beat.at < 0 then
			error(`Facet motion: timeline beat {index} needs a finite 'at' >= 0 (seconds from the start)`, 0)
		end
		if beat.at < previousAt then
			-- an out-of-order beat could never fire on the frame it claims, and
			-- interrupt/skip order would stop meaning anything
			error(
				`Facet motion: timeline beat {index} is out of order (at {beat.at} after {previousAt}). `
					.. `Declare beats in the order they fire.`,
				0
			)
		end
		if beat.run ~= nil and type(beat.run) ~= "function" then
			error(`Facet motion: timeline beat {index}: run must be a function`, 0)
		end
		if beat.terminal ~= nil and type(beat.terminal) ~= "function" then
			error(`Facet motion: timeline beat {index}: terminal must be a function`, 0)
		end
		previousAt = beat.at
	end

	local elapsed = 0
	local nextBeat = 1
	local done = false
	local detach: (() -> ())? = nil

	local handle = {}

	local function leave()
		if detach ~= nil then
			detach()
			detach = nil
		end
	end

	-- run every remaining beat NOW, in order: the beat happens (`run`) and then
	-- lands on its declared end state (`terminal`) with zero time in between
	local function fastForward()
		while nextBeat <= #beats do
			local beat = beats[nextBeat]
			nextBeat += 1
			if beat.run ~= nil then
				beat.run()
			end
			if beat.terminal ~= nil then
				beat.terminal()
			end
		end
	end

	-- put every remaining beat's declared end state in place without playing it
	local function terminalsOnly()
		while nextBeat <= #beats do
			local beat = beats[nextBeat]
			nextBeat += 1
			if beat.terminal ~= nil then
				beat.terminal()
			end
		end
	end

	local function advanceBeats(dt: number)
		if done then
			return
		end
		elapsed += dt
		while nextBeat <= #beats and beats[nextBeat].at <= elapsed do
			local beat = beats[nextBeat]
			nextBeat += 1
			if beat.run ~= nil then
				beat.run()
			end
			if done then
				return -- a beat interrupted or skipped its own timeline
			end
		end
		if nextBeat > #beats then
			done = true
			leave()
			if onDone ~= nil then
				onDone("complete")
			end
		end
	end

	function handle.interrupt(_: any)
		if done then
			return
		end
		done = true
		leave()
		-- THE BEAT MID-PLAY TERMINALIZES TOO (ui-designer §8.2; lead ruling on
		-- P5-F6): its `run` already fired, so only its declared end state can make
		-- "nothing half-painted on this frame" true — springs it started would
		-- converge later than the contract allows. Terminals are declared end
		-- states (snaps), so re-running one that already visually completed is
		-- idempotent by construction.
		local playing = beats[nextBeat - 1]
		if playing ~= nil and playing.terminal ~= nil then
			playing.terminal()
		end
		terminalsOnly()
		if onDone ~= nil then
			onDone("interrupt")
		end
	end

	function handle.skip(_: any)
		if done then
			return
		end
		done = true
		leave()
		fastForward()
		if onDone ~= nil then
			onDone("skip")
		end
	end

	function handle.isDone(_: any): boolean
		return done
	end

	function handle.elapsed(_: any): number
		return elapsed
	end

	if #beats == 0 then
		done = true
		if onDone ~= nil then
			onDone("complete")
		end
		return handle :: any
	end

	if internals.isReduced() then
		-- durations zeroed, every beat and every event still fires, in order
		done = true
		fastForward()
		if onDone ~= nil then
			onDone("reduced")
		end
		return handle :: any
	end

	detach = internals.attach({ pre = advanceBeats })

	return handle :: any
end

return timeline
