--!strict

local fs = require("@std/fs")
local process = require("@std/process")
local Loader = require("../../tests/lib/loader")
local Lute = require("../vendor/verify/src/lute")
local App = require("../../src/ui/app")

local loader = Loader.new()
local Facet = loader.require((process.args[4] or "src") .. "/init.luau") :: typeof(require("../../src"))
local engineLib = loader.require("tests/lib/native_engine.luau") :: typeof(require("../../tests/lib/native_engine"))
local workspacePath = assert(process.args[2], "expected the saved workspace")
local phone = process.args[3] == "phone-portrait"
local engine = engineLib.new()
local runtime = Facet.Roblox.createRuntime(engine)
local gui = engine.new("GuiService")
gui.IsTenFootInterface = function(): boolean
	return false
end
gui.GetGuiInset = function(): (Vector2, Vector2)
	return engine.types.Vector2.new(0, 58), engine.types.Vector2.zero
end
local playerGui = engine.new("PlayerGui")
local owner = engine.new("ModuleScript")
local app: App.App? = nil
local facade: { [string]: unknown } = table.clone((Facet :: unknown) :: { [string]: unknown })
facade.app = function(options: App.AppOptions): App.App
	options.runtime = runtime
	options.types = engine.types
	options.services = { GuiService = gui }
	options.focusRing = false
	options.environment = {
		viewportSize = engine.types.Vector2.new(if phone then 389 else 1919, if phone then 843 else 1080),
		touchEnabled = phone,
		viewingDistance = "automatic",
	}
	app = Facet.app(options)
	return assert(app)
end
local hubReference = { Shop = "Shop", Economy = "Economy" }
local services: { [string]: unknown } = {
	ReplicatedStorage = { Packages = { Facet = "Facet" }, Shared = { Hub = hubReference } },
	GuiService = gui,
	ContextActionService = {},
	RunService = { Heartbeat = engine.heartbeat },
}
local modules: { [unknown]: unknown } = { Facet = facade, [hubReference] = {}, Shop = {}, Economy = {} }
local environment: { [string]: unknown } = table.clone((engine.types :: unknown) :: { [string]: unknown })
environment.game = {
	GetService = function(_self: unknown, name: string): unknown
		return assert(services[name], name)
	end,
}
environment.script = { Theme = "Theme", Model = "Model", Destroying = owner.Destroying }
environment.task = { spawn = function(_body: () -> ()) end, defer = function(_body: () -> ()) end }
environment.require = function(reference: unknown): unknown
	return assert(modules[reference], tostring(reference))
end
local function load(name: string): unknown
	local file = workspacePath .. "/src/client/Interface/" .. name .. ".luau"
	return Lute.chunk.load(fs.readFileToString(file), { name = file, environment = environment })()
end
modules.Theme = load("Theme")
modules.Model = load("Model")
local interface = load("init") :: { mount: (unknown) -> () }
local function connection(): { Disconnect: () -> () }
	return { Disconnect = function() end }
end
local started = os.clock()
interface.mount({
	playerGui = playerGui,
	economy = {
		getState = function(): unknown
			return {
				coins = 1000,
				gems = 50,
				perSecond = 1,
				zone = 1,
				zoneProgress = 10,
				zoneGoal = 1000,
				boostPrice = 10,
				quests = {},
				offer = { name = "Offer", bought = false, endsAt = 100, coins = 1000, price = 20 },
			}
		end,
		serverNow = function(): number
			return 0
		end,
		onStateChanged = connection,
	},
	shop = {
		getState = function(): unknown
			return { owned = {}, wallet = { Coins = 1000, Gems = 50 } }
		end,
		onStateChanged = connection,
		catalog = {},
	},
	hub = {
		getState = function(): unknown
			return { level = 1 }
		end,
		onStateChanged = connection,
	},
})
print(
	`saved mount policy: {process.args[3]} {(os.clock() - started) * 1000} ms; native layout and asynchronous tasks excluded`
)
assert(app).dispose()
runtime:dispose()
