--!strict
--[[
	value_reveal — "hold a number at what it WAS, then move it to what it IS, on
	cue, and land the truth whatever happens."

	WHY THIS EXISTS (game-side evidence, 2026-08-02). A results screen grew this
	state machine twice in one file — once for a progress bar, once for a wallet
	counter — and EVERY bug the director reported in two review rounds was in one
	of the two copies:

	  · the machine ran once at construction, before its payload existed, and that
	    path released the hold — so the final value painted for a few frames, the
	    payload arrived, the hold went back up, and the bar visibly EMPTIED before
	    filling ("the rally points bar starts filled, then when the message comes
	    up it empties");
	  · the "counting" flag was set BEFORE the counter was seeded, and a counter is
	    created at zero, so one frame painted 0 ("coins/rally points pop to a new
	    value");
	  · an earlier round had the mirror defect on the other axis — the number
	    stated and then WITHDRAWN, which is the punchline before the joke.

	None of those are about the number. They are all about the SHAPE: what "not
	yet" means, what order the seed and the flag go in, and which paths count as
	abandoning. That shape is what lives here, once.

	THE FIVE RULES IT ENCODES

	  1. HELD IS THE DEFAULT. Before the cue the reveal reads `from`. A caller
	     with no payload yet is WAITING, not abandoning — the single most
	     expensive confusion of the two hand-rolled copies.
	  2. SEED, THEN COUNT. `run` writes the start value before it flips the flag
	     that makes anything read the animator, so no frame can observe an
	     unseeded animator.
	  3. EVERY ABANDON PATH LANDS THE TRUTH. Skip, a new epoch, a payload that
	     changed mid-flight, a reveal whose window has already passed, and a
	     caller that cannot animate at all — all of them release to `to`. There is
	     no path on which a number is left showing what it was.
	  4. ONCE PER EPOCH. A reveal runs once for a given `epoch` (a tail id, a
	     round stamp — whatever the caller's "this is a different showing" is) and
	     a new epoch rearms it on the settled state of the last one.
	  5. DEGRADING IS NOT WITHHOLDING. `capable = false` (no motion clock,
	     reduced motion) is not a hold — it is an immediate landing. Decoration
	     may be skipped; the fact may not.

	It owns NO clock and NO signals of its own: the caller passes its animator and
	its two flags, so the reveal composes with whatever the surface already reads.
]]

local value_reveal = {}

export type Animator = {
	-- place the animator AT a value with no transit (the seed)
	snap: (self: any, value: number) -> (),
	-- and send it toward one
	setTarget: (self: any, value: number) -> (),
}

export type Spec = {
	-- the two flags the caller's own memo reads. `held` true = paint `from`;
	-- `counting` true = paint the animator. Neither true = paint `to`.
	held: { set: (self: any, value: boolean) -> () },
	counting: { set: (self: any, value: boolean) -> () },
	-- absent = the caller has no animator (no motion clock, reduced motion):
	-- every cue lands immediately, which is rule 5
	animator: Animator?,
}

export type Cue = {
	-- "this is a different showing" — a tail id, a round stamp, anything stable
	-- for one reveal and different for the next. nil = there is no showing at all
	epoch: string?,
	-- is the window open yet?
	open: boolean,
	-- has it already closed? (a client that arrived late has nothing to hold for)
	past: boolean,
	-- the caller gave up on the ceremony: land everything now
	abandoned: boolean,
	-- the payload; nil = NOT YET KNOWN, which is rule 1 and is not an abandon
	from: number?,
	to: number?,
}

export type Reveal = {
	-- call whenever any input changed; idempotent, cheap, and safe before the
	-- payload exists
	sync: (self: any, cue: Cue) -> (),
	-- the animator settled — the caller wires this to its own onSettle
	landed: (self: any) -> (),
	-- release everything to the settled state (teardown, a new surface)
	rest: (self: any) -> (),
}

function value_reveal.new(spec: Spec): Reveal
	local ranFor: string? = nil
	local self = {}

	local function release()
		spec.counting:set(false)
		spec.held:set(false)
	end

	function self.rest(_: any)
		ranFor = nil
		release()
	end

	function self.landed(_: any)
		spec.counting:set(false)
	end

	function self.sync(_: any, cue: Cue)
		--[[ RULE 5 first: a caller that cannot animate never holds. This is checked
			before "do we know the payload yet", because an incapable caller has
			nothing to wait FOR. ]]
		if spec.animator == nil then
			ranFor = cue.epoch
			release()
			return
		end
		-- RULE 3: an explicit abandon lands the truth and arms the epoch, so a
		-- late-arriving cue cannot restart a ceremony the caller already ended.
		if cue.abandoned then
			ranFor = cue.epoch
			release()
			return
		end
		--[[ RULE 1: NOT YET KNOWN IS NOT AN ABANDON. No epoch, or no payload, and
			the reveal simply keeps waiting — it does NOT release. Releasing here is
			the defect that painted the final value and then took it away. ]]
		if cue.epoch == nil or cue.from == nil or cue.to == nil then
			return
		end
		-- RULE 4: a new showing rearms on the settled state of the last one.
		if ranFor ~= nil and ranFor ~= cue.epoch then
			ranFor = nil
			release()
		end
		if ranFor == cue.epoch then
			return
		end
		if not cue.open then
			-- still coming: hold, unless the window is already behind us (rule 3's
			-- late-arrival path — there is nothing left to animate toward)
			spec.held:set(not cue.past)
			return
		end
		ranFor = cue.epoch
		-- RULE 2: SEED, THEN COUNT. Nothing may read the animator before it holds
		-- the start value.
		local animator = spec.animator :: Animator
		animator:snap(cue.from :: number)
		animator:setTarget(cue.to :: number)
		spec.held:set(false)
		spec.counting:set(true)
	end

	return self :: any
end

return value_reveal
