--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Compose = require("../src").Compose
local function node(w, path)
	return assert(
		w.adapter.node(path) or w.adapter.node((string.gsub(path, "/S/Badge%+background/Badge", "/S/Badge"))),
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
	t.it("switches actual icon visibility both ways with the readable paint pair", function()
		local w = world.new()
		local status = Compose.cell("neutral")
		local record = mount(w, { label = "Ready", icon = "status.success", status = status })
		local height = node(w, ROOT).rect.h
		for _, entry in
			{
				{ "neutral", "control", "content", true },
				{ "warning", "content", "surface", false },
				{ "error", "danger", "onDanger", false },
				{ "neutral", "control", "content", true },
			}
		do
			status:set(entry[1])
			w.pres.refresh()
			t.expect(node(w, PLATE).props.tint.role).toBe(entry[2])
			t.expect(node(w, ROOT .. "/Label").props.tint.role).toBe(entry[3])
			t.expect(node(w, ROOT .. "/Icon/Glyph").props.tint.role).toBe(entry[3])
			t.expect(w.adapter.visibleOf(ROOT .. "/Icon/Art")).toBe(entry[4])
			t.expect(w.adapter.visibleOf(ROOT .. "/Icon/Glyph")).toBe(not entry[4])
			t.expect(node(w, ROOT).rect.h).toBe(height)
			t.expect(record.dump().status).toBe(entry[1])
		end
		status:set("invalid")
		w.pres.refresh()
		t.expect(record.dump().status).toBe("neutral")
		t.expect(w.adapter.visibleOf(ROOT .. "/Icon/Art")).toBe(true)
		status:set("warning")
		w.pres.refresh()
		t.expect(w.adapter.visibleOf(ROOT .. "/Icon/Glyph")).toBe(true)
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
				t.expect(w.adapter.visibleOf(ROOT .. "/Icon/Glyph")).toBe(true)
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
		t.expect(require("../src/paths").nodeAt(w.handle.root.node, ROOT .. "/Label").props.disclose).toBe(true)
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
	t.it("drives real appearance changes and reports actual visibility only while mounted", function()
		local w = world.new()
		local built = require("../examples/gallery/scenarios/badge").build({
			Facet = require("../src"),
			UI = w.UI,
			Compose = Compose,
			presenter = w.pres,
		})
		t.expect(built.report()).toBeNil()
		w.present(built.screen)
		t.expect(built.report().artVisible).toBe(true)
		t.expect(built.steps.warning().glyphVisible).toBe(true)
		t.expect(built.steps.error().badge.status).toBe("error")
		t.expect(w.adapter.driveActivate("/Badge/Content/BadgeRecipe/Commands/Neutral")).toBe(true)
		w.settle()
		t.expect(built.report().artVisible).toBe(true)
		t.expect(built.report().glyphVisible).toBe(false)
		w.close()
		t.expect(built.report()).toBeNil()
	end)
end)
