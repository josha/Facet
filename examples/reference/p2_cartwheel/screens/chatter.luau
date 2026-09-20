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
	local Compose = app.Compose
	local S = app.S
	local entitlement = app.services.entitlement

	local self: any = {}
	local subscribed = entitlement.chatterPlus
	local tier = Compose.cell("yearly")
	local optHighlight = Compose.cell(false)
	local optTools = Compose.cell(true)
	local subscribeModal: any = nil
	local optionsModal: any = nil
	self.tier = tier

	local notSubscribed = Compose.formula(function(use)
		return not use(subscribed)
	end)
	local title = Compose.formula(function(use)
		return if use(subscribed) then S.t("chatter.plusTitle") else S.t("chatter.title")
	end)

	-- ---- a post row ----------------------------------------------------------

	-- The page is built per visit: a node belongs to the mount that made it.
	local function buildPage(): any
		local function postRow(post: any, highlighted: boolean): any
			local potion = data.potionById(post.potion)
			local tags: { any } = {}
			for index, tagIndex in post.tags do
				table.insert(tags, parts.chip(app, "Tag" .. index, (data.chatterTags :: any)[tagIndex]))
			end
			local avatarPlate = UI.Box("Plate")({
				surface = "base",
				width = UI.fill(),
				height = UI.fill(),
			})
			avatarPlate = UI.corners(avatarPlate, "pill")
			avatarPlate = UI.stroke(avatarPlate, {})
			avatarPlate = UI.gradient(avatarPlate, { colors = { "surfaceStrong", "control" }, rotation = 45 })
			return UI.HStack("Post_" .. post.id)({
				gap = "s",
				align = "start",
				width = UI.fill(),

				UI.ZStack("Avatar")({
					width = { type = "fixed", px = "controlSizes.regular.height" },
					height = { type = "fixed", px = "controlSizes.regular.height" },

					avatarPlate,
					if potion ~= nil
						then parts.potionMark(app, "Mark", potion, "iconSizes.medium")
						else UI.Spacer("Mark")({}),
				}),
				UI.VStack("Body")({
					gap = "xs",
					width = UI.fill(),

					UI.Text("Message")({
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
					UI.HStack("Tags")(app.withChildren({
						wrap = true,
						gap = "xs",
					}, tags)),
					UI.Text("When")({
						text = S.t("chatter.ago", { ago = strings.relative(post.minutes) }),
						textSize = "caption",
						role = "secondary",
					}),
				}),
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
			local isSelected = Compose.formula(function(use)
				return use(tier) == entry.id
			end)
			table.insert(tierMemos, isSelected)
			local children: { any } = {
				UI.Text("Label")({
					text = if entry.id == "yearly"
						then S.t("chatter.tierYearly", { credits = entry.credits })
						else S.t("chatter.tierMonthly", { credits = entry.credits }),
					textSize = "body",
				}),
			}
			if entry.save ~= nil then
				table.insert(children, UI.Spacer("Gap")({ width = UI.fill() }))
				table.insert(children, parts.chip(app, "Save", S.t("chatter.save", { percent = entry.save })))
			end
			return UI.Button("Tier_" .. entry.id)(app.withChildren({
				label = if entry.id == "yearly"
					then S.t("chatter.tierYearly", { credits = entry.credits })
					else S.t("chatter.tierMonthly", { credits = entry.credits }),
				selected = isSelected,
				width = UI.fill(),
				align = "center",
				gap = "s",
				onActivate = function()
					tier:set(entry.id)
				end,
			}, children))
		end

		-- hoisted: `openSubscribe` may run more than once in a session, and a memo
		-- built inside it would be one more memo every time
		local purchasePending = Compose.formula(function(use)
			return use(app.commands.status("purchase:chatter")) == "pending"
		end)
		local purchaseIdle = Compose.formula(function(use)
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
			subscribeModal = app.presentModal(function()
				local children: { any } = {
					UI.Text("Title")({ text = S.t("chatter.getTitle"), textSize = "title" }),
					UI.Text("Body")({ text = S.t("chatter.getBody"), textSize = "body", role = "secondary" }),
				}
				for _, entry in data.chatterTiers :: any do
					table.insert(children, tierRow(entry))
				end
				table.insert(
					children,
					UI.Button("Subscribe")({
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
					app.when("WorkingWhen")({
						condition = purchasePending,
						thenView = function()
							return parts.chip(app, "Working", S.t("command.working"))
						end,
					})
				)
				return UI.Screen("CartwheelSubscribe")({
					padding = "l",

					UI.VStack("Card")(app.withChildren({
						gap = "m",
						padding = "l",
						surface = "raised",
						width = UI.fill(),
					}, children)),
				})
			end, { outsideTapCancel = true, initialFocus = "Subscribe" })
		end
		self.openSubscribe = openSubscribe

		local function openOptions()
			if optionsModal ~= nil then
				return
			end
			optionsModal = app.presentModal(function()
				return UI.Screen("CartwheelChatterOptions")({
					padding = "l",

					UI.VStack("Card")({
						gap = "m",
						padding = "l",
						surface = "raised",
						width = UI.fill(),

						UI.Text("Title")({ text = S.t("chatter.options"), textSize = "title" }),
						UI.Text("Status")({
							text = S.t("chatter.optionsStatus"),
							textSize = "caption",
							role = "secondary",
						}),
						UI.Toggle("Highlight")({ label = S.t("chatter.optHighlight"), value = optHighlight }),
						UI.Toggle("Tools")({ label = S.t("chatter.optTools"), value = optTools }),
						UI.Button("Close")({
							label = S.t("ledger.close"),
							surface = "accent",
							onActivate = function()
								if optionsModal ~= nil then
									app.presenter.dismiss(optionsModal)
									optionsModal = nil
								end
							end,
						}),
					}),
				})
			end, { outsideTapCancel = true, initialFocus = "Highlight" })
		end

		-- ---- the page ------------------------------------------------------------

		local marketingCard = parts.card(app, {
			id = "Marketing",
			children = {
				UI.Text("Heading")({ text = S.t("chatter.getTitle"), textSize = "heading" }),
				UI.Text("Body")({ text = S.t("chatter.getBody"), textSize = "body", role = "secondary" }),
				UI.Button("GetStarted")({
					label = S.t("chatter.getStarted"),
					surface = "accent",
					onActivate = openSubscribe,
				}),
			},
		})

		local page = UI.VStack("Chatter")({
			padding = "m",
			gap = "s",
			width = UI.fill(),
			height = UI.fill(),

			UI.HStack("Header")({
				gap = "s",
				align = "center",
				width = UI.fill(),

				UI.Text("Title")({ text = title, textSize = "title" }),
				UI.Spacer("Gap")({ width = UI.fill() }),
				app.when("OptionsWhen")({
					condition = subscribed,
					thenView = function()
						return UI.Button("Options")({
							label = S.t("chatter.options"),
							compactLabel = { icon = "menu" },
							onActivate = openOptions,
						})
					end,
				}),
			}),
			UI.ScrollView("Feed")({
				axis = "y",
				gap = "m",
				width = UI.fill(),
				height = UI.fill(),

				app.when("MarketingWhen")({
					condition = notSubscribed,
					thenView = function()
						return marketingCard
					end,
				}),
				app.when("HighlightWhen")({
					condition = subscribed,
					thenView = function()
						local children: { any } = {
							UI.Text("Heading")({ text = S.t("chatter.highlighted"), textSize = "heading" }),
						}
						for _, row in bonusRows do
							table.insert(children, row)
						end
						return UI.VStack("Highlighted")(app.withChildren({
							gap = "s",
							width = UI.fill(),
						}, children))
					end,
				}),
				UI.VStack("Posts")(app.withChildren({
					gap = "m",
					width = UI.fill(),
				}, postRows)),
			}),
		})

		return page
	end

	self.view = buildPage

	function self.dump(): any
		return {
			subscribed = subscribed:peek(),
			tier = tier:peek(),
			posts = #(data.chatterPosts :: any),
			bonus = #(data.chatterBonusPosts :: any),
			options = { highlight = optHighlight:peek(), tools = optTools:peek() },
			subscribeOpen = subscribeModal ~= nil,
		}
	end

	return self
end

return chatter
