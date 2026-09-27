--!strict
local MEASURED = {
	RoundsRow = { 148, 44 },
	RoundsColumn = { 44, 148 },
	TasksFull = { 225, 124 },
	TasksOne = { 151, 24 },
	TasksCompact = { 75, 36 },
	HealthPod = { 146, 26 },
	HealthCompact = { 38, 26 },
	FeedText = { 83, 12 },
	ClockFull = { 164, 36 },
	ClockCompact = { 48, 26 },
	ClockShort = { 41, 26 },
	RailFull = { 101, 116 },
	RailCompact = { 39, 20 },
	ReadoutText = { 64, 12 },
	ActionsFull = { 148, 44 },
	ActionsCompact = { 44, 44 },
	WeaponText = { 52, 12 },
	Objective = { 120, 26 },
	ObjectiveShort = { 30, 26 },
	Reveal = { 28, 28 },
}
local LANDSCAPE, PORTRAIT, TINY = { 828, 256 }, { 374, 560 }, { 300, 140 }

local function measure(root: any, engine: any, box: { number })
	local V2 = engine.types.Vector2
	for name, size in MEASURED do
		for _, node in root:GetDescendants() do
			if
				node.Name == name
				and node.Parent
				and node.Parent.Parent
				and node.Parent.Parent:GetAttribute("FacetForm") ~= nil
			then
				node.AbsoluteSize = V2.new(size[1], size[2])
			end
		end
	end
	root:FindFirstChild("Zones", true).AbsoluteSize = V2.new(box[1], box[2])
end

return { MEASURED = MEASURED, LANDSCAPE = LANDSCAPE, PORTRAIT = PORTRAIT, TINY = TINY, measure = measure }
