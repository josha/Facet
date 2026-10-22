--!strict

export type Racer = {
	name: string,
	position: number,
	lap: number,
	lapCount: number,
	completedLaps: number,
	bestLap: number?,
	gap: number,
	finished: boolean,
	eliminated: boolean,
}

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

local function lapKnockout(racers: { Racer }, lastLap: number): (string?, number)
	local lap = 0
	local active = 0
	local last: string? = nil
	for _, racer in racers do
		if not racer.eliminated then
			active += 1
			lap = math.max(lap, racer.completedLaps)
			if not racer.finished then
				last = racer.name
			end
		end
	end
	return if active > 1 and lap >= 1 and lap > lastLap then last else nil, math.max(lastLap, lap)
end

return { advance = advance, ahead = ahead, lapKnockout = lapKnockout }
