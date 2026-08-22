--!strict
--[[ THE HOSTED ROW-ACTIONS HALF of `controls/virtual_list.luau` — the swipe
	gesture, the per-row engines, the shared tray overlay and the keyboard/pad
	route, for a list built with `spec.rowActions`.

	WHY IT IS ITS OWN FILE. `docs/handoff/SOURCE_CAP_LEDGER.md`'s row for
	`virtual_list.luau` named this block by name (`hostedItemExtentIn` through
	`hostedRestoreFocusOnDisengage`, 23% of the file) and made the extraction a
	PRECONDITION rather than a companion: "the next change of any size to this
	file is PRECEDED by the extraction, not accompanied by it". The file was 805
	characters from 193,000 and 7,805 from the 200,000-char Source WRITE cap,
	past which a module stops live-syncing into an open Studio session, silently
	(`docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md`).

	WHAT MADE IT EXTRACTABLE, when the same ledger row recorded that it was NOT
	one-way as written. The block read seven REASSIGNED host scalars — the six
	contribution handoffs (`hostedMotionClock`, `hostedNow`, `hostedActionSystem`,
	`hostedFocusGraph`, `hostedPresentModal`, `hostedDismiss`) plus
	`boundController` — and a reassigned local cannot be shared by reference at
	all, which is exactly why this seam stayed closed. They are now ONE record,
	`deps.delivery`, the same technique `table.luau` proved on 2026-08-18 with
	`rowGesture`. Two more cells joined it for the same reason and no other:
	`scrollPath` (the host's `mountedScrollPath`, written by the focus-group
	derivation and by `syncGeometry`, read here to spell every overlay path) and
	`suppressActivate` (the one-Activate swallow, the only cell BOTH halves
	write — this file arms it from the swipe, the host spends it in
	`handleActivate` and clears it on a cancel).

	THE REST OF THE SEAM IS VALUES AND NEVER-REASSIGNED FUNCTIONS, threaded as an
	explicit dependency table rather than captured, exactly as
	`virtual_window.new` and `virtual_reorder.new` already are in the same host.
	`tests/virtual_list_hosted_seam.spec.luau` is the read-vs-write seam test that
	keeps it that way: READ == DECLARED == PASSED as set comparisons over the live
	sources, the shared WRITE surface pinned by name, and the one-way require
	asserted directly.

	IT IS ONE-WAY MECHANICALLY, NOT ASPIRATIONALLY. This module requires
	`virtual_list.luau` nowhere and names no type from it. The two mounted-path
	ids the HOST also needs (`OVERLAY_ID`, `TRAY_GROUP_ID`) are published from
	here and read there, which is the allowed direction; the path CONTRACT they
	spell is documented once, in `virtual_list.luau`'s own header.

	WHAT STAYED BEHIND. The list's own keyboard/gamepad plumbing, the focus-group
	derivation (it walks the mounted tree and reads `mountedScrollPath` beside
	four non-hosted facts), the render, and the contribution `bundle` — which is
	where every cell of `delivery` is written. ]]

local row_actions = require("./row_actions")
local row_actions_state = require("../input/row_actions_state")
local rowCapability = require("../row_capability")
local specGuard = require("../spec_guard")

local virtual_list_hosted = {}

--[[ THE TWO MOUNTED-PATH IDS, published because the HOST renders the nodes they
	name (the overlay region and the tray group) while everything that READS a
	path built from them lives here. One spelling, two readers, no drift. ]]
virtual_list_hosted.OVERLAY_ID = "RowActionsOverlay"
virtual_list_hosted.TRAY_GROUP_ID = "RowActionsTray"
local HOSTED_OVERLAY_ID = virtual_list_hosted.OVERLAY_ID
local HOSTED_TRAY_GROUP_ID = virtual_list_hosted.TRAY_GROUP_ID
-- "nothing is engaged", as ONE shared empty table: the overlay's items memo
-- answers this for the whole closed life of every hosted list, and a fresh empty
-- table per recompute would dirty the keyed region for no change at all.
local HOSTED_NO_OVERLAY: { any } = {}

-- the closed key set for whatever `spec.rowActions(item)` returns for ONE row —
-- exactly the three fields `newRowActions` exposes besides the ones this control
-- supplies itself (`paths`/`coordinator`/`onSlide`/`onCommitHeight`/`id`).
-- Checked per row, at engine build, with the row's key in the message (§4;
-- newTable's own ROW_ACTIONS_RESULT_KEYS precedent).
local HOSTED_ROW_ACTIONS_KEYS = specGuard.keySet({ "leading", "trailing", "fullSwipe" })

--[[ THE CELLS BOTH HALVES HOLD. Every field here is a scalar that is REASSIGNED
	after this module is constructed, which is the whole reason the record exists:
	a reassigned local cannot be shared by reference, so the two files name the
	same cell instead of each holding a copy that goes stale.

	  · `controller` / `scrollPath` — the bound render controller and the mounted
	    scroll path. The host writes both (the native-scroll seam and
	    `syncGeometry`/`focusGroups`); this file reads them to bind a lazily-built
	    engine and to spell every overlay path.
	  · the six CONTRIBUTION HANDOFFS — what the presenter handed the list's
	    contribution, held so a lazily-built engine can be given the identical
	    handoffs the moment it exists. A hosted engine has no node of its own for
	    the presenter's contribution walk to find, so the host relays (row_actions
	    Task 2 report, "contribution seams").
	  · `suppressActivate` — SWALLOW EXACTLY ONE ACTIVATE, on this path. THREE
	    producers, one rule:
	      * a promoted pointer drag ends with an engine Activated on the origin
	        row (whichever side of InputEnded it lands), or every reorder would
	        also read as a tap on the row it started from;
	      * a HOSTED SWIPE ends the same way, and is armed at the axis lock rather
	        than at the release — see `hostedResolveAxis`, which carries the
	        red-team finding that made it a blocker;
	      * a tap on an OPEN hosted row means "close the tray" and nothing else —
	        iOS parity, and the alternative is a swipe-then-tap opening whatever
	        the row's `onActivate` opens.
	    WHAT MAY SPEND IT is as much of the rule as where it is armed — the lesson
	    is `docs/lessons/an-arm-set-by-a-gesture-must-name-what-may-spend-it.md`,
	    written from this exact seam: all three producers are POINTER gestures
	    leaving a
	    POINTER Activated behind, so a DEVICE Activate (`meta.source == "action"`,
	    no pointer-down anywhere) is never it and never consumed by it. Cleared by
	    the one pointer Activate it swallows, by a cancel, by a device Activate, or
	    by the next down. It is the ONE cell both halves write. ]]
export type Delivery = {
	controller: any,
	scrollPath: string?,
	suppressActivate: string?,
	motionClock: any,
	now: any,
	actionSystem: any,
	focusGraph: any,
	presentModal: any,
	dismiss: any,
}

--[[ EVERY FACT THE HOSTED HALF HAS, BY NAME. The list IS the seam test: a field
	added here is a fact the list decided and handed over; a field this module
	would rather reach for is a require back, and there is nowhere to put one.
	Ordered as `virtual_list.luau` declares them. ]]
export type Deps = {
	Facet: any,
	core: any,
	spec: any,
	id: string,
	listScope: any,
	-- the one record both halves hold (see `Delivery` above)
	delivery: Delivery,
	-- is `spec.rowActions` present at all — every allocation below is behind it
	enabled: boolean,
	rowActions: any,
	windowItems: any,
	indexByKey: any,
	scrollTop: any,
	rowExtentIn: (any, string) -> number,
	rowPathUnder: (string, string) -> string,
	hitPathOf: (string) -> string?,
	mountedRowPath: (string) -> string?,
	itemForKey: (string) -> any?,
}

function virtual_list_hosted.new(deps: Deps)
	local Facet = deps.Facet
	local core = deps.core
	local spec = deps.spec
	local id = deps.id
	local listScope = deps.listScope
	local delivery = deps.delivery
	local hostedEnabled = deps.enabled
	local hostedRowActions = deps.rowActions
	local windowItems = deps.windowItems
	local indexByKey = deps.indexByKey
	local scrollTop = deps.scrollTop
	local rowExtentIn = deps.rowExtentIn
	local rowPathUnder = deps.rowPathUnder
	local hitPathOf = deps.hitPathOf
	local mountedRowPath = deps.mountedRowPath
	local itemForKey = deps.itemForKey

	-- Everything in this section is inert on a list without `spec.rowActions`:
	-- the two plain tables below are the only allocations, they are PER LIST
	-- (never per row), and nothing reactive, no coordinator and no engine is
	-- constructed unless the feature is on.

	--[[ RETENTION POLICY, stated once so nothing has to infer it:
		  * ONE engine per row KEY, built at the moment that row's gesture first
		    resolves horizontal, kept for the life of the LIST — never rebuilt per
		    scroll pass, because a windowed-out row is coming back (that is what
		    virtualization is) and rebuilding would defeat the laziness this whole
		    design exists for. Leaving one behind is safe: any scroll closes the
		    engaged row through the shared coordinator before it can leave the
		    window.
		  * The cache is DROPPED WHOLESALE on a re-present (see
		    `hostedNoticeMount`), because every engine captured its row/tray paths
		    at build and those paths name the previous mount.
		  * Disposal otherwise rides the list scope (registered below):
		    `buildHosted` opens its own independent `core:scope()`, so nothing
		    else would ever free them. ]]
	local hostedEngines: { [string]: any } = {}
	--[[ key -> whatever `spec.rowActions(item)` answered, or `false` for "this
		row has no actions". Cached because the DECIDE-and-DECLINE half runs on
		every press (an unwrapped row must not hold the capture — see the
		dispatcher) while the BUILD half is deferred to the axis lock, and calling
		a consumer callback twice per gesture to answer the same question is a
		cost with no reason.

		CACHED AGAINST THE ITEM, NOT THE KEY ALONE. `spec.rowActions(item)` is a
		function of the item, and a list's items change under a stable key all the
		time — a row locks and unlocks, ownership transfers, a race finishes. A
		key-only cache froze the FIRST press's verdict forever: a row that
		answered nil while locked stayed declined for the rest of the session, and
		a row that lost its actions kept firing them. `hostedItemByKey` records
		which item each answer was derived from, and the rows observer below drops
		the answer AND the engine the moment that identity moves. ]]
	local hostedFieldsByKey: { [string]: any } = {}
	local hostedItemByKey: { [string]: any } = {}
	--[[ mounted hit path -> row key. NEVER parsed out of a path (a data key is
		arbitrary text, so a pattern over `[{key}]` is a guess about what a key may
		contain) — CONSTRUCTED from `windowItems`, which is already this control's
		one source of truth for "which rows are mounted" (`pathOf`/`mountedRowPath`
		derive from it too). Rebuilt only when that memo's identity changes, which
		its own `sameWindow` equality makes exactly "the key sequence changed", so
		a same-window scroll rebuilds nothing and a row costs no registration
		closure at all. ]]
	local hostedKeyByHitPath: { [string]: string } = {}
	local hostedMapWindow: any = nil
	local hostedMapRoot: string? = nil

	-- ONE open row across the whole list (row_actions' own policy object, the
	-- same one Table hands its wrapped rows), and the two signals the Task 4
	-- overlay + presentation slide read: WHICH row is engaged, and by HOW MANY
	-- px. `engagedOffset` is signed exactly as the engine's own offset is
	-- (negative = revealing the trailing edge).

	local hostedCoordinator: any = nil
	local engagedKey: any = nil
	local engagedOffset: any = nil
	--[[ the engine's commit collapse (the height the committing row's box is
		animating down to), forwarded verbatim and composed into that row's
		`rowExtentDim` below. `hostedCommitKey == nil` = no override anywhere.

		TWO SIGNALS, NOT ONE `{ key, px }` TABLE, and the reason is fine-grained
		reactivity: EVERY mounted row's height memo has to read the key (to answer
		"is it me?"), but only the ONE committing row ever reads the px. Split, a
		collapse spring's ~20 per-frame px writes invalidate exactly one memo; as a
		single table they would have invalidated every row in the window, every
		frame of every commit. ]]
	local hostedCommitKey: any = nil
	local hostedCommitPx: any = nil
	if hostedEnabled then
		hostedCoordinator = row_actions.newCoordinator(core)
		engagedKey = listScope:own(core:signal(nil :: string?))
		engagedOffset = listScope:own(core:signal(0))
		hostedCommitKey = listScope:own(core:signal(nil :: string?))
		hostedCommitPx = listScope:own(core:signal(0))
	end

	-- ONE row's height, commit override included: the row box itself and the
	-- overlay's tray group (which fills that same box) read it through here, so a
	-- collapsing row can never leave its tray standing at the old height.
	local function hostedItemExtentIn(use: any, key: string): number
		if use(hostedCommitKey) == key then
			return use(hostedCommitPx)
		end
		return rowExtentIn(use, key)
	end

	-- WHERE THIS ROW'S TRAY WILL MOUNT (see the path contract at the top of the
	-- file). Keyed on the row, because the overlay is a keyed region; the
	-- `{Tray*}When/then/{Tray*}` tail is row_actions' own shape, since the trays
	-- under the group ARE that engine's own `trayViews`.
	-- this row's whole overlay region — the prefix everything a revealed tray
	-- mounts sits under, and therefore the test for "is that path inside THIS
	-- row's tray"
	local function hostedOverlayRowPath(key: string): string?
		local root = delivery.scrollPath
		if root == nil then
			return nil
		end
		return `{root}/Canvas/{HOSTED_OVERLAY_ID}/[{key}]`
	end

	local function hostedTrayPath(key: string, edge: string): string?
		local region = hostedOverlayRowPath(key)
		if region == nil then
			return nil
		end
		local tray = if edge == "leading" then "TrayLeading" else "TrayTrailing"
		return `{region}/{HOSTED_TRAY_GROUP_ID}/{tray}When/then/{tray}`
	end

	local function hostedKeyOfHit(path: string): string?
		local root = delivery.scrollPath
		if root == nil then
			return nil -- not presented: there are no mounted paths to answer with
		end
		local window = windowItems:get() :: { any }
		if hostedMapWindow ~= window or hostedMapRoot ~= root then
			hostedMapWindow = window
			hostedMapRoot = root
			table.clear(hostedKeyByHitPath)
			for _, entry in window do
				hostedKeyByHitPath[rowPathUnder(root, entry.key) .. "/Hit"] = entry.key
			end
		end
		return hostedKeyByHitPath[path]
	end

	--[[ THE LIVE GESTURE, owned by the host. `hostedActiveKey` is the row a press
		is currently on (down .. up/cancel) and `hostedPending` is that gesture
		before its axis has resolved.

		WHY THE KEY IS HELD RATHER THAN LOOKED UP PER EVENT. A row can UNMOUNT
		mid-gesture — scrolled out from under a held finger, or removed from the
		data outright — and the adapter's own remove-then-cancel arrives AFTER the
		row is gone from the window. A path lookup would answer nil at exactly that
		moment, so the engine would never be told its gesture died: its internal
		`drag` would stay non-nil forever, and the "a non-active row may not claim"
		rule below would then refuse that row every future press. Holding the key
		makes the cancel land on the right engine no matter what the tree did, and
		it is also strictly cheaper than the lookup it replaces. ]]
	local hostedActiveKey: string? = nil
	type HostedPending = {
		key: string,
		path: string,
		originPos: any,
		rectOf: (string) -> any,
		declined: boolean,
	}
	local hostedPending: HostedPending? = nil

	--[[ THE SLIDE SEAM. The engine owns the number; this control owns only WHO is
		engaged and BY HOW MUCH, because those two are what the shared tray overlay
		and the presentation write (Task 4) are derived from. Zero means closed:
		the row disengages, which is what unmounts the overlay.

		TWO ROWS SLIDE AT ONCE, routinely. Starting a swipe on row B claims the
		coordinator, which CLOSES row A — and A's close is a spring, so for the
		next several frames A is still writing a shrinking non-zero slide while B
		is writing a growing one. Last-writer-wins would hand the tray back and
		forth between them (A's spring steps AFTER B's move, every frame).

		THE RULE, exactly as implemented: the engaged row keeps writing its own
		pixels; any OTHER row may take the tray only when it is driving the live
		gesture (`hostedActiveKey`), or when nothing is engaged at all. The second
		clause is what lets a programmatic `_open` — no gesture anywhere — engage a
		row; the first is what stops a row that is merely FINISHING ITS CLOSE from
		taking the tray back off the row the player is actually dragging.

		ENGAGEMENT IS NOT THE PAINT (fixed 2026-08-15; carried defect 2 of
		`docs/plans/table-hosted-row-actions-stage2.md` §"three open hosted-mode
		defects" — "a visible regression on a shipped Table surface, not a
		theoretical one", because Table animates it today and a hosted Table would
		inherit the jump). `hostedWriteSlide` USED TO paint only the engaged row, so
		a row that lost engagement while its own close spring was still in flight
		stopped being painted on that very frame and snapped flat, while its engine
		went on computing pixels nobody wrote.

		The two really are different things and are now spelled as two. ENGAGEMENT
		is singular by policy — the coordinator's one-open rule means at most one
		row owns the TRAY, the overlay's anchor and the focus-restore target — and
		that arbitration below is unchanged. The SLIDE is per row, because two
		springs are genuinely in flight at once during a handover, so it rides
		`hostedSlideByKey` and every entry in it is painted. iOS animates the
		previously-open row closed under the new one; so does this now.

		Both engagement writes ride ONE transaction so a memo over the pair can
		never observe the new row against the previous row's pixels. ]]
	--[[ SUB-PIXEL IS HOME (device bug round 2026-08-12, finding C9b). This tested
		`px ~= 0`, and a position-domain spring only reaches its target at
		`spring.luau`'s 1e-3 epsilon — 35 frames after the row has visually arrived,
		measured. `row_actions.REVEAL_EPS` is the SAME half-pixel the engine's own
		tray reveal uses, and the two must be the same number: the engagement ending
		is what clears the presentation transform, drops the shared overlay entry and
		puts the focus ring back on the row (`hostedRestoreFocusOnDisengage`), and if
		the tray's focused button unmounted first the ring would have nowhere left to
		come back from. ]]
	local HOSTED_HOME_EPS: number = (row_actions :: any).REVEAL_EPS
	--[[ EVERY ROW THAT IS NOT AT HOME, and how far. Keyed by row key, never by
		path (a row's path changes as the window scrolls; its key does not), and a
		plain table rather than a signal: `hostedWriteSlide` is called explicitly at
		the one place this is written, so nothing needs to observe it, and a signal
		per drag pixel is exactly the per-row reactive cost the hosted design's own
		floor experiment rejected. An entry exists only while |px| >= the half-pixel
		home epsilon — see `hostedApplySlide` — so the table is empty on a list
		nobody has swiped, and empty again the moment the last spring lands. ]]
	local hostedSlideByKey: { [string]: number } = {}
	-- FORWARD-DECLARED, and it has to be: `hostedApplySlide` below calls it, and a
	-- `local function` declared after its caller is a GLOBAL lookup at call time —
	-- nil, silently (docs/lessons/a-helper-declared-below-its-caller-is-a-global.md,
	-- docs/lessons/later-locals-are-not-upvalues.md). It is defined a few lines
	-- down, beside the presentation-channel comment that explains what it writes.
	local hostedWriteSlide: () -> ()
	local function hostedApplySlide(key: string, px: number)
		if math.abs(px) >= HOSTED_HOME_EPS then
			hostedSlideByKey[key] = px
			local engaged = engagedKey:get()
			if engaged == key then
				engagedOffset:set(px)
			elseif engaged == nil or hostedActiveKey == key then
				core:transaction(function()
					engagedKey:set(key)
					engagedOffset:set(px)
				end)
			end
		else
			hostedSlideByKey[key] = nil
			if engagedKey:get() == key then
				core:transaction(function()
					engagedOffset:set(0)
					engagedKey:set(nil)
				end)
			end
		end
		-- ...and paint, here rather than only from the two engagement observers:
		-- a row that is closing WITHOUT the engagement moves no signal at all, and
		-- that silence is exactly what the carried defect was made of. The write is
		-- change-gated inside the renderer, so a repeat costs one comparison.
		hostedWriteSlide()
	end

	--[[ THE SLIDE ITSELF — the PRESENTATION CHANNEL, not a layout prop (design §3;
		ADR-0022's presentation authority, the same door the DropLine and the drag
		ghost translate through). A disengaged row declares NO reactive offset prop
		at all — that is the whole point, and it is what the floor experiment
		measured: a per-row reactive `offsetX` cost +6.7-8.8% fling on rows nobody
		swiped. Here the engaged row is translated from OUTSIDE the tree, so a
		closed row's blueprint is byte-identical to a plain list's.

		WHY IT IS RE-ASSERTED EVERY FRAME (from `bundle.syncGeometry`) rather than
		only on the signal: the renderer FORGETS a path's transform when that path
		is removed (`lastTransform` is cleared on removal — renderer.luau), so a
		row that unmounts and comes back mid-slide would otherwise be left flat
		while this control still believed it was translated. The write is
		change-gated inside the renderer, so re-asserting an unchanged transform
		costs one comparison. ]]
	-- what this control last wrote, key -> path. Keyed the same way the slide
	-- itself is, so a row that scrolled to a new path (or out of the window
	-- entirely) has its OLD path cleared rather than left behind translated.
	local hostedSlidPaths: { [string]: string } = {}
	function hostedWriteSlide()
		local ctrl = delivery.controller
		if ctrl == nil then
			return -- not presented yet; the next sync writes it
		end
		-- CLEAR FIRST, in its own pass. A row can leave for two reasons — it
		-- reached home, or it moved to a different path — and both have to release
		-- the path they were written at BEFORE anything is written, or a row that
		-- scrolled by exactly one slot would clear the entry the row now occupying
		-- that path had just been given. Assigning nil to the key `pairs` is
		-- currently visiting is the one table mutation Lua allows mid-iteration.
		for key, path in hostedSlidPaths do
			if hostedSlideByKey[key] == nil or mountedRowPath(key) ~= path then
				-- RESTORED, not zeroed: nil clears the presentation transform
				-- outright (and decrements the renderer's own live-presentation
				-- count), so a row at home is exactly as untransformed as one that
				-- never slid.
				ctrl.setPresentationTransform(path, nil)
				hostedSlidPaths[key] = nil
			end
		end
		for key, px in hostedSlideByKey do
			local path = mountedRowPath(key)
			if path ~= nil then
				ctrl.setPresentationTransform(path, { x = px, y = 0 })
				hostedSlidPaths[key] = path
			end
		end
	end

	local function hostedApplyCommitHeight(key: string, px: number?)
		if px == nil then
			if hostedCommitKey:get() == key then
				hostedCommitKey:set(nil)
			end
			return
		end
		core:transaction(function()
			hostedCommitKey:set(key)
			hostedCommitPx:set(px)
		end)
	end

	--[[ DOES THIS ROW HAVE ACTIONS AT ALL? Answered on every press (the capture
		verdict depends on it — an unwrapped row must not hold one), cached per
		key, and deliberately SEPARATE from building the engine: the build waits
		for the axis lock, this does not. `false` is the memo for "asked, and the
		answer was no". ]]
	local function hostedFieldsFor(key: string): any?
		local cached = hostedFieldsByKey[key]
		if cached ~= nil then
			return if cached == false then nil else cached
		end
		local item = itemForKey(key)
		if item == nil then
			return nil -- not in the data; nothing to cache either
		end
		hostedItemByKey[key] = item
		local fields = hostedRowActions(item)
		if fields ~= nil then
			specGuard.assertKnownKeys(
				"newVirtualList",
				fields,
				HOSTED_ROW_ACTIONS_KEYS,
				`spec.rowActions result (row '{key}')`
			)
			if fields.leading == nil and fields.trailing == nil then
				fields = nil -- declared, but with nothing on either edge
			end
		end
		hostedFieldsByKey[key] = if fields == nil then false else fields
		return fields
	end

	-- BUILD. Called at the AXIS LOCK, never at pointer-down (see the dispatcher):
	-- a vertical pan, a fling and a tap must all cost zero engines. Returns nil
	-- for a row with no actions, a row that is not mounted, and a list that has
	-- not been presented yet (no mounted paths to hand the engine).
	local function hostedEngineFor(key: string): any?
		local existing = hostedEngines[key]
		if existing ~= nil then
			return existing
		end
		local fields = hostedFieldsFor(key)
		if fields == nil then
			return nil
		end
		local rowPath = mountedRowPath(key)
		if rowPath == nil then
			return nil
		end
		local engine = row_actions.buildHosted(Facet, core, {
			-- unique per row: rows sharing a coordinator must carry unique ids
			-- (row_actions' own refusal), and the id is what a dump names
			id = `{id}:{key}`,
			leading = fields.leading,
			trailing = fields.trailing,
			fullSwipe = fields.fullSwipe,
			coordinator = hostedCoordinator,
			-- the live theme metrics the tray's own natural width is measured
			-- against (`buttonPad`/`buttonMinWidth`). Optional on both sides:
			-- absent, row_actions degrades to the neutral snapshot exactly as it
			-- does for a Table row built without one.
			env = spec.env,
			-- `rowDeletable`, threaded the same way Table threads it: this side owns
			-- the item and the predicate, the engine owns the one destructive funnel
			-- that evaluates the verdict. Fail-closed via `rowCapability.allows`.
			deletable = if spec.rowDeletable ~= nil
				then function()
					return rowCapability.allows(spec.rowDeletable, itemForKey(key))
				end
				else nil,
			paths = {
				-- the row node, NOT the cell: it is what the engine reads a live
				-- rect from (the commit threshold is a fraction of the row width)
				-- and the prefix its "is focus still inside this row" test uses.
				-- Keyed, so it is stable across every scroll the row survives.
				content = rowPath,
				trayLeading = if fields.leading ~= nil then hostedTrayPath(key, "leading") else nil,
				trayTrailing = if fields.trailing ~= nil then hostedTrayPath(key, "trailing") else nil,
			},
			onSlide = function(px: number)
				hostedApplySlide(key, px)
			end,
			onCommitHeight = function(px: number?)
				hostedApplyCommitHeight(key, px)
			end,
		})
		-- relay every presenter handoff this list has already received: an engine
		-- born mid-session must be as wired as one born at present time
		if delivery.motionClock ~= nil then
			engine.bindMotion(delivery.motionClock, delivery.now)
		end
		if delivery.controller ~= nil then
			engine.bindController(delivery.controller)
		end
		if delivery.actionSystem ~= nil then
			engine.bindActionSystem(delivery.actionSystem)
		end
		if delivery.focusGraph ~= nil then
			engine.bindFocusGraph(delivery.focusGraph)
		end
		if delivery.presentModal ~= nil then
			engine.bindPresent(delivery.presentModal, delivery.dismiss)
		end
		hostedEngines[key] = engine
		-- one geometry pass immediately, so the engine has whatever rects exist
		-- before the gesture it was built for is dispatched into it
		engine.syncGeometry()
		return engine
	end

	-- the engine the LIVE gesture belongs to, by held key — never by path lookup
	-- (see `hostedActiveKey`'s own comment: the row may already be unmounted)
	local function hostedLiveEngine(): any?
		return if hostedActiveKey ~= nil then hostedEngines[hostedActiveKey] else nil
	end

	--[[ ===== THE FOCUSED ROW'S KEY SURFACE (parity round 3, owed row 9) ========
		A row's Delete/menu bindings belong to its ENGINE (`row_actions.luau`'s
		`ensureKeysContext`), and a hosted engine is born at a pointer gesture's
		AXIS LOCK — so until this, a row a keyboard-only or pad-only player had
		merely focused had no engine and therefore no binding at all. Not Delete,
		and not ButtonX/Shift+Return either, which is a pad's whole route to a
		NON-destructive action. Row actions were reachable by pointer only.

		THE LIST STANDS IN FOR THE ENGINE THAT DOES NOT EXIST YET. One context per
		LIST (never per row), binding exactly `row_actions.ROW_KEYS` — the same
		table the engine binds, so a host's spelling cannot drift from the
		control's — and materialising that ONE row's engine on the press. The
		alternative considered and refused was building an engine when focus
		ARRIVES: that is one engine per row a d-pad passes over, which is the
		laziness this whole design exists for, spent on a walk that presses
		nothing.

		WHY IT CANNOT DOUBLE-FIRE: the engine's own context is `sink = true` at
		`ROW_KEY_PRIORITY`, this one sits strictly below, and the action system
		cuts every strictly-lower context once a sink consumes
		(`src/input/actions.luau`). So the moment a row HAS an engine with focus
		inside it, the engine answers and this context never sees the key.
		MEASURED ON THE ENGINE, not only on the model: two sinking `InputContext`s
		on one key deliver to the higher priority alone, and the lower one receives
		it as soon as the higher is disabled
		(`docs/lessons/input-context-arbitration-measured.md`, Play mode
		2026-08-13). The only prior citation was a headless spike.

		ENABLED BY FOCUS, BUILT BY THE PRESS: the context is enabled only while the
		ring sits on a row hit whose row declares actions, so a TextField elsewhere
		on the screen keeps Backspace and a plain list binds nothing at all. ]]
	local hostedKeysContext: any = nil
	-- the row the ring is on, IF that row declares actions. `hostedFieldsFor` is
	-- the same cached decide-and-decline the pointer dispatcher asks on every
	-- press — it calls the consumer's callback at most once per (key, item), and
	-- it never builds anything.
	local function hostedFocusedActionableKey(): string?
		if delivery.focusGraph == nil then
			return nil
		end
		local path = delivery.focusGraph.focused:get()
		if path == nil then
			return nil
		end
		local key = hostedKeyOfHit(path)
		if key == nil then
			return nil -- the ring is not on a row hit of this list
		end
		return if hostedFieldsFor(key) ~= nil then key else nil
	end
	local function hostedRouteKey(verb: (engine: any) -> ())
		local key = hostedFocusedActionableKey()
		if key == nil then
			return
		end
		local engine = hostedEngineFor(key)
		if engine ~= nil then
			verb(engine)
		end
	end
	local function hostedEnsureKeysContext()
		if delivery.actionSystem == nil or hostedKeysContext ~= nil then
			return
		end
		local ctx = delivery.actionSystem.createContext({
			name = `VirtualListRowKeys-{id}`,
			-- strictly below the engine's own — see the block comment above
			priority = row_actions.ROW_KEY_PRIORITY - 1,
			sink = true,
		})
		local deleteAction = ctx.createAction("RowActionsDelete", "Bool")
		for _, binding in row_actions.ROW_KEYS.delete do
			deleteAction.bind(binding)
		end
		deleteAction.onPressed(function()
			hostedRouteKey(function(engine)
				engine.commitDestructive()
			end)
		end)
		local menuAction = ctx.createAction("RowActionsMenu", "Bool")
		for _, binding in row_actions.ROW_KEYS.menu do
			menuAction.bind(binding)
		end
		menuAction.onPressed(function()
			hostedRouteKey(function(engine)
				engine.toggleMenu()
			end)
		end)
		ctx.setEnabled(false) -- enabled only while the ring is on an actionable row
		hostedKeysContext = ctx
		listScope:own(function()
			if hostedKeysContext ~= nil then
				hostedKeysContext.destroy()
				hostedKeysContext = nil
			end
		end)
	end
	-- the same deferral row_actions' own `syncKeysEnabled` makes (Task 11b): a
	-- list nobody has ever focused a row of builds no context at all.
	local function hostedSyncKeysEnabled()
		local on = hostedFocusedActionableKey() ~= nil
		if not on and hostedKeysContext == nil then
			return
		end
		hostedEnsureKeysContext()
		if hostedKeysContext ~= nil then
			hostedKeysContext.setEnabled(on)
		end
	end

	--[[ RESOLVE THE AXIS, then build. Identical rule to the composite's own
		`onPointerMove` and to `row_actions.composeWithReorder`'s `resolveAxis`: a
		pure function of dx/dy against the one lock constant, ties go VERTICAL so
		an ambiguous gesture is never taken away from the native scroll.

		This is where the engine is BORN. Deferring past the lock is the whole
		laziness story on touch: a phone user pans and flings THROUGH rows
		constantly, and every one of those gestures starts with a pointer-down on
		a row. Building there would have made "lazy" mean "lazy until the player
		scrolls once". A tap resolves the same way — it never crosses the lock, so
		it never builds anything either. ]]
	local function hostedResolveAxis(pending: HostedPending, pos: any)
		local dx, dy = pos.x - pending.originPos.x, pos.y - pending.originPos.y
		if dx * dx + dy * dy < row_actions_state.AXIS_LOCK_PX ^ 2 then
			return -- still accumulating toward the lock radius
		end
		if math.abs(dx) <= math.abs(dy) then
			pending.declined = true -- vertical: the native scroll owns this gesture
			--[[ ...AND A PAN IS NOT A TAP (carried defect 3, fixed 2026-08-15 —
				`docs/plans/table-hosted-row-actions-stage2.md` §"three open
				hosted-mode defects": "a vertical pan begun on a row still fires that
				row's `onActivate`").

				IT IS THE SAME RED-TEAM DEFECT AS ABOVE, IN THE BRANCH THAT WAS
				MISSED. The
				horizontal branch below arms for one reason — the row's `Hit` is a
				real engine `GuiButton`, so the same pointer sequence that swipes it
				ends in an `Activated` on it — and that reason does not care which
				way the axis went. The native scroll owning the gesture makes this
				dispatcher inert; it does not move the button out from under the
				finger. A short pan that begins and ends inside one row still
				delivers `Activated`, so reading a list by dragging it opened
				whatever the row opens.

				ARMED HERE, at the lock, for the same reason the horizontal branch
				is: an `Activated` can land before `InputEnded`, so `onPointerUp` is
				already too late. And it stays one pan wide — spent by the one
				pointer Activate it exists for, cleared by the next down and by
				`onPointerCancel` (which is where a scroll that steals the capture
				arrives), and never eligible for a DEVICE Activate at all
				(`meta.source == "action"`; docs/lessons/an-arm-set-by-a-gesture-
				must-name-what-may-spend-it.md). ]]
			delivery.suppressActivate = pending.path
			return
		end
		local engine = hostedEngineFor(pending.key)
		if engine == nil then
			pending.declined = true
			return
		end
		--[[ REPLAY the down at the TRUE ORIGIN, marked `replayed`. The position
			has to be the origin (the engine's own clamp math measures every later
			move against it), but the TIME is now, not then — so `replayed = true`
			tells the engine's velocity tracker to skip its seed rather than record
			a hundreds-of-px jump over one frame. Exactly the affordance
			`composeWithReorder` uses for the identical reason. ]]
		local accepted = engine.pointerHandlers.onPointerDown(pending.path, {
			x = pending.originPos.x,
			y = pending.originPos.y,
			pointerType = pending.originPos.pointerType,
			replayed = true,
		}, pending.rectOf)
		if accepted == false then
			-- the engine REFUSED the gesture (a commit still in flight, or — the
			-- bug class C1 exists for — a previous gesture whose end it never
			-- heard, leaving its own `drag` live). Go inert rather than push moves
			-- into a drag this gesture does not own: reading a delta against some
			-- earlier gesture's origin is worse than doing nothing.
			pending.declined = true
			return
		end
		--[[ A HOSTED SWIPE IS UNDONE BY ITS OWN RELEASE, unless this arms here (a
			red-team BLOCKER, 2026-08-13). A row's `Hit` is a real engine
			`GuiButton`, so the SAME pointer sequence that swipes it also ends in a
			native `Activated` on it — "whichever side of `InputEnded` it lands",
			the fact this file's own `delivery.suppressActivate` declaration already
			records. The arm existed only in `onPointerUp`'s UNRESOLVED branch (a
			tap on an already-open row): a gesture that resolved HORIZONTAL — every
			real swipe — armed nothing, so `handleActivate` fell straight past the
			`engaged == key` test (which answers only `meta.source == "action"`)
			and past the `delivery.suppressActivate == path` test, into `spec.onActivate`.
			Worse than the Table defect it mirrors, which was order-dependent:
			measured RED on BOTH orders, BOTH edges and BOTH pointer kinds — 8 of a
			12-combination matrix. On the shipped playlist analogue that reads
			"swipe to reveal Remove, and the track plays".

			ARMED AT THE LOCK, NOT AT THE RELEASE, exactly as `table.luau`'s host
			dispatcher arms it and for the identical reason: an `Activated` that
			lands BEFORE `InputEnded` has already been dispatched by the time any
			`onPointerUp` could arm anything. THIS is the lock — the one place this
			control decides a gesture went sideways — so there is no second copy of
			the rule to keep in step. Armed once and left armed through the release:
			it is cleared by the one POINTER Activate it swallows, by a cancel, by a
			device Activate, or by the next down. ]]
		delivery.suppressActivate = pending.path
		hostedPending = nil
	end

	--[[ CLOSE ANOTHER ROW — the ONE way this control ever puts a row away on
		behalf of a press or an Activate somewhere else. Both the tray and the
		row's own action MENU go, because they are independent state
		(`row_actions.luau`'s `menuOpen`, and the reason `newCoordinator.claim`
		calls `_closeMenu()` alongside `_close()` on the row it claims away from —
		redteam item 7). Without the menu half, a press on another row could leave
		the first row's menu — and its `transientScope` focus trap — armed over a
		row the player had already moved on from. The coordinator's claim covers
		this ONLY for a press that becomes a gesture; a tap, or a keyboard
		Activate, never claims anything, which is exactly when this runs. ]]
	local function hostedCloseRow(key: string)
		local engine = hostedEngines[key]
		if engine == nil then
			return
		end
		engine.close()
		engine._closeMenu()
	end

	--[[ THE ONE SHARED DISPATCHER. Four functions for the whole list, allocated
		once at build: every row's `Hit` carries the SAME four values, so a row
		mounting costs four static prop reads and no closure at all. The hit's own
		path is the routing key on the DOWN (the renderer passes it to every
		handler — render/renderer.luau's pointer wiring), which is exactly why this
		can be shared: a per-row closure would exist only to remember something the
		event already carries. Every later event of that gesture routes by the HELD
		key instead, so an unmounting row cannot lose its own cancel. ]]
	local hostedDispatch = {
		onPointerDown = function(path: string, pos: any, rectOf: (string) -> any): boolean?
			--[[ A NEW GESTURE MAKES ANY PENDING SUPPRESSION STALE. `delivery.suppressActivate`
				is armed at the axis lock (`hostedResolveAxis`, above) and on the up of
				a same-row re-grab (`onPointerUp`, below), and is normally cleared by
				the Activate that follows it — but a release that produces no Activated
				(e.g. the up lands off the translated `Hit`) leaves it armed with
				nothing left to clear it, and it would then swallow the NEXT Activate
				on that row.

				THIS IS THE WEAKEST OF THE FOUR CLEARS, NOT THE ONLY ONE, and the
				first draft of it carried a premise that is simply false (a red-team
				finding, 2026-08-13 — `table.luau`'s twin comment carries the identical
				correction, because it is one rule in two controls): "a real Activated
				always fires between a pointer-up and the next pointer-down, so a
				still-live suppression can never legitimately survive to see another
				down." TWO ACTIVATE PRODUCERS CARRY NO POINTER-DOWN AT ALL — an IAS
				device Activate (gamepad A / keyboard Return, `meta.source ==
				"action"`), and the minimum-target hit expander, a SEPARATE
				`GuiButton` whose press produces no pointer event on this row's `Hit`
				at all (`screen_target.luau`'s `pointerActivateMeta`). Either of them
				can reach `handleActivate` while an arm from a silently-ended swipe is
				still live, and be eaten by it. So the arm is cleared on a CANCEL too
				(`onPointerCancel`, below), and `handleActivate` refuses to spend it
				on a device Activate at all.

				The standing rule this cost us — an arm owes three answers where it is
				set: where it is armed, what clears it, and what class of event may
				spend it — is
				`docs/lessons/an-arm-set-by-a-gesture-must-name-what-may-spend-it.md`. ]]
			delivery.suppressActivate = nil
			local key = hostedKeyOfHit(path)
			if key == nil then
				return false
			end
			--[[ THE IN-LIST HALF OF OUTSIDE-DISMISS. The presenter's own
				`outsideDismiss` (contributed below) answers a tap OUTSIDE this
				list's subtree — but the whole list is one contribution here, so
				every row is "inside" it and a press on a DIFFERENT row would
				never reach that path. Table gets this free precisely because its
				rows each contribute separately; a hosted list has to say it.

				ABOVE EVERY DECLINE, and that placement is the fix for a real bug
				(review round 1, F1): a press on a row that CANNOT swipe — one
				whose `rowActions(item)` answered nil, or a pen press — still
				means "put the open tray away". It used to sit below both
				`return false`s, so a mixed list (some rows actionable, some not)
				left the tray open and the row slid when the player pressed an
				actionless row, with no way back except pressing an actionable
				one. Dismissal has nothing to do with whether THIS press can
				become a gesture.

				The press is NOT swallowed (the same `consume = false` rule the
				engine's own `outsideDismiss` carries, round 7's lesson: closing
				must not eat unrelated clicks), so pressing another row still
				selects/activates it exactly as it would with nothing open. The
				same-row half rides the UP instead — see `onPointerUp`, because
				at the down it is not yet knowable whether this is a tap or a
				re-grab of the open row.

				STILL NOT COVERED (review round 1, F2 — carried, and named here
				rather than left silent): a tap on the list's own EMPTY CANVAS,
				below the last row. iOS closes there. It reaches neither seam —
				the presenter's outside-tap test says "inside this contribution"
				for the whole list, and this dispatcher only ever hears from a row
				`Hit`. Closing it needs a hit surface over the empty canvas, and
				every shape of that is a real cost or a real risk: a permanent
				`Grip` is an instance per list this whole mission exists to avoid,
				and making the Canvas itself `active` would put an input-consuming
				node between a finger and the native ScrollingFrame — a touch-scroll
				regression only a device pass could clear. Deferred to the device
				pass with that evidence, not fixed blind. ]]
			local engaged = engagedKey:get()
			if engaged ~= nil and engaged ~= key then
				hostedCloseRow(engaged)
			end
			if pos.pointerType ~= nil and pos.pointerType ~= "mouse" and pos.pointerType ~= "touch" then
				-- PEN/STYLUS/anything else: declined HERE, at the down, exactly as
				-- row_actions' own `onPointerDown` declines it. Deferring the
				-- decision to the replayed down would have meant holding the
				-- capture for the whole gesture and building an engine for a
				-- pointer class the engine then refuses — a build that can never
				-- do anything. The shipping adapter only ever emits mouse/touch,
				-- so this is a guard against a future one, not a live repro.
				return false
			end
			if hostedFieldsFor(key) == nil then
				-- DECLINE: an unwrapped row must behave exactly like a row on a
				-- list with no `rowActions` at all, and that row holds no capture.
				-- Answered from the cached spec result, NOT by building anything.
				return false
			end
			hostedActiveKey = key
			hostedPending = {
				key = key,
				path = path,
				originPos = pos,
				rectOf = rectOf,
				declined = false,
			}
			-- TENTATIVE ACCEPT, the same verdict row_actions' own `onPointerDown`
			-- returns and for the same reason: the axis is genuinely unknown at
			-- down (dx = dy = 0), and the capture model offers no way to hand one
			-- back later — a vertical verdict is honored by going inert instead.
			return true
		end,
		onPointerMove = function(path: string, pos: any, rectOf: (string) -> any)
			local pending = hostedPending
			if pending ~= nil then
				if pending.declined then
					return
				end
				hostedResolveAxis(pending, pos)
				if hostedPending ~= nil then
					return -- still pending, or declined by this very move
				end
			end
			local engine = hostedLiveEngine()
			if engine ~= nil then
				engine.pointerHandlers.onPointerMove(path, pos, rectOf)
			end
		end,
		onPointerUp = function(path: string, pos: any, rectOf: (string) -> any)
			local engine = hostedLiveEngine()
			local key = hostedActiveKey
			local unresolved = hostedPending ~= nil
			-- CLEARED UNCONDITIONALLY, both of them: this gesture is over however
			-- it ends, and a stale active key would misroute the next one
			hostedPending = nil
			hostedActiveKey = nil
			if engine ~= nil and not unresolved then
				engine.pointerHandlers.onPointerUp(path, pos, rectOf)
				return
			end
			-- unresolved (a tap, or a gesture that never left the lock radius):
			-- the engine was never told a down, so it is never told an up. But a
			-- tap on the OPEN row's own slid content means close, and means ONLY
			-- close — the activate it would otherwise fire is swallowed.
			if unresolved and key ~= nil then
				local open = hostedEngines[key]
				if open ~= nil and open._isOpen() then
					open.close()
					delivery.suppressActivate = path
				end
			end
		end,
		onPointerCancel = function(path: string, reason: string?): boolean?
			local engine = hostedLiveEngine()
			local unresolved = hostedPending ~= nil
			hostedPending = nil
			hostedActiveKey = nil
			-- A CANCELLED GESTURE HAS NO ARTIFACT COMING (the arm-must-name-what-
			-- may-spend-it rule, applied to this dispatcher too): the engine fires
			-- no `Activated` for
			-- a capture it took away, so an arm left standing here would be spent
			-- on the next producer that carries no pointer-down — an IAS device
			-- Activate, or the minimum-target hit expander's own `Activated` —
			-- costing the player a dead press on the row they just swiped. Same
			-- clear, same reason, as `table.luau`'s `hitOnPointerCancel`.
			delivery.suppressActivate = nil
			if engine ~= nil and not unresolved then
				return engine.pointerHandlers.onPointerCancel(path, reason)
			end
			return nil
		end,
	}

	-- the engaged row's engine, or nil — the one every list-level verb (Cancel
	-- now; the overlay and outside-tap in Task 4) routes through
	local function hostedEngagedEngine(): any?
		local key = if engagedKey ~= nil then engagedKey:get() else nil
		return if key ~= nil then hostedEngines[key] else nil
	end

	--[[ FREE ONE ROW'S ENGINE, and leave no state pointing at it. `dispose()`
		releases the coordinator claim and tears the engine's own scope down, but
		it deliberately does NOT run the close ladder (row_actions.luau's own
		`dispose`), so a row disposed while REVEALED would otherwise leave
		`engagedKey`/`engagedOffset` pinned to a row that no longer exists — a
		stuck-open tray over a dead row once Task 4 paints one. Clearing them here
		is the host's job, because they are the host's signals. ]]
	local function hostedDropEngine(key: string)
		local engine = hostedEngines[key]
		hostedEngines[key] = nil
		hostedFieldsByKey[key] = nil
		hostedItemByKey[key] = nil
		if hostedActiveKey == key then
			hostedActiveKey = nil
			hostedPending = nil
		end
		if engine ~= nil then
			engine.dispose()
		end
		if engagedKey:get() == key then
			core:transaction(function()
				engagedOffset:set(0)
				engagedKey:set(nil)
			end)
		end
		if hostedCommitKey:get() == key then
			hostedCommitKey:set(nil)
		end
		-- the row is gone or rebuilding: whatever it was translated by is not a
		-- fact about anything any more. The engine that was computing that number
		-- has just been disposed, so nothing will ever write it home — this entry
		-- has to go with the engine, or the row comes back translated forever.
		hostedSlideByKey[key] = nil
		hostedWriteSlide()
	end

	--[[ A RE-PRESENT INVALIDATES EVERY ENGINE. Each one captured its row path and
		its tray paths at BUILD time (a hosted engine owns no nodes, so it can only
		be told where to look), and those strings name the mount it was built
		under. Dismiss the surface and present again — a new screen root, a
		different id, a keyed region remounting — and every one of them points at a
		tree that no longer exists: `controller.rectOf` answers nil, the commit
		threshold can never trip, and the tray can never be measured. Nothing about
		that is recoverable in place, and it does not need to be: engines are lazy,
		so dropping the cache costs one rebuild on the next real gesture. ]]
	--[[ Called from `buildFocusGroups` — the ONE place this control learns its
		mounted path, and the presenter runs it on every present and every
		refresh. That is what makes the drop correct: the root is compared and
		RECORDED here, so a re-mount is noticed on the very next refresh whether
		or not anyone ever touches the list again, and a run where the root has
		not moved costs one string compare (`hostedMapRoot` used to be written
		only by `hostedKeyOfHit`, so this cloned the engine table on every
		refresh until the next pointer-down). Recording it also invalidates the
		path map — the map is keyed on this same root, and a stale one would
		answer with paths from the previous mount. ]]
	local function hostedNoticeMount()
		local root = delivery.scrollPath
		if root == hostedMapRoot then
			return
		end
		local previousRoot = hostedMapRoot
		hostedMapRoot = root
		hostedMapWindow = nil -- force the path map to rebuild under the new root
		if previousRoot == nil then
			return -- the very first mount: nothing was built under a previous root
		end
		for key in table.clone(hostedEngines) do
			hostedDropEngine(key)
		end
	end

	--[[ THE OVERLAY'S ITEM LIST: the at-most-one engaged row, as a keyed region's
		items (see the path contract at the top of the file for why a keyed region
		and not a `When`). Recomputes only when the engagement MOVES — never per
		drag pixel, which rides `engagedOffset` and the presentation channel. ]]
	local hostedOverlayItems: any = nil
	if hostedEnabled then
		hostedOverlayItems = listScope:own(core:memo(function(use)
			local key = use(engagedKey)
			if key == nil then
				return HOSTED_NO_OVERLAY
			end
			return { { key = key } }
		end))
	end

	--[[ WHEN THE TRAY GOES AWAY, THE RING COMES BACK TO ITS ROW (fix round 1, R1).
		A revealed tray's buttons are focusables that exist only while the row is
		engaged, so closing the row while one of them holds focus is a structural
		change under the ring. The graph's own answer for a grouped scope whose
		focused path vanished is `entryFocus`, which is the FIRST focusable in the
		WHOLE SCOPE (`focus_graph.replaceGroups`) — measured: focus on r2's Delete,
		close, and the ring lands on r1's hit; on a real screen, whatever sits at
		the top of the surface. That is a teleport away from what the player was
		doing, and it happens on every close path there is (a tray tap, Cancel, a
		scroll, another row).

		So the ring is moved HERE, while both the tray and the row are still
		mounted: the engagement leaving a row whose tray holds focus puts focus on
		THAT ROW'S OWN HIT — the thing the player was working on, and what "Up
		comes back" means once the tray is gone. Only when focus is genuinely
		inside the departing row's overlay region: a player whose ring is anywhere
		else (another control, another row) is never yanked. ]]
	local hostedFocusRow: string? = nil
	local function hostedRestoreFocusOnDisengage()
		local key = engagedKey:get()
		local previous = hostedFocusRow
		hostedFocusRow = key
		if previous == nil or previous == key then
			return
		end
		local graph = delivery.focusGraph
		if graph == nil then
			return
		end
		local focused = graph.focused:get()
		local region = hostedOverlayRowPath(previous)
		if focused == nil or region == nil or string.sub(focused, 1, #region + 1) ~= region .. "/" then
			return
		end
		local hit = hitPathOf(previous)
		if hit ~= nil then
			-- ...and if the row is no longer mounted (scrolled away while open)
			-- there is nothing to put the ring on, so the graph's own survivor
			-- rule is left to answer — the same fall-through every other
			-- unmount-under-focus takes.
			graph.focusOn(hit)
		end
	end

	if hostedEnabled then
		-- the slide, written the instant the engagement or the offset moves. Both
		-- signals are written inside ONE transaction by `hostedApplySlide`, so a
		-- move that changes both still resolves to a single pair of reads.
		listScope:own(core:observe(engagedKey, hostedWriteSlide))
		listScope:own(core:observe(engagedKey, hostedRestoreFocusOnDisengage))
		listScope:own(core:observe(engagedOffset, hostedWriteSlide))
		--[[ SCROLL CLOSES THE OPEN ROW (iOS parity; `newCoordinator.bindScroll`'s
			own rule). That coordinator method takes a render controller and a path
			and rides `observeScroll` — but this list ALREADY owns the engine's
			CanvasPosition mirror as a signal (`scrollTop`, written by
			`bindNativeScroll` or by a test), and it is live before any controller
			is bound. So the coordinator's own code path is reused verbatim against
			a one-method shim over that signal, rather than a second subscription to
			the same engine scroll that could arrive later, or not at all. ]]
		listScope:own(hostedCoordinator.bindScroll({
			observeScroll = function(_path: string, onScroll: (any) -> ()): () -> ()
				return core:observe(scrollTop, function(y: any)
					onScroll({ x = 0, y = y })
				end)
			end,
		}, ""))
		--[[ THE ITEM BEHIND A TOUCHED KEY MOVED. One observer answers both halves
			of the same question, because they have one root cause — a cached
			answer outliving the item it was derived from:
			  * the row LEFT the data. A deleted key never comes back (unlike a
			    windowed-out row, which keeps its engine on purpose), and an
			    engine still holding the tray for it would pin the overlay over a
			    row that is gone.
			  * the row's ITEM CHANGED under a stable key — locked to unlocked,
			    ownership transferred, a racer finished. `spec.rowActions(item)`
			    is a function of the item, so both the cached verdict and the
			    engine built from it are now answers to an old question.
			Dropping the engine covers both directions (a row that GAINS actions
			and a row that LOSES them), and it is lazy, so the cost is one rebuild
			on the next real gesture.

			An untouched list pays NOTHING here: `hostedItemByKey` is empty until
			a press, and `indexByKey` is a memo this control already recomputes on
			every data change for its own focus pruning. ]]
		listScope:own(core:observe(spec.rows, function(items: { any })
			if next(hostedItemByKey) == nil then
				return
			end
			local index = indexByKey:get() :: { [string]: number }
			for key, item in table.clone(hostedItemByKey) do
				local at = index[key]
				if at == nil or items[at] ~= item then
					hostedDropEngine(key)
				end
			end
		end))
		-- engines are independent scope roots (`buildHosted` opens its own), so
		-- the list is what frees them
		listScope:own(function()
			for key in table.clone(hostedEngines) do
				hostedDropEngine(key)
			end
		end)
	end
	--[[ THE SURFACE, and it is deliberately the same set of names the host used
		to hold as locals — `virtual_list.luau` rebinds each to a local of its
		original spelling, so no call site over there changed. `engines` travels as
		a TABLE (already a reference): this file inserts and drops, the host's
		contribution iterates it to relay a handoff to every engine that exists. ]]
	return {
		closeRow = hostedCloseRow,
		dispatch = hostedDispatch,
		engagedEngine = hostedEngagedEngine,
		engagedKey = engagedKey,
		engagedOffset = engagedOffset,
		engines = hostedEngines,
		itemExtentIn = hostedItemExtentIn,
		noticeMount = hostedNoticeMount,
		overlayItems = hostedOverlayItems,
		syncKeysEnabled = hostedSyncKeysEnabled,
		trayPath = hostedTrayPath,
		writeSlide = hostedWriteSlide,
	}
end

return virtual_list_hosted
