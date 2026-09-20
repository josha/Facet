--!strict
-- A gallery page is an ordinary TabView. Each example owns only its active
-- tab's resources: a tab's content runs under its own owner, so leaving the tab
-- releases the example's controls, watchers and subscriptions.

return function(ctx: any, id: string, groups: { any }): any
	local Facet = ctx.Facet
	local UI, Compose = ctx.UI, ctx.Compose
	local selections: { [string]: any } = {}
	local active: any = nil
	local preference = Compose.cell("automatic")
	-- Where the category navigation sits, for the host's "use sidebar / use top
	-- tabs" choice. The mounted page publishes it.
	local placement = Compose.cell(nil :: string?)

	-- One example, mounted as a tab's page. Its root keeps its own name, and the
	-- host's geometry and controller reach the example through its root node.
	local function examplePage(entry: any)
		local built = entry.scenario.build(ctx)
		active = { id = entry.id, built = built }
		Compose.cleanup(function()
			if built.dispose then
				built.dispose()
			end
			if active and active.built == built then
				active = nil
			end
		end)
		local root = if type(built.screen) == "function" then built.screen() else built.screen
		local contribution = table.clone(Facet.contribution.read(root) or {})
		local syncGeometry = contribution.syncGeometry
		contribution.syncGeometry = function(rectOf, rootNode)
			if syncGeometry then
				syncGeometry(rectOf, rootNode)
			end
			if built.present and built.present.onGeometry then
				-- the example names paths from its own root
				local prefix = rootNode.path:sub(1, -#root.id - 2)
				built.present.onGeometry(function(path)
					return rectOf(prefix .. path)
				end)
			end
		end
		local bindController = contribution.bindController
		contribution.bindController = function(controller)
			if bindController then
				bindController(controller)
			end
			built.handle = { controller = controller }
		end
		return Facet.contribution.attach(root, contribution)
	end

	local function tabsFor(key: string, entries: { any }, top: boolean)
		local selection = selections[key]
		if selection == nil then
			selection = Compose.cell(entries[1].id)
			selections[key] = selection
		end
		local tabs = {}
		for _, entry in entries do
			table.insert(tabs, {
				id = entry.id,
				label = entry.label,
				content = function()
					if entry.tabs == nil then
						return examplePage(entry)
					end
					-- Scroll the page bar with its content when large type or a short
					-- viewport leaves too little room under the category bar.
					return UI.ScrollView("PageScroll")({
						width = UI.fill(),
						height = UI.fill(),

						UI.VStack("PageViewport")({
							width = UI.fill(),
							height = function(use)
								return { type = "fixed", px = math.max(1, use(ctx.env:get("viewportRect")).h) }
							end,
							tabsFor(entry.id, entry.tabs, false),
						}),
					})
				end,
			})
		end
		return UI.TabView(key)({
			env = ctx.env,
			selection = selection,
			-- Categories are peer destinations; examples within them are page tabs.
			-- Automatic placement lets the inner TabView use Facet's nesting rule.
			style = if top then "sidebarAdaptable" else "automatic",
			sidebarPreference = if top then preference else nil,
			shoulderNavigation = "content",
			tabs = tabs,
		})
	end

	local function Page()
		-- The category bar's home: the adaptive policy, then the player's choice
		-- wherever the policy leaves room for one.
		local conditions = Facet.adaptive.conditions(ctx.env)
		Compose.watch(function(use)
			local home = use(conditions.navPlacement)
			local chosen = use(preference)
			local fixed = home == "bottomBar" or home == "bottomBarCompact" or use(conditions.isTenFoot)
			placement:set(if fixed or chosen == "automatic" then home else chosen)
		end)
		return UI.Screen(id)({ tabsFor("Categories", groups, true) })
	end

	return {
		navigationLayout = {
			placement = placement,
			toggle = function()
				preference:set(if placement:peek() == "sidebar" then "topBar" else "sidebar")
			end,
		},
		screen = Page,
		report = function()
			local selected = {}
			for key, selection in selections do
				selected[key] = selection:peek()
			end
			return {
				selected = selected,
				navigation = { placement = placement:peek(), preference = preference:peek() },
				active = if active then active.id else nil,
				example = if active and active.built.report then active.built.report() else nil,
			}
		end,
		dispose = function() end,
	}
end
