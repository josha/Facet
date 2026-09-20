--!strict
--[[ AN INTERACTIVE CONTAINER IS NEVER LEFT WITHOUT AN OBJECT.

	Container elision is CREATION-TIME: the adapter gives a layout-only class
	(VStack, HStack, ZStack, Grid, Anchor, Spacer) a handle and no engine object,
	because 40% of a surface's instances paint nothing. `create` cannot know that
	such a node will LATER be handed pointer handlers or a drag detector, so every
	other seam materialises on demand — that is the whole design.

	Two seams stopped doing it. `screen_pointer.setPointerHandlers` and
	`screen_target.setDragDetector` returned early on `instance == nil` (guards
	added after a live crash), which drops the declaration for good and silently:
	a `UI.draggable` VStack — a showcase card is exactly that — would simply never
	be draggable, and nothing would say so.

	The fake target mirrors the rule, so this is provable headlessly. ]]
local t = require("./lib/testkit")
local Facet = require("../src")
local fake = require("./lib/fake_target")
local Compose = Facet.Compose

local function world()
	local adapter, frame = fake.new(), nil
	local app = Facet.new({
		newAdapter = function()
			return adapter
		end,
		newInputSystem = function(core)
			return Facet.newActionSystem(core)
		end,
		bindEnv = function(env)
			env:set("viewportRect", { x = 0, y = 0, w = 640, h = 480 })
			env:set("reducedMotion", true)
			return function() end
		end,
		connectFrame = function(fn)
			frame = fn
			return function() end
		end,
	})
	return app, adapter, function(count: number?)
		for _ = 1, count or 3 do
			frame(1 / 60)
		end
	end
end

local fill = { type = "fill" }

t.describe("elided containers and interaction seams", function()
	t.it("elides an inert layout container and leaves it without an object", function()
		local app, adapter, settle = world()
		local UI = app.controls
		app.mount(function()
			return UI.Screen("S")({
				UI.VStack("Inert")({ width = fill, UI.Text("T")({ text = "hi" }) }),
			})
		end)
		settle(3)
		local node = assert(adapter.node("/S/Inert"))
		t.expect(node.elided).toBe(true)
		app.dispose()
	end)

	t.it("materialises a draggable container and lands its drag declaration", function()
		local app, adapter, settle = world()
		local UI = app.controls
		app.mount(function()
			return UI.Screen("S")({
				UI.draggable(
					UI.VStack("Card")({
						width = { type = "fixed", px = 120 },
						height = { type = "fixed", px = 80 },
						UI.Text("T")({ text = "card" }),
					}),
					{ payload = { kind = "card", id = "a" } }
				),
				UI.VStack("Inert")({ width = fill, height = { type = "fixed", px = 60 } }),
			})
		end)
		settle(3)
		local card = assert(adapter.node("/S/Card"))
		-- the drag declaration bought the card an engine object...
		t.expect(card.elided).toBe(nil)
		t.expect(card.materialized).toBe(true)
		-- ...and it actually landed on one of the two acquisition seams
		t.expect(card.dragDetector ~= nil or card.pointer ~= nil).toBe(true)
		-- ...while its inert sibling is still free
		t.expect(assert(adapter.node("/S/Inert")).elided).toBe(true)
		app.dispose()
	end)

	t.it("drives a real drag on the materialised container", function()
		local app, adapter, settle = world()
		local UI = app.controls
		local dropped = 0
		app.mount(function()
			return UI.Screen("S")({
				UI.draggable(
					UI.VStack("Card")({
						width = { type = "fixed", px = 120 },
						height = { type = "fixed", px = 80 },
						UI.Text("T")({ text = "card" }),
					}),
					{ payload = { kind = "card", id = "a" } }
				),
				UI.dropTarget(UI.VStack("Bin")({ width = fill, height = { type = "fixed", px = 200 } }), {
					onDrop = function()
						dropped += 1
					end,
				}),
			})
		end)
		settle(3)
		local card = assert(adapter.node("/S/Card"))
		local bin = assert(adapter.node("/S/Bin"))
		t.expect(card.elided).toBe(nil)
		local to = { x = bin.rect.x + bin.rect.w / 2, y = bin.rect.y + bin.rect.h / 2 }
		local from = { x = card.rect.x + card.rect.w / 2, y = card.rect.y + card.rect.h / 2 }
		adapter.driveDragStart(card.path, from)
		settle(1)
		adapter.driveDragContinue(card.path, to, { x = to.x - from.x, y = to.y - from.y })
		settle(1)
		adapter.driveDragEnd(card.path, to)
		settle(3)
		t.expect(dropped).toBe(1)
		app.dispose()
	end)

	t.it("materialises a container that is given a hit rect", function()
		local app, adapter, settle = world()
		local UI = app.controls
		local handle = assert(adapter)
		app.mount(function()
			return UI.Screen("S")({ UI.VStack("Inert")({ width = fill }) })
		end)
		settle(3)
		local node = assert(handle.node("/S/Inert"))
		t.expect(node.elided).toBe(true)
		handle.setHitRect(node, { x = 0, y = 0, w = 44, h = 44 })
		t.expect(node.elided).toBe(nil)
		t.expect(node.materialized).toBe(true)
		local _ = Compose
		app.dispose()
	end)
end)
