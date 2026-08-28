--!strict
--[[ THE CONTAINMENT INVARIANT — layer 1 of the overflow guard (director order,
	2026-08-21: "how do we ensure our test system catches those overflows like
	with the 9 and prevents them").

	THE ESCAPE THIS ANSWERS. The region-expand plate painted its `9` 8px past its
	own panel edge, live, at every viewport, while the 180-cell demo sweep and the
	whole suite were green. Measured at the report: panel 208 wide at x=130,
	children spanning 138..346. `plate.w` measured FORM 1 and was written straight
	onto a box that also declares padding, and a padded box's declared width is its
	OUTER width, so the content box was `plate.w` minus two insets and the form,
	measured against `plate.w`, overflowed it by exactly that (fixed 27af00f).

	IT ESCAPED THREE INSTRUMENTS AT ONCE, and each hole is a different sentence:

	  1. THE SWEEPS NEVER OPEN STATEFUL SURFACES. The plate exists only after a
	     tap. `tests/overflow_sweep.spec.luau` mounts and settles; a surface that
	     is not on screen at settle is not swept. (That is layer 3's charter —
	     `states` in the scenario contract, driven by the sweep.)
	  2. THE ORACLES ASK THE WRONG QUESTION. `tools/studio/device_matrix.luau`'s
	     `observe()` asks "is this rect off the VIEWPORT" (`absPos.x < -1 or
	     right > vw + 1`). The plate was fully on screen. Nothing anywhere asked
	     "is this rect outside the box it lives in".
	  3. NOTHING FORBADE A ZERO BOX. A visible, non-empty Text solving 0 wide is
	     copy the player cannot read, and the suite had no sentence about it.

	SO THIS MODULE IS THE MISSING QUESTION, asked after every settle in every
	fixture that mounts through `tests/lib/world`:

	  (a) every EFFECTIVELY-VISIBLE PAINTED node's rect is contained by its nearest
	      containment boundary's box;
	  (b) a visible, non-empty Text node never has a zero-width or zero-height box.

	── EFFECTIVELY VISIBLE, AND WHY IT IS SPELT OUT ──────────────────────────────

	The forensics on this very defect misread own-`Visible` on a hidden variant
	subtree and reported the collapsed `12`/`9` solving width 0 as a second defect.
	It was not: those texts solve 36 and 18 wherever `ClockStack` is standing, and
	the zeros live in the HIDDEN form-1 subtree, every node of which the framework
	marks invisible. A guard that read a node's OWN `visible` flag would have
	inherited that misreading and shipped a permanent false positive on the exact
	surface it was built for.

	So visibility here is the ANCESTOR CHAIN: a node is effectively visible when
	its own flag is not false, no ancestor's flag is false, and its surface root
	is not hidden. Every one of those three is a fact the adapter already records
	(`setVisible`, `setRootVisible`), so this reads the target rather than
	re-deriving anything.

	── WHAT A CONTAINMENT BOUNDARY IS ───────────────────────────────────────────

	Walking up from a node, the first ancestor that is one of these:

	  * a SCROLL HOST (`ScrollView`). Its box is the engine WINDOW
	    (`windowRect`), which is narrower than the frame by the bar thickness —
	    and the constraint applies on the CROSS AXIS ONLY, because content along
	    the axis it scrolls is content the player can bring back. This is the
	    correction the §14a pass had to make mid-sweep for scroll canvases, made
	    once, here.
	  * a CLIP HOST — `clipChildren`, a fade group (a CanvasGroup renders its
	    subtree into its own buffer, so it crops), or a `Foreign` box (which clips
	    from birth, ADR-0034). Both axes: the engine really does cut here.
	  * a PANEL — any node carrying a real `surface`. It does NOT clip, and that
	    is exactly why it belongs: a plate that paints its content past its own
	    edge is the defect above, and nothing in the engine will stop it.

	`plain` is not a panel. `surface = "plain"` is the caller saying NO PLATE:
	`chrome_slots.classify` returns nil for it before any class rule, and the
	native path clears `nativeSurface` with it, so the node carries no fill at
	all. Treating one as a boundary would invent an edge the player cannot see.

	A COMPOSITION IS NOT A BOUNDARY, AND THAT IS A MEASURED RULE RATHER THAN AN
	OVERSIGHT (follow-up triage, 2026-08-21). The solver-split round counted 312
	cases suite-wide of a REGION placed below its composition's own content box and
	routed the class here. Reproduced exactly, and every one of the 312 carries
	`fallback = true` — the composition's own declaration that no arrangement is
	legal, which it already files once per solve, on itself, marked
	`designed = true`, naming the offer it could not satisfy. All 312 are the
	BOTTOM edge (the slot partition is clamped to the box, so nothing escapes
	sideways), and where it fires nothing escapes paint — on the worst cell in the
	suite the composition is offered 304x0 and this guard, the collision finding
	and the off-screen check are all silent. Policing it would re-tell an existing
	finding and call the framework's own designed behaviour a defect. Pinned by
	three cases in `tests/overflow_guard.spec.luau` so the verdict cannot rot into
	an omission.

	ONE CLAUSE OF THAT VERDICT WAS WRONG, and it is struck above rather than left
	to be re-derived: "a LEGAL composition cannot produce one (measured at the
	boundary: the arrangement is rejected the moment a form outgrows the box)"
	stood here until `docs/adr/ADR-0056-lane-give-way-both-ends.md`, which is its
	counterexample. The reasoning was about a form OUTGROWING its box; the defect
	was a zone PLACED outside a box it fits inside, by an arithmetic slip in the
	give-way's own placement — legal, unrejected, uncollided, up to 300px out. The
	312 count was real and every one of them really was a `fallback`; what a count
	cannot know is whether the set it counted is closed. THE SCOPE DECISION ABOVE
	SURVIVES on the three clauses that are still true plus ADR-0056's arithmetic (a
	legal composition's placement now sums to the lane exactly, so the case this
	guard would newly catch cannot be produced) — but it survives as a conclusion
	from a proof rather than from a sample, and the pinned cases now include an arm
	that DECLARES a chrome row, because the two that were here declare none and an
	inset of 0 made them incapable of failing on the class that actually shipped.

	── WHAT PAINTS ──────────────────────────────────────────────────────────────

	A node is judged when it puts something on glass: a non-empty Text, an Image
	with a picture, a Button, a Path, or anything carrying a real surface. A bare
	VStack is a measurement, not a mark — and judging containers as well as their
	leaves would report one overflow twice, once for the box and once for the
	glyph inside it, which is how a census turns into a log nobody reads.

	── WHAT IT DELIBERATELY CANNOT SEE ──────────────────────────────────────────

	It reads SOLVED rects. A node in flight — a slide-in, a marquee, a reveal —
	carries its travel in `presentedPosition`, composed separately (ADR-0022
	Decision 2), so motion is outside this census by construction rather than by a
	waiver somebody has to remember to write. Likewise the R18 hit-expander floor:
	the expanded target is a FIELD on the control's handle (`setHitRect`), never a
	node, so a sub-44px control's target legitimately exceeding its parent is not
	a thing this can report. Both are stated in `tests/lib/overflow_waivers.luau`
	so a reader does not go looking for waivers that cannot exist.

	── THE THEMED PASS (task THEME, 2026-08-27) ─────────────────────────────────

	EVERYTHING ABOVE WAS ONLY EVER ASKED UNDER STUDIO NEUTRAL, and that is the hole
	the director's items 6-9 came through. `tests/overflow_sweep.spec.luau` swings
	eight theme packages onto every swept surface — and collects only
	`controller.diagnostics()` on those passes; this oracle runs once per viewport,
	on the freshly-mounted neutral tree, BEFORE the first `env:set("themeMetrics")`.
	Measured on 2026-08-27 over the showcase corpus at every swept viewport: the
	neutral pass reports ZERO and the eight packages report 92 DISTINCT violations
	the suite had never asked about.

	A PACKAGE ALSO MOVES THE EDGE THE QUESTION IS ABOUT, twice, and both are
	invisible to the neutral rules:

	  1. A THEMED PANEL'S VISIBLE EDGE IS NOT ITS RECT. A nine-slice skin carves a
	     border out of its own box (`ThemeSnapshot.chromeInsets[slot]` — 24px per
	     side on Pixel Quest's `panel`, 30 on Fantasy Ornate's), so the box a player
	     sees content inside is the rect MINUS that. Judging against the outer rect
	     pardons a child painted over the whole frame.
	  2. A PLATE IS OFTEN A SIBLING, NOT AN ANCESTOR. The library's own idiom for a
	     tinted panel is `ZStack{ Box(surface, fill×fill), content }` — the HUD's
	     `glass()` and `selection_indicator`'s pill both build one — so the node
	     carrying the surface is the content's SIBLING and `boundaryFor`, which only
	     ever walks up, never sees it. The framework's chrome reservation lands on
	     that plate, which has no children, and the content clears nothing.

	So with a snapshot in hand this module judges against the THEMED CONTENT BOX of
	the nearest boundary, and treats a full-bleed surfaced sibling as the boundary
	its stack really has. Both are exactly zero-cost on a flat package: Studio
	Neutral, classic-desktop, glossy-mobile and sci-fi HUD publish an all-zero
	`chromeInsets`, so the themed box IS the rect and the sibling plate inset is
	nothing. WITHOUT a snapshot nothing below changes by a byte — every existing
	caller keeps the neutral rules it had.
]]

local waivers = require("./overflow_waivers")
local chrome_slots = require("../../src/tokens/chrome_slots")

local overflow_guard = {}

export type Violation = {
	kind: string,
	node: string,
	class: string,
	boundary: string,
	edge: string,
	overhang: number,
	text: string?,
	waiver: string?,
}

export type Ledger = { waivers: { any }, hits: { [string]: number } }

--[[ A LEDGER IS A WAIVER LIST PLUS ITS USE COUNT, and the count is why it is an
	object rather than two module locals. "Is this waiver still needed" is a claim
	about the WHOLE SUITE — every fixture world and every sweep cell, in one
	process — so it cannot be answered from inside a single spec, and a spec that
	wants to prove the no-rot machinery WORKS needs a ledger of its own rather than
	a way to poke the real one. Both are the same three lines this way. ]]
function overflow_guard.newLedger(waiverList: { any }): Ledger
	local hits: { [string]: number } = {}
	for _, w in waiverList do
		hits[w.id] = 0
	end
	return { waivers = waiverList, hits = hits }
end

-- the process-wide ledger, over the shipped registry: what `world` and the sweep
-- judge against, and what `tests/overflow_guard.spec.luau` reads for rot
local DEFAULT: Ledger = overflow_guard.newLedger(waivers)
overflow_guard.default = DEFAULT
overflow_guard.waivers = waivers

function overflow_guard.unusedWaivers(ledger: Ledger?): { string }
	local l = ledger or DEFAULT
	local out: { string } = {}
	for id, n in l.hits do
		if n == 0 then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

-- ── the census ───────────────────────────────────────────────────────────────

local function parentPath(path: string): string?
	local cut = string.find(path, "/[^/]*$")
	if cut == nil or cut <= 1 then
		return nil
	end
	return string.sub(path, 1, cut - 1)
end

local function isRealSurface(props: any): boolean
	local surface = if type(props) == "table" then props.surface else nil
	return type(surface) == "string" and surface ~= "plain"
end

local function paints(node: any): boolean
	local props = node.props or {}
	if isRealSurface(props) then
		return true
	end
	if node.class == "Text" then
		return type(props.text) == "string" and props.text ~= ""
	end
	if node.class == "Image" then
		return props.image ~= nil
	end
	if node.class == "Button" then
		--[[ A TRANSPARENT HIT TARGET PAINTS NOTHING, and this is the house rule
			rather than a new one: `tools/lune/triage_overflow_waivers.luau` already
			measured it ("a `Hit` Button carries no surface and no label and covers
			nothing a player can see, and counting one is how this probe manufactured
			its first false positives"). It reached this guard the same way, from the
			other direction: with a bare Button counted as paint, nineteen scroll-snap
			cases reported a row's full-width `Hit` overflowing its list by exactly
			8px — the SCROLL BAR, whose window the fixture's layout does not reserve
			(fake_target `_deriveWindowRect`). Nothing there is painted and nothing
			there is visible; the finding was the instrument's. ]]
		return (type(props.label) == "string" and props.label ~= "") or props.icon ~= nil or props.image ~= nil
	end
	if node.class == "Path" then
		return true
	end
	return false
end

--[[ THE THEMED CONTENT BOX of a surfaced node: its rect minus the carved border
	the installed package reserves for that node's chrome slot. `snapshot` nil (the
	neutral pass and every existing caller) returns the rect unchanged, and so does
	every package whose `chromeInsets` are all zero — which is what makes this rule
	free on a flat theme rather than merely cheap.

	THE SLOT IS DERIVED THE WAY THE RENDERER DERIVES IT (`chrome_slots.classify`,
	the same call `render/layout_node` makes), minus the internal `hint` channel a
	node census cannot carry: a control that declared its OWN slot (a Slider's rail)
	is judged against the slot the generic map guesses instead. That under-reports
	on those few nodes and can never over-report, which is the right direction for
	an always-on check. ]]
local function themedBox(snapshot: any, node: any, box: any): any
	if type(snapshot) ~= "table" or box == nil then
		return box
	end
	local insets = (snapshot :: any).chromeInsets
	if type(insets) ~= "table" then
		return box
	end
	local props = node.props or {}
	local slot = chrome_slots.classify({
		class = node.class,
		surface = props.surface,
		hasSelection = props.selected ~= nil,
	})
	local ins = if slot ~= nil then (insets :: any)[slot] else nil
	if type(ins) ~= "table" then
		return box
	end
	local top = if type(ins.top) == "number" then ins.top else 0
	local right = if type(ins.right) == "number" then ins.right else 0
	local bottom = if type(ins.bottom) == "number" then ins.bottom else 0
	local left = if type(ins.left) == "number" then ins.left else 0
	if top == 0 and right == 0 and bottom == 0 and left == 0 then
		return box
	end
	return { x = box.x + left, y = box.y + top, w = box.w - left - right, h = box.h - top - bottom }
end

--[[ THE PLATE THIS CONTAINER REALLY HAS, or nil. The library's idiom for a tinted
	panel is `ZStack{ Box(surface, fill×fill), content }` — the plate is a SIBLING of
	the content, so the surface that draws the edge is never on the walk up. A plate
	is recognised by what makes it one rather than by its id: a childless surfaced
	node whose rect is its parent's rect. `childrenOf` is derived from the sorted
	path census, so this costs one pass over the paths rather than a search per node.
	Only ever consulted when a snapshot is in hand, because on a flat package the
	plate's themed box IS its rect and the rule could only restate the parent. ]]
local function plateOf(
	nodes: { [string]: any },
	children: { [string]: { string } },
	parent: string,
	from: string?
): any?
	local host = nodes[parent]
	if host == nil or host.rect == nil then
		return nil
	end
	for _, childPath in children[parent] or {} do
		--[[ NEVER THE BRANCH THE QUESTION CAME UP, which is the difference between a
			rule and a tautology: the plate is a boundary for its SIBLINGS, and asking
			whether a plate clears its own carved border reports every plate in the
			library overflowing itself by exactly its own inset (measured: ten on the HUD
			alone before this line existed). ]]
		if childPath == from then
			continue
		end
		local child = nodes[childPath]
		if child == nil or child.rect == nil or not isRealSurface(child.props) then
			continue
		end
		if #(children[childPath] or {}) > 0 then
			continue
		end
		local r, h = child.rect, host.rect
		if
			math.abs(r.x - h.x) <= 1
			and math.abs(r.y - h.y) <= 1
			and math.abs(r.w - h.w) <= 1
			and math.abs(r.h - h.h) <= 1
		then
			return child
		end
	end
	return nil
end

--[[ THE BOUNDARY THIS NODE LIVES IN, and on which axes it binds. `axes` is
	"both" everywhere except a scroll host, where the scrolled axis is exempt
	(content you can scroll to is content you can reach). ]]
local function boundaryFor(
	nodes: { [string]: any },
	children: { [string]: { string } },
	path: string,
	snapshot: any?
): (string?, any?, { [string]: boolean }?)
	local cursor, from = parentPath(path), path
	while cursor ~= nil do
		local n = nodes[cursor]
		if n ~= nil then
			if n.class == "ScrollView" then
				local box = n.windowRect or n.rect
				if box ~= nil then
					local scrolled = if type(n.scrollRegion) == "table" then n.scrollRegion.axis else nil
					return cursor, themedBox(snapshot, n, box), { x = scrolled ~= "x", y = scrolled ~= "y" }
				end
			elseif
				(n.props ~= nil and n.props.clipChildren == true)
				or n.canvasGroupInstance ~= nil
				or n.foreignClips == true
			then
				if n.rect ~= nil then
					return cursor, themedBox(snapshot, n, n.rect), { x = true, y = true }
				end
			elseif isRealSurface(n.props) and n.rect ~= nil then
				return cursor, themedBox(snapshot, n, n.rect), { x = true, y = true }
			elseif snapshot ~= nil then
				-- ...AND THE SIBLING PLATE, which is a boundary this container has and
				-- does not carry itself (see `plateOf`). The BOX is the plate's, so the
				-- edge judged is the one a player sees painted.
				local plate = plateOf(nodes, children, cursor, from)
				if plate ~= nil then
					local box = themedBox(snapshot, plate, plate.rect)
					-- IDENTITY, deliberately: `themedBox` hands back the SAME table when
					-- the package reserves nothing for this slot, so this reads "does the
					-- plate carve anything at all". A plate that carves nothing draws its
					-- edge exactly where the parent's box already is and could only
					-- restate the walk-up.
					if box ~= plate.rect then
						return cursor, box, { x = true, y = true }
					end
				end
			end
		end
		if nodes[cursor] ~= nil then
			from = cursor
		end
		cursor = parentPath(cursor)
	end
	return nil, nil, nil
end

local function waiverFor(ledger: Ledger, violation: Violation): any?
	for _, w in ledger.waivers do
		if w.kind ~= violation.kind then
			continue
		end
		if string.find(violation.node, w.node) == nil then
			continue
		end
		if w.boundary ~= nil and string.find(violation.boundary, w.boundary) == nil then
			continue
		end
		if w.maxPx ~= nil and violation.overhang > w.maxPx then
			-- NAMED, NOT SILENT: the waiver matched the shape and refused the SIZE,
			-- and a reader has to be told which waiver decided that or the message
			-- reads as if nothing was ever waived here.
			violation.waiver = `{w.id} (cap {w.maxPx}px exceeded)`
			return nil
		end
		ledger.hits[w.id] += 1
		return w
	end
	return nil
end

--[[ EVERY VIOLATION THIS TARGET IS CURRENTLY SHOWING. Pure: it reads the
	adapter's own census and returns; nothing here fails a test. `world` turns the
	list into a red, and the sweep turns the same list into a finding, so the two
	cannot drift on what counts. ]]
function overflow_guard.violations(adapter: any, ledger: Ledger?, snapshot: any?): { Violation }
	local book = ledger or DEFAULT
	local nodes: { [string]: any } = {}
	local paths = adapter.paths()
	for _, path in paths do
		nodes[path] = adapter.node(path)
	end
	--[[ THE CHILD INDEX, built once, and only when a snapshot is in hand: it exists
		for the sibling-plate rule (`plateOf`) and nothing else asks for it, so the
		neutral pass pays nothing at all for a question it never puts. A path's parent
		is the census entry it hangs off, which is not always its literal path parent —
		an elided container the target never gave a handle is simply absent — so the
		walk climbs to the nearest ancestor that IS in the census, exactly as the
		visibility chain below does. ]]
	local children: { [string]: { string } } = {}
	if snapshot ~= nil then
		for _, path in paths do
			local parent = parentPath(path)
			while parent ~= nil and nodes[parent] == nil do
				parent = parentPath(parent)
			end
			if parent ~= nil then
				local bucket = children[parent]
				if bucket == nil then
					bucket = {}
					children[parent] = bucket
				end
				table.insert(bucket, path)
			end
		end
	end

	-- ANCESTOR-CHAIN VISIBILITY, memoized down the path. `paths()` is sorted, so a
	-- parent is always resolved before its children and the walk is one lookup.
	local visible: { [string]: boolean } = {}
	local function effectivelyVisible(path: string): boolean
		local memo = visible[path]
		if memo ~= nil then
			return memo
		end
		local node = nodes[path]
		local ok = true
		if node == nil or node.visible == false or node.alive == false then
			ok = false
		else
			local root = node.parentRoot
			if root ~= nil and adapter.rootVisibleOf ~= nil and adapter.rootVisibleOf(root.id) == false then
				ok = false
			end
		end
		if ok then
			local parent = parentPath(path)
			-- an ancestor that is not in the census is an elided container the
			-- target never gave a handle: it hides nothing, so the chain continues
			-- through it rather than stopping.
			while parent ~= nil and nodes[parent] == nil do
				parent = parentPath(parent)
			end
			if parent ~= nil then
				ok = effectivelyVisible(parent)
			end
		end
		visible[path] = ok
		return ok
	end

	local out: { Violation } = {}
	for _, path in paths do
		local node = nodes[path]
		if node == nil or node.rect == nil then
			continue
		end
		if not effectivelyVisible(path) then
			continue
		end
		local props = node.props or {}

		-- (b) A VISIBLE STRING IN A BOX WITH NO AREA. It has no waiver class and
		-- never will: there is no design in which copy the player is meant to read
		-- is solved to nothing.
		if node.class == "Text" and type(props.text) == "string" and props.text ~= "" then
			if node.rect.w <= 0 or node.rect.h <= 0 then
				local v: Violation = {
					kind = "zero-box",
					node = path,
					class = node.class,
					boundary = "-",
					edge = if node.rect.w <= 0 then "width" else "height",
					overhang = 0,
					text = props.text,
				}
				if waiverFor(book, v) == nil then
					table.insert(out, v)
				end
				continue
			end
		end

		if not paints(node) then
			continue
		end
		local boundaryPath, box, axes = boundaryFor(nodes, children, path, snapshot)
		if boundaryPath == nil or box == nil or axes == nil then
			continue
		end
		local r = node.rect
		-- a zero-area node paints nothing and cannot be outside anything
		if r.w <= 0 or r.h <= 0 then
			continue
		end
		local worst, edge = 0, ""
		local sides = {
			{ axis = "x", name = "left", over = box.x - r.x },
			{ axis = "x", name = "right", over = (r.x + r.w) - (box.x + box.w) },
			{ axis = "y", name = "top", over = box.y - r.y },
			{ axis = "y", name = "bottom", over = (r.y + r.h) - (box.y + box.h) },
		}
		for _, side in sides do
			if not axes[side.axis] then
				continue
			end
			-- SUB-PIXEL IS NOT AN OVERHANG. Solved rects carry fractional px from
			-- fill weights and metric ladders; a half-pixel is the arithmetic, not a
			-- design escaping its plate.
			if side.over > worst and side.over > 1 then
				worst, edge = side.over, side.name
			end
		end
		if worst > 1 then
			local v: Violation = {
				kind = "outside-parent",
				node = path,
				class = node.class,
				boundary = boundaryPath,
				edge = edge,
				overhang = worst,
				text = if type(props.text) == "string"
					then props.text
					elseif type(props.label) == "string" then props.label
					else nil,
			}
			if waiverFor(book, v) == nil then
				table.insert(out, v)
			end
		end
	end
	return out
end

function overflow_guard.describe(v: Violation): string
	if v.kind == "zero-box" then
		return string.format(
			'zero-box: %s [%s] "%s" is visible with zero %s',
			v.node,
			v.class,
			tostring(v.text),
			v.edge
		)
	end
	local quoted = if v.text ~= nil and v.text ~= "" then string.format(' "%s"', v.text) else ""
	local capped = if v.waiver ~= nil then string.format(" [waiver %s]", v.waiver) else ""
	return string.format(
		"outside-parent: %s [%s]%s overflows %s past its %s edge by %.1fpx%s",
		v.node,
		v.class,
		quoted,
		v.boundary,
		v.edge,
		v.overhang,
		capped
	)
end

--[[ THE RED. `label` names the fixture and the state it was in, because the
	sweep drives the same surface through several and a path alone cannot tell a
	reader which tap produced it. ]]
function overflow_guard.assertContained(adapter: any, label: string?, ledger: Ledger?)
	local found = overflow_guard.violations(adapter, ledger)
	if #found == 0 then
		return
	end
	local lines: { string } = {}
	for i, v in found do
		if i > 12 then
			table.insert(lines, string.format("   ...and %d more", #found - 12))
			break
		end
		table.insert(lines, "   " .. overflow_guard.describe(v))
	end
	error(
		string.format(
			"containment invariant: %d violation(s)%s\n%s",
			#found,
			if label ~= nil then " in " .. label else "",
			table.concat(lines, "\n")
		),
		3
	)
end

return overflow_guard
