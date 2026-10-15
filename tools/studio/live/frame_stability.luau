--!strict
export type Sample = { path: string, rect: { number }, text: { number }? }
export type Fault = { path: string, frame: number, firstFrame: number, delta: { number }, textDelta: { number }? }
export type Tracker = {
	frame: number,
	quiet: number,
	seen: number,
	first: { [string]: { frame: number, sample: Sample } },
	previous: { [string]: Sample },
	faults: { Fault },
}

local function equal(a: Sample, b: Sample): boolean
	for index, value in a.rect do
		if value ~= b.rect[index] then
			return false
		end
	end
	local x, y = a.text, b.text
	return if x and y then x[1] == y[1] and x[2] == y[2] else x == y
end

local function new(): Tracker
	return { frame = 0, quiet = 0, seen = 0, first = {}, previous = {}, faults = {} }
end

local function push(tracker: Tracker, samples: { Sample })
	tracker.frame += 1
	local changed = false
	local current: { [string]: Sample } = {}
	for _, sample in samples do
		current[sample.path] = sample
		local previous = tracker.previous[sample.path]
		changed = changed or previous == nil or not equal(previous, sample)
		local first = tracker.first[sample.path]
		if first == nil then
			tracker.seen += 1
			tracker.first[sample.path] = { frame = tracker.frame, sample = sample }
		elseif previous == nil or not equal(previous, sample) then
			local delta, failed = {}, false
			for index, value in sample.rect do
				delta[index] = value - first.sample.rect[index]
				failed = failed or math.abs(delta[index]) > 0.5
			end
			local textDelta: { number }? = nil
			local a, b = first.sample.text, sample.text
			if a and b then
				local difference = { b[1] - a[1], b[2] - a[2] }
				textDelta = difference
				failed = failed or difference[1] ~= 0 or difference[2] ~= 0
			end
			if failed then
				table.insert(tracker.faults, {
					path = sample.path,
					frame = tracker.frame,
					firstFrame = first.frame,
					delta = delta,
					textDelta = textDelta,
				})
			end
		end
	end
	for path in tracker.previous do
		changed = changed or current[path] == nil
	end
	tracker.previous = current
	tracker.quiet = if changed then 0 else tracker.quiet + 1
end

return { new = new, push = push }
