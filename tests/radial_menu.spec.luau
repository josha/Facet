--!strict
local t = require("./lib/testkit")
local it, expect = t.it, t.expect
local world = require("./lib/world")
local Facet = require("../src") :: any
local function setup(extra: any?)
	local w = world.new({
		viewport = { x = 0, y = 0, w = 800, h = 650 },
		capabilities = { pointer = true, keyboard = true, gamepad = true, touch = true },
	})
	local fired = {}
	local spec = {
		id = "Ctl",
		items = {
			{
				id = "wave",
				label = "Wave",
				icon = "flag",
				slot = "N",
				onSelect = function()
					table.insert(fired, "wave")
				end,
			},
			{
				id = "point",
				label = "Point",
				slot = "E",
				onSelect = function()
					table.insert(fired, "point")
				end,
			},
		},
		distribution = "compass",
	}
	for k, v in extra or {} do
		spec[k] = v
	end
	local c = Facet.Controls.RadialMenu(w.core, spec)
	w.present(Facet.UI.Screen({ id = "S", children = { c.blueprint } }))
	w.settle(2)
	return w, c, fired
end
local function launcher(w)
	for _, p in w.adapter.paths() do
		if p:match("/Launcher$") then
			return p
		end
	end
	error("missing launcher")
end
local function sector(c, id)
	for _, s in c.dump().sectors do
		if s.id == id then
			return s
		end
	end
	error("missing sector " .. id)
end
local function tapOpen(w, c)
	w.adapter.tap(launcher(w))
	w.settle(3)
	expect(c.dump().open).toBe(true)
end
t.describe("RadialMenu control", function()
	it("a new radial launcher waits for its solved position before painting", function()
		local w = world.new()
		local c = Facet.Controls.RadialMenu(w.core, {
			id = "Ctl",
			preset = "donut",
			items = { { id = "look", label = "Look" } },
		})
		local shown = w.core:signal(false)
		w.pres.present(Facet.UI.Screen({
			id = "Initial",
			children = {
				Facet.UI.When({
					condition = shown,
					thenView = function()
						return c.blueprint
					end,
				}),
			},
		}))
		shown:set(true)
		w.pres.refresh()
		for _ = 1, 3 do
			for _, p in w.adapter.paths() do
				if p:match("/LauncherVisual$") then
					local node = w.adapter.node(p)
					if node.canvasGroupInstance.groupTransparency < 1 then
						expect(node.rect.x >= 0 and node.rect.y >= 0).toBe(true)
					end
				end
			end
			w.pres.refresh()
		end
		expect(w.adapter.node(launcher(w)) ~= nil).toBe(true)
		c.dispose()
	end)

	it("all focal presets blend the launcher into closing and can reopen mid-exit", function()
		for _, preset in { "circle", "donut" } do
			for _, appearance in { "buttons", "wedges" } do
				for _, center in { "empty", "back", "close", "root", "content" } do
					local w, c = setup({ preset = preset, appearance = appearance, center = center })
					tapOpen(w, c)
					w.settle(60)
					c.api.close()
					for _ = 1, 6 do
						w.settle(1)
						local visual = w.adapter.node(launcher(w):match("^(.-/LauncherVisual)"))
						local opacity = 1 - visual.canvasGroupInstance.groupTransparency
						expect(opacity > 0 and opacity < 1).toBe(true)
						expect(math.abs(opacity + c.dump().opacity - 1) < 0.001).toBe(true)
					end
					w.adapter.tap(launcher(w))
					w.settle(3)
					expect(c.dump().open).toBe(true)
					c.api.close()
					w.settle(100)
					expect(c.dump().visible).toBe(false)
					expect(w.adapter.node(launcher(w)).rect.w > 0).toBe(true)
				end
			end
		end
	end)
	it("list dismissal hands off within the same animation without overlapping paint", function()
		local w, c = setup()
		w.env:set("viewportRect", { x = 0, y = 0, w = 420, h = 200 })
		w.settle(3)
		tapOpen(w, c)
		w.settle(60)
		c.api.close()
		local handoff = false
		for _ = 1, 80 do
			w.settle(1)
			for _, p in w.adapter.paths() do
				if p:match("/LauncherVisual$") and c.dump().visible then
					local opacity = 1 - w.adapter.node(p).canvasGroupInstance.groupTransparency
					if opacity > 0 then
						handoff = true
						for _, q in w.adapter.paths() do
							if q:match("/ListArea$") then
								expect(w.adapter.node(q).canvasGroupInstance.groupTransparency).toBe(1)
							end
						end
					end
				end
			end
		end
		expect(handoff).toBe(true)
	end)
	it("caller-owned launchers leave no overlapping built-in trigger", function()
		local w, c = setup({ launcher = false })
		local function noLauncher()
			for _, p in w.adapter.paths() do
				expect(p:match("/Launcher$") == nil).toBe(true)
			end
		end
		noLauncher()
		expect(c.api.open()).toBe(true)
		expect(c.api.isVisible:get()).toBe(true)
		w.settle(30)
		local s = sector(c, "wave")
		w.adapter.tap(s.path)
		w.settle(80)
		expect(c.dump().visible).toBe(false)
		noLauncher()
	end)

	it("projected clearance fits atomically and freezes with pointer selection", function()
		local core = Facet.newCore()
		local anchor = core:signal({ x = 400, y = 325, clearance = 115 })
		local w, c = setup({ anchor = anchor, clearance = 80, center = "empty" })
		tapOpen(w, c)
		w.settle(60)
		expect(sector(c, "wave").inner >= 115).toBe(true)
		local l, radius = c.dump(), sector(c, "wave").inner
		local s = sector(c, "wave")
		w.adapter.pointerDown(s.path, s.x, s.y, "touch")
		anchor:set({ x = 430, y = 325, clearance = 140 })
		w.settle(30)
		expect(c.dump().centerX).toBe(l.centerX)
		expect(sector(c, "wave").inner).toBe(radius)
		w.adapter.pointerUp(l.centerX, l.centerY)
		w.settle(90)
		expect(math.abs(c.dump().centerX - 430) < 0.1).toBe(true)
		expect(math.abs(sector(c, "wave").inner - 140) < 0.1).toBe(true)
	end)
	it("fixed following preserves opening clearance until the next opening", function()
		local core = Facet.newCore()
		local anchor = core:signal({ x = 400, y = 325, clearance = 115 })
		local w, c = setup({ anchor = anchor, follow = "fixed" })
		tapOpen(w, c)
		anchor:set({ x = 440, y = 325, clearance = 140 })
		w.settle(40)
		expect(math.abs(sector(c, "wave").inner - 115) < 0.001).toBe(true)
		expect(c.dump().centerX).toBe(400)
		c.api.close()
		w.settle(80)
		c.api.open()
		w.settle(30)
		expect(math.abs(sector(c, "wave").inner - 140) < 0.001).toBe(true)
		expect(c.dump().centerX).toBe(440)
	end)
	it("ornate portrait character ring fits while preserving its focal clearance", function()
		local pkg = require("../examples/themes/fantasy_ornate").build(Facet.themes)
		local w, c = setup({
			preset = "donut",
			center = "empty",
			distribution = "even",
			clearance = 82,
			ringWidth = "controlSizes.large.height",
			items = {
				{ id = "equipment", label = "Equipment", compactLabel = { icon = "menu", prefer = true } },
				{ id = "wave", label = "Wave", icon = "flag" },
				{ id = "inspect", label = "Inspect", icon = "facet:search" },
			},
		})
		w.env:set("themeMetrics", Facet.themes.resolve(pkg, nil, {}))
		w.env:set("viewportRect", { x = 0, y = 0, w = 360, h = 378 })
		w.settle(3)
		tapOpen(w, c)
		expect(c.dump().presentation).toBe("radial")
		for _, s in c.dump().sectors do
			expect(s.inner >= 82).toBe(true)
		end
	end)
	it("launcher compositors leave room for ornate circle borders", function()
		local pkg = require("../examples/themes/fantasy_ornate").build(Facet.themes)
		for _, preset in { "bottom-left", "donut" } do
			local w, c = setup({ preset = preset, distribution = "even" })
			w.env:set("themeMetrics", Facet.themes.resolve(pkg, nil, {}))
			w.settle(3)
			local button = w.adapter.node(launcher(w)).rect
			local group
			for _, p in w.adapter.paths() do
				if p:match("/LauncherVisual$") then
					group = w.adapter.node(p).rect
				end
			end
			expect(button.x - group.x >= 2).toBe(true)
			expect(button.y - group.y >= 2).toBe(true)
			expect(group.x + group.w - button.x - button.w >= 2).toBe(true)
			expect(group.y + group.h - button.y - button.h >= 2).toBe(true)
		end
	end)
	it("corner navigation stays painted while an action closes into the launcher", function()
		local w, c = setup({
			preset = "bottom-left",
			appearance = "buttons",
			distribution = "even",
			items = { { id = "pack", label = "Pack", children = { { id = "map", label = "Map" } } } },
		})
		tapOpen(w, c)
		c.api.select("pack")
		w.settle(60)
		c.api.select("map")
		w.settle(2)
		for _, p in w.adapter.paths() do
			if p:match("/Back$") then
				w.adapter.tap(p)
			end
		end
		expect(c.dump().open).toBe(true)
		c.api.close()
		local closingFrames = 0
		for _ = 1, 100 do
			w.settle(1)
			local back, trigger
			for _, p in w.adapter.paths() do
				if p:match("/Back$") then
					back = w.adapter.node(p)
				end
				if p:match("/Launcher$") then
					trigger = w.adapter.node(p)
				end
			end
			if c.dump().visible then
				closingFrames += 1
				expect(back ~= nil).toBe(true)
				expect(back.rect.w >= 32 and back.rect.w <= 44).toBe(true)
				expect(back.rect.h).toBe(back.rect.w)
				local opacity = 0
				for _, p in w.adapter.paths() do
					if p:match("/NavigationIcon$") or p:match("/LauncherIcon$") then
						opacity += 1 - w.adapter.node(p).canvasGroupInstance.groupTransparency
					end
				end
				expect(math.abs(opacity - 1) < 0.001).toBe(true)
				expect(trigger == nil).toBe(true)
			else
				expect(trigger ~= nil).toBe(true)
				expect(back == nil).toBe(true)
				break
			end
		end
		expect(closingFrames > 2).toBe(true)
	end)
	it("landscape corners compact before falling back without shrinking touch targets", function()
		for _, preset in { "bottom-left", "bottom-right", "top-left", "top-right" } do
			for _, height in { 209, 165 } do
				local calls = 0
				local w, c = setup({
					preset = preset,
					appearance = "buttons",
					distribution = "even",
					items = {
						{
							id = "look",
							label = "Look",
							icon = "facet:search",
							onSelect = function()
								calls += 1
							end,
						},
						{ id = "pack", label = "Pack", icon = "menu" },
						{ id = "wave", label = "Wave", icon = "flag" },
					},
				})
				w.env:set("viewportRect", { x = 0, y = 0, w = 469, h = height })
				w.settle(3)
				tapOpen(w, c)
				w.settle(60)
				local d = c.dump()
				expect(d.presentation).toBe("radial")
				for i, s in d.sectors do
					expect(s.size >= 44).toBe(true)
					expect(s.x - s.size / 2 >= 0 and s.x + s.size / 2 <= d.windowRect.w).toBe(true)
					expect(s.y - s.size / 2 >= 0 and s.y + s.size / 2 <= d.windowRect.h).toBe(true)
					for j = i + 1, #d.sectors do
						local other = d.sectors[j]
						expect((s.x - other.x) ^ 2 + (s.y - other.y) ^ 2 >= ((s.size + other.size) / 2) ^ 2).toBe(true)
					end
				end
				w.adapter.tap(d.sectors[1].path)
				w.settle(3)
				expect(c.dump().open).toBe(false)
				expect(calls).toBe(1)
			end
		end
	end)
	it("compact fitting retains explicit clearance and falls back below minimum touch size", function()
		for _, case in { { height = 209, clearance = 150 }, { height = 120 } } do
			local w, c = setup({
				preset = "bottom-left",
				appearance = "buttons",
				distribution = "even",
				clearance = case.clearance,
			})
			w.env:set("viewportRect", { x = 0, y = 0, w = 469, h = case.height })
			w.settle(3)
			tapOpen(w, c)
			expect(c.dump().presentation).toBe("list")
			if case.clearance then
				expect(c.dump().sectors[1].inner >= case.clearance).toBe(true)
			end
		end
	end)
	it("corner opening and closing keep the launcher fixed under the shared transform", function()
		for _, preset in { "bottom-left", "bottom-right", "top-left", "top-right" } do
			for _, appearance in { "buttons", "wedges" } do
				local w, c = setup({ preset = preset, appearance = appearance, distribution = "even" })
				-- Reverse both ways before settling: the pivot must not change on interruption.
				for _, open in { true, false, true } do
					if open then
						c.api.open()
					else
						c.api.close()
					end
					w.settle(2)
					local d = c.dump()
					local rings
					for _, p in w.adapter.paths() do
						if p:match("/Rings$") then
							rings = w.adapter.node(p)
						end
					end
					expect(rings ~= nil).toBe(true)
					local r, scale = rings.rect, rings.props.transform.scale
					local painted = rings.presentedPosition
					local x = painted.x + r.w / 2 + (d.windowRect.x + d.centerX - r.x - r.w / 2) * scale
					local y = painted.y + r.h / 2 + (d.windowRect.y + d.centerY - r.y - r.h / 2) * scale
					expect(math.abs(x - d.windowRect.x - d.centerX) < 0.001).toBe(true)
					expect(math.abs(y - d.windowRect.y - d.centerY) < 0.001).toBe(true)
				end
			end
		end
	end)
	it("focus highlights the painted radial surface rather than its inner content", function()
		for _, appearance in { "buttons", "wedges" } do
			for _, surface in { "native", "none" } do
				local w, c = setup({ appearance = appearance, buttonSurface = surface })
				w.pres.focus.focusOn(launcher(w))
				w.press("Return")
				w.settle(60)
				local path = sector(c, "point").path
				w.pres.focus.focusOn(path)
				w.settle(2)
				local node = w.adapter.node(path)
				local contentFocus = appearance == "buttons" and surface == "none"
				expect(node.focused == true).toBe(contentFocus)
				expect(node.props.selected).toBe(true)
				if appearance == "buttons" and not contentFocus then
					local visual = path:match("^(.-/Visual)/")
					expect(w.adapter.node(visual .. "/Content/Disc").props.tint.role).toBe("accent")
				end
			end
		end
	end)
	it("compact icon content stays centered in its radial button", function()
		local w, c = setup({
			appearance = "buttons",
			preset = "bottom-left",
			distribution = "even",
			items = {
				{ id = "search", label = "Search", icon = "facet:search", labelStyle = "both" },
			},
		})
		tapOpen(w, c)
		w.settle(60)
		local path = sector(c, "search").path
		local button = w.adapter.node(path).rect
		local found = false
		for _, p in w.adapter.paths() do
			if p:find(path .. "/", 1, true) and p:match("/Compact$") then
				local r = w.adapter.node(p).rect
				if r.h > 0 then
					found = true
					expect(math.abs(r.x + r.w / 2 - button.x - button.w / 2) < 1).toBe(true)
					expect(math.abs(r.y + r.h / 2 - button.y - button.h / 2) < 1).toBe(true)
				end
			end
		end
		expect(found).toBe(true)
	end)
	it("closing a list fades its rows before restoring the launcher", function()
		local w, c = setup()
		w.env:set("viewportRect", { x = 0, y = 0, w = 420, h = 200 })
		w.settle(3)
		tapOpen(w, c)
		w.settle(60)
		c.api.close()
		w.settle(2)
		local area
		for _, p in w.adapter.paths() do
			expect(p:match("/Launcher$") == nil).toBe(true)
			if p:match("/ListArea$") then
				area = w.adapter.node(p)
			end
		end
		expect(area ~= nil).toBe(true)
		expect(area.canvasGroupInstance.groupTransparency > 0 and area.canvasGroupInstance.groupTransparency < 1).toBe(
			true
		)
		w.settle(120)
		expect(launcher(w) ~= nil).toBe(true)
	end)
	it("opening wedges share one scale so adjacent seams cannot round independently", function()
		local w, c = setup({ appearance = "wedges" })
		tapOpen(w, c)
		local rings
		for _, p in w.adapter.paths() do
			local n = w.adapter.node(p)
			if p:match("/Rings$") then
				rings = n
			end
			if p:match("/Visual$") then
				expect(n.props.transform.scale).toBe(1)
			end
		end
		expect(rings ~= nil).toBe(true)
		expect(rings.props.transform.scale > 0 and rings.props.transform.scale < 1).toBe(true)
	end)
	it("list launcher touch release and native activation echo latch once", function()
		local w, c, fired = setup()
		w.env:set("viewportRect", { x = 0, y = 0, w = 420, h = 200 })
		w.settle(3)
		local p, d = launcher(w), c.dump()
		w.adapter.pointerDown(p, d.centerX, d.centerY, "touch")
		w.adapter.pointerUp(d.centerX, d.centerY)
		w.adapter.tap(p, { pointerType = "touch" })
		w.settle(3)
		expect(c.dump().open).toBe(true)
		w.adapter.tap(sector(c, "wave").path, { pointerType = "touch" })
		expect(#fired).toBe(1)
	end)
	it("list fallback has one navigation control for every center policy", function()
		for _, center in { "empty", "back", "root", "close", "content" } do
			local w, c = setup({ center = center })
			w.env:set("viewportRect", { x = 0, y = 0, w = 420, h = 200 })
			w.settle(3)
			tapOpen(w, c)
			expect(c.dump().presentation).toBe("list")
			local count = 0
			for _, path in w.adapter.paths() do
				if
					path:match("/Back$")
					or path:match("/Center$")
					or (path:find("$navigation", 1, true) and path:match("/Item$"))
				then
					count += 1
				end
			end
			expect(count).toBe(1)
		end
	end)
	it("image-only buttons omit native plate and stroke with per-item overrides", function()
		local w, c = setup({
			appearance = "buttons",
			buttonSurface = "none",
			items = {
				{ id = "wave", label = "Wave", icon = "flag", slot = "N" },
				{ id = "point", label = "Point", slot = "E", buttonSurface = "native" },
			},
		})
		tapOpen(w, c)
		w.settle(60)
		for _, id in { "wave", "point" } do
			local visual = sector(c, id).path:match("^(.-/Visual)/")
			local props = w.adapter.node(visual .. "/Content/Disc").props
			expect(props.stroke ~= nil).toBe(id == "point")
			expect(props.tint ~= nil).toBe(id == "point")
		end
	end)
	it("slim bands share one pair of radii for unequal content", function()
		local w, c = setup({ contentFit = "radial" })
		tapOpen(w, c)
		local a, b = sector(c, "wave"), sector(c, "point")
		expect(math.abs(a.paintInner - b.paintInner) < 0.001).toBe(true)
		expect(math.abs(a.paintOuter - b.paintOuter) < 0.001).toBe(true)
	end)
	it("closing a submenu retains its content and geometry until the fade finishes", function()
		local w, c = setup({
			distribution = "even",
			items = {
				{ id = "gear", label = "Gear", children = { { id = "tool", label = "Tool" } } },
			},
		})
		tapOpen(w, c)
		c.api.select("gear")
		w.settle(60)
		c.api.close()
		w.tick(1 / 60)
		expect(c.dump().sectors[1].id).toBe("tool")
		expect(c.dump().visible).toBe(true)
		w.settle(120)
		expect(c.dump().visible).toBe(false)
	end)

	it("empty-center Back is a ring target and corner Back occupies the launcher", function()
		local w, c = setup({ center = "empty", distribution = "even" })
		tapOpen(w, c)
		w.settle(40)
		local nav = sector(c, "$navigation")
		expect(nav.angle % 360).toBe(225)
		w.adapter.tap(nav.path)
		expect(c.dump().open).toBe(false)
		local w2, c2 = setup({ center = "empty", distribution = "even", preset = "bottom-left" })
		local d = c2.dump()
		tapOpen(w2, c2)
		for _, p in w2.adapter.paths() do
			if p:match("/Back$") then
				local r = w2.adapter.node(p).rect
				expect(math.abs(r.x + r.w / 2 - d.centerX) < 0.01).toBe(true)
				expect(math.abs(r.y + r.h / 2 - d.centerY) < 0.01).toBe(true)
			end
		end
	end)
	it("direction gestures preserve radial choices and select beyond the painted ring", function()
		local w, c, fired = setup({ gestureSelection = "direction" })
		w.env:set("viewportRect", { x = 0, y = 0, w = 420, h = 200 })
		w.settle(3)
		local d = c.dump()
		w.adapter.pointerDown(launcher(w), d.centerX, d.centerY, "touch")
		w.adapter.pointerMove(d.centerX + 500, d.centerY)
		expect(c.dump().presentation).toBe("radial")
		expect(c.dump().candidate).toBe(":point")
		w.adapter.pointerUp(d.centerX + 500, d.centerY)
		expect(fired[1]).toBe("point")
	end)
	it("retiring surface and glyph share a single fade and preserve paint eligibility", function()
		for _, appearance in { "wedges", "buttons" } do
			local w, c = setup({ appearance = appearance })
			tapOpen(w, c)
			w.settle(60)
			expect(w.core:lastError()).toBe(nil)
			local p = sector(c, "wave").path
			local visual = p:match("^(.-/Visual)/")
			expect(visual ~= nil).toBe(true)
			local strokeBefore = if appearance == "wedges"
				then w.adapter.node(visual .. "/Content/Sector").props.thickness
				else nil
			c.api.close()
			w.tick(1 / 60)
			w.pres.refresh()
			if strokeBefore then
				expect(w.adapter.node(visual .. "/Content/Sector").props.thickness < strokeBefore).toBe(true)
			end
			expect(w.adapter.node(p).props.enabled).toBe(true)
			expect(w.pres.focus.focusOn(p)).toBe(false)
			expect(w.adapter.node(visual).canvasGroupInstance.groupTransparency < 1).toBe(true)
			expect(
				w.adapter.node(visual .. (if appearance == "wedges" then "/Content/Sector" else "/Content/Disc")) ~= nil
			).toBe(true)
		end
	end)

	it("replacement crossfades from the parent while expansion keeps ancestors visible", function()
		local w, c = setup({
			appearance = "buttons",
			distribution = "even",
			items = {
				{
					id = "gear",
					label = "Gear",
					children = {
						{
							id = "tool",
							label = "Tool",
							navigation = "expand",
							children = { { id = "lamp", label = "Lamp" } },
						},
					},
				},
			},
		})
		tapOpen(w, c)
		w.settle(60)
		local old = sector(c, "gear").path:match("^(.-/Visual)/")
		c.api.select("gear")
		w.settle(2)
		local new = sector(c, "tool").path:match("^(.-/Visual)/")
		expect(w.adapter.node(new).canvasGroupInstance.groupTransparency < 1).toBe(true)
		expect(w.adapter.node(old).canvasGroupInstance.groupTransparency < 1).toBe(true)
		w.settle(60)
		expect(w.adapter.node(old)).toBe(nil)
		expect(w.adapter.node(new).canvasGroupInstance.groupTransparency < 0.01).toBe(true)
		c.api.select("tool")
		w.settle(3)
		expect(w.adapter.node(new).canvasGroupInstance.groupTransparency < 0.01).toBe(true)
		c.api.root()
		w.settle(1)
		c.api.select("gear")
		w.settle(90)
		expect(w.core:lastError()).toBe(nil)
		expect(
			w.adapter.node(sector(c, "tool").path:match("^(.-/Visual)/")).canvasGroupInstance.groupTransparency < 0.01
		).toBe(true)
	end)

	it("separate button art and labels have the same center", function()
		local w, c = setup({ appearance = "buttons" })
		tapOpen(w, c)
		w.settle(60)
		for _, s in c.dump().sectors do
			local p = s.path
			local visual = p:match("^(.-/Visual)/")
			local disc
			for _, path in w.adapter.paths() do
				if path:find(visual .. "/", 1, true) and path:match("/Disc$") then
					disc = w.adapter.node(path).rect
				end
			end
			local label = w.adapter.node(p).rect
			expect(math.abs((disc.x + disc.w / 2) - (label.x + label.w / 2)) <= 0.51).toBe(true)
			expect(math.abs((disc.y + disc.h / 2) - (label.y + label.h / 2)) <= 0.51).toBe(true)
		end
	end)

	it("list fallback hugs its rows when the viewport is taller than its contents", function()
		local w, c = setup({
			preset = "donut",
			clearance = 200,
			distribution = "even",
			items = {
				{ id = "inspect", label = "Inspect" },
				{ id = "unpack", label = "Unpack" },
				{ id = "take", label = "Pick up" },
			},
		})
		w.env:set("viewportRect", { x = 0, y = 0, w = 240, h = 700 })
		tapOpen(w, c)
		w.settle(60)
		expect(c.dump().presentation).toBe("list")
		local list, bottom = nil, 0
		for _, p in w.adapter.paths() do
			local r = w.adapter.node(p).rect
			if p:match("/List$") then
				list = r
			end
			if p:find("/List/Items/", 1, true) and p:match("/Item$") then
				bottom = math.max(bottom, r.y + r.h)
			end
		end
		expect(math.abs(list.y + list.h - bottom - 8) < 1).toBe(true)
		c.dispose()
	end)
	it("off-center rings do not cross an integer pivot on their final animation frame", function()
		local w, c = setup({ preset = "donut", anchor = { x = 400, y = 200.25, visible = true }, contentFit = "none" })
		c.api.open()
		local minY, maxY = math.huge, -math.huge
		for _ = 1, 90 do
			w.settle(1)
			local d = c.dump()
			if d.opacity >= 0.999 then
				for _, p in w.adapter.paths() do
					if p:match("/Rings$") then
						local n = w.adapter.node(p)
						local r, scale = n.rect, n.props.transform.scale
						-- Native UDim offsets truncate, including a near-integer animated pivot.
						local pivot = math.floor(n.presentedPosition.y + r.h / 2)
						local y = pivot + (d.windowRect.y + d.centerY - r.y - r.h / 2) * scale
						minY, maxY = math.min(minY, y), math.max(maxY, y)
					end
				end
			end
		end
		expect(maxY - minY < 0.15).toBe(true)
		c.dispose()
	end)

	it("short viewport list reserves separate navigation and preview space", function()
		local w, c = setup()
		w.env:set("viewportRect", { x = 0, y = 0, w = 420, h = 200 })
		tapOpen(w, c)
		expect(c.dump().presentation).toBe("list")
		local list, back, preview
		for _, p in w.adapter.paths() do
			if p:match("/List$") then
				list = w.adapter.node(p).rect
			end
			if p:match("/Back$") then
				back = w.adapter.node(p).rect
			end
			if p:match("/Candidate$") then
				preview = w.adapter.node(p).rect
			end
		end
		expect(list.y >= back.y + back.h).toBe(true)
		expect(list.y + list.h <= preview.y).toBe(true)
	end)
	it("list rows leave space around the complete button and focus outline", function()
		local w, c = setup()
		w.env:set("viewportRect", { x = 0, y = 0, w = 420, h = 200 })
		tapOpen(w, c)
		local rows = {}
		for _, p in w.adapter.paths() do
			if p:find("/List/Items/", 1, true) and p:match("/Item$") then
				table.insert(rows, w.adapter.node(p).rect)
			end
		end
		table.sort(rows, function(a, b)
			return a.y < b.y
		end)
		expect(#rows).toBe(2)
		expect(rows[2].y > rows[1].y + rows[1].h).toBe(true)
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		w.settle(3)
		local scroll = 0
		for _, p in w.adapter.paths() do
			if p:match("/List$") then
				scroll = w.adapter.scrollPositionOf(p).y
			end
		end
		expect(scroll > 0).toBe(true)
	end)
	it("custom image content fits its actual painted rectangle at every direction", function()
		local geometry = require("../src/controls/radial_geometry")
		for _, preferred in { true, false } do
			local items = {}
			for _, slot in { "N", "NE", "E", "SE", "S", "SW", "W", "NW" } do
				table.insert(items, {
					id = slot,
					slot = slot,
					label = if preferred then "I" else "A deliberately long image action label",
					compactLabel = { image = "rbxassetid://85188541706347", prefer = preferred },
				})
			end
			local w, c = setup({ items = items, center = "back" })
			tapOpen(w, c)
			w.settle(60)
			local d = c.dump()
			for _, s in d.sectors do
				local node = w.adapter.node(s.path)
				expect(node.props.compactLabel.image).toBe("rbxassetid://85188541706347")
				local r = node.rect
				for _, x in { r.x, r.x + r.w } do
					for _, y in { r.y, r.y + r.h } do
						local dx, dy = x - d.centerX, y - d.centerY
						local radius = math.sqrt(dx * dx + dy * dy)
						expect(radius >= s.paintInner and radius <= s.paintOuter).toBe(true)
						expect(math.abs(geometry.delta(math.deg(math.atan2(dx, -dy)), s.angle)) <= s.paintSpan / 2).toBe(
							true
						)
					end
				end
			end
			c.dispose()
		end
	end)
	it("content-fitted navigation arcs contain the themed icon square", function()
		local geometry = require("../src/controls/radial_geometry")
		for _, theme in
			{
				require("../examples/themes/pixel_quest"),
				require("../examples/themes/fantasy_ornate"),
			}
		do
			for _, ringWidth in { false, 61.6 } do
				local w, c = setup({ preset = "donut", center = "empty", ringWidth = ringWidth or nil, clearance = 82 })
				local metrics = Facet.themes.resolve(theme.build(Facet.themes), nil, {})
				w.env:set("themeMetrics", metrics)
				tapOpen(w, c)
				w.settle(60)
				local d, s = c.dump(), sector(c, "$navigation")
				local glyph
				for _, p in w.adapter.paths() do
					if p:sub(1, #s.path) == s.path and p:match("/Glyph$") then
						glyph = w.adapter.node(p).rect
					end
				end
				expect(glyph ~= nil).toBe(true)
				local half = math.min(metrics.iconSizes.medium, glyph.w, glyph.h) / 2
				local margin = metrics.space.xs
				local border = metrics.strokes.hairline / 2
				for _, dx in { -half, half } do
					for _, dy in { -half, half } do
						local x, y = glyph.x + glyph.w / 2 - d.centerX + dx, glyph.y + glyph.h / 2 - d.centerY + dy
						local radius = math.sqrt(x * x + y * y)
						expect(radius >= s.paintInner + border + margin and radius <= s.paintOuter - border - margin).toBe(
							true
						)
						local angle = math.abs(geometry.delta(math.deg(math.atan2(x, -y)), s.angle))
						local seamDistance = radius * math.sin(math.rad(s.paintSpan / 2 - angle))
						expect(seamDistance >= margin / 4 + border + margin).toBe(true)
					end
				end
				c.dispose()
			end
		end
	end)
	it("content fit defaults to both axes and preserves gesture targets", function()
		local fired = 0
		local w, c = setup({
			items = {
				{
					id = "wave",
					label = "Wave",
					icon = "flag",
					labelStyle = "icon",
					slot = "N",
					onSelect = function()
						fired += 1
					end,
				},
			},
		})
		tapOpen(w, c)
		local s = sector(c, "wave")
		expect(c.dump().contentFit).toBe("both")
		expect(s.paintSpan < s.span).toBe(true)
		expect(s.paintOuter - s.paintInner < s.outer - s.inner).toBe(true)
		local p = s.path
		w.adapter.pointerDown(p, s.x, s.y, "touch")
		w.adapter.pointerMove(s.x, c.dump().centerY - s.outer + 1)
		w.adapter.pointerUp(s.x, c.dump().centerY - s.outer + 1)
		w.settle(3)
		expect(c.dump().open).toBe(false)
		expect(fired).toBe(1)
	end)
	it("content fit offers independent axes and an unchanged full-ring mode", function()
		for _, mode in { "none", "radial", "angular" } do
			local w, c = setup({ contentFit = mode })
			tapOpen(w, c)
			local s = sector(c, "wave")
			expect(s.paintSpan == s.span).toBe(mode ~= "angular")
			expect(s.paintInner == s.inner and s.paintOuter == s.outer).toBe(mode ~= "radial")
			c.dispose()
		end
	end)
	it("RadialMenu pointer: a tap activates through the presenter (device-true)", function()
		local w, c, fired = setup()
		tapOpen(w, c)
		local s = sector(c, "wave")
		w.adapter.tap(s.path)
		w.settle(3)
		expect(#fired).toBe(1)
		expect(c.dump().open).toBe(false)
	end)
	it("RadialMenu touch: a touch tap/pan drives the control (device-true)", function()
		local w, c, fired = setup()
		local l = c.dump()
		local p = launcher(w)
		w.adapter.pointerDown(p, l.centerX, l.centerY, "touch")
		w.settle(2)
		local s = sector(c, "point")
		w.adapter.pointerMove(s.x, s.y)
		w.adapter.pointerUp(s.x, s.y)
		w.settle(3)
		expect(#fired).toBe(1)
		expect(fired[1]).toBe("point")
	end)
	it("RadialMenu keyboard: focus + Return drives the control", function()
		local w, c, fired = setup()
		w.pres.focus.focusOn(launcher(w))
		w.press("Return")
		w.settle(3)
		w.pres.focus.focusOn(sector(c, "wave").path)
		w.press("Return")
		expect(#fired).toBe(1)
	end)
	it("RadialMenu gamepad: focus + ButtonA drives the control", function()
		local w, c, fired = setup()
		w.pres.focus.focusOn(launcher(w))
		w.press("ButtonA")
		w.settle(3)
		w.pres.focus.focusOn(sector(c, "point").path)
		w.press("ButtonA")
		expect(#fired).toBe(1)
	end)
	it("RadialMenu pointer affordance: drag previews and center return cancels", function()
		local w, c, fired = setup()
		local p = launcher(w)
		local l = c.dump()
		w.adapter.pointerDown(p, l.centerX, l.centerY, "mouse")
		w.settle(2)
		local s = sector(c, "wave")
		w.adapter.pointerMove(s.x, s.y)
		expect(c.dump().candidate).toBe(":wave")
		expect(#fired).toBe(0)
		w.adapter.pointerMove(l.centerX, l.centerY)
		w.adapter.pointerUp(l.centerX, l.centerY)
		expect(#fired).toBe(0)
		expect(c.dump().open).toBe(false)
	end)
	it("RadialMenu touch affordance: launcher tap latches with 44px targets", function()
		local w, c, fired = setup()
		local l = c.dump()
		local p = launcher(w)
		w.adapter.pointerDown(p, l.centerX, l.centerY, "touch")
		w.adapter.pointerUp(l.centerX, l.centerY)
		w.settle(3)
		expect(c.dump().open).toBe(true)
		expect(#fired).toBe(0)
		for _, s in c.dump().sectors do
			expect(s.size >= 44).toBe(true)
		end
	end)
	it("RadialMenu keyboard affordance: Tab traversal and semantic Cancel", function()
		local w, c = setup()
		tapOpen(w, c)
		w.pres.focus.focusOn(sector(c, "wave").path)
		w.press("Tab")
		w.settle(2)
		expect(w.pres.focus.focused:get() ~= nil).toBe(true)
		w.press("ButtonB")
		expect(c.dump().open).toBe(false)
	end)
	it("RadialMenu gamepad affordance: analog preview, neutral and B cancellation", function()
		local w, c, fired = setup()
		tapOpen(w, c)
		w.system.deviceAxis("Thumbstick1", 1, 0)
		w.settle(2)
		expect(c.dump().candidate).toBe(":point")
		w.system.deviceAxis("Thumbstick1", 0, 0)
		expect(#fired).toBe(0)
		w.press("ButtonB")
		expect(c.dump().open).toBe(false)
	end)
	it("RadialMenu hot-switch: in-flight state resolves CARRY or CANCEL on a class flip", function()
		local w, c = setup()
		tapOpen(w, c)
		w.env:set("preferredInput", "Gamepad")
		w.settle(2)
		expect(c.dump().open).toBe(true)
	end)
	it("mixed navigation and all completion policies preserve the logical path", function()
		local w, c = setup({
			distribution = "even",
			navigation = "expand",
			items = {
				{
					id = "equipment",
					label = "Equipment",
					navigation = "replace",
					children = {
						{
							id = "tools",
							label = "Tools",
							navigation = "expand",
							children = {
								{ id = "home", label = "Home", completion = "root", onSelect = function() end },
								{ id = "back", label = "Return", completion = "back", onSelect = function() end },
								{ id = "stay", label = "Stay", completion = "stay", onSelect = function() end },
							},
						},
					},
				},
			},
		})
		tapOpen(w, c)
		c.api.select("equipment")
		w.settle(3)
		c.api.select("tools")
		w.settle(3)
		expect(#c.dump().openPath).toBe(2)
		c.api.select("stay")
		expect(#c.dump().openPath).toBe(2)
		c.api.select("back")
		w.settle(3)
		expect(#c.dump().openPath).toBe(1)
		c.api.select("tools")
		w.settle(3)
		c.api.select("home")
		w.settle(3)
		expect(#c.dump().openPath).toBe(0)
		expect(c.dump().open).toBe(true)
	end)
end)

t.describe("RadialMenu capture, fitting and lifetime", function()
	it("hover previews through the controller without executing", function()
		local w, c, fired = setup()
		tapOpen(w, c)
		local s = sector(c, "point")
		w.adapter.pointerPreview("/S/Ctl", s.x, s.y)
		expect(c.dump().candidate).toBe(":point")
		expect(#fired).toBe(0)
	end)
	it("native Activated before or after release cannot double commit", function()
		for _, order in { "before", "after" } do
			local w, c, fired = setup({ completion = "stay" })
			tapOpen(w, c)
			local s = sector(c, "wave")
			w.adapter.pointerDown(s.path, s.x, s.y, "touch")
			w.adapter.pointerUp(s.x, s.y, order)
			expect(#fired).toBe(1)
		end
	end)
	it("a second touch cannot steal capture and input loss cancels", function()
		local w, c, fired = setup()
		local l = c.dump()
		w.adapter.pointerDown(launcher(w), l.centerX, l.centerY, "touch")
		w.settle(2)
		local s = sector(c, "wave")
		w.adapter.pointerDown(s.path, s.x, s.y, "touch")
		w.adapter.interruptCapture()
		w.adapter.pointerUp(s.x, s.y, "after")
		expect(#fired).toBe(0)
		expect(c.dump().captured).toBe(false)
		expect(c.dump().open).toBe(false)
	end)
	it("eligibility is checked again after a captured drag", function()
		local core = Facet.newCore()
		local enabled = core:signal(true)
		local calls = 0
		local w, c = setup({
			distribution = "even",
			items = {
				{
					id = "go",
					label = "Go",
					enabled = enabled,
					onSelect = function()
						calls += 1
					end,
				},
			},
		})
		local l = c.dump()
		w.adapter.pointerDown(launcher(w), l.centerX, l.centerY, "touch")
		w.settle(2)
		local s = sector(c, "go")
		w.adapter.pointerMove(s.x, s.y)
		enabled:set(false)
		w.adapter.pointerUp(s.x, s.y, "after")
		expect(calls).toBe(0)
	end)
	it("moving focal anchors freeze under capture and disappearing targets dismiss", function()
		local core = Facet.newCore()
		local anchor = core:signal({ x = 400, y = 325 })
		local w, c = setup({ anchor = anchor })
		local l = c.dump()
		w.adapter.pointerDown(launcher(w), l.centerX, l.centerY, "touch")
		w.settle(2)
		anchor:set({ x = 420, y = 325 })
		w.settle(2)
		expect(c.dump().centerX).toBe(l.centerX)
		w.adapter.pointerUp(l.centerX, l.centerY)
		w.settle(60)
		expect(math.abs(c.dump().centerX - 420) < 0.1).toBe(true)
		anchor:set({ x = 420, y = 325, visible = false })
		w.settle(2)
		expect(c.dump().open).toBe(false)
	end)
	it("large text and a small viewport choose the accessible list and retain activation", function()
		local w, c, fired = setup()
		w.env:set("viewportRect", { x = 0, y = 0, w = 320, h = 300 })
		w.env:set("preferredTextOffset", 12)
		w.settle(3)
		tapOpen(w, c)
		expect(c.dump().presentation).toBe("list")
		local s = sector(c, "wave")
		w.adapter.tap(s.path, { source = "pointer", pointerType = "touch" })
		expect(#fired).toBe(1)
	end)
	it("all corners keep their buttons inside the offered surface", function()
		for _, preset in { "top-left", "top-right", "bottom-left", "bottom-right" } do
			local w, c = setup({ preset = preset, appearance = "buttons", distribution = "even" })
			tapOpen(w, c)
			w.settle(30)
			expect(c.dump().presentation).toBe("radial")
			for _, s in c.dump().sectors do
				expect(s.x - s.size / 2 >= 0 and s.x + s.size / 2 <= 800).toBe(true)
				expect(s.y - s.size / 2 >= 0 and s.y + s.size / 2 <= 650).toBe(true)
			end
		end
	end)
	it("mixed hierarchy is reached by pointer dispatch and Back restores the parent", function()
		local w, c = setup({
			distribution = "even",
			items = {
				{
					id = "gear",
					label = "Gear",
					navigation = "replace",
					children = {
						{
							id = "tools",
							label = "Tools",
							navigation = "expand",
							children = { { id = "use", label = "Use", completion = "stay" } },
						},
					},
				},
			},
		})
		tapOpen(w, c)
		w.adapter.tap(sector(c, "gear").path)
		w.settle(3)
		w.adapter.tap(sector(c, "tools").path)
		w.settle(3)
		expect(#c.dump().openPath).toBe(2)
		w.press("ButtonB")
		w.settle(4)
		expect(#c.dump().openPath).toBe(1)
		expect(w.pres.focus.focused:get()).toBe(sector(c, "tools").path)
	end)
	it("callback disposal retires input before executing and cannot fire twice", function()
		local calls = 0
		local c
		local w
		w, c = setup({
			distribution = "even",
			items = {
				{
					id = "go",
					label = "Go",
					onSelect = function()
						calls += 1
						c.dispose()
					end,
				},
			},
		})
		tapOpen(w, c)
		local s = sector(c, "go")
		w.adapter.pointerDown(s.path, s.x, s.y, "touch")
		w.adapter.pointerUp(s.x, s.y, "after")
		expect(calls).toBe(1)
		w.adapter.tap(s.path)
		expect(calls).toBe(1)
	end)
	it("interrupted opening preserves opacity and eventually releases every retiring row", function()
		local w, c = setup()
		tapOpen(w, c)
		w.settle(2)
		local before = c.dump().opacity
		c.api.close()
		w.tick()
		c.api.open()
		expect(c.dump().opacity > 0 and before > 0).toBe(true)
		w.settle(40)
		c.api.close()
		w.settle(60)
		expect(c.dump().visible).toBe(false)
		for _, p in w.adapter.paths() do
			expect(p:find("/Items/", 1, true) == nil).toBe(true)
		end
	end)
	it("icon and text content stays usable through native themes and reduced motion", function()
		local w, c = setup({
			distribution = "even",
			items = {
				{ id = "look", label = "Look at the beautiful mountain", icon = "facet:search", labelStyle = "both" },
			},
		})
		w.env:set("reducedMotion", true)
		tapOpen(w, c)
		w.settle(12)
		expect(sector(c, "look").path ~= nil).toBe(true)
		expect(c.dump().lastError).toBe(nil)
	end)
end)

t.describe("Quick actions Showcase fitting", function()
	local scenario = require("../examples/gallery/scenarios/radial_menu")
	for _, size in { { 359, 718 }, { 844, 390 }, { 320, 568 }, { 600, 320 } } do
		for _, offset in { 0, 14 } do
			it(`Quick actions {size[1]}x{size[2]} text +{offset} mounts and opens`, function()
				local w = world.new({
					viewport = { x = 0, y = 0, w = size[1], h = size[2] },
					env = {
						preferredTextOffset = offset,
					},
				})
				local built = scenario.build({ Facet = Facet, core = w.core, env = w.env })
				w.present(built.screen)
				w.settle(3)
				built.steps.open()
				w.settle(30)
				expect(built.report().menu.open).toBe(true)
				built.steps.character()
				w.settle(4)
				built.steps.open()
				w.settle(30)
				expect(built.report().menu.open).toBe(true)
			end)
		end
	end
end)

t.describe("RadialMenu aperture and live data", function()
	it("pass-through cuts both native capture and popup-catcher rectangles around the center", function()
		local w, c = setup({ center = "empty", centerPassThrough = true })
		tapOpen(w, c)
		w.settle(20)
		local d = c.dump()
		local centerX = d.windowRect.x + d.centerX
		local centerY = d.windowRect.y + d.centerY
		local count = 0
		for _, p in w.adapter.paths() do
			if p:match("/Plane$") or p:find("/__popupcatcher__/", 1, true) and p:match("/Hit$") then
				local n = w.adapter.node(p)
				local r = n.rect
				assert(r, "missing aperture rectangle")
				expect(centerX >= r.x and centerX < r.x + r.w and centerY >= r.y and centerY < r.y + r.h).toBe(false)
				count += 1
			end
		end
		expect(count).toBe(8)
	end)
	it("removing an ancestor restores the nearest valid logical page", function()
		local core = Facet.newCore()
		local items = core:signal({ { id = "gear", label = "Gear", children = { { id = "go", label = "Go" } } } })
		local w, c = setup({ distribution = "even", items = items })
		tapOpen(w, c)
		w.adapter.tap(sector(c, "gear").path)
		w.settle(3)
		items:set({ { id = "other", label = "Other" } })
		w.settle(5)
		expect(#c.dump().openPath).toBe(0)
		expect(sector(c, "other").path ~= nil).toBe(true)
	end)
	it("held semantic action selects on release, not on stick neutral", function()
		local w = world.new({
			viewport = { x = 0, y = 0, w = 700, h = 700 },
			capabilities = {
				gamepad = true,
				keyboard = true,
			},
		})
		local ctx = w.system.createContext({ name = "GameQuickActions", priority = 10, sink = false })
		local held = ctx.createAction("QuickActions", "Bool")
		held.bind({ keyCode = "ButtonR2" })
		local calls = 0
		local c = Facet.Controls.RadialMenu(w.core, {
			holdAction = held,
			items = { {
				id = "go",
				label = "Go",
				onSelect = function()
					calls += 1
				end,
			} },
		})
		w.present(Facet.UI.Screen({ id = "S", children = { c.blueprint } }))
		w.settle(2)
		w.system.deviceKey("ButtonR2", true)
		w.settle(3)
		w.system.deviceAxis("Thumbstick1", 0, -1)
		w.settle(2)
		expect(calls).toBe(0)
		w.system.deviceKey("ButtonR2", false)
		w.settle(2)
		expect(calls).toBe(1)
	end)
end)

t.describe("RadialMenu teardown and compact navigation", function()
	it("dismiss during animation returns all core registries to baseline", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1000, h = 800 } })
		local before = w.core:counters()
		local c = Facet.Controls.RadialMenu(w.core, {
			id = "Ctl",
			center = "empty",
			items = {
				{
					id = "gear",
					label = "Gear",
					navigation = "expand",
					children = { { id = "tool", label = "Tool", onSelect = function() end } },
				},
			},
		})
		w.present(Facet.UI.Screen({ id = "S", children = { c.blueprint } }))
		w.settle(2)
		c.api.open()
		w.settle(2)
		c.api.select("gear")
		w.settle(2)
		w.system.deviceAxis("Thumbstick1", 0, -1)
		w.pres.dismiss(w.handle)
		c.dispose()
		c.dispose()
		local after = w.core:counters()
		for key, value in before do
			expect(after[key]).toBe(value)
		end
	end)
	it("rounded navigation keeps its 32px visual and changes its glyph with depth", function()
		local w, c = setup({
			distribution = "even",
			center = "empty",
			preset = "bottom-left",
			items = { { id = "gear", label = "Gear", children = { { id = "tool", label = "Tool" } } } },
		})
		c.api.open()
		w.settle(60)
		local function nav()
			for _, p in w.adapter.paths() do
				if p:match("/Back$") then
					return w.adapter.node(p), p
				end
			end
			error("missing compact navigation")
		end
		local n, p = nav()
		expect(n.rect.w).toBe(32)
		expect(n.rect.h).toBe(32)
		local function glyph(path)
			for _, p2 in w.adapter.paths() do
				if p2:find(path .. "/", 1, true) and p2:find("/NavigationIcon/", 1, true) and p2:match("/Glyph$") then
					return w.adapter.node(p2).props.text
				end
			end
		end
		expect(glyph(p)).toBe("x")
		c.api.select("gear")
		w.settle(4)
		local _, p2 = nav()
		expect(glyph(p2)).toBe("<")
		w.adapter.tap(p2)
		w.settle(4)
		expect(#c.dump().openPath).toBe(0)
	end)
end)

t.describe("Quick actions narrow focal movement", function()
	it("leaving the world item stops prompt updates before scene disposal", function()
		local scenario = require("../examples/gallery/scenarios/radial_menu")
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 650 } })
		local disposed, staleUpdates = false, 0
		local built = scenario.build({
			Facet = Facet,
			core = w.core,
			env = w.env,
			worldActions = function()
				return {
					anchor = w.core:signal({ x = 400, y = 350, clearance = 60 }),
					place = function() end,
					setOpen = function()
						if disposed then
							staleUpdates += 1
						end
					end,
					dispose = function()
						disposed = true
					end,
					dump = function()
						return {}
					end,
				}
			end,
		})
		w.present(built.screen)
		w.settle(3)
		built.steps.world()
		w.settle(3)
		built.steps.corner()
		w.settle(10)
		expect(disposed).toBe(true)
		expect(staleUpdates).toBe(0)
	end)
	it("wandering on a narrow phone keeps a fitting ring instead of oscillating into a list", function()
		local scenario = require("../examples/gallery/scenarios/radial_menu")
		local w = world.new({ viewport = { x = 0, y = 0, w = 359, h = 718 } })
		local built = scenario.build({ Facet = Facet, core = w.core, env = w.env })
		w.present(built.screen)
		w.settle(3)
		built.steps.character()
		w.settle(3)
		built.steps.open()
		w.settle(30)
		built.steps.move()
		for _ = 1, 40 do
			w.settle(6)
			expect(built.report().menu.presentation).toBe("radial")
		end
	end)
end)
