--!strict

export type Progress = { checkpoint: number, lap: number, progress: number }
export type Rank = { name: string, progress: number, finish: number, out: boolean }

local function advance(racer: Progress, t: number, onRoad: boolean, checkpoints: number): boolean
	local checkpoint = math.floor(t * checkpoints)
	local crossed = onRoad and checkpoint == (racer.checkpoint + 1) % checkpoints
	if crossed then
		racer.checkpoint = checkpoint
		if checkpoint == 0 then
			racer.lap += 1
		end
	end
	local fraction = if onRoad then math.clamp(t * checkpoints - racer.checkpoint, 0, 1) else 0
	racer.progress = racer.lap + (racer.checkpoint + fraction) / checkpoints
	return crossed and checkpoint == 0
end

local function ahead(a: Rank, b: Rank): boolean
	if a.out ~= b.out then
		return not a.out
	end
	if a.finish ~= b.finish then
		return a.finish < b.finish
	end
	if a.progress == b.progress then
		return a.name < b.name
	end
	return a.progress > b.progress
end

return { advance = advance, ahead = ahead }
