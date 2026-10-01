--!strict

local library = require("./library")
local document = require("./document")
local values = require("./value")

local adapter = {}

function adapter.expression(tag: string, data: any?): any
	local result = data or {}
	result.__facetExpression = tag
	return result
end

function adapter.stateKeys(definition: any): { string }
	return definition.states or (if definition.state then { definition.state } else {})
end

function adapter.stateName(node: document.Node, key: string): string
	return "state_" .. node.id .. (if #adapter.stateKeys(library.definitions[node.kind]) == 1 then "" else "_" .. key)
end

function adapter.initial(node: document.Node, key: string): any
	local value = node.props[key]
	if value == nil then
		value = library.definitions[node.kind].defaults[key]
	end
	if node.kind == "DateTimePicker" and key == "value" and node.props.time == true and type(value) == "table" then
		value = document.copy(value)
		value.hour = value.hour or 0
		value.minute = value.minute or 0
	end
	if node.kind == "ColorPicker" and key == "value" then
		return adapter.expression("color", values.color(value))
	end
	return value
end

function adapter.properties(node: document.Node): any
	local definition = library.definitions[node.kind]
	local props = document.copy(definition.defaults)
	for key, item in node.props do
		props[key] = document.copy(item)
	end
	local function expression(tag, data)
		return adapter.expression(tag, data)
	end
	local function state(key)
		return expression("state", { name = adapter.stateName(node, key), initial = adapter.initial(node, key) })
	end
	local function setter(key, constant)
		return expression("setter", { name = adapter.stateName(node, key), constant = constant })
	end
	local function content(nodes: any?)
		return expression("content", { nodes = nodes or node.children })
	end
	local function actions(items: any, key: string)
		for _, item in items or {} do
			if item.children then
				actions(item.children, key)
			elseif not item.divider then
				item[key] = expression("noop")
			end
		end
	end
	for _, descriptor in definition.fields do
		if descriptor.kind == "color" and props[descriptor.key] ~= nil and descriptor.key ~= definition.state then
			props[descriptor.key] = expression("color", values.color(props[descriptor.key]))
		end
	end
	for _, key in adapter.stateKeys(definition) do
		props[key] = state(key)
	end
	if node.kind == "Toggle" and props.mixed ~= nil then
		props.onChange = setter("value")
	end
	if node.kind == "NumberInput" then
		props.value =
			expression("cell", { value = tostring(node.props.numericValue or definition.defaults.numericValue) })
	end
	if node.kind == "Image" or definition.nativeSize then
		props.Size = expression("size", { width = props.width or 240, height = props.height or 140 })
		props.width, props.height = nil, nil
	end
	if definition.content and #node.children > 0 then
		props[definition.content] = content()
		if node.kind == "Card" then
			props.image = nil
		end
	elseif definition.content and node.kind ~= "Card" then
		props[definition.content] = content()
	end
	if node.kind == "ErrorBoundary" then
		props.view, props.fallback = content(), content({})
	end
	if definition.anchor then
		props[definition.anchor] = expression("anchor", { node = node })
		props.anchorLabel = nil
	end
	if node.kind == "Menu" or node.kind == "SplitButton" or node.kind == "RadialMenu" then
		actions(props.items, "onSelect")
	end
	if node.kind == "ComboBox" then
		props.acceptCustom = expression("accept")
	end
	if node.kind == "DateTimePicker" then
		props.onChange = setter("value")
	end
	if node.kind == "Pagination" or node.kind == "Vote" then
		props.onChange = setter(if node.kind == "Pagination" then "page" else "value")
	end
	if node.kind == "StepIndicator" then
		props.onSelect = setter("current")
	end
	if node.kind == "Dialog" or node.kind == "Popover" or node.kind == "Toast" then
		props.onPresentedChange = setter("isPresented")
	end
	if node.kind == "Callout" then
		props.onRetire = setter("isPresented", false)
	end
	if node.kind == "Skeleton" and props.form ~= "line" then
		props.lines = nil
	end
	if node.kind == "LevelPicker" then
		if props.segment == "image" then
			props.images = props.images
				or {
					filled = "rbxassetid://108245103349446",
					empty = "rbxassetid://73716910467356",
				}
		else
			props.images = nil
		end
		if props.segment ~= "glyph" then
			props.glyphs = nil
		end
	end
	if node.kind == "Toast" and (node.props.position ~= nil or node.props.width ~= nil or node.props.fade ~= nil) then
		props.action = nil
		props.closeButton = nil
	end

	if node.kind == "Toast" and props.action then
		props.action.onActivate = setter("isPresented", false)
	end
	if node.kind == "NavBar" then
		props.onBack = expression("noop")
	end
	if node.kind == "Dialog" or node.kind == "Notice" or node.kind == "Sheet" or node.kind == "Callout" then
		actions(props.actions, "onActivate")
	end
	if node.kind == "Card" then
		if props.primaryAction then
			props.primaryAction.onActivate = expression("noop")
		end
		if props.menu then
			actions(props.menu.items, "onSelect")
		end
	end
	if node.kind == "Alert" then
		actions(props.actions, "onActivate")
	end
	if node.kind == "RowActions" then
		actions(props.leading, "onActivate")
		actions(props.trailing, "onActivate")
	end
	if node.kind == "TabView" or node.kind == "PageView" then
		local pages = props[if node.kind == "TabView" then "tabs" else "pages"]
		for index, page in pages do
			page.content = content(if node.children[index] then { node.children[index] } else {})
		end
	end
	if node.kind == "NavigationStack" then
		props.root.content = content(if node.children[1] then { node.children[1] } else {})
		local keys = {}
		for key in props.destinations do
			table.insert(keys, key)
		end
		table.sort(keys)
		for index, key in keys do
			props.destinations[key].content =
				content(if node.children[index + 1] then { node.children[index + 1] } else {})
		end
	end
	if node.kind == "VirtualList" or node.kind == "VirtualGrid" then
		props.render = expression("row")
	end
	if node.kind == "Table" then
		for _, column in props.columns do
			column.value = expression("column", { key = column.id })
		end
	end
	return props
end

function adapter.evaluate(item: any, ctx: any, locals: any): any
	if type(item) ~= "table" then
		return item
	end
	local tag = item.__facetExpression
	local function evaluate(value)
		return adapter.evaluate(value, ctx, locals)
	end
	if tag == "state" then
		if not locals[item.name] then
			locals[item.name] = ctx.Compose.cell(evaluate(item.initial))
		end
		return locals[item.name]
	elseif tag == "cell" then
		return ctx.Compose.cell(evaluate(item.value))
	elseif tag == "color" then
		return ctx.types.Color3.fromRGB(item.r, item.g, item.b)
	elseif tag == "size" then
		return ctx.types.UDim2.fromOffset(item.width, item.height)
	elseif tag == "setter" then
		return function(value)
			locals[item.name]:set(if item.constant ~= nil then item.constant else value)
		end
	elseif tag == "noop" then
		return function() end
	elseif tag == "accept" then
		return function(value)
			return true, value
		end
	elseif tag == "column" then
		return function(row)
			return row[item.key]
		end
	elseif tag == "row" then
		return function(current)
			return ctx.UI.Text "RowLabel" {
				text = function(use)
					local row = use(current)
					return tostring(row.label or row.name or row.id or "Item")
				end,
				wrap = true,
			}
		end
	elseif tag == "content" then
		return function()
			local props = { gap = "s", width = "fill" }
			for _, node in item.nodes do
				table.insert(props, ctx.render(node))
			end
			return ctx.UI.VStack "__FacetDesignContent"(props)
		end
	elseif tag == "anchor" then
		local key = "anchor_" .. item.node.id
		if not locals[key] then
			local definition = library.definitions[item.node.kind]
			locals[key] = ctx.UI.Button(item.node.name .. "Anchor") {
				label = item.node.props.anchorLabel or definition.defaults.anchorLabel,
				onActivate = function()
					locals[adapter.stateName(item.node, "isPresented")]:set(true)
				end,
			}
		end
		return locals[key]
	end
	local result = {}
	for key, child in item do
		result[key] = evaluate(child)
	end
	return result
end

function adapter.emit(item: any, emitNode: any, depth: number?): string
	if type(item) ~= "table" then
		return values.literal(item)
	end
	local level = depth or 0
	local tag = item.__facetExpression
	local function emit(child)
		return adapter.emit(child, emitNode, level + 1)
	end
	if tag == "state" then
		return item.name
	elseif tag == "cell" then
		return "Compose.cell(" .. emit(item.value) .. ")"
	elseif tag == "color" then
		return `Color3.fromRGB({item.r}, {item.g}, {item.b})`
	elseif tag == "size" then
		return `UDim2.fromOffset({item.width}, {item.height})`
	elseif tag == "setter" then
		return "function(value) "
			.. item.name
			.. ":set("
			.. (if item.constant ~= nil then values.literal(item.constant) else "value")
			.. ") end"
	elseif tag == "noop" then
		return "function() end"
	elseif tag == "accept" then
		return "function(value) return true, value end"
	elseif tag == "column" then
		return "function(row) return row[" .. values.literal(item.key) .. "] end"
	elseif tag == "row" then
		return 'function(current) return UI.Text "RowLabel" { text = function(use) local row = use(current) return tostring(row.label or row.name or row.id or "Item") end, wrap = true } end'
	elseif tag == "anchor" then
		return "anchor_" .. item.node.id
	elseif tag == "content" then
		local lines = { 'function() return UI.VStack "__FacetDesignContent" { gap = "s", width = "fill",' }
		for _, node in item.nodes do
			table.insert(lines, emitNode(node, level + 1) .. ",")
		end
		table.insert(lines, "} end")
		return table.concat(lines, "\n")
	end
	local keys, pieces = {}, {}
	for key in item do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then
			return a < b
		end
		return type(a) == "number"
	end)
	for _, key in keys do
		table.insert(pieces, "[" .. values.literal(key) .. "] = " .. emit(item[key]))
	end
	return "{ " .. table.concat(pieces, ", ") .. " }"
end

return adapter
