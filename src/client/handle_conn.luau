--!strict
--[[ HANDLE CONNECTION RECONNECT — the shared disconnect-before-reconnect rule
	every `handle.*Conn` setter in the pointer/chrome adapter family needs
	(task CONN, review-fix234-findings.md Findings 1 & 4).

	A recycled handle (`screen_target.adapter.adopt`, instance recycling ON by
	default) is the SAME Lua table across park->adopt lives: `adopt` re-keys the
	pooled `candidate` handle directly into `handlesByPath`, carrying every
	`*Conn` field on it forward untouched. FIX-2 fixed exactly one of those
	fields (`activatedConn`) with an inline disconnect-before-reconnect guard;
	the review found every sibling setter shared the same bug in one of two
	shapes:

	  * UNCONDITIONAL OVERWRITE (Finding 1: `pointerBeganConn`, `hoverEnterConn`,
	    `hoverLeaveConn`, `scrollConn`, `barConn`/`barWindowConn`) — the prior
	    life's connection is never disconnected, so it stays live beside the
	    fresh one. Roblox fires `RBXScriptSignal` listeners in connection order,
	    so the OLDER, stale connection (closed over a prior life's
	    handlers/path) can win a race the fresh one should have owned.
	  * A `== nil` GUARD (Finding 4: `hitExpanderPointerConn`) — never
	    accumulates, but for exactly that reason also never REWIRES: a
	    permanent misroute surviving every future recycle, not a duplicate-
	    listener leak.

	Two functions answer both shapes with one rule each, so eight
	hand-repeated guards become two calls — the "fix shared logic once"
	standard this campaign holds itself to, not a suggestion.

	WHY THIS IS ITS OWN MODULE AND NOT A `screen_vocabulary` ADDITION. Every
	caller of these two functions is `screen_pointer.luau`/`screen_chrome.luau`,
	the same adapter-family siblings `screen_vocabulary` already serves — but
	`screen_vocabulary` touches `Enum` (`TEXT_ALIGN_MAP`) at MODULE SCOPE, which
	makes REQUIRING it (not just calling into it) engine-only. `screen_pointer`
	was deliberately built with NO module-scope engine touch of its own
	(`ctx.services` resolves `game:GetService` lazily, at `.new()` time, exactly
	so `tests/pointer_seam_ownership.spec.luau` can require it and drive its
	capture/hover/cursor logic headlessly with a fake `ctx`) — requiring
	`screen_vocabulary` from it would have silently defeated that property for
	every consumer of this module, not only the two functions that needed it.
	This module touches no engine global, at module scope or inside either
	function, so it costs that property nothing: `tests/handle_conn.spec.luau`
	requires it directly and drives both functions with plain fake-connection
	tables, the same technique `pointer_seam_ownership.spec.luau` already uses
	for `screen_pointer` itself.

	depends on: nothing (pure).
]]

local handle_conn = {}

--[[ RECONNECT: disconnect a handle's PRIOR `*Conn` field before making a fresh
	one. Every call site is a setter invoked exactly ONCE per (path,
	fresh-or-adopted handle) — `render/renderer.luau`'s create-or-adopt block
	calls each one right after choosing the engine object — so an
	unconditional overwrite is the right shape here: reconnecting on every call
	IS what should happen, because there is only ever one call per life.
	`factory` may answer nil (e.g. the node no longer qualifies for a
	connection at all), which correctly leaves the field nil too. ]]
function handle_conn.reconnect(handle: any, field: string, factory: () -> RBXScriptConnection?): RBXScriptConnection?
	local prior = handle[field]
	if prior ~= nil then
		(prior :: RBXScriptConnection):Disconnect()
	end
	local conn = factory()
	handle[field] = conn
	return conn
end

--[[ RECONNECT ON IDENTITY CHANGE: for a slot whose setter can run MANY times
	within a single life (unlike every site `reconnect` above serves, which
	runs exactly once per life), an unconditional disconnect-and-remake on
	every call would churn a fresh connection each time for no reason. What
	actually needs to change is whether the WATCHED identity moved: unchanged
	is a no-op — which preserves the same-life, order-independent wiring the
	field's old `== nil` guard existed for (two setters may run in either
	order within one life and both compute the SAME current identity, so
	whichever runs first wins and the second is a no-op, exactly as the guard
	intended) — and a genuinely changed identity (a park->adopt recycle:
	`adopt` reassigns `handle.path`, which is already the generation stamp the
	recycling mechanism provides, needing no new field) disconnects the stale
	connection before wiring the fresh one. The old `== nil` guard could never
	tell "already correct" from "stale forever"; comparing identity can. ]]
function handle_conn.reconnectOnChange(
	handle: any,
	field: string,
	identityField: string,
	identity: any,
	factory: () -> RBXScriptConnection?
)
	if handle[field] ~= nil and handle[identityField] == identity then
		return
	end
	if handle[field] ~= nil then
		(handle[field] :: RBXScriptConnection):Disconnect()
	end
	handle[identityField] = identity
	handle[field] = factory()
end

return handle_conn
