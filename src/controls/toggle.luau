--!strict
-- Setting rows retain their real indicator and one activation/focus owner.
local Compose = require("../vendor/compose/core")
local guard = require("../spec_guard")
local contract = require("../class_contract")
local chrome = require("../tokens/chrome_slots")
local selection = require("../selection_model")
local read = selection.read
local themePackage = require("../themes/package")
local contribution = require("../input/contribution")
local schema = require("../blueprint_schema")
local menuRecipe = require("./menu_recipe")
local vocabulary = require("./control_vocabulary")

local toggle = {}

local KEYS = guard.keySet({
	"id",
	"label",
	"value",
	"mixed",
	"presentation",
	"enabled",
	"onChange",
	"children",
	"row",
	"hint",
	"indicatorPosition",
	"controlSize",
	"width",
})

local DISPLAY_ONLY_META = table.freeze({ displayOnly = true })

local POSITIONS = { "leading", "trailing" }
local POSITION_SET = guard.keySet(POSITIONS)

local DEFAULT_HEIGHT = table.freeze({ type = "minMax", min = "targetSizes.minimum" })
local INDICATOR_BOX = table.freeze({ type = "minMax", min = "l" })

local function build(Facet: any, core: any, spec: any, owner: any)
	guard.assertKnownKeys("UI.Toggle", spec, KEYS, "spec")
	assert(spec.row == nil or spec.children == nil, "Toggle.row cannot combine with children")
	local presentation = spec.presentation or "switch"
	assert(
		presentation == "switch" or presentation == "checkbox" or presentation == "button",
		"UI.Toggle: presentation must be switch | checkbox | button"
	)
	assert(
		selection.isSource(spec.value) and type(read(spec.value)) == "boolean",
		"UI.Toggle: value must be a boolean Compose readable or function(use)"
	)
	assert(
		spec.mixed == nil
			or (presentation == "checkbox" and selection.isSource(spec.mixed) and type(read(spec.mixed)) == "boolean"),
		"UI.Toggle: mixed must be a boolean Compose readable or function(use) on a checkbox"
	)
	assert(spec.children == nil or presentation == "button", "UI.Toggle: children require the button presentation")
	assert(spec.onChange == nil or type(spec.onChange) == "function", "UI.Toggle: onChange must be a function")
	assert(
		spec.onChange ~= nil
			or (selection.isWritable(spec.value) and (spec.mixed == nil or selection.isWritable(spec.mixed))),
		"UI.Toggle: readonly value or mixed requires onChange"
	)
	assert(
		spec.hint == nil or spec.row == nil,
		"UI.Toggle: `hint` and `row.description` are the same line — a row states its hint as "
			.. "`row = { description = ... }`"
	)
	assert(
		spec.indicatorPosition == nil or presentation ~= "button",
		"UI.Toggle: the button presentation has no indicator to place — it IS the indicator (the plate "
			.. "stays pressed). `indicatorPosition` belongs to a switch or a checkbox."
	)
	assert(
		spec.indicatorPosition == nil or POSITION_SET[spec.indicatorPosition],
		`UI.Toggle: \`indicatorPosition\` must be {table.concat(POSITIONS, " | ")} `
			.. `(got '{tostring(spec.indicatorPosition)}')`
	)
	vocabulary.assertSize("UI.Toggle", spec.controlSize)
	local UI = Facet.UI
	local width = if spec.width ~= nil
		then Compose.formula(function(use)
			local value = read(spec.width, use)
			if value ~= nil then
				local ok, why = schema.checkValue(assert(schema.forClass("Box")).props.width, value)
				assert(ok, "UI.Toggle: width must be a valid dimension: " .. tostring(why))
				local content = value.type == "hug" or value.type == "content" or value.type == "minMax"
				assert(
					not (content and (spec.row ~= nil or presentation == "button")),
					"UI.Toggle: content-sized width is unsupported on row and button forms; use fixed or fill"
				)
			end
			return value
		end)
		else nil
	if width then
		width:peek()
	end
	local function contentWidth(use)
		local value = if width then use(width) else nil
		return if value and (value.type == "hug" or value.type == "content" or value.type == "minMax")
			then UI.hug()
			else UI.fill()
	end
	local function rowWidth(use)
		return (if width then use(width) else nil) or UI.fill()
	end

	local disposed = false
	Compose.cleanup(function()
		disposed = true
	end)
	local function activate()
		if disposed or not contract.enabledNow(spec.enabled) then
			return
		end
		core.reactor:batch(function()
			local nextValue = if spec.mixed and read(spec.mixed) then true else not read(spec.value)
			if spec.onChange then
				-- The model accepts by writing its source; a request never writes first.
				spec.onChange(nextValue)
			else
				if spec.mixed then
					spec.mixed:set(false)
				end
				spec.value:set(nextValue)
			end
		end)
	end
	local selected = Compose.formula(function(use)
		return selection.read(spec.value, use) or (spec.mixed ~= nil and selection.read(spec.mixed, use))
	end)

	local sizedHeight = vocabulary.deriveSize("UI.Toggle", spec.controlSize, function(rung)
		return vocabulary.heightFor(rung) or DEFAULT_HEIGHT
	end)

	local wantsLadderPadding = spec.row ~= nil or presentation ~= "switch" or spec.hint ~= nil
	local sizedPadding = if wantsLadderPadding
		then vocabulary.deriveSize("UI.Toggle", spec.controlSize, vocabulary.paddingFor)
		else nil
	local props: any = {
		id = spec.id or "Toggle",
		label = spec.label or "",
		enabled = spec.enabled,
		height = sizedHeight or { type = "minMax", min = "targetSizes.minimum" },
		padding = sizedPadding,
		onActivate = activate,
	}
	local side = spec.indicatorPosition or (if presentation == "checkbox" then "leading" else "trailing")

	local function checkboxMark(): any
		local marks = {}
		local choices: { { any } } = {
			{
				"Check",
				"checkmark",
				function(use)
					return selection.read(spec.value, use) and not (spec.mixed and selection.read(spec.mixed, use))
				end,
			},
			{
				"Mixed",
				"decrement",
				function(use)
					return spec.mixed ~= nil and selection.read(spec.mixed, use)
				end,
			},
		}
		for _, item in choices do
			table.insert(
				marks,
				chrome.attachHint(
					UI.Text({
						id = item[1],
						text = themePackage.iconGlyph(item[2]) or (if item[1] == "Check" then "x" else "-"),
						textSize = "control",
						hidden = Compose.formula(function(use)
							return not item[3](use)
						end),
					}),
					{ icon = item[2], selectionMark = true }
				)
			)
		end
		-- the checked fill: invisible unless the theme authors a selection ink
		table.insert(
			marks,
			1,
			chrome.attachHint(
				UI.corners(
					UI.Box({
						id = "Fill",
						width = { type = "fill" },
						height = { type = "fill" },
						hidden = Compose.formula(function(use)
							return not use(selected)
						end),
					}),
					"control"
				),
				{ selectionMark = true }
			)
		)
		return UI.corners(
			UI.ZStack({
				id = "Indicator",
				alignH = "center",
				alignV = "center",
				surface = "chip",
				width = INDICATOR_BOX,
				height = INDICATOR_BOX,
				children = marks,
			}),
			"control"
		)
	end

	local function switchMark(): any
		local leaf = UI.Toggle({
			id = "Indicator",
			label = "",
			value = selected,
			enabled = spec.enabled,
			focusable = false,

			width = { type = "fixed", px = "controls.toggle.markWidth" },

			padding = 0,
			height = { type = "minMax", min = "targetSizes.minimum" },
		})

		-- Current Compose nodes are owned mutable hosts; detached descriptions remain immutable.
		if Compose.custodyOf(leaf) == "owned" then
			leaf.meta = DISPLAY_ONLY_META
			return leaf
		end
		local marked = table.clone(leaf)
		marked.meta = DISPLAY_ONLY_META
		return table.freeze(marked)
	end

	local function indicatorFor(): any?
		if presentation == "checkbox" then
			return checkboxMark()
		elseif presentation == "switch" then
			return switchMark()
		end
		return nil
	end

	local function labelColumn(): any
		local title = UI.Text({ id = "Label", text = spec.label or "", textSize = "control", width = contentWidth })
		if spec.hint == nil then
			return title
		end
		return UI.VStack({
			id = "Labels",
			gap = "xs",
			width = contentWidth,
			children = {
				title,

				UI.Text({ id = "Hint", text = spec.hint, textSize = "label", role = "secondary", width = contentWidth }),
			},
		})
	end

	local blueprint
	if spec.row then
		assert(spec.row.value == nil, "Toggle.row: value is supplied by the toggle")
		props.width = rowWidth
		props.selected = selected

		local mark = indicatorFor()

		props.children = menuRecipe.semantic(
			UI,
			spec.label,
			spec.row,
			if mark ~= nil
				then nil
				else Compose.formula(function(use)
					return if spec.mixed and selection.read(spec.mixed, use)
						then "Mixed"
						elseif selection.read(spec.value, use) then "On"
						else "Off"
				end),
			mark,
			side
		)
		-- A SETTING ROW WEARS THE ROW FRAME. `selected` alone
		-- classifies a Button into the `selection` slot, whose carve differs from
		-- `control` (Fantasy Ornate: 8 vs 14 px), so this row's content sat 6 px
		-- left of every Button and Slider row. The mark carries the state; the
		-- sheet's `.facet-selected > .facet-chrome-control` rule still lights it.
		blueprint = chrome.attachHint(UI.Button(props), { slot = "control" })
	elseif presentation == "switch" and spec.hint == nil and side == "trailing" then
		props.value = spec.value
		props.width = width
		blueprint = UI.Toggle(props)
	elseif presentation == "button" then
		props.width = width
		props.selected = selected
		props.children = spec.children
		blueprint = UI.Button(props)
	else
		props.selected = selected
		props.width = rowWidth
		local parts: { any } = { labelColumn() }
		local mark = indicatorFor()
		if side == "leading" then
			table.insert(parts, 1, mark)
		else
			table.insert(parts, mark)
		end
		props.children =
			{ UI.HStack({ id = "Row", gap = "s", align = "center", width = contentWidth, children = parts }) }
		blueprint = UI.Button(props)
	end

	local focusGraph: any = nil
	local rowPath: string? = nil
	blueprint = contribution.attach(blueprint, {
		handleActivate = function(path: string): boolean
			if focusGraph ~= nil and rowPath ~= nil and path ~= rowPath then
				focusGraph.focusOn(rowPath)
			end
			activate()
			return true
		end,
		bindFocusGraph = function(graph: any)
			focusGraph = graph
		end,
		syncGeometry = function(_rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil and rowPath == nil then
				rowPath = rootNode.path
			end
		end,
	})

	if spec.controlSize ~= nil then
		blueprint = vocabulary.reserveTarget(UI, core, props.id, blueprint, props.width)
	end
	local function dump()
		return {
			schema = "facet-toggle-dump/1",
			value = selection.read(spec.value),
			mixed = spec.mixed ~= nil and selection.read(spec.mixed),
			presentation = presentation,
			enabled = contract.enabledNow(spec.enabled),
			hint = selection.read(spec.hint),
			indicatorPosition = side,
			controlSize = selection.read(spec.controlSize),
			width = if width and width:peek() then width:peek().type else nil,
		}
	end
	return table.freeze({
		blueprint = blueprint,
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	})
end
function toggle.build(Facet, core, spec)
	local parent = Compose.currentOwner()
	local owner = if parent then parent.createChild() else core.owner.createChild()
	local ok, result = pcall(Compose.withOwner, owner, function()
		return build(Facet, core, spec, owner)
	end)
	if not ok then
		owner.dispose()
		error(result, 0)
	end
	return result
end
return toggle
