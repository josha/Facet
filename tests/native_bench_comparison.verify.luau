--!strict

local Verify = require("../tools/vendor/verify/src/core")
local Workloads = require("../bench/comparison")
local Parity = require("../bench/comparison/parity")
local Types = require("../bench/comparison/types")
local S = require("../bench/comparison/support")

return function(harness: Verify.Harness)
	harness:suite("Facet versus bare", function()
		for _, workload in Workloads do
			harness:case(workload.id, {
				id = "native_bench_comparison::" .. workload.id,
				run = function()
					Parity(workload)
				end,
			})
		end
		harness:case("parity rejects a hidden matching item", {
			id = "native_bench_comparison::parity rejects a hidden matching item",
			run = function()
				local source: Types.Workload? = nil
				for _, workload in Workloads do
					if workload.id == "shop-filter-200" then
						source = workload
						break
					end
				end
				local subject = assert(source)
				local broken: Types.Workload = {
					id = subject.id,
					iterations = subject.iterations,
					what = subject.what,
					prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
						local scene = subject.prepare(world, lane)
						return {
							step = function(index: number)
								scene.step(index)
								if lane == "facet" then
									S.find(world, "Item1").Visible = false
								end
							end,
							snapshot = scene.snapshot,
							stop = scene.stop,
						}
					end,
				}
				Verify.expect(function()
					Parity(broken)
				end):toThrow("differs at checkpoint 1")
			end,
		})
	end)
end
