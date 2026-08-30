--!strict
--[[ ONE MOUNT, ONE ENGINE SCROLL MIRROR — the arbitration every virtualized
	collection shares (O-31).

	WHAT IT IS FOR. A virtualized collection windows its rows against `scrollTop`,
	and `scrollTop` is written by an engine `CanvasPosition` mirror. Until 2026-08-15
	that mirror only existed if the CONSUMER called `bindNativeScroll(controller)`
	after `present`, and a consumer who forgot got a control that mounted, painted,
	took taps, and windowed its FIRST LINES FOREVER — measured live in Studio, an
	engine scroll to y=2000 leaving a grid's window at `c1..c16`. A census of the
	showcase demos on the same day found five of nine callers outside the tests
	omitting it, so the framework binds it itself now and the public call is an
	override rather than an obligation. The auto-bind contract is pinned by
	`tests/native_scroll_autobind.spec.luau` and documented in
	`docs/reference/api.md` (`bindNativeScroll`).

	WHY THE ARBITRATION IS ITS OWN MODULE AND NOT THREE COPIES. `virtual_list`,
	`virtual_grid` (both axes) and `table` each install a DIFFERENT mirror — the
	list arms its reorder registry with it, the table adds the row-actions
	tray-close on the same path — but they arbitrate identically: at most one
	mirror at a time, an explicit consumer bind that lands on the same
	(controller, path) must not add a second engine observer, and an explicit
	unbind must stick. Three copies of that is the shape this codebase already
	refuses elsewhere (`virtual_grid.luau`, "Two intercepts differing only in a
	direction pair is the shape a general mechanism is owed"). `install` is the
	only thing that varies, so it is the only thing passed in.

	THE TWO PRESENTER SEAMS IT RIDES, and why they are not `buildFocusGroups`.
	O-31 proposed handing the controller through `buildFocusGroups(rootNode)`,
	"the one seam that hands a control its own mounted path". It is not: the
	presenter calls a contribution's `focusGroups` only from `focus_map.autoGroups`,
	which runs only when the consumer left `opts.navigationGroups` ABSENT. Measured
	across four presenter configurations (`tests/native_scroll_autobind.spec.luau`
	quotes the table): `focusGroups` fires 2, 0, 0, 0 while `bindController` fires
	1, 1, 1, 1 and `syncGeometry` fires 3, 3, 3, 3. So the seams used here are:

	  · `bindController(controller)` -> `noticeController`, once per discovered
	    bundle, at present and on a structural sync;
	  · `syncGeometry(rectOf, node)` -> `noticeMount`, on every refresh AND every
	    solve, carrying the control's own MOUNTED NODE.

	IDENTITY, NOT PATH, IS THE MOUNT KEY. The node table handed to `syncGeometry`
	is stable across plain refreshes and FRESH after a remount — measured, including
	a remount back to the same path, which a path comparison cannot see. That is
	what makes the mirror self-healing across a `UI.When` flip: RascalRally's Sponsor
	HUD hand-rolls the path comparison for exactly this reason and its own comment
	says the bind "would go stale across a pose flip".

	AN EXPLICIT UNBIND STICKS. `noticeMount` re-asserts only when the MOUNT changes,
	never per frame, so `unbindNativeScroll()` is not a one-frame suggestion — it is
	still the one thing a consumer can say about the mirror.

	THERE IS NO OPT-OUT KEY, and that is deliberate. The only collection whose
	scrolling is genuinely owned elsewhere is a `newTable{ scrolls = false }` block
	table, which owns no `ScrollingFrame` and already publishes that fact as
	`api.scrollPath() == nil` (ruling 3, O-10). `noticeMount` passes that nil
	straight through, and the table's own `install` mirrors nothing while still
	binding its tray-close to the real scrolling ancestor — so the opt-out is the
	control's own published scroll path, one general mechanism, expressed where the
	answer already lived. A `newVirtualList`/`newVirtualGrid` always mounts its own
	`ScrollView`, so neither has such a state to be in.

	Public interface: `nativeScrollBinding.new(install) -> { bind, noticeController,
	noticeMount }`. Depends on nothing.
]]

export type Binding = {
	-- the control's public `bindNativeScroll` body. Idempotent per
	-- (controller, path): the same pair hands back the SAME stop function rather
	-- than installing a second engine observer.
	bind: (controller: any, path: string?) -> () -> (),
	-- from the contribution's `bindController`
	noticeController: (controller: any) -> (),
	-- from the contribution's `syncGeometry`. `path` is the control's OWN scroll
	-- host, and nil means it has none — a `newTable{ scrolls = false }` block
	-- table. `install` still runs for a nil path, because a control with no canvas
	-- of its own may still have something to wire against the page that carries it
	-- (Table's row-actions tray-close); it simply mirrors nothing.
	noticeMount: (node: any, path: string?) -> (),
}

local nativeScrollBinding = {}

function nativeScrollBinding.new(install: (controller: any, path: string?) -> () -> ()): Binding
	-- the controller the presenter contributed; never cleared, because an unbind
	-- ends a MIRROR and not the control's relationship with the renderer
	local contributedController: any = nil
	-- the mounted node this binding last acted on (identity, see the header)
	local noticedNode: any = nil
	local activeController: any = nil
	local activePath: string? = nil
	local activeUnsub: (() -> ())? = nil
	-- `activePath` is legitimately nil for a live binding (the block table), so
	-- "is anything bound" is `activeUnsub`, never the path
	local bound = false

	-- ONE stop function, handed to every caller, so the framework's auto-bind and
	-- a consumer's explicit bind cannot each hold half of the teardown.
	local function stop()
		if not bound then
			return
		end
		local unsub = activeUnsub
		bound = false
		activeUnsub = nil
		activeController = nil
		activePath = nil
		if unsub ~= nil then
			unsub()
		end
	end

	local self: Binding = {} :: any

	function self.bind(controller: any, path: string?): () -> ()
		if bound and activeController == controller and activePath == path then
			return stop
		end
		stop()
		bound = true
		activeController = controller
		activePath = path
		activeUnsub = install(controller, path)
		return stop
	end

	function self.noticeController(controller: any)
		if contributedController == nil then
			contributedController = controller
		end
	end

	function self.noticeMount(node: any, path: string?)
		-- BEFORE the controller arrives there is nothing to bind with, and
		-- recording the mount would spend the one chance this mount had. The
		-- presenter orders these the other way round (`bindContribution` runs
		-- before the first `feedGeometry`), so this is a guard, not a path.
		if node == nil or node == noticedNode or contributedController == nil then
			return
		end
		noticedNode = node
		self.bind(contributedController, path)
	end

	return self
end

return nativeScrollBinding
