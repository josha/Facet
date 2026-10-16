--!strict

export type Node = {
	parent: unknown,
	path: string,
	identity: number?,
	x: number?,
	y: number?,
	width: number?,
	height: number?,
	text: string?,
}
export type Snapshot = { [unknown]: Node }
export type Exclusion = { path: string, identity: number, reason: string, before: string, after: string }

local function describe(node: Node): string
	return `{node.x},{node.y} {node.width}x{node.height} Text={node.text}`
end

local function geometry(a: Node, b: Node): boolean
	return a.x ~= b.x or a.y ~= b.y or a.width ~= b.width or a.height ~= b.height
end

local function compare(before: Snapshot, after: Snapshot): (boolean, { Exclusion })
	local changed = next(after) == nil
	local excluded: { Exclusion } = {}
	for id, node in after do
		local old = before[id]
		if old == nil or old.parent ~= node.parent then
			changed = true
			continue
		end
		local reason: string? = nil
		if node.text ~= nil and old.text ~= node.text then
			reason = "text changed this frame"
		elseif geometry(old, node) then
			local parent, oldParent = after[node.parent], before[node.parent]
			local oneAxis = (node.width ~= old.width) ~= (node.height ~= old.height)
			if
				parent
				and oldParent
				and parent.width ~= nil
				and parent.width == oldParent.width
				and parent.height == oldParent.height
				and oneAxis
				and node.x == old.x
				and node.y == old.y
			then
				reason = "one-axis fill inside a fixed-size parent"
			end
		end
		if reason then
			table.insert(excluded, {
				path = node.path,
				identity = node.identity or 0,
				reason = reason,
				before = describe(old),
				after = describe(node),
			})
		elseif geometry(old, node) then
			changed = true
		end
	end
	for id in before do
		if after[id] == nil then
			changed = true
		end
	end
	return changed, excluded
end

export type Run = { previous: Snapshot, lastChange: number, started: number, seconds: number? }

local function start(snapshot: Snapshot, now: number): Run
	return { previous = snapshot, lastChange = now, started = now }
end

local function step(run: Run, snapshot: Snapshot, now: number, quiet: number): { Exclusion }
	local changed, excluded = compare(run.previous, snapshot)
	run.previous = snapshot
	if run.seconds == nil then
		if changed then
			run.lastChange = now
		end
		if now - run.lastChange >= quiet then
			run.seconds = run.lastChange - run.started
		end
	end
	return excluded
end

return { compare = compare, start = start, step = step }
