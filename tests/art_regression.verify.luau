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
end
