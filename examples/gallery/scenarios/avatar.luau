--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type PresenceCell = typeof(require("@repo/tools/typecheck/aliases").PresenceCell)
type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
type ControlSize = typeof(require("@repo/tools/typecheck/aliases").ControlSizeValue)
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
type ExampleContext = typeof(require("@repo/examples/types").Context)
return {
	title = "Avatars",
	build = function(ctx: ExampleContext)
		local UI, Compose: ComposeModule, Host = ctx.UI, ctx.Compose, ctx.Host
		local D, D2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
		local initialSize: ControlSize? = "regular"
		local mode, presence =
			Compose.cell("ready"),
			(function(value: ("online" | "away" | "busy" | "offline" | "inExperience")?): PresenceCell
				return Compose.cell(value)
			end)("online")
		local size = Compose.cell(initialSize)
		local attempts, activations, status = Compose.cell(0), Compose.cell(0), Compose.cell("loading")
		local record: TextButton? = nil
		local function report()
			local image = record and record:FindFirstChild("Image", true)
			return {
				state = status:peek(),
				imageMounted = image ~= nil and image:IsA("GuiObject") and image.Visible,
				presence = presence:peek(),
				controlSize = size:peek(),
				activations = activations:peek(),
			}
		end
		local function request(value)
			mode:set(value)
			attempts:update(function(count: number)
				return count + 1
			end)
			return report()
		end
		local function section()
			local presenceOptions: { PickerOption } = {
				{ value = "online", label = "Online" },
				{ value = "away", label = "Away" },
				{ value = "busy", label = "Busy" },
				{ value = "offline", label = "Offline" },
				{ value = "inExperience", label = "In game" },
			}
			local sizeOptions: { PickerOption } = {
				{ value = "compact", label = "Compact" },
				{ value = "regular", label = "Regular" },
				{ value = "large", label = "Large" },
			}
			return Host.Frame "AvatarRecipe" {
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				Host.UIListLayout { Padding = D.new(0, 16), SortOrder = E.SortOrder.LayoutOrder },
				UI.Text { text = "Player identity", textRole = "title" },
				UI.Text {
					text = "Pictures fall back to initials. Presence keeps its meaning when the mark is hidden.",
				},
				Host.Frame "Faces" {
					BackgroundTransparency = 1,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					Host.UIListLayout {
						FillDirection = E.FillDirection.Horizontal,
						VerticalAlignment = E.VerticalAlignment.Center,
						Padding = D.new(0, 12),
						SortOrder = E.SortOrder.LayoutOrder,
					},
					UI.Avatar "Portrait" {
						name = "Ada Quill",
						presence = presence,
						controlSize = size,
						image = function(use: Use)
							return "portrait/" .. tostring(use(attempts))
						end,
						loader = function(_, resolve, reject)
							if mode:peek() == "ready" then
								resolve("rbxassetid://75342910516929")
							elseif mode:peek() == "failed" then
								reject("No picture")
							end
							return nil
						end,
						onStatus = function(value: "failed" | "loading" | "ready")
							status:set(value)
						end,
						onActivate = function()
							activations:update(function(value: number)
								return value + 1
							end)
						end,
						ref = function(node: TextButton)
							record = node
						end,
					},
					UI.Avatar "Initials" { name = "Émile Noël", backplate = true, controlSize = size },
					UI.Avatar "Icon" { name = "Bo Marchetti", form = "icon", controlSize = size },
					UI.Avatar "Guest" {
						name = "Guest",
						icon = "person",
						background = "success",
						presence = "inExperience",
						controlSize = size,
					},
				},
				UI.Picker "Picture" {
					label = "Picture",
					selected = mode,
					onChange = function()
						attempts:update(function(count: number)
							return count + 1
						end)
					end,
					options = {
						{ value = "pending", label = "Loading" },
						{ value = "ready", label = "Loaded" },
						{ value = "failed", label = "Failed" },
					},
				},
				UI.Picker "Presence" {
					label = "Presence",
					selected = presence,
					options = presenceOptions,
				},
				UI.Picker "Size" {
					label = "Size",
					selected = size,
					options = sizeOptions,
				},
				UI.Text {

					text = function(use: Use)
						return "Selected " .. tostring(use(activations)) .. " times"
					end,
					textRole = "caption",
				},
			}
		end
		return {
			section = section,
			screen = function()
				return UI.ScrollView "Avatar" {
					padding = 16,
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					section(),
				}
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
