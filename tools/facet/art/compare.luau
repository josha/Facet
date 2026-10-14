--!strict

local Raster = require("../lib/raster")

type Image = Raster.Image

export type Metrics = {
	identical: boolean,
	sameShape: boolean,
	maxDelta: number,
	meanAbsoluteError: number,
	differingPercent: number,
}

export type Tolerance = { maxDelta: number, meanAbsoluteError: number, differingPercent: number }

local Compare = {}

Compare.EXACT = table.freeze({ maxDelta = 0, meanAbsoluteError = 0, differingPercent = 0 }) :: Tolerance

function Compare.metrics(expected: Image, actual: Image): Metrics
	if expected.width ~= actual.width or expected.height ~= actual.height then
		return { identical = false, sameShape = false, maxDelta = 255, meanAbsoluteError = 255, differingPercent = 100 }
	end
	local left = if expected.channels == 4 then expected else Raster.Image.convert(expected, 4)
	local right = if actual.channels == 4 then actual else Raster.Image.convert(actual, 4)
	if buffer.tostring(left.data) == buffer.tostring(right.data) then
		return { identical = true, sameShape = true, maxDelta = 0, meanAbsoluteError = 0, differingPercent = 0 }
	end
	local pixels = left.width * left.height
	local maxDelta, total, differing = 0, 0, 0
	for pixel = 0, pixels - 1 do
		local changed = false
		for channel = 0, 3 do
			local delta =
				math.abs(buffer.readu8(left.data, pixel * 4 + channel) - buffer.readu8(right.data, pixel * 4 + channel))
			if delta > 0 then
				changed = true
				total += delta
				if delta > maxDelta then
					maxDelta = delta
				end
			end
		end
		if changed then
			differing += 1
		end
	end
	return {
		identical = false,
		sameShape = true,
		maxDelta = maxDelta,
		meanAbsoluteError = total / (pixels * 4),
		differingPercent = differing / pixels * 100,
	}
end

function Compare.within(metrics: Metrics, tolerance: Tolerance): boolean
	return metrics.sameShape
		and metrics.maxDelta <= tolerance.maxDelta
		and metrics.meanAbsoluteError <= tolerance.meanAbsoluteError
		and metrics.differingPercent <= tolerance.differingPercent
end

function Compare.describe(metrics: Metrics): string
	if metrics.identical then
		return "identical"
	elseif not metrics.sameShape then
		return "different size"
	end
	return ("max delta %d, mean abs error %.4f, %.2f%% pixels differ"):format(
		metrics.maxDelta,
		metrics.meanAbsoluteError,
		metrics.differingPercent
	)
end

return table.freeze(Compare)
