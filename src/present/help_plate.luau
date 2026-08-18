--!strict
--[[ HELP — the player-PULLED plate (navigation-and-menus brief §2 D3a; director
	ruling 2026-08-16 §6.2).

	`UI.Button{ help = "…" }` says one sentence about what a view does. The player
	asks for it — by resting a pointer on the view, or by landing the keyboard /
	gamepad ring on it — and it goes away the moment they stop asking. That is the
	whole construct, and its restraint is the interesting part.

	WHY IT SHOWS NOTHING ON TOUCH, AND WHY THAT IS THE SPECIFICATION.
	Apple's `.help(_:)` "configures the view's accessibility hint and its help tag
	(also called a tooltip) on the desktop platforms that have one", and the UIKit
	interaction
	"makes it possible to show a tooltip WHEN HOVERING A POINTER over a view or
	control" (both read 2026-08-16). On a touch phone nothing appears at all, and
	Apple binds no gesture to it anywhere. Neither does this: the ONE touch
	gesture that could carry it — long-press — belongs to the full-value
	disclosure plate, and D2 measured that before deciding. `UI.Text{ reveal =
	"auto" }` is opt-in, `UI.Text`-only, one strip per presentation and disabled
	under reduced motion, so a disclosing `Toggle` label or `Table` cell has no
	other touch route to its own truncated value even in principle. Two constructs
	competing for one gesture on the only class where neither has an alternative is
	the defect this file refuses to create. NOTHING HERE KNOWS THE WORD.

	THE CONSEQUENCE IS A RULE, NOT A FOOTNOTE. Because a touch player never sees
	it, `help` is never the only route to something a player needs, and
	`text_audit.helpRoutes` is that claim made mechanical: it reports a help string
	the screen says nowhere else, and — the half `clippedEssential` structurally
	cannot do — it separately reports help that NO live gesture reaches, which no
	authoring waiver may silence. `declarations()` below is what feeds it, read off
	the live mounted tree rather than from a hand-written fixture.

	WHAT IT DOES NOT OWN. The plate is presented through `presenter.presentAnchored`
	(D1) in its CHROME mode, so the placement, the safe-area flip, the along-edge
	shift and the moving-source follow are the shipped ones — and it joins no
	stack, pushes no focus scope and creates no input context. That last part is
	structural rather than configured: a presented surface pushes a scope even when
	it holds nothing focusable, and a scope with no members is still the top one,
	so a merely-passive plate STILL took the next arrow press away from the control
	it was describing. Measured, then fixed by giving D1 a chrome mode rather than
	by hand-rolling a third copy of "mount a layer and place it against a rect".
	IT CARRIES D1'S ARROW TAIL (director, device review 2026-08-16: *"should we get
	some sort of pointer... to indicate which control the tooltip is attached to"*).
	This module used to record the opposite, on the reasoning that the arrow is
	what tells the app-pushed coach mark apart from this one. The distinction is
	real and the arrow never carried it — a callout arrives unbidden on every input
	class and retires permanently; this appears only while a pointer rests or a
	ring sits, and leaves when either moves. What the arrow carries is WHICH
	CONTROL the sentence is about. Through the seam, so the suppression rule comes
	with it: a plate the clamp carried off its source drops the stem.

	THE VALUE OUTRANKS THE CONVENIENCE. One pointer dwell or one focus move can
	resolve to two different answers when a helped view also holds a truncated
	`disclose` label. The disclosure plate wins, always: a player who cannot read
	the label needs to know what it SAYS before being told what it DOES, and two
	plates over one control is never the right answer.
]]

local blueprintLib = require("../blueprint")
local focusMap = require("./focus_map")
local themeSnapshot = require("../themes/snapshot")
local paths = require("../paths")

local help_plate = {}

local HELP_ROOT = "__help__"
local PLATE_ID = "Plate"
local BODY_ID = "Body"
local DUMP_SCHEMA = "facet-help-dump/1"

-- THE SAME 0.45 s DELIBERATION the disclosure plate's pointer dwell uses, and
-- for the same reason: a plate that appeared the instant a pointer crossed a
-- control would fire on every pass THROUGH a toolbar. Focus carries its own
-- deliberation — the ring was moved on purpose — so it presents immediately.
local HELP_DWELL = 0.45
-- the plate hugs its sentence and wraps inside the safe box rather than running
-- off the edge, so a ~1.4x localization expansion lengthens it instead of
-- clipping it. The inset is the spacing step, resolved live from the theme.
local EDGE_INSET_METRIC = "s"

local isPathPrefix = paths.isPrefix

--[[ ctx — the by-reference presenter state this module reads and never owns:
	  core, env          the injected reactive/fact seam
	  stack              the presented handles, read live
	  presenter          `presentAnchored` / `dismiss` — the ONLY way a surface
	                     is created here, so this module mounts nothing itself
	  handleOwning(p)    which presented surface owns a path
	  discloseTargetIn   the disclosure plate's own resolver, asked FIRST so the
	                     full value outranks the convenience (see the header)
	  metricsNow()       the LIVE metric authority, read per presentation
	  safeBox()          the presenter's safe box, reused and never re-derived
]]
function help_plate.new(ctx: any)
	local env = ctx.env
	local stack = ctx.stack
	local presenter = ctx.presenter
	local handleOwning = ctx.handleOwning
	local discloseTargetIn = ctx.discloseTargetIn
	local metricsNow = ctx.metricsNow
	local safeBox = ctx.safeBox

	-- { handle, owner, sourcePath, text, source }
	local live: any = nil
	-- { owner, sourcePath, text, remaining }
	local dwell: any = nil
	-- re-entrancy guard: presenting a surface re-runs the focus sync, and a focus
	-- sync that presented again would recurse through `presentAnchored`
	local presenting = false

	--[[ THE FIRST HELPED NODE AT OR UNDER `path`, in document order — the same
		shape (and the same hidden-candidate rule) as the disclosure walker.
		Engagement names either the helped node itself (a hover zone is wired on it
		directly) or a focusable that contains it (the ring lands on a Button whose
		child Text carries the sentence), and one walk answers both. ]]
	local function helpTargetIn(handle: any, path: string?): (string?, string?)
		if handle == nil or path == nil or handle.hasHelp ~= true then
			return nil, nil
		end
		local ctrl = handle.controller
		if ctrl == nil then
			return nil, nil
		end
		local node = focusMap.nodeAt(handle.root.node, path)
		if node == nil then
			return nil, nil
		end
		-- A HIDDEN CANDIDATE HELPS NOBODY (the F-1 class): a losing ViewThatFits
		-- candidate keeps its mount and its rects, and a plate raised for a control
		-- that is nowhere on screen points at nothing.
		--[[ ONE OWNER FOR "IS THIS PATH INSIDE A SUBTREE THAT DOES NOT PAINT"
			(reuse audit REUSE-29). `focusMap.isHiddenPath` is the published answer and
			takes the SET `hiddenRoots()` already returns, so the array this used to
			build was a conversion nobody needed. Hoisted once rather than re-read per
			node: the walk visits every node in the subtree. ]]
		local hiddenRoots: { [string]: boolean } = if ctrl.hiddenRoots ~= nil then ctrl.hiddenRoots() else {}
		local foundPath: string? = nil
		local foundText: string? = nil
		local function walk(n: any)
			if foundPath ~= nil or focusMap.isHiddenPath(n.path, hiddenRoots) then
				return
			end
			local text = if n.props ~= nil then n.props.help else nil
			if type(text) == "string" and text ~= "" then
				foundPath = n.path
				foundText = text
				return
			end
			for _, child in n.children or {} do
				walk(child)
			end
		end
		walk(node)
		return foundPath, foundText
	end

	local function dispose()
		if live == nil then
			return
		end
		local handle = live.handle
		live = nil
		presenter.dismiss(handle)
	end

	local function present(owner: any, sourcePath: string, text: string, source: string)
		dispose()
		local box = safeBox()
		local inset = themeSnapshot.resolveNumber(metricsNow(), EDGE_INSET_METRIC) or 0
		local panel = blueprintLib.VStack({
			id = PLATE_ID,
			-- the panel treatment, so the plate is themed by the ACTIVE snapshot
			-- (fill, corner, stroke, insets) rather than by numbers written here
			surface = "raised",
			padding = "s",
			-- HUG WITH A CEILING: a short sentence gets a short plate, a long one
			-- WRAPS inside the safe box instead of running off the screen edge —
			-- which is what makes a 1.4x pseudo-localized string legible rather
			-- than clipped
			width = { type = "hug", max = math.max(0, box.w - 2 * inset) },
			children = { blueprintLib.Text({ id = BODY_ID, text = text, textSize = "body" }) },
		})
		presenting = true
		--[[ CHROME, NOT A SURFACE, and that is a structural claim rather than a
			configured one. A presented surface pushes a focus scope even when it
			holds nothing focusable, and a scope with no members is still the TOP
			scope — measured: the first arrow press after a plate appeared had
			nowhere to go, and the ring on the control being described went nil. A
			chrome layer joins no stack, pushes no scope and creates no input
			context, so a help plate CANNOT take navigation from the control it is
			explaining. It is the same shape the full-value disclosure plate and the
			toast strip already have, reached through D1's own seam. ]]
		local ok, handle = pcall(presenter.presentAnchored, panel, {
			id = HELP_ROOT,
			chrome = true,
			anchor = {
				source = { path = sourcePath },
				edge = "bottom",
				-- leading-aligned on the control, which is where the reader's eye is
				align = "start",
				--[[ AND IT POINTS AT WHAT IT DESCRIBES (director, device review
					2026-08-16): *"should we get some sort of pointer like in the original
					image to indicate which control the tooltip is attached to"* — Win32's
					titled tooltip and `f1-avatar-editor.jpeg` both have a stem.

					This read `tail = false`, on the reasoning that the arrow is what tells
					the app-pushed coach mark apart from the player-pulled plate. That
					distinction is real and the arrow was never what carried it: a callout
					arrives on its own initiative, on every input class, and retires
					permanently; a help plate appears only while a pointer rests or a ring
					sits, on two classes, and leaves the moment either moves. What the
					arrow carries is WHICH CONTROL the sentence is about, and a
					`align = "start"` plate under a row of same-sized buttons genuinely
					leaves that open.

					D1'S TAIL, NOT A SECOND ONE. This is the whole change: the centre, the
					corner keep-out, the edge flip and — the half that matters — the
					SUPPRESSION rule all arrive with it. A plate the clamp carried off its
					source drops its arrow rather than pointing at empty screen.

					DEFAULT ON, with no per-view flag. An opt-in stem would be off in every
					surface that already declares `help =`, so the finding would stand
					everywhere it was reported; and "which control is this about" is not a
					question an author should be able to answer wrong. ]]
				tail = true,
			},
		})
		presenting = false
		if not ok or type(handle) ~= "table" then
			return
		end
		live = { handle = handle, owner = owner, sourcePath = sourcePath, text = text, source = source }
	end

	local api = {}

	function api.dismiss(_reason: string)
		dwell = nil
		dispose()
	end

	-- is a plate already answering for this exact control? Then leave it alone:
	-- re-presenting an identical plate on every refresh is visible flicker.
	local function shows(sourcePath: string): boolean
		return live ~= nil and live.sourcePath == sourcePath
	end

	--[[ THE POINTER ENGAGEMENT, off the renderer's hover zone. `nil` means the
		pointer left everything. Idempotent: a hover that re-reports the same node
		neither restarts the dwell nor re-mounts the plate. ]]
	function api.hover(path: string?)
		if presenting then
			return
		end
		local owner = handleOwning(path)
		--[[ THE VALUE OUTRANKS THE CONVENIENCE. If this engagement also resolves a
			truncated disclosed label, that plate is the answer and this one stands
			down — never two plates over one control. ]]
		if path ~= nil and discloseTargetIn(owner, path) ~= nil then
			dwell = nil
			dispose()
			return
		end
		local targetPath, text = helpTargetIn(owner, path)
		if targetPath == nil then
			dwell = nil
			if live ~= nil and live.source == "pointer" then
				dispose()
			end
			return
		end
		if shows(targetPath :: string) then
			return
		end
		if dwell ~= nil and dwell.sourcePath == targetPath then
			return -- already counting on this control
		end
		-- moving to a DIFFERENT control retires the old answer immediately; the new
		-- one has to earn its dwell
		if live ~= nil and live.source == "pointer" then
			dispose()
		end
		dwell = { owner = owner, sourcePath = targetPath, text = text, remaining = HELP_DWELL }
	end

	--[[ THE FOCUS ENGAGEMENT. The presenter calls this from the ONE place that
		already decides whether a surface is painting a focus ring at all, so a
		plate can never appear off a focus the keyboard is not reaching — and a
		pointer tap (which sets `focusVisible = false`) presents nothing, which is
		exactly how touch ends up showing nothing without a device branch. ]]
	function api.focus(path: string?)
		if presenting then
			return
		end
		-- a DIRECT pointer engagement outranks focus, which merely happens to be
		-- somewhere and is re-synced on every refresh
		if live ~= nil and live.source == "pointer" then
			return
		end
		local owner = handleOwning(path)
		if path ~= nil and discloseTargetIn(owner, path) ~= nil then
			dispose()
			return
		end
		local targetPath, text = helpTargetIn(owner, path)
		if targetPath == nil then
			if live ~= nil then
				dispose()
			end
			return
		end
		if shows(targetPath :: string) then
			return
		end
		present(owner, targetPath :: string, text :: string, "focus")
	end

	-- the dwell, stepped on the presenter's own tick. Guarded, so a presentation
	-- with nothing hovered does no per-frame work at all.
	function api.tick(dt: number)
		if dwell == nil then
			return
		end
		dwell.remaining -= math.max(dt, 0)
		if dwell.remaining > 0 then
			return
		end
		local d = dwell
		dwell = nil
		-- RE-ASK AT EXPIRY, never present the hover-time snapshot: the control may
		-- have unmounted or lost its declaration while the dwell counted
		local targetPath, text = helpTargetIn(d.owner, d.sourcePath)
		if targetPath ~= nil and text ~= nil then
			present(d.owner, targetPath, text, "pointer")
		end
	end

	--[[ THE PLATE OUTLIVES NEITHER ITS SOURCE NODE NOR ITS SURFACE. Called from
		`refresh` and from `dismiss`: a surface that left the stack takes its plate
		with it, and a node a `UI.When` closed over stops resolving. ]]
	function api.revalidate()
		if live == nil then
			return
		end
		if table.find(stack, live.owner) == nil then
			dispose()
			return
		end
		local targetPath = helpTargetIn(live.owner, live.sourcePath)
		if targetPath == nil then
			dispose()
		end
	end

	--[[ EVERY LIVE HELP DECLARATION, and whether anything actually reaches it —
		the input `text_audit.helpRoutes` is written against.

		`hover` is a LIVE fact, not a declaration: the renderer wires the hover zone
		only while the pointer class is live, so a pure-touch session reports false
		here and the audit says so. `focus` asks whether the ring can land on this
		node or on something containing it, read off `focus_map`'s own FOCUSABLE set
		rather than a second list. Between them they answer the question a
		declaration cannot: is there a gesture left that reaches this sentence. ]]
	function api.declarations(): { [string]: any }
		local out: { [string]: any } = {}
		local pointerLive = env:get("interactionClasses"):get().pointer == true
		for _, handle in stack do
			if handle.hasHelp ~= true or handle.root == nil then
				continue
			end
			local function walk(n: any, focusableAbove: boolean)
				local focusable = focusableAbove
					or (focusMap.FOCUSABLE[n.class] == true and not (n.props ~= nil and n.props.focusable == false))
				local text = if n.props ~= nil then n.props.help else nil
				if type(text) == "string" and text ~= "" then
					out[n.path] = { text = text, hover = pointerLive, focus = focusable }
				end
				for _, child in n.children or {} do
					walk(child, focusable)
				end
			end
			walk(handle.root.node, false)
		end
		return out
	end

	function api.dump(): any
		local count = 0
		for _ in api.declarations() do
			count += 1
		end
		if live == nil then
			return table.freeze({
				schema = DUMP_SCHEMA,
				present = false,
				declarations = count,
				dwelling = dwell ~= nil,
				text = if count == 0
					then "no help declared, nothing showing"
					else `{count} help declaration(s), nothing showing`,
			})
		end
		return table.freeze({
			schema = DUMP_SCHEMA,
			present = true,
			path = `/{HELP_ROOT}/Layer/Surface/{PLATE_ID}`,
			labelPath = `/{HELP_ROOT}/Layer/Surface/{PLATE_ID}/{BODY_ID}`,
			sourcePath = live.sourcePath,
			source = live.source,
			helpText = live.text,
			declarations = count,
			dwelling = dwell ~= nil,
			text = `help for {live.sourcePath} ({live.source}): {live.text}`,
		})
	end

	return api
end

return help_plate
