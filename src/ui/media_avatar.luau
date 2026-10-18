--!strict
local Types = require("./types")
local Engine = require("./engine_types")
local Media = require("./media_types")
local ComposeTypes = require("../vendor/compose/core")
local ControlTypes = require("./control_types")
local MediaProps = require("./media_props")

return function(ctx: Types.Context, UI: ControlTypes.Controls)
	local Host, runtime, Compose = ctx.Host, ctx.runtime, ctx.Compose
	local types, read = ctx.types, ctx.read
	local E, D2, D, V2 = types.Enum, types.UDim2, types.UDim, types.Vector2
	local metric, controlSize = ctx.metric, ctx.controlSize
	local function initials(name: string?): string
		local first: string?, last: string?, count = nil, nil, 0
		for word in string.gmatch(name or "", "%S+") do
			first = first or word
			last = word
			count += 1
		end
		local function character(word: string): string
			return string.sub(word, 1, (utf8.offset(word, 2) or (#word + 1)) - 1)
		end
		return if first == nil
			then ""
			elseif count == 1 then character(first)
			else character(first) .. character(last :: string)
	end

	UI.Avatar = ctx.construct("Avatar", function(spec: MediaProps.AvatarProps): TextButton
		assert(spec.form == nil or spec.form == "standard" or spec.form == "icon", "Facet Avatar invalid form")
		local diameter = function(use: ComposeTypes.Use)
			return read(spec.diameter, use)
				or controlSize(spec.controlSize, if spec.form == "icon" then "iconSize" else "height", use)
		end
		local native = ctx.props(spec, {
			"name",
			"image",
			"userId",
			"presence",
			"presenceLabel",
			"diameter",
			"onActivate",
			"form",
			"controlSize",
			"backplate",
			"presenceMark",
			"loader",
			"onStatus",
			"resource",
			"icon",
			"background",
		}, {
			Size = function(use: ComposeTypes.Use)
				local pixels = diameter(use)
				return D2.fromOffset(pixels, pixels)
			end,
			Text = "",
			AutoButtonColor = false,
			Selectable = spec.onActivate ~= nil,
			Interactable = spec.onActivate ~= nil,
			Host.UICorner({ CornerRadius = ctx.round }),
		})
		local onActivate = spec.onActivate
		if onActivate then
			native.Activated = function()
				onActivate()
			end
		end
		assert(spec.background == nil or table.find({
			"surface",
			"surfaceStrong",
			"control",
			"contentStrong",
			"accent",
			"success",
			"warning",
			"danger",
		}, spec.background) ~= nil, "Facet Avatar background must be a palette role such as accent or success")
		assert(
			spec.icon == nil or not (spec.image or spec.userId or spec.resource),
			"Facet Avatar takes one face: image, userId, resource or icon"
		)
		local root = ctx.styled(Host.TextButton(native), "avatar")
		local function ringWidth(use: ComposeTypes.Use): number
			return 2 * metric("strokes.hairline", use)
		end
		if onActivate then
			local state = ctx.observe.GuiState(root)
			runtime.mountFragment(function()
				local ring = Host.UIStroke({
					Name = "HoverRing",
					ApplyStrokeMode = E.ApplyStrokeMode.Border,
					Thickness = ringWidth,
					Transparency = function(use: ComposeTypes.Use): number
						return if use(state) == E.GuiState.Hover then 0 else 1
					end,
				})
				ring:AddTag("facet-avatar-hover")
				return { ring }
			end, root)
		end
		if spec.backplate then
			ctx.styled(root, "accent")
		end
		if spec.background then
			root:AddTag("facet-avatar-background-" .. spec.background)
		end
		local function facts(use: ComposeTypes.Use)
			local name, presence = read(spec.name, use), read(spec.presence, use)
			assert(type(name) == "string" and name ~= "", "Facet Avatar name must be nonempty")
			assert(
				presence == nil
					or ({ online = true, away = true, busy = true, offline = true, inExperience = true })[presence],
				"Facet Avatar invalid presence"
			)
			return {
				name = name,
				presence = presence,
				label = if presence then name .. ", " .. (read(spec.presenceLabel, use) or presence) else name,
			}
		end
		runtime.decorate(root, {
			Attributes = {
				AccessibleLabel = function(use: ComposeTypes.Use): string
					return facts(use).label
				end,
			},
		})
		local pictured = Compose.cell(false)
		runtime.mount(function()
			return ctx.text({
				Name = "Initials",
				Visible = function(use: ComposeTypes.Use)
					return not use(pictured) and read(spec.icon, use) == nil
				end,
				Size = D2.fromScale(1, 1),
				Text = function(use: ComposeTypes.Use)
					return initials(facts(use).name)
				end,
				TextScaled = true,
				TextXAlignment = E.TextXAlignment.Center,
				TextYAlignment = E.TextYAlignment.Center,
				Host.UITextSizeConstraint({
					MaxTextSize = function(use: ComposeTypes.Use)
						return math.max(8, math.floor(diameter(use) * 0.4 + 0.5))
					end,
				}),
			})
		end, root)
		if spec.icon ~= nil then
			runtime.mount(function()
				return ctx.icon(function(use: ComposeTypes.Use)
					return read(spec.icon, use) or ""
				end, {
					Name = "Face",
					AnchorPoint = V2.new(0.5, 0.5),
					Position = D2.fromScale(0.5, 0.5),
					Size = D2.fromScale(0.6, 0.6),
				})
			end, root)
		end
		if spec.presence then
			runtime.mount(function()
				return Host.Frame "PresenceRing" {
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					ZIndex = 2,
					Visible = function(use: ComposeTypes.Use)
						return facts(use).presence == "inExperience"
					end,
					Host.UICorner({ CornerRadius = ctx.round }),
					ctx.styled(
						Host.UIStroke({
							ApplyStrokeMode = E.ApplyStrokeMode.Border,
							BorderStrokePosition = E.BorderStrokePosition.Inner,
							Thickness = ringWidth,
						}),
						"avatar-ring"
					),
					Host.Frame "Gap" {
						BackgroundTransparency = 1,
						AnchorPoint = V2.new(0.5, 0.5),
						Position = D2.fromScale(0.5, 0.5),
						Size = function(use: ComposeTypes.Use)
							local inset = 2 * ringWidth(use)
							return D2.new(1, -inset, 1, -inset)
						end,
						Host.UICorner({ CornerRadius = ctx.round }),
						ctx.styled(
							Host.UIStroke({
								ApplyStrokeMode = E.ApplyStrokeMode.Border,
								BorderStrokePosition = E.BorderStrokePosition.Inner,
								Thickness = ringWidth,
							}),
							"avatar-ring-gap"
						),
					},
				}
			end, root)
		end
		local image, userId, onStatus = spec.image, spec.userId, spec.onStatus
		if image or userId or spec.resource then
			runtime.mount(function()
				return UI.AsyncImage({
					imageProperties = { Host.UICorner({ CornerRadius = ctx.round }) },
					Name = "Portrait",
					loader = spec.loader,
					onStatus = function(state: Media.ImageState, failure: unknown)
						pictured:set(state == "ready")
						if onStatus then
							onStatus(state, failure)
						end
					end,
					resource = spec.resource,
					Size = D2.fromScale(1, 1),
					image = function(use: ComposeTypes.Use)
						return if image
							then read(image, use)
							else "rbxthumb://type=AvatarHeadShot&id=" .. tostring(read(userId, use)) .. "&w=150&h=150"
					end,
					placeholder = function(_state: ComposeTypes.Readable<Media.ImageState>): Instance
						return Host.Frame({ BackgroundTransparency = 1, Size = D2.fromScale(1, 1) })
					end,
					Host.UICorner({ CornerRadius = ctx.round }),
				})
			end, root)
		end
		local presence = spec.presence
		if presence and spec.presenceMark ~= false and spec.form ~= "icon" then
			local marks: { [string]: "dot" | "ring" | "square" | "dash" } =
				{ online = "dot", away = "dash", busy = "square", offline = "ring" }
			local statuses: { [string]: Media.Status } =
				{ online = "success", away = "warning", busy = "error", offline = "neutral" }
			runtime.mount(function()
				return UI.StatusIndicator "Presence" {
					diameter = 12,
					cutout = true,
					Visible = function(use: ComposeTypes.Use)
						local presence = facts(use).presence
						return presence ~= nil and presence ~= "inExperience"
					end,
					form = function(use: ComposeTypes.Use): "dot" | "ring" | "square" | "dash"
						local current = facts(use).presence
						return if current then marks[current] or "dot" else "dot"
					end,
					AnchorPoint = V2.new(1, 1),
					Position = D2.fromScale(1, 1),
					status = function(use: ComposeTypes.Use): Media.Status
						local current = read(presence, use)
						return if current then statuses[current] or "neutral" else "neutral"
					end,
				}
			end, root)
		end
		return root
	end)

	UI.AvatarGroup = ctx.construct("AvatarGroup", function(spec: MediaProps.AvatarGroupProps): Frame
		local items = Compose.formula(function(use: ComposeTypes.Use)
			local members = read(spec.items, use)
			assert(type(members) == "table", "Facet AvatarGroup items must be an array")
			local seen: { [string]: boolean }, count = {}, 0
			for key, member in members do
				assert(
					type(key) == "number" and key >= 1 and key % 1 == 0 and key <= #members,
					"Facet AvatarGroup items must be dense"
				)
				assert(
					type(member) == "table" and type(member.id) == "string" and member.id ~= "" and not seen[member.id],
					"Facet AvatarGroup needs unique nonempty ids"
				)
				assert(type(member.name) == "string" and member.name ~= "", "Facet AvatarGroup needs member names")
				seen[member.id] = true
				count += 1
			end
			assert(count == #members, "Facet AvatarGroup items must be dense")
			return members
		end)
		assert(
			spec.layout == nil or spec.layout == "stacked" or spec.layout == "spread",
			"Facet AvatarGroup invalid layout"
		)
		assert(
			spec.overflow == nil or spec.overflow == "count" or spec.overflow == "ellipsis",
			"Facet AvatarGroup invalid overflow"
		)
		assert(spec.form == nil or spec.form == "standard" or spec.form == "icon", "Facet AvatarGroup invalid form")
		assert(
			spec.onOverflow == nil or type(spec.onOverflow) == "function",
			"Facet AvatarGroup onOverflow must be a function"
		)
		local maximum = spec.max or 4
		assert(maximum >= 1 and maximum % 1 == 0, "Facet AvatarGroup max must be positive")
		local size = function(use: ComposeTypes.Use)
			return read(spec.diameter, use)
				or controlSize(spec.controlSize, if spec.form == "icon" then "iconSize" else "height", use)
		end
		local spacing = if spec.layout == "spread" then 8 else -10
		local floor = ctx.touchFloor()
		local native = ctx.props(spec, {
			"items",
			"max",
			"diameter",
			"layout",
			"onOverflow",
			"overflow",
			"controlSize",
			"form",
			"overflowLabel",
		}, {
			BackgroundTransparency = 1,
			Size = function(use: ComposeTypes.Use)
				return D2.fromOffset(0, size(use))
			end,
			AutomaticSize = E.AutomaticSize.X,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				Padding = D.new(0, spacing),
				SortOrder = E.SortOrder.LayoutOrder,
			}),
		})
		native[#native + 1] = Compose.keyed({
			from = function(use: ComposeTypes.Use)
				local items = use(items)
				local visible: { Media.AvatarMember } = {}
				for index = 1, math.min(#items, maximum) do
					table.insert(visible, items[index])
				end
				return visible
			end,
			key = function(item: Media.AvatarMember)
				return if item.resource then item.id .. "\0" .. tostring(item.resource) else item.id
			end,
			render = function(current: ComposeTypes.Readable<Media.AvatarMember>, index: ComposeTypes.Readable<number>)
				return UI.Avatar({
					resource = current:peek().resource,
					Name = function(use: ComposeTypes.Use)
						return use(current).id
					end,
					name = function(use: ComposeTypes.Use)
						return use(current).name
					end,
					image = if current:peek().icon
						then nil
						else function(use: ComposeTypes.Use)
							local item = use(current)
							return item.image
								or (
									if item.userId
										then "rbxthumb://type=AvatarHeadShot&id=" .. tostring(item.userId) .. "&w=150&h=150"
										else ""
								)
						end,
					presence = function(use: ComposeTypes.Use): Media.Presence?
						return use(current).presence :: Media.Presence?
					end,
					icon = if current:peek().icon
						then function(use: ComposeTypes.Use): string?
							return use(current).icon
						end
						else nil,
					diameter = size,
					presenceMark = spec.layout == "spread",
					LayoutOrder = index,
				})
			end,
		})
		native[#native + 1] = Compose.show(function(use: ComposeTypes.Use)
			return #use(items) > maximum
		end, function()
			return ctx.styled(
				Host.TextButton "Overflow" {
					Attributes = {
						AccessibleLabel = (function(use: ComposeTypes.Use): string
							local label = read(spec.overflowLabel, use)
							assert(
								label == nil or type(label) == "string",
								"Facet AvatarGroup overflowLabel must be a string"
							)
							return label or tostring(#use(items) - maximum) .. " more players"
						end) :: Engine.Value<Engine.AttributeValue?>,
					},
					Size = function(use: ComposeTypes.Use)
						local pixels = size(use)
						return D2.fromOffset(pixels, pixels)
					end,
					LayoutOrder = maximum + 2,
					Text = function(use: ComposeTypes.Use)
						return if spec.overflow == "ellipsis" then "…" else "+" .. tostring(#use(items) - maximum)
					end,
					TextScaled = true,
					Selectable = spec.onOverflow ~= nil,
					AutoButtonColor = false,
					Activated = function()
						local onOverflow = spec.onOverflow
						if onOverflow then
							onOverflow()
						end
					end,
					Host.UICorner({ CornerRadius = ctx.round }),
					Host.UITextSizeConstraint {
						MaxTextSize = function(use: ComposeTypes.Use): number
							return math.max(8, math.floor(size(use) * 0.4 + 0.5))
						end,
					},
					Host.UISizeConstraint({
						MinSize = function(use: ComposeTypes.Use): Vector2
							local minimum = floor(use)
							return V2.new(minimum, minimum)
						end,
					}),
				},
				"button"
			)
		end)
		if spacing < 0 then
			native[#native + 1] = Compose.show(function(use: ComposeTypes.Use)
				return #use(items) > maximum
			end, function()
				return Host.Frame "OverflowGap" {
					BackgroundTransparency = 1,
					LayoutOrder = maximum + 1,
					Size = D2.fromOffset(4 - 2 * spacing, 0),
				}
			end)
		end
		local group = Host.Frame(native)
		if spec.layout ~= "spread" then
			ctx.styled(group, "avatar-stack")
		end
		return group
	end)
end
