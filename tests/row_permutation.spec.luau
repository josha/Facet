--!strict
-- Plan E: unchanged row order is geometry dirt, while payload dirt still measures.
local t = require("./lib/testkit")
local Facet = require("../src")
local fake = require("./lib/fake_target")
local function world(full: boolean, opts: any?)
	opts = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 600, h = 1000 })
	local items = {}
	for i = 1, 96 do
		items[i] = {
			key = tostring(i),
			height = core:signal({ type = "fixed", px = 20 + i % 3 }),
			label = core:signal("row " .. i),
		}
	end
	local rows = core:signal(items)
	local bp = Facet.UI.Screen({
		id = "S",
		children = {
			(if opts.horizontal then Facet.UI.HStack else Facet.UI.VStack)({
				id = "List",
				width = { type = "fill" },
				height = if opts.fixedList then { type = "fixed", px = 1000 } else { type = "content" },
				gap = opts.gap or 2,
				padding = opts.padding,
				distribute = opts.distribute,
				children = {
					Facet.UI.Box({
						id = "Header",
						width = { type = "fixed", px = 100 },
						height = { type = "fixed", px = 17 },
					}),
					Facet.UI.ForEach({
						id = "Rows",
						items = rows,
						key = function(item)
							return item.key
						end,
						row = function(item)
							return Facet.UI.ZStack({
								id = "Row",
								width = if opts.horizontalKnown then item.height else { type = "fill" },
								height = if opts.horizontalKnown then { type = "fixed", px = 22 } else item.height,
								margin = opts.margin,
								children = {
									Facet.UI.Box({
										id = "A",
										width = { type = "fixed", px = 10 },
										height = {
											type = "fixed",
											px = 10,
										},
									}),
									if opts.withText
										then Facet.UI.Text({
											id = "B",
											text = item.label,
											width = { type = "fixed", px = 40 },
											textSize = 12,
										})
										else Facet.UI.Box({
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
			if items[1].label then
				items[1].label:set("changed content that wraps over the narrow row")
			end
			if not opts.textOnly then
				items[1].height:set({ type = "fixed", px = 47 })
			end
		end
		local out = {}
		for i = #items, 1, -1 do
			out[#out + 1] = items[i]
		end
		items = out
		rows:set(out)
		controller.refresh()
	end
	local added = 0
	local function snapshot()
		t.expect(core:lastError()).toBeNil()
		local paths = adapter.paths()
		table.sort(paths)
		local out = {}
		for _, path in paths do
			local n = adapter.node(path)
			local r = n.rect
			if r then
				out[#out + 1] = `{path}:{r.x},{r.y},{r.w},{r.h}`
				for _, key in { "rectOf", "screenRectOf" } do
					local public = controller[key](path)
					if public then
						out[#out + 1] = `{key}:{public.x},{public.y},{public.w},{public.h}`
					end
				end
			end
		end
		local findings = {}
		for _, d in controller.diagnostics() do
			findings[#findings + 1] = `{d.node}:{d.issue}`
		end
		table.sort(findings)
		out[#out + 1] = table.concat(findings, ";")
		return table.concat(out, "\n")
	end
	return {
		reverse = reverse,
		adapter = adapter,
		splice = function(remove)
			local out = table.clone(items)
			if remove then
				table.remove(out, 3)
			else
				added += 1
				table.insert(out, 3, { key = "added" .. added, height = core:signal({ type = "fixed", px = 23 }) })
			end
			items = out
			rows:set(out)
			controller.refresh()
		end,
		snapshot = snapshot,
		controller = controller,
		dispose = function()
			t.expect(core:lastError()).toBeNil()
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
		print(
			"PERMUTATION",
			st.lastMeasureCalls,
			st.lastArranged,
			st.rectWrites,
			st.lastArrangeEntries,
			st.lastPlaceScanned
		)
		t.expect(st.lastMeasureCalls <= 10).toBe(true)
		t.expect(st.lastArrangeEntries <= 4).toBe(true)
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

t.describe("row prefix refusal and chained replay", function()
	for _, opts in
		{
			{ name = "changed text", withText = true },
			{ name = "text-only change", withText = true, textOnly = true },
			{ name = "horizontal prefix", horizontal = true, horizontalKnown = true },
			{ name = "fractional gap", gap = 1.5 },
			{ name = "fractional origin", padding = 0.5 },
			{ name = "margin", margin = 3 },
			{ name = "horizontal", horizontal = true },
			{ name = "distribution", distribute = "center" },
		}
	do
		t.it(opts.name .. " preserves geometry and findings through mixed and clean frames", function()
			local a, b = world(false, opts), world(true, opts)
			for step, changed in { false, false, true, false, false } do
				a.reverse(changed)
				b.reverse(changed)
				t.expect(a.snapshot()).toBe(b.snapshot())
				if opts.horizontalKnown and step == 1 then
					t.expect(a.controller.stats().lastArrangeEntries <= 4).toBe(true)
				end
				for _, path in a.adapter.paths() do
					for _, key in { "text", "textWrapped", "compactLabel" } do
						t.expect(a.adapter.node(path).props[key]).toBe(b.adapter.node(path).props[key])
					end
				end
			end
			a.dispose()
			b.dispose()
		end)
	end
end)

t.describe("host local paint order", function()
	local function ranking(w, localScope)
		local paths = w.adapter.paths()
		table.sort(paths, function(a, b)
			local na, nb = w.adapter.node(a), w.adapter.node(b)
			local pa, pb =
				if localScope then (na.instanceHost and na.instanceHost.path) or "" else "",
				if localScope then (nb.instanceHost and nb.instanceHost.path) or "" else ""
			if pa ~= pb then
				return pa < pb
			end
			return na.z < nb.z
		end)
		return table.concat(paths, "\n")
	end
	t.it("reorders hosts without visiting their clean children, against a full z walk", function()
		local a, b = world(false), world(true)
		local before = a.controller.stats().zVisits
		a.reverse(false)
		b.reverse(false)
		b.controller.initialRender()
		t.expect(ranking(a, true)).toBe(ranking(b, true))
		local visits = a.controller.stats().zVisits - before
		print("HOST Z VISITS", visits)
		t.expect(visits <= 105).toBe(true)
		for step = 1, 12 do
			if step % 3 == 0 then
				a.splice(true)
				b.splice(true)
			elseif step % 3 == 1 then
				a.splice(false)
				b.splice(false)
			else
				a.reverse(step % 2 == 0)
				b.reverse(step % 2 == 0)
			end
			b.controller.initialRender()
			t.expect(ranking(a, true)).toBe(ranking(b, true))
		end
		-- Acquiring a cross-host reader after local numbering must restore ranking
		-- immediately, before the first drop target can ask for a tie break.
		a.controller.dragRegistry()
		t.expect(ranking(a, false)).toBe(ranking(b, false))
		a.reverse(false)
		b.reverse(false)
		b.controller.initialRender()
		t.expect(ranking(a, false)).toBe(ranking(b, false))
		a.dispose()
		b.dispose()
	end)
end)

t.describe("surviving row extents", function()
	t.it("removing a row reuses surviving measurements against forced full", function()
		local a, b = world(false), world(true)
		a.splice(true)
		b.splice(true)
		t.expect(a.snapshot()).toBe(b.snapshot())
		print("REMOVE CALLS", a.controller.stats().lastMeasureCalls)
		t.expect(a.controller.stats().lastMeasureCalls <= 100).toBe(true)
		for step = 1, 4 do
			a.reverse(step % 2 == 0)
			b.reverse(step % 2 == 0)
			a.splice(true)
			b.splice(true)
			t.expect(a.snapshot()).toBe(b.snapshot())
		end
		a.dispose()
		b.dispose()
	end)
end)

t.describe("suffix rebase after deletion", function()
	t.it("places the shifted suffix without entering each hosted row", function()
		local a, b = world(false, { fixedList = true }), world(true, { fixedList = true })
		a.splice(true)
		b.splice(true)
		t.expect(a.snapshot()).toBe(b.snapshot())
		print("REMOVE ENTRIES", a.controller.stats().lastArrangeEntries, a.controller.stats().lastMeasureCalls)
		t.expect(a.controller.stats().lastArrangeEntries <= 4).toBe(true)
		for step = 1, 4 do
			a.splice(true)
			b.splice(true)
			t.expect(a.snapshot()).toBe(b.snapshot())
		end
		a.dispose()
		b.dispose()
	end)
end)

t.describe("host-local ordering after an interrupted adapter write", function()
	t.it("restores global priority and retries a failed restoration", function()
		local zOrder = require("../src/render/z_order")
		local zScope = require("../src/render/z_scope")
		local function node(path, children, host)
			return { path = path, class = "Box", props = {}, children = children or {}, hostSpace = host }
		end
		local a = node("/S/A", { node("/S/A/a"), node("/S/A/b") }, true)
		local b = node("/S/B", { node("/S/B/a"), node("/S/B/b") }, true)
		local c = node("/S/C", { node("/S/C/a"), node("/S/C/b") }, true)
		local root = { node = node("/S", { a, b, c }) }
		local handles, lastZ = {}, {}
		local function collect(n)
			handles[n.path] = { path = n.path }
			for _, child in n.children do
				collect(child)
			end
		end
		collect(root.node)
		local fail = false
		local z = zOrder.new({
			root = root,
			handles = handles,
			lastZ = lastZ,
			hitLift = { any = false },
			metrics = function()
				return nil
			end,
			stats = { zMemoEntries = 0, zPasses = 0, zVisits = 0 },
			adapter = {
				setZOrder = function(h, _value)
					if fail and h.path == "/S/B" then
						error("injected adapter failure")
					end
				end,
			},
		})
		z.sync(nil)
		root.node.children = { c, a, b }
		fail = true
		local ok = pcall(function()
			z.sync({ { path = "/S", node = root.node } })
		end)
		t.expect(ok).toBe(false)
		t.expect(zScope.of(lastZ).localNumbers).toBe(true)
		ok = pcall(function()
			zScope.requireGlobal(lastZ)
		end)
		t.expect(ok).toBe(false)
		t.expect(zScope.of(lastZ).global).toBe(false)
		t.expect(zScope.of(lastZ).localNumbers).toBe(true)
		fail = false
		zScope.requireGlobal(lastZ)
		t.expect(lastZ["/S/C/a"] < lastZ["/S/A/a"]).toBe(true)
		t.expect(lastZ["/S/A/a"] < lastZ["/S/B/a"]).toBe(true)
		t.expect(zScope.of(lastZ).localNumbers).toBe(false)
	end)
end)
