--!strict

local UI = require "./ui"
local Math = require "./math"

local Compose = require "../core"
local Design = require "../design"

export type Scene = {
	viewport: Compose.Node,
	world: Compose.Node,
	camera: Compose.Node,
	nodes: { [string]: Compose.Node },
	zoom: Compose.Value<number>,
	fit: () -> (),
	zoomTo: (scale: number, around: UI.Point?) -> (),
	pick: (point: UI.Point) -> string?,
	dispose: () -> (),
}

export type Options = {
	accent: unknown?,
	token: ((name: string) -> Design.Literal)?,
	resolveToken: ((name: string) -> Design.Resolved)?,
	inputs: { [string]: Design.Literal }?,
	slots: { [string]: () -> Compose.Node }?,
}

return function(ui: UI.UI)
	local Theme = require "./theme"(ui)
	local ATTRIBUTE = "ComposeDesignNode"
	local AXES = {
		{ name = "X", direction = { X = 1, Y = 0, Z = 0 }, color = ui.rgb(242, 92, 84) },
		{ name = "Y", direction = { X = 0, Y = 1, Z = 0 }, color = ui.rgb(80, 200, 120) },
		{ name = "Z", direction = { X = 0, Y = 0, Z = 1 }, color = ui.rgb(53, 129, 247) },
	}

	local function helper(name: string, size: UI.Vector, color: unknown, transparency: number): Compose.Node
		local part = ui.new "Part"
		ui.set(part, "Name", name)
		ui.set(part, "Anchored", true)
		ui.set(part, "CanCollide", false)
		ui.set(part, "CanQuery", false)
		ui.set(part, "CastShadow", false)
		ui.set(part, "Material", ui.values.enum("Material", "SmoothPlastic"))
		ui.set(part, "Size", ui.values.vector3(size.X, size.Y, size.Z))
		ui.set(part, "Color", color)
		ui.set(part, "Transparency", transparency)
		return part
	end

	local function boundsOf(instance: Compose.Node): (unknown, UI.Vector)
		if ui.isA(instance, "Model") then
			local frame, extent = ui.call(instance, "GetBoundingBox")
			return frame, ui.vector(extent)
		elseif ui.isA(instance, "BasePart") then
			return ui.get(instance, "CFrame"), ui.xyz(instance, "Size")
		end
		return ui.call(instance, "GetPivot"), { X = 1, Y = 1, Z = 1 }
	end

	local function closestOnAxis(
		origin: UI.Vector,
		axis: UI.Vector,
		rayOrigin: UI.Vector,
		rayDirection: UI.Vector
	): number
		local w = Math.vsub(origin, rayOrigin)
		local b = Math.dot(axis, rayDirection)
		local d = Math.dot(axis, w)
		local e = Math.dot(rayDirection, w)
		local c = Math.dot(rayDirection, rayDirection)
		local denominator = c - b * b
		if math.abs(denominator) < 1e-6 then
			return 0
		end
		return (b * e - c * d) / denominator
	end

	return function(session: Design.Session, parent: Compose.Node, options: Options): Scene
		local accent = options.accent or Theme.color.accent
		local viewport = ui.new "ViewportFrame"
		ui.set(viewport, "Name", "DesignScene")
		ui.set(viewport, "Size", ui.values.udim2(1, 0, 1, 0))
		ui.set(viewport, "BackgroundColor3", Theme.color.canvas)
		ui.set(viewport, "BorderSizePixel", 0)
		ui.set(viewport, "Ambient", ui.rgb(150, 150, 160))
		ui.set(viewport, "LightColor", ui.rgb(255, 250, 240))
		ui.set(viewport, "LightDirection", ui.values.vector3(-1, -2, -0.6))
		ui.set(viewport, "Active", true)
		local world = ui.new "WorldModel"
		ui.set(world, "Parent", viewport)
		local camera = ui.new "Camera"
		ui.set(camera, "FieldOfView", 50)
		ui.set(camera, "Parent", viewport)
		ui.set(viewport, "CurrentCamera", camera)
		local guides = ui.new "Folder"
		ui.set(guides, "Name", "Guides")
		ui.set(guides, "Parent", world)
		for step = -32, 32, 4 do
			local major = step == 0
			local tone = if major then Theme.color.secondary else Theme.color.grid
			local width = if major then 0.08 else 0.04
			local fade = if major then 0.3 else 0.5
			local across = helper("GridX", { X = 64, Y = 0.02, Z = width }, tone, fade)
			ui.set(across, "CFrame", ui.values.cframe(Math.frame { X = 0, Y = 0, Z = step }))
			ui.set(across, "Parent", guides)
			local along = helper("GridZ", { X = width, Y = 0.02, Z = 64 }, tone, fade)
			ui.set(along, "CFrame", ui.values.cframe(Math.frame { X = step, Y = 0, Z = 0 }))
			ui.set(along, "Parent", guides)
		end
		ui.set(viewport, "Parent", parent)
		local nodes: { [string]: Compose.Node } = {}
		local runtime = ui.runtime
		local stopDesign: (() -> ())? = nil
		local yaw, pitch, distance, focus = math.rad(35), math.rad(-28), 28, { X = 0, Y = 1, Z = 0 }
		local zoom = Compose.cell(1)
		local function aim()
			local rotation = Math.rotation(pitch, yaw, 0)
			ui.set(
				camera,
				"CFrame",
				ui.values.cframe(
					Math.multiply(Math.multiply(Math.frame(focus), rotation), Math.frame { X = 0, Y = 0, Z = distance })
				)
			)
			ui.set(camera, "Focus", ui.values.cframe(Math.frame(focus)))
			zoom:set(28 / distance)
		end
		aim()
		local function ray(point: UI.Point): (UI.Vector, UI.Vector)
			local size = ui.xy(viewport, "AbsoluteSize")
			local local2 = Math.sub(point, ui.xy(viewport, "AbsolutePosition"))
			local ndc = { X = local2.X / math.max(size.X, 1) * 2 - 1, Y = 1 - local2.Y / math.max(size.Y, 1) * 2 }
			local tanY = math.tan(math.rad(ui.number(camera, "FieldOfView")) / 2)
			local tanX = tanY * size.X / math.max(size.Y, 1)
			local direction = Math.unit(
				Math.transform(ui.components(ui.get(camera, "CFrame")), { X = ndc.X * tanX, Y = ndc.Y * tanY, Z = -1 })
			)
			return ui.xyz(ui.get(camera, "CFrame"), "Position"), direction
		end
		local function nodeOf(instance: Compose.Node?): string?
			local current = instance
			while current and current ~= world do
				local id = ui.call(current, "GetAttribute", ATTRIBUTE)
				if type(id) == "string" then
					return id
				end
				current = ui.get(current, "Parent")
			end
			return nil
		end
		local gizmo = ui.new "Folder"
		ui.set(gizmo, "Name", "Gizmo")
		ui.set(gizmo, "Parent", world)
		local selectedBox = helper("Selected", { X = 1, Y = 1, Z = 1 }, accent, 0.9)
		ui.set(selectedBox, "Parent", gizmo)
		local hoverBox = helper("Hovered", { X = 1, Y = 1, Z = 1 }, accent, 0.95)
		ui.set(hoverBox, "Parent", gizmo)
		local handles: { [Compose.Node]: UI.Vector } = {}
		for _, axis in AXES do
			local shaft = helper("Axis" .. axis.name, { X = 0.12, Y = 0.12, Z = 2.4 }, axis.color, 0)
			ui.set(shaft, "CanQuery", true)
			ui.set(shaft, "Parent", gizmo)
			local tip = helper("Tip" .. axis.name, { X = 0.4, Y = 0.4, Z = 0.6 }, axis.color, 0)
			ui.set(tip, "CanQuery", true)
			ui.set(tip, "Parent", gizmo)
			handles[shaft] = axis.direction
			handles[tip] = axis.direction
		end
		local function show(box: Compose.Node, id: string?)
			local instance = if id then nodes[id] else nil
			if instance == nil or ui.get(instance, "Parent") == nil then
				ui.set(box, "Transparency", 1)
				return
			end
			local frame, size = boundsOf(instance)
			ui.set(box, "CFrame", frame)
			ui.set(box, "Size", ui.values.vector3(size.X + 0.15, size.Y + 0.15, size.Z + 0.15))
			ui.set(box, "Transparency", if box == selectedBox then 0.9 else 0.95)
		end
		local function placeGizmo(id: string?)
			local instance = if id then nodes[id] else nil
			for part, direction in handles do
				if instance == nil or ui.get(instance, "Parent") == nil then
					ui.set(part, "Transparency", 1)
					ui.set(part, "CanQuery", false)
				else
					local origin = ui.xyz(ui.call(instance, "GetPivot"), "Position")
					local _, extent = boundsOf(instance)
					local reach = math.abs(Math.dot(extent, direction)) / 2 + 0.6
					local length = if string.sub(ui.text(part, "Name"), 1, 3) == "Tip" then reach + 2.7 else reach + 1.2
					ui.set(
						part,
						"CFrame",
						ui.values.cframe(
							Math.lookAt(
								Math.vadd(origin, Math.vscale(direction, length)),
								Math.vadd(origin, Math.vscale(direction, length + 1))
							)
						)
					)
					ui.set(part, "Transparency", 0)
					ui.set(part, "CanQuery", true)
				end
			end
		end
		local function pick(point: UI.Point): string?
			local origin, direction = ray(point)
			local parameters = ui.values.raycastParams(false, { guides, gizmo })
			local hit = ui.call(
				world,
				"Raycast",
				ui.values.vector3(origin.X, origin.Y, origin.Z),
				ui.values.vector3(direction.X * 2000, direction.Y * 2000, direction.Z * 2000),
				parameters
			)
			return if hit then nodeOf(ui.get(hit, "Instance")) else nil
		end
		local root = Compose.createRootOwner(function()
			Compose.watch(function(use: Compose.Use)
				local value = use(session.document)
				if stopDesign then
					stopDesign()
				end
				table.clear(nodes)
				stopDesign = runtime.mount(function(): Compose.Node
					return Design.render(value, session.library, {
						inputs = options.inputs,
						slots = options.slots,
						token = options.token,
						resolveToken = options.resolveToken,
						decorate = function(node: Design.Node, built: Compose.Node)
							if ui.isA(built, "PVInstance") then
								runtime.decorate(built, { Attributes = { [ATTRIBUTE] = node.id } })
								nodes[node.id] = built
							end
						end,
					})
				end, world)
			end)
			Compose.watch(function(use: Compose.Use)
				use(session.document)
				local id = use(session.selected)
				show(selectedBox, id)
				placeGizmo(id)
			end)
			Compose.watch(function(use: Compose.Use)
				use(session.document)
				local hovered = use(session.hovered)
				show(hoverBox, if hovered == use(session.selected) then nil else hovered)
			end)
		end, runtime.reactor)
		local release = Compose.owner.own(ui.owner, root.dispose)
		local function fit()
			local value = session.document:peek()
			local instance = nodes[value.root.id]
			if instance then
				local frame, size = boundsOf(instance)
				focus = ui.xyz(frame, "Position")
				distance = math.clamp(Math.magnitude(size) * 1.4, 6, 400)
			end
			aim()
		end
		local function zoomTo(scale: number, _around: UI.Point?)
			distance = math.clamp(28 / math.max(scale, 0.05), 2, 600)
			aim()
		end
		local UserInputService = ui.service "UserInputService"
		type Drag = {
			kind: "orbit" | "pan" | "move",
			from: UI.Point,
			axis: UI.Vector?,
			origin: UI.Vector?,
			start: number?,
		}
		local drag: Drag? = nil
		local moved: UI.Vector? = nil
		local function translate(instance: Compose.Node, target: UI.Vector)
			local origin = ui.xyz(ui.call(instance, "GetPivot"), "Position")
			local delta = Math.vsub(target, origin)
			local targets: { Compose.Node } = if ui.isA(instance, "BasePart")
				then { instance }
				else ui.descendants(instance)
			local changes: { { node: Compose.Node, property: string, frame: { number } } } = {}
			for _, node in targets do
				local part = ui.isA(node, "BasePart")
				if part or ui.isA(node, "Model") then
					local frame = ui.components(if part then ui.get(node, "CFrame") else ui.call(node, "GetPivot"))
					frame[1] += delta.X
					frame[2] += delta.Y
					frame[3] += delta.Z
					table.insert(
						changes,
						{ node = node, property = if part then "CFrame" else "WorldPivot", frame = frame }
					)
				end
			end
			if ui.isA(instance, "Model") then
				local pivot = ui.components(ui.call(instance, "GetPivot"))
				pivot[1], pivot[2], pivot[3] = target.X, target.Y, target.Z
				table.insert(changes, { node = instance, property = "WorldPivot", frame = pivot })
			end
			for _, change in changes do
				ui.set(change.node, change.property, ui.values.cframe(change.frame))
			end
		end
		local connections: { UI.Connection } = {}
		local function connect(connection: UI.Connection)
			table.insert(connections, connection)
		end
		connect(ui.connect(viewport, "InputBegan", function(input: Compose.Node)
			local point = Theme.point(input)
			if ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton2") then
				drag = { kind = "orbit", from = point }
			elseif
				ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton3")
				or (
					ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1")
					and ui.call(UserInputService, "IsKeyDown", ui.values.enum("KeyCode", "Space")) == true
				)
			then
				drag = { kind = "pan", from = point }
			elseif ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1") then
				local origin, direction = ray(point)
				local parameters = ui.values.raycastParams(true, { gizmo })
				local hit = ui.call(
					world,
					"Raycast",
					ui.values.vector3(origin.X, origin.Y, origin.Z),
					ui.values.vector3(direction.X * 2000, direction.Y * 2000, direction.Z * 2000),
					parameters
				)
				local axis = if hit and ui.isA(ui.get(hit, "Instance"), "Part")
					then handles[ui.get(hit, "Instance")]
					else nil
				local selected = nodes[session.selected:peek()]
				if axis and selected then
					local pivot = ui.xyz(ui.call(selected, "GetPivot"), "Position")
					drag = {
						kind = "move",
						from = point,
						axis = axis,
						origin = pivot,
						start = closestOnAxis(pivot, axis, origin, direction),
					}
					moved = nil
				else
					local id = pick(point)
					session.select(id or session.document:peek().root.id)
				end
			elseif ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseWheel") then
				distance = math.clamp(distance * (if ui.xyz(input, "Position").Z > 0 then 0.87 else 1 / 0.87), 2, 600)
				aim()
			end
		end))
		connect(ui.connect(viewport, "InputChanged", function(input: Compose.Node)
			if ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseWheel") then
				distance = math.clamp(distance * (if ui.xyz(input, "Position").Z > 0 then 0.87 else 1 / 0.87), 2, 600)
				aim()
			elseif
				ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseMovement") and drag == nil
			then
				session.hovered:set(pick(Theme.point(input)))
			end
		end))
		connect(ui.connect(UserInputService, "InputChanged", function(input: Compose.Node)
			local active = drag
			if active == nil or ui.get(input, "UserInputType") ~= ui.values.enum("UserInputType", "MouseMovement") then
				return
			end
			local point = Theme.point(input)
			local delta = Math.sub(point, active.from)
			if active.kind == "orbit" then
				yaw -= delta.X * 0.008
				pitch = math.clamp(pitch - delta.Y * 0.008, math.rad(-88), math.rad(88))
				active.from = point
				aim()
			elseif active.kind == "pan" then
				local scale = distance * 0.0016
				local frame = ui.get(camera, "CFrame")
				focus = Math.vadd(
					focus,
					Math.vadd(
						Math.vscale(ui.xyz(frame, "RightVector"), -delta.X * scale),
						Math.vscale(ui.xyz(frame, "UpVector"), delta.Y * scale)
					)
				)
				active.from = point
				aim()
			else
				local axis, origin, start = active.axis, active.origin, active.start
				local selected = nodes[session.selected:peek()]
				if axis and origin and start and selected then
					local rayOrigin, rayDirection = ray(point)
					local along = closestOnAxis(origin, axis, rayOrigin, rayDirection) - start
					if ui.call(UserInputService, "IsKeyDown", ui.values.enum("KeyCode", "LeftControl")) ~= true then
						along = math.round(along)
					end
					local target = Math.vadd(origin, Math.vscale(axis, along))
					translate(selected, target)
					moved = target
					show(selectedBox, session.selected:peek())
					placeGizmo(session.selected:peek())
				end
			end
		end))
		connect(ui.connect(UserInputService, "InputEnded", function(input: Compose.Node)
			local active = drag
			if active == nil then
				return
			end
			local released = ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1")
				or ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton2")
				or ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton3")
			if not released then
				return
			end
			drag = nil
			local target = moved
			moved = nil
			if active.kind == "move" and target then
				local node = Design.document.find(session.document:peek().root, session.selected:peek())
				if node and session.library.kinds[node.kind].fields.position then
					session.change("position", { literal = { target.X, target.Y, target.Z } })
				end
			end
		end))
		return {
			viewport = viewport,
			world = world,
			camera = camera,
			nodes = nodes,
			zoom = zoom,
			fit = fit,
			zoomTo = zoomTo,
			pick = pick,
			dispose = function()
				for _, connection in connections do
					connection:Disconnect()
				end
				if stopDesign then
					stopDesign()
				end
				release()
				ui.destroy(viewport)
			end,
		}
	end
end
