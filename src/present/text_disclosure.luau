--!strict
--[[ TextDisclosure — the FULL-VALUE DISCLOSURE plate: the one static plate a
	truncated `disclose` (or `reveal`) label raises on hover dwell, keyboard or
	gamepad focus, or touch long-press, plus its clamp, revalidation and dump.
	Extracted from src/present/presenter.luau for Studio's 200,000-character
	`Source` WRITE cap.

	WHY THIS IS A SAFE SEAM: the block owns its two mutable locals
	(`disclosurePlate`, `disclosureDwell`) and every writer of them, one set per
	`new` — never module state. Everything else arrives on `ctx` and is BORROWED:
	the presented `stack`, the focus `graph`, the handles, `env` and the
	presenter's `safeBox`/`handleOwning`/`metricsNow` are read, never written or
	copied. `isDisposed` is a live getter, not a snapshot. The plate's own scope,
	root, controller and offset cells are created and released here.
	`tests/text_disclosure_seam.spec.luau` mechanises all of it.

	The presenter binds the returned delegates under its original names and keeps
	its frame order: motion -> stepDwell -> help tick -> clamp -> anchored sync.

	Strictly one-way: this never requires the presenter back. ]]

local renderer = require("../render/renderer")
local focusMap = require("./focus_map")
local anchorPlacement = require("../layout/anchor_placement")
local themeSnapshot = require("../themes/snapshot")
local Compose = require("../vendor/compose/core")
local cleanup = require("../core/cleanup")

local isHiddenPath = focusMap.isHiddenPath
local nodeAt = focusMap.nodeAt
local contributionsForPath = focusMap.contributionsForPath

local textDisclosure = {}

function textDisclosure.new(ctx: any)
	local core = ctx.core
	local env = ctx.env
	local adapter = ctx.adapter
	local graph = ctx.graph
	local stack = ctx.stack
	local motionClock = ctx.motionClock
	local mountComponent = ctx.mountComponent
	local metricsNow = ctx.metricsNow
	local safeBox = ctx.safeBox
	local handleOwning = ctx.handleOwning
	local isDisposed = ctx.isDisposed

	--[[ ===== FULL-VALUE DISCLOSURE (the large-text round) =====================

		A `UI.Text{ disclose = true }` that TRUNCATED owes the reader the whole
		string. The screen declares the debt; the presenter pays it, here, with one
		STATIC plate — no marquee and no travel; a live plate costs only its clamp's
		two reads per frame (the same round chose the static form precisely so reduced-motion parity is structural rather than a
		branch, and so the moving-label count stays zero).

		PRESENTER-PRIVATE, exactly like the scrim, the popup catcher and the toast
		layer: not in `stack`, no focus scope, no input context, no tap handler. It
		cannot be focused or traversed because there is nothing there to focus it
		WITH — that is what "presentation chrome" means, rather than a property the
		layer politely observes.

		AT MOST ONE, ACROSS EVERY SURFACE AND EVERY INPUT CLASS. Three engagements
		feed it — hover dwell (pointer), focus enter (keyboard/gamepad), long-press
		(touch) — and presenting disposes whatever was up. Two plates would be two
		answers to "what is this label", and the second would be covering the first.
		A plate already showing THIS label is left alone whichever engagement raised
		it, and only that engagement takes it down; a direct pointer/touch ask
		outranks focus, which is merely wherever focus happens to be.

		THE FACTS COME FROM THE SOLVE, NEVER FROM A RE-MEASURE. `controller.textAt`
		is the same verdict the reserved box was built from, so the plate appears
		exactly when the engine is ellipsizing and vanishes the moment a re-solve
		makes room — a second measurement here would be a second opinion.
	]]
	local DISCLOSE_ROOT = "__disclose__"
	local DISCLOSE_PLATE = `/{DISCLOSE_ROOT}/Layer/Plate`
	local DISCLOSE_LABEL = `{DISCLOSE_PLATE}/Full`
	-- POINTER DWELL. A plate that appeared the instant a pointer crossed a label
	-- would fire on every pass THROUGH a list; 0.45s is the quiet delay the plan
	-- asks for, long enough to be a decision and short enough not to feel broken.
	-- Focus and long-press carry their own deliberation and present immediately.
	local DISCLOSE_DWELL = 0.45
	local DISCLOSURE_SCHEMA = "facet-disclosure-dump/1"

	local disclosurePlate: any = nil -- { scope, controller, root, owner, sourcePath, source, text }
	local disclosureDwell: any = nil -- { owner, sourcePath, text, remaining }

	-- the first TRUNCATED, DISCLOSED Text at or under `path`, in document order.
	-- Engagement names a focusable (or the label itself); the debt belongs to the
	-- Text, and a control is free to hold exactly one — a row's name cell.
	-- what a disclosing node owes. The mounted node carries the RESOLVED value,
	-- so a bound label discloses what it is currently saying rather than a Readable
	local function valueOf(n: any): (string, boolean)
		return tostring(n.props.text ~= nil and n.props.text or n.props.label), n.props.rich == true
	end

	local function disclosureTargetIn(handle: any, path: string?): (string?, string?, boolean?)
		if handle == nil or path == nil then
			return nil, nil
		end
		local ctrl = handle.controller
		if ctrl == nil or ctrl.textAt == nil then
			return nil, nil
		end
		--[[ A CONTROL MAY WIDEN THE SCOPE TO ITS OWN ROW (the adaptation wave). The default is
			"at or under the focused path", which is dead for any control whose focus
			stop is a SIBLING of its disclosed label rather than its ancestor — a
			Table's row `Hit` beside `Row/Cells/…`. The control answers for the paths
			it recognises and nil for the rest; the walk below is unchanged, so the
			hidden gate, the truncation test and the document order still decide. ]]
		local scoped = path
		for _, c in contributionsForPath(handle.contributions or {}, path) do
			if c.bundle.discloseScope ~= nil then
				local widened = c.bundle.discloseScope(path)
				if type(widened) == "string" then
					scoped = widened
					break
				end
			end
		end
		local node = nodeAt(handle.root.node, scoped)
		if node == nil then
			return nil, nil
		end
		-- A HIDDEN CANDIDATE DISCLOSES NOTHING (architecture review F-1). A
		-- losing ViewThatFits candidate keeps its mount, its rects and its
		-- textFacts — only visibility knows it does not paint. Without this
		-- gate, focusing a row whose RICH candidate lost raised a plate for a
		-- string that is nowhere on screen.
		--[[ ONE OWNER FOR "IS THIS PATH INSIDE A SUBTREE THAT DOES NOT PAINT"
			(the reuse audit's fourth-copy finding). `focusMap.isHiddenPath` is the published answer and
			takes the SET `hiddenRoots()` already returns, so the array this used to
			build was a conversion nobody needed. Hoisted once rather than re-read per
			node: the walk visits every node in the subtree. ]]
		local hiddenRoots: { [string]: boolean } = if ctrl.hiddenRoots ~= nil then ctrl.hiddenRoots() else {}
		local foundPath: string? = nil
		local foundText: string? = nil
		--[[ ...AND WHETHER THE VALUE IS MARKUP (fix round 1, review finding P1b-4).
			The plate shows the AUTHORED string, which for `rich = true` is markup —
			so a plate that did not parse it showed a reader `<b>Lap</b> record`. The
			flag travels beside the value for exactly that reason: they are one fact
			about one label, and separating them is how they drift. ]]
		local foundRich: boolean? = nil
		local function walk(n: any)
			if foundPath ~= nil or isHiddenPath(n.path, hiddenRoots) then
				return
			end
			-- class-AGNOSTIC on purpose (the large-text gate): any node whose measured text
			-- carries the disclose declaration owes its full value — a Text's
			-- `text`, a Toggle's one-line `label` — the facts channel is the same.
			-- A `reveal` node is a disclosure source too (2026-08-04): the static
			-- plate is the auto reveal's declared full-value alternative
			if n.props ~= nil and (n.props.disclose == true or n.props.reveal ~= nil) then
				local facts = ctrl.textAt(n.path)
				if facts ~= nil and facts.truncated == true then
					foundPath = n.path
					foundText, foundRich = valueOf(n)
					return
				end
			end
			for _, child in n.children or {} do
				walk(child)
			end
		end
		walk(node)
		return foundPath, foundText, foundRich
	end

	local function disposeDisclosure()
		if disclosurePlate == nil then
			return
		end
		local plate = disclosurePlate
		disclosurePlate = nil
		cleanup({
			plate.controller.dispose,
			function()
				plate.scope:dispose()
			end,
		})
	end

	local function dismissDisclosure(_reason: string)
		disclosureDwell = nil
		disposeDisclosure()
	end

	--[[ THE CLAMP, RE-RUNNABLE (found live 2026-08-04, RascalRally: a card
		caption's full-value plate hung off the BOTTOM of the screen). The plate's
		size is a solve output whose text measure can land ASYNCHRONOUSLY on the
		live adapter: a clamp computed once at mount used the placeholder height,
		chose "below fits", and the plate then grew past the screen edge — while
		every headless witness measured synchronously and stayed green. The clamp
		therefore FOLLOWS the live rects: `presentDisclosure` runs it at mount and
		the presenter tick re-runs it while a plate is live, so a late text
		measure, a source that moved, or a viewport change all re-place the plate
		on the next frame. The signals no-op when nothing changed, so a settled
		plate costs two reads per frame and zero writes. ]]
	local function clampDisclosure()
		local plate = disclosurePlate
		if plate == nil then
			return
		end
		local ctrl = plate.owner.controller
		local srcRect = if ctrl.screenRectOf ~= nil
			then ctrl.screenRectOf(plate.sourcePath)
			else ctrl.rectOf(plate.sourcePath)
		local safe = safeBox(plate.owner.reserveAppChrome)
		local gap = themeSnapshot.resolveNumber(metricsNow(), "xs") or 4
		-- the width ceiling follows the LIVE safe box as well: insets that grow
		-- under a live plate re-wrap it inside the new box, never past its edge
		local maxW = math.max(0, safe.w - 2 * gap)
		if plate.maxW:peek() ~= maxW then
			plate.maxW:set(maxW)
			plate.controller.refresh()
		end
		local plateRect = plate.controller.rectOf(DISCLOSE_PLATE)
		if type(srcRect) ~= "table" or type(plateRect) ~= "table" then
			return
		end
		--[[ THROUGH THE SHARED SOLVER (D1). This block WAS the first hand-rolled
			copy of the anchored-placement rules: prefer below, flip above, clamp
			into the safe box. Being a copy, it had the flip subtly wrong — it
			flipped whenever below did not fit, including when above did not fit
			either, which is the "worse place" `row_actions`' own ruling forbids (a
			plate both clipped AND on the wrong side of its label). It now asks
			`anchor_placement.solve`, which encodes both halves of that rule once. ]]
		local placement = anchorPlacement.solve({
			source = srcRect,
			size = { w = plateRect.w, h = plateRect.h },
			safe = safe,
			edge = "bottom",
			-- leading-aligned on the label, which is where a reader's eye already is
			align = "start",
			gap = gap,
		})
		if plate.ox:peek() ~= placement.x or plate.oy:peek() ~= placement.y then
			plate.ox:set(placement.x)
			plate.oy:set(placement.y)
			plate.controller.refresh()
		end
	end

	-- mount the plate near `sourcePath`, clamped into the safe box. Two passes by
	-- necessity: the plate's size is a solve output, and the clamp needs it — so
	-- it is mounted at the source's own corner, measured, then moved through the
	-- anchor offsets (reactive, `dirty = arrange`), which is a re-solve and never
	-- a remount — and the clamp KEEPS following the live rects after mount
	-- (`clampDisclosure` above).
	local function presentDisclosure(owner: any, sourcePath: string, fullText: string, source: string, rich: boolean?)
		disposeDisclosure()
		local ctrl = owner.controller
		local srcRect = if ctrl.screenRectOf ~= nil then ctrl.screenRectOf(sourcePath) else ctrl.rectOf(sourcePath)
		if type(srcRect) ~= "table" then
			return
		end
		local box = safeBox(owner.reserveAppChrome)
		local metrics = metricsNow()
		local gap = themeSnapshot.resolveNumber(metrics, "xs") or 4
		local sc = core.owner.createChild()
		local ox = Compose.cell(srcRect.x)
		local oy = Compose.cell(srcRect.y + srcRect.h + gap)
		local maxW = Compose.cell(math.max(0, box.w - 2 * gap))
		local root = mountComponent(function(UI)
			return UI.Screen({
				id = DISCLOSE_ROOT,
				children = {
					UI.Anchor({
						id = "Layer",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							-- a VStack and not a Box: a Box is a LEAF, and the plate has to
							-- hold the label it exists to show
							UI.VStack({
								id = "Plate",
								anchor = "topLeft",
								offsetX = ox,
								offsetY = oy,
								-- the panel treatment, so the plate is themed by the ACTIVE
								-- ThemeSnapshot (fill, corner, stroke, contentInsets) rather
								-- than by numbers written here
								surface = "raised",
								padding = "s",
								-- HUG WITH A CEILING, not a fixed width: a short value gets a
								-- short plate, and a long one wraps inside the safe box instead
								-- of running off the screen edge — which is the same overflow
								-- ladder the label it is disclosing just failed. The ceiling is
								-- a cell the clamp keeps equal to the live safe box
								width = function(use: any): any
									return { type = "hug", max = use(maxW) }
								end,
								children = {
									UI.Text({
										id = "Full",
										text = fullText,
										textSize = "body",
										rich = if rich == true then true else nil,
									}),
								},
							}),
						},
					}),
				},
			})
		end)
		sc.own(root.dispose)
		local controller = renderer.attach(core, root, env, adapter, {
			clock = motionClock,
			-- window space: the anchor offsets below are the SAME coordinates
			-- `screenRectOf` answers in, so the clamp arithmetic has one frame
			rootPolicy = "edgeToEdge",
		})
		controller.initialRender()
		if controller.setDisplayOrder ~= nil then
			-- above its owner's content, inside its owner's band — so a plate over a
			-- base screen never covers a modal, and a modal's own plate is above it
			controller.setDisplayOrder(owner.displayOrder + 25)
		end
		disclosurePlate = {
			scope = sc,
			controller = controller,
			root = root,
			owner = owner,
			sourcePath = sourcePath,
			source = source,
			text = fullText,
			rich = rich == true,
			ox = ox,
			oy = oy,
			maxW = maxW,
		}
		clampDisclosure()
	end

	--[[ FIRST ENGAGEMENT OWNS THE PLATE, AND IT IS KEYED ON THE LABEL, NOT ON THE
		INPUT CLASS. A focused row that is also long-pressed, or hovered, is ONE
		question with one answer, and re-presenting it as a different `source` would
		dispose and remount an identical plate — visibly, on every refresh, because
		the focus sync runs on all of them. So a live plate for this label is left
		exactly as it is, and the engagement that raised it is the one entitled to
		take it down. ]]
	local function plateShows(sourcePath: string): boolean
		return disclosurePlate ~= nil and disclosurePlate.sourcePath == sourcePath
	end

	local function syncDisclosureFocus(path: string?)
		if isDisposed() then
			return
		end
		-- A DIRECT ENGAGEMENT OUTRANKS FOCUS. A pointer dwell or a long press is a
		-- deliberate ask about ONE label; focus merely happens to be somewhere, and
		-- it is re-synced on every refresh. Without this, a refresh under a live
		-- hover plate would replace it with the focused row's plate — the reader's
		-- answer swapped out from under them by a frame of housekeeping.
		if disclosurePlate ~= nil and disclosurePlate.source ~= "focus" then
			return
		end
		local owner = handleOwning(path)
		-- containment (architecture review F-11): a surface that declared no
		-- disclosure anywhere skips the tree walk entirely — the stamp is
		-- conservative (structural regions keep it true), so this can never
		-- silently disable the feature
		if owner ~= nil and owner.hasDisclose ~= true then
			owner = nil
		end
		-- ...AND A POINTER-DRIVEN FOCUS MOVE IS NOT A FOCUS ENGAGEMENT (device round 3,
		-- the same term the ring reads). Tapping a row moves focus there; the
		-- finger asked to press the row, not to read its name, and a plate popping
		-- up under every tap is the tooltip-on-click behaviour nobody wants. The
		-- pointer's own engagement is the hover dwell, which has its own seam.
		if graph.focusVisible:peek() == false then
			owner = nil
		end
		-- ...AND THE SURFACE MUST OWN INPUT (rounds 4/6). A passive HUD has focus
		-- IDENTITY from the moment it mounts; it has the keyboard only once it
		-- engages, and a plate presented off a focus the player never moved is the
		-- same lie as a focus ring on a surface the keyboard is not reaching.
		if owner ~= nil and owner.isPassive and owner.responder:peek() ~= "engaged" then
			owner = nil
		end
		local targetPath, fullText, fullRich = disclosureTargetIn(owner, path)
		if targetPath == nil then
			-- focus left every disclosed label, so the plate it raised goes with it
			-- (the guard above already returned for a pointer/touch one)
			if disclosurePlate ~= nil then
				dismissDisclosure("focusLeave")
			end
			return
		end
		if plateShows(targetPath :: string) then
			return -- already answered for this label; a refresh must not restart it
		end
		presentDisclosure(owner, targetPath :: string, fullText :: string, "focus", fullRich)
	end

	--[[ ENGAGEMENT SEAMS (adapter-driven; constitution §2 "a leading underscore
		means engine-adapter seam"). Pointer hover and touch long-press are engine
		facts — MouseEnter/MouseLeave and the gesture arbiter's `longPress` — and
		the presenter is engine-free, so the client hands them over here rather than
		this module reaching for either. Focus needs no seam: the presenter owns the
		focus graph and reads it directly (above).

		`nil` means DISENGAGED (the pointer left everything / the press released).
		Both are idempotent: a hover that re-reports the same node neither restarts
		the dwell nor re-mounts the plate. ]]
	local function discloseHoverEngage(path: string?)
		local owner = handleOwning(path)
		local targetPath, fullText = disclosureTargetIn(owner, path)
		if targetPath == nil then
			disclosureDwell = nil
			if disclosurePlate ~= nil and disclosurePlate.source == "pointer" then
				dismissDisclosure("pointerLeave")
			end
			return
		end
		if plateShows(targetPath :: string) then
			return -- already answered for this label, by this or another engagement
		end
		if disclosureDwell ~= nil and disclosureDwell.sourcePath == targetPath then
			return -- the dwell is already counting on this label
		end
		-- moving to a DIFFERENT label retires the old answer immediately; the new
		-- one has to earn its dwell
		if disclosurePlate ~= nil and disclosurePlate.source == "pointer" then
			dismissDisclosure("pointerMove")
		end
		disclosureDwell = {
			owner = owner,
			sourcePath = targetPath,
			text = fullText,
			remaining = DISCLOSE_DWELL,
		}
	end

	local function longPress(path: string?)
		local owner = handleOwning(path)
		--[[ THE MENU OWNS THE LONG PRESS INSIDE ITS OWN TRIGGER, and only there
			(navigation-and-menus D2). The plate keeps the gesture everywhere else,
			because it is the ONLY touch route to a truncated label's full value:
			`UI.Text{ reveal = "auto" }` is opt-in, `UI.Text`-only, at most one per
			presentation and disabled entirely under reduced motion, and a disclosing
			`Toggle` label or `Table` cell has no marquee even in principle. Deleting
			the binding would therefore have been an accessibility regression that
			`text_audit` structurally cannot see — it checks the DECLARATION, never
			the reachability. So this is a carve-out, not a removal. ]]
		if owner ~= nil and owner.contextTriggerOwns ~= nil and owner.contextTriggerOwns(path) then
			return
		end
		local targetPath, fullText, fullRich = disclosureTargetIn(owner, path)
		if targetPath == nil then
			if disclosurePlate ~= nil and disclosurePlate.source == "touch" then
				dismissDisclosure("release")
			end
			return
		end
		if plateShows(targetPath :: string) then
			return -- already answered for this label, by this or another engagement
		end
		-- the long press IS the deliberation: no dwell on top of it
		disclosureDwell = nil
		presentDisclosure(owner, targetPath :: string, fullText :: string, "touch", fullRich)
	end

	--[[ the plate outlives neither its source node nor its surface. Called from
		`refresh` and from `dismiss`.

		"The source node unmounted" needs no walk of its own: `refresh` re-solves
		before this runs, so a node a `UI.When` closed over has no entry in the
		solve's text facts at all — the same read that answers
		"a re-solve made room for it" answers "it is gone", and it is a map lookup
		rather than a tree walk on every refresh. What the STACK check adds is
		different in kind: it keeps a dismissed surface's DISPOSED controller from
		being read at all. ]]
	local function revalidateDisclosure()
		if disclosureDwell ~= nil and table.find(stack, disclosureDwell.owner) == nil then
			disclosureDwell = nil
		end
		if disclosurePlate == nil then
			return
		end
		local plate = disclosurePlate
		if table.find(stack, plate.owner) == nil then
			dismissDisclosure("surfaceDismissed")
			return
		end
		local facts = plate.owner.controller.textAt ~= nil and plate.owner.controller.textAt(plate.sourcePath)
		if facts == nil or facts.truncated ~= true then
			dismissDisclosure("goneOrNoLongerTruncated")
			return
		end
		-- ...AND THE PLATE ANSWERS FOR THE LABEL AS IT IS. A losing ViewThatFits
		-- candidate keeps its text facts, and a bound value can change while still
		-- truncated; either would leave the plate showing text that is not on
		-- screen. Hidden retires it; a changed value re-presents it, same source.
		local ctrl = plate.owner.controller
		local node = nodeAt(plate.owner.root.node, plate.sourcePath)
		if
			node == nil or isHiddenPath(plate.sourcePath, if ctrl.hiddenRoots ~= nil then ctrl.hiddenRoots() else {})
		then
			dismissDisclosure("hidden")
			return
		end
		local text, rich = valueOf(node)
		if text ~= plate.text or rich ~= plate.rich then
			presentDisclosure(plate.owner, plate.sourcePath, text, plate.source, rich)
		end
	end

	--[[ disclosure() -> the live plate, in the shipped `dump()` shape
		(constitution §6): frozen, deterministic, and safe when nothing is up. It is
		the inspection surface for "is the full value reachable right now", which is
		otherwise only observable as pixels. ]]
	local function dump(): any
		if disclosurePlate == nil then
			return table.freeze({ schema = DISCLOSURE_SCHEMA, present = false })
		end
		return table.freeze({
			schema = DISCLOSURE_SCHEMA,
			present = true,
			path = DISCLOSE_PLATE,
			labelPath = DISCLOSE_LABEL,
			sourcePath = disclosurePlate.sourcePath,
			source = disclosurePlate.source,
			text = disclosurePlate.text,
		})
	end

	-- POINTER DWELL (the large-text round), one slice of the presenter's tick.
	-- Guarded, so a presentation with nothing engaged does no per-frame work.
	local function stepDwell(step: number)
		if disclosureDwell ~= nil then
			local d = disclosureDwell
			d.remaining -= step
			if d.remaining <= 0 then
				disclosureDwell = nil
				-- RE-ASK AT EXPIRY, never present the hover-time snapshot
				-- (architecture review F-2): the label may have stopped
				-- truncating (a re-solve made room) or changed its bound value
				-- while the dwell counted — the plate must answer for the label
				-- as it IS, or not at all. The facts come from the live solve,
				-- which is the same rule the seams and refresh already follow.
				local targetPath, fullText, fullRich = disclosureTargetIn(d.owner, d.sourcePath)
				if targetPath ~= nil and fullText ~= nil then
					presentDisclosure(d.owner, targetPath, fullText, "pointer", fullRich)
				end
			end
		end
	end

	return {
		targetIn = disclosureTargetIn,
		shows = plateShows,
		focus = syncDisclosureFocus,
		hover = discloseHoverEngage,
		longPress = longPress,
		revalidate = revalidateDisclosure,
		dump = dump,
		dismiss = dismissDisclosure,
		disposePlate = disposeDisclosure,
		stepDwell = stepDwell,
		clamp = clampDisclosure,
	}
end

return textDisclosure
