--!strict
local t = require("./lib/testkit")
local HELPERS =
	{ fill = true, badged = true, environment = true, worldAnchor = true, scrollTo = true, scrollToVisible = true }
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local catalogue = require("../examples/gallery/client/demo_picker")
local allControls = require("../examples/gallery/scenarios/all_controls")
local Compose = Facet.Compose

local NAME_ATTRIBUTES = { "AccessibleLabel", "FacetLabel", "label" }
local REGION_CLASSES = { "ScrollingFrame" }

local KNOWN_UNNAMED: { [string]: { control: string, nameable: boolean, reason: string, props: () -> any } } = {
	["facet-level-picker"] = {
		control = "LevelPicker",
		nameable = false,
		reason = "LevelPicker has no label or name option, so its selectable root cannot carry an accessible name",
		props = function()
			return { value = Compose.cell(2) }
		end,
	},
	["facet-rating"] = {
		control = "Rating",
		nameable = false,
		reason = "Rating has no label or name option; its only text is the star glyphs",
		props = function()
			return { value = Compose.cell(2) }
		end,
	},
	["facet-slider-track"] = {
		control = "Slider",
		nameable = true,
		reason = "Slider has no name option, so the selectable track of a Slider without a visible label has no accessible name",
		props = function()
			return { value = Compose.cell(0.5) }
		end,
	},
	["facet-text-input"] = {
		control = "TextInput",
		nameable = true,
		reason = "TextInput has no label or name option, so an empty field without a placeholder has no accessible name",
		props = function()
			return { value = Compose.cell(""), presentation = "search" }
		end,
	},
}

local REJECTS_EMPTY = {
	Avatar = "Facet Avatar name must be nonempty",
	Badge = "Facet Badge requires meaningful text",
	Menu = "Menu items require nonempty labels",
	Picker = "Picker options require nonempty labels",
	RowActions = "Menu items require nonempty labels",
}

local function trimmed(value: any): string
	if type(value) ~= "string" then
		return ""
	end
	return (string.gsub(value, "^%s+", ""):gsub("%s+$", ""))
end

local function meaningful(text: string): boolean
	if utf8.len(text) == nil then
		return false
	end
	for _, code in utf8.codes(text) do
		local ascii = code < 128 and string.match(string.char(code), "%w") ~= nil
		local symbol = (code >= 0x2000 and code <= 0x2BFF) or code >= 0x1F000 or (code >= 0xFE00 and code <= 0xFE0F)
		if ascii or (code >= 128 and not symbol) then
			return true
		end
	end
	return false
end

local function shown(node: any, stop: any): boolean
	local cursor = node
	while cursor and cursor ~= stop do
		if cursor:IsA("GuiObject") and cursor.Visible == false then
			return false
		end
		if cursor:IsA("LayerCollector") and cursor.Enabled == false then
			return false
		end
		cursor = cursor.Parent
	end
	return true
end

local function interactive(node: any): boolean
	if not node:IsA("GuiObject") then
		return false
	end
	for _, class in REGION_CLASSES do
		if node:IsA(class) then
			return false
		end
	end
	return node:IsA("TextBox") or node.Selectable == true
end

local function labelOf(node: any): string
	for _, key in NAME_ATTRIBUTES do
		local attribute = trimmed(node:GetAttribute(key))
		if meaningful(attribute) then
			return attribute
		end
	end
	if node:IsA("TextButton") or node:IsA("TextBox") or node:IsA("TextLabel") then
		local own = trimmed(node.Text)
		if meaningful(own) then
			return own
		end
	end
	if node:IsA("TextBox") then
		local placeholder = trimmed(node.PlaceholderText)
		if meaningful(placeholder) then
			return placeholder
		end
	end
	return ""
end

local function accessibleName(node: any): string
	local own = labelOf(node)
	if own ~= "" then
		return own
	end
	for _, descendant in node:GetDescendants() do
		if descendant:IsA("GuiObject") and shown(descendant, node) then
			local found = labelOf(descendant)
			if found ~= "" then
				return found
			end
		end
	end
	return ""
end

local function path(node: any, stop: any): string
	local parts = {}
	local cursor = node
	while cursor and cursor ~= stop do
		table.insert(parts, 1, `{cursor.Name}<{cursor.ClassName}>`)
		cursor = cursor.Parent
	end
	return table.concat(parts, "/")
end

local function knownDefect(node: any, strict: boolean): string?
	for tag, gap in KNOWN_UNNAMED do
		if (not strict or not gap.nameable) and node:HasTag(tag) then
			return tag
		end
	end
	return nil
end

local function unnamed(root: any, strict: boolean): ({ string }, number, { [string]: boolean })
	local missing, checked, known = {}, 0, {}
	for _, node in root:GetDescendants() do
		if interactive(node) and shown(node, root) then
			checked += 1
			if accessibleName(node) == "" then
				local tag = knownDefect(node, strict)
				if tag then
					known[tag] = true
				else
					table.insert(missing, path(node, root))
				end
			end
		end
	end
	return missing, checked, known
end

local function texts(root: any): { [string]: boolean }
	local found = {}
	for _, node in root:GetDescendants() do
		if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
			found[node.Text] = true
		end
		for _, key in NAME_ATTRIBUTES do
			local value = node:GetAttribute(key)
			if type(value) == "string" then
				found[value] = true
			end
		end
	end
	return found
end

local function world()
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local root = engine.new("ScreenGui")
	local gui = engine.new("GuiService")
	local UI = Facet.controls(runtime, {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui },
		inputParent = root,
		overlayParent = root,
		reducedMotion = true,
	})
	return engine, runtime, root, UI
end

local function galleryContext()
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local viewport = Compose.cell({ width = 1280, height = 720 })
	local target = engine.new("Folder")
	local guiService = engine.new("GuiService")
	local reducedMotion = Compose.cell(true)
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = viewport,
		inputTarget = target,
		worldTarget = engine.new("Folder"),
		guiService = guiService,
		runService = { Heartbeat = engine.heartbeat },
		reducedMotion = reducedMotion,
		pageVisible = Compose.cell(true),
		UI = Facet.controls(runtime, {
			types = engine.types,
			viewport = viewport,
			guiService = guiService,
			services = { GuiService = guiService },
			inputParent = target,
			reducedMotion = reducedMotion,
		}),
	}
	return ctx, engine, target
end

local function load(kind: string, name: string): any
	return require("../examples/gallery/" .. (if kind == "example" then "examples/" else "scenarios/") .. name)
end

local function find(root: any, name: string): any
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function item(id: string, label: string): any
	return { id = id, label = label, onSelect = function() end }
end

local fixtures: { [string]: (Host: any, engine: any) -> any } = {
	Button = function()
		return { label = "Press", onActivate = function() end }
	end,
	Toggle = function()
		return { value = Compose.cell(false), label = "Music" }
	end,
	TextInput = function()
		return { value = Compose.cell(""), placeholder = "Name" }
	end,
	Stepper = function()
		return { value = Compose.cell(1), min = 0, max = 10, label = "Count" }
	end,
	Slider = function()
		return { value = Compose.cell(0.5), label = "Volume" }
	end,
	Rating = function()
		return { value = Compose.cell(2) }
	end,
	LevelPicker = function()
		return { value = Compose.cell(2) }
	end,
	Chip = function()
		return { label = "Chip", onRemove = function() end }
	end,
	NumberInput = function()
		return { value = Compose.cell("1"), numericValue = Compose.cell(1), label = "Laps", stepButtons = true }
	end,
	DateTimePicker = function()
		return {
			value = Compose.cell({ year = 2026, month = 9, day = 23 }),
			onChange = function() end,
			label = "Race day",
			style = "inline",
			clock = function()
				return { year = 2026, month = 9, day = 23 }
			end,
		}
	end,
	ColorPicker = function()
		return {
			value = Compose.cell(require("@lune/roblox").Color3.new(1, 0, 0)),
			onChange = function() end,
			label = "Paint",
			style = "inline",
			modes = { "swatches", "spectrum", "sliders" },
		}
	end,
	ShortcutHint = function()
		return { keys = { { "Ctrl", "K" } } }
	end,
	Screen = function()
		return {}
	end,
	VStack = function()
		return { gap = "s" }
	end,
	HStack = function()
		return { gap = "s" }
	end,
	ZStack = function()
		return {}
	end,
	ScrollView = function()
		return { gap = "s" }
	end,
	Grid = function()
		return { columns = 2 }
	end,
	Text = function()
		return { text = "Text" }
	end,
	Label = function()
		return { title = "Label", icon = "checkmark" }
	end,
	Image = function()
		return { image = "rbxassetid://1" }
	end,
	Divider = function()
		return {}
	end,
	Spacer = function()
		return { minLength = "m" }
	end,
	Badge = function()
		return { label = "Badge" }
	end,
	StatusIndicator = function()
		return { status = "success", count = 3 }
	end,
	Path = function()
		return { points = Facet.pathShapes.needle(45), role = "accent" }
	end,
	ProgressView = function()
		return { value = Compose.cell(0.5), label = "Loading" }
	end,
	Skeleton = function()
		return {}
	end,
	AsyncImage = function()
		return {
			source = "image",
			loader = function(source, resolve)
				resolve(source)
			end,
		}
	end,
	Avatar = function()
		return { name = "Ada", onActivate = function() end }
	end,
	AvatarGroup = function()
		return {
			items = {
				{ id = "a", name = "Ada" },
				{ id = "b", name = "Bo" },
				{ id = "c", name = "Cy" },
				{ id = "d", name = "Di" },
				{ id = "e", name = "Ed" },
				{ id = "f", name = "Fe" },
			},
			max = 3,
			onOverflow = function() end,
		}
	end,
	ErrorBoundary = function(Host)
		return {
			view = function()
				return Host.TextLabel({ Text = "Healthy" })
			end,
			fallback = function()
				return Host.TextLabel({ Text = "Failed" })
			end,
		}
	end,
	Stage = function()
		return {}
	end,
	Pagination = function()
		return { page = Compose.cell(3), pageCount = 10, onChange = function() end }
	end,
	Card = function()
		return {
			image = "rbxassetid://1",
			title = "Card",
			onActivate = function() end,
			primaryAction = { label = "Play", onActivate = function() end },
		}
	end,
	Vote = function()
		return { value = Compose.cell("none"), onChange = function() end }
	end,
	StepIndicator = function()
		return {
			steps = { { id = "a", label = "A", navigable = true }, { id = "b", label = "B" } },
			current = "a",
			onSelect = function() end,
		}
	end,
	Menu = function()
		return {
			label = "Options",
			isPresented = Compose.cell(true),
			items = { item("a", "Alpha"), item("b", "Beta") },
		}
	end,
	Picker = function()
		return {
			selected = Compose.cell("a"),
			style = "segmented",
			options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
		}
	end,
	ComboBox = function()
		return {
			acceptCustom = function()
				return true
			end,
			text = Compose.cell("A"),
			value = Compose.cell("a"),
			options = { { value = "a", label = "Alpha" } },
		}
	end,
	SplitButton = function()
		return { label = "Action", onActivate = function() end, items = { item("a", "Alpha") } }
	end,
	RadialMenu = function()
		return { items = { item("a", "Alpha"), item("b", "Beta") }, isPresented = Compose.cell(true), label = "Quick" }
	end,
	DisclosureGroup = function(Host)
		return {
			label = "Details",
			expanded = Compose.cell(true),
			content = function()
				return Host.TextLabel({ Text = "Body" })
			end,
		}
	end,
	CollapsibleView = function(Host)
		return {
			label = "Details",
			expanded = Compose.cell(true),
			content = function()
				return Host.TextLabel({ Text = "Body" })
			end,
		}
	end,
	Alert = function()
		return {
			title = "Confirm",
			message = "Continue?",
			isPresented = Compose.cell(true),
			actions = { { id = "ok", label = "OK" }, { id = "cancel", label = "Cancel", role = "cancel" } },
		}
	end,
	Dialog = function(Host)
		local open = Compose.cell(true)
		return {
			title = "Confirm",
			isPresented = open,
			onPresentedChange = function(nextValue: boolean)
				open:set(nextValue)
			end,
			content = function()
				return Host.TextLabel({ Text = "Body" })
			end,
			actions = { { id = "ok", label = "OK", onActivate = function() end } },
		}
	end,
	Snackbar = function()
		local shown = Compose.cell(true)
		return {
			isPresented = shown,
			message = "Saved",
			action = { label = "Undo", onActivate = function() end },
			onPresentedChange = function(nextValue: boolean)
				shown:set(nextValue)
			end,
		}
	end,
	Notice = function()
		return {
			message = "Connection interrupted",
			link = { label = "Details", onActivate = function() end },
			actions = { { id = "Retry", label = "Retry", onActivate = function() end } },
			onDismiss = function() end,
		}
	end,
	NavBar = function()
		return { title = "Tracks", onBack = function() end, backLabel = "Back" }
	end,
	Popover = function(Host)
		return {
			isPresented = Compose.cell(true),
			source = { rect = { x = 10, y = 10, w = 40, h = 40 } },
			content = function()
				return Host.TextLabel({ Text = "Body" })
			end,
		}
	end,
	Sheet = function(Host)
		return {
			title = "Sheet",
			detent = Compose.cell("medium"),
			isPresented = Compose.cell(true),
			content = function()
				return Host.TextLabel({ Text = "Body" })
			end,
		}
	end,
	Callout = function(Host)
		return {
			anchor = Host.Frame({}),
			onRetire = function() end,
			content = function()
				return Host.TextLabel({ Text = "Tip" })
			end,
			isPresented = Compose.cell(true),
		}
	end,
	TabView = function(Host)
		local tab = function(id, label)
			return {
				id = id,
				label = label,
				content = function()
					return Host.TextLabel({ Text = label })
				end,
			}
		end
		return { selection = Compose.cell("a"), tabs = { tab("a", "Alpha"), tab("b", "Beta") } }
	end,
	PageView = function(Host)
		local page = function(id, title)
			return {
				id = id,
				title = title,
				content = function()
					return Host.TextLabel({ Text = title })
				end,
			}
		end
		return { selection = Compose.cell("a"), pages = { page("a", "Alpha"), page("b", "Beta") } }
	end,
	NavigationStack = function(Host)
		return {
			path = Compose.cell({ { id = "detail", value = 1 } }),
			root = {
				title = "Root",
				content = function()
					return Host.TextLabel({ Text = "Root" })
				end,
			},
			destinations = {
				detail = {
					title = "Detail",
					content = function()
						return Host.TextLabel({ Text = "Detail" })
					end,
				},
			},
		}
	end,
	RowActions = function(Host)
		return {
			content = function()
				return Host.TextLabel({ Text = "Row" })
			end,
			trailing = { { id = "delete", label = "Delete", role = "destructive", onActivate = function() end } },
			open = Compose.cell("trailing"),
		}
	end,
	Table = function()
		return {
			from = { { id = "a", label = "Alpha" }, { id = "b", label = "Beta" } },
			key = function(entry)
				return entry.id
			end,
			columns = {
				{
					id = "label",
					label = "Label",
					value = function(entry)
						return entry.label
					end,
				},
			},
		}
	end,
}
for _, name in { "VirtualList", "VirtualGrid" } do
	fixtures[name] = function(Host)
		return {
			from = { { id = "a" }, { id = "b" } },
			key = function(entry)
				return entry.id
			end,
			itemSize = 24,
			render = function()
				return Host.TextLabel({ Text = "Row" })
			end,
		}
	end
end

local CORPUS = {
	{
		id = "german-compound",
		text = "Donaudampfschifffahrtselektrizitätenhauptbetriebswerkbauunterbeamtengesellschaft",
	},
	{ id = "japanese", text = "設定を保存しました" },
	{ id = "chinese", text = "保存更改并返回主菜单" },
	{ id = "korean", text = "설정을 저장했습니다" },
	{ id = "arabic", text = "حفظ الإعدادات" },
	{ id = "hebrew", text = "שמור את ההגדרות" },
	{ id = "bidi-mixed", text = "Level 5 — المستوى ٥ — שלב 5" },
	{ id = "thai", text = "บันทึกการตั้งค่า" },
	{ id = "devanagari", text = "सेटिंग्स सहेजें" },
	{ id = "combining-marks", text = "e\u{0301}le\u{0300}ve Z\u{0351}\u{036B}a\u{0310}l\u{0346}g\u{0352}o" },
	{ id = "emoji-zwj", text = "👩‍👩‍👧‍👦 Family 🏳️‍🌈 👋🏽" },
	{ id = "long-copy", text = string.rep("Translated copy grows longer. ", 24) },
	{ id = "surrounding-space", text = "  padded  " },
	{ id = "empty", text = "" },
}

local function textHosts(Host: any, value: string): { [string]: () -> any }
	local function body()
		return Host.Frame({})
	end
	return {
		Text = function()
			return { text = value }
		end,
		Button = function()
			return { label = value, onActivate = function() end }
		end,
		Toggle = function()
			return { value = Compose.cell(true), label = value }
		end,
		TextInput = function()
			return { value = Compose.cell(value) }
		end,
		Chip = function()
			return { label = value, selected = Compose.cell(false) }
		end,
		NumberInput = function()
			return { value = Compose.cell("1"), numericValue = Compose.cell(1), label = value }
		end,
		Badge = function()
			return { label = value }
		end,
		Stepper = function()
			return { value = Compose.cell(1), min = 0, max = 5, label = value }
		end,
		Slider = function()
			return { value = Compose.cell(0.5), label = value }
		end,
		ProgressView = function()
			return { value = Compose.cell(0.5), label = value }
		end,
		Picker = function()
			return {
				selected = Compose.cell("a"),
				style = "inline",
				options = { { value = "a", label = value }, { value = "b", label = "Other" } },
			}
		end,
		Alert = function()
			return {
				title = value,
				message = value,
				isPresented = Compose.cell(true),
				actions = { { id = "ok", label = value } },
			}
		end,
		Menu = function()
			return { label = "Open", isPresented = Compose.cell(true), items = { item("a", value) } }
		end,
		SplitButton = function()
			return { label = value, onActivate = function() end, items = { item("a", "Other") } }
		end,
		DisclosureGroup = function()
			return { label = value, expanded = Compose.cell(false), content = body }
		end,
		Sheet = function()
			return { title = value, detent = Compose.cell("medium"), isPresented = Compose.cell(true), content = body }
		end,
		TabView = function()
			return {
				selection = Compose.cell("a"),
				tabs = { { id = "a", label = value, content = body }, { id = "b", label = "Other", content = body } },
			}
		end,
		NavigationStack = function()
			return { path = Compose.cell({}), root = { title = value, content = body }, destinations = {} }
		end,
		RowActions = function()
			return {
				content = body,
				trailing = { { id = "delete", label = value, onActivate = function() end } },
				open = Compose.cell("trailing"),
			}
		end,
		Table = function()
			return {
				from = { { id = "a", label = value } },
				key = function(entry)
					return entry.id
				end,
				columns = {
					{
						id = "label",
						label = value,
						value = function(entry)
							return entry.label
						end,
					},
				},
			}
		end,
		Avatar = function()
			return { name = value }
		end,
	}
end

local function galleryTargets(): { { id: string, scenario: any } }
	local list = {}
	for _, group in allControls.groups do
		for _, tab in group.tabs do
			table.insert(list, { id = `{group.id}/{tab.id}`, scenario = tab.scenario })
		end
	end
	return list
end

t.describe("native accessibility and localization corpus", function()
	t.it("gives every selectable node of every public control an accessible name", function()
		local _, probe = world()
		local UI = Facet.controls(probe, { types = engineLib.new().types })
		for name in UI do
			assert(fixtures[name] or HELPERS[name], `Missing corpus fixture: {name}`)
		end
		for name in fixtures do
			assert(UI[name], `Stale corpus fixture: {name}`)
		end
		probe.dispose()
		local names = {}
		for name in fixtures do
			table.insert(names, name)
		end
		table.sort(names)
		local failures, total = {}, 0
		for _, name in names do
			local engine, runtime, root, controls = world()
			local stop = runtime.mount(function()
				return controls[name](fixtures[name](runtime.constructors, engine))
			end, root)
			engine.heartbeat.fire(1 / 60)
			local missing, checked = unnamed(root, true)
			total += checked
			for _, entry in missing do
				table.insert(failures, `{name}: {entry}`)
			end
			stop()
			runtime:dispose()
		end
		for tag, gap in KNOWN_UNNAMED do
			local engine, runtime, root, controls = world()
			local stop = runtime.mount(function()
				return controls[gap.control](gap.props())
			end, root)
			engine.heartbeat.fire(1 / 60)
			local _, _, known = unnamed(root, false)
			if not known[tag] then
				table.insert(
					failures,
					`{tag}: known gap no longer reproduces; remove it from KNOWN_UNNAMED ({gap.reason})`
				)
			end
			stop()
			runtime:dispose()
		end
		assert(total >= 30, `only {total} selectable nodes were checked`)
		assert(#failures == 0, "selectable nodes without an accessible name:\n" .. table.concat(failures, "\n"))
	end)

	t.it("gives every selectable node of every gallery demo an accessible name", function()
		local ctx, engine, target = galleryContext()
		ctx.selection = Compose.cell("all-controls")
		ctx.themeMode = Compose.cell("light")
		ctx.theme = Compose.cell(Facet.themes.neutralPackage())
		ctx.packages = { Neutral = ctx.theme:peek() }
		ctx.load = load
		ctx.reducedMotion = nil
		local stop, gui = ctx.runtime.mount(function()
			local sheet =
				Facet.themes.createStyleSheet(ctx.runtime, ctx.theme, { types = ctx.types, theme = ctx.themeMode })
			return ctx.Host.ScreenGui "FacetGallery" {
				sheet,
				ctx.Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
				require("../examples/gallery/client/screen").build(ctx),
			}
		end, target)
		local bar = find(gui, "Tabs")
		local failures, total = {}, 0
		for _, demo in catalogue.list() do
			find(bar, demo.id).Activated.fire()
			engine.heartbeat.fire(1 / 60)
			assert(ctx.errorMessage:peek() == nil, `{demo.id}: {ctx.errorMessage:peek()}`)
			local missing, checked = unnamed(gui, false)
			total += checked
			for _, entry in missing do
				table.insert(failures, `{demo.id}: {entry}`)
			end
		end
		stop()
		ctx.runtime:dispose()
		for _, scenario in galleryTargets() do
			local sctx, sengine, starget = galleryContext()
			sctx.load = load
			local sstop, node = sctx.runtime.mount(function()
				local built = scenario.scenario.build(sctx)
				if built.dispose then
					Compose.cleanup(built.dispose)
				end
				return sctx.Host.ScreenGui "DemoScreen" { built.screen() }
			end, starget)
			sengine.heartbeat.fire(1 / 60)
			local missing, checked = unnamed(node, false)
			total += checked
			for _, entry in missing do
				table.insert(failures, `{scenario.id}: {entry}`)
			end
			sstop()
			sctx.runtime:dispose()
		end
		assert(total > 100, `only {total} selectable nodes were checked`)
		assert(#failures == 0, "gallery nodes without an accessible name:\n" .. table.concat(failures, "\n"))
	end)

	t.it("mounts every corpus string through the text-bearing controls without changing it", function()
		local failures, mounted = {}, 0
		for _, entry in CORPUS do
			assert(utf8.len(entry.text) ~= nil, `{entry.id}: corpus string is not valid UTF-8`)
			local names = {}
			for name in textHosts({}, entry.text) do
				table.insert(names, name)
			end
			table.sort(names)
			for _, name in names do
				local engine, runtime, root, UI = world()
				local ok, err = pcall(function()
					local stop = runtime.mount(function()
						return UI[name](textHosts(runtime.constructors, entry.text)[name]())
					end, root)
					engine.heartbeat.fire(1 / 60)
					local found = texts(root)
					if entry.text ~= "" and not found[entry.text] then
						table.insert(failures, `{name} {entry.id}: no native Text or name equals the input`)
					end
					for value in found do
						if utf8.len(value) == nil then
							table.insert(failures, `{name} {entry.id}: invalid UTF-8 reached native Text`)
						end
					end
					stop()
				end)
				local rejection = if entry.text == "" then REJECTS_EMPTY[name] else nil
				if rejection then
					if ok or not string.find(tostring(err), rejection, 1, true) then
						table.insert(failures, `{name} {entry.id}: expected the diagnostic "{rejection}"`)
					end
				elseif not ok then
					table.insert(failures, `{name} {entry.id}: {err}`)
				end
				runtime:dispose()
				mounted += 1
			end
		end
		assert(mounted >= #CORPUS * 20, `only {mounted} corpus mounts ran`)
		assert(#failures == 0, "localization corpus failures:\n" .. table.concat(failures, "\n"))
	end)

	t.it("follows reactive relabels through every corpus string", function()
		local engine, runtime, root, UI = world()
		local value = Compose.cell("Start")
		local stop = runtime.mount(function()
			return runtime.constructors.Frame({
				UI.Text({ text = value }),
				UI.Button({ label = value, onActivate = function() end }),
				UI.Toggle({ value = Compose.cell(false), label = value }),
			})
		end, root)
		for _, entry in CORPUS do
			value:set(entry.text)
			engine.heartbeat.fire(1 / 60)
			local count = 0
			for _, node in root:GetDescendants() do
				if (node:IsA("TextLabel") or node:IsA("TextButton")) and node.Text == entry.text then
					count += 1
				end
			end
			assert(entry.text == "" or count >= 3, `{entry.id}: {count} of 3 relabelled controls show the input`)
		end
		stop()
		runtime:dispose()
	end)

	t.it("keeps multibyte text edits valid UTF-8 through TextInput editing and maxLength", function()
		for _, entry in CORPUS do
			local engine, runtime, root, UI = world()
			local open, bounded = Compose.cell(""), Compose.cell("")
			local field, limited
			local stop = runtime.mount(function()
				field = UI.TextInput({ value = open })
				limited = UI.TextInput({ value = bounded, maxLength = 3 })
				return runtime.constructors.Frame({ field, limited })
			end, root)
			field:CaptureFocus()
			field.Text = entry.text
			assert(open:peek() == entry.text, `{entry.id}: edit changed the text to {open:peek()}`)
			assert(utf8.len(open:peek()) ~= nil, `{entry.id}: edit produced invalid UTF-8`)
			field:ReleaseFocus(true)
			assert(open:peek() == entry.text, `{entry.id}: commit changed the text`)
			limited:CaptureFocus()
			limited.Text = entry.text
			local kept = bounded:peek()
			local length = utf8.len(kept)
			assert(length ~= nil, `{entry.id}: maxLength split a character`)
			assert(length <= 3, `{entry.id}: maxLength kept {length} characters`)
			assert(string.sub(entry.text, 1, #kept) == kept, `{entry.id}: maxLength did not keep a prefix`)
			assert(limited.Text == kept, `{entry.id}: native Text differs from the bounded model`)
			local expected = math.min(3, utf8.len(entry.text) :: number)
			assert(length == expected, `{entry.id}: maxLength kept {length} of {expected} characters`)
			limited:ReleaseFocus(true)
			stop()
			runtime:dispose()
		end
	end)
end)
