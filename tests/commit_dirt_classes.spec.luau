--!strict
--[[ THE COMMIT'S DIRTY SET IS NOT THE BUILD'S (wicked-fast T5b).

	After T5 the six position-independent walks stop at a moved subtree — but not at
	the root itself, because `skip` refuses ANY path in `nodeDirty` and a plate root
	wrote `offsetX` this tick. So the floor was 253 visits x 6 walks, and every one
	of those visits is a walk re-deriving an answer from inputs that did not change.

	`nodeDirty` is the right set for `layout_node.build`: a node whose `offsetX`
	changed must be rebuilt, and the P3 store's `dirty` argument is what makes that
	happen. It is the WRONG set for four of the eight commit walks, and the audit
	below is the proof: `textScale`, `padding`, `textVerdicts` and `scrollRegions`
	read no arrange-class prop at all.

	SO THERE ARE TWO SETS, NOT ONE NARROWED ONE. Build-side: every class, as today.
	Commit-side: everything except the SEVEN pure-arrange props (`anchor`, `offsetX`,
	`offsetY`, `alignH`, `alignV`, `lineAlign`, `distribute`), keeping `hidden` —
	which is arrange-class but is read by `harvest`, `visible` and `hitRects`.

	AND THE THREE HIDDEN-READING WALKS KEEP THE ALL-CLASSES SET. Not because their
	answer depends on a position — `harvest`'s and `visible`'s do not, and they keep
	T5's `moveBlind` claim and T5's numbers — but because narrowing a walk's SET is
	only sound if the walk cannot read anything the narrowing threw away, and
	`hiddenRoots` is DERIVED state `harvest` itself maintains. Keeping those three on
	`nodeDirty` also preserves the invariant `harvest`'s own header states: `visible`
	and `hitRects` share its `skip` and only ever add reasons NOT to prune, so a node
	the harvest reached is a node they reach. Give one of the three a different set
	and that stops being true.

	KEEPING `hidden` IN THE COMMIT-SIDE SET IS CONSERVATISM, NOT A NECESSITY, AND
	SAYING SO IS THE HONEST VERSION (review round 1, m3). `commitDirty` is consulted
	by exactly one branch — `skip(…, arrangeBlind = true)` — and its only four callers
	are the four walks below, none of which reads `hidden`. Dropping it TODAY would
	cost extra pruning of a subtree whose hidden verdict those four do not carry, and
	the report's own mutation (b) shows exactly that: it reddens counter pins and the
	source round trip, never the oracle. It stays so that a fifth walk which DOES read
	`hidden` can be promoted to `arrangeBlind` without re-deriving the set, and
	because narrowing it further is a behaviour question for the framework's owner
	rather than a free win. The `hide` cases below pin the behaviour either way.

	WHICH IS WHY `skip` TAKES TWO CLAIMS AND NOT ONE (deviation from the task brief,
	recorded rather than silent). The brief fused them — the four narrow walks would
	pass `skip(node, true)` and `harvest`/`visible` would "give it back" and revert to
	`skip(node)`. MEASURED at `a9607e17` with exactly that edit: `harvest` goes to
	**1503** on a pure tick, not to the 253 the brief's own pins in this file assert.
	`moveBlind` is what prunes a translated subtree's CLONES (which are not in
	`nodeDirty` at all), so taking it away from `harvest` and `visible` would have
	deleted the whole of T5 for those two walks. The two claims are therefore a
	LADDER: `moveBlind` = "my output cannot read a position", `arrangeBlind` =
	"...nor a pure PLACEMENT prop", and only the second selects the commit-side set.

	WHAT MAKES THE FOUR REACH 3 AND NOT 253: T4 stamps `moveOnly`/`prev` on the
	translate ROOT's entry as well as its descendants (`solver.luau`, "THE ROOT IS A
	MOVE TOO, AND SAYS SO — ... Inert until T5b takes it out of `nodeDirty`"). That
	stamp was inert until this task, because `skip` tested `nodeDirty` first; once the
	plate roots leave the commit-side set, `skip(root, true, true)` sees a `moveOnly`
	entry whose `prev` is what it last committed and stops there. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")
local fs = require("@lune/fs")
local schema = require("../src/blueprint_schema")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local PLATES = scene.PLATES
local CASTERS = PLATES // scene.CASTER_EVERY -- 50
local MOUNTED = PLATES * scene.NODES_PER_PLATE + 2 + 1 -- 1503
local DIRTY_TICK = 3 + PLATES -- 253, the all-classes closure T5 left them at
local DIRTY_CASTS = DIRTY_TICK + CASTERS -- 303
local ARRANGE_BLIND = { "textScale", "padding", "textVerdicts", "scrollRegions" }
-- Screen, Canvas, the ForEach region: the three nodes whose entries this solve
-- rewrote for a reason that is not a pure-arrange prop write. The Screen and the
-- Canvas are ARRANGED (`lastArranged` is 252 = 250 roots + these two) so their
-- entries are new tables with no `moveOnly` stamp, and the region owns no entry at
-- all and has 250 children, so `probeEntry` can borrow nothing and never prunes.
local CLEAN_FLOOR = 3
-- ...and on a caster tick each caster plate is back: a `width` write on its `Cast`
-- box is `dirty = { "measure" }`, which the narrowing never drops, so the closure
-- holds the caster ROOT and the `Cast` leaf. `Row` and `Hp` are the translate roots
-- T5 already prunes (`tests/commit_translate.spec`'s `RECTPASS_CASTS` derivation).
local CASTER_FLOOR = CLEAN_FLOOR + CASTERS * 2 -- 103

--[[ THE AUDIT'S SOURCE OF TRUTH. One row per walk; `true` means "this walk reads a
	prop whose declared dirty class is `arrange`", which is what disqualifies it from
	the commit-side set. It is re-derived from the walk bodies, and it is asserted
	against BOTH the source (the scan below, so the claim about the FILE is
	executable) and the behaviour (the driver below, so the claim about the SET is):

	| walk          | reads an arrange-class prop? | which                                   |
	|---------------|------------------------------|-----------------------------------------|
	| harvest       | YES                          | `authoredHidden[path]` / `entry.hidden`  |
	| textScale     | no                           | `props.textSize` (measure), `class`, `metrics`, `entry.textFacts.size` |
	| padding       | no                           | `class`, `props.padding` (measure), `metrics` |
	| textVerdicts  | no                           | `class`, `#children`, the compact form, `entry.compact`, `entry.textFacts.wraps` |
	| visible       | YES                          | `nextHidden` (= `hiddenRoots`), `hiddenFlips`, `solverHidden`, `paintHeld`, `pathNodes` |
	| scrollRegions | no                           | `class == "ScrollView"`, `props.axis/padding/indicators/autoscroll`, `entry.*` |
	| hitRects      | YES                          | `nextHidden`, `hiddenFlips`, plus `entry.rect` (it must see a move anyway) |
	| rect_pass     | n/a — it IS the position pass | `entry.rect`                           |
]]
local WALK_READS_ARRANGE: { [string]: boolean } = {
	harvest = true,
	textScale = false,
	padding = false,
	textVerdicts = false,
	visible = true,
	hitRects = true,
	scrollRegions = false,
	rectPass = true,
}

describe("T5b: a pure-arrange write does not dirty the commit", function()
	it("the four arrange-blind walks stop at the top of the surface", function()
		local s = scene.new()
		s.tick(3, 2)
		s.tick(3, 2)
		local by = s.stats().lastCommitVisitsByWalk
		for _, name in ARRANGE_BLIND do
			expect(`{name}={by[name]}`).toBe(`{name}={CLEAN_FLOOR}`)
		end
		s.dispose()
	end)

	it("...and the three that read `hidden` are UNCHANGED from T5", function()
		local s = scene.new()
		s.tick(3, 2)
		s.tick(3, 2)
		local by = s.stats().lastCommitVisitsByWalk
		expect(`harvest={by.harvest} visible={by.visible}`).toBe(`harvest={DIRTY_TICK} visible={DIRTY_TICK}`)
		expect(`hitRects={by.hitRects}`).toBe(`hitRects={MOUNTED}`)
		-- `rect_pass` is unchanged too: it never asked `skip` at all, it stops AT a
		-- translate root and emits the solver's run (T5/N1).
		expect(`rectPass={by.rectPass}`).toBe(`rectPass={DIRTY_TICK}`)
		s.dispose()
	end)

	it("a MEASURE-class write still dirties the commit (the narrowing is not a hole)", function()
		local s = scene.new()
		s.tickWithCasts(3, 2)
		s.tickWithCasts(3, 2)
		local by = s.stats().lastCommitVisitsByWalk
		-- READ OFF THE RUN: the 50 caster roots and their `Cast` boxes are back in the
		-- set, because a width write is `dirty = { "measure" }` and is never dropped.
		-- Pinned EXACTLY rather than as `>= CASTERS`: a bound could not tell 103 from
		-- 303, and 303 is precisely the number this task exists to move.
		for _, name in ARRANGE_BLIND do
			expect(`{name}={by[name]}`).toBe(`{name}={CASTER_FLOOR}`)
		end
		-- ...and the all-classes three still pay the whole closure
		expect(`harvest={by.harvest} visible={by.visible}`).toBe(`harvest={DIRTY_CASTS} visible={DIRTY_CASTS}`)
		s.dispose()
	end)

	it("a placement prop on a TEXT LEAF prunes the leaf, and the leaf really moved", function()
		--[[ THE SHAPE THE NARROWING IS LOAD-BEARING FOR (review round 1, I1), on the
			fixture the oracle uses. `Lvl` is a Text — one of the three classes the four
			narrowed walks write for — and `lineAlign` under its HStack parent is a
			pure-arrange prop authored on the leaf ITSELF. Before T5b that leaf was in
			`nodeDirty` and every walk descended to it; after T5b it is a childless
			translate root and the four stop above it while `harvest` still visits it.

			READ OFF THE RUN. 5 = Screen, Canvas, the region, the plate root and `Row`
			(the ancestors of the dirty leaf, all re-arranged), with `Lvl` pruned;
			`harvest` is 6 — the same five plus `Lvl`. The other 249 plates are
			untouched this frame and prune on plain entry identity. ]]
		local s = scene.new({ plates = 20 })
		s.tick(3, 2)
		s.tick(3, 2)
		local before = s.snapshot()
		s.nudgeLabel(7, "end")
		local by = s.stats().lastCommitVisitsByWalk
		-- NON-VACUITY FIRST: a drive with no room to move makes every line below
		-- meaningless, and `Name` (61x16 in a 16px row) is exactly that drive
		expect(`moved={before ~= s.snapshot()}`).toBe("moved=true")
		for _, name in ARRANGE_BLIND do
			expect(`{name}={by[name]}`).toBe(`{name}=5`)
		end
		expect(`harvest={by.harvest} visible={by.visible}`).toBe("harvest=6 visible=6")
		-- ...and the leaf the four pruned is the one that moved
		for _, name in ARRANGE_BLIND do
			expect(`{name}<harvest={by[name] < by.harvest}`).toBe(`{name}<harvest=true`)
		end
		s.dispose()
	end)

	it("a `hidden` flip is seen by every walk, at every device view", function()
		for _, view in device_views.VIEWS do
			local s = scene.new({ viewport = { x = 0, y = 0, w = view.w, h = view.h } })
			s.tick(3, 2)
			s.tick(3, 2)
			s.hide(11, true)
			local by = s.stats().lastCommitVisitsByWalk
			--[[ `hidden` is arrange-class and is KEPT, so the flip is in the COMMIT's set
				too and all seven descend past `CLEAN_FLOOR` to plate 11. The four
				arrange-blind walks are the load-bearing half of this assertion: they are
				the only ones answered against the narrowed set, so they are the only ones
				a `hidden` dropped from it could silently strand. ]]
			for _, name in ARRANGE_BLIND do
				expect(`{view.id}:{name}>{CLEAN_FLOOR}={by[name] > CLEAN_FLOOR}`).toBe(
					`{view.id}:{name}>{CLEAN_FLOOR}=true`
				)
			end
			expect(`{view.id}:harvest={by.harvest > CLEAN_FLOOR} visible={by.visible > CLEAN_FLOOR}`).toBe(
				`{view.id}:harvest=true visible=true`
			)
			expect(`{view.id}:{s.adapter.liveNodes()["/S/Canvas/Plates/[p11]/Plate"].visible}`).toBe(`{view.id}:false`)
			s.hide(11, false)
			expect(`{view.id}:back={s.adapter.liveNodes()["/S/Canvas/Plates/[p11]/Plate"].visible}`).toBe(
				`{view.id}:back=true`
			)
			s.dispose()
		end
	end)
end)

--[[ THE PROP -> WALK READ AUDIT, HALF ONE: THE SOURCE.

	The table above is a comment, and a comment cannot be executed. This scan makes
	its claim about the FILE executable, exactly as `tests/translate_arm.spec.luau`'s
	`stampsAfterLiteral` does for the solver's entry literal: slice each walk's body
	out of `src/render/commit_walks.luau` and assert which tokens it contains.

	TWO CLAIMS, AND THEY LICENSE DIFFERENT HALVES OF THE NARROWING:

	  1. NO walk body mentions any of the SEVEN pure-arrange props. That is what
	     licenses dropping them from the commit-side set at all — a walk cannot read
	     what it does not name.
	  2. The `hidden` channel — `authoredHidden`, `hiddenRoots`, `nextHidden`,
	     `hiddenFlips`, `solverHidden`, `entry.hidden` — appears in exactly the three
	     walks marked `true`. That is what licenses KEEPING `hidden`, and it is what
	     turns a fourth walk quietly learning to read it into a red line.

	The scan is a pure function of a source string, so it is fed a fabricated body
	with the defect in it (the negative control below): a scan that cannot see the
	defect would pass the real case for the wrong reason forever. ]]
local WALK_SOURCE = fs.readFile("src/render/commit_walks.luau")

--[[ the eight walk bodies, sliced from the head of `local function <name>(` to the
	head of the next TOP-LEVEL `local function` (one tab; the nested `walk`/`push*`
	closures are two and are part of their own body).

	COMMENTS ARE STRIPPED FIRST, and that is not tidiness. `visible`'s doc block
	names `solverHidden` and sits between `textVerdicts`'s body and `visible`'s own,
	so scanning raw text reported `textVerdicts` as a `hidden` reader — a prose
	mention is not a read, and an audit that cannot tell them apart would either
	fail on a comment or be silenced by deleting one. ]]
local function walkBodies(source: string): { [string]: string }
	local stripped = source:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
	local out: { [string]: string } = {}
	local starts: { { name: string, head: number, body: number } } = {}
	local at = 1
	while true do
		local s, e, name = string.find(stripped, "\n\tlocal function ([%a_][%w_]*)%(", at)
		if s == nil then
			break
		end
		table.insert(starts, { name = name :: string, head = s :: number, body = e :: number })
		at = (e :: number) + 1
	end
	for i, entry in starts do
		local stop = if starts[i + 1] ~= nil then starts[i + 1].head - 1 else #stripped
		-- from the head, so the SIGNATURE is part of the body: `visible(rootNode,
		-- rects, nextHidden)` names its hidden channel there and nowhere else
		out[entry.name] = string.sub(stripped, entry.head, stop)
	end
	return out
end

-- the seven props the commit-side set drops, and the `hidden` channel it keeps
local PURE_ARRANGE_ORDER = { "anchor", "offsetX", "offsetY", "alignH", "alignV", "lineAlign", "distribute" }
local HIDDEN_TOKENS = { "authoredHidden", "hiddenRoots", "nextHidden", "hiddenFlips", "solverHidden", "%.hidden" }
local AUDITED_WALKS = { "harvest", "textScale", "padding", "textVerdicts", "visible", "hitRects", "scrollRegions" }

local function readsHidden(body: string): boolean
	for _, token in HIDDEN_TOKENS do
		if string.find(body, token) ~= nil then
			return true
		end
	end
	return false
end

local function readsPlacement(body: string): string?
	for _, prop in PURE_ARRANGE_ORDER do
		-- every placement prop reaches a walk the only way a prop can — off
		-- `node.props` — so the token is the field read, not the bare name
		if string.find(body, `props%.{prop}`) ~= nil or string.find(body, `props and node%.props%.{prop}`) ~= nil then
			return prop
		end
	end
	return nil
end

describe("T5b audit, half one: the walk bodies, read out of the source", function()
	it("the slicer finds all SEVEN walk bodies that live in this module", function()
		-- seven, not eight: `rect_pass` is its own module and asks `skip` nothing, as
		-- `WALK_READS_ARRANGE`'s own `rectPass` row concedes
		expect(`audited={#AUDITED_WALKS}`).toBe("audited=7")
		local bodies = walkBodies(WALK_SOURCE)
		for _, name in AUDITED_WALKS do
			expect(`{name}-sliced={bodies[name] ~= nil and #bodies[name] > 400}`).toBe(`{name}-sliced=true`)
		end
	end)

	it("NO walk reads any of the seven props the commit-side set drops", function()
		local bodies = walkBodies(WALK_SOURCE)
		for _, name in AUDITED_WALKS do
			expect(`{name}-placement={readsPlacement(bodies[name])}`).toBe(`{name}-placement=nil`)
		end
	end)

	it("the `hidden` channel appears in exactly the three walks the table marks true", function()
		local bodies = walkBodies(WALK_SOURCE)
		for _, name in AUDITED_WALKS do
			expect(`{name}-hidden={readsHidden(bodies[name])}`).toBe(`{name}-hidden={WALK_READS_ARRANGE[name]}`)
		end
	end)

	it("NEGATIVE CONTROL: the scan sees both defects it exists to catch", function()
		local fake = table.concat({
			"",
			"\t-- a COMMENT naming authoredHidden and node.props.offsetX, which is not a read",
			"\tlocal function padding(rootNode: any, metrics: any)",
			"\t\tlocal want = authoredHidden[node.path]",
			"\t\tlocal off = node.props.offsetX",
			"\tlocal function textScale(rootNode: any)",
			"\t\tlocal size = node.props.textSize",
			"\tlocal function done()",
		}, "\n")
		local bodies = walkBodies(fake)
		expect(`padding-hidden={readsHidden(bodies.padding)}`).toBe("padding-hidden=true")
		expect(`padding-placement={readsPlacement(bodies.padding)}`).toBe("padding-placement=offsetX")
		expect(`textScale-hidden={readsHidden(bodies.textScale)}`).toBe("textScale-hidden=false")
		expect(`textScale-placement={readsPlacement(bodies.textScale)}`).toBe("textScale-placement=nil")
	end)
end)

--[[ ...AND THE SET THE RENDERER ACTUALLY DROPS, ROUND-TRIPPED AGAINST THE SCHEMA.

	`PURE_ARRANGE_PROPS` is a literal in `renderer.luau`, and a literal drifts. The
	rule it has to satisfy is one sentence: it is EVERY prop the schema declares
	arrange-only, MINUS the ones a commit walk reads — which the scan above says is
	exactly `hidden`. Both halves are derived here, so a ninth arrange prop added to
	the schema, or a walk that starts reading one, moves this line rather than
	silently widening what the commit stops seeing. ]]
local RENDERER_SOURCE = fs.readFile("src/render/renderer.luau")

local function rendererDrops(): { string }
	local literal = string.match(RENDERER_SOURCE, "local PURE_ARRANGE_PROPS[^\n]*=%s*{(.-)}")
	assert(literal ~= nil, "PURE_ARRANGE_PROPS literal not found in src/render/renderer.luau")
	local out: { string } = {}
	for name in string.gmatch(literal :: string, "([%a_][%w_]*)%s*=%s*true") do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

describe("T5b audit, half two: what the renderer drops is the schema minus what a walk reads", function()
	it("the schema's arrange-only props are the eight this task reasoned about", function()
		local arrangeOnly: { string } = {}
		for _, props in schema.propDirty() do
			for prop, classes in props do
				if #classes == 1 and classes[1] == "arrange" then
					arrangeOnly[#arrangeOnly + 1] = prop
				end
			end
		end
		-- `propDirty` is per class, so a shared prop appears once per class that
		-- declares it; de-duplicate before comparing
		local seen: { [string]: boolean } = {}
		local unique: { string } = {}
		for _, prop in arrangeOnly do
			if not seen[prop] then
				seen[prop] = true
				table.insert(unique, prop)
			end
		end
		table.sort(unique)
		expect(table.concat(unique, ",")).toBe("alignH,alignV,anchor,distribute,hidden,lineAlign,offsetX,offsetY")
	end)

	it("the renderer drops exactly those minus `hidden`", function()
		expect(table.concat(rendererDrops(), ",")).toBe("alignH,alignV,anchor,distribute,lineAlign,offsetX,offsetY")
	end)

	it("...and `hidden` is the one it keeps BECAUSE a walk reads it", function()
		local bodies = walkBodies(WALK_SOURCE)
		local readers: { string } = {}
		for _, name in AUDITED_WALKS do
			if readsHidden(bodies[name]) then
				table.insert(readers, name)
			end
		end
		table.sort(readers)
		expect(`hidden-readers={table.concat(readers, ",")}`).toBe("hidden-readers=harvest,hitRects,visible")
		for _, dropped in rendererDrops() do
			expect(`dropped-{dropped}-is-hidden={dropped == "hidden"}`).toBe(`dropped-{dropped}-is-hidden=false`)
		end
	end)
end)

--[[ THE PROP -> WALK READ AUDIT, HALF TWO: THE DRIVER.

	The scan above proves the walk bodies do not NAME a placement prop. This proves
	the commit-side SET behaves as if that is true: for every one of the seven props,
	on the parent kind that actually reads it, a drive leaves the four arrange-blind
	walks at their clean floor while the all-classes walks descend — and the adapter
	is told the same thing a `commitScope = false` commit would have told it.

	THE PARENT MAP IS T3's (`tests/layout_prop_dirt.spec.luau`'s `PARENT_FOR` /
	`CLASS_FOR_KIND`), for the same reason it exists there: `alignH` under a VStack
	is INERT, and a drive nothing reads makes every assertion below vacuous. That
	audit answers "is this prop unread by MEASURE?"; this one answers "is this WALK
	unread by an arrange-class prop?", which is the different question the
	commit-side set depends on. The two tables are asserted against each other in
	`layout_prop_dirt`'s own round trip against the schema, and against this file's
	`rendererDrops()` above.

	THE FIXTURE GIVES ALL FOUR WALKS REAL WORK. A driver whose surface has no Text,
	no Button and no ScrollView would report a clean floor for walks that had nothing
	to do in the first place — so each kid carries a padded, sized Text, a Button
	with a compact form and a ScrollView with overflowing content, and the CONTROL
	case below drives a MEASURE-class prop on the SAME fixture and requires every one
	of the four to rise above the floor. ]]
local PARENT_FOR: { [string]: string } = {
	anchor = "anchor",
	offsetX = "anchor",
	offsetY = "anchor",
	alignH = "zstack",
	alignV = "zstack",
	lineAlign = "hstack",
	distribute = "vstack",
}
local CLASS_FOR_KIND: { [string]: (props: any) -> any } = {
	anchor = UI.Anchor,
	zstack = UI.ZStack,
	hstack = UI.HStack,
	vstack = UI.VStack,
}
-- `distribute` is authored on the parent that distributes, never on a child
local DRIVEN_ON_PARENT: { [string]: boolean } = { distribute = true }

local function px(n: number): any
	return { type = "fixed", px = n }
end

-- read off the prop's own spec, so an enum that grows cannot leave this audit
-- driving a value that no longer exists
--[[ ...AND `stretch` IS EXCLUDED, WHICH IS A FINDING RATHER THAN A CONVENIENCE.
	`lineAlign = "stretch"` is the one value of the seven props that changes the
	driven node's SIZE, so the solver cannot translate it and the entry it writes
	carries no `moveOnly` stamp. That case is driven on its own below, and it is
	worth its own case: it is the proof that the narrowing lifts only `skip`'s dirty
	VETO and never entry identity. Here the pair is a pure PLACEMENT move. ]]
local function valuesFor(prop: string, keepStretch: boolean?): (any, any)
	local spec = (schema.forClass("VStack") :: any).props[prop]
	if spec.enum ~= nil then
		local last = spec.enum[#spec.enum]
		if last == "stretch" and keepStretch ~= true then
			last = spec.enum[#spec.enum - 1]
		end
		return spec.enum[1], last
	end
	for _, ty in spec.types do
		if ty == "number" then
			return 0, 23
		end
	end
	error(`commit_dirt_classes: no drivable value for {prop}`, 0)
end

type World = { by: { [string]: number }, shot: string, dispose: () -> () }

--[[ TWO SHAPES, AND THE SECOND ONE IS WHAT LICENSES THE AUDIT (review round 1, I1).

	`"container"` binds the driven prop to a `UI.VStack` that CARRIES the Text,
	Button and ScrollView. That was the whole audit in the first round, and it has a
	hole: those three classes are the ONLY ones the four arrange-blind walks ever
	write for (`commit_walks.luau` — `textScale` writes where a size resolves,
	`padding` for `Button`/`Text`, `textVerdicts` for a label-driven `Text`/`Button`,
	`scrollRegions` for `ScrollView`). A container arm therefore never drives a
	placement prop on a node whose walk OUTPUT it can observe, and the review proved
	the consequence: an aliased `props.offsetX` read inside `textScale`'s own write
	left all twenty cases green.

	`"leaf"` binds the same prop directly onto each of those three leaves, under the
	same parent kind `PARENT_FOR` says reads it. `distribute` is the one prop with no
	leaf spelling — it is authored on the container that distributes — so its leaf
	arm binds it on the parent and makes the three leaves its CHILDREN, which is the
	same question asked the only way that prop can be asked it. ]]
local function driveWorld(
	prop: string,
	control: boolean,
	commitScope: boolean,
	shape: string,
	keepStretch: boolean?
): World
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
	-- CONTROL: the same mount, the same drive, a `dirty = { "measure" }` prop
	-- instead of the arrange-only one. Without it a clean floor here could be a
	-- floor this fixture reports for anything at all.
	local driven = if control then "width" else prop
	local a: any, b: any = px(40), px(61)
	if not control then
		a, b = valuesFor(prop, keepStretch)
	end
	local sig = core:signal(a)
	local onParent = DRIVEN_ON_PARENT[prop] == true and not control
	-- the three classes the four arrange-blind walks write for, and nothing else
	local function leaf(kind: string, id: string, bind: boolean): any
		local props: any
		if kind == "Text" then
			props = { id = id, text = "a label", textSize = 14, padding = 4 }
		elseif kind == "Button" then
			props = { id = id, label = "Press me", compactLabel = { text = "P" } }
		else
			props = {
				id = id,
				axis = "y",
				width = px(60),
				height = px(30),
				children = { UI.Box({ id = "Tall", width = px(50), height = px(400) }) },
			}
		end
		if bind then
			props[driven] = sig
		end
		return (if kind == "Text" then UI.Text elseif kind == "Button" then UI.Button else UI.ScrollView)(props)
	end
	local function leaves(bind: boolean): { any }
		return { leaf("Text", "T", bind), leaf("Button", "B", bind), leaf("ScrollView", "SV", bind) }
	end
	local function kid(id: string, bind: boolean): any
		local props: any = { id = id, width = px(120), height = px(90), children = leaves(false) }
		if bind then
			props[driven] = sig
		end
		return UI.VStack(props)
	end
	local parentProps: any
	if shape == "leaf" then
		-- the three leaves ARE the parent's children, so the prop the parent reads is
		-- read ABOUT a Text, a Button and a ScrollView
		parentProps = {
			id = "P",
			width = px(600),
			height = { type = "fill", weight = 1 },
			children = leaves(control or not onParent),
		}
	else
		parentProps = {
			id = "P",
			width = px(600),
			height = { type = "fill", weight = 1 },
			children = { kid("A", control or not onParent), kid("B", false) },
		}
	end
	if onParent then
		parentProps[prop] = sig
	end
	local root =
		mountLib.mount(core, UI.Screen({ id = "S", children = { CLASS_FOR_KIND[PARENT_FOR[prop]](parentProps) } }))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = true,
		measureReuse = true,
		layoutNodeReuse = true,
		commitScope = commitScope,
	})
	controller.initialRender()
	-- two warm drives: `initialRender` is not a reuse solve, and the prune compares
	-- against what the PREVIOUS commit recorded, so the pinned drive is the third
	sig:set(b)
	controller.refresh()
	sig:set(a)
	controller.refresh()
	sig:set(b)
	controller.refresh()
	local by = {}
	for name, n in (controller.stats() :: any).lastCommitVisitsByWalk do
		by[name] = n
	end
	--[[ EVERY adapter prop, BY VALUE to the bottom, not a hand-picked few. The first
		round listed `textSize`/`padding`/`label`/`textWrapped` by name and serialised
		the padding as a BOOLEAN, so two different insets compared equal; and a walk
		writes more than those four (`textFont`, `icon`, `compactLabel`). A dump that
		does not carry what a walk writes cannot see that walk skip a write it owed. ]]
	local function ser(v: any, depth: number): string
		if type(v) ~= "table" then
			return tostring(v)
		end
		if depth <= 0 then
			return "…"
		end
		local inner = {}
		for k, item in v do
			table.insert(inner, `{tostring(k)}={ser(item, depth - 1)}`)
		end
		table.sort(inner)
		return `\{{table.concat(inner, ",")}\}`
	end
	local out: { string } = {}
	for path, node in adapter.liveNodes() do
		local r, region = node.rect, node.scrollRegion
		local props = {}
		for k, v in node.props or {} do
			table.insert(props, `{k}={ser(v, 6)}`)
		end
		table.sort(props)
		table.insert(
			out,
			`{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|vis={tostring(node.visible)}`
				.. `|canvas={if region then `{region.contentW},{region.contentH}` else "-"}`
				.. `|{table.concat(props, ",")}`
		)
	end
	table.sort(out)
	return {
		by = by,
		shot = table.concat(out, "\n"),
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

describe("T5b audit, half three: driving each dropped prop leaves the four walks at the floor", function()
	--[[ THE FLOOR IS PER PROP AND PER SHAPE, AND EVERY NUMBER IS READ OFF THE RUN,
		because the SOLVER's answer differs and the commit is downstream of it.

		LEAF SHAPE — the prop on a Text, a Button and a ScrollView under the parent
		that reads it. This is the arm the audit is licensed by (review round 1, I1):

		  | prop                     | four | harvest | why |
		  | anchor/offsetX/offsetY   |   3  |    5    | the Text and the Button are CHILDLESS TRANSLATE ROOTS — same size, new origin, so `arrange` stamps `moveOnly`/`prev` on their own entries and `translateDescendants` returns immediately, which is why `lastTranslated` reads 0 and the stamp is there anyway. The four prune both; `harvest` keeps the all-classes set and visits them. That GAP is this task |
		  | lineAlign (start -> end) |   3  |    5    | the same, one axis over |
		  | alignH/alignV (ZStack)   |   5  |    5    | no translate at all: a ZStack re-arranges its children, so every entry is fresh and ENTRY IDENTITY refuses the prune for both sets. The narrowing changes nothing here and the pin says so rather than hiding it |
		  | distribute (on the parent) | 3  |    3    | the dirty node is the PARENT, arranged either way; its leaves are clean-and-moved, so T5's `moveBlind` already prunes them for `harvest` too |

		THE SCROLLVIEW IS NEVER PRUNED ON THIS ARM, AND THAT IS A FINDING RATHER THAN
		A GAP IN THE FLOOR. `literalIsWholeEntry` (`solver.luau`) refuses the `scroll`
		and `composition` kinds, so a ScrollView can never BE a translate root: it is
		arranged, its entry is fresh, and every walk visits it. So the 3 above is
		Screen + parent + ScrollView, and `scrollRegions` sees a moved scroll host on
		every frame it moves — which is exactly what it must do, since its `hostW`/
		`hostH` come off that entry.

		CONTAINER SHAPE — the prop on a VStack that CARRIES the three leaves. Kept
		because it is a real authoring shape, but it is NOT the licence: the walks
		write nothing for a VStack.

		  | prop | four | harvest |
		  | anchor/offsetX/offsetY/lineAlign | 2 | 3 |
		  | alignH/alignV | 4 | 4 |
		  | distribute | 2 | 2 | ]]
	local FLOOR: { [string]: { [string]: number } } = {
		leaf = { anchor = 3, offsetX = 3, offsetY = 3, lineAlign = 3, alignH = 5, alignV = 5, distribute = 3 },
		container = { anchor = 2, offsetX = 2, offsetY = 2, lineAlign = 2, alignH = 4, alignV = 4, distribute = 2 },
	}
	-- the props whose drive the solver answers with the translate arm ON A NODE THE
	-- ALL-CLASSES SET STILL HOLDS, which is where the commit-side set is the only
	-- thing standing between the four walks and a visit
	local BELOW_HARVEST: { [string]: { [string]: boolean } } = {
		leaf = { anchor = true, offsetX = true, offsetY = true, lineAlign = true },
		container = { anchor = true, offsetX = true, offsetY = true, lineAlign = true },
	}
	local SHAPES = { "leaf", "container" }

	for _, shape in SHAPES do
		it(`{shape}: each of the seven, on the parent kind that reads it`, function()
			for prop in PARENT_FOR do
				local pruned = driveWorld(prop, false, true, shape)
				local unpruned = driveWorld(prop, false, false, shape)
				local at = `{shape}/{prop}`
				-- (1) NON-VACUITY: the fixture painted something
				expect(`{at}:painted={#pruned.shot > 400}`).toBe(`{at}:painted=true`)
				-- (2) THE CLAIM: the four arrange-blind walks are at this prop's floor
				for _, name in ARRANGE_BLIND do
					expect(`{at}:{name}={pruned.by[name]}`).toBe(`{at}:{name}={FLOOR[shape][prop]}`)
				end
				-- (3) ...and where the solver translated, they are STRICTLY below the walk
				-- that kept the all-classes set. That inequality is the narrowing itself.
				for _, name in ARRANGE_BLIND do
					local below = pruned.by[name] < pruned.by.harvest
					expect(`{at}:{name}<harvest={below}`).toBe(
						`{at}:{name}<harvest={BELOW_HARVEST[shape][prop] == true}`
					)
				end
				-- (4) ...and the adapter was told exactly what an UNPRUNED commit would
				-- have told it, which is the only thing a prune is allowed to change.
				-- On the LEAF arm this is the assertion the review's aliased-read
				-- mutation has to break: the pruned commit skips the Text whose own
				-- placement prop moved, so a walk that read one would write a different
				-- size there and nowhere else.
				if pruned.shot ~= unpruned.shot then
					error(`{at}: the pruned commit told the adapter something else`, 0)
				end
				pruned.dispose()
				unpruned.dispose()
			end
		end)
	end

	it("a RESIZE is still seen: `lineAlign = stretch` is not a placement move", function()
		--[[ THE SOUNDNESS CASE. Dropping a prop from the commit-side set lifts exactly
			one thing — `skip`'s "this path is dirty" veto — and never entry identity.
			`stretch` is the one value of the seven props that changes the driven node's
			SIZE, so the solver cannot translate it: the entry it writes is a fresh table
			with no `moveOnly` stamp, and all four walks descend to it even though
			`lineAlign` is in `PURE_ARRANGE_PROPS`. Without this case the audit above
			could be read as "an arrange write is invisible to the commit", which is the
			claim this task does NOT make. Driven on the LEAF arm, so the node that
			resizes is one the four walks write for. ]]
		local w = driveWorld("lineAlign", false, true, "leaf", true)
		local unpruned = driveWorld("lineAlign", false, false, "leaf", true)
		for _, name in ARRANGE_BLIND do
			expect(`stretch:{name}={w.by[name]}`).toBe(`stretch:{name}={w.by.harvest}`)
			expect(`stretch:{name}>{FLOOR.leaf.lineAlign}={w.by[name] > FLOOR.leaf.lineAlign}`).toBe(
				`stretch:{name}>{FLOOR.leaf.lineAlign}=true`
			)
		end
		if w.shot ~= unpruned.shot then
			error("lineAlign=stretch: the pruned commit told the adapter something else", 0)
		end
		w.dispose()
		unpruned.dispose()
	end)

	it("CONTROL: a MEASURE-class write on the same fixtures moves every one of the four", function()
		--[[ The floors above are only evidence if these fixtures can produce a
			non-floor. Same mounts, same drive, `width` instead of the arrange-only prop
			— and `width` is `dirty = { "measure" }`, which the commit-side set never
			drops. Run on BOTH shapes, because both carry a floor. ]]
		for _, shape in SHAPES do
			for prop in PARENT_FOR do
				local w = driveWorld(prop, true, true, shape)
				local floor = FLOOR[shape][prop]
				for _, name in ARRANGE_BLIND do
					expect(`{shape}/{prop}-control:{name}>{floor}={w.by[name] > floor}`).toBe(
						`{shape}/{prop}-control:{name}>{floor}=true`
					)
				end
				w.dispose()
			end
		end
	end)

	it("...and the drive is LIVE on BOTH shapes: the seven props each move the geometry", function()
		--[[ The `alignH`-under-a-VStack trap, from T3's own audit: a prop the parent
			does not read produces identical geometry at both ends of the drive, and
			every differential above then compares a thing to itself. Taken on a FORCED
			FULL SOLVE (no incremental, no memo, so there is no prune of any kind in
			play) and on the SAME fixture the assertions above use, so liveness is a
			fact about the fixture rather than about the fix. ]]
		for _, shape in SHAPES do
			for prop in PARENT_FOR do
				local before = driveWorld(prop, false, true, shape, false)
				local after = driveWorld(prop, false, true, shape, false)
				-- both worlds end on value `b`, so they must agree; the liveness question
				-- is whether value `a` and value `b` differ, taken below
				expect(`{shape}/{prop}:deterministic={before.shot == after.shot}`).toBe(
					`{shape}/{prop}:deterministic=true`
				)
				before.dispose()
				after.dispose()
			end
		end
		for _, shape in SHAPES do
			for prop in PARENT_FOR do
				local core = customFactory.new()
				local env = environment.new(core)
				env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
				local a, b = valuesFor(prop)
				local sig = core:signal(a)
				local onParent = DRIVEN_ON_PARENT[prop] == true
				local function leafOf(kind: string, id: string, bind: boolean): any
					local props: any
					if kind == "Text" then
						props = { id = id, text = "a label", textSize = 14, padding = 4 }
					elseif kind == "Button" then
						props = { id = id, label = "Press me", compactLabel = { text = "P" } }
					else
						props = {
							id = id,
							axis = "y",
							width = px(60),
							height = px(30),
							children = { UI.Box({ id = "Tall", width = px(50), height = px(400) }) },
						}
					end
					if bind then
						props[prop] = sig
					end
					return (if kind == "Text" then UI.Text elseif kind == "Button" then UI.Button else UI.ScrollView)(
						props
					)
				end
				local function leavesOf(bind: boolean): { any }
					return { leafOf("Text", "T", bind), leafOf("Button", "B", bind), leafOf("ScrollView", "SV", bind) }
				end
				local kids: { any }
				if shape == "leaf" then
					kids = leavesOf(not onParent)
				else
					local function kid(id: string, bind: boolean): any
						local props: any = { id = id, width = px(120), height = px(90), children = leavesOf(false) }
						if bind then
							props[prop] = sig
						end
						return UI.VStack(props)
					end
					kids = { kid("A", not onParent), kid("B", false) }
				end
				local parentProps: any =
					{ id = "P", width = px(600), height = { type = "fill", weight = 1 }, children = kids }
				if onParent then
					parentProps[prop] = sig
				end
				local root = mountLib.mount(
					core,
					UI.Screen({ id = "S", children = { CLASS_FOR_KIND[PARENT_FOR[prop]](parentProps) } })
				)
				local adapter = fake_target.new()
				local controller = renderer.attach(core, root, env, adapter, {
					rootPolicy = "edgeToEdge",
					incrementalLayout = false,
					measureReuse = false,
					layoutNodeReuse = true,
					commitScope = true,
				})
				controller.initialRender()
				local function shot(): string
					local out: { string } = {}
					for path, node in adapter.liveNodes() do
						local r = node.rect
						table.insert(out, `{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}`)
					end
					table.sort(out)
					return table.concat(out, "\n")
				end
				local atA = shot()
				sig:set(b)
				controller.refresh()
				if atA == shot() then
					error(`{shape}/{prop}: the drive is INERT on this parent — every assertion above is vacuous`, 0)
				end
				controller.dispose()
				root.dispose()
			end
		end
	end)

	it("with NO commit-side set supplied, every walk falls back to the all-classes one", function()
		--[[ The two sets are built and reset in lockstep in `renderer.attach`, so
			production never reaches this — but `commit_walks.harvest`'s eighth argument
			is optional, and "optional" has to MEAN something. Constructed the way
			`tests/commit_translate.spec`'s `skip` case is, with the argument omitted:
			`arrangeBlind` must then answer exactly as `moveBlind` does. ]]
		local commit_walks = require("../src/render/commit_walks")
		local function tbl(): any
			return {}
		end
		local ctx: any = {
			adapter = {},
			handles = tbl(),
			stats = { lastCommitVisits = 0, lastCommitVisitsByWalk = {}, propWrites = 0, rectWrites = 0 },
			rectsEqual = function(x: any, y: any): boolean
				return x == y
			end,
			paintedRectIn = function(): any
				return nil
			end,
			pathEscapesClip = function(): boolean
				return false
			end,
			reculPathClips = function() end,
			lastTextSize = tbl(),
			lastTextFont = tbl(),
			lastPadding = tbl(),
			lastCompact = tbl(),
			lastWrapped = tbl(),
			lastVisible = tbl(),
			lastHitRects = tbl(),
			lastScrollRegions = tbl(),
			scrollAutoscroll = tbl(),
			pathClipObservers = tbl(),
			solverHidden = tbl(),
			paintHeld = tbl(),
			pathNodes = tbl(),
			inputSinks = tbl(),
			-- THE RECYCLE-KEY WORN-SET DEP (T8 R3, re-review Minor 3). `CommitCtx`
			-- declares it and `commit_walks.new` binds it unguarded, so a hand-built
			-- record that omits it is a latent nil call the day a fixture here grows
			-- a leaf Button with a compact form. A no-op recorder: nothing in this
			-- file asserts on the worn set, only that the ladder can run at all.
			noteWorn = function() end,
			lastCommitEntry = tbl(),
			hiddenRoots = tbl(),
			lastCompositions = tbl(),
			lastTextFacts = tbl(),
			authoredHidden = tbl(),
		}
		local walks = commit_walks.new(ctx)
		local leafNode = { path = "/S/A", class = "Box", props = {}, children = {} }
		local rootNode = { path = "/S", class = "Screen", props = {}, children = { leafNode } }
		local entry = { rect = { x = 0, y = 0, w = 10, h = 10 } }
		local rects = { ["/S"] = { rect = { x = 0, y = 0, w = 100, h = 100 } }, ["/S/A"] = entry }
		-- the leaf is in the ALL-CLASSES set, and no commit-side set was supplied
		local dirty = { ["/S"] = true, ["/S/A"] = true }
		-- ONE metrics table across every call: `pruning` also requires the
		-- scale/theme/offset stamp to be unchanged, and the theme is compared by
		-- IDENTITY, so a fresh `{}` per call disarms the prune (`armed` reads false)
		local metrics = {}
		walks.harvest(rootNode, rects, true, dirty, 1, metrics, 0)
		walks.harvest(rootNode, rects, true, dirty, 1, metrics, 0)
		ctx.lastCommitEntry["/S/A"] = entry
		expect(`armed={walks.scope.armed()}`).toBe("armed=true")
		-- without a second set the dirty veto still applies to an arrangeBlind walk
		expect(`arrangeBlind={walks.scope.skip(leafNode, true, true)}`).toBe("arrangeBlind=false")
		expect(`moveBlind={walks.scope.skip(leafNode, true)}`).toBe("moveBlind=false")
		-- ...and with a commit-side set that omits it, the arrangeBlind walk prunes
		-- and the move-blind one still does not
		walks.harvest(rootNode, rects, true, dirty, 1, metrics, 0, { ["/S"] = true })
		expect(`narrowed-arrangeBlind={walks.scope.skip(leafNode, true, true)}`).toBe("narrowed-arrangeBlind=true")
		expect(`narrowed-moveBlind={walks.scope.skip(leafNode, true)}`).toBe("narrowed-moveBlind=false")
	end)
end)

--[[ THE ORACLE — the four arms `tests/commit_translate.spec.luau` built, plus the
	one step this task adds at every view: `hide(i, true)` then `hide(i, false)`.

	`hidden` is arrange-classed, so this is the step that shows what the narrowing
	does and does not touch. It is NOT a claim that dropping `hidden` would break
	paint today (see the header: the four narrowed walks do not read it); it is the
	step that would catch it if a walk which does read it were ever promoted. ]]
local function arms(view: any, opts: any): (any, any, any, any)
	local base = table.clone(opts or {})
	base.viewport = { x = 0, y = 0, w = view.w, h = view.h }
	local a = table.clone(base)
	local b = table.clone(base)
	b.measureReuse = false
	local c = table.clone(base)
	c.measureReuse = false
	c.incremental = false -- a forced full solve: no translate, no reuse, no narrow set
	local d = table.clone(base)
	d.commitScope = false -- the pre-P4 commit: every walk descends the whole tree
	return scene.new(a), scene.new(b), scene.new(c), scene.new(d)
end

local ORACLE_PLATES = 20

describe("T5b oracle: the ADAPTER is told the same thing, hide included", function()
	local FIXTURES: { any } = {
		{ name = "plain", plates = ORACLE_PLATES },
		{ name = "overflow", plates = ORACLE_PLATES, overflow = true },
		{ name = "fractional", plates = ORACLE_PLATES, fractional = true },
		{ name = "withPath", plates = ORACLE_PLATES, withPath = true },
	}
	for _, fixture in FIXTURES do
		it(`{fixture.name}: every step, every view, hide and unhide included`, function()
			for _, view in device_views.VIEWS do
				local a, b, c, d = arms(view, fixture)
				local label = `{fixture.name}/{view.id}`
				local function step(what: string, compareB: boolean, drive: (any) -> ())
					drive(a)
					drive(b)
					drive(c)
					drive(d)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: {what} diverged from a FULL solve`, 0)
					end
					if a.snapshot() ~= d.snapshot() then
						error(`{label}: {what} diverged from an UNPRUNED commit`, 0)
					end
					if compareB and a.snapshot() ~= b.snapshot() then
						error(`{label}: {what} diverged from the memo-less solve`, 0)
					end
				end
				if #a.snapshot() == 0 then
					error(`{label}: the fixture painted NOTHING — every comparison below is vacuous`, 0)
				end
				for round = 1, 2 do
					local dx, dy = round * 3, round * 2
					step(`tick {round}`, true, function(w)
						w.tick(dx, dy)
					end)
					step(`caster tick {round}`, false, function(w)
						w.tickWithCasts(dx, dy)
					end)
					step(`hp {round}`, false, function(w)
						w.hp(7, 0.1 * round)
					end)
					-- THE STEP THIS TASK ADDS. `hidden` is arrange-class, and the whole
					-- question of the narrowing is whether it survived it.
					step(`hide {round}`, false, function(w)
						w.hide(3 + round, true)
					end)
					step(`tick-while-hidden {round}`, false, function(w)
						w.tick(dx, dy)
					end)
					step(`unhide {round}`, false, function(w)
						w.hide(3 + round, false)
					end)
					--[[ ...AND A PLACEMENT PROP ON A TEXT LEAF (review round 1, I1). Every
						other step here writes the plate ROOT, a VStack container, and the
						four narrowed walks write for `Text`/`Button`/`ScrollView` and
						nothing else — so without this step the oracle never moves a
						pure-arrange prop on a node whose walk output it can see. `Lvl`
						measures 15x15 in a 16px row, so this moves it by one pixel; the
						counter case below asserts the move rather than assuming it. ]]
					step(`nudge label {round}`, false, function(w)
						w.nudgeLabel(4 + round, if round % 2 == 0 then "center" else "end")
					end)
					step(`unnudge label {round}`, false, function(w)
						w.nudgeLabel(4 + round, "start")
					end)
					step(`add {round}`, false, function(w)
						w.add(round)
					end)
					step(`tick-after-add {round}`, false, function(w)
						w.tick(dx, dy)
					end)
					local added = #a.items
					step(`remove {round}`, false, function(w)
						w.remove(added)
					end)
				end
				a.dispose()
				b.dispose()
				c.dispose()
				d.dispose()
			end
		end)
	end
end)
