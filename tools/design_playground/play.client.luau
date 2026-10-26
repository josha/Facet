--!strict

local storage = game:GetService("ReplicatedStorage")
local Facet = require(storage.Facet)
local remote = storage:WaitForChild("ComposeDesignStorage")
assert(remote:IsA("RemoteFunction"), "ComposeDesignStorage must be a RemoteFunction")
local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "ComposeDesignPlay"
screen.ResetOnSpawn = false
screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local loaded, source = remote:InvokeServer("load")
local saved: string = if loaded and type(source) == "string" then source else ""
local pending: string? = nil
local scheduled = false

local schedule: () -> ()
local function flush()
	scheduled = false
	local snapshot = pending
	if snapshot == nil then
		return
	end
	pending = nil
	local ok, problem = remote:InvokeServer("save", snapshot)
	if not ok then
		warn(`Compose Design: {problem}`)
		pending = pending or snapshot
		schedule()
	end
end

schedule = function()
	if not scheduled then
		scheduled = true
		task.delay(8, flush)
	end
end

local opened = Facet.composeDesign().edit(screen, "Screen", {
	read = function(): string
		return saved
	end,
	write = function(expected: string, generated: string): boolean
		if saved ~= expected then
			return false
		end
		saved = generated
		pending = generated
		schedule()
		return true
	end,
	watch = function(_changed: () -> ()): () -> ()
		return function() end
	end,
})

script.Destroying:Connect(function()
	flush()
	opened.dispose()
	screen:Destroy()
end)
