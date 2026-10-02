--!strict

type SupplyModule = typeof(require("@repo/examples/reference/p1_glade/services/supply"))
local loadSupply = require :: (string) -> SupplyModule
local makeView = require("./showcase_view")
local art = require("./showcase_art")
local creatures = {
	{
		id = "emberwisp",
		name = "Ember wisp",
		nectar = "bramble",
		label = "Bramble",
		note = "A warm little light that loves berry nectar.",
	},
	{
		id = "palewisp",
		name = "Pale wisp",
		nectar = "clover",
		label = "Clover",
		note = "A quiet visitor, soft as the morning mist.",
	},
	{
		id = "sunwisp",
		name = "Sun wisp",
		nectar = "meadow",
		label = "Meadow",
		note = "A pocket of sunshine with a sweet tooth.",
	},
}
return {
	title = "Glade",
	build = function(ctx: any)
		local supplyService = if script
			then ctx.load("reference", "p1_glade", "services", "supply")
			else loadSupply("../../reference/p1_glade/services/supply")
		local UI, Host, C = ctx.UI, ctx.Host, ctx.Compose
		local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
		local view = makeView(ctx)
		local now, visitor, seen, journal = C.cell(0), C.cell(nil), C.cell({}), C.cell({})
		local nectar, favoriteOnly, favorites = C.cell("bramble"), C.cell(false), C.cell({})
		local detail, presented = C.cell(creatures[1]), C.cell(false)
		local feederOpen, guideOpen, journalOpen = C.cell(false), C.cell(false), C.cell(false)
		local notice = C.cell("The dew bowl is nearly empty. Refill it to welcome your first visitor.")
		local owner = C.currentOwner()
		local supply = supplyService.new({
			Compose = C,
			now = now,
			rooted = function(body)
				return C.withOwner(owner, body)
			end,
		})
		local water = supply.level("mossholm", "dew")
		local function refill()
			supply.refill("mossholm", "dew")
			notice:set("Fresh water. A good place to pause.")
		end
		local function invite()
			if water:peek() < 0.2 then
				notice:set("Refill the dew bowl first. Your visitors need fresh water.")
				return false
			end
			supply.assign("mossholm", nectar:peek())
			local found
			for _, creature in creatures do
				if creature.nectar == nectar:peek() then
					found = creature
				end
			end
			if not found then
				return false
			end
			local collection = table.clone(seen:peek())
			collection[found.id] = true
			local entries = table.clone(journal:peek())
			table.insert(entries, {
				id = #entries + 1,
				text = found.name .. " stopped by for " .. string.lower(found.label) .. " nectar.",
			})
			ctx.runtime:batch(function()
				visitor:set(found)
				seen:set(collection)
				journal:set(entries)
				now:set(now:peek() + 45)
				notice:set(found.name .. " discovered! Find it in your field guide.")
			end)
			return true
		end
		local function reset()
			ctx.runtime:batch(function()
				now:set(0)
				supply.reset()
				seen:set({})
				journal:set({})
				visitor:set(nil)
				favorites:set({})
				favoriteOnly:set(false)
				nectar:set("bramble")
				notice:set("The dew bowl is nearly empty. Refill it to welcome your first visitor.")
			end)
		end
		local function scene(creature)
			return Host.Frame "GladeScene" {
				Size = D2.new(1, 0, 0, 300),
				BackgroundTransparency = 1,
				UI.Image "GardenPainting" { image = art.garden, scaleMode = "fit" :: "fit", Size = D2.fromScale(1, 1) } :: unknown,
				C.show(function(use: any)
					return use(creature) ~= nil
				end, function()
					return UI.Image "VisitorSprite" {
						image = art.wisps,
						scaleMode = "fit" :: "fit",
						Size = D2.fromScale(0.23, 0.35),
						Position = D2.fromScale(0.45, 0.3),
						ImageRectSize = V2.new(341, 341),
						ImageRectOffset = function(use: any)
							local id = use(creature).id
							return V2.new((if id == "emberwisp" then 0 elseif id == "palewisp" then 1 else 2) * 341, 0)
						end,
					}
				end),
			}
		end
		local function garden()
			local island = scene(visitor)
			ctx.runtime.decorate(island, { Size = D2.fromScale(1, 1) })
			local function hotspot(name: string, label, x, y, action, enabled)
				return UI.Button(name) {
					label = label,
					onActivate = action,
					enabled = enabled,
					Position = D2.fromScale(x, y),
					AnchorPoint = V2.new(0.5, 0.5),
				}
			end
			return UI.ScrollView "Glade" {
				padding = "l",
				align = "center" :: "center",
				UI.VStack "GardenContent" {
					width = "fill" :: "fill",
					gap = "m",
					Host.UISizeConstraint { MaxSize = V2.new(960, 100000) } :: unknown,
					view.text("GardenTitle", "A small place to care for", "title"),
					view.text("GardenObjective", "Fill the pond, choose a nectar, and see who visits."),
					Host.Frame "GardenLandscape" {
						Size = D2.new(1, 0, 0, 640),
						BackgroundTransparency = 1,
						Host.UIAspectRatioConstraint { AspectRatio = 1.5, DominantAxis = E.DominantAxis.Width } :: unknown,
						island,
						hotspot("RefillDew", "Fill pond", 0.3, 0.7, refill),
						hotspot("OpenFeeder", "Offer nectar", 0.79, 0.69, function()
							feederOpen:set(true)
						end),
						hotspot(
							"InspectVisitor",
							function(use: any)
								return if use(visitor) then use(visitor).name else "Waiting for a visitor"
							end,
							0.62,
							0.25,
							function()
								if visitor:peek() then
									detail:set(visitor:peek())
									presented:set(true)
								end
							end,
							function(use: any)
								return use(visitor) ~= nil
							end
						),
					},
					view.text("GladeNotice", notice, "heading"),
					UI.ProgressView "DewLevel" { label = "Pond water", value = water },
					view.actions({
						view.button("OpenFieldGuide", function(use: any)
							local count = 0
							for _ in use(seen) do
								count += 1
							end
							return `Field guide · {count}/3 visitors`
						end, function()
							guideOpen:set(true)
						end),
						view.button("OpenJournal", "Recent visits", function()
							journalOpen:set(true)
						end),
					}),
					UI.Sheet "Feeder" {
						title = "What will you leave out?",
						isPresented = feederOpen,
						closeButton = true,
						detent = C.cell("medium"),
						content = function(): Instance
							local offerings = {
								view.text(
									"FeederHint",
									"Each nectar attracts a different visitor. Fresh water is needed too."
								),
							}
							for _, creature in creatures do
								table.insert(
									offerings,
									view.button("Offer_" .. creature.nectar, creature.label .. " nectar", function()
										nectar:set(creature.nectar)
										if invite() then
											feederOpen:set(false)
										end
									end)
								)
							end
							table.insert(offerings, view.text("FeederNotice", notice))
							return UI.VStack {
								width = "fill" :: "fill",
								gap = "m",
								table.unpack((offerings :: unknown) :: { unknown }),
							}
						end,
					},
				},
			}
		end
		local function collection()
			local children = { UI.Toggle "FavoritesOnly" { label = "Favorites only", value = favoriteOnly } }
			for _, creature in creatures do
				table.insert(
					children,
					C.show(function(use: any)
						return not use(favoriteOnly) or use(favorites)[creature.id] == true
					end, function()
						return UI.VStack {
							width = "fill" :: "fill",
							gap = "s",
							view.text(creature.id .. "Name", function(use: any)
								return if use(seen)[creature.id]
									then creature.name
									else "Undiscovered · " .. creature.label .. " nectar"
							end, "heading") :: unknown,
							view.text(creature.id .. "Note", creature.note),
							view.actions({
								view.button("Inspect_" .. creature.id, "View visitor", function()
									detail:set(creature)
									presented:set(true)
								end, function(use: any)
									return use(seen)[creature.id] == true
								end),
								UI.Toggle("Favorite_" .. creature.id)({
									label = "Favorite",
									value = function(use: any)
										return use(favorites)[creature.id] == true
									end,
									onChange = function(value)
										local nextFavorites = table.clone(favorites:peek())
										nextFavorites[creature.id] = value
										favorites:set(nextFavorites)
									end,
								}),
							}),
							UI.Divider {},
						}
					end)
				)
			end
			return view.page(
				"CollectionPage",
				"Your field guide",
				"A familiar face is always worth remembering.",
				children
			)
		end
		local function notes()
			return view.page("JournalPage", "Small moments, collected", "Every visit leaves a little story.", {
				C.show(function(use: any)
					return #use(journal) == 0
				end, function()
					return view.text("EmptyJournal", "Your first visitor will start the story.")
				end),
				C.keyed({
					from = journal,
					key = function(item)
						return item.id
					end,
					render = function(current): GuiObject
						return view.text("Visit" .. current:peek().id, function(use: any)
							local entry = use(current)
							return `{entry.id}. {entry.text}`
						end)
					end,
				}),
				view.button("ResetGlade", "Start a fresh journal", reset),
			})
		end
		local function visitorSheet()
			return UI.Sheet "VisitorDetails" {
				title = "Field notes",
				isPresented = presented,
				detent = C.cell("large"),
				closeButton = true,
				content = function(): Instance
					return UI.VStack {
						width = "fill" :: "fill",
						gap = "m",
						scene(detail) :: unknown,
						view.text("VisitorName", function(use: any)
							return use(detail).name
						end, "title"),
						view.text("VisitorNote", function(use: any)
							return use(detail).note .. "\nFavorite nectar: " .. use(detail).label
						end),
					}
				end,
			}
		end
		return {
			screen = function()
				return Host.Frame "WispGarden" {
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					garden() :: unknown,
					visitorSheet(),
					UI.Sheet "FieldGuide" {
						title = "Field guide",
						isPresented = guideOpen,
						closeButton = true,
						detent = C.cell("large"),
						content = collection,
					},
					UI.Sheet "VisitJournal" {
						title = "Recent visits",
						isPresented = journalOpen,
						closeButton = true,
						detent = C.cell("large"),
						content = notes,
					},
				}
			end,
			report = function()
				local count = 0
				for _ in seen:peek() do
					count += 1
				end
				return {
					discovered = count,
					visits = #journal:peek(),
					water = water:peek(),
					visitor = if visitor:peek() then visitor:peek().id else nil,
				}
			end,
			refill = refill,
			invite = invite,
			reset = reset,
			model = { nectar = nectar, guideOpen = guideOpen, journalOpen = journalOpen },
		}
	end,
}
