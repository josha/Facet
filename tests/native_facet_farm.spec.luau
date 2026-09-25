--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local farmModel = require("../examples/facet_farm/model")
local screens = require("../examples/facet_farm/screens")
local theme = require("../examples/facet_farm/theme")
local Compose = Facet.Compose

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
	local runtime = Facet.Roblox.createRuntime(engine)
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
			reducedMotion = true,
			services = { GuiService = gui, UserInputService = input },
		} :: any
	)
	local farm
	local stop, screen = runtime.mount(function()
		farm = farmModel.new(Compose, clock)
		return runtime.constructors.ScreenGui({ screens.farm(Facet, UI, runtime.constructors, engine.types, farm) })
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

t.describe("Facet Farm", function()
	t.it("plows, plants, grows, harvests and levels up by the crop rules", function()
		local clock, advance = clockAt(0)
		local farm = farmModel.new(Compose, clock)
		t.expect(farm.act(1)).toBe(true)
		t.expect(farm.plots:peek()[1].state).toBe("plowed")
		t.expect(farm.coins:peek()).toBe(120 - farmModel.PLOW_COST)
		farm.tool:set("plant")
		t.expect(farm.act(1)).toBe(true)
		t.expect(farm.coins:peek()).toBe(120 - farmModel.PLOW_COST - 5)
		t.expect(farm.act(1)).toBe(false)
		advance(20)
		t.expect(farmModel.stateAt(farm.plots:peek()[1], clock())).toBe("ready")
		t.expect(farm.act(1)).toBe(true)
		t.expect(farm.coins:peek()).toBe(120 - farmModel.PLOW_COST - 5 + 14)
		t.expect(farm.xp:peek()).toBe(1)
		t.expect(farm.toast:peek().message).toBe("+14 coins from Wheat")
		farm.seed:set("carrot")
		t.expect(farm.act(1)).toBe(false)
		t.expect(farm.toast:peek().message).toBe("Carrot unlocks at level 2")
		farm.xp:set(farmModel.xpFor(2) - 1)
		farm.seed:set("wheat")
		farm.act(1)
		advance(20)
		farm.act(1)
		t.expect(farm.level:peek()).toBe(2)
		t.expect(farm.levelUp:peek()).toBe(true)
	end)

	t.it("withers a crop left three growth times and clears it back to grass", function()
		local clock, advance = clockAt(0)
		local farm = farmModel.new(Compose, clock)
		farm.act(2)
		farm.tool:set("plant")
		farm.act(2)
		advance(60)
		t.expect(farmModel.stateAt(farm.plots:peek()[2], clock())).toBe("withered")
		t.expect(farm.act(2)).toBe(true)
		t.expect(farm.plots:peek()[2].state).toBe("grass")
	end)

	t.it("mounts a field of plot buttons that play the game through Facet controls", function()
		local world = mount()
		local plot = world.find("Plot1")
		t.expect(plot:IsA("TextButton")).toBe(true)
		t.expect(plot:GetAttribute("label")).toBe("Plot 1, grass")
		plot.Activated.fire()
		t.expect(plot:GetAttribute("label")).toBe("Plot 1, plowed")
		world.farm.tool:set("plant")
		plot.Activated.fire()
		t.expect(plot:GetAttribute("label")).toBe("Plot 1, Wheat growing")
		t.expect(world.find("Growth") ~= nil).toBe(true)
		t.expect(world.find("Sprout") ~= nil).toBe(true)
		world.advance(20)
		t.expect(plot:GetAttribute("label")).toBe("Plot 1, Wheat ready")
		t.expect(world.find("Wheat") ~= nil).toBe(true)
		world.find("HarvestAll").Activated.fire()
		t.expect(world.farm.coins:peek()).toBe(120 - farmModel.PLOW_COST - 5 + 14)
		t.expect(world.find("Coins").Text).toBe(`{world.farm.coins:peek()} coins`)
		local previous
		for _ = 1, 3 do
			world.find("Market").Activated.fire()
			world.step(40)
			local row = world.find("Seed_wheat")
			t.expect(row ~= nil and row ~= previous).toBe(true)
			previous = row
			world.find("SheetPanel"):FindFirstChild("Close", true).Activated.fire()
			world.step(40)
			t.expect(world.farm.marketOpen:peek()).toBe(false)
			t.expect(world.find("Seed_wheat")).toBeNil()
		end
		t.expect(world.find("SeedMarket"):GetAttribute("FacetError")).toBeNil()
		world.find("Market").Activated.fire()
		t.expect(#world.screen:FindFirstChild("Field", true):GetChildren() > 20).toBe(true)
		world.farm.marketOpen:set(false)
		world.step(40)
		t.expect(world.find("Board").Visible).toBe(true)
		world.find("View").Activated.fire()
		t.expect(world.farm.view:peek()).toBe("3d")
		t.expect(world.find("Board").Visible).toBe(false)
		t.expect(world.find("View").Text).toBe("2D board")
		world.find("View").Activated.fire()
		t.expect(world.farm.view:peek()).toBe("2d")
		world.stop()
	end)
end)

return nil
