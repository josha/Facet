--!strict
return {
	title = "Avatars",
	build = function(ctx)
		local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
		local D, D2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
		local mode, presence, size = Compose.cell("ready"), Compose.cell("online"), Compose.cell("regular")
		local attempts, activations, status = Compose.cell(0), Compose.cell(0), Compose.cell("loading")
		local record
		local function report()
			local image = record and record:FindFirstChild("Image", true)
			return {
				state = status:peek(),
				imageMounted = image ~= nil and image.Visible,
				presence = presence:peek(),
				controlSize = size:peek(),
				activations = activations:peek(),
			}
		end
		local function request(value)
			mode:set(value)
			attempts:update(function(count)
				return count + 1
			end)
			return report()
		end
		local function row(name, children)
			local p = {
				Name = name,
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = E.FillDirection.Horizontal,
					Wraps = true,
					Padding = D.new(0, 8),
					SortOrder = E.SortOrder.LayoutOrder,
				}),
			}
			for _, child in children do
				table.insert(p, child)
			end
			return Host.Frame(p)
		end
		local function section()
			local choices = {}
			for _, state in { "online", "away", "busy", "offline" } do
				table.insert(
					choices,
					UI.Button({
						label = state,
						onActivate = function()
							presence:set(state)
						end,
					})
				)
			end
			local sizes = {}
			for _, rung in { "compact", "regular", "large" } do
				table.insert(
					sizes,
					UI.Button({
						label = rung,
						onActivate = function()
							size:set(rung)
						end,
					})
				)
			end
			return Host.Frame({
				Name = "AvatarRecipe",
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				Host.UIListLayout({ Padding = D.new(0, 16), SortOrder = E.SortOrder.LayoutOrder }),
				UI.Label({ text = "Player identity", textRole = "title" }),
				UI.Label({

					text = "Pictures fall back to initials. Presence keeps its meaning when the mark is hidden.",
				}),
				row("Faces", {
					UI.Avatar({
						Name = "Portrait",
						name = "Ada Quill",
						presence = presence,
						controlSize = size,
						image = function(use)
							return "portrait/" .. tostring(use(attempts))
						end,
						loader = function(_, resolve, reject)
							if mode:peek() == "ready" then
								resolve("rbxassetid://75342910516929")
							elseif mode:peek() == "failed" then
								reject("No picture")
							end
						end,
						onStatus = function(value)
							status:set(value)
						end,
						onActivate = function()
							activations:update(function(value)
								return value + 1
							end)
						end,
						ref = function(node)
							record = node
						end,
					}),
					UI.Avatar({ Name = "Initials", name = "Émile Noël", backplate = true, controlSize = size }),
					UI.Avatar({ Name = "Icon", name = "Bo Marchetti", form = "icon", controlSize = size }),
				}),
				row("Requests", {
					UI.Button({
						Name = "Pending",
						label = "Loading",
						onActivate = function()
							request("pending")
						end,
					}),
					UI.Button({
						Name = "Ready",
						label = "Picture",
						onActivate = function()
							request("ready")
						end,
					}),
					UI.Button({
						Name = "Fail",
						label = "Initials",
						onActivate = function()
							request("failed")
						end,
					}),
				}),
				row("Presence", choices),
				row("Sizes", sizes),
				UI.Label({

					text = function(use)
						return "Selected " .. tostring(use(activations)) .. " times"
					end,
				}),
			})
		end
		return {
			section = section,
			screen = function()
				return Host.ScrollingFrame({
					Name = "Avatar",
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					CanvasSize = D2.new(),
					AutomaticCanvasSize = E.AutomaticSize.Y,
					section(),
				})
			end,
			report = report,
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
