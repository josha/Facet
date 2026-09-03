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
	it("the slicer finds all eight walk bodies", function()
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

local function driveWorld(prop: string, control: boolean, commitScope: boolean, keepStretch: boolean?): World
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
	local function kid(id: string, bind: boolean): any
		local props: any = {
			id = id,
			width = px(120),
			height = px(90),
			children = {
				UI.Text({ id = "T", text = "a label", textSize = 14, padding = 4 }),
				UI.Button({ id = "B", label = "Press me", compactLabel = { text = "P" } }),
				UI.ScrollView({
					id = "SV",
					axis = "y",
					width = px(60),
					height = px(30),
					children = { UI.Box({ id = "Tall", width = px(50), height = px(400) }) },
				}),
			},
		}
		if bind then
			props[driven] = sig
		end
		return UI.VStack(props)
	end
	local parentProps: any = {
		id = "P",
		width = px(600),
		height = { type = "fill", weight = 1 },
		children = { kid("A", control or not onParent), kid("B", false) },
	}
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
	local function ser(v: any): string
		if type(v) ~= "table" then
			return tostring(v)
		end
		local inner = {}
		for k, item in v do
			table.insert(inner, `{tostring(k)}={tostring(item)}`)
		end
		table.sort(inner)
		return `\{{table.concat(inner, ",")}\}`
	end
	local out: { string } = {}
	for path, node in adapter.liveNodes() do
		local r = node.rect
		table.insert(
			out,
			`{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|vis={tostring(node.visible)}`
				-- the padding VALUE, not merely its presence: `padding` is one of the four
				-- walks pinned here and it reaches paint through this prop alone, so a
				-- boolean would compare two different insets equal
				.. `|size={tostring((node.props or {}).textSize)}|pad={ser((node.props or {}).padding)}`
				.. `|label={tostring((node.props or {}).label)}|wrap={tostring((node.props or {}).textWrapped)}`
				.. `|canvas={if node.scrollRegion
					then `{node.scrollRegion.contentW},{node.scrollRegion.contentH}`
					else "-"}`
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
	--[[ THE FLOOR IS PER PROP AND IT IS READ OFF THE RUN, because the SOLVER's
		answer differs and the commit is downstream of it:

		  | prop                        | four | harvest | why                        |
		  | anchor/offsetX/offsetY      |   2  |    3    | the driven kid is a TRANSLATE root: same size, new origin, so its entry carries `moveOnly` and its `prev` is what the last commit noted. `harvest` still visits it (all-classes set); the four do not — that GAP is this task |
		  | lineAlign (start -> end)    |   2  |    3    | the same, one axis over |
		  | alignH/alignV (ZStack)      |   4  |    4    | no translate at all (`lastTranslated` is 0): a ZStack re-arranges, so every entry is new and ENTRY IDENTITY refuses the prune for both sets. The narrowing changes nothing here and the pin says so rather than hiding it |
		  | distribute (on the parent)  |   2  |    2    | the dirty node is the PARENT, whose `selfArrangeKey` moved, so it is arranged either way; its two kids are translate roots T5 already prunes |

		So four of the seven show the T5b gap directly, as `by[walk] < by.harvest` on
		the SAME run — a differential inside one process, not a number compared against
		a memory. The other three are pinned at their floor with the reason written in. ]]
	local FLOOR: { [string]: number } = {
		anchor = 2,
		offsetX = 2,
		offsetY = 2,
		lineAlign = 2,
		alignH = 4,
		alignV = 4,
		distribute = 2,
	}
	-- the props whose drive the solver answers with the translate arm, which is where
	-- the commit-side set is the only thing standing between the four walks and a visit
	local BELOW_HARVEST: { [string]: boolean } = { anchor = true, offsetX = true, offsetY = true, lineAlign = true }

	it("each of the seven, on the parent kind that reads it", function()
		for prop in PARENT_FOR do
			local pruned = driveWorld(prop, false, true)
			local unpruned = driveWorld(prop, false, false)
			-- (1) NON-VACUITY: the fixture painted something
			expect(`{prop}:painted={#pruned.shot > 400}`).toBe(`{prop}:painted=true`)
			-- (2) THE CLAIM: the four arrange-blind walks are at this prop's floor
			for _, name in ARRANGE_BLIND do
				expect(`{prop}:{name}={pruned.by[name]}`).toBe(`{prop}:{name}={FLOOR[prop]}`)
			end
			-- (3) ...and where the solver translated, they are STRICTLY below the walk
			-- that kept the all-classes set. That inequality is the narrowing itself.
			for _, name in ARRANGE_BLIND do
				local below = pruned.by[name] < pruned.by.harvest
				expect(`{prop}:{name}<harvest={below}`).toBe(`{prop}:{name}<harvest={BELOW_HARVEST[prop] == true}`)
			end
			-- (4) ...and the adapter was told exactly what an UNPRUNED commit would
			-- have told it, which is the only thing a prune is allowed to change
			if pruned.shot ~= unpruned.shot then
				error(`{prop}: the pruned commit told the adapter something else`, 0)
			end
			pruned.dispose()
			unpruned.dispose()
		end
	end)

	it("a RESIZE is still seen: `lineAlign = stretch` is not a placement move", function()
		--[[ THE SOUNDNESS CASE. Dropping a prop from the commit-side set lifts exactly
			one thing — `skip`'s "this path is dirty" veto — and never entry identity.
			`stretch` is the one value of the seven props that changes the driven node's
			SIZE, so the solver cannot translate it: the entry it writes is a fresh table
			with no `moveOnly` stamp, and all four walks descend to it even though
			`lineAlign` is in `PURE_ARRANGE_PROPS`. Without this case the audit above
			could be read as "an arrange write is invisible to the commit", which is the
			claim this task does NOT make. ]]
		local w = driveWorld("lineAlign", false, true, true)
		local unpruned = driveWorld("lineAlign", false, false, true)
		for _, name in ARRANGE_BLIND do
			expect(`stretch:{name}={w.by[name]}`).toBe(`stretch:{name}={w.by.harvest}`)
			expect(`stretch:{name}>{FLOOR.lineAlign}={w.by[name] > FLOOR.lineAlign}`).toBe(
				`stretch:{name}>{FLOOR.lineAlign}=true`
			)
		end
		if w.shot ~= unpruned.shot then
			error("lineAlign=stretch: the pruned commit told the adapter something else", 0)
		end
		w.dispose()
		unpruned.dispose()
	end)

	it("CONTROL: a MEASURE-class write on the same fixture moves every one of the four", function()
		--[[ The floor above is only evidence if this fixture can produce a non-floor.
			Same mount, same drive, `width` instead of the arrange-only prop — and
			`width` is `dirty = { "measure" }`, which the commit-side set never drops. ]]
		for prop in PARENT_FOR do
			local w = driveWorld(prop, true, true)
			for _, name in ARRANGE_BLIND do
				expect(`{prop}-control:{name}>{FLOOR[prop]}={w.by[name] > FLOOR[prop]}`).toBe(
					`{prop}-control:{name}>{FLOOR[prop]}=true`
				)
			end
			w.dispose()
		end
	end)

	it("...and the drive is LIVE: the seven props each move this fixture's geometry", function()
		--[[ The `alignH`-under-a-VStack trap, from T3's own audit: a prop the parent
			does not read produces identical geometry at both ends of the drive, and
			every differential above then compares a thing to itself. Both ends are
			taken from the same world so this is a fact about the FIXTURE. ]]
		for prop in PARENT_FOR do
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
			local a, b = valuesFor(prop)
			local sig = core:signal(a)
			local onParent = DRIVEN_ON_PARENT[prop] == true
			local function kid(id: string, bind: boolean): any
				local props: any =
					{ id = id, width = px(120), height = px(90), children = { UI.Text({ id = "T", text = "x" }) } }
				if bind then
					props[prop] = sig
				end
				return UI.VStack(props)
			end
			local parentProps: any = {
				id = "P",
				width = px(600),
				height = { type = "fill", weight = 1 },
				children = { kid("A", not onParent), kid("B", false) },
			}
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
				error(`{prop}: the drive is INERT on this parent — every assertion above is vacuous`, 0)
			end
			controller.dispose()
			root.dispose()
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
			lastCommitEntry = tbl(),
			hiddenRoots = tbl(),
			lastCompositions = tbl(),
			lastTextFacts = tbl(),
			authoredHidden = tbl(),
		}
		local walks = commit_walks.new(ctx)
		local leaf = { path = "/S/A", class = "Box", props = {}, children = {} }
		local root = { path = "/S", class = "Screen", props = {}, children = { leaf } }
		local entry = { rect = { x = 0, y = 0, w = 10, h = 10 } }
		local rects = { ["/S"] = { rect = { x = 0, y = 0, w = 100, h = 100 } }, ["/S/A"] = entry }
		-- the leaf is in the ALL-CLASSES set, and no commit-side set was supplied
		local dirty = { ["/S"] = true, ["/S/A"] = true }
		-- ONE metrics table across every call: `pruning` also requires the
		-- scale/theme/offset stamp to be unchanged, and the theme is compared by
		-- IDENTITY, so a fresh `{}` per call disarms the prune (`armed` reads false)
		local metrics = {}
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		ctx.lastCommitEntry["/S/A"] = entry
		expect(`armed={walks.scope.armed()}`).toBe("armed=true")
		-- without a second set the dirty veto still applies to an arrangeBlind walk
		expect(`arrangeBlind={walks.scope.skip(leaf, true, true)}`).toBe("arrangeBlind=false")
		expect(`moveBlind={walks.scope.skip(leaf, true)}`).toBe("moveBlind=false")
		-- ...and with a commit-side set that omits it, the arrangeBlind walk prunes
		-- and the move-blind one still does not
		walks.harvest(root, rects, true, dirty, 1, metrics, 0, { ["/S"] = true })
		expect(`narrowed-arrangeBlind={walks.scope.skip(leaf, true, true)}`).toBe("narrowed-arrangeBlind=true")
		expect(`narrowed-moveBlind={walks.scope.skip(leaf, true)}`).toBe("narrowed-moveBlind=false")
	end)
end)

--[[ THE ORACLE — the four arms `tests/commit_translate.spec.luau` built, plus the
	one step this task adds at every view: `hide(i, true)` then `hide(i, false)`.

	A narrowing that dropped `hidden` from the commit-side set would be invisible to
	every other step in the suite and lethal here. ]]
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
