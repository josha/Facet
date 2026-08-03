--!strict
-- Presenter (design §12.1): owns screen/modal lifetimes, ScreenGui-level
-- policy (via the render adapter), focus scopes, and InputContext lifetime +
-- priority. Never owns game state. Engine-free: the adapter and action system
-- are injected (FakeTarget + headless actions in tests; ScreenTarget + IAS on
-- the client).
-- present(blueprint, opts)      -> handle   (base screen)
-- presentModal(blueprint, opts) -> handle   (focus trap + higher-priority sink context)
-- dismiss(handle) / back()      -> pops the top modal (Cancel routing)

local mountLib = require("../mount")
local blueprintLib = require("../blueprint")
local chrome_slots = require("../tokens/chrome_slots")
local renderer = require("../render/renderer")
local focus_graph = require("../focus/focus_graph")
local contribution = require("../input/contribution")
-- structural transitions, the toast model and the semantic feedback seam
-- (ADR-0022 Decisions 3, 4, 7). Each is engine-free and driven from here.
local transitionsLib = require("../render/transitions")
local toast_schedule = require("./toast_schedule")
local feedbackLib = require("./feedback")
local motionClockLib = require("../motion/clock")
-- the metric authority (ADR-0019 §2). The modal-dismissal spec pins the
-- forgiveness ring to space.l and the target ring to the effective hit floor;
-- both are now THEME values read from the live `themeMetrics` fact, so a theme
-- with roomier spacing gets a proportionally roomier dismiss ring for free.
local themeSnapshot = require("../themes/snapshot")
local specGuard = require("../spec_guard")

local presenter = {}

-- present()/presentModal()/presentCritical() options (verifier F4: the
-- presenter surface is typed, not `any`)
export type PresentOpts = {
	rootPolicy: string?,
	onActivate: ((path: string?, meta: any?) -> ())?,
	onAdjust: ((path: string, direction: number, rectOf: (string) -> any) -> ())?,
	onFocusNav: ((path: string) -> ())?,
	onReorderNav: ((path: string, direction: number) -> ())?,
	sinkNavigation: boolean?,
	-- responder mode (ADR-0014, present() only). Absent/nil = today's
	-- engaged-open semantics (context enabled, non-sinking — correct for a
	-- UI-only place). "passive" = a HUD that binds nothing gameplay-contended:
	-- its nav context is created DISABLED, so deviceKey navigation reaches lower
	-- (gameplay) contexts and never moves the HUD's focus. A passive surface
	-- becomes first responder via a tap on one of its focusables or handle.engage(),
	-- and drops back on Cancel / outside-tap / handle.resign(). presentModal is
	-- always engaged-exclusive regardless of this opt.
	responder: string?, -- "passive"
	-- engine-selection bridge (native-substrate NS-A12): presentModal-only
	-- opt-in that mirrors LuauUI's logical focus to GuiService.SelectedObject
	-- while the modal owns UI input. Ignored on present() (passive/gameplay
	-- surfaces keep SelectedObject nil — NS-A11). Experiment until the
	-- physical-gamepad row (NS-P1) closes; reversible by omitting the opt.
	engineSelectionBridge: boolean?,
	-- NO-POP TEXT (text-measurement milestone): mount and measure with the
	-- surface's ROOT hidden, and reveal it once the text is exact. Exact text
	-- arrives one re-solve after the first solve, so an ungated screen appears
	-- with conservatively-wide boxes and then visibly shrinks. The shrink is
	-- always safe (the estimate can only over-reserve; nothing ever clips) but
	-- "usually doesn't jump" is not a property a designer can build on.
	--
	-- Bounded by `revealTimeout` seconds, because a UI that never appears is a
	-- worse failure than one that jumps: on timeout the surface is revealed with
	-- the safe boxes. Needs an adapter with setRootVisible; without one the
	-- surface simply reveals immediately rather than hiding forever.
	revealWhenTextExact: boolean?,
	revealTimeout: number?, -- default 2s
	-- gameplay guard (ADR-0014): an engaged-exclusive context (modal, or a
	-- passive surface once engaged) binds Space to a no-op GameplayGuard so the
	-- keyboard jump is sunk while it is first responder (ButtonA is already sunk
	-- via Activate, arrows/D-pad via Navigate). Default true; set false for a
	-- surface that wants Space (a word-game modal). WASD is not sunk in v1.
	gameplayGuard: boolean?,
	-- grouped, direction-aware focus (§9.3; verifier F2): NavigationGroups
	-- for this screen's scope. When present, Up/Down/Left/Right (and dpad)
	-- route through graph.navigateDirection; Left/Right adjust bindings are
	-- unavailable on such screens (grouped navigation owns the horizontal).
	-- static array, or a function of the mounted root re-evaluated on every
	-- refresh (dynamic surfaces: tables whose rows churn/reorder). ABSENT =
	-- auto-derive: from mounted input contributions when any provides focusGroups,
	-- else from the mounted LAYOUT structure when it has a horizontal container or
	-- Grid with >=2 focusables (HStack row -> horizontal group; Grid -> per-row 2D
	-- groups), else the flat ring (ADR-0013 WP-1). `false` = force the flat ring,
	-- ignoring both (a legacy flat-list consumer opting out of auto-grouping).
	navigationGroups: ({ focus_graph.NavigationGroup } | (rootNode: any) -> { focus_graph.NavigationGroup } | boolean)?,
	-- presentModal only (ADR-0013 WP-2): while this modal is on top, a pointer/
	-- touch tap whose path is NOT owned by the modal's blueprint dismisses the
	-- modal (platform sheet outside-tap) and never routes to a lower screen.
	-- Default true; set false to restore legacy clickthrough routing. A scrim or
	-- close button living INSIDE the modal blueprint is owned by it and routes
	-- normally, so consumers with an in-blueprint scrim are unaffected.
	outsideTapCancel: boolean?,
	-- what the CANCEL verb (gamepad ButtonB) does to this surface.
	--   "dismiss" (default) — today's contract, unchanged: a modal dismisses, an
	--                         engaged-from-passive surface resigns (ADR-0014).
	--   "none"              — Cancel does nothing to THIS surface. For a
	--                         MANDATORY surface: a modal whose choice has no
	--                         legal "not now" (a role pick that parks the player
	--                         until they choose), where dismiss-on-B would strand
	--                         them behind a decision they never made.
	-- Orthogonal to `outsideTapCancel` (the pointer path) by design: a mandatory
	-- modal sets BOTH. Cancel is still OFFERED to the focused contribution's
	-- `handleCancel` first either way — a control inside the surface keeps its own
	-- cancel (an open popup still closes) — this opt only governs what the
	-- SURFACE does when nothing consumed it. `presenter.dismiss(handle)` and
	-- `presenter.back()` are explicit programmatic calls and are NOT gated by it.
	cancelPolicy: string?, -- "dismiss" | "none"
	-- scrim/catcher appearance (modal-dismissal spec §2.2/§3.1). The presenter
	-- synthesizes a full-viewport catcher beneath the top exclusive surface so
	-- outside taps land on SOMETHING (closes the empty-space gap) and lower
	-- surfaces are blocked. "scrim" (default for modals) dims at the scrimOpacity
	-- token (0.45); "none" is fully transparent but STILL catching (a transient
	-- popover, or an engaged HUD that must keep the world visible — the default
	-- for a passive surface once engaged, §3.6).
	scrim: string?, -- "scrim" | "none"
	-- consume a navigation direction before focus moves (gamepad grab mode:
	-- a grabbed row eats up/down to reorder itself). Return true = consumed.
	onNavigateIntercept: ((direction: string) -> boolean)?,
	-- post-layout geometry hook (§17 Phase 5 keyboard occlusion): called with
	-- the controller's rectOf after the initial render and after every refresh,
	-- so a control can read its own solved rects (a text field feeds its rect
	-- into its keep-visible policy). Generic: never text-specific.
	--
	-- ADDITIVE, not an override (see feedGeometry): passing this does NOT suppress
	-- the contributions' own `syncGeometry`, so a screen may ask where its nodes
	-- landed without silently disabling a composed Table's scroll-into-view.
	onGeometry: ((rectOf: (string) -> any) -> ())?,
	-- keep-visible presentation offset (§17 Phase 5): a Readable<number> the
	-- presenter observes and applies as an upward transform on the screen root
	-- (0 = none). A text field publishes its keyboard-occlusion offset here.
	keepVisibleOffset: any?,
	-- structural transition for the SURFACE itself (ADR-0022 Decision 3):
	-- { enter, exit?, class?, fade? }. The enter runs on the first painted frame;
	-- `dismiss` then defers the teardown until the exit completes or the
	-- coordinator's flat 500 ms cap fires — whichever comes first. The surface
	-- leaves the stack (and its focus scope and input context) IMMEDIATELY either
	-- way: a screen on its way out must never still take input.
	--
	-- A fading form needs a fade GROUP, and a `Screen` is not one — so the
	-- transition targets the root's single `canvasGroup` child when it has one
	-- (`UI.ZStack{ canvasGroup = true }` around the screen's content is the
	-- documented shape), and the root otherwise.
	transition: any?,
	-- presentCritical only
	fallbackScreen: ((err: any) -> any)?,
}

-- presentToast options (ADR-0022 Decision 4; ui-designer spec §3.1)
export type ToastOpts = {
	key: string?, -- same-key supersede ("subject" in the spec)
	priority: number?, -- default 0; higher runs first in the queue
	duration: number?, -- seconds visible, default 4
	readFloor: number?, -- minimum dwell before anything may replace it, default 1.5
	position: string?, -- "top" (default) | "bottom" — the edge it docks to
	transition: any?, -- default: slide in from its own edge, with a fade
	context: any?, -- carried on the toast's dismiss event, untouched
}

-- CLOSED OPTS (constitution §4; ARCH-1). This is the widest opts table in the
-- library — twenty declared fields, most of them booleans and policy strings
-- with silent defaults — so it is the one where an accepted-and-ignored key
-- costs the most: `outsideTapCancle = false` left the modal dismissing on an
-- outside tap with nothing to say about it. Every declared field is legal, and
-- exactly those.
local PRESENT_OPTS_KEYS = specGuard.keySet({
	"cancelPolicy",
	"engineSelectionBridge",
	"fallbackScreen",
	"gameplayGuard",
	"keepVisibleOffset",
	"navigationGroups",
	"onActivate",
	"onAdjust",
	"onFocusNav",
	"onGeometry",
	"onNavigateIntercept",
	"onReorderNav",
	"outsideTapCancel",
	"responder",
	"revealTimeout",
	"revealWhenTextExact",
	"rootPolicy",
	"scrim",
	"sinkNavigation",
	"transition",
})
local TOAST_OPTS_KEYS = specGuard.keySet({
	"context",
	"duration",
	"key",
	"position",
	"priority",
	"readFloor",
	"transition",
})
local PRESENTER_OPTS_KEYS = specGuard.keySet({ "clock", "now" })

local FOCUSABLE: { [string]: boolean } = { Button = true, Toggle = true, TextField = true }

-- B-BTN4: `enabled = false` must be consistent across focus, activation,
-- appearance and semantics. It used to reach only paint and semantics, so a
-- disabled control stayed in focus order and still activated on tap, Return and
-- ButtonA — visible as disabled, fully operable by keyboard and gamepad.
local function isDisabled(node: any): boolean
	return node ~= nil and node.props ~= nil and node.props.enabled == false
end

-- ===== modal outside-tap: two-zone geometry (modal-dismissal spec) ==========
-- Zone A ("no dismiss") is the modal's PAINTED region, never its blueprint-path
-- envelope: an invisible/transparent container that geometrically covers the
-- screen contributes NOTHING (defusing the "fill root swallows every tap"
-- footgun), while a VISIBLE fullscreen panel correctly has no outside. A node is
-- "painted" iff it carries a `surface` fill OR is a content-bearing leaf.
local CONTENT_PAINTED: { [string]: boolean } =
	{ Text = true, Button = true, Toggle = true, TextField = true, Image = true }
-- forgiveness ring = space.l (≈ half the hit floor) and the effective hit floor
-- itself (targetSizes.minimum). Roles, not literals — the boundary mirror of the
-- target-forgiveness logic (spec §3.2).

local function pointInRect(x: number, y: number, r: any): boolean
	return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function inflate(r: any, m: number): any
	return { x = r.x - m, y = r.y - m, w = r.w + 2 * m, h = r.h + 2 * m }
end

-- inflate a rect symmetrically so each axis reaches at least `floor` (the 44px
-- effective hit rect of an edge button that may be smaller than its target)
local function inflateToFloor(r: any, floor: number): any
	local dw = math.max(0, floor - r.w)
	local dh = math.max(0, floor - r.h)
	return { x = r.x - dw / 2, y = r.y - dh / 2, w = r.w + dw, h = r.h + dh }
end

-- is (x,y) inside `subtreeRoot`'s Zone A? = ( outermost painted panel bbox ⊕ 24 )
-- ∪ ( each focusable's 44px hit rect ). Reads SOLVED rects (rectOf), replacing
-- the pure path-prefix test for the dismiss decision. Returns false when nothing
-- is painted (a wholly-invisible surface has no Zone A, so every tap is Zone B).
-- Scoped to any subtree so both a modal (whole root) and a transient popup (its
-- contribution subtree) share one geometry (ADR-0014 two-zone model).
local function zoneAContains(rectOf: (string) -> any, subtreeRoot: any, x: number, y: number, metrics: any): boolean
	local forgiveMargin: number = metrics.space.l
	local hitFloor: number = metrics.targetSizes.minimum
	local bbox: any = nil
	local focusHit = false
	local function consider(node: any)
		local props = node.props
		local painted = (props ~= nil and props.surface ~= nil) or CONTENT_PAINTED[node.class] == true
		if painted then
			local r = rectOf(node.path)
			if r ~= nil then
				if bbox == nil then
					bbox = { x = r.x, y = r.y, w = r.w, h = r.h }
				else
					local bx2 = math.max(bbox.x + bbox.w, r.x + r.w)
					local by2 = math.max(bbox.y + bbox.h, r.y + r.h)
					bbox.x = math.min(bbox.x, r.x)
					bbox.y = math.min(bbox.y, r.y)
					bbox.w = bx2 - bbox.x
					bbox.h = by2 - bbox.y
				end
				if FOCUSABLE[node.class] and not (props ~= nil and props.focusable == false) then
					if pointInRect(x, y, inflateToFloor(r, hitFloor)) then
						focusHit = true
					end
				end
			end
		end
		for _, child in node.children or {} do
			consider(child)
		end
	end
	if subtreeRoot ~= nil then
		consider(subtreeRoot)
	end
	if focusHit then
		return true
	end
	return bbox ~= nil and pointInRect(x, y, inflate(bbox, forgiveMargin))
end

local function modalInZoneA(handle: any, x: number, y: number, metrics: any): boolean
	return zoneAContains(handle.controller.rectOf, handle.root.node, x, y, metrics)
end

-- grips (opt-in focusable pointer zones) sort AFTER the ordinary walk so list
-- navigation lands on content first; they stay reachable past the end
-- (gamepad resize affordance — the virtual cursor ignores MouseIcon)
-- A RETIRING SUBTREE IS NOT INTERACTIVE (ADR-0022 Decision 3). A node whose
-- structural region declared an exit transition stays MOUNTED while it plays that
-- exit — its layout slot holds, its instances stay put — and that is exactly the
-- window in which it must stop being focusable and stop taking taps. Focus landing
-- on a control that is fading out is the defect this guard exists for; every walk
-- over the mounted tree that feeds focus or hit routing prunes at the mark.
local function isRetiring(node: any): boolean
	return node ~= nil and node.retiring == true
end

local function focusWalk(node: any, out: { string }, deferred: { string })
	if isRetiring(node) then
		return
	end
	if node.class == "Grip" then
		if node.props and node.props.focusable == true then
			table.insert(deferred, node.path)
		end
	elseif FOCUSABLE[node.class] and not (node.props and node.props.focusable == false) and not isDisabled(node) then
		table.insert(out, node.path)
	end
	for _, child in node.children do
		focusWalk(child, out, deferred)
	end
end

-- hidden(path) tells focusOrder to skip a path and everything beneath it. It
-- exists for ViewThatFits (A-AL1): a losing candidate stays MOUNTED so a resize
-- re-chooses without rebuilding, which means focus order — not the mount tree —
-- is what has to exclude it. Without this, navigation would land on a control
-- with a zero rect that the player cannot see.
-- is `prefix` a PATH prefix of `path` (segment-aligned, so "/S/Name" prefixes
-- "/S/Name/Field" but not "/S/NameX/...")
local function isPathPrefix(prefix: string, path: string): boolean
	return path == prefix or string.sub(path, 1, #prefix + 1) == prefix .. "/"
end

-- An order entry is a bare path OR the live-predicate form `{ id = path,
-- focusable = () -> boolean }` (ADR-0022 Decision 5). Both have to be filterable,
-- because the hidden rule is about the NODE, not about how it was declared.
local function entryPath(entry: any): string?
	if type(entry) == "string" then
		return entry
	end
	if type(entry) == "table" and type(entry.id) == "string" then
		return entry.id
	end
	return nil
end

local function isHiddenPath(path: string?, hidden: { [string]: boolean }): boolean
	if path == nil then
		return false
	end
	for root in hidden do
		if isPathPrefix(root, path) then
			return true
		end
	end
	return false
end

local function filterHidden(order: { any }, hidden: { [string]: boolean }?): { any }
	if hidden == nil or next(hidden) == nil then
		return order
	end
	local out: { any } = {}
	for _, entry in order do
		if not isHiddenPath(entryPath(entry), hidden) then
			table.insert(out, entry)
		end
	end
	return out
end

-- The SAME exclusion for a GROUPED scope. Every path into a grouped scope —
-- a contribution's `focusGroups`, `autoGroups`, `layoutGroups`, or an explicit
-- `navigationGroups` opt — used to skip this filter entirely, so a losing
-- `ViewThatFits` candidate stayed in the ring: on a wide viewport a pad walked
-- onto the hidden COLUMN candidate's buttons and could not reach the visible ROW
-- at all (found building RascalRally's results CTA band, 2026-07-30). The public
-- contract has always been "losing candidates are excluded from focus order"
-- (docs/reference/api.md § ViewThatFits); this is the grouped half of it.
local function filterGroupsHidden(groups: { any }, hidden: { [string]: boolean }?): { any }
	if groups == nil or hidden == nil or next(hidden) == nil then
		return groups
	end
	local out: { any } = {}
	for _, group in groups do
		if type(group) == "table" and type(group.order) == "table" then
			local filtered = filterHidden(group.order, hidden)
			if #filtered ~= #group.order then
				local copy = table.clone(group)
				copy.order = filtered
				table.insert(out, copy)
				continue
			end
		end
		table.insert(out, group)
	end
	return out
end

local function focusOrder(node: any, out: { string })
	local deferred: { string } = {}
	focusWalk(node, out, deferred)
	for _, path in deferred do
		table.insert(out, path)
	end
end

-- ===== input auto-wiring seam (ADR-0013; ui_todo §0) =======================
-- The presenter walks the MOUNTED tree, discovers each composite's attached
-- input-contribution bundle, and auto-composes navigation groups + Activate
-- dispatch + grab intercept + focus-move reporting + geometry + keep-visible +
-- action-system binding. Every consumer-passed present() opt still overrides
-- its auto counterpart, per-opt (see makeHandle).

type Contribution = { path: string, node: any, bundle: contribution.Bundle }

-- collect contributions in DOCUMENT (pre-order) order
local function collectContributions(rootNode: any): { Contribution }
	local out: { Contribution } = {}
	local function walk(node: any)
		local bundle = contribution.read(node)
		if bundle ~= nil then
			table.insert(out, { path = node.path, node = node, bundle = bundle })
		end
		for _, child in node.children or {} do
			walk(child)
		end
	end
	walk(rootNode)
	return out
end

-- find the mounted node at an exact path (small trees; full DFS)
local function nodeAt(rootNode: any, path: string?): any
	if path == nil then
		return nil
	end
	if rootNode.path == path then
		return rootNode
	end
	for _, child in rootNode.children or {} do
		local found = nodeAt(child, path)
		if found ~= nil then
			return found
		end
	end
	return nil
end

-- is `path` inside a subtree that is playing its exit? (the tap half of the
-- retiring rule above: a fading control must not still activate)
local function pathIsRetiring(rootNode: any, path: string): boolean
	if rootNode == nil then
		return false
	end
	if isRetiring(rootNode) then
		return isPathPrefix(rootNode.path, path)
	end
	for _, child in rootNode.children or {} do
		if pathIsRetiring(child, path) then
			return true
		end
	end
	return false
end

-- contributions whose root path prefixes `path`, longest prefix first
local function contributionsForPath(contributions: { Contribution }, path: string): { Contribution }
	local matches: { Contribution } = {}
	for _, c in contributions do
		if isPathPrefix(c.path, path) then
			table.insert(matches, c)
		end
	end
	table.sort(matches, function(a, b)
		return #a.path > #b.path
	end)
	return matches
end

-- auto NavigationGroups: contributions contribute their groups at their tree
-- position; standalone focusables outside any contribution subtree form flat
-- vertical groups between them (preserving focusOrder order); focusable grips
-- defer last. Re-derived on every refresh (function form).
-- collect focusable paths (excluding grips) under `node`, in document order
-- (hoisted above autoGroups — both derivations share the layout helpers)
local function collectFocusables(node: any, out: { string })
	if node.class == "Grip" or isRetiring(node) then
		return
	end
	if FOCUSABLE[node.class] and not (node.props and node.props.focusable == false) then
		table.insert(out, node.path)
	end
	for _, child in node.children or {} do
		collectFocusables(child, out)
	end
end

local function focusableCount(node: any): number
	local out: { string } = {}
	collectFocusables(node, out)
	return #out
end

-- does this subtree contain an input contribution that declares focus groups?
-- (a layout container must never swallow one — its groups own its focusables)
local function subtreeHasFocusGroups(node: any): boolean
	local bundle = contribution.read(node)
	if bundle ~= nil and bundle.focusGroups ~= nil then
		return true
	end
	for _, child in node.children or {} do
		if subtreeHasFocusGroups(child) then
			return true
		end
	end
	return false
end

-- per-row horizontal groups for a Grid's focusables, linked by up/down exits
-- (grid 2D nav, column-preserving); shared by both group derivations
local function emitGridGroups(node: any, groups: { any })
	local cells: { string } = {}
	collectFocusables(node, cells)
	local colsProp = node.props and node.props.columns
	local cols = if type(colsProp) == "number" and colsProp >= 1 then colsProp else #cells
	local rows: { { string } } = {}
	for i, path in cells do
		local r = math.floor((i - 1) / cols) + 1
		rows[r] = rows[r] or {}
		table.insert(rows[r], path)
	end
	local base = `auto-grid-{node.path}`
	for r = 1, #rows do
		local exit: { [string]: string } = {}
		if rows[r - 1] ~= nil then
			exit.up = `{base}-r{r - 1}`
		end
		if rows[r + 1] ~= nil then
			exit.down = `{base}-r{r + 1}`
		end
		table.insert(groups, {
			name = `{base}-r{r}`,
			axis = "horizontal",
			entry = "nearest",
			containment = true, -- grid: left/right stay in the row; up/down via exits
			exit = exit,
			order = rows[r],
		})
	end
end

local function autoGroups(rootNode: any): { any }
	local groups: { any } = {}
	local pending: { string } = {}
	local grips: { string } = {}
	local flatCount = 0
	local function flush()
		if #pending > 0 then
			flatCount += 1
			table.insert(
				groups,
				{ name = `auto-flat-{flatCount}`, axis = "vertical", entry = "nearest", order = pending }
			)
			pending = {}
		end
	end
	local function walk(node: any)
		if isRetiring(node) then
			return
		end
		local bundle = contribution.read(node)
		if bundle ~= nil and bundle.focusGroups ~= nil then
			-- a contribution owns its own subtree's focus: emit its groups and do
			-- NOT descend (its focusables live inside the groups it declares)
			flush()
			for _, group in bundle.focusGroups(node) do
				table.insert(groups, group)
			end
			return
		end
		-- LAYOUT-AWARE RUNS (director virtual-controller round): an HStack row of
		-- focusables navigates HORIZONTALLY and a Grid navigates as a grid, the
		-- same derivation the no-contribution path has always used. Every
		-- ungrouped run used to become a VERTICAL group, so "right" inside the
		-- hand's card row was orthogonal-dead — the pad could not reach Card B.
		if node.class == "Grid" and focusableCount(node) >= 2 and not subtreeHasFocusGroups(node) then
			flush()
			emitGridGroups(node, groups)
			return
		end
		if node.class == "HStack" and focusableCount(node) >= 2 and not subtreeHasFocusGroups(node) then
			flush()
			local cells: { string } = {}
			collectFocusables(node, cells)
			table.insert(groups, { name = `auto-h-{node.path}`, axis = "horizontal", entry = "nearest", order = cells })
			return
		end
		if node.class == "Grip" then
			if node.props and node.props.focusable == true then
				table.insert(grips, node.path)
			end
		elseif FOCUSABLE[node.class] and not (node.props and node.props.focusable == false) then
			table.insert(pending, node.path)
		end
		for _, child in node.children or {} do
			walk(child)
		end
	end
	walk(rootNode)
	flush()
	if #grips > 0 then
		table.insert(groups, { name = "auto-grips", axis = "vertical", order = grips })
	end
	return groups
end

-- ===== auto navigation groups from LAYOUT STRUCTURE (ADR-0013 WP-1) =========
-- A PLAIN screen (no input contributions) still deserves 2D navigation when its
-- layout says so: an HStack row of focusables is a horizontal group; focusables
-- under a Grid are per-row horizontal groups linked by up/down exits (grid 2D
-- nav, column-preserving); everything else is the vertical document order. This
-- only ENGAGES when the tree actually contains a horizontal container or a Grid
-- with >=2 focusables — otherwise the flat ring stays byte-identical (many tests
-- depend on the flat ring's wrap behavior). Grips keep their deferred-last spot.

-- does the tree contain an HStack or Grid holding >=2 focusables? (the engage
-- gate: only then do we derive groups; else the flat ring is preserved exactly)
local function hasHorizontalStructure(node: any): boolean
	if (node.class == "HStack" or node.class == "Grid") and focusableCount(node) >= 2 then
		return true
	end
	for _, child in node.children or {} do
		if hasHorizontalStructure(child) then
			return true
		end
	end
	return false
end

-- build layout-derived NavigationGroups. Always returns a valid array once the
-- gate has engaged (re-run on every refresh); a plain vertical run collapses to
-- a single vertical group, an HStack to a horizontal group, a Grid to per-row
-- horizontal groups with declared up/down exits (entry="nearest" preserves the
-- column) contained so left/right cannot wrap across rows.
local function layoutGroups(rootNode: any): { any }
	local groups: { any } = {}
	local pending: { string } = {}
	local grips: { string } = {}
	local vCount = 0
	local function flushVertical()
		if #pending > 0 then
			vCount += 1
			table.insert(groups, { name = `auto-v-{vCount}`, axis = "vertical", entry = "nearest", order = pending })
			pending = {}
		end
	end
	local function walk(node: any)
		if isRetiring(node) then
			return
		end
		if node.class == "Grip" then
			if node.props and node.props.focusable == true then
				table.insert(grips, node.path)
			end
			return
		end
		if node.class == "Grid" and focusableCount(node) >= 2 then
			flushVertical()
			emitGridGroups(node, groups)
			return -- focusables consumed by the grid block
		end
		if node.class == "HStack" and focusableCount(node) >= 2 then
			flushVertical()
			local cells: { string } = {}
			collectFocusables(node, cells)
			-- no containment: up/down fall through to the adjacent stacked group
			-- (stacked HStacks read as a loose 2D board — column-preserving via
			-- entry="nearest"); horizontal moves stay within the row
			table.insert(groups, { name = `auto-h-{node.path}`, axis = "horizontal", entry = "nearest", order = cells })
			return
		end
		if FOCUSABLE[node.class] and not (node.props and node.props.focusable == false) then
			table.insert(pending, node.path)
		end
		for _, child in node.children or {} do
			walk(child)
		end
	end
	walk(rootNode)
	flushVertical()
	if #grips > 0 then
		table.insert(groups, { name = "auto-grips", axis = "vertical", order = grips })
	end
	return groups
end

-- Activate dispatch when the consumer passed NO opts.onActivate: (1) a
-- props.onActivate on the node; (2) a Toggle whose value is a settable signal
-- flips; (3) the longest-prefix contribution whose handleActivate consumes it;
-- (4) no-op. When opts.onActivate IS present it wins outright (override).
local function activateEffect(handle: any, node: any, path: string?, meta: any?)
	if handle.onActivate ~= nil then
		handle.onActivate(path, meta) -- consumer override
		return
	end
	if path == nil then
		return
	end
	-- (1) a leaf that declares its own effect
	if node ~= nil and node.props ~= nil and type(node.props.onActivate) == "function" then
		node.props.onActivate(path, meta)
		return
	end
	-- (2) Toggle auto-flip (contract.luau §Toggle: "Activate flips value")
	if node ~= nil and node.class == "Toggle" and node.dynamicProps ~= nil then
		local value = node.dynamicProps.value
		if type(value) == "table" and (value :: any).kind == "signal" then
			value:set(not value:get())
			return
		end
	end
	-- (3) longest-prefix contribution dispatch
	for _, c in contributionsForPath(handle.contributions, path) do
		if c.bundle.handleActivate ~= nil and c.bundle.handleActivate(path, meta) then
			return
		end
	end
	-- (4) no-op
end

-- Activate dispatch + the semantic `activate` event, which fires on the CAUSAL
-- FRAME (this one) and exactly once per press, AFTER the effect — so a subscriber
-- that reads the resulting state sees the state the press produced.
--
-- DISABLED FIRST (B-BTN4; verifier finding V12). This gate used to sit AFTER the
-- consumer override, so a screen presented with `opts.onActivate` — the gallery
-- client's own integration and the common game pattern — still activated a
-- disabled control. `enabled = false` has to mean disabled on every path,
-- including the one that overrides everything else, and a disabled control emits
-- no event either: nothing happened.
local function dispatchActivate(handle: any, path: string?, meta: any?)
	local node = if path ~= nil then nodeAt(handle.root.node, path) else nil
	if isDisabled(node) then
		return true -- consumes the verb and does nothing
	end
	activateEffect(handle, node, path, meta)
	if path ~= nil and handle.emitFeedback ~= nil then
		handle.emitFeedback({ type = "activate", path = path, surface = handle, context = meta })
	end
	return nil
end

-- THE FIVE-LAYER SURFACE ORDER (ui-designer spec §6.3), encoded here because this
-- is where surface z is decided. BANDS, not one running counter: a toast has to
-- sit above every base screen and below every modal regardless of the order they
-- were presented in, which a single monotonic counter cannot express. Within a
-- band, creation order still decides (each surface takes the next +100 step), so
-- ~100 live surfaces per band before two would tie — far past anything real.
--
-- `dragProxy` has no consumer in this package: the drag proxy is P4's, and the
-- constant lives here so its layer is a decision on the record rather than a
-- number chosen at the proxy's call site.
local SURFACE_LAYER = table.freeze({
	base = 10000,
	toast = 20000,
	dragProxy = 30000,
	modal = 40000,
})
presenter.SURFACE_LAYER = SURFACE_LAYER

export type PresenterOpts = {
	-- the motion clock every transition and the toast schedule ride. Supply one to
	-- share it with the rest of the application (the client binds it to
	-- RunService.PreRender); absent, the presenter builds its own and `tick`
	-- steps it.
	clock: any?,
	now: (() -> number)?,
}

function presenter.new(core: any, env: any, adapter: any, actionSystem: any, opts: PresenterOpts?)
	specGuard.assertKnownKeys("newPresenter", opts, PRESENTER_OPTS_KEYS, "opts")
	local self = {}
	local graph = focus_graph.new(core)
	local stack: { any } = {} -- presented handles, base first
	self.focus = graph
	local presenterOpts: PresenterOpts = opts or {}
	local nowFn = presenterOpts.now or os.clock

	-- ===== the semantic feedback seam (ADR-0022 Decision 7; row SF-F1) =======
	-- ONE bus per presenter. `presenter.onFeedback` is the primary seam (every
	-- surface, one subscription — a game maps events to sound/haptics in one
	-- place); `handle.onFeedback` is the same bus filtered to that surface.
	-- LuauUI plays nothing.
	local bus = feedbackLib.new()

	local function emitFeedback(event: any)
		bus.emit(event)
	end

	-- THE REGISTRATION POINT FOR SESSION EVENTS (ADR-0022 Decision 7). P4's drag
	-- session emits `commit` / `land` / `reject` / `cancel` / `pickup` through
	-- exactly this call, so every semantic event a game hears — control, motion,
	-- toast, session — arrives on one bus with one taxonomy.
	self.emitFeedback = emitFeedback
	self.onFeedback = bus.subscribe
	self.feedbackTypes = feedbackLib.TYPES
	-- the documented five-band paint order, reachable from the INSTANCE the
	-- public API hands out (P5-F3: the module-table copy was unreachable through
	-- `LuauUI.newPresenter`)
	self.SURFACE_LAYER = SURFACE_LAYER

	-- subscribers to "a modal took the screen" (disposition F7; see presentModal)
	local modalWatchers: { (handle: any) -> () } = {}

	-- ===== the motion clock (ADR-0022 Decision 1) ============================
	-- One clock for every surface transition and the toast schedule. A clock at
	-- rest costs nothing, so building it eagerly costs a table; `self.tick(dt)`
	-- steps it (the client binds that to RunService.PreRender).
	local motionPolicy: any = nil
	do
		local ok, readable = pcall(function()
			return env:get("motionPolicy")
		end)
		if ok then
			motionPolicy = readable
		end
	end
	local motionClock = presenterOpts.clock or motionClockLib.new(core, { motionPolicy = motionPolicy, now = nowFn })
	self.motionClock = motionClock
	local lastTick = nowFn()
	-- per-frame work registered through self.onTick (autoscroll steppers, fixture
	-- probes) — run inside self.tick, after the motion step
	local tickHooks: { (dt: number) -> () } = {}

	-- the live metric authority (ADR-0019 §2). Read per use, never captured: a
	-- theme commit must move the dismiss geometry in the same frame it moves the
	-- solved rects those decisions are taken against.
	local function metricsNow(): any
		local m = env:get("themeMetrics"):get()
		return if type(m) == "table" and type(m.targetSizes) == "table" then m else themeSnapshot.neutral()
	end

	-- ===== responder priority bands (ADR-0014; research conclusion 3) ========
	-- Base screens stay at 1500 (above the ~1000 avatar default, below the
	-- doc-sanctioned gameplay sink at 2000, so a passive/plain screen never
	-- suppresses movement). The ENGAGED-EXCLUSIVE band starts at 3000 —
	-- mirroring ContextActionPriority.High and sitting STRICTLY above the
	-- gameplay sink at 2000 (moved up from the previous 2000 base, which would
	-- have TIED a game's own PlayContext with undocumented tie-break). An
	-- engaged-from-passive surface takes the band base (3000); modals stack
	-- +500 per depth above it.
	local BASE_SCREEN_PRIORITY = 1500
	local ENGAGED_BASE_PRIORITY = 3000

	local function topModalPriority(): number
		local top = ENGAGED_BASE_PRIORITY
		for _, handle in stack do
			if handle.kind == "modal" then
				top += 500
			end
		end
		return top
	end

	-- presenter-level readable: true while ANY presented surface is exclusive
	-- (a modal, or an engaged-from-passive surface — both sink, becoming first
	-- responder over gameplay). A client adapter observes this to hide the touch
	-- controls while an exclusive surface is up (src/client/responder_effects).
	local exclusive = core:signal(false)
	self.exclusiveSurfaceActive = exclusive
	local function refreshExclusive()
		local anyExclusive = false
		for _, handle in stack do
			if handle.kind == "modal" or (handle.isPassive and handle.responder:get() == "engaged") then
				anyExclusive = true
				break
			end
		end
		exclusive:set(anyExclusive)
	end

	local handleByPath: ((string) -> any)? = nil

	-- one shared observer drives focus visuals across all presented handles
	local function syncFocusVisuals(path: string?)
		-- THE RING IS A NAVIGATION ANSWER, NOT A FOCUS ANSWER (DB-3(b)): a
		-- pointer/touch-driven focus move tracks focus without drawing it.
		local ringVisible = graph.focusVisible:get() ~= false
		for _, handle in stack do
			local rootPath = "/" .. (handle.blueprint.id or "")
			local owns = path ~= nil and string.sub(path, 1, #rootPath) == rootPath
			handle.controller.setFocusPath(if owns then path else nil, ringVisible)
			-- focus-gated Adjust bindings (matrix §B-Table): bind/unbind as focus
			-- enters/leaves a declared adjust target so gameplay keys are never
			-- shadowed while focus is elsewhere
			if handle.syncAdjustBindings ~= nil then
				handle.syncAdjustBindings(if owns then path else nil)
			end
			-- ARMED FOLLOWS FOCUS (director virtual-controller round): while a
			-- session is armed, every focus move IS the aim — the verdict paints
			-- on the row you are standing on and the ghost rides along (RR
			-- SponsorGesture §3: ghost-follows-focus). Without this, navigation
			-- moved the ring but the session kept aiming at the hand, so a commit
			-- landed where the pickup began.
			if owns then
				local reg = if handle.controller.peekDragRegistry ~= nil
					then handle.controller.peekDragRegistry()
					else nil
				if reg ~= nil and reg.mode ~= nil and reg.mode() == "armed" then
					reg.armTo(path)
				end
			end
		end
	end
	core:observe(graph.focused, syncFocusVisuals)
	-- ...and on the ORIGIN flipping under a standing focus: the first arrow press
	-- after a tap must bring the ring back onto the node the finger left it on,
	-- without waiting for focus to move somewhere else.
	core:observe(graph.focusVisible, function()
		syncFocusVisuals(graph.focused:get())
	end)

	-- cross-surface z: a monotonic layer per presented surface (base first, each
	-- later surface above). Deterministic and creation-ordered; the synthesized
	-- scrim sits just BELOW its owner (spec §2.2).
	local displayLayer = 0

	-- ===== synthesized scrim / catcher (modal-dismissal spec §2.2/§3.1) ========
	-- The presenter mounts ONE full-viewport catcher beneath the top EXCLUSIVE
	-- surface (a modal, or an engaged-from-passive surface). It closes the
	-- Drive-F1 empty-space gap (every tap now hits something), is the modal
	-- barrier (blocks lower surfaces), and doubles as the "region B exists"
	-- affordance. It is presenter-private: NOT in `stack`, NOT focusable, NOT in
	-- any focus scope, on a path outside every blueprint root ("/__scrim__/...").
	local scrim: any = nil -- { scope, controller, path, owner, mode }

	-- one non-destructive outcome for outside-tap, Cancel (B), and Close (spec
	-- §2.3): a modal dismisses (or SWALLOWS if it declined outside-dismiss — a
	-- true barrier, never a clickthrough); an engaged-passive surface resigns.
	local function applyOutsideOutcome(candidate: any, engagedPassive: boolean)
		if candidate.kind == "modal" then
			if candidate.outsideTapCancel then
				self.dismiss(candidate)
			end
			-- outsideTapCancel=false: swallow (barrier), no dismiss, no clickthrough
		elseif engagedPassive then
			candidate.resign() -- back to passive (ADR-0014), not disposal
		end
	end

	local function currentExclusive(): any?
		for i = #stack, 1, -1 do
			local h = stack[i]
			if h.kind == "modal" or (h.isPassive and h.responder:get() == "engaged") then
				return h
			end
		end
		return nil
	end

	local function disposeScrim()
		if scrim ~= nil then
			scrim.controller.dispose()
			scrim.scope:dispose()
			scrim = nil
		end
	end

	-- a scrim tap: Zone A (panel + ring + button hit rects) does nothing (benign
	-- near-miss); Zone B resolves the one non-destructive outcome.
	local function onScrimInteraction(meta: any)
		local owner = if scrim ~= nil then scrim.owner else nil
		if owner == nil then
			return
		end
		local x = if type(meta) == "table" then meta.x else nil
		local y = if type(meta) == "table" then meta.y else nil
		if x ~= nil and y ~= nil and modalInZoneA(owner, x, y, metricsNow()) then
			return -- Zone A: forgiveness / a tap on the painted panel itself
		end
		applyOutsideOutcome(owner, owner.isPassive and owner.responder:get() == "engaged")
	end

	-- mount the catcher beneath `owner`. mode "scrim" = dim at scrimOpacity
	-- (modals); "none" = transparent but still catching (engaged HUDs, §3.6).
	local function mountScrim(owner: any, mode: string): any
		local catcher: { [string]: any } = {
			id = "catcher",
			label = "",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			focusable = false, -- never in the focus walk / navigation
		}
		-- "scrim" DIMS at scrimOpacity; "plain" is the suppressed surface — no
		-- fill, no interactive tag, no corner, no stroke. Before this the "none"
		-- mode declared NO surface at all, and a Button with no surface still
		-- classifies as `control`, so the invisible catcher wore the installed
		-- package's SOLID control colour across the whole viewport and hid the
		-- screen it was guarding. Both suppressed values are already what
		-- `sheet_model.classifyTags` treats as paint-free (`suppressed`).
		catcher.surface = if mode ~= "none" then "scrim" else "plain"
		-- NOT A DECORATION SURFACE (ADR-0020 R9 / chrome_slots.NO_SLOT).
		--
		-- The catcher is a full-viewport Button whose entire job is to be
		-- INVISIBLE and swallow a tap. Nothing generic can tell it apart from a
		-- real button: `CONTROL_CLASSES` sees a Button and classifies it as the
		-- `control` slot, so every image-driven package painted its button plate
		-- over the whole screen and the surface beneath vanished. Live-found under
		-- the P5 reference packages (rich-skinning-v2), and it is the same defect
		-- class the Slider's accent fill needed the hint for.
		--
		-- The dimming case is unaffected either way: `surface = "scrim"` is
		-- suppressed native paint, and this hint says the node is not a skin
		-- target in EITHER mode.
		local catcherBlueprint = chrome_slots.attachHint(blueprintLib.Button(catcher), { slot = chrome_slots.NO_SLOT })
		local bp = blueprintLib.Screen({ id = "__scrim__", children = { catcherBlueprint } })
		local sc = core:scope("present-scrim")
		local root = mountLib.mount(core, bp, { scope = sc:child("mount") })
		local controller = renderer.attach(core, root, env, adapter, {
			-- edge-to-edge: the dim/barrier covers the whole viewport (incl. insets)
			rootPolicy = "edgeToEdge",
			onNodeTap = function(_path: string, meta: any?)
				onScrimInteraction(meta)
			end,
		})
		controller.initialRender()
		if controller.setDisplayOrder ~= nil then
			controller.setDisplayOrder(owner.displayOrder - 50)
		end
		return {
			scope = sc,
			controller = controller,
			root = root,
			path = "/__scrim__/catcher",
			owner = owner,
			mode = mode,
		}
	end

	-- keep exactly ONE scrim, beneath the current top exclusive surface. Only the
	-- top modal's scrim is live (spec §3.5): as the top changes, the scrim moves.
	-- ===== transient-popup catcher (matrix section B PopupButton; outsideDismiss)
	-- A PLAIN base screen with an OPEN PopupButton (a contribution whose
	-- outsideDismiss is active) is NOT exclusive, so the modal scrim above never
	-- covers it. The presenter synthesizes a SEPARATE transparent full-viewport
	-- catcher beneath that screen so a tap on EMPTY space dismisses the popup
	-- (Zone-A geometry over the contribution's own subtree). A tap on a rendered
	-- sibling above the catcher is handled in onNodeTap (path-outside test). A
	-- real modal/engaged surface SUPPRESSES this catcher (currentExclusive gate),
	-- so the two mechanisms never stack.
	local popupCatcher: any = nil -- { scope, controller, root, path, owner, contribPath, dismiss }

	local function currentPopupOwner(): (any?, any?)
		if currentExclusive() ~= nil then
			return nil, nil -- a modal / engaged-passive surface owns outside-tap
		end
		for i = #stack, 1, -1 do
			local h = stack[i]
			for _, c in h.contributions or {} do
				local od = c.bundle.outsideDismiss
				if od ~= nil and od.active ~= nil and od.active:get() == true then
					return h, c
				end
			end
		end
		return nil, nil
	end

	local function disposePopupCatcher()
		if popupCatcher ~= nil then
			popupCatcher.controller.dispose()
			popupCatcher.scope:dispose()
			popupCatcher = nil
		end
	end

	-- a catcher tap: Zone A (the popup's painted panel + ring + hit rects) does
	-- nothing (a benign near-miss / a tap on the popup itself); Zone B dismisses.
	local function onPopupCatcherTap(meta: any)
		if popupCatcher == nil then
			return
		end
		local owner = popupCatcher.owner
		local x = if type(meta) == "table" then meta.x else nil
		local y = if type(meta) == "table" then meta.y else nil
		local sub = nodeAt(owner.root.node, popupCatcher.contribPath)
		if x ~= nil and y ~= nil and zoneAContains(owner.controller.rectOf, sub, x, y, metricsNow()) then
			return -- Zone A
		end
		popupCatcher.dismiss()
	end

	local function mountPopupCatcher(owner: any, contribPath: string, dismiss: () -> ()): any
		local catcher: { [string]: any } = {
			id = "catcher",
			label = "",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			focusable = false, -- transparent, never focusable / in navigation
		}
		local bp = blueprintLib.Screen({ id = "__popupcatcher__", children = { blueprintLib.Button(catcher) } })
		local sc = core:scope("present-popup-catcher")
		local root = mountLib.mount(core, bp, { scope = sc:child("mount") })
		local controller = renderer.attach(core, root, env, adapter, {
			rootPolicy = "edgeToEdge",
			onNodeTap = function(_path: string, meta: any?)
				onPopupCatcherTap(meta)
			end,
		})
		controller.initialRender()
		if controller.setDisplayOrder ~= nil then
			controller.setDisplayOrder(owner.displayOrder - 50)
		end
		return {
			scope = sc,
			controller = controller,
			root = root,
			path = "/__popupcatcher__/catcher",
			owner = owner,
			contribPath = contribPath,
			dismiss = dismiss,
		}
	end

	function self.syncPopupCatcher()
		local owner, c = currentPopupOwner()
		if owner == nil or c == nil then
			disposePopupCatcher()
			return
		end
		if popupCatcher ~= nil and popupCatcher.owner == owner and popupCatcher.contribPath == c.path then
			return
		end
		disposePopupCatcher()
		popupCatcher = mountPopupCatcher(owner, c.path, c.bundle.outsideDismiss.dismiss)
	end
	function self.topPopupCatcherPath(): string?
		return if popupCatcher ~= nil then popupCatcher.path else nil
	end

	local function syncScrim()
		local topEx = currentExclusive()
		if topEx == nil then
			disposeScrim()
			self.syncPopupCatcher() -- no exclusive surface: a base popup may want a catcher
			return
		end
		local mode = topEx.scrimMode
		if scrim ~= nil and scrim.owner == topEx and scrim.mode == mode then
			self.syncPopupCatcher() -- an exclusive surface suppresses the popup catcher
			return
		end
		disposeScrim()
		scrim = mountScrim(topEx, mode)
		self.syncPopupCatcher()
	end
	function self.topScrimPath(): string?
		return if scrim ~= nil then scrim.path else nil
	end

	-- no-pop text gate (text-measurement milestone). A gated surface stays
	-- hidden until its renderer reports no outstanding premeasurement round,
	-- OR until its deadline passes — whichever comes first. The deadline is not
	-- optional: an adapter that never answers must not be able to hide a game's
	-- UI permanently.
	local function syncTextReveal(handle: any)
		if not handle.textRevealPending then
			return
		end
		local pending = handle.controller.textPending ~= nil and handle.controller.textPending()
		if pending and os.clock() < handle.textRevealDeadline then
			return
		end
		handle.textRevealPending = false
		handle.textRevealedExact = not pending
		handle.controller.setRootVisible(true)
	end

	-- ===== DRAG-PROXY HOST (ADR-0022 Decision 5; ui-designer §5.3/§6.3) ======
	--
	-- The ghost layer. PRESENTER-PRIVATE exactly like the toast layer: not in
	-- `stack`, no focus scope, no input context, no tap handler — a surface with
	-- nothing to intercept input with. The drag registry drives it through the
	-- three-verb contract (`show`/`transform`/`hide`); the registry owns 1:1
	-- tracking, pickup scale and flights, this host owns pixels and the layer
	-- slot (above toasts, below modals — SURFACE_LAYER.dragProxy). Proxy
	-- blueprints are display composites by contract: nothing here wires a tap,
	-- and an interactive proxy is the caller doing it wrong.
	local dragProxyState: any = nil
	local function dragProxyHide(token: any)
		if dragProxyState == nil or (token ~= nil and dragProxyState.token ~= token) then
			return
		end
		local state = dragProxyState
		dragProxyState = nil
		state.controller.dispose()
		state.scope:dispose()
	end
	local dragProxyHost = {
		show = function(info: any): any
			dragProxyHide(nil) -- one live session, one ghost: a second show replaces
			local rect = (type(info) == "table" and info.rect) or { x = 0, y = 0, w = 44, h = 44 }
			local content = (type(info) == "table" and info.blueprint)
			if content == nil then
				-- the default ghost: a themed plate the size of the grab rect. Styling
				-- rides the NORMALIZING modifiers, never raw prop tables — the same
				-- rule authored screens follow.
				content = blueprintLib.Box({
					id = "Ghost",
					surface = "control",
					width = { type = "fixed", px = rect.w },
					height = { type = "fixed", px = rect.h },
				})
				content = blueprintLib.corners(content, "control")
				content = blueprintLib.shadow(content, "overlay")
			end
			-- the slot pins at the GRAB rect origin; `transform` drives deltas from
			-- there through the presentation channel, so the ghost never touches
			-- solver geometry mid-drag (Decision 2)
			local slot = blueprintLib.ZStack({
				id = "Slot",
				offsetX = rect.x,
				offsetY = rect.y,
				width = { type = "fixed", px = rect.w },
				height = { type = "fixed", px = rect.h },
				children = { content },
			})
			local bp = blueprintLib.Screen({
				id = "__dragproxy__",
				children = {
					blueprintLib.Anchor({
						id = "Layer",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = { slot },
					}),
				},
			})
			local sc = core:scope("present-dragproxy")
			local root = mountLib.mount(core, bp, { scope = sc:child("mount") })
			-- edgeToEdge, NOT coreSafeContent (director fix round, the "odd offset"):
			-- the registry hands this host WINDOW-space coordinates (screenRectOf
			-- includes the core inset), so the ghost surface's own origin must BE the
			-- window origin. Under coreSafeContent the root sat below the inset and
			-- the ghost rendered exactly GuiInset pixels below the finger — invisible
			-- headlessly, where insets are zero.
			local ctrl = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
			ctrl.initialRender()
			if ctrl.setDisplayOrder ~= nil then
				ctrl.setDisplayOrder(SURFACE_LAYER.dragProxy)
			end
			dragProxyState = {
				scope = sc,
				controller = ctrl,
				origin = { x = rect.x, y = rect.y },
				token = {},
			}
			return dragProxyState.token
		end,
		transform = function(token: any, t: any)
			if dragProxyState == nil or dragProxyState.token ~= token then
				return
			end
			dragProxyState.controller.setPresentationTransform("/__dragproxy__/Layer/Slot", {
				x = (t.x or 0) - dragProxyState.origin.x,
				y = (t.y or 0) - dragProxyState.origin.y,
				scale = t.scale,
			})
		end,
		hide = dragProxyHide,
	}

	local function makeHandle(blueprint: any, opts: any, kind: string)
		-- an unknown cancelPolicy is refused LOUDLY, the same way an unknown
		-- rootPolicy is (renderer.attach): a typo that silently kept the default
		-- would read as "the framework ignored my mandatory modal".
		local cancelPolicy = (opts and opts.cancelPolicy) or "dismiss"
		if cancelPolicy ~= "dismiss" and cancelPolicy ~= "none" then
			error(`LuauUI presenter: unknown cancelPolicy '{tostring(cancelPolicy)}'. Valid: dismiss, none.`, 0)
		end
		-- ...and so do the other two string enums (F-15). They used to be compared
		-- by equality and passed through raw, which is the exact failure the rule
		-- above refuses: `responder = "Passive"` silently presented an ENGAGED
		-- surface that sank nothing it was supposed to sink, and `scrim = "None"`
		-- silently DIMMED the screen. Absent stays legal — each has a default.
		local responderOpt = if opts ~= nil then opts.responder else nil
		if responderOpt ~= nil and responderOpt ~= "passive" then
			error(
				`LuauUI presenter: unknown responder '{tostring(responderOpt)}'. Valid: passive (omit for engaged).`,
				0
			)
		end
		local scrimOpt = if opts ~= nil then opts.scrim else nil
		if scrimOpt ~= nil and scrimOpt ~= "scrim" and scrimOpt ~= "none" then
			error(`LuauUI presenter: unknown scrim '{tostring(scrimOpt)}'. Valid: scrim, none.`, 0)
		end
		local scope = core:scope(`present-{kind}-{blueprint.id or "screen"}`)
		-- STRUCTURAL TRANSITIONS (ADR-0022 Decision 3). Every surface gets a
		-- coordinator: it costs a table, builds a spring only when a region actually
		-- declares a transition, and it is the only thing that makes `UI.When
		-- { transition = … }` mean anything on this screen. `surfaceRef` is filled in
		-- once the handle exists, so an `arrive` fired at mount already names its
		-- surface.
		local surfaceRef: any = nil
		local coordinator = transitionsLib.new({
			core = core,
			clock = motionClock,
			metrics = metricsNow,
			feedback = function(event: any)
				event.surface = surfaceRef
				emitFeedback(event)
			end,
		})
		local root = mountLib.mount(core, blueprint, { scope = scope:child("mount"), transitions = coordinator })
		local controller = renderer.attach(core, root, env, adapter, {
			rootPolicy = (opts and opts.rootPolicy) or "coreSafeContent",
			-- engine-selection bridge (native-substrate NS-A12, corrections §11):
			-- OPT-IN and modal/exclusive-only. Passive/gameplay surfaces never
			-- set it, so GuiService.SelectedObject stays nil for them (NS-A11).
			-- LuauUI's logical focus graph remains the sole authority; the
			-- bridge is a render output that clears on teardown. Physical-pad
			-- non-interference proof is ledger row NS-P1; until it closes this
			-- stays an experiment, not a contract.
			engineSelectionBridge = (opts and opts.engineSelectionBridge) == true and kind ~= "screen",
			-- pointer taps activate directly (no focus round-trip): same
			-- semantic command path as the Activate action
			onNodeTap = function(path: string, meta: any?)
				-- a control inside a subtree that is playing its EXIT is not there any
				-- more as far as interaction is concerned: it still paints, so it can
				-- still be pressed, and a press on something on its way out is never
				-- what the player meant (ADR-0022 Decision 3)
				if pathIsRetiring(root.node, path) then
					return
				end
				-- outside-tap policy is owned by the topmost EXCLUSIVE surface: a
				-- modal (ADR-0013 WP-2) OR an engaged-from-passive surface (ADR-0014).
				-- A tap whose path is NOT owned by that surface dismisses/resigns it
				-- (platform sheet dismiss) and never clicks through to a lower handle.
				for i = #stack, 1, -1 do
					local candidate = stack[i]
					local engagedPassive = candidate.isPassive and candidate.responder:get() == "engaged"
					if candidate.kind == "modal" or engagedPassive then
						local surfaceRoot = "/" .. (candidate.blueprint.id or "")
						if not isPathPrefix(surfaceRoot, path) then
							-- outside taps are ALWAYS consumed now (the modal is a barrier):
							-- dismiss/resign, or SWALLOW when the modal declined outside-
							-- dismiss — never a clickthrough to a lower surface (modal-
							-- dismissal spec §3.4, changed from the pre-spec fall-through).
							-- The scrim catcher makes this correct by construction; this
							-- fast-path handles a tap on a rendered lower node.
							applyOutsideOutcome(candidate, engagedPassive)
							return
						end
						break -- only the topmost exclusive surface owns the policy
					end
				end
				local h = handleByPath and handleByPath(path)
				-- transient-popup outside-tap (matrix §B PopupButton; outsideDismiss):
				-- when a base-screen contribution is dismissable-on-outside-tap and the
				-- tapped node is OUTSIDE its subtree, dismiss it (non-destructive) and
				-- swallow the tap. Handles a tap on a rendered sibling ABOVE the
				-- synthesized catcher; taps on empty space route through the catcher.
				-- An exclusive surface above already returned (it owns the policy), so
				-- a real modal never lets a lower popup steal its outside-tap.
				if h ~= nil then
					for _, c in h.contributions or {} do
						local od = c.bundle.outsideDismiss
						if
							od ~= nil
							and od.active ~= nil
							and od.active:get() == true
							and not isPathPrefix(c.path, path)
						then
							od.dismiss()
							return
						end
					end
				end
				-- a tap on a focusable INSIDE a passive (not-yet-engaged) surface
				-- engages it BEFORE the activate routes (director 2026-07-21): the
				-- surface becomes first responder for that gesture, then dispatches
				if h ~= nil and h.isPassive and h.responder:get() == "passive" then
					h.engage()
				end
				-- Apple model: clicking a focusable moves keyboard focus there
				-- BEFORE the activate routes (director round 2) — navigation
				-- then continues from the clicked control. The ORIGIN is set
				-- first, so the move tracks focus without painting a ring the
				-- finger never asked for (DB-3(b)); the next Navigate restores it.
				graph.setFocusOrigin("pointer")
				graph.focusOn(path)
				if h ~= nil then
					dispatchActivate(h, path, meta)
				end
			end,
		})
		controller.initialRender()
		-- the coordinator's writes need handles, which only exist once the tree has
		-- rendered; binding flushes whatever a mount-time enter already seeded, so
		-- the first painted frame is the seeded one rather than a frame at rest
		-- followed by a jump
		coordinator.bindController(controller)

		-- discover the mounted input contributions (ADR-0013) in document order;
		-- the presenter auto-composes each screen's four-input story from them,
		-- with every consumer opt overriding its auto counterpart per-opt (below)
		--
		-- THIS ARRAY IS LIVE, AND IS UPDATED IN PLACE BY `syncContributions` ON
		-- EVERY REFRESH (device round 1, DB-4 — the crown bug). It used to be a
		-- ONE-SHOT walk, which silently assumed every contributing control is
		-- mounted at present() time. `UI.When` exists precisely so that is not
		-- true: RascalRally's whole Sponsor HUD lives under one region gated on
		-- "am I a sponsor", the presenter is constructed at client startup while
		-- the player is still a racer, and so on a real device NOTHING the racer
		-- list contributes was ever wired — no `handleActivate` (a tap on a row
		-- with a card held did nothing at all), no `handleCancel`, no declared
		-- focus groups, no `bindController`. Every headless row passed because
		-- the test rig seats the sponsor BEFORE constructing the presenter.
		-- The focus MAP was already re-derived per refresh for exactly this
		-- reason (see `refresh`, "phase-1 verifier finding F1"); this is the same
		-- rule applied to the wiring the map is useless without.
		local contributions = collectContributions(root.node)
		-- DRAG-TO-EDGE AUTOSCROLL RIDES THE PRESENTER CLOCK (device report
		-- 2026-07-29). A finger parked in a scroller's edge band emits no further
		-- pointer events, so nothing driven by input alone can ever start the
		-- scroll — it needs frames. The policy is the ScrollView's (see the
		-- `autoscroll` prop) and the controller owns the host chain; this is only
		-- the clock, on the one sanctioned frame source, quarantined like every
		-- other tick hook. Inert while no drag is announced.
		if type(controller.stepAutoscroll) == "function" then
			scope:own(self.onTick(function(dt: number)
				controller.stepAutoscroll(dt)
			end))
		end
		-- ONE-TIME wiring per DISCOVERED bundle, run at present time for what is
		-- mounted now and again from `syncContributions` for anything a keyed
		-- region mounts later. Keyed on the bundle table's identity, so a
		-- surviving contribution is never bound twice and a control that
		-- unmounts and remounts (same bundle, same closures) is not re-bound.
		local boundBundles: { [any]: boolean } = {}
		local function bindContribution(c: Contribution)
			if boundBundles[c.bundle] then
				return
			end
			boundBundles[c.bundle] = true
			-- always bind the action system into every contribution
			-- (idempotent — e.g. TextInput's edit-mode sink context uses it)
			if c.bundle.bindActionSystem ~= nil then
				c.bundle.bindActionSystem(actionSystem)
			end
			-- hand over the render controller too (B-VAL2): a control that adopts a
			-- native adapter capability (UIDragDetector) reaches it through the
			-- controller, never by fabricating an adapter handle of its own
			if c.bundle.bindController ~= nil then
				c.bundle.bindController(controller)
			end
			-- and the FOCUS GRAPH, for the controls that must MOVE focus rather
			-- than merely follow it (VirtualList's index focus policy: the data
			-- re-sorted under the ring and the control's policy says the ring stays
			-- on the SLOT). Bound here rather than handed over by the consumer, so
			-- there is exactly one focus authority and no consumer-side split brain.
			if c.bundle.bindFocusGraph ~= nil then
				c.bundle.bindFocusGraph(graph)
			end
			-- transient-popup outsideDismiss (matrix §B PopupButton): observe each
			-- active readable so the synthesized catcher is mounted/retired as the
			-- popup opens/closes (see the popup-catcher block above)
			if c.bundle.outsideDismiss ~= nil and c.bundle.outsideDismiss.active ~= nil then
				scope:own(core:observe(c.bundle.outsideDismiss.active, function()
					self.syncPopupCatcher()
				end))
			end
		end
		for _, c in contributions do
			bindContribution(c)
		end

		-- GEOMETRY IS A BROADCAST, NOT A ROUTING DECISION (2026-07-27).
		--
		-- `opts.onGeometry` used to WIN OUTRIGHT — feed the consumer, return, and
		-- skip every contribution's `syncGeometry`. That is the right shape for
		-- `onActivate`, where two handlers for one press is a genuine conflict the
		-- surface owner has to settle. It is the wrong shape here: solved rects are
		-- a notification, nothing arbitrates, and there is no reading under which
		-- one listener's interest cancels another's.
		--
		-- What it actually did was arm a silent trap, and the parity reference had
		-- already written it down as one: passing `onGeometry` on a screen holding a
		-- Table disabled that Table's scroll-into-view, and any TextInput's
		-- keep-visible, with nothing to see. A consumer asking "where did my chip
		-- row land" has no way to know it just switched off a control it composed.
		--
		-- Both are fed now. Every syncGeometry in the framework is idempotent and
		-- equality-guarded (text_input's stores and compares; table's assigns), so a
		-- consumer that already forwards by hand — the shape the audit found in the
		-- tutorial examples — simply feeds the same rects twice and nothing moves.
		local function feedGeometry(rectOf: (string) -> any)
			if opts and opts.onGeometry ~= nil then
				opts.onGeometry(rectOf)
			end
			for _, c in contributions do
				if c.bundle.syncGeometry ~= nil then
					-- the contribution's own MOUNTED NODE rides along: a control that
					-- needs the solved rect of one of its own descendants (a Slider's
					-- track) would otherwise have to guess the path, or wait for an
					-- unrelated callback to hand it one. Second argument, so every
					-- existing one-argument syncGeometry is unaffected.
					c.bundle.syncGeometry(rectOf, c.node)
				end
			end
		end
		feedGeometry(controller.rectOf) -- feed the first solved geometry

		-- navigation groups: an explicit array/function wins; `false` forces the
		-- flat ring; ABSENT auto-derives grouped nav when any contribution
		-- provides focusGroups, else the flat ring stays (today's behavior)
		local ngOpt = opts and opts.navigationGroups
		local navigationGroups: any = nil
		local navigationGroupsFn: any = nil
		if type(ngOpt) == "function" then
			navigationGroupsFn = ngOpt
			navigationGroups = navigationGroupsFn(root.node)
		elseif type(ngOpt) == "table" then
			navigationGroups = ngOpt -- static array
		elseif ngOpt ~= false then
			local hasFocusGroups = false
			for _, c in contributions do
				if c.bundle.focusGroups ~= nil then
					hasFocusGroups = true
					break
				end
			end
			if hasFocusGroups then
				navigationGroupsFn = autoGroups
				navigationGroups = autoGroups(root.node)
			elseif hasHorizontalStructure(root.node) then
				-- no contributions, but the LAYOUT has a horizontal container /
				-- grid: derive 2D navigation from tree structure (ADR-0013 WP-1)
				navigationGroupsFn = layoutGroups
				navigationGroups = layoutGroups(root.node)
			end
		end
		-- RE-DISCOVER THE CONTRIBUTIONS FROM THE LIVE TREE (device round 1, DB-4).
		-- Called at the top of every `refresh`, i.e. after every structural change.
		-- Cheap by construction: one pre-order walk of the same tree `refresh`
		-- already walks for the focus map, and a pass that finds nothing new does
		-- nothing at all. Two things can change:
		--   · a bundle appears (a `UI.When` opened) — it is bound once and starts
		--     receiving Activate/Cancel/geometry from this frame;
		--   · a bundle disappears (the region closed) — it leaves the array, so a
		--     dispatch can never reach a control that is no longer on screen.
		-- A surviving bundle keeps its identity, so nothing is re-bound and no
		-- consumer sees a second `bindController`.
		local autoNavigationGroups = ngOpt == nil
		local function syncContributions()
			local fresh = collectContributions(root.node)
			local changed = #fresh ~= #contributions
			if not changed then
				for i, c in fresh do
					if contributions[i].bundle ~= c.bundle or contributions[i].path ~= c.path then
						changed = true
						break
					end
				end
			end
			if not changed then
				return false
			end
			-- IN PLACE: `feedGeometry`, the Activate dispatch and the popup sweep
			-- all hold this array (directly or through `handle.contributions`), so
			-- replacing the table would leave stale readers behind.
			table.clear(contributions)
			for _, c in fresh do
				table.insert(contributions, c)
				bindContribution(c)
			end
			-- A LATE focusGroups contribution UPGRADES the scope's navigation model
			-- (a screen whose only grouped control mounts later would otherwise keep
			-- the flat/layout-derived ring forever). Only when the consumer left the
			-- choice to us; an explicit `navigationGroups` opt still wins outright.
			if autoNavigationGroups and navigationGroupsFn ~= autoGroups then
				for _, c in contributions do
					if c.bundle.focusGroups ~= nil then
						navigationGroupsFn = autoGroups
						if surfaceRef ~= nil then
							surfaceRef.navigationGroupsFn = autoGroups
						end
						break
					end
				end
			end
			return true
		end

		if navigationGroups ~= nil then
			-- grouped, direction-aware scope (§9.3; verifier F2). Hidden candidates
			-- leave the ring here exactly as they do on the flat path below.
			navigationGroups = filterGroupsHidden(
				navigationGroups,
				if controller.hiddenRoots ~= nil then controller.hiddenRoots() else nil
			)
			graph.pushScope({ name = blueprint.id or kind, trap = kind == "modal", groups = navigationGroups })
		else
			local order: { string } = {}
			focusOrder(root.node, order)
			order = filterHidden(order, if controller.hiddenRoots ~= nil then controller.hiddenRoots() else nil)
			graph.pushScope({ name = blueprint.id or kind, trap = kind == "modal", order = order })
		end

		-- navigation InputContext: modal contexts sit above and SINK so lower
		-- screens never receive navigation while covered (§9.1, spike-true).
		-- Base screens never sink by default (HUD overlays must not eat
		-- gameplay input) but a focus-DRIVEN screen opts in via
		-- opts.sinkNavigation (director hand-test 2026-07-20). NOTE: sinking
		-- is per-CONTEXT, so the opt-in sinks EVERYTHING this context binds —
		-- arrows AND Return/ButtonA/ButtonB (and Adjust keys when wired) —
		-- correct for a full-screen focus-driven list, too broad for a HUD.
		-- Also: base screens share priority 1500, and sink only beats
		-- STRICTLY lower priorities — two focus-driven base screens would
		-- double-deliver on the shared focus graph (modals avoid this via
		-- +500 stacking); present the second one as a modal instead.
		-- Responder mode (ADR-0014). present() default = today's engaged-open
		-- semantics (context enabled, non-sinking — correct for a UI-only place).
		-- opts.responder = "passive" (present() only): the nav context is created
		-- DISABLED so a passive HUD binds nothing gameplay-contended and deviceKey
		-- navigation reaches lower (gameplay) contexts. presentModal is always
		-- engaged-exclusive (sinking). A passive surface becomes first responder
		-- via engage() (tap-in / explicit), raising itself into the engaged band
		-- (3000, strictly above the gameplay sink at 2000) with sink=true, and
		-- drops back on resign() / Cancel / outside-tap.
		local isPassive = kind == "screen" and (opts and opts.responder) == "passive"
		local contextPriority: number
		if kind == "modal" then
			contextPriority = topModalPriority() + 500
		elseif isPassive then
			contextPriority = ENGAGED_BASE_PRIORITY
		else
			contextPriority = BASE_SCREEN_PRIORITY
		end
		local context = actionSystem.createContext({
			name = `Nav-{blueprint.id or kind}`,
			priority = contextPriority,
			-- passive starts non-sinking + DISABLED (below); engage() flips both
			sink = kind == "modal" or (not isPassive and (opts and opts.sinkNavigation) == true),
		})
		local navigate = context.createAction("Navigate", "Direction1D")
		local activate = context.createAction("Activate", "Bool")
		local cancel = context.createAction("Cancel", "Bool")
		-- Adjust: the horizontal "change the focused thing" semantic (grip
		-- resize now; sliders later) — keyboard arrows, dpad, and bumpers
		local adjust = context.createAction("Adjust", "Direction1D")
		navigate.bind({ keyCode = "Down", direction = 1 })
		navigate.bind({ keyCode = "Up", direction = -1 })
		-- gamepad d-pad (PS Cross maps to ButtonA for Activate; the d-pad
		-- names are shared across vendors)
		navigate.bind({ keyCode = "DPadDown", direction = 1 })
		navigate.bind({ keyCode = "DPadUp", direction = -1 })
		-- input-axis tolerance (matrix §D.5; UI-PARADIGM-003): some console
		-- stacks deliver the D-pad (or the left stick) as an analog Thumbstick1
		-- axis, not DPad* keys. Bind it with the deadzone/re-center LATCH so such
		-- a pad still Navigates one step per push (the y component drives the
		-- vertical axis; screen-space convention = +y is down). The IAS
		-- realization is a Studio-drive/physical rider (roblox_input.bindAxis).
		navigate.bindAxis({ axis = "Thumbstick1", component = "y" })
		-- grouped screens own the horizontal axis too (verifier F2): Left/
		-- Right + dpad become real directions instead of Adjust
		local navigateH = if navigationGroups ~= nil then context.createAction("NavigateH", "Direction1D") else nil
		if navigateH ~= nil then
			navigateH.bind({ keyCode = "Left", direction = -1 })
			navigateH.bind({ keyCode = "Right", direction = 1 })
			navigateH.bind({ keyCode = "DPadLeft", direction = -1 })
			navigateH.bind({ keyCode = "DPadRight", direction = 1 })
			-- Thumbstick1 horizontal (matrix §D.5): the x component drives the
			-- horizontal axis on a grouped screen, same latch as the vertical.
			navigateH.bindAxis({ axis = "Thumbstick1", component = "x" })
		end
		activate.bind({ keyCode = "Return" })
		activate.bind({ keyCode = "ButtonA" })
		-- horizontal keys bind ONLY when the screen opts in (onAdjust): a
		-- non-modal screen must not shadow gameplay arrow/bumper bindings
		if opts and opts.onAdjust then
			adjust.bind({ keyCode = "Left", direction = -1 })
			adjust.bind({ keyCode = "Right", direction = 1 })
			-- dedicated keys the platform never contends for: Left/Right
			-- arrows are eaten upstream by camera scripts on some control
			-- stacks (hand-test + injection probes 2026-07-20), so comma
			-- and period always reach IAS
			adjust.bind({ keyCode = "Comma", direction = -1 })
			adjust.bind({ keyCode = "Period", direction = 1 })
			adjust.bind({ keyCode = "DPadLeft", direction = -1 })
			adjust.bind({ keyCode = "DPadRight", direction = 1 })
			adjust.bind({ keyCode = "ButtonL1", direction = -1 })
			adjust.bind({ keyCode = "ButtonR1", direction = 1 })
		end

		-- Dynamic Adjust auto-wiring (matrix §B-Table; UI-PARADIGM-001). ADR-0013
		-- kept Adjust consumer-opt-in so a non-modal screen never shadows gameplay
		-- arrow/bumper keys. To close the GAP without reopening that hazard, a
		-- control's contribution can declare `adjustTargets` + `handleAdjust`, and
		-- the presenter binds the Adjust keys ONLY while the FOCUSED path is one of
		-- those targets — so the keys are unbound (never shadowing) whenever focus
		-- sits elsewhere. opts.onAdjust (above) still wins per-opt and binds
		-- unconditionally (back-compat), so this engages only when it is absent.
		-- Comma/Period/L1/R1 never collide with a grouped screen's horizontal
		-- Navigate (NavigateH owns Left/Right + DPad L/R); the arrow/dpad
		-- horizontals are added only on a FLAT screen where NavigateH is absent.
		local function bindAdjustKeys(): { any }
			local bound: { any } = {
				adjust.bind({ keyCode = "Comma", direction = -1 }),
				adjust.bind({ keyCode = "Period", direction = 1 }),
				adjust.bind({ keyCode = "ButtonL1", direction = -1 }),
				adjust.bind({ keyCode = "ButtonR1", direction = 1 }),
			}
			if navigateH == nil then
				table.insert(bound, adjust.bind({ keyCode = "Left", direction = -1 }))
				table.insert(bound, adjust.bind({ keyCode = "Right", direction = 1 }))
				table.insert(bound, adjust.bind({ keyCode = "DPadLeft", direction = -1 }))
				table.insert(bound, adjust.bind({ keyCode = "DPadRight", direction = 1 }))
			end
			return bound
		end
		local dynamicAdjust = not (opts and opts.onAdjust)
			and (function(): boolean
				for _, c in contributions do
					if c.bundle.adjustTargets ~= nil or c.bundle.handleAdjust ~= nil then
						return true
					end
				end
				return false
			end)()
		local adjustBindings: { any } = {}
		local function setAdjustBound(on: boolean)
			if on == (#adjustBindings > 0) then
				return -- already in the requested state
			end
			if on then
				adjustBindings = bindAdjustKeys()
			else
				for _, b in adjustBindings do
					b.remove()
				end
				adjustBindings = {}
			end
		end
		-- Escape is permanently bound to the Roblox CoreGui menu (engine
		-- VirtualInput refuses it outright; verified live 2026-07-19, D1) —
		-- keyboard/mouse close affordances are screen-provided (scrim tap,
		-- gear toggle); gamepad B is the bindable Cancel.
		cancel.bind({ keyCode = "ButtonB" })

		-- Gameplay guard (ADR-0014): an engaged-exclusive context (modal, or a
		-- passive surface once engaged) additionally sinks the avatar-contended
		-- keys our other bindings do not already cover. ButtonA is sunk via
		-- Activate and arrows/D-pad via Navigate; Space (keyboard jump) is not,
		-- so bind it to a no-op GameplayGuard Bool action inside this sinking
		-- context. Overridable: opts.gameplayGuard = false opts out (a word-game
		-- modal that wants Space). WASD is deliberately NOT sunk in v1 (ADR-0014
		-- open decision, pending the live IAS move/jump binding-set probe). For a
		-- passive surface the guard lives in a DISABLED context until engage(),
		-- so Space reaches gameplay while passive.
		if (kind == "modal" or isPassive) and not (opts and opts.gameplayGuard == false) then
			local gameplayGuard = context.createAction("GameplayGuard", "Bool")
			gameplayGuard.bind({ keyCode = "Space" })
		end

		-- passive surfaces present with their nav context DISABLED: they bind
		-- nothing gameplay-contended until engaged (ADR-0014). engage() enables +
		-- sinks; resign() disables + un-sinks.
		if isPassive then
			context.setEnabled(false)
		end

		local handle: any = {
			kind = kind,
			blueprint = blueprint,
			scope = scope,
			root = root,
			controller = controller,
			context = context,
			actions = { navigate = navigate, activate = activate, cancel = cancel, adjust = adjust },
			contributions = contributions,
			-- modal outside-tap dismiss (ADR-0013 WP-2): default true; a modal
			-- opts out with outsideTapCancel=false to keep legacy clickthrough
			outsideTapCancel = not (opts and opts.outsideTapCancel == false),
			-- what Cancel (ButtonB) does to this SURFACE once no contribution
			-- consumed it: "dismiss" (default — modal dismisses / engaged-passive
			-- resigns) or "none" (a mandatory surface: Cancel is a no-op)
			cancelPolicy = cancelPolicy,
			onActivate = (opts and opts.onActivate) or nil,
			-- the surface's structural-transition machinery (ADR-0022 Decision 3)
			coordinator = coordinator,
			transition = (opts and opts.transition) or nil,
			emitFeedback = emitFeedback,
			navigationGroupsFn = navigationGroupsFn,
			onAdjust = (opts and opts.onAdjust) or nil,
			onReorderNav = (opts and opts.onReorderNav) or nil,
			feedGeometry = feedGeometry,
			-- the live re-discovery of this surface's input contributions (DB-4);
			-- `refresh` calls it before it re-derives the focus map, so a region
			-- that opened this frame is wired BEFORE its nodes join the ring
			syncContributions = syncContributions,
			-- responder mode (ADR-0014): passive surfaces engage/resign; every
			-- other surface reports "engaged" (a plain screen is engaged-open,
			-- non-sinking; a modal is engaged-exclusive). Readable for consumers.
			isPassive = isPassive,
			responder = scope:own(core:signal(if isPassive then "passive" else "engaged")),
			-- scrim appearance (spec §3.1): modals dim by default; engaged HUDs are
			-- transparent-but-catching; either overridable via opts.scrim.
			scrimMode = (opts and opts.scrim) or (if kind == "modal" then "scrim" else "none"),
			-- cross-surface z (spec §2.2 + ui-designer §6.3): each later surface
			-- renders above the ones before it WITHIN ITS BAND, and the bands keep a
			-- modal above every toast above every base screen whatever order they
			-- arrived in. The synthesized scrim sits at displayOrder-50, beneath its
			-- owner.
			displayOrder = (function()
				displayLayer += 100
				return (if kind == "modal" then SURFACE_LAYER.modal else SURFACE_LAYER.base) + displayLayer
			end)(),
		}
		if controller.setDisplayOrder ~= nil then
			controller.setDisplayOrder(handle.displayOrder)
		end
		surfaceRef = handle

		-- ONE SURFACE, ONE TRANSITION TARGET. A fading form needs a fade GROUP and a
		-- `Screen` is not one, so the transition targets the root's single declared
		-- `canvasGroup` child when it has one — `UI.ZStack{ canvasGroup = true }`
		-- around the screen's content is the documented shape — and the root itself
		-- otherwise (a slide needs no group).
		handle.transitionNode = (function()
			local rootNode = root.node
			if rootNode.props ~= nil and rootNode.props.canvasGroup == true then
				return rootNode
			end
			local only: any = nil
			for _, child in rootNode.children or {} do
				if child.props ~= nil and child.props.canvasGroup == true then
					if only ~= nil then
						return rootNode -- two groups: the surface itself is the target
					end
					only = child
				end
			end
			return only or rootNode
		end)()
		if handle.transition ~= nil then
			coordinator.beginEnter(handle.transitionNode.path, handle.transitionNode, handle.transition)
		end

		-- the same bus, filtered to this surface (the presenter-level
		-- `presenter.onFeedback` is the primary seam; this is the per-screen one)
		function handle.onFeedback(fn: (event: any) -> ()): () -> ()
			return bus.subscribe(function(event: any)
				if event.surface == handle then
					fn(event)
				end
			end)
		end

		-- no-pop text gate: hide the ROOT now (the tree is already mounted and
		-- solved, it just must not be SEEN yet) and let refresh() reveal it.
		-- Gating is only possible where the adapter can hide a whole root and
		-- the surface actually asked for it.
		handle.textRevealPending = false
		if (opts and opts.revealWhenTextExact) == true then
			local timeout = if type(opts.revealTimeout) == "number" then opts.revealTimeout else 2
			handle.textRevealDeadline = os.clock() + timeout
			-- an adapter that cannot hide a root does not get a hidden surface:
			-- it gets today's behaviour, which is visible and correct
			handle.textRevealPending = controller.setRootVisible(false)
			syncTextReveal(handle)
		end

		-- engage(): a passive surface becomes first responder — its nav context
		-- rises into the engaged band with sink=true, so it handles events BEFORE
		-- the avatar (IAS priority 3000 > gameplay 2000). No-op for non-passive
		-- surfaces (a modal is always exclusive; a plain screen is engaged-open).
		-- Idempotent, so tap-then-explicit or churn never double-registers.
		function handle.engage()
			if not isPassive or handle.responder:get() == "engaged" then
				return
			end
			context.setEnabled(true)
			-- through the seam, never a field write: the Roblox adapter must
			-- mirror this onto the real InputContext.Sink (P1, 2026-07-21)
			context.setSink(true)
			handle.responder:set("engaged")
			refreshExclusive()
			syncScrim() -- an engaged HUD gets its transparent catcher (spec §3.6)
		end

		-- resign(): drop back to passive — un-sink and disable the nav context so
		-- avatar/gameplay input is restored EXACTLY (Cancel / outside-tap route
		-- here). No-op for non-passive surfaces.
		function handle.resign()
			if not isPassive or handle.responder:get() == "passive" then
				return
			end
			context.setSink(false)
			context.setEnabled(false)
			handle.responder:set("passive")
			refreshExclusive()
			syncScrim() -- resigned: no longer exclusive, its catcher is retired
		end

		-- navigate intercept (gamepad grab mode etc.): opts.onNavigateIntercept
		-- wins; else chain the contributions' navigateIntercept, first true
		-- consumes the direction
		function handle.navigateIntercept(direction: string): boolean
			if opts and opts.onNavigateIntercept ~= nil then
				return opts.onNavigateIntercept(direction) == true
			end
			for _, c in contributions do
				if c.bundle.navigateIntercept ~= nil and c.bundle.navigateIntercept(direction) then
					return true
				end
			end
			return false
		end

		-- focus-move report (Apple selection-follows-focus): opts.onFocusNav
		-- wins; else route to the longest-prefix contribution's focusMoved.
		--
		-- Keep-visible (A-SV1) runs FIRST and unconditionally: any focusable
		-- inside a native scroll host is brought into view by the ONE shared
		-- substrate (controller.scrollToVisible), so a keyboard/gamepad focus
		-- move off the visible band works without every control re-implementing
		-- scroll arithmetic. It is a no-op when the node has no scroll ancestor,
		-- is already visible, or the adapter has no scroll seam — and a control
		-- with its OWN windowing (VirtualList) still gets its focusMoved call.
		function handle.focusMoved(path: string)
			if handle.controller ~= nil and handle.controller.scrollToVisible ~= nil then
				handle.controller.scrollToVisible(path)
			end
			if opts and opts.onFocusNav ~= nil then
				opts.onFocusNav(path)
				return
			end
			for _, c in contributionsForPath(contributions, path) do
				if c.bundle.focusMoved ~= nil and c.bundle.focusMoved(path) then
					return
				end
			end
		end

		-- dynamic Adjust binding gate (matrix §B-Table): bind the Adjust keys iff
		-- the currently-focused (owned) path is a declared adjust target, so
		-- gameplay keys are never shadowed while focus sits off-target. Called by
		-- the shared focus observer on every focus move and by refresh (targets may
		-- churn). No-op unless a contribution opted into the dynamic path.
		function handle.syncAdjustBindings(ownedPath: string?)
			if not dynamicAdjust then
				return
			end
			local isTarget = false
			if ownedPath ~= nil then
				for _, c in contributions do
					if c.bundle.adjustTargets ~= nil then
						local targets = c.bundle.adjustTargets(root.node)
						if type(targets) == "table" and targets[ownedPath] == true then
							isTarget = true
							break
						end
					end
				end
			end
			setAdjustBound(isTarget)
		end

		-- transient-popup focus trap/restore (matrix §B PopupButton; transientScope).
		-- While a contribution's transientScope is active, focus is TRAPPED within
		-- rootPath's subtree (defaulting to the contribution's own mounted path so the
		-- trigger stays the scope entry — focus does not jump into the open rows on
		-- open) via the focus graph's own trap/restore machinery; on deactivation
		-- focus RESTORES to the pre-activation focused path (the trigger). Driven from
		-- refresh (the rows are mounted/unmounted by the same UI.When at refresh), so
		-- the pushed trap scope always reflects the CURRENT mounted popup.
		local transientPushed: { [string]: boolean } = {}
		local function transientName(c: any): string
			return `__transient__{c.path}`
		end
		function handle.syncTransientScopes()
			for _, c in contributions do
				local ts = c.bundle.transientScope
				if ts ~= nil and ts.active ~= nil then
					local name = transientName(c)
					local wantActive = ts.active:get() == true
					local pushed = transientPushed[c.path] == true
					if wantActive then
						local rootPath = ts.rootPath or c.path
						local sub = nodeAt(root.node, rootPath)
						local order: { string } = {}
						if sub ~= nil then
							focusOrder(sub, order)
						end
						if not pushed then
							-- pushScope records the current focus (the trigger) for
							-- restore and enters at order[1] (the trigger) — no jump
							graph.pushScope({ name = name, trap = true, order = order })
							transientPushed[c.path] = true
						else
							-- rows may churn while open: keep the trap order current
							graph.setOrder(name, order)
						end
					elseif pushed then
						graph.removeScope(name) -- top trap: restores focus to the trigger
						transientPushed[c.path] = nil
					end
				end
			end
		end
		-- pop any live transient trap scopes (dismissing a screen with an OPEN
		-- popup must not orphan its trap scope in the focus graph)
		function handle.clearTransientScopes()
			for _, c in contributions do
				if transientPushed[c.path] then
					graph.removeScope(transientName(c))
					transientPushed[c.path] = nil
				end
			end
		end

		-- keep-visible: opts.keepVisibleOffset wins; else observe EVERY
		-- contribution's keepVisibleOffset readable and apply the MAX (the largest
		-- upward shift keeps every field clear of the on-screen keyboard; with a
		-- single control the max is just its own offset — unchanged §17 Phase 5)
		local offsets: { any } = {}
		if opts and opts.keepVisibleOffset ~= nil then
			table.insert(offsets, opts.keepVisibleOffset)
		else
			for _, c in contributions do
				if c.bundle.keepVisibleOffset ~= nil then
					table.insert(offsets, c.bundle.keepVisibleOffset)
				end
			end
		end
		if #offsets > 0 then
			local function maxOffset(): number
				local m = 0
				for _, r in offsets do
					local v = r:get()
					if type(v) == "number" and v > m then
						m = v
					end
				end
				return m
			end
			for _, r in offsets do
				scope:own(core:observe(r, function()
					controller.setPresentationOffset(maxOffset())
				end))
			end
			controller.setPresentationOffset(maxOffset())
		end

		-- ARMED AIM = FOCUS, ONE TRUTH (director virtual-controller round): a
		-- consumed intercept that stepped a live armed session's aim must move
		-- the RING with it — two parallel "where am I" states (a frozen ring and
		-- an invisible aim) is exactly the disorientation the live pass found.
		-- focusOn feeds the shared focused-observer, which re-aims idempotently.
		local function syncFocusToAim()
			local reg = if controller.peekDragRegistry ~= nil then controller.peekDragRegistry() else nil
			if reg ~= nil and reg.mode ~= nil and reg.mode() == "armed" then
				local target = reg.interactionTarget()
				if target ~= nil and target ~= graph.focused:get() then
					graph.focusOn(target)
				end
			end
		end

		if navigateH ~= nil then
			scope:own(core:observe(navigateH.state, function(dir)
				if dir == 1 or dir == -1 then
					-- a NAVIGATION verb asks "where does the ring go next", so the ring
					-- comes back even if a tap had put it away (DB-3(b))
					graph.setFocusOrigin("navigation")
					local direction = if dir == 1 then "right" else "left"
					if handle.navigateIntercept(direction) then
						syncFocusToAim()
						return
					end
					graph.navigateDirection(direction)
					local focused = graph.focused:get()
					if focused ~= nil then
						handle.focusMoved(focused)
					end
				end
			end))
		end
		scope:own(core:observe(navigate.state, function(dir)
			if dir == 1 or dir == -1 then
				graph.setFocusOrigin("navigation") -- see the horizontal case above
				local vertical = if dir == 1 then "down" else "up"
				-- gamepad grab mode etc.: the screen may CONSUME the move
				if handle.navigateIntercept(vertical) then
					syncFocusToAim()
					return
				end
				if navigationGroups ~= nil then
					-- direction-aware vertical movement for grouped scopes
					graph.navigateDirection(vertical)
					local focused = graph.focused:get()
					if focused ~= nil then
						handle.focusMoved(focused)
					end
					return
				end
				-- shift+Navigate: move the focused thing instead of focus
				-- (list reorder — the keyboard-reachable drag equivalent).
				-- Shift held CONSUMES the key even when the reorder is
				-- impossible (top row + up): falling through would wrap focus
				-- to the far end (verifier 2026-07-20 F1)
				if handle.onReorderNav ~= nil and actionSystem.modifiers ~= nil and actionSystem.modifiers().shift then
					local focused = graph.focused:get()
					if focused ~= nil then
						handle.onReorderNav(focused, dir)
					end
					return
				end
				graph.navigate(dir)
				-- Apple model: navigation-driven focus moves report to the
				-- screen (selection follows focus in lists); pointer focusOn
				-- does NOT route here — tap selection rides the activate meta
				local focused = graph.focused:get()
				if focused ~= nil then
					handle.focusMoved(focused)
				end
			end
		end))
		scope:own(core:observe(adjust.state, function(dir)
			if not (dir == 1 or dir == -1) then
				return
			end
			local focused = graph.focused:get()
			if focused == nil then
				return
			end
			if handle.onAdjust then
				-- rectOf rides along so consumers can seed a first adjust
				-- from the actually-rendered size (fill columns)
				handle.onAdjust(focused, dir, controller.rectOf)
			else
				-- contribution dynamic path (matrix §B-Table): route to the
				-- longest-prefix contribution's handleAdjust
				for _, c in contributionsForPath(contributions, focused) do
					if c.bundle.handleAdjust ~= nil and c.bundle.handleAdjust(focused, dir) then
						return
					end
				end
			end
		end))
		activate.onPressed(function()
			-- held modifiers ride along so list semantics (range/toggle select)
			-- work identically for keyboard and pointer
			local meta: any = { source = "action" }
			if actionSystem.modifiers ~= nil then
				local mods = actionSystem.modifiers()
				meta.shift = mods.shift
				meta.toggle = mods.toggle
			end
			dispatchActivate(handle, graph.focused:get(), meta)
		end)
		cancel.onPressed(function()
			-- transient-popup Cancel (matrix §B PopupButton; handleCancel): offer
			-- Cancel to the focused/longest-prefix contribution BEFORE the modal-
			-- dismiss / passive-resign / no-op branches (first true consumes). An
			-- open popup consumes it (closes); with nothing to cancel it returns
			-- false and Cancel falls through. ORDERING: a base screen and a modal
			-- are SEPARATE contexts — a modal above sinks ButtonB, so a base
			-- popup's handleCancel never fires while a modal is up (the modal's own
			-- dismiss wins, as required). Inside a MODAL, its OWN contribution is
			-- offered first, then the modal dismiss falls through — so a modal that
			-- contains an open popup closes the popup on the first ButtonB and
			-- dismisses on the second. Every existing modal/responder test stays
			-- green (no prior contribution declares handleCancel).
			local focused = graph.focused:get()
			local candidates = if focused ~= nil then contributionsForPath(contributions, focused) else contributions
			for _, c in candidates do
				if c.bundle.handleCancel ~= nil and c.bundle.handleCancel(focused) then
					return
				end
			end
			-- cancelPolicy = "none": the SURFACE ignores Cancel (a mandatory modal
			-- whose choice has no legal "not now"). Declared per surface, checked
			-- AFTER the contribution offer above, so a control inside a mandatory
			-- modal still cancels itself.
			if handle.cancelPolicy == "none" then
				return
			end
			if handle.kind == "modal" then
				self.dismiss(handle)
			elseif handle.isPassive and handle.responder:get() == "engaged" then
				-- Cancel on an engaged-from-passive surface resigns it (back to
				-- passive, context disabled) instead of doing nothing (ADR-0014)
				handle.resign()
			end
		end)

		-- STEP-5 DRAG INTEGRATION (ADR-0022 Decision 5): every surface's registry
		-- receives the presentation collaborators the moment the surface exists,
		-- so no fixture or game ever wires them — the feedback bus (drag events
		-- carry this surface), the shared motion clock (pickup scale, flights),
		-- an injected `now`, and the ghost layer above. `emit` adapts the
		-- registry's `(event, info)` shape onto the bus's Event table.
		if controller.setDragCollaborators ~= nil then
			controller.setDragCollaborators({
				feedback = {
					emit = function(event: string, info: any)
						emitFeedback({
							type = event,
							path = if type(info) == "table" then (info.source or info.targetId) else nil,
							reason = if type(info) == "table" then info.reason else nil,
							surface = surfaceRef,
							context = info,
						})
					end,
				},
				motionClock = motionClock,
				now = nowFn,
				proxy = dragProxyHost,
			})
		end
		-- FINDING F7: a trapping surface presenting cancels any live drag on the
		-- surfaces beneath it. Broadcast to registries that already EXIST (peek —
		-- never build a registry just to tell it about a modal); the registry
		-- itself decides which kinds trap.
		for _, liveHandle in stack do
			local reg = if liveHandle.controller ~= nil and liveHandle.controller.peekDragRegistry ~= nil
				then liveHandle.controller.peekDragRegistry()
				else nil
			if reg ~= nil then
				reg.surfacePresented(kind)
			end
		end
		table.insert(stack, handle)
		refreshExclusive() -- a modal joining the stack raises the exclusive flag
		syncScrim() -- synthesize/move the catcher beneath the new top exclusive surface
		-- paint the INITIAL focus ring: the shared focused-observer fired
		-- during pushScope, BEFORE this handle joined the stack, so the first
		-- focus of a fresh screen never rendered its ring (latent since
		-- phase 1; surfaced by the gamepad flow, 2026-07-20)
		local current = graph.focused:get()
		if current ~= nil then
			local rootPath = "/" .. (blueprint.id or "")
			if string.sub(current, 1, #rootPath) == rootPath then
				controller.setFocusPath(current)
				handle.syncAdjustBindings(current) -- initial focus may already sit on a target
			end
		end
		return handle
	end

	handleByPath = function(path: string): any
		-- taps route to the handle whose blueprint owns the path prefix;
		-- modals sit later in the stack, so search from the top
		for i = #stack, 1, -1 do
			local handle = stack[i]
			local rootPath = "/" .. (handle.blueprint.id or "")
			if string.sub(path, 1, #rootPath) == rootPath then
				return handle
			end
		end
		return nil
	end

	function self.present(blueprint: any, opts: PresentOpts?)
		specGuard.assertKnownKeys("presenter.present", opts, PRESENT_OPTS_KEYS, "opts")
		return makeHandle(blueprint, opts, "screen")
	end

	function self.presentModal(blueprint: any, opts: PresentOpts?)
		specGuard.assertKnownKeys("presenter.presentModal", opts, PRESENT_OPTS_KEYS, "opts")
		-- the base screen's context stays enabled for non-sunk actions, but
		-- navigation keys are sunk by the modal context's priority+sink
		local handle = makeHandle(blueprint, opts, "modal")
		-- A MODAL CANCELS A LIVE DRAG (ui-designer spec §5.4/§6.3; disposition F7).
		-- A focus trap and a drag proxy cannot coexist: the proxy tracks a pointer
		-- the trap has just taken away, and the drop it would resolve against is
		-- behind a barrier. The presenter states the fact; P4's drag session
		-- subscribes here and cancels itself (emitting its own `cancel` event with a
		-- reason) — the presenter never reaches into a session it does not own.
		local watchers = table.clone(modalWatchers)
		for _, fn in watchers do
			fn(handle)
		end
		return handle
	end

	-- P4's registration point for the rule above; returns an unsubscribe.
	function self.onModalPresented(fn: (handle: any) -> ()): () -> ()
		assert(type(fn) == "function", "presenter.onModalPresented takes a function(handle)")
		table.insert(modalWatchers, fn)
		return function()
			local index = table.find(modalWatchers, fn)
			if index ~= nil then
				table.remove(modalWatchers, index)
			end
		end
	end

	-- critical-screen fallback (§17 Phase 4): a screen whose construction or
	-- presentation throws presents opts.fallbackScreen(err) instead of taking
	-- the client down. The factory runs under pcall; so does makeHandle, so a
	-- blueprint that explodes during mount/render also falls back. The
	-- fallback screen itself presents normally (its errors stay hard).
	function self.presentCritical(blueprintFactory: () -> any, opts: PresentOpts)
		specGuard.assertKnownKeys("presenter.presentCritical", opts, PRESENT_OPTS_KEYS, "opts")
		assert(
			type(opts) == "table" and type(opts.fallbackScreen) == "function",
			"presentCritical requires opts.fallbackScreen(err) -> Blueprint"
		)
		local ok, blueprintOrError = pcall(blueprintFactory)
		if ok then
			local presented, handleOrError = pcall(makeHandle, blueprintOrError, opts, "screen")
			if presented then
				return handleOrError
			end
			blueprintOrError = handleOrError
		end
		-- THE FALLBACK IS PRESENTED WITH THE CALLER'S OPTS (F-16). It used to get
		-- `{ onActivate = … }` and nothing else, so a critical screen declared
		-- `rootPolicy = "edgeToEdge"` (or navigationGroups, transition,
		-- keepVisibleOffset, sinkNavigation…) lost every one of them exactly when
		-- things had already gone wrong — the stand-in rendered under the wrong
		-- root policy and the wrong navigation model, a second failure stacked on
		-- the first. Everything the caller declared about this screen is still
		-- true of the screen standing in for it. `fallbackScreen` is the one opt
		-- that does not ride along: the fallback presents as an ordinary screen
		-- and its own errors stay hard.
		local fallbackOpts: any = table.clone(opts :: any)
		fallbackOpts.fallbackScreen = nil
		return makeHandle(opts.fallbackScreen(blueprintOrError), fallbackOpts, "screen")
	end

	function self.dismiss(handle: any)
		local index = table.find(stack, handle)
		if index == nil then
			return
		end
		table.remove(stack, index)
		handle.context.destroy()
		-- pop any live transient popup trap scopes first, so removing the base
		-- scope never leaves an orphaned trap on top (matrix §B PopupButton)
		if handle.clearTransientScopes ~= nil then
			handle.clearTransientScopes()
		end
		-- remove THIS handle's focus scope wherever it sits — dismissing a
		-- covered screen must not pop the live top scope (verifier F3)
		graph.removeScope(handle.blueprint.id or handle.kind)
		-- the dismissal is a fact the moment it is decided, not when the pixels
		-- finish moving (SF-F1's causal frame)
		emitFeedback({ type = "dismiss", path = "/" .. (handle.blueprint.id or handle.kind), surface = handle })
		local function teardown()
			handle.controller.dispose()
			-- handle.scope owns the mount child scope; disposing it disposes the
			-- mounted tree exactly once (a separate root.dispose() here double-
			-- disposed the 'mount' child — phase-4 fault injection, input-switch)
			handle.scope:dispose()
			if handle.coordinator ~= nil then
				handle.coordinator.dispose()
			end
		end
		-- A DISMISSED SURFACE LEAVES THE STACK NOW AND THE SCREEN LATER. Its input
		-- context is destroyed, its focus scope popped and its exclusivity dropped
		-- above — a surface on its way out must never still take input — while the
		-- mounted tree and the instances live on until the exit completes, or until
		-- the coordinator's flat 500 ms cap fires. `dismiss` is idempotent through
		-- the stack check, so a second call during the exit does nothing.
		if handle.transition ~= nil and handle.coordinator ~= nil and handle.transitionNode ~= nil then
			local spec = transitionsLib.resolve(handle.transition)
			if spec.exit ~= "instant" then
				handle.coordinator.beginExit(handle.transitionNode.path, handle.transitionNode, spec, teardown)
				refreshExclusive()
				syncScrim()
				return
			end
		end
		teardown()
		refreshExclusive() -- dismissing a modal may lower the exclusive flag
		syncScrim() -- retire or re-home the scrim to the new top exclusive surface
	end

	function self.back()
		for i = #stack, 1, -1 do
			if stack[i].kind == "modal" then
				self.dismiss(stack[i])
				return true
			end
		end
		return false
	end

	function self.refresh()
		for _, handle in stack do
			handle.controller.refresh()
			-- FIRST: re-discover the input contributions from the tree this refresh
			-- just re-rendered (device round 1, DB-4). Before the focus map below,
			-- because a contribution that just mounted owns the groups that map is
			-- built from — wiring it a frame later would give the surface one frame
			-- of the wrong navigation model and, worse, one frame in which a tap on
			-- a freshly-mounted control dispatches to nothing.
			if handle.syncContributions ~= nil then
				handle.syncContributions()
			end
			-- a region that mounted since the last refresh has handles only now, so
			-- its enter transition's seeded values land here rather than a frame late
			if handle.coordinator ~= nil then
				handle.coordinator.flush()
			end
			-- re-feed solved geometry to keep-visible-aware controls (opt or
			-- every contribution's syncGeometry — see makeHandle.feedGeometry)
			handle.feedGeometry(handle.controller.rectOf)
			-- a gated surface reveals itself the moment its text round closes
			syncTextReveal(handle)
			-- re-derive the focus map from the CURRENT mounted tree so
			-- focusables mounted/unmounted by When/ForEach stay reachable and
			-- dead paths never receive Activate (phase-1 verifier finding F1)
			if handle.navigationGroupsFn ~= nil then
				local ctrl = handle.controller
				graph.replaceGroups(
					handle.blueprint.id or handle.kind,
					filterGroupsHidden(
						handle.navigationGroupsFn(handle.root.node),
						if ctrl ~= nil and ctrl.hiddenRoots ~= nil then ctrl.hiddenRoots() else nil
					)
				)
			else
				local order: { string } = {}
				focusOrder(handle.root.node, order)
				local ctrl = handle.controller
				order = filterHidden(order, if ctrl ~= nil and ctrl.hiddenRoots ~= nil then ctrl.hiddenRoots() else nil)
				graph.setOrder(handle.blueprint.id or handle.kind, order)
			end
			-- push/pop transient popup trap scopes now that the popup rows are
			-- mounted/unmounted (matrix §B PopupButton; transientScope) — AFTER the
			-- base order update so a close restores focus to the trigger cleanly
			if handle.syncTransientScopes ~= nil then
				handle.syncTransientScopes()
			end
			-- re-gate the dynamic Adjust bindings: adjust targets may have churned
			-- (rows added/removed) even when the focused path is unchanged
			if handle.syncAdjustBindings ~= nil then
				local f = graph.focused:get()
				local rootPath = "/" .. (handle.blueprint.id or "")
				local owns = f ~= nil and string.sub(f, 1, #rootPath) == rootPath
				handle.syncAdjustBindings(if owns then f else nil)
			end
		end
	end

	-- ===== TOASTS (ADR-0022 Decision 4; rows SF-T1..T3) =======================
	--
	-- A toast surface is PRESENTER-PRIVATE, exactly like the scrim and the popup
	-- catcher: it is not in `stack`, pushes no focus scope, creates no input
	-- context and wires no tap handler. That is what "input-transparent" is —
	-- not a property the layer politely observes, but a surface that has nothing
	-- to observe it with. Nothing here can reach `SelectedObject`, the responder
	-- chain, or the outside-tap policy, because none of that is built.
	--
	-- ONE layer holds every visible toast, as a keyed `UI.ForEach` carrying the
	-- transition — so a toast's enter/exit is the SAME retire model a `UI.When`
	-- gets, proven by the same tests, rather than a second animation path.
	--
	-- The scheduler (`toast_schedule`) owns priority, the queue cap, read floors
	-- and supersede; this driver owns pixels. Under reduced motion the transition
	-- places instantly and the schedule is untouched: every toast that would have
	-- been shown is still shown, for the same time (SF-T3).
	local toastTime = 0
	local toastPosition = "top"
	local toastTransition: any = nil
	local toastLayer: any = nil
	local toastSchedule: any = nil
	local syncToastLayer: () -> ()

	local function toastRowBlueprint(entry: any): any
		-- the fade GROUP the transition needs, wrapped by the presenter so a caller
		-- never has to know that a fade is a CanvasGroup fact
		return blueprintLib.ZStack({
			id = "Toast",
			width = { type = "fill", weight = 1 },
			height = { type = "content" },
			canvasGroup = true,
			children = { entry.data.blueprint },
		})
	end

	local function disposeToastLayer()
		if toastLayer == nil then
			return
		end
		local layer = toastLayer
		toastLayer = nil
		layer.coordinator.dispose()
		layer.controller.dispose()
		layer.scope:dispose()
	end

	local function ensureToastSchedule()
		if toastSchedule ~= nil then
			return
		end
		toastSchedule = toast_schedule.new({
			now = function()
				return toastTime
			end,
			onDismiss = function(entry: any, reason: string)
				-- every retirement is traceable, including the queued one dropped at
				-- the cap (disposition F3) — nothing vanishes without a reason code.
				-- REPLACEMENT IS ITS OWN VERB (ui-designer review R2-F1 ruling): a
				-- superseded toast emits exactly one `supersede`; `dismiss` means the
				-- surface actually retired on its own terms (timeout/capacity/manual/
				-- preempt). One causal moment, one event.
				emitFeedback({
					type = if reason == "supersede" then "supersede" else "dismiss",
					path = `/__toast__/Items/[{entry.id}]`,
					reason = if reason == "supersede" then nil else reason,
					context = { key = entry.key, priority = entry.priority, context = entry.data.context },
				})
			end,
		})
	end

	local function ensureToastLayer(options: any)
		if toastLayer ~= nil then
			return
		end
		-- the first toast fixes the layer's edge and transition for its lifetime:
		-- one layer, one stacking direction, so a burst cannot make the strip hop
		-- from one edge to the other mid-read
		toastPosition = if options.position == "bottom" then "bottom" else "top"
		toastTransition = options.transition
			or {
				-- a toast comes from the edge it docks to, and fades with it
				enter = if toastPosition == "bottom" then "slide-up" else "slide-down",
				fade = true,
			}
		local sc = core:scope("present-toast")
		-- scope-owned, so a layer that comes and goes twenty times leaves the core's
		-- counters exactly where it found them
		local items = sc:own(core:signal({}))
		local rows = blueprintLib.ForEach({
			id = "Items",
			items = items,
			key = function(entry: any): string
				return tostring(entry.id)
			end,
			row = toastRowBlueprint,
			transition = toastTransition,
		})
		local children: { any } = {}
		if toastPosition == "bottom" then
			-- the strip is pushed to the far edge; nothing else in the layer paints,
			-- so the spacer costs one transparent frame
			table.insert(children, blueprintLib.Spacer({ id = "Push", height = { type = "fill", weight = 1 } }))
		end
		table.insert(children, rows)
		-- padding lifts the strip off the surface edges (director SFH-3: rows
		-- hugging the exact top edge collided with content pinned there, and
		-- edge-to-edge rows read as a debug bar rather than a toast)
		local bp = blueprintLib.Screen({
			id = "__toast__",
			align = "center",
			gap = "s",
			padding = "m",
			children = children,
		})
		local surfaceRef: any = nil
		local coordinator = transitionsLib.new({
			core = core,
			clock = motionClock,
			metrics = metricsNow,
			feedback = function(event: any)
				event.surface = surfaceRef
				emitFeedback(event)
			end,
		})
		local root = mountLib.mount(core, bp, { scope = sc:child("mount"), transitions = coordinator })
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "coreSafeContent" })
		controller.initialRender()
		coordinator.bindController(controller)
		if controller.setDisplayOrder ~= nil then
			-- above every base screen, below every modal (ui-designer §6.3)
			controller.setDisplayOrder(SURFACE_LAYER.toast)
		end
		toastLayer = {
			scope = sc,
			controller = controller,
			root = root,
			items = items,
			coordinator = coordinator,
			itemsNode = nodeAt(root.node, "/__toast__/Items"),
		}
		surfaceRef = toastLayer
	end

	syncToastLayer = function()
		if toastLayer == nil then
			return
		end
		toastLayer.items:set(toastSchedule.visible())
		toastLayer.controller.refresh()
		-- the refresh is what CREATED the new row's handles; re-assert the enter's
		-- seeded values onto them so a toast never paints one frame at rest
		toastLayer.coordinator.flush()
		-- the layer retires when nothing is showing, nothing is waiting, and no row
		-- is still playing its exit — a retiring row is still mounted, so the
		-- mounted child count is the honest test
		local itemsNode = toastLayer.itemsNode
		local pending = if itemsNode ~= nil then #itemsNode.children else 0
		if toastSchedule.isEmpty() and pending == 0 then
			disposeToastLayer()
		end
	end

	function self.presentToast(blueprint: any, opts: ToastOpts?)
		assert(
			type(blueprint) == "table" and type(blueprint.class) == "string",
			"presenter.presentToast takes a blueprint (UI.*) and an options table"
		)
		specGuard.assertKnownKeys("presenter.presentToast", opts, TOAST_OPTS_KEYS, "opts")
		local options: any = opts or {}
		ensureToastSchedule()
		ensureToastLayer(options)
		local id = toastSchedule.push({
			key = options.key,
			priority = options.priority,
			duration = options.duration,
			readFloor = options.readFloor,
			data = { blueprint = blueprint, context = options.context },
		})
		syncToastLayer()
		return {
			id = id,
			dismiss = function()
				if toastSchedule == nil then
					return false
				end
				local removed = toastSchedule.dismiss(id, "manual")
				syncToastLayer()
				return removed
			end,
		}
	end

	function self.toastCounts()
		if toastSchedule == nil then
			return { visible = 0, queued = 0, sequence = 0 }
		end
		return toastSchedule.counts()
	end

	-- ONE FRAME OF PRESENTER TIME. Steps the motion clock (every surface and toast
	-- transition rides it) and advances the toast schedule. The client binds this
	-- to RunService.PreRender; the headless suite passes a scripted `dt`, which is
	-- what makes every rule above deterministic. Nothing animates and no deferred
	-- teardown completes without it — including the exit cap, which is measured in
	-- CLOCK time, not wall time.
	function self.tick(dt: number?)
		local step = dt
		local t = nowFn()
		if step == nil then
			step = t - lastTick
		end
		lastTick = t
		motionClock:step(step)
		if toastSchedule ~= nil then
			toastTime += math.max(step, 0)
			toastSchedule.update()
			syncToastLayer()
		end
		-- registered frame work (Step 5): per-frame consumers that are not motion
		-- values — an autoscrolling list's `stepAutoscroll`, a fixture's per-frame
		-- probe — ride the SAME tick so "one clock, one driver" stays true. Hooks
		-- run after the motion step: they read this frame's settled values.
		for _, hook in table.clone(tickHooks) do
			-- quarantined (verifier RR-12): a throwing hook must not starve its
			-- siblings or escape into the render thread's PreRender handler
			pcall(hook, step :: number)
		end
	end

	-- register per-frame work on the presenter's clock; returns an unsubscribe.
	-- The one sanctioned frame source outside the motion clock itself — a second
	-- RunService connection in a consumer is the bug class this prevents.
	function self.onTick(fn: (dt: number) -> ()): () -> ()
		table.insert(tickHooks, fn)
		return function()
			local index = table.find(tickHooks, fn)
			if index ~= nil then
				table.remove(tickHooks, index)
			end
		end
	end

	function self.depth(): number
		return #stack
	end

	return self
end

return presenter
