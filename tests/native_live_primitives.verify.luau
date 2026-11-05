--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Contracts = require("./lib/live_contracts")
local Double = require("./lib/live_double")
local Exclusions = require("./lib/live_exclusions")
local Lute = require("../tools/vendor/verify/src/lute")

local excluded: { [string]: string } = {}
for reason, names in Exclusions do
	for _, name in names do
		excluded[name] = reason
	end
end
local ownSpec: { [string]: boolean } = {
	["primitives/screen-padding-and-gap"] = true,
	["primitives/grid-cells-and-gaps"] = true,
	["primitives/zstack-alignment"] = true,
	["primitives/stack-distribution"] = true,
	["primitives/fill-and-extents"] = true,
	["primitives/scroll-view-capped-natural-height"] = true,
}

return function(harness: Verify.Harness)
	harness:case("the live host uses native selection assignment rules", function(check)
		local path = "tools/studio/live/suites/primitives.luau"
		local source = string.gsub(
			Lute.fixture.host.readFile(path),
			't.check%("this build has the layout constructors", present%)',
			[[
local screen = Instance.new("ScreenGui")
screen.Parent = game.Players.LocalPlayer.PlayerGui
local target = Instance.new("Frame")
target.Visible, target.Selectable, target.Parent = false, false, screen
game.GuiService.SelectedObject = target
t.check("native assignment accepts a hidden unselectable descendant", game.GuiService.SelectedObject == target)
game.GuiService.SelectedObject = nil
screen:Destroy()
]],
			1
		)
		Double.run(check, "primitives", "screen-padding-and-gap", { [path] = source })
	end)
	harness:case("live report setup hides galleries for isolated fixtures", function(check)
		local path = "tools/studio/live/suites/primitives.luau"
		local source = string.gsub(
			Lute.fixture.host.readFile(path),
			"return cases",
			[[
local gallery = Instance.new("ScreenGui")
gallery.Name, gallery.Parent = "FacetGalleryProof", game.Players.LocalPlayer.PlayerGui
for _, case in cases do case.keepGallery = false end
return cases
]]
		)
		source = string.gsub(
			source,
			't.check%("this build has the layout constructors", present%)',
			[[
t.check("the original runner hides unrelated gallery controls", game.Players.LocalPlayer.PlayerGui.FacetGalleryProof.Enabled == false)
]],
			1
		)
		Double.run(check, "primitives", "screen-padding-and-gap", { [path] = source })
	end)
	harness:case("live report requirements cannot be bypassed", function(check)
		local path = "tools/studio/live/suites/primitives.luau"
		local source = string.gsub(
			Lute.fixture.host.readFile(path),
			"return cases",
			[[
for _, case in cases do case.requires = {"unavailable-native-observation"} end
return cases
]]
		)
		local proof = Verify.createHarness({ now = os.clock })
		proof:case("required native observation", function(context)
			Double.run(context, "primitives", "screen-padding-and-gap", { [path] = source })
		end)
		local report = proof:run({ executor = "live-double-requirements" })
		check:expect(report.failed):toBe(1)
	end)
	harness:case("live bodies use the wall deadline rather than an arbitrary virtual frame limit", function(check)
		local path = "tools/studio/live/suites/primitives.luau"
		local source, count = string.gsub(
			Lute.fixture.host.readFile(path),
			't.check%("this build has the layout constructors", present%)',
			'task.wait(601) t.check("this build has the layout constructors", present)',
			1
		)
		check:expect(count):toBe(1)
		Double.run(check, "primitives", "screen-padding-and-gap", { [path] = source })
	end)
	harness:case("live case scope preserves saved focus evidence", function(check)
		local path = "tools/studio/live/suites/primitives.luau"
		local source, count = string.gsub(
			Lute.fixture.host.readFile(path),
			't.check%("this build has the layout constructors", present%)',
			[[local live = require(game.ReplicatedStorage.FacetLive)
			live.signal("save evidence", function() live.save("focus-evidence", '{"observed":true}') end)
			t.check("this build has the layout constructors", present)]],
			1
		)
		check:expect(count):toBe(1)
		local proof = Verify.createHarness({ now = os.clock })
		proof:case("saved evidence", function(context)
			Double.run(context, "primitives", "screen-padding-and-gap", { [path] = source })
		end)
		local report = proof:run({ executor = "live-double-scope" })
		check:expect(report.passed):toBe(1)
		check:expect(report.results[1].artifacts[1].name):toBe("live/focus-evidence.json")
		check:expect(report.results[1].artifacts[1].content):toBe('{"observed":true}')
	end)
	harness:case("engine datatype details preserve live assertion outcomes", function(check)
		local path = "tools/studio/live/suites/primitives.luau"
		for _, passes in { true, false } do
			local source, count = string.gsub(
				Lute.fixture.host.readFile(path),
				't.check%("this build has the layout constructors", present%)',
				`t.check("datatype detail", {tostring(passes)}, Color3.new(1, 0, 0))`,
				1
			)
			check:expect(count):toBe(1)
			local proof = Verify.createHarness({ now = os.clock })
			proof:case("datatype detail", function(context)
				Double.run(context, "primitives", "screen-padding-and-gap", { [path] = source })
			end)
			local report = proof:run({ executor = "live-double-detail" })
			check:expect(report.passed):toBe(if passes then 1 else 0)
			check:expect(report.failed):toBe(if passes then 0 else 1)
			if not passes then
				local named = false
				for _, failure in report.results[1].failures do
					named = named or string.find(failure.message, "datatype detail", 1, true) ~= nil
				end
				check:expect(named):toBe(true)
			end
		end
	end)
	harness:case("all committed live sources register on the Verify engine double", function(check)
		local catalog = Double.catalog(check)
		check:expect(catalog.total > 0):toBe(true)
		check:expect(catalog.total):toBe(catalog.automatic + catalog.interactive)
	end)
	harness:case("every live case runs in CI or names why it cannot", function(check)
		local catalog = Double.catalog(check)
		local inCi = Contracts.names()
		local known: { [string]: boolean } = {}
		local unclassified: { string } = {}
		for _, source in catalog.sources do
			for _, case in source.cases do
				local name = `{source.id}/{case.id}`
				known[name] = true
				if not inCi[name] and not excluded[name] and not ownSpec[name] then
					table.insert(unclassified, name)
				end
			end
		end
		local stale: { string } = {}
		for name in excluded do
			if not known[name] or inCi[name] then
				table.insert(stale, name)
			end
		end
		table.sort(unclassified)
		table.sort(stale)
		check:expect(unclassified):toEqual({})
		check:expect(stale):toEqual({})
	end)
	for _, id in
		{
			"screen-padding-and-gap",
			"grid-cells-and-gaps",
			"zstack-alignment",
			"stack-distribution",
			"fill-and-extents",
			"scroll-view-capped-natural-height",
		}
	do
		harness:case(`original live primitives/{id} on the Verify engine double`, function(check)
			Double.run(check, "primitives", id)
		end)
	end
	harness:case("the unchanged live assertions reject a planted gap regression", function(check)
		local path = "tools/studio/live/suites/primitives.luau"
		local source, count = string.gsub(Lute.fixture.host.readFile(path), 'gap = "s"', 'gap = "m"', 1)
		check:expect(count):toBe(1)
		local proof = Verify.createHarness({ now = os.clock })
		proof:case("planted gap", function(context)
			Double.run(context, "primitives", "screen-padding-and-gap", { [path] = source })
		end)
		local report = proof:run({ executor = "live-double-defect" })
		check:expect(report.failed):toBe(1)
		local detected = false
		for _, step in report.results[1].steps do
			detected = detected or step.name == "B follows A by 10 + 8" and step.status == "failed"
		end
		check:expect(detected):toBe(true)
		Double.run(check, "primitives", "screen-padding-and-gap")
	end)
end
