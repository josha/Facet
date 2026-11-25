--!strict
local Shared = require("./types")
local Inputs = require("./input_types")
local ComposeTypes = require("../vendor/compose/core")
local reduced = require("./motion").reduced
local decoration = require("./native_decoration")

return function(ctx: Shared.Context, button: TextButton, cooldown: Inputs.Cooldown?, charges: Shared.ValueNumber?)
	local Compose, runtime, Host = ctx.Compose, ctx.runtime, ctx.Host
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
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
			local authored = button:FindFirstChildWhichIsA("UICorner")
			local shade = Host.Frame "CooldownShade" {
				AnchorPoint = V2.new(0, 1),
				Position = D2.fromScale(0, 1),
				Size = function(use: Shared.Use): UDim2
					local level = use(shown)
					return D2.fromScale(1, if level > 0 then 1 / level else 1)
				end,
				BorderSizePixel = 0,
				Active = false,
				Selectable = false,
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
			table.insert(
				children,
				Host.Frame "CooldownSweep" {
					AnchorPoint = V2.new(0, 1),
					Position = D2.fromScale(0, 1),
					Size = function(use: Shared.Use): UDim2
						return D2.fromScale(1, use(shown))
					end,
					Visible = function(use: Shared.Use): boolean
						return use(shown) > 0
					end,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ClipsDescendants = true,
					ZIndex = button.ZIndex + 1,
					Active = false,
					Selectable = false,
					shade,
				}
			)
		end
		if charges ~= nil then
			local source = charges
			local label = ctx.text({
				Name = "Charges",
				AnchorPoint = V2.new(1, 1),
				Position = D2.new(1, -4, 1, -4),
				AutomaticSize = E.AutomaticSize.XY,
				Text = function(use: Shared.Use): string
					local count = readNumber(source, use)
					assert(
						count >= 0 and count < math.huge and count % 1 == 0,
						"Facet Button charges must be a nonnegative integer"
					)
					return tostring(count)
				end,
				ZIndex = button.ZIndex + 2,
			})
			ctx.textRole(label, "caption")
			label:AddTag("facet-charges")
			table.insert(children, label)
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
		return { decoration(Compose, runtime, ctx.types, button, cover) }
	end, button)
end
