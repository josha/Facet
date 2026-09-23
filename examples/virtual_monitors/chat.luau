--!strict
return function(ctx)
	local Compose, Host, UI, runtime, model = ctx.Compose, ctx.Host, ctx.UI, ctx.runtime, ctx.model
	local D, D2, V2, C3, E = ctx.D, ctx.D2, ctx.V2, ctx.C3, ctx.E
	local text, row, column, button = ctx.text, ctx.row, ctx.column, ctx.button
	local chat, promptUsed = model.chat, model.chatPromptUsed
	local body = Host.Frame({ Name = "ChatBody", Size = D2.fromScale(1, 1), BackgroundTransparency = 1 })
	local extent = ctx.observeSize(body)
	local width = Compose.formula(function(use)
		return math.min(960, math.max(0, use(extent).X - 24))
	end)
	local short = Compose.formula(function(use)
		return use(extent).Y < 360
	end)
	local footerHeight = Compose.cell(0)
	local measured = Compose.cell({})
	local status = Compose.cell({
		mode = "windowed",
		direction = "vertical",
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
	local function footerExtent(use)
		local measuredHeight = use(footerHeight)
		return if measuredHeight > 0 then measuredHeight else (if use(width) < 298 then 172 else 124)
	end
	local function prompt(value)
		promptUsed:set(true)
		chat.draft:set(value)
	end
	local function sparkle(size)
		local path = Host.Path2D({
			Name = "AssistantMark",
			Thickness = math.max(2, math.floor(size / 10)),
			Closed = true,
			Color3 = function(use)
				return if use(model.dark) then C3.fromRGB(192, 172, 255) else C3.fromRGB(91, 70, 140)
			end,
		})
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
		return Host.Frame({
			Name = "AssistantIcon",
			Size = D2.fromOffset(size, size),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			path,
		})
	end
	local function message(current)
		local id = current:peek().id
		local card = column("Message_" .. id, {
			text("Role", function(use)
				return if use(current).role == "user" then "You" else "Assistant"
			end, 16, {}, "facet-secondary"),
			text("Message", function(use)
				local value = use(current).content
				return if value == "" then "Thinking…" else value
			end, 18),
		}, {
			Size = function(use)
				return D2.new(1, if use(current).role == "assistant" then -32 else 0, 0, 0)
			end,
			Position = function(use)
				return D2.fromOffset(if use(current).role == "assistant" then 32 else 0, 0)
			end,
			BackgroundTransparency = function(use)
				return if use(current).role == "user" then 0 else 1
			end,
			ctx.padding(14),
			ctx.rounded(),
		})
		card:AddTag("facet-track")
		local observation = runtime.host.observation
		local function updateSize()
			local height = observation.readProperty(card, "AbsoluteSize").Y
			if height > 0 and measured:peek()[id] ~= height then
				measured:update(function(currentSizes)
					local nextSizes = table.clone(currentSizes)
					nextSizes[id] = height
					return nextSizes
				end)
			end
		end
		Compose.cleanup(observation.observeProperty(card, "AbsoluteSize", updateSize))
		updateSize()
		return UI.RowActions({
			Name = "MessageActions_" .. id,
			Size = D2.fromScale(1, 1),
			content = function()
				return Host.Frame({
					Name = "MessageRow_" .. id,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					BackgroundTransparency = 1,
					card,
					Compose.show(function(use)
						return use(current).role == "assistant"
					end, function()
						local icon = sparkle(20)
						runtime.decorate(icon, { Position = D2.fromOffset(0, 14) })
						return icon
					end),
				})
			end,
			trailing = {
				{
					id = "DeleteMessage",
					label = "Delete",
					role = "destructive",
					onActivate = function()
						chat.remove(id)
					end,
				},
			},
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
		},
		{
			id = "FollowReplies",
			label = "Follow replies",
			checked = model.followChat,
			onChange = function(value)
				model.followChat:set(value)
			end,
		},
		{ divider = true },
		{ id = "Clear", label = "Clear conversation", role = "destructive", onSelect = chat.clear },
	}
	runtime.mountFragment(function()
		local findGame = button("FindGame", "Find a game", function()
			prompt("What game should I play with friends?")
		end, { Size = D2.fromOffset(130, 40), AutomaticSize = E.AutomaticSize.Y, TextWrapped = true })
		local buildSomething = button("BuildSomething", "Build something", function()
			prompt("Help me build a game browser")
		end, { Size = D2.fromOffset(160, 40), AutomaticSize = E.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 2 })
		local prompts = Host.Frame({
			Name = "Suggestions",
			Visible = function(use)
				return not use(short)
			end,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				SortOrder = E.SortOrder.LayoutOrder,
				Wraps = true,
				Padding = D.new(0, 8),
			}),
			findGame,
			buildSomething,
		})
		local footer = column("Composer", {
			prompts,
			row("ComposeMessage", {
				UI.TextInput({
					Name = "Draft",
					value = chat.draft,
					placeholder = "Message assistant",
					onChange = function(value)
						chat.draft:set(value)
					end,
					onCommit = function(_, reason)
						if reason == "submit" then
							chat.send()
						end
					end,
					Size = D2.new(1, -156, 0, 44),
				}),
				UI.SplitButton({
					Name = "Send",
					menuLabel = "More",
					Size = D2.fromOffset(148, 44),
					AutomaticSize = E.AutomaticSize.None,
					label = function(use)
						return if use(chat.streaming) then "Stop" else "Send"
					end,
					onActivate = function()
						if chat.streaming:peek() then
							chat.stop()
						else
							chat.send()
						end
					end,
					items = {
						{
							id = "Fresh",
							label = "Send in a new conversation",
							onSelect = function()
								local kept = chat.draft:peek()
								chat.clear()
								chat.draft:set(kept)
								chat.send()
							end,
						},
						{ id = "Clear", label = "Clear conversation", role = "destructive", onSelect = chat.clear },
					},
				}),
			}, { Size = D2.new(1, 0, 0, 44) }),
			text("Disclaimer", "Simulated responses · No messages leave this device", 12, {
				Visible = function(use)
					return not use(short)
				end,
			}, "facet-secondary"),
		}, { AnchorPoint = V2.new(0, 1), Position = D2.fromScale(0, 1), Size = D2.new(1, 0, 0, 0) })
		local observation = runtime.host.observation
		local function measureFooter()
			local height = observation.readProperty(footer, "AbsoluteSize").Y
			if height > 0 then
				footerHeight:set(height)
			end
		end
		Compose.cleanup(observation.observeProperty(footer, "AbsoluteSize", measureFooter))
		measureFooter()
		return {
			Host.Frame({
				Name = "ConversationColumn",
				BackgroundTransparency = 1,
				AnchorPoint = V2.new(0.5, 0),
				Position = D2.fromScale(0.5, 0),
				Size = D2.new(1, -24, 1, 0),
				Host.UISizeConstraint({ MaxSize = V2.new(960, math.huge) }),
				row("ChatToolbar", {
					text(
						"Status",
						function(use)
							local count = #use(chat.messages)
							return if use(chat.streaming)
								then "Writing a reply…"
								elseif count == 0 then "New conversation"
								else `{count} messages`
						end,
						15,
						{
							Size = D2.new(1, -154, 0, 22),
							AutomaticSize = E.AutomaticSize.None,
							TextTruncate = E.TextTruncate.AtEnd,
						},
						"facet-secondary"
					),
					UI.Menu({
						Name = "Conversation",
						trigger = button("ConversationMenu", "Conversation", function() end, {
							compactLabel = "Thread",
							Size = D2.fromOffset(146, 40),
							AutomaticSize = E.AutomaticSize.None,
						}),
						items = conversationItems,
						Size = D2.fromOffset(146, 40),
						AutomaticSize = E.AutomaticSize.None,
					}),
				}, { Size = D2.new(1, 0, 0, 40) }),
				Host.Frame({
					Name = "Thread",
					Position = D2.fromOffset(0, 50),
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					Size = function(use)
						return D2.fromOffset(use(width), math.max(0, use(extent).Y - footerExtent(use) - 62))
					end,
					Compose.keyed({
						from = function(use)
							return { use(model.followChat) }
						end,
						key = function(value)
							return tostring(value)
						end,
						render = function(current)
							return ctx.collection("VirtualList", {
								Name = "Messages",
								from = chat.messages,
								key = function(item)
									return item.id
								end,
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
					Compose.show(function(use)
						return #use(chat.messages) == 0
					end, function()
						local entered = Compose.cell(0)
						local motion = runtime.tween(function(use)
							return use(entered)
						end, { seconds = 0.24 })
						entered:set(1)
						local function reveal(use)
							local reduced = ctx.actions.reducedMotion
							if Compose.isReadable(reduced) then
								reduced = use(reduced)
							elseif type(reduced) == "function" then
								reduced = reduced(use)
							end
							return if reduced then 1 else math.clamp(use(motion), 0, 1)
						end
						return Host.CanvasGroup({
							Name = "Welcome",
							Size = D2.fromScale(1, 1),
							BackgroundTransparency = 1,
							GroupTransparency = function(use)
								return 1 - reveal(use)
							end,
							column("WelcomeContent", {
								Compose.show(function(use)
									return not use(short)
								end, function()
									return sparkle(40)
								end),
								UI.Label({
									Name = "WelcomeQuestion",
									text = "What are you working on?",
									textRole = "title",
									TextSize = function(use)
										return if use(short) then 20 else 28
									end,
									TextWrapped = true,
									TextYAlignment = E.TextYAlignment.Top,
									Size = D2.new(1, 0, 0, 0),
									AutomaticSize = E.AutomaticSize.Y,
								}),
								Compose.show(function(use)
									return not use(short)
								end, function()
									return text(
										"Hint",
										"Ask a question or try a prompt below.",
										18,
										{ LayoutOrder = 3 },
										"facet-secondary"
									)
								end),
							}, {
								AnchorPoint = V2.new(0.5, 0.5),
								Size = D2.new(1, -24, 0, 0),
								Position = function(use)
									return D2.new(0.5, 0, 0.5, (1 - reveal(use)) * 12)
								end,
							}),
						})
					end),
				}),
				footer,
				UI.Callout({
					Name = "PromptHint",
					anchor = findGame,
					edge = "top",
					align = "leading",
					featureUsed = promptUsed,
					isPresented = function(use)
						return #use(chat.messages) == 0 and not use(promptUsed) and not use(short)
					end,
					onRetire = function()
						promptUsed:set(true)
					end,
					content = function()
						return text("PromptTip", "Start from a prompt, then edit it before you send.", 16)
					end,
				}),
				Compose.show(chat.streaming, function()
					return UI.ProgressView({
						Name = "ReplyProgress",
						value = function(use)
							return use(chat.streamedChars) / math.max(1, use(chat.totalChars))
						end,
						Position = function(use)
							return D2.new(0, 0, 1, -footerExtent(use) - 8)
						end,
						Size = D2.new(1, 0, 0, 4),
					})
				end),
			}),
		}
	end, body)
	return body
end
