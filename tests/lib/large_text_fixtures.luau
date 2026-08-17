--!strict
--[[ THE LARGE-TEXT CONTROL FIXTURES — one mountable screen per
	tests/conformance/controls_registry row (acceptance LT-8).

	Split out of tests/large_text_matrix.spec so the sweep file stays readable:
	this is the DATA (what is mounted, what truncation is declared, and why), the
	spec is the ASSERTIONS. Nothing here runs a check; nothing there decides what
	a control's large-text fixture should be.

	Each fixture names the registry `class` it covers — several fixtures may
	cover one row (a Button is worth sweeping in three shapes) — and any
	`allowClipped` path prefixes whose truncation is DECLARED, each citing a gap
	in LT_GAPS. An allowlist entry is never "this is fine": it is "the framework
	has no way to express the fix", and tests/large_text_open_defects.luau
	carries the failing repro for each one.
]]

local LuauUI = require("../../src") :: any
local UI = require("../../src/blueprint")
local resources = require("../../src/async/resources")
local lt = require("./large_text")

local fixtures = {}

local PSEUDO = lt.PSEUDO
local GERMAN = lt.GERMAN_COMPOUND

--[[ THE DECLARED GAPS — found by this sweep, now CLOSED in the framework (the
	fixtures below carry the fixes, so the sweep re-proves them every run; no
	allowlist entries remain).

	LT-G1  (FIXED) a Toggle's one-line label had no full-value path — `disclose`
	       now rides UI.Toggle, feeding the same textFacts/plate the Text prop
	       does (tests/text_disclosure.spec "LT-G1" describe).

	LT-G2  (FIXED) table-authored text had no disclose channel — a Column's
	       `disclose = true` now stamps its value cells and header title
	       (tests/table.spec "Table column disclosure").

	LT-G4  (OPEN) a Picker's OPTION labels have no full-value path. `disclose` is
	       a `UI.Text` prop and `newPicker` neither accepts nor forwards one, so an
	       option label that ellipsizes has no way back to the whole string. Found
	       2026-08-13 by the wrap rule (director ruling 5): before it, a wrapped
	       phrase reported `truncated = false` no matter how squeezed, so this
	       entire class was invisible to `clippedEssential`. Fix is a `disclose`
	       pass-through on the option record; until then the sweep declares it.

	LT-G3  (AUTHORING RULE) a pinned px `rowHeight` is honored verbatim and is
	       preference-blind by contract: pin only a height that clears
	       (textSize + Largest offset) * lineHeight for every cell, or leave it
	       unpinned (the default row box composes the offset automatically).
	       An undisclosed clip from a too-short pinned row is caught by
	       clippedEssential; the api.md Table entry states the rule.
]]
local LT_GAPS = { G1 = "LT-G1", G2 = "LT-G2", G3 = "LT-G3", G4 = "LT-G4" }
fixtures.LT_GAPS = LT_GAPS

-- ── fixtures ────────────────────────────────────────────────────────────────
-- `class` is the controls_registry row this fixture covers (several fixtures may
-- cover one row: a Button has three shapes worth sweeping). `allowClipped` is a
-- list of path PREFIXES whose truncation is declared, each with a gap citation.

export type Fixture = {
	id: string,
	class: string,
	build: (core: any, w: any) -> any,
	allowClipped: { string }?,
	why: string?,
}

local FIXTURES: { Fixture } = {
	{
		id = "Text",
		class = "Text",
		-- an essential status line: a phrase, so the reflow rung applies and it
		-- must WRAP at every preference rather than ellipsize
		build = function()
			return UI.Text({ id = "Ctl", text = PSEUDO })
		end,
	},
	{
		id = "Text-identity-disclosed",
		class = "Text",
		-- the identity case done RIGHT: one unbroken name in a bounded cell,
		-- declaring `disclose`, which is the full-value path LTN-4 shipped. This
		-- is the fixture the plan means by "prefer declaring disclose": it
		-- truncates and produces NO finding, because the reader can still get the
		-- whole string.
		build = function()
			return UI.VStack({
				id = "Ctl",
				width = { type = "fixed", px = 140 },
				children = { UI.Text({ id = "Name", text = GERMAN, disclose = true }) },
			})
		end,
	},
	{
		id = "Button-plain",
		class = "Button",
		-- an ACTION label. The plan forbids it becoming an ellipsis at any
		-- preference; a phrase has legal breaks, so the framework's answer is to
		-- wrap and grow the button.
		build = function()
			return UI.Button({ id = "Ctl", label = lt.PSEUDO_ACTION })
		end,
	},
	{
		id = "Button-circle",
		class = "Button",
		-- shape = "circle": the drawn content is the ICON and the label stays the
		-- semantic name, so there is no text to clip and the disc must stay on
		-- its 1:1 target at every preference
		build = function()
			return UI.Button({ id = "Ctl", label = lt.PSEUDO_ACTION, shape = "circle", icon = "more" })
		end,
	},
	{
		id = "Button-compactLabel",
		class = "Button",
		-- the declared compact alternative: the solver measures BOTH strings in
		-- one pass and picks per solve, so a narrow box takes the compact form
		-- instead of cutting the full one.
		--
		-- 150px is chosen, not arbitrary: it is under what the FULL label needs in
		-- either theme at any preference (214-362px), so the swap always happens,
		-- and above what the COMPACT form needs at Largest under Fantasy
		-- Parchment (110px), so the last rung of the ladder still fits its box. A
		-- narrower authored width clips the compact form itself at Larger under
		-- that package — see LT6-FIXEDPX below, which pins that boundary.
		build = function()
			return UI.HStack({
				id = "Ctl",
				gap = 8,
				children = {
					UI.Button({
						id = "Save",
						label = lt.PSEUDO_ACTION,
						compactLabel = "OK",
						width = { type = "fixed", px = 150 },
					}),
					UI.Button({
						id = "Later",
						label = lt.PSEUDO_SECONDARY,
						compactLabel = "No",
						width = { type = "fixed", px = 150 },
					}),
				},
			})
		end,
	},
	{
		id = "Toggle",
		class = "Toggle",
		-- the one-line label form is measured, signed design; `disclose` (the
		-- LT-G1 fix) is its declared full-value path, so the truncation files no
		-- finding and needs no allowlist any more
		build = function(core)
			return UI.Toggle({ id = "Ctl", label = PSEUDO, value = core:signal(false), disclose = true })
		end,
	},
	{
		id = "TextField",
		class = "TextField",
		-- the placeholder is instruction text: it must reflow, never ellipsize
		build = function()
			return UI.TextField({ id = "Ctl", text = "", placeholder = PSEUDO })
		end,
	},
	{
		id = "Grip",
		class = "Grip",
		build = function()
			return UI.Grip({
				id = "Ctl",
				cursorHint = "rbxasset://SizeEW",
				focusable = true,
				width = { type = "fixed", px = 44 },
				height = { type = "fixed", px = 44 },
			})
		end,
	},
	{
		id = "Slider",
		class = "Slider",
		build = function(core)
			return LuauUI.newSlider(LuauUI, core, {
				id = "Ctl",
				label = PSEUDO,
				value = core:signal(0.5),
				min = 0,
				max = 1,
				step = 0.1,
			}).blueprint
		end,
	},
	{
		id = "Stepper",
		class = "Stepper",
		build = function(core)
			return LuauUI.newStepper(LuauUI, core, {
				id = "Ctl",
				label = PSEUDO,
				value = core:signal(3),
				min = 0,
				max = 10,
				step = 1,
			}).blueprint
		end,
	},
	{
		id = "Chip",
		class = "Chip",
		build = function(core)
			return LuauUI.newChip(LuauUI, core, { id = "Ctl", label = PSEUDO, selected = core:signal(false) }).blueprint
		end,
	},
	{
		-- row-actions Task 3: the trailing tray REVEALED (via the programmatic
		-- `_open` seam — the only seam this task ships) so the sweep actually
		-- measures the pseudo-localized tray button label, not a closed,
		-- zero-Instance passthrough. `buttonMinWidth` is a floor, never a cap
		-- (docs/reference/api.md `newRowActions`), so this fixture proves the
		-- long label widens the button rather than clipping.
		id = "RowActions",
		class = "RowActions",
		build = function(core)
			local ra = LuauUI.newRowActions(LuauUI, core, {
				id = "Ctl",
				content = UI.Text({ id = "Title", text = "Row" }),
				trailing = { { id = "delete", label = PSEUDO, onAction = function() end } },
			})
			ra._open("trailing")
			return ra.blueprint
		end,
	},
	{
		id = "PopupButton",
		class = "PopupButton",
		build = function(core)
			return LuauUI.newPopupButton(LuauUI, core, {
				id = "Ctl",
				value = core:signal("one"),
				options = { { id = "one", label = PSEUDO }, { id = "two", label = lt.PSEUDO_SECONDARY } },
			}).blueprint
		end,
	},
	{
		--[[ THE OPEN MENU'S PANEL, mounted directly from the recipe every menu
			renders from (`src/controls/menu_recipe.luau`). The control presents its
			panel as its OWN surface through `presenter.presentAnchored`, and this
			sweep mounts and measures ONE screen — so sweeping `newMenu`'s blueprint
			would sweep the trigger and never a single row.

			The rows are what the preference actually threatens: each declares a
			FIXED px height off the control-size ladder while its label grows, which
			is precisely the "painted at a size nobody measured" family this matrix
			exists to catch (docs/lessons/, the fixed-px-height defect class). Both
			row forms are here — the leaf and the submenu row with its chevron — plus
			the divider that separates two icon groups. ]]
		id = "Menu-panel",
		class = "Menu",
		build = function(core)
			local recipe = require("../../src/controls/menu_recipe")
			return UI.VStack({
				id = "Ctl",
				surface = "raised",
				gap = recipe.ROW_GAP,
				width = { type = "fill", weight = 1 },
				children = {
					recipe.row(UI, { id = "Item:a", label = PSEUDO, icon = "edit" }),
					recipe.row(UI, { id = "Item:b", label = GERMAN, icon = "edit" }),
					recipe.divider(UI, "Div-3"),
					recipe.row(UI, { id = "Item:c", label = lt.PSEUDO_ACTION, submenu = true }),
					recipe.row(UI, { id = "Item:d", label = PSEUDO, role = "destructive" }),
				},
			})
		end,
	},
	--[[ THE COACH MARK'S PLATE (navigation-and-menus D3b). It is swept through
		`callout.plate` — the exported builder the control itself mounts — because
		a Callout's blueprint is the caller's ANCHOR node and the plate does not
		exist until something presents it, so mounting the control here would sweep
		a button and never the surface. Two lines of player copy over a full-width
		dismiss row is exactly the shape a text preference squeezes. ]]
	{
		id = "Callout-plate",
		class = "Callout",
		build = function()
			local calloutLib = require("../../src/controls/callout")
			return calloutLib.plate(UI, {
				content = UI.VStack({
					id = "Content",
					gap = "xs",
					children = {
						UI.Text({ id = "Title", text = lt.PSEUDO_ACTION, textSize = "body" }),
						-- WRAPS rather than truncating, which is what player copy in a
						-- coach mark has to do: the German compound below is one
						-- unbreakable word and clipped at Large(+4) the first time this
						-- fixture ran, which is exactly the finding the sweep exists to
						-- make. A caption is a phrase, so it is a phrase here.
						UI.Text({ id = "Sub", text = lt.PSEUDO_SECONDARY, textSize = "caption", role = "secondary" }),
					},
				}),
				dismissLabel = PSEUDO,
			})
		end,
	},
	{
		id = "Rating",
		class = "Rating",
		build = function(core)
			return LuauUI.newRating(LuauUI, core, { id = "Ctl", value = core:signal(3) }).blueprint
		end,
	},
	{
		-- THE GLYPH SEGMENT AT THE TOP OF THE RANGE, which is this control's only
		-- large-text exposure and the reason the fixture is not the default `bar`:
		-- a bar has no text in it at all, while a glyph is painted at
		-- `textSize * typographyScale` and TEN of them share one strip. That is
		-- exactly the shape that starved the rating's tail before the run became a
		-- uniform Grid, at twice the count.
		id = "LevelPicker",
		class = "LevelPicker",
		build = function(core)
			return LuauUI.newLevelPicker(
				LuauUI,
				core,
				{ id = "Ctl", value = core:signal(4), count = 10, segment = "glyph" }
			).blueprint
		end,
	},
	{
		id = "Picker",
		class = "Picker",
		build = function(core)
			return LuauUI.newPicker(LuauUI, core, {
				id = "Ctl",
				label = lt.PSEUDO_ACTION,
				selected = core:signal("a"),
				options = {
					{ value = "a", label = lt.PSEUDO_ACTION },
					{ value = "b", label = lt.PSEUDO_SECONDARY },
				},
				-- THE ESCAPE HATCH, declared (navigation-and-menus D6). A two-option
				-- picker resolves segmented, and the segmented presentation now
				-- carries the sliding indicator by DEFAULT — so the unindicated
				-- shape, which this fixture exists to sweep, has to ask for itself.
				-- The `Picker-indicator` fixture below sweeps the shipped default.
				indicator = "none",
			}).blueprint
		end,
		allowClipped = { "/S/Ctl/Options" },
		why = LT_GAPS.G4,
	},
	{
		--[[ The D4 seam is a DECORATION over the option strip, so the thing a
			preference can break here is the relationship between the two: the chip
			is derived from the SOLVED rect of the selected option, so a preference
			that grows the label has to grow the chip with it. A hand-computed width
			would drift at exactly one of the four offsets and nowhere else.

			A second Picker fixture rather than a change to the first, because the
			`indicator` property changes what the control PAINTS (the options go
			plain and drop the selected tag) and the unindicated shape has to keep
			being swept as well. ]]
		id = "Picker-indicator",
		class = "Picker",
		build = function(core)
			return LuauUI.newPicker(LuauUI, core, {
				id = "Ctl",
				selected = core:signal("a"),
				presentation = "segmented",
				indicator = "pill",
				options = {
					{ value = "a", label = lt.PSEUDO_ACTION },
					{ value = "b", label = lt.PSEUDO_SECONDARY },
				},
			}).blueprint
		end,
		-- LT-G4, the SAME open gap the unindicated Picker fixture declares: an
		-- option label has no `disclose` pass-through, so under Fantasy Parchment
		-- at Larger it ellipsizes with no route to the whole string. The indicator
		-- neither causes nor cures it — it decorates the box the label is in.
		allowClipped = { "/S/Ctl/Indicator/Options" },
		why = LT_GAPS.G4,
	},
	{
		--[[ THE TAB STRIP IS THE TIGHTEST TEXT BOX THE FRAMEWORK SHIPS
			(navigation-and-menus D5). A thumb-zone bar divides one compact width
			among every tab, so a preference that grows the type has the least room
			here of anywhere — which is exactly why the reference shells all carry a
			terse second string for this home, and why the sweep has to see it.

			`placement` is DECLARED rather than left automatic: the fixture harness
			builds from a bare core with no environment, and pinning the home is
			also what makes the row a text sweep rather than a placement one. ]]
		id = "TabView",
		class = "TabView",
		build = function(core)
			return LuauUI.newTabView(LuauUI, core, {
				id = "Ctl",
				selection = core:signal("a"),
				placement = "bottomBar",
				tabs = {
					{
						id = "a",
						label = lt.PSEUDO_ACTION,
						content = function()
							return UI.Text({ id = "Body", text = PSEUDO })
						end,
					},
					{
						id = "b",
						label = lt.PSEUDO_SECONDARY,
						content = function()
							return UI.Text({ id = "Body", text = PSEUDO })
						end,
					},
				},
			}).blueprint
		end,
		-- LT-G4, inherited whole from the strip this control composes: a tab label
		-- is a picker option label, which has no `disclose` pass-through, so at the
		-- expansion locale and the largest preference it ellipsizes with no route
		-- to the whole string. Composing the picker inherits its open gaps as well
		-- as its floors, and saying so is the point of citing the same one.
		allowClipped = { "/S/Ctl/BottomHome/then/BottomBand/Strip/Indicator/Options" },
		why = LT_GAPS.G4,
	},
	{
		id = "DisclosureGroup",
		class = "DisclosureGroup",
		build = function(core)
			return LuauUI.newDisclosureGroup(LuauUI, core, {
				id = "Ctl",
				label = lt.PSEUDO_ACTION,
				expanded = core:signal(true),
				content = function()
					return UI.Text({ id = "Body", text = PSEUDO })
				end,
			}).blueprint
		end,
	},
	{
		id = "ProgressView",
		class = "ProgressView",
		build = function(core)
			return LuauUI.newProgressView(LuauUI, core, { id = "Ctl", value = 0.4, showValue = true }).blueprint
		end,
	},
	{
		id = "Label",
		class = "Label",
		build = function(core)
			return LuauUI.newLabel(LuauUI, core, { id = "Ctl", title = PSEUDO, icon = "rbxassetid://1" }).blueprint
		end,
	},
	{
		id = "TextInput",
		class = "TextInput",
		build = function(core, w)
			return LuauUI.newTextInput(LuauUI, core, {
				id = "Ctl",
				value = core:signal(""),
				placeholder = PSEUDO,
				env = w.env,
				actionSystem = w.system,
			}).blueprint
		end,
	},
	{
		id = "Table",
		class = "Table",
		build = function(core)
			return LuauUI.newTable(LuauUI, core, {
				id = "Ctl",
				rows = core:signal({ { id = "a", name = PSEUDO }, { id = "b", name = GERMAN } }),
				key = function(row: any)
					return row.id
				end,
				rowHeight = 44,
				-- THE AUTO EDIT TOOLBAR IS PART OF THE CONTROL, so it has to be in
				-- the sweep (EQ-6, 2026-08-06). Without these two lines the toolbar
				-- row never mounted here, and the header band that grew into it at
				-- Largest text was a defect no row of this matrix could see —
				-- reported from a phone instead. `reorderable` + no owner `editing`
				-- signal + the touch environment this sweep already uses is exactly
				-- the condition that shows the toggle.
				reorderable = true,
				onReorder = function() end,
				columns = {
					{
						id = "name",
						title = PSEUDO,
						width = { type = "fill", weight = 1 },
						value = function(row: any)
							return row.name
						end,
						-- the LT-G2 fix: the column's declaration covers the
						-- table-authored value cells AND the header title, so the
						-- identity truncation has its full-value path and files no
						-- finding. The px `rowHeight` stays authored (LT-G3 is an
						-- AUTHORING rule now: a pinned row must clear the painted
						-- text at every preference, or stay unpinned — the audit
						-- catches an undisclosed clip either way)
						disclose = true,
					},
				},
			}).blueprint
		end,
	},
	{
		id = "VirtualList",
		class = "VirtualList",
		-- the identity cell done RIGHT: the CALLER owns the cell factory here, so
		-- the unbroken name declares `disclose` and the row produces no finding —
		-- the same fix the Table cannot express
		build = function(core)
			return LuauUI.newVirtualList(LuauUI, core, {
				id = "Ctl",
				rows = core:signal({ { id = "a", label = PSEUDO }, { id = "b", label = GERMAN } }),
				key = function(item: any)
					return item.id
				end,
				rowHeight = 44,
				viewportHeight = 200,
				overscan = 1,
				cell = function(item: any)
					return UI.Text({ id = "Label", text = item.label, disclose = true })
				end,
			}).blueprint
		end,
	},
	{
		id = "VirtualGrid",
		class = "VirtualGrid",
		-- THE SAME CELL SHAPE AS THE VirtualList FIXTURE ABOVE, DELIBERATELY: a
		-- fixed-extent slot holding one unbroken identity name that declares
		-- `disclose`. What this fixture adds is the second axis — a grid's slot is
		-- also NARROWER than a list's row by a factor of its lane count, so the same
		-- name at the same preference has far less width to wrap into. That is the
		-- case a list cannot reach, and it is why this is a fixture rather than an
		-- UNSWEEPABLE row.
		build = function(core)
			return LuauUI.newVirtualGrid(LuauUI, core, {
				id = "Ctl",
				items = core:signal({
					{ id = "a", label = PSEUDO },
					{ id = "b", label = GERMAN },
					{ id = "c", label = PSEUDO },
					{ id = "d", label = GERMAN },
				}),
				key = function(item: any)
					return item.id
				end,
				columns = 2,
				itemExtent = 44,
				viewportExtent = 200,
				overscan = 1,
				cell = function(item: any)
					return UI.Text({ id = "Label", text = item.label, disclose = true })
				end,
			}).blueprint
		end,
	},
	{
		id = "AsyncImage",
		class = "AsyncImage",
		build = function(core)
			local provider = resources.newProvider(core)
			return LuauUI.newAsyncImage(LuauUI, core, {
				id = "Ctl",
				provider = provider,
				scope = core:scope("large-text-async"),
				key = "avatar/1",
			}).blueprint
		end,
	},
	{
		id = "PathShapes-ring",
		class = "PathShapes",
		-- pathShapes is pure math; the thing that MOUNTS is the UI.Path it feeds,
		-- so the fixture sweeps the pair (which also covers the Path leaf row)
		build = function()
			return UI.Path({
				id = "Ctl",
				points = LuauUI.pathShapes.ring({ radius = 0.5 }),
				width = { type = "fixed", px = 64 },
				height = { type = "fixed", px = 64 },
			})
		end,
	},
	{
		id = "Path",
		class = "Path",
		build = function()
			return UI.Path({
				id = "Ctl",
				points = LuauUI.pathShapes.ring({ radius = 0.4 }),
				width = { type = "fixed", px = 48 },
				height = { type = "fixed", px = 48 },
			})
		end,
	},
	{
		id = "Image",
		class = "Image",
		build = function()
			return UI.Image({ id = "Ctl", image = "rbxassetid://1" })
		end,
	},
	--[[ THE FOREIGN BOX (ADR-0034), SWEPT LIKE Box/Path/Image AND FOR ONE MORE
		REASON THAN THEY ARE. A Foreign draws no text of its own — its face is a
		caller-owned GuiObject the framework never measures — so the naive reading
		is that a text-preference sweep has nothing to look at, which is the reason
		`Stage` is declared UNSWEEPABLE below.

		It is swept anyway, because this class has a property those three share and
		`Stage` does not exercise here: its box is DECLARED in px and CANNOT reflow,
		while the caption beside it grows with the preference. That is exactly the
		shape a preference collision takes, so the fixture pairs the two — a rigid
		box and a caption that has to find room around it at every offset in
		{ 0, 4, 10, 14 } and in both reference themes. ]]
	{
		id = "Foreign",
		class = "Foreign",
		build = function()
			return UI.VStack({
				id = "Ctl",
				children = {
					UI.Foreign({
						id = "Pane",
						width = { type = "fixed", px = 120 },
						height = { type = "fixed", px = 68 },
						surface = "raised",
					}),
					UI.Text({ id = "Caption", text = PSEUDO }),
				},
			})
		end,
	},
	{
		id = "Box",
		class = "Box",
		build = function()
			return UI.Box({ id = "Ctl", height = { type = "fixed", px = 40 } })
		end,
	},
	{
		id = "Spacer",
		class = "Spacer",
		build = function()
			return UI.VStack({
				id = "Ctl",
				children = { UI.Text({ id = "A", text = PSEUDO }), UI.Spacer({ id = "Gap" }) },
			})
		end,
	},
	{
		id = "Divider",
		class = "Divider",
		build = function()
			return UI.VStack({
				id = "Ctl",
				children = {
					UI.Text({ id = "A", text = lt.PSEUDO_ACTION }),
					UI.Divider({ id = "Rule" }),
					UI.Text({ id = "B", text = lt.PSEUDO_SECONDARY }),
				},
			})
		end,
	},
	{
		id = "VStack",
		class = "VStack",
		build = function()
			return UI.VStack({
				id = "Ctl",
				gap = 8,
				children = { UI.Text({ id = "A", text = PSEUDO }), UI.Text({ id = "B", text = PSEUDO }) },
			})
		end,
	},
	{
		id = "HStack",
		class = "HStack",
		build = function()
			return UI.HStack({
				id = "Ctl",
				gap = 8,
				children = {
					UI.Text({ id = "A", text = lt.PSEUDO_ACTION }),
					UI.Text({ id = "B", text = lt.PSEUDO_SECONDARY }),
				},
			})
		end,
	},
	{
		id = "ZStack",
		class = "ZStack",
		build = function()
			return UI.ZStack({
				id = "Ctl",
				height = { type = "fixed", px = 120 },
				children = { UI.Box({ id = "Plate" }), UI.Text({ id = "Over", text = lt.PSEUDO_ACTION }) },
			})
		end,
	},
	{
		id = "Anchor",
		class = "Anchor",
		build = function()
			return UI.Anchor({
				id = "Ctl",
				height = { type = "fixed", px = 120 },
				children = { UI.Text({ id = "Pinned", text = lt.PSEUDO_ACTION, anchor = "topLeft" }) },
			})
		end,
	},
	{
		id = "Grid",
		class = "Grid",
		build = function()
			return UI.Grid({
				id = "Ctl",
				columns = 2,
				minColumnWidth = "intrinsic",
				gap = 8,
				children = {
					-- ...and the grid's action carries ITS fix, which for a Button is
					-- the compact form rather than `disclose` (director ruling 5,
					-- 2026-08-13): at Large under fantasy-parchment the theme's own
					-- chrome insets leave less drawable width than the label's longest
					-- word, so the label can no longer wrap and would ellipsize. A
					-- declared compact form is the rung above the ellipsis.
					UI.Button({ id = "A", label = lt.PSEUDO_ACTION, compactLabel = "\u{015E}\u{00E1}\u{1E7D}\u{00E9}" }),
					UI.Button({ id = "B", label = lt.PSEUDO_SECONDARY }),
				},
			})
		end,
	},
	{
		-- THE ROW GRID AT LARGEST TEXT (parity round 2 §2.2). It is swept for a
		-- reason the flow grid above cannot cover: a row grid's column widths come
		-- from the WIDEST CELL IN THAT COLUMN ACROSS EVERY ROW, so one label growing
		-- under a text-size preference re-widths a column under every other row —
		-- and the columns are then reduced to fit the box. A key/value pair is the
		-- shape that actually ships.
		id = "GridRow",
		class = "GridRow",
		build = function()
			return UI.Grid({
				id = "Ctl",
				gap = 8,
				children = {
					UI.GridRow({
						id = "R1",
						children = {
							UI.Text({ id = "K1", text = lt.PSEUDO_SECONDARY }),
							-- THE VALUE CELL CARRIES THE FIX (director ruling 5,
							-- 2026-08-13). A row grid reduces its columns to fit the box,
							-- and at Largest under fantasy-parchment this column is
							-- narrower than the longest WORD of its value — so the value
							-- can no longer wrap (wrapping there breaks the word) and it
							-- ellipsizes. `disclose` is the framework's declared answer to
							-- exactly that, and the sweep re-proves it every run.
							UI.Text({ id = "V1", text = lt.PSEUDO_ACTION, disclose = true }),
						},
					}),
					UI.GridRow({
						id = "R2",
						children = {
							-- row 2's KEY is the same long string in the same reduced
							-- column, so it carries the same declared path (see V1 above)
							UI.Text({ id = "K2", text = lt.PSEUDO_ACTION, disclose = true }),
							UI.Text({ id = "V2", text = lt.PSEUDO_SECONDARY }),
						},
					}),
				},
			})
		end,
	},
	{
		id = "ScrollView",
		class = "ScrollView",
		build = function()
			return UI.ScrollView({
				id = "Ctl",
				height = { type = "fixed", px = 200 },
				children = {
					UI.Text({ id = "A", text = PSEUDO }),
					UI.Text({ id = "B", text = PSEUDO }),
					UI.Text({ id = "C", text = PSEUDO }),
				},
			})
		end,
	},
	{
		id = "AdaptiveStack",
		class = "AdaptiveStack",
		build = function()
			return UI.AdaptiveStack({
				id = "Ctl",
				axis = "y",
				gap = 8,
				children = {
					UI.Button({ id = "A", label = lt.PSEUDO_ACTION }),
					UI.Button({ id = "B", label = lt.PSEUDO_SECONDARY }),
				},
			})
		end,
	},
	{
		id = "ViewThatFits",
		class = "ViewThatFits",
		build = function()
			return UI.ViewThatFits({
				id = "Ctl",
				children = {
					UI.HStack({
						id = "Row",
						gap = 8,
						children = {
							UI.Button({ id = "RowSave", label = lt.PSEUDO_ACTION }),
							UI.Button({ id = "RowLater", label = lt.PSEUDO_SECONDARY }),
						},
					}),
					UI.VStack({
						id = "Col",
						gap = 8,
						children = {
							UI.Button({ id = "ColSave", label = lt.PSEUDO_ACTION }),
							UI.Button({ id = "ColLater", label = lt.PSEUDO_SECONDARY }),
						},
					}),
				},
			})
		end,
	},
	{
		id = "Composition",
		class = "Composition",
		build = function()
			return UI.Composition({
				id = "Ctl",
				arrangements = { "twoLane", "column" },
				laneGap = 12,
				groupGap = 8,
				height = { type = "fill", weight = 1 },
				groups = {
					{ id = "body", lane = "main", sizing = "fill", minWidth = 200 },
					{ id = "actions", lane = "trail", sizing = "hug" },
				},
				children = {
					UI.Region({
						id = "Status",
						group = "body",
						rank = 1,
						children = { UI.Text({ id = "Line", text = PSEUDO }) },
					}),
					UI.Region({
						id = "Cta",
						group = "actions",
						rank = 2,
						children = { UI.Button({ id = "Go", label = lt.PSEUDO_ACTION }) },
					}),
				},
			})
		end,
	},
	{
		id = "Region",
		class = "Region",
		-- a Region only means anything inside a Composition, so its fixture is the
		-- Composition that gives it a box (the conformance kit does the same)
		build = function()
			return UI.Composition({
				id = "Ctl",
				arrangements = { "column" },
				groups = { { id = "body", lane = "main", sizing = "fill" } },
				height = { type = "fill", weight = 1 },
				children = {
					UI.Region({
						id = "Only",
						group = "body",
						rank = 1,
						sizing = "fill",
						children = { UI.Text({ id = "Line", text = PSEUDO }) },
					}),
				},
			})
		end,
	},
	{
		id = "When",
		class = "When",
		build = function(core)
			return UI.When({
				id = "Ctl",
				condition = core:signal(true),
				thenView = function()
					return UI.Text({ id = "Shown", text = PSEUDO })
				end,
			})
		end,
	},
	{
		id = "ForEach",
		class = "ForEach",
		build = function(core)
			return UI.ForEach({
				id = "Ctl",
				items = core:signal({ 1, 2 }),
				key = function(item: any)
					return tostring(item)
				end,
				row = function(item: any)
					return UI.Text({ id = `row{item}`, text = PSEUDO })
				end,
			})
		end,
	},
	{
		id = "ErrorBoundary",
		class = "ErrorBoundary",
		build = function()
			return UI.ErrorBoundary({
				id = "Ctl",
				view = function()
					return UI.Text({ id = "Body", text = PSEUDO })
				end,
				fallback = function()
					return UI.Text({ id = "Fallback", text = "failed" })
				end,
			})
		end,
	},
}

-- registry rows that CANNOT be a fixture, each with the reason. Silence here
-- would be the same silent-zero the extension checker exists to prevent.
local UNSWEEPABLE: { [string]: string } = {
	SelectionIndicator = "the DECORATION half of Picker's `indicator` property (navigation-and-menus D4): it returns "
		.. "the layer Picker mounts, so it is swept through the `Picker-indicator` fixture — at every preference, in "
		.. "both reference themes — rather than twice",
	MenuRecipe = "the ROW half of every menu (navigation-and-menus D2): it returns the blueprints Menu, PopupButton "
		.. "and RowActions mount, so it is swept through the `Menu-panel` fixture — which mounts those very rows, "
		.. "at every preference and in both reference themes — rather than three times",
	Screen = "the sweep's own root: every fixture is mounted inside a UI.Screen, so the row is exercised by all of them",
	ValueModel = "stateless value arithmetic — no blueprint, nothing to mount or measure",
	-- the two halves of src/controls/row_actions.luau that were lifted out on
	-- 2026-08-14 so that file could get back under the 200,000-char
	-- `Script.Source` WRITE cap (docs/lessons/
	-- the-200k-source-cap-is-on-writing-not-loading.md). Neither is a control;
	-- the RowActions row itself is swept and is the thing that mounts them.
	RowActionsSpec = "pure ActionSpec validation and leaf string/id helpers — no blueprint, nothing to mount or "
		.. "measure. The tray buttons its output describes are swept through the RowActions fixture",
	RowActionsCoordinator = "three closures over one plain local (which row is open) — no blueprint, nothing to "
		.. "mount or measure. The rows it coordinates are swept through the RowActions fixture",
	RowActionsReorder = "a pointer-gesture arbiter over two handler tables — no blueprint, nothing to mount or "
		.. "measure. The rows it arbitrates for are swept through the RowActions and Table fixtures",
	RowActionsMetrics = "theme-metric resolution and band arithmetic — no blueprint, nothing to mount or measure. "
		.. "The plates whose widths it decides are swept through the RowActions fixture, at every preference",
	RowActionsTrays = "the VIEW half of RowActions: it returns the tray blueprints the RowActions fixture itself "
		.. "mounts, so it is swept there — at every preference, in both reference themes — rather than twice",
	RowActionsRoot = "the NODE half of RowActions: it returns the row blueprint the RowActions fixture itself "
		.. "mounts, so it is swept there — at every preference, in both reference themes — rather than twice",
	-- the reorder/drop/autoscroll half of src/controls/virtual_list.luau, lifted
	-- out on 2026-08-15 so that file could get back under the same cap. Not a
	-- control; the VirtualList row itself is swept and is the thing that mounts it.
	VirtualReorder = "the DRAG half of VirtualList: canvas-offset arithmetic, reorder commits, slide springs and "
		.. "the edge-autoscroll model — no blueprint, nothing to mount or measure. The rows it moves are swept "
		.. "through the VirtualList fixture, at every preference",
	VirtualWindow = "the WINDOWING arithmetic of VirtualList: a running-offset index and the memos over it — no "
		.. "blueprint, nothing to mount or measure. The rows it windows are swept through the VirtualList "
		.. "fixture, at every preference, and the measured-extent form is what that sweep re-measures",
	NativeScrollBinding = "the engine scroll mirror's arbitration (O-31, 2026-08-15): it decides WHEN a mirror "
		.. "is installed and hands every caller one stop function — no blueprint, no text, nothing to mount or "
		.. "measure. The collections whose scroll it arbitrates are swept through the VirtualList, VirtualGrid "
		.. "and Table fixtures, at every preference",
	Stage = "the engine-content box draws no text and holds no control: it is a rectangle whose contents are a "
		.. "3D scene the ENGINE renders, so there is nothing for a text-preference sweep to overlap, clip or "
		.. "push under a hit floor. Text ABOUT a stage (a caption, a label) is an ordinary UI.Text beside it "
		.. "and is swept as one",
}

fixtures.FIXTURES = FIXTURES
fixtures.UNSWEEPABLE = UNSWEEPABLE

return fixtures
