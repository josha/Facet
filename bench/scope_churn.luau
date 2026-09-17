--!strict
-- lune run bench/scope_churn [children|keyed-churn|keyed-reverse] [size] [samples]
-- Explicit scopes and handles isolate ownership/composition from rendering.
-- Run this same file on each revision, serially, in alternating order.
local process = require("@lune/process")
local serde = require("@lune/serde")
local Facet = require("../src") :: any

local workload = process.args[1] or "keyed-churn"
local size = tonumber(process.args[2]) or 20000
local samples = tonumber(process.args[3]) or 150
assert(workload == "children" or workload == "keyed-churn" or workload == "keyed-reverse", "unknown workload")
assert(size > 0 and size % 1 == 0 and samples > 0 and samples % 1 == 0, "size and samples must be positive integers")
local core = Facet.newCore()
local scope = core:scope("benchmark")
local children = {}
local root, items
local start = os.clock()
if workload == "children" then
	for i = 1, size do
		children[i] = scope:child()
	end
else
	local data = {}
	for i = 1, size do
		data[i] = { id = tostring(i), text = `row {i}` }
	end
	items = scope:own(core:signal(data))
	root = Facet.mount(
		core,
		Facet.UI.Screen({
			id = "S",
			Facet.UI.ForEach({
				id = "Rows",
				items = items,
				key = function(item)
					return item.id
				end,
				row = function(item)
					return Facet.UI.Text({ id = "T", text = item.text })
				end,
			}),
		})
	)
end
local mountMs = (os.clock() - start) * 1000
local counter = 0
local function step()
	counter += 1
	if workload == "children" then
		for i = 1, math.max(1, size // 100) do
			children[i]:dispose()
			children[i] = scope:child()
		end
	else
		local previous = items:get()
		local changed = table.clone(previous)
		if workload == "keyed-reverse" then
			for i = 1, size do
				changed[i] = previous[size - i + 1]
			end
		else
			for i = 1, math.max(1, size // 100) do
				changed[i] = { id = `new-{counter}-{i}`, text = `row {counter} {i}` }
			end
		end
		items:set(changed)
	end
end
for _ = 1, 20 do
	step()
end
local timings = {}
for i = 1, samples do
	local before = os.clock()
	step()
	timings[i] = (os.clock() - before) * 1000
end
if root then
	local rows = root.node.children[1].children
	assert(#rows == size)
	for i, item in items:get() do
		assert(rows[i].props.text == item.text, `incorrect row {i}`)
	end
else
	assert(core:counters().scopes == size + 1, "incorrect live scope count")
end
assert(core:lastError() == nil, tostring(core:lastError()))
start = os.clock()
if root then
	root.dispose()
end
scope:dispose()
local unmountMs = (os.clock() - start) * 1000
assert(core:lastError() == nil, tostring(core:lastError()))
for key, value in core:counters() do
	assert(value == 0, `leaked {key}: {value}`)
end
table.sort(timings)
print(serde.encode("json", {
	workload = workload,
	size = size,
	samples = samples,
	p50 = timings[math.ceil(samples * 0.5)],
	p95 = timings[math.ceil(samples * 0.95)],
	p99 = timings[math.ceil(samples * 0.99)],
	mountMs = mountMs,
	unmountMs = unmountMs,
	teardown = core:counters(),
}))
