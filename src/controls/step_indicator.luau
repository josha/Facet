--!strict
--[[ StepIndicator — where a workflow is (phase6 P6b, D7). Not numeric Stepper,
	not a Picker: it shows a list of step STATES and at most lets the caller move
	between the steps it allows.

	ONE AUTHORITY. `current` (a step id, or nil) alone decides the underline, the
	summary and the "current" cue. A row's own `state` (complete | error |
	upcoming, or `current` only when it agrees) decides its leading cue and its
	readable state word, so an errored current step still shows its error. A
	missing or removed current is a truthful "No current step", never a guess.

	ONLY PERMITTED STEPS ARE BUTTONS. A step becomes a Button when it is
	`navigable`, `enabled` and the control has `onSelect`; every other step is
	informational content (disabled paint where `enabled = false`), never a fake
	disabled command. Activation re-reads the step and proposes `onSelect(id)`;
	nothing here writes `current`.

	FIT. When the measured width holds every label the steps run in a row with the
	shared selection underline (built only while there are steps). Otherwise a
	"Step n of m — Label" summary and a Steps button present the whole list in a
	Popover, where permitted steps select through the same path. ]]
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local ownedFormula = require("../core/owned_formula")
local contribution = require("../input/contribution")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")
local textFit = require("../layout/text_fit")
local vocabulary = require("./control_vocabulary")
local selectionIndicator = require("./selection_indicator")
local alert = require("./alert")

local stepIndicator = {}

local specTypes = require("../spec_types/step_indicator")
export type Spec = specTypes.Spec

local KEYS =
	guard.keySet({ "controlSize", "current", "enabled", "env", "id", "listLabel", "onSelect", "sizing", "steps" })
local STEP_KEYS = guard.keySet({ "description", "enabled", "id", "label", "navigable", "state" })
local STATES = { complete = true, current = true, upcoming = true, error = true }
local SIZINGS = { fill = true, hug = true }
local STATE_WORDS = { complete = "Complete", current = "Current", upcoming = "Upcoming", error = "Error" }
local DUMP_SCHEMA = "facet-step-indicator-dump/1"

-- nil when the snapshot is legal, else the reason
local function refusal(steps: any, current: any): string?
	if type(steps) ~= "table" then
		return "`steps` is an array of { id, label, description?, state?, navigable?, enabled? }"
	end
	if current ~= nil and (type(current) ~= "string" or current == "") then
		return "`current` is a step id or nil"
	end
	local seen: { [string]: boolean } = {}
	for i, step in steps do
		if type(step) ~= "table" then
			return `steps[{i}] is not a table`
		end
		for key in step do
			if STEP_KEYS[key] ~= true then
				return `steps[{i}] has an unknown key '{tostring(key)}'`
			end
		end
		if type(step.id) ~= "string" or step.id == "" or string.find(step.id, "/", 1, true) then
			return `steps[{i}].id is a nonempty path-safe string`
		end
		if seen[step.id] then
			return `two steps share the id '{step.id}'`
		end
		seen[step.id] = true
		if type(step.label) ~= "string" or step.label == "" then
			return `steps[{i}].label is a nonempty string`
		end
		if step.description ~= nil and type(step.description) ~= "string" then
			return `steps[{i}].description is a string`
		end
		if step.state ~= nil and STATES[step.state] ~= true then
			return `steps[{i}].state is complete | current | upcoming | error`
		end
		if step.state == "current" and step.id ~= current then
			return `steps[{i}] says current but \`current\` is '{tostring(current)}'`
		end
		for _, key in { "navigable", "enabled" } do
			if step[key] ~= nil and type(step[key]) ~= "boolean" then
				return `steps[{i}].{key} is a boolean`
			end
		end
	end
	return nil
end

local function build(Facet: any, core: any, spec: Spec, owner: any)
	guard.assertKnownKeys("UI.StepIndicator", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "StepIndicator"
	local where = `UI.StepIndicator('{id}')`
	if spec.steps == nil then
		error(`Facet {where}: \`steps\` is required.`, 0)
	end
	local initialReason = refusal(selection.read(spec.steps), selection.read(spec.current))
	if initialReason ~= nil then
		error(`Facet {where}: {initialReason}.`, 0)
	end
	if spec.onSelect ~= nil and type(spec.onSelect) ~= "function" then
		error(`Facet {where}: \`onSelect(id)\` is a function.`, 0)
	end
	local sizing = spec.sizing or "fill"
	if SIZINGS[sizing] ~= true then
		error(`Facet {where}: \`sizing\` is fill | hug.`, 0)
	end
	if spec.listLabel ~= nil and (type(spec.listLabel) ~= "string" or spec.listLabel == "") then
		error(`Facet {where}: \`listLabel\` is a nonempty string.`, 0)
	end
	vocabulary.assertSize("UI.StepIndicator", spec.controlSize)
	local enabledNow = selection.read(spec.enabled)
	if enabledNow ~= nil and type(enabledNow) ~= "boolean" then
		error(`Facet {where}: \`enabled\` is a boolean or a bound boolean.`, 0)
	end
	local onSelect: any = spec.onSelect

	-- ===== one legal snapshot: steps and current together ==================
	local diagnostics: { string } = {}
	local last = { steps = selection.read(spec.steps), current = selection.read(spec.current) }
	local lastReason: string? = nil
	local snapshot = ownedFormula(owner, function(use)
		local steps, current = selection.read(spec.steps, use), selection.read(spec.current, use)
		local reason = refusal(steps, current)
		if reason == nil then
			last, lastReason = { steps = steps, current = current }, nil
		elseif reason ~= lastReason then
			lastReason = reason
			local line = `Facet {where}: {reason} — keeping the last legal steps`
			selection.note(diagnostics, line)
		end
		-- a current id that names no step is a legal, unavailable current
		local index: number? = nil
		for i, step in last.steps do
			if step.id == last.current then
				index = i
			end
		end
		return { steps = last.steps, current = if index ~= nil then last.current else nil, index = index }
	end)
	local enabled = ownedFormula(owner, function(use)
		return selection.read(spec.enabled, use) ~= false
	end)
	local currentId = ownedFormula(owner, function(use)
		return use(snapshot).current
	end)
	local listOpen = Compose.cell(false)
	-- the list closes when the caller ACCEPTS a step; a refusal changes nothing
	owner.watchStatic(currentId, function()
		listOpen:set(false)
	end)

	local function stateOf(step: any, current: string?): string
		if step.state ~= nil and step.state ~= "current" then
			return step.state
		end
		return if step.id == current then "current" else "upcoming"
	end
	local function summaryOf(snap: any): string
		if #snap.steps == 0 then
			return "No steps"
		end
		if snap.index == nil then
			return "No current step"
		end
		return `Step {snap.index} of {#snap.steps} — {snap.steps[snap.index].label}`
	end
	local function permitted(step: any): boolean
		return onSelect ~= nil and step.navigable == true and step.enabled ~= false
	end

	-- ===== proposals: re-read the step, then one onSelect ====================
	local disposed = false
	local function select(stepId: string)
		if disposed or not enabled:peek() then
			return
		end
		local snap = snapshot:peek()
		for _, step in snap.steps do
			if step.id == stepId then
				if permitted(step) and stepId ~= snap.current then
					onSelect(stepId)
				end
				return
			end
		end
	end

	-- ===== one step's content, live by id ====================================
	local function stepById(use: any, stepId: string): (any, number?)
		for i, step in use(snapshot).steps do
			if step.id == stepId then
				return step, i
			end
		end
		return nil, nil
	end
	local function cue(stepId: string): any
		local state = Compose.formula(function(use)
			local step = stepById(use, stepId)
			return if step ~= nil then stateOf(step, use(currentId)) else "upcoming"
		end)
		local marked = Compose.formula(function(use)
			local s = use(state)
			return s == "complete" or s == "error"
		end)
		-- a FLOOR, not a cap: the number grows with the player's text size, and the
		-- width follows the height so the circle never becomes an oval
		return UI.ZStack({
			id = "Cue",
			width = { type = "aspect", ratio = 1 },
			height = { type = "minMax", min = "iconSizes.medium" },
			alignH = "center",
			alignV = "center",
			children = {
				-- complete is a real check and error its own mark: never colour alone
				require("./label").icon(UI, "checkmark", {
					id = "Check",
					tint = { role = "accent", blend = 1 },
					hidden = function(use)
						return use(state) ~= "complete"
					end,
				}),
				require("./label").icon(UI, "status.error", {
					id = "Error",
					tint = { role = "danger", blend = 1 },
					hidden = function(use)
						return use(state) ~= "error"
					end,
				}),
				-- current and upcoming: the step's number in an outlined circle
				UI.corners(
					UI.ZStack({
						id = "Circle",
						width = UI.fill(),
						height = UI.fill(),
						alignH = "center",
						alignV = "center",
						hidden = marked,
						stroke = Compose.formula(function(use)
							return UI.strokeData({ color = if use(state) == "current" then "accent" else "hairline" })
						end),
						children = {
							UI.Text({
								id = "Number",
								textSize = "caption",
								text = function(use)
									local _, index = stepById(use, stepId)
									return if index ~= nil then tostring(index) else ""
								end,
							}),
						},
					}),
					"pill"
				),
			},
		})
	end
	-- `span` is fill in the row (its steps share the width) and hug in the list,
	-- whose panel hugs its content and would leave a fill line nothing to fill
	local function copy(stepId: string, described: boolean, span: any): { any }
		local lines: { any } = {
			UI.Text({
				id = "Label",
				textSize = "label",
				width = span,
				text = function(use)
					local step = stepById(use, stepId)
					return if step ~= nil then step.label else ""
				end,
			}),
			UI.Text({
				id = "State",
				textSize = "caption",
				role = "secondary",
				width = span,
				text = function(use)
					local step = stepById(use, stepId)
					return if step ~= nil then STATE_WORDS[stateOf(step, use(currentId))] else ""
				end,
			}),
		}
		if described then
			table.insert(
				lines,
				UI.Text({
					id = "Description",
					textSize = "caption",
					role = "secondary",
					width = span,
					text = function(use)
						local step = stepById(use, stepId)
						return if step ~= nil then step.description or "" else ""
					end,
				})
			)
		end
		return lines
	end
	-- a step is a Button when it may be selected, else plain content. That SHAPE
	-- (and whether it has a description) is the row's key; everything else is live
	local function stepView(entry: any, width: any, idPrefix: string): any
		local span = if width.type == "hug" then UI.hug() else UI.fill()
		local children = {
			cue(entry.id),
			UI.VStack({ id = "Copy", width = span, gap = 0, children = copy(entry.id, entry.described, span) }),
		}
		if entry.button then
			return require("./button").build(Facet, core, {
				id = `{idPrefix}{entry.id}`,
				label = function(use)
					local step = stepById(use, entry.id)
					return if step ~= nil then step.label else entry.id
				end,
				width = width,
				align = "start",
				controlSize = spec.controlSize,
				surface = "plain",
				children = children,
				onActivate = function()
					select(entry.id)
				end,
			}).blueprint
		end
		return UI.HStack({
			id = `{idPrefix}{entry.id}`,
			width = width,
			gap = "s",
			align = "start",
			padding = "xs",
			enabled = function(use)
				local step = stepById(use, entry.id)
				return step == nil or step.enabled ~= false
			end,
			children = children,
		})
	end
	local entries = ownedFormula(owner, function(use)
		local out = {}
		for _, step in use(snapshot).steps do
			local button, described = permitted(step), (step.description or "") ~= ""
			table.insert(out, {
				key = `{step.id}:{if button then "b" else "i"}{if described then "d" else ""}`,
				id = step.id,
				button = button,
				described = described,
			})
		end
		return out
	end)
	local function stepsRegion(regionId: string, width: any, idPrefix: string): any
		return UI.ForEach({
			id = regionId,
			items = entries,
			key = function(entry: any): string
				return entry.key
			end,
			row = function(entry: any): any
				return stepView(entry, width, idPrefix)
			end,
		})
	end

	-- ===== the measured fit ================================================
	local env = if spec.env ~= nil then spec.env else surfaceEnv.find(core)
	local offered = Compose.cell(math.huge)
	local rowFits = ownedFormula(owner, function(use)
		local snap = use(snapshot)
		if #snap.steps == 0 then
			return true
		end
		local metrics = if env ~= nil then use(env:get("themeMetrics")) else themeSnapshot.neutral()
		local facts = if env ~= nil then textFit.facts({ env = env, use = use }) else { scale = 1, offset = 0 }
		local icon = themeSnapshot.resolveNumber(metrics, "iconSizes.medium") or 24
		local gap = themeSnapshot.resolveNumber(metrics, "s") or 8
		local widest = 0
		for _, step in snap.steps do
			widest = math.max(widest, alert.labelWidth(metrics, facts, step.label))
		end
		-- fill sizing gives every step the widest label's share; hug, its own
		local need = 0
		for _, step in snap.steps do
			local label = if sizing == "fill" then widest else alert.labelWidth(metrics, facts, step.label)
			need += icon + gap * 3 + label + alert.buttonChromeX(metrics)
		end
		return need <= use(offered)
	end)

	-- the row and its underline, built only while there are steps to underline
	local function rowView(): any
		local segments = Compose.formula(function(use)
			local out = {}
			for _, step in use(snapshot).steps do
				table.insert(out, { id = `Step-{step.id}`, value = step.id })
			end
			return out
		end)
		local width = if sizing == "fill" then UI.fill() else UI.hug()
		local strip = UI.HStack({
			id = "Strip",
			width = UI.fill(),
			gap = "xs",
			align = "start",
			children = { stepsRegion("Steps", width, "Step-") },
		})
		local indicator = selectionIndicator.build(Facet, core, {
			id = "Underline",
			content = strip,
			segments = segments,
			selected = currentId,
			skin = "underline",
			env = spec.env,
			width = UI.fill(),
		})
		Compose.cleanup(function()
			indicator.dispose()
		end)
		return indicator.blueprint
	end

	-- the summary and the whole list in a Popover
	local function summaryView(): any
		local popover = require("./popover").build(Facet, core, {
			id = "List",
			isPresented = listOpen,
			onPresentedChange = function(next: boolean)
				listOpen:set(next)
			end,
			trigger = UI.Button({
				id = "ShowSteps",
				label = spec.listLabel or "Steps",
				disclose = true,
				-- nothing to list
				hidden = function(use)
					return #use(snapshot).steps == 0
				end,
			}),
			maxWidth = 360,
			content = function()
				return UI.VStack({
					id = "Items",
					gap = "xs",
					children = { stepsRegion("List", UI.hug(), "Item-") },
				})
			end,
		})
		Compose.cleanup(function()
			listOpen:set(false)
			popover.dispose()
		end)
		-- stacked: the summary is only ever shown where a row did not fit
		return UI.VStack({
			id = "Compact",
			width = UI.fill(),
			gap = "xs",
			align = "start",
			children = {
				UI.Text({
					id = "Summary",
					width = UI.fill(),
					disclose = true,
					text = function(use)
						return summaryOf(use(snapshot))
					end,
				}),
				popover.blueprint,
			},
		})
	end

	-- the root always takes its offer, which is what the fit measures: `sizing` is
	-- only how the steps share it (a hugging root would measure its own summary)
	local root = UI.VStack({
		id = id,
		width = UI.fill(),
		enabled = enabled,
		children = {
			UI.When({
				id = "Form",
				condition = ownedFormula(owner, function(use)
					return use(rowFits) and #use(snapshot).steps > 0
				end),
				thenView = rowView,
				elseView = summaryView,
			}),
		},
	})

	local blueprint = contribution.attach(root, {
		syncGeometry = function(rectOf: any, node: any?)
			if node == nil then
				return
			end
			local r = rectOf(node.path)
			if type(r) == "table" and r.w ~= offered:peek() then
				offered:set(r.w)
			end
		end,
	})
	owner.own(function()
		disposed = true
	end)

	local function dump()
		local snap = snapshot:peek()
		local steps = {}
		for _, step in snap.steps do
			table.insert(steps, { id = step.id, state = stateOf(step, snap.current), button = permitted(step) })
		end
		return {
			schema = DUMP_SCHEMA,
			id = id,
			current = snap.current,
			summary = summaryOf(snap),
			form = if rowFits:peek() and #snap.steps > 0 then "row" else "summary",
			listOpen = listOpen:peek(),
			steps = steps,
			diagnostics = table.clone(diagnostics),
		}
	end

	return {
		blueprint = blueprint,
		api = {
			diagnostics = function(): { string }
				return table.clone(diagnostics)
			end,
		},
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	}
end

function stepIndicator.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end

return stepIndicator
