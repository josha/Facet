--!strict
-- T15 probe (item 2): what does the ADR-0037 `Facet.Controls.<Name>` closure hop
-- cost? It is one Luau call frame between the author and `<control>.build`, at
-- CONSTRUCTION only. Compared against the legacy spelling it replaced, which is
-- the same builder called directly. Throwaway.
local Facet = require("../../src") :: any

local N = 4000

local function timeIt(label: string, fn: (i: number) -> ()): number
	for i = 1, 200 do
		fn(i)
	end
	local t0 = os.clock()
	for i = 1, N do
		fn(i)
	end
	local ms = (os.clock() - t0) * 1000 / N
	print(`{label}: {string.format("%.5f", ms)} ms/construction`)
	return ms
end

local core = Facet.newCore()

-- the cheapest composite there is, so the hop is the largest possible FRACTION
local viaNamespace = timeIt("Facet.Controls.ProgressView (one closure hop)", function(i)
	local bar = Facet.Controls.ProgressView(core, { id = `P{i}`, value = 0.5 })
	if bar.dispose ~= nil then
		bar.dispose()
	end
end)
local viaLegacy = timeIt("Facet.newProgressView (the builder direct)", function(i)
	local bar = Facet.newProgressView(Facet, core, { id = `Q{i}`, value = 0.5 })
	if bar.dispose ~= nil then
		bar.dispose()
	end
end)

-- ...and the bare frame, so the difference above has a scale to be read against
local function inner(a: any, b: any, c: any): any
	return a
end
local wrapper = function(b: any, c: any)
	return inner(core, b, c)
end
local hop = timeIt("a bare closure hop (control)", function(i)
	local _ = wrapper(core, i)
end)
local direct = timeIt("a bare direct call (control)", function(i)
	local _ = inner(core, core, i)
end)

print("")
print(
	`namespace vs legacy: {string.format("%+.5f", viaNamespace - viaLegacy)} ms `
		.. `({string.format("%+.2f", (viaNamespace / viaLegacy - 1) * 100)}%)`
)
print(`the hop ITSELF, isolated: {string.format("%+.6f", hop - direct)} ms`)
