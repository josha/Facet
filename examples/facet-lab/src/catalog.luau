--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type CellFactory = typeof(require("@repo/tools/typecheck/aliases").CellFactory)
type BooleanCell = typeof(require("@repo/tools/typecheck/aliases").BooleanCell)
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type FacetModule = typeof(require("@repo/tools/typecheck/aliases").FacetModule)
type App = typeof(require("@repo/tools/typecheck/aliases").App)
type ControlSize = typeof(require("@repo/tools/typecheck/aliases").ControlSizeValue)
type MenuItem = typeof(require("@repo/tools/typecheck/aliases").MenuItem)
type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
type OverlayAction = typeof(require("@repo/tools/typecheck/aliases").OverlayAction)
type DialogAction = typeof(require("@repo/tools/typecheck/aliases").DialogAction)
type TableColumn = typeof(require("@repo/tools/typecheck/aliases").TableColumn)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type SheetDetent = typeof(require("@repo/tools/typecheck/aliases").SheetDetent)
type DropInfo = typeof(require("@repo/tools/typecheck/aliases").DropInfo)
type Readable<T> = { peek: (Readable<T>) -> T }
type Cell<T> = Readable<T> & { set: (Cell<T>, T) -> (), update: (Cell<T>, (T) -> T) -> () }
type Use = <T>(Readable<T>) -> T

local CatalogTypes = require("./catalog_types")
export type Context = CatalogTypes.Context
export type Properties = CatalogTypes.Properties
export type Builder = CatalogTypes.Builder
export type Source = CatalogTypes.Source
export type Axis = CatalogTypes.Axis
export type State = CatalogTypes.State
export type Make = CatalogTypes.Make
export type Valid = CatalogTypes.Valid
export type PageDefinition = CatalogTypes.PageDefinition

local catalog = {}

catalog.NONE = table.freeze({})
local NONE = catalog.NONE
local VIRTUAL_DEMOS = {
	"selectionFrom",
	"selectionIndicator",
	"rowActions",
	"minColumnWidth",
	"minColumns",
	"slots",
	"slotControls",
}

catalog.DEFAULT = "(default)"
local DEFAULT = catalog.DEFAULT

local ART = "rbxassetid://75342910516929"
type Row = { id: string, name: string, laps: number }
local ROWS: { Row } = {
	{ id = "1", name = "Coastal Circuit", laps = 3 },
	{ id = "2", name = "Canyon Run", laps = 5 },
	{ id = "3", name = "City Loop", laps = 4 },
	{ id = "4", name = "Glacier Pass", laps = 2 },
	{ id = "5", name = "Harbour Sprint", laps = 6 },
	{ id = "6", name = "Desert Dunes", laps = 3 },
}

local function properties(values: Properties): Properties
	return values
end

local nativeGlyph = require("./native_glyph")
local splitBack = require("./split_back_demo")

local function implied(choices: { [string]: Source }): { [string]: Source }
	return choices
end

local function stacked(props: StackProps): StackProps
	return props
end

local function menuList(items: { MenuItem }): { MenuItem }
	return items
end

local function optionList(options: { PickerOption }): { PickerOption }
	return options
end

local function actionList(actions: { OverlayAction }): { OverlayAction }
	return actions
end

local function dialogActions(actions: { DialogAction }): { DialogAction }
	return actions
end

local function columnList(columns: { TableColumn }): { TableColumn }
	return columns
end

local function reorderRows(c: Context, rows: Cell<{ Row }>)
	return function(keys: { string }, slot: number)
		local remaining: { Row }, moved: { Row } = {}, {}
		for _, row in rows:peek() do
			table.insert(if table.find(keys, row.id) then moved else remaining, row)
		end
		for index, row in moved do
			table.insert(remaining, slot + index, row)
		end
		rows:set(remaining)
		c.log("onReorder")(keys, slot)
	end
end

local function transferState(c: Context): Properties
	return require("./collection_transfer_state")(c, ROWS)
end

local function rowDropState(c: Context): Properties
	local rows = c.cell("lapCopies", ROWS)
	return {
		from = rows,
		render = function(current)
			return c.UI.Text({
				text = function(use)
					local item = use(current)
					return `{item.name} · {item.laps} laps`
				end,
				Size = UDim2.fromScale(1, 1),
				wrap = true,
			})
		end,
		drag = function(items)
			return { payload = { route = items[1] }, operations = { "apply" } }
		end,
		rowDrop = function(current, key)
			return {
				label = function(use)
					return use(current).name
				end,
				operation = "apply",
				accepts = function(payload)
					return type(payload) == "table" and payload.route ~= nil and payload.route.id ~= key
				end,
				onDrop = function(payload)
					local nextRows: { Row } = table.clone(rows:peek())
					for index, item in nextRows do
						if item.id == key then
							nextRows[index] = { id = key, name = item.name, laps = payload.route.laps }
						end
					end
					rows:set(nextRows)
					c.log("copiedLaps")(key, payload.route.laps)
					return true
				end,
			}
		end,
	}
end

local function emptyStatus(c: Context)
	return c.cell("status", {
		mode = "windowed",
		direction = "vertical",
		total = 0,
		retained = 0,
		first = 0,
		last = 0,
		firstRow = 0,
		lastRow = 0,
		rowCount = 0,
		extent = 0,
		following = false,
		measured = 0,
	})
end
local LONG = "A deliberately long label that has to wrap or truncate honestly in every theme"

catalog.FAMILIES = table.freeze({
	{ id = "actions", label = "Actions" },
	{ id = "inputs", label = "Inputs" },
	{ id = "selection", label = "Selection" },
	{ id = "status", label = "Status & identity" },
	{ id = "overlays", label = "Overlays" },
	{ id = "navigation", label = "Navigation" },
	{ id = "collections", label = "Collections" },
	{ id = "layout", label = "Layout & primitives" },
	{ id = "facet", label = "Facet capabilities" },
})

local SIZES: Axis = { key = "controlSize", values = { "xsmall", "compact", "regular", "large" } }
local CORNERS: Axis = { key = "corners", values = { DEFAULT, "pill", "square" } }
local FIELD_APPEARANCE: Axis = { key = "appearance", values = { "standard", "contrast", "utility" } }
local DISABLED: State = { name = "disabled", props = properties { enabled = false } }
local hintPages = require("./hint_pages")({ sizes = SIZES, none = NONE })
local strips = require("./strip_overflow")(NONE)
local function fixed(w: number, h: number?): Properties
	return {
		Size = UDim2.fromOffset(w, h or 0),
		AutomaticSize = if h then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
	}
end
local function merged(a: Properties, b: Properties): Properties
	local out = table.clone(a)
	for k, v in b do
		out[k] = v
	end
	return out
end

local function plate(c: Context, tag: string, w: number, h: number): Frame
	local node = c.Host.Frame({ Size = UDim2.fromOffset(w, h), BorderSizePixel = 0 })
	node:AddTag(tag)
	return node
end

local ALIGN: Axis = { key = "align", values = { "start", "center", "end", "stretch" } }
local DISTRIBUTE: Axis =
	{ key = "distribute", values = { "start", "center", "end", "spaceBetween", "spaceAround", "spaceEvenly" } }
local GAP: Axis = { key = "gap", values = { "xs", "s", "m", "l", "xl" } }

local function stackDemo(c: Context, props: Properties): Properties
	props.gap = props.gap or "s"
	props.padding = props.padding or "s"
	for _, size in { { 40, 24 }, { 72, 48 }, { 56, 32 } } do
		props[#props + 1] = plate(c, "facet-control", size[1], size[2])
	end
	props.ref = function(node: Instance)
		node:AddTag("facet-panel")
	end
	return props
end

local function menuItems(c: Context): { MenuItem }
	return {
		{ id = "edit", label = "Edit", icon = "edit", onSelect = c.log("onSelect edit") },
		{ id = "flag", label = "Report", icon = "flag", onSelect = c.log("onSelect flag") },
		{ id = "d1", divider = true },
		{
			id = "delete",
			label = "Delete",
			icon = "trash",
			role = "destructive",
			onSelect = c.log("onSelect delete"),
		},
	}
end

local function trigger(c: Context, label: string, overlay: (open: BooleanCell) -> Instance): Instance
	local open = c.cell("open", false)
	return c.UI.VStack(stacked({
		gap = "xs",
		c.UI.Button({
			label = label,
			onActivate = function()
				open:set(true)
			end,
		}),
		overlay(open),
	}))
end

type FieldGroupProps = {
	layout: ("column" | "wrap")?,
	controlSize: ControlSize?,
	indicatorPosition: ("leading" | "trailing")?,
	hints: boolean?,
	enabled: boolean?,
}

local function fieldGroup(
	UI: FacetControls,
	p: FieldGroupProps,
	c: Context,
	presentation: "checkbox" | "switch"
): Instance
	local items: StackProps = { gap = if p.layout == "wrap" then "s" else "xs", wrap = p.layout == "wrap" }
	for i, label in { "Tire wear", "Fuel use", "Damage" } do
		items[#items + 1] = UI.Toggle({
			label = label,
			presentation = presentation,
			value = c.cell(`{presentation}{i}`, i == 1),
			controlSize = p.controlSize,
			indicatorPosition = p.indicatorPosition,
			hint = if p.hints then "Shown in the pit panel" else nil,
			enabled = p.enabled,
			Size = if p.layout == "wrap" then nil else UDim2.fromScale(1, 0),
		})
	end
	items.width = "fill"
	return UI.VStack({
		width = 260,
		gap = "xs",
		UI.Text({ text = "Show in race", textRole = "label", role = "secondary" }),
		if p.layout == "wrap" then UI.HStack(items) else UI.VStack(items),
	})
end

local PAGE_DATA: { [string]: PageDefinition } = {

	Button = {
		family = "actions",
		alias = "Button · IconButton · Link · ButtonGroup",
		purpose = "Starts an action. Appearance sets emphasis; role carries meaning (destructive).",
		alternatives = "Toggle for an on/off setting; Picker for choosing one value; Menu for many actions.",
		scenarios = { "action_controls", "shortcut_hint" },
		snippet = 'UI.Button { label = "Save", appearance = "emphasis" :: string, onActivate = save }',
		base = function(c: Context)
			return { label = "Button", onActivate = c.log("onActivate") }
		end,
		axes = {
			{ key = "appearance", values = { "standard", "emphasis", "soft", "utility", "link", "inverse" } },
			SIZES,
			CORNERS,
			{ key = "role", values = { "default", "destructive", "cancel", "onIndicator" } },

			{
				key = "shape",
				values = { DEFAULT, "rect", "circle" },
				implies = implied { circle = properties { icon = "settings" } },
			},
		},
		states = {
			{ name = "native glyph", props = nativeGlyph },
			{
				name = "circle with caption",
				props = properties { shape = "circle", icon = "settings", caption = "Settings" },
			},
			{ name = "shortcut hint", props = hintPages.buttonHint },
			{ name = "circle with shortcut hint", props = hintPages.circleHint },
			{ name = "discloses a truncated label", props = merged(fixed(120, 44), { label = LONG, disclose = true }) },
			{ name = "fixed 140×64", props = fixed(140, 64) },
			{
				name = "reactive width (tap to change)",
				props = function(c: Context)
					return require("./button_width_demo")(c, false)
				end,
			},
			{
				name = "reactive width with subtitle",
				props = function(c: Context)
					return require("./button_width_demo")(c, true)
				end,
			},
			{
				name = "compact label (short room)",
				props = merged(fixed(110, 44), { label = LONG, compactLabel = "Save" }),
			},
			{
				name = "image button",
				props = properties { image = ART, subtitle = "12 playing", imageAspectRatio = 16 / 9 },
			},
			{
				name = "image, crop framing",
				props = properties { image = ART, imageFraming = "crop", imageAspectRatio = 1 },
			},
			{
				name = "settings row",
				props = properties { row = { description = "Shown in the garage", icon = "settings", value = "On" } },
			},
			{ name = "hint line", props = properties { hint = "Saves your setup" } },
			{ name = "thumb target (touch)", props = properties { label = "DRIFT", target = "thumb" } },
			{
				name = "inline target (touch)",
				props = function(c: Context): Properties
					return merged(
						merged(
							fixed(24, 44),
							{ label = "", target = "inline", controlSize = "xsmall", name = "Page one" }
						),
						nativeGlyph(c)
					)
				end,
			},
			{
				name = "subtitle in a fixed 117 width (wraps)",
				props = merged(fixed(117), { label = "Boost Board", subtitle = "HELP · 2 energy", icon = "settings" }),
			},
			{ name = "pop on press", props = properties { pop = true } },
			{ name = "haptic", props = properties { haptic = true } },
			{ name = "hold repeats", props = properties { repeatDelay = 0.4, repeatInterval = 0.1 } },
			{ name = "shortcut S", props = properties { shortcut = { keyCode = "S" } } },
			{ name = "dialog default (Return)", props = properties { dialogAction = "default" } },
			{ name = "help plate", props = properties { help = "Saves your setup" } },
			{
				name = "help: title, shortcut, top edge",
				props = properties {
					help = {
						title = "Save",
						body = "Saves your setup",
						shortcut = { { "Ctrl", "S" } },
						edge = "top",
						align = "start",
					},
				},
			},
			{
				name = "pointer reported",
				props = function(c: Context)
					return {
						onPointerDown = c.log("onPointerDown"),
						onPointerUp = c.log("onPointerUp"),
						onPointerCancel = c.log("onPointerCancel"),
					}
				end,
			},
			{ name = "label text size", props = properties { textSize = "label" } },
			{
				name = "reactive numeric text size",
				props = function(c: Context)
					local size = c.cell("buttonTextSize", 16)
					return {
						label = "Change text size",
						textSize = size,
						onActivate = function()
							size:set(if size:peek() == 16 then 24 else 16)
						end,
					}
				end,
			},
			{
				name = "named icon (circle)",
				props = properties { icon = "settings", shape = "circle", name = "Settings" },
			},
			DISABLED,
			{ name = "disabled (alias)", props = properties { disabled = true } },
			{ name = "selected", props = properties { selected = true } },
			{ name = "busy", props = properties { busy = true } },
			{ name = "icon", props = properties { icon = "settings" } },
			{ name = "trailing icon", props = properties { trailingIcon = "chevron.trailing" } },
			{ name = "underline always", props = properties { appearance = "link", underline = "always" } },
			{ name = "underline on hover", props = properties { appearance = "link", underline = "hover" } },
			{ name = "long text", props = properties { label = LONG } },
		},
		valid = function(p: Properties)
			local forms = (if p.image then 1 else 0) + (if p.row then 1 else 0)
			return not (p.shape == "circle" and (p.icon == nil or p.trailingIcon ~= nil or forms > 0))
				and not (p.underline ~= nil and (p.icon or p.image or p.row or p.shape == "circle" or p.compactLabel))
				and forms <= 1
				and not (forms == 1 and (p.icon ~= nil or p.trailingIcon ~= nil or p.compactLabel ~= nil))
		end,
	},
	SplitButton = {
		family = "actions",
		alias = "Button + Menu (composed)",
		purpose = "A primary action beside a menu of related alternatives.",
		alternatives = "Button when there is one action; Menu when no action is primary.",
		scenarios = { "action_controls", "menu" },
		snippet = 'UI.SplitButton { label = "Start", onActivate = start, items = { … } }',
		base = function(c: Context)
			return { label = "Start race", onActivate = c.log("onActivate"), items = menuItems(c) }
		end,
		axes = {},
		states = {
			{ name = "menu label", props = properties { menuLabel = "More start options" } },
			{ name = "shortcut R", props = properties { shortcut = { keyCode = "R" } } },
			DISABLED,
			{ name = "busy", props = properties { busy = true } },
			{ name = "long text", props = properties { label = LONG } },
		},
	},
	Menu = {
		family = "actions",
		matrix = false,
		alias = "Menu · Dropdown menu",
		purpose = "A list of actions opened from a trigger; icons, roles, sections, shortcuts, badges and submenus.",
		alternatives = "Picker (menu) to choose a value; RadialMenu for quick gamepad actions.",
		scenarios = { "menu" },
		snippet = 'UI.Menu { label = "More", items = { { id = "edit", label = "Edit", onSelect = edit } } }',
		base = function(c: Context)
			return { label = "Actions", items = menuItems(c) }
		end,
		axes = {
			{ key = "edge", values = { "bottom", "top", "leading", "trailing" }, matrix = false },
			{ key = "align", values = { "start", "center", "end" }, matrix = false },
			{ key = "presentation", values = { "automatic", "menu", "sheet" }, matrix = false },
		},
		states = {
			{ name = "Close shown", props = properties { closeButton = true } },
			{ name = "Close hidden", props = properties { closeButton = false } },
			{
				name = "diagnostics controls",
				props = function(c: Context)
					local controls: { [string]: any } = {}
					return {
						controls = controls,
						onOpen = function()
							if controls.diagnostics then
								c.log("diagnostics")(table.concat(controls.diagnostics(), "; "))
							end
						end,
					}
				end,
			},
			{
				name = "custom trigger",
				props = function(c: Context)
					return {
						label = NONE,
						trigger = c.UI.Button({ label = "More", icon = "more", shape = "circle" }),
					}
				end,
			},
			{ name = "disclosure chevron", props = properties { disclosure = true } },
			{
				name = "opens on activate + secondary only",
				props = properties { triggers = { "activate", "secondary" } },
			},
			{ name = "sheet back label", props = properties { presentation = "sheet", backLabel = "Previous" } },
			{
				name = "open / close reported",
				props = function(c: Context)
					return { onOpen = c.log("onOpen"), onClose = c.log("onClose") }
				end,
			},
			{
				name = "controlled open",
				props = function(c: Context)
					return { isPresented = c.cell("menuOpen", false) }
				end,
			},
			DISABLED,
			{
				name = "avatar, badge, meta, sections, disabled row",
				props = function(c: Context)
					return {
						items = menuList {
							{
								id = "ada",
								label = "Ada Quill",
								avatar = { name = "Ada Quill" },
								onSelect = c.log("ada"),
							},
							{ id = "d1", divider = true },
							{ id = "inbox", label = "Inbox", icon = "flag", badge = 3, onSelect = c.log("inbox") },
							{
								id = "size",
								label = "Garage",
								meta = "12 cars",
								description = "Your saved builds",
								onSelect = c.log("garage"),
							},
							{
								id = "rename",
								label = "Rename",
								sectionTitle = "Edit",
								icon = "edit",
								onSelect = c.log("rename"),
							},
							{
								id = "locked",
								label = "Locked item",
								icon = "settings",
								enabled = false,
								onSelect = c.log("locked"),
							},
						},
					}
				end,
			},
			{
				name = "checked + selected items",
				props = function(c: Context)
					local mode = c.cell("menuMode", "rally")
					return {
						items = menuList {
							{ id = "grid", label = "Show grid", checked = c.cell("menuGrid", true) },
							{ id = "d1", divider = true },
							{ id = "road", label = "Road", selected = mode, value = "road" },
							{ id = "rally", label = "Rally", selected = mode, value = "rally" },
						},
					}
				end,
			},
			{ name = "width 320", props = properties { width = 320 } },
			{ name = "maxHeight 140", props = properties { maxHeight = 140 } },
			{
				name = "searchable",
				props = function(c: Context)
					return { query = c.cell("menuQuery", "") }
				end,
			},
			{
				name = "submenu + shortcuts",
				props = function(c: Context)
					return {
						items = menuList {
							{ id = "copy", label = "Copy", shortcutLabel = "Ctrl+C", onSelect = c.log("copy") },
							{ id = "paste", label = "Paste", shortcutLabel = "Ctrl+V", onSelect = c.log("paste") },
							{ id = "share", label = "Share", children = menuItems(c) },
						},
					}
				end,
			},
		},
	},
	RadialMenu = {
		family = "actions",
		matrix = false,
		alias = "(Facet-only)",
		purpose = "A ring of quick actions for gamepad sticks and touch; opens from a launcher or a world anchor.",
		alternatives = "Menu for long or text-heavy lists.",
		scenarios = { "radial_menu" },
		cellWidth = 240,
		cellHeight = 480,
		snippet = 'UI.RadialMenu { label = "Quick actions", items = { … } }',
		base = function(c: Context)
			local items: Properties = {}
			for _, name in { "settings", "edit", "flag", "trash", "person", "calendar" } do
				table.insert(items, { id = name, label = name, icon = name, onSelect = c.log(`onSelect {name}`) })
			end

			items[1] = {
				id = "settings",
				label = "settings",
				icon = "settings",
				children = {
					{ id = "sound", label = "Sound", icon = "edit", onSelect = c.log("onSelect sound") },
					{ id = "video", label = "Video", icon = "flag", onSelect = c.log("onSelect video") },
					{ id = "input", label = "Input", icon = "person", onSelect = c.log("onSelect input") },
				},
			}
			return { label = "Quick actions", icon = "menu", items = items, launcher = true }
		end,

		make = function(UI: FacetControls, p: Properties): Instance
			local style = p.labelStyle
			p.labelStyle = nil
			if style ~= nil then
				local items: Properties = {}
				for _, item in p.items do
					local copy = table.clone(item)
					copy.labelStyle = style
					table.insert(items, copy)
				end
				p.items = items
			end
			return UI.RadialMenu(p)
		end,
		demonstrates = { "labelStyle" },
		axes = {
			{
				key = "preset",
				values = { "donut", "top-left", "top-right", "bottom-left", "bottom-right" },
				matrix = false,
			},
			{ key = "appearance", values = { "wedges", "buttons" }, matrix = false },
			{
				key = "distribution",
				values = { "even", "compass" },
				matrix = false,
				implies = implied {
					compass = function(c: Context)
						local items: Properties = {}
						for i, slot in { "N", "E", "S", "W", "NE", "SW" } do
							local name = ({ "settings", "edit", "flag", "trash", "person", "calendar" })[i]
							table.insert(items, {
								id = name,
								label = name,
								icon = name,
								slot = slot,
								onSelect = c.log(`onSelect {name}`),
							})
						end
						return { items = items }
					end,
				},
			},
			{ key = "center", values = { "back", "root", "close", "content", "empty" }, matrix = false },
			{ key = "ringWidth", values = { DEFAULT, "narrow", "regular", "wide" }, matrix = false },
			{ key = "contentFit", values = { "radial", "both", "angular", "none" }, matrix = false },
			{ key = "buttonSurface", values = { DEFAULT, "native", "none" }, matrix = false },
			{ key = "labelStyle", values = { DEFAULT, "text", "icon" }, matrix = false },
			{ key = "navigation", values = { "replace", "expand" }, matrix = false },
			{ key = "expansion", values = { "fan", "ring" }, matrix = false },
			{ key = "completion", values = { "close", "stay", "root", "back" }, matrix = false },
			{ key = "gestureSelection", values = { "bounded", "direction" }, matrix = false },
			{ key = "scrim", values = { "dark", "light", "none" }, matrix = false },
			{ key = "follow", values = { "idle", "always", "fixed" }, matrix = false },
		},
		valid = function(p: Properties)
			return not (p.distribution == "compass" and p.preset ~= nil and p.preset ~= "donut")
				and not (p.buttonSurface ~= nil and p.appearance ~= "buttons")
				and not (p.center == "content" and p.centerContent == nil)
		end,
		states = {
			DISABLED,
			{
				name = "list form (crowded ring)",
				props = function(c: Context)
					local items: Properties = {}
					for i = 1, 20 do
						table.insert(
							items,
							{ id = `emote{i}`, label = `Emote {i}`, onSelect = c.log(`onSelect emote{i}`) }
						)
					end
					return { items = items }
				end,
			},
			{ name = "centre label", props = properties { centerLabel = "Pick one" } },
			{
				name = "centre content",
				props = function(c: Context)
					return {
						center = "content",
						centerContent = c.UI.Label({
							title = "Kart",
							icon = "person",
							presentation = "iconOnly",
						}),
					}
				end,
			},
			{ name = "centre passes presses through", props = properties { centerPassThrough = true } },
			{ name = "clearance 40", props = properties { clearance = 40 } },
			{ name = "no motion", props = properties { transition = false } },
			{
				name = "no launcher (controlled)",
				props = function(c: Context)
					return { launcher = false, isPresented = c.cell("radialOpen", true) }
				end,
			},
			{
				name = "open / close reported",
				props = function(c: Context)
					return { onOpen = c.log("onOpen"), onClose = c.log("onClose") }
				end,
			},
			{
				name = "hold action (InputAction)",
				props = function(c: Context)
					local action = c.Host.InputAction({ Name = "LabRadialHold" })
					c.Host.InputContext({ Name = "LabRadialContext", Parent = workspace :: Instance, action :: unknown })
					return { holdAction = action }
				end,
			},
			{
				name = "anchored at a point",
				props = properties { anchor = { x = 400, y = 300, visible = true } },
			},
			{
				name = "skinned slots",
				props = properties { skin = { item = { default = ART }, center = { default = ART } } },
			},
		},
	},
	ShortcutHint = hintPages.ShortcutHint,
	ButtonGuide = hintPages.ButtonGuide,

	TextInput = {
		family = "inputs",
		valid = function(p: Properties)
			return not (p.presentation == "number" and p.multiline)
				and not (p.presentation == "search" and p.leading ~= nil)
				and not (p.visibleLines ~= nil and not p.multiline)
				and not ((p.stepButtons or p.prefix or p.scrub) and p.presentation ~= "number")
		end,
		cellWidth = 200,
		alias = "TextInput · TextArea · SearchInput · InputLabel",
		purpose = "Edits text with a label, hint, error, leading/trailing content and a clear button.",
		alternatives = "NumberInput for numbers; ComboBox to pick-or-type; Picker for a closed list.",
		scenarios = { "text_controls" },
		snippet = 'UI.TextInput { label = "Name", value = name, placeholder = "Your name" }',
		base = function(c: Context)
			return {
				label = "Label",
				value = c.cell("value", "Value"),
				placeholder = "Placeholder",
				Size = UDim2.fromScale(1, 0),
			}
		end,
		axes = {
			FIELD_APPEARANCE,
			SIZES,
			CORNERS,
			{
				key = "presentation",
				values = { "plain", "search", "number" },
				implies = implied {
					number = function(c: Context)
						return { value = c.cell("draft", "42"), numericValue = c.cell("number", 42) }
					end,
				},
			},
		},
		states = {
			DISABLED,
			{ name = "disabled (alias)", props = properties { disabled = true } },
			{ name = "read only", props = properties { readOnly = true } },
			{ name = "error", props = properties { errorText = "That name is taken" } },
			{
				name = "invalid (readable)",
				props = function(c: Context)
					return { invalid = c.cell("invalid", true) }
				end,
			},
			{
				name = "hint + required",
				props = properties { hint = "Shown to other players", requiredMark = "required" },
			},
			{ name = "optional mark", props = properties { requiredMark = "optional" } },
			{
				name = "empty",
				props = function(c: Context)
					return { value = c.cell("empty", "") }
				end,
			},
			{ name = "clear button", props = properties { clearButton = true } },
			{
				name = "clear while editing",
				props = properties { clearButton = true, clearButtonMode = "whileEditing" },
			},
			{
				name = "leading + trailing",
				props = function(c: Context)
					return {
						leading = c.UI.Label({
							title = "Name",
							icon = "person",
							presentation = "iconOnly",
						}),
						trailing = c.UI.Text({ text = "kg", role = "secondary" }),
					}
				end,
			},
			{ name = "select all on focus", props = properties { selectOnFocus = "all" } },
			{ name = "max 10 characters", props = properties { maxLength = 10 } },
			{
				name = "validate: letters only",
				props = properties {
					validate = function(text)
						return if string.find(text, "%d") then nil else text
					end,
				},
			},
			{
				name = "change, commit, cancel reported",
				props = function(c: Context)
					return { onChange = c.log("onChange"), onCommit = c.log("onCommit"), onCancel = c.log("onCancel") }
				end,
			},
			{ name = "multiline, 3 lines", props = properties { multiline = true, visibleLines = 3 } },
			{
				name = "number bounds + format",
				props = function(c: Context)
					return {
						presentation = "number",
						value = c.cell("bounded", "5"),
						numericValue = c.cell("boundedNumber", 5),
						min = 0,
						max = 10,
						format = function(n)
							return string.format("%.1f", n)
						end,
						parse = tonumber,
					}
				end,
			},
			{
				name = "long text",
				props = function(c: Context)
					return { value = c.cell("long", LONG), label = LONG }
				end,
			},
		},
	},
	NumberInput = {
		family = "inputs",
		cellWidth = 200,
		alias = "NumberInput",
		purpose = "Edits a number with bounds, step buttons, prefix/suffix and scrub.",
		alternatives = "Stepper for small integer ranges; Slider for approximate values.",
		scenarios = { "text_controls" },
		snippet = "UI.NumberInput { value = draft, numericValue = speed, min = 0, max = 300, step = 5 }",
		base = function(c: Context)
			return {
				label = "Speed",
				value = c.cell("draft", "120"),
				numericValue = c.cell("number", 120),
				min = 0,
				max = 300,
				step = 5,
				Size = UDim2.fromScale(1, 0),
			}
		end,
		axes = { FIELD_APPEARANCE, SIZES },
		states = {
			DISABLED,
			{ name = "step buttons", props = properties { stepButtons = true } },
			{ name = "prefix/suffix", props = properties { prefix = "$", suffix = "km/h" } },
			{ name = "error", props = properties { errorText = "Out of range" } },
			{ name = "scrub (drag)", props = properties { scrub = true } },
			{ name = "precision 2", props = properties { precision = 2, step = 0.25 } },
			{
				name = "arithmetic parse (Facet.recipes)",
				props = function(c: Context)
					return { parse = c.Facet.recipes.arithmetic.parse, hint = "Try 2*60+5" }
				end,
			},
			{
				name = "commit reported",
				props = function(c: Context)
					return { onCommit = c.log("onCommit") }
				end,
			},
			{ name = "select all on focus", props = properties { selectOnFocus = "all" } },
		},
	},
	ComboBox = {
		family = "inputs",
		cellWidth = 200,
		alias = "Dropdown (editable)",
		purpose = "Pick from suggestions or type a custom value the model accepts or refuses.",
		alternatives = "Picker (menu) when typing is not allowed.",
		scenarios = { "selection_controls" },
		snippet = "UI.ComboBox { value = id, text = text, options = { … }, acceptCustom = validate }",
		base = function(c: Context)
			return {
				value = c.cell("value", "road"),
				text = c.cell("text", "Road"),
				options = {
					{ value = "road", label = "Road" },
					{ value = "rally", label = "Rally" },
					{ value = "kart", label = "Kart" },
				},
				acceptCustom = function(text: string)
					return #text >= 3, "Use at least 3 characters."
				end,
				placeholder = "Vehicle",
				Size = UDim2.fromScale(1, 0),
			}
		end,
		axes = {},
		states = {
			DISABLED,
			{
				name = "change reported, commit on focus lost",
				props = function(c: Context)
					return { onChange = c.log("onChange"), commitOnFocusLost = true }
				end,
			},
		},
	},
	Slider = {
		family = "inputs",
		cellWidth = 240,
		alias = "Slider · SliderKnob · Knob",
		purpose = "Adjusts a value along a track; range mode has two thumbs, a vertical axis and a turned track.",
		alternatives = "Stepper or NumberInput when exact values matter.",
		scenarios = { "adaptive_controls" },
		snippet = 'UI.Slider { label = "Volume", value = volume, min = 0, max = 100 }',
		base = function(c: Context)
			return { label = "Volume", value = c.cell("value", 40), min = 0, max = 100, Size = UDim2.fromScale(1, 0) }
		end,
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			if (p.rotation or 0) % 180 == 0 then
				return UI.Slider(p)
			end
			p.AnchorPoint = Vector2.new(0.5, 0.5)
			p.Position = UDim2.fromScale(0.5, 0.5)
			local stage = c.Host.Frame({
				Name = "RotationStage",
				Size = UDim2.fromScale(1, 0),
				BackgroundTransparency = 1,
				UI.Slider(p),
			})
			local area = UI.environment(stage)
			c.app.runtime.decorate(stage, {
				Size = function(use: Use)
					return UDim2.new(1, 0, 0, math.max(use(area.viewportSize).X, 240) + 64)
				end,
			})
			return stage
		end,
		axes = {
			SIZES,
			{ key = "thumb", values = { "always", "auto", "none" } },

			{ key = "contained", values = { false, true } },
			{ key = "rotation", values = { 0, 15, 45, 90 } },
		},
		states = {
			{
				name = "settings row",
				props = properties { row = { description = "Master volume", icon = "settings" } },
			},
			{
				name = "percent format",
				props = properties {
					format = function(v)
						return `{math.round(v)}%`
					end,
				},
			},
			{ name = "no tap-to-position", props = properties { tapToPosition = false } },
			{
				name = "change and commit reported",
				props = function(c: Context)
					return { onChange = c.log("onChange"), onCommit = c.log("onCommit") }
				end,
			},
			{
				name = "range, min gap 20",
				props = function(c: Context)
					return { range = true, minGap = 20, value = c.cell("gapRange", { lower = 20, upper = 70 }) }
				end,
			},
			{ name = "image knob and track", props = properties { thumbImage = ART, trackImage = ART } },
			DISABLED,
			{ name = "stepped", props = properties { step = 10 } },
			{
				name = "custom knob",
				props = function(c: Context)
					return {
						thumbContent = function()
							return c.UI.Badge({ label = "♦", appearance = "status", status = "accent" })
						end,
					}
				end,
			},
			{
				name = "colour track",
				props = function(c: Context)
					return {
						trackContent = function()
							return c.Host.Frame({
								Size = UDim2.new(1, 0, 0, 6),
								BorderSizePixel = 0,
								BackgroundColor3 = Color3.new(1, 1, 1),
								c.Host.UIGradient({
									Color = ColorSequence.new({
										ColorSequenceKeypoint.new(0, Color3.fromRGB(230, 57, 70)),
										ColorSequenceKeypoint.new(0.5, Color3.fromRGB(242, 176, 30)),
										ColorSequenceKeypoint.new(1, Color3.fromRGB(63, 184, 113)),
									}),
								}),
							})
						end,
					}
				end,
			},
			{
				name = "range",
				props = function(c: Context)
					return { range = true, value = c.cell("range", { lower = 20, upper = 70 }) }
				end,
			},
			{ name = "vertical", props = properties { axis = "y", Size = UDim2.fromOffset(80, 200) } },
		},
		valid = function(p: Properties)
			return not (p.thumbContent and p.thumbImage)
				and not (p.trackContent and p.trackImage)
				and not (p.axis == "y" and p.row ~= nil)
		end,
	},
	Stepper = {
		family = "inputs",
		cellWidth = 240,
		alias = "Stepper",
		purpose = "Increments or decrements a bounded number; hold repeats.",
		alternatives = "NumberInput for typed values; StepIndicator for workflow steps (different control).",
		scenarios = { "adaptive_controls", "level_picker" },
		snippet = 'UI.Stepper { label = "Laps", value = laps, min = 1, max = 10 }',
		base = function(c: Context)
			return { label = "Laps", value = c.cell("value", 3), min = 1, max = 10 }
		end,
		axes = {},
		states = {
			{ name = "step 2", props = properties { step = 2 } },
			{ name = "slow repeat (1 s, then 0.5 s)", props = properties { repeatDelay = 1, repeatInterval = 0.5 } },
			{
				name = "format + change reported",
				props = function(c: Context)
					return {
						format = function(v)
							return `{v} laps`
						end,
						onChange = function(v)
							c.cell("value", 3):set(v)
							c.log("onChange")(v)
						end,
					}
				end,
			},
			DISABLED,
			{
				name = "at minimum",
				props = function(c: Context)
					return { value = c.cell("min", 1) }
				end,
			},
		},
	},
	ColorPicker = {
		family = "inputs",
		cellWidth = 300,
		alias = "ColorPicker",
		purpose = "Chooses a colour through swatches, spectrum, sliders or brick colours; optional alpha and draft.",
		alternatives = "A Picker of named swatches for a small palette.",
		scenarios = { "pickers" },
		snippet = 'UI.ColorPicker { label = "Accent", value = color, onChange = function(v) color:set(v) end }',
		base = function(c: Context)
			local value = c.cell("color", Color3.fromRGB(60, 94, 246))
			return {
				label = "Accent",
				value = value,
				onChange = function(v)
					value:set(v)
					c.log("onChange")(v)
				end,
				Size = UDim2.fromScale(1, 0),
			}
		end,
		axes = {
			FIELD_APPEARANCE,
			SIZES,
			{ key = "style", values = { "automatic", "inline" } },
		},
		states = {
			{
				name = "label, hint, required",
				props = properties { label = "Team colour", hint = "Shown on your kart", requiredMark = "required" },
			},
			{
				name = "empty with placeholder",
				props = function(c: Context)
					return { allowEmpty = true, placeholder = "No colour", value = c.cell("emptyColor", nil) }
				end,
			},
			{ name = "square corners", props = properties { corners = "square" } },
			{
				name = "saved swatches",
				props = function(c: Context)
					return {
						swatches = {
							Color3.fromRGB(220, 60, 60) :: Color3 | { color: Color3, label: string },
							{ color = Color3.fromRGB(60, 160, 90), label = "Pit green" },
						},
						onSaveSwatch = c.log("onSaveSwatch"),
						onRemoveSwatch = c.log("onRemoveSwatch"),
					}
				end,
			},
			{
				name = "commit reported",
				props = function(c: Context)
					return { onCommit = c.log("onCommit") }
				end,
			},
			{
				name = "presented by the caller",
				props = function(c: Context)
					local open = c.cell("pickerOpen", false)
					return {
						isPresented = open,
						onPresentedChange = function(v)
							open:set(v)
						end,
						onDismiss = c.log("onDismiss"),
					}
				end,
			},
			DISABLED,
			{ name = "read only", props = properties { readOnly = true } },
			{ name = "error", props = properties { errorText = "Too dark" } },
			{ name = "draft (Cancel / Apply)", props = properties { draft = true } },
			{ name = "brick colours", props = properties { modes = { "swatches", "brick" } } },
			{
				name = "all colour modes",
				props = properties { modes = { "swatches", "spectrum", "sliders", "brick" } },
			},
			{
				name = "alpha",
				props = function(c: Context)
					local alpha = c.cell("alpha", 0.8)
					return {
						alpha = alpha,
						onAlphaChange = function(a)
							alpha:set(a)
							c.log("onAlphaChange")(a)
						end,
					}
				end,
			},
		},
	},
	DateTimePicker = {
		family = "inputs",
		valid = function(p: Properties)
			return not (p.selection == "range" and p.time)
		end,
		cellWidth = 320,
		alias = "DateTimePicker",
		purpose = "Chooses a civil date, date-time or range; dual-pane range, presets, controller calendar.",
		alternatives = "A Picker of preset dates when only a few days apply.",
		scenarios = { "pickers" },
		snippet = 'UI.DateTimePicker { label = "Race day", value = day, onChange = function(v) day:set(v) end }',
		base = function(c: Context)
			local value = c.cell("date", { year = 2026, month = 9, day = 24 })
			return {
				label = "Race day",
				value = value,
				onChange = function(v)
					value:set(v)
					c.log("onChange")(if v then `{v.year}-{v.month}-{v.day}` else "nil")
				end,
				clock = function()
					return { year = 2026, month = 9, day = 24 }
				end,
				Size = UDim2.fromScale(1, 0),
			}
		end,
		axes = {
			FIELD_APPEARANCE,
			SIZES,
			{ key = "style", values = { "automatic", "inline" } },
		},
		states = {
			{ name = "day-first locale", props = properties { locale = { order = "dmy", separator = "." } } },
			{
				name = "commit reported",
				props = function(c: Context)
					return { onCommit = c.log("onCommit") }
				end,
			},
			{ name = "24-hour time", props = properties { time = true, hourCycle = 24 } },
			{
				name = "weekends disabled",
				props = function(c: Context)
					return {
						isDateDisabled = function(d)
							local weekday = c.Facet.civilDate.weekday(d)
							return weekday == 1 or weekday == 7
						end,
					}
				end,
			},
			{ name = "week starts Monday", props = properties { weekStart = 2 } },
			{
				name = "custom field format",
				props = properties {
					format = function(d)
						return `{d.day}/{d.month}/{d.year}`
					end,
				},
			},
			{
				name = "presented by the caller",
				props = function(c: Context)
					local open = c.cell("dateOpen", false)
					return {
						isPresented = open,
						onPresentedChange = function(v)
							open:set(v)
						end,
						onDismiss = c.log("onDismiss"),
					}
				end,
			},
			{ name = "read only", props = properties { readOnly = true } },
			{ name = "hint + required", props = properties { hint = "Pick a race day", requiredMark = "required" } },
			{ name = "square corners", props = properties { corners = "square" } },
			DISABLED,
			{
				name = "time, 15-minute grid",
				props = function(c: Context)
					local v = c.cell("datetime", { year = 2026, month = 9, day = 24, hour = 14, minute = 30 })
					return {
						time = true,
						minuteStep = 15,
						value = v,
						onChange = function(x)
							v:set(x)
						end,
					}
				end,
			},
			{ name = "error", props = properties { errorText = "Pick a weekday" } },
			{
				name = "empty",
				props = function(c: Context)
					return { value = c.cell("none", nil), placeholder = "No date" }
				end,
			},
			{
				name = "min/max (Sep 10–30)",
				props = properties {
					min = { year = 2026, month = 9, day = 10 },
					max = { year = 2026, month = 9, day = 30 },
				},
			},
			{
				name = "empty, opens on March",
				props = function(c: Context)
					return {
						value = c.cell("noneRef", nil),
						placeholder = "No date",
						referenceDate = { year = 2027, month = 3, day = 1 },
					}
				end,
			},
			{
				name = "range presets + draft",
				props = function(c: Context)
					local range = c.cell("presetRange", {
						start = { year = 2026, month = 9, day = 20 },
						finish = { year = 2026, month = 9, day = 27 },
					})
					return {
						selection = "range",
						value = NONE,
						onChange = NONE,
						range = range,
						draft = true,
						presets = {
							{
								id = "week",
								label = "Next 7 days",
								range = function(today)
									return { start = today, finish = c.Facet.civilDate.addDays(today, 6) }
								end,
							},
						},
						onRangeChange = function(r)
							range:set(r)
						end,
						onRangeCommit = c.log("onRangeCommit"),
					}
				end,
			},
			{
				name = "range",
				props = function(c: Context)
					local range = c.cell("range", {
						start = { year = 2026, month = 9, day = 20 },
						finish = { year = 2026, month = 9, day = 27 },
					})
					return {
						selection = "range",
						value = NONE,
						onChange = NONE,
						range = range,
						onRangeChange = function(r)
							range:set(r)
							c.log("onRangeChange")()
						end,
					}
				end,
			},
		},
	},

	Toggle = {
		family = "selection",
		cellWidth = 180,
		alias = "Toggle · Switch · Checkbox · ToggleButton",
		purpose = "Turns one setting on or off. A checkbox is not a separate control: it is this Toggle with "
			.. '`presentation = "checkbox"` (pick it under Controls; "mixed" is the indeterminate state). '
			.. '`presentation = "button"` is a toggle button.',
		alternatives = "Button for a one-shot action; Picker for exclusive choices.",
		scenarios = { "selection_controls" },
		snippet = 'UI.Toggle { label = "Music", value = music }',
		base = function(c: Context)
			return { label = "Label", value = c.cell("value", true) }
		end,
		axes = {
			{ key = "presentation", values = { "switch", "checkbox", "button" } },
			{ key = "controlSize", values = SIZES.values },
			{ key = "indicatorPosition", values = { DEFAULT, "leading", "trailing" } },
			{ key = "appearance", values = { DEFAULT, "plain" } },
		},
		states = {
			{
				name = "fixed width 220",
				props = properties { Size = UDim2.fromOffset(220, 0), AutomaticSize = Enum.AutomaticSize.Y },
			},
			{
				name = "settings row",
				props = properties { row = { description = "Plays in menus", icon = "settings" } },
			},
			{ name = "label text size", props = properties { textSize = "label" } },
			{
				name = "change reported",
				props = function(c: Context)
					local value = c.cell("value", true)
					return {
						onChange = function(v)
							value:set(v)
							c.log("onChange")(v)
						end,
					}
				end,
			},
			DISABLED,
			{
				name = "off",
				props = function(c: Context)
					return { value = c.cell("off", false) }
				end,
			},
			{
				name = "mixed",
				props = function(c: Context)
					return { presentation = "checkbox", mixed = c.cell("mixed", true) }
				end,
			},
			{ name = "hint", props = properties { hint = "Hint text" } },
			{ name = "icon", props = properties { icon = "settings" } },
			{ name = "long text", props = properties { label = LONG, Size = UDim2.fromScale(1, 0) } },
		},
		valid = function(p: Properties)
			local shape: string = p.presentation or "switch"
			local mixed = p.mixed == nil or shape == "checkbox"
			local plainButton = shape == "button" and p.appearance == "plain"
			return mixed and not plainButton
		end,
	},
	Chip = {
		family = "selection",
		demonstrates = { "removeFocusFallback" },
		alias = "Chip · InputChip · FilterChip",
		purpose = "A compact selectable or removable token.",
		alternatives = "Toggle for a labelled setting; Badge for read-only status.",
		scenarios = { "selection_controls", "action_controls" },
		snippet = 'UI.Chip { label = "Rally", selected = rally }',
		base = function(c: Context)
			return { label = "Chip", selected = c.cell("selected", false) }
		end,
		axes = { { key = "appearance", values = { "standard", "utility" } }, SIZES, CORNERS },
		states = {
			{
				name = "toggle reported",
				props = function(c: Context)
					local selected = c.cell("selected", false)
					return {
						onToggle = function(v)
							selected:set(v)
							c.log("onToggle")(v)
						end,
					}
				end,
			},
			DISABLED,
			{
				name = "selected",
				props = function(c: Context)
					return { selected = c.cell("on", true) }
				end,
			},
			{
				name = "leading + trailing",
				props = function(c: Context)
					return {
						leading = c.UI.Label({
							title = "Rally",
							icon = "flag",
							presentation = "iconOnly",
						}),
						trailing = c.UI.Label({
							title = "More",
							icon = "chevron.trailing",
							presentation = "iconOnly",
						}),
					}
				end,
			},
			{
				name = "removable (always editing)",
				props = function(c: Context)
					return { selected = NONE, onRemove = c.log("onRemove") }
				end,
			},
			{
				name = "selectable + removable in edit mode",
				props = function(c: Context)
					return {
						onRemove = c.log("onRemove"),
						editing = c.cell("editing", true),
						removeLabel = "Remove Rally",
						removeFocusFallback = c.cell("fallback", nil),
					}
				end,
			},
			{ name = "long text", props = properties { label = LONG } },
		},
	},
	Picker = {
		family = "selection",
		cellWidth = 300,
		alias = "SegmentedControl · RadioGroup · Select · OptionCards",
		purpose = "Chooses one value (or several) from a set; style picks segmented, radio, menu, inline, link or cards.",
		alternatives = "ComboBox when typing is allowed; TabView for destination pages.",
		scenarios = { "selection_controls", "pickers" },
		snippet = 'UI.Picker { label = "Mode", selected = mode, style = "segmented", options = { … } }',
		base = function(c: Context)
			return {
				label = "Mode",
				selected = c.cell("selected", "rally"),
				options = {
					{ value = "road", label = "Road" },
					{ value = "rally", label = "Rally" },
					{ value = "drift", label = "Drift" },
				},
			}
		end,
		axes = {
			{
				key = "style",
				values = { "automatic", "segmented", "radioGroup", "menu", "inline", "navigationLink", "cards" },
			},
			{ key = "controlSize", values = SIZES.values, props = properties { style = "segmented" } },
			{
				key = "appearance",
				values = { DEFAULT, "standard", "contrast", "utility", "filled", "stroke" },
				implies = implied {
					filled = { style = "segmented" },
					stroke = { style = "segmented" },
				},
			},
		},
		valid = function(p: Properties)
			local style: string, word = p.style or "automatic", p.appearance
			if p.iconOnly then
				for _, option in p.options or {} do
					if option.icon == nil then
						return false
					end
				end
				if style == "radioGroup" then
					return false
				end
			end
			local badHeight = p.maxHeight ~= nil
				and style ~= "menu"
				and style ~= "navigationLink"
				and style ~= "automatic"
			local badRequired = p.required == false and style ~= "cards"
			local badIndicator = p.indicatorPosition ~= nil and style ~= "radioGroup"
			local badAlignment = p.valueAlignment ~= nil and style ~= "menu"
			if badHeight or badRequired or badIndicator or badAlignment then
				return false
			end
			if word == nil then
				return true
			elseif style == "segmented" then
				return word == "filled" or word == "stroke" or word == "utility"
			elseif style == "menu" or style == "navigationLink" then
				return word == "standard" or word == "contrast" or word == "utility"
			end
			return style == "automatic"
		end,
		states = {
			{
				name = "change vetoed (Drift)",
				props = function(c: Context)
					return {
						onChanging = function(new, old)
							c.log("onChanging")(new, old)
							return new ~= "drift"
						end,
						onChange = c.log("onChange"),
					}
				end,
			},
			{ name = "menu value at start", props = properties { style = "menu", valueAlignment = "start" } },
			{
				name = "searchable",
				props = function(c: Context)
					return { query = c.cell("pickerQuery", "") }
				end,
			},
			{
				name = "menu placeholder",
				props = function(c: Context)
					return { style = "menu", placeholder = "Choose a mode", selected = c.cell("none", nil) }
				end,
			},
			{ name = "text size 13", props = properties { textSize = 13 } },
			{ name = "required mark", props = properties { requiredMark = "required" } },
			{ name = "pill corners", props = properties { style = "segmented", corners = "pill" } },
			DISABLED,
			{ name = "error", props = properties { errorText = "Pick a mode" } },
			{ name = "hint", props = properties { hint = "You can change this later" } },
			{ name = "menu sizes", props = properties { style = "menu" }, across = "controlSize", matrixOnly = true },
			{ name = "underline indicator", props = properties { indicator = "underline" } },
			{
				name = "multiple",
				props = function(c: Context)
					return { multiple = true, selected = c.cell("many", { road = true, drift = true }) }
				end,
			},
			{
				name = "controlled open",
				props = function(c: Context)
					return { style = "menu", isPresented = c.cell("pickerOpen", false) }
				end,
			},
			{
				name = "menu: bounded, rich rows",
				props = properties {
					style = "menu",
					maxHeight = 180,
					options = optionList {
						{
							value = "ada",
							label = "Ada Quill",
							avatar = { name = "Ada Quill" },
							sectionTitle = "Friends",
						},
						{ value = "rally", label = "Rally", badge = 2, indicator = { status = "success" } },
						{ value = "road", label = "Road", meta = "12 km" },
						{ value = "kart", label = "Kart (locked)", enabled = false, sectionTitle = "Locked" },
						{ value = "drift", label = "Drift", description = "Hold the slide" },
					},
				},
				across = false,
			},
			{
				name = "cards: meta, reselect clears",
				props = properties {
					style = "cards",
					required = false,
					options = optionList {
						{
							value = "road",
							label = "Road",
							icon = "edit",
							meta = "12 km",
							description = "Smooth tarmac",
							badge = "New",
						},
						{ value = "rally", label = "Rally", icon = "flag", meta = "8 km", description = "Gravel" },
					},
				},
				across = false,
			},
			{
				name = "radio mark trailing",
				props = properties { style = "radioGroup", indicatorPosition = "trailing" },
				across = false,
			},
			{ name = "vertical", props = properties { axis = "y" } },
			{ name = "hug", props = properties { sizing = "hug" } },
			{ name = "strip scrolls", props = strips.scrolls, across = false },
			{
				name = "icon only",
				props = properties {
					iconOnly = true,
					options = {
						{ value = "road", label = "Road", icon = "edit" },
						{ value = "rally", label = "Rally", icon = "flag" },
						{ value = "drift", label = "Drift", icon = "settings" },
					},
				},
			},
			{
				name = "long text",
				props = properties {
					options = {
						{ value = "a", label = LONG },
						{ value = "rally", label = "Rally" },
					},
				},
			},
		},
		demonstrates = { "Style" },
	},
	Rating = {
		family = "selection",
		alias = "Rating",
		purpose = "Chooses a star rating, or shows one read-only.",
		alternatives = "Vote for up/down reactions.",
		scenarios = { "selection_controls" },
		snippet = "UI.Rating { value = stars, count = 5 }",
		base = function(c: Context)
			return { value = c.cell("value", 3), count = 5 }
		end,
		axes = { { key = "starSize", values = { "small", "medium", "large" } } },
		states = {
			{ name = "custom glyphs", props = properties { glyphs = { filled = "♥", empty = "♡" } } },
			{
				name = "change reported",
				props = function(c: Context)
					local value = c.cell("value", 3)
					return {
						onChange = function(v)
							value:set(v)
							c.log("onChange")(v)
						end,
					}
				end,
			},
			DISABLED,
			{ name = "read only", props = properties { readOnly = true } },
			{
				name = "zero, no zero allowed",
				props = function(c: Context)
					return { value = c.cell("zero", 1), allowZero = false }
				end,
			},
			{ name = "ten stars", props = properties { count = 10 } },
		},
	},
	Vote = {
		family = "selection",
		alias = "(Facet-only) up/down vote",
		purpose = "Up/down reaction with a summary; the model may refuse a vote.",
		alternatives = "Rating for a scale.",
		scenarios = { "selection_controls" },
		snippet = "UI.Vote { value = vote, onChange = function(v) vote:set(v) end }",
		base = function(c: Context)
			local value = c.cell("vote", "none")
			return {
				value = value,
				summary = "98% liked this",
				onChange = function(v)
					value:set(v)
					c.log("onChange")(v)
				end,
			}
		end,
		axes = { SIZES },
		states = {
			DISABLED,
			{ name = "read only", props = properties { readOnly = true } },
			{
				name = "diagnostics table",
				props = function(c: Context)
					return { controls = {} }
				end,
			},
		},
	},
	LevelPicker = {
		family = "selection",
		cellWidth = 280,
		alias = "(Facet-only) level bar",
		purpose = "Chooses a level from a row of segments (bars, glyphs or images).",
		alternatives = "Slider for continuous values.",
		scenarios = { "level_picker" },
		snippet = "UI.LevelPicker { value = level, count = 5 }",
		base = function(c: Context)
			return { value = c.cell("value", 3), count = 5 }
		end,
		axes = {
			{
				key = "segment",
				values = { "bar", "glyph", "image" },
				implies = implied { image = { images = { filled = ART, empty = ART } } },
			},
			{ key = "segmentSize", values = { "small", "medium", "large" }, props = properties { segment = "glyph" } },
		},
		states = {
			DISABLED,
			{ name = "read only", props = properties { readOnly = true } },
			{
				name = "custom glyphs",
				props = properties { segment = "glyph", glyphs = { filled = "●", empty = "○" } },
			},
			{
				name = "tint pair",
				props = properties {
					tint = { filled = Color3.fromRGB(63, 184, 113), empty = Color3.fromRGB(80, 80, 90) },
				},
			},
			{ name = "no zero", props = properties { allowZero = false } },
			{
				name = "change reported",
				props = function(c: Context)
					local value = c.cell("value", 3)
					return {
						onChange = function(v)
							value:set(v)
							c.log("onChange")(v)
						end,
					}
				end,
			},
		},
		valid = function(p: Properties)
			local glyphs = p.glyphs == nil or p.segment == "glyph"
			local images = (p.images == nil or p.segment == "image") and not (p.segment == "image" and p.images == nil)
			return glyphs and images
		end,
	},

	Badge = {
		family = "status",
		alias = "Badge · StatusBadge",
		purpose = "A short read-only label or status seal.",
		alternatives = "StatusIndicator for a dot/count; Chip when it can be selected.",
		scenarios = { "badge", "status_family" },
		snippet = 'UI.Badge { label = "New", appearance = "status", status = "success" }',
		base = function()
			return { label = "Badge" }
		end,
		axes = {
			{ key = "appearance", values = { "standard", "status", "utility" } },
			SIZES,
			{ key = "corners", values = { DEFAULT, "square", "rounded", "capsule", 4 } },
		},
		states = {
			{ name = "icon only (named)", props = properties { label = "", icon = "checkmark", name = "Verified" } },
			{ name = "success", props = properties { appearance = "status", status = "success" } },
			{ name = "warning", props = properties { appearance = "status", status = "warning" } },
			{ name = "error", props = properties { appearance = "status", status = "error" } },
			{ name = "info", props = properties { appearance = "status", status = "info" } },
			{ name = "accent", props = properties { appearance = "status", status = "accent" } },
			{ name = "neutral", props = properties { appearance = "status", status = "neutral" } },
			{ name = "voice", props = properties { appearance = "status", status = "voice" } },
			{ name = "contrast", props = properties { appearance = "status", status = "contrast" } },
			{ name = "icon", props = properties { icon = "checkmark" } },
			{ name = "trailing icon", props = properties { icon = "checkmark", iconPosition = "trailing" } },
			{
				name = "bound empty label (hidden)",
				props = properties {
					label = function(): string?
						return nil
					end,
				},
			},
		},
	},
	badged = {
		host = "Badge",
		family = "status",
		alias = "Badge placement A (corner seal)",
		purpose = "Puts a count or a dot on the corner of a Button, icon Button or Avatar without moving its box.",
		alternatives = "An inline Badge in a row.",
		scenarios = { "badge" },
		snippet = 'UI.badged(UI.Button { icon = "flag", shape = "circle", label = "Inbox" }, count)',
		base = function()
			return {}
		end,
		axes = {
			{ key = "value", values = { 3, 120, "1.2K", true, 0 } },
			{ key = "host", values = { "icon button", "button", "avatar" } },
		},
		states = {
			{ name = "right to left", props = properties { direction = "rtl" } },
			{ name = "accent status", props = properties { status = "accent" } },
		},
		make = function(UI: FacetControls, p: Properties): Instance
			local host = if p.host == "button"
				then UI.Button({ label = "Inbox" })
				elseif p.host == "avatar" then UI.Avatar({ name = "Ada Quill" })
				else UI.Button({ label = "Inbox", icon = "flag", shape = "circle" })
			return UI.badged(host, p.value, { direction = p.direction, status = p.status })
		end,
	},
	StatusIndicator = {
		family = "status",
		alias = "StatusIndicator",
		purpose = "A dot, ring, square or dash in a status colour, optionally with a count.",
		alternatives = "Badge for words.",
		scenarios = { "status_indicator", "status_family" },
		snippet = 'UI.StatusIndicator { status = "success" }',
		base = function()
			return { status = "success", name = "Online" }
		end,
		axes = {
			{ key = "form", values = { "dot", "ring", "square", "dash" } },
			SIZES,
			{
				key = "status",
				values = { "neutral", "info", "success", "warning", "error", "accent", "voice", "contrast" },
			},
		},
		states = {
			{ name = "diameter 28", props = properties { diameter = 28 } },
			{ name = "count", props = properties { count = 7 } },
			{ name = "count over max", props = properties { count = 150, max = 99 } },
			{ name = "cutout", props = properties { cutout = true } },
		},
		stateAxis = "status",
	},
	ProgressView = {
		family = "status",
		cellWidth = 240,
		alias = "Progress · Loading",
		purpose = "Determinate or indeterminate progress: a bar, ring, needle gauge or spinner; segments and a damage trail.",
		alternatives = "Skeleton for content that is still loading.",
		scenarios = { "progress_ring" },
		snippet = 'UI.ProgressView { value = 0.4, presentation = "bar" }',
		base = function()
			return { value = 0.4, label = "Uploading", Size = UDim2.fromScale(1, 0) }
		end,
		axes = {
			{
				key = "presentation",
				values = { "bar", "circular", "gauge", "spinner" },
				implies = implied { spinner = { value = NONE } },
			},
			{ key = "controlSize", values = { DEFAULT, "xsmall", "compact", "regular", "large" } },
		},
		states = {
			{ name = "indeterminate", props = properties { value = NONE } },
			{ name = "value shown", props = properties { showValue = true } },
			{ name = "end label", props = properties { endLabel = "3 of 7 files" } },
			{ name = "complete", props = properties { value = 1 } },
			{
				name = "min/max 0–200, formatted",
				props = properties {
					value = 120,
					min = 0,
					max = 200,
					showValue = true,
					format = function(v)
						return `{v} HP`
					end,
				},
			},
			{ name = "segments 5", props = properties { segments = 5 } },
			{ name = "thickness 10", props = properties { thickness = 10 } },
			{ name = "damage trail", props = properties { trail = { delay = 0.3, duration = 0.6 } } },
			{
				name = "ring sizes",
				props = properties { presentation = "circular" },
				across = "controlSize",
				matrixOnly = true,
			},
			{
				name = "spinner sizes",
				props = properties { presentation = "spinner", value = NONE },
				across = "controlSize",
				matrixOnly = true,
			},
			{
				name = "ring diameter 96, value shown",
				props = properties { presentation = "circular", diameter = 96, showValue = true },
				across = false,
				matrixOnly = true,
			},
			{ name = "gauge, value shown", props = properties { presentation = "gauge", showValue = true } },
			{ name = "gauge sweep 180", props = properties { presentation = "gauge", sweep = 180 } },
			{ name = "gauge sweep 300", props = properties { presentation = "gauge", sweep = 300 } },
			{ name = "gauge without needle", props = properties { presentation = "gauge", needle = false } },
			{
				name = "gauge sizes",
				props = properties { presentation = "gauge" },
				across = "controlSize",
				matrixOnly = true,
			},
		},
		valid = function(p: Properties)
			local shape = p.presentation or "bar"
			return not (shape == "spinner" and p.value ~= nil)
				and not (shape == "gauge" and p.value == nil)
				and not ((p.sweep ~= nil or p.needle ~= nil) and shape ~= "gauge")
				and not (p.showValue and p.value == nil)
				and not (p.segments ~= nil and shape ~= "bar")
				and not (p.diameter ~= nil and shape == "bar")
				and not (shape == "bar" and p.controlSize ~= nil and p.thickness ~= nil)
				and not (p.trail ~= nil and p.value == nil)
		end,
	},
	Skeleton = {
		family = "status",
		alias = "Skeleton",
		purpose = "Placeholder shapes while content loads; stops its clock when hidden or reduced.",
		alternatives = "ProgressView when progress is known.",
		scenarios = { "skeleton" },
		snippet = 'UI.Skeleton { form = "line", lines = 3 }',
		base = function()
			return { form = "line", Size = UDim2.fromOffset(200, 0), AutomaticSize = Enum.AutomaticSize.Y }
		end,
		axes = {
			{
				key = "form",
				values = { "box", "line", "circle" },
				implies = implied {
					circle = { Size = UDim2.fromOffset(64, 64) },
					box = { Size = UDim2.fromOffset(200, 64) },
				},
			},
			SIZES,
			{ key = "corners", values = { DEFAULT, "square", 4, "control", "panel", "pill" } },
		},
		states = { { name = "3 lines", props = properties { lines = 3 } } },
	},
	Avatar = {
		family = "status",
		valid = function(p: Properties)
			local faces = (if p.content ~= nil and p.content ~= "initials" then 1 else 0)
				+ (if p.image ~= nil then 1 else 0)
				+ (if p.resource ~= nil then 1 else 0)
			return faces <= 1
				and not (p.form == "icon" and p.presence ~= nil)
				and not (p.diameter ~= nil and p.controlSize ~= nil)
				and not (p.presenceLabel ~= nil and p.presence == nil)
		end,
		alias = "Avatar · AvatarIcon",
		purpose = "A person's picture or initials with an optional presence mark.",
		alternatives = "Image for decorative pictures.",
		scenarios = { "avatar", "identity" },
		snippet = 'UI.Avatar { name = "Ada Lovelace", presence = "online" }',
		base = function()
			return { name = "Ada Lovelace" }
		end,
		axes = {

			{ key = "content", values = { "initials", "image", "icon", "userId", "failed" } },
			{ key = "controlSize", values = { DEFAULT, "xsmall", "compact", "regular", "large" } },
			{ key = "form", values = { "standard", "icon" } },
			{ key = "presence", values = { DEFAULT, "online", "away", "busy", "offline", "inExperience" } },
		},
		make = function(UI: FacetControls, p: Properties): Instance
			local content = p.content
			p.content = nil
			if content == "image" then
				p.image = ART
			elseif content == "icon" then
				p.icon = "person"
			elseif content == "userId" then
				p.userId = 156
			elseif content == "failed" then
				p.image = "rbxassetid://999999999999999"
			end
			return UI.Avatar(p)
		end,
		demonstrates = { "image", "userId", "icon" },
		states = {
			{ name = "diameter 72", props = properties { diameter = 72, controlSize = NONE } },
			{ name = "localized presence", props = properties { presence = "online", presenceLabel = "En ligne" } },
			{ name = "no presence mark", props = properties { presence = "online", presenceMark = false } },
			{ name = "backplate", props = properties { backplate = true } },
			{ name = "background: accent", props = properties { background = "accent" } },
			{ name = "background: success", props = properties { background = "success" } },
			{
				name = "activatable",
				props = function(c: Context)
					return { onActivate = c.log("onActivate") }
				end,
			},
			{
				name = "custom loader + status",
				props = function(c: Context)
					return {
						loader = function(source, resolve)
							task.delay(0.5, resolve, source)
							return nil
						end,
						onStatus = c.log("onStatus"),
						image = ART,
					}
				end,
			},
			{
				name = "shared resource",
				props = function(c: Context)
					return {
						resource = c.Compose.createSharedResource(function()
							return { value = c.Compose.cell(ART), state = c.Compose.cell("ready") }
						end),
					}
				end,
			},
		},
	},
	AvatarGroup = {
		family = "status",
		alias = "AvatarGroup · AvatarIconGroup",
		purpose = "Several avatars stacked or spread, with an overflow count.",
		alternatives = "A list of Avatars when every person matters.",
		scenarios = { "avatar_group" },
		snippet = "UI.AvatarGroup { items = members, max = 3 }",
		base = function()
			local items: Properties = {}
			for i, name in { "Ada", "Grace", "Linus", "Margaret", "Alan", "Barbara" } do
				table.insert(items, { id = tostring(i), name = name })
			end
			items[1].image = ART
			items[2].userId = 156
			items[3].presence = "online"
			items[4].icon = "person"
			return { items = items, max = 4 }
		end,
		axes = {
			{ key = "layout", values = { "stacked", "spread" } },
			{ key = "overflow", values = { "count", "ellipsis" } },
			SIZES,
			{ key = "form", values = { "standard", "icon" } },
		},
		states = {
			{ name = "diameter 48", props = properties { diameter = 48 } },
			{ name = "localized overflow", props = properties { overflowLabel = "et 2 autres" } },
			{
				name = "activatable overflow",
				props = function(c: Context)
					return { onOverflow = c.log("onOverflow") }
				end,
			},
		},
		valid = function(p: Properties)
			return not (p.diameter ~= nil and p.controlSize ~= nil)
		end,
	},
	Label = {
		family = "status",
		alias = "InputLabel (icon + title) · Icon",
		purpose = "An icon beside a title, with presentation rules for compact spaces.",
		alternatives = "Text alone when no icon is needed.",
		scenarios = { "identity" },
		snippet = 'UI.Label { title = "Settings", icon = "settings" }',
		base = function()
			return { title = "Settings", icon = "settings" }
		end,
		axes = {
			{ key = "presentation", values = { "titleAndIcon", "titleOnly", "iconOnly" } },
			{ key = "iconPosition", values = { "leading", "trailing" } },
			{
				key = "icon",
				values = {
					"settings",
					"star",
					"heart",
					"chat",
					"gift",
					"coin",
					"gem",
					"bag",
					"trophy",
					"crown",
					"lock",
					"bolt",
					"wrench",
					"timer",
					"car",
				},
				props = properties { presentation = "iconOnly" },
			},
		},
		states = {
			{ name = "large icon", props = properties { iconSize = 32 } },
			{ name = "wide gap", props = properties { gap = "m" } },
			{ name = "long text", props = properties { title = LONG } },
			{ name = "strong", props = properties { textSize = "strong" } },
			{ name = "heading", props = properties { textSize = "heading" } },

			{ name = "filled icon", props = properties { icon = "person.fill" } },
		},
	},
	Notice = {
		family = "status",
		cellWidth = 320,
		alias = "BannerContext · Alert (inline)",
		purpose = "Inline or affixed status message with severity, link, actions and dismiss.",
		alternatives = "Toast for transient confirmation; Alert/Dialog for decisions.",
		scenarios = { "notice" },
		snippet = 'UI.Notice { severity = "warning", message = "Low storage" }',
		base = function()
			return { title = "Update available", message = "A new track pack is ready.", Size = UDim2.fromScale(1, 0) }
		end,
		axes = {
			{ key = "severity", values = { "info", "success", "warning", "error" } },
			{ key = "appearance", values = { "standard", "emphasis" } },
			{ key = "placement", values = { "inline", "affixed" }, matrix = false },
			{
				key = "controlSize",
				values = SIZES.values,
				props = function(c: Context)
					return {
						actions = { { id = "install", label = "Install", onActivate = c.log("install") } },
					}
				end,
			},
		},
		states = {
			{ name = "no icon", props = properties { icon = false } },
			{ name = "custom icon", props = properties { icon = "flag" } },
			{
				name = "actions + link",
				props = function(c: Context)
					return {
						link = { label = "Release notes", onActivate = c.log("link") },
						actions = { { id = "install", label = "Install", onActivate = c.log("install") } },
					}
				end,
			},
			{
				name = "dismissable",
				props = function(c: Context)
					return { onDismiss = c.log("onDismiss") }
				end,
			},
			{ name = "long text", props = properties { message = LONG .. ". " .. LONG } },
		},
	},
	AsyncImage = {
		family = "status",
		alias = "Image (async)",
		purpose = "An image with loading and failure states, a placeholder and an optional loader or shared resource.",
		alternatives = "Image for already-available content.",
		scenarios = { "async_images" },
		snippet = 'UI.AsyncImage { source = id, failureLabel = "Picture unavailable" }',
		base = function()
			return { source = "rbxthumb://type=AvatarHeadShot&id=156&w=150&h=150", Size = UDim2.fromOffset(150, 84) }
		end,
		axes = {},
		states = {
			{
				name = "fit mode (imageProperties)",
				props = properties { imageProperties = { ScaleType = Enum.ScaleType.Fit } },
			},
			{ name = "dimmed", props = properties { dimmed = true } },
			{
				name = "unavailable + label",
				props = properties { source = "rbxassetid://999999999999999", failureLabel = "Picture unavailable" },
			},
			{ name = "image key", props = properties { source = NONE, image = ART } },
			{
				name = "custom placeholder",
				props = function(c: Context)
					return {
						source = "rbxassetid://999999999999998",
						placeholder = function(stateNow)
							return c.UI.Text({
								text = function(use: Use)
									return `state: {use(stateNow)}`
								end,
								textRole = "caption",
							})
						end,
					}
				end,
			},
			{
				name = "slow loader + status",
				props = function(c: Context)
					return {
						loader = function(source, resolve)
							task.delay(1, resolve, source)
							return nil
						end,
						onStatus = c.log("onStatus"),
					}
				end,
			},
			{
				name = "shared resource",
				props = function(c: Context)
					return {
						source = NONE,
						resource = c.Compose.createSharedResource(function()
							return { value = c.Compose.cell(ART), state = c.Compose.cell("ready") }
						end),
					}
				end,
			},
		},
	},
	Image = {
		family = "status",
		alias = "Image · Images · Icon",
		purpose = "Images with framing, scale modes, tint, circle shape and resampling.",
		alternatives = "Avatar for people; AsyncImage for loaded images.",
		scenarios = { "leaf_capabilities" },
		snippet = 'UI.Image { image = "rbxassetid://…", scaleMode = "crop" }',
		base = function()
			return { image = ART, Size = UDim2.fromOffset(120, 80) }
		end,
		axes = { { key = "scaleMode", values = { "fit", "fill", "crop", "stretch" } } },
		states = {
			{ name = "pixelated", props = properties { resample = "pixelated" } },
			{ name = "tinted", props = properties { tint = Color3.fromRGB(60, 94, 246) } },
			{
				name = "circle",
				props = properties { shape = "circle", Size = UDim2.fromOffset(80, 80) },
				across = false,
			},
			{
				name = "tiled 40x40",
				props = properties { scaleMode = "tile", tileSize = { width = 40, height = 40 } },
				across = false,
			},
			{
				name = "nine-slice",
				props = properties {
					scaleMode = "slice",
					sliceCenter = { x0 = 64, y0 = 64, x1 = 192, y1 = 192 },
					sliceScale = 0.5,
				},
				across = false,
			},
		},
		valid = function(p: Properties)
			return (p.tileSize ~= nil) == (p.scaleMode == "tile") and (p.sliceCenter ~= nil) == (p.scaleMode == "slice")
		end,
	},
	Stage = {
		family = "status",
		alias = "Stage (3D preview)",
		purpose = "A native ViewportFrame with a camera and 3D content Compose owns; lazy build in scroll feeds.",
		alternatives = "Image for a flat picture.",
		scenarios = { "cards", "card_rail" },
		snippet = "UI.Stage { camera = CFrame.new(0, 2, 6), content = function(runtime, world, live) … end }",
		base = function(c: Context)
			return {
				Size = UDim2.fromOffset(240, 135),
				camera = CFrame.lookAt(Vector3.new(4, 3, 6), Vector3.zero),
				content = function(runtime, world, live): (() -> ())?
					local part = runtime.constructors.Part({
						Size = Vector3.new(2, 2, 2),
						Color = Color3.fromRGB(60, 94, 246),
						Anchored = true,
					})
					part.Parent = world
					local spin = game:GetService("RunService").Heartbeat:Connect(function(dt)
						if live:peek() then
							(part :: Part).CFrame *= CFrame.Angles(0, dt, 0)
						end
					end)
					return function()
						spin:Disconnect()
					end
				end,
			}
		end,
		axes = { { key = "fieldOfView", values = { 40, 70 } } },
		states = { { name = "lazy", props = properties { lazy = true } } },
	},

	Alert = {
		family = "overlays",
		matrix = false,
		alias = "Dialog (confirmation)",
		purpose = "A brief modal decision with one to three role-placed actions.",
		alternatives = "Dialog for richer content; Notice for non-blocking status.",
		scenarios = { "alert" },
		snippet = 'UI.Alert { isPresented = open, title = "Leave?", message = "…", actions = { … } }',
		base = function(c: Context)
			return {
				title = "Start this race?",
				message = "Your selected driver is ready.",
				actions = {
					{ id = "Cancel", label = "Cancel", role = "cancel", onActivate = c.log("cancel") },
					{ id = "Start", label = "Start", role = "default", onActivate = c.log("start") },
				},
			}
		end,
		axes = {
			{ key = "severity", values = { "information", "warning", "critical" } },

			{ key = "form", values = { "isPresented", "item", "presenting" }, matrix = false },
		},
		states = {
			{ name = "icon", props = properties { icon = "status.warning" } },
			{
				name = "custom content",
				props = function(c: Context)
					return {
						content = function(): Instance
							return c.UI.Text({ text = "3 laps · Coastal Circuit", role = "secondary" })
						end,
					}
				end,
			},
			{ name = "narrow (maxWidth 280)", props = properties { maxWidth = 280 } },
			{ name = "roomy padding 24", props = properties { padding = 24 } },
			{ name = "full screen", props = properties { surface = "fullScreen" } },
			{ name = "no motion", props = properties { transition = false } },
			{
				name = "error cell cleared on dismiss",
				props = function(c: Context)
					return { error = c.cell("alertError", "Save failed") }
				end,
			},
			{
				name = "destructive + shortcut",
				props = function(c: Context)
					return {
						actions = {
							{
								id = "Cancel",
								label = "Cancel",
								role = "cancel",
								shortcut = "cancelAction",
								onActivate = c.log("cancel"),
							},
							{
								id = "Delete",
								label = "Delete",
								role = "destructive",
								shortcut = "defaultAction",
								onActivate = c.log("delete"),
							},
						},
					}
				end,
			},
			{ name = "long text", props = properties { message = LONG .. ". " .. LONG } },
			{
				name = "don't ask again",
				props = function(c: Context)
					return { suppression = { isSuppressed = c.cell("suppressed", false), label = "Don't ask again" } }
				end,
			},
		},
		demonstrates = { "isPresented", "item", "presenting" },
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local form = p.form or "isPresented"
			p.form = nil
			if form == "item" then
				local item = c.Compose.cell(nil :: { name: string }?)
				p.item = item
				p.title = function(data)
					return `Delete {data.name}?`
				end
				return UI.VStack(stacked({
					gap = "xs",
					UI.Button({
						label = "Show for an item",
						onActivate = function()
							item:set({ name = "Coastal Circuit" })
						end,
					}),
					UI.Alert(p),
				}))
			end
			return trigger(c, "Show alert", function(open)
				p.isPresented = open
				if form == "presenting" then
					p.presenting = { name = "Canyon Run" }
					p.title = function(data)
						return `Start {data.name}?`
					end
				end

				return UI.Alert(p)
			end)
		end,
	},
	Dialog = {
		family = "overlays",
		demonstrates = { "isPresented", "onPresentedChange", "onDismiss" },
		matrix = false,
		alias = "Dialog (Title · Content · Actions · HeroMedia)",
		purpose = "A modal surface with title, content, hero media and actions.",
		alternatives = "Alert for a short decision; Sheet for a task panel.",
		scenarios = { "overlays" },
		snippet = 'UI.Dialog { isPresented = open, title = "Terms", content = body, actions = { … } }',
		base = function(c: Context)
			return {
				title = "Leave the lobby?",
				content = function(): Instance
					return c.UI.Text({
						text = "Your spot will be given to another player.",
						wrap = true,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					})
				end,
				actions = {
					{ id = "Stay", label = "Stay", role = "cancel", onActivate = c.log("stay") },
					{
						id = "Leave",
						label = "Leave",
						role = "destructive",
						onActivate = c.log("leave"),
					},
				},
				closeButton = false,
			}
		end,
		axes = {
			{ key = "width", values = { "automatic", "narrow", "wide" } },
			{ key = "actionLayout", values = { "automatic", "row", "stacked" } },
		},
		states = {
			{ name = "close button", props = properties { closeButton = true } },

			{
				name = "Apply keeps it open",
				props = function(c: Context)
					return {
						actions = dialogActions {
							{ id = "Stay", label = "Stay", role = "cancel", onActivate = c.log("stay") },
							{
								id = "Apply",
								label = "Apply",
								role = "default",
								keepOpen = true,
								onActivate = c.log("apply (stays open)"),
							},
							{
								id = "Leave",
								label = "Leave",
								role = "destructive",
								onActivate = c.log("leave"),
							},
						},
					}
				end,
			},
			{ name = "hero", props = properties { hero = { image = ART, aspectRatio = 2, scaleMode = "crop" } } },
			{ name = "action label", props = properties { actionLabel = "Choose carefully: this cannot be undone." } },
			{
				name = "long rich body (selectable)",
				props = function(c: Context)
					return {
						contentSelectable = true,
						content = function(): Instance
							return c.UI.Text({
								rich = true,
								wrap = true,
								text = string.rep("<b>Rule.</b> " .. LONG .. ". ", 12),
								Size = UDim2.fromScale(1, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
							})
						end,
					}
				end,
			},
		},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			return trigger(c, "Show dialog", function(open)
				p.isPresented = open
				p.onPresentedChange = function(v)
					c.log("onPresentedChange")(v)
					open:set(v)
				end
				p.onDismiss = c.log("onDismiss")
				return UI.Dialog(p)
			end)
		end,
	},
	Sheet = {
		family = "overlays",
		demonstrates = { "isPresented", "transition", "onPresentedChange" },
		matrix = false,
		alias = "Sheet (Root · Header · Content · Actions · FullBleed)",
		purpose = "A draggable panel with detents; bottom, side, centre or adaptive placement.",
		alternatives = "Dialog for a short modal; Popover for anchored content.",
		scenarios = { "sheet" },
		snippet = 'UI.Sheet { title = "Filters", isPresented = open, detent = detent, content = body }',
		base = function(c: Context)
			return {
				title = "Filters",
				detent = c.cell("detent", "medium"),
				detents = { "medium", "large" } :: { SheetDetent },
				content = function(): Instance
					return c.UI.VStack(stacked({
						width = "fill",
						gap = "s",
						c.UI.Toggle({ label = "Only friends", value = c.cell("friends", false) }),
						c.UI.Slider({
							Name = "Distance",
							label = "Distance",
							value = c.cell("dist", 5),
							min = 0,
							max = 10,
							Size = UDim2.fromScale(1, 0),
						}),
					}))
				end,
			}
		end,
		axes = {
			{ key = "placement", values = { "adaptive", "automatic", "bottom", "side", "center" } },
			{ key = "width", values = { "automatic", "narrow", "wide" } },
			{ key = "dragIndicator", values = { "automatic", "visible", "hidden" } },
		},
		states = {
			{
				name = "no interactive dismiss",
				props = properties { interactiveDismissDisabled = true, closeButton = true },
			},
			{
				name = "stacked actions",
				props = function(c: Context)
					return {
						actionLayout = "stacked",
						actions = actionList {
							{
								id = "Apply",
								label = "Apply",
								role = "default",
								onActivate = c.log("apply"),
							},
							{ id = "Reset", label = "Reset", onActivate = c.log("reset") },
						},
					}
				end,
			},
			{ name = "body pans the sheet", props = properties { scrollPolicy = "atLargestDetent" } },
			{ name = "close button", props = properties { closeButton = true } },
			{ name = "starts on Distance", props = properties { initialFocus = "Distance" } },
			{ name = "close label", props = properties { closeButton = "Close" } },
			{ name = "no content inset", props = properties { contentInset = "none" } },
			{
				name = "full-bleed hero (sticky)",
				props = properties { hero = { image = ART, aspectRatio = 2, sticky = true } },
			},
			{
				name = "custom header",
				props = function(c: Context)
					return {
						header = function()
							return c.UI.Text({ text = "Custom header", textRole = "heading" })
						end,
					}
				end,
			},
			{ name = "no header", props = properties { header = false } },
			{
				name = "hug + fraction + fixed detents",
				props = function(c: Context)
					return {
						detents = {
							"hug" :: SheetDetent,
							{ id = "third", fraction = 0.33 },
							{ id = "tall", height = 520 },
						} :: { SheetDetent },
						detent = c.cell("hugDetent", "hug"),
					}
				end,
			},
			{ name = "left edge", props = properties { placement = "side", edge = "left" } },
			{ name = "button guide", props = hintPages.sheetGuide },
		},
		valid = function(p: Properties)
			return p.edge == nil or p.placement == "side" or p.placement == "adaptive"
		end,
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local shown = trigger(c, "Show sheet", function(open)
				p.isPresented = open
				p.onPresentedChange = function(nextValue: boolean)
					c.log("presentation requested")(nextValue)
					open:set(nextValue)
				end
				return UI.Sheet(p)
			end)
			if p.placement == "bottom" then
				return UI.VStack(stacked({ gap = "xs", shown, require("./sheet_glass_demo")(c) }))
			end
			return shown
		end,
	},
	Popover = {
		family = "overlays",
		matrix = false,
		alias = "Popover (Anchor · Content · Root)",
		purpose = "Anchored content that stays attached to its trigger; becomes a sheet on compact touch screens.",
		alternatives = "Callout for teaching; Menu for actions.",
		scenarios = { "overlays" },
		snippet = "UI.Popover { isPresented = open, trigger = button, content = body }",
		base = function(c: Context)
			local open = c.cell("open", false)
			return {
				isPresented = open,
				onPresentedChange = function(v)
					open:set(v)
				end,
				trigger = c.UI.Button({ label = "About" }),
				content = function(): Instance
					return c.UI.Text({
						text = "Anchored content with a tail.",
						wrap = true,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					})
				end,
				maxWidth = 280,
			}
		end,
		axes = {
			{ key = "edge", values = { "bottom", "top", "leading", "trailing" } },
			{ key = "align", values = { "start", "center", "end" } },
		},
		states = {
			{ name = "Close shown", props = properties { closeButton = true } },
			{ name = "Close hidden", props = properties { closeButton = false } },
			{
				name = "HUD settings (non-modal on touch)",
				props = properties { modal = false, compact = "popover", closeButton = true },
			},
			{ name = "cancel policy none", props = properties { cancelPolicy = "none" } },
			{
				name = "dismiss reported",
				props = function(c: Context)
					return { onDismiss = c.log("onDismiss") }
				end,
			},
			{ name = "gap 24", props = properties { gap = 24 } },
			{
				name = "bounded height (scrolls)",
				props = function(c: Context)
					return {
						maxHeight = 120,
						content = function(): Instance
							return c.UI.Text({
								text = string.rep("Anchored content with a tail. ", 12),
								wrap = true,
								Size = UDim2.fromScale(1, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
							})
						end,
					}
				end,
			},
			{ name = "no tail", props = properties { tail = false } },
			{ name = "stays a popover on touch", props = properties { compact = "popover" } },
			{ name = "sheet title (compact touch)", props = properties { title = "About scoring" } },
			{ name = "cross offset 24", props = properties { crossOffset = 24 } },
			{
				name = "rect source",
				props = function(c: Context)
					local open = c.cell("open", false)
					return {
						trigger = NONE,
						source = { rect = { x = 600, y = 300, w = 40, h = 40 } },
						isPresented = open,
					}
				end,
			},
		},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			if p.trigger == nil then
				local open = p.isPresented
				return UI.VStack(stacked({
					gap = "xs",
					UI.Button({
						label = "Open at a rect",
						onActivate = function()
							open:set(true)
						end,
					}),
					UI.Popover(p),
				}))
			end
			return UI.Popover(p)
		end,
		demonstrates = { "source" },
	},
	Callout = {
		family = "overlays",
		cellHeight = 220,
		matrix = false,
		alias = "EducationalTooltip · Coachmark",
		purpose = "Teaches a feature anchored to a control, with steps, media, actions and retirement rules.",
		alternatives = "help on a Button for a hover/focus tooltip; Popover for arbitrary content.",
		scenarios = { "callout" },
		snippet = 'UI.Callout { anchor = button, title = "New!", onRetire = retire }',
		base = function(c: Context)
			return {
				title = "New: lap counter",
				content = function(): Instance
					return c.UI.Text({ text = "Press Plus to add a lap." })
				end,
				onRetire = c.log("onRetire"),
			}
		end,

		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local anchor = UI.Button({ label = "Plus", onActivate = c.log("plus") })
			p.anchor = anchor
			return UI.VStack(stacked({
				gap = "xs",
				padding = { top = 60, bottom = 60 },
				anchor,
				UI.Callout(p),
			}))
		end,
		demonstrates = { "anchor" },
		axes = {
			{ key = "edge", values = { "bottom", "top", "leading", "trailing" } },
			{ key = "align", values = { "leading", "center", "trailing" } },
		},
		states = {
			{ name = "dismiss label", props = properties { dismissLabel = "Got it!" } },
			{ name = "priority 2", props = properties { priority = 2 } },
			{
				name = "show / hide reported",
				props = function(c: Context)
					return { onShow = c.log("onShow"), onHide = c.log("onHide") }
				end,
			},
			{ name = "already seen (retired)", props = properties { seen = true } },
			{ name = "after 2 sessions (not yet)", props = properties { sessions = 1, afterSessions = 2 } },
			{ name = "feature used (retired)", props = properties { featureUsed = true } },
			{ name = "steps", props = properties { steps = { index = 1, count = 3 } } },
			{ name = "close button", props = properties { closeButton = true } },
			{ name = "media", props = properties { media = { image = ART, aspectRatio = 2 } } },
			{
				name = "two actions",
				props = function(c: Context)
					return {
						actions = actionList {
							{ id = "Try", label = "Try it", role = "default", onActivate = c.log("try") },
							{ id = "Later", label = "Later", onActivate = c.log("later") },
						},
					}
				end,
			},
			{ name = "no tail", props = properties { tail = false } },
			{
				name = "controlled presentation",
				props = function(c: Context)
					return { isPresented = c.cell("calloutShown", true) }
				end,
			},
		},
	},

	TabView = {
		family = "navigation",
		cellWidth = 280,
		cellHeight = 220,
		alias = "Tabs · SideNav",
		purpose = "Peer destinations with lazy pages; adaptive placement (sidebar, top, bottom), sections and customization.",
		alternatives = "Picker (segmented) for a value inside a page; NavigationStack for drill-down.",
		scenarios = { "containers", "all_controls" },
		snippet = 'UI.TabView { selection = tab, tabs = { { id = "a", label = "A", content = pageA } } }',
		base = function(c: Context)
			local function page(text)
				return function()
					return c.UI.Text({ text = text })
				end
			end
			return {
				selection = c.cell("tab", "one"),
				tabs = {
					{ id = "one", label = "One", icon = "flag", content = page("First page") },
					{ id = "two", label = "Two", icon = "edit", badge = 3, content = page("Second page") },
					{
						id = "three",
						label = "Three",
						icon = "person",
						indicator = { status = "success" },
						content = page("Third page"),
					},
				},
				Size = UDim2.fromScale(1, 1),
			}
		end,
		axes = {
			{ key = "indicator", values = { "automatic", "underline", "pill", "none" } },
			SIZES,
			{ key = "placement", values = { "automatic", "topBar", "bottomBar", "bottomBarCompact", "sidebar" } },
		},
		states = {
			{
				name = "floating phone track and icon mark",
				props = properties {
					track = "floating",
					indicator = "mark",
					placement = "bottomBar",
					labelPlacement = "belowIcon",
					controlSize = "compact",
				},
				across = false,
			},
			{
				name = "floating rail and inset selection",
				props = properties { track = "floating", indicator = "mark", placement = "sidebar", railWidth = 120 },
				across = false,
			},
			{
				name = "floating mark and bottom badge anchor",
				props = function(c: Context)
					return {
						selection = c.cell("tab", "one"),
						track = "floating",
						indicator = "mark",
						indicatorPlacement = "belowIcon",
						placement = "bottomBar",
						labelPlacement = "belowIcon",
						tabs = {
							{
								id = "one",
								label = "Games",
								icon = "view.grid",
								badge = 3,
								badgeAnchor = "bottomTrailing",
								content = function()
									return c.UI.Text {
										text = "The badge is below the icon. The mark has its own label gap.",
									}
								end,
							},
							{
								id = "two",
								label = "Profile",
								icon = "person",
								content = function()
									return c.UI.Text { text = "Profile page" }
								end,
							},
						} :: {
							{
								id: string,
								label: string,
								icon: string,
								badge: number?,
								badgeAnchor: string?,
								content: () -> Instance,
							}
						},
					}
				end,
				across = false,
			},
			{ name = "labels below icons", props = properties { labelPlacement = "belowIcon" } },
			{ name = "labels beside icons", props = properties { labelPlacement = "besideIcon" } },
			{
				name = "sidebar adaptable, expanded at ten feet",
				props = function(c: Context)
					return {
						style = "sidebarAdaptable",
						sidebarExpanded = c.cell("expanded", true),
					}
				end,
				across = false,
			},
			DISABLED,
			{ name = "icon only", props = properties { iconOnly = true } },
			{ name = "text size 12", props = properties { textSize = 12 } },
			{
				name = "sidebar adaptable",
				props = properties { style = "sidebarAdaptable", railWidth = 120 },
				across = false,
			},
			{ name = "collapsible", props = properties { style = "collapsible" }, across = false },
			{ name = "retain only the top page", props = properties { retention = "top" } },
			{ name = "no motion", props = properties { transition = false } },
			{ name = "slow crossfade", props = properties { transition = { seconds = 0.6 } } },
			{
				name = "sections + customization",
				props = function(c: Context)
					return {
						style = "sidebarAdaptable",
						sidebarPreference = "sidebar",
						sections = { { id = "main", label = "Main" } },
						customization = { order = { "three", "one", "two" }, hidden = {} },
						accessories = {
							foot = function()
								return c.UI.Button({ label = "Edit", appearance = "utility" })
							end,
						},
					}
				end,
				across = false,
			},
			{ name = "shoulders move the content", props = properties { shoulderNavigation = "content" } },
			{ name = "no scroll/focus restore", props = properties { restoreScroll = false, restoreFocus = false } },
			{
				name = "change reported",
				props = function(c: Context)
					return { onChange = c.log("onChange") }
				end,
			},
		},
		valid = function(p: Properties)
			local placement = p.placement or "automatic"
			return not ((p.style == "sidebarAdaptable" or p.style == "collapsible") and placement ~= "automatic")
				and not (p.sidebarPreference ~= nil and p.style ~= "sidebarAdaptable")
		end,
	},
	NavigationSplitView = {
		family = "navigation",
		cellWidth = 760,
		cellHeight = 420,
		alias = "(Facet) related panes",
		purpose = "Shows panes side by side or stacked top/bottom, with a resize divider and compact navigation.",
		alternatives = "NavigationStack for a hierarchy; TabView for peer destinations.",
		scenarios = { "collection_workbench" },
		snippet = "UI.NavigationSplitView { sidebar = files, detail = linkedFiles }",
		base = function(c: Context)
			return {
				preferredCompactColumn = c.cell("column", "sidebar"),
				backLabel = "Files",
				detailLabel = "Linked files",
				sidebarWidth = c.cell("width", 320),
				sidebarHeight = c.cell("height", 220),
				sidebar = function(): Instance
					return c.UI.Button { label = "Files" }
				end,
				detail = function(): Instance
					return c.UI.Button { label = "Linked files" }
				end,
			}
		end,
		axes = {
			{ key = "axis", values = { "x", "y" } },
			{ key = "resizable", values = { true, false } },
			{ key = "alwaysShowResizeHandle", values = { true, false } },
		},
		states = {
			{ name = "compact: Files opens detail, no Show detail row", cellWidth = 380, props = splitBack(false) },
			{ name = "compact: the detail NavBar owns Back (compactBack)", cellWidth = 380, props = splitBack(true) },
		},
	},

	NavigationStack = {
		family = "navigation",
		cellWidth = 320,
		cellHeight = 200,
		alias = "(Facet) drill-down navigation",
		purpose = "Pushes detail screens with Back; a spring slide by default, or a crossfade.",
		alternatives = "TabView for peers.",
		scenarios = { "navigation_stack" },
		snippet = 'UI.NavigationStack { path = path, root = { title = "Garage", content = list }, destinations = { … } }',
		base = function(c: Context)
			local path = c.cell("path", {})
			return {
				path = path,
				backLabel = "Back",
				Size = UDim2.fromScale(1, 1),
				root = {
					title = "Garage",
					content = function(): Instance
						return c.UI.Button({
							label = "Open car",
							onActivate = function()
								path:set({ { id = "car", value = "Rally 7" } })
								c.log("push car")()
							end,
						})
					end,
				},
				destinations = {
					car = {
						title = "Car",
						content = function(entry): Instance
							return c.UI.Button({ label = `Drive {entry and entry.value or "?"}` })
						end,
					},
				},
			}
		end,
		axes = {
			{ key = "transition", values = { DEFAULT, false }, matrix = false },
		},
		states = {
			{ name = "crossfade 0.3 s", props = properties { transition = { seconds = 0.3 } } },
			{
				name = "page owns its header",
				across = false,
				props = function(c: Context)
					local path = c.cell("path", {})
					return {
						chrome = "hidden",
						destinations = {
							car = {
								chrome = "hidden",
								initialFocus = "Drive",
								content = function(): Instance
									return c.UI.VStack {
										width = "fill",
										height = "fill",
										c.UI.Text { text = "My page header", textRole = "heading" },
										c.UI.Button {
											label = "Back",
											onActivate = function()
												path:set({})
											end,
										},
										c.UI.Button "Drive" { label = "Drive (initialFocus selects it)" },
										c.UI.Text {
											text = "This page uses the whole stack rectangle. Back also uses Escape, B or a right swipe from the left edge.",
											TextWrapped = true,
										},
									}
								end,
							},
						},
					}
				end,
			},
		},
	},
	NavBar = {
		family = "navigation",
		cellWidth = 360,
		alias = "HeaderBar (Leading · Content · Trailing · Actions)",
		purpose = "A header row with back, title and leading/centre/trailing slots.",
		alternatives = "A plain HStack when there is no navigation.",
		scenarios = { "overlays" },
		snippet = 'UI.NavBar { title = "Garage", onBack = back, trailing = tools }',
		base = function(c: Context)
			return {
				title = "Garage",
				onBack = c.log("onBack"),
				backLabel = "Back",
				trailing = c.UI.Button({ label = "Edit", appearance = "utility", onActivate = c.log("edit") }),
				Size = UDim2.fromScale(1, 0),
			}
		end,
		axes = { { key = "surface", values = { DEFAULT, "surface", "panel", "pane" } } },
		states = {
			{ name = "heading title size", props = properties { titleSize = "heading" } },
			{ name = "wide gap + padding", props = properties { gap = 24, padding = 16 } },
			{ name = "long title", props = properties { title = LONG } },
			{ name = "no back", props = properties { onBack = NONE } },
			{
				name = "back from a cell",
				props = function(c: Context)
					return { onBack = c.cell("navBack", true) }
				end,
			},
			{
				name = "leading slot",
				props = function(c: Context)
					return {
						leading = c.UI.Label({
							title = "Garage",
							icon = "settings",
							presentation = "iconOnly",
						}),
					}
				end,
			},
			{
				name = "centre slot",
				props = function(c: Context)
					return {
						center = c.UI.Picker({
							selected = c.cell("navSeg", "a"),
							style = "segmented",
							options = {
								{ value = "a", label = "Cars" },
								{ value = "b", label = "Parts" },
							},
						}),
					}
				end,
			},
		},
	},
	PageView = {
		family = "navigation",
		cellWidth = 360,
		cellHeight = 220,
		alias = "(Facet) paged carousel",
		purpose = "Swipeable pages with indicators, summary and previous/next controls.",
		alternatives = "Pagination for result pages.",
		scenarios = { "page_view" },
		snippet = 'UI.PageView { selection = page, pages = { { id = "a", label = "A", content = view } } }',
		base = require("./page_view_demo"),
		axes = {},
		states = {
			{
				name = "rotating carousel",
				props = properties { autoAdvanceSeconds = 20, scrollWheel = true, controls = false, summary = false },
			},
			{ name = "no summary", props = properties { summary = false } },
			{ name = "no controls", props = properties { controls = false } },
			{ name = "no indicators", props = properties { indicators = false } },
			{
				name = "overlay indicators",
				props = properties { indicatorPlacement = "overlay", summary = false, controls = false },
			},
		},
	},
	Pagination = {
		family = "navigation",
		cellWidth = 360,
		alias = "Pagination",
		purpose = "Moves between numbered result pages, or next/previous for unknown counts.",
		alternatives = "PageView for swiped content.",
		scenarios = { "paging" },
		snippet = "UI.Pagination { page = page, pageCount = 12, onChange = function(n) page:set(n) end }",
		base = function(c: Context)
			local page = c.cell("page", 4)
			return {
				page = page,
				pageCount = 12,
				onChange = function(n)
					page:set(n)
					c.log("onChange")(n)
				end,
			}
		end,
		axes = {
			{ key = "form", values = { "numbers", "arrows", "label" } },
			SIZES,
			{ key = "direction", values = { "ltr", "rtl" } },
		},
		states = {
			{
				name = "two siblings, two at each end",
				props = properties { siblingCount = 2, boundaryCount = 2, pageCount = 20 },
			},
			DISABLED,
			{ name = "first/last", props = properties { showFirstLast = true } },
			{ name = "unknown total", props = properties { pageCount = NONE, hasNext = true, hasPrevious = true } },
			{ name = "no pages", props = properties { pageCount = 0 } },
			{ name = "diagnostics table", props = properties { controls = {} } },
		},
	},
	StepIndicator = {
		family = "navigation",
		cellWidth = 420,
		alias = "(Facet) workflow steps",
		purpose = "Shows progress through a multi-step workflow; steps may be navigable or in error.",
		alternatives = "Stepper is a numeric control, not this.",
		scenarios = { "steps" },
		snippet = "UI.StepIndicator { steps = steps, current = current, onSelect = select }",
		base = function(c: Context)
			local current = c.cell("current", "ship")
			local logSelect = c.log("onSelect")
			return {
				steps = {
					{ id = "cart", label = "Cart", state = "complete", navigable = true } :: {
						id: string,
						label: string,
						state: string?,
						navigable: boolean?,
						description: string?,
						enabled: boolean?,
					},
					{ id = "ship", label = "Shipping", description = "Address and speed", navigable = true },
					{ id = "pay", label = "Payment", state = "error", navigable = true },
					{ id = "review", label = "Review", enabled = false },
				},
				current = current,
				onSelect = function(id)
					current:set(id)
					logSelect(id)
				end,
				Size = UDim2.fromScale(1, 0),
			}
		end,
		axes = { SIZES, { key = "sizing", values = { "fill", "hug" } } },
		states = {
			DISABLED,
			{
				name = "list label (narrow)",
				props = properties { listLabel = "All steps", Size = UDim2.fromOffset(200, 0) },
			},
			{ name = "diagnostics table", props = properties { controls = {} } },
		},
	},
	DisclosureGroup = {
		family = "navigation",
		cellWidth = 280,
		alias = "Accordion (Item · Root) · Outline row",
		purpose = "Shows and hides a section of content under a labelled header.",
		alternatives = "CollapsibleView for a single expandable panel with its own chrome.",
		scenarios = { "containers", "collapsible_view" },
		snippet = 'UI.DisclosureGroup { label = "Race rules", expanded = open, outsideDismiss = true, content = body }',

		base = function(c: Context)
			return {
				label = "Race rules",
				expanded = c.cell("expanded", true),
				content = function(): Instance
					return c.UI.VStack(stacked({
						width = "fill",
						gap = "xs",
						c.UI.Toggle({
							label = "Collisions",
							value = c.cell("collisions", true),
							Size = UDim2.fromScale(1, 0),
						}),
						c.UI.Toggle({
							label = "Catch-up boost",
							value = c.cell("boost", false),
							Size = UDim2.fromScale(1, 0),
						}),
						c.UI.Text({
							text = "Laps and items follow the track's defaults unless a host changes them.",
							role = "secondary",
							wrap = true,
							Size = UDim2.fromScale(1, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
						}),
					}))
				end,
				Size = UDim2.fromScale(1, 0),
			}
		end,
		axes = {
			{ key = "appearance", values = { "plain", "contained", "divided", "outline" } },
			{ key = "chevronPosition", values = { "leading", "trailing" } },
		},
		states = {
			DISABLED,
			{
				name = "collapsed",
				props = function(c: Context)
					return { expanded = c.cell("shut", false) }
				end,
			},
			{ name = "description", props = properties { description = "Three settings" } },
			{ name = "icon", props = properties { icon = "settings" } },
			{ name = "outline row type + indent", props = properties { textSize = "label", indent = "m" } },
			{
				name = "toggle reported",
				props = function(c: Context)
					return { onToggle = c.log("onToggle") }
				end,
			},

			{ name = "single-open group", props = properties { singleOpen = true }, across = false },
		},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			if not p.singleOpen then
				return UI.DisclosureGroup(p)
			end
			p.singleOpen = nil
			local sections = { "Rules", "Rewards", "Credits" }
			local cells = {}
			for _, name in sections do
				cells[name] = c.cell(`open{name}`, name == "Rules")
			end
			local list: Properties = { width = "fill", gap = "xs" }
			for _, name in sections do
				local spec = table.clone(p)
				spec.label = name
				spec.expanded = cells[name]
				spec.onToggle = function(open)
					if open then
						c.app.runtime:batch(function()
							for other, cell in cells do
								if other ~= name then
									cell:set(false)
								end
							end
						end)
					end
				end
				table.insert(list, UI.DisclosureGroup(spec))
			end
			return UI.VStack(list)
		end,
	},
	CollapsibleView = {
		family = "navigation",
		alias = "(Facet) collapsible panel",
		purpose = "A button that expands into a larger presented panel, restoring focus when it collapses.",
		alternatives = "DisclosureGroup inside lists.",
		scenarios = { "collapsible_view" },
		snippet = 'UI.CollapsibleView { label = "Filters", expanded = open, content = body }',
		base = function(c: Context)
			return {
				label = "Filters",
				expanded = c.cell("expanded", false),
				content = function(): Instance
					return c.UI.VStack({
						gap = "s",
						padding = "m",
						c.UI.Text({ text = "Panel content" }),
						c.UI.Button "Apply" { label = "Apply" },
					})
				end,
			}
		end,
		axes = { { key = "appearance", values = { "standard", "emphasis", "soft", "utility" } } },
		states = {
			{ name = "native glyph", props = nativeGlyph },
			DISABLED,
			{ name = "icon", props = properties { icon = "settings" } },
			{ name = "dismiss button", props = properties { dismissButton = true } },
			{ name = "outside dismissal disabled", props = properties { outsideDismiss = false } },
			{ name = "selected", props = properties { selected = true } },
			{ name = "initial focus: Apply", props = properties { initialFocus = "Apply" } },
			{
				name = "activation reported",
				props = function(c: Context)
					return { onActivate = c.log("onActivate") }
				end,
			},
		},
	},

	Card = {
		family = "collections",
		cellWidth = 240,
		alias = "(Facet) media card with action reveal",
		purpose = "Artwork, title and caption with a primary action and a More menu revealed on hover/focus.",
		alternatives = "Image Button for a single action.",
		scenarios = { "cards", "card_rail" },
		snippet = 'UI.Card { image = art, title = "Coast", primaryAction = { label = "Play", onActivate = play } }',
		base = function(c: Context)
			return {
				image = ART,
				title = "Coastal Circuit",
				caption = "12 playing",
				onActivate = c.log("onActivate"),
				primaryAction = { label = "Play", icon = "flag", onActivate = c.log("play") },
				menu = { items = menuItems(c), label = "More" },
				Size = UDim2.fromScale(1, 0),
			}
		end,
		axes = {
			{ key = "reveal", values = { "automatic", "always" } },

			{ key = "ringTarget", values = { "card", "media" } },
		},
		states = {
			DISABLED,
			{ name = "long title", props = properties { title = LONG } },
			{ name = "square artwork", props = properties { imageAspectRatio = 1 } },
			{ name = "fit framing", props = properties { imageFraming = "fit" } },
			{ name = "informational (no body action)", props = properties { onActivate = NONE } },
			{ name = "no actions (ends at the body)", props = properties { primaryAction = NONE, menu = NONE } },
			{
				name = "badges",
				props = properties {
					badges = {
						leading = { label = "Rare", status = "accent" },
						trailing = { label = "Owned", status = "success", icon = "checkmark" },
					},
				},
			},
			{
				name = "3D artwork",
				props = function(c: Context)
					return {
						artwork = function()
							return c.UI.Stage({ camera = CFrame.lookAt(Vector3.new(4, 3, 6), Vector3.zero) })
						end,
					}
				end,
			},
			{ name = "controls table", props = properties { controls = {} } },

			{ name = "row of cards", props = properties { row = true }, across = false, cellWidth = 740 },
		},
		demonstrates = { "browseTarget" },
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			if not p.row then
				return UI.Card(p)
			end
			p.row = nil
			local cards: Properties = {
				gap = "m",
				columns = function(use: Use)
					return c.Facet.adaptive.columnsFor(use(c.logical).width - 400, 200, 16)
				end,
				cellHeight = 240,
				Size = UDim2.fromOffset(720, 0),
			}
			for i, name in { "Coastal Circuit", "Canyon Run", "City Loop" } do
				local spec = table.clone(p)
				spec.title = name
				spec.onActivate = c.log(`open {i}`)
				spec.primaryAction = { label = "Play", onActivate = c.log(`play {i}`) }
				table.insert(cards, UI.Card(spec))
			end
			return UI.Grid(cards)
		end,
	},
	CellEditor = {
		family = "collections",
		cellWidth = 280,
		cellHeight = 90,
		purpose = "A row label that becomes a text field while renaming, with durable drafts and commit validation.",
		alternatives = "TextInput for immediate text changes.",
		scenarios = { "table_virtualized" },
		snippet = 'UI.CellEditor { editor = "text", value = name, draft = draft, onChange = save }',
		base = function(c: Context)
			local value = c.cell("value", "Coast")
			return {
				editor = "text",
				label = "File name",
				value = value,
				draft = c.cell("draft", nil),
				onChange = function(v)
					value:set(v)
				end,
				Size = UDim2.fromScale(1, 1),
			}
		end,
		states = {
			DISABLED,
			{ name = "pending", props = properties { busy = true } },
			{ name = "custom edit action", props = properties { editLabel = "Edit title" } },
			{
				name = "renaming",
				props = function(c: Context)
					return { editing = c.cell("cellEditing", true) }
				end,
			},
			{
				name = "validation",
				props = properties {
					validate = function(v)
						return if v == "" then "Enter a name." else nil
					end,
				},
			},
			{
				name = "number",
				props = function(c: Context)
					return {
						editor = "number",
						value = c.cell("number", 10),
						onChange = function(v)
							c.cell("number", 10):set(v)
						end,
						min = 0,
						max = 100,
						step = 1,
					}
				end,
			},
			{
				name = "menu",
				props = function(c: Context)
					return {
						editor = "menu",
						draft = NONE,
						value = c.cell("menu", "Blue"),
						options = { { value = "Blue", label = "Blue" }, { value = "Coral", label = "Coral" } },
						onChange = function(v)
							c.cell("menu", "Blue"):set(v)
						end,
					}
				end,
			},
			{
				name = "toggle",
				props = function(c: Context)
					return {
						editor = "toggle",
						draft = NONE,
						value = c.cell("flag", true),
						onChange = function(v)
							c.cell("flag", true):set(v)
						end,
					}
				end,
			},
		},
	},

	Table = {
		family = "collections",
		demonstrates = {
			"selectionFrom",
			"selectionIndicator",
			"rowActions",
			"focusPolicy",
			"initialFocus",
			"autoFocus",
			"wrapFocus",
			"maxRetained",
			"onReachEnd",
		},
		cellWidth = 460,
		cellHeight = 260,
		alias = "(Facet) table",
		purpose = "Columns with sorting, resizing, selection, reorder, row actions, priority collapse and virtualization.",
		alternatives = "VirtualList for a single column.",
		scenarios = { "table_virtualized", "row_actions", "collections" },
		snippet = 'UI.Table { from = rows, key = "id", columns = { { id = "name", label = "Track", value = … } } }',
		base = function(c: Context)
			return {
				from = c.cell("rows", ROWS),
				key = "id",
				columns = columnList {
					{
						id = "name",
						label = "Track",
						value = function(r)
							return r.name
						end,
					},
					{
						id = "laps",
						label = "Laps",
						width = 72,
						priority = 2,
						value = function(r)
							return r.laps
						end,
					},
				},
				Size = UDim2.fromScale(1, 1),
			}
		end,
		axes = { { key = "selectionMode", values = { "none", "single", "multiple" }, matrix = false } },
		states = {
			{ name = "copy rows by dragging into this collection", props = transferState },
			{
				name = "custom cell render",
				props = function(c: Context)
					return {
						columns = columnList {
							{
								id = "name",
								label = "Track",
								render = function(current): GuiObject
									return c.UI.Text({
										text = function(use: Use)
											return `▸ {use(current).name}`
										end,
									})
								end,
							},
							{
								id = "laps",
								label = "Laps",
								width = 72,
								value = function(r)
									return r.laps
								end,
							},
						},
					}
				end,
			},
			{ name = "tall rows, header 56, gap 4", props = properties { itemSize = 56, headerHeight = 56, gap = 4 } },
			{
				name = "sorted (controlled)",
				props = function(c: Context)
					local sort = c.cell("sort", { column = "laps", direction = "descending" })
					return {
						sort = sort,
						onSortChange = function(s)
							sort:set(s)
							c.log("onSortChange")(s.column, s.direction)
						end,
					}
				end,
			},
			{
				name = "widths (controlled)",
				props = function(c: Context)
					local widths = c.cell("widths", { name = 220, laps = 90 })
					return {
						widths = widths,
						onWidthsChange = function(w)
							widths:set(w)
							c.log("onWidthsChange")()
						end,
						columns = columnList {
							{
								id = "name",
								label = "Track",
								minWidth = 120,
								maxWidth = 320,
								value = function(r)
									return r.name
								end,
							},
							{
								id = "laps",
								label = "Laps",
								resizable = false,
								sortable = false,
								value = function(r)
									return r.laps
								end,
							},
						},
					}
				end,
			},
			{ name = "page scrolls (all rows)", props = properties { scrolls = false, Size = UDim2.fromScale(1, 0) } },
			{ name = "alternating rows", props = properties { alternatingRows = true } },
			{
				name = "reorderable (drag label)",
				props = function(c: Context)
					local rows = c.cell("rows", ROWS)
					return {
						reorderable = true,
						movable = function(r)
							return r.id ~= "1"
						end,
						onReorder = reorderRows(c, rows),
						dragLabel = function(r)
							return r.name
						end,
						from = rows,
					}
				end,
			},
			{
				name = "reorder + delete (drag, Delete key; Edit on touch/pad)",
				props = function(c: Context)
					local rows = c.cell("editRows", ROWS)
					return {
						from = rows,
						selectionMode = "multiple",
						reorderable = true,
						onReorder = reorderRows(c, rows),
						deletable = true,
						rowDeletable = function(r)
							return r.id ~= "1"
						end,
						onDelete = function(keys)
							local gone, kept = {}, {}
							for _, key in keys do
								gone[key] = true
							end
							for _, r in rows:peek() do
								if not gone[r.id] then
									table.insert(kept, r)
								end
							end
							rows:set(kept)
							c.log("onDelete")()
						end,
					}
				end,
			},
			{
				name = "activation + edit mode",
				props = function(c: Context)
					return {
						selectionMode = "single",
						onActivate = c.log("onActivate"),
						editing = c.cell("tableEditing", true),
					}
				end,
			},
			{
				name = "row actions",
				props = function(c: Context)
					return {
						rowActions = function()
							return {
								trailing = {
									{
										id = "delete",
										label = "Delete",
										icon = "trash",
										role = "destructive",
										onActivate = c.log("delete"),
									},
								},
							}
						end,
					}
				end,
			},
			{
				name = "selection (controlled), row 3 unselectable, row 4 disabled",
				props = function(c: Context)
					local selection = c.cell("selected", { ["2"] = true })
					return {
						selectionMode = "multiple",
						selection = selection,
						onSelectionChange = function(s)
							selection:set(s)
							c.log("onSelectionChange")()
						end,
						selectable = function(r)
							return r.id ~= "3"
						end,
						disabled = function(r)
							return r.id == "4"
						end,
					}
				end,
			},
			{ name = "no header", props = properties { header = false } },
			{ name = "windowed, overscan 1", props = properties { mode = "windowed", overscan = 1 } },
			{ name = "measured rows", props = properties { measure = true } },
			{ name = "snap to rows", props = properties { snap = "item" } },
			{ name = "follows the end", props = properties { follow = "end", followThreshold = 24 } },
			{
				name = "status + controls + focus",
				props = function(c: Context)
					return { status = emptyStatus(c), controls = {}, focus = {} }
				end,
			},
			{ name = "measured map", props = properties { measured = { ["1"] = 72 } } },
			{ name = "reduced motion", props = properties { reducedMotion = true } },

			{
				name = "editable cells",
				props = function(c: Context)
					local rows = c.cell("editRows", {
						{ id = "1", name = "Coastal Circuit", laps = 3, night = false, surface = "road" },
						{ id = "2", name = "Canyon Run", laps = 5, night = true, surface = "dirt" },
						{ id = "3", name = "City Loop", laps = 4, night = false, surface = "road" },
					})
					return {
						from = rows,
						columns = columnList {
							{ id = "name", label = "Track", editor = "text", editLabel = "Rename track" },
							{ id = "laps", label = "Laps", width = 96, editor = "number", min = 1, max = 9, step = 1 },
							{
								id = "night",
								label = "Night",
								width = 64,
								editor = "toggle",
								editable = function(item)
									return item.id ~= "2"
								end,
							},
							{
								id = "surface",
								label = "Surface",
								width = 110,
								editor = "menu",
								options = {
									{ value = "road", label = "Road" },
									{ value = "dirt", label = "Dirt" },
								},
							},
						},
						onCellChange = function(key, column, value)
							local nextRows = {}
							for _, row in rows:peek() do
								if row.id == key then
									row = table.clone(row)
									row[column] = value
								end
								table.insert(nextRows, row)
							end
							rows:set(nextRows)
							c.log("onCellChange")(key, column, value)
						end,
					}
				end,
			},
			{
				name = "empty",
				props = function(c: Context)
					return { from = c.cell("none", {}) }
				end,
			},
		},
	},
	VirtualList = {
		family = "collections",
		demonstrates = VIRTUAL_DEMOS,
		cellWidth = 280,
		cellHeight = 220,
		alias = "List",
		purpose = "Windowed rows for large data; selection, reorder, row focus and native scroll.",
		alternatives = "A plain VStack for a few rows.",
		scenarios = { "collection_demo", "card_rail", "collections" },
		snippet = 'UI.VirtualList { from = rows, key = "id", render = function(current) … end }',
		base = function(c: Context)
			return {
				from = c.cell("rows", ROWS),
				key = "id",
				itemSize = 44,
				Size = UDim2.fromScale(1, 1),
				onActivate = function(r)
					c.log("onActivate")(r.name)
				end,
				render = function(current): GuiObject
					return c.UI.Text({
						text = function(use: Use)
							return use(current).name
						end,
						Size = UDim2.new(1, 0, 0, 44),
					})
				end,
			}
		end,
		axes = {
			{ key = "selectionMode", values = { "none", "single", "multiple" }, matrix = false },
			{ key = "snap", values = { "none", "item" }, matrix = false },
			{ key = "mode", values = { "windowed", "all" }, matrix = false },
		},
		states = {
			{ name = "content clipped", props = properties { contentOverflow = "clip" } },
			{ name = "content visible", props = properties { contentOverflow = "visible" } },
			{ name = "copy rows by dragging into this collection", props = transferState },
			{ name = "no reorder autoscroll", props = properties { reorderable = true, autoscroll = false } },
			{ name = "focus stays on the index", props = properties { focusPolicy = "index" } },
			{
				name = "cards rail",
				props = properties {
					direction = "horizontal",
					itemSize = "cards",
					cards = { perView = 2, peek = 24 },
				},
				across = false,
			},
			{ name = "horizontal", props = properties { direction = "horizontal", itemSize = 120 } },
			{ name = "measured rows", props = properties { measure = true } },
			{ name = "gap 8, overscan 3", props = properties { gap = 8, overscan = 3 } },
			{ name = "follows the end", props = properties { follow = "end", followThreshold = 24 } },
			{
				name = "recycled rows",
				props = function(c: Context)
					return {
						render = NONE,
						recycle = function(current): GuiObject
							return c.UI.Text({
								text = function(use: Use)
									return use(current).name
								end,
								Size = UDim2.fromScale(1, 1),
							})
						end,
					}
				end,
			},
			{
				name = "selection reported",
				props = function(c: Context)
					local selection = c.cell("selection", {})
					return {
						selection = selection,
						onSelectionChange = function(s)
							selection:set(s)
							c.log("onSelectionChange")()
						end,
					}
				end,
			},
			{
				name = "reorder (row 1 fixed)",
				props = function(c: Context)
					local rows = c.cell("rows", ROWS)
					return {
						from = rows,
						reorderable = true,
						onReorder = reorderRows(c, rows),
						movable = function(r)
							return r.id ~= "1"
						end,
						dragLabel = function(r)
							return r.name
						end,
					}
				end,
			},
			{
				name = "reorder + delete (caller Edit)",
				props = function(c: Context)
					local rows = c.cell("listEditRows", ROWS)
					return {
						from = rows,
						selectionMode = "multiple",
						reorderable = true,
						onReorder = reorderRows(c, rows),
						deletable = true,
						editing = c.cell("listEditing", false),
						onDelete = function(keys)
							local gone, kept = {}, {}
							for _, key in keys do
								gone[key] = true
							end
							for _, r in rows:peek() do
								if not gone[r.id] then
									table.insert(kept, r)
								end
							end
							rows:set(kept)
							c.log("onDelete")()
						end,
					}
				end,
			},
			{
				name = "row focus + wrap",
				props = function(c: Context)
					return { focus = {}, initialFocus = "2", autoFocus = false, wrapFocus = true }
				end,
			},
			{
				name = "row 3 unselectable, row 4 disabled",
				props = properties {
					selectionMode = "single",
					selectable = function(r)
						return r.id ~= "3"
					end,
					disabled = function(r)
						return r.id == "4"
					end,
				},
			},
			{
				name = "reach end reported",
				props = function(c: Context)
					return { onReachEnd = c.log("onReachEnd") }
				end,
			},
			{
				name = "status + controls",
				props = function(c: Context)
					return { status = emptyStatus(c), controls = {}, maxRetained = 8 }
				end,
			},
			{ name = "measured map", props = properties { measured = { ["1"] = 72 } } },
			{ name = "reduced motion", props = properties { reducedMotion = true } },
			{ name = "cross gap 4", props = properties { crossGap = 4 } },
		},
	},
	VirtualGrid = {
		family = "collections",
		demonstrates = VIRTUAL_DEMOS,
		cellWidth = 460,
		cellHeight = 220,
		alias = "Grid (virtualized)",
		purpose = "Windowed grid of cells for large collections.",
		alternatives = "UI.Grid for a few cells.",
		scenarios = { "virtual_grid", "virtual_hgrid", "cards" },
		snippet = 'UI.VirtualGrid { from = games, key = "id", columns = 3, itemSize = 208, render = … }',
		base = function(c: Context)
			return {
				from = c.cell("rows", ROWS),
				key = "id",
				columns = 3,
				itemSize = 64,
				gap = 8,
				Size = UDim2.fromScale(1, 1),
				onActivate = function(r)
					c.log("onActivate")(r.name)
				end,
				render = function(current): GuiObject
					return c.UI.Button({
						label = function(use: Use)
							return use(current).name
						end,
						Size = UDim2.fromScale(1, 1),
					})
				end,
			}
		end,
		axes = {
			{ key = "columns", values = { 3, 2, 1 } },
			{ key = "snap", values = { "none", "item" }, matrix = false },
		},
		states = {
			{
				name = "recycled cells",
				props = function(c: Context)
					return {
						render = NONE,
						recycle = function(current): GuiObject
							return c.UI.Text({
								text = function(use: Use)
									return use(current).name
								end,
								Size = UDim2.fromScale(1, 1),
							})
						end,
					}
				end,
			},
			{ name = "content clipped", props = properties { contentOverflow = "clip" } },
			{ name = "content visible", props = properties { contentOverflow = "visible" } },
			{ name = "copy rows by dragging into this collection", props = transferState },
			{
				name = "horizontal",
				props = properties { direction = "horizontal", columns = 2, itemSize = 140 },
				across = false,
			},
			{ name = "cross gap 16", props = properties { crossGap = 16 } },
			{ name = "hug", props = require("./hug_state")(ROWS, NONE) },
			{ name = "selected cards", props = require("./card_selection_state")(ART) },
			{
				name = "minColumns 2",
				props = properties { columns = NONE, minColumnWidth = 260, minColumns = 2 },
				across = false,
			},
		},
	},
	RowActions = {
		family = "collections",
		demonstrates = { "swipeEnabled", "coordinator" },
		cellWidth = 320,
		cellHeight = 150,
		alias = "(Facet-only) swipe actions",
		purpose = "Leading/trailing swipe actions on a row, reachable by pointer, touch, keyboard and gamepad.",
		alternatives = "A trailing More Menu button when there is one secondary action.",
		scenarios = { "row_actions" },
		snippet = 'UI.RowActions { content = row, trailing = { { id = "delete", label = "Delete", role = "destructive", onActivate = del } } }',
		base = function(c: Context)
			return {
				content = function(): Instance
					return c.UI.Button({
						label = "Swipe or focus this row",
						appearance = "utility",
						Size = UDim2.fromScale(1, 1),
					})
				end,
				leading = { { id = "flag", label = "Flag", icon = "flag", onActivate = c.log("flag") } },
				trailing = {
					{
						id = "delete",
						label = "Delete",
						icon = "trash",
						role = "destructive",
						onActivate = c.log("delete"),
					},
				},

				Size = UDim2.new(1, 0, 0, 52),
			}
		end,
		axes = {},
		states = {
			{
				name = "bottom item actions",
				props = function(c: Context)
					local value = c.cell("cardName", "Environments")
					return {
						actionPlacement = "bottom",
						Size = UDim2.new(1, 0, 0, 120),
						content = function(): Instance
							return c.UI.CellEditor {
								editor = "text",
								label = "File name",
								value = value,
								onChange = function(v)
									if type(v) == "string" then
										value:set(v)
									end
								end,
								Size = UDim2.fromScale(1, 1),
							}
						end,
					}
				end,
			},
			{
				name = "editing",
				props = function(c: Context)
					return { editing = c.cell("editing", true) }
				end,
			},
			{ name = "no full swipe", props = properties { fullSwipe = false } },
			{
				name = "full swipe trailing only",
				props = properties { fullSwipe = { leading = false, trailing = true } },
			},
			{ name = "action width 120", props = properties { actionWidth = 120 } },
			{
				name = "open (controlled)",
				props = function(c: Context)
					local open = c.cell("open", "trailing")
					return {
						open = open,
						onOpenChange = function(edge)
							open:set(edge)
							c.log("onOpenChange")(edge)
						end,
					}
				end,
			},
			{
				name = "shared coordinator",
				props = function(c: Context)
					return { coordinator = c.cell("coordinator", nil) }
				end,
			},
			DISABLED,
			{ name = "reduced motion", props = properties { reducedMotion = true } },
		},
	},

	ScrollView = {
		family = "layout",
		alias = "ScrollView",
		purpose = "Native scrolling on one or both axes, with gap, padding, align and distribute.",
		alternatives = "VirtualList for large data.",
		scenarios = { "containers" },
		snippet = 'UI.ScrollView { axis = "y", gap = "s", … }',
		base = function(c: Context)
			local rows = {}
			for i = 1, 12 do
				table.insert(rows, c.UI.Button({ label = `Row {i}`, appearance = "utility" }))
			end
			rows.width = 240
			rows.height = 180
			rows.gap = "xs"
			return rows
		end,
		axes = {
			{ key = "axis", values = { "y", "x", "xy" } },
			{ key = "align", values = { "start", "center", "end" } },
		},
		states = {
			{ name = "padding m", props = properties { padding = "m" } },
			{ name = "spread (distribute)", props = properties { distribute = "spaceBetween" } },
		},
	},
	focusRing = {
		host = "TabView",
		family = "navigation",
		alias = "Focus ring",
		purpose = "One theme focus ring replaces the engine selection glow after keyboard or gamepad input. Press Tab here.",
		snippet = "UI.focusRing(playerGui)",
		base = function()
			return {}
		end,
		make = function(UI: FacetControls): Instance
			return UI.HStack({
				gap = "s",
				UI.Button({ label = "First" }),
				UI.Button({ label = "Second" }),
				UI.Button({ label = "Third" }),
			})
		end,
	},
	focusSection = {
		host = "TabView",
		family = "navigation",
		alias = "Focus section",
		purpose = "Selection that enters the sidebar from the detail returns to the row last selected there (TV Left, arrow keys).",
		snippet = "UI.focusSection(sidebar)",
		base = function()
			return {}
		end,
		axes = { { key = "entry", values = { "restore", "first", "nearest" } } },
		states = {
			{ name = "preferred Row 3", props = properties { preferred = "Row 3" } },
			{
				name = "takes the selection on appear, gives it back",
				props = properties { focusOnAppear = true, returnFocus = true },
			},
		},
		make = function(UI: FacetControls, p: Properties): Instance
			local rows: Properties = { Name = "Sidebar", gap = "xs", width = 140, align = "stretch" }
			for index = 1, 4 do
				table.insert(
					rows,
					UI.Button({ Name = `Row {index}`, label = `Row {index}`, Size = UDim2.new(1, 0, 0, 0) })
				)
			end
			local sidebar = UI.VStack(rows)
			UI.focusSection(sidebar, {
				entry = p.entry,
				preferred = p.preferred,
				focusOnAppear = p.focusOnAppear,
				returnFocus = p.returnFocus,
			})
			return UI.HStack({
				gap = "m",
				sidebar,
				UI.VStack "Detail" {
					gap = "xs",
					UI.Button({ label = "Detail one" }),
					UI.Button({ label = "Detail two" }),
				},
			})
		end,
	},
	Toast = {
		family = "overlays",
		matrix = false,
		alias = "Toast · Snackbar",
		purpose = "A transient message. Without an action it is display-only and stacks per edge; with one it docks "
			.. "bottom one at a time, is pad-reachable, pauses on hover and may be bound to isPresented.",
		alternatives = "Notice for persistent status.",
		scenarios = { "notice", "sponsor_toast" },
		snippet = 'UI.Toast { Name = "Saved", message = "Kart sold", action = { label = "Undo", onActivate = undo } }',
		demonstrates = {
			"message",
			"content",
			"icon",
			"action",
			"closeButton",
			"isPresented",
			"onPresentedChange",
			"key",
			"priority",
			"duration",
			"readFloor",
			"position",
			"width",
			"fade",
			"onDismiss",
		},
		base = function()
			return {}
		end,
		make = function(UI: FacetControls, _: Properties, c: Context): Instance
			local shown = c.Compose.cell({} :: { { n: number, spec: Properties } })
			local count = 0
			local function add(spec: Properties)
				count += 1
				spec.onDismiss = c.log("onDismiss")
				local list = table.clone(shown:peek())
				table.insert(list, { n = count, spec = spec })
				shown:set(list)
			end
			return UI.VStack(stacked({
				gap = "xs",
				UI.Button({
					label = "Toast (top, 3 s)",
					onActivate = function()
						add({ message = `Saved ({count + 1})`, duration = 3, readFloor = 1 })
					end,
				}),
				UI.Button({
					label = "Priority toast (bottom, hug, fade)",
					onActivate = function()
						add({
							message = "Level up",
							priority = 2,
							position = "bottom",
							width = "hug",
							fade = true,
						})
					end,
				}),
				UI.Button({
					label = "Toast with an action (Undo)",
					onActivate = function()
						add({
							message = `Kart sold ({count + 1})`,
							icon = "checkmark",
							duration = 6,
							action = { label = "Undo", onActivate = c.log("undo") },
						})
					end,
				}),
				UI.Button({
					label = "Bound action toast (caller decides)",
					onActivate = function()
						local shown = c.Compose.cell(true)
						add({
							message = "Offline: times upload when you reconnect",
							isPresented = shown,
							onPresentedChange = function(v)
								c.log("onPresentedChange")(v)
								shown:set(v)
							end,
							action = { label = "Retry", onActivate = c.log("retry") },
						})
					end,
				}),
				UI.Button({
					label = "Keyed toast (replaces)",
					onActivate = function()
						add({
							key = "sync",
							content = function(): Instance
								return UI.Text({ text = `Syncing… ({count + 1})` })
							end,
						})
					end,
				}),
				c.Compose.keyed({
					from = shown,
					key = function(entry)
						return entry.n
					end,
					render = function(entry: Readable<{ n: number, spec: Properties }>): GuiObject
						return UI.Toast(entry:peek().spec)
					end,
				}),
			}))
		end,
	},
	draggable = {
		host = "Button",
		family = "collections",
		alias = "Drag source",
		purpose = "Makes any node a drag source: pointer travel, the touch long press, or A / Return on a selected source.",
		alternatives = "Table and list reorder for rows.",
		snippet = 'UI.draggable(card, { payload = "card" })',
		demonstrates = {
			"payload",
			"enabled",
			"armOnTap",
			"touchPickup",
			"touchDragAxis",
			"hitArea",
			"returnTravel",
			"operations",
			"valid",
			"onStart",
			"onEnd",
		},
		axes = {
			{ key = "transferScale", values = { 1, 0.75, 1.25 } },
			{ key = "rejectTransfer", values = { false, true } },
			{ key = "transferScrolled", values = { false, true } },
			{ key = "reserveSlots", values = { false, true } },
		},
		states = {
			{ name = "without status labels", props = properties { statusLabels = false } },
			{ name = "horizontal touch pickup", props = properties { touchPickup = "immediate", touchDragAxis = "X" } },
		},
		base = function()
			return { touchPickup = "longPress", touchDragAxis = "XY" }
		end,
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			return require("./container_transfer_demo")(UI, c.Host, c.Compose, c.types, {
				scale = p.transferScale,
				reject = p.rejectTransfer,
				scrolled = p.transferScrolled,
				touchPickup = p.touchPickup,
				touchDragAxis = p.touchDragAxis,
				statusLabels = p.statusLabels,
				reserveSlots = p.reserveSlots,
			})
		end,
	},
	commandScope = {
		host = "Frame",
		family = "actions",
		alias = "Board typing scope",
		purpose = "Type one matching rack letter at a focused board cell. Text entry owns keys while chat edits.",
		alternatives = "Button shortcuts for one action; collection focus for a list.",
		demonstrates = { "targets", "commands", "enabled" },
		snippet = "local scope = UI.commandScope(board, { targets = targets, commands = commands })",
		axes = { { key = "typingEnabled", values = { true, false } } },
		states = {
			{ name = "two matching A tiles", props = properties {} },
			{ name = "chat takes keys", props = properties {} },
			{ name = "commands disabled", props = properties { typingEnabled = false } },
		},
		base = function()
			return { typingEnabled = true }
		end,
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			return require("./container_transfer_demo")(UI, c.Host, c.Compose, c.types, {
				commandTyping = true,
				typingEnabled = p.typingEnabled,
				duplicateLetters = true,
				reserveSlots = true,
				touchPickup = "immediate",
			})
		end,
	},
	dropTarget = {
		host = "Button",
		family = "collections",
		alias = "Drop target",
		purpose = "Accepts a dragged payload; accepts() gives the legality and a reason, onReject reports a refusal.",
		alternatives = "Table and list reorder for rows.",
		snippet = "UI.dropTarget(slot, { onDrop = place, accepts = legal })",
		demonstrates = {
			"onDrop",
			"travel",
			"landing",
			"accepts",
			"onReject",
			"onEnter",
			"onLeave",
			"focusTarget",
			"label",
			"onUpdate",
			"operation",
			"passThrough",
		},
		base = function()
			return {}
		end,
		make = function(UI: FacetControls, _: Properties, c: Context): Instance
			local card = UI.Button({ label = "Card" })
			local open = UI.Button({ label = "Open slot" })
			local full = UI.Button({ label = "Full slot" })
			UI.draggable(card, { payload = "card" })
			UI.dropTarget(open, {
				travel = true,
				landing = function()
					return {
						x = open.AbsolutePosition.X,
						y = open.AbsolutePosition.Y,
						w = open.AbsoluteSize.X,
						h = open.AbsoluteSize.Y,
					}
				end,
				label = "Open slot",
				focusTarget = open,
				operation = "move",
				passThrough = function(payload)
					return payload == "decoration"
				end,
				onUpdate = c.log("onUpdate"),
				onDrop = c.log("onDrop"),
				onEnter = c.log("onEnter"),
				onLeave = c.log("onLeave"),
			})
			UI.dropTarget(full, {
				accepts = function()
					return false, "FULL"
				end,
				onDrop = c.log("onDrop"),
				onReject = c.log("onReject"),
			})
			return UI.HStack({ gap = "l", card, open, full })
		end,
	},
	adjustable = {
		host = "HStack",
		family = "inputs",
		alias = "Adjustable game control",
		purpose = "A game control takes the Slider's keyboard and gamepad adjustment: shoulders, Comma/Period and its arrow axis.",
		snippet = 'UI.adjustable(row, { onAdjust = turn, axis = "none", repeats = true })',
		demonstrates = { "onAdjust", "canAdjust", "enabled", "disabled", "busy" },
		base = function()
			return {}
		end,
		axes = { { key = "axis", values = { "horizontal", "vertical", "none" } } },
		states = { { name = "repeats when held", props = properties { repeats = true } } },
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local angle = 0
			local readout = UI.Text({ text = "0°" }) :: TextLabel
			local row = UI.HStack(stacked({
				gap = "xs",
				UI.Button({ label = "Dial" }),
				readout,
			}))
			UI.adjustable(row, {
				axis = p.axis,
				repeats = p.repeats,
				onAdjust = function(direction)
					angle += direction * 15
					readout.Text = `{angle}°`
					c.log("onAdjust")(direction)
				end,
			})
			return row
		end,
	},
	feedback = {
		host = "VStack",
		family = "inputs",
		alias = "Haptic feedback",
		purpose = "Plays a named feedback kind on the engine HapticEffect: selection, impact, success, warning or error.",
		snippet = 'UI.feedback("success")',
		base = function()
			return {}
		end,
		axes = { { key = "kind", values = { "selection", "impact", "success", "warning", "error" } } },
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local kind = p.kind or "success"
			return UI.VStack({
				gap = "xs",
				UI.Button({
					label = `Play {kind}`,
					onActivate = function()
						UI.feedback(kind)
						c.log("feedback")(kind)
					end,
				}),
				UI.Button({ label = `Press plays {kind}`, haptic = kind }),
			})
		end,
	},
	responder = {
		host = "VStack",
		family = "navigation",
		alias = "First responder",
		purpose = "A passive surface leaves Tab and Space to the game until the player selects or taps into it.",
		snippet = "UI.responder(hud, { gameplayGuard = true })",
		demonstrates = { "passive", "gameplayGuard", "traversalWrap" },
		base = function()
			return {}
		end,
		make = function(UI: FacetControls, _: Properties, c: Context): Instance
			local hud = UI.VStack({
				gap = "xs",
				UI.Button({ label = "Map" }),
				UI.Button({ label = "Bag" }),
			})
			local responder = UI.responder(hud, { passive = true, gameplayGuard = true, traversalWrap = false })
			return UI.VStack(stacked({
				gap = "xs",
				UI.Button({
					label = "Engage",
					onActivate = function()
						responder.engage()
						c.log("engaged")(true)
					end,
				}),
				hud,
			}))
		end,
	},
	scrollTo = {
		host = "ScrollView",
		family = "layout",
		alias = "Scroll to top / bottom",
		purpose = "Moves a ScrollingFrame to a position (animated unless reduced motion).",
		alternatives = "scrollToVisible to reveal a node.",
		snippet = 'UI.scrollTo(frame, "bottom")',
		base = function()
			return {}
		end,
		axes = { { key = "position", values = { "top", "bottom" } } },
		states = { { name = "instant", props = properties { animated = false } } },
		make = function(UI: FacetControls, p: Properties): Instance
			local list: Properties = { Name = "List", width = 220, height = 140, gap = "xs" }
			for i = 1, 20 do
				table.insert(list, UI.Text({ text = `Line {i}` }))
			end
			local view = UI.ScrollView(list)
			return UI.VStack(stacked({
				gap = "xs",
				UI.Button({
					label = `Scroll to {p.position or "top"}`,
					onActivate = function()
						UI.scrollTo(view, p.position or "top", { animated = p.animated })
					end,
				}),
				view,
			}))
		end,
	},
	scrollToVisible = {
		host = "ScrollView",
		family = "layout",
		alias = "Scroll into view",
		purpose = "Brings a node (or a rect of it) into view through every scrolling ancestor.",
		alternatives = "scrollTo for a fixed position.",
		snippet = "UI.scrollToVisible(node)",
		base = function()
			return {}
		end,
		axes = { { key = "target", values = { 5, 15, 20 } } },
		states = { { name = "instant", props = properties { animated = false } } },
		make = function(UI: FacetControls, p: Properties): Instance
			local target
			local list: Properties = { width = 220, height = 140, gap = "xs" }
			for i = 1, 20 do
				local line = UI.Text({ text = `Line {i}` })
				if i == (p.target or 5) then
					target = line
				end
				table.insert(list, line)
			end
			return UI.VStack(stacked({
				gap = "xs",
				UI.Button({
					label = `Reveal line {p.target or 5}`,
					onActivate = function()
						UI.scrollToVisible(target, nil, { animated = p.animated })
					end,
				}),
				UI.ScrollView(list),
			}))
		end,
	},
	Text = {
		family = "layout",
		alias = "Text",
		purpose = "Text with type roles, secondary role, wrap, truncation (end or middle), fit, rich text, direction and tint.",
		alternatives = "Label for icon + title.",
		scenarios = { "text_degrade", "text_controls" },
		snippet = 'UI.Text { text = "Hello", textRole = "body" }',
		base = function()
			return { text = "The quick brown fox" }
		end,
		axes = {
			{
				key = "textRole",
				values = { "caption", "label", "body", "control", "strong", "numeral", "heading", "title" },
			},
			{ key = "role", values = { "content", "secondary" } },
		},
		states = {
			{
				name = "reveal auto (marquee)",
				props = properties { text = LONG, reveal = "auto", Size = UDim2.fromOffset(200, 24) },
			},
			{
				name = "discloses a truncated value",
				props = properties { text = LONG, disclose = true, Size = UDim2.fromOffset(200, 24) },
			},
			{ name = "accent tint", props = properties { tint = Color3.fromRGB(60, 94, 246) } },
			{
				name = "centred",
				props = properties {
					textAlign = "center",
					Size = UDim2.fromOffset(220, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
				},
			},
			{
				name = "wraps",
				props = properties {
					text = LONG,
					wrap = true,
					Size = UDim2.fromOffset(220, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
				},
			},
			{
				name = "truncate end",
				props = properties {
					text = LONG,
					truncate = "end",
					Size = UDim2.fromOffset(220, 24),
					AutomaticSize = Enum.AutomaticSize.None,
				},
			},
			{ name = "rich", props = properties { rich = true, text = "Plain, <b>bold</b> and <i>italic</i>" } },
			{
				name = "at most 2 lines",
				props = properties { text = LONG .. ". " .. LONG, lines = 2, Size = UDim2.fromOffset(220, 0) },
			},
			{
				name = "truncate middle",
				props = properties {
					text = "Coastal circuit — practice lap 14",
					truncate = "middle",
					Size = UDim2.fromOffset(160, 0),
				},
			},
			{ name = "size 22 px", props = properties { textSize = 22, textRole = NONE } },
			{
				name = "fit to box",
				props = properties {
					textSize = { fit = { cap = "title", floor = "caption" } },
					Size = UDim2.fromOffset(160, 40),
				},
				across = false,
			},
			{ name = "right to left", props = properties { text = "مرحبا بالعالم", direction = "rtl" } },
		},
		valid = function(p: Properties)
			return not (p.textSize ~= nil and type(p.textSize) == "string" and p.textRole ~= nil)
		end,
	},
	Divider = {
		family = "layout",
		alias = "Divider",
		purpose = "A hairline between content groups; turns with its stack.",
		alternatives = "Spacing alone when the grouping is already clear.",
		scenarios = { "containers" },
		snippet = "UI.Divider {}",
		base = function()
			return {}
		end,
		axes = {
			{ key = "appearance", values = { "standard", "strong" } },
			{ key = "thickness", values = { DEFAULT, 3, "strokes.hairline" } },
		},
		states = {
			{ name = "vertical (in an HStack)", props = properties { vertical = true }, across = false },
			{ name = "axis x forced", props = properties { axis = "x", Size = UDim2.fromOffset(1, 40) } },
		},
		make = function(UI: FacetControls, p: Properties): Instance
			local vertical = p.vertical
			p.vertical = nil
			if vertical then
				return UI.HStack({
					height = 40,
					gap = "s",
					UI.Text({ text = "Left" }),
					UI.Divider(p),
					UI.Text({ text = "Right" }),
				})
			end
			return UI.VStack({
				width = 200,
				gap = "s",
				UI.Text({ text = "Above" }),
				UI.Divider(p),
				UI.Text({ text = "Below" }),
			})
		end,
	},
	Grid = {
		family = "layout",
		alias = "Grid (Root · Cell)",
		purpose = "A UIGridLayout of equal cells: columns, gaps, row gap, cell height or aspect ratio, alignment.",
		alternatives = "VirtualGrid for large data.",
		scenarios = { "container_grid" },
		snippet = 'UI.Grid { columns = 3, gap = "s", … }',
		base = function(c: Context)
			local cells = { columns = 3, gap = "xs", Size = UDim2.fromOffset(300, 0) }
			for i = 1, 6 do
				table.insert(cells, c.UI.Button({ label = `Cell {i}`, Size = UDim2.fromScale(1, 1) }))
			end
			return cells
		end,
		axes = {
			{ key = "columns", values = { 1, 2, 3, 4 } },
			{ key = "align", values = { "start", "center", "end" } },
		},
		states = {
			{ name = "row gap l", props = properties { rowGap = "l" } },
			{ name = "cell height 64", props = properties { cellHeight = 64 } },
			{ name = "square cells", props = properties { aspectRatio = 1 } },
			{ name = "padding s", props = properties { padding = "s" } },
			{ name = "width 200, height 160 (extents)", props = properties { Size = NONE, width = 200, height = 160 } },
			{ name = "column flow", props = properties { flow = "column" } },
		},
	},
	Path = {
		family = "layout",
		alias = "Path (vector stroke) · Facet.pathShapes",
		purpose = "Strokes normalized points (a ring, an arc, a needle from Facet.pathShapes) in a theme role or tint.",
		alternatives = "ProgressView circular for a progress ring.",
		scenarios = { "progress_ring" },
		snippet = 'UI.Path { points = Facet.pathShapes.ring({ radius = 0.4 }), closed = true, thickness = 4, role = "accent" }',
		base = function(c: Context)
			return {
				points = c.Facet.pathShapes.ring({ radius = 0.4 }),
				closed = true,
				thickness = 4,
				width = 64,
				height = 64,
			}
		end,
		axes = {
			{ key = "role", values = { "accent", "secondary", "content" } },
			{ key = "thickness", values = { 2, 4, 8 } },
		},
		states = {
			{
				name = "arc 250°",
				props = function(c: Context)
					return { points = c.Facet.pathShapes.arc(0, 250, { radius = 0.4 }), closed = false }
				end,
			},
			{
				name = "needle at 45°",
				props = function(c: Context)
					return {
						points = c.Facet.pathShapes.needle(45, { innerRadius = 0.1, radius = 0.45 }),
						closed = false,
					}
				end,
			},
			{ name = "tint", props = properties { tint = Color3.fromRGB(63, 184, 113) } },
		},
	},
	HStack = {
		family = "layout",
		alias = "HStack (row)",
		purpose = "Lays children out in a row; gap, cross-axis align, main-axis distribution and wrapping.",
		alternatives = "VStack for a column; Grid for aligned columns.",
		scenarios = { "flow_wrap" },
		snippet = 'UI.HStack { gap = "s", align = "center", distribute = "spaceBetween", a, b, c }',
		base = function(c: Context)
			return stackDemo(c, { width = 300, height = 80 })
		end,
		axes = { ALIGN, DISTRIBUTE, GAP },
		states = {
			{ name = "wrap (narrow)", props = properties { wrap = true, width = 120, height = "hug" }, across = false },
			{ name = "panel surface", props = properties { surface = "panel", padding = "s" }, across = false },
			{
				name = "pill surface",
				props = properties { surface = "panel", corners = "pill", padding = "s" },
				across = false,
			},
			{
				name = "warning status",
				props = properties { surface = "panel", status = "warning", padding = "s" },
				across = false,
			},
		},
	},
	VStack = {
		family = "layout",
		alias = "VStack (column)",
		purpose = "Lays children out in a column; gap, cross-axis align, main-axis distribution and wrapping.",
		alternatives = "HStack for a row; ScrollView when the column can outgrow its box.",
		scenarios = { "containers" },
		snippet = 'UI.VStack { gap = "s", align = "start", a, b, c }',
		base = function(c: Context)
			return stackDemo(c, { width = 160, height = 240 })
		end,
		axes = { ALIGN, DISTRIBUTE, GAP },
		states = {
			{ name = "wrap (short)", props = properties { wrap = true, height = 80, width = "hug" }, across = false },
			{ name = "panel surface", props = properties { surface = "panel", padding = "s" }, across = false },
			{
				name = "pane, 6 px corners",
				props = properties { surface = "pane", corners = 6, padding = "s" },
				across = false,
			},
			{
				name = "success status",
				props = properties { surface = "panel", status = "success", padding = "s" },
				across = false,
			},
		},
	},
	ZStack = {
		family = "layout",
		alias = "ZStack (layers)",
		purpose = "Layers children in one box; each layer aligns inside it (AnchorPoint + scale Position).",
		alternatives = "A stack when the children should not overlap.",
		scenarios = { "containers" },
		snippet = 'UI.ZStack { alignH = "end", alignV = "start", plate, badge }',
		base = function(c: Context)
			return {
				width = 140,
				height = 96,
				plate(c, "facet-panel", 140, 96),
				c.UI.Badge({ label = "New", appearance = "status", status = "accent" }),
			}
		end,
		axes = {
			{ key = "alignH", values = { "start", "center", "end" } },
			{ key = "alignV", values = { "start", "center", "end" } },
		},
		states = { { name = "padding s", props = properties { padding = "s" } } },
	},
	Spacer = {
		family = "layout",
		alias = "Spacer",
		purpose = "Flexible space that takes a stack's leftover, never less than its minimum length.",
		alternatives = "distribute on the stack when every gap should grow alike; UI.fill() to grow a child.",
		scenarios = { "navigation_stack" },
		snippet = "UI.HStack { back, UI.Spacer {}, done }",
		base = function()
			return {}
		end,
		axes = {
			{ key = "minLength", values = { 0, 24, "l" } },
			{ key = "room", values = { "hug", 360 } },
		},
		states = {},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local room = p.room
			p.room = nil
			return UI.HStack(stacked({
				align = "center",
				width = (if room == 360 then 360 else "hug") :: number | "hug",
				UI.Button({ label = "Back", onActivate = c.log("back") }),
				UI.Spacer(p),
				UI.Button({ label = "Done", appearance = "emphasis" :: string, onActivate = c.log("done") }),
			}))
		end,
	},
	fill = {
		host = "HStack",
		family = "layout",
		alias = "Flex grow (UIFlexItem)",
		purpose = "Makes one child grow along its stack's main axis; a weight shares the free space.",
		alternatives = 'Spacer for empty space; width = "fill" on the cross axis.',
		snippet = 'UI.Text { text = "Name", UI.fill() }',
		base = function()
			return {}
		end,
		axes = { { key = "weight", values = { DEFAULT, 1, 3 } } },
		states = {},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			return UI.HStack({
				width = 360,
				gap = "s",
				UI.Button({ label = "Grows", UI.fill(p.weight) }),
				UI.Button({ label = "Weight 1", UI.fill(1) }),
				UI.Button({ label = "Fixed" }),
			})
		end,
	},
	Screen = {
		family = "layout",
		alias = "Screen (a mount's root)",
		purpose = "The root of a screen: it fills its parent, stacks its children vertically and pads them "
			.. "(padding m by default). The safe area is the ScreenGui's job (ScreenInsets keeps the root out "
			.. "of the top bar and notches); a long body goes in a ScrollView that takes the remaining height.",
		alternatives = "A stack for anything that is not the root.",
		snippet = 'app.mount(function() return UI.Screen { Name = "Main", UI.Text { … }, UI.ScrollView { UI.fill(), … } } end)',
		cellWidth = 380,
		cellHeight = 320,
		base = function()
			return {}
		end,
		axes = {
			{ key = "padding", values = { DEFAULT, 0, "xl" } },
			{ key = "align", values = { DEFAULT, "start", "center", "end" } },
			{ key = "distribute", values = { DEFAULT, "start", "center", "spaceBetween" } },
		},
		states = {
			{ name = "chrome band", props = properties { chrome = "band" } },
			{ name = "chrome edge", props = properties { chrome = "edge" } },
			{ name = "surface (reaches the glass at safe edges)", props = properties { surface = "surface" } },
			{ name = "gap l", props = properties { gap = "l" } },
			{ name = "fixed 300×200 (width/height)", props = properties { width = 300, height = 200 } },
		},

		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local env = UI.environment()
			local facts = c.Compose.formula(function(use: Use)
				local inset = use(env.safeInsets)
				local size = use(env.viewportSize)
				return `Environment: {math.floor(size.X)}×{math.floor(size.Y)} {use(env.sizeClass)}, input {use(
					env.effectiveInput
				)}; ` .. `safe insets top {inset.top} (the top bar) — the ScreenGui keeps the root below it`
			end)
			local plain = { wrap = true, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y }
			local rows: Properties = { width = "fill", gap = "xs", UI.fill() }
			for i = 1, 8 do
				table.insert(
					rows,
					UI.Text(merged(plain, { text = `Body row {i} — scrolls inside the remaining height` }))
				)
			end
			table.insert(p, UI.Text(merged(plain, { text = "Screen title (first child)", textRole = "heading" })))
			table.insert(p, UI.Text(merged(plain, { text = facts, textRole = "caption" })))
			if p.surface then
				table.insert(p, require("./full_bleed_demo")(c))
			end
			table.insert(p, UI.ScrollView(rows))
			table.insert(p, UI.Button({ label = "Continue (last child, stays pinned)", appearance = "emphasis" }))
			local screen = UI.Screen(p)
			screen:AddTag("facet-panel")
			return UI.VStack({
				gap = "xs",
				width = "fill",
				UI.Text(merged(plain, {
					text = "The plate is the Screen's box (it fills this cell like a ScreenGui); its padding is the gap to the plate edge.",
					textRole = "caption",
				})),
				UI.VStack({ width = "fill", height = 260, screen :: unknown }),
			})
		end,
	},
	ErrorBoundary = {
		family = "layout",
		alias = "ErrorBoundary",
		purpose = "Contains a failing view: its fallback shows in its place, with retry; the rest of the screen lives.",
		alternatives = "Validate data before it reaches the view when the failure is expected.",
		snippet = "UI.ErrorBoundary { view = risky, fallback = function(err, retry) … end }",
		base = function()
			return {}
		end,
		axes = {},
		states = { { name = "view fails", props = properties { fails = true } } },
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local fail = c.Compose.cell(p.fails == true)
			return UI.ErrorBoundary({
				view = function()
					if fail:peek() then
						error("the track list could not load", 0)
					end
					return UI.Text({ text = "Track list loaded" })
				end,
				fallback = function(err, retry)
					return UI.VStack({
						gap = "xs",
						UI.Text({ text = `Fallback: {tostring(err)}` }),
						UI.Button({
							label = "Retry (succeeds)",
							onActivate = function()
								fail:set(false)
								retry()
							end,
						}),
					})
				end,
				onError = c.log("onError"),
				width = p.width or 260,
				maxWidth = p.maxWidth,
			})
		end,
		demonstrates = { "view", "fallback", "onError", "width", "height" },
	},

	AdaptiveStack = {
		family = "layout",
		fills = true,
		alias = "AdaptiveStack (row that folds to a column)",
		purpose = "A row while its children fit its width, a column when they do not; `axis` pins one. "
			.. "The playground is the preview's width: switch Platform (phone, desktop) to watch it fold live.",
		alternatives = "ViewThatFits to swap whole layouts; HStack wrap to flow onto more lines.",
		scenarios = { "hud" },
		snippet = 'UI.AdaptiveStack { gap = "s", start, garage, leaderboard }',
		cellWidth = 460,
		base = function(c: Context)
			return {
				width = "fill",
				gap = "s",
				c.UI.Button({ label = "Start race", appearance = "emphasis" }),
				c.UI.Button({ label = "Garage" }),
				c.UI.Button({ label = "Leaderboard" }),
				c.UI.Button({ label = "Settings" }),
			}
		end,
		make = function(UI: FacetControls, p: Properties): Instance
			if p.axis ~= "x" then
				return UI.AdaptiveStack(p)
			end
			local row = table.clone(p)
			row.width = "hug"
			row.height = "hug"
			local window: Properties = {
				axis = "x",
				width = p.width or "fill",
				height = p.height or "hug",
				UI.AdaptiveStack(row),
			}
			return UI.ScrollView(window)
		end,
		axes = {
			{ key = "width", values = { "fill", 460, 240 } },
			{ key = "axis", values = { DEFAULT, "x", "y" } },
			{ key = "gap", values = { "xs", "s", "l" } },
		},
		states = {
			{ name = "padding s", props = properties { padding = "s" } },
			{ name = "align center", props = properties { align = "center" } },
			{ name = "distribute spaceBetween", props = properties { distribute = "spaceBetween" } },
			{ name = "height 160", props = properties { height = 160 } },
		},
	},
	ViewThatFits = {
		family = "layout",
		fills = true,
		alias = "ViewThatFits (first candidate that fits)",
		purpose = "Shows the first child, richest first, that fits its width (and height when fixed); the "
			.. "last is the fallback. The playground is the preview's width: switch Platform to watch it step down.",
		alternatives = "AdaptiveStack when only the axis should change; compactLabel on one Button.",
		scenarios = { "hud" },
		snippet = "UI.ViewThatFits { fullToolbar, shortToolbar, menuButton }",
		cellWidth = 380,
		base = function(c: Context)
			local UI = c.UI
			return {
				width = "fill",
				UI.HStack({
					gap = "s",
					UI.Button({ label = "Start race", appearance = "emphasis" }),
					UI.Button({ label = "Garage" }),
					UI.Button({ label = "Leaderboard" }),
					UI.Button({ label = "Settings" }),
				}),
				UI.HStack({
					gap = "s",
					UI.Button({ label = "Start", appearance = "emphasis" }),
					UI.Button({ label = "More" }),
				}),
				UI.Button({ label = "Menu" }),
			}
		end,
		axes = { { key = "width", values = { "fill", 360, 200, 110 } } },
		states = {
			{ name = "height 32 (too short for any)", props = properties { height = 32 } },
			{ name = "segmented, then menu", props = strips.fallback },
		},
	},
	Composition = {
		family = "layout",
		fills = true,
		alias = "Composition (HUD zones)",
		purpose = "A HUD with ranked regions. Narrow the plate: higher ranks give way first. "
			.. "The caption names each form; tap a short form to expand it.",
		note = "Room sets the plate width; gap and padding set spacing. Enable topbar for the real Roblox strip. "
			.. "In the captioned bottom row, captioned circles and the Race Button share one baseline. "
			.. "The leading Settings button opens a popup. Resize Studio to see strip regions land in the top zone. "
			.. "With topbar, a trailing badge keeps the padding from the screen edge.",
		alternatives = "A Screen with stacks when nothing competes for the same edge.",
		scenarios = { "hud", "radial_menu" },
		snippet = 'UI.Composition { UI.Region { zone = "topLeft", rank = 1, full, short }, … }',
		cellWidth = 380,
		cellHeight = 300,
		base = function()
			return { topbar = false, passive = false }
		end,
		axes = {
			{ key = "room", values = { "fill", 300, 200 } },
			{ key = "gap", values = { DEFAULT, "xs", "m" } },
			{ key = "padding", values = { DEFAULT, 0, "l" } },
			{ key = "rows", values = { DEFAULT, "fit" }, matrix = false },

			{ key = "topbar", values = { false, true }, matrix = false },
		},
		states = { { name = "captioned bottom row", props = properties { captions = true } } },
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local room = p.room or "fill"
			local captions = p.captions == true
			p.room, p.captions = nil, nil
			local forms, names = {}, {}
			local function region(name: string, zone, rank, mayDrop, ...)
				local form = c.cell("form" .. name, 1)
				table.insert(forms, form)
				table.insert(names, name)
				return UI.Region({
					Name = name,
					zone = zone,
					rank = rank,
					mayDrop = mayDrop,
					form = form,
					expand = if name == "Round"
						then function(): Instance
							return UI.Text({ text = "Round 3 · Capture the flag · 2:14 left" })
						end
						else nil,
					...,
				})
			end
			table.insert(
				p,
				region("Menu", "topLeft", 1, false, UI.Button({ label = "Open menu" }), UI.Button({ label = "Menu" }))
			)
			table.insert(
				p,
				region(
					"Round",
					"top",
					2,
					false,
					UI.Badge({ label = "Round 3 · Capture the flag" }),
					UI.Badge({ label = "R3" })
				)
			)
			table.insert(
				p,
				region(
					"Weapons",
					"topRight",
					3,
					true,
					UI.HStack({
						gap = "xs",
						UI.Badge({ label = "Rifle 24/90" }),
						UI.Badge({ label = "Pistol 7/21" }),
					})
				)
			)
			table.insert(p, region("Strip", "topbar", 5, true, UI.Badge({ label = "Top bar strip" })))
			for _, strip in require("./topbar_demo")(c, p.topbar == true) do
				table.insert(p, strip)
			end
			if captions then
				for _, item in require("./caption_row_demo")(UI) do
					table.insert(p, item)
				end
			else
				table.insert(
					p,
					region("Ready", "bottom", 1, false, UI.Button({ label = "Ready up", appearance = "emphasis" }))
				)
				table.insert(
					p,
					region("Fps", "bottomRight", 4, true, UI.Text({ text = "60 FPS", textRole = "caption" }))
				)
			end
			local composition = UI.Composition(p)
			local plate = UI.VStack({ width = room, height = "fill", composition :: unknown })
			plate:AddTag("facet-panel")
			return UI.VStack({
				width = "fill",
				height = 260,
				gap = "xs",
				UI.Text({
					text = function(use: Use)
						local parts = {}
						for i, form in forms do
							local shown = use(form)
							table.insert(
								parts,
								`{names[i]}: {if shown == 0 then "hidden" elseif shown == 1 then "full" else "short"}`
							)
						end
						return "Showing now — " .. table.concat(parts, " · ")
					end,
					textRole = "caption",
					wrap = true,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
				}),
				plate,
			})
		end,
	},
	Region = {
		family = "layout",
		fills = true,
		alias = "Region (a Composition zone member)",
		purpose = "A full and short form compete with a rank 1 neighbour. Narrow the plate to change forms; "
			.. "tap a short form to expand it. Choose topbar to compare strip placements.",
		note = "Higher ranks give way first. Form is 1 for full, 2 for short, 0 for hidden. "
			.. 'A hidden mayDrop region has a "…" reveal button unless reveal is false.',
		alternatives = "A plain child of a Screen when it never competes for room.",
		scenarios = { "hud" },
		snippet = 'UI.Region { zone = "topRight", rank = 2, mayDrop = true, form = formCell, full, short }',
		cellWidth = 380,
		cellHeight = 220,
		base = function()
			return { zone = "top", rank = 2 }
		end,
		axes = {
			{
				key = "zone",
				values = {
					"topLeft",
					"top",
					"topRight",
					"left",
					"center",
					"right",
					"bottomLeft",
					"bottom",
					"bottomRight",
					"topbar",
					"action",
				},
			},
			{ key = "rank", values = { 1, 2, 3 } },
			{ key = "room", values = { "fill", 200 } },
		},
		states = {
			{ name = "mayDrop", props = properties { mayDrop = true } },
			{ name = "noReveal", props = properties { mayDrop = true, reveal = false } },
			{ name = "leading top bar", props = properties { zone = "topbar", leading = true } },
			{ name = "trailing", props = properties { zone = "topbar", trailing = true } },
		},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local form = c.cell("form", 1)
			local room = p.room or "fill"
			local composition = UI.Composition({
				topbar = p.zone == "topbar",
				UI.Region "Neighbour" {
					zone = "top",
					rank = 1,
					UI.Badge({ label = "Neighbour · rank 1 · top" }),
				},
				UI.Region "UnderTest" {
					zone = p.zone,
					rank = p.rank,
					leading = if p.zone == "topbar" then p.leading else nil,
					trailing = if p.zone == "topbar" then p.trailing else nil,
					mayDrop = p.mayDrop,
					reveal = p.reveal,
					form = form,
					expand = function(): Instance
						return UI.Text({ text = "Region under test — the full form, disclosed in place" })
					end,
					UI.Badge({ label = "Region under test (full form)" }),
					UI.Badge({ label = "Short form" }),
				},
			})
			local plate = UI.VStack({ width = room, height = "fill", composition :: unknown })
			plate:AddTag("facet-panel")
			return UI.VStack({
				width = "fill",
				height = 200,
				gap = "xs",
				UI.Text({
					text = function(use: Use)
						local shown = use(form)
						return `Showing now: {if shown == 0
							then "hidden (form 0)"
							elseif shown == 1 then "full form (form 1)"
							else "short form (form 2) — tap it to expand"}`
					end,
					textRole = "caption",
					wrap = true,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
				}),
				plate,
			})
		end,
		demonstrates = { "form", "expand", "leading", "trailing" },
	},

	environment = require("./environment_page"),
	worldAnchor = {
		host = "RadialMenu",
		family = "facet",
		alias = "World anchor (RadialMenu / markers)",
		purpose = "Projects a world object to a screen anchor each Heartbeat, for a RadialMenu anchor or a marker.",
		alternatives = "A GuiObject anchor for on-screen UI.",
		scenarios = { "world_markers", "radial_menu" },
		snippet = "local binding = UI.worldAnchor({ target = crate }); binding.anchor",
		base = function()
			return {}
		end,
		axes = { { key = "offscreen", values = { "hide", "retain" } } },
		states = {
			{ name = "occlusion ray", props = properties { occlusion = true } },
			{ name = "padding 0.5", props = properties { padding = 0.5 } },
		},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local part: Part? = workspace:FindFirstChild("LabAnchorPart") :: Part?
			if part == nil then
				part = Instance.new("Part")
				assert(part).Name = "LabAnchorPart"
				assert(part).Anchored = true
				assert(part).Size = Vector3.new(4, 4, 4)
				assert(part).Position = Vector3.new(0, 4, -20)
				assert(part).Parent = workspace
			end
			local binding = UI.worldAnchor({
				target = assert(part) :: BasePart,
				offscreen = p.offscreen,
				occlusion = p.occlusion,
				padding = p.padding,
				camera = workspace.CurrentCamera,
			})
			c.Compose.cleanup(binding.dispose)
			return UI.Text({
				text = function(use: Use)
					local a = use(binding.anchor)
					return `x {math.floor(a.x or 0)} y {math.floor(a.y or 0)} clearance {math.floor(a.clearance or 0)} visible {tostring(
						a.visible
					)} onscreen {tostring(a.onscreen)}`
				end,
			})
		end,
		demonstrates = { "target", "offscreen", "occlusion", "padding", "camera" },
		surface = "UI.worldAnchor",
	},
	Compose = {
		facet = true,
		family = "facet",
		alias = "Structure (show · switch · keyed · presence)",
		purpose = "Compose mounts and unmounts parts of the tree: a condition, a keyed branch, a keyed list, and an exit phase.",
		alternatives = "Visible = false when the node must keep its place.",
		snippet = "Compose.show(loaded, content, placeholder) · Compose.switch(mode, { a = …, b = … }) · Compose.keyed { from, key, render } · Compose.presence(open, build, { exit })",
		surface = "Facet.Compose",
		base = function()
			return {}
		end,
		axes = { { key = "structure", values = { "show", "switch", "keyed", "presence" } } },
		states = {},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local Compose: ComposeModule = c.Compose
			local kind = p.structure or "show"
			if kind == "show" then
				local loaded = Compose.cell(false)
				return UI.VStack(stacked({
					gap = "s",
					UI.Toggle({ label = "Loaded", value = loaded }),
					Compose.show(loaded, function()
						return UI.Text({ text = "Coastal Circuit · 3 laps" })
					end, function()
						return UI.Skeleton({
							form = "line",
							Size = UDim2.fromOffset(180, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
						})
					end),
				}))
			elseif kind == "switch" then
				local mode = Compose.cell("road")
				return UI.VStack(stacked({
					gap = "s",
					UI.Picker({
						selected = mode,
						style = "segmented",
						options = {
							{ value = "road", label = "Road" },
							{ value = "rally", label = "Rally" },
						},
					}),
					Compose.switch(mode, {
						road = function()
							return UI.Text({ text = "Smooth tarmac" })
						end,
						rally = function()
							return UI.Badge({
								label = "Gravel",
								appearance = "status",
								status = "warning",
							})
						end,
					}),
				}))
			elseif kind == "keyed" then
				local items = Compose.cell({ ROWS[1], ROWS[2], ROWS[3] })
				return UI.VStack(stacked({
					gap = "xs",
					UI.Button({
						label = "Rotate",
						controlSize = "compact",
						onActivate = function()
							local list = table.clone(items:peek())
							table.insert(list, assert(table.remove(list, 1)))
							items:set(list)
						end,
					}),
					Compose.keyed({
						from = items,
						key = function(item)
							return item.id
						end,
						render = function(value: Readable<Row>, index: Readable<number>): GuiObject
							return UI.Text({
								LayoutOrder = index,
								text = function(use: Use)
									return `{use(value).name} · {use(value).laps} laps`
								end,
							})
						end,
					}),
				}))
			end
			local open = Compose.cell(true)
			return UI.VStack(stacked({
				gap = "s",
				UI.Toggle({ label = "Shown", value = open }),
				Compose.presence(open, function(phase)
					local fade = c.app.runtime.tween(function(use: Use)
						return if use(phase.exiting) then 1 else 0
					end, { seconds = 0.3 })
					return UI.Text({ text = "I fade out before I leave", TextTransparency = fade })
				end, {
					exit = function()
						local done = Compose.cell(false)
						task.delay(0.3, function()
							done:set(true)
						end)
						return { completed = done }
					end,
				}),
			}))
		end,
	},
	Motion = {
		facet = true,
		family = "facet",
		alias = "Motion (runtime.tween · runtime.spring)",
		purpose = "Compose motion on any bound property: a tween with easing or a spring; reduced motion is an option.",
		alternatives = "The controls' own motion needs nothing.",
		scenarios = { "component_motion", "with_animation", "time_curves" },
		snippet = "Size = runtime.spring(function(use) return use(open) and 1 or 0 end, { period = 0.3 })",
		surface = "app.runtime.tween / app.runtime.spring",
		base = function()
			return {}
		end,
		axes = {
			{ key = "kind", values = { "tween", "spring" } },
			{ key = "reducedMotion", values = { false, true } },
		},
		states = {},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local runtime = c.app.runtime
			local at = c.Compose.cell(false)
			local body = function(use: Use): number
				return if use(at) then 1 else 0
			end
			local reduced = c.Compose.cell(p.reducedMotion == true)
			local motion: Readable<number> = if p.kind == "spring"
				then runtime.spring(body, { period = 0.4, damping = 0.6, reducedMotion = reduced })
				else runtime.tween(
					body,
					{ seconds = 0.4, ease = c.Compose.easing.outQuad, reducedMotion = reduced }
				)
			local dot = UI.Badge({
				label = "●",
				appearance = "status",
				status = "accent",
				Position = function(use: Use)
					return UDim2.new(use(motion) * 0.8, 0, 0, 0)
				end,
			})
			local track = UI.ZStack({ width = 300, height = 40, dot :: unknown })
			track:AddTag("facet-track")
			return UI.VStack(stacked({
				gap = "s",
				UI.Button({
					label = "Move",
					onActivate = function()
						at:set(not at:peek())
					end,
				}),
				track,
			}))
		end,
	},
	adaptive = {
		facet = true,
		family = "facet",
		cellWidth = 360,
		alias = "Facet.adaptive (pure decisions)",
		purpose = "Size class, height class, orientation, axis and column decisions from numbers, never a device name.",
		alternatives = "UI.environment for the live facts these decide from.",
		surface = "Facet.adaptive",
		snippet = "Facet.adaptive.sizeClass(width) · axisFor(width) · columnsFor(available, 200, 16)",
		base = function()
			return {}
		end,
		axes = { { key = "width", values = { 360, 700, 1200 } } },
		states = {},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local a = c.Facet.adaptive
			local w = p.width or 360
			return UI.Text({
				text = `sizeClass({w}) = {a.sizeClass(w)} · heightClass({w}) = {a.heightClass(w)} · orientationFor({w}, 600) = {a.orientationFor(
					w,
					600
				)} · axisFor = {a.axisFor(w)} · columnsFor(…, 200, 16) = {a.columnsFor(w, 200, 16)} · atLeast regular = {tostring(
					a.sizeClassAtLeast(a.sizeClass(w), "regular")
				)} · breakpoints {a.BREAKPOINTS.regular}/{a.BREAKPOINTS.wide}`,
				wrap = true,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			})
		end,
	},
	civilDate = {
		facet = true,
		family = "facet",
		cellWidth = 360,
		alias = "Facet.civilDate (calendar arithmetic)",
		purpose = "Civil dates with no time zone: arithmetic, words (format/parse in a locale) and fixed-offset instants.",
		alternatives = "DateTimePicker for the player's choice.",
		surface = "Facet.civilDate",
		snippet = "civil.format(civil.addDays({ year = 2026, month = 2, day = 27 }, 3))",
		base = function()
			return {}
		end,
		axes = { { key = "order", values = { "mdy", "dmy", "ymd" } } },
		states = {},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local civil = c.Facet.civilDate
			local d = { year = 2026, month = 2, day = 27 }
			local locale = { order = p.order or "mdy", separator = "/" }
			local parsed, why = civil.parse("02/30/2026")
			return UI.Text({
				text = table.concat({
					`format(+3 days) = {civil.format(civil.addDays(d, 3), locale)}`,
					`addMonths(Jan 31, 1) = {civil.format(
						civil.addMonths({ year = 2026, month = 1, day = 31 }, 1),
						locale
					)}`,
					`weekday = {civil.weekday(d)} · isLeap(2028) = {tostring(civil.isLeap(2028))} · daysIn(Feb) = {civil.daysIn(
						2026,
						2
					)}`,
					`parse("02/30/2026") = {tostring(parsed)} ({tostring(why)})`,
					`formatTime 14:05 (12h) = {civil.formatTime(
						{ year = 2026, month = 1, day = 1, hour = 14, minute = 5 },
						12
					)}`,
				}, "\n"),
				wrap = true,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			})
		end,
	},

	ButtonGroup = {
		recipe = true,
		family = "actions",
		alias = "ButtonGroup",
		purpose = "Two or three related actions in one row or column.",
		alternatives = "Dialog/Sheet `actions` inside an overlay; a Menu for many actions.",
		snippet = 'UI.HStack { gap = "s", UI.Button { label = "Cancel" }, UI.Button { label = "Save", appearance = "emphasis" } }',
		base = function()
			return {}
		end,
		axes = {
			{ key = "axis", values = { "x", "y" } },
			{ key = "sizing", values = { "fit", "fill" } },
			{ key = "count", values = { 2, 3 } },
		},
		states = {},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local grow = p.sizing == "fill"
			local function button(spec: Properties)
				if grow then
					table.insert(spec, UI.fill())
				end
				return UI.Button(spec)
			end
			local group: Properties = {
				gap = "s",
				width = if grow then 320 else "hug",
				align = if grow and p.axis == "y" then "stretch" else nil,
				button({ label = "Cancel", onActivate = c.log("cancel") }),
				button({ label = "Save", appearance = "emphasis" :: string, onActivate = c.log("save") }),
			}
			if p.count == 3 then
				table.insert(
					group,
					button({
						label = "Delete",
						role = "destructive",
						appearance = "utility",
						onActivate = c.log("delete"),
					})
				)
			end
			return if p.axis == "y" then UI.VStack(group) else UI.HStack(group)
		end,
	},
	CheckboxGroup = {
		recipe = true,
		family = "selection",
		alias = "CheckboxGroup",
		purpose = "A legend over independent checkboxes sharing one rung and side.",
		alternatives = "Picker radioGroup when exactly one may be chosen.",
		snippet = 'UI.VStack { UI.Text { text = "Show" }, UI.Toggle { presentation = "checkbox", … }, … }',
		base = function()
			return {}
		end,
		axes = {
			{ key = "controlSize", values = SIZES.values },
			{ key = "indicatorPosition", values = { "leading", "trailing" } },
			{ key = "layout", values = { "column", "wrap" } },
		},
		states = { DISABLED, { name = "hints", props = properties { hints = true } } },
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			return fieldGroup(UI, p, c, "checkbox")
		end,
	},
	ToggleGroup = {
		recipe = true,
		family = "selection",
		alias = "ToggleGroup",
		purpose = "A legend over switches sharing one rung and side.",
		alternatives = "CheckboxGroup for choices applied later.",
		snippet = 'UI.VStack { UI.Text { text = "Audio" }, UI.Toggle { label = "Music", value = music }, … }',
		base = function()
			return {}
		end,
		axes = {
			{ key = "controlSize", values = SIZES.values },
			{ key = "indicatorPosition", values = { "leading", "trailing" } },
			{ key = "layout", values = { "column", "wrap" } },
		},
		states = { DISABLED, { name = "hints", props = properties { hints = true } } },
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			return fieldGroup(UI, p, c, "switch")
		end,
	},
	ChipGroup = {
		recipe = true,
		family = "selection",
		alias = "ChipGroup",
		purpose = "Filter chips in a wrapping block or one scrolling rail.",
		alternatives = "Picker segmented for one exclusive choice.",
		snippet = 'UI.HStack { wrap = true, gap = "s", UI.Chip { label = "Rain", selected = rain }, … }',
		base = function()
			return {}
		end,
		axes = { { key = "layout", values = { "wrap", "scroll" } }, SIZES },
		states = { DISABLED },
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local chips: { [any]: any } = { gap = "s" }
			for _, tag in { "Rain", "Night", "Mirror", "Reverse", "Traffic", "Fog" } do
				table.insert(
					chips,
					UI.Chip({
						label = tag,
						selected = c.cell(`chip{tag}`, tag == "Night"),
						controlSize = p.controlSize,
						enabled = p.enabled,
					})
				)
			end
			if p.layout == "scroll" then
				chips.axis = "x"
				chips.width = 240
				chips.height = 56
				return UI.ScrollView(chips)
			end
			chips.wrap = true
			chips.width = 240
			return UI.HStack(chips)
		end,
	},
	HeaderBarActions = {
		recipe = true,
		family = "navigation",
		title = "HeaderBar.Actions",
		cellWidth = 360,
		alias = "HeaderBar.Actions",
		purpose = "A header's trailing row of icon actions: an HStack of icon Buttons in NavBar `trailing`.",
		alternatives = "A More Menu when there are more than three actions.",
		snippet = 'UI.NavBar { title = "Garage", trailing = UI.HStack { UI.Button { label = "Edit", icon = "edit", shape = "circle" }, … } }',
		base = function()
			return {}
		end,
		axes = { { key = "count", values = { 1, 2, 3 } } },
		states = {},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local row: Properties = { gap = "xs" }
			for i, icon in { "settings", "edit", "flag" } do
				if i <= (p.count or 1) then
					table.insert(
						row,
						UI.Button({
							label = icon,
							icon = icon,
							shape = "circle",
							appearance = "utility",
							onActivate = c.log(`action {icon}`),
						})
					)
				end
			end
			return UI.NavBar({ title = "Garage", trailing = UI.HStack(row) :: GuiObject, Size = UDim2.fromScale(1, 0) })
		end,
	},
	Empty = {
		recipe = true,
		family = "status",
		cellWidth = 280,
		alias = "Empty state",
		purpose = "A region placeholder: icon, title, message and one next action.",
		alternatives = "Skeleton while loading; Notice for a transient condition.",
		snippet = 'UI.VStack { align = "center", UI.Label { icon = "flag", … }, UI.Text { … }, UI.Button { appearance = "soft" } }',
		base = function()
			return {}
		end,
		axes = { { key = "kind", values = { "empty", "no results", "failed" } } },
		states = {},
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local copy = ({
				empty = { "flag", "No tracks yet", "Create one to race it with friends.", "Create" },
				["no results"] = { "menu", "No matches", "Nothing matches your filters.", "Clear search" },
				failed = { "status.warning", "Couldn't load", "Check your connection and try again.", "Retry" },
			})[p.kind or "empty"]
			return UI.VStack({
				width = "fill",
				align = "center",
				gap = "s",
				padding = "m",
				UI.Label({ title = copy[2], icon = copy[1], presentation = "iconOnly", iconSize = 32 }),
				UI.Text({ text = copy[2], textRole = "strong", textAlign = "center" }),
				UI.Text({
					text = copy[3],
					role = "secondary",
					textAlign = "center",
					wrap = true,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
				}),
				UI.Button({ label = copy[4], appearance = "soft", onActivate = c.log(copy[4]) }),
			})
		end,
	},
	Tooltip = {
		recipe = true,
		family = "overlays",
		alias = "Tooltip",
		purpose = "Hover/focus help: `help` on a Button (title, body, shortcut, edge, align). Nothing on touch, by design.",
		alternatives = "Callout to teach a feature; Popover for interactive content.",
		snippet = 'UI.Button { label = "Plus", help = { title = "Laps", body = "Adds a lap", shortcut = { { "L" } } } }',
		base = function()
			return {}
		end,
		axes = {
			{ key = "edge", values = { "bottom", "top", "leading", "trailing" } },
			{ key = "align", values = { "start", "center", "end" } },
		},
		states = { { name = "one sentence", props = properties { plain = true }, across = false } },
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			if p.plain then
				return UI.Button({ label = "Plus", help = "Adds a lap", onActivate = c.log("plus") })
			end
			return UI.Button({
				label = "Plus",
				onActivate = c.log("plus"),
				help = {
					title = "Laps",
					body = "Adds a lap to the race.",
					shortcut = { { "L" } },
					edge = p.edge,
					align = p.align,
				},
			})
		end,
	},
	SearchForm = {
		recipe = true,
		family = "inputs",
		title = "Search",
		cellWidth = 280,
		alias = "SearchInput (search form)",
		purpose = 'A search field filtering a list live: `TextInput { presentation = "search" }` has the leading mark and a clear button.',
		alternatives = "ComboBox to pick one suggestion; Picker with `query` for a searchable choice.",
		scenarios = { "text_controls" },
		snippet = 'UI.TextInput { presentation = "search", value = query, onCommit = run }',
		base = function()
			return {}
		end,
		axes = { FIELD_APPEARANCE, SIZES, CORNERS },
		states = { DISABLED },
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			local query = c.cell("query", "")
			local function matches(use: Use, row): boolean
				local q = string.lower(use(query))
				return q == "" or string.find(string.lower(row.name), q, 1, true) ~= nil
			end

			local list: Properties = { width = "fill", gap = "xs" }
			for _, row in ROWS do
				table.insert(
					list,
					UI.Text({
						text = `{row.name} · {row.laps} laps`,
						Visible = function(use: Use)
							return matches(use, row)
						end,
					})
				)
			end
			return UI.VStack(stacked({
				width = "fill",
				gap = "s",
				UI.TextInput({
					presentation = "search",
					value = query,
					placeholder = "Search tracks",
					clearButton = true,
					onCommit = c.log("onCommit"),
					appearance = p.appearance,
					controlSize = p.controlSize,
					corners = p.corners,
					enabled = p.enabled,
					Size = UDim2.fromScale(1, 0),
				}),
				UI.VStack(list),
				c.Compose.show(function(use: Use)
					for _, row in ROWS do
						if matches(use, row) then
							return false
						end
					end
					return true
				end, function()
					return UI.Text({ text = "No tracks match", role = "secondary" })
				end),
			}))
		end,
	},
	SettingsRows = {
		recipe = true,
		family = "selection",
		title = "Settings rows",
		cellWidth = 360,
		alias = "List (settings rows)",
		purpose = "Button, Toggle and Slider rows share one leading edge: a settings list from public row options.",
		alternatives = "Table for data.",
		snippet = 'UI.Button { row = { title = "Garage", value = "12" } } · UI.Toggle { row = { … } } · UI.Slider { row = { … } }',
		base = function()
			return {}
		end,
		axes = { SIZES },
		states = { DISABLED },
		make = function(UI: FacetControls, p: Properties, c: Context): Instance
			return UI.VStack(stacked({
				width = "fill",
				gap = 0,
				UI.Button({
					label = "Garage",
					row = { description = "12 cars", icon = "settings", value = "Open" },
					onActivate = c.log("garage"),
					enabled = p.enabled,
					controlSize = p.controlSize,
				}),
				UI.Divider({}),
				UI.Toggle({
					label = "Music",
					row = { description = "Plays in menus", icon = "edit" },
					value = c.cell("music", true),
					enabled = p.enabled,
					controlSize = p.controlSize,
				}),
				UI.Divider({}),
				UI.Slider({
					label = "Volume",
					row = { description = "Master", icon = "flag" },
					value = c.cell("volume", 60),
					min = 0,
					max = 100,
					enabled = p.enabled,
					Size = UDim2.fromScale(1, 0),
				}),
			}))
		end,
	},
}

local function hierarchyState(c: any): { [string]: any }
	local rows = c.cell(
		"treeRows",
		{
			{
				id = "folder",
				name = "Championship",
				laps = 0,
				children = {
					{ id = "coast", name = "Coastal Circuit", laps = 3 },
					{
						id = "nested",
						name = "Time trials",
						laps = 0,
						children = {
							{ id = "harbour", name = "Harbour Sprint", laps = 6 },
						},
					},
				},
			},
			{ id = "empty", name = "Community races", laps = 0, children = {} },
			{ id = "readme", name = "Practice loop", laps = 1 },
		} :: { any }
	)
	local expanded = c.cell("expanded", {})
	return {
		from = rows,
		children = "children",
		expanded = expanded,
		indent = 24,
		onExpansionChange = function(value)
			expanded:set(value)
			c.log("onExpansionChange")(value)
		end,
		onActivate = NONE,
	}
end
for _, name in { "VirtualList", "Table" } do
	table.insert(
		assert(PAGE_DATA[name].states),
		{ name = "expandable hierarchy", props = hierarchyState, across = false }
	)
end
PAGE_DATA.Outline = {
	demonstrates = { "slots", "slotControls" },
	family = "collections",
	alias = "Outline",
	cellWidth = 340,
	cellHeight = 280,
	purpose = "Expand nested groups, select rows, and edit items in one hierarchy.",
	note = "Expand a group with its arrow; Left/Right collapse or expand the focused row. Selection and expansion settings are below; events go to the log.",
	alternatives = "VirtualList for flat rows. Table with children for hierarchy with columns.",
	snippet = 'UI.Outline { from = roots, key = "id", children = "children", expanded = expanded, render = renderCell }',
	base = function(c: Context)
		local spec: any = assert(PAGE_DATA.VirtualList.base)(c)
		for key, value in hierarchyState(c) do
			spec[key] = if value == NONE then nil else value
		end
		spec.selection = c.cell("outlineSelection", {})
		return spec
	end,
	axes = { { key = "selectionMode", values = { "single", "multiple" }, matrix = false } },
	states = {
		{ name = "content clipped", props = properties { contentOverflow = "clip" } },
		{ name = "content visible", props = properties { contentOverflow = "visible" } },
		{
			name = "expanded",
			props = function(c: Context)
				local expanded = c.cell("expandedExample", { folder = true, nested = true })
				return {
					expanded = expanded,
					onExpansionChange = function(value)
						expanded:set(value)
						c.log("onExpansionChange")(value)
					end,
				}
			end,
		},
		{ name = "large indentation", props = properties { indent = 48 } },
		{ name = "reduced motion", props = properties { reducedMotion = true } },
		{
			name = "disabled folder",
			props = properties {
				disabled = function(item)
					return item.id == "folder"
				end,
			},
		},
	},
}

for _, name in { "VirtualList", "VirtualGrid", "Outline" } do
	table.insert(assert(PAGE_DATA[name].axes), {
		key = "scrollReset",
		values = { "start", "once", "twice" },
		matrix = false,
	})
	table.insert(assert(PAGE_DATA[name].states), {
		name = "reserved key slot",
		props = properties {
			slots = if name == "Outline" then { "folder", "reserved" } else { "1", "reserved", "2" },
			slotControls = {},
		},
	})
end

for _, name in { "VirtualList", "VirtualGrid", "Table", "Outline" } do
	table.insert(assert(PAGE_DATA[name].states), {
		name = "drop a row onto another to copy its lap count",
		props = function(c)
			local props = rowDropState(c)
			if name == "Table" then
				props.render = nil
			end
			return props
		end,
	})
end

for _, name in
	{ "Screen", "VStack", "HStack", "ZStack", "ScrollView", "Grid", "AdaptiveStack", "ViewThatFits", "ErrorBoundary" }
do
	table.insert(assert(PAGE_DATA[name].states), {
		name = "width 480 capped at 280",
		props = properties { width = 480, maxWidth = 280, Size = NONE },
	})
end

PAGE_DATA.gestureArbiter = {
	host = "ScrollView",
	family = "layout",
	alias = "Shared gesture decision",
	purpose = "Keep a child drag and a parent pan from using the same contact.",
	alternatives = "ZoomView and draggable consult this policy directly.",
	snippet = "local gesture = UI.gestureArbiter(surface)",
	demonstrates = { "begin", "move", "claim", "get", "finish" },
	axes = {},
	states = {},
	make = function(UI: FacetControls, _: Properties, c: Context): Instance
		local surface = require("./container_transfer_demo")(UI, c.Host, c.Compose, c.types, { scrolled = true })
		UI.gestureArbiter(surface)
		return surface
	end,
}

PAGE_DATA.DiegeticScreen = require("./diegetic_demo")
PAGE_DATA.WorldMarker = require("./world_marker_demo")

PAGE_DATA.ZoomView = require("./zoom_page")
PAGE_DATA.SpatialGrid = require("./spatial_grid_demo")
PAGE_DATA.CustomTransitions = require("./custom_transition_demo")

PAGE_DATA.Travel = {
	family = "layout",
	purpose = "Move one tile between clipped rows and show its destination.",
	alternatives = "Use Travel for every item slot change.",
	snippet = 'UI.Travel { destination = destination, path = "arc", content = Tile }',
	base = function()
		return { path = "arc", many = false, shuffle = false, recycle = false }
	end,
	axes = {
		{ key = "path", values = { "straight", "arc" } },
		{ key = "many", values = { false, true } },
		{ key = "shuffle", values = { false, true } },
		{ key = "recycle", values = { false, true } },
	},
	states = {
		{ name = "recycled destinations", props = properties { recycle = true } },
		{ name = "shuffle a row", props = properties { shuffle = true } },
		{ name = "many items, same container", props = properties { many = true } },
		{ name = "straight", props = properties { path = "straight" } },
		{ name = "arc", props = properties { path = "arc" } },
	},
	make = function(UI: FacetControls, p: Properties, c: Context): Instance
		if p.recycle then
			return require("./travel_recycle_demo")(UI, c.Host, c.Compose)
		end
		if p.shuffle then
			return require("./zoom_travel_demo").shuffle(UI, c.Host, c.Compose)
		end
		if p.many then
			return require("./zoom_travel_demo").many(UI, c.Host, c.Compose)
		end
		return require("./zoom_travel_demo").travel(
			UI,
			c.Host,
			c.Compose,
			if p.path == "straight" then "straight" else "arc"
		)
	end,
}

PAGE_DATA.RewardSequence = {
	recipe = true,
	family = "media",
	purpose = "Order a reward with lock, sweep, flash, travel, count and refill.",
	alternatives = "Use Travel for one slot change.",
	snippet = "local reward = UI.sequence { steps = steps }; reward.play()",
	base = function()
		return { pulse = true }
	end,
	axes = { { key = "pulse", values = { true, false } } },
	states = {
		{ name = "reward sequence", props = properties {} },
		{ name = "sweep only", props = properties { pulse = false } },
	},
	make = function(UI: FacetControls, p: Properties, c: Context): Instance
		return require("./reward_sequence_demo")(UI, c.Host, c.Compose, p.pulse ~= false)
	end,
}
PAGE_DATA.sequence = PAGE_DATA.RewardSequence
PAGE_DATA.countUp = {
	family = "media",
	purpose = "Show a changing total.",
	alternatives = "Use Text for a fixed number.",
	snippet = "local number = UI.countUp(total)",
	axes = {},
	states = {},
	make = PAGE_DATA.RewardSequence.make,
}
PAGE_DATA.Flash = {
	family = "media",
	purpose = "Pulse or sweep over a GUI target.",
	alternatives = "Use a game-owned state for a lasting highlight.",
	snippet = "UI.Flash { target = slot, progress = progress }",
	axes = {},
	states = {},
	make = PAGE_DATA.RewardSequence.make,
}

PAGE_DATA.format = {
	facet = true,
	family = "media",
	purpose = "Read currency and XP totals in a HUD counter strip.",
	surface = "Facet.format",
	alternatives = "Use grouped for an exact wallet total.",
	snippet = "UI.Text { text = Facet.format.compact(93210) }",
	axes = {},
	states = {},
	make = function(_UI: FacetControls, _p: Properties, c: Context): Instance
		return require("./hud_demo").counters(c)
	end,
}
PAGE_DATA.Timer = {
	family = "media",
	purpose = "Track a round deadline and show its completion.",
	alternatives = "Use Facet.format.duration for a fixed duration.",
	snippet = "UI.Timer { deadline = roundDeadline, now = os.clock }",
	demonstrates = { "deadline", "start", "now", "onComplete", "textRole", "controls" },
	axes = { { key = "hours", values = { false, true } }, { key = "elapsed", values = { false, true } } },
	states = {},
	make = function(_UI: FacetControls, p: Properties, c: Context): Instance
		return require("./hud_demo").timer(c, p.hours == true, p.elapsed == true)
	end,
}
PAGE_DATA.Typewriter = {
	family = "media",
	purpose = "Read an NPC dialogue line as it appears, or skip the reveal.",
	alternatives = "Use Text to show the full line at once.",
	snippet = "UI.Typewriter { text = dialogueLine, controls = reveal }",
	demonstrates = { "controls", "onRevealed" },
	axes = {},
	states = {},
	make = function(_UI: FacetControls, _p: Properties, c: Context): Instance
		return require("./hud_demo").dialogue(c)
	end,
}

local function kindOf(id: string, data: any, UI: any): string
	if UI[id] ~= nil then
		return "control"
	end
	return if data and data.recipe then "recipe" elseif data and data.facet then "facet" else "stale"
end

export type Page = { id: string, title: string, family: string, kind: string, data: any, helpers: { Page }? }

function catalog.build(UI: any): any
	local pages: { [string]: Page } = {}
	local missing: { string } = {}
	local stale: { string } = {}
	local ids = {}
	for id in UI do
		table.insert(ids, id)
	end
	for id in PAGE_DATA do
		if UI[id] == nil then
			table.insert(ids, id)
		end
	end
	for _, id in ids do
		local data = PAGE_DATA[id]
		local kind = kindOf(id, data, UI)
		if kind == "stale" then
			table.insert(stale, id)
			continue
		end
		if data == nil then
			table.insert(missing, id)
			data = {
				family = "layout",
				purpose = "No lab data yet: a public capability the lab does not show (coverage fails).",
				axes = {},
				states = {},
			}
		end
		pages[id] = { id = id, title = data.title or id, family = data.family, kind = kind, data = data }
	end
	for id, page in pages do
		local host = page.data.host and pages[page.data.host]
		if host then
			host.helpers = host.helpers or {}
			table.insert(host.helpers, page)
			table.sort(host.helpers, function(a, b)
				return a.id < b.id
			end)
			pages[id] = nil
		end
	end
	local families = {}
	for _, family in catalog.FAMILIES do
		local members: { Page } = {}
		for _, page in pages do
			if page.family == family.id then
				table.insert(members, page)
			end
		end
		table.sort(members, function(a, b)
			return string.lower(a.title) < string.lower(b.title)
		end)
		table.insert(families, { id = family.id, label = family.label, pages = members })
	end
	table.sort(missing)
	table.sort(stale)
	return { families = families, pages = pages, missing = missing, stale = stale }
end

catalog.PAGE_DATA = PAGE_DATA
return catalog
