--!strict
-- Expandable content with focus recovery. Native pages and caret motion belong
-- to Compose; Facet supplies the header, layout, theme icon and input behavior.

local controlContract = require("../class_contract")
local contribution = require("../input/contribution")
local themePackage = require("../themes/package")
local chrome_slots = require("../tokens/chrome_slots")
local specGuard = require("../spec_guard")

local disclosure_group = {}
local selection = require("../selection_model")
local regionTransitions = require("../render/region_transitions")

local specTypes = require("../spec_types/disclosure_group")
type BooleanCell = specTypes.BooleanCell
export type Spec<V = BooleanCell> = specTypes.Spec<V>

local DISCLOSURE_GROUP_KEYS = specGuard.keySet({
	"content",
	"enabled",
	"expanded",
	"id",
	"label",
	"onToggle",
	"presenter",
})

function disclosure_group.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("UI.DisclosureGroup", spec, DISCLOSURE_GROUP_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Disclosure"
	if type(spec.label) ~= "string" or spec.label == "" then
		error(`Facet UI.DisclosureGroup('{id}'): \`label\` is required (the header is the control)`, 0)
	end
	local expanded = spec.expanded
	if not selection.isWritable(expanded) or type(selection.read(expanded)) ~= "boolean" then
		error(
			`Facet UI.DisclosureGroup('{id}'): \`expanded\` must be a writable Compose cell holding a boolean, owned by the caller `
				.. `owns (the disclosure state must outlive the control)`,
			0
		)
	end
	if type(spec.content) ~= "function" then
		error(`Facet UI.DisclosureGroup('{id}'): \`content\` must be a function returning a Blueprint`, 0)
	end
	if spec.presenter ~= nil and type((spec.presenter :: any).withAnimation) ~= "function" then
		error(`Facet UI.DisclosureGroup('{id}'): \`presenter\` must be a presenter (something with withAnimation)`, 0)
	end

	local headerPath: string? = nil
	local focusGraph: any = nil

	local function isEnabled(): boolean
		return controlContract.enabledNow(spec.enabled)
	end

	local function toggle(): boolean
		if not isEnabled() then
			return false
		end
		local next_ = not selection.read(expanded)
		-- Return focus before removing the branch that currently contains it.
		if not next_ then
			if focusGraph ~= nil and headerPath ~= nil then
				local focused = focusGraph.focused:peek()
				if focused ~= nil and string.sub(focused, 1, #headerPath) ~= headerPath then
					focusGraph.focusOn(headerPath)
				end
			end
		end
		local function flip()
			expanded:set(next_)
			if spec.onToggle ~= nil then
				spec.onToggle(next_)
			end
		end
		if spec.presenter ~= nil then
			spec.presenter.withAnimation("dismiss", flip)
		else
			flip()
		end
		return true
	end

	local CARET = themePackage.iconGlyph("chevron.trailing") or ">"
	local env = require("../env/surface_env").find(core)
	local function caretGoal(use)
		return if use(expanded) then 90 else 0
	end
	local caretMotion = Facet.runtime.spring(caretGoal, { period = 0.22, damping = 1 })
	local function caretAngle(use)
		return if env and use(env:get("motionPolicy")) == "reduced" then caretGoal(use) else use(caretMotion)
	end

	local function content()
		return UI.ZStack({
			id = "Reveal",
			clipChildren = true,
			width = { type = "fill", weight = 1 },
			children = { spec.content() },
		})
	end
	local reveal, adoptReveal =
		regionTransitions.branch({ enter = "reveal", class = "dismiss", exitClass = "dismiss" }, expanded, content)
	local root = UI.VStack({
		id = id,
		gap = "xs",
		width = { type = "fill", weight = 1 },
		children = {
			UI.Button({
				id = "Header",
				label = spec.label,
				enabled = spec.enabled,
				gap = "xs",
				width = { type = "fill", weight = 1 },
				height = { type = "minMax", min = "targetSizes.minimum" },
				children = {
					chrome_slots.attachHint(
						UI.Text({ id = "Caret", text = CARET, textSize = "control", rotation = caretAngle }),
						{ icon = "chevron.trailing" }
					),
					UI.Text({
						id = "Label",
						text = spec.label,
						textSize = "control",
						width = { type = "fill", weight = 1 },
					}),
				},
			}),
			reveal,
		},
	})

	if adoptReveal then
		adoptReveal(root)
	end

	local built = contribution.attach(root, {
		handleActivate = function(path: string): boolean
			if string.sub(path, -7) == "/Header" then
				headerPath = path
				return toggle()
			end
			return false
		end,
		syncGeometry = function(_rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil and headerPath == nil then
				for _, child in rootNode.children or {} do
					if child.id == "Header" then
						headerPath = child.path
					end
				end
			end
		end,
		bindController = function(controller: any)
			if controller ~= nil and controller.focusGraph ~= nil then
				focusGraph = controller.focusGraph
			end
		end,
	})

	local api = {}
	api.blueprint = built

	function api.bindFocus(graph: any)
		focusGraph = graph
	end

	function api.dump()
		return {
			schema = "facet-disclosure-dump/1",
			id = id,
			label = spec.label,
			expanded = selection.read(expanded),
			headerPath = headerPath,
			semanticText = `{spec.label}: {if selection.read(expanded) then "expanded" else "collapsed"}`,
		}
	end

	function api.dispose() end

	return api
end

return disclosure_group
