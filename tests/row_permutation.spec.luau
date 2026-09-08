--!strict
-- Plan E: unchanged row order is geometry dirt, while payload dirt still measures.
local t = require("./lib/testkit")
local Facet = require("../src")
local fake = require("./lib/fake_target")
local function world(full: boolean)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 600, h = 1000 })
	local items = {}
	for i = 1, 96 do
		items[i] = { key = tostring(i), height = core:signal({ type = "fixed", px = 20 + i % 3 }) }
	end
	local rows = core:signal(items)
	local bp = Facet.UI.Screen({
		id = "S",
		children = {
			Facet.UI.VStack({
				id = "List",
				width = { type = "fill" },
				height = { type = "content" },
				gap = 2,
				children = {
					Facet.UI.ForEach({
						id = "Rows",
						items = rows,
						key = function(item)
							return item.key
						end,
						row = function(item)
							return Facet.UI.ZStack({
								id = "Row",
								width = { type = "fill" },
								height = item.height,
								children = {
									Facet.UI.Box({
										id = "A",
										width = { type = "fixed", px = 10 },
										height = {
											type = "fixed",
											px = 10,
										},
									}),
									Facet.UI.Box({
										id = "B",
										width = { type = "fixed", px = 5 },
										height = {
											type = "fixed",
											px = 5,
										},
									}),
								},
							})
						end,
					}),
				},
			}),
		},
	})
	local root = Facet.mount(core, bp)
	local adapter = fake.new()
	local controller = Facet.renderer.attach(
		core,
		root,
		env,
		adapter,
		{ rootPolicy = "edgeToEdge", structuralReuse = not full, incrementalLayout = not full, measureReuse = not full }
	)
	controller.initialRender()
	-- Establish the incremental memo on a settled session before the measured drive.
	items[1].height:set({ type = "fixed", px = 22 })
	controller.refresh()
	items[1].height:set({ type = "fixed", px = 21 })
	controller.refresh()
	local function reverse(changed: boolean)
		if changed then
			items[1].height:set({ type = "fixed", px = 47 })
		end
		local out = {}
		for i = #items, 1, -1 do
			out[#out + 1] = items[i]
		end
		items = out
		rows:set(out)
		controller.refresh()
	end
	local function snapshot()
		local paths = adapter.paths()
		table.sort(paths)
		local out = {}
		for _, path in paths do
			local n = adapter.node(path)
			local r = n.rect
			if r then
				out[#out + 1] = `{path}:{r.x},{r.y},{r.w},{r.h}`
			end
		end
		return table.concat(out, "\n")
	end
	return {
		reverse = reverse,
		snapshot = snapshot,
		controller = controller,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

t.describe("row permutation measurement", function()
	t.it("does not remeasure clean hosted rows, against an independent forced-full oracle", function()
		local a, b = world(false), world(true)
		a.reverse(false)
		b.reverse(false)
		t.expect(a.snapshot()).toBe(b.snapshot())
		local st = a.controller.stats()
		print("PERMUTATION", st.lastMeasureCalls, st.lastArranged, st.rectWrites)
		t.expect(st.lastMeasureCalls <= 10).toBe(true)
		a.dispose()
		b.dispose()
	end)
	t.it("a permutation with a changed row measures its new height", function()
		local a, b = world(false), world(true)
		a.reverse(true)
		b.reverse(true)
		t.expect(a.snapshot()).toBe(b.snapshot())
		t.expect(a.controller.stats().lastMeasured > 1).toBe(true)
		a.reverse(false)
		b.reverse(false)
		t.expect(a.snapshot()).toBe(b.snapshot())
		a.dispose()
		b.dispose()
	end)
end)
