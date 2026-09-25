--!strict

local COPY = {
	title = "Two plates, and who raised them",
	intro = "A tooltip is pulled by the player and shows nothing on touch. A coach mark is pushed by the app and shows on every input class.",
	plus = "+",
	plusName = "Post to Marketplace",
	share = "Share",
	tipTitle = "Post Avatars to Marketplace",
	tipSub = "Anyone can wear it",
	secondTitle = "Share your build",
	secondSub = "Friends can try it on",
	dismiss = "Got it",
	show = "Show the coach mark",
	showSecond = "Ask for a second one",
	use = "I used the feature",
	reset = "Start a fresh session",
	resetNote = "A retired coach mark never comes back — that is the contract, not a bug. The only thing that brings one back is a new session, so this button is what a new session IS: the save file is cleared and a fresh pair of coach marks is built. Without it this screen could be tested exactly once per launch.",
	pressed = "Presses on the + underneath: ",
	queueTitle = "The queue",
	stateTitle = "What the framework reports",
	saveTitle = "What THIS app chose to save",
	saveNothing = "nothing yet — the framework has written none of it",
	helpTitle = "Help is pulled, and it is never the only route",
	helpPlus = "Posts this avatar to the Marketplace",
	helpShare = "Shares this build with your friends",
	helpNote = "Hover the two buttons above with a pointer, or put the ring on them. On touch neither says anything — which is why both sentences are also printed here: Posts this avatar to the Marketplace. Shares this build with your friends.",
	note = "The coach mark never blocks: the + keeps counting presses underneath it, and one arrow press reaches the Got it row.",
}

return {
	title = "Coach marks and help",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum

		local seen = Compose.cell(false)
		local featureUsed = Compose.cell(false)
		local saved = Compose.cell(COPY.saveNothing)
		local reported = Compose.cell("—")
		local presses = Compose.cell(0)
		local pressLine = Compose.formula(function(use)
			return COPY.pressed .. tostring(use(presses))
		end)

		local function plate(title: string, sub: string): any
			return Host.Frame "Body" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 4),
				}),
				UI.Label({
					LayoutOrder = 1,
					Name = "Title",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = title,
					textRole = "body",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({
					LayoutOrder = 2,
					Name = "Sub",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = sub,
					textRole = "caption",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			}
		end

		local generation = Compose.cell(1)

		local function mark(id: string)
			return {
				id = id,
				requested = Compose.cell(false),
				showing = Compose.cell(false),
				retired = Compose.cell(false),
			}
		end
		local tip, second = mark("AvatarTip"), mark("ShareTip")
		local function stateOf(entry: any): string
			if entry.retired:peek() then
				return "retired"
			elseif entry.showing:peek() then
				return "showing"
			elseif entry.requested:peek() then
				return "queued"
			end
			return "waiting"
		end
		local function ask(entry: any)
			if not entry.retired:peek() then
				entry.requested:set(true)
			end
		end
		local function callbacks(entry: any, onRetire: (string) -> ())
			return {
				onShow = function()
					entry.showing:set(true)
				end,
				onHide = function(reason: string)
					entry.showing:set(false)

					if reason ~= "hidden" then
						entry.requested:set(false)
					end
				end,
				onRetire = function(reason: string)
					entry.retired:set(true)
					entry.requested:set(false)
					onRetire(reason)
				end,
			}
		end

		local function avatarTip()
			local events = callbacks(tip, function(reason: string)
				reported:set(reason)

				seen:set(true)
				saved:set(`seen = true (because the framework reported "{reason}")`)
			end)
			local anchor = UI.Button "Plus" {
				label = COPY.plus,
				name = COPY.plusName,
				help = COPY.helpPlus,
				onActivate = function()
					presses:set(presses:peek() + 1)
				end,
			}
			return Host.Frame "PlusSlot" {
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 0),
				}),
				anchor,
				Compose.keyed({
					from = function(use)
						return { use(generation) }
					end,
					render = function()
						return UI.Callout({
							LayoutOrder = 2,
							Name = "AvatarTip",
							anchor = anchor,
							content = function()
								return plate(COPY.tipTitle, COPY.tipSub)
							end,
							dismissLabel = COPY.dismiss,
							isPresented = tip.requested,
							seen = seen,
							featureUsed = featureUsed,
							priority = 1,
							onShow = events.onShow,
							onHide = events.onHide,
							onRetire = events.onRetire,
							AnchorPoint = Vector2.new(0, 0),
							Position = UDim2.new(0, 0, 0, 0),
						})
					end,
				}),
			}
		end

		local function shareTip()
			local events = callbacks(second, function() end)
			local anchor = UI.Button "Share" {
				label = COPY.share,
				help = COPY.helpShare,
				onActivate = function() end,
			}
			return Host.Frame "ShareSlot" {
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.new(0, 0, 0, 0),
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 0),
				}),
				anchor,
				Compose.keyed({
					from = function(use)
						return { use(generation) }
					end,
					render = function()
						return UI.Callout({
							LayoutOrder = 2,
							Name = "ShareTip",
							anchor = anchor,
							content = function()
								return plate(COPY.secondTitle, COPY.secondSub)
							end,
							dismissLabel = COPY.dismiss,
							isPresented = second.requested,
							priority = 0,
							onShow = events.onShow,
							onHide = events.onHide,
							onRetire = events.onRetire,
							AnchorPoint = Vector2.new(0, 0),
							Position = UDim2.new(0, 0, 0, 0),
						})
					end,
				}),
			}
		end

		local queueLine = Compose.cell("—")
		local stateLine = Compose.cell("—")
		local function queue()
			local showing, waiting
			for _, entry in { tip, second } do
				if entry.showing:peek() then
					showing = entry.id
				elseif entry.requested:peek() then
					waiting = entry.id
				end
			end
			return {
				showing = showing,
				waiting = waiting,
				text = `Showing: {showing or "none"}; waiting: {waiting or "none"}`,
			}
		end
		local function readState()
			queueLine:set(queue().text)
			stateLine:set(`{tip.id}: {stateOf(tip)}\n{second.id}: {stateOf(second)}`)
		end
		Compose.watch(function(use)
			for _, entry in { tip, second } do
				use(entry.retired)
				use(entry.showing)
				use(entry.requested)
			end
			readState()
		end)

		local function resetSession()
			seen:set(false)
			featureUsed:set(false)
			saved:set(COPY.saveNothing)
			reported:set("—")
			for _, entry in { tip, second } do
				entry.requested:set(false)
				entry.showing:set(false)
				entry.retired:set(false)
			end
			generation:set(generation:peek() + 1)
		end

		local function pick(id: string, label: string, onPress: () -> ()): any
			return UI.Button({
				Name = id,
				label = label,
				onActivate = function()
					onPress()
					readState()
				end,
			})
		end

		local function Example()
			return Host.Frame "CalloutDemo" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 12),
					PaddingBottom = UDim.new(0, 12),
					PaddingLeft = UDim.new(0, 12),
					PaddingRight = UDim.new(0, 12),
				}),
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 12),
				}),
				Host.Frame "Bar" {
					LayoutOrder = 1,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					shareTip(),
					avatarTip(),
				},
				Host.ScrollingFrame "Page" {
					LayoutOrder = 2,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					Host.UIFlexItem({ FlexMode = Enum.UIFlexMode.Fill }),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 6,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					UI.Label({
						LayoutOrder = 1,
						Name = "Title",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.title,
						textRole = "heading",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Label({
						LayoutOrder = 2,
						Name = "Intro",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.intro,
						role = "secondary",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Host.Frame({
						LayoutOrder = 3,
						Name = "Picks",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Horizontal,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
							Wraps = true,
						}),
						pick("Show", COPY.show, function()
							ask(tip)
						end),
						pick("ShowSecond", COPY.showSecond, function()
							ask(second)
						end),
						pick("Use", COPY.use, function()
							featureUsed:set(true)
						end),
						pick("Reset", COPY.reset, resetSession),
					}),
					UI.Label({
						LayoutOrder = 4,
						Name = "Presses",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = pressLine,
						textRole = "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Label({
						LayoutOrder = 5,
						Name = "ResetNote",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.resetNote,
						textRole = "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					Host.Frame({
						LayoutOrder = 6,
						Name = "Queue",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 4),
						}),
						Host.UIPadding({
							PaddingTop = UDim.new(0, 8),
							PaddingBottom = UDim.new(0, 8),
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
						}),
						UI.Label({
							LayoutOrder = 1,
							Name = "QueueTitle",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = COPY.queueTitle,
							textRole = "caption",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						UI.Label({
							LayoutOrder = 2,
							Name = "QueueBody",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = queueLine,
							textRole = "caption",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
					}),
					Host.Frame({
						LayoutOrder = 7,
						Name = "State",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 4),
						}),
						Host.UIPadding({
							PaddingTop = UDim.new(0, 8),
							PaddingBottom = UDim.new(0, 8),
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
						}),
						UI.Label({
							LayoutOrder = 1,
							Name = "StateTitle",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = COPY.stateTitle,
							textRole = "caption",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						UI.Label({
							LayoutOrder = 2,
							Name = "StateBody",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = stateLine,
							textRole = "caption",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						UI.Label({
							LayoutOrder = 3,
							Name = "Reported",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = reported,
							textRole = "caption",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
					}),
					Host.Frame({
						LayoutOrder = 8,
						Name = "Save",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 4),
						}),
						Host.UIPadding({
							PaddingTop = UDim.new(0, 8),
							PaddingBottom = UDim.new(0, 8),
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
						}),
						UI.Label({
							LayoutOrder = 1,
							Name = "SaveTitle",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = COPY.saveTitle,
							textRole = "caption",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						UI.Label({
							LayoutOrder = 2,
							Name = "SaveBody",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = saved,
							textRole = "caption",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
					}),
					Host.Frame({
						LayoutOrder = 9,
						Name = "Help",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 4),
						}),
						Host.UIPadding({
							PaddingTop = UDim.new(0, 8),
							PaddingBottom = UDim.new(0, 8),
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
						}),
						UI.Label({
							LayoutOrder = 1,
							Name = "HelpTitle",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = COPY.helpTitle,
							textRole = "caption",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						UI.Label({
							LayoutOrder = 2,
							Name = "HelpBody",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = COPY.helpNote,
							textRole = "caption",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
					}),
					UI.Label({
						LayoutOrder = 10,
						Name = "Note",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.note,
						textRole = "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
				},
			}
		end

		return {
			screen = Example,
			present = {},
			presses = presses,
			seen = seen,

			steps = {
				show = function()
					ask(tip)
					readState()
					return { state = stateOf(tip) }
				end,
				showSecond = function()
					ask(second)
					readState()
					return { showing = queue().showing }
				end,
				use = function()
					featureUsed:set(true)
					readState()
					return { state = stateOf(tip), saved = saved:peek() }
				end,
				reset = function()
					resetSession()
					readState()
					return { generation = generation:peek() }
				end,
				reread = function()
					readState()
					return { queue = queueLine:peek() }
				end,
			},

			report = function()
				return {
					tip = { id = tip.id, state = stateOf(tip) },
					second = { id = second.id, state = stateOf(second) },
					queue = queue(),
					presses = presses:peek(),
					seen = seen:peek(),
					saved = saved:peek(),
					generation = generation:peek(),
				}
			end,

			dispose = function() end,
		}
	end,
}
