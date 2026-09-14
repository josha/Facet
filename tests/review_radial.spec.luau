--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Facet = require("../src") :: any
local scenario = require("../examples/gallery/scenarios/radial_menu")
t.describe("handheld character commands", function()
	for _, size in { { 1280, 720 }, { 960, 540 }, { 800, 600 }, { 677, 338 } } do
		t.it("fits " .. size[1] .. "x" .. size[2], function()
			local w = world.new({
				viewport = { x = 0, y = 0, w = size[1], h = size[2] },
				preferredInput = "Gamepad",
				env = { viewingDistance = "near" },
			})
			local s = scenario.build({
				Facet = Facet,
				core = w.core,
				env = w.env,
				presenter = w.pres,
				actionSystem = w.system,
			})
			w.present(s.screen, s.present)
			s.steps.character()
			w.settle(3)
			s.steps.open()
			w.settle(3)
			t.expect(s.report().menu.presentation).toBe(if size[2] >= 540 then "radial" else "list")
			w.pres.dismiss(w.handle)
		end)
	end
end)
