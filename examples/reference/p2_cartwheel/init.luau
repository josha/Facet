--!strict
local data = require("@self/content/data")
local strings = require("@self/content/strings")
local clockService = require("@self/services/clock")
local orderService = require("@self/services/order_service")
local statsService = require("@self/services/stats_service")
local ambientService = require("@self/services/ambient_service")
local entitlementService = require("@self/services/entitlement_service")
local identityService = require("@self/services/identity_service")
local commandsService = require("@self/services/commands")
local referenceView = require("./view")
local Cartwheel = { title = "Cartwheel" }
function Cartwheel.build(ctx)
	local Compose, UI, Host = ctx.Compose, ctx.UI, ctx.Host
	local D2 = ctx.types.UDim2
	local view = referenceView(ctx)
	local S = strings.new("en")
	local clock = clockService.new(Compose, { start = 0 })
	local orders = orderService.new({ Compose = Compose, clock = clock, seed = 1 })
	local stats = statsService.new({ Compose = Compose, seed = 1 })
	local ambient = ambientService.new({ seed = 1 })
	local entitlement = entitlementService.new({ Compose = Compose })
	local identity = identityService.new({ Compose = Compose })
	local notice = Compose.cell("")
	local commands = commandsService.new({
		Compose = Compose,
		clock = clock,
		strings = S,
		toast = function(_, message)
			notice:set(message)
		end,
	})
	local section, query, timeframe = Compose.cell("dashboard"), Compose.cell(""), Compose.cell("today")
	local selectedBrew, detailOpen = Compose.cell(0), Compose.cell(false)
	local selectedPlaza = Compose.cell(data.plazas[1].id)
	local ledgerTimeframe = Compose.cell("twoWeeks")
	local draftName, selectedPotion = Compose.cell("New potion"), Compose.cell("scratch")
	local drafts = {}
	local base, essence, garnish = Compose.cell(data.bases[1].id), Compose.cell(""), Compose.cell("")
	local guild, watchword, signupOpen, celebration =
		Compose.cell(""), Compose.cell(""), Compose.cell(false), Compose.cell(false)
	local function advance(dt)
		clock.advance(dt)
	end
	local heartbeat = ctx.heartbeat or (if game then game:GetService("RunService").Heartbeat else nil)
	if heartbeat then
		local beat = heartbeat:Connect(advance)
		Compose.cleanup(function()
			beat:Disconnect()
		end)
	end
	Compose.cleanup(clock.dispose)
	Compose.cleanup(commands.dispose)
	orders.onCompleted(function(brew)
		stats.recordCompletion(brew)
		celebration:set(true)
		notice:set(`Brew #{brew.id} collected · {brew.bottles} bottles`)
	end)
	local function brewCommand(id, verb)
		local previous = orders.snapshotOf(id)
		return commands.submit({
			id = verb .. ":" .. id,
			decide = function()
				if verb == "start" then
					return orders.canStart(previous.status)
				end
				return orders.canFinish(previous.status)
			end,
			confirm = function()
				if verb == "start" then
					orders.applyStart(id)
				else
					orders.applyFinish(id)
					orders.notifyCompleted(id)
				end
			end,
		})
	end
	local function purchase(product)
		return commands.submit({
			id = "buy:" .. product,
			decide = function()
				return entitlement.decide(product)
			end,
			confirm = function()
				entitlement.grant(product)
			end,
		})
	end
	local function signup()
		return commands.submit({
			id = "signup",
			decide = function()
				return identity.decide(guild:peek())
			end,
			confirm = function()
				identity.signIn(guild:peek())
				signupOpen:set(false)
				notice:set("Welcome, " .. guild:peek())
			end,
		})
	end
	local function openBrew(id)
		selectedBrew:set(id)
		detailOpen:set(true)
	end
	local rows = Compose.formula(function(use)
		local result, q = {}, string.lower(use(query))
		for _, brew in use(orders.brews) do
			if string.find(string.lower(orders.searchText(brew)), q, 1, true) then
				table.insert(result, brew)
			end
		end
		return result
	end)
	local function brewRow(current)
		local brew = current:peek()
		return view.column(tostring(brew.id), {
			view.action("Open", function(use)
				local row = use(current)
				return `Brew #{row.id} · {row.bottles} bottles · {row.status}`
			end, function()
				openBrew(brew.id)
			end),
			view.action("Advance", function(use)
				return if use(current).status == "ready" then "Collect brew" else "Start brewing"
			end, function()
				brewCommand(brew.id, if orders.statusOf(brew.id) == "ready" then "finish" else "start")
			end, function(use)
				local status = use(current).status
				return status == "new" and use(commands.status("start:" .. brew.id)) ~= "pending"
					or status == "ready" and use(commands.status("finish:" .. brew.id)) ~= "pending"
			end),
		})
	end
	local function brewsPage()
		return Host.Frame "Brews" {
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			UI.TextInput "Search" {
				value = query,
				placeholder = "Search brews",
				Size = D2.new(1, -32, 0, 44),
				Position = D2.fromOffset(16, 8),
			},
			UI.VirtualList "BrewList" {
				from = rows,
				key = function(item)
					return item.id
				end,
				itemSize = 108,
				gap = 8,
				Position = D2.fromOffset(16, 60),
				Size = D2.new(1, -32, 1, -76),
				render = brewRow,
			},
		}
	end
	local function chart(title, series)
		local bars = {}
		local largest = 1
		for _, count in series do
			largest = math.max(largest, count)
		end
		for index, count in series do
			table.insert(
				bars,
				Host.Frame({
					Name = tostring(index),
					Size = D2.new(1 / #series, -2, count / largest, 0),
					Position = D2.new((index - 1) / #series, 0, 1 - count / largest, 0),
					BackgroundColor3 = ctx.types.Color3.fromRGB(108, 146, 124),
					BorderSizePixel = 0,
				})
			)
		end
		local p = { Name = title, BackgroundTransparency = 1, Size = D2.new(1, 0, 0, 140) }
		for _, node in bars do
			table.insert(p, node)
		end
		return Host.Frame(p)
	end
	local function dashboard()
		return view.page("Dashboard", {
			view.text("Cartwheel", 30),
			view.text("Brew potions, serve the waiting cart, and choose your next market pitch."),
			view.text(function(use)
				use(orders.brews)
				use(stats.version)
				return `{orders.count()} brews · {stats.collectedBottles()} bottles collected`
			end),
			view.action("Brews", "Open brew queue", function()
				section:set("brews")
			end),
			view.text("Recommended pitch: " .. ambient.recommendedPlaza().name),
			UI.Picker "Timeframe" {
				selected = timeframe,
				options = {
					{ value = "today", label = "Today" },
					{ value = "week", label = "Week" },
					{ value = "month", label = "Month" },
					{ value = "year", label = "Year" },
				},
			},
			view.text("Top five", 24),
			view.column("TopFive", {
				view.list(function(use)
					use(stats.version)
					local result = {}
					for _, row in stats.topFive(use(timeframe)) do
						table.insert(result, { id = row.potion.id, name = row.potion.name, bottles = row.bottles })
					end
					return result
				end, function(current)
					return view.text(function(use)
						local row = use(current)
						return row.name .. " · " .. row.bottles .. " bottles"
					end)
				end),
			}),
		})
	end
	local function selectPotion(id)
		drafts[selectedPotion:peek()] =
			{ name = draftName:peek(), base = base:peek(), essence = essence:peek(), garnish = garnish:peek() }
		local potion = data.potionById(id)
		local record = drafts[id]
			or {
				name = if potion then potion.name else "New potion",
				base = if potion then potion.base else data.bases[1].id,
				essence = if potion then potion.essence or "" else "",
				garnish = if potion then potion.garnish or "" else "",
			}
		ctx.runtime:batch(function()
			selectedPotion:set(id)
			draftName:set(record.name)
			base:set(record.base)
			essence:set(record.essence)
			garnish:set(record.garnish)
		end)
	end
	local function pickerOptions(items, optional)
		local options = if optional then { { value = "", label = "None" } } else {}
		for _, item in items do
			table.insert(options, { value = item.id, label = item.name })
		end
		return options
	end
	local function workbench()
		return view.page("Workbench", {
			view.text("Workbench", 28),
			UI.TextInput "PotionName" { value = draftName, placeholder = "Potion name" },
			view.action("NewPotion", "New potion", function()
				selectPotion("scratch")
			end),
			UI.Picker "Base" { selected = base, options = pickerOptions(data.bases, false) },
			UI.Picker "Essence" { selected = essence, options = pickerOptions(data.essences, true) },
			UI.Picker "Garnish" { selected = garnish, options = pickerOptions(data.garnishes, true) },
			view.text(function(use)
				local values = data.attributesOf(use(base), use(essence), use(garnish))
				local parts = {}
				for index, name in data.ATTRIBUTES do
					table.insert(parts, name .. " " .. tostring(values[index]))
				end
				return table.concat(parts, " · ")
			end),
			view.text("Potion gallery", 24),
			view.column("Potions", {
				view.list(data.potions, function(current)
					local potion = current:peek()
					return view.column(potion.id, {
						Host.ImageLabel "Potion" {
							Image = potion.mark.image,
							BackgroundTransparency = 1,
							Size = D2.fromOffset(48, 48),
						},
						view.action("Mix", potion.name, function()
							selectPotion(potion.id)
						end),
					})
				end),
			}),
		})
	end
	local function ledger()
		return view.page("Ledger", {
			view.text("Ledger", 28),
			UI.Picker "LedgerTimeframe" {
				selected = ledgerTimeframe,
				options = {
					{ value = "twoWeeks", label = "Two weeks" },
					{ value = "month", label = "Month · Full Ledger" },
					{ value = "year", label = "Year · Full Ledger" },
				},
			},
			Compose.show(function(use)
				return use(ledgerTimeframe) ~= "twoWeeks" and not use(entitlement.fullLedger)
			end, function()
				return view.column("Unlock", {
					view.text("Unlock the Full Ledger to inspect all trading history."),
					view.action("Buy", `Unlock Full Ledger · {data.fullLedgerCredits} Credits`, function()
						purchase("ledger")
					end, function(use)
						return use(commands.status("buy:ledger")) ~= "pending"
					end),
				})
			end, function()
				return view.column("Trading", {
					Compose.keyed({
						from = function(use)
							return { use(ledgerTimeframe) }
						end,
						key = function(id)
							return id
						end,
						render = function(current)
							local period = current:peek()
							local rows = {}
							for _, plaza in data.plazas do
								table.insert(
									rows,
									view.column(plaza.id, {
										view.text(plaza.name, 22),
										chart(plaza.name, stats.series(plaza.id, period)),
									})
								)
							end
							return view.column("Markets", rows)
						end,
					}),
				})
			end),
		})
	end
	local function chatter()
		return view.page("Chatter", {
			view.text("Chatter", 28),
			view.action("Subscribe", "Join Chatter+ · 9 Credits monthly", function()
				purchase("chatter")
			end, function(use)
				return not use(entitlement.chatterPlus) and use(commands.status("buy:chatter")) ~= "pending"
			end),
			view.column("Posts", {
				view.list(function(use)
					local result = table.clone(data.chatterPosts)
					if use(entitlement.chatterPlus) then
						for _, post in data.chatterBonusPosts do
							table.insert(result, post)
						end
					end
					return result
				end, function(current)
					local post = current:peek()
					local tags = {}
					for _, index in post.tags do
						table.insert(tags, data.chatterTags[index])
					end
					return view.column(post.id, {
						view.text(post.who, 22),
						view.text(data.potionById(post.potion).name .. " · " .. tostring(post.minutes) .. " min ago"),
						view.text(table.concat(tags, " · ")),
					})
				end),
			}),
		})
	end
	local function marketStage(plaza)
		local V3, CF = ctx.types.Vector3, ctx.types.CFrame
		return UI.Stage "MarketScene" {
			Size = D2.new(1, 0, 0, 220),
			camera = CF.lookAt(V3.new(6, 4, 9), V3.new(0, 1, 0)),
			content = function(sceneRuntime, world)
				return sceneRuntime.mount(function()
					return Host.Model({
						Name = plaza.name,
						Host.Part "Ground" {
							Anchored = true,
							Size = V3.new(16, 0.3, 12),
							CFrame = CF.new(0, -0.2, 0),
							Color = ctx.types.Color3.fromRGB(87, 103, 83),
						},
						Host.Part "Cart" {
							Anchored = true,
							Size = V3.new(4, 1.5, 2),
							CFrame = CF.new(0, 1, 0),
							Color = ctx.types.Color3.fromRGB(118, 79, 49),
							Material = ctx.types.Enum.Material.Wood,
						},
						Host.Part "Canopy" {
							Anchored = true,
							Size = V3.new(5, 0.2, 3),
							CFrame = CF.new(0, 3, 0),
							Color = ctx.types.Color3.fromRGB(168, 94, 69),
						},
						Host.Part "LeftPost" {
							Anchored = true,
							Size = V3.new(0.2, 3, 0.2),
							CFrame = CF.new(-1.8, 1.5, 0.7),
							Color = ctx.types.Color3.fromRGB(118, 79, 49),
						},
						Host.Part "RightPost" {
							Anchored = true,
							Size = V3.new(0.2, 3, 0.2),
							CFrame = CF.new(1.8, 1.5, 0.7),
							Color = ctx.types.Color3.fromRGB(118, 79, 49),
						},
						Compose.keyed({
							from = function()
								return { 1, 2, 3, 4, 5 }
							end,
							key = function(value)
								return value
							end,
							render = function(current)
								local index = current:peek()
								return Host.Part({
									Name = "Potion" .. index,
									Anchored = true,
									Shape = ctx.types.Enum.PartType.Cylinder,
									Size = V3.new(0.6, 0.3, 0.3),
									CFrame = CF.new(-1.5 + index * 0.5, 2, 0) * CF.Angles(0, 0, math.pi / 2),
									Color = ctx.types.Color3.fromHSV(index / 7, 0.5, 0.8),
									Material = ctx.types.Enum.Material.Glass,
								})
							end,
						}),
					})
				end, world)
			end,
		}
	end
	local function plazas()
		return view.page("Plazas", {
			view.text("Plazas", 28),
			UI.Picker "Market" { selected = selectedPlaza, options = pickerOptions(data.plazas, false) },
			view.column("Conditions", {
				Compose.keyed({
					from = function(use)
						return { use(selectedPlaza) }
					end,
					key = function(id)
						return id
					end,
					render = function(current)
						local id = current:peek()
						local plaza = data.plazaById(id)
						local weather = ambient.forPlaza(id)
						return view.column(id, {
							view.text(plaza.name, 24),
							view.text(plaza.pitch),
							marketStage(plaza),
							view.text(
								if weather.damp then "Damp spell during trading hours" else "Clear trading hours"
							),
							view.text(`Cloud cover {weather.cloud}%`),
							chart("Daylight", weather.samples),
						})
					end,
				}),
			}),
		})
	end
	local function screen()
		return Host.Frame "Cartwheel" {
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			UI.TabView "Destinations" {
				selection = section,
				style = "sidebarAdaptable",
				Size = D2.new(1, 0, 1, -112),
				tabs = {
					{ id = "dashboard", label = "Dashboard", content = dashboard },
					{ id = "brews", label = "Brews", content = brewsPage },
					{ id = "workbench", label = "Workbench", content = workbench },
					{ id = "ledger", label = "Ledger", content = ledger },
					{ id = "chatter", label = "Chatter", content = chatter },
					{ id = "plazas", label = "Plazas", content = plazas },
				},
			},
			UI.Button "Guild" {
				label = function(use)
					return if use(identity.signedIn)
						then "Sign out of " .. use(identity.guildName)
						else "Join the guild"
				end,
				Position = D2.new(0, 16, 1, -106),
				onActivate = function()
					if identity.signedIn:peek() then
						identity.signOut()
					else
						signupOpen:set(true)
					end
				end,
			},
			UI.Label({
				text = notice,
				TextWrapped = true,
				Position = D2.new(0, 16, 1, -60),
				Size = D2.new(1, -32, 0, 56),
				AutomaticSize = ctx.types.Enum.AutomaticSize.None,
			}),
			UI.Sheet "BrewDetail" {
				title = "Brew",
				isPresented = detailOpen,
				detent = Compose.cell("large"),
				content = function()
					local brew = orders.byId(selectedBrew:peek())
					local parts = { view.text(`Brew #{brew.id}`, 28) }
					for _, item in brew.items do
						table.insert(parts, view.text(data.potionById(item.potion).name .. " × " .. item.bottles))
					end
					table.insert(
						parts,
						view.text(function(use)
							use(clock.nowSignal)
							use(orders.brews)
							return "Status: "
								.. orders.statusOf(brew.id)
								.. (
									if orders.remaining(brew.id)
										then ` · {math.ceil(orders.remaining(brew.id))} s`
										else ""
								)
						end)
					)
					table.insert(
						parts,
						view.action("Start", "Start brewing", function()
							brewCommand(brew.id, "start")
						end, function(use)
							use(orders.brews)
							return orders.statusOf(brew.id) == "new"
								and use(commands.status("start:" .. brew.id)) ~= "pending"
						end)
					)
					table.insert(
						parts,
						view.action("Collect", "Collect brew", function()
							brewCommand(brew.id, "finish")
						end, function(use)
							use(orders.brews)
							return orders.statusOf(brew.id) == "ready"
								and use(commands.status("finish:" .. brew.id)) ~= "pending"
						end)
					)
					return view.page("Brew", parts)
				end,
			},
			UI.Sheet "Signup" {
				title = "Join the guild",
				isPresented = signupOpen,
				detent = Compose.cell("medium"),
				content = function()
					return view.column("Form", {
						UI.TextInput "GuildName" {
							value = guild,
							placeholder = "Guild name",
							maxLength = 24,
							validate = identity.normalize,
						},
						UI.TextInput "Watchword" {
							value = watchword,
							placeholder = "Watchword",
							maxLength = 32,
						},
						view.text(commands.reason("signup")),
						view.action("Submit", "Join", signup, function(use)
							return use(guild) ~= ""
								and use(watchword) ~= ""
								and use(commands.status("signup")) ~= "pending"
						end),
					})
				end,
			},
			UI.Alert "Celebration" {
				isPresented = celebration,
				title = "Brew collected!",
				message = notice,
				actions = { { id = "done", label = "Keep brewing" } },
			},
		}
	end
	return {
		screen = screen,
		model = {
			clock = clock,
			orders = orders,
			stats = stats,
			commands = commands,
			entitlement = entitlement,
			identity = identity,
			section = section,
			ledgerTimeframe = ledgerTimeframe,
			draftName = draftName,
			selectedPotion = selectedPotion,
			base = base,
			essence = essence,
			garnish = garnish,
		},
		steps = {
			advance = advance,
			openBrew = openBrew,
			start = function(id)
				return brewCommand(id, "start")
			end,
			collect = function(id)
				return brewCommand(id, "finish")
			end,
			purchase = purchase,
			selectPotion = selectPotion,
			signup = function(name, password)
				guild:set(name)
				watchword:set(password)
				return signup()
			end,
		},
		report = function()
			return {
				orders = orders.dump(),
				stats = stats.dump(),
				entitlement = entitlement.dump(),
				identity = identity.dump(),
				commands = commands.dump(),
			}
		end,
	}
end
return Cartwheel
