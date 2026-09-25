--!strict
local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function first(root: Instance, name: string): any
	return root:FindFirstChild(name, true)
end

add("explicit-paint-beats-the-sheet", { "paint-72" }, function(t: any)
	local red = Color3.fromRGB(200, 0, 0)
	local stage = t.mount(function(UI, Host)
		return Host.Frame "Row" {
			Size = UDim2.fromOffset(400, 60),
			BackgroundTransparency = 1,
			Host.UIListLayout { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) },
			UI.Button "Plain" { label = "Plain" },
			UI.Button "Painted" { label = "Painted", BackgroundColor3 = red, BackgroundTransparency = 0 },
		}
	end)
	t.settle(10)
	local plain, painted = first(stage, "Plain"), first(stage, "Painted")
	local sheetColour = plain:GetStyled("BackgroundColor3")
	t.check(
		"the authored colour paints the Button over the sheet",
		painted:GetStyled("BackgroundColor3") == red,
		tostring(painted:GetStyled("BackgroundColor3"))
	)
	t.check(
		"the sheet paints a Button with no authored colour",
		sheetColour ~= red and sheetColour ~= plain.BackgroundColor3,
		{ tostring(sheetColour), tostring(plain.BackgroundColor3) }
	)
end)

add("toggle-follows-a-live-palette", { "paint-76" }, function(t: any)
	local value = t.Facet.Compose.cell(true)
	local context
	local stage = t.mount(function(UI, _, _, ctx)
		context = ctx
		return UI.Toggle "Sound" { label = "Sound", value = value }
	end)
	t.settle(10)
	local node = first(stage, "Sound")
	local package = context.theme:peek()
	local names = {}
	for _, palette in package.style.themes do
		table.insert(names, palette.name)
	end
	t.check("the package has a second palette", #names >= 2, names)
	if #names < 2 then
		return
	end
	local current = context.palette:peek()
	local other = if names[1] == current then names[2] else names[1]
	local before = node:GetStyled("BackgroundColor3")
	context.palette:set(other)
	t.settle(10)
	local after = node:GetStyled("BackgroundColor3")
	t.check(`the on track repaints for {other}`, before ~= after, { tostring(before), tostring(after) })
	t.check("the palette swap leaves the value on", value:peek() == true)
	t.check("the node is the same instance", first(stage, "Sound") == node)
end)

add("alert-title-is-centred", { "navigation-1-37" }, function(t: any)
	local stage = t.mount(function(UI, Host)
		return Host.Frame "Host" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			UI.Alert "Confirm" {
				isPresented = t.Facet.Compose.cell(true),
				title = "Save changes?",
				message = "Your edits stay on this device until you save.",
				actions = { { id = "save", label = "Save" }, { id = "cancel", label = "Cancel", role = "cancel" } },
			},
		}
	end, { size = Vector2.new(800, 600) })
	t.settle(30)
	local title = nil
	for _, node in stage.Parent:GetDescendants() do
		if node:IsA("TextLabel") and node.Text == "Save changes?" and t.visible(node) then
			title = node
		end
	end
	t.check("the alert title is on screen", title ~= nil)
	if title == nil then
		return
	end
	local panel = title.Parent
	while panel and panel:IsA("GuiObject") and panel.AbsoluteSize.X <= title.AbsoluteSize.X + 1 do
		panel = panel.Parent
	end
	local box = t.rect(panel)
	local drawn = title.AbsolutePosition.X + title.AbsoluteSize.X / 2
	local glyphs = title.TextBounds.X
	local left = if title.TextXAlignment == Enum.TextXAlignment.Center
		then drawn - glyphs / 2
		else title.AbsolutePosition.X
	t.near("the title's glyphs are centred in the panel", left + glyphs / 2, box.x + box.w / 2, 1.5)
end)

add("path-strokes-in-theme-roles", { "mech1-38", "themes-P3-18" }, function(t: any)
	for _, theme in t.themes do
		local stage = t.mount(function(UI, Host)
			return Host.Frame "Row" {
				Size = UDim2.fromOffset(300, 80),
				BackgroundTransparency = 1,
				Host.UIListLayout { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) },
				UI.Path "Accent" { points = t.Facet.pathShapes.ring(), role = "accent", thickness = 3, width = 64 },
				UI.Path "Content" { points = t.Facet.pathShapes.needle(45), thickness = 2, width = 64 },
			}
		end, { theme = theme.package, size = Vector2.new(400, 200) })
		t.settle(8)
		local accent = t.find(t.find(stage, "Accent"), "Stroke")
		local content = t.find(t.find(stage, "Content"), "Stroke")
		local palette = theme.package.style.themes[1]
		t.check(
			`{theme.name} accent path takes the accent colour`,
			accent:GetStyled("Color3") ~= content:GetStyled("Color3"),
			{
				tostring(accent:GetStyled("Color3")),
				tostring(content:GetStyled("Color3")),
			}
		)
		t.check(
			`{theme.name} path draws its points`,
			#accent:GetControlPoints() == 9 and #content:GetControlPoints() == 2
		)
		t.near(`{theme.name} path box is 64 px`, t.find(stage, "Accent").AbsoluteSize.X, 64, 0.5)
		t.check(`{theme.name} palette known`, palette ~= nil)
		t.cleanup()
	end
end)

return cases
