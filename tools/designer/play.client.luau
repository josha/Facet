--!strict

type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false)

local storage = game:GetService("ReplicatedStorage")
local Facet = require(storage.Facet)
local designer = require(storage.FacetDesignModules.designer)
local runtime: ComposeRuntime = Facet.Roblox.createRuntime()
local Host = (runtime.constructors :: unknown) :: RobloxHost
local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local stopBackground = runtime.mount(function()
	return Host.ScreenGui "FacetDesignBackground" {
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 0,
		Host.Frame "Background" {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(237, 240, 247),
			BorderSizePixel = 0,
		},
	}
end, playerGui)
local stop, screen = runtime.mount(function()
	return Host.ScreenGui "FacetDesignPlay" {
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}
end, playerGui)
local remote = storage:WaitForChild("FacetDesignStorage") :: RemoteFunction
local loaded, response = pcall(function()
	return remote:InvokeServer("load")
end)
local canSave = loaded and response.ok
local memory = if canSave then response.library else {}
local pending: any
local scheduled = false
local saving = false
local mounted: any
local flush: () -> ()
local function schedule()
	if scheduled then
		return
	end
	scheduled = true
	task.delay(8, function()
		scheduled = false
		flush()
	end)
end
flush = function()
	if saving or not pending then
		return
	end
	saving = true
	local snapshot = pending
	pending = nil
	local ok, result = pcall(function()
		return remote:InvokeServer("save", snapshot)
	end)
	if mounted then
		mounted.model:update(function(previous)
			local nextValue = table.clone(previous)
			nextValue.status = if ok and result.ok
				then "Saved to your private library"
				elseif ok and result.retryable == false then result.message
				else "Cloud save failed. Retrying shortly; keep this session open"
			return nextValue
		end)
	end
	if not ok or not result.ok then
		pending = pending or snapshot
		if ok and result.retryable == false then
			canSave = false
		else
			schedule()
		end
	end
	saving = false
end
mounted = designer.mount(Facet, screen :: ScreenGui, {
	inputParent = playerGui,
	keyboardNavigation = true,
	read = function()
		return memory
	end,
	flush = function()
		task.spawn(flush)
	end,
	write = function(value)
		assert(canSave, "Saved designs unavailable. Your changes are local until you rejoin")
		memory = require(storage.FacetDesignModules.document).copy(value)
		pending = memory
		schedule()
	end,
})

if not canSave then
	mounted.model:update(function(previous)
		local nextValue = table.clone(previous)
		nextValue.status = "Saved designs are unavailable in this session. Rejoin to retry"
		return nextValue
	end)
end

script.Destroying:Connect(function()
	mounted.dispose()
	stop()
	stopBackground()
	runtime:dispose()
end)
