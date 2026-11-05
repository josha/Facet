--!strict

local UI = require "./ui"
local Math = require "./math"

local Compose = require "../core"
local Design = require "../design"

local MAX_DISTANCE = 5000

export type Preset = "fit" | "eye-height" | "approach-20" | "close-up" | "top-down"
export type Target = { world: Compose.Node, camera: Compose.Node, eyeHeight: number? }
export type CameraState = {
	preset: string,
	yaw: number,
	pitch: number,
	distance: number,
	focus: UI.Vector,
	frame: { number },
	fieldOfView: number,
}

export type Scene = {
	viewport: Compose.Node,
	world: Compose.Node,
	camera: Compose.Node,
	nodes: { [string]: Compose.Node },
	zoom: Compose.Value<number>,
	fit: () -> (),
	zoomTo: (scale: number, around: UI.Point?) -> (),
	pick: (point: UI.Point) -> string?,
	preset: Compose.ReadOnlyValue<string>,
	setCamera: (preset: Preset) -> (),
	orbit: (yaw: number, pitch: number) -> (),
	pan: (offset: UI.Point) -> (),
	play: (sequence: string) -> (),
	guides: (enabled: boolean) -> (),
	readCamera: () -> CameraState,
	reframe: () -> (),
	dispose: () -> (),
}

export type Options = {
	target: Target?,
	library: Design.Library?,
	fieldOfView: number?,
	readOnly: boolean?,
	accent: unknown?,
	token: ((name: string) -> Design.Literal)?,
	resolveToken: ((name: string) -> Design.Resolved)?,
	inputs: { [string]: Design.Literal }?,
	bindings: { [string]: Design.Resolved }?,
	outputs: { [string]: (args: { Design.Literal }) -> () }?,
	slots: { [string]: () -> unknown }?,
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
		local library = options.library or session.library
		local accent = options.accent or Theme.color.accent
		local target = options.target
		local viewport = ui.new(if target then "Frame" else "ViewportFrame")
		ui.set(viewport, "Name", "DesignScene")
		ui.set(viewport, "Size", ui.values.udim2(1, 0, 1, 0))
		ui.set(viewport, "BackgroundColor3", Theme.color.canvas)
		ui.set(viewport, "BorderSizePixel", 0)
		if target then
			ui.set(viewport, "BackgroundTransparency", 1)
		else
			ui.set(viewport, "Ambient", ui.rgb(150, 150, 160))
			ui.set(viewport, "LightColor", ui.rgb(255, 250, 240))
			ui.set(viewport, "LightDirection", ui.values.vector3(-1, -2, -0.6))
		end
		ui.set(viewport, "Active", true)
		local world = ui.new(if target then "Model" else "WorldModel")
		ui.set(world, "Name", "DesignWorld")
		ui.set(world, "Parent", if target then target.world else viewport)
		local camera = if target then target.camera else ui.new "Camera"
		local previous: { [string]: unknown } = {}
		if target then
			for _, key in { "CFrame", "Focus", "FieldOfView", "CameraType" } do
				previous[key] = ui.get(camera, key)
			end
		else
			ui.set(camera, "Parent", viewport)
			ui.set(viewport, "CurrentCamera", camera)
		end
		local restoreCamera = Compose.owner.own(ui.owner, function()
			for key, value in previous do
				ui.set(camera, key, value)
			end
		end)
		if target then
			ui.set(camera, "CameraType", ui.values.enum("CameraType", "Scriptable"))
		end
		ui.set(camera, "FieldOfView", options.fieldOfView or (if target then ui.number(camera, "FieldOfView") else 50))
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
		local runtime = ui.runtime
		local stopDesign: (() -> ())? = nil
		local players: { [string]: Design.Player } = {}
		local yaw, pitch, distance, focus = math.rad(35), math.rad(-28), 28, { X = 0, Y = 1, Z = 0 }
		local zoom = Compose.cell(1)
		local preset = Compose.cell "fit"
		local function dimensions(): (UI.Point, UI.Point)
			return if target then ui.xy(camera, "ViewportSize") else ui.xy(viewport, "AbsoluteSize"),
				if target then { X = 0, Y = 0 } else ui.xy(viewport, "AbsolutePosition")
		end
		local function aim()
			local rotation = Math.rotation(pitch, yaw, 0)
			local frame =
				Math.multiply(Math.multiply(Math.frame(focus), rotation), Math.frame { X = 0, Y = 0, Z = distance })
			if target then
				local size = dimensions()
				local center =
					Math.add(ui.xy(viewport, "AbsolutePosition"), Math.scale(ui.xy(viewport, "AbsoluteSize"), 0.5))
				local tangent = math.tan(math.rad(ui.number(camera, "FieldOfView")) / 2)
				frame = Math.multiply(
					frame,
					Math.frame {
						X = (1 - center.X * 2 / math.max(size.X, 1)) * distance * tangent * size.X / math.max(
							size.Y,
							1
						),
						Y = (center.Y * 2 / math.max(size.Y, 1) - 1) * distance * tangent,
						Z = 0,
					}
				)
			end
			ui.set(camera, "CFrame", ui.values.cframe(frame))
			ui.set(camera, "Focus", ui.values.cframe(Math.frame(focus)))
			zoom:set(28 / distance)
		end
		aim()
		local function ray(point: UI.Point): (UI.Vector, UI.Vector)
			local size, origin = dimensions()
			local local2 = Math.sub(point, origin)
			local ndc = { X = local2.X / math.max(size.X, 1) * 2 - 1, Y = 1 - local2.Y / math.max(size.Y, 1) * 2 }
			local tanY = math.tan(math.rad(ui.number(camera, "FieldOfView")) / 2)
			local tanX = tanY * size.X / math.max(size.Y, 1)
			local direction = Math.unit(
				Math.transform(ui.components(ui.get(camera, "CFrame")), { X = ndc.X * tanX, Y = ndc.Y * tanY, Z = -1 })
			)
			return ui.xyz(ui.get(camera, "CFrame"), "Position"), direction
		end
		type Bounds = { left: number, top: number, right: number, bottom: number }
		local function projectedBounds(instance: Compose.Node): Bounds?
			local frame, extent = boundsOf(instance)
			local components = ui.components(frame)
			local origin = ui.xyz(frame, "Position")
			local size, at = dimensions()
			local tanY = math.tan(math.rad(ui.number(camera, "FieldOfView")) / 2)
			local tanX = tanY * size.X / math.max(size.Y, 1)
			local bounds: Bounds = { left = math.huge, top = math.huge, right = -math.huge, bottom = -math.huge }
			for _, x in { -0.5, 0.5 } do
				for _, y in { -0.5, 0.5 } do
					for _, z in { -0.5, 0.5 } do
						local corner = Math.vadd(
							origin,
							Math.transform(components, { X = extent.X * x, Y = extent.Y * y, Z = extent.Z * z })
						)
						local localPoint = ui.vector(
							ui.call(
								ui.get(camera, "CFrame"),
								"PointToObjectSpace",
								ui.values.vector3(corner.X, corner.Y, corner.Z)
							)
						)
						if localPoint.Z < -0.01 then
							local px = at.X + (localPoint.X / -localPoint.Z / tanX + 1) * size.X / 2
							local py = at.Y + (1 - localPoint.Y / -localPoint.Z / tanY) * size.Y / 2
							bounds.left = math.min(bounds.left, px)
							bounds.top = math.min(bounds.top, py)
							bounds.right = math.max(bounds.right, px)
							bounds.bottom = math.max(bounds.bottom, py)
						end
					end
				end
			end
			return if bounds.left < math.huge then bounds else nil
		end
		local function nodeOf(instance: Compose.Node?): string?
			local current = instance
			while current and current ~= world do
				local id = ui.call(current, "GetAttribute", ATTRIBUTE)
				if type(id) == "string" then
					return id
				end
				current = ui.optionalNode(ui.get(current, "Parent"))
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
			local node = if id then Design.document.find(session.document:peek().root, id) else nil
			local position = if node then node.props.position else nil
			local movable = node ~= nil
				and session.library.kinds[node.kind].fields.position ~= nil
				and (position == nil or position.literal ~= nil)
			for part, direction in handles do
				if not movable or instance == nil or ui.get(instance, "Parent") == nil or (id and blocked(id)) then
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
			local excluded: { unknown } = { guides, gizmo }
			for id, instance in nodes do
				if blocked(id) then
					table.insert(excluded, instance)
				end
			end
			local included: { unknown } = {}
			if target then
				for id, instance in nodes do
					if ui.isA(instance, "BasePart") and not blocked(id) then
						table.insert(included, instance)
					end
				end
			end
			local parameters = ui.values.raycastParams(target ~= nil, if target then included else excluded)
			local hit = ui.call(
				if target then target.world else world,
				"Raycast",
				ui.values.vector3(origin.X, origin.Y, origin.Z),
				ui.values.vector3(direction.X * 15000, direction.Y * 15000, direction.Z * 15000),
				parameters
			)
			return if hit then nodeOf(ui.optionalNode(ui.get(hit, "Instance"))) else nil
		end
		local refreshSelection: () -> () = function() end
		local root = Compose.createRootOwner(function()
			Compose.watch(function(use: Compose.Use)
				local value = use(session.document)
				if stopDesign then
					stopDesign()
				end
				table.clear(nodes)
				stopDesign = runtime.mount(function(): Compose.Node
					return ui.node(Design.render(value, library, {
						use = use,
						exclude = function(node: Design.Node): boolean
							return node.hidden == true
						end,
						inputs = options.inputs,
						bindings = options.bindings,
						outputs = options.outputs,
						slots = options.slots,
						players = function(made: { [string]: Design.Player })
							players = made
						end,
						token = options.token,
						resolveToken = options.resolveToken,
						decorate = function(node: Design.Node, subject: unknown)
							local built = ui.node(subject)
							if ui.isA(built, "PVInstance") then
								runtime.decorate(built, { Attributes = { [ATTRIBUTE] = node.id } })
								nodes[node.id] = built
							end
						end,
					}))
				end, world)
			end)
			local selectionBoxes: { [string]: Compose.Node } = {}
			Compose.watch(function(use: Compose.Use)
				use(session.document)
				local id = use(session.selected)
				local ids = use(session.selection)
				for _, box in selectionBoxes do
					ui.destroy(box)
				end
				table.clear(selectionBoxes)
				if #ids > 1 then
					for _, selected in ids do
						if nodes[selected] then
							local box = helper(`Selected_{selected}`, { X = 1, Y = 1, Z = 1 }, accent, 0.95)
							ui.set(box, "Parent", gizmo)
							selectionBoxes[selected] = box
						end
					end
				end
				refreshSelection = function()
					show(selectedBox, id)
					if #ids > 1 then
						local low = { X = math.huge, Y = math.huge, Z = math.huge }
						local high = { X = -math.huge, Y = -math.huge, Z = -math.huge }
						for _, selected in ids do
							local instance = nodes[selected]
							if instance then
								show(selectionBoxes[selected], selected)
								local frame, size = boundsOf(instance)
								local components = ui.components(frame)
								local origin = ui.xyz(frame, "Position")
								for _, x in { -0.5, 0.5 } do
									for _, y in { -0.5, 0.5 } do
										for _, z in { -0.5, 0.5 } do
											local point = Math.vadd(
												origin,
												Math.transform(
													components,
													{ X = size.X * x, Y = size.Y * y, Z = size.Z * z }
												)
											)
											low = {
												X = math.min(low.X, point.X),
												Y = math.min(low.Y, point.Y),
												Z = math.min(low.Z, point.Z),
											}
											high = {
												X = math.max(high.X, point.X),
												Y = math.max(high.Y, point.Y),
												Z = math.max(high.Z, point.Z),
											}
										end
									end
								end
							end
						end
						if low.X < math.huge then
							local center = Math.vscale(Math.vadd(low, high), 0.5)
							local size = Math.vadd(Math.vsub(high, low), { X = 0.15, Y = 0.15, Z = 0.15 })
							ui.set(selectedBox, "CFrame", ui.values.cframe(Math.frame(center)))
							ui.set(selectedBox, "Size", ui.values.vector3(size.X, size.Y, size.Z))
							ui.set(selectedBox, "Transparency", 0.9)
						end
					end
					placeGizmo(id)
				end
				refreshSelection()
			end)
			Compose.watch(function(use: Compose.Use)
				use(session.document)
				local hovered = use(session.hovered)
				show(hoverBox, if hovered and table.find(use(session.selection), hovered) then nil else hovered)
			end)
		end, runtime.reactor)
		local release = Compose.owner.own(ui.owner, root.dispose)
		local function setCamera(chosen: Preset)
			assert(
				chosen == "fit"
					or chosen == "eye-height"
					or chosen == "approach-20"
					or chosen == "close-up"
					or chosen == "top-down",
				"Unknown Camera preset; choose fit, eye-height, approach-20, close-up or top-down"
			)
			local value = session.document:peek()
			local instance = nodes[value.root.id]
			if instance then
				local frame, size = boundsOf(instance)
				focus = ui.xyz(frame, "Position")
				local viewportSize = ui.xy(viewport, "AbsoluteSize")
				local fullSize = dimensions()
				local tangent = math.tan(math.rad(ui.number(camera, "FieldOfView")) / 2)
				local vertical = math.atan(tangent * viewportSize.Y / math.max(1, fullSize.Y))
				local horizontal = math.atan(tangent * viewportSize.X / math.max(1, fullSize.Y))
				distance =
					math.clamp(Math.magnitude(size) * 0.575 / math.sin(math.min(vertical, horizontal)), 6, MAX_DISTANCE)
				yaw, pitch = math.rad(35), math.rad(-28)
				if chosen == "eye-height" or chosen == "approach-20" then
					focus.Y += -size.Y / 2 + (if target then target.eyeHeight or 5.5 else 5.5)
					yaw, pitch = 0, 0
					distance = size.Z / 2 + (if chosen == "approach-20" then 20 else 8)
				elseif chosen == "close-up" then
					distance = math.max(2, distance * 0.55)
				elseif chosen == "top-down" then
					yaw, pitch = 0, math.rad(-90)
				end
			end
			preset:set(chosen)
			aim()
		end
		local function fit()
			setCamera "fit"
		end
		local function orbit(yawDegrees: number, pitchDegrees: number)
			assert(
				yawDegrees == yawDegrees
					and pitchDegrees == pitchDegrees
					and math.abs(yawDegrees) < math.huge
					and math.abs(pitchDegrees) < math.huge,
				"Orbit requires finite angles in degrees"
			)
			yaw, pitch = math.rad(yawDegrees), math.rad(math.clamp(pitchDegrees, -89, 89))
			preset:set "orbit"
			aim()
		end
		local function zoomTo(scale: number, _around: UI.Point?)
			assert(scale > 0 and scale < math.huge, "Zoom requires a finite positive scale")
			distance = math.clamp(28 / math.max(scale, 0.005), 2, MAX_DISTANCE)
			preset:set "custom"
			aim()
		end
		local function pan(offset: UI.Point)
			assert(
				offset.X == offset.X
					and offset.Y == offset.Y
					and math.abs(offset.X) < math.huge
					and math.abs(offset.Y) < math.huge,
				"Pan requires finite pixel offsets"
			)
			preset:set "custom"
			local fullSize = dimensions()
			local scale = distance
				* 2
				* math.tan(math.rad(ui.number(camera, "FieldOfView")) / 2)
				/ math.max(fullSize.Y, 1)
			local frame = ui.get(camera, "CFrame")
			focus = Math.vadd(
				focus,
				Math.vadd(
					Math.vscale(ui.xyz(frame, "RightVector"), -offset.X * scale),
					Math.vscale(ui.xyz(frame, "UpVector"), offset.Y * scale)
				)
			)
			aim()
		end
		local UserInputService = ui.service "UserInputService"
		type Drag = {
			kind: "orbit" | "pan" | "move" | "marquee",
			from: UI.Point,
			axis: UI.Vector?,
			origin: UI.Vector?,
			start: number?,
			origins: { [string]: UI.Vector }?,
			to: UI.Point?,
			base: { string }?,
		}
		local drag: Drag? = nil
		local moved: UI.Vector? = nil
		local marquee = Theme.frame("DesignMarquee", accent)
		ui.set(marquee, "BackgroundTransparency", 0.85)
		ui.set(marquee, "Visible", false)
		ui.set(marquee, "ZIndex", 10)
		Theme.stroke(marquee, accent, 1)
		ui.set(marquee, "Parent", viewport)
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
			if options.readOnly then
				return
			end
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
					if target then target.world else world,
					"Raycast",
					ui.values.vector3(origin.X, origin.Y, origin.Z),
					ui.values.vector3(direction.X * 2000, direction.Y * 2000, direction.Z * 2000),
					parameters
				)
				local axis = if hit and ui.isA(ui.get(hit, "Instance"), "Part")
					then handles[ui.node(ui.get(hit, "Instance"))]
					else nil
				local selected = nodes[session.selected:peek()]
				if axis and selected and not blocked(session.selected:peek()) then
					local origins: { [string]: UI.Vector } = {}
					local ids: { string } = {}
					for _, id in session.selection:peek() do
						local node = Design.document.find(session.document:peek().root, id)
						local covered = false
						for _, ancestor in ids do
							local holder = Design.document.find(session.document:peek().root, ancestor)
							covered = covered or (holder ~= nil and Design.document.find(holder, id) ~= nil)
						end
						if
							node
							and nodes[id]
							and not blocked(id)
							and not covered
							and session.library.kinds[node.kind].fields.position
							and (node.props.position == nil or node.props.position.literal ~= nil)
						then
							table.insert(ids, id)
							origins[id] = ui.xyz(ui.call(nodes[id], "GetPivot"), "Position")
						end
					end
					session.selectMany(ids)
					selected = nodes[session.selected:peek()]
					if selected == nil then
						return
					end
					local pivot = ui.xyz(ui.call(selected, "GetPivot"), "Position")
					drag = {
						kind = "move",
						from = point,
						axis = axis,
						origin = pivot,
						start = closestOnAxis(pivot, axis, origin, direction),
						origins = origins,
					}
					moved = nil
				else
					local id = pick(point)
					if id then
						local modified = ui.keyDown {
							"LeftShift",
							"RightShift",
							"LeftControl",
							"RightControl",
							"LeftMeta",
							"RightMeta",
							"LeftSuper",
							"RightSuper",
						}
						session.select(id, if modified then "toggle" else "replace")
					else
						local modified = ui.keyDown {
							"LeftShift",
							"RightShift",
							"LeftControl",
							"RightControl",
							"LeftMeta",
							"RightMeta",
							"LeftSuper",
							"RightSuper",
						}
						local base = if modified then table.clone(session.selection:peek()) else {}
						drag = { kind = "marquee", from = point, base = base }
						session.selectMany(base)
					end
				end
			elseif ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseWheel") then
				preset:set "custom"
				distance =
					math.clamp(distance * (if ui.xyz(input, "Position").Z > 0 then 0.87 else 1 / 0.87), 2, MAX_DISTANCE)
				aim()
			end
		end))
		connect(ui.connect(viewport, "InputChanged", function(input: Compose.Node)
			if ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseWheel") then
				preset:set "custom"
				distance =
					math.clamp(distance * (if ui.xyz(input, "Position").Z > 0 then 0.87 else 1 / 0.87), 2, MAX_DISTANCE)
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
				preset:set "orbit"
				yaw -= delta.X * 0.008
				pitch = math.clamp(pitch - delta.Y * 0.008, math.rad(-88), math.rad(88))
				active.from = point
				aim()
			elseif active.kind == "marquee" then
				active.to = point
				local at = ui.xy(viewport, "AbsolutePosition")
				ui.set(
					marquee,
					"Position",
					ui.values.udim2(
						0,
						math.min(active.from.X, point.X) - at.X,
						0,
						math.min(active.from.Y, point.Y) - at.Y
					)
				)
				ui.set(marquee, "Size", ui.values.udim2(0, math.abs(delta.X), 0, math.abs(delta.Y)))
				ui.set(marquee, "Visible", true)
			elseif active.kind == "pan" then
				pan(delta)
				active.from = point
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
					if active.origins then
						for id, from in active.origins do
							translate(nodes[id], Math.vadd(from, Math.vscale(axis, along)))
						end
					end
					moved = target
					refreshSelection()
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
			if active.kind == "marquee" then
				ui.set(marquee, "Visible", false)
				local ids = table.clone(active.base or {})
				local point = active.to
				if point and Math.length(Math.sub(point, active.from)) >= 4 then
					local left, right = math.min(point.X, active.from.X), math.max(point.X, active.from.X)
					local top, bottom = math.min(point.Y, active.from.Y), math.max(point.Y, active.from.Y)
					for id, instance in nodes do
						if id ~= session.document:peek().root.id and not blocked(id) then
							local bounds = projectedBounds(instance)
							if
								bounds
								and bounds.left <= right
								and bounds.right >= left
								and bounds.top <= bottom
								and bounds.bottom >= top
							then
								table.insert(ids, id)
							end
						end
					end
				end
				session.selectMany(ids)
				return
			end
			local target = moved
			moved = nil
			if active.kind == "move" and target then
				local node = Design.document.find(session.document:peek().root, session.selected:peek())
				if node and session.library.kinds[node.kind].fields.position then
					local origin = active.origin
					if origin then
						local delta = Math.vsub(target, origin)
						session.change("position", function(current: Design.Node): Design.Value
							local property = current.props.position
							local literal = if property then property.literal else nil
							local x = if type(literal) == "table" then literal[1] else nil
							local y = if type(literal) == "table" then literal[2] else nil
							local z = if type(literal) == "table" then literal[3] else nil
							return {
								literal = {
									(if type(x) == "number" then x else 0) + delta.X,
									(if type(y) == "number" then y else 0) + delta.Y,
									(if type(z) == "number" then z else 0) + delta.Z,
								},
							}
						end)
					end
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
			preset = preset,
			setCamera = setCamera,
			orbit = orbit,
			pan = pan,
			play = function(sequence: string)
				assert(players[sequence], "Unknown Design sequence").play()
			end,
			guides = function(enabled: boolean)
				ui.set(guides, "Parent", if enabled then world else nil)
				ui.set(gizmo, "Parent", if enabled then world else nil)
			end,
			reframe = function()
				local chosen = preset:peek()
				if
					chosen == "fit"
					or chosen == "eye-height"
					or chosen == "approach-20"
					or chosen == "close-up"
					or chosen == "top-down"
				then
					setCamera(chosen)
				else
					aim()
				end
			end,
			readCamera = function(): CameraState
				return {
					preset = preset:peek(),
					yaw = math.deg(yaw),
					pitch = math.deg(pitch),
					distance = distance,
					focus = table.clone(focus),
					frame = ui.components(ui.get(camera, "CFrame")),
					fieldOfView = ui.number(camera, "FieldOfView"),
				}
			end,
			dispose = function()
				for _, connection in connections do
					connection:Disconnect()
				end
				if stopDesign then
					stopDesign()
				end
				release()
				restoreCamera()
				ui.destroy(guides)
				ui.destroy(gizmo)
				ui.destroy(world)
				ui.destroy(viewport)
			end,
		}
	end
end
