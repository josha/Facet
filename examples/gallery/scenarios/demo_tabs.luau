--!strict
return function(ctx: any, id: string, groups: { any })
	local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
	local UDim2 = ctx.types.UDim2
	local selections = {}
	local preference = Compose.cell("automatic")
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
		return UI.TabView({
			Name = key,
			selection = selected,
			tabs = tabs,
			style = if outer then "sidebarAdaptable" else "automatic",
			sidebarPreference = if outer then preference else nil,
			shoulderNavigation = if outer then nil else "content",
			accessories = if outer
				then {
					head = function()
						return UI.Button "UseTopTabs" {
							label = "Use top tabs",
							appearance = "utility",
							Size = UDim2.new(1, 0, 0, 40),
							onActivate = function()
								preference:set("topBar")
							end,
						}
					end,
					trailing = function(place)
						return UI.Button "UseSidebar" {
							label = if place == "topBar" then "Use sidebar" else nil,
							name = "Use sidebar",
							appearance = "utility",
							icon = "menu",
							onActivate = function()
								preference:set("sidebar")
							end,
						}
					end,
				}
				else nil,
			Size = UDim2.fromScale(1, 1),
		})
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
