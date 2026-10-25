--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local InputProps = require("./input_props")
local State = require("./collection_reorder_state")
local STACK = 6
local FEEDBACK_Z = 1000
return function<V, K>(
	shared: State.Reorder<V, K>,
	body: ScrollingFrame,
	insideBody: boolean?,
	canvasAt: ComposeTypes.Cell<Vector2>,
	bodyAt: ComposeTypes.Cell<UDim2>
): Frame
	local ctx, spec, gesture = shared.ctx, shared.spec, shared.gesture
	local Compose, Host = ctx.Compose, ctx.Host
	local read = ctx.read
	local D2, V2 = ctx.types.UDim2, ctx.types.Vector2
	local moving, incoming, choosingDestination, drag =
		shared.moving, shared.incoming, shared.choosingDestination, shared.drag
	local source, controls, rowNodes = shared.source, shared.controls, shared.rowNodes
	local grid, horizontal, scaleOf = shared.grid, shared.horizontal, shared.scaleOf
	local axis, crossAxis = shared.axis, shared.crossAxis
	local function dragImage(dropY: (ComposeTypes.Use) -> number): (Frame, number, UDim2)
		local move = assert(moving:peek())
		local source = rowNodes[move.key]
		local index = assert(controls.indexOfKey)(move.key)
		local placement = if index then assert(controls.placementOf)(index) else nil
		local extent = if placement then placement.size else 0
		local nativeSize = if source then source.AbsoluteSize / scaleOf(body) else V2.zero
		local crossSize = if crossAxis(nativeSize) > 0
			then crossAxis(nativeSize)
			elseif placement then placement.crossSize
			else 0
		local previewKeys = { move.key }
		for _, key in move.keys do
			if key ~= move.key then
				table.insert(previewKeys, key)
			end
		end
		local layers = math.min(3, #move.keys)
		local stack = STACK * (layers - 1)
		local function sized(inset: number): UDim2
			return if grid
				then (if horizontal then D2.fromOffset(extent, crossSize) else D2.fromOffset(crossSize, extent))
				elseif horizontal then D2.new(0, extent, 1, -inset)
				else D2.new(1, -inset, 0, extent)
		end
		local imageProps: Types.FrameProps = {
			Name = "DragImage",
			ZIndex = FEEDBACK_Z + 1,
			BackgroundTransparency = 1,
			Interactable = false,
			Size = if grid
				then (if horizontal
					then D2.fromOffset(extent + stack, crossSize + stack)
					else D2.fromOffset(crossSize + stack, extent + stack))
				elseif horizontal then D2.new(0, extent + stack, 1, 0)
				else D2.new(1, 0, 0, extent + stack),
			Position = function(use: ComposeTypes.Use)
				local live = use(moving)
				local base = if horizontal then use(bodyAt).X.Offset else use(bodyAt).Y.Offset
				local window = axis(body.AbsoluteWindowSize) / scaleOf(body)
				local along = if live and live.pointer
					then math.clamp(
						shared.alongBody(body, live.pointer) + base - extent / 2,
						base,
						math.max(base, base + window - extent - stack)
					)
					else dropY(use)
				local across = 0
				if grid then
					local pointer = if live and live.pointer
						then crossAxis(live.pointer - body.AbsolutePosition) / scaleOf(body) - crossSize / 2
						else (if placement then placement.crossOffset else 0)
					if live and live.keyboard then
						local candidate = live.remaining[live.slot + 1]
						local index = if candidate then assert(controls.indexOfKey)(candidate) else #live.rows
						local at = assert(controls.placementOf)(index or 1)
						pointer = at.crossOffset + (if candidate then 0 else at.crossSize) - crossAxis(use(canvasAt))
					end
					across = math.clamp(
						pointer,
						0,
						math.max(0, crossAxis(body.AbsoluteWindowSize) / scaleOf(body) - crossSize - stack)
					)
				end
				return if horizontal then D2.fromOffset(along, across) else D2.fromOffset(across, along)
			end,
			ctx.styled(
				ctx.text({
					Name = "DragLabel",
					ZIndex = FEEDBACK_Z + 2,
					BackgroundTransparency = 0,
					AnchorPoint = V2.new(1, 0),
					Position = D2.fromScale(1, 0),
					Visible = #move.keys > 1,
					Text = function(use: ComposeTypes.Use)
						local live = use(moving)
						if live == nil then
							return ""
						end
						if #live.keys > 1 then
							return tostring(#live.keys) .. " selected"
						end
						local index = assert(controls.indexOfKey)(live.key)
						return if spec.dragLabel and index then spec.dragLabel(live.rows[index]) else tostring(live.key)
					end,
				}),
				"badge"
			),
		}
		local image = Host.Frame(imageProps)
		local top = FEEDBACK_Z + 1
		for layer = layers, 1, -1 do
			local original = rowNodes[previewKeys[layer]] or source
			local parent = if original then original.Parent else nil
			local painted: GuiObject? = if layer == 1 and move.preview
				then move.preview
				elseif parent and parent:IsA("Frame") and parent:HasTag("facet-tablerow") then parent
				else original
			local copy = if painted then painted:Clone() else nil
			if copy then
				local cells = copy:FindFirstChild("Cells", true)
				if cells and cells:IsA("GuiObject") then
					cells.Visible = true
				end
				local row = if copy.Name == "Reorderable" then copy else copy:FindFirstChild("Reorderable", true)
				if row then
					for _, name in { "Move", "SelectMark", "Minus", "Confirm" } do
						local control = row:FindFirstChild(name)
						if control and control:IsA("GuiObject") then
							control.Visible = false
						end
					end
				end
				for _, node in copy:GetDescendants() do
					if node:GetAttribute("FacetDragExclude") == true then
						node:Destroy()
					end
				end
				local nodes = copy:GetDescendants()
				table.insert(nodes, copy)
				local base = top
				for _, node in nodes do
					local rest = node:GetAttribute("FacetDragRestX")
					if type(rest) == "number" and node:IsA("GuiObject") then
						node.Position =
							D2.new(node.Position.X.Scale, rest, node.Position.Y.Scale, node.Position.Y.Offset)
					end
					if node:IsA("GuiObject") then
						node.Interactable, node.Active, node.Selectable = false, false, false
						node.ZIndex += base
						top = math.max(top, node.ZIndex)
					elseif node:IsA("Path2D") then
						node.ZIndex += base
						top = math.max(top, node.ZIndex)
					elseif node:IsA("UIDragDetector") then
						node.Enabled = false
					elseif node:IsA("InputContext") then
						node.Enabled = false
					end
				end
				copy.Name = "Reorderable"
				copy.AnchorPoint = V2.zero
				copy.Position = D2.fromOffset(STACK * (layer - 1), STACK * (layer - 1))
				copy.Size = sized(stack)
				copy.ZIndex = base + 1
				copy.Parent = image
			end
		end
		(image:FindFirstChild("DragLabel") :: GuiObject).ZIndex = top + 1
		return image, top + 2, sized(stack)
	end
	local rootProps: Types.FrameProps = {
		Name = "ReorderFeedback",
		ZIndex = FEEDBACK_Z,
		Position = function(use: ComposeTypes.Use)
			return if insideBody then D2.fromOffset(use(canvasAt).X, use(canvasAt).Y) else D2.fromOffset(0, 0)
		end,
		Size = D2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Attributes = { FacetDragFeedback = true } :: EngineTypes.Attributes,
		Compose.show(function(use)
			return use(incoming) ~= nil
		end, function()
			local function placement(use: ComposeTypes.Use)
				local proposal = use(incoming)
				local rows = read(source, use)
				if #rows == 0 then
					return { offset = 0, size = 44, crossOffset = 0, crossSize = 44 }, true
				end
				local key = proposal and proposal.beforeKey
				local index = if key ~= nil then assert(controls.indexOfKey)(key :: K) else #rows
				return assert(controls.placementOf)(index or #rows), key ~= nil
			end
			return ctx.styled(
				Host.Frame {
					Name = "InsertionLine",
					BorderSizePixel = 0,
					ZIndex = FEEDBACK_Z,
					Size = function(use: ComposeTypes.Use)
						local at = placement(use)
						return if grid
							then (if horizontal then D2.fromOffset(at.size, 2) else D2.fromOffset(2, at.size))
							elseif horizontal then D2.new(0, 2, 1, 0)
							else D2.new(1, 0, 0, 2)
					end,
					Position = function(use: ComposeTypes.Use)
						local at, before = placement(use)
						local offset = if insideBody
							then V2.zero
							else V2.new(use(bodyAt).X.Offset, use(bodyAt).Y.Offset)
						local along = at.offset + (if not grid and not before then at.size else 0) - axis(use(canvasAt))
						local across = if grid
							then at.crossOffset + (if before then 0 else at.crossSize) - crossAxis(use(canvasAt))
							else 0
						return D2.fromOffset(
							offset.X + (if horizontal then along else across),
							offset.Y + (if horizontal then across else along)
						)
					end,
				},
				"drop-line"
			)
		end),
		Compose.show(function(use: ComposeTypes.Use)
			return use(moving) ~= nil
		end, function()
			local function dropY(use: ComposeTypes.Use): number
				local move = use(moving)
				if move == nil then
					return 0
				end
				local candidate = move.remaining[move.slot + 1]
				local index = if candidate then assert(controls.indexOfKey)(candidate) else #move.rows
				local at = assert(controls.placementOf)(index or 1)
				return (if insideBody then 0 elseif horizontal then use(bodyAt).X.Offset else use(bodyAt).Y.Offset)
					+ at.offset
					+ (if candidate then 0 else at.size)
					- axis(use(canvasAt))
			end
			local image, targetZ, frontSize = dragImage(dropY)
			drag.preview(image, body, frontSize)
			image.Visible = false
			local keyboardTargetProps: InputProps.ButtonProps = {
				Name = "Drop",
				label = "Drop",
				Position = D2.new(1, -100, 0, 0),
				Size = D2.fromOffset(100, 40),
				ZIndex = targetZ,
				Visible = function(use: ComposeTypes.Use)
					local move = use(moving)
					return move ~= nil
						and move.keyboard
						and not use(choosingDestination)
						and (spec.onReorder ~= nil or spec.drop ~= nil)
				end,
				onActivate = shared.commit,
			}
			gesture.keyboardTarget = shared.UI.Button(keyboardTargetProps)
			local nativeProps: Types.FrameProps = {
				Name = "DropFeedback",
				ZIndex = FEEDBACK_Z,
				gesture.keyboardTarget :: ComposeTypes.Child,
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ctx.styled(
					Host.Frame "DropLine" {
						Visible = function(use)
							local session = use(drag.state)
							local move = use(moving)
							return (spec.onReorder ~= nil or spec.drop ~= nil)
								and session ~= nil
								and (
									(move and move.keyboard and not use(choosingDestination))
									or (session.target == body and body:GetAttribute("FacetDropState") == "accepted")
								)
						end,
						Size = function(use: ComposeTypes.Use): UDim2
							local move = use(moving)
							if grid and move then
								local candidate = move.remaining[move.slot + 1]
								local index = if candidate then assert(controls.indexOfKey)(candidate) else #move.rows
								local at = assert(controls.placementOf)(index or 1)
								return if horizontal then D2.fromOffset(at.size, 2) else D2.fromOffset(2, at.size)
							end
							return if horizontal then D2.new(0, 2, 1, 0) else D2.new(1, 0, 0, 2)
						end,
						BorderSizePixel = 0,
						ZIndex = FEEDBACK_Z,
						Position = function(use: ComposeTypes.Use)
							local move = use(moving)
							if grid and move then
								local candidate = move.remaining[move.slot + 1]
								local index = if candidate then assert(controls.indexOfKey)(candidate) else #move.rows
								local at = assert(controls.placementOf)(index or 1)
								local along = at.offset - axis(use(canvasAt))
								local across = at.crossOffset
									+ (if candidate then 0 else at.crossSize)
									- crossAxis(use(canvasAt))
								return if horizontal then D2.fromOffset(along, across) else D2.fromOffset(across, along)
							end
							return if horizontal then D2.fromOffset(dropY(use), 0) else D2.fromOffset(0, dropY(use))
						end,
					},
					"divider"
				),
				image,
			}
			return Host.Frame(nativeProps)
		end),
	}
	local root = Host.Frame(rootProps)
	return root
end
