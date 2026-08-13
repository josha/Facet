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

	local currentTitle = scope:own(core:memo(function(use)
		local demo = demo_picker.find(use(selection))
		return demo_picker.clip(if demo ~= nil then demo.title else "—", demo_picker.CHIP_LABEL_CHARS)
	end))
	local toggleLabel = scope:own(core:memo(function(use)
		return if use(open) then "Close" else use(currentTitle)
	end))

	local rows = {}
	for _, demo in demo_picker.DEMOS do
		local isCurrent = scope:own(core:memo(function(use)
			return use(selection) == demo.id
		end))
		table.insert(
			rows,
			UI.Button({
				id = demo.id,
				label = demo.title,
				selected = isCurrent,
				onActivate = function()
					local command = demo_picker.choose(selection:get(), demo.id)
					if command.action == "swap" then
						selection:set(command.selection)
						show(command.selection)
					end
					open:set(false)
				end,
			})
		)
	end

	-- THE CHIP and THE LIST, as pieces. The host composes them into one chrome
	-- surface beside the theme picker's chip when it asks for `composed`; the
	-- historical screen below is what a non-composing caller still gets.
	-- see theme_picker's chip: one HStack cannot hold two children called
	-- "Toggle", and the historical id stays on the non-composed path
	local chip = UI.Button({
		id = if opts.composed == true then "DemoToggle" else "Toggle",
		label = toggleLabel,
		surface = "chip",
		onActivate = function()
			open:set(not open:get())
		end,
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
		children = rows,
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
			list = list,
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
