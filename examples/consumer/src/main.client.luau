--!strict
if not game:IsLoaded() then
	game.Loaded:Wait()
end
local storage = game:GetService("ReplicatedStorage")
local Facet = require(storage:WaitForChild("Facet"))
local screen = require(storage:WaitForChild("FacetConsumerScreen"))
local app = Facet.new()
screen.session(Facet, app, { closeAfterSeconds = 120 })
