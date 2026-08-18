--!strict
-- PER-ROW CAPABILITY OPT-OUTS — the one mechanism `newTable` and
-- `newVirtualList` both use for `rowSelectable` / `rowMovable` / `rowDeletable`.
--
-- WHAT IT IS FOR. A consumer wants "this list is reorderable, but the pinned row
-- at the top stays put", or "these rows can be deleted, that one cannot". The
-- container-level capability (`reorderable` + `onReorder`, a destructive row
-- action, `selection`) says what the CONTAINER can do; these predicates say
-- which ROWS may take part.
--
-- WHY IT IS A MODULE AND NOT TWO COPIES. The family spans two controls, and
-- `docs/reference/swiftui-parity.md` §13 already carries "gesture machinery in
-- four implementations that duplicate state and math" as a confirmed defect. A
-- capability gate whose two copies could disagree about what a thrown predicate
-- means is that defect being re-committed while it is on the list. One
-- implementation, two callers.
--
-- THREE RULES, each from a rule this repo already paid for:
--
--   1. POSITIVE POLARITY. SwiftUI spells these `selectionDisabled` /
--      `deleteDisabled` / `moveDisabled` — negative, where true means OFF. Facet
--      spells them positively, because `rowFocusable` already sits on the same
--      spec tables meaning true = on, and `rowFocusable` beside `moveDisabled`
--      is a bug factory. The parity doc carries the inverse mapping so a SwiftUI
--      author is not left guessing.
--
--   2. A PREDICATE MAY ONLY SUBTRACT. It answers "may THIS ROW participate?",
--      never "can this container do X at all?". Declaring one without the
--      capability it narrows is a CONSTRUCTION error (constitution §4: an
--      accepted property must do something) — see `assertNarrowsSomething`.
--
--   3. IT FAILS CLOSED. A predicate that throws refuses the capability. See
--      `allows` for why that direction and not the other.
--
-- Absent predicate == every row participates, which is what makes adopting this
-- family cost nothing: `allows(nil, item)` is `true` and one `~= nil` check.

local row_capability = {}

export type Predicate = ((item: any) -> boolean)?

--[[ THE GATE ─────────────────────────────────────────────────────────────────
	`allows(pred, item, core, what)` answers "may this row do `what`?".

	FAILS CLOSED, AND THE DIRECTION IS THE WHOLE POINT. Constitution §7 requires
	a consumer callback that computes a value the framework needs to have a
	STATED fallback on throw. For a capability gate there are only two choices
	and they are not symmetric:

	  * fail OPEN (a thrown predicate means "yes") — a consumer bug silently
	    deletes a row the author was trying to protect. Unrecoverable, and the
	    player is the one who finds out.
	  * fail CLOSED (a thrown predicate means "no") — a consumer bug makes a row
	    stubbornly refuse to move or delete. Visible, annoying, harmless, and
	    the quarantined error says exactly which predicate threw.

	So it fails closed. The error is quarantined through the core rather than
	re-raised, because a broken predicate on row 4 must not take down a list of
	four hundred.

	A predicate returning a non-boolean is treated as its truthiness, EXCEPT
	that an explicit `false` is the only refusal — this mirrors `rowFocusable`'s
	shipped reading (`spec.rowFocusable(item) ~= false`), so an author who
	returns `nil` from a forgotten branch keeps the permissive default rather
	than silently pinning every row.

	A THROW IS SWALLOWED, NOT RECORDED, AND THAT IS A KNOWN GAP RATHER THAN A
	CHOICE. Constitution §8's error ladder says a quarantined user callback is
	"recorded via `lastError`" — but `core`'s `fail` is a private local
	(`core/custom.luau:60`) and `Core` publishes only `lastError()` to READ it.
	A composite control has no public channel to write one, which is why every
	shipped quarantine in `row_actions.luau` is a bare `pcall` too
	(`:1542`, `:1620`, `:1889`, `:3336`). This module follows the house idiom
	rather than inventing a seam; the gap is real and is recorded for the
	round that adds a control-facing error channel.
]]
function row_capability.allows(pred: Predicate, item: any): boolean
	if pred == nil then
		return true
	end
	if item == nil then
		-- a key with no live item (a row removed mid-gesture). Nothing to ask
		-- the predicate about; the capability's own funnel already handles a
		-- missing item, so this must not be the thing that decides.
		return true
	end
	local ok, result = pcall(pred, item)
	if not ok then
		return false
	end
	return result ~= false
end

--[[ THE CONSTRUCTION REFUSAL ────────────────────────────────────────────────
	A predicate that narrows a capability the control does not have is an
	accepted property that does nothing — constitution §4's exact prohibition,
	and the defect class round 2's placement audit was written to end.

	`declared` is the human-readable thing the author must add for the predicate
	to mean anything (`onReorder`, `selection`, `rowActions`). The message names
	the predicate, what is missing, and how to fix it, per §4's refusal shape.
]]
function row_capability.assertNarrowsSomething(
	control: string,
	predName: string,
	pred: Predicate,
	capabilityPresent: boolean,
	declared: string,
	fix: string
)
	if pred == nil or capabilityPresent then
		return
	end
	error(
		`Facet {control}: spec.{predName} narrows a capability this control does not have — `
			.. `it would be accepted and do nothing. {declared} is missing. {fix}`,
		3
	)
end

return row_capability
