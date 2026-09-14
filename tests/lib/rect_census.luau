--!strict
--[[ THE RECT CENSUS: what every node's solved box is right now, and how many of
	them changed between two of those answers.

	Lifted verbatim in behaviour from `bench/perf_scenes.luau`'s `probeRects` /
	`movedCount`, which the theme-swap scenes report as `movedRects` and
	`tools/check_perf_scenes.py` reads to hold "a palette-only swap must reflow
	nothing". The same question is the belt under the paint-only law
	(`tests/motion_paint_only.spec.luau`), so it lives here rather than being
	written a second time.

	APPEARING AND DISAPPEARING BOTH COUNT AS A MOVE. A node that is not in both
	answers has had its geometry decided at least once in between, which is the
	thing being counted; the bench's copy makes the same call for the same reason.

	FOLLOW-UP (2026-09-13): `bench/perf_scenes.luau` still carries its own copy —
	it was owned by another task at the time this was extracted, so it was left
	alone deliberately. Point it at this module the next time that file is open. ]]

local rect_census = {}

export type Census = { [string]: { x: number, y: number, w: number, h: number } }

function rect_census.of(adapter: any): Census
	local out: Census = {}
	for _, path in adapter.paths() do
		local node = adapter.node(path)
		local r = if node ~= nil then node.rect else nil
		if r ~= nil then
			out[path] = { x = r.x, y = r.y, w = r.w, h = r.h }
		end
	end
	return out
end

function rect_census.movedCount(before: Census, after: Census): number
	local moved = 0
	for path, a in after do
		local b = before[path]
		if b == nil or a.x ~= b.x or a.y ~= b.y or a.w ~= b.w or a.h ~= b.h then
			moved += 1
		end
	end
	for path in before do
		if after[path] == nil then
			moved += 1
		end
	end
	return moved
end

return rect_census
