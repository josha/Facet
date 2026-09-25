--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local storage = game:GetService("ReplicatedStorage")

local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function api(command: string, argument: any): any
	return (workspace:WaitForChild("FacetShowcaseAPI") :: any):Invoke(command, argument)
end

local function gallery(): ScreenGui
	return Players.LocalPlayer.PlayerGui:WaitForChild("FacetGallery") :: ScreenGui
end

local function demos(): { string }
	local screen = (require :: any)(storage:WaitForChild("Gallery"):WaitForChild("screen"))
	local out = {}
	for _, entry in screen.list() do
		table.insert(out, if type(entry) == "table" then entry.id else entry)
	end
	return out
end

local function blocked(node: Instance): boolean
	local at: Instance? = node
	while at and at:IsA("GuiObject") do
		if not at.Interactable then
			return true
		end
		at = at.Parent
	end
	return false
end

local function sweep(t: any, where: string)
	local layer = gallery()
	local bounds = t.rect(layer)
	local totals = { demos = 0, selectable = 0, accepted = 0, refused = 0, clipped = 0, lateral = 0 }
	for _, id in demos() do
		local shown = api("show", id)
		if not (shown and shown.ok) then
			t.check(`{where} {id} shows`, false, shown)
			continue
		end
		t.settle(30)
		totals.demos += 1
		local bad = t.offenders(layer, bounds)
		totals.clipped += #bad.clipped
		totals.lateral += #bad.lateral
		t.check(`{where} {id} draws no control past the screen sides`, #bad.lateral == 0, bad.lateral)
		t.check(`{where} {id} cuts no unwrapped text`, #bad.clipped == 0, bad.clipped)
		for _, node in layer:GetDescendants() do
			if
				(node:IsA("GuiButton") or node:IsA("TextBox"))
				and node.Selectable
				and t.visible(node)
				and t.clipped(node)
			then
				GuiService.SelectedObject = node
				t.settle(1)
				local took = GuiService.SelectedObject == node
				if blocked(node) then
					totals.refused += if took then 0 else 1
					t.check(`{where} {id} {node.Name} refuses selection under a blocked ancestor`, not took)
				else
					totals.selectable += 1
					totals.accepted += if took then 1 else 0
					t.check(`{where} {id} {node.Name} accepts selection`, took)
				end
			end
		end
		GuiService.SelectedObject = nil
		local collapsed = {}
		for _, node in layer:GetDescendants() do
			if
				node:IsA("GuiObject")
				and not node:IsA("ScrollingFrame")
				and (node:IsA("GuiButton") or node:IsA("TextBox") or node.Selectable)
				and t.visible(node)
			then
				local at = node.Parent
				while at and at ~= layer and at:IsA("GuiObject") do
					if not at:IsA("ScrollingFrame") and (at.AbsoluteSize.X < 1 or at.AbsoluteSize.Y < 1) then
						table.insert(collapsed, node:GetFullName())
						break
					end
					at = at.Parent
				end
			end
		end
		t.check(`{where} {id} collapses no visible control to zero size`, #collapsed == 0, collapsed)
	end
	t.note(where .. " totals", totals)
	t.check(`{where} swept every demo`, totals.demos >= 10, totals.demos)
end

add("demo-sweep-desktop", {}, function(t: any)
	sweep(t, "desktop")
end)

add("demo-sweep-phone", {}, function(t: any)
	t.device({ device = "iphone_14", orientation = Enum.ScreenOrientation.Portrait, restore = "xbox" })
	sweep(t, "phone")
end)

add("disabled-subtree", {}, function(t: any)
	local stage = t.mount(function(UI, Host)
		return Host.Frame "Area" {
			Size = UDim2.fromOffset(400, 300),
			Interactable = false,
			UI.Button "Inner" { label = "Inside" },
			UI.Toggle "Check" { label = "Option", value = t.Facet.Compose.cell(false) },
		}
	end)
	t.settle(10)
	for _, name in { "Inner", "Check" } do
		local node = t.find(stage, name)
		local target = if node and node:IsA("GuiButton")
			then node
			else node and node:FindFirstChildWhichIsA("GuiButton", true)
		if target then
			t.check(
				`{name} under a non-interactable ancestor takes no input`,
				not target.Interactable or blocked(target)
			)
		else
			t.check(`{name} mounted`, false)
		end
	end
end)

local function scrollers(t: any, where: string)
	local layer = gallery()
	local count = 0
	for _, id in demos() do
		local shown = api("show", id)
		if not (shown and shown.ok) then
			continue
		end
		t.settle(30)
		for _, frame in layer:GetDescendants() do
			if frame:IsA("ScrollingFrame") and t.visible(frame) and frame.AbsoluteWindowSize.Y > 0.5 then
				local extent = 0
				for _, child in frame:GetChildren() do
					if child:IsA("GuiObject") and child.Visible then
						extent = math.max(
							extent,
							child.AbsolutePosition.Y
								- frame.AbsolutePosition.Y
								+ frame.CanvasPosition.Y
								+ child.AbsoluteSize.Y
						)
					end
				end
				count += 1
				t.check(
					`{where} {id} {frame.Name} canvas holds its content`,
					frame.AbsoluteCanvasSize.Y + 1 >= extent
						or frame.AbsoluteCanvasSize.Y + 1 >= frame.AbsoluteWindowSize.Y
							and extent <= frame.AbsoluteWindowSize.Y + 1,
					{ canvas = frame.AbsoluteCanvasSize.Y, content = extent, window = frame.AbsoluteWindowSize.Y }
				)
				local before = frame.CanvasPosition
				frame.CanvasPosition = Vector2.new(before.X, frame.AbsoluteCanvasSize.Y)
				t.settle(2)
				local bottom = frame.CanvasPosition.Y + frame.AbsoluteWindowSize.Y
				t.check(
					`{where} {id} {frame.Name} scrolls to its content end`,
					bottom + 1 >= math.min(extent, frame.AbsoluteCanvasSize.Y),
					{ bottom = bottom, content = extent }
				)
				frame.CanvasPosition = before
			end
		end
	end
	t.note(where .. " scrollers", count)
	t.check(`{where} found scrollers`, count > 0, count)
end

add("scroll-sweep-desktop", {}, function(t: any)
	scrollers(t, "desktop")
end)

add("theme-sweep", {}, function(t: any)
	local layer = gallery()
	local bounds = t.rect(layer)
	local count = 0
	for _, entry in t.themes do
		local applied = api("theme", entry.name)
		if not (applied and applied.ok ~= false) then
			continue
		end
		for _, id in { "all-controls", "collections" } do
			api("show", id)
			t.settle(30)
			local bad = t.offenders(layer, bounds)
			count += 1
			t.check(`{entry.name} {id} draws no control past the screen sides`, #bad.lateral == 0, bad.lateral)
			t.check(`{entry.name} {id} cuts no unwrapped text`, #bad.clipped == 0, bad.clipped)
		end
	end
	api("theme", "Neutral")
	t.note("theme screens", count)
	t.check("swept every theme", count >= 8, count)
end)

local function owningButton(node: Instance?): Instance?
	local at = node
	while at and at:IsA("GuiObject") do
		if at:IsA("GuiButton") or at:IsA("TextBox") then
			return at
		end
		at = at.Parent
	end
	return nil
end

local function clicks(t: any, where: string)
	local input = game:GetService("UserInputService")
	local virtual = (input :: any):CreateVirtualInput()
	t.check(`{where} virtual input is available`, virtual ~= nil)
	if not virtual then
		return
	end
	local LogService = game:GetService("LogService")
	local errors = {}
	local watch = LogService.MessageOut:Connect(function(message, kind)
		if kind == Enum.MessageType.MessageError then
			table.insert(errors, message)
		end
	end)
	local inset = GuiService:GetGuiInset()
	local playerGui = Players.LocalPlayer.PlayerGui
	local layer = gallery()
	local bounds = t.rect(layer)
	local totals = { clicked = 0, typed = 0, covered = 0 }
	for _, id in demos() do
		api("show", id)
		t.settle(30)
		local visited = {}
		local function reveal(node: any)
			local at = node.Parent
			while at and at ~= layer do
				if at:IsA("ScrollingFrame") then
					local window = at.AbsoluteWindowSize
					local offset = node.AbsolutePosition - at.AbsolutePosition
					local canvas = at.CanvasPosition
					local x, y = canvas.X, canvas.Y
					if offset.Y < 0 or offset.Y + node.AbsoluteSize.Y > window.Y then
						y = math.max(0, canvas.Y + offset.Y - (window.Y - node.AbsoluteSize.Y) / 2)
					end
					if offset.X < 0 or offset.X + node.AbsoluteSize.X > window.X then
						x = math.max(0, canvas.X + offset.X - (window.X - node.AbsoluteSize.X) / 2)
					end
					if x ~= canvas.X or y ~= canvas.Y then
						at.CanvasPosition = Vector2.new(x, y)
					end
				end
				at = at.Parent
			end
		end
		local function hittable(node: any): Vector2?
			if not node.Parent or not t.visible(node) or node.AbsoluteSize.X < 1 then
				return nil
			end
			if
				not t.clipped(node)
				or t.clipped(node).w < node.AbsoluteSize.X - 1
				or t.clipped(node).h < node.AbsoluteSize.Y - 1
			then
				reveal(node)
				t.settle(2)
			end
			local seen = t.clipped(node)
			if not seen or seen.x < bounds.x or seen.r > bounds.r or seen.y < bounds.y or seen.b > bounds.b then
				return nil
			end
			local centre = Vector2.new(seen.x + seen.w / 2, seen.y + seen.h / 2)
			for _, hit in playerGui:GetGuiObjectsAtPosition(centre.X, centre.Y) do
				local owner = owningButton(hit)
				if owner then
					return if owner == node then centre else nil
				elseif hit.Active then
					return nil
				end
			end
			return nil
		end
		for _ = 1, 400 do
			local node, centre = nil, nil
			for _, candidate in layer:GetDescendants() do
				if (candidate:IsA("GuiButton") or candidate:IsA("TextBox")) and not visited[candidate] then
					local spot = hittable(candidate)
					if spot then
						node, centre = candidate, spot
						break
					end
				end
			end
			if not node or not centre then
				break
			end
			visited[node] = true
			local at = centre + inset
			local before = #errors
			pcall(function()
				virtual:SendMousePosition(at)
				virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, true)
				virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, false)
			end)
			t.settle(4)
			if node:IsA("TextBox") and node:IsFocused() then
				pcall(function()
					virtual:SendTextInput("Probe")
					virtual:SendKey(true, Enum.KeyCode.Return, false)
					virtual:SendKey(false, Enum.KeyCode.Return, false)
				end)
				t.settle(4)
				totals.typed += 1
			end
			t.settle(12)
			totals.clicked += 1
			if #errors > before then
				t.check(`{where} {id} {node.Name} click raises no error`, false, { table.unpack(errors, before + 1) })
			end
		end
		local failed = {}
		for _, node in layer:GetDescendants() do
			if node:IsA("TextLabel") and t.visible(node) and string.find(node.Text, " stopped$") then
				table.insert(failed, node:GetFullName())
			end
		end
		t.check(`{where} {id} shows no failure screen after every click`, #failed == 0, failed)
	end
	watch:Disconnect()
	t.note(where .. " clicks", totals)
	t.check(`{where} clicked controls`, totals.clicked > 100, totals)
	t.check(`{where} raised no script error while clicking`, #errors == 0, errors)
end

add("click-sweep-desktop", {}, function(t: any)
	clicks(t, "desktop")
end)

add("click-sweep-phone", {}, function(t: any)
	t.device({ device = "iphone_14", orientation = Enum.ScreenOrientation.Portrait, restore = "xbox" })
	clicks(t, "phone")
end)

return cases
