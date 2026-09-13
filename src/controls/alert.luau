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
	So the card SETTLES DOWN ON THE WAY IN, from 1.5% over: the type never
	re-rasterizes and the text lands at its final rect on the first painted frame.

	IT STILL DIPS OUT. The band answers a question about the instant the text
	ARRIVES and is read, and an exit is the opposite instant — the plate is leaving,
	it is already fading, and a swell there is neither what the shape asks for nor
	what the band is for. `render/transitions.luau`'s `absentFor` spends `scale` on
	the ENTER alone, so the exit keeps the ratified dip to `MATERIALIZE_SCALE`, on
	the faster `dismiss` class it always had.

	`plate = "fades"` is the acknowledgement the shape needs (see
	`acknowledgePlate`). ]]
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
	so the key costs it nothing.

	…AND THE TEXT-SAFE BAND IS MERGED THE SAME WAY (RED-TEAM F8). `scale` is not a
	taste this control happens to hold — it is the answer to an ENGINE fact about
	the type on this card (see `ALERT_MATERIALIZE_SCALE`), and it is true of every
	alert, not only of the ones that took the default. A caller who writes
	`transition = { enter = "materialize" }` to change the motion CLASS was not
	asking for their title to re-flow a beat after it settled, so they get the band
	too; a caller who writes a `scale` of their own has said something about it and
	keeps it, exactly as they keep their own `plate`. Only the scaling form is
	touched: nothing else reads the key, and writing it onto a slide would be a
	claim about a channel that form does not drive. ]]
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
local themeSnapshot = require("../themes/snapshot")
local textMetrics = require("../layout/text_metrics")
local textFit = require("../layout/text_fit")
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
--[[ ...AND A ROW THAT CANNOT HOLD ITS OWN LABELS IS NOT A ROW (owner ruling A5,
	2026-09-13: "a modal's action label must never be cut").

	The rungs above are all CATEGORICAL — a width class, a viewing distance, a text
	preference — and every one of them is a proxy for the question that actually
	decides the form: does the widest arrangement of these labels fit the width
	this card has. Measured on the LT-8 fixture, the proxies miss it in both
	directions: on a 1280 desktop at the default preference, "Permanently delete
	this saved progress" beside "Keep the previous checkpoint" asked for 802 px of
	a 528 px card and simply ran out of it, while a phone's compact class stacks
	alerts whose labels would have fitted a row twice over.

	So the measured answer joins them, as an OR rather than a replacement: the
	platform conventions still hold (a television stacks; a phone stacks; more than
	two actions stack), and a row that does not fit now stacks as well. Pure, and
	exported beside the rest, so a caller can predict the form from numbers it
	already has. ]]
function alert.rowFits(labelWidths: { number }, chromeX: number, gap: number, available: number): boolean
	if #labelWidths == 0 then
		return true
	end
	local need = gap * (#labelWidths - 1)
	for _, w in labelWidths do
		need += w + chromeX
	end
	--[[ `math.huge <= math.huge` IS TRUE, AND IT IS NOT A FIT (R9, 2026-09-13).
		A label nobody can measure is charged `math.huge` precisely so it cannot fit;
		an `available` of `math.huge` would then have answered YES to the row — the
		one form that can cut — on the exact inputs the charge exists to refuse. An
		infinite need never fits, whatever the offer. ]]
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
	local themeMetrics, viewportRect, platformChrome =
		env:get("themeMetrics"), env:get("viewportRect"), env:get("platformChrome")
	--[[ ═══ THE CARD'S OWN WIDTH, FROM THE FACTS IT IS BUILT OUT OF (A5) ═══
		Two callers need it and they must not disagree: the card's PADDING (which
		yields to the carved frame rather than stacking with it) and the action
		row's BUDGET (which decides the form). Both are derived here, in one
		function, from the published facts — never re-measured from a solved rect,
		which does not exist when the form has to be chosen. ]]
	local function cardSpend(metrics: any): any
		--[[ THE CARD'S PADDING YIELDS TO THE PANEL'S CARVED FRAME, IT DOES NOT
			STACK WITH IT (owner ruling A5.1). `render/layout_node.luau` ADDS a
			slot's `chromeInsets` to whatever padding a node already carries, which
			is right in general — a Button's theme padding and its skin's border are
			two different reservations. On this card they are the SAME one: the
			carved frame IS the modal's inner margin, and paying for it twice took
			35 px a side out of a 390 px phone under Fantasy Parchment, leaving
			"Continue" 288 px of Fondamento where 326 would have fitted it. So the
			authored step is spent only where the art does not already cover it.
			A flat package carves nothing and this is the identity. ]]
		local art = if type(metrics) == "table" and type(metrics.chromeInsets) == "table"
			then (metrics.chromeInsets :: any).panel
			else nil
		local authored = themeSnapshot.resolveNumber(metrics, spec.padding or "m") or 0
		--[[ ...BUT NEVER TO NOTHING. A carved frame's inset is where its ART ends,
			not where a line of type wants to start: spending exactly it put the
			message flush against Fantasy Parchment's painted border (live capture,
			2026-09-13). One `xs` is kept inside the frame whatever it carves — the
			smallest step the package itself declares, so a denser theme keeps a
			denser gap — and it costs 4 px a side of the 34 this yield gives back. ]]
		local floor = math.min(authored, themeSnapshot.resolveNumber(metrics, "xs") or 0)
		local function side(name: string): number
			local carved = if type(art) == "table" and type((art :: any)[name]) == "number"
				then (art :: any)[name]
				else 0
			return math.max(floor, authored - carved)
		end
		return { top = side("top"), right = side("right"), bottom = side("bottom"), left = side("left") }
	end
	--[[ the width the ACTIONS are laid out inside: the card's box less what both
		halves of its frame spend on each side. The card is `hug` capped at
		`maxWidth`, so its widest possible box is that cap or the screen it sits in,
		whichever is smaller — the conservative side of the two, which is the side a
		"does this fit" question must be answered on. ]]
	local function actionsWidth(use: any): number
		local metrics = use(themeMetrics)
		local vp = use(viewportRect)
		local chrome = use(platformChrome)
		local insets = if type(chrome) == "table" then (chrome :: any).insets else nil
		local screenW = (if type(vp) == "table" and type(vp.w) == "number" then vp.w else 0)
			- (if type(insets) == "table" then (insets.left or 0) + (insets.right or 0) else 0)
		-- the Screen this control mounts declares `padding = "m"` (see `blueprint`)
		local screenPad = themeSnapshot.resolveNumber(metrics, "m") or 0
		--[[ AN UNRESOLVABLE CAP IS NOT AN INFINITE ONE (NEW-2). `math.huge` was the
			first fallback and it reads as "this card may be as wide as it likes",
			which is the direction that keeps a row nothing can hold. A card can never
			be wider than the screen it is centred in, so the screen is the honest
			ceiling when the metric cannot be resolved — and under a healthy package
			the `min` below takes the cap anyway, so nothing moves on the path every
			real theme takes. ]]
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
		--[[ IT DOES NOT SUBTRACT THE BLEED LANE, and that is a known approximation
			rather than an oversight (latent, noted 2026-09-13). Where a package
			carves, the lane is netted to nothing and there is nothing to subtract;
			where it does not, the lane is `max(m, bleed) - m` wider than this
			estimate says — and `buttonChromeX` over-charges by about as much, since
			a Button's own carved inset is counted in full while the solver may yield
			part of it. The two err in opposite directions on the same packages. If
			either is ever made exact, the other has to be, or the rung starts
			answering a question about a card nobody is drawing. ]]
		return math.max(0, card - pad.left - pad.right - artX)
	end
	-- the natural width of one action label, at the size and face a Button will
	-- actually draw it — `text_metrics` is the solver's own measurer, not a copy
	local function labelWidth(metrics: any, facts: any, label: string): number
		local _, role = themeSnapshot.effectiveTypeRole(metrics, "Button", nil)
		local size = textMetrics.reservedSize(
			if type(role) == "table" and type(role.size) == "number" then role.size else 16,
			facts.scale,
			facts.offset
		)
		local font = if type(role) == "table" then role.fontKey else nil
		--[[ A FONT THIS MEASURER CANNOT KEY ON IS NO MEASUREMENT AT ALL, AND THE
			SAFE ANSWER IS "IT DOES NOT FIT" (RED-TEAM F2; direction corrected by
			NEW-2). `text_metrics.measure` keys its caches on the font DESCRIPTOR,
			and a `themeMetrics` fact is whatever an adapter or a fixture pushed — a
			partial table has no `type` section, so `effectiveTypeRole` answers no
			role and the descriptor is nil. Raising here quarantines the memo that
			asked and lands on `lastError` for a screen that used to render clean.

			IT REPORTS `math.huge`, NOT ZERO. Zero was the first answer and it is the
			WRONG direction: a label of no width always fits, so the degraded rung
			picked the ROW — the one form of the two that can put a button outside
			the card (measured on `themeMetrics = {}` with two long labels: 331 px
			of overflow). A label nobody can measure is charged as "does not fit",
			which stacks; a stack is full-width by construction and cannot overflow
			the box it is stacked in. Every fallback in this rung errs the same way,
			toward the form that cannot cut. ]]
		if type(font) ~= "string" then
			return math.huge
		end
		local lineHeight = if type(role) == "table" then role.lineHeight else nil
		return textMetrics.measure(label, font, size, math.huge, lineHeight, 1).width
	end
	-- ...plus the chrome one Button spends around it, and the gap a row puts
	-- between two of them
	local function buttonChromeX(metrics: any): number
		local sizes = if type(metrics) == "table" then (metrics :: any).controlSizes else nil
		local regular = if type(sizes) == "table" then (sizes :: any).regular else nil
		local padX = if type(regular) == "table" and type(regular.paddingX) == "number" then regular.paddingX else 0
		local art = if type(metrics) == "table" and type(metrics.chromeInsets) == "table"
			then (metrics.chromeInsets :: any).control
			else nil
		local artX = if type(art) == "table" then (art.left or 0) + (art.right or 0) else 0
		return padX * 2 + artX
	end
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
		--[[ THE HEADER IS THE TITLE, AND A MARK ONLY WHEN ONE IS CALLED FOR (owner
			report A3 and its addendum, 2026-09-13). With no mark the title's own
			text is CENTRED IN THE CARD — one full-width centred line, the way the
			message under it always has been. With a mark, the mark LEADS the title
			and the pair is centred AS A UNIT: both hug and the row distributes them
			to the centre, so the line reads from the mark rather than from the middle
			of whatever width was left over. (A `fill` title beside an icon centred
			its text in the REMAINDER, which put the line visibly right of the card's
			centre by half the mark.) ]]
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
		--[[ THE TITLE HUGS ON BOTH PATHS (RED-TEAM F12). The marked path had to hug
			— that is what lets the mark and the line centre as one unit — and the
			unmarked one was left on `fill`, which is the declaration that made this
			card's WIDTH follow its content. A hugging ScrollView asks its children
			what they want; a `fill` child answers "whatever I am given", so a lone
			67-character title reported the width of its longest WORD and the card
			collapsed to 92 px around a one-line 60 px title. Hugging, the title asks
			for the line it wants, the card grows to the cap, and the line wraps
			inside it. `textAlign` still differs, and only that: an unmarked title
			centres its own glyphs in the box it hugged to, which IS the card's
			centre because the row centres it. ]]
		local marked = #header > 0
		--[[ A BLANK TITLE IS NO TITLE (NEW-5; made reactive by R2). A hugging Text
			asks for the width of what it DRAWS, and whitespace draws nothing: `" "`
			measured 0x24 and the containment guard reported a visible node with zero
			width — correctly, it IS one. `""` is the same box under a different
			spelling, so the two are folded.

			TWO RUNGS, BECAUSE ONE OF THEM CAN BE ANSWERED FOR FREE. A literal blank
			is known here, so it mounts NOTHING — no node and (with no mark) no row
			either, which is the whole of R7: an empty `Header` still cost a `gap`,
			8 px of dead space above the message. A READABLE title cannot be judged
			at build — it is blank now, or it goes blank three frames from now when
			the caller's signal changes — so that one mounts and binds `hidden`,
			which is the framework's own spelling for "this view is not to be drawn"
			and the one the solver's hidden verdict, the hit walk and `hiddenRoots`
			all already follow. It reserves its slot; a node that has to be able to
			come BACK cannot give the slot up without a structural region, and a
			structural region would move every alert's title path for the sake of a
			degenerate case. ]]
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
						then branchScope:own(core:memo(function(use)
							return blank(use(def.title))
						end))
						else nil,
					tint = if def.severity == "critical" then { role = "danger", blend = 1 } else nil,
				})
			)
		end
		-- an empty row is not a row: it would still spend the content stack's gap
		-- (R7), which is 8 px of nothing above the message
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
				--[[ ...AND NOT THE CONTROL'S OWN CONTENT ALIGNMENT (A5, 2026-09-13).
					`Controls.Button` declares `align = "center"` on its blueprint for
					its own content stack; cloned onto the alert's action it became a
					cross-axis intent of the action's OWN, and the stacked form's
					`align = "stretch"` then passed it by — so the primary action, the
					one every `defaultAction`/`cancelAction` takes this branch for,
					was the ONE button in a full-width stack that hugged its label
					(measured: 184 px beside 322). The plain branch below declares no
					`align` at all, and these two must present identically. ]]
				props.align = nil
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
		--[[ THE FORM IS MEASURED, NOT ONLY CLASSIFIED (A5). The categorical rungs
			still hold — a television stacks, a phone stacks, three actions stack, a
			text preference stacks — and the labels themselves now get a vote, which
			is the vote that decides whether one gets CUT. `disclose` stays on the
			buttons underneath all of this as the last resort it was meant to be: a
			label that does not fit even a full-width stacked button at the largest
			preference.

			WHAT THIS MEMO IS, AND IS NOT (RED-TEAM F9). It is decided from the
			WIDTHS AT OPEN — the labels, the theme, the viewport and the text
			preference as they are when the card is built, re-derived whenever any of
			those facts moves. It is NOT re-decided from the solve: nothing here reads
			an arranged rect, so a calibration pass, a text-measure epoch or a
			settled font cannot flip the form under a player mid-read. The one
			consequence worth naming is the direction of its error, and it is the
			direction of the FORM rather than of any one number: every fallback below
			it errs toward "does not fit" — an unmeasurable label is charged
			`math.huge`, an unresolvable width cap falls back to the screen the card
			is centred in rather than to infinity — so a wrong answer OVER-STACKS. A
			stack is full width by construction and cannot put a button outside the
			card; a row can, and did, when these two erred the other way (NEW-2).

			AND IT MEASURES WHAT THE BUTTON WILL ACTUALLY DRAW — WHICH IS THE FULL
			LABEL, EVEN WHERE A `compactLabel` EXISTS (RED-TEAM F11, MEASURED AND
			DECLINED). The review's rule was `math.min(label, compactLabel)`: an
			action carrying a short form has already said the short form is
			acceptable, so charge the row for that. It is true of a box the solver
			NARROWS — the compact ladder swaps the string in when the offer is
			narrower than the natural width — and false of this one. An alert's row is
			an `AdaptiveStack` of HUGGING buttons: nothing ever offers them less than
			they ask for, so the ladder never engages and the full string is what gets
			drawn.

			MEASURED on the gallery's own `04_confirm_dialog` at 1280 with
			`compactLabel = "Delete"`: charging the compact width kept the row, and the
			button then drew "Permanently delete this saved progress" at 449 px inside
			a 528 px content box beside a 91 px Cancel — 12 px of button OUTSIDE the
			card's right edge, with nothing truncated to show for it. The stack it
			replaced overflowed by nothing at all. So the compact form is not spent
			here, and a caller who supplies one still gets the reflow that keeps their
			label inside the card. If the row is ever taught to narrow its buttons,
			this is the line that changes with it. ]]
		local stacked = branchScope:own(core:memo(function(use)
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
				-- the carved frame IS this card's inner margin, so the authored step
				-- is spent only where the art does not already cover it (`cardSpend`)
				padding = branchScope:own(core:memo(function(use)
					return cardSpend(use(themeMetrics))
				end)),
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
