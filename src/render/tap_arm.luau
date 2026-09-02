--!strict
--[[ ── ONE ACTIVATION PER PRESS, AND THE ARM DISPATCH BESIDE IT ───────────────

	Lifted out of `render/renderer.luau` on 2026-09-01, BYTE-VERBATIM in its bodies,
	because the source-cap ledger's row for that file names this block as its next
	seam and says when it comes out: *before the next round that changes tap
	dispatch, the arm paradigm or the recycle pool / removal sweep / parked-props
	record.* Perf campaign P5 changes the removal sweep, so the extraction PRECEDES
	the product change rather than accompanying it — which is what the wording has
	demanded of every split this file has taken.

	WHAT IS HERE. Two questions a press has to answer before it means anything, and
	the four per-path records they own:

	  * IS THIS PRESS A SECOND SIGNAL FOR A PRESS ALREADY DISPATCHED?
	    (`dispatchNodeTapOnce`, `detectorTapGuard`, `lastNodeTapAt`)
	  * DOES THIS PRESS PICK SOMETHING UP INSTEAD OF ACTIVATING IT?
	    (`tapArmsInstead` for the touch paradigm's `armOnTap`, `activateArms` for the
	    non-pointer arm→navigate→commit verb, `armedBySeam`, `armOnTapDecl`,
	    `armedHere`)

	WHY IT COULD LEAVE, in this repository's own terms. Three of the four records are
	tables declared inside the block and read nowhere else, so THE STATE LEFT WITH THE
	CODE. The fourth, `armedHere`, is the shape the ledger warned about — a REASSIGNED
	SCALAR with a writer outside the block (`controller.cancelArmed`) — so it takes the
	accessor move `controls/table.luau` and `render/drag_bridge.luau` both proved:
	it is a local here, written on exactly three lines, and the renderer holds no copy.
	`disarm()` is that writer's replacement and it is the ONLY way out of this module's
	one mutable scalar.

	THREE NAMES CROSS, all by reference and none reassigned: `dragBridge` (the
	registry accessor pair — `peek()` never builds, which every read here depends on:
	"there is no registry" MEANS "no declaring source is mounted"), `dragSourceEnabled`
	(the per-path live gate the renderer writes at declaration time and the registry
	consults per acquisition) and `dragCollaborators` (whose `now` is what makes the
	echo window drivable from a spec).

	`TAP_ECHO_WINDOW` is at module scope rather than inside the constructor because it
	is a constant of the paradigm and not of a surface; it is exported for the spec
	that pins it.
]]

local tap_arm = {}

--[[ 50 ms is far below any human double-tap, so a real second tap is never eaten,
	and far above the gap between an engine `Activated` and a detector's release
	synthesis for the same press. ]]
local TAP_ECHO_WINDOW = 0.05
tap_arm.TAP_ECHO_WINDOW = TAP_ECHO_WINDOW

export type Deps = {
	-- `render/drag_bridge`: `peek()` (never builds) is the only half read here
	dragBridge: any,
	-- path -> "may this source be picked up right now", written by the renderer's
	-- drag declaration wiring and read here per press
	dragSourceEnabled: { [string]: () -> boolean },
	-- the injectable collaborators; only `now` is read, and only by the echo window
	dragCollaborators: { [string]: any },
}

export type TapArm = {
	tapArmsInstead: (path: string, meta: any?) -> boolean,
	armedBySeam: () -> boolean,
	activateArms: (path: string, meta: any?) -> boolean,
	dispatchNodeTapOnce: (path: string) -> boolean,
	-- the four per-path record writers the renderer keeps, so the records themselves
	-- never leave this file
	declareSource: (path: string, armOnTap: boolean) -> (),
	forgetSource: (path: string) -> (),
	guardDetector: (path: string) -> (),
	forgetDetector: (path: string) -> (),
	-- the ONE writer of `armedHere` outside this module's own two seams
	disarm: () -> (),
}

function tap_arm.new(deps: Deps): TapArm
	local dragBridge = deps.dragBridge
	local dragSourceEnabled = deps.dragSourceEnabled
	local dragCollaborators = deps.dragCollaborators

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
		local reg = dragBridge.peek()
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
		local reg = dragBridge.peek()
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
		local reg = dragBridge.peek()
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
	return {
		tapArmsInstead = tapArmsInstead,
		armedBySeam = armedBySeam,
		activateArms = activateArms,
		dispatchNodeTapOnce = dispatchNodeTapOnce,
		declareSource = function(path: string, armOnTap: boolean)
			armOnTapDecl[path] = armOnTap == true or nil
		end,
		forgetSource = function(path: string)
			armOnTapDecl[path] = nil
		end,
		guardDetector = function(path: string)
			detectorTapGuard[path] = true
		end,
		-- BOTH records, always: the echo timestamp is meaningless without the guard
		-- that reads it, and a path is REUSED across a remount
		forgetDetector = function(path: string)
			detectorTapGuard[path] = nil
			lastNodeTapAt[path] = nil
		end,
		disarm = function()
			armedHere = false
		end,
	}
end

return tap_arm
