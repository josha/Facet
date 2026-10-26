--!strict

local Files = require("./files")
local Hash = require("./hash")
local Json = require("./json")
local Run = require("./run")

export type Record = {
	parent: string?,
	keys: { string },
	types: { [string]: string },
}

export type Schema = { [string]: { writable: { string } } }

local Generator = {}

local function words(text: string): { string }
	local list: { string } = {}
	for word in string.gmatch(text, "[^%s]+") do
		table.insert(list, word)
	end
	return list
end

local function sortedUnique(list: { string }): { string }
	local seen: { [string]: boolean } = {}
	local unique: { string } = {}
	for _, item in list do
		if not seen[item] then
			seen[item] = true
			table.insert(unique, item)
		end
	end
	table.sort(unique)
	return unique
end

Generator.CLASSES = sortedUnique(
	words(
		"BindableFunction ClickDetector HapticEffect Highlight Part PointLight StyleLink WedgePart Weld Model Sound Camera CanvasGroup Folder Frame GuiObject GuiButton ImageButton ImageLabel InputAction InputBinding InputContext Path2D ScrollingFrame ScreenGui BillboardGui SurfaceGui StyleRule StyleSheet TextBox TextButton TextLabel UIAspectRatioConstraint UICorner UIDragDetector UIFlexItem UIGradient UIGridLayout UIListLayout UIPadding UIPageLayout UIScale UIShadow UISizeConstraint UIStroke UITextSizeConstraint ViewportFrame WorldModel"
	)
)

Generator.DATATYPES = words(
	"UDim UDim2 Vector2 Vector3 Color3 CFrame Enum Font Rect ColorSequence ColorSequenceKeypoint NumberSequence NumberSequenceKeypoint NumberRange Path2DControlPoint FloatCurveKey TweenInfo"
)

Generator.OBSERVED = words(
	"AnchorPoint AbsoluteContentSize BackgroundColor3 CornerRadius AbsolutePosition AbsoluteSize AbsoluteWindowSize CanvasPosition CurrentPage DisplayImage DisplayName Enabled FontFace GamepadEnabled GamepadCursorEnabled GuiState Interactable KeyCode KeyboardEnabled MouseEnabled Parent Position PreferredBinding PreferredInput PreferredTextSize PreferredTransparency PrimaryModifier ReducedMotionEnabled SecondaryModifier SelectedObject Size Text ContentText TextBounds TextFits TextSize TextColor3 TextXAlignment TextYAlignment TextWrapped RichText TextScaled TextTruncate LineHeight TouchEnabled Visible OnScreenKeyboardVisible OnScreenKeyboardSize AbsoluteCanvasSize Scale CursorPosition TopbarInset ViewportDisplaySize AutomaticSize PaddingTop PaddingBottom"
)

Generator.OBSERVED_CLASSES = words(
	"GamepadService UICorner GuiBase2d GuiObject GuiService UserInputService LayerCollector Instance InputAction InputBinding InputContext TextLabel TextBox TextButton ScrollingFrame UIGridStyleLayout UIPageLayout UIScale UIPadding"
)

Generator.SCHEMA = "tools/typecheck/engine_members.json"
Generator.OUTPUT = "src/ui/engine_types.luau"

local function set(list: { string }): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, item in list do
		result[item] = true
	end
	return result
end

local function lines(text: string): { string }
	local normalized = string.gsub(text, "\r\n", "\n")
	return string.split(normalized, "\n")
end

local function declaration(line: string): (string?, string?)
	local name, parent = string.match(line, "^declare extern type ([%w_]+) extends ([%w_]+) with$")
	if name ~= nil then
		return name, parent
	end
	return string.match(line, "^declare extern type ([%w_]+) with$"), nil
end

function Generator.records(source: string): { [string]: Record }
	local entries: { [string]: Record } = {}
	local list = lines(source)
	local index = 1
	while index <= #list do
		local name, parent = declaration(list[index])
		if name == nil then
			index += 1
			continue
		end
		local finish = nil
		for candidate = index + 1, #list do
			if list[candidate] == "end" then
				finish = candidate
				break
			end
		end
		if finish == nil then
			break
		end
		local record: Record = { parent = parent, keys = {}, types = {} }
		for position = index + 1, finish - 1 do
			local key, native = string.match(list[position], "^\t([%a_][%w_]*): (.+)$")
			if key ~= nil and native ~= nil then
				if record.types[key] == nil then
					table.insert(record.keys, key)
				end
				record.types[key] = native
			end
		end
		entries[name] = record
		index = finish + 1
	end
	return entries
end

local function mapWords(text: string, transform: (string) -> string): string
	local mapped = string.gsub(text, "[%w_]+", transform)
	return mapped
end

local function enumWord(word: string): string
	if string.sub(word, 1, 4) == "Enum" and word ~= "EnumItem" and string.match(string.sub(word, 5, 5), "^%u$") then
		return "Enum." .. string.sub(word, 5)
	end
	return word
end

local function anyWord(word: string): string
	return if word == "any" then "unknown" else word
end

function Generator.nativeType(value: string): string
	local enums = mapWords(value, enumWord)
	local content = mapWords(enums, function(word: string): string
		return if word == "ContentId" then "string" else word
	end)
	return mapWords(content, anyWord)
end

local function capitalized(native: string): string
	local spaced = string.gsub(native, "%?", " Optional ")
	local parts: { string } = { "Value" }
	for part in string.gmatch(spaced, "[%w]+") do
		table.insert(parts, string.upper(string.sub(part, 1, 1)) .. string.sub(part, 2))
	end
	return table.concat(parts)
end

function Generator.generate(definitions: string, schema: Schema, classes: { string }?): (string, { string })
	local selected = classes or Generator.CLASSES
	local selectedSet = set(selected)
	local entries = Generator.records(definitions)
	local function entry(name: string): Record
		local found = entries[name]
		if found == nil then
			error(("the definitions declare no class %s"):format(name), 0)
		end
		return found
	end
	local ordered: { string } = {}
	local visited: { [string]: boolean } = {}
	local function visit(name: string)
		if visited[name] then
			return
		end
		local parent = entry(name).parent
		if parent ~= nil then
			visit(parent)
		end
		visited[name] = true
		table.insert(ordered, name)
	end
	for _, name in selected do
		visit(name)
	end
	local result: { string } = {
		"--!strict",
		'local Compose = require("../vendor/compose/core")',
		"",
		"export type Input<T> = Compose.Input<T>",
		"export type StaticValue = typeof(Compose.static(nil))",
		'export type EventKey = typeof(Compose.event(""))',
		"export type Constructor<P, N> = ((P) -> N) & ((string) -> (P) -> N)",
		"export type AttributeValue = string | boolean | number | UDim | UDim2 | BrickColor | Color3 | Vector2 | Vector3 | CFrame | NumberSequence | ColorSequence | NumberRange | Rect | Font",
		"export type Attributes = { [string]: Input<AttributeValue?> }",
		"",
	}
	local aliases: { [string]: string } = {}
	local aliasNames: { [string]: boolean } = {}
	local function shared(native: string): string
		local existing = aliases[native]
		if existing ~= nil then
			return existing
		end
		local name = capitalized(native)
		if aliasNames[name] then
			error(("two native types share the alias %s"):format(name), 0)
		end
		aliases[native] = name
		aliasNames[name] = true
		return name
	end
	local function isInstance(name: string?): boolean
		local current = name
		while current ~= nil and entries[current] ~= nil do
			if current == "Instance" then
				return true
			end
			current = entries[current].parent
		end
		return false
	end
	local own: { [string]: { string } } = {}
	for _, name in ordered do
		local record = entry(name)
		local fields: { string } = if name == "Instance" then { "\tAttributes: Attributes?," } else {}
		local writable: { [string]: boolean }? = nil
		for _, key in record.keys do
			local native = record.types[key]
			if string.sub(native, 1, 16) == "RBXScriptSignal<" then
				local arguments = string.sub(native, 17, -2)
				if string.sub(arguments, 1, 1) == "(" and string.sub(arguments, -1) == ")" then
					arguments = string.sub(arguments, 2, -2)
				end
				arguments = mapWords(mapWords(arguments, enumWord), anyWord)
				table.insert(fields, ("\t%s: ((%s) -> ())?,"):format(key, arguments))
			else
				if writable == nil then
					local members = schema[name]
					if members == nil then
						error(("the writable-member metadata has no class %s"):format(name), 0)
					end
					writable = set(members.writable)
				end
				if (writable :: { [string]: boolean })[key] then
					local instanceProperty = false
					for word in string.gmatch(native, "[%w_]+") do
						if isInstance(word) then
							instanceProperty = true
							break
						end
					end
					local propertyType = Generator.nativeType(native)
					if instanceProperty and string.sub(propertyType, -1) ~= "?" then
						propertyType ..= "?"
					end
					local value = shared(propertyType)
					if instanceProperty then
						value = "(" .. value .. " | StaticValue)"
					end
					table.insert(fields, ("\t%s: %s?,"):format(key, value))
				end
			end
		end
		local inherited: { string } = if record.parent ~= nil then table.clone(own[record.parent]) else {}
		table.move(fields, 1, #fields, #inherited + 1, inherited)
		own[name] = inherited
		if not selectedSet[name] then
			continue
		end
		table.insert(result, ("export type %sNativeProps = {"):format(name))
		table.move(inherited, 1, #inherited, #result + 1, result)
		table.insert(result, "\t[number | EventKey]: Compose.Child,")
		table.insert(result, "}")
		table.insert(result, ("export type %sProps = {"):format(name))
		table.move(inherited, 1, #inherited, #result + 1, result)
		table.insert(result, "\t[number | EventKey]: Compose.Child,")
		table.insert(result, ("\tref: ((%s) -> ())?,"):format(name))
		table.insert(result, "}")
		table.insert(result, "")
	end
	local sharedNatives: { string } = {}
	for native in aliases do
		table.insert(sharedNatives, native)
	end
	table.sort(sharedNatives, function(left: string, right: string): boolean
		return aliases[left] < aliases[right]
	end)
	local insertAt = (table.find(result, "export type Attributes = { [string]: Input<AttributeValue?> }") :: number) + 1
	for offset, native in sharedNatives do
		table.insert(result, insertAt + offset - 1, ("export type %s = Input<%s>"):format(aliases[native], native))
	end
	table.insert(result, "export type RobloxTypes = {")
	for _, name in Generator.DATATYPES do
		table.insert(result, ("\t%s: typeof(%s),"):format(name, name))
	end
	table.insert(result, "\tBrickColor: typeof(BrickColor)?,")
	table.insert(result, "}")
	table.insert(result, "")
	local observed = set(Generator.OBSERVED)
	local observedClasses = set(Generator.OBSERVED_CLASSES)
	local entryNames: { string } = {}
	for name in entries do
		table.insert(entryNames, name)
	end
	table.sort(entryNames)
	local groupOrder: { { native: string, class: string } } = {}
	local groups: { [string]: { string } } = {}
	for _, name in entryNames do
		if not observedClasses[name] then
			continue
		end
		local record = entries[name]
		for _, key in record.keys do
			local native = record.types[key]
			if observed[key] and string.sub(native, 1, 15) ~= "RBXScriptSignal" then
				local mapped = Generator.nativeType(native)
				local groupKey = mapped .. "\0" .. name
				if groups[groupKey] == nil then
					groups[groupKey] = {}
					table.insert(groupOrder, { native = mapped, class = name })
				end
				table.insert(groups[groupKey], key)
			end
		end
	end
	local members: { [string]: { [string]: { string } } } = {}
	for _, group in groupOrder do
		for _, key in groups[group.native .. "\0" .. group.class] do
			local natives = members[key]
			if natives == nil then
				natives = {}
				members[key] = natives
			end
			local names = natives[group.native]
			if names == nil then
				names = {}
				natives[group.native] = names
			end
			table.insert(names, group.class)
		end
	end
	table.insert(result, "export type Observe = {")
	local memberKeys: { string } = {}
	for key in members do
		table.insert(memberKeys, key)
	end
	table.sort(memberKeys)
	for _, key in memberKeys do
		local nativeKeys: { string } = {}
		for native in members[key] do
			table.insert(nativeKeys, native)
		end
		table.sort(nativeKeys)
		local signatures: { string } = {}
		for _, native in nativeKeys do
			local names = table.clone(members[key][native])
			table.sort(names)
			table.insert(signatures, ("((%s) -> Compose.Value<%s>)"):format(table.concat(names, " | "), native))
		end
		table.insert(result, ("\t%s: %s,"):format(key, table.concat(signatures, " & ")))
	end
	table.insert(result, "}")
	table.insert(result, "")
	table.insert(result, "export type Host = {")
	for _, name in selected do
		if name ~= "GuiObject" and name ~= "GuiButton" then
			table.insert(result, ("\t%s: Constructor<%sNativeProps, %s>,"):format(name, name, name))
		end
	end
	table.insert(result, "}")
	table.insert(result, "")
	table.insert(result, "return {}")
	table.insert(result, "")
	return table.concat(result, "\n"), ordered
end

function Generator.format(text: string, scratch: string): string
	local formatted = text
	for _ = 1, 2 do
		Files.write(scratch, formatted)
		local result = Run.capture({ "stylua", scratch }, { timeout = 120 })
		if not result.ok then
			error(("stylua could not format the generated engine types: %s%s"):format(result.stdout, result.stderr), 0)
		end
		formatted = Files.text(scratch)
	end
	Files.remove(scratch)
	return formatted
end

function Generator.metadata(root: string, classes: { string }): Json.Object
	local result = Json.object()
	for _, name in classes do
		local path = Files.join(root, "content/en-us/reference/engine/classes", name .. ".yaml")
		local raw = Files.read(path)
		local list = lines(raw)
		local section: { string } = {}
		local inside = false
		for position, line in list do
			if inside then
				if string.match(line, "^%S") ~= nil then
					break
				end
				table.insert(section, line)
			elseif line == "properties:" and position < #list then
				inside = true
			end
		end
		local writable: { string } = {}
		local entry: { string }? = nil
		local function finish()
			local current = entry
			if current == nil then
				return
			end
			local member = string.match(current[1], "^  %- name: [%w_]+%.([%w_]+)%s*$")
			if member == nil then
				return
			end
			local write: string? = nil
			local readonly = false
			for _, line in current do
				if write == nil then
					write = string.match(line, "^      write: (%S+)")
				end
				if string.match(line, "^      %- ReadOnly%s*$") ~= nil then
					readonly = true
				end
			end
			if not readonly and write == "None" then
				table.insert(writable, member)
			end
		end
		for _, line in section do
			if string.sub(line, 1, 10) == "  - name: " then
				finish()
				entry = { line }
			elseif entry ~= nil then
				table.insert(entry, line)
			end
		end
		finish()
		table.sort(writable)
		local record = Json.object()
		Json.set(record, "sha256", Hash.sha256(raw))
		Json.set(record, "writable", Json.array(writable))
		Json.set(result, name, record)
	end
	return result
end

function Generator.schema(value: unknown): Schema
	local schema: Schema = {}
	local object = Json.asObject(value)
	if object == nil then
		error("the writable-member metadata is not a JSON object", 0)
	end
	for _, name in Json.keys(object) do
		schema[name] = { writable = Json.strings(Json.field(object[name], "writable")) or {} }
	end
	return schema
end

function Generator.closure(entries: { [string]: Record }, classes: { string }): { string }
	local found: { [string]: boolean } = {}
	for _, name in classes do
		local current: string? = name
		while current ~= nil do
			found[current] = true
			local record = entries[current]
			if record == nil then
				error(("the definitions declare no class %s"):format(current), 0)
			end
			current = record.parent
		end
	end
	local list: { string } = {}
	for name in found do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

return table.freeze(Generator)
