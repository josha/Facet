--!strict
local process = require("@lune/process")
local serde = require("@lune/serde")
local nativeApp = require("./native_app")
local workload = process.args[1] or "keyed-churn"
local size = tonumber(process.args[2]) or 20000
local samples = tonumber(process.args[3]) or 150
assert(workload == "children" or workload == "keyed-churn" or workload == "keyed-reverse", "unknown workload")
assert(size > 0 and size % 1 == 0 and samples > 0 and samples % 1 == 0, "invalid sample dimensions")
local world = nativeApp()
local Compose, Host = world.Compose, world.Host
local owner = Compose.createOwner(world.runtime.reactor)
local children = {}
local stop, root, items
local started = os.clock()
if workload == "children" then
	for index = 1, size do
		children[index] = owner.createChild()
	end
else
	local data = {}
	for index = 1, size do
		data[index] = { id = tostring(index), text = `row {index}` }
	end
	items = Compose.cell(data)
	stop, root = world.runtime.mount(function()
		return Host.Folder({
			Compose.keyed({
				from = items,
				key = "id",
				render = function(current)
					return Host.TextLabel({
						Name = function(use)
							return use(current).id
						end,
						Text = function(use)
							return use(current).text
						end,
					})
				end,
			}),
		})
	end, world.target)
end
local mountMs = (os.clock() - started) * 1000
local counter = 0
local function step()
	counter += 1
	if workload == "children" then
		for index = 1, math.max(1, size // 100) do
			children[index].dispose()
			children[index] = owner.createChild()
		end
	else
		local previous = items:peek()
		local changed = table.clone(previous)
		if workload == "keyed-reverse" then
			for index = 1, size do
				changed[index] = previous[size - index + 1]
			end
		else
			for index = 1, math.max(1, size // 100) do
				changed[index] = { id = `new-{counter}-{index}`, text = `row {counter} {index}` }
			end
		end
		items:set(changed)
	end
end
for _ = 1, 20 do
	step()
end
local timings = {}
for index = 1, samples do
	local before = os.clock()
	step()
	timings[index] = (os.clock() - before) * 1000
end
if root then
	local byName = {}
	for _, node in root:GetChildren() do
		byName[node.Name] = node
	end
	assert(#root:GetChildren() == size)
	for _, item in items:peek() do
		assert(byName[item.id].Text == item.text, `incorrect row {item.id}`)
	end
else
	assert(owner.size() == size, "incorrect live child owner count")
end
started = os.clock()
if stop then
	stop()
end
owner.dispose()
world.dispose()
local unmountMs = (os.clock() - started) * 1000
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
	teardown = #world.target:GetChildren(),
	evidenceClass = "lune",
	geometryMeasured = false,
}))
