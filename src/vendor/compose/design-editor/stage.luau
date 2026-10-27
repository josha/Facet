--!strict

local UI = require "./ui"
local Math = require "./math"

local Compose = require "../core"
local Design = require "../design"

export type Stage = {
	surface: Compose.Node,
	overlay: Compose.Node,
	nodes: { [string]: Compose.Node },
	zoom: Compose.Value<number>,
	fit: () -> (),
	zoomTo: (scale: number, around: UI.Point?) -> (),
	resize: (size: UI.Point) -> (),
	play: (sequence: string) -> (),
	dispose: () -> (),
}

export type Options = {
	size: UI.Point,
	accent: unknown?,
	token: ((name: string) -> Design.Literal)?,
	resolveToken: ((name: string) -> Design.Resolved)?,
	inputs: { [string]: Design.Literal }?,
	slots: { [string]: () -> Compose.Node }?,
}

return function(ui: UI.UI)
	local Theme = require "./theme"(ui)
	local ATTRIBUTE = "ComposeDesignNode"

	local function frame(name: string): Compose.Node
		local created = ui.new "Frame"
		ui.set(created, "Name", name)
		ui.set(created, "BackgroundTransparency", 1)
		ui.set(created, "BorderSizePixel", 0)
		return created
	end

	local function contains(instance: Compose.Node, point: UI.Point, root: Compose.Node): boolean
		local current: Compose.Node? = instance
		while current and ui.isA(current, "GuiObject") do
			if not ui.get(current, "Visible") then
				return false
			end
			if current == instance or ui.get(current, "ClipsDescendants") then
				local at, size = ui.xy(current, "AbsolutePosition"), ui.xy(current, "AbsoluteSize")
				if point.X < at.X or point.Y < at.Y or point.X > at.X + size.X or point.Y > at.Y + size.Y then
					return false
				end
			end
			if current == root then
				break
			end
			current = ui.get(current, "Parent")
		end
		return true
	end

	local function depthOf(instance: Compose.Node, root: Compose.Node): number
		local depth, ancestor = 0, ui.get(instance, "Parent")
		while ancestor and ancestor ~= root do
			depth += 1
			ancestor = ui.get(ancestor, "Parent")
		end
		return depth
	end

	local function scaleOf(instance: Compose.Node): number
		local factor, current: Compose.Node? = 1, instance
		while current do
			local uiScale = ui.call(current, "FindFirstChildWhichIsA", "UIScale")
			if uiScale then
				factor *= ui.number(uiScale, "Scale")
			end
			current = ui.get(current, "Parent")
		end
		return factor
	end

	return function(session: Design.Session, parent: Compose.Node, options: Options): Stage
		local accent = options.accent or Theme.color.accent
		local width, height = options.size.X, options.size.Y
		local holder = frame "DesignStage"
		ui.set(holder, "Size", ui.values.udim2(1, 0, 1, 0))
		ui.set(holder, "AnchorPoint", ui.values.vector2(0.5, 0.5))
		ui.set(holder, "Position", ui.values.udim2(0.5, 0, 0.5, 0))
		local camera = ui.new "UIScale"
		ui.set(camera, "Parent", holder)
		local zoom = Compose.cell(1)
		local pan: UI.Point = { X = 0, Y = 0 }
		local framed: { { instance: Compose.Node, grow: number } } = {}
		local function centered(name: string, grow: number): Compose.Node
			local created = frame(name)
			ui.set(created, "AnchorPoint", ui.values.vector2(0.5, 0.5))
			ui.set(created, "Position", ui.values.udim2(0.5, 0, 0.5, 0))
			ui.set(created, "Size", ui.values.udim2(0, width + grow, 0, height + grow))
			table.insert(framed, { instance = created, grow = grow })
			return created
		end
		for depth, spread in { 24, 12, 4 } do
			local shadow = centered("Shadow", spread)
			ui.set(shadow, "Position", ui.values.udim2(0.5, 0, 0.5, spread / 3))
			ui.set(shadow, "BackgroundColor3", Theme.color.shadow)
			ui.set(shadow, "BackgroundTransparency", 0.94 - depth * 0.06)
			ui.set(shadow, "ZIndex", 0)
			Theme.corner(shadow, 4 + spread / 2)
			ui.set(shadow, "Parent", holder)
		end
		local surface = centered("DesignSurface", 0)
		ui.set(surface, "ClipsDescendants", true)
		ui.set(surface, "BackgroundTransparency", 0)
		ui.set(surface, "BackgroundColor3", ui.rgb(18, 20, 26))
		ui.set(surface, "ZIndex", 1)
		local title = Theme.label("", Theme.color.secondary, Theme.size.small, Theme.font.bold)
		ui.set(title, "Name", "ArtboardTitle")
		ui.set(title, "AnchorPoint", ui.values.vector2(0.5, 1))
		ui.set(title, "Position", ui.values.udim2(0.5, 0, 0.5, -height / 2 - 6))
		ui.set(title, "Size", ui.values.udim2(0, width, 0, 16))
		local titleScale = ui.new "UIScale"
		ui.set(titleScale, "Parent", title)
		ui.set(title, "Parent", holder)
		local dimensions = Theme.label(`{width} × {height}`, Theme.color.tertiary, Theme.size.small)
		ui.set(dimensions, "Name", "ArtboardSize")
		ui.set(dimensions, "TextXAlignment", ui.values.enum("TextXAlignment", "Right"))
		ui.set(dimensions, "Size", ui.values.udim2(1, 0, 1, 0))
		ui.set(dimensions, "Parent", title)
		local overlay = centered("DesignOverlay", 0)
		ui.set(overlay, "ZIndex", 2)
		ui.set(overlay, "Active", true)
		ui.set(surface, "Parent", holder)
		ui.set(overlay, "Parent", holder)
		ui.set(holder, "Parent", parent)
		local nodes: { [string]: Compose.Node } = {}
		local UserInputService = ui.service "UserInputService"
		local function blocked(id: string): boolean
			local node, parentNode = Design.document.find(session.document:peek().root, id)
			while node do
				if node.locked or node.hidden then
					return true
				end
				node = parentNode
				if node then
					local _, ancestor = Design.document.find(session.document:peek().root, node.id)
					parentNode = ancestor
				end
			end
			return false
		end
		type Resize = {
			corner: UI.Point,
			from: UI.Point,
			size: UI.Point,
			instance: Compose.Node,
			result: UI.Point?,
		}
		local resizing: Resize? = nil
		local function toGui(input: Compose.Node): UI.Point
			return Theme.point(input)
		end
		type Grip = { frame: Compose.Node, corner: UI.Point }
		local selectionGrips: { Grip } = {}
		local function gripAt(point: UI.Point): Grip?
			for _, grip in selectionGrips do
				local frame = grip.frame
				if
					ui.get(frame, "Visible")
					and ui.get(frame, "Parent")
					and ui.isA(ui.get(frame, "Parent"), "GuiObject")
					and ui.get(ui.get(frame, "Parent"), "Visible")
				then
					local center =
						Math.add(ui.xy(frame, "AbsolutePosition"), Math.scale(ui.xy(frame, "AbsoluteSize"), 0.5))
					if Math.length(Math.sub(point, center)) <= 8 then
						return grip
					end
				end
			end
			return nil
		end
		local function resizable(id: string?): ("fields" | "size")?
			local node = if id then Design.document.find(session.document:peek().root, id) else nil
			local kind = if node then session.library.kinds[node.kind] else nil
			if kind == nil then
				return nil
			end
			local fields = kind.fields
			if fields.width ~= nil and fields.height ~= nil then
				return "fields"
			end
			local native = fields.Size
			if native ~= nil and native.type == "datatype" and native.datatype == "UDim2" then
				return "size"
			end
			return nil
		end
		type Drop = { destination: string, before: number, edge: UI.Point, along: UI.Point }
		type Carry = { id: string, start: UI.Point, active: boolean, drop: Drop? }
		local carrying: Carry? = nil
		type Marquee = { from: UI.Point, to: UI.Point, base: { string } }
		local marquee: Marquee? = nil
		local marqueeBox = frame "DesignMarquee"
		ui.set(marqueeBox, "BackgroundColor3", accent)
		ui.set(marqueeBox, "BackgroundTransparency", 0.85)
		ui.set(marqueeBox, "Visible", false)
		ui.set(marqueeBox, "ZIndex", 2005)
		Theme.stroke(marqueeBox, accent, 1)
		ui.set(marqueeBox, "Parent", overlay)
		local function updateMarquee(point: UI.Point)
			local active = marquee
			if active == nil then
				return
			end
			active.to = point
			local left, top = math.min(active.from.X, point.X), math.min(active.from.Y, point.Y)
			local right, bottom = math.max(active.from.X, point.X), math.max(active.from.Y, point.Y)
			local origin, factor = ui.xy(overlay, "AbsolutePosition"), scaleOf(overlay)
			ui.set(marqueeBox, "Position", ui.values.udim2(0, (left - origin.X) / factor, 0, (top - origin.Y) / factor))
			ui.set(marqueeBox, "Size", ui.values.udim2(0, (right - left) / factor, 0, (bottom - top) / factor))
			ui.set(marqueeBox, "Visible", true)
		end
		local function finishMarquee()
			local active = marquee
			marquee = nil
			ui.set(marqueeBox, "Visible", false)
			if active == nil then
				return
			end
			local ids = table.clone(active.base)
			if Math.length(Math.sub(active.to, active.from)) >= 4 then
				local left, top = math.min(active.from.X, active.to.X), math.min(active.from.Y, active.to.Y)
				local right, bottom = math.max(active.from.X, active.to.X), math.max(active.from.Y, active.to.Y)
				for id, instance in nodes do
					if id ~= session.document:peek().root.id and not blocked(id) and ui.get(instance, "Parent") then
						local at, extent = ui.xy(instance, "AbsolutePosition"), ui.xy(instance, "AbsoluteSize")
						local x1 = math.max(at.X, left)
						local y1 = math.max(at.Y, top)
						local x2 = math.min(at.X + extent.X, right)
						local y2 = math.min(at.Y + extent.Y, bottom)
						local current: Compose.Node? = instance
						local visible = true
						while current and ui.isA(current, "GuiObject") do
							visible = visible and ui.get(current, "Visible") ~= false
							if ui.get(current, "ClipsDescendants") then
								local origin, size = ui.xy(current, "AbsolutePosition"), ui.xy(current, "AbsoluteSize")
								x1 = math.max(x1, origin.X)
								y1 = math.max(y1, origin.Y)
								x2 = math.min(x2, origin.X + size.X)
								y2 = math.min(y2, origin.Y + size.Y)
							end
							if current == surface then
								break
							end
							current = ui.get(current, "Parent")
						end
						if visible and x1 <= x2 and y1 <= y2 then
							table.insert(ids, id)
						end
					end
				end
			end
			session.selectMany(ids)
		end
		local marker = frame "DesignDropMarker"
		ui.set(marker, "BackgroundTransparency", 0)
		ui.set(marker, "BackgroundColor3", accent)
		ui.set(marker, "ZIndex", 2004)
		ui.set(marker, "Visible", false)
		ui.set(marker, "Parent", overlay)
		local function horizontal(instance: Compose.Node): boolean
			local layout = ui.call(instance, "FindFirstChildWhichIsA", "UIListLayout")
			return layout ~= nil and ui.get(layout, "FillDirection") == ui.values.enum("FillDirection", "Horizontal")
		end
		local function dropAt(point: UI.Point, moving: string): Drop?
			local value = session.document:peek()
			local movingNode = Design.document.find(value.root, moving)
			if movingNode == nil then
				return nil
			end
			local host: Design.Node? = nil
			local deepest = -1
			for id, instance in nodes do
				local node = Design.document.find(value.root, id)
				local kind = if node then session.library.kinds[node.kind] else nil
				if
					node
					and kind
					and kind.children == "list"
					and kind.leaf ~= true
					and not blocked(id)
					and not table.find(session.selection:peek(), id)
					and Design.document.find(movingNode, id) == nil
					and ui.get(instance, "Parent")
					and contains(instance, point, surface)
				then
					local depth = depthOf(instance, surface)
					if depth > deepest then
						host, deepest = node, depth
					end
				end
			end
			local container = host
			if container == nil then
				return nil
			end
			local box = nodes[container.id]
			local across = horizontal(box)
			local origin = ui.xy(overlay, "AbsolutePosition")
			local at, extent = ui.xy(box, "AbsolutePosition"), ui.xy(box, "AbsoluteSize")
			local before, count = 1, 0
			local edge = if across then at.X else at.Y
			for _, child in container.children do
				if child.id ~= moving and not table.find(session.selection:peek(), child.id) then
					count += 1
					local instance = nodes[child.id]
					if instance then
						local position, size = ui.xy(instance, "AbsolutePosition"), ui.xy(instance, "AbsoluteSize")
						local middle = if across then position.X + size.X / 2 else position.Y + size.Y / 2
						local pointer = if across then point.X else point.Y
						if pointer > middle then
							before = count + 1
							edge = if across then position.X + size.X else position.Y + size.Y
						end
					end
				end
			end
			return {
				destination = container.id,
				before = before,
				edge = if across
					then { X = edge - origin.X, Y = at.Y - origin.Y }
					else { X = at.X - origin.X, Y = edge - origin.Y },
				along = if across then { X = 2, Y = extent.Y } else { X = extent.X, Y = 2 },
			}
		end
		local function carry(point: UI.Point)
			local active = carrying
			if active == nil then
				return
			end
			if not active.active and Math.length(Math.sub(point, active.start)) < 4 then
				return
			end
			active.active = true
			local drop = dropAt(point, active.id)
			active.drop = drop
			ui.set(marker, "Visible", drop ~= nil)
			if drop then
				ui.set(marker, "Position", ui.values.udim2(0, drop.edge.X, 0, drop.edge.Y))
				ui.set(marker, "Size", ui.values.udim2(0, drop.along.X, 0, drop.along.Y))
			end
		end
		local function finishCarry()
			local active = carrying
			carrying = nil
			ui.set(marker, "Visible", false)
			local drop = if active and active.active then active.drop else nil
			if active and drop then
				session.move(active.id, drop.destination, drop.before)
			elseif active and not active.active then
				session.select(active.id)
			end
		end
		local function startResize(corner: UI.Point, from: UI.Point)
			local id = session.selected:peek()
			if #session.selection:peek() ~= 1 or blocked(id) then
				return
			end
			local instance: Compose.Node? = nodes[id]
			local node = Design.document.find(session.document:peek().root, id)
			if instance == nil or node == nil then
				return
			end
			if resizable(id) == nil then
				return
			end
			resizing = {
				corner = corner,
				from = from,
				size = Math.scale(ui.xy(instance, "AbsoluteSize"), 1 / scaleOf(instance)),
				instance = instance,
				result = nil,
			}
		end
		local function updateResize(at: UI.Point)
			local active = resizing
			if active == nil then
				return
			end
			local delta = Math.scale(Math.sub(at, active.from), 1 / scaleOf(active.instance))
			local signed = { X = delta.X * (active.corner.X * 2 - 1), Y = delta.Y * (active.corner.Y * 2 - 1) }
			local width = math.max(1, math.round(active.size.X + signed.X))
			local height = math.max(1, math.round(active.size.Y + signed.Y))
			if
				ui.call(UserInputService, "IsKeyDown", ui.values.enum("KeyCode", "LeftShift")) == true
				and active.size.Y > 0
			then
				local ratio = active.size.X / active.size.Y
				if math.abs(signed.X) > math.abs(signed.Y) then
					height = math.max(1, math.round(width / ratio))
				else
					width = math.max(1, math.round(height * ratio))
				end
			end
			active.result = { X = width, Y = height }
			ui.set(active.instance, "AutomaticSize", ui.values.enum("AutomaticSize", "None"))
			ui.set(active.instance, "Size", ui.values.udim2(0, width, 0, height))
		end
		local function finishResize()
			local active = resizing
			resizing = nil
			local result = if active then active.result else nil
			if result == nil then
				return
			end
			local id = session.selected:peek()
			local node = Design.document.find(session.document:peek().root, id)
			if node == nil then
				return
			end
			local fields = session.library.kinds[node.kind].fields
			if resizable(id) == "size" then
				session.change("Size", { literal = { 0, result.X, 0, result.Y } })
				return
			end
			local changes: { [string]: Design.Value } = {
				width = { literal = result.X },
				height = { literal = result.Y },
			}
			if fields.fillWidth then
				changes.fillWidth = { literal = false }
			end
			if fields.fillHeight then
				changes.fillHeight = { literal = false }
			end
			session.changeMany(changes)
		end
		local runtime = ui.runtime
		local stopDesign: (() -> ())? = nil
		local function pick(point: UI.Point): string?
			local chosen: string? = nil
			local deepest = -1
			for id, instance in nodes do
				if not blocked(id) and ui.get(instance, "Parent") and contains(instance, point, surface) then
					local depth = depthOf(instance, surface)
					if depth > deepest then
						chosen, deepest = id, depth
					end
				end
			end
			return chosen
		end
		local function outline(
			name: string,
			thickness: number,
			handles: boolean,
			target: (Compose.Use) -> { string }
		): Compose.Node
			local box = frame(name)
			ui.set(box, "Visible", false)
			ui.set(box, "Interactable", false)
			ui.set(box, "ZIndex", 2001)
			local ring = Theme.stroke(box, accent, thickness)
			local badge: Compose.Node? = nil
			local grips: { Compose.Node } = {}
			local badgeScale = if handles then ui.new "UIScale" else nil
			if handles then
				for _, corner in { { X = 0, Y = 0 }, { X = 1, Y = 0 }, { X = 0, Y = 1 }, { X = 1, Y = 1 } } do
					local handle = frame "Handle"
					ui.set(handle, "AnchorPoint", ui.values.vector2(0.5, 0.5))
					ui.set(handle, "Position", ui.values.udim2(corner.X, 0, corner.Y, 0))
					ui.set(handle, "Size", ui.values.udim2(0, 7, 0, 7))
					ui.set(handle, "BackgroundTransparency", 0)
					ui.set(handle, "BackgroundColor3", Theme.color.white)
					ui.set(handle, "ZIndex", 2002)
					Theme.stroke(handle, accent, 1)
					ui.set(handle, "Parent", box)
					table.insert(grips, handle)
					table.insert(selectionGrips, { frame = handle, corner = corner })
				end
				local size = Theme.label("", Theme.color.white, Theme.size.small, Theme.font.bold)
				ui.set(size, "Name", "SizeBadge")
				ui.set(size, "TextTruncate", ui.values.enum("TextTruncate", "None"))
				ui.set(size, "AutomaticSize", ui.values.enum("AutomaticSize", "X"))
				ui.set(size, "AnchorPoint", ui.values.vector2(0.5, 0))
				ui.set(size, "Position", ui.values.udim2(0.5, 0, 1, 8))
				ui.set(size, "Size", ui.values.udim2(0, 0, 0, 18))
				ui.set(size, "BackgroundTransparency", 0)
				ui.set(size, "BackgroundColor3", accent)
				ui.set(size, "TextXAlignment", ui.values.enum("TextXAlignment", "Center"))
				ui.set(size, "ZIndex", 2003)
				Theme.corner(size, 4)
				Theme.pad(size, 6)
				ui.set(badgeScale, "Parent", size)
				ui.set(size, "Parent", box)
				badge = size
			end
			ui.set(box, "Parent", overlay)
			local connections: { UI.Connection } = {}
			local function release()
				for _, connection in connections do
					connection:Disconnect()
				end
				table.clear(connections)
			end
			local shown: { Compose.Node } = {}
			local function place()
				local instance = shown[1]
				if instance == nil or ui.get(instance, "Parent") == nil or ui.get(instance, "Visible") == false then
					ui.set(box, "Visible", false)
					return
				end
				local factor = scaleOf(instance)
				local at = Math.scale(
					Math.sub(ui.xy(instance, "AbsolutePosition"), ui.xy(overlay, "AbsolutePosition")),
					1 / factor
				)
				local extent = Math.scale(ui.xy(instance, "AbsoluteSize"), 1 / factor)
				local left = at.X
				local top = at.Y
				local right = at.X + extent.X
				local bottom = at.Y + extent.Y
				for _, other in shown do
					local point = Math.scale(
						Math.sub(ui.xy(other, "AbsolutePosition"), ui.xy(overlay, "AbsolutePosition")),
						1 / factor
					)
					local otherSize = Math.scale(ui.xy(other, "AbsoluteSize"), 1 / factor)
					left = math.min(left, point.X)
					top = math.min(top, point.Y)
					right = math.max(right, point.X + otherSize.X)
					bottom = math.max(bottom, point.Y + otherSize.Y)
				end
				local size = { X = right - left, Y = bottom - top }
				ui.set(box, "Position", ui.values.udim2(0, left, 0, top))
				ui.set(box, "Size", ui.values.udim2(0, size.X, 0, size.Y))
				ui.set(box, "Visible", true)
				ui.set(ring, "Thickness", thickness / factor)
				for _, grip in grips do
					ui.set(grip, "Size", ui.values.udim2(0, 7 / factor, 0, 7 / factor))
				end
				if badgeScale then
					ui.set(badgeScale, "Scale", 1 / factor)
				end
				if badge then
					ui.set(badge, "Position", ui.values.udim2(0.5, 0, 1, 8 / factor))
					ui.set(
						badge,
						"Text",
						`{math.round(size.X / ui.number(camera, "Scale") * factor)} × {math.round(
							size.Y / ui.number(camera, "Scale") * factor
						)}`
					)
				end
			end
			Compose.watch(function(use: Compose.Use)
				release()
				local ids = target(use)
				table.clear(shown)
				for _, id in ids do
					if nodes[id] then
						table.insert(shown, nodes[id])
					end
				end
				local id = ids[1]
				local canResize = #ids == 1 and resizable(id) ~= nil and not blocked(id)
				for _, grip in grips do
					ui.set(grip, "Visible", canResize)
				end
				for _, instance in shown do
					table.insert(connections, ui.changed(instance, "AbsolutePosition", place))
					table.insert(connections, ui.changed(instance, "AbsoluteSize", place))
					table.insert(connections, ui.changed(overlay, "AbsolutePosition", place))
					table.insert(connections, ui.changed(overlay, "AbsoluteSize", place))
				end
				place()
			end)
			Compose.cleanup(release)
			return box
		end
		local started = false
		local players: { [string]: Design.Player } = {}
		local root = Compose.createRootOwner(function()
			Compose.watch(function(use: Compose.Use)
				local value = use(session.document)
				ui.set(title, "Text", value.name)
				if stopDesign then
					stopDesign()
				end
				table.clear(nodes)
				stopDesign = runtime.mount(function(): Compose.Node
					local rendered, content = pcall(function(): unknown
						return Design.render(value, session.library, {
							exclude = function(node: Design.Node): boolean
								return node.hidden == true
							end,
							inputs = options.inputs,
							slots = options.slots,
							token = options.token,
							resolveToken = options.resolveToken,
							players = function(made: { [string]: Design.Player })
								players = made
							end,
							decorate = function(node: Design.Node, built: Compose.Node)
								if ui.isA(built, "GuiObject") then
									runtime.decorate(built, { Attributes = { [ATTRIBUTE] = node.id } })
									nodes[node.id] = built
									local kind = session.library.kinds[node.kind]
									if kind and kind.children == "list" and #node.children == 0 then
										local floor = ui.new "UISizeConstraint"
										ui.set(floor, "Name", "DesignEmptyFloor")
										ui.set(floor, "MinSize", ui.values.vector2(96, 48))
										ui.set(floor, "Parent", built)
										local mark = ui.new "UIStroke"
										ui.set(mark, "Name", "DesignEmptyMark")
										ui.set(mark, "Color", Theme.color.tertiary)
										ui.set(mark, "Transparency", 0.4)
										ui.set(mark, "Thickness", 1)
										ui.set(mark, "ApplyStrokeMode", ui.values.enum("ApplyStrokeMode", "Border"))
										ui.set(mark, "Parent", built)
									end
								end
							end,
						})
					end)
					if not rendered then
						if not started then
							error(content, 0)
						end
						table.clear(nodes)
						session.problem:set(`This design does not render: {content}`)
						return nil
					end
					local provide = session.library.provide
					return if provide then provide(content) else content
				end, surface)
			end)
			outline("DesignHover", 1, false, function(use: Compose.Use): { string }
				local id = use(session.hovered)
				return if id and not table.find(use(session.selection), id) then { id } else {}
			end)
			outline("DesignSelected", 1.5, true, function(use: Compose.Use): { string }
				use(session.document)
				return use(session.selection)
			end)
			local perNode: { Compose.Node } = {}
			Compose.watch(function(use: Compose.Use)
				use(session.document)
				local ids = use(session.selection)
				for _, box in perNode do
					ui.destroy(box)
				end
				table.clear(perNode)
				if #ids > 1 then
					for _, id in ids do
						table.insert(
							perNode,
							outline(`DesignSelected_{id}`, 1, false, function(read: Compose.Use): { string }
								read(session.document)
								return { id }
							end)
						)
					end
				end
			end)
		end, runtime.reactor)
		started = true
		local release = Compose.owner.own(ui.owner, root.dispose)
		local function apply()
			local scale = zoom:peek()
			ui.set(camera, "Scale", scale)
			ui.set(titleScale, "Scale", 1 / scale)
			ui.set(title, "Size", ui.values.udim2(0, width * scale, 0, 16))
			ui.set(title, "Position", ui.values.udim2(0.5, 0, 0.5, -height / 2 - 6 / scale))
			ui.set(holder, "Position", ui.values.udim2(0.5, pan.X, 0.5, pan.Y))
		end
		local function zoomTo(scale: number, around: UI.Point?)
			local before = zoom:peek()
			local after = math.clamp(scale, 0.1, 8)
			if around and ui.get(holder, "Parent") and ui.isA(ui.get(holder, "Parent"), "GuiObject") then
				local host = ui.get(holder, "Parent")
				local center = Math.add(
					Math.add(ui.xy(host, "AbsolutePosition"), Math.scale(ui.xy(host, "AbsoluteSize"), 0.5)),
					pan
				)
				pan = Math.add(pan, Math.scale(Math.sub(around, center), 1 - after / before))
			end
			zoom:set(after)
			apply()
		end
		local function fit()
			pan = { X = 0, Y = 0 }
			local host = ui.get(holder, "Parent")
			if host and ui.isA(host, "GuiObject") and ui.xy(host, "AbsoluteSize").X > 0 then
				local room = Math.sub(ui.xy(host, "AbsoluteSize"), { X = 96, Y = 120 })
				zoom:set(math.clamp(math.min(room.X / width, room.Y / height), 0.1, 1))
			else
				zoom:set(1)
			end
			apply()
		end
		local panning: UI.Point? = nil
		local function beginMarquee(point: UI.Point, input: Compose.Node)
			local picked = pick(point)
			if picked == nil or picked == session.document:peek().root.id then
				local additive = ui.modified(input, { "Shift", "Ctrl", "Meta" })
				marquee =
					{ from = point, to = point, base = if additive then table.clone(session.selection:peek()) else {} }
			end
		end
		local surfaceInput: { UI.Connection } = {}
		if ui.isA(parent, "GuiObject") then
			table.insert(
				surfaceInput,
				ui.connect(parent, "InputChanged", function(input: Compose.Node)
					if ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseWheel") then
						local factor = if ui.xyz(input, "Position").Z > 0 then 1.15 else 1 / 1.15
						zoomTo(zoom:peek() * factor, toGui(input))
					end
				end)
			)
			table.insert(
				surfaceInput,
				ui.connect(parent, "InputBegan", function(input: Compose.Node)
					local middle = ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton3")
					local spaced = ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1")
						and ui.call(UserInputService, "IsKeyDown", ui.values.enum("KeyCode", "Space")) == true
					if middle or spaced then
						panning = toGui(input)
					elseif ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1") then
						beginMarquee(toGui(input), input)
					end
				end)
			)
		end
		local function onPointerChanged(input: Compose.Node)
			if marquee and ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseMovement") then
				updateMarquee(toGui(input))
				return
			end
			if resizing and ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseMovement") then
				updateResize(toGui(input))
				return
			end
			if carrying and ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseMovement") then
				carry(toGui(input))
				return
			end
			local from = panning
			if from and ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseMovement") then
				local at = toGui(input)
				pan = Math.add(pan, Math.sub(at, from))
				panning = at
				apply()
			end
		end
		local function onPointerEnded(input: Compose.Node)
			if ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1") and marquee then
				finishMarquee()
			end
			if
				ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton3")
				or ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1")
			then
				panning = nil
			end
			if ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1") and resizing then
				finishResize()
			end
			if ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1") and carrying then
				finishCarry()
			end
		end
		for _, source in { UserInputService, parent } do
			if source == UserInputService or ui.isA(source, "GuiObject") then
				table.insert(surfaceInput, ui.connect(source, "InputChanged", onPointerChanged))
				table.insert(surfaceInput, ui.connect(source, "InputEnded", onPointerEnded))
			end
		end
		local began = ui.connect(overlay, "InputBegan", function(input: Compose.Node)
			if
				ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1")
				or ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "Touch")
			then
				local point = toGui(input)
				local grip = gripAt(point)
				if grip then
					startResize(grip.corner, point)
				elseif ui.call(UserInputService, "IsKeyDown", ui.values.enum("KeyCode", "Space")) ~= true then
					local picked = pick(point)
					if picked == nil or picked == session.document:peek().root.id then
						beginMarquee(point, input)
						return
					end
					local modified = ui.modified(input, { "Shift", "Ctrl", "Meta" })
					if modified then
						session.select(picked, "toggle")
					elseif not table.find(session.selection:peek(), picked) then
						session.select(picked)
					end
					if not modified then
						local movable: { string } = {}
						for _, id in session.selection:peek() do
							if not blocked(id) then
								table.insert(movable, id)
							end
						end
						session.selectMany(movable)
						carrying = { id = picked, start = point, active = false, drop = nil }
					end
				end
			end
		end)
		local moved = ui.connect(overlay, "InputChanged", function(input: Compose.Node)
			if ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseMovement") then
				session.hovered:set(pick(toGui(input)))
			end
		end)
		local left = ui.connect(overlay, "MouseLeave", function()
			session.hovered:set(nil)
		end)
		local function resize(next: UI.Point)
			width, height = next.X, next.Y
			for _, entry in framed do
				ui.set(entry.instance, "Size", ui.values.udim2(0, width + entry.grow, 0, height + entry.grow))
			end
			ui.set(dimensions, "Text", `{width} × {height}`)
			fit()
		end
		return {
			surface = surface,
			overlay = overlay,
			nodes = nodes,
			zoom = zoom,
			fit = fit,
			zoomTo = zoomTo,
			resize = resize,
			play = function(sequence: string)
				local player = players[sequence]
				if player then
					player.play()
				end
			end,
			dispose = function()
				for _, connection in surfaceInput do
					connection:Disconnect()
				end
				began:Disconnect()
				moved:Disconnect()
				left:Disconnect()
				if stopDesign then
					stopDesign()
				end
				release()
				ui.destroy(holder)
			end,
		}
	end
end
