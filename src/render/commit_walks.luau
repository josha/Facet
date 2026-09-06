--!strict
--[[ THE COMMIT WALKS — everything that turns a finished solve into adapter writes.

	One solve produces one `rects` map, and six separate walks of the live tree
	spend it: the two typography paint seams, the solver's own text verdicts, the
	visibility verdict, the hit-geometry floor, and the native scroll canvas. They
	are grouped here because they are the same KIND of thing — a depth-first walk
	that compares a solve output against a per-path record of what was last
	written and sends only the difference — and because every one of them is a
	MINIMAL-WRITE contract whose record lives outside it.

	THE RECORDS STAY WITH THE RENDERER, BY REFERENCE. `lastTextSize`,
	`lastTextFont`, `lastPadding`, `lastCompact`, `lastWrapped`, `lastVisible`,
	`lastHitRects`, `lastScrollRegions` are declared in `render/renderer.luau` and
	handed here as tables. That is not an accident of extraction: the renderer's
	removal sweep clears them when a path leaves, and its parked-props record
	carries five of them across an instance RECYCLE
	(`captureParkedProps`/`restoreParkedProps`), so the owner of the lifetime has
	to be the file that owns mounting. A table is already a reference, so sharing
	one costs nothing and creates no way back — which is the same seam test
	`render/rect_pass.luau` passed, and the reason this module reads not one
	reassigned local of its host.

	WHY IT IS A MODULE. Roblox refuses a `Script.Source` assignment at 200,000
	characters, and every LIVE path is a write, so a module over the cap silently
	stops syncing into an open Studio session and a live check then tests the code
	baked into the place rather than the edits on disk.
	`renderer.luau` reached 198,974 — 1,026 characters of headroom — and
	`tools/lune/verify/data/source-cap-ledger.md` had this extraction OWED BEFORE the next
	change of any size. The prescription there was "rect_pass-shaped: lift the
	RECT WRITE half of solveAndApply"; the rect diff-and-write loop itself had
	already left in `rect_pass.luau` (2026-08-17, one day before that row was
	written), so what shipped is the rest of the same half — the five other write
	loops the commit span runs beside it.

	THE OLD NAMES, so prose elsewhere still resolves. Inside `renderer.luau` these
	six were `applyTextScale`, `applyPadding`, `applyTextVerdicts`, `pushVisible`,
	`pushHitRects` and `pushRegions`; a comment in another module naming one of
	those means the function of that shape here. `src/client/screen_target.luau`
	still spells two of them the old way on purpose — it is itself inside the
	source-cap band, and a rename there costs it characters it does not have.

	WHAT DELIBERATELY STAYED BEHIND. The commit span's ORDER is the renderer's:
	visibility before hit geometry before rects before canvases, with the
	text-measurement follow-up last, and each of those orderings has its own
	recorded reason at the call site. So does the overhang lift
	(`render/hit_lift.luau`) and the z walk it triggers — a lift is paint ORDER,
	not a rect, and `syncZOrder` is declared far below the walks that need it.
]]

local authority = require("./authority")
local layout_node = require("./layout_node")
local themeSnapshot = require("../themes/snapshot")
-- the ONE reading of the `textSize = "fit"` grammar (shared with the schema and
-- with `render/layout_node.textOf`, which resolves the band the solver picks from)
local textFit = require("../layout/text_fit")
local solver = require("../layout/solver")

local commit_walks = {}

--[[ A TOUCH FLOOR THAT GROWS UNTIL IT MEETS SOMETHING PRESSABLE (DIR5 review H1).

	`own` is the rect the node paints, `want` is the floor it would like, and
	`blockers` are the rects the caller decided may stop it — for a cover, every
	AUTHOR-declared node that can sink a press (ruling R23). The
	answer is `want`, given back one side at a time, each side stopping at the first
	blocker in its way and never shrinking past `own`.

	WHY GROWTH RATHER THAN A BOX TO CLAMP INTO. R18's ruling splits by what is
	UNDERNEATH: the 44px floor is EXEMPT over PASSIVE content — it is the F1
	accessibility floor and the convention every platform ships — and BANNED over
	INTERACTIVE content, because two actionable targets for one gesture is an
	ambiguity the player cannot see. So the bound is other pressable things, not a
	container. A first version clamped a cover into its REGION instead, and the
	measurement refused it: on the shipped HUD demo three covers whose floors reach
	nothing at all lost the floor purely because their regions are 21-30px tall, and
	`overflow_sweep`'s "no dead-end compact" guard reported it on five viewports — a
	route the thumb cannot land on is a route on paper.

	ONE SIDE AT A TIME, AND THE ORDER IS DETERMINISTIC rather than optimal: each
	side is grown against the rect as it stands, so an earlier side's growth is
	visible to a later side's test. That is conservative in the right direction (it
	can only grant less, never overlap more) and it is why this needs no fixed
	point. In the fixture that commissioned the rule the two vertical gaps are 9.5px
	against a 10.5px ask, so a cover that used to take 26% of each of two
	neighbouring Buttons now grows 42px of its 44 and takes nothing.

	It is a free function because a rule with a rect, a wish and a list in it
	deserves a table of cases (`tests/hit_floor_region_clamp.spec.luau`). ]]
function commit_walks.growWithin(own: any, want: any, blockers: { any }): any
	local out = { x = own.x, y = own.y, w = own.w, h = own.h }
	local asks = {
		{ side = "top", ask = math.max(0, own.y - want.y) },
		{ side = "bottom", ask = math.max(0, (want.y + want.h) - (own.y + own.h)) },
		{ side = "left", ask = math.max(0, own.x - want.x) },
		{ side = "right", ask = math.max(0, (want.x + want.w) - (own.x + own.w)) },
	}
	for _, entry in asks do
		local granted = entry.ask
		if granted <= 0 then
			continue
		end
		for _, b in blockers do
			if b.w <= 0 or b.h <= 0 then
				continue
			end
			--[[ TWO SKIPS PER SIDE, and the second one is what a first draft got
				wrong. A blocker BESIDE this rect on the other axis is never in its way;
				and a blocker entirely on the FAR side of the edge being moved cannot be
				hit by moving that edge — a rect above the box does not block growth
				DOWNWARD. Without the second test its negative "room" clamped the
				opposite side to zero, which cost every boxed-in-on-one-side cover its
				whole floor. ]]
			local room: number
			if entry.side == "top" or entry.side == "bottom" then
				if b.x >= out.x + out.w or b.x + b.w <= out.x then
					continue
				end
				if entry.side == "top" then
					if b.y >= out.y then
						continue
					end
					room = out.y - (b.y + b.h)
				else
					if b.y + b.h <= out.y + out.h then
						continue
					end
					room = b.y - (out.y + out.h)
				end
			else
				if b.y >= out.y + out.h or b.y + b.h <= out.y then
					continue
				end
				if entry.side == "left" then
					if b.x >= out.x then
						continue
					end
					room = out.x - (b.x + b.w)
				else
					if b.x + b.w <= out.x + out.w then
						continue
					end
					room = b.x - (out.x + out.w)
				end
			end
			granted = math.min(granted, room)
		end
		--[[ ...AND A SIDE THAT WAS GRANTED NOTHING — OR LESS THAN NOTHING, which is
			what a blocker already level with or inside this rect computes — MOVES NOT
			AT ALL. This is the guard that makes the rule one-directional: a floor may
			never shrink a node past what it already paints. ]]
		if granted <= 0 then
			continue
		end
		if entry.side == "top" then
			out.y -= granted
			out.h += granted
		elseif entry.side == "bottom" then
			out.h += granted
		elseif entry.side == "left" then
			out.x -= granted
			out.w += granted
		else
			out.w += granted
		end
	end
	return out
end

--[[ THE CONTRACT, AS A TYPE RATHER THAN A PARAGRAPH. Every field is read-only to
	this module or a by-reference table the renderer declares ONCE and never
	rebinds — which is the whole seam test, because a reassigned local cannot be
	shared by reference at all. `tests/commit_walks_seam.spec.luau` compares this
	declaration against what the module READS and what the renderer PASSES, in
	both directions, over the live sources. ]]
export type CommitCtx = {
	adapter: any, -- the render target
	handles: any, -- path -> adapter handle
	stats: any, -- the renderer's counters
	rectsEqual: any, -- the pure rect comparison
	paintedRectIn: any, -- a solve's rect for a path, as painted
	pathEscapesClip: any, -- is this stroked path outside its clip host
	reculPathClips: any, -- re-cull the paths against the live scroll offsets
	--[[ the eight minimal-write records, one per verdict the walks below send.
		They belong to the renderer because it owns the LIFETIME: its removal sweep
		clears each of them per path, and its parked-props record carries five
		across an instance recycle. ]]
	lastTextSize: any,
	lastTextFont: any,
	lastPadding: any,
	lastCompact: any,
	lastWrapped: any,
	lastVisible: any,
	lastHitRects: any,
	lastScrollRegions: any,
	scrollAutoscroll: any, -- per scroll host: its autoscroll declaration
	pathClipObservers: any, -- per scroll host: the live-offset subscription
	solverHidden: any, -- path -> the solver's hidden verdict this pass
	paintHeld: any, -- path -> the presenter's paint hold
	pathNodes: any, -- the stroked-path node set
	inputSinks: any, -- path -> can this node SINK a press (the overhang lift's census)
	--[[ `originOf(path) -> (ox, oy)`: a path's COORDINATE-SPACE origin (Plan C, C1),
		read off THIS solve's rect map rather than `lastRects` — the caller builds it
		as a closure over the very map it hands these walks, because they run before
		`lastRects` is rewritten and a host that moved on this solve must be composed
		against where it is NOW. One reader: `authorPressableRects`. ]]
	originOf: (string) -> (number, number),
	-- THE RECYCLE-KEY WORN-SET UPDATER (T8 R2, Important 2): the compact ladder
	-- below writes `icon`/`compactLabel` straight to the adapter with style
	-- authority, bypassing `applyStyleProp` because their VALUE is derived
	-- (`layout_node.compactForm`), not simply `node.props[prop]` — so this dep
	-- is the shared updater rather than a second copy of the worn-set code.
	noteWorn: (path: string, prop: string, value: any) -> (),
	--[[ THE FIVE THE PRUNE OWNS (P4). `lastCommitEntry` is the ninth minimal-write
		record and has the same lifetime as the other eight; the three maps below it
		were rebuilt from the whole rect map by the renderer on every solve and are
		now maintained IN PLACE by `harvest`, which is why they cross rather than
		being rebound up there; `authoredHidden` is the renderer's own hide set,
		read-only here, merged with the solver's verdict on the same walk. ]]
	lastCommitEntry: any,
	hiddenRoots: any,
	lastCompositions: any,
	lastTextFacts: any,
	authoredHidden: any,
}

function commit_walks.new(ctx: CommitCtx)
	local adapter = ctx.adapter
	local handles = ctx.handles
	local stats = ctx.stats
	local rectsEqual = ctx.rectsEqual
	local paintedRectIn = ctx.paintedRectIn
	local pathEscapesClip = ctx.pathEscapesClip
	local reculPathClips = ctx.reculPathClips
	local lastTextSize = ctx.lastTextSize
	local lastTextFont = ctx.lastTextFont
	local lastPadding = ctx.lastPadding
	local lastCompact = ctx.lastCompact
	local lastWrapped = ctx.lastWrapped
	local lastVisible = ctx.lastVisible
	local lastHitRects = ctx.lastHitRects
	local lastScrollRegions = ctx.lastScrollRegions
	local scrollAutoscroll = ctx.scrollAutoscroll
	local pathClipObservers = ctx.pathClipObservers
	local solverHidden = ctx.solverHidden
	local paintHeld = ctx.paintHeld
	local pathNodes = ctx.pathNodes
	local inputSinks = ctx.inputSinks
	local originOf = ctx.originOf
	local noteWorn = ctx.noteWorn
	local lastCommitEntry = ctx.lastCommitEntry
	local hiddenRoots = ctx.hiddenRoots
	local lastCompositions = ctx.lastCompositions
	local lastTextFacts = ctx.lastTextFacts
	local authoredHidden = ctx.authoredHidden

	--[[ THE COMMIT'S OWN SKIP (perf campaign P4), and it is the arrange skip's
		mirror rather than a new idea.

		WHAT THE PROFILE FOUND (FacetBench, headless Lune, 2026-09-01, `battle_hud` at
		5 109 nodes, measured after P1/P2/P3). A one-leaf update arranged FIVE nodes and
		then spent **3.99 ms of `Facet/commit`** — 62 % of the whole step — walking the
		live tree seven times to make about four writes: the six walks below at 2.23 ms,
		`rect_pass.apply` at 1.29, and a loop over every entry in the rect map to
		re-harvest the hidden set, the compositions and the text facts. Every one of
		those walks is already minimal-write, so the writes were right; the TRAVERSAL
		was the cost.

		THE PREDICATE, and why it is sound. A subtree may be skipped when BOTH of the
		two things every walk here reads about it are the ones it was last committed
		with:

		  · `nodeDirty` — the ancestor-closed set of paths whose MOUNTED node dirtied
		    this frame, of every dirty class (`renderer.markNodeDirty`). The walks read
		    `node.props`/`node.class`/`node.children`, and a mounted node is mutated IN
		    PLACE (`mount.luau` writes `node.props[name] = newValue`), so node identity
		    says nothing and this set is the only honest signal. `nil` means "no such
		    set" and refuses the prune outright.
		  · `lastCommitEntry[path] == rects[path]` — ENTRY IDENTITY, which P2 made
		    meaningful: a solve given `reuse` hands a skipped subtree's entries forward
		    table for table, and builds a NEW table for every node it walks (even one
		    landing on the rect it already had). So an identical entry is the solver
		    saying "I did not touch this", and a re-walked node compares unequal and is
		    visited — conservative in the only safe direction.

		BOTH ARE ANCESTOR-CLOSED, which is what makes pruning a SUBTREE legal rather
		than only a node: `markNodeDirty` walks up to the root, and `arrange` can only
		reach a child through a parent it did not skip, so a child with a new entry has
		a parent with one. A walk that stops at a clean node therefore stops above
		nothing that changed.

		AND DOCUMENT ORDER SURVIVES IT. The prune is a `return` inside the same
		depth-first walks, so what reaches the adapter is a SUBSEQUENCE of the full
		walk's operations in the same order — which is the property `rect_pass`'s own
		ancestors-first rule depends on, and which `tests/commit_scope.spec.luau`
		asserts against a full-walk arm as an ordered operation log.

		THE TWO WALKS THAT READ ACROSS THE TREE CANNOT PRUNE, and they say so at their
		own sites: `visible`'s stroked-path cull asks a CLIP HOST's box, and
		`hitRects`' framework-chrome floor grows against every author-pressable rect on
		the surface. Both fall back to the full walk on a surface that has the feature
		at all, which is nearly none. ]]
	local pruning = false
	--[[ ...AND WHETHER THIS COMMIT RECORDS WHAT IT COMMITTED, which is a SEPARATE
		question from whether it prunes and the two must not be one flag.

		`pruning` is off for a commit that cannot prove what changed — a structural
		solve, a moved stamp, a re-entrant solve. If such a commit also declined to
		RECORD, the next one would find nothing to compare against and pay full price
		too, so every viewport change, theme swap and list edit would cost two whole
		commits instead of one. Recording on a walk that is already visiting every node
		is one table write per node.

		`recording` is off only when the FEATURE is off, and that is what keeps the
		differential oracle's `commitScope = false` arm an honest pre-P4 build rather
		than a pre-P4 build carrying a store it never reads (P3 review, I2: a control
		arm dearer than the thing it is the control for inflates every ratio taken
		against it). ]]
	local recording = false
	local nodeDirty: any = nil
	--[[ ...AND THE COMMIT'S OWN HALF OF THAT SET (wicked-fast T5b): the same
		ancestor-closed closure MINUS the seven props that move a node and change
		nothing any walk here reads (`renderer.PURE_ARRANGE_PROPS`). Only the walks
		that claim `arrangeBlind` are answered against it; `nil` (a commit handed no
		second set) falls the whole way back to `nodeDirty`, so every walk keeps the
		set it had before this existed. ]]
	local commitDirty: any = nil
	local commitRects: any = nil
	--[[ THE SIBLING SCAN, COUNTED AND THEN SPENT ONCE (Plan C, C4).

		`scanCount` is every question the commit asked about a child — the honest cost
		of the prune, which the visit counter cannot see: P4 already took the VISITS
		to the dirty chain, and what is left is `skip(child)` asked of all 1,000
		siblings under a list node, once per walk, eight times over, to be told
		"skip" 8,000 times. `descendKids` and its two twins are the answers, cached
		per node for the whole commit, so the eight walks share ONE classification of
		each child instead of taking eight. Measured on `deep_stack_scene`, one
		leaf's text: 8,032 questions -> 1,011.

		IT IS `skip` ITSELF, ASKED ONCE, NOT AN APPROXIMATION OF IT. `buildDescend`
		shares `entryVerdict` — the half of `skip` that costs anything — across the
		three shapes `skip` is called in here, and each walk reads the list for its
		OWN shape. So no walk's prune changes: every node any walk descends is a node
		`skip` answered "descend" for, with the same flags, on the same state.

		AND IT CANNOT GO STALE THE UNSAFE WAY. The one input that moves during a
		commit is `lastCommitEntry`, written by `rect_pass`'s `note`/`noteEntry`, and
		that write can only turn `skip` from false to TRUE (it sets `last = probe`) —
		`note` sets it to exactly the entry `probeEntry` will keep returning. So a
		list built by an earlier walk is at worst a SUPERSET of what a later walk
		would compute, which is the conservative direction: an extra descent, never a
		missed one. Measured, and this is the load-bearing pin: `lastCommitVisits`,
		`lastCommitVisitsByWalk`, `rectWrites`, `propWrites` and `engineWrites` are
		IDENTICAL before and after, on every drive of every fixture.

		WHAT IT COSTS WHERE IT CANNOT HELP, stated because it took three measured
		rounds to get to nearly zero. A commit that prunes almost nothing — a reorder,
		a big structural add — cannot be helped by any of this and can only be charged
		for it. The first shape charged **+3.0 %** on `war_room_inventory reorder`, and
		the three things that were it are each fixed and each commented at their own
		site below: the lost DIRTY SHORT-CIRCUIT (`skip` answers a dirty node without
		probing its entry; the sift did not), the WORST-CASE PREALLOCATION (three
		`table.create(n - 1)` per visited node), and THREE HASH WRITES per visited node
		where one will do. Measured against `e74b17fd`, medians of three:
		`reorder` **+0.7 %** (29.66 -> 29.86 ms), `removeItem-items` **-0.7 %**,
		`killfeed_nameplates addItem-feed` **+0.1 %**, `removeItem-feed` **-3.3 %** —
		every class in the three workloads now at or better than the base except
		`reorder`, and that one inside the runs' own overlap.

		WHAT IT IS NOT: a DIRTY-CHILD index. The plan proposed descending only the
		children the dirty scan marked, and that is unsound — the entry-identity half
		of `skip` is closed UPWARD only, so a dirty parent's CLEAN child gets a new
		entry whenever the solve re-arranged it. Driven: a `fill`-width child of a row
		whose `width` signal moves is in NO dirty set and its rect goes 300 -> 220
		(`tests/commit_descend_cache.spec.luau`, "A CLEAN CHILD OF A DIRTY PARENT").
		That child would have kept painting 300 px behind a green suite. ]]
	local scanCount = 0
	--[[ ...and the QUESTIONS THAT STILL COST A CALL, which is a different number and
		is C14's (Plan C). `scanCount` counts loop ITERATIONS; `probeCount` counts the
		`entryVerdict` calls left inside them once `buildDescend` answers the common
		case from the two entry maps directly. The two are published side by side
		deliberately: C14 removes probes and must remove NO iterations, because the
		fork arithmetic beside it copies a prefix of `kids` BY INDEX. `scanCount`
		unmoved against a fallen `probeCount` is how a reader knows that held.
		Measured on `deep_stack_scene`, one leaf's text: 1,011 scans either way, and
		1,011 probes -> 1. ]]
	local probeCount = 0
	-- ...and the array slots those answers were stored in (fix round 1); see
	-- `render_stats.lastCommitListCells`. Incremented at the THREE fork sites only,
	-- which run a handful of times a commit rather than once a child.
	local listCells = 0
	-- one per `skip` shape (see `buildDescend`); all three filled by one pass
	local descendKids: { [string]: { any } } = {}
	local descendMoveKids: { [string]: { any } } = {}
	local descendCommitKids: { [string]: { any } } = {}
	-- axis 3, the solve-wide inputs every walk reads and no node dirties: the paint
	-- scale, the theme snapshot (compared by IDENTITY — one env-held table per theme)
	-- and the preferred-text offset. A move here rewrites every node, so it refuses
	-- the prune for one commit and the walk that follows re-notes the whole tree.
	local stampScale: any = nil
	local stampMetrics: any = nil
	local stampOffset: any = nil
	-- the paths whose HIDDEN verdict flipped this commit. A flip is inherited, so
	-- `visible`/`hitRects` descend through a clean subtree under one of these.
	local hiddenFlips: { [string]: boolean } = {}
	-- has this surface ever shown a framework-chrome expander (`cover`/`close`)?
	-- Latched, and cleared only by a full commit, because the floor those nodes ask
	-- for is a function of OTHER nodes' rects.
	local sawChrome = false

	-- P4's visit counter, per walk (wicked-fast T2). `lastCommitVisits` keeps its
	-- meaning — it is the SUM — but a single number cannot say which walk stopped
	-- at a moved subtree and which had to descend it, and that is the whole
	-- question T5 asks. The per-node cost went DOWN: a local increment instead of
	-- a table-field one, published once per walk.
	local function publishVisits(name: string, n: number)
		stats.lastCommitVisits += n
		local byWalk = stats.lastCommitVisitsByWalk
		if byWalk ~= nil then
			byWalk[name] = (byWalk[name] or 0) + n
		end
		-- ...and the QUESTIONS, not the answers (C4). One local increment in `skip`
		-- and one field write per walk, for the same reason the visit counter is
		-- shaped that way. It is a running total rather than a per-walk split
		-- because the cache below makes the split meaningless: the FIRST walk to
		-- reach a node pays its whole sibling scan and the other seven pay none of
		-- it, so a per-walk number would read as an imbalance rather than as a cut.
		stats.lastCommitScans = scanCount
		stats.lastCommitProbes = probeCount
		stats.lastCommitListCells = listCells
	end

	--[[ THE ENTRY THIS NODE ANSWERS FOR, WHICH IS NOT ALWAYS ITS OWN, and this is the
		correction the first implementation of the prune needed rather than a
		refinement of it.

		THESE WALKS RUN OVER THE MOUNTED TREE AND THE ENTRIES COME FROM THE LAYOUT
		TREE, and the two are not the same shape: `UI.ForEach`, `UI.When` and
		`UI.ErrorBoundary` own MOUNTING, not layout, so `layout_node.build` splices
		their children into the enclosing flow and emits no node for the region — and
		neither for a `ForEach`'s per-item wrapper. Those paths have NO rect entry,
		ever. A predicate that compared `rects[path]` directly therefore read `nil ==
		nil` on every one of them and pruned the whole subtree: measured, the
		`rect_cow` oracle's offer-change step left all 200 rows painting their old
		width, because the walk stopped at the `ForEach` region above them.

		SO AN ENTRY-LESS NODE BORROWS THE ONE BELOW IT, and only down a chain it
		wholly contains: a single-child wrapper is answered by its child, recursively,
		and a node with two or more children answers `nil` and is never pruned. That
		is exactly the `ForEach` shape — the region has N children and is walked, each
		item wrapper has ONE and is answered by its row — so the sibling scan under a
		dirty list costs one comparison per row instead of one walk per row, and the
		region itself is one visit that writes nothing (it has no handle).

		WHY BORROWING IS SOUND. `nodeDirty` is closed over mounted-path PREFIXES, so a
		dirty node anywhere below marks every wrapper above it; and `arrange` can only
		reach a node through a parent it did not skip, so a changed entry below the
		borrowed one implies the borrowed one changed too. Both properties are about
		the subtree, which is what makes the borrowed answer answer for all of it. ]]
	local function probeEntry(node: any): any
		local entry = commitRects[node.path]
		if entry ~= nil then
			return entry
		end
		local kids = node.children
		if #kids == 1 then
			return probeEntry(kids[1])
		end
		return nil
	end

	--[[ `moveBlind` (wicked-fast O4) says THIS WALK'S OUTPUT CANNOT READ A POSITION,
		so "the only thing that happened here is a move" is as good as "nothing
		happened". Six of the eight walks are in that class by inspection — `harvest`
		(hidden/composition/textFacts), `textScale` (textFacts.size), `padding`
		(class + `props.padding`), `textVerdicts` (compact + wrap verdicts),
		`scrollRegions` (`contentSize`, `rect.w`/`rect.h`) and `visible` behind its
		existing whole-surface `prunable` latch. `hitRects` is NOT: it centres a
		target-floor expander on `r.x`/`r.y`.

		IT IS STILL THE TABLE-IDENTITY TEST, one link further back. The solver's
		translate arm clones the entry it re-bases and leaves `prev` pointing at the
		table it superseded (`layout/solver.luau`, `translateDescendants`), breaking
		the chain at depth 1 as it goes — so `last == probe.prev` means "the entry I
		last committed is exactly the one this move started from", which is a
		statement about identity and not about what changed.

		`moveOnly` IS STICKY, WHICH IS WHY `last ~= nil` IS LOAD-BEARING. An entry
		that translated on tick N and merely skipped on N+1 is the same table and
		still says `moveOnly = true` — but its `prev` was cleared as the chain broke,
		so `probe.prev` is nil, and a node this commit span has never NOTED (no
		handle, P5) has `last` nil too. Without the guard `nil == nil` would prune a
		node nothing was ever committed for, forever.

		`arrangeBlind` (wicked-fast T5b) IS A SECOND, STRICTLY STRONGER CLAIM, and it
		is a separate parameter rather than the same one because the two answer
		different questions. `moveBlind` decides whether a MOVE is as good as nothing
		— which is about the ENTRY. `arrangeBlind` decides WHICH DIRTY SET the node is
		looked up in — which is about the PROPS a walk reads. Four walks make both
		claims (`textScale`, `padding`, `textVerdicts`, `scrollRegions`: none of them
		names an arrange-class prop, mechanised in `tests/commit_dirt_classes.spec`).
		`harvest` and `visible` make only the first: their output cannot read a
		position either, but they DO read `hidden`, which is arrange-classed, and
		`visible`/`hitRects` additionally depend on reaching every node `harvest`
		reached (see `harvest`'s two-small-loops note), which is only true while the
		three of them share one set.

		FUSING THE TWO WOULD HAVE COST T5 ENTIRELY, and that is measured rather than
		argued: taking `moveBlind` away from `harvest` at `a9607e17` takes it from 253
		visits to 1503 on the nameplates fixture, because what `moveBlind` prunes is a
		translated subtree's CLONES, and a clone is in NEITHER dirty set. ]]
	--[[ THE HALF OF THE PRUNE THAT IS ABOUT THE ENTRY, AND NOTHING ELSE — lifted out
		of `skip` so that `skip` and the descend sift below cannot drift (C4). It is
		the expensive half: `probeEntry` walks a chain of entry-less wrappers, and the
		two table reads under it are what the commit pays per sibling.

		`settled` = "the entry I last committed is the one this solve carried
		forward" (table identity, P2/P4). `moved` = "...or the one this solve's
		TRANSLATE ARM re-based it from" (T5's `moveBlind`, T4's `prev` chain), which
		is a stronger statement than `settled` and is only good enough for a walk
		whose output cannot read a position. Neither reads a dirty set: which SET a
		caller is answered against is the caller's question, not the entry's. ]]
	local function entryVerdict(node: any): (boolean, boolean)
		local probe = probeEntry(node)
		if probe == nil then
			return false, false
		end
		local last = lastCommitEntry[node.path]
		if last == probe then
			return true, true
		end
		return false, probe.moveOnly == true and last ~= nil and last == probe.prev
	end
	local function skip(node: any, moveBlind: boolean?, arrangeBlind: boolean?): boolean
		scanCount += 1
		if not pruning then
			return false
		end
		-- THE SET DEPENDS ON THE QUESTION (T5b). A walk that told us its output cannot
		-- read a POSITION may still read `hidden`, which is arrange-classed; a walk
		-- that told us it reads no arrange-class prop AT ALL is answered against the
		-- commit-side set instead. Every other walk — and every walk at all on a
		-- commit that was handed no second set — keeps the all-classes one.
		local set = if arrangeBlind == true and commitDirty ~= nil then commitDirty else nodeDirty
		if set[node.path] == true then
			return false
		end
		local settled, moved = entryVerdict(node)
		return settled or (moveBlind == true and moved)
	end
	--[[ THE CHILDREN WORTH DESCENDING, CLASSIFIED ONCE PER COMMIT (C4). See
		`descendKids` above for why this replaces the sibling scan and not the prune.

		THREE LISTS, ONE PASS, because `skip` has three shapes in this file and they
		are NESTED: `skip(n)` (base — `hitRects` and `rect_pass`), `skip(n, true)`
		(`harvest`, `visible`) and `skip(n, true, true)` (the four arrange-blind
		walks). `commitDirty` is a subset of `nodeDirty` and `moved` only widens
		`settled`, so base-skippable implies move-skippable implies commit-skippable —
		i.e. the three DESCEND lists nest the other way, commit ⊆ move ⊆ base. All
		three come out of one walk over the children sharing ONE `entryVerdict`, which
		is where the cost is.

		AND THE CALLER DOES NOT RE-ASK. Each walk iterates the list for its OWN shape,
		so a member is one `skip` would have answered "descend" and its per-node guard
		is redundant — the walks pass `chosen` to say so, and keep the guard for the
		ROOT, which no parent selected. THAT is the difference between this and a
		single shared list: with one base list every walk still had to ask its own
		question of every member, and on a STRUCTURAL commit — where almost nothing
		prunes and the list is the child list — that is a whole extra pass. Measured
		before it was fixed: `war_room_inventory reorder` +4.7 %,
		`killfeed_nameplates addItem-feed` +4.2 %.

		THE LIST IS `node.children` ITSELF UNTIL A CHILD IS ACTUALLY PRUNED, for the
		same reason and measured in the same run: a commit that descends everything
		would otherwise allocate a full copy of the tree, one table per visited node,
		read once and dropped. The prefix is copied on the FIRST pruned child and not
		before, so the common structural case allocates nothing at all.

		THE THREE SIFTS ARE WRITTEN OUT rather than factored behind a helper. A helper
		would take either a per-build record (three allocations per visited node,
		which is the cost this whole paragraph exists to avoid) or a table of state
		(three table writes per child in place of three local ones) — on the loop the
		commit span is made of. ]]
	local function buildDescend(node: any)
		local kids = node.children
		local path = node.path
		--[[ THE COMMIT-SIDE SIFT IS NOT ALWAYS ASKED FOR (review Minor 5). `descendOf`
			can only ever hand back `descendCommitKids` through its
			`arrangeBlind == true and commitDirty ~= nil` arm, so on a commit handed no
			second set that list is unreachable — and computing it was a table lookup
			and, on the old shape, a whole third array per visited node, for nobody. ]]
		local wantCommit = commitDirty ~= nil
		--[[ THE THREE LISTS ARE ALIASED UNTIL A CHILD'S VERDICTS DISAGREE, and that is
			the whole allocation story (review Important 2).

			`nil` means "identical to `kids` so far"; two of them holding the SAME table
			means "identical to each other so far". A list is materialised only when it
			first has to differ from the one above it — the first child it excludes, or
			the first child on which its own predicate parts company with its
			neighbour's. On a surface with no `moveOnly` entries and no arrange-class-only
			dirt the three predicates never part company, so ONE array serves all three.

			MEASURED, on `deep_stack_scene` at 1,000 rows, one leaf's text: the eager
			shape built 5 arrays totalling 2,999 SLOTS per commit — three of them
			`table.create(999)` at the list node, for lists that end up holding one
			element each — where HEAD allocated none. That is ~48 KB a commit on a step
			whose whole allocation is 703 KB.

			AND THE FORK IS SIZED TO WHAT IT COPIES, not to the worst case: `table.create`
			at the prefix length, with the appends after it growing geometrically. The old
			`table.create(n - 1)` was the tight bound only for a list that prunes its FIRST
			child and keeps every other one, which is the opposite of the case this
			mechanism exists for. ]]
		local lb: { any }? = nil
		local lm: { any }? = nil
		local lc: { any }? = nil
		local nb, nm, nc = 0, 0, 0
		for i, child in kids do
			scanCount += 1
			local p = child.path
			local dirtyAll = nodeDirty[p] == true
			local dirtyCommit = if wantCommit then (commitDirty :: any)[p] == true else dirtyAll
			--[[ `skip`'s three shapes, written out against `skip`'s own inputs. They NEST
				as SKIP sets (base => move => commit), so the descend lists nest the other
				way — which is what makes the aliasing below sound.

				AND THE DIRTY TEST COMES FIRST, EXACTLY AS `skip` ORDERS IT (fix round 1).
				`skip` returns at `set[node.path] == true` WITHOUT probing the entry, and a
				node in every dirty set is descended by every shape whatever its entry
				says — so the probe is not just unnecessary there, it is the expensive
				thing. Losing that short-circuit is what the reorder regression actually
				was: a reorder dirties nearly every node, so the first version paid a
				`probeEntry` for each of ~7,300 children that `skip` had answered with one
				hash lookup. MEASURED across four arms: the allocation fix alone took
				`gcKb` from 10,733 back to 10,490 (baseline 10,416) and moved the class
				not at all (30.401 -> 30.630 ms), which is what said the arrays were never
				the cost. ]]
			--[[ THE COMMON ANSWER, WITHOUT THE CALL THAT COMPUTES IT (Plan C, C14).

				`entryVerdict` is `probeEntry` plus a `lastCommitEntry` lookup plus a
				compare, and `probeEntry`'s FIRST LINE is `commitRects[node.path]`. So for
				a child that owns its own entry — which is nearly every child of nearly
				every visited node — the whole verdict is TWO HASH LOOKUPS AND AN `==`,
				wrapped in two closure calls. This branch does the two lookups here and
				keeps the calls for the children that actually need them: an entry-LESS
				one (a spliced `UI.When`/`UI.ForEach`/`UI.ErrorBoundary` region or a
				single-child pass-through, where `probeEntry` walks a chain), and one whose
				entry this solve REPLACED, where `moved` still has to be computed.

				IT IS `entryVerdict` ITSELF, NOT AN APPROXIMATION OF IT, and that is the
				whole safety argument — the same one C4 makes one level up. `settled` IS
				`lastCommitEntry[p] == probeEntry(child)`, and for `own ~= nil` that is
				exactly `lastCommitEntry[p] == own`; `settled` short-circuits `moved` in
				every consumer below, so the three flags are the same three. No verdict
				can differ, which is why `lastCommitScans`, `lastCommitVisits`,
				`lastCommitVisitsByWalk`, `rectWrites`, `propWrites` and `engineWrites` are
				identical on every drive of every fixture.

				WHAT THE PLAN ASKED FOR INSTEAD, AND WHY IT IS NOT HERE. C14 was written
				as a set-membership filter: publish the ids the solve WALKED and skip the
				probe for a child outside the set. Built and measured against this branch
				at `48f010cd` (`attr battle_hud L 3`), it produced **the identical probe
				count on every class** — because a child a walked-set filter may prune must
				also own an entry (a spliced region owns none, and pruning one takes its
				whole subtree with it) and must also have been COMMITTED before (an entry
				the last commit had no handle for is deliberately left unnoted so the next
				one descends). Both terms are hash lookups on the entry maps, so the
				membership test is a THIRD lookup deciding nothing the first two had not:
				`cw.harvest` 0.098 -> 0.078 ms with it against **0.074 ms without**, and
				+11 % / +14 % against HEAD on the two structural classes it cannot help.
				`render/commit_walks` needs no fact from the solve to answer this.

				AND IT DOES NOT `continue`. The fork points below copy a PREFIX of `kids`
				BY INDEX (`i - 1`), so skipping the rest of the body would let the first
				fork after a filtered child copy that child back into the list. The flags
				are set directly and every child still reaches the fork logic with the same
				`i`. `scanCount` therefore does not move; `probeCount` — the calls this
				branch did NOT answer — is this task's number, and the two are pinned
				together for exactly that reason. ]]
			local skipB, skipM, skipC
			local own = commitRects[p]
			if dirtyAll and dirtyCommit then
				skipB, skipM, skipC = false, false, false
			elseif own ~= nil and lastCommitEntry[p] == own then
				-- `settled`, computed rather than guessed: the entry this solve carried
				-- forward IS the one the last commit wrote
				skipB = not dirtyAll
				skipM = not dirtyAll
				skipC = not dirtyCommit
			else
				probeCount += 1
				local settled, moved = entryVerdict(child)
				skipB = not dirtyAll and settled
				skipM = not dirtyAll and (settled or moved)
				skipC = not dirtyCommit and (settled or moved)
			end
			--[[ ...and the two places a list has to leave the one above it. They are
				MUTUALLY EXCLUSIVE at any one child: `skipM ~= skipB` needs `skipM` true
				(base keeps, move drops) and `skipC ~= skipM` needs `skipM` false. ]]
			if skipM ~= skipB and lm == lb then
				local src: { any } = if lb ~= nil then lb else kids
				local len = if lb ~= nil then nb else i - 1
				listCells += len + 1
				local forked = table.create(len)
				table.move(src, 1, len, 1, forked)
				-- commit was following move, so it leaves base with it
				if lc == lm then
					lc = forked
					nc = len
				end
				lm = forked
				nm = len
			end
			if skipC ~= skipM and lc == lm then
				local src: { any } = if lm ~= nil then lm else kids
				local len = if lm ~= nil then nm else i - 1
				listCells += len + 1
				local forked = table.create(len)
				table.move(src, 1, len, 1, forked)
				lc = forked
				nc = len
			end
			if skipB then
				-- base drops it, and so do the other two (base => move => commit), so any
				-- list still aliasing `kids` forks HERE and they keep sharing one array
				if lb == nil then
					listCells += i
					local forked = table.create(i - 1)
					table.move(kids, 1, i - 1, 1, forked)
					if lm == nil then
						lm = forked
						nm = i - 1
					end
					if lc == nil then
						lc = forked
						nc = i - 1
					end
					lb = forked
					nb = i - 1
				end
			else
				-- ...and a child a list KEEPS is appended once per DISTINCT array; an
				-- aliased list was already served by the one it shares a table with
				if lb ~= nil then
					nb += 1
					lb[nb] = child
				end
				if not skipM and lm ~= nil and lm ~= lb then
					nm += 1
					lm[nm] = child
				end
				if not skipC and lc ~= nil and lc ~= lm and lc ~= lb then
					nc += 1
					lc[nc] = child
				end
			end
		end
		--[[ ...AND ONLY A LIST THAT DIVERGED IS STORED (fix round 1, and it is the
			half of the reorder regression the allocation was NOT). Three hash inserts
			per visited node, into three tables that grow to the visited-node count and
			are `table.clear`ed every commit, is a real bill on a commit that visits
			everything: measured on `war_room_inventory reorder`, writing all three
			costs +2.8 % against `e74b17fd` and writing only the base costs +0.7 %,
			with `removeItem-items` going +3.0 % -> -0.7 % and the update classes
			unmoved (`battle_hud updateItem-hp` -20.7 % -> -20.9 %). `descendKids` is
			also the BUILT MARKER, so it is written unconditionally; the other two are
			written only where their predicate actually parted company, which on a
			stack-shaped surface is never, and `descendOf` falls back down the chain. ]]
		descendKids[path] = lb or kids
		if lm ~= lb then
			descendMoveKids[path] = lm or kids
		end
		if wantCommit and lc ~= lm then
			descendCommitKids[path] = lc or kids
		end
	end
	--[[ ...and the read side, which takes the SAME two claims `skip` takes so a walk
		names its shape in one place. An unarmed commit gets `node.children` back
		untouched and caches nothing: `skip` answers false for everything there, so
		every list would be the child list, and the `commitScope = false` arm is the
		differential oracle's pre-P4 control — a control that allocates what the fast
		path does not is not the control. ]]
	local function descendOf(node: any, moveBlind: boolean?, arrangeBlind: boolean?): { any }
		if not pruning then
			return node.children
		end
		local path = node.path
		-- the base list doubles as the BUILT marker, so one lookup answers both "is
		-- this node classified" and "what does the flagless shape descend"
		local base = descendKids[path]
		if base == nil then
			buildDescend(node)
			base = descendKids[path] :: { any }
		end
		--[[ ...and a shape that never diverged reads the one above it. The fallback
			chain is commit -> move -> base, which is the same nesting `buildDescend`
			builds along, so a miss is "identical to my neighbour" and never "not
			computed". `arrangeBlind` with no `commitDirty` falls to the move list
			exactly as `skip` falls back to `nodeDirty`. ]]
		if arrangeBlind == true and commitDirty ~= nil then
			local c = descendCommitKids[path]
			if c ~= nil then
				return c
			end
			local m = descendMoveKids[path]
			return if m ~= nil then m else base
		elseif moveBlind == true then
			local m = descendMoveKids[path]
			return if m ~= nil then m else base
		end
		return base
	end
	-- WRITTEN AT THE END OF THE COMMIT AND NOWHERE ELSE, so all seven walks compare
	-- against the same "last committed" state. `rect_pass` is the last walk and is
	-- the one that calls this; on an unarmed commit it is never called at all, which
	-- is what keeps the differential oracle's off arm an honest pre-P4 build (P3
	-- review, I2: a control that writes a store the fix reads is not the control).
	local function note(node: any)
		lastCommitEntry[node.path] = probeEntry(node)
	end
	-- ...and the same write for a path the last walk APPLIED WITHOUT VISITING as a
	-- node (wicked-fast N1): `rect_pass` emits a translated subtree straight from
	-- the solver's flat run, so it holds the path and the entry but no node to probe
	-- from. Without it the next commit compares against a two-ticks-old table and
	-- descends everything — the whole prune, silently undone one tick later.
	local function noteEntry(path: string, entry: any)
		lastCommitEntry[path] = entry
	end
	local function armed(): boolean
		return pruning
	end
	local function records(): boolean
		return recording
	end

	--[[ THE SEVENTH WALK, AND THE ONE THAT ARMS THE OTHER SIX (P4).

		It replaces `renderer.solveAndApply`'s own loop over the WHOLE rect map — the
		one that rebuilt `nextHidden`, `nextCompositions` and `nextTextFacts` from
		scratch on every solve and then compared the hidden set to decide whether the
		focus map's epoch had to move. Same three answers, same merge of the AUTHORED
		hides into the solver's own verdict, and the same "a hide is a focus-map
		change" bump; what changed is that the three maps now live across solves and
		only the paths this commit can reach are re-derived.

		TWO ARMS, and the full one is EXACTLY the loop it replaces. A commit that
		cannot prove what changed — no reuse solve, no dirty set, a moved scale/theme/
		offset, or the `commitScope` opt off — clears all three and rebuilds them from
		the map, which is also what makes a structural change self-cleaning: paths that
		left the tree leave the maps with it.

		THE EPOCH BUMP IS THE SET COMPARISON IT ALWAYS WAS. On the full arm the new set
		is built beside the old one and diffed both ways; on the pruned arm every
		membership change passes through the flip below, so the two arms answer the
		same question from different directions. Bumping unconditionally would defeat
		the epoch entirely — this runs on every solve. ]]
	local function harvest(
		rootNode: any,
		rects: any,
		enabled: boolean,
		dirty: { [string]: boolean }?,
		scale: number,
		metrics: any,
		prefOffset: number,
		-- the commit-side half of `dirty` (T5b). Optional: absent means every walk is
		-- answered against `dirty`, which is what this file did before T5b.
		commitDirtySet: { [string]: boolean }?
	): boolean
		local stampSame = stampScale == scale and stampMetrics == metrics and stampOffset == prefOffset
		stampScale, stampMetrics, stampOffset = scale, metrics, prefOffset
		nodeDirty = dirty
		commitDirty = commitDirtySet
		commitRects = rects
		recording = enabled
		pruning = enabled and dirty ~= nil and stampSame
		table.clear(hiddenFlips)
		-- ...and the descend lists, which are a function of THIS commit's dirty sets
		-- and THIS commit's entries and are therefore worth nothing to the next one
		-- (C4). Cleared here rather than at the end of the span for the reason
		-- `hiddenFlips` is: this is the one call every commit makes first.
		listCells = 0
		table.clear(descendKids)
		table.clear(descendMoveKids)
		table.clear(descendCommitKids)
		scanCount = 0
		probeCount = 0
		local changed = false
		if not pruning then
			sawChrome = false
			local next_: { [string]: boolean } = {}
			table.clear(lastCompositions)
			table.clear(lastTextFacts)
			for path in authoredHidden do
				next_[path] = true
			end
			for path, entry in rects do
				if entry.hidden == true then
					next_[path] = true
				end
				if entry.composition ~= nil then
					lastCompositions[path] = entry.composition
				end
				if entry.textFacts ~= nil then
					lastTextFacts[path] = entry.textFacts
				end
			end
			for path in next_ do
				if hiddenRoots[path] == nil then
					changed = true
					break
				end
			end
			if not changed then
				for path in hiddenRoots do
					if next_[path] == nil then
						changed = true
						break
					end
				end
			end
			table.clear(hiddenRoots)
			for path in next_ do
				hiddenRoots[path] = true
			end
			return changed
		end
		local visits = 0
		-- `chosen` = MY PARENT ALREADY ASKED (C4): this node came out of
		-- `descendOf(parent, true)`, which is the same question this guard asks, so
		-- asking it again is a second sibling scan. The ROOT has no parent and is
		-- guarded at the call below.
		local function walk(node: any, chosen: boolean)
			if not chosen and skip(node, true) then
				return
			end
			visits += 1
			local path = node.path
			local entry = rects[path]
			local want = authoredHidden[path] == true or (entry ~= nil and entry.hidden == true)
			if want ~= (hiddenRoots[path] == true) then
				hiddenRoots[path] = if want then true else nil
				hiddenFlips[path] = true
				changed = true
			end
			lastCompositions[path] = if entry ~= nil then entry.composition else nil
			lastTextFacts[path] = if entry ~= nil then entry.textFacts else nil
			for _, child in descendOf(node, true) do
				walk(child, true)
			end
		end
		walk(rootNode, false)
		publishVisits("harvest", visits)
		--[[ THE TWO SMALL LOOPS, AND THEY ARE BELT-AND-BRACES RATHER THAN LOAD-BEARING
			— which is stated here because a guard nobody can redden is a guard whose
			reason has to be written down instead of assumed.

			Both sets are recomputed above for every path the walk VISITED, and a hidden
			verdict can only move in two ways, each of which forces a visit: the authored
			half changes through `props.hidden` (arrange class, so `markNodeDirty` marks
			the path and `skip` refuses it) and the solver half changes through the
			entry, which is the identity the prune compares. Mutation-tested 2026-09-01:
			deleting either loop reddens NOTHING in this repository's suite.

			THEY STAY because the argument's first half lives in ANOTHER file — it is a
			property of how `renderer.refresh` routes the `hidden` prop, not of anything
			here — and because both are zero-length on every surface that authors no
			hide and one or two entries on the ones that do. The removal side is
			collected into a list first: assigning nil during a generalized iteration is
			what Luau leaves undefined.

			AND THE REPAIR IS WHOLE, WHICH IT WAS NOT WHEN THIS COMMENT FIRST SHIPPED
			(P4 review, folded minor 1). A flip recorded here updates `hiddenRoots` —
			the set `controller.hiddenRoots()` publishes and the focus map filters on —
			but `visible` and `hitRects` see `hiddenFlips` only if their own walks REACH
			the node, and they may be pruned at an ancestor before they do. A half
			repair that moves focus and leaves paint is worse than no repair, because
			the two then disagree with nobody able to see it. `markFlip` therefore
			marks the mounted-path PREFIXES too, so the walk descends to the node. That
			forces the whole tree for one commit, which is the conservative direction
			and costs nothing at all while these loops keep never firing. The VISITED
			branch above needs none of it: `visible` and `hitRects` share this `skip`
			and only ever add reasons NOT to prune, so a node the harvest reached is a
			node they reach. ]]
		local function markFlip(path: string)
			hiddenFlips[path] = true
			local at: string? = string.match(path, "^(.*)/[^/]*$")
			while at ~= nil and at ~= "" and hiddenFlips[at] ~= true do
				hiddenFlips[at] = true
				at = string.match(at, "^(.*)/[^/]*$")
			end
		end
		for path in authoredHidden do
			if hiddenRoots[path] == nil then
				hiddenRoots[path] = true
				markFlip(path)
				changed = true
			end
		end
		local stale: { string } = {}
		for path in hiddenRoots do
			local entry = rects[path]
			if authoredHidden[path] ~= true and not (entry ~= nil and entry.hidden == true) then
				table.insert(stale, path)
			end
		end
		for _, path in stale do
			hiddenRoots[path] = nil
			markFlip(path)
			changed = true
		end
		return changed
	end

	-- paint seam for scaled text (input-paradigms expansion, matrix D.1): write
	-- props.textSize * typographyScale, tracking the last value per path so a
	-- steady scale is a no-op (minimal-write contract) but a displaySize flip
	-- rewrites every scaled size. Runs inside solveAndApply so paint and the
	-- re-solved layout always agree.
	--
	-- ...and the INTRINSIC size paints too (director fix round 2026-07-25). It
	-- used not to: an absent `textSize` left the adapter's hardcoded TextSize 16,
	-- while the measure seam above reserved the class's typography ROLE from the
	-- snapshot. A package that moved that role — compact-pointer draws its control
	-- text at 13 — was therefore reserved for at one size and drawn at another,
	-- and a single-line button label wrapped ("Pla"/"y") inside a box the solver
	-- had sized correctly for the size it measured. Same argument as `padding`
	-- below, same seam, same guarantee: written inside the solve, against THAT
	-- solve's metrics, so the size the engine draws with and the size the solver
	-- reserved can never disagree.
	--
	-- `textScale` multiplies AUTHORED sizes only, exactly as the measure seam does
	-- (an intrinsic default is not scaled there either), and the preferred-text
	-- offset stays out of paint because the engine applies its own at draw time.
	-- THE FACE, beside the size, from the SAME role (F2, 2026-08-02). The
	-- typography role has always carried a font descriptor and the MEASURE seam
	-- has always keyed `text_metrics` on it (`toLayoutNode` -> `layoutNode.font`);
	-- paint did not, so every text node was drawn in whatever face the adapter
	-- hardcoded at creation. That is `Text.font`'s deprecation read backwards —
	-- there, the author's face reached measurement and never paint; here, the
	-- THEME's face reached measurement and never paint — and it is why a weight
	-- channel had to be a role rather than a prop.
	--
	-- Both seams resolve through `themeSnapshot.effectiveTypeRole`, so the
	-- descriptor the solver measured with IS the descriptor the engine draws with.
	-- Written inside the solve, against THAT solve's metrics, exactly as the size
	-- and the Button padding beside it are. Minimal-write: the descriptor key is
	-- cached per path, so a steady theme costs zero writes and every screen whose
	-- roles all resolve to the family's Regular face is byte-identical.
	--[[ `rects` AND `prefOffset` ARE HERE FOR ONE NODE SHAPE: `textSize = "fit"`
		(audit §10). Every other size on this walk is derived from the PROP, which
		is why the walk could be prop-only for four stages; a fit node has no
		authored size at all — the SOLVER chose one, against the box, and the whole
		point of the prop is that the two seams cannot then disagree about it. So
		paint reads the solve's own answer rather than re-deriving a number the
		solver has already rejected.

		The recovery is an identity rather than a new channel: `textFacts.size` is
		the size the measure used, which for EVERY text node is what the engine will
		draw — the authored size plus the additive offset the engine adds itself —
		so the size to WRITE is that minus the same offset. ]]
	local function textScale(rootNode: any, scale: number, metrics: any, rects: any?, prefOffset: number?)
		local offset = if type(prefOffset) == "number" then prefOffset else 0
		local visits = 0
		-- `chosen`: see `harvest`'s walk (C4)
		local function walk(node: any, chosen: boolean)
			if not chosen and skip(node, true, true) then
				return
			end
			visits += 1
			-- an AUTHORED size paints; a role name is just as authored as a number
			-- (it resolves through the same snapshot the measure seam used), while
			-- an absent prop falls back to the class's own typography role
			local authored = node.props and node.props.textSize
			local fitProp = textFit.fitSpecOf(authored)
			local raw = if fitProp ~= nil then nil else themeSnapshot.resolveSize(metrics, authored)
			local fitted: number? = nil
			if fitProp ~= nil then
				-- a node the solve did not reach keeps whatever it has, exactly as the
				-- wrap verdict does: absent facts are not a verdict
				local entry = if type(rects) == "table" then (rects :: any)[node.path] else nil
				local facts = if type(entry) == "table" then entry.textFacts else nil
				if type(facts) == "table" and type(facts.size) == "number" then
					fitted = facts.size - offset
				end
			elseif raw == nil and not (node.class == "Button" and #node.children > 0) then
				raw = themeSnapshot.intrinsicTextSize(metrics, node.class)
			end
			if (raw ~= nil or fitted ~= nil) and handles[node.path] ~= nil then
				--[[ ONE LADDER, AUTHORED OR NOT — the ten-foot adaptation round, 2026-08-18.
					This read
					`if authored then raw * scale else raw`, and the measure seam said the
					same thing, so the two agreed and nothing clipped — which is precisely
					why nobody saw that `UI.Text{ text }` painted 16px on a television
					while `UI.Text{ textSize = "body" }` painted 24. The ten-foot floor is
					a property of the ROLE ("body text must clear ~29pt at 3m", D.1), and
					an unauthored node wears a role too (`INTRINSIC_TEXT_ROLE`), so it
					takes the same multiplier. Scaling here alone would draw 27px inside a
					box reserved for 18: `layout_node.textOf` moves in the same commit,
					and measure/paint agreement is the property that had to survive. ]]
				-- a fit size is ALREADY the number to draw (the solver picked it out of
				-- a band this seam's own `layout_node.textOf` had already scaled), so it
				-- is written straight through rather than multiplied a second time
				local scaled = if fitted ~= nil then fitted else (raw :: number) * scale
				if lastTextSize[node.path] ~= scaled then
					authority.assertWrite(node.class, "textSize", "layout")
					adapter.setProp(handles[node.path], "textSize", scaled, "layout")
					lastTextSize[node.path] = scaled
					stats.propWrites += 1
				end
				-- a CONTENT Button draws no text of its own, so it has no face to
				-- write either (`raw` is already nil for one, above)
				local roleName, role =
					themeSnapshot.effectiveTypeRole(metrics, node.class, node.props and node.props.textSize)
				if role ~= nil then
					if lastTextFont[node.path] ~= role.fontKey then
						authority.assertWrite(node.class, "textFont", "layout")
						adapter.setProp(handles[node.path], "textFont", {
							role = roleName,
							fontKey = role.fontKey,
							family = role.font.family,
							weight = role.font.weight,
							style = role.font.style,
						}, "layout")
						lastTextFont[node.path] = role.fontKey
						stats.propWrites += 1
					end
				end
			end
			for _, child in descendOf(node, true, true) do
				walk(child, true)
			end
		end
		walk(rootNode, false)
		publishVisits("textScale", visits)
	end

	-- PAINT SEAM FOR PADDING, exactly the shape `textScale` has. A Button's
	-- engine text inset is theme geometry: it resolves through the snapshot, so a
	-- theme swap or a designer's live metric edit moves it — and it is written
	-- here, inside the solve, against THAT solve's metrics, so the inset the
	-- engine draws with and the padding the solver reserved can never disagree.
	-- Minimal-write: the effective four sides are cached per path, so a steady
	-- theme costs zero writes.
	--
	-- ...AND A PADDED `Text` GOES OUT THE SAME SEAM (device report 2026-08-12,
	-- IMG_3691 — the S1..S12 stat tiles). `UI.padding` is legal on a Text because
	-- the solver's text measure ADDS it to the reserved box
	-- (`blueprint_schema` Text.padding: "it lets UI.padding apply without
	-- wrapping"), and nothing painted it: the plate came out label+12 wide and the
	-- glyphs were drawn from the box's leading edge, so every tile's label sat
	-- against — and over — its own rounded corner. Measured at a size nobody
	-- painted, which is "measure the requirement, not the render"
	-- read backwards. A container spends its padding in `arrange` (children are
	-- placed at rect + padding) and a Button already had this write, so a text LEAF
	-- was the one shape where the two passes could disagree.
	--
	-- Guarded on an AUTHORED value: an unpadded Text — every Text on every shipped
	-- screen but these — raises no write and materializes no engine modifier.
	local function padding(rootNode: any, metrics: any)
		local visits = 0
		-- `chosen`: see `harvest`'s walk (C4)
		local function walk(node: any, chosen: boolean)
			if not chosen and skip(node, true, true) then
				return
			end
			visits += 1
			local pad: any = nil
			if node.class == "Button" then
				pad = themeSnapshot.buttonPadding(metrics, node.props)
			elseif node.class == "Text" then
				if node.props ~= nil and node.props.padding ~= nil then
					pad = themeSnapshot.resolveSides(metrics, node.props.padding)
				elseif lastPadding[node.path] ~= nil then
					-- ...AND AN ADOPTED INSTANCE MUST BE UN-PADDED EXPLICITLY. The
					-- recycler carries `padding` across an adoption
					-- (`captureParkedProps`/`restoreParkedProps` below), so a padded
					-- label recycled into an unpadded one would keep the previous row's
					-- inset on a modifier this seam had stopped visiting. Zeroing is a
					-- write; skipping is a stale glyph box.
					pad = { top = 0, right = 0, bottom = 0, left = 0 }
				end
			end
			if pad ~= nil and handles[node.path] ~= nil then
				local top, right, bottom, left = solver.sides(pad)
				local key = `{top},{right},{bottom},{left}`
				if lastPadding[node.path] ~= key then
					authority.assertWrite(node.class, "padding", "layout")
					adapter.setProp(handles[node.path], "padding", pad, "layout")
					lastPadding[node.path] = key
					stats.propWrites += 1
				end
			end
			for _, child in descendOf(node, true, true) do
				walk(child, true)
			end
		end
		walk(rootNode, false)
		publishVisits("padding", visits)
	end

	-- PAINT SEAM FOR THE COMPACT LADDER, the same shape `textScale` and
	-- `padding` have (director, 2026-07-27).
	--
	-- The verdict is the SOLVER's — only it knows the width this node ended up
	-- with — and it reaches paint through the rects it produced, so the string the
	-- box was reserved for is the string the engine draws. That is the whole
	-- reason this is a post-solve seam and not a prop the author toggles.
	--
	-- The label ITSELF still goes out on the ordinary binding write, so there is
	-- exactly one writer for `Text` and `screen_target`'s TextWrapped rule
	-- re-decides from the string it is handed, exactly as it does for a reactive
	-- label. An icon form additionally raises an icon REQUEST, which is the same
	-- upgrade-not-dependency arrangement `props.icon` already uses: the ASCII
	-- glyph is already drawn, and theme art paints over it if any resolves.
	-- Minimal-write: the verdict is cached per path, so a steady layout costs zero
	-- writes and a node with no compact form is never visited twice.
	-- ...and the WRAP verdict, on the same seam and for the same reason (director
	-- ruling 5, 2026-08-13). `screen_target`'s TextWrapped rule sees the string and
	-- not the box, so it cannot answer "does this phrase's longest word fit"; the
	-- solver can, and does (`textFacts.wraps`). Unlike `lastCompact` this IS a value
	-- the instance holds, so it rides the parked-props record across a recycle
	-- exactly as `lastTextSize` does — a recycled instance carrying `TextWrapped =
	-- false` with a cleared cache would silently keep it.
	--
	-- `nil` means "never written", which is the adapter's own default (wrap on
	-- whitespace) — so the overwhelmingly common `wraps = true` node costs ZERO
	-- writes, on the first solve and every one after it.
	-- ONE WALK, TWO VERDICTS. Both are the solver's answers about text, both reach
	-- paint through the rects that produced them, and both are cached per path — so
	-- they share the traversal rather than paying for a second one on every solve.
	local function textVerdicts(rootNode: any, rects: any)
		local visits = 0
		-- `chosen`: see `harvest`'s walk (C4)
		local function walk(node: any, chosen: boolean)
			if not chosen and skip(node, true, true) then
				return
			end
			visits += 1
			local handle = handles[node.path]
			local labelDriven = node.class == "Text" or (node.class == "Button" and #node.children == 0)
			if labelDriven and handle ~= nil then
				local entry = rects[node.path]
				if node.class == "Button" then
					local isCompact = entry ~= nil and entry.compact == true
					local form = layout_node.compactForm(node.props)
					if form ~= nil and lastCompact[node.path] ~= isCompact then
						authority.assertWrite("Button", "text", "binding")
						-- `drawnButtonText` CAN return nil (an icon form whose glyph
						-- does not resolve and whose props declare no `label`), so
						-- `label` rides the SAME worn-set choke point as `icon` and
						-- `compactLabel` below — it is a BINDING_PROPS member that
						-- crosses nil on exactly the same compact toggle, just via a
						-- different write site than `applyProp`'s own.
						local labelValue = layout_node.drawnButtonText(node.props, isCompact)
						adapter.setProp(handle, "label", labelValue, "binding")
						stats.propWrites += 1
						noteWorn(node.path, "label", labelValue)
						if form.kind == "icon" then
							authority.assertWrite("Button", "icon", "style")
							local iconValue = if isCompact then form.icon else nil
							adapter.setProp(handle, "icon", iconValue, "style")
							stats.propWrites += 1
							noteWorn(node.path, "icon", iconValue)
						elseif form.kind == "image" then
							authority.assertWrite("Button", "compactLabel", "style")
							local compactLabelValue = if isCompact then form else nil
							adapter.setProp(handle, "compactLabel", compactLabelValue, "style")
							stats.propWrites += 1
							noteWorn(node.path, "compactLabel", compactLabelValue)
						end
						lastCompact[node.path] = isCompact
					end
				end
				-- THE WRAP VERDICT (ruling 5). A node the solve did not reach (hidden,
				-- not yet solved) keeps whatever it has: absent facts are not a verdict.
				local facts = if entry ~= nil then entry.textFacts else nil
				if facts ~= nil then
					local wraps = facts.wraps == true
					local previous = lastWrapped[node.path]
					if (if previous == nil then true else previous) ~= wraps then
						authority.assertWrite(node.class, "textWrapped", "layout")
						adapter.setProp(handle, "textWrapped", wraps, "layout")
						lastWrapped[node.path] = wraps
						stats.propWrites += 1
					end
				end
			end
			for _, child in descendOf(node, true, true) do
				walk(child, true)
			end
		end
		walk(rootNode, false)
		publishVisits("textVerdicts", visits)
	end

	--[[ THE VISIBILITY VERDICT. A hidden candidate must not PAINT: a zero rect was
		not enough, because text still wrapped and drew inside a 0px box (found live
		in the `adaptive_controls` capture, where the losing action column's labels
		ran down the screen edge). The solver marks the candidate ROOT only, so
		hiddenness is carried DOWN the walk. Feature-detected: an adapter with no
		`setVisible` keeps today's behaviour, and — deliberately — writes no
		`solverHidden` verdict either, exactly as before this was a module. ]]
	local function visible(rootNode: any, rects: any, nextHidden: any)
		if adapter.setVisible == nil then
			return
		end
		local function rectFor(path: string): any
			return paintedRectIn(rects, path)
		end
		--[[ A STROKED PATH IS THE ONE VERDICT ON THIS WALK THAT IS NOT LOCAL (P4).
			`pathEscapesClip` asks the path's CLIP HOST for its box, so a host that
			merely RESIZED — its own entry new, the path's entry carried forward
			untouched — changes the answer for a node the prune would stop at. Rather
			than reason about which resizes can reach which path, a surface that draws
			any stroked path takes the full walk.

			THE CASE IS REAL AND IT IS DRIVEN, not argued (P4 review, I1). A clip host
			that shrinks because a SIBLING GREW moves no rect inside itself: the path's
			entry is carried forward table-for-table and `dirtyContains` never reaches
			it, so the prune stops exactly where the cull was needed. Setting
			`prunable = true` leaves the ring painting outside its own host —
			`tests/commit_scope.spec.luau`, "A STROKED PATH IS CULLED BY A CLIP HOST
			THAT SHRANK".

			AND THE COST OF THE GATE IS ONE WHOLE WALK, WHICH THE FIRST VERSION OF THIS
			COMMENT UNDERSTATED. Measured 2026-09-01 on a 1,002-node list, steady
			one-leaf update: 40 visits with both gates open, 1,039 with this one shut,
			2,042 with both. The denominator is the PRUNED commit, not the pre-P4 one,
			so a shut gate is ~26x this walk's own work and not "one eighth of the
			commit". `pathNodes` is empty on every screen in this repository's showcase
			but the two that draw rings — AND on any surface carrying a CIRCULAR
			`ProgressView`, which emits two `UI.Path` leaves of its own
			(`controls/progress_view.luau`, the ring's Track and Arc). A screen with one
			spinner therefore loses this walk's prune entirely. ]]
		local prunable = next(pathNodes) == nil
		local visits = 0
		-- `chosen`: see `harvest`'s walk (C4). It is true only where the parent
		-- selected from `descendOf(parent, true)` — the identical question — and
		-- false on the root and on every child of a node that took the live list,
		-- where this guard's own `prunable and not flipped` short-circuits before
		-- `skip` is ever called.
		local function pushVisible(node: any, hidden: boolean, forced: boolean, chosen: boolean)
			-- ...AND A HIDE IS INHERITED, so a flip at an ancestor has to reach every
			-- descendant even where the descendant itself is clean.
			local flipped = forced or hiddenFlips[node.path] == true
			if not chosen and prunable and not flipped and skip(node, true) then
				return
			end
			visits += 1
			local isHidden = hidden or nextHidden[node.path] == true
			solverHidden[node.path] = isHidden
			-- RS-PATHCLIP: a stroked path outside its clip host is culled. It is
			-- decided per NODE and never inherited (a Path is a leaf, and the
			-- solver's own verdict is what descends), so the walk keeps carrying
			-- `isHidden` down and this only widens the write for the path itself.
			-- ...and a presenter PAINT HOLD (auto reveal) is a per-node veto the
			-- same way: never inherited, never contradicting the solver.
			local wantHidden = isHidden or paintHeld[node.path] == true
			if not wantHidden and pathNodes[node.path] == true and pathEscapesClip(node.path, rectFor) then
				wantHidden = true
			end
			local handle = handles[node.path]
			if handle ~= nil and lastVisible[node.path] ~= not wantHidden then
				adapter.setVisible(handle, not wantHidden)
				lastVisible[node.path] = not wantHidden
			end
			--[[ THE CACHED LIST ONLY WHERE THE PRUNE IS LIVE (C4). A non-prunable
				surface never consults `skip` at all, and a FLIP forces every descendant
				whatever `skip` would have said — so both take the live child list, as
				they did before the cache existed. Where the prune IS live, a child whose
				own verdict flipped is still in the list: `hiddenFlips` is written only
				for nodes `harvest` VISITED, and `skip` is monotone in its flags, so a
				node `skip(n, true)` refused is a node `skip(n)` refused too. ]]
			local selected = prunable and not flipped
			for _, child in (if selected then descendOf(node, true) else node.children) do
				pushVisible(child, isHidden, flipped, selected)
			end
		end
		pushVisible(rootNode, false, false, false)
		publishVisits("visible", visits)
	end

	--[[ B-BTN3: enforce the effective target floor in HIT geometry. The visual rect
		is deliberately untouched — flooring the painted size would silently rewrite
		shipped design (a 22px icon button would double) — so the framework separates
		what the player SEES from what the player can HIT. ]]
	local function hitRects(rootNode: any, rects: any, nextHidden: any, metrics: any)
		if adapter.setHitRect == nil then
			return
		end
		-- A HIDDEN CANDIDATE ASKS FOR NOTHING — found live by the rich-skinning
		-- device matrix, under the flat default, with real injected clicks. This
		-- walk used to ignore the
		-- `nextHidden` set the visibility walk just built. A hidden candidate
		-- solves to zero width, so every control inside it fell under the floor
		-- and the renderer ASKED for an expanded hit rect — a live activation
		-- surface for a control the player cannot see, which in the real adapter
		-- sits at the ScreenGui root and out-ranked the VISIBLE winner's buttons.
		-- Hiddenness is carried down the walk (the solver marks the candidate
		-- ROOT only) exactly as `pushVisible` carries it, and a hidden node takes
		-- the SAME diff path with `want = nil`, so a node that BECOMES hidden has
		-- its expander retracted rather than merely left un-refreshed.
		--[[ ...AND THE ONE FLOOR THAT IS BOUNDED (DIR5 review H1). A
			region's expand affordance in the "cover" role IS the region's whole box,
			so inflating it to the touch floor necessarily leaves the region on the
			axis it is short on — measured at 390x150 as 960 px2 of one neighbouring
			Button and 828 of another, 26% of each, delivered to the plate instead of
			to the button the player aimed at.

			THE BOUND IS R18 AS IT WAS RULED, AND THE REGION BOX IS NOT IT. The ruling
			splits by what is UNDERNEATH: the 44px floor is EXEMPT over PASSIVE content
			— it is the F1 accessibility floor and the convention every platform ships
			— and BANNED over INTERACTIVE content, because two actionable targets for
			one gesture is the ambiguity the player cannot see. So a cover keeps its
			whole floor unless that floor would reach an interactive node OUTSIDE its
			own region, and only then falls back to the region's box.

			CLAMPING TO THE REGION UNCONDITIONALLY WAS TRIED FIRST AND MEASURED WRONG.
			On the shipped HUD demo the un-clamped floors of all five covers take
			NOTHING from any interactive node — the regions have room around them — and
			the unconditional clamp took the accessibility floor off three of them
			purely because their regions are 21-30px tall. `overflow_sweep`'s
			"no dead-end compact" guard reported it on five viewports: a route the
			thumb cannot land on is a route on paper. The guard was right and the
			first rule was over-applied.

			WHY NOT A NODE-AWARE `effectiveHitFloor`. `syncZOrder` calls that same
			function to reserve the expander's z slot, and NM-H4a made that reservation
			a function of the CLASS rather than of the current state after a whole-band
			paint defect on a real device. A floor that returned nil for a cover would
			move every z below every cover and put the reservation back on history.
			This decision reads THIS SOLVE's rects and the structural sink census, and
			never `lastHitRects` — it is a function of the frame, not of its history. ]]
		--[[ EVERY NODE THE FRAMEWORK SYNTHESIZED FOR ITSELF, which is the honest
			scope of the rule above rather than the one case that commissioned it
			(plate-B fix round 1, its review's MEDIUM-2). A cover is a region's whole
			box and a `close` is the plate's own way out; both are chrome no author
			declared, and the ruling this implements is about what a floor LANDS ON,
			not about which of the two asked for it. Measured before the widening: the
			close's 44px band took 6x6 px at Medium and 9x9 at Large from an author
			Button in the plate's top-trailing corner, with the close on top — two
			actionable targets for one gesture.

			A `chevron` is deliberately NOT here: it reserves its own column out of
			the form's measure, so its floor overlaps nothing it did not already own,
			and growing it would be arithmetic with no case behind it. ]]
		local function isFrameworkChrome(node: any): boolean
			local props = node.props
			local target = if props ~= nil then props.expandTarget else nil
			if type(target) ~= "table" then
				return false
			end
			local role = (target :: any).role
			return role == "cover" or role == "close"
		end
		--[[ EVERY RECT A PRESS MEANT FOR THE AUTHOR COULD LAND ON — and only those
			(ruling R23, 2026-08-21). `inputSinks` is the same structural census the
			overhang lift resolves against, collected on the live-path walk, so this
			costs one pass over that set per STANDING COVER and nothing at all on every
			other node. Its VALUE is what R23 turns on: `true` for a sinker the author
			declared, `false` for one the framework synthesized.

			WHY THE FRAMEWORK MAY NOT BLOCK ITSELF. R18 ruled the AUTHOR-content
			question — a framework floor landing on the player's own controls is the
			one-gesture-two-meanings collision, and that is the DIR5 theft this rule
			exists to close. It was never asked whether the framework should surrender
			the F1 accessibility floor to its OWN affordance, and `hit_lift`'s doctrine
			already answers the same question the other way: "expander-vs-expander is
			left to the existing host z order… another expander's invisible rect never
			[creates a lift]". A cover paints not one pixel; two of them overlapping is
			an ordering question the z walk already decides, not an ambiguity the
			player can see.

			MEASURED, WHICH IS WHY THIS IS A RULING AND NOT A PREFERENCE. Counting the
			framework's own affordances as blockers put 43 of the 381 route boxes in
			the suite's own swept matrix under the touch floor and retracted 32 covers
			outright, the smallest route landing at 25px — one pixel above
			`overflow_sweep`'s dead-end bar, i.e. a silent accessibility regression
			that nothing would have reported.

			IT NEEDS NO "NOT MY OWN REGION" FILTER, and one was written and then
			removed because no mutation could redden it (2026-08-21). R18 exempts the
			floor inside its own region, and the geometry already delivers that: every
			side's test skips a blocker on the far side of the edge it is moving, so a
			blocker CONTAINED in the node's own rect — which is what a region's own
			standing form is — skips on all four sides by construction.

			A HIDDEN NODE CANNOT BE PRESSED, and `solverHidden` was written by the
			visibility walk that runs immediately before this one. ]]
		--[[ ...AND THE BLOCKERS ARE BROUGHT INTO THE CHROME NODE'S OWN SPACE (Plan C,
			C1), which is why this takes the entry's path. Beneath a coordinate-space
			host a rect is stored relative to that host, so a sink under one host and a
			chrome node under another are two rects in two origins and comparing them
			raw means nothing.

			COMPOSED INTO THE ENTRY'S SPACE, NOT INTO WINDOW SPACE, and that choice is
			forced rather than stylistic: `growWithin(r, want, blockers)` RETURNS `want`,
			and `want` is what `setHitRect` stores and what `applyHitExpander` later
			re-bases by subtracting the host origin. Composing the blockers to window
			space while leaving `want` raw compares mismatched spaces; composing `want`
			too hands back a window-space rect the adapter then re-bases a SECOND time.
			Either way a space host's chrome expander is wrong by the host origin. So
			each blocker is offset by `originOf(sink) - originOf(entry)` and `r`, `want`,
			`growWithin`'s output and the stored entry all stay in the entry's space.

			`originOf` READS THIS SOLVE'S MAP, never `lastRects`: this walk runs inside
			the commit span, before `lastRects` is rewritten, so last frame's origin
			would be a one-frame lag on exactly the frame a host moved. ]]
		local function authorPressableRects(entryPath: string): { any }
			local out: { any } = {}
			local ex, ey = originOf(entryPath)
			for path, authored in inputSinks do
				if authored ~= true or solverHidden[path] == true then
					continue
				end
				local other = rects[path]
				local r = if other ~= nil then other.rect else nil
				if r ~= nil and r.w > 0 and r.h > 0 then
					local ox, oy = originOf(path)
					if ox == ex and oy == ey then
						table.insert(out, r)
					else
						table.insert(out, { x = r.x + ox - ex, y = r.y + oy - ey, w = r.w, h = r.h })
					end
				end
			end
			return out
		end
		local visits = 0
		-- `chosen`: see `harvest`'s walk (C4). It is true only where the parent
		-- selected from `descendOf(parent)` — this walk's own, flagless question —
		-- and false wherever the parent took the live list, where `not sawChrome and
		-- not flipped` short-circuits this guard before `skip` is called.
		local function pushHitRects(node: any, hidden: boolean, forced: boolean, chosen: boolean)
			--[[ THE CHROME FLOOR IS THE OTHER NON-LOCAL VERDICT (P4). A cover's or a
				close's floor grows against every AUTHOR-pressable rect on the surface
				(`authorPressableRects` below, ruling R23), so any rect moving anywhere
				can change what a chrome node asks for — including a chrome node whose
				own entry was carried forward. `sawChrome` latches the moment this walk
				meets one and is cleared only by a full commit. The hide half is
				`pushVisible`'s, for the same reason.

				THE CASE IS REAL AND IT IS DRIVEN (P4 review, I1). An author control
				that WIDENS toward a cover moves the cover's floor without moving the
				cover: its rect is unchanged, its entry is carried forward, and the
				prune stops there. Dropping `not sawChrome` resurrects the exact R23 hit
				theft the floor exists to prevent — a 44x44 expander standing over the
				author's own button instead of the 40x32 the blockers leave it
				(`tests/commit_scope.spec.luau`, "A CHROME FLOOR IS RE-GROWN WHEN AN
				AUTHOR CONTROL MOVES UNDER IT").

				AND THE COST IS ONE WHOLE WALK, stated the same way `pushVisible`'s gate
				states it: 40 steady visits become 1,040 with this gate shut and 2,042
				with both (1,002-node list, 2026-09-01). IT IS NOT A RARE SHAPE. Every
				dismissible plate the framework builds carries a `close`
				(`blueprint.luau`'s close affordance) and every `UI.Region` in its
				compact form carries a `cover` (`blueprint.luau`'s expand affordance),
				so any screen with a plate or a region loses this walk's prune for the
				life of the surface. The headline `battle_hud` numbers have neither
				feature and are therefore the BEST case. ]]
			local flipped = forced or hiddenFlips[node.path] == true
			if not chosen and not sawChrome and not flipped and skip(node) then
				return
			end
			visits += 1
			local isHidden = hidden or nextHidden[node.path] == true
			local entry = rects[node.path]
			if isFrameworkChrome(node) then
				sawChrome = true
			end
			-- the same reading the solve was handed as `hitFloor` (see
			-- `effectiveHitFloor`): the contract declares the floor exists, the
			-- theme owns its value, and it clamps up only
			local floor = layout_node.effectiveHitFloor(node.class, metrics)
			if floor ~= nil then
				local handle = handles[node.path]
				if entry ~= nil and handle ~= nil then
					local r = entry.rect
					local want: any = nil
					if not isHidden and (r.w < floor or r.h < floor) then
						local w = math.max(r.w, floor)
						local h = math.max(r.h, floor)
						want = {
							x = r.x - math.floor((w - r.w) / 2),
							y = r.y - math.floor((h - r.h) / 2),
							w = w,
							h = h,
						}
						if isFrameworkChrome(node) then
							-- `r` is NOT composed: it is this entry's own rect, already in
							-- this entry's space, and the blockers are composed INTO that
							-- space above
							want = commit_walks.growWithin(r, want, authorPressableRects(node.path))
							-- grown back to the box it already paints, there is
							-- nothing to advertise: an expander the size of its own
							-- host is a transparent duplicate of it
							if want.w <= r.w and want.h <= r.h then
								want = nil
							end
						end
					end
					local last = lastHitRects[node.path]
					if not rectsEqual(last, want) then
						adapter.setHitRect(handle, want)
						lastHitRects[node.path] = want
					end
				end
			end
			--[[ ...and the same two exemptions (C4), plus the LATCH — read HERE and not
				at the top, so a chrome node found in THIS NODE'S OWN BODY still opens the
				full walk for its own children.

				WHAT DID CHANGE, said plainly (review Minor 1): `selected` is decided once
				for the whole child loop, so a chrome node discovered inside an EARLIER
				SIBLING's subtree no longer widens the walk for the LATER siblings — before
				the cache the latch was re-read inside each child's own guard.

				IT IS OUTPUT-NEUTRAL BECAUSE OF THE LATCH'S LIFETIME, not because of the
				loop. `sawChrome` is cleared only by an UNARMED commit (`harvest`'s
				`if not pruning` arm) and is re-latched during that same commit, whose
				`hitRects` walks the whole tree. So on any surface that holds chrome at
				all, `sawChrome` is already true at the START of every pruned commit,
				`selected` is false everywhere, and the live child list is taken exactly as
				before. The narrowing can only bite on a surface where no walk has ever met
				chrome — where the latch never becomes true and there is nothing to widen
				for. Beyond that, the only thing a wider walk recomputes is another chrome
				node's floor: `authorPressableRects` is read by `isFrameworkChrome` nodes
				alone. ]]
			local selected = not sawChrome and not flipped
			for _, child in (if selected then descendOf(node) else node.children) do
				pushHitRects(child, isHidden, flipped, selected)
			end
		end
		pushHitRects(rootNode, false, false, false)
		publishVisits("hitRects", visits)
	end

	--[[ NATIVE SCROLL REGIONS — the native-substrate round's scroll seam, and the
		one place a canvas is published. A scroll node's SOLVED
		content extent (plus its own padding — children arrange inside the padded
		area, so the canvas must include it) maps to the adapter's canvas. The
		adapter/engine owns the live offset; the solver keeps owning every content
		rect. Feature-detected: a scroll-less adapter (billboard until proven, old
		fake) keeps the clip-only fallback. ]]
	local function scrollRegions(rootNode: any, rects: any, metrics: any)
		if adapter.setScrollRegion == nil then
			return
		end
		local visits = 0
		-- `chosen`: see `harvest`'s walk (C4)
		local function pushRegions(node: any, chosen: boolean)
			if not chosen and skip(node, true, true) then
				return
			end
			visits += 1
			if node.class == "ScrollView" then
				local entry = rects[node.path]
				local handle = handles[node.path]
				if entry ~= nil and entry.contentSize ~= nil and handle ~= nil then
					-- THE PADDING THE SOLVER ACTUALLY SPENT, not the padding the
					-- author wrote (found 2026-07-27 while chasing a landscape
					-- scroll cut-off). `toLayoutNode` adds a slot's `chromeInsets`
					-- to this node's padding before the solve, and a ScrollView
					-- always classifies into the `scrollbar` slot — so recomputing
					-- from `props.padding` here would under-report the canvas by
					-- exactly the theme's reservation, and the tail of the content
					-- would be unreachable. Inert today (every shipped package
					-- declares `chrome.scrollbar = { kind = "native" }`, reserving
					-- zero) and wrong the moment one does not.
					local props = node.props or {}
					local layoutPadding = if entry.padding ~= nil
						then entry.padding
						else themeSnapshot.resolveSides(metrics, props.padding)
					local pt, pr, pb, pl = solver.sides(layoutPadding)
					-- ...PLUS THE THEME'S DECORATION BLEED (director round 11,
					-- root-caused 2026-07-27 from a landscape capture).
					--
					-- A canvas built from RECTS stops exactly at the last child's
					-- rect — I measured it doing so to the pixel in seven
					-- configurations. A `shadow` recipe paints OUTSIDE that rect,
					-- so under Sci-Fi HUD (a centred 24px glow on `panel`) the
					-- bottom of the last element was unreachable: scrollbar at the
					-- end of its track, content still cut off.
					--
					-- It is spent HERE and nowhere else, deliberately. Reserving it
					-- as layout margin would be the other way to fix it and it would
					-- be wrong — a glow is meant to overlap its neighbours, and
					-- reserving it would space every themed screen out by 24px in
					-- every direction. A canvas allowance is the scroll-inset shape every
					-- platform ships: the layout does not move, the paint becomes
					-- reachable.
					-- Zero for every package that declares no shadow.
					local bleed = if type(metrics.chromeBleed) == "number" then metrics.chromeBleed else 0
					local region = {
						axis = props.axis or "y",
						contentW = entry.contentSize.w + pl + pr + bleed,
						contentH = entry.contentSize.h + pt + pb + bleed,
						-- the host's ARRANGED box, so the adapter's cross-axis
						-- canvas clamp is deterministic instead of racing the
						-- engine's own window geometry mid-layout. FIX ROUND 2
						-- (task SCROLL2, RED-TEAM re-review): this read `entry.w`/
						-- `entry.h`, which do not exist on a solver rect entry — the
						-- arranged box lives at `entry.rect.w`/`entry.rect.h`
						-- (`layout/solver.luau`'s `out[node.id] = { rect = rect, ... }`).
						-- So `hostW`/`hostH` were ALWAYS nil, which made
						-- `screen_scroll_indicators.setScrollRegion`'s
						-- `instance.AbsoluteWindowSize` fallback the ONLY branch ever
						-- taken on the live adapter — self-consistent before fix round
						-- 1's reorder (it ran right after `rectPass.apply` painted
						-- THIS solve's Size), genuinely stale after it (now reads the
						-- class-default/previous-solve Size, one solve behind). Fixed
						-- at the root rather than re-arguing the fallback's safety.
						hostW = entry.rect.w,
						hostH = entry.rect.h,
						-- per-host indicator opt-out (director ruling 2026-08-09):
						-- carried on the region because the adapter learns a host
						-- overflows on exactly this walk — the same place its
						-- indicator lifecycle begins
						indicators = if props.indicators == "none" then "none" else "auto",
					}
					-- the host's own autoscroll declaration, recorded on the SAME
					-- walk that publishes its canvas: `false` opts out, a table
					-- tunes the model, absent means on-and-inert. Kept here so the
					-- per-frame stepper never needs a tree lookup.
					scrollAutoscroll[node.path] = if props.autoscroll == false
						then false
						else (if type(props.autoscroll) == "table" then props.autoscroll else true)
					local last = lastScrollRegions[node.path]
					if
						last == nil
						or last.axis ~= region.axis
						or last.contentW ~= region.contentW
						or last.contentH ~= region.contentH
						or last.indicators ~= region.indicators
						or last.hostW ~= region.hostW
						or last.hostH ~= region.hostH
					then
						authority.assertWrite("common", "canvasSize", "layout")
						adapter.setScrollRegion(handle, region)
						lastScrollRegions[node.path] = region
					end
					-- RS-PATHCLIP: the host's live offset is what a stroked path
					-- inside it has to be re-culled against. One subscription per
					-- scroll host, taken where the host is already in hand; the
					-- callback early-outs on a surface with no paths, so a list that
					-- draws none pays a comparison.
					if adapter.observeScroll ~= nil and pathClipObservers[node.path] == nil then
						pathClipObservers[node.path] = adapter.observeScroll(handle, function()
							reculPathClips()
						end)
					end
				end
			end
			for _, child in descendOf(node, true, true) do
				pushRegions(child, true)
			end
		end
		pushRegions(rootNode, false)
		publishVisits("scrollRegions", visits)
	end
	return {
		harvest = harvest,
		textScale = textScale,
		padding = padding,
		textVerdicts = textVerdicts,
		visible = visible,
		hitRects = hitRects,
		scrollRegions = scrollRegions,
		--[[ THE PRUNE ITSELF, handed to `render/rect_pass` — the eighth walk of the
			same tree and the last one in the commit, which is why it is the walk that
			WRITES the record all seven compare against. Three functions rather than a
			shared record because the two files then share no mutable state at all: the
			prune's own state stays a per-attach local in here, exactly as the seam
			test for this module requires. `publishVisits` rides along so `rect_pass`
			— the eighth walk, and not one of this module's seven — publishes into the
			same per-walk table instead of keeping a second one (wicked-fast T2). ]]
		scope = {
			skip = skip,
			-- ...and the eighth walk descends the same cached list the seven do (C4),
			-- which is also what makes it the walk that FILLS the cache for a subtree
			-- the `moveBlind` seven stopped above
			descendOf = descendOf,
			note = note,
			noteEntry = noteEntry,
			armed = armed,
			records = records,
			publishVisits = publishVisits,
		},
	}
end

return commit_walks
