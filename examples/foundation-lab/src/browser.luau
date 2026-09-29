--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local browser = {}

local LOG_LINES = 8
local catalog = require(script.Parent.catalog)
local NONE = catalog.NONE

local SIZE_KEYS = { controlSize = true, starSize = true, segmentSize = true }

export type MountOpts = { Facet: any, app: any, ctx: any, settings: any, catalog: any }

function browser.mount(opts: MountOpts): any
	local Facet, app, ctx, cat, settings = opts.Facet, opts.app, opts.ctx, opts.catalog, opts.settings
	local UI, Compose = app.UI, Facet.Compose
	local Host = app.runtime.constructors
	local adaptive = Facet.adaptive
	local scenarios = ReplicatedStorage:WaitForChild("FacetScenarios")
	local demoTabs = require(scenarios:WaitForChild("demo_tabs")) :: any

	local state = {
		top = Compose.cell("catalog"),
		selected = Compose.cell(cat.families[1].pages[1].id),
		query = Compose.cell(""),
		compactPath = Compose.cell({}),
		expanded = {} :: { [string]: any },
		pages = {} :: { [string]: any },
		errors = {} :: { [string]: { [string]: string } },
	}
	for _, family in cat.families do
		state.expanded[family.id] = Compose.cell(true)
	end
	state.expanded.lab = Compose.cell(true)

	local env = UI.environment()

	local logical = Compose.cell({ width = 1280, height = 720 })
	local roomy = Compose.formula(function(use)
		local size = use(logical)
		return adaptive.sizeClassAtLeast(adaptive.sizeClass(size.width), "regular")
			and adaptive.heightClass(size.height) ~= "short"
	end)
	local compact = Compose.formula(function(use)
		return not use(roomy)
	end)

	local function wrapped(props: { [string]: any }): any
		props.wrap = if props.wrap == nil then true else props.wrap
		props.Size = props.Size or UDim2.fromScale(1, 0)
		props.AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.Y
		props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
		return UI.Text(props)
	end
	local function caption(text: any): any
		return wrapped({ text = text, textRole = "caption" })
	end
	local function heading(text: string): any
		return wrapped({ Name = "Heading", text = text, textRole = "heading" })
	end
	local function section(id: string, title: string, body: { any }): any
		local children: { any } = { Name = id, width = "fill", gap = "m", heading(title) }
		for _, child in body do
			table.insert(children, child)
		end
		return UI.VStack(children)
	end
	local function scroller(id: string, children: { any }): any
		children.Name = id
		children.width = "fill"
		children.height = "fill"
		children.gap = "xl"
		children.padding = { top = "m", left = "m", right = "m", bottom = "xl" }
		return UI.ScrollView(children)
	end
	local function when(condition: any, view: () -> any): any
		return Compose.show(condition, view)
	end

	local function dropdown(id: string, label: string, selected: any, values: { any }, onChange: any?, enabledFor: any?)
		local options = {}
		for _, v in values do
			local option = if type(v) == "table" then table.clone(v) else { value = v, label = tostring(v) }
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
	local function titled(values: { string }): { any }
		local out = {}
		for _, v in values do
			local label = if v == "tv" then "TV" else string.upper(string.sub(v, 1, 1)) .. string.sub(v, 2)
			table.insert(out, { value = v, label = label })
		end
		return out
	end

	local function pageState(page: any): any
		local ps = state.pages[page.id]
		if ps ~= nil then
			return ps
		end
		local data = page.data or {}
		ps = {
			examples = Compose.cell(false),
			axis = {},
			flags = {},
			values = {},
			version = Compose.cell(0),
			log = Compose.cell({}),
		}
		for _, axis in data.axes or {} do
			ps.axis[axis.key] = Compose.cell(axis.values[1])
		end
		for _, st in data.states or {} do
			ps.flags[st.name] = Compose.cell(false)
		end
		state.pages[page.id] = ps
		return ps
	end

	local function append(ps: any, line: string)
		local lines = table.clone(ps.log:peek())
		table.insert(lines, `{os.date("%H:%M:%S")} {line}`)
		while #lines > LOG_LINES do
			table.remove(lines, 1)
		end
		ps.log:set(lines)
	end

	local function contextFor(ps: any, persistent: boolean): any
		local c: any = {
			UI = UI,
			Compose = Compose,
			Facet = Facet,
			Host = Host,
			app = app,
			ctx = ctx,
			logical = logical,
		}
		function c.cell(name: string, initial: any): any
			if not persistent then
				return Compose.cell(initial)
			end
			local value = ps.values[name]
			if value == nil then
				value = Compose.cell(initial)
				ps.values[name] = value
				task.defer(function()
					ps.version:set(ps.version:peek() + 1)
				end)
			end
			return value
		end
		function c.log(name: string): (...any) -> ()
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

	local function merge(into: { [any]: any }, from: any, c: any)
		local values = if type(from) == "function" then from(c) else from
		for key, value in values or {} do
			into[key] = value
		end
	end

	local function finalProps(page: any, c: any, overrides: { [string]: any }): { [any]: any }
		local props = {}
		merge(props, page.data.base, c)
		for key, value in overrides do
			props[key] = if value == NONE or value == catalog.DEFAULT then nil else value
		end
		return props
	end

	local function configure(page: any, c: any, axisValues: { [string]: any }, stateList: { any }, context: any?)
		local out = {}
		for _, st in stateList do
			merge(out, st.props, c)
		end
		for key, value in axisValues do
			out[key] = value
		end
		local needs = { context }
		for _, axis in page.data.axes or {} do
			table.insert(needs, axis.implies and axis.implies[axisValues[axis.key]])
		end
		for _, need in needs do
			for key, value in (if type(need) == "function" then need(c) else need) or {} do
				if out[key] == nil then
					out[key] = value
				end
			end
		end
		return out
	end

	local ANY: any
	ANY = setmetatable({}, {
		__index = function()
			return ANY
		end,
		__call = function()
			return ANY
		end,
	})
	local DRY = setmetatable({
		cell = function(_name: string, initial: any): any
			return initial
		end,
		log = function(): any
			return function() end
		end,
	}, {
		__index = function()
			return ANY
		end,
	})

	local function isValid(page: any, axisValues: { [string]: any }, stateList: { any }, context: any?): boolean
		local valid = page.data.valid
		if valid ~= nil and not valid(finalProps(page, DRY, configure(page, DRY, axisValues, stateList, context))) then
			return false
		end
		local refusal = (app :: any).refusal
		if page.data.make ~= nil or refusal == nil then
			return true
		end
		local ok, answer = pcall(function()
			local live = contextFor(pageState(page), false)
			return refusal(page.id, finalProps(page, live, configure(page, live, axisValues, stateList, context)))
		end)
		return not ok or answer == nil
	end

	local function recordError(pageId: string, where: string, err: any)
		state.errors[pageId] = state.errors[pageId] or {}
		state.errors[pageId][where] = string.sub(tostring(err), 1, 240)
	end

	local function render(page: any, c: any, overrides: { [string]: any }, where: string, tall: boolean?): any
		local data = page.data
		return UI.ErrorBoundary({
			Name = "Live",
			width = if data.cellWidth then "fill" else "hug",
			height = if tall then "fill" else "hug",
			view = function()
				local props = finalProps(page, c, overrides)
				if data.make then
					return data.make(UI, props, c)
				end
				return UI[page.id](props)
			end,
			fallback = function(failure)
				recordError(page.id, where, failure)
				local message = string.gsub(tostring(failure), "^.-:%d+: ", "")
				return UI.Text({
					Name = "Refused",
					text = `Refused: {string.sub(message, 1, 220)}`,
					textRole = "caption",
					wrap = true,
					Size = UDim2.fromOffset(240, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					TextXAlignment = Enum.TextXAlignment.Left,
					ref = function(label)
						label:AddTag("facet-validation")
					end,
				})
			end,
			onError = function() end,
			if tall then UI.fill() else nil,
		})
	end

	local function cells(page: any, id: string, title: string?, entries: { any }): any
		local data, c = page.data, contextFor(pageState(page), false)
		local row: { any } = { Name = "Cells", width = "fill", wrap = true, gap = "m" }
		for i, entry in entries do
			local states = if entry.state then { entry.state } else {}
			if not isValid(page, entry.axis or {}, states, entry.context) then
				continue
			end
			local overrides = configure(page, c, entry.axis or {}, states, entry.context)
			local height = if entry.state and entry.state.cellHeight then entry.state.cellHeight else data.cellHeight
			table.insert(
				row,
				UI.VStack({
					Name = `C{i}`,
					gap = "xs",
					width = (entry.state and entry.state.cellWidth) or data.cellWidth or "hug",
					height = height or "hug",
					UI.Text({ Name = "Label", text = entry.label, textRole = "caption" }),
					render(page, c, overrides, `{id}C{i}`, height ~= nil),
				})
			)
		end
		if #row == 0 then
			return nil
		end
		local children: { any } = { Name = id, width = "fill", gap = "s" }
		if title then
			table.insert(children, wrapped({ Name = "Title", text = title, textRole = "body" }))
		end
		table.insert(children, UI.HStack(row))
		return UI.VStack(children)
	end

	local function axisCells(axis: any, st: any?): { any }
		local entries = {}
		for _, value in axis.values do
			table.insert(
				entries,
				{ label = tostring(value), axis = { [axis.key] = value }, state = st, context = axis.props }
			)
		end
		return entries
	end

	local function Controls(page: any): any
		local data, ps = page.data, pageState(page)
		local axes, states = data.axes or {}, data.states or {}
		local row: { any } = { Name = "Options", width = "fill", wrap = true, gap = "m", align = "center" }

		local function current(use: any, key: string?, value: any, extra: any?): (any, any)
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
		local checked = data.valid ~= nil or (app :: any).refusal ~= nil
		for _, axis in axes do
			table.insert(
				row,
				dropdown(
					`Axis_{axis.key}`,
					axis.key,
					ps.axis[axis.key],
					axis.values,
					nil,
					if checked
						then function(value)
							return Compose.formula(function(use)
								return isValid(page, current(use, axis.key, value))
							end)
						end
						else nil
				)
			)
		end
		for _, st in states do
			if st.matrixOnly then
				continue
			end
			table.insert(
				row,
				UI.Toggle({
					Name = `State_{st.name}`,
					label = st.name,
					presentation = "checkbox",
					appearance = "plain",
					controlSize = "compact",
					textSize = "label",
					value = ps.flags[st.name],

					enabled = if checked
						then Compose.formula(function(use)
							return use(ps.flags[st.name]) or isValid(page, current(use, nil, nil, st))
						end)
						else nil,
				})
			)
		end
		table.insert(
			row,
			UI.Button({
				Name = "Reset",
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
						ps.version:set(ps.version:peek() + 1)
						ps.log:set({})
					end)
				end,
			})
		)
		return section("Controls", "Controls", { caption("Configuration options for the playground"), UI.HStack(row) })
	end

	local function show(v: any): string
		if type(v) == "table" and #v > 0 then
			return `{#v} items`
		elseif type(v) == "table" then
			local parts = {}
			for k, x in v do
				table.insert(parts, `{k}={tostring(x)}`)
			end
			table.sort(parts)
			return `\{{table.concat(parts, ", ")}\}`
		end
		return tostring(v)
	end

	local function Playground(page: any): any
		local data, ps = page.data, pageState(page)
		local axes, states = data.axes or {}, data.states or {}

		local signature = Compose.formula(function(use)
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
		local cellHeight = Compose.formula(function(use)
			for _, st in states do
				if st.cellHeight and use(ps.flags[st.name]) then
					return st.cellHeight
				end
			end
			return data.cellHeight or "hug"
		end)
		local liveControl = UI.VStack({
			Name = "Live",

			width = if data.fills then "fill" elseif data.cellWidth then data.cellWidth * 2 else "hug",
			height = cellHeight,
			padding = { top = "l", bottom = "l", left = "m", right = "m" },
			Compose.keyed({
				from = signature,
				key = function(item: any): string
					return item.id
				end,
				render = function()
					local values, list = {}, {}
					for _, axis in axes do
						values[axis.key] = ps.axis[axis.key]:peek()
					end
					for _, st in states do
						if ps.flags[st.name]:peek() then
							table.insert(list, st)
						end
					end
					return render(page, c, configure(page, c, values, list), "playground", cellHeight:peek() ~= "hug")
				end,
			}),
		})

		local seen: { [string]: string } = {}
		Compose.watch(function(use)
			use(ps.version)
			for name, cell in ps.values do
				local now = show(use(cell))
				if seen[name] ~= nil and seen[name] ~= now then
					append(ps, `{name} → {now}`)
				end
				seen[name] = now
			end
		end)
		local values = Compose.formula(function(use)
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
			caption(function(use)
				return `Configuration: {use(signature)[1].id}\nValues: {use(values)}`
			end),
			caption(function(use)
				local lines = use(ps.log)
				return if #lines == 0 then "Event log: (interact with the control)" else table.concat(lines, "\n")
			end),
		})
	end

	local function Examples(page: any): { any }
		local data = page.data
		local axes = data.axes or {}
		local variants, sizing, states = {}, {}, {}
		if data.matrix == false then
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
		for s, st in data.states or {} do
			local across = first
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

	local function InContext(page: any): any
		local ps = pageState(page)
		return UI.VStack({
			Name = "InContext",
			width = "fill",
			gap = "s",
			when(function(use)
				return not use(ps.examples)
			end, function()
				return UI.Button({
					Name = "ShowExamples",
					label = "Show examples",
					appearance = "utility",
					controlSize = "compact",
					onActivate = function()
						ps.examples:set(true)
					end,
				})
			end),
			when(ps.examples, function()
				local entries = {}
				for _, name in page.data.scenarios do
					local module = scenarios:FindFirstChild(name)
					if module ~= nil then
						table.insert(entries, { id = name, label = name, scenario = require(module) :: any })
					end
				end
				local scenarioCtx = table.clone(ctx)
				scenarioCtx.UI = UI
				local built = demoTabs(scenarioCtx, "Examples", entries)
				if built.dispose then
					Compose.cleanup(built.dispose)
				end
				return UI.VStack({ Name = "Examples", width = "fill", height = 600, built.screen() })
			end),
		})
	end

	local function Content(page: any): any
		local data = page.data or {}
		local body: { any } = {}
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
		if data.scenarios then
			table.insert(body, InContext(page))
		end
		return section("Content", "Content", body)
	end

	local function Header(title: string, description: string?, note: string?): any
		local children: { any } = {
			Name = "Header",
			width = "fill",
			gap = "m",
			wrapped({
				Name = "Title",
				text = title,
				textRole = function(use)
					return if use(compact) then "heading" else "title"
				end,
			}),
		}
		if description then
			table.insert(children, wrapped({ Name = "Description", text = description }))
		end
		if note then
			table.insert(children, wrapped({ Name = "Note", text = note }))
		end
		return UI.VStack(children)
	end

	local function Page(page: any): any
		local data = page.data
		local children: { any } = { Header(page.title, data.purpose, data.note) }
		if data.base ~= nil then
			local options = #(data.axes or {})
			for _, st in data.states or {} do
				options += if st.matrixOnly then 0 else 1
			end
			if options > 0 then
				table.insert(children, Controls(page))
			end
			table.insert(children, Playground(page))
			for _, view in Examples(page) do
				table.insert(children, view)
			end
		end
		for _, helper in page.helpers or {} do
			local hs = pageState(helper)
			local c = contextFor(hs, false)
			local values = {}
			for _, axis in helper.data.axes or {} do
				values[axis.key] = axis.values[1]
			end
			table.insert(
				children,
				section(`Helper_{helper.id}`, helper.data.alias or helper.id, {
					caption(`{helper.data.purpose} ({helper.data.snippet})`),
					render(helper, c, configure(helper, c, values, {}), "helper"),
				})
			)
		end
		table.insert(children, Content(page))
		return scroller(`Page_{page.id}`, children)
	end

	local function tagged(name: string, tag: string, w: number, h: number): any
		local node = Host.Frame({ Name = name, Size = UDim2.fromOffset(w, h), BorderSizePixel = 0 })
		node:AddTag(tag)
		return node
	end
	local function StylePage(): any
		local surfaces: { any } = { Name = "Surfaces", gap = "m", width = "fill", wrap = true }
		for _, tag in
			{ "surface", "pane", "panel", "control", "field", "button", "badge", "track", "skeleton", "scrim" }
		do
			table.insert(
				surfaces,
				UI.VStack({
					gap = "xs",
					tagged(tag, `facet-{tag}`, 96, 56),
					UI.Text({ text = `facet-{tag}`, textRole = "caption" }),
				})
			)
		end

		local palette = Compose.formula(function(use)
			local package, name = use(ctx.theme), use(ctx.themeMode)
			for _, entry in package.style.themes do
				if entry.name == name then
					return entry
				end
			end
			return package.style.themes[1]
		end)
		local swatches: { any } = { Name = "Palette", gap = "m", width = "fill", wrap = true }
		for _, role in
			{ "surface", "surfaceStrong", "content", "contentStrong", "accent", "danger", "success", "warning" }
		do
			table.insert(
				swatches,
				UI.VStack({
					gap = "xs",
					Host.Frame({
						Name = role,
						Size = UDim2.fromOffset(72, 40),
						BorderSizePixel = 0,
						BackgroundColor3 = function(use)
							local color = use(palette).colors[role]
							return if color then Color3.new(color.r, color.g, color.b) else Color3.new()
						end,
					}),
					UI.Text({ text = role, textRole = "caption" }),
				})
			)
		end
		local ramp: { any } = { Name = "Type", gap = "xs", width = "fill" }
		for _, role in Facet.themes.TYPE_ROLES do
			table.insert(ramp, wrapped({ text = `{role} — The quick brown fox`, textRole = role }))
		end
		local ladder: { any } = { Name = "Ladder", gap = "m", width = "fill", wrap = true }
		for _, size in { "xsmall", "compact", "regular", "large" } do
			for _, appearance in { "standard", "emphasis", "soft", "utility", "link", "inverse" } do
				table.insert(ladder, UI.Button({ label = appearance, appearance = appearance, controlSize = size }))
			end
		end
		local dividers = UI.VStack({
			Name = "Dividers",
			width = 240,
			gap = "s",
			UI.Text({ text = "standard", textRole = "caption" }),
			UI.Divider({}),
			UI.Text({ text = "strong", textRole = "caption" }),
			UI.Divider({ appearance = "strong" }),
		})
		return scroller("Style", {
			Header(
				"Style",
				"Theme token gallery: the public theme tags, the live palette, type roles and the control ladder."
			),
			caption(function(use)
				return `Theme: {use(ctx.themeName)} / {use(ctx.themeMode)}`
			end),
			section("SurfacesSection", "Surface tags", { UI.HStack(surfaces) }),
			section("PaletteSection", "Palette", { UI.HStack(swatches) }),
			section("TypeSection", "Type roles", { UI.VStack(ramp) }),
			section("DividerSection", "Dividers", { dividers }),
			section("LadderSection", "Control ladder × appearance", { UI.HStack(ladder) }),
		})
	end

	local function themeOptions(): { any }
		local out = {}
		local names = {}
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
	local themeChoice = Compose.formula(function(use)
		return `{use(ctx.themeName)}/{use(ctx.themeMode)}`
	end)
	local function setTheme(value: string): any
		local name, palette = string.match(value, "^([^/]+)/?(.*)$")
		local package = ctx.packages[name or ""]
		if package == nil then
			return { ok = false, reason = "unknown theme" }
		end
		app.runtime:batch(function()
			ctx.themeName:set(name)
			ctx.theme:set(package)
			ctx.themeMode:set(if palette ~= nil and palette ~= "" then palette else package.style.defaultTheme)
		end)
		return { ok = true, current = themeChoice:peek() }
	end

	local themeCell = Compose.cell(themeChoice:peek())
	Compose.watch(function(use)
		themeCell:set(use(themeChoice))
	end)

	local function settingPicker(key: string, label: string): any
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
	local function motionPicker(): any
		return dropdown("Setting_motion", "Motion", settings.cells.motion, MOTION_OPTIONS, function(value)
			settings.set("motion", value)
		end)
	end

	local function SettingsPage(): any
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
				caption(
					"A forced input or text size is a preview of Facet's decisions (the controls' environment option); real engine input still arrives and the engine still renders the device text size. For real touch and gamepad use Studio's Device Emulator and Controller Emulator."
				),
			}),
			section("SimulationSection", "Simulated or real", {
				caption(settings.lines),
				UI.Button({
					Name = "ResetAll",
					label = "Reset everything to Automatic",
					onActivate = settings.reset,
				}),
			}),
			section("BuildSection", "Build", {
				caption(`Facet {Facet.VERSION} · {tostring(workspace:GetAttribute("Facet_Build"))}`),
			}),
		})
	end

	local function Detail(): any
		local current = Compose.formula(function(use)
			local top = use(state.top)
			return { { id = if top == "catalog" then use(state.selected) else "@" .. top } }
		end)
		local detail: { any } = { Name = "Detail", width = "fill", height = "fill" }
		table.insert(
			detail,
			UI.VStack({
				Name = "Body",
				width = "fill",
				height = "fill",
				UI.fill(),
				Compose.keyed({
					from = current,
					key = function(item: any): string
						return item.id
					end,
					render = function(item: any)
						local id = item:peek().id
						if id == "@style" then
							return StylePage()
						elseif id == "@settings" then
							return SettingsPage()
						end
						local ok, node = pcall(Page, cat.pages[id])
						if ok then
							return node
						end
						recordError(id, "page", node)
						return caption(`Page failed: {node}`)
					end,
				}),
			})
		)
		return UI.VStack(detail)
	end

	local function matches(page: any, query: string): boolean
		if query == "" then
			return true
		end
		local hay = string.lower(page.title .. " " .. ((page.data and page.data.alias) or ""))
		return string.find(hay, string.lower(query), 1, true) ~= nil
	end

	local function pageRow(
		id: string,
		label: string,
		isSelected: (any) -> boolean,
		pick: () -> (),
		shown: (any) -> boolean
	): any
		return UI.Button({
			Name = id,
			Visible = shown,
			label = label,

			appearance = "utility",
			controlSize = "compact",
			textSize = "body",
			selected = isSelected,
			onActivate = pick,
			Size = function(use)
				local package = use(ctx.theme)
				local dense = math.max(32, package.metrics.targetSizes.pointer or 44)
				return UDim2.new(1, 0, 0, if use(env.interactionClasses).primary == "pointer" then dense else 44)
			end,
			AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	local function Outline(onPick: (() -> ())?): any
		local function group(id: string, label: string, entries: { any }): any
			local function any(use: any): boolean
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
				content = function()
					local rows: { any } = { Name = "Rows", width = "fill" }
					for _, e in entries do
						local row = pageRow(e.id, e.label, e.selected, function()
							e.pick()
							if onPick then
								onPick()
							end
						end, function(use)
							return e.matches(use(state.query))
						end)
						table.insert(rows, row)
					end
					return UI.VStack(rows)
				end,
			})
		end
		local groups: { any } = { Name = "Tree", width = "fill", gap = 0, padding = { bottom = "m" } }
		for _, family in cat.families do
			local entries = {}
			for _, page in family.pages do
				table.insert(entries, {
					id = `P_{page.id}`,
					label = page.title,
					selected = function(use)
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
			table.insert(groups, group(family.id, family.label, entries))
		end
		local labEntries = {}
		for _, entry in { { id = "style", label = "Style" } } do
			table.insert(labEntries, {
				id = `L_{entry.id}`,
				label = entry.label,
				selected = function(use)
					return use(state.top) == entry.id
				end,
				matches = function(q)
					return q == "" or string.find(string.lower(entry.label), string.lower(q), 1, true) ~= nil
				end,
				pick = function()
					state.top:set(entry.id)
				end,
			})
		end
		table.insert(groups, group("lab", "Lab", labEntries))
		return UI.VStack({
			Name = "OutlineList",
			width = "fill",
			height = "fill",
			gap = "s",
			padding = { top = "s", left = "s", right = "s" },
			UI.TextInput({
				Name = "Search",
				value = state.query,
				placeholder = "Search...",
				presentation = "search",
				clearButton = true,
				controlSize = "compact",
				Size = UDim2.fromScale(1, 0),
			}),
			UI.Button({
				Name = "L_settings",
				label = "Settings",
				icon = "settings",
				controlSize = "compact",
				selected = function(use)
					return use(state.top) == "settings"
				end,
				onActivate = function()
					state.top:set("settings")
					if onPick then
						onPick()
					end
				end,
				Size = UDim2.fromScale(1, 0),
			}),
			UI.ScrollView({ Name = "Outline", width = "fill", height = "fill", UI.fill(), UI.VStack(groups) }),
		})
	end

	local function Catalog(): any
		return UI.VStack({
			Name = "Catalog",
			width = "fill",
			height = "fill",
			when(roomy, function()
				local pane = UI.VStack({
					Name = "OutlinePane",
					height = "fill",
					width = function(use)
						return math.clamp(math.floor(use(logical).width * 0.22), 240, 305)
					end,
					Outline(),
				})
				pane:AddTag("facet-pane")

				UI.focusSection(pane)
				return UI.HStack({
					Name = "Split",
					width = "fill",
					height = "fill",
					gap = 0,
					pane,
					UI.Divider({ Name = "PaneDivider", appearance = "strong" }),
					UI.VStack({ Name = "DetailPane", width = "fill", height = "fill", UI.fill(), Detail() }),
				})
			end),
			when(compact, function()
				local function open()
					state.compactPath:set({ { id = "page" } })
				end
				return UI.NavigationStack({
					Name = "Browse",
					path = state.compactPath,
					backLabel = "Controls",
					Size = UDim2.fromScale(1, 1),
					root = {
						title = "Controls",
						content = function()
							local outline = Outline(open)

							UI.focusSection(outline, { focusOnAppear = `P_{state.selected:peek()}` })
							return outline
						end,
					},
					destinations = {
						page = {
							title = function(use)
								local top = use(state.top)
								if top ~= "catalog" then
									return if top == "settings" then "Settings" else "Style"
								end
								local page = cat.pages[use(state.selected)]
								return if page then page.title else ""
							end,
							content = function()
								return UI.VStack({ Name = "Current", width = "fill", height = "fill", Detail() })
							end,
						},
					},
				})
			end),
		})
	end

	app.mount(function()
		local roomSize = Compose.cell(nil :: Vector2?)
		local device = Compose.formula(function(use)
			local size = use(roomSize) or use(env.viewportSize)
			return settings.device(use, { width = math.max(size.X, 320), height = math.max(size.Y, 240) })
		end)
		Compose.watch(function(use)
			local size = use(device).logical
			logical:set(size)
			settings.viewport:set(Vector2.new(size.width, size.height))
		end)
		local frame = UI.VStack({
			Name = "Device",
			Size = function(use)
				local d = use(device)
				return if d.simulated
					then UDim2.fromOffset(d.logical.width, d.logical.height)
					else UDim2.fromScale(1 / d.scale, 1 / d.scale)
			end,
			AutomaticSize = Enum.AutomaticSize.None,
			ClipsDescendants = true,

			padding = function(use)
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
				Transparency = function(use)
					return if use(device).simulated then 0.4 else 1
				end,
			}),
			Host.UIScale({
				Name = "Preview",
				Scale = function(use)
					return use(device).scale
				end,
			}),
			Catalog(),
		})
		frame:AddTag("facet-surface")
		local stage = UI.ZStack({
			Name = "Stage",
			width = "fill",
			height = "fill",
			alignH = "center",
			alignV = "center",
			frame,
		})
		local room = UI.environment(stage)
		Compose.watch(function(use)
			roomSize:set(use(room.viewportSize))
		end)
		return stage
	end)

	return {
		state = state,
		settings = settings,
		setTheme = setTheme,
		themes = function(): any
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
		open = function(id: string): any
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
		section = function(name: string): any
			local page = cat.pages[state.selected:peek()]
			local data = page.data or {}
			local exists = name == "overview" or (name == "examples" and data.scenarios ~= nil)
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
			local axes, states = data.axes or {}, data.states or {}
			local choices = {}
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
			local function try(list: { any })
				local values, active = {}, {}
				for _, axis in axes do
					values[axis.key] = axis.values[1]
				end
				for _, choice in list do
					if choice.axis then
						values[choice.axis] = choice.value
					else
						table.insert(active, choice.state)
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

		configure = function(command: string): any
			local page = cat.pages[state.selected:peek()]
			local ps = pageState(page)
			local name, json = string.match(command, "^value:([^=]+)=(.*)$")
			if name then
				local cell = ps.values[name]
				if cell == nil then
					return { ok = false, reason = "no such value" }
				end
				cell:set(game:GetService("HttpService"):JSONDecode(json))
				return { ok = true }
			end
			local sign, flag = string.match(command, "^([%+%-])(.+)$")
			if sign and ps.flags[flag] then
				ps.flags[flag]:set(sign == "+")
				return { ok = true }
			end
			local key, value = string.match(command, "^([^=]+)=(.*)$")
			if key and ps.axis[key] then
				for _, axis in page.data.axes or {} do
					for _, v in if axis.key == key then axis.values else {} do
						if tostring(v) == value then
							ps.axis[key]:set(v)
							return { ok = true }
						end
					end
				end
				ps.axis[key]:set(value)
				return { ok = true }
			end
			return { ok = false, reason = "unknown command" }
		end,
		report = function(): any
			local page = cat.pages[state.selected:peek()]
			local ps = pageState(page)
			local config, values = {}, {}
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
				errors = state.errors[page.id] or {},
				totalErrors = total,
				missing = cat.missing,
				log = ps.log:peek(),
				logical = logical:peek(),
			}
		end,
	}
end

return browser
