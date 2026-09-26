--!strict
return function(ctx: any, id: string, groups: { any })
	local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
	local UDim2 = ctx.types.UDim2
	local selections = {}
	local preference = ctx.categoryPlacement or Compose.cell("automatic")
	local builtById = {}
	local function tabsFor(key, entries, outer, parentVisible)
		local selected = selections[key]
		if not selected then
			selected = Compose.cell(entries[1].id)
			selections[key] = selected
		end
		local tabs = {}
		for _, entry in entries do
			table.insert(tabs, {
				id = entry.id,
				label = entry.label,
				content = function()
					local visible = Compose.formula(function(use)
						return (not parentVisible or use(parentVisible)) and use(selected) == entry.id
					end)
					if entry.tabs then
						return tabsFor(entry.id, entry.tabs, false, visible)
					end
					local pageContext = table.clone(ctx)
					pageContext.pageVisible = visible
					local built = entry.scenario.build(pageContext)
					builtById[entry.id] = built
					if built.dispose then
						Compose.cleanup(built.dispose)
					end
					return built.screen()
				end,
			})
		end
		if not outer then
			return UI.TabView({
				Name = key,
				selection = selected,
				tabs = tabs,
				shoulderNavigation = "content",
				Size = UDim2.fromScale(1, 1),
			})
		end
		local side, roomy = Compose.cell(false), Compose.cell(false)
		local view = UI.TabView({
			Name = key,
			selection = selected,
			tabs = tabs,
			style = "sidebarAdaptable",
			placement = function(use)
				return if use(side) then "sidebar" else "topBar"
			end,
			accessories = {
				head = function()
					return UI.Button "UseTopTabs" {
						label = "Use top tabs",
						appearance = "utility",
						Size = UDim2.new(1, 0, 0, 40),
						onActivate = function()
							preference:set("top")
						end,
					}
				end,
				trailing = function()
					return UI.Button "UseSidebar" {
						label = "",
						name = "Use sidebar",
						appearance = "utility",
						icon = "menu",
						Visible = roomy,
						onActivate = function()
							preference:set("side")
						end,
					}
				end,
			},
			Size = UDim2.fromScale(1, 1),
		})
		local env = UI.environment(view)
		Compose.watch(function(use)
			local room = use(env.sizeClass) ~= "compact"
			local choice = use(preference)
			roomy:set(room)
			side:set(if choice == "automatic" then use(env.navPlacement) == "sidebar" else choice == "side" and room)
		end)
		return view
	end
	return {
		screen = function()
			return Host.Frame({
				Name = id,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				tabsFor("Categories", groups, true, ctx.pageVisible),
			})
		end,
		report = function()
			local selected = {}
			for key, value in selections do
				selected[key] = value:peek()
			end
			local entries, key, leaf = groups, "Categories", nil
			while entries do
				local current = selected[key] or entries[1].id
				local found
				for _, entry in entries do
					if entry.id == current then
						found = entry
						break
					end
				end
				if not found then
					break
				end
				leaf, key, entries = found.id, found.id, found.tabs
			end
			local built = leaf and builtById[leaf]
			return {
				selected = selected,
				active = leaf,
				example = if built and built.report then built.report() else nil,
			}
		end,
	}
end
