--!strict
-- PROBE-EXEMPT: this whole file is the ENGINE-SIDE materializer — INSTRUMENT,
-- NOT EXAMPLE. It is the corpus's only concentration of direct `Instance.new`
-- and raw geometry writes, and that is its SUBJECT: `foreign_content.luau` is
-- the scenario a reader copies, and it declares these panes as data.
--
-- THE FOREIGN-CONTENT MATERIALIZER (UI.Foreign, ADR-0034).
--
-- An ENGINE-SIDE sibling of `runner.luau`, deliberately NOT a scenario: scenario
-- modules are engine-free by contract, so a fixture that wants instances inside a
-- `UI.Foreign` box declares them as DATA (`built.foreignContent = { [nodePath] =
-- { kind, … } }`) and this module is the one place that turns a `kind` into an
-- Instance.
--
-- IT LIVES HERE, IN ITS OWN FILE, RATHER THAN INSIDE `runner.luau`, FOR A REASON
-- THE RUNNER ITSELF RECORDS. `init.client.luau`'s fixture branch once dropped a
-- fixture's `present` opts because only the test rigs passed them — "the test rigs
-- were more correct than the shipped host, which is the failure mode
-- docs/lessons/the-solver-already-told-you.md is named after" (C2, 2026-08-12).
-- `foreignContent` is exactly the same shape of fact, so both hosts materialize it
-- through ONE function instead of the scenario runner having a capability the
-- showcase a player actually opens does not.
--
-- EVERY `kind` IS SOMETHING FACET CANNOT EXPRESS. That is not decoration: a demo
-- of an escape hatch whose panes the framework could have drawn demonstrates
-- nothing. See `foreign_content.luau`'s header for what each one proves.

local foreign_instances = {}

--[[ THE SEAM'S OWN TYPE CONTRACT, and it exists because the suite could not see
	the one defect on the other side of it (review 2026-08-22, MED-2).

	`foreign_content.luau` hands these descriptors ACROSS the seam and this module
	writes their fields straight onto engine properties. An engine property takes an
	engine type: `TextLabel.TextSize` takes a NUMBER. The declarative-purity sweep
	briefly turned that field into `"control"` — the theme role name the lint asks
	for everywhere else — and NOTHING caught it: the whole suite passed (this path
	needs a live engine to run) and the lint passed too (a name is exactly what it
	demands). Only reading the diff did.

	So the refusal ladder this module's header describes now covers a wrong-typed
	FIELD as well as an unknown KIND. It is checked HERE, in the module that owns
	the write, because that is the only place that knows which property each field
	becomes — and `tests/foreign.spec.luau` drives it from the shipped descriptors,
	so the pin is on the real content rather than on a fixture's copy of it. ]]
foreign_instances.CONTENT_SCHEMA = {
	richText = { text = "string", textSize = "number?" },
	engineList = { items = "table" },
	oversize = {},
}

-- validate(content) -> nil | reason. `nil` is "this crosses the seam cleanly".
function foreign_instances.validate(content: any): string?
	if type(content) ~= "table" then
		return `foreign content must be a table, got {type(content)}`
	end
	local fields = (foreign_instances.CONTENT_SCHEMA :: any)[content.kind]
	if fields == nil then
		return `unknown foreign content kind '{tostring(content.kind)}'`
	end
	for field, expected in fields do
		local optional = string.sub(expected, -1) == "?"
		local want = if optional then string.sub(expected, 1, -2) else expected
		local got = type(content[field])
		if got == "nil" then
			if not optional then
				return `foreign '{content.kind}' is missing required field '{field}' ({want})`
			end
		elseif got ~= want then
			return `foreign '{content.kind}' field '{field}' must be a {want} — it is written straight `
				.. `onto an ENGINE property, which takes no theme name — got {got} ({tostring(content[field])})`
		end
	end
	return nil
end

-- build(content) -> Instance. Errors on an unknown kind, and on a field whose type
-- the engine property cannot take, rather than answering nil: a silently empty
-- pane is the accepted-and-ignored failure this whole feature's refusal ladder
-- exists to remove.
function foreign_instances.build(content: any): Instance
	local refusal = foreign_instances.validate(content)
	if refusal ~= nil then
		error(`foreign_instances.build: {refusal}`, 2)
	end
	if content.kind == "richText" then
		-- RICH TEXT: markup spans inside ONE string. `UI.Text` resolves ONE
		-- typography role and ONE colour for the whole label — by design, because
		-- the solver measures with one font descriptor — so bold + italic + two
		-- colours on one line is not expressible in Facet at all.
		local label = Instance.new("TextLabel")
		label.RichText = true
		label.Text = content.text
		label.TextSize = content.textSize or 18
		label.Font = Enum.Font.GothamMedium
		label.TextColor3 = Color3.fromRGB(236, 238, 243)
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		return label
	elseif content.kind == "engineList" then
		-- ENGINE-MEASURED LAYOUT: a UIListLayout with AutomaticCanvasSize over rows
		-- carrying AutomaticSize, i.e. the engine deciding extents from its own
		-- children. Facet pins `AutomaticCanvasSize = None` on every ScrollingFrame
		-- it creates (the solver owns content geometry), so this is precisely the
		-- measure model the framework refuses — running inside a box it declared.
		local scroller = Instance.new("ScrollingFrame")
		scroller.Size = UDim2.fromScale(1, 1)
		scroller.BackgroundTransparency = 1
		scroller.BorderSizePixel = 0
		scroller.CanvasSize = UDim2.new()
		scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroller.ScrollBarThickness = 4
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = scroller
		for index, item in content.items :: { string } do
			local row = Instance.new("TextLabel")
			row.LayoutOrder = index
			row.Text = item
			row.TextSize = 15
			row.Font = Enum.Font.Gotham
			row.TextColor3 = Color3.fromRGB(214, 219, 230)
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.BackgroundTransparency = 1
			-- AutomaticSize: the property the solver cannot see. Each row sizes
			-- ITSELF from its text and the list re-flows around it.
			row.Size = UDim2.new(1, -8, 0, 0)
			row.AutomaticSize = Enum.AutomaticSize.Y
			row.TextWrapped = true
			row.Parent = scroller
		end
		return scroller
	elseif content.kind == "oversize" then
		-- THE CLIP, PROVED: twice the box on both axes, offset negatively so the
		-- crop shows on every edge. Without the container's `ClipsDescendants` this
		-- would paint over the panes beside it.
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(2, 2)
		frame.Position = UDim2.fromOffset(-24, -24)
		frame.BackgroundColor3 = Color3.fromRGB(196, 92, 64)
		frame.BorderSizePixel = 0
		--[[ 0.02 AND NOT 0, AND THE REASON IS A LIVE MEASUREMENT (Studio, 2026-08-15).
			A native-mode Facet surface links a theme StyleSheet at its root, and that
			sheet's class-default rules select `Frame` among six others — including
			`BackgroundTransparency = 1`. A StyleRule loses to an EXPLICIT write, but
			the engine decides "explicit" by VALUE, not by assignment: this frame is
			born at 0, which IS the Frame class default, so writing 0 changes nothing
			the engine can see and the rule keeps winning. Measured on the adopted
			instance: raw = 0, `GetStyled("BackgroundTransparency")` = 1, and the pane
			rendered EMPTY. Writing 0.5 gave styled = 0.5; writing 0 again went back to
			styled = 1. So a class-default value cannot be held against a rule at all.

			0.02 is visually opaque and not the default, so it sticks. This is the
			general rule for ANY adopted GuiObject of a class Facet itself renders,
			and api.md's `Foreign` section states it. ]]
		frame.BackgroundTransparency = 0.02
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 28)
		corner.Parent = frame
		return frame
	elseif content.kind == "part" then
		-- THE REFUSAL, LIVE: the 3-D case arriving at the 2-D seam.
		return Instance.new("Part")
	end
	error(`foreign_instances: unknown kind '{tostring(content.kind)}'`, 0)
end

-- adopt(controller, nodePath, content) -> status string. NEVER throws: the status
-- goes on screen, so a refusal is visible in the experience rather than only in
-- the output window.
function foreign_instances.adopt(controller: any, nodePath: string, content: any): string
	local host = if controller ~= nil and controller.foreignHost ~= nil then controller.foreignHost(nodePath) else nil
	if host == nil then
		return "no host (this adapter has no foreign seam; the box still paints its plate)"
	end
	local madeOk, made = pcall(foreign_instances.build, content)
	if not madeOk then
		return tostring(made)
	end
	local ok, err = pcall(function()
		host.adopt(made)
	end)
	if not ok then
		-- the caller owns the instance, so the caller cleans it up: Facet never
		-- took it and never will
		(made :: Instance):Destroy()
		return `REFUSED — {tostring(err)}`
	end
	return `adopted a {(made :: Instance).ClassName}`
end

-- applyAll(controller, foreignContent) -> { [nodePath]: status }
function foreign_instances.applyAll(controller: any, foreignContent: { [string]: any }): { [string]: string }
	local applied: { [string]: string } = {}
	for nodePath, content in foreignContent do
		applied[nodePath] = foreign_instances.adopt(controller, nodePath, content)
	end
	return applied
end

return foreign_instances
