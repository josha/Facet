--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Compose = require("../src").Compose
local snapshot = require("../src/themes/snapshot")
local function node(w, path)
	return assert(w.adapter.node(path), path)
end
local function part(w, name)
	for path, value in w.adapter.liveNodes() do
		if
			string.sub(path, 1, 8) == "/S/Mark/"
			and string.sub(path, -#name - 1) == "/" .. name
			and w.adapter.visibleOf(path)
		then
			return value
		end
	end
	error("missing status part " .. name)
end
local function mount(w, spec)
	local record
	spec = table.clone(spec)
	spec.ref = function(value)
		record = value
	end
	w.present(function()
		return w.UI.Screen("S")({ w.UI.StatusIndicator("Mark")(spec) })
	end)
	return record
end
t.describe("StatusIndicator", function()
	t.it("paints a compact surface-less dot with readable semantics and no focus stop", function()
		local w = world.new()
		local record = mount(w, { name = "Connected" })
		t.expect(node(w, "/S/Mark").rect.w).toBe(16)
		t.expect(node(w, "/S/Mark").rect.h).toBe(16)
		t.expect(part(w, "Mark").props.shape).toBe("circle")
		t.expect(part(w, "Mark").props.tint.role).toBe("contentSecondary")
		t.expect(record.dump().semanticText).toBe("Connected")
		t.expect(record.api.semanticText:peek()).toBe("Connected")
		t.expect(#w.handle.focusOrder().traversal).toBe(0)
		for _, value in w.adapter.liveNodes() do
			t.expect(value.props.surface).toBeNil()
		end
	end)
	t.it("distinguishes all four shapes at 10 13 and 16 pixels independently of pill radius", function()
		local metrics = table.clone(snapshot.neutral())
		metrics.radii = table.clone(metrics.radii)
		metrics.radii.pill = 1
		for _, size in { 10, 13, 16 } do
			for _, form in { "dot", "ring", "square", "dash" } do
				local w = world.new({ themeMetrics = metrics })
				mount(w, { form = form, width = { type = "fixed", px = size }, height = { type = "fixed", px = size } })
				local mark, detail = part(w, "Mark"), part(w, "Detail")
				t.expect(mark.rect.w).toBe(size)
				t.expect(mark.rect.h).toBe(size)
				t.expect(mark.props.shape).toBe(if form == "square" then "rect" else "circle")
				if form == "ring" or form == "dash" then
					t.expect(detail.rect.w > 0 and detail.rect.h > 0).toBe(true)
					t.expect(detail.props.shape).toBe(if form == "ring" then "circle" else "rect")
					t.expect(detail.rect.x >= mark.rect.x and detail.rect.y >= mark.rect.y).toBe(true)
					t.expect(detail.rect.x + detail.rect.w <= mark.rect.x + mark.rect.w).toBe(true)
					if form == "dash" then
						t.expect(detail.rect.w > detail.rect.h).toBe(true)
					end
				else
					t.expect(detail.rect.w).toBe(0)
					t.expect(detail.rect.h).toBe(0)
				end
				w.close()
			end
		end
	end)
	t.it("uses shared palette pairs for every status and caps the actual mounted count", function()
		local expected = {
			neutral = { "contentSecondary", "surface" },
			info = { "accent", "onAccent" },
			success = { "success", "onSuccess" },
			warning = { "warning", "onWarning" },
			error = { "danger", "onDanger" },
			accent = { "accent", "onAccent" },
		}
		for status, pair in expected do
			local w = world.new()
			local count = Compose.cell(0)
			local record = mount(w, { status = status, count = count })
			t.expect(part(w, "Plate").props.tint.role).toBe(pair[1])
			t.expect(part(w, "Count").props.tint.role).toBe(pair[2])
			local cappedWidth
			for _, n in { 0, 9, 99, 100, 1000 } do
				count:set(n)
				w.pres.refresh()
				local text = if n > 99 then "99+" else tostring(n)
				t.expect(part(w, "Count").props.text).toBe(text)
				t.expect(record.dump().semanticText).toBe(status .. ", " .. text)
				if n == 100 then
					cappedWidth = node(w, "/S/Mark").rect.w
				end
				if n == 1000 then
					t.expect(node(w, "/S/Mark").rect.w).toBe(cappedWidth)
				end
			end
			w.close()
		end
	end)
	t.it("spends the cutout within the reserved footprint", function()
		local w = world.new()
		mount(
			w,
			{ form = "ring", width = { type = "fixed", px = 16 }, height = { type = "fixed", px = 16 }, cutout = true }
		)
		local root, cutout, mark = node(w, "/S/Mark"), part(w, "Cutout"), part(w, "Mark")
		t.expect(root.rect.w).toBe(16)
		t.expect(cutout.rect).toEqual(root.rect)
		t.expect(cutout.props.tint.role).toBe("surface")
		t.expect(mark.rect.w).toBe(14)
		t.expect(mark.rect.x).toBe(root.rect.x + 1)
		t.expect(mark.rect.y).toBe(root.rect.y + 1)
	end)
	t.it("retains one validated paint and semantic answer across invalid updates and recovery", function()
		local w = world.new()
		local form, status = Compose.cell("ring"), Compose.cell("neutral")
		local record = mount(w, { form = form, status = status })
		form:set("invalid")
		w.pres.refresh()
		t.expect(record.dump().form).toBe("ring")
		t.expect(part(w, "Detail").props.shape).toBe("circle")
		t.expect(form:peek()).toBe("invalid")
		form:set("square")
		status:set("error")
		w.pres.refresh()
		t.expect(record.dump().form).toBe("square")
		t.expect(part(w, "Mark").props.shape).toBe("rect")
		t.expect(part(w, "Mark").props.tint.role).toBe("danger")
		status:set("invalid")
		w.pres.refresh()
		t.expect(record.dump().status).toBe("error")
		t.expect(record.api.semanticText:peek()).toBe("error")
		status:set(nil)
		form:set(nil)
		w.pres.refresh()
		t.expect(record.dump().status).toBe("neutral")
		t.expect(part(w, "Mark").props.shape).toBe("circle")
	end)
	t.it("rejects a late hole or invalid count without losing the last valid seal", function()
		local w = world.new()
		local form, count = Compose.cell("dot"), Compose.cell(7)
		local record = mount(w, { form = form, count = count, max = 9 })
		for _, invalid in { -1, 1.5, math.huge, 0 / 0 } do
			count:set(invalid)
			w.pres.refresh()
			t.expect(part(w, "Count").props.text).toBe("7")
			count:set(7)
			w.pres.refresh()
		end
		form:set("ring")
		w.pres.refresh()
		t.expect(record.dump().form).toBe("dot")
		form:set("square")
		count:set(12)
		w.pres.refresh()
		t.expect(record.dump().form).toBe("square")
		t.expect(part(w, "Count").props.text).toBe("9+")
	end)
	t.it("resolves checked rung metrics and recovers to the compact default", function()
		local w = world.new()
		local size = Compose.cell("compact")
		local record = mount(w, { controlSize = size })
		size:set("invalid")
		w.pres.refresh()
		t.expect(node(w, "/S/Mark").rect.w).toBe(16)
		size:set("large")
		w.pres.refresh()
		t.expect(node(w, "/S/Mark").rect.w).toBe(24)
		t.expect(record.dump().controlSize).toBe("large")
		size:set(nil)
		w.pres.refresh()
		t.expect(node(w, "/S/Mark").rect.w).toBe(16)
		local metrics = table.clone(snapshot.neutral())
		metrics.controlSizes = table.clone(metrics.controlSizes)
		metrics.controlSizes.compact = table.clone(metrics.controlSizes.compact)
		metrics.controlSizes.compact.iconSize = 19
		w.env:set("themeMetrics", metrics)
		w.pres.refresh()
		t.expect(node(w, "/S/Mark").rect.w).toBe(19)
	end)
	t.it("refuses invalid construction before mounting", function()
		for _, spec in
			{
				{ form = "triangle" },
				{ status = "bad" },
				{ count = -1 },
				{ count = math.huge },
				{ count = 0 / 0 },
				{ count = 1.5 },
				{ count = Compose.cell(nil) },
				{ max = 4 },
				{ count = 1, max = 0 },
				{ count = 1, max = math.huge },
				{ count = 1, form = "ring" },
				{ count = 1, form = "dash" },
				{ name = "" },
				{ cutout = "yes" },
				{ controlSize = "tiny" },
			}
		do
			local w = world.new()
			local ok, err = pcall(function()
				mount(w, spec)
			end)
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(err), "StatusIndicator", 1, true) ~= nil).toBe(true)
			t.expect(w.adapter.liveCount()).toBe(0)
		end
	end)
end)

t.describe("StatusIndicator gallery", function()
	t.it("drives actual count text and shape choices with no stale report after close", function()
		local w = world.new()
		local built = require("../examples/gallery/scenarios/status_indicator").build({
			Facet = require("../src"),
			UI = w.UI,
			Compose = Compose,
			presenter = w.pres,
		})
		t.expect(built.report()).toBeNil()
		w.present(built.screen)
		t.expect(built.report().rect.w > 0).toBe(true)
		t.expect(built.steps.capped().count.count).toBe("99+")
		t.expect(built.steps.ring().form).toBe("ring")
		t.expect(w.adapter.driveActivate("/StatusIndicator/Content/StatusRecipe/Commands/Reset")).toBe(true)
		w.settle()
		t.expect(built.report().count.count).toBe("0")
		w.close()
		t.expect(built.report()).toBeNil()
	end)
end)

t.describe("StatusIndicator authored footprints", function()
	t.it("spends an authored count height once and keeps cutout content inside its inset", function()
		for _, cutout in { false, true } do
			for _, height in { { type = "percent", fraction = 0.5 }, { type = "fixed", px = 20 } } do
				local w = world.new()
				w.present(function()
					return w.UI.Screen("S")({
						width = { type = "fixed", px = 100 },
						height = { type = "fixed", px = 100 },
						w.UI.StatusIndicator("Mark")({
							count = 7,
							width = { type = "fixed", px = 40 },
							height = height,
							cutout = cutout,
						}),
					})
				end)
				local root, plate, count = node(w, "/S/Mark").rect, part(w, "Plate").rect, part(w, "Count").rect
				t.expect(root.h).toBe(if height.type == "percent" then 50 else 20)
				t.expect(plate.h).toBe(root.h - (if cutout then 2 else 0))
				t.expect(plate.y).toBe(root.y + (if cutout then 1 else 0))
				t.expect(count.y >= plate.y and count.y + count.h <= plate.y + plate.h).toBe(true)
				w.close()
			end
		end
	end)
	t.it("centers ring and dash details in the actual circle within a nonsquare reservation", function()
		for _, form in { "ring", "dash", "square" } do
			local w = world.new()
			mount(w, { form = form, width = { type = "fixed", px = 10 } })
			local root, mark, detail = node(w, "/S/Mark").rect, part(w, "Mark").rect, part(w, "Detail").rect
			t.expect(root.w).toBe(10)
			t.expect(root.h).toBe(16)
			t.expect(mark.h).toBe(if form == "square" then 16 else 10)
			if form ~= "square" then
				t.expect(math.abs(detail.y + detail.h / 2 - mark.y - mark.h / 2) <= 0.5).toBe(true)
				t.expect(detail.y > mark.y and detail.y + detail.h < mark.y + mark.h).toBe(true)
			end
			w.close()
		end
	end)
	t.it("refuses false form and status instead of publishing defaults", function()
		local w = world.new()
		local form, status = Compose.cell("ring"), Compose.cell("error")
		local record = mount(w, { form = form, status = status })
		form:set(false)
		w.pres.refresh()
		t.expect(record.dump().form).toBe("ring")
		t.expect(part(w, "Detail").props.shape).toBe("circle")
		form:set("square")
		status:set(false)
		w.pres.refresh()
		t.expect(record.dump().status).toBe("error")
		t.expect(part(w, "Mark").props.tint.role).toBe("danger")
		status:set(nil)
		w.pres.refresh()
		t.expect(record.dump().status).toBe("neutral")
	end)
end)

t.describe("StatusIndicator round containment", function()
	t.it("selects a contained visible square from either axis with cutout and fractional offers", function()
		for _, cutout in { false, true } do
			for _, axes in
				{
					{ 10, 16 },
					{ 16, 10 },
					{ false, 10 },
					{ 16.49, 10.49 },
					{ 16.5, 10.5 },
					{ 16.99, 10.99 },
					{ 10.49, 16.49 },
					{ 10.5, 16.5 },
					{ 10.99, 16.99 },
					{ 10.49, 10.99 },
					{ 10.99, 10.49 },
				}
			do
				local metrics = table.clone(snapshot.neutral())
				metrics.strokes = table.clone(metrics.strokes)
				metrics.strokes.hairline = 2
				local w = world.new({ themeMetrics = metrics })
				mount(w, {
					form = "ring",
					width = if axes[1] then { type = "fixed", px = axes[1] } else nil,
					height = { type = "fixed", px = axes[2] },
					cutout = cutout,
				})
				local root = node(w, "/S/Mark").rect
				local visible, mounted = {}, 0
				for path, value in w.adapter.liveNodes() do
					if path ~= "/S/Mark" and string.sub(path, -5) == "/Mark" then
						mounted += 1
						if w.adapter.visibleOf(path) then
							table.insert(visible, value)
						end
					end
				end
				t.expect(#visible).toBe(1)
				local mark = visible[1].rect
				t.expect(mark.w).toBe(
					math.floor(math.min(root.w, root.h))
						- (
							if cutout
								then 2 * math.min(2, math.floor(math.floor(math.min(root.w, root.h)) * 0.1 + 0.5))
								else 0
						)
				)
				t.expect(mark.w).toBe(mark.h)
				t.expect(
					mark.x >= root.x
						and mark.y >= root.y
						and mark.x + mark.w <= root.x + root.w
						and mark.y + mark.h <= root.y + root.h
				).toBe(true)
				for path, value in w.adapter.liveNodes() do
					if
						(string.sub(path, -7) == "/Cutout" or string.sub(path, -7) == "/Detail")
						and w.adapter.visibleOf(path)
					then
						local r = value.rect
						t.expect(
							r.x >= root.x
								and r.y >= root.y
								and r.x + r.w <= root.x + root.w
								and r.y + r.h <= root.y + root.h
						).toBe(true)
					end
				end
				t.expect(mounted).toBe(2) -- existing fit ladder owns one constant passive alternative
				w.close()
			end
		end
	end)
	t.it("keeps fractional theme insets inside the selected circular cutout", function()
		local metrics = table.clone(snapshot.neutral())
		metrics.strokes = table.clone(metrics.strokes)
		metrics.strokes.hairline = 1.25
		local w = world.new({ themeMetrics = metrics })
		w.present(function()
			return w.UI.Screen("S")({
				padding = { left = 0.49, top = 0.99 },
				w.UI.StatusIndicator("Mark")({
					form = "ring",
					width = { type = "fixed", px = 16.5 },
					height = { type = "fixed", px = 26.5 },
					cutout = true,
				}),
			})
		end)
		local root, cutout, mark, detail =
			node(w, "/S/Mark").rect, part(w, "Cutout").rect, part(w, "Mark").rect, part(w, "Detail").rect
		t.expect(root.x).toBe(0.49)
		t.expect(root.y).toBe(0.99)
		t.expect(cutout.w).toBe(16)
		t.expect(cutout.h).toBe(16)
		t.expect(mark.w).toBe(13)
		t.expect(mark.h).toBe(13)
		t.expect(
			detail.x >= mark.x
				and detail.y >= mark.y
				and detail.x + detail.w <= mark.x + mark.w
				and detail.y + detail.h <= mark.y + mark.h
		).toBe(true)
		for _, rect in { cutout, mark, detail } do
			t.expect(
				rect.x >= root.x
					and rect.y >= root.y
					and rect.x + rect.w <= root.x + root.w
					and rect.y + rect.h <= root.y + root.h
			).toBe(true)
		end
	end)
	t.it("retains a legal subpixel reservation with zero quantized paint", function()
		local w = world.new()
		mount(w, { form = "ring", width = { type = "fixed", px = 0.99 }, height = { type = "fixed", px = 0.49 } })
		local root, mark = node(w, "/S/Mark").rect, part(w, "Mark").rect
		t.expect(root.w).toBe(0.99)
		t.expect(root.h).toBe(0.49)
		t.expect(mark.w).toBe(0)
		t.expect(mark.h).toBe(0)
		t.expect(mark.x >= root.x and mark.y >= root.y and mark.x <= root.x + root.w and mark.y <= root.y + root.h)
			.toBe(true)
	end)
	t.it("reselects the fitted axis when a relative parent offer changes", function()
		local w = world.new()
		local width, height = Compose.cell({ type = "fixed", px = 200 }), Compose.cell({ type = "fixed", px = 100 })
		w.present(function()
			return w.UI.Screen("S")({
				width = width,
				height = height,
				w.UI.StatusIndicator("Mark")({
					form = "dash",
					width = { type = "percent", fraction = 0.5 },
					height = { type = "percent", fraction = 0.5 },
				}),
			})
		end)
		for _, dimensions in { { 200, 100 }, { 60, 200 }, { 200, 100 } } do
			width:set({ type = "fixed", px = dimensions[1] })
			height:set({ type = "fixed", px = dimensions[2] })
			w.pres.refresh()
			local root, actual = node(w, "/S/Mark").rect, nil
			for path, value in w.adapter.liveNodes() do
				if path ~= "/S/Mark" and string.sub(path, -5) == "/Mark" and w.adapter.visibleOf(path) then
					actual = value.rect
				end
			end
			t.expect(actual.w).toBe(math.min(root.w, root.h))
			t.expect(actual.h).toBe(actual.w)
			t.expect(
				actual.x >= root.x
					and actual.y >= root.y
					and actual.x + actual.w <= root.x + root.w
					and actual.y + actual.h <= root.y + root.h
			).toBe(true)
		end
	end)
end)

t.describe("StatusIndicator small cutout", function()
	t.it("caps small Pixel gutters but restores its full hairline on large marks", function()
		local metrics = require("../src/themes/snapshot").resolve(
			require("../examples/themes/pixel_quest").build(require("../src").themes),
			nil,
			{}
		)
		for _, size in { 8, 10, 11, 13, 16, 40 } do
			for _, form in { "dot", "ring", "square", "dash" } do
				local w = world.new({ themeMetrics = metrics })
				mount(w, {
					form = form,
					width = { type = "fixed", px = size },
					height = { type = "fixed", px = size },
					cutout = true,
				})
				local mark, detail, cutout = part(w, "Mark").rect, part(w, "Detail").rect, part(w, "Cutout").rect
				local gutter = math.min(4, math.floor(size * 0.1 + 0.5))
				t.expect(mark.w).toBe(size - 2 * gutter)
				t.expect(mark.h).toBe(size - 2 * gutter)
				t.expect(mark.x - cutout.x).toBe(gutter)
				t.expect(mark.y - cutout.y).toBe(gutter)
				if form == "ring" or form == "dash" then
					t.expect(detail.w > 0 and detail.h > 0 and detail.w < mark.w and detail.h < mark.h).toBe(true)
					t.expect(
						detail.x >= mark.x
							and detail.y >= mark.y
							and detail.x + detail.w <= mark.x + mark.w
							and detail.y + detail.h <= mark.y + mark.h
					).toBe(true)
				end
				w.close()
			end
		end
	end)
end)
