--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local farmModel = require("../examples/facet_farm/model")
	local screens = require("../examples/facet_farm/screens")
	local theme = require("../examples/facet_farm/theme")
	local Compose: ComposeModule = Facet.Compose

	local function clockAt(start: number)
		local now = start
		return function()
			return now
		end, function(seconds: number)
			now += seconds
		end
	end

	local function mount()
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		local clock, advance = clockAt(100)
		local UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				theme = theme.create(Facet),
				motionLevel = "none",
				services = { GuiService = gui, UserInputService = input },
			} :: any
		)
		local farm
		local stop, screen: any = runtime.mount(function()
			farm = farmModel.new(Compose, clock)
			return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
				screens.farm(Facet, UI, runtime.constructors, engine.types, farm),
			})
		end, engine.new("Folder"))
		return {
			engine = engine,
			screen = screen,
			farm = farm,
			advance = function(seconds: number)
				advance(seconds)
				farm.tick()
			end,
			step = function(frames: number)
				for _ = 1, frames do
					engine.heartbeat.fire(1 / 60)
				end
			end,
			find = function(name: string): any
				return screen:FindFirstChild(name, true)
			end,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	verifyHarness:suite("Facet Farm", function()
		verifyHarness:case("plows, plants, grows, harvests and levels up by the crop rules", {
			id = "native_facet_farm::Facet Farm::plows, plants, grows, harvests and levels up by the crop rules",
			run = function()
				local clock, advance = clockAt(0)
				local farm = farmModel.new(Compose, clock)
				Verify.expect((farm.act(1))):toBe(true)
				Verify.expect(farm.plots:peek()[1].state):toBe("plowed")
				Verify.expect((farm.coins:peek())):toBe(120 - farmModel.PLOW_COST)
				farm.tool:set("plant")
				Verify.expect((farm.act(1))):toBe(true)
				Verify.expect((farm.coins:peek())):toBe(120 - farmModel.PLOW_COST - 5)
				Verify.expect((farm.act(1))):toBe(false)
				advance(20)
				Verify.expect((farmModel.stateAt(farm.plots:peek()[1], clock()))):toBe("ready")
				Verify.expect((farm.act(1))):toBe(true)
				Verify.expect((farm.coins:peek())):toBe(120 - farmModel.PLOW_COST - 5 + 14)
				Verify.expect((farm.xp:peek())):toBe(1)
				Verify.expect(farm.toast:peek().message):toBe("+14 coins from Wheat")
				farm.seed:set("carrot")
				Verify.expect((farm.act(1))):toBe(false)
				Verify.expect(farm.toast:peek().message):toBe("Carrot unlocks at level 2")
				farm.xp:set(farmModel.xpFor(2) - 1)
				farm.seed:set("wheat")
				farm.act(1)
				advance(20)
				farm.act(1)
				Verify.expect((farm.level:peek())):toBe(2)
				Verify.expect((farm.levelUp:peek())):toBe(true)
			end,
		})

		verifyHarness:case("withers a crop left three growth times and clears it back to grass", {
			id = "native_facet_farm::Facet Farm::withers a crop left three growth times and clears it back to grass",
			run = function()
				local clock, advance = clockAt(0)
				local farm = farmModel.new(Compose, clock)
				farm.act(2)
				farm.tool:set("plant")
				farm.act(2)
				advance(60)
				Verify.expect((farmModel.stateAt(farm.plots:peek()[2], clock()))):toBe("withered")
				Verify.expect((farm.act(2))):toBe(true)
				Verify.expect(farm.plots:peek()[2].state):toBe("grass")
			end,
		})

		verifyHarness:case("mounts a field of plot buttons that play the game through Facet controls", {
			id = "native_facet_farm::Facet Farm::mounts a field of plot buttons that play the game through Facet controls",
			run = function()
				local world = mount()
				local plot = world.find("Plot1")
				Verify.expect((plot:IsA("TextButton"))):toBe(true)
				Verify.expect((plot:GetAttribute("label"))):toBe("Plot 1, grass")
				plot.Activated.fire()
				Verify.expect((plot:GetAttribute("label"))):toBe("Plot 1, plowed")
				world.farm.tool:set("plant")
				plot.Activated.fire()
				Verify.expect((plot:GetAttribute("label"))):toBe("Plot 1, Wheat growing")
				Verify.expect(world.find("Growth") ~= nil):toBe(true)
				Verify.expect(world.find("Sprout") ~= nil):toBe(true)
				world.advance(20)
				Verify.expect((plot:GetAttribute("label"))):toBe("Plot 1, Wheat ready")
				Verify.expect(world.find("Wheat") ~= nil):toBe(true)
				world.find("HarvestAll").Activated.fire()
				Verify.expect((world.farm.coins:peek())):toBe(120 - farmModel.PLOW_COST - 5 + 14)
				Verify.expect(world.find("Coins").Text):toBe(`{world.farm.coins:peek()} coins`)
				local previous
				for _ = 1, 3 do
					world.find("Market").Activated.fire()
					world.step(40)
					local row = world.find("Seed_wheat")
					Verify.expect(row ~= nil and row ~= previous):toBe(true)
					previous = row
					world.find("ModalBack").Pressed.fire()
					world.step(40)
					Verify.expect((world.farm.marketOpen:peek())):toBe(false)
					Verify.expect((world.find("Seed_wheat"))):toBeNil()
				end
				Verify.expect((world.find("SeedMarket"):GetAttribute("FacetError"))):toBeNil()
				world.find("Market").Activated.fire()
				Verify.expect(#world.screen:FindFirstChild("Field", true):GetChildren() > 20):toBe(true)
				world.farm.marketOpen:set(false)
				world.step(40)
				Verify.expect(world.find("Board").Visible):toBe(true)
				world.find("View").Activated.fire()
				Verify.expect((world.farm.view:peek())):toBe("3d")
				Verify.expect(world.find("Board").Visible):toBe(false)
				Verify.expect(world.find("View").Text):toBe("2D board")
				world.find("View").Activated.fire()
				Verify.expect((world.farm.view:peek())):toBe("2d")
				world.stop()
			end,
		})
	end)

	return nil
end
