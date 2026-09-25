--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local controls = require("../src/ui")
local geometry = require("../src/ui/nav_radial_geometry")
local engines = require("./lib/native_engine")
local monitorModel = require("../examples/virtual_monitors/model")
local monitorScreens = require("../examples/virtual_monitors/screens")

local function radialWorld(spec: any): any
	local engine: any
	engine = engines.new({
		measureText = function(node: any): any
			local text = node.Text or ""
			return engine.types.Vector2.new(#text * 11, if #text > 0 then 20 else 0)
		end,
	})
	local gui, input = engine.new("GuiService"), engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local runtime = Roblox.createRuntime(engine)
	local UI: any = controls(
		Compose,
		runtime,
		{
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			reducedMotion = true,
		} :: any
	)
	spec.isPresented = spec.isPresented or Compose.cell(true)
	local stop, screen = runtime.mount(function()
		return runtime.constructors.ScreenGui({ UI.RadialMenu(spec) })
	end, engine.new("Folder"))
	return {
		engine = engine,
		input = input,
		find = function(name: string): any
			return screen:FindFirstChild(name, true)
		end,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function centerOf(world: any): (number, number)
	local position = world.find("Center").Position
	return position.X.Offset, position.Y.Offset
end

local function paintOf(world: any, id: string): any
	local frame = world.find("Sector-" .. id):FindFirstChild("Paint")
	local path = frame:FindFirstChild("Sector")
	local cx, cy = centerOf(world)
	local x, y, w, h = frame.Position.X.Offset, frame.Position.Y.Offset, frame.Size.X.Offset, frame.Size.Y.Offset
	local points = path:GetControlPoints()
	local function absolute(point: any): (number, number)
		return x + point.Position.X.Scale * w - cx, y + point.Position.Y.Scale * h - cy
	end
	local mx, my = absolute(points[math.ceil(#points / 2)])
	local middle = math.sqrt(mx * mx + my * my)
	local ax, ay = absolute(points[1])
	local bx, by = absolute(points[#points])
	local first, last = math.deg(math.atan2(ax, -ay)), math.deg(math.atan2(bx, -by))
	local extent = (last - first) % 360
	return {
		thickness = path.Thickness,
		inner = middle - path.Thickness / 2,
		outer = middle + path.Thickness / 2,
		first = first,
		extent = extent,
		w = w,
		h = h,
	}
end

local function iconItems(slots: { string }, fired: { string }?): { any }
	local items = {}
	for _, slot in slots do
		table.insert(items, {
			id = slot,
			slot = slot,
			label = slot,
			icon = "flag",
			labelStyle = "icon",
			onSelect = function()
				if fired then
					table.insert(fired, slot)
				end
			end,
		})
	end
	return items
end

local compassSlots = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

t.describe("native parity weak3 h2: radial content fit", function()
	t.it("defaults to both axes and matches an explicit both fit", function()
		local results: { [string]: any } = {}
		for _, mode in { "default", "both", "none" } do
			local world = radialWorld({
				distribution = "compass",
				contentFit = if mode == "default" then nil else mode,
				items = iconItems({ "N", "E" }),
			})
			results[mode] = paintOf(world, "N")
			world.stop()
		end
		local default, both, none = results.default, results.both, results.none
		t.expect(default.thickness).toBe(both.thickness)
		t.expect(default.w).toBe(both.w)
		t.expect(default.h).toBe(both.h)
		t.expect(default.thickness < none.thickness).toBe(true)
		t.expect(default.extent < none.extent - 1).toBe(true)
	end)
	t.it("offers independent radial and angular axes and an unchanged full-ring none mode", function()
		local results: { [string]: any } = {}
		for _, mode in { "none", "radial", "angular", "both" } do
			local world = radialWorld({ distribution = "compass", contentFit = mode, items = iconItems({ "N", "E" }) })
			results[mode] = paintOf(world, "N")
			world.stop()
		end
		local none, radial, angular, both = results.none, results.radial, results.angular, results.both
		t.expect(math.abs(none.inner - 40) < 1).toBe(true)
		t.expect(math.abs(none.outer - 220) < 1).toBe(true)
		t.expect(math.abs(none.extent - 45) < 1.5).toBe(true)
		t.expect(radial.thickness < none.thickness).toBe(true)
		t.expect(math.abs(radial.extent - none.extent) < 1.5).toBe(true)
		t.expect(math.abs(angular.thickness - none.thickness) < 0.01).toBe(true)
		t.expect(angular.extent < none.extent - 1).toBe(true)
		t.expect(math.abs(both.thickness - radial.thickness) < 0.01).toBe(true)
		t.expect(both.extent < none.extent - 1).toBe(true)
	end)
	t.it("gives every sector of a radial-fit ring one pair of radii for unequal content", function()
		local world = radialWorld({
			distribution = "compass",
			contentFit = "radial",
			items = {
				{ id = "N", slot = "N", label = "Go" },
				{ id = "E", slot = "E", label = "Wave hello" },
				{ id = "S", slot = "S", label = "Wave", icon = "flag", labelStyle = "icon" },
			},
		})
		local north, east, south = paintOf(world, "N"), paintOf(world, "E"), paintOf(world, "S")
		t.expect(north.thickness < 150).toBe(true)
		for _, other in { east, south } do
			t.expect(math.abs(other.thickness - north.thickness) < 0.001).toBe(true)
			t.expect(math.abs(other.inner - north.inner) < 2.5).toBe(true)
		end
		world.stop()
	end)
	t.it("encloses icon and compact icon content inside its fitted paint at every compass direction", function()
		for _, compact in { false, true } do
			local items = {}
			for _, slot in compassSlots do
				table.insert(items, {
					id = slot,
					slot = slot,
					label = "A deliberately long icon action label",
					icon = if compact then nil else "flag",
					labelStyle = if compact then nil else "icon",
					compactLabel = if compact then { icon = "flag", prefer = true } else nil,
				})
			end
			local world = radialWorld({ distribution = "compass", ringWidth = 72, items = items })
			local cx, cy = centerOf(world)
			for _, slot in compassSlots do
				local paint = paintOf(world, slot)
				t.expect(paint.thickness < 72).toBe(true)
				local button = world.find(slot)
				t.expect(button.Text).toBe("")
				local bx, by = button.Position.X.Offset - cx, button.Position.Y.Offset - cy
				local half = 10 + 4
				for _, dx in { -half, half } do
					for _, dy in { -half, half } do
						local x, y = bx + dx, by + dy
						local radius = math.sqrt(x * x + y * y)
						t.expect(radius >= paint.inner and radius <= paint.outer).toBe(true)
						local offset = (math.deg(math.atan2(x, -y)) - paint.first) % 360
						t.expect(offset <= paint.extent).toBe(true)
					end
				end
				t.expect(paint.extent < 44).toBe(true)
			end
			world.stop()
		end
	end)
	t.it("keeps the full logical sector as the gesture target outside the fitted paint", function()
		local fired = {}
		local world = radialWorld({ distribution = "compass", items = iconItems({ "N", "E" }, fired) })
		local paint = paintOf(world, "N")
		local cx, cy = centerOf(world)
		local sector = geometry.sectors({ { id = "N", slot = "N" } }, 0, 360, "compass", 40, 220)[1]
		t.expect(sector.outer - 1 > paint.outer).toBe(true)
		local touch: any = {
			UserInputType = world.engine.types.Enum.UserInputType.Touch,
			UserInputState = world.engine.types.Enum.UserInputState.Begin,
			Position = world.engine.types.Vector3.new(cx, cy - 130, 0),
		}
		world.find("N").InputBegan.fire(touch)
		touch.UserInputState = world.engine.types.Enum.UserInputState.Change
		touch.Position = world.engine.types.Vector3.new(cx, cy - (sector.outer - 1), 0)
		world.input.InputChanged.fire(touch)
		touch.UserInputState = world.engine.types.Enum.UserInputState.End
		world.input.InputEnded.fire(touch)
		t.expect(table.concat(fired, ",")).toBe("N")
		world.stop()
	end)
end)

local function findNamed(node: any, name: string): any
	if node.Name == name then
		return node
	end
	for _, child in node:GetChildren() do
		local found = findNamed(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function pathOf(node: any, stop: any): string
	local names = {}
	local current = node
	while current and current ~= stop do
		table.insert(names, 1, current.Name)
		current = current.Parent
	end
	return table.concat(names, "/")
end

t.describe("native parity weak3 h2: virtual monitors saved shelf", function()
	t.it("unmounts the Catalog grid on the Saved shelf so the table owns the whole feed, and restores it", function()
		local Facet = require("../src")
		local engine: any = engines.new()
		local runtime = Roblox.createRuntime(engine)
		local target = engine.new("ScreenGui")
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local lifetime = Compose.createRootOwner(function()
			local model = monitorModel.new(Compose)
			Compose.cleanup(model.dispose)
			local views = monitorScreens.create(Facet, runtime, {
				model = model,
				types = engine.types,
				services = { GuiService = gui, UserInputService = input },
				reducedMotion = true,
			})
			local _, discover = runtime.mount(views.Discover, target)
			local body = findNamed(discover, "DiscoverBody")
			local function feeds(): { any }
				local found = {}
				for _, child in body:GetChildren() do
					if child.Name == "Feed" then
						table.insert(found, child)
					end
				end
				return found
			end
			local grid = findNamed(discover, "Games")
			t.expect(grid ~= nil).toBe(true)
			t.expect(pathOf(grid, discover)).toBe(pathOf(body, discover) .. "/Feed/Games")
			t.expect(findNamed(discover, "SavedGames")).toBe(nil)
			model.toggleSaved("1")
			model.toggleSaved("2")
			findNamed(discover, "Saved").Activated.fire()
			t.expect(model.shelf:peek()).toBe("saved")
			t.expect(findNamed(discover, "Games")).toBe(nil)
			t.expect(grid.Parent).toBe(nil)
			local saved = findNamed(discover, "SavedGames")
			t.expect(saved ~= nil).toBe(true)
			local only = feeds()
			t.expect(#only).toBe(1)
			t.expect(saved.Parent).toBe(only[1])
			local flex = only[1]:FindFirstChildWhichIsA("UIFlexItem")
			t.expect(flex ~= nil and flex.FlexMode == engine.types.Enum.UIFlexMode.Fill).toBe(true)
			t.expect(saved.Size).toBe(engine.types.UDim2.fromScale(1, 1))
			findNamed(discover, "Browse").Activated.fire()
			t.expect(model.shelf:peek()).toBe("browse")
			t.expect(findNamed(discover, "SavedGames")).toBe(nil)
			t.expect(saved.Parent).toBe(nil)
			local restored = findNamed(discover, "Games")
			t.expect(restored ~= nil).toBe(true)
			t.expect(#feeds()).toBe(1)
			t.expect(restored.Parent).toBe(feeds()[1])
		end, runtime.reactor)
		lifetime.dispose()
		t.expect(#target:GetChildren()).toBe(0)
		runtime:dispose()
	end)
end)

local function keyedRows(throwOn: { [string]: boolean }): any
	local engine: any = engines.new()
	local runtime = Roblox.createRuntime(engine)
	local cards = Compose.cell({ { id = "a" }, { id = "b" } })
	local built: { [string]: number } = {}
	local live = 0
	local stop, frame = runtime.mount(function()
		return runtime.constructors.Frame({
			Name = "Rows",
			Compose.keyed({
				from = cards,
				key = function(card: { id: string })
					return card.id
				end,
				render = function(card: any)
					local id = card:peek().id
					if throwOn[id] then
						error("row factory throws for " .. id, 0)
					end
					built[id] = (built[id] or 0) + 1
					live += 1
					Compose.cleanup(function()
						live -= 1
					end)
					return runtime.constructors.TextLabel({ Name = "Row-" .. id, Text = id })
				end,
			}),
		})
	end, engine.new("ScreenGui"))
	return {
		cards = cards,
		built = built,
		live = function()
			return live
		end,
		names = function(): string
			local names = {}
			for _, child in frame:GetChildren() do
				table.insert(names, child.Name)
			end
			return table.concat(names, ",")
		end,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

t.describe("native parity weak3 h2: keyed row factory failure outside a boundary", function()
	t.it(
		"removes a departing row, keeps the survivor and skips the throwing row, and the writer sees the failure",
		function()
			local rows = keyedRows({ c = true })
			t.expect(rows.names()).toBe("Row-a,Row-b")
			t.expect(rows.live()).toBe(2)
			local ok, failure = pcall(function()
				rows.cards:set({ { id = "a" }, { id = "c" } })
			end)
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(failure), "row factory throws for c", 1, true) ~= nil).toBe(true)
			t.expect(rows.names()).toBe("Row-a")
			t.expect(rows.live()).toBe(1)
			t.expect(rows.built.a).toBe(1)
			rows.stop()
			t.expect(rows.live()).toBe(0)
		end
	)
	t.it("retries the row that threw on the next update", function()
		local throwOn = { c = true }
		local rows = keyedRows(throwOn)
		pcall(function()
			rows.cards:set({ { id = "a" }, { id = "c" } })
		end)
		throwOn.c = nil
		rows.cards:set({ { id = "a" }, { id = "c" } })
		t.expect(rows.names()).toBe("Row-a,Row-c")
		t.expect(rows.live()).toBe(2)
		t.expect(rows.built.a).toBe(1)
		t.expect(rows.built.c).toBe(1)
		rows.stop()
		t.expect(rows.live()).toBe(0)
	end)
	t.it("mounts independent rows later in the same update as a throwing row", function()
		local rows = keyedRows({ c = true })
		local ok = pcall(function()
			rows.cards:set({ { id = "d" }, { id = "c" }, { id = "a" }, { id = "e" } })
		end)
		t.expect(ok).toBe(false)
		local names = {}
		for name in string.gmatch(rows.names(), "[^,]+") do
			names[name] = true
		end
		t.expect(names["Row-d"] and names["Row-a"] and names["Row-e"]).toBe(true)
		t.expect(names["Row-c"]).toBe(nil)
		t.expect(names["Row-b"]).toBe(nil)
		t.expect(rows.live()).toBe(3)
		rows.stop()
		t.expect(rows.live()).toBe(0)
	end)
	t.it("cannot strand a retained row when an insertion precedes a throwing row", function()
		local rows = keyedRows({ c = true })
		pcall(function()
			rows.cards:set({ { id = "d" }, { id = "c" }, { id = "a" } })
		end)
		rows.cards:set({})
		t.expect(rows.names()).toBe("")
		t.expect(rows.live()).toBe(0)
		rows.cards:set({ { id = "a" } })
		t.expect(rows.names()).toBe("Row-a")
		rows.stop()
		t.expect(rows.live()).toBe(0)
	end)
end)

t.describe("native parity weak3 h2: RowActions own-row tap", function()
	local function rowsWorld(): (any, { [string]: any })
		local Facet = require("../src")
		local engine: any = engines.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local UI: any = Facet.controls(
			runtime,
			{
				types = engine.types,
				guiService = gui,
				reducedMotion = true,
				services = { GuiService = gui, UserInputService = input },
			} :: any
		)
		local Host = runtime.constructors
		local state: { [string]: any } = {
			open = { a = Compose.cell(nil), b = Compose.cell(nil) },
			coordinator = Compose.cell(nil),
			fired = {},
			content = {},
		}
		local function row(name: string)
			return UI.RowActions({
				Name = name,
				open = state.open[name],
				coordinator = state.coordinator,
				content = function()
					return Host.TextButton({
						Name = "RowContent",
						Text = name,
						Activated = function()
							table.insert(state.content, name)
						end,
					})
				end,
				leading = {
					{
						id = "Pin",
						label = "Pin",
						onActivate = function()
							table.insert(state.fired, name .. ":Pin")
						end,
					},
				},
				trailing = {
					{
						id = "Delete",
						label = "Delete",
						onActivate = function()
							table.insert(state.fired, name .. ":Delete")
						end,
					},
				},
			})
		end
		local stop, screen = runtime.mount(function()
			return Host.ScreenGui({ Host.Frame({ Name = "List", row("a"), row("b") }) })
		end, engine.new("Folder"))
		local V2 = engine.types.Vector2
		local a, b = findNamed(screen, "a"), findNamed(screen, "b")
		a.AbsolutePosition, a.AbsoluteSize = V2.new(0, 0), V2.new(300, 44)
		b.AbsolutePosition, b.AbsoluteSize = V2.new(0, 44), V2.new(300, 44)
		local w = {
			screen = screen,
			press = function(x: number, y: number, kind: string?)
				local E = engine.types.Enum
				input.InputBegan.fire({
					UserInputType = (E.UserInputType :: any)[kind or "Touch"],
					UserInputState = E.UserInputState.Begin,
					Position = engine.types.Vector3.new(x, y, 0),
				}, false)
			end,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
		return w, state
	end

	t.it("closes the open tray on a tap on its own row content and the content does not activate", function()
		local w, state = rowsWorld()
		local row = findNamed(w.screen, "a")
		local content = findNamed(row, "Content")
		local shield = findNamed(row, "DismissTray")
		t.expect(shield.Parent).toBe(content)
		t.expect(shield.Visible).toBe(false)
		for _, kind in { "Touch", "MouseButton1" } do
			state.open.a:set("trailing")
			t.expect(shield.Visible).toBe(true)
			t.expect(shield.Active).toBe(true)
			t.expect(shield.Selectable).toBe(false)
			t.expect(shield.Size).toEqual(engines.new().types.UDim2.fromScale(1, 1))
			t.expect(shield.ZIndex > findNamed(row, "RowContent").ZIndex).toBe(true)
			w.press(100, 20, kind)
			t.expect(state.open.a:peek()).toBe("trailing")
			shield.Activated.fire()
			t.expect(state.open.a:peek()).toBeNil()
			t.expect(shield.Visible).toBe(false)
		end
		t.expect(#state.content).toBe(0)
		t.expect(#state.fired).toBe(0)
		state.open.a:set("leading")
		shield.Activated.fire()
		t.expect(state.open.a:peek()).toBeNil()
		t.expect(#state.content).toBe(0)
		w.stop()
	end)

	t.it("keeps the tray open for a press on the open tray, and the tray action still runs once", function()
		local w, state = rowsWorld()
		state.open.a:set("trailing")
		w.press(280, 20)
		t.expect(state.open.a:peek()).toBe("trailing")
		findNamed(findNamed(findNamed(w.screen, "a"), "trailing"), "Delete").Activated.fire()
		t.expect(state.fired).toEqual({ "a:Delete" })
		t.expect(state.open.a:peek()).toBeNil()
		state.open.a:set("leading")
		w.press(20, 20)
		t.expect(state.open.a:peek()).toBe("leading")
		w.stop()
	end)

	t.it("still closes the open row when another row is pressed, and that row still activates", function()
		local w, state = rowsWorld()
		state.open.a:set("trailing")
		w.press(100, 60)
		t.expect(state.open.a:peek()).toBeNil()
		t.expect(state.open.b:peek()).toBeNil()
		findNamed(findNamed(w.screen, "b"), "RowContent").Activated.fire()
		t.expect(state.content).toEqual({ "b" })
		w.stop()
	end)
end)
