--!strict
local Verify = require("../tools/vendor/verify/src/core")
local fs = require("@std/fs")
local Lute = require("../tools/vendor/verify/src/lute")
local NativeEngine = require("./lib/native_engine")
local Roblox = NativeEngine.types
local datatypeName = require("../tools/vendor/verify/src/roblox").datatypes.typeof
local function scope(fields: { [string]: unknown }): { [string]: unknown }
	return fields
end
type Case = { id: string, setup: unknown? }
type Pointer = { heldDrag: (Vector2, Vector2) -> (), up: (Vector2) -> (), cleanup: () -> () }
type Catalog = { pointer: (unknown) -> Pointer, drivers: { [string]: unknown }, requirements: { [string]: string } }
type RegisterOptions = {
	device: string,
	registerOnly: boolean,
	connectGamepad: (() -> ())?,
	disconnectGamepad: (() -> ())?,
}
type Register = (unknown, string, RegisterOptions) -> Catalog

return function(harness: Verify.Harness)
	harness:case("Xbox drivers use native controller input for transfer recall zoom travel and shuffle", function(t)
		local json = require("@std/json")
		local buttons: { string } = {}
		local steps: { string } = {}
		local forbidden = 0
		local engine = NativeEngine.new()
		local root = engine.new("Frame")
		local node = engine.new("TextButton")
		node.Name = "Shuffle"
		node.Parent = root
		engine.environment.poke(node, "AbsolutePosition", Roblox.Vector2.zero)
		engine.environment.poke(node, "AbsoluteSize", Roblox.Vector2.new(64, 64))
		for _, name in { "Send", "Return" } do
			local button = engine.new("TextButton")
			button.Name = name
			button.Parent = root
		end
		local source = engine.new("Frame")
		engine.environment.poke(source, "AbsolutePosition", Roblox.Vector2.zero)
		engine.environment.poke(source, "AbsoluteSize", Roblox.Vector2.new(64, 64))
		local state = {
			source = source,
			target = node,
			view = node,
			row = { Parent = root },
			content = { Parent = { Parent = root } },
		}
		local service = {
			WaitForChild = function(self: unknown): unknown
				return self
			end,
			KeyboardEnabled = true,
			PreferredInput = Roblox.Enum.PreferredInput.Gamepad,
			GamepadEnabled = true,
			TouchEnabled = false,
			MouseEnabled = false,
			RenderStepped = { Wait = function() end },
			JSONDecode = function(_self: unknown, value: string): unknown
				return Lute.parse(value)
			end,
		}
		local live = {
			press = function(names: { string }, frames: number?): string
				local input: { string } = {}
				for _, name in names do
					if name == "ButtonR1" then
						t:expect((frames or 3) >= 30):toBe(true)
					end
					table.insert(buttons, name)
					table.insert(
						input,
						"Gamepad1:"
							.. (
								if string.sub(name, 1, 6) == "Stick2"
									then "Thumbstick2:1"
									elseif string.sub(name, 1, 5) == "Stick" then "Thumbstick1:1"
									else name
							)
					)
				end
				return json.serialize({ input = input })
			end,
			step = function(name: string)
				table.insert(steps, name)
			end,
		}
		local travelFactory = Lute.chunk.load(fs.readFileToString("tools/studio/live/zoom_travel_drivers.luau"))()
		local register = Lute.chunk.load(fs.readFileToString("tools/studio/live/interactive.luau"), {
			environment = scope({
				game = {
					ReplicatedStorage = {
						FacetLive = { zoom_travel_drivers = "travel" },
						WaitForChild = function()
							return service
						end,
					},
					GetService = function()
						return service
					end,
				},
				Enum = Roblox.Enum,
				Vector2 = Roblox.Vector2,
				typeof = datatypeName,
				require = function(name: unknown): unknown
					return if name == "travel" then travelFactory else Verify
				end,
			}),
		})() :: Register
		local catalog = register(live, "", { device = "keep", registerOnly = true })
		local io = {
			hold = function()
				forbidden += 1
			end,
			drag = function()
				forbidden += 1
			end,
		}
		local expected: { [string]: string } = {
			["keyboard-gamepad-place-and-cancel"] = "ButtonA,DPadDown,ButtonA,ButtonA,ButtonB",
			["zoom-gamepad"] = "ButtonR1,Stick2Right,ButtonY",
			["travel-gamepad"] = "ButtonA,ButtonA",
			["shuffle-gamepad"] = "ButtonA,ButtonA,ButtonA",
			["sidebar-dpad-to-collections"] = "DPadDown",
		}
		for id, sequence in expected do
			table.clear(buttons)
			table.clear(steps)
			local driver = catalog.drivers[id] :: (unknown, unknown, unknown) -> ()
			driver({
				check = function(_name: string, passed: boolean)
					t:expect(passed):toBe(true)
				end,
			}, state, io)
			t:expect(forbidden):toBe(0)
			t:expect(table.concat(buttons, ",")):toBe(sequence)
			t:expect(#steps > 0):toBe(true)
			t:expect(catalog.requirements[id]):toBe("input-gamepad")
		end
		table.clear(buttons)
		table.clear(steps)
		local sidebar = catalog.drivers["sidebar-dpad-to-collections"] :: (unknown, unknown) -> ()
		sidebar({
			check = function(_name: string, passed: boolean)
				t:expect(passed):toBe(true)
			end,
		}, { across = true })
		t:expect(table.concat(buttons, ",")):toBe("DPadRight")
		t:expect(steps[1]):toBe("afterRight")
		local connected, disconnected = 0, 0
		local hotplug = register(live, "in47", {
			device = "none",
			registerOnly = true,
			connectGamepad = function()
				connected += 1
			end,
			disconnectGamepad = function()
				disconnected += 1
			end,
		})
		local hotplugSteps: { [string]: string } = {
			["text-edit-carries-gamepad-connect"] = "afterConnect",
			["radial-hot-switch-keeps-open"] = "afterPlug,afterUnplug",
			["input-fact-follows-device"] = "afterPlug",
		}
		for id, sequence in hotplugSteps do
			table.clear(steps)
			local driver = hotplug.drivers[id] :: () -> ()
			driver()
			t:expect(table.concat(steps, ",")):toBe(sequence)
		end
		t:expect(connected):toBe(3)
		t:expect(disconnected):toBe(3)
	end)
	harness:case("interactive suites register drivers before capability selection", function(t)
		local positions: { Vector2 } = {}
		local down = false
		local virtual = {
			IsA = function(_self: unknown, className: string): boolean
				return className == "VirtualInput" or className == "Object"
			end,
			SendMousePosition = function(_self: unknown, point: Vector2)
				assert(point.X < 1000, "blocked native input")
				table.insert(positions, point)
			end,
			SendMouseButton = function(_self: unknown, point: Vector2, _button: unknown, nextDown: boolean)
				down = nextDown
				table.insert(positions, point)
			end,
		}
		local service = {
			CreateVirtualInput = function(_self: unknown)
				return virtual
			end,
			GetGuiInset = function(_self: unknown): Vector2
				return Roblox.Vector2.new(0.25, 0.5)
			end,
			RenderStepped = { Wait = function(_self: unknown) end },
			KeyboardEnabled = true,
			PreferredInput = "Keyboard",
			GamepadEnabled = false,
			TouchEnabled = false,
			MouseEnabled = true,
			WaitForChild = function(self: unknown, _name: string): unknown
				return self
			end,
		}
		local storage =
			{ FacetLive = { zoom_travel_drivers = "zoom_travel_drivers" }, WaitForChild = service.WaitForChild }
		local gameStub = {
			ReplicatedStorage = storage,
			GetService = function(_self: unknown, _name: string)
				return service
			end,
		}
		local travelFactory = Lute.chunk.load(fs.readFileToString("tools/studio/live/zoom_travel_drivers.luau"))()
		local register = Lute.chunk.load(fs.readFileToString("tools/studio/live/interactive.luau"), {
			environment = scope({
				game = gameStub,
				Enum = Roblox.Enum,
				Vector2 = Roblox.Vector2,
				typeof = datatypeName,
				require = function(name: unknown): unknown
					return if name == "zoom_travel_drivers" then travelFactory else Verify
				end,
			}),
		})() :: Register
		local pointerCatalog = register({}, "", { device = "none", registerOnly = true })
		local ordinary = Verify.createHarness({ source = "in24", prefixIds = false, now = os.clock })
		ordinary:case("ordinary", function(context)
			context:expect(true):toBe(true)
		end)
		local ordinaryReport = ordinary:run({ executor = "roblox-studio", capabilities = { "roblox-client" } })
		local dispatched = false
		local dispatch = (
			register :: unknown
		) :: (unknown, string, { device: string, registerOnly: boolean }) -> Verify.Report
		local returned = dispatch({
			cases = function()
				return { { id = "ordinary", run = function() end } }
			end,
			report = function(suite: string)
				dispatched = suite == "in24"
				return ordinaryReport
			end,
		}, "in24", { device = "none", registerOnly = false })
		t:expect(dispatched):toBe(true)
		t:expect(returned.passed):toBe(1)
		service.GamepadEnabled = true
		service.PreferredInput = "Gamepad"
		local catalogs = { pointerCatalog, register({}, "", { device = "keep", registerOnly = true }) }
		local io = pointerCatalog.pointer({})
		io.heldDrag(Roblox.Vector2.new(1.25, 2.75), Roblox.Vector2.new(21.75, 22.25))
		io.up(Roblox.Vector2.new(21.75, 22.25))
		t:expect(#positions > 16):toBe(true)
		for _, point in positions do
			t:expect(point.X % 1):toBe(0)
			t:expect(point.Y % 1):toBe(0)
		end
		local accepted = pcall(io.heldDrag, Roblox.Vector2.new(1, 2), Roblox.Vector2.new(2000, 2))
		t:expect(accepted):toBe(false)
		t:expect(down):toBe(true)
		io.cleanup()
		t:expect(down):toBe(false)
		local count = 0
		local missing: { string } = {}
		for _, name in
			{
				"native_mechanisms_input",
				"needs_live_input",
				"weak3_pointer",
				"container_transfer",
				"zoom_travel",
				"command_scope",
				"reward_sequence",
				"in47",
				"in24",
			}
		do
			local file = name .. ".luau"
			local source = fs.readFileToString("tools/studio/live/suites/" .. file)
			if not string.find(source, "setup =", 1, true) then
				continue
			end
			local cases = Lute.chunk.load(source, {
				environment = scope({
					game = gameStub,
					Enum = Roblox.Enum,
					Vector2 = Roblox.Vector2,
					typeof = datatypeName,
					Vector3 = Roblox.Vector3,
					Color3 = Roblox.Color3,
					UDim2 = Roblox.UDim2,
					UDim = Roblox.UDim,
				}),
			})() :: { Case }
			for _, case in cases do
				if not case.setup then
					continue
				end
				count += 1
				if string.match(case.id, "gamepad$") then
					t:expect(catalogs[2].requirements[case.id]):toBe("input-gamepad")
				end
				for _, catalog in catalogs do
					if type(catalog.drivers[case.id]) ~= "function" then
						table.insert(missing, file .. "/" .. case.id)
					end
				end
			end
		end
		assert(#missing == 0, table.concat(missing, ", "))
		t:expect(count > 0):toBe(true)
		t:expect(catalogs[1].requirements["collection-immediate-touch-transfer"]):toBe("input-native-touch")
		t:expect(catalogs[1].requirements["keyboard-gamepad-place-and-cancel"]):toBe("input-gamepad")
		t:expect(catalogs[1].requirements["reserved-slots-pointer-recall"]):toBeNil()
		for _, id in
			{ "board-typing-pointer-and-text-entry", "return-and-space-activate-once", "shift-return-opens-row-menu" }
		do
			t:expect(catalogs[2].requirements[id]):toBe("input-keyboard")
		end
		for _, id in { "touch-drag-scrolls-reorderable-list", "mail-swipe-and-tap" } do
			t:expect(catalogs[2].requirements[id]):toBe("input-native-touch")
		end
		for _, id in { "slider-rotation-live", "zoom-pointer", "zoom-collection-capture-camera" } do
			t:expect(catalogs[2].requirements[id]):toBe("input-mouse")
		end
		for _, id in
			{ "text-edit-carries-gamepad-connect", "radial-hot-switch-keeps-open", "input-fact-follows-device" }
		do
			t:expect(catalogs[1].requirements[id]):toBe("input-native-controller-connect")
		end
	end)
end
