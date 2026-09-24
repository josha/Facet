--!strict
-- Expandable content with focus recovery. Native pages and caret motion belong
-- to Compose; Facet supplies the header, layout, theme icon and input behavior.

local controlContract = require("../class_contract")
local Compose = require("../vendor/compose/core")
local contribution = require("../input/contribution")
local themePackage = require("../themes/package")
local chrome_slots = require("../tokens/chrome_slots")
local specGuard = require("../spec_guard")
local vocabulary = require("./control_vocabulary")

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
	"description",
	"icon",
	"chevronPosition",
	"appearance",
	"controlSize",
	"textSize",
	"indent",
})

local APPEARANCES = { "plain", "contained", "divided", "outline" }
local APPEARANCE_SET = specGuard.keySet(APPEARANCES)
local POSITIONS = { "leading", "trailing" }
local POSITION_SET = specGuard.keySet(POSITIONS)

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

	local appearance = if spec.appearance == nil then "plain" else spec.appearance
	if not APPEARANCE_SET[appearance] then
		error(
			`Facet UI.DisclosureGroup('{id}'): \`appearance\` must be {table.concat(APPEARANCES, " | ")} `
				.. `(got '{tostring(spec.appearance)}')`,
			0
		)
	end
	local chevronSide = if spec.chevronPosition == nil then "leading" else spec.chevronPosition
	if not POSITION_SET[chevronSide] then
		error(
			`Facet UI.DisclosureGroup('{id}'): \`chevronPosition\` must be {table.concat(POSITIONS, " | ")} `
				.. `(got '{tostring(spec.chevronPosition)}')`,
			0
		)
	end
	if spec.icon ~= nil and not themePackage.isIconName(spec.icon) then
		error(
			`Facet UI.DisclosureGroup('{id}'): \`icon\` is a semantic icon NAME the theme can answer `
				.. `(got '{tostring(spec.icon)}') — never an asset id, which no package could then re-skin.`,
			0
		)
	end
	if spec.description ~= nil and type(selection.read(spec.description)) ~= "string" then
		error(
			`Facet UI.DisclosureGroup('{id}'): \`description\` is the second line under the label — a string `
				.. `or a getter for one (got {typeof(selection.read(spec.description))}).`,
			0
		)
	end
	vocabulary.assertSize("UI.DisclosureGroup", spec.controlSize)
	-- the header's type role (label, caret, icon); `control` as before
	local textSize = spec.textSize or "control"
	-- an outline row: no header plate and no expanded wash, like a tree row
	local outline = appearance == "outline"

	local headerPath: string? = nil
	local rootPath: string? = nil
	local focusGraph: any = nil
	local function returnContentFocus()
		if focusGraph == nil or headerPath == nil or rootPath == nil then
			return
		end
		local focused = focusGraph.focused:peek()
		local prefix = rootPath .. "/Reveal/"
		if focused ~= nil and string.sub(focused, 1, #prefix) == prefix then
			focusGraph.focusOn(headerPath)
		end
	end
	-- Register before presence: caller-owned state can collapse the branch too.
	Compose.watch(function(use)
		if not use(expanded) then
			returnContentFocus()
		end
	end)

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
			returnContentFocus()
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
			padding = if spec.indent ~= nil then { left = spec.indent, right = 0, top = 0, bottom = 0 } else nil,
			children = { spec.content() },
		})
	end
	local reveal, adoptReveal =
		regionTransitions.branch({ enter = "reveal", class = "dismiss", exitClass = "dismiss" }, expanded, content)
	local caret = chrome_slots.attachHint(
		UI.Text({ id = "Caret", text = CARET, textSize = textSize, rotation = caretAngle }),
		{ icon = "chevron.trailing" }
	)
	local title: any = UI.Text({
		id = "Label",
		text = spec.label,
		textSize = textSize,
		width = { type = "fill", weight = 1 },
	})
	if spec.description ~= nil then
		title = UI.VStack({
			id = "Labels",
			gap = "xs",
			width = { type = "fill", weight = 1 },
			children = {
				UI.Text({
					id = "Label",
					text = spec.label,
					textSize = textSize,
					width = { type = "fill", weight = 1 },
				}),
				UI.Text({
					id = "Description",
					text = spec.description,
					textSize = "label",
					role = "secondary",
					width = { type = "fill", weight = 1 },

					disclose = true,
				}),
			},
		})
	end
	local headerChildren: { any } = {}
	if chevronSide == "leading" then
		table.insert(headerChildren, caret)
	end
	if spec.icon ~= nil then
		table.insert(
			headerChildren,
			chrome_slots.attachHint(
				UI.Text({ id = "Icon", text = themePackage.iconGlyph(spec.icon) or "", textSize = textSize }),
				{ icon = spec.icon }
			)
		)
	end
	table.insert(headerChildren, title)
	if chevronSide == "trailing" then
		table.insert(headerChildren, caret)
	end

	local sizedHeight = vocabulary.deriveSize("UI.DisclosureGroup", spec.controlSize, function(rung)
		return vocabulary.heightFor(rung) or { type = "minMax", min = "targetSizes.minimum" }
	end)
	local sizedPadding = vocabulary.deriveSize("UI.DisclosureGroup", spec.controlSize, vocabulary.paddingFor)

	local header: any = UI.Button({
		id = "Header",
		label = spec.label,
		enabled = spec.enabled,
		selected = if outline then nil else expanded,
		surface = if outline then "plain" else nil,
		gap = "xs",
		width = { type = "fill", weight = 1 },
		height = sizedHeight or { type = "minMax", min = "targetSizes.minimum" },
		padding = sizedPadding,
		children = headerChildren,
	})
	if spec.controlSize ~= nil then
		header = vocabulary.reserveTarget(UI, core, "Header", header, { type = "fill", weight = 1 })
	end
	local groupChildren: { any } = { header }
	if appearance == "divided" then
		table.insert(
			groupChildren,
			UI.When({
				id = "Rule",
				condition = expanded,
				thenView = function()
					return UI.Divider({ id = "Divider" })
				end,
			})
		)
	end
	table.insert(groupChildren, reveal)
	local root = UI.VStack({
		id = id,
		gap = "xs",
		width = { type = "fill", weight = 1 },
		surface = if appearance == "contained" then "raised" else nil,
		children = groupChildren,
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
			if rootNode == nil then
				return
			end
			rootPath = rootNode.path
			if headerPath ~= nil then
				return
			end
			local function findHeader(node: any)
				for _, child in node.children or {} do
					if child.id == "Header" then
						headerPath = child.path
						return
					end
					findHeader(child)
					if headerPath ~= nil then
						return
					end
				end
			end
			findHeader(rootNode)
		end,

		bindFocusGraph = function(graph: any)
			focusGraph = graph
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
			description = selection.read(spec.description),
			icon = spec.icon,
			chevronPosition = chevronSide,
			appearance = appearance,
			controlSize = selection.read(spec.controlSize),
			textSize = textSize,
			indent = spec.indent,
			expanded = selection.read(expanded),
			headerPath = headerPath,
			semanticText = `{spec.label}: {if selection.read(expanded) then "expanded" else "collapsed"}`,
		}
	end

	function api.dispose() end

	return api
end

return disclosure_group
