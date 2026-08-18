--!strict
--[[ CROSS-SURFACE OVERLAP — two mounted surfaces covering each other (ADR-0028).

	WHAT IT DOES. Answers, for one paint target, "which pairs of live surfaces
	cover each other without either having said it means to". ADR-0025's
	`resolution.collisions` answers the same question one level down — which
	REGIONS of a single `UI.Composition` paint into each other — and this file
	deliberately reuses its shape and its vocabulary: a painted box per
	participant, an unordered pairwise scan of intersections, `{ a, b, dx, dy }`
	sorted by id, and one English sentence per pair filed as a `diagnostics()`
	finding. It is the same alarm, asked of surfaces instead of regions.

	THE PREDICATE, which is the whole design:

	    fire when two live surfaces on one target both COVER something, their
	    cover rects intersect, and NEITHER declared that it means to cover the
	    other.

	Cross-surface overlap is not a defect by itself — a modal SHOULD cover a HUD;
	that is what a modal is for. What is a defect is two surfaces on top of each
	other that nobody ordered, because then which one a player sees is an accident
	of mount order. So the alarm reads DECLARATIONS, and the vocabulary already
	existed:

	  * `rootPolicy = "edgeToEdge"` — the renderer's own words for it are "a
	    DECORATION layer, not content" (renderer.luau, ROOT_POLICIES). Every
	    scrim, catcher, popover plate and drag ghost the presenter mounts is one.
	    It is a declaration on EITHER side of the pair: a scrim means to cover,
	    and a scrim means to be covered.
	  * a DIFFERENT DISPLAY BAND — `presenter.SURFACE_LAYER`'s four bands exist so
	    that "a toast is above every base screen and below every modal, whatever
	    order they arrived in". Two surfaces in different bands are layered on
	    purpose. Two in the same band are not: within a band the presenter simply
	    steps +100 per surface, which is arrival order, not intent.
	  * an UNSET display order declares nothing at all, which is why the band is
	    `nil` until `controller.setDisplayOrder` is called. A surface raised by a
	    bare `renderer.attach` and never ordered — a debug probe — has said
	    nothing about where it belongs, and that is precisely the case that
	    commissioned this file.

	AND A SURFACE THAT COVERS NOTHING IS IN NO PAIR (ADR-0026's hand-off). A
	surface at `opacity = 0` occupies its box and covers nothing visible; `hidden`
	is the same shape, so is a framework fade to nothing, so is a root the
	presenter has switched off while it waits for exact text. A geometry-only test
	would report a collision no player can see. `coverRect` answers `nil` for all
	of them by construction rather than by a list of special cases: it is the
	union of what the surface actually paints, and a node that paints nothing
	contributes nothing to a union.

	PUBLIC INTERFACE (internal to the framework; reached by consumers through
	`controller.coverRect()` and `controller.diagnostics()`):

	    surface_overlap.bandOf(displayOrder)        -> number
	    surface_overlap.coverRect(rootPath, rects, excluded) -> Rect?
	    surface_overlap.scan({ Surface })           -> { Overlap }   -- pure
	    surface_overlap.issue(overlap)              -> string
	    surface_overlap.register(target, entry)     -> () -> ()      -- unregister
	    surface_overlap.findingsFor(target, entry)  -> { Finding }
	    surface_overlap.scans()                     -> number        -- see COST

	COST — ZERO OFF THE INSPECTION PATH, AND IT IS A TEST RATHER THAN A CLAIM.
	Nothing here runs in a solve, a commit or a frame. A surface pays one table
	write when it attaches and one when it disposes, and everything else happens
	inside `controller.diagnostics()`, which is a diagnostic read. That is not an
	optimisation, it is the correct place: a cross-surface fact is not a property
	of any one surface's solve — it changes when ANOTHER surface mounts, moves or
	fades, which this surface's solve cannot see — so computing it at solve time
	would be both stale on one side and duplicated on the other. `scans()` counts
	the pairwise passes so `tests/surface_overlap.spec.luau` can assert the frame
	path performs zero of them.

	Depends on: nothing. Pure Luau; no engine, no core, no solver.
]]

local rectLib = require("../rect")
local num = require("../num")
-- bound at module scope: `solver.luau` records that a per-call allocation on
-- the measure path is a bench regression this repository has already paid for
local roundPx = num.roundPx

local surface_overlap = {}

export type Rect = { x: number, y: number, w: number, h: number }

-- one participant in the scan, as the scan sees it: four facts, no controller
export type Surface = {
	id: string,
	-- what this surface actually paints, or nil when it paints nothing
	rect: Rect?,
	-- the layer it declared, or nil when it never declared one
	displayOrder: number?,
	rootPolicy: string,
}

export type Overlap = {
	a: string,
	b: string,
	dx: number,
	dy: number,
	-- the id of the surface entirely inside the other's cover rect, when there
	-- is one. A full cover and a clipped corner are different bugs and the
	-- sentence says which.
	covered: string?,
}

-- THE BAND WIDTH, DERIVED FROM `presenter.SURFACE_LAYER` RATHER THAN COPIED.
-- That table is `{ base = 10000, toast = 20000, dragProxy = 30000, modal = 40000 }`
-- and its own header explains the spacing: "within a band, creation order still
-- decides (each surface takes the next +100 step), so ~100 live surfaces per band
-- before two would tie". So a band is the 10 000-wide bucket, and the +100 step,
-- the scrim's -50 and the plate's +25 all stay inside their owner's bucket.
-- `tests/surface_overlap.spec.luau` reads the presenter's real table and fails if
-- the two ever disagree, so this is a derivation with a pin, not a second copy.
local LAYER_BAND = 10000
surface_overlap.LAYER_BAND = LAYER_BAND

function surface_overlap.bandOf(displayOrder: number): number
	return math.floor(displayOrder / LAYER_BAND)
end

-- how many pairwise passes have run, ever. The instrument behind this file's
-- zero-cost claim (see COST above); it is an integer increment inside the scan
-- and is read by tests only.
local scanCount = 0
function surface_overlap.scans(): number
	return scanCount
end

--[[ coverRect(rootPath, rects, excluded) -> Rect?

	The union of every painted box BELOW the surface's root.

	The root itself is excluded on purpose. A `UI.Screen`'s rect is the content
	rect its `rootPolicy` resolved — the box the surface is ALLOWED to paint in,
	which is the same box for every base screen on the device and would make
	every pair a full-screen collision. What a surface covers is what it puts in
	that box. (A fill container inside it still claims the whole screen, and that
	is honest: a container that fills the screen may put its content anywhere in
	it, at any viewport and any text size.)

	`excluded(path)` is the caller's "this node paints nothing, and neither does
	anything under it" test — hidden, held, or faded to nothing. It is asked once
	per node, and a nil or zero-area rect is skipped without asking.
]]
function surface_overlap.coverRect(rootPath: string, rects: { [string]: Rect }, excluded: (string) -> boolean): Rect?
	local minX, minY, maxX, maxY
	for path, rect in rects do
		if path == rootPath or rect == nil or rect.w <= 0 or rect.h <= 0 then
			continue
		end
		if excluded(path) then
			continue
		end
		if minX == nil then
			minX, minY, maxX, maxY = rect.x, rect.y, rect.x + rect.w, rect.y + rect.h
		else
			minX = math.min(minX :: number, rect.x)
			minY = math.min(minY :: number, rect.y)
			maxX = math.max(maxX :: number, rect.x + rect.w)
			maxY = math.max(maxY :: number, rect.y + rect.h)
		end
	end
	if minX == nil then
		return nil
	end
	return {
		x = minX :: number,
		y = minY :: number,
		w = (maxX :: number) - (minX :: number),
		h = (maxY :: number) - (minY :: number),
	}
end

-- DID EITHER OF THEM SAY IT MEANS TO COVER THE OTHER? Symmetric on purpose: the
-- brief's rule is "neither declared", and a scrim declaring `edgeToEdge`
-- excuses the pair whichever side of it the other surface is on.
local function declared(a: Surface, b: Surface): boolean
	if a.rootPolicy == "edgeToEdge" or b.rootPolicy == "edgeToEdge" then
		return true
	end
	local oa, ob = a.displayOrder, b.displayOrder
	if oa == nil or ob == nil then
		return false
	end
	return surface_overlap.bandOf(oa) ~= surface_overlap.bandOf(ob)
end
surface_overlap.declared = declared

local contains = rectLib.contains

--[[ scan(surfaces) -> { Overlap }

	The pure half: every unordered pair, one intersection test each, sorted by id
	so a report is the same on every run. This is ADR-0025's collision loop with
	regions swapped for surfaces — same arithmetic, same `{ a, b, dx, dy }` row,
	same "touching is not overlapping" epsilon of zero (an intersection has to
	have area).
]]
function surface_overlap.scan(surfaces: { Surface }): { Overlap }
	scanCount += 1
	-- only the ones that cover something can be in a pair, and sorting makes the
	-- pair order independent of registration order
	local covering: { Surface } = {}
	for _, s in surfaces do
		local r = s.rect
		if r ~= nil and r.w > 0 and r.h > 0 then
			table.insert(covering, s)
		end
	end
	if #covering < 2 then
		return {}
	end
	table.sort(covering, function(x, y)
		if x.id ~= y.id then
			return x.id < y.id
		end
		return (x.displayOrder or -1) < (y.displayOrder or -1)
	end)

	local out: { Overlap } = {}
	for i = 1, #covering do
		for j = i + 1, #covering do
			local a, b = covering[i], covering[j]
			if declared(a, b) then
				continue
			end
			local ra, rb = a.rect :: Rect, b.rect :: Rect
			local dx, dy = rectLib.intersection(ra, rb)
			if dx > 0 and dy > 0 then
				local covered: string? = nil
				if contains(ra, rb) then
					covered = b.id
				elseif contains(rb, ra) then
					covered = a.id
				end
				table.insert(out, {
					a = a.id,
					b = b.id,
					dx = roundPx(dx),
					dy = roundPx(dy),
					covered = covered,
				})
			end
		end
	end
	return out
end

-- THE REMEDIES, IN THE SENTENCE. `the-solver-already-told-you.md`'s rule: a
-- finding that names the defect and not the fix is a finding an author reads
-- twice and acts on once.
local REMEDY = "(put one in a display band above the other with setDisplayOrder, "
	.. "present it edgeToEdge if it is a decoration layer, hide it while it is not "
	.. "wanted, or dismiss it)"

--[[ issue(overlap) -> the one sentence, identical on both surfaces of the pair.

	It is one sentence per PAIR rather than one per victim because neither
	surface is the offender: ADR-0025 could name the region painting outside its
	own box, and here both surfaces are inside theirs — the defect is that nobody
	said which is on top.
]]
function surface_overlap.issue(o: Overlap): string
	local head
	if o.covered ~= nil then
		local coverer = if o.covered == o.a then o.b else o.a
		head = `surface '{coverer}' completely covers surface '{o.covered}' ({o.dx}x{o.dy}px)`
	else
		head = `surface '{o.a}' overlaps surface '{o.b}' by {o.dx}x{o.dy}px`
	end
	return `{head} — two independently mounted surfaces cover each other and neither declared that it `
		.. `means to, so which one a player sees is an accident of mount order {REMEDY}`
end

--[[ ── THE LIVE REGISTRY ──────────────────────────────────────────────────────

	One entry per attached surface, bucketed by PAINT TARGET, because that is
	what "the same screen" means: two surfaces on two adapters are two windows
	and can no more overlap than two devices can.

	Weak-keyed on the target, exactly as `src/client/theme_controller.luau`'s
	`liveControllers` is weak-keyed on the environment, so a target that goes
	away takes its bucket with it. The entries themselves are removed explicitly
	by `controller.dispose()`; the weak keys are the backstop, not the plan.
]]
-- The registered surface: its id, and ONE closure that answers the four facts
-- the scan reads. A closure rather than four fields because every one of them is
-- live — the cover rect changes with the solve, the display order with a
-- `setDisplayOrder` — and a snapshot taken at scan time cannot go stale between
-- registration and the read.
export type Entry = {
	id: string,
	snapshot: () -> Surface,
}

local live: { [any]: { [any]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

function surface_overlap.register(target: any, entry: Entry): () -> ()
	local bucket = live[target]
	if bucket == nil then
		bucket = {}
		live[target] = bucket
	end
	bucket[entry] = true
	return function()
		local b = live[target]
		if b ~= nil then
			b[entry] = nil
		end
	end
end

-- how many surfaces are live on this target. The cheap precondition: with fewer
-- than two there is nothing to intersect and nothing below runs at all.
function surface_overlap.count(target: any): number
	local bucket = live[target]
	if bucket == nil then
		return 0
	end
	local n = 0
	for _ in bucket do
		n += 1
	end
	return n
end

export type Finding = { node: string, issue: string }

--[[ findingsFor(target, entry) -> the findings THIS surface should report.

	Filed on both surfaces of a pair, and here is why: `controller.diagnostics()`
	is per surface, and a consumer holding the base screen's controller (which is
	all `tests/overflow_sweep.spec.luau` holds) would otherwise never hear that
	something landed on top of it. A pair is symmetric and its sentence is
	identical on both sides; only the `node` differs, and it is the surface's own
	root path so a report points at a path the reader can look up.
]]
function surface_overlap.findingsFor(target: any, entry: Entry, rootPath: string): { Finding }
	local bucket = live[target]
	if bucket == nil or bucket[entry] == nil then
		return {}
	end
	-- THE CHEAP PRECONDITION, and the whole cost on a one-surface target: no
	-- cover rect is computed, no descriptor table is built, no pair loop runs.
	local n = 0
	for _ in bucket do
		n += 1
		if n >= 2 then
			break
		end
	end
	if n < 2 then
		return {}
	end

	local surfaces: { Surface } = {}
	for other in bucket do
		table.insert(surfaces, other.snapshot())
	end
	local out: { Finding } = {}
	for _, o in surface_overlap.scan(surfaces) do
		if o.a == entry.id or o.b == entry.id then
			table.insert(out, { node = rootPath, issue = surface_overlap.issue(o) })
		end
	end
	return out
end

return surface_overlap
