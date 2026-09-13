--!strict
-- Brief modal decisions. Reuses Facet's layout, controls, themes and presenter;
-- the optional binding/data forms change ownership, not the input/layout engine.
local guard = require("../spec_guard")
local contract = require("../class_contract")
local coreContract = require("../core/contract")
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
	return type(value) == "table" and (value.kind == "signal" or value.kind == "memo")
end

--[[ THE MODAL SETTLES DOWN INTO PLACE, IT DOES NOT GROW INTO IT (owner report
	A1, 2026-09-13: "the alert's text pops after it opens").

	MEASURED, live: Roblox rasterizes text at `floor(TextSize x effectiveScale)`,
	so the ratified 0.96 -> 1 materialize paints every string on this card ONE
	WHOLE PIXEL SMALL for the entire flight — TextBounds 127.5x19 at 0.96 and at
	0.9999999 alike — and snaps to 133.5x20 the instant the scale reaches exactly
	1. The channel holds its `UIScale` until the spring settles, so on a live
	frame-by-frame probe the card stopped moving at 0.50 s and the title jumped
	5% wider at 0.78 s: a re-flow on a card that had been still for a quarter of
	a second, which is precisely what was reported.

	1.015 IS THE NUMBER AND IT IS DERIVED, not chosen: the band [1, 1 + 1/n)
	floors to the same pixel for text of size n, and 1/0.015 = 66 px is above
	every size this framework can paint (the neutral ladder's largest is `title`
	24, x1.5 at a ten-foot display = 36, plus the engine's largest preferred-text
	offset of 14 = 50, with headroom for a package that authors a taller ladder).
	So the card eases DOWN from 1.5% over, the type never re-rasterizes, and the
	text lands at its final rect on the first painted frame.

	`plate = "fades"` is the acknowledgement the shape needs (see
	`acknowledgePlate`); the `dismiss` exit still dips out faster than it came. ]]
local ALERT_MATERIALIZE_SCALE = 1.015
local DEFAULT_TRANSITION = table.freeze({ enter = "materialize", plate = "fades", scale = ALERT_MATERIALIZE_SCALE })

-- `resolve`'s own detail begins lower-case ("unknown enter form …"), so the
-- address needs its colon or the two run together (review N5)
local function transitionRefusal(err: any): string
	local detail = string.gsub(tostring(err), "^Facet transition: ", "")
	return `Controls.Alert: transition: {detail} — the modal materializes by default; `
		.. 'pass `{ enter = "instant" }` to opt out.'
end

--[[ THE CARD IS THIS SURFACE'S PLATE, and the modal says so (task 7 item 3).
	Merged, never overwritten: a caller's own `plate` is their call, and a
	declaration that already makes the claim is passed through by IDENTITY. A
	form that never fades (`instant`, a pure slide) records nothing either way,
	so the key costs it nothing. ]]
local function mergePlate(value: any): any
	if type(value) ~= "table" or value.plate ~= nil then
		return value
	end
	local merged = table.clone(value)
	merged.plate = "fades"
	return merged
end

--[[ ...AND A READABLE TRANSITION IS NOT AN EXCEPTION (review N3). The first
	shape of this returned a Readable untouched — "there is no table here to
	merge into" — so a caller who bound their transition to a signal got no
	acknowledgement, recorded `via = "surface"`, and the reference-app sweeps
	counted their modal. A Readable has a VALUE, and a memo is the framework's
	own way to derive one from it; owned on the alert's scope, so it dies with
	the control.

	THIS MEMO NEVER RAISES. A Facet memo QUARANTINES a body that errors — measured
	while building this: the refusal was recorded as a warning, the memo then read
	as nothing, and what reached the caller was `resolve`'s own unaddressed
	message from one layer down. So validation lives at the READ (see
	`validateTransition` below), where it can refuse cleanly; the memo does one
	job, merging the acknowledgement.

	`false` is the framework's own "no transition" spelling on `When`/`ForEach`,
	and the present site's `or` already folded it to the default — only the
	build check disagreed, refusing a value the next line ignored. It folds
	here, in one place, on both paths. ]]
local function acknowledgePlate(core: any, scope: any, declared: any): any
	if declared == nil or declared == false then
		return DEFAULT_TRANSITION
	end
	if isReadableTransition(declared) then
		return scope:own(core:memo(function(use)
			local value = use(declared)
			if value == nil or value == false then
				return DEFAULT_TRANSITION
			end
			return mergePlate(value)
		end))
	end
	return mergePlate(declared)
end
local chromeSlots = require("../tokens/chrome_slots")
local alert = {}
type Text = string | coreContract.Readable<string>
export type Action = {
	id: string,
	label: Text,
	compactLabel: Text?,
	role: ("default" | "cancel" | "destructive")?,
	enabled: (boolean | coreContract.Readable<boolean>)?,
	shortcut: ("defaultAction" | "cancelAction" | { keyCode: string, modifiers: { shift: boolean? }? })?,
	onActivate: ((any?) -> ())?,
}
export type Spec = {
	id: string?,
	title: (Text | ((any) -> Text))?,
	message: (Text | ((any) -> Text))?,
	actions: ({ Action } | ((any) -> { Action }))?,
	isPresented: coreContract.Signal<boolean>?,
	presenter: any?,
	presenting: any?,
	item: coreContract.Signal<any>?,
	error: any?,
	icon: Text?,
	severity: ("automatic" | "standard" | "critical")?,
	suppression: { isSuppressed: coreContract.Signal<boolean>, label: Text? }?,
	content: ((any, any?) -> any)?,
	env: any?,
	maxWidth: (number | string)?,
	padding: (number | string)?,
	surface: string?,
	-- the modal's own enter/exit (transitions round 2026-09-12); default is the
	-- materialize fade-and-grow, and `{ enter = "instant" }` opts out
	transition: any?,
}
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
--[[ ACTION PLACEMENT IS ROLE-DRIVEN, NOT AUTHORED (the platform alert convention).
	A row puts the cancel action on the LEADING side; a stack puts it at the
	BOTTOM, with the most likely action on top. Author order is preserved among
	the remaining actions. The stack is used when there are more than two actions,
	on a compact width, on a ten-foot display (a television stacks every alert), and at an
	accessibility text preference (the engine's Larger/Largest steps, where phones
	stacks its alert buttons too); otherwise the actions share one centered row.
	Pure and exported so a caller can predict the form and an order without
	mounting anything. ]]
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
function alert.build(Facet: any, core: any, spec: Spec)
	guard.assertKnownKeys("Controls.Alert", spec, KEYS, "spec")
	local UI = Facet.UI
	local env = surfaceEnv.resolve(
		"Controls.Alert",
		spec.id or "Alert",
		core,
		spec.env,
		"action placement adapts to the width class and viewing distance"
	)
	local sizeClass, distanceProfile, textOffset =
		env:get("sizeClass"), env:get("distanceProfile"), env:get("preferredTextOffset")
	local function read(v, use)
		return if UI.isReadable(v) then (if use then use(v) else v:get()) else v
	end
	local function textValue(v, name, optional, factory)
		assert(
			(optional and v == nil)
				or type(v) == "string"
				or (UI.isReadable(v) and type(v:get()) == "string")
				or (factory and type(v) == "function"),
			"Controls.Alert: "
				.. name
				.. " must be a string or Readable<string>"
				.. (if factory then " or data factory" else "")
		)
	end
	local function signal(v, name)
		assert(type(v) == "table" and v.kind == "signal", "Controls.Alert: " .. name .. " must be a settable Signal")
	end
	textValue(spec.title, "title", spec.error ~= nil, true)
	textValue(spec.message, "message", true, true)
	textValue(spec.icon, "icon", true, false)
	assert(
		spec.severity == nil
			or spec.severity == "automatic"
			or spec.severity == "standard"
			or spec.severity == "critical",
		"Controls.Alert: severity must be automatic, standard or critical"
	)
	assert(
		spec.content == nil or type(spec.content) == "function",
		"Controls.Alert: content must be a scoped blueprint factory"
	)
	assert(
		spec.maxWidth == nil
			or type(spec.maxWidth) == "string"
			or (type(spec.maxWidth) == "number" and spec.maxWidth > 0 and spec.maxWidth < math.huge),
		"Controls.Alert: maxWidth must be positive finite pixels or a metric name"
	)
	assert(
		spec.padding == nil
			or type(spec.padding) == "string"
			or (type(spec.padding) == "number" and spec.padding >= 0 and spec.padding < math.huge),
		"Controls.Alert: padding must be nonnegative finite pixels or a metric name"
	)
	assert(spec.surface == nil or type(spec.surface) == "string", "Controls.Alert: surface must be a string")
	--[[ VALIDATED AS EARLY AS THE VALUE ALLOWS (review D8 — this used to claim
		"not on the first `present()`", which stopped being true for half the
		shapes). An invalid `transition` used to reach `transitions.resolve`
		inside `presentModal`, which raises a message naming "Facet transition"
		and nothing that points back at this spec — and for a BOUND alert
		(`isPresented`/`item`) that call runs inside an observer, outside every
		pcall this control has, so the whole failure read as "the dialog never
		opened".

		A STATIC declaration is judged HERE, where it was authored. A READABLE one
		cannot be — its build-time value is not the value the alert will open on
		— so it is judged on its first read, in `present()`, and a refusal there
		takes the same recorded-and-reset exit as the content and dynamic-data
		failures beside it rather than raising into an observer. Either way
		`resolve` is the one authority on the shape: this calls IT rather than
		growing a second, drifting copy of the rule, and only re-addresses the
		message. A bare `"instant"` is the case worth naming in the text: the
		round's own design note invited it, and the schema wants
		`{ enter = "instant" }`. ]]
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
	assert(
		spec.id == nil or (type(spec.id) == "string" and spec.id ~= ""),
		"Controls.Alert: id must be a nonempty string"
	)
	assert(
		not (spec.item ~= nil and (spec.presenting ~= nil or spec.error ~= nil or spec.isPresented ~= nil)),
		"Controls.Alert: item is an alternative to isPresented/presenting/error"
	)
	assert(
		not (spec.presenting ~= nil and spec.error ~= nil),
		"Controls.Alert: presenting and error are alternative data sources"
	)
	if spec.isPresented ~= nil then
		signal(spec.isPresented, "isPresented")
		assert(type(spec.isPresented:get()) == "boolean", "Controls.Alert: isPresented must hold a boolean")
	end
	if spec.item ~= nil then
		signal(spec.item, "item")
	end
	if spec.suppression ~= nil then
		guard.assertKnownKeys(
			"Controls.Alert suppression",
			spec.suppression,
			guard.keySet({ "isSuppressed", "label" }),
			"spec"
		)
		signal(spec.suppression.isSuppressed, "suppression.isSuppressed")
		assert(
			type(spec.suppression.isSuppressed:get()) == "boolean",
			"Controls.Alert: isSuppressed must hold a boolean"
		)
		textValue(spec.suppression.label, "suppression.label", true, false)
	end
	local source = if spec.item ~= nil then spec.item elseif spec.error ~= nil then spec.error else spec.presenting
	local automaticError = spec.error ~= nil
		and type(spec.error) == "table"
		and spec.error.kind == "signal"
		and spec.isPresented == nil
	local bound = spec.isPresented ~= nil or spec.item ~= nil or automaticError
	assert(
		not bound or (type(spec.presenter) == "table" and type(spec.presenter.presentModal) == "function"),
		"Controls.Alert: a presentation binding requires presenter"
	)
	local function actionsValue(value)
		assert(
			value == nil or (type(value) == "table" and not UI.isReadable(value)),
			"Controls.Alert: actions must be an array or data factory"
		)
		if value ~= nil then
			for key in value do
				assert(
					type(key) == "number" and key >= 1 and key <= #value and key % 1 == 0,
					"Controls.Alert: actions must be a dense array"
				)
			end
		end
		local list = if value == nil or #value == 0 then DEFAULT_ACTIONS else value
		local ids, cancel = {}, nil
		for _, a in list do
			guard.assertKnownKeys("Controls.Alert action", a, ACTION_KEYS, "spec")
			assert(
				type(a.id) == "string" and a.id ~= "" and not a.id:find("/", 1, true) and ids[a.id] == nil,
				"Controls.Alert: each action needs a unique nonempty id without slashes"
			)
			textValue(a.label, "action.label", false, false)
			textValue(a.compactLabel, "action.compactLabel", true, false)
			assert(
				a.role == nil or a.role == "default" or a.role == "cancel" or a.role == "destructive",
				"Controls.Alert: action role must be default, cancel or destructive"
			)
			assert(
				a.enabled == nil or type(read(a.enabled)) == "boolean",
				"Controls.Alert: action enabled must be boolean or Readable<boolean>"
			)
			assert(
				a.onActivate == nil or type(a.onActivate) == "function",
				"Controls.Alert: action onActivate must be a function"
			)
			assert(
				a.shortcut == nil
					or a.shortcut == "defaultAction"
					or a.shortcut == "cancelAction"
					or type(a.shortcut) == "table",
				"Controls.Alert: shortcut must be defaultAction, cancelAction or a Button shortcut"
			)
			if type(a.shortcut) == "table" then
				shortcut.validate(a.shortcut)
			end
			if a.role == "cancel" then
				assert(cancel == nil, "Controls.Alert: only one cancel action is allowed")
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
				"Controls.Alert: error needs a user-facing errorDescription"
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
	local scope = core:scope("alert-" .. (spec.id or "Alert"))
	-- resolved ONCE, not per present: a Readable declaration becomes one memo on
	-- this scope rather than a fresh one every time the modal opens
	local declaredTransition = acknowledgePlate(core, scope, spec.transition)
	--[[ A READABLE'S CHECK, ON THE READ (review N5). The static form was judged
		at build above; a Readable cannot be, so it is judged here — the first
		read is `present()`, and raising HERE rather than inside the memo is what
		keeps the message addressed to Alert (a memo that errors is quarantined,
		and `resolve`'s own message surfaces from one layer down instead). Cheap:
		one `resolve` on a value the coordinator is about to resolve anyway. For a
		BOUND alert this still fires inside the observer that opened it — a value
		nobody can see until it is read leaves nowhere earlier to say so. ]]
	local function validateTransition(): any
		if isReadableTransition(spec.transition) then
			local ok, err = pcall(transitionsLib.resolve, declaredTransition)
			if not ok then
				error(transitionRefusal(err), 0)
			end
		end
		return declaredTransition
	end
	local handle, presenter, current = nil, spec.presenter, initialDefinition
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
	local function card(branchScope)
		local def = current or definition()
		if def == nil then
			return nil
		end
		if spec.content then
			assert(
				def.contentScope ~= nil and not def.contentScope:isDisposed() and not def.contentMounted,
				"Controls.Alert: custom content requires present() or a presentation binding; do not mount blueprint directly"
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
		table.insert(
			header,
			UI.Text({
				id = "Title",
				text = def.title,
				disclose = true,
				textSize = "heading",
				textAlign = "center",
				width = UI.fill(),
				tint = if def.severity == "critical" then { role = "danger", blend = 1 } else nil,
			})
		)
		table.insert(
			content,
			UI.HStack({ id = "Header", width = UI.fill(), gap = "s", align = "center", children = header })
		)
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
			branchScope:own(def.contentScope)
		end
		if def.content then
			table.insert(content, def.content)
		end
		if spec.suppression then
			local toggle = branchScope:own(Facet.Controls.Toggle(core, {
				id = "Suppression",
				value = spec.suppression.isSuppressed,
				label = spec.suppression.label or "Do not ask again",
				presentation = "checkbox",
			}))
			table.insert(content, toggle.blueprint)
		end
		local function actionButton(action, itemScope)
			local bp
			if action.shortcut ~= nil then
				bp = itemScope:own(Facet.Controls.Button(core, {
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
				})).blueprint
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
				props.surface = if action.role == "default" then "accent" else nil
				return Facet.contribution.attach(UI.Button(props), Facet.contribution.read(bp))
			end
			return UI.Button({
				id = action.id,
				label = action.label,
				compactLabel = action.compactLabel,
				enabled = action.enabled,
				role = if action.role == "destructive" then "destructive" else nil,
				surface = if action.role == "default" then "accent" else nil,
				height = { type = "minMax", min = "targetSizes.minimum" },
				--[[ A CUT ACTION LABEL KEEPS A ROUTE TO ITS WHOLE STRING (task 7
					item 6's consequence, closed the way the large-text sweep's
					last open gap was — a one-line button label declaring the
					accessibility plate, which is what every segment of a sliding
					strip now does; the ledger of those gaps and their closures
					lives in `tests/lib/large_text_fixtures.luau`). A one-word
					label cannot wrap, so when the card's own carved frame narrows
					the stack — measured: `fantasy-parchment`'s panel contentInsets
					take 19 px a side, so a 390 px phone at the Largest preference
					gives "Continue" 288 px of Fondamento instead of 326 —
					the engine must ellipsize it, and an ACTION is the least
					optional text on the screen. `disclose` is the framework's
					answer for exactly this shape (`UI.Button{ disclose = true }`,
					which every segment of a sliding strip now declares); it
					reserves nothing while the label fits.

					BOTH BRANCHES, or neither (review N2): the shortcut branch
					above rebuilds its props and has to restate this one. ]]
				disclose = true,
			})
		end
		-- One keyed region, two orders: a mode flip MOVES the mounted actions
		-- (identity, focus and shortcuts survive) rather than remounting them.
		local stacked = branchScope:own(core:memo(function(use)
			return alert.resolveStacked(#def.actions, use(sizeClass), use(distanceProfile), use(textOffset))
		end))
		local rowOrder, stackOrder = alert.orderActions(def.actions, false), alert.orderActions(def.actions, true)
		local function mode(row, stack)
			return branchScope:own(core:memo(function(use)
				return if use(stacked) then stack else row
			end))
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
		--[[ THE CARD IS A PLATE THAT HAPPENS TO SCROLL (task 7 item 6). It is a
			`ScrollView` so a long message on a short screen stays reachable, and
			`chrome_slots.classify` answers by CLASS before it reads `surface` —
			so `raised` never got a look in and the modal card classified as a
			scroll TRACK under every skinned package: no carved frame, no
			hairline, no shadow, no contentInsets. The hint is the channel
			classify's own header describes for exactly this ("a control that
			declares its own slot knows something the generic surface/class map
			cannot infer"), and it outranks both rules. The CLASS rule itself is
			untouched: an unhinted `ScrollView` is still a scrollbar, which is
			right for RadialMenu's list and every example. ]]
		return chromeSlots.attachHint(
			UI.ScrollView({
				id = "Card",
				axis = "y",
				width = { type = "hug", max = spec.maxWidth or "controls.alert.maxWidth" },
				height = UI.hug(),
				alignH = "center",
				alignV = "center",
				padding = spec.padding or "m",
				gap = "s",
				surface = spec.surface or "raised",
				children = content,
			}),
			{ slot = "panel" }
		)
	end
	local content = if dynamic
		then UI.When({ id = "Decision", condition = scope:own(core:signal(true)), thenView = card })
		else card(scope)
	local actionPrefix = "/"
		.. (spec.id or "Alert")
		.. "/Center/"
		.. (if dynamic then "Decision/then/" else "")
		.. "Card/Actions/Order/["
	local blueprint = Facet.contribution.attach(
		UI.Screen({
			id = spec.id or "Alert",
			padding = "m",
			children = {
				-- the FADE GROUP the materialize transition needs (picker_menu's own
				-- popover shape): the whole modal fades/scales in as one plate
				-- rather than piece by piece
				UI.ZStack({
					id = "Center",
					canvasGroup = true,
					width = UI.fill(),
					height = UI.fill(),
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
	local function present(target)
		assert(not disposed, "Controls.Alert: cannot present a disposed alert")
		if handle then
			return handle
		end
		presenter = target or presenter
		assert(
			type(presenter) == "table" and type(presenter.presentModal) == "function",
			"Controls.Alert: present requires a presenter"
		)
		if dynamic then
			local ok, result = pcall(definition)
			if not ok then
				lastError = tostring(result)
				if type(warn) == "function" then
					warn("Facet Alert: " .. lastError)
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
			local contentScope = core:scope("alert-content")
			local ok, body = pcall(function()
				local result = spec.content(contentScope, current.data)
				assert(
					result == nil
						or (
							type(result) == "table"
							and type(result.class) == "string"
							and type(UI[result.class]) == "function"
							and type(result.props) == "table"
						),
					"Controls.Alert: content must return a blueprint or nil"
				)
				return result
			end)
			if not ok then
				lastError = tostring(body)
				if type(warn) == "function" then
					warn("Facet Alert: " .. lastError)
				end
				contentScope:dispose()
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
		--[[ THE TRANSITION'S OWN REFUSAL TAKES THE SAME EXIT AS EVERY OTHER
			PRESENT-TIME FAILURE (review D2). A Readable transition can only be
			judged when it is read (review N5), and for a BOUND alert
			(`isPresented`/`item`) that read happens inside the observer that
			opened it — where a raise is quarantined: `isPresented` stayed true
			while `dump().presented` said false and `lastError` said nothing, so
			the dialog "silently never opened" all over again, which is the exact
			failure task 7 item 5 existed to remove. It now lands where the
			content and dynamic-data failures above already land: recorded on
			`lastError`, warned, binding reset, `nil` returned. ]]
		local specOk, resolvedTransition = pcall(validateTransition)
		if not specOk then
			lastError = tostring(resolvedTransition)
			if type(warn) == "function" then
				warn("Facet Alert: " .. lastError)
			end
			if current ~= nil and current.contentScope ~= nil then
				current.contentScope:dispose()
				current.content, current.contentScope = nil, nil
			end
			resetBinding()
			return nil
		end
		handle = presenter.presentModal(blueprint, {
			initialFocus = if initial then { id = initial } else nil,
			outsideTapCancel = false,
			-- the modal open (transitions round 2026-09-12): scale 0.96 → 1 with a
			-- fade, and the default `dismiss` exit dips out faster than it came.
			-- `plate = "fades"` is MERGED IN rather than defaulted, so a caller
			-- who overrides the form still gets the acknowledgement the shape
			-- needs — the Card IS this surface's plate, and the backdrop the
			-- backdrop-before-content gate is about is the presenter's scrim
			-- behind the whole modal (`blueprint_schema`'s TRANSITION_PLATES
			-- header). A caller who writes `plate` themselves keeps their value.
			transition = resolvedTransition,
		})
		local opened = handle
		handle.scope:own(function()
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
	scope:own(function()
		disposed = true
		dismiss()
	end)
	if bound then
		local desired = scope:own(core:memo(function(use)
			return (spec.isPresented == nil or use(spec.isPresented)) and (source == nil or read(source, use) ~= nil)
		end))
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
		scope:own(core:observe(desired, sync))
		sync(desired:get())
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
			scope:dispose()
		end,
	})
end
return alert
