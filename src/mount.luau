--!strict
-- Mounted node graph (design §4.3 #2, §6.4): materializes a blueprint over a
-- core exactly once per node (factory-once, UI-RUNTIME-001), subscribes
-- dynamic props to their declared dirty classes, and gives ONLY structural
-- regions (When/ForEach) the power to mount/move/unmount (UI-RUNTIME-002).
-- Engine-free: rendering is a later consumer of this graph + dirty queue.
-- Public: mount(core, blueprint, opts?) -> MountedRoot
--   root.node          the mounted tree
--   root.takeDirty()   drain the dirty queue [{path, class}] in order
--   root.dirtySeq()    monotonic count of dirties ever pushed (survives takeDirty)
--   root.counters()    { mounted, factoryRuns } live totals
--   root.dump()        deterministic tree (id/path/class/dirty/factoryRuns)
--   root.dispose()

local blueprintLib = require("./blueprint")
local profile = require("./core/profile")
local specGuard = require("./spec_guard")
-- the `UI.sensoryFeedback` declaration's reader (round 2 §3.3, and the control
-- form's cascade in round 3). Requires nothing; see the note in that file on why
-- the contract lives with the vocabulary rather than in the authoring layer.
local feedbackContract = require("./present/feedback")

type Blueprint = blueprintLib.Blueprint

local DIRTY_CLASSES = { "paint", "measure", "arrange", "structure", "navigation", "semantics" }

--[[ THE CLASSES WHOSE CHILDREN ARE LAID OUT IN A LINE (Plan D, D6a), so a child of
	one is a "row" for `render/instance_boundary`'s fifth coordinate-space trigger.
	Mount is where the fact belongs because mount is the only pass that knows the
	AUTHORED parent: a `ForEach` region is spliced into the enclosing flow by
	`render/layout_node`, so by the time the solver sees a row its parent is the
	stack's flow and the region has vanished. The fact is threaded down instead —
	one boolean parameter through `mountNode` and the three structural regions — so
	a row mounted inside a `ForEach` inside a `VStack` inherits the stack-ness the
	region stands in for.

	`ScrollView` IS IN THE SET, and it is not an oversight that it is not a stack: a
	scroller lays its children out along an axis exactly as a stack does, and it is
	where Facet's own `Table` puts its rows (`controls/table.luau`'s Body is a
	`ScrollView` unless `spec.scrolls == false`). Without it the trigger reached a
	hand-written list and not the framework's list control — measured on
	RascalRally's racer list, which is that control. The scroller itself is still
	REFUSED as a coordinate space by name in `render/instance_boundary`; this set
	answers a different question, about the scroller's CHILDREN. ]]
local STACK_PARENT: { [string]: boolean } = { VStack = true, HStack = true, ScrollView = true }

--[[ ===== THE INHERITED CHANNELS (stabilization pass 2026-09-07, stream C) =====
	Design note: `docs/superpowers/specs/2026-09-07-inherited-tint-disabled.md`.

	`enabled` and `tint` are declared on a container and resolved onto its WHOLE
	SUBTREE, and this is the pass that resolves them, for the reason the
	`sensoryFeedback` cascade below already gives: mount is the only walk that sees
	a blueprint's ancestors and its mounted node at the same moment. Two more
	reasons make it the right owner here — every reader of "disabled" reads a
	MOUNTED NODE (the focus map, the presenter's Activate dispatch, the renderer's
	three input gates), and mount already owns the per-node scopes and the dirty
	queue, so reactivity and teardown need no new machinery.

	THE RECORD IS SHARED BY REFERENCE. `Inherit` is what a node hands its children,
	and a node that re-declares nothing hands down the identical table it received —
	so an undeclared tree allocates nothing and stores nothing, and a declared one
	costs one table per declaration site rather than one per node.

	TWO RULES, AND THEY ARE DIFFERENT ON PURPOSE:
	  * disabled is a CONJUNCTION — own `false` OR any ancestor's `false`. There is
	    no re-enable, in either direction, so a screen can never present a control
	    that looks live inside a panel that is not.
	  * tint is NEAREST-DECLARATION — the node's own value, else the nearest
	    ancestor's. A control STOPS it for its own interior, because inside a
	    control paint belongs to the role and the state machine (blueprint_schema's
	    TINT block).
]]
export type Inherit = { disabled: boolean, tint: any? }

local TINT_STOPS: { [string]: boolean } = { Button = true, Toggle = true, TextField = true }

-- the two prop names whose change re-resolves a subtree (see `recascade`)
local INHERITED_PROPS: { [string]: boolean } = { enabled = true, tint = true }

--[[ Resolve one node against the record it was handed. Sets the two derived
	fields — `node.disabled` (this node is inside, or is, a disabled subtree) and
	`node.inheritedTint` (the tint it paints when it declared none) — records the
	incoming record for a later re-walk, and returns the record its children get
	plus whether either derived field actually MOVED.

	The derived fields are deliberately NOT folded into `node.props`: props stays
	"what the author declared", which is what makes "does this node override?"
	answerable at all. ]]
local function sameRecord(a: any, b: any): boolean
	if a == b then
		return true
	end
	if a == nil or b == nil then
		return false
	end
	return a.disabled == b.disabled and a.tint == b.tint
end

local function applyInherited(node: any, inherited: any): (any, boolean, boolean, boolean)
	local props = node.props
	local ownEnabled = if props ~= nil then props.enabled else nil
	local ownTint = if props ~= nil then props.tint else nil
	local inTint = if inherited ~= nil then inherited.tint else nil
	local disabled = (inherited ~= nil and inherited.disabled == true) or ownEnabled == false
	local inheritedTint = if ownTint == nil then inTint else nil

	local disabledMoved = (node.disabled == true) ~= disabled
	local tintMoved = node.inheritedTint ~= inheritedTint
	node.disabled = if disabled then true else nil
	node.inheritedTint = inheritedTint
	node.inheritFrom = inherited

	local childTint = if TINT_STOPS[node.class] then nil else (if ownTint ~= nil then ownTint else inTint)
	local previous = node.inheritOut
	local out: any = nil
	if disabled or childTint ~= nil then
		if inherited ~= nil and inherited.disabled == disabled and inherited.tint == childTint then
			out = inherited -- the same answer this node was handed: share the table
		elseif previous ~= nil and previous.disabled == disabled and previous.tint == childTint then
			out = previous -- unchanged: descendants keep the reference they hold
		else
			out = { disabled = disabled, tint = childTint }
		end
	end
	--[[ `outSame` IS THE STOP CONDITION FOR THE RE-WALK, and it is a different
		question from whether this node moved. A container that declares its OWN tint
		never moves when that tint changes — its `inheritedTint` is nil either way —
		while everything below it moves, which is exactly the bound-container case.
		So the walk descends on what this node HANDS DOWN, not on what it wears. ]]
	local outSame = sameRecord(out, previous)
	node.inheritOut = out
	return out, disabledMoved, tintMoved, outSame
end

-- STRUCTURAL TRANSITIONS. An optional
-- collaborator — supplied by the render/presenter layer, scripted in headless
-- tests — that turns a structural REMOVAL into a RETIREMENT: the subtree stays in
-- `children`, is marked `retiring` (so the presenter's focus walk and the tap
-- routing skip it), and only disposes when the collaborator says the exit is over.
--
-- The mount layer owns lifetime and identity; the collaborator owns time. That
-- split is why the hard cap lives in the coordinator: this module has no clock and
-- must not grow one.
--
-- `shouldRetire` returns the resolved spec, or nil for "dispose now" (no declared
-- transition, an `instant` exit, or a collaborator that declines). `release` is
-- the teardown seam: the region's scope is going away, so drop any motion still
-- running for that path — optional, so a minimal collaborator need not implement it.
export type Transitions = {
	shouldRetire: (path: string, node: any) -> any?,
	beginExit: (path: string, node: any, spec: any, done: () -> ()) -> (),
	cancelExit: (path: string) -> (),
	beginEnter: (path: string, node: any, spec: any) -> (),
	release: ((path: string) -> ())?,
}

-- THE SEMANTIC FEEDBACK SINK (round 2 §3.3), the second optional collaborator
-- and exactly the same shape of seam as `transitions`: supplied by the
-- presentation layer (the presenter passes its own bus), scripted in headless
-- tests, absent in a bare mount. It exists because `UI.sensoryFeedback` is
-- declared on a BLUEPRINT and fires on a MOUNTED node's lifetime — the observer
-- must die exactly when the node unmounts, which is the node scope this module
-- owns and nothing downstream has.
--
-- The mount layer says WHAT HAPPENED and WHERE. It never decides what an event
-- means, and it plays nothing (`src/present/feedback.luau:4-5`).
export type FeedbackSink = (event: { type: string, path: string }) -> ()

export type MountOpts = {
	scope: any?,
	transitions: Transitions?,
	feedback: FeedbackSink?,
}

local mountLib = {}

-- CLOSED OPTS (constitution §4). `scope` misspelled means the mount owns
-- its own root scope and the caller's dispose frees nothing.
local MOUNT_OPTS_KEYS = specGuard.keySet({ "scope", "transitions", "feedback" })

function mountLib.mount(core: any, rootBlueprint: Blueprint, opts: MountOpts?)
	specGuard.assertKnownKeys("mount", opts, MOUNT_OPTS_KEYS, "opts")
	local rootScope = if opts and opts.scope then opts.scope else core:scope("mount-root")
	local transitions: Transitions? = if opts then opts.transitions else nil
	local feedbackSink: FeedbackSink? = if opts then opts.feedback else nil

	-- drop a coordinator's motion for a path whose region is being torn down
	local function releaseTransition(path: string)
		local t = transitions
		if t ~= nil then
			if t.release ~= nil then
				t.release(path)
			else
				t.cancelExit(path)
			end
		end
	end
	local counters = { mounted = 0, factoryRuns = 0 }
	local dirtyQueue: { { path: string, class: string, prop: string? } } = {}
	--[[ A MONOTONIC COUNT OF EVERY DIRTY EVER PUSHED, never reset by `takeDirty`.
		`#dirtyQueue` answers "how much is pending", which is not the question the
		renderer's solve-feedback check asks — it asks "did anything dirty the tree
		since the moment I marked", and a `takeDirty` between the mark and the check
		makes a length comparison silently answer no. Read through `root.dirtySeq()`.
	]]
	local dirtySeq = 0

	local function pushDirty(path: string, class: string, prop: string?)
		dirtySeq += 1
		table.insert(dirtyQueue, { path = path, class = class, prop = prop })
	end

	local mountNode -- forward

	-- run a structural factory under the nearest enclosing error boundary
	-- (§17 Phase 4): at mount time errors stay hard unless a boundary catches
	-- them; at rebuild time an uncaught error is quarantined by the core's
	-- observer pcall, while a boundary swaps its subtree to the fallback view
	local function guarded<T>(boundary: any, produce: () -> T): (boolean, T?)
		if boundary == nil then
			local value = produce()
			return true, value
		end
		local ok, result = pcall(produce)
		if ok then
			return true, result :: T?
		end
		boundary.trip(result)
		return false, nil
	end

	--[[ structural region: When

		THE BRANCH SCOPE IS HANDED TO THE FACTORY — `thenView(branchScope)`, the
		symmetric twin of `ForEach`'s `row(item, itemScope)` below
		(docs/reference/api.md §When, built 2026-08-15). The lifetime already
		existed and was simply not passed: `branchScope` is created one line above
		each factory call and disposed on branch exit, so a panel that owns a
		MotionValue, a timer or an async handle can own it HERE instead of hoisting
		it to the enclosing scope, where it outlives the panel. Ignoring the
		argument stays valid — every `thenView() -> Blueprint` written before this
		is unchanged.

		AND WHY THERE IS NO `elseView` TO HAND A SECOND SCOPE TO. The false case is
		a second `UI.When` with an inverted condition, which is its OWN region with
		its OWN `scope:child(path .. "/then")`; the two branches therefore cannot
		share a lifetime even by accident. An `elseView` prop would have to answer
		"same scope or sibling", and the only safe answer is SIBLING — one shared
		scope would carry a resource the false branch allocated into the true
		branch on the next flip, which is the hoisted-state leak this change closes
		wearing a different costume. A sibling scope is exactly what two `When`s
		already give you, for one more line and no new idiom, so the prop buys
		nothing and adds a way to get the lifetime wrong. Refused deliberately; see
		`tests/mount.spec.luau`, "a flip back gets a FRESH scope". ]]
	local function mountWhen(
		bp: Blueprint,
		path: string,
		scope: any,
		boundary: any,
		activation: string?,
		inStack: boolean?,
		inherited: any
	): any
		local node: any = {
			class = "When",
			path = path,
			children = {},
			factoryRuns = 0,
			branchScope = nil,
			-- the inherited record a LATER branch mount reads. Read off the node
			-- rather than captured, because a re-cascade updates it in place: a
			-- branch entered after an ancestor flipped must inherit the CURRENT
			-- answer, not the one that was true when the region was mounted
			inheritFrom = inherited,
		}
		local branchPath = path .. "/then"
		-- the declared transition, stamped onto the branch root so a collaborator
		-- can read it off the node it is asked about
		local declared = if transitions ~= nil then bp.props.transition else nil
		local coord = transitions :: any
		-- the subtree that is on its way out: still mounted, still in `children`,
		-- non-interactive, holding its own scope until the exit completes
		local retiring: any = nil -- { mounted, scope, finished }

		scope:own(function()
			-- the region itself is going away mid-exit: drop the motion and let the
			-- retiring scope die with its parent (a second dispose here would be one
			-- too many — the scope is still this scope's child)
			if retiring ~= nil then
				retiring.finished = true
				local held = retiring
				retiring = nil
				releaseTransition(held.mounted.path)
			end
		end)

		-- returns true when the branch RETIRED (and must not be disposed here)
		local function beginRetire(mounted: any): boolean
			local spec = coord.shouldRetire(mounted.path, mounted)
			if spec == nil then
				return false
			end
			mounted.retiring = true
			local held = { mounted = mounted, scope = node.branchScope, finished = false }
			retiring = held
			node.branchScope = nil -- the retiring subtree owns its scope until done
			coord.beginExit(mounted.path, mounted, spec, function()
				-- `done` may fire on this very frame (an instant form, or reduced
				-- motion), later, or at the coordinator's hard cap — and never after
				-- the branch was re-entered or the region disposed
				if held.finished or retiring ~= held then
					return
				end
				held.finished = true
				retiring = nil
				local index = table.find(node.children, mounted)
				if index ~= nil then
					table.remove(node.children, index)
				end
				if not held.scope:isDisposed() then
					held.scope:dispose()
				end
				pushDirty(path, "structure")
			end)
			return true
		end

		local function setBranch(on: boolean)
			if on and retiring ~= nil then
				-- RE-ENTRY MID-EXIT: the same mounted subtree comes back —
				-- same node table, same instances, same factoryRuns, same scope. The
				-- coordinator reverses from the current presentation values, so a
				-- smooth reversal falls out of the model instead of being a case.
				local held = retiring
				retiring = nil
				held.finished = true
				coord.cancelExit(held.mounted.path)
				node.branchScope = held.scope
				held.mounted.retiring = nil
				node.children = { held.mounted }
				coord.beginEnter(held.mounted.path, held.mounted, declared)
				pushDirty(path, "structure")
				return
			end
			if not on and declared ~= nil and node.branchScope ~= nil and node.children[1] ~= nil then
				if beginRetire(node.children[1]) then
					-- the subtree is still mounted but no longer interactive, which
					-- IS a structural change to every consumer of the mounted tree
					pushDirty(path, "structure")
					return
				end
			end
			if node.branchScope ~= nil then
				node.branchScope:dispose()
				node.branchScope = nil
				node.children = {}
			end
			if on then
				local branchScope = scope:child(branchPath)
				node.branchScope = branchScope
				local ok, mounted = guarded(boundary, function()
					return mountNode(
						bp.props.thenView(branchScope),
						branchPath,
						branchScope,
						1,
						boundary,
						activation,
						inStack,
						node.inheritFrom
					)
				end)
				if not ok then
					return -- the boundary swapped to its fallback
				end
				node.children = { mounted }
				if declared ~= nil then
					mounted.transition = declared
					coord.beginEnter(mounted.path, mounted, declared)
				end
			end
			pushDirty(path, "structure")
		end
		scope:own(core:observe(bp.props.condition, function(on)
			setBranch(on == true)
		end))
		-- initial state, without a spurious initial dirty entry
		local initial = bp.props.condition:get() == true
		if initial then
			local branchScope = scope:child(branchPath)
			node.branchScope = branchScope
			local mounted = mountNode(
				bp.props.thenView(branchScope),
				branchPath,
				branchScope,
				1,
				boundary,
				activation,
				inStack,
				node.inheritFrom
			)
			node.children = { mounted }
			if declared ~= nil then
				mounted.transition = declared
				coord.beginEnter(mounted.path, mounted, declared)
			end
		end
		return node
	end

	--[[ A ForEach ITEM ROOT SPLICED INTO A STACK IS A ROW (Plan D, D6a) — the fact
		`render/instance_boundary`'s fifth coordinate-space trigger asks for, and the
		only node that may carry it.

		WHY MOUNT, AND WHY ONLY HERE. A region is spliced into the enclosing flow by
		`render/layout_node`, so by the time the solver sees a row its parent is the
		stack's flow and the region has vanished — mount is the one pass that still
		knows the authored parent. And the population is deliberately the ForEach's
		items ALONE, not every stack inside a stack: the lever this fact buys is the
		LIST SHIFT (a reorder/insert/remove moves every row below it, and a hosted row
		is one rect write instead of one per box), which only a keyed region produces.
		Every other stack-in-stack would pay a real Instance for a shift it never has —
		measured on `tools/lune/check_elision_census`'s fixture, where the broader rule
		gave back 40 of 61 elisions on 20 rows and the narrow one gives back none.

		A structural row (a `When` as the item root) still THREADS the fact down, so
		the branch it splices in is the row; only the layout node it produces is
		stamped, because `createOptsFor` is asked of nothing else. ]]
	local function markRow(mounted: any, inStack: boolean?)
		if inStack == true and mounted ~= nil then
			mounted.inStack = true
		end
	end

	-- structural region: ForEach (add/remove/move only, §5.4)
	local function mountForEach(
		bp: Blueprint,
		path: string,
		scope: any,
		boundary: any,
		activation: string?,
		inStack: boolean?,
		inherited: any
	): any
		local node: any = {
			class = "ForEach",
			path = path,
			-- the inherited record a LATER row mount reads (see `mountWhen`)
			inheritFrom = inherited,
			children = {},
			factoryRuns = 0,
			itemsByKey = {},
		}
		-- rows on their way out, by key: still mounted, still in `children` at the
		-- slot they held, non-interactive, disposed when their exit completes
		local retiring: { [string]: any } = {}
		local declared = if transitions ~= nil then bp.props.transition else nil
		local coord = transitions :: any

		scope:own(function()
			for _, held in retiring do
				held.finished = true
				releaseTransition(held.entry.mounted.path)
			end
			table.clear(retiring)
		end)

		local function apply(items: { any })
			local wanted: { [string]: any } = {}
			local order: { string } = {}
			for _, item in items do
				local key = tostring(bp.props.key(item))
				if wanted[key] ~= nil then
					error(`Facet ForEach {path}: duplicate key '{key}' (duplicate keys are hard errors)`, 0)
				end
				wanted[key] = item
				table.insert(order, key)
			end
			local changed = false
			--[[ THE UNGUARDED ROW-FACTORY THROW (2026-08-17).

				With no ErrorBoundary above it a throwing `row` factory used to
				unwind `apply` from the middle of the ADD phase, after the REMOVE
				phase had already disposed the rows that left. What survived was a
				`node.children` array still pointing at disposed rows, with no
				`structure` dirty queued — and structuralSync only runs on a
				`structure` entry, so the renderer kept those rows' Instances on
				screen, frozen, for the rest of the session.

				The rebuild now COMPLETES. The throwing key is simply absent from
				`itemsByKey`, so the rows that left stay gone, the children array is
				rebuilt from the survivors in the new order, the `structure` dirty is
				pushed, and the next update retries the row that threw. The error is
				re-raised once the tree is consistent, so containment is exactly
				where it was: the observer's quarantine records it on
				`core:lastError` and the writer still returns.

				With a boundary nothing changes — `guarded` trips it and `apply`
				returns, leaving the fallback path it has always taken. ]]
			local deferredError: any = nil
			-- exits and enters run AFTER the children array is rebuilt, so a form
			-- that completes on the spot (instant, reduced motion) removes a row the
			-- rebuild has already placed rather than one it is about to
			local exits: { { key: string, node: any, spec: any } } = {}
			local enters: { { node: any } } = {}
			-- remove
			for key, entry in node.itemsByKey do
				if wanted[key] == nil then
					local spec = if declared ~= nil then coord.shouldRetire(entry.mounted.path, entry.mounted) else nil
					if spec ~= nil then
						entry.mounted.retiring = true
						retiring[key] = {
							entry = entry,
							-- the slot it held; re-inserted there (clamped) on every
							-- rebuild so a departing row exits IN PLACE
							index = table.find(node.children, entry.mounted) or (#node.children + 1),
							finished = false,
						}
						table.insert(exits, { key = key, node = entry.mounted, spec = spec })
					else
						entry.scope:dispose()
					end
					node.itemsByKey[key] = nil
					changed = true
				end
			end
			-- add
			for _, key in order do
				if node.itemsByKey[key] == nil then
					local rowPath = `{path}/[{key}]`
					local held = retiring[key]
					if held ~= nil then
						-- RE-ENTRY MID-EXIT: the same key came back, so the same
						-- mounted row comes back with it (identity, scope, instances)
						held.finished = true
						retiring[key] = nil
						coord.cancelExit(held.entry.mounted.path)
						held.entry.mounted.retiring = nil
						node.itemsByKey[key] = held.entry
						coord.beginEnter(held.entry.mounted.path, held.entry.mounted, declared)
						changed = true
						continue
					end
					local itemScope = scope:child(rowPath)
					-- the item scope rides along so row factories can own
					-- item-scoped resources (async handles, per-row memos —
					-- §10.3/§10.5); ignoring the second argument stays valid
					local produce = function()
						local built = mountNode(
							bp.props.row(wanted[key], itemScope),
							rowPath,
							itemScope,
							1,
							boundary,
							activation,
							inStack,
							node.inheritFrom
						)
						markRow(built, inStack)
						return built
					end
					local mounted
					if boundary ~= nil then
						local ok, produced = guarded(boundary, produce)
						if not ok then
							return -- the boundary swapped to its fallback
						end
						mounted = produced
					else
						local ok, produced = pcall(produce)
						if not ok then
							-- skip THIS row and keep rebuilding (see the block above);
							-- the partial subtree the factory managed to mount goes
							-- with its scope so the counters stay honest
							if not itemScope:isDisposed() then
								itemScope:dispose()
							end
							if deferredError == nil then
								deferredError = produced
							end
							continue
						end
						mounted = produced
					end
					node.itemsByKey[key] = {
						scope = itemScope,
						mounted = mounted,
					}
					if declared ~= nil then
						mounted.transition = declared
						table.insert(enters, { node = mounted })
					end
					changed = true
				end
			end
			-- order (a pure move changes children order, never remounts)
			local newChildren = {}
			for _, key in order do
				-- a key whose factory threw has no entry (see `deferredError`); the
				-- rebuild is over the SURVIVORS, in the new order
				local entry = node.itemsByKey[key]
				if entry ~= nil then
					table.insert(newChildren, entry.mounted)
				end
			end
			-- retiring rows keep their previous slot, clamped to the new length;
			-- lowest recorded slot first so several exits stay in their old order
			local held: { any } = {}
			for _, record in retiring do
				table.insert(held, record)
			end
			table.sort(held, function(a, b)
				return a.index < b.index
			end)
			for _, record in held do
				table.insert(newChildren, math.min(record.index, #newChildren + 1), record.entry.mounted)
			end
			local orderChanged = #newChildren ~= #node.children
			if not orderChanged then
				for i, child in newChildren do
					if node.children[i] ~= child then
						orderChanged = true
						break
					end
				end
			end
			node.children = newChildren
			if changed or orderChanged then
				pushDirty(path, "structure")
			end
			for _, exit in exits do
				local record = retiring[exit.key]
				if record ~= nil then
					coord.beginExit(exit.node.path, exit.node, exit.spec, function()
						if record.finished or retiring[exit.key] ~= record then
							return
						end
						record.finished = true
						retiring[exit.key] = nil
						local index = table.find(node.children, record.entry.mounted)
						if index ~= nil then
							table.remove(node.children, index)
						end
						if not record.entry.scope:isDisposed() then
							record.entry.scope:dispose()
						end
						pushDirty(path, "structure")
					end)
				end
			end
			for _, enter in enters do
				coord.beginEnter(enter.node.path, enter.node, declared)
			end
			if deferredError ~= nil then
				-- the tree is consistent now; hand the throw back to whoever opened
				-- this pass so containment stays where it was
				error(deferredError, 0)
			end
		end
		scope:own(core:observe(bp.props.items, function(items)
			apply(items)
		end))
		-- initial mount without a structure-dirty entry
		local initialItems = bp.props.items:get()
		local order: { string } = {}
		local seen: { [string]: boolean } = {}
		for _, item in initialItems do
			local key = tostring(bp.props.key(item))
			if seen[key] then
				error(`Facet ForEach {path}: duplicate key '{key}' (duplicate keys are hard errors)`, 0)
			end
			seen[key] = true
			local itemScope = scope:child(`{path}/[{key}]`)
			local built = mountNode(
				bp.props.row(item, itemScope),
				`{path}/[{key}]`,
				itemScope,
				1,
				boundary,
				activation,
				inStack,
				node.inheritFrom
			)
			markRow(built, inStack)
			node.itemsByKey[key] = { scope = itemScope, mounted = built }
			table.insert(order, key)
		end
		for _, key in order do
			table.insert(node.children, node.itemsByKey[key].mounted)
		end
		if declared ~= nil then
			for _, key in order do
				local mounted = node.itemsByKey[key].mounted
				mounted.transition = declared
				coord.beginEnter(mounted.path, mounted, declared)
			end
		end
		return node
	end

	-- error boundary (§17 Phase 4): mounts view() under its own standalone
	-- scope; a factory error at mount or during any structural rebuild inside
	-- the subtree trips the boundary — the view scope is disposed and
	-- fallback(err) mounts in its place (once; fallback errors stay hard).
	-- The content scope is standalone (not scope:child) so tripping can
	-- dispose it early without a double-dispose at teardown; the boundary's
	-- scope owns a guard closure that disposes whichever content scope is
	-- current.
	local function mountErrorBoundary(
		bp: Blueprint,
		path: string,
		scope: any,
		_boundary: any,
		activation: string?,
		inStack: boolean?,
		inherited: any
	): any
		local node: any = {
			class = "ErrorBoundary",
			path = path,
			-- the inherited record a LATER fallback/view mount reads (see `mountWhen`)
			inheritFrom = inherited,
			children = {},
			factoryRuns = 0,
		}
		local contentScope: any = nil
		local tripped = false
		scope:own(function()
			if contentScope ~= nil and not contentScope:isDisposed() then
				contentScope:dispose()
			end
		end)
		local function mountFallback(err: any)
			tripped = true
			if contentScope ~= nil and not contentScope:isDisposed() then
				contentScope:dispose()
			end
			node.children = {}
			contentScope = core:scope(path .. "/fallback")
			node.children = {
				mountNode(
					bp.props.fallback(err),
					path .. "/fallback",
					contentScope,
					1,
					nil,
					activation,
					inStack,
					node.inheritFrom
				),
			}
			pushDirty(path, "structure")
		end
		local boundary = {
			trip = function(err: any)
				if not tripped then
					mountFallback(err)
				end
			end,
		}
		contentScope = core:scope(path .. "/view")
		local ok, result = pcall(function()
			return mountNode(
				bp.props.view(),
				path .. "/view",
				contentScope,
				1,
				boundary,
				activation,
				inStack,
				node.inheritFrom
			)
		end)
		if ok and not tripped then
			node.children = { result }
		elseif not tripped then
			mountFallback(result)
		end
		return node
	end

	-- THE STRUCTURAL REGIONS, and the bookkeeping every one of them owes: it is
	-- one mounted node with `factoryRuns == 1`, and it decrements the live count
	-- when its scope dies. That tail used to be copied per region (Step 5.5
	-- cleanup ledger C-05), so a fourth region meant remembering to copy it
	-- correctly a fourth time; now it is one table entry.
	-- `mountErrorBoundary` takes no boundary of its own — it CREATES one — so the
	-- extra argument is deliberately ignored there.
	local STRUCTURAL: { [string]: (Blueprint, string, any, any, string?, boolean?, any) -> any } = {
		ErrorBoundary = mountErrorBoundary,
		When = mountWhen,
		ForEach = mountForEach,
	}

	--[[ THE INHERITED CHANNELS' REACTIVE HALF. A container's `enabled` / `tint` is
		an ordinary reactive prop — the per-prop observer in `mountNode` writes
		`node.props` and pushes this node's own dirt — and this is what carries the
		change to the SUBTREE: it re-resolves each descendant against the record its
		parent now hands down, and pushes dirt only where a derived value actually
		moved, so re-declaring the same value costs one walk and no writes.

		THE PROP NAMES ARE `enabled` AND `tint` because those are the names the
		renderer's refresh loop already dispatches on: a descendant that inherited a
		disable is re-applied through the same seam as one that declared it, so there
		is no second write site and no second state channel.

		A FLIP IS A GESTURE, NOT A FRAME — a panel switched off, a hue dragged — so an
		honest O(touched) subtree walk beats keeping a second index in sync, and the
		walk stops the moment a node hands its children the answer they already had. ]]
	local function recascade(node: any, inherited: any)
		local childInherit, disabledMoved, tintMoved, outSame = applyInherited(node, inherited)
		--[[ A STRUCTURAL REGION IS WALKED THROUGH, NEVER DIRTIED. It carries no `dirty`
			table because it materializes nothing — no instance, no paint, no focus stop —
			so an entry naming its path would send the renderer's refresh loop to a node
			with no props to write. The nodes it splices into the flow push their own. ]]
		local dirtyOf = node.dirty
		if dirtyOf ~= nil and disabledMoved then
			dirtyOf.paint = true
			dirtyOf.semantics = true
			dirtyOf.navigation = true
			pushDirty(node.path, "paint", "enabled")
			pushDirty(node.path, "semantics", "enabled")
			pushDirty(node.path, "navigation", "enabled")
		end
		if dirtyOf ~= nil and tintMoved then
			dirtyOf.paint = true
			pushDirty(node.path, "paint", "tint")
		end
		if outSame then
			return
		end
		for _, child in node.children do
			recascade(child, childInherit)
		end
	end

	mountNode = function(
		bp: Blueprint,
		parentPath: string,
		scope: any,
		index: number,
		boundary: any,
		inheritedActivation: string?,
		inStack: boolean?,
		inherited: any
	): any
		local id = bp.id or `{bp.class}#{index}`
		local path = parentPath .. "/" .. id
		local mountStructural = STRUCTURAL[bp.class]
		if mountStructural ~= nil then
			local node = mountStructural(bp, path, scope, boundary, inheritedActivation, inStack, inherited)
			--[[ A REGION IS A NODE THE CASCADE HAS TO KNOW ABOUT. It declares neither
				channel, so it hands its children exactly the record it was handed — but
				the RE-WALK compares against `node.inheritOut`, and a region that never
				recorded one would report "the same answer as before" the first time an
				ancestor flipped and stop the walk at the region's own door. Resolving it
				here (after the initial branch, which mounted with the same record) is
				what makes a `When` branch follow its panel. ]]
			applyInherited(node, inherited)
			node.id = id
			counters.mounted += 1
			counters.factoryRuns += 1
			node.factoryRuns = 1
			scope:own(function()
				counters.mounted -= 1
			end)
			return node
		end

		-- ordinary node: factory runs ONCE here
		counters.mounted += 1
		counters.factoryRuns += 1
		local node: any = {
			class = bp.class,
			id = id,
			path = path,
			props = {}, -- resolved static values; dynamic props tracked below
			-- library-internal metadata channel (input contributions): copied
			-- verbatim, never observed, never rendered, never dumped
			meta = bp.meta,
			dynamicProps = {},
			dirty = {},
			factoryRuns = 1,
			children = {},
		}
		scope:own(function()
			counters.mounted -= 1
		end)

		local dirtyMap = blueprintLib.PROP_DIRTY[bp.class] or {}
		for propName, value in bp.props do
			if blueprintLib.isReadable(value) then
				node.dynamicProps[propName] = value
				node.props[propName] = value:get()
				local classes = dirtyMap[propName] or { "paint" }
				scope:own(core:observe(value, function(newValue)
					node.props[propName] = newValue
					for _, dirtyClass in classes do
						node.dirty[dirtyClass] = true
						pushDirty(path, dirtyClass, propName)
					end
					-- ...and where the prop is one of the two INHERITED channels, the
					-- subtree it declares for is re-resolved from this new value
					if INHERITED_PROPS[propName] then
						recascade(node, node.inheritFrom)
					end
				end))
			else
				node.props[propName] = value
			end
		end

		-- THE OFF-PATH COST IS ONE NIL CHECK. `meta` is absent on the overwhelming
		-- majority of nodes (it exists only where a modifier put something there),
		-- and the cascade below now runs for every node rather than only when a
		-- feedback sink is wired — so the read is gated on the channel existing at
		-- all rather than being paid per node on every mount in the framework.
		local declarations = if bp.meta ~= nil then feedbackContract.readDeclarations(node) else nil

		-- SENSORY FEEDBACK, THE CONTROL FORM (round 3): the cascade. Resolved
		-- HERE because this is the only walk that sees a blueprint's ancestors and
		-- its mounted node at the same moment, and it is resolved for EVERY node
		-- rather than only the activatable ones, because "activatable" is a render
		-- fact this layer must not learn. `nil` when nothing above declared, so an
		-- undeclared tree stores no field at all and the off path costs one table
		-- read per node.
		--
		-- It is read (not observed): a blueprint is frozen, so a declaration cannot
		-- change without a remount, and the remount re-inherits from this same
		-- parameter — which is why a `When` branch re-entered later still feels
		-- like the panel it is inside.
		local activationFeedback = feedbackContract.activationIn(declarations) or inheritedActivation
		if activationFeedback ~= nil then
			node.activationFeedback = activationFeedback
		end

		-- THE INHERITED CHANNELS, resolved for this node and for the record its
		-- children receive. `nil` in, `nil` out on an undeclared tree: the fields are
		-- never written and the off path costs one table read per node.
		local childInherit = applyInherited(node, inherited)

		-- ...and the CHANGE form (round 2 §3.3): one observer per declaration,
		-- owned by this node's scope, so it stops the frame the node unmounts.
		-- Built ONLY when a sink is wired — a mount with no presentation layer has
		-- no bus to emit on, and an observer nobody can hear is pure cost.
		local sink = feedbackSink
		if sink ~= nil and declarations ~= nil then
			for _, decl in declarations do
				-- the control form has no Readable to watch: its cause is a press,
				-- which the presenter owns. Skipping it here is what keeps
				-- `core:observe` from being handed a nil trigger.
				if decl.trigger ~= nil then
					scope:own(core:observe(decl.trigger, function()
						-- a FRESH table per emission: the presenter stamps `surface`
						-- onto the event it is handed, and a shared table would carry
						-- one surface's stamp into the next emission
						sink({ type = decl.event, path = path })
					end))
				end
			end
		end

		-- duplicate explicit sibling ids are hard errors; generated ids are
		-- position-unique by construction
		if bp.children then
			local seen: { [string]: boolean } = {}
			for i, childBp in bp.children do
				local childId = childBp.id or `{childBp.class}#{i}`
				if seen[childId] then
					error(`Facet mount {path}: duplicate child id '{childId}'`, 0)
				end
				seen[childId] = true
				table.insert(
					node.children,
					mountNode(
						childBp,
						path,
						scope,
						i,
						boundary,
						activationFeedback,
						STACK_PARENT[bp.class],
						childInherit
					)
				)
			end
		end
		return node
	end

	-- MICROPROFILER PHASE `Facet/mount` (roadmap Step 9): the INITIAL tree build.
	-- The same scope name the renderer's structural sync uses, because they are the
	-- same question — how much does making and un-making this tree cost — and a
	-- mount-ramp profile wants one bar that grows with row count, not two.
	local rootNode = profile.span("mount", function()
		return mountNode(rootBlueprint, "", rootScope, 1)
	end)

	local function dumpNode(node: any): any
		local dirty = {}
		for _, c in DIRTY_CLASSES do
			if node.dirty and node.dirty[c] then
				table.insert(dirty, c)
			end
		end
		local d: any = {
			id = node.id,
			path = node.path,
			class = node.class,
			factoryRuns = node.factoryRuns,
			dirty = dirty,
		}
		if #node.children > 0 then
			d.children = {}
			for _, child in node.children do
				table.insert(d.children, dumpNode(child))
			end
		end
		return d
	end

	local root = {
		node = rootNode,
		dispose = function()
			profile.span("mount", function()
				rootScope:dispose()
			end)
		end,
		takeDirty = function(): { { path: string, class: string, prop: string? } }
			local taken = dirtyQueue
			dirtyQueue = {}
			return taken
		end,
		-- see `dirtySeq` above: monotonic, survives `takeDirty`
		dirtySeq = function(): number
			return dirtySeq
		end,
		counters = function()
			return table.clone(counters)
		end,
		dump = function()
			return { schema = "facet-mount-dump/1", tree = dumpNode(rootNode) }
		end,
	}
	return root
end

return mountLib
