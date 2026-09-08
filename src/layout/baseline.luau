--!strict
-- Baselines are semantic line-box guides, not captured glyph outlines. The
-- typography role's baseline is an em ratio (default .8), with half the leading
-- above it. Nested guides come from the existing solver's arranged geometry.
local facts = require("./measure_facts")
local textMetrics = require("./text_metrics")
local baseline = {}
function baseline.is(value: any): boolean
	return value == "firstTextBaseline" or value == "lastTextBaseline"
end
function baseline.alignment(parent: any, child: any): any
	return child.lineAlign or child.align or parent.align
end
function baseline.has(node: any): boolean
	if node.baselineAligned ~= nil then
		return node.baselineAligned
	end
	if baseline.is(node.align) then
		if not table.isfrozen(node) then
			node.baselineAligned = true
		end
		return true
	end
	for _, child in node.children or {} do
		if baseline.is(baseline.alignment(node, child)) then
			if not table.isfrozen(node) then
				node.baselineAligned = true
			end
			return true
		end
	end
	if not table.isfrozen(node) then
		node.baselineAligned = false
	end
	return false
end
function baseline.text(node: any, tf: any, height: number, which: string, metrics: any): number
	local pt, _, pb = facts.sides(node.padding)
	local line = tf.size * (tf.lineHeight or 1.2)
	local lines = math.max(1, tf.lines or 1)
	local box = textMetrics.lineBoxPx(tf.size, lines, tf.lineHeight)
	local leading = (line - tf.size) / 2
	local role = if type(node.textSize) == "string" and metrics ~= nil then metrics.type[node.textSize] else nil
	local ratio = node.textBaseline or (if role ~= nil then role.baseline else nil) or 0.8
	local first = pt + math.max(0, (height - pt - pb - box) / 2) + leading + tf.size * ratio
	return math.clamp(first + (if which == "lastTextBaseline" then (lines - 1) * line else 0), 0, height)
end
local function cloneTree(node: any): any
	local copy = table.clone(node)
	-- Solver-owned memo records must never be shared with the measurement probe.
	copy.cmemo, copy.oMemo, copy.hostSpace = nil, nil, nil
	copy.mStamp = nil
	if node.children then
		local descendants = {}
		for _, child in node.children do
			table.insert(descendants, cloneTree(child))
		end
		copy.children = descendants
	end
	return copy
end
function baseline.offset(solve: any, ctx: any, node: any, width: number, height: number, which: string): number
	if node.kind == "text" and ctx.textFacts[node.id] then
		return baseline.text(node, ctx.textFacts[node.id], height, which, ctx.metrics)
	end
	if not node.children or #node.children == 0 then
		return height
	end
	-- The clone is confined to an opted-in nested baseline participant. Calling
	-- the same solver keeps padding, wrapping, grids, frames and candidate choice
	-- under one authority; none of the probe's caches or findings escape it.
	local cache = ctx.baselineCache
	if cache == nil then
		cache = {}
		ctx.baselineCache = cache
	end
	local key = `{node.id}|{width}|{height}|{which}`
	if cache[key] ~= nil then
		return cache[key]
	end
	local copy = cloneTree(node)
	copy.width, copy.height = { type = "fixed", px = width }, { type = "fixed", px = height }
	local solved = solve(
		copy,
		{ w = width, h = height },
		{ rootPolicy = "edgeToEdge", metrics = ctx.metrics, baselineCache = cache }
	)
	local guide: number? = nil
	local function visit(current: any)
		local entry = solved.rects[current.id]
		if entry and entry.hidden == true then
			return
		end
		if entry and entry.textFacts and entry.hidden ~= true then
			local value = entry.rect.y + baseline.text(current, entry.textFacts, entry.rect.h, which, ctx.metrics)
			guide = if guide == nil
				then value
				elseif which == "firstTextBaseline" then math.min(guide, value)
				else math.max(guide, value)
		end
		for _, child in current.children or {} do
			visit(child)
		end
	end
	visit(copy)
	local value = math.clamp(guide or height, 0, height)
	cache[key] = value
	return value
end
-- One group per baseline word: explicit first and last overrides can coexist.
function baseline.line(offset: any, ctx: any, node: any, sizes: any, first: number, last: number): (any, number)
	local groups, cross = {}, 0
	for i = first, last do
		local child, s = node.children[i], sizes[i]
		local align = baseline.alignment(node, child)
		cross = math.max(cross, s.h + s.mt + s.mb)
		if baseline.is(align) then
			local b = offset(ctx, child, s.w, s.h, align)
			local group = groups[align] or { above = 0, below = 0 }
			group.above = math.max(group.above, s.mt + b)
			group.below = math.max(group.below, s.mb + s.h - b)
			groups[align] = group
		end
	end
	for _, group in groups do
		cross = math.max(cross, group.above + group.below)
	end
	return groups, cross
end
return baseline
