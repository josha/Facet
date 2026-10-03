--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type RowAction = typeof(require("@repo/tools/typecheck/aliases").RowAction)
type MenuItem = typeof(require("@repo/tools/typecheck/aliases").MenuItem)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Context = typeof(require("@repo/examples/types").Context)
return function(ctx: Context)
	local Compose: ComposeModule, Host, UI, runtime, model = ctx.Compose, ctx.Host, ctx.UI, ctx.runtime, ctx.model
	local D2, V2, C3, E = ctx.D2, ctx.V2, ctx.C3, ctx.E
	local words, quiet, button = ctx.words, ctx.quiet, ctx.button
	local chat, promptUsed = model.chat, model.chatPromptUsed
	local extent = Compose.cell(V2.new(920, 560))
	local width = Compose.formula(function(use: Use)
		return math.min(960, math.max(0, use(extent).X - 24))
	end)
	local short = Compose.formula(function(use: Use)
		return use(extent).Y < 360
	end)
	local measured = Compose.cell({})
	local status = Compose.cell({
		mode = "windowed" :: "windowed",
		direction = "vertical" :: "vertical",
		total = 0,
		retained = 0,
		first = 0,
		last = 0,
		firstRow = 0,
		lastRow = 0,
		rowCount = 0,
		extent = 0,
		following = false,
		measured = 0,
	})
	local function prompt(value)
		promptUsed:set(true)
		chat.draft:set(value)
	end
	local function sparkle(size: number)
		local path = Host.Path2D "AssistantMark" {
			Thickness = math.max(2, math.floor(size / 10)),
			Closed = true,
			Color3 = function(use: Use)
				return if use(model.dark) then C3.fromRGB(192, 172, 255) else C3.fromRGB(91, 70, 140)
			end,
		}
		local points = {}
		for corner = 0, 7 do
			local radius = if corner % 2 == 0 then 0.46 else 0.12
			local angle = math.rad(-90 + corner * 45)
			table.insert(
				points,
				ctx.types.Path2DControlPoint.new(
					D2.fromScale(0.5 + math.cos(angle) * radius, 0.5 + math.sin(angle) * radius)
				)
			)
		end
		path:SetControlPoints(points)
		return Host.Frame "AssistantIcon" {
			Size = D2.fromOffset(size, size),
			BackgroundTransparency = 1,
			path :: unknown,
		}
	end
	local motion = UI.environment().reducedMotion
	local function reduced(use: Use)
		return use(motion)
	end
	local spin = runtime.timeline({ duration = 1.6, repeats = math.huge, autoplay = false })
	Compose.watch(function(use: Use)
		if use(chat.streaming) and not reduced(use) then
			spin:play()
		else
			spin:pause()
		end
	end)
	local textService = (function()
		local ok, service = pcall(function()
			return (game :: any):GetService("TextService")
		end)
		return if ok then service else nil
	end)()
	local function measuredHeight(label: TextLabel)
		if textService == nil then
			return label
		end
		local observation = assert(runtime.host.observation)
		local serial = 0
		local function refresh()
			local text = label.ContentText
			local widthNow = label.AbsoluteSize.X
			if text == "" or widthNow <= 0 then
				return
			end
			serial += 1
			local ticket = serial
			task.spawn(function()
				local size = label:GetStyled("TextSize")
				local params = Instance.new("GetTextBoundsParams")
				params.Text = text
				params.Font = label:GetStyled("FontFace")
				params.Size = size
				params.Width = widthNow
				local ok, bounds = pcall(function()
					return textService:GetTextBoundsAsync(params)
				end)
				if not ok or ticket ~= serial or label.Parent == nil then
					return
				end
				local lines = math.max(1, math.round(bounds.Y / size))
				local height = size + (lines - 1) * size * label:GetStyled("LineHeight")
				if height > 0 then
					label.AutomaticSize = E.AutomaticSize.None
					label.Size = D2.new(1, 0, 0, math.round(height))
				end
			end)
		end
		Compose.cleanup(observation.observeProperty(label, "ContentText", refresh))
		Compose.cleanup(observation.observeProperty(label, "AbsoluteSize", refresh))
		refresh()
		return label
	end
	local function message(current)
		local id = current:peek().id
		local isUser = current:peek().role == "user"
		local streamingHere = Compose.formula(function(use: Use)
			return use(chat.active) == id
		end)
		local function content(props: { [any]: unknown })
			props.Visible = function(use: Use)
				return use(current).content ~= ""
			end
			return words("Message", function(use: Use)
				return use(current).content
			end, "body", props)
		end
		local rowFrame
		if isUser then
			local card = UI.VStack("Message_" .. id)({
				padding = 14,
				ctx.rounded(18) :: unknown,
				content({
					Size = D2.new(0, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.XY,
					Host.UISizeConstraint({
						MaxSize = function(use: Use)
							return V2.new(math.max(96, math.floor(use(width) * 0.78) - 32), math.huge)
						end,
					}),
				}),
			})
			card:AddTag("facet-track")
			rowFrame =
				UI.VStack("MessageRow_" .. id)({ width = "fill" :: "fill", align = "end" :: "end", card :: unknown })
		else
			local icon = sparkle(22)
			runtime.decorate(icon, {
				Rotation = function(use: Use)
					return if use(streamingHere) and not reduced(use) then use(spin.progress) * 360 else 0
				end,
			})
			rowFrame = UI.HStack("MessageRow_" .. id)({
				width = "fill" :: "fill",
				gap = 12,
				icon :: unknown,
				UI.VStack("Message_" .. id)({
					gap = "s",
					Size = D2.new(0, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					UI.fill() :: unknown,
					Compose.show(function(use: Use)
						return use(current).content == ""
					end, function()
						return UI.ProgressView "Thinking" {
							presentation = "spinner" :: "spinner",
							label = "Thinking",
							diameter = 18,
						}
					end),
					measuredHeight(content({})),
					Compose.show(function(use: Use)
						return use(current).content ~= "" and not use(streamingHere)
					end, function()
						return UI.HStack "MessageTools" {
							gap = "s",
							align = "center" :: "center",
							UI.Vote "Feedback" {
								value = function(use: Use)
									return use(chat.feedback)[id] or "none"
								end,
								onChange = function(nextValue)
									chat.rate(id, nextValue)
								end,
								controlSize = "compact" :: "compact",
							} :: unknown,
							button("Retry", "Retry", function()
								chat.retry(id)
							end, { appearance = "utility", controlSize = "compact" :: "compact" }),
						}
					end),
				}),
			})
		end
		local observation = assert(runtime.host.observation)
		local key = tostring(id)
		local function updateSize()
			local height = (observation.readProperty(rowFrame, "AbsoluteSize") :: Vector2).Y
			if height > 0 and measured:peek()[key] ~= height then
				measured:update(function(currentSizes)
					local nextSizes = table.clone(currentSizes)
					nextSizes[key] = height
					return nextSizes
				end)
			end
		end
		Compose.cleanup(observation.observeProperty(rowFrame, "AbsoluteSize", updateSize))
		updateSize()
		local trailing: { RowAction } = {
			{
				id = "DeleteMessage",
				label = "Delete",
				role = "destructive" :: "destructive",
				onActivate = function()
					model.deleteMessage(id)
				end,
			},
		}
		if isUser then
			table.insert(trailing, 1, {
				id = "EditMessage",
				label = "Edit",
				onActivate = function()
					chat.edit(id)
				end,
			})
		end
		return UI.RowActions({
			Name = "MessageActions_" .. id,
			Size = D2.fromScale(1, 1),
			content = function(): GuiObject
				return rowFrame :: GuiObject
			end,
			trailing = trailing,
		})
	end
	local conversationItems = {
		{
			id = "Suggest",
			label = "Suggest",
			children = {
				{
					id = "FindGame",
					label = "Find a game",
					onSelect = function()
						prompt("What game should I play with friends?")
					end,
				},
				{
					id = "BuildSomething",
					label = "Build something",
					onSelect = function()
						prompt("Help me build a game browser")
					end,
				},
			},
		} :: MenuItem,
		{
			id = "FollowReplies",
			label = "Follow replies",
			checked = model.followChat,
			onChange = function(value)
				model.followChat:set(value)
			end,
		} :: MenuItem,
		{ divider = true } :: MenuItem,
		{ id = "Clear", label = "Clear conversation", role = "destructive" :: "destructive", onSelect = chat.clear } :: MenuItem,
	}
	local findGame = button("FindGame", "Find a game", function()
		prompt("What game should I play with friends?")
	end, { TextWrapped = true })
	local buildSomething = button("BuildSomething", "Build something", function()
		prompt("Help me build a game browser")
	end, { TextWrapped = true })
	local send = UI.Button "Send" {
		name = function(use: Use)
			return if use(chat.streaming) then "Stop" else "Send"
		end,
		icon = function(use: Use)
			return if use(chat.streaming) then "close" else "chevron.up"
		end,
		shape = "circle" :: "circle",
		appearance = function(use: Use)
			return if use(chat.streaming) or use(chat.draft):match("%S") then "emphasis" else "soft"
		end,
		onActivate = function()
			if chat.streaming:peek() then
				chat.stop()
			else
				chat.send()
			end
		end,
	}
	local welcome = Compose.show(function(use: Use)
		return #use(chat.messages) == 0
	end, function()
		local entered = Compose.cell(0)
		local motion = runtime.tween(function(use: Use)
			return use(entered)
		end, { seconds = 0.24 })
		entered:set(1)
		local function reveal(use: Use)
			return if reduced(use) then 1 else math.clamp(use(motion), 0, 1)
		end
		return Host.CanvasGroup "Welcome" {
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			GroupTransparency = function(use: Use)
				return 1 - reveal(use)
			end,
			UI.VStack "WelcomeContent" {
				gap = "s",
				AnchorPoint = V2.new(0.5, 0.5),
				Size = D2.new(1, -24, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				Position = function(use: Use)
					return D2.new(0.5, 0, 0.5, (1 - reveal(use)) * 12)
				end,
				Compose.show(function(use: Use)
					return not use(short)
				end, function()
					return sparkle(40)
				end) :: unknown,
				UI.Text "WelcomeQuestion" {
					text = "What are you working on?",
					textRole = "title" :: "title",
					TextSize = function(use: Use)
						return if use(short) then 20 else 28
					end,
					TextWrapped = true,
					TextYAlignment = E.TextYAlignment.Top,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
				},
				Compose.show(function(use: Use)
					return not use(short)
				end, function()
					return quiet("Hint", "Ask a question or try a prompt below.", "body")
				end),
			},
		}
	end)
	local body = UI.VStack "ChatBody" {
		width = "fill" :: "fill",
		height = "fill" :: "fill",
		align = "center" :: "center",
		UI.VStack "ConversationColumn" {
			width = "fill" :: "fill",
			height = "fill" :: "fill",
			gap = "s",
			Host.UISizeConstraint({ MaxSize = V2.new(960, math.huge) }) :: unknown,
			UI.Notice "Disclaimer" {
				placement = "affixed" :: "affixed",
				message = "Simulated responses · No messages leave this device",
				Visible = function(use: Use)
					return not use(short)
				end,
			},
			UI.HStack "ChatToolbar" {
				width = "fill" :: "fill",
				gap = "s",
				align = "center" :: "center",
				quiet(
					"Status",
					function(use: Use)
						local count = #use(chat.messages)
						return if use(chat.streaming)
							then "Writing a reply…"
							elseif count == 0 then "New conversation"
							else `{count} messages`
					end,
					"label",
					{
						Size = D2.fromOffset(0, 22),
						AutomaticSize = E.AutomaticSize.None,
						TextWrapped = false,
						TextTruncate = E.TextTruncate.AtEnd,
						UI.fill(),
					}
				) :: unknown,
				button("NewChat", "New chat", function()
					local kept = chat.draft:peek()
					chat.clear()
					chat.draft:set(kept)
				end, {
					icon = "edit",
					appearance = "utility",
					Size = D2.fromOffset(0, 40),
					AutomaticSize = E.AutomaticSize.X,
					Visible = function(use: Use)
						return #use(chat.messages) > 0
					end,
				}),
				UI.Menu {
					trigger = button("ConversationMenu", "Conversation", function() end, {
						compactLabel = "Thread",
						Size = D2.fromOffset(146, 40),
						AutomaticSize = E.AutomaticSize.None,
					}),
					items = conversationItems,
					width = { type = "hug" :: "hug", min = 220, max = 320 },
				},
			},
			UI.ZStack "Thread" {
				ClipsDescendants = true,
				Size = D2.fromScale(1, 0),
				AutomaticSize = E.AutomaticSize.None,
				UI.fill() :: unknown,
				Compose.keyed({
					from = function(use: Use)
						return { use(model.followChat) }
					end,
					key = function(value)
						return tostring(value)
					end,
					render = function(current): GuiObject
						return ctx.collection("VirtualList", {
							Name = "Messages",
							from = chat.messages,
							key = "id",
							render = message,
							itemSize = 110,
							gap = 12,
							measured = measured,
							follow = if current:peek() then "end" else "none",
							followThreshold = 48,
							status = status,
							Size = D2.fromScale(1, 1),
							BackgroundTransparency = 1,
							ScrollBarThickness = 5,
						}, model.chatScroll)
					end,
				}),
				welcome,
			},
			UI.VStack "Composer" {
				width = "fill" :: "fill",
				gap = "s",
				UI.Grid "Suggestions" {
					columns = function(use: Use)
						return if use(width) < 420 then 1 else 2
					end,
					gap = "s",
					cellHeight = 44,
					Visible = function(use: Use)
						return not use(short) and #use(chat.messages) == 0
					end,
					findGame :: unknown,
					buildSomething,
				} :: unknown,
				UI.TextInput "Draft" {
					value = chat.draft,
					placeholder = "Reply to Assistant…",
					corners = "pill" :: "pill",
					trailing = send,
					onChange = function(value)
						chat.draft:set(value)
					end,
					onCommit = function(_, reason)
						if reason == "submit" then
							chat.send()
						end
					end,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
				},
			},
		},
	}
	ctx.measure(body, extent)
	local callout = UI.Callout "PromptHint" {
		anchor = findGame,
		edge = "top" :: "top",
		align = "leading" :: "leading",
		featureUsed = promptUsed,
		isPresented = function(use: Use)
			return #use(chat.messages) == 0 and not use(promptUsed) and not use(short)
		end,
		onRetire = function()
			promptUsed:set(true)
		end,
		content = function(): Instance
			return words("PromptTip", "Start from a prompt, then edit it before you send.", "label")
		end,
	}
	return body,
		UI.ZStack "Overlays" {
			width = "fill" :: "fill",
			height = "fill" :: "fill",
			callout :: unknown,
			ctx.toastFor("Chat"),
		}
end
