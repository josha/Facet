--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
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

local function press(name: string): Instance?
	local live = (require :: any)(storage:WaitForChild("FacetLive"))
	live.press({ name })
	return GuiService.SelectedObject
end

local function controls(t: any, layer: Instance): { GuiObject }
	local out = {}
	for _, node in layer:GetDescendants() do
		if
			(node:IsA("GuiButton") or node:IsA("TextBox"))
			and node.Selectable
			and node.Interactable
			and t.visible(node)
			and t.clipped(node)
		then
			table.insert(out, node)
		end
	end
	return out
end

local function walk(t: any, id: string, direction: string, limit: number)
	local layer = gallery()
	local shown = api("show", id)
	if not (shown and shown.ok) then
		t.check(`{id} shows`, false, shown)
		return
	end
	t.settle(30)
	local pool = controls(t, layer)
	table.sort(pool, function(a, b)
		if math.abs(a.AbsolutePosition.Y - b.AbsolutePosition.Y) > 4 then
			return a.AbsolutePosition.Y < b.AbsolutePosition.Y
		end
		return a.AbsolutePosition.X < b.AbsolutePosition.X
	end)
	local start: GuiObject? = nil
	for _, node in pool do
		if not node:IsDescendantOf((layer:FindFirstChild("Demos", true) or layer) :: Instance) then
			continue
		end
		start = node
		break
	end
	start = start or pool[1]
	if start == nil then
		t.check(`{id} has a selectable control`, false)
		return
	end
	local delivered = 0
	local watch = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 then
			delivered += 1
		end
	end)
	GuiService.SelectedObject = start
	t.settle(3)
	local visited: { [Instance]: boolean } = { [start] = true }
	local order = { start.Name }
	local lost, stuck = 0, 0
	local previous: GuiObject = start
	for _ = 1, limit do
		local selected = press(direction)
		if selected == nil then
			lost += 1
			break
		end
		if selected == previous then
			stuck += 1
			break
		end
		visited[selected] = true
		table.insert(order, selected.Name)
		previous = selected :: GuiObject
	end
	watch:Disconnect()
	local count = 0
	for _ in visited do
		count += 1
	end
	t.note(
		`{id} {direction} walk`,
		{ order = order, visited = count, pool = #pool, ended = if stuck > 0 then "edge" else "limit" }
	)
	t.check(`{id} {direction} arrives as real Gamepad1 input`, delivered > 0, delivered)
	t.check(`{id} {direction} never drops the selection`, lost == 0, lost)
	t.check(`{id} {direction} moves the selection from control to control`, count >= math.min(3, #pool), count)
	for node in visited do
		t.check(`{id} {node.Name} reached by {direction} is on screen`, t.visible(node :: GuiObject))
	end
	GuiService.SelectedObject = nil
end

local function demos(): { string }
	local screen = (require :: any)(storage:WaitForChild("Gallery"):WaitForChild("screen"))
	local out = {}
	for _, entry in screen.list() do
		table.insert(out, if type(entry) == "table" then entry.id else entry)
	end
	return out
end

add(
	"gallery-dpad-walk",
	{ "apps2-10", "apps2-32", "apps2-43", "apps2-68", "apps2-169", "apps-192", "navigation-3-68" },
	function(t: any)
		for _, id in demos() do
			walk(t, id, "DPadDown", 40)
			walk(t, id, "DPadRight", 12)
		end
	end
)

add("picker-activates-by-pad", { "paint-27" }, function(t: any)
	local layer = gallery()
	api("show", "all-controls")
	t.settle(30)
	local tab: GuiButton? = nil
	for _, node in layer:GetDescendants() do
		if node:IsA("GuiButton") and node.Name == "choices" and t.visible(node) then
			tab = node
			break
		end
	end
	t.check("the Choices tab is on screen", tab ~= nil)
	if tab == nil then
		return
	end
	GuiService.SelectedObject = tab
	t.settle(3)
	press("ButtonA")
	t.settle(20)
	local option: GuiButton?, trigger: GuiButton? = nil, nil
	for _, node in layer:GetDescendants() do
		if node:IsA("GuiButton") and t.visible(node) then
			if option == nil and node:HasTag("facet-segment") and not node:HasTag("facet-segment-current") then
				option = node
			elseif trigger == nil and node:HasTag("facet-disclosure") then
				trigger = node
			end
		end
	end
	t.check("ButtonA on the Choices tab shows its page", option ~= nil and trigger ~= nil)
	if option then
		GuiService.SelectedObject = option
		t.settle(3)
		press("ButtonA")
		t.settle(5)
		t.check(`ButtonA on segment {option.Name} makes it current`, option:HasTag("facet-segment-current"))
	end
	if trigger then
		local fired = 0
		local connection = trigger.Activated:Connect(function()
			fired += 1
		end)
		GuiService.SelectedObject = trigger
		t.settle(3)
		press("ButtonA")
		connection:Disconnect()
		t.check(`ButtonA on the selected {trigger.Name} activates it once`, fired == 1, fired)
		press("ButtonB")
	end
	GuiService.SelectedObject = nil
end)

local MOVES = { "DPadDown", "DPadRight", "DPadLeft", "StickUp" }

local function reach(t: any, id: string)
	local layer = gallery()
	local shown = api("show", id)
	if not (shown and shown.ok) then
		t.check(`{id} shows`, false, shown)
		return
	end
	t.settle(30)
	local pool = controls(t, layer)
	local wanted: { [Instance]: boolean } = {}
	for _, node in pool do
		wanted[node] = true
	end
	local start = pool[1]
	if start == nil then
		t.check(`{id} has a selectable control`, false)
		return
	end
	local reached: { [Instance]: boolean } = { [start] = true }
	local queue = { start }
	local presses, head = 0, 1
	while head <= #queue and presses < 400 do
		local from = queue[head]
		head += 1
		for _, move in MOVES do
			if not (from.Parent and from:IsDescendantOf(layer)) then
				break
			end
			GuiService.SelectedObject = from
			t.settle(2)
			if GuiService.SelectedObject ~= from then
				break
			end
			local landed = press(move)
			presses += 1
			if landed and landed ~= from and landed:IsDescendantOf(layer) and not reached[landed] then
				reached[landed] = true
				table.insert(queue, landed)
			end
		end
	end
	local missing = {}
	for node in wanted do
		if not reached[node] then
			table.insert(missing, node:GetFullName())
		end
	end
	table.sort(missing)
	t.note(`{id} reach`, { pool = #pool, reached = #queue, presses = presses, missing = missing })
	t.check(`{id} every visible control is reachable by D-pad and stick`, #missing == 0, missing)
	GuiService.SelectedObject = nil
end

for _, id in
	{ "all-controls", "collections", "motion-layout", "hud", "radial-menu", "ex02", "ex03", "ex05", "ex06", "ex07" }
do
	add(
		"reach-" .. id,
		{ "apps2-10", "apps2-32", "apps2-43", "apps2-68", "apps2-169", "apps-192", "navigation-3-68" },
		function(t: any)
			reach(t, id)
		end
	)
end

return cases
