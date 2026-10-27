--!strict

type ExampleContext = typeof(require("@repo/examples/types").Context)
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Use = <T>(ReadOnlyValue<T>) -> T
type StringPickerOption = typeof(require("@repo/tools/typecheck/aliases").StringPickerOption)
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type ZStackProps = typeof(require("@repo/tools/typecheck/aliases").ZStackProps)
type ScrollViewProps = typeof(require("@repo/tools/typecheck/aliases").ScrollViewProps)
type GridProps = typeof(require("@repo/tools/typecheck/aliases").GridProps)
type CardSpec = typeof(require("@repo/tools/typecheck/aliases").CardSpec)
type TextInputProps = typeof(require("@repo/tools/typecheck/aliases").TextInputProps)
type Entry = { id: string, value: string? }
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
type Item = typeof(items[1])
local byId: { [string]: Item } = {}
for index, item in items do
	item.artIndex = index - 1
	byId[item.id] = item
end
return {
	title = "Adventurer's Pack",
	build = function(ctx: ExampleContext)
		local UI, Host, C = ctx.UI, ctx.Host, ctx.Compose
		local V3, C3, E, D2 = ctx.types.Vector3, ctx.types.Color3, ctx.types.Enum, ctx.types.UDim2
		local view = makeView(ctx)
		local outfit: { [string]: string } = { coat = "traveler", boots = "boots", tool = "sword" }
		local entries: { Entry } = {}
		local equipped = C.cell(outfit)
		local query, filter, path = C.cell(""), C.cell("all"), C.cell(entries)
		local resetVersion = C.cell(0)
		local hotbar = C.cell({ "sword", "lantern", "pick" })
		local width, loadoutOpen, roomy = C.cell(1100), C.cell(false), C.cell(true)
		local wideAt = UI.environment().scaled(850)
		local toolPayloads: { [string]: { kind: string, id: string } } = {}
		local toolOf: { [unknown]: string } = {}
		for _, item in items do
			if item.slot == "tool" then
				local payload = { kind = "tool", id = item.id }
				toolPayloads[item.id] = payload
				toolOf[payload] = item.id
			end
		end
		local wide = C.formula(function(use: Use)
			return use(width) >= use(wideAt)
		end)
		local notice = C.cell("The frost cave needs 10 warmth. Find a warmer outfit.")
		local warmth = C.formula(function(use: Use)
			local total = 0
			for _, id in use(equipped) do
				total += byId[id].warmth
			end
			return total
		end)
		local filtered = C.formula(function(use: Use)
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
		local function equip(id: string)
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
		local function assign(id: string, slot: number)
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
			notice:set(`Assigned {byId[id].name} to slot {slot}.`)
			return true
		end
		local function reset()
			resetVersion:set(resetVersion:peek() + 1)
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
					view.part("Coat", V3.new(1.9, 2.1, 1), V3.new(0, 2.3, 0), function(use: Use)
						return C3.fromRGB(table.unpack(byId[use(equipped).coat].color))
					end),
					view.part(
						"Head",
						V3.new(1.1, 1.1, 1.1),
						V3.new(0, 3.95, 0),
						C3.fromRGB(234, 194, 147),
						{ Shape = E.PartType.Ball }
					),
					view.part("LeftBoot", V3.new(0.8, 1.3, 1.2), V3.new(-0.55, 0.65, 0.15), function(use: Use)
						return C3.fromRGB(table.unpack(byId[use(equipped).boots].color))
					end),
					view.part("RightBoot", V3.new(0.8, 1.3, 1.2), V3.new(0.55, 0.65, 0.15), function(use: Use)
						return C3.fromRGB(table.unpack(byId[use(equipped).boots].color))
					end),
					view.part("Tool", V3.new(0.35, 2.8, 0.35), V3.new(1.4, 2.2, 0), function(use: Use)
						return C3.fromRGB(table.unpack(byId[use(equipped).tool].color))
					end),
				}
			end, ctx.types.CFrame.lookAt(V3.new(7, 5, 9), V3.new(0, 2, 0)), 240)
		end
		local function equipmentArt(item: Item, maximum: number?)
			local cap = if maximum then UI.environment().scaled(maximum) else nil
			return UI.Image "EquipmentArt" {
				image = art.equipment,
				AnchorPoint = ctx.types.Vector2.new(0.5, 0.5),
				Position = D2.fromScale(0.5, 0.5),
				scaleMode = "fit",
				Size = D2.fromScale(1, 1),
				ImageRectSize = ctx.types.Vector2.new(256, 256),
				ImageRectOffset = ctx.types.Vector2.new(item.artIndex % 4 * 256, math.floor(item.artIndex / 4) * 256),
				if cap
					then Host.UISizeConstraint {
						MaxSize = function(use: Use)
							local extent = use(cap)
							return ctx.types.Vector2.new(extent, extent)
						end,
					}
					else nil,
			}
		end
		local function details(entry: Entry?)
			local item = byId[assert(entry and entry.value)]
			local body = UI.ZStack "ItemDetails" { width = "fill", height = "fill" }
			local room = UI.environment(body)
			local detailWidth, detailHeight = room.scaled(760), room.scaled(420)
			local function decision()
				return UI.VStack "EquipmentDecision" {
					width = "fill",
					gap = "s",
					align = "stretch",
					view.text("ItemName", item.name, "title"),
					view.text("Comparison", function(use: Use)
						local current = byId[use(equipped)[item.slot]]
						return `Equipped: {current.name}\nWarmth  {current.warmth} → {item.warmth}\nPower  {current.power} → {item.power}`
					end),
					UI.Button "EquipItem" {
						appearance = "emphasis",
						label = function(use: Use)
							return if use(equipped)[item.slot] == item.id then "Equipped" else "Equip " .. item.name
						end,
						onActivate = function()
							equip(item.id)
						end,
						enabled = function(use: Use)
							return use(equipped)[item.slot] ~= item.id
						end,
					},
					view.text("EquipmentNotice", notice, "caption"),
					if item.slot == "tool"
						then UI.VStack({
							width = "fill",
							gap = "s",
							view.text("AssignTool", "Assign to hotbar", "label"),
							UI.Grid({
								columns = 3,
								gap = "s",
								view.button("Assign1", "Slot 1", function()
									assign(item.id, 1)
								end),
								view.button("Assign2", "Slot 2", function()
									assign(item.id, 2)
								end),
								view.button("Assign3", "Slot 3", function()
									assign(item.id, 3)
								end),
							} :: GridProps),
						} :: StackProps)
						else nil,
				}
			end
			UI.ZStack({
				Parent = C.static(body),
				width = "fill",
				height = "fill",
				alignH = "center",
				alignV = "center",
				C.show(function(use: Use)
					return use(room.viewportWidth) >= 560
				end, function()
					return UI.HStack({
						width = function(use: Use)
							return math.min(use(room.viewportWidth), use(detailWidth))
						end,
						height = function(use: Use)
							return math.min(use(room.viewportHeight), use(detailHeight))
						end,
						gap = "m",
						padding = "s",
						UI.ZStack({
							width = "fill",
							height = "fill",
							UI.fill() :: Child,
							equipmentArt(item, 420) :: Child,
						} :: ZStackProps) :: Child,
						UI.ScrollView({
							width = 300,
							height = "fill",
							padding = "s",
							UI.VStack "CenteredDecision" {
								width = "fill",
								height = "fill",
								distribute = "center",
								decision(),
							},
						} :: ScrollViewProps) :: Child,
					} :: StackProps)
				end, function()
					return UI.ScrollView({
						width = "fill",
						height = "fill",
						gap = "s",
						padding = "s",
						UI.ZStack({
							width = "fill",
							height = function(use: Use)
								return math.max(80, math.min(160, use(room.viewportHeight) * 0.3))
							end,
							equipmentArt(item),
						} :: ZStackProps),
						decision(),
					} :: ScrollViewProps)
				end),
			} :: ZStackProps)
			return body
		end
		local function bag()
			local categories: { StringPickerOption } = {
				{ value = "all", label = "All equipment" },
				{ value = "coat", label = "Coats" },
				{ value = "boots", label = "Boots" },
				{ value = "tool", label = "Tools" },
			}
			return UI.NavigationStack "PackNavigation" {
				path = path,
				Size = D2.fromScale(1, 1),
				root = {
					title = "Adventurer's Pack",
					chrome = "hidden",
					content = function(): Instance
						local measuredWidth = C.cell(600)
						local env = UI.environment()
						local cardSize, columnWidth = env.scaled(104), env.scaled(320)
						return UI.Screen "BagPage" {
							gap = "s",
							C.show(roomy, function()
								return UI.VStack({
									width = "fill",
									gap = "s",
									view.text("Objective", "Prepare for the frost cave", "label"),
									UI.ProgressView "Warmth" {
										label = "Warmth",
										value = warmth,
										max = 10,
										showValue = true,
									},
								} :: StackProps)
							end),
							UI.HStack({
								width = "fill",
								gap = "s",
								UI.TextInput "SearchEquipment"({
									presentation = "search",
									value = query,
									placeholder = "Find equipment…",
									UI.fill(),
								} :: TextInputProps) :: Child,
								view.button("EquipmentFilters", function(use: Use)
									local selected = use(filter)
									for _, category in categories do
										if category.value == selected and selected ~= "all" then
											return `Filters: {category.label}`
										end
									end
									return "Filters"
								end, function()
									path:set({ { id = "filters" } })
								end) :: Child,
							} :: StackProps),
							C.show(function(use: Use)
								return #use(filtered) == 0
							end, function()
								return view.text("NoEquipment", "No equipment matches. Change the search or filters.")
							end),
							UI.VirtualGrid "EquipmentGrid" {
								from = filtered,
								scrollReset = function(use: Use)
									return `{use(resetVersion)}:{use(filter)}:{use(query)}`
								end,
								key = "id",
								measure = true,
								gap = 12,
								itemSize = function(use: Use)
									return use(cardSize)
								end,
								columns = function(use: Use)
									return math.max(1, math.floor(use(measuredWidth) / use(columnWidth)))
								end,
								Size = D2.fromScale(1, 1),
								UI.fill(),
								ref = function(node: ScrollingFrame)
									view.observeWidth(measuredWidth, node)
								end,
								recycle = false,
								render = function(current: ReadOnlyValue<Item>): GuiObject
									local item = current:peek()
									local card = UI.HStack("Item_" .. item.id)({
										width = "fill",
										gap = "s",
										align = "center",
										UI.ZStack({ width = 80, height = 80, equipmentArt(item) } :: ZStackProps),
										UI.Card({
											title = item.name,
											caption = function(use: Use)
												return `{item.warmth} warmth · {item.power} power{if use(equipped)[item.slot]
														== item.id
													then " · Equipped"
													else ""}`
											end,
											AutomaticSize = E.AutomaticSize.Y,
											Size = D2.new(1, 0, 0, 0),
											UI.fill(),
											onActivate = function()
												path:set({ { id = "item", value = item.id } })
											end,
										} :: CardSpec),
										if item.slot == "tool"
											then C.show(wide, function()
												local move = UI.Button("Move_" .. item.id)({
													label = "Move",
													appearance = "utility",
												})
												UI.draggable(move, { payload = toolPayloads[item.id], armOnTap = true })
												return move
											end)
											else nil,
									})
									return card
								end,
							},
						}
					end,
				},
				destinations = {
					item = { title = "Equipment", content = details },
					filters = {
						title = "Equipment filters",
						content = function()
							return UI.ScrollView({
								padding = "m",
								gap = "m",
								UI.Picker "EquipmentCategory" { selected = filter, options = categories },
								view.button("FilterLoadout", "Inspect loadout", function()
									loadoutOpen:set(true)
								end),
								view.button("FilterReset", "Start over", reset),
								view.button("ShowEquipment", "Show equipment", function()
									path:set({})
								end),
							} :: ScrollViewProps)
						end,
					},
				},
			}
		end
		local belt: () -> Frame
		local function loadout()
			return view.page(
				"LoadoutPage",
				"Ready for the cold?",
				"Your outfit changes as you equip items from the pack.",
				{
					portrait(),
					UI.ProgressView { label = "Warmth", value = warmth, max = 10, showValue = true },
					view.text("EquippedSummary", function(use: Use)
						local e = use(equipped)
						return byId[e.coat].name .. " · " .. byId[e.boots].name .. " · " .. byId[e.tool].name
					end),
					view.button("EnterCave", "Enter the frost cave", function()
						notice:set("Expedition ready! Your gear keeps you warm inside the frost cave.")
					end, function(use: Use)
						return use(warmth) >= 10
					end),
					view.text("ExpeditionNotice", notice),
					view.button("ResetPack", "Pack again", reset),
					belt(),
				}
			)
		end
		belt = function()
			local slots = {}
			for slot = 1, 3 do
				local target = view.button("Slot" .. slot, function(use: Use)
					return `{slot} · {byId[use(hotbar)[slot]].name}`
				end, function()
					equip(hotbar:peek()[slot])
				end)
				UI.dropTarget(target, {
					accepts = function(payload: unknown)
						return toolOf[payload] ~= nil
					end,
					onDrop = function(payload: unknown)
						local id = toolOf[payload]
						if id then
							assign(id, slot)
						end
					end,
				})
				table.insert(slots, target)
			end
			return UI.VStack "HotbarDock" {
				width = "fill",
				gap = "s",
				view.text("HotbarHint", function(use: Use)
					return if use(wide)
						then "HOTBAR · Drag a tool here to rearrange it. Select a slot to equip."
						else "HOTBAR · Assign slots from a tool's details. Select a slot to equip."
				end, "caption"),
				UI.Grid "HotbarSlots" {
					columns = 1,
					gap = "s",
					cellHeight = 52,
					table.unpack(slots),
				},
			}
		end
		local function screen()
			return UI.Screen "AdventurersPack" {
				padding = "m",
				gap = "s",
				ref = function(node)
					view.observeWidth(width, node)
					local bodyRoom = UI.environment(node)
					local toolbarAt = bodyRoom.scaled(500)
					C.watch(function(use: Use)
						roomy:set(use(bodyRoom.viewportHeight) >= use(toolbarAt))
					end)
				end,
				C.show(roomy, function()
					return UI.HStack({
						width = "fill",
						gap = "s",
						wrap = true,
						view.button("ShowLoadout", "Inspect loadout", function()
							loadoutOpen:set(true)
						end),
						view.button("ResetInventory", "Start over", reset),
					} :: StackProps)
				end),
				Host.Frame "EquipmentWorkbench" {
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					UI.fill(),
					Host.Frame "Backpack" {
						BackgroundTransparency = 1,
						Size = function(use: Use)
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
