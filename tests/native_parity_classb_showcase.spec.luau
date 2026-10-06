--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	type World = {
		engine: any,
		runtime: any,
		gui: any,
		input: any,
		screen: any,
		stop: () -> (),
	}

	local function setup(build: (any, any, any, any) -> any, options: { [string]: any }?): World
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui, UserInputService = input },
		}
		for key, value in (options or {}) :: { [string]: any } do
			if key == "prepare" then
				value(engine, input)
			else
				config[key] = value
			end
		end
		local UI = Facet.controls(runtime, config :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, screen: any = runtime.mount(function()
			return Host.ScreenGui({ build(UI, Host, engine, gui) })
		end, engine.new("Folder"))
		return {
			engine = engine,
			runtime = runtime,
			gui = gui,
			input = input,
			screen = screen,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

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

	local function action(root: any, name: string): any
		local winner
		for _, node in root:GetDescendants() do
			if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
				if winner == nil or node.Priority > winner.Parent.Priority then
					winner = node:FindFirstChild(name)
				end
			end
		end
		return winner
	end

	local function rowOf(node: any): string?
		local at = node
		while at do
			local key = string.match(at.Name, "^row%-(%d+)$")
			if key then
				return at.Name
			end
			at = at.Parent
		end
		return nil
	end

	local function rows(count: number): { { id: string, index: number } }
		local list = {}
		for index = 1, count do
			list[index] = { id = string.format("row-%02d", index), index = index }
		end
		return list
	end

	local function mounted(list: any): { [string]: any }
		local out = {}
		for _, node in list:GetDescendants() do
			if string.match(node.Name, "^row%-%d+$") and out[node.Name] == nil then
				out[node.Name] = node
			end
		end
		return out
	end

	verifyHarness:suite("native parity classb showcase", function()
		verifyHarness:case("apps2-244 collection navigation skips ineligible rows and never lands on one", {
			id = "native_parity_classb_showcase::native parity classb showcase::apps2-244 collection navigation skips ineligible rows and never lands on one",
			run = function()
				local activated = {}
				local focus: FixtureCollectionTypes.FocusControls<any> = {}
				local world = setup(function(UI: FacetControls)
					return UI.VirtualList({
						from = rows(24),
						key = function(item)
							return item.id
						end,
						itemSize = 44,
						focus = focus,
						disabled = function(item: { id: string, index: number })
							return item.index % 3 == 0
						end,
						onActivate = function(item)
							table.insert(activated, item.id)
						end,
						render = function(current): GuiObject
							return UI.Button("Card")({
								label = function(use: Use)
									return use(current).id
								end,
							})
						end,
					})
				end)
				local list = world.screen:FindFirstChildWhichIsA("ScrollingFrame", true)
				list.AbsoluteWindowSize = world.engine.types.Vector2.new(420, 1200)
				assert(focus.focus)("row-01")
				local visited = {}
				local down = action(world.screen, "CollectionDown")
				Verify.expect(down ~= nil):toBe(true)
				for _ = 1, 10 do
					down.Pressed.fire()
					local key = rowOf(world.gui.SelectedObject)
					table.insert(visited, key or "nil")
				end
				Verify.expect(visited):toEqual({
					"row-02",
					"row-04",
					"row-05",
					"row-07",
					"row-08",
					"row-10",
					"row-11",
					"row-13",
					"row-14",
					"row-16",
				})
				local nodes = mounted(list)
				local refused = find(nodes["row-03"], "RowHit")
				Verify.expect(refused.Interactable):toBe(false)
				refused.Activated.fire(nil)
				Verify.expect(#activated):toBe(0)
				find(nodes["row-04"], "RowHit").Activated.fire(nil)
				Verify.expect(activated):toEqual({ "row-04" })
				world.stop()
			end,
		})

		verifyHarness:case("apps2-280 the resolved input fact follows the device for a control that adapts to it", {
			id = "native_parity_classb_showcase::native parity classb showcase::apps2-280 the resolved input fact follows the device for a control that adapts to it",
			run = function()
				local world = setup(function(UI: FacetControls)
					return UI.Table({
						from = { { id = 1, name = "a" }, { id = 2, name = "b" } },
						key = function(item)
							return item.id
						end,
						selection = Compose.cell({}),
						columns = {
							{
								id = "name",
								label = "Name",
								value = function(item)
									return item.name
								end,
							} :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, {
					prepare = function(engine, input)
						input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
					end,
				})
				local Enum = world.engine.types.Enum
				local header = find(world.screen, "Header")
				local function minimum(): number
					return header.Size.Y.Offset
				end
				local heights = {}
				for _, kind in
					{ "KeyboardAndMouse", "Gamepad", "Touch", "KeyboardAndMouse" } :: { "Gamepad" | "KeyboardAndMouse" | "Touch" }
				do
					world.input.PreferredInput = Enum.PreferredInput[kind]
					table.insert(heights, `{kind} {minimum()}`)
				end
				Verify.expect(heights)
					:toEqual({ "KeyboardAndMouse 40", "Gamepad 44", "Touch 44", "KeyboardAndMouse 40" })
				world.stop()
			end,
		})
	end)
end
