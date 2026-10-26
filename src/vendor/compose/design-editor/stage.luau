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
	dispose: () -> (),
}

export type Options = {
	size: UI.Point,
	accent: unknown?,
	token: ((name: string) -> Design.Literal)?,
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
					ui.get(frame, "Parent")
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
		local function startResize(corner: UI.Point, from: UI.Point)
			local id = session.selected:peek()
			local instance: Compose.Node? = nodes[id]
			local node = Design.document.find(session.document:peek().root, id)
			if instance == nil or node == nil then
				return
			end
			local fields = session.library.kinds[node.kind].fields
			if fields.width == nil or fields.height == nil then
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
		local function pick(point: UI.Point): string
			local value = session.document:peek()
			local chosen, deepest = value.root.id, -1
			for id, instance in nodes do
				if ui.get(instance, "Parent") and contains(instance, point, surface) then
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
			target: (Compose.Use) -> string?
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
			local shown: Compose.Node? = nil
			local function place()
				local instance = shown
				if instance == nil or ui.get(instance, "Parent") == nil then
					ui.set(box, "Visible", false)
					return
				end
				local factor = scaleOf(instance)
				local at = Math.scale(
					Math.sub(ui.xy(instance, "AbsolutePosition"), ui.xy(overlay, "AbsolutePosition")),
					1 / factor
				)
				local size = Math.scale(ui.xy(instance, "AbsoluteSize"), 1 / factor)
				ui.set(box, "Position", ui.values.udim2(0, at.X, 0, at.Y))
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
				local id = target(use)
				shown = if id then nodes[id] else nil
				local instance = shown
				if instance then
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
							inputs = options.inputs,
							slots = options.slots,
							token = options.token,
							decorate = function(node: Design.Node, built: Compose.Node)
								if ui.isA(built, "GuiObject") then
									runtime.decorate(built, { Attributes = { [ATTRIBUTE] = node.id } })
									nodes[node.id] = built
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
			outline("DesignHover", 1, false, function(use: Compose.Use): string?
				local id = use(session.hovered)
				return if id == use(session.selected) then nil else id
			end)
			outline("DesignSelected", 1.5, true, function(use: Compose.Use): string?
				use(session.document)
				return use(session.selected)
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
					end
				end)
			)
		end
		table.insert(
			surfaceInput,
			ui.connect(UserInputService, "InputChanged", function(input: Compose.Node)
				if resizing and ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseMovement") then
					updateResize(toGui(input))
					return
				end
				local from = panning
				if from and ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseMovement") then
					local at = toGui(input)
					pan = Math.add(pan, Math.sub(at, from))
					panning = at
					apply()
				end
			end)
		)
		table.insert(
			surfaceInput,
			ui.connect(UserInputService, "InputEnded", function(input: Compose.Node)
				if
					ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton3")
					or ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1")
				then
					panning = nil
				end
				if ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1") and resizing then
					finishResize()
				end
			end)
		)
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
					session.select(pick(point))
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
