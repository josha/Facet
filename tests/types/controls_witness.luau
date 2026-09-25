--!strict
local Facet = require("../../src")
local Compose = Facet.Compose
type Use = <T>(Facet.Readable<T>) -> T
local runtime = Facet.Roblox.createRuntime()
local UI = Facet.controls(runtime)
local enabled = Compose.cell(true)
local text = Compose.cell("Amber")
local value = Compose.cell(0.5)
local selected = Compose.cell("home")
local expanded = Compose.cell(false)
local function content(): Instance
	return UI.Text({ text = "Content" })
end
local function guiContent(): GuiObject
	return UI.Text({ text = "Content" })
end
local function nothing() end
local button: TextButton = UI.Button({
	label = text,
	enabled = enabled,
	Size = UDim2.fromOffset(200, 44),
	Visible = function(use: Use): boolean
		return use(enabled)
	end,
	onActivate = nothing,
})
local named: TextButton = UI.Button("Save")({ label = "Save", onActivate = nothing })
local toggle: TextButton = UI.Toggle({
	value = enabled,
	onChange = function(nextValue: boolean)
		enabled:set(nextValue)
	end,
})
local input: TextBox | Frame = UI.TextInput({
	value = text,
	onChange = function(nextValue: string)
		text:set(nextValue)
	end,
	onCommit = function(nextValue: string, reason: "submit" | "focusLost")
		text:set(nextValue .. reason)
	end,
})
local slider: Frame = UI.Slider({
	value = value,
	min = 0,
	max = 1,
	onChange = function(nextValue: number)
		value:set(nextValue)
	end,
})
local stepper: Frame = UI.Stepper({ value = value, min = 0, max = 10 })
local rating: TextButton = UI.Rating({ value = value })
local level: TextButton = UI.LevelPicker({ value = value })
local chip: GuiObject = UI.Chip({ label = "Amber", selected = enabled })
local shortcut: GuiObject = UI.ShortcutHint({ keys = { { "Ctrl", "K" } } })
local label: GuiObject = UI.Text({ text = text })
local textProps: Facet.TextProps =
	{ text = "Ready", textSize = "caption" :: "caption", role = "secondary" :: "secondary" }
local sized: GuiObject = UI.Text(textProps)
local labelProps: Facet.LabelProps =
	{ title = text, icon = "checkmark", presentation = "iconOnly" :: "iconOnly", iconSize = 20 }
local titled: GuiObject = UI.Label(labelProps)
local imageProps: Facet.ImageProps = {
	image = "rbxassetid://1",
	scaleMode = "tile" :: "tile",
	tileSize = { width = 16, height = 16 },
	resample = "pixelated" :: "pixelated",
}
local picture: GuiObject = UI.Image(imageProps)
local badgeProps: Facet.BadgeProps = { label = "Ready", status = "success" :: "success" }
local badge: GuiObject = UI.Badge(badgeProps)
local statusProps: Facet.StatusIndicatorProps = { status = "success" :: "success" }
local status: GuiObject = UI.StatusIndicator(statusProps)
local pathProps: Facet.PathProps = { points = Facet.pathShapes.arc(0, 90), role = "accent" :: "accent", thickness = 2 }
local path: Frame = UI.Path(pathProps)
local escaped: string = Facet.richText.escape("<b>")
local progress: GuiObject = UI.ProgressView({ value = value, min = 0, max = 1 })
local skeletonProps: Facet.SkeletonProps = { form = "line" :: "line" }
local skeleton: GuiObject = UI.Skeleton(skeletonProps)
local image: GuiObject = UI.AsyncImage({ image = "rbxassetid://123" })
local avatarProps: Facet.AvatarProps = { name = "Alder", presence = "online" :: "online" }
local avatar: GuiObject = UI.Avatar(avatarProps)
local avatars: GuiObject = UI.AvatarGroup({ items = { { id = "a", name = "Alder" } } })
local stage: ViewportFrame = UI.Stage({ fieldOfView = 60 })
local pageCell = Compose.cell(1)
local paginationProps: Facet.PaginationSpec = {
	page = pageCell,
	pageCount = 12,
	form = "numbers" :: "numbers",
	onChange = function(nextPage: number)
		pageCell:set(nextPage)
	end,
}
local pagination: Frame = UI.Pagination(paginationProps)
local stepCell = Compose.cell("a")
local stepList: { Facet.Step } = { { id = "a", label = "A", navigable = true }, { id = "b", label = "B" } }
local stepProps: Facet.StepIndicatorSpec = {
	steps = stepList,
	current = function(use: Use): string?
		return use(stepCell)
	end,
	onSelect = function(id: string)
		stepCell:set(id)
	end,
}
local stepIndicator: Frame = UI.StepIndicator(stepProps)
type VoteValue = "up" | "down" | "none"
local initialVote: VoteValue = "none"
local voteCell: Facet.Cell<VoteValue> = Compose.cell(initialVote)
local voteProps: Facet.VoteSpec = {
	value = voteCell,
	summary = "92% liked",
	onChange = function(nextValue: VoteValue)
		voteCell:set(nextValue)
	end,
}
local vote: Frame = UI.Vote(voteProps)
local cardControls: Facet.CardControls = {}
local cardProps: Facet.CardSpec = {
	image = "rbxassetid://1",
	title = text,
	caption = "Friends playing",
	onActivate = nothing,
	primaryAction = { label = "Play", onActivate = nothing },
	menu = { items = { { id = "hide", label = "Not interested", onSelect = nothing } } },
	controls = cardControls,
}
local card: Frame = UI.Card(cardProps)
local sealed: Frame = UI.badged(UI.Button({ label = "Inbox" }), 3)
local raceDay = Compose.cell({ year = 2026, month = 10, day = 4 } :: Facet.CivilDate?)
local datePicker: GuiObject = UI.DateTimePicker({
	label = "Race day",
	value = raceDay,
	onChange = function(next: Facet.CivilDate?)
		raceDay:set(next)
	end,
	min = { year = 2026, month = 1, day = 1 },
})
local startPaint: Color3? = Color3.fromRGB(230, 57, 70)
local paint: Facet.Cell<Color3?> = Compose.cell(startPaint)
local colorProps: Facet.ColorPickerProps = {
	label = "Kart paint",
	value = paint,
	onChange = function(next: Color3)
		paint:set(next)
	end,
}
local colorPicker: Frame = UI.ColorPicker(colorProps)
local civilDay: Facet.CivilDate? = Facet.civilDate.parse("09/03/2026")
local dialogOpen = Compose.cell(false)
local dialogProps: Facet.DialogSpec = {
	isPresented = dialogOpen,
	onPresentedChange = function(nextValue: boolean)
		dialogOpen:set(nextValue)
	end,
	title = text,
	content = content,
	actions = { { id = "Leave", label = "Leave", role = "destructive" :: "destructive", onActivate = nothing } },
	width = "narrow" :: "narrow",
}
local dialog: Frame = UI.Dialog(dialogProps)
local popoverOpen = Compose.cell(false)
local popoverProps: Facet.PopoverSpec = {
	isPresented = popoverOpen,
	onPresentedChange = function(nextValue: boolean)
		popoverOpen:set(nextValue)
	end,
	source = { rect = { x = 0, y = 0, w = 40, h = 40 } },
	edge = "trailing" :: "trailing",
	content = content,
}
local popover: GuiObject = UI.Popover(popoverProps)
local noticeProps: Facet.NoticeSpec = {
	message = text,
	severity = "warning" :: "warning",
	placement = "affixed" :: "affixed",
	onDismiss = nothing,
}
local notice: Frame = UI.Notice(noticeProps)
local navBarProps: Facet.NavBarSpec = { title = text, onBack = nothing, backLabel = "Back" }
local navBar: Frame = UI.NavBar(navBarProps)
local snackOpen = Compose.cell(false)
local snackbarProps: Facet.SnackbarSpec = {
	isPresented = snackOpen,
	message = text,
	duration = 4,
	action = { label = "Undo", onActivate = nothing },
	onPresentedChange = function(nextValue: boolean)
		snackOpen:set(nextValue)
	end,
}
local snackbar: Frame = UI.Snackbar(snackbarProps)
local items = { { id = "save", label = "Save", onSelect = nothing } }
local menu: GuiObject = UI.Menu({ items = items })
local split: GuiObject = UI.SplitButton({ label = "Save", onActivate = nothing, items = items })
local picker: GuiObject = UI.Picker({ selected = selected, options = { { value = "home", label = "Home" } } })
local combo: GuiObject = UI.ComboBox({
	value = selected,
	text = text,
	options = { { value = "home", label = "Home" } },
	acceptCustom = function(candidate: string): (boolean, string?)
		return #candidate > 0, nil
	end,
})
local tabs: GuiObject =
	UI.TabView({ selection = selected, tabs = { { id = "home", label = "Home", content = content } } })
local pages: GuiObject = UI.PageView({ selection = selected, pages = { { id = "home", content = content } } })
local stack: GuiObject = UI.NavigationStack({
	path = Compose.cell({} :: { { id: string, value: string? } }),
	root = { title = "Home", content = content },
	destinations = {},
})
local radial: GuiObject = UI.RadialMenu({ items = items, holdAction = Instance.new("InputAction") })
local nestedRadial: GuiObject = UI.RadialMenu({ items = require("./radial_witness") })
local alert: GuiObject = UI.Alert({ isPresented = expanded, title = "Save", actions = { { id = "ok", label = "OK" } } })
local sheet: GuiObject = UI.Sheet({ isPresented = expanded, detent = Compose.cell("large"), content = content })
local disclosure: GuiObject = UI.DisclosureGroup({ expanded = expanded, content = content })
local outline: GuiObject = UI.DisclosureGroup({
	expanded = expanded,
	content = content,
	appearance = "outline" :: "outline",
	textSize = "label",
	indent = "m" :: "m",
})
local sideSheet: GuiObject = UI.Sheet({
	isPresented = expanded,
	detent = Compose.cell("large"),
	content = content,
	placement = "adaptive" :: "adaptive",
})
local compactTabs: GuiObject = UI.TabView({
	selection = selected,
	controlSize = "xsmall" :: "xsmall",
	tabs = { { id = "home", label = "Home", content = content } },
})
local toolbarPicker: GuiObject = UI.Picker({
	selected = selected,
	style = "menu" :: "menu",
	label = "Motion",
	valueAlignment = "start" :: "start",
	sizing = "hug" :: "hug",
	options = { { value = "home", label = "Home" } },
})
local collapsible: GuiObject = UI.CollapsibleView({ expanded = expanded, content = content })
local calloutAnchor: GuiObject = button
local callout: GuiObject = UI.Callout({ anchor = calloutAnchor, content = content, onRetire = nothing })
local rows = Compose.cell({ { id = "a", title = "Amber" } })
local list: ScrollingFrame = UI.VirtualList({
	from = rows,
	key = function(row: { id: string, title: string }): string
		return row.id
	end,
	render = function(current: Facet.Readable<{ id: string, title: string }>): GuiObject
		return UI.Text({
			text = function(use: Use): string
				return use(current).title
			end,
		})
	end,
})
local grid: ScrollingFrame = UI.VirtualGrid({ from = Compose.cell({ "Amber" }), render = guiContent, columns = 2 })
local tableView: GuiObject = UI.Table({
	from = rows,
	key = function(row: { id: string, title: string }): string
		return row.id
	end,
	columns = {
		{
			id = "title",
			label = "Title",
			value = function(row: { id: string, title: string }): string
				return row.title
			end,
		},
	},
})
local fieldList: ScrollingFrame = UI.VirtualList({ from = rows, key = "id", render = guiContent })
local fieldTable: GuiObject = UI.Table({
	from = rows,
	key = "id",
	columns = {
		{
			id = "title",
			label = "Title",
			value = function(row: { id: string, title: string }): string
				return row.title
			end,
		},
	},
})
local actions: GuiObject =
	UI.RowActions({ content = guiContent, trailing = { { id = "save", label = "Save", onActivate = nothing } } })
local mounted: { GuiObject } = {
	button,
	named,
	toggle,
	input,
	slider,
	stepper,
	rating,
	level,
	chip,
	shortcut,
	label,
	badge,
	status,
	path,
	progress,
	skeleton,
	image,
	avatar,
	avatars,
	stage,
	pagination,
	stepIndicator,
	vote,
	card,
	sealed,
	datePicker,
	colorPicker,
	dialog,
	popover,
	notice,
	navBar,
	snackbar,
	menu,
	split,
	picker,
	combo,
	tabs,
	pages,
	stack,
	radial,
	nestedRadial,
	alert,
	sheet,
	disclosure,
	outline,
	sideSheet,
	compactTabs,
	toolbarPicker,
	collapsible,
	callout,
	list,
	grid,
	fieldList,
	fieldTable,
	tableView,
	actions,
}
local _civil = civilDay
local _escaped = escaped
return mounted
