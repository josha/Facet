--!strict

local UI = require "./ui"

local Compose = require "../core"
local Design = require "../design"

export type LibraryPanel = {
	root: Compose.Node,
	filter: (text: string) -> (),
	dispose: () -> (),
}

return function(ui: UI.UI)
	local Theme = require "./theme"(ui)
	local color = Theme.color
	local size = Theme.size

	return function(session: Design.Session, parent: Compose.Node): LibraryPanel
		local library = session.library
		local connections: { UI.Connection } = {}
		local root = Theme.frame "DesignLibrary"
		ui.set(root, "Size", ui.values.udim2(1, 0, 1, 0))
		ui.set(root, "Parent", parent)

		local search = ui.new "TextBox"
		ui.set(search, "Name", "Search")
		ui.set(search, "Position", ui.values.udim2(0, 8, 0, 4))
		ui.set(search, "Size", ui.values.udim2(1, -16, 0, size.row))
		ui.set(search, "BackgroundColor3", color.field)
		ui.set(search, "BorderSizePixel", 0)
		ui.set(search, "Text", "")
		ui.set(search, "PlaceholderText", "Search")
		ui.set(search, "PlaceholderColor3", color.tertiary)
		ui.set(search, "TextColor3", color.text)
		ui.set(search, "TextSize", size.text)
		ui.set(search, "FontFace", Theme.font.medium)
		ui.set(search, "ClearTextOnFocus", false)
		ui.set(search, "TextXAlignment", ui.values.enum("TextXAlignment", "Left"))
		Theme.corner(search, 4)
		Theme.pad(search, 8)
		ui.set(search, "Parent", root)

		local scroller = Theme.scroller "Kinds"
		ui.set(scroller, "Position", ui.values.udim2(0, 0, 0, size.row + 8))
		ui.set(scroller, "Size", ui.values.udim2(1, 0, 1, -(size.row + 8)))
		Theme.list(scroller, ui.values.enum("FillDirection", "Vertical"), 1)
		Theme.pad(scroller, 8, 8, 4, 8)
		ui.set(scroller, "Parent", root)

		local groups: { [string]: { string } } = {}
		local order: { string } = {}
		for name, kind in library.kinds do
			local category = kind.category or "Library"
			local members = groups[category]
			if members == nil then
				members = {}
				groups[category] = members
				table.insert(order, category)
			end
			table.insert(members, name)
		end
		local preferred = library.categories or {}
		table.sort(order, function(left: string, right: string): boolean
			local a, b = table.find(preferred, left), table.find(preferred, right)
			if a and b then
				return a < b
			elseif a or b then
				return a ~= nil
			end
			return left < right
		end)

		type Entry = { name: string, button: Compose.Node, header: Compose.Node }
		local entries: { Entry } = {}
		local headers: { [string]: Compose.Node } = {}
		local layout = 0
		for _, category in order do
			local members = groups[category]
			table.sort(members)
			layout += 1
			local header = Theme.label(category, color.tertiary, size.small, Theme.font.bold)
			ui.set(header, "Name", category)
			ui.set(header, "Size", ui.values.udim2(1, 0, 0, size.row))
			ui.set(header, "LayoutOrder", layout)
			ui.set(header, "Parent", scroller)
			headers[category] = header
			for _, name in members do
				layout += 1
				local button = ui.new "TextButton"
				ui.set(button, "Name", name)
				ui.set(button, "Size", ui.values.udim2(1, 0, 0, size.row))
				ui.set(button, "AutoButtonColor", false)
				ui.set(button, "BorderSizePixel", 0)
				ui.set(button, "BackgroundTransparency", 1)
				ui.set(button, "BackgroundColor3", color.hover)
				ui.set(button, "Text", "")
				ui.set(button, "LayoutOrder", layout)
				Theme.corner(button, 4)
				local glyph = Theme.label(Theme.glyph[name] or "◇", color.tertiary, size.small, Theme.font.bold)
				ui.set(glyph, "Name", "Glyph")
				ui.set(glyph, "Size", ui.values.udim2(0, 16, 1, 0))
				ui.set(glyph, "TextXAlignment", ui.values.enum("TextXAlignment", "Center"))
				ui.set(glyph, "Parent", button)
				local title = Theme.label(name, color.secondary, size.text)
				ui.set(title, "Name", "Title")
				ui.set(title, "Position", ui.values.udim2(0, 22, 0, 0))
				ui.set(title, "Size", ui.values.udim2(1, -22, 1, 0))
				ui.set(title, "Parent", button)
				ui.set(button, "Parent", scroller)
				for _, connection in Theme.hover(button, color.panel, color.hover, 1) do
					table.insert(connections, connection)
				end
				table.insert(
					connections,
					ui.connect(button, "Activated", function()
						session.insert(name)
					end)
				)
				table.insert(entries, { name = name, button = button, header = header })
			end
		end

		local function filter(text: string)
			local needle = string.lower(text)
			local shown: { [Compose.Node]: boolean } = {}
			for _, entry in entries do
				local visible = needle == "" or string.find(string.lower(entry.name), needle, 1, true) ~= nil
				ui.set(entry.button, "Visible", visible)
				if visible then
					shown[entry.header] = true
				end
			end
			for _, header in headers do
				ui.set(header, "Visible", shown[header] == true)
			end
		end

		table.insert(
			connections,
			ui.changed(search, "Text", function()
				filter(ui.text(search, "Text"))
			end)
		)

		return {
			root = root,
			filter = filter,
			dispose = function()
				for _, connection in connections do
					connection:Disconnect()
				end
				table.clear(connections)
				ui.destroy(root)
			end,
		}
	end
end
