--!strict

type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
local Facet = require("../../src")

local types = {
	Enum = Enum,
	UDim = UDim,
	UDim2 = UDim2,
	Vector2 = Vector2,
	Vector3 = Vector3,
	Color3 = Color3,
	CFrame = CFrame,
	Rect = Rect,
	NumberSequence = NumberSequence,
	NumberSequenceKeypoint = NumberSequenceKeypoint,
	ColorSequence = ColorSequence,
	ColorSequenceKeypoint = ColorSequenceKeypoint,
	NumberRange = NumberRange,
	Font = Font,
	TweenInfo = TweenInfo,
	BrickColor = BrickColor,
}

export type World = {
	Facet: typeof(Facet),
	Compose: typeof(Facet.Compose),
	runtime: Facet.Runtime,
	Host: RobloxHost,
	UI: Facet.Controls,
	engine: { new: (string) -> Instance, environment: { poke: () -> () } },
	target: Instance,
	types: typeof(types),
	viewport: { w: number, h: number },
	frame: (number?) -> (),
	dispose: () -> (),
}

return function(parent: Instance): World
	local runtime = Facet.Roblox.createRuntime()
	local target = Instance.new("Folder")
	target.Name = "StudioBench"
	target.Parent = parent
	local root = Facet.Compose.createRootOwner(function()
		runtime.adopt(target)
	end, runtime.reactor)
	return {
		Facet = Facet,
		Compose = Facet.Compose,
		runtime = runtime,
		Host = (runtime.constructors :: unknown) :: RobloxHost,
		UI = Facet.controls(runtime),
		engine = {
			new = function(class: string): Instance
				return Instance.new(class)
			end,
			environment = {
				poke = function() end,
			},
		},
		target = target,
		types = types,
		viewport = { w = 800, h = 600 },
		frame = function()
			runtime:settle()
		end,
		dispose = function()
			root.dispose()
			runtime:dispose()
			target:Destroy()
		end,
	}
end
