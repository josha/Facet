--!strict
local Facet = require(game:GetService("ReplicatedStorage").Packages.Facet)
local run = require(script.Recipes)
local actionEnabled = Facet.Compose.cell(script:GetAttribute("DisableAction") ~= true)
local stop: (() -> ())? = nil
local function mount()
	if stop then
		stop()
	end
	local example = script:GetAttribute("Example")
	stop = run(if type(example) == "string" then example else "Bakery", script:GetAttribute("Weak") == true, actionEnabled)
end
script:GetAttributeChangedSignal("Example"):Connect(mount)
script:GetAttributeChangedSignal("Weak"):Connect(mount)
script:GetAttributeChangedSignal("DisableAction"):Connect(function()
	actionEnabled:set(script:GetAttribute("DisableAction") ~= true)
end)
script.Destroying:Connect(function()
	if stop then
		stop()
	end
end)
mount()
