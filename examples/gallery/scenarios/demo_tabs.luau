--!strict
-- A gallery page is an ordinary TabView. Each example owns only its active
-- tab's resources; leaving it releases its controls, effects and subscriptions.
local demoHost
if game then
	demoHost = require(game:GetService("ReplicatedStorage").Gallery.demo_host)
else
	demoHost = require("../client/demo_host")
end

return function(ctx: any, id: string, groups: { any }): any
	local Facet, UI = ctx.Facet, ctx.Facet.View
	local scope = ctx.core:scope(id)
	local core = ctx.core
	local selections = {}
	local active = nil
	local preference = scope:own(core:signal("automatic"))
	local function tabsFor(owner, key, entries)
		local selection = selections[key]
		if selection == nil then
			selection = scope:own(core:signal(entries[1].id))
			selections[key] = selection
		end
		local tabs = {}
		for _, entry in entries do
			table.insert(tabs, {
				id = entry.id,
				label = entry.label,
				content = function(tabScope)
					if entry.tabs then
						local nested = tabsFor(tabScope, entry.id, entry.tabs)
						-- Scroll the page bar with its content when large type or a short
						-- viewport leaves too little room under the category bar.
						return UI.ScrollView({
							id = "PageScroll",
							width = UI.fill(),
							height = UI.fill(),

							UI.VStack({
								id = "PageViewport",
								width = UI.fill(),
								height = tabScope:own(core:memo(function(use)
									return { type = "fixed", px = math.max(1, use(ctx.env:get("viewportRect")).h) }
								end)),
								nested.blueprint,
							}),
						})
					end
					local childContext = table.clone(ctx)
					childContext.core = demoHost.scopedCore(ctx.core, tabScope)
					local built = entry.scenario.build(childContext)
					active = { id = entry.id, built = built }
					tabScope:own(function()
						if built.dispose then
							built.dispose()
						end
						if active and active.built == built then
							active = nil
						end
					end)
					-- A nested example receives the tab's viewport and inset policy.
					-- Keep its contribution metadata (input handlers) on the same node.
					local props = table.clone(built.screen.props)
					props.id, props.children = built.screen.id, built.screen.children
					props.width, props.height = UI.fill(), UI.fill()
					if built.screen.class == "Component" then
						-- Deferred descriptions acquire their tree at mount. Keep the
						-- component intact rather than copying its empty placeholder.
						props.id, props.children = "ComponentPage", { built.screen }
					end
					local body = UI.VStack(props)
					local contribution = table.clone(Facet.contribution.read(built.screen) or {})
					local syncGeometry = contribution.syncGeometry
					contribution.syncGeometry = function(rectOf, rootNode)
						if syncGeometry then
							syncGeometry(rectOf, rootNode)
						end
						if built.present and built.present.onGeometry then
							local prefix = rootNode.path:sub(1, -#body.id - 2)
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
					local bound = {}
					if ctx.presenter then
						tabScope:own(ctx.presenter.onTick(function()
							if built.handle == nil then
								return
							end
							for _, value in built do
								if type(value) == "table" then
									local api = value.api or value
									if
										not bound[api]
										and type(api.bindNativeScroll) == "function"
										and type(api.scrollPath) == "function"
										and api.scrollPath() ~= nil
									then
										tabScope:own(api.bindNativeScroll(built.handle.controller))
										bound[api] = true
									end
								end
							end
						end))
					end
					return Facet.contribution.attach(body, contribution)
				end,
			})
		end
		-- This diagnostic host reads placement and dump(), and coordinates
		-- scenario handles across tab changes. Ordinary pages use View.TabView.
		local view
		view = Facet.Controls.TabView(core, {
			id = key,
			env = ctx.env,
			selection = selection,
			-- Categories are peer destinations; examples within them are page tabs.
			-- Automatic placement lets the inner TabView use Facet's nesting rule.
			style = if owner == scope then "sidebarAdaptable" else "automatic",
			sidebarPreference = if owner == scope then preference else nil,
			shoulderNavigation = "content",
			tabs = tabs,
		})
		owner:own(view)
		return view
	end
	local view = tabsFor(scope, "Categories", groups)
	return {
		navigationLayout = {
			placement = view.placement,
			toggle = function()
				preference:set(if view.placement:get() == "sidebar" then "topBar" else "sidebar")
			end,
		},
		screen = UI.Screen({ id = id, view.blueprint }),
		report = function()
			local selected = {}
			for key, selection in selections do
				selected[key] = selection:get()
			end
			return {
				selected = selected,
				navigation = view.dump(),
				active = if active then active.id else nil,
				example = if active and active.built.report then active.built.report() else nil,
			}
		end,
		dispose = function()
			scope:dispose()
		end,
	}
end
