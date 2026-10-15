--!strict

local Extended = require(game:GetService("ReplicatedStorage").Shared.Extended)
local Kit = require(script.Parent.Kit)
local E = require(script.Parent.ExtendedKit)
local function mount(playerGui: PlayerGui)
	local api = Extended.client()
	local saved = api.get().livery
	local draft = table.clone(saved)
	local modal, scroll = E.panel(playerGui, "Livery")
	E.label(scroll, "Car preview")
	local preview = Kit.create("ViewportFrame", {
		Size = UDim2.new(1, 0, 0, 160),
		BackgroundColor3 = Kit.colors.card,
		Parent = scroll,
	}) :: ViewportFrame
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(Vector3.new(5, 4, 6), Vector3.zero)
	camera.Parent = preview
	preview.CurrentCamera = camera
	local function part(size: Vector3, position: Vector3): Part
		local object = Instance.new("Part")
		object.Anchored = true
		object.Size = size
		object.Position = position
		object.Parent = preview
		return object
	end
	local body = part(Vector3.new(3, 0.7, 5), Vector3.zero)
	local accent = part(Vector3.new(1.5, 0.6, 2), Vector3.new(0, 0.65, 0))
	for _, x in { -1.6, 1.6 } do
		for _, z in { -1.6, 1.6 } do
			local wheel = part(Vector3.new(0.5, 1, 1), Vector3.new(x, -0.2, z))
			wheel.Color = Color3.fromRGB(20, 20, 24)
		end
	end
	local marks: { Part } = {}
	for index = 1, 6 do
		local mark = part(Vector3.new(0.25, 0.03, 1), Vector3.new((index - 3.5) * 0.4, 0.37, 1.5))
		mark.Color = Color3.new(1, 1, 1)
		table.insert(marks, mark)
	end
	local readout = E.label(scroll, "")
	local status = E.label(scroll, "Saved")
	local function dirty(): boolean
		return draft.body ~= saved.body
			or draft.accent ~= saved.accent
			or draft.shade ~= saved.shade
			or draft.decal ~= saved.decal
	end
	local function render()
		body.Color = Color3.fromHSV(draft.body, 0.85, draft.shade)
		accent.Color = Color3.fromHSV(draft.accent, 0.85, 1)
		local decalIndex = table.find(Extended.decals, draft.decal) or 1
		for index, mark in marks do
			mark.Transparency = if decalIndex == 1 or index > decalIndex then 1 else 0
			mark.Orientation = Vector3.new(0, (decalIndex - 2) * 15, 0)
		end
		readout.Text = ("Preview: Body %.0f Accent %.0f Shade %.0f %s"):format(
			draft.body * 360,
			draft.accent * 360,
			draft.shade * 100,
			draft.decal
		)
		status.Text = if dirty() then "Unsaved changes" else "Saved"
	end
	for _, field in { "body", "accent" } do
		E.label(scroll, if field == "body" then "Body color" else "Accent color")
		local row = Kit.create(
			"Frame",
			{ Size = UDim2.new(1, 0, 0, 104), BackgroundTransparency = 1, Parent = scroll },
			{
				Kit.create(
					"UIGridLayout",
					{ CellSize = UDim2.new(1 / 3, -6, 0, 48), CellPadding = UDim2.fromOffset(8, 8) }
				),
			}
		)
		for index, name in { "Red", "Amber", "Green", "Cyan", "Blue", "Violet" } do
			local hue = (index - 1) / 6
			local control = E.button(row, name, function()
				if field == "body" then
					draft.body = hue
				else
					draft.accent = hue
				end
				render()
			end)
			control.BackgroundColor3 = Color3.fromHSV(hue, 0.85, 0.6)
		end
	end
	E.label(scroll, "Shade")
	local shade = E.label(scroll, "100%")
	for _, value in { 0.5, 0.75, 1 } do
		E.button(scroll, ("Shade %d%%"):format(value * 100), function()
			draft.shade = value
			shade.Text = ("%d%%"):format(value * 100)
			render()
		end)
	end
	E.label(scroll, "Decals")
	local grid = Kit.create("Frame", { Size = UDim2.new(1, 0, 0, 160), BackgroundTransparency = 1, Parent = scroll }, {
		Kit.create("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 48), CellPadding = UDim2.fromOffset(8, 8) }),
	})
	for _, name in Extended.decals do
		E.button(grid, name, function()
			draft.decal = name
			render()
		end)
	end
	E.button(scroll, "Save", function()
		local result = api.request("livery", draft)
		if result.ok then
			saved = table.clone(result.state.livery)
			draft = table.clone(saved)
			render()
		end
	end)
	local confirm = Kit.modal(Kit.screen(playerGui, "Livery"), "Discard", "Confirm")
	local list = Kit.scroller()
	list.Parent = confirm.body
	Kit.list(Enum.FillDirection.Vertical, 8).Parent = list
	E.label(list, "Discard unsaved changes?")
	local closing = false
	E.button(list, "Discard", function()
		draft = table.clone(saved)
		render()
		confirm.setOpen(false)
		if closing then
			modal.setOpen(false)
		end
	end)
	E.button(list, "Cancel", function()
		confirm.setOpen(false)
	end)
	local function leave(close: boolean)
		closing = close
		if false then
			confirm.setOpen(true)
		elseif close then
			modal.setOpen(false)
		end
	end
	E.button(scroll, "Revert", function()
		leave(false)
	end)
	modal.close.Activated:Connect(function()
		if dirty() then
			modal.setOpen(true)
			leave(true)
		end
	end)
	Kit.bindBack(modal, function()
		leave(true)
	end)
	render()
end
return { mount = mount }
