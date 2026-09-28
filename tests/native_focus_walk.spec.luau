--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("./lib/testkit")
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

local function replay(atlas: any): (any, { [string]: any }, (offsets: any) -> (), () -> ())
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
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
	local stop, screen = runtime.mount(function()
		return runtime.constructors.ScreenGui({})
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
	for path in atlas.containers do
		container(path)
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
	local function scroll(offsets: any)
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
		end
	end
	scroll(nil)
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
	end
	return atlas
end

local function overlaps(at: any, size: any, box: any, window: any): boolean
	return at.X + size.X > box.X and at.Y + size.Y > box.Y and at.X < box.X + window.X and at.Y < box.Y + window.Y
end

local function visible(from: any, other: any): boolean
	local at, size = other.AbsolutePosition, other.AbsoluteSize
	local parent = other.Parent
	while parent and parent:IsA("GuiObject") do
		if parent:IsA("ScrollingFrame") then
			if from:IsDescendantOf(parent) then
				return true
			end
			if not overlaps(at, size, parent.AbsolutePosition, parent.AbsoluteSize) then
				return false
			end
		end
		parent = parent.Parent
	end
	local screen = other:FindFirstAncestorWhichIsA("ScreenGui")
	return overlaps(at, size, { X = 0, Y = 0 }, screen.AbsoluteSize)
end

local function ahead(from: any, other: any, direction: string): boolean
	local a, s = from.AbsolutePosition, from.AbsoluteSize
	local b, z = other.AbsolutePosition, other.AbsoluteSize
	return (direction == "Up" and b.Y + z.Y <= a.Y + 1)
		or (direction == "Down" and b.Y >= a.Y + s.Y - 1)
		or (direction == "Left" and b.X + z.X <= a.X + 1)
		or (direction == "Right" and b.X >= a.X + s.X - 1)
end

local function problemsOf(atlas: any): { string }
	local UI, byPath, scroll, done = replay(atlas)
	local first = atlas.stops[1].path
	local seen, queue, head = { [first] = true }, { first }, 1
	local problems = {}
	while queue[head] do
		local path = queue[head]
		head += 1
		scroll((((atlas.offsets or {}).dpad or {})[path] or {}).DPadDown)
		assert(byPath[path], `no stop {path}`)
		for direction, move in UI.focusQuery(byPath[path]) do
			local target = move.target
			if target and byPath[target.Name] and not seen[target.Name] then
				seen[target.Name] = true
				table.insert(queue, target.Name)
			end
			if move.rule == "none" then
				local from = byPath[path]
				for _, other in byPath do
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
				scroll(((atlas.offsets[family] or {})[from] or {})[key])
				local predicted = UI.focusQuery(byPath[from])[KEY_DIRECTION[key]]
				local query = if predicted.target and predicted.target ~= byPath[from]
					then predicted.target.Name
					else nil
				if engineTarget ~= query and not allowed(atlas.page, from, key, engineTarget, query) then
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
	if file == "divergences.json" or string.sub(file, -5) ~= ".json" or string.find(file, "--keys.json", 1, true) then
		continue
	end
	local atlas = load(file)
	t.describe(`focus walk {file}`, function()
		t.it("every stop is reachable, no move is a dead end, and the engine's move is the query's", function()
			local found = problemsOf(atlas)
			local report = process.env.FACET_FOCUS_WALK_REPORT
			if report and #found > 0 then
				fs.writeFile(`{report}/{file}`, serde.encode("json", { page = atlas.page, problems = found }))
			end
			t.expect(found).toEqual({})
		end)
	end)
end

if process.env.FACET_FOCUS_ATLAS == nil then
	t.describe("M2 named case", function()
		t.it("M2: D-pad Up from Boost reaches the Rear slider, live and in the query", function()
			local atlas = load("all-controls_inputs_basics.json")
			local root =
				"Gallery/Demos/Content/all-controls/AllControls/Categories/Content/inputs/inputs/Content/basics/AdaptiveScreen/BodyScroll/Body/Settings/SliderShapes/"
			local boost, rear = root .. "Boost", root .. "BalanceRow/Balance"
			local UI, byPath, scroll, done = replay(atlas)
			scroll(atlas.offsets.dpad[boost].DPadUp)
			t.expect(atlas.moves.dpad[boost].DPadUp).toBe(rear)
			t.expect(UI.focusQuery(byPath[boost]).Up.target).toBe(byPath[rear])
			done()
		end)
	end)
end

return nil
