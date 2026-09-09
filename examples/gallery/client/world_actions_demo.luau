--!strict
-- Native scene content for Quick actions; every UI element remains Facet-owned.
local worldAnchor = require(game:GetService("ReplicatedStorage").Facet.client.world_anchor) :: any
local demo = {}
function demo.mount(host: any, showWorld: (boolean) -> (), triggered: () -> ()): any
	local camera = workspace.CurrentCamera
	local savedCamera = { cf = camera.CFrame, kind = camera.CameraType, subject = camera.CameraSubject }
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(0, 1000, 10)
	-- Showcase has CharacterAutoLoads=false. A local invisible viewer gives the
	-- native prompt a proximity origin; it is scene content, not a UI substitute.
	local player = game:GetService("Players").LocalPlayer
	local oldCharacter = player.Character
	local viewer = nil
	if not oldCharacter then
		viewer = Instance.new("Model")
		viewer.Name = "Facet_PromptViewer"
		local root = Instance.new("Part")
		root.Name, root.Anchored, root.Transparency, root.CanCollide = "HumanoidRootPart", true, 1, false
		root.CFrame = camera.CFrame
		root.Parent = viewer
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = viewer
		viewer.PrimaryPart = root
		viewer.Parent = workspace
		player.Character = viewer
	end
	local backdrop = Instance.new("Part")
	backdrop.Name, backdrop.Anchored, backdrop.CanCollide = "Facet_ItemBackdrop", true, false
	backdrop.Size, backdrop.CFrame = Vector3.new(500, 500, 1), CFrame.new(0, 1000, -100)
	backdrop.Color = Color3.fromRGB(28, 38, 43)
	backdrop.Material = Enum.Material.SmoothPlastic
	backdrop.Parent = workspace
	local model = Instance.new("Model")
	model.Name = "Facet_QuickActionsItem"
	local function part(name, size, offset, color)
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame, p.Color = name, size, CFrame.new(offset), color
		p.Anchored, p.CanCollide = true, false
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = model
		return p
	end
	local body = part("TrailPack", Vector3.new(1.2, 1.5, 0.5), Vector3.zero, Color3.fromRGB(42, 111, 114))
	part("Pocket", Vector3.new(0.85, 0.65, 0.25), Vector3.new(0, -0.2, -0.36), Color3.fromRGB(211, 160, 75))
	part("Handle", Vector3.new(0.5, 0.15, 0.2), Vector3.new(0, 0.9, 0), Color3.fromRGB(211, 160, 75))
	model.PrimaryPart = body
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "QuickActionsPrompt"
	prompt.ActionText, prompt.ObjectText = "Actions", "Trail pack"
	prompt.HoldDuration, prompt.MaxActivationDistance = 0, 100
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	local conn = prompt.Triggered:Connect(triggered)
	local stopCamera = host.presenter.onTick(function()
		if workspace.CurrentCamera == camera then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.new(0, 1000, 10)
		end
	end)
	local binding = worldAnchor.new(host, { target = model })
	local disposed, placed, opened = false, false, false
	showWorld(true)
	return {
		anchor = binding.anchor,
		place = function(rect)
			if placed or disposed or not rect or rect.w <= 0 or rect.h <= 0 then
				return
			end
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.new(0, 1000, 10)
			local ray = camera:ViewportPointToRay(rect.x + rect.w / 2, rect.y + rect.h / 2)
			-- Fit the authored prop to the demo pane once; the library then measures
			-- the actual model. Camera motion and model rotation remain live facts.
			local distance = math.max(12, camera.ViewportSize.Y * 1.8 / math.max(55, math.min(100, rect.h * 0.2)))
			local pos = ray.Origin + ray.Direction * distance
			model:PivotTo(CFrame.lookAt(pos, camera.CFrame.Position))
			model.Parent = workspace
			placed = true
		end,
		setOpen = function(value)
			opened = value
			prompt.Enabled = not value
		end,
		turn = function()
			model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(30), 0))
		end,
		resize = function()
			model:ScaleTo(if model:GetScale() > 1 then 1 else 1.35)
		end,
		take = function()
			model.Parent = nil
		end,
		dump = function()
			return {
				anchor = binding.anchor:get(),
				placed = placed,
				open = opened,
				promptEnabled = prompt.Enabled,
				present = model.Parent ~= nil,
			}
		end,
		dispose = function()
			if disposed then
				return
			end
			disposed = true
			stopCamera()
			conn:Disconnect()
			binding.dispose()
			model:Destroy()
			backdrop:Destroy()
			if viewer then
				if player.Character == viewer then
					player.Character = oldCharacter
				end
				viewer:Destroy()
			end
			if workspace.CurrentCamera == camera then
				camera.CFrame, camera.CameraSubject, camera.CameraType =
					savedCamera.cf, savedCamera.subject, savedCamera.kind
			end
			showWorld(false)
		end,
	}
end
return demo
