--!strict
-- HOW THE PRESENTER READS A MOUNTED TREE: focus order, the linear traversal rank,
-- navigation groups, and the input contributions that declare them.
-- Extracted from `presenter.luau` 2026-08-06.
--
-- WHY IT LIVES HERE. `presenter.luau` had grown to 200 609 characters — past the
-- 200 000 at which Roblox refuses a script-driven `Source` assignment — and 78% of it
-- is a single closure (`presenter.new`) whose parts all share upvalues. This block was
-- never inside that closure: it is pure, takes everything it needs as arguments, and
-- holds no state. Moving it is a FILE MOVE, not a refactor, and the bodies below are
-- byte-identical to what they were in `presenter.luau` — including their comments,
-- which are where this behaviour's reasoning is recorded.
--
-- The exports are listed at the BOTTOM rather than written as `function M.x`, so that
-- every internal call site keeps calling a plain local and no line of the moved code
-- had to change.

-- ONE dependency, and it is the reason the contribution walks live here rather than
-- beside the input system: a contribution's `focusGroups` is an INPUT to the focus map,
-- so collecting contributions and deriving groups is one cluster or it is a cycle.
local contribution = require("../input/contribution")
local paths = require("../paths")

local FOCUSABLE: { [string]: boolean } = { Button = true, Toggle = true, TextField = true }

-- B-BTN4: `enabled = false` must be consistent across focus, activation,
-- appearance and semantics. It used to reach only paint and semantics, so a
-- disabled control stayed in focus order and still activated on tap, Return and
-- ButtonA — visible as disabled, fully operable by keyboard and gamepad.
local function isDisabled(node: any): boolean
	return node ~= nil and node.props ~= nil and node.props.enabled == false
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
local isPathPrefix = paths.isPrefix

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
				-- THIS FILTER PUNCHES A HOLE, and a 2-D group's `columns` describes a
				-- RECTANGLE it no longer has: every entry after a removed one shifts a
				-- lane, so the perpendicular arrow would land confidently wrong.
				-- `focus_graph.remove` drops the field for the same reason and this is
				-- the same splice, one layer up — the group falls back to its 1-D
				-- reading, which is merely old (ADR-0030, "the rectangle invariant").
				copy.columns = nil
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

-- ===== the LINEAR reading of the focus map (roadmap Step 8 follow-up) ========
--
-- Everything above derives the order the ARROWS walk, and defers focusable Grips
-- to the end of it so directional navigation lands on content before it lands on
-- a value control's grab zone. Tab inherited that deferral and should not have: a Slider
-- between a button row and a list traversed AFTER the whole list, because a
-- Slider's focus stop is a Grip (director playtest 2026-08-03; the measurement is
-- in artifacts/traversal-document-order/acceptance.md).
--
-- So the presenter hands the graph a RANK — a sort key over the members the scope
-- already has, never a second list of members (decision packet TDN-2). Two rules,
-- in this order:
--
--   1. `traversalPriority`, a sort TIER (default 0, negative earlier, later
--      positive) so an author can move ONE control without redeclaring the map;
--   2. document position, so within a tier the order is the order the screen
--      reads in.
--
-- COMPLETENESS BY CONSTRUCTION. The rank is derived FROM the finished order, so
-- it covers exactly that order's paths — it cannot be missing one, which is what
-- `graph.traverse` requires before it will sort at all. That is why this runs
-- after the producer and after the hidden-filter rather than inside the walks:
-- three producers with three different pruning rules cannot drift from a map that
-- is built out of their own output.

--[[ ===== initialFocus: which control holds focus when the surface appears =====
	(director playtest 2026-08-03 round 5.)

	`opts.initialFocus` is `"first"` (the default and the pre-option behavior),
	`"none"`, a node id, or `{ id = "…" }`. This turns the author's answer into
	what `FocusScope.initialFocus` wants: `"first"`, `"none"`, or a resolved PATH.

	AN ID IS MATCHED AGAINST THE SCOPE'S OWN FOCUSABLES, by final path segment or
	by full path, so `"Save"` finds `/Settings/Actions/Save` without the author
	knowing the tree above it. An id that matches nothing is REFUSED naming what
	is available (§4: a value that is accepted must do something) — an author who
	typos a control name should not silently get "first" and wonder why.

	THE RESERVED WORDS ARE CHECKED FOR COLLISION, not assumed away. `"first"` and
	`"none"` are keywords, so a surface that actually contains a focusable with one
	of those ids is ambiguous — and rather than resolve it silently in either
	direction, construction refuses and names the escape hatch. It costs one branch
	and removes a class of bug nobody would ever guess at. ]]
local RESERVED_INITIAL_FOCUS: { [string]: boolean } = { first = true, none = true }

local function resolveInitialFocus(spec: any, order: { string }, surfaceName: string): string?
	if spec == nil then
		return nil
	end
	local wanted: string
	local explicitId = type(spec) == "table"
	if explicitId then
		wanted = (spec :: any).id
	else
		wanted = spec :: string
	end

	local function matches(path: string): boolean
		return path == wanted or string.sub(path, -(#wanted + 1)) == "/" .. wanted
	end

	local hit: string? = nil
	local ids: { string } = {}
	for _, path in order do
		local segs = string.split(path, "/")
		table.insert(ids, segs[#segs])
		if matches(path) and hit == nil then
			hit = path
		end
	end

	if not explicitId and RESERVED_INITIAL_FOCUS[wanted] then
		if hit ~= nil then
			error(
				`Facet present('{surfaceName}'): initialFocus '{wanted}' is ambiguous — it is a reserved word `
					.. `AND a mounted focusable has that id ({hit}). Rename the control, or say `
					.. `initialFocus = \{ id = "{wanted}" } to mean the control.`,
				0
			)
		end
		return wanted -- the keyword, with nothing to collide with
	end

	if hit == nil then
		local shown = table.concat(ids, ", ")
		if #ids > 12 then
			shown = table.concat(table.move(ids, 1, 12, 1, {}), ", ") .. `, … ({#ids} focusables)`
		end
		error(
			`Facet present('{surfaceName}'): initialFocus '{wanted}' names no focusable on this surface. `
				.. `Available: {if #ids > 0 then shown else "(none — this surface has no focusables)"}. `
				.. `Use "first" for the first one, or "none" for no initial focus.`,
			0
		)
	end
	return hit
end

-- `handle.focusOrder()`'s dump schema (constitution §6: every dump carries one).
-- Bump the integer if the shape changes in a way a reader could not absorb.
local FOCUS_ORDER_SCHEMA = "facet-focus-order/1"

-- the AUTHORED traversal tier on one mounted path, for the inspection dump.
-- Linear rather than a cached map on purpose: this runs once per entry in a
-- human-triggered debug call, never on the traversal path itself.
local function nodePriority(root: any, path: string): number
	local function walk(node: any): number?
		if node.path == path then
			local p = node.props ~= nil and node.props.traversalPriority or nil
			return if type(p) == "number" then p else 0
		end
		for _, child in node.children or {} do
			local found = walk(child)
			if found ~= nil then
				return found
			end
		end
		return nil
	end
	return walk(root) or 0
end

-- document position of every non-retiring node, plus the traversal tier declared
-- on it. One pre-order walk; `retiring` is pruned because every producer above
-- prunes it, so the two can never disagree about a fading subtree.
local function documentIndex(root: any): ({ [string]: number }, { [string]: number })
	local index: { [string]: number } = {}
	local priority: { [string]: number } = {}
	local n = 0
	local function walk(node: any)
		if isRetiring(node) then
			return
		end
		n += 1
		index[node.path] = n
		local p = node.props ~= nil and node.props.traversalPriority or nil
		if type(p) == "number" then
			priority[node.path] = p
		end
		for _, child in node.children or {} do
			walk(child)
		end
	end
	walk(root)
	return index, priority
end

-- every path in a flat order or a grouped map, in the order the graph will
-- concatenate them — the exact member set `allIds(scope)` will produce
local function orderPaths(order: { any }?, groups: { any }?): { string }
	local out: { string } = {}
	if order ~= nil then
		for _, entry in order do
			local path = entryPath(entry)
			if path ~= nil then
				table.insert(out, path)
			end
		end
	elseif groups ~= nil then
		for _, group in groups do
			for _, entry in (group.order or {}) :: { any } do
				local path = entryPath(entry)
				if path ~= nil then
					table.insert(out, path)
				end
			end
		end
	end
	return out
end

-- rank[path] = 1..N in linear-traversal order, for exactly the paths in `order`
-- or `groups`. A path the document walk never saw (a contribution may declare
-- one) sorts after everything it did see, deterministically, rather than
-- destabilizing the sort or dropping out of the map.
local function traversalRank(rootNode: any, order: { any }?, groups: { any }?): { [string]: number }
	local paths = orderPaths(order, groups)
	local index, priority = documentIndex(rootNode)
	local rows = table.create(#paths)
	local unseen = #paths + 1
	for i, path in paths do
		table.insert(rows, {
			path = path,
			priority = priority[path] or 0,
			doc = index[path] or (unseen + i),
			i = i,
		})
	end
	table.sort(rows, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		if a.doc ~= b.doc then
			return a.doc < b.doc
		end
		return a.i < b.i -- Luau's sort is not stable; keep equal keys reproducible
	end)
	local rank: { [string]: number } = {}
	for position, row in rows do
		rank[row.path] = position
	end
	return rank
end

-- ===== input auto-wiring seam (ADR-0013; ui_todo §0) =======================
-- The presenter walks the MOUNTED tree, discovers each composite's attached
-- input-contribution bundle, and auto-composes navigation groups + Activate
-- dispatch + grab intercept + focus-move reporting + geometry + keep-visible +
-- action-system binding. Every consumer-passed present() opt still overrides
-- its auto counterpart, per-opt (see makeHandle).

export type Contribution = { path: string, node: any, bundle: contribution.Bundle }

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
-- A ROW GRID DECLARES ITS ROWS, so they are read rather than inferred (parity
-- round 2 §2.2). Structural regions are transparent here for the same reason they
-- are in the layout tree: a `UI.ForEach` of `UI.GridRow`s is still a row grid, and
-- inferring "one row of everything" from an absent `columns` would make a 2D board
-- navigate as a single very wide row.
local STRUCTURAL: { [string]: boolean } = { When = true, ForEach = true, ErrorBoundary = true }
local function collectGridRows(node: any, out: { any }): boolean
	local sawOther = false
	for _, child in node.children or {} do
		if isRetiring(child) then
			continue
		elseif child.class == "GridRow" then
			table.insert(out, child)
		elseif STRUCTURAL[child.class] then
			sawOther = collectGridRows(child, out) or sawOther
		else
			sawOther = true
		end
	end
	return sawOther
end

local function emitGridGroups(node: any, groups: { any })
	local rows: { { string } } = {}
	local declaredRows: { any } = {}
	local mixed = collectGridRows(node, declaredRows)
	if #declaredRows > 0 and not mixed then
		for _, rowNode in declaredRows do
			local rowCells: { string } = {}
			collectFocusables(rowNode, rowCells)
			if #rowCells > 0 then
				table.insert(rows, rowCells)
			end
		end
	end
	if #rows == 0 then
		local cells: { string } = {}
		collectFocusables(node, cells)
		local colsProp = node.props and node.props.columns
		local cols = if type(colsProp) == "number" and colsProp >= 1 then colsProp else #cells
		for i, path in cells do
			local r = math.floor((i - 1) / cols) + 1
			rows[r] = rows[r] or {}
			table.insert(rows[r], path)
		end
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

-- A GRID IS NOT A CLOSED BOX (found live 2026-08-06, tutorial example 06).
--
-- `emitGridGroups` links its rows to EACH OTHER with up/down exits and sets
-- `containment = true` so left/right stay in a row. But the first row got no `up`
-- and the last row got no `down`, and containment stops the fall-through that
-- lets stacked `HStack`s leak into their neighbours. So focus entering a Grid
-- could never leave it: on a page of `board Grid -> rack -> Start over`, Down
-- from the bottom board row landed on the bottom board row, forever — measured,
-- fourteen presses, no movement. Everything after the grid was unreachable by
-- D-pad or arrow keys, which is the standing principle (`ui_todo.md` §0) failing
-- in the one container built for boards.
--
-- The grid cannot know its neighbours while it is being emitted, but the group
-- ARRAY is in document order, so adjacency answers it afterwards: the row before
-- a grid's first row and the row after its last row are exactly the groups either
-- side of it — including the last/first row of an adjacent grid, which is the
-- right target too. Authored exits are never overwritten.
local function linkGridBoundaries(groups: { any })
	local function gridPathOf(group: any): string?
		local name = group.name
		if type(name) ~= "string" then
			return nil
		end
		local path = string.match(name, "^auto%-grid%-(.*)%-r%d+$")
		return path
	end
	for index, group in groups do
		local path = gridPathOf(group)
		if path == nil then
			continue
		end
		local exit = group.exit
		if exit == nil then
			exit = {}
			group.exit = exit
		end
		-- ONLY A GROUP THIS DERIVATION EMITTED (architecture review M-2). Array
		-- adjacency is a DOCUMENT-ORDER artifact, and it only tracks visual order
		-- for the groups this module appends itself during one depth-first walk
		-- (`auto-flat-*`, `auto-v-*`, `auto-h-*`, `auto-grid-*`). A contribution's
		-- bundle is spliced in whole, in whatever order `bundle.focusGroups(node)`
		-- returned it — nothing promises its first entry is its topmost row — so a
		-- Grid sitting next to a contributing control could be handed an exit into
		-- that control's LAST visual row. A group whose members all filtered away
		-- is refused for the same reason: an exit into an empty group is the dead
		-- end this whole function exists to remove, just quieter.
		local function linkable(candidate: any): boolean
			if candidate == nil or type(candidate.name) ~= "string" then
				return false
			end
			if string.sub(candidate.name, 1, 5) ~= "auto-" then
				return false
			end
			return candidate.order ~= nil and #candidate.order > 0
		end
		if exit.up == nil then
			local before = groups[index - 1]
			-- only the boundary row has no intra-grid `up`, so `before` here is
			-- genuinely outside this grid
			if linkable(before) and gridPathOf(before) ~= path then
				exit.up = before.name
			end
		end
		if exit.down == nil then
			local after = groups[index + 1]
			if linkable(after) and gridPathOf(after) ~= path then
				exit.down = after.name
			end
		end
	end
end

--[[ IS THIS NODE A HORIZONTAL RUN OF FOCUSABLES? One predicate, because the
	answer is asked in THREE places — the contribution-aware `autoGroups`, the
	layout-only `layoutGroups`, and the `hasHorizontalStructure` gate that decides
	whether the second one engages at all — and it was written three times as
	`node.class == "HStack"`.

	AN `AdaptiveStack` CURRENTLY RUNNING ALONG X IS ONE TOO (found by
	navigation-and-menus D5, and it was a SHIPPED defect rather than a new one).
	`AdaptiveStack` exists so a row/column flip is a re-solve and not a remount,
	which is exactly why every adaptive row of controls the framework builds is
	one — `newPicker`'s segmented option strip, and therefore `newTabView`'s tab
	strip, are both `AdaptiveStack`s. Matching on `HStack` alone left every one of
	them navigating VERTICALLY on a pad: the wings of a tab bar answered Up/Down,
	and Right walked straight out of the band into the page underneath it.

	THE AXIS IS READ LIVE, because it is a bound prop by construction; a
	build-time read would pin the group to whichever shape the first frame
	happened to be. A stack on "y" is deliberately NOT a horizontal run — the flat
	vertical ring is already the right answer for it, and many tests depend on
	that ring being byte-identical.

	ONE HONEST LIMIT, measured rather than assumed. The presenter caches the whole
	derivation against the renderer's STRUCTURE EPOCH (`presenter.luau`'s
	`focusDerivation`), so an axis flip with no other consequence does not
	re-derive until the next structural change. Both shipped flips DO change
	structure and were checked live: a Picker resolving `segmented -> inline`
	re-derives (horizontal -> vertical), and a TabView re-homing from `bottomBar`
	to `sidebar` re-derives (horizontal -> vertical), because both move mounted
	nodes. A caller that binds `axis` to a bare signal and changes nothing else
	keeps the previous group for one structural beat. ]]
local function isHorizontalRun(node: any): boolean
	if node.class == "HStack" then
		return true -- byte-identical to the rule that shipped
	end
	if node.class ~= "AdaptiveStack" then
		return false
	end
	local axis = node.props and node.props.axis
	if type(axis) == "table" and (axis.kind == "signal" or axis.kind == "memo") then
		axis = (axis :: any):get()
	end
	if axis ~= "x" then
		return false
	end
	--[[ …AND IT MUST ACTUALLY BE A RUN, which is where the `HStack` rule got away
		with not asking. An adaptive stack is ALSO how a construct flips a whole
		SCREEN between arrangements — `newTabView`'s root is one, holding a tab
		strip on one side of a content region — and calling that a horizontal group
		would put the bar's wings and the page's controls in one left/right ring
		with nothing left for up/down.

		A RUN IS A NODE NO CHILD OF WHICH HOLDS MORE THAN ONE FOCUSABLE. It is
		exact rather than a heuristic: a strip of segments has one focusable per
		child however each is wrapped (a badged tab wears a cell around its
		Button), and a container of REGIONS has a child holding several. ]]
	for _, child in node.children or {} do
		if focusableCount(child) > 1 then
			return false
		end
	end
	return true
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
		if isHorizontalRun(node) and focusableCount(node) >= 2 and not subtreeHasFocusGroups(node) then
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
	-- BEFORE the grips group is appended: grips are deferred to the end of the
	-- ring regardless of where they sit in the document, so a grid's down-exit
	-- must not be pointed at them by mere array adjacency
	linkGridBoundaries(groups)
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
	if (isHorizontalRun(node) or node.class == "Grid") and focusableCount(node) >= 2 then
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
		if isHorizontalRun(node) and focusableCount(node) >= 2 then
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
	-- same rule, same reason, as the contribution-aware derivation above
	linkGridBoundaries(groups)
	if #grips > 0 then
		table.insert(groups, { name = "auto-grips", axis = "vertical", order = grips })
	end
	return groups
end

return {
	FOCUS_ORDER_SCHEMA = FOCUS_ORDER_SCHEMA,
	FOCUSABLE = FOCUSABLE,
	isDisabled = isDisabled,
	isRetiring = isRetiring,
	isPathPrefix = isPathPrefix,
	entryPath = entryPath,
	isHiddenPath = isHiddenPath,
	filterHidden = filterHidden,
	filterGroupsHidden = filterGroupsHidden,
	focusOrder = focusOrder,
	resolveInitialFocus = resolveInitialFocus,
	nodePriority = nodePriority,
	documentIndex = documentIndex,
	orderPaths = orderPaths,
	traversalRank = traversalRank,
	collectContributions = collectContributions,
	nodeAt = nodeAt,
	pathIsRetiring = pathIsRetiring,
	contributionsForPath = contributionsForPath,
	collectFocusables = collectFocusables,
	focusableCount = focusableCount,
	subtreeHasFocusGroups = subtreeHasFocusGroups,
	autoGroups = autoGroups,
	hasHorizontalStructure = hasHorizontalStructure,
	layoutGroups = layoutGroups,
}
