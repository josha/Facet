--!strict
-- Logical focus graph (design §9.3, UI-FOCUS-001): LuauUI owns focus identity
-- and movement; Roblox SelectedObject/NextSelection* are render outputs
-- applied by the platform adapter (not here — engine-free).
-- Scopes stack; the top scope owns navigation; modal scopes trap and restore
-- the previous focus on pop. A scope is either FLAT ({ order }) — a single
-- ring where navigate(±1) wraps — or GROUPED ({ groups }) per Phase 4:
-- each NavigationGroup declares an axis ("vertical" | "horizontal"), a wrap
-- policy, optional containment (implicit exits blocked), an entry policy
-- ("first" | "restore" | "nearest"), and per-direction exit overrides
-- ({ up/down/left/right = targetGroupName }). navigateDirection() moves along
-- the active group's axis, wraps or stops at edges per the group, and crosses
-- groups through declared exits or (uncontained) array-order fallthrough.
-- Structural changes keep focus when it survives, else the nearest surviving
-- neighbor, preferring the following item.
--
-- FOCUS-SKIP (ADR-0022 Decision 5, row SF-L3). An order entry may be written as
-- `{ id = path, focusable = () -> boolean }` instead of a bare path string.
-- The predicate is evaluated AT NAVIGATION TIME, never cached, so a row that
-- becomes ineligible while something is armed drops out of the ring on the very
-- next press without anyone rebuilding the order. Bare strings stay eligible
-- forever, so every existing caller is unchanged.
--
--   * Skipping is navigation-only. An ineligible node is still mounted, still
--     hit-testable, and still activates on a tap — "skipped for navigation"
--     must never mean "dead to inspection", or the player loses the one
--     affordance that could explain why it is ineligible.
--   * THE ACTIVE-INTERACTION EXEMPTION is binding: the node named by
--     `beginInteraction(id)` keeps its focusability for as long as the
--     interaction lives, even if its own predicate flips false. Yanking the row
--     out from under a gesture that is aiming at it is the defect the exemption
--     exists to prevent; the flip takes effect when `endInteraction()` runs. An
--     illegal commit on such a node REJECTS (a session verdict) rather than the
--     node vanishing mid-gesture.
--   * A group with no eligible entries is skipped whole: entry falls through to
--     the next group in the direction of travel rather than parking focus on a
--     node the player cannot use.

local focus_graph = {}

export type OrderEntry = string | { id: string, focusable: (() -> boolean)? }

export type NavigationGroup = {
	name: string,
	axis: string, -- "vertical" | "horizontal"
	order: { any }, -- { OrderEntry }: bare paths, or { id, focusable }
	wrap: boolean?,
	containment: boolean?,
	entry: string?, -- "first" (default) | "restore" | "nearest"
	exit: { [string]: string }?, -- direction -> target group name
}

export type FocusScope = {
	name: string,
	order: { any }?, -- FLAT scope
	groups: { NavigationGroup }?, -- GROUPED scope
	trap: boolean, -- modal: navigation stays inside, never escapes
	-- LINEAR TRAVERSAL (Tab / Shift+Tab) wrap policy, declared by the SCOPE.
	-- Default `true`. The plan's rule is that traversal wrap is a property of the
	-- active scope, not of any control or group inside it — a group's own `wrap`
	-- governs the DIRECTIONAL arrows along that group's axis and nothing else, so
	-- a screen cannot end up wrapping differently depending on which control the
	-- ring happens to be standing on. `true` is the default because it matches the
	-- flat ring the arrows have always walked (a list whose focus stops dead at
	-- the ends reads as "focus went nowhere" — director hand-test 2026-07-20) and
	-- because a trapped modal has nowhere else for Tab to go by construction.
	traversalWrap: boolean?,
	-- LINEAR TRAVERSAL ORDER, as a SORT KEY over the members this scope already
	-- has — never a second list of members (decision packet TDN-2).
	--
	-- Constitution §9 requires that Navigate and Traverse walk one focus map, and
	-- names the failure mode precisely: "a second order, derived from Instances or
	-- maintained alongside, is the defect — the two would disagree the first time a
	-- node was hidden". That failure is a MEMBERSHIP disagreement, and a rank map
	-- cannot produce one: `traverse` still takes its members from `allIds(scope)`
	-- and its eligibility from the same predicate the arrows use, and only asks
	-- this table what order to read them in. A path here that is not in `allIds` is
	-- invisible; a path in `allIds` that is missing here still traverses, sorting
	-- stably where it already sat.
	--
	-- nil means "no opinion", and a scope with no rank traverses BYTE-IDENTICALLY
	-- to pre-stage behavior — which is what makes a consumer-supplied
	-- `navigationGroups` keep its declared order verbatim.
	traversalRank: { [string]: number }?,
	-- where focus lands as this scope is pushed: nil / "first" (the first
	-- eligible node — the default and the pre-option behavior), "none" (push with
	-- no focus at all), or a resolved PATH. See pushScope.
	initialFocus: string?,
}

-- direction -> axis delta per group axis; nil = orthogonal to the axis
local AXIS_DELTA: { [string]: { [string]: number } } = {
	vertical = { down = 1, up = -1 },
	horizontal = { right = 1, left = -1 },
}
-- direction -> group-array fallthrough delta (implicit exits)
local FALLTHROUGH_DELTA: { [string]: number } = { down = 1, right = 1, up = -1, left = -1 }

function focus_graph.new(core: any)
	local self = {}
	local focused = core:signal(nil :: string?)
	local scopes: { any } = {} -- stack; top owns navigation
	local restoreStack: { string? } = {} -- previous focus per pushed modal
	-- the node an in-progress interaction is aiming at (drag hover, armed
	-- target). Exempt from every focusability predicate while it is set.
	local interactionId: string? = nil
	--[[ ── FOCUS IS ALWAYS TRACKED; THE RING IS NOT ALWAYS DRAWN ────────────────
		(device round 1, DB-3(b): "there is a random blue stripe to the left of the
		racer" — a focus ring painted on a phone, where no keyboard focus exists.)

		Focus IDENTITY is unconditional: a tap moves it (the Apple model, director
		round 2) so navigation continues from what the player touched, and every
		consumer that follows focus — the drag aim, keep-visible, the selection
		bridge — keeps working on touch exactly as it does on a pad. What a tap
		must NOT do is draw the ring: a ring is the answer to "where will the next
		Navigate go", and a finger asked no such question.

		So the graph carries the ORIGIN of the last focus move and publishes
		`focusVisible` from it. `pointer` (a tap/click, and anything that follows
		one — a programmatic focusOn is a CONTINUATION of the act that caused it)
		hides the ring; `navigation` (a key, a d-pad, an explicit
		setFocusOrigin("navigation")) shows it. Hybrid devices need no branch and
		no env fact: whichever way the player last moved focus is the way the
		surface answers, and the first arrow press after a tap brings the ring back.
	]]
	local focusOrigin = "navigation"
	local focusVisible = core:signal(true)

	self.focused = focused
	-- Readable<boolean>: should the focus ring PAINT right now? (see above)
	self.focusVisible = focusVisible

	-- "pointer" | "navigation". Idempotent; the presenter calls it on the acts
	-- it owns (a node tap / a navigation verb) and nothing else has to know.
	function self.setFocusOrigin(kind: string)
		local next = if kind == "pointer" then "pointer" else "navigation"
		if next == focusOrigin then
			return
		end
		focusOrigin = next
		focusVisible:set(next ~= "pointer")
	end

	function self.focusOrigin(): string
		return focusOrigin
	end

	local function top(): any
		return scopes[#scopes]
	end

	-- ORDERS ARE NORMALIZED ON INGEST: entries collapse to plain path strings and
	-- their predicates move to a side map, so every line below that indexes,
	-- wraps, or splices an order keeps working on a string array exactly as it
	-- did before focus-skip existed.
	local function normalizeOrder(list: { any }?, sink: { [string]: () -> boolean }): { string }
		local out: { string } = {}
		for _, entry in list or {} do
			if type(entry) == "string" then
				table.insert(out, entry)
			elseif type(entry) == "table" and type(entry.id) == "string" then
				table.insert(out, entry.id)
				if type(entry.focusable) == "function" then
					sink[entry.id] = entry.focusable
				end
			end
		end
		return out
	end

	--[[ THE ARGUMENT IS READ, NEVER CONSUMED (api-architecture-consistency F-14).
		Normalization used to write back into the CALLER's tables: `order` rewritten
		in place, `_focusable`/`_lastFocus` injected into a public exported type that
		declares neither, and every later `remove`/`setOrder`/`setGroupOrder`
		splicing the caller's own array. Three costs: a `table.freeze`d literal —
		this library's own idiom for immutable data — was a hard error from inside
		the graph; one NavigationGroup literal reused across two surfaces gave the
		two scopes a shared predicate map; and a caller reading its array back after
		a structural edit read the graph's state, not its own declaration.

		So the graph copies on ingest. `_focusable`, `_lastFocus` and the normalized
		order live ONLY on these internal copies, and every mutating method below
		operates on them. The copies are shallow: nested values the graph only ever
		reads (a group's `exit` map, a predicate closure) stay shared, which is
		correct — sharing is only a hazard where something writes. ]]
	local function internalGroups(groups: { any }): { any }
		local out: { any } = {}
		for i, group in groups do
			local sink: { [string]: () -> boolean } = {}
			local copy: any = table.clone(group)
			copy.order = normalizeOrder(group.order, sink)
			copy._focusable = sink
			out[i] = copy
		end
		return out
	end

	local function internalScope(scope: any): any
		if scope == nil then
			return nil
		end
		local copy: any = table.clone(scope)
		copy._lastFocus = nil
		-- the graph's own copy, same rule as the order tables below (F-14): the
		-- caller may keep building into the map it handed us and must not be able
		-- to reach in and re-rank a live scope behind `traverse`'s back
		if scope.traversalRank ~= nil then
			copy.traversalRank = table.clone(scope.traversalRank)
		end
		if scope.groups ~= nil then
			copy.groups = internalGroups(scope.groups)
			copy.order = nil
			copy._focusable = nil
		elseif scope.order ~= nil then
			local sink: { [string]: () -> boolean } = {}
			copy.order = normalizeOrder(scope.order, sink)
			copy._focusable = sink
		end
		return copy
	end

	local function predicateFor(scope: any, id: string): (() -> boolean)?
		if scope == nil then
			return nil
		end
		if scope.groups ~= nil then
			for _, group in scope.groups do
				local fn = group._focusable ~= nil and group._focusable[id] or nil
				if fn ~= nil then
					return fn
				end
			end
			return nil
		end
		return if scope._focusable ~= nil then scope._focusable[id] else nil
	end

	-- Evaluated at NAVIGATION TIME. A node with no declared predicate is always
	-- focusable (every pre-focus-skip caller), and the live interaction's target
	-- is focusable whatever its predicate says.
	local function isFocusable(scope: any, id: string?): boolean
		if id == nil then
			return false
		end
		if id == interactionId then
			return true
		end
		local fn = predicateFor(scope, id)
		if fn == nil then
			return true
		end
		return fn() ~= false
	end

	local function indexOf(list: { string }, id: string?): number?
		for i, v in list do
			if v == id then
				return i
			end
		end
		return nil
	end

	local function groupByName(scope: any, name: string?): NavigationGroup?
		for _, group in (scope.groups or {}) :: { NavigationGroup } do
			if group.name == name then
				return group
			end
		end
		return nil
	end

	local function groupOf(scope: any, id: string?): (NavigationGroup?, number?)
		for gi, group in (scope.groups or {}) :: { NavigationGroup } do
			local i = indexOf(group.order, id)
			if i ~= nil then
				return group, gi
			end
		end
		return nil, nil
	end

	-- THE SECOND READING (decision packet TDN-2). `allIds` answers WHO is in the
	-- scope; this answers what order the LINEAR verb reads them in. It takes the
	-- member list as given and only reorders it, so traversal can never reach a
	-- node the arrows cannot, nor miss one they can.
	--
	-- `table.sort` in Luau is NOT stable, so the comparator carries the entry's
	-- original index as an explicit final tiebreak. Without it, two controls at the
	-- same rank could swap between presses, which reads to a player as Tab going
	-- backwards for no reason.
	--
	-- THE MAP MUST COVER EVERY MEMBER, or this reorders nothing. Ranking only the
	-- paths it recognizes is not merely incomplete, it is UNSORTABLE: mixing ranked
	-- and unranked entries and falling back to index order for the mixed pairs
	-- yields an intransitive comparator (rank 9 at index 1, unranked at index 2,
	-- rank 1 at index 3 gives a<b and b<c but c<a), which Luau's sort is entitled
	-- to reject or to answer with garbage. The presenter always emits the rank from
	-- the SAME walk that produced the order, so completeness is the real contract
	-- and a gap is a bug — one that leaves traversal on the pre-stage reading,
	-- where it is at worst old, rather than on an order nobody can predict.
	local function traversalOrder(scope: any, ids: { string }): { string }
		local rank = scope.traversalRank
		if rank == nil then
			return ids
		end
		local rows = table.create(#ids)
		for i, id in ids do
			local r = rank[id]
			if r == nil then
				return ids -- incomplete: no opinion at all, rather than half of one
			end
			table.insert(rows, { id = id, rank = r, i = i })
		end
		table.sort(rows, function(a, b)
			if a.rank ~= b.rank then
				return a.rank < b.rank
			end
			return a.i < b.i
		end)
		local out = table.create(#rows)
		for _, row in rows do
			table.insert(out, row.id)
		end
		return out
	end

	local function allIds(scope: any): { string }
		if scope.order ~= nil then
			return scope.order
		end
		local out: { string } = {}
		for _, group in (scope.groups or {}) :: { NavigationGroup } do
			for _, id in group.order do
				table.insert(out, id)
			end
		end
		return out
	end

	-- remember the last focused id per group (entry = "restore")
	local function recordFocus(scope: any, id: string?)
		if scope == nil or id == nil or scope.groups == nil then
			return
		end
		local group = groupOf(scope, id)
		if group ~= nil then
			scope._lastFocus = scope._lastFocus or {}
			scope._lastFocus[group.name] = id
		end
	end

	local function setFocus(id: string?)
		focused:set(id)
		-- A SCOPE THAT ASKED FOR NO INITIAL FOCUS STOPS DECLINING ONE THE MOMENT IT
		-- GETS IT. `initialFocus = "none"` means "do not invent focus for me", not
		-- "never hold focus" — and the two are told apart by this flag rather than
		-- by testing `focused == nil`, which cannot distinguish "never had it" from
		-- "the focused node just unmounted". Order updates skip their auto-entry
		-- while it is set; once the player Tabs or taps in, the scope behaves like
		-- every other and keeps the nearest-survivor rule intact.
		if id ~= nil then
			local scope = top()
			if scope ~= nil then
				scope._awaitingFirstFocus = nil
			end
		end
		recordFocus(top(), id)
	end

	local function entryFocus(scope: any): string?
		if scope == nil then
			return nil
		end
		for _, id in allIds(scope) do
			if isFocusable(scope, id) then
				return id
			end
		end
		return nil
	end

	-- the eligible id closest to `start`, expanding outward (0, +1, -1, +2, …).
	-- With no predicates declared the offset-0 probe wins immediately, which is
	-- the pre-focus-skip "clamp to the index" answer unchanged. A TIE goes to the
	-- FOLLOWING item, the same preference §9.3 applies everywhere else focus has
	-- to pick a survivor.
	local function nearestEligible(scope: any, order: { string }, start: number): string?
		local n = #order
		if n == 0 then
			return nil
		end
		local from = math.clamp(start, 1, n)
		for offset = 0, n do
			for _, index in { from + offset, from - offset } do
				if index >= 1 and index <= n and isFocusable(scope, order[index]) then
					return order[index]
				end
			end
		end
		return nil
	end

	-- enter a group per its entry policy; fromIndex feeds "nearest". Returns
	-- whether it landed: a group with NO eligible entries is skipped whole, and
	-- the caller falls through to the next group in the direction of travel
	-- rather than parking focus somewhere the player cannot use.
	local function enterGroup(scope: any, group: NavigationGroup, fromIndex: number?, direction: string?): boolean
		if #group.order == 0 then
			return false
		end
		local entry = group.entry or "first"
		local target: string? = nil
		-- ENTRY ALONG THE GROUP'S OWN AXIS lands at the NEAR END (director
		-- virtual-controller round): pressing right into a horizontal row means
		-- "the first card", every time — ordinal "nearest" mapped row 3 to card
		-- 3, which read as random. Perpendicular entry (a grid's up/down between
		-- rows) keeps ordinal nearest, which is what preserves the column.
		local axisDelta = if direction ~= nil then AXIS_DELTA[group.axis or "vertical"][direction :: string] else nil
		if axisDelta ~= nil then
			target = nearestEligible(scope, group.order, if axisDelta > 0 then 1 else #group.order)
		elseif entry == "restore" then
			local remembered = scope._lastFocus and scope._lastFocus[group.name]
			if remembered ~= nil and indexOf(group.order, remembered) ~= nil and isFocusable(scope, remembered) then
				target = remembered
			end
		elseif entry == "nearest" and fromIndex ~= nil then
			target = nearestEligible(scope, group.order, fromIndex)
		end
		if target == nil then
			target = nearestEligible(scope, group.order, 1)
		end
		if target == nil then
			return false
		end
		setFocus(target)
		return true
	end

	-- base scope (screen) or modal push. Modal scopes trap and remember the
	-- previous focus for restoration on pop.
	--[[ `initialFocus` decides where focus lands as the scope is pushed — HERE,
		not by the caller setting focus afterwards (director playtest 2026-08-03
		round 5). A push already sets focus, so a caller that corrected it a moment
		later would fire the focus observers twice and paint a ring on one control
		before moving it to another. One decision, one notification.

		nil / "first" — the first eligible node, which is what every scope did
		                before this option existed and is still the default.
		"none"        — the scope is pushed with NO focus. It arrives on the first
		                Tab, tap, or engage, exactly as it does for a scope whose
		                nodes were all ineligible at push time.
		anything else — a RESOLVED PATH. The presenter turns an author's node id
		                into one and refuses an id that names nothing, so by the
		                time it reaches here it is known to be in this scope; if it
		                is somehow not eligible, entry falls back rather than
		                leaving focus somewhere the player cannot reach. ]]
	function self.pushScope(scope: FocusScope)
		-- the graph's own copy; the caller's tables are never written (F-14 above)
		local internal = internalScope(scope)
		if internal.trap then
			table.insert(restoreStack, focused:get())
		end
		table.insert(scopes, internal)
		local want = scope.initialFocus
		if want == "none" then
			internal._awaitingFirstFocus = true
			setFocus(nil)
		elseif want ~= nil and want ~= "first" and isFocusable(internal, want) then
			setFocus(want)
		else
			setFocus(entryFocus(internal))
		end
	end

	function self.popScope()
		local closing = table.remove(scopes)
		if closing and closing.trap then
			local previous = table.remove(restoreStack)
			focused:set(previous)
			recordFocus(top(), previous)
		elseif top() then
			setFocus(entryFocus(top()))
		else
			focused:set(nil)
		end
	end

	-- remove a scope BY NAME wherever it sits in the stack (§12.1: dismissing
	-- a covered screen must remove ITS scope, not the top one — phase-4
	-- verifier F3). Removing the top behaves like popScope; removing a buried
	-- scope leaves the active scope and focus untouched (its trap-restore
	-- entry, if any, is dropped with it).
	function self.removeScope(name: string)
		for i = #scopes, 1, -1 do
			local scope = scopes[i]
			if scope.name == name then
				local wasTop = i == #scopes
				-- its restore entry index = traps below it + itself
				local k = 1
				for j = 1, i - 1 do
					if scopes[j].trap then
						k += 1
					end
				end
				table.remove(scopes, i)
				if scope.trap then
					local previous = table.remove(restoreStack, k)
					if wasTop then
						focused:set(previous)
						recordFocus(top(), previous)
						return
					end
				end
				if wasTop then
					if top() then
						setFocus(entryFocus(top()))
					else
						focused:set(nil)
					end
				end
				return
			end
		end
	end

	-- leave `group` in `direction`: declared exit first; containment blocks
	-- implicit exits; otherwise fall through the group array in order
	local function exitFrom(
		scope: any,
		group: NavigationGroup,
		groupIndex: number,
		direction: string,
		fromIndex: number?
	)
		local declared = group.exit and group.exit[direction]
		if declared ~= nil then
			local target = groupByName(scope, declared)
			if target ~= nil then
				enterGroup(scope, target, fromIndex, direction)
			end
			return
		end
		if group.containment == true then
			return
		end
		local delta = FALLTHROUGH_DELTA[direction]
		if delta == nil then
			return
		end
		-- keep walking while a neighbor has nothing eligible in it (focus-skip):
		-- an all-ineligible group is transparent to navigation, not a wall
		local groups = scope.groups :: { NavigationGroup }
		local index = groupIndex + delta
		while groups[index] ~= nil do
			if enterGroup(scope, groups[index], fromIndex, direction) then
				return
			end
			index += delta
		end
	end

	-- direction-aware navigation ("up" | "down" | "left" | "right")
	function self.navigateDirection(direction: string)
		local scope = top()
		if scope == nil then
			return
		end
		if scope.groups == nil then
			-- flat ring: down/right advance, up/left go back
			local delta = FALLTHROUGH_DELTA[direction]
			if delta ~= nil then
				self.navigate(delta)
			end
			return
		end
		local group, groupIndex = groupOf(scope, focused:get())
		if group == nil then
			setFocus(entryFocus(scope))
			return
		end
		local i = indexOf((group :: NavigationGroup).order, focused:get()) :: number
		local axisDelta = AXIS_DELTA[(group :: NavigationGroup).axis or "vertical"][direction]
		if axisDelta == nil then
			-- orthogonal to the group's axis: only an exit can move focus
			exitFrom(scope, group :: NavigationGroup, groupIndex :: number, direction, i)
			return
		end
		local order = (group :: NavigationGroup).order
		local n = #order
		-- step along the axis, SKIPPING ineligible entries (SF-L3)
		local j = i + axisDelta
		while j >= 1 and j <= n do
			if isFocusable(scope, order[j]) then
				setFocus(order[j])
				return
			end
			j += axisDelta
		end
		if (group :: NavigationGroup).wrap == true then
			local k = i
			for _ = 1, n do
				k = ((k + axisDelta - 1) % n) + 1
				if isFocusable(scope, order[k]) then
					setFocus(order[k])
					return
				end
			end
			return -- nothing eligible anywhere in the ring: focus stays put
		end
		exitFrom(scope, group :: NavigationGroup, groupIndex :: number, direction, i)
	end

	-- ring navigation within the active scope. Flat scopes wrap (the spike
	-- clamped non-traps, but a list whose focus stops dead at the ends reads
	-- as "focus went nowhere" — director hand-test 2026-07-20). Grouped
	-- scopes map ±1 onto the active group's axis.
	function self.navigate(delta: number)
		local scope = top()
		if scope == nil then
			return
		end
		if scope.groups ~= nil then
			local group = groupOf(scope, focused:get())
			local axis = if group ~= nil then (group :: NavigationGroup).axis else "vertical"
			local direction = if axis == "horizontal"
				then (if delta >= 0 then "right" else "left")
				else (if delta >= 0 then "down" else "up")
			self.navigateDirection(direction)
			return
		end
		local order = scope.order :: { string }
		if #order == 0 then
			return
		end
		local i = indexOf(order, focused:get())
		if i == nil then
			setFocus(entryFocus(scope))
			return
		end
		local n = #order
		-- the first probe honours the caller's delta; the rest advance one slot
		-- at a time in the same direction, so skipping never turns a ±1 step into
		-- a ±2 one (SF-L3)
		local step = if delta >= 0 then 1 else -1
		local k = i + delta
		for _ = 1, n do
			local index = ((k - 1) % n) + 1
			if isFocusable(scope, order[index]) then
				setFocus(order[index])
				return
			end
			k += step
		end
	end

	--[[ ── LINEAR TRAVERSAL: Tab / Shift+Tab ────────────────────────────────────
		The desktop convention, over the SAME graph the arrows walk. `delta` is +1
		(Tab) or -1 (Shift+Tab); the answer is whether focus actually moved.

		The members are `allIds(scope)` — a flat scope's own order, or every group's
		order concatenated in group-array order. That is the whole point: traversal
		is a second READING of one focus map, never a second focus map. Everything
		the arrows already skip — hidden, disabled, non-focusable, retiring, and
		losing adaptive candidates (all filtered out before they ever reach the
		graph) plus live focus-skip predicates (evaluated here, at navigation time)
		— is skipped identically, because it is the same set and the same predicate.

		The READING is `traversalOrder`, which sorts those members by the scope's
		rank. The concatenated group order is NOT document order: the presenter
		defers focusable Grips (a Slider's track, a Rating's strip)
		to the end so the ARROWS land on content first, and Tab inherited that — so
		a Slider sitting between a button row and a list traversed after the whole
		list (director playtest 2026-08-03). Tab means document order on every
		platform that has ever had a Tab key; the arrows keep the deferral, which
		is theirs. A scope with no rank reads in `allIds` order, unchanged.

		Where traversal DIFFERS from `navigate` is that it crosses group boundaries
		unconditionally: a contained group is contained against the ARROWS (left
		does not leave a grid row), and Tab's job is precisely to leave. Wrap is the
		scope's policy (see FocusScope.traversalWrap). ]]
	function self.traverse(delta: number): boolean
		local scope = top()
		if scope == nil then
			return false
		end
		local order = traversalOrder(scope, allIds(scope))
		local n = #order
		if n == 0 then
			return false
		end
		local current = focused:get()
		local i = indexOf(order, current)
		local step = if delta >= 0 then 1 else -1
		if i == nil then
			-- Focus is outside this scope (or nil): traversal ENTERS rather than
			-- no-ops — and it enters at the END IT CAME FROM (architecture review
			-- ARCH-9). Tab lands on the first eligible node, Shift+Tab on the last;
			-- entering a scope backwards and landing on its first item reads as the
			-- ring jumping past everything, which is the disorientation the
			-- near-end entry rule exists to prevent everywhere else in this graph.
			local entry = if step > 0 then entryFocus(scope) else nearestEligible(scope, order, n)
			if entry == nil then
				return false
			end
			setFocus(entry)
			return true
		end
		local wrap = scope.traversalWrap ~= false
		local k = i
		for _ = 1, n do
			k += step
			if k < 1 or k > n then
				if not wrap then
					return false -- an end, and this scope does not wrap
				end
				k = ((k - 1) % n) + 1
			end
			local candidate = order[k]
			if candidate ~= current and isFocusable(scope, candidate) then
				setFocus(candidate)
				return true
			end
		end
		return false -- nothing else eligible anywhere in the scope: focus stays put
	end

	-- replace a GROUPED scope's whole group map (dynamic surfaces: table rows
	-- reorder/churn — gamepad support 2026-07-20): keeps focus when it
	-- survives the new map, else enters the first group.
	--
	-- A FLAT scope is UPGRADED rather than refused (device round 1, DB-4). A
	-- surface whose only group-declaring control lives inside a `UI.When` is
	-- flat at present time and grouped the moment that region opens; refusing
	-- the upgrade left it navigating a flat ring for the rest of its life, with
	-- the declared wraps and exits silently dropped. The scope keeps its name,
	-- its trap and its stack position — only its navigation model changes.
	-- `rank` rides along with every order write for the same reason it rides along
	-- with `pushScope`: it must come from the SAME derivation that produced the
	-- order, or the two drift and traversal starts sorting a map that no longer
	-- exists. Omitting it clears the scope's rank rather than leaving a stale one.
	function self.replaceGroups(scopeName: string, groups: { NavigationGroup }, rank: { [string]: number }?)
		for i = #scopes, 1, -1 do
			local scope = scopes[i]
			if scope.name == scopeName then
				-- copied on ingest, exactly like pushScope (F-14)
				scope.groups = internalGroups(groups)
				scope.order = nil
				scope._focusable = nil
				scope.traversalRank = if rank ~= nil then table.clone(rank) else nil
				if scope._lastFocus ~= nil then
					for groupName, remembered in scope._lastFocus do
						local group = groupByName(scope, groupName)
						if group == nil or indexOf((group :: NavigationGroup).order, remembered) == nil then
							scope._lastFocus[groupName] = nil
						end
					end
				end
				if i == #scopes then
					local current = focused:get()
					if not scope._awaitingFirstFocus and (current == nil or indexOf(allIds(scope), current) == nil) then
						setFocus(entryFocus(scope))
					end
				end
				return
			end
		end
	end

	-- replace a FLAT scope's order after structural change: keeps focus if it
	-- survives, else nearest surviving neighbor
	function self.setOrder(name: string, order: { any }, rank: { [string]: number }?)
		for i = #scopes, 1, -1 do
			local scope = scopes[i]
			if scope.name == name then
				if scope.groups ~= nil then
					return -- grouped scopes update per group (setGroupOrder)
				end
				local oldOrder = scope.order :: { string }
				local oldIndex = indexOf(oldOrder, focused:get())
				local sink: { [string]: () -> boolean } = {}
				local normalized = normalizeOrder(order, sink)
				scope.order = normalized
				scope._focusable = sink
				scope.traversalRank = if rank ~= nil then table.clone(rank) else nil
				if i == #scopes then
					local current = focused:get()
					if not scope._awaitingFirstFocus and (current == nil or indexOf(normalized, current) == nil) then
						local fallback = if oldIndex ~= nil then math.min(oldIndex, #normalized) else 1
						setFocus(nearestEligible(scope, normalized, math.max(1, fallback)))
					end
				end
				return
			end
		end
	end

	-- replace ONE group's order after structural change (§9.3): keeps focus
	-- when it survives, else the nearest survivor (prefers the following item)
	function self.setGroupOrder(scopeName: string, groupName: string, order: { any })
		for i = #scopes, 1, -1 do
			local scope = scopes[i]
			if scope.name == scopeName and scope.groups ~= nil then
				local group = groupByName(scope, groupName)
				if group == nil then
					return
				end
				local oldOrder = (group :: NavigationGroup).order
				local oldIndex = indexOf(oldOrder, focused:get())
				local sink: { [string]: () -> boolean } = {}
				local normalized = normalizeOrder(order, sink);
				(group :: NavigationGroup).order = normalized;
				(group :: any)._focusable = sink
				if scope._lastFocus and scope._lastFocus[groupName] ~= nil then
					if indexOf(normalized, scope._lastFocus[groupName]) == nil then
						scope._lastFocus[groupName] = nil
					end
				end
				if i == #scopes and oldIndex ~= nil then
					local current = focused:get()
					if current == nil or indexOf(normalized, current) == nil then
						local fallback = math.max(1, math.min(oldIndex, #normalized))
						setFocus(nearestEligible(scope, normalized, fallback))
					end
				end
				return
			end
		end
	end

	-- a focusable disappeared (structural change): nearest surviving neighbor
	-- in the active scope, preferring the following item (design §9.3)
	function self.remove(id: string)
		local scope = top()
		if scope == nil then
			return
		end
		-- an exemption cannot protect a node that no longer exists; the SESSION
		-- still ends the targeting through its own path (finding F5)
		if interactionId == id then
			interactionId = nil
		end
		if scope.groups ~= nil then
			local group = groupOf(scope, id)
			if group == nil then
				return
			end
			local order = (group :: NavigationGroup).order
			local i = indexOf(order, id) :: number
			table.remove(order, i)
			if (group :: any)._focusable ~= nil then
				(group :: any)._focusable[id] = nil
			end
			if focused:get() == id then
				setFocus(nearestEligible(scope, order, math.min(i, #order)))
			end
			return
		end
		local order = scope.order :: { string }
		local i = indexOf(order, id)
		if i == nil then
			return
		end
		table.remove(order, i)
		if scope._focusable ~= nil then
			scope._focusable[id] = nil
		end
		if focused:get() == id then
			setFocus(nearestEligible(scope, order, math.min(i, #order)))
		end
	end

	-- pointer-driven focus (Apple model, director round 2): clicking a
	--[[ ── FOCUS MAP INSPECTION ─────────────────────────────────────────────────
		Both readings of one scope's focus map, as data, for the surface-level
		`handle.focusOrder()` dump.

		This exists because the defect it ships beside was found by a person in a
		playtest and by none of the instruments: there was no way to ASK what order
		Tab would take, so the only way to see it was to press Tab sixteen times and
		write down where focus landed. Reporting the linear order and the group
		order side by side is the whole point — a reader has to be able to see that
		they differ (they are meant to) while covering the same set (they must).

		`eligible` is the LIVE predicate, evaluated now, so an entry a focus-skip
		predicate is currently refusing reads false without leaving the map. Nodes
		excluded upstream — hidden, disabled, non-focusable, retiring, losing
		adaptive candidates — are filtered before they ever reach the graph and are
		therefore absent entirely, which is itself the answer to "why is it not in
		my Tab order".

		Returns nil for an unknown scope name so a caller can tell "no such scope"
		from "a scope with nothing in it". ]]
	function self.focusMap(scopeName: string?): any?
		local scope = if scopeName == nil then top() else nil
		if scopeName ~= nil then
			for i = #scopes, 1, -1 do
				if scopes[i].name == scopeName then
					scope = scopes[i]
					break
				end
			end
		end
		if scope == nil then
			return nil
		end
		local members = allIds(scope)
		local traversal = {}
		for _, id in traversalOrder(scope, members) do
			table.insert(traversal, {
				path = id,
				rank = if scope.traversalRank ~= nil then scope.traversalRank[id] else nil,
				eligible = isFocusable(scope, id),
			})
		end
		local navigation = {}
		if scope.groups == nil then
			-- A FLAT SCOPE STILL HAS A DIRECTIONAL READING — it is one vertical ring,
			-- and that ring is where the Grip deferral lives for a plain screen.
			-- Reporting `navigation = {}` here would have made the dump silent about
			-- the arrows on exactly the surfaces where the two readings differ most
			-- visibly, which is the comparison the dump exists to serve. The name is
			-- parenthesized so nobody mistakes it for a declared group.
			table.insert(navigation, { name = "(flat)", axis = "vertical", order = members })
		end
		for _, group in (scope.groups or {}) :: { NavigationGroup } do
			local order = {}
			for _, entry in group.order do
				table.insert(order, entry)
			end
			table.insert(navigation, {
				name = group.name,
				axis = group.axis,
				order = order,
			})
		end
		return {
			scope = scope.name,
			trap = scope.trap == true,
			traversalWrap = scope.traversalWrap ~= false,
			ranked = scope.traversalRank ~= nil,
			traversal = traversal,
			navigation = navigation,
		}
	end

	-- focusable moves keyboard focus there; only paths in the ACTIVE scope
	-- are accepted (a background screen's node cannot steal focus)
	function self.focusOn(path: string): boolean
		local scope = top()
		if scope == nil or indexOf(allIds(scope), path) == nil then
			return false
		end
		-- an ineligible node does not TAKE focus, but it is still tappable and
		-- still activates: refusing the focus move is not refusing the tap
		if not isFocusable(scope, path) then
			return false
		end
		setFocus(path)
		return true
	end

	-- ===== active-interaction exemption (SF-L3) ===========================
	-- The node an in-progress interaction is aiming at keeps its focusability
	-- for as long as the interaction lives. Calling this again MOVES the
	-- exemption (a drag's hovered target changes as the player navigates); the
	-- graph holds exactly one at a time, because exactly one gesture is live.
	function self.beginInteraction(id: string?)
		interactionId = id
	end

	function self.endInteraction()
		interactionId = nil
	end

	function self.interactionTarget(): string?
		return interactionId
	end

	-- is this node navigable right now? (the predicate, plus the exemption)
	function self.isFocusable(id: string): boolean
		return isFocusable(top(), id)
	end

	function self.activeScopeName(): string?
		local scope = top()
		return scope and scope.name
	end

	return self
end

return focus_graph
