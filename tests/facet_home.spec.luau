--!strict

local t = require("./lib/testkit")
local model = require("../examples/facet_home/model")
local fs, serde = require("@lune/fs"), require("@lune/serde")
local document = require("../tools/designer/modules/document")
local source = require("../tools/designer/modules/source")
local exporter = require("../tools/designer/modules/export")
local agent = require("../tools/designer/modules/agent")

t.describe("Facet Home player state", function()
	t.it("edits furniture without changing previous layouts", function()
		local initial = model.empty()
		local placed = model.edit(initial, "place", 1, "sofa", "sage")
		local rotated = model.edit(placed, "rotate", 1)
		local painted = model.edit(rotated, "paint", 1, nil, "clay")
		t.expect(model.count(initial)).toBe(0)
		t.expect(placed.slots["1"].rotation).toBe(0)
		t.expect(painted.slots["1"].rotation).toBe(1)
		t.expect(rotated.slots["1"].palette).toBe("sage")
		t.expect(model.count(model.edit(painted, "remove", 1))).toBe(0)
	end)
	t.it("rejects unknown furniture, invalid positions, and untrusted layouts", function()
		for _, slot in { 0, 7, 1.5, math.huge, 0 / 0 } do
			t.expect(pcall(model.edit, model.empty(), "place", slot, "sofa")).toBe(false)
		end
		t.expect(pcall(model.edit, model.empty(), "place", 1, "untrusted")).toBe(false)
		t.expect(pcall(model.edit, model.empty(), "place", 1, "sofa", "untrusted")).toBe(false)
		t.expect(pcall(model.edit, model.empty(), "rotate", 1)).toBe(false)
		local value = model.edit(model.empty(), "place", 1, "plant")
		value.slots["01"] = value.slots["1"]
		t.expect(pcall(model.validate, value)).toBe(false)
	end)
	t.it("uses revisions to reject an overwrite from another session", function()
		local draft = model.edit(model.empty(), "place", 2, "table")
		local saved = model.replace(nil, 0, draft)
		t.expect(saved.revision).toBe(1)
		t.expect(draft.revision).toBe(0)
		t.expect(pcall(model.replace, saved, 0, draft)).toBe(false)
		t.expect(model.replace(saved, 1, draft).revision).toBe(2)
	end)
	t.it("resets a wrong note and completes the four-note activity", function()
		local score = 0
		for _, note in { 2, 4, 1, 3 } do
			score = model.puzzleNext(score, note)
		end
		t.expect(score).toBe(4)
		local reset, correct = model.puzzleNext(2, 2)
		t.expect(reset).toBe(0)
		t.expect(correct).toBe(false)
	end)
end)

t.describe("Facet Home visual source", function()
	for _, name in { "Home", "Furnish", "Activities", "People", "Settings", "Wall" } do
		t.it("keeps " .. name .. " editable by humans and agents", function()
			local prefix = "examples/facet_home/designs/" .. name
			local code = fs.readFile(prefix .. ".luau")
			local parsed = source.parse(code, name)
			local saved = serde.decode("json", fs.readFile(prefix .. ".design.json"))
			t.expect(exporter.component(parsed)).toBe(exporter.component(document.validate(saved.design)))
			local changed, design =
				agent.patch(code, { { op = "set", node = "Heading", property = "text", value = "Agent edit" } }, name)
			t.expect(assert(document.find(
				design.root,
				(function()
					for _, row in document.rows(design.root) do
						if row.name == "Heading" then
							return row.id
						end
					end
					error("Missing heading")
				end)()
			)).props.text).toBe("Agent edit")
			t.expect(exporter.component(source.parse(changed, name))).toBe(changed)
		end)
	end
	t.it("reuses a visually editable furniture cell with agent edits", function()
		local code = fs.readFile("examples/facet_home/designs/Furnish.luau")
		local parsed = source.parse(code, "Furnish")
		local saved = serde.decode("json", fs.readFile("examples/facet_home/designs/Furnish.design.json"))
		t.expect(exporter.component(parsed)).toBe(exporter.component(document.validate(saved.design)))
		local changed = agent.patch(
			code,
			{ { op = "set", node = "FurnitureCategory", property = "textRole", value = "body" } },
			"Furnish"
		)
		t.expect(exporter.component(source.parse(changed, "Furnish"))).toBe(changed)
	end)
	t.it("rejects a literal cast that changes the property type", function()
		local code = fs.readFile("examples/facet_home/designs/Home.luau")
		t.expect(
			pcall(
				source.parse,
				string.gsub(code, 'textRole = "title" :: "title"', 'textRole = "title" :: "caption"'),
				"Home"
			)
		).toBe(false)
	end)
end)
