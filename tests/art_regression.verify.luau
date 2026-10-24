--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local expect = Verify.expect
	local fs = require("@std/fs")
	local Raster = require("../tools/facet/lib/raster")
	local targets = require("../tools/facet/art")
	local Compare = require("../tools/facet/art/compare")

	verifyHarness:suite("generated art matches the committed files", function()
		for _, target in targets do
			local name = `{target.name} regenerates every committed PNG pixel for pixel`
			verifyHarness:case(name, {
				id = `art_regression::generated art matches the committed files::{name}`,
				timeoutSeconds = 300,
				run = function()
					local problems: { string } = {}
					local outputs = target.generate()
					expect(#outputs > 0):toBe(true)
					for _, output in outputs do
						if not fs.exists(output.path) then
							table.insert(problems, `{output.path}: not committed`)
						else
							local committed = Raster.Png.decode(buffer.fromstring(fs.readFileToString(output.path)))
							local metrics = Compare.metrics(committed, output.image)
							if not Compare.within(metrics, Compare.EXACT) then
								table.insert(problems, `{output.path}: {Compare.describe(metrics)}`)
							end
						end
					end
					expect(table.concat(problems, "\n")):toBe("")
				end,
			})
		end
	end)

	verifyHarness:suite("standard icon registry", function()
		local name = "every registered glyph has committed art and its upload record"
		verifyHarness:case(name, {
			id = `art_regression::standard icon registry::{name}`,
			run = function()
				local icons = require("../src/ui/icons")
				local Json = require("../tools/facet/lib/json")
				local manifest = Json.objectField(
					Json.decode(fs.readFileToString("assets/icons/upload-manifest.json")),
					"assets"
				) or Json.object()
				local problems: { string } = {}
				local registered: { [string]: boolean } = {}
				for iconName, art in icons.ART do
					registered[art.assetName] = true
					if not fs.exists(`assets/icons/{art.assetName}.png`) then
						table.insert(problems, `{iconName}: assets/icons/{art.assetName}.png is not committed`)
					end
					local uploaded = Json.stringField(manifest[art.assetName], "contentId") or ""
					if art.contentId ~= uploaded then
						table.insert(problems, `{iconName}: registry '{art.contentId}', manifest '{uploaded}'`)
					end
				end
				for _, entry in fs.listDirectory("assets/icons") do
					local stem = string.match(entry.name, "^(facet_icon_[%w_]+)%.png$")
					if stem ~= nil and not registered[stem] then
						table.insert(problems, `assets/icons/{entry.name} has no registry entry`)
					end
				end
				table.sort(problems)
				expect(table.concat(problems, "\n")):toBe("")
				for _, glyph in { "star", "coin", "gem", "gift", "chat", "lock", "car" } do
					expect(icons.ART[glyph].assetName):toBe(`facet_icon_{glyph}`)
				end
			end,
		})
	end)
end
