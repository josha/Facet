--!strict
-- Brief modal decisions. Reuses Facet's layout, controls, themes and presenter;
-- the optional binding/data forms change ownership, not the input/layout engine.
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local ownedFormula = require("../core/owned_formula")
local contribution = require("../input/contribution")
local selection = require("../selection_model")
local guard = require("../spec_guard")
local contract = require("../class_contract")
local shortcut = require("./button_shortcut")
local surfaceEnv = require("../env/surface_env")
-- the ONE authority on a transition's shape; `alert.build` re-addresses its
-- refusal rather than re-deriving the rule (task 7 item 5)
local transitionsLib = require("../render/transitions")

-- a Readable, by the SAME test `transitions.resolve` itself applies when it
-- unwraps one (`render/transitions.luau`) — module-level here, where `Facet.UI`
-- is not yet in hand, and deliberately the one authority's own shape rather
-- than a second opinion about what counts as readable
local function isReadableTransition(value: any): boolean
	return Compose.isReadable(value)
end

local ALERT_MATERIALIZE_SCALE = 1.015
local DEFAULT_TRANSITION = table.freeze({ enter = "materialize", plate = "fades", scale = ALERT_MATERIALIZE_SCALE })

-- `resolve`'s own detail begins lower-case ("unknown enter form …"), so the
-- address needs its colon or the two run together (review N5)
local function transitionRefusal(err: any): string
	local detail = string.gsub(tostring(err), "^Facet transition: ", "")
	return `UI.Alert: transition: {detail} — the modal materializes by default; `
		.. 'pass `{ enter = "instant" }` to opt out.'
end

local function mergePlate(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local wantsPlate = value.plate == nil
	local wantsScale = value.enter == "materialize" and value.scale == nil
	if not wantsPlate and not wantsScale then
		return value
	end
	local merged = table.clone(value)
	if wantsPlate then
		merged.plate = "fades"
	end
	if wantsScale then
		merged.scale = ALERT_MATERIALIZE_SCALE
	end
	return merged
end

local function acknowledgePlate(declared: any): any
	if declared == nil or declared == false then
		return DEFAULT_TRANSITION
	end
	if isReadableTransition(declared) then
		return ownedFormula(Compose.currentOwner(), function(use)
			local value = use(declared)
			if value == nil or value == false then
				return DEFAULT_TRANSITION
			end
			return mergePlate(value)
		end)
	end
	return mergePlate(declared)
end
local chromeSlots = require("../tokens/chrome_slots")
local themeSnapshot = require("../themes/snapshot")
local textMetrics = require("../layout/text_metrics")
local textFit = require("../layout/text_fit")
local alert = {}
local specTypes = require("../spec_types/alert")
type Text = specTypes.Text
export type Action = specTypes.Action
type BooleanCell = specTypes.BooleanCell
export type Spec<P = BooleanCell> = specTypes.Spec<P>
local KEYS = guard.keySet({
	"id",
	"title",
	"message",
	"actions",
	"isPresented",
	"presenter",
	"presenting",
	"item",
	"error",
	"icon",
	"severity",
	"suppression",
	"content",
	"env",
	"maxWidth",
	"padding",
	"surface",
	"transition",
})
local ACTION_KEYS = guard.keySet({ "id", "label", "compactLabel", "role", "enabled", "shortcut", "onActivate" })
local DEFAULT_ACTIONS = table.freeze({ table.freeze({ id = "OK", label = "OK", role = "default" }) })
local function point(x, y)
	return { x = x, y = y, inX = 0, inY = 0, outX = 0, outY = 0 }
end
local CAUTION = table.freeze({ point(0.5, 0.08), point(0.94, 0.9), point(0.06, 0.9) })
local STEM = table.freeze({ point(0.5, 0.35), point(0.5, 0.6) })
local DOT = table.freeze({ point(0.5, 0.73), point(0.5, 0.75) })
alert.ACCESSIBILITY_TEXT_OFFSET = 10 -- the "Larger" preferred-text reservation, px (api.md `preferredTextOffset`)
function alert.resolveStacked(
	actionCount: number,
	sizeClass: any,
	distanceProfile: any,
	preferredTextOffset: number?
): boolean
	return actionCount > 2
		or sizeClass == "compact"
		or distanceProfile == "ten-foot"
		or (preferredTextOffset or 0) >= alert.ACCESSIBILITY_TEXT_OFFSET
end
function alert.rowFits(labelWidths: { number }, chromeX: number, gap: number, available: number): boolean
	if #labelWidths == 0 then
		return true
	end
	local need = gap * (#labelWidths - 1)
	for _, w in labelWidths do
		need += w + chromeX
	end
	return need <= available and need < math.huge
end
function alert.orderActions(actions: { Action }, stacked: boolean): { Action }
	local rest, cancel = {}, nil
	for _, a in actions do
		if a.role == "cancel" and cancel == nil then
			cancel = a
		else
			table.insert(rest, a)
		end
	end
	if cancel ~= nil then
		table.insert(rest, if stacked then #rest + 1 else 1, cancel)
	end
	return rest
end
-- one action label's measured width at the Button type role (shared with Dialog)
function alert.labelWidth(metrics: any, facts: any, label: string): number
	local _, role = themeSnapshot.effectiveTypeRole(metrics, "Button", nil)
	local size = textMetrics.reservedSize(
		if type(role) == "table" and type(role.size) == "number" then role.size else 16,
		facts.scale,
		facts.offset
	)
	local font = if type(role) == "table" then role.fontKey else nil
	if type(font) ~= "string" then
		return math.huge
	end
	local lineHeight = if type(role) == "table" then role.lineHeight else nil
	return textMetrics.measure(label, font, size, math.huge, lineHeight, 1).width
end
-- ...plus the chrome one Button spends around it, and the gap a row puts
-- between two of them
-- the horizontal chrome a regular Button spends around its label (shared with Dialog)
function alert.buttonChromeX(metrics: any): number
	local sizes = if type(metrics) == "table" then (metrics :: any).controlSizes else nil
	local regular = if type(sizes) == "table" then (sizes :: any).regular else nil
	local padX = if type(regular) == "table" and type(regular.paddingX) == "number" then regular.paddingX else 0
	local art = if type(metrics) == "table" and type(metrics.chromeInsets) == "table"
		then (metrics.chromeInsets :: any).control
		else nil
	local artX = if type(art) == "table" then (art.left or 0) + (art.right or 0) else 0
	return padX * 2 + artX
end
--[[ THE PINNED ACTION GROUP a modal panel shares (Dialog, Sheet): the Alert
	stacking policy, then a measured fall to the safe stack when a row cannot
	show every full label at `widthOf(use)`. Cancel sits first in a row and last
	in a stack; the default action wears `dialogAction = "default"` (Return).
	`press(action)` is the caller's — actions never close anything here. ]]
function alert.actionGroup(
	Facet: any,
	owner: any,
	env: any,
	actions: { any },
	layout: string,
	widthOf: (any) -> number,
	press: (any) -> (),
	-- false: a compact screen alone does not stack a row that fits (Dialog)
	compactStacks: boolean?
): any
	local themeMetrics, sizeClass = env:get("themeMetrics"), env:get("sizeClass")
	local distanceProfile, textOffset = env:get("distanceProfile"), env:get("preferredTextOffset")
	local stacked = ownedFormula(owner, function(use)
		if layout == "stacked" then
			return true
		end
		if
			layout == "automatic"
			and alert.resolveStacked(
				#actions,
				if compactStacks == false then nil else use(sizeClass),
				use(distanceProfile),
				use(textOffset)
			)
		then
			return true
		end
		-- a row that cannot show every full label falls to the safe stack,
		-- whichever layout asked for it
		local metrics = use(themeMetrics)
		local facts = textFit.facts({ env = env, use = use })
		local widths = {}
		for _, action in actions do
			local label = selection.read(action.label, use)
			table.insert(widths, alert.labelWidth(metrics, facts, if type(label) == "string" then label else ""))
		end
		local gap = themeSnapshot.resolveNumber(metrics, "m") or 0
		return not alert.rowFits(widths, alert.buttonChromeX(metrics), gap, widthOf(use))
	end)
	local rowOrder, stackOrder = alert.orderActions(actions, false), alert.orderActions(actions, true)
	local function mode(row: any, stack: any): any
		return ownedFormula(owner, function(use)
			return if use(stacked) then stack else row
		end)
	end
	return Facet.UI.AdaptiveStack({
		id = "Actions",
		axis = mode("x", "y"),
		align = mode("center", "stretch"),
		gap = mode("m", "s"),
		width = Facet.UI.fill(),
		distribute = "center",
		children = {
			Facet.UI.ForEach({
				id = "Order",
				items = mode(rowOrder, stackOrder),
				key = function(action: any): string
					return action.id
				end,
				row = function(action: any): any
					return Facet.nativeControls.Button({
						id = action.id,
						label = action.label,
						enabled = action.enabled,
						busy = action.busy,
						role = if action.role == "destructive" then "destructive" else nil,
						surface = if action.role == "default" then "accent" else nil,
						dialogAction = if action.role == "default" then "default" else nil,
						disclose = true,
						height = { type = "minMax", min = "targetSizes.minimum" },
						onActivate = function()
							press(action)
						end,
					})
				end,
			}),
		},
	})
end
local function build(Facet: any, core: any, spec: Spec, owner: any)
	guard.assertKnownKeys("UI.Alert", spec, KEYS, "spec")
	local UI = Facet.UI
	local env = surfaceEnv.resolve(
		"UI.Alert",
		spec.id or "Alert",
		core,
		spec.env,
		"action placement adapts to the width class and viewing distance"
	)
	local sizeClass, distanceProfile, textOffset =
		env:get("sizeClass"), env:get("distanceProfile"), env:get("preferredTextOffset")
	local themeMetrics, viewportRect, platformChrome =
		env:get("themeMetrics"), env:get("viewportRect"), env:get("platformChrome")
	local function cardSpend(metrics: any): any
		local art = if type(metrics) == "table" and type(metrics.chromeInsets) == "table"
			then (metrics.chromeInsets :: any).panel
			else nil
		local authored = themeSnapshot.resolveNumber(metrics, spec.padding or "m") or 0
		local floor = math.min(authored, themeSnapshot.resolveNumber(metrics, "xs") or 0)
		local function side(name: string): number
			local carved = if type(art) == "table" and type((art :: any)[name]) == "number"
				then (art :: any)[name]
				else 0
			return math.max(floor, authored - carved)
		end
		return { top = side("top"), right = side("right"), bottom = side("bottom"), left = side("left") }
	end
	local function outerMargin(metrics: any): number
		local margin = themeSnapshot.resolveNumber(metrics, "m") or 0
		local bleed = if type(metrics) == "table" then metrics.chromeBleed or 0 else 0
		return math.max(margin, bleed)
	end
	local function actionsWidth(use: any): number
		local metrics = use(themeMetrics)
		local vp = use(viewportRect)
		local chrome = use(platformChrome)
		local insets = if type(chrome) == "table" then (chrome :: any).insets else nil
		local screenW = (if type(vp) == "table" and type(vp.w) == "number" then vp.w else 0)
			- (if type(insets) == "table" then (insets.left or 0) + (insets.right or 0) else 0)
		-- The fade group keeps the same themed outer margin as the card had.
		local screenPad = outerMargin(metrics)
		local cap = themeSnapshot.resolveNumber(metrics, spec.maxWidth or "controls.alert.maxWidth")
		local card = math.max(0, screenW - 2 * screenPad)
		if type(cap) == "number" then
			card = math.min(cap, card)
		end
		local pad = cardSpend(metrics)
		local art = if type(metrics) == "table" and type(metrics.chromeInsets) == "table"
			then (metrics.chromeInsets :: any).panel
			else nil
		local artX = if type(art) == "table" then (art.left or 0) + (art.right or 0) else 0
		return math.max(0, card - pad.left - pad.right - artX)
	end
	-- the natural width of one action label, at the size and face a Button will
	-- actually draw it — `text_metrics` is the solver's own measurer, not a copy
	local labelWidth, buttonChromeX = alert.labelWidth, alert.buttonChromeX
	local function read(v, use)
		return if UI.isReadable(v) then (if use then use(v) else v:peek()) else v
	end
	local function textValue(v, name, optional, factory)
		assert(
			(optional and v == nil)
				or type(v) == "string"
				or (UI.isReadable(v) and type(v:peek()) == "string")
				or (factory and type(v) == "function"),
			"UI.Alert: "
				.. name
				.. " must be a string or Readable<string>"
				.. (if factory then " or data factory" else "")
		)
	end
	local function signal(v, name)
		assert(selection.isWritable(v), "UI.Alert: " .. name .. " must be a writable Compose cell")
	end
	textValue(spec.title, "title", spec.error ~= nil, true)
	textValue(spec.message, "message", true, true)
	textValue(spec.icon, "icon", true, false)
	assert(
		spec.severity == nil
			or spec.severity == "automatic"
			or spec.severity == "standard"
			or spec.severity == "critical",
		"UI.Alert: severity must be automatic, standard or critical"
	)
	assert(
		spec.content == nil or type(spec.content) == "function",
		"UI.Alert: content must be a blueprint factory taking the Compose owner"
	)
	assert(
		spec.maxWidth == nil
			or type(spec.maxWidth) == "string"
			or (type(spec.maxWidth) == "number" and spec.maxWidth > 0 and spec.maxWidth < math.huge),
		"UI.Alert: maxWidth must be positive finite pixels or a metric name"
	)
	assert(
		spec.padding == nil
			or type(spec.padding) == "string"
			or (type(spec.padding) == "number" and spec.padding >= 0 and spec.padding < math.huge),
		"UI.Alert: padding must be nonnegative finite pixels or a metric name"
	)
	assert(spec.surface == nil or type(spec.surface) == "string", "UI.Alert: surface must be a string")
	-- ...for a value that IS one here. `false` folds to the default (the
	-- framework's own "no transition" spelling, which the present site already
	-- ignored) and a Readable is judged on its first READ instead — a signal's
	-- build-time value is not the one the alert will open on, so refusing on it
	-- is a check about the wrong instant (review N5).
	if spec.transition ~= nil and spec.transition ~= false and not isReadableTransition(spec.transition) then
		local ok, err = pcall(transitionsLib.resolve, spec.transition)
		if not ok then
			error(transitionRefusal(err), 0)
		end
	end
	assert(spec.id == nil or (type(spec.id) == "string" and spec.id ~= ""), "UI.Alert: id must be a nonempty string")
	assert(
		not (spec.item ~= nil and (spec.presenting ~= nil or spec.error ~= nil or spec.isPresented ~= nil)),
		"UI.Alert: item is an alternative to isPresented/presenting/error"
	)
	assert(
		not (spec.presenting ~= nil and spec.error ~= nil),
		"UI.Alert: presenting and error are alternative data sources"
	)
	if spec.isPresented ~= nil then
		signal(spec.isPresented, "isPresented")
		assert(type(spec.isPresented:peek()) == "boolean", "UI.Alert: isPresented must hold a boolean")
	end
	if spec.item ~= nil then
		signal(spec.item, "item")
	end
	if spec.suppression ~= nil then
		guard.assertKnownKeys(
			"UI.Alert suppression",
			spec.suppression,
			guard.keySet({ "isSuppressed", "label" }),
			"spec"
		)
		signal(spec.suppression.isSuppressed, "suppression.isSuppressed")
		assert(type(spec.suppression.isSuppressed:peek()) == "boolean", "UI.Alert: isSuppressed must hold a boolean")
		textValue(spec.suppression.label, "suppression.label", true, false)
	end
	local source = if spec.item ~= nil then spec.item elseif spec.error ~= nil then spec.error else spec.presenting
	local automaticError = spec.error ~= nil
		and type(spec.error) == "table"
		and selection.isWritable(spec.error)
		and spec.isPresented == nil
	local bound = spec.isPresented ~= nil or spec.item ~= nil or automaticError
	assert(
		not bound
			or Facet.surfaces ~= nil
			or (type(spec.presenter) == "table" and type(spec.presenter.presentModal) == "function"),
		"UI.Alert: a presentation binding requires presenter"
	)
	local function actionsValue(value)
		assert(
			value == nil or (type(value) == "table" and not UI.isReadable(value)),
			"UI.Alert: actions must be an array or data factory"
		)
		if value ~= nil then
			for key in value do
				assert(
					type(key) == "number" and key >= 1 and key <= #value and key % 1 == 0,
					"UI.Alert: actions must be a dense array"
				)
			end
		end
		local list = if value == nil or #value == 0 then DEFAULT_ACTIONS else value
		local ids, cancel = {}, nil
		for _, a in list do
			guard.assertKnownKeys("UI.Alert action", a, ACTION_KEYS, "spec")
			assert(
				type(a.id) == "string" and a.id ~= "" and not a.id:find("/", 1, true) and ids[a.id] == nil,
				"UI.Alert: each action needs a unique nonempty id without slashes"
			)
			textValue(a.label, "action.label", false, false)
			textValue(a.compactLabel, "action.compactLabel", true, false)
			assert(
				a.role == nil or a.role == "default" or a.role == "cancel" or a.role == "destructive",
				"UI.Alert: action role must be default, cancel or destructive"
			)
			assert(
				a.enabled == nil or type(read(a.enabled)) == "boolean",
				"UI.Alert: action enabled must be boolean or Readable<boolean>"
			)
			assert(
				a.onActivate == nil or type(a.onActivate) == "function",
				"UI.Alert: action onActivate must be a function"
			)
			assert(
				a.shortcut == nil
					or a.shortcut == "defaultAction"
					or a.shortcut == "cancelAction"
					or type(a.shortcut) == "table",
				"UI.Alert: shortcut must be defaultAction, cancelAction or a Button shortcut"
			)
			if type(a.shortcut) == "table" then
				shortcut.validate(a.shortcut)
			end
			if a.role == "cancel" then
				assert(cancel == nil, "UI.Alert: only one cancel action is allowed")
				cancel = a
			end
			ids[a.id] = a
		end
		return list, ids, cancel
	end
	if type(spec.actions) ~= "function" then
		actionsValue(spec.actions)
	end
	local function definition()
		local data = read(source)
		if source ~= nil and data == nil then
			return nil
		end
		-- Freeze the record identity for this presentation. Domain objects should
		-- be immutable; updates replace the caller's signal value.
		if type(data) == "table" then
			data = table.clone(data)
		end
		if spec.error ~= nil then
			assert(
				type(data) == "table" and type(data.errorDescription) == "string",
				"UI.Alert: error needs a user-facing errorDescription"
			)
		end
		local title = if type(spec.title) == "function" then spec.title(data) else spec.title
		local message = if type(spec.message) == "function" then spec.message(data) else spec.message
		if spec.error ~= nil then
			title = title or data.errorDescription
			message = message or data.recoverySuggestion or data.failureReason
		end
		textValue(title, "title result", false, false)
		textValue(message, "message result", true, false)
		local list, ids, cancel =
			actionsValue(if type(spec.actions) == "function" then spec.actions(data) else spec.actions)
		local severity = if spec.severity == nil or spec.severity == "automatic"
			then (if spec.error ~= nil then "critical" else "standard")
			else spec.severity
		return {
			title = title,
			message = message,
			actions = list,
			byId = ids,
			cancel = cancel,
			data = data,
			severity = severity,
		}
	end
	local dynamic = spec.content ~= nil
		or source ~= nil
		or type(spec.title) == "function"
		or type(spec.message) == "function"
		or type(spec.actions) == "function"
	local initialDefinition = if dynamic then nil else definition()
	-- resolved ONCE, not per present: a Readable declaration becomes one memo on
	-- this scope rather than a fresh one every time the modal opens
	local declaredTransition = acknowledgePlate(spec.transition)
	local function validateTransition(): any
		if isReadableTransition(spec.transition) then
			local ok, err = pcall(transitionsLib.resolve, declaredTransition)
			if not ok then
				error(transitionRefusal(err), 0)
			end
		end
		return declaredTransition
	end
	local handle, presenter, current = nil, spec.presenter or Facet.presenter, initialDefinition
	local disposed, closing = false, false
	local lastError = nil
	local function resetBinding()
		if spec.isPresented then
			spec.isPresented:set(false)
		end
		if spec.item then
			spec.item:set(nil)
		end
		if automaticError then
			spec.error:set(nil)
		end
	end
	local function dismiss()
		local old = handle
		handle = nil
		closing = true
		resetBinding()
		if old then
			presenter.dismiss(old)
		end
		closing = false
	end
	local function activate(action)
		if disposed or (action and not contract.enabledNow(action.enabled)) then
			return
		end
		local data = current and current.data
		dismiss()
		if action and action.onActivate then
			action.onActivate(data)
		end
	end
	local function card()
		local branchOwner = Compose.currentOwner() or owner
		local def = current or definition()
		if def == nil then
			return nil
		end
		if spec.content then
			assert(
				def.contentScope ~= nil and not def.contentScope.isDisposed() and not def.contentMounted,
				"UI.Alert: custom content requires present() or a presentation binding; do not mount blueprint directly"
			)
			def.contentMounted = true
		end
		current = def
		local content = {}
		local header = {}
		if spec.icon ~= nil then
			table.insert(
				header,
				UI.Image({
					id = "Icon",
					image = spec.icon,
					width = { type = "fixed", px = "controls.alert.iconSize" },
					height = { type = "fixed", px = "controls.alert.iconSize" },
					alignH = "center",
				})
			)
		elseif def.severity == "critical" then
			local paths = {}
			for i, points in { CAUTION, STEM, DOT } do
				table.insert(
					paths,
					UI.Path({
						id = "Mark" .. i,
						points = points,
						closed = i == 1,
						width = UI.fill(),
						height = UI.fill(),
						thickness = "controls.alert.iconStroke",
						tint = { role = "danger", blend = 1 },
					})
				)
			end
			table.insert(
				header,
				UI.ZStack({
					id = "Caution",
					width = { type = "fixed", px = "controls.alert.iconSize" },
					height = { type = "fixed", px = "controls.alert.iconSize" },
					alignH = "center",
					children = paths,
				})
			)
		end
		local marked = #header > 0
		local function blank(value: any): boolean
			return type(value) ~= "string" or string.match(value, "%S") == nil
		end
		local staticBlank = type(def.title) == "string" and blank(def.title)
		if not staticBlank then
			table.insert(
				header,
				UI.Text({
					id = "Title",
					text = def.title,
					disclose = true,
					textSize = "heading",
					textAlign = if marked then "start" else "center",
					width = UI.hug(),
					hidden = if UI.isReadable(def.title)
						then ownedFormula(branchOwner, function(use)
							return blank(use(def.title))
						end)
						else nil,
					tint = if def.severity == "critical" then { role = "danger", blend = 1 } else nil,
				})
			)
		end
		-- an empty row is not a row: with no children it would hug to nothing and
		-- still spend the content stack's gap, 8 px of nothing above the message
		if #header > 0 then
			table.insert(
				content,
				UI.HStack({
					id = "Header",
					width = UI.fill(),
					gap = "s",
					align = "center",
					distribute = "center",
					children = header,
				})
			)
		end
		if def.message ~= nil then
			table.insert(
				content,
				UI.Text({
					id = "Message",
					text = def.message,
					disclose = true,
					role = "secondary",
					textAlign = "center",
					width = UI.fill(),
				})
			)
		end
		if def.contentScope then
			branchOwner.own(def.contentScope.dispose)
		end
		if def.content then
			table.insert(content, def.content)
		end
		if spec.suppression then
			local toggle = require("./toggle").build(Facet, core, {
				id = "Suppression",
				value = spec.suppression.isSuppressed,
				label = spec.suppression.label or "Do not ask again",
				presentation = "checkbox",
			})
			branchOwner.own(toggle.dispose)
			table.insert(content, toggle.blueprint)
		end
		local function actionButton(action)
			local itemOwner = Compose.currentOwner()
			local bp
			if action.shortcut ~= nil then
				local button = require("./button").build(Facet, core, {
					id = action.id,
					label = action.label,
					height = { type = "minMax", min = "targetSizes.minimum" },
					enabled = action.enabled,
					role = if action.role == "destructive" then "destructive" else nil,
					dialogAction = if action.shortcut == "defaultAction"
						then "default"
						elseif action.shortcut == "cancelAction" then "cancel"
						else nil,
					shortcut = if type(action.shortcut) == "table" then action.shortcut else nil,
					onActivate = function()
						activate(action)
					end,
				})
				itemOwner.own(button.dispose)
				bp = button.blueprint
				-- Keep the existing Button shortcut/lifetime bundle on the same
				-- plain label presentation as the other alert actions — WHICH
				-- INCLUDES THE FULL-VALUE ROUTE (review N2). This branch rebuilds
				-- `props` from scratch, so every presentation key the plain branch
				-- below declares has to be restated here or it is silently
				-- dropped; `disclose` was, and this is the branch every
				-- `defaultAction`/`cancelAction` takes — a confirm dialog's
				-- PRIMARY action, the one most likely to be read.
				local props = table.clone(bp.props)
				props.id = bp.id
				props.compactLabel = action.compactLabel
				props.disclose = true
				props.align = nil
				props.surface = if action.role == "default" then "accent" else nil
				return contribution.attach(UI.Button(props), contribution.read(bp))
			end
			return UI.Button({
				id = action.id,
				label = action.label,
				compactLabel = action.compactLabel,
				enabled = action.enabled,
				role = if action.role == "destructive" then "destructive" else nil,
				surface = if action.role == "default" then "accent" else nil,
				height = { type = "minMax", min = "targetSizes.minimum" },
				disclose = true,
			})
		end
		-- One keyed region, two orders: a mode flip MOVES the mounted actions
		-- (identity, focus and shortcuts survive) rather than remounting them.
		local stacked = ownedFormula(branchOwner, function(use)
			if alert.resolveStacked(#def.actions, use(sizeClass), use(distanceProfile), use(textOffset)) then
				return true
			end
			local metrics = use(themeMetrics)
			local facts = textFit.facts({ env = env, use = use })
			local widths = {}
			for _, action in def.actions do
				local label = read(action.label, use)
				table.insert(widths, labelWidth(metrics, facts, if type(label) == "string" then label else ""))
			end
			local gap = themeSnapshot.resolveNumber(metrics, "m") or 0
			return not alert.rowFits(widths, buttonChromeX(metrics), gap, actionsWidth(use))
		end)
		local rowOrder, stackOrder = alert.orderActions(def.actions, false), alert.orderActions(def.actions, true)
		local function mode(row, stack)
			return ownedFormula(branchOwner, function(use)
				return if use(stacked) then stack else row
			end)
		end
		table.insert(
			content,
			UI.AdaptiveStack({
				id = "Actions",
				axis = mode("x", "y"),
				align = mode("center", "stretch"),
				gap = mode("m", "s"),
				width = UI.fill(),
				distribute = "center",
				children = {
					UI.ForEach({
						id = "Order",
						items = mode(rowOrder, stackOrder),
						key = function(action)
							return action.id
						end,
						row = actionButton,
					}),
				},
			})
		)
		return chromeSlots.attachHint(
			UI.ScrollView({
				id = "Card",
				axis = "y",
				width = { type = "hug", max = spec.maxWidth or "controls.alert.maxWidth" },
				height = UI.hug(),
				alignH = "center",
				alignV = "center",
				-- the carved frame IS this card's inner margin, so the authored step
				-- is spent only where the art does not already cover it (`cardSpend`)
				padding = ownedFormula(branchOwner, function(use)
					return cardSpend(use(themeMetrics))
				end),
				gap = "s",
				surface = spec.surface or "raised",
				children = content,
			}),
			{ slot = "panel" }
		)
	end
	local function buildScreen()
		local content = if dynamic
			then UI.When({ id = "Decision", condition = Compose.cell(true), thenView = card })
			else card()
		local actionPrefix = "/"
			.. (spec.id or "Alert")
			.. "/Center/"
			.. (if dynamic then "Decision/then/" else "")
			.. "Card/Actions/Order/["
		local blueprint = contribution.attach(
			UI.Screen({
				id = spec.id or "Alert",
				align = "center",
				distribute = "center",
				children = {
					-- Bound the composited texture to the card. A full-screen CanvasGroup
					-- downsamples small desktop text along with the entire viewport.
					-- Keep a themed bleed margin so the card's shadow is not clipped.
					UI.ZStack({
						id = "Center",
						canvasGroup = true,
						width = UI.hug(),
						height = UI.hug(),
						alignH = "center",
						alignV = "center",
						padding = ownedFormula(Compose.currentOwner(), function(use)
							return outerMargin(use(themeMetrics))
						end),
						children = { content },
					}),
				},
			}),
			{
				handleActivate = function(path)
					local key = if path:sub(1, #actionPrefix) == actionPrefix
						then path:match("^([^%]]+)%]/", #actionPrefix + 1)
						else nil
					local action = current and key and current.byId[key]
					if not action then
						return false
					end
					activate(action)
					return true
				end,
				handleCancel = function()
					local cancel = current and current.cancel
					activate(if cancel and contract.enabledNow(cancel.enabled) then cancel else nil)
					return true
				end,
			}
		)
		return blueprint
	end
	local blueprint = UI.ZStack({ id = (spec.id or "Alert") .. "Anchor" })
	local function present(target)
		assert(not disposed, "UI.Alert: cannot present a disposed alert")
		if handle then
			return handle
		end
		presenter = target or presenter
		assert(
			type(presenter) == "table" and type(presenter.presentModal) == "function",
			"UI.Alert: present requires a presenter"
		)
		if dynamic then
			local ok, result = pcall(definition)
			if not ok then
				lastError = tostring(result)
				if type(warn) == "function" then
					warn("Facet " .. lastError)
				end
				resetBinding()
				return nil
			end
			current = result
		else
			current = initialDefinition
		end
		if current == nil then
			return nil
		end
		if spec.content then
			local contentScope = owner.createChild()
			local ok, body = pcall(function()
				local result = Compose.withOwner(contentScope, function()
					return spec.content(contentScope, current.data)
				end)
				assert(
					result == nil
						or (
							type(result) == "table"
							and type(result.class) == "string"
							and (type(UI[result.class]) == "function" or (result.class == "Component" and result.meta and type(
								result.meta.build
							) == "function"))
							and type(result.props) == "table"
						),
					"UI.Alert: content must return a blueprint or nil"
				)
				return result
			end)
			if not ok then
				lastError = tostring(body)
				if type(warn) == "function" then
					warn("Facet " .. lastError)
				end
				contentScope.dispose()
				resetBinding()
				return nil
			end
			current.content, current.contentScope = body, contentScope
		end
		local initial = if current.cancel and contract.enabledNow(current.cancel.enabled)
			then current.cancel.id
			else nil
		if initial == nil then
			for _, action in current.actions do
				if action.role ~= "destructive" and contract.enabledNow(action.enabled) then
					initial = action.id
					break
				end
			end
		end
		local specOk, resolvedTransition = pcall(validateTransition)
		if not specOk then
			lastError = tostring(resolvedTransition)
			if type(warn) == "function" then
				warn("Facet " .. lastError)
			end
			if current ~= nil and current.contentScope ~= nil then
				current.contentScope.dispose()
				current.content, current.contentScope = nil, nil
			end
			resetBinding()
			return nil
		end
		local presentModal = if Facet.surfaces then Facet.surfaces.modal else presenter.presentModal
		handle = presentModal(if Facet.surfaces then buildScreen else blueprint, {
			initialFocus = if initial then { id = initial } else nil,
			outsideTapCancel = false,
			-- the modal open (transitions round 2026-09-12; band 2026-09-13): it
			-- SETTLES DOWN from 1.015 with a fade on the way in — the text-safe
			-- direction, see `ALERT_MATERIALIZE_SCALE` — and DIPS OUT to the ratified
			-- 0.96 on the way back, faster than it came, on the `dismiss` class.
			-- `plate = "fades"` is MERGED IN rather than defaulted, so a caller
			-- who overrides the form still gets the acknowledgement the shape
			-- needs — the Card IS this surface's plate, and the backdrop the
			-- backdrop-before-content gate is about is the presenter's scrim
			-- behind the whole modal (`blueprint_schema`'s TRANSITION_PLATES
			-- header). A caller who writes `plate` themselves keeps their value.
			transition = resolvedTransition,
		})
		local opened = handle
		handle.scope.own(function()
			if handle == opened then
				handle = nil
				closing = true
				resetBinding()
				closing = false
			end
		end)
		if spec.isPresented then
			spec.isPresented:set(true)
		end
		return handle
	end
	owner.own(function()
		disposed = true
		dismiss()
	end)
	if bound then
		local desired = ownedFormula(Compose.currentOwner(), function(use)
			return (spec.isPresented == nil or use(spec.isPresented)) and (source == nil or read(source, use) ~= nil)
		end)
		local function sync(want)
			if disposed or closing then
				return
			end
			if want then
				present()
			elseif handle then
				dismiss()
			end
		end
		owner.watchStatic(desired, sync)
		sync(desired:peek())
	end
	local function dump()
		return {
			schema = "facet-alert-dump/1",
			lastError = lastError,
			id = spec.id or "Alert",
			presented = handle ~= nil,
			actionCount = if current then #current.actions else 0,
			severity = if current then current.severity else spec.severity or "automatic",
		}
	end
	return table.freeze({
		blueprint = blueprint,
		present = present,
		dismiss = dismiss,
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	})
end
function alert.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end
return alert
