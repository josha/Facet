--!strict
-- FakeTarget: the headless RenderTargetAdapter (design §13 seam proof).
-- Records a virtual node tree + an op log so tests can assert minimal writes,
-- structural adds/removes, and final virtual state. Same interface as the
-- client-only ScreenTarget.

local chrome_slots = require("../../src/tokens/chrome_slots")
local default_style = require("../../src/tokens/default_style")
-- the PURE paint resolvers the live adapter goes through. Sharing them is the
-- point: a mirror that computed its own colours would prove the fake, not the
-- framework.
local sheet_model = require("../../src/tokens/sheet_model")
-- ...and the PURE rulings the stage content seam is made of, for the same reason
local tag_sync = require("../../src/render/tag_sync")
local stage_content = require("../../src/render/stage_content")
-- ...and the foreign-content seam's ruling ladder, for the same
-- reason: the refusals a caller sees are one function, not one per adapter
local foreign_content = require("../../src/render/foreign_content")

local imageFraming = require("../../src/render/image_framing")
local fake_target = {}

-- EVERY PROP THIS ADAPTER HANDLES, declared (SF-M9's pin).
--
-- This list is the fix for a defect class rather than a nicety. `setProp` used to
-- record ANY prop into `node.props`, so a headless suite could go green on a
-- channel the live adapter had no branch for — which is exactly what happened to
-- the keyboard keep-visible transform: written, recorded, asserted, and never
-- landing on a device. So the fake now REFUSES an undeclared prop, and
-- tests/render_target_contract.spec.luau compares this list against both the
-- renderer's declared emissions and the live adapter's own switch.
--
-- `handled` for a generic recorder means "the renderer may write it and a test may
-- read it back"; the props that also carry a STRUCTURAL mirror below (the
-- gradient's child, the tint's claim, the transform's composed position) say so in
-- their own comments.
local HANDLED_PROPS: { string } = {
	-- data (binding authority)
	"text",
	"label",
	"value",
	"enabled",
	"active",
	"image",
	"selected",
	"cursorHint",
	"placeholder",
	"editing",
	"maxLength",
	"keyboardType",
	"multiline",
	"points",
	"thickness",
	"closed",
	"tint",
	-- paint (style authority)
	"surface",
	"role",
	"shadow",
	"gradient",
	"corners",
	"stroke",
	"textAlign",
	"scaleMode",
	"imageFraming",
	"shape",
	"icon",
	"compactLabel",
	-- dedicated seams (layout + presentation authority)
	"clipChildren",
	"textSize",
	-- the SOLVER's wrap verdict (director ruling 5): the live adapter turns it into
	-- `TextWrapped`, which it can only decide with the drawable width the solve knows
	"textWrapped",
	-- the typography role's FACE, beside its size (F2): the live adapter turns
	-- this descriptor into a FontFace (bespoke) or a `facet-type-<role>` tag
	-- (native), so it has to be a declared prop here or the parity pin blinds
	-- the suite to the whole seam — the SF-M9 lesson this list exists for
	"textFont",
	"padding",
	"transform",
	"transparency",
	"dragHeld",
}
fake_target.HANDLED_PROPS = table.freeze(HANDLED_PROPS)
local HANDLED: { [string]: boolean } = {}
for _, prop in HANDLED_PROPS do
	HANDLED[prop] = true
end

-- authored scaleMode -> the engine ScaleType token the live adapter applies. Same
-- lockstep contract KEYBOARD_TYPE_ENGINE_NAME carries: kept equal to
-- screen_target's SCALE_MODE_ENGINE so the mapping — including `fill` and `crop`
-- both meaning the engine's Crop — is provable without an engine.
local SCALE_MODE_ENGINE_NAME: { [string]: string } = { fit = "Fit", fill = "Crop", crop = "Crop", stretch = "Stretch" }
fake_target.SCALE_MODE_ENGINE_NAME = table.freeze(SCALE_MODE_ENGINE_NAME)

-- The engine scrollbar's thickness, in LOCKSTEP with `SCROLL_BAR_THICKNESS` in
-- src/client/screen_target.luau. It is the thickness of the INSTANCE the live
-- adapter creates on every scroll host, ALWAYS, under both indicator policies
-- (director ruling 2026-08-28 leaves this half alone — the bar itself paints
-- and flashes the same either way). What changed is the LAYOUT reserve
-- (`adapter.scrollBarThickness`) and the engine's window: "always" still
-- charges the window for the instance under the 2026-08-12 reversal; "auto"
-- pairs a zero reserve with a frame WIDENED by this same thickness
-- (`_deriveWindowRect` below), which cancels the engine's own narrowing
-- instead of reserving it from content. `setScrollRegion` models the window
-- either way.
fake_target.SCROLL_BAR_THICKNESS = 8

-- ...AND THE RESERVE IS ONE PIXEL WIDER THAN THE BAR (director report
-- 2026-08-30), in LOCKSTEP with `SCROLL_BAR_GUTTER`/`SCROLL_BAR_RESERVE` in
-- src/client/screen_target.luau. `SCROLL_BAR_THICKNESS` above is the INSTANCE —
-- what the engine paints and what it narrows its own window by. This is what the
-- adapter PUBLISHES as `adapter.scrollBarThickness`, which the renderer feeds to
-- `solver.solve` as `scrollBarReserve`: the bar plus a hairline of clearance, so
-- content stops one pixel short of the bar instead of flush against it. A spec
-- that means "the reserve a live session actually publishes" reads this one; a
-- spec about the bar INSTANCE (the `auto` policy's frame widen, the engine's
-- window narrowing) reads `SCROLL_BAR_THICKNESS` above. They are different
-- numbers on purpose and the gutter is the difference.
fake_target.SCROLL_BAR_GUTTER = 1
fake_target.SCROLL_BAR_RESERVE = fake_target.SCROLL_BAR_THICKNESS + fake_target.SCROLL_BAR_GUTTER

-- the theme a tint resolves against with NO PACKAGE INSTALLED: the library's own
-- style, which is what the live target's `paletteTheme()` falls back to. Once a
-- package is pushed through `setThemePackage` this fake tracks that package's
-- theme instead — see `paletteTheme` below. It used to be the ONLY answer here,
-- which is precisely why no headless check could see the 2026-08-14 defect: a
-- fake that resolves every tint against neutral cannot tell a themed colour from
-- a stale one.
local NEUTRAL_THEME = { colors = default_style.colors, extra = default_style.extra }

-- a `UI.Path`'s stroke role -> the palette token it resolves to, in LOCKSTEP with
-- `PATH_ROLE_TOKEN` in src/client/screen_paint.luau. A Path2D is not a GuiObject,
-- so no rule can ever paint one: this is adapter-owned in both targets.
local PATH_ROLE_TOKEN: { [string]: string } = { accent = "accent", secondary = "contentSecondary" }

-- the engine property each class's tint claims (mirrors applyTint)
local TINT_ENGINE_PROP: { [string]: { string } } = {
	Box = { "BackgroundColor3", "BackgroundTransparency" },
	Text = { "TextColor3" },
	Image = { "ImageColor3" },
	Path = { "Path2D.Color3" },
	-- a ViewportFrame's "picture" IS its rendered scene, and the engine multiplies
	-- it by the same ImageColor3 an ImageLabel uses (research 2026-08-08)
	Stage = { "ImageColor3" },
}

-- ...and the EXTRA property a tint that declares its own `transparency` claims.
-- A Box already claimed its transparency, so it adds nothing there; Text and
-- Image take one more (mirrors applyTint's `hasAlpha` branches).
local TINT_ALPHA_ENGINE_PROP: { [string]: { string } } = {
	Text = { "TextTransparency" },
	Image = { "ImageTransparency" },
	Stage = { "ImageTransparency" },
}

-- opts.trackThemeRoots: opt into the WHOLE-TARGET theme relink seam
-- (screen_target.relinkThemeSheet). Off by default so the targets
-- that assert the single-root `linkAt` path are unaffected; on, this adapter
-- keeps a roots list and repoints every live one, which is the contract the
-- client target implements against real StyleLinks.
export type Opts = { trackThemeRoots: boolean?, ops: boolean? }

function fake_target.new(opts: Opts?)
	local nodes: { [string]: any } = {}
	local ops: { string } = {}
	--[[ THE OP LOG IS OPT-IN (Plan C addendum, T12). All 22 `table.insert(ops, …)`
		sites below interpolate a formatted string, and `setRect` is on the commit's
		hot loop: 1.40 us per write measured from inside `rect_pass.applyOne`, which is
		10.28 ms of the 30.9 ms `war_room_inventory L reorder` class in FacetBench — a
		THIRD of a headline number spent by the instrument reading it.

		THE INTERPOLATION IS INSIDE THE GUARD, NOT AT THE CALL SITE. `note(\`rect …\`)`
		builds the string and throws it away. Only a guard the caller takes BEFORE it
		composes costs nothing, which is why every site reads
		`if recordOps then` / `note(...)` / `end` (stylua's own three-line shape for
		this — it does not keep a single-line `if...then...end` at this width) and
		why the source scan pins that shape rather than a single-line spelling. ]]
	local recordOps = opts ~= nil and opts.ops == true
	local function note(line: string)
		table.insert(ops, line)
	end
	local rootCount = 0
	-- cumulative engine Position/Size writes, mirroring `applyRect`'s own bill —
	-- see `adapter.engineWrites` beside `hostCount`, and the mirror in `setRect`
	local engineWriteCount = 0
	-- MIRRORS `screen_target`'s module-scope `lastRootHandle`: the root of the last
	-- `create` on this target, whichever surface asked for it. `adopt` is the only
	-- reader, because `adopt` is the only entry point that is not told its root.
	local lastCreatedRoot: any = nil

	--[[ THE INSTANCE-HOST MIRROR, AND WHY A TARGET WITH NO INSTANCES
		HAS ONE AT ALL.

		This adapter's core simplification is that there is no parenting here — a
		flat map of nodes, and every ancestor's transform counted, so the composed
		WINDOW POSITION comes out the same as the live adapter's. That stays exactly
		true and `_composePresentation` is untouched by this.

		What it could NOT mirror is WHICH NODES ARE REAL PARENTS, and that turned
		out to matter for something that has nothing to do with position: the live
		`parkEligible` refuses to recycle a registered host, and this target had no
		field to refuse on. So the single most important interaction in nesting —
		"every host registered is one node removed from the recycle pool" — was
		invisible to every headless recycling spec. A fake that accepts what the
		real one refuses proves the wrong thing, which is the rule the park mirror
		below already states about its other three refusals.

		`crops` IS NOT `clipChildren`, AND THE DIFFERENCE IS THE POINT. What the
		framework actually asks a host is "can something drawn outside a child's own
		box survive here" — the question the focus ring's float placement turns on.
		A `ClipsDescendants` host answers no. So does a `CanvasGroup`, which does not
		set that property at all but renders its subtree into a buffer its own size,
		which crops just as hard. A plain move-boundary host answers YES, and
		conflating the three is how a ring that only ever needed to exist inside a
		scroll canvas would start appearing under every container that merely moves.
	]]
	local instanceHosts: { [string]: any } = {}
	local function registerFakeHost(path: string, crops: boolean, hostSpace: boolean?): any
		local existing = instanceHosts[path]
		if existing ~= nil then
			-- create-or-REUSE, mirroring `screen_presentation.registerHost`, and
			-- `crops` accumulates rather than being overwritten: a node can declare
			-- itself a fade group at creation and then be given `clipChildren`, and
			-- the second declaration must not un-crop the first.
			existing.crops = existing.crops or crops
			-- ...and `hostSpace` accumulates for the identical reason (Plan C): a path
			-- registered twice must not lose the fact that its children's rects are
			-- stored relative to it, or every one of them lands at `rect - host`.
			existing.hostSpace = existing.hostSpace or hostSpace
			return existing
		end
		-- `rect = nil` mirrors the live shape (screen_target.setRect:2098-2100
		-- writes `entry.rect` on the host it re-parents against); the engine-write
		-- mirror below reads it to find the host-relative pair a real parent buys.
		local entry = { path = path, crops = crops, children = {}, rect = nil, hostSpace = hostSpace }
		instanceHosts[path] = entry
		return entry
	end
	local function unregisterFakeHost(path: string)
		instanceHosts[path] = nil
	end
	--[[ LEAVING THE HOST ABOVE, mirroring the live `releaseHostMembership` (T4b).
		`children` was write-only on this target until now — filled at create and read
		by nobody — which is precisely why the live adapter's own gap (a `remove` that
		never emptied it) was invisible headless. The park rule below reads the array,
		so both exits have to maintain it or a host that outlived every child it
		destroyed would be refused forever. ]]
	local function releaseFakeHostMembership(node: any)
		local host = node.instanceHost
		if host == nil then
			return
		end
		for i, child in host.children do
			if child == node then
				table.remove(host.children, i)
				break
			end
		end
		node.instanceHost = nil
	end
	-- the nearest registered ANCESTOR, by the same separator walk the live registry
	-- uses — not a scan, and never the node itself
	local function hostFor(path: string): any
		local i = #path
		while i > 1 do
			if string.sub(path, i, i) == "/" then
				local entry = instanceHosts[string.sub(path, 1, i - 1)]
				if entry ~= nil then
					return entry
				end
			end
			i -= 1
		end
		return nil
	end

	--[[ WHO IS DIRECTLY UNDER WHOM (T12). The coordinate-space recompose in `setRect`
		found a host's subtree by walking EVERY node in this target and testing
		`string.sub(path, 1, #prefix) == prefix` — O(hosts x nodes) per commit, which on
		FacetBench's `nameplates L` tick is 248 hosts x 1,503 nodes and 21.3 of the
		class's 24.0 ms. The same class LIVE is 2.876 ms: the engine reparents for free
		and this fake was charging Facet for the difference.

		KEYED ON THE NEAREST PATH THAT IS ACTUALLY A NODE, NOT THE LAST "/" CUT
		(fix round, found by `facet_sponsor_table.spec`'s map name tags going stale
		on their dot's own move). `mount.luau`'s `ForEach` and `When` splice their
		children in WITHOUT a wrapper node at the per-item / per-branch path segment
		— nameplates_scene's own header calls `.../[p1]` "a path string with nothing
		mounted at it" — so a leaf can sit at `.../Dot/NameTagRegion/then/NameTag`
		while NEITHER `NameTagRegion` NOR `then` was ever `create`d. A bare last-"/"
		cut indexes that leaf under a parent key nobody ever inserts, orphaning it
		from `Dot`'s own bucket the first time `Dot` moves — exactly the class of
		regression this file exists to catch, caught here by RUNNING it rather than
		reasoning about it. `nearestExistingAncestor` walks past any such gap to the
		nearest path that IS a node, which is the same tolerance `hostFor` and
		`spaceOriginOf` already have for a coordinate-space ancestor.

		AND THE SELECTION IS BY PATH WHILE THE COMPUTATION IS BY HOST CHAIN, exactly as
		today. `spaceOriginOf` walks `handle.instanceHost`, never the composed node's
		path; `adopt` re-keys `nodes[newPath]` and never deletes the old key, so the old
		key stays in this index too. Matching today's set is the requirement; fixing
		`adopt`'s leak is a different change with its own oracle.

		THE INDEX PARENT IS RESOLVED ONCE, AT CREATE, AND NEVER REVISED (fix round 1,
		review Minor 1). A node created while an intermediate ancestor is still absent
		is keyed under the higher ancestor it was born under, and creating that
		intermediate LATER does not re-home it — so it follows the ancestor's move, not
		the intermediate's. No renderer path reaches this: the reconciler-only segments
		above are never created AT ALL (the gap is permanent), and every real ancestor
		is mounted parent-first. It is stated here because it is the standing shape of
		this index, and because `unindexNode`'s re-homing deliberately adds a second
		case of it.

		DECLARED BEFORE `adapter.create`, ON PURPOSE. Luau closures capture upvalues by
		lexical scope at the time a `local function` is COMPILED, not at the time it
		runs — a `create` defined above this block would have found `indexNode` still a
		free (nil) global the first time the renderer actually called it. ]]
	local childrenOf: { [string]: { [string]: true } } = {}
	local function parentPathOf(path: string): string?
		local i = #path
		while i > 1 do
			if string.sub(path, i, i) == "/" then
				return string.sub(path, 1, i - 1)
			end
			i -= 1
		end
		return nil
	end
	-- the nearest ancestor path that is ACTUALLY a live node, skipping any
	-- reconciler-only segment nothing was ever created at. `nodes` is declared
	-- above this block, so it is already an upvalue here.
	local function nearestExistingAncestor(path: string): string?
		local p = parentPathOf(path)
		while p ~= nil and nodes[p] == nil do
			p = parentPathOf(p)
		end
		return p
	end
	local function indexNode(path: string)
		local parent = nearestExistingAncestor(path)
		if parent == nil then
			return
		end
		local bucket = childrenOf[parent]
		if bucket == nil then
			bucket = {}
			childrenOf[parent] = bucket
		end
		bucket[path] = true
	end
	--[[ ...AND UNINDEXING RE-HOMES WHAT IT WOULD ORPHAN (fix round 1, review
		Important 3). The first draft ended `childrenOf[path] = nil`, throwing away a
		still-populated bucket. `park` refuses a HOST that still has children
		(`#hostEntry.children > 0`), but a PLAIN node with path-children is parkable
		and removable, and the old prefix scan reached those children anyway — it
		selected on the path STRING, not on a live parent chain. Measured on
		`fake_target_ops_opt.spec`'s fixture (e): a leaf under a parked middle node
		stayed at its pre-move `2,2` where the old scan re-based it to `72,82`.

		So the orphans move up to the nearest ancestor that IS still a node — the same
		key `indexNode` would compute for them now that this path is gone (every call
		site deletes `nodes[path]` BEFORE calling here, so the walk already skips the
		dying node), and the same set the old scan selected. A re-homed child keeps
		that higher key if its old parent is later adopted back, which is the
		create-time resolution shape documented above rather than a new one. The
		alternative — asserting the bucket is empty — would make the renderer's
		deepest-first sweep discipline load-bearing and undocumented. ]]
	local function unindexNode(path: string)
		local orphans = childrenOf[path]
		childrenOf[path] = nil
		local parent = nearestExistingAncestor(path)
		if parent == nil then
			return
		end
		local bucket: { [string]: true }? = childrenOf[parent]
		if bucket == nil and orphans ~= nil then
			bucket = {}
			childrenOf[parent] = bucket
		end
		if bucket == nil then
			return
		end
		bucket[path] = nil
		if orphans ~= nil then
			for child in orphans do
				bucket[child] = true
			end
		end
		if next(bucket) == nil then
			childrenOf[parent] = nil
		end
	end

	local trackThemeRoots = (opts ~= nil and opts.trackThemeRoots == true)
	local themeRoots: { any } = {}
	local LEGACY_SHEET = { Name = "FacetStyle (legacy)" }
	local activeThemeSheet: any = nil

	-- ===== THE PALETTE ADAPTER-OWNED PAINT RESOLVES AGAINST =================
	-- The mirror of screen_paint's `paletteTheme()`: the installed package theme,
	-- or the library style when none is installed. Set by `setThemePackage`, which
	-- is the ONE commit both targets take a theme through.
	local activeThemePalette: any = nil
	local function paletteTheme(): any
		return activeThemePalette or NEUTRAL_THEME
	end
	local function pathRoleColor(role: any): any
		return sheet_model.paletteColor(paletteTheme(), PATH_ROLE_TOKEN[tostring(role)] or "content")
	end

	-- pointer-capture state (declared up top: destroyRoot references it)
	local pointerCapture: any = nil
	local hoverHint: string? = nil
	local captureHint: string? = nil

	local adapter = {}

	--[[ THE CLASSIFICATION-TAG MIRROR (SCREEN-X, 2026-08-22).

		WHY IT EXISTS. Tags are the ONLY channel by which Facet's surfaces, states
		and roles reach native paint, and this fake modelled none of them — which
		is why a dead tag-REMOVAL loop shipped for four days under 7,116 green
		cases and had to be found by looking at a screen (the removal
		test compared five characters against a six-character literal).

		WHAT IS SHARED AND WHAT IS MIRRORED. The DECISION is not copied: `owns` and
		`diff` are `src/render/tag_sync.luau`, the same pure module the live
		adapter calls, so the two targets cannot disagree about what a sync does.
		What is mirrored is the narrow bookkeeping around it — which classification
		state a create and three prop writes leave behind — and it is deliberately
		NOT the adapter's whole classification surface. It covers the family the
		sticky-tag defect was about (surface, selected, role, and the interactive
		default a Button/Toggle takes at create); a state this map does not model
		simply produces no tag here, which is a gap a reader can see rather than a
		lie. Keep it in lockstep with `screen_target`'s `syncTags` inputs and
		`screen_paint.applySurfaceNative`, exactly as `SCALE_MODE_ENGINE_NAME` is
		kept in lockstep with the adapter's own map. ]]
	local function syncFakeTags(handle: any)
		local state = handle.tagState
		if state == nil then
			return
		end
		local desired = sheet_model.classifyTags({
			surface = state.surface,
			selected = state.selected == true,
			interactive = state.interactive == true,
			buttonRole = state.buttonRole,
		})
		local plan = tag_sync.diff(handle.tags or {}, desired)
		local live: { [string]: boolean } = {}
		for _, tag in handle.tags or {} do
			live[tag] = true
		end
		for _, tag in plan.remove do
			live[tag] = nil
		end
		for _, tag in plan.add do
			live[tag] = true
		end
		local out: { string } = {}
		for tag in live do
			table.insert(out, tag)
		end
		table.sort(out)
		handle.tags = out
	end

	-- the tags a node wears right now, sorted. `{}` for a node this mirror does
	-- not classify (everything that is not an interactive leaf).
	function adapter.tagsOf(path: string): { string }
		local node = nodes[path]
		return if node ~= nil and node.tags ~= nil then node.tags else {}
	end

	function adapter.createRoot(screenId: string): any
		rootCount += 1
		if recordOps then
			note(`createRoot {screenId}`)
		end
		local root = { id = screenId, alive = true }
		if trackThemeRoots then
			-- a LATER root inherits whatever sheet the target currently carries,
			-- so a modal opened after an install is never Neutral over a themed
			-- screen
			root.themeSheet = activeThemeSheet or LEGACY_SHEET
			table.insert(themeRoots, root)
		end
		return root
	end

	-- Declared ONLY when opted in: the theme controller feature-detects this
	-- method, so an adapter that always carries it would never exercise the
	-- single-root `linkAt` fallback that every other target still uses.
	if trackThemeRoots then
		-- repoint EVERY live root; nil restores the target's legacy sheet
		function adapter.relinkThemeSheet(sheet: any?)
			activeThemeSheet = sheet
			local live: { any } = {}
			for _, root in themeRoots do
				if root.alive then
					root.themeSheet = sheet or LEGACY_SHEET
					table.insert(live, root)
				end
			end
			themeRoots = live
		end

		-- screenId -> the sheet that root currently links (test accessor)
		function adapter.rootThemeSheets(): { [string]: any }
			local out: { [string]: any } = {}
			for _, root in themeRoots do
				if root.alive then
					out[root.id] = root.themeSheet
				end
			end
			return out
		end

		function adapter.legacyThemeSheet(): any
			return LEGACY_SHEET
		end
	end

	-- `decorationHint` is the renderer's 4th argument (theme fix round): the
	-- pure decoration hint read off the node's INTERNAL meta channel. A real
	-- target uses it to classify a decoration slot and to tag the node with its
	-- own paint identity; this one RECORDS it, so a headless test can prove the
	-- hint actually travelled blueprint -> mount -> renderer -> adapter rather
	-- than only that a control declared one.
	-- `createOpts` is the renderer's 5th argument: the
	-- creation-time facts that decide which engine object the live adapter builds.
	-- Mirrored, so "this node became a fade GROUP" is provable headless — the live
	-- target materializes a CanvasGroup and nothing else can fade a subtree.
	-- MIRRORS THE LIVE ADAPTER'S ELISION. `screen_target` gives a pure layout container
	-- a handle and no engine object; this target has no engine objects at all, but it
	-- must report the same VERDICT or a headless test cannot see the rule being turned
	-- off at runtime.
	local FAKE_ELIDABLE: { [string]: boolean } =
		{ VStack = true, HStack = true, ZStack = true, Grid = true, Anchor = true, Spacer = true }

	function adapter.create(
		rootHandle: any,
		path: string,
		class: string,
		decorationHint: any?,
		createOpts: { canvasGroup: boolean? }?
	): any
		local node = {
			path = path,
			class = class,
			props = {},
			rect = nil,
			alive = true,
			root = rootHandle,
			decorationHint = decorationHint,
		}
		if class == "Button" or class == "Toggle" then
			-- the class default the live adapter takes at CREATE: control chrome plus
			-- interaction states, both from the sheet (screen_target's create branch)
			node.tagState = { surface = "control", interactive = true }
			node.tags = {}
			syncFakeTags(node)
		end
		if createOpts ~= nil and createOpts.canvasGroup == true then
			node.canvasGroupInstance = { className = "CanvasGroup", groupTransparency = 0 }
			-- a fade group is a REAL PARENT from birth: its subtree renders into the
			-- group's own buffer, which is exactly why it CROPS
			registerFakeHost(path, true)
		end
		if createOpts ~= nil and (createOpts :: any).instanceHost == true then
			-- a declared MOVE boundary: a real parent so the engine carries the
			-- subtree, and a plain one — no buffer, no clip, nothing cropped.
			-- `hostSpace` says the stronger thing (Plan C): this node is also the ORIGIN
			-- its subtree's rects are stored against, so nothing beneath it arrives in
			-- window space and `setRect` composes this entry's rect back in.
			registerFakeHost(path, false, (createOpts :: any).hostSpace == true)
		end
		if class == "Path" then
			-- the DEFAULT stroke role's colour, from the live theme: `role` is
			-- optional, so a path that never declares one is painted only here
			-- (mirrors screen_target's Path2D creation)
			node.pathRoleColor = pathRoleColor(nil)
			--[[ THE STROKE ITSELF, as a record (2026-09-07). `screen_target` creates a
				`Path2D` CHILD for a Path node and owns two facts about it that nothing
				else can reach: its paint order — born at its holder's `ZIndex` and
				mirrored by `setZOrder`, because the z walk never visits a child — and
				how many times its GEOMETRY has been uploaded, which is a real cost
				(`SetControlPoints` hands the engine a whole new shape and the engine
				does not diff it). A fake with no stroke record could not tell a target
				that uploads once from one that uploads on every rect write, which is
				exactly the difference `screen_presentation.applyPathPoints` now makes.
				`zIndex` starts at 1 because that is what a freshly created engine
				object carries when `create` reads it. ]]
			node.pathStroke = { zIndex = 1, uploads = 0, points = nil }
		end
		-- ANY creation option means a real engine object is required, mirroring the
		-- live guard exactly. This read
		-- `createOpts.canvasGroup ~= true` while a group was the only option there
		-- was, and when a second option arrived the fake happily elided a node it had
		-- just registered as a real parent — a host with no instance to be one, green
		-- headless and impossible live. Precisely the divergence this target exists
		-- to prevent, found by the elision census refusing to show the step's cost.
		if FAKE_ELIDABLE[class] and decorationHint == nil and createOpts == nil then
			node.elided = true
		end
		if class == "Foreign" then
			-- MIRROR THE LIVE ADAPTER'S TWO CREATION-TIME FACTS. The box
			-- CLIPS from birth, because "the framework owns the box" is only a
			-- contract if nothing the caller adopts can paint outside it; and the
			-- node is flagged as a foreign box so the park refusal below is keyed on
			-- a field rather than on a class name, exactly as the Stage refusal is.
			node.foreignBox = true
			node.foreignClips = true
		end
		-- ...and where THIS node parents. A node is never its own host, so the
		-- registration above and this lookup cannot collide.
		local host = hostFor(path)
		if host ~= nil then
			node.instanceHost = host
			table.insert(host.children, node)
		end
		-- WHICH SURFACE ROOT THIS NODE HANGS UNDER, mirroring the live adapter's
		-- `if host ~= nil then instance.Parent = host.instance else instance.Parent =
		-- rootHandle.gui` (screen_target `buildHandle`). Nil means "inside a host
		-- instead", which is the same answer the live tree gives. A create is handed
		-- its own root and is always right; `adopt` is not handed one at all, which
		-- is the whole reason this record exists — see `adapter.adopt`.
		node.parentRoot = if host ~= nil then nil else rootHandle
		lastCreatedRoot = rootHandle
		nodes[path] = node
		indexNode(path)
		if recordOps then
			note(`create {path} ({class})`)
		end
		-- born under a live transform: the first placement already carries the offset
		adapter._composePresentation(node)
		return node
	end

	-- THE PRESENTATION COMPOSITION, MIRRORED. The live adapter
	-- writes `rect + own transform + every ancestor's` as the node's engine Position
	-- — it has to, because its instance tree is FLAT, so a container's move does not
	-- carry the nodes inside it. The composed WINDOW POSITION is the fact both
	-- adapters must agree on, so that is what this records: `presentedPosition`.
	--
	-- (The live rule stops accumulating at a real instance parent, whose own move
	-- already carries its children; there is no parenting here, so every ancestor
	-- counts — the two arrive at the same window position, which is the point.)
	function adapter._composePresentation(node: any)
		local ox, oy = 0, 0
		-- `node.rect` is already the WINDOW rect (see `setRect`), so the
		-- coordinate-space chain is not added again here
		local own = node.props.transform
		if type(own) == "table" then
			ox += own.x or 0
			oy += own.y or 0
		end
		local path = node.path
		for i = #path, 2, -1 do
			if string.sub(path, i, i) == "/" then
				local ancestor = nodes[string.sub(path, 1, i - 1)]
				local t = if ancestor ~= nil then ancestor.props.transform else nil
				if type(t) == "table" then
					ox += t.x or 0
					oy += t.y or 0
				end
			end
		end
		node.presentationOffset = { x = ox, y = oy }
		-- THE SIZE HALF, AND IT DELIBERATELY DOES NOT ACCUMULATE (withAnimation size,
		-- 2026-08-14). An offset has to accumulate because the instance tree is flat —
		-- a container's move carries nothing inside it. A SIZE change carries nothing
		-- either, and that is exactly why a child must NOT inherit it: every rect is
		-- absolute, so growing a panel's painted box must leave the nodes inside it at
		-- their own solved size. The live adapter reads only `presentationTransforms
		-- [handle.path]` for this; the loop above is the offset's business alone.
		local sw = if type(own) == "table" and type(own.w) == "number" then own.w else 0
		local sh = if type(own) == "table" and type(own.h) == "number" then own.h else 0
		node.presentationSize = { w = sw, h = sh }
		if node.rect ~= nil then
			node.presentedPosition = { x = node.rect.x + ox, y = node.rect.y + oy }
			-- what the engine `Size` is actually written as, which is the fact both
			-- adapters must agree on (the live one writes it in `applyRect`)
			node.presentedSize = { w = node.rect.w + sw, h = node.rect.h + sh }
			-- CENTERED SCALE PIVOT (director fix round, RR parity): the live adapter
			-- re-anchors a motion-scaled instance to its center, so the scaled visual
			-- rect inflates about the solved rect's center — the node's visual CENTER
			-- never moves under scale. This records that composed fact so headless
			-- pins can hold the pivot the live UIScale honours.
			local s = if type(own) == "table" and type(own.scale) == "number" then own.scale else nil
			if s ~= nil and s ~= 1 then
				local r = node.rect
				node.presentedVisualRect = {
					x = r.x + ox + r.w * (1 - s) / 2,
					y = r.y + oy + r.h * (1 - s) / 2,
					w = r.w * s,
					h = r.h * s,
				}
			else
				node.presentedVisualRect = nil
			end
		else
			node.presentedPosition = nil
			node.presentedSize = nil
			node.presentedVisualRect = nil
		end
	end

	--[[ THE SPACE-HOST CHAIN ABOVE A PATH, over the STORED rects the host entries
		hold. Zero on every path with no coordinate-space host above it, which is
		every path on a host-free tree. ]]
	local function spaceOriginOf(handle: any): (number, number)
		local ox, oy = 0, 0
		local h = handle.instanceHost
		while h ~= nil do
			if h.hostSpace and h.rect ~= nil then
				ox += h.rect.x
				oy += h.rect.y
			end
			h = hostFor(h.path)
		end
		return ox, oy
	end

	--[[ THE STROKE'S GEOMETRY UPLOAD, VALUE-DIFFED — the mirror of
		`src/client/screen_presentation.luau`'s `applyPathPoints`. Both call sites
		are mirrored (the `points` prop setter, and the belt `applyRect` runs on
		every rect write) so a headless spec can count what the engine would
		actually be handed. Compared BY VALUE: the prop arrives as a fresh table on
		every rebuild, so identity would never match. ]]
	local function applyFakePathPoints(handle: any)
		local stroke = handle.pathStroke
		local points = handle.normPoints
		if stroke == nil or points == nil then
			return
		end
		local applied = stroke.points
		if applied ~= nil and #applied == #points then
			local same = true
			for i = 1, #points do
				local a, b = applied[i], points[i]
				if
					a.x ~= b.x
					or a.y ~= b.y
					or a.inX ~= b.inX
					or a.inY ~= b.inY
					or a.outX ~= b.outX
					or a.outY ~= b.outY
				then
					same = false
					break
				end
			end
			if same then
				return
			end
		end
		local copy = table.create(#points)
		for _, p in points do
			table.insert(copy, { x = p.x, y = p.y, inX = p.inX, inY = p.inY, outX = p.outX, outY = p.outY })
		end
		stroke.points = copy
		stroke.uploads += 1
	end

	function adapter.setRect(handle: any, rect: any)
		if handle.props.imageFraming then
			handle.imagePlan = imageFraming.resolve(handle.props.imageFraming, rect.w, rect.h)
		end
		--[[ TWO RECTS, AND THE NAMES SAY WHICH IS WHICH (Plan C, C1).

			`storedRect` is exactly what the renderer handed over. Beneath a
			COORDINATE-SPACE host that is HOST-RELATIVE, because the solver stores it
			that way and the engine composes the rest by parenting — it is the number
			the live `applyRect` writes, and the one an oracle compares between a hosted
			and an unhosted world.

			`rect` is where the node IS: the stored rect plus every space host above it.
			That is what this target has always reported under that name and what every
			rule written against it means — a containment audit, an overlap sweep, a
			pointer coordinate. Keeping the name honest is the same doctrine the header
			states about `presentedPosition`: there is no parenting here, so the fake
			reports the composed window answer and lets the engine-write mirror below
			carry the host-relative pair separately. ]]
		handle.storedRect = rect
		local selfHost = instanceHosts[handle.path]
		if selfHost ~= nil then
			-- mirrors `screen_target.setRect`: a host records the STORED rect its own
			-- children's engine-write mirror and window composition re-base against.
			-- WRITTEN BEFORE the composition below, and the renderer walks in document
			-- order, so a child always composes against a current origin.
			selfHost.rect = rect
		end
		local spaceX, spaceY = spaceOriginOf(handle)
		handle.rect = if spaceX == 0 and spaceY == 0
			then rect
			else { x = rect.x + spaceX, y = rect.y + spaceY, w = rect.w, h = rect.h }
		--[[ ...AND THE HIT BAND IS RE-BASED HERE TOO, mirroring the live `applyRect`,
			which calls `applyHitExpander(handle)` for exactly this reason. The commit
			pushes hit rects BEFORE it pushes rects, so on a fresh build a host's own
			rect is not yet current when the expander is first placed and the origin
			`setHitRect` composed against was stale. Placing it in the one function that
			re-bases a node is what makes the two unable to disagree. ]]
		local storedHit = handle.storedHitRect
		if storedHit ~= nil then
			handle.hitRect = if spaceX == 0 and spaceY == 0
				then storedHit
				else { x = storedHit.x + spaceX, y = storedHit.y + spaceY, w = storedHit.w, h = storedHit.h }
		end
		-- see `engineWrites`: the position the engine would be handed is the
		-- host-relative pair (`presentedPosition` is the WINDOW pair; both are kept).
		-- ZERO under a coordinate-space host, mirroring
		-- `screen_presentation.hostOriginOf`: those children's rects are ALREADY
		-- relative to it, so there is nothing left to subtract.
		local hostOx, hostOy = 0, 0
		local host = handle.instanceHost
		if host ~= nil and host.rect ~= nil and host.hostSpace ~= true then
			hostOx, hostOy = host.rect.x, host.rect.y
		end
		-- the STORED pair, never the composed one: this mirrors what `applyRect` sends
		local px, py = rect.x - hostOx, rect.y - hostOy
		if handle.lastWriteX ~= px or handle.lastWriteY ~= py then
			handle.lastWriteX, handle.lastWriteY = px, py
			engineWriteCount += 1
		end
		if handle.lastWriteW ~= rect.w or handle.lastWriteH ~= rect.h then
			handle.lastWriteW, handle.lastWriteH = rect.w, rect.h
			engineWriteCount += 1
		end
		-- ORDERING-HAZARD MIRROR (task SCROLL2 fix round 1, RED-TEAM finding 1):
		-- captured at the EXACT moment this call runs, mirroring the live
		-- `applyRect`'s own read of `handle.barOverlayWidenW/H`
		-- (screen_presentation.luau composes `pw = rect.w + ... + barOverlayWidenW`
		-- into the Size it actually sends). `_deriveWindowRect` below recomputes
		-- `windowRect` FRESH from whatever is current every time it runs, which
		-- cannot see a stale write — this field is a plain snapshot instead, so a
		-- renderer that calls `setRect` before the widen for THIS solve has been
		-- written (`setScrollRegion`, below) proves it by staying stale here.
		handle.appliedRectW = rect.w + (handle.barOverlayWidenW or 0)
		handle.appliedRectH = rect.h + (handle.barOverlayWidenH or 0)
		if recordOps then
			note(`rect {handle.path} {rect.x},{rect.y} {rect.w}x{rect.h}`)
		end
		-- a rect write RE-APPLIES the stored transform, exactly as the live
		-- applyRect does: a re-solve must never drop a running motion
		adapter._composePresentation(handle)
		-- ...and re-runs the stroke belt, exactly as the live `applyRect` does. It is
		-- a BELT and not a write: `applyFakePathPoints` value-diffs, so a box that
		-- moved with points that did not uploads nothing (mirrors the live diff)
		applyFakePathPoints(handle)
		--[[ ...AND A COORDINATE-SPACE HOST'S MOVE RECOMPOSES ITS WHOLE SUBTREE, which
			the `transform` prop branch below already does for its own reason. Under Plan
			C a host move produces exactly ONE `setRect` — the host's — and zero for its
			descendants, which is the point; but every descendant's `presentedPosition`
			is a function of this rect, so without this loop each would keep its pre-move
			value forever while a real engine reparents for free. The oracle's
			`pos == sro` identity is the instrument that catches it. ]]
		if selfHost ~= nil and selfHost.hostSpace == true then
			--[[ DEPTH-FIRST OVER THE INDEX, not a scan of the map. Same set, same
				per-node computation. Order is output-neutral: `spaceOriginOf` (above)
				and `_composePresentation` read only host entries and ancestor
				`props.transform`, never a sibling's composed rect.

				THE ONE SEMANTIC DIFFERENCE FROM THE OLD SCAN, AND WHY IT IS ACCEPTED:
				the old walk visited every node whose PATH carried the prefix whether or
				not its intermediate ancestors were themselves in `nodes`; this recursion
				stops at a missing link in `childrenOf`. `adopt`'s old-key leak (indexed
				but with no live parent chain above it) is the one case this could matter
				for, and the characterisation pin in `fake_target_ops_opt.spec` freezes
				that fixture byte-equal before and after. ]]
			local function recompose(parentPath: string)
				local bucket = childrenOf[parentPath]
				if bucket == nil then
					return
				end
				for path in bucket do
					local node = nodes[path]
					if node ~= nil and node.storedRect ~= nil then
						local sx, sy = spaceOriginOf(node)
						local st = node.storedRect
						node.rect = if sx == 0 and sy == 0
							then st
							else { x = st.x + sx, y = st.y + sy, w = st.w, h = st.h }
						local sh = node.storedHitRect
						if sh ~= nil then
							node.hitRect = if sx == 0 and sy == 0
								then sh
								else { x = sh.x + sx, y = sh.y + sy, w = sh.w, h = sh.h }
						end
						adapter._composePresentation(node)
					end
					recompose(path)
				end
			end
			recompose(handle.path)
		end
		-- ...AND RE-DERIVES THE ENGINE WINDOW, because it is a function of this rect
		-- (2026-08-14). `windowRect` was computed only in `setScrollRegion`, so a
		-- host that MOVED or RESIZED without its canvas changing — a rotation, a
		-- sibling growing, a safe-area shift — went on reporting the window of the
		-- box it used to occupy. The engine has no such lag: AbsoluteWindowSize is
		-- read off the live frame. A test comparing a descendant against a stale
		-- window is the "instrument reading an unreal surface" trap ENGINEERING.md
		-- names, and it fails in the safe-looking direction (the old window is
		-- usually the right SIZE, so only the position is wrong and only sometimes).
		if handle.scrollRegion ~= nil then
			adapter._deriveWindowRect(handle, handle.scrollRegion)
		end
	end

	function adapter.setProp(handle: any, prop: string, value: any, _authority: string)
		-- THE HANDLED-PROP GATE (SF-M9). A prop this adapter does not declare is a
		-- prop the live adapter is probably not implementing either, and recording it
		-- silently is how a headless-green/live-broken channel ships.
		if not HANDLED[prop] then
			error(
				`FakeTarget: setProp('{prop}') is not a declared handled prop. Add it to `
					.. "tests/lib/fake_target's HANDLED_PROPS *and* to screen_target's setProp switch — "
					.. "tests/render_target_contract.spec.luau pins the two together (SF-M9).",
				0
			)
		end
		handle.props[prop] = value
		if prop == "role" and handle.focused then
			adapter.setFocusVisual(handle, true, handle.focusProfile)
		end
		if recordOps then
			note(`prop {handle.path}.{prop}={tostring(value)}`)
		end
		if handle.tagState ~= nil then
			--[[ the three writes that re-classify, mirroring the live adapter's own
				handle bookkeeping: `screen_paint.applySurfaceNative` (a `plain` or
				`scrim` surface CLEARS the surface tag and stops advertising
				interaction), `setProp`'s `role` branch (`default` means no role tag)
				and its `selected` branch. ]]
			local state = handle.tagState
			local touched = false
			if prop == "surface" then
				local name = if type(value) == "string" then value else nil
				state.surface = if name == "plain" then nil else name
				state.interactive = name ~= "plain"
					and name ~= "scrim"
					and (handle.class == "Button" or handle.class == "Toggle")
				touched = true
			elseif prop == "role" then
				state.buttonRole = if value == "default" or value == nil then nil else tostring(value)
				touched = true
			elseif prop == "selected" then
				state.selected = value == true
				touched = true
			end
			if touched then
				syncFakeTags(handle)
			end
		end
		if prop == "clipChildren" and value == true then
			-- an authored clip host, registered at the PROP WRITE exactly as the live
			-- adapter does. The renderer writes this before it recurses into the
			-- node's children, so a child created afterwards finds the host already
			-- there — the same ordering the live adapter relies on.
			registerFakeHost(handle.path, true)
		end
		-- A PADDED TEXT LEAF'S `UIPadding`, mirrored (device round 2026-08-12,
		-- IMG_3691). The live adapter materializes ONE `UIPadding` under a padded
		-- TextLabel and writes all four sides into it, and materializes NOTHING for
		-- an unpadded label. Mirrored here for the same reason the gradient child
		-- below is: the defect being closed was a padding the solver MEASURED and
		-- nothing PAINTED, so "the glyphs are really drawn inside the box" has to be
		-- an assertion rather than a write nobody follows to the engine.
		if prop == "padding" and handle.class == "Text" then
			local sides = { top = 0, right = 0, bottom = 0, left = 0 }
			if type(value) == "number" then
				sides = { top = value, right = value, bottom = value, left = value }
			elseif type(value) == "table" then
				for _, side in { "top", "right", "bottom", "left" } do
					sides[side] = if type((value :: any)[side]) == "number" then (value :: any)[side] else 0
				end
			end
			local any = sides.top ~= 0 or sides.right ~= 0 or sides.bottom ~= 0 or sides.left ~= 0
			if handle.textPadding == nil and any then
				handle.textPadding = { className = "UIPadding", creations = 0 }
			end
			if handle.textPadding ~= nil then
				handle.textPadding.creations += 1
				handle.textPadding.sides = sides
			end
		end
		-- THE PER-VIEW GRADIENT'S CHILD, mirrored (charter cap 11). The real
		-- adapter materializes ONE named `UIGradient` from this data and REUSES
		-- it; the same contract is mirrored here — same reason
		-- KEYBOARD_TYPE_ENGINE_NAME is — so "the modifier was APPLIED, not just
		-- emitted" is provable without an engine. Keep the two in lockstep.
		if prop == "gradient" then
			if value == nil then
				handle.gradientInstance = nil
			else
				local live = handle.gradientInstance
				if live == nil then
					live = { className = "UIGradient", name = "FacetGradient", creations = 0 }
					handle.gradientInstance = live
				end
				live.creations += 1
				live.colorStops = value.colors
				live.alphaStops = value.transparency
				live.rotation = value.rotation
				live.enabled = value.enabled
			end
		elseif prop == "stroke" then
			-- the authored border's ONE bespoke child, mirrored like the gradient's:
			-- reused rather than re-created, so "a pulse never stacks two borders"
			-- is provable headless
			if value == nil then
				handle.strokeInstance = nil
			else
				local live = handle.strokeInstance
				if live == nil then
					live = { className = "UIStroke", name = "FacetStroke", creations = 0 }
					handle.strokeInstance = live
				end
				live.creations += 1
				live.thickness = value.thickness
				live.color = value.color
				live.transparency = value.transparency
				live.applyStrokeMode = "Border"
			end
		elseif prop == "tint" then
			-- the CONTINUOUS COLOUR, mirrored through the SAME pure resolver the live
			-- adapter uses, and with the same CLAIMS recorded: a tint's whole contract
			-- is "this node took these engine properties from the sheet", so a mirror
			-- that only recorded the value would prove emission and not application.
			if value == nil then
				handle.tintSpec = nil
				handle.tintColor = nil
				handle.tintTransparency = nil
			else
				-- the SPEC is kept, not just the colour it resolved to: a theme commit
				-- has to re-resolve it (mirrors screen_paint.refreshThemedPaint, where
				-- the live adapter keeps `handle.tint` for the same reason)
				handle.tintSpec = value
				handle.tintColor = sheet_model.tintColor(paletteTheme(), value, handle.class)
				-- the tint's own ALPHA, mirrored through the same pure resolver (which
				-- also refuses a Path, where the engine has no such channel)
				handle.tintTransparency = sheet_model.tintTransparency(value, handle.class)
				handle.paintClaims = handle.paintClaims or {}
				for _, engineProp in TINT_ENGINE_PROP[handle.class] or {} do
					handle.paintClaims[engineProp] = true
				end
				if (value :: any).transparency ~= nil then
					for _, engineProp in TINT_ALPHA_ENGINE_PROP[handle.class] or {} do
						handle.paintClaims[engineProp] = true
					end
				end
			end
		elseif prop == "points" and handle.pathStroke ~= nil then
			-- the same seam `screen_props` writes on the live target
			handle.normPoints = value
			applyFakePathPoints(handle)
		elseif prop == "role" and handle.class == "Path" then
			-- A `UI.Path`'s STROKE COLOUR, mirrored (director report 2026-08-14). A
			-- Path2D is not a GuiObject and no rule can select one, so the live
			-- adapter resolves this itself against the installed theme — which makes
			-- it exactly the kind of paint a headless target must model, or "the ring
			-- is the theme's accent" stays an assumption.
			handle.pathRoleColor = pathRoleColor(value)
		elseif prop == "imageFraming" then
			handle.imagePlan = if value ~= nil
				then imageFraming.resolve(value, (handle.rect or {}).w or 0, (handle.rect or {}).h or 0)
				else nil
		elseif prop == "scaleMode" then
			handle.appliedScaleType = if value == nil then nil else SCALE_MODE_ENGINE_NAME[tostring(value)]
			if value ~= nil then
				handle.paintClaims = handle.paintClaims or {}
				handle.paintClaims.ScaleType = true
			end
		elseif prop == "transform" then
			-- offset composes onto the rect for this node AND its subtree; scale and
			-- rotation are paint on the node's own instance (the live target's UIScale
			-- child and GuiObject.Rotation)
			handle.motionScaleInstance = if type(value) == "table"
					and type(value.scale) == "number"
					and (value.scale ~= 1 or handle.motionScaleInstance ~= nil)
				then { className = "UIScale", name = "FacetMotionScale", scale = value.scale }
				else nil
			handle.rotation = if type(value) == "table" and type(value.rotation) == "number" then value.rotation else 0
			local prefix = handle.path .. "/"
			for path, node in nodes do
				if path == handle.path or string.sub(path, 1, #prefix) == prefix then
					adapter._composePresentation(node)
				end
			end
		elseif prop == "transparency" then
			-- ONE property, on a declared fade group, that no rule owns
			if handle.canvasGroupInstance ~= nil then
				handle.canvasGroupInstance.groupTransparency = if type(value) == "number"
					then math.clamp(value, 0, 1)
					else 0
			end
		end
	end

	function adapter.remove(handle: any)
		handle.alive = false
		-- the host record dies with the node, mirroring `dropPath`: a stale entry
		-- keeps re-parenting new nodes into a destroyed instance, which is the one
		-- way a flat tree can lose a whole subtree silently
		unregisterFakeHost(handle.path)
		-- ...and the node leaves the host ABOVE it on the same terms `park` does
		releaseFakeHostMembership(handle)
		nodes[handle.path] = nil
		unindexNode(handle.path)
		if recordOps then
			note(`remove {handle.path}`)
		end
		adapter._cancelIfCaptured(handle, "removed")
	end

	-- ---- instance recycling, mirrored ---------------------------------------
	-- The fake target implements the same three-call contract as the live adapter
	-- so the differential test below can run the SAME scenario with recycling on
	-- and off and compare the resulting virtual state. Its eligibility rule is
	-- deliberately the same SHAPE as the live one (refuse anything carrying
	-- adapter-owned state) even though this target grows far less of it — a fake
	-- that accepts what the real one refuses would prove the wrong thing.
	function adapter.park(handle: any): boolean
		if handle == nil or handle.alive ~= true then
			return false
		end
		if handle.canvasGroupInstance ~= nil or handle.decoration ~= nil then
			return false
		end
		--[[ A REGISTERED HOST TRAVELS ONLY IF IT IS PLAIN AND EMPTY, mirroring
			`parkEligible`'s narrowed rule (T4b).

			The refusal used to be `instanceHosts[handle.path] ~= nil` — every host — and
			it was called the migration's sharpest trade here for good reason. Plan C's
			C1 made every reactive-placement container with children a host, and the
			arena's `removeItem` class went +21.3 % on plate roots the sweep destroyed
			instead of pooling.

			What is still refused is what a fresh `create` could not reproduce for the
			adopter: a CROPPING host (a fade group's buffer, an authored `clipChildren`,
			a `ScrollView` — construction decisions), and a host that still has
			CHILDREN, which would travel with somebody else's subtree inside it. The
			renderer sweeps departed paths deepest-first so that second test is asked
			after the children have left. ]]
		local hostEntry = instanceHosts[handle.path]
		if hostEntry ~= nil and (hostEntry.crops == true or #hostEntry.children > 0) then
			return false
		end
		-- a Stage carrying LIVE CONTENT (the live adapter's WorldModel holds models
		-- the caller parented there) is refused: recycling one would hand a new
		-- identity somebody else's scene. Keyed on the CONTENT SEAM, mirroring the
		-- live adapter's `handle.stageWorld ~= nil` — NOT on the class name
		-- (platform review N3: on a hasStage == false engine a DEGRADED Stage is
		-- a plain Frame and IS parkable live, so a class-name refusal here made
		-- the fake stricter than the adapter it mirrors).
		if handle.stageApi ~= nil then
			return false
		end
		-- a FOREIGN box is refused for the same reason and one step earlier: it is
		-- refused whether or not anything has been adopted yet, because the caller
		-- may adopt at any time and there is no engine-degrade case that turns a
		-- Foreign into an ordinary Frame (mirrors the live `handle.foreignBox`).
		if handle.foreignBox ~= nil then
			return false
		end
		-- MIRROR THE LIVE ADAPTER'S REFUSALS. `screen_target.park` refuses a node
		-- carrying a presentation transform, because that record is keyed to the path
		-- and a recycled instance would inherit an offset nothing is driving. A fake
		-- that accepts what the real adapter refuses proves the wrong thing — this one
		-- did, and a re-created path came back at -50 instead of at rest.
		if handle.props ~= nil and handle.props.transform ~= nil then
			return false
		end
		nodes[handle.path] = nil
		unindexNode(handle.path)
		-- the two registration facts `park` releases and `adopt` re-earns, mirroring
		-- the live adapter: membership of the host above, and — since T4b made a plain
		-- host parkable — this node's OWN entry, which would otherwise hand a later
		-- node at this path a parent that has left the tree
		releaseFakeHostMembership(handle)
		unregisterFakeHost(handle.path)
		handle.parked = true
		handle.alive = false
		-- PROPERTIES SURVIVE, mirroring the live adapter. The renderer now writes only
		-- what differs on adoption. T8 R2 (review Critical 1) — THE INVARIANT THIS
		-- COMMENT USED TO STATE WAS FALSE: the pool does NOT only ever hand a node to
		-- a consumer declaring the same property names; it hands a node to a
		-- consumer whose BINDING ∪ STYLE PROPS worn-set matches (`render/recycle_key.luau`),
		-- which is the namespace the CREATE-time key and the park-time key both sign
		-- from — narrowing that namespace on only one side (W1b's own regression) is
		-- exactly what let a Button adopt an instance still wearing a previous
		-- occupant's `enabled = false`. LAYOUT props are the one channel that CAN
		-- legitimately differ across an adoption — `commit_walks.luau`'s value-diffed
		-- writes (padding's own explicit un-pad branch among them) are what keep
		-- THOSE honest, not the recycle key. Clearing here would model an adapter
		-- that does not exist and would hide the property diff entirely.
		if recordOps then
			note(`park {handle.path}`)
		end
		adapter._cancelIfCaptured(handle, "removed")
		return true
	end

	function adapter.adopt(
		handle: any,
		newPath: string,
		newClass: string,
		hint: any,
		rootHandle: any,
		createOpts: any
	): boolean
		if handle == nil or handle.parked ~= true or handle.class ~= newClass then
			return false
		end
		-- MIRROR THE LIVE ADAPTER'S HINT GATE (L-28). The decoration hint arrives
		-- through `create` and no later setter re-plans it, so a node adopted under
		-- a DIFFERENT hint would keep the wrong chrome plan forever. Content, not
		-- address: the renderer rebuilds hint tables on every window slide.
		if chrome_slots.hintKey(handle.decorationHint) ~= chrome_slots.hintKey(hint) then
			return false
		end
		handle.parked = nil
		handle.alive = true
		handle.path = newPath
		--[[ WHERE AN ADOPTED NODE LANDS, mirroring the live adapter exactly. `park`
			unparented this instance, so `adopt` has to parent it again: into its
			instance host if it has one, and otherwise under the root of the surface
			doing the adopting — which the renderer now passes in (NM-H4a).

			`lastCreatedRoot` is the answer this used to give, and it stays as the
			fallback for a caller that passes no root — which is also exactly the
			shipped defect, so reverting the renderer's one extra argument reddens
			the regression in `instance_recycling.spec` without touching this file.
			A fake with no parent record at all is how 288 headless replays of this
			defect saw nothing. ]]
		--[[ ...AND THE HOST ENTRY ITSELF, re-resolved for the NEW path and written
			unconditionally, the `nil` included (Plan C), mirroring the live `adopt`.
			This handle carried its PREVIOUS path's host, which was invisible while the
			field only fed the park refusal and the engine-write mirror — and is not
			invisible once `_composePresentation` reads the chain to decide whether a
			stored rect is host-relative: an adopted node under a coordinate-space host
			would compose against the host it used to live under, or against none. ]]
		--[[ ...AND THE NODE'S OWN REGISTRATION, re-earned from the ADOPTER's creation
			options and never carried across (T4b, mirroring the live `adopt`). A plain
			host parks now, so an adoption can put a real parent back into the tree; the
			bucket key answers "host" for a coordinate space and for a rotated container
			alike, so `hostSpace` has to come from the node being mounted or a whole
			subtree ends up stored against an origin nobody composes back. ]]
		if createOpts ~= nil and (createOpts :: any).instanceHost == true then
			local entry = registerFakeHost(newPath, false, (createOpts :: any).hostSpace == true)
			--[[ ...AND THE ENTRY IS BORN AT THE RECT THE INSTANCE IS ALREADY AT, which
				is the live adapter's third `registerHost` argument (`handle.windowRect`,
				the same table `setRect` writes into the entry) and is NOT optional here.
				The renderer carries `lastRects` across an adoption and skips a rect write
				that would land on the same numbers — a plate re-appearing at the position
				its predecessor left is the COMMON case in a windowed list — so an entry
				born at `nil` can stay there for the life of the node, and every child
				beneath it composes against an origin of zero. Found by the differential,
				which reported the whole subtree at its host-relative rect. ]]
			entry.rect = handle.storedRect
		end
		local newHost = hostFor(newPath)
		handle.instanceHost = newHost
		if newHost ~= nil then
			table.insert(newHost.children, handle)
		end
		handle.parentRoot = if newHost ~= nil
			then handle.parentRoot
			else (if rootHandle ~= nil then rootHandle else lastCreatedRoot)
		nodes[newPath] = handle
		-- THE OLD KEY IS LEFT IN THE INDEX ON PURPOSE (T12 correction). `nodes`
		-- itself never deletes the old path here either (see the three
		-- `nodes[...] = nil` sites this file actually has: remove, park,
		-- destroyRoot — adopt is not one of them), and `spaceOriginOf` walks
		-- `handle.instanceHost`, never the composed node's own path, so today's
		-- prefix walk still visits the stale entry. Matching that set is the
		-- requirement; fixing the leak is a separate change with its own oracle.
		indexNode(newPath)
		if recordOps then
			note(`adopt {newPath} ({newClass})`)
		end
		adapter._composePresentation(handle)
		return true
	end

	function adapter.discardParked(handle: any)
		if handle ~= nil then
			handle.parked = nil
			handle.alive = false
			if recordOps then
				note(`discard {handle.path}`)
			end
		end
	end

	-- THE OPERATION LOG, READ-ONLY. Recorded since this target was written and
	-- never exposed, which meant no spec could assert the ORDER two adapter calls
	-- arrive in — and order is exactly what decides whether a nested subtree is
	-- re-based against a current origin or a stale one.
	function adapter.ops(): { string }
		assert(
			recordOps,
			"fake_target: the op log is opt-in — build this target with fake_target.new({ ops = true })"
		)
		return ops
	end

	-- THE HOST REGISTRY, READ-ONLY, for the specs that assert who is a real parent
	-- and what that costs the pool. `hostOf` answers the nearest registered
	-- ANCESTOR (what a node parents under); `isHost` answers about the path itself.
	function adapter.hostOf(path: string): any
		local node = nodes[path]
		return if node ~= nil then node.instanceHost else nil
	end
	--[[ THE WINDOW-SPACE RECT, BY ITS EXPLICIT NAME — the same number
		`controller.rectOf` answers and the same table `node.rect` already holds (see
		`setRect`). It exists so a rule that MEANS "wherever this node is on screen,
		whatever space it is stored in" can say so at the call site instead of relying
		on a reader knowing that `node.rect` is composed. `node.storedRect` is the
		other half: exactly what the renderer handed the adapter. ]]
	function adapter.composedRect(path: string): any
		local node = nodes[path]
		return if node ~= nil then node.rect else nil
	end

	function adapter.isHost(path: string): boolean
		return instanceHosts[path] ~= nil
	end
	--[[ ...and WHICH KIND of host, which `isHost` cannot say and T4b made worth
		asking: `nil` for a path that is not registered at all, and otherwise the
		coordinate-space flag itself. A parked plain host can be adopted by a node
		with the OPPOSITE flag (`kindOf` answers `"host"` for both a coordinate space
		and a rotated container), so "it is a host again" is not the claim that
		matters after an adoption — "it is a host of the ADOPTER's kind" is. ]]
	function adapter.hostSpaceAt(path: string): boolean?
		local entry = instanceHosts[path]
		return if entry == nil then nil else entry.hostSpace == true
	end
	function adapter.hostCount(): number
		local n = 0
		for _ in instanceHosts do
			n += 1
		end
		return n
	end

	-- THE ENGINE-WRITE MIRROR (Plan C, T0): the live `applyRect` compares the pair
	-- it is about to write against the pair it wrote last (`handle.lastWriteX/Y`,
	-- `lastWriteW/H`) and skips an equal one. Mirrored here at the same
	-- granularity — Position and Size counted separately — so a headless
	-- demonstrator can pin the collapse a real parent buys instead of inferring it.
	function adapter.engineWrites(): number
		return engineWriteCount
	end

	function adapter.setZOrder(handle: any, z: number)
		handle.z = z
		-- ...and the stroke, which the walk never visits (live: `handle.path2d.ZIndex = z`)
		if handle.pathStroke ~= nil then
			handle.pathStroke.zIndex = z
		end
		if recordOps then
			note(`z {handle.path}={z}`)
		end
	end

	-- cross-surface z (modal-dismissal spec §2.2): whole-root display order. The
	-- presenter orders base < scrim < modal so the synthesized scrim sits beneath
	-- its owner; tests read it back via rootDisplayOrder(screenId).
	local rootDisplayOrders: { [string]: number } = {}
	function adapter.setRootDisplayOrder(rootHandle: any, n: number)
		rootHandle.displayOrder = n
		rootDisplayOrders[rootHandle.id] = n
		if recordOps then
			note(`displayOrder {rootHandle.id}={n}`)
		end
	end
	function adapter.rootDisplayOrder(screenId: string): number?
		return rootDisplayOrders[screenId]
	end

	function adapter.destroyRoot(rootHandle: any)
		rootCount -= 1
		rootHandle.alive = false
		for path, node in nodes do
			if node.root == rootHandle then
				node.alive = false
				unregisterFakeHost(path)
				nodes[path] = nil
				unindexNode(path)
				adapter._cancelIfCaptured(node, "destroyed") -- teardown: no keep-alive
			end
		end
		-- a kept-alive capture (lift) points at a node already REMOVED from
		-- the map — mirror production: THIS root's own teardown still ends
		-- it. `pointerCapture.root` survives `remove()` (which clears the
		-- `nodes` map entry, never the node's own fields), so it is still
		-- answerable here even though the node is already gone from `nodes`.
		--
		-- SCOPED to `rootHandle`, not unconditional (verifier 2026-07-20 F4
		-- shipped this unconditional; row-actions Task 10 found the gap it
		-- left: the SAME adapter-wide `pointerCapture` slot can belong to a
		-- gesture on a COMPLETELY DIFFERENT, still-live root — the
		-- presenter's own transient popup-catcher root is mounted/retired
		-- reactively as any `outsideDismiss.active` readable changes, and an
		-- unconditional cancel here cancelled an unrelated row's own
		-- still-live drag out from under it the instant some OTHER row's
		-- tray closed via the shared coordinator. Mirrors the identical fix
		-- in screen_target.luau's own `destroyRoot`.
		if pointerCapture ~= nil and pointerCapture.root == rootHandle then
			adapter._cancelIfCaptured(pointerCapture, "destroyed")
		end
		if recordOps then
			note("destroyRoot")
		end
	end

	function adapter.setActivateHandler(handle: any, fn: () -> ())
		handle.onActivate = fn
	end

	-- setFocusVisual(handle, on, profile?): the optional third arg is the env
	-- distanceProfile ("ten-foot" | "near", UI-PARADIGM-003 matrix D.4). Recorded
	-- so tests can prove the focus treatment differs between display classes; a
	-- 2-arg call (older renderer) leaves focusProfile nil, unchanged behavior.
	function adapter.setFocusVisual(handle: any, on: boolean, profile: string?)
		handle.focused = on
		if on then
			handle.focusProfile = profile
			-- ten-foot focus LIFT mirror (director live find 2026-07-21): the
			-- lift is a card idiom — it applies only when the lifted bounds
			-- still fit the screen (a scaled full-width surface would overflow
			-- the viewport, as the Xbox filter field did live). Mirrors the
			-- screen_target rule so the cap is headlessly provable.
			if profile == "ten-foot" and handle.rect ~= nil and handle.props.role ~= chrome_slots.ON_INDICATOR_ROLE then
				local scale = default_style.extra.tenFootFocusScale
				local screen = nil
				local rootSegment = string.match(handle.path or "", "^(/[^/]+)")
				if rootSegment ~= nil and nodes[rootSegment] ~= nil then
					screen = nodes[rootSegment].rect
				end
				local rect = handle.rect
				handle.focusLift = screen == nil
					or (
						rect.x + rect.w * scale <= screen.x + screen.w
						and rect.y + rect.h * scale <= screen.y + screen.h
					)
			else
				handle.focusLift = false
			end
		end
		if recordOps then
			note(`focus {handle.path}={tostring(on)}`)
		end
	end

	-- pointer hover layer (UI-PARADIGM-001): the renderer calls enableHover only
	-- for interactive nodes when the pointer class is live, so a pure-touch tree
	-- never marks a node hover-capable. hover/unhover then flip the recorded
	-- hover state only where it was enabled (headless mirror of MouseEnter/Leave).
	function adapter.setHoverObserver(handle: any, callback: any): () -> ()
		handle.hoverObserver = callback
		return function()
			handle.hoverObserver = nil
		end
	end

	function adapter.enableHover(handle: any)
		handle.hoverEnabled = true
	end

	-- full-value disclosure engagement zones (Step 8.5, LTN-4): the headless
	-- mirror records the wiring per half; specs drive the presenter's seams
	-- directly, and the wiring specs read `discloseZones` to assert the
	-- renderer's per-class gating. Calls MERGE per half like the real adapter.
	function adapter.enableDisclosure(handle: any, callbacks: any)
		handle.discloseZone = handle.discloseZone or {}
		if callbacks.hover ~= nil and handle.discloseZone.hover == nil then
			handle.discloseZone.hover = callbacks.hover
		end
		if callbacks.longPress ~= nil and handle.discloseZone.longPress == nil then
			handle.discloseZone.longPress = callbacks.longPress
		end
	end

	-- pointer seam: capture-based routing + semantic cursor hints,
	-- mirroring the ScreenTarget contract (down captures; moves/up route to
	-- the captured node until release; a captured drag keeps its hint alive)
	function adapter.setPointerHandlers(handle: any, handlers: any)
		handle.pointer = handlers
	end

	-- wheel scrolling (Phase 4 touch-scroll design): tests drive it directly
	function adapter.setScrollHandler(handle: any, fn: (number) -> ())
		handle.scrollHandler = fn
	end
	function adapter.scrollWheel(path: string, delta: number)
		local node = nodes[path]
		if node and node.scrollHandler then
			node.scrollHandler(delta)
		end
	end

	-- native scroll host seam (native-substrate NS-A2): the headless mirror of
	-- ScreenTarget's ScrollingFrame canvas. The fake records the declared
	-- region + programmatic position, and driveScroll() is the HEADLESS SCROLL
	-- DRIVER — it stands in for the engine moving CanvasPosition and fires the
	-- renderer's observer exactly like a real user fling would.
	-- scroll indicator policy, mirrored (director ruling 2026-08-09; reserve half
	-- reversed 2026-08-12; "auto" half of THAT reversed again 2026-08-28 — see
	-- `SCROLL_BAR_THICKNESS`'s own header above and
	-- `src/client/screen_scroll_indicators.luau`'s file header for the full
	-- ruling chain). The fake records the POLICY FACTS and derives the same
	-- reserve rule the live adapter derives — "always" reserves, "auto" does
	-- not — so a headless world proves the event order (flash on first
	-- overflow, show on scroll, fade scheduled) and the layout invariant without
	-- an engine. The configured thickness a spec opted into is captured on the
	-- first call, because the presenter applies the boot policy during
	-- construction.
	function adapter.setScrollIndicatorPolicy(policy: string, reduced: boolean?)
		if adapter._configuredBarThickness == nil then
			adapter._configuredBarThickness = adapter.scrollBarThickness or 0
		end
		adapter.scrollIndicatorPolicy = if policy == "auto" then "auto" else "always"
		adapter.scrollIndicatorReduced = reduced == true
		-- THE POLICY MOVES THE RESERVE AGAIN, BUT ONLY FOR "auto" (director ruling
		-- 2026-08-28): "always" still charges the window for the bar instance
		-- (2026-08-12, unchanged); "auto" publishes zero, paired with
		-- `_deriveWindowRect`'s widen below so the zero reserve does not
		-- reproduce 2026-08-09's clip.
		adapter.scrollBarThickness = if adapter.scrollIndicatorPolicy == "auto"
			then 0
			else adapter._configuredBarThickness
		if recordOps then
			note(`indicatorPolicy {adapter.scrollIndicatorPolicy} reduced={tostring(reduced == true)}`)
		end
	end

	--[[ THE ENGINE WINDOW, DERIVED FROM THE TWO THINGS IT DEPENDS ON — this host's
		live rect and its declared region. Called from BOTH writers (`setRect` and
		`setScrollRegion`) because either one can move it, and it used to be
		computed in only the second: a host that was re-positioned or re-sized
		without its canvas changing kept answering with the window of the box it no
		longer occupied.

		"auto" LOSES NOTHING (director ruling 2026-08-28): the live adapter widens
		the FRAME by the bar's thickness whenever the scroll axis overflows under
		"auto" (`applyBarOverlayWiden`), which cancels the engine's own narrowing
		one-for-one — the net window a player sees is the FULL rect either way.
		The fake has no separate "instance Size vs solved rect" to widen, so it
		models the NET OUTCOME directly: `lost` is zero under "auto", full under
		"always", exactly like the live pair (widen + narrow) resolves to. ]]
	function adapter._deriveWindowRect(handle: any, region: any)
		local rect = handle.rect
		if region == nil or rect == nil then
			handle.windowRect = nil
			handle.barInstanceThickness = nil
			return
		end
		local bar = if region.indicators == "none" then 0 else fake_target.SCROLL_BAR_THICKNESS
		handle.barInstanceThickness = bar
		local isX = region.axis == "x"
		local overflows = if isX then (region.contentW or 0) > rect.w + 1 else (region.contentH or 0) > rect.h + 1
		local lost = if overflows and adapter.scrollIndicatorPolicy ~= "auto" then bar else 0
		handle.windowRect = {
			x = rect.x,
			y = rect.y,
			w = if isX then rect.w else math.max(0, rect.w - lost),
			h = if isX then math.max(0, rect.h - lost) else rect.h,
		}
	end

	function adapter.setScrollRegion(handle: any, region: any)
		handle.scrollRegion = region
		handle.indicatorsOff = region ~= nil and region.indicators == "none" or nil
		handle.scrollPosition = handle.scrollPosition or { x = 0, y = 0 }
		-- THE WINDOW IS NOT THE FRAME (device round 2026-08-12; the instrument this
		-- suite did not have). A `ScrollingFrame`'s VISIBLE box is narrower than its
		-- own rect by the BAR THICKNESS on the cross axis whenever the scroll axis
		-- overflows — even at `ScrollBarInset.None`, which is the engine fact
		-- `src/client/screen_target.luau` records at its cross-axis canvas clamp and
		-- spends on the canvas only. The LAYOUT reserve is a separate number
		-- (`adapter.scrollBarThickness`), so the two CAN disagree — and when they
		-- did, the difference was content laid out outside the window and clipped by
		-- the engine, which no headless check could see because the fake modelled no
		-- window at all. They agree now: the 2026-08-12 reversal publishes the
		-- reserve under every indicator policy, and this model is what proves it.
		--
		-- The instance thickness is NOT the published reserve: the live adapter
		-- creates every scroll host with `ScrollBarThickness = SCROLL_BAR_THICKNESS`
		-- and only zeroes it for a host that declared `indicators = "none"`. Kept in
		-- lockstep with that file, exactly like `SCALE_MODE_ENGINE_NAME`.
		--
		-- ORDERING-HAZARD MIRROR (task SCROLL2 fix round 1, RED-TEAM finding 1):
		-- the REAL `applyBarOverlayWiden` (screen_scroll_indicators.setScrollRegion)
		-- writes `handle.barOverlayWidenW/H` from exactly this fact — does the
		-- scroll axis overflow its own arranged box — independently of
		-- `_deriveWindowRect`'s net-outcome window derivation above, because the
		-- ordering hazard this proves is about WHEN the write lands relative to
		-- `setRect`, not what window size results. `region.hostW/hostH` are the
		-- host's solved box (`commit_walks.scrollRegions`), so this needs no
		-- `handle.rect`, exactly like the real `setScrollRegion`.
		if region == nil then
			handle.barOverlayWidenW = nil
			handle.barOverlayWidenH = nil
		else
			local isXAxis = region.axis == "x"
			local hostW = if type(region.hostW) == "number" then region.hostW else 0
			local hostH = if type(region.hostH) == "number" then region.hostH else 0
			local overflowsAxis = if isXAxis
				then (region.contentW or 0) > hostW + 1
				else (region.contentH or 0) > hostH + 1
			local widenAmount = if overflowsAxis
					and adapter.scrollIndicatorPolicy == "auto"
					and region.indicators ~= "none"
				then fake_target.SCROLL_BAR_THICKNESS
				else 0
			if isXAxis then
				handle.barOverlayWidenH = if widenAmount > 0 then widenAmount else nil
				handle.barOverlayWidenW = nil
			else
				handle.barOverlayWidenW = if widenAmount > 0 then widenAmount else nil
				handle.barOverlayWidenH = nil
			end
		end
		adapter._deriveWindowRect(handle, region)
		table.insert(
			ops,
			if region == nil
				then `scrollregion {handle.path}=nil`
				else `scrollregion {handle.path} axis={region.axis} content={region.contentW}x{region.contentH}`
		)
	end

	-- the engine window of a scroll host, or nil for anything that is not one /
	-- has no region yet. The rect a test should compare a descendant against when
	-- the question is "can the player SEE this", rather than `node(path).rect`.
	function adapter.windowRectOf(path: string): any
		local handle = nodes[path]
		return if handle ~= nil then handle.windowRect else nil
	end
	-- engine-faithful clamp (verifier F3): CanvasPosition clamps to the
	-- scrollable extent (measured live: write 1000 -> 800 on a 1200/400 host)
	-- and the changed-signal only fires on an actual value change
	local function clampScroll(handle: any, pos: { x: number, y: number }): { x: number, y: number }
		local region = handle.scrollRegion
		local rect = handle.rect
		if region == nil or rect == nil then
			return { x = pos.x, y = pos.y }
		end
		return {
			x = math.clamp(pos.x, 0, math.max(0, (region.contentW or 0) - rect.w)),
			y = math.clamp(pos.y, 0, math.max(0, (region.contentH or 0) - rect.h)),
		}
	end
	--[[ MANY OBSERVERS PER NODE, BECAUSE THE ENGINE HAS MANY (2026-08-13) --------
		This used to be ONE slot -- `handle.scrollObserver = fn` -- so a second
		`observeScroll` on the same node silently REPLACED the first, and the
		replaced one's unsubscribe then did nothing. `ScreenTarget.observeScroll`
		does the opposite: it opens an INDEPENDENT `GetPropertyChangedSignal(
		"CanvasPosition")` connection per call and returns a closure that
		disconnects only that one -- which is why its own connection census lists
		the CanvasPosition observer under "connections captured in closures rather
		than stored on a handle".

		The divergence was not theoretical. `Table.bindNativeScroll` registers TWO
		observers on the SAME body path -- the `scrollTop` CanvasPosition mirror,
		then (for a table that declares `rowActions`) the coordinator's
		scroll-closes-the-open-tray -- and the second landing on top of the first
		left the mirror DEAD in every headless fixture: `dump().scrollTop` read 0
		after a scroll the engine would have reported as 120. A fake target that
		cannot hold what the real one holds does not fail loudly; it reports a
		wrong number confidently, which is worse.

		So: a LIST, fired in registration order, each unsubscribe removing exactly
		its own entry and idempotent (calling it twice must not evict somebody
		else's). `handle.scrollObserver` is kept as a mirror of the FIRST live
		registration so the handler-slot census below counts a scroll observer
		exactly as it did before.
	]]
	local function fireScrollObservers(handle: any)
		local list = handle.scrollObservers
		if list == nil then
			return
		end
		-- iterate a COPY: an observer may unsubscribe itself or a sibling while it
		-- runs, and a live-mutated array would skip the next entry
		for _, entry in table.clone(list) do
			if entry.live then
				entry.fn(handle.scrollPosition)
			end
		end
	end
	function adapter.setScrollPosition(handle: any, pos: { x: number, y: number })
		local clamped = clampScroll(handle, pos)
		local previous = handle.scrollPosition
		handle.scrollPosition = clamped
		if recordOps then
			note(`scrollpos {handle.path}={clamped.x},{clamped.y}`)
		end
		local changed = previous == nil or previous.x ~= clamped.x or previous.y ~= clamped.y
		if changed then
			fireScrollObservers(handle)
		end
	end
	function adapter.observeScroll(handle: any, fn: (pos: { x: number, y: number }) -> ()): () -> ()
		local list = handle.scrollObservers
		if list == nil then
			list = {}
			handle.scrollObservers = list
		end
		local entry = { fn = fn, live = true }
		table.insert(list, entry)
		handle.scrollObserver = (list :: any)[1].fn
		return function()
			if not entry.live then
				return
			end
			entry.live = false
			for i, other in list do
				if other == entry then
					table.remove(list, i)
					break
				end
			end
			handle.scrollObserver = if #list > 0 then (list :: any)[1].fn else nil
		end
	end
	-- engine-selection bridge (NS-A12): records the mirrored path so tests can
	-- assert opt-in-only behavior and teardown clearing
	adapter.engineSelection = nil
	function adapter.setEngineSelection(handle: any?)
		adapter.engineSelection = if handle ~= nil then handle.path else nil
		if recordOps then
			note(`engineselection {if handle ~= nil then handle.path else "nil"}`)
		end
	end

	-- native drag acquisition mirror (NS-A5): stores handlers; driveDrag* stand
	-- in for the engine's UIDragDetector lifecycle. opts.noDragDetector on the
	-- fake constructor mimics an engine without the class (fallback tests).
	function adapter.setDragDetector(handle: any, handlers: any): (() -> ())?
		if adapter.noDragDetector then
			return nil
		end
		handle.dragDetector = handlers
		if recordOps then
			note(`dragdetector {handle.path}`)
		end
		return function()
			handle.dragDetector = nil
		end
	end
	function adapter.driveDragStart(path: string, pos: any)
		local node = nodes[path]
		if node and node.dragDetector and node.dragDetector.onStart then
			node.dragDetector.onStart(pos)
		end
	end
	function adapter.driveDragContinue(path: string, pos: any, delta: any)
		local node = nodes[path]
		if node and node.dragDetector and node.dragDetector.onContinue then
			node.dragDetector.onContinue(pos, delta)
		end
	end
	function adapter.driveDragEnd(path: string, pos: any)
		local node = nodes[path]
		if node and node.dragDetector and node.dragDetector.onEnd then
			node.dragDetector.onEnd(pos)
		end
	end

	-- native touch-gesture mirror (NS-A6): stores the normalized-gesture sink;
	-- tests drive it with already-normalized value objects
	function adapter.setTouchGestureHandlers(handle: any, onGesture: (gesture: any) -> ()): () -> ()
		handle.touchGestures = onGesture
		return function()
			handle.touchGestures = nil
		end
	end
	function adapter.driveTouchGesture(path: string, gesture: any)
		local node = nodes[path]
		if node and node.touchGestures then
			node.touchGestures(gesture)
		end
	end

	-- the pointer's SECONDARY button (D2): the headless mirror stores the sink
	-- and `driveSecondaryActivate` is what a spec presses. The real adapter
	-- filters `InputBegan` to `MouseButton2`; there is no input object to fake
	-- here, so a spec drives the already-filtered outcome — which is why the
	-- native arbitration stays a physical row (NM-X2).
	function adapter.setPointerPreview(handle: any, fn: any): () -> ()
		handle.pointerPreview = fn
		return function()
			handle.pointerPreview = nil
		end
	end
	function adapter.pointerPreview(path: string, x: number, y: number)
		local node = nodes[path]
		if node and node.pointerPreview and pointerCapture == nil then
			node.pointerPreview({ x = x, y = y, pointerType = "mouse" })
		end
	end

	function adapter.setSecondaryActivate(handle: any, fn: () -> ()): () -> ()
		handle.secondaryActivate = fn
		return function()
			handle.secondaryActivate = nil
		end
	end
	function adapter.driveSecondaryActivate(path: string): boolean
		local node = nodes[path]
		if node and node.secondaryActivate then
			node.secondaryActivate()
			return true
		end
		return false
	end

	-- effective-target floor seam (B-BTN3): the framework asks for an expanded HIT
	-- area; the real adapter realises it as a transparent expander behind the
	-- control. `nil` removes it.
	function adapter.setVisible(handle: any, visible: boolean)
		handle.visible = visible
		if recordOps then
			note(`visible {handle.path}={tostring(visible)}`)
		end
	end
	function adapter.visibleOf(path: string): boolean?
		local node = nodes[path]
		return if node ~= nil then node.visible else nil
	end

	--[[ TWO RECTS HERE FOR THE SAME REASON `setRect` HAS TWO (Plan C, C1).
		`storedHitRect` is what the renderer handed over — the wanted band in the
		ENTRY's own space, which `applyHitExpander` re-bases by the host origin (zero
		under a coordinate space, because it is already relative). `hitRect` is where
		that band IS, which is what every rule comparing it against a neighbouring
		control's box means. Re-derived in `setRect` too, because the commit pushes
		hit rects BEFORE rects and the host origin can still be stale here — exactly
		the ordering the live `applyRect -> applyHitExpander` call answers. ]]
	function adapter.setHitRect(handle: any, rect: any)
		handle.storedHitRect = rect
		if rect == nil then
			handle.hitRect = nil
		else
			local sx, sy = spaceOriginOf(handle)
			handle.hitRect = if sx == 0 and sy == 0
				then rect
				else { x = rect.x + sx, y = rect.y + sy, w = rect.w, h = rect.h }
		end
		table.insert(
			ops,
			if rect == nil then `hitrect {handle.path}=nil` else `hitrect {handle.path} {rect.w}x{rect.h}`
		)
	end
	function adapter.hitRectOf(path: string): any
		local node = nodes[path]
		return if node ~= nil then node.hitRect else nil
	end

	-- the per-control sensory verb the renderer publishes (target_contract
	-- `setActivationFeedback`). Recorded, never acted on: the real adapter turns
	-- it into an attribute a haptics consumer reads, and the fake is where the
	-- "a recycled instance never inherits the previous control's verb" claim is
	-- provable without an engine.
	function adapter.setActivationFeedback(handle: any, verb: string?)
		handle.activationFeedback = verb
		if recordOps then
			note(`activationfeedback {handle.path}={tostring(verb)}`)
		end
	end
	function adapter.activationFeedbackOf(path: string): string?
		local node = nodes[path]
		return if node ~= nil then node.activationFeedback else nil
	end

	-- engine text premeasurement (text-measurement milestone). The renderer hands
	-- over the WORDS a solve could not size exactly; a real adapter answers off
	-- the render path. Here the batch is held so a test can play the engine
	-- deliberately — which is what makes the ordering claim ("first frame
	-- conservative, exactly one re-solve exact") provable headless.
	local textBatches: { { requests: { any }, done: (({ any }, boolean?) -> ())? } } = {}
	-- batches this target has already answered once, kept so `answerAgain` can
	-- replay the settled correction the live adapter sends (see below)
	local answeredBatches: { { requests: { any }, done: (({ any }, boolean?) -> ())? } } = {}
	local function forgetBatch(batch: any)
		-- releasing `done` is the whole point: it is the RENDERER's own closure,
		-- and it holds that surface's mounted tree
		batch.done = nil
		local pending = table.find(textBatches, batch)
		if pending ~= nil then
			table.remove(textBatches, pending)
		end
		local answered = table.find(answeredBatches, batch)
		if answered ~= nil then
			table.remove(answeredBatches, answered)
		end
	end
	--[[ SYNC-ANSWER MODE — THE SETTLED ENGINE, AS IT ACTUALLY BEHAVES.

		The default above QUEUES, which is right for a spec that plays the engine by
		hand and wrong for the one question that is about the STACK the answer runs
		on. On a live client `text_premeasure.spawn` is `task.spawn`, which runs its
		body synchronously until its first yield, and once the session has settled
		`measureBatch`'s `GetTextBoundsAsync` does not yield either — so the answer
		reaches `premeasure_round`'s `done` INSIDE the solve that asked for it.
		Measured live (T17, FacetBench §C15): `sync=1` on a one-step drive and
		`maxNestDepth=3` on an ordinary mount, with `C stack overflow (when calling
		anonymous function on line 484 in ...text_premeasure)` on a two-workload run.

		WITHOUT THIS MODE THE DEPTH PIN IS VACUOUS: delivered from top level, the
		re-entry depth reads 1 at HEAD and the red can never be red. The two
		witnesses it publishes are the ones probe D read live — the nesting of the
		answer bodies (`maxAnswerDepth`) and the Luau stack the deepest one ran on
		(`maxAnswerStack`, counted with `debug.info`, which is what an overflow is a
		consequence of). Both are recorded here rather than in `src/`: a counter
		inside the framework would be measuring its own claim.

		`answerAgain` still replays against these batches, and the cancel token
		still forgets them, so a disposed surface is not called back — the same
		promise the queued arm makes. ]]
	local syncAnswer: ((string, number, string) -> number?)? = nil
	local syncFinal: boolean? = nil
	local ownThread = false
	local answerErrors: { string } = {}
	local answerDepth = 0
	local maxAnswerDepth = 0
	local maxAnswerStack = 0
	local function stackDepth(): number
		local n = 0
		while debug.info(n + 1, "l") ~= nil do
			n += 1
		end
		return n
	end
	local function answerInline(batch: any)
		if batch.done == nil then
			return
		end
		local widthOf = syncAnswer :: (string, number, string) -> number?
		local results = {}
		for _, request in batch.requests do
			table.insert(results, {
				font = request.font,
				size = request.size,
				word = request.word,
				width = widthOf(request.word, request.size, request.font),
			})
		end
		answerDepth += 1
		maxAnswerDepth = math.max(maxAnswerDepth, answerDepth)
		maxAnswerStack = math.max(maxAnswerStack, stackDepth())
		local done = batch.done
		if ownThread then
			--[[ ...AND THE OTHER HALF OF THE LIVE SHAPE, which the first form of this
				mode did not have and which is exactly the gap that hid the error-path
				defect (T18-B review, Important 1). `text_premeasure.spawn` is
				`task.spawn`: a NEW THREAD, resumed synchronously, so the answer still
				reaches the renderer inside the solve that asked — and a THROW dies at
				the thread boundary and is reported by the scheduler instead of
				unwinding the caller. `coroutine.resume` is that shape exactly; the
				absorbed error is recorded so a spec can assert it rather than lose it. ]]
			local ok, err = coroutine.resume(coroutine.create(done), results, syncFinal)
			if not ok then
				table.insert(answerErrors, tostring(err))
			end
		else
			done(results, syncFinal)
		end
		answerDepth -= 1
	end
	--[[ turn the mode on (a `widthOf`) or off (`nil`), and reset the witnesses.
		`ownThread` picks which half of the live shape to reproduce: OFF answers on the
		caller's own stack (the cheapest reproduction of "the answer lands inside the
		solve"), ON answers on a fresh coroutine the way `task.spawn` does, which is the
		only arm that can see what a throwing re-solve does. ]]
	function adapter.answerTextInline(
		widthOf: ((string, number, string) -> number?)?,
		final: boolean?,
		onOwnThread: boolean?
	)
		syncAnswer = widthOf
		syncFinal = final
		ownThread = onOwnThread == true
		answerDepth = 0
		maxAnswerDepth = 0
		maxAnswerStack = 0
		table.clear(answerErrors)
	end
	-- the deepest NESTING of answer bodies, and the deepest Luau stack one ran on
	function adapter.textAnswerDepth(): number
		return maxAnswerDepth
	end
	function adapter.textAnswerStack(): number
		return maxAnswerStack
	end
	-- errors an `ownThread` answer absorbed at its thread boundary, the way the live
	-- scheduler absorbs them
	function adapter.textAnswerErrors(): { string }
		return table.clone(answerErrors)
	end
	--[[ RETURNS THE CANCEL TOKEN THE CONTRACT DESCRIBES, and it is a memory fact
		rather than a fidelity nicety (measured 2026-08-29).

		`src/render/target_contract.luau`'s `measureTextWidths` line says an adapter
		MAY return a nullary function the renderer calls on dispose, after which it
		must not invoke `done` again; `screen_target` returns one
		(`text_premeasure.measure`). This target returned nothing, which is legal —
		and meant a batch, and therefore the `done` closure the renderer handed
		over, was held HERE for the life of the process. That closure is
		`renderer.attach`'s own, so it keeps `solveAndApply`'s upvalues alive:
		`root`, the whole mounted node tree, every per-path map. So every screen
		with one unmeasured word that a long-lived headless process presented
		stayed in memory AFTER a complete `presenter.dismiss` — measured at ~5 KB
		per presented node, ~120 KB per twenty-button screen, unbounded in the
		number of cycles. A spec that plays the engine (`deliverTextWidths`) was no
		better: the answered batch moved to `answeredBatches` and was never dropped
		either. (This is the retention a present/dismiss loop on ONE adapter sees.
		The suite's own heap had a second, larger cause with the same shape —
		`src/render/surface_overlap.luau`'s registry — fixed in the same round.)

		The renderer already collects these tokens (`textMeasureCancels`) and calls
		them in `controller.dispose`, so nothing in `src/` changes. Cancelling
		drops the batch from BOTH lists and nils `done`, so a cancelled batch
		neither delivers nor retains — exactly what the live token promises. ]]
	function adapter.measureTextWidths(requests: { any }, done: (results: { any }, final: boolean?) -> ()): () -> ()
		-- NOT an op: asking the engine for word widths is an observation, not a
		-- write to the tree, and the minimal-writes assertions count writes
		local batch = { requests = requests, done = done }
		if syncAnswer ~= nil then
			table.insert(answeredBatches, batch)
			answerInline(batch)
			return function()
				forgetBatch(batch)
			end
		end
		table.insert(textBatches, batch)
		return function()
			forgetBatch(batch)
		end
	end
	function adapter.textBatchCount(): number
		return #textBatches
	end
	-- ...and the WHOLE request, descriptor included (F2). The font a batch asks
	-- about is the font the solver measured with, so this is the instrument that
	-- proves a typography role reached MEASUREMENT — read off the seam the engine
	-- would answer, never re-derived from the same function the renderer called.
	function adapter.pendingTextRequests(): { { word: string, size: number, font: string } }
		local out: { { word: string, size: number, font: string } } = {}
		for _, batch in textBatches do
			for _, request in batch.requests do
				table.insert(out, { word = request.word, size = request.size, font = request.font })
			end
		end
		table.sort(out, function(a, b)
			if a.font ~= b.font then
				return a.font < b.font
			end
			if a.size ~= b.size then
				return a.size < b.size
			end
			return a.word < b.word
		end)
		return out
	end
	function adapter.pendingTextWords(): { string }
		local out: { string } = {}
		for _, batch in textBatches do
			for _, request in batch.requests do
				table.insert(out, request.word)
			end
		end
		table.sort(out)
		return out
	end
	-- deliver every queued batch. widthOf(word, size, font) -> number, or nil
	-- for "the engine could not measure this one".
	local function answer(batches: { any }, widthOf: (string, number, string) -> number?, final: boolean?)
		for _, batch in batches do
			-- a CANCELLED batch (the surface that asked was disposed) is not owed
			-- an answer — the same promise the live cancel token makes
			if batch.done == nil then
				continue
			end
			local results = {}
			for _, request in batch.requests do
				table.insert(results, {
					font = request.font,
					size = request.size,
					word = request.word,
					width = widthOf(request.word, request.size, request.font),
				})
			end
			batch.done(results, final)
		end
	end
	-- final=false answers the batch WITHOUT closing it: the real adapter does
	-- this while the engine's boot window is still open, so the surface knows a
	-- trustworthy answer is still coming and a reveal gate keeps waiting.
	function adapter.deliverTextWidths(widthOf: (string, number, string) -> number?, final: boolean?)
		local batches = textBatches
		textBatches = {}
		for _, batch in batches do
			table.insert(answeredBatches, batch)
		end
		answer(batches, widthOf, final)
	end
	--[[ ...AND THE LIVE ASYMMETRY THE ONE ABOVE CANNOT REPRODUCE (Plan D, D3a):
		answer the MOST RECENT batch and leave every older one outstanding.

		`deliverTextWidths` answers everything, which is the settled engine. The BOOT
		window is not that shape: `client/text_premeasure.measureBatch` warms the font
		first (`ContentProvider:PreloadAsync`, which yields) and the FacetBench loop
		driver applies its steps in one unbroken Luau run, so the first big batch's
		thread never resumes while later, smaller batches are answered from a font that
		is already warm. That is the state S2 measured live — a large unanswered
		backlog with the drain still making one-word progress — and it is the state
		`tests/text_collect_inflight.spec.luau` has to mount in order to see the
		collector budget being eaten. ]]
	function adapter.deliverLatestTextWidths(widthOf: (string, number, string) -> number?, final: boolean?)
		local batch = textBatches[#textBatches]
		if batch == nil then
			return
		end
		table.remove(textBatches, #textBatches)
		table.insert(answeredBatches, batch)
		answer({ batch }, widthOf, final)
	end
	-- the real adapter re-reads a batch once the session has settled and answers
	-- the SAME batch again with corrections (the engine's boot answers are wrong
	-- but stable). This replays that second answer.
	function adapter.answerAgain(widthOf: (string, number, string) -> number?, final: boolean?)
		answer(answeredBatches, widthOf, final)
	end

	-- whole-root visibility (the reveal gate): a surface that must not be seen
	-- until its text is exact hides its ROOT, not each node
	local rootVisible: { [string]: boolean } = {}
	function adapter.setRootVisible(rootHandle: any, visible: boolean)
		rootVisible[rootHandle.id] = visible
		if recordOps then
			note(`rootvisible {rootHandle.id}={tostring(visible)}`)
		end
	end
	function adapter.rootVisibleOf(screenId: string): boolean?
		return rootVisible[screenId]
	end

	function adapter.getScrollPosition(handle: any): { x: number, y: number }?
		return handle.scrollPosition
	end

	-- THE ENGINE-CONTENT SEAM, MIRRORED (UI.Stage). The live adapter owns a
	-- ViewportFrame with a WorldModel and a Camera inside it; there are no
	-- Instances here, so this twin RECORDS instead: the same three verbs, through
	-- the same PURE rulings (`stage_content`), appending to an inspectable `calls`
	-- array and answering a stable content stub. That is what makes the seam's
	-- whole contract — the shapes it accepts, the shapes it refuses, the caching,
	-- and the death of a handle with its node — provable without Roblox.
	function adapter.stageHost(handle: any): any?
		if handle == nil or handle.class ~= "Stage" or handle.alive ~= true then
			return nil
		end
		if handle.stageApi ~= nil then
			return handle.stageApi
		end
		local content = { kind = "stage-content-stub" }
		local api: any = { calls = {} }
		local function assertLive()
			if handle.stageDisposed == true or handle.alive ~= true then
				error(stage_content.disposedError(handle.stagePath or handle.path), 0)
			end
		end
		function api.setCamera(spec: any)
			-- NORMALIZE FIRST, then record: a refusal must leave nothing behind, or
			-- a test could read a half-applied camera the live adapter never wrote
			local camera = stage_content.normalizeCamera(spec)
			assertLive()
			table.insert(api.calls, { method = "setCamera", spec = camera })
		end
		function api.setLighting(spec: any)
			local lighting = stage_content.normalizeLighting(spec)
			assertLive()
			table.insert(api.calls, { method = "setLighting", spec = lighting })
		end
		function api.contentRoot(): any
			assertLive()
			return content
		end
		-- the path is captured because `remove` clears the node's own entry, and
		-- the refusal must still be able to name the node that died
		handle.stagePath = handle.path
		handle.stageApi = api
		return api
	end

	--[[ THE FOREIGN-CONTENT SEAM, MIRRORED (UI.Foreign).

		The live adapter parents a caller's real GuiObject under a real clipping
		Frame; there are no Instances here, so this twin RECORDS. What makes the
		mirror worth having is that the half that DECIDES is pure: the refusal
		ladder lives in `foreign_content.assertAdmissible` and takes a description
		of the candidate rather than the candidate, so the fake states one directly
		(`{ present, className, isGuiObject, isLayerCollector, alive }`) and the live
		adapter builds the same five facts from `IsA` and a guarded Parent write.
		Every refusal a caller can hit is therefore provable without Roblox; what is
		NOT provable here — that the engine draws a VideoFrame inside a Frame — is
		the live Studio slice and this file does not pretend to it.

		IT RETAINS NOTHING. `adopt` records the CLASS NAME and the property claimed,
		never the candidate, which mirrors the live adapter's own structural
		guarantee: the framework cannot write a property of an instance it holds no
		reference to (tests/foreign.spec.luau walks the handle and proves it).
	]]
	function adapter.foreignHost(handle: any): any?
		if handle == nil or handle.class ~= "Foreign" or handle.alive ~= true then
			return nil
		end
		if handle.foreignApi ~= nil then
			return handle.foreignApi
		end
		local api: any = { calls = {} }
		local function assertLive()
			if handle.alive ~= true then
				error(foreign_content.disposedError(handle.foreignPath or handle.path), 0)
			end
		end
		function api.adopt(instance: any)
			-- LIVENESS FIRST, then the ladder: a handle whose node has died must say
			-- so rather than complain about the instance, because the instance is
			-- fine and the node is the thing that went away.
			assertLive()
			local candidate: any = if type(instance) == "table"
				then instance
				else {
					present = false,
					className = "",
					isGuiObject = false,
					isLayerCollector = false,
					alive = false,
				}
			foreign_content.assertAdmissible(handle.foreignPath or handle.path, candidate)
			table.insert(api.calls, {
				method = "adopt",
				className = candidate.className,
				property = foreign_content.CLAIMED_PROPERTY,
			})
		end
		-- the path is captured because `remove` clears the node's own entry, and the
		-- refusal must still be able to name the node that died
		handle.foreignPath = handle.path
		handle.foreignApi = api
		return api
	end

	-- ── the rest of the declared seam (SEAM-20) ─────────────────────────────
	-- These four were CALLED by the framework and implemented by the live
	-- ScreenTarget while the fake had no version at all, so the conformance case
	-- "satisfies every required and optional method" was true of a list that did
	-- not name them. Minimal recording implementations: they answer honestly for
	-- a headless target (it paints nothing natively) and let a test read back
	-- what the framework asked for.

	-- reduced motion, SHEET half: the renderer suppresses the target's NATIVE
	-- transition layer. Headless there is no such layer, so this records the
	-- request. (The BESPOKE half is `setReducedMotion` below.)
	local nativeTransitions: boolean? = nil
	function adapter.setNativeTransitionsEnabled(on: boolean)
		nativeTransitions = on
		if recordOps then
			note(`nativetransitions={tostring(on)}`)
		end
	end
	function adapter.nativeTransitionsEnabled(): boolean?
		return nativeTransitions
	end

	--[[ ADAPTER-OWNED MOTION, MODELLED (C1, 2026-08-12) ─────────────────────────
		The live ScreenTarget answers a press with a UIScale dip: a TweenService
		tween under full motion and NO tween at all under reduced motion, where the
		scale is written instantly instead (`screen_target.luau`
		`wireNativePressDip` / `recoverPressDip`, and the same fork in `setFill`
		and `applyToggleValue`). That decision is the ADAPTER'S, so a fake that
		modelled none of it could never see whether the fact reached the target —
		which is exactly why C1 survived: the only checks that mentioned
		`isReducedMotion` matched the SOURCE TEXT of screen_target.luau, and source
		text is true of a closure nobody calls.

		Headless there is no TweenService, so the fake records the DECISION the
		live adapter makes from the same input: one entry per press in
		`motionOps()`, `kind = "tween"` (full motion) or `kind = "instant"`
		(reduced). The fact it reads is the one the RENDERER pushes — there is no
		construction-time closure here on purpose, because a fake that accepted one
		would let the forgotten-opt defect back in through the instrument.
	]]
	local reducedMotion = false
	local motionOps: { { path: string, kind: string } } = {}
	function adapter.setReducedMotion(reduced: boolean)
		reducedMotion = reduced == true
		if recordOps then
			note(`reducedmotion={tostring(reducedMotion)}`)
		end
	end
	-- what the target currently believes, for a spec that wants the fact itself
	function adapter.reducedMotion(): boolean
		return reducedMotion
	end

	--[[ THE BACKGROUND TRANSPARENCY PREFERENCE. Modelled here for the
		same reason `setReducedMotion` is: the defect this seam exists to prevent is a
		fact that never ARRIVES, and a fake that took the value from construction
		instead of from the renderer's push could not see that defect. What the fake
		does NOT model is the paint — this target has no engine backdrop to repaint,
		and only a Studio session can show a `BackgroundTransparency` move. ]]
	local preferredTransparency = 1
	function adapter.setPreferredTransparency(effective: number)
		preferredTransparency = effective
		if recordOps then
			note(`preferredtransparency={tostring(effective)}`)
		end
	end
	function adapter.preferredTransparency(): number
		return preferredTransparency
	end
	-- every adapter-side motion decision since the last read, oldest first.
	-- Deliberately NOT part of `ops`: `takeOps()` is asserted positionally by
	-- several specs, and a press must not shift their indices.
	function adapter.takeMotionOps(): { { path: string, kind: string } }
		local out = motionOps
		motionOps = {}
		return out
	end
	-- the press dip itself, played from the drivers that model a real press
	-- (`tap`, `touchTap`). `driveActivate` is the DEV-DRIVE verb — it calls the
	-- handler without a press, exactly as the live adapter does — so it plays no
	-- dip, and neither does a node the framework never made interactive.
	local function playPressDip(path: string)
		if nodes[path] == nil or nodes[path].onActivate == nil then
			return
		end
		table.insert(motionOps, { path = path, kind = if reducedMotion then "instant" else "tween" })
	end

	-- native paint report. A headless target has NO native StyleSheet paint, so
	-- it returns nil — which is the honest answer and keeps theme_controller on
	-- the explicit-write (fallback) path exactly as it was before this method
	-- existed. Specs that want the native path override it (see
	-- tests/theme_controller.spec.luau's `nativeAdapter`).
	function adapter.nativeStyleInfo(): any
		return nil
	end

	-- the root a theme sheet would link at. nil headless: there is no Instance.
	-- Overridden by the specs that drive native theming.
	function adapter.themeRootGui(): any
		return nil
	end

	-- the DECORATION half of a theme package. Records the pushes (including the
	-- nil push uninstall makes) and reports `false` = the chrome did not change,
	-- which is what a target with no decoration surface must say.
	local themePackagePushes: { any } = {}
	function adapter.setThemePackage(package: any?, themeName: string?, snapshot: any?): boolean
		table.insert(themePackagePushes, { package = package, theme = themeName, snapshot = snapshot })
		-- THE PALETTE HALF OF THE COMMIT, mirrored from screen_target's
		-- `setActiveTheme`: pick the named theme (or the package's default) out of
		-- the package, and fall back to the library style when the package is
		-- cleared. Everything adapter-owned that reads a palette resolves against
		-- this, in both targets.
		local theme: any = nil
		if type(package) == "table" and type((package :: any).style) == "table" then
			local wanted = themeName or (package :: any).style.defaultTheme
			for _, entry in (package :: any).style.themes do
				if entry.name == wanted then
					theme = entry
				end
			end
		end
		activeThemePalette = theme
		-- ...AND THE REPAINT, mirroring screen_paint.refreshThemedPaint. A commit is
		-- a RE-SOLVE and never a rebuild, so nothing else will ever
		-- re-visit a node whose layout did not change — and a `tint` and a Path's
		-- stroke role are paint, not geometry. Without this a static tint keeps the
		-- OUTGOING package's colour for the rest of its life.
		for _, node in nodes do
			if node.pathRoleColor ~= nil then
				node.pathRoleColor = pathRoleColor(node.props.role)
			end
			if node.tintSpec ~= nil then
				node.tintColor = sheet_model.tintColor(paletteTheme(), node.tintSpec, node.class)
			end
		end
		return false
	end
	function adapter.themePackagePushes(): { any }
		return themePackagePushes
	end

	-- THE GROWTH SEAM, GROWN (ARCH-5). `theme_controller` feature-detects
	-- `setThemeStyle` and calls it on every commit for a target that can take a
	-- runtime palette; ScreenTarget cannot, so this fake is the only place the
	-- call has ever been observable. Recording, so a spec can assert the commit
	-- reached the target rather than inferring it from paint.
	local themeStylePushes: { any } = {}
	function adapter.setThemeStyle(style: any)
		table.insert(themeStylePushes, style)
	end
	function adapter.themeStylePushes(): { any }
		return themeStylePushes
	end

	-- test readers for the declared region and the current offset (A-SV1)
	function adapter.scrollRegionOf(path: string): any
		local node = nodes[path]
		return if node ~= nil then node.scrollRegion else nil
	end
	function adapter.scrollPositionOf(path: string): any
		local node = nodes[path]
		return if node ~= nil then node.scrollPosition else nil
	end

	-- test driver: the "engine" scrolled (user wheel/touch/momentum)
	function adapter.driveScroll(path: string, pos: { x: number, y: number })
		local node = nodes[path]
		assert(node ~= nil, `driveScroll: no node {path}`)
		node.scrollPosition = clampScroll(node, pos)
		fireScrollObservers(node)
	end

	-- a captured zone that unmounts mid-drag cancels — unless the cancel
	-- handler answers true to reason "removed" (a drag-owned lift unmounting
	-- its own origin row keeps the capture alive)
	function adapter._cancelIfCaptured(handle: any, reason: string?)
		if pointerCapture == handle then
			local keep = nil
			if handle.pointer and handle.pointer.cancel then
				keep = handle.pointer.cancel(reason)
			end
			if keep == true and reason == "removed" then
				return
			end
			pointerCapture = nil
			captureHint = nil
		end
	end

	-- the Roblox menu opened (Escape is engine-reserved): abort any capture
	function adapter.interruptCapture()
		if pointerCapture ~= nil then
			adapter._cancelIfCaptured(pointerCapture, "interrupted")
		end
	end

	function adapter.hover(path: string)
		local node = nodes[path]
		hoverHint = node and node.props.cursorHint or nil
		-- the hover VISUAL state only exists where the renderer enabled it
		-- (pointer class live); off pointer this is a no-op, matching production
		if node and node.hoverEnabled then
			node.hovered = true
			if node.hoverObserver then
				node.hoverObserver(true)
			end
		end
	end

	function adapter.unhover(path: string)
		hoverHint = nil
		local node = nodes[path]
		if node and node.hoverEnabled then
			node.hovered = false
			if node.hoverObserver then
				node.hoverObserver(false)
			end
		end
	end

	function adapter.cursorHint(): string?
		return captureHint or hoverHint
	end

	function adapter.pointerDown(path: string, x: number, y: number, pointerType: string?)
		-- a live capture OWNS the pointer: a began on another zone mid-drag
		-- is ignored, never a steal (engine parity; live-found 2026-07-20)
		if pointerCapture ~= nil then
			-- REDTEAM FIX (item 14, LOW), mirrored from screen_target.luau's
			-- own identical fix (see its comment there for the full repro):
			-- `destroyRoot`'s own capture-cancel is scoped to nodes it can
			-- still find belonging to the root it is tearing down — a
			-- captured node destroyed through some OTHER path first (this
			-- fake's `alive` flag models the live adapter's
			-- `instance:IsDescendantOf(game)`) leaves `pointerCapture`
			-- pointing at a dead node no `destroyRoot` call, on ANY root,
			-- can ever reach again — a stuck capture blocking every future
			-- press adapter-wide. A liveness check here treats a capture on
			-- a node that is no longer alive as already-ended.
			if pointerCapture.alive == false then
				pointerCapture = nil
				captureHint = nil
			else
				return
			end
		end
		local node = nodes[path]
		if node and node.pointer then
			pointerCapture = node
			pointerCapture.pointerType = pointerType or "mouse"
			captureHint = node.props.cursorHint
			if node.pointer.down then
				local claimed = node.pointer.down({ x = x, y = y, pointerType = pointerType or "mouse" })
				-- a zone may DECLINE (return false): the capture dissolves so a
				-- sibling zone under the same point can claim the gesture
				-- (engine double-dispatch parity; live-found 2026-07-20)
				if claimed == false then
					pointerCapture = nil
					captureHint = nil
				end
			end
		end
	end

	function adapter.pointerMove(x: number, y: number)
		if pointerCapture and pointerCapture.pointer.move then
			pointerCapture.pointer.move({ x = x, y = y, pointerType = pointerCapture.pointerType })
		end
	end

	--[[ THE RELEASE THAT ACTIVATES (redteam BLOCKER, 2026-08-13) ───────────────
		A pointer gesture on a real `GuiButton` — every Table row `Hit`, every
		VirtualList row — does not end at `InputEnded`. The engine ALSO fires that
		button's `Activated`, and both this repo's own gesture engines record the
		same hard-won fact about it: it lands "whichever side of `InputEnded`" the
		engine feels like. A drag, a swipe and a tap are indistinguishable to that
		signal; only the control's own suppression tells them apart.

		This driver never delivered it. `pointerUp` was the end of the story, so
		EVERY swipe case in this suite proved its control against a sequence the
		engine does not produce — and two cases written specifically to assert "a
		swipe is not a tap" passed by asserting their own starting value, unable to
		fail. The defect they were guarding survived them (a swipe's own Activated
		closed the tray it had just opened, or fired the row's primary action).

		`activate` is therefore an ORDER, not a boolean: "after" is the common
		engine order (InputEnded, then Activated), "before" the one that exposed
		the second half of the same defect, `nil` the legacy silent release a
		gesture that ends OFF the button genuinely produces. The meta matches
		`setActivateHandler`'s exactly (`source = "pointer"`, the capture's own
		pointer kind, the release point) — a partial meta would be a different lie. No
		press dip: the dip belongs to the PRESS, which this release is the end of,
		not to the activate.

		A SEPARATE FUNCTION, not a third argument to `pointerUp`. Two dozen shipped
		call sites already pass a redundant pointer-type string there (`pointerUp(x,
		y, "touch")` — the type comes from the capture and always has), so an
		`activate` parameter in that slot would read as satisfied by a string that
		means nothing of the kind, and every one of those releases would silently
		stay silent. It also RAISES on a release with no live capture: a case that
		believes it delivered an Activated and delivered nothing is the exact
		failure mode this exists to end. ]]
	function adapter.pointerUpActivating(x: number, y: number, order: "before" | "after")
		if order ~= "before" and order ~= "after" then
			error(`fake_target.pointerUpActivating: order must be "before" or "after", got {tostring(order)}`, 2)
		end
		local captured = pointerCapture
		if captured == nil then
			error("fake_target.pointerUpActivating: no live pointer capture — nothing could activate", 2)
		end
		local function fireActivated()
			if captured.onActivate ~= nil then
				captured.onActivate({
					source = "pointer",
					pointer = captured.pointerType or "mouse",
					x = x,
					y = y,
				})
			end
		end
		if order == "before" then
			fireActivated()
		end
		adapter.pointerUp(x, y)
		if order == "after" then
			fireActivated()
		end
	end

	function adapter.pointerUp(x: number, y: number)
		if pointerCapture then
			if pointerCapture.pointer.up then
				pointerCapture.pointer.up({ x = x, y = y, pointerType = pointerCapture.pointerType })
			end
			pointerCapture = nil
			captureHint = nil
		end
	end

	-- text-entry seam (§17 Phase 5): the headless mirror of what the engine
	-- TextBox adapter will do. setTextInputHandlers stores the control's
	-- handlers on the node; the simulation helpers below drive the SAME handler
	-- seam (no back-door writes to the model). Each field keeps its own engine
	-- text buffer, which is allowed to diverge from the model when maxLength/
	-- validate reject an edit — reconciled on commit/blur (IME-safe model).
	function adapter.setTextInputHandlers(handle: any, handlers: any)
		handle.textHandlers = handlers
		handle.textBuffer = handle.props.text or ""
	end

	-- keyboardType engine-application mirror (§17 Phase 5 hint wiring). ScreenTarget
	-- maps keyboardType -> Enum.TextInputType and writes it to the TextBox ONLY when
	-- the security-locked member is reachable (canSetTextInputType; docs/research/
	-- 2026-07-20-textbox-engine-facts.md §1 — RobloxScript-locked, so false on
	-- shipping engines). This headless mirror lets that capability CONTRACT be proven
	-- without an engine: the declared hint always lands as data (props.keyboardType,
	-- via the generic setProp above, unchanged), while appliedTextInputType() reports
	-- the engine token the adapter WOULD apply — mapped when capable, nil when not.
	-- Default false mirrors a shipping engine. Map kept in lockstep with
	-- screen_target.luau's KEYBOARD_TYPE_ENGINE_NAME.
	local textInputTypeCapable = false
	local KEYBOARD_TYPE_ENGINE_NAME: { [string]: string } =
		{ default = "Default", numeric = "Number", email = "Email", phone = "Phone" }
	function adapter.setTextInputTypeCapable(capable: boolean)
		textInputTypeCapable = capable
	end
	function adapter.appliedTextInputType(path: string): string?
		if not textInputTypeCapable then
			return nil
		end
		local node = nodes[path]
		local kt = node and node.props.keyboardType
		return if kt ~= nil then KEYBOARD_TYPE_ENGINE_NAME[kt] else nil
	end
	local function graphemes(s: string): { string }
		local out: { string } = {}
		local i = 1
		local n = #s
		while i <= n do
			local nextI = utf8.offset(s, 2, i)
			local j = if nextI ~= nil then (nextI :: number) - 1 else n
			table.insert(out, string.sub(s, i, j))
			i = j + 1
		end
		return out
	end
	-- engine gains focus (our editing binding drove CaptureFocus): seed the
	-- engine buffer from the currently-shown text and fire onFocusGained
	function adapter.focusText(path: string)
		local node = nodes[path]
		if node == nil or node.textHandlers == nil then
			return
		end
		node.textBuffer = node.props.text or ""
		if node.textHandlers.onFocusGained then
			-- deliver the focused node's path (engine-initiated focus learns the
			-- path only here — mirrors ScreenTarget passing handle.path; F1)
			node.textHandlers.onFocusGained(path)
		end
	end
	-- type per grapheme, firing onTextChanged with the full engine buffer each
	-- step (mirrors TextBox.Text changing as the user types)
	function adapter.typeText(path: string, str: string)
		local node = nodes[path]
		if node == nil or node.textHandlers == nil then
			return
		end
		for _, g in graphemes(str) do
			node.textBuffer = (node.textBuffer or "") .. g
			if node.textHandlers.onTextChanged then
				node.textHandlers.onTextChanged(node.textBuffer)
			end
		end
	end
	-- paste idiom: one onTextChanged with a multi-grapheme delta appended
	function adapter.pasteText(path: string, str: string)
		local node = nodes[path]
		if node == nil or node.textHandlers == nil then
			return
		end
		node.textBuffer = (node.textBuffer or "") .. str
		if node.textHandlers.onTextChanged then
			node.textHandlers.onTextChanged(node.textBuffer)
		end
	end
	function adapter.commitText(path: string) -- engine FocusLost(enterPressed)
		local node = nodes[path]
		if node and node.textHandlers and node.textHandlers.onFocusLost then
			node.textHandlers.onFocusLost("enter")
		end
	end
	function adapter.blurText(path: string) -- engine FocusLost (tapped away)
		local node = nodes[path]
		if node and node.textHandlers and node.textHandlers.onFocusLost then
			node.textHandlers.onFocusLost("focusLost")
		end
	end
	function adapter.cancelText(path: string) -- engine-reported Escape (D1)
		local node = nodes[path]
		if node and node.textHandlers and node.textHandlers.onFocusLost then
			node.textHandlers.onFocusLost("cancel")
		end
	end

	-- test helpers (meta mirrors the ScreenTarget's pointer metadata: kind of
	-- pointer plus held modifiers at activate time)
	function adapter.tap(path: string, meta: any?)
		local node = nodes[path]
		if node and node.onActivate then
			-- a press is motion before it is a callback (see playPressDip)
			playPressDip(path)
			node.onActivate(meta)
		end
	end

	-- the DEV DRIVE seam's headless mirror (ScreenTarget.driveActivate): the same
	-- call into the same registered handler, with the same "was there one" answer.
	-- Kept name-identical so a spec can prove a game's dev-drive verb and a real
	-- press reach ONE closure rather than two lookalikes.
	function adapter.driveActivate(path: string, meta: any?): boolean
		local node = nodes[path]
		if node == nil or node.onActivate == nil then
			return false
		end
		node.onActivate(meta)
		return true
	end

	--[[ THE HONEST TOUCH TAP (device round 1, DB-4) ────────────────────────────
		`tap` above is ONE call into the activate handler with whatever meta the
		test invents. A real finger is three things in a fixed order — an
		`InputBegan` on the node, an `InputEnded`, and only then `GuiButton
		.Activated` carrying `{ source = "pointer", pointer = "touch", x, y }`
		(ScreenTarget's `setActivateHandler`) — and a driver that skips the first
		two and hands `{}` for the third cannot see a defect that lives in the
		order or in the meta. The one-thumb sponsor flow (tap a card, tap a row)
		passed headless for exactly that reason while doing nothing on a phone.

		So: this drives all three, through the same seams the engine drives, with
		the real meta. A node with no pointer handlers simply gets nothing from
		the first two — which is the truth for a plain Button, and is the point:
		the ORDER is modelled, not assumed away. `tapPos` defaults to the node's
		own centre, so a caller that does not care about the point says nothing.
	]]
	function adapter.touchTap(path: string, pos: { x: number, y: number }?, meta: any?)
		local node = nodes[path]
		if node == nil then
			return
		end
		local rect = node.rect or { x = 0, y = 0, w = 0, h = 0 }
		local x = if pos ~= nil then pos.x else rect.x + (rect.w or 0) / 2
		local y = if pos ~= nil then pos.y else rect.y + (rect.h or 0) / 2
		adapter.pointerDown(path, x, y, "touch")
		adapter.pointerUp(x, y)
		playPressDip(path)
		if node.onActivate then
			local m: any = { source = "pointer", pointer = "touch", x = x, y = y }
			if type(meta) == "table" then
				for k, v in meta :: any do
					m[k] = v
				end
			end
			node.onActivate(m)
		end
	end
	function adapter.node(path: string): any
		return nodes[path]
	end
	--[[ THE STROKE A `Path` NODE OWNS: `{ zIndex, uploads }`, or nil for every
		other class. `zIndex` is the paint order this target gave the engine object
		it created beside the node; `uploads` is how many times its geometry has
		been handed over. Both are facts only the adapter knows. ]]
	function adapter.pathStrokeOf(path: string): any
		local node = nodes[path]
		return if node ~= nil then node.pathStroke else nil
	end
	--[[ WHICH SURFACE ROOT THIS NODE IS PARENTED UNDER, or nil when it lives
		inside an instance host instead. The live adapter answers this with
		`instance.Parent`; nothing headless could ask it before, which is exactly
		why a node adopted into the WRONG surface's ScreenGui was invisible to
		every replay of NM-H4a. ]]
	function adapter.rootIdOf(path: string): string?
		local node = nodes[path]
		local root = if node ~= nil then node.parentRoot else nil
		return if root ~= nil then root.id else nil
	end
	-- every live node path, sorted (test-only enumeration)
	function adapter.paths(): { string }
		local out: { string } = {}
		for path in nodes do
			table.insert(out, path)
		end
		table.sort(out)
		return out
	end

	function adapter.liveCount(): number
		local n = 0
		for _ in nodes do
			n += 1
		end
		return n
	end
	-- ADAPTER-HELD HANDLER CENSUS (roadmap Step 4, metric M4). On the engine
	-- every one of these slots is a live RBXScriptConnection; headless they are
	-- the same slots holding plain functions. Counting them is the honest
	-- headless stand-in for "engine connections": it counts exactly what Facet
	-- asked the target to hold, and claims nothing about what the engine
	-- allocates internally. The ScreenTarget answers the same question with its
	-- own real connection count, so a perf record can carry the field on both
	-- instruments without changing meaning.
	local HANDLER_SLOTS = {
		"onActivate",
		"pointer",
		"scrollHandler",
		"scrollObserver",
		"dragDetector",
		"touchGestures",
		"textHandlers",
		"hoverEnabled",
		"hoverObserver",
	}
	function adapter.handlerCount(): number
		local n = 0
		for _, node in nodes do
			for _, slot in HANDLER_SLOTS do
				if node[slot] ~= nil and node[slot] ~= false then
					n += 1
				end
			end
		end
		return n
	end
	-- ...and the DRAINING read takes the same guard `ops()` does (fix round 1,
	-- review Important 4): the two share one log, `takeOps` has ~2.5x the call
	-- sites, and an unarmed caller looping over an empty table for a forbidden op
	-- passes vacuously forever.
	function adapter.takeOps(): { string }
		assert(
			recordOps,
			"fake_target: the op log is opt-in — build this target with fake_target.new({ ops = true })"
		)
		local taken = ops
		ops = {}
		return taken
	end
	function adapter.rootCount(): number
		return rootCount
	end
	-- the whole live node table, for a differential that has to compare EVERY
	-- property of every node rather than a chosen few
	function adapter.liveNodes(): { [string]: any }
		return nodes
	end

	return adapter
end

return fake_target
