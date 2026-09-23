return {
	title = "Time-based easing",
	build = function(ctx)
		local Host, UI, Compose, runtime = ctx.Host, ctx.UI, ctx.Compose, ctx.runtime
		local D, D2, C3, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Color3, ctx.types.Enum
		local reduced, race, gallery, panel = Compose.cell(false), Compose.cell(0), Compose.cell(0), Compose.cell(0)
		local counts = { race = Compose.cell(0), gallery = Compose.cell(0), panel = Compose.cell(0) }
		local stopwatch = runtime.timeline({ duration = 4, autoplay = false })
		local cooldown = runtime.tween(function(use)
			return use(race)
		end, { seconds = 0.5, ease = Compose.easing.linear })
		local chasing = runtime.spring(function(use)
			return use(race)
		end, { period = 0.5, damping = 1 })
		local panelFlight = runtime.tween(function(use)
			return use(panel)
		end, { seconds = 0.45, ease = Compose.easing.inOutQuint })
		local lanes = {}
		for _, definition in
			{
				{ "Linear", Compose.easing.linear },
				{ "Quad", Compose.easing.outQuad },
				{ "Back", Compose.easing.outBack },
				{ "Bounce", Compose.easing.outBounce },
			}
		do
			table.insert(lanes, {
				name = definition[1],
				value = runtime.tween(function(use)
					return use(gallery)
				end, { seconds = 0.4, ease = definition[2] }),
			})
		end
		local function decorative(source, destination, use)
			return if use(reduced) or (ctx.reducedMotion and use(ctx.reducedMotion))
				then use(destination)
				else use(source)
		end
		local function toggle(cell, counter)
			cell:set(1 - cell:peek())
			counter:set(counter:peek() + 1)
		end
		local function runRace()
			toggle(race, counts.race)
			stopwatch:restart()
		end
		local function launch()
			toggle(gallery, counts.gallery)
		end
		local function fly()
			toggle(panel, counts.panel)
		end
		local function label(name, text)
			return UI.Label({
				Name = name,
				Text = text,
				TextWrapped = true,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			})
		end
		local function screen()
			local children = {
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 12) }),
				label("Title", "Time curves — a duration a spring cannot promise"),
				UI.Toggle({ Name = "Reduced", label = "Reduce decorative motion", value = reduced }),
				label("RaceHeading", "Cooldown: on time versus approaching"),
				UI.Button({ Name = "RunRace", label = "Run the cooldown", onActivate = runRace }),
				UI.ProgressView({
					Name = "Cooldown",
					label = "Tween — 0.5 seconds, linear",
					value = cooldown,
					showValue = true,
				}),
				UI.ProgressView({
					Name = "Chasing",
					label = "Spring — 0.5 second response",
					value = chasing,
					showValue = true,
				}),
				label("Stopwatch", function(use)
					return string.format(
						"Elapsed %.2f s · cooldown %.0f%% · spring %.0f%%",
						use(stopwatch.elapsed),
						use(cooldown) * 100,
						use(chasing) * 100
					)
				end),
				label("GalleryHeading", "One 400 ms trip, four curves"),
				UI.Button({ Name = "Launch", label = "Launch all four", onActivate = launch }),
			}
			for _, lane in lanes do
				table.insert(
					children,
					Host.Frame({
						Name = lane.name,
						Size = D2.new(1, 0, 0, 68),
						BackgroundTransparency = 1,
						label("Caption", lane.name),
						Host.Frame({
							Name = "Track",
							Position = D2.fromOffset(0, 32),
							Size = D2.new(1, 0, 0, 32),
							BackgroundTransparency = 1,
							Host.Frame({
								Name = "Marker",
								Size = D2.fromOffset(28, 28),
								BorderSizePixel = 0,
								BackgroundColor3 = C3.fromRGB(64, 144, 255),
								Position = function(use)
									local v = decorative(lane.value, gallery, use)
									return D2.new(v, -28 * v, 0, 0)
								end,
							}),
						}),
					})
				)
			end
			table.insert(children, label("PanelHeading", "A 450 ms panel trip — position and height share one curve"))
			table.insert(children, UI.Button({ Name = "FlyPanel", label = "Fly the panel", onActivate = fly }))
			table.insert(
				children,
				Host.Frame({
					Name = "PanelLane",
					Size = D2.new(1, 0, 0, 48),
					BackgroundTransparency = 1,
					Host.Frame({
						Name = "Puck",
						Size = D2.fromOffset(32, 32),
						BackgroundColor3 = C3.fromRGB(80, 180, 160),
						BorderSizePixel = 0,
						Position = function(use)
							local v = decorative(panelFlight, panel, use)
							return D2.new(v, -32 * v, 0, 0)
						end,
					}),
				})
			)
			table.insert(
				children,
				Host.Frame({
					Name = "GrowingPanel",
					BackgroundColor3 = C3.fromRGB(80, 180, 160),
					BorderSizePixel = 0,
					Size = function(use)
						return D2.new(1, 0, 0, 64 + 64 * decorative(panelFlight, panel, use))
					end,
					label("PanelCaption", "The plate doubles its height on the same curve, in the same action."),
				})
			)
			return Host.ScrollingFrame({
				Name = "TimeCurves",
				Size = D2.fromScale(1, 1),
				AutomaticCanvasSize = E.AutomaticSize.Y,
				CanvasSize = D2.new(),
				BackgroundTransparency = 1,
				table.unpack(children),
			})
		end
		return {
			screen = screen,
			reduced = reduced,
			steps = { race = runRace, launch = launch, panel = fly },
			report = function()
				local values = {}
				for _, lane in lanes do
					values[lane.name] = lane.value:peek()
				end
				return {
					race = race:peek(),
					cooldown = cooldown:peek(),
					spring = chasing:peek(),
					elapsed = stopwatch.elapsed:peek(),
					gallery = gallery:peek(),
					curves = values,
					panel = panel:peek(),
					panelProgress = panelFlight:peek(),
					reduced = reduced:peek(),
					runs = { race = counts.race:peek(), gallery = counts.gallery:peek(), panel = counts.panel:peek() },
				}
			end,
		}
	end,
}
