--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Compose = require("../src").Compose
local function node(w, path)
	return assert(
		w.adapter.node(path)
			or w.adapter.node((string.gsub(path, "/S/Badge%+background/Badge", "/S/Badge")))
			or w.adapter.node((string.gsub(path, "/Label$", "/LabelContent/then/Label"))),
		path
	)
end
local function mount(w, spec)
	local record
	spec = table.clone(spec)
	spec.ref = function(value)
		record = value
	end
	w.present(function()
		return w.UI.Screen("S")({ w.UI.Badge("Badge")(spec) })
	end)
	return record
end
local ROOT = "/S/Badge+background/Badge"
local PLATE = "/S/Badge+background/Plate"
t.describe("Badge", function()
	t.it("owns a surface-less plate for absent static and bound neutral status", function()
		for _, spec in
			{
				{ label = "New" },
				{ label = "New", status = "neutral" },
				{ label = "New", status = Compose.cell("neutral") },
			}
		do
			local w = world.new()
			local record = mount(w, spec)
			t.expect(node(w, PLATE).props.tint.role).toBe("control")
			t.expect(node(w, ROOT .. "/Label").props.tint.role).toBe("content")
			t.expect(record.dump().semanticText).toBe("New")
			t.expect(#w.handle.focusOrder().traversal).toBe(0)
			for _, value in w.adapter.liveNodes() do
				t.expect(value.props.surface).toBeNil()
			end
			w.close()
		end
	end)
	t.it("retains one semantic icon host through readable paint changes and recovery", function()
		local w = world.new()
		local status = Compose.cell("neutral")
		local record = mount(w, { label = "Ready", icon = "status.success", status = status })
		local height = node(w, ROOT).rect.h
		local icon = node(w, ROOT .. "/Icon")
		for _, entry in
			{
				{ "neutral", "control", "content" },
				{ "warning", "warning", "onWarning" },
				{ "success", "success", "onSuccess" },
				{ "error", "danger", "onDanger" },
				{ "neutral", "control", "content" },
			}
		do
			status:set(entry[1])
			w.pres.refresh()
			t.expect(node(w, PLATE).props.tint.role).toBe(entry[2])
			t.expect(node(w, ROOT .. "/Label").props.tint.role).toBe(entry[3])
			t.expect(node(w, ROOT .. "/Icon").props.tint.role).toBe(entry[3])
			t.expect(node(w, ROOT .. "/Icon")).toBe(icon)
			t.expect(icon.decorationHint.icon).toBe("status.success")
			t.expect(w.adapter.visibleOf(ROOT .. "/Icon")).toBe(true)
			local tags = w.adapter.tagsOf(ROOT .. "/Icon")
			for _, role in { "onSuccess", "onWarning", "onDanger" } do
				t.expect(table.find(tags, "facet-letters-" .. role) ~= nil).toBe(entry[3] == role)
			end
			t.expect(node(w, ROOT).rect.h).toBe(height)
			t.expect(record.dump().status).toBe(entry[1])
		end
		status:set("invalid")
		w.pres.refresh()
		t.expect(record.dump().status).toBe("neutral")
		t.expect(w.adapter.visibleOf(ROOT .. "/Icon")).toBe(true)
		status:set("warning")
		w.pres.refresh()
		t.expect(w.adapter.visibleOf(ROOT .. "/Icon")).toBe(true)
	end)
	t.it("keeps icon badges at the same height as plain captions and respects icon side", function()
		local heights = {}
		for _, side in { "none", "leading", "trailing" } do
			local w = world.new()
			mount(w, {
				label = "Ranked",
				icon = if side == "none" then nil else "status.info",
				iconPosition = if side == "none" then nil else side,
			})
			table.insert(heights, node(w, ROOT).rect.h)
			if side ~= "none" then
				local icon, label = node(w, ROOT .. "/Icon").rect, node(w, ROOT .. "/Label").rect
				t.expect(if side == "leading" then icon.x + icon.w <= label.x else label.x + label.w <= icon.x)
					.toBe(true)
			end
			w.close()
		end
		t.expect(heights[1]).toBe(heights[2])
		t.expect(heights[1]).toBe(heights[3])
	end)
	t.it("uses strong media paint and a plateless utility without claiming an ornament slot", function()
		for _, appearance in { "standard", "status", "utility" } do
			local w = world.new()
			mount(
				w,
				{ label = "Live", appearance = appearance, status = "error", over = "media", icon = "status.error" }
			)
			if appearance == "utility" then
				t.expect(w.adapter.node(PLATE)).toBeNil()
				t.expect(node(w, ROOT .. "/Label").props.tint.role).toBe("contentSecondary")
			else
				t.expect(node(w, PLATE).props.tint.role).toBe("surfaceStrong")
				t.expect(node(w, ROOT .. "/Label").props.tint.role).toBe("contentStrong")
				t.expect(w.adapter.visibleOf(ROOT .. "/Icon")).toBe(true)
			end
			if appearance == "status" then
				t.expect(node(w, ROOT .. "/Mark").rect.w > 0).toBe(true)
			end
			t.expect(#w.handle.focusOrder().traversal).toBe(0)
			w.close()
		end
	end)
	t.it("keeps live words and rung geometry checked through invalid values", function()
		local w = world.new()
		local label, size = Compose.cell("New"), Compose.cell("compact")
		local record = mount(w, { label = label, controlSize = size })
		label:set(42)
		w.pres.refresh()
		t.expect(node(w, ROOT .. "/Label").props.text).toBe("New")
		t.expect(record.dump().label).toBe("New")
		label:set("Ready")
		size:set("large")
		w.pres.refresh()
		t.expect(node(w, ROOT .. "/Label").props.text).toBe("Ready")
		t.expect(node(w, ROOT).rect.h >= 24).toBe(true)
		size:set("invalid")
		w.pres.refresh()
		t.expect(record.dump().controlSize).toBe("large")
		size:set(nil)
		w.pres.refresh()
		t.expect(record.dump().controlSize).toBeNil()
		t.expect(require("../src/paths").nodeAt(w.handle.root.node, ROOT .. "/LabelContent/then/Label").props.disclose)
			.toBe(true)
	end)
	t.it("requires meaningful initial content and an icon-only name", function()
		for _, spec in
			{
				{},
				{ label = "" },
				{ icon = "status.info" },
				{ label = 2 },
				{ label = "New", icon = "rbxassetid://123" },
				{ label = "New", iconPosition = "leading" },
				{ label = "New", icon = "status.info", iconPosition = "above" },
				{ label = "New", appearance = "emphasis" },
				{ label = "New", status = "bad" },
			}
		do
			local w = world.new()
			t.expect(pcall(function()
				mount(w, spec)
			end)).toBe(false)
			t.expect(w.adapter.liveCount()).toBe(0)
		end
		local w = world.new()
		local record = mount(w, { icon = "status.info", name = "Information" })
		t.expect(record.dump().semanticText).toBe("Information")
		t.expect(w.adapter.node(ROOT .. "/Label")).toBeNil()
	end)
end)

t.describe("Badge gallery", function()
	t.it("drives real appearance changes and reports mounted icon geometry", function()
		local w = world.new()
		local built = require("../examples/gallery/scenarios/badge").build({
			Facet = require("../src"),
			UI = w.UI,
			Compose = Compose,
			presenter = w.pres,
		})
		t.expect(built.report()).toBeNil()
		w.present(built.screen)
		t.expect(built.report().icon.w > 0).toBe(true)
		t.expect(built.steps.warning().badge.status).toBe("warning")
		t.expect(built.steps.error().badge.status).toBe("error")
		t.expect(w.adapter.driveActivate("/Badge/Content/BadgeRecipe/Commands/Neutral")).toBe(true)
		w.settle()
		t.expect(built.report().icon.w > 0).toBe(true)
		w.close()
		t.expect(built.report()).toBeNil()
	end)
end)

t.describe("Badge live content presence", function()
	t.it("mounts and removes a checked live caption while retaining the icon and plate", function()
		local w = world.new()
		local label = Compose.cell(nil)
		local record = mount(w, { label = label, icon = "status.info", name = "Information" })
		local plate, icon = node(w, PLATE), node(w, ROOT .. "/Icon")
		local labelPath = ROOT .. "/LabelContent/then/Label"
		t.expect(w.adapter.node(labelPath)).toBeNil()
		for _ = 1, 5 do
			label:set("Ready")
			w.pres.refresh()
			t.expect(node(w, labelPath).props.text).toBe("Ready")
			t.expect(record.dump().label).toBe("Ready")
			for _, empty in { "", false } do
				if empty == false then
					label:set(nil)
				else
					label:set(empty)
				end
				w.pres.refresh()
				t.expect(w.adapter.node(labelPath)).toBeNil()
			end
			t.expect(node(w, PLATE)).toBe(plate)
			t.expect(node(w, ROOT .. "/Icon")).toBe(icon)
		end
	end)
	t.it("quarantines an empty unnamed caption and false status, then recovers", function()
		local w = world.new()
		local label, status = Compose.cell("Ready"), Compose.cell("error")
		local record = mount(w, { label = label, status = status })
		for _, empty in { "", false } do
			if empty == false then
				label:set(nil)
			else
				label:set(empty)
			end
			w.pres.refresh()
			t.expect(record.dump().label).toBe("Ready")
		end
		label:set("New")
		status:set(false)
		w.pres.refresh()
		t.expect(record.dump().status).toBe("error")
		status:set("neutral")
		w.pres.refresh()
		t.expect(record.dump().label).toBe("New")
		t.expect(record.dump().status).toBe("neutral")
	end)
	t.it("rejects supplied empty or non-string names and false appearance", function()
		for _, spec in
			{
				{ label = "Ready", name = "" },
				{ label = "Ready", name = false },
				{ label = "Ready", appearance = false },
			}
		do
			local w = world.new()
			t.expect(pcall(function()
				mount(w, spec)
			end)).toBe(false)
		end
	end)
end)

t.describe("Badge status silhouette", function()
	t.it("separates warning and error marks from their equal-role plate with a page-color cutout", function()
		local themes = require("../src").themes
		local snapshot = require("../src/themes/snapshot")
		for _, package in
			{
				snapshot.neutralPackage(),
				require("../examples/themes/pixel_quest").build(themes),
				(require("../examples/themes/fantasy_ornate").build(themes)),
			}
		do
			for _, status in { "warning", "error" } do
				local w = world.new({ themeMetrics = snapshot.resolve(package) })
				mount(w, { label = "Ready", appearance = "status", status = status })
				local cutout, mark
				for path, value in w.adapter.liveNodes() do
					if string.find(path, ROOT .. "/Mark/", 1, true) and w.adapter.visibleOf(path) then
						if string.sub(path, -7) == "/Cutout" then
							cutout = value
						end
						if string.sub(path, -5) == "/Mark" then
							mark = value
						end
					end
				end
				t.expect(cutout ~= nil).toBe(true)
				t.expect(cutout.props.tint.role).toBe("surface")
				t.expect(mark.props.tint.role).toBe(node(w, PLATE).props.tint.role)
				t.expect(cutout.rect.w > mark.rect.w and cutout.rect.h > mark.rect.h).toBe(true)
				for _, theme in package.style.themes do
					t.expect(theme.colors.surface).never().toEqual(theme.colors[mark.props.tint.role])
				end
				w.close()
			end
		end
	end)
end)

t.describe("Badge placement: a count on a host sits on its corner", function()
	local function corner(direction: string?, value: any)
		local w = world.new()
		w.present(function()
			local UI = w.UI
			return UI.Screen("S")({
				UI.badged(
					UI.Button("Inbox")({
						label = "Inbox",
						width = { type = "fixed", px = 120 },
						height = { type = "fixed", px = 44 },
					}),
					value,
					direction
				),
			})
		end)
		w.settle(3)
		return w
	end
	t.it("centres the seal on the top-right corner, paint only: the host's box and target are unchanged", function()
		local w = corner(nil, 120)
		local host = w.adapter.node("/S/Inbox+badge/Inbox").rect
		local wrapper = w.adapter.node("/S/Inbox+badge").rect
		t.expect(`{wrapper.w}x{wrapper.h}`).toBe(`{host.w}x{host.h}`)
		local seal = w.adapter.node("/S/Inbox+badge/CornerBadge")
		local offset = seal.props.transform or { x = 0, y = 0 }
		local cx, cy = seal.rect.x + offset.x + seal.rect.w / 2, seal.rect.y + offset.y + seal.rect.h / 2
		t.expect(`{math.abs(cx - (host.x + host.w)) < 0.51} {math.abs(cy - host.y) < 0.51}`).toBe("true true")
		t.expect(w.adapter.node("/S/Inbox+badge/CornerBadge/Count").props.text).toBe("99+")
		-- the seal takes no focus and no tap
		t.expect(#w.handle.focusOrder().traversal).toBe(1)
	end)
	t.it("mirrors to the top-left in rtl, and `true` is a dot with no number", function()
		local w = corner("rtl", true)
		local host = w.adapter.node("/S/Inbox+badge/Inbox").rect
		local seal = w.adapter.node("/S/Inbox+badge/CornerBadge")
		local offset = seal.props.transform or { x = 0, y = 0 }
		local cx = seal.rect.x + offset.x + seal.rect.w / 2
		t.expect(math.abs(cx - host.x) < 0.51).toBe(true)
		t.expect(w.adapter.node("/S/Inbox+badge/CornerBadge/Count").props.text).toBe("")
		t.expect(seal.props.hidden == true).toBe(false)
	end)
	t.it("a tab icon wears its count on the icon's corner; a text tab keeps the trailing pill", function()
		local w = world.new()
		w.present(function()
			local UI = w.UI
			return UI.Screen("S")({
				UI.Picker({
					id = "Tabs",
					style = "segmented",
					selected = Compose.cell("a"),
					options = {
						{ value = "a", label = "Inbox", icon = "menu", badge = 3 },
						{ value = "b", label = "Sent", icon = "flag" },
					},
				}),
				UI.Picker({
					id = "Words",
					style = "segmented",
					selected = Compose.cell("a"),
					options = { { value = "a", label = "Inbox", badge = 3 }, { value = "b", label = "Sent" } },
				}),
			})
		end)
		w.settle(3)
		local found = { corner = false, pill = false }
		for _, path in w.adapter.paths() do
			found.corner = found.corner or string.find(path, "/Icon%+badge/CornerBadge$") ~= nil
			found.pill = found.pill or string.find(path, "/Words/.-Opt1/.-/Badge$") ~= nil
		end
		t.expect(`corner {found.corner} pill {found.pill}`).toBe("corner true pill true")
	end)
end)
