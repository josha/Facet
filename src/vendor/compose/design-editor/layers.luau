--!strict

local UI = require "./ui"

local Compose = require "../core"
local Design = require "../design"

export type Layers = {
	root: Compose.Node,
	dispose: () -> (),
}

export type Options = {
	indent: number?,
}

return function(ui: UI.UI)
	local Theme = require "./theme"(ui)
	local color = Theme.color
	local size = Theme.size

	type Row = { button: Compose.Node, glyph: Compose.Node, name: Compose.Node }

	local function row(id: string): Row
		local button = ui.new "TextButton"
		ui.set(button, "Name", id)
		ui.set(button, "Size", ui.values.udim2(1, 0, 0, size.row))
		ui.set(button, "AutoButtonColor", false)
		ui.set(button, "BorderSizePixel", 0)
		ui.set(button, "BackgroundTransparency", 1)
		ui.set(button, "BackgroundColor3", color.hover)
		ui.set(button, "Text", "")
		Theme.corner(button, 4)
		local glyph = Theme.label("", color.tertiary, size.small, Theme.font.bold)
		ui.set(glyph, "Name", "Glyph")
		ui.set(glyph, "Size", ui.values.udim2(0, 16, 1, 0))
		ui.set(glyph, "TextXAlignment", ui.values.enum("TextXAlignment", "Center"))
		ui.set(glyph, "Parent", button)
		local name = Theme.label("", color.secondary, size.text)
		ui.set(name, "Name", "Title")
		ui.set(name, "Position", ui.values.udim2(0, 22, 0, 0))
		ui.set(name, "Size", ui.values.udim2(1, -22, 1, 0))
		ui.set(name, "Parent", button)
		return { button = button, glyph = glyph, name = name }
	end

	return function(session: Design.Session, parent: Compose.Node, options: Options?): Layers
		local settings: Options = options or {}
		local indent = settings.indent or 16
		local scroller = Theme.scroller "DesignLayers"
		ui.set(scroller, "Size", ui.values.udim2(1, 0, 1, 0))
		Theme.list(scroller, ui.values.enum("FillDirection", "Vertical"), 1)
		Theme.pad(scroller, 8, 8, 4, 8)
		ui.set(scroller, "Parent", parent)
		local rows: { [string]: Row } = {}
		local UserInputService = ui.service "UserInputService"
		local indicator = Theme.frame("DropIndicator", color.accent)
		ui.set(indicator, "Size", ui.values.udim2(1, -16, 0, 2))
		ui.set(indicator, "Visible", false)
		ui.set(indicator, "ZIndex", 10)
		ui.set(indicator, "Parent", parent)
		type Drop = { destination: string, before: number?, into: boolean }
		type Drag = { id: string, start: UI.Point, active: boolean, drop: Drop? }
		local dragging: Drag? = nil
		local function dropAt(point: UI.Point, moving: string): (Drop?, Row?)
			local value = session.document:peek()
			for id, entry in rows do
				local at, extent = ui.xy(entry.button, "AbsolutePosition"), ui.xy(entry.button, "AbsoluteSize")
				if point.Y >= at.Y and point.Y < at.Y + extent.Y then
					local node, parentNode, index = Design.document.find(value.root, id)
					local movingNode = Design.document.find(value.root, moving)
					if node == nil or movingNode == nil or Design.document.find(movingNode, id) then
						return nil, nil
					end
					local fraction = (point.Y - at.Y) / extent.Y
					local container = session.library.kinds[node.kind].children == "list"
					if parentNode == nil or (container and fraction > 0.25 and fraction < 0.75) then
						return if container then { destination = id, before = nil, into = true } else nil, entry
					end
					local before = if fraction <= 0.5 then index else (index or 0) + 1
					local _, from, origin = Design.document.find(value.root, moving)
					if from == parentNode and origin and before and origin < before then
						before -= 1
					end
					return { destination = parentNode.id, before = before, into = false }, entry
				end
			end
			return nil, nil
		end
		local function showDrop(drop: Drop?, entry: Row?, point: UI.Point)
			ui.set(indicator, "Visible", false)
			if drop == nil or entry == nil then
				return
			end
			local origin = ui.xy(parent, "AbsolutePosition")
			local at, extent = ui.xy(entry.button, "AbsolutePosition"), ui.xy(entry.button, "AbsoluteSize")
			if drop.into then
				ui.set(indicator, "Position", ui.values.udim2(0, at.X - origin.X, 0, at.Y - origin.Y))
				ui.set(indicator, "Size", ui.values.udim2(0, extent.X, 0, extent.Y))
				ui.set(indicator, "BackgroundTransparency", 0.8)
			else
				local fraction = (point.Y - at.Y) / extent.Y
				local y = if fraction <= 0.5 then at.Y else at.Y + extent.Y
				ui.set(indicator, "Position", ui.values.udim2(0, at.X - origin.X, 0, y - origin.Y - 1))
				ui.set(indicator, "Size", ui.values.udim2(0, extent.X, 0, 2))
				ui.set(indicator, "BackgroundTransparency", 0)
			end
			ui.set(indicator, "Visible", true)
		end
		local connections: { UI.Connection } = {}
		local function clear()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			for _, entry in rows do
				ui.destroy(entry.button)
			end
			table.clear(rows)
		end
		local function paint(selected: string, hovered: string?)
			for id, entry in rows do
				local active = id == selected
				ui.set(entry.button, "BackgroundColor3", if active then color.accentSoft else color.hover)
				ui.set(entry.button, "BackgroundTransparency", if active then 0 elseif id == hovered then 0.4 else 1)
				ui.set(entry.name, "TextColor3", if active then color.text else color.secondary)
				ui.set(entry.name, "FontFace", if active then Theme.font.bold else Theme.font.medium)
				ui.set(entry.glyph, "TextColor3", if active then color.accent else color.tertiary)
			end
		end
		local root = Compose.createRootOwner(function()
			Compose.watch(function(use: Compose.Use)
				local value = use(session.document)
				clear()
				for order, entry in Design.document.nodes(value.root) do
					local node = entry.node
					local created = row(node.id)
					ui.set(created.button, "LayoutOrder", order)
					ui.set(created.glyph, "Text", Theme.glyph[node.kind] or "◇")
					ui.set(created.name, "Text", node.name)
					local padding = ui.new "UIPadding"
					ui.set(padding, "PaddingLeft", ui.values.udim(0, 6 + entry.depth * indent))
					ui.set(padding, "PaddingRight", ui.values.udim(0, 6))
					ui.set(padding, "Parent", created.button)
					local id = node.id
					table.insert(
						connections,
						ui.connect(created.button, "Activated", function()
							session.select(id)
						end)
					)
					table.insert(
						connections,
						ui.connect(created.button, "InputBegan", function(input: Compose.Node)
							if
								ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1")
								and node.id ~= value.root.id
							then
								dragging = { id = id, start = Theme.point(input), active = false, drop = nil }
							end
						end)
					)
					table.insert(
						connections,
						ui.connect(created.button, "MouseEnter", function()
							session.hovered:set(id)
						end)
					)
					table.insert(
						connections,
						ui.connect(created.button, "MouseLeave", function()
							if session.hovered:peek() == id then
								session.hovered:set(nil)
							end
						end)
					)
					rows[id] = created
					ui.set(created.button, "Parent", scroller)
				end
				paint(session.selected:peek(), session.hovered:peek())
			end)
			Compose.watch(function(use: Compose.Use)
				use(session.document)
				paint(use(session.selected), use(session.hovered))
			end)
		end, ui.runtime.reactor)
		local release = Compose.owner.own(ui.owner, root.dispose)
		local moved = ui.connect(UserInputService, "InputChanged", function(input: Compose.Node)
			local drag = dragging
			if drag == nil or ui.get(input, "UserInputType") ~= ui.values.enum("UserInputType", "MouseMovement") then
				return
			end
			local point = Theme.point(input)
			if not drag.active and math.sqrt((point.X - drag.start.X) ^ 2 + (point.Y - drag.start.Y) ^ 2) < 4 then
				return
			end
			drag.active = true
			local drop, entry = dropAt(point, drag.id)
			drag.drop = drop
			showDrop(drop, entry, point)
		end)
		local ended = ui.connect(UserInputService, "InputEnded", function(input: Compose.Node)
			local drag = dragging
			if drag == nil or ui.get(input, "UserInputType") ~= ui.values.enum("UserInputType", "MouseButton1") then
				return
			end
			dragging = nil
			showDrop(nil, nil, { X = 0, Y = 0 })
			local drop = drag.drop
			if drag.active and drop then
				session.move(drag.id, drop.destination, drop.before)
				session.select(drag.id)
			end
		end)
		return {
			root = scroller,
			dispose = function()
				release()
				moved:Disconnect()
				ended:Disconnect()
				clear()
				ui.destroy(indicator)
				ui.destroy(scroller)
			end,
		}
	end
end
