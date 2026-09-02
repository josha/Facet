--!strict
--[[ boundary_report — THE STAGE 1 REPORT, and nothing else.

	Public interface, one entry point:

	  `boundary_report.report(root, result) -> distribution`
	      the answer to "if any single node changed size, how much of the tree
	      would a boundary-aware layout have to redo?", for the tree as solved.
	      `result` must come from a solve run with `{ analyzeBoundaries = true }`;
	      without it the report raises at the CALLER's line (level 2), because the
	      mistake is always the solve that did not ask for the analysis.

	Re-exported by the solver as `solver.boundaryReport`, which is the name every
	consumer, doc and spec writes and the name the error message keeps.

	WHY IT IS ITS OWN FILE. `tools/lune/verify/data/source-cap-ledger.md`'s solver
	row carries a trigger that is a STATE rather than a number — "the next round
	that opens this file for more than a comment takes a seam FIRST" — and the two
	seams that row named (`flowPartition`/`flowPlan`, the placement arithmetic) were
	both taken on 2026-08-22, so the row was naming candidates that had already
	left. This is the one that replaced them, and it is the cheapest seam this file
	has ever had: it reads NO `ctx`, no mutable upvalue, no helper of the solver and
	not even the solver's `Node` type at runtime — the whole of its input is the two
	arguments, and its output is a fresh table of numbers.

	`root` AND `result` ARE TYPED `any` ON PURPOSE, the way `./shrink`, `./grid`,
	`./flow` and `./measure_facts` type theirs: the solver requires THIS module, so
	importing `solver.Node` back would be the require cycle the split exists to
	avoid, and re-declaring the schema here is the copy-goes-stale failure the seam
	is for. What it actually reads of a node is `id` and `children`, and what it
	reads of a result is `work.boundary` — three fields, all of them stable.

	IT IS NOT ON ANY FRAME PATH. `controller.analyzeBoundaries()` is a Stage-1
	measurement tool (`examples/performance/lab`, `tests/perf_lab.spec.luau`), which
	is the other half of why the walk below is written for clarity rather than for
	allocation: one array of nodes, one parent map, one subtree-size map, one sort.

	===== WHAT IT ANSWERS =========================================================

	For each node it walks upward to the nearest ancestor that ABSORBS a size change
	(inclusive of the node itself — a fixed-size node absorbs its own content's
	change) and counts that ancestor's subtree. With no absorbing ancestor the answer
	is the whole tree, which is what Facet does today for every node.

	Reported as a distribution rather than one number because the interesting fact is
	the SHAPE: if the median node is isolated to a handful of nodes but the mean is
	the whole tree, the win is real but uneven, and that changes what Stage 2 should
	do first.
]]

local boundary_report = {}

function boundary_report.report(root: any, result: any): any
	local boundary = result and result.work and result.work.boundary
	if boundary == nil then
		error("solver.boundaryReport: solve with { analyzeBoundaries = true } first", 2)
	end
	local parentOf: { [string]: string } = {}
	local subtree: { [string]: number } = {}
	local order: { any } = {}

	local function walk(node: any, parent: any?)
		if parent ~= nil then
			parentOf[node.id] = parent.id
		end
		table.insert(order, node)
		for _, child in node.children or {} do
			walk(child, node)
		end
	end
	walk(root, nil)

	-- subtree sizes, bottom-up over the same order
	for i = #order, 1, -1 do
		local node = order[i]
		local n = 1
		for _, child in node.children or {} do
			n += subtree[child.id] or 1
		end
		subtree[node.id] = n
	end

	local total = #order
	local affected: { number } = {}
	local absorbed = 0
	for _, node in order do
		if boundary[node.id] == true then
			absorbed += 1
		end
		-- nearest absorbing ancestor, INCLUSIVE
		local at: string? = node.id
		local hops = 0
		while at ~= nil and boundary[at] ~= true and hops <= total do
			at = parentOf[at]
			hops += 1
		end
		table.insert(affected, if at ~= nil and boundary[at] == true then (subtree[at] or total) else total)
	end
	table.sort(affected)
	local sum = 0
	for _, v in affected do
		sum += v
	end
	local function pct(p: number): number
		return affected[math.max(1, math.min(#affected, math.floor(#affected * p)))]
	end
	return {
		nodes = total,
		absorbingNodes = absorbed,
		-- how many nodes a single change would re-lay-out, if boundaries were honoured
		meanAffected = if #affected > 0 then sum / #affected else 0,
		medianAffected = pct(0.5),
		p95Affected = pct(0.95),
		worstAffected = affected[#affected],
		-- what Facet does today for every single change
		todayAffected = total,
		-- 1.0 = boundaries would buy nothing; 0.1 = a change touches a tenth of the tree
		meanShareOfTree = if total > 0 and #affected > 0 then (sum / #affected) / total else 1,
	}
end

return boundary_report
