--!strict
local Shared = require("./types")
local Inputs = require("./input_types")
local ControlTypes = require("./control_types")
local ComposeTypes = require("../vendor/compose/core")
local reduced = require("./motion").reduced
local decoration = require("./native_decoration")

local WIPE_STEP = 1e-3

return function(
	ctx: Shared.Context,
	UI: ControlTypes.Controls,
	button: TextButton,
	cooldown: Inputs.Cooldown?,
	charges: Shared.ValueNumber?,
	worded: (ComposeTypes.Use?) -> boolean
)
	local Compose, runtime, Host = ctx.Compose, ctx.runtime, ctx.Host
	local types = ctx.types
	local D2, V2 = types.UDim2, types.Vector2
	local readNumber = ctx.read<<number>>
	runtime.mountFragment(function()
		local children: { Shared.Child } = {}
		if cooldown then
			local pair = cooldown
			local function fraction(use: Shared.Use?): number
				local remaining = readNumber(pair.remaining, use)
				local total = readNumber(pair.total, use)
				assert(
					remaining == remaining and math.abs(remaining) < math.huge,
					"Facet Button cooldown.remaining must be finite"
				)
				assert(total > 0 and total < math.huge, "Facet Button cooldown.total must be finite and positive")
				return math.clamp(remaining / total, 0, 1)
			end
			local shown = runtime.motion(Compose.numberCodec).tween(fraction, {
				seconds = function(use: Shared.Use): number
					return ctx.metric("motion.fast", use)
				end,
				ease = ctx.motionEase("trail"),
				reducedMotion = Compose.formula(reduced(ctx)),
			})
			local function running(use: Shared.Use): boolean
				return use(shown) > 0
			end
			local labelled = Compose.formula(function(use: Shared.Use): boolean
				return worded(use)
			end)
			table.insert(
				children,
				Compose.show(labelled, function()
					local thickness = function(use: Shared.Use): number
						return math.max(3, ctx.metric("strokes.hairline", use))
					end
					local bar = Host.Frame "CooldownBar" {
						Size = function(use: Shared.Use): UDim2
							return D2.fromScale(1 - use(shown), 1)
						end,
						BorderSizePixel = 0,
					}
					bar:AddTag("facet-cooldown-bar")
					local track = Host.Frame "CooldownTrack" {
						AnchorPoint = V2.new(0.5, 1),
						Position = function(use: Shared.Use): UDim2
							return D2.new(0.5, 0, 1, -ctx.metric("space.xs", use))
						end,
						Size = function(use: Shared.Use): UDim2
							local side = math.max(ctx.metric("space.s", use), ctx.metric("radii.control", use))
							return D2.new(1, -2 * side, 0, thickness(use))
						end,
						Visible = running,
						BorderSizePixel = 0,
						Active = false,
						Selectable = false,
						bar,
					}
					track:AddTag("facet-cooldown-track")
					return track
				end, function()
					local authored = button:FindFirstChildWhichIsA("UICorner")
					local function half(right: boolean): GuiObject
						local transparency = types.NumberSequence.new({
							types.NumberSequenceKeypoint.new(0, 1),
							types.NumberSequenceKeypoint.new(0.5, 1),
							types.NumberSequenceKeypoint.new(0.5 + WIPE_STEP, 0),
							types.NumberSequenceKeypoint.new(1, 0),
						})
						local function edge(use: Shared.Use): number
							return math.max((1 - use(shown)) * 360, if right then 0 else 180)
						end
						local shade = Host.Frame "CooldownShade" {
							Position = D2.fromScale(if right then -1 else 0, 0),
							Size = D2.fromScale(2, 1),
							BorderSizePixel = 0,
							Active = false,
							Selectable = false,
							Host.UIGradient {
								Transparency = transparency,
								Rotation = edge,
							},
							if authored
								then Host.UICorner {
									CornerRadius = (
											runtime.observe(authored, "CornerRadius") :: unknown
										) :: ComposeTypes.ReadOnlyValue<UDim>,
								}
								else nil,
						}
						shade:AddTag("facet-cooldown")
						shade:AddTag("facet-scrim")
						return Host.Frame(if right then "CooldownRight" else "CooldownLeft")({
							Position = D2.fromScale(if right then 0.5 else 0, 0),
							Size = D2.fromScale(0.5, 1),
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							ClipsDescendants = true,
							Active = false,
							Selectable = false,
							Visible = function(use: Shared.Use): boolean
								return use(shown) > 0 and edge(use) < (if right then 180 else 360)
							end,
							shade,
						})
					end
					return Host.Frame "CooldownWipe" {
						Size = D2.fromScale(1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Active = false,
						Selectable = false,
						half(true),
						half(false),
					}
				end)
			)
		end
		if charges ~= nil then
			local source = charges
			local badge = UI.Badge {
				Name = "Charges",
				label = function(use: Shared.Use): string
					local count = readNumber(source, use)
					assert(
						count >= 0 and count < math.huge and count % 1 == 0,
						"Facet Button charges must be a nonnegative integer"
					)
					return tostring(count)
				end,
				controlSize = "compact",
				AnchorPoint = V2.new(0.5, 0.5),
				Position = function(use: Shared.Use): UDim2
					local inset = ctx.metric("space.xs", use)
					return D2.new(1, -inset, 0, inset)
				end,
			}
			badge:AddTag("facet-charges")
			table.insert(children, badge)
		end
		local cover = Host.Frame "Cooldown" {
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = button.ZIndex + 1,
			Active = false,
			Selectable = false,
			table.unpack(children),
		}
		return { decoration(Compose, runtime, types, button, cover) }
	end, button)
end
