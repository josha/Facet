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
		local home, distant = Compose.cell("automatic"), Compose.cell(false)
		local effective = Compose.formula(function(use)
			local choice, place = use(preference), use(home)
			if use(distant) or choice == "automatic" or string.find(place, "bottom") ~= nil then
				return place
			end
			return if choice == "side" then "sidebar" else "topBar"
		end)
		local view = UI.TabView({
			Name = key,
			selection = selected,
			tabs = tabs,
			style = "sidebarAdaptable",
			placement = function(use)
				local place = use(effective)
				return if place == use(home) then "automatic" else place
			end,
			Size = UDim2.fromScale(1, 1),
		})
		local env = UI.environment(view)
		Compose.watch(function(use)
			home:set(use(env.navPlacement))
			distant:set(use(env.isTenFoot))
		end)
		if ctx.categoryLayout then
			local layout = {
				placement = effective,
				available = Compose.formula(function(use)
					local place = use(effective)
					return not use(distant) and (place == "sidebar" or place == "topBar")
				end),
				toggle = function()
					preference:set(if effective:peek() == "sidebar" then "top" else "side")
				end,
			}
			ctx.categoryLayout:set(layout)
			Compose.cleanup(function()
				if ctx.categoryLayout:peek() == layout then
					ctx.categoryLayout:set(nil)
				end
			end)
		end
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
