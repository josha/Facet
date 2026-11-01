--!strict

type ExampleContext = typeof(require("@repo/examples/types").Context)
type Built = typeof(require("@repo/examples/types").Built)
type Tab = typeof(require("@repo/tools/typecheck/aliases").Tab)
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Value<T> = typeof(require("@repo/src/vendor/compose/core").cell<<T>>(nil :: never))
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
type Placement = "automatic" | "sidebar" | "topBar" | "bottomBar" | "bottomBarCompact" | "none"
type Entry = typeof(require("@repo/examples/types").DemoTab)
type CategoryLayout = typeof(require("@repo/examples/types").CategoryLayout)
local function placementOf(value: string): Placement
	if value == "sidebar" or value == "topBar" or value == "bottomBar" then
		return value
	elseif value == "bottomBarCompact" or value == "none" then
		return value
	end
	return "automatic"
end
return function(ctx: ExampleContext, id: string, groups: { Entry })
	local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
	local UDim2 = ctx.types.UDim2
	local selections: { [string]: Value<string> } = {}
	local preference: Value<string> = ctx.categoryPlacement or Compose.cell("automatic")
	local builtById: { [string]: Built } = {}
	local function tabsFor(
		key: string,
		entries: { Entry },
		outer: boolean,
		parentVisible: ReadOnlyValue<boolean>?
	): GuiObject
		local selected = selections[key]
		if not selected then
			selected = Compose.cell(entries[1].id)
			selections[key] = selected
		end
		local tabs: { Tab } = {}
		for _, entry in entries do
			table.insert(tabs, {
				id = entry.id,
				label = entry.label,
				content = function(): Instance
					local visible = Compose.formula(function(use: Use): boolean
						return (not parentVisible or use(parentVisible)) and use(selected) == entry.id
					end)
					local children = entry.tabs
					if children then
						return tabsFor(entry.id, children, false, visible)
					end
					local pageContext = table.clone(ctx)
					pageContext.pageVisible = visible
					local built = assert(entry.scenario).build(pageContext)
					builtById[entry.id] = built
					local dispose = built.dispose
					if dispose then
						Compose.cleanup(dispose)
					end
					return built.screen()
				end,
			})
		end
		if not outer then
			return UI.TabView {
				Name = key,
				selection = selected,
				tabs = tabs,
				shoulderNavigation = "content",
				Size = UDim2.fromScale(1, 1),
			}
		end
		local home, distant = Compose.cell("automatic"), Compose.cell(false)
		local effective = Compose.formula(function(use: Use): string
			local choice, place = use(preference), use(home)
			if use(distant) or choice == "automatic" or string.find(place, "bottom") ~= nil then
				return place
			end
			return if choice == "side" then "sidebar" else "topBar"
		end)
		local view = UI.TabView {
			Name = key,
			selection = selected,
			tabs = tabs,
			style = "sidebarAdaptable",
			placement = function(use: Use): Placement
				local place = use(effective)
				return if place == use(home) then "automatic" else placementOf(place)
			end,
			Size = UDim2.fromScale(1, 1),
		}
		local env = UI.environment(view)
		Compose.watch(function(use: Use)
			home:set(use(env.navPlacement))
			distant:set(use(env.isTenFoot))
		end)
		local categoryLayout = ctx.categoryLayout
		if categoryLayout then
			local layout: CategoryLayout = {
				placement = effective,
				available = Compose.formula(function(use: Use): boolean
					local place = use(effective)
					return not use(distant) and (place == "sidebar" or place == "topBar")
				end),
				toggle = function()
					preference:set(if effective:peek() == "sidebar" then "top" else "side")
				end,
			}
			categoryLayout:set(layout)
			Compose.cleanup(function()
				if categoryLayout:peek() == layout then
					categoryLayout:set(nil)
				end
			end)
		end
		return view
	end
	return {
		screen = function()
			return Host.Frame(id)({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				tabsFor("Categories", groups, true, ctx.pageVisible),
			})
		end,
		select = function(path: string): boolean
			local entries: { Entry }?, key = groups, "Categories"
			for part in string.gmatch(path, "[^/]+") do
				local found: Entry? = nil
				local currentEntries: { Entry } = entries or {}
				for _, entry in currentEntries do
					if entry.id == part then
						found = entry
						break
					end
				end
				local cell = selections[key]
				if found == nil or cell == nil then
					return false
				end
				cell:set(part)
				key, entries = part, found.tabs
			end
			return true
		end,
		report = function()
			local selected: { [string]: string } = {}
			for key, value in selections do
				selected[key] = value:peek()
			end
			local entries: { Entry }?, key, leaf: string? = groups, "Categories", nil
			while entries do
				local current = selected[key] or entries[1].id
				local found: Entry? = nil
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
			local built = if leaf then builtById[leaf] else nil
			local report = if built then built.report else nil
			return {
				selected = selected,
				active = leaf,
				example = if report then report() else nil,
			}
		end,
	}
end
