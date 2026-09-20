--!strict
-- lune run bench/scope_churn [children|keyed-churn|keyed-reverse] [size] [samples]
-- Explicit owners isolate ownership; the keyed workloads run a mounted screen.
-- Run this same file on each revision, serially, in alternating order.
local process = require("@lune/process")
local serde = require("@lune/serde")
local nativeApp = require("./native_app")

local workload = process.args[1] or "keyed-churn"
local size = tonumber(process.args[2]) or 20000
local samples = tonumber(process.args[3]) or 150
assert(workload == "children" or workload == "keyed-churn" or workload == "keyed-reverse", "unknown workload")
assert(size > 0 and size % 1 == 0 and samples > 0 and samples % 1 == 0, "size and samples must be positive integers")
local world = nativeApp()
local Compose, UI, core = world.Compose, world.UI, world.core
local baseline = core.owner.size()
local owner = Compose.createOwner()
local children = {}
local close, root, items
local start = os.clock()
if workload == "children" then
	for i = 1, size do
		children[i] = owner.createChild()
	end
else
	local data = {}
	for i = 1, size do
		data[i] = { id = tostring(i), text = `row {i}` }
	end
	items = Compose.cell(data)
	close, root = world.app.mount(function()
		return UI.Screen("S")({
			UI.ForEach("Rows")({
				Compose.keyed({
					from = items,
					key = function(item)
						return item.id
					end,
					render = function(item)
						return UI.Text(`T{item:peek().id}`)({
							text = function(use)
								return use(item).text
							end,
						})
					end,
				}),
			}),
		})
	end, { rootPolicy = "edgeToEdge" })
end
local mountMs = (os.clock() - start) * 1000
local counter = 0
local function step()
	counter += 1
	if workload == "children" then
		for i = 1, math.max(1, size // 100) do
			children[i].dispose()
			children[i] = owner.createChild()
		end
	else
		local previous = items:peek()
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
	local rows = root.children[1].children
	assert(#rows == size)
	for i, item in items:peek() do
		assert(rows[i].props.text == item.text, `incorrect row {i}`)
	end
else
	assert(owner.size() == size, "incorrect live child owner count")
end
assert(core.lastError() == nil, tostring(core.lastError()))
start = os.clock()
if close then
	close()
	world.frame()
end
owner.dispose()
local unmountMs = (os.clock() - start) * 1000
assert(core.lastError() == nil, tostring(core.lastError()))
assert(world.adapter.rootCount() == 0, "the dismissed screen is still mounted")
local registrations = core.owner.size()
assert(registrations == baseline, `leaked {registrations - baseline} registrations`)
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
	teardown = core.owner.size(),
}))
