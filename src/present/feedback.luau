--!strict
-- THE SEMANTIC FEEDBACK SEAM (ADR-0022 Decision 7; ui-designer spec §7;
-- acceptance row SF-F1). One per-presenter event bus, and one rule that matters
-- more than the bus: LuauUI PLAYS NOTHING. It never triggers a sound, a haptic or
-- a particle — it says what happened, on the frame it happened, with enough
-- context for a game to map it to its own assets and policy (corrections §13,
-- responsibility ledger RG-4).
--
-- THE TAXONOMY IS CLOSED (spec §7 "closed initial taxonomy (v1)"). Growing it is a
-- contract amendment with a gate, never an ad-hoc string at a call site, because
-- taxonomy sprawl — every control inventing its own verb — is the named risk. An
-- unknown type is an authoring error that lists the vocabulary.
--
-- THE CAUSAL FRAME IS THE ACCEPTANCE. An event fires synchronously in the frame
-- its cause resolved (the activate frame, the arrival frame, the retire frame),
-- exactly once — never on a timer afterwards and never twice for one cause. A
-- subscriber that plays a sound on `arrive` must be able to trust that the thing
-- has visibly landed.
--
--   bus.subscribe(fn) -> unsubscribe
--   bus.emit({ type, path?, surface?, reason?, context? })
--   bus.count()                       -- live subscriber count (leak assertions)

local feedback = {}

-- v1, closed. `arrive` is any chase/transition reaching its live target (a MOTION
-- event); `land` is a drag/commit payload reaching its resolved drop (a SESSION
-- event) — disposition F4 keeps them distinct so their causal frames cannot merge.
-- `celebrate` is ADR-0022 Decision 7's name for a choreographed reward beat; §7's
-- list omits it, so it is included here rather than left as the one verb the ADR
-- names and the framework refuses.
local TYPES: { string } = {
	"activate",
	"select",
	"adjust",
	"pickup",
	"commit",
	"reject",
	"cancel",
	"arrive",
	"land",
	"dismiss",
	"supersede",
	"celebrate",
}
local TYPE_SET: { [string]: boolean } = {}
for _, name in TYPES do
	TYPE_SET[name] = true
end
feedback.TYPES = table.freeze(TYPES)
feedback.TYPE_LIST = table.concat(TYPES, ", ")

export type Event = {
	type: string,
	-- the mounted path the event is about (absent for a surface-level event)
	path: string?,
	-- the presented handle it belongs to, when it belongs to one
	surface: any?,
	-- a machine-readable reason: "timeout" | "capacity" | "preempt" | "manual"
	-- for a dismiss; a game-supplied code for a reject. REPLACEMENT IS ITS OWN
	-- VERB, not a dismiss reason: a superseded toast emits `type = "supersede"`
	-- with `reason = nil` (src/present/presenter.luau's onDismiss), so nothing
	-- ever arrives as `type = "dismiss", reason = "supersede"`.
	reason: string?,
	context: any?,
}

export type Bus = {
	subscribe: (fn: (event: Event) -> ()) -> () -> (),
	emit: (event: Event) -> (),
	count: () -> number,
	dispose: () -> (),
}

function feedback.new(): Bus
	-- subscriptions are boxes so unsubscribing DURING a fire is safe: a game that
	-- one-shots a beat removes itself from inside its own handler
	local subs: { { fn: ((event: Event) -> ())? } } = {}
	local disposed = false
	local lastEmitError: string? = nil
	local bus: any = {}

	function bus.subscribe(fn: (event: Event) -> ()): () -> ()
		if type(fn) ~= "function" then
			error(`LuauUI feedback: onFeedback takes a function(event), got {typeof(fn)}`, 0)
		end
		local box: { fn: ((event: Event) -> ())? } = { fn = fn }
		table.insert(subs, box)
		return function()
			box.fn = nil
			for i, entry in subs do
				if entry == box then
					table.remove(subs, i)
					break
				end
			end
		end
	end

	function bus.emit(event: Event)
		if disposed then
			return
		end
		if type(event) ~= "table" or type(event.type) ~= "string" then
			error(`LuauUI feedback: an event is a table \{ type, path?, reason?, context? }, got {typeof(event)}`, 0)
		end
		if not TYPE_SET[event.type] then
			error(
				`LuauUI feedback: unknown event type '{event.type}'. The v1 taxonomy is CLOSED: `
					.. `{feedback.TYPE_LIST}. Growing it is a contract amendment with a gate — carry your own `
					.. "meaning in `reason`/`context` instead of inventing a verb.",
				0
			)
		end
		-- snapshot: a handler that subscribes or unsubscribes must not change who
		-- this emission reaches
		local snapshot = table.clone(subs)
		for _, box in snapshot do
			local fn = box.fn
			if fn ~= nil then
				-- QUARANTINED (verifier RR-12): one throwing subscriber must not
				-- starve its siblings or escape into the emitting control's causal
				-- frame — the same rule the core applies to observers
				local ok, err = pcall(fn, event)
				if not ok then
					lastEmitError = tostring(err)
				end
			end
		end
	end

	function bus.count(): number
		local n = 0
		for _, box in subs do
			if box.fn ~= nil then
				n += 1
			end
		end
		return n
	end

	-- the last error a subscriber quarantined during emit, nil when healthy
	function bus.lastError(): string?
		return lastEmitError
	end

	function bus.dispose()
		disposed = true
		table.clear(subs)
	end

	return bus :: Bus
end

return feedback
