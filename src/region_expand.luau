--!strict
--[[ THE EXPAND — a stepped-down region discloses its richest form (wave REVEAL).

	`src/layout/composition.luau` decides WHICH form of a region is standing and
	reports whether the player is therefore looking at less than the region has
	(`expandable`, and the `plate` box that would hold the rest). This file is the
	other half: what opens the disclosure, what closes it, and what is left behind
	when it goes.

	WHY IT IS A ROOT LEAF. `UI.Region` synthesizes the affordance, so the thing
	that owns the presentation has to be reachable from `src/blueprint.luau` — and
	`src/present/` requires `blueprint`, so anything under it would be a cycle.
	This module therefore requires NOTHING (the `src/class_contract.luau` shape):
	every blueprint it needs arrives as a BUILDER from the caller, and every
	presenter function arrives through the contribution seam. That is also what
	makes it testable with two table doubles and no mount.

	WHAT IT DOES NOT OWN, and the list is the point:
	  * the PLACEMENT is `presenter.presentAnchored`'s (D1) — edge flip, safe-area
	    clamp, moving-source follow, arrow tail, all shipped;
	  * the DISMISSALS are the presented surface's own. The plate is presented
	    `modal` over a catching scrim (dimmed at the theme's own token — see
	    `anchoredOpts`, and the three reports that decided it), and that ONE
	    decision buys three of the four routes the contract
	    asks for: a tap outside dismisses (`outsideTapCancel`), gamepad B dismisses
	    (the default `cancelPolicy`), and the focus scope is pushed and POPPED — so
	    focus returns to the affordance that opened it without this file holding a
	    path or a restore of its own. ESCAPE IS NOT ON THAT LIST AND CANNOT BE: it
	    is permanently bound to the Roblox CoreGui menu and the engine refuses the
	    binding (ADR-0013 §Justified exceptions), so the KEYBOARD route out is the
	    close affordance `blueprint.luau` puts in the panel — a modal traps the
	    ring, which is what makes the ring the whole keyboard story;
	  * the SIZE is the composition's (`plate.w`), and whether a plate is possible
	    at all is too (`plate.sheet`).

	WHY MODAL, when the brief's fourth dismissal route is "focus loss". A plate
	that does not trap focus strands its own contents: this repository measured it
	on the HUD paint probe, where "a second base surface's focusables are in
	NEITHER surface's traversal ring, in either responder mode", so a keyboard or
	gamepad player could see the disclosed form and never reach a control in it.
	The richest form is exactly the form most likely to HOLD controls. So focus
	loss becomes structural rather than incidental: the scope is the plate's, and
	the fourth route is served by the epoch check below instead.

	THE EPOCH CHECK IS THE ONE ORIGINAL MECHANISM HERE, and it is four lines. A
	plate is anchored to a rect the composition owns. `syncGeometry` runs on every
	solve and every frame (the presenter's own cadence, "asking nothing new of any
	caller"), so the engine re-reads that rect and CLOSES when it has moved,
	resized, or gone. Rotation, a viewport change, a theme-metric change and a
	re-solve that put the region back on its richest form are all the same event
	from the player's side — the thing they opened this against is not there any
	more — and one rule covers every one of them without a single new controller
	API. The alternative, following the source, is what a TOOLTIP wants; a
	disclosure that survives a rotation is a plate pointing at a box that moved.
]]

local region_expand = {}

export type Plate = { w: number, h: number, sheet: boolean }
export type Facts = { expandable: boolean, activeForm: number, plate: Plate? }

export type Config = {
	-- the region's authored id, for the surface name and every diagnostic
	id: string,
	-- the plate's CONTENT at a resolved width: the region's own form 1, wrapped by
	-- the caller (which is the only layer that may build blueprints). It takes the
	-- whole `plate` record — the width AND the cap it was measured against — because
	-- the caller has one correction to make that the pure pass cannot (see its own
	-- note in `blueprint.luau`)
	panelOf: (any) -> any,
	-- the same content as a full-width sheet SCREEN, for the offer where the plate
	-- cannot meet its floor
	sheetOf: () -> any,
	-- an authored handler REPLACES both presentations (`expand = function`)
	handler: (() -> ())?,
	--[[ WHERE THE FACTS COME FROM, when they are not the composition's (wave
		TABLE, 2026-08-18). Everything below this line — the anchored plate, the
		sheet fallback, the four dismissal routes, the toggle-on-second-press, the
		epoch check and the teardown count — is about a DISCLOSURE, not about
		`UI.Composition`. The only composition-specific thing in this file was
		`facts()`, which reads the region's row out of the last resolution dump.

		`newTable`'s column collapse is the second disclosure in the framework and
		it is not a region at all: the facts are "are any columns collapsed", and
		the plate's width is the table's own measured content width. Handing them in
		is what let that feature reuse this whole file rather than grow a second
		overlay beside it — which is the standing rule ("do not build a second
		overlay system"), and it cost six lines.

		Absent, the composition read below is used, byte-identical for every
		`UI.Region`. The argument is the anchor path this engine is currently
		tracking, so a caller keyed by path needs no state of its own. ]]
	factsOf: ((anchorPath: string?) -> Facts?)?,
}

local function parentPath(path: string): string?
	-- the composition is the region's parent by construction (`UI.Composition`
	-- refuses a child that is not a `UI.Region`), so this is a strip, not a search
	return string.match(path, "^(.*)/[^/]+$")
end

local function rectOfPath(rectOf: any, path: string?): any
	if rectOf == nil or path == nil then
		return nil
	end
	local ok, rect = pcall(rectOf, path)
	return if ok then rect else nil
end

function region_expand.new(config: Config)
	local self = {} :: any
	local regionPath: string? = nil
	local controller: any = nil
	local presentAnchoredFn: any = nil
	local presentModalFn: any = nil
	local dismissFn: any = nil
	local handle: any = nil
	local mode: string? = nil -- "anchored" | "sheet" while open
	-- the rect the plate was opened against; the epoch check compares against it
	local openedAgainst: any = nil
	local teardowns = 0
	-- guards the dismiss we drive ourselves against the one the presenter drives
	local closing = false

	--[[ THE FACTS, READ FROM THE LAST SOLVE rather than recomputed. The renderer
		publishes each `UI.Composition` node's resolution dump, keyed by path; the
		region's own row is in it under the region's path. Nothing here re-derives
		"is this stepped down" — that is the composition's ruling and there is
		exactly one of it. ]]
	local function facts(): Facts?
		-- a caller that owns its own facts answers first, and never consults the
		-- composition dump at all (see `Config.factsOf`)
		if config.factsOf ~= nil then
			return (config.factsOf :: any)(regionPath)
		end
		if controller == nil or controller.compositionAt == nil or regionPath == nil then
			return nil
		end
		local parent = parentPath(regionPath :: string)
		if parent == nil then
			return nil
		end
		local ok, dump = pcall(controller.compositionAt, parent)
		if not ok or type(dump) ~= "table" then
			return nil
		end
		for _, row in (dump :: any).regions or {} do
			if row.id == regionPath then
				return { expandable = row.expandable == true, activeForm = row.activeForm or 0, plate = row.plate }
			end
		end
		return nil
	end

	local function close(_reason: string?)
		if handle == nil then
			return
		end
		local h = handle
		handle = nil
		mode = nil
		openedAgainst = nil
		teardowns += 1
		if dismissFn ~= nil then
			closing = true
			pcall(dismissFn, h)
			closing = false
		end
	end

	--[[ ONE SET OF PRESENT OPTIONS, and every dismissal route is in it. `modal`
		catches the outside tap, so it closes the plate and never clicks through to
		the HUD underneath. `cancelPolicy` is left at its default (`dismiss`), which is
		what makes gamepad ButtonB close it (Escape cannot be bound on this platform, so the
		panel's own close affordance is the keyboard route). No `transition` is declared, so
		the plate PLACES rather than travels — which is the reduced-motion answer by
		construction rather than by a branch that only one player ever exercises.

		`scrim = "scrim"`, AND THE THIRD REPORT OF THE SAME BUG IS WHY (director round
		5, 2026-08-21; DIR2-2 and DIR3-1 before it: "the popup background is opaque").
		MEASURED live at the third report: `/__scrim__/catcher`, full viewport,
		`GetStyled("BackgroundTransparency") = 0` — an opaque full-screen fill under a
		plate, with the roots and display orders all correct and
		`GuiService.PreferredTransparency = 1`, so it was neither a stacking bug nor
		the accessibility case.

		THE MECHANISM IS WHAT THE ROLE OWNS. `scrim = "none"` mounts the catcher as
		`surface = "plain"`, and `plain` is the SUPPRESSED surface: it earns no
		`facet-surface-*` tag, so nothing in the sheet's vocabulary can address it and
		its transparency is whatever the CLASS DEFAULT rule happens to leave — a value
		this file neither states nor owns, on the one node in the framework that
		covers the entire screen. `scrim` is the opposite: the role carries the
		theme's own `scrimOpacity` through `sheet_model.SCRIM_RULE`, it is the ONE
		rule the player's `PreferredTransparency` composes against (ADR-0035,
		`PREFERENCE_RULE_PROPS`), and a package that ships an opaque one is caught by
		`transient_over_live.spec` across all eight.

		It is also the right PRODUCT answer, which is why this is not merely a
		robustness fix: a disclosure plate is a modal that covers content, and the
		dim is how a player is told the screen behind it is not live. The Menu keeps
		`none` — a menu is a small list at a button, not a plate over the screen. ]]
	local function anchoredOpts(): any
		return {
			id = `Expand:{config.id}`,
			modal = true,
			scrim = "scrim",
			outsideTapCancel = true,
			anchor = {
				source = { path = regionPath },
				edge = "bottom",
				align = "start",
				gap = "s",
				--[[ NO TAIL (director device round, 2026-08-21: "the plate alone on a
					blank background"). The wedge and its seam are the only nodes this
					overlay contributes that paint OPAQUELY by design — the seam is a
					`surface = "base"` band carrying a reconstructed `surfaceStrong` tint —
					and this feature anchors plates to zone pills pressed against the
					screen edges, which is the geometry the shipped tailed surfaces (a
					toolbar button, a disc in the middle of a strip) never gave the
					placement machinery. A disclosure that opens at its own region does
					not need an arrow to say where it came from; nothing that can paint
					over the screen is worth that.

					`rootPolicy` is not passed either: `presentAnchored` forces
					`edgeToEdge` for every anchored surface (anchored.luau), so declaring
					it here said nothing and read like a choice. What remains is exactly
					the Menu's shipped option set — the one anchored modal this
					repository has already proven on a device. ]]
				tail = false,
			},
		}
	end

	--[[ OPEN. Returns the presentation it chose, or nil when there was nothing to
		open — and "nothing to open" is a real answer rather than a failure: a
		region that is standing on its richest form has nothing more to show, and a
		plate that opened anyway would be a duplicate of what is already on screen. ]]
	function self.open(): string?
		if config.handler ~= nil then
			pcall(config.handler)
			return "custom"
		end
		if handle ~= nil then
			-- a second activation on an open plate CLOSES it: the affordance is the
			-- same control the player just used, and leaving it inert is how a
			-- disclosure becomes a trap on touch
			close("toggle")
			return nil
		end
		local f = facts()
		if f == nil or not f.expandable or f.plate == nil then
			return nil
		end
		local plate = f.plate :: Plate
		if plate.sheet then
			if presentModalFn == nil then
				return nil
			end
			handle = (presentModalFn :: any)(config.sheetOf(), {
				scrim = "scrim",
				outsideTapCancel = true,
			})
			mode = "sheet"
		else
			if presentAnchoredFn == nil or regionPath == nil then
				return nil
			end
			handle = (presentAnchoredFn :: any)(config.panelOf(plate), anchoredOpts())
			mode = "anchored"
		end
		if handle ~= nil then
			openedAgainst = rectOfPath(if controller ~= nil then controller.rectOf else nil, regionPath)
			--[[ EVERY DISMISS PATH, not only the ones this file drives. An outside tap
				is torn down inside the presenter and never comes back through `close`,
				so without this the engine would hold a dead handle and refuse to open
				again — the defect `row_actions` and the Menu each found live and each
				fixed exactly here. ]]
			if handle.onFeedback ~= nil then
				local mine = handle
				handle.onFeedback(function(event: any)
					if type(event) == "table" and event.type == "dismiss" and not closing and handle == mine then
						handle = nil
						mode = nil
						openedAgainst = nil
						teardowns += 1
					end
				end)
			end
		end
		return mode
	end

	function self.close()
		close("caller")
	end

	function self.state(): string
		return mode or "closed"
	end

	-- TEARDOWN, COUNTED. Every route out of the plate increments it exactly once —
	-- the caller's, the affordance's second press, the epoch check's, and the
	-- presenter's own outside-tap — which is what a leak test can assert against.
	function self.teardowns(): number
		return teardowns
	end

	function self.facts(): Facts?
		return facts()
	end

	--[[ THE EPOCH CHECK. Called on every solve and every frame through the
		contribution seam. Two rect reads and no writes while nothing is open. ]]
	function self.sync(rectOf: any, rootNode: any?)
		if rootNode ~= nil and rootNode.path ~= nil then
			regionPath = rootNode.path
		end
		if handle == nil then
			return
		end
		local now = rectOfPath(rectOf, regionPath)
		if now == nil or now.w == nil or now.w <= 0 or now.h <= 0 then
			close("gone")
			return
		end
		local was = openedAgainst
		if was == nil then
			openedAgainst = now
			return
		end
		if now.x ~= was.x or now.y ~= was.y or now.w ~= was.w or now.h ~= was.h then
			close("epoch")
			return
		end
		local f = facts()
		if f ~= nil and not f.expandable then
			-- the region climbed back to its richest form under the plate: what the
			-- plate is showing is now on the screen behind it
			close("richest")
		end
	end

	--[[ THE CONTRIBUTION `UI.Region` attaches to its own node. Three fields, all of
		them the shipped seam: the presenter hands over what a blueprint cannot
		construct, and this file holds no reference back to the presenter object. ]]
	self.contribution = {
		syncGeometry = function(rectOf: any, rootNode: any?)
			self.sync(rectOf, rootNode)
		end,
		bindPresent = function(presentModal: any, dismiss: any, presentAnchored: any)
			presentModalFn = presentModal
			dismissFn = dismiss
			presentAnchoredFn = presentAnchored
		end,
		bindController = function(ctrl: any)
			controller = ctrl
		end,
		--[[ THE SECOND ROUTE TO THE SAME PLATE. A screen's overflow census lists what
			the screen has stopped showing, and its row for a SIMPLIFIED region opens
			this — through `presenter.expand(regionPath)`, which finds this bundle by
			the same longest-prefix dispatch an Activate uses. One region, one plate:
			a census that built its own would be a second thing to keep in step. ]]
		expandOpen = function(): string?
			return self.open()
		end,
	}

	return self
end

return region_expand
