--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	local fs = require("@lune/fs")
	local process = require("@lune/process")
	local serde = require("@lune/serde")

	local Facet = require("../src") :: any
	local engineLib = require("./lib/native_engine")

	local DIR = process.env.FACET_FOCUS_ATLAS or "tests/fixtures/focus_atlas"
	local DIVERGENCES = DIR .. "/divergences.json"
	local divergences = if fs.isFile(DIVERGENCES) then serde.decode("json", fs.readFile(DIVERGENCES)) else {}

	local KEY_DIRECTION: { [string]: string } = {
		DPadUp = "Up",
		DPadDown = "Down",
		DPadLeft = "Left",
		DPadRight = "Right",
		Up = "Up",
		Down = "Down",
		Left = "Left",
		Right = "Right",
	}

	local function allowed(page: string, from: string, key: string, engine: string?, query: string?): boolean
		for _, entry in divergences do
			if
				entry.page == page
				and entry.from == from
				and entry.key == key
				and entry.engine == (engine or "none")
				and entry.query == (query or "none")
			then
				return true
			end
		end
		return false
	end

	local function replay(atlas: any): (any, { [string]: any }, (offsets: any, scene: any) -> (), () -> ())
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		local parent = engine.new("Folder")
		local UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				guiService = gui,
				inputParent = parent,
				services = { GuiService = gui, UserInputService = input },
			} :: any
		)
		local Vector2 = engine.types.Vector2
		local byPath: { [string]: any } = {}
		local stop, screen: any = runtime.mount(function()
			return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({})
		end, parent)
		screen.AbsoluteSize = Vector2.new(atlas.viewport[1], atlas.viewport[2])
		local frames: { [string]: any } = {}
		local placed: { { node: any, rect: { number }, chain: { string } } } = {}
		local function container(path: string?): any
			if path == nil then
				return screen
			end
			local frame = frames[path]
			if frame == nil then
				local entry = atlas.containers[path]
				frame = engine.new(if entry.scroll then "ScrollingFrame" else "Frame")
				frame.Name = path
				frame.Selectable = entry.selectable == true
				frame.SelectionGroup = entry.behavior ~= nil
				for direction, behavior in entry.behavior or {} do
					frame["SelectionBehavior" .. direction] = (engine.types.Enum.SelectionBehavior :: any)[behavior]
				end
				if entry.owner then
					frame:SetAttribute("FacetSelectionOwner", true)
				end
				frame.AbsoluteSize = Vector2.new(entry.rect[3], entry.rect[4])
				frame.Parent = container(entry.chain[1])
				frames[path] = frame
				table.insert(placed, { node = frame, rect = entry.rect, chain = entry.chain })
			end
			return frame
		end
		for path, entry in atlas.containers do
			local frame = container(path)
			if entry.selectable then
				byPath[path] = frame
			end
		end
		for _, entry in atlas.stops do
			local node = engine.new("Frame")
			node.Name = entry.path
			node.Selectable = true
			node.AbsoluteSize = Vector2.new(entry.rect[3], entry.rect[4])
			if entry.adjustable then
				node:AddTag("facet-adjustable")
				node:SetAttribute("axis", entry.adjustable)
			end
			node.Parent = container(entry.chain[1])
			byPath[entry.path] = node
			table.insert(placed, { node = node, rect = entry.rect, chain = entry.chain })
		end
		for path, entry in atlas.containers do
			if entry.entry then
				for _, stop in atlas.stops do
					if stop.chain[1] == path and string.match(stop.path, "([^/]+)$") == entry.entry then
						frames[path]:SetAttribute("FacetEntry", stop.path)
					end
				end
			end
		end
		for _, entry in atlas.stops do
			for direction, target in entry.links do
				byPath[entry.path]["NextSelection" .. direction] = byPath[target]
			end
		end
		local extras: { [string]: any } = {}
		local function extra(entry: any): any
			local node = extras[entry.path]
			if node == nil then
				node = engine.new("Frame")
				node.Name = entry.path
				node.Selectable = true
				if entry.adjustable then
					node:AddTag("facet-adjustable")
					node:SetAttribute("axis", entry.adjustable)
				end
				node.Parent = container(entry.chain[1])
				extras[entry.path] = node
				byPath[entry.path] = node
			end
			return node
		end
		local function scroll(offsets: any, scene: any)
			for _, item in placed do
				local x, y = item.rect[1], item.rect[2]
				for _, path in item.chain do
					local at = atlas.containers[path].scroll and (offsets or {})[path]
					if at then
						x -= at[1]
						y -= at[2]
					end
				end
				item.node.AbsolutePosition = Vector2.new(x, y)
				item.node.AbsoluteSize = Vector2.new(item.rect[3], item.rect[4])
				item.node.Visible = true
			end
			for _, node in extras do
				node.Visible = false
			end
			if scene == nil then
				return
			end
			for path, rect in scene.rects or {} do
				local node = byPath[path] or frames[path]
				if node then
					node.AbsolutePosition = Vector2.new(rect[1], rect[2])
					node.AbsoluteSize = Vector2.new(rect[3], rect[4])
				end
			end
			for _, path in scene.gone or {} do
				byPath[path].Visible = false
			end
			for _, entry in scene.added or {} do
				local node = extra(entry)
				node.Visible = true
				node.AbsolutePosition = Vector2.new(entry.rect[1], entry.rect[2])
				node.AbsoluteSize = Vector2.new(entry.rect[3], entry.rect[4])
			end
			for _, entry in scene.added or {} do
				for direction, target in entry.links do
					extras[entry.path]["NextSelection" .. direction] = byPath[target]
				end
			end
		end
		scroll(nil, nil)
		gui.SelectedObject = byPath[atlas.stops[1].path]
		return UI, byPath, scroll, function()
			stop()
			runtime:dispose()
		end
	end

	local function load(file: string): any
		local atlas = serde.decode("json", fs.readFile(`{DIR}/{file}`))
		local keys = `{DIR}/{string.sub(file, 1, -6)}--keys.json`
		if fs.isFile(keys) then
			local pass = serde.decode("json", fs.readFile(keys))
			atlas.moves.keys = pass.moves.keys
			atlas.offsets.keys = pass.offsets.keys
			if pass.scenes then
				atlas.scenes = atlas.scenes or {}
				atlas.scenes.keys = pass.scenes.keys
			end
		end
		return atlas
	end

	local function visible(from: any, other: any): boolean
		local at, size = other.AbsolutePosition, other.AbsoluteSize
		local left, top, right, bottom = at.X, at.Y, at.X + size.X, at.Y + size.Y
		local screen = other:FindFirstAncestorWhichIsA("ScreenGui").AbsoluteSize
		local parent = other.Parent
		while parent and parent:IsA("GuiObject") do
			if parent:IsA("ScrollingFrame") then
				if from:IsDescendantOf(parent) then
					return true
				end
				local box, window = parent.AbsolutePosition, parent.AbsoluteSize
				left, top = math.max(left, box.X, 0), math.max(top, box.Y, 0)
				right = math.min(right, box.X + window.X, screen.X)
				bottom = math.min(bottom, box.Y + window.Y, screen.Y)
				if right <= left or bottom <= top then
					return false
				end
			end
			parent = parent.Parent
		end
		return right > 0 and bottom > 0 and left < screen.X and top < screen.Y
	end

	local function ahead(from: any, other: any, direction: string): boolean
		local a, s = from.AbsolutePosition, from.AbsoluteSize
		local b, z = other.AbsolutePosition, other.AbsoluteSize
		if direction == "Up" or direction == "Down" then
			local lane = b.X < a.X + s.X and a.X < b.X + z.X
			if direction == "Up" then
				return b.Y + z.Y < a.Y + s.Y / 2 and (lane or b.Y < a.Y)
			end
			return b.Y > a.Y + s.Y / 2 and (lane or b.Y + z.Y > a.Y + s.Y)
		end
		local lane = b.Y < a.Y + s.Y and a.Y < b.Y + z.Y
		if direction == "Left" then
			return b.X + z.X < a.X + s.X / 2 and (lane or b.X < a.X)
		end
		return b.X > a.X + s.X / 2 and (lane or b.X + z.X > a.X + s.X)
	end

	local function problemsOf(atlas: any): { string }
		local UI, byPath, scroll, done = replay(atlas)
		local first = atlas.stops[1].path
		local seen, queue, head = { [first] = true }, { first }, 1
		local problems = {}
		while queue[head] do
			local path = queue[head]
			head += 1
			scroll(
				(((atlas.offsets or {}).dpad or {})[path] or {}).DPadDown,
				(((atlas.scenes or {}).dpad or {})[path] or {}).DPadDown
			)
			assert(byPath[path], `no stop {path}`)
			for direction, move in UI.focusQuery(byPath[path]) do
				local target = move.target
				if target and atlas.containers[target.Name] then
					for _, entry in atlas.stops do
						if table.find(entry.chain, target.Name) then
							target = byPath[entry.path]
							break
						end
					end
				end
				if target and byPath[target.Name] and not seen[target.Name] then
					seen[target.Name] = true
					table.insert(queue, target.Name)
				end
				if move.rule == "none" and not allowed(atlas.page, path, `dead {direction}`, nil, nil) then
					local from = byPath[path]
					for _, entry in atlas.stops do
						local other = byPath[entry.path]
						if other ~= from and ahead(from, other, direction) and visible(from, other) then
							table.insert(problems, `dead end: {path} {direction}`)
							break
						end
					end
				end
			end
		end
		for _, entry in atlas.stops do
			if not seen[entry.path] and not allowed(atlas.page, entry.path, "reach", nil, nil) then
				table.insert(problems, `unreachable: {entry.path}`)
			end
		end
		for _, family in { "dpad", "keys" } do
			for from, row in atlas.moves[family] or {} do
				for key, engineTarget in row do
					scroll(
						((atlas.offsets[family] or {})[from] or {})[key],
						(((atlas.scenes or {})[family] or {})[from] or {})[key]
					)
					local predicted = UI.focusQuery(byPath[from])[KEY_DIRECTION[key]]
					local query = if predicted.target and predicted.target ~= byPath[from]
						then predicted.target.Name
						else nil
					local entered = query ~= nil
						and atlas.containers[query] ~= nil
						and engineTarget ~= nil
						and string.sub(engineTarget, 1, #query + 1) == query .. "/"
					if
						engineTarget ~= query
						and not entered
						and not allowed(atlas.page, from, key, engineTarget, query)
					then
						table.insert(
							problems,
							`disagree: {from} {key} engine={engineTarget or "none"} query={query or "none"}`
						)
					end
				end
			end
		end
		done()
		return problems
	end

	for _, file in fs.readDir(DIR) do
		if
			file == "divergences.json"
			or string.sub(file, -5) ~= ".json"
			or string.find(file, "--keys.json", 1, true)
		then
			continue
		end
		local atlas = load(file)
		verifyHarness:suite(`focus walk {file}`, function()
			verifyHarness:case("every stop is reachable, no move is a dead end, and the engine's move is the query's", {
				id = "native_focus_walk::"
					.. `focus walk {file}`
					.. "::"
					.. "every stop is reachable, no move is a dead end, and the engine's move is the query's",
				run = function()
					local found = problemsOf(atlas)
					local report = process.env.FACET_FOCUS_WALK_REPORT
					if report and #found > 0 then
						fs.writeFile(`{report}/{file}`, serde.encode("json", { page = atlas.page, problems = found }))
					end
					Verify.expect(found):toEqual({})
				end,
			})
		end)
	end

	if process.env.FACET_FOCUS_ATLAS == nil then
		verifyHarness:suite("M2 named case", function()
			verifyHarness:case("M2: D-pad Up from Boost reaches the Rear slider, live and in the query", {
				id = "native_focus_walk::M2 named case::M2: D-pad Up from Boost reaches the Rear slider, live and in the query",
				run = function()
					local atlas = load("all-controls_inputs_basics.json")
					local root =
						"Gallery/Demos/Content/all-controls/AllControls/Categories/Content/inputs/inputs/Content/basics/AdaptiveScreen/BodyScroll/Body/Settings/SliderShapes/"
					local boost, rear = root .. "Boost", root .. "BalanceRow/Balance"
					local UI, byPath, scroll, done = replay(atlas)
					scroll(atlas.offsets.dpad[boost].DPadUp)
					Verify.expect(atlas.moves.dpad[boost].DPadUp):toBe(rear)
					Verify.expect(UI.focusQuery(byPath[boost]).Up.target):toBe(byPath[rear])
					done()
				end,
			})
		end)
	end

	return nil
end
