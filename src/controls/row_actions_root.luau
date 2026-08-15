--!strict
--[[ row_actions_root — the standalone/Table row node, composed.

	WHAT THIS IS. The node tree `newRowActions` mounts when it is NOT in hosted
	mode: the root `UI.Anchor`, the trays under it in paint order, the `Content`
	ZStack that slides over them (with its sign-following anchor, its edit gutter
	padding and its collapse `overflow` declaration), the drag hit Grip on top,
	and the edit-mode leading minus painted over the lot.

	HOSTED MODE BUILDS NONE OF THIS. A closed hosted row must cost its host
	nothing at all, so `buildEngine` simply does not call `build` — the seams the
	nodes used to answer for (paths, paint, the presenter handoffs) are
	`pathsOf`/`applySlide`/`contributionFields` instead.

	ONE EXCEPTION, AND IT IS DELIBERATE: `buildEditAffordance` (2026-08-15, stage 1
	of `docs/plans/table-hosted-row-actions-stage2.md`'s order). The edit-mode minus
	is the one node BOTH modes want, for the same reason the trays are
	(`row_actions_trays.luau`): a hosted host parents it under its own overlay
	instead of this file's row root, and a parent is not a reason to have two
	constructions of one button that can drift apart. So it is a SECOND exported
	function rather than an inline block, `buildEngine` calls it whenever
	`hasEditAffordance`, and `build` below merely receives the result. Table is the
	only surface that has an edit mode at all, and it cannot host without this.

	IT SHARES NOTHING MUTABLE WITH THE ENGINE. Every input is a build-time fact or
	a reactive node `buildEngine` creates once and never reassigns: `offset`,
	`rowHeightOverride`, `editAffordanceShown`, `editGutterPx`, the tray views, the
	`pointerHandlers` table, and `firstDestructiveEntry` (a local function, for the
	minus' accessible label). It touches none of that closure's ~60 mutable
	upvalues, which is the test every extraction in this split had to pass
	(docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md,
	tools/check_source_size.py).

	PUBLIC INTERFACE: `build(p) -> any` (the root blueprint) and
	`buildEditAffordance(p) -> any` (the edit-mode minus `UI.When`, used by BOTH
	modes — see above).

	DEPENDS ON: `./row_actions_metrics` for the `EDIT_AFFORDANCE` theme key alone.

	THE PAINT ORDER IS THE CONTRACT, and it is three device rounds deep: trays
	first, then Content (which slides over them), then the Hit Grip INSIDE Content
	and after `content` (2026-08-13: the engine delivers a press to the TOPMOST
	interactive object only, so a Grip behind a Button never sees the swipe —
	docs/lessons/a-button-eats-the-swipe-underneath-it.md), then the edit minus
	last so a trailing swipe passes under it. Reorder these and a device breaks in
	a way no headless test can see. ]]

local rowActionsMetrics = require("./row_actions_metrics")

local EDIT_AFFORDANCE = rowActionsMetrics.EDIT_AFFORDANCE

local row_actions_root = {}

export type Params = {
	UI: any,
	core: any,
	scope: any,
	id: string,
	-- `spec.width`: nil leaves the root content-sized (every standalone caller);
	-- Table passes its own `{ type = "fill", weight = 1 }` straight through
	width: any,
	content: any,
	-- the tray `UI.When`s (row_actions_trays), already in paint order
	trayViews: { any },
	-- the engine's own live state, read-only from here
	offset: any,
	rowHeightOverride: any,
	-- the four `_pointerHandlers`, wired onto the internal Hit Grip unless the
	-- caller drives them from its own hit surface (`externalGesture`)
	pointerHandlers: any,
	externalGesture: boolean,
	-- Task 9, all nil/false unless this row can ever show the edit-mode minus.
	-- `editAffordanceView` is built by `buildEditAffordance` below, in
	-- `buildEngine` (both modes) — nil when `hasEditAffordance` is false.
	hasEditAffordance: boolean,
	editAffordanceShown: any,
	editGutterPx: any,
	editAffordanceView: any,
}

export type EditAffordanceParams = {
	UI: any,
	-- `editAffordanceShown` — the live "is this row editing" memo
	-- (row_actions_metrics); the `UI.When` mounts nothing while it is false
	editAffordanceShown: any,
	-- the destructive action this minus stands for, for its accessible label
	-- (nil is legal — the fallback name below is used)
	destructiveEntry: any,
}

--[[ THE EDIT-MODE MINUS, BUILT ONCE FOR BOTH MODES (2026-08-15, stage 1 of the
	Table-hosting order). Standalone/Table parents it in `build` below, last, so a
	trailing swipe passes under it; a HOST parents it in its own per-list overlay
	beside the shared trays, at the path it declared as `spec.paths.editAffordance`.
	Same node ids in both — `EditAffordanceWhen/then/EditAffordance` — because the
	engine's Activate route matches on that suffix under whichever root applies. ]]
function row_actions_root.buildEditAffordance(p: EditAffordanceParams): any
	local UI = p.UI
	local editAffordanceShown = p.editAffordanceShown
	local destructiveEntry = p.destructiveEntry

	-- ===== Task 9: the edit-mode leading minus =============================
	-- iOS pattern: while editing AND a destructive action exists somewhere,
	-- a small circular button sits in a LEADING gutter; tapping it opens the
	-- trailing tray (the destructive action is a second tap away, never
	-- direct). `UI.When` keyed on `editAffordanceShown` — the identical
	-- lazy-mount idiom the trays already use (Task 3's own header comment;
	-- `table.luau:1079-1122`'s `EditWhen` is the cited precedent): zero
	-- Instances while not editing, beyond the one permanent `Frame` a
	-- mounted-but-closed `UI.When` always costs — paid only when
	-- `hasEditAffordance`, i.e. only when a caller actually wires `editing`
	-- on a row that has a destructive action. (The menu no longer shares
	-- this cost — redteam item 2's fix moved it to its own presentModal
	-- surface, which mounts and unmounts atomically with zero permanent
	-- node on the row at all; see the big comment above `local function
	-- openMenu` in row_actions.luau.)
	--
	-- PAINT ORDER: built here, INSERTED AFTER `Content` (array order = paint
	-- order, later wins) — see the insertion site below. It used to go in
	-- ahead of Content, which let a trailing drag cover it; the director's
	-- device round reversed that call ("the minus STAYS PINNED at the left
	-- during a swipe"), and Content's gutter is a padding now, so at rest
	-- and on a leading swipe the two never overlap either way.
	--
	-- DIAMETER: `shape = "circle"` + ONE authored axis (`width` only —
	-- `blueprint.luau`'s own `assertShape` rejects both) makes a true 1:1
	-- disc at the theme's `editAffordance` metric; the framework's OWN
	-- Button contract (`src/controls/contract.luau`: `Button.minHitSize =
	-- 44`) already floors the ENGINE HIT RECT at `targetSizes.minimum`
	-- regardless of the painted size (`renderer.luau`'s `effectiveHitFloor`
	-- — B-BTN3, "the VISUAL rect is deliberately untouched... declaring a
	-- floor here is all a new control has to do") — the documented small-
	-- target pattern this codebase already has (the reorder Grip's own
	-- `minHitSize = 44` is the sibling precedent), so NOTHING extra is
	-- authored here for the hit-target rule: a 28px disc already gets a
	-- 44px+ tappable area for free, on every input class.
	--
	-- COLOUR (`danger` glyph, per the brief). `role = "destructive"` is the
	-- one existing theme-token mechanism this control family has for
	-- "danger" (the SAME mapping the header comment above already
	-- establishes for a destructive tray button: "role = 'destructive'
	-- maps straight to it... paints control/content pair"). It could NOT be
	-- composed with `surface = "raised"` (surfaceStrong) to get a literal
	-- "danger glyph ON a surfaceStrong plate" split: `src/tokens/
	-- sheet_model.luau`'s own comment on the role rules is explicit — "role
	-- owns the resting fill... sit after the base/surface/selected fills"
	-- — so a `role = "destructive"` Button's BackgroundColor3 always wins
	-- over a `surface = "raised"` on the SAME node, regardless of prop
	-- order; the token vocabulary has no independent "content-only danger"
	-- tint (Text's own `role` enum is `{ "secondary", "content" }`, no
	-- `"danger"`; the chrome `ImageColor3` role tints — `$ChromeTintDanger`
	-- — only reach IMAGE-driven skinned art layers, not the plain-glyph
	-- fallback path this composite otherwise relies on). Adding that split
	-- would mean a new sheet rule in a file this task does not touch.
	-- `role = "destructive"` reuses the ALREADY-shipped, already-tested
	-- mapping instead: a solid danger-filled disc with an onDanger minus,
	-- visually consistent with the trailing tray's own destructive button
	-- one tap away — the closer real-iOS match besides.
	return UI.When({
		id = "EditAffordanceWhen",
		condition = editAffordanceShown,
		thenView = function()
			return UI.Button({
				id = "EditAffordance",
				anchor = "left",
				shape = "circle",
				role = "destructive",
				icon = "decrement", -- the framework's own minus glyph (standard_icons)
				-- ACCESSIBLE LABEL (the reorder Grip carries none — it is
				-- unfocusable, non-activating; this IS a Button, so it
				-- needs one). `Button.label` is the framework's own
				-- "required even when the button renders custom content...
				-- stays the semantic name and is not drawn" seam
				-- (blueprint_schema.luau) — the SAME icon-only-control
				-- precedent `shape = "circle"` exists for. Reuses the
				-- destructive action's own label (typically "Delete") so
				-- the announced name matches exactly what a second tap
				-- reaches.
				label = if destructiveEntry ~= nil then destructiveEntry.action.label else "Delete",
				width = { type = "fixed", px = EDIT_AFFORDANCE },
			})
		end,
	})
end

function row_actions_root.build(p: Params): any
	local UI = p.UI
	local core = p.core
	local scope = p.scope
	local id = p.id
	local width = p.width
	local content = p.content
	local trayViews = p.trayViews
	local offset = p.offset
	local rowHeightOverride = p.rowHeightOverride
	local pointerHandlers = p.pointerHandlers
	local externalGesture = p.externalGesture
	local hasEditAffordance = p.hasEditAffordance
	local editGutterPx = p.editGutterPx
	-- built by `buildEditAffordance` above, in `buildEngine`, so hosted mode gets
	-- the identical node — nil exactly when `hasEditAffordance` is false
	local editAffordanceView = p.editAffordanceView

	-- the trays (`row_actions_trays`, built once for both modes) come FIRST, in
	-- declared order: array order is paint order, and Content — inserted
	-- last, below — slides over them.
	local children = table.clone(trayViews)

	-- THE EDIT GUTTER IS A PADDING, NOT AN OFFSET (director device round
	-- 2026-08-12, finding 2 — this replaces the branch that shipped).
	--
	-- Content's rendered `offsetX` is the bare `offset` in BOTH modes now.
	-- The gutter the minus lives in is the Content node's own left PADDING,
	-- which is a very different thing geometrically and is what fixes the
	-- pop the director filmed.
	--
	-- What shipped: `contentOffsetX = offset` when `offset < 0`, else
	-- `offset + gutter`. `offsetFill` (solver.luau) shrinks a topLeft-
	-- anchored `fill` child by a POSITIVE offset and leaves a NEGATIVE one
	-- at full width ("pushing a child out past the very edge it is anchored
	-- to... is deliberate"), so the two branches are not two views of one
	-- line — they are a STEP of exactly `editGutterPx` at `offset == 0`.
	-- The old comment priced that as "a single-frame pop... at the instant a
	-- live drag crosses zero". It is not: EVERY trailing swipe lives in the
	-- negative branch, so the whole gesture and the whole close flight ran a
	-- full gutter to the left (the row band eating the minus slot, frames
	-- f022-f031) and the gutter reappeared in one frame at the terminal
	-- write (f034). The minus never unmounted — `EditAffordanceWhen` is
	-- keyed on `editing` alone — it was COVERED by a row that had slid into
	-- its gutter.
	--
	-- Padding has neither problem. It is spent before `offsetFill` ever
	-- runs, so it applies identically at every offset and on both signs:
	--   offset  0  -> content box [g, W]      (identical to the old rest)
	--   offset +k  -> [g+k, W]                (identical to the old leading)
	--   offset -k  -> [g-k, W-k]              (continuous, and the trailing
	--                                          tray is exposed by the FULL k
	--                                          — the under-exposure the old
	--                                          comment feared is what the
	--                                          padding form avoids)
	-- With no edit affordance the padding is absent and every number above
	-- is byte-identical to what shipped.
	--
	-- THE ONE DIFFERENCE FROM AN OFFSET, stated so nobody rediscovers it as
	-- a bug: a padding PARTICIPATES IN MEASURE. On a row whose width is
	-- content-sized (hug), turning `editing` on therefore makes the row
	-- itself 28px wider, where the old offset form left the hug width alone
	-- and displaced the content inside it. That is the correct reading of
	-- "reserve a gutter" — the row genuinely needs the room — and it is
	-- inert for every shipped caller: a list row is `fill` (Table hands its
	-- own `width = { type = "fill", weight = 1 }` straight through to
	-- `spec.width`, and a bare caller in a list gives the same), so the box
	-- is the row's assigned width in both states and only the inner content
	-- moves. A HUG row that also wires `editing` is the one shape that sees
	-- it, and it sees a row that grew to fit its own affordance.
	local contentOffsetX = offset
	--[[ ...AND THE ANCHOR HAS TO FOLLOW THE SIGN (device bug round
		2026-08-12, findings C9c and C9d — "the Mark Read button is very tall
		vertically and causes odd row resizing" / "when the row animates back,
		it overlaps the mark read button and causes that to collapse into
		something on a different row").

		NEITHER FINDING IS ABOUT THE BUTTON. `Content` is `width = fill` under
		an `anchor` parent, and `solver.luau`'s `offsetFill` SHRINKS a fill
		anchor child by its own offset — giving back exactly the room the
		offset costs it, so it cannot hang off the far edge. That rule is
		right, and it has one exemption it states itself: a child anchored to
		the edge it is being PUSHED PAST keeps its full width, because no width
		could bring it back anyway.

		A TRAILING swipe is a negative offsetX on a `topLeft` child, which is
		exactly that exemption — full width, pure translation, correct, and it
		is why the trailing edge never showed this. A LEADING swipe is a
		POSITIVE offsetX on the same `topLeft` child, so the row's content box
		lost the tray's whole width: measured on a showcase list row, `Content`
		319 -> 194px, the preview line re-wrapped, `Content/Row` grew 88 ->
		117px, and the solver reported "overflows its zstack by 0x29px" — 29px
		of row painted over the row below — for the whole time the tray was
		open. On the way back it re-wrapped in two discrete 14px steps
		mid-flight, which is the "collapse" and the "pop" in the report.

		A reveal TRANSLATES the row; it never re-lays it out. Flipping the
		anchor to the edge the offset pushes toward puts both signs inside the
		exemption, and the placement arithmetic is unchanged in both: at
		`topRight` with an unshrunk fill child, `(innerW - w) * 1` is zero, so
		the child still lands at `innerX + offset`. The two branches therefore
		meet exactly at `offset == 0`, with no step for a live drag to cross —
		and `anchor` is an arrange-only prop (blueprint_schema BOX.anchor,
		`dirty = { "arrange" }`), the same class `offsetX` itself is in, so the
		flip costs one node's re-arrange and no re-measure. ]]
	local contentAnchor = scope:own(core:memo(function(use)
		return if use(offset) > 0 then "topRight" else "topLeft"
	end))
	local contentPadding: any = nil
	if hasEditAffordance then
		contentPadding = scope:own(core:memo(function(use)
			return { left = use(editGutterPx) }
		end))
	end
	-- REDTEAM FIX (item 15, LOW). This block used to ALWAYS mount the
	-- hit-surface Grip below, even under `externalGesture = true`, with
	-- every handler set to `nil` — a real Instance that does nothing:
	-- `screen_target.luau` sets `instance.Active = true` for EVERY
	-- `Grip` unconditionally at create time, regardless of whether it
	-- carries any pointer handlers at all, so an "inert" Grip still
	-- costs a genuine extra Active (hit-testable) node — the comment
	-- above (Task 10's own) claimed the caller "must not ALSO wire its
	-- own competing Content Grip," which undersold what was actually
	-- happening: the node itself still mounted, unwired, not "not
	-- wired = doesn't exist." `externalGesture` means Table's own row
	-- Hit (composed with reorder) is ALREADY the row's one pointer
	-- surface — this Grip would never receive a single event even if it
	-- did carry handlers — so it is now OMITTED entirely rather than
	-- merely left unwired: one real Instance saved per wrapped,
	-- reorderable Table row (proven by table.spec.luau's own "mounts NO
	-- internal Content/Hit Grip" case).
	local contentChildren: { any } = { content }
	if not externalGesture then
		table.insert(
			contentChildren,
			--[[ THE DRAG HIT SURFACE, AND IT IS ON TOP (ruling 6, director
				2026-08-13). A `UI.Grip` — unfocusable by default, so it never
				steals a Tab stop from the focusable controls inside `content`
				— sized to fill, and inserted AFTER `content` in this
				array-order-is-paint-order list, which paints it OVER the row.

				IT USED TO BE FIRST, i.e. behind, justified by a comment
				claiming Roblox delivers InputBegan "to every Active GuiObject
				under the point independently of paint order". Measured on the
				real engine 2026-08-13: FALSE. The engine delivers to the
				TOPMOST interactive object only; a `GuiButton` inside `content`
				sinks the press and a Grip behind it receives nothing. A
				control click on the bare Grip fired `GRIP InputBegan`; the
				same click over a button fired the button's
				`InputBegan`/`Activated` and nothing on the Grip. Full evidence
				and the two traps that experiment nearly fell into:
				`docs/lessons/a-button-eats-the-swipe-underneath-it.md`.

				So a row whose `content` held a Button could not be swiped
				where that button covered it. On top, the gesture always
				reaches the row — and the press the row decides is not a swipe
				is handed back down by `forwardUnclaimedTap` above.

				THE OPTION NOT TAKEN was per-caller opt-in ("each button
				declares: offer my presses to the row first"). Rejected by the
				director because it fails in the direction this framework keeps
				getting burned by: silently, per caller, invisible until a
				device.

				AND DO NOT TRUST A HEADLESS TEST HERE ALONE. `fake_target`
				models handler WIRING, not the engine's input sinking, so a
				headless "the grip receives the gesture" case passed on the day
				the real device was dead. The order below is pinned headlessly;
				that the order is the one the ENGINE needs is a live-engine
				claim, verified in Studio. ]]
			UI.Grip({
				id = "Hit",
				width = { type = "fill" },
				height = { type = "fill" },
				onPointerDown = pointerHandlers.onPointerDown,
				onPointerMove = pointerHandlers.onPointerMove,
				onPointerUp = pointerHandlers.onPointerUp,
				onPointerCancel = pointerHandlers.onPointerCancel,
			})
		)
	end
	table.insert(
		children,
		UI.ZStack({
			id = "Content",
			-- SIGN-FOLLOWING (device round 2026-08-12, C9c/C9d): see the big
			-- comment above `local contentAnchor`. Not a static "topLeft".
			anchor = contentAnchor,
			offsetX = contentOffsetX,
			-- `nil` unless this row can ever show the edit minus, so a row
			-- that never wires `editing` carries no padding prop at all
			padding = contentPadding,
			width = { type = "fill" },
			height = { type = "fill" },
			--[[ THE COLLAPSE IS AN INTENTIONAL OVERLAP, AND THE SOLVER WAS
				SAYING SO (director device round 2026-08-13, found while
				timing the commit pause).

				A destructive commit drives the root's height to 0 over a
				spring while `content` — the caller's own row — keeps its
				natural height. That is the whole point of the collapse: the
				row shrinks out from under its contents. But it is also,
				literally, a child overflowing its ZStack, and the solver
				filed a diagnostic for it on EVERY destructive commit:
				"/…/Content/Body: this child overflows its zstack by 0x69px…
				or set overflow = 'intentionalOverlap'".

				Nobody had read it because no case ever sampled
				`diagnostics()` DURING the collapse — the C8a cases above run
				200 frames past the fire, by which point `resetToClosed` has
				put the height back and the diagnostic is long gone
				(docs/lessons/the-solver-already-told-you.md, again).

				So take the solver's own suggestion, and take it ONLY while it
				is true — and key it on `rowHeightOverride` rather than on
				`committingSig`, which was the first thing tried and is one
				frame short. `finishCommit` clears `committingSig` when the
				action fires, but the height override outlives it by a frame:
				measured, the row spends exactly one solve back at offset 0
				with its height still 0, and the diagnostic landed on that
				frame alone. The override IS the collapse — it is non-nil for
				precisely as long as this control is driving the row's height
				under its own contents — so it is the honest condition. A row
				that is not collapsing declares nothing, and a real overflow
				on a resting row still reports.
			]]
			overflow = scope:own(core:memo(function(use)
				return if use(rowHeightOverride) ~= nil then "intentionalOverlap" else nil
			end)),
			children = contentChildren,
		})
	)

	-- ...AND THE MINUS PAINTS OVER IT (director device round 2026-08-12,
	-- finding 2: "the minus STAYS PINNED at the left during a swipe").
	-- Inserted AFTER Content — array order is paint order, later wins — so
	-- a row sliding left on a trailing swipe passes UNDER the affordance
	-- instead of covering it. At rest and through a LEADING swipe the two
	-- do not overlap at all (Content's own left padding is exactly this
	-- gutter), so this changes nothing except the one case it exists for.
	-- The old ordering deliberately let a trailing drag cover the minus;
	-- the director's ruling reverses that call.
	if editAffordanceView ~= nil then
		table.insert(children, editAffordanceView)
	end

	-- REDTEAM FIX (item 2, BLOCKER): the action menu no longer builds a
	-- node here at all — it moved to its own `presentModal` surface (see
	-- the big comment above `local function openMenu`, in
	-- row_actions.luau). No `menuAnchor`, nothing inserted into `children`: a row
	-- with a menu now costs exactly the SAME instance count, open or
	-- closed, as a row with none — an improvement over the old design's
	-- "one permanent Instance while closed" cost (its own comment used
	-- to price that in here), not merely a wash.

	-- Task 5: `height` is the ONE new root prop this task adds — bound to
	-- `rowHeightOverride`, which stays `nil` (BOX.height "content-sized
	-- when absent") for every row that never commits, byte-identical to
	-- Tasks 3-4 (no `height` prop existed on the root before this task).
	local heightPx = scope:own(core:memo(function(use)
		local px = use(rowHeightOverride)
		if px == nil then
			return nil
		end
		return { type = "fixed", px = px }
	end))
	return UI.Anchor({ id = id, width = width, height = heightPx, children = children })
end

return row_actions_root
