--!strict

type StringPickerOption = typeof(require("@repo/tools/typecheck/aliases").StringPickerOption)
type Tab = typeof(require("@repo/tools/typecheck/aliases").Tab)
type AlertAction = typeof(require("@repo/tools/typecheck/aliases").AlertAction)
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Value<T> = typeof(require("@repo/src/vendor/compose/core").cell<<T>>(nil :: never))
type Use = <T>(ReadOnlyValue<T>) -> T
type ExampleContext = typeof(require("@repo/examples/types").Context)
local Services = require("@self/services")
local seed = require("@self/content/seed")
local strings = require("@self/content/strings")
local referenceView = require("./view")
local Foyer = { title = "Foyer" }
function Foyer.build(ctx: ExampleContext)
	local Compose, UI, Host = ctx.Compose, ctx.UI, ctx.Host
	local D2 = ctx.types.UDim2
	local view = referenceView(ctx)
	local services = Services.new({ Compose = Compose })
	local destination, tab, query, locale =
		Compose.cell("home"), Compose.cell("forYou"), Compose.cell(""), Compose.cell("en")
	local noSelection: string? = nil
	local selected: Value<string?> = Compose.cell(noSelection)
	local detailOpen, notifications, invite = Compose.cell(false), Compose.cell(false), Compose.cell(false)
	local noSection: Services.Section? = nil
	local sectionOpen = Compose.cell(false)
	local expanded: Value<Services.Section?> = Compose.cell(noSection)
	local filtered = services.filterMemo(query)
	local notice = Compose.cell("")
	local function text(key: string, param: string?): (Use) -> string
		return function(use: Use): string
			return strings.get(use(locale), key, param)
		end
	end
	local function open(id: string)
		selected:set(id)
		detailOpen:set(true)
	end
	local function settle()
		services.settle()
	end
	local heartbeat: RBXScriptSignal? = ctx.heartbeat or (if game then game:GetService("RunService").Heartbeat else nil)
	if heartbeat then
		local beat = heartbeat:Connect(settle)
		Compose.cleanup(function()
			beat:Disconnect()
		end)
	end
	Compose.watch(function(use: Use)
		local status = use(services.refreshStatus)
		if status == "confirmed" then
			notice:set(strings.get(locale:peek(), "toast.refreshed"))
		elseif status == "rejected" then
			notice:set(strings.get(locale:peek(), services.refreshReason:peek() or "err.generic"))
		end
	end)
	Compose.watch(function(use: Use)
		if use(services.visitStatus) == "confirmed" then
			notice:set(strings.get(locale:peek(), "toast.visited"))
		elseif use(services.visitStatus) == "rejected" then
			notice:set(strings.get(locale:peek(), "err.generic"))
		end
	end)
	local function image(key: string, size: UDim2?)
		return UI.AsyncImage "Artwork" {
			source = key,
			Size = size or D2.new(1, 0, 0, 140),
			failureLabel = "Artwork unavailable",
			loader = function(source: string, resolve: (string?) -> (), reject: (unknown) -> ()): (() -> ())?
				local ok, asset = seed.assetFor(source)
				if ok then
					resolve(asset)
				else
					reject("scripted-failure")
				end
				return nil
			end,
		}
	end
	local function tile(item: seed.Tile)
		return view.column(item.id, {
			image(item.thumbKey),
			view.action("Open", item.title, function()
				open(item.id)
			end),
			view.text(item.creator .. " · " .. item.approval .. "% approval"),
			view.text(if item.sponsored then "Sponsored" else item.blurb),
		})
	end
	local function tiles(items: { seed.Tile }): ScrollingFrame
		return UI.VirtualGrid "Worlds" {
			from = function(): { seed.Tile }
				return items
			end,
			key = function(item: seed.Tile): string
				return item.id
			end,
			itemSize = 258,
			minColumnWidth = 232,
			measure = true,
			gap = 12,
			Size = D2.fromScale(1, 1),
			recycle = false,
			render = function(current: ReadOnlyValue<seed.Tile>): GuiObject
				return tile(current:peek())
			end,
		}
	end
	local feeds: { StringPickerOption } = {
		{ value = "forYou", label = "For you" },
		{ value = "charts", label = "Charts" },
	}
	local locales: { StringPickerOption } = {
		{ value = "en", label = "English" },
		{ value = "xa", label = "Expanded" },
	}
	local function feed(): Instance
		return view.page("Feed", {
			view.text("Foyer", 30),
			UI.TextInput "Search" { value = query, placeholder = text("search.ph") },
			view.action("Refresh", text("refresh.label"), services.refresh, function(use: Use)
				return use(services.refreshStatus) ~= "pending"
			end),
			view.action("Notifications", function(use: Use)
				return strings.get(use(locale), "bell.label") .. " · " .. tostring(use(services.noticeCount))
			end, function()
				services.clearNotices()
				notifications:set(true)
			end),
			UI.Picker "FeedSelection" {
				selected = tab,
				options = feeds,
			},
			Compose.show(function(use: Use)
				return use(query) ~= ""
			end, function()
				return view.column("SearchResults", {
					view.watch(function(use: Use): { seed.Tile }
						return use(filtered)
					end, function(current: ReadOnlyValue<seed.Tile>): GuiObject
						return tile(current:peek())
					end, function(item: seed.Tile): string
						return item.id
					end),
					Compose.show(function(use: Use)
						return #use(filtered) == 0
					end, function()
						return view.text(text("search.none"))
					end),
				})
			end, function()
				return view.column("Sections", {
					view.watch(function(use: Use): { Services.Section }
						return if use(tab) == "charts" then services.charted else use(services.sections)
					end, function(current: ReadOnlyValue<Services.Section>): GuiObject
						local entry = current:peek()
						return view.column(entry.id, {
							view.text(text(entry.titleKey), 24),
							view.action(
								"SeeAll",
								text("section.seeAll", strings.get(locale:peek(), entry.titleKey)),
								function()
									expanded:set(entry)
									sectionOpen:set(true)
								end
							),
							view.column("Tiles", {
								view.watch(function(use: Use): { seed.Tile }
									return use(current).tiles
								end, function(item: ReadOnlyValue<seed.Tile>): GuiObject
									return tile(item:peek())
								end, function(item: seed.Tile): string
									return item.id
								end),
							}),
						})
					end, function(entry: Services.Section): string
						return entry.id
					end),
				})
			end),
		})
	end
	local function friends(): Instance
		return view.page("Crews", {
			view.text(text("nav.crews"), 28),
			view.action("Invite", text("invite.label"), function()
				invite:set(true)
			end),
			view.column("Friends", {
				view.list(services.friends, function(current: ReadOnlyValue<seed.Friend>): GuiObject
					local friend = current:peek()
					return view.column(friend.id, {
						image(friend.portraitKey, D2.fromOffset(60, 60)),
						view.text(friend.handle, 22),
						UI.StatusIndicator {
							status = if friend.presence == "here" then "success" else "neutral",
						},
						view.text(friend.presence),
					})
				end, function(friend: seed.Friend): string
					return friend.id
				end),
			}),
		})
	end
	local function mailbox(): Instance
		return view.page("Mail", {
			view.text(text("notices.title"), 28),
			view.column("Notices", {
				view.list(services.notices, function(current: ReadOnlyValue<seed.Notice>): GuiObject
					local item = current:peek()
					return view.column(
						item.id,
						{ view.text(item.bodyKeyless), view.text(text(item.timeKey, item.timeParam)) }
					)
				end, function(item: seed.Notice): string
					return item.id
				end),
			}),
		})
	end
	local destinations: { Tab } = {
		{ id = "home", label = text("nav.home"), content = feed },
		{ id = "crews", label = text("nav.crews"), content = friends },
		{
			id = "forge",
			label = text("nav.forge"),
			content = function(): Instance
				return view.page("Forge", { view.text(text("nav.forge"), 28), view.text(text("stub.honest")) })
			end,
		},
		{ id = "mail", label = text("nav.mail"), content = mailbox },
		{
			id = "you",
			label = text("nav.you"),
			content = function(): Instance
				return view.page("Profile", {
					view.text(text("profile.label"), 28),
					view.text(text("profile.caption")),
					UI.Picker "Locale" {
						selected = locale,
						options = locales,
					},
				})
			end,
		},
	}
	local inviteActions: { AlertAction } = {
		{ id = "close", label = text("close.label"), role = "cancel" },
	}
	local function screen(): Instance
		return Host.Frame "Foyer" {
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 1),
			UI.TabView "Destinations" {
				style = "sidebarAdaptable",
				selection = destination,
				Size = D2.new(1, 0, 1, -64),
				tabs = destinations,
			},
			UI.Text {
				text = notice,
				TextWrapped = true,
				Position = D2.new(0, 16, 1, -60),
				Size = D2.new(1, -32, 0, 56),
				AutomaticSize = ctx.types.Enum.AutomaticSize.None,
			},
			UI.Sheet "WorldDetail" {
				title = "World",
				isPresented = detailOpen,
				detent = Compose.cell("large"),
				content = function(): Instance
					local item = assert(services.tileById(assert(selected:peek())))
					return view.page("World", {
						image(item.thumbKey),
						view.text(item.title, 28),
						view.text(item.creator),
						view.text(item.blurb),
						view.text(`{item.approval}% approval`),
						view.action("Visit", function(use: Use)
							return strings.get(
								use(locale),
								if use(services.visitStatus) == "pending" then "detail.visiting" else "detail.visit"
							)
						end, function()
							services.visit(item.id)
						end, function(use: Use)
							return use(services.visitStatus) ~= "pending"
						end),
					})
				end,
			},
			UI.Sheet "Section" {
				title = "Explore worlds",
				isPresented = sectionOpen,
				detent = Compose.cell("large"),
				content = function(): Instance
					return tiles(assert(expanded:peek()).tiles)
				end,
			},
			UI.Sheet "Notifications" {
				title = text("notices.title"),
				isPresented = notifications,
				detent = Compose.cell("medium"),
				content = mailbox,
			},
			UI.Alert "Invite" {
				isPresented = invite,
				title = Compose.formula(text("invite.label")),
				message = Compose.formula(text("invite.stub")),
				actions = inviteActions,
			},
		}
	end
	return {
		screen = screen,
		model = { services = services, destination = destination, tab = tab, query = query, locale = locale },
		steps = {
			settle = settle,
			open = open,
			search = function(value: string)
				query:set(value)
			end,
			refresh = services.refresh,
			visit = services.visit,
			reject = services.scriptRejection,
		},
		report = function()
			return {
				page = services.currentPage(),
				refresh = services.refreshStatus:peek(),
				visit = services.visitStatus:peek(),
				continued = services.continueIds:peek(),
				notices = services.noticeCount:peek(),
			}
		end,
	}
end
return Foyer
