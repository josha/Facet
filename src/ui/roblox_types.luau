--!strict
local Shared = require("./types")

local cached: Shared.RobloxTypes? = nil

return function(): Shared.RobloxTypes
	local known = cached
	if
		known
		and known.Enum == Enum
		and known.UDim2 == UDim2
		and known.Color3 == Color3
		and known.TweenInfo == TweenInfo
		and known.Font == Font
	then
		return known
	end
	local made: Shared.RobloxTypes = {
		UDim = UDim,
		UDim2 = UDim2,
		Vector2 = Vector2,
		Vector3 = Vector3,
		Color3 = Color3,
		CFrame = CFrame,
		RaycastParams = RaycastParams,
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
	cached = made
	return made
end
