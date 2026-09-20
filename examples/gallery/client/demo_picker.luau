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
	-- the application the picker mounts into and builds its controls from
	app: any,
	env: any,
	composed: boolean?,
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
	local app = opts.app
	local UI, Compose = app.controls, opts.Facet.Compose
	local selection = Compose.cell(demo_picker.initialSelection())
	local open = Compose.cell(false)
	local mounted: any = nil
	local mountedId: string? = nil
	local raise: () -> ()
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
			pcall(app.presenter.dismiss, mounted.handle)
		end
		mounted = nil
	end
	local function show(id: string): boolean
		local demo = demo_picker.find(id)
		if demo == nil then
			return false
		end
		disposeMounted()
		local ok, built = pcall(opts.mountDemo, demo)
		if not ok then
			(opts.warn or print)(`[Facet Showcase] '{demo.title}' failed to mount: {tostring(built)}`)
			raise()
			return false
		end
		mounted = built
		mountedId = id
		raise()
		return true
	end
	local function mountedDemo(): string?
		return mountedId
	end
	-- Selection and open state belong to the host because the picker remounts
	-- when another demo is raised. Each mounted view owns its derived bindings.
	local function Rows(props: { scroll: boolean? })
		local rows: { any } = if props.scroll
			then { gap = "xs", surface = "raised", padding = "s", width = UI.hug(), height = UI.hug() }
			else { gap = "xs", width = UI.fill() }
		for _, demo in demo_picker.DEMOS do
			table.insert(
				rows,
				UI.Button(demo.id)({
					label = demo.title,
					selected = function(use)
						return use(selection) == demo.id
					end,
					onActivate = function()
						local command = demo_picker.choose(selection:peek(), demo.id)
						if command.action == "swap" then
							selection:set(command.selection)
							show(command.selection)
						end
						if opts.onChose then
							opts.onChose()
						else
							open:set(false)
						end
					end,
				})
			)
		end
		return if props.scroll then UI.ScrollView("Rows")(rows) else UI.VStack("Rows")(rows)
	end
	local function pressChip()
		if opts.onChip ~= nil then
			opts.onChip()
		else
			open:set(not open:peek())
		end
	end
	local function Chip(props: { id: string, icon: boolean? })
		local label = Compose.formula(function(use)
			if use(open) then
				return "Close"
			end
			local demo = demo_picker.find(use(selection))
			local title = if demo then demo.title else "—"
			return if opts.composed then title else demo_picker.clip(title, demo_picker.CHIP_LABEL_CHARS)
		end)
		return UI.Button(props.id)({
			label = label,
			surface = "chip",
			shape = if props.icon then "circle" else nil,
			icon = if props.icon then "menu" else nil,
			onActivate = pressChip,
		})
	end
	-- Each piece is a component: the host that places it builds it in its own mount.
	local function chip()
		return Chip({ id = if opts.composed then "DemoToggle" else "Toggle" })
	end
	local function iconChip()
		return Chip({ id = "DemoToggleIcon", icon = true })
	end
	local function list()
		return Rows({ scroll = true })
	end
	local function rowsStack()
		return Rows({})
	end
	if opts.composed == true then
		raise = function()
			if opts.onRaise ~= nil then
				opts.onRaise()
			end
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
			watchRaise = function(fn: (demoHandle: any?) -> ()): () -> ()
				table.insert(raiseListeners, fn)
				return function()
					local index = table.find(raiseListeners, fn)
					if index ~= nil then
						table.remove(raiseListeners, index)
					end
				end
			end,
			show = show,
			current = function()
				return selection:peek()
			end,
			mounted = mountedDemo,
			showNext = function(step: number): boolean
				local id = demo_picker.next(selection:peek(), step)
				selection:set(id)
				return show(id)
			end,
			dispose = disposeMounted,
		}
	end
	local function screen()
		return UI.Screen("ShowcaseDemos")({
			padding = "s",
			UI.Anchor("Dock")({
				width = UI.fill(),
				height = UI.fill(),
				UI.VStack("Panel")({
					anchor = "topLeft",
					offsetY = -demo_picker.BAR_HEIGHT,
					gap = "xs",
					chip(),
					UI.When("List")({
						Compose.show(open, function()
							return UI.When("then")({ list() })
						end),
					}),
				}),
			}),
		})
	end
	local close: (() -> ())? = nil
	local handle: any = nil
	-- A demo presented after the picker covers it, so the picker is presented again.
	function raise()
		if close ~= nil then
			close()
		end
		local nextClose, _, nextHandle = app.mount(screen, { responder = "passive" })
		close, handle = nextClose, nextHandle
		if opts.onRaise ~= nil then
			opts.onRaise()
		end
	end
	raise()
	show(selection:peek())
	return {
		handleOf = function()
			return handle
		end,
		selection = selection,
		open = open,
		current = function()
			return selection:peek()
		end,
		mounted = mountedDemo,
		showNext = function(step: number): boolean
			local id = demo_picker.next(selection:peek(), step)
			selection:set(id)
			return show(id)
		end,
		dispose = function()
			disposeMounted()
			if close ~= nil then
				close()
			end
		end,
	}
end
return demo_picker
