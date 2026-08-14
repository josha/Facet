--!strict
-- TOWN CHATTER — the feed and its entitlement gate (spec §11).
--
-- One `When` on the entitlement fact decides everything: the marketing card or
-- the highlighted section, the plain title or the plus one, the options button
-- or nothing. The purchase itself is a command like any other — the first
-- attempt declines with copy the player can read, and the second confirms.
--
-- Production mapping: Roblox Subscriptions. The PROMPT is a host sheet, so the
-- in-experience UI ends where the prompt would begin; the tiers page below is
-- the part a game actually owns.
local data = require("../content/data")
local parts = require("./parts")
local strings = require("../content/strings")

local chatter = {}

function chatter.new(app: any): any
	local UI = app.UI
	local core = app.core
	local S = app.S
	local entitlement = app.services.entitlement

	local self: any = {}
	local subscribed = entitlement.chatterPlus
	local tier = core:signal("yearly")
	local optHighlight = core:signal(false)
	local optTools = core:signal(true)
	local subscribeModal: any = nil
	local optionsModal: any = nil
	self.tier = tier

	local notSubscribed = core:memo(function(use)
		return not use(subscribed)
	end)
	local title = core:memo(function(use)
		return if use(subscribed) then S.t("chatter.plusTitle") else S.t("chatter.title")
	end)

	-- ---- a post row ----------------------------------------------------------

	local function postRow(post: any, highlighted: boolean): any
		local potion = data.potionById(post.potion)
		local tags: { any } = {}
		for index, tagIndex in post.tags do
			table.insert(tags, parts.chip(app, "Tag" .. index, (data.chatterTags :: any)[tagIndex]))
		end
		local avatarPlate = UI.Box({
			id = "Plate",
			surface = "base",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
		})
		avatarPlate = UI.corners(avatarPlate, "pill")
		avatarPlate = UI.stroke(avatarPlate, {})
		avatarPlate = UI.gradient(avatarPlate, { colors = { "surfaceStrong", "control" }, rotation = 45 })
		return UI.HStack({
			id = "Post_" .. post.id,
			gap = "s",
			align = "start",
			width = { type = "fill", weight = 1 },
			children = {
				UI.ZStack({
					id = "Avatar",
					width = { type = "fixed", px = "controlSizes.regular.height" },
					height = { type = "fixed", px = "controlSizes.regular.height" },
					children = {
						avatarPlate,
						if potion ~= nil
							then parts.potionMark(app, "Mark", potion, "iconSizes.medium")
							else UI.Spacer({ id = "Mark" }),
					},
				}),
				UI.VStack({
					id = "Body",
					gap = "xs",
					width = { type = "fill", weight = 1 },
					children = {
						UI.Text({
							id = "Message",
							text = S.t("chatter.postSaid", {
								who = post.who,
								potion = if potion == nil then post.potion else potion.name,
							}),
							textSize = if highlighted then "strong" else "body",
							lineLimit = 3,
							disclose = true,
						}),
						-- ragged, not uniform: a post's tags are words of different
						-- lengths, and the uniform grid this used to be padded both of
						-- them out to the wider one (measured 105/105, 113/113, 83/83 ...
						-- across the six seeded posts). `wrap = true` also means a third
						-- tag would drop to a second line instead of squeezing the row.
						UI.HStack({
							id = "Tags",
							wrap = true,
							gap = "xs",
							children = tags,
						}),
						UI.Text({
							id = "When",
							text = S.t("chatter.ago", { ago = strings.relative(post.minutes) }),
							textSize = "caption",
							role = "secondary",
						}),
					},
				}),
			},
		})
	end

	local postRows: { any } = {}
	for _, post in data.chatterPosts :: any do
		table.insert(postRows, postRow(post, false))
	end
	local bonusRows: { any } = {}
	for _, post in data.chatterBonusPosts :: any do
		table.insert(bonusRows, postRow(post, true))
	end

	-- ---- the subscription modal ---------------------------------------------

	local tierMemos: { any } = {}
	local function tierRow(entry: any): any
		local isSelected = core:memo(function(use)
			return use(tier) == entry.id
		end)
		table.insert(tierMemos, isSelected)
		local children: { any } = {
			UI.Text({
				id = "Label",
				text = if entry.id == "yearly"
					then S.t("chatter.tierYearly", { credits = entry.credits })
					else S.t("chatter.tierMonthly", { credits = entry.credits }),
				textSize = "body",
			}),
		}
		if entry.save ~= nil then
			table.insert(children, UI.Spacer({ id = "Gap", width = { type = "fill", weight = 1 } }))
			table.insert(children, parts.chip(app, "Save", S.t("chatter.save", { percent = entry.save })))
		end
		return UI.Button({
			id = "Tier_" .. entry.id,
			label = if entry.id == "yearly"
				then S.t("chatter.tierYearly", { credits = entry.credits })
				else S.t("chatter.tierMonthly", { credits = entry.credits }),
			selected = isSelected,
			width = { type = "fill", weight = 1 },
			align = "center",
			gap = "s",
			onActivate = function()
				tier:set(entry.id)
			end,
			children = children,
		})
	end

	local tierRows: { any } = {}
	for _, entry in data.chatterTiers :: any do
		table.insert(tierRows, tierRow(entry))
	end

	-- hoisted: `openSubscribe` may run more than once in a session, and a memo
	-- built inside it would be one more memo every time
	local purchasePending = core:memo(function(use)
		return use(app.commands.status("purchase:chatter")) == "pending"
	end)
	local purchaseIdle = core:memo(function(use)
		return not use(purchasePending)
	end)

	local function closeSubscribe()
		if subscribeModal ~= nil then
			app.presenter.dismiss(subscribeModal)
			subscribeModal = nil
		end
	end
	self.closeSubscribe = closeSubscribe

	local function openSubscribe()
		if subscribeModal ~= nil then
			return
		end
		local children: { any } = {
			UI.Text({ id = "Title", text = S.t("chatter.getTitle"), textSize = "title" }),
			UI.Text({ id = "Body", text = S.t("chatter.getBody"), textSize = "body", role = "secondary" }),
		}
		for _, row in tierRows do
			table.insert(children, row)
		end
		table.insert(
			children,
			UI.Button({
				id = "Subscribe",
				label = S.t("chatter.subscribe"),
				surface = "accent",
				enabled = purchaseIdle,
				onActivate = function()
					app.actions.purchase("chatter", function()
						closeSubscribe()
					end)
				end,
			})
		)
		table.insert(
			children,
			UI.When({
				id = "WorkingWhen",
				condition = purchasePending,
				thenView = function()
					return parts.chip(app, "Working", S.t("command.working"))
				end,
			})
		)
		subscribeModal = app.presenter.presentModal(
			UI.Screen({
				id = "CartwheelSubscribe",
				padding = "l",
				children = {
					UI.VStack({
						id = "Card",
						gap = "m",
						padding = "l",
						surface = "raised",
						width = { type = "fill", weight = 1 },
						children = children,
					}),
				},
			}),
			{ outsideTapCancel = true, initialFocus = "Subscribe" }
		)
	end
	self.openSubscribe = openSubscribe

	local function openOptions()
		if optionsModal ~= nil then
			return
		end
		optionsModal = app.presenter.presentModal(
			UI.Screen({
				id = "CartwheelChatterOptions",
				padding = "l",
				children = {
					UI.VStack({
						id = "Card",
						gap = "m",
						padding = "l",
						surface = "raised",
						width = { type = "fill", weight = 1 },
						children = {
							UI.Text({ id = "Title", text = S.t("chatter.options"), textSize = "title" }),
							UI.Text({
								id = "Status",
								text = S.t("chatter.optionsStatus"),
								textSize = "caption",
								role = "secondary",
							}),
							UI.Toggle({ id = "Highlight", label = S.t("chatter.optHighlight"), value = optHighlight }),
							UI.Toggle({ id = "Tools", label = S.t("chatter.optTools"), value = optTools }),
							UI.Button({
								id = "Close",
								label = S.t("ledger.close"),
								surface = "accent",
								onActivate = function()
									if optionsModal ~= nil then
										app.presenter.dismiss(optionsModal)
										optionsModal = nil
									end
								end,
							}),
						},
					}),
				},
			}),
			{ outsideTapCancel = true, initialFocus = "Highlight" }
		)
	end

	-- ---- the page ------------------------------------------------------------

	local marketingCard = parts.card(app, {
		id = "Marketing",
		children = {
			UI.Text({ id = "Heading", text = S.t("chatter.getTitle"), textSize = "heading" }),
			UI.Text({ id = "Body", text = S.t("chatter.getBody"), textSize = "body", role = "secondary" }),
			UI.Button({
				id = "GetStarted",
				label = S.t("chatter.getStarted"),
				surface = "accent",
				onActivate = openSubscribe,
			}),
		},
	})

	local page = UI.VStack({
		id = "Chatter",
		padding = "m",
		gap = "s",
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {
			UI.HStack({
				id = "Header",
				gap = "s",
				align = "center",
				width = { type = "fill", weight = 1 },
				children = {
					UI.Text({ id = "Title", text = title, textSize = "title" }),
					UI.Spacer({ id = "Gap", width = { type = "fill", weight = 1 } }),
					UI.When({
						id = "OptionsWhen",
						condition = subscribed,
						thenView = function()
							return UI.Button({
								id = "Options",
								label = S.t("chatter.options"),
								compactLabel = { icon = "menu" },
								onActivate = openOptions,
							})
						end,
					}),
				},
			}),
			UI.ScrollView({
				id = "Feed",
				axis = "y",
				gap = "m",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.When({
						id = "MarketingWhen",
						condition = notSubscribed,
						thenView = function()
							return marketingCard
						end,
					}),
					UI.When({
						id = "HighlightWhen",
						condition = subscribed,
						thenView = function()
							local children: { any } = {
								UI.Text({ id = "Heading", text = S.t("chatter.highlighted"), textSize = "heading" }),
							}
							for _, row in bonusRows do
								table.insert(children, row)
							end
							return UI.VStack({
								id = "Highlighted",
								gap = "s",
								width = { type = "fill", weight = 1 },
								children = children,
							})
						end,
					}),
					UI.VStack({
						id = "Posts",
						gap = "m",
						width = { type = "fill", weight = 1 },
						children = postRows,
					}),
				},
			}),
		},
	})

	function self.view(): any
		return page
	end

	function self.dump(): any
		return {
			subscribed = subscribed:get(),
			tier = tier:get(),
			posts = #postRows,
			bonus = #bonusRows,
			options = { highlight = optHighlight:get(), tools = optTools:get() },
			subscribeOpen = subscribeModal ~= nil,
		}
	end

	function self.dispose()
		closeSubscribe()
		if optionsModal ~= nil then
			app.presenter.dismiss(optionsModal)
			optionsModal = nil
		end
		for _, memo in tierMemos do
			memo:dispose()
		end
		purchaseIdle:dispose()
		purchasePending:dispose()
		title:dispose()
		notSubscribed:dispose()
		optTools:dispose()
		optHighlight:dispose()
		tier:dispose()
	end

	return self
end

return chatter
