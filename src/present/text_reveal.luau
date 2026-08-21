--!strict
--[[ TextReveal — the AUTO REVEAL (marquee): the travelling strip a
	`UI.Text{ reveal = "auto" }` that TRUNCATED gets, its scan/rest/travel cycle
	and its dump. Extracted verbatim from src/present/presenter.luau for
	Studio's 200,000-character `Source` WRITE cap — over it a module silently
	stops live-syncing into an open session, so a live check against it tests
	the built place rather than the edits on disk
	(docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md; O-29 is what
	that cost this file).

	WHY THIS IS A SAFE SEAM, by the same test that moved the catchers out: does
	the block read or WRITE a mutable upvalue of the `presenter.new` closure? It
	writes only `revealState` and `revealScan`, which it also DECLARES and which
	nothing else in that file reads. It reads `stack` (never reassigned — the
	live list of presented handles, by reference) and ONE collaborator from the
	disclosure block, `plateShows`, a `local function` that is likewise never
	reassigned and so is passed as a value. Zero entanglement.

	THE ONE CROSS-FEATURE RULE, and the reason `plateShows` is a dependency
	rather than a copy: the reader's own STATIC ask outranks the ambient travel.
	A live disclosure plate for the same label retires the strip; the
	plate is the full-value path under reduced motion too.

	`new(ctx)` returns the four entry points presenter.new bound before the move:
	  retireRevealFor(owner)
	                   drop the strip and the cycle if THIS surface owns it,
	                   releasing the held paint — `dismiss` calls it, and the
	                   predicate moved in with `revealState` so that state stays
	                   private (it was the block's one reader outside itself)
	  stepReveal(dt)   the presenter's ONE tick drives the whole cycle — there
	                   are no per-label frame loops, and an idle presenter pays
	                   a timer-gated rescan (REVEAL_RESCAN), never a per-frame
	                   tree walk
	  reveal()         the frozen dump, rebound as `self.reveal`
	  movingText()     the moving-text count `text_audit.movingText` audits
	                   (allowance 1), rebound as `self.movingText`

	ctx (the first four go BY REFERENCE, which is what makes them safe):
	  core, env, adapter   the injected engine seam, exactly as presenter has it
	  stack                the presented handles, base first — read live
	  plateShows(path)     is a disclosure plate up for this source right now?

	Strictly one-way: this never requires the presenter back. ]]

local mountLib = require("../mount")
local blueprintLib = require("../blueprint")
local renderer = require("../render/renderer")
local focusMap = require("./focus_map")

local isPathPrefix = focusMap.isPathPrefix

local textReveal = {}

function textReveal.new(ctx: any)
	local core = ctx.core
	local env = ctx.env
	local adapter = ctx.adapter
	local stack = ctx.stack
	local plateShows = ctx.plateShows

	--[[ ════════════════════ THE AUTO REVEAL (marquee) ════════════════════

		Director ruling 2026-08-04, superseding large-text accessibility's "no marquee shipped" for
		surfaces that DECLARE it: a `UI.Text{ reveal = "auto" }` that TRUNCATED
		auto-scrolls its whole value. The plan's rung-4 constraint list binds:

		· QUIET DELAY — the string rests in the engine's own ellipsis for
		  REVEAL_PAUSE before anything moves (and between cycles).
		· READING DIRECTION — the strip slides LEFT, revealing the tail (the
		  framework has no RTL fact today; when one lands, the travel sign reads
		  it here and nowhere else).
		· GRAPHEME BOUNDARIES — the whole string travels as ONE strip at its
		  natural one-line width; it is never re-segmented, and the resting paint
		  is the engine's own ellipsis. (The strip's edges crop glyphs in motion
		  exactly as any scrolling region does — the constraint forbids BREAKING
		  the string, not clipping a moving edge.)
		· PAUSE AT ENDS — the tail holds for REVEAL_PAUSE before the return leg,
		  and the return ends back in the ellipsis rest.
		· STATIC ALTERNATIVE — a reveal node is ALSO a disclosure source (the
		  renderer wires the same engagement zones), so hover dwell / long-press
		  raise the large-text accessibility plate; a live plate for this label OUTRANKS the travel.
		· REDUCED MOTION — travel never starts, and a mid-flight flip retires the
		  strip on the next tick. The plate remains the full-value path.
		· AT MOST ONE — one strip across every surface; `self.movingText()` feeds
		  `text_audit.movingText`, whose allowance stays 1.
		· NO PER-LABEL FRAME LOOPS — the presenter's ONE tick drives the cycle;
		  an idle presenter pays a timer-gated rescan (REVEAL_RESCAN), never a
		  per-frame tree walk, and surfaces without the declaration are skipped
		  by the `hasReveal` stamp entirely.

		HOW THE STRIP PAINTS. Presenter-private, exactly like the disclosure
		plate: a `clipChildren` Window fixed at the source label's own rect, an
		anchored Full label inside it at the string's natural one-line width (the
		SOLVE's own `naturalWidth` fact — never a second opinion), and the travel
		is one anchor-offset signal. While the strip covers the source, the
		source's own paint is HELD through `controller.setPaintHeld` — the solve,
		the rects and the truncation facts are untouched, so the target stays
		"truncated" and the audit stays honest. The strip exists only while
		travelling; at rest the source paints its ellipsis and the moving-text
		count is zero. ]]
	local REVEAL_ROOT = "__reveal__"
	local REVEAL_WINDOW = `/{REVEAL_ROOT}/Layer/Window`
	local REVEAL_LABEL = `{REVEAL_WINDOW}/Inner/Full`
	local REVEAL_SCHEMA = "facet-reveal-dump/1"
	-- the quiet delay before travel, and both end pauses. Longer than the plate's
	-- 0.45 dwell on purpose: nothing here was asked for, so the reader gets a
	-- moment with the stable ellipsis before the line starts moving.
	local REVEAL_PAUSE = 1.2
	-- idle rescan cadence — well under REVEAL_PAUSE, so found-to-moving latency
	-- is invisible, and far from per-frame work
	local REVEAL_RESCAN = 0.5
	-- travel speed as a GLYPH rate, so raising the text preference slows the
	-- px/s with the bigger glyphs instead of racing them: glyphs/s times the
	-- average glyph width (text_metrics' 0.62 em) times the PAINTED size
	-- (facts.size already carries the preference offset)
	local REVEAL_GLYPHS_PER_S = 3.0
	local REVEAL_GLYPH_EM = 0.62
	-- the strip is measured by the same headless metrics the solve used; the
	-- engine can paint a hair wider (measured live at ~1px on the heavy face),
	-- so the strip carries this much slack past the natural width
	local REVEAL_SLACK = 2

	local revealState: any = nil -- { owner, sourcePath, text, phase, wait, travel, overlay? }
	local revealScan = 0

	-- the first DECLARED, TRUNCATED reveal text under this surface, in document
	-- order — the same walk shape as disclosureTargetIn, against the same facts
	local function revealTargetIn(handle: any): (string?, string?)
		local ctrl = handle.controller
		if ctrl == nil or ctrl.textAt == nil then
			return nil, nil
		end
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
			if n.props ~= nil and n.props.reveal ~= nil then
				local facts = ctrl.textAt(n.path)
				if facts ~= nil and facts.truncated == true and facts.reveal == true then
					foundPath = n.path
					foundText = tostring(n.props.text)
					return
				end
			end
			for _, child in n.children or {} do
				walk(child)
			end
		end
		walk(handle.root.node)
		return foundPath, foundText
	end

	-- unmount the strip and give the source its paint back (cycle state kept)
	local function retireRevealStrip()
		local st = revealState
		if st == nil or st.overlay == nil then
			return
		end
		local overlay = st.overlay
		st.overlay = nil
		if st.owner.controller.setPaintHeld ~= nil then
			st.owner.controller.setPaintHeld(st.sourcePath, false)
		end
		overlay.controller.dispose()
		overlay.scope:dispose()
	end

	local function retireReveal()
		retireRevealStrip()
		revealState = nil
		revealScan = 0
	end

	-- ...and the reveal strip goes with its owner SYNCHRONOUSLY, exactly as the
	-- disclosure plate does — a dismissed presenter may never tick again, and a
	-- strip that waited for one would leak its overlay and the held paint. The
	-- predicate lives here rather than at `dismiss`'s call site so `revealState`
	-- stays private to this module.
	local function retireRevealFor(owner: any)
		if revealState ~= nil and revealState.owner == owner then
			retireReveal()
		end
	end

	-- mount the strip over the source rect; returns false when the geometry or
	-- facts are not real yet (the cycle rests and asks again)
	local function mountRevealStrip(): boolean
		local st = revealState
		local ctrl = st.owner.controller
		local srcRect = if ctrl.screenRectOf ~= nil
			then ctrl.screenRectOf(st.sourcePath)
			else ctrl.rectOf(st.sourcePath)
		local facts = ctrl.textAt(st.sourcePath)
		if type(srcRect) ~= "table" or facts == nil or tonumber(facts.naturalWidth) == nil then
			return false
		end
		local labelW = (tonumber(facts.naturalWidth) :: number) + REVEAL_SLACK
		if labelW <= srcRect.w then
			return false -- nothing hidden to reveal (a stale verdict; the verify path retires it)
		end
		-- facts.size is the MEASURED size, which already carries the preference
		-- offset (large-text accessibility: the offset applies once, at the measure seam) — the strip
		-- declares the pre-offset size so the engine lands on the same paint
		local offsetFact = env:get("preferredTextOffset"):get()
		local offset = if type(offsetFact) == "number" then math.clamp(offsetFact, 0, 32) else 0
		local paintSize = math.max(1, (tonumber(facts.size) or 16) - offset)
		local sc = core:scope("present-reveal")
		local wx = sc:own(core:signal(srcRect.x))
		local wy = sc:own(core:signal(srcRect.y))
		local offx = sc:own(core:signal(-st.travel))
		local bp = blueprintLib.Screen({
			id = REVEAL_ROOT,
			children = {
				blueprintLib.Anchor({
					id = "Layer",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						blueprintLib.VStack({
							id = "Window",
							anchor = "topLeft",
							offsetX = wx,
							offsetY = wy,
							width = { type = "fixed", px = srcRect.w },
							height = { type = "fixed", px = srcRect.h },
							clipChildren = true,
							children = {
								blueprintLib.Anchor({
									id = "Inner",
									width = { type = "fill", weight = 1 },
									height = { type = "fill", weight = 1 },
									children = {
										blueprintLib.Text({
											id = "Full",
											text = st.text,
											textSize = paintSize,
											lineLimit = 1,
											anchor = "topLeft",
											offsetX = offx,
											width = { type = "fixed", px = labelW },
										}),
									},
								}),
							},
						}),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp, { scope = sc:child("mount") })
		local controller = renderer.attach(core, root, env, adapter, {
			-- window space, exactly like the plate: the anchor offsets are the
			-- coordinates `screenRectOf` answers in
			rootPolicy = "edgeToEdge",
		})
		controller.initialRender()
		if controller.setDisplayOrder ~= nil then
			-- above its owner's content, below a disclosure plate (+25): the
			-- static answer always reads over the moving one
			controller.setDisplayOrder(st.owner.displayOrder + 24)
		end
		if ctrl.setPaintHeld ~= nil then
			ctrl.setPaintHeld(st.sourcePath, true)
		end
		st.overlay = {
			scope = sc,
			controller = controller,
			wx = wx,
			wy = wy,
			offx = offx,
			windowW = srcRect.w,
			windowH = srcRect.h,
			srcX = srcRect.x,
			srcY = srcRect.y,
			labelW = labelW,
		}
		return true
	end

	-- the strip FOLLOWS the live rects and facts (the clampDisclosure lesson):
	-- a moved source re-places the window; a resized source or a late engine
	-- measure re-mounts the strip at the new numbers
	local function followRevealGeometry(facts: any)
		local st = revealState
		local overlay = st.overlay
		local ctrl = st.owner.controller
		local srcRect = if ctrl.screenRectOf ~= nil
			then ctrl.screenRectOf(st.sourcePath)
			else ctrl.rectOf(st.sourcePath)
		if type(srcRect) ~= "table" then
			retireReveal()
			return
		end
		local wantLabelW = (tonumber(facts.naturalWidth) or 0) + REVEAL_SLACK
		if
			math.abs(srcRect.w - overlay.windowW) > 0.5
			or math.abs(srcRect.h - overlay.windowH) > 0.5
			or math.abs(wantLabelW - overlay.labelW) > 1
		then
			retireRevealStrip()
			if not mountRevealStrip() then
				st.phase, st.wait, st.travel = "rest", REVEAL_PAUSE, 0
			end
			return
		end
		if srcRect.x ~= overlay.srcX or srcRect.y ~= overlay.srcY then
			overlay.srcX, overlay.srcY = srcRect.x, srcRect.y
			overlay.wx:set(srcRect.x)
			overlay.wy:set(srcRect.y)
			overlay.controller.refresh()
		end
	end

	local function stepReveal(dt: number)
		-- reduced motion: the whole engine is inert (the plate is the path)
		if env:get("reducedMotion"):get() == true then
			if revealState ~= nil then
				retireReveal()
			end
			return
		end
		if revealState == nil then
			revealScan -= dt
			if revealScan > 0 then
				return
			end
			revealScan = REVEAL_RESCAN
			-- topmost surface first, same order the outside-tap policy resolves;
			-- surfaces without the declaration cost one boolean read
			for i = #stack, 1, -1 do
				local h = stack[i]
				if h.hasReveal == true then
					local path, text = revealTargetIn(h)
					if path ~= nil then
						revealState = {
							owner = h,
							sourcePath = path,
							text = text,
							phase = "rest",
							wait = REVEAL_PAUSE,
							travel = 0,
						}
						break
					end
				end
			end
			return
		end
		local st = revealState
		-- verify the debt is still real: same owner presented, same string, still
		-- truncated. A re-solve that made room, a swapped text, a dismissed
		-- surface — all retire on the next tick, releasing the held paint.
		local facts = if table.find(stack, st.owner) ~= nil then st.owner.controller.textAt(st.sourcePath) else nil
		if facts == nil or facts.truncated ~= true or facts.reveal ~= true or tostring(facts.text) ~= st.text then
			retireReveal()
			return
		end
		-- ...and still PAINTED (found live 2026-08-04, the F-1 class): a losing
		-- arrangement/ViewThatFits candidate keeps its mount, its rects AND its
		-- truncation facts — only visibility knows it does not draw. A preference
		-- drop flipped the recap's composition to the rich form and the strip
		-- kept travelling over the hidden reduced line. Hiddenness is re-read
		-- every tick exactly as the facts are.
		--[[ THE FOURTH COPY OF THE SAME TEST (reuse audit REUSE-29 — the audit
			counted three and this file had two of them). Same published owner as
			the scan above; hiddenness is re-read every tick exactly as the facts
			are, so this one takes the set fresh rather than hoisting it. ]]
		local ctrl = st.owner.controller
		if ctrl.hiddenRoots ~= nil and focusMap.isHiddenPath(st.sourcePath, ctrl.hiddenRoots()) then
			retireReveal()
			return
		end
		-- the reader's own static ask outranks the ambient travel
		if plateShows(st.sourcePath) then
			retireRevealStrip()
			st.phase, st.wait, st.travel = "rest", REVEAL_PAUSE, 0
			return
		end
		if st.phase == "rest" then
			st.wait -= dt
			if st.wait <= 0 then
				if mountRevealStrip() then
					st.phase = "out"
				else
					st.wait = REVEAL_PAUSE
				end
			end
			return
		end
		if st.overlay == nil then
			-- a strip phase with no strip (adapter refused a mount): rest again
			st.phase, st.wait, st.travel = "rest", REVEAL_PAUSE, 0
			return
		end
		followRevealGeometry(facts)
		if revealState ~= st or st.overlay == nil then
			return
		end
		local speed = REVEAL_GLYPHS_PER_S * REVEAL_GLYPH_EM * (tonumber(facts.size) or 16)
		local distance = math.max(0, st.overlay.labelW - st.overlay.windowW)
		if st.phase == "out" then
			st.travel = math.min(distance, st.travel + speed * dt)
			st.overlay.offx:set(-st.travel)
			st.overlay.controller.refresh()
			if st.travel >= distance then
				st.phase, st.wait = "end", REVEAL_PAUSE
			end
		elseif st.phase == "end" then
			st.wait -= dt
			if st.wait <= 0 then
				st.phase = "back"
			end
		elseif st.phase == "back" then
			st.travel = math.max(0, st.travel - speed * dt)
			st.overlay.offx:set(-st.travel)
			st.overlay.controller.refresh()
			if st.travel <= 0 then
				retireRevealStrip()
				st.phase, st.wait = "rest", REVEAL_PAUSE
			end
		end
	end

	--[[ reveal() -> the live strip, in the shipped dump shape (constitution §6):
		frozen, deterministic, safe when nothing is up. `present` means the strip
		is mounted (the source's paint is held); a resting cycle reports its
		target with `present = false`, because at rest the screen shows exactly
		what an undeclared label would. ]]
	local function reveal(): any
		local st = revealState
		if st == nil or st.overlay == nil then
			return table.freeze({
				schema = REVEAL_SCHEMA,
				present = false,
				sourcePath = if st ~= nil then st.sourcePath else nil,
				phase = if st ~= nil then st.phase else nil,
				travel = 0,
				distance = 0,
			})
		end
		return table.freeze({
			schema = REVEAL_SCHEMA,
			present = true,
			path = REVEAL_WINDOW,
			labelPath = REVEAL_LABEL,
			sourcePath = st.sourcePath,
			phase = st.phase,
			travel = st.travel,
			distance = math.max(0, st.overlay.labelW - st.overlay.windowW),
			text = st.text,
		})
	end

	-- the moving-text count `text_audit.movingText` audits (allowance 1): the
	-- strip counts the whole time it is mounted — conservative on purpose
	local function movingText(): number
		return if revealState ~= nil and revealState.overlay ~= nil then 1 else 0
	end
	return {
		retireRevealFor = retireRevealFor,
		stepReveal = stepReveal,
		reveal = reveal,
		movingText = movingText,
	}
end

return textReveal
