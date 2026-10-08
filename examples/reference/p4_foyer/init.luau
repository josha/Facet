--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type OptionalStringCell = typeof(require("@repo/tools/typecheck/aliases").OptionalStringCell)
type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
type Tab = typeof(require("@repo/tools/typecheck/aliases").Tab)
type AlertAction = typeof(require("@repo/tools/typecheck/aliases").AlertAction)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type ExampleContext = typeof(require("@repo/examples/types").Context)
local Services = require("@self/services")
local seed = require("@self/content/seed")
local strings = require("@self/content/strings")
local referenceView = require("./view")
local Foyer = { title = "Foyer" }
function Foyer.build(ctx: ExampleContext)
	local Compose: ComposeModule, UI, Host = ctx.Compose, ctx.UI, ctx.Host
	local D2 = ctx.types.UDim2
	local view = referenceView(ctx)
	local services = Services.new({ Compose = Compose })
	local destination, tab, query, locale =
		Compose.cell("home"), Compose.cell("forYou"), Compose.cell(""), Compose.cell("en")
	local selected, detailOpen, notifications, invite =
		(function(value: string?): OptionalStringCell
			return Compose.cell(value)
		end)(nil), Compose.cell(false), Compose.cell(false), Compose.cell(false)
	local sectionOpen, expanded = Compose.cell(false), Compose.cell(nil :: { tiles: { seed.Tile } }?)
	local filtered = services.filterMemo(query)
	local notice = Compose.cell("")
	local function text(key, param)
		return function(use: Use)
			return strings.get(use(locale), key, param)
		end
	end
	local function open(id)
		selected:set(id)
		detailOpen:set(true)
	end
	local function settle()
		services.settle()
	end
	local heartbeat = ctx.heartbeat or (if game then game:GetService("RunService").Heartbeat else nil)
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
			loader = function(source, resolve, reject)
				local ok, asset = seed.assetFor(source)
				if ok then
					resolve(asset)
				else
					reject("scripted-failure")
				end
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
	local function tiles(items)
		return UI.VirtualGrid "Worlds" {
			from = function()
				return items
			end,
			key = function(item)
				return item.id
			end,
			itemSize = 258,
			minColumnWidth = 232,
			measure = true,
			gap = 12,
			Size = D2.fromScale(1, 1),
			render = function(current): GuiObject
				return tile(current:peek())
			end,
		}
	end
	local function feed()
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
				options = {
					{ value = "forYou", label = "For you" } :: PickerOption,
					{ value = "charts", label = "Charts" } :: PickerOption,
				},
			},
			Compose.show(function(use: Use)
				return use(query) ~= ""
			end, function()
				return view.column("SearchResults", {
					view.list(filtered, function(current)
						return tile(current:peek())
					end),
					Compose.show(function(use: Use)
						return #use(filtered) == 0
					end, function()
						return view.text(text("search.none"))
					end),
				})
			end, function()
				return view.column("Sections", {
					view.list(function(use: Use)
						return if use(tab) == "charts" then services.charted else use(services.sections)
					end, function(current)
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
								view.list(function(use: Use)
									return use(current).tiles
								end, function(item)
									return tile(item:peek())
								end),
							}),
						})
					end),
				})
			end),
		})
	end
	local function friends()
		return view.page("Crews", {
			view.text(text("nav.crews"), 28),
			view.action("Invite", text("invite.label"), function()
				invite:set(true)
			end),
			view.column("Friends", {
				view.list(services.friends, function(current)
					local friend = current:peek()
					return view.column(friend.id, {
						image(friend.portraitKey, D2.fromOffset(60, 60)),
						view.text(friend.handle, 22),
						UI.StatusIndicator({
							status = if friend.presence == "here"
								then "success" :: "success"
								else "neutral" :: "neutral",
						}),
						view.text(friend.presence),
					})
				end),
			}),
		})
	end
	local function mailbox(): Instance
		return view.page("Mail", {
			view.text(text("notices.title"), 28),
			view.column("Notices", {
				view.list(services.notices, function(current)
					local item = current:peek()
					return view.column(
						item.id,
						{ view.text(item.bodyKeyless), view.text(text(item.timeKey, item.timeParam)) }
					)
				end),
			}),
		})
	end
	local function screen()
		return Host.Frame "Foyer" {
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 1),
			UI.TabView "Destinations" {
				style = "sidebarAdaptable" :: "sidebarAdaptable",
				selection = destination,
				Size = D2.new(1, 0, 1, -64),
				tabs = {
					{ id = "home", label = text("nav.home"), content = feed } :: Tab,
					{ id = "crews", label = text("nav.crews"), content = friends } :: Tab,
					{
						id = "forge",
						label = text("nav.forge"),
						content = function(): Instance
							return view.page(
								"Forge",
								{ view.text(text("nav.forge"), 28), view.text(text("stub.honest")) }
							)
						end,
					} :: Tab,
					{ id = "mail", label = text("nav.mail"), content = mailbox } :: Tab,
					{
						id = "you",
						label = text("nav.you"),
						content = function(): Instance
							return view.page("Profile", {
								view.text(text("profile.label"), 28),
								view.text(text("profile.caption")),
								UI.Picker "Locale" {
									selected = locale,
									options = {
										{ value = "en", label = "English" } :: PickerOption,
										{ value = "xa", label = "Expanded" } :: PickerOption,
									},
								},
							})
						end,
					} :: Tab,
				},
			} :: unknown,
			UI.Text({
				text = notice,
				TextWrapped = true,
				Position = D2.new(0, 16, 1, -60),
				Size = D2.new(1, -32, 0, 56),
				AutomaticSize = ctx.types.Enum.AutomaticSize.None,
			}),
			UI.Sheet "WorldDetail" {
				title = "World",
				isPresented = detailOpen,
				detent = Compose.cell("large"),
				content = function(): Instance
					local item = services.tileById(selected:peek())
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
				actions = {
					{ id = "close", label = text("close.label"), role = "cancel" :: "cancel" } :: AlertAction,
				},
			},
		}
	end
	return {
		screen = screen,
		model = { services = services, destination = destination, tab = tab, query = query, locale = locale },
		steps = {
			settle = settle,
			open = open,
			search = function(value)
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
