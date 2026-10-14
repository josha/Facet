--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local motion = require("./motion")

return function(
	Compose: Shared.ComposeModule,
	runtime: ComposeTypes.Runtime,
	options: Shared.Config?
): (Shared.Config, Shared.RobloxTypes, Shared.Services)
	assert(runtime.host.name == "roblox", "Facet.controls requires a Compose Roblox runtime")
	local config: Shared.Config = if options then table.clone(options) else {}
	assert(
		((config :: unknown) :: { [string]: unknown }).reducedMotion == nil,
		'Facet: the reducedMotion option is gone; set motionLevel = "normal", "limited" or "none"'
	)
	if type(config.motionLevel) == "string" then
		motion.check(config.motionLevel)
	end
	motion.publish(Compose, runtime, config.motionLevel)
	local environment = config.environment
	if environment and environment.preferredTextSize ~= nil then
		local owner = (runtime :: unknown) :: { [string]: unknown }
		local previous = owner.FacetTextPreference
		owner.FacetTextPreference = environment.preferredTextSize
		if Compose.currentOwner() then
			Compose.cleanup(function()
				if owner.FacetTextPreference == environment.preferredTextSize then
					owner.FacetTextPreference = previous
				end
			end)
		end
	end
	local types: Shared.RobloxTypes = config.types
		or {
			UDim = UDim,
			UDim2 = UDim2,
			Vector2 = Vector2,
			Vector3 = Vector3,
			Color3 = Color3,
			CFrame = CFrame,
			Enum = Enum,
			Font = Font,
			Rect = Rect,
			ColorSequence = ColorSequence,
			ColorSequenceKeypoint = ColorSequenceKeypoint,
			NumberSequence = NumberSequence,
			NumberSequenceKeypoint = NumberSequenceKeypoint,
			NumberRange = NumberRange,
			Path2DControlPoint = Path2DControlPoint,
			FloatCurveKey = FloatCurveKey,
			TweenInfo = TweenInfo,
			BrickColor = BrickColor,
		}
	assert(types.UDim2 and types.Enum, "Facet.controls requires Roblox datatypes")
	local services: Shared.Services = if config.services then table.clone(config.services) else {}
	if game then
		services.GamepadService = services.GamepadService or game:GetService("GamepadService")
		services.GuiService = services.GuiService or game:GetService("GuiService")
		services.UserInputService = services.UserInputService or game:GetService("UserInputService")
		services.Players = services.Players or game:GetService("Players")
		services.RunService = services.RunService or game:GetService("RunService")
		services.TextService = services.TextService or game:GetService("TextService")
		services.ContentProvider = services.ContentProvider or game:GetService("ContentProvider")
		services.Workspace = services.Workspace or game:GetService("Workspace")
		services.TweenService = services.TweenService or game:GetService("TweenService")
	end
	config.services = services
	config.guiService = config.guiService or services.GuiService
	config.userInputService = config.userInputService or services.UserInputService
	return config, types, services
end
