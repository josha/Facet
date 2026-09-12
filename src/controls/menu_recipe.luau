--!strict
--[[ THE MENU ROW, AND THE RULE FOR HOW A MENU IS PRESENTED — the one copy of
	both (navigation-and-menus brief §2 D2; director call §5, 2026-08-16).

	Three controls now render an action list: `row_actions`' floating menu (the
	first, and the one that wrote the recipe), `popup_button`'s option panel, and
	the freestanding `menu`. Before this module there were two copies of the row
	and one copy of the presentation rule sitting inside a control that is not the
	only one that needs it. The director's call names the cost exactly: *"three
	copies of a menu row is how the icon-first ruling gets silently lost"*.

	WHAT MOVED HERE, AND WHAT DELIBERATELY DID NOT CHANGE ON THE WAY.

	  * `resolvePresentation` is `popup_button.resolvePresentation` RELOCATED, not
	    rewritten — same three rules, same order, same numbers. It was already a
	    pure function of three primitives with no env read, which is why this is a
	    move. `popup_button.resolvePresentation` still exists and still answers;
	    it is now an alias, so no caller and no doc line changes.
	  * `row` is `row_actions.buildMenuRows`'s per-row body, lifted verbatim for
	    the LEAF case: a `UI.Button` carrying `label`, `compactLabel = { icon }`,
	    `role`, a fill width and the fixed themed row height. Byte-for-byte the
	    same props, because `row_actions_input.spec` pins two things that a
	    reshaped row would break silently — `MenuRows` must stay "a padding-free
	    VStack of fixed-height rows" for its own flip prediction to be exact, and
	    `controller.textAt(<row path>)` must answer for the row's own label.

	THE RULING THIS FILE EXISTS TO KEEP (director, device round 2026-08-12,
	carried over from `row_actions.luau` rather than re-derived): a menu row keeps
	its LABEL, and there is DELIBERATELY NO `prefer`. Icon-first is the TRAY's
	inversion. *"A menu row is a list of names — it is where the words live, and
	it is the reading of the tray a player reaches for when a glyph is not
	enough."* The icon therefore rides `compactLabel`, which draws it only when
	the words genuinely do not fit; a fill-width menu row rarely runs out of room,
	so this mostly keeps the label, and that is the correct default for a menu
	rather than a defect.

	THE ONE ROW SHAPE THAT IS NOT THE SHIPPED ONE, AND WHY. A SUBMENU row has to
	show a trailing chevron — the guidance: a menu item indicates the presence of a
	submenu by displaying a symbol — like a chevron — after its label."* A `Button`
	is a container (B-BTN1), so an accessory means moving the visible label into
	content, exactly as `disclosure_group`'s header does for its caret: `label`
	stays the semantic name every assistive reader and every contract wants, the
	visible text becomes a fill `UI.Text`, and the chevron is its own node
	carrying the semantic icon NAME beside its ASCII glyph so a theme package can
	paint art over it. Leaf rows never take this form, so
	`row_actions` — which has no submenus — renders the identical tree it always
	did.

	THE TWO GUIDANCE LINTS LIVE HERE TOO, because they are properties of a menu's
	ITEMS and both menus author items: icons are per-group all-or-nothing, and a
	group of more than about five items wants its own menu.
]]

local themePackage = require("../themes/package")
local chrome_slots = require("../tokens/chrome_slots")

local guard = require("../spec_guard")
local selection = require("../selection_model")
local menu_recipe = {}
-- Shared content for semantic setting/action rows. Accessories are inert; the
-- owning Button, Toggle or Slider retains the single input identity.
function menu_recipe.semantic(UI, core, scope, label, spec, value)
	guard.assertKnownKeys("control.row", spec, guard.keySet({ "description", "icon", "value" }), "row")
	for _, key in { "description", "icon", "value" } do
		local v = selection.read(spec[key])
		assert(v == nil or type(v) == "string", "control.row: " .. key .. " must be string or readable string")
	end
	return table.clone(menu_recipe.row(UI, {
		id = "RowContent",
		wrap = true,
		label = label or "",
		description = spec.description or "",
		icon = spec.icon,
		value = value or spec.value,
		core = core,
		scope = scope,
	}).children)
end

--[[ THEME METRICS, never bare pixels. The three row heights ARE
	the three control sizes — compact for the pointer menu, regular for the inline
	list, large for the touch sheet — so a theme that retunes its control ladder
	retunes every menu with it. A touch SHEET uses a visually larger row, not just
	a hit-floored one: on a finger the target should look as big as it is (B-DSP3). ]]
menu_recipe.ROW_HEIGHT = "controlSizes.compact.height"
menu_recipe.SHEET_ROW_HEIGHT = "controlSizes.large.height"
menu_recipe.INLINE_ROW_HEIGHT = "controlSizes.regular.height"
-- the hairline of surface showing between two rows
menu_recipe.ROW_GAP = "strokes.hairline"

--[[ THE CARD, AND THE PAINT A ROW INSIDE ONE TAKES (user review of the desktop
	split button, 2026-09-12: *"the open menu still reads as stacked rounded
	rects"*). The picker's popover settled the SHAPE of the answer one round
	earlier and these four constants are that ruling, named once so the freestanding
	menu and the picker menu cannot drift:

	  * the PANEL is the plate. `surface = "raised"` already carries the corner and
	    the stroke, so a row inside it owns neither — a row that keeps its own
	    control radius is what makes a list read as a stack of separate buttons.
	  * a row therefore rests at `plain` (paints nothing at all — `chrome_slots`:
	    "AN EXPLICIT `plain` PAINTS NOTHING, including chrome") and the hairline
	    between two rows is the only rhythm.
	  * the SELECTED row's fill is the row's own `surface`, which is what makes
	    "the fill fits the row exactly" true BY CONSTRUCTION rather than by two
	    boxes agreeing about a rectangle. It is `accent`, with the label at
	    `onAccent`, because that is the ONE pair every theme of every package
	    guarantees (`gateTheme` refuses a package whose accent pair reads below
	    4.5:1, and `tests/selection_contrast.spec.luau` re-asks it of every shipped
	    theme). `controlSelected` is deliberately NOT the fill here: its readable
	    partner is `$OnSelected`, a token only the STYLE SHEET can resolve — a
	    child `UI.Text` (which is what a row with a check, an icon or a description
	    draws its label into) has no route to it, so pairing a label with that fill
	    from the decision layer means guessing, and the guess is wrong on two of the
	    eleven shipped themes in each direction. See the spec for the measurements.
	  * the ends of the card are the ends of the FIRST and LAST rows, so those two
	    take the panel's radius on their outer corners and 0 everywhere else. A
	    square row corner inside a rounded card paints over the card's arc; the
	    engine does not clip a child to a parent's `UICorner`. ]]
menu_recipe.CARD_CORNER = "panel"
menu_recipe.SELECTED_SURFACE = "accent"
menu_recipe.SELECTED_LABEL_ROLE = "onAccent"
menu_recipe.RESTING_SURFACE = "plain"
menu_recipe.RESTING_LABEL_ROLE = "content"

-- Guidance: if a submenu contains more than about five items, consider creating a
-- new menu". Advice, so it is a diagnostic rather than a refusal.
menu_recipe.GROUP_SIZE_ADVICE = 5
-- Guidance: it can be difficult for people to reveal multiple levels of hierarchical
-- submenus, so it's generally best to restrict them to a single level. Nothing
-- documents no structural cap, so neither does this: depth is UNBOUNDED and a
-- second level of nesting is diagnosed, never refused (director ruling §6.4).
menu_recipe.DEPTH_ADVICE = 2

--[[ ADAPTIVE PRESENTATION (acceptance row B-DSP3), RELOCATED FROM
	`popup_button.resolvePresentation` UNCHANGED. The choice comes from the item
	count, the available SPACE class, and whether touch is the PRIMARY interaction
	class (`touchPrimary` below — ADAPT-9: merely HAVING touch is what put a sheet
	on a mouse-driven touchscreen laptop) — never from a device name. Pure and exported so a caller can predict it.

	  menu    the floating panel. The desktop/pointer idiom.
	  inline  rows in place, no separate panel surface. Good for a couple of
	          options with room to show them.
	  sheet   a bottom-anchored, full-width surface with larger rows. The touch
	          idiom, and the fallback when a compact space cannot hold a long menu. ]]
--[[ IS TOUCH THE PRIMARY WAY IN? (audit 2026-08-18.)

	The rung below used to be asked with `classes.touch == true` at both call
	sites — "touch is available at all" — which puts a SHEET on a touchscreen
	laptop that is being driven with a mouse. `src/env/environment.luau` already
	settled that argument for the whole framework: "A mouse still wins outright,
	which keeps every desktop and every hybrid (touchscreen laptop) exactly where
	it was." So the question is which class is PRIMARY, and it is asked here, once,
	rather than spelled twice in two controls. ]]
function menu_recipe.touchPrimary(classes: any): boolean
	if type(classes) ~= "table" then
		return false
	end
	local primary = (classes :: any).primary
	if primary ~= nil then
		return primary == "touch"
	end
	--[[ A TABLE THAT NEVER SAID WHICH CLASS IS PRIMARY (re-review MEDIUM-2).
		`interactionClasses` is typed `table | Readable`, and a HAND-AUTHORED one —
		a fixture, a consumer driving its own class set from a Signal — may carry
		`touch = true` and no `primary` at all. Reading `primary` alone made that
		table resolve a MENU where it used to resolve a sheet: a silent idiom
		regression, which is the exact failure class this wave exists to end, arriving
		through the fix for it.

		So the fallback is EXPLICIT and it is the older meaning: a table with no
		primary has said only "touch is live", and the only thing that can mean is the
		answer it has always given. A REFUSAL was the other candidate and is wrong
		here — it would turn a shape that worked yesterday into a build error, in a
		control whose facts normally arrive from an environment that always declares
		`primary`, so the loudness would land on the one caller who is not the problem.
		Both shapes are specced (`menu.spec`). ]]
	return (classes :: any).touch == true
end

function menu_recipe.resolvePresentation(
	optionCount: number,
	sizeClass: string?,
	touchLive: boolean?,
	gamepadPrimary: boolean?
): string
	if touchLive == true then
		return "sheet"
	end
	if (sizeClass == "compact" or gamepadPrimary == true) and optionCount > 6 then
		return "sheet"
	end
	if optionCount <= 3 and sizeClass ~= "compact" then
		return "inline"
	end
	return "menu"
end

--[[ THE PICKER MENU'S OWN LADDER (Picker `style = "menu"`, 2026-09-11). The
	reference-platform-shaped picker presents its options ANCHORED to the trigger — the
	menu that pops from a form row on a phone and from a pop-up button on a
	desktop — and only reaches for the bottom sheet when the list cannot be a
	popover: a gamepad (one panel, focus-navigable, the same call `newMenu`
	makes), or more rows than a thumb-sized panel holds on a compact or touch
	surface. `inline` is deliberately absent: a picker that wanted rows in place
	declares `style = "inline"`, which is a strip, not a popup. Pure, exported,
	and separate from `resolvePresentation` above so the action menu's own
	touch->sheet ruling is untouched. ]]
menu_recipe.PICKER_POPOVER_LIMIT = 6
function menu_recipe.resolvePickerPresentation(
	optionCount: number,
	sizeClass: string?,
	touchLive: boolean?,
	gamepadPrimary: boolean?
): string
	if gamepadPrimary == true then
		return "sheet"
	end
	if (sizeClass == "compact" or touchLive == true) and optionCount > menu_recipe.PICKER_POPOVER_LIMIT then
		return "sheet"
	end
	return "menu"
end

-- the themed row height for a resolved presentation. One place, so a menu and a
-- popup at the same presentation can never disagree about how tall a row is.
function menu_recipe.rowHeightFor(presentation: string): string
	if presentation == "sheet" then
		return menu_recipe.SHEET_ROW_HEIGHT
	elseif presentation == "inline" then
		return menu_recipe.INLINE_ROW_HEIGHT
	end
	return menu_recipe.ROW_HEIGHT
end

export type Row = {
	wrap: boolean?, -- wrap a labelled badge row when its offer is narrow
	labelTint: any?, -- optional semantic label paint, e.g. a selection indicator
	width: any?,
	textSize: any?,
	iconOnly: boolean?,
	core: any?, -- required with scope for readable icon or badge
	scope: any?,
	badge: any?, -- string | number | Readable; empty removes the badge paint
	surface: any?,
	value: any?,
	description: any?,
	markHidden: any?,
	--[[ THE CARD PAINTS THE SELECTION, so the Button must not also carry the
		`facet-selected` style tag: the sheet's `Selected row` rule owns
		BackgroundColor3 AND TextColor3 wherever that tag lands, which would repaint
		the card row's own surface out from under it and leave the two forms of one
		row (a leaf's drawn label, a content row's child `UI.Text`) sitting on two
		different fills. `selected` stays the row's source of truth for the check
		mark and for `cardRow`'s surface; it just stops being a paint channel.
		Nothing else in the library sets this — every other caller keeps the sheet's
		treatment byte for byte. ]]
	platedSelection: boolean?,
	indicator: string?, -- "radio" | "check" | "mark" (the picker menu's check-only slot)
	indicatorEdge: string?, -- "leading" (default) | "trailing": the picker menu's check sits at the row's trailing edge under touch
	id: string, -- the path segment, already prefixed by the caller
	label: any, -- string | number | Readable — the SEMANTIC name, always present
	icon: any?, -- semantic icon NAME or Readable<string?>, never an asset id
	role: string?, -- "default" (the fallback) | "destructive"
	enabled: any?, -- boolean | Readable<boolean>
	selected: any?, -- Readable<boolean>, for a menu that also marks a current value
	submenu: boolean?, -- true draws the trailing chevron and takes the content form
	height: (string | number)?, -- the themed row height; defaults to the compact one
}

--[[ ONE MENU ROW. `UI` is the blueprint library the caller already holds
	(`Facet.UI`), passed rather than required so this module stays free of the
	init cycle every control avoids the same way. ]]
function menu_recipe.row(UI: any, row: Row): any
	local height = { type = "fixed", px = row.height or menu_recipe.ROW_HEIGHT }
	local function readable(value)
		return type(value) == "table" and (value.kind == "signal" or value.kind == "memo")
	end
	local function read(value, use)
		return if readable(value) then use(value) else value
	end
	local liveIcon = readable(row.icon)
	if liveIcon or readable(row.badge) then
		assert(row.core and row.scope, "menu row: readable icon and badge require core and scope")
	end
	-- see `platedSelection`: the tag is the SHEET's selection paint, and a card row
	-- has already painted its own
	local buttonSelected = if row.platedSelection == true then nil else row.selected

	if row.description ~= nil or row.indicator ~= nil or liveIcon or row.badge ~= nil then
		local content = {}
		-- the indicator slot, placed leading (a desktop menu) or trailing (a
		-- phone menu marks the chosen row at its far edge — `indicatorEdge`)
		local indicatorView: any = nil
		if row.indicator ~= nil then
			--[[ `mark` is the PICKER MENU's indicator (2026-09-11): the check
				alone, in a reserved slot, with NO resting outline — the row that is
				not chosen shows an empty slot, exactly as a pop-up menu on every
				desktop and the menu picker on a phone draw it. `radio` and `check`
				keep their resting ring/box, which is what makes them read as a
				toggle rather than a current value. ]]
			--[[ THE CHARACTER IS THE TABLE'S, NEVER A LITERAL (2026-09-11). Both
				marks used to author their own text — `"o"`, `"[]"`, `"*"` — beside an
				icon hint naming a rung that had no art, so what a player actually saw
				in Studio was those three characters, in every theme, forever. Two
				separate defects sat in one line: no art existed for the names (fixed
				in `standard_icons`), and the floor beneath them was hand-written here
				rather than in `ICON_FALLBACK_GLYPHS`, so it could never be resolved,
				tinted, suppressed under art, or seen by a coverage check. Every glyph
				now comes from the ONE table the resolution ladder reads, which is what
				makes "the ASCII floor is a recovery path" a checkable claim. ]]
			local indicatorChildren = {}
			local offName = if row.indicator == "radio"
				then "facet:selection.radio.off"
				else "facet:selection.check.off"
			local onName = if row.indicator == "radio" then "facet:selection.radio.on" else "checkmark"
			if row.indicator ~= "mark" then
				table.insert(
					indicatorChildren,
					chrome_slots.attachHint(
						UI.Text({
							id = "Outline",
							tint = row.labelTint,
							hidden = row.selected,
							text = themePackage.iconGlyph(offName),
							textSize = "control",
							textAlign = "center",
							width = { type = "fill", weight = 1 },
						}),
						{ icon = offName }
					)
				)
			end
			table.insert(
				indicatorChildren,
				chrome_slots.attachHint(
					UI.Text({
						id = "Mark",
						tint = row.labelTint,
						hidden = row.markHidden,
						text = themePackage.iconGlyph(onName),
						textSize = "control",
						textAlign = "center",
						width = { type = "fill", weight = 1 },
					}),
					{ icon = onName }
				)
			)
			indicatorView = UI.ZStack({
				id = "Indicator",
				width = { type = "minMax", min = "l" },
				height = { type = "minMax", min = "l" },
				children = indicatorChildren,
			})
			if row.indicatorEdge ~= "trailing" then
				table.insert(content, indicatorView)
			end
		end
		local function iconView(icon)
			return chrome_slots.attachHint(
				UI.Text({
					id = "Icon",
					tint = row.labelTint,
					text = themePackage.iconGlyph(icon) or "•",
					textSize = row.textSize or "control",
					width = { type = "minMax", min = "l" },
				}),
				{ icon = icon }
			)
		end
		if liveIcon then
			local icons = row.scope:own(row.core:memo(function(use)
				local icon = read(row.icon, use)
				return if icon == nil or icon == "" then {} else { icon }
			end))
			table.insert(
				content,
				UI.ForEach({
					id = "Icons",
					items = icons,
					key = function(icon)
						return icon
					end,
					row = function(icon)
						return iconView(icon)
					end,
				})
			)
		elseif row.icon ~= nil then
			table.insert(content, iconView(row.icon))
		end

		if not row.iconOnly then
			local labels = {
				UI.Text({
					id = "Label",
					tint = row.labelTint,
					text = row.label,
					textSize = row.textSize or "control",
					width = if row.wrap then UI.hug() else { type = "fill", weight = 1 },
				}),
			}
			local function description()
				return UI.Text({
					id = "Description",
					tint = row.labelTint,
					text = row.description,
					textSize = "caption",
					role = "secondary",
					width = { type = "fill", weight = 1 },
				})
			end
			if readable(row.description) and row.core and row.scope then
				table.insert(
					labels,
					UI.When({
						id = "DescriptionWhen",
						condition = row.scope:own(row.core:memo(function(use)
							local value = use(row.description)
							return value ~= nil and value ~= ""
						end)),
						thenView = description,
					})
				)
			elseif row.description ~= nil and row.description ~= "" then
				table.insert(labels, description())
			end
			table.insert(
				content,
				UI.VStack({
					gap = "xs",
					width = if row.wrap then UI.hug() else { type = "fill", weight = 1 },
					children = labels,
				})
			)
		end
		if row.value ~= nil then
			table.insert(
				content,
				UI.Text({
					id = "Value",
					tint = row.labelTint,
					text = row.value,
					textSize = "control",
					role = "secondary",
				})
			)
		end
		if row.badge ~= nil then
			local badge = if readable(row.badge)
				then row.scope:own(row.core:memo(function(use)
					local value = read(row.badge, use)
					return if value == nil then "" else tostring(value)
				end))
				else tostring(row.badge)
			local hidden = if readable(badge)
				then row.scope:own(row.core:memo(function(use)
					return use(badge) == ""
				end))
				else badge == ""
			table.insert(
				content,
				UI.Text({
					id = "Badge",
					text = badge,
					hidden = hidden,
					surface = "badge",
					textSize = "caption",
					padding = { left = "xs", right = "xs" },
					corners = UI.cornersData("pill"),
				})
			)
		end
		if row.indicatorEdge == "trailing" and indicatorView ~= nil then
			table.insert(content, indicatorView)
		end
		return UI.Button({
			id = row.id,
			label = row.label,
			role = row.role or "default",
			surface = row.surface,
			enabled = row.enabled,
			selected = buttonSelected,
			width = row.width or { type = "fill", weight = 1 },
			height = { type = "minMax", min = row.height or "targetSizes.minimum" },
			children = {
				UI.HStack({
					wrap = row.wrap,
					gap = "s",
					width = if row.wrap then UI.hug() else { type = "fill", weight = 1 },
					children = content,
				}),
			},
		})
	end
	if row.submenu ~= true then
		-- THE SHIPPED LEAF ROW, unchanged from `row_actions.buildMenuRows`.
		return UI.Button({
			id = row.id,
			label = row.label,
			-- `icon` alone needs `shape = "circle"`, and a menu row keeps its label,
			-- so the action icon rides `compactLabel`. See this file's header for
			-- the ruling that forbids `prefer` here.
			compactLabel = if row.icon ~= nil then { icon = row.icon } else nil,
			role = if row.role == "destructive" then "destructive" else "default",
			-- the card's rows go `plain` and the selected one takes the card's own
			-- fill; every other caller leaves this nil and keeps the control plate
			surface = row.surface,
			enabled = row.enabled,
			selected = buttonSelected,
			width = { type = "fill", weight = 1 },
			height = height,
		})
	end
	--[[ THE SUBMENU ROW: a CONTENT button (B-BTN1). The visible label moves into a
		child so the chevron can sit after it, and `label` stays the semantic name.
		The caret draws the framework's ASCII-safe glyph itself and carries the
		semantic icon NAME beside it, so an installed theme package paints its art
		over the character and a package that ships none still reads (the semantic-icon rule —
		`disclosure_group`'s caret makes the identical argument). ]]
	local glyph = themePackage.iconGlyph("chevron.trailing") or ">"
	return UI.Button({
		id = row.id,
		label = row.label,
		role = if row.role == "destructive" then "destructive" else "default",
		surface = row.surface,
		enabled = row.enabled,
		selected = buttonSelected,
		gap = "xs",
		width = { type = "fill", weight = 1 },
		height = height,
		children = {
			UI.Text({
				id = "Label",
				-- the same pairing every other content row takes: a submenu row on a
				-- card is selectable too, and its label is a CHILD, so the sheet's
				-- own `TextButton` colour rules cannot reach it (see CARD_CORNER)
				tint = row.labelTint,
				text = row.label,
				-- the SAME role the renderer gives a Button's own text, so moving the
				-- label into content changes no geometry
				textSize = "control",
				width = { type = "fill", weight = 1 },
			}),
			chrome_slots.attachHint(
				UI.Text({ id = "Chevron", tint = row.labelTint, text = glyph, textSize = "control" }),
				{ icon = "chevron.trailing" }
			),
		},
	})
end

--[[ WHERE A ROW SITS IN THE CARD, as the four radii it therefore carries.
	`only` is the one-row menu, which is the whole plate and takes all four. Pure
	and exported so a test can ask the same question the panel does. ]]
function menu_recipe.cardCorners(position: string): any
	local top = position == "first" or position == "only"
	local bottom = position == "last" or position == "only"
	local corner = menu_recipe.CARD_CORNER
	return {
		topLeft = if top then corner else 0,
		topRight = if top then corner else 0,
		bottomLeft = if bottom then corner else 0,
		bottomRight = if bottom then corner else 0,
	}
end

--[[ ONE ROW OF THE CARD: `menu_recipe.row`, plus the three things a flat row
	inside one plate owes (see CARD_CORNER above) — its resting/selected surface,
	the label colour that pairs with the selected one, and its share of the card's
	corner.

	`slot = "none"` rides along because the selected row's surface classifies as a
	`control` decoration slot: without it a skinned package paints a whole button
	picture over the one row that is supposed to read as a fill inside the card,
	and the paired label is then sitting on art rather than on `$Accent`. It is the
	same declaration `selection_indicator` makes for its pill, for the same reason
	it gives: *"arbitrary control artwork can replace that fill with dark pixels,
	breaking the paired label"*. The hint is inert while the row rests at `plain`,
	which classifies to no slot anyway.

	The tint NAMES BOTH ENDS — `content` when the row is not selected, never nil —
	which is `picker`'s own idiom for the same job one control over (its pill-plated
	segment label). A bound paint that resolves to nil RELEASES its claim, and a
	release restores whatever the property held when the claim was taken, which on a
	recycled instance is the previous occupant's colour rather than this theme's.
	Naming the resting end costs one property write and cannot be stale. It is also
	free of the disabled state: that dims `TextTransparency` (`Disabled subtree
	text`), never the colour, so a colour claim takes nothing away from it. ]]
function menu_recipe.cardRow(UI: any, core: any, scope: any, row: Row, position: string): any
	local spec: any = table.clone(row)
	local selected = row.selected
	if type(selected) == "table" and (selected.kind == "signal" or selected.kind == "memo") then
		assert(core ~= nil and scope ~= nil, "menu card row: a reactive `selected` requires core and scope")
		spec.surface = scope:own(core:memo(function(use)
			return if use(selected) then menu_recipe.SELECTED_SURFACE else menu_recipe.RESTING_SURFACE
		end))
		spec.labelTint = scope:own(core:memo(function(use)
			return {
				role = if use(selected) then menu_recipe.SELECTED_LABEL_ROLE else menu_recipe.RESTING_LABEL_ROLE,
				blend = 1,
			}
		end))
	else
		local on = selected == true
		spec.surface = if on then menu_recipe.SELECTED_SURFACE else menu_recipe.RESTING_SURFACE
		spec.labelTint =
			{ role = if on then menu_recipe.SELECTED_LABEL_ROLE else menu_recipe.RESTING_LABEL_ROLE, blend = 1 }
	end
	return chrome_slots.attachHint(
		UI.corners(menu_recipe.row(UI, spec), menu_recipe.cardCorners(position)),
		{ slot = chrome_slots.NO_SLOT }
	)
end

--[[ A DIVIDER ITEM. `UI.Divider` is the shipped axis-aware hairline (A-LV3): it
	infers its orientation from the stack it is in, so the same call is correct in
	a vertical menu panel and would be correct in a horizontal one. It is not
	focusable and carries no action, which is the whole point — a divider groups,
	it never responds. ]]
function menu_recipe.divider(UI: any, id: string): any
	return UI.Divider({ id = id, width = { type = "fill", weight = 1 } })
end

--[[ THE ICON LINT: provide icons for all menu items in a group, or none of
	them"). A GROUP is the run of action items between two dividers — which is what
	makes this checkable at authoring time rather than a taste call: the author has
	already said where the groups are. Returns the 1-based index of the first item
	in the first mixed group, or nil.

	This is the lint that keeps D2's new `icon` field from being a free-for-all: a
	half-iconned group looks fine in the one fixture it was authored in and reads
	as a rendering bug everywhere else. ]]
function menu_recipe.mixedIconGroup(items: { any }): number?
	local groupStart: number? = nil
	local withIcon, without = 0, 0
	local function verdict(): number?
		if withIcon > 0 and without > 0 then
			return groupStart
		end
		return nil
	end
	for index, item in items do
		if type(item) ~= "table" then
			continue
		end
		if item.divider == true then
			local bad = verdict()
			if bad ~= nil then
				return bad
			end
			groupStart, withIcon, without = nil, 0, 0
			continue
		end
		if groupStart == nil then
			groupStart = index
		end
		if item.icon ~= nil then
			withIcon += 1
		else
			without += 1
		end
	end
	return verdict()
end

--[[ THE GROUP-SIZE ADVICE: if a submenu contains more than about five
	items, consider creating a new menu"). Counts ACTIONABLE items only — a
	divider is the author grouping, not another thing to read — and answers with
	the count so the diagnostic can name it. ]]
function menu_recipe.actionableCount(items: { any }): number
	local n = 0
	for _, item in items do
		if type(item) == "table" and item.divider ~= true then
			n += 1
		end
	end
	return n
end

return menu_recipe
