--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local storage = game:GetService("ReplicatedStorage")

type Case = {
	id: string,
	contracts: { string },
	run: ((any) -> ())?,
	setup: ((any) -> any)?,
	steps: { [string]: (any, any) -> () }?,
	keepGallery: boolean?,
}
local cases: { Case } = {}

local function add(id: string, contracts: { string }, run: (any) -> (), keepGallery: boolean?)
	table.insert(cases, { id = id, contracts = contracts, run = run, keepGallery = keepGallery })
end

local function api(command: string, argument: any): any
	return (workspace:WaitForChild("FacetShowcaseAPI") :: any):Invoke(command, argument)
end

local function gallery(): ScreenGui
	return (Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui):WaitForChild("FacetGallery") :: ScreenGui
end

local function press(name: string): Instance?
	local live = (require :: any)(storage:WaitForChild("FacetLive"))
	live.press({ name })
	return GuiService.SelectedObject
end

local function controls(t: any, layer: Instance): { GuiObject }
	local out: { GuiObject } = {}
	for _, node in layer:GetDescendants() do
		if
			(node:IsA("GuiButton") or node:IsA("TextBox"))
			and node.Selectable
			and node.Interactable
			and t.visible(node)
			and t.clipped(node)
		then
			table.insert(out, node :: GuiObject)
		end
	end
	return out
end

local function walk(t: any, id: string, direction: string, limit: number, seen: { [Instance]: boolean }): number
	local layer = gallery()
	local shown = api("show", id)
	if not (shown and shown.ok) then
		t.check(`{id} shows`, false, shown)
		return 0
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
		return 0
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
	for node in visited do
		seen[node] = true
		t.check(`{id} {node.Name} reached by {direction} is on screen`, t.visible(node :: GuiObject))
	end
	GuiService.SelectedObject = nil
	return #pool
end

local function demos(): { string }
	local screen = (require :: any)(storage:WaitForChild("Gallery"):WaitForChild("screen"))
	local out: { string } = {}
	for _, entry in screen.list() do
		table.insert(out, if type(entry) == "table" then entry.id else entry)
	end
	return out
end

add("gallery-dpad-walk", {}, function(t: any)
	for _, id in demos() do
		local seen: { [Instance]: boolean } = {}
		local pool = math.max(walk(t, id, "DPadDown", 40, seen), walk(t, id, "DPadRight", 12, seen))
		local count = 0
		for _ in seen do
			count += 1
		end
		t.check(`{id} the d-pad moves the selection from control to control`, count >= math.min(3, pool), count)
	end
end)

add("picker-activates-by-pad", {}, function(t: any)
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
	local start: GuiObject? = pool[1]
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
				table.insert(queue, landed :: GuiObject)
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
	add("reach-" .. id, {}, function(t: any)
		reach(t, id)
	end)
end

add("value-control-limit-hands-the-move-to-the-engine", { "input-engine-handoff" }, function(t: any)
	local Compose = t.Facet.Compose
	local value = Compose.cell(8)
	local stage = t.mount(function(UI: any, Host: any)
		return Host.Frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			UI.Button("Before")({
				label = "Before",
				Position = UDim2.fromOffset(40, 100),
				Size = UDim2.fromOffset(120, 44),
			}),
			UI.Stepper("Step")({
				value = value,
				max = 10,
				Position = UDim2.fromOffset(220, 100),
				Size = UDim2.fromOffset(240, 44),
			}),
			UI.Button("After")({
				label = "After",
				Position = UDim2.fromOffset(520, 100),
				Size = UDim2.fromOffset(120, 44),
			}),
		})
	end, { size = Vector2.new(800, 300), frames = 12 })
	local step, before, after = t.find(stage, "Step"), t.find(stage, "Before"), t.find(stage, "After")
	local function selected(): string
		local now = GuiService.SelectedObject
		return if now then now.Name else "nil"
	end
	GuiService.SelectedObject = step
	t.settle(6)
	t.check("in range the stop holds its axis", step.NextSelectionRight == step and step.NextSelectionLeft == step)
	press("DPadRight")
	t.check("Right in range changes the value and keeps the selection", value:peek() == 9 and selected() == "Step", {
		value:peek(),
		selected(),
	})
	press("DPadRight")
	t.check("the value reaches the maximum", value:peek() == 10 and selected() == "Step", { value:peek(), selected() })
	t.check("at the maximum the stop frees Right", step.NextSelectionRight ~= step)
	press("DPadRight")
	t.check("at the maximum the engine moves Right to the next control", selected() == "After", selected())
	t.check("the value stays at the maximum", value:peek() == 10, value:peek())
	value:set(0)
	GuiService.SelectedObject = step
	t.settle(6)
	t.check(
		"at the minimum the stop frees Left and holds Right",
		step.NextSelectionLeft ~= step and step.NextSelectionRight == step
	)
	press("DPadLeft")
	t.check("at the minimum the engine moves Left to the previous control", selected() == "Before", selected())
	value:set(10)
	GuiService.SelectedObject = step
	t.settle(6)
	press("StickRight")
	t.check("at the maximum the stick moves Right to the next control", selected() == "After", selected())
	GuiService.SelectedObject = nil
end)

local function pad(t: any, keys: { string })
	local live = (require :: any)(storage.FacetLive)
	local result = game:GetService("HttpService"):JSONDecode(live.press(keys))
	t.note(table.concat(keys, "+") .. " delivered", result)
	for _, key in keys do
		local seen = false
		for _, input in result.input do
			seen = seen or input == "Gamepad1:" .. key
		end
		t.check(key .. " is delivered as Gamepad1", seen, result.input)
	end
	return result
end

add("pad-table-edit-checkbox-reorder-done", {}, function(t: any)
	local rows, selection
	local stage = t.mount(function(UI: any, _: any, C: any)
		rows = C.cell({
			{ id = "neon", name = "Neon Straightaway" },
			{ id = "drift", name = "Drift City Nights" },
			{ id = "turbo", name = "Turbo Cascade" },
		})
		selection = C.cell({})
		return UI.Table "Tracks" {
			Position = UDim2.fromOffset(60, 80),
			Size = UDim2.fromOffset(600, 360),
			from = rows,
			key = "id",
			selection = selection,
			selectionMode = "multiple",
			reorderable = true,
			onReorder = function(keys: { string }, slot: number)
				local nextRows, moved = {}, {}
				for _, item in rows:peek() do
					if table.find(keys, item.id) then
						table.insert(moved, item)
					else
						table.insert(nextRows, item)
					end
				end
				for index, item in moved do
					table.insert(nextRows, slot + index, item)
				end
				rows:set(nextRows)
			end,
			columns = {
				{
					id = "name",
					label = "Name",
					render = function(item)
						return UI.Text {
							text = function(use)
								return use(item).name
							end,
						}
					end,
				},
			},
		}
	end, { size = Vector2.new(960, 720), frames = 30 })
	local edit = t.find(stage, "Edit")
	GuiService.SelectedObject = edit
	t.settle(3)
	pad(t, { "ButtonA" })
	t.settle(20)
	t.check("ButtonA enters edit mode", edit.ContentText == "Done", edit.ContentText)
	local row = t.find(stage, "Body"):FindFirstChild("neon", true)
	local hit, mark, handle = t.find(row, "RowHit"), t.find(row, "SelectMark"), t.find(row, "Move")
	for _ = 1, 6 do
		if GuiService.SelectedObject == hit then
			break
		end
		pad(t, { "DPadDown" })
	end
	t.check(
		"DPadDown reaches the row checkbox selection target",
		GuiService.SelectedObject == hit,
		GuiService.SelectedObject and GuiService.SelectedObject.Name
	)
	t.check("the checkbox paints in edit mode", t.visible(mark))
	pad(t, { "ButtonA" })
	t.check("ButtonA checks the selected row", selection:peek().neon == true and t.find(mark, "Check").Visible)
	pad(t, { "ButtonA" })
	t.check("ButtonA clears the same checkbox", selection:peek().neon ~= true)
	for _ = 1, 6 do
		if GuiService.SelectedObject == handle then
			break
		end
		pad(t, { "DPadRight" })
	end
	t.check("DPadRight reaches the reorder handle", GuiService.SelectedObject == handle)
	pad(t, { "ButtonA" })
	t.check("ButtonA grabs the row", GuiService.SelectedObject ~= nil and GuiService.SelectedObject.Name == "Drop")
	pad(t, { "DPadDown", "ButtonA" })
	t.check("the row drops one place lower", rows:peek()[2].id == "neon", rows:peek())
	GuiService.SelectedObject = edit
	t.settle(3)
	pad(t, { "ButtonA" })
	t.settle(20)
	t.check("Done leaves edit mode", edit.ContentText == "Edit", edit.ContentText)
	t.check("Done hides the selection mark and reorder handle", not t.visible(mark) and not t.visible(handle))
	GuiService.SelectedObject = nil
end, false)

add("pad-radial-complete-labels-at-each-level", {}, function(t: any)
	local fired = 0
	local stage = t.mount(function(UI: any)
		return UI.RadialMenu "Tools" {
			label = "Tools",
			Position = UDim2.fromOffset(24, 240),
			items = {
				{
					id = "plant",
					label = "Plant a seed",
					children = {
						{
							id = "carrot",
							label = "Plant carrots",
							onSelect = function()
								fired += 1
							end,
						},
						{
							id = "potato",
							label = "Plant potatoes",
							onSelect = function()
								fired += 1
							end,
						},
					},
				},
				{
					id = "harvest",
					label = "Harvest the crop",
					onSelect = function()
						fired += 1
					end,
				},
				{
					id = "plow",
					label = "Plow the field",
					onSelect = function()
						fired += 1
					end,
				},
			} :: { any },
		}
	end, { size = Vector2.new(960, 720), frames = 30 })
	GuiService.SelectedObject = t.find(stage, "Launcher")
	t.settle(3)
	pad(t, { "ButtonA" })
	t.settle(30)
	local function labels(ids: { string })
		for _, id in ids do
			local button = t.find(stage, id)
			t.check(
				id .. " label is complete and visible",
				button ~= nil and t.visible(button) and button.ContentText == button.Text,
				button and button.ContentText
			)
			if button then
				local inset = button:FindFirstChildWhichIsA("UIPadding")
				local padding = if inset
					then inset:GetStyled("PaddingLeft").Offset + inset:GetStyled("PaddingRight").Offset
					else 0
				t.check(
					id .. " has room for the complete caption",
					button.TextBounds.X + padding <= button.AbsoluteSize.X + 1,
					{ button.TextBounds.X, padding, button.AbsoluteSize.X }
				)
			end
		end
	end
	labels({ "plant", "harvest", "plow" })
	GuiService.SelectedObject = t.find(stage, "plant")
	t.settle(3)
	pad(t, { "ButtonA" })
	t.settle(30)
	labels({ "carrot", "potato" })
	GuiService.SelectedObject = t.find(stage, "carrot")
	t.settle(3)
	pad(t, { "ButtonA" })
	t.settle(30)
	t.check("ButtonA runs the selected child once", fired == 1, fired)
	GuiService.SelectedObject = nil
end, false)

add("pad-rating-bounded-marks-and-all-values", {}, function(t: any)
	local value
	local stage = t.mount(function(UI: any, _: any, C: any)
		value = C.cell(0)
		return UI.Rating "Rating" {
			Position = UDim2.fromOffset(80, 120),
			Size = UDim2.fromOffset(180, 44),
			count = 10,
			starSize = "large",
			value = value,
		}
	end, { size = Vector2.new(960, 720), frames = 30 })
	local rating = t.find(stage, "Rating")
	GuiService.SelectedObject = rating
	t.settle(3)
	local marks = 0
	for _, child in rating:GetDescendants() do
		if child:IsA("GuiObject") and string.match(child.Name, "^Level%d+$") then
			marks += 1
			t.check(
				child.Name .. " stays inside the bounded rating",
				t.rect(child).x >= t.rect(rating).x - 1 and t.rect(child).r <= t.rect(rating).r + 1,
				t.rect(child)
			)
		end
	end
	t.check("all ten rating marks paint", marks == 10, marks)
	for index = 1, 10 do
		pad(t, { "DPadRight" })
		t.check("DPadRight reaches value " .. index, value:peek() == index, value:peek())
	end
	for index = 9, 0, -1 do
		pad(t, { "DPadLeft" })
		t.check("DPadLeft reaches value " .. index, value:peek() == index, value:peek())
	end
	GuiService.SelectedObject = nil
end, false)

add("pad-row-actions-menu-open-close-and-command", {}, function(t: any)
	local fired = 0
	local stage = t.mount(function(UI: any)
		return UI.RowActions "Actions" {
			Position = UDim2.fromOffset(80, 140),
			Size = UDim2.fromOffset(500, 60),
			content = function()
				return UI.Button "TrackButton" { label = "Track" }
			end,
			trailing = {
				{
					id = "remove",
					label = "Remove track",
					onActivate = function()
						fired += 1
					end,
				},
			},
		}
	end, { size = Vector2.new(960, 720), frames = 30 })
	local content = t.find(stage, "TrackButton")
	GuiService.SelectedObject = content
	t.settle(3)
	pad(t, { "ButtonX" })
	t.settle(20)
	local layer = stage:FindFirstAncestorWhichIsA("LayerCollector")
	local remove = t.find(layer, "trailing:remove")
	t.check("ButtonX opens the trailing command", remove ~= nil and t.visible(remove))
	pad(t, { "ButtonB" })
	t.settle(20)
	t.check(
		"ButtonB restores row content focus without an action",
		GuiService.SelectedObject == content and fired == 0,
		fired
	)
	pad(t, { "ButtonX" })
	t.settle(20)
	GuiService.SelectedObject = t.find(layer, "trailing:remove")
	t.settle(3)
	pad(t, { "ButtonA" })
	t.settle(40)
	t.check("ButtonA runs the row command exactly once", fired == 1, fired)
	GuiService.SelectedObject = nil
end, false)

return cases
