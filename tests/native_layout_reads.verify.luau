--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
local Lute = require("../tools/vendor/verify/src/lute")
local Facet = require("../src")
local engines = require("./lib/native_engine")
local Navigation = require("../src/ui/navigation_types")

type Record = { id: number, label: string }
type World = {
	engine: engines.Engine,
	UI: Facet.Controls,
	Host: Facet.Host,
	Compose: Facet.ComposeModule,
	mount: (build: () -> Instance) -> Instance,
	step: (frames: number) -> (),
	stop: () -> (),
}

return function(harness: Verify.Harness)
	local test = Bdd.create(harness)
	local describe, it, expect = test.describe, test.it, test.expect

	local function live(): World
		local engine = engines.new({ guardLayoutReads = true })
		local globals = (table.clone(engine.types) :: unknown) :: { [string]: unknown }
		local services: { [string]: unknown } = {}
		local function service(name: string): unknown
			if name == "CollectionService" then
				return nil
			end
			if not services[name] then
				services[name] = engine.new(name)
			end
			return services[name]
		end
		globals.game = {
			GetService = function(_self: unknown, name: string): unknown
				return service(name)
			end,
		}
		local loaded = Lute.loader.new({ globals = globals }).require("src") :: Facet.Facet
		local gui = VerifyRoblox.assertInstance(service("GuiService"))
		engine.environment.fakeOn(gui, "GetInsetArea", function()
			return engine.types.Rect.new(0, 0, 1280, 720)
		end)
		local input = VerifyRoblox.assertInstance(service("UserInputService"))
		for _, method in { "GetNavigationGamepads", "GetKeysPressed", "GetMouseButtonsPressed", "GetGamepadState" } do
			engine.environment.fakeOn(input, method, function()
				return {}
			end)
		end
		local frames = { Heartbeat = engine.heartbeat, PreRender = engine.heartbeat }
		local runtime = loaded.Roblox.createRuntime(engine)
		local UI = loaded.controls(runtime, {
			types = engine.types,
			services = {
				GuiService = (gui :: unknown) :: GuiService,
				UserInputService = (input :: unknown) :: UserInputService,
				RunService = (frames :: unknown) :: RunService,
			},
		})
		local stops: { () -> () } = {}
		return {
			engine = engine,
			UI = UI,
			Host = loaded.host(runtime),
			Compose = loaded.Compose,
			mount = function(build: () -> Instance): Instance
				local stop, mounted = runtime.mount(build, engine.new("Folder"))
				table.insert(stops, stop)
				local root = (mounted :: unknown) :: Instance
				for _, node in root:GetDescendants() do
					if node:IsA("ScrollingFrame") then
						local scroller = VerifyRoblox.assertInstance(node)
						engine.environment.fakeOn(scroller, "GetScrollVelocity", function()
							return engine.types.Vector2.zero
						end)
						engine.environment.fakeOn(scroller, "ResetScrollVelocity", function() end)
					end
				end
				return root
			end,
			step = function(count: number)
				for _ = 1, count do
					engine.heartbeat:Fire(1 / 60)
				end
			end,
			stop = function()
				for _, stop in stops do
					stop()
				end
				runtime:dispose()
			end,
		}
	end

	local function resize(world: World, root: Instance, pass: number)
		local V2 = world.engine.types.Vector2
		local poke = world.engine.environment.poke
		local nodes = root:GetDescendants()
		table.insert(nodes, 1, root)
		for index, node in nodes do
			local target = VerifyRoblox.assertInstance(node)
			local across, down = 160 + 9 * pass + index % 7, 24 + 3 * pass + index % 5
			if node:IsA("GuiBase2d") then
				poke(target, "AbsoluteSize", V2.new(across, down))
				poke(target, "AbsolutePosition", V2.new(index + pass, 2 * index + pass))
			end
			if node:IsA("ScrollingFrame") then
				poke(target, "AbsoluteWindowSize", V2.new(across, 4 * down))
				poke(target, "AbsoluteCanvasSize", V2.new(across, 12 * down))
			end
			if node:IsA("UIGridStyleLayout") then
				poke(target, "AbsoluteContentSize", V2.new(across, 6 * down))
			end
			if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
				poke(target, "TextBounds", V2.new(across // 2, down // 2))
			end
		end
	end

	local function shake(world: World, root: Instance)
		for pass = 1, 12 do
			resize(world, root, pass)
			if pass % 3 == 0 then
				world.step(1)
			end
		end
		world.step(8)
	end

	describe("layout change signals", function()
		it("a truncated caption that reports TextFits false while its bounds fit reflows once, not every frame", {
			id = "native_layout_reads::a truncated caption that reports TextFits false while its bounds fit reflows once, not every frame",
			run = function()
				local world = live()
				local V2 = world.engine.types.Vector2
				local E = world.engine.types.Enum
				local label: TextLabel
				world.mount(function()
					label = world.UI.Text "Title" {
						text = "Alpha",
						AutomaticSize = E.AutomaticSize.XY,
						TextTruncate = E.TextTruncate.AtEnd,
					} :: TextLabel
					return label
				end)
				local target = VerifyRoblox.assertInstance(label)
				local toggles = 0
				local poke = world.engine.environment.poke
				poke(target, "TextFits", false)
				poke(target, "TextBounds", V2.new(32, 18))
				poke(target, "AbsoluteSize", V2.new(34, 18))
				label:GetPropertyChangedSignal("AutomaticSize"):Connect(function()
					toggles += 1
					if label.AutomaticSize == E.AutomaticSize.None then
						poke(target, "AbsoluteSize", V2.new(0, 0))
					else
						poke(target, "AbsoluteSize", V2.new(34, 18))
					end
				end)
				world.step(60)
				expect(toggles <= 8):toBe(true)
				world.stop()
			end,
		})

		it("the guard records a layout read inside a layout change handler", {
			id = "native_layout_reads::layout change signals::the guard records a layout read inside a layout change handler",
			run = function()
				local engine = engines.new({ guardLayoutReads = true })
				local frame = engine.new("Frame")
				local seen: Vector2? = nil
				local connection = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					seen = frame.AbsoluteSize
				end)
				engine.environment.poke(
					VerifyRoblox.assertInstance(frame),
					"AbsoluteSize",
					engine.types.Vector2.new(40, 20)
				)
				connection:Disconnect()
				expect(seen):toEqual(engine.types.Vector2.new(40, 20))
				expect(#engine.layoutReadsInChange()):toBe(1)
				local _ = frame.AbsoluteSize
				expect(#engine.layoutReadsInChange()):toBe(1)
			end,
		})
		it("a measured collection resized quickly reads layout only after the change", {
			id = "native_layout_reads::layout change signals::a measured collection resized quickly reads layout only after the change",
			run = function()
				local world = live()
				local UI = world.UI
				local records: { Record } = {}
				for index = 1, 30 do
					records[index] = { id = index, label = `Row {index}` }
				end
				local list = world.mount(function(): Instance
					return UI.VirtualList {
						from = records,
						key = "id",
						itemSize = 24,
						measure = true,
						render = function(current: Facet.ReadOnlyValue<Record>): GuiObject
							return UI.Text {
								text = function(use: Facet.Use): string
									return use(current).label
								end,
							}
						end,
					}
				end)
				shake(world, list)
				expect(world.engine.layoutReadsInChange()):toEqual({})
				world.stop()
			end,
		})
		it("tab, button and navigation chrome read layout only after the change", {
			id = "native_layout_reads::layout change signals::tab, button and navigation chrome read layout only after the change",
			run = function()
				local world = live()
				local UI, Host, Compose = world.UI, world.Host, world.Compose
				local screen = world.mount(function(): Instance
					return Host.ScreenGui {
						UI.TabView {
							selection = Compose.cell("one"),
							tabs = {
								{
									id = "one",
									label = "One",
									glyph = function()
										return Host.Frame {}
									end,
									badge = "9",
									content = UI.Text { text = "Body" },
								},
								{ id = "two", label = "Two", content = UI.Text { text = "Other" } },
							},
						},
						UI.Button { label = "Continue to checkout", compactLabel = "Continue" },
						UI.NavigationStack {
							path = Compose.cell({} :: { Navigation.NavigationEntry<unknown> }),
							root = {
								title = "Recipe book",
								content = function(): GuiBase2d
									return Host.Frame {}
								end,
							},
							destinations = {},
						},
					}
				end)
				shake(world, screen)
				expect(world.engine.layoutReadsInChange()):toEqual({})
				world.stop()
			end,
		})
	end)
end
