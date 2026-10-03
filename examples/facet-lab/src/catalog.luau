--!strict

local catalog = {}

catalog.NONE = table.freeze({})
local NONE = catalog.NONE

catalog.DEFAULT = "(default)"
local DEFAULT = catalog.DEFAULT

local ART = "rbxassetid://75342910516929"
local ROWS = {
	{ id = "1", name = "Coastal Circuit", laps = 3 },
	{ id = "2", name = "Canyon Run", laps = 5 },
	{ id = "3", name = "City Loop", laps = 4 },
	{ id = "4", name = "Glacier Pass", laps = 2 },
	{ id = "5", name = "Harbour Sprint", laps = 6 },
	{ id = "6", name = "Desert Dunes", laps = 3 },
}

local function transferState(c)
	local rows = c.cell("transferRows", ROWS)
	local serial = 0
	return {
		from = rows,
		collectionId = rows,
		drag = function(items, keys)
			return { payload = { items = items, keys = keys, collection = rows }, operations = { "copy" } }
		end,
		drop = {
			operation = "copy",
			accepts = function(payload)
				return type(payload) == "table" and payload.items ~= nil
			end,
			onDrop = function(payload, info)
				local next = table.clone(rows:peek())
				for index, item in payload.items do
					serial += 1
					local copy = table.clone(item)
					copy.id, copy.name = "copy-" .. serial, item.name .. " copy"
					table.insert(next, info.insertion.slot + index, copy)
				end
				rows:set(next)
				c.log("onDrop")(info.operation, info.insertion.slot)
				return true
			end,
		},
	}
end

local function emptyStatus(c: any): any
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

local SIZES = { key = "controlSize", values = { "xsmall", "compact", "regular", "large" } }
local CORNERS = { key = "corners", values = { DEFAULT, "pill", "square" } }
local FIELD_APPEARANCE = { key = "appearance", values = { "standard", "contrast", "utility" } }
local DISABLED = { name = "disabled", props = { enabled = false } }
local function fixed(w: number, h: number?): any
	return {
		Size = UDim2.fromOffset(w, h or 0),
		AutomaticSize = if h then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
	}
end
local function merged(a: { [any]: any }, b: { [any]: any }): { [any]: any }
	local out = table.clone(a)
	for k, v in b do
		out[k] = v
	end
	return out
end
local function para(c: any, text: any, props: { [string]: any }?): any
	return c.UI.Text(merged({
		text = text,
		wrap = true,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, props or {}))
end

local function plate(c: any, tag: string, w: number, h: number): any
	local node = c.Host.Frame({ Size = UDim2.fromOffset(w, h), BorderSizePixel = 0 })
	node:AddTag(tag)
	return node
end

local ALIGN = { key = "align", values = { "start", "center", "end", "stretch" } }
local DISTRIBUTE =
	{ key = "distribute", values = { "start", "center", "end", "spaceBetween", "spaceAround", "spaceEvenly" } }
local GAP = { key = "gap", values = { "xs", "s", "m", "l", "xl" } }

local function stackDemo(c: any, props: { [any]: any }): { [any]: any }
	props.gap = props.gap or "s"
	props.padding = props.padding or "s"
	for _, size in { { 40, 24 }, { 72, 48 }, { 56, 32 } } do
		table.insert(props, plate(c, "facet-control", size[1], size[2]))
	end
	props.ref = function(node)
		node:AddTag("facet-panel")
	end
	return props
end

local function menuItems(c: any): { any }
	return {
		{ id = "edit", label = "Edit", icon = "edit", onSelect = c.log("onSelect edit") },
		{ id = "flag", label = "Report", icon = "flag", onSelect = c.log("onSelect flag") },
		{ id = "d1", divider = true },
		{ id = "delete", label = "Delete", icon = "trash", role = "destructive", onSelect = c.log("onSelect delete") },
	}
end

local function trigger(c: any, label: string, overlay: (open: any) -> any): any
	local open = c.cell("open", false)
	return c.UI.VStack({
		gap = "xs",
		c.UI.Button({
			label = label,
			onActivate = function()
				open:set(true)
			end,
		}),
		overlay(open),
	})
end

local function fieldGroup(UI: any, p: any, c: any, presentation: string): any
	local items: { any } = { gap = if p.layout == "wrap" then "s" else "xs", wrap = p.layout == "wrap" }
	for i, label in { "Tire wear", "Fuel use", "Damage" } do
		table.insert(
			items,
			UI.Toggle({
				label = label,
				presentation = presentation,
				value = c.cell(`{presentation}{i}`, i == 1),
				controlSize = p.controlSize,
				indicatorPosition = p.indicatorPosition,
				hint = if p.hints then "Shown in the pit panel" else nil,
				enabled = p.enabled,
				Size = if p.layout == "wrap" then nil else UDim2.fromScale(1, 0),
			})
		)
	end
	items.width = "fill"
	return UI.VStack({
		width = 260,
		gap = "xs",
		UI.Text({ text = "Show in race", textRole = "label", role = "secondary" }),
		if p.layout == "wrap" then UI.HStack(items) else UI.VStack(items),
	})
end

local PAGE_DATA: { [string]: any } = {

	Button = {
		family = "actions",
		alias = "Button · IconButton · Link · ButtonGroup",
		purpose = "Starts an action. Appearance sets emphasis; role carries meaning (destructive).",
		alternatives = "Toggle for an on/off setting; Picker for choosing one value; Menu for many actions.",
		scenarios = { "action_controls", "shortcut_hint" },
		snippet = 'UI.Button { label = "Save", appearance = "emphasis", onActivate = save }',
		base = function(c)
			return { label = "Button", onActivate = c.log("onActivate") }
		end,
		axes = {
			{ key = "appearance", values = { "standard", "emphasis", "soft", "utility", "link", "inverse" } },
			SIZES,
			CORNERS,
			{ key = "role", values = { "default", "destructive", "cancel", "onIndicator" } },

			{ key = "shape", values = { DEFAULT, "rect", "circle" }, implies = { circle = { icon = "settings" } } },
		},
		states = {
			{ name = "discloses a truncated label", props = merged(fixed(120, 44), { label = LONG, disclose = true }) },
			{ name = "fixed 140×64", props = fixed(140, 64) },
			{
				name = "compact label (short room)",
				props = merged(fixed(110, 44), { label = LONG, compactLabel = "Save" }),
			},
			{ name = "image button", props = { image = ART, subtitle = "12 playing", imageAspectRatio = 16 / 9 } },
			{ name = "image, crop framing", props = { image = ART, imageFraming = "crop", imageAspectRatio = 1 } },
			{
				name = "settings row",
				props = { row = { description = "Shown in the garage", icon = "settings", value = "On" } },
			},
			{ name = "hint line", props = { hint = "Saves your setup" } },
			{ name = "pop on press", props = { pop = true } },
			{ name = "haptic", props = { haptic = true } },
			{ name = "hold repeats", props = { repeatDelay = 0.4, repeatInterval = 0.1 } },
			{ name = "shortcut S", props = { shortcut = { keyCode = "S" } } },
			{ name = "dialog default (Return)", props = { dialogAction = "default" } },
			{ name = "help plate", props = { help = "Saves your setup" } },
			{
				name = "help: title, shortcut, top edge",
				props = {
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
				props = function(c)
					return {
						onPointerDown = c.log("onPointerDown"),
						onPointerUp = c.log("onPointerUp"),
						onPointerCancel = c.log("onPointerCancel"),
					}
				end,
			},
			{ name = "label text size", props = { textSize = "label" } },
			{ name = "named icon (circle)", props = { icon = "settings", shape = "circle", name = "Settings" } },
			DISABLED,
			{ name = "disabled (alias)", props = { disabled = true } },
			{ name = "selected", props = { selected = true } },
			{ name = "busy", props = { busy = true } },
			{ name = "icon", props = { icon = "settings" } },
			{ name = "trailing icon", props = { trailingIcon = "chevron.trailing" } },
			{ name = "underline always", props = { appearance = "link", underline = "always" } },
			{ name = "underline on hover", props = { appearance = "link", underline = "hover" } },
			{ name = "long text", props = { label = LONG } },
		},
		valid = function(p)
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
		base = function(c)
			return { label = "Start race", onActivate = c.log("onActivate"), items = menuItems(c) }
		end,
		axes = {},
		states = {
			{ name = "menu label", props = { menuLabel = "More start options" } },
			{ name = "shortcut R", props = { shortcut = { keyCode = "R" } } },
			DISABLED,
			{ name = "busy", props = { busy = true } },
			{ name = "long text", props = { label = LONG } },
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
		base = function(c)
			return { label = "Actions", items = menuItems(c) }
		end,
		axes = {
			{ key = "edge", values = { "bottom", "top", "leading", "trailing" }, matrix = false },
			{ key = "align", values = { "start", "center", "end" }, matrix = false },
			{ key = "presentation", values = { "automatic", "menu", "sheet" }, matrix = false },
		},
		states = {
			{
				name = "diagnostics controls",
				props = function(c)
					local controls = {}
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
				props = function(c)
					return { label = NONE, trigger = c.UI.Button({ label = "More", icon = "more", shape = "circle" }) }
				end,
			},
			{ name = "disclosure chevron", props = { disclosure = true } },
			{ name = "opens on activate + secondary only", props = { triggers = { "activate", "secondary" } } },
			{ name = "sheet back label", props = { presentation = "sheet", backLabel = "Previous" } },
			{
				name = "open / close reported",
				props = function(c)
					return { onOpen = c.log("onOpen"), onClose = c.log("onClose") }
				end,
			},
			{
				name = "controlled open",
				props = function(c)
					return { isPresented = c.cell("menuOpen", false) }
				end,
			},
			DISABLED,
			{
				name = "avatar, badge, meta, sections, disabled row",
				props = function(c)
					return {
						items = {
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
				props = function(c)
					local mode = c.cell("menuMode", "rally")
					return {
						items = {
							{ id = "grid", label = "Show grid", checked = c.cell("menuGrid", true) },
							{ id = "d1", divider = true },
							{ id = "road", label = "Road", selected = mode, value = "road" },
							{ id = "rally", label = "Rally", selected = mode, value = "rally" },
						},
					}
				end,
			},
			{ name = "width 320", props = { width = 320 } },
			{ name = "maxHeight 140", props = { maxHeight = 140 } },
			{
				name = "searchable",
				props = function(c)
					return { query = c.cell("menuQuery", "") }
				end,
			},
			{
				name = "submenu + shortcuts",
				props = function(c)
					return {
						items = {
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
		base = function(c)
			local items = {}
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

		make = function(UI, p)
			local style = p.labelStyle
			p.labelStyle = nil
			if style ~= nil then
				local items = {}
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
				implies = {
					compass = function(c)
						local items = {}
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
		valid = function(p)
			return not (p.distribution == "compass" and p.preset ~= nil and p.preset ~= "donut")
				and not (p.buttonSurface ~= nil and p.appearance ~= "buttons")
				and not (p.center == "content" and p.centerContent == nil)
		end,
		states = {
			DISABLED,
			{
				name = "list form (crowded ring)",
				props = function(c)
					local items = {}
					for i = 1, 20 do
						table.insert(
							items,
							{ id = `emote{i}`, label = `Emote {i}`, onSelect = c.log(`onSelect emote{i}`) }
						)
					end
					return { items = items }
				end,
			},
			{ name = "centre label", props = { centerLabel = "Pick one" } },
			{
				name = "centre content",
				props = function(c)
					return {
						center = "content",
						centerContent = c.UI.Label({ title = "Kart", icon = "person", presentation = "iconOnly" }),
					}
				end,
			},
			{ name = "centre passes presses through", props = { centerPassThrough = true } },
			{ name = "clearance 40", props = { clearance = 40 } },
			{ name = "no motion", props = { transition = false } },
			{
				name = "no launcher (controlled)",
				props = function(c)
					return { launcher = false, isPresented = c.cell("radialOpen", true) }
				end,
			},
			{
				name = "open / close reported",
				props = function(c)
					return { onOpen = c.log("onOpen"), onClose = c.log("onClose") }
				end,
			},
			{
				name = "hold action (InputAction)",
				props = function(c)
					local action = c.Host.InputAction({ Name = "LabRadialHold" })
					c.Host.InputContext({ Name = "LabRadialContext", Parent = workspace, action })
					return { holdAction = action }
				end,
			},
			{
				name = "anchored at a point",
				props = { anchor = { x = 400, y = 300, visible = true } },
			},
			{
				name = "skinned slots",
				props = { skin = { item = { default = ART }, center = { default = ART } } },
			},
		},
	},
	ShortcutHint = {
		family = "actions",
		alias = "Shortcut",
		purpose = "Shows the key or button for an action, adapting to the live input device.",
		alternatives = "Button.shortcut to bind the key on the action itself.",
		scenarios = { "shortcut_hint" },
		snippet = 'UI.ShortcutHint { keys = { { "Ctrl", "S" } } }',
		base = function()
			return { keys = { { "Ctrl", "S" } } }
		end,
		axes = { SIZES },
		states = {
			{
				name = "action (device-adaptive)",
				props = function(c)
					local action = c.Host.InputAction({
						Name = "LabSave",
						c.Host.InputBinding({ KeyCode = Enum.KeyCode.F2, UIButton = nil }),
					})
					return { keys = NONE, action = action }
				end,
			},
			{ name = "alternatives", props = { keys = { { "Ctrl", "S" }, { "F2" } }, separator = " or " } },
			{ name = "label after", props = { label = "Save" } },
			{ name = "label before", props = { label = "Save", labelPosition = "start" } },
		},
		valid = function(p)
			return not (p.action ~= nil and p.keys ~= nil)
		end,
	},

	TextInput = {
		family = "inputs",
		valid = function(p)
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
		base = function(c)
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
				implies = {
					number = function(c)
						return { value = c.cell("draft", "42"), numericValue = c.cell("number", 42) }
					end,
				},
			},
		},
		states = {
			DISABLED,
			{ name = "disabled (alias)", props = { disabled = true } },
			{ name = "read only", props = { readOnly = true } },
			{ name = "error", props = { errorText = "That name is taken" } },
			{
				name = "invalid (readable)",
				props = function(c)
					return { invalid = c.cell("invalid", true) }
				end,
			},
			{ name = "hint + required", props = { hint = "Shown to other players", requiredMark = "required" } },
			{ name = "optional mark", props = { requiredMark = "optional" } },
			{
				name = "empty",
				props = function(c)
					return { value = c.cell("empty", "") }
				end,
			},
			{ name = "clear button", props = { clearButton = true } },
			{ name = "clear while editing", props = { clearButton = true, clearButtonMode = "whileEditing" } },
			{
				name = "leading + trailing",
				props = function(c)
					return {
						leading = c.UI.Label({ title = "Name", icon = "person", presentation = "iconOnly" }),
						trailing = c.UI.Text({ text = "kg", role = "secondary" }),
					}
				end,
			},
			{ name = "select all on focus", props = { selectOnFocus = "all" } },
			{ name = "max 10 characters", props = { maxLength = 10 } },
			{
				name = "validate: letters only",
				props = {
					validate = function(text)
						return if string.find(text, "%d") then nil else text
					end,
				},
			},
			{
				name = "change, commit, cancel reported",
				props = function(c)
					return { onChange = c.log("onChange"), onCommit = c.log("onCommit"), onCancel = c.log("onCancel") }
				end,
			},
			{ name = "multiline, 3 lines", props = { multiline = true, visibleLines = 3 } },
			{
				name = "number bounds + format",
				props = function(c)
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
				props = function(c)
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
		base = function(c)
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
			{ name = "step buttons", props = { stepButtons = true } },
			{ name = "prefix/suffix", props = { prefix = "$", suffix = "km/h" } },
			{ name = "error", props = { errorText = "Out of range" } },
			{ name = "scrub (drag)", props = { scrub = true } },
			{ name = "precision 2", props = { precision = 2, step = 0.25 } },
			{
				name = "arithmetic parse (Facet.recipes)",
				props = function(c)
					return { parse = c.Facet.recipes.arithmetic.parse, hint = "Try 2*60+5" }
				end,
			},
			{
				name = "commit reported",
				props = function(c)
					return { onCommit = c.log("onCommit") }
				end,
			},
			{ name = "select all on focus", props = { selectOnFocus = "all" } },
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
		base = function(c)
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
				props = function(c)
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
		base = function(c)
			return { label = "Volume", value = c.cell("value", 40), min = 0, max = 100, Size = UDim2.fromScale(1, 0) }
		end,
		make = function(UI, p, c)
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
				Size = function(use)
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
			{ name = "settings row", props = { row = { description = "Master volume", icon = "settings" } } },
			{
				name = "percent format",
				props = {
					format = function(v)
						return `{math.round(v)}%`
					end,
				},
			},
			{ name = "no tap-to-position", props = { tapToPosition = false } },
			{
				name = "change and commit reported",
				props = function(c)
					return { onChange = c.log("onChange"), onCommit = c.log("onCommit") }
				end,
			},
			{
				name = "range, min gap 20",
				props = function(c)
					return { range = true, minGap = 20, value = c.cell("gapRange", { lower = 20, upper = 70 }) }
				end,
			},
			{ name = "image knob and track", props = { thumbImage = ART, trackImage = ART } },
			DISABLED,
			{ name = "stepped", props = { step = 10 } },
			{
				name = "custom knob",
				props = function(c)
					return {
						thumbContent = function()
							return c.UI.Badge({ label = "♦", appearance = "status", status = "accent" })
						end,
					}
				end,
			},
			{
				name = "colour track",
				props = function(c)
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
				props = function(c)
					return { range = true, value = c.cell("range", { lower = 20, upper = 70 }) }
				end,
			},
			{ name = "vertical", props = { axis = "y", Size = UDim2.fromOffset(80, 200) } },
		},
		valid = function(p)
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
		base = function(c)
			return { label = "Laps", value = c.cell("value", 3), min = 1, max = 10 }
		end,
		axes = {},
		states = {
			{ name = "step 2", props = { step = 2 } },
			{ name = "slow repeat (1 s, then 0.5 s)", props = { repeatDelay = 1, repeatInterval = 0.5 } },
			{
				name = "format + change reported",
				props = function(c)
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
				props = function(c)
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
		base = function(c)
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
		axes = { FIELD_APPEARANCE, SIZES, { key = "style", values = { "automatic", "inline" } } },
		states = {
			{
				name = "label, hint, required",
				props = { label = "Team colour", hint = "Shown on your kart", requiredMark = "required" },
			},
			{
				name = "empty with placeholder",
				props = function(c)
					return { allowEmpty = true, placeholder = "No colour", value = c.cell("emptyColor", nil) }
				end,
			},
			{ name = "square corners", props = { corners = "square" } },
			{
				name = "saved swatches",
				props = function(c)
					return {
						swatches = {
							Color3.fromRGB(220, 60, 60),
							{ color = Color3.fromRGB(60, 160, 90), label = "Pit green" },
						},
						onSaveSwatch = c.log("onSaveSwatch"),
						onRemoveSwatch = c.log("onRemoveSwatch"),
					}
				end,
			},
			{
				name = "commit reported",
				props = function(c)
					return { onCommit = c.log("onCommit") }
				end,
			},
			{
				name = "presented by the caller",
				props = function(c)
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
			{ name = "read only", props = { readOnly = true } },
			{ name = "error", props = { errorText = "Too dark" } },
			{ name = "draft (Cancel / Apply)", props = { draft = true } },
			{ name = "brick colours", props = { modes = { "swatches", "brick" } } },
			{
				name = "alpha",
				props = function(c)
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
		valid = function(p)
			return not (p.selection == "range" and p.time)
		end,
		cellWidth = 320,
		alias = "DateTimePicker",
		purpose = "Chooses a civil date, date-time or range; dual-pane range, presets, controller calendar.",
		alternatives = "A Picker of preset dates when only a few days apply.",
		scenarios = { "pickers" },
		snippet = 'UI.DateTimePicker { label = "Race day", value = day, onChange = function(v) day:set(v) end }',
		base = function(c)
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
		axes = { FIELD_APPEARANCE, SIZES, { key = "style", values = { "automatic", "inline" } } },
		states = {
			{ name = "day-first locale", props = { locale = { order = "dmy", separator = "." } } },
			{
				name = "commit reported",
				props = function(c)
					return { onCommit = c.log("onCommit") }
				end,
			},
			{ name = "24-hour time", props = { time = true, hourCycle = 24 } },
			{
				name = "weekends disabled",
				props = function(c)
					return {
						isDateDisabled = function(d)
							local weekday = c.Facet.civilDate.weekday(d)
							return weekday == 1 or weekday == 7
						end,
					}
				end,
			},
			{ name = "week starts Monday", props = { weekStart = 2 } },
			{
				name = "custom field format",
				props = {
					format = function(d)
						return `{d.day}/{d.month}/{d.year}`
					end,
				},
			},
			{
				name = "presented by the caller",
				props = function(c)
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
			{ name = "read only", props = { readOnly = true } },
			{ name = "hint + required", props = { hint = "Pick a race day", requiredMark = "required" } },
			{ name = "square corners", props = { corners = "square" } },
			DISABLED,
			{
				name = "time, 15-minute grid",
				props = function(c)
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
			{ name = "error", props = { errorText = "Pick a weekday" } },
			{
				name = "empty",
				props = function(c)
					return { value = c.cell("none", nil), placeholder = "No date" }
				end,
			},
			{
				name = "min/max (Sep 10–30)",
				props = { min = { year = 2026, month = 9, day = 10 }, max = { year = 2026, month = 9, day = 30 } },
			},
			{
				name = "empty, opens on March",
				props = function(c)
					return {
						value = c.cell("noneRef", nil),
						placeholder = "No date",
						referenceDate = { year = 2027, month = 3, day = 1 },
					}
				end,
			},
			{
				name = "range presets + draft",
				props = function(c)
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
				props = function(c)
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
		base = function(c)
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
				props = { Size = UDim2.fromOffset(220, 0), AutomaticSize = Enum.AutomaticSize.Y },
			},
			{ name = "settings row", props = { row = { description = "Plays in menus", icon = "settings" } } },
			{ name = "label text size", props = { textSize = "label" } },
			{
				name = "change reported",
				props = function(c)
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
				props = function(c)
					return { value = c.cell("off", false) }
				end,
			},
			{
				name = "mixed",
				props = function(c)
					return { presentation = "checkbox", mixed = c.cell("mixed", true) }
				end,
			},
			{ name = "hint", props = { hint = "Hint text" } },
			{ name = "icon", props = { icon = "settings" } },
			{ name = "long text", props = { label = LONG, Size = UDim2.fromScale(1, 0) } },
		},
		valid = function(p)
			local shape = p.presentation or "switch"
			return (p.mixed == nil or shape == "checkbox") and not (shape == "button" and p.appearance == "plain")
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
		base = function(c)
			return { label = "Chip", selected = c.cell("selected", false) }
		end,
		axes = { { key = "appearance", values = { "standard", "utility" } }, SIZES, CORNERS },
		states = {
			{
				name = "toggle reported",
				props = function(c)
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
				props = function(c)
					return { selected = c.cell("on", true) }
				end,
			},
			{
				name = "leading + trailing",
				props = function(c)
					return {
						leading = c.UI.Label({ title = "Rally", icon = "flag", presentation = "iconOnly" }),
						trailing = c.UI.Label({ title = "More", icon = "chevron.trailing", presentation = "iconOnly" }),
					}
				end,
			},
			{
				name = "removable (always editing)",
				props = function(c)
					return { selected = NONE, onRemove = c.log("onRemove") }
				end,
			},
			{
				name = "selectable + removable in edit mode",
				props = function(c)
					return {
						onRemove = c.log("onRemove"),
						editing = c.cell("editing", true),
						removeLabel = "Remove Rally",
						removeFocusFallback = c.cell("fallback", nil),
					}
				end,
			},
			{ name = "long text", props = { label = LONG } },
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
		base = function(c)
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
			{ key = "controlSize", values = SIZES.values, props = { style = "segmented" } },
			{
				key = "appearance",
				values = { DEFAULT, "standard", "contrast", "utility", "filled", "stroke" },
				implies = { filled = { style = "segmented" }, stroke = { style = "segmented" } },
			},
		},
		valid = function(p)
			local style, word = p.style or "automatic", p.appearance
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
			if
				(p.maxHeight ~= nil and style ~= "menu" and style ~= "navigationLink" and style ~= "automatic")
				or (p.required == false and style ~= "cards")
				or (p.indicatorPosition ~= nil and style ~= "radioGroup")
				or (p.valueAlignment ~= nil and style ~= "menu")
			then
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
				props = function(c)
					return {
						onChanging = function(new, old)
							c.log("onChanging")(new, old)
							return new ~= "drift"
						end,
						onChange = c.log("onChange"),
					}
				end,
			},
			{ name = "menu value at start", props = { style = "menu", valueAlignment = "start" } },
			{
				name = "searchable",
				props = function(c)
					return { query = c.cell("pickerQuery", "") }
				end,
			},
			{
				name = "menu placeholder",
				props = function(c)
					return { style = "menu", placeholder = "Choose a mode", selected = c.cell("none", nil) }
				end,
			},
			{ name = "text size 13", props = { textSize = 13 } },
			{ name = "required mark", props = { requiredMark = "required" } },
			{ name = "pill corners", props = { style = "segmented", corners = "pill" } },
			DISABLED,
			{ name = "error", props = { errorText = "Pick a mode" } },
			{ name = "hint", props = { hint = "You can change this later" } },
			{ name = "menu sizes", props = { style = "menu" }, across = "controlSize", matrixOnly = true },
			{ name = "underline indicator", props = { indicator = "underline" } },
			{
				name = "multiple",
				props = function(c)
					return { multiple = true, selected = c.cell("many", { road = true, drift = true }) }
				end,
			},
			{
				name = "controlled open",
				props = function(c)
					return { style = "menu", isPresented = c.cell("pickerOpen", false) }
				end,
			},
			{
				name = "menu: bounded, rich rows",
				props = {
					style = "menu",
					maxHeight = 180,
					options = {
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
				props = {
					style = "cards",
					required = false,
					options = {
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
				props = { style = "radioGroup", indicatorPosition = "trailing" },
				across = false,
			},
			{ name = "vertical", props = { axis = "y" } },
			{ name = "hug", props = { sizing = "hug" } },
			{
				name = "icon only",
				props = {
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
				props = { options = { { value = "a", label = LONG }, { value = "rally", label = "Rally" } } },
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
		base = function(c)
			return { value = c.cell("value", 3), count = 5 }
		end,
		axes = { { key = "starSize", values = { "small", "medium", "large" } } },
		states = {
			{ name = "custom glyphs", props = { glyphs = { filled = "♥", empty = "♡" } } },
			{
				name = "change reported",
				props = function(c)
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
			{ name = "read only", props = { readOnly = true } },
			{
				name = "zero, no zero allowed",
				props = function(c)
					return { value = c.cell("zero", 1), allowZero = false }
				end,
			},
			{ name = "ten stars", props = { count = 10 } },
		},
	},
	Vote = {
		family = "selection",
		alias = "(Facet-only) up/down vote",
		purpose = "Up/down reaction with a summary; the model may refuse a vote.",
		alternatives = "Rating for a scale.",
		scenarios = { "selection_controls" },
		snippet = "UI.Vote { value = vote, onChange = function(v) vote:set(v) end }",
		base = function(c)
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
			{ name = "read only", props = { readOnly = true } },
			{
				name = "diagnostics table",
				props = function(c)
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
		base = function(c)
			return { value = c.cell("value", 3), count = 5 }
		end,
		axes = {
			{
				key = "segment",
				values = { "bar", "glyph", "image" },
				implies = { image = { images = { filled = ART, empty = ART } } },
			},
			{ key = "segmentSize", values = { "small", "medium", "large" }, props = { segment = "glyph" } },
		},
		states = {
			DISABLED,
			{ name = "read only", props = { readOnly = true } },
			{ name = "custom glyphs", props = { segment = "glyph", glyphs = { filled = "●", empty = "○" } } },
			{
				name = "tint pair",
				props = { tint = { filled = Color3.fromRGB(63, 184, 113), empty = Color3.fromRGB(80, 80, 90) } },
			},
			{ name = "no zero", props = { allowZero = false } },
			{
				name = "change reported",
				props = function(c)
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
		valid = function(p)
			return (p.images == nil or p.segment == "image") and not (p.segment == "image" and p.images == nil)
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
			{ name = "icon only (named)", props = { label = "", icon = "checkmark", name = "Verified" } },
			{ name = "success", props = { appearance = "status", status = "success" } },
			{ name = "warning", props = { appearance = "status", status = "warning" } },
			{ name = "error", props = { appearance = "status", status = "error" } },
			{ name = "info", props = { appearance = "status", status = "info" } },
			{ name = "accent", props = { appearance = "status", status = "accent" } },
			{ name = "neutral", props = { appearance = "status", status = "neutral" } },
			{ name = "voice", props = { appearance = "status", status = "voice" } },
			{ name = "contrast", props = { appearance = "status", status = "contrast" } },
			{ name = "icon", props = { icon = "checkmark" } },
			{ name = "trailing icon", props = { icon = "checkmark", iconPosition = "trailing" } },
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
			{ key = "value", values = { 3, 120, "New", true, 0 } },
			{ key = "host", values = { "icon button", "button", "avatar" } },
		},
		states = { { name = "right to left", props = { direction = "rtl" } } },
		make = function(UI, p)
			local host = if p.host == "button"
				then UI.Button({ label = "Inbox" })
				elseif p.host == "avatar" then UI.Avatar({ name = "Ada Quill" })
				else UI.Button({ label = "Inbox", icon = "flag", shape = "circle" })
			return UI.badged(host, p.value, p.direction)
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
			{ name = "diameter 28", props = { diameter = 28 } },
			{ name = "count", props = { count = 7 } },
			{ name = "count over max", props = { count = 150, max = 99 } },
			{ name = "cutout", props = { cutout = true } },
		},
		stateAxis = "status",
	},
	ProgressView = {
		family = "status",
		cellWidth = 240,
		alias = "Progress · Loading",
		purpose = "Determinate or indeterminate progress as a bar, ring or spinner; segments and a damage trail.",
		alternatives = "Skeleton for content that is still loading.",
		scenarios = { "progress_ring" },
		snippet = 'UI.ProgressView { value = 0.4, presentation = "bar" }',
		base = function()
			return { value = 0.4, label = "Uploading", Size = UDim2.fromScale(1, 0) }
		end,
		axes = {
			{
				key = "presentation",
				values = { "bar", "circular", "spinner" },
				implies = { spinner = { value = NONE } },
			},
			{ key = "controlSize", values = { DEFAULT, "xsmall", "compact", "regular", "large" } },
		},
		states = {
			{ name = "indeterminate", props = { value = NONE } },
			{ name = "value shown", props = { showValue = true } },
			{ name = "end label", props = { endLabel = "3 of 7 files" } },
			{ name = "complete", props = { value = 1 } },
			{
				name = "min/max 0–200, formatted",
				props = {
					value = 120,
					min = 0,
					max = 200,
					showValue = true,
					format = function(v)
						return `{v} HP`
					end,
				},
			},
			{ name = "segments 5", props = { segments = 5 } },
			{ name = "thickness 10", props = { thickness = 10 } },
			{ name = "damage trail", props = { trail = { delay = 0.3, duration = 0.6 } } },
			{ name = "ring sizes", props = { presentation = "circular" }, across = "controlSize", matrixOnly = true },
			{
				name = "spinner sizes",
				props = { presentation = "spinner", value = NONE },
				across = "controlSize",
				matrixOnly = true,
			},
			{
				name = "ring diameter 96, value shown",
				props = { presentation = "circular", diameter = 96, showValue = true },
				across = false,
				matrixOnly = true,
			},
		},
		valid = function(p)
			local shape = p.presentation or "bar"
			return not (shape == "spinner" and p.value ~= nil)
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
				implies = { circle = { Size = UDim2.fromOffset(64, 64) }, box = { Size = UDim2.fromOffset(200, 64) } },
			},
			SIZES,
			{ key = "corners", values = { DEFAULT, "square", 4, "control", "panel", "pill" } },
		},
		states = { { name = "3 lines", props = { lines = 3 } } },
	},
	Avatar = {
		family = "status",
		valid = function(p)
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
		make = function(UI, p)
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
			{ name = "diameter 72", props = { diameter = 72, controlSize = NONE } },
			{ name = "localized presence", props = { presence = "online", presenceLabel = "En ligne" } },
			{ name = "no presence mark", props = { presence = "online", presenceMark = false } },
			{ name = "backplate", props = { backplate = true } },
			{ name = "background: accent", props = { background = "accent" } },
			{ name = "background: success", props = { background = "success" } },
			{
				name = "activatable",
				props = function(c)
					return { onActivate = c.log("onActivate") }
				end,
			},
			{
				name = "custom loader + status",
				props = function(c)
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
				props = function(c)
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
			local items = {}
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
			{ name = "diameter 48", props = { diameter = 48 } },
			{ name = "localized overflow", props = { overflowLabel = "et 2 autres" } },
			{
				name = "activatable overflow",
				props = function(c)
					return { onOverflow = c.log("onOverflow") }
				end,
			},
		},
		valid = function(p)
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
		},
		states = {
			{ name = "large icon", props = { iconSize = 32 } },
			{ name = "wide gap", props = { gap = "m" } },
			{ name = "long text", props = { title = LONG } },
			{ name = "strong", props = { textSize = "strong" } },
			{ name = "heading", props = { textSize = "heading" } },

			{ name = "filled icon", props = { icon = "person.fill" } },
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
				props = function(c)
					return { actions = { { id = "install", label = "Install", onActivate = c.log("install") } } }
				end,
			},
		},
		states = {
			{ name = "no icon", props = { icon = false } },
			{ name = "custom icon", props = { icon = "flag" } },
			{
				name = "actions + link",
				props = function(c)
					return {
						link = { label = "Release notes", onActivate = c.log("link") },
						actions = { { id = "install", label = "Install", onActivate = c.log("install") } },
					}
				end,
			},
			{
				name = "dismissable",
				props = function(c)
					return { onDismiss = c.log("onDismiss") }
				end,
			},
			{ name = "long text", props = { message = LONG .. ". " .. LONG } },
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
			{ name = "fit mode (imageProperties)", props = { imageProperties = { ScaleType = Enum.ScaleType.Fit } } },
			{ name = "dimmed", props = { dimmed = true } },
			{
				name = "unavailable + label",
				props = { source = "rbxassetid://999999999999999", failureLabel = "Picture unavailable" },
			},
			{ name = "image key", props = { source = NONE, image = ART } },
			{
				name = "custom placeholder",
				props = function(c)
					return {
						source = "rbxassetid://999999999999998",
						placeholder = function(stateNow)
							return c.UI.Text({
								text = function(use)
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
				props = function(c)
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
				props = function(c)
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
			{ name = "pixelated", props = { resample = "pixelated" } },
			{ name = "tinted", props = { tint = Color3.fromRGB(60, 94, 246) } },
			{ name = "circle", props = { shape = "circle", Size = UDim2.fromOffset(80, 80) }, across = false },
			{
				name = "tiled 40x40",
				props = { scaleMode = "tile", tileSize = { width = 40, height = 40 } },
				across = false,
			},
			{
				name = "nine-slice",
				props = {
					scaleMode = "slice",
					sliceCenter = { x0 = 64, y0 = 64, x1 = 192, y1 = 192 },
					sliceScale = 0.5,
				},
				across = false,
			},
		},
		valid = function(p)
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
		base = function(c)
			return {
				Size = UDim2.fromOffset(240, 135),
				camera = CFrame.lookAt(Vector3.new(4, 3, 6), Vector3.zero),
				content = function(runtime, world, live)
					local part = runtime.constructors.Part({
						Size = Vector3.new(2, 2, 2),
						Color = Color3.fromRGB(60, 94, 246),
						Anchored = true,
					})
					part.Parent = world
					local spin = game:GetService("RunService").Heartbeat:Connect(function(dt)
						if live:peek() then
							part.CFrame *= CFrame.Angles(0, dt, 0)
						end
					end)
					return function()
						spin:Disconnect()
					end
				end,
			}
		end,
		axes = { { key = "fieldOfView", values = { 40, 70 } } },
		states = { { name = "lazy", props = { lazy = true } } },
	},

	Alert = {
		family = "overlays",
		matrix = false,
		alias = "Dialog (confirmation)",
		purpose = "A brief modal decision with one to three role-placed actions.",
		alternatives = "Dialog for richer content; Notice for non-blocking status.",
		scenarios = { "alert" },
		snippet = 'UI.Alert { isPresented = open, title = "Leave?", message = "…", actions = { … } }',
		base = function(c)
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
			{ name = "icon", props = { icon = "status.warning" } },
			{
				name = "custom content",
				props = function(c)
					return {
						content = function()
							return c.UI.Text({ text = "3 laps · Coastal Circuit", role = "secondary" })
						end,
					}
				end,
			},
			{ name = "narrow (maxWidth 280)", props = { maxWidth = 280 } },
			{ name = "roomy padding 24", props = { padding = 24 } },
			{ name = "full screen", props = { surface = "fullScreen" } },
			{ name = "no motion", props = { transition = false } },
			{
				name = "error cell cleared on dismiss",
				props = function(c)
					return { error = c.cell("alertError", "Save failed") }
				end,
			},
			{
				name = "destructive + shortcut",
				props = function(c)
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
			{ name = "long text", props = { message = LONG .. ". " .. LONG } },
			{
				name = "don't ask again",
				props = function(c)
					return { suppression = { isSuppressed = c.cell("suppressed", false), label = "Don't ask again" } }
				end,
			},
		},
		demonstrates = { "isPresented", "item", "presenting" },
		make = function(UI, p, c)
			local form = p.form or "isPresented"
			p.form = nil
			if form == "item" then
				local item = c.Compose.cell(nil)
				p.item = item
				p.title = function(data)
					return `Delete {data.name}?`
				end
				return UI.VStack({
					gap = "xs",
					UI.Button({
						label = "Show for an item",
						onActivate = function()
							item:set({ name = "Coastal Circuit" })
						end,
					}),
					UI.Alert(p),
				})
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
		base = function(c)
			return {
				title = "Leave the lobby?",
				content = function()
					return c.UI.Text({
						text = "Your spot will be given to another player.",
						wrap = true,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					})
				end,
				actions = {
					{ id = "Stay", label = "Stay", role = "cancel", onActivate = c.log("stay") },
					{ id = "Leave", label = "Leave", role = "destructive", onActivate = c.log("leave") },
				},
				closeButton = false,
			}
		end,
		axes = {
			{ key = "width", values = { "automatic", "narrow", "wide" } },
			{ key = "actionLayout", values = { "automatic", "row", "stacked" } },
		},
		states = {
			{ name = "close button", props = { closeButton = true } },

			{
				name = "Apply keeps it open",
				props = function(c)
					return {
						actions = {
							{ id = "Stay", label = "Stay", role = "cancel", onActivate = c.log("stay") },
							{
								id = "Apply",
								label = "Apply",
								keepOpen = true,
								onActivate = c.log("apply (stays open)"),
							},
							{ id = "Leave", label = "Leave", role = "destructive", onActivate = c.log("leave") },
						},
					}
				end,
			},
			{ name = "hero", props = { hero = { image = ART, aspectRatio = 2, scaleMode = "crop" } } },
			{ name = "action label", props = { actionLabel = "Choose carefully: this cannot be undone." } },
			{
				name = "long rich body (selectable)",
				props = function(c)
					return {
						contentSelectable = true,
						content = function()
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
		make = function(UI, p, c)
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
		demonstrates = { "isPresented" },
		matrix = false,
		alias = "Sheet (Root · Header · Content · Actions · FullBleed)",
		purpose = "A draggable panel with detents; bottom, side, centre or adaptive placement.",
		alternatives = "Dialog for a short modal; Popover for anchored content.",
		scenarios = { "sheet" },
		snippet = 'UI.Sheet { title = "Filters", isPresented = open, detent = detent, content = body }',
		base = function(c)
			return {
				title = "Filters",
				detent = c.cell("detent", "medium"),
				detents = { "medium", "large" },
				content = function()
					return c.UI.VStack({
						width = "fill",
						gap = "s",
						c.UI.Toggle({ label = "Only friends", value = c.cell("friends", false) }),
						c.UI.Slider({
							label = "Distance",
							value = c.cell("dist", 5),
							min = 0,
							max = 10,
							Size = UDim2.fromScale(1, 0),
						}),
					})
				end,
				closeButton = false,
			}
		end,
		axes = {
			{ key = "placement", values = { "adaptive", "automatic", "bottom", "side", "center" } },
			{ key = "width", values = { "automatic", "narrow", "wide" } },
			{ key = "dragIndicator", values = { "automatic", "visible", "hidden" } },
		},
		states = {
			{ name = "no interactive dismiss", props = { interactiveDismissDisabled = true } },
			{
				name = "stacked actions",
				props = function(c)
					return {
						actionLayout = "stacked",
						actions = {
							{ id = "Apply", label = "Apply", role = "default", onActivate = c.log("apply") },
							{ id = "Reset", label = "Reset", onActivate = c.log("reset") },
						},
					}
				end,
			},
			{ name = "body pans the sheet", props = { scrollPolicy = "atLargestDetent" } },
			{ name = "close button", props = { closeButton = true } },
			{ name = "close label", props = { closeButton = "Close" } },
			{ name = "no content inset", props = { contentInset = "none" } },
			{ name = "full-bleed hero (sticky)", props = { hero = { image = ART, aspectRatio = 2, sticky = true } } },
			{
				name = "custom header",
				props = function(c)
					return {
						header = function()
							return c.UI.Text({ text = "Custom header", textRole = "heading" })
						end,
					}
				end,
			},
			{ name = "no header", props = { header = false } },
			{
				name = "hug + fraction + fixed detents",
				props = function(c)
					return {
						detents = { "hug", { id = "third", fraction = 0.33 }, { id = "tall", height = 520 } },
						detent = c.cell("hugDetent", "hug"),
					}
				end,
			},
			{ name = "left edge", props = { placement = "side", edge = "left" } },
		},
		valid = function(p)
			return p.edge == nil or p.placement == "side" or p.placement == "adaptive"
		end,
		make = function(UI, p, c)
			return trigger(c, "Show sheet", function(open)
				p.isPresented = open
				return UI.Sheet(p)
			end)
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
		base = function(c)
			local open = c.cell("open", false)
			return {
				isPresented = open,
				onPresentedChange = function(v)
					open:set(v)
				end,
				trigger = c.UI.Button({ label = "About" }),
				content = function()
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
			{ name = "non-modal (no catcher, no Cancel)", props = { modal = false } },
			{ name = "cancel policy none", props = { cancelPolicy = "none" } },
			{
				name = "dismiss reported",
				props = function(c)
					return { onDismiss = c.log("onDismiss") }
				end,
			},
			{ name = "gap 24", props = { gap = 24 } },
			{
				name = "bounded height (scrolls)",
				props = function(c)
					return {
						maxHeight = 120,
						content = function()
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
			{ name = "no tail", props = { tail = false } },
			{ name = "stays a popover on touch", props = { compact = "popover" } },
			{ name = "sheet title (compact touch)", props = { title = "About scoring" } },
			{ name = "cross offset 24", props = { crossOffset = 24 } },
			{
				name = "rect source",
				props = function(c)
					local open = c.cell("open", false)
					return {
						trigger = NONE,
						source = { rect = { x = 600, y = 300, w = 40, h = 40 } },
						isPresented = open,
					}
				end,
			},
		},
		make = function(UI, p, c)
			if p.trigger == nil then
				local open = p.isPresented
				return UI.VStack({
					gap = "xs",
					UI.Button({
						label = "Open at a rect",
						onActivate = function()
							open:set(true)
						end,
					}),
					UI.Popover(p),
				})
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
		base = function(c)
			return {
				title = "New: lap counter",
				content = function()
					return c.UI.Text({ text = "Press Plus to add a lap." })
				end,
				onRetire = c.log("onRetire"),
			}
		end,

		make = function(UI, p, c)
			local anchor = UI.Button({ label = "Plus", onActivate = c.log("plus") })
			p.anchor = anchor
			return UI.VStack({ gap = "xs", padding = { top = 60, bottom = 60 }, anchor, UI.Callout(p) })
		end,
		demonstrates = { "anchor" },
		axes = {
			{ key = "edge", values = { "bottom", "top" } },
			{ key = "align", values = { "leading", "center", "trailing" } },
		},
		states = {
			{ name = "dismiss label", props = { dismissLabel = "Got it!" } },
			{ name = "priority 2", props = { priority = 2 } },
			{
				name = "show / hide reported",
				props = function(c)
					return { onShow = c.log("onShow"), onHide = c.log("onHide") }
				end,
			},
			{ name = "already seen (retired)", props = { seen = true } },
			{ name = "after 2 sessions (not yet)", props = { sessions = 1, afterSessions = 2 } },
			{ name = "feature used (retired)", props = { featureUsed = true } },
			{ name = "steps", props = { steps = { index = 1, count = 3 } } },
			{ name = "close button", props = { closeButton = true } },
			{ name = "media", props = { media = { image = ART, aspectRatio = 2 } } },
			{
				name = "two actions",
				props = function(c)
					return {
						actions = {
							{ id = "Try", label = "Try it", role = "default", onActivate = c.log("try") },
							{ id = "Later", label = "Later", onActivate = c.log("later") },
						},
					}
				end,
			},
			{ name = "no tail", props = { tail = false } },
			{
				name = "controlled presentation",
				props = function(c)
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
		base = function(c)
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
				name = "sidebar adaptable, expanded at ten feet",
				props = function(c)
					return { style = "sidebarAdaptable", sidebarExpanded = c.cell("expanded", true) }
				end,
				across = false,
			},
			DISABLED,
			{ name = "icon only", props = { iconOnly = true } },
			{ name = "text size 12", props = { textSize = 12 } },
			{ name = "sidebar adaptable", props = { style = "sidebarAdaptable", railWidth = 120 }, across = false },
			{ name = "collapsible", props = { style = "collapsible" }, across = false },
			{ name = "retain only the top page", props = { retention = "top" } },
			{ name = "no motion", props = { transition = false } },
			{ name = "slow crossfade", props = { transition = { seconds = 0.6 } } },
			{
				name = "sections + customization",
				props = function(c)
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
			{ name = "shoulders move the content", props = { shoulderNavigation = "content" } },
			{ name = "no scroll/focus restore", props = { restoreScroll = false, restoreFocus = false } },
			{
				name = "change reported",
				props = function(c)
					return { onChange = c.log("onChange") }
				end,
			},
		},
		valid = function(p)
			local placement = p.placement or "automatic"
			return not ((p.style == "sidebarAdaptable" or p.style == "collapsible") and placement ~= "automatic")
				and not (p.sidebarPreference ~= nil and p.style ~= "sidebarAdaptable")
		end,
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
		base = function(c)
			local path = c.cell("path", {})
			return {
				path = path,
				backLabel = "Back",
				Size = UDim2.fromScale(1, 1),
				root = {
					title = "Garage",
					content = function()
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
						content = function(entry)
							return c.UI.Text({ text = `Car details: {entry and entry.value or "?"}` })
						end,
					},
				},
			}
		end,
		axes = {
			{ key = "transition", values = { DEFAULT, false }, matrix = false },
		},
		states = { { name = "crossfade 0.3 s", props = { transition = { seconds = 0.3 } } } },
	},
	NavBar = {
		family = "navigation",
		cellWidth = 360,
		alias = "HeaderBar (Leading · Content · Trailing · Actions)",
		purpose = "A header row with back, title and leading/centre/trailing slots.",
		alternatives = "A plain HStack when there is no navigation.",
		scenarios = { "overlays" },
		snippet = 'UI.NavBar { title = "Garage", onBack = back, trailing = tools }',
		base = function(c)
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
			{ name = "heading title size", props = { titleSize = "heading" } },
			{ name = "wide gap + padding", props = { gap = 24, padding = 16 } },
			{ name = "long title", props = { title = LONG } },
			{ name = "no back", props = { onBack = NONE } },
			{
				name = "leading slot",
				props = function(c)
					return { leading = c.UI.Label({ title = "Garage", icon = "settings", presentation = "iconOnly" }) }
				end,
			},
			{
				name = "centre slot",
				props = function(c)
					return {
						center = c.UI.Picker({
							selected = c.cell("navSeg", "a"),
							style = "segmented",
							options = { { value = "a", label = "Cars" }, { value = "b", label = "Parts" } },
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
		base = function(c)
			local pages = {}
			for _, name in { "Coast", "Canyon", "City" } do
				table.insert(pages, {
					id = name,
					label = name,
					content = function()
						return c.UI.Text({ text = `{name} course` })
					end,
				})
			end
			return { selection = c.cell("page", "Coast"), pages = pages, Size = UDim2.fromScale(1, 1) }
		end,
		axes = {},
		states = {
			{ name = "no summary", props = { summary = false } },
			{ name = "no controls", props = { controls = false } },
			{ name = "no indicators", props = { indicators = false } },
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
		base = function(c)
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
			{ name = "two siblings, two at each end", props = { siblingCount = 2, boundaryCount = 2, pageCount = 20 } },
			DISABLED,
			{ name = "first/last", props = { showFirstLast = true } },
			{ name = "unknown total", props = { pageCount = NONE, hasNext = true, hasPrevious = true } },
			{ name = "no pages", props = { pageCount = 0 } },
			{ name = "diagnostics table", props = { controls = {} } },
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
		base = function(c)
			local current = c.cell("current", "ship")
			local logSelect = c.log("onSelect")
			return {
				steps = {
					{ id = "cart", label = "Cart", state = "complete", navigable = true },
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
			{ name = "list label (narrow)", props = { listLabel = "All steps", Size = UDim2.fromOffset(200, 0) } },
			{ name = "diagnostics table", props = { controls = {} } },
		},
	},
	DisclosureGroup = {
		family = "navigation",
		cellWidth = 280,
		alias = "Accordion (Item · Root) · Outline row",
		purpose = "Shows and hides a section of content under a labelled header.",
		alternatives = "CollapsibleView for a single expandable panel with its own chrome.",
		scenarios = { "containers", "collapsible_view" },
		snippet = 'UI.DisclosureGroup { label = "Race rules", expanded = open, content = body }',

		base = function(c)
			return {
				label = "Race rules",
				expanded = c.cell("expanded", true),
				content = function()
					return c.UI.VStack({
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
					})
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
				props = function(c)
					return { expanded = c.cell("shut", false) }
				end,
			},
			{ name = "description", props = { description = "Three settings" } },
			{ name = "icon", props = { icon = "settings" } },
			{ name = "outline row type + indent", props = { textSize = "label", indent = "m" } },
			{
				name = "toggle reported",
				props = function(c)
					return { onToggle = c.log("onToggle") }
				end,
			},

			{ name = "single-open group", props = { singleOpen = true }, across = false },
		},
		make = function(UI, p, c)
			if not p.singleOpen then
				return UI.DisclosureGroup(p)
			end
			p.singleOpen = nil
			local sections = { "Rules", "Rewards", "Credits" }
			local cells = {}
			for _, name in sections do
				cells[name] = c.cell(`open{name}`, name == "Rules")
			end
			local list: { any } = { width = "fill", gap = "xs" }
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
		base = function(c)
			return {
				label = "Filters",
				expanded = c.cell("expanded", false),
				content = function()
					return c.UI.VStack({
						gap = "s",
						padding = "m",
						c.UI.Text({ text = "Panel content" }),
						c.UI.Button({ Name = "Apply", label = "Apply" }),
					})
				end,
			}
		end,
		axes = { { key = "appearance", values = { "standard", "emphasis", "soft", "utility" } } },
		states = {
			DISABLED,
			{ name = "icon", props = { icon = "settings" } },
			{ name = "dismiss button", props = { dismissButton = true } },
			{ name = "selected", props = { selected = true } },
			{ name = "initial focus: Apply", props = { initialFocus = "Apply" } },
			{
				name = "activation reported",
				props = function(c)
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
		base = function(c)
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
			{ name = "long title", props = { title = LONG } },
			{ name = "square artwork", props = { imageAspectRatio = 1 } },
			{ name = "fit framing", props = { imageFraming = "fit" } },
			{ name = "informational (no body action)", props = { onActivate = NONE } },
			{
				name = "3D artwork",
				props = function(c)
					return {
						artwork = function()
							return c.UI.Stage({ camera = CFrame.lookAt(Vector3.new(4, 3, 6), Vector3.zero) })
						end,
					}
				end,
			},
			{ name = "controls table", props = { controls = {} } },

			{ name = "row of cards", props = { row = true }, across = false, cellWidth = 740 },
		},
		demonstrates = { "browseTarget" },
		make = function(UI, p, c)
			if not p.row then
				return UI.Card(p)
			end
			p.row = nil
			local cards: { any } = {
				gap = "m",
				columns = function(use)
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
		purpose = "A model-backed cell editor with durable drafts and commit validation.",
		alternatives = "TextInput for immediate text changes.",
		scenarios = { "table_virtualized" },
		snippet = 'UI.CellEditor { editor = "text", value = name, draft = draft, onChange = save }',
		base = function(c)
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
			{ name = "pending", props = { busy = true } },
			{
				name = "validation",
				props = {
					validate = function(v)
						return if v == "" then "Enter a name." else nil
					end,
				},
			},
			{
				name = "number",
				props = function(c)
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
				props = function(c)
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
				props = function(c)
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
		base = function(c)
			return {
				from = c.cell("rows", ROWS),
				key = "id",
				columns = {
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
				props = function(c)
					return {
						columns = {
							{
								id = "name",
								label = "Track",
								render = function(current)
									return c.UI.Text({
										text = function(use)
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
			{ name = "tall rows, header 56, gap 4", props = { itemSize = 56, headerHeight = 56, gap = 4 } },
			{
				name = "sorted (controlled)",
				props = function(c)
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
				props = function(c)
					local widths = c.cell("widths", { name = 220, laps = 90 })
					return {
						widths = widths,
						onWidthsChange = function(w)
							widths:set(w)
							c.log("onWidthsChange")()
						end,
						columns = {
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
			{ name = "page scrolls (all rows)", props = { scrolls = false, Size = UDim2.fromScale(1, 0) } },
			{ name = "alternating rows", props = { alternatingRows = true } },
			{
				name = "reorderable (drag label)",
				props = function(c)
					local rows = c.cell("rows", ROWS)
					return {
						reorderable = true,
						movable = function(r)
							return r.id ~= "1"
						end,
						onReorder = c.log("onReorder"),
						dragLabel = function(r)
							return r.name
						end,
						from = rows,
					}
				end,
			},
			{
				name = "reorder + delete (drag, Delete key; Edit on touch/pad)",
				props = function(c)
					local rows = c.cell("editRows", ROWS)
					return {
						from = rows,
						selectionMode = "multiple",
						reorderable = true,
						onReorder = c.log("onReorder"),
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
				props = function(c)
					return {
						selectionMode = "single",
						onActivate = c.log("onActivate"),
						editing = c.cell("tableEditing", true),
					}
				end,
			},
			{
				name = "row actions",
				props = function(c)
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
				props = function(c)
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
			{ name = "no header", props = { header = false } },
			{ name = "windowed, overscan 1", props = { mode = "windowed", overscan = 1 } },
			{ name = "measured rows", props = { measure = true } },
			{ name = "snap to rows", props = { snap = "item" } },
			{ name = "follows the end", props = { follow = "end", followThreshold = 24 } },
			{
				name = "status + controls + focus",
				props = function(c)
					return { status = emptyStatus(c), controls = {}, focus = {} }
				end,
			},
			{ name = "measured map", props = { measured = { ["1"] = 72 } } },
			{ name = "reduced motion", props = { reducedMotion = true } },

			{
				name = "editable cells",
				props = function(c)
					local rows = c.cell("editRows", {
						{ id = "1", name = "Coastal Circuit", laps = 3, night = false, surface = "road" },
						{ id = "2", name = "Canyon Run", laps = 5, night = true, surface = "dirt" },
						{ id = "3", name = "City Loop", laps = 4, night = false, surface = "road" },
					})
					return {
						from = rows,
						columns = {
							{ id = "name", label = "Track", editor = "text" },
							{ id = "laps", label = "Laps", width = 96, editor = "number", min = 1, max = 9, step = 1 },
							{ id = "night", label = "Night", width = 64, editor = "toggle" },
							{
								id = "surface",
								label = "Surface",
								width = 110,
								editor = "menu",
								options = { { value = "road", label = "Road" }, { value = "dirt", label = "Dirt" } },
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
				props = function(c)
					return { from = c.cell("none", {}) }
				end,
			},
		},
	},
	VirtualList = {
		family = "collections",
		demonstrates = { "selectionFrom", "selectionIndicator", "rowActions", "minColumnWidth" },
		cellWidth = 280,
		cellHeight = 220,
		alias = "List",
		purpose = "Windowed rows for large data; selection, reorder, row focus and native scroll.",
		alternatives = "A plain VStack for a few rows.",
		scenarios = { "collection_demo", "card_rail", "collections" },
		snippet = 'UI.VirtualList { from = rows, key = "id", render = function(current) … end }',
		base = function(c)
			return {
				from = c.cell("rows", ROWS),
				key = "id",
				itemSize = 44,
				Size = UDim2.fromScale(1, 1),
				onActivate = function(r)
					c.log("onActivate")(r.name)
				end,
				render = function(current)
					return c.UI.Text({
						text = function(use)
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
			{ name = "copy rows by dragging into this collection", props = transferState },
			{ name = "no reorder autoscroll", props = { reorderable = true, autoscroll = false } },
			{ name = "focus stays on the index", props = { focusPolicy = "index" } },
			{
				name = "cards rail",
				props = { direction = "horizontal", itemSize = "cards", cards = { perView = 2, peek = 24 } },
				across = false,
			},
			{ name = "horizontal", props = { direction = "horizontal", itemSize = 120 } },
			{ name = "measured rows", props = { measure = true } },
			{ name = "gap 8, overscan 3", props = { gap = 8, overscan = 3 } },
			{ name = "follows the end", props = { follow = "end", followThreshold = 24 } },
			{
				name = "selection reported",
				props = function(c)
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
				props = function(c)
					return {
						reorderable = true,
						onReorder = c.log("onReorder"),
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
				props = function(c)
					local rows = c.cell("listEditRows", ROWS)
					return {
						from = rows,
						selectionMode = "multiple",
						reorderable = true,
						onReorder = c.log("onReorder"),
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
				props = function(c)
					return { focus = {}, initialFocus = "2", autoFocus = false, wrapFocus = true }
				end,
			},
			{
				name = "row 3 unselectable, row 4 disabled",
				props = {
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
				props = function(c)
					return { onReachEnd = c.log("onReachEnd") }
				end,
			},
			{
				name = "status + controls",
				props = function(c)
					return { status = emptyStatus(c), controls = {}, maxRetained = 8 }
				end,
			},
			{ name = "measured map", props = { measured = { ["1"] = 72 } } },
			{ name = "reduced motion", props = { reducedMotion = true } },
			{ name = "cross gap 4", props = { crossGap = 4 } },
		},
	},
	VirtualGrid = {
		family = "collections",
		demonstrates = { "selectionFrom", "selectionIndicator", "rowActions", "minColumnWidth" },
		cellWidth = 460,
		cellHeight = 220,
		alias = "Grid (virtualized)",
		purpose = "Windowed grid of cells for large collections.",
		alternatives = "UI.Grid for a few cells.",
		scenarios = { "virtual_grid", "virtual_hgrid", "cards" },
		snippet = 'UI.VirtualGrid { from = games, key = "id", columns = 3, itemSize = 208, render = … }',
		base = function(c)
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
				render = function(current)
					return c.UI.Button({
						label = function(use)
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
			{ name = "copy rows by dragging into this collection", props = transferState },
			{ name = "horizontal", props = { direction = "horizontal", columns = 2, itemSize = 140 }, across = false },
			{ name = "cross gap 16", props = { crossGap = 16 } },
		},
	},
	RowActions = {
		family = "collections",
		demonstrates = { "swipeEnabled", "coordinator" },
		cellWidth = 320,
		alias = "(Facet-only) swipe actions",
		purpose = "Leading/trailing swipe actions on a row, reachable by pointer, touch, keyboard and gamepad.",
		alternatives = "A trailing More Menu button when there is one secondary action.",
		scenarios = { "row_actions" },
		snippet = 'UI.RowActions { content = row, trailing = { { id = "delete", label = "Delete", role = "destructive", onActivate = del } } }',
		base = function(c)
			return {
				content = function()
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
				name = "editing",
				props = function(c)
					return { editing = c.cell("editing", true) }
				end,
			},
			{ name = "no full swipe", props = { fullSwipe = false } },
			{ name = "full swipe trailing only", props = { fullSwipe = { leading = false, trailing = true } } },
			{ name = "action width 120", props = { actionWidth = 120 } },
			{
				name = "open (controlled)",
				props = function(c)
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
				props = function(c)
					return { coordinator = c.cell("coordinator", nil) }
				end,
			},
			DISABLED,
			{ name = "reduced motion", props = { reducedMotion = true } },
		},
	},

	ScrollView = {
		family = "layout",
		alias = "ScrollView",
		purpose = "Native scrolling on one or both axes, with gap, padding, align and distribute.",
		alternatives = "VirtualList for large data.",
		scenarios = { "containers" },
		snippet = 'UI.ScrollView { axis = "y", gap = "s", … }',
		base = function(c)
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
			{ name = "padding m", props = { padding = "m" } },
			{ name = "spread (distribute)", props = { distribute = "spaceBetween" } },
		},
	},
	focusRing = {
		host = "TabView",
		family = "navigation",
		alias = "Focus ring",
		purpose = "One theme focus ring in place of the engine selection glow; it shows after keyboard or gamepad input. app.mount installs it, so press Tab here.",
		snippet = "UI.focusRing(playerGui)",
		base = function()
			return {}
		end,
		make = function(UI)
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
			{ name = "preferred Row 3", props = { preferred = "Row 3" } },
			{
				name = "takes the selection on appear, gives it back",
				props = { focusOnAppear = true, returnFocus = true },
			},
		},
		make = function(UI, p)
			local rows: { any } = { Name = "Sidebar", gap = "xs", width = 140 }
			for index = 1, 4 do
				table.insert(rows, UI.Button({ Name = `Row {index}`, label = `Row {index}`, width = "fill" }))
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
				UI.VStack({
					Name = "Detail",
					gap = "xs",
					UI.Button({ label = "Detail one" }),
					UI.Button({ label = "Detail two" }),
				}),
			})
		end,
	},
	focusQuery = {
		host = "TabView",
		family = "navigation",
		alias = "Focus query",
		purpose = "UI.focusQuery(from) reports what a D-pad or arrow move from a control would select and why "
			.. "(capture, link, beam, stop or none), without moving the selection. Select a control below.",
		snippet = "UI.focusQuery(selected)",
		base = function()
			return {}
		end,
		make = function(UI, _, c)
			local selected = c.Compose.cell(nil)
			local function cell(name: string): any
				local node = UI.Button({ Name = name, label = name })
				node.SelectionGained:Connect(function()
					selected:set(node)
				end)
				return node
			end

			local angle = 0
			local dial = UI.Text({ Name = "Dial", textRole = "label", text = "Dial 0°" })
			UI.adjustable(dial, {
				axis = "horizontal",
				onAdjust = function(direction)
					angle += direction * 15
					dial.Text = `Dial {angle}°`
				end,
			})
			dial.SelectionGained:Connect(function()
				selected:set(dial)
			end)
			local function row(direction: string): any
				return UI.Text({
					Name = direction,
					textRole = "caption",
					text = function(use)
						local from = use(selected)
						if from == nil then
							return `{direction}: —`
						end
						local move = UI.focusQuery(from)[direction]
						return `{direction}: {if move.target then move.target.Name else "—"} ({move.rule})`
					end,
				})
			end
			return UI.HStack({
				gap = "l",
				UI.VStack({
					gap = "xs",
					UI.HStack({ gap = "xs", cell("A1"), cell("A2"), cell("A3") }),
					UI.HStack({ gap = "xs", cell("B1"), dial, cell("B3") }),
					UI.HStack({ gap = "xs", cell("C1"), cell("C2"), cell("C3") }),
				}),
				UI.VStack({ gap = "xs", row("Up"), row("Down"), row("Left"), row("Right") }),
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
		snippet = 'UI.Toast "Saved" { message = "Kart sold", action = { label = "Undo", onActivate = undo } }',
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
		make = function(UI, _, c)
			local shown = c.Compose.cell({})
			local count = 0
			local function add(spec)
				count += 1
				spec.onDismiss = c.log("onDismiss")
				local list = table.clone(shown:peek())
				table.insert(list, { n = count, spec = spec })
				shown:set(list)
			end
			return UI.VStack({
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
						add({ message = "Level up", priority = 2, position = "bottom", width = "hug", fade = true })
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
							content = function()
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
					render = function(entry)
						return UI.Toast(entry:peek().spec)
					end,
				}),
			})
		end,
	},
	draggable = {
		host = "Button",
		family = "collections",
		alias = "Drag source",
		purpose = "Makes any node a drag source: pointer travel, the touch long press, or A / Return on a selected source.",
		alternatives = "Table and list reorder for rows.",
		snippet = 'UI.draggable(card, { payload = "card" })',
		demonstrates = { "payload", "enabled", "armOnTap", "operations", "valid", "onStart", "onEnd" },
		base = function()
			return {}
		end,
		make = function(UI, _, c)
			local card = UI.Button({ label = "Drag me" })
			local slot = UI.Button({ label = "Drop here" })
			UI.draggable(card, {
				payload = "card",
				armOnTap = true,
				enabled = true,
				operations = { "copy" },
				valid = function()
					return card.Parent ~= nil
				end,
				onStart = c.log("onStart"),
				onEnd = c.log("onEnd"),
			})
			UI.dropTarget(slot, {
				operation = "copy",
				onDrop = function(payload, info)
					c.log("onDrop")(payload, info.mode)
				end,
			})
			return UI.HStack({ gap = "l", card, slot })
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
			"accepts",
			"onReject",
			"onEnter",
			"onLeave",
			"focusTarget",
			"onUpdate",
			"operation",
			"passThrough",
		},
		base = function()
			return {}
		end,
		make = function(UI, _, c)
			local card = UI.Button({ label = "Card" })
			local open = UI.Button({ label = "Open slot" })
			local full = UI.Button({ label = "Full slot" })
			UI.draggable(card, { payload = "card" })
			UI.dropTarget(open, {
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
		states = { { name = "repeats when held", props = { repeats = true } } },
		make = function(UI, p, c)
			local angle = 0
			local readout = UI.Text({ text = "0°" })
			local row = UI.HStack({
				gap = "xs",
				UI.Button({ label = "Dial" }),
				readout,
			})
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
		make = function(UI, p, c)
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
		make = function(UI, _, c)
			local hud = UI.VStack({
				gap = "xs",
				UI.Button({ label = "Map" }),
				UI.Button({ label = "Bag" }),
			})
			local responder = UI.responder(hud, { passive = true, gameplayGuard = true, traversalWrap = false })
			return UI.VStack({
				gap = "xs",
				UI.Button({
					label = "Engage",
					onActivate = function()
						responder.engage()
						c.log("engaged")(true)
					end,
				}),
				hud,
			})
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
		states = { { name = "instant", props = { animated = false } } },
		make = function(UI, p)
			local list: { any } = { Name = "List", width = 220, height = 140, gap = "xs" }
			for i = 1, 20 do
				table.insert(list, UI.Text({ text = `Line {i}` }))
			end
			local view = UI.ScrollView(list)
			return UI.VStack({
				gap = "xs",
				UI.Button({
					label = `Scroll to {p.position or "top"}`,
					onActivate = function()
						UI.scrollTo(view, p.position or "top", { animated = p.animated })
					end,
				}),
				view,
			})
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
		states = { { name = "instant", props = { animated = false } } },
		make = function(UI, p)
			local target
			local list: { any } = { width = 220, height = 140, gap = "xs" }
			for i = 1, 20 do
				local line = UI.Text({ text = `Line {i}` })
				if i == (p.target or 5) then
					target = line
				end
				table.insert(list, line)
			end
			return UI.VStack({
				gap = "xs",
				UI.Button({
					label = `Reveal line {p.target or 5}`,
					onActivate = function()
						UI.scrollToVisible(target, nil, { animated = p.animated })
					end,
				}),
				UI.ScrollView(list),
			})
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
				props = { text = LONG, reveal = "auto", Size = UDim2.fromOffset(200, 24) },
			},
			{
				name = "discloses a truncated value",
				props = { text = LONG, disclose = true, Size = UDim2.fromOffset(200, 24) },
			},
			{ name = "accent tint", props = { tint = Color3.fromRGB(60, 94, 246) } },
			{
				name = "centred",
				props = { textAlign = "center", Size = UDim2.fromOffset(220, 0), AutomaticSize = Enum.AutomaticSize.Y },
			},
			{
				name = "wraps",
				props = {
					text = LONG,
					wrap = true,
					Size = UDim2.fromOffset(220, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
				},
			},
			{
				name = "truncate end",
				props = {
					text = LONG,
					truncate = "end",
					Size = UDim2.fromOffset(220, 24),
					AutomaticSize = Enum.AutomaticSize.None,
				},
			},
			{ name = "rich", props = { rich = true, text = "Plain, <b>bold</b> and <i>italic</i>" } },
			{
				name = "at most 2 lines",
				props = { text = LONG .. ". " .. LONG, lines = 2, Size = UDim2.fromOffset(220, 0) },
			},
			{
				name = "truncate middle",
				props = {
					text = "Coastal circuit — practice lap 14",
					truncate = "middle",
					Size = UDim2.fromOffset(160, 0),
				},
			},
			{ name = "size 22 px", props = { textSize = 22, textRole = NONE } },
			{
				name = "fit to box",
				props = { textSize = { fit = { cap = "title", floor = "caption" } }, Size = UDim2.fromOffset(160, 40) },
				across = false,
			},
			{ name = "right to left", props = { text = "مرحبا بالعالم", direction = "rtl" } },
		},
		valid = function(p)
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
			{ name = "vertical (in an HStack)", props = { vertical = true }, across = false },
			{ name = "axis x forced", props = { axis = "x", Size = UDim2.fromOffset(1, 40) } },
		},
		make = function(UI, p)
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
		base = function(c)
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
			{ name = "row gap l", props = { rowGap = "l" } },
			{ name = "cell height 64", props = { cellHeight = 64 } },
			{ name = "square cells", props = { aspectRatio = 1 } },
			{ name = "padding s", props = { padding = "s" } },
			{ name = "width 200, height 160 (extents)", props = { Size = NONE, width = 200, height = 160 } },
			{ name = "column flow", props = { flow = "column" } },
		},
	},
	Path = {
		family = "layout",
		alias = "Path (vector stroke) · Facet.pathShapes",
		purpose = "Strokes normalized points (a ring, an arc, a needle from Facet.pathShapes) in a theme role or tint.",
		alternatives = "ProgressView circular for a progress ring.",
		scenarios = { "progress_ring" },
		snippet = 'UI.Path { points = Facet.pathShapes.ring({ radius = 0.4 }), closed = true, thickness = 4, role = "accent" }',
		base = function(c)
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
				props = function(c)
					return { points = c.Facet.pathShapes.arc(0, 250, { radius = 0.4 }), closed = false }
				end,
			},
			{
				name = "needle at 45°",
				props = function(c)
					return {
						points = c.Facet.pathShapes.needle(45, { innerRadius = 0.1, radius = 0.45 }),
						closed = false,
					}
				end,
			},
			{ name = "tint", props = { tint = Color3.fromRGB(63, 184, 113) } },
		},
	},
	HStack = {
		family = "layout",
		alias = "HStack (row)",
		purpose = "Lays children out in a row; gap, cross-axis align, main-axis distribution and wrapping.",
		alternatives = "VStack for a column; Grid for aligned columns.",
		scenarios = { "flow_wrap" },
		snippet = 'UI.HStack { gap = "s", align = "center", distribute = "spaceBetween", a, b, c }',
		base = function(c)
			return stackDemo(c, { width = 300, height = 80 })
		end,
		axes = { ALIGN, DISTRIBUTE, GAP },
		states = { { name = "wrap (narrow)", props = { wrap = true, width = 120, height = "hug" }, across = false } },
	},
	VStack = {
		family = "layout",
		alias = "VStack (column)",
		purpose = "Lays children out in a column; gap, cross-axis align, main-axis distribution and wrapping.",
		alternatives = "HStack for a row; ScrollView when the column can outgrow its box.",
		scenarios = { "containers" },
		snippet = 'UI.VStack { gap = "s", align = "start", a, b, c }',
		base = function(c)
			return stackDemo(c, { width = 160, height = 240 })
		end,
		axes = { ALIGN, DISTRIBUTE, GAP },
		states = { { name = "wrap (short)", props = { wrap = true, height = 80, width = "hug" }, across = false } },
	},
	ZStack = {
		family = "layout",
		alias = "ZStack (layers)",
		purpose = "Layers children in one box; each layer aligns inside it (AnchorPoint + scale Position).",
		alternatives = "A stack when the children should not overlap.",
		scenarios = { "containers" },
		snippet = 'UI.ZStack { alignH = "end", alignV = "start", plate, badge }',
		base = function(c)
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
		states = { { name = "padding s", props = { padding = "s" } } },
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
		axes = { { key = "minLength", values = { 0, 24, "l" } }, { key = "room", values = { "hug", 360 } } },
		states = {},
		make = function(UI, p, c)
			local room = p.room
			p.room = nil
			return UI.HStack({
				align = "center",
				width = if room == 360 then 360 else "hug",
				UI.Button({ label = "Back", onActivate = c.log("back") }),
				UI.Spacer(p),
				UI.Button({ label = "Done", appearance = "emphasis", onActivate = c.log("done") }),
			})
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
		make = function(UI, p, c)
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
		snippet = 'app.mount(function() return UI.Screen "Main" { UI.Text { … }, UI.ScrollView { UI.fill(), … } } end)',
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
			{ name = "chrome band", props = { chrome = "band" } },
			{ name = "chrome edge", props = { chrome = "edge" } },
			{ name = "gap l", props = { gap = "l" } },
			{ name = "fixed 300×200 (width/height)", props = { width = 300, height = 200 } },
		},

		make = function(UI, p, c)
			local env = UI.environment()
			local facts = c.Compose.formula(function(use)
				local inset = use(env.safeInsets)
				local size = use(env.viewportSize)
				return `Environment: {math.floor(size.X)}×{math.floor(size.Y)} {use(env.sizeClass)}, input {use(
					env.effectiveInput
				)}; ` .. `safe insets top {inset.top} (the top bar) — the ScreenGui keeps the root below it`
			end)
			local rows: { any } = { width = "fill", gap = "xs", UI.fill() }
			for i = 1, 8 do
				table.insert(rows, UI.Text({ text = `Body row {i} — scrolls inside the remaining height` }))
			end
			local plain = { wrap = true, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y }
			table.insert(p, UI.Text(merged(plain, { text = "Screen title (first child)", textRole = "heading" })))
			table.insert(p, UI.Text(merged(plain, { text = facts, textRole = "caption" })))
			table.insert(p, UI.ScrollView(rows))
			table.insert(p, UI.Button({ label = "Continue (last child, stays pinned)", appearance = "emphasis" }))
			local screen = UI.Screen(p)
			screen:AddTag("facet-panel")
			return UI.VStack({
				gap = "xs",
				width = "fill",
				UI.Text(merged(plain, {
					text = "The plate is the Screen's box (it fills this cell as it fills a ScreenGui); its padding is the gap to the plate edge.",
					textRole = "caption",
				})),
				UI.VStack({ width = "fill", height = 260, screen }),
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
		states = { { name = "view fails", props = { fails = true } } },
		make = function(UI, p, c)
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
		cellWidth = 380,
		base = function(c)
			return {
				width = "fill",
				gap = "s",
				c.UI.Button({ label = "Start race", appearance = "emphasis" }),
				c.UI.Button({ label = "Garage" }),
				c.UI.Button({ label = "Leaderboard" }),
				c.UI.Button({ label = "Settings" }),
			}
		end,
		axes = {
			{ key = "width", values = { "fill", 460, 240 } },
			{ key = "axis", values = { DEFAULT, "x", "y" } },
			{ key = "gap", values = { "xs", "s", "l" } },
		},
		states = {
			{ name = "padding s", props = { padding = "s" } },
			{ name = "align center", props = { align = "center" } },
			{ name = "distribute spaceBetween", props = { distribute = "spaceBetween" } },
			{ name = "height 160", props = { height = 160 } },
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
		base = function(c)
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
		states = { { name = "height 32 (too short for any)", props = { height = 32 } } },
	},
	Composition = {
		family = "layout",
		fills = true,
		alias = "Composition (HUD zones)",
		purpose = "A game HUD layout. The framed plate is a small screen holding six UI.Region children: "
			.. "Menu (top-left), Round (top), Weapons (top-right), Strip (Roblox top-bar strip), Ready (bottom) "
			.. "and FPS (bottom-right). When the zones do not fit, the region with the HIGHEST rank number "
			.. "steps down to its shorter form first; a `mayDrop` region then hides. The caption above the "
			.. "plate names the form each region shows right now. A region showing its short form can be "
			.. "tapped: its `expand` opens the full form in place, anchored to it.",
		note = "Controls — room: the plate's width (200 crowds the zones so you can watch them give way); "
			.. "gap: space between regions in one zone; padding: inset from the plate's edges; topbar: "
			.. "put the Strip region in Roblox's real top bar instead of the top zone.",
		alternatives = "A Screen with stacks when nothing competes for the same edge.",
		scenarios = { "hud", "radial_menu" },
		snippet = 'UI.Composition { UI.Region { zone = "topLeft", rank = 1, full, short }, … }',
		cellWidth = 380,
		cellHeight = 300,
		base = function()
			return { topbar = false }
		end,
		axes = {
			{ key = "room", values = { "fill", 300, 200 } },
			{ key = "gap", values = { DEFAULT, "xs", "m" } },
			{ key = "padding", values = { DEFAULT, 0, "l" } },

			{ key = "topbar", values = { false, true }, matrix = false },
		},
		states = {},
		make = function(UI, p, c)
			local room = p.room or "fill"
			p.room = nil
			local forms, names = {}, {}
			local function region(name, zone, rank, mayDrop, ...)
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
						then function()
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
					UI.HStack({ gap = "xs", UI.Badge({ label = "Rifle 24/90" }), UI.Badge({ label = "Pistol 7/21" }) })
				)
			)
			table.insert(p, region("Strip", "topbar", 5, true, UI.Badge({ label = "Top bar strip" })))
			table.insert(
				p,
				region("Ready", "bottom", 1, false, UI.Button({ label = "Ready up", appearance = "emphasis" }))
			)
			table.insert(p, region("Fps", "bottomRight", 4, true, UI.Text({ text = "60 FPS", textRole = "caption" })))
			local composition = UI.Composition(p)
			local plate = UI.VStack({ width = room, height = "fill", composition })
			plate:AddTag("facet-panel")
			return UI.VStack({
				width = "fill",
				height = 260,
				gap = "xs",
				UI.Text({
					text = function(use)
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
		purpose = "One HUD element inside a Composition. The framed plate holds two regions: a fixed rank 1 "
			.. "'Neighbour' at the top, and the region under test, which has a full form and a short form "
			.. "(richest first). The caption reads which form shows. When the short form shows, tap it: "
			.. "`expand` opens the full content in place, anchored to the region.",
		note = "Controls — zone: the edge or corner the region sits in; rank: its priority (1 keeps the full "
			.. "form longest, higher numbers give way first); room: the plate's width (200 crowds it); "
			.. "mayDrop (a state): it may hide entirely when even the short form does not fit. `form` is the "
			.. "cell the composition writes: 1 full, 2 short, 0 hidden. A hidden mayDrop region is revealed "
			.. 'by the zone\'s "…" button; reveal = false (a state) opts out.',
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
				},
			},
			{ key = "rank", values = { 1, 2, 3 } },
			{ key = "room", values = { "fill", 200 } },
		},
		states = {
			{ name = "mayDrop", props = { mayDrop = true } },
			{ name = "noReveal", props = { mayDrop = true, reveal = false } },
		},
		make = function(UI, p, c)
			local form = c.cell("form", 1)
			local room = p.room or "fill"
			local composition = UI.Composition({
				topbar = false,
				UI.Region({
					Name = "Neighbour",
					zone = "top",
					rank = 1,
					UI.Badge({ label = "Neighbour · rank 1 · top" }),
				}),
				UI.Region({
					Name = "UnderTest",
					zone = p.zone,
					rank = p.rank,
					mayDrop = p.mayDrop,
					reveal = p.reveal,
					form = form,
					expand = function()
						return UI.Text({ text = "Region under test — the full form, disclosed in place" })
					end,
					UI.Badge({ label = "Region under test (full form)" }),
					UI.Badge({ label = "Short form" }),
				}),
			})
			local plate = UI.VStack({ width = room, height = "fill", composition })
			plate:AddTag("facet-panel")
			return UI.VStack({
				width = "fill",
				height = 200,
				gap = "xs",
				UI.Text({
					text = function(use)
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
		demonstrates = { "form", "expand" },
	},

	environment = {
		host = "Screen",
		family = "facet",
		alias = "Environment (size class, input, safe area)",
		purpose = "Live readables of the engine facts a screen adapts to: viewport, size/height class, orientation, input classes, display size, safe insets, text size, reduced motion.",
		alternatives = "Observe one container's AbsoluteSize for a local decision.",
		snippet = "local env = UI.environment(); env.sizeClass, env.interactionClasses, …",
		base = function()
			return {}
		end,
		axes = { { key = "source", values = { "viewport", "this box" } } },
		states = {},
		make = function(UI, p, c)
			local text = c.Compose.cell("")
			local label = UI.Text({
				text = text,
				wrap = true,
				Size = UDim2.fromOffset(320, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			})
			local env = if p.source == "this box" then UI.environment(label) else UI.environment()
			c.Compose.watch(function(use)
				local size = use(env.viewportSize)
				local ic = use(env.interactionClasses)
				local inset = use(env.safeInsets)
				text:set(table.concat({
					`viewport {math.floor(size.X)}×{math.floor(size.Y)} ({use(env.viewportWidth)} wide, {use(
						env.viewportHeight
					)} high)`,
					`sizeClass {use(env.sizeClass)} · heightClass {use(env.heightClass)} · {use(env.orientation)} · axis {use(
						env.axis
					)}`,
					`compact {tostring(use(env.isCompact))} · regular {tostring(use(env.isRegular))} · regular+ {tostring(
						use(env.isRegularOrWider)
					)} · wide {tostring(use(env.isWide))} · short {tostring(use(env.isShort))} · tall {tostring(
						use(env.isTall)
					)} · landscape {tostring(use(env.isLandscape))}`,
					`input {ic.primary} (pointer {tostring(ic.pointer)}, touch {tostring(ic.touch)}, gamepad {tostring(
						ic.gamepad
					)}, keyboard {tostring(ic.keyboard)}) · effective {use(env.effectiveInput)}`,
					`display {use(env.displaySize)} · text {use(env.preferredTextSize)} · motion {use(
						env.motionLevel
					)}`,
					`safe insets t{inset.top} l{inset.left} b{inset.bottom} r{inset.right}`,
				}, "\n"))
			end)
			local atLeast = env.atLeast("regular")
			return UI.VStack({
				gap = "xs",
				label,
				UI.Text({
					text = function(use)
						return `atLeast("regular") = {tostring(use(atLeast))}`
					end,
					textRole = "caption",
				}),
			})
		end,
		surface = "UI.environment",
	},
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
			{ name = "occlusion ray", props = { occlusion = true } },
			{ name = "padding 0.5", props = { padding = 0.5 } },
		},
		make = function(UI, p, c)
			local part = workspace:FindFirstChild("LabAnchorPart")
			if part == nil then
				part = Instance.new("Part")
				part.Name = "LabAnchorPart"
				part.Anchored = true
				part.Size = Vector3.new(4, 4, 4)
				part.Position = Vector3.new(0, 4, -20)
				part.Parent = workspace
			end
			local binding = UI.worldAnchor({
				target = part,
				offscreen = p.offscreen,
				occlusion = p.occlusion,
				padding = p.padding,
				camera = workspace.CurrentCamera,
			})
			c.Compose.cleanup(binding.dispose)
			return UI.Text({
				text = function(use)
					local a = use(binding.anchor)
					return `x {math.floor(a.x)} y {math.floor(a.y)} clearance {math.floor(a.clearance or 0)} visible {tostring(
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
		purpose = "Compose's structural operations mount and unmount parts of the tree: a condition, a keyed branch, a keyed list, and an exit phase for leaving nodes.",
		alternatives = "Visible = false when the node must keep its place.",
		snippet = "Compose.show(loaded, content, placeholder) · Compose.switch(mode, { a = …, b = … }) · Compose.keyed { from, key, render } · Compose.presence(open, build, { exit })",
		surface = "Facet.Compose",
		base = function()
			return {}
		end,
		axes = { { key = "structure", values = { "show", "switch", "keyed", "presence" } } },
		states = {},
		make = function(UI, p, c)
			local Compose = c.Compose
			local kind = p.structure or "show"
			if kind == "show" then
				local loaded = Compose.cell(false)
				return UI.VStack({
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
				})
			elseif kind == "switch" then
				local mode = Compose.cell("road")
				return UI.VStack({
					gap = "s",
					UI.Picker({
						selected = mode,
						style = "segmented",
						options = { { value = "road", label = "Road" }, { value = "rally", label = "Rally" } },
					}),
					Compose.switch(mode, {
						road = function()
							return UI.Text({ text = "Smooth tarmac" })
						end,
						rally = function()
							return UI.Badge({ label = "Gravel", appearance = "status", status = "warning" })
						end,
					}),
				})
			elseif kind == "keyed" then
				local items = Compose.cell({ ROWS[1], ROWS[2], ROWS[3] })
				return UI.VStack({
					gap = "xs",
					UI.Button({
						label = "Rotate",
						controlSize = "compact",
						onActivate = function()
							local list = table.clone(items:peek())
							table.insert(list, table.remove(list, 1))
							items:set(list)
						end,
					}),
					Compose.keyed({
						from = items,
						key = function(item)
							return item.id
						end,
						render = function(value, index)
							return UI.Text({
								LayoutOrder = index,
								text = function(use)
									return `{use(value).name} · {use(value).laps} laps`
								end,
							})
						end,
					}),
				})
			end
			local open = Compose.cell(true)
			return UI.VStack({
				gap = "s",
				UI.Toggle({ label = "Shown", value = open }),
				Compose.presence(open, function(phase)
					local fade = c.app.runtime.tween(function(use)
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
			})
		end,
	},
	Motion = {
		facet = true,
		family = "facet",
		alias = "Motion (runtime.tween · runtime.spring)",
		purpose = "Compose motion on any bound property: a tween with easing, or a spring with period and damping; reduced motion is an option.",
		alternatives = "The controls' own motion needs nothing.",
		scenarios = { "component_motion", "with_animation", "time_curves" },
		snippet = "Size = runtime.spring(function(use) return use(open) and 1 or 0 end, { period = 0.3 })",
		surface = "app.runtime.tween / app.runtime.spring",
		base = function()
			return {}
		end,
		axes = { { key = "kind", values = { "tween", "spring" } }, { key = "reducedMotion", values = { false, true } } },
		states = {},
		make = function(UI, p, c)
			local runtime = c.app.runtime
			local at = c.Compose.cell(false)
			local body = function(use)
				return if use(at) then 1 else 0
			end
			local reduced = c.Compose.cell(p.reducedMotion == true)
			local motion = if p.kind == "spring"
				then runtime.spring(body, { period = 0.4, damping = 0.6, reducedMotion = reduced })
				else runtime.tween(
					body,
					{ seconds = 0.4, ease = c.Compose.easing.outQuad, reducedMotion = reduced }
				)
			local dot = UI.Badge({
				label = "●",
				appearance = "status",
				status = "accent",
				Position = function(use)
					return UDim2.new(use(motion) * 0.8, 0, 0, 0)
				end,
			})
			local track = UI.ZStack({ width = 300, height = 40, dot })
			track:AddTag("facet-track")
			return UI.VStack({
				gap = "s",
				UI.Button({
					label = "Move",
					onActivate = function()
						at:set(not at:peek())
					end,
				}),
				track,
			})
		end,
	},
	adaptive = {
		facet = true,
		family = "facet",
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
		make = function(UI, p, c)
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
				Size = UDim2.fromOffset(360, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			})
		end,
	},
	civilDate = {
		facet = true,
		family = "facet",
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
		make = function(UI, p, c)
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
				Size = UDim2.fromOffset(360, 0),
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
		make = function(UI, p, c)
			local grow = p.sizing == "fill"
			local function button(spec)
				if grow then
					table.insert(spec, UI.fill())
				end
				return UI.Button(spec)
			end
			local group: { any } = {
				gap = "s",
				width = if grow then 320 else "hug",
				align = if grow and p.axis == "y" then "stretch" else nil,
				button({ label = "Cancel", onActivate = c.log("cancel") }),
				button({ label = "Save", appearance = "emphasis", onActivate = c.log("save") }),
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
		states = { DISABLED, { name = "hints", props = { hints = true } } },
		make = function(UI, p, c)
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
		states = { DISABLED, { name = "hints", props = { hints = true } } },
		make = function(UI, p, c)
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
		make = function(UI, p, c)
			local chips: { any } = { gap = "s" }
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
		make = function(UI, p, c)
			local row: { any } = { gap = "xs" }
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
			return UI.NavBar({ title = "Garage", trailing = UI.HStack(row), Size = UDim2.fromScale(1, 0) })
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
		make = function(UI, p, c)
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
		states = { { name = "one sentence", props = { plain = true }, across = false } },
		make = function(UI, p, c)
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
		make = function(UI, p, c)
			local query = c.cell("query", "")
			local function matches(use, row): boolean
				local q = string.lower(use(query))
				return q == "" or string.find(string.lower(row.name), q, 1, true) ~= nil
			end

			local list: { any } = { width = "fill", gap = "xs" }
			for _, row in ROWS do
				table.insert(
					list,
					UI.Text({
						text = `{row.name} · {row.laps} laps`,
						Visible = function(use)
							return matches(use, row)
						end,
					})
				)
			end
			return UI.VStack({
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
				c.Compose.show(function(use)
					for _, row in ROWS do
						if matches(use, row) then
							return false
						end
					end
					return true
				end, function()
					return UI.Text({ text = "No tracks match", role = "secondary" })
				end),
			})
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
		make = function(UI, p, c)
			return UI.VStack({
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
			})
		end,
	},
}

for _, name in
	{ "Screen", "VStack", "HStack", "ZStack", "ScrollView", "Grid", "AdaptiveStack", "ViewThatFits", "ErrorBoundary" }
do
	table.insert(PAGE_DATA[name].states, {
		name = "width 480 capped at 280",
		props = { width = 480, maxWidth = 280, Size = NONE },
	})
end

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
