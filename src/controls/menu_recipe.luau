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
	show a trailing chevron — HIG: *"A menu item indicates the presence of a
	submenu by displaying a symbol — like a chevron — after its label."* A `Button`
	is a container (B-BTN1), so an accessory means moving the visible label into
	content, exactly as `disclosure_group`'s header does for its caret: `label`
	stays the semantic name every assistive reader and every contract wants, the
	visible text becomes a fill `UI.Text`, and the chevron is its own node
	carrying the semantic icon NAME beside its ASCII glyph so a theme package can
	paint art over it (ADR-0020 R4). Leaf rows never take this form, so
	`row_actions` — which has no submenus — renders the identical tree it always
	did.

	THE TWO HIG LINTS LIVE HERE TOO, because they are properties of a menu's
	ITEMS and both menus author items: icons are per-group all-or-nothing, and a
	group of more than about five items wants its own menu.
]]

local themePackage = require("../themes/package")
local chrome_slots = require("../tokens/chrome_slots")

local menu_recipe = {}

--[[ THEME METRICS (ADR-0019 §2), never bare pixels. The three row heights ARE
	the three control sizes — compact for the pointer menu, regular for the inline
	list, large for the touch sheet — so a theme that retunes its control ladder
	retunes every menu with it. A touch SHEET uses a visually larger row, not just
	a hit-floored one: on a finger the target should look as big as it is (B-DSP3). ]]
menu_recipe.ROW_HEIGHT = "controlSizes.compact.height"
menu_recipe.SHEET_ROW_HEIGHT = "controlSizes.large.height"
menu_recipe.INLINE_ROW_HEIGHT = "controlSizes.regular.height"
-- the hairline of surface showing between two rows
menu_recipe.ROW_GAP = "strokes.hairline"

-- HIG: "if a submenu contains more than about five items, consider creating a
-- new menu". Advice, so it is a diagnostic rather than a refusal.
menu_recipe.GROUP_SIZE_ADVICE = 5
-- HIG: "It can be difficult for people to reveal multiple levels of hierarchical
-- submenus, so it's generally best to restrict them to a single level." SwiftUI
-- documents no structural cap, so neither does this: depth is UNBOUNDED and a
-- second level of nesting is diagnosed, never refused (director ruling §6.4).
menu_recipe.DEPTH_ADVICE = 2

--[[ ADAPTIVE PRESENTATION (acceptance row B-DSP3), RELOCATED FROM
	`popup_button.resolvePresentation` UNCHANGED. The choice comes from the item
	count, the available SPACE class, and whether touch is a LIVE interaction
	class — never from a device name. Pure and exported so a caller can predict it.

	  menu    the floating panel. The desktop/pointer idiom.
	  inline  rows in place, no separate panel surface. Good for a couple of
	          options with room to show them.
	  sheet   a bottom-anchored, full-width surface with larger rows. The touch
	          idiom, and the fallback when a compact space cannot hold a long menu. ]]
function menu_recipe.resolvePresentation(optionCount: number, sizeClass: string?, touchLive: boolean?): string
	if touchLive == true then
		return "sheet"
	end
	if sizeClass == "compact" and optionCount > 6 then
		return "sheet"
	end
	if optionCount <= 3 and sizeClass ~= "compact" then
		return "inline"
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
	id: string, -- the path segment, already prefixed by the caller
	label: any, -- string | number | Readable — the SEMANTIC name, always present
	icon: string?, -- semantic icon NAME, never an asset id
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
			enabled = row.enabled,
			selected = row.selected,
			width = { type = "fill", weight = 1 },
			height = height,
		})
	end
	--[[ THE SUBMENU ROW: a CONTENT button (B-BTN1). The visible label moves into a
		child so the chevron can sit after it, and `label` stays the semantic name.
		The caret draws the framework's ASCII-safe glyph itself and carries the
		semantic icon NAME beside it, so an installed theme package paints its art
		over the character and a package that ships none still reads (ADR-0020 R4 —
		`disclosure_group`'s caret makes the identical argument). ]]
	local glyph = themePackage.iconGlyph("chevron.trailing") or ">"
	return UI.Button({
		id = row.id,
		label = row.label,
		role = if row.role == "destructive" then "destructive" else "default",
		enabled = row.enabled,
		selected = row.selected,
		gap = "xs",
		width = { type = "fill", weight = 1 },
		height = height,
		children = {
			UI.Text({
				id = "Label",
				text = row.label,
				-- the SAME role the renderer gives a Button's own text, so moving the
				-- label into content changes no geometry
				textSize = "control",
				width = { type = "fill", weight = 1 },
			}),
			chrome_slots.attachHint(
				UI.Text({ id = "Chevron", text = glyph, textSize = "control" }),
				{ icon = "chevron.trailing" }
			),
		},
	})
end

--[[ A DIVIDER ITEM. `UI.Divider` is the shipped axis-aware hairline (A-LV3): it
	infers its orientation from the stack it is in, so the same call is correct in
	a vertical menu panel and would be correct in a horizontal one. It is not
	focusable and carries no action, which is the whole point — a divider groups,
	it never responds. ]]
function menu_recipe.divider(UI: any, id: string): any
	return UI.Divider({ id = id, width = { type = "fill", weight = 1 } })
end

--[[ THE ICON LINT (HIG: "provide icons for all menu items in a group, or none of
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

--[[ THE GROUP-SIZE ADVICE (HIG: "if a submenu contains more than about five
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
