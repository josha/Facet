--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	local model = require("../examples/facet_home/model")
	local fs, serde = require("@lune/fs"), require("@lune/serde")
	local document = require("../tools/designer/modules/document")
	local source = require("../tools/designer/modules/source")
	local exporter = require("../tools/designer/modules/export")
	local agent = require("../tools/designer/modules/agent")

	verifyHarness:suite("Facet Home player state", function()
		verifyHarness:case("edits furniture without changing previous layouts", {
			id = "facet_home::Facet Home player state::edits furniture without changing previous layouts",
			run = function()
				local initial = model.empty()
				local placed = model.edit(initial, "place", 1, "sofa", "sage")
				local rotated = model.edit(placed, "rotate", 1)
				local painted = model.edit(rotated, "paint", 1, nil, "clay")
				Verify.expect((model.count(initial))):toBe(0)
				Verify.expect(placed.slots["1"].rotation):toBe(0)
				Verify.expect(painted.slots["1"].rotation):toBe(1)
				Verify.expect(rotated.slots["1"].palette):toBe("sage")
				Verify.expect((model.count(model.edit(painted, "remove", 1)))):toBe(0)
			end,
		})
		verifyHarness:case("rejects unknown furniture, invalid positions, and untrusted layouts", {
			id = "facet_home::Facet Home player state::rejects unknown furniture, invalid positions, and untrusted layouts",
			run = function()
				for _, slot in { 0, 7, 1.5, math.huge, 0 / 0 } do
					Verify.expect((pcall(model.edit, model.empty(), "place", slot, "sofa"))):toBe(false)
				end
				Verify.expect((pcall(model.edit, model.empty(), "place", 1, "untrusted"))):toBe(false)
				Verify.expect((pcall(model.edit, model.empty(), "place", 1, "sofa", "untrusted"))):toBe(false)
				Verify.expect((pcall(model.edit, model.empty(), "rotate", 1))):toBe(false)
				local value = model.edit(model.empty(), "place", 1, "plant")
				value.slots["01"] = value.slots["1"]
				Verify.expect((pcall(model.validate, value))):toBe(false)
			end,
		})
		verifyHarness:case("uses revisions to reject an overwrite from another session", {
			id = "facet_home::Facet Home player state::uses revisions to reject an overwrite from another session",
			run = function()
				local draft = model.edit(model.empty(), "place", 2, "table")
				local saved = model.replace(nil, 0, draft)
				Verify.expect(saved.revision):toBe(1)
				Verify.expect(draft.revision):toBe(0)
				Verify.expect((pcall(model.replace, saved, 0, draft))):toBe(false)
				Verify.expect(model.replace(saved, 1, draft).revision):toBe(2)
			end,
		})
		verifyHarness:case("resets a wrong note and completes the four-note activity", {
			id = "facet_home::Facet Home player state::resets a wrong note and completes the four-note activity",
			run = function()
				local score = 0
				for _, note in { 2, 4, 1, 3 } do
					score = model.puzzleNext(score, note)
				end
				Verify.expect(score):toBe(4)
				local reset, correct = model.puzzleNext(2, 2)
				Verify.expect(reset):toBe(0)
				Verify.expect(correct):toBe(false)
			end,
		})
	end)

	verifyHarness:suite("Facet Home visual source", function()
		for _, name in { "Home", "Furnish", "Activities", "People", "Settings", "Wall" } do
			verifyHarness:case("keeps " .. name .. " editable by humans and agents", {
				id = "facet_home::"
					.. "Facet Home visual source"
					.. "::"
					.. "keeps "
					.. name
					.. " editable by humans and agents",
				run = function()
					local prefix = "examples/facet_home/designs/" .. name
					local code = fs.readFile(prefix .. ".luau")
					local parsed = source.parse(code, name)
					local saved = serde.decode("json", fs.readFile(prefix .. ".design.json"))
					Verify.expect((exporter.component(parsed)))
						:toBe(exporter.component(document.validate(saved.design)))
					local changed, design = agent.patch(
						code,
						{ { op = "set", node = "Heading", property = "text", value = "Agent edit" } },
						name
					)
					Verify.expect(assert(document.find(
						design.root,
						(function()
							for _, row in document.rows(design.root) do
								if row.name == "Heading" then
									return row.id
								end
							end
							error("Missing heading")
						end)()
					)).props.text):toBe("Agent edit")
					Verify.expect((exporter.component(source.parse(changed, name)))):toBe(changed)
				end,
			})
		end
		verifyHarness:case("reuses a visually editable furniture cell with agent edits", {
			id = "facet_home::Facet Home visual source::reuses a visually editable furniture cell with agent edits",
			run = function()
				local code = fs.readFile("examples/facet_home/designs/Furnish.luau")
				local parsed = source.parse(code, "Furnish")
				local saved = serde.decode("json", fs.readFile("examples/facet_home/designs/Furnish.design.json"))
				Verify.expect((exporter.component(parsed))):toBe(exporter.component(document.validate(saved.design)))
				local changed = agent.patch(
					code,
					{ { op = "set", node = "FurnitureCategory", property = "textRole", value = "body" } },
					"Furnish"
				)
				Verify.expect((exporter.component(source.parse(changed, "Furnish")))):toBe(changed)
			end,
		})
		verifyHarness:case("rejects a literal cast that changes the property type", {
			id = "facet_home::Facet Home visual source::rejects a literal cast that changes the property type",
			run = function()
				local code = fs.readFile("examples/facet_home/designs/Home.luau")
				Verify.expect(
					(
						pcall(
							source.parse,
							string.gsub(code, 'textRole = "title" :: "title"', 'textRole = "title" :: "caption"'),
							"Home"
						)
					)
				):toBe(false)
			end,
		})
	end)
end
