--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local context = require("../src/ui/context")
local register = require("../src/ui/inputs")
local bindThemes = require("../src/ui/themes")
local engineLib = require("./lib/native_engine")
local expect = t.expect

local function find(root: any, name: string): any
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function world(build: (any, any) -> any, theme: any?): any
	local engine: any = engineLib.new()
	local runtime = Roblox.createRuntime(engine)
	local UI: any = {}
	local gui = engine.new("GuiService")
	local held: { [string]: boolean } = {}
	local input = setmetatable({
		IsKeyDown = function(_, key)
			return held[key.Name] == true
		end,
		GetFocusedTextBox = function()
			return nil
		end,
	}, {
		__index = function(_, key)
			local real = engine.new("UserInputService")
			local value = real[key]
			if type(value) == "function" then
				return function(_, ...)
					return value(real, ...)
				end
			end
			return value
		end,
	})
	register(
		context(Compose, runtime, {
			types = engine.types,
			theme = theme,
			services = { GuiService = gui, UserInputService = input :: any },
			guiService = gui,
		}),
		UI
	)
	local screen = engine.new("ScreenGui")
	local stop = runtime.mount(function()
		return build(UI, runtime.constructors)
	end, screen)
	return { engine = engine, gui = gui, held = held, screen = screen, stop = stop, E = engine.types.Enum }
end

local function action(w: any, name: string): any
	for _, child in w.screen:GetChildren() do
		if child:IsA("InputContext") and child.Enabled then
			local found = child:FindFirstChild(name)
			if found then
				return found
			end
		end
	end
	return nil
end

local function tagWorld(theme: any?, rung: string?): any
	local state = { selected = Compose.cell(false), editing = Compose.cell(false), removes = 0 }
	local w = world(function(UI)
		return UI.Chip("Tag")({
			label = "Rain",
			selected = state.selected,
			editing = state.editing,
			controlSize = rung,
			onRemove = function()
				state.removes += 1
			end,
		})
	end, theme)
	w.state = state
	w.tag = find(w.screen, "Tag")
	return w
end

local function activate(w: any, input: string)
	if input == "pointer" or input == "touch" then
		w.tag.Activated.fire({
			UserInputType = if input == "pointer" then w.E.UserInputType.MouseButton1 else w.E.UserInputType.Touch,
		}, 1)
	else
		w.gui.SelectedObject = w.tag
		local found = action(w, "Activate")
		found.Pressed.fire()
		found.Released.fire()
	end
end

t.describe("native Chip edit mode", function()
	for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
		t.it(
			"a tag selects with no mark; editing shows the mark in its plate and activation removes, via " .. input,
			function()
				local w = tagWorld()
				local mark = find(w.tag, "Remove")
				expect(mark.Visible).toBe(false)
				activate(w, input)
				expect(`{w.state.selected:peek()} {w.state.removes}`).toBe("true 0")
				w.state.editing:set(true)
				expect(mark.Visible).toBe(true)
				expect(mark:IsDescendantOf(w.tag)).toBe(true)
				expect(mark:IsA("TextLabel")).toBe(true)
				expect(w.tag:GetAttribute("AccessibleLabel")).toBe("Remove Rain")
				activate(w, input)
				expect(`{w.state.selected:peek()} {w.state.removes}`).toBe("true 1")
				w.stop()
			end
		)
	end

	t.it("Delete and Backspace remove the focused tag only while editing", function()
		for _, key in { "Delete", "Backspace" } do
			local w = tagWorld()
			w.gui.SelectedObject = w.tag
			expect(`{key} resting {action(w, "RemoveChip") == nil}`).toBe(`{key} resting true`)
			w.state.editing:set(true)
			local remove = action(w, "RemoveChip")
			local keys = {}
			for _, binding in remove:GetChildren() do
				table.insert(keys, binding.KeyCode.Name)
			end
			table.sort(keys)
			expect(table.concat(keys, " ")).toBe("Backspace ButtonX Delete")
			remove.Pressed.fire()
			remove.Released.fire()
			expect(`{key} editing {w.state.removes}`).toBe(`{key} editing 1`)
			w.stop()
		end
	end)

	t.it("one plate in skinned themes: the mark is text inside the tag, never its own button", function()
		for _, theme in { "pixel_quest", "fantasy_ornate" } do
			local module: any = (require :: any)("../examples/themes/" .. theme)
			local package = module.build(bindThemes(Compose))
			for _, rung in { false, "compact", "large" } :: { any } do
				local w = tagWorld(package, if rung then rung else nil)
				w.state.editing:set(true)
				local buttons = {}
				for _, node in w.screen:GetDescendants() do
					if node:IsA("TextButton") or node:IsA("ImageButton") then
						table.insert(buttons, node)
					end
				end
				expect(`{theme} {tostring(rung)}: {#buttons} {find(w.tag, "Remove").ClassName}`).toBe(
					`{theme} {tostring(rung)}: 1 TextLabel`
				)
				expect(buttons[1] == w.tag).toBe(true)
				w.stop()
			end
		end
	end)

	t.it("a selectable tag that can be removed must say when it is editing", function()
		local ok, err = pcall(world, function(UI)
			return UI.Chip("Tag")({ label = "Rain", selected = Compose.cell(false), onRemove = function() end })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "editing", 1, true) ~= nil).toBe(true)
		local okEditing = pcall(world, function(UI)
			return UI.Chip("Tag")({ label = "Rain", selected = Compose.cell(false), editing = true })
		end)
		expect(okEditing).toBe(false)
	end)

	t.it("Delete or Backspace on the last of N tags removes exactly one and lands on the new last", function()
		for _, key in { "Delete", "Backspace" } do
			for _, n in { 3, 2 } do
				local all = { "A", "B", "C" }
				local items = Compose.cell(table.move(all, 1, n, 1, {}))
				local w = world(function(UI, Host)
					return Host.Frame({
						Name = "Tokens",
						Compose.keyed({
							from = items,
							render = function(current, index)
								local id = current:peek()
								return UI.Chip({
									Name = id,
									label = id,
									LayoutOrder = index,
									onRemove = function()
										local nextItems = table.clone(items:peek())
										table.remove(nextItems, table.find(nextItems, id) :: number)
										items:set(nextItems)
									end,
								})
							end,
						}),
					})
				end)
				w.gui.SelectedObject = find(w.screen, all[n])
				w.held[key] = true
				local remove = action(w, "RemoveChip")
				remove.Pressed.fire()
				local landed = w.gui.SelectedObject
				local again = action(w, "RemoveChip")
				again.Pressed.fire()
				w.held[key] = nil
				again.Released.fire()
				expect(`{key} last of {n}: {#items:peek()} left, focus {landed and landed.Name}`).toBe(
					`{key} last of {n}: {n - 1} left, focus {all[n - 1]}`
				)
				w.stop()
			end
		end
	end)

	t.it("a held removal does not repeat after an input change, and inherited disabled refuses it", function()
		local calls, enabled = 0, Compose.cell(true)
		local w = world(function(UI, Host)
			return Host.Frame({
				Name = "Holder",
				UI.Chip("Token")({
					label = "Rain",
					enabled = enabled,
					onRemove = function()
						calls += 1
					end,
				}),
			})
		end)
		local token = find(w.screen, "Token")
		w.gui.SelectedObject = token
		local remove = action(w, "RemoveChip")
		remove.Pressed.fire()
		expect(calls).toBe(1)
		w.engine.heartbeat.fire(1)
		expect(calls).toBe(1)
		remove.Released.fire()
		find(w.screen, "Holder").Interactable = false
		token.Activated.fire()
		expect(calls).toBe(1)
		find(w.screen, "Holder").Interactable = true
		enabled:set(false)
		token.Activated.fire()
		expect(action(w, "RemoveChip")).toBeNil()
		expect(calls).toBe(1)
		w.stop()
	end)
end)
