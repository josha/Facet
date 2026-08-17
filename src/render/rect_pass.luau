--!strict
--[[ HOW A SOLVE'S RECTS REACH THE ADAPTER, AND IN WHAT ORDER (ADR-0032).

	The order is the whole content of this module, and it is load-bearing rather
	than tidy.

	WHAT IT REPLACED. The renderer applied a solve's rects by iterating
	`result.rects` as a HASH — its own comment called it "the unordered rect hash".
	On a flat tree that is fine: every node's engine Position is absolute, so no
	node's answer depends on another's having landed first. Under a nested tree it
	stops being fine, because a descendant's Position is relative to its HOST. A
	descendant reached before its host re-bases against an origin that has not
	moved yet, writes a wrong value, and has to be corrected afterwards.

	MEASURED IN STUDIO, 2026-08-17, on a 120-node list inside a `ScrollView` whose
	container grew 40px: **240 engine `Position` changes across 120 descendants**,
	two each. `GetPropertyChangedSignal` fires only on a real VALUE change, so
	these were not redundant writes a minimal-write contract could catch — they
	were two different values:

	    1. cell  -> y = 60    WRONG: the new window rect against the host's OLD origin
	    2. list  -> y = 60    the host finally moves, and its origin updates
	    3. cell  -> y = 20    corrected, when the host re-bases its own children

	The net change is zero, which is exactly what "a Position is parent-relative"
	predicts. The path paid 2N writes to arrive there, and for the moment between
	1 and 3 every descendant of a moved container is drawn in the wrong place — a
	frame landing in that window shows the whole subtree jump.

	THE FIX IS TWO HALVES AND NEEDS BOTH. Ordering alone does not do it: apply the
	host first and its inline child re-base then runs against the children's own
	stale rects, which is the same defect mirrored. Deferring alone does not do it
	either: the child's first write still sees a stale origin. Together — document
	order here, and the adapter's re-base moved to `settleRects` after every rect
	has landed — a child whose parent-relative position did not change writes
	nothing at all.

	DOCUMENT ORDER IS ANCESTORS-FIRST BY CONSTRUCTION, so this needs no sort and no
	host bookkeeping: one walk of the live tree the renderer already knows how to
	do. **Do not put the hash back.** The sweep afterwards keeps the old behaviour
	for any solved path the walk cannot reach, which should be none.

	WHY IT IS A MODULE. Partly cohesion — "the rect pass" is a nameable thing with
	one rule — and partly the 200,000-character `Script.Source` WRITE cap, which
	`renderer.luau` is perpetually against: over it a module silently stops
	live-syncing into an open Studio session, so a live check tests the built place
	rather than the edits on disk. Everything it takes is read-only to it or a
	by-reference table declared once and never rebound (`handles`, `lastRects`,
	`lastBarInsets`, `stats`), which is the same seam test every other extraction
	from this file passed.
]]

local authority = require("./authority")

local rect_pass = {}

--[[ ctx:
	  adapter         the render target
	  handles         path -> adapter handle, by reference
	  lastRects       path -> the rect last written, by reference (the minimal-write
	                  contract's own record; a rect equal to it is not re-sent)
	  lastBarInsets   path -> the scroll bar gutter this solve spent, by reference
	  stats           the renderer's counters, by reference
	  rectsEqual      the pure rect comparison
]]
function rect_pass.new(ctx: any)
	local adapter = ctx.adapter
	local handles = ctx.handles
	local lastRects = ctx.lastRects
	local lastBarInsets = ctx.lastBarInsets
	local stats = ctx.stats
	local rectsEqual = ctx.rectsEqual

	local function applyOne(path: string, entry: any)
		local handle = handles[path]
		-- the bar gutter a scroll host spent this solve, carried on the same walk
		-- the rects are (solver: `out[id].barInset`). Nil on every node that is not
		-- an overflowing scroll host, which is nearly all of them, so this is one
		-- nil assignment per node rather than a second walk.
		lastBarInsets[path] = entry.barInset
		if handle ~= nil and not rectsEqual(lastRects[path], entry.rect) then
			authority.assertWrite("common", "size", "layout")
			adapter.setRect(handle, entry.rect)
			lastRects[path] = entry.rect
			stats.rectWrites += 1
		end
	end

	-- `rects` is the solve's `path -> entry` map; `rootNode` is the live tree it
	-- was solved from.
	local function apply(rootNode: any, rects: { [string]: any })
		local applied: { [string]: boolean } = {}
		local function walk(node: any)
			local entry = rects[node.path]
			if entry ~= nil then
				applied[node.path] = true
				applyOne(node.path, entry)
			end
			for _, child in node.children do
				walk(child)
			end
		end
		walk(rootNode)
		-- any solved path the walk could not reach — a node that left the tree
		-- between the solve and the apply. Order cannot matter for one of these:
		-- it has no live ancestor to be relative to.
		for path, entry in rects do
			if not applied[path] then
				applyOne(path, entry)
			end
		end
		-- ...and the DEFERRED RE-BASE. A host that moved may carry children this
		-- solve did not re-emit — an incremental re-solve of the host alone — and
		-- placing those is the adapter's business, not this walk's. It runs after
		-- every rect has landed, so a child it touches is re-based against two
		-- current numbers instead of one; with the adapter's write skip in front of
		-- it, a child already in the right place costs nothing. Feature-detected,
		-- like every other optional adapter capability.
		if adapter.settleRects ~= nil then
			adapter.settleRects()
		end
	end

	return { apply = apply }
end

return rect_pass
