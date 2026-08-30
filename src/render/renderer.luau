--!strict
-- Renderer (design §4.3 #4, §13): walks the mounted graph, solves layout, and
-- drives a RenderTargetAdapter. Engine-free — ScreenTarget (client-only) and
-- the FakeTarget (tests) implement the same adapter interface, which is what
-- proves the §13 seam.
-- Adapter interface (all handles opaque to this module):
--   adapter.createRoot(screenId: string) -> rootHandle
--   adapter.create(rootHandle, path, class, decorationHint?) -> handle
--   adapter.setRect(handle, rect)                       [layout authority]
--   adapter.setProp(handle, prop, value, authority)     [checked upstream]
--   adapter.remove(handle)
--   adapter.destroyRoot(rootHandle)
-- Update model: refresh() drains the mounted dirty queue; paint-only changes
-- write props without re-solving; measure/arrange/structure re-solve and
-- write only rects that actually changed (minimal-write contract).
-- ARMED COMMITS: `presenter.withAnimation` arms the controller for exactly one
-- commit, in which the solved rects are diffed against the last ones and the
-- nodes that STARTED moving get a relative presentation record that flies them
-- in from where they used to be. The solve stays exact and instant either way —
-- only the PAINT travels (docs/plans/parity-round2.md §Phase 1).

local solver = require("../layout/solver")
local profile = require("../core/profile")
local text_metrics = require("../layout/text_metrics")
local authority = require("./authority")
-- the per-node presentation channel: transform,
-- transparency, the authored triple and the `withAnimation` records, behind one
-- write site. Constructed per surface in `attach` — see the pointer there.
local presentation_channel = require("./presentation_channel")
-- the cross-surface overlap alarm: a live registry of surfaces per
-- paint target, read only by `controller.diagnostics()` — nothing here runs in a
-- solve, a commit or a frame
local surface_overlap = require("./surface_overlap")
local themeSnapshot = require("../themes/snapshot")
-- the measure seam and the button-text grammar (see the pointer below)
local layout_node = require("./layout_node")
-- the hit-expander overhang lift: the paint order a touch floor needs to be
-- deliverable (its own file for the same 200k reason `layout_node` is)
local hit_lift = require("./hit_lift")
local instance_boundary = require("./instance_boundary")
local rect_pass = require("./rect_pass")
local commit_walks = require("./commit_walks")
local chrome_slots = require("../tokens/chrome_slots")
-- public drag/drop: the declaration channel and the per-surface
-- registry that turns declarations into one acquisition→session→terminal path
local dragContract = require("../input/drag_contract")
local dragRegistryLib = require("../input/drag_registry")
local autoscrollLib = require("../input/autoscroll")
local specGuard = require("../spec_guard")
-- the CLASS SCHEMA, read here for one reason only: an enum prop's closed set has
-- to be enforced where a BOUND value lands, not just where a static one is
-- authored (see `assertEnumValue` below)
local schema = require("../blueprint_schema")

local renderer = {}

-- CLASSES WHOSE FACE IS NOT THE FRAMEWORK'S TO PAINT. Both reserve a box for
-- content something else draws — a `Stage`'s engine-rendered 3-D scene, a
-- `Foreign`'s caller-owned GuiObject — so a theme package's whole-art recipe
-- covering the box would cover the content. The create path pins the no-slot
-- hint from this table (see ensureTree); a theme still reaches either pane
-- through the authored stroke/corners modifiers, which decorate the box's edge
-- rather than its face.
local NO_DECORATION_CLASSES: { [string]: boolean } = { Stage = true, Foreign = true }

-- THE PROP CHANNEL MANIFEST MOVED (2026-08-17, the 200k `Source` write-cap
-- pressure again). `BINDING_PROPS`, `STYLE_PROPS`, `STYLE_PROP_ORDER`,
-- `BINDING_PROP_CLASSES`, `emitsBinding` and `DIRECT_PROPS` — module-level data
-- plus one pure predicate over it, reading no `attach` upvalue at all — now live
-- in `render/prop_channels.luau`, with the two load-time completeness assertions
-- that guard them. Rebound to locals of their original names, so no call site in
-- this file moved, and re-exported below because every consumer already reads
-- them off `renderer`.
local prop_channels = require("./prop_channels")
local paths = require("../paths")
local rectLib = require("../rect")
local isPathPrefix = paths.isPrefix
local BINDING_PROPS = prop_channels.BINDING_PROPS
local STYLE_PROPS = prop_channels.STYLE_PROPS
local emitsBinding = prop_channels.emitsBinding
local STYLE_PROP_ORDER = prop_channels.STYLE_PROP_ORDER
renderer.STYLE_PROPS = prop_channels.STYLE_PROPS
renderer.BINDING_PROPS = prop_channels.BINDING_PROPS
renderer.EMITTED_PROPS = prop_channels.EMITTED_PROPS
renderer.DIRECT_PROPS = prop_channels.DIRECT_PROPS

-- THE MEASURE SEAM MOVED (2026-08-14, the 200k `Source` write-cap split).
-- `toLayoutNode` — the mounted-node -> `solver.Node` translation — plus the
-- button-text grammar it shares with the paint seam (`compactForm`,
-- `drawnButtonText`) and the declared hit floor now live in
-- `render/layout_node.luau`. Nothing about them changed: they read no state this
-- file owns, every input was already an argument, and the two public names are
-- re-exported below so `renderer.compactForm` / `renderer.drawnButtonText` are
-- exactly where every caller already looks. WHY: Roblox refuses a `Script.Source`
-- write at >= 200,000 chars, so an over-cap module stops live-syncing into an open
-- Studio session and a live check against it tests the place file instead of the
-- edits.
-- Rebound to locals of their original names, so no call site in this file moved.
local toLayoutNode = layout_node.toLayoutNode
local effectiveHitFloor = layout_node.effectiveHitFloor
renderer.compactForm = layout_node.compactForm
renderer.drawnButtonText = layout_node.drawnButtonText

local function rectsEqual(a: any, b: any): boolean
	if a == nil or b == nil then
		return a == nil and b == nil
	end
	return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

local TAPPABLE: { [string]: boolean } = { Button = true, Toggle = true, TextField = true }
-- WHAT CAN TAKE A PRESS AWAY FROM AN OVERHANGING HIT EXPANDER (the overhang
-- lift, `src/render/hit_lift.luau`): the classes the adapter realises as a real input
-- SINKER — the tappables (GuiButton/TextBox) plus a `Grip`, the non-button
-- Active pointer zone (`screen_target.luau`, `class == "Grip"`). Everything else
-- is a Frame or a Label the engine routes straight through, so it cannot steal a
-- band whatever its z, and lifting a host over one would be paint churn for
-- nothing. A node that declares `active` joins them, because that prop is the
-- author asking the adapter for exactly this sinking.
local INPUT_SINKING: { [string]: boolean } = { Button = true, Toggle = true, TextField = true, Grip = true }
-- nodes that get the pointer HOVER layer (UI-PARADIGM-001): activatable chrome
-- the renderer draws (Table rows/headers render as Button). TextField is not a
-- hover surface (its affordance is the caret/edit handshake, not a hover lift).
local HOVERABLE: { [string]: boolean } = { Button = true, Toggle = true }

export type RendererAttachOpts = {
	-- "coreSafeContent" (default) | "deviceSafeContent" | "edgeToEdge"
	rootPolicy: string?,
	-- THE EDGE-FLOOR KNOB (director ruling, 2026-08-23): "if the
	-- user truly specifies edge-to-edge we should do so with no padding.
	-- Ensure the user can specify padding" — a number (a literal px, never
	-- scaled) or a theme metric name (`themeSnapshot.resolveNumber`'s own
	-- grammar — the same one `Table.cellPadding`/`anchor.gap` already use),
	-- which rides the ten-foot ladder for free because the metrics snapshot
	-- resolveNumber reads from is already display-scaled. Floors bottom/left/
	-- right (never top — the platform's own row owns that
	-- edge) at max(whatever the policy already reserves, this). NEVER legal
	-- together with `rootPolicy = "edgeToEdge"`: attach() refuses the
	-- combination rather than silently picking a winner (§ ROOT POLICY below).
	-- Omitted = today's behavior, byte for byte, on every policy (no default
	-- flip this round).
	edgeFloor: (number | string)?,
	-- a pointer tap on a mounted path. `meta` carries the tap's geometry
	-- (`x`/`y`) for the outside-tap policy, and `via` for a detector-driven tap.
	onNodeTap: ((path: string, meta: any?) -> ())?,
	-- OPT-IN mirror of logical focus to the engine's own selection; the presenter
	-- sets it for modal/exclusive surfaces only
	engineSelectionBridge: boolean?,
	-- FULL-VALUE DISCLOSURE engagement — the large-text round's cut-label seam:
	-- pointer enter/leave
	-- and touch long-press on a `disclose` Text, delivered as (path | nil). The
	-- presenter routes these to its `_discloseHover`/`_discloseLongPress`
	-- engine-adapter seams; hand-attached surfaces may omit both (no zones are
	-- wired, focus-driven disclosure still works through the presenter).
	onDiscloseHover: ((path: string?) -> ())?,
	onDiscloseLongPress: ((path: string?) -> ())?,
	recycleInstances: boolean?,
	incrementalLayout: boolean?,
}

local ATTACH_OPTS_KEYS = specGuard.keySet({
	"engineSelectionBridge",
	"onNodeTap",
	"rootPolicy",
	"edgeFloor",
	"onDiscloseHover",
	"onDiscloseLongPress",
	"recycleInstances",
	"incrementalLayout",
})

-- attach(core, mountedRoot, env, adapter, opts) -> controller
function renderer.attach(
	core: any,
	root: any,
	env: any,
	adapter: any,
	--[[ THE DECLARED TYPE IS THE SHIPPED TRUTH (api-architecture-consistency F-29).
		`engineSelectionBridge` was read through an `(opts :: any)` cast and passed
		by the presenter for months while the type said this table held two keys —
		so a strict consumer wanting the bridge on a hand-attached surface got a
		type error for a supported option, and no checker would have caught the
		flag's removal. `onNodeTap` was declared one-arg and has always been called
		with `(path, meta)`; both in-tree consumers already write the two-arg form,
		and `meta` is where the outside-tap geometry (`x`/`y`) and `via` live. ]]
	opts: RendererAttachOpts?
)
	-- ...AND THE DECLARED TYPE IS ALSO CLOSED (constitution §4). F-29 made
	-- the three fields honest; this makes a fourth, misspelled one loud instead of
	-- inert — the same rule `rootPolicy`'s own value check applies one level up.
	specGuard.assertKnownKeys("renderer.attach", opts, ATTACH_OPTS_KEYS, "opts")
	-- THE ACCEPTED POLICIES, ENUMERATED. `edgeToEdge` was passed by every modal
	-- scrim for months and read by nothing: it fell through to the default and
	-- the scrim was quietly inset, with a comment above the call site describing
	-- behaviour the code did not have. An unknown mode is now a failure at the
	-- call site instead of a shrug at render time.
	local ROOT_POLICIES = {
		-- content, inset by the CoreGui reservation (the default)
		coreSafeContent = true,
		-- content, inset by the per-edge maximum of CoreGui and device insets
		deviceSafeContent = true,
		--[[ content that MEANS TO RIDE THE PLATFORM'S TOPBAR BAND: the
			same three edges `deviceSafeContent` clears, and a TOP brought up to where
			the free strip starts — `platformChrome.bandInsets`, the fact api.md has
			described as *"what a surface that means to ride the band applies instead"*
			since the chrome band shipped and which no policy applied. WHAT REACHES THE STRIP IS A
			DECLARATION, never the whole surface: a composition with no `topbar` region
			reserves the platform's whole row and is byte-identical to
			`deviceSafeContent`. ]]
		bandSafeContent = true,
		-- DECORATION only — a scrim or a backdrop, painting under the insets
		edgeToEdge = true,
	}
	local rootPolicy = (opts and opts.rootPolicy) or "coreSafeContent"
	if ROOT_POLICIES[rootPolicy] ~= true then
		local names = {}
		for name in ROOT_POLICIES do
			table.insert(names, name)
		end
		table.sort(names)
		error(`Facet renderer: unknown rootPolicy '{tostring(rootPolicy)}'. Valid: {table.concat(names, ", ")}.`, 0)
	end
	local optEdgeFloor = opts and opts.edgeFloor
	--[[ THE ONE COMBINATION THIS OPT REFUSES (director ruling):
		explicit `edgeToEdge` means zero padding, guaranteed — a decoration
		layer that asked to paint to the edge and a floor that pads it away
		from the edge is a contradiction at the call site, not a race the
		renderer picks a winner for. Same doctrine `edgeToEdge` itself already
		got above: an unusable combination fails loudly here instead of
		silently doing whichever the last write meant. ]]
	if optEdgeFloor ~= nil and rootPolicy == "edgeToEdge" then
		error(
			"Facet renderer: edgeFloor has no effect under rootPolicy = 'edgeToEdge' (edge-to-edge is zero "
				.. "padding by definition) — drop edgeFloor, or use a rootPolicy that reserves content insets.",
			0
		)
	end
	local rootHandle = adapter.createRoot(root.node.id or "Screen")
	local attachScope = core:scope("renderer-attach")
	local initialized = false
	-- THE TWO FACTS THE CROSS-SURFACE ALARM READS BACK. `rootVisible`
	-- mirrors what the adapter accepted from `setRootVisible`, and
	-- `declaredOrder` stays nil until something calls `setDisplayOrder` —
	-- "nobody ordered this surface" and "this surface is at layer 0" are
	-- different declarations and must not share a value.
	local rootVisible = true
	local declaredOrder: number? = nil
	local handles: { [string]: any } = {} -- path -> adapter handle
	local lastRects: { [string]: any } = {}
	-- path -> the scrollbar gutter that scroll host reserved on its last solve,
	-- `{ right, bottom }`, or nil for anything that reserved none. Read back
	-- through `controller.scrollBarInsetOf` by a control whose node has to line up
	-- ACROSS a scroll boundary it does not live inside (see the solver's own
	-- `barInset` note, and `newTable`'s header padding).
	local lastBarInsets: { [string]: any } = {}
	local lastScrollRegions: { [string]: any } = {}
	-- per-ScrollView autoscroll: the authored declaration, and the live model.
	-- Declared with the regions because they are written and dropped together.
	local scrollAutoscroll: { [string]: any } = {}
	local autoscrollModels: { [string]: any } = {}
	-- drag math reads solved rects through this lookup
	local function rectOf(path: string): any
		return lastRects[path]
	end
	-- path -> its nearest ScrollView ANCESTOR's path (rebuilt every structural
	-- sync by the live-path walk). It exists for one reason: the solver arranges
	-- a scroll host's children in the HOST's own coordinate space and the engine
	-- shifts them by CanvasPosition, so a solved rect inside a scrolled list is
	-- NOT where that row is on screen. A pointer, meanwhile, always arrives in
	-- window space. Hit-testing one against the other silently targets the wrong
	-- row the moment the list is scrolled — which is precisely the case edge
	-- autoscroll spends its whole life in.
	local scrollHostOf: { [string]: string } = {}
	-- ===== STROKED PATHS ARE NOT CROPPED BY THE ENGINE (RS-PATHCLIP) ========
	--
	-- A `UI.Path` renders as an engine stroke that is NOT a box in the widget
	-- tree, so no ancestor's clip crops it: inside a scrolling list a WINDOWED
	-- row sitting outside the viewport still painted its ring — a family-hued
	-- arc floating on empty plate, unattached to any row (Sponsor review round
	-- 1, F1; the parallel-Sponsor landscape capture, the ring of the row one
	-- pitch BELOW the last visible one). Every sibling in that row cropped
	-- correctly, which is the tell: the defect is the primitive, not the layout.
	--
	-- A stroke also cannot be crop*ped* half-way — there is no partial-clip
	-- operation for it — so the framework's rule is all-or-nothing: a path whose
	-- painted box is not FULLY inside every clip host above it does not paint at
	-- all. `clipHostOf` is the nearest such ancestor, threaded down the same
	-- live-path walk that already threads the scroll host (it is free there and
	-- a whole-tree search per path otherwise).
	local clipHostOf: { [string]: string } = {}
	local pathNodes: { [string]: boolean } = {}
	local pathNodeCount = 0
	-- what the SOLVER decided about each node's visibility, so the scroll-time
	-- re-cull never contradicts it (a path inside a losing ViewThatFits candidate
	-- stays hidden however its rect lands)
	local solverHidden: { [string]: boolean } = {}
	-- ===== THE HIT-EXPANDER OVERHANG LIFT (2026-08-15) =====================
	-- A control under the touch floor gets an invisible hit expander at
	-- `hostZ - 1`, and the engine delivers input to the TOPMOST interactive object
	-- only — so a sibling walked later outranks it and the band it advertises past
	-- its host is undeliverable. The answer is a PAINT ORDER: the host's whole
	-- branch is walked after the branches its expander reaches into. The rule, its
	-- qualifier ("non-expander siblings only"), the clause that stops it at the
	-- host, and the corpus measurement that makes the reorder safe all live in
	-- `src/render/hit_lift.luau`; this file supplies the three facts it resolves
	-- against and applies the order it returns.
	--
	-- the parent NODE of each live path, so a constraint between two nodes resolves
	-- to the two SIBLING branches that carry them (the lift moves whole subtrees,
	-- which is what keeps a `zIndex` scope intact), and the census of what can
	-- actually SINK a press
	local parentNodeOf: { [string]: any } = {}
	-- path -> TRUE when this input sinker is the author's, FALSE when it is one
	-- the framework synthesized (ruling R23; the walk that builds it says why).
	-- Both are keys: iterate for "any sinker", read the value for "the author's".
	local inputSinks: { [string]: boolean } = {}
	local hitLift = hit_lift.new()
	-- assigned below, where the z walk is defined: the solve re-runs it when the
	-- lift changes, because the lift is GEOMETRY and structural sync runs before
	-- the solve that produces it
	local syncZOrder: () -> ()
	local pathClipObservers: { [string]: () -> () } = {}
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
	-- ONE mounted-node lookup for the whole surface (Step 5.5 cleanup ledger C-02).
	-- `refresh` used to declare an identical depth-first walk as a closure INSIDE
	-- its dirty loop — one allocation per changed prop per frame — while the
	-- presentation channel had written the same walk once more of its own.
	-- IT SITS HERE, above its old home next to `refresh`, because the presentation
	-- channel is constructed immediately below and takes it as a dependency: a
	-- `local function` declared later is not an upvalue of anything above it, it is
	-- a nil global.
	local function findNode(path: string): any
		local function walk(node: any): any
			if node.path == path then
				return node
			end
			for _, child in node.children do
				local found = walk(child)
				if found then
					return found
				end
			end
			return nil
		end
		return walk(root.node)
	end

	-- THE PRESENTATION CHANNEL MOVED (2026-08-14, the 200k `Source` write-cap
	-- split). `transform`/`transparency` are PRESENTATION properties and this
	-- surface's whole motion write surface — the imperative channel, the authored
	-- `opacity`/`scale`/`rotation` triple, the `withAnimation` records and the one
	-- write site they compose through — now lives in
	-- `render/presentation_channel.luau`. WHY: Roblox refuses a `Script.Source`
	-- write at >= 200,000 chars, so an over-cap module stops live-syncing into an
	-- open Studio session and a live check against it tests the place file instead
	-- of the edits.
	--
	-- WHAT MADE THE SEAM CHEAP: every upvalue the channel needs is shareable BY
	-- REFERENCE. `handles` and `lastRects` are tables the renderer mutates in place
	-- and the channel reads; `findNode`, `adapter`, `core` and `root` never change
	-- identity. Nothing crosses this boundary as a reassigned local, which is why
	-- no accessor callbacks were needed (contrast `screen_paint`'s three). The
	-- price is that `dispose` must CLEAR `handles`/`lastRects` rather than rebind
	-- them — see the note there.
	local channel = presentation_channel.new({
		core = core,
		root = root,
		adapter = adapter,
		handles = handles,
		lastRects = lastRects,
		findNode = findNode,
	})
	-- rebound to locals of their original names, so no call site in this file moved
	local presentationShift = channel.presentationShift
	local readAuthoredPresentation = channel.readAuthoredPresentation

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
		local out = if dx == 0
				and dy == 0
				and px == 0
				and py == 0
			then rect
			else { x = rect.x - dx + px, y = rect.y - dy + py, w = rect.w, h = rect.h }
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
		if dx == 0 and dy == 0 and px == 0 and py == 0 then
			return rect
		end
		return { x = rect.x - dx + px, y = rect.y - dy + py, w = rect.w, h = rect.h }
	end
	-- half a pixel of slack: a rect that lands exactly on its host's edge is
	-- INSIDE it, and solved rects are not guaranteed integral.
	local CLIP_EPSILON = 0.5
	local function clipContains(outer: any, inner: any): boolean
		return rectLib.contains(outer, inner, CLIP_EPSILON)
	end
	-- does this path escape ANY clip host above it? Nested hosts all count: a
	-- list inside a clipped panel must crop against both.
	local function pathEscapesClip(path: string, rectFor: (string) -> any): boolean
		local own = rectFor(path)
		if own == nil then
			return false
		end
		local host: string? = clipHostOf[path]
		local guard = 0
		while host ~= nil and guard < 32 do
			local hostRect = rectFor(host)
			if hostRect ~= nil and not clipContains(hostRect, own) then
				return true
			end
			host = clipHostOf[host]
			guard += 1
		end
		return false
	end
	-- ===== public drag/drop ==========================
	-- ONE registry per surface, built lazily: a screen with no `UI.draggable`
	-- and no `UI.dropTarget` pays nothing for the feature existing. It is handed
	-- the LIVE rect lookup and the paint-order walk (`lastZ`, declared below and
	-- read through a closure) so a drop verdict is always about the geometry and
	-- the stacking the player is actually looking at.
	-- RETIRING SUBTREES ARE NOT DRAG SURFACES: the mount layer keeps a
	-- retiring subtree in `children` so its exit can paint, but the transition
	-- contract says
	-- it "turns non-interactive" — for drag that must mean RESOLUTION-time
	-- exclusion rather than registration churn, so a re-entry mid-exit is
	-- eligible again the same frame with no rewiring. Roots are collected once
	-- per structural sync; the registry consults the predicate per resolution.
	local retiringRoots: { string } = {}
	local function collectRetiringRoots()
		table.clear(retiringRoots)
		local function walk(node: any)
			if node.retiring == true then
				table.insert(retiringRoots, node.path)
				return -- descendants are covered by the prefix test
			end
			for _, child in node.children do
				walk(child)
			end
		end
		walk(root.node)
	end
	local function isPathLive(path: string): boolean
		for _, retired in retiringRoots do
			-- SEGMENT boundary, not a bare prefix (verifier P2-2): a retiring
			-- "/S/Slot" must not exclude its live sibling "/S/SlotA"
			if isPathPrefix(retired, path) then
				return false
			end
		end
		return true
	end

	local dragRegistryInstance: any = nil
	local dragCollaborators: { [string]: any } = {}
	-- per-path live-enabled reads for drag SOURCES (P2-3); populated at wiring,
	-- cleared with the wiring's unbind
	local dragSourceEnabled: { [string]: () -> boolean } = {}
	-- ONE ACTIVATION PER PRESS, the platform verifier's ruling: a node carrying
	-- both a drag detector and
	-- a native Activated can hear the same press twice (the detector's release
	-- synthesis for classes where the engine consumes the click; the native event
	-- for classes where it does not — gamepad A is documented to deliver it).
	-- Whichever signal arrives first wins; a second signal for the same path
	-- inside the window is the same press echoing. 50 ms is far below any human
	-- double-tap, so a real second tap is never eaten. Time rides the injectable
	-- `now` collaborator so the suite drives this deterministically.
	-- ONLY detector-carrying nodes can echo (they are the only nodes with two
	-- signals per press); every other control dispatches unconditionally — a
	-- toggle mashed twice in 40 ms is two real presses and must count twice.
	local detectorTapGuard: { [string]: boolean } = {}
	local lastNodeTapAt: { [string]: number } = {}
	-- armOnTap sources by path (director round six): consulted by the shared tap
	-- dispatch so a TAP on a declaring source ARMS instead of activating — the
	-- touch paradigm's pickup. Registered with the source, cleared with it.
	local armOnTapDecl: { [string]: boolean } = {}
	local function tapArmsInstead(path: string, meta: any?): boolean
		if armOnTapDecl[path] ~= true then
			return false
		end
		-- action-source activates (gamepad A / Return) belong to the consumer's
		-- onActivate — the armed paradigm already owns them
		if type(meta) == "table" and meta.source == "action" then
			return false
		end
		-- the registry exists whenever a source is registered (registerSource
		-- built it), so a nil instance means no declaring source is mounted
		local reg = dragRegistryInstance
		if reg == nil then
			return false
		end
		if reg.isActive() then
			-- a live session: this tap means something else (put-back, a row
			-- commit) and flows to the consumer unchanged
			return false
		end
		local enabled = dragSourceEnabled[path]
		if enabled ~= nil and not enabled() then
			return false
		end
		return reg.arm(path) == true
	end
	--[[ AN ACTIVATE NOBODY ELSE WANTED, ON A DRAG SOURCE, IS THE PICKUP — the
			keyboard-and-pad drag adaptation.

		`drag_registry.luau`'s own header says "the non-pointer arm->navigate->commit
		verbs all funnel into `beginSession`", and every piece of that path was
		proven working when called directly — `arm`, `armTo`, `commit`. Nothing
		called `arm`. The presenter only ever aimed an ALREADY-armed session, so the
		public `UI.draggable` verb had no default gamepad or keyboard pickup at all:
		with the card focused, ButtonA armed nothing and Return armed nothing (audit
		the adaptation review's high-severity finding M-9).

		THE RULE IS `newVirtualList`'S, HOISTED. That control already answers this
		for its own rows — `grabOnActivate = reorderable and onActivate == nil`, "a
		source with no consumer Activate arms on Activate" — and the reason the
		public verb had none is that `renderer` excluded action-source activates
		from the tap-arm path on the grounds that "they belong to the consumer's
		`onActivate`; the armed paradigm already owns them". Nothing else owned
		them, so they owned nothing.

		"NO CONSUMER WANTED IT" IS DECIDED STRUCTURALLY, not predicted: the
		presenter offers this LAST, after the node's own `onActivate`, after the
		Toggle flip and after every contribution — so a `VirtualList` row, a Table
		row and any control with its own Activate keep theirs untouched, and this
		fires only on the Activates that would otherwise have been a no-op.

		THE COMMIT IS ONLY EVER OURS. `armedHere` is set when THIS seam armed the
		session, so a control-owned grab (a VirtualList row's) can never be
		committed or cancelled by the generic path — its own contribution handles
		both, and a session it armed is invisible here. ]]
	local armedHere = false
	local function armedBySeam(): boolean
		local reg = dragRegistryInstance
		if reg == nil or not reg.isActive() or reg.mode() ~= "armed" then
			armedHere = false
			return false
		end
		return armedHere
	end
	local function activateArms(path: string, meta: any?): boolean
		-- POINTER activates never arm: a mouse lifts by travelling past the
		-- promotion token and a tap has to stay a tap (`armOnTap` is the touch
		-- paradigm's own opt-in, above). This is the non-pointer half only.
		if type(meta) ~= "table" or meta.source ~= "action" then
			return false
		end
		local reg = dragRegistryInstance
		if reg == nil then
			return false
		end
		if reg.isActive() then
			-- the COMMIT half of arm->navigate->commit: the aim is wherever the
			-- focus ring left it (the presenter's `armTo` follows focus), so the
			-- drop lands on the thing the player is looking at
			if not armedBySeam() then
				return false
			end
			reg.commit()
			armedHere = false
			return true
		end
		local enabled = dragSourceEnabled[path]
		if enabled ~= nil and not enabled() then
			return false
		end
		-- `arm` refuses a path that is not a registered source, so this is also
		-- the "is this a draggable?" test — one answer, in the registry
		if reg.arm(path) ~= true then
			return false
		end
		armedHere = true
		return true
	end

	local TAP_ECHO_WINDOW = 0.05
	local function dispatchNodeTapOnce(path: string): boolean
		if not detectorTapGuard[path] then
			return true
		end
		local clock = dragCollaborators.now or os.clock
		local at = clock()
		local last = lastNodeTapAt[path]
		if last ~= nil and (at - last) < TAP_ECHO_WINDOW then
			return false
		end
		lastNodeTapAt[path] = at
		return true
	end
	local dragUnbind: { [string]: () -> () } = {}
	local lastZ: { [string]: number } = {}
	local function dragRegistry(): any
		if dragRegistryInstance == nil then
			dragRegistryInstance = dragRegistryLib.new({
				core = core,
				rectOf = screenRectOf,
				zOf = function(path: string): number?
					return lastZ[path]
				end,
				-- A RETIRING SUBTREE IS NOT A DRAG SURFACE — resolution-time
				-- exclusion, reversal-safe by construction
				isPathLive = isPathLive,
				-- P2-3: disabled sources acquire nothing, read live per acquisition
				isSourceEnabled = function(path: string): boolean
					local read = dragSourceEnabled[path]
					return read == nil or read()
				end,
				now = dragCollaborators.now,
				feedback = dragCollaborators.feedback,
				proxy = dragCollaborators.proxy,
				motionClock = dragCollaborators.motionClock,
			})
			-- THE HELD SOURCE IS A NODE STATE (director round five): the registry
			-- publishes which path a live session is carrying; the adapter's
			-- `dragHeld` state empties that node's label through the same tag+rule
			-- channel `selected` paints by. Framework guarantee — no consumer code.
			--[[ THROUGH THE MANIFEST, LIKE EVERY OTHER RENDERER WRITE — the architecture
		review's channel rule.
				These two were the only `adapter.setProp` calls in this file that
				skipped `authority.assertWrite`, which is the single sentence
				constitution §11 makes about the renderer ("asserts every write").
				`dragHeld` has always been declared (`common`, presentation
				authority) — the assert was simply never made, so the one property
				whose whole point is that a consumer cannot author it was the one
				property nothing checked. `findNode` is an O(N) walk and this
				observer fires only when a drag session picks a source up or puts
				it down, which is a gesture boundary, not a frame. ]]
			local function setDragHeld(dragPath: string, held: boolean)
				local handle = handles[dragPath]
				if handle == nil then
					return
				end
				local node = findNode(dragPath)
				authority.assertWrite(if node ~= nil then node.class else "common", "dragHeld", "presentation")
				adapter.setProp(handle, "dragHeld", held, "presentation")
			end
			local heldPath: string? = nil
			attachScope:own(core:observe(dragRegistryInstance.heldSource, function(path: string?)
				if heldPath ~= nil and heldPath ~= path then
					setDragHeld(heldPath, false)
				end
				heldPath = path
				if path ~= nil then
					setDragHeld(path, true)
				end
			end))
		end
		return dragRegistryInstance
	end
	-- native drag acquisition, shared by the mount-time wiring below and the
	-- public `controller.attachDragDetector`. Nilable by contract: an adapter or
	-- an engine without `UIDragDetector` answers nil and the caller falls back
	-- to the framework's own pointer capture — the ONE thing that must never differ
	-- between the two paths is the promotion rule, which lives in the registry.
	local function attachDetector(path: string, handlers: any): (() -> ())?
		if adapter.setDragDetector == nil then
			return nil
		end
		local handle = handles[path]
		if handle == nil then
			return nil
		end
		return adapter.setDragDetector(handle, handlers)
	end
	local stats = {
		creates = 0,
		removes = 0,
		rectWrites = 0,
		propWrites = 0,
		solves = 0,
		textMeasureBatches = 0,
		-- recycling: `parked` counts nodes taken out of the tree intact rather than
		-- destroyed; `recycled` counts creates served from the pool instead of the
		-- engine. Both stay 0 unless the feature is on, which makes "is it actually
		-- doing anything" a readable number rather than an inference.
		parked = 0,
		recycled = 0,
		-- diagnostics for "why is recycling doing nothing": whether the feature is
		-- armed at all, and how many park attempts the ADAPTER refused
		recycleArmed = false,
		parkRefused = 0,
		-- nodes the MOST RECENT solve arranged / measured
		lastArranged = 0,
		lastMeasured = 0,
		-- re-solves earned by a consumer publishing a layout prop back from this
		-- surface's own geometry (see THE SOLVE'S OWN FEEDBACK). The stated cost of
		-- closing that frame: one extra solve on the frame the number moves, which
		-- is the solve the NEXT frame used to pay.
		feedbackSolves = 0,
		-- solves served by re-solving one absorbing box instead of the whole tree
		partialSolves = 0,
		elided = 0,
		ssPasses = 0,
		ssEnsureTree = 0,
		ssRetire = 0,
		ssLivePaths = 0,
		ssSweep = 0,
		ssZOrder = 0,
		-- structuralSync phase timings, ms accumulated. MEASURED rather than assumed:
		-- the pass was believed to be O(all live nodes), and it is not — the no-op walk
		-- is ~6% of it and the rest is per-NEW-NODE setup. Kept so that stays visible.
		ssTotal = 0,
		lastSkipped = 0,
	}
	-- THE RECT PASS (src/render/rect_pass): one walk in DOCUMENT ORDER, so a host's
	-- own rect always lands before anything beneath it. Built once per attach, over
	-- the four by-reference records it writes.
	local rectPass = rect_pass.new({
		adapter = adapter,
		handles = handles,
		lastRects = lastRects,
		lastBarInsets = lastBarInsets,
		stats = stats,
		rectsEqual = rectsEqual,
	})
	local lastDiagnostics: { any } = {}
	-- the last solve's composition resolutions, by node path. A solve
	-- OUTPUT, exposed exactly where the other two live (`diagnostics`,
	-- `hiddenRoots`) — an adaptive screen whose only evidence is a screenshot is
	-- an adaptive screen nobody can debug.
	local lastCompositions: { [string]: any } = {}
	-- ...and the last solve's per-text-node measurement facts, by node path
	-- the large-text round's cut verdict. Same channel, same reason: "this label
	-- was cut" is a solve output,
	-- and the presenter's disclosure affordance and the text audit both need it
	-- from the ONE authority that decided it rather than by re-measuring.
	local lastTextFacts: { [string]: any } = {}
	-- words handed to the adapter's premeasurement seam and not yet answered.
	-- Guards against asking twice while one round is in flight; a word that
	-- comes back (measured OR refused) is recorded in text_metrics and can
	-- never be requested again, so this set is the only loop guard needed.
	local textInFlight: { [string]: boolean } = {}
	-- the live premeasurement deliveries this surface has outstanding, cancelled on
	-- teardown so a late answer cannot reach a dismissed surface
	local textMeasureCancels: { () -> () } = {}
	local disposed = false
	-- paths whose subtree the solver hid this pass (losing ViewThatFits candidates)
	-- THE STRUCTURE EPOCH (2026-08-05). Monotonic; bumped by exactly the two things
	-- that can change what the focus map derives to for a given tree: a structural
	-- sync (nodes mounted/unmounted/reordered) and a change in which roots are HIDDEN
	-- (a ViewThatFits candidate losing at a new width does that without any structural
	-- churn at all, which is why the second half is not optional).
	--
	-- It exists because `presenter.refresh` re-derived the whole focus map from a full
	-- tree walk plus a traversal-rank sort EVERY frame, for EVERY presented surface,
	-- whether or not anything had moved. Measured on the ornate dense-scroll at
	-- 360x691: 478 derivations across 120 frames, 78.4 ms — 20% of all Facet work in
	-- the frame, and the great majority of it re-deriving a map identical to the one
	-- already installed.
	local structureEpoch = 0
	local hiddenRoots: { [string]: boolean } = {}
	-- AUTHORED `hidden` (round 3, item D), kept as its own tiny
	-- set and MERGED into the solver's hidden verdict on every solve. One set means
	-- the prop inherits, with no second implementation: the paint walk, the hit-rect
	-- retraction, the `hiddenRoots` the focus map filters on, and the structure-epoch
	-- bump that makes the focus map notice. Maintained at mount, at removal, and on
	-- the prop's own dirty — never by a whole-tree scan per solve.
	local authoredHidden: { [string]: boolean } = {}
	-- VIEW LIFETIME HOOKS (round 3, item D): `onAppear` and `onDisappear`.
	--
	-- Both are queued rather than called where they are discovered, and the ordering
	-- is the capability rather than an implementation detail:
	--   * appear drains AFTER the frame's solve, so the callback can read its own
	--     rect. The contract the declarative UI convention sets is that the
	--     closure "completes before the first
	--     rendered frame appears" — nothing here has reached a screen when it runs,
	--     because the whole refresh is one synchronous call.
	--   * disappear drains AFTER the removal sweep, so the handle is already gone and
	--     "the path is not mounted" is a fact rather than a comment. It is drained
	--     OUTSIDE the `mount` profiler span too — a consumer's analytics call is not
	--     Instance churn and must not be billed as it.
	local appearQueue: { { path: string, fn: (string) -> () } } = {}
	local disappearHooks: { [string]: (string) -> () } = {}
	local departedQueue: { { path: string, fn: (string) -> () } } = {}
	-- the expanded hit rect currently pushed per path (nil = none needed)
	local lastHitRects: { [string]: any } = {}
	-- THE metric authority for this surface. Read fresh at every
	-- use rather than captured, because `themeMetrics` is a live fact: the swap
	-- transaction sets it and re-solves in the same invocation, and a captured
	-- snapshot would paint the old theme's geometry for one frame. A garbage
	-- fact falls back to neutral rather than crashing a mounted surface.
	local function currentMetrics(): any
		local m = env:get("themeMetrics"):get()
		return if type(m) == "table" and type(m.type) == "table" then m else themeSnapshot.neutral()
	end
	-- last visibility pushed per path (hidden subtrees, A-AL1)
	local lastVisible: { [string]: boolean } = {}
	-- PRESENTATION HOLDS (auto reveal, 2026-08-04): paths whose own paint the
	-- PRESENTER is holding while its travelling strip covers them. Presentation
	-- layer only — the solve, rects and facts are untouched — and the visibility
	-- walk ORs it in so a re-solve (or a structural remount of the path) cannot
	-- un-hold a covered label. Presenter-owned: set and cleared through
	-- `controller.setPaintHeld`, never by structuralSync.
	local paintHeld: { [string]: boolean } = {}

	-- RS-PATHCLIP, the LIVE half. A native scroll host moves its canvas without
	-- moving one solved rect ("a same-window scroll delta is zero writes" —
	-- virtual_list), so a cull decided at solve time goes stale the moment the
	-- player scrolls. This re-runs it from the LIVE painted rects and is wired to
	-- every scroll host's own offset change; it touches nothing but paths, and
	-- never contradicts the solver's own hidden verdict.
	local function reculPathClips()
		if adapter.setVisible == nil or pathNodeCount == 0 then
			return
		end
		for path in pathNodes do
			local handle = handles[path]
			if handle ~= nil then
				local want = solverHidden[path] ~= true
					and paintHeld[path] ~= true
					and not pathEscapesClip(path, screenRectOf)
				if lastVisible[path] ~= want then
					adapter.setVisible(handle, want)
					lastVisible[path] = want
				end
			end
		end
	end

	-- A CLOSED SET IS ONLY CLOSED IF THE REACTIVE DOOR IS SHUT TOO
	-- (found live 2026-08-06, playing tutorial example 05).
	--
	-- `PropSpec.enum` exists because an enum prop used to accept any string and
	-- silently do nothing for an unrecognised one — `surface = "panel"` tagged the
	-- node with a selector no rule matched and painted nothing. But `schema.checkValue`
	-- runs at CONSTRUCTION, over a STATIC value. The word game bound `surface` to a
	-- memo returning "tileEmpty"/"tileCorrect"/…, never members of the surface enum,
	-- and all thirty board tiles rendered at BackgroundTransparency = 1: the exact
	-- defect the enum was added to remove, re-entering through the reactive door.
	--
	-- `tint` already had this rule (sheet_model.tintColor: "a bound tint is read long
	-- after construction, so this is the only place a reactive one is ever checked").
	--
	-- SCOPE, STATED HONESTLY (architecture review M-1). This runs inside
	-- `applyProp`/`applyStyleProp`, which are reached only for BINDING_PROPS and
	-- STYLE_PROPS — the PAINT and SEMANTICS channels. It therefore guards
	-- `surface`, `role`, `textAlign`, `scaleMode` and `shape`, and it does NOT
	-- guard an enum prop the SOLVER consumes: `anchor`, `alignH`/`alignV`,
	-- `overflow`, `align`, `reveal`, `axis`, `minColumnWidth`, `itemSizing`,
	-- `focusVisual`. A bound `itemSizing = "unifrom"` still resolves silently as
	-- `natural`. The complete seam is `mount.luau`'s binding write, which is where
	-- every bound value of every channel lands; moving it there is the recorded
	-- follow-up. Do not read this as "every enum prop" — it is not.
	local function assertEnumValue(class: string, prop: string, value: any)
		if type(value) ~= "string" then
			return
		end
		local classSpec = schema.forClass(class)
		local spec = if classSpec ~= nil then (classSpec.props :: any)[prop] else nil
		if spec == nil or spec.enum == nil then
			return
		end
		for _, allowed in spec.enum do
			if value == allowed then
				return
			end
		end
		error(
			`Facet {class}.{prop}: '{value}' is not one of {table.concat(spec.enum, " | ")}. `
				.. "A bound value outside the closed set is not a state — it paints nothing.",
			0
		)
	end

	local function applyProp(handle: any, node: any, prop: string)
		authority.assertWrite(node.class, if prop == "label" then "text" else prop, "binding")
		local value = node.props[prop]
		assertEnumValue(node.class, prop, value)
		-- B-BTN1: a content button's label is SEMANTICS, not paint. Writing it as
		-- text too would draw it underneath the custom content.
		if prop == "label" and node.class == "Button" and #node.children > 0 then
			value = ""
		elseif prop == "label" and node.class == "Button" then
			-- ...and an ICON button's label is semantics too: the drawn mark is the
			-- semantic glyph. Same seam the measure pass reads (renderer.drawnButtonText).
			value = renderer.drawnButtonText(node.props)
		elseif prop == "thickness" and type(value) == "string" then
			-- A PATH'S STROKE WEIGHT MAY NAME A METRIC, like the Divider's.
			-- The adapter writes engine pixels, so the name resolves here against
			-- the live snapshot — the same resolution point every other theme-owned
			-- number uses.
			value = themeSnapshot.resolveNumber(currentMetrics(), value)
		end
		adapter.setProp(handle, prop, value, "binding")
		stats.propWrites += 1
	end

	local function applyStyleProp(handle: any, node: any, prop: string)
		authority.assertWrite(node.class, prop, "style")
		assertEnumValue(node.class, prop, node.props[prop])
		adapter.setProp(handle, prop, node.props[prop], "style")
		stats.propWrites += 1
	end

	local function applyProps(handle: any, node: any)
		-- structural region nodes (When/ForEach) carry no user props
		for prop in node.props or {} :: any do
			-- `tint` is the ONE binding prop that is applied after the style props
			-- (ensureTree below), because it composes OVER the paint they settle: a
			-- surface written after a tint would overwrite the very property the tint
			-- claimed, and the node would wear its plain fill for as long as nothing
			-- else touched it.
			if emitsBinding(node.class, prop) and prop ~= "tint" then
				applyProp(handle, node, prop)
			end
		end
	end

	-- ---- INSTANCE RECYCLING (opt-in, default OFF) ---------------------------
	--
	-- A windowed list destroys a row at one end and builds an identical one at the
	-- other, every time the window slides, for no reason except that the PATH
	-- changed. Measured on this engine: build one 24-object row 0.252 ms, destroy
	-- it 0.045 ms, rewrite the same objects' properties 0.024 ms — **12x**. The
	-- structural pass (`Facet/mount`) was 0.66-0.97 ms/frame at every viewport,
	-- the largest single component of a frame.
	--
	-- Feature-detected on both sides: the adapter must offer
	-- `park`/`adopt`/`discardParked`. Since L-28 a THEMED node is eligible too —
	-- the adapter releases its chrome's path-keyed registrations on park and
	-- re-keys them on adopt — and `park` still refuses what cannot travel
	-- (clip-host role, presentation transform, motion scale, sibling-parented
	-- hit expander / float focus ring, a focused node). A refusal falls straight
	-- through to the ordinary remove, so the feature can only ever do nothing —
	-- never something different.
	-- ON BY DEFAULT; pass `recycleInstances = false` to opt out. It only ever avoids
	-- work: `park` refuses any node it cannot take intact and the refusal falls
	-- through to the ordinary remove, so the worst case is one boolean test per
	-- create and per remove.
	--
	-- WHY ON: the saving is proportional to CHURN, and churn is not what a creeping
	-- scroll does — it is what a FLING does. Measured on this workload: a steady
	-- scroll retires 2.8 objects/frame (0.035 ms/frame saved, inside the noise),
	-- while a seek that replaces the whole window retires 62.9 objects per jump
	-- (0.78 ms saved per jump, at a measured 12.4 us of engine work per object).
	-- On a low-end Android that avoided work is several times more expensive again,
	-- and it lands on exactly the frames a list feels worst on.
	local recycleEnabled = (opts == nil or opts.recycleInstances ~= false)
		and adapter.park ~= nil
		and adapter.adopt ~= nil
		and adapter.discardParked ~= nil
	-- key: the CREATION-TIME facts the adapter baked into the object. Class decides
	-- the engine class; the decoration hint decides its skin; canvasGroup decides
	-- the class outright. Two nodes agreeing on all three are interchangeable as
	-- far as construction goes — everything else is a property write the renderer
	-- is about to make anyway, because every per-path cache died with the old path.
	stats.recycleArmed = recycleEnabled
	local recyclePool: { [string]: { any } } = {}
	-- the key each live path was BUILT with. Recorded at create because the dying
	-- node's decoration hint is not available at remove time: `pathNodes` is cleared
	-- and refilled with LIVE paths before the sweep, so a dying path reads nil there
	-- and every parked handle would land in a bucket no create ever looks in.
	local recycleKeyOf: { [string]: string } = {}
	local recyclePooled = 0
	local RECYCLE_POOL_CAP = 64
	-- THE KEY INCLUDES THE DECLARED PROPERTY SET, and that is what makes carrying the
	-- property caches sound.
	--
	-- Adoption now writes only the properties that DIFFER from what the instance
	-- already holds. That is only safe if every property on the instance is one the
	-- new node also declares — otherwise a property the OLD identity set and the new
	-- one does not would survive, and nothing would ever clear it. (Proven, not
	-- assumed: the ragged case in `instance_recycling.spec` exists precisely because
	-- rows with different property sets are where that bug lives.)
	--
	-- So two nodes share a pool bucket only if they agree on class, decoration hint,
	-- canvasGroup AND the exact set of property names they declare. In a virtualized
	-- list every row comes from one blueprint, so they all agree and the pool works;
	-- anything else simply does not match and takes the ordinary create path.
	local propSigCache: { [any]: string } = {}
	local function propSignature(node: any): string
		local props = node.props
		if props == nil then
			return ""
		end
		local hit = propSigCache[props]
		if hit ~= nil then
			return hit
		end
		local names = {}
		for name in props do
			table.insert(names, name)
		end
		table.sort(names)
		local sig = table.concat(names, ",")
		propSigCache[props] = sig
		return sig
	end
	-- the hint goes in BY CONTENT (chrome_slots.hintKey), never by address: a
	-- windowed list rebuilds its cell blueprints on every slide, so a
	-- content-equal hint is a different table by construction and
	-- `tostring(hint)` made every hinted node's bucket unreachable (L-28)
	-- `createKind` names the ENGINE OBJECT (`render/instance_boundary.kindOf`), not
	-- merely whether there were creation options: two kinds that produce different
	-- classes must never share a bucket.
	local function recycleKey(class: string, hint: any, createKind: string, propSig: string): string
		return `{class}\0{chrome_slots.hintKey(hint)}\0{createKind}\0{propSig}`
	end
	local function drainRecyclePool()
		if recyclePooled == 0 then
			return
		end
		for _, bucket in recyclePool do
			for _, handle in bucket do
				adapter.discardParked(handle)
			end
		end
		table.clear(recyclePool)
		recyclePooled = 0
	end

	-- FORWARD. The per-path property caches are declared throughout this file, well
	-- after `ensureTree` — so the park/adopt handlers that move them are declared here
	-- and defined once every cache exists. (Assigning them inline read `lastTextSize`
	-- as nil and took out 47 cases.)
	local captureParkedProps: (path: string) -> any
	local restoreParkedProps: (path: string, carried: any) -> ()

	local function ensureTree(node: any)
		if handles[node.path] == nil then
			-- THE LIFETIME BOOKKEEPING, first, so it is impossible to reach a `return`
			-- or an adapter refusal below without it. `props.onDisappear` is captured
			-- BY VALUE here rather than read off the tree at removal time, because at
			-- removal the node is no longer in the tree — that is the whole point of
			-- the hook. `props.hidden` is registered the same way the sweep clears it.
			if node.props ~= nil then
				if node.props.onAppear ~= nil then
					table.insert(appearQueue, { path = node.path, fn = node.props.onAppear })
				end
				if node.props.onDisappear ~= nil then
					disappearHooks[node.path] = node.props.onDisappear
				end
				if node.props.hidden == true then
					authoredHidden[node.path] = true
				end
				-- read at mount so a node born faded/scaled/rotated/offset paints that
				-- way on its FIRST frame; the write happens after the handle exists, below
				if
					node.props.opacity ~= nil
					or node.props.scale ~= nil
					or node.props.rotation ~= nil
					or node.props.offset ~= nil
				then
					readAuthoredPresentation(node)
				end
			end
			-- The DECORATION HINT rides the blueprint's internal `meta` channel
			-- (chrome_slots.readHint) — the same channel the input contribution
			-- uses, never the public prop bag. It is handed to `create` because
			-- skinning is the adapter's LAST construction step: a hint delivered
			-- afterwards would build one decoration and immediately churn it for
			-- another. Targets that do not skin ignore the argument.
			-- 5th argument: the creation-time facts the adapter can only honour while
			-- it is CHOOSING the engine object, so they cannot arrive as a later prop
			-- write. WHICH nodes earn one, and of which kind, is the nested tree's
			-- boundary predicate and lives in `render/instance_boundary` — the one
			-- predicate the nested-tree migration changes, and the reason it has a
			-- module rather than two branches in the busiest function here.
			local createOpts: any = instance_boundary.createOptsFor(node)
			local hint = chrome_slots.readHint(node)
			-- A STAGE IS NEVER A DECORATION SURFACE (reference-app matrix,
			-- 2026-08-08). An ornate package's whole-art recipe painted its
			-- `control` plate OVER a Stage's ViewportFrame — the 3D scene, which
			-- IS the node's content, vanished behind the skin. The engine-content
			-- leaf pins the no-slot hint at creation so no package recipe can
			-- ever cover the scene; a theme still reaches the pane through the
			-- authored stroke/corners modifiers, which decorate the box's edge
			-- rather than its face.
			-- ...AND `UI.Foreign` JOINS IT FOR THE SAME REASON, ONE STEP STRONGER: a Foreign box's face IS somebody else's instance, so a
			-- package recipe painting a `control` plate over it would cover content
			-- the framework does not even know the shape of. A second member would
			-- have made this a chain of string compares on the hot mount path, so it
			-- became one table lookup (NO_DECORATION_CLASSES, module scope) — the
			-- off-path node now pays one index instead of one compare.
			if NO_DECORATION_CLASSES[node.class] then
				-- UNCONDITIONAL (architecture review F14): "never a decoration
				-- surface" is a fact about the CLASS, so no channel — not even a
				-- blueprint-supplied hint — may override it into a covering slot.
				hint = { slot = chrome_slots.NO_SLOT }
			end
			local adopted: any = nil
			if recycleEnabled then
				local key = recycleKey(node.class, hint, instance_boundary.kindOf(createOpts), propSignature(node))
				local bucket = recyclePool[key]
				if bucket ~= nil and #bucket > 0 then
					local candidate = table.remove(bucket)
					recyclePooled -= 1
					-- ADOPT MAY REFUSE. It is the adapter's judgement, not ours, and a
					-- refusal must cost nothing but a fresh create — so the candidate is
					-- discarded rather than pushed back, which would let one permanently
					-- un-adoptable handle be retried on every create forever.
					-- the incoming hint rides along so the adapter can hold its own
					-- mismatch rule (the bucket key already agrees by construction,
					-- but the adapter must not depend on its caller's bookkeeping)
					-- ...AND SO DOES THIS SURFACE'S ROOT (NM-H4a): an adoption re-parents,
					-- and only the caller knows which surface it re-parents into.
					if adapter.adopt(candidate, node.path, node.class, hint, rootHandle) then
						adopted = candidate
						-- restore the instance's own property record under its new path,
						-- so `applyProps` writes only what actually differs
						local carried = candidate.parkedProps
						if carried ~= nil then
							candidate.parkedProps = nil
							restoreParkedProps(node.path, carried)
						end
					else
						candidate.parkedProps = nil
						adapter.discardParked(candidate)
					end
				end
			end
			if adopted ~= nil then
				handles[node.path] = adopted
				stats.recycled += 1
			else
				local made = adapter.create(rootHandle, node.path, node.class, hint, createOpts)
				handles[node.path] = made
				stats.creates += 1
				-- nodes the adapter declined to give an engine object. Counted so a
				-- runtime disable is visible: the source-shape test can only see that
				-- the RULE exists, not that it is switched on.
				if made ~= nil and made.elided == true then
					stats.elided += 1
				end
			end
			if recycleEnabled then
				recycleKeyOf[node.path] =
					recycleKey(node.class, hint, instance_boundary.kindOf(createOpts), propSignature(node))
			end
			-- THE PER-CONTROL SENSORY VERB, published once per handle (see
			-- target_contract's `setActivationFeedback`). Bounded to the classes
			-- that can be activated, because a verb on a Box describes an event
			-- that cannot happen there; written UNCONDITIONALLY for those classes —
			-- the nil included — because a recycled instance carries the previous
			-- control's property, and "only write when there is something to say"
			-- is exactly how a commit button's sensation leaks onto its successor.
			-- Mount-static by construction (a blueprint is frozen), so there is no
			-- update path: a changed declaration is a changed blueprint, which is a
			-- remount.
			if TAPPABLE[node.class] and adapter.setActivationFeedback ~= nil then
				adapter.setActivationFeedback(handles[node.path], node.activationFeedback)
			end
			applyProps(handles[node.path], node)
			-- ...and the authored triple, now that a handle exists (the channel's own
			-- gate keeps a node declaring none of the three to one hash lookup)
			channel.paintAuthored(node.path)
			-- the engine text inset must MATCH the solver's padding (the adapter
			-- used to hardcode 12px, which rendered a 22px star button's glyph
			-- into a negative text area — playlist place, 2026-07-20). The write
			-- itself is `commit_walks.padding`'s, per solve: writing it ONCE here meant a
			-- theme commit moved the solver's padding while the engine kept the
			-- construction inset for the rest of the session.
			-- geometry-affecting typography inputs are layout authority (§11):
			-- applied identically to measurement and render. The scaled value is
			-- written by `commit_walks.textScale`, per solve, so a displaySize flip
			-- (handheld -> TV dock) re-scales paint to match the re-solved layout.
			-- pointer taps flow through the adapter into the same semantic
			-- activate path as focus+Activate (touch parity). Routed through the
			-- per-press dedupe, the platform verifier's one-activation rule: when a node
			-- ALSO carries a drag detector,
			-- some input classes deliver both this native Activated AND the
			-- detector's release — one press, one activation, first signal wins.
			local onNodeTap = opts and opts.onNodeTap
			if onNodeTap ~= nil and TAPPABLE[node.class] and adapter.setActivateHandler ~= nil then
				local path = node.path
				adapter.setActivateHandler(handles[path], function(meta: any?)
					-- A HIDDEN NODE RESPONDS TO NOTHING (round 3, item D). The
					-- convention this prop is named for is explicit that a hidden view
					-- "can't receive or respond to interactions", and this is the one
					-- gate that has to
					-- hold it: `solverHidden` is the MERGED verdict the visibility walk
					-- writes for every node, so the same line covers an authored
					-- `hidden` and a losing `ViewThatFits` candidate. The candidate case
					-- was previously carried only by its zero rect and the retracted hit
					-- expander — true, but a consequence rather than a rule, and an
					-- authored hide keeps its full-size box on purpose.
					if solverHidden[path] == true then
						return
					end
					if dispatchNodeTapOnce(path) then
						if tapArmsInstead(path, meta) then
							return
						end
						onNodeTap(path, meta)
					end
				end)
			end
			-- pointer hover layer (UI-PARADIGM-001, matrix R§7): interactive nodes
			-- get a hover state, but ONLY when the pointer class is live. A
			-- pure-touch device allocates no hover wiring (hover does not exist off
			-- pointer); nothing essential lives behind it — the visual is a free
			-- preview, the activate path above is class-agnostic. Optional adapter
			-- method: targets without it degrade cleanly (like setRootDisplayOrder).
			if
				adapter.enableHover ~= nil
				and HOVERABLE[node.class]
				and env:get("interactionClasses"):get().pointer == true
			then
				adapter.enableHover(handles[node.path])
			end
			-- FULL-VALUE DISCLOSURE engagement zones, from the large-text round: a Text
			-- that declares `disclose` gets pointer enter/leave and touch
			-- long-press observation on its own instance, routed to the
			-- presenter's engagement seams. Wired at mount like enableHover (the
			-- prop is construction-only), gated per input class the same way —
			-- and only OBSERVED: the label still sinks nothing. Whether a plate
			-- actually appears stays the presenter's call (it re-checks live
			-- truncation facts on every engagement).
			-- class-agnostic like the presenter's walker: a Toggle's
			-- one-line label declares disclose the same way a Text does
			-- ...and a `reveal` node gets the SAME zones: the static plate is the
			-- auto reveal's declared full-value alternative (director 2026-08-04)
			-- ...and a `help` node (D3a) joins the HOVER half and ONLY that half:
			-- the convention binds no gesture to help, and the press stayed with the plate
			local discloses = (node.props or {}).disclose == true or (node.props or {}).reveal ~= nil
			if (discloses or (node.props or {}).help ~= nil) and adapter.enableDisclosure ~= nil then
				local hoverCb = opts and (opts :: any).onDiscloseHover
				local pressCb = opts and (opts :: any).onDiscloseLongPress
				if hoverCb ~= nil or pressCb ~= nil then
					local path = node.path
					local classes = env:get("interactionClasses"):get()
					adapter.enableDisclosure(handles[path], {
						hover = if hoverCb ~= nil and classes.pointer == true
							then function(over: boolean)
								hoverCb(if over then path else nil)
							end
							else nil,
						longPress = if pressCb ~= nil
								and discloses
								and classes.touch == true
							then function(held: boolean)
								pressCb(if held then path else nil)
							end
							else nil,
					})
				end
			end
			-- PUBLIC DRAG/DROP DECLARATIONS. Registration happens at
			-- mount and unregistration at removal (structuralSync), so a
			-- windowed row that scrolls out of the window stops being a drop
			-- target the frame it stops existing — which is the honest answer:
			-- the hit-test is over VISIBLE targets, and edge autoscroll is how a
			-- row that is not visible becomes reachable.
			local dropDecl = dragContract.readTarget(node)
			if dropDecl ~= nil then
				dragUnbind[node.path .. "\0drop"] = dragRegistry().registerTarget(node.path, dropDecl)
			end
			local dragDecl = dragContract.readSource(node)
			local dragAcquiredNatively = false
			if dragDecl ~= nil then
				-- a DISABLED source acquires nothing (verifier P2-3): the tap gate
				-- already honored enabled=false; the SESSION gate must too. The decl
				-- is frozen, so the gate lives in a renderer-side map the registry
				-- consults per acquisition (reads the LIVE resolved prop — mount
				-- writes updates into node.props)
				local declNode = node
				local declEnabled = dragDecl.enabled
				dragSourceEnabled[node.path] = function(): boolean
					if declNode.props ~= nil and declNode.props.enabled == false then
						return false
					end
					-- the DECLARATION's own gate, from the drag design: a source may refuse to be
					-- picked up while the control stays enabled and activatable, so a
					-- blocked affordance can still explain itself on a tap
					if declEnabled == nil then
						return true
					end
					if type(declEnabled) == "table" and type((declEnabled :: any).get) == "function" then
						return (declEnabled :: any):get() ~= false
					end
					return declEnabled ~= false
				end
				local registry = dragRegistry()
				local unregisterSource = registry.registerSource(node.path, dragDecl)
				armOnTapDecl[node.path] = dragDecl.armOnTap == true
				dragUnbind[node.path .. "\0drag"] = function()
					dragSourceEnabled[node.path] = nil
					armOnTapDecl[node.path] = nil
					unregisterSource()
				end
				-- ACQUISITION, IN PREFERENCE ORDER: the engine's own detector when
				-- the adapter has one (it owns cross-input drag motion), else the
				-- pointer capture below. Either way the promotion test, the
				-- session and every terminal are the registry's.
				local handlers = registry.detectorHandlers(node.path)
				local rawEnd = handlers.onEnd
				local tapPath = node.path
				local tapClass = node.class
				local tapNode = node
				handlers.onEnd = function(pos: any)
					-- the drag design's pointer-capture rule, LIVE half (found 2026-07-27 by a
					-- real injected click):
					-- the engine's UIDragDetector CONSUMES the click, so a release
					-- under the promotion token never reaches `.Activated`. The
					-- registry answers "tap" for exactly that case and the tap is
					-- dispatched through the SAME node-tap path a native tap takes —
					-- same policy checks, same semantic activate, never eaten.
					--
					-- BOUNDED AGAINST DOUBLE-FIRE, the platform verifier's rule: on some
					-- input classes the engine delivers `Activated` even WITH a
					-- detector (gamepad A on a selected button is documented to), so
					-- both paths route through dispatchNodeTapOnce — whichever signal
					-- arrives first wins the press, the second inside the window is
					-- the same press echoing, never a second activation. And the
					-- synthesized tap honors the same gate the native path does
					-- as the platform verifier requires: a disabled node taps nothing.
					local outcome = rawEnd(pos)
					local onNodeTap = opts and opts.onNodeTap
					if
						outcome == "tap"
						and onNodeTap ~= nil
						and TAPPABLE[tapClass]
						and (tapNode.props == nil or tapNode.props.enabled ~= false)
						and dispatchNodeTapOnce(tapPath)
					then
						if not tapArmsInstead(tapPath, nil) then
							onNodeTap(tapPath, { via = "dragDetectorTap" })
						end
					end
				end
				local detach = attachDetector(node.path, handlers)
				if detach ~= nil then
					dragAcquiredNatively = true
					detectorTapGuard[node.path] = true
					local rawDetach = detach
					detach = function()
						detectorTapGuard[node.path] = nil
						lastNodeTapAt[node.path] = nil
						rawDetach()
					end
					dragUnbind[node.path .. "\0det"] = detach
				end
			end
			-- pointer zones: nodes carrying pointer callbacks get
			-- capture-based down/move/up through the adapter; handlers receive
			-- the node path and the renderer's rect lookup for drag math.
			--
			-- THAT LOOKUP IS `screenRectOf`, NOT `rectOf` (forced closed by
			-- the device report of 2026-07-28 — gallery example 02 on a 6.1-inch
			-- phone: "when I pick up a row it doesn't always appear under my finger,
			-- the picked up chip moves up as I scroll down"). The whole reason a
			-- handler is handed a rect is to compare it against `pos`, and `pos` is
			-- always WINDOW space. A solved rect inside a scroll host is CANVAS
			-- space — the engine shifts it by CanvasPosition — so a block Table
			-- inside a scrolling page did its drag arithmetic against a rect that
			-- does not move while the page does, and every verdict was wrong by the
			-- page's scroll offset.
			--
			-- It was deferred on "no current consumer drags mid-slide", which
			-- weighed only the PRESENTATION half of the shift and missed the SCROLL
			-- half — which a shipped example lives in. Handlers that use rects as
			-- pure DIFFERENCES (Table's resize guide) or read only w/h are
			-- unaffected: the shift is common to both terms.
			local wantsDragCapture = dragDecl ~= nil and not dragAcquiredNatively
			if
				adapter.setPointerHandlers ~= nil
				and (
					wantsDragCapture
					or (node.props and (node.props.onPointerDown or node.props.onPointerMove or node.props.onPointerUp))
				)
			then
				local path = node.path
				local props = node.props or {}
				local registry = if wantsDragCapture then dragRegistry() else nil
				adapter.setPointerHandlers(handles[path], {
					down = function(pos: any)
						-- the drag declaration is offered the press FIRST: only it
						-- can decline on touch (so a native scroll host under the
						-- node keeps the pan), and a decline must reach the adapter
						-- before an authored handler claims the capture
						if registry ~= nil and registry.pointerDown(path, pos) == false then
							return false
						end
						if props.onPointerDown then
							-- propagate the CLAIM/DECLINE verdict: a handler
							-- returning false dissolves the capture so a
							-- sibling zone under the same point can take it
							return props.onPointerDown(path, pos, screenRectOf)
						end
						return nil
					end,
					move = function(pos: any)
						if registry ~= nil then
							registry.pointerMove(path, pos)
						end
						if props.onPointerMove then
							props.onPointerMove(path, pos, screenRectOf)
						end
					end,
					up = function(pos: any)
						if registry ~= nil then
							registry.pointerUp(path, pos)
						end
						if props.onPointerUp then
							props.onPointerUp(path, pos, screenRectOf)
						end
					end,
					-- the zone died mid-drag; reason "removed" may be answered
					-- with true = keep the capture alive (a drag-owned lift
					-- unmounting its own origin row)
					cancel = function(reason: string?)
						local keep: boolean? = nil
						if registry ~= nil then
							keep = registry.pointerCancel(path, reason)
						end
						if props.onPointerCancel then
							local authored = props.onPointerCancel(path, reason)
							if authored ~= nil then
								return authored
							end
						end
						return keep
					end,
				})
			end
			-- text-entry seam (§17 Phase 5, TextField): the control supplies
			-- onTextChanged/onFocusGained/onFocusLost as node props (functions,
			-- not engine writes); the adapter wires them to the TextBox and
			-- reports edits/focus back through them. Optional adapter method —
			-- absent adapters degrade to a read-only field (§13 seam).
			if
				adapter.setTextInputHandlers ~= nil
				and node.class == "TextField"
				and node.props
				and (node.props.onTextChanged or node.props.onFocusGained or node.props.onFocusLost)
			then
				-- bind the node's full path into onFocusGained: on the real
				-- engine a native-tap focus never routes through handleActivate,
				-- so this is where the control learns its path for keep-visible
				-- (F1). The adapter also passes its handle path; the renderer
				-- guarantees it (path arg wins, node.path is the fallback).
				local nodePath = node.path
				local onFocusGained = node.props.onFocusGained
				adapter.setTextInputHandlers(handles[node.path], {
					onTextChanged = node.props.onTextChanged,
					onFocusGained = if onFocusGained ~= nil
						then function(path: string?)
							onFocusGained(path or nodePath)
						end
						else nil,
					onFocusLost = node.props.onFocusLost,
				})
			end
			-- real clipping (touch-scroll design): a container declaring
			-- clipChildren becomes an engine clip host — its descendants
			-- render inside it and partial overflow crops
			if node.props and node.props.clipChildren == true then
				authority.assertWrite(node.class, "clipChildren", "layout")
				adapter.setProp(handles[node.path], "clipChildren", true, "layout")
			end
			-- wheel scrolling (Phase 4 touch-scroll design): scroll containers
			-- declare onScrollWheel(path, delta, rectOf); the adapter routes
			-- hover-wheel input to it
			if adapter.setScrollHandler ~= nil and node.props and node.props.onScrollWheel then
				local path = node.path
				local props = node.props
				adapter.setScrollHandler(handles[path], function(delta: number)
					props.onScrollWheel(path, delta, rectOf)
				end)
			end
			-- style-authority hints: surface/text roles + Phase 4 shadow and
			-- corner styling (§7.3, §17; visuals resolve inside the adapter's
			-- style application — headless targets keep the data as the dump)
			for _, styleProp in STYLE_PROP_ORDER do
				local hint = node.props and node.props[styleProp]
				if hint ~= nil then
					applyStyleProp(handles[node.path], node, styleProp)
				end
			end
			-- ...and the CONTINUOUS COLOUR LAST. It claims the
			-- same engine property the surface above just painted, so it has to be the
			-- final word — and because it is last, the adapter's blend resolves against
			-- a node whose style paint is already settled. A reactive change later rides
			-- the ordinary refresh path, by which time the same is true.
			if node.props ~= nil and node.props.tint ~= nil then
				applyProp(handles[node.path], node, "tint")
			end
		end
		for _, child in node.children do
			ensureTree(child)
		end
	end

	-- one walk, two jobs: the live-path set the removal sweep needs, and the
	-- nearest-scroll-host map `screenRectOf` needs. Threading the host down the
	-- recursion is free here and costs a whole-tree search per hit-test if it is
	-- computed on demand instead.
	local function livePaths(node: any, set: { [string]: boolean }, host: string?, clip: string?)
		set[node.path] = true
		scrollHostOf[node.path] = host
		clipHostOf[node.path] = clip
		-- ...and the stroked-path census (RS-PATHCLIP): the cull runs over this
		-- set, so a surface with no `UI.Path` never pays for the rule existing.
		if node.class == "Path" then
			pathNodes[node.path] = true
			pathNodeCount += 1
		end
		--[[ ...and the census the overhang lift resolves against (`hit_lift`):
			which paths can actually SINK a press. Collected on this walk for the same
			reason the two above are — it is free here, and a whole-tree search per
			expander otherwise.

			THE VALUE SAYS WHO DECLARED IT, and it is not decoration (ruling R23,
			2026-08-21). `hit_lift` wants EVERY sinker and iterates the keys; the
			hit-floor walk wants only the ones the AUTHOR declared, because the
			framework may not take the accessibility floor off its own synthesized
			affordance — the same line `hit_lift`'s own doctrine already draws when it
			refuses to lift one expander over another. A framework affordance is a KEY
			WITH A FALSE VALUE, so never write `if inputSinks[path] then`: ask
			`inputSinks[path] == true` for "the author's", or iterate for "any". ]]
		if INPUT_SINKING[node.class] or (node.props ~= nil and node.props.active == true) then
			-- framework-declared today means the ONE prop the schema documents that
			-- way (`expandTarget`, the region's expand affordance, which authors
			-- never write). A second synthesized affordance joins by being named
			-- here, and R23 is the ruling that decides whether it should.
			inputSinks[node.path] = node.props == nil or node.props.expandTarget == nil
		end
		local nextHost = if node.class == "ScrollView" then node.path else host
		-- a ScrollView is a clip host by construction (the adapter mounts a real
		-- scrolling host); any container may declare itself one
		local nextClip = if node.class == "ScrollView"
				or (node.props ~= nil and node.props.clipChildren == true)
			then node.path
			else clip
		for _, child in node.children do
			parentNodeOf[child.path] = node
			livePaths(child, set, nextHost, nextClip)
		end
	end

	-- the scaled text size last written per path. The paint seam that writes it —
	-- authored sizes, intrinsic sizes, and why it runs inside the solve — is
	-- `commit_walks.textScale`.
	local lastTextSize: { [string]: number } = {}
	-- ...and the FACE beside the size, from the SAME role (F2): the descriptor key
	-- last written per path. Same seam, same walk.
	local lastTextFont: { [string]: string } = {}

	-- the effective four sides last written per path — a Button's engine text inset
	-- and an authored `Text` padding both go out on `commit_walks.padding`, which
	-- carries the reasoning and the device report behind the second one.
	local lastPadding: { [string]: string } = {}

	-- the compact-ladder verdict last written per path. The seam that writes it,
	-- and why a post-solve seam is the only place it can be decided, is
	-- `commit_walks.textVerdicts`.
	local lastCompact: { [string]: boolean } = {}

	-- ...and the WRAP verdict, on the same walk. `nil` means "never written", which
	-- is the adapter's own default, so the common `wraps = true` node costs zero
	-- writes; unlike `lastCompact` this IS a value the instance holds, so it rides
	-- the parked-props record below (`commit_walks.textVerdicts` has the rest).
	local lastWrapped: { [string]: boolean } = {}

	-- The instance's own property record, moved with it across a recycle. These say
	-- what the ENGINE OBJECT holds, so they stay true when the path changes — which is
	-- what lets adoption write only the differences.
	--
	-- TWO ARE DELIBERATELY EXCLUDED, and the difference is worth stating: a cache may
	-- be carried only if it records a VALUE the instance holds. `solverHidden` is a
	-- verdict about the node. `lastCompact` looks like a value and is not — it gates
	-- `commit_walks.textVerdicts`' compact half, whose WRITE depends on the new node's label, so a carried
	-- `true` skips re-applying a different row's glyph and the previous row's label
	-- survives. (Caught by "a REMOUNTED button gets its verdict re-applied", which is
	-- itself the pin for a defect found live on RascalRally's watch-cycle buttons.)
	captureParkedProps = function(path: string): any
		return {
			rect = lastRects[path],
			z = lastZ[path],
			textSize = lastTextSize[path],
			textFont = lastTextFont[path],
			padding = lastPadding[path],
			visible = lastVisible[path],
			hitRect = lastHitRects[path],
			textWrapped = lastWrapped[path],
		}
	end
	restoreParkedProps = function(path: string, carried: any)
		lastRects[path] = carried.rect
		lastZ[path] = carried.z
		lastTextSize[path] = carried.textSize
		lastTextFont[path] = carried.textFont
		lastPadding[path] = carried.padding
		lastVisible[path] = carried.visible
		lastHitRects[path] = carried.hitRect
		lastWrapped[path] = carried.textWrapped
	end
	-- THE COMMIT WALKS (`src/render/commit_walks`): the six write loops that spend
	-- a finished solve — the two typography paint seams, the text verdicts, the
	-- visibility verdict, the hit floor and the native scroll canvas. Built once
	-- per attach over the records above, every one of which is a table this file
	-- declares, clears on removal and carries across a recycle, and which that one
	-- reads and writes BY REFERENCE. Declared here rather than beside the rect
	-- pass because five of those records do not exist until this line.
	local commitWalks = commit_walks.new({
		adapter = adapter,
		handles = handles,
		stats = stats,
		rectsEqual = rectsEqual,
		paintedRectIn = paintedRectIn,
		pathEscapesClip = pathEscapesClip,
		reculPathClips = reculPathClips,
		lastTextSize = lastTextSize,
		lastTextFont = lastTextFont,
		lastPadding = lastPadding,
		lastCompact = lastCompact,
		lastWrapped = lastWrapped,
		lastVisible = lastVisible,
		lastHitRects = lastHitRects,
		lastScrollRegions = lastScrollRegions,
		scrollAutoscroll = scrollAutoscroll,
		pathClipObservers = pathClipObservers,
		solverHidden = solverHidden,
		paintHeld = paintHeld,
		pathNodes = pathNodes,
		inputSinks = inputSinks,
	})

	-- the inputs of the most recent solve, for the opt-in boundary analysis below
	local lastSolveInputs: any = nil

	-- ---- INCREMENTAL LAYOUT, STAGE 2 v2 — SKIP SUBTREES INSIDE ONE SOLVE -------
	--
	-- v1 re-solved the boundary subtree as its own ROOT and it could not be made
	-- correct: a sub-solve gets a fresh `ctx` (no `hasScroll`, `hiddenDepth` 0, zeroed
	-- insets) and a screen-root policy applied to a node that is not a screen. Ten
	-- existing cases found ten ways that mattered, starting with a `percent` box
	-- resolving its fraction against itself.
	--
	-- v2 keeps ONE solve from the root — same traversal, same ctx, same policies — and
	-- lets the solver SKIP a subtree it can prove cannot have changed: no dirty node
	-- inside it, and the same offer/rect it had last time. Nothing is re-based,
	-- re-rooted or re-parented, so there is no second context to disagree with the
	-- first. The published verdicts and diagnostics for a skipped subtree are replayed
	-- from the previous result, which is exactly the mechanism the measure memo in
	-- `solver.measure` already uses (and which a differential fuzz once caught
	-- returning geometry without them).
	local incrementalEnabled = opts == nil or (opts :: any).incrementalLayout ~= false
	local lastResult: any = nil
	local dirtyContains: { [string]: boolean }? = nil

	-- `controller.onSolved` listeners: run at the tail of every OUTERMOST solve.
	-- The presenter uses exactly one of these, to feed solved geometry to the
	-- consumers that measure this surface (see the tail of solveAndApply, L-31).
	local solvedListeners: { () -> () } = {}
	local notifyingSolved = false

	--[[ ── THE SOLVE'S OWN FEEDBACK, DRAINED BY THAT SOLVE ─────────────────────
		L-31 gave the measure→publish cycle its settle phase, and closed it for a
		publication that is an ENVIRONMENT write: `geometryFacts` depends on the env
		signal, so the settle callback below re-solves and the cycle lands in one
		flush. A publication that is a NODE PROP took a different road. `mount.luau`
		binds a reactive prop through `core:observe`, which writes `node.props` and
		pushes a dirty entry — and that queue is drained by `controller.refresh()`,
		on the host's NEXT frame. So the solve that produced the measurement laid the
		tree out against the OLD prop and the correction arrived a frame later
		(the node that must spend a reservation lives outside it: a Table's header
		pays the gutter its body spent, and `present`'s own solve paid it late).

		THE MARK IS THE MECHANISM, and it is what keeps this from becoming "solve on
		every write". `feedbackMark` is the tree's dirty sequence as the notification
		BEGAN, so the only dirt this ever acts on is dirt a `solvedListener` caused.
		Two arrival times, one rule:

		  * the solve came from `refresh`/`initialRender` (no flush open), so the
		    listener's `:set` flushes synchronously and the dirt is on the tree by
		    the time the notify loop returns — drained inline, right there;
		  * the solve came from the settle callback below (a flush IS open), so the
		    write joins `writeSet`, the core ends the pass, drains propagation and
		    RESTARTS the pass from the first callback (`core/contract.luau`) — which
		    is the first moment the dirt exists. `feedbackArmed` carries the mark
		    across that one pass boundary.

		NO NEW CYCLE. The re-solve is bounded by `SOLVE_FEEDBACK_ROUND_CAP` and a
		publication that will not converge is the same loud error the core's
		`FEEDBACK_ROUND_CAP` already produces — quarantined into `lastError` when it
		fires from the settle phase, propagated from `refresh` exactly as a throwing
		`solvedListener` already is (see the notify block). It is not a second
		scheduler: it runs inside the solve it belongs to, publishes nothing, and
		touches no observer, so glitch-freedom and observer creation order are
		untouched by construction.

		WHAT IT DELIBERATELY DOES NOT DO: consume the dirty queue. `refresh` still
		sees those entries and still commits the paint half of the prop — this
		closes the LAYOUT frame, not the property-write cadence, and leaving the
		queue alone is what keeps `onAppear`/`onDisappear` ordering and the
		structural sync byte-identical. The cost is `stats.feedbackSolves`: one
		extra solve on the frame a consumer publishes, which is the solve the next
		frame used to pay. ]]
	local SOLVE_FEEDBACK_ROUND_CAP = 8
	local feedbackMark = 0
	local feedbackArmed = false
	local feedbackDepth = 0
	local solvingFromSettle = false
	local resolveForFeedback: () -> ()
	--[[ `root.dirtySeq()` as it stood when the last FULL solve began, or -1 for
		"no full solve has completed". Every dirty pushed at or below it was already
		on the tree when that solve read the props, so a full solve has answered it;
		anything above it is genuinely unsolved. This is what lets `refresh` tell a
		queue entry a settle-phase solve already consumed from one it has not seen
		(owed row O-20) — see THE STALE-LAYOUT-DIRT TEST in `refresh`.

		FULL solves only. An incremental solve covered the subtree in
		`dirtyContains` and nothing else, so it cannot speak for the queue.
		Committed after the solve body rather than before it, so a solve that
		throws leaves the mark where it was and `refresh` re-solves.

		THE FULL-SOLVE GUARD IS A RECORDED NULL RESULT, kept deliberately. Deleting
		`solvedEverything = false` at the reuse branch reddens NOTHING in the suite
		(mutation M4, 2026-08-15) — and on today's code that is correct rather than
		a coverage hole: `dirtyContains` is set only inside `refresh`, and that same
		`refresh` has already drained the queue, so an incremental solve's mark can
		never be the one a later skip consults. It stays because it is what makes
		the name of this variable true, and because the day `dirtyContains` outlives
		one refresh the alternative is a surface that silently stops laying out. ]]
	local fullSolveSeq = -1

	local function solveAndApply()
		stats.solves += 1
		-- read BEFORE the solve: the props of everything dirtied up to here are
		-- already written (`mount`'s bound-prop observer writes `node.props` and
		-- THEN pushes), so this solve sees them. Whether it may be COMMITTED is
		-- decided at the reuse branch below, which is the one place that knows
		-- whether this turned out to be a full solve or an incremental one.
		local seqAtSolveStart = root.dirtySeq()
		local solvedEverything = true
		local vp = env:get("viewportRect"):get()
		local insets = env:get("coreSafeInsets"):get()
		-- deviceSafeContent, from the native-substrate round: the notch/rounded-corner
		-- device insets are a SEPARATE fact from the CoreGui insets; a screen
		-- opting into deviceSafeContent clears BOTH, so the content rect insets
		-- by the per-edge maximum. coreSafeContent (default) keeps the historic
		-- CoreGui-only behavior. Exactly one authority applies insets: these
		-- facts feed the solver; the ScreenGui renders IgnoreGuiInset=true.
		-- edgeToEdge: a DECORATION layer, not content. Safe areas exist so content
		-- is readable and reachable; a scrim or a backdrop is neither — it has to
		-- paint to the edges or it draws a rectangle inside the screen with the
		-- world showing around it, which is what a device capture showed.
		--
		-- THIS NAME WAS ALREADY BEING PASSED AND NEVER READ. The presenter has
		-- asked for `rootPolicy = "edgeToEdge"` on every scrim since scrims
		-- existed, with a comment saying "covers the whole viewport (incl.
		-- insets)" — and no branch here matched it, so every scrim silently got
		-- the ordinary content insets instead. A policy string nothing consumes
		-- is indistinguishable from a policy that works until you look.
		--[[ ...AND THE FOURTH CASE, which is the one `bandInsets` was published for. `platformChrome` is the single authority that can say "the
			top band is an L": `insets` clears everything (what `deviceSafeContent`
			applies) and `bandInsets` is the same four edges with the top brought up to
			where the platform's FREE strip starts. Reading the derived fact rather
			than re-deriving it is the whole point — it is the one place that knows
			what a zero means, and it carries the belt an inset measured against
			another viewport needs. `bandFullTop` rides beside it: the platform's whole
			top reservation, which is what the composition reserves when nothing
			declares a `topbar` region. ]]
		local band: any = nil
		local bandFullTop: number? = nil
		if rootPolicy == "edgeToEdge" then
			insets = { top = 0, bottom = 0, left = 0, right = 0 }
		elseif rootPolicy == "bandSafeContent" then
			local chrome = env:get("platformChrome"):get()
			if type(chrome) == "table" then
				insets = (chrome :: any).bandInsets
				band = (chrome :: any).band
				bandFullTop = ((chrome :: any).insets :: any).top
			end
		elseif rootPolicy == "deviceSafeContent" then
			local device = env:get("deviceSafeInsets"):get()
			if type(device) == "table" then
				insets = {
					top = math.max(insets.top, device.top or 0),
					bottom = math.max(insets.bottom, device.bottom or 0),
					left = math.max(insets.left, device.left or 0),
					right = math.max(insets.right, device.right or 0),
				}
			end
		end
		-- split text-scale seams, from the native-substrate round: MEASURE reserves
		-- the engine-scaled
		-- bounds (typographyScale includes the player preference); PAINT writes
		-- only authored scale — the engine applies the preference itself at
		-- draw time (double-application fix, corrections §9). The RESERVATION
		-- FLOOR (measure >= paint, preferred-text sweep 2026-07-24) and its
		-- garbage-fact guards live once, in `themes/snapshot.reserveScale`, which
		-- the public `Facet.text.facts` calls on the same two keys — so a
		-- consumer PREDICTING a text box reserves at exactly this scale.
		local paintScale = env:get("typographyPaintScale"):get()
		if type(paintScale) ~= "number" or paintScale ~= paintScale then
			paintScale = 1
		end
		local measureScale = themeSnapshot.reserveScale(env:get("typographyScale"):get(), paintScale)
		-- ten-foot presentation (input-paradigms expansion): TVs clip edges,
		-- so overscan margins compose ON TOP of the CoreGui safe insets while
		-- the display class is Large; a near display keeps the full canvas
		-- NOT UNDER `bandSafeContent`: `platformChrome` composes the overscan into
		-- both of its inset records itself, so a second addition here would spend a
		-- television's margin twice
		if rootPolicy ~= "bandSafeContent" and env:get("distanceProfile"):get() == "ten-foot" then
			local overscan = env:get("effectiveOverscanInsets"):get()
			if type(overscan) == "table" then
				insets = {
					top = insets.top + (overscan.top or 0),
					bottom = insets.bottom + (overscan.bottom or 0),
					left = insets.left + (overscan.left or 0),
					right = insets.right + (overscan.right or 0),
				}
			end
		end
		-- the legal domain lives with the policy (`themes/snapshot.textOffset`), so
		-- the public `Facet.text.facts` clamps the offset exactly as this seam does
		local prefOffset = themeSnapshot.textOffset(env:get("preferredTextOffset"):get())
		-- the adapter owns the scrollbar thickness (it is engine-specific); the
		-- solver reserves it off a scrolling region's cross axis so content is
		-- never laid out underneath the bar
		local barReserve = if type((adapter :: any).scrollBarThickness) == "number"
			then (adapter :: any).scrollBarThickness
			else 0
		-- EXACT TEXT MEASUREMENT (text-measurement milestone): bracket the solve
		-- so the words it could not size exactly come back attached to THIS
		-- surface's solve. Per-solve rather than a global queue on purpose — a
		-- shared queue lets one surface drain another's requests, and the
		-- surface that never sees its own measurement never re-solves.
		text_metrics.beginCollect()
		-- ONE snapshot per solve: the layout-node builder, the solver's measure
		-- path and the paint seam must all resolve the same theme, or a swap
		-- landing mid-solve would measure one theme and paint another
		local metrics = currentMetrics()
		--[[ ...AND `bandSafeContent` FLOORS ITS OTHER THREE EDGES AT THE THEME'S
			GUTTER. The platform's safe inset answers "what must be
			cleared"; it does not answer "may content touch the glass", and on a device
			whose engine pre-excludes the notch from the camera the lateral inset is
			ZERO — so every edge-anchored control laid out flush against the camera's
			own boundary. The HUD demo spent this per-edge max by hand since
			2026-08-15; the policy owns it now and the hand-roll is deleted.
			`space.gutter` and not `space.s`, because the screen edge is the one step
			in the scale with a physical floor under it (`max(8, space.s)`).

			IT IS HERE AND NOT IN THE SOLVER, which is the audit's own split: this is
			the policy resolver, and `solver.solve` stays a pure function of the insets
			it is handed.

			WHY ONLY THIS POLICY, when the audit says "floor every policy": MEASURED.
			Built the wider way, `tests/overflow_sweep.spec.luau` files 255 findings
			across 51 of its 95 scenarios — content that no longer fits its own box, 249
			of them at the two narrowest swept viewports. THE LINE THAT LANDS IT IS THIS
			BRANCH'S CONDITION. ]]
		if rootPolicy == "bandSafeContent" then
			local space = (metrics :: any).space
			local gutter = if type(space) == "table" and type(space.gutter) == "number"
				then math.max(0, space.gutter)
				else 0
			if gutter > 0 then
				insets = {
					-- the TOP is the platform's, untouched: a theme gutter there would
					-- stop the topbar row sitting level with the engine's own buttons,
					-- which is the one thing the chrome-band rule exists to prevent
					top = insets.top,
					bottom = math.max(insets.bottom, gutter),
					left = math.max(insets.left, gutter),
					right = math.max(insets.right, gutter),
				}
			end
		end
		--[[ THE EDGE-FLOOR KNOB, APPLIED (director ruling). Same
			three edges as `bandSafeContent`'s own gutter floor above and the
			same reason (the top is the platform's row, never a
			theme value) — this is a SEPARATE, opt-in floor a consumer names
			explicitly, so it composes with whatever the policy already
			reserved (MAX, never a second addition) rather than replacing it.
			`attach()` already refused `edgeToEdge + edgeFloor` together, so
			this is reachable only on a policy that has content insets to
			begin with. `metrics` is the display-scaled snapshot `resolveNumber`
			resolves a metric NAME against — the ten-foot ladder a package's
			`space.*` already rides — so `edgeFloor = "l"` grows at the same
			1.5x every neighbor (`space.gutter`, `anchor.gap`, `cellPadding`)
			grows at; a literal number stays the literal pixel count at every
			distance, exactly like those neighbors' own number arm. ]]
		if rootPolicy ~= "edgeToEdge" and optEdgeFloor ~= nil then
			local floorPx = themeSnapshot.resolveNumber(metrics, optEdgeFloor)
			if type(floorPx) == "number" and floorPx == floorPx and floorPx > 0 then
				insets = {
					top = insets.top,
					bottom = math.max(insets.bottom, floorPx),
					left = math.max(insets.left, floorPx),
					right = math.max(insets.right, floorPx),
				}
			end
		end
		local layoutRoot = toLayoutNode(root.node, metrics, measureScale, prefOffset)
		local solveOpts = {
			safeInsets = insets,
			rootPolicy = rootPolicy,
			scrollBarReserve = barReserve,
			metrics = metrics,
			-- §9: the platform's free strip in WINDOW space, and the whole row above
			-- the content rect. `nil` on every other policy, so the solver's own band
			-- branch costs an undeclared surface one nil check.
			band = band,
			bandFullTop = bandFullTop,
		}
		-- kept so the Stage-1 boundary analysis can re-solve the SAME tree with the
		-- SAME offers; an analysis run against a differently-built tree would be
		-- measuring something other than what shipped
		lastSolveInputs = { layoutRoot = layoutRoot, viewport = { w = vp.w, h = vp.h }, opts = solveOpts }
		if incrementalEnabled and lastResult ~= nil and dirtyContains ~= nil then
			solveOpts.reuse = { previous = lastResult, dirtyContains = dirtyContains }
			-- this solve covered `dirtyContains` and skipped the rest, so it cannot
			-- answer for the whole queue (see `fullSolveSeq`)
			solvedEverything = false
		end
		local result = solver.solve(layoutRoot, { w = vp.w, h = vp.h }, solveOpts)
		if result.work ~= nil and (result.work.skipped or 0) > 0 then
			stats.partialSolves += 1
			stats.lastSkipped = result.work.skipped
		end
		lastResult = result
		-- the last solve's work, surfaced through `controller.stats()`. This is what
		-- makes "one changed value re-laid-out the whole tree" a testable claim rather
		-- than something you have to instrument the solver to see.
		if result.work ~= nil then
			stats.lastArranged = result.work.arranged
			stats.lastMeasured = result.work.measured
		end
		-- MICROPROFILER PHASE `Facet/commit` (roadmap Step 9): the ADAPTER COMMIT —
		-- everything between a finished solve and a frame the player can see. Visibility,
		-- hit rects, rects, scroll regions, z-order, transforms and the text-measurement
		-- follow-up all live here. It is deliberately ONE scope for the whole pass rather
		-- than one per write class: the question a capture asks is "is the framework's
		-- output cheap relative to its solve", and eight sibling bars answer it worse than
		-- one. `measure`/`arrange` are nested INSIDE the enclosing solve and remain
		-- separately named, so inclusive-minus-exclusive still separates the two halves.
		profile.span("commit", function()
			local textRequests = text_metrics.endCollect()
			lastDiagnostics = result.diagnostics
			-- `result.rects` and `prefOffset` are for `textSize = "fit"` alone: that node
			-- has no authored size for this walk to scale, so paint reads the size the
			-- SOLVER chose against the box (see `commit_walks.textScale`)
			commitWalks.textScale(root.node, paintScale, metrics, result.rects, prefOffset)
			commitWalks.padding(root.node, metrics)
			commitWalks.textVerdicts(root.node, result.rects)
			-- hidden subtrees (A-AL1): a ViewThatFits candidate that lost keeps its
			-- mount but must not be reachable. The solver marks the losing candidate
			-- roots; the presenter reads this set to exclude them from focus order,
			-- so navigation can never land on an invisible control.
			local nextHidden: { [string]: boolean } = {}
			local nextCompositions: { [string]: any } = {}
			local nextTextFacts: { [string]: any } = {}
			-- THE AUTHORED HIDES JOIN THE SOLVER'S OWN VERDICT (round 3, item D). One
			-- set from here down, so `hidden = true` inherits the paint walk, the
			-- hit-rect retraction, the `hiddenRoots` the focus map filters on, and the
			-- structure-epoch bump below — none of which a parallel paint-only channel
			-- would have reached.
			for path in authoredHidden do
				nextHidden[path] = true
			end
			for path, entry in result.rects do
				if entry.hidden == true then
					nextHidden[path] = true
				end
				if entry.composition ~= nil then
					nextCompositions[path] = entry.composition
				end
				if entry.textFacts ~= nil then
					nextTextFacts[path] = entry.textFacts
				end
			end
			lastCompositions = nextCompositions
			lastTextFacts = nextTextFacts
			-- ...AND A HIDE IS A FOCUS-MAP CHANGE, with no structural sync behind it.
			-- Compared rather than assumed-changed: the set is 0-2 entries on a normal
			-- surface, so this is cheaper than the derivation it guards, and bumping
			-- unconditionally here would defeat the epoch entirely (this runs on every
			-- solve).
			local hiddenChanged = false
			for path in nextHidden do
				if hiddenRoots[path] == nil then
					hiddenChanged = true
					break
				end
			end
			if not hiddenChanged then
				for path in hiddenRoots do
					if nextHidden[path] == nil then
						hiddenChanged = true
						break
					end
				end
			end
			if hiddenChanged then
				structureEpoch += 1
			end
			hiddenRoots = nextHidden
			-- a hidden candidate must not PAINT. A zero rect was not enough: text still
			-- wrapped and drew inside a 0px box (found live in the adaptive_controls
			-- capture, where the losing action column's labels ran down the screen edge).
			commitWalks.visible(root.node, result.rects, nextHidden)
			-- B-BTN3: enforce the effective target floor in HIT geometry. The visual
			-- rect is deliberately untouched — flooring the painted size would silently
			-- rewrite shipped design (a 22px icon button would double) — so the
			-- framework separates what the player SEES from what the player can HIT.
			-- Feature-detected: an adapter without the seam keeps today's behaviour.
			commitWalks.hitRects(root.node, result.rects, nextHidden, metrics)
			-- ...and the paint order those expanders need in order to be REACHABLE
			-- (the overhang lift, `src/render/hit_lift.luau`). It runs HERE
			-- because the lift is geometry: structural sync assigns z before the
			-- solve that produces the rects, so the z walk re-runs from here, and
			-- only when the lift itself changed. It stays behind rather than
			-- travelling with the floor walk because a lift is paint ORDER, and
			-- `syncZOrder` is declared far below both.
			if
				adapter.setHitRect ~= nil
				and hitLift.refresh(result.rects, lastHitRects, inputSinks, parentNodeOf, solverHidden)
			then
				syncZOrder()
			end
			-- `withAnimation`, and ONLY on the armed commit it forces for itself
			-- (design §"Blocker 1"). It must sit HERE: root classification is
			-- top-down, so it needs a tree walk rather than the unordered rect hash
			-- below, and it has to read `lastRects` before that loop overwrites it.
			if channel.armed() then
				channel.installAnimationRecords(result.rects)
			end
			-- NATIVE SCROLL REGIONS, from the native-substrate round: the canvas the
			-- adapter is told about, plus the per-host autoscroll and indicator
			-- declarations that ride the same walk. `render/commit_walks` carries the
			-- rule and the two live findings behind it (the theme's own chrome
			-- reservation, the shadow bleed).
			--
			-- RUNS BEFORE `rectPass.apply` BELOW — LOAD-BEARING (task SCROLL2 fix
			-- round 1, RED-TEAM finding 1). `applyBarOverlayWiden`
			-- (`screen_scroll_indicators.setScrollRegion`) writes
			-- `handle.barOverlayWidenW/H` from THIS solve's own overflow facts;
			-- `applyRect` (`screen_presentation.luau`, driven by `rectPass.apply`)
			-- reads that same field composing the Size it sends. Swapped from the
			-- opposite order, which painted a freshly-overflowing "auto" host with
			-- the PREVIOUS solve's widen (nil on a fresh mount, since the field is a
			-- bare non-reactive write with no settle-phase feedback) — reproducing
			-- the 2026-08-09 clip on any host nothing else ever re-solves. Safe to
			-- run first: this walk reads only `result.rects`/`metrics`/the handle
			-- map, all already populated above, and nothing `rectPass.apply` sets up.
			commitWalks.scrollRegions(root.node, result.rects, metrics)

			-- ANCESTORS FIRST, AND IT IS LOAD-BEARING, NOT TIDINESS: under a nested
			-- tree a descendant's engine Position is relative to its HOST, so a
			-- descendant applied before its host re-bases against an origin that has
			-- not moved yet. `render/rect_pass` carries the rule, the live
			-- measurement behind it, and the deferred re-base that goes with it.
			-- (Unaffected by running after `scrollRegions` above: neither reads
			-- anything the other writes to the engine.)
			rectPass.apply(root.node, result.rects)

			-- ...and only now, with this frame fully painted from the conservative
			-- estimate, ask the engine for the words it could not size. Ordering is
			-- the safety property: the first frame is always the over-reserving
			-- fallback, never a guess waiting on an async answer, and the exact
			-- geometry lands one re-solve later. Batched per SOLVE over the whole
			-- tree's vocabulary — never per node.
			if adapter.measureTextWidths ~= nil and #textRequests > 0 and not disposed then
				local batch: { any } = {}
				for _, request in textRequests do
					local key = `{request.font}\0{request.size}\0{request.word}`
					if not textInFlight[key] then
						textInFlight[key] = true
						table.insert(batch, request)
					end
				end
				if #batch > 0 then
					stats.textMeasureBatches += 1
					-- `final` (default true) is the adapter saying "this batch is
					-- closed". An adapter that answers early with widths it does not
					-- yet trust — the Roblox one does, while the engine's boot window
					-- is still open — passes false, and the words stay in flight so a
					-- surface waiting for exact text keeps waiting.
					local cancelMeasure = adapter.measureTextWidths(batch, function(results: { any }, final: boolean?)
						local learned = false
						for _, entry in results do
							if type(entry) ~= "table" then
								continue
							end
							if final ~= false then
								textInFlight[`{entry.font}\0{entry.size}\0{entry.word}`] = nil
							end
							if type(entry.width) == "number" then
								-- an adapter may answer the SAME batch twice (the
								-- Roblox one re-reads once the session has settled and
								-- corrects the boot answer), so a re-solve is owed only
								-- when a width actually moved
								local previous = text_metrics.measuredWidth(entry.font, entry.size, entry.word)
								if text_metrics.setMeasured(entry.font, entry.size, entry.word, entry.width) then
									if previous ~= entry.width then
										learned = true
									end
								else
									-- a measurement this seam refuses is a measurement
									-- that could clip: keep the estimate, and do not
									-- ask for it again on every solve
									text_metrics.markUnmeasurable(entry.font, entry.size, entry.word)
								end
							else
								text_metrics.markUnmeasurable(entry.font, entry.size, entry.word)
							end
						end
						--[[ exactly one re-solve per answered round, and only when the
							round actually taught the measurer something.

							PUBLISH THE GENERATION FIRST (director 2026-08-04, the
							finish-screen size pop). The re-solve fixes the SOLVER's boxes,
							but a consumer memo that called `Facet.text.fit/.size/.measure`
							has no dependency on the exact-width store — it is plain data —
							so it evaluated once against the ESTIMATOR and nothing here
							invalidated it. Bumping `textMeasureEpoch` is that dependency:
							any memo that reads it re-derives once, on this frame, together
							with the solve rather than at some arbitrary later tick. Written
							before `solveAndApply` so the re-solve already sees the
							re-derived values instead of needing a third pass. ]]
						if learned and not disposed then
							-- `env:get` answers the FACT's signal, so the current value is one
							-- more `:get()` in (same shape as every other read in this file)
							env:set("textMeasureEpoch", ((env:get("textMeasureEpoch"):get() :: number?) or 0) + 1)
							solveAndApply()
						end
					end)
					-- A BOOT-WINDOW BATCH ANSWERS TWICE, up to ~12 s apart.
					-- `disposed` already gates the re-solve; this stops the delivery
					-- itself, so a torn-down surface is not called back at all.
					if type(cancelMeasure) == "function" then
						table.insert(textMeasureCancels, cancelMeasure)
					end
				end
			end
			-- A REFLOW MOVES THE DROP TARGETS. Every rect the live
			-- session hit-tests against was just rewritten, so the hover is
			-- re-evaluated at the last pointer position on THIS frame — a verdict
			-- that trailed the layout by a frame is a verdict about geometry the
			-- player is no longer looking at.
			if dragRegistryInstance ~= nil and dragRegistryInstance.isActive() then
				dragRegistryInstance.refreshTargets()
			end
		end)
		--[[ THE SOLVE IS OVER: tell whoever measures this surface (L-31).
			The presenter's `feedGeometry` used to run only from `refresh()` on the
			host's frame connection, which put a whole FRAME between a solve and the
			consumer that measures it — so a consumer publishing a number derived
			from its own geometry (a dock reserving space, a keyboard inset, a
			sticky header) could never join the flush that caused it, and opened a
			second one. Fed from here, that write lands inside the settle phase that
			produced the rects and the cycle converges before anything is painted.

			RE-ENTRANCY IS THE ONLY HAZARD, and it is real: the text-measurement
			round above calls `solveAndApply()` again from inside this very
			function. Notifying from the inner call would feed rects the outer call
			is about to rewrite, so the guard reports once, from the outermost
			solve, with the final geometry. ]]
		--[[ THE LAYOUT FRAME IS CLOSED, so record what it answered for. `math.max`
			because the text-measurement round above re-enters `solveAndApply`, and
			an inner solve that ran LATER read a higher sequence than this one —
			overwriting it with the outer solve's older mark would re-open dirt the
			inner solve has already answered. ]]
		if solvedEverything then
			fullSolveSeq = math.max(fullSolveSeq, seqAtSolveStart)
		end
		if not notifyingSolved then
			notifyingSolved = true
			-- the tree's dirty sequence BEFORE anyone is told: everything past this
			-- mark is, by definition, something a listener published (see the
			-- solve-feedback block above)
			feedbackMark = root.dirtySeq()
			-- deliberately NOT pcall'd: `feedGeometry` runs unguarded from
			-- `refreshBody` today and a throwing consumer must keep behaving the
			-- same way. When this fires from the settle phase the core quarantines
			-- it into `lastError` like every other callback; when it fires from
			-- `controller.refresh()` it propagates, exactly as before.
			local ok, err = pcall(function()
				for _, fn in solvedListeners do
					fn()
				end
			end)
			notifyingSolved = false
			if not ok then
				error(err, 0)
			end
			if root.dirtySeq() > feedbackMark then
				-- the write flushed synchronously (no flush was open): the dirt is
				-- already on the tree, so close the cycle here
				resolveForFeedback()
			elseif solvingFromSettle then
				-- a flush IS open, so the write is still in `writeSet`. The core ends
				-- this pass, drains it and restarts from the first settle callback —
				-- which is where the mark gets read again.
				feedbackArmed = true
			end
		end
	end

	--[[ The re-solve a published prop earns, bounded. `dirtyContains` is cleared
		first and deliberately: the incremental set was closed over the dirt the
		CURRENT refresh took, and the node a listener just published into is not in
		it — reusing it would skip the very subtree this exists to fix. ]]
	resolveForFeedback = function()
		feedbackArmed = false
		if feedbackDepth >= SOLVE_FEEDBACK_ROUND_CAP then
			feedbackDepth = 0
			error(
				`Facet renderer: a solve's geometry feedback did not converge in {SOLVE_FEEDBACK_ROUND_CAP} rounds `
					.. `(a consumer publishing a layout prop derived from the rect that prop moves?); solve-feedback round cap`,
				0
			)
		end
		feedbackDepth += 1
		stats.feedbackSolves += 1
		dirtyContains = nil
		local ok, err = pcall(solveAndApply)
		feedbackDepth -= 1
		if not ok then
			error(err, 0)
		end
	end

	-- flat sibling rendering paints in z-order; instance creation order is NOT
	-- deterministic across a structural sync, so z is assigned explicitly from
	-- the tree walk (live-found defect 2026-07-19). `lastZ` itself is
	-- declared up with `rectOf`, because the drag registry reads it as the
	-- paint-order tie-break for overlapping drop targets.
	-- AUTHORED PAINT ORDER, WITHIN THE PARENT'S STACKING SCOPE.
	-- Siblings are visited in `(zIndex or 0, declaration order)`
	-- order, so a lifted node — a drag ghost, a toast — paints above the siblings it
	-- was declared before, and its whole SUBTREE travels with it because the walk
	-- is depth-first over one counter. Nothing crosses a scope: a child's counter is
	-- always higher than its parent's, whatever its zIndex, which is why lifting
	-- across surfaces stays structural (the presenter's display order).
	--
	-- The declaration index is part of the key rather than trusted to `table.sort`:
	-- Luau's sort is NOT stable, so ties between two zero-index siblings would
	-- otherwise be free to swap between solves — and z-order churn is exactly the
	-- non-determinism the explicit z walk exists to remove.
	-- ...and the SECOND KEY, only when something asked for it: a branch whose hit
	-- expander overhangs into a later sibling is walked AFTER that sibling
	-- (`src/render/hit_lift.luau` owns the rule and the ordering).
	local function orderedChildren(node: any): { any }
		local children = node.children
		if children == nil or #children < 2 then
			return children or {}
		end
		local lifted = hitLift.touches(children)
		local anyLift = false
		for _, child in children do
			if child.props ~= nil and type(child.props.zIndex) == "number" and child.props.zIndex ~= 0 then
				anyLift = true
				break
			end
		end
		if not anyLift then
			-- the overwhelmingly common case allocates nothing
			return if lifted then hitLift.order(children) else children
		end
		local indexed: { { node: any, index: number, z: number } } = table.create(#children)
		for index, child in children do
			local z = if child.props ~= nil and type(child.props.zIndex) == "number" then child.props.zIndex else 0
			table.insert(indexed, { node = child, index = index, z = z })
		end
		table.sort(indexed, function(a, b)
			if a.z ~= b.z then
				return a.z < b.z
			end
			return a.index < b.index
		end)
		local out: { any } = table.create(#children)
		for _, entry in indexed do
			table.insert(out, entry.node)
		end
		return if lifted then hitLift.order(out) else out
	end
	function syncZOrder()
		if adapter.setZOrder == nil then
			return
		end
		local z = 0
		local zMetrics = currentMetrics()
		local function walkZ(node: any)
			-- A HOST WITH A HIT EXPANDER OWNS THE COUNTER BELOW IT TOO. The adapter
			-- paints the expander at `hostZ - 1`, and without this reservation that
			-- number belongs to whatever node happened to be walked immediately
			-- before — a TIE, which the engine breaks by insertion order, i.e. by
			-- exactly the non-determinism this explicit walk exists to remove. It is
			-- also what makes the overhang lift land: a host lifted one position past
			-- a leaf sibling would otherwise put its expander level with it, and
			-- level is not above (measured on `keyboard_navigation`, whose rows are
			-- leaves: Row1 at z 37 over Row2 at z 36 left the expander at 36).
			-- THE CLASS, NOT THE CURRENT STATE (NM-H4a, live 2026-08-17): reading
			-- `lastHitRects` made this band a function of HISTORY. See
			-- tests/hit_expander_z_band.spec.
			if effectiveHitFloor(node.class, zMetrics) ~= nil then
				z += 1
			end
			z += 1
			if handles[node.path] ~= nil and lastZ[node.path] ~= z then
				authority.assertWrite("common", "zIndex", "layout")
				adapter.setZOrder(handles[node.path], z)
				lastZ[node.path] = z
			end
			for _, child in orderedChildren(node) do
				walkZ(child)
			end
		end
		walkZ(root.node)
	end

	-- THE TWO DRAINS. Both take the queue by value and clear it BEFORE calling
	-- anything, so a hook that mounts or dismisses something (which is the normal
	-- reason to have one) cannot make its own entry run twice or make the drain
	-- re-enter itself. The callbacks are deliberately unprotected — that is the house
	-- rule every other handler prop follows (`onPointerDown`, `onScrollWheel`), and a
	-- swallowed error in a lifetime hook is a leak nobody ever sees.
	local function drainDeparted()
		if #departedQueue == 0 then
			return
		end
		local batch = departedQueue
		departedQueue = {}
		for _, entry in batch do
			entry.fn(entry.path)
		end
	end

	local function drainAppeared()
		if #appearQueue == 0 then
			return
		end
		local batch = appearQueue
		appearQueue = {}
		for _, entry in batch do
			entry.fn(entry.path)
		end
	end

	local function structuralSync()
		structureEpoch += 1
		local _t0 = os.clock()
		ensureTree(root.node)
		local _t1 = os.clock()
		collectRetiringRoots() -- retire begin/cancel both push structure
		-- mounted identity may have changed under any path (a When branch, a ForEach
		-- row, a re-created ViewThatFits candidate), so the presentation channel's
		-- node memo is dropped wholesale rather than patched per path
		channel.dropNodeCache()
		local alive: { [string]: boolean } = {}
		table.clear(scrollHostOf)
		table.clear(clipHostOf)
		table.clear(pathNodes)
		-- the two the overhang lift rebuilds on the same walk; a path is REUSED
		-- across a remount, so a stale parent link would resolve a constraint to a
		-- branch that no longer exists
		table.clear(parentNodeOf)
		table.clear(inputSinks)
		pathNodeCount = 0
		local _t2 = os.clock()
		livePaths(root.node, alive, nil, nil)
		local _t3 = os.clock()
		for path, handle in handles do
			if not alive[path] then
				-- drag/drop declarations die WITH their node: an
				-- unregistered target that was the live hover fires exactly one
				-- `leave` and clears the verdict on its way out (finding F5), and
				-- paths are reused across a remount, so a stale binding would make
				-- a fresh node inherit a dead declaration.
				for _, suffix in { "\0drop", "\0drag", "\0det" } do
					local unbind = dragUnbind[path .. suffix]
					if unbind ~= nil then
						dragUnbind[path .. suffix] = nil
						unbind()
					end
				end
				-- PARK BEFORE REMOVE. `park` refuses anything carrying path-keyed
				-- adapter state, and a refusal falls through to the ordinary remove —
				-- so this can only ever save a create, never change what is on screen.
				local parked = false
				local key = recycleKeyOf[path]
				recycleKeyOf[path] = nil
				if recycleEnabled and key ~= nil and recyclePooled < RECYCLE_POOL_CAP then
					if not adapter.park(handle) then
						stats.parkRefused += 1
					else
						local bucket = recyclePool[key]
						if bucket == nil then
							bucket = {}
							recyclePool[key] = bucket
						end
						table.insert(bucket, handle)
						recyclePooled += 1
						parked = true
						stats.parked += 1
					end
				end
				if parked then
					-- CARRY THE PROPERTY CACHES WITH THE INSTANCE.
					--
					-- These record what the ENGINE OBJECT currently holds, so they are a
					-- property of the instance and not of the path — carrying them across
					-- a recycle is accurate, not stale. Dropping them (which is right for
					-- a real removal, where the instance is destroyed) meant every
					-- adopted node had all ~8 properties per object rewritten from
					-- scratch, and `mount` is 67% of a fling frame.
					--
					-- `solverHidden` is deliberately NOT carried: it is a verdict about
					-- the NODE, not a value on the instance, and the new identity gets
					-- its own.
					handle.parkedProps = captureParkedProps(path)
				else
					adapter.remove(handle)
				end
				handles[path] = nil
				lastRects[path] = nil
				lastBarInsets[path] = nil
				lastScrollRegions[path] = nil
				scrollAutoscroll[path] = nil
				if autoscrollModels[path] ~= nil then
					autoscrollModels[path]:reset()
					autoscrollModels[path] = nil
				end
				lastZ[path] = nil
				lastTextSize[path] = nil
				lastTextFont[path] = nil
				lastPadding[path] = nil
				-- ...and the wrap verdict, which is a VALUE the departed instance held:
				-- a path re-created with a different string would otherwise be told
				-- nothing and keep the old node's `TextWrapped` (ruling 5)
				lastWrapped[path] = nil
				-- paths are REUSED across a structural remount (a When/ForEach child, a
				-- re-created ViewThatFits candidate), so these caches must be forgotten
				-- too. Leaving them made a fresh instance inherit the old verdict: a node
				-- re-created while still hidden got no setVisible write and painted
				-- (reopening the defect the hidden-candidate fix closed), and a re-created
				-- sub-floor control silently lost its hit expander (verifier finding V10).
				lastVisible[path] = nil
				lastHitRects[path] = nil
				solverHidden[path] = nil
				-- ...and the authored hide, for the same reason: a path re-created with
				-- no `hidden` prop would otherwise inherit the old node's verdict and
				-- never paint
				authoredHidden[path] = nil
				-- THE LIFETIME HOOK, queued rather than called. Called here it would run
				-- inside the sweep's own iteration over `handles` and inside the `mount`
				-- profiler span; both are wrong, and the first is a live-mutation hazard
				-- while the walk is still running.
				local departed = disappearHooks[path]
				if departed ~= nil then
					disappearHooks[path] = nil
					table.insert(departedQueue, { path = path, fn = departed })
				end
				-- ...and the compact-label verdict cache (found LIVE 2026-08-04:
				-- RascalRally's watch-cycle buttons painted "Previous racer" ellipsized
				-- after a pose toggle at EVERY preference). A re-created button is
				-- born with its FULL label; a surviving `true` here said the swap was
				-- already applied, so `commit_walks.textVerdicts` never wrote the glyph again.
				-- One mount looked right — which is why the device pass that shipped
				-- the feature saw chevrons — and every remount after it did not.
				lastCompact[path] = nil
				-- a scroll host that left takes its RS-PATHCLIP subscription with it
				if pathClipObservers[path] ~= nil then
					local detach = pathClipObservers[path]
					pathClipObservers[path] = nil
					detach()
				end
				-- ...and every per-path presentation cache, which the channel forgets
				-- together: the transform (and its live count), the transparency, both
				-- composed memos, the parked paint delta, the authored triple and any
				-- `withAnimation` record. The write is skipped — the handle is already
				-- gone (V10's per-path clear, above).
				channel.forgetPath(path)
				stats.removes += 1
			end
		end
		local _t4 = os.clock()
		syncZOrder()
		local _t5 = os.clock()
		stats.ssPasses += 1
		stats.ssEnsureTree += (_t1 - _t0) * 1000
		stats.ssRetire += (_t2 - _t1) * 1000
		stats.ssLivePaths += (_t3 - _t2) * 1000
		stats.ssSweep += (_t4 - _t3) * 1000
		stats.ssZOrder += (_t5 - _t4) * 1000
		stats.ssTotal += (_t5 - _t0) * 1000
	end

	--[[ ENVIRONMENT GEOMETRY DRIVES RE-ARRANGEMENT — AS ONE FACT, NOT EIGHT.
		These eight keys all mean the same thing to this surface: "the space you
		were solved for is no longer the space you are in." They were once
		observed INDEPENDENTLY, each callback running a full `solveAndApply()`,
		and the multiplication was real work on a real device: L-27 recorded "one
		viewport change costs 5 solves and 2 structural syncs, reproducibly" and
		the 2026-08-13 device capture priced a solve at 8.270 ms of arrange +
		3.057 ms of measure, 58.5% of wall.

		Two facts compound to make five. An adapter learns SEVERAL of these at
		once (`roblox_env.pushViewport()` writes six on one resize), and some are
		DERIVED from others — `typographyScale` is a memo over `displaySize` and
		`preferredTextOffset`, so even a single loose write fires twice.

		One memo over all eight fixes both. The core is glitch-free, so it
		recomputes at most ONCE per flush no matter how many of its dependencies
		moved, and the fresh table is deliberate: identity-inequality means "some
		geometry fact changed", which is exactly the question this observer asks.
		Paired with the adapter batching a platform event into one transaction
		(`env:batch`), five solves become one — measured, not assumed, in
		tests/geometry_solve_coalescing.spec.

		THE MEMO CARRIES VALUES, NOT A FRESH TABLE (RED-TEAM 2026-08-13). The first
		cut returned `{}` and relied on identity-inequality, which made "recomputed"
		mean "changed" and discarded both guarantees the core states in its own
		header — set-and-revert transactions and unchanged recomputes are fire-free.
		Measured then: a viewport set-and-reverted inside one batch cost 1 solve
		instead of 0, and a `preferredTextSize` change that left `typographyScale`
		on the same clamped value cost 1 instead of 0. Wasted solves in exactly the
		dimension this entry exists to remove. So it returns the pulled values and
		compares them element-wise; eight comparisons per flush buys both properties
		back, and it stays honest if a DERIVED key is ever added to the list.

		ADDING A KEY: put it in the list and nowhere else. REMOVING one silently
		makes the surface deaf to it, which is why that spec drives every key
		individually and asserts each still costs exactly one solve. ]]
	--[[ BY CONTENT, NOT BY TABLE IDENTITY. Every one of these facts that is not a
		scalar is a FLAT RECORD — a rect (`x,y,w,h`) or a four-edge inset — and the
		adapter builds a BRAND NEW one on every `pushViewport()`. A `TopbarInset`
		change alone re-publishes a viewportRect whose numbers are identical, and
		under identity comparison that is a full re-solve of the surface for a
		viewport that did not move. Comparing the numbers costs at most eight field
		reads and removes a whole class of solve nobody asked for.

		One level deep is deliberate and sufficient: no environment geometry fact
		nests, and a deep walk would be a general-purpose comparison bolted to a
		specific eight. A nested fact is REFUSED rather than half-compared — any
		table-valued FIELD returns false, i.e. re-solves.

		That refusal is load-bearing and the reason is worth stating, because the
		comment here used to promise conservatism it did not deliver (architecture
		gate F3, 2026-08-14). Comparing a nested field by identity is only safe
		when the inner table is rebuilt with the outer one. A future fact shaped
		`{ rect = <cached>, insets = <fresh> }` — outer rebuilt, inner reused —
		would compare the inner references as EQUAL and report "unchanged", which
		is a MISSED re-solve, not an extra one: the surface goes silently deaf to
		one platform fact. Refusing the shape costs nothing today (no fact has a
		table-valued field) and makes the conservative claim literally true. ]]
	-- ...and the comparison itself is `src/rect.luau`'s, from the reuse audit: the
	-- same body
	-- lived here and in `src/controls/selection_indicator.luau`, across a layer
	-- boundary, with the indicator's copy carrying a comment naming this one.
	local sameGeometryValue = rectLib.sameFlatValue
	--[[ ...AND THE ONE NESTED FACT, compared exactly rather than refused.
		`platformChrome` is `{ band, rects, insets, bandInsets }` — three flat
		records and a LIST of them — and it is a memo, so it hands back a brand-new
		frozen table on every recompute; under identity OR `sameFlatValue` a
		band-riding surface would re-solve on every flush. This walks exactly the four
		fields the fact has, and an unknown fifth would compare as "changed", which is
		the safe direction. ]]
	local function sameChrome(a: any, b: any): boolean
		if a == nil or b == nil then
			return a == b
		end
		if type(a) ~= "table" or type(b) ~= "table" then
			return false
		end
		if not sameGeometryValue(a.band, b.band) then
			return false
		end
		if not sameGeometryValue(a.insets, b.insets) or not sameGeometryValue(a.bandInsets, b.bandInsets) then
			return false
		end
		local ar, br = a.rects, b.rects
		if type(ar) ~= "table" or type(br) ~= "table" or #ar ~= #br then
			return false
		end
		for i = 1, #ar do
			if not sameGeometryValue(ar[i], br[i]) then
				return false
			end
		end
		return true
	end

	local GEOMETRY_KEYS = {
		"viewportRect",
		"coreSafeInsets",
		"deviceSafeInsets",
		"overscanInsets",
		"displaySize",
		-- geometry-affecting (matrix D.1): a preferredTextSize or displaySize
		-- change re-scales text at measure AND paint
		"typographyScale",
		"preferredTextOffset",
		-- a theme commit is geometry: new type sizes, spacing,
		-- control metrics and content insets all reach the solver, so the
		-- surface RE-SOLVES — it is never rebuilt, so mount identity, focus,
		-- selection, scroll and text entry survive a swap untouched
		"themeMetrics",
	}
	--[[ AN edgeToEdge SURFACE DOES NOT CONSUME A SAFE-AREA INSET (L-31).
		`solveAndApply` opens with `if rootPolicy == "edgeToEdge" then insets =
		{0,0,0,0}` — it reads `coreSafeInsets` and throws the value away, and never
		reads `deviceSafeInsets` at all. Leaving both in the dependency list made
		every scrim, backdrop and dock re-solve for an inset it is defined to
		ignore, and the shipped case is the one that hurts: a dock that PUBLISHES
		its measured height into `coreSafeInsets` re-solved for its own
		publication, every time, forever. Measured on the general two-surface
		shape: 4 arranges per geometry change, 3 with this narrowing.

		The two remaining policies both consume both keys (`coreSafeContent` uses
		coreSafeInsets; `deviceSafeContent` takes the per-edge max of both), so
		this is the only policy that can be narrowed and it is narrowed on the
		exact branch that proves it. `rootPolicy` is fixed for the controller's
		life (read once at attach), so the key list is safe to fix with it. ]]
	if rootPolicy == "edgeToEdge" then
		local narrowed = {}
		for _, key in GEOMETRY_KEYS do
			if key ~= "coreSafeInsets" and key ~= "deviceSafeInsets" then
				table.insert(narrowed, key)
			end
		end
		GEOMETRY_KEYS = narrowed
	end
	--[[ ...AND `bandSafeContent` READS ONE FACT WHERE THE OTHERS READ THREE. Its content rect comes from `platformChrome`, which is DERIVED
		from the core and device insets, the two topbar facts, the declared app chrome
		and the overscan — so subscribing to the raw three would be both incomplete (a
		`TopbarInset` change would move the band and re-solve nothing) and redundant.
		Same narrowing `edgeToEdge` gets above, in the other direction.

		It is the one NESTED fact in this list and it has a comparator of its own
		(`sameChrome`); the refusal the block above documents stands for facts with
		none. ]]
	if rootPolicy == "bandSafeContent" then
		local swapped = { "platformChrome" }
		for _, key in GEOMETRY_KEYS do
			if key ~= "coreSafeInsets" and key ~= "deviceSafeInsets" and key ~= "overscanInsets" then
				table.insert(swapped, key)
			end
		end
		GEOMETRY_KEYS = swapped
	end
	-- scope-owned like every other memo: an unowned one is a live registry node
	-- after dispose, which the registry-neutrality suites catch as a leak
	local geometryFacts = attachScope:own(core:memo(function(use)
		local values = table.create(#GEOMETRY_KEYS)
		for i, key in GEOMETRY_KEYS do
			values[i] = use(env:get(key))
		end
		return values
	end, function(a: any, b: any): boolean
		if a == nil or b == nil then
			return a == b
		end
		for i = 1, #GEOMETRY_KEYS do
			local same = if GEOMETRY_KEYS[i] == "platformChrome"
				then sameChrome(a[i], b[i])
				else sameGeometryValue(a[i], b[i])
			if not same then
				return false
			end
		end
		return true
	end))
	--[[ THE RE-SOLVE IS SETTLE WORK, NOT OBSERVER WORK (L-31, 2026-08-14).
		This observer used to call `solveAndApply()` inline, which meant a surface
		committed to a layout in the MIDDLE of propagation — before the flush had
		finished deciding what the environment was. Any write made later in the
		same flush (the shipped case: a sibling surface publishing its measured
		height back into `coreSafeInsets`) then invalidated that solve, and the
		surface solved a second time. Measured headless on the general
		two-surface shape (tools/lune/_probe_settle): 4 solves and 2 reactive
		flushes per geometry change against 2 and 1 with no round trip.

		Deferring to `core:settle` costs nothing anyone can observe — the settle
		phase runs INSIDE the flush, so a top-level `env:set` still returns with
		the surface solved — and buys the whole cycle one flush instead of two.
		The flag is the idempotence the settle contract requires: the callback
		runs once per settle pass and must be a boolean read when there is
		nothing to do. ]]
	local geometryPending = false
	attachScope:own(core:observe(geometryFacts, function()
		geometryPending = true
	end))
	attachScope:own(core:settle(function()
		--[[ FIRST, because a pass restarts from the FIRST callback: when the branch
			below solved and a consumer published a PROP, this is the pass the core
			restarted for, and this is the first moment that dirt exists on the tree
			(see THE SOLVE'S OWN FEEDBACK). The arm is one-shot — it is consumed
			whether or not there turned out to be anything to drain, so a solve
			nobody fed back from cannot leave this callback watching later flushes —
			which was true of the ARM and false of its EFFECT until 2026-08-15; see
			the disarm callback registered directly below. ]]
		if feedbackArmed then
			feedbackArmed = false
			if initialized and root.dirtySeq() > feedbackMark then
				resolveForFeedback()
			end
		end
		if not geometryPending then
			return
		end
		-- cleared even when the surface is not initialized yet, so a geometry
		-- change made before the first render cannot solve on some later flush —
		-- the inline observer dropped it, and this must drop it identically
		geometryPending = false
		if initialized then
			-- ...and the solve knows it is running inside an open flush, which is
			-- what decides where its own feedback can be observed
			solvingFromSettle = true
			local ok, err = pcall(solveAndApply)
			solvingFromSettle = false
			if not ok then
				error(err, 0)
			end
		end
	end))
	--[[ THE ARM DOES NOT OUTLIVE ITS FLUSH (owed row O-20, measured 2026-08-15).

		THE DEFECT. `feedbackArmed` is set by ANY settle-phase solve that ends with
		a flush still open, including one whose `onSolved` listeners published
		nothing at all — the write, when there is one, is still in the core's
		`writeSet` and cannot be seen from inside the callback that made it, so the
		arm cannot be conditioned on it at the point it is set. When nothing was
		published the core has nothing to drain, does not restart the settle pass,
		and the arm SURVIVES INTO THE NEXT FLUSH — where it fires against a
		`feedbackMark` read during the previous one and buys a full re-solve of a
		tree nobody fed anything back to.

		WHY A SECOND CALLBACK IS THE WHOLE FIX. A genuinely earned arm is always
		consumed inside its own flush: a published write leaves the core's write set
		non-empty, so the core ends the pass and restarts from the FIRST settle
		callback, which is the one above. An arm still standing when the pass runs
		to completion is therefore, by construction, one that was never earned.
		Registered AFTER the callback above so it runs after it within a pass, and
		never reached in a pass that breaks early to drain a real write.

		WHAT IT COST WHILE IT LEAKED, both halves measured on the same fixtures:
		every geometry change after the first opened with a spurious full solve
		(Rascal Rally's role-pick modal, 3 solves per rotation against 1 today), and
		the first bound-value change after ANY geometry change was silently promoted
		from an incremental solve to a full one — `tests/perf_principles.spec` could
		not see the second, because `stats().lastArranged` reports the LAST solve of
		a frame rather than every solve in it. ]]
	attachScope:own(core:settle(function()
		feedbackArmed = false
	end))

	local controller = {}

	function controller.refresh()
		local dirty = root.takeDirty()
		local needsSolve = false
		local needsStructure = false
		--[[ THE STALE-LAYOUT-DIRT TEST (owed row O-20, measured 2026-08-15).
			A settle-phase solve does NOT consume the dirty queue — deliberately, so
			the structural sync, the paint commit and the appear/disappear ordering
			below stay byte-identical. The cost was that `refresh` read `measure`/
			`arrange` off the queue and solved AGAIN for dirt that solve had already
			answered: on Rascal Rally's role-pick modal the two `width` writes its CTA
			sub-labels publish landed BEFORE the settle solve, that solve was full, and
			nothing dirtied the tree afterwards — yet the frame paid a second full
			solve for them every rotation.

			`root.dirtySeq()` is monotonic and survives `takeDirty`, so "has anything
			dirtied this tree since the last full solve started" is one comparison.
			Deliberately ALL-OR-NOTHING rather than per-entry: one new dirty makes the
			whole queue live again, which is the conservative direction and needs no
			sequence number on the entries. It gates ONLY the layout classes —
			`structure` still forces a solve, because a structural sync has not run
			yet and last solve's rects were never materialised. ]]
		local layoutDirtIsStale = fullSolveSeq >= 0 and root.dirtySeq() <= fullSolveSeq
		-- paths whose authored `hidden` moved this frame. Collected rather than
		-- resolved inline because the LIVE value has to be read off the tree, and the
		-- tree read is worth doing once per path even when a signal fired twice.
		local hiddenTouched: { string }? = nil
		-- ...and the same collection for the authored presentation quad (`offset` added by amendment, gap 16 framework-gaps-phase2). One list,
		-- not four: they share one stored record and one re-read.
		local presentationTouched: { string }? = nil
		for _, entry in dirty do
			if entry.prop == "hidden" and entry.path ~= nil then
				hiddenTouched = hiddenTouched or {}
				table.insert(hiddenTouched :: { string }, entry.path)
			end
			if
				entry.path ~= nil
				and (
					entry.prop == "opacity"
					or entry.prop == "scale"
					or entry.prop == "rotation"
					or entry.prop == "offset"
				)
			then
				presentationTouched = presentationTouched or {}
				table.insert(presentationTouched :: { string }, entry.path)
			end
			if entry.class == "structure" then
				needsStructure = true
				needsSolve = true
			elseif entry.class == "measure" or entry.class == "arrange" then
				-- see THE STALE-LAYOUT-DIRT TEST above
				needsSolve = needsSolve or not layoutDirtIsStale
			elseif entry.class == "navigation" or entry.class == "semantics" then
				-- ...AND THE FOCUS MAP CAN CHANGE WITHOUT THE TREE CHANGING. Read off
				-- the SCHEMA rather than off a hand-kept prop list: `focusable` declares
				-- `dirty = { "navigation" }` and `enabled` declares `semantics`, and both
				-- decide whether a node is in the order at all. Caught by the suite —
				-- "re-enabling restores focus reachability with no remount" and
				-- "navigation skips a disabled Slider's track" both went red when the
				-- epoch only counted structure and hidden roots.
				--
				-- `semantics` also carries `selected`, which the map does not read, so
				-- this over-invalidates on a selection change. That is a click, not a
				-- frame, and the alternative is a list of prop names that a future
				-- navigation prop would silently fall off.
				structureEpoch += 1
			end
			-- paint/semantics: prop-level writes below
		end
		if needsStructure then
			-- MICROPROFILER PHASE `Facet/mount` (roadmap Step 9): creating,
			-- reconciling and retiring Instances. Named apart from `commit` because
			-- Instance churn and property writes have completely different fixes —
			-- one is a keying/virtualization problem, the other is a diff problem.
			profile.span("mount", structuralSync)
		end
		-- OUTSIDE the mount span, and before the solve: by here the departed nodes'
		-- handles are gone, which is the guarantee `onDisappear` publishes.
		drainDeparted()
		-- ...and the authored hides, re-read from the live tree, so the merge inside
		-- the solve below sees this frame's value
		if hiddenTouched ~= nil then
			for _, path in hiddenTouched :: { string } do
				local node = findNode(path)
				authoredHidden[path] = if node ~= nil
						and node.props ~= nil
						and node.props.hidden == true
					then true
					else nil
			end
		end
		-- THE AUTHORED TRIPLE, re-read from the live tree. Here — after the
		-- structural sync, before the solve — because the read must see this frame's
		-- value, and because on an ARMED commit the OLD value has to be captured
		-- before it is overwritten: that difference is what `withAnimation` flies.
		if presentationTouched ~= nil then
			channel.reactAuthored(presentationTouched :: { string })
		end
		-- prop writes for changed nodes (paint/semantics): write ONLY the
		-- changed prop, once, even when it dirtied several classes
		-- ...AND ON DIRT THIS PASS WILL ACT ON, not merely dirt: the loop below writes
		-- paint/semantics props and nothing else. A layout-only frame walked it and
		-- committed nothing, 2.07x per frame in every device capture
		-- (tests/nested_tree_pins.spec, "a layout-only frame does not open a commit
		-- scope that commits nothing").
		local hasPaintDirt = false
		for _, entry in dirty do
			if (entry.class == "paint" or entry.class == "semantics") and entry.prop ~= nil then
				hasPaintDirt = true
				break
			end
		end
		if hasPaintDirt then
			-- MICROPROFILER PHASE `Facet/commit`: adapter property writes. Guarded so
			-- an idle frame pays a comparison rather than a scope.
			profile.span("commit", function()
				local seen: { [string]: boolean } = {}
				for _, entry in dirty do
					local key = entry.path .. "\30" .. tostring(entry.prop)
					if
						(entry.class == "paint" or entry.class == "semantics")
						and entry.prop ~= nil
						and not seen[key]
					then
						seen[key] = true
						local node = findNode(entry.path)
						if node ~= nil and handles[entry.path] ~= nil then
							if BINDING_PROPS[entry.prop] then
								applyProp(handles[entry.path], node, entry.prop :: string)
							elseif STYLE_PROPS[entry.prop] then
								applyStyleProp(handles[entry.path], node, entry.prop :: string)
							end
						end
					end
				end
			end)
		end
		-- AN ARMED COMMIT ALWAYS SOLVES: the record walk runs
		-- inside the solve, and an authored opacity dirties `paint` alone, so a pure
		-- fade would otherwise have no walk to record itself in. One armed commit per
		-- `withAnimation` call, and incremental layout skips a solve nothing dirtied.
		if channel.armed() then
			needsSolve = true
		end
		if needsSolve then
			-- A STRUCTURAL change clears the dirty set: the tree's shape moved, so the
			-- last solve's rects are not a safe base to splice onto.
			-- A STRUCTURAL change gives no reuse set at all: the tree's shape moved, so
			-- last solve's rects are not a safe base for anything.
			if needsStructure then
				dirtyContains = nil
			else
				-- THE ANCESTOR CLOSURE. A node may be skipped only if NOTHING inside it
				-- is dirty, so the set handed to the solver is every dirty node plus
				-- every ancestor of one — the solver skips exactly the nodes absent
				-- from it. Paths are `/a/b/c`, so the ancestors are the prefixes.
				local contains: { [string]: boolean } = {}
				for _, entry in dirty do
					local path = entry.path
					if (entry.class == "measure" or entry.class == "arrange") and path ~= nil then
						contains[path] = true
						local at = path
						while true do
							local cut = string.match(at, "^(.*)/[^/]*$")
							if cut == nil or cut == "" or contains[cut] then
								break
							end
							contains[cut] = true
							at = cut
						end
					end
				end
				dirtyContains = contains
			end
			solveAndApply()
			-- the set belongs to THIS refresh; a re-entrant solve (text measurement, an
			-- env observer) must not reuse it, and gets a full solve instead
			dirtyContains = nil
		end
		-- LAST, after the solve, so a hook can read its own rect (see the queue's
		-- declaration). Nothing has reached the screen yet: this whole call is
		-- synchronous, and the engine renders after it returns.
		drainAppeared()
		return stats
	end

	-- focus visuals are style output (§8.4): the presenter drives this with
	-- the logical focus path; nil clears
	local focusedPath: string? = nil
	local focusRingVisible = true
	local bridgeEngaged = (opts and opts.engineSelectionBridge) == true
	-- `visible` (optional, default true) is the RING's own answer, separate from
	-- the focus path: a pointer/touch-driven focus move tracks focus, drives the
	-- selection bridge and moves the aim, and paints nothing (focus_graph's
	-- `focusVisible`; device round 1's second focus finding). Absent = today's
	-- behaviour, so
	-- every existing caller is unchanged.
	function controller.setFocusPath(path: string?, visible: boolean?)
		local wantRing = visible ~= false
		if path == focusedPath and wantRing == focusRingVisible then
			return
		end
		-- engine-selection bridge, from the native-substrate round: OPT-IN mirror of
		-- logical focus to
		-- engine selection while this surface owns UI input. Measured engine
		-- constraints (spike m9): the mirrored instance must be Selectable
		-- (non-selectable targets get warned about and REASSIGNED); expect
		-- native autoscroll inside scroll hosts; offscreen selection is NOT
		-- auto-cleared. Facet focus identity stays authoritative — this is a
		-- render output, cleared on dispose. Feature-detected + flag-gated:
		-- passive surfaces never reach here with the flag set.
		if bridgeEngaged and adapter.setEngineSelection ~= nil then
			adapter.setEngineSelection(if path ~= nil then handles[path] else nil)
		end
		-- A CONTROL THAT PAINTS ITS OWN FOCUSED STATE GETS NO SECOND ONE (director
		-- playtest 2026-08-03). `focusVisual = "none"` is declared on the NODE, so
		-- the decision is made here, where the node is known — the adapter's
		-- `setFocusVisual` handle carries no props and could not see it, and a check
		-- there would have been accepted-and-ignored, which is the one thing a
		-- declared prop may never be.
		local function paintsOwnFocus(p: string?): boolean
			if p == nil then
				return false
			end
			local node = findNode(p)
			return node ~= nil and node.props ~= nil and node.props.focusVisual == "none"
		end
		if adapter.setFocusVisual ~= nil then
			-- ten-foot focus strengthening (UI-PARADIGM-003, matrix D.4): the
			-- distance profile rides the focus write so the adapter can render an
			-- unmistakable-at-3m state (scale + glow) on a Large display while a
			-- near display keeps the hairline ring. Third arg is optional —
			-- older adapters ignore it and stay byte-identical.
			local profile = env:get("distanceProfile"):get()
			if focusedPath ~= nil and handles[focusedPath] ~= nil and not paintsOwnFocus(focusedPath) then
				adapter.setFocusVisual(handles[focusedPath], false, profile)
			end
			if wantRing and path ~= nil and handles[path] ~= nil and not paintsOwnFocus(path) then
				adapter.setFocusVisual(handles[path], true, profile)
			end
		end
		focusedPath = path
		focusRingVisible = wantRing
	end

	-- verifier F2: a displaySize dock (Medium <-> Large) must re-strengthen a
	-- RESTING focus visual — text and margins already re-adopt via the solve
	-- subscription, and the focus ring must move with them without waiting for
	-- the next focus change
	attachScope:own(core:observe(env:get("distanceProfile"), function(profile)
		if
			adapter.setFocusVisual ~= nil
			and focusRingVisible
			and focusedPath ~= nil
			and handles[focusedPath] ~= nil
		then
			adapter.setFocusVisual(handles[focusedPath], true, profile)
		end
	end))

	-- verifier F3: hover is a hot-switch CARRY idiom — a pointer ARRIVING
	-- mid-session (dock adds a mouse) enables hover on nodes that already
	-- exist, not only on nodes created after the flip. enableHover is
	-- idempotent; there is no disable path (without a mouse the events
	-- simply never fire).
	do
		local hoverLive = env:get("interactionClasses"):get().pointer == true
		attachScope:own(core:observe(env:get("interactionClasses"), function(classes)
			local live = classes.pointer == true
			if live and not hoverLive and adapter.enableHover ~= nil then
				local function enableWalk(node: any)
					if HOVERABLE[node.class] and handles[node.path] ~= nil then
						adapter.enableHover(handles[node.path])
					end
					for _, child in node.children do
						enableWalk(child)
					end
				end
				enableWalk(root.node)
			end
			hoverLive = live
		end))
	end

	-- ...and the SAME carry idiom for disclosure engagement zones (architecture
	-- review F-5): long-press is the ONLY full-value path on touch, so a touch
	-- class arriving mid-session (hybrid handheld docking, first tap on a
	-- touchscreen laptop) must retrofit zones onto already-mounted disclosed
	-- labels exactly as hover does. `enableDisclosure` merges per half, so a
	-- label wired for hover at mount gains the touch half here without
	-- disturbing the first.
	do
		local discloseHoverCb = opts and (opts :: any).onDiscloseHover
		local disclosePressCb = opts and (opts :: any).onDiscloseLongPress
		if (discloseHoverCb ~= nil or disclosePressCb ~= nil) and adapter.enableDisclosure ~= nil then
			local last = env:get("interactionClasses"):get()
			local lastPointer, lastTouch = last.pointer == true, last.touch == true
			attachScope:own(core:observe(env:get("interactionClasses"), function(classes)
				local pointer, touch = classes.pointer == true, classes.touch == true
				if (pointer and not lastPointer) or (touch and not lastTouch) then
					local function wireWalk(node: any)
						local discloses = (node.props or {}).disclose == true or (node.props or {}).reveal ~= nil
						if (discloses or (node.props or {}).help ~= nil) and handles[node.path] ~= nil then
							local path = node.path
							adapter.enableDisclosure(handles[path], {
								hover = if discloseHoverCb ~= nil and pointer
									then function(over: boolean)
										discloseHoverCb(if over then path else nil)
									end
									else nil,
								-- the press half is the PLATE's, never help's (D3a)
								longPress = if disclosePressCb ~= nil
										and discloses
										and touch
									then function(held: boolean)
										disclosePressCb(if held then path else nil)
									end
									else nil,
							})
						end
						for _, child in node.children do
							wireWalk(child)
						end
					end
					wireWalk(root.node)
				end
				lastPointer, lastTouch = pointer, touch
			end))
		end
	end

	--[[ REDUCED MOTION IS A LIVE FACT, AND IT REACHES THE TARGET FROM HERE — both
		halves of a target's motion, through one observation of one env key.

		`setNativeTransitionsEnabled` is the SHEET half, from the native-stylesheet round:
		when the target runs sheet-owned paint, the adapter strips/restores the
		sheet's declared transitions on the fly (SetPropertyTransitions({}) — the
		proven instant path, spike m9).

		`setReducedMotion` is the BESPOKE half (C1, 2026-08-12), and it exists
		because the comment that used to stand here was false. It said bespoke
		targets "consult the reducedMotion policy per-play already" — they consult
		a `screen_target.new({ isReducedMotion = ... })` CLOSURE, and no production
		caller anywhere ever passed one (not the showcase, not RascalRally's four
		GUIs), so every bespoke tween ran at full motion for a player who had asked
		for less. A construction-time opt four call sites forgot is the defect; the
		repair is that the framework pushes the fact instead of hoping a consumer
		wires it. Both calls are feature-detected, so a target with neither degrades
		by name (target_contract) rather than crashing.

		Pushed once at attach and again on every change, so a mid-session flip of
		the player's setting lands without a remount. ]]
	if adapter.setNativeTransitionsEnabled ~= nil or adapter.setReducedMotion ~= nil then
		local function pushReducedMotion(reduced: boolean)
			if adapter.setNativeTransitionsEnabled ~= nil then
				adapter.setNativeTransitionsEnabled(reduced ~= true)
			end
			if adapter.setReducedMotion ~= nil then
				adapter.setReducedMotion(reduced == true)
			end
		end
		pushReducedMotion(env:get("reducedMotion"):get() == true)
		attachScope:own(core:observe(env:get("reducedMotion"), function(reduced)
			pushReducedMotion(reduced == true)
		end))
	end

	--[[ THE PLAYER'S BACKGROUND TRANSPARENCY PREFERENCE (owed row O-26).

		The third accessibility fact to ride this seam, and it rides it for exactly
		the reason the second one had to: `setReducedMotion` above exists because the
		fact used to arrive only through a construction-time opt that all four
		production call sites forgot, so the preference silently did nothing. A
		preference the framework merely PUBLISHES is a preference no player feels;
		`effectiveTransparency` had been published and unread for four stages.

		The env memo is the clamp — a garbage or NaN platform reading becomes 1
		(paint what the theme said) before it ever reaches an adapter, so the seam
		carries a value already in its legal domain.

		UNLIKE `setReducedMotion`, THIS ONE REPAINTS. Reduced motion changes how the
		NEXT transition plays; a transparency preference changes what is on screen
		right now, so an adapter that takes it has to move the backdrop it has
		already painted, not merely remember the number. ]]
	if adapter.setPreferredTransparency ~= nil then
		local effective = env:get("effectiveTransparency")
		adapter.setPreferredTransparency(effective:get())
		attachScope:own(core:observe(effective, function(value)
			adapter.setPreferredTransparency(value)
		end))
	end

	function controller.initialRender()
		structuralSync()
		solveAndApply()
		root.takeDirty() -- initial mount noise is not an update
		initialized = true
		-- the same order `refresh` uses, for the same reason: after the solve, so an
		-- `onAppear` on a first-frame node can read the rect it was just given
		drainDeparted()
		drainAppeared()
		return stats
	end

	--[[ "THIS SURFACE JUST FINISHED SOLVING" — the seam a measurer needs (L-31).
		The presenter registers exactly one listener here and uses it to feed
		solved rects to `onGeometry` and every contribution's `syncGeometry`. It
		exists because the alternative is polling `stats().solves`, which clones a
		table on every settle pass of every flush in the session.

		It fires at the tail of the OUTERMOST solve only (a text-measurement
		re-solve nests), so a listener always sees final geometry. ]]
	--[[ ...AND THE SAME DRAIN, ASKED FOR BY HAND (see THE SOLVE'S OWN FEEDBACK).
		`initialRender` solves before the presenter has discovered its contributions
		— a contribution cannot be bound to a controller that has not rendered — so
		the FIRST `syncGeometry` is a direct call, not an `onSolved` notification,
		and nothing in the solve is there to notice what it published. The presenter
		calls this immediately after that one hand-made feed. A no-op unless
		something really dirtied the tree since the last solve was announced. ]]
	function controller.settleFeedback()
		if initialized and root.dirtySeq() > feedbackMark then
			resolveForFeedback()
		end
	end

	function controller.onSolved(fn: () -> ()): () -> ()
		table.insert(solvedListeners, fn)
		return function()
			for i, existing in solvedListeners do
				if existing == fn then
					table.remove(solvedListeners, i)
					break
				end
			end
		end
	end

	controller.rectOf = rectOf
	-- ...and the same rect in WINDOW space. `rectOf` answers the
	-- SOLVED rect, which inside a scroll host is canvas-space — the engine shifts
	-- it by CanvasPosition — and which a live presentation transform has moved away
	-- from on screen. Anything comparing a rect against a POINTER (drop hit-tests,
	-- autoscroll bands) must use this one, or it targets the wrong row the moment
	-- the list is scrolled or the surface is shifted.
	controller.screenRectOf = screenRectOf

	--[[ A NODE HANDS BACK ITS OWN MOUNTED PATH (gap 15, framework-gaps-phase2).
		`handles` is this surface's live path -> instance-handle registry, so it
		already answers "what is actually mounted right now" — the fact a caller
		who only knows the DECLARED id chain (never told at what depth an
		ancestor `UI.When` sits) previously had no honest way to reach except
		enumerating every live path and substring-scanning it by hand
		(`examples/reference/p5_wardrobe/init.luau`'s `adapter.paths()` fallback,
		dead code because no adapter ever grew that dump — this is the API that
		makes it unnecessary).

		Exact match first (the common case: nothing between the declared node and
		the surface root spliced a segment in), then a `/then`-stripped compare
		against every live path — `paths.stripThenSegments` is the one home for
		that arithmetic, shared with any future caller. Returns the FIRST live
		path whose stripped form equals the declared one; a declared chain that
		names no live node, or genuinely matches more than one (an author-level
		ambiguity this function does not try to arbitrate), answers through the
		same "first found" rule rather than throwing — callers already treat a
		`nil`/best-effort path the way `stageHost`/`screenRectOf` do. ]]
	local function mountedPathOf(declaredPath: string): string?
		if handles[declaredPath] ~= nil then
			return declaredPath
		end
		for livePath in handles do
			if paths.stripThenSegments(livePath) == declaredPath then
				return livePath
			end
		end
		return nil
	end
	controller.mountedPathOf = mountedPathOf

	--[[ THE SCROLLBAR GUTTER A HOST SPENT, for a node that must align ACROSS it.

		A scroll host reserves the bar off its own cross axis, so its DESCENDANTS
		stop short of it with nothing to do. The node this exists for is the one
		outside that subtree: a Table's header is a sibling of its scrolling body,
		lays its columns across the full frame, and drifts from the rows it names by
		exactly the reserve (director report 2026-08-14; the solver's `barInset`
		note carries the measurement).

		`{ right, bottom }` in px, or nil for a host that reserved nothing — which is
		the half a sibling cannot work out for itself, because it depends on whether
		the CONTENT overflows. Do not derive it from `adapter.scrollBarThickness`:
		that is the thickness a bar WOULD take, not the gutter this host took. ]]
	function controller.scrollBarInsetOf(path: string): any
		return lastBarInsets[path]
	end

	-- keep-visible presentation transform (§17 Phase 5 keyboard occlusion): the
	-- presenter drives a transient upward offset on the SCREEN ROOT so an edited
	-- field stays above the on-screen keyboard. Presentation authority (never
	-- layout): it shifts what is painted without re-solving. dy=0 restores.
	local lastOffsetY: number? = nil
	-- programmatic scroll, from the native-substrate round: the framework's ONLY
	-- scroll
	-- write — keep-visible and scroll-to-row compute a target and set it here;
	-- the engine owns everything between offsets. Degrades to a no-op on a
	-- scroll-less adapter (fallback path stays clip-only).
	function controller.scrollTo(path: string, pos: { x: number, y: number })
		local handle = handles[path]
		if handle ~= nil and adapter.setScrollPosition ~= nil then
			adapter.setScrollPosition(handle, pos)
		end
	end

	-- hidden-subtree roots from the last solve (A-AL1). The presenter consults
	-- this when rebuilding focus order; an empty table means nothing is hidden.
	-- see `structureEpoch` above: the value a caller can cache a tree derivation on.
	function controller.structureEpoch(): number
		return structureEpoch
	end

	function controller.hiddenRoots(): { [string]: boolean }
		-- A COPY, like `stats()` (F-30). The live set is the renderer's own state
		-- for the frame; a caller that mutated it corrupted the visibility walk,
		-- and a caller that cached it held a table the next solve replaced. One
		-- shallow clone of a small map, on a diagnostic read.
		return table.clone(hiddenRoots)
	end

	-- native drag acquisition (B-VAL2; corrections §1): attach a UIDragDetector to
	-- a MOUNTED node by path. The engine owns acquisition and cross-input motion;
	-- the framework converts positions into its own value model. Returns a detach
	-- function, or nil when the adapter or engine has no detector — callers MUST
	-- have a fallback, which is why the return value is nilable rather than an
	-- error.
	function controller.attachDragDetector(path: string, handlers: any): (() -> ())?
		return attachDetector(path, handlers)
	end

	-- CONTEXT GESTURES ON A MOUNTED NODE (D2 Menu). The two engine channels a
	-- context trigger needs and no control can reach: the NORMALIZED touch
	-- gesture stream (shipped with nothing consuming it as a trigger) and
	-- the pointer's SECONDARY button. Same nilable contract as
	-- attachDragDetector — an adapter or engine without either simply never
	-- fires, and a Menu's other three triggers still open it.
	function controller.attachContextGestures(path: string, handlers: any): (() -> ())?
		local handle = handles[path]
		if handle == nil then
			return nil
		end
		local offs: { () -> () } = {}
		if handlers.onGesture ~= nil and adapter.setTouchGestureHandlers ~= nil then
			table.insert(offs, adapter.setTouchGestureHandlers(handle, handlers.onGesture))
		end
		if handlers.onSecondary ~= nil and adapter.setSecondaryActivate ~= nil then
			table.insert(offs, adapter.setSecondaryActivate(handle, handlers.onSecondary))
		end
		if #offs == 0 then
			return nil
		end
		return function()
			for _, off in offs do
				off()
			end
		end
	end

	-- THE SURFACE'S DRAG REGISTRY. Every mounted
	-- `UI.draggable` / `UI.dropTarget` on this surface lives here, and so does
	-- the one session all four input classes drive. Consumers reach it for the
	-- non-pointer verbs (`arm`/`armTo`/`commit`/`cancel`), the predicted
	-- `verdict` Readable, and `refreshTargets()` — which an autoscrolling host
	-- calls in the SAME frame as its scroll write so the row-under-pointer
	-- verdict never trails the scroll.
	function controller.dragRegistry(): any
		return dragRegistry()
	end

	--[[ THE LAST-RESORT ACTIVATE, and the Cancel that belongs with it — the
		keyboard-and-pad drag adaptation again.
		The presenter calls `activateArms` after every other meaning of a press has
		declined, and `cancelArmed` from its Cancel chain after the contributions
		have had theirs — so B/Escape puts down a card the generic verb picked up,
		and never a grab some control owns. Both answer false when there is nothing
		of ours to act on, which is what keeps them out of every other route. ]]
	function controller.activateArms(path: string, meta: any?): boolean
		return activateArms(path, meta)
	end

	function controller.cancelArmed(reason: string?): boolean
		if not armedBySeam() then
			return false
		end
		dragRegistryInstance.cancel(reason or "cancelVerb")
		armedHere = false
		return true
	end

	-- Non-creating read of the registry. The presenter broadcasts "a surface just
	-- presented" (finding F7) to every LIVE surface; using `dragRegistry()` for
	-- that would lazily build a registry on every surface that never declared a
	-- draggable, purely to tell it about a modal it cannot care about.
	function controller.peekDragRegistry(): any
		return dragRegistryInstance
	end

	-- INTEGRATION SEAM for the presentation layer: the semantic feedback bus,
	-- the drag-proxy layer, the motion clock and an injected `now`. Each is
	-- optional and each degrades exactly one behaviour — a registry with none of
	-- them still resolves every verdict identically, which is how the headless
	-- suite drives it. Callable at any time (before or after the first
	-- declaration mounts): the presentation layer is built around a PRESENTED
	-- surface, so a seam that could only be set before mount would force every
	-- host to guess the order.
	function controller.setDragCollaborators(collaborators: { [string]: any })
		for key, value in collaborators do
			dragCollaborators[key] = value
		end
		if dragRegistryInstance ~= nil then
			dragRegistryInstance.setCollaborators(collaborators)
		end
	end

	-- read the live offset (A-SV1: the public construct needs a READABLE as well
	-- as a settable offset). The engine co-authors this value, so it is read
	-- from the adapter rather than cached as a framework-owned property.
	function controller.scrollPosition(path: string): { x: number, y: number }?
		local handle = handles[path]
		if handle ~= nil and adapter.getScrollPosition ~= nil then
			return adapter.getScrollPosition(handle)
		end
		return nil
	end

	-- scroll-to-visible (A-SV1): THE shared keep-visible substrate. Every
	-- control that must bring a focused, selected, or newly-revealed descendant
	-- into view asks for it here instead of carrying its own scroll arithmetic,
	-- so the minimum-distance rule, the clamp, and the axis handling exist once.
	-- Returns true when it actually moved the host.

	function controller.scrollToVisible(path: string): boolean
		if adapter.setScrollPosition == nil then
			return false -- clip-only fallback adapter: nothing to scroll
		end
		-- the nearest ScrollView ANCESTOR (never `path` itself). `structuralSync`'s
		-- `livePaths` walk already threads that host down the tree and records it
		-- here — its own comment says it exists so this is not "computed on demand
		-- instead", which is exactly what a second full-tree walk here was doing
		-- (Step 5.5 cleanup ledger C-03). Absent from the map means not yet
		-- structurally synced, and such a path has no `lastRects` entry either, so
		-- both spellings refuse it.
		local hostPath: string? = scrollHostOf[path]
		if hostPath == nil then
			return false
		end
		local hostRect = lastRects[hostPath]
		local targetRect = lastRects[path]
		local region = lastScrollRegions[hostPath]
		if hostRect == nil or targetRect == nil or region == nil then
			return false
		end
		local isX = region.axis == "x"
		local current = controller.scrollPosition(hostPath) or { x = 0, y = 0 }
		local offset = if isX then current.x else current.y
		local band = if isX then hostRect.w else hostRect.h
		local extent = if isX then region.contentW else region.contentH
		-- canvas-space span of the target (the solver arranges children in the
		-- host's own coordinate space; the engine shifts them by the offset)
		local top = (if isX then targetRect.x else targetRect.y) - (if isX then hostRect.x else hostRect.y)
		local size = if isX then targetRect.w else targetRect.h
		-- ONE implementation of the minimum-distance rule (A-SV2)
		local wanted = solver.keepVisibleOffset(top, size, offset, band, extent)
		if wanted == nil then
			return false
		end
		controller.scrollTo(hostPath, {
			x = if isX then wanted else current.x,
			y = if isX then current.y else wanted,
		})
		return true
	end

	--[[ HAND A PRESS TO WHAT IS UNDERNEATH IT (ruling 6, director 2026-08-13).

		THE ENGINE FACT THIS EXISTS FOR, measured live in Studio 2026-08-13 and
		measured directly: Roblox
		delivers `InputBegan` to the TOPMOST interactive object only. A `GuiButton`
		sinks it and an Active `Frame` behind it receives NOTHING. So a hit surface
		painted BEHIND a row's content — which is how `row_actions` and `table`'s own
		`rowBlueprint` were both built, on a comment claiming the opposite — is dead
		wherever a Button covers it, and the row cannot be swiped there.

		The ruled repair (option A) puts the gesture surface ON TOP, where it always
		receives the press, and makes it FORWARD a press it decides was not its own.
		Forwarding cannot go back through the engine — the press has already been
		delivered and sunk — so it comes here instead, to the one place that holds
		the live tree, the solved rects and the tap dispatch the engine's own
		`Activated` would have reached.

		WHAT IT PICKS. The LAST node in document order (which is paint order, so the
		last match is the topmost) that (i) sits under `within` and is not under
		`skip`, (ii) is something the engine would have delivered the press to at
		all, (iii) is not hidden or disabled, (iv) contains the point in WINDOW
		space, and (v) is not scrolled out of its own clip host.

		"SOMETHING THE ENGINE WOULD HAVE DELIVERED TO" IS TWO FAMILIES, NOT ONE, and
		getting that wrong would have traded one dead control for another. A `Button`
		/`Toggle`/`TextField` is activated through `setActivateHandler`, so a
		forwarded press has to run that dispatch. But a `Rating`, a `Slider` and every
		other control built on a POINTER ZONE (`onPointerDown`/`onPointerUp` props,
		) is not `TAPPABLE` at all — it hears the raw press. Before this
		ruling those worked and the swipe did not, because they were painted on top;
		forwarding only the tappable family would have inverted exactly that, on the
		same surfaces. So a pointer zone gets its down/up pair replayed at the point,
		in order, with the same `screenRectOf` a native press is handed.

		The `skip` prefix exists because the forwarding surface is ITSELF a pointer
		zone and lives inside `within` — without it, the Grip would forward every
		press straight back to itself.

		The tappable path runs the SAME body `setActivateHandler` runs — the hidden
		gate, the per-press dedupe, the drag-arm check, `opts.onNodeTap` — because a
		forwarded tap must be indistinguishable from a native one. Returns the path it
		dispatched to, or nil when nothing was under the point. ]]
	local function isPointerZone(node: any): boolean
		local props = node.props
		return props ~= nil and (props.onPointerDown ~= nil or props.onPointerUp ~= nil)
	end
	function controller.tapAt(x: number, y: number, sel: any?): string?
		local within: string? = if type(sel) == "table" then sel.within else nil
		local skip: string? = if type(sel) == "table" then sel.skip else nil
		local found: any = nil
		local function walk(node: any)
			local path = node.path
			if skip ~= nil and isPathPrefix(skip, path) then
				return -- the forwarding surface's own subtree is never a target
			end
			local tappable = TAPPABLE[node.class]
			if
				(tappable or isPointerZone(node))
				and solverHidden[path] ~= true
				and (node.props == nil or node.props.enabled ~= false)
			then
				local rect = screenRectOf(path)
				if
					rect ~= nil
					and x >= rect.x
					and x <= rect.x + rect.w
					and y >= rect.y
					and y <= rect.y + rect.h
					and not pathEscapesClip(path, screenRectOf)
				then
					found = node -- last match wins: document order IS paint order
				end
			end
			for _, child in node.children do
				walk(child)
			end
		end
		local from = if within ~= nil then findNode(within) else root.node
		if from == nil then
			return nil
		end
		walk(from)
		if found == nil then
			return nil
		end
		local node = found :: any
		local target = node.path :: string
		if not TAPPABLE[node.class] then
			-- a POINTER ZONE: replay the press it never received, in order
			local pos = { x = x, y = y, pointerType = "touch", forwarded = true }
			if node.props.onPointerDown ~= nil then
				node.props.onPointerDown(target, pos, screenRectOf)
			end
			if node.props.onPointerUp ~= nil then
				node.props.onPointerUp(target, pos, screenRectOf)
			end
			return target
		end
		local onNodeTap = opts and opts.onNodeTap
		if onNodeTap == nil then
			return nil
		end
		if not dispatchNodeTapOnce(target) then
			return nil
		end
		if tapArmsInstead(target, { via = "forwardedTap" }) then
			return target
		end
		onNodeTap(target, { via = "forwardedTap" })
		return target
	end

	-- THE SCROLL HOST THAT CARRIES A NODE, with everything an edge autoscroll
	-- needs to steer it, in ONE answer (Table's reorder autoscroll, 2026-07-29).
	--
	-- A control cannot work this out for itself. The host may be its own scroller
	-- (a viewport Table's Body) or an ANCESTOR it does not own — a block Table
	-- inside a scrolling page is the shipped shape, and there the thing that has
	-- to move belongs to the consumer's screen, not to the control. The nearest
	-- ScrollView ancestor is already threaded down `structuralSync`'s live-path
	-- walk for `screenRectOf`, and the canvas extent is already recorded per host
	-- for the region push, so this exposes the pair rather than tempting three
	-- separate internals out through the API (the same argument `scrollToVisible`
	-- makes for the keep-visible arithmetic).
	--
	-- `rect` is in WINDOW space, because the caller compares it against a POINTER.
	-- Pass `includeSelf` for a node that may BE the host.
	function controller.scrollHostFor(path: string, includeSelf: boolean?): any
		local hostPath: string? = if includeSelf == true and lastScrollRegions[path] ~= nil
			then path
			else scrollHostOf[path]
		if hostPath == nil then
			return nil
		end
		local region = lastScrollRegions[hostPath]
		local rect = screenRectOf(hostPath)
		if region == nil or rect == nil then
			return nil
		end
		local isX = region.axis == "x"
		local offset = controller.scrollPosition(hostPath) or { x = 0, y = 0 }
		local band = if isX then rect.w else rect.h
		local extent = if isX then region.contentW else region.contentH
		return {
			path = hostPath,
			rect = rect,
			axis = if isX then "x" else "y",
			offset = if isX then offset.x else offset.y,
			-- clamped the way the engine clamps CanvasPosition: nothing to scroll
			-- reports 0, which is what makes an autoscroll model INERT rather than
			-- arming against a canvas that cannot move
			maxScroll = math.max(0, extent - band),
		}
	end

	-- ===== drag-to-edge autoscroll (device report 2026-07-29) ==============
	-- "I moved my finger to the bottom of the scroll view and held it, and it
	-- didn't auto-scroll."
	--
	-- THE POLICY LIVES ON THE SCROLLER (director ruling, same day). A drag says
	-- only WHERE the pointer is; every ScrollView decides for itself whether that
	-- point is at an edge it can still move along. That is what makes it work for
	-- a Table, an HStack of cards, or a mix, with no per-control copy — and it is
	-- the only arrangement that can answer the NESTED case, because "which
	-- scroller should move" is a question about the chain of scrollers under the
	-- point, not about the thing being dragged.
	--
	-- THE CHAIN RULE, innermost outward: take the ScrollViews whose PAINTED rect
	-- contains the drag point, nearest first. The first one that (a) has the point
	-- inside one of its own edge bands and (b) can still travel that way wins.
	-- A host already pinned at that end is transparent — the gesture falls
	-- through to its parent, which is what lets a short inner list hand a drag off
	-- to the page once its own tail is reached. Every host that is not the winner
	-- is reset, so a chain can never have two models armed at once.
	local pointerDrag: any = nil
	local autoscrollClock = 0

	-- a live pointer drag, published by whoever owns it (Table's reorder, the
	-- public drag registry). `nil` retracts it. `refresh` is called after a scroll
	-- lands so the owner can re-resolve its verdict in the SAME frame.
	function controller.setPointerDrag(info: any)
		if info == nil then
			pointerDrag = nil
			for _, model in autoscrollModels do
				model:reset()
			end
			return
		end
		pointerDrag = info
	end

	-- the ScrollView chain under a point, innermost first
	local function scrollChainAt(x: number, y: number): { string }
		local chain: { string } = {}
		for path, region in lastScrollRegions do
			if region ~= nil and handles[path] ~= nil then
				local rect = screenRectOf(path)
				if rect ~= nil and rectLib.containsClosed(rect, x, y) then
					table.insert(chain, path)
				end
			end
		end
		-- deepest path first: a descendant's path is strictly longer than its
		-- ancestor's (paths are "/a/b/c"), so length orders the chain without a
		-- second tree walk. Ties are unrelated subtrees, which cannot both contain
		-- the point unless they overlap; `sort` is stable enough for that case
		-- because either answer is equally correct.
		table.sort(chain, function(a, b)
			return #a > #b
		end)
		return chain
	end

	-- `autoscroll` prop -> model options, or nil when this host opts out
	local function autoscrollOptsFor(path: string): any
		local declared = scrollAutoscroll[path]
		if declared == false then
			return nil
		end
		return if type(declared) == "table" then declared else {}
	end

	-- one autoscroll frame for the whole surface. Returns the host it moved (nil
	-- when nothing did) so a caller can assert on it.
	function controller.stepAutoscroll(dt: number?): any
		autoscrollClock += math.max(dt or 0, 0)
		local drag = pointerDrag
		if drag == nil or type(drag.pos) ~= "table" or adapter.setScrollPosition == nil then
			for _, model in autoscrollModels do
				model:reset()
			end
			return nil
		end
		local chain = scrollChainAt(drag.pos.x, drag.pos.y)
		local winner: string? = nil
		local winnerStep: any = nil
		for _, path in chain do
			if winner ~= nil then
				break
			end
			local opts = autoscrollOptsFor(path)
			local region = lastScrollRegions[path]
			local rect = screenRectOf(path)
			if opts ~= nil and region ~= nil and rect ~= nil then
				local isX = region.axis == "x"
				local band = if isX then rect.w else rect.h
				local extent = if isX then region.contentW else region.contentH
				local maxScroll = math.max(0, extent - band)
				local current = controller.scrollPosition(path) or { x = 0, y = 0 }
				local offset = if isX then current.x else current.y
				local model = autoscrollModels[path]
				if model == nil then
					-- the band follows the HOST's shape, not the screen's: a short
					-- wide inner list and the tall page around it do not want the
					-- same reach (autoscroll.bandForViewport owns that choice).
					local resolved = table.clone(opts)
					if resolved.bandH == nil then
						resolved.bandH = autoscrollLib.bandForViewport(rect.w, rect.h)
					end
					model = autoscrollLib.new(resolved)
					autoscrollModels[path] = model
				end
				-- the model is written for the scroll axis as a 1-D problem, so an
				-- x-axis host is fed its own axis's numbers
				local step = model:step({
					now = autoscrollClock,
					pointerPos = if isX then { x = drag.pos.y, y = drag.pos.x } else drag.pos,
					hostRect = if isX then { x = rect.y, y = rect.x, w = rect.h, h = rect.w } else rect,
					canvasPos = offset,
					maxScroll = maxScroll,
				})
				-- CAN THIS HOST STILL TRAVEL THE WAY THE POINTER IS ASKING? The model
				-- deliberately stays ARMED at the end of its canvas (its rule 5, so
				-- pulling back and pushing in again does not re-pay the dwell) — but
				-- for a CHAIN that would mean a list pinned at its tail silently
				-- swallowing the gesture forever. A host that cannot move in the
				-- direction of the band it owns is transparent: it disarms and the
				-- drag falls through to its parent, which is what lets a short inner
				-- list hand off to the page (director, 2026-07-29).
				local bandName = model:band()
				local canTravel = if bandName == "top" or bandName == "left"
					then offset > 0
					elseif bandName == "bottom" or bandName == "right" then offset < maxScroll
					else false
				if step.state ~= "idle" and canTravel then
					winner = path
					winnerStep = step
					if step.delta ~= 0 then
						controller.scrollTo(path, {
							x = if isX then offset + step.delta else current.x,
							y = if isX then current.y else offset + step.delta,
						})
						if type(drag.refresh) == "function" then
							drag.refresh()
						end
					end
				else
					model:reset()
				end
			end
		end
		-- every host that did not win is disarmed, so no second model keeps a
		-- dwell timer running behind the one the player is actually steering
		for path, model in autoscrollModels do
			if path ~= winner then
				model:reset()
			end
		end
		if winner == nil then
			return nil
		end
		return { path = winner, state = winnerStep.state, delta = winnerStep.delta }
	end

	-- engine-driven scroll observation (windowing consumes this in Phase 3):
	-- returns an unsubscribe; a scroll-less adapter returns a no-op unsubscribe
	function controller.observeScroll(path: string, fn: (pos: { x: number, y: number }) -> ()): () -> ()
		local handle = handles[path]
		if handle ~= nil and adapter.observeScroll ~= nil then
			return adapter.observeScroll(handle, fn)
		end
		return function() end
	end

	-- THE PRESENTATION CHANNEL'S FIVE PUBLIC METHODS, rebound onto the controller
	-- from `render/presentation_channel.luau` (see the construction above). Same
	-- functions, same names, same contract — `controller` is the renderer's public
	-- surface and none of it moved.
	controller.setPresentationTransform = channel.setPresentationTransform
	controller.setPresentationTransparency = channel.setPresentationTransparency
	controller.armAnimation = channel.armAnimation
	controller.disarmAnimation = channel.disarmAnimation
	controller.animationRecordCount = channel.animationRecordCount

	-- keep-visible, REIMPLEMENTED OVER THE PER-NODE CHANNEL. The
	-- root node IS the surface, so its transform is the whole-surface shift the
	-- keyboard case needs; `dy = 0` writes the zero transform rather than clearing,
	-- because "restored" is a value the presenter's own tests read back.
	function controller.setPresentationOffset(dy: number)
		if dy == lastOffsetY then
			return
		end
		lastOffsetY = dy
		controller.setPresentationTransform(root.node.path, { x = 0, y = -dy })
	end

	-- cross-surface z (modal-dismissal spec §2.2): the presenter orders whole
	-- surfaces (base < scrim < modal) via the root's display order. Optional
	-- adapter method — headless/older targets that don't order roots ignore it.
	function controller.setDisplayOrder(n: number)
		-- recorded whatever the adapter does with it: the ORDER is the caller's
		-- declaration about layering, and a headless target that cannot
		-- order roots has not un-declared it
		declaredOrder = n
		if adapter.setRootDisplayOrder ~= nil then
			adapter.setRootDisplayOrder(rootHandle, n)
		end
	end

	-- THE ENGINE-CONTENT SEAM (UI.Stage, ViewportFrame adoption 2026-08-08). A
	-- `Stage` reserves a box for content the ENGINE draws, and that content is
	-- Instances by nature — so the framework never touches it: the adapter answers
	-- a per-node handle (camera, lighting, a content root the caller parents its own
	-- models into) and this is the one door to it. Optional on BOTH sides: an
	-- adapter that never grew the seam, a node that is not a live Stage, or a path
	-- that is not mounted all answer nil, so an author gates on the nil or presents
	-- a fallback plate — never a crash and never a silent no-op.
	function controller.stageHost(path: string): any?
		if adapter.stageHost == nil then
			return nil
		end
		local handle = handles[path]
		if handle == nil then
			return nil
		end
		return adapter.stageHost(handle)
	end

	-- THE FOREIGN-CONTENT SEAM (UI.Foreign). Stage's 2-D sibling and the
	-- same door in the same place: a `Foreign` reserves a box for a GuiObject class
	-- Facet does not wrap, the caller creates that instance, and `adopt` is the one
	-- verb that puts it in the box. Optional on BOTH sides for the same reasons —
	-- an adapter that never grew the seam, a node that is not a live Foreign, or a
	-- path that is not mounted all answer nil, so an author gates on the nil and
	-- presents a fallback plate rather than crashing or silently doing nothing.
	function controller.foreignHost(path: string): any?
		if adapter.foreignHost == nil then
			return nil
		end
		local handle = handles[path]
		if handle == nil then
			return nil
		end
		--[[ THE `host` AUTHORITY IS ASSERTED HERE TOO, as the architecture review
		asked. "The renderer
			asserts every write" was true of four of the five authorities: the only
			`host` assert in the framework lived in the ENGINE ADAPTER
			(`screen_target`'s `adopt`), so a second render target — the whole point
			of the target contract — could grow a foreign seam that claimed
			`Foreign.Parent` with nothing checking. This is the renderer's own gate
			on the same claim, made where the seam is HANDED OUT rather than where
			one adapter happens to use it: past this line the caller holds the verb
			that parents somebody else's instance into a Facet box, and the manifest
			has said the framework may. The adapter keeps its own assert — two gates
			on one claim is the intent (nothing else may write it), not a
			duplication. ]]
		authority.assertWrite("Foreign", "Parent", "host")
		return adapter.foreignHost(handle)
	end

	-- whole-surface visibility, used by the presenter's no-pop text gate: a
	-- surface mounts and solves normally but is not SEEN until its text is
	-- exact. Returns false when the adapter cannot hide a root, so the caller
	-- can degrade to showing it rather than gating on a write that never lands.
	function controller.setRootVisible(visible: boolean): boolean
		if adapter.setRootVisible == nil then
			return false
		end
		adapter.setRootVisible(rootHandle, visible)
		-- ...and a surface nobody can see covers nothing. Recorded only
		-- where the write LANDED: on a target that cannot hide a root the surface
		-- is still on screen, and the alarm must go on believing that.
		rootVisible = visible
		return true
	end

	-- INCREMENTAL-LAYOUT STAGE 1: DETECTION ONLY (docs/plans/incremental-layout.md).
	--
	-- Re-solves the last tree with boundary detection on and reports how much of it a
	-- boundary-aware layout would have to redo for a single change. It changes
	-- nothing and runs only when called, so an ordinary frame pays nothing for it —
	-- the whole point of Stage 1 is to size Stages 2 and 3 before touching the solver
	-- for real.
	function controller.analyzeBoundaries(): any
		if lastSolveInputs == nil then
			return nil
		end
		local opts2 = table.clone(lastSolveInputs.opts)
		opts2.analyzeBoundaries = true
		local result = solver.solve(lastSolveInputs.layoutRoot, lastSolveInputs.viewport, opts2)
		return solver.boundaryReport(lastSolveInputs.layoutRoot, result)
	end

	function controller.stats()
		return table.clone(stats)
	end

	--[[ coverRect() -> what this surface actually PAINTS, or nil.

		The union of every painted box below the root, with nothing that paints
		nothing in it. The root's own rect is excluded by
		`surface_overlap.coverRect`: a `UI.Screen`'s rect is the content rect its
		`rootPolicy` resolved — the box the surface is allowed to paint in, which
		is the same box for every base screen on the device — and what a surface
		COVERS is what it puts in that box.

		A node is skipped when it or any ancestor is hidden, paint-held, or faded
		to nothing. That last one is the authored-presentation hand-off honoured by construction:
		an authored `opacity = 0` composes to `T = 1` in `lastComposedAlpha`, and a
		fade group is its subtree's real instance parent, so an ancestor at 1
		hides everything under it. A surface with nothing left covers nothing, and
		this answers nil — which is the whole reason the alarm is not a geometry
		test.
	]]
	local FULLY_FADED = 1 - 1e-6
	local function paintsNothing(path: string): boolean
		local p = path
		while p ~= "" do
			if hiddenRoots[p] == true or paintHeld[p] == true then
				return true
			end
			local alpha = channel.composedAlpha(p)
			if alpha ~= nil and alpha >= FULLY_FADED then
				return true
			end
			local cut = string.find(p, "/[^/]*$")
			if cut == nil then
				break
			end
			p = string.sub(p, 1, (cut :: number) - 1)
		end
		return false
	end

	function controller.coverRect(): any
		if not rootVisible then
			return nil
		end
		return surface_overlap.coverRect(root.node.path, lastRects, paintsNothing)
	end

	-- THE SURFACE, AS THE CROSS-SURFACE ALARM SEES IT. Registered once at attach,
	-- dropped once at dispose; every field is answered on demand so nothing here
	-- is computed by a frame.
	local surfaceEntry: surface_overlap.Entry = {
		id = root.node.id or "Screen",
		snapshot = function()
			return {
				id = root.node.id or "Screen",
				rect = controller.coverRect(),
				displayOrder = declaredOrder,
				rootPolicy = rootPolicy,
			}
		end,
	}
	local unregisterSurface = surface_overlap.register(adapter, surfaceEntry)

	--[[ retireSurface() — this stops being a SURFACE now, whatever is still on
		screen.

		`presenter.dismiss` takes a surface out of the stack immediately and
		tears its tree down LATER, when the exit transition finishes or the
		coordinator's cap fires. In that window a departing screen is fully
		painted over its replacement — which is the transition doing its job, and
		exactly what the framework arranged. Found by the corpus rather than by
		design: `p3_sipworks` pushes one detail over another and the alarm
		reported the pair on every compact viewport.

		So the alarm's set of live surfaces is the PRESENTER's set of live
		surfaces, and this is the one call that keeps them equal. Idempotent, and
		`dispose()` calls it again for every surface that never went through a
		presenter at all.
	]]
	function controller.retireSurface()
		unregisterSurface()
	end

	function controller.diagnostics()
		local out = table.clone(lastDiagnostics) -- a copy, like `stats()` (F-30)
		-- ...plus the findings no single solve can see: this surface covering, or
		-- being covered by, another surface on the same target with neither having
		-- declared it. Costs one length check when this is the only
		-- surface on the target, which is the overwhelming majority of reads.
		for _, finding in surface_overlap.findingsFor(adapter, surfaceEntry, root.node.path) do
			table.insert(out, finding)
		end
		return out
	end

	-- compositionAt(path) -> the last solve's `facet-composition-dump/1` for that
	-- UI.Composition node, or nil. Omit the path for every one of them, keyed by
	-- path. This is the "why" surface: which arrangement won, which
	-- form each region resolved to, and the rule every richer candidate broke.
	function controller.compositionAt(path: string?): any
		if path == nil then
			-- the SET is a copy (F-30); each dump inside it is the stored dump,
			-- exactly what the per-path read hands back
			return table.clone(lastCompositions)
		end
		return lastCompositions[path]
	end

	-- textAt(path) -> the last solve's measurement facts for that text node, or
	-- nil. Omit the path for every one of them, keyed by path. Same shape
	-- and same copy discipline as `compositionAt`: font, size, lines,
	-- naturalLines, truncated, lineLimit, disclose, policy, text.
	function controller.textAt(path: string?): any
		if path == nil then
			return table.clone(lastTextFacts)
		end
		return lastTextFacts[path]
	end

	-- THE PRESENTATION HOLD (auto reveal, 2026-08-04). The presenter paints its
	-- travelling strip OVER a source label and holds that label's own paint
	-- while the strip covers it. Presentation-layer only: the solve, the rects
	-- and the facts are untouched, so the reveal target stays "truncated" and
	-- the strip's travel distance stays honest. The hold survives re-solves and
	-- structural remounts of the path (the visibility walk ORs it in); it is
	-- the PRESENTER's to clear, and it dies with this controller either way.
	function controller.setPaintHeld(path: string, held: boolean)
		paintHeld[path] = if held then true else nil
		local handle = handles[path]
		if handle ~= nil and adapter.setVisible ~= nil then
			local want = solverHidden[path] ~= true and not held
			if lastVisible[path] ~= want then
				adapter.setVisible(handle, want)
				lastVisible[path] = want
			end
		end
	end

	-- is a text premeasurement round still outstanding? A surface that must not
	-- be seen until its text is exact polls this. False also means "nothing was
	-- ever asked for", which is the right answer for an adapter without the
	-- seam: there is nothing to wait for.
	function controller.textPending(): boolean
		for _ in textInFlight do
			return true
		end
		return false
	end

	function controller.dispose()
		-- a premeasurement round outlives the surface that asked for it (it is
		-- an async engine call): mark the controller dead so a late answer
		-- neither re-solves nor writes into destroyed handles
		disposed = true
		for _, cancel in textMeasureCancels do
			cancel()
		end
		table.clear(textMeasureCancels)
		-- ...and a disposed surface is no longer a surface: it leaves the
		-- cross-surface registry before anything else, so a teardown that throws
		-- later cannot leave a ghost overlapping the screen
		unregisterSurface()
		-- the selection bridge always clears on teardown: a dismissed
		-- modal must never leave the engine pointing at a destroyed instance
		if bridgeEngaged and adapter.setEngineSelection ~= nil then
			adapter.setEngineSelection(nil)
		end
		-- the drag registry dies with its surface: a live session holding a proxy
		-- and a motion pair must not outlive the tree it was aiming at
		if dragRegistryInstance ~= nil then
			dragRegistryInstance.dispose()
			dragRegistryInstance = nil
		end
		table.clear(dragUnbind)
		table.clear(scrollHostOf)
		-- RS-PATHCLIP: the per-scroll-host offset subscriptions are the one
		-- connection this rule holds, so they die with the surface like every
		-- other adapter subscription
		for path, detach in pathClipObservers do
			pathClipObservers[path] = nil
			detach()
		end
		table.clear(clipHostOf)
		table.clear(pathNodes)
		pathNodeCount = 0
		-- a `withAnimation` spring is built on the presenter's clock, which OUTLIVES
		-- this surface, so the springs die with the surface that started them
		channel.settleAll()
		attachScope:dispose()
		drainRecyclePool()
		adapter.destroyRoot(rootHandle)
		-- CLEARED IN PLACE, never rebound: the presentation channel holds both of
		-- these BY REFERENCE (see its construction above), so `handles = {}` here
		-- would leave it answering out of a table this surface had abandoned.
		table.clear(handles)
		table.clear(lastRects)
		-- ...and the overhang lift, which is a fact about a tree that no longer
		-- exists: a re-presented surface recomputes it from its own first solve
		table.clear(parentNodeOf)
		table.clear(inputSinks)
		hitLift.clear()
		-- ...and the per-host scrollbar gutters beside them: a dismissed surface
		-- that kept answering `scrollBarInsetOf` would hand a re-presented control
		-- the geometry of a tree that no longer exists
		table.clear(lastBarInsets)
		-- TEARDOWN IS A DISAPPEARANCE, and it is the most common one: a panel closes
		-- by being dismissed, not by having its rows re-keyed. Queued here, after the
		-- root is destroyed, so the hooks run with nothing left to reach and an error
		-- in one cannot strand the teardown above it. A pending APPEAR is dropped
		-- rather than fired — a node that never had a frame did not appear — while
		-- every declared cleanup still runs, because a missed cleanup is the dangerous
		-- direction and an extra one is not.
		table.clear(appearQueue)
		for path, fn in disappearHooks do
			table.insert(departedQueue, { path = path, fn = fn })
		end
		table.clear(disappearHooks)
		table.clear(authoredHidden)
		drainDeparted()
	end

	return controller
end

return renderer
