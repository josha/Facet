--!strict
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type NumberCell = typeof(require("@repo/tools/typecheck/example_shapes").numberCell(nil :: any))
type ExampleContext = typeof(require("@repo/examples/types")(nil :: any))
return {
	title = "Time-based easing",
	build = function(ctx: ExampleContext)
		local Host, UI, Compose: typeof(require("@repo/src/vendor/compose/core")), runtime =
			ctx.Host, ctx.UI, ctx.Compose, ctx.runtime
		local D, D2, C3, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Color3, ctx.types.Enum
		local reduced, race, gallery, panel = Compose.cell(false), Compose.cell(0), Compose.cell(0), Compose.cell(0)
		local counts = { race = Compose.cell(0), gallery = Compose.cell(0), panel = Compose.cell(0) }
		local stopwatch = runtime.timeline({ duration = 4, autoplay = false })
		local cooldown = runtime.tween(function(use: Use)
			return use(race)
		end, { seconds = 0.5, ease = Compose.easing.linear })
		local chasing = runtime.spring(function(use: Use)
			return use(race)
		end, { period = 0.5, damping = 1 })
		local panelFlight = runtime.tween(function(use: Use)
			return use(panel)
		end, { seconds = 0.45, ease = Compose.easing.inOutQuint })
		local lanes = {}
		for _, definition in
			{
				{ name = "Linear", ease = Compose.easing.linear },
				{ name = "Quad", ease = Compose.easing.outQuad },
				{ name = "Back", ease = Compose.easing.outBack },
				{ name = "Bounce", ease = Compose.easing.outBounce },
			}
		do
			table.insert(lanes, {
				name = definition.name,
				value = runtime.tween(function(use: Use)
					return use(gallery)
				end, { seconds = 0.4, ease = definition.ease }),
			})
		end
		local function decorative(source: Readable<number>, destination: Readable<number>, use: Use): number
			return if use(reduced) or (ctx.reducedMotion and use(ctx.reducedMotion))
				then use(destination)
				else use(source)
		end
		local function toggle(cell: NumberCell, counter: NumberCell)
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
		local function label(name: string, text: string | ((Use) -> string)): GuiObject
			return UI.Text({
				Name = name,
				text = text,
				TextWrapped = true,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			})
		end
		local function screen()
			local children = {
				label("Title", "Time curves — a duration a spring cannot promise"),
				UI.Toggle "Reduced" { label = "Reduce decorative motion", value = reduced },
				label("RaceHeading", "Cooldown: on time versus approaching"),
				UI.Button "RunRace" { label = "Run the cooldown", onActivate = runRace },
				UI.ProgressView "Cooldown" {
					label = "Tween — 0.5 seconds, linear",
					value = cooldown,
					showValue = true,
				},
				UI.ProgressView "Chasing" {
					label = "Spring — 0.5 second response",
					value = chasing,
					showValue = true,
				},
				label("Stopwatch", function(use: Use)
					return string.format(
						"Elapsed %.2f s · cooldown %.0f%% · spring %.0f%%",
						use(stopwatch.elapsed),
						use(cooldown) * 100,
						use(chasing) * 100
					)
				end),
				label("GalleryHeading", "One 400 ms trip, four curves"),
				UI.Button "Launch" { label = "Launch all four", onActivate = launch },
			}
			for _, lane in lanes do
				table.insert(
					children,
					Host.Frame({
						Name = lane.name,
						Size = D2.new(1, 0, 0, 68),
						BackgroundTransparency = 1,
						label("Caption", lane.name) :: unknown,
						Host.Frame "Track" {
							Position = D2.fromOffset(0, 32),
							Size = D2.new(1, 0, 0, 32),
							BackgroundTransparency = 1,
							Host.Frame "Marker" {
								Size = D2.fromOffset(28, 28),
								BorderSizePixel = 0,
								BackgroundColor3 = C3.fromRGB(64, 144, 255),
								Position = function(use: Use)
									local v = decorative(lane.value, gallery, use)
									return D2.new(v, -28 * v, 0, 0)
								end,
							},
						},
					})
				)
			end
			table.insert(children, label("PanelHeading", "A 450 ms panel trip — position and height share one curve"))
			table.insert(children, UI.Button "FlyPanel" { label = "Fly the panel", onActivate = fly })
			table.insert(
				children,
				Host.Frame "PanelLane" {
					Size = D2.new(1, 0, 0, 48),
					BackgroundTransparency = 1,
					Host.Frame "Puck" {
						Size = D2.fromOffset(32, 32),
						BackgroundColor3 = C3.fromRGB(80, 180, 160),
						BorderSizePixel = 0,
						Position = function(use: Use)
							local v = decorative(panelFlight, panel, use)
							return D2.new(v, -32 * v, 0, 0)
						end,
					},
				}
			)
			table.insert(
				children,
				Host.Frame "GrowingPanel" {
					BackgroundColor3 = C3.fromRGB(80, 180, 160),
					BorderSizePixel = 0,
					Size = function(use: Use)
						return D2.new(1, 0, 0, 64 + 64 * decorative(panelFlight, panel, use))
					end,
					label("PanelCaption", "The plate doubles its height on the same curve, in the same action."),
				}
			)
			return UI.ScrollView "TimeCurves" {
				padding = 16,
				gap = 12,
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				table.unpack((children :: unknown) :: { unknown }),
			}
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
