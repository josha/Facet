--!strict
local Types = require("./types")
local Content = require("./content_types")
local Inputs = require("./input_types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local values = require("./content_values")
local reducedMotion = require("./motion")

type Snapshot = { steps: { Content.Step }, current: string?, index: { [string]: number } }

local STATES: { [string]: string } =
	{ complete = "Complete", current = "Current", upcoming = "Upcoming", error = "Error" }
local STEP_KEYS: { [string]: boolean } =
	{ id = true, label = true, description = true, state = true, navigable = true, enabled = true }

return function(
	ctx: Types.Context,
	UI: {
		StepIndicator: Types.Constructor<Content.StepIndicatorSpec, Frame>,
		Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
		Menu: Nav.MenuConstructor,
	}
): ()
	local Host, Compose, read, runtime = ctx.Host, ctx.Compose, ctx.read, ctx.runtime
	local E, D2, V2, D = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2, ctx.types.UDim

	local function problem(steps: unknown, current: unknown): string?
		if type(steps) ~= "table" then
			return "steps must be an array of steps"
		end
		if current ~= nil and type(current) ~= "string" then
			return "current must be a step id or nil"
		end
		local seen: { [string]: boolean } = {}
		for index, step in steps :: { unknown } do
			if type(step) ~= "table" then
				return `step {index} must be a table`
			end
			local entry = step :: { [string]: unknown }
			for key in entry do
				if type(key) ~= "string" or not STEP_KEYS[key] then
					return `step {index} has the unknown field '{tostring(key)}'`
				end
			end
			if type(entry.id) ~= "string" or entry.id == "" then
				return `step {index} needs a nonempty string id`
			end
			if seen[entry.id :: string] then
				return `two steps share the id '{entry.id}'`
			end
			seen[entry.id :: string] = true
			if type(entry.label) ~= "string" or string.find(entry.label :: string, "%S") == nil then
				return `step '{entry.id}' needs a nonempty label`
			end
			if entry.description ~= nil and type(entry.description) ~= "string" then
				return `step '{entry.id}' description must be a string`
			end
			if entry.state ~= nil and STATES[entry.state :: string] == nil then
				return `step '{entry.id}' state must be complete, current, upcoming or error`
			end
			if entry.state == "current" and entry.id ~= current then
				return `step '{entry.id}' is marked current, but current names '{tostring(current)}'`
			end
			for _, flag in { "navigable", "enabled" } do
				if entry[flag] ~= nil and type(entry[flag]) ~= "boolean" then
					return `step '{entry.id}' {flag} must be a boolean`
				end
			end
		end
		return nil
	end

	UI.StepIndicator = ctx.construct("StepIndicator", function(spec: Content.StepIndicatorSpec): Frame
		local initialSteps, initialCurrent = read(spec.steps), read(spec.current)
		local refusal = problem(initialSteps, initialCurrent)
		if refusal then
			error(`Facet UI.StepIndicator: {refusal}`, 0)
		end
		assert(
			spec.sizing == nil or spec.sizing == "fill" or spec.sizing == "hug",
			"Facet UI.StepIndicator: sizing is fill or hug"
		)
		assert(
			spec.onSelect == nil or type(spec.onSelect) == "function",
			"Facet UI.StepIndicator: onSelect must be a function"
		)
		assert(
			spec.listLabel == nil or type(spec.listLabel) == "string",
			"Facet UI.StepIndicator: listLabel must be a string"
		)
		local sizing = spec.sizing or "fill"
		local onSelect = spec.onSelect
		local checks = values(ctx, "StepIndicator")
		if spec.controls then
			spec.controls.diagnostics = checks.list
		end
		local last: Snapshot
		local function snapshot(steps: { Content.Step }, current: string?): Snapshot
			local index: { [string]: number } = {}
			for position, step in steps do
				index[step.id] = position
			end
			return { steps = steps, current = if current and index[current] then current else nil, index = index }
		end
		last = snapshot(initialSteps, initialCurrent)
		local refused = false
		local model = Compose.formula(function(use: ComposeTypes.Use): Snapshot
			local steps, current = read(spec.steps, use), read(spec.current, use)
			local reason = problem(steps, current)
			if reason == nil then
				last, refused = snapshot(steps, current), false
			elseif not refused then
				refused = true
				checks.note(`Facet UI.StepIndicator: {reason}; the last legal snapshot stays`)
			end
			return last
		end)
		local enabled = function(use: ComposeTypes.Use?): boolean
			return read(spec.enabled, use) ~= false
		end
		local function permitted(step: Content.Step): boolean
			return onSelect ~= nil and step.navigable == true and step.enabled ~= false
		end
		local function stateOf(step: Content.Step, current: string?): string
			return step.state or (if step.id == current then "current" else "upcoming")
		end
		local summary = Compose.formula(function(use: ComposeTypes.Use): string
			local m = use(model)
			if #m.steps == 0 then
				return "No steps"
			end
			if m.current == nil then
				return "No current step"
			end
			local position = m.index[m.current]
			return `Step {position} of {#m.steps} — {m.steps[position].label}`
		end)
		local function propose(id: string)
			local m = model:peek()
			local position = m.index[id]
			if onSelect == nil or not enabled() or position == nil or id == m.current then
				return
			end
			if permitted(m.steps[position]) then
				onSelect(id)
			end
		end
		local stepById = function(id: string, use: ComposeTypes.Use?): Content.Step?
			local m = read(model, use)
			local position = m.index[id]
			return if position then m.steps[position] else nil
		end
		local cueSize = function(use: ComposeTypes.Use?): number
			return (ctx.controlSize(spec.controlSize, "iconSize", use))
		end
		local measures = Compose.cell({} :: { [string]: ComposeTypes.Readable<Vector2> })
		local cells: { [string]: GuiObject } = {}
		local cellMeasures = Compose.cell({} :: { [string]: { ComposeTypes.Readable<Vector2> } })
		local function content(id: string): { Types.Child }
			local numberLabel = ctx.text({
				Name = "Number",
				Text = function(use: ComposeTypes.Use): string
					return tostring(read(model, use).index[id] or "")
				end,
				AnchorPoint = V2.new(0.5, 0.5),
				Position = D2.fromScale(0.5, 0.5),
			})
			local numberBounds = ctx.observe(numberLabel, "TextBounds")
			local numberSize = ctx.observeStyled(numberLabel, "TextSize")
			local numberExtent = ctx.observe(numberLabel, "AbsoluteSize")
			local cue = Host.Frame({
				Name = "Cue",
				LayoutOrder = 1,
				BackgroundTransparency = 1,
				Size = function(use: ComposeTypes.Use)
					use(numberBounds)
					use(numberSize)
					use(numberExtent)
					local bounds = numberLabel.TextBounds
					local line = tonumber(numberLabel:GetStyled("TextSize")) or 0
					local side = math.max(cueSize(use), math.ceil(math.max(bounds.X, bounds.Y, line)) + 8)
					return D2.fromOffset(side, side)
				end,
				Host.UIAspectRatioConstraint({ AspectRatio = 1 }) :: Types.Child,
				ctx.styled(
					Host.Frame({
						Name = "Circle",
						BackgroundTransparency = 1,
						Size = D2.fromScale(1, 1),
						Visible = function(use: ComposeTypes.Use): boolean
							local step = stepById(id, use)
							local state = if step then stateOf(step, read(model, use).current) else "upcoming"
							return state ~= "complete" and state ~= "error"
						end,
						Host.UICorner({ CornerRadius = D.new(1, 0) }) :: Types.Child,
						Host.UIStroke({ ApplyStrokeMode = E.ApplyStrokeMode.Border }) :: Types.Child,
						numberLabel :: Types.Child,
					}),
					"step-circle"
				) :: Types.Child,
				ctx.icon("checkmark", {
					Name = "Check",
					Size = D2.fromScale(1, 1),
					Visible = function(use: ComposeTypes.Use): boolean
						local step = stepById(id, use)
						return step ~= nil and stateOf(step, read(model, use).current) == "complete"
					end,
				}) :: Types.Child,
				ctx.icon("status.error", {
					Name = "Error",
					Size = D2.fromScale(1, 1),
					Visible = function(use: ComposeTypes.Use): boolean
						local step = stepById(id, use)
						return step ~= nil and stateOf(step, read(model, use).current) == "error"
					end,
				}) :: Types.Child,
			})
			local label = ctx.text({
				Name = "Label",
				LayoutOrder = 1,
				Text = function(use: ComposeTypes.Use): string
					local step = stepById(id, use)
					return if step then step.label else ""
				end,
				TextTruncate = E.TextTruncate.AtEnd,
			})
			local state = ctx.text({
				Name = "State",
				LayoutOrder = 2,
				Text = function(use: ComposeTypes.Use): string
					local step = stepById(id, use)
					return if step then STATES[stateOf(step, read(model, use).current)] else ""
				end,
			})
			state:AddTag("facet-type-caption")
			state:AddTag("facet-secondary")
			local description = ctx.text({
				Name = "Description",
				LayoutOrder = 3,
				Text = function(use: ComposeTypes.Use): string
					local step = stepById(id, use)
					return if step then step.description or "" else ""
				end,
				Visible = function(use: ComposeTypes.Use): boolean
					local step = stepById(id, use)
					return step ~= nil and step.description ~= nil
				end,
			})
			description:AddTag("facet-type-caption")
			description:AddTag("facet-secondary")
			local copy = ctx.column({ label, state, description }, { Name = "Copy", LayoutOrder = 2 })
			local measure = ctx.text({
				Name = "Measure",
				Visible = false,
				Text = function(use: ComposeTypes.Use): string
					local step = stepById(id, use)
					return if step then step.label else ""
				end,
			})
			local measured = ctx.observe(measure, "TextBounds")
			local next = table.clone(measures:peek())
			next[id] = measured
			measures:set(next)
			Compose.cleanup(function()
				local remaining = table.clone(measures:peek())
				remaining[id] = nil
				measures:set(remaining)
			end)
			return {
				Host.UIListLayout({
					FillDirection = E.FillDirection.Horizontal,
					SortOrder = E.SortOrder.LayoutOrder,
					VerticalAlignment = E.VerticalAlignment.Top,
					Padding = function(use: ComposeTypes.Use)
						return D.new(0, ctx.metric("space.s", use))
					end,
				}) :: Types.Child,
				cue :: Types.Child,
				copy :: Types.Child,
				measure :: Types.Child,
			}
		end
		local rowItems = Compose.keyed({
			from = function(use: ComposeTypes.Use): { Content.Step }
				return use(model).steps
			end,
			key = function(step: Content.Step): string
				return step.id .. (if permitted(step) then ":button" else ":plain")
			end,
			render = function(source: ComposeTypes.Readable<Content.Step>, index: ComposeTypes.Readable<number>)
				local step = source:peek()
				local id = step.id
				local node: GuiObject
				local layout = {
					Name = `Step-{id}`,
					LayoutOrder = index,
					Size = D2.fromScale(0, 0),
					AutomaticSize = E.AutomaticSize.XY,
				}
				if permitted(step) then
					local props: Inputs.ButtonProps = {
						Name = layout.Name,
						LayoutOrder = layout.LayoutOrder,
						Size = layout.Size,
						AutomaticSize = layout.AutomaticSize,
						label = "",
						name = function(use: ComposeTypes.Use): string
							local live = stepById(id, use)
							return if live then live.label else id
						end,
						enabled = enabled,
						selected = false,
						onActivate = function()
							propose(id)
						end,
					}
					for _, child in content(id) do
						table.insert(props, child)
					end
					local button = UI.Button(props)
					node = button
				else
					local props: Types.FrameNativeProps = {
						Name = layout.Name,
						LayoutOrder = layout.LayoutOrder,
						Size = layout.Size,
						AutomaticSize = layout.AutomaticSize,
						BackgroundTransparency = 1,
						Attributes = {
							label = function(use: ComposeTypes.Use): string
								local live = stepById(id, use)
								return if live then live.label else id
							end,
						} :: Types.Attributes,
					}
					for _, child in content(id) do
						table.insert(props, child)
					end
					node = Host.Frame(props)
					Compose.watch(function(use: ComposeTypes.Use)
						local live = stepById(id, use)
						if live and live.enabled == false or not enabled(use) then
							node:AddTag("facet-disabled")
						elseif node:HasTag("facet-disabled") then
							node:RemoveTag("facet-disabled")
						end
					end)
				end
				cells[id] = node
				local next = table.clone(cellMeasures:peek())
				next[id] = { ctx.observe(node, "AbsolutePosition"), ctx.observe(node, "AbsoluteSize") }
				cellMeasures:set(next)
				Compose.cleanup(function()
					if cells[id] == node then
						cells[id] = nil
					end
					local remaining = table.clone(cellMeasures:peek())
					remaining[id] = nil
					cellMeasures:set(remaining)
				end)
				return node
			end,
		})
		local stripX = Compose.cell(0)
		local reduced = reducedMotion(ctx)
		local target = Compose.formula(function(use: ComposeTypes.Use): { x: number, width: number, shown: boolean }
			local m = use(model)
			local measured = if m.current then use(cellMeasures)[m.current] else nil
			if measured == nil then
				return { x = 0, width = 0, shown = false }
			end
			local at, size = use(measured[1]), use(measured[2])
			return { x = at.X - use(stripX), width = size.X, shown = true }
		end)
		local springX = runtime.spring(function(use: ComposeTypes.Use)
			return use(target).x
		end, { period = 0.25, damping = 1 })
		local springWidth = runtime.spring(function(use: ComposeTypes.Use)
			return use(target).width
		end, { period = 0.25, damping = 1 })
		local row = Host.Frame({
			Name = "Row",
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 0),
			AutomaticSize = E.AutomaticSize.Y,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				SortOrder = E.SortOrder.LayoutOrder,
				VerticalAlignment = E.VerticalAlignment.Top,
				ItemLineAlignment = E.ItemLineAlignment.Stretch,
				HorizontalFlex = if sizing == "fill" then E.UIFlexAlignment.Fill else E.UIFlexAlignment.None,
				Padding = function(use: ComposeTypes.Use)
					return D.new(0, ctx.metric("space.m", use))
				end,
			}) :: Types.Child,
			rowItems,
		})
		local underline = ctx.styled(
			Host.Frame({
				Name = "Underline",
				BorderSizePixel = 0,
				AnchorPoint = V2.new(0, 1),
				ZIndex = 2,
				Visible = function(use: ComposeTypes.Use): boolean
					return use(target).shown
				end,
				Position = function(use: ComposeTypes.Use)
					local x = if reduced(use) then use(target).x else use(springX)
					return D2.new(0, x, 1, 0)
				end,
				Size = function(use: ComposeTypes.Use)
					local width = if reduced(use) then use(target).width else use(springWidth)
					return D2.fromOffset(width, 2)
				end,
			}),
			"selection-indicator"
		)
		local strip = Host.Frame({
			Name = "Strip",
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 0),
			AutomaticSize = E.AutomaticSize.Y,
			row :: Types.Child,
			underline :: Types.Child,
		})
		local stripPosition = ctx.observe(strip, "AbsolutePosition")
		Compose.watch(function(use: ComposeTypes.Use)
			stripX:set(use(stripPosition).X)
		end)
		local root: Frame
		local offered = Compose.cell(0)
		local form = Compose.formula(function(use: ComposeTypes.Use): "row" | "summary"
			local m = use(model)
			local width = use(offered)
			if #m.steps == 0 or width <= 0 then
				return "row"
			end
			local gap, inner = ctx.metric("space.m", use), ctx.metric("space.s", use)
			local all = use(measures)
			local widest, total = 0, 0
			for _, step in m.steps do
				local measure = all[step.id]
				local labelWidth = if measure then use(measure).X else 0
				local cell = cueSize(use) + inner + labelWidth
				widest = math.max(widest, cell)
				total += cell
			end
			local need = (if sizing == "fill" then widest * #m.steps else total) + gap * (#m.steps - 1)
			return if need <= width then "row" else "summary"
		end)
		local listOpen = Compose.cell(false)
		Compose.watch(function(use: ComposeTypes.Use)
			use(model)
			if listOpen:peek() then
				listOpen:set(false)
			end
		end)
		local compact = ctx.row({
			ctx.text({ Name = "Summary", Text = summary, TextTruncate = E.TextTruncate.AtEnd }),
			Compose.show(function(use: ComposeTypes.Use): boolean
				return #use(model).steps > 0
			end, function()
				return UI.Menu({
					Name = "ShowSteps",
					label = spec.listLabel or "Steps",
					isPresented = listOpen,
					enabled = enabled,
					items = function(use: ComposeTypes.Use): { Nav.MenuItem<string> }
						local items: { Nav.MenuItem<string> } = {}
						local m = use(model)
						for _, step in m.steps do
							local id = step.id
							table.insert(items, {
								id = `Item-{id}`,
								label = step.label,
								description = STATES[stateOf(step, m.current)],
								marked = id == m.current,
								enabled = permitted(step),
								dismiss = false,
								onSelect = function()
									propose(id)
								end,
							})
						end
						return items
					end,
				})
			end),
		}, { Name = "SummaryRow" })
		root = Host.Frame(ctx.props(spec, {
			"steps",
			"current",
			"onSelect",
			"sizing",
			"listLabel",
			"controlSize",
			"enabled",
			"controls",
		}, {
			Name = "StepIndicator",
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 0),
			AutomaticSize = E.AutomaticSize.Y,
			Attributes = {
				FacetCurrent = checks.attribute(function(use: ComposeTypes.Use)
					return use(model).current
				end),
				FacetSummary = checks.attribute(summary),
				FacetForm = checks.attribute(form),
				FacetListOpen = checks.attribute(listOpen),
			} :: Types.Attributes,
			strip :: Types.Child,
			compact :: Types.Child,
		}))
		runtime.decorate(strip, {
			Visible = function(use: ComposeTypes.Use): boolean
				return use(form) == "row"
			end,
		})
		runtime.decorate(compact, {
			Visible = function(use: ComposeTypes.Use): boolean
				return use(form) == "summary"
			end,
		})
		local size = ctx.observe(root, "AbsoluteSize")
		Compose.watch(function(use: ComposeTypes.Use)
			offered:set(use(size).X)
		end)
		return root
	end)
end
