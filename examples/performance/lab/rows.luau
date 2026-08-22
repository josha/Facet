--!strict
-- The performance lab's ROW SHAPE (roadmap Step 9, acceptance PL-3/PL-5/PL-12).
--
-- The plan names this exactly: "each row is an `HStack` containing an image, a
-- `VStack` of primary/secondary text, and representative controls such as a
-- button, toggle, and value control". A list of bare text labels is a cheaper
-- workload that measures a different framework — it never exercises composite
-- control construction, async resource lifecycle per row, or the hit-floor
-- expansion that real interactive rows pay for.
--
-- ONE definition, three consumers: the Facet dense-scroll workload, the headless
-- Lune scene, and the raw-Roblox reference (which reads the GEOMETRY constants
-- below so the two implementations present the same box at the same pitch — a
-- reference laid out differently compares nothing).
--
-- ENGINE-FREE AND REQUIRE-FREE, like the gallery scenario modules: `Facet` and
-- `core` arrive as arguments, so this file runs identically under Lune and inside
-- Roblox with no path assumptions.

local rows = {}

-- Bump with any change to the row's structure, sizes, or control set. Travels
-- with every capture beside the dataset version: the pair IS the workload
-- identity, and a capture from a different pair is not a comparison.
--
-- /2 (2026-08-05): THE ROW NOW RESTACKS ON A COMPACT WIDTH. /1 was a single
-- non-adaptive HStack, and its five children need ~475px — so it overflowed EVERY
-- phone in portrait. On a 359x718 device the solver reported 18 findings: nine
-- "content overflows this hstack by 132px on the main axis; it will paint outside its
-- box" (one per mounted row) and nine vertical overflows of up to 106px, because the
-- Stepper's 44px-floor buttons do not fit a 48px inner height either. The framework
-- diagnosed all of it correctly; the lab never asked. Screenshots from a phone are
-- what finally showed it.
--
-- The fix keeps the workload IDENTICAL — same nodes, same controls, same async image,
-- same disclosure — and changes only the ARRANGEMENT, so a compact capture is still
-- measuring the same work. Dropping a control on narrow screens would have made two
-- viewports incomparable, which is worse than the bug.
rows.VERSION = "perf-row/4"

-- ---- the geometry contract ------------------------------------------------
-- Shared with the native reference so both implementations occupy the same
-- pitch and the same viewport, and with the headless scene so its solve does the
-- same amount of work.
rows.ROW_HEIGHT = 56
-- the restacked form is THREE lines (identity / toggle+button / value control) plus
-- their gaps; measured against the solver's own overflow diagnostics, not guessed
rows.COMPACT_ROW_HEIGHT = 152
rows.ROW_GAP = 4
rows.IMAGE_SIZE = 40
rows.OVERSCAN = 2
-- The narrowest viewport the one-line form fits in. Every supported phone in portrait
-- (320-430px) is far below it, which is why the one-line row could never have worked
-- there — and a landscape phone (up to ~932px) is only sometimes above it.
-- MEASURED IN THE REAL SLOT, which is the part the first measurement got wrong. A row
-- measured with a free height only reveals HORIZONTAL overflow; inside a VirtualList it
-- has a FIXED slot, and the one-line form is too TALL for 56px long after it is narrow
-- enough to fit: at 480px it overflows the slot by 77px, at 540px by 48px, at 600px by
-- 1px, and only from ~640px is it clean. The margin below covers the scrollbar
-- reservation and the list's own padding.
rows.ONE_LINE_MIN_WIDTH = 720

-- The fixed (non-text) part of a row: 8px of padding above and below. It does not
-- move with the type scale, so it is not scaled.
rows.ROW_PADDING_V = 16
-- The TEXT-DRIVEN content of each arrangement at type scale 1.0, measured. The
-- one-line form's text block is shorter than the avatar, so at scale 1 the image is
-- what sets the height — which is why the constant reads as 40 rather than 29.
rows.TEXT_BLOCK = 29
rows.COMPACT_TEXT_BLOCK = 136
-- The gap between the compact form's lines (the `Row` VStack's own `gap`), named so
-- the split arrangement's extra line can be charged for it rather than guessing.
rows.COMPACT_LINE_GAP = 4
-- The control height to fall back to when no metrics are installed — Studio
-- Neutral's `controlSizes.regular.height`, restated so the flat path needs no
-- snapshot.
rows.DEFAULT_CONTROL_HEIGHT = 46
-- MEASURED AT 360px (L-26): the list leaves a row's controls line 302px of the
-- viewport's 360, and the flat Toggle+Button pair needs 264 of it. Both halves are
-- stated because the split rule is an arithmetic comparison and a rule with one
-- number in it is a remembered constant.
rows.LIST_CHROME_H = 58
rows.COMPACT_CONTROLS_WIDTH = 264

-- The row height for an arrangement AT THE LIVE TYPE SCALE. A VirtualList is a
-- FIXED-height windowing list, so the height and the arrangement must be one decision
-- — two would be the split brain `ctx.compact` exists elsewhere in this framework to
-- prevent.
--
-- THE TYPE SCALE IS PART OF THAT DECISION (found on the ten-foot matrix row, where
-- every row overflowed its 56px slot by 3px). A `Large` display class composes a 1.5x
-- floor onto the typography scale, so a row height measured at 1.0 is simply wrong
-- there — the same mistake as measuring it at one viewport width. Only the text part
-- scales; the padding and the avatar do not.
--
-- The one-line form deliberately over-reserves at large scales (max() of an unscaled
-- avatar against scaled text) rather than tracking the exact measurement: a slot that
-- is a few px too tall wastes space, and a slot a few px too short paints one row over
-- the next, which is the defect this whole constant exists to prevent.
-- THE THEME IS THE THIRD INPUT TO THIS BOX (L-26, 2026-08-05), and it was missing
-- for the same reason the viewport width and the type scale each were once: every
-- number above was measured on the FLAT surface, and nobody had asked whether they
-- survived a theme. They do not. A themed `control` carries a carved border the
-- solver reserves as padding — `chromeInsets.control` — and under fantasy-ornate
-- that is 14 per side across and 10 per side down. Measured with the theme actually
-- installed: the one-line row overflowed its 56px slot by 19px at EVERY viewport,
-- and the compact row overflowed its 152px slot by 26px.
--
-- ADDITIVE, never a max() against a themed control height, and that is the
-- load-bearing part: `chromeInsets` is all zeros for every flat package, so this
-- term is exactly 0 on the flat surface and every row height, pitch, window bound
-- and recorded capture stays byte-identical. A themed workload is a different
-- workload; a flat one must not move because a themed one was fixed.
function rows.themeInset(snapshot: any?): { x: number, y: number }
	local chrome = if type(snapshot) == "table" then snapshot.chromeInsets else nil
	local control = if type(chrome) == "table" then chrome.control else nil
	if type(control) ~= "table" then
		return { x = 0, y = 0 }
	end
	local function side(v: any): number
		return if type(v) == "number" then v else 0
	end
	return {
		x = side(control.left) + side(control.right),
		y = side(control.top) + side(control.bottom),
	}
end

-- HOW MANY LINES OF THE ARRANGEMENT ARE CONTROLS, which is what the theme's
-- vertical inset is charged per. Declared beside the builder that lays them out so
-- the two cannot drift: the one-line form puts every control on the single line;
-- the compact form has a controls line and a value line, and (under a theme that
-- costs enough across) a third line for the button.
--[[ HOW MANY TEXT LINES THE ARRANGEMENT STACKS, which is what the accessibility
	text preference is charged per.

	FOUND ON A REAL DEVICE, 2026-08-13 (game director, Galaxy A10e): `dense-scroll`,
	`mount-ramp` and `resize-relayout` all REFUSED TO MOUNT with
	"/PerfWorkload/Rows/Canvas/W/[r1]/Row/Row overflows its zstack by 0x11px". It
	reproduced in Studio only once `preferredTextOffset` was raised — clean at 0,
	+11px at offset 4, +39px at 10, +59px at 14 — so it was invisible to every
	headless run and to a default Studio session, and visible to anyone whose phone
	asks for larger text.

	THE CAUSE IS THE THIRD MISSING INPUT TO THIS BOX, and it is the same story
	twice already told above: `heightFor` learned the type scale after the ten-foot
	row overflowed by 3px, and learned the theme after L-26 measured 19px under
	fantasy-ornate. It never learned the ACCESSIBILITY TEXT PREFERENCE. A
	VirtualList is a fixed-pitch window, so a slot measured without an input the
	content actually has is simply wrong — `docs/lessons/facet-fixed-px-heights.md`
	names the class: a px height fixed against unfixed content.

	`preferredTextOffset` adds its px to EVERY text line's font size, so the charge
	is per line, not per row. Declared here rather than inlined for the reason
	`controlLines` is: the builder below is what decides it, and a constant that
	drifts from the builder is how this box was wrong the previous two times. ]]
--[[ WHAT ONE STEP OF THE TEXT PREFERENCE COSTS ONE LINE, MEASURED.

	The preference adds its px to a line's FONT SIZE, and a line's laid-out height
	grows by more than that — line height is a multiple of font size, and the
	large-text path composes the display scale on top. So charging the raw offset
	is not enough, and the first attempt at this fix did exactly that and still
	refused to mount.

	MEASURED against the real engine in a Studio Play session, 2026-08-13, on the
	one-line arrangement at 698x1513 (dense-scroll, flat theme, scale 1.0), by
	mounting at each offset and reading the solver's own overflow:

	  offset   slot   overflow   content actually needed
	     0      56        0              56
	     4      56        3              59
	    10      65       19              84
	    14      73       31             104

	Content minus the 16px of fixed padding gives the text block: 40 (the avatar
	wins), 43, 68, 88 — i.e. 3.5, 3.9 and 4.2 px per offset step across two lines,
	rising rather than linear because each line's height rounds up independently.

	2.5 px per line per step is therefore an OVER-reservation at every measured
	point (headroom 6/16/11 px at offsets 4/10/14), and over is the correct
	direction by this file's own rule, stated where ROW_HEIGHT is defined: "a slot
	that is a few px too tall wastes space, and a slot a few px too short paints
	one row over the next, which is the defect this whole constant exists to
	prevent."

	A future round that wants the exact number should MEASURE the block rather
	than scale it — the table above is the fixture to check against. ]]
rows.PREFERRED_PX_PER_LINE = 2.5

function rows.textLines(compact: boolean): number
	-- both arrangements stack `Name` over `Detail` (see the builder's UI.Text pair);
	-- the compact form's block is taller because those lines wrap, not because there
	-- are more of them
	return 2
end

function rows.controlLines(compact: boolean, split: boolean?): number
	if not compact then
		return 1
	end
	return if split == true then 3 else 2
end

-- The arrangement's own control height, from the live metrics rather than a
-- constant: a metric package may resize every control at once, and the extra line
-- the split arrangement adds is exactly one control tall.
function rows.controlHeight(snapshot: any?): number
	local sizes = if type(snapshot) == "table" then snapshot.controlSizes else nil
	local regular = if type(sizes) == "table" then sizes.regular else nil
	local h = if type(regular) == "table" then regular.height else nil
	return if type(h) == "number" then h else rows.DEFAULT_CONTROL_HEIGHT
end

-- `split` is the arrangement decision `splitControlsFor` made, threaded in rather
-- than re-derived: the height and the arrangement are ONE decision (the split brain
-- `ctx.compact` exists to prevent), and this function has no viewport to re-decide
-- from.
function rows.heightFor(
	compact: boolean,
	typeScale: number?,
	snapshot: any?,
	split: boolean?,
	preferredTextOffset: number?
): number
	local s = if type(typeScale) == "number" and typeScale == typeScale then math.clamp(typeScale, 0.5, 3) else 1
	local isSplit = compact and split == true
	local themed = rows.themeInset(snapshot).y * rows.controlLines(compact, isSplit)
	-- THE ACCESSIBILITY TEXT PREFERENCE, charged per stacked text line (see
	-- `rows.textLines`). Clamped to the framework's own declared range so a garbage
	-- fact cannot produce a negative slot; 0 is the default and keeps every existing
	-- height, pitch, window bound and recorded capture byte-identical.
	local offset = if type(preferredTextOffset) == "number" and preferredTextOffset == preferredTextOffset
		then math.clamp(preferredTextOffset, 0, 14)
		else 0
	local preferred = math.ceil(offset * rows.PREFERRED_PX_PER_LINE) * rows.textLines(compact)
	if compact then
		-- the extra line the split arrangement adds carries one control's height plus
		-- the gap above it
		local extra = if isSplit then rows.controlHeight(snapshot) + rows.COMPACT_LINE_GAP else 0
		return rows.ROW_PADDING_V + math.ceil(rows.COMPACT_TEXT_BLOCK * s) + themed + extra + preferred
	end
	-- the one-line form's text can now EXCEED the avatar, which it never could at
	-- offset 0 — so the preference joins the max() rather than being added after it
	return rows.ROW_PADDING_V + math.ceil(math.max(rows.IMAGE_SIZE, rows.TEXT_BLOCK * s + preferred)) + themed
end

-- THE ONE ARRANGEMENT DECISION, from a measured width rather than a device size class.
-- The framework's `isCompact` flips at 600px, which is the right boundary for a screen
-- and the wrong one for THIS row: measured, the one-line form still overflows its slot
-- at 600px. A row's requirement is a property of the row, so the lab measures it.
function rows.compactFor(viewportWidth: number): boolean
	return viewportWidth < rows.ONE_LINE_MIN_WIDTH
end

-- THE SECOND ARRANGEMENT DECISION, and the horizontal half of the same L-26 story.
-- The compact form's controls line holds a Toggle and a Button side by side. Measured
-- flat at 360px it needs 264px of the 302px the list leaves it; each control then pays
-- the theme's horizontal inset, so under fantasy-ornate the pair needs 320px and
-- overflowed by 18. There is no narrower arrangement left, so the Button takes its own
-- line — exactly the ruling the Stepper already has above it, for the same reason.
--
-- `nil` viewportWidth means "decide from the theme alone": a flat package costs 0 and
-- never splits, so the flat arrangement cannot move whatever the width.
function rows.splitControlsFor(viewportWidth: number?, snapshot: any?): boolean
	local inset = rows.themeInset(snapshot)
	if inset.x <= 0 then
		return false
	end
	local width = if type(viewportWidth) == "number" then viewportWidth else 0
	local available = width - rows.LIST_CHROME_H
	return rows.COMPACT_CONTROLS_WIDTH + 2 * inset.x > available
end

-- The mounted window a bounded virtualization must stay inside, expressed as the
-- rule rather than a number: rows that fit the viewport, plus overscan at both
-- ends, plus one partial row at each edge.
function rows.expectedWindow(
	viewportHeight: number,
	compact: boolean?,
	typeScale: number?,
	snapshot: any?,
	split: boolean?
): number
	local pitch = rows.heightFor(compact == true, typeScale, snapshot, split) + rows.ROW_GAP
	return math.ceil(viewportHeight / pitch) + 2 * rows.OVERSCAN + 2
end

export type CellCtx = {
	-- the VirtualList cell scope: owns everything the row allocates, so a row
	-- leaving the window reclaims its controls and cancels its image
	scope: any,
	-- the async resource provider the row's image is acquired through. Required:
	-- the cold/warm distinction is a property of the PROVIDER's cache, not of two
	-- different row shapes, so there is no provider-less variant of this row.
	provider: any,
	-- owner-held state, keyed by item id, so a row that leaves and re-enters the
	-- window shows what it showed before (a control whose value resets on scroll
	-- is a different — and much cheaper — workload)
	values: { [string]: any },
	toggles: { [string]: any },
	-- the scope that owns those signals; longer-lived than the cell scope, and
	-- disposed when the dataset is replaced
	ownerScope: any?,
	onActivate: ((item: any) -> ())?,
	-- Step 8.5: `disclose` on the identity line, so a truncated long name keeps a
	-- full-value path. Kept ON by default — the plan forbids improving a profile
	-- by dropping accessibility behaviour, so the expensive path is the default
	-- path and the cheap one is not offered.
	failImage: boolean?,
	-- true when the row must restack for a narrow offer. Supplied by the caller from
	-- `Facet.adaptive.conditions(...).isCompact`, so the height and the arrangement
	-- come from ONE decision.
	compact: boolean?,
	-- true when the compact form's controls line must ALSO break in two, because the
	-- installed theme's `chromeInsets` cost more across than the line has left
	-- (L-26). Supplied by the caller from `rows.splitControlsFor`, for the same
	-- one-decision reason `compact` is. Always false on a flat package.
	splitControls: boolean?,
}

-- Build one row. `item` is a dataset.Item.
function rows.cell(Facet: any, core: any, item: any, ctx: CellCtx): any
	local UI = Facet.UI
	local scope = ctx.scope

	-- The per-row value/toggle signals OUTLIVE the cell (a control that resets when
	-- its row scrolls away is a different, cheaper workload), so they are owned by
	-- the caller's longer-lived `ownerScope` rather than by `scope`. Owning them
	-- somewhere is not optional: a live Studio reset left 488 undisposed signals on
	-- the core because dropping the cache TABLE does not release the SIGNALS.
	local owner = ctx.ownerScope
	local value = ctx.values[item.id]
	if value == nil then
		value = core:signal(item.value)
		if owner ~= nil then
			owner:own(value)
		end
		ctx.values[item.id] = value
	end
	local toggled = ctx.toggles[item.id]
	if toggled == nil then
		toggled = core:signal(item.enabled)
		if owner ~= nil then
			owner:own(toggled)
		end
		ctx.toggles[item.id] = toggled
	end

	local image = Facet.Controls.AsyncImage(core, {
		id = "Avatar",
		scope = scope,
		provider = ctx.provider,
		key = if ctx.failImage then item.imageKey .. "&broken=1" else item.imageKey,
		width = { type = "fixed", px = rows.IMAGE_SIZE },
		height = { type = "fixed", px = rows.IMAGE_SIZE },
	})

	-- the VALUE CONTROL. A Stepper rather than a Slider on purpose: it is a
	-- composite (label + readout + two Buttons over the shared value model), so a
	-- row genuinely carries nested construction and the hit-floor expansion that
	-- goes with it, and it is drivable from every input class without a pointer.
	-- OWNERSHIP, THE PART THAT IS EASY TO GET WRONG (found live, 2026-08-04).
	--
	-- `newStepper` takes no `scope` key — its spec guard names the nine it accepts
	-- — and instead builds its OWN scope and hands back a `dispose`. `newAsyncImage`
	-- above takes the opposite shape: it accepts the cell scope and owns itself
	-- into it. Both are legitimate; the trap is assuming the second shape applies
	-- to the first.
	--
	-- The first version of this row did assume it, and the result was a control
	-- scope per materialized row that nothing ever released: a headless probe of
	-- 400 scroll steps over 2 000 rows took the core from 96 memos and 31 scopes to
	-- 17 078 memos and 4 278 scopes, all still subscribed to live value signals. A
	-- leak like that does not merely waste memory — it makes every later update
	-- notify a crowd of dead readers, which is precisely the "updates proportional
	-- to changed content" question the churn workload asks.
	--
	-- The cell scope releases it, because `scope:own` accepts any table with a
	-- `dispose()`. Recorded as PLN-4.
	local stepper = scope:own(Facet.Controls.Stepper(core, {
		id = "Rate",
		label = "Rate",
		value = value,
		min = 0,
		max = 1,
		step = 0.05,
		format = function(v: number): string
			return string.format("%d%%", math.floor(v * 100 + 0.5))
		end,
	}))

	local labels = UI.VStack({
		id = "Labels",
		gap = 2,
		width = { type = "fill", weight = 1 },
		children = {
			-- IDENTITY: may truncate, and therefore discloses (Step 8.5's rung 3).
			-- Removing this to make the profile prettier is exactly the "weakened
			-- accessibility behaviour" the plan forbids.
			-- ONE LINE EACH, ALWAYS. A VirtualList slot is a FIXED height, and these two
			-- texts were the only things in the row free to grow: a long identity name
			-- wrapped to a second line and the row painted 5px into its neighbour. It
			-- showed up only in the sweep and only on a phone, because it needs a long
			-- string AND a narrow box AND that particular row inside the window — three
			-- coincidences, which is why the height constant looked correct for months.
			--
			-- This is `Text.lineLimit`'s whole reason for existing (see
			-- docs/lessons/fixed-px-heights ...): the OWNER knows the box is fixed, so
			-- the owner caps the lines. `disclose` keeps the full name reachable once it
			-- truncates, so nothing is hidden — the line count is bounded, not the value.
			UI.Text({ id = "Name", text = item.name, textSize = 15, disclose = true, lineLimit = 1 }),
			UI.Text({ id = "Detail", text = item.detail, textSize = "caption", lineLimit = 1 }),
		},
	})
	local toggle = UI.Toggle({ id = "Ready", label = "Ready", value = toggled })
	local open = UI.Button({
		id = "Open",
		label = "Open",
		onActivate = function()
			if ctx.onActivate ~= nil then
				ctx.onActivate(item)
			end
		end,
	})

	if ctx.compact == true then
		-- TWO LINES, SAME NODES. Identity above, controls below — the arrangement a
		-- phone can actually hold. Nothing is dropped, so a compact capture measures
		-- the same construction, the same async image and the same disclosure as a
		-- desktop one.
		-- BUILT AS A LIST, not as a literal with a conditional hole in it: `{a, nil, b}`
		-- leaves an array whose length is a border rather than 3, and the row that
		-- vanished would be the Value line.
		local split = ctx.splitControls == true
		local lines = {
			UI.HStack({
				id = "Head",
				gap = "s",
				width = { type = "fill", weight = 1 },
				children = { image.blueprint, labels },
			}),
			-- THE CONTROLS STACK TOO. Two lines was not enough: the controls line
			-- alone needs ~420px (a Toggle, a Stepper with its label, readout and
			-- two 44px-floor buttons, and a Button), so at 320-414px it still
			-- overflowed. The Stepper takes its own line because it is the widest
			-- of the three by a distance.
			--
			-- ...and under a theme the Button leaves this line too (L-26): each control
			-- pays the recipe's `contentInsets` across, and at 360px the pair no longer
			-- fits. Same nodes, same ids, one more line — the arrangement moves and the
			-- workload does not, which is the rule the split above already follows.
			UI.HStack({
				id = "Controls",
				gap = "s",
				width = { type = "fill", weight = 1 },
				children = if split then { toggle } else { toggle, open },
			}),
		}
		if split then
			table.insert(
				lines,
				UI.HStack({
					id = "Action",
					gap = "s",
					width = { type = "fill", weight = 1 },
					children = { open },
				})
			)
		end
		table.insert(
			lines,
			UI.HStack({
				id = "Value",
				gap = "s",
				width = { type = "fill", weight = 1 },
				children = { stepper.blueprint },
			})
		)
		return UI.VStack({
			id = "Row",
			gap = rows.COMPACT_LINE_GAP,
			padding = "xs",
			width = { type = "fill", weight = 1 },
			children = lines,
		})
	end

	return UI.HStack({
		id = "Row",
		gap = "s",
		padding = "xs",
		width = { type = "fill", weight = 1 },
		children = { image.blueprint, labels, toggle, stepper.blueprint, open },
	})
end

-- The row's own control census, so a capture can state how much of a mounted
-- window is control construction rather than leaving a reader to count the
-- blueprint by eye. Kept beside the builder so it cannot drift from it.
rows.NODES_PER_ROW = {
	-- HStack + AsyncImage layers + VStack + 2 Text + Toggle + Stepper subtree + Button
	note = "structural estimate for the capture summary; the AUTHORITATIVE count is the live instance census",
	approximate = 16,
}

return rows
