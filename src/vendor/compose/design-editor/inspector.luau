--!strict

local UI = require "./ui"

local Compose = require "../core"
local Design = require "../design"
local Datatype = Design.datatype

export type Inspector = {
	root: Compose.Node,
	dispose: () -> (),
}

export type Options = {
	tokens: { string }?,
	measure: ((id: string, key: string) -> number?)?,
	play: ((sequence: string) -> ())?,
}

return function(ui: UI.UI)
	local Theme = require "./theme"(ui)
	local color = Theme.color
	local size = Theme.size
	local LABEL = 112
	local GROUPS = { "Layout", "Auto layout", "Fill", "Text", "Image", "Interaction" }

	local function describe(value: Design.Value?): string
		if value == nil then
			return ""
		end
		local input, item, output, token, node = value.input, value.item, value.output, value.token, value.node
		local held, played, role = value.state, value.play, value.motion
		local moving = if role then "  〜 " .. role else ""
		if node then
			return "◎ " .. node
		elseif played then
			return "▶ " .. played
		elseif held then
			return "state." .. held .. moving
		elseif input then
			return input .. moving
		elseif item then
			return "item." .. item .. moving
		elseif output then
			return "→ " .. output
		elseif token then
			return token
		end
		return ""
	end

	local function glyphOf(value: Design.Value): string
		if value.token then
			return "◆"
		elseif value.play then
			return "▶"
		elseif value.output then
			return "⚡"
		end
		return "⛓"
	end

	local function choices(value: Design.Document, field: Design.Field, tokens: { string }): { Design.Value }
		local list: { Design.Value } = {}
		if field.type == "event" then
			for _, output in value.contract.outputs do
				table.insert(list, { output = output.id })
			end
			local sequences = value.sequences
			if sequences then
				for _, sequence in sequences do
					table.insert(list, { play = sequence.id })
				end
			end
			return list
		end
		if field.type == "node" then
			local function visit(node: Design.Node)
				table.insert(list, { node = node.id })
				for _, child in node.children do
					visit(child)
				end
			end
			visit(value.root)
			return list
		end
		for _, input in value.contract.inputs do
			local slot = input.type == "slot"
			if slot == (field.type == "content") then
				table.insert(list, { input = input.id })
			end
		end
		local state = value.state
		if state and field.type ~= "content" then
			for _, entry in state do
				table.insert(list, { state = entry.id })
			end
		end
		if field.tokens then
			for _, name in tokens do
				table.insert(list, { token = name })
			end
		end
		return list
	end

	local function same(left: Design.Value?, right: Design.Value): boolean
		return left ~= nil
			and left.input == right.input
			and left.output == right.output
			and left.token == right.token
			and left.item == right.item
			and left.node == right.node
			and left.state == right.state
			and left.play == right.play
	end

	local function humanize(key: string): string
		local trimmed = string.gsub(key, "Color3$", "Color")
		local spaced = string.gsub(string.gsub(trimmed, "(%u)(%u%l)", "%1 %2"), "(%l)(%u)", "%1 %2")
		return string.upper(string.sub(spaced, 1, 1)) .. string.lower(string.sub(spaced, 2))
	end

	local function hex(text: string): unknown?
		if string.match(text, "^#%x%x%x%x%x%x$") then
			return ui.hex(text)
		end
		return nil
	end

	return function(session: Design.Session, parent: Compose.Node, options: Options?): Inspector
		local settings: Options = options or {}
		local tokens = settings.tokens or {}
		local scroller = Theme.scroller "DesignInspector"
		ui.set(scroller, "Size", ui.values.udim2(1, 0, 1, 0))
		Theme.list(scroller, ui.values.enum("FillDirection", "Vertical"), 0)
		ui.set(scroller, "Parent", parent)
		local built: { Compose.Node } = {}
		local connections: { UI.Connection } = {}
		local function track(list: { UI.Connection })
			for _, connection in list do
				table.insert(connections, connection)
			end
		end
		local function clear()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			for _, instance in built do
				ui.destroy(instance)
			end
			table.clear(built)
		end
		type Scrub = { key: string, box: Compose.Node, from: number, start: number, value: number }
		local scrub: Scrub? = nil
		local UserInputService = ui.service "UserInputService"
		local scrubMoved = ui.connect(UserInputService, "InputChanged", function(input: Compose.Node)
			local active = scrub
			if active and ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseMovement") then
				local step = if ui.call(UserInputService, "IsKeyDown", ui.values.enum("KeyCode", "LeftShift"))
						== true
					then 10
					else 1
				active.value =
					math.max(0, active.start + math.round((ui.xy(input, "Position").X - active.from) / 2) * step)
				ui.set(active.box, "Text", tostring(active.value))
			end
		end)
		local scrubEnded = ui.connect(UserInputService, "InputEnded", function(input: Compose.Node)
			local active = scrub
			if active and ui.get(input, "UserInputType") == ui.values.enum("UserInputType", "MouseButton1") then
				scrub = nil
				if active.value ~= active.start then
					session.change(active.key, { literal = active.value })
				end
			end
		end)
		local order = 0
		local function block(name: string, height: number): Compose.Node
			order += 1
			local frame = Theme.frame(name)
			ui.set(frame, "Size", ui.values.udim2(1, 0, 0, height))
			ui.set(frame, "LayoutOrder", order)
			ui.set(frame, "Parent", scroller)
			table.insert(built, frame)
			return frame
		end
		local function field(text: string, commit: (string) -> (), mono: boolean?): Compose.Node
			local created = ui.new "TextBox"
			ui.set(created, "BackgroundColor3", color.field)
			ui.set(created, "BorderSizePixel", 0)
			ui.set(created, "Text", text)
			ui.set(created, "PlaceholderText", "—")
			ui.set(created, "PlaceholderColor3", color.tertiary)
			ui.set(created, "TextColor3", color.text)
			ui.set(created, "TextSize", size.text)
			ui.set(created, "FontFace", if mono then Theme.font.mono else Theme.font.medium)
			ui.set(created, "ClearTextOnFocus", false)
			ui.set(created, "TextXAlignment", ui.values.enum("TextXAlignment", "Left"))
			ui.set(created, "TextTruncate", ui.values.enum("TextTruncate", "AtEnd"))
			Theme.corner(created, 4)
			Theme.pad(created, 8)
			local ring = Theme.stroke(created, color.accent, 1, 1)
			track {
				ui.connect(created, "Focused", function()
					ui.set(ring, "Transparency", 0)
				end),
				ui.connect(created, "FocusLost", function()
					ui.set(ring, "Transparency", 1)
					if ui.text(created, "Text") ~= text then
						commit(ui.text(created, "Text"))
					end
				end),
			}
			return created
		end
		local function pressable(
			name: string,
			rest: unknown,
			over: unknown,
			activate: () -> (),
			transparency: number?
		): Compose.Node
			local created = ui.new "TextButton"
			ui.set(created, "Name", name)
			ui.set(created, "BorderSizePixel", 0)
			ui.set(created, "AutoButtonColor", false)
			ui.set(created, "Text", "")
			ui.set(created, "BackgroundTransparency", transparency or 0)
			Theme.corner(created, 4)
			track(Theme.hover(created, rest, over, transparency))
			track {
				ui.connect(created, "Activated", function()
					activate()
				end),
			}
			return created
		end
		local function toggle(on: boolean, set: boolean, activate: () -> ()): Compose.Node
			local switch = pressable(
				"Toggle",
				if on then color.accent else color.raised,
				if on then color.accent else color.hover,
				activate,
				if set then 0 else 0.55
			)
			ui.set(switch, "Size", ui.values.udim2(0, 36, 0, 22))
			Theme.corner(switch, 11)
			local knob = Theme.frame("Knob", color.white)
			ui.set(knob, "Size", ui.values.udim2(0, 18, 0, 18))
			ui.set(knob, "AnchorPoint", ui.values.vector2(0, 0.5))
			ui.set(knob, "Position", ui.values.udim2(0, if on then 16 else 2, 0.5, 0))
			ui.set(knob, "BackgroundTransparency", if set then 0 else 0.35)
			Theme.corner(knob, 9)
			ui.set(knob, "Parent", switch)
			return switch
		end
		local function segmented(list: { string }, current: string?, pick: (string) -> ()): Compose.Node
			local frame = Theme.frame("Segmented", color.field)
			Theme.corner(frame, 4)
			Theme.pad(frame, 2, 2, 2, 2)
			local layout = Theme.list(frame, ui.values.enum("FillDirection", "Horizontal"), 2)
			ui.set(layout, "HorizontalFlex", ui.values.enum("UIFlexAlignment", "Fill"))
			for index, option in list do
				local active = option == current
				local segment = pressable(option, if active then color.raised else color.field, color.hover, function()
					pick(option)
				end)
				ui.set(segment, "LayoutOrder", index)
				ui.set(segment, "Size", ui.values.udim2(0, 0, 1, 0))
				ui.set(segment, "Text", humanize(option))
				ui.set(segment, "TextSize", size.small)
				ui.set(segment, "TextScaled", true)
				local cap = ui.new "UITextSizeConstraint"
				ui.set(cap, "MaxTextSize", size.small)
				ui.set(cap, "MinTextSize", 8)
				ui.set(cap, "Parent", segment)
				Theme.pad(segment, 4, 4, 0, 0)
				ui.set(segment, "FontFace", if active then Theme.font.bold else Theme.font.medium)
				ui.set(segment, "TextColor3", if active then color.text else color.secondary)
				Theme.corner(segment, 3)
				ui.set(segment, "Parent", frame)
			end
			return frame
		end
		local function editorSlot(row: Compose.Node): Compose.Node
			local slot = Theme.frame "Editor"
			ui.set(slot, "Size", ui.values.udim2(1, -LABEL - 30, 1, -4))
			ui.set(slot, "AnchorPoint", ui.values.vector2(0, 0.5))
			ui.set(slot, "Position", ui.values.udim2(0, LABEL, 0.5, 0))
			ui.set(slot, "Parent", row)
			return slot
		end
		local showAdvanced = Compose.cell(false)
		local function render(value: Design.Document, id: string, advancedOpen: boolean)
			clear()
			order = 0
			local node = Design.document.find(value.root, id)
			if node == nil then
				return
			end
			local kind = session.library.kinds[node.kind]
			local header = block("Header", 56)
			Theme.pad(header, size.gutter, size.gutter, 10, 10)
			local badge = Theme.frame("Badge", color.accentSoft)
			ui.set(badge, "Size", ui.values.udim2(0, 28, 0, 28))
			ui.set(badge, "AnchorPoint", ui.values.vector2(0, 0.5))
			ui.set(badge, "Position", ui.values.udim2(0, 0, 0.5, 0))
			Theme.corner(badge, 6)
			local glyph = Theme.label(Theme.glyph[node.kind] or "◇", color.accent, 14, Theme.font.bold)
			ui.set(glyph, "Size", ui.values.udim2(1, 0, 1, 0))
			ui.set(glyph, "TextXAlignment", ui.values.enum("TextXAlignment", "Center"))
			ui.set(glyph, "Parent", badge)
			ui.set(badge, "Parent", header)
			local name = field(node.name, function(text: string)
				session.rename(text)
			end)
			ui.set(name, "Name", "NodeName")
			ui.set(name, "BackgroundTransparency", 1)
			ui.set(name, "TextSize", size.title)
			ui.set(name, "FontFace", Theme.font.bold)
			ui.set(name, "Position", ui.values.udim2(0, 36, 0, 0))
			ui.set(name, "Size", ui.values.udim2(1, -36, 0, 20))
			ui.set(name, "Parent", header)
			local kindLabel = Theme.label(node.kind, color.tertiary, size.small)
			ui.set(kindLabel, "Position", ui.values.udim2(0, 44, 0, 20))
			ui.set(kindLabel, "Size", ui.values.udim2(1, -44, 0, 16))
			ui.set(kindLabel, "Parent", header)
			local function section(title: string)
				local frame = block(title, 36)
				local rule = Theme.frame("Rule", color.divider)
				ui.set(rule, "Size", ui.values.udim2(1, 0, 0, 1))
				ui.set(rule, "Parent", frame)
				local caption = Theme.label(title, color.text, size.small, Theme.font.bold)
				ui.set(caption, "Position", ui.values.udim2(0, size.gutter, 0, 12))
				ui.set(caption, "Size", ui.values.udim2(1, -2 * size.gutter, 0, 18))
				ui.set(caption, "Parent", frame)
			end
			local function row(key: string, title: string): (Compose.Node, Compose.Node)
				local frame = block(key, 32)
				Theme.pad(frame, size.gutter)
				local caption = Theme.label(title, color.secondary, size.small)
				ui.set(caption, "Name", "Label")
				ui.set(caption, "Size", ui.values.udim2(0, LABEL - 6, 1, 0))
				ui.set(caption, "TextWrapped", true)
				ui.set(caption, "TextTruncate", ui.values.enum("TextTruncate", "AtEnd"))
				ui.set(caption, "Parent", frame)
				return frame, caption
			end
			if session.library.tags ~= nil then
				local tagRow = row("Tags", "Style tags")
				local tags = field(table.concat(node.tags or {}, ", "), function(text: string)
					local tags: { string } = {}
					for tag in string.gmatch(text, "[^,%s]+") do
						table.insert(tags, tag)
					end
					session.tag(if #tags > 0 then tags else nil)
				end, true)
				ui.set(tags, "PlaceholderText", "None")
				ui.set(tags, "Size", ui.values.udim2(1, 0, 1, 0))
				ui.set(tags, "Parent", editorSlot(tagRow))
			end
			if kind.children == "template" then
				section "Data"
				local lists: { string } = {}
				for _, input in value.contract.inputs do
					if input.type == "list" then
						table.insert(lists, input.id)
					end
				end
				local bind = node.bind
				local current = if bind then bind.from else nil
				local listRow = row("List", "Source")
				local slot = editorSlot(listRow)
				if #lists > 0 then
					local picker = segmented(lists, current, function(chosen: string)
						session.bind { from = chosen, key = if bind then bind.key else "id" }
					end)
					ui.set(picker, "Size", ui.values.udim2(1, 0, 1, 0))
					ui.set(picker, "Parent", slot)
				else
					local empty = Theme.label("No list inputs", color.tertiary, size.small)
					ui.set(empty, "Size", ui.values.udim2(1, 0, 1, 0))
					ui.set(empty, "Parent", slot)
				end
				if bind then
					local keyRow = row("Key", "Key")
					local keySlot = editorSlot(keyRow)
					local keyBox = field(bind.key, function(text: string)
						session.bind { from = bind.from, key = text }
					end, true)
					ui.set(keyBox, "Size", ui.values.udim2(1, 0, 1, 0))
					ui.set(keyBox, "Parent", keySlot)
				end
			end
			local grouped: { [string]: { string } } = {}
			local extra: { string } = {}
			local advancedKeys: { string } = {}
			for key, entry in kind.fields do
				if not Design.document.applies(node, kind, key) then
					continue
				end
				if entry.advanced and node.props[key] == nil then
					table.insert(advancedKeys, key)
					continue
				end
				local group = entry.group or "Properties"
				if grouped[group] == nil then
					grouped[group] = {}
					if not table.find(GROUPS, group) then
						table.insert(extra, group)
					end
				end
				table.insert(grouped[group], key)
			end
			table.sort(extra)
			local sequence = table.clone(GROUPS)
			for _, group in extra do
				table.insert(sequence, group)
			end
			local function renderGroups(sequenceList: { string }, groupedKeys: { [string]: { string } })
				for _, group in sequenceList do
					local keys = groupedKeys[group]
					if keys == nil then
						continue
					end
					table.sort(keys, function(left: string, right: string): boolean
						local a, b = kind.fields[left].order or math.huge, kind.fields[right].order or math.huge
						if a == b then
							return left < right
						end
						return a < b
					end)
					section(group)
					for _, key in keys do
						local entry = kind.fields[key]
						local property = node.props[key]
						local line, caption = row(key, entry.label or humanize(key))
						local slot = editorSlot(line)
						local literal = if property then property.literal else nil
						local contentKind = session.library.contentKind
						if property and literal == nil then
							local pill = pressable("Binding", color.accentSoft, color.hover, function()
								session.change(key, nil)
							end)
							ui.set(pill, "Size", ui.values.udim2(1, 0, 1, 0))
							local target = property.node
							local named = if target then Design.document.find(value.root, target) else nil
							ui.set(
								pill,
								"Text",
								glyphOf(property) .. "  " .. if named then "◎ " .. named.name else describe(property)
							)
							ui.set(pill, "TextColor3", color.accent)
							ui.set(pill, "TextSize", size.small)
							ui.set(pill, "FontFace", Theme.font.bold)
							ui.set(pill, "TextXAlignment", ui.values.enum("TextXAlignment", "Left"))
							ui.set(pill, "TextTruncate", ui.values.enum("TextTruncate", "AtEnd"))
							Theme.pad(pill, 8)
							ui.set(pill, "Parent", slot)
						elseif entry.type == "boolean" then
							local fallback = entry.default
							local defaults = kind.defaults
							if fallback == nil and defaults then
								fallback = defaults[key]
							end
							local on = if literal ~= nil then literal == true else fallback == true
							local switch = toggle(on, literal ~= nil, function()
								session.change(key, { literal = not on })
							end)
							ui.set(switch, "AnchorPoint", ui.values.vector2(0, 0.5))
							ui.set(switch, "Position", ui.values.udim2(0, 0, 0.5, 0))
							ui.set(switch, "Parent", slot)
						elseif entry.type == "choice" and #(entry.options or {}) > 3 then
							local list = entry.options or {}
							local current = if type(literal) == "string" then literal else nil
							local picker = pressable("Picker", color.field, color.hover, function()
								local at = if current then table.find(list, current) or 0 else 0
								session.change(key, { literal = list[at % #list + 1] })
							end)
							ui.set(picker, "Size", ui.values.udim2(1, 0, 1, 0))
							ui.set(picker, "Text", (if current then humanize(current) else "Auto") .. "  ▾")
							ui.set(picker, "TextColor3", if current then color.text else color.tertiary)
							ui.set(picker, "TextSize", size.small)
							ui.set(picker, "FontFace", Theme.font.medium)
							ui.set(picker, "TextXAlignment", ui.values.enum("TextXAlignment", "Left"))
							Theme.pad(picker, 8)
							ui.set(picker, "Parent", slot)
						elseif entry.type == "choice" then
							local picker = segmented(
								entry.options or {},
								if type(literal) == "string" then literal else nil,
								function(chosen: string)
									session.change(key, { literal = chosen })
								end
							)
							ui.set(picker, "Size", ui.values.udim2(1, 0, 1, 0))
							ui.set(picker, "Parent", slot)
						elseif entry.type == "number" then
							local box = field(
								if type(literal) == "number" then tostring(literal) else "",
								function(text: string)
									local number = tonumber(text)
									if number then
										session.change(key, { literal = number })
									elseif text == "" then
										session.change(key, nil)
									end
								end,
								true
							)
							ui.set(box, "PlaceholderText", "Auto")
							ui.set(box, "Size", ui.values.udim2(1, 0, 1, 0))
							ui.set(caption, "Active", true)
							track {
								ui.connect(caption, "InputBegan", function(input: Compose.Node)
									if
										ui.get(input, "UserInputType")
										== ui.values.enum("UserInputType", "MouseButton1")
									then
										local measured = if settings.measure then settings.measure(id, key) else nil
										local start = if type(literal) == "number"
											then literal
											else tonumber(ui.text(box, "Text")) or math.round(measured or 0)
										scrub = {
											key = key,
											box = box,
											from = ui.xy(input, "Position").X,
											start = start,
											value = start,
										}
									end
								end),
								ui.connect(caption, "MouseEnter", function()
									ui.set(caption, "TextColor3", color.text)
								end),
								ui.connect(caption, "MouseLeave", function()
									ui.set(caption, "TextColor3", color.secondary)
								end),
							}
							ui.set(box, "Parent", slot)
						elseif entry.type == "color" then
							local text = if type(literal) == "string" then literal else ""
							local box = field(text, function(changed: string)
								session.change(key, if changed == "" then nil else { literal = changed })
							end, true)
							ui.set(box, "PlaceholderText", "None")
							ui.set(box, "Size", ui.values.udim2(1, 0, 1, 0))
							Theme.pad(box, 30, 8)
							local swatch = Theme.frame("Swatch", hex(text) or color.field)
							ui.set(swatch, "Size", ui.values.udim2(0, 14, 0, 14))
							ui.set(swatch, "AnchorPoint", ui.values.vector2(0, 0.5))
							ui.set(swatch, "Position", ui.values.udim2(0, -22, 0.5, 0))
							Theme.corner(swatch, 3)
							Theme.stroke(swatch, color.white, 1, if hex(text) then 0.85 else 0.6)
							ui.set(swatch, "Parent", box)
							ui.set(box, "Parent", slot)
						elseif entry.type == "vector3" then
							local components: { number } = {}
							if type(literal) == "table" then
								for index = 1, 3 do
									local component = literal[index]
									components[index] = if type(component) == "number" then component else 0
								end
							else
								components = { 0, 0, 0 }
							end
							local layout = Theme.list(slot, ui.values.enum("FillDirection", "Horizontal"), 4)
							ui.set(layout, "HorizontalFlex", ui.values.enum("UIFlexAlignment", "Fill"))
							for index, axis in { "X", "Y", "Z" } do
								local cell = field(tostring(components[index]), function(text: string)
									local number = tonumber(text)
									if number then
										local nextValue: { [string | number]: Design.Literal } = {}
										for position = 1, 3 do
											nextValue[position] = if position == index
												then number
												else components[position]
										end
										session.change(key, { literal = nextValue })
									end
								end, true)
								ui.set(cell, "Name", axis)
								ui.set(cell, "LayoutOrder", index)
								ui.set(cell, "Size", ui.values.udim2(0, 0, 1, 0))
								Theme.pad(cell, 16, 4)
								local tag = Theme.label(axis, color.tertiary, size.small, Theme.font.bold)
								ui.set(tag, "Position", ui.values.udim2(0, -12, 0, 0))
								ui.set(tag, "Size", ui.values.udim2(0, 10, 1, 0))
								ui.set(tag, "Parent", cell)
								ui.set(cell, "Parent", slot)
							end
						elseif entry.type == "string" then
							local box = field(if type(literal) == "string" then literal else "", function(text: string)
								session.change(key, if text == "" then nil else { literal = text })
							end)
							ui.set(box, "Size", ui.values.udim2(1, 0, 1, 0))
							ui.set(box, "Parent", slot)
						elseif
							entry.type == "datatype"
							and entry.datatype ~= nil
							and Datatype.arity[entry.datatype] ~= nil
						then
							local arity = Datatype.arity[entry.datatype]
							local defaults = kind.defaults
							local fallback = if defaults then defaults[key] else entry.default
							local current = if type(literal) == "table"
								then literal
								else if type(fallback) == "table" then fallback else {}
							local components: { [string | number]: Design.Literal } = {}
							for index = 1, arity do
								components[index] = current[index] or 0
							end
							ui.set(line, "Size", ui.values.udim2(1, 0, 0, arity * 32))
							Theme.list(slot, ui.values.enum("FillDirection", "Vertical"), 4)
							for index = 1, arity do
								local component = components[index]
								local name = Datatype.token(component)
								local cell = Theme.frame(`Component{index}`)
								ui.set(cell, "LayoutOrder", index)
								ui.set(cell, "Size", ui.values.udim2(1, 0, 0, 28))
								local label = Theme.label(tostring(index), color.tertiary, size.small)
								ui.set(label, "Size", ui.values.udim2(0, 14, 1, 0))
								ui.set(label, "Parent", cell)
								local function change(next: Design.Literal)
									local changed = table.clone(components)
									changed[index] = next
									session.change(key, { literal = changed })
								end
								local box = field(name or tostring(component), function(text: string)
									local number = tonumber(text)
									if number then
										change(number)
									elseif text == "" then
										change(0)
									end
								end, true)
								ui.set(
									box,
									"Size",
									ui.values.udim2(1, if entry.tokens and #tokens > 0 then -38 else -18, 1, 0)
								)
								ui.set(box, "Position", ui.values.udim2(0, 18, 0, 0))
								ui.set(box, "TextColor3", if name then color.accent else color.text)
								ui.set(box, "Parent", cell)
								if entry.tokens and #tokens > 0 then
									local bind = pressable("Bind", color.panel, color.hover, function()
										local at = if name then table.find(tokens, name) or 0 else 0
										local reference: { [string | number]: Design.Literal } =
											{ token = tokens[at % #tokens + 1] }
										change(reference)
									end, 1)
									ui.set(bind, "Size", ui.values.udim2(0, 20, 1, 0))
									ui.set(bind, "Position", ui.values.udim2(1, -20, 0, 0))
									ui.set(bind, "Text", "◆")
									ui.set(bind, "TextSize", size.small)
									ui.set(bind, "TextColor3", if name then color.accent else color.tertiary)
									ui.set(bind, "Parent", cell)
								end
								ui.set(cell, "Parent", slot)
							end
						elseif entry.type == "value" or entry.type == "datatype" then
							local box = field(
								if literal ~= nil then Design.literal(literal) else "",
								function(text: string)
									if text == "" then
										session.change(key, nil)
										return
									end
									local parsed, result = pcall(Design.parseLiteral, text)
									if parsed then
										session.change(key, { literal = result })
									else
										session.problem:set(`{entry.label or humanize(key)}: {result}`)
									end
								end,
								true
							)
							ui.set(box, "Size", ui.values.udim2(1, 0, 1, 0))
							ui.set(box, "Parent", slot)
						elseif
							entry.type == "content"
							and type(literal) == "table"
							and type(literal["$template"]) == "string"
						then
							local childId: string = literal["$template"]
							local open = pressable("OpenContent", color.accentSoft, color.hover, function()
								session.select(childId)
							end)
							ui.set(open, "Size", ui.values.udim2(1, 0, 1, 0))
							local found = Design.document.find(value.root, childId)
							ui.set(open, "Text", "◇ " .. (if found then found.name else childId))
							ui.set(open, "TextColor3", color.accent)
							ui.set(open, "TextSize", size.small)
							ui.set(open, "Parent", slot)
						elseif entry.type == "content" and contentKind ~= nil then
							local add = pressable("AddContent", color.panel, color.hover, function()
								session.content(key, contentKind)
							end)
							ui.set(add, "Size", ui.values.udim2(1, 0, 1, 0))
							ui.set(add, "Text", "+ " .. contentKind)
							ui.set(add, "TextColor3", color.accent)
							ui.set(add, "TextSize", size.small)
							ui.set(add, "Parent", slot)
						else
							local hint = Theme.label("Not bound", color.tertiary, size.small)
							ui.set(hint, "Size", ui.values.udim2(1, 0, 1, 0))
							ui.set(hint, "Parent", slot)
						end
						local available = choices(value, entry, tokens)
						if #available > 0 then
							local bound = property ~= nil and literal == nil
							local link = pressable("Bind", color.panel, color.hover, function()
								local at = 0
								for index, option in available do
									if same(property, option) then
										at = index
									end
								end
								local chosen = table.clone(available[at % #available + 1])
								local follows = chosen.input ~= nil or chosen.state ~= nil or chosen.item ~= nil
								chosen.motion = if property and follows then property.motion else nil
								session.change(key, chosen)
							end, 1)
							ui.set(link, "Size", ui.values.udim2(0, 24, 0, 24))
							ui.set(link, "AnchorPoint", ui.values.vector2(1, 0.5))
							ui.set(link, "Position", ui.values.udim2(1, 0, 0.5, 0))
							ui.set(
								link,
								"Text",
								if entry.type == "event" then "⚡" elseif entry.tokens then "◆" else "⛓"
							)
							ui.set(link, "TextSize", size.small)
							ui.set(link, "FontFace", Theme.font.bold)
							ui.set(link, "TextColor3", if bound then color.accent else color.tertiary)
							ui.set(link, "Parent", line)
						end
						local motion = session.library.motion
						local follows = property ~= nil
							and (property.input ~= nil or property.state ~= nil or property.item ~= nil)
						if motion ~= nil and property ~= nil and follows then
							local current = property
							local roles = motion.roles
							local moves = pressable("Motion", color.panel, color.hover, function()
								local at = if current.motion then table.find(roles, current.motion) or 0 else 0
								local moved = table.clone(current)
								moved.motion = roles[at + 1]
								session.change(key, moved)
							end, 1)
							ui.set(moves, "Size", ui.values.udim2(0, 24, 0, 24))
							ui.set(moves, "AnchorPoint", ui.values.vector2(1, 0.5))
							ui.set(moves, "Position", ui.values.udim2(1, -28, 0.5, 0))
							ui.set(moves, "Text", "〜")
							ui.set(moves, "TextSize", size.small)
							ui.set(moves, "FontFace", Theme.font.bold)
							ui.set(moves, "TextColor3", if current.motion then color.accent else color.tertiary)
							ui.set(moves, "Parent", line)
						end
					end
				end
			end
			renderGroups(sequence, grouped)
			if #advancedKeys > 0 then
				local toggleFrame = block("AdvancedToggle", 36)
				local toggle = pressable("Advanced", color.raised, color.hover, function()
					showAdvanced:set(not showAdvanced:peek())
				end)
				ui.set(
					toggle,
					"Text",
					if advancedOpen then `Advanced  ▾  {#advancedKeys}` else `Advanced  ▸  {#advancedKeys}`
				)
				ui.set(toggle, "TextColor3", color.secondary)
				ui.set(toggle, "TextSize", size.small)
				ui.set(toggle, "FontFace", Theme.font.bold)
				ui.set(toggle, "Size", ui.values.udim2(1, -2 * size.gutter, 0, 28))
				ui.set(toggle, "Position", ui.values.udim2(0, size.gutter, 0, 4))
				ui.set(toggle, "TextXAlignment", ui.values.enum("TextXAlignment", "Left"))
				ui.set(toggle, "Parent", toggleFrame)
				if advancedOpen then
					renderGroups({ "Advanced" }, { Advanced = advancedKeys })
				end
			end
			local sequences = value.sequences
			local play = settings.play
			if sequences and play then
				local heading = block("Sequences", 28)
				local title = Theme.label("Sequences", color.secondary, size.small)
				ui.set(title, "FontFace", Theme.font.bold)
				ui.set(title, "Size", ui.values.udim2(1, -2 * size.gutter, 1, 0))
				ui.set(title, "Position", ui.values.udim2(0, size.gutter, 0, 0))
				ui.set(title, "Parent", heading)
				for _, entry in sequences do
					local strip = block("Sequence", 32)
					local sequenceId = entry.id
					local start = pressable("Play", color.raised, color.hover, function()
						play(sequenceId)
					end)
					local steps = #entry.steps
					local plural = if steps == 1 then "step" else "steps"
					local autoplay = if entry.autoplay then "  ·  on show" else ""
					ui.set(start, "Text", `▶  {sequenceId}   {steps} {plural}{autoplay}`)
					ui.set(start, "TextColor3", color.text)
					ui.set(start, "TextSize", size.small)
					ui.set(start, "TextXAlignment", ui.values.enum("TextXAlignment", "Left"))
					ui.set(start, "Size", ui.values.udim2(1, -2 * size.gutter, 0, 28))
					ui.set(start, "Position", ui.values.udim2(0, size.gutter, 0, 2))
					ui.set(start, "Parent", strip)
				end
			end
			block("End", 16)
		end
		local root = Compose.createRootOwner(function()
			Compose.watch(function(use: Compose.Use)
				render(use(session.document), use(session.selected), use(showAdvanced))
			end)
		end, ui.runtime.reactor)
		local release = Compose.owner.own(ui.owner, root.dispose)
		return {
			root = scroller,
			dispose = function()
				release()
				scrubMoved:Disconnect()
				scrubEnded:Disconnect()
				clear()
				ui.destroy(scroller)
			end,
		}
	end
end
