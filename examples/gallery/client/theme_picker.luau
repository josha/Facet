--!strict
-- GALLERY THEME PICKER — an EXAMPLE, deliberately not library code.
--
-- Director review 2026-07-25: "no idea how to swap themes". Every piece of the
-- swap machinery shipped (ADR-0019 §7: install / swap / swapPackage, atomic,
-- no remount) and none of it was reachable without editing a workspace
-- attribute before pressing Play. This is the missing handle: a compact
-- top-right overlay listing Studio Neutral plus every package the place
-- replicated, with that package's themes underneath.
--
-- WHY IT LIVES IN examples/, NOT src/. A theme picker is a piece of a
-- DEVELOPER TOOL, not of a UI framework: a shipping game chooses its theme, it
-- does not hand the player a menu of the five reference packages. Putting it in
-- the library would have made every consumer carry it. It is written entirely
-- through the public surface (`LuauUI.themes`, `theme_controller`, `UI.*`), so
-- a game that DOES want one can copy this file and keep it.
--
-- TWO HALVES:
--   1. the MODEL below is pure — a listing, a selection, and what a selection
--      asks the controller to do. It requires nothing, touches no engine API at
--      module scope, and is what tests/gallery_theme_picker.spec.luau asserts;
--   2. `mount()` builds the overlay and drives the controller. Its proof is the
--      live Studio pass, not a headless test.
--
-- FOCUS. The overlay is presented `responder = "passive"` (ADR-0014): it binds
-- nothing gameplay-contended, it does not move the fixture's focus when it
-- appears, and it becomes first responder only once the player actually engages
-- it. That is the whole reason it can sit over an arbitrary screen.
--
-- RE-THEMING ITSELF. The picker is an ordinary LuauUI screen on the SAME
-- adapter, so the package it installs paints it too — which is exactly the
-- proof you want from it: if the picker still reads after a swap, the swap
-- worked.

local theme_picker = {}

-- set the workspace attribute LuauUI_ThemePicker = false to hide it
theme_picker.ATTRIBUTE = "LuauUI_ThemePicker"

theme_picker.NEUTRAL_ID = "studio-neutral"

-- The STANDALONE strip this picker lifts its own chip into, and it must match
-- demo_picker.BAR_HEIGHT — which is now only the FLOOR of what the showcase
-- reserves, not the whole answer. In the showcase both chips are composed into
-- one surface whose real bottom edge is measured and reserved from
-- (`demo_picker.barReservation`, wired in init.client): this literal was tuned
-- under Studio Neutral and every other reference package's chip outgrows it.
theme_picker.BAR_HEIGHT = 62
-- THE LABEL IS CLIPPED, NOT THE BOX. Two chips share the reserved strip and
-- neither can measure the other: they are separate presented surfaces, so no
-- solver lays them out together. Constraining the BOX (UI.frame maxWidth) was
-- the first try and it is wrong here — a Button label WRAPS inside a narrower
-- box, so the chip grew a second line, left the strip and covered the
-- demo's title. Shortening the TEXT keeps it one line by construction.
-- 14 characters is what fits beside the demo picker's chip on the narrowest
-- phone portrait Roblox reports (320px).
theme_picker.CHIP_LABEL_CHARS = 14
-- where this chip starts, measured from the strip's left edge. The demo
-- picker's chip is 8px in and never wider than 138px at 14 clipped characters,
-- so 154 clears it with a visible gap on every viewport.
theme_picker.CHIP_OFFSET_X = 154

export type Entry = {
	-- the package's own identity slug ("studio-neutral", "fantasy-parchment")
	id: string,
	displayName: string,
	-- the ModuleScript name under ReplicatedStorage.LuauUIThemes (nil for the
	-- built-in neutral package, which is not a module at all)
	moduleName: string?,
	themes: { string },
	package: any,
}

export type Selection = { packageId: string, theme: string }

-- isPickable(module) -> should this theme MODULE appear in the picker?
--
-- The folder the picker discovers holds two populations: the reference packages
-- a director, a designer or an RS-P2 phone pass wants to look at, and the
-- deliberately-degenerate FIXTURES the acceptance scenarios install by name (a
-- package with a bogus asset, one with its icon map removed, a namespaced
-- conformance stub). A module says which it is with `testOnly = true`, and this
-- is the one place that reads it — a picker whose first three rows are broken
-- test packages teaches the wrong thing about the framework.
--
-- Pure and module-shaped (never package-shaped) on purpose: `testOnly` is a
-- property of the FILE, not of the compiled package, so the check has to happen
-- where the ModuleScript is still in hand.
function theme_picker.isPickable(module: any): boolean
	return type(module) == "table" and type(module.build) == "function" and module.testOnly ~= true
end

local function themeNamesOf(pkg: any): { string }
	local out: { string } = {}
	for _, entry in pkg.style.themes do
		table.insert(out, entry.name)
	end
	return out
end

-- listing(packages, neutralPackage) -> ordered entries.
--
-- `packages` is moduleName -> compiled package (the shape the runner already
-- builds from ReplicatedStorage.LuauUIThemes). Studio Neutral is ALWAYS first
-- and always present, because "put it back the way it was" has to be one click
-- and can never depend on a module having replicated. The rest sort by display
-- name so the list is stable between sessions — a picker whose rows move
-- between runs teaches nothing.
--
-- A duplicate package id keeps the FIRST module that claimed it: two modules
-- compiling to one id would otherwise give two rows that fight over the same
-- sheet (they share one, by name — ADR-0019's documented limit).
function theme_picker.listing(packages: { [string]: any }, neutralPackage: any): { Entry }
	local entries: { Entry } = {
		{
			id = theme_picker.NEUTRAL_ID,
			displayName = neutralPackage.identity.displayName,
			moduleName = nil,
			themes = themeNamesOf(neutralPackage),
			package = neutralPackage,
		},
	}
	local seen: { [string]: boolean } = { [theme_picker.NEUTRAL_ID] = true }
	local names: { string } = {}
	for moduleName in packages do
		table.insert(names, moduleName)
	end
	table.sort(names)
	local rest: { Entry } = {}
	for _, moduleName in names do
		local pkg = packages[moduleName]
		if type(pkg) ~= "table" or type(pkg.identity) ~= "table" or seen[pkg.identity.id] then
			continue
		end
		seen[pkg.identity.id] = true
		table.insert(rest, {
			id = pkg.identity.id,
			displayName = pkg.identity.displayName or pkg.identity.id,
			moduleName = moduleName,
			themes = themeNamesOf(pkg),
			package = pkg,
		})
	end
	table.sort(rest, function(a, b)
		return a.displayName < b.displayName
	end)
	for _, entry in rest do
		table.insert(entries, entry)
	end
	return entries
end

-- clip(text, chars) -> text that fits one chip line, with an ellipsis when it
-- had to give something up. Pure, so the spec asserts it.
function theme_picker.clip(text: string, chars: number): string
	if #text <= chars then
		return text
	end
	return string.sub(text, 1, math.max(1, chars - 1)) .. "…"
end

function theme_picker.find(entries: { Entry }, packageId: string): Entry?
	for _, entry in entries do
		if entry.id == packageId then
			return entry
		end
	end
	return nil
end

-- the selection a freshly mounted picker starts on: Studio Neutral, its own
-- default theme. Matches what an un-themed gallery is already showing, so the
-- picker never lies about the state it found.
function theme_picker.initialSelection(entries: { Entry }): Selection
	local neutral = entries[1]
	return { packageId = neutral.id, theme = neutral.package.style.defaultTheme }
end

export type Command = {
	-- "none" | "swapPackage" | "swap" — exactly the controller call to make
	action: string,
	selection: Selection,
	package: any?,
}

-- choosePackage(entries, current, packageId) -> Command.
--
-- Selecting the package that is already installed is a NO-OP, not a redundant
-- swap: `swapPackage` re-materializes a sheet and re-resolves a snapshot, and
-- doing that on every click of the active row would churn the live surface for
-- nothing. Selecting a different one carries the NEW package's own default
-- theme, never the outgoing package's theme name — "Candlelight" means nothing
-- to Glossy Mobile, and asking for it is an error the controller would raise.
function theme_picker.choosePackage(entries: { Entry }, current: Selection, packageId: string): Command
	local entry = theme_picker.find(entries, packageId)
	if entry == nil or packageId == current.packageId then
		return { action = "none", selection = current }
	end
	local theme = entry.package.style.defaultTheme
	return {
		action = "swapPackage",
		selection = { packageId = entry.id, theme = theme },
		package = entry.package,
	}
end

-- chooseTheme(entries, current, themeName) -> Command. A theme the active
-- package does not declare is refused here rather than thrown by the controller.
function theme_picker.chooseTheme(entries: { Entry }, current: Selection, themeName: string): Command
	local entry = theme_picker.find(entries, current.packageId)
	if entry == nil or themeName == current.theme then
		return { action = "none", selection = current }
	end
	for _, name in entry.themes do
		if name == themeName then
			return {
				action = "swap",
				selection = { packageId = current.packageId, theme = themeName },
				package = entry.package,
			}
		end
	end
	return { action = "none", selection = current }
end

-- the themes the second row shows for a selection (empty when the id is unknown)
function theme_picker.themesFor(entries: { Entry }, selection: Selection): { string }
	local entry = theme_picker.find(entries, selection.packageId)
	return if entry ~= nil then entry.themes else {}
end

-- ===== the picker's own spacing and chip box ================================
-- Declared here rather than written inline in `mount` for one reason: they are
-- the values the director judged, so tests/gallery_theme_picker.spec.luau
-- resolves each of them against every reference package's snapshot and asserts
-- the geometry they produce. A number buried in a table five levels down inside
-- `mount` can only ever be proved by looking at a screenshot.
--
-- Every one of them is a METRIC NAME, never a literal, except the grid's own
-- row gap: the picker is re-painted by the package it installs, so its spacing
-- has to move with that package's space ladder the same way its chips do.

-- SECTION GAP (director picker-polish round, 2026-07-26): "clear negative space
-- between the picker grid's bottom row and the Day/Night theme toggle row".
--
-- The picker asks TWO questions — which package, then which of that package's
-- themes — and they were `xs` apart, which is the same order as the gap BETWEEN
-- chips: the theme row read as one more row of the grid. `m` is the smallest
-- step that is unambiguously bigger than the grid's own 4 px row gap under every
-- reference package (classic-desktop 8, sci-fi 14, studio-neutral 16, glossy 18
-- — 2x to 4.5x), so the break reads as a break at desktop density and still
-- scales with a package that wants more air.
theme_picker.SECTION_GAP = "m"
-- inside a section — the title to its grid, one theme chip to the next. Both
-- were already `xs` and neither is what the director was looking at.
theme_picker.ROW_GAP = "xs"
-- between chip COLUMNS. The one deliberate literal: it feeds `minColumnWidth`'s
-- arithmetic, the grid's column count is a director ruling (three columns under
-- classic-desktop, approved 2026-07-26) and a theme-owned column gap would
-- re-column the grid on a swap.
theme_picker.GRID_GAP = 4
-- ...and between chip ROWS, which is a different question with a different
-- answer (director finding 14, 2026-07-26: "more VERTICAL space between rows,
-- especially studio-neutral and compact-pointer").
--
-- A grid's COLUMN pitch is `innerWidth / columns`, so at 544 px and two columns
-- the chips sat 78 px apart horizontally while the literal put their rows 4 px
-- apart — one number doing two jobs whose consequences are not comparable. The
-- solver's `rowGap` splits the axes and never enters the column arithmetic, so
-- the rows can take a spacing-ladder step without touching the ruling.
--
-- `s` is that step: the smallest one that is at least the old literal under
-- every reference package, and one that grows with a denser target — 8 under
-- studio-neutral (2x the literal), 6 under compact-pointer (1.5x), 4 under
-- classic-desktop's tight desktop ladder, 8 under sci-fi, ornate, parchment and
-- pixel-quest, 10 under both glossy packages. `xs` was measured and rejected: it
-- is 2 under classic-desktop and compact-pointer, which would have made the two
-- packages the director named tighter than the literal they were cramped at.
theme_picker.GRID_ROW_GAP = "s"

-- THE CHIP BOX.
--
-- `minMax` with a min and NO max: a FLOOR, NEVER A CEILING (director round 9,
-- found live 2026-07-26). This was `fixed`, and a fixed row cannot hold a
-- wrapped label: under classic-desktop the compact height is 22 px and a
-- two-line chip needs 30, so "Classic Desktop" clipped to "Classic"; under
-- sci-fi the 32 px row could not hold two lines of 14 px at its 1.45 leading, so
-- the label OVERFLOWED its plate into the rows above and below.
theme_picker.CHIP_HEIGHT = table.freeze({ type = "minMax", min = "controlSizes.compact.height" })

-- ...and the padding is what makes that floor the ANSWER rather than a number
-- the content always beats (director picker-polish round, 2026-07-26: "chips
-- read taller than needed, especially at desktop density").
--
-- A Button's default padding is `controls.button.padding` — 12 px on all four
-- sides, and no reference package authors it, so it was the SAME 12 px under a
-- 13 px desktop type ladder as under a 17 px touch one. Vertically that put
-- every chip 24 px above its own line box and the compact-height floor never
-- decided anything: classic-desktop chips solved to 39 px on a package whose
-- whole control ladder tops out at 32.
--
-- Vertical is now `xs` — the package's own smallest step — so the chip's height
-- IS its package's compact control metric for a single line (22 / 32 / 36 / 44
-- under classic-desktop / sci-fi / studio-neutral / glossy-mobile) and a desktop
-- package gets a desktop-density chip while a touch package keeps its 44 px
-- target. Two lines still grow the box, because the floor is a floor.
--
-- HORIZONTAL STAYS THE THEME'S BUTTON PADDING, named rather than copied. The
-- chip's WIDTH is what the round-9 measured-column machinery reasons about
-- (`minColumnWidth = "intrinsic"` + `itemSizing = "uniform"` size every cell
-- from the widest measured chip), and the director's three columns are a ruling:
-- narrowing the chips would re-column the grid.
theme_picker.CHIP_PADDING = table.freeze({
	top = "xs",
	bottom = "xs",
	left = "controls.button.padding",
	right = "controls.button.padding",
})

-- ===== the overlay =========================================================
-- Everything below needs a live LuauUI; nothing above does.

export type MountOpts = {
	LuauUI: any,
	core: any,
	env: any,
	adapter: any,
	presenter: any,
	-- moduleName -> compiled package (the caller resolves ReplicatedStorage)
	packages: { [string]: any },
	-- injected so a caller can pass its own; defaults to LuauUI.client's
	themeController: any,
	-- COLLAPSIBLE (the showcase place). With ten reference packages this panel
	-- is a full-height column on a 360px phone: it covers the screen it is
	-- supposed to be re-theming, which makes it useless exactly where a theme
	-- most needs looking at. Collapsed, it is one chip that says which theme is
	-- live and opens the panel when pressed.
	--
	-- OPT-IN, and default off, because the eight single-example places want the
	-- panel visible the moment they start — there is nothing else on screen
	-- competing with it there, and the director-tuned geometry those places'
	-- specs assert is the expanded panel.
	collapsible: boolean?,
	warn: ((message: string) -> ())?,
}

-- mount(opts) -> { handle, entries, selection, dispose } | nil.
--
-- Returns nil when there is nothing to pick BETWEEN (no replicated packages):
-- a one-row picker is chrome that teaches nothing and still costs a surface.
function theme_picker.mount(opts: MountOpts): any
	local LuauUI = opts.LuauUI
	local UI = LuauUI.UI
	local core = opts.core
	local themes = LuauUI.themes
	local entries = theme_picker.listing(opts.packages, themes.neutralPackage())
	if #entries < 2 then
		return nil
	end

	local warnFn = opts.warn or print
	local scope = core:scope("gallery-theme-picker")
	local selection = scope:own(core:signal(theme_picker.initialSelection(entries)))

	-- ONE controller for this environment (ADR-0019: `themeMetrics` is a single
	-- fact, so a second install is a capability error rather than a silent
	-- clobber). Installed on NEUTRAL, which is what the gallery is already
	-- showing — so mounting the picker changes nothing until it is used.
	local ok, controller = pcall(opts.themeController.install, opts.adapter, themes.neutralPackage(), {
		env = opts.env,
	})
	if not ok then
		warnFn(`[LuauUI Gallery] theme picker: {tostring(controller)}`)
		scope:dispose()
		return nil
	end
	-- SAY SO when the target cannot take native paint. On a fallback target a
	-- package install commits the whole METRIC half live (sizes, spacing, type
	-- all swap) while the palette applies from construction — the documented
	-- ADR-0019 limit. Without this line the picker looks broken: rows resize and
	-- nothing changes colour, and there is nothing on screen explaining why.
	if controller.inspect().fallback then
		warnFn(
			"[LuauUI Gallery] theme picker: this target paints through the explicit-write path, so a swap moves "
				.. "METRICS live but not the palette (ADR-0019). Set the workspace attribute LuauUI_NativeStyle = true "
				.. "before Play to see the full transaction."
		)
	end

	local function apply(command: Command)
		if command.action == "none" then
			return
		end
		local applied, err = pcall(function()
			if command.action == "swapPackage" then
				controller.swapPackage(command.package, command.selection.theme)
			else
				controller.swap(command.selection.theme)
			end
		end)
		if not applied then
			-- a refused swap must leave the PICKER showing what is really
			-- installed, or the next click reasons from a lie
			warnFn(`[LuauUI Gallery] theme picker: {tostring(err)}`)
			return
		end
		selection:set(command.selection)
	end

	-- `onSelect` is a NODE handler, not a path pattern. See the note above the
	-- present call: a surface-level `opts.onActivate` OVERRIDES every node's own
	-- handler on that surface, so routing these rows by parsing their ids meant
	-- the picker's own chip stopped working the moment the two shared a surface.
	local function chip(id: string, label: string, isActive: any, onSelect: () -> ())
		return UI.Button({
			id = id,
			label = label,
			surface = "chip",
			onActivate = onSelect,
			-- THE ACTIVE ROW IS A SELECTION (director finding 12, root-caused live
			-- 2026-07-26). This used to swap `surface` to `"accent"`, and a surface
			-- is a promise about a FILL: under a skinned package the accent fill is
			-- replaced by the package's chrome ART — which `Chrome role — accent`
			-- only MULTIPLIES toward the accent, and a multiply can never lighten —
			-- while the accent's `$OnAccent` label colour was still applied. Under
			-- fantasy-ornate that measured as `GetStyled TextColor3` =
			-- rgb(32, 22, 8) on a dark plum plate: the director's invisible label.
			--
			-- `selected` is what this actually is, and the framework models it end
			-- to end: it routes the node to the package's own `selection` chrome
			-- slot (ornate cut a plate for exactly this), tints it with
			-- `$ChromeTintSelected`, and pairs the label with `$OnSelected`, which
			-- `sheet_model.selectedContentColor` resolves against the theme's
			-- declared selected surface — a declaration the reference-package sweep
			-- now holds to the art's own sampled colour.
			--
			-- Reactive, so a swap repaints the row without rebuilding it — the same
			-- no-remount promise the swap itself makes.
			selected = scope:own(core:memo(function(use)
				return use(isActive) == true
			end)),
			-- the box, and the two director rounds behind it, are documented on
			-- CHIP_HEIGHT / CHIP_PADDING above — where a test can reach them
			height = theme_picker.CHIP_HEIGHT,
			padding = theme_picker.CHIP_PADDING,
		})
	end

	local packageChips: { any } = {}
	for _, entry in entries do
		table.insert(
			packageChips,
			chip(
				`P_{entry.id}`,
				entry.displayName,
				scope:own(core:memo(function(use)
					return use(selection).packageId == entry.id
				end)),
				function()
					apply(theme_picker.choosePackage(entries, selection:get(), entry.id))
				end
			)
		)
	end

	-- The theme row is built for EVERY theme of every package and shown only for
	-- the active one. A `UI.When` per package keeps the rows out of the tree
	-- (and out of the focus order) when they are not the live ones, without the
	-- picker ever rebuilding its own root.
	local themeRows: { any } = {}
	for _, entry in entries do
		local chips: { any } = {}
		for _, name in entry.themes do
			table.insert(
				chips,
				chip(
					`T_{entry.id}_{name}`,
					name,
					scope:own(core:memo(function(use)
						local live = use(selection)
						return live.packageId == entry.id and live.theme == name
					end)),
					function()
						apply(theme_picker.chooseTheme(entries, selection:get(), name))
					end
				)
			)
		end
		table.insert(
			themeRows,
			UI.When({
				id = `Themes_{entry.id}`,
				condition = scope:own(core:memo(function(use)
					return use(selection).packageId == entry.id
				end)),
				thenView = function()
					return UI.HStack({ id = "Row", gap = theme_picker.ROW_GAP, children = chips })
				end,
			})
		)
	end

	-- COLLAPSED MODE (opt-in; see MountOpts.collapsible). `panelOpen` is a plain
	-- signal so the handle toggles it with no remount.
	--
	-- `collapsible` is a BUILD-TIME boolean, not a binding, and the shell it adds
	-- is built in plain Lua rather than with a `When`. That is deliberate: an
	-- always-present wrapper would move the panel from
	-- `/GalleryThemePicker/Dock/Panel` to `.../Dock/Shell/Panel` in every place,
	-- and the eight single-example places' director-tuned geometry assertions
	-- name that path. Un-collapsed, the tree is exactly what it has always been.
	local isCollapsible = opts.collapsible == true
	local panelOpen = scope:own(core:signal(not isCollapsible))
	local handleLabel = scope:own(core:memo(function(use)
		if use(panelOpen) then
			return "Theme ×"
		end
		local entry = theme_picker.find(entries, use(selection).packageId)
		local name = if entry ~= nil then entry.displayName else "—"
		if isCollapsible then
			-- collapsed, the chip is one of two in a shared strip: drop the
			-- "Theme:" prefix and clip the name (see CHIP_LABEL_CHARS)
			return theme_picker.clip(name, theme_picker.CHIP_LABEL_CHARS)
		end
		return `Theme: {name}`
	end))

	-- the expanded panel, unchanged. Hoisted to a local so it can be mounted
	-- either directly (the default) or behind a collapsed handle (the showcase).
	-- THE TWO SECTIONS, hoisted: the composed card rebuilds around them without
	-- a second surface, and the historical panel below is unchanged.
	local panelSections = {
		-- THE FIRST QUESTION, as one group. The caption labels the grid
		-- and belongs to it, so it keeps the tight ROW_GAP while the
		-- SECTION_GAP above separates this whole block from the theme
		-- row — otherwise the title floats equidistant between the panel
		-- edge and the grid and the hierarchy reads as three loose rows.
		-- `fill` on purpose: the group is a grouping, not a size, and the
		-- grid inside it must still be offered the panel's full inner
		-- width (round 9's §9a-iii — a container measures its children in
		-- its OWN definite box).
		UI.VStack({
			id = "Choose",
			width = { type = "fill", weight = 1 },
			gap = theme_picker.ROW_GAP,
			children = {
				UI.Text({
					id = "Title",
					text = "Theme",
					textSize = "caption",
					role = "secondary",
				}),
				UI.Grid({
					id = "Packages",
					-- MEASURED, NOT GUESSED (director round 9). This was a literal 132 px,
					-- which is a guess about a FONT: under classic-desktop's 13 px
					-- BuilderSans it is far too wide, and under sci-fi's 14 px Michroma —
					-- a display face whose glyphs are much wider at the same size — far
					-- too narrow, so the same picker over-wrapped in one theme and
					-- clipped in the other. `"intrinsic"` sizes the column from the WIDEST
					-- CHIP as the solver measures it under the LIVE theme, recomputed on
					-- every solve, so the grid re-columns itself on a swap with nothing
					-- to update.
					minColumnWidth = "intrinsic",
					-- UNIFORM CELLS (director ruling 2026-07-26). With intrinsic columns
					-- the chips are already sized from real measurements, but they are
					-- still RAGGED — ten plates of ten different widths. A picker is a
					-- set of equal choices and reads better as one, so every cell takes
					-- the max measured size. It is the same measurement, max-reduced, so
					-- a wide theme font grows all ten together on the next solve.
					itemSizing = "uniform",
					gap = theme_picker.GRID_GAP,
					-- the ROWS breathe with the package (director finding 14); the
					-- COLUMN gap above stays a literal because it decides the count
					rowGap = theme_picker.GRID_ROW_GAP,
					width = { type = "fill", weight = 1 },
					children = packageChips,
				}),
			},
		}),
		UI.VStack({ id = "Themes", gap = theme_picker.ROW_GAP, children = themeRows }),
	}

	local panel = UI.VStack({
		id = "Panel",
		anchor = if isCollapsible then nil else "topRight",
		surface = "raised",
		padding = "s",
		-- the gap BETWEEN THE TWO QUESTIONS (see SECTION_GAP): which
		-- package, then which of that package's themes
		gap = theme_picker.SECTION_GAP,
		-- FILL, and a GRID for the chips (live-found 2026-07-25, P5). With
		-- the four rich-skinning-v2 reference packages the row became TEN
		-- chips; an HStack ran them off both edges of a 1233px viewport and
		-- put "Studio Neutral" — the one row that has to be reachable,
		-- because it is how you put it back — at x = -37. A picker that
		-- grows with the corpus has to wrap, and on a 360px phone it has to
		-- wrap several times.
		--
		-- `percent` with a CAP is the shape that does both: full width minus a
		-- margin, never wider than 560. On a desktop the picker stays a top-right
		-- card that does not cover the screen it sits over; on a phone it takes
		-- what there is and wraps into more rows.
		width = { type = "percent", fraction = 1, offset = -16, max = 560 },
		children = panelSections,
	})

	-- COMPOSED: ONE NODE IS BOTH THE CARD AND THE SCROLLER.
	--
	-- Two wrong shapes came before this, and both are worth remembering because
	-- the framework allows all three:
	--
	--   1. ScrollView AROUND the card. A scroll container clips to ITSELF, so it
	--      clipped the card: a device capture showed a hard rectangle slicing a
	--      row of theme chips in half while the card's own rounded corner
	--      continued past the cut, with the scrollbar floating outside it.
	--   2. ScrollView INSIDE the card. The clip was right, but now there were two
	--      raised surfaces — a rounded panel inside a rounded panel with a gutter
	--      and no meaning to it.
	--   3. THIS. `ScrollView` takes `surface` and `padding` like any container
	--      (CONTAINER_LAYOUT), so the scroller IS the card. One node, one edge,
	--      one padding, scrollbar inside it by construction, and it cannot clip
	--      its own corners because they are its own.
	--
	-- ...AND IT IS SIZED `hug`, ON BOTH AXES (director round 10, found live
	-- 2026-07-26 on a phone). `fill` was the fourth wrong shape: it made the card
	-- as big as the space rather than as big as the list, so under Studio Neutral
	-- the ten themes ended less than halfway down a plate that ran to the bottom
	-- of the screen, and the same card was the full width of the phone with the
	-- rows inset inside it. Under Fantasy Ornate — taller rows, a 30px carved
	-- frame — the OPPOSITE half showed: the list ran off the bottom of the
	-- viewport and did not scroll, because a `fill` box is by definition never
	-- smaller than its content, so the overflow that turns scrolling on never
	-- registered.
	--
	-- `hug` is one declaration for both: the content size, capped at what the
	-- parent offered. Short list -> a card that stops at the last row. Long list
	-- -> the cap bites, content exceeds the box, and the ScrollView scrolls.
	if opts.composed == true then
		panel = UI.ScrollView({
			id = "Panel",
			surface = "raised",
			padding = "s",
			gap = theme_picker.SECTION_GAP,
			width = { type = "hug" },
			height = { type = "hug" },
			children = panelSections,
		})
	end

	-- THE CHIP. One blueprint, used by the collapsed shell here and — when the
	-- host composes the chrome itself — handed straight over so the host's own
	-- solver lays it out beside the demo picker's.
	-- DISTINCT ID WHEN COMPOSED. Both pickers' chips were called "Toggle", which
	-- was fine while they lived in separate surfaces and is a duplicate-child-id
	-- error the moment one HStack holds them both. The historical id survives on
	-- the path the single-example places assert.
	local chip = UI.Button({
		id = if opts.composed == true then "ThemeToggle" else "Toggle",
		label = handleLabel,
		surface = "chip",
		height = theme_picker.CHIP_HEIGHT,
		padding = theme_picker.CHIP_PADDING,
		onActivate = function()
			panelOpen:set(not panelOpen:get())
		end,
	})

	-- un-collapsed: the panel IS the dock's child, at its historical path.
	-- collapsed: a shell holds a handle plus the panel behind a `When`.
	local dockChild = if isCollapsible
		then UI.VStack({
			id = "Shell",
			anchor = "topLeft",
			offsetX = theme_picker.CHIP_OFFSET_X,
			-- lifted back INTO the strip the showcase reserved through
			-- coreSafeInsets, so the chip sits beside the demo picker's rather
			-- than over the demo. Collapsed mode is only used there.
			offsetY = -theme_picker.BAR_HEIGHT,
			gap = theme_picker.ROW_GAP,
			alignH = "start",
			children = {
				chip,
				UI.When({
					id = "PanelWhen",
					condition = panelOpen,
					thenView = function()
						return panel
					end,
				}),
			},
		})
		else panel

	local screen = UI.Screen({
		id = "GalleryThemePicker",
		padding = "s",
		children = {
			UI.Anchor({
				id = "Dock",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					dockChild,
				},
			}),
		},
	})

	-- COMPOSED: the host is building ONE chrome surface and wants the pieces, not
	-- a presented overlay. Two chips in two surfaces cannot measure each other,
	-- so keeping them apart meant a hard-coded offset — and on a real iPhone the
	-- text is wider than the offset assumed and the chips overlapped. Handing the
	-- pieces to one solver makes overlap structurally impossible.
	if opts.composed == true then
		return {
			chip = chip,
			panel = panel,
			open = panelOpen,
			-- THE SAME PATH A TAP TAKES, exposed as the scriptable entry point.
			--
			-- This slot used to read `dispatch = dispatch`, and `dispatch` had not
			-- existed since behaviour moved onto the nodes — a deleted local whose
			-- reference survived, which Luau reads as a nil GLOBAL rather than
			-- failing (docs/lessons/later-locals-are-not-upvalues.md is the same
			-- family). So the composed picker shipped `dispatch = nil`, and the
			-- showcase's `LuauUIShowcaseAPI.pickTheme` errored with "attempt to call
			-- a nil value" for every caller: there was NO working route to switch
			-- theme from a script, which is exactly the kind of thing an agent
			-- driving the place needs and cannot get from a tap (XP-B3).
			--
			-- `pickPackage` routes through `apply`, the identical call the chips'
			-- own `onActivate` makes, so driving it exercises the real command path
			-- instead of a parallel one that can rot on its own. It still does not
			-- prove the BUTTON works — only a real tap does that.
			pickPackage = function(packageId: string): boolean
				local command = theme_picker.choosePackage(entries, selection:get(), packageId)
				if command.action == "none" then
					return false
				end
				apply(command)
				return true
			end,
			entries = entries,
			selection = selection,
			controller = controller,
			dispose = function()
				controller.uninstall()
				scope:dispose()
			end,
		}
	end

	-- NO SURFACE-LEVEL `onActivate`, DELIBERATELY.
	--
	-- `presenter.dispatchActivate` is explicit about this: "when opts.onActivate
	-- IS present it wins outright (override)" — it runs and RETURNS, so no node
	-- on that surface ever gets its own `props.onActivate`. This picker used to
	-- route its rows that way, by matching `P_`/`T_` prefixes out of the path,
	-- and the cost only became visible once the host composed both pickers into
	-- one surface: the override swallowed every activation, so the theme chip and
	-- the demo chip both went dead while the rows kept working. Before that, a
	-- re-present that DROPPED the override had the mirror-image effect — chips
	-- worked, rows dead. Two bugs, one cause, and they trade places.
	--
	-- Node handlers have neither failure mode: they cannot be dropped by a
	-- re-present and they cannot be swallowed by a sibling surface's router.
	-- `dispatch` survives only as a scriptable entry point (the showcase's
	-- pointer-free drive API calls it); nothing on screen depends on it.
	local presentOpts = {
		-- PASSIVE (ADR-0014): binds nothing gameplay-contended and never moves
		-- the fixture's focus on appearance. It engages only when used.
		responder = "passive",
	}
	local handle = opts.presenter.present(screen, presentOpts)

	return {
		-- A FUNCTION, NOT A FIELD. `raise` re-presents this surface and rebinds
		-- the local, so a snapshot taken here goes stale the first time the host
		-- raises the picker — and it points at a DISMISSED handle, which is worse
		-- than nil because it still looks usable.
		handleOf = function()
			return handle
		end,
		-- z-order is present order (presenter §2.2). A host that mounts other
		-- surfaces after this one re-presents it to put it back on top.
		raise = function()
			opts.presenter.dismiss(handle)
			handle = opts.presenter.present(screen, presentOpts)
		end,
		entries = entries,
		selection = selection,
		controller = controller,
		dispose = function()
			opts.presenter.dismiss(handle)
			controller.uninstall()
			scope:dispose()
		end,
	}
end

return theme_picker
