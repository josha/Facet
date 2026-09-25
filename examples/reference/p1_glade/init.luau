--!strict
local seed = require("@self/content/seed")
local strings = require("@self/content/strings")
local supplyService = require("@self/services/supply")
local commerceService = require("@self/services/commerce")
local visitsService = require("@self/services/visits")
local referenceView = require("./view")
local Glade = { title = "Glade" }
function Glade.build(ctx)
	local Compose, Host, UI, runtime = ctx.Compose, ctx.Host, ctx.UI, ctx.runtime
	local D2, V2, C3, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Color3, ctx.types.Enum
	local view = referenceView(ctx)
	local owner = Compose.currentOwner()
	local now, locale = Compose.cell(0), Compose.cell("en")
	local function rooted(body)
		return Compose.withOwner(owner, body)
	end
	local supply = supplyService.new({ Compose = Compose, now = now, rooted = rooted })
	local commerce = commerceService.new({ Compose = Compose, now = now })
	local visits =
		visitsService.new({ Compose = Compose, now = now, rooted = rooted, charmTier = commerce.charmTier() })
	local section, search = Compose.cell("glades"), Compose.cell("")
	local selected, detailOpen, shopOpen, wisp, wispOpen =
		Compose.cell("mossholm"), Compose.cell(false), Compose.cell(false), Compose.cell(nil), Compose.cell(false)
	local notice, complete = Compose.cell(""), Compose.cell(false)
	local keeperName, keeperContact = Compose.cell(seed.KEEPER.displayName), Compose.cell(seed.KEEPER.contact)
	local draftName, draftContact = Compose.cell(seed.KEEPER.displayName), Compose.cell(seed.KEEPER.contact)
	local editOpen, resetOpen = Compose.cell(false), Compose.cell(false)
	local reducedMotion = Compose.cell(false)
	local guiService = ctx.guiService
	if guiService then
		reducedMotion:set(guiService.ReducedMotionEnabled)
		local preference = guiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
			reducedMotion:set(guiService.ReducedMotionEnabled)
		end)
		Compose.cleanup(function()
			preference:Disconnect()
		end)
	end
	local favorites = {}
	for _, glade in seed.GLADES do
		favorites[glade.id] = Compose.cell(glade.favourite)
	end
	local function L(key, subs)
		return strings.get(locale:peek(), key, subs)
	end
	local function text(key, subs)
		return function(use)
			return strings.get(use(locale), key, subs)
		end
	end
	local function advance(dt)
		now:update(function(value)
			return value + math.max(0, dt)
		end)
		commerce.update(now:peek())
	end
	local heartbeat = ctx.heartbeat or (if game then game:GetService("RunService").Heartbeat else nil)
	if heartbeat then
		local beat = heartbeat:Connect(advance)
		Compose.cleanup(function()
			beat:Disconnect()
		end)
	end
	local ready = Compose.formula(function(use)
		return use(supply.state(seed.TASK.glade, "dew")) == "full"
			and use(supply.nectarOf(seed.TASK.glade)) == seed.TASK_NECTAR
			and use(supply.state(seed.TASK.glade, "nectar")) == "full"
	end)
	Compose.watch(function(use)
		if use(ready) and not complete:peek() then
			complete:set(true)
			local visitor = visits.current(seed.TASK.glade):peek()
			if visitor and visitor.wisp == seed.TASK.wisp then
				visits.markPresented(visitor.id)
			end
			notice:set(L("task.toast", { wisp = L("wisp." .. seed.TASK.wisp), glade = L("glade." .. seed.TASK.glade) }))
		end
	end)
	local function reset()
		runtime:batch(function()
			supply.reset()
			commerce.reset()
			visits.reset()
			now:set(0)
			complete:set(false)
			keeperName:set(seed.KEEPER.displayName)
			keeperContact:set(seed.KEEPER.contact)
			for _, item in seed.GLADES do
				favorites[item.id]:set(item.favourite)
			end
			search:set("")
			notice:set("")
			detailOpen:set(false)
			shopOpen:set(false)
			section:set("glades")
		end)
	end
	local function saveKeeper()
		keeperName:set(draftName:peek())
		keeperContact:set(draftContact:peek())
		editOpen:set(false)
	end
	local function refill(id)
		supply.refill(id, "dew")
		notice:set(L("toast.refill", { glade = L("glade." .. id) }))
	end
	local function choose(id, nectarId)
		local nectar = seed.NECTAR_BY_ID[nectarId]
		if not nectar then
			return false
		end
		if nectar.premium then
			local held = commerce.satchelOf(nectarId)
			if held:peek() <= 0 then
				shopOpen:set(true)
				return false
			end
			held:update(function(count)
				return count - 1
			end)
		end
		supply.assign(id, nectarId)
		return true
	end
	local function open(id)
		selected:set(id)
		detailOpen:set(true)
	end
	local filtered = Compose.formula(function(use)
		local query, which = string.lower(use(search)), use(section)
		local result = {}
		for _, glade in seed.GLADES do
			local favorite = use(favorites[glade.id])
			if
				(which ~= "favorites" or favorite)
				and string.find(string.lower(strings.get(use(locale), "glade." .. glade.id)), query, 1, true)
			then
				table.insert(result, glade)
			end
		end
		return result
	end)
	local function scene(gladeId)
		local visitor = visits.current(gladeId)
		return Host.Frame "LivingGlade" {
			Size = D2.new(1, 0, 0, 190),
			ClipsDescendants = true,
			BorderSizePixel = 0,
			BackgroundColor3 = function(use)
				local definition = seed.GLADE_BY_ID[gladeId]
				local index = math.floor(
					((use(now) + definition.phaseOffset) % seed.DAY_SECONDS) / seed.DAY_SECONDS * #seed.PHASES
				) + 1
				local sky = seed.SKY[seed.PHASES[index]].high
				return C3.new(sky[1], sky[2], sky[3])
			end,
			Host.Frame "Meadow" {
				Position = D2.fromScale(0, 0.7),
				Size = D2.fromScale(1, 0.3),
				BackgroundColor3 = C3.new(seed.MOSS[1], seed.MOSS[2], seed.MOSS[3]),
				BorderSizePixel = 0,
			},
			Compose.show(function(use)
				return use(visitor) ~= nil
			end, function()
				local id = visitor:peek().wisp
				local definition = seed.WISP_BY_ID[id]
				return Host.Frame({
					Name = id,
					Size = D2.fromOffset(36, 36),
					AnchorPoint = V2.new(0.5, 0.5),
					Position = function(use)
						local at = if use(reducedMotion) then 0 else use(now)
						return D2.fromScale(0.5 + math.sin(at * 0.25) * 0.2, 0.45 + math.sin(at) * 0.04)
					end,
					BackgroundColor3 = C3.new(definition.core[1], definition.core[2], definition.core[3]),
					BorderSizePixel = 0,
					Host.UICorner({ CornerRadius = ctx.types.UDim.new(1, 0) }),
				})
			end),
		}
	end
	local function detail()
		local id = selected:peek()
		local options = {}
		for _, nectar in seed.NECTARS do
			table.insert(options, { value = nectar.id, label = L("nectar." .. nectar.id) })
		end
		local choice = Compose.cell(supply.nectarOf(id):peek())
		return view.page("GladeDetail", {
			view.text(text("glade." .. id), 28),
			scene(id),
			UI.Toggle "Favorite" { label = "Favorite glade", value = favorites[id] },
			view.text(function(use)
				return "Dew: " .. use(supply.state(id, "dew"))
			end),
			UI.ProgressView({ value = supply.level(id, "dew"), label = "Dew" }),
			view.action("Refill", "Refill dew", function()
				refill(id)
			end),
			view.text(function(use)
				return "Nectar: " .. use(supply.state(id, "nectar"))
			end),
			UI.ProgressView({ value = supply.level(id, "nectar"), label = "Nectar" }),
			UI.Picker "Nectar" {
				selected = choice,
				options = options,
				onChange = function(value)
					if choose(id, value) then
						choice:set(value)
					end
				end,
			},
			view.text("Recent visitors", 22),
			view.column("Visits", {
				view.list(visits.recent(id), function(current)
					local visit = current:peek()
					return view.action(visit.id, text("wisp." .. visit.wisp), function()
						wisp:set(visit.wisp)
						wispOpen:set(true)
					end)
				end),
			}),
		})
	end
	local function overview()
		return view.page("Glades", {
			view.text("Glade", 30),
			view.text("Prepare a home for a visiting wisp."),
			view.text(function(use)
				return if use(complete)
					then "Mossholm is ready. Your visiting wisp has a home."
					else "Refill Mossholm's dew and offer " .. strings.get(
						use(locale),
						"nectar." .. seed.TASK_NECTAR
					) .. "."
			end),
			view.action("Task", text("task.open", { glade = L("glade." .. seed.TASK.glade) }), function()
				open(seed.TASK.glade)
			end),
			UI.TextInput "Search" { value = search, placeholder = "Search glades" },
			view.column("Glades", {
				view.list(filtered, function(current)
					local glade = current:peek()
					return view.column(glade.id, {
						scene(glade.id),
						view.action("Open", text("glade." .. glade.id), function()
							open(glade.id)
						end),
						view.text(function(use)
							return "Dew "
								.. use(supply.state(glade.id, "dew"))
								.. " · Nectar "
								.. use(supply.state(glade.id, "nectar"))
						end),
					})
				end),
			}),
		})
	end
	local function wisps()
		return view.page("Wisps", {
			view.text("Wisps", 28),
			view.column("Visitors", {
				view.list(seed.WISPS, function(current)
					local item = current:peek()
					return view.column(item.id, {
						view.action("Open", text("wisp." .. item.id), function()
							wisp:set(item.id)
							wispOpen:set(true)
						end),
						view.text("Favorite nectar: " .. L("nectar." .. item.favourite)),
						view.text("Visits at " .. item.phase),
					})
				end),
			}),
		})
	end
	local function shop()
		local children = { view.text("Provisions", 28) }
		for _, pack in seed.PACKS do
			table.insert(
				children,
				view.column(pack.id, {
					view.text(`{L("nectar." .. pack.nectar)} × {pack.quantity}`),
					view.action("Buy", function(use)
						return if use(commerce.status(pack.id)) == "pending"
							then "Confirming…"
							else commerce.priceOf(pack.id)
					end, function()
						commerce.buyPack(pack.id)
					end, function(use)
						return use(commerce.status(pack.id)) ~= "pending"
					end),
					view.text(function(use)
						return use(commerce.status(pack.id))
							.. (if use(commerce.reason(pack.id)) then ": " .. use(commerce.reason(pack.id)) else "")
					end),
				})
			)
		end
		return view.page("Shop", children)
	end
	local function keeper()
		local children = {
			view.text("Keeper", 28),
			view.text(keeperName, 22),
			view.text(keeperContact),
			view.action("EditKeeper", text("keeper.edit"), function()
				draftName:set(keeperName:peek())
				draftContact:set(keeperContact:peek())
				editOpen:set(true)
			end),
			view.action("FreshStart", text("keeper.freshStart"), function()
				resetOpen:set(true)
			end),
			view.text(function(use)
				return "Charm: " .. use(commerce.charmTier())
			end),
			view.action("Shop", "Browse provisions", function()
				shopOpen:set(true)
			end),
		}
		for _, tier in seed.CHARM_TIERS do
			table.insert(
				children,
				view.action(tier.id, `Keeper's Charm: {tier.id} · {commerce.charmPriceOf(tier.id)}`, function()
					commerce.buyCharm(tier.id)
				end, function(use)
					return use(commerce.status(tier.id)) ~= "pending"
				end)
			)
			table.insert(children, view.text(commerce.status(tier.id)))
		end
		for _, nectar in seed.NECTARS do
			if nectar.premium then
				table.insert(
					children,
					view.text(function(use)
						return L("nectar." .. nectar.id) .. ": " .. tostring(use(commerce.satchelOf(nectar.id)))
					end)
				)
			end
		end
		table.insert(children, view.action("Restore", "Restore provisions", commerce.restore))
		table.insert(
			children,
			UI.Picker "Locale" {
				selected = locale,
				options = { { value = "en", label = "English" }, { value = "xa", label = "Expanded" } },
			}
		)
		return view.page("Keeper", children)
	end
	local function screen()
		return Host.Frame "Glade" {
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 1),
			UI.TabView "Destinations" {
				selection = section,
				style = "sidebarAdaptable",
				Size = D2.new(1, 0, 1, -64),
				tabs = {
					{ id = "glades", label = "Glades", content = overview },
					{ id = "favorites", label = "Favorites", content = overview },
					{ id = "wisps", label = "Wisps", content = wisps },
					{
						id = "flora",
						label = "Flora",
						content = function()
							return view.page("Flora", {
								view.list(seed.FLORA, function(current)
									local item = current:peek()
									return view.column(item.id, {
										view.text(text("flora." .. item.id), 24),
										view.text(text("flora.species." .. item.id)),
										Host.Frame({
											Size = D2.new(1, 0, 0, 80),
											BorderSizePixel = 0,
											BackgroundColor3 = C3.new(item.art[1], item.art[2], item.art[3]),
										}),
									})
								end),
							})
						end,
					},
					{ id = "keeper", label = "Keeper", content = keeper },
				},
			},
			UI.Text({
				text = notice,
				Position = D2.new(0, 16, 1, -60),
				Size = D2.new(1, -32, 0, 56),
				AutomaticSize = ctx.types.Enum.AutomaticSize.None,
				TextWrapped = true,
			}),
			UI.Sheet "KeeperEdit" {
				title = text("keeper.editTitle"),
				isPresented = editOpen,
				detent = Compose.cell("medium"),
				content = function()
					return view.column("Fields", {
						UI.TextInput "DisplayName" {
							value = draftName,
							placeholder = text("keeper.displayName"),
						},
						UI.TextInput "Contact" {
							value = draftContact,
							placeholder = text("keeper.contact"),
						},
						view.action("SaveKeeper", text("keeper.save"), saveKeeper),
						view.action("CancelKeeper", text("keeper.cancel"), function()
							editOpen:set(false)
						end),
					})
				end,
			},
			UI.Alert "Reset" {
				isPresented = resetOpen,
				title = Compose.formula(text("keeper.confirmTitle")),
				message = Compose.formula(text("keeper.confirmBody")),
				actions = {
					{ id = "cancel", label = text("keeper.keep"), role = "cancel" },
					{ id = "reset", label = text("keeper.startOver"), role = "destructive", onActivate = reset },
				},
			},
			UI.Sheet "Detail" {
				title = "Glade",
				isPresented = detailOpen,
				detent = Compose.cell("large"),
				content = detail,
			},
			UI.Sheet "Provisions" {
				title = "Provisions",
				isPresented = shopOpen,
				detent = Compose.cell("large"),
				content = shop,
			},
			UI.Sheet "Wisp" {
				title = "Wisp",
				isPresented = wispOpen,
				detent = Compose.cell("medium"),
				content = function()
					local id = wisp:peek()
					local item = seed.WISP_BY_ID[id]
					local last = visits.lastSeen(id)
					return view.column("Wisp", {
						view.text(text("wisp." .. id), 28),
						view.text("Favorite nectar: " .. L("nectar." .. item.favourite)),
						view.text(if last then "Last seen in " .. L("glade." .. last.glade) else "Not seen yet"),
					})
				end,
			},
		}
	end
	return {
		screen = screen,
		model = {
			supply = supply,
			commerce = commerce,
			visits = visits,
			now = now,
			complete = complete,
			keeperName = keeperName,
			keeperContact = keeperContact,
			draftName = draftName,
			draftContact = draftContact,
			section = section,
			selected = selected,
		},
		steps = {
			advance = advance,
			open = open,
			refill = refill,
			choose = choose,
			buy = commerce.buyPack,
			charm = commerce.buyCharm,
			restore = commerce.restore,
			reset = reset,
			saveKeeper = saveKeeper,
		},
		report = function()
			return {
				supplies = supply.dump(),
				commerce = commerce.dump(),
				visits = visits.dump(),
				complete = complete:peek(),
			}
		end,
	}
end
return Glade
