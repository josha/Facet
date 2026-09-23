return {
	title = "Nested color and enabled controls",
	build = function(ctx)
		local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
		local D, D2, C3, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Color3, ctx.types.Enum
		local live, blend, engaged = Compose.cell(true), Compose.cell(35), Compose.cell(0)
		local function palette(use, role)
			local package = if ctx.theme then use(ctx.theme) else ctx.Facet.themes.neutralPackage()
			local mode = if ctx.themeMode then use(ctx.themeMode) else package.style.defaultTheme
			local chosen = package.style.themes[1]
			for _, candidate in package.style.themes do
				if candidate.name == mode then
					chosen = candidate
				end
			end
			local rgb = chosen.colors[role] or (chosen.extra or {})[role] or chosen.colors.content
			return C3.new(rgb.r, rgb.g, rgb.b)
		end
		local tint = Compose.formula(function(use)
			return palette(use, "contentSecondary"):Lerp(palette(use, "accent"), use(blend) / 100)
		end)
		local function label(name, text, color)
			return UI.Label({
				Name = name,
				Text = text,
				TextColor3 = color,
				TextWrapped = true,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				TextTransparency = function(use)
					return if use(live) then 0 else 0.5
				end,
			})
		end
		local function screen()
			local after = UI.Button({
				Name = "After",
				label = "After",
				onActivate = function()
					live:set(true)
				end,
			})
			local go = UI.Button({
				Name = "Go",
				label = "Engage",
				enabled = live,
				onActivate = function()
					engaged:set(engaged:peek() + 1)
				end,
			})
			local innerGo = UI.Button({
				Name = "InnerGo",
				label = "Engage from inner panel",
				enabled = live,
				onActivate = function()
					engaged:set(engaged:peek() + 1)
				end,
			})
			Compose.watch(function(use)
				if not use(live) and ctx.guiService then
					local focused = ctx.guiService.SelectedObject
					if
						focused == go
						or focused == innerGo
						or (focused and (focused:IsDescendantOf(go) or focused:IsDescendantOf(innerGo)))
					then
						ctx.guiService.SelectedObject = after
					end
				end
			end)
			return Host.ScrollingFrame({
				Name = "InheritedSubtree",
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				AutomaticCanvasSize = E.AutomaticSize.Y,
				CanvasSize = D2.new(),
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 12) }),
				UI.Label({ Text = "Nested color and control state", textRole = "title" }),
				UI.Toggle({ Name = "PowerToggle", label = "Panel power", value = live }),
				UI.Slider({ Name = "BlendSlider", label = "Tint", value = blend, min = 0, max = 100, step = 5 }),
				Host.Frame({
					Name = "Panel",
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 8) }),
					Host.Frame({
						Name = "Row",
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 8) }),
						label("HeroTitle", "The title and crest share this panel's live tint", tint),
						Host.ImageLabel({
							Name = "Crest",
							Image = "rbxasset://textures/ui/GuiImagePlaceholder.png",
							ImageColor3 = tint,
							Size = D2.fromOffset(40, 40),
							BackgroundTransparency = 1,
						}),
					}),
					label("Note", "This leaf keeps its own danger color", function(use)
						return palette(use, "danger")
					end),
					Host.Frame({
						Name = "Inner",
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 8) }),
						label("Sub", "The inner panel keeps its own secondary color", function(use)
							return palette(use, "contentSecondary")
						end),
						innerGo,
					}),
					go,
					label("Count", function(use)
						return "Engaged " .. use(engaged) .. " times"
					end, function(use)
						return palette(use, "contentPrimary")
					end),
				}),
				after,
				UI.Label({
					Text = "Control paint stays independent of the surrounding text tint. Power disables both controls and moves focus to After.",
					TextWrapped = true,
				}),
			})
		end
		return {
			screen = screen,
			live = live,
			blend = blend,
			engaged = engaged,
			report = function()
				return { enabled = live:peek(), blend = blend:peek() / 100, engaged = engaged:peek() }
			end,
		}
	end,
}
