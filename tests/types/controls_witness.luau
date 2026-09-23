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
	return UI.Label({ label = "Content" })
end
local function guiContent(): GuiObject
	return UI.Label({ label = "Content" })
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
local input: TextBox = UI.TextInput({
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
local label: GuiObject = UI.Label({ label = text })
local badgeProps: Facet.BadgeProps = { label = "Ready", status = "success" :: "success" }
local badge: GuiObject = UI.Badge(badgeProps)
local statusProps: Facet.StatusIndicatorProps = { status = "success" :: "success" }
local status: GuiObject = UI.StatusIndicator(statusProps)
local progress: GuiObject = UI.ProgressView({ value = value, min = 0, max = 1 })
local skeletonProps: Facet.SkeletonProps = { form = "line" :: "line" }
local skeleton: GuiObject = UI.Skeleton(skeletonProps)
local image: GuiObject = UI.AsyncImage({ image = "rbxassetid://123" })
local avatarProps: Facet.AvatarProps = { name = "Alder", presence = "online" :: "online" }
local avatar: GuiObject = UI.Avatar(avatarProps)
local avatars: GuiObject = UI.AvatarGroup({ items = { { id = "a", name = "Alder" } } })
local stage: ViewportFrame = UI.Stage({ fieldOfView = 60 })
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
		return UI.Label({
			label = function(use: Use): string
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
	progress,
	skeleton,
	image,
	avatar,
	avatars,
	stage,
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
	collapsible,
	callout,
	list,
	grid,
	tableView,
	actions,
}
return mounted
