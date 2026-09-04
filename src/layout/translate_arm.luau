--!strict
--[[ THE TRANSLATE ARM (wicked-fast O3), lifted out of `layout/solver.luau` on
	2026-09-03 (Plan C, T2): `translatable` and `translateDescendants`, the two
	functions that decide whether a subtree whose size did not change and whose
	origin did can be re-based onto its new origin by one delta instead of being
	re-measured and re-arranged, and then do the re-basing.

	NO DEPS RECORD, AND NONE IS NEEDED — the strongest one-way claim a seam in this
	repository can make, the same one `./placement` and `../render/recycle_key`
	already carry about themselves. Every input arrives as a parameter
	(`reuse`/`node` for `translatable`; `ctx`/`node`/`base`/`was`/`out` for
	`translateDescendants`), both read only `reuse.dirtyContains`/`reuse.previous`,
	`node.children` and `child.id`/`child.kind` off what they are handed, and
	neither closes over a solver local. `ctx: any, node: any` rather than the
	solver's own `Ctx`/`Node` — stack's precedent (`layout/stack.luau`) — because
	those types are erased at runtime and importing them would name a solver symbol,
	which is the one thing a one-way module may not do. `Rect` is declared fresh
	below for the same reason `./anchor_placement`, `./composition` and
	`./text_audit` each declare the same four numbers rather than import the
	solver's.

	THE TWO CTX COUNTER WRITES are the whole of what this module changes about its
	caller's state: `ctx.rectInserts` and `ctx.translated`, both `+= 1`, once per
	descendant re-based. Everything else it writes is by INDEX into three tables it
	does not own — `out[child.id]`, `ctx.translatedPaths[n]` and
	`ctx.translatedEntries[n]` — never a field of `ctx` itself.

	`literalIsWholeEntry` and `selfPlaces` STAY IN THE SOLVER: they are the ROOT's
	gate (does THIS node qualify to become a translate root at all), not the
	subtree's, and `translatable` is only ever asked once that gate has already
	passed. ]]

local translate_arm = {}

-- a solved box, declared here rather than imported for the reason the module
-- header gives: `./stack`, `./anchor_placement`, `./composition` and
-- `./text_audit` each declare the same four numbers for the same reason.
export type Rect = { x: number, y: number, w: number, h: number }

-- NO CHILD IN THE DIRTY SET => NO DESCENDANT IN IT (it is prefix-closed), so one
-- pass answers for the subtree. It also refuses a child the previous solve never
-- recorded, which only a torn `lastResult` reaches.
function translate_arm.translatable(reuse: any, node: any): boolean
	local kids = node.children
	if kids == nil then
		return true
	end
	local contains, rects = reuse.dirtyContains, reuse.previous.rects
	for _, child in kids do
		local id = child.id
		if contains[id] == true or rects[id] == nil then
			return false
		end
	end
	return true
end

--[[ RE-BASE EVERY DESCENDANT ONTO THE ROOT'S NEW ORIGIN. Returns false — having
	written some — if a node below has no previous entry; the caller rolls the
	partial run back, map included. Not dead code: `translatable` inspects DIRECT
	children only, and the argument that a new GRANDCHILD cannot reach here runs
	through `builtIds` and `structural_scope.widen` in two other files. ]]
function translate_arm.translateDescendants(ctx: any, node: any, base: Rect, was: Rect, out: { [string]: any }): boolean
	local kids = node.children
	if kids == nil then
		return true
	end
	local rects = (ctx.reuse :: any).previous.rects
	local paths, entries = ctx.translatedPaths, ctx.translatedEntries
	for _, child in kids do
		--[[ A COMPOSITION IS REFUSED AS A DESCENDANT FOR THE SAME REASON
			`literalIsWholeEntry` REFUSES IT AS A ROOT (RED-TEAM T9, finding 2), and the
			reason is stronger here: its resolution is a FUNCTION OF ITS ORIGIN.
			`composition_resolve` converts author `exclusions` from window space into the
			box and decides `atRoot` by comparing the placed y to the root rect, so a
			re-based clone carries lanes and a platform-band reservation computed at the
			position it no longer occupies. `scroll` is safely translated (every field it
			stamps is translation-invariant); this one is not. Refusing rolls the whole
			run back to a full arrange for this root, which is the conservative direction
			and costs nothing on a tree with no composition in it. ]]
		if child.kind == "composition" then
			return false
		end
		local prevEntry = rects[child.id]
		if prevEntry == nil or prevEntry.rect == nil then
			return false
		end
		local old = prevEntry.rect
		local entry = table.clone(prevEntry)
		-- FROM THE ROOT'S ORIGIN, NOT BY A DELTA: `old.x + (new - was)` gains a rounding
		-- per solve — `tests/table.spec` read 35.99999999999998 for a row whose closed x
		-- is exactly 36. This form is idempotent.
		entry.rect = table.freeze({ x = base.x + (old.x - was.x), y = base.y + (old.y - was.y), w = old.w, h = old.h })
		entry.moveOnly = true
		entry.prev = prevEntry
		-- THE CHAIN BREAK. `prev` has one reader — the next commit's `skip`, comparing
		-- identity — and the entry superseded above no longer needs its own, or the node
		-- retains its whole history: N holds N-1 holds N-2, forever.
		prevEntry.prev = nil
		out[child.id] = entry
		ctx.translated += 1
		ctx.rectInserts += 1
		local n = #paths + 1
		paths[n] = child.id
		entries[n] = entry
		if not translate_arm.translateDescendants(ctx, child, base, was, out) then
			return false
		end
	end
	return true
end

return translate_arm
