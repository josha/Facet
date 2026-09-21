--!strict
-- The gallery transport paints an existing picture; real headshots use the caller's native provider.
return {
	title = "Avatars",
	ledgerRows = {},
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local provider, release = ctx.app.newResourceProvider({ bind = false })
		local mode, presence, size = Compose.cell("ready"), Compose.cell("online"), Compose.cell("regular")
		local activations, attempt = Compose.cell(0), Compose.cell(1)
		local rootPath, controller, record
		local function complete()
			for _, request in provider.pendingRequests() do
				if mode:peek() == "ready" then
					provider.complete(request.key, request.generation, "rbxassetid://75342910516929")
				elseif mode:peek() == "failed" then
					provider.fail(request.key, request.generation, "No picture")
				end
			end
		end
		local function report()
			if not rootPath or not controller or not record then
				return nil
			end
			ctx.presenter.refresh()
			local base = rootPath .. "/Faces/PortraitRow/[" .. tostring(attempt:peek()) .. "]/Portrait+target/Portrait"
			return {
				portrait = record.dump(),
				rect = controller.rectOf(base),
				imageMounted = controller.rectOf(base .. "/Layers/Picture/then/Picture") ~= nil,
				activations = activations:peek(),
				providerHandles = provider.counters().handles,
			}
		end
		local function request(value)
			mode:set(value)
			attempt:set(attempt:peek() + 1)
			ctx.presenter.refresh()
			complete()
			return report()
		end
		local function section()
			Compose.cleanup(ctx.presenter.onTick(complete))
			Compose.cleanup(function()
				rootPath, controller, record = nil, nil, nil
			end)
			local root = UI.VStack("AvatarRecipe")({
				width = UI.fill(),
				gap = "m",
				UI.Text("Title")({ text = "Player identity", textSize = "heading", width = UI.fill() }),
				UI.Text("Note")({
					text = "Pictures fall back to initials. Presence keeps its meaning when the mark is hidden.",
					width = UI.fill(),
				}),
				UI.HStack("Faces")({
					gap = "m",
					wrap = true,
					UI.ForEach("PortraitRow")({
						items = function(use)
							return { use(attempt) }
						end,
						key = function(wave)
							return wave
						end,
						row = function(wave)
							return UI.Avatar("Portrait")({
								name = "Ada Quill",
								key = "portrait/" .. tostring(wave),
								provider = provider,
								presence = presence,
								controlSize = size,
								onActivate = function()
									activations:set(activations:peek() + 1)
								end,
								ref = function(value)
									record = value
								end,
							})
						end,
					}),
					UI.Avatar("Initials")({ name = "Émile Noël", backplate = true, controlSize = size }),
					UI.Avatar("Icon")({ name = "Bo Marchetti", form = "icon", controlSize = size }),
				}),
				UI.HStack("Requests")({
					gap = "s",
					wrap = true,
					UI.Button("Pending")({
						label = "Loading",
						onActivate = function()
							request("pending")
						end,
					}),
					UI.Button("Ready")({
						label = "Picture",
						onActivate = function()
							request("ready")
						end,
					}),
					UI.Button("Fail")({
						label = "Initials",
						onActivate = function()
							request("failed")
						end,
					}),
				}),
				UI.HStack("Presence")({
					gap = "s",
					wrap = true,
					UI.Button("Online")({
						label = "Online",
						onActivate = function()
							presence:set("online")
						end,
					}),
					UI.Button("Away")({
						label = "Away",
						onActivate = function()
							presence:set("away")
						end,
					}),
					UI.Button("Busy")({
						label = "Busy",
						onActivate = function()
							presence:set("busy")
						end,
					}),
					UI.Button("Offline")({
						label = "Offline",
						onActivate = function()
							presence:set("offline")
						end,
					}),
				}),
				UI.HStack("Sizes")({
					gap = "s",
					wrap = true,
					UI.Button("Compact")({
						label = "Compact",
						onActivate = function()
							size:set("compact")
						end,
					}),
					UI.Button("Regular")({
						label = "Regular",
						onActivate = function()
							size:set("regular")
						end,
					}),
					UI.Button("Large")({
						label = "Large",
						onActivate = function()
							size:set("large")
						end,
					}),
				}),
				UI.Text("Activations")({
					text = function(use)
						return `Selected {use(activations)} times`
					end,
				}),
			})
			return ctx.Facet.contribution.attach(root, {
				bindController = function(value)
					controller = value
				end,
				syncGeometry = function(_, node)
					if node then
						rootPath = node.path
					end
				end,
			})
		end
		return {
			section = section,
			screen = function()
				return UI.Screen("Avatar")({
					padding = "m",
					UI.ScrollView("Content")({ width = UI.fill(), height = UI.fill(), section() }),
				})
			end,
			report = report,
			dispose = release,
			steps = {
				pending = function()
					return request("pending")
				end,
				ready = function()
					return request("ready")
				end,
				fail = function()
					return request("failed")
				end,
				presence = function()
					presence:set(if presence:peek() == "online" then "away" else "online")
					return report()
				end,
				busy = function()
					presence:set("busy")
					return report()
				end,
				offline = function()
					presence:set("offline")
					return report()
				end,
				compact = function()
					size:set("compact")
					return report()
				end,
				large = function()
					size:set("large")
					return report()
				end,
			},
			reset = function()
				presence:set("online")
				size:set("regular")
				activations:set(0)
				request("ready")
			end,
		}
	end,
}
