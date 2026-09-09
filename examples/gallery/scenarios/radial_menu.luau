--!strict
-- Curated Quick actions: the scene owns outcomes and the control owns input.
return {
	title = "Quick actions",
	ledgerRows = {},
	build = function(ctx)
		local Facet, core, env = ctx.Facet, ctx.core, ctx.env
		local UI = Facet.UI
		local scope = core:scope("quick-actions")
		local selected = scope:own(core:signal("gestures"))
		local status = scope:own(core:signal("Ready for a little adventure"))
		local glow = scope:own(core:signal(false))
		local moving = scope:own(core:signal(false))
		local skinned = scope:own(core:signal(false))
		local separate = scope:own(core:signal(false))
		local corner = scope:own(core:signal("bottom-left"))
		local corners = { "bottom-left", "bottom-right", "top-right", "top-left" }
		local fitting = scope:own(core:signal("both"))
		local fitModes = { "both", "radial", "angular", "none" }
		local fitNames = { both = "Hug content", radial = "Slim band", angular = "Short arcs", none = "Full arcs" }
		local advanced = scope:own(core:signal(false))
		local passThrough = scope:own(core:signal(false))
		local centerPolicy = scope:own(core:signal("empty"))
		local lastAction = scope:own(core:signal("ready"))
		local current = nil
		local worldScene = nil
		local function action(id, text)
			return function()
				lastAction:set(id)
				status:set(text)
			end
		end
		local scenes = scope:own(core:memo(function(use)
			return {
				{
					id = use(selected) .. ":" .. tostring(use(skinned)) .. ":" .. use(centerPolicy) .. ":" .. tostring(
						use(passThrough)
					) .. ":" .. tostring(use(separate)) .. ":" .. use(fitting) .. ":" .. use(corner),
					kind = use(selected),
					skin = use(skinned),
					separate = use(separate),
					fit = use(fitting),
					corner = use(corner),
					center = use(centerPolicy),
					passThrough = use(passThrough),
				},
			}
		end))
		local function scene(item, sceneScope)
			local anchor = sceneScope:own(core:signal(nil))
			local offset = sceneScope:own(core:signal(0))
			local baseRect = nil
			local time = 0
			local items
			local menu, native = nil, nil
			local spec =
				{ id = "Commands", env = env, center = "empty", label = "Quick actions", contentFit = item.fit }
			if item.kind == "world" then
				if ctx.worldActions then
					native = sceneScope:own(ctx.worldActions(function()
						if menu then
							menu.api.open()
						end
					end))
					worldScene = native
					sceneScope:own(function()
						if worldScene == native then
							worldScene = nil
						end
					end)
				end
				spec.preset, spec.center = "donut", "empty"
				spec.launcher = native == nil
				spec.anchor = if native then native.anchor else anchor
				spec.ringWidth = "controlSizes.large.height"
				spec.appearance = if item.separate then "buttons" else "wedges"
				items = {
					{
						id = "inspect",
						label = "Inspect",
						icon = "facet:search",
						completion = "stay",
						onSelect = function()
							if native then
								native.turn()
							end
							action("inspect", "A sturdy trail pack. Turn it to inspect the pocket.")()
						end,
					},
					{
						id = "resize",
						label = "Unpack",
						icon = "menu",
						completion = "stay",
						onSelect = function()
							if native then
								native.resize()
							end
							action("resize", "The pack expands. The menu adjusts around it.")()
						end,
					},
					{
						id = "take",
						label = "Pick up",
						icon = "checkmark",
						onSelect = function()
							if native then
								native.take()
							end
							action("take", "Pack collected. Switch tabs and return to try again.")()
						end,
					},
				}
			elseif item.kind == "corner" then
				spec.preset = item.corner
				spec.appearance = "buttons"
				items = {
					{
						id = "look",
						label = "Look",
						icon = "facet:search",
						labelStyle = "both",
						onSelect = action("look", "You spotted a trail beyond the trees."),
					},
					{
						id = "pack",
						label = "Pack",
						icon = "menu",
						navigation = "replace",
						children = {
							{
								id = "map",
								label = "Map",
								compactLabel = { icon = "flag" },
								onSelect = action("map", "Map opened. The lookout is just ahead."),
							},
							{
								id = "snack",
								label = "Snack",
								compactLabel = { icon = "checkmark" },
								onSelect = action("snack", "A quick snack. Ready to keep exploring."),
							},
						},
					},
					{
						id = "wave",
						label = "Wave",
						icon = "flag",
						onSelect = action("wave", "You wave hello to a friend."),
					},
				}
			elseif item.kind == "gestures" then
				spec.preset = "circle"
				spec.distribution = "compass"
				spec.gestureSelection = "direction"
				spec.center = "back"
				spec.appearance = "wedges"
				items = {
					{
						id = "wave",
						label = "Wave",
						slot = "N",
						icon = "flag",
						onSelect = action("wave", "You wave hello to a friend."),
					},
					{
						id = "cheer",
						label = "Cheer",
						slot = "NE",
						icon = "increment",
						onSelect = action("cheer", "A cheer for the next adventure!"),
					},
					{
						id = "point",
						label = "Point",
						slot = "E",
						icon = "chevron.trailing",
						onSelect = action("point", "You point toward the lookout."),
					},
					{
						id = "sit",
						label = "Sit",
						slot = "SW",
						icon = "chevron.down",
						onSelect = action("sit", "You take a seat and enjoy the view."),
					},
					{
						id = "inspect",
						label = "Inspect",
						slot = "W",
						icon = "facet:search",
						onSelect = action("inspect", "Trail guide · explorer · ready to help"),
					},
				}
			else
				spec.preset = "donut"
				spec.appearance = if item.separate then "buttons" else "wedges"
				spec.center = item.center
				spec.centerPassThrough = item.passThrough
				spec.clearance = 82
				spec.ringWidth = "controlSizes.large.height"
				spec.anchor = anchor
				items = {
					{
						id = "equipment",
						label = "Equipment",
						compactLabel = { icon = "menu", prefer = true },
						icon = "menu",
						navigation = "replace",
						children = {
							{
								id = "tools",
								label = "Tools",
								icon = "edit",
								navigation = "expand",
								expansion = "fan",
								children = {
									{
										id = "lantern",
										label = "Lantern",
										compactLabel = { icon = "increment" },
										checked = glow,
										onChange = function(on)
											status:set(
												if on
													then "Lantern on. A little light for the trail."
													else "Lantern off."
											)
										end,
									},
									{
										id = "stow",
										label = "Stow",
										compactLabel = { icon = "chevron.leading" },
										completion = "back",
										onSelect = action("stow", "Tools tucked away. Back to equipment."),
									},
									{
										id = "ready",
										label = "Ready",
										compactLabel = { icon = "checkmark" },
										completion = "root",
										onSelect = action("ready", "All set. Back to your main commands."),
									},
								},
							},
							{
								id = "wear",
								label = "Wear",
								completion = "back",
								onSelect = action("wear", "Your adventure gear is on."),
							},
						},
					},
					{
						id = "wave",
						label = "Wave",
						icon = "flag",
						labelStyle = "icon",
						completion = "close",
						onSelect = action("wave", "You wave, then return to exploring."),
					},
					{
						id = "inspect",
						label = "Inspect",
						compactLabel = { icon = "facet:search", prefer = true },
						completion = "stay",
						onSelect = action(
							"inspect",
							"Trail guide · explorer · lantern " .. (if glow:get() then "on" else "off")
						),
					},
				}
			end
			spec.items = items
			if item.skin then
				spec.appearance = "buttons"
				spec.buttonSurface = "none"
				-- Already shipped, available Facet art. Native labels remain over the image.
				spec.skin =
					{ item = { default = "rbxassetid://75192659975960", pressed = "rbxassetid://119648517302972" } }
			end
			menu = sceneScope:own(Facet.Controls.RadialMenu(core, spec))
			if native then
				sceneScope:own(core:observe(menu.api.isVisible, function(value)
					native.setOpen(value)
				end))
			end
			current = menu
			sceneScope:own(function()
				if current == menu then
					current = nil
				end
			end)
			local armAngle = sceneScope:own(core:memo(function(use)
				local a = use(lastAction)
				return if a == "wave" or a == "cheer" then -55 elseif a == "point" then -90 else 12
			end))
			local bodyY = sceneScope:own(core:memo(function(use)
				return if use(lastAction) == "sit" then 14 else 0
			end))
			local silhouette = UI.Anchor({
				id = "Explorer",
				width = { type = "fixed", px = 76 },
				height = { type = "fixed", px = 110 },
				anchor = "center",
				offsetX = offset,
				offsetY = bodyY,
				children = {
					UI.Box({
						id = "Head",
						tint = { role = "control", blend = 1 },
						width = { type = "fixed", px = 32 },
						height = { type = "fixed", px = 32 },
						anchor = "top",
						corners = UI.cornersData("pill"),
					}),
					UI.Box({
						id = "Coat",
						tint = { role = "accent", blend = 1 },
						width = { type = "fixed", px = 40 },
						height = { type = "fixed", px = 46 },
						anchor = "center",
						corners = UI.cornersData("pill"),
					}),
					UI.Box({
						id = "Arm",
						tint = { role = "accent", blend = 1 },
						width = { type = "fixed", px = 12 },
						height = { type = "fixed", px = 42 },
						offsetX = 60,
						offsetY = 30,
						rotation = armAngle,
					}),
					UI.Box({
						id = "LegLeft",
						tint = { role = "control", blend = 1 },
						width = { type = "fixed", px = 13 },
						height = { type = "fixed", px = 30 },
						offsetX = 21,
						offsetY = 78,
					}),
					UI.Box({
						id = "LegRight",
						tint = { role = "control", blend = 1 },
						width = { type = "fixed", px = 13 },
						height = { type = "fixed", px = 30 },
						offsetX = 43,
						offsetY = 78,
					}),
				},
			})
			local root = UI.Anchor({
				id = "Scene",
				width = UI.fill(),
				height = UI.fill(),
				children = {
					if item.kind == "world" then UI.Spacer({ width = UI.fill(), height = UI.fill() }) else silhouette,
					menu.blueprint,
				},
			})
			return Facet.contribution.attach(root, {
				syncGeometry = function(rectOf, node)
					if node then
						baseRect = rectOf(node.path)
					end
					if native then
						native.place(baseRect)
					elseif baseRect then
						anchor:set({
							x = baseRect.x + baseRect.w / 2 + offset:get(),
							y = baseRect.y + baseRect.h / 2,
							visible = true,
						})
					end
				end,
				bindInputScope = function(input)
					sceneScope:own(input.onTick(function(dt)
						if item.kind == "character" and moving:get() and baseRect then
							time += dt
							offset:set(math.sin(time) * math.min(24, baseRect.w * 0.02))
							anchor:set({
								x = baseRect.x + baseRect.w / 2 + offset:get(),
								y = baseRect.y + baseRect.h / 2,
								visible = true,
							})
						end
					end))
				end,
			})
		end
		local tabs = {}
		for _, tab in
			{
				{ id = "corner", text = "Corner commands", short = "Corner" },
				{ id = "gestures", text = "Quick gestures", short = "Gestures" },
				{ id = "character", text = "Character commands", short = "Character" },
				{ id = "world", text = "Nearby item", short = "Item" },
			}
		do
			table.insert(
				tabs,
				UI.Button({
					id = tab.id,
					label = tab.text,
					compactLabel = tab.short,
					width = UI.fill(),
					selected = scope:own(core:memo(function(use)
						return use(selected) == tab.id
					end)),
					onActivate = function()
						selected:set(tab.id)
					end,
				})
			)
		end
		local instruction = scope:own(core:memo(function(use)
			local tab = use(selected)
			return if tab == "gestures"
				then "Tap •••, then choose. Or press, slide to an action, and release."
				elseif tab == "corner" then "Open the corner menu. Pack takes you into your supplies."
				elseif tab == "world" then (if ctx.worldActions
					then "Use the pack’s Actions prompt, then inspect, unpack, or pick it up."
					else "Open this example in Roblox to try a nearby item’s Actions prompt.")
				else "Open your commands. Equipment leads to Tools. The explorer stays in view."
		end))
		local disclosure = scope:own(Facet.Controls.DisclosureGroup(core, {
			id = "Advanced",
			label = "More options",
			expanded = advanced,
			content = function()
				return UI.VStack({
					gap = "s",
					width = UI.fill(),
					children = {
						UI.Button({
							id = "ContentFit",
							label = scope:own(core:memo(function(use)
								return "Arc shape: " .. fitNames[use(fitting)]
							end)),
							onActivate = function()
								fitting:set(fitModes[(table.find(fitModes, fitting:get()) :: number) % #fitModes + 1])
							end,
						}),
						UI.Button({
							id = "CornerPosition",
							label = scope:own(core:memo(function(use)
								return "Corner: " .. use(corner)
							end)),
							onActivate = function()
								corner:set(corners[(table.find(corners, corner:get()) :: number) % #corners + 1])
							end,
						}),
						UI.Toggle({ id = "Separate", label = "Separate character icons", value = separate }),
						UI.Toggle({ id = "Skin", label = "Jewel buttons", value = skinned }),
						UI.Toggle({ id = "Move", label = "Let the explorer wander", value = moving }),
						UI.Toggle({ id = "PassThrough", label = "Allow taps through the center", value = passThrough }),
						UI.Button({
							id = "CenterPolicy",
							label = scope:own(core:memo(function(use)
								return "Center: " .. use(centerPolicy)
							end)),
							onActivate = function()
								centerPolicy:set(if centerPolicy:get() == "empty" then "back" else "empty")
							end,
						}),
					},
				})
			end,
		}))
		local function sceneRows()
			return UI.ForEach({
				id = "Scenes",
				items = scenes,
				key = function(s)
					return s.id
				end,
				row = scene,
			})
		end
		local function controls()
			return {
				UI.HStack({ id = "Tabs", width = UI.fill(), gap = "xs", children = tabs }),
				UI.ZStack({
					id = "InstructionPlate",
					surface = "base",
					width = UI.fill(),
					children = {
						UI.Text({
							id = "Instruction",
							text = instruction,
							width = UI.fill(),
							textSize = "caption",
							disclose = true,
						}),
					},
				}),
				UI.ZStack({
					id = "ResultPlate",
					surface = "base",
					width = UI.fill(),
					children = {
						UI.Text({ id = "Result", text = status, width = UI.fill(), textSize = "body", disclose = true }),
					},
				}),
				disclosure.blueprint,
			}
		end
		local compact = scope:own(core:memo(function(use)
			local v = use(env:get("viewportRect"))
			return v.h < 450 or (v.w < 600 and use(env:get("preferredTextOffset")) >= 10)
		end))
		return {
			screen = UI.Screen({
				id = "RadialMenu",
				padding = "m",
				children = {
					UI.When({
						id = "Arrangement",
						condition = compact,
						thenView = function()
							local sidebar = controls()
							-- Stack the three destinations where their horizontal compact
							-- forms would compete with the command surface.
							sidebar[1] = UI.VStack({ id = "Tabs", width = UI.fill(), gap = "xs", children = tabs })
							return UI.HStack({
								width = UI.fill(),
								height = UI.fill(),
								gap = "s",
								children = {
									UI.ScrollView({
										id = "Options",
										padding = { right = "s" },
										width = scope:own(core:memo(function(use)
											return {
												type = "fixed",
												px = math.clamp(use(env:get("viewportRect")).w * 0.38, 110, 240),
											}
										end)),
										height = UI.fill(),
										gap = "s",
										children = sidebar,
									}),
									sceneRows(),
								},
							})
						end,
					}),
					UI.When({
						id = "TallArrangement",
						condition = scope:own(core:memo(function(use)
							return not use(compact)
						end)),
						thenView = function()
							local content = controls()
							table.insert(content, 3, sceneRows())
							return UI.VStack({ width = UI.fill(), height = UI.fill(), gap = "s", children = content })
						end,
					}),
				},
			}),
			steps = {
				world = function()
					selected:set("world")
				end,
				unpack = function()
					if current then
						current.api.select("resize")
					end
				end,
				take = function()
					if current then
						current.api.select("take")
					end
				end,
				fitBoth = function()
					fitting:set("both")
				end,
				fitRadial = function()
					fitting:set("radial")
				end,
				fitAngular = function()
					fitting:set("angular")
				end,
				fitNone = function()
					fitting:set("none")
				end,
				corner = function()
					selected:set("corner")
				end,
				gestures = function()
					selected:set("gestures")
				end,
				orbit = function()
					selected:set("character")
					separate:set(true)
				end,
				wedges = function()
					separate:set(false)
				end,
				skin = function()
					skinned:set(true)
				end,
				native = function()
					skinned:set(false)
				end,
				move = function()
					moving:set(true)
				end,
				still = function()
					moving:set(false)
				end,
				passThrough = function()
					passThrough:set(true)
				end,
				centerBack = function()
					centerPolicy:set("back")
				end,
				back = function()
					if current then
						current.api.back()
					end
				end,
				close = function()
					if current then
						current.api.close()
					end
				end,
				lantern = function()
					if current then
						current.api.select("lantern")
					end
				end,
				stow = function()
					if current then
						current.api.select("stow")
					end
				end,
				ready = function()
					if current then
						current.api.select("ready")
					end
				end,
				open = function()
					if current then
						current.api.open()
					end
				end,
				wave = function()
					if current then
						current.api.select("wave")
					end
				end,
				character = function()
					selected:set("character")
				end,
				equipment = function()
					if current then
						current.api.select("equipment")
					end
				end,
				tools = function()
					if current then
						current.api.select("tools")
					end
				end,
				reset = function()
					if current then
						current.api.close()
					end
					selected:set("gestures")
					glow:set(false)
					moving:set(false)
					skinned:set(false)
					separate:set(false)
					passThrough:set(false)
					centerPolicy:set("empty")
					advanced:set(false)
					fitting:set("both")
					status:set("Ready for a little adventure")
					lastAction:set("ready")
				end,
			},
			report = function()
				return {
					tab = selected:get(),
					status = status:get(),
					menu = if current then current.dump() else nil,
					world = if worldScene then worldScene.dump() else nil,
				}
			end,
			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
