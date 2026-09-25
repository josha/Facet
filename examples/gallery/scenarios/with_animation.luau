return {
	title = "State-driven motion",
	build = function(ctx)
		local Host, UI, Compose, runtime = ctx.Host, ctx.UI, ctx.Compose, ctx.runtime
		local D, D2, V2, C3, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Color3, ctx.types.Enum
		local target, reduced, runs = Compose.cell(0), Compose.cell(false), Compose.cell(0)
		local effectiveReduced = Compose.formula(function(use)
			return use(reduced) or (ctx.reducedMotion ~= nil and use(ctx.reducedMotion))
		end)
		UI = ctx.Facet.controls(runtime, {
			types = ctx.types,
			theme = ctx.theme,
			viewport = ctx.viewport,
			guiService = ctx.guiService,
			inputParent = ctx.inputTarget,
			reducedMotion = effectiveReduced,
		})
		local order = Compose.cell({ "Alpha", "Bravo", "Charlie" })
		local flight = runtime.spring(function(use)
			return use(target)
		end, { period = 0.5, damping = 0.8 })
		local amount = Compose.formula(function(use)
			return if use(effectiveReduced) then use(target) else use(flight)
		end)
		local charge = runtime.tween(function(use)
			return use(target)
		end, { seconds = 1.2, ease = Compose.easing.linear })
		local function animate()
			target:set(1 - target:peek())
			runs:set(runs:peek() + 1)
			local next = table.clone(order:peek())
			next[1], next[3] = next[3], next[1]
			order:set(next)
		end
		local function color(use, role)
			local package = if ctx.theme then use(ctx.theme) else ctx.Facet.themes.neutralPackage()
			local mode = if ctx.themeMode then use(ctx.themeMode) else package.style.defaultTheme
			local palette = package.style.themes[1]
			for _, candidate in package.style.themes do
				if candidate.name == mode then
					palette = candidate
				end
			end
			local rgb = palette.colors[role] or (palette.extra or {})[role] or palette.colors.accent
			return C3.new(rgb.r, rgb.g, rgb.b)
		end
		local function label(name, text)
			return UI.Text({
				Name = name,
				text = text,
				TextWrapped = true,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			})
		end
		local function screen()
			return Host.ScrollingFrame "StateMotion" {
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				AutomaticCanvasSize = E.AutomaticSize.Y,
				CanvasSize = D2.new(),
				Host.UIPadding({
					PaddingLeft = D.new(0, 12),
					PaddingRight = D.new(0, 12),
					PaddingBottom = D.new(0, 12),
				}),
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 12) }),
				label("Title", "One action, one shared motion"),
				UI.Toggle "Reduced" { label = "Reduce decorative motion", value = reduced },
				UI.Button "Animate" { label = "Animate", onActivate = animate },
				label(
					"Decorative",
					"The puck changes color and position; the card grows; the badge fades, shrinks and turns."
				),
				Host.Frame "PuckLane" {
					Size = D2.new(1, 0, 0, 56),
					BackgroundTransparency = 1,
					Host.Frame "Puck" {
						Size = D2.fromOffset(40, 40),
						BorderSizePixel = 0,
						Position = function(use)
							local v = use(amount)
							return D2.new(v, -40 * v, 0, 8)
						end,
						BackgroundColor3 = function(use)
							return color(use, "contentSecondary"):Lerp(
								color(use, "accent"),
								math.clamp(use(amount), 0, 1)
							)
						end,
						Host.UICorner({ CornerRadius = D.new(1, 0) }),
					},
				},
				Host.Frame "GrowingCard" {
					BorderSizePixel = 0,
					Size = function(use)
						return D2.new(1, 0, 0, 64 + 64 * use(amount))
					end,
					BackgroundColor3 = function(use)
						return color(use, "accent")
					end,
					Host.Frame "Pip" {
						Size = D2.fromOffset(16, 16),
						Position = D2.fromOffset(12, 12),
						BackgroundColor3 = C3.new(1, 1, 1),
						BorderSizePixel = 0,
					},
					UI.Text "CardCaption" {
						text = "The card grows; this pip keeps its size.",
						Position = D2.fromOffset(40, 8),
						Size = D2.new(1, -48, 1, -16),
						TextWrapped = true,
					},
				},
				Host.Frame "EffectsLane" {
					Size = D2.new(1, 0, 0, 100),
					BackgroundTransparency = 1,
					Host.CanvasGroup "Badge" {
						Position = D2.fromScale(0.5, 0.5),
						AnchorPoint = V2.new(0.5, 0.5),
						Size = function(use)
							local side = 76 - 28 * use(amount)
							return D2.fromOffset(side, side)
						end,
						Rotation = function(use)
							return 90 * use(amount)
						end,
						GroupTransparency = function(use)
							return 0.65 * math.clamp(use(amount), 0, 1)
						end,
						BackgroundColor3 = function(use)
							return color(use, "accent")
						end,
						UI.Text({ text = "GO", Size = D2.fromScale(1, 1), TextXAlignment = E.TextXAlignment.Center }),
					},
				},
				Host.CanvasGroup "WrappedFade" {
					Size = D2.new(1, 0, 0, 84),
					BackgroundTransparency = 1,
					GroupTransparency = function(use)
						return 0.65 * math.clamp(use(amount), 0, 1)
					end,
					Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 8) }),
					label("FadedLabel", "A group fades its label and controls together"),
					UI.Button "Locked" { label = "Locked", enabled = false },
				},
				Host.Frame "Details" {
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Compose.presence(function(use)
						return use(target) == 1
					end, function(phase)
						local arrived = Compose.cell(false)
						local opacity = runtime.tween(function(use)
							return if use(arrived) and not use(phase.exiting) then 1 else 0
						end, { seconds = 0.2 })
						arrived:set(true)
						return Host.CanvasGroup "DetailArrival" {
							BackgroundTransparency = 1,
							Size = D2.new(1, 0, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
							GroupTransparency = function(use)
								return if use(effectiveReduced) then 0 else 1 - use(opacity)
							end,
							label(
								"DetailPanel",
								"Detail panel — the same action reveals this information and reverses the cards below."
							),
						}
					end, {
						exit = function()
							return {
								completed = if effectiveReduced:peek()
									then Compose.cell(true)
									else runtime.timeline({ duration = 0.2 }).completed,
							}
						end,
					}),
				},
				Host.Frame "Cards" {
					Size = D2.new(1, 0, 0, 136),
					BackgroundTransparency = 1,
					Compose.OrderedCollection({
						from = order,
						key = function(name)
							return name
						end,
						render = function(current, placement)
							local origin = if current:peek() == "Alpha"
								then 0
								elseif current:peek() == "Bravo" then 1
								else 2
							return UI.Button({
								Name = current:peek(),
								label = current,
								LayoutOrder = function(use)
									return use(placement).index
								end,
								Size = D2.new(1, 0, 0, 40),
								Position = function(use)
									return D2.fromOffset(0, (origin + (2 - 2 * origin) * use(amount)) * 48)
								end,
							})
						end,
					}),
				},
				label(
					"Informational",
					"Charge keeps moving to its known destination when decorative motion is reduced."
				),
				UI.ProgressView "Charge" { label = "Charge", value = charge, showValue = true },
				UI.ProgressView "Busy" { label = "No terminus" },
				UI.ProgressView "Spinner" { label = "Spinner", presentation = "spinner" },
				label("Status", function(use)
					return "Animations: " .. use(runs)
				end),
			}
		end
		return {
			screen = screen,
			steps = { run = animate, reverse = animate },
			reduced = reduced,
			report = function()
				return {
					target = target:peek(),
					runs = runs:peek(),
					progress = amount:peek(),
					charge = charge:peek(),
					order = order:peek(),
					reduced = reduced:peek(),
				}
			end,
		}
	end,
}
