--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type TextProps = typeof(require("@repo/tools/typecheck/aliases").TextProps)
type TextValue = typeof(require("@repo/tools/typecheck/aliases").TextPropsText)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type ScrollViewProps = typeof(require("@repo/tools/typecheck/aliases").ScrollViewProps)
type DemoTab = typeof(require("@repo/examples/types").DemoTab)
type Scenario = typeof(require("@repo/examples/types").Scenario)
type DemoTabs = typeof(require("@repo/examples/gallery/scenarios/demo_tabs"))
type ExampleContext = typeof(require("@repo/examples/types").Context)
local loadDemoTabs: (Instance) -> DemoTabs = require
local loadScenario: (Instance) -> Scenario = require

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local browser = {}

local LOG_LINES = 8
local catalog = require("./catalog")
type FacetModule = typeof(require("@repo/tools/typecheck/aliases").FacetModule)
type App = typeof(require("@repo/tools/typecheck/aliases").App)
type Controls = typeof(require("@repo/tools/typecheck/aliases").Controls)
type ThemePackage = typeof(require("@repo/tools/typecheck/aliases").ThemePackage)
type StringCell = typeof(require("@repo/tools/typecheck/aliases").StringCell)
type BooleanCell = typeof(require("@repo/tools/typecheck/aliases").BooleanCell)
type NumberCell = typeof(require("@repo/tools/typecheck/aliases").NumberCell)
type UnknownCell = typeof(require("@repo/tools/typecheck/aliases").UnknownCell)
type Cell<T> = Readable<T> & { set: (Cell<T>, T) -> (), update: (Cell<T>, (T) -> T) -> () }
type Settings = typeof(require("@repo/examples/facet-lab/src/lab_settings").new(nil :: never, nil :: never))
type Props = { width: unknown?, label: unknown?, Size: unknown?, AutomaticSize: unknown?, [unknown]: unknown }
type Source = Props | (catalog.Context) -> Props
type Page =
	{ id: string, title: string, family: string, kind: string, data: catalog.PageDefinition, helpers: { Page }? }
export type CatalogData = {
	families: { { id: string, label: string, pages: { Page } } },
	pages: { [string]: Page },
	missing: { string },
	stale: { string },
}
type PageState = {
	examples: BooleanCell,
	axis: { [string]: UnknownCell },
	flags: { [string]: BooleanCell },
	values: { [string]: UnknownCell },
	version: NumberCell,
	revision: NumberCell,
	log: Cell<{ string }>,
}
type MatrixEntry = { label: string, axis: { [string]: unknown }?, state: catalog.State?, context: Source? }
type OutlineEntry = {
	id: string,
	label: string,
	selected: (Use) -> boolean,
	matches: (string) -> boolean,
	pick: () -> (),
}
type Choice = { axis: string?, value: unknown, state: catalog.State? }
type Reply = { ok: boolean, reason: string?, id: string?, page: string?, section: string?, current: string? }
export type Context = {
	Facet: FacetModule,
	Compose: ComposeModule,
	UI: Controls,
	Host: RobloxHost,
	runtime: typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime),
	types: typeof(require("@repo/tools/typecheck/aliases").RobloxTypes),
	packages: { [string]: ThemePackage },
	theme: Cell<ThemePackage>,
	themeName: StringCell,
	themeMode: StringCell,
	sceneVisible: BooleanCell,
	preview: (ExampleContext, Instance, GuiObject) -> Frame,
}
local NONE = catalog.NONE
local collectionEditing = require(script.Parent.collection_editing)
local dragDropDemo = require(script.Parent.drag_drop_demo)
local variantCell = require(script.Parent.variant_cell)
local matrixRow = require(script.Parent.matrix_row)
local matrixWidth = require(script.Parent.matrix_width)
local matrixLimit = require(script.Parent.matrix_limit)
local renderResult = require(script.Parent.render_result)
local pageKey = require(script.Parent.page_key)

local SIZE_KEYS: { [string]: boolean } = { controlSize = true, starSize = true, segmentSize = true }

local function list<T>(items: { T }?): { T }
	return items or {}
end

export type MountOpts = { Facet: FacetModule, app: App, ctx: Context, settings: Settings, catalog: CatalogData }

function browser.mount(opts: MountOpts)
	local Facet, app, ctx, cat, settings = opts.Facet, opts.app, opts.ctx, opts.catalog, opts.settings
	local UI, Compose: ComposeModule = app.UI, Facet.Compose
	local Host = (app.runtime.constructors :: unknown) :: RobloxHost
	local adaptive = Facet.adaptive
	local scenarios = ReplicatedStorage:WaitForChild("FacetScenarios")
	local demoTabs = loadDemoTabs(scenarios:WaitForChild("demo_tabs"))

	local state = {
		top = Compose.cell("catalog"),
		selected = Compose.cell(cat.families[1].pages[1].id),
		query = Compose.cell(""),
		compactPath = Compose.cell({} :: { { id: string, value: unknown? } }),
		expanded = {} :: { [string]: BooleanCell },
		pages = {} :: { [string]: PageState },
		errors = {} :: { [string]: { [string]: string } },
	}
	for _, family in cat.families do
		state.expanded[family.id] = Compose.cell(true)
	end
	state.expanded.lab = Compose.cell(true)

	local env = UI.environment()

	local logical = Compose.cell({ width = 1280, height = 720 })
	local roomy = Compose.formula(function(use: Use)
		local size = use(logical)
		return adaptive.sizeClassAtLeast(adaptive.sizeClass(size.width), "regular")
			and adaptive.heightClass(size.height) ~= "short"
	end)
	local compact = Compose.formula(function(use: Use)
		return not use(roomy)
	end)

	local function wrapped(props: TextProps): GuiObject
		props.wrap = if props.wrap == nil then true else props.wrap
		props.Size = props.Size or UDim2.fromScale(1, 0)
		props.AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.Y
		props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
		return UI.Text(props)
	end
	local function caption(text: TextValue): GuiObject
		return wrapped({ text = text, textRole = "caption" })
	end
	local function heading(text: string): GuiObject
		return wrapped({ Name = "Heading", text = text, textRole = "heading" })
	end
	local function section(id: string, title: string, body: { Child }): GuiObject
		local children: StackProps = { Name = id, width = "fill", gap = "m", heading(title) }
		for _, child in body do
			children[#children + 1] = child
		end
		return UI.VStack(children)
	end
	local function scroller(id: string, children: ScrollViewProps): GuiObject
		children.Name = id
		children.width = "fill"
		children.height = "fill"
		children.gap = "xl"
		children.padding = { top = "m", left = "m", right = "m", bottom = "xl" }
		return UI.ScrollView(children)
	end
	local function when(condition: Readable<boolean> | (Use) -> boolean, view: () -> Child): Child
		return Compose.show(condition, view)
	end

	local function dropdown<V>(
		id: string,
		label: string,
		selected: Cell<V>,
		values: { V | { value: V, label: string } },
		onChange: ((V) -> ())?,
		enabledFor: ((V) -> Readable<boolean>)?
	): GuiObject
		local options: { typeof(require("@repo/tools/typecheck/aliases").PickerOption) } = {}
		for _, v in values do
			local option = (
				(if type(v) == "table" then table.clone(v) else { value = v, label = tostring(v) }) :: unknown
			) :: typeof(require("@repo/tools/typecheck/aliases").PickerOption)
			option.enabled = if enabledFor then enabledFor(option.value) else nil
			option.id = string.gsub(tostring(option.value), "[^%w_%-]", "_")
			table.insert(options, option)
		end
		return UI.Picker({
			Name = id,
			label = label,
			style = "menu",
			valueAlignment = "start",
			sizing = "hug",
			controlSize = "compact",
			selected = selected,
			options = options,
			onChange = onChange,
		})
	end
	local function titled(values: { string }): { { value: string, label: string } }
		local out = {}
		for _, v in values do
			local label = if v == "tv" then "TV" else string.upper(string.sub(v, 1, 1)) .. string.sub(v, 2)
			table.insert(out, { value = v, label = label })
		end
		return out
	end

	local function pageState(page: Page): PageState
		local ps = state.pages[page.id]
		if ps ~= nil then
			return ps
		end
		local data = page.data
		ps = {
			examples = Compose.cell(false),
			axis = {},
			flags = {},
			values = {},
			version = Compose.cell(0),
			revision = Compose.cell(0),
			log = Compose.cell({}),
		}
		for _, axis in list(data.axes) do
			ps.axis[axis.key] = Compose.cell(axis.values[1])
		end
		for _, st in list(data.states) do
			ps.flags[st.name] = Compose.cell(false)
		end
		state.pages[page.id] = ps
		return ps
	end

	local function append(ps: PageState, line: string)
		local lines = table.clone(ps.log:peek())
		table.insert(lines, `{os.date("%H:%M:%S")} {line}`)
		while #lines > LOG_LINES do
			table.remove(lines, 1)
		end
		ps.log:set(lines)
	end

	local function contextFor(ps: PageState, persistent: boolean): catalog.Context
		local c = (
			{
				UI = UI,
				Compose = Compose,
				Facet = Facet,
				Host = Host,
				types = ctx.types,
				app = app,
				ctx = ctx,
				logical = logical,
			} :: unknown
		) :: catalog.Context
		function c.cell<T>(name: string, initial: T): Cell<T>
			if not persistent then
				return Compose.cell(initial)
			end
			local value: Cell<T>? = (ps.values[name] :: unknown) :: Cell<T>?
			if value == nil then
				value = Compose.cell(initial)
				ps.values[name] = (value :: unknown) :: UnknownCell
				task.defer(function()
					ps.version:set(ps.version:peek() + 1)
				end)
			end
			return (value :: unknown) :: Cell<T>
		end
		function c.log(name: string): (...unknown) -> ()
			return function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					local v = select(i, ...)
					table.insert(parts, if type(v) == "table" then "{…}" else tostring(v))
				end
				append(ps, if #parts > 0 then `{name}({table.concat(parts, ", ")})` else name)
			end
		end
		return c
	end

	local function merge(into: Props, from: Source?, c: catalog.Context)
		local values: Props = if type(from) == "function" then from(c) else from or {}
		for key, value in values do
			into[key] = value
		end
	end

	local function finalProps(page: Page, c: catalog.Context, overrides: Props): Props
		local props = {}
		merge(props, page.data.base, c)
		for key, value in overrides do
			props[key] = if value == NONE or value == catalog.DEFAULT then nil else value
		end
		return props
	end

	local function configure(
		page: Page,
		c: catalog.Context,
		axisValues: Props,
		stateList: { catalog.State },
		context: Source?
	)
		local out: Props = {}
		for _, st in stateList do
			merge(out, st.props, c)
		end
		for key, value in axisValues do
			out[key] = value
		end
		local needs: { Source? } = { context }
		for _, axis in list(page.data.axes) do
			table.insert(needs, axis.implies and axis.implies[axisValues[axis.key] :: string])
		end
		for _, need in needs do
			local values: Props = if type(need) == "function" then need(c) else need or {}
			for key, value in values do
				if out[key] == nil then
					out[key] = value
				end
			end
		end
		return out
	end

	local ANY: unknown
	ANY = setmetatable({}, {
		__index = function()
			return ANY
		end,
		__call = function()
			return ANY
		end,
	})
	local DRY = (
		setmetatable({
			cell = function(_name: string, initial: unknown)
				return initial
			end,
			log = function()
				return function() end
			end,
		}, {
			__index = function()
				return ANY
			end,
		}) :: unknown
	) :: catalog.Context

	local function isValid(page: Page, axisValues: Props, stateList: { catalog.State }, context: Source?): boolean
		local valid = page.data.valid
		if
			valid ~= nil
			and not valid(finalProps(page, DRY, configure(page, DRY, axisValues, stateList, context)) :: never)
		then
			return false
		end
		local refusal = app.refusal
		if page.data.make ~= nil or refusal == nil then
			return true
		end
		local ok, answer = pcall(function()
			local live = contextFor(pageState(page), false)
			return refusal(page.id, finalProps(page, live, configure(page, live, axisValues, stateList, context)))
		end)
		return not ok or answer == nil
	end

	local function recordError(pageId: string, where: string, err: unknown)
		state.errors[pageId] = state.errors[pageId] or {}
		state.errors[pageId][where] = string.sub(tostring(err), 1, 240)
	end

	local function render(
		page: Page,
		c: catalog.Context,
		overrides: Props,
		where: string,
		tall: boolean?,
		available: Readable<number>?
	)
		local data = page.data
		return UI.ErrorBoundary "Live" {
			width = if data.cellWidth then "fill" else "hug",
			height = if tall then "fill" else "hug",
			view = function()
				local props = finalProps(page, c, overrides)
				local node = renderResult(state.errors, page.id, where, function()
					return if data.make then data.make(UI, props :: never, c) else app.construct(page.id, props)
				end)
				if available and page.kind == "control" and node:IsA("GuiObject") then
					matrixLimit(Compose, Host, node, available)
				end
				return node
			end,
			fallback = function(failure)
				recordError(page.id, where, failure)
				local message = string.gsub(tostring(failure), "^.-:%d+: ", "")
				return UI.Text "Refused" {
					text = `Refused: {string.sub(message, 1, 220)}`,
					textRole = "caption",
					wrap = true,
					Size = UDim2.fromOffset(240, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					TextXAlignment = Enum.TextXAlignment.Left,
					ref = function(label)
						label:AddTag("facet-validation")
					end,
				}
			end,
			onError = function() end,
			if tall then UI.fill() else nil,
		}
	end

	local function cells(page: Page, id: string, title: string?, entries: { MatrixEntry }): GuiObject?
		local data, c = page.data, contextFor(pageState(page), false)
		local available = Compose.cell(0)
		local row: StackProps = { Name = "Cells", width = "fill", wrap = true, gap = "m" }
		for i, entry in entries do
			local states = if entry.state then { entry.state } else {}
			if not isValid(page, entry.axis or {}, states, entry.context) then
				continue
			end
			local width = (entry.state and entry.state.cellWidth) or data.cellWidth
			local overrides = matrixWidth(
				Compose,
				configure(page, c, entry.axis or {}, states, entry.context),
				available,
				page.kind == "control",
				ctx.types,
				entry.state ~= nil and entry.state.name == "long text",
				if type(width) == "number" then width else nil
			)
			local height = if entry.state and entry.state.cellHeight then entry.state.cellHeight else data.cellHeight
			row[#row + 1] = variantCell(UI, {
				Name = `C{i}`,
				gap = "xs",
				width = (entry.state and entry.state.cellWidth) or data.cellWidth or "hug",
				height = height or "hug",
				UI.Text "Label" { text = entry.label, textRole = "caption" },
				render(page, c, overrides, `{id}C{i}`, height ~= nil, available),
			}, available)
		end
		if #row == 0 then
			return nil
		end
		local children: StackProps = { Name = id, width = "fill", gap = "s" }
		if title then
			children[#children + 1] = wrapped({ Name = "Title", text = title, textRole = "body" })
		end
		children[#children + 1] = matrixRow(UI, Compose, row, available)
		return UI.VStack(children)
	end

	local function axisCells(axis: catalog.Axis, st: catalog.State?): { MatrixEntry }
		local entries = {}
		for _, value in axis.values do
			table.insert(
				entries,
				{ label = tostring(value), axis = { [axis.key] = value }, state = st, context = axis.props }
			)
		end
		return entries
	end

	local function Controls(page: Page): GuiObject
		local data, ps = page.data, pageState(page)
		local axes, states = list(data.axes), list(data.states)
		local row: StackProps = { Name = "Options", width = "fill", wrap = true, gap = "m", align = "center" }

		local function current(
			use: Use,
			key: string?,
			value: unknown,
			extra: catalog.State?
		): ({ [string]: unknown }, { catalog.State })
			local values, list = {}, {}
			for _, axis in axes do
				values[axis.key] = if axis.key == key then value else use(ps.axis[axis.key])
			end
			for _, st in states do
				if st == extra or use(ps.flags[st.name]) then
					table.insert(list, st)
				end
			end
			return values, list
		end
		local checked = data.valid ~= nil or app.refusal ~= nil
		for _, axis in axes do
			row[#row + 1] = dropdown(
				`Axis_{axis.key}`,
				axis.key,
				ps.axis[axis.key],
				axis.values,
				nil,
				if checked
					then function(value)
						return Compose.formula(function(use: Use)
							return isValid(page, current(use, axis.key, value))
						end)
					end
					else nil
			)
		end
		for _, st in states do
			if st.matrixOnly then
				continue
			end
			row[#row + 1] = UI.Toggle({
				Name = `State_{st.name}`,
				label = st.name,
				presentation = "checkbox",
				appearance = "plain",
				controlSize = "compact",
				textSize = "label",
				value = ps.flags[st.name],

				enabled = if checked
					then Compose.formula(function(use: Use)
						return use(ps.flags[st.name]) or isValid(page, current(use, nil, nil, st))
					end)
					else nil,
			})
		end
		row[#row + 1] = UI.Button "Reset" {
			label = "Reset",
			textSize = "label",
			controlSize = "compact",
			onActivate = function()
				app.runtime:batch(function()
					for _, axis in axes do
						ps.axis[axis.key]:set(axis.values[1])
					end
					for _, st in states do
						ps.flags[st.name]:set(false)
					end
					ps.values = {}
					ps.revision:set(ps.revision:peek() + 1)
					ps.version:set(ps.version:peek() + 1)
					ps.log:set({})
				end)
			end,
		}
		return section("Controls", "Controls", { caption("Configuration options for the playground"), UI.HStack(row) })
	end

	local function show(v: unknown): string
		if type(v) == "table" and #(v :: { unknown }) > 0 then
			return `{#(v :: { unknown })} items`
		elseif type(v) == "table" then
			local parts = {}
			for k, x in v :: { [unknown]: unknown } do
				table.insert(parts, `{k}={tostring(x)}`)
			end
			table.sort(parts)
			return `\{{table.concat(parts, ", ")}\}`
		end
		return tostring(v)
	end

	local function Playground(page: Page): GuiObject
		local data, ps = page.data, pageState(page)
		local axes, states = list(data.axes), list(data.states)

		local signature = Compose.formula(function(use: Use)
			local parts = {}
			for _, axis in axes do
				table.insert(parts, `{axis.key}={use(ps.axis[axis.key])}`)
			end
			for _, st in states do
				if use(ps.flags[st.name]) then
					table.insert(parts, st.name)
				end
			end
			return { { id = table.concat(parts, " · ") } }
		end)
		local c = contextFor(ps, true)
		local cellHeight = Compose.formula(function(use: Use): number | "hug" | "fill"
			for _, st in states do
				if st.cellHeight and use(ps.flags[st.name]) then
					return st.cellHeight
				end
			end
			return data.cellHeight or "hug"
		end)
		local available = Compose.cell(0)
		local liveControl = UI.VStack "Live" {

			width = "fill",
			maxWidth = if data.cellWidth and not data.fills then data.cellWidth * 2 else nil,
			height = function(use: Use)
				return use(cellHeight) :: number | "hug" | "fill"
			end,
			padding = { top = "l", bottom = "l", left = "m", right = "m" },
			Compose.keyed({
				from = signature,
				key = function(item: { id: string }): string
					return item.id
				end,
				render = function(): GuiObject
					local values, list = {}, {}
					for _, axis in axes do
						values[axis.key] = ps.axis[axis.key]:peek()
					end
					for _, st in states do
						if ps.flags[st.name]:peek() then
							table.insert(list, st)
						end
					end
					local props = matrixWidth(
						Compose,
						configure(page, c, values, list),
						available,
						page.kind == "control",
						ctx.types,
						ps.flags["long text"] ~= nil and ps.flags["long text"]:peek()
					)
					return render(page, c, props, "playground", cellHeight:peek() ~= "hug", available)
				end,
			}),
		}

		local room = UI.environment(liveControl)
		Compose.watch(function(use: Use)
			available:set(use(room.viewportSize).X)
		end)
		local seen: { [string]: string } = {}
		Compose.watch(function(use: Use)
			use(ps.version)
			for name, cell in ps.values do
				local now = show(use(cell))
				if seen[name] ~= nil and seen[name] ~= now then
					append(ps, `{name} → {now}`)
				end
				seen[name] = now
			end
		end)
		local values = Compose.formula(function(use: Use)
			use(ps.version)
			local out = {}
			for name, cell in ps.values do
				table.insert(out, `{name} = {show(use(cell))}`)
			end
			table.sort(out)
			return if #out == 0 then "(no controlled values yet)" else table.concat(out, " · ")
		end)
		return section("Playground", "Playground", {
			liveControl,
			caption(function(use: Use)
				return `Configuration: {use(signature)[1].id}\nValues: {use(values)}`
			end),
			caption(function(use: Use)
				local lines = use(ps.log)
				return if #lines == 0 then "Event log: (interact with the control)" else table.concat(lines, "\n")
			end),
		})
	end

	local function Examples(page: Page): { Child }
		local data = page.data
		local axes = list(data.axes)
		local variants, sizing, states = {}, {}, {}
		if data.matrix == false then
			if #axes == 0 and #list(data.states) == 0 then
				return {}
			end
			return {
				section("Examples", "Examples", {
					caption("One presents at a time: set it up in Controls and open it in the Playground."),
				}),
			}
		end
		local shown, first = {}, nil
		for _, axis in axes do
			if axis.matrix ~= false then
				table.insert(shown, axis)
				if axis.key == data.stateAxis then
					first = axis
				end
			end
		end
		first = first or shown[1]
		for a, axis in shown do
			local view = cells(page, `A{a}`, axis.key, axisCells(axis))
			if view then
				table.insert(if SIZE_KEYS[axis.key] then sizing else variants, view)
			end
		end
		for s, st in list(data.states) do
			local across: catalog.Axis? = first
			for _, axis in shown do
				if axis.key == st.across then
					across = axis
				end
			end
			if st.across == false then
				across = nil
			end
			local entries = if across then axisCells(across, st) else { { label = st.name, state = st } }
			local view = cells(page, `S{s}`, st.name, entries)
			if view then
				table.insert(states, view)
			end
		end
		if #variants == 0 and #sizing == 0 then
			table.insert(variants, cells(page, "Rest", nil, { { label = "rest" } }))
		end
		local out = {}
		if #variants > 0 then
			table.insert(out, section("Variants", "Variants", variants))
		end
		if #sizing > 0 then
			table.insert(out, section("Sizing", "Sizing", sizing))
		end
		if #states > 0 then
			table.insert(out, section("States", "States", states))
		end
		return out
	end

	local function InContext(page: Page): GuiObject
		local ps = pageState(page)
		return UI.VStack "InContext" {
			width = "fill",
			gap = "s",
			when(function(use: Use)
				return not use(ps.examples)
			end, function()
				return UI.Button "ShowExamples" {
					label = "Show examples",
					appearance = "utility",
					controlSize = "compact",
					onActivate = function()
						ps.examples:set(true)
					end,
				}
			end),
			when(ps.examples, function()
				local entries: { DemoTab } = {}
				for _, name in assert(page.data.scenarios) do
					local module = scenarios:FindFirstChild(name)
					if module ~= nil then
						table.insert(entries, { id = name, label = name, scenario = loadScenario(module) })
					end
				end
				local scenarioCtx = (table.clone(ctx) :: unknown) :: ExampleContext
				scenarioCtx.UI = UI
				local built = demoTabs(scenarioCtx, "Examples", entries)
				return UI.VStack "Examples" { width = "fill", height = 600, built.screen() }
			end),
		}
	end

	local function Content(page: Page): GuiObject
		local data = page.data
		local body: { Child } = {}
		table.insert(body, caption(`Foundation: {data.alias or "—"}`))
		if data.alternatives then
			table.insert(body, caption(`Choose instead: {data.alternatives}`))
		end
		if data.snippet then
			table.insert(body, wrapped({ text = data.snippet, textRole = "caption", role = "content" }))
		end
		table.insert(
			body,
			caption(
				if page.kind == "control"
					then `Public: app.UI.{page.id} — docs/reference/api.md`
					elseif page.kind == "facet" then `Public: {data.surface or page.id} — docs/reference/api.md`
					else "Recipe: composed from the public controls above (no constructor of its own)"
			)
		)
		if page.id == "draggable" or page.id == "dropTarget" then
			table.insert(
				body,
				UI.Button "OpenDragDropDemo" {
					label = "Open Drag and drop demo",
					onActivate = function()
						state.top:set("drag-drop")
					end,
				}
			)
		end
		if data.scenarios then
			table.insert(body, InContext(page))
		end
		return section("Content", "Content", body)
	end

	local function Header(title: string, description: string?, note: string?): GuiObject
		local children: StackProps = {
			Name = "Header",
			width = "fill",
			gap = "m",
			wrapped({
				Name = "Title",
				text = title,
				textRole = function(use: Use)
					return if use(compact) then "heading" else "title"
				end,
			}),
		}
		if description then
			children[#children + 1] = wrapped({ Name = "Description", text = description })
		end
		if note then
			children[#children + 1] = wrapped({ Name = "Note", text = note })
		end
		return UI.VStack(children)
	end

	local function Page(page: Page): GuiObject
		local data = page.data
		local children: ScrollViewProps = { Header(page.title, data.purpose, data.note) }
		if page.id == "Table" or page.id == "VirtualList" or page.id == "VirtualGrid" or page.id == "Outline" then
			children[#children + 1] =
				section("Editing", if page.id == "Outline" then "Two-column hierarchy and editing" else "Editing", {
					collectionEditing(contextFor(pageState(page), true), page.id),
				})
		end
		if data.base ~= nil then
			local options = #list(data.axes)
			for _, st in list(data.states) do
				options += if st.matrixOnly then 0 else 1
			end
			if options > 0 then
				children[#children + 1] = Controls(page)
			end
			children[#children + 1] = Playground(page)
			for _, view in Examples(page) do
				children[#children + 1] = view
			end
		end
		for _, helper in (page.helpers or {} :: { Page }) do
			local hs = pageState(helper)
			local c = contextFor(hs, false)
			local values = {}
			for _, axis in list(helper.data.axes) do
				values[axis.key] = axis.values[1]
			end
			children[#children + 1] = section(`Helper_{helper.id}`, helper.data.alias or helper.id, {
				caption(`{helper.data.purpose} ({helper.data.snippet})`),
				render(helper, c, configure(helper, c, values, {}), "helper"),
			})
		end
		children[#children + 1] = Content(page)
		return scroller(`Page_{page.id}`, children)
	end

	local function tagged(name: string, tag: string, w: number, h: number): GuiObject
		local node = Host.Frame({ Name = name, Size = UDim2.fromOffset(w, h), BorderSizePixel = 0 })
		node:AddTag(tag)
		return node
	end
	local function StylePage(): GuiObject
		local surfaces: StackProps = { Name = "Surfaces", gap = "m", width = "fill", wrap = true }
		for _, tag in
			{ "surface", "pane", "panel", "control", "field", "button", "badge", "track", "skeleton", "scrim" }
		do
			surfaces[#surfaces + 1] = UI.VStack({
				gap = "xs",
				tagged(tag, `facet-{tag}`, 96, 56),
				UI.Text({ text = `facet-{tag}`, textRole = "caption" }),
			})
		end

		local palette = Compose.formula(function(use: Use)
			local package, name = use(ctx.theme), use(ctx.themeMode)
			for _, entry in package.style.themes do
				if entry.name == name then
					return entry
				end
			end
			return package.style.themes[1]
		end)
		local swatches: StackProps = { Name = "Palette", gap = "m", width = "fill", wrap = true }
		for _, role in
			{ "surface", "surfaceStrong", "content", "contentStrong", "accent", "danger", "success", "warning" }
		do
			local swatch: StackProps = {
				gap = "xs",
				Host.Frame({
					Name = role,
					Size = UDim2.fromOffset(72, 40),
					BorderSizePixel = 0,
					BackgroundColor3 = function(use: Use)
						local color = use(palette).colors[role]
						return if color then Color3.new(color.r, color.g, color.b) else Color3.new()
					end,
				}),
				UI.Text({ text = role, textRole = "caption" }),
			}
			swatches[#swatches + 1] = UI.VStack(swatch)
		end
		local ramp: StackProps = { Name = "Type", gap = "xs", width = "fill" }
		for _, role in Facet.themes.TYPE_ROLES do
			ramp[#ramp + 1] = wrapped({
				text = `{role} — The quick brown fox`,
				textRole = (role :: unknown) :: typeof(require("@repo/tools/typecheck/aliases").TextProps.textRole),
			})
		end
		local ladder: StackProps = { Name = "Ladder", gap = "m", width = "fill", wrap = true }
		for _, size in { "xsmall", "compact", "regular", "large" } :: { "xsmall" | "compact" | "regular" | "large" } do
			for _, appearance in
				{ "standard", "emphasis", "soft", "utility", "link", "inverse" } :: { "standard" | "emphasis" | "soft" | "utility" | "link" | "inverse" }
			do
				ladder[#ladder + 1] = UI.Button({
					label = appearance,
					appearance = appearance :: typeof(require("@repo/tools/typecheck/aliases").ButtonProps.appearance),
					controlSize = size :: typeof(require("@repo/tools/typecheck/aliases").ButtonProps.controlSize),
				})
			end
		end
		local dividers = UI.VStack "Dividers" {
			width = 240,
			gap = "s",
			UI.Text({ text = "standard", textRole = "caption" }),
			UI.Divider({}),
			UI.Text({ text = "strong", textRole = "caption" }),
			UI.Divider({ appearance = "strong" }),
		}
		return scroller("Style", {
			Header(
				"Style",
				"Theme token gallery: the public theme tags, the live palette, type roles and the control ladder."
			),
			caption(function(use: Use)
				return `Theme: {use(ctx.themeName)} / {use(ctx.themeMode)}`
			end),
			section("SurfacesSection", "Surface tags", { UI.HStack(surfaces) }),
			section("PaletteSection", "Palette", { UI.HStack(swatches) }),
			section("TypeSection", "Type roles", { UI.VStack(ramp) }),
			section("DividerSection", "Dividers", { dividers }),
			section("LadderSection", "Control ladder × appearance", { UI.HStack(ladder) }),
		})
	end

	local function themeOptions(): { { value: string, label: string } }
		local out = {}
		local names: { string } = {}
		for name in ctx.packages do
			table.insert(names, name)
		end
		table.sort(names, function(a, b)
			return if a == "foundation" then true elseif b == "foundation" then false else a < b
		end)
		for _, name in names do
			local package = ctx.packages[name]
			for _, palette in package.style.themes do
				table.insert(out, {
					value = `{name}/{palette.name}`,
					label = if name == "foundation"
						then palette.name
						else `{package.identity and package.identity.displayName or name} · {palette.name}`,
				})
			end
		end
		return out
	end
	local THEMES = themeOptions()
	local themeChoice = Compose.formula(function(use: Use)
		return `{use(ctx.themeName)}/{use(ctx.themeMode)}`
	end)
	local function setTheme(value: string): Reply
		local name, palette = string.match(value, "^([^/]+)/?(.*)$")
		local package = ctx.packages[name or ""]
		if package == nil then
			return { ok = false, reason = "unknown theme" }
		end
		app.runtime:batch(function()
			ctx.themeName:set(assert(name))
			ctx.theme:set(package)
			ctx.themeMode:set(if palette ~= nil and palette ~= "" then palette else package.style.defaultTheme)
		end)
		return { ok = true, current = themeChoice:peek() }
	end

	local themeCell = Compose.cell(themeChoice:peek())
	Compose.watch(function(use: Use)
		themeCell:set(use(themeChoice))
	end)

	local function settingPicker(key: string, label: string): GuiObject
		return dropdown(`Setting_{key}`, label, settings.cells[key], titled(settings.CHOICES[key]), function(value)
			settings.set(key, value)
		end)
	end

	local MOTION_OPTIONS = {
		{ value = "automatic", label = "Device" },
		{ value = "normal", label = "Game: Normal" },
		{ value = "limited", label = "Game: Limited" },
		{ value = "none", label = "Game: None" },
	}
	local function motionPicker(): GuiObject
		return dropdown("Setting_motion", "Motion", settings.cells.motion, MOTION_OPTIONS, function(value)
			settings.set("motion", value)
		end)
	end

	local function SettingsPage(): GuiObject
		return scroller("Settings", {
			Header("Settings", "Theme and preview. Every setting is reused public Facet or showcase logic."),
			section("ThemeSection", "Theme", {
				dropdown("Theme", "Theme", themeCell, THEMES, setTheme),
			}),
			section("PreviewSection", "Preview", {
				settingPicker("platform", "Platform"),
				settingPicker("orientation", "Orientation"),
				settingPicker("distance", "Viewing distance"),
				motionPicker(),
				settingPicker("transparency", "Preferred transparency"),
				settingPicker("hover", "Hover paint"),
				settingPicker("input", "Input"),
				settingPicker("text", "Text size"),
				UI.Toggle "Setting_buttonGuides" { label = "Button guides", value = settings.buttonGuides },
				caption(
					"A forced input or text size is a preview of Facet's decisions (the controls' environment option); real engine input still arrives and the engine still renders the device text size. For real touch and gamepad use Studio's Device Emulator and Controller Emulator."
				),
			}),
			section("SimulationSection", "Simulated or real", {
				caption(settings.lines),
				UI.Button "ResetAll" {
					label = "Reset everything to Automatic",
					onActivate = settings.reset,
				},
			}),
			section("BuildSection", "Build", {
				caption(`Facet {Facet.VERSION} · {tostring(workspace:GetAttribute("Facet_Build"))}`),
			}),
		})
	end

	local function Detail(): GuiObject
		local current = Compose.formula(function(use: Use)
			local top = use(state.top)
			local id = if top == "catalog" then use(state.selected) else "@" .. top
			local revision = if top == "catalog" then use(pageState(cat.pages[id]).revision) else 0
			return { { id = id, revision = revision } }
		end)
		local detail: StackProps = { Name = "Detail", width = "fill", height = "fill" }
		detail[#detail + 1] = UI.VStack "Body" {
			width = "fill",
			height = "fill",
			UI.fill(),
			Compose.keyed({
				from = current,
				key = pageKey,
				render = function(item: Readable<{ id: string, revision: number }>): GuiObject
					local id = item:peek().id
					if id == "@style" then
						return StylePage()
					elseif id == "@settings" then
						return SettingsPage()
					elseif id == "@drag-drop" then
						return dragDropDemo(ctx)
					end
					local ok, node = pcall(Page, cat.pages[id])
					if ok then
						return node
					end
					recordError(id, "page", node)
					return caption(`Page failed: {node}`)
				end,
			}),
		}
		return UI.VStack(detail)
	end

	local function matches(page: Page, query: string): boolean
		if query == "" then
			return true
		end
		local hay = string.lower(page.title .. " " .. ((page.data and page.data.alias) or ""))
		return string.find(hay, string.lower(query), 1, true) ~= nil
	end

	local function pageRow(
		id: string,
		label: string,
		isSelected: (Use) -> boolean,
		pick: () -> (),
		shown: (Use) -> boolean
	)
		return UI.Button({
			Name = id,
			Visible = shown,
			label = label,

			appearance = "utility",
			controlSize = "compact",
			textSize = "body",
			selected = isSelected,
			onActivate = pick,
			Size = function(use: Use)
				local package = use(ctx.theme)
				local dense = math.max(32, package.metrics.targetSizes.pointer or 44)
				return UDim2.new(1, 0, 0, if use(env.interactionClasses).primary == "pointer" then dense else 44)
			end,
			AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	local function Outline(onPick: (() -> ())?): GuiObject
		local function group(id: string, label: string, entries: { OutlineEntry })
			local function any(use: Use): boolean
				local q = use(state.query)
				for _, e in entries do
					if e.matches(q) then
						return true
					end
				end
				return false
			end
			return UI.DisclosureGroup({
				Name = `G_{id}`,
				label = label,
				appearance = "outline",
				textSize = "body",
				indent = "m",
				expanded = state.expanded[id],
				Size = UDim2.fromScale(1, 0),
				Visible = any,
				content = function(): Instance
					local rows: StackProps = { Name = "Rows", width = "fill" }
					for _, e in entries do
						local row = pageRow(e.id, e.label, e.selected, function()
							e.pick()
							if onPick then
								onPick()
							end
						end, function(use: Use)
							return e.matches(use(state.query))
						end)
						rows[#rows + 1] = row
					end
					return UI.VStack(rows)
				end,
			})
		end
		local groups: StackProps = { Name = "Tree", width = "fill", gap = 0, padding = { bottom = "m" } }
		for _, family in cat.families do
			local entries = {}
			for _, page in family.pages do
				table.insert(entries, {
					id = `P_{page.id}`,
					label = page.title,
					selected = function(use: Use)
						return use(state.top) == "catalog" and use(state.selected) == page.id
					end,
					matches = function(q)
						return matches(page, q)
					end,
					pick = function()
						app.runtime:batch(function()
							state.top:set("catalog")
							state.selected:set(page.id)
						end)
					end,
				})
			end
			groups[#groups + 1] = group(family.id, family.label, entries)
		end
		local labEntries = {}
		for _, entry in { { id = "drag-drop", label = "Drag and drop demo" }, { id = "style", label = "Style" } } do
			table.insert(labEntries, {
				id = `L_{entry.id}`,
				label = entry.label,
				selected = function(use: Use)
					return use(state.top) == entry.id
				end,
				matches = function(q)
					return q == "" or string.find(string.lower(entry.label), string.lower(q), 1, true) ~= nil
				end,
				pick = function()
					state.top:set(entry.id)
					if onPick then
						onPick()
					end
				end,
			})
		end
		groups[#groups + 1] = group("lab", "Lab", labEntries)
		return UI.VStack "OutlineList" {
			width = "fill",
			height = "fill",
			gap = "s",
			padding = { top = "s", left = "s", right = "s" },
			UI.TextInput "Search" {
				value = state.query,
				placeholder = "Search...",
				presentation = "search",
				clearButton = true,
				controlSize = "compact",
				Size = UDim2.fromScale(1, 0),
			},
			UI.Button "L_settings" {
				label = "Settings",
				icon = "settings",
				controlSize = "compact",
				selected = function(use: Use)
					return use(state.top) == "settings"
				end,
				onActivate = function()
					state.top:set("settings")
					if onPick then
						onPick()
					end
				end,
				Size = UDim2.fromScale(1, 0),
			},
			UI.ScrollView "Outline" {
				width = "fill",
				height = "fill",
				UI.fill(),
				UI.VStack(groups),
			},
		}
	end

	local function Catalog(): GuiObject
		return UI.VStack "Catalog" {
			width = "fill",
			height = "fill",
			when(roomy, function()
				local pane = UI.VStack "OutlinePane" {
					height = "fill",
					width = function(use: Use)
						return math.clamp(math.floor(use(logical).width * 0.22), 240, 305)
					end,
					Outline(),
				}
				pane:AddTag("facet-pane")

				UI.focusSection(pane)
				return UI.HStack "Split" {
					width = "fill",
					height = "fill",
					gap = 0,
					pane,
					UI.Divider "PaneDivider" { appearance = "strong" },
					UI.VStack "DetailPane" {
						width = "fill",
						height = "fill",
						UI.fill(),
						Detail(),
					},
				}
			end),
			when(compact, function()
				local function open()
					state.compactPath:set({ { id = "page" } })
				end
				return UI.NavigationStack "Browse" {
					path = state.compactPath,
					backLabel = "Controls",
					Size = UDim2.fromScale(1, 1),
					root = {
						title = "Controls",
						content = function(): Instance
							local outline = Outline(open)

							UI.focusSection(outline, { focusOnAppear = `P_{state.selected:peek()}` })
							return outline
						end,
					},
					destinations = {
						page = {
							title = function(use: Use)
								local top = use(state.top)
								if top ~= "catalog" then
									return if top == "settings"
										then "Settings"
										elseif top == "drag-drop" then "Drag and drop demo"
										else "Style"
								end
								local page = cat.pages[use(state.selected)]
								return if page then page.title else ""
							end,
							content = function(): Instance
								return UI.VStack "Current" {
									width = "fill",
									height = "fill",
									Detail(),
								}
							end,
						},
					},
				}
			end),
		}
	end

	app.mount(function()
		local roomSize = Compose.cell(nil :: Vector2?)
		local device = Compose.formula(function(use: Use)
			local size = use(roomSize) or use(env.viewportSize)
			return settings.device(use, { width = math.max(size.X, 320), height = math.max(size.Y, 240) })
		end)
		Compose.watch(function(use: Use)
			local size = use(device).logical
			logical:set(size)
			settings.viewport:set(Vector2.new(size.width, size.height))
		end)
		local deviceProps: StackProps = {
			Size = function(use: Use)
				local d = use(device)
				return if d.simulated
					then UDim2.fromOffset(d.logical.width, d.logical.height)
					else UDim2.fromScale(1 / d.scale, 1 / d.scale)
			end,
			AutomaticSize = Enum.AutomaticSize.None,
			ClipsDescendants = true,

			padding = function(use: Use): number | { left: number, right: number, top: number, bottom: number }
				local d = use(device)
				if use(settings.cells.platform) ~= "tv" then
					return 0
				end
				local w, h = d.logical.width, d.logical.height
				return {
					left = math.floor(w * 0.05),
					right = math.floor(w * 0.05),
					top = math.floor(h * 0.05),
					bottom = math.floor(h * 0.05),
				}
			end,

			Host.UIStroke({
				Name = "DeviceEdge",
				Color = Color3.fromRGB(128, 128, 128),
				Thickness = 1,
				Transparency = function(use: Use)
					return if use(device).simulated then 0.4 else 1
				end,
			}),
			Host.UIScale({
				Name = "Preview",
				Scale = function(use: Use)
					return use(device).scale
				end,
			}),
			Catalog(),
		}
		local frame = UI.VStack "Device"(deviceProps)
		frame:AddTag("facet-surface")
		Compose.watch(function(use)
			frame.BackgroundTransparency = if use(ctx.sceneVisible) then 1 else 0
		end)
		local stage = UI.ZStack "Stage" {
			width = "fill",
			height = "fill",
			alignH = "center",
			alignV = "center",
			frame,
		}
		local room = UI.environment(stage)
		Compose.watch(function(use: Use)
			roomSize:set(use(room.viewportSize))
		end)
		return ctx.preview((ctx :: unknown) :: ExampleContext, stage, frame)
	end)

	return {
		state = state,
		settings = settings,
		setTheme = setTheme,
		themes = function()
			local entries = {}
			for name, package in ctx.packages do
				local palettes = {}
				for _, palette in package.style.themes do
					table.insert(palettes, palette.name)
				end
				table.insert(entries, { id = name, themes = palettes })
			end
			return { entries = entries, current = themeChoice:peek() }
		end,
		pageIds = function(): { string }
			local ids = {}
			for _, family in cat.families do
				for _, page in family.pages do
					table.insert(ids, page.id)
				end
			end
			return ids
		end,
		pages = cat.pages,
		open = function(id: string): Reply
			if cat.pages[id] == nil then
				return { ok = false, reason = "unknown page" }
			end
			app.runtime:batch(function()
				state.top:set("catalog")
				state.selected:set(id)
				state.compactPath:set({ { id = "page" } })
			end)
			return { ok = true, id = id }
		end,
		section = function(name: string): Reply
			local page = cat.pages[state.selected:peek()]
			local data = page.data
			local exists = name == "overview"
				or (name == "examples" and data.scenarios ~= nil)
				or (
					name == "editing"
					and (
						page.id == "Table"
						or page.id == "VirtualList"
						or page.id == "VirtualGrid"
						or page.id == "Outline"
					)
				)
			if exists and name == "examples" then
				pageState(page).examples:set(true)
			end
			return { ok = exists, page = page.id, section = name }
		end,

		probe = function(): { string }
			local page = cat.pages[state.selected:peek()]
			local data = page.data
			if data == nil or data.base == nil then
				return {}
			end
			local ps = pageState(page)
			local axes, states = list(data.axes), list(data.states)
			local choices: { Choice } = {}
			for _, axis in axes do
				for _, value in axis.values do
					table.insert(choices, { axis = axis.key, value = value })
				end
			end
			for _, st in states do
				if not st.matrixOnly then
					table.insert(choices, { state = st })
				end
			end
			local refused = {}
			local function try(list: { Choice })
				local values, active = {}, {}
				for _, axis in axes do
					values[axis.key] = axis.values[1]
				end
				for _, choice in list do
					if choice.axis then
						values[choice.axis] = choice.value
					else
						table.insert(active, assert(choice.state))
					end
				end
				if not isValid(page, values, active) then
					return
				end
				state.errors[page.id] = {}
				app.runtime:batch(function()
					for _, axis in axes do
						ps.axis[axis.key]:set(values[axis.key])
					end
					for _, st in states do
						ps.flags[st.name]:set(table.find(active, st) ~= nil)
					end
				end)
				task.wait()
				local err = state.errors[page.id].playground
				if err then
					local parts = {}
					for key, value in values do
						table.insert(parts, `{key}={value}`)
					end
					for _, st in active do
						table.insert(parts, `+{st.name}`)
					end
					table.sort(parts)
					table.insert(refused, `{table.concat(parts, " ")}: {string.sub(err, 1, 120)}`)
				end
			end
			for i, a in choices do
				try({ a })
				for j = i + 1, #choices do
					local b = choices[j]
					if not (a.axis and b.axis and a.axis == b.axis) then
						try({ a, b })
					end
				end
			end
			state.errors[page.id] = {}
			app.runtime:batch(function()
				for _, axis in axes do
					ps.axis[axis.key]:set(axis.values[1])
				end
				for _, st in states do
					ps.flags[st.name]:set(false)
				end
			end)
			return refused
		end,

		configure = function(command: string): Reply
			local page = cat.pages[state.selected:peek()]
			local ps = pageState(page)
			local function allowed(key: string?, value: unknown, flag: string?): boolean
				local axes, active = {}, {}
				for name, cell in ps.axis do
					axes[name] = if name == key then value else cell:peek()
				end
				for _, st in list(page.data.states) do
					if (st.name == flag and value == true) or (st.name ~= flag and ps.flags[st.name]:peek()) then
						table.insert(active, st)
					end
				end
				return isValid(page, axes, active)
			end

			local name, json = string.match(command, "^value:([^=]+)=(.*)$")
			if name then
				local cell = ps.values[name]
				if cell == nil then
					return { ok = false, reason = "no such value" }
				end
				cell:set(game:GetService("HttpService"):JSONDecode(assert(json)))
				return { ok = true }
			end
			local sign, flag = string.match(command, "^([%+%-])(.+)$")
			if sign and flag and ps.flags[flag] then
				if sign == "+" and not allowed(nil, true, flag) then
					return { ok = false, reason = "disabled configuration" }
				end
				ps.flags[flag]:set(sign == "+")
				return { ok = true }
			end
			local key, value = string.match(command, "^([^=]+)=(.*)$")
			if key and ps.axis[key] then
				for _, axis in list(page.data.axes) do
					local options: { unknown } = if axis.key == key then axis.values else {}
					for _, v in options do
						if tostring(v) == value then
							if not allowed(key, v, nil) then
								return { ok = false, reason = "disabled configuration" }
							end
							ps.axis[key]:set(v)
							return { ok = true }
						end
					end
				end
				return { ok = false, reason = "unknown option" }
			end
			return { ok = false, reason = "unknown command" }
		end,
		report = function()
			local page = cat.pages[state.selected:peek()]
			local ps = pageState(page)
			local config: { [string]: boolean | string } = {}
			local values = {}
			for key, cell in ps.axis do
				config[key] = tostring(cell:peek())
			end
			for key, cell in ps.flags do
				if cell:peek() then
					config["+" .. key] = true
				end
			end
			for key, cell in ps.values do
				values[key] = show(cell:peek())
			end
			local total = 0
			for _, errs in state.errors do
				for _ in errs do
					total += 1
				end
			end
			local selected = game:GetService("GuiService").SelectedObject
			return {
				top = state.top:peek(),
				page = page.id,
				selected = if selected then selected:GetFullName() else nil,
				config = config,
				values = values,
				examples = ps.examples:peek(),
				errors = state.errors[page.id] or {} :: { [string]: string },
				pageErrors = state.errors,
				totalErrors = total,
				missing = cat.missing,
				log = ps.log:peek(),
				logical = logical:peek(),
			}
		end,
	}
end

return browser
