--!strict
local storage = game:GetService("ReplicatedStorage")
local Facet = require(storage:WaitForChild("Facet"))
local screen = require(storage:WaitForChild("FacetConsumerScreen"))
local app = Facet.app({ name = "FacetConsumer" })
app.mount(function()
	return screen.build(Facet, app.UI)
end)
script.Destroying:Connect(app.dispose)
