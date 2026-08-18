--!strict
--[[ row_actions_trays — the tray blueprints, built once, used by BOTH modes.

	A tray is the same thing in both modes (Task 4): the same buttons, the same
	compactLabel degrade ladder, the same destructive role, the same
	per-action width props, revealed by the same memo over `openEdge`/
	`offset`. The only difference is WHO PARENTS IT — this composite's own
	row root in standalone/Table, the host's ONE shared overlay in hosted
	mode (`virtual_list.luau`'s `RowActionsOverlay`) — and a parent is not a
	reason to have two tray builders that can drift apart. So the whole
	construction lives here, once, and the two modes differ only in where
	the resulting blueprints are handed: the standalone root's `children`, or
	`api.trayViews`.

	The `When` wrappers are part of the shared view for the same reason: a
	host that mounted a bare tray would have to reinvent "stay mounted while
	the close flight is still visibly running", and get the edge-vs-offset
	rule below right a second time.

	A hosted engine is itself lazy (built at the axis lock, for one row the
	player actually swiped), so building these eagerly here costs a list
	nothing until a real gesture — and it must be eager for the same
	reuse-not-leak reason the naturals in `row_actions_metrics` are: a reactive
	node created inside a `When`'s factory would be a fresh one every remount.

	IT SHARES NOTHING MUTABLE WITH THE ENGINE. Every input is a build-time
	constant: the two validated ActionSpec lists, and reactive nodes
	(`offset`, `openEdge`, `committingSig`, `motionBound`, the band metrics)
	that `buildEngine` creates once and never reassigns. This module reads them,
	derives more memos from them, and returns blueprints — it writes none of that
	closure's ~60 mutable upvalues, which is what licensed the extraction when
	row_actions.luau had to get back under the 200,000-char `Script.Source` WRITE
	cap (docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md,
	tools/check_source_size.py).

	THE INVARIANT THIS FILE EXISTS TO KEEP: the tray uncovered has to be the tray
	DRAWN. `row_actions_metrics.bandWidth` decides how far the row TRAVELS; every
	quantity here — plate width, plate padding, inter-plate gap, the band's
	row-facing gutter — is spent at the SAME reveal fraction, so the drawn band is
	exactly `frac x bandWidth`, which is exactly `|offset|`. Four device rounds are
	written into the comments below; change one term without the others and the
	band paints past the row's edge again.

	PUBLIC INTERFACE: `build(p) -> { any }` — the `UI.When` blueprints, in paint
	order. `p` carries `UI`, `core`, `scope`, the two action lists, the two band
	widths, the two natural-width maps, `offset`, `openEdge`, `committingSig`,
	`motionBound`, `editGutterPx`, `buttonPadPx`, `trayGapPx`, `rowGutterPx`, and
	`REVEAL_EPS`.

	DEPENDS ON: `./row_actions_spec` (trayId, the ActionSpec type) and
	`./row_actions_metrics` (the BUTTON_MIN_WIDTH theme key) — no reactive
	runtime, no presenter, no engine. ]]

local rowActionsSpec = require("./row_actions_spec")
local rowActionsMetrics = require("./row_actions_metrics")

type Edge = rowActionsSpec.Edge
type ActionSpec = rowActionsSpec.ActionSpec

local trayId = rowActionsSpec.trayId
local BUTTON_MIN_WIDTH = rowActionsMetrics.BUTTON_MIN_WIDTH

local row_actions_trays = {}

export type Params = {
	UI: any,
	core: any,
	scope: any,
	leadingActions: { ActionSpec }?,
	trailingActions: { ActionSpec }?,
	-- the band widths (row_actions_metrics): the distance the row travels
	leadingWidth: any,
	trailingWidth: any,
	-- the per-action natural-width signals, keyed by action id
	leadingNaturals: { [string]: any },
	trailingNaturals: { [string]: any },
	-- the engine's own live state, read-only from here
	offset: any,
	openEdge: any,
	committingSig: any,
	motionBound: any,
	-- theme-resolved amounts (row_actions_metrics); `editGutterPx` is nil unless
	-- this row can ever show the edit-mode minus
	editGutterPx: any,
	buttonPadPx: any,
	trayGapPx: any,
	rowGutterPx: any,
	REVEAL_EPS: number,
}

function row_actions_trays.build(p: Params): { any }
	local UI = p.UI
	local core = p.core
	local scope = p.scope
	local leadingActions = p.leadingActions
	local trailingActions = p.trailingActions
	local leadingWidth = p.leadingWidth
	local trailingWidth = p.trailingWidth
	local leadingNaturals = p.leadingNaturals
	local trailingNaturals = p.trailingNaturals
	local offset = p.offset
	local openEdge = p.openEdge
	local committingSig = p.committingSig
	local motionBound = p.motionBound
	local editGutterPx = p.editGutterPx
	local buttonPadPx = p.buttonPadPx
	local trayGapPx = p.trayGapPx
	local rowGutterPx = p.rowGutterPx
	local REVEAL_EPS = p.REVEAL_EPS

	local trayViews: { any } = {}
	if leadingActions ~= nil or trailingActions ~= nil then
		--[[ THE REVEAL FRACTION, ONE MEMO PER EDGE — how much of this edge's band the
			row has uncovered, 0..1. Every part of the band's drawn geometry reads THIS
			and nothing else, which is what makes "the tray uncovered is the tray
			drawn" true by construction rather than by three call sites agreeing.

			IT COVERS THE FIXED EXTRAS TOO (device round 2026-08-12, C9a's residue).
			`bandWidth` counts the inter-plate gaps and the row-facing gutter into the
			travel — the row has to move far enough to uncover the negative space as
			well as the plates — so a band that scaled only its PLATES painted those
			extras at full size from the first frame and reached past the row's own
			edge by up to `trayGap + rowGutter` while the reveal was young. Scaling all
			three by one fraction makes the drawn band exactly `frac x bandWidth`,
			which is exactly `|offset|`.

			`motionBound` rather than the `motionClock` upvalue: see `bindMotion`. With
			no motion authority at all (a bare mount, no presenter) there is no travel
			to be a fraction of, and the tray is static at full size — Task 3's
			behaviour, unchanged. ]]
		local revealFracs: { [string]: any } = {}
		for _, edge in { "leading", "trailing" } do
			local traySig = if edge == "leading" then leadingWidth else trailingWidth
			revealFracs[edge] = scope:own(core:memo(function(use)
				if not use(motionBound) then
					return 1
				end
				local trayW = use(traySig)
				if trayW <= 0 then
					return 0
				end
				return math.clamp(math.abs(use(offset)) / trayW, 0, 1)
			end))
		end

		--[[ per-action WIDTH prop: one `core:memo` per declared action, built HERE
			(not inside `buildTray`'s lazy factory) for the identical reuse-not-leak
			reason as the naturals above. A plate reads its share of the SAME observed
			`offset` the slide itself uses — no second spring, no per-button spring —
			so it "stretches in" from 0 toward its (live) natural width as `|offset|`
			approaches `trayWidth` (docs/plans/row-actions-implementation.md Task 4:
			"SwiftUI feel").

			THE FALLBACK IS "NO MOTION AUTHORITY", NOT "NO SPRING YET" (device bug
			round 2026-08-12, findings C9a and C8b — the SAME line caused both).

			It read `spring == nil or n == nil`, and both halves were wrong in a way
			only a per-frame trace could see (tests/row_actions_motion.spec.luau):

			  * `spring` is built LAZILY, by the first `retarget` — and a LIVE DRAG
			    never retargets. It writes `offset` straight through `applySlide`
			    (`onPointerMove`), so for the whole of every gesture-driven reveal
			    `spring` was still nil and every plate painted at the `buttonMinWidth`
			    FLOOR. Measured: 14 drag frames, `offset` -27 -> -183, the band a
			    constant 159px on all of them. That is C9a's "the red appears and then
			    the row animates above it", and it is also C8b's "the row animates too
			    far": the drag painted the leading plate at the 64px floor while the
			    release settles to its real 117px natural, so the row flew 53px past
			    the band the player had been watching.
			  * `n == nil` is the tray's FIRST MOUNTED FRAME — the naturals are derived
			    from `controller.textAt` on the mounted button, so they cannot exist
			    before the mount. Measured on `_open`: frame 1 painted the whole 159px
			    band at `offset` 0, frame 2 dropped to 26px. One frame of full band,
			    then a collapse, then the growth.

			"NO MOTION AUTHORITY" (`revealFracs` above, via `motionBound`) is the
			honest test for the case the fallback exists for: a bare `mountLib.mount`
			with no presenter, where there is no travel for a plate to grow with and a
			static tray is the only sensible paint. With a clock — real or
			reduced-motion — the plate is ALWAYS `natural x frac`, and an unmeasured
			natural is simply 0 for the one frame before the first `syncGeometry` lands
			(the measurement itself is geometry-free — it asks
			`text_metrics.measure(..., math.huge)` — so a 0-wide plate cannot starve
			it; see `deriveNaturals`). The band a tray paints therefore never exceeds
			the travel that uncovered it, which is the whole geometric contract of a
			swipe tray. ]]
		local function buildWidthProps(naturals: { [string]: any }, fracSig: any, actions: { ActionSpec })
			local props: { [string]: any } = {}
			for _, action in actions do
				local natural = naturals[action.id]
				props[action.id] = scope:own(core:memo(function(use)
					local n = use(natural)
					if not use(motionBound) then
						return { type = "minMax", min = BUTTON_MIN_WIDTH }
					end
					if n == nil then
						return { type = "fixed", px = 0 }
					end
					return { type = "fixed", px = math.floor(n * use(fracSig) + 0.5) }
				end))
			end
			return props
		end
		local leadingWidthProps = buildWidthProps(leadingNaturals, revealFracs.leading, leadingActions or {})
		local trailingWidthProps = buildWidthProps(trailingNaturals, revealFracs.trailing, trailingActions or {})

		--[[ THE PLATE'S OWN PADDING IS SPENT AT THE REVEAL FRACTION TOO — and this
			is the half of the close-flight overflow that `REVEAL_EPS` did NOT fix
			(director device round 2026-08-13: the plates "go past the end of the
			rows, overlap, and then pop out").

			MEASURED, LIVE, IN STUDIO — not deduced. Glossy Touch, `row-actions`,
			the VirtualList surface, per frame through the close flight. The plate
			LAYOUT rects are flush the whole way down, exactly as the headless sweep
			says (`plateR == rootR == 700` on every frame). What is painted is not:

			    plate w26 -> FacetChrome [674..700]   (flush)
			    plate w16 -> FacetChrome [684..700]   (flush — the crossover)
			    plate w13 -> FacetChrome [684..703]   ( +3 past the row)
			    plate  w8 -> FacetChrome [684..708]   ( +8 past the row)
			    plate  w4 -> FacetChrome [684..712]   (+12 past the row)

			...and at w4 the two plates' decorations are [680..708] and [684..712]:
			24 of their 28px overlap each other. Then the tray unmounts. Past the
			end, overlapping, popping out — the three symptoms, in order.

			THE MECHANISM IS AN ENGINE RULE, WHICH IS WHY NO SOLVER CAN SEE IT.
			`screen_chrome.luau`'s `applyFullBleed` makes a decoration cover its
			host's OWN box rather than the host's content box, by cancelling the
			host's `UIPadding`: `Position = (0, -left)`, `Size = (1, left + right)`.
			That cancellation is only an identity while the host is WIDER than its
			own padding. Below that the padded content box inverts, and Roblox
			normalizes an inverted box by absolute value, so the compensation stops
			cancelling and starts INFLATING. Confirmed by a controlled probe with no
			Facet in it at all — a bare Frame, `UIPadding(8,8)`, one child at
			`(0,-8)`/`(1,+16)`, host width swept 40 -> 0 (12/12 exact):

			    painted = if left + right <= w then w else 2 * (left + right) - w

			With `buttonPad` 8 a side, that is `32 - w` for every plate under 16px —
			a decoration that GROWS as its plate shrinks, centred on the plate, so
			half the growth goes out past the band's right edge, which is the row's
			right edge. The list clips at +25px, so all 12px of it is on screen.

			THE FIX IS TO REMOVE THE LAST UNSCALED TERM IN THE BAND. Every other
			quantity in this tray is already spent at the reveal fraction — the
			plate widths above, the inter-plate gap and the band's row-facing
			gutter below — for the one reason this file keeps restating: the tray
			uncovered has to be the tray drawn. The plate's own interior padding was
			the one thing still being paid in full at every width, and it is exactly
			the term `applyFullBleed` compensates for. Spent at the fraction, `left +
			right` shrinks with the plate it sits in, the precondition holds at every
			width, and the decoration is the plate again.

			IT MOVES NO LAYOUT. The padding lives INSIDE a `{ type = "fixed" }`
			plate, so it never contributed to the plate's width, the band's width or
			the row's travel; at `frac == 1` it is `buttonPad`, byte-identical to
			what shipped. The only thing that changes is what gets painted.

			THE `math.min` IS THE INVARIANT, NOT A GUARD. Deriving the padding from
			the same fraction makes `left + right <= w` true for every fraction a
			`buttonMinWidth` of 64 against a `buttonPad` of 8 can produce, but that
			is an inequality argument about two theme metrics a package is free to
			re-tune. Clamping to half the plate's OWN drawn width makes it true by
			construction, for any package, at any width. ]]
		local function buildPadProps(widthProps: { [string]: any }, fracSig: any, actions: { ActionSpec })
			local props: { [string]: any } = {}
			for _, action in actions do
				local widthProp = widthProps[action.id]
				props[action.id] = scope:own(core:memo(function(use)
					local pad = use(buttonPadPx)
					-- NO MOTION AUTHORITY is a static tray at its natural size (the
					-- same branch, for the same reason, as `buildWidthProps` above):
					-- there is no reveal fraction to spend, and the plate is never
					-- painted narrower than `buttonMinWidth`, so full padding is
					-- both correct and safe.
					if not use(motionBound) then
						return { left = pad, right = pad }
					end
					local spent = math.floor(pad * use(fracSig) + 0.5)
					local w = use(widthProp)
					if type(w) == "table" and w.type == "fixed" and type(w.px) == "number" then
						spent = math.min(spent, math.floor(w.px / 2))
					end
					return { left = spent, right = spent }
				end))
			end
			return props
		end
		local leadingPadProps = buildPadProps(leadingWidthProps, revealFracs.leading, leadingActions or {})
		local trailingPadProps = buildPadProps(trailingWidthProps, revealFracs.trailing, trailingActions or {})

		-- the band's row-facing padding and its inter-plate gap, ONE live memo each
		-- per edge, built HERE for the identical reuse-not-leak reason as the
		-- naturals and the width props above: `buildTray` runs inside a lazy `When`
		-- factory, so a memo created in there would be a fresh reactive node on
		-- every open/close cycle.
		--
		-- BOTH SCALE WITH THE REVEAL (device round 2026-08-12, C9a's residue — see
		-- `revealFracs` above). They are counted into `bandWidth`, therefore into
		-- the row's travel, so painting them at full size while the plates were
		-- still growing put band edge ahead of row edge by up to `trayGap +
		-- rowGutter`. Now `drawn band == frac x bandWidth == |offset|`, exactly.
		local trayPaddings: { [string]: any } = {}
		local trayGaps: { [string]: any } = {}
		for _, edge in { "leading", "trailing" } do
			local frac = revealFracs[edge]
			trayPaddings[edge] = scope:own(core:memo(function(use)
				local g = math.floor(use(rowGutterPx) * use(frac) + 0.5)
				return if edge == "leading" then { right = g } else { left = g }
			end))
			trayGaps[edge] = scope:own(core:memo(function(use)
				return math.floor(use(trayGapPx) * use(frac) + 0.5)
			end))
		end
		local function trayPadding(edge: Edge): any
			return trayPaddings[edge]
		end

		local function buildTray(edge: Edge, actions: { ActionSpec })
			local widthProps = if edge == "leading" then leadingWidthProps else trailingWidthProps
			local padProps = if edge == "leading" then leadingPadProps else trailingPadProps
			local buttons = {}
			for _, action in actions do
				table.insert(
					buttons,
					UI.Button({
						id = "Action:" .. action.id,
						label = action.label,
						-- ICON-FIRST (director ruling, device round 2026-08-12).
						-- `Button.icon` (the top-level prop) is circle-only and a
						-- tray button is rectangular, so the action icon still
						-- rides `compactLabel` — the same semantic name, the same
						-- framework-glyph floor, the same theme-art overlay, no new
						-- art paradigm. What INVERTED is which representation is the
						-- default: `prefer = true` makes the icon what this button
						-- wears at every width, and `label` stays the semantic name
						-- (announced, and still the drawn text of the presentModal
						-- menu row that names the same action). An action with NO
						-- icon has nothing to prefer and keeps its word.
						--
						-- Why the fit ladder could not express it: the verdict is
						-- per-button "does MY label fit MY box", so at any tray
						-- width wide enough for "Flag" and too narrow for "Delete"
						-- one plate wears a glyph and its neighbour wears a word.
						compactLabel = if action.icon ~= nil then { icon = action.icon, prefer = true } else nil,
						role = if action.role == "destructive" then "destructive" else "default",
						width = widthProps[action.id],
						height = { type = "fill" },
						-- spent at the reveal fraction, never more than half the
						-- plate's own drawn width — see `buildPadProps` above for the
						-- live measurement and the engine rule behind it
						padding = padProps[action.id],
					})
				)
			end
			return UI.HStack({
				id = trayId(edge),
				anchor = if edge == "leading" then "left" else "right",
				-- the gutter between two plates (device round 2026-08-12): rounded
				-- corners drawn flush read as one merged slab, and the sliding row
				-- content merged with the first plate mid-flight. Theme metric, and
				-- the SAME number `leadingWidth`/`trailingWidth` add to the travel
				-- distance above — the tray uncovered has to be the tray drawn, which
				-- is why it is spent at the REVEAL FRACTION rather than in full (see
				-- `trayGaps` above).
				gap = trayGaps[edge],
				-- ...and the band's own ROW-FACING padding (device bug round
				-- 2026-08-12, finding A1a). It goes on the side the row slides in
				-- from — left for a trailing tray, right for a leading one — so the
				-- negative space always lands BETWEEN the row and the first plate
				-- and never on the outside edge, where it would only shrink the
				-- band's reach into the row's corner. Counted in `bandExtras`
				-- above, so the row travels far enough to uncover it.
				padding = trayPadding(edge),
				-- Task 9: the LEADING tray shifts right by the same live gutter
				-- Content does below, so the two compose instead of colliding —
				-- "the minus sits outside the leading tray's reveal" (brief). The
				-- trailing tray needs no such term: it is anchored to the row's
				-- OWN right edge, untouched by a LEADING-side gutter.
				offsetX = if edge == "leading" then editGutterPx else nil,
				height = { type = "fill" },
				children = buttons,
			})
		end

		if leadingActions ~= nil then
			-- MOUNTED WHILE OPEN, **OR** WHILE THE CLOSE FLIGHT IS STILL VISIBLY
			-- LIVE (Task 4). `openEdge` flips the instant `close()`/a new `open()`
			-- on the other edge is called, but the spring keeps animating `offset`
			-- back toward 0 over several frames — unmounting on `openEdge`
			-- alone would make the tray vanish INSTANTLY while Content is still
			-- visibly sliding back over empty space. Reusing `offset` (the same
			-- signal `Content.offsetX` and the width props above already read)
			-- keeps the outgoing tray mounted for exactly as long as it is
			-- still on screen, with no new coupling.
			--
			-- "VISIBLY" is `REVEAL_EPS`, not zero (device round 2026-08-12, C9b —
			-- see the constant's own comment), and a destructive commit takes the
			-- tray away outright (C8a — see `committingSig`).
			local revealed = scope:own(core:memo(function(use)
				-- C8a: a destructive commit leaves nothing standing behind the row
				-- (see `committingSig`'s own comment above)
				if use(committingSig) then
					return false
				end
				if use(openEdge) == "leading" then
					return true
				end
				-- C9b: sub-pixel is arrived (see `REVEAL_EPS`)
				return use(offset) >= REVEAL_EPS
			end))
			table.insert(
				trayViews,
				UI.When({
					id = "TrayLeadingWhen",
					condition = revealed,
					thenView = function()
						return buildTray("leading", leadingActions :: { ActionSpec })
					end,
				})
			)
		end
		if trailingActions ~= nil then
			local revealed = scope:own(core:memo(function(use)
				-- C8a / C9b — the mirror of the leading memo above, same two rules
				if use(committingSig) then
					return false
				end
				if use(openEdge) == "trailing" then
					return true
				end
				return use(offset) <= -REVEAL_EPS
			end))
			table.insert(
				trayViews,
				UI.When({
					id = "TrayTrailingWhen",
					condition = revealed,
					thenView = function()
						return buildTray("trailing", trailingActions :: { ActionSpec })
					end,
				})
			)
		end
	end
	return trayViews
end

return row_actions_trays
