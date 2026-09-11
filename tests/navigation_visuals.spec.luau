--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local fake = require("./lib/fake_target")
local Facet = require("../src") :: any
local actions = require("../examples/gallery/scenarios/action_controls")
local tabs = require("../examples/gallery/scenarios/tab_view")
local function newAdapter()
	local a = fake.new()
	a.scrollBarThickness = fake.SCROLL_BAR_THICKNESS
	return a
end

local function pathEnding(w, suffix)
	for _, path in w.adapter.paths() do
		if path:sub(-#suffix) == suffix then
			return path
		end
	end
	error("missing " .. suffix)
end

t.describe("actions layout adaptation", function()
	t.it("measures fill columns at their placed pixel widths for aspect images", function()
		for width = 500, 510 do
			local w = world.new({ viewport = { x = 0, y = 0, w = width, h = 900 } })
			local U = Facet.UI
			local art = Facet.Controls.Button(w.core, {
				id = "Art",
				label = "Art",
				image = "rbxassetid://1",
				width = U.fill(),
				imageAspectRatio = 1,
				onActivate = function() end,
			})
			w.present(U.Screen({
				id = "S",
				children = {
					U.HStack({
						id = "Row",
						width = U.fill(),
						children = {
							U.VStack({ id = "Column", width = U.fill(), children = { art.blueprint } }),
							U.Box({ width = U.fill(), height = { type = "fixed", px = 1 } }),
						},
					}),
				},
			}))
			t.expect(#w.controller.diagnostics()).toBe(0)
			w.pres.dismiss(w.handle)
			art.dispose()
		end
	end)

	t.it("uses a compact centered confirmation with horizontal desktop actions", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1280, h = 800 }, newAdapter = newAdapter })
		local built = actions.build({ Facet = Facet, core = w.core, env = w.env, presenter = w.pres })
		w.present(built.screen)
		w.adapter.tap(pathEnding(w, "/Confirm"))
		w.settle(4)
		local accept = w.adapter.node(pathEnding(w, "/Accept")).rect
		local cancel = w.adapter.node(pathEnding(w, "/Cancel")).rect
		t.expect(math.abs(accept.y - cancel.y) < 1).toBe(true)
		t.expect(accept.x + accept.w <= cancel.x or cancel.x + cancel.w <= accept.x).toBe(true)
		local card = w.adapter.node(pathEnding(w, "/RaceConfirmation/Center/Card")).rect
		t.expect(card.w < 900 and card.h < 400).toBe(true)
		w.adapter.tap(pathEnding(w, "/Cancel"))
		w.settle(3)
		w.pres.dismiss(w.handle)
		built.dispose()
	end)
	t.it("reflows showroom and race setup when a desktop switches to distant viewing", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1440, h = 900 }, newAdapter = newAdapter })
		local built = actions.build({ Facet = Facet, core = w.core, env = w.env, presenter = w.pres })
		w.present(built.screen)
		local function boxes()
			return w.adapter.node(pathEnding(w, "/Showroom")).rect, w.adapter.node(pathEnding(w, "/RaceSetup")).rect
		end
		local a, b = boxes()
		t.expect(a.x + a.w <= b.x and math.abs(a.y - b.y) < 1).toBe(true)
		w.env:set("viewingDistance", "ten-foot")
		w.settle(4)
		a, b = boxes()
		t.expect(a.y + a.h <= b.y).toBe(true)
		t.expect(w.env:get("interactionClasses"):get().primary).toBe("pointer")
		w.pres.dismiss(w.handle)
		built.dispose()
	end)
end)

t.describe("navigation visual containment", function()
	for _, theme in { "pixel_quest", "fantasy_ornate" } do
		local package = require("../examples/themes/" .. theme).build(Facet.themes)
		local metrics = Facet.themes.resolve(package, nil, {})
		for _, view in
			{
				{ 390, 844, "Touch", "near" },
				{ 800, 450, "Gamepad", "near" },
				{ 1024, 768, "Touch", "near" },
				{ 1079, 809, "Touch", "near" },
				{ 1440, 900, "MouseKeyboard", "near" },
				{ 1920, 1080, "Gamepad", "ten-foot" },
			}
		do
			for _, fixture in { { "actions", actions }, { "tabs", tabs } } do
				t.it(theme .. " " .. fixture[1] .. " " .. view[1] .. "x" .. view[2] .. " largest text", function()
					local w = world.new({
						viewport = { x = 0, y = 0, w = view[1], h = view[2] },
						preferredInput = view[3],
						newAdapter = function()
							local a = fake.new()
							a.scrollBarThickness = fake.SCROLL_BAR_THICKNESS
							return a
						end,
						themeMetrics = metrics,
						env = { preferredTextOffset = 14, viewingDistance = view[4] },
					})
					local built = fixture[2].build({
						Facet = Facet,
						core = w.core,
						env = w.env,
						presenter = w.pres,
						actionSystem = w.system,
						adapter = w.adapter,
					})
					w.present(built.screen, built.present)
					if fixture[1] == "actions" then
						local art = w.controller.rectOf(pathEnding(w, "/HeroScene/HeroArt"))
						t.expect(art ~= nil and art.w > 0 and art.h >= 240).toBe(true)
						built.steps.showSettings()
						w.settle(40)
						built.steps.showDrivers()
						w.settle(40)
						built.steps.showHero()
						w.settle(40)
					else
						built.steps.customize()
						w.settle(40)
						built.steps.select(built, "me")
						w.settle(40)
					end
					w.pres.dismiss(w.handle)
					built.dispose()
				end)
			end
		end
	end
end)

t.describe("navigation capsule art", function()
	t.it("uses navigation chrome instead of a full decorated panel", function()
		local w = world.new({
			viewport = { x = 0, y = 0, w = 1920, h = 1080 },
			preferredInput = "Gamepad",
			env = {
				viewingDistance = "ten-foot",
			},
		})
		local tab = Facet.Controls.TabView(w.core, {
			env = w.env,
			selection = w.core:signal("a"),
			style = "sidebarAdaptable",
			tabs = {
				{
					id = "a",
					label = "Garage",
					content = function()
						return Facet.UI.Button({ id = "Play", label = "Play" })
					end,
				},
			},
		})
		w.present(Facet.UI.Screen({ id = "S", children = { tab.blueprint } }))
		tab.collapseSidebar()
		w.settle(4)
		local found
		local function walk(n)
			if n.id == "AdaptableBar" then
				found = n
			end
			for _, c in n.children or {} do
				walk(c)
			end
		end
		walk(w.handle.root.node)
		t.expect(found ~= nil).toBe(true)
		t.expect(found.meta and found.meta.decoration and found.meta.decoration.slot).toBe("navigation")
		w.pres.dismiss(w.handle)
		tab.dispose()
	end)
end)

t.describe("navigation capsule adaptive paint order", function()
	for _, batched in { false, true } do
		t.it("assigns capsule paint order after compact to distant resize, batched " .. tostring(batched), function()
			local package = require("../examples/themes/fantasy_ornate").build(Facet.themes)
			local w = world.new({
				viewport = { x = 0, y = 0, w = 390, h = 844 },
				preferredInput = "Touch",
				themeMetrics = Facet.themes.resolve(package, nil, {}),
				env = { viewingDistance = "near" },
			})
			local built = tabs.build({
				Facet = Facet,
				core = w.core,
				env = w.env,
				presenter = w.pres,
				actionSystem = w.system,
				adapter = w.adapter,
			})
			w.present(built.screen, built.present)
			for _ = 1, 2 do
				local function resize()
					w.env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
					w.env:set("viewingDistance", "ten-foot")
					w.env:set("preferredInput", "Gamepad")
					w.env:set("displaySize", "Large")
				end
				if batched then
					w.env:batch(resize)
				else
					resize()
				end
				w.settle(4)
				local count = 0
				for _, path in w.adapter.paths() do
					if string.find(path, "/AdaptableBar", 1, true) then
						count += 1
						local node = w.adapter.node(path)
						t.expect({ path = path, assigned = type(node.z) == "number" and node.z > 1 })
							.toEqual({ path = path, assigned = true })
						local base = string.match(path, "^(.-/AdaptableBar)")
						if path ~= base then
							t.expect(node.z > w.adapter.node(base).z).toBe(true)
						end
					end
				end
				t.expect(count > 2).toBe(true)
				w.env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
				w.env:set("viewingDistance", "near")
				w.env:set("preferredInput", "Touch")
				w.env:set("displaySize", "Small")
				w.settle(4)
			end
			w.pres.dismiss(w.handle)
			built.dispose()
		end)
	end
end)
