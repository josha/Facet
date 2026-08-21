--!strict
-- PreferredTextSize offset seam (the large-text accessibility work; the
-- measured offsets are in artifacts/large-text-accessibility/probe/preference-probe.json).
--
-- The engine applies the player's text-size preference as a FIXED PIXEL OFFSET
-- on every text node at draw time — measured live 2026-08-03: Medium=0, Large=4,
-- Larger=10, Largest=14, identical across font, weight, and requested size
-- (built-ins and theme-package fonts alike). `GetTextBoundsAsync` does NOT
-- include it (it answers for the literal requested size at every preference),
-- so the solver measuring at `size + offset` reserves EXACTLY what the engine
-- paints. That makes this one number the whole seam.
--
-- This module owns the decision core, engine-free so the suite can drive it:
--   * apply IMMEDIATELY from the measured-fallback table (never yield, never
--     block first mount);
--   * confirm each preference once through the injected yielding lookup
--     (`TextService:GetTextSizeOffsetAsync` live), cached per enum value for
--     the session;
--   * when the confirmed answer differs from what was applied AND the player
--     is still on that preference, apply once more — one atomic correction,
--     the renderer's existing `preferredTextOffset` watch re-solves;
--   * a stale answer (preference moved on while the lookup yielded) is
--     DISCARDED ENTIRELY — never cached, never applied. The live engine lookup
--     has no preference parameter (it answers for whatever preference is
--     CURRENT when it answers), so an answer that arrives after another step
--     may describe either value; caching it under the requested name would
--     poison that preference for the whole session with an under-reserving
--     number (platform review F1 — the A->B->A repro measured exactly that).
--     The next visit to the preference simply asks again;
--   * a failed/garbage lookup keeps the fallback and is retried only on the
--     next visit to that preference, so failure can never loop reflow;
--   * an answer LARGER than the sanity ceiling is clamped to the ceiling and
--     applied — never discarded in favour of a smaller fallback. If the
--     platform raises its constants, discarding the truthful bigger answer
--     would under-reserve (platform review F2); clamping keeps the box within
--     one bounded step of the truth in the safe direction.
--
-- The fallback table is MEASURED data (the probe artifact), not a guess; it is
-- what ships when the confirm lookup cannot answer, and over- or under-shoot
-- is bounded by the platform changing its constants out from under us.

local preferred_text = {}

-- measured 2026-08-03 (probe artifact); the pre-stage guess had Large=6
preferred_text.FALLBACK_OFFSETS = table.freeze({
	Medium = 0,
	Large = 4,
	Larger = 10,
	Largest = 14,
} :: { [string]: number })

-- a confirmed offset outside this range is engine garbage, not a preference:
-- refuse it and keep the fallback (same clamp ceiling the renderer applies)
local MAX_OFFSET = 32

export type Options = {
	-- the yielding engine lookup; called OFF the caller's thread. nil/error =>
	-- no answer (fallback stands). Injected so tests never touch the engine.
	getOffset: (preference: string) -> number?,
	-- the env writer; called synchronously from setPreference and at most once
	-- more per confirmed correction
	apply: (offset: number) -> (),
	-- scheduler seam (default task.spawn); tests may run it inline
	spawn: ((f: () -> ()) -> ())?,
}

export type Controller = {
	setPreference: (self: Controller, name: string) -> (),
	dispose: (self: Controller) -> (),
	-- inspection for diagnostics/tests: what is applied, and from which source
	current: (self: Controller) -> { preference: string?, offset: number, source: string },
}

function preferred_text.new(opts: Options): Controller
	assert(type(opts) == "table", "preferred_text.new: options table required")
	assert(type(opts.getOffset) == "function", "preferred_text.new: getOffset is required")
	assert(type(opts.apply) == "function", "preferred_text.new: apply is required")
	local spawnFn: (f: () -> ()) -> () = opts.spawn or function(f)
		task.spawn(f)
	end

	local measured: { [string]: number } = {}
	local inFlight: { [string]: boolean } = {}
	local disposed = false
	local currentPreference: string? = nil
	local appliedOffset = 0
	local appliedSource = "fallback"
	-- the stale-answer instrument (F1): bumped on EVERY setPreference. A lookup
	-- captures the epoch when it is spawned; an answer whose epoch is no longer
	-- current raced at least one step and may describe EITHER preference, so it
	-- is dropped on the floor — name equality across the yield is not enough,
	-- because the engine lookup answers for whatever preference is live when it
	-- answers, not for the name this controller asked about
	local epoch = 0

	local self = {} :: any

	local function applyFor(name: string, offset: number, source: string)
		appliedOffset = offset
		appliedSource = source
		opts.apply(offset)
	end

	function self.setPreference(_self: any, name: string)
		if disposed or type(name) ~= "string" then
			return
		end
		currentPreference = name
		epoch += 1
		local known = measured[name]
		if known ~= nil then
			applyFor(name, known, "measured")
			return
		end
		local fallback = preferred_text.FALLBACK_OFFSETS[name]
		-- an UNKNOWN enum value (a future fifth preference) starts from the
		-- largest known fallback: over-reserving a new larger tier is safe,
		-- under-reserving it clips — and the confirm lookup corrects it exactly
		applyFor(
			name,
			fallback or preferred_text.FALLBACK_OFFSETS.Largest,
			if fallback ~= nil then "fallback" else "fallback-unknown"
		)
		if inFlight[name] then
			return
		end
		inFlight[name] = true
		local spawnEpoch = epoch
		spawnFn(function()
			local ok, answer = pcall(opts.getOffset, name)
			inFlight[name] = false
			if disposed then
				return
			end
			-- THE EPOCH GUARD (platform review F1). The live engine lookup has no
			-- preference parameter: it answers for whatever preference is CURRENT
			-- when it answers. If the player stepped again while this lookup was
			-- in flight, the answer may describe EITHER preference — so it is
			-- dropped entirely, never cached under `name` (an A->B->A double-step
			-- would otherwise poison A with B's smaller offset for the whole
			-- session, the permanent under-reserve this stage exists to remove).
			-- The next visit to `name` simply asks again.
			if epoch ~= spawnEpoch then
				return
			end
			if not ok or type(answer) ~= "number" or answer ~= answer or answer < 0 then
				return -- fallback stands; retried on the next visit to `name`
			end
			-- an answer past the sanity ceiling is CLAMPED, not discarded
			-- (platform review F2): if the platform raises its constants, the
			-- truthful bigger answer must still beat a smaller stale fallback —
			-- clamping keeps the reservation within one bounded step of the truth
			-- in the safe direction, while NaN/negative garbage above stays refused
			answer = math.floor(math.min(answer, MAX_OFFSET) + 0.5)
			measured[name] = answer
			if answer ~= appliedOffset then
				applyFor(name, answer, "measured")
			else
				appliedSource = "measured"
			end
		end)
	end

	function self.dispose(_self: any)
		disposed = true
	end

	function self.current(_self: any): { preference: string?, offset: number, source: string }
		return { preference = currentPreference, offset = appliedOffset, source = appliedSource }
	end

	return self :: Controller
end

return preferred_text
