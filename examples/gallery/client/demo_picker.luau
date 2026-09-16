--!strict
-- GALLERY DEMO PICKER — the other half of the hands-on place.
--
-- `theme_picker` made themes switchable at runtime. This makes the DEMO
-- switchable at runtime, which is what turns the gallery from "publish a place
-- per example" into one place you publish once and explore on a phone, a
-- tablet, a desktop and a console.
--
-- Before this, choosing what to look at meant setting a workspace attribute
-- (`Facet_Example = 5`) and republishing. That is a fine developer affordance
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
-- FOCUS. Presented `responder = "passive"`, like the theme picker:
-- it binds nothing gameplay-contended and does not steal the demo's focus.

local demo_picker = {}

demo_picker.ATTRIBUTE = "Facet_DemoPicker"

-- The FLOOR of the strip the showcase reserves for its chrome (see
-- init.client's reserveBar and `barReservation` below). The two picker chips
-- draw inside it, one at each end; every demo is laid out below it by the
-- solver, so nothing floats over anything.
--
-- IT USED TO BE THE WHOLE ANSWER, and that was the bug. 62 = the strip's 8px top
-- padding + the taller chip's measured 46px + 8px of slack — measured once, under
-- Facet Neutral, on one machine. A chip is a THEMED control: its height is its
-- package's chrome plus its label at the player's own text size. Under Pixel
-- Quest, on a physical phone, the chip came out taller than the strip meant to hold it
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
--
--[[ `overscanTop` IS SUBTRACTED, AND THAT IS NOT A FUDGE (director round 4,
	2026-08-21). This value is what content must clear in WINDOW space — the host
	publishes it as `appChromeInsets.top` less the platform's own row (2026-09-13)
	— and on a ten-foot display `renderer.luau` ADDS `effectiveOverscanInsets.top`
	to the insets before it solves any content surface. The chip row now sits inside that same
	margin (`showcase_chrome`'s `barTop`), so its measured bottom edge already
	contains the overscan — reserving the raw number would spend it twice and open
	a sixty-pixel dead band between the chips and the demo. Measured at
	1920x1080 Large: demo top 149 either way, where the naive arithmetic gives 209.

	Zero on every non-ten-foot row, where the renderer adds nothing, so the five
	view matrix is byte-identical. ]]
function demo_picker.barReservation(coreTop: number, chipsBottom: number?, slack: number, overscanTop: number?): number
	local floor = coreTop + demo_picker.BAR_HEIGHT
	if chipsBottom == nil then
		return floor
	end
	local over = if type(overscanTop) == "number" and overscanTop > 0 then overscanTop else 0
	return math.max(floor, math.max(0, chipsBottom - over) + slack)
end

--[[ reservationSlack(baseSlack, chromeBleed) -> the gap `barReservation` above
	spends between the chip row's measured bottom edge and the demo starting
	below it (task SHOWCASE3, director repro: Samsung Galaxy S22 Ultra preset,
	Glossy Mobile — a hard dark band edge right under the "Playlist table" /
	"Settings" chips).

	`baseSlack` (`metrics.space.s`) is a PLAIN GAP — the same rhythm step the
	chrome pads itself with — and it is the whole answer under a flat package,
	where nothing paints past a chip's own box. It stopped being the whole
	answer the day a package started drawing a `shadow = "raised"` glow on
	that chip (`chrome.control`): the glow paints OUTSIDE the chip's box, by up
	to the package's own `chromeBleed` (17px under Glossy Mobile/Glossy
	Touch/Fantasy Ornate, 24px under Sci-Fi HUD) — measured live on the S22
	Ultra preset (logical viewport 359x690, `GuiService:GetGuiInset().Y` 58):
	chip row ends at y=58, `Playlist` demo screen (an OPAQUE `surface = "base"`
	panel, presented AFTER the chrome so it paints OVER it) started at y=68,
	only 10px below — 7px short of the chip's own 17px glow, so the demo's
	opaque background painted over the tail of the shadow and cropped it to a
	hard edge instead of a fade.

	`math.max`, NOT `+` — the SAME idiom `src/render/layout_node.luau`'s own
	scroll-canvas reservation already uses for this identical class of fact
	("the requirement is that the gutter be AT LEAST the glow's reach"): a
	package whose rhythm step already clears its own glow (there are none
	today, but a future one might) owes nothing extra, and adding the two
	would only ever overspend. Zero `chromeBleed` (every flat package) leaves
	`baseSlack` untouched, so nothing unthemed moves. ]]
function demo_picker.reservationSlack(baseSlack: number, chromeBleed: number?): number
	local bleed = if type(chromeBleed) == "number" and chromeBleed > 0 then chromeBleed else 0
	return math.max(baseSlack, bleed)
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
	-- "example" -> ReplicatedStorage.FacetExamples.<module>, built with the
	--              tutorial contract build(Facet, core, opts)
	-- "fixture"  -> ReplicatedStorage.FacetScenarios.<module>, built with the
	--              scenario contract build(ctx) using a MINIMAL ctx
	kind: string,
	module: string,
}

-- Keep the picker short. Focused comparisons live inside the three tabbed
-- collections; standalone scenarios remain available to verification tools.
demo_picker.DEMOS = {
	{
		id = "all-controls",
		title = "All controls",
		blurb = "Inputs, actions, indicators and navigation in nested tabs",
		kind = "fixture",
		module = "all_controls",
	},
	{
		id = "collections",
		title = "Collections",
		blurb = "Lists, tables, grids and row actions with large data sets",
		kind = "fixture",
		module = "collections",
	},
	{
		id = "motion-layout",
		title = "Motion and layout",
		blurb = "Compare animation, wrapping, transparency and adaptive layouts",
		kind = "fixture",
		module = "motion_layout",
	},
	{
		id = "hud",
		title = "Screen-anchored HUD",
		blurb = "Game HUD zones adapt to the screen and recover hidden commands",
		kind = "fixture",
		module = "hud",
	},
	{
		id = "radial-menu",
		title = "Quick actions",
		blurb = "Contextual commands around a launcher or a world object",
		kind = "fixture",
		module = "radial_menu",
	},
	{
		id = "ex02",
		title = "Playlist table",
		blurb = "Organize a playlist: sort, edit, reorder and resize columns",
		kind = "example",
		module = "02_playlist_table",
	},
	{
		id = "ex03",
		title = "Settings sync",
		blurb = "Try instant changes, delayed saves and rejected changes that roll back",
		kind = "example",
		module = "03_settings_sync",
	},
	{
		id = "ex05",
		title = "Word game",
		blurb = "Play a word puzzle with keyboard, touch or gamepad",
		kind = "example",
		module = "05_word_game",
	},
	{
		id = "ex06",
		title = "Crossword",
		blurb = "Build crossing words on an interactive board",
		kind = "example",
		module = "06_tile_game",
	},
	{
		id = "ex07",
		title = "Match 3",
		blurb = "Swap tiles, make matches and follow the score",
		kind = "example",
		module = "07_match3",
	},
	-- scaffold: new control demos are appended above this line.
} :: { Demo }

function demo_picker.isPrimary(id: string): boolean
	return demo_picker.find(id) ~= nil
end

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
	Facet: any,
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
	local Facet = opts.Facet
	local UI = Facet.UI
	local core = opts.core
	local scope = core:scope("gallery-demo-picker")

	local selection = scope:own(core:signal(demo_picker.initialSelection()))
	local open = scope:own(core:signal(false))
	local mounted: any = nil
	-- WHAT IS ACTUALLY ON SCREEN, which is a different fact from `selection`.
	-- `selection` is what the player (or a script) ASKED for; this is what they
	-- GOT, and it is nil whenever `mountDemo` threw. See `show` below for the
	-- measurement that made the distinction load-bearing.
	local mountedId: string? = nil
	-- FORWARD-DECLARED. `show` calls `raise`, and `raise` needs the screen, which
	-- needs the rows, which need `show`. A local declared later is not an upvalue
	-- of a function defined earlier — it compiles as a global read and is nil at
	-- call time (this file was the
	-- lesson's next victim).
	local raise: () -> ()
	-- everyone who has to go back on top after a demo mounts, in registration
	-- order. The host's own `onRaise` option runs first and is unchanged.
	local raiseListeners: { (demoHandle: any?) -> () } = {}

	local function disposeMounted()
		mountedId = nil
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

	--[[ show(id) -> DID IT ACTUALLY MOUNT?

		THE RETURN VALUE IS THE POINT, and it is new. `mountDemo` runs under a
		`pcall`, so a fixture module that is not replicated, or a build that
		errors, used to end as a `warn` on a console no scripted caller reads —
		while `selection` had already advanced and `current()` answered the id of a
		demo that is not on screen.

		THAT IS NOT HYPOTHETICAL. Measured live in the showcase place on
		2026-08-15: with one scenario module renamed out from under it,
		`FacetShowcaseAPI.showNext` answered `{"current":"measured-extents"}` and
		`current` agreed — over an EMPTY screen. A caller that takes the id on
		faith then measures whatever surface is still standing (a leftover probe,
		the chrome, nothing at all) and reports a clean bill of health for a demo
		it never looked at; one 32-demo sweep scanned a leftover `hud` surface 21
		times exactly that way (artifacts/hit-expander-overhang/corpus-measurement.md).

		So the answer travels with the request: this returns false, `mountedId`
		stays nil, and `mounted()` below is what the API reports beside `current`. ]]
	local function show(id: string): boolean
		local demo = demo_picker.find(id)
		if demo == nil then
			return false
		end
		disposeMounted()
		local ok, built = pcall(opts.mountDemo, demo)
		if not ok then
			(opts.warn or print)(`[Facet Showcase] '{demo.title}' failed to mount: {tostring(built)}`)
			-- RAISE ANYWAY. The previous demo has already been dismissed, so
			-- returning here left a blank screen with no way back: the chips are
			-- presented BELOW the demo in z-order, and only `raise` puts them back
			-- on top. A failed demo must not take the chrome down with it.
			raise()
			return false
		end
		mounted = built
		mountedId = id
		raise()
		return true
	end

	-- the id of the demo actually on screen, or nil when the last mount failed.
	-- Published on both return shapes below, beside `current`.
	local function mountedDemo(): string?
		return mountedId
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
	-- ELEVEN since the parity round-2 fixtures joined it, which moves the
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
		width = UI.hug(),
		height = UI.hug(),
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
		width = UI.fill(),
		children = buildRows(),
	})

	if opts.composed == true then
		--[[ IN COMPOSED MODE THIS PICKER OWNS NO SURFACE, so "raise" means "ask the
			host to put its chrome back on top" — the demo it just mounted was
			presented after the chrome and therefore draws over it. `show` calls this,
			and `raise` is a forward-declared local: leaving it nil here would make the
			first demo swap a nil call.

			IT IS A LIST NOW, NOT ONE CALLBACK (director round 3, 2026-08-21). The host
			option is the theme picker's; the CHROME needs the same signal for its open
			panel, and it is constructed after this picker, so it cannot be an option.
			A panel that is not raised is a transient the live screen climbs over — the
			z-order the whole arrangement leans on is PRESENT ORDER, and a demo swap
			re-presents the demo. Measured: six swaps put the demo at displayOrder
			11000 against a panel presented at 10400. ]]
		raise = function()
			if opts.onRaise ~= nil then
				opts.onRaise()
			end
			--[[ THE HANDLE RIDES ALONG, and the error does not vanish (review
				MINOR-2). A listener is told WHICH demo handle it is being raised over,
				so a surface that is already above it can decline to spend a present
				(`showcase_chrome`'s raisePanel: the presenter's `displayLayer` counter
				only goes up). `mounted` is nil when the mount failed, which is exactly
				the case where nothing climbed and nothing needs raising.

				`pcall` stays — one broken listener must not take the rest of the
				chrome down with it — but the error is REPORTED now, through the same
				`warn` seam the mount failure two screens up already uses. A protected
				call that drops what it caught is a listener that silently stops
				working. ]]
			local handle = if mounted ~= nil then mounted.handle else nil
			for _, listener in raiseListeners do
				local ok, err = pcall(listener, handle)
				if not ok then
					(opts.warn or print)(`[Facet Showcase] a raise listener failed: {tostring(err)}`)
				end
			end
		end
		return {
			chip = chip,
			iconChip = iconChip,
			list = list,
			rows = rowsStack,
			open = open,
			selection = selection,
			--[[ REGISTER TO GO BACK ON TOP. Returns its own unsubscribe, so a caller
				with a scope owns it the way it owns an observer. Called AFTER the demo
				is mounted and presented, which is the only moment at which "put me
				back on top" means anything. ]]
			watchRaise = function(fn: (demoHandle: any?) -> ()): () -> ()
				table.insert(raiseListeners, fn)
				return function()
					local index = table.find(raiseListeners, fn)
					if index ~= nil then
						table.remove(raiseListeners, index)
					end
				end
			end,
			-- the host mounts the first demo itself once its chrome is up: this
			-- picker no longer owns a surface to raise above it
			show = show,
			current = function()
				return selection:get()
			end,
			mounted = mountedDemo,
			showNext = function(step: number): boolean
				local id = demo_picker.next(selection:get(), step)
				selection:set(id)
				return show(id)
			end,
			dispose = function()
				disposeMounted()
				scope:dispose()
			end,
		}
	end

	-- INSIDE THE RESERVED STRIP, at its left end (the theme chip takes the
	-- right). The negative offset lifts this surface back INTO the strip that
	-- `appChromeInsets` reserved for it.
	local screen = UI.Screen({
		id = "ShowcaseDemos",
		padding = "s",
		children = {
			UI.Anchor({
				id = "Dock",
				width = UI.fill(),
				height = UI.fill(),
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
		mounted = mountedDemo,
		showNext = function(step: number): boolean
			local id = demo_picker.next(selection:get(), step)
			selection:set(id)
			return show(id)
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
