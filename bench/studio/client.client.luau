--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type Lane = { median: number }
type Row = { id: string, status: string, facet: Lane?, bare: Lane? }

local repo = ReplicatedStorage:WaitForChild("FacetRepo")
local runner = repo:WaitForChild("bench"):WaitForChild("studio"):WaitForChild("run") :: ModuleScript
local run = (require(runner) :: unknown) :: (Instance, string?) -> { Row }
local player = Players.LocalPlayer
task.wait(2)
local rows = run(player:WaitForChild("PlayerGui"), nil)
local lines = { "| Workload | Bare (us) | Facet (us) | Facet / bare | Status |", "| --- | ---: | ---: | ---: | --- |" }
for _, row in rows do
	local facet, bare = row.facet, row.bare
	if facet and bare then
		table.insert(
			lines,
			string.format(
				"| %s | %.0f | %.0f | %.2fx | %s |",
				row.id,
				bare.median,
				facet.median,
				facet.median / bare.median,
				row.status
			)
		)
	else
		table.insert(lines, string.format("| %s | | | | %s |", row.id, row.status))
	end
end
local report = table.concat(lines, "\n")
ReplicatedStorage:SetAttribute("FacetStudioBench", report)
print(report)
