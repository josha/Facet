--!strict
-- THE THEME LEDGER — what turning the theme axis on found, on 2026-08-14.
--
-- Read `tests/overflow_sweep.spec.luau`'s "THE THEME AXIS" and "THE THEME LEDGER"
-- sections first: they say what the axis sweeps, what it costs, and what these
-- rows are under. In one sentence: this is a TO-DO LIST WITH A MEASUREMENT ON
-- EVERY LINE, not a list of things that are allowed.
--
-- It exists as its own file for one reason — it is data, it is long, and it can
-- only ever shrink. The instrument that reads it stays readable.
--
-- Each row:
--   surface   the swept surface's name (a scenario, an example, a proof)
--   variant   the fixture's step value where one exists, "-" otherwise
--   node      the NORMALIZED path (see normalizePath in the spec). A `*` INSIDE a
--             segment is a wildcard covering a run of hand-named siblings that
--             carry one defect; a segment that IS `[*]` or `*` is literal.
--   sig       the finding's derived class (numbers and quoted names blanked)
--   px        the LARGEST px figure this finding carried anywhere in the themed
--             tier on 2026-08-14. A finding above it fails: the defect got worse.
--   since     the smallest preferredTextOffset it was measured at. A finding at a
--             smaller preference fails.
--   packages  every package that reports it. A finding under a package not named
--             here fails.
--   kind      the triage class, the same vocabulary the spec's WAIVERS use, plus
--             the one the theme axis adds:
--               cascade-floor — the degrade cascade ran to its floor and the box
--                 CROPPED the residual (ruling 1). Distinct from `row-cannot-shrink`
--                 precisely because that class is repairable by authoring and this
--                 one is not: the finding carries the solver's own "every shrinkable
--                 child is already at its floor" suffix.
--               theme-inset-yield — a control smaller than the theme it wears.
--                 The renderer already gave the inset back and the content still
--                 draws, so it is the mildest row here — but it is the direct
--                 signal of `docs/lessons/a-fixed-box-cannot-hold-a-themes-frame.md`
--                 ("a control's fixed dimension is a promise it cannot keep under
--                 a theme it has not seen"), which is why it is recorded rather
--                 than filtered.
--
-- TWO ROWS ARE ALREADY GONE, and they are why this file exists at all: O-23
-- (`progress_ring`'s spinner row, 40px past its box under both Glossy packages at
-- the DEFAULT preference) and O-25 (`02_playlist_table`'s cells, 4px outside
-- every cell under Pixel Quest). Both were framework defects no consumer could
-- reach. Deleting a row from here is what fixing one looks like.

local theme_ledger = {}

export type Row = {
	surface: string,
	variant: string,
	node: string,
	sig: string,
	px: number,
	since: number,
	packages: string,
	kind: string,
}

theme_ledger.ROWS = {
	{
		-- THE 2026-08-27 ROWS (task THEME, ADR-0059). `chrome_slots.spendInset` used to
		-- spend a package's carved border whenever ANY pixels remained; it now asks whether
		-- the node's own LINE BOX still fits, which is what stopped a 16px glyph being drawn
		-- into a 4x4 box (director item 6). Nothing below is a new defect — every one is a
		-- control that was already too small for the frame its package asked it to wear, and
		-- every one is REPAIRED (the reservation comes back and the content draws). What
		-- changed is that the framework now says so, which is the whole point of the change,
		-- and these rows are where it says it until the packages re-spec those rungs.
		-- THE ROUND-BUTTON FAMILY, and the director's own item 6: a `shape = "circle"` HUD
		-- chip is sized from `controlSizes.<rung>.height` and the smallest rung of every
		-- ornate package is narrower than that package's own frame — 22px against 16 under
		-- compact-pointer, 36 against 16 under pixel-quest. Three sibling discs, one
		-- construction, one row.
		surface = "hud",
		variant = "-",
		node = "/HudScreen/Hud/Rounds/RoundStrip/R*",
		sig = "the 'X' chrome contentInsets could not be",
		px = 52,
		since = 0,
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		-- ...and the bottom-right cluster's disc, the same construction on the `regular` rung.
		surface = "hud",
		variant = "-",
		node = "/HudScreen/Hud/Actions/A1r",
		sig = "the 'X' chrome contentInsets could not be",
		px = 46,
		since = 0,
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		-- THE ON-SCREEN KEYBOARD, 28 keys and one construction. At +14 a key's line box
		-- outgrows what its package's frame leaves; the frame comes back and the letter draws.
		-- The same three rows already carry this fixture's `collapsed-box` findings.
		surface = "05_word_game",
		variant = "-",
		node = "/Wordle/page/col/kb/kbrow*/key_*",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 14,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch",
		kind = "theme-inset-yield",
	},
	{
		-- a BADGE is the smallest control in the library and the one an ornate seal fits
		-- least; four tiles, one construction. THE NODE GAINED A SEGMENT (task
		-- THEME2, director item: "the badge has no padding and overlaps the edge
		-- of the control"): `badgedTile` used to align the "Count" Text directly
		-- in the tile's own overlay ZStack; it now wraps it in a "BadgeCorner"
		-- ZStack carrying the corner-clearing inset, so the path is one segment
		-- longer (`globMatches` requires an EQUAL segment count, so the old
		-- pattern stopped matching outright rather than matching wrong). The
		-- finding itself (the badge's OWN `badge`-slot seal art not affording its
		-- 10px contentInset in a 28px box) is unrelated to that fix and unmoved.
		surface = "adaptive_controls",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Hud/Tiles/t*+overlay/t*BadgeCorner/t*Badge",
		sig = "the 'X' chrome contentInsets could not be",
		px = 28,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment",
		kind = "theme-inset-yield",
	},
	{
		-- the same four badges reached through the theme-authoring surface; see
		-- the row above for the added `BadgeCorner` path segment.
		surface = "theme_authoring",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Hud/Tiles/t*+overlay/t*BadgeCorner/t*Badge",
		sig = "the 'X' chrome contentInsets could not be",
		px = 28,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment",
		kind = "theme-inset-yield",
	},
	{
		-- THE TOP BAR'S FOUR ICON BUTTONS, one row each and all the same story: a 44px
		-- target wearing a frame its package sized for a labelled button.
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/TopBar/BellZ/Bell",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/TopBar/Profile",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/TopBar/Refresh",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/TopBar/SearchSlot/IconForm",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		-- ...and the unread count's seal, the badge story again.
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/TopBar/BellZ/BadgeWhen/then/BadgeBubble/Count",
		sig = "the 'X' chrome contentInsets could not be",
		px = 20,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment",
		kind = "theme-inset-yield",
	},
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Nav/Content/Tab-home/then/HomeBody/FeedPage/FriendsRow/AddTile/BadgeWhen/then/BadgeBubble/Count",
		sig = "the 'X' chrome contentInsets could not be",
		px = 20,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment",
		kind = "theme-inset-yield",
	},
	{
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Nav/Content/Tab-home/then/HomeBody/FeedPage/FriendsRow/AddTile/B",
		sig = "the 'X' chrome contentInsets could not be",
		px = 56,
		since = 14,
		packages = "fantasy-ornate,glossy-touch",
		kind = "theme-inset-yield",
	},
	{
		-- the section headers' `See all` link-buttons, one construction per section.
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Nav/Content/Tab-home/then/HomeBody/FeedPage/Sections/[*]/Body/Header/SeeAll",
		sig = "the 'X' chrome contentInsets could not be",
		px = 52,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		-- NOT a yield: the feed page's own content box on a short landscape. It appeared
		-- 2026-08-27 when Pixel Quest's frame narrowed (ADR-0059 Decision 5) and the page
		-- re-flowed; the neutral pass already waives this page's parent `HomeBody` for the
		-- same short-landscape reason (see the spec's own waiver list).
		--
		-- `compact-pointer` joined 2026-08-28 (task SCROLL2, fa7233a): the director's
		-- ruling drops the "auto" scroll reserve to zero, so this page's own scroll host
		-- measures 8px wider under a touch-derived package at +14 — a SMALLER collapse
		-- (2px, well inside this row's existing 5px ceiling) under a package this row did
		-- not previously need to name.
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Nav/Content/Tab-home/then/HomeBody/FeedPage",
		sig = "content box collapses to Npx on y: padding N",
		px = 5,
		since = 0,
		packages = "compact-pointer,pixel-quest",
		kind = "collapsed-box",
	},
	{
		-- the catalog's filter disc and the preview's two history discs — icon buttons on
		-- the 44px target floor, the same story as p4_foyer's top bar.
		surface = "p5_wardrobe",
		variant = "-",
		node = "/Wardrobe/BoutiqueWhen/then/Body/Catalog/CatalogCol/CategoryRow/Filter",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p5_wardrobe",
		variant = "-",
		node = "/Wardrobe/BoutiqueWhen/then/Body/Preview/PreviewCol/PaneZ/Controls/History/Undo",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p5_wardrobe",
		variant = "-",
		node = "/Wardrobe/BoutiqueWhen/then/Body/Preview/PreviewCol/PaneZ/Controls/History/Redo",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "row_actions",
		variant = "vlist",
		node = "/MailActions/VListWhen/then/VListPane",
		sig = "content overflows this vstack by Npx on the",
		px = 324,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "scroll_host",
		variant = "-",
		node = "/ScrollHost",
		sig = "content overflows this vstack by Npx on the",
		px = 190,
		since = 14,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Detail/Lane/Body/then/Host/Sections/CartWhen/then/CartSection/Cart/Page/CardGrid/Sky/Skyglow/Axis",
		sig = "content overflows this hstack by Npx on the",
		px = 183,
		-- RE-RECORDED 2026-08-27 (task THEME): +14 -> +0. Pixel Quest's `control`
		-- recipe now reserves the two design pixels its art carves rather than the
		-- four its nine-slice border needs (ADR-0059 Decision 5), so this row's
		-- controls are 8px narrower per side and the axis caption is 3px wide of
		-- fitting at the DEFAULT preference where it used to fit until +14.
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "row-cannot-shrink",
	},
	{
		surface = "authoring",
		variant = "-",
		node = "/AuthoringScreen",
		sig = "content overflows this vstack by Npx on the",
		px = 169,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "sponsor_drop",
		variant = "-",
		node = "/DropLab/Main",
		sig = "content overflows this vstack by Npx on the",
		px = 161,
		since = 0,
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "sponsor_list",
		variant = "-",
		node = "/ListLab/Body/Rows/Canvas/W/[*]/Row/Card",
		sig = "newVirtualList 'X' declares itemExtent = N,",
		px = 160,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "lying-itemExtent",
	},
	{
		--[[ THE PAGE'S OWN CHROME IS TALLER THAN A 200px BOX, which is what is left
			of a 640x320 landscape phone under the showcase's 120px picker strip.
			Measured 2026-08-14 with both of this fixture's real defects fixed (the
			extents now derive from the live text facts and the window is the solved
			pane, so neither the rows nor the list contribute a single finding): the
			title, the WRAPPING control row and the two-line status alone measure 268px
			there at +14 and 216px under Pixel Quest at the DEFAULT preference. The
			control row is the bulk of it — `UI.Toggle` is a full-width ROW control, so
			it takes a wrap line to itself and the four size chips take one or two more.

			IT IS NOT REPAIRABLE BY GIVING THE LIST LESS ROOM, which is what the first
			version did (`viewportHeight - 210`): the list is already at zero on every
			cell this row covers. Repairing it means the fixture carrying less chrome on
			a short screen — a compact control row, or the title dropping — which is a
			design change to a demo whose chrome IS its subject, so it is recorded with
			the measurement rather than tuned away. ]]
		--[[ THE SAME CLASS AS `/VariableExtents` BELOW, one surface over, and it is
			here for the same reason: a page that cannot delegate its scrolling has to
			fit its own chrome above the list, and at the Largest preference on a
			320x640 phone under a package that carves real chrome, it does not.

			WHAT SEPARATES IT FROM ITS NEIGHBOUR IS THE `since`. `/VariableExtents` is
			recorded from +0 — it overflows at the DEFAULT preference. This surface is
			clean at +0, +4 and +10 on every package, and only fails at +14, because
			four rounds of measured trimming went in before this row was written: the
			auto Edit/Done toolbar row (owned `editing` took it back), the header
			band's `minMax` floor (77 findings, all of them that band — the fixture is
			headerless), a second row of buttons (five long labels made it 96px and put
			the page 20px over at the DEFAULT preference) and the page title. Each is
			recorded in the WAIVERS entry's `where`.

			IT IS NOT REPAIRABLE BY GIVING THE LIST LESS ROOM: the list is already at
			zero on every cell this row covers, and a floor on it would paint over the
			neighbour instead — the mistake `/VariableExtents` records having made. ]]
		surface = "table_virtualized",
		variant = "-",
		node = "/TableVirtualized",
		sig = "content overflows this vstack by Npx on the",
		px = 171,
		since = 14,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "variable_extents",
		variant = "-",
		node = "/VariableExtents",
		sig = "content overflows this vstack by Npx on the",
		px = 157,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "keyboard_navigation",
		variant = "-",
		node = "/KbdNav/Body/Actions",
		sig = "content overflows this hstack by Npx on the",
		px = 145,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "row-cannot-shrink",
	},
	-- `async_images` held a `page-not-scrollable` row here (/AsyncImages, 143px,
	-- since = 14, every package). DELETED with its neutral waiver when the fixture
	-- entered the demo picker (round-3 O-30) and its page became a ScrollView: a row
	-- that no longer fires is a fixed defect, and deleting the line is the point of
	-- the ledger.
	{
		surface = "adaptive_controls",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Settings/Volume",
		sig = "content overflows this hstack by Npx on the",
		px = 138,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "row-cannot-shrink",
	},
	{
		surface = "theme_authoring",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Settings/Volume",
		sig = "content overflows this hstack by Npx on the",
		px = 138,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "row-cannot-shrink",
	},
	{
		surface = "perf_capture",
		variant = "-",
		node = "/PerfCapture/Actions",
		sig = "content overflows this hstack by Npx on the",
		px = 126,
		since = 14,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "row-cannot-shrink",
	},
	{
		surface = "adaptive_controls",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Hud/Toolbar",
		sig = "content overflows this hstack by Npx on the",
		px = 121,
		since = 0,
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "row-cannot-shrink",
	},
	{
		surface = "theme_authoring",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Hud/Toolbar",
		sig = "content overflows this hstack by Npx on the",
		px = 121,
		since = 0,
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "row-cannot-shrink",
	},
	{
		surface = "drag_session",
		variant = "-",
		node = "/DragLab",
		sig = "content overflows this vstack by Npx on the",
		px = 117,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "row_actions",
		variant = "table",
		node = "/MailActions/TableWhen/then/TablePane",
		sig = "content overflows this vstack by Npx on the",
		px = 102,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "sponsor_drop",
		variant = "-",
		node = "/DropLab/Main/ListZone/Rows",
		sig = "this child overflows its zstack by NxNpx and",
		px = 102,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "layer-overlap",
	},
	{
		surface = "adaptive_controls",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Settings/Brightness",
		sig = "content overflows this hstack by Npx on the",
		px = 98,
		since = 14,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "row-cannot-shrink",
	},
	{
		surface = "theme_authoring",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Settings/Brightness",
		sig = "content overflows this hstack by Npx on the",
		px = 98,
		since = 14,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "row-cannot-shrink",
	},
	{
		surface = "virtual_list_native",
		variant = "-",
		node = "/VLNative",
		sig = "content overflows this vstack by Npx on the",
		px = 97,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "sponsor_toast",
		variant = "-",
		node = "/ToastLab/Stage/Beneath",
		sig = "this child overflows its zstack by NxNpx and",
		px = 94,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "layer-overlap",
	},
	{
		-- RE-RECORDED 2026-08-16 (navigation-and-menus D5): the section nav became
		-- one `newTabView`, so this node moved out of a hand-built `ContentHost`
		-- and the ceiling moved 86 -> 96px with it. Same defect, same cell — a
		-- 320px-tall landscape at the largest preference under a heavy package.
		-- `compact-pointer` joins the list because the construct's band is the
		-- tap-target floor on every package rather than whatever an icon-only row
		-- happened to measure.
		surface = "p4_foyer",
		variant = "-",
		node = "/Foyer/Root/Nav/Content/Tab-home/then/HomeBody",
		sig = "content overflows this vstack by Npx on the",
		px = 96,
		since = 0,
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	-- CLOSED 2026-08-28 (task SCROLL2, fa7233a). This row recorded `/Foyer/Root/Nav`
	-- (the TabView root) on the three heaviest packages overflowing 3-4px at 320px-tall
	-- landscape @+14 — the same "nothing left to give" cell its child `HomeBody` above
	-- is waived for. The director's zero-auto-reserve ruling hands this touch-derived
	-- cell's scroll host 8px more measured width, which absorbs the shortfall; the
	-- finding no longer fires anywhere in the themed passes.
	{
		surface = "flow_wrap",
		variant = "-",
		node = "/FlowWrap/Page/AlignBox",
		sig = "the wrapped lines overflow this hwrap by Npx",
		px = 82,
		since = 14,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "wrap-clamp",
	},
	{
		surface = "sponsor_motion",
		variant = "-",
		node = "/MotionLab/Main/StageColumn/WashRow/WashLabel",
		sig = "this child overflows its zstack by NxNpx and",
		px = 78,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "layer-overlap",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row*",
		sig = "content overflows this hstack by Npx on the",
		px = 74,
		since = 14,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "row-cannot-shrink",
	},
	{
		-- RE-PINNED 2026-08-28 (task SCROLL2, fa7233a): 71 -> 72. `Page` is a
		-- touch-derived auto-policy ScrollView; the director's zero-auto-reserve
		-- ruling hands it 8px more measured width, which redistributes through the
		-- Chips hwrap and lands this fixed 36+36 padding chrome on a 72px box instead
		-- of 71 — still fully collapsed (0px of content) either way, just a 1px wider
		-- box hitting the same ceiling.
		surface = "with_animation",
		variant = "-",
		node = "/MotionDemo/Page/Stage/Decorative/Chips/Order/[*]/Chip",
		sig = "content box collapses to Npx on x: padding N",
		px = 72,
		since = 0,
		packages = "fantasy-ornate",
		kind = "collapsed-box",
	},
	{
		surface = "perf_capture",
		variant = "-",
		node = "/PerfCapture",
		sig = "content overflows this vstack by Npx on the",
		px = 67,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "authoring",
		variant = "-",
		node = "/AuthoringScreen/ValidGrid/g*",
		sig = "the 'X' chrome contentInsets could not be",
		px = 60,
		since = 0,
		packages = "fantasy-ornate,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "sponsor_avatars",
		variant = "-",
		node = "/AvatarLab/Avatars/Set/[*]/Avatar/Fallback",
		sig = "the 'X' chrome contentInsets could not be",
		px = 60,
		since = 0,
		packages = "fantasy-ornate,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "with_animation",
		variant = "-",
		node = "/MotionDemo/Page/Stage/Decorative/Card",
		sig = "the 'X' chrome contentInsets could not be",
		px = 60,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	-- THE TWO 06_tile_game `theme-inset-yield` ROWS ARE GONE (2026-08-29, the
	-- crossword rewrite), and they were deleted rather than re-recorded because
	-- the defect they described is fixed rather than moved.
	--
	-- Both were one cause: a `{ type = "fixed", px = "controlSizes.large.height" }`
	-- square. A fixed box cannot afford a package's chrome inset, so Compact
	-- Pointer and Pixel Quest each yielded theirs on all 25 board cells and all 7
	-- rack tiles. The rewrite sizes both from
	-- `{ type = "minMax", min = "targetSizes.minimum" }` — a FLOOR the square can
	-- grow past, which is the answer docs/lessons/facet-fixed-px-heights.md names
	-- — so the inset is affordable and nothing yields. The board cell is also no
	-- longer a Button at all (it is a plate plus a `plain` hit layer), so it
	-- classifies into no chrome slot to begin with.
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Detail/Lane/Body/then/Host/Sections/CartWhen/then/CartSection/Cart/Page/CardGrid/Recent/RecentBrews/HeroTiles/Tiles/TileGrid/TileRows/[*]/*/Body",
		sig = "this child overflows its zstack by NxNpx and",
		px = 56,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "layer-overlap",
	},
	{
		surface = "sponsor_celebration",
		variant = "-",
		node = "/CelebrationLab/Stage",
		sig = "content box collapses to Npx on y: padding N",
		px = 53,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest",
		kind = "collapsed-box",
	},
	{
		surface = "adaptive_controls",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Hud/CompactRow/Cmp*",
		sig = "the 'X' chrome contentInsets could not be",
		px = 52,
		since = 0,
		-- WIDENED by wave TEN-FOOT (ADAPT-8, 2026-08-20): the 52px demo button is DELIBERATELY narrower than its label, and at ten-foot the scaled button padding (12 -> 18, twice) plus Compact Pointer's own 16px frame comes to exactly 52 — so two more packages now notice a yield the other three already reported. The art itself does not scale (see snapshot.densityClassOf), so this is the padding half, and the fixture keeps its literal on purpose: spending targetSizes.minimum here was measured WORSE (fantasy-parchment stopped fitting on a compact phone).
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "theme_authoring",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Hud/CompactRow/Cmp*",
		sig = "the 'X' chrome contentInsets could not be",
		px = 52,
		since = 0,
		-- WIDENED by wave TEN-FOOT (ADAPT-8, 2026-08-20): the 52px demo button is DELIBERATELY narrower than its label, and at ten-foot the scaled button padding (12 -> 18, twice) plus Compact Pointer's own 16px frame comes to exactly 52 — so two more packages now notice a yield the other three already reported. The art itself does not scale (see snapshot.densityClassOf), so this is the padding half, and the fixture keeps its literal on purpose: spending targetSizes.minimum here was measured WORSE (fantasy-parchment stopped fitting on a compact phone).
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "sponsor_drop",
		variant = "-",
		node = "/DropLab/Main/Hand/Card*",
		sig = "content box collapses to Npx on y: padding N",
		px = 48,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "collapsed-box",
	},
	{
		surface = "sponsor_drop",
		variant = "-",
		node = "/DropLab/Main/ListZone/Rows/Canvas/W/[*]/Row/Card",
		sig = "newVirtualList 'X' declares itemExtent = N,",
		-- RE-PINNED by wave TEN-FOOT (ADAPT-8, 2026-08-20): the hosted row's content scales with the ladder (66px slot, 72px content under Fantasy Ornate) while the art frame it must clear does not — the same 6px shortfall the near pass records at 48.
		px = 72,
		since = 0,
		packages = "fantasy-ornate,glossy-touch,pixel-quest",
		kind = "lying-itemExtent",
	},
	{
		surface = "sponsor_avatars",
		variant = "-",
		node = "/AvatarLab",
		sig = "content overflows this vstack by Npx on the",
		px = 47,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "sponsor_drop",
		variant = "-",
		node = "/DropLab/Main/Hand",
		sig = "content box collapses to Npx on y: padding N",
		px = 47,
		since = 14,
		packages = "fantasy-ornate",
		kind = "collapsed-box",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Celebration/CelebrationFull/then/CelebrationPiece/CelebrationPieceLabel",
		sig = "this child overflows its zstack by NxNpx and",
		px = 45,
		since = 0,
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "layer-overlap",
	},
	{
		surface = "scroll_host",
		variant = "-",
		node = "/ScrollHost/Strip",
		sig = "content box collapses to Npx on y: padding N",
		px = 45,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,scifi-hud",
		kind = "collapsed-box",
	},
	{
		surface = "p1_glade",
		variant = "-",
		-- RE-RECORDED by framework-gaps-phase2 §6 (2026-08-22): the shell is
		-- `newTabView` now, so a section body is a TAB's content rather than one of
		-- four `When`s in a ZStack. Same node, same finding, same box — the path is
		-- the only thing that moved.
		node = "/Glade/Nav/Content/Tab-glades/then/Pane_glades/Panes/Section/Body_glades/GladesPage/Cards/Glades/[*]/*/Fav_*",
		sig = "the 'X' chrome contentInsets could not be",
		-- RE-PINNED by wave TEN-FOOT (ADAPT-8, 2026-08-20): the star already spends `targetSizes.minimum`, so its box follows the ladder to 68 under Pixel Quest. Same finding, larger box, SMALLER shortfall (20px of room for a 32px frame at near, 28px at distance).
		px = 68,
		since = 0,
		-- ...and fantasy-ornate joined 2026-08-27 (task THEME, ADR-0059): `spendInset`'s
		-- affordability test is now the node's own line box, so a control this package
		-- had always been too small for finally says so.
		packages = "fantasy-ornate,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Sidebar/Rail/Body/then/Icons/Rows/GuildCard",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Sidebar/Rail/Body/then/Icons/Rows/Plaza_emberfall",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		-- ...and fantasy-ornate joined 2026-08-27 (task THEME, ADR-0059): `spendInset`'s
		-- affordability test is now the node's own line box, so a control this package
		-- had always been too small for finally says so.
		packages = "fantasy-ornate,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Sidebar/Rail/Body/then/Icons/Rows/Plaza_gullsgate",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		-- ...and fantasy-ornate joined 2026-08-27 (task THEME, ADR-0059): `spendInset`'s
		-- affordability test is now the node's own line box, so a control this package
		-- had always been too small for finally says so.
		packages = "fantasy-ornate,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Sidebar/Rail/Body/then/Icons/Rows/Plaza_willowmere",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		-- ...and fantasy-ornate joined 2026-08-27 (task THEME, ADR-0059): `spendInset`'s
		-- affordability test is now the node's own line box, so a control this package
		-- had always been too small for finally says so.
		packages = "fantasy-ornate,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Sidebar/Rail/Body/then/Icons/Rows/Row_brews",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		-- ...and fantasy-ornate joined 2026-08-27 (task THEME, ADR-0059): `spendInset`'s
		-- affordability test is now the node's own line box, so a control this package
		-- had always been too small for finally says so.
		packages = "fantasy-ornate,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Sidebar/Rail/Body/then/Icons/Rows/Row_cart",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		-- ...and fantasy-ornate joined 2026-08-27 (task THEME, ADR-0059): `spendInset`'s
		-- affordability test is now the node's own line box, so a control this package
		-- had always been too small for finally says so.
		packages = "fantasy-ornate,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Sidebar/Rail/Body/then/Icons/Rows/Row_chatter",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		-- ...and fantasy-ornate joined 2026-08-27 (task THEME, ADR-0059): `spendInset`'s
		-- affordability test is now the node's own line box, so a control this package
		-- had always been too small for finally says so.
		packages = "fantasy-ornate,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Sidebar/Rail/Body/then/Icons/Rows/Row_ledger",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		-- ...and fantasy-ornate joined 2026-08-27 (task THEME, ADR-0059): `spendInset`'s
		-- affordability test is now the node's own line box, so a control this package
		-- had always been too small for finally says so.
		packages = "fantasy-ornate,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Sidebar/Rail/Body/then/Icons/Rows/Row_potions",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		-- ...and fantasy-ornate joined 2026-08-27 (task THEME, ADR-0059): `spendInset`'s
		-- affordability test is now the node's own line box, so a control this package
		-- had always been too small for finally says so.
		packages = "fantasy-ornate,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Sidebar/Rail/Body/then/Icons/Rows/Row_topfive",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		-- ...and fantasy-ornate joined 2026-08-27 (task THEME, ADR-0059): `spendInset`'s
		-- affordability test is now the node's own line box, so a control this package
		-- had always been too small for finally says so.
		packages = "fantasy-ornate,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Sidebar/Rail/Body/then/Icons/Rows/Row_workbench",
		sig = "the 'X' chrome contentInsets could not be",
		px = 44,
		since = 0,
		-- ...and fantasy-ornate joined 2026-08-27 (task THEME, ADR-0059): `spendInset`'s
		-- affordability test is now the node's own line box, so a control this package
		-- had always been too small for finally says so.
		packages = "fantasy-ornate,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p5_wardrobe",
		variant = "-",
		node = "/Wardrobe/BoutiqueWhen/then/Body/Preview/PreviewCol/PaneZ/Controls",
		sig = "this child overflows its zstack by NxNpx and",
		px = 44,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest",
		kind = "layer-overlap",
	},
	{
		surface = "scroll_host",
		variant = "-",
		node = "/ScrollHost/FocusList/Focus*",
		sig = "the 'X' chrome contentInsets could not be",
		-- RE-PINNED by wave TEN-FOOT (ADAPT-8, 2026-08-20): the row's box now follows the theme's own touch floor (the fixture stopped spelling it as a 44), so at ten-foot under Pixel Quest it is 68 rather than 44. The px column records the BOX, not the shortfall, and the shortfall got SMALLER: 44 - 24 = 20px of room for a 32px frame at near, 68 - 40 = 28px at distance.
		px = 68,
		since = 0,
		-- ...and fantasy-parchment, glossy-touch joined 2026-08-27 (task THEME, ADR-0059): `spendInset`'s
		-- affordability test is now the node's own line box, so a control this package
		-- had always been too small for finally says so.
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Detail/Lane/Body/then/Host/Sections/CartWhen/then/CartSection/Cart/Page/CardGrid/ChatterSlot/ChatterCard/OpenChatter",
		sig = "content overflows this hstack by Npx on the",
		px = 40,
		since = 0,
		packages = "classic-desktop,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest",
		kind = "row-cannot-shrink",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Detail/Lane/Body/then/Host/Sections/CartWhen/then/CartSection/Cart/Page/CardGrid/Sky/Skyglow/OpenPlaza",
		sig = "content overflows this hstack by Npx on the",
		px = 40,
		since = 14,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "row-cannot-shrink",
	},
	{
		surface = "row_actions",
		variant = "table",
		node = "/MailActions/TableWhen/then/TablePane/MailTable/Main",
		sig = "content overflows this vstack by Npx on the",
		-- RE-RECORDED 2026-08-29 (task SHOWCASE3): 40 -> 55, under
		-- fantasy-ornate/fantasy-parchment/glossy-touch only (the other five
		-- packages stay at or under 40 here -- their own font/control sizing
		-- lands the same extra room below the ceiling). `controls.table.rowGap`
		-- (2px, flat) is now `math.max`'d against the active package's
		-- `chromeBleed` (`src/controls/table.luau`'s new `rowBandGap`), so
		-- `Main`'s own row-to-row seam widens under a themed glow the same
		-- amount everywhere it applies -- this surface's `page-not-scrollable`
		-- defect is pre-existing and unrepaired (the pane genuinely has no
		-- scroll route at this viewport/preference), so the fix's own,
		-- otherwise-correct extra room lands as MORE of the same accepted
		-- overflow rather than a new class of defect.
		px = 55,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "06_tile_game",
		variant = "-",
		node = "/TileGame/Page/rack/rt*",
		sig = "content box collapses to Npx on x: padding N",
		px = 40, -- re-recorded 2026-08-28 (task SCROLL2, fa7233a): 39 -> 40, the zero-auto-reserve ruling's 8px-wider touch-derived scroll host redistributing 1px onto this rack row (390x844 still measures 39 elsewhere; this is glossy-touch's new max)
		since = 0,
		-- ...and pixel-quest joined 2026-08-27 (task THEME, ADR-0059): `spendInset`'s
		-- affordability test is now the node's own line box, so a control this package
		-- had always been too small for finally says so.
		packages = "fantasy-ornate,glossy-touch,pixel-quest",
		kind = "collapsed-box",
	},
	{
		surface = "sponsor_list",
		variant = "-",
		node = "/ListLab/Body/Rows/Canvas/W/[*]/Row/Card/Labels",
		sig = "content overflows this vstack by Npx on the",
		px = 37,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "05_word_game",
		variant = "-",
		node = "/Wordle/page/col/kb/kbrow2/key_*",
		sig = "content box collapses to Npx on x: padding N",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "collapsed-box",
	},
	{
		surface = "adaptive_controls",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Hud/Shrink/Vocab*",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row1/RowMark1",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row10/RowMark10",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row11/RowMark11",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row12/RowMark12",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row13/RowMark13",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row14/RowMark14",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row2/RowMark2",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row3/RowMark3",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row4/RowMark4",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row5/RowMark5",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row6/RowMark6",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row7/RowMark7",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row8/RowMark8",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "composition",
		variant = "-",
		node = "/CompositionScreen/Body/OfferFrame/Summary/Field/FieldScroll/Row9/RowMark9",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "row_actions",
		variant = "list",
		node = "/MailActions/ListWhen/then/List/Rows/RowsForEach/[*]/*/Content/Row/DotWhen/then/Dot",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "row_actions",
		variant = "vlist",
		-- `Row/Content/...`: the row moved to `itemExtent = "measured"` on 2026-08-15,
		-- and measured mode mounts ONE control-owned `Content` wrapper per row (the node
		-- whose rect IS the measurement). The finding is the same one at the same place
		-- in the cell; only the path gained a level.
		node = "/MailActions/VListWhen/then/VListPane/VList/Canvas/W/[*]/Row/Content/RowBody/DotWhen/then/Dot",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "sponsor_list",
		variant = "-",
		node = "/ListLab/Body/Rows/Canvas/DropLine",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "sponsor_list",
		variant = "-",
		node = "/ListLab/Body/Rows/Canvas/W/[*]/Row/Card/EdgeBar",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "sponsor_list",
		variant = "-",
		node = "/ListLab/Body/Rows/Canvas/W/[*]/Row/Card/Swatch",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "compact-pointer,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "sponsor_markers",
		variant = "-",
		node = "/MarkerLab/Stage/Overlay/Markers/[*]/Dot",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "compact-pointer,fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "theme_authoring",
		variant = "-",
		node = "/AdaptiveScreen/BodyScroll/Body/Hud/Shrink/Vocab*",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "with_animation",
		variant = "-",
		node = "/MotionDemo/Page/Stage/Decorative/Card/Pip",
		sig = "the 'X' chrome contentInsets could not be",
		px = 32,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "theme-inset-yield",
	},
	{
		surface = "row_actions",
		variant = "table",
		node = "/MailActions/TableWhen/then/TablePane/MailTable/Main/Body/Rows/[*]/*/Content/Row/Cells/Cell-subject/Value",
		sig = "this child overflows its zstack by NxNpx and",
		px = 31,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "layer-overlap",
	},
	-- CLOSED 2026-08-16 by the D5 migration. This row recorded the bottom bar's
	-- hand-built wings overflowing their own HStack by 30px under four packages —
	-- a `row-cannot-shrink`, because an icon-only wing had no rung left to step
	-- down to. The wings are `newPicker` segments now, and `Option.icon` rides
	-- `compactLabel`, so the row degrades the word to the glyph at exactly the
	-- width that needs it and the finding fires nowhere in the sweep. Deleted
	-- rather than re-pointed, which is what this list exists to make possible.
	{
		surface = "probe",
		variant = "-",
		node = "/ProbeScreen",
		sig = "content overflows this vstack by Npx on the",
		px = 30,
		since = 14,
		packages = "fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "05_word_game",
		variant = "-",
		node = "/Wordle/page/col/kb/kbrow1/key_*",
		sig = "content box collapses to Npx on x: padding N",
		px = 32, -- re-recorded 2026-08-15 (O-19): 390x844 is 3px worse than the widest cell the tier had
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "collapsed-box",
	},
	{
		surface = "05_word_game",
		variant = "-",
		node = "/Wordle/page/col/kb/kbrow3/key_*",
		sig = "content box collapses to Npx on x: padding N",
		px = 32, -- re-recorded 2026-08-15 (O-19): 390x844 is 3px worse than the widest cell the tier had
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "collapsed-box",
	},
	{
		--[[ THE CASCADE REACHED ITS FLOOR AND THE BOX CROPPED THE REST — which is
			ruling 1's designed last rung, filed by the one surface built to demonstrate
			it, at the widest of its four width stops.

			MEASURED, NOT ASSUMED (2026-08-14). At 320x640 at +14 under Fantasy Ornate
			the row's plate is 154px: two nested padded panels and a scroll reserve take
			166px of a 320px phone under that package's insets. Inside it the Button has
			already taken its COMPACT form (`label = "Srt"`, read off the node) and is
			still 83px of button chrome, "Best fit" is at its 30px floor, and "Newest"
			holds the authored 60px `minMax` minimum — 181px of floor in a 154px box. So
			the solver crops the trailing 27px at the box edge and says so, which is the
			difference between this and the `row-cannot-shrink` rows above: those carry
			no "already at its floor" suffix and are all still repairable by authoring.

			WHAT WOULD MAKE IT GO AWAY IS THE DEMO GIVING UP ITS SUBJECT: a wrap on the
			row, a smaller authored floor, or thinner panel padding tuned against this
			one cell. The fixture's own header refuses the last of those in as many
			words. Recorded with its measurement instead. ]]
		surface = "text_degrade",
		variant = "-",
		node = "/TextDegrade/Page/RowPanel/Row",
		sig = "content overflows this hstack by Npx on the",
		px = 27,
		since = 14,
		packages = "fantasy-ornate,glossy-touch",
		kind = "cascade-floor",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Detail/Lane/Body/then/Host/Sections/CartWhen/then/CartSection/Cart/Page/CardGrid/RackSlot/Rack/OpenPotions",
		sig = "content overflows this hstack by Npx on the",
		px = 26,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest",
		kind = "row-cannot-shrink",
	},
	{
		surface = "selection_bridge",
		variant = "-",
		node = "/BridgeBase",
		sig = "content overflows this vstack by Npx on the",
		px = 24,
		since = 14,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch,pixel-quest,scifi-hud",
		kind = "page-not-scrollable",
	},
	{
		surface = "sponsor_motion",
		variant = "-",
		node = "/MotionLab/Main/StageColumn/Stage/Puck",
		sig = "this child overflows its zstack by NxNpx and",
		px = 23,
		since = 14,
		packages = "fantasy-ornate,glossy-mobile,glossy-touch,pixel-quest",
		kind = "layer-overlap",
	},
	{
		surface = "sponsor_motion",
		variant = "-",
		node = "/MotionLab/Main/StageColumn/Stage/SlotA",
		sig = "this child overflows its zstack by NxNpx and",
		px = 23,
		since = 14,
		packages = "fantasy-ornate,glossy-mobile,glossy-touch,pixel-quest",
		kind = "layer-overlap",
	},
	{
		surface = "sponsor_motion",
		variant = "-",
		node = "/MotionLab/Main/StageColumn/Stage/SlotB",
		sig = "this child overflows its zstack by NxNpx and",
		px = 23,
		since = 14,
		packages = "fantasy-ornate,glossy-mobile,glossy-touch,pixel-quest",
		kind = "layer-overlap",
	},
	{
		surface = "row_actions",
		variant = "table",
		node = "/MailActions/TableWhen/then/TablePane/MailTable/Main/Body/Rows/[*]/*/Content/Row/Cells/Cell-from/Value",
		sig = "this child overflows its zstack by NxNpx and",
		px = 21,
		since = 0,
		packages = "classic-desktop,compact-pointer,fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "layer-overlap",
	},
	{
		surface = "p2_cartwheel",
		variant = "-",
		node = "/Cartwheel/Shell/Detail/Lane/Body/then/Host/Sections/CartWhen/then/CartSection/Cart/Page/CardGrid/Recent/RecentBrews/OpenBrews",
		sig = "content overflows this hstack by Npx on the",
		px = 16,
		since = 0,
		-- ...and pixel-quest joined them 2026-08-27 for the same reason as the row
		-- above (ADR-0059 Decision 5), at 11px against this row's 16px ceiling
		packages = "fantasy-ornate,glossy-touch,pixel-quest,scifi-hud",
		kind = "row-cannot-shrink",
	},
	-- CLOSED 2026-08-28 (task SCROLL2, fa7233a). This row recorded
	-- `/Wardrobe/.../CatalogCol` overflowing 16px at 320x640@+14 under four heavy
	-- packages. The director's zero-auto-reserve ruling hands this touch-derived
	-- column's scroll host 8px more measured width, which absorbs the overflow; the
	-- finding no longer fires anywhere in the themed passes.
	{
		surface = "sponsor_motion",
		variant = "-",
		node = "/MotionLab/Main/StageColumn/Stage/RewardChip",
		sig = "this child overflows its zstack by NxNpx and",
		px = 15,
		since = 14,
		packages = "fantasy-ornate,glossy-mobile,glossy-touch,pixel-quest",
		kind = "layer-overlap",
	},
	{
		surface = "row_actions",
		variant = "list",
		node = "/MailActions/ListWhen/then/List/Rows/RowsForEach/[*]/*/Content/Row/Text/TopLine",
		sig = "content overflows this hstack by Npx on the",
		px = 14,
		since = 0,
		packages = "fantasy-ornate,fantasy-parchment,glossy-touch",
		kind = "row-cannot-shrink",
	},
	{
		surface = "scroll_host",
		variant = "-",
		node = "/ScrollHost/List",
		sig = "content box collapses to Npx on y: padding N",
		px = 13,
		since = 0,
		packages = "compact-pointer,glossy-mobile,glossy-touch,pixel-quest,scifi-hud",
		kind = "collapsed-box",
	},
	{
		surface = "sponsor_drop",
		variant = "-",
		node = "/DropLab/Main/ListZone/Rows/Canvas/W/[*]/Row/Card/Row",
		sig = "content overflows this hstack by Npx on the",
		px = 12,
		since = 14,
		packages = "glossy-mobile,glossy-touch",
		kind = "row-cannot-shrink",
	},
	{
		surface = "with_animation",
		variant = "-",
		node = "/MotionDemo/Page/Stage/Decorative/Card",
		sig = "content overflows this vstack by Npx on the",
		px = 12,
		since = 0,
		packages = "compact-pointer",
		kind = "page-not-scrollable",
	},
	-- CLOSED 2026-08-16 by the D5 migration. The feed page's scroll box collapsed
	-- to nothing under `compact-pointer` and `scifi-hud` because the shell above it
	-- had spent every pixel; the construct's bands declare no padding of their own
	-- (a container that adds no spacing is a structural statement, not a style
	-- value), which handed those pixels back and the finding fires nowhere.
	{
		--[[ FOUND BY THE 390x844 VIEWPORT (O-19, 2026-08-15), and it is the mildest
			row in this file: Pixel Quest's `barTrack` carves 8+8 of inset, and at this
			width the demo's own progress value leaves the FILL 2px wide, so the track
			reports that nothing inside it can draw. There is no copy inside a progress
			fill and nothing beside it moves — a 2px sliver of a bar not painting its
			inner plate is a bleed, not a lost word. Recorded rather than filtered
			because the same sentence on a node that DID carry copy would be real.

			RE-PINNED 2026-08-28 (task SCROLL2, fa7233a): 2 -> 10. `Page` is a
			touch-derived auto-policy ScrollView; the director's zero-auto-reserve
			ruling hands it 8px more measured width, which reaches this bar's own
			`barTrack` and grows it by the same 8px (measured directly: this exact cell
			now reports 10, not 2) — still fully collapsed against the fixed 8+8
			padding, just a wider box hitting the same ceiling. `SpringBar`'s twin row
			(which stood here until now) is DELETED rather than re-pinned: measured at
			the same cell, its fill no longer collapses at all — a defect this ruling
			genuinely fixed, not merely widened. ]]
		surface = "time_curves",
		variant = "-",
		node = "/TimeCurves/Page/CooldownBar/Bar",
		sig = "content box collapses to Npx on x: padding N",
		px = 10,
		since = 0,
		packages = "pixel-quest",
		kind = "collapsed-box",
	},
	{
		surface = "sponsor_celebration",
		variant = "-",
		node = "/CelebrationLab",
		sig = "content overflows this vstack by Npx on the",
		px = 3,
		since = 14,
		packages = "glossy-touch,pixel-quest",
		kind = "page-not-scrollable",
	},
	-- CLOSED 2026-08-18 by ADAPT-18/19 (wave TABLE). This entry recorded the
	-- playlist's five-star rating run overflowing its own cell by 2px under
	-- Fantasy Ornate, from +0 — a `layer-overlap` on the one column whose content
	-- is a fixed-width run of glyphs rather than text that can ellipsize. The
	-- column now COLLAPSES at the viewports where it could not fit, so there is no
	-- cell for the stars to overflow and the finding fires nowhere in the themed
	-- passes. The rating is still reachable: the disclosure plate lists it per row.
	-- Deleted rather than re-recorded, which is what this list is for.
	--[[ DELETED by framework-gaps-phase2 §6 (2026-08-22), which is what this ledger
		is FOR: the defect is gone rather than moved. The row read

		    p3_sipworks /Sipworks/Shell/Middle/Content — content box collapses to 2px
		    on y, from +14, under pixel-quest

		— Pixel Quest's fields at 76px in a hand-built shell that stacked a top bar, a
		`Middle` row and a `Dock`, each with a gap of its own, left the content region
		2px on a 640x320 landscape at the largest text preference. The shell is
		`Facet.Controls.TabView` now, and the construct declares NO padding and NO gap
		anywhere in its own scaffold (its header says why), so those steps came back to
		the content. The sweep reports nothing at that cell any more, from any package. ]]
	{
		--[[ TWO TAB BARS DO NOT FIT ON A 320px-TALL LANDSCAPE AT THE LARGEST TEXT
			PREFERENCE, and that is a fact about NESTING rather than about this fixture
			— which is why it is recorded here rather than authored around. `r2`'s shape
			is a page's top bar inside an app's bar, and each band is a themed control
			row: under the five heaviest packages at +14 the pair needs 108px and 92px
			each, and the landscape has one band's worth of room between them.

			MEASURED, NOT ASSUMED, and the fixture already spent what it could: the
			readouts moved off the screen and into the tabs (four lines of prose above
			a TabView cost 114 findings), and the page padding came off (which took the
			scifi-hud row at +0 with it — 2px, the one finding here that fired at the
			DEFAULT preference). What is left is the two bands themselves.

			The same class as `p3_sipworks` below it: a screen with genuinely no room,
			not a control that cannot draw. Every tab is still reachable and the page's
			own body is a scroller; what runs past the box is the band the construct
			places. A framework answer would be a nested TabView that degrades its own
			band on a short height, which no version of this control has. ]]
		surface = "tab_view",
		variant = "-",
		node = "/TabViewDemo/Root/App/Content/Tab-pages/then/Page",
		sig = "content overflows this vstack by Npx on the",
		px = 42,
		since = 14,
		packages = "fantasy-ornate,fantasy-parchment,glossy-mobile,glossy-touch,scifi-hud",
		kind = "page-not-scrollable",
	},
} :: { Row }

return theme_ledger
