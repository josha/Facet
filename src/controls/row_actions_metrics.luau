--!strict
--[[ row_actions_metrics — every live pixel amount a row-actions band is made of.

	WHAT THIS IS. The theme-resolved chrome of `newRowActions`: the four
	`controls.rowActions.*` metrics, the per-action NATURAL width signals, the
	band-width arithmetic those sum into, and the edit-mode gutter. One factory,
	`build(...)`, returns them all as already-owned reactive nodes.

	IT SHARES NOTHING WITH THE ENGINE. Everything here is a function of the
	arguments handed in — `core`/`scope`, the two validated ActionSpec lists, and
	`spec.env` — and every value it returns is created ONCE and never reassigned,
	so `buildEngine` closes over each as a plain constant. It reads none of that
	closure's ~60 mutable upvalues, which is exactly the test that licensed this
	extraction (tools/check_source_size.py).

	THE ONE INVARIANT THAT SPANS THE SEAM, restated because it is the whole
	geometric contract of a swipe tray and it is now authored on this side of it:
	`leadingWidth`/`trailingWidth` are the number the ROW TRAVELS, and the band
	drawn beside it must be exactly that. `bandExtras` is why the inter-plate gaps
	and the row-facing gutter are IN that sum; `row_actions_trays` is what spends
	them at the reveal fraction so the drawn band equals `|offset|` at every
	frame. Change one side and the other has to move with it.

	PUBLIC INTERFACE:
	  * `BUTTON_MIN_WIDTH`, `EDIT_AFFORDANCE` — the theme KEYS, re-exported
	    because a tray plate and the edit minus declare them raw as props
	  * `build(core, scope, env, leadingActions, trailingActions,
	     hasEditAffordance, editingReadable)` -> `{ metricsSig, buttonPadPx,
	     buttonMinWidthPx, trayGapPx, rowGutterPx, buttonChromePx,
	     leadingNaturals, trailingNaturals, leadingWidth, trailingWidth,
	     editAffordanceShown, editGutterPx }`

	DEPENDS ON: `../themes/snapshot` alone.

	NOT HERE: the NATURALS are WRITTEN by `deriveNaturals` in row_actions.luau,
	which needs the live `controller.textAt` facts and the icon glyph — a
	presenter-supplied surface this module deliberately does not import. It owns
	the signals and the arithmetic over them; the measurement stays with the
	engine that receives the geometry broadcast. ]]

local themeSnapshot = require("../themes/snapshot")
local rowActionsSpec = require("./row_actions_spec")

type ActionSpec = rowActionsSpec.ActionSpec

local row_actions_metrics = {}

-- THEME METRICS (Task 2). A tray button never sits narrower than
-- `buttonMinWidth` — the localization floor — and `buttonPad` is its inner
-- horizontal padding. Theme strings only; resolved by the solver exactly like
-- `slider.luau`'s `THUMB_SIZE`/`RAIL_HEIGHT`.
local BUTTON_MIN_WIDTH = "controls.rowActions.buttonMinWidth"
local BUTTON_PAD = "controls.rowActions.buttonPad"
-- ...and the gutter BETWEEN two adjacent tray buttons (director device round
-- 2026-08-12: "Delete 645-777, Flag 780-905, corners touching"). Zero read as one
-- merged slab, and mid-flight the sliding row content merged with the first plate
-- too. A THEME metric, not a literal: `snapshot.resolve` fills it from the
-- package's own `space.xs` when the package declares none, so it moves with the
-- spacing scale the rest of the surface already uses.
local TRAY_GAP = "controls.rowActions.trayGap"
-- ...and the gutter between the ROW ITSELF and the tray band beside it (device
-- bug round 2026-08-12, findings A1a/A2: "the trash tray butts straight against
-- the row with zero negative space", and the edit minus doing the same on the
-- leading edge). `trayGap` separates two PLATES from each other; this separates
-- the whole band — and the edit-mode minus, which lives in the same strip — from
-- the sliding row. A second theme metric rather than a reuse of `trayGap`
-- because the two are different decisions at different scales: a hairline
-- between two members of one group, a clear step between the group and the
-- surface it sits beside. `snapshot.resolve` fills it from the package's own
-- `space.s` when the package declares none.
--
-- IT IS PART OF THE BAND, NOT A THING BESIDE IT: `row_actions_trays.buildTray`
-- spends it as the
-- tray HStack's own row-facing padding, so the band's width (and therefore the
-- travel distance the row slides, and therefore the reveal fraction each plate
-- stretches by) all move together by construction — the same "the tray
-- uncovered has to be the tray drawn" rule the `trayGap` fix already had to
-- learn.
local ROW_GUTTER = "controls.rowActions.rowGutter"
-- Task 9: the edit-mode leading minus' diameter (both axes — `shape = "circle"`
-- below takes only ONE authored axis and derives the other).
local EDIT_AFFORDANCE = "controls.rowActions.editAffordance"

-- `BUTTON_MIN_WIDTH` is re-exported because a tray plate declares it RAW as a
-- `minMax` floor when there is no motion authority to spend a reveal fraction
-- against (`row_actions_trays.buildWidthProps`) — the resolved
-- `buttonMinWidthPx` below is the same metric for the arithmetic that needs a
-- number rather than a key.
row_actions_metrics.BUTTON_MIN_WIDTH = BUTTON_MIN_WIDTH
-- ...and `EDIT_AFFORDANCE` for the same reason: the edit-mode minus authors ONE
-- axis as `{ type = "fixed", px = EDIT_AFFORDANCE }` and lets `shape = "circle"`
-- derive the other, so the Button prop wants the key, not the resolved number
-- `editGutterPx` sums.
row_actions_metrics.EDIT_AFFORDANCE = EDIT_AFFORDANCE

--[[ THE ROOM THE ROW LEAVES FOR THE MINUS, WRITTEN ONCE (task THEME fix round,
	2026-08-28; review finding C1).

	`editGutterPx` below resolves this list, and `row_actions_root` hands the SAME
	list to `chrome_slots.attachHint` as the disc's `footprint`, so the space the
	row reserves and the ceiling the framework's size floor may not cross are one
	expression rather than two that happen to agree. They did not, before: the
	`shape = "circle"` icon floor in `render/layout_node` raises a disc to hold its
	picture at full size and had no bound at all, so a package whose `control`
	inset is SPENDABLE handed the growth straight through — measured 2026-08-28 on
	a legal Pixel Quest variant carving 4px per side, a 40px disc against a 36px
	gutter, painting onto every row (director item 9's photograph).

	A LIST IS A SUM (`themeSnapshot.resolveTotal`, the grammar `resolveSides` and
	`resolveDim` already share): "as wide as the affordance metric, plus the
	row-facing negative space the band spends". Both terms are theme metrics, so
	the reservation moves with the package exactly as it always did. ]]
local EDIT_FOOTPRINT = table.freeze({ EDIT_AFFORDANCE, ROW_GUTTER })
row_actions_metrics.EDIT_FOOTPRINT = EDIT_FOOTPRINT

--[[ EVERY ARGUMENT IS A BUILD-TIME FACT, and that is what makes this safe to
	call once from inside `buildEngine` and close over the result. `env` is
	`spec.env` (optional, `themeSnapshot.neutral()` when absent);
	`leadingActions`/`trailingActions` are the already-validated lists;
	`editingReadable` is `spec.editing`, read only when `hasEditAffordance`. ]]
function row_actions_metrics.build(
	core: any,
	scope: any,
	env: any,
	leadingActions: { any }?,
	trailingActions: { any }?,
	hasEditAffordance: boolean,
	editingReadable: any
): any
	-- ===== theme-resolved chrome (Task 4 fix) ================================
	-- `buttonPad`/`buttonMinWidth`/`trayGap` are theme facts with no font/size
	-- component (unlike the label's own font/size, which arrive already
	-- resolved through `controller.textAt` — see `deriveNaturals`, which stays
	-- in row_actions.luau because it needs the presenter's live text facts), so
	-- they need the environment's theme snapshot directly. `spec.env` is
	-- optional, exactly `table.luau`'s own `metricsOr`/`rowGapPx` pattern:
	-- absent degrades to `themeSnapshot.neutral()`, present and live re-solves
	-- on a runtime theme swap (`env:get("themeMetrics")` is itself reactive).
	--
	-- HOISTED above the naturals (director device round 2026-08-12): the tray's
	-- own travel distance now includes its inter-button gutters, so `trayGap` has
	-- to exist before `leadingWidth`/`trailingWidth` read it.
	local function metricsOr(raw: any): any
		return if type(raw) == "table" and type(raw.controls) == "table" then raw else themeSnapshot.neutral()
	end
	local metricsSig = scope:own(core:memo(function(use)
		if env == nil then
			return themeSnapshot.neutral()
		end
		return metricsOr(use(env:get("themeMetrics")))
	end))
	local buttonPadPx = scope:own(core:memo(function(use)
		return themeSnapshot.resolveNumber(use(metricsSig), BUTTON_PAD) or 0
	end))
	local buttonMinWidthPx = scope:own(core:memo(function(use)
		return themeSnapshot.resolveNumber(use(metricsSig), BUTTON_MIN_WIDTH) or 0
	end))
	local trayGapPx = scope:own(core:memo(function(use)
		return themeSnapshot.resolveNumber(use(metricsSig), TRAY_GAP) or 0
	end))
	local rowGutterPx = scope:own(core:memo(function(use)
		return themeSnapshot.resolveNumber(use(metricsSig), ROW_GUTTER) or 0
	end))
	-- A3 (device bug round 2026-08-12): a themed package's control frame is room
	-- the label cannot use, and a tray button's natural width has to reserve it
	-- the same way the button's own hug measure does — see `deriveNaturals`
	-- (row_actions.luau).
	-- Zero under every flat package (`snapshot.resolve` only fills
	-- `chromeInsets` for a nineSlice/layered slot recipe), so this is inert
	-- until a package actually paints a frame.
	local buttonChromePx = scope:own(core:memo(function(use)
		local metrics = use(metricsSig)
		local insets = if type(metrics) == "table" and type(metrics.chromeInsets) == "table"
			then (metrics.chromeInsets :: any).control
			else nil
		if type(insets) ~= "table" then
			return 0
		end
		local left = if type(insets.left) == "number" then insets.left else 0
		local right = if type(insets.right) == "number" then insets.right else 0
		return left + right
	end))

	-- per-action NATURAL (unconstrained) width — a live-derived signal, one per
	-- declared action, created eagerly at BUILD time rather than inside the
	-- tray's lazy `UI.When` factory. A reactive value created INSIDE that
	-- factory would be a FRESH `core:memo` every remount (Trays mount lazily;
	-- a row can open and close many times), which `scope:own` would dutifully
	-- own and never release until this whole composite disposes — a slow leak
	-- shaped exactly like the "table with no dispose()" mistake
	-- scope_impl.luau's own `own()` guards against, just one level up (a table
	-- WITH a dispose(), that nothing ever calls). Building it once, here, and
	-- having the tray factory below only ever LOOK UP an existing entry, means
	-- every open/close cycle reuses the same handful of reactive nodes.
	--
	-- The signal itself is written by `syncGeometry`/`deriveNaturals` (which stay
	-- in row_actions.luau) on EVERY sync (not frozen — see that file's own TRAY
	-- WIDTH header comment): a plain
	-- `core:signal`, not a memo, because the write happens from an external
	-- hook (the presenter's geometry broadcast), not from a `use()`-tracked
	-- computation.
	local leadingNaturals: { [string]: any } = {}
	for _, action in leadingActions or {} do
		leadingNaturals[action.id] = scope:own(core:signal(nil :: number?))
	end
	local trailingNaturals: { [string]: any } = {}
	for _, action in trailingActions or {} do
		trailingNaturals[action.id] = scope:own(core:signal(nil :: number?))
	end
	local function sumNaturals(naturals: { [string]: any }, use: (any) -> any): number
		local total = 0
		for _, sig in naturals do
			local v = use(sig)
			if v ~= nil then
				total += v
			end
		end
		return total
	end
	-- the tray's total width IS the sum of its buttons' naturals PLUS the gutters
	-- between them — never the tray CONTAINER's own solved rect (that WAS the
	-- feedback-loop bug: a number this same reveal can shrink, chasing a
	-- collapsing target). The naturals themselves are geometry-free (see above)
	-- and `trayGapPx` is a theme metric, so this sum moves live with a label/
	-- text-size/theme change and can never chase itself.
	--
	-- The inter-plate term is `(n - 1) * gap`, the HStack's own arithmetic — the
	-- travel distance and the thing it has to uncover must be the same number, or
	-- the last button parks half off the row (device round 2026-08-12). The
	-- row-facing `rowGutter` (device BUG round, same date — finding A1a) is the
	-- band's own padding and belongs to the same sum for the same reason: the
	-- row has to travel far enough to uncover the plates AND the negative space
	-- in front of them, or the gutter is simply the first plate's new left
	-- margin and the row still butts against art.
	local function bandExtras(actions: { ActionSpec }?, use: (any) -> any): number
		local n = if actions ~= nil then #actions else 0
		if n < 1 then
			return 0
		end
		return (n - 1) * use(trayGapPx) + use(rowGutterPx)
	end
	--
	-- ZERO STAYS ZERO. `0` is this pair's own "nothing has been measured yet"
	-- sentinel (`provisionalWidth` below substitutes its estimate on exactly
	-- that test, which is what keeps a single-frame flick openable), so the
	-- band's fixed extras are added only once there is a plate to put them
	-- beside.
	local function bandWidth(naturals: { [string]: any }, actions: { ActionSpec }?, use: (any) -> any): number
		local sum = sumNaturals(naturals, use)
		if sum <= 0 then
			return 0
		end
		return sum + bandExtras(actions, use)
	end
	local leadingWidth = scope:own(core:memo(function(use)
		return bandWidth(leadingNaturals, leadingActions, use)
	end))
	local trailingWidth = scope:own(core:memo(function(use)
		return bandWidth(trailingNaturals, trailingActions, use)
	end))

	-- ===== Task 9: the edit-mode gutter (leading minus + content/leading-tray
	-- shift) — built ONLY when it can ever matter (`hasEditAffordance`), so a
	-- caller who never wires `editing` adds none of these reactive nodes.
	--
	-- `editGutterPx` is the ONE live pixel amount both Content's rendered
	-- offsetX (row_actions.luau) and the leading tray's own offsetX
	-- (`row_actions_trays.buildTray`) read: 0
	-- when not currently editing, `editAffordancePx + rowGutterPx` (the resolved
	-- `controls.rowActions.editAffordance` metric, live to a theme swap
	-- exactly like `buttonPadPx`/`buttonMinWidthPx` above, PLUS the same
	-- row-facing negative space the tray band spends — device bug round
	-- 2026-08-12, finding A2: a strip exactly one diameter wide leaves the disc
	-- touching the row it is meant to sit outside of) while editing. A
	-- SEPARATE signal from `offset` (Task 5's gesture/spring seam) by design —
	-- see the big comments above `local editingReadable` and `contentOffsetX` in
	-- row_actions.luau for why the two must never merge into one write.
	local editAffordanceShown: any = nil
	local editGutterPx: any = nil
	if hasEditAffordance then
		editAffordanceShown = scope:own(core:memo(function(use)
			return use(editingReadable) == true
		end))
		-- ONE EXPRESSION, resolved once (2026-08-28; see `EDIT_FOOTPRINT` above).
		-- This used to be `editAffordancePx + rowGutterPx` through two memos of its
		-- own; it is the same two metrics and the same sum, said in the form the
		-- disc's `footprint` hint also takes, so the reservation and the ceiling
		-- cannot be edited apart.
		editGutterPx = scope:own(core:memo(function(use)
			if use(editAffordanceShown) then
				return themeSnapshot.resolveTotal(use(metricsSig), EDIT_FOOTPRINT) or 0
			end
			return 0
		end))
	end

	return {
		metricsSig = metricsSig,
		buttonPadPx = buttonPadPx,
		buttonMinWidthPx = buttonMinWidthPx,
		trayGapPx = trayGapPx,
		rowGutterPx = rowGutterPx,
		buttonChromePx = buttonChromePx,
		leadingNaturals = leadingNaturals,
		trailingNaturals = trailingNaturals,
		leadingWidth = leadingWidth,
		trailingWidth = trailingWidth,
		editAffordanceShown = editAffordanceShown,
		editGutterPx = editGutterPx,
	}
end

return row_actions_metrics
