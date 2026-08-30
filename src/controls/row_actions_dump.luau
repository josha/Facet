--!strict
--[[ row_actions_dump — the `dump()` diagnostics snapshot, split out of
	`row_actions.luau` (task EXTRACT2, 2026-08-29).

	SOURCE_CAP_LEDGER's row_actions.luau row named this exact seam across two
	prior recordings: "a dump builder reads state and writes nothing, so a
	`row_actions_dump.luau` taking the tray/edge/commit records as an argument
	list cannot require back... it needs no behavioural change, only an
	argument list." That is exactly what this file is: `build` is called
	FRESH, synchronously, every time a caller asks `api.dump()` for a
	snapshot — never held across two calls — so there is nothing here for a
	later mutation of `committed`/`offset`/`openEdge` to go stale against.
	Passing today's VALUES once, by argument, is the whole extraction; no
	record, no live reference, no upvalue of `buildEngine` crosses this
	boundary at all.

	THIS DOES NOT CONTRADICT the file's own header ("THE ONE ENGINE... ~65
	nested functions share ~60 mutable upvalues... deliberately... threading a
	state record through them is a rewrite of code four device rounds
	hardened, not an extraction"). That ruling is about `buildEngine`'s OWN
	internal wiring — the commit ladder, the gesture state machine, the menu
	(`menuHandle` is one of the header's own named examples) — none of which
	this file touches. `dump()` was always the one exception: an external,
	on-demand snapshot call, not a participant in the live state machine.

	`tests/row_actions_dump_seam.spec.luau` mechanises the one-way property:
	the fields this module READS (its own `Params` type) are exactly the
	fields the ONE call site (row_actions.luau's own `dump` wrapper) PASSES,
	and this module requires nothing back. ]]

export type Params = {
	id: string,
	offsetPx: number,
	openEdge: ("leading" | "trailing")?,
	committed: boolean,
	menuOpen: boolean,
	menuHeightPx: number,
}

local row_actions_dump = {}

function row_actions_dump.build(p: Params): { [string]: any }
	local phase: string
	if p.committed then
		phase = "committing"
	elseif p.openEdge == nil then
		phase = "closed"
	else
		phase = "open"
	end
	return {
		schema = "facet-rowactions-dump/1",
		id = p.id,
		offset = p.offsetPx,
		openEdge = p.openEdge,
		phase = phase,
		-- Task 8: the action menu's own open state, independent of the
		-- tray's `openEdge`/`phase` above.
		menuOpen = p.menuOpen,
		-- ruling 4: the height the FLIP decision is made against, published so a
		-- test can compare the number this file actually uses with the one the
		-- solver paints. Without it the only available check compares the solver
		-- against a second copy of the same arithmetic written in the test — a
		-- check that cannot see this file being wrong, which is the class
		-- docs/lessons and the simplicity gate both name.
		menuHeightPx = p.menuHeightPx,
	}
end

return row_actions_dump
