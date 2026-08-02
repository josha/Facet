local customFactory = require("../../src/core/custom")
local UI = require("../../src/blueprint")
local mountLib = require("../../src/mount")
local environment = require("../../src/env/environment")
local renderer = require("../../src/render/renderer")
local text_metrics = require("../../src/layout/text_metrics")
local fake_target = require("../../tests/lib/fake_target")
local LuauUI = require("../../src")

-- the engine's real numbers, measured live 2026-07-24
local ENGINE = {
	["16| "] = 3.5,
	["16|Volume"] = 45,
	["16|Brightness"] = 62.5,
	["14|Quality"] = 36,
	["14|Download"] = 51,
	["16|Save"] = 27.5,
	["16|changes"] = 50,
}
local core = customFactory.new()
local env = environment.new(core)
env:set("viewportRect", { x = 0, y = 0, w = 1233, h = 1067 })
env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
local volume = core:signal(6)
local stepper =
	LuauUI.newStepper(LuauUI, core, { id = "Volume", label = "Volume", value = volume, min = 0, max = 10, step = 1 })
local screen = UI.Screen({
	id = "S",
	padding = 0,
	children = {
		UI.Text({ id = "Heading", text = "Volume", textSize = 16 }),
		stepper.blueprint,
	},
})
local root = mountLib.mount(core, screen)
local adapter = fake_target.new()
function adapter.measureTextWidths(requests, done)
	local results = {}
	for _, r in requests do
		table.insert(results, { font = r.font, size = r.size, word = r.word, width = ENGINE[`{r.size}|{r.word}`] })
	end
	done(results)
end
local controller = renderer.attach(core, root, env, adapter, {})
controller.initialRender()
print("plain Text /S/Heading   :", adapter.node("/S/Heading").rect.w)
print("stepper label /S/Volume/Label:", adapter.node("/S/Volume/Label").rect.w)
print("requests seen           :", text_metrics.measuredCount())
print("stored Volume@16        :", text_metrics.measuredWidth("BuilderSans", 16, "Volume"))
