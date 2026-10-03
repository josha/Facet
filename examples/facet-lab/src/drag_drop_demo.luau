--!strict
return function(ctx: any)
	local UI, Host, C = ctx.UI, ctx.Host, ctx.Compose
	local D2, V2, V3, CF, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Vector3, ctx.types.CFrame, ctx.types.Enum
	local C3 = ctx.types.Color3
	local palette = {
		Red = C3.fromRGB(245, 92, 97),
		Green = C3.fromRGB(85, 194, 109),
		Blue = C3.fromRGB(76, 159, 245),
		Gray = C3.fromRGB(154, 155, 162),
		None = C3.fromRGB(180, 180, 180),
	}
	local function assets(onStart, onEnd)
		local records =
			{ { id = "portrait", kind = "image", assetId = "rbxassetid://75342910516929", name = "Portrait" } }
		for _, name in { "Red", "Green", "Blue" } do
			table.insert(records, { id = name, kind = "color", value = palette[name], label = name, name = name })
		end
		return UI.VirtualGrid {
			Name = "AppearanceAssets",
			from = records,
			key = "id",
			itemSize = 112,
			columns = 4,
			gap = 8,
			Size = D2.new(1, 0, 0, 120),
			Host.UISizeConstraint { MaxSize = ctx.types.Vector2.new(480, math.huge) },
			drag = function(items)
				return { payload = items[1], operations = { "copy", "apply" }, onStart = onStart, onEnd = onEnd }
			end,
			render = function(current)
				local item = current:peek()
				return UI.VStack {
					Name = "Asset" .. item.id,
					width = "fill",
					padding = "s",
					gap = "s",
					align = "center",
					if item.kind == "image"
						then UI.Image { image = item.assetId, Size = D2.fromOffset(48, 48) }
						else Host.Frame {
							BackgroundColor3 = item.value,
							Size = D2.fromOffset(48, 48),
							Host.UICorner { CornerRadius = ctx.types.UDim.new(0, 8) },
						},
					UI.Text { text = item.name, textRole = "caption" },
				}
			end,
		}
	end

	local env = UI.environment()
	local notice = C.cell("Choose an asset above, then drag it onto an object below.")
	local picked, keyboard = C.cell(nil), C.cell(false)
	local mesh, undo = C.cell(nil), C.cell(nil)
	local angle = C.cell(0)
	local world = ctx.worldTarget
	local camera = world and world.CurrentCamera
	local bounds =
		Host.Frame { Name = "WorldDropArea", Size = D2.fromScale(1, 1), BackgroundTransparency = 1, UI.fill() }
	local block, model
	if world then
		local stop
		stop, model = ctx.runtime.mount(function()
			block = Host.Part {
				Name = "PaintBlock",
				Anchored = true,
				Size = V3.new(3, 3, 3),
				Position = V3.new(-2.5, 6003, 0),
				Color = palette.Gray,
			}
			return Host.Model { Name = "FacetAppearanceWorld", block }
		end, world)
		C.cleanup(stop)
	end
	if ctx.sceneVisible then
		ctx.sceneVisible:set(true)
		C.cleanup(function()
			ctx.sceneVisible:set(false)
		end)
	end
	if camera then
		local oldType, oldFrame, oldFov = camera.CameraType, camera.CFrame, camera.FieldOfView
		local function frame()
			local size = bounds.AbsoluteSize
			if size.X <= 0 or size.Y <= 0 then
				return
			end
			camera.CameraType, camera.FieldOfView = E.CameraType.Scriptable, 55
			local rotate = CF.Angles(0, math.rad(angle:peek()), 0)
			camera.CFrame = CF.new(0, 6003, 20) * rotate
			local function slope(point)
				local ray = camera:ScreenPointToRay(point.X, point.Y)
				local direction = camera.CFrame:VectorToObjectSpace(ray.Direction)
				return V2.new(direction.X / -direction.Z, direction.Y / -direction.Z)
			end
			local first, last = slope(bounds.AbsolutePosition), slope(bounds.AbsolutePosition + size)
			local distance = math.max(11 / (last.X - first.X), 6 / (first.Y - last.Y))
			local middle = slope(bounds.AbsolutePosition + size / 2)
			camera.CFrame = CF.new(0, 6003, 0) * rotate * CF.new(-middle.X * distance, -middle.Y * distance, distance)
		end
		if ctx.runService then
			ctx.runService:BindToRenderStep("FacetAppearanceCamera", E.RenderPriority.Last.Value + 1, frame)
			C.cleanup(function()
				ctx.runService:UnbindFromRenderStep("FacetAppearanceCamera")
			end)
		end
		C.cleanup(function()
			camera.CameraType, camera.CFrame, camera.FieldOfView = oldType, oldFrame, oldFov
		end)
	end
	local alive, meshContent = true, nil
	C.cleanup(function()
		alive = false
		if meshContent then
			meshContent:Destroy()
		end
	end)
	if game and model then
		task.spawn(function()
			local editable
			local ok, result = pcall(function()
				local service = game:GetService("AssetService")
				editable = service:CreateEditableMesh()
				assert(editable, "The mesh memory budget is exhausted")
				local vertices = {
					editable:AddVertex(V3.new(-2, -2, 0)),
					editable:AddVertex(V3.new(2, -2, 0)),
					editable:AddVertex(V3.new(2, 2, 0)),
					editable:AddVertex(V3.new(-2, 2, 0)),
				}
				local uv = {
					editable:AddUV(V2.new(0, 1)),
					editable:AddUV(V2.new(1, 1)),
					editable:AddUV(V2.new(1, 0)),
					editable:AddUV(V2.new(0, 0)),
				}
				local first, second =
					editable:AddTriangle(vertices[1], vertices[2], vertices[3]),
					editable:AddTriangle(vertices[1], vertices[3], vertices[4])
				editable:SetFaceUVs(first, { uv[1], uv[2], uv[3] })
				editable:SetFaceUVs(second, { uv[1], uv[3], uv[4] })
				return service:CreateMeshPartAsync(Content.fromObject(editable))
			end)
			if not alive then
				if ok then
					result:Destroy()
				end
				if editable then
					editable:Destroy()
				end
				return
			end
			if ok then
				result.Name, result.Anchored, result.DoubleSided = "ImageCanvas", true, true
				result.Position, result.Size = V3.new(2.5, 6003, 0), V3.new(4, 4, 0.1)
				result.Parent = model
				meshContent = editable
				mesh:set(result)
			else
				notice:set("The editable mesh could not load: " .. tostring(result))
			end
			if not ok and editable then
				editable:Destroy()
			end
		end)
	end
	local function targetSpec(target, focus)
		return {
			operation = "apply",
			focusTarget = focus,
			accepts = function(payload)
				if type(payload) ~= "table" then
					return false, "Choose a color or an image"
				end
				if payload.kind == "color" then
					return true
				end
				local image = payload.kind == "image"
					or (payload.kind == "files" and #payload.items == 1 and payload.items[1].kind == "Image")
				return image and target:IsA("MeshPart"), "Images need a mesh canvas; colors can paint either object"
			end,
			onUpdate = function(_, info, accepted, reason)
				notice:set(
					if accepted
						then (if info.mode == "armed"
							then "Press Enter or A to apply to the "
							else "Release to apply to the ") .. (if target == block then "block" else "canvas")
						else reason
				)
			end,
			onDrop = function(payload)
				undo:set({
					target = target,
					color = target.Color,
					texture = if target:IsA("MeshPart") then target.TextureID else nil,
				})
				if payload.kind == "color" then
					target.Color = payload.value
				else
					target.TextureID = if payload.kind == "image"
						then payload.assetId
						else payload.items[1].assetId or "rbxassetid://75342910516929"
				end
				notice:set(
					"Applied "
						.. (payload.label or payload.name or "image")
						.. " to the "
						.. (if target == block then "block" else "canvas")
						.. "."
				)
				return true
			end,
			onReject = function(_, reason)
				notice:set(reason or "Drop rejected")
			end,
		}
	end
	local function showDestinations(use)
		return use(keyboard) or use(env.effectiveInput) == "Gamepad"
	end
	local function destination(target, name, title, hint)
		local choice = UI.Button {
			Name = name,
			label = "Apply here",
			Visible = showDestinations,
			enabled = function(use)
				return use(picked) ~= nil
			end,
		}
		UI.dropTarget(target, targetSpec(target, choice))
		return UI.VStack {
			width = "fill",
			gap = "xs",
			align = "center",
			BackgroundTransparency = 1,
			UI.fill(),
			UI.Text { text = title, textRole = "title" },
			UI.Text {
				text = hint,
				textRole = "caption",
				wrap = true,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				TextXAlignment = E.TextXAlignment.Center,
			},
			choice,
		}
	end
	return UI.VStack {
		Name = "DragAndDropDemo",
		BackgroundTransparency = 1,
		UI.fill(),
		width = "fill",
		height = "fill",
		gap = "s",
		padding = "m",
		UI.VStack {
			Name = "WorldTools",
			BackgroundTransparency = 0,
			width = "fill",
			gap = "s",
			ref = function(node)
				node:AddTag("facet-panel")
			end,
			UI.Text {
				text = "Drag and drop demo",
				textRole = "title",
				wrap = true,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			},
			UI.Text {
				text = function(use)
					if use(env.effectiveInput) == "Touch" then
						return "Hold an asset, then drag it onto an object."
					end
					if showDestinations(use) then
						return "Pick up an asset with Enter or A, then choose Apply here. Escape or B cancels."
					end
					return "Drag an image onto the canvas, or a color onto either object. Objects light up when you can drop."
				end,
				wrap = true,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			},
			assets(function(payload, mode)
				picked:set(payload)
				keyboard:set(mode == "armed")
				notice:set(
					"Holding "
						.. (payload.label or payload.name or "asset")
						.. " · "
						.. (if payload.kind == "image" then "Drop on the canvas" else "Drop on either object")
				)
			end, function(accepted, reason)
				picked:set(nil)
				keyboard:set(false)
				if not accepted then
					notice:set(
						if reason == "No destination"
							then "Nothing changed. Release over an object to apply the asset."
							else "Nothing changed. " .. (reason or "Drag cancelled.")
					)
				end
			end),
		},
		bounds,
		UI.HStack {
			Name = "WorldDestinations",
			ref = function(node)
				node:AddTag("facet-panel")
			end,
			BackgroundTransparency = 0,
			width = "fill",
			gap = "m",
			align = "center",
			if block then destination(block, "ChooseBlock", "Block", "Drop a color here") else nil,
			C.show(function(use)
				return use(mesh) ~= nil
			end, function()
				return destination(mesh:peek(), "ChooseCanvas", "Canvas", "Drop an image or color here")
			end),
		},
		UI.HStack {
			Name = "WorldStatus",
			ref = function(node)
				node:AddTag("facet-panel")
			end,
			BackgroundTransparency = 0,
			width = "fill",
			gap = "s",
			align = "center",
			wrap = true,
			UI.Text {
				Name = "DropStatus",
				text = notice,
				wrap = true,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				UI.fill(),
			},
			UI.Button {
				Name = "UndoAppearance",
				label = "Undo",
				enabled = function(use)
					return use(undo) ~= nil
				end,
				onActivate = function()
					local prior = undo:peek()
					if prior and prior.target.Parent then
						prior.target.Color = prior.color
						if prior.texture then
							prior.target.TextureID = prior.texture
						end
					end
					undo:set(nil)
					notice:set("Appearance restored.")
				end,
			},
			UI.Button {
				Name = "ResetAppearance",
				label = "Reset all",
				onActivate = function()
					if block then
						block.Color = palette.Gray
					end
					local canvas = mesh:peek()
					if canvas then
						canvas.TextureID = ""
						canvas.Color = palette.None
					end
					undo:set(nil)
					notice:set("Both objects reset. Drag an asset to try again.")
				end,
			},
		},
	}
end
