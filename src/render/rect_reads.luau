--!strict
--[[ THE FOUR GEOMETRY READS, lifted out of `render/renderer.luau` on 2026-09-03
	(Plan C, T1) because the renderer stood 1,853 characters from the size line
	its own ledger row names, and the campaign's change is a change to exactly
	these reads: rects beneath an instance host that is a COORDINATE SPACE are
	stored host-relative, and `rectOf`/`screenRectOf` compose the host chain on
	read the way `screenRectOf` already composes the scroll and presentation
	shifts (T3 fills `hostOriginOf`; here it is the identity).

	ONE-WAY BY THE FILE'S OWN TEST. Everything this reads is a table the renderer
	mutates IN PLACE and never rebinds — `handles`, `lastRects`, `scrollHostOf`
	(`dispose` clears them with `table.clear` for exactly this reason) — plus the
	adapter and one function. No reassigned upvalue of the host crosses this
	boundary; `tests/rect_reads_seam.spec.luau` is the proof. ]]
local rect_reads = {}

export type Deps = {
	adapter: any,
	handles: { [string]: any },
	lastRects: { [string]: any },
	scrollHostOf: { [string]: string },
	presentationShift: (path: string) -> (number, number),
}

function rect_reads.new(deps: Deps)
	local adapter = deps.adapter
	local handles = deps.handles
	local lastRects = deps.lastRects
	local scrollHostOf = deps.scrollHostOf
	local presentationShift = deps.presentationShift

	--[[ path -> nearest COORDINATE-SPACE host ancestor, filled on the renderer's
		live-path walk (`livePaths`) exactly the way `scrollHostOf` is, and cleared in
		place with the renderer's other per-path maps.

		IT IS ALSO WHAT SAYS A CARRIED RECT MAY BE CARRIED. A stored rect beneath a
		space host is HOST-RELATIVE, so `renderer.restoreParkedProps` may move one onto
		a recycled path only when the two paths sit in the SAME space — otherwise the
		rect is in the wrong origin, and `rect_pass.applyOne` compares by VALUE, so the
		wrong rect would match the incoming one and write nothing. Dropping it instead
		costs one spare `setRect` per cross-space recycle and cannot be wrong. ]]
	local hostSpaceOf: { [string]: string } = {}
	-- the set of paths that ARE coordinate-space hosts (T3 fills it on the same walk)
	local spaceHosts: { [string]: true } = {}
	-- space host -> how many `Path` nodes live under it (T5's `visible` gate fills it
	-- on the same walk). A COUNT, so `noteUnder` DELETES the key at zero: `0` is
	-- truthy in Luau, and a gate written `if spaceHostHasPath[path] then` would
	-- otherwise refuse forever once a Path had ever been under that host.
	local spaceHostHasPath: { [string]: number } = {}
	--[[ ...AND THE ORDER THE DECREMENT DEPENDS ON, recorded here because it is a
		property of the CALLER and this is the map that pays for it. `noteFromHost`
		climbs `hostSpaceOf`, and `dropPath` clears that link — so a sweep that tore
		down a nested space host BEFORE the Path beneath it would stop the climb one
		host short and leave every surviving ancestor counted forever. The removal
		sweep therefore visits deepest first (T4b, `renderer.sweepDeparted`'s two
		arms), and a Path's path is strictly longer than that of any space host above
		it, so the Path is always reached first. ]]
	-- which space host a PATH node was last counted under, so a reparented Path can
	-- note the OLD host −1 and the NEW host +1. Keyed by the Path's own
	-- path; nil for a Path with no space host above it. WHO FILLS IT: `livePaths`
	-- (T5 step 3), on the same latch edge that fills `spaceHostHasPath`. WHO READS
	-- IT: two sites — `sweepDeparted`'s decrement, which starts its climb there, and
	-- that walk's reparent branch, which compares it against
	-- the nearest space host the walk has just computed, BEFORE `hostSpaceOf[path]`
	-- is rewritten for this walk. Nothing else reads it.
	local pathHostOf: { [string]: string } = {}
	-- absolute origin of a host, cached; invalidated wholesale by an epoch bump
	local originCache: { [string]: { x: number, y: number, epoch: number } } = {}
	-- the COMPOSED rect of a path, cached against the same epoch: inside a space
	-- host `rectOf` would otherwise allocate a fresh
	-- table per call, and ~30 sites compare what it returns BY IDENTITY —
	-- `slider.luau:183-185` skips a signal write on identity, and the pointer
	-- contract `(path, pos, rectOf)` is called per pointer MOVE by `table_rows`,
	-- `level_picker`, `virtual_list_hosted`, `region_expand`. Memoised per
	-- (path, epoch), identity is stable between host moves; the cost is one table
	-- per path under a host per host move, on demand.
	local composedCache: { [string]: { epoch: number, src: any, rect: any } } = {}
	local originEpoch = 0

	local function invalidateOrigins()
		originEpoch += 1
	end
	local function clearHosts()
		table.clear(hostSpaceOf)
		table.clear(spaceHosts)
		table.clear(originCache)
		table.clear(composedCache)
		table.clear(spaceHostHasPath)
		table.clear(pathHostOf)
		originEpoch += 1
	end
	-- ±1 on `hostPath` ITSELF and every space host above it. This is the entry point
	-- for a caller that already HAS the host rather than a path under it — T5's
	-- reparent branch knows the OLD host and the NEW host, and `noteUnder(map,
	-- oldHost, -1)` would start at `hostSpaceOf[oldHost]` and SKIP `oldHost`, which
	-- is the one host whose count actually changed. `nil` is a legal argument and a
	-- no-op (a Path with no space host above it). The key is DELETED at zero.
	local function noteFromHost(map: { [string]: number }, hostPath: string?, delta: number)
		local host = hostPath
		while host ~= nil do
			local n = (map[host] or 0) + delta
			map[host] = if n > 0 then n else nil
			host = hostSpaceOf[host]
		end
	end
	-- ±1 on every space-host ancestor of `path`; the key is DELETED at zero
	local function noteUnder(map: { [string]: number }, path: string, delta: number)
		noteFromHost(map, hostSpaceOf[path], delta)
	end
	-- one departed path (called from `sweepDeparted`): the bounded structural arm
	-- does not clear the whole map, and an origin read off a stale entry is a WRONG
	-- origin, not a slow one
	local function dropPath(path: string)
		hostSpaceOf[path] = nil
		spaceHosts[path] = nil
		originCache[path] = nil
		composedCache[path] = nil
		spaceHostHasPath[path] = nil
		pathHostOf[path] = nil
	end
	--[[ THE COMMIT SPAN'S OWN MAP, and the stable function that reads it. Two commit
		readers compare rects that may sit in different coordinate spaces —
		`commit_walks.authorPressableRects` and `hit_lift.refresh` — and both run
		BEFORE `rect_pass` rewrites `lastRects`, so `hostOriginOf` (which walks
		`lastRects`) would compose them against LAST frame's host origin: a one-frame
		lag on exactly the frame a host moved. `commit_walks.new` is built once per
		attach and wants a stable function, so the per-commit part is the MAP — the
		renderer assigns it at the top of the span. It is the CALLER's table, never
		cleared here — the renderer hands over a fresh empty one at `dispose`. ]]
	local commitRects: { [string]: any } = {}
	local function setCommitRects(rects: { [string]: any })
		commitRects = rects
	end
	-- the sum of the host chain above `path` — (0, 0) on every path with no
	-- coordinate-space host above it, which is every path on a host-free tree
	local function hostOriginOf(path: string): (number, number)
		local host = hostSpaceOf[path]
		if host == nil then
			return 0, 0
		end
		local cached = originCache[host]
		if cached ~= nil and cached.epoch == originEpoch then
			return cached.x, cached.y
		end
		local r = lastRects[host]
		local hx, hy = hostOriginOf(host)
		local x = hx + (if r ~= nil then r.x else 0)
		local y = hy + (if r ~= nil then r.y else 0)
		originCache[host] = { x = x, y = y, epoch = originEpoch }
		return x, y
	end
	-- THE SAME WALK OVER A CALLER-SUPPLIED MAP. `paintedRectIn` reads
	-- the CURRENT solve's `rects`, on purpose; `hostOriginOf` reads `lastRects`,
	-- which on the cull pass is last frame's. Uncached by construction — the map is
	-- the argument, so there is nothing stable to key on.
	local function originIn(rects: { [string]: any }, path: string): (number, number)
		local ox, oy = 0, 0
		local host = hostSpaceOf[path]
		while host ~= nil do
			local e = rects[host]
			local r = if e ~= nil then (e.rect or e) else nil
			if r ~= nil then
				ox += r.x
				oy += r.y
			end
			host = hostSpaceOf[host]
		end
		return ox, oy
	end

	-- drag math reads solved rects through this lookup. THE STORED TABLE, UNCHANGED,
	-- whenever the origin is (0, 0): `slider.luau` compares what this returns by
	-- identity to skip a signal write, and a host-free tree must stay byte-identical
	-- at the allocation level too (Plan C ruling R-6). INSIDE a host the composed
	-- table is memoised against the origin epoch so identity is stable
	-- between host moves and no per-read allocation happens.
	local function rectOf(path: string): any
		local rect = lastRects[path]
		if rect == nil then
			return nil
		end
		local ox, oy = hostOriginOf(path)
		if ox == 0 and oy == 0 then
			return rect
		end
		local cached = composedCache[path]
		-- `src` is compared BY IDENTITY: a stored rect is `table.freeze`d and replaced
		-- wholesale when it changes (Global Constraints), so a different table is the
		-- exact test for "this path's own rect moved", and the epoch is the test for
		-- "a host above it moved".
		if cached ~= nil and cached.epoch == originEpoch and cached.src == rect then
			return cached.rect
		end
		local out = { x = rect.x + ox, y = rect.y + oy, w = rect.w, h = rect.h }
		composedCache[path] = { epoch = originEpoch, src = rect, rect = out }
		return out
	end
	-- path -> its nearest ScrollView ANCESTOR's path (rebuilt every structural
	-- sync by the live-path walk). It exists for one reason: the solver arranges
	-- a scroll host's children in the HOST's own coordinate space and the engine
	-- shifts them by CanvasPosition, so a solved rect inside a scrolled list is
	-- NOT where that row is on screen. A pointer, meanwhile, always arrives in
	-- window space. Hit-testing one against the other silently targets the wrong
	-- row the moment the list is scrolled — which is precisely the case edge
	-- autoscroll spends its whole life in.
	local function scrollShift(path: string): (number, number)
		local dx, dy = 0, 0
		local host: string? = scrollHostOf[path]
		local guard = 0
		while host ~= nil and guard < 32 do
			local handle = handles[host]
			if handle ~= nil and adapter.getScrollPosition ~= nil then
				local pos = adapter.getScrollPosition(handle)
				if type(pos) == "table" then
					dx += pos.x or 0
					dy += pos.y or 0
				end
			end
			host = scrollHostOf[host]
			guard += 1
		end
		return dx, dy
	end
	-- the solved rect in WINDOW space: nested scroll offsets accumulate up the
	-- chain, so a list inside a scrolled panel still answers where it is drawn —
	-- and presentation offsets accumulate with them, so a shifted surface answers
	-- where it is drawn too.
	--
	-- `relativeTo` (gap 37, framework-gaps-phase2): optional second path whose
	-- WINDOW-space origin is subtracted from the answer, so a caller who wants
	-- "where is A inside B" gets it in one call instead of two `screenRectOf`
	-- reads and a hand-subtraction — the exact pattern three call sites in
	-- RascalRally's `StoryFlow.luau` (`_layerRectOf`/`_centreOf`) had each grown
	-- their own copy of. `nil` when either node is not live, same as the
	-- one-argument form; a node relative to ITSELF is `{x=0,y=0,w,h}`.
	local function screenRectOf(path: string, relativeTo: string?): any
		local rect = lastRects[path]
		if rect == nil then
			return nil
		end
		local dx, dy = scrollShift(path)
		local px, py = presentationShift(path)
		local hx, hy = hostOriginOf(path)
		local out = if dx == 0
				and dy == 0
				and px == 0
				and py == 0
				and hx == 0
				and hy == 0
			then rect
			else { x = rect.x - dx + px + hx, y = rect.y - dy + py + hy, w = rect.w, h = rect.h }
		if relativeTo == nil then
			return out
		end
		local origin = if relativeTo == path then out else screenRectOf(relativeTo)
		if origin == nil then
			return nil
		end
		return { x = out.x - origin.x, y = out.y - origin.y, w = out.w, h = out.h }
	end
	-- the same window-space answer over a solve's FRESH rects: the visibility
	-- pass runs before `lastRects` is updated, and culling this frame's paths
	-- against last frame's geometry is exactly the one-frame lag that makes a
	-- re-sorted row flash its ring outside the list.
	local function paintedRectIn(rects: any, path: string): any
		local rect = if rects[path] ~= nil then rects[path].rect else nil
		if rect == nil then
			return nil
		end
		local dx, dy = scrollShift(path)
		local px, py = presentationShift(path)
		-- `originIn`, NOT `hostOriginOf`: the argument map is the fresh one this
		-- function exists to read, not last frame's `lastRects`.
		local hx, hy = originIn(rects, path)
		if dx == 0 and dy == 0 and px == 0 and py == 0 and hx == 0 and hy == 0 then
			return rect
		end
		return { x = rect.x - dx + px + hx, y = rect.y - dy + py + hy, w = rect.w, h = rect.h }
	end

	local function commitOriginOf(path: string): (number, number)
		return originIn(commitRects, path)
	end

	return {
		rectOf = rectOf,
		scrollShift = scrollShift,
		screenRectOf = screenRectOf,
		paintedRectIn = paintedRectIn,
		hostSpaceOf = hostSpaceOf,
		spaceHosts = spaceHosts,
		spaceHostHasPath = spaceHostHasPath,
		pathHostOf = pathHostOf,
		hostOriginOf = hostOriginOf,
		originIn = originIn,
		noteUnder = noteUnder,
		noteFromHost = noteFromHost,
		invalidateOrigins = invalidateOrigins,
		setCommitRects = setCommitRects,
		commitOriginOf = commitOriginOf,
		clearHosts = clearHosts,
		dropPath = dropPath,
	}
end

return rect_reads
