--!strict
local FixtureRoblox = require("../tools/vendor/verify/src/roblox")
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local context = require("../src/ui/context")
local registerDrag = require("../src/ui/drag")
local registerGrid = require("../src/ui/spatial_grid")
local sessionOf = require("../src/ui/drag_session")
local engines = require("./lib/native_engine")
local Types = require("../src/ui/types")
local Env = require("../src/ui/environment_types")
type Item = { id: string, column: number, row: number, width: number, height: number }

local function fixture()
	local C = Facet.Compose
	local engine = engines.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local inputService = engine.new("UserInputService")
	local config =
		{ types = engine.types, guiService = gui, services = { UserInputService = inputService, GuiService = gui } }
	local UI = table.clone(Facet.controls(runtime, config))
	local ctx = context(C, runtime, config)
	registerDrag(ctx, UI)
	registerGrid(ctx, UI)
	local service = sessionOf(ctx)
	local items = C.cell({
		{ id = "A", column = 1, row = 1, width = 2, height = 2 },
		{ id = "B", column = 4, row = 1, width = 1, height = 2 },
	} :: { Item })
	local commits = 0
	local pending = false
	local complete: ((boolean, string?) -> boolean)? = nil
	local last: Env.DropPlacement? = nil
	local stop, root = runtime.mount(function()
		return ctx.Host.ScreenGui {
			UI.SpatialGrid {
				from = items,
				key = function(item: Item): string
					return item.id
				end,
				placement = function(item: Item): Facet.SpatialPlacement
					return item
				end,
				columns = 5,
				rows = 4,
				cellSize = 48,
				gap = 4,
				footprint = function(): Vector2
					return engine.types.Vector2.new(2, 2)
				end,
				drag = function(current: Types.ReadOnlyValue<Item>): Facet.DraggableSpec
					return { payload = current, returnTravel = false }
				end,
				drop = {
					travel = false,
					onDrop = function(_payload: unknown, info: Facet.DropInfo): boolean | "pending"
						commits += 1
						last = info.placement
						complete = info.complete
						return if pending then "pending" else true
					end,
				},
				render = function(current: Types.ReadOnlyValue<Item>): GuiObject
					return UI.Button { Name = current:peek().id, label = current:peek().id }
				end,
			},
		}
	end, engine.new("Folder"))
	local function find(name: string): GuiObject
		return assert((root :: Instance):FindFirstChild(name, true)) :: GuiObject
	end
	local source = find("A")
	engine.environment.poke(FixtureRoblox.assertInstance(source), "AbsoluteSize", engine.types.Vector2.new(100, 100))
	return {
		engine = engine,
		runtime = runtime,
		gui = gui,
		items = items,
		find = find,
		service = service,
		begin = function(mode: "pointer" | "armed")
			service.begin(source, { payload = "A", returnTravel = false }, mode, nil, false)
		end,
		activate = function(name: string, gamepad: boolean?)
			local input = engine.new("InputObject")
			input.UserInputType = if gamepad
				then engine.types.Enum.UserInputType.Gamepad1
				else engine.types.Enum.UserInputType.Keyboard
			input.KeyCode = if gamepad then engine.types.Enum.KeyCode.ButtonA else engine.types.Enum.KeyCode.Return
			local signal = ((find(name) :: GuiButton).Activated :: unknown) :: engines.Signal<InputObject, number>
			signal:Fire(input, 1)
		end,
		tap = function(name: string, position: Vector2?)
			local node = find(name)
			local input = engine.new("InputObject")
			input.UserInputType = engine.types.Enum.UserInputType.Touch
			input.UserInputState = engine.types.Enum.UserInputState.Begin
			input.Position = if position
				then engine.types.Vector3.new(position.X, position.Y, 0)
				else engine.types.Vector3.new(20, 20, 0)
			local began = (node.InputBegan :: unknown) :: engines.Signal<InputObject>
			began:Fire(input)
			input.UserInputState = engine.types.Enum.UserInputState.End
			inputService.InputEnded:Fire(input)
		end,
		commits = function(): number
			return commits
		end,
		last = function(): Env.DropPlacement?
			return last
		end,
		pending = function()
			pending = true
		end,
		complete = function(ok: boolean): boolean
			return assert(complete)(ok, "Server refused placement")
		end,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

return function(h: Verify.Harness)
	h:case("touch placement uses the cell under a carried item without picking it up again", function()
		local w = fixture()
		w.tap("A")
		w.tap("A", w.engine.types.Vector2.new(78, 78))
		Verify.expect(w.commits()):toBe(1)
		Verify.expect(assert(w.last()).column):toBe(2)
		Verify.expect(assert(w.last()).row):toBe(2)
		Verify.expect(w.service.state:peek()):toBe(nil)
		w.stop()
	end)
	h:case("Lab inventory and transition examples construct their interactive content", function()
		local Catalog = require("../examples/facet-lab/src/catalog_types")
		for _, demo in
			{
				require("../examples/facet-lab/src/spatial_grid_demo"),
				require("../examples/facet-lab/src/custom_transition_demo"),
			}
		do
			local engine = engines.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local screen = engine.new("ScreenGui")
			local UI = Facet.controls(runtime, { types = engine.types, overlayParent = screen })
			local c = (
				{
					cell = function<T>(_name: string, initial: T)
						return Facet.Compose.cell(initial)
					end,
					Compose = Facet.Compose,
					Host = runtime.constructors,
					types = engine.types,
					app = { runtime = runtime },
				} :: unknown
			) :: Catalog.Context
			Verify.expect(demo.base ~= nil):toBe(true)
			local stop, mounted = runtime.mount(function()
				return assert(demo.make)(UI, {} :: never, c)
			end, screen)
			local root = mounted :: GuiObject
			Verify.expect(#root:GetDescendants() > 10):toBe(true)
			if root.Name == "InventoryScroll" then
				local pack = assert(root:FindFirstChild("Pack", true)) :: GuiButton
				local loot = assert(root:FindFirstChild("Loot", true))
				local destination = assert(loot:FindFirstChild("Cell3_2", true)) :: GuiButton
				local input = engine.new("InputObject")
				input.UserInputType = engine.types.Enum.UserInputType.Keyboard
				input.KeyCode = engine.types.Enum.KeyCode.Return
				local pickup = (pack.Activated :: unknown) :: engines.Signal<InputObject, number>
				pickup:Fire(input, 1)
				local drop = (destination.Activated :: unknown) :: engines.Signal<InputObject, number>
				drop:Fire(input, 1)
				Verify.expect(loot:FindFirstChild("Pack") ~= nil):toBe(true)
				Verify.expect((assert(root:FindFirstChild("Inventory", true))):FindFirstChild("Pack")):toBe(nil)
			end
			stop()
			runtime:dispose()
		end
	end)
	h:case("touch tap and gamepad A share the same cell placement", function()
		for _, kind in { "touch", "gamepad" } do
			local w = fixture()
			w.gui.SelectedObject = w.find("A")
			if kind == "touch" then
				w.tap("A")
			else
				w.activate("A", true)
			end
			Verify.expect(w.service.state:peek() ~= nil):toBe(true)
			w.gui.SelectedObject = w.find("Cell2_2")
			if kind == "touch" then
				w.tap("Cell2_2")
			else
				w.activate("Cell2_2", true)
			end
			Verify.expect(w.commits()):toBe(1)
			Verify.expect(assert(w.last()).column):toBe(2)
			w.stop()
		end
	end)
	h:case("a button can both pick up and receive a drop without replacing its activation", function()
		local w = fixture()
		w.gui.SelectedObject = w.find("A")
		w.activate("A")
		Verify.expect(w.service.state:peek() ~= nil):toBe(true)
		w.gui.SelectedObject = w.find("Cell2_2")
		w.activate("Cell2_2")
		Verify.expect(w.commits()):toBe(1)
		Verify.expect(w.service.state:peek()):toBe(nil)
		Verify.expect(w.gui.SelectedObject):toBe(w.find("A"))
		w.stop()
	end)
	h:case("checks a full footprint and permits overlapping the moving item's old cells", function()
		local w = fixture()
		w.begin("armed")
		w.service.hover(w.find("Cell2_2"))
		Verify.expect(w.find("Cell2_2"):GetAttribute("FacetDropState")):toBe("accepted")
		w.service.hover(w.find("Cell3_1"))
		Verify.expect(w.find("Cell3_1"):GetAttribute("FacetDropState")):toBe("rejected")
		w.service.hover(w.find("Cell5_4"))
		Verify.expect(w.find("Cell5_4"):GetAttribute("FacetDropState")):toBe("rejected")
		Verify.expect(w.service.commit(w.find("Cell2_2"))):toBe(true)
		Verify.expect(w.commits()):toBe(1)
		Verify.expect(assert(w.last()).column):toBe(2)
		Verify.expect(assert(w.last()).height):toBe(2)
		w.stop()
	end)
	h:case("revalidates occupancy at commit and retains keyed nodes after a move", function()
		local w = fixture()
		local original = w.find("A")
		w.begin("armed")
		w.service.hover(w.find("Cell2_2"))
		w.items:set({
			{ id = "A", column = 1, row = 1, width = 2, height = 2 },
			{ id = "B", column = 3, row = 2, width = 1, height = 2 },
		})
		Verify.expect(w.service.commit(w.find("Cell2_2"))):toBe(false)
		Verify.expect(w.commits()):toBe(0)
		w.items:set({ { id = "A", column = 2, row = 3, width = 2, height = 2 } })
		Verify.expect(w.find("A")):toBe(original)
		w.stop()
	end)
	h:case("maps a pointer using the pickup anchor and the native scale", function()
		local w = fixture()
		local grid = w.find("SpatialGrid")
		w.engine.environment.poke(
			FixtureRoblox.assertInstance(grid),
			"AbsoluteSize",
			w.engine.types.Vector2.new(256, 204)
		)
		w.engine.environment.poke(FixtureRoblox.assertInstance(w.find("Cells")), "AbsoluteSize", grid.AbsoluteSize)
		w.begin("pointer")
		w.service.update(w.engine.types.Vector2.new(102, 102))
		Verify.expect(w.service.commit(grid)):toBe(true)
		Verify.expect(assert(w.last()).column):toBe(2)
		Verify.expect(assert(w.last()).row):toBe(2)
		w.stop()
	end)
	h:case("keeps pending placement owned and rejects late completion after teardown", function()
		local w = fixture()
		w.pending()
		w.begin("armed")
		w.service.commit(w.find("Cell2_2"))
		Verify.expect(assert(w.service.state:peek()).pending):toBe(true)
		w.stop()
		Verify.expect(w.complete(true)):toBe(false)
	end)
	h:case("exposes native cell targets during carry and restores item targets after cancellation", function()
		local w = fixture()
		w.gui.SelectedObject = w.find("A")
		Verify.expect(w.find("Cell2_2").Selectable):toBe(false)
		w.begin("armed")
		Verify.expect(w.find("Cell2_2").Selectable):toBe(true)
		Verify.expect(w.gui.SelectedObject):toBe(w.find("Cell1_1"))
		w.service.finish(false)
		Verify.expect(w.find("Cell2_2").Selectable):toBe(false)
		Verify.expect(w.find("A").Selectable):toBe(true)
		w.stop()
	end)
end
