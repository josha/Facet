--!strict
local Verify = require("../tools/vendor/verify/src/core")
local format = require("../src/ui/format")

return function(harness: Verify.Harness)
	harness:case("compact rounds significant digits and promotes suffixes", function(t)
		local cases: { { number | string } } = {
			{ 93210, "93.2K" },
			{ 2350, "2.35K" },
			{ 1250000, "1.25M" },
			{ 999, "999" },
			{ -2350, "-2.35K" },
			{ 0, "0" },
			{ 1500, "1.5K" },
			{ 12000, "12K" },
			{ 999950, "1M" },
			{ 999949, "1M" },
			{ 999499, "999K" },
			{ 1e9, "1B" },
			{ 1e12, "1T" },
		}
		for _, pair in cases do
			t:expect(format.compact(pair[1] :: number)):toBe(pair[2])
		end
		t:expect(format.compact(2350, { significantDigits = 2 })):toBe("2.4K")
		t:expect(format.compact(-999950)):toBe("-1M")
		t:expect(format.compact(999950, { significantDigits = 4 })):toBe("1M")
	end)
	harness:case("grouped preserves requested decimals and literal separators", function(t)
		t:expect(format.grouped(387153)):toBe("387,153")
		t:expect(format.grouped(1234567.5, { decimals = 1 })):toBe("1,234,567.5")
		t:expect(format.grouped(-1234567.5, { decimals = 2, separator = "_" })):toBe("-1_234_567.50")
		t:expect(format.grouped(999.99, { decimals = 1 })):toBe("1,000.0")
		t:expect(format.grouped(0)):toBe("0")
		t:expect(format.grouped(1000000, { separator = "%" })):toBe("1%000%000")
	end)
	harness:case("duration clamps and changes fields at minute and hour boundaries", function(t)
		local cases: { { number | string } } = {
			{ 59, "0:59" },
			{ 60, "1:00" },
			{ 3599, "59:59" },
			{ 3600, "1:00:00" },
			{ -1, "0:00" },
			{ 0, "0:00" },
			{ 3723, "1:02:03" },
		}
		for _, pair in cases do
			t:expect(format.duration(pair[1] :: number)):toBe(pair[2])
		end
		t:expect(format.duration(77.9)):toBe("1:17")
		t:expect(format.duration(77, { hours = true })):toBe("0:01:17")
	end)
	harness:case("formatters refuse nonfinite numbers and invalid precision", function(t)
		for _, value in { 0 / 0, math.huge, -math.huge } do
			local formatters: { (number) -> string } = {
				function(number: number): string
					return format.compact(number)
				end,
				function(number: number): string
					return format.grouped(number)
				end,
				function(number: number): string
					return format.duration(number)
				end,
			}
			for _, formatter in formatters do
				local ok = pcall(formatter, value)
				t:expect(ok):toBe(false)
			end
		end
		for _, digits in { 0, -1, 1.5, math.huge, 0 / 0, 16 } do
			local ok = pcall(function(): string
				return format.compact(1, { significantDigits = digits })
			end)
			t:expect(ok):toBe(false)
		end
		local ok = pcall(function(): string
			return format.grouped(1, { decimals = -1 })
		end)
		t:expect(ok):toBe(false)
	end)
end
