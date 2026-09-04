--!strict
-- Deterministic layout dump (design §7.5, UI-DIAG-001): converts a solver
-- result + snapshot into a versioned, machine-readable tree with stable
-- ordering (children in declaration order; keys canonical). Feeds the render
-- command's fixtures and later the Studio differential comparison.

local solver = require("./solver")

local dump = {}

--[[ `ox`/`oy` is the ABSOLUTE ORIGIN of the coordinate space this node sits in
	(Plan C). A rect beneath a space host is stored RELATIVE to that host, and a dump
	is read as window-space geometry — so the accumulator rides the recursion this
	function already does, computed from each host's own entry BEFORE descending into
	it. Two numbers rather than a per-node map, and self-contained: `dump` is handed
	`result.rects` and never sees a solver `ctx`, so it could not read one anyway. ]]
local function nodeDump(node: solver.Node, rects: { [string]: any }, ox: number, oy: number): any
	local entry = rects[node.id]
	local rect = entry and entry.rect
	if rect ~= nil and (ox ~= 0 or oy ~= 0) then
		rect = { x = rect.x + ox, y = rect.y + oy, w = rect.w, h = rect.h }
	end
	local d: any = {
		id = node.id,
		kind = node.kind,
		rect = rect,
		overflow = entry and entry.overflow,
		textState = entry and entry.textState,
		-- PER-TEXT-NODE MEASUREMENT FACTS: the font descriptor and px size
		-- this solve measured with, the natural and drawn line counts, whether the
		-- engine will ellipsize, whether the author declared a way back to the full
		-- string (`disclose`, and/or the auto `reveal` with its `naturalWidth`,
		-- 2026-08-04), and the resulting overflow policy ("wrap" | "cap" |
		-- "truncate" | "truncate+disclose" | "truncate+reveal"). Nil on every node
		-- that is not text — a dump that reported a truncation state for a Box
		-- would be inviting a reader to act on a number about nothing.
		textFacts = entry and entry.textFacts,
		-- the declared interactive floor: carried so a DUMP-based audit
		-- can run text_audit.hitFloor without the live rects table
		hitFloor = entry and entry.hitFloor,
		contentSize = entry and entry.contentSize,
		-- the composition resolution rides the same channel as the
		-- rect it produced: WHICH arrangement, WHICH form per region, and WHY
		-- every richer candidate lost. Nil on every node that is not one.
		composition = entry and entry.composition,
		-- a region/candidate that lost is present in the tree and absent from the
		-- screen; a dump that did not say so would read as a layout bug
		hidden = entry and entry.hidden,
		dims = {
			width = (node.width or { type = "content" }).type,
			height = (node.height or { type = "content" }).type,
		},
	}
	if node.children then
		-- this node's own entry rect is what its subtree is stored against, so the
		-- push happens here, from the PARENT-space rect above
		local childOx, childOy = ox, oy
		if node.hostSpace == true and entry ~= nil and entry.rect ~= nil then
			childOx += entry.rect.x
			childOy += entry.rect.y
		end
		d.children = {}
		for _, child in node.children do
			table.insert(d.children, nodeDump(child, rects, childOx, childOy))
		end
	end
	return d
end

function dump.fromSolve(
	root: solver.Node,
	viewport: { w: number, h: number },
	opts: { safeInsets: solver.SafeInsets?, rootPolicy: string? }?
): any
	local result = solver.solve(root, viewport, opts)
	return {
		-- /2 adds `textFacts` per text node. Additive, so a /1 reader keeps
		-- working; the version moves because a diff against a stored /1 fixture
		-- would otherwise read as a layout change.
		-- NO BUMP for `measured` (T9): each `diagnostics` finding now carries an
		-- internal `measured: boolean?` stamp, same class as `filedBy` — additive
		-- on a table no reader enumerates, so it is not a schema change.
		schema = "facet-dump/2",
		viewport = viewport,
		rootPolicy = (opts and opts.rootPolicy) or "coreSafeContent",
		safeInsets = (opts and opts.safeInsets) or { top = 0, bottom = 0, left = 0, right = 0 },
		contentRect = result.contentRect,
		diagnostics = result.diagnostics,
		tree = nodeDump(root, result.rects, 0, 0),
	}
end

return dump
