--!strict

local Audit = require("./lab_audit")
local Visible = require("./audit_visible")
type ReservedKeys = typeof(require("@repo/src/ui/reserved_keys"))
local Sweep = {}

function Sweep.failure(node: Instance): string?
	local failure = node:GetAttribute("FacetError")
	if type(failure) == "string" and failure ~= "" then
		return failure
	end
	if node:IsA("TextLabel") then
		local text = (node :: TextLabel).Text
		if node.Name == "DestinationError" or string.find(text, "Page failed:", 1, true) then
			return text
		end
	end
	return nil
end

function Sweep.dismissCommand(node: Instance): boolean
	return node:IsA("GuiButton")
		and (
			node.Name == "Close"
			or node.Name == "CloseCommand"
			or node.Name == "Cancel"
			or node.Name == "Done"
			or node.Name == "Collapse"
			or node:GetAttribute("AccessibleLabel") == "Close"
			or node:HasTag("facet-role-cancel")
		)
end

function Sweep.dismissalResult(delivered: boolean, closed: boolean): string?
	return if closed then nil elseif delivered then "faults" else "unsupported"
end

function Sweep.escapeInput(
	input: UserInputService,
	gui: GuiService,
	keys: { [string]: Enum.KeyCode },
	reservedKeys: ReservedKeys,
	send: () -> ()
): boolean
	local delivered = false
	local release = reservedKeys.add(input, keys, {
		keys = { Escape = true },
		priority = math.huge,
		sink = false,
		gui = gui,
		enabled = function()
			return true
		end,
		press = function()
			delivered = true
		end,
		release = function() end,
	})
	local ok, err = pcall(function(): boolean
		send()
		return true
	end)
	release()
	if not ok then
		error(err)
	end
	return delivered
end

function Sweep.controlInput(
	command: string,
	locate: (string) -> GuiButton?,
	press: (GuiButton) -> boolean,
	config: () -> { [string]: string | boolean }
): string
	local sign, flag = string.match(command, "^([%+%-])(.+)$")
	local key, value = string.match(command, "^([^=]+)=(.*)$")
	local name = if sign then `State_{flag}` else `Axis_{key}`
	local node = locate(name)
	if not node or not press(node) then
		return "unsupported"
	end
	if key then
		local optionId = string.gsub(assert(value), "[^%w_%-]", "_")
		local option = locate(optionId)
		if not option then
			return "faults"
		end
		if not press(option) then
			return "unsupported"
		end
	end
	local actual = config()
	local matches = if sign then (actual[`+{flag}`] == true) == (sign == "+") else actual[assert(key)] == value
	return if matches then "passed" else "faults"
end

function Sweep.engineFault(message: string, kind: string): boolean
	return kind == "MessageError" or string.find(message, "unexpectedly tried to set the parent", 1, true) ~= nil
end

function Sweep.sections(page: Instance): { string }
	local sections = {}
	for _, child in page:GetChildren() do
		if
			child:IsA("GuiObject")
			and child.Name ~= "Header"
			and child.Name ~= "Controls"
			and child.Name ~= "Content"
		then
			table.insert(sections, child.Name)
		end
	end
	return sections
end

function Sweep.identity(node: Instance, root: Instance): string
	local parts = {}
	local at: Instance? = node
	while at and at ~= root do
		local parent = at.Parent
		local index = 0
		if parent then
			for _, sibling in parent:GetChildren() do
				if sibling.Name == at.Name then
					index += 1
				end
				if sibling == at then
					break
				end
			end
		end
		table.insert(parts, 1, `{at.Name}[{index}]`)
		at = parent
	end
	return table.concat(parts, ".")
end

function Sweep.scrollStops(scroll: ScrollingFrame): { { x: number, y: number } }
	local x = math.max(0, scroll.AbsoluteCanvasSize.X - scroll.AbsoluteWindowSize.X)
	local y = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
	local positions = { { x = 0, y = 0 } }
	if x > 0 or y > 0 then
		table.insert(positions, { x = x / 2, y = y / 2 })
		table.insert(positions, { x = x, y = y })
	end
	return positions
end

function Sweep.targetVisible(node: Instance, includeOutsideWindow: boolean?): boolean
	local painted = if node:IsA("UIDragDetector") then node.Parent else node
	return painted ~= nil and painted:IsA("GuiObject") and Visible(painted :: GuiObject, includeOutsideWindow)
end

function Sweep.inventory(
	group: Instance,
	page: Instance,
	visibleOnly: boolean?,
	outsideCollections: boolean?
): { [string]: boolean }
	local inventory = {}
	for _, node in group:GetDescendants() do
		if node:IsA("GuiButton") or node:IsA("TextBox") or node:IsA("UIDragDetector") then
			local inside = false
			if outsideCollections then
				local parent = node.Parent
				while parent and parent ~= group do
					if parent:IsA("ScrollingFrame") and parent:HasTag("facet-collection") then
						inside = true
						break
					end
					parent = parent.Parent
				end
			end
			if not inside and (not visibleOnly or Sweep.targetVisible(node)) then
				inventory[Sweep.identity(node, page)] = true
			end
		end
	end
	return inventory
end

function Sweep.options(data: any): { string }
	local commands = {}
	for _, axis in data.axes or {} do
		for _, value in axis.values do
			table.insert(commands, `{axis.key}={tostring(value)}`)
		end
		table.insert(commands, `{axis.key}={tostring(axis.values[1])}`)
	end
	for _, state in data.states or {} do
		if not state.matrixOnly then
			table.insert(commands, `+{state.name}`)
			table.insert(commands, `-{state.name}`)
		end
	end
	return commands
end

function Sweep.snapshot(root: Instance): { string }
	local rows = {}
	for _, node in root:GetDescendants() do
		if node:IsA("GuiObject") then
			local tags = node:GetTags()
			table.sort(tags)
			local text = if node:IsA("TextLabel")
					or node:IsA("TextButton")
					or node:IsA("TextBox")
				then (node :: TextLabel).Text
				else ""
			local path = string.sub(node:GetFullName(), #root:GetFullName() + 2)
			table.insert(
				rows,
				`{path}|{node.ClassName}|{node.Visible}|{node.Size}|{node.Position}|{node.AnchorPoint}|{node.BackgroundTransparency}|{text}|{table.concat(
					tags,
					","
				)}`
			)
		end
	end
	table.sort(rows)
	return rows
end

function Sweep.same(a: { string }, b: { string }): boolean
	return #a == #b and table.concat(a, "\n") == table.concat(b, "\n")
end

function Sweep.difference(a: { string }, b: { string }): { string }
	local old, new, changed = {}, {}, {}
	for _, row in a do
		old[row] = true
	end
	for _, row in b do
		new[row] = true
	end
	for _, row in a do
		if not new[row] and #changed < 10 then
			table.insert(changed, `before: {string.sub(row, 1, 500)}`)
		end
	end
	for _, row in b do
		if not old[row] and #changed < 10 then
			table.insert(changed, `after: {string.sub(row, 1, 500)}`)
		end
	end
	return changed
end

function Sweep.detached(selected: Instance?, root: Instance): boolean
	return selected ~= nil and not selected:IsDescendantOf(root)
end

function Sweep.run(lab: any, playerGui: PlayerGui, ids: { string }, supplied: any?): any
	local deps = supplied or {}
	local modules = game:GetService("ReplicatedStorage"):FindFirstChild("FacetVerify")
	local Verify: any = deps.Verify or (require :: any)(assert(modules):FindFirstChild("core"))
	local InputHost: any = deps.InputHost or (require :: any)(assert(modules):FindFirstChild("roblox")).inputHost
	local input = assert(deps.input or InputHost.native(), "native virtual input is unavailable")
	local wait = deps.wait or task.wait
	local gui = game:GetService("GuiService")
	local frames = game:GetService("RunService")
	local inputService = game:GetService("UserInputService")
	local touchInset: Vector2? = nil
	local virtual = game:GetService("UserInputService"):CreateVirtualInput() :: any
	local observations = {}
	local currentRow: any = nil
	local logged = game:GetService("LogService").MessageOut:Connect(function(message, kind)
		if currentRow and Sweep.engineFault(message, kind.Name) then
			local issue = `engine error: {string.sub(message, 1, 300)}`
			if not table.find(currentRow.faults, issue) then
				table.insert(currentRow.faults, issue)
			end
		end
	end)
	local harness = Verify.createHarness({ now = os.clock, source = "FacetLab/sweep" })
	local function present(node: Instance): boolean
		return node.Parent ~= nil and node:IsA("GuiObject") and Visible(node :: GuiObject)
	end
	local function shown(node: Instance): boolean
		local at: Instance? = node
		while at do
			if at:IsA("GuiObject") and not (at :: GuiObject).Visible then
				return false
			end
			at = at.Parent
		end
		return node.Parent ~= nil
	end
	local function pageFor(id: string): any
		local root = playerGui:FindFirstChild("Facet_Lab")
		return root and root:FindFirstChild(`Page_{id}`, true)
	end
	local function reveal(node: GuiObject)
		gui.SelectedObject = nil
		for _ = 1, 3 do
			local at = node.Parent
			while at do
				if at:IsA("ScrollingFrame") then
					local scroll = at :: ScrollingFrame
					scroll.CanvasPosition = Vector2.new(
						scroll.CanvasPosition.X,
						math.max(0, node.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y - 80)
					)
				end
				at = at.Parent
			end
			frames.PreRender:Wait()
			if present(node) and node.AbsoluteSize.X > 0 and node.AbsoluteSize.Y > 0 then
				break
			end
		end
	end
	local function pointer(point: any, down: boolean)
		input.pointer({ x = point.x, y = point.y, button = "left", down = down })
	end
	local function key(code: string): boolean
		local function send()
			input.key({ code = code, down = true })
			wait(0.02)
			input.key({ code = code, down = false })
			wait(0.02)
		end
		if code == "Escape" then
			local module = game:GetService("ReplicatedStorage")
				:WaitForChild("Facet")
				:WaitForChild("ui")
				:WaitForChild("reserved_keys")
			assert(module:IsA("ModuleScript"))
			local loadModule = (require :: unknown) :: (ModuleScript) -> ReservedKeys
			local reservedKeys: ReservedKeys = deps.reservedKeys or loadModule(module)
			return Sweep.escapeInput(
				inputService,
				gui,
				(Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode },
				reservedKeys,
				send
			)
		end
		send()
		return false
	end
	local function press(node: GuiObject): boolean
		reveal(node)
		if not present(node) or node.AbsoluteSize.X < 1 or node.AbsoluteSize.Y < 1 then
			return false
		end
		local hits = 0
		local connection = if node:IsA("GuiButton")
			then (node :: GuiButton).Activated:Connect(function()
				hits += 1
			end)
			else nil
		local point = InputHost.screenCenter(node)
		if touchInset then
			point = {
				x = node.AbsolutePosition.X + node.AbsoluteSize.X / 2 + touchInset.X,
				y = node.AbsolutePosition.Y + node.AbsoluteSize.Y / 2 + touchInset.Y,
			}
		end
		local calibrated = inputService.InputBegan:Connect(function(event)
			if
				event.UserInputType == Enum.UserInputType.Touch
				or event.UserInputType == Enum.UserInputType.MouseButton1
			then
				touchInset = Vector2.new(point.x - event.Position.X, point.y - event.Position.Y)
			end
		end)
		local ok, err = pcall(function()
			pointer(point, true)
			wait(0.03)
			pointer(point, false)
			wait(0.08)
			if hits == 0 and node:IsA("GuiButton") and node.Parent and touchInset then
				local center = node.AbsolutePosition + node.AbsoluteSize / 2 + touchInset
				point = { x = center.X, y = center.Y }
				pointer(point, true)
				wait(0.03)
				pointer(point, false)
				wait(0.08)
			end
		end)
		calibrated:Disconnect()
		if connection then
			connection:Disconnect()
		end
		if not ok then
			error(err)
		end
		return if node:IsA("GuiButton") then hits > 0 else inputService:GetFocusedTextBox() == node
	end
	local function outsidePress(point: { x: number, y: number }): boolean
		local delivered = false
		local connections: { RBXScriptConnection } = {}
		for _, node in playerGui:GetDescendants() do
			if node.Name == "DismissOutside" and node:IsA("GuiButton") and shown(node) then
				table.insert(
					connections,
					node.Activated:Connect(function()
						delivered = true
					end)
				)
			end
		end
		local ok, err = pcall(function()
			pointer(point, true)
			wait(0.03)
			pointer(point, false)
			wait(0.08)
		end)
		for _, connection in connections do
			connection:Disconnect()
		end
		if not ok then
			error(err)
		end
		return delivered
	end

	local function surfaces(): { any }
		local root = playerGui:FindFirstChild("Facet_Lab")
		local overlays = root and root:FindFirstChild("PreviewOverlays", true)
		local out = {}
		for _, node in playerGui:GetDescendants() do
			if
				node:IsA("GuiObject")
				and shown(node)
				and (
					node.Name == "SheetPanel"
					or node.Name == "RadialPanel"
					or node.Name == "AlertPanel"
					or (overlays ~= nil and node:IsDescendantOf(overlays) and node:HasTag("facet-panel"))
					or node:HasTag("facet-dialog")
					or node:HasTag("facet-popover")
					or node:HasTag("facet-menu")
					or node:HasTag("facet-toast")
				)
			then
				table.insert(out, node)
			end
		end
		return out
	end
	for _, id in ids do
		harness:case(id, {
			id = `lab-sweep::{id}`,
			run = function(context: any)
				local row: any = {
					id = id,
					options = 0,
					pointer = 0,
					keyboard = 0,
					fields = 0,
					drags = 0,
					faults = {},
					unsupported = {},
					disabled = {},
					dismissals = {},
				}
				observations[id] = row
				currentRow = row
				if deps.progress then
					deps.progress(row, false)
				end
				local seen = {}
				local function note(bucket: string, message: string)
					local identity = `{bucket}:{message}`
					if not seen[identity] then
						seen[identity] = true
						table.insert(row[bucket], message)
					end
				end
				local function attempt(label: string, action: any): any
					local ok, answer = pcall(action)
					if not ok then
						note("unsupported", `{label}: {answer}`)
					end
					return if ok then answer else nil
				end
				local function inspect(step: string, changed: Instance?)
					row.step = step
					if deps.progress then
						deps.progress(row, false)
					end
					for where, message in lab.report().errors do
						note("faults", `refused {where}: {message}`)
					end
					local root = playerGui:FindFirstChild("Facet_Lab")
					if root then
						for _, n in root:GetDescendants() do
							local failure = Sweep.failure(n)
							if failure and present(n) then
								note("faults", `destination error: {failure}`)
							end
						end
					end
					if changed and changed:IsA("GuiObject") and changed.Parent and Visible(changed :: GuiObject) then
						local size = (changed :: GuiObject).AbsoluteSize
						if size.X < 1 or size.Y < 1 then
							note("faults", `visible element has zero size: {changed:GetFullName()}`)
						end
					end
					if Sweep.detached(gui.SelectedObject, playerGui) then
						note("faults", `{step}: selection outside PlayerGui`)
					end
					local scope = changed
					while
						scope
						and scope.Parent
						and scope.Parent ~= pageFor(id)
						and not string.match(scope.Name, "^C%d+$")
					do
						scope = scope.Parent
					end
					local page = pageFor(id)
					local audit = Audit(lab, playerGui, { id }, {
						current = true,
						visibleOnly = true,
						node = scope or (page and page:FindFirstChild("Playground")),
					})
					if audit ~= "audit: clean" then
						note("faults", audit)
					end
				end
				local function tidy(mode: string, trigger: GuiObject?)
					local panels = surfaces()
					for _, panel in panels do
						local before = panel:GetFullName()
						local acted = false
						if mode == "close" then
							for _, n in panel:GetDescendants() do
								if n:IsA("GuiButton") and present(n) and Sweep.dismissCommand(n) then
									acted = attempt(before, function()
										return press(n)
									end) == true
									break
								end
							end
						elseif mode == "outside" then
							local root = playerGui:FindFirstChild("Facet_Lab")
							local frame = root and root:FindFirstChild("PreviewRoot", true)
							if frame and frame:IsA("GuiObject") then
								local inset = gui:GetGuiInset()
								local p = frame.AbsolutePosition + Vector2.new(2, frame.AbsoluteSize.Y - 2) + inset
								local a, b = panel.AbsolutePosition + inset, panel.AbsoluteSize
								if p.X < a.X or p.X > a.X + b.X or p.Y < a.Y or p.Y > a.Y + b.Y then
									acted = attempt(before, function()
										return outsidePress({ x = p.X, y = p.Y })
									end) == true
								end
							end
						else
							acted = attempt("Escape", function()
								return key("Escape")
							end) == true
						end
						wait(0.3)
						table.insert(
							row.dismissals,
							{ path = before, mode = mode, sent = acted, closed = not shown(panel) }
						)
						local outcome = Sweep.dismissalResult(acted, not shown(panel))
						if outcome then
							note(outcome, `surface remained open after {mode}: {before}`)
						end
						if shown(panel) then
							if not acted then
								note("unsupported", `{mode}: no available dismissal for {before}`)
							end
							if mode ~= "close" then
								tidy("close", nil)
							end
							if shown(panel) then
								local other = if id == "Button" then "Text" else "Button"
								lab.open(other)
								wait(0.02)
								lab.open(id)
								wait(0.15)
							end
						end
					end
					if #surfaces() == 0 then
						local deadline = os.clock() + 2
						while os.clock() < deadline do
							local pending = false
							for _, n in playerGui:GetDescendants() do
								pending = pending or (n.Name == "DismissOutside" and n:IsA("GuiObject") and shown(n))
							end
							if not pending then
								break
							end
							frames.PreRender:Wait()
						end
						for _, n in playerGui:GetDescendants() do
							if n.Name == "DismissOutside" and n:IsA("GuiObject") and shown(n) then
								note("faults", `{mode}: orphan scrim {n:GetFullName()}`)
							end
						end
					end
				end
				local function reset(): boolean
					local page = pageFor(id)
					local n = page and page:FindFirstChild("Controls") and page.Controls:FindFirstChild("Reset", true)
					return n ~= nil and press(n)
				end
				lab.open(id)
				wait(0.25)
				attempt("initial Reset", reset)
				local first = pageFor(id)
				if not first then
					note("faults", "page did not mount")
					inspect("open")
					if deps.progress then
						deps.progress(row, true)
					end
					context:expect(#row.faults):toBe(0)
					return
				end
				local baseline = first:FindFirstChild("Playground") and Sweep.snapshot(first.Playground.Live) or {}
				local initial = Audit(lab, playerGui, { id }, { current = true })
				if initial ~= "audit: clean" then
					note("faults", initial)
				end
				local data = lab.pages[id].data
				for _, command in Sweep.options(data) do
					local outcome = attempt(command, function()
						return Sweep.controlInput(command, function(name: string): GuiButton?
							local page = pageFor(id)
							local controls = page and page:FindFirstChild("Controls")
							local node = controls and controls:FindFirstChild(name, true)
							if node then
								if node:IsA("GuiButton") then
									return node
								end
								for _, child in node:GetDescendants() do
									if child:IsA("GuiButton") and child:HasTag("facet-disclosure") then
										return child
									end
								end
							end
							for _, panel in surfaces() do
								local item = panel:FindFirstChild(name, true)
								if item and item:IsA("GuiButton") and present(item) then
									return item
								end
							end
							return nil
						end, function(node: GuiButton): boolean
							local delivered = press(node)
							wait(0.3)
							return delivered
						end, function()
							return lab.report().config
						end)
					end)
					if outcome == "passed" then
						row.options += 1
					elseif outcome then
						note(outcome, `Controls input did not apply: {command}`)
					end
					wait(0.05)
					local page = pageFor(id)
					if page and page:FindFirstChild("Playground") then
						reveal(page.Playground)
					end
					inspect(command)
				end
				attempt("Controls Reset", reset)
				wait(0.1)
				local virtualCollection = id == "VirtualGrid" or id == "VirtualList"
				local function visit(
					section: string,
					visibleOnly: boolean,
					region: Instance?,
					outsideCollections: boolean?
				)
					local completed = {}
					local start = assert(pageFor(id))
					local group = region or start:FindFirstChild(section)
					local inventory = if group
						then Sweep.inventory(group, start, visibleOnly, outsideCollections)
						else {}
					while true do
						local page = pageFor(id)
						local group = if region and region.Parent then region else page and page:FindFirstChild(section)
						if not group then
							break
						end
						local target: any = nil
						local identity = ""
						for _, node in group:GetDescendants() do
							if node:IsA("GuiButton") or node:IsA("TextBox") or node:IsA("UIDragDetector") then
								local path = Sweep.identity(node, page)
								if
									inventory[path]
									and not completed[path]
									and Sweep.targetVisible(node, not visibleOnly)
								then
									target, identity = node, path
									break
								end
							end
						end
						if not target then
							break
						end
						completed[identity] = true
						if target:IsA("UIDragDetector") then
							local n = target.Parent
							if n and n:IsA("GuiObject") then
								attempt(identity, function()
									reveal(n)
									local point = InputHost.screenCenter(n)
									if touchInset then
										local center = n.AbsolutePosition + n.AbsoluteSize / 2 + touchInset
										point = { x = center.X, y = center.Y }
									end
									local starts = 0
									local connection = target.DragStart:Connect(function()
										starts += 1
									end)
									pointer(point, true)
									for step = 1, 5 do
										virtual:SendMousePosition(
											Vector2.new(point.x + step * math.min(8, n.AbsoluteSize.X / 12), point.y)
										)
										wait(0.03)
									end
									pointer({ x = point.x + math.min(40, n.AbsoluteSize.X / 2), y = point.y }, false)
									connection:Disconnect()
									if starts > 0 then
										row.drags += 1
									else
										note("unsupported", `drag did not start: {identity}`)
									end
								end)
							end
						elseif target:IsA("TextBox") then
							attempt(identity, function()
								if not press(target) then
									note("unsupported", `field did not focus: {identity}`)
									return
								end
								input.text("4")
								key("Return")
								row.fields += 1
							end)
						else
							if target.Interactable and target.Active then
								for _, mode in { "close", "outside", "escape" } do
									if target.Parent == nil then
										break
									end
									local hit = attempt(identity, function()
										return press(target)
									end)
									if hit then
										row.pointer += 1
									else
										note("unsupported", `press did not activate: {identity}`)
									end
									local opened = #surfaces() > 0
									tidy(mode, target)
									if not opened then
										break
									end
								end
								if target.Parent and target.Selectable then
									attempt(`keyboard {identity}`, function()
										reveal(target)
										gui.SelectedObject = target
										frames.PreRender:Wait()
										local hits = 0
										local connection = target.Activated:Connect(function()
											hits += 1
										end)
										local ok, err = pcall(function()
											key("Return")
											wait(0.08)
										end)
										connection:Disconnect()
										if not ok then
											error(err)
										end
										if hits > 0 then
											row.keyboard += 1
										else
											note("unsupported", `Return did not activate: {identity}`)
										end
									end)
									tidy("close", nil)
								end
							else
								note("disabled", identity)
							end
						end
						inspect(identity, target)
					end
				end
				for _, section in Sweep.sections(assert(pageFor(id))) do
					if not virtualCollection then
						visit(section, false, nil)
					else
						visit(section, false, nil, true)
						local page = pageFor(id)
						local group = page and page:FindFirstChild(section)
						local collections = {}
						for _, node in if group then group:GetDescendants() else {} do
							if node:IsA("ScrollingFrame") and node:HasTag("facet-collection") then
								table.insert(collections, node :: ScrollingFrame)
							end
						end
						if #collections == 0 then
							visit(section, false, nil)
						end
						for _, scroll in collections do
							if not scroll.Parent then
								continue
							end
							reveal(scroll)
							local original = scroll.CanvasPosition
							for index = 1, 3 do
								local position = Sweep.scrollStops(scroll)[index]
								if not position then
									break
								end
								if not scroll.Parent then
									break
								end
								scroll.CanvasPosition = Vector2.new(position.x, position.y)
								wait(0.1)
								visit(section, true, scroll)
								inspect(`{section} window {index}`, scroll)
							end
							if scroll.Parent then
								scroll.CanvasPosition = original
							end
						end
					end
				end
				attempt("final Reset", reset)
				wait(0.35)
				local final = pageFor(id)
				local restored = if final and final:FindFirstChild("Playground")
					then Sweep.snapshot(final.Playground.Live)
					else {}
				row.reset = final ~= nil
					and final:FindFirstChild("Playground") ~= nil
					and Sweep.same(baseline, restored)
				if not row.reset then
					row.resetDifferences = Sweep.difference(baseline, restored)
					note("faults", "Reset structural snapshot differs")
				end
				inspect("Reset")
				if deps.progress then
					deps.progress(row, true)
				end
				context:expect(#row.faults):toBe(0)
				if #row.unsupported > 0 then
					context:skip(`native sweep incomplete: {#row.unsupported} unsupported interactions`)
				end
			end,
		})
	end
	local ok, report = pcall(function()
		return harness:run({ executor = "roblox-client", environment = { tool = "FacetLab/sweep" } })
	end)
	logged:Disconnect()
	input.close()
	if not ok then
		error(report)
	end
	return { pages = observations, report = report }
end

return Sweep
