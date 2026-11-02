--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Nav = require("./navigation_types")
local NavigationProps = require("./navigation_props")

export type MenuEntry<V> = { key: string, heading: string?, item: Nav.MenuItem<V>?, ruled: boolean? }
type Draft<V> = Nav.MenuItem<V> & { id: string?, children: Nav.Input<{ Nav.MenuItem<V> }>? }
export type BuildMenu = <V>(spec: NavigationProps.MenuSpec<V>, wrap: boolean) -> GuiObject

return function(ctx: Types.Context)
	local read = ctx.read
	local DIM_FIELDS: { [string]: { [string]: boolean } } = {
		fixed = { px = true },
		fill = { weight = true, min = true, max = true },
		hug = { min = true, max = true },
		percent = { fraction = true, offset = true, min = true, max = true },
		content = {},
		minMax = { min = true, preferred = true, max = true },
	}
	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and math.abs(value) < math.huge
	end
	local function checkWidth(width: unknown)
		if width == nil then
			return
		end
		if type(width) == "number" then
			assert(
				finite(width) and width > 0,
				"Facet UI.Menu: width must be a finite number of pixels above 0, a UDim, a UDim2 or a dimension table"
			)
			return
		end
		if typeof(width) == "UDim" or typeof(width) == "UDim2" then
			return
		end
		assert(
			type(width) == "table",
			"Facet UI.Menu: width must be a number of pixels, a UDim, a UDim2 or a dimension table"
		)
		local dim = width :: { [string]: unknown }
		local fields = DIM_FIELDS[tostring(dim.type)]
		if fields == nil then
			error(
				`Facet UI.Menu: width.type must be fixed, fill, hug, percent, content or minMax (got {tostring(dim.type)})`,
				0
			)
		end
		for key, value in dim do
			if key ~= "type" then
				if not fields[key] then
					error(`Facet UI.Menu: a {tostring(dim.type)} width does not take '{tostring(key)}'`, 0)
				end
				if not (finite(value) or (type(value) == "string" and key ~= "fraction" and key ~= "weight")) then
					error(`Facet UI.Menu: width.{tostring(key)} must be a finite number or a theme metric name`, 0)
				end
			end
		end
		if dim.type == "fixed" then
			assert(dim.px ~= nil, "Facet UI.Menu: a fixed width requires px")
		elseif dim.type == "percent" then
			assert(dim.fraction ~= nil, "Facet UI.Menu: a percent width requires fraction")
		end
	end
	local function length(value: Nav.MenuDimLength?, use: ComposeTypes.Use?): number?
		if value == nil then
			return nil
		end
		return if type(value) == "string" then ctx.metric(value, use) else value
	end
	local function resolveWidth(width: Nav.MenuWidth, natural: number, room: number, use: ComposeTypes.Use?): number
		if type(width) == "number" then
			return width
		end
		if typeof(width) == "UDim" then
			local udim = width :: UDim
			return udim.Scale * room + udim.Offset
		end
		if typeof(width) == "UDim2" then
			local udim = (width :: UDim2).X
			return udim.Scale * room + udim.Offset
		end
		local dim = width :: Nav.MenuDim
		local lower, upper = length(dim.min, use) or 0, length(dim.max, use) or math.huge
		local value = if dim.type == "fixed"
			then assert(length(dim.px, use))
			elseif dim.type == "fill" then room
			elseif dim.type == "percent" then (dim.fraction or 0) * room + (dim.offset or 0)
			elseif dim.type == "minMax" then length(dim.preferred, use) or natural
			else natural
		return math.max(0, math.clamp(value, lower, math.max(lower, upper)))
	end
	local function actionItem<V>(item: Nav.MenuItem<V>): Nav.MenuAction<V>
		assert(item.divider ~= true, "Menu action cannot be a divider")
		return item
	end
	local function commitItem<V>(item: Nav.MenuAction<V>): boolean
		if read(item.enabled) == false then
			return false
		end
		if item.checked then
			item.checked:set(not item.checked:peek())
			if item.onChange then
				item.onChange(item.checked:peek())
			end
		elseif item.selected then
			item.selected:set(item.value)
			if item.onChange then
				item.onChange(item.value)
			end
		end
		local onSelect: (() -> ())? = item.onSelect
		if onSelect then
			onSelect()
		end
		return true
	end
	local function menuItems<V>(items: { Nav.MenuItem<V> }, use: ComposeTypes.Use?): { Nav.MenuItem<V> }
		local readItems = read<<{ Nav.MenuItem<V> }>>
		assert(type(items) == "table", "Menu.items must be an array")
		local result: { Nav.MenuItem<V> } = {}
		local identifiers: { [string]: boolean } = {}
		for index = 1, #items do
			local source = items[index]
			local copy = table.clone(source) :: Draft<V>
			local id: string = source.id or tostring(index)
			copy.id = id
			local item: Nav.MenuItem<V> = copy
			assert(not identifiers[id], `Facet UI.Menu: two items at one level share the id '{id}'`)
			identifiers[id] = true
			if item.divider ~= true and item.avatar ~= nil then
				for key in (item.avatar :: unknown) :: { [string]: unknown } do
					if key ~= "name" and key ~= "image" and key ~= "userId" then
						error(`Facet UI.Menu: an avatar takes name, image and userId, not '{key}'`, 0)
					end
				end
			end
			if not item.divider then
				assert(
					type(read(item.label, use)) == "string"
						and string.find(read<<string>>(item.label, use), "%S") ~= nil,
					"Menu items require nonempty labels"
				)
				assert(not (item.children and item.onSelect), "A menu item cannot have both children and onSelect")
				assert(
					item.children or item.onSelect or item.checked or item.selected,
					"Menu items require an action, submenu, or selection state"
				)
				assert(not (item.checked and item.selected), "A menu item cannot be both checked and selected")
				if item.children then
					copy.children = menuItems(readItems(item.children, use), use)
				end
			end
			table.insert(result, item)
		end
		return result
	end
	local function advice<V>(items: { Nav.MenuItem<V> }, path: string, depth: number, notes: { string }): { string }
		local readItems = read<<{ Nav.MenuItem<V> }>>
		local actions, destructive = 0, nil :: number?
		for index, item in items do
			if item.divider ~= true then
				actions += 1
				if read(item.role) == "destructive" then
					destructive = index
				end
				if item.children then
					local id = item.id or tostring(index)
					if depth + 1 >= 2 then
						table.insert(
							notes,
							`Facet UI.Menu: submenu '{id}' nests {depth + 1} levels deep. The platform guidance advises a single level.`
						)
					end
					advice(readItems(item.children), `{path}[{index}].children`, depth + 1, notes)
				end
			end
		end
		if actions > 5 then
			table.insert(notes, `Facet UI.Menu: {path} holds {actions} items; past about five, consider a new menu.`)
		end
		if destructive and destructive ~= #items then
			table.insert(
				notes,
				`Facet UI.Menu: {path}[{destructive}] is destructive but not last; put destructive items at the end of the menu.`
			)
		end
		return notes
	end
	return {
		checkWidth = checkWidth,
		resolveWidth = resolveWidth,
		actionItem = actionItem,
		commitItem = commitItem,
		menuItems = menuItems,
		advice = advice,
	}
end
