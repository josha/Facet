--!strict
-- ScreenPointer — THE POINTER SEAM of the ScreenTarget adapter: the one activate
-- meta, the global pointer capture, the semantic cursor, and the engine
-- connection census that counts them. Extracted from
-- src/client/screen_target.luau for Studio's 200_000-character `Source` WRITE
-- cap — over that cap a module silently stops live-syncing into an open Studio
-- session, so every live check against it tests the built place rather than the
-- edits on disk.
-- Strictly one-way, like screen_chrome/screen_paint/screen_presentation/
-- screen_scroll_indicators: it never requires back.
--
-- WHY THIS IS ONE MODULE AND NOT FOUR THINGS. A press is one story: `InputBegan`
-- on a zone (or on its minimum-target expander) opens a CAPTURE, the capture owns
-- the pointer until it ends, the zone's cursor hint stays applied for exactly that
-- long, and the census reports what is currently held. The cursor state came with
-- it for that reason — `captureHint` and `hoverHint` are written from inside the
-- capture and from the hover wiring and nowhere else, so leaving them behind would
-- have meant two accessors for state neither side shares.
--
-- ctx:
--   handlesByPath   BY REFERENCE — the same live-handle map screen_target holds.
--                   `connectionCensus` walks it, and it is the ONLY thing this
--                   module needs from the host: nothing here reads a reassigned
--                   host local, so there are no accessors
--
-- `new(ctx)` returns the four adapter methods, which screen_target binds onto its
-- adapter under their original names, plus the four internals its remaining code
-- calls (`pointerActivateMeta`, `connectPointerBegan`, `endCapture`, `menuConn`),
-- each rebound to a local of its ORIGINAL name so no call site moved. Public
-- surface unmoved: all of this is internal to `screen_target.new`, whose contract
-- is the `adapter` table it returns.
--
-- TWO EXPORTS ARE NOT A RENAME, and both are here because a MUTABLE UPVALUE
-- cannot be shared by reference. `capturedHandle()` answers the host's three
-- reads of `activeCapture` (park refuses a captured node; remove and destroyRoot
-- each end a capture pointing into what they are tearing down).
-- `disposeGlobals()` is destroyRoot's three-line teardown of the adapter-wide
-- state — the menu connection and the cursor hint — which is this module's now.

--[[ THE SERVICES ARE RESOLVED AT CONSTRUCTION, NOT AT REQUIRE. Module-scope
	`game:GetService` locals made this file engine-only to REQUIRE, so the pointer
	seam — the cursor, the capture, the menu abort — had no headless instrument of
	any kind, and three shipped defects (the session-wide menu disconnect,
	the cursor stomp, the second finger) could only be found by reading.
	`ctx.services` is that instrument; a client passes nothing and gets the
	engine's own services, exactly as before. ]]
local function engineServices(): any
	return {
		userInput = game:GetService("UserInputService"),
		gui = game:GetService("GuiService"),
	}
end

-- the recycle-safe reconnect helpers (task CONN, review-fix234 Finding 1/4):
-- a module of their own, not a screen_vocabulary addition — see
-- handle_conn.luau's header for why (it would have cost this file its
-- headless-requireability, which tests/pointer_seam_ownership.spec.luau
-- depends on).
local handle_conn = require("./handle_conn")
local reconnect = handle_conn.reconnect
local reconnectOnChange = handle_conn.reconnectOnChange

local screen_pointer = {}

function screen_pointer.new(ctx: any)
	local handlesByPath = ctx.handlesByPath
	local services = ctx.services or engineServices()
	local UserInputService = services.userInput
	local GuiService = services.gui
	local adapter = {}

	-- semantic cursor requests: the framework names an intent
	-- ("colResize"); this table maps it to uploaded cursor art. No first-party
	-- cursor set exists — assets are a rider; an unmapped hint keeps the
	-- default arrow but the seam (hover + capture persistence) is live.
	local CURSOR_ART: { [string]: string } = ctx.cursorArt or {}
	local hoverHint: string? = nil
	local captureHint: string? = nil
	--[[ THE HOST'S CURSOR IS BORROWED, NOT OWNED (2026-08-17).

		This used to write `UserInputService.MouseIcon = <art> or ""` on every hint
		change — including every hint CLEAR and the whole-adapter teardown. `""` is
		not "no request", it is "the default arrow", so a game that had set its own
		crosshair lost it the first time a pointer left a Grip and never got it
		back. And because `CURSOR_ART` is empty today (no first-party cursor set has
		shipped — the seam is live, the assets are a rider), EVERY write this module
		made was that stomp: it could only ever clear the host's cursor, never set
		one of its own.

		So the framework now borrows: the host's value is captured the first time
		this module is actually about to overwrite it, and restored the moment it
		has no request of its own — on hint clear, on capture end, and on teardown.
		With no art mapped it writes nothing at all, which is the correct behaviour
		for a subsystem that has nothing to say. ]]
	local borrowedMouseIcon: string? = nil
	local function applyCursor()
		local hint = captureHint or hoverHint
		local art = if hint ~= nil then CURSOR_ART[hint] else nil
		if art ~= nil then
			if borrowedMouseIcon == nil then
				borrowedMouseIcon = UserInputService.MouseIcon
			end
			UserInputService.MouseIcon = art
		elseif borrowedMouseIcon ~= nil then
			UserInputService.MouseIcon = borrowedMouseIcon
			borrowedMouseIcon = nil
		end
	end

	--[[ THE ONE ACTIVATE META, built in ONE place ─────────────────────────────
		activate meta: pointer kind + held modifiers, so list semantics
		(replace/toggle/range vs touch additive) resolve per device.

		SHARED, since 2026-08-13, with the minimum-target hit expander below, and
		sharing it IS the fix for a HIGH defect (redteam item 2: a synthesized
		Activate must carry the pointer kind, and this closes it). The expander
		is a second real `GuiButton` whose `Activated`
		carries its own `InputObject` — it always knew the pointer kind — but it
		sent `{ source = "hitExpander" }` and nothing else. A meta that EXISTS but
		is silent satisfies neither half of a control's `meta == nil or
		meta.pointer == "touch"` test, so every finger landing in a short row's
		44px overhang was answered as a MOUSE CLICK: measured on an edit-mode
		multi-select Table, three taps built a three-row selection and one tap in
		the overhang REPLACE-selected and discarded it, and two overhang taps
		inside the double-click window opened the row — handing a phone a
		double-tap-to-open for a verb the touch conventions reserve for zoom. The
		expander is not a different KIND of activation, it is the same control
		being pressed, so it now owes and sends the identical meta ("an adapter
		that synthesizes an activate owes the same meta a real one carries").
		`source = "hitExpander"` is retired rather than kept alongside: `source`
		is the field controls read to tell a POINTER press from a DEVICE Activate
		(`meta.source == "action"`), a third value means neither to every one of
		them, and nothing in the framework or the games ever read it. ]]
	local function pointerActivateMeta(inputObject: InputObject?): any
		local userInputType = inputObject and inputObject.UserInputType
		local pointer = "mouse"
		if userInputType == Enum.UserInputType.Touch then
			pointer = "touch"
		elseif userInputType ~= nil and string.find(tostring(userInputType), "Gamepad") ~= nil then
			pointer = "gamepad"
		elseif userInputType == Enum.UserInputType.Keyboard then
			-- NOT A POINTER AT ALL (roadmap Step 8). The engine fires the
			-- SELECTED GuiButton's Activated for a keyboard press too, and
			-- that arrived here classified as a mouse click — so the one
			-- signal that identifies an engine-selection echo of an IAS
			-- Activate was indistinguishable from a real click. Naming it
			-- is what lets the presenter collapse the pair and nothing else
			-- (see dispatchActivate).
			pointer = "keyboard"
		end
		local function down(keyCode: Enum.KeyCode): boolean
			return UserInputService:IsKeyDown(keyCode)
		end
		-- window-space tap position rides the meta so the presenter can run
		-- the modal Zone-A geometry (a scrim/catcher tap; modal-dismissal
		-- spec §3.2). InputObject.Position is inset-subtracted gui space
		-- (this ScreenGui renders IgnoreGuiInset), so add the inset.
		local tapPos = inputObject and inputObject.Position
		local guiInset = GuiService:GetGuiInset()
		return {
			source = "pointer",
			pointer = pointer,
			x = if tapPos ~= nil then tapPos.X + guiInset.X else nil,
			y = if tapPos ~= nil then tapPos.Y + guiInset.Y else nil,
			shift = down(Enum.KeyCode.LeftShift) or down(Enum.KeyCode.RightShift),
			toggle = down(Enum.KeyCode.LeftControl)
				or down(Enum.KeyCode.RightControl)
				or down(Enum.KeyCode.LeftMeta)
				or down(Enum.KeyCode.RightMeta),
		}
	end

	function adapter.setActivateHandler(handle: any, fn: (meta: any?) -> ())
		local instance = handle.instance
		-- kept on the handle so the effective-target hit expander (B-BTN3) can
		-- forward to the SAME activation path rather than becoming a second one
		handle.activate = fn
		--[[ DISCONNECT BEFORE RECONNECT (device bug fix, director 2026-08-23:
			nested-tabs hit targets shift after a bottom-tab round trip; task CONN
			moved this to the shared `screen_vocabulary.reconnect` helper — see
			its header for the general rule this is the original case of). This
			call runs once per (path, fresh-or-adopted handle) —
			`render/renderer.luau`'s create-or-adopt block calls it right after
			choosing the engine object — and a RECYCLED instance (`adapter.adopt`,
			instance recycling ON by default) is never destroyed between lives,
			only reparented. Without the disconnect, `instance.Activated` kept
			every PRIOR life's connection — each one a closure over
			`local path = node.path` from a DIFFERENT commit, bound to whatever
			node this physical instance used to represent — and a single real
			click fired all of them, `dispatchNodeTapOnce` keyed per PATH so it
			let every one through. Measured live: `tab_view`'s nested page strip,
			Pages -> Notes -> Pages, a tap on "Clothing"'s own painted rect
			selected "Backgrounds" — a recycled button carrying a stale listener
			from an earlier occupant. Toggle/Button are otherwise never
			reactivated on the SAME handle without a path change, so this is a
			leak fix, not a behavior change for the non-recycled case. ]]
		reconnect(handle, "activatedConn", function(): RBXScriptConnection?
			if instance:IsA("GuiButton") then
				return instance.Activated:Connect(function(inputObject: InputObject)
					fn(pointerActivateMeta(inputObject))
				end)
			end
			return nil
		end)
	end

	-- pointer capture: down on the zone captures; global move/up
	-- route to it until release, and the zone's cursor hint stays applied
	local activeCapture: any = nil
	local function endCapture(cancelReason: string?)
		if activeCapture == nil then
			return
		end
		local captured = activeCapture
		if cancelReason ~= nil and captured.handle.pointer and captured.handle.pointer.cancel then
			local keep = captured.handle.pointer.cancel(cancelReason)
			if keep == true and cancelReason == "removed" then
				-- a drag-owned LIFT unmounted its own origin row: the capture
				-- (global UIS connections + closured handlers) stays alive so
				-- the drag can finish
				return
			end
		end
		for _, connection in captured.connections do
			connection:Disconnect()
		end
		activeCapture = nil
		captureHint = nil
		applyCursor()
	end

	-- Escape opens the Roblox CoreGui menu and CANNOT be intercepted (engine
	-- truth D1: the key is permanently core-reserved). The next best drag UX
	-- (director round 2): the moment the menu opens, ANY live pointer capture
	-- aborts — no stuck drags behind the menu. Adapter-level: every draggable
	-- gets this, not just tables. Disconnected on destroyRoot.
	local menuConn = GuiService.MenuOpened:Connect(function()
		endCapture("interrupted")
	end)

	-- ENGINE TRUTH (verified live 2026-07-19): InputObject.Position is in the
	-- inset-subtracted gui space (topbar excluded) while this adapter renders
	-- with IgnoreGuiInset=true, whose AbsolutePositions are window space — so
	-- pointer positions must add the gui inset before reaching drag math,
	-- which compares against solver rects (window space).
	local function toWindowSpace(
		position: Vector3,
		pointerType: string?
	): { x: number, y: number, pointerType: string? }
		local inset = GuiService:GetGuiInset()
		return { x = position.X + inset.X, y = position.Y + inset.Y, pointerType = pointerType }
	end
	local function pointerTypeOf(inputObject: InputObject): string
		return if inputObject.UserInputType == Enum.UserInputType.Touch then "touch" else "mouse"
	end

	-- ENGINE CONNECTION CENSUS (roadmap Step 4, metric M4). Read-only.
	--
	-- The slot list is derived from the REAL assignment sites, not invented: the
	-- first version of this function counted four names that exist nowhere in
	-- the repository (they were permanently 0) while missing nine connections
	-- that do exist — a census that could only ever undercount, reported as if
	-- it were complete. The platform review caught it; the list below is grepped
	-- from `handle.<name>Conn* = ...:Connect(` in this file and screen_chrome.
	--
	-- What it counts: adapter-held RBXScriptConnections reachable from a handle.
	-- What it does NOT count, and says so: connections held in closures rather
	-- than on a handle (the pointer-capture list, UIDragDetector handlers, touch
	-- gesture handlers and the scroll-position observer all return a detach
	-- function and keep their connections captured), and anything the engine
	-- allocates internally, which no script can see.
	local CENSUS_SLOTS = {
		"activatedConn",
		"pointerBeganConn",
		"hitExpanderPointerConn",
		"hoverEnterConn",
		"hoverLeaveConn",
		"hoverStateConn",
		"discloseEnterConn",
		"discloseLeaveConn",
		"discloseTouchConn",
		"scrollConn",
		"textChangedConn",
		"focusedConn",
		"focusLostConn",
		"oskReturnConn",
		"chromeOverrideConn",
		"barConn",
		"barWindowConn",
		-- a LIST of connections rather than one (screen_chrome's text lift)
		"chromeTextConns",
	}
	function adapter.connectionCensus(): any
		local perSlot: { [string]: number } = {}
		for _, slot in CENSUS_SLOTS do
			perSlot[slot] = 0
		end
		local nodes = 0
		for _, handle in handlesByPath do
			nodes += 1
			for _, slot in CENSUS_SLOTS do
				local v = (handle :: any)[slot]
				if type(v) == "table" then
					perSlot[slot] += #v
				elseif v ~= nil then
					perSlot[slot] += 1
				end
			end
		end
		local handleTotal = 0
		for _, n in perSlot do
			handleTotal += n
		end
		-- the adapter's own always-on connection, counted by LIVENESS rather
		-- than as a constant 1
		local global = if menuConn ~= nil and menuConn.Connected then 1 else 0
		local captureHeld = 0
		if activeCapture ~= nil and activeCapture.connections ~= nil then
			captureHeld = #activeCapture.connections
		end
		return {
			nodes = nodes,
			perSlot = perSlot,
			handleTotal = handleTotal,
			global = global,
			captureHeld = captureHeld,
			total = handleTotal + global + captureHeld,
			excluded = {
				"connections captured in closures rather than stored on a handle: UIDragDetector "
					.. "(setDragDetector), touch gestures (setTouchGestureHandlers) and the CanvasPosition "
					.. "observer (observeScroll) each return a detach function and hold their connection there",
				"anything the engine allocates internally, which is not observable from script",
			},
			note = "adapter-held RBXScriptConnections reachable from a handle, plus the live global and any "
				.. "in-flight pointer capture. An undercount by construction, and the exclusions are listed "
				.. "rather than implied.",
		}
	end

	--[[ WHAT A PRESS ON A POINTER ZONE STARTS, IN ONE BODY, FOR BOTH SURFACES THAT
		CAN RECEIVE IT (director ruling, 2026-08-14: a 44px touch floor under an
		8px divider).

		A control whose solved rect is under its contract's `minHitSize` gets a
		second real `TextButton` from `setHitRect` — the `FacetHitExpander`, a
		sibling at `host.z - 1`. Until now that button was wired to `handle.activate`
		ALONE, and `activate` is assigned for TAPPABLE classes only (Button, Toggle,
		TextField). A `Grip` is a POINTER ZONE, not a tappable, so its expander was a
		GuiButton that SANK `InputBegan` and forwarded nothing — and a GuiButton sinks
		it for everything underneath too — a button eats the swipe under it.

		Measured live on the Table's 8x28 resize divider: a click in the 26px band the
		expander covers did NOTHING, while the same click clear of it cycled the sort.
		And the floor bought the grip nothing either — the expander sits BEHIND the
		control, so it never widened the draggable band: the resize target stayed
		8x28 = 224px^2 against the 1936px^2 a finger needs.

		So the expander runs the host's gesture as well, and it is the SAME body
		extracted rather than a second copy: the expander's whole contract is "a press
		here is a press on the host", and two spellings of what a press starts is
		exactly how the two surfaces come to disagree. The tap half of the repair is
		the control's — a zone that decides the press was not its gesture forwards it
		on through `controller.tapAt` (row_actions' ruling 6 machinery, reused). ]]
	local function beginPointerCapture(handle: any, handlers: any, inputObject: InputObject)
		if
			inputObject.UserInputType ~= Enum.UserInputType.MouseButton1
			and inputObject.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		-- a live capture OWNS the pointer until it ends: crossing another
		-- pointer zone mid-drag fires that zone's InputBegan, which used
		-- to silently kill the capture (no cancel reason -> stuck ghost,
		-- no drop commit; live-found in the playlist place 2026-07-20)
		if activeCapture ~= nil then
			-- REDTEAM FIX (item 14, LOW). `destroyRoot`'s own
			-- capture-cancel (below) only ever fires for a capture
			-- belonging to the ROOT being destroyed — correct for a
			-- whole-root teardown, but a captured node that dies
			-- through some OTHER path (a single-row removal that
			-- destroys its own Instance directly, say) leaves
			-- `activeCapture` pointing at a destroyed instance
			-- forever: a destroyed instance has no parent chain at
			-- all, so `IsDescendantOf` is false against EVERY root —
			-- no `destroyRoot` call, on ANY root, ever reaches it.
			-- The adapter's single capture slot then blocks every
			-- future press permanently (the comment above: "a live
			-- capture OWNS the pointer... never a steal") — a
			-- genuine adapter-wide input death. A pcall-guarded
			-- liveness check (per code review) treats a capture
			-- whose own instance is no longer part of the live tree
			-- at all as already-ended, cleaning it up here instead
			-- of leaving it to never end.
			local ok, stillLive = pcall(function()
				return (activeCapture.handle.instance :: Instance):IsDescendantOf(game)
			end)
			if ok and stillLive then
				return
			end
			endCapture("destroyed")
		end
		local connections = {}
		activeCapture = { handle = handle, connections = connections }
		captureHint = handle.cursorHint
		applyCursor()
		--[[ THE CAPTURE BELONGS TO THE FINGER THAT OPENED IT (2026-08-17).

			`UserInputService.InputChanged`/`InputEnded` are GLOBAL: with two fingers
			down, the second one's moves drove the first one's drag and the second
			one's lift ENDED it. The engine hands the same `InputObject` back for the
			whole life of one touch, so identity is the filter — and it is applied to
			TOUCH only, because a mouse drag legitimately mixes objects (the moves
			arrive as `MouseMovement`, the release as `MouseButton1`, and they are
			never the same object). ]]
		local originatingTouch: InputObject? = if inputObject.UserInputType == Enum.UserInputType.Touch
			then inputObject
			else nil
		local function fromThisPointer(other: InputObject): boolean
			return originatingTouch == nil
				or other.UserInputType ~= Enum.UserInputType.Touch
				or other == originatingTouch
		end
		table.insert(
			connections,
			UserInputService.InputChanged:Connect(function(moveObject: InputObject)
				if not fromThisPointer(moveObject) then
					return
				end
				if
					moveObject.UserInputType == Enum.UserInputType.MouseMovement
					or moveObject.UserInputType == Enum.UserInputType.Touch
				then
					if handlers.move then
						handlers.move(
							toWindowSpace(
								moveObject.Position,
								if moveObject.UserInputType == Enum.UserInputType.Touch then "touch" else "mouse"
							)
						)
					end
				end
			end)
		)
		table.insert(
			connections,
			UserInputService.InputEnded:Connect(function(endObject: InputObject)
				if not fromThisPointer(endObject) then
					return
				end
				if
					endObject.UserInputType == Enum.UserInputType.MouseButton1
					or endObject.UserInputType == Enum.UserInputType.Touch
				then
					if handlers.up then
						handlers.up(toWindowSpace(endObject.Position, pointerTypeOf(endObject)))
					end
					endCapture()
				end
			end)
		)
		if handlers.down then
			local claimed = handlers.down(toWindowSpace(inputObject.Position, pointerTypeOf(inputObject)))
			-- a zone may DECLINE (return false): dissolve this capture so
			-- the engine's next InputBegan (another zone under the same
			-- point, e.g. the edit handle above a row body) can claim it
			if claimed == false then
				for _, connection in connections do
					connection:Disconnect()
				end
				activeCapture = nil
				captureHint = nil
				applyCursor()
			end
		end
	end

	-- one wiring, used for the control's own instance and for its hit expander
	local function connectPointerBegan(handle: any, instance: GuiObject, handlers: any): RBXScriptConnection
		return instance.InputBegan:Connect(function(inputObject: InputObject)
			beginPointerCapture(handle, handlers, inputObject)
		end)
	end

	function adapter.setPointerHandlers(handle: any, handlers: any)
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return
		end
		handle.pointer = handlers
		-- DISCONNECT BEFORE RECONNECT (task CONN, Finding 1): this setter runs
		-- once per (path, fresh-or-adopted handle), same cadence as
		-- `setActivateHandler` above — an unconditional overwrite here left a
		-- recycled handle's PRIOR life's `handlers` (closed over that life's
		-- `path`/`props`) live beside the fresh one, and `beginPointerCapture`'s
		-- single-capture-slot rule made the STALE, earlier-connected listener the
		-- likely winner of a real press (see review-fix234-findings.md Finding 1).
		reconnect(handle, "pointerBeganConn", function()
			return connectPointerBegan(handle, instance, handlers)
		end)
		-- SAME-LIFE ORDER-INDEPENDENT, RECYCLE-SAFE (task CONN, Finding 4):
		-- `setHitRect` may run before or after this (the renderer pushes hit
		-- geometry from the solve, handlers from the structural sync), so each
		-- side wires the expander if the other got there first. `handle.path` is
		-- the identity `reconnectOnChange` compares: unchanged within one life
		-- (whichever side runs first stamps it, the second is a no-op —
		-- preserving the property the old `== nil` guard existed for), and it is
		-- already the generation stamp a park->adopt recycle provides (`adopt`
		-- reassigns it), so a handle recycled into a new identity gets a genuine
		-- disconnect-and-rewire instead of the permanent misroute the `== nil`
		-- guard could never distinguish from "already correct".
		if handle.hitExpander ~= nil then
			reconnectOnChange(handle, "hitExpanderPointerConn", "hitExpanderPointerConnPath", handle.path, function()
				return connectPointerBegan(handle, handle.hitExpander, handlers)
			end)
		end
		-- hover: request/clear the zone's semantic cursor
		if handle.class == "Grip" then
			reconnect(handle, "hoverEnterConn", function()
				return instance.MouseEnter:Connect(function()
					hoverHint = handle.cursorHint
					applyCursor()
				end)
			end)
			reconnect(handle, "hoverLeaveConn", function()
				return instance.MouseLeave:Connect(function()
					hoverHint = nil
					applyCursor()
				end)
			end)
		end
	end

	-- wheel scrolling (Phase 4 touch-scroll design): hover-wheel input on a
	-- scroll container routes to the renderer-wired handler
	function adapter.setScrollHandler(handle: any, fn: (number) -> ())
		local instance = handle.instance
		if not instance:IsA("GuiObject") then
			return
		end
		-- DISCONNECT BEFORE RECONNECT (task CONN, Finding 1): `fn` closes over the
		-- caller's `path`/`props` at THIS call, so an unconditional overwrite left
		-- a recycled handle answering wheel input on a prior life's path forever.
		reconnect(handle, "scrollConn", function()
			return instance.InputChanged:Connect(function(inputObject: InputObject)
				if inputObject.UserInputType == Enum.UserInputType.MouseWheel then
					fn(inputObject.Position.Z)
				end
			end)
		end)
	end

	-- THE HOST'S THREE READS OF THE LIVE CAPTURE, as one question: `park` refuses
	-- to recycle a captured node, and `remove`/`destroyRoot` each have to end a
	-- capture that points into what they are destroying (the alternative is a
	-- global capture aimed at a dead instance, which blocks every future press —
	-- redteam item 14). A number or a slot cannot travel by reference, so it
	-- travels as the question instead.
	local function capturedHandle(): any?
		return if activeCapture ~= nil then activeCapture.handle else nil
	end

	-- destroyRoot's whole-adapter teardown: the always-on menu connection, and any
	-- cursor hint left over. The hint is released REGARDLESS of whose capture set
	-- it — a hint from a capture on another root is already stale as of this root's
	-- teardown.
	--[[ TWO TEARDOWNS, NOT ONE (2026-08-17). `disposeGlobals` used to
		disconnect the adapter-wide `MenuOpened` connection on ANY `destroyRoot`,
		and an adapter hosts several roots at once — the presenter mounts and
		retires a transient popup-catcher root reactively, so the FIRST such
		retirement killed drag-abort-on-menu for every remaining root, for the rest
		of the session. Escape cannot be intercepted, so the abort is the only thing
		standing between an open CoreGui menu and a stuck drag behind it.

		The CURSOR half is genuinely per-root and stays that way: a hint from a
		capture on a root that is going away is stale the moment it goes. So the
		host calls `releaseCursorHint` on every teardown and `disposeGlobals` only
		when the last root goes. ]]
	local function releaseCursorHint()
		hoverHint = nil
		applyCursor()
	end
	local function disposeGlobals()
		menuConn:Disconnect()
		captureHint = nil
		releaseCursorHint()
	end

	return {
		setActivateHandler = adapter.setActivateHandler,
		setPointerHandlers = adapter.setPointerHandlers,
		setScrollHandler = adapter.setScrollHandler,
		connectionCensus = adapter.connectionCensus,
		pointerActivateMeta = pointerActivateMeta,
		connectPointerBegan = connectPointerBegan,
		endCapture = endCapture,
		menuConn = menuConn,
		capturedHandle = capturedHandle,
		releaseCursorHint = releaseCursorHint,
		disposeGlobals = disposeGlobals,
		beginPointerCapture = beginPointerCapture,
	}
end

return screen_pointer
