--!strict
-- GALLERY DEMO PICKER — the other half of the hands-on place.
--
-- `theme_picker` made themes switchable at runtime. This makes the DEMO
-- switchable at runtime, which is what turns the gallery from "publish a place
-- per example" into one place you publish once and explore on a phone, a
-- tablet, a desktop and a console.
--
-- Before this, choosing what to look at meant setting a workspace attribute
-- (`LuauUI_Example = 5`) and republishing. That is a fine developer affordance
-- and a useless one on a device you are holding.
--
-- WHY IT LIVES IN examples/, NOT src/. Same reason as the theme picker: a demo
-- switcher is a piece of a SHOWCASE, not of a UI framework. It is written
-- entirely through the public surface, so a game that wants an in-game debug
-- menu can copy this file.
--
-- TWO HALVES, like theme_picker:
--   1. the MODEL below is pure — the catalogue, the selection, and what a
--      selection asks the host to do. It requires nothing and touches no engine
--      API at module scope; tests/gallery_demo_picker.spec.luau asserts it;
--   2. `mount()` builds the overlay. Its proof is the live device pass.
--
-- COLLAPSED BY DEFAULT. On a 360px phone the screen belongs to the demo, not to
-- the chrome for switching demos — so this is one button until you press it,
-- and it closes again on selection.
--
-- FOCUS. Presented `responder = "passive"` (ADR-0014), like the theme picker:
-- it binds nothing gameplay-contended and does not steal the demo's focus.

local demo_picker = {}

demo_picker.ATTRIBUTE = "LuauUI_DemoPicker"

-- The FLOOR of the strip the showcase reserves for its chrome (see
-- init.client's reserveBar and `barReservation` below). The two picker chips
-- draw inside it, one at each end; every demo is laid out below it by the
-- solver, so nothing floats over anything.
--
-- IT USED TO BE THE WHOLE ANSWER, and that was the bug. 62 = the strip's 8px top
-- padding + the taller chip's measured 46px + 8px of slack — measured once, under
-- Studio Neutral, on one machine. A chip is a THEMED control: its height is its
-- package's chrome plus its label at the player's own text size. Under Pixel
-- Quest, on an iPhone, the chip came out taller than the strip meant to hold it
-- and painted over the top of the demo's own page title (device report
-- 2026-07-27) — the same failure the 40 before it had, one theme later.
--
-- So the strip MEASURES now, and this is only its floor: the value for the frame
-- before any geometry exists, and the strip the standalone (non-composed) pickers
-- draw their own chip into.
demo_picker.BAR_HEIGHT = 62

-- THE RESERVATION, as arithmetic rather than as a constant.
--
-- `chipsBottom` is the solved bottom edge of the composed chip row, fed back from
-- the chrome surface through the presenter's `onGeometry` seam — which is what
-- retired this file's old excuse ("a literal because two separate surfaces cannot
-- measure each other"): the showcase composes both chips into ONE surface it owns,
-- and the presenter hands that surface its own solved rects after every refresh.
--
-- IT CANNOT CHASE ITS OWN TAIL. The chip row is placed at the live Roblox topbar
-- inset and NOT at this reservation, so its bottom edge does not move when the
-- reservation does. Reserving from a measurement that the reservation feeds would
-- be a loop; this one is a fixed point on the first frame it has geometry for.
--
-- nil `chipsBottom` = no geometry yet: the floor stands.
function demo_picker.barReservation(coreTop: number, chipsBottom: number?, slack: number): number
	local floor = coreTop + demo_picker.BAR_HEIGHT
	if chipsBottom == nil then
		return floor
	end
	return math.max(floor, chipsBottom + slack)
end
-- THE LABEL IS CLIPPED, NOT THE BOX — same reasoning as theme_picker's
-- CHIP_LABEL_CHARS, and the same first wrong answer: constraining the box made
-- "Temperature converter" WRAP to two lines, so the chip grew out of the
-- strip and covered the demo's own title. Clipping the text keeps one line.
demo_picker.CHIP_LABEL_CHARS = 14

export type Demo = {
	id: string,
	title: string,
	blurb: string,
	-- "example" -> ReplicatedStorage.LuauUIExamples.<module>, built with the
	--              tutorial contract build(LuauUI, core, opts)
	-- "fixture"  -> ReplicatedStorage.LuauUIScenarios.<module>, built with the
	--              scenario contract build(ctx) using a MINIMAL ctx
	kind: string,
	module: string,
}

-- THE CATALOGUE. Order is deliberate: the all-controls fixture is first because
-- it is the one that answers "what does this framework look like on my device",
-- and the tutorials follow in the order the guide teaches them.
demo_picker.DEMOS = {
	{
		id = "all-controls",
		title = "All controls",
		blurb = "One semantic tree, every control, adapting from space and input — not device names",
		kind = "fixture",
		module = "adaptive_controls",
	},
	-- the second fixture, for the same reason the first one leads: swipe row
	-- actions are a FEEL feature, and this is the surface a device pass drives
	-- (its ModeBar switches the same mail model between the hand-wrapped list,
	-- the Table integration, and the VirtualList-hosted mode)
	{
		id = "row-actions",
		title = "Swipe row actions",
		blurb = "Mail-style swipe actions: hand-wrapped list, Table, and hosted VirtualList",
		kind = "fixture",
		module = "row_actions",
	},
	-- the third and fourth fixtures, and they lead the tutorials for the same
	-- reason the first two do: each is the ONLY hands-on surface for a piece of
	-- public API that a still screenshot cannot show. A sideways virtualizer has
	-- to be flung, and a motion policy has to be watched.
	{
		id = "card-rail",
		title = "Card rail",
		blurb = "400 cards sideways: swipe, or step with Left/Right",
		kind = "fixture",
		module = "card_rail",
	},
	{
		id = "with-animation",
		title = "Animation",
		blurb = "One spring moves, reveals and re-orders — Full vs Reduced",
		kind = "fixture",
		module = "with_animation",
	},
	-- ...and the accessibility preference that had to wait for a paint path
	-- (ADR-0035). It sits here, beside the motion demo, because the two are the
	-- same kind of thing: a still screenshot of a backdrop is a dim rectangle, and
	-- the capability is the DIFFERENCE between two settings.
	{
		id = "preferred-transparency",
		title = "Background transparency",
		blurb = "The player's opacity setting, answered by the framework's own backdrop",
		kind = "fixture",
		module = "preferred_transparency",
	},
	-- the fifth fixture, for the same reason as the two above it: a rotating arc
	-- cannot be shown by a still screenshot, and the determinate ring beside it is
	-- what makes "one function of one scalar" legible rather than a claim
	{
		id = "progress-ring",
		title = "Circular progress",
		blurb = "A ring that fills, a ring that spins — one arc on UI.Path",
		kind = "fixture",
		module = "progress_ring",
	},
	-- the sixth fixture, for the same reason as the four above it: what `wrap`
	-- does is only legible NEXT TO what happens without it, and that comparison is
	-- a toggle, not a screenshot
	{
		id = "flow-wrap",
		title = "Flow wrap",
		blurb = "Fourteen tags in one row: turn wrapping off and watch them leave the box",
		kind = "fixture",
		module = "flow_wrap",
	},
	-- the seventh and eighth fixtures, and both are here for the reason the five
	-- above them are: what they demonstrate is a DIFFERENCE between two states of
	-- the same content, which a still screenshot flattens into one picture. The
	-- lifecycle pair is one switch driving two badges (only one caption moves);
	-- the opt-out family is five identical rows of which three refuse something,
	-- and a refusal is an absence until something says who refused.
	--
	-- `lifecycle-hidden` closes round 3's O-15: `lifecycle_hidden` shipped into
	-- `scenarios/init.luau` ORDER on 2026-08-13 and was left out of this list
	-- because this file belonged to a concurrent agent that day, which made it
	-- selectable by workspace attribute and unreachable in-experience.
	{
		id = "lifecycle-hidden",
		title = "Lifecycle & hidden",
		blurb = "One switch, two badges: the slot that stays and the events you cannot see",
		kind = "fixture",
		module = "lifecycle_hidden",
	},
	{
		id = "row-capabilities",
		title = "Rows that say no",
		blurb = "Five rows, one table: pinned, protected and locked — and who refused",
		kind = "fixture",
		module = "row_capabilities",
	},
	-- ...and the ninth, for the reason every fixture above it is here: what it
	-- shows is a SEQUENCE, and a still screenshot flattens a sequence into one
	-- picture. Four stops, one row, and a label that gives things up in order.
	{
		id = "text-degrade",
		title = "What a label gives up",
		blurb = "Narrow one row four times: it says it shorter before anything is cut",
		kind = "fixture",
		module = "text_degrade",
	},
	-- the ninth fixture, and it is here for the reason the others are: what it
	-- demonstrates is a DIFFERENCE between two states of the same list. One toggle
	-- makes every row declare the same height, and the taller posts immediately
	-- paint over their neighbours — the defect the overflow sweep measured, beside
	-- the feature that ends it, in one surface.
	{
		id = "variable-extents",
		title = "Rows of different heights",
		blurb = "400 posts, none the same height: declare one number for all of them and watch",
		kind = "fixture",
		module = "variable_extents",
	},
	-- ...and its Stage 2 sibling, listed separately because the difference between
	-- the two FIXTURES is the demonstration. The one above declares each post's
	-- height correctly and shows what that costs to author; this one declares
	-- nothing, wraps its bodies with no `lineLimit`, and its status line reports how
	-- much of the canvas is measurement and how much is still the estimate.
	{
		id = "measured-extents",
		title = "Rows that measure themselves",
		blurb = "400 posts and no height arithmetic anywhere: the list learns what it painted",
		kind = "fixture",
		module = "measured_extents",
	},
	-- ...and the one after it, for the reason every fixture here is listed: the
	-- difference it demonstrates is a NUMBER, not a picture. A table windowing two
	-- thousand rows and a table that mounted all two thousand look identical; the
	-- status line is the only place the windowing exists, and the three buttons all
	-- act on a row the window has never held.
	{
		id = "table-virtualized",
		title = "Two thousand rows, seventeen real",
		blurb = "One table windowing 2 000 rows: every verb reaches a row that is not there",
		kind = "fixture",
		module = "table_virtualized",
	},
	-- ...and its sibling, for the reason every fixture here is listed: what it shows
	-- is a CHANGE. A table whose first column is 218px wide and one whose first
	-- column was always 218px are the same screenshot, so the committed width of
	-- every column is on screen and the divider is the only way to move it.
	{
		id = "table-columns",
		title = "Columns you can resize",
		blurb = "A header with dividers: drag one, or Tab to a heading and press Return",
		kind = "fixture",
		module = "table_columns",
	},
	-- ...and the lazy grid, for the reason every fixture here is listed: a
	-- `LazyVGrid` over five thousand cells and an eager grid over five thousand
	-- cells paint the same first screen, so the only place the feature exists is
	-- the count of cells that were ever built — and the lane chips move every item
	-- to a different line without moving the one under your eye.
	{
		id = "virtual-grid",
		title = "Lazy grid",
		blurb = "5 000 cells, a few dozen ever built — change the lanes and keep your place",
		kind = "fixture",
		module = "virtual_grid",
	},
	-- ...and the same control turned a quarter turn onto the x axis (LazyHGrid). The
	-- picker carries both because the difference is not a value you can read off a
	-- status line: the lanes run DOWN, the lines advance RIGHTWARD, and the
	-- keyboard ring steps a cell with Down and a whole line with Right.
	{
		id = "virtual-hgrid",
		title = "Lazy rail",
		blurb = "The same 5 000 cells sideways — lanes run down, Right steps a whole line",
		kind = "fixture",
		module = "virtual_hgrid",
	},
	-- the tenth fixture, and the reason is the one every fixture above it gives:
	-- what it demonstrates is INVISIBLE in a picture. Five buttons painted
	-- identically report four different verbs and one nothing at all, and one
	-- declaration on a panel reaches three controls inside it — so the capability
	-- only exists in the log beside them.
	{
		id = "sensory-feedback",
		title = "Sensory feedback",
		blurb = "Five identical buttons that mean different things — one panel speaks for three",
		kind = "fixture",
		module = "sensory_feedback",
	},
	-- ...and the eleventh, for the reason every fixture above it is here: what it
	-- shows is a COMPARISON between two states of one screen. The commissioning
	-- screenshots are a HUD before and after a browser URL bar opens; the switch
	-- in this fixture is that URL bar, and the HUD degrades by rank instead of
	-- landing on itself.
	{
		id = "hud",
		title = "Screen-anchored HUD",
		blurb = "A game HUD: open the URL bar and watch it give way by rank instead of overlap",
		kind = "fixture",
		module = "hud",
	},
	-- ...and the twelfth, for the same reason: what it shows is the difference
	-- between four states that paint IDENTICAL pixels. Only the declaration
	-- changes, and only the framework's own sentence tells them apart.
	{
		id = "surface-overlap",
		title = "Cross-surface overlap",
		blurb = "One probe over one screen: same pixels, four declarations, one alarm",
		kind = "fixture",
		module = "surface_overlap",
	},
	-- ...and two more of the same kind, both landed 2026-08-15. Each shows a
	-- defect that IS NOT IN A FRAME: a leak paints nothing at all, and a
	-- dictionary's iteration order is only wrong compared with the frame before
	-- it. Neither is reachable from a screenshot, which is exactly the test this
	-- catalogue exists to apply.
	{
		id = "branch-scope",
		title = "When branch scope",
		blurb = "Two identical panels. One releases what it opened; the other keeps it",
		kind = "fixture",
		module = "branch_scope",
	},
	{
		id = "sorted-entries",
		title = "Deterministic dictionaries",
		blurb = "The same twelve scores built three ways: one column reshuffles, one holds",
		kind = "fixture",
		module = "sorted_entries",
	},
	-- ...and the time-curve fixture (ADR-0033), here for the reason every fixture
	-- above it is: the difference between a duration and a spring's asymptote is
	-- not in any single frame. It is a stopwatch reading 0.52 against 1.05, four
	-- pucks that land together by different routes, and a reduced-motion pass
	-- where the decorative halves place instantly while the cooldown keeps
	-- stepping — none of which a screenshot can hold.
	{
		id = "time-curves",
		title = "Time curves",
		blurb = "A cooldown that lands on time, four curves, one 400 ms trip",
		kind = "fixture",
		module = "time_curves",
	},
	-- ...and the one demo whose content LuauUI does not draw at all (ADR-0034):
	-- RichText spans, an engine-measured list, and a 2x-oversize frame the box
	-- crops — three capabilities the framework declines by design, plus a button
	-- that adopts a `Part` and shows the refusal verbatim.
	{
		id = "foreign-content",
		title = "Foreign instances",
		blurb = "A box for an instance LuauUI does not own: RichText, an engine list, and the clip",
		kind = "fixture",
		module = "foreign_content",
	},
	-- ...and the two the round-3 owed ledger's O-30 named: a piece of public API is
	-- not shipped because a fixture somewhere calls it, it is shipped when a player
	-- can reach it. `newAsyncImage` was exercised by the `async_images` scenario
	-- and five reference/sponsor surfaces and `canvasGroup` by six `sponsor_*`
	-- fixtures and `p2_cartwheel` — and NO entry in this list reached either, so in
	-- the shipped place both were selectable by workspace attribute and by nothing
	-- a player can do. That is the same defect `lifecycle-hidden` above records.
	{
		id = "async-images",
		title = "Async images",
		blurb = "Three thumbnails over the real transport: placeholder, ready, and one that fails",
		kind = "fixture",
		module = "async_images",
	},
	{
		id = "canvas-group",
		title = "One fade, or three",
		blurb = "Three plates, one opacity: faded as a single picture, then one plate at a time",
		kind = "fixture",
		module = "canvas_group",
	},
	{
		id = "ex01",
		title = "Temperature converter",
		blurb = "Text entry: live preview versus committed value",
		kind = "example",
		module = "01_temperature_converter",
	},
	{
		id = "ex02",
		title = "Playlist table",
		blurb = "Sortable, reorderable, filterable table",
		kind = "example",
		module = "02_playlist_table",
	},
	{
		id = "ex03",
		title = "Settings sync",
		blurb = "Optimistic apply, accept, reject and rollback",
		kind = "example",
		module = "03_settings_sync",
	},
	{
		id = "ex04",
		title = "Confirm dialog",
		blurb = "Modal presentation, focus trapping and cancel",
		kind = "example",
		module = "04_confirm_dialog",
	},
	{
		id = "ex05",
		title = "Word game",
		blurb = "A full keyboard game — try it with a touch keyboard",
		kind = "example",
		module = "05_word_game",
	},
	{
		id = "ex06",
		title = "Tile game",
		blurb = "Grid layout and drag interaction",
		kind = "example",
		module = "06_tile_game",
	},
	{
		id = "ex07",
		title = "Match 3",
		blurb = "Dense animated grid",
		kind = "example",
		module = "07_match3",
	},
} :: { Demo }

-- clip(text, chars) -> text that fits one chip line, with an ellipsis when it
-- had to give something up. Pure, so the spec asserts it.
function demo_picker.clip(text: string, chars: number): string
	if #text <= chars then
		return text
	end
	return string.sub(text, 1, math.max(1, chars - 1)) .. "…"
end

function demo_picker.list(): { Demo }
	return demo_picker.DEMOS
end

function demo_picker.find(id: string): Demo?
	for _, d in demo_picker.DEMOS do
		if d.id == id then
			return d
		end
	end
	return nil
end

function demo_picker.initialSelection(): string
	return demo_picker.DEMOS[1].id
end

export type Command = { action: string, selection: string }

-- choose(current, id) -> what the host should do. Selecting the demo already
-- showing is a NO-OP, not a remount: a picker that tears down and rebuilds the
-- thing you are already looking at loses your scroll position and your state
-- for nothing.
function demo_picker.choose(current: string, id: string): Command
	if id == current then
		return { action = "none", selection = current }
	end
	if demo_picker.find(id) == nil then
		return { action = "none", selection = current }
	end
	return { action = "swap", selection = id }
end

-- next(current) -> the following demo, wrapping. The gamepad/keyboard path: a
-- player on a couch should not have to open a list to move on.
function demo_picker.next(current: string, step: number): string
	local index = 1
	for i, d in demo_picker.DEMOS do
		if d.id == current then
			index = i
		end
	end
	local count = #demo_picker.DEMOS
	local nextIndex = ((index - 1 + step) % count + count) % count + 1
	return demo_picker.DEMOS[nextIndex].id
end

export type MountOpts = {
	LuauUI: any,
	core: any,
	env: any,
	presenter: any,
	-- (demo) -> built | nil; the host owns HOW a demo mounts, because that
	-- differs between the tutorial contract and the scenario contract
	mountDemo: (Demo) -> any,
	-- called after this overlay re-presents itself, so the host can re-raise any
	-- OTHER overlay it owns (the theme picker) above the freshly mounted demo
	onRaise: (() -> ())?,
	-- COMPOSED ONLY. What the chip's press means when the host owns panel
	-- PRESENCE — the showcase chrome does, because the open panel is now its own
	-- presented surface (showcase_chrome.luau §2). The chrome writes `open` back
	-- so this picker's chip still says "Close" while its own section is showing.
	onChip: (() -> ())?,
	-- COMPOSED ONLY. Called after a ROW is chosen, so the host can take its panel
	-- down. Absent, the picker closes its own `open` signal exactly as before.
	onChose: (() -> ())?,
	warn: ((message: string) -> ())?,
}

-- mount(opts) -> { handle, selection, current, dispose }
function demo_picker.mount(opts: MountOpts): any
	local LuauUI = opts.LuauUI
	local UI = LuauUI.UI
	local core = opts.core
	local scope = core:scope("gallery-demo-picker")

	local selection = scope:own(core:signal(demo_picker.initialSelection()))
	local open = scope:own(core:signal(false))
	local mounted: any = nil
	-- FORWARD-DECLARED. `show` calls `raise`, and `raise` needs the screen, which
	-- needs the rows, which need `show`. A local declared later is not an upvalue
	-- of a function defined earlier — it compiles as a global read and is nil at
	-- call time (docs/lessons/later-locals-are-not-upvalues.md; this file was the
	-- lesson's next victim).
	local raise: () -> ()

	local function disposeMounted()
		if mounted == nil then
			return
		end
		if mounted.dispose ~= nil then
			pcall(mounted.dispose)
		end
		if mounted.handle ~= nil then
			pcall(opts.presenter.dismiss, mounted.handle)
		end
		mounted = nil
	end

	local function show(id: string)
		local demo = demo_picker.find(id)
		if demo == nil then
			return
		end
		disposeMounted()
		local ok, built = pcall(opts.mountDemo, demo)
		if not ok then
			(opts.warn or print)(`[LuauUI Showcase] '{demo.title}' failed to mount: {tostring(built)}`)
			-- RAISE ANYWAY. The previous demo has already been dismissed, so
			-- returning here left a blank screen with no way back: the chips are
			-- presented BELOW the demo in z-order, and only `raise` puts them back
			-- on top. A failed demo must not take the chrome down with it.
			raise()
			return
		end
		mounted = built
		raise()
	end

	--[[ THE CHIP'S LABEL, AND WHERE THE CHARACTER CLIP DID AND DID NOT SURVIVE.

		`CHIP_LABEL_CHARS = 14` is documented as "what fits beside the demo picker's
		chip on the narrowest phone portrait (320px)" — which makes the constant a
		TWO-CHIP BUDGET written as a number, and clipping by character count the
		thing `[SHOWCASE-CHROME]: CONCERNS 16` replaced: the composed chrome steps
		its chips down a `UI.ViewThatFits` ladder to icon-only instead, which is a
		measurement rather than a guess about a font. So the COMPOSED chip carries
		the demo's real title and lets the ladder decide.

		The STANDALONE path keeps the clip byte-for-byte: it draws its own chip into
		its own 62px strip with no ladder above it, and the eight single-example
		places' geometry assertions are written against that. ]]
	local currentTitle = scope:own(core:memo(function(use)
		local demo = demo_picker.find(use(selection))
		local title = if demo ~= nil then demo.title else "—"
		if opts.composed == true then
			return title
		end
		return demo_picker.clip(title, demo_picker.CHIP_LABEL_CHARS)
	end))
	local toggleLabel = scope:own(core:memo(function(use)
		return if use(open) then "Close" else use(currentTitle)
	end))

	-- A FUNCTION, NOT AN ARRAY. The composed host draws its rows inside its own
	-- card (`rows` below) while the standalone path keeps its own `ScrollView`
	-- (`list`); building the blueprints twice keeps the two trees from ever
	-- sharing a node table, which is the kind of aliasing that only misbehaves
	-- once both are mounted at the same time. The `selected` memos are shared —
	-- they are derived state, not nodes.
	local isCurrentOf: { [string]: any } = {}
	for _, demo in demo_picker.DEMOS do
		isCurrentOf[demo.id] = scope:own(core:memo(function(use)
			return use(selection) == demo.id
		end))
	end
	local function buildRows(): { any }
		local rows = {}
		for _, demo in demo_picker.DEMOS do
			table.insert(
				rows,
				UI.Button({
					id = demo.id,
					label = demo.title,
					selected = isCurrentOf[demo.id],
					onActivate = function()
						local command = demo_picker.choose(selection:get(), demo.id)
						if command.action == "swap" then
							selection:set(command.selection)
							show(command.selection)
						end
						if opts.onChose ~= nil then
							opts.onChose()
						else
							open:set(false)
						end
					end,
				})
			)
		end
		return rows
	end

	-- THE CHIP and THE LIST, as pieces. The host composes them into one chrome
	-- surface beside the theme picker's chip when it asks for `composed`; the
	-- historical screen below is what a non-composing caller still gets.
	-- see theme_picker's chip: one HStack cannot hold two children called
	-- "Toggle", and the historical id stays on the non-composed path
	local function pressChip()
		if opts.onChip ~= nil then
			opts.onChip()
		else
			open:set(not open:get())
		end
	end
	local chip = UI.Button({
		id = if opts.composed == true then "DemoToggle" else "Toggle",
		label = toggleLabel,
		surface = "chip",
		onActivate = pressChip,
	})
	-- THE ICON RUNG of the chrome's `ViewThatFits` ladder (CONCERNS 16: step the
	-- chips down to icon-only rather than clipping their labels by character
	-- count). `label` stays and is not drawn, so the rung is still a control with
	-- an accessible name; "menu" is the framework's own list mark.
	local iconChip = UI.Button({
		id = "DemoToggleIcon",
		label = toggleLabel,
		surface = "chip",
		shape = "circle",
		icon = "menu",
		onActivate = pressChip,
	})
	-- THE LIST SCROLLS, AND IT IS SIZED `hug` ON BOTH AXES (director report
	-- 2026-07-27, found live under Pixel Quest). This was a plain `VStack`, so it
	-- had no cap and no scroller: nine demos at a pixel package's row height came
	-- to 720px inside the 689px this overlay actually gets on a notched phone
	-- (844 viewport, less 59+34 safe insets, less the 62px reserved chrome strip)
	-- and the last demo was simply cut off the bottom of the screen with no way to
	-- reach it. Landscape is far worse: 700px of list in 235px of room.
	--
	-- NINE IS THAT MEASUREMENT'S COUNT, NOT TODAY'S. The catalogue stands at
	-- ELEVEN since the SwiftUI-parity round-2 fixtures joined it, which moves the
	-- margin the wrong way — and is exactly why the fix had to be a cap rather
	-- than a taller literal. Adding a demo does not send anyone back to re-measure
	-- this number; that is the property the cap bought.
	--
	-- The THEME picker met this exact defect in round 10 and its fix is written up
	-- at length beside its own panel — including the three wrong shapes that came
	-- first (a ScrollView around the card clips the card; one inside it makes two
	-- raised surfaces; and `fill` never registers overflow at all because a fill
	-- box is by definition never smaller than its content). This picker is the
	-- sibling that was missed.
	--
	-- `ScrollView` takes `surface` and `padding` like any container, so the
	-- scroller IS the card: one node, one edge, one padding, scrollbar inside it
	-- by construction. `hug` is the content size CAPPED at what the parent
	-- offered, which is one declaration for both cases — a short list stops at its
	-- last row, a long one lets the cap bite so the overflow turns scrolling on.
	local list = UI.ScrollView({
		id = "Rows",
		gap = "xs",
		surface = "raised",
		padding = "s",
		width = { type = "hug" },
		height = { type = "hug" },
		children = buildRows(),
	})
	-- ...AND THE PLAIN STACK the composed host puts inside ITS card. The chrome's
	-- panel is already a `ScrollView` with `surface = "raised"` — the scroller IS
	-- the card — so handing it the `list` above would nest a raised scroller in a
	-- raised scroller, which is wrong shape #2 from the theme picker's round-10
	-- write-up (a rounded panel inside a rounded panel with a gutter and no
	-- meaning to it).
	local rowsStack = UI.VStack({
		id = "Rows",
		gap = "xs",
		width = { type = "fill", weight = 1 },
		children = buildRows(),
	})

	if opts.composed == true then
		-- IN COMPOSED MODE THIS PICKER OWNS NO SURFACE, so "raise" means "ask the
		-- host to put its chrome back on top" — the demo it just mounted was
		-- presented after the chrome and therefore draws over it. `show` calls
		-- this, and `raise` is a forward-declared local: leaving it nil here
		-- would make the first demo swap a nil call.
		raise = function()
			if opts.onRaise ~= nil then
				opts.onRaise()
			end
		end
		return {
			chip = chip,
			iconChip = iconChip,
			list = list,
			rows = rowsStack,
			open = open,
			selection = selection,
			-- the host mounts the first demo itself once its chrome is up: this
			-- picker no longer owns a surface to raise above it
			show = show,
			current = function()
				return selection:get()
			end,
			showNext = function(step: number)
				local id = demo_picker.next(selection:get(), step)
				selection:set(id)
				show(id)
			end,
			dispose = function()
				disposeMounted()
				scope:dispose()
			end,
		}
	end

	-- INSIDE THE RESERVED STRIP, at its left end (the theme chip takes the
	-- right). The negative offset lifts this surface back INTO the strip that
	-- `coreSafeInsets` reserved for it.
	local screen = UI.Screen({
		id = "ShowcaseDemos",
		padding = "s",
		children = {
			UI.Anchor({
				id = "Dock",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.VStack({
						id = "Panel",
						anchor = "topLeft",
						offsetY = -demo_picker.BAR_HEIGHT,
						gap = "xs",
						children = {
							chip,
							UI.When({
								id = "List",
								condition = open,
								thenView = function()
									return list
								end,
							}),
						},
					}),
				},
			}),
		},
	})

	-- Z-ORDER IS PRESENT ORDER (presenter §2.2: each later surface renders
	-- above). There is no opts.displayOrder and no bring-to-front, so a demo
	-- presented after this overlay draws OVER it — which is exactly what
	-- happened: the all-controls stepper rendered on top of the demo chip and
	-- cut its label in half.
	--
	-- So the overlay re-presents itself after every demo mount. It is a two-node
	-- surface; rebuilding it is cheaper than the alternative of teaching the
	-- presenter a raise operation for one example's benefit.
	local handle: any = nil
	function raise()
		if handle ~= nil then
			opts.presenter.dismiss(handle)
		end
		handle = opts.presenter.present(screen, { responder = "passive" })
		if opts.onRaise ~= nil then
			opts.onRaise()
		end
	end

	raise()
	-- mount the first demo immediately: an empty screen with one button on it
	-- is not a showcase
	show(selection:get())

	return {
		handleOf = function()
			return handle
		end,
		selection = selection,
		open = open,
		current = function()
			return selection:get()
		end,
		showNext = function(step: number)
			local id = demo_picker.next(selection:get(), step)
			selection:set(id)
			show(id)
		end,
		dispose = function()
			disposeMounted()
			if handle ~= nil then
				opts.presenter.dismiss(handle)
			end
			scope:dispose()
		end,
	}
end

return demo_picker
