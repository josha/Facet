--!strict
local makeView = require("./showcase_view")
local vehicles = {
	{ id = "comet", label = "Comet coupe", length = 5.8, cabin = 1.1 },
	{ id = "rover", label = "Trail rover", length = 5.2, cabin = 1.8 },
	{ id = "sprint", label = "Sprint kart", length = 4.3, cabin = 0.6 },
}
local wheels = {
	{ value = "street", label = "Street" },
	{ value = "rally", label = "Rally" },
	{ value = "sport", label = "Sport" },
}
return {
	title = "Garage",
	build = function(ctx: any)
		local UI, Host, C = ctx.UI, ctx.Host, ctx.Compose
		local V3, CF, C3, E, D2 = ctx.types.Vector3, ctx.types.CFrame, ctx.types.Color3, ctx.types.Enum, ctx.types.UDim2
		local view = makeView(ctx)
		local vehicle, wheel, paint = C.cell("comet"), C.cell("street"), C.cell(C3.fromRGB(247, 111, 70))
		local angle, stripe = C.cell(25), C.cell(true)
		local presets, name, presented = C.cell({}), C.cell("Weekend racer"), C.cell(false)
		local notice = C.cell("Pick a ride. Make it yours.")
		local width, savedOpen = C.cell(1000), C.cell(false)
		local metric = UI.environment().metricScale
		local wide = C.formula(function(use: any)
			return use(width) >= 850 * use(metric)
		end)
		local spec = C.formula(function(use: any)
			for _, item in vehicles do
				if item.id == use(vehicle) then
					return item
				end
			end
			return vehicles[1]
		end)
		local function reset()
			ctx.runtime:batch(function()
				vehicle:set("comet")
				wheel:set("street")
				paint:set(C3.fromRGB(247, 111, 70))
				stripe:set(true)
				angle:set(25)
				presets:set({})
				name:set("Weekend racer")
				notice:set("Pick a ride. Make it yours.")
			end)
		end
		local function save()
			local label = string.match(name:peek(), "^%s*(.-)%s*$") or ""
			if label == "" then
				return
			end
			local nextPresets = table.clone(presets:peek())
			table.insert(nextPresets, {
				id = #nextPresets + 1,
				name = label,
				vehicle = vehicle:peek(),
				wheel = wheel:peek(),
				paint = paint:peek(),
				stripe = stripe:peek(),
			})
			presets:set(nextPresets)
			presented:set(false)
			notice:set("Saved “" .. label .. "” to Presets.")
		end
		local function preview()
			return view.stage("VehiclePreview", function()
				local parts = {
					view.part("Plinth", V3.new(8, 0.2, 8), V3.new(0, -0.25, 0), C3.fromRGB(46, 55, 72)),
				}
				local function at(x, y, z)
					return function(use: any)
						return CF.Angles(0, math.rad(use(angle)), 0) * CF.new(x, y, z)
					end
				end
				table.insert(
					parts,
					view.part("Body", V3.new(3, 0.9, 6), V3.new(), paint, {
						CFrame = at(0, 1, 0),
						Size = function(use: any)
							return V3.new(3, 0.9, use(spec).length)
						end,
					})
				)
				table.insert(
					parts,
					view.part("Cabin", V3.new(2.4, 1, 2.5), V3.new(), C3.fromRGB(67, 107, 131), {
						CFrame = at(0, 1.8, -0.3),
						Size = function(use: any)
							return V3.new(2.4, use(spec).cabin, 2.5)
						end,
					})
				)
				table.insert(
					parts,
					view.part("Roof", V3.new(2.5, 0.18, 2.7), V3.new(), paint, {
						CFrame = function(use: any)
							return CF.Angles(0, math.rad(use(angle)), 0) * CF.new(0, 1.8 + use(spec).cabin / 2, -0.3)
						end,
					})
				)
				for _, x in { -1.6, 1.6 } do
					for _, z in { -1.8, 1.8 } do
						table.insert(
							parts,
							view.part("Wheel", V3.new(0.6, 1.3, 1.3), V3.new(), C3.fromRGB(24, 25, 30), {
								Shape = E.PartType.Cylinder,
								CFrame = at(x, 0.6, z),
								Size = function(use: any)
									local radius = if use(wheel) == "rally" then 1.7 else 1.3
									return V3.new(0.65, radius, radius)
								end,
							})
						)
						table.insert(
							parts,
							view.part("Rim", V3.new(0.68, 0.8, 0.8), V3.new(), function(use: any)
								return if use(wheel) == "sport"
									then C3.fromRGB(239, 191, 86)
									else C3.fromRGB(180, 192, 208)
							end, { Shape = E.PartType.Cylinder, CFrame = at(x, 0.6, z) })
						)
					end
				end
				for _, x in { -1, 1 } do
					table.insert(
						parts,
						view.part("Headlight", V3.new(0.65, 0.3, 0.1), V3.new(), C3.fromRGB(255, 238, 175), {
							CFrame = function(use: any)
								return CF.Angles(0, math.rad(use(angle)), 0)
									* CF.new(x, 1.1, use(spec).length / 2 + 0.03)
							end,
							Material = E.Material.Neon,
						})
					)
				end
				table.insert(
					parts,
					view.part("Stripe", V3.new(0.6, 0.02, 1.25), V3.new(), C3.fromRGB(244, 236, 212), {
						CFrame = at(0, 1.46, 1.9),
						Transparency = function(use: any)
							return if use(stripe) then 0 else 1
						end,
					})
				)
				return Host.Model "Ride" { table.unpack((parts :: unknown) :: { unknown }) }
			end)
		end
		local function saved()
			return UI.VStack "SavedRides" {
				width = "fill" :: "fill",
				gap = "m",
				C.show(function(use: any)
					return #use(presets) == 0
				end, function()
					return view.text("EmptyPresets", "Save your first car from the configurator.")
				end) :: unknown,
				C.keyed({
					from = presets,
					key = function(item)
						return item.id
					end,
					render = function(current): GuiObject
						return view.button("LoadPreset" .. current:peek().id, function(use: any)
							return use(current).name
						end, function()
							local item: any = current:peek()
							ctx.runtime:batch(function()
								vehicle:set(item.vehicle)
								wheel:set(item.wheel)
								paint:set(item.paint)
								stripe:set(item.stripe)
								notice:set("Loaded “" .. item.name .. "”.")
								savedOpen:set(false)
							end)
						end)
					end,
				}),
			}
		end
		local function screen()
			local rides = {}
			for _, item in vehicles do
				table.insert(rides, { value = item.id, label = item.label })
			end
			local stage = preview()
			ctx.runtime.decorate(stage, {
				Size = function(use: any)
					return D2.new(1, 0, 0, if use(wide) then 410 else 250)
				end,
			})
			return UI.ScrollView "Garage" {
				padding = "l",
				gap = "l",
				ref = view.observeWidth(width),
				view.text("GarageTitle", "Build your weekend ride", "title") :: unknown,
				UI.AdaptiveStack "Configurator" {
					width = "fill" :: "fill",
					gap = "l",
					axis = function(use: any)
						return if use(wide) then "x" else "y"
					end,
					UI.VStack "Showroom" {
						Size = function(use: any)
							return D2.new(1, if use(wide) then -354 else 0, 0, 0)
						end,
						AutomaticSize = E.AutomaticSize.Y,
						gap = "m",
						stage :: unknown,
						UI.Slider "Turntable" { label = "Rotate car", value = angle, min = -180, max = 180, step = 1 },
						UI.Picker "VehicleLineup" { label = "Vehicle", selected = vehicle, options = rides },
					} :: unknown,
					UI.VStack "Inspector" {
						Size = function(use: any)
							return if use(wide) then D2.fromOffset(330, 0) else D2.new(1, 0, 0, 0)
						end,
						AutomaticSize = E.AutomaticSize.Y,
						gap = "m",
						view.text("ModelName", function(use: any)
							return use(spec).label
						end, "title") :: unknown,
						UI.ColorPicker "Paint" { label = "Paint", value = paint },
						UI.Picker "Wheels" { label = "Wheels", selected = wheel, options = wheels },
						UI.Toggle "StripeToggle" { label = "Racing stripe", value = stripe },
						UI.Divider {},
						UI.Popover "SaveRide" {
							isPresented = presented,
							onPresentedChange = function(value)
								presented:set(value)
							end,
							trigger = UI.Button "SavePreset" { label = "Save this car" },
							compact = "popover",
							maxWidth = 320,
							content = function(): Instance
								return UI.VStack {
									width = "fill" :: "fill",
									gap = "m",
									view.text("SaveTitle", "Name this car", "heading") :: unknown,
									UI.TextInput "PresetName" { label = "Name", value = name },
									view.button("ConfirmSave", "Save car", save, function(use: any)
										return string.find(use(name), "%S") ~= nil
									end),
								}
							end,
						},
						UI.DisclosureGroup "SavedCars" {
							label = function(use: any)
								return `Saved cars · {#use(presets)}`
							end,
							expanded = savedOpen,
							content = saved,
						},
						view.text("GarageNotice", notice),
						view.button("ResetGarage", "Reset garage", reset),
					},
				},
			}
		end
		return {
			screen = screen,
			report = function()
				return {
					vehicle = vehicle:peek(),
					wheels = wheel:peek(),
					presets = #presets:peek(),
					stripe = stripe:peek(),
				}
			end,
			model = {
				vehicle = vehicle,
				wheel = wheel,
				paint = paint,
				name = name,
				presets = presets,
				savedOpen = savedOpen,
			},
			save = save,
			reset = reset,
		}
	end,
}
