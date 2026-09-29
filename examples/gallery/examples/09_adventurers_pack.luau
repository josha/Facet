--!strict
local makeView = require("./showcase_view")
local art = require("./showcase_art")
local items = {
	{ id = "traveler", name = "Traveler's coat", slot = "coat", warmth = 1, power = 0, color = { 117, 89, 63 } },
	{ id = "frostcoat", name = "Frostguard coat", slot = "coat", warmth = 6, power = 0, color = { 77, 156, 189 } },
	{ id = "embercoat", name = "Ember cloak", slot = "coat", warmth = 3, power = 2, color = { 209, 107, 70 } },
	{ id = "boots", name = "Trail boots", slot = "boots", warmth = 1, power = 0, color = { 124, 91, 57 } },
	{ id = "snowboots", name = "Snowstep boots", slot = "boots", warmth = 4, power = 0, color = { 181, 211, 223 } },
	{ id = "sword", name = "Iron sword", slot = "tool", warmth = 0, power = 5, color = { 178, 191, 201 } },
	{ id = "lantern", name = "Sunstone lantern", slot = "tool", warmth = 2, power = 1, color = { 247, 193, 82 } },
	{ id = "pick", name = "Glacier pick", slot = "tool", warmth = 0, power = 8, color = { 113, 199, 211 } },
}
local byId = {}
for index, item in items do
	item.artIndex = index - 1
	byId[item.id] = item
end
return {
	title = "Adventurer's Pack",
	build = function(ctx: any)
		local UI, Host, C = ctx.UI, ctx.Host, ctx.Compose
		local V3, C3, E, D2 = ctx.types.Vector3, ctx.types.Color3, ctx.types.Enum, ctx.types.UDim2
		local view = makeView(ctx)
		local equipped = C.cell({ coat = "traveler", boots = "boots", tool = "sword" })
		local query, filter, path = C.cell(""), C.cell("all"), C.cell({})
		local hotbar = C.cell({ "sword", "lantern", "pick" })
		local width, loadoutOpen = C.cell(1100), C.cell(false)
		local metric = UI.environment().metricScale
		local wide = C.formula(function(use: any)
			return use(width) >= 850 * use(metric)
		end)
		local notice = C.cell("The frost cave needs 10 warmth. Find a warmer outfit.")
		local warmth = C.formula(function(use: any)
			local total = 0
			for _, id in use(equipped) do
				total += byId[id].warmth
			end
			return total
		end)
		local filtered = C.formula(function(use: any)
			local found = {}
			local search, category = string.lower(use(query)), use(filter)
			for _, item in items do
				if
					(category == "all" or item.slot == category)
					and string.find(string.lower(item.name), search, 1, true)
				then
					table.insert(found, item)
				end
			end
			return found
		end)
		local function equip(id)
			local item = byId[id]
			if not item then
				return false
			end
			local nextEquipment = table.clone(equipped:peek())
			nextEquipment[item.slot] = id
			equipped:set(nextEquipment)
			notice:set("Equipped " .. item.name .. ".")
			return true
		end
		local function assign(id, slot)
			if not byId[id] or byId[id].slot ~= "tool" or slot < 1 or slot > 3 then
				return false
			end
			local nextBar = table.clone(hotbar:peek())
			for index, value in nextBar do
				if value == id then
					nextBar[index] = nextBar[slot]
					break
				end
			end
			nextBar[slot] = id
			hotbar:set(nextBar)
			return true
		end
		local function reset()
			equipped:set({ coat = "traveler", boots = "boots", tool = "sword" })
			hotbar:set({ "sword", "lantern", "pick" })
			query:set("")
			filter:set("all")
			path:set({})
			notice:set("The frost cave needs 10 warmth. Find a warmer outfit.")
		end
		local function portrait()
			return view.stage("Explorer", function()
				return Host.Model "ExplorerModel" {
					view.part("Snow", V3.new(6, 0.2, 5), V3.new(0, -0.1, 0), C3.fromRGB(208, 224, 232)),
					view.part("Coat", V3.new(1.9, 2.1, 1), V3.new(0, 2.3, 0), function(use: any)
						return C3.fromRGB(table.unpack(byId[use(equipped).coat].color))
					end),
					view.part(
						"Head",
						V3.new(1.1, 1.1, 1.1),
						V3.new(0, 3.95, 0),
						C3.fromRGB(234, 194, 147),
						{ Shape = E.PartType.Ball }
					),
					view.part("LeftBoot", V3.new(0.8, 1.3, 1.2), V3.new(-0.55, 0.65, 0.15), function(use: any)
						return C3.fromRGB(table.unpack(byId[use(equipped).boots].color))
					end),
					view.part("RightBoot", V3.new(0.8, 1.3, 1.2), V3.new(0.55, 0.65, 0.15), function(use: any)
						return C3.fromRGB(table.unpack(byId[use(equipped).boots].color))
					end),
					view.part("Tool", V3.new(0.35, 2.8, 0.35), V3.new(1.4, 2.2, 0), function(use: any)
						return C3.fromRGB(table.unpack(byId[use(equipped).tool].color))
					end),
				}
			end, ctx.types.CFrame.lookAt(V3.new(7, 5, 9), V3.new(0, 2, 0)), 240)
		end
		local function details(entry)
			local item = byId[entry.value]
			return view.page("ItemDetails", item.name, "Compare it with your current equipment.", {
				portrait(),
				view.text("Comparison", function(use: any)
					local current = byId[use(equipped)[item.slot]]
					return `Equipped: {current.name}\nWarmth  {current.warmth} → {item.warmth}     Power  {current.power} → {item.power}`
				end),
				view.button("EquipItem", function(use: any)
					return if use(equipped)[item.slot] == item.id then "Equipped" else "Equip " .. item.name
				end, function()
					equip(item.id)
				end, function(use: any)
					return use(equipped)[item.slot] ~= item.id
				end),
				view.text("EquipmentNotice", notice),
			})
		end
		local function equipmentArt(item: any)
			return UI.Image "EquipmentArt" {
				image = art.equipment,
				scaleMode = "fit",
				Size = D2.fromScale(1, 1),
				ImageRectSize = ctx.types.Vector2.new(256, 256),
				ImageRectOffset = ctx.types.Vector2.new(item.artIndex % 4 * 256, math.floor(item.artIndex / 4) * 256),
			}
		end
		local function bag()
			return UI.NavigationStack "PackNavigation" {
				path = path,
				Size = D2.fromScale(1, 1),
				root = {
					title = "Adventurer's Pack",
					content = function()
						local measuredWidth = C.cell(600)
						local metricScale = UI.environment().metricScale
						return UI.Screen "BagPage" {
							gap = "m",
							view.text("Objective", "Prepare for the frost cave", "title"),
							UI.ProgressView "Warmth" { label = "Warmth", value = warmth, max = 10, showValue = true },
							UI.TextInput "SearchEquipment" {
								presentation = "search",
								value = query,
								placeholder = "Find equipment…",
							},
							UI.Picker "EquipmentCategory" {
								selected = filter,
								options = {
									{ value = "all", label = "All equipment" },
									{ value = "coat", label = "Coats" },
									{ value = "boots", label = "Boots" },
									{ value = "tool", label = "Tools" },
								},
							},
							C.show(function(use: any)
								return #use(filtered) == 0
							end, function()
								return view.text("NoEquipment", "No equipment matches. Try another search.")
							end),
							UI.VirtualGrid "EquipmentGrid" {
								from = filtered,
								key = "id",
								measure = true,
								gap = 12,
								itemSize = function(use: any)
									return 300 * use(metricScale)
								end,
								columns = function(use: any)
									return math.max(1, math.floor(use(measuredWidth) / (230 * use(metricScale))))
								end,
								Size = D2.new(1, 0, 0, 310),
								UI.fill(),
								ref = view.observeWidth(measuredWidth),
								render = function(current)
									local item: any = current:peek()
									local card = UI.Card("Item_" .. item.id)({
										title = item.name,
										caption = function(use: any)
											return `+{item.warmth} warmth · {item.power} power{if use(equipped)[item.slot]
													== item.id
												then " · Equipped"
												else ""}`
										end,
										artwork = function()
											return equipmentArt(item)
										end,
										imageAspectRatio = 1.6,
										AutomaticSize = E.AutomaticSize.Y,
										Size = D2.new(1, 0, 0, 0),
										onActivate = function()
											path:set({ { id = "item", value = item.id } })
										end,
									})
									if item.slot == "tool" then
										UI.draggable(
											card,
											{ payload = { kind = "tool", id = item.id }, armOnTap = true }
										)
									end
									return card
								end,
							},
						}
					end,
				},
				destinations = { item = { title = "Equipment", content = details } },
			}
		end
		local function loadout()
			return view.page(
				"LoadoutPage",
				"Ready for the cold?",
				"Your outfit changes as you equip items from the pack.",
				{
					portrait(),
					UI.ProgressView { label = "Warmth", value = warmth, max = 10, showValue = true },
					view.text("EquippedSummary", function(use: any)
						local e = use(equipped)
						return byId[e.coat].name .. " · " .. byId[e.boots].name .. " · " .. byId[e.tool].name
					end),
					view.button("EnterCave", "Enter the frost cave", function()
						notice:set("Expedition ready! Your gear keeps you warm inside the frost cave.")
					end, function(use: any)
						return use(warmth) >= 10
					end),
					view.text("ExpeditionNotice", notice),
					view.button("ResetPack", "Pack again", reset),
				}
			)
		end
		local function belt()
			local slots = {}
			for slot = 1, 3 do
				local target = view.button("Slot" .. slot, function(use: any)
					return `{slot} · {byId[use(hotbar)[slot]].name}`
				end, function()
					equip(hotbar:peek()[slot])
				end)
				UI.dropTarget(target, {
					accepts = function(payload)
						return payload.kind == "tool"
					end,
					onDrop = function(payload)
						assign(payload.id, slot)
					end,
				})
				table.insert(slots, target)
			end
			return UI.VStack "HotbarDock" {
				width = "fill",
				gap = "s",
				view.text(
					"HotbarHint",
					"HOTBAR · Drag a tool here to rearrange it. Select a slot to equip.",
					"caption"
				),
				UI.Grid "HotbarSlots" { columns = 3, gap = "s", cellHeight = 52, table.unpack(slots) },
			}
		end
		local function screen()
			return UI.ScrollView "AdventurersPack" {
				padding = "m",
				gap = "s",
				ref = view.observeWidth(width),
				UI.HStack {
					width = "fill",
					gap = "s",
					wrap = true,
					view.button("ShowLoadout", "Inspect loadout", function()
						loadoutOpen:set(true)
					end),
					view.button("ResetInventory", "Start over", reset),
				},
				Host.Frame "EquipmentWorkbench" {
					BackgroundTransparency = 1,
					Size = D2.new(1, 0, 0, 560),
					Host.Frame "Backpack" {
						BackgroundTransparency = 1,
						Size = function(use: any)
							return D2.new(if use(wide) then 0.66 else 1, if use(wide) then -12 else 0, 1, 0)
						end,
						bag(),
					},
					C.show(wide, function()
						return Host.Frame "CharacterPanel" {
							BackgroundTransparency = 1,
							Position = D2.fromScale(0.66, 0),
							Size = D2.fromScale(0.34, 1),
							loadout(),
						}
					end),
				},
				belt(),
				UI.Sheet "LoadoutSheet" {
					title = "Expedition loadout",
					isPresented = loadoutOpen,
					closeButton = true,
					detent = C.cell("large"),
					content = loadout,
				},
			}
		end
		return {
			screen = screen,
			report = function()
				return { warmth = warmth:peek(), equipped = equipped:peek(), hotbar = hotbar:peek(), path = path:peek() }
			end,
			equip = equip,
			assign = assign,
			reset = reset,
			model = { query = query, filter = filter, filtered = filtered, path = path, loadoutOpen = loadoutOpen },
		}
	end,
}
