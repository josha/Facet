--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Facet = require(ReplicatedStorage:WaitForChild("Facet"))
local demo = require(ReplicatedStorage:WaitForChild("MinimapExample"):WaitForChild("minimap_demo"))
local C = Facet.Compose
local app = Facet.app { name = "MinimapExample", suspendGameplay = true }
local UI, Host = app.UI, Facet.host(app.runtime)
local types: typeof(require("@repo/tools/typecheck/aliases").RobloxTypes) = {
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
app.mount(function()
	local radar = C.cell(false)
	return UI.Screen "MapExample" {
		surface = "surface",
		padding = 0,
		UI.HStack "MapChoices" {
			width = "fill",
			wrap = true,
			padding = "s",
			UI.Button {
				label = "Race course",
				onActivate = function()
					radar:set(false)
				end,
			},
			UI.Button {
				label = "Radar",
				onActivate = function()
					radar:set(true)
				end,
			},
		},
		UI.VStack "MapExampleBody" {
			width = "fill",
			UI.fill(),
			C.show(function(use: Facet.Use): boolean
				return not use(radar)
			end, function()
				return demo.build({
					UI = UI,
					Host = Host,
					Compose = C,
					app = app,
					types = types,
					cell = function<T>(_name: string, value: T)
						return C.cell(value)
					end,
				}, {})
			end),
			C.show(radar, function()
				return demo.build({
					UI = UI,
					Host = Host,
					Compose = C,
					app = app,
					types = types,
					cell = function<T>(_name: string, value: T)
						return C.cell(value)
					end,
				}, { radar = true })
			end),
		},
	}
end)
script.Destroying:Connect(app.dispose)
