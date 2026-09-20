--!strict
local Compose = require("../vendor/compose/core")
local guard = require("../spec_guard")
local contract = require("../class_contract")
local selection = require("../selection_model")
local contribution = require("../input/contribution")
local surfaceEnv = require("../env/surface_env")
local menuRecipe = require("./menu_recipe")
local shortcut = require("./button_shortcut")
local button = {}
local KEYS = guard.keySet({
	"id",
	"label",
	"compactLabel",
	"children",
	"enabled",
	"busy",
	"onActivate",
	"repeatDelay",
	"repeatInterval",
	"shortcut",
	"dialogAction",
	"role",
	"surface",
	"selected",
	"gap",
	"align",
	"width",
	"height",
	"shrinkWeight",
	"focusable",
	"image",
	"imageAspectRatio",
	"imageFraming",
	"subtitle",
	"row",
	"pop",
	"help",
	"icon",
	"shape",
	"textSize",
	"padding",
	"hidden",
	"anchor",
	"alignH",
	"alignV",
	"margin",
	"offsetX",
	"offsetY",
	"zIndex",
	"layoutPriority",
	"traversalPriority",
	"gridSpan",
	"disclose",
	"onAppear",
	"onDisappear",
	"onPointerDown",
	"onPointerUp",
	"onPointerCancel",
	"onPointerMove",
})
-- Placement, visibility and lifecycle properties the primitive reads as authored.
local PASSTHROUGH = {
	"hidden",
	"anchor",
	"alignH",
	"alignV",
	"margin",
	"offsetX",
	"offsetY",
	"zIndex",
	"layoutPriority",
	"traversalPriority",
	"gridSpan",
	"disclose",
	"onAppear",
	"onDisappear",
}
local POINTER = { "onPointerDown", "onPointerUp", "onPointerCancel", "onPointerMove" }
local function build(Facet, core, spec, owner)
	guard.assertKnownKeys("UI.Button", spec, KEYS, "spec")
	assert(spec.onActivate == nil or type(spec.onActivate) == "function", "Button: onActivate must be a function")
	for _, key in POINTER do
		assert(spec[key] == nil or type(spec[key]) == "function", `Button: {key} must be a function`)
	end
	for _, key in { "enabled", "busy" } do
		local v = selection.read(spec[key])
		assert(v == nil or type(v) == "boolean", `Button: {key} must be boolean or readable boolean`)
	end
	local repeating = spec.repeatInterval ~= nil or spec.repeatDelay ~= nil
	local delay = spec.repeatDelay or 0.4
	local interval = spec.repeatInterval or 0.1
	assert(
		type(delay) == "number" and delay > 0 and delay < math.huge,
		"Button: repeatDelay must be positive finite seconds"
	)
	assert(
		type(interval) == "number" and interval > 0 and interval < math.huge,
		"Button: repeatInterval must be positive finite seconds"
	)
	assert(
		spec.dialogAction == nil or spec.dialogAction == "default" or spec.dialogAction == "cancel",
		"Button: dialogAction must be default | cancel"
	)
	shortcut.validate(spec.shortcut)
	assert(
		spec.row == nil or (spec.children == nil and spec.image == nil),
		"UI.Button.row cannot combine with children or image"
	)
	local imageForm = spec.image ~= nil
	assert(not imageForm or spec.children == nil, "UI.Button.image and children are alternative content forms")
	assert(
		imageForm or (spec.subtitle == nil and spec.imageAspectRatio == nil and spec.imageFraming == nil),
		"UI.Button.subtitle, imageAspectRatio and imageFraming require image"
	)
	assert(
		not imageForm or (type(selection.read(spec.label)) == "string" and selection.read(spec.label) ~= ""),
		"UI.Button.image requires a nonempty label"
	)
	local ratio = spec.imageAspectRatio or 16 / 9
	assert(
		type(ratio) == "number" and ratio > 0 and ratio < math.huge,
		"UI.Button.imageAspectRatio must be positive and finite"
	)
	local UI = Facet.UI
	local id = spec.id or "Button"
	local disposed = false
	local rootNode, inputScope, system
	local graph, paintAllowed, controller, hoverOff
	-- Optional release feedback changes paint only. An interrupted pop
	-- begins at its current scale and settles at one.
	local env = if imageForm or spec.pop then surfaceEnv.find(core) else nil
	local popTimeline = if spec.pop then Facet.runtime.timeline({ duration = 0.45, autoplay = false }) else nil
	local popStart = if popTimeline then Compose.cell(1) else nil
	local popScale
	if popTimeline then
		popTimeline:seek(0.45)
		popScale = Compose.formula(function(use)
			if env and use(env:get("motionPolicy")) == "reduced" then
				return 1
			end
			local phase = use(popTimeline.progress)
			return 1 + (use(popStart) - 1) * (1 - phase) ^ 3 + 0.25 * math.sin(math.pi * phase) * math.exp(-3 * phase)
		end)
		owner.watch(function(use)
			if env and use(env:get("motionPolicy")) == "reduced" then
				popTimeline:pause()
				popTimeline:seek(0.45)
			end
		end)
	end
	local focused = if imageForm then Compose.cell(false) else nil
	local hovered = if imageForm then Compose.cell(false) else nil
	local hold, elapsed, hasRepeated = nil, 0, false
	local suppressTap = false
	local suppressSelectionEcho = false
	local actionKeys = {}
	if spec.shortcut then
		actionKeys[spec.shortcut.keyCode] = true
	end
	local dialogKey = if spec.dialogAction == "default"
		then "Return"
		elseif spec.dialogAction == "cancel" then "ButtonB"
		else nil
	if dialogKey then
		actionKeys[dialogKey] = true
	end
	local canBeBusy = spec.busy == true or UI.isReadable(spec.busy)
	local contexts = {}
	local keysWired = false
	local busy = spec.busy
	local showProgress = if canBeBusy
		then Compose.formula(function(use)
			return selection.read(busy, use) == true
		end)
		else nil
	local enabled = Compose.formula(function(use)
		return contract.enabledIn(use, spec.enabled) and selection.read(busy, use) ~= true
	end)
	local function available()
		return not disposed and enabled:peek() and not contract.isDisabled(rootNode)
	end
	local function stop()
		hold = nil
		elapsed = 0
		hasRepeated = false
	end
	owner.own(function()
		disposed = true
		stop()
		if hoverOff then
			hoverOff()
			hoverOff = nil
		end
		for _, ctx in contexts do
			ctx.destroy()
		end
	end)
	owner.watchStatic(enabled, function(on)
		if not on then
			stop()
		end
	end)
	local function activate(path, meta)
		if not available() then
			return
		end
		if suppressSelectionEcho and meta and (meta.pointer == "gamepad" or meta.pointer == "keyboard") then
			return
		end
		if suppressTap and (meta == nil or meta.source == "pointer") then
			suppressTap = false
			return
		end
		-- THE INITIAL PRESS ONLY (controller ruling): a repeat pulse reaches this
		-- same closure every `repeatInterval` (default 0.1s), well under the
		-- `reward` spring's settle time, so an ungated kick would stack on every
		-- pulse of a held repeating button and never return to rest.
		if meta == nil or meta.source ~= "repeat" then
			if popTimeline and (not env or selection.read(env:get("motionPolicy")) ~= "reduced") then
				popStart:set(popScale:peek())
				popTimeline:restart()
			end
		end
		if spec.onActivate then
			spec.onActivate(path, meta)
		end
	end
	local function start(source)
		if not available() then
			return false
		end
		hold = source
		elapsed = 0
		hasRepeated = false
		suppressTap = false
		return true
	end
	local function wireKeys()
		if keysWired or not system or not inputScope or not rootNode or inputScope.priority() == 0 then
			return
		end
		keysWired = true
		if not repeating and spec.shortcut == nil and spec.dialogAction == nil then
			return
		end
		local function action(name, bindings, priority, eligible, held)
			local ctx = system.createContext({
				name = id .. ":" .. name,
				priority = inputScope.priority() + priority,
				sink = true,
			})
			local a = ctx.createAction(name, "Bool")
			for _, binding in bindings do
				a.bind(binding)
			end
			ctx.setEnabled(false)
			a.onPressed(function()
				if available() and inputScope.available(rootNode.path) and eligible() then
					if held then
						suppressSelectionEcho = true
						start(a)
					end
					inputScope.activate(rootNode.path, { source = "shortcut" })
				end
			end)
			a.onReleased(stop)
			table.insert(contexts, ctx)
			return { ctx = ctx, action = a, eligible = eligible }
		end
		local entries = {}
		if repeating then
			table.insert(
				entries,
				action("Hold", { { keyCode = "Return" }, { keyCode = "Space" }, { keyCode = "ButtonA" } }, 2, function()
					return inputScope.focused() == rootNode.path
				end, true)
			)
		end
		if spec.shortcut and spec.shortcut.keyCode ~= dialogKey then
			table.insert(
				entries,
				action("Shortcut", { spec.shortcut }, 1, function()
					return inputScope.preferred(rootNode.path, spec.shortcut.keyCode)
				end, false)
			)
		end
		if spec.dialogAction then
			table.insert(
				entries,
				action(
					"Dialog",
					{ { keyCode = if spec.dialogAction == "default" then "Return" else "ButtonB" } },
					1,
					function()
						return inputScope.preferred(rootNode.path, dialogKey)
					end,
					false
				)
			)
		end
		local function tick(dt)
			if disposed then
				return
			end
			local can = available() and inputScope.available(rootNode.path)
			for _, entry in entries do
				entry.ctx.setEnabled(can and entry.eligible())
			end
			if hold == nil then
				return
			end
			if
				not can
				or (
					hold ~= "pointer"
					and (
						inputScope.focused() ~= rootNode.path
						or not hold.state:peek()
						or not system.wouldWinArbitration(hold.context, hold.lastBinding)
					)
				)
			then
				stop()
				return
			end
			elapsed += dt
			local threshold = if hasRepeated then interval else delay
			if elapsed >= threshold then
				-- Never replay a backlog after a suspended frame; one current intent per tick.
				elapsed = 0
				hasRepeated = true
				if hold == "pointer" then
					suppressTap = true
				end
				inputScope.activate(rootNode.path, { source = "repeat", pointer = hold == "pointer" })
			end
		end
		owner.own(inputScope.onTick(tick))
		tick(0)
	end
	local function syncFocus()
		if focused then
			focused:set(
				rootNode ~= nil
					and graph ~= nil
					and graph.focused:peek() == rootNode.path
					and (paintAllowed == nil or paintAllowed:peek() ~= false)
			)
		end
	end
	local function attachHover()
		if imageForm and controller and rootNode and not hoverOff then
			hoverOff = controller.attachContextGestures(rootNode.path, {
				onHoverChanged = function(on)
					hovered:set(on)
				end,
			})
		end
	end
	local hasContent = spec.children ~= nil or spec.row ~= nil or canBeBusy or imageForm
	assert(spec.compactLabel == nil or not hasContent, "UI.Button.compactLabel requires a plain text button")
	local content
	if spec.row then
		content = menuRecipe.semantic(UI, spec.label, spec.row)
	elseif hasContent then
		content = if spec.children
			then table.clone(spec.children)
			else { UI.Text({ id = "Label", text = spec.label or "", textSize = "control" }) }
	end
	if canBeBusy then
		table.insert(
			content,
			Compose.show(showProgress, function()
				local progress = Facet.Controls.ProgressView(core, { id = "Progress", presentation = "spinner" })
				return UI.frame(progress.blueprint, { minWidth = 0 })
			end)
		)
	end
	if imageForm then
		-- Reserve the maximum transform once; focus changes only paint. The same
		-- envelope works at any authored width, including responsive grid columns.
		local lift = 1.05
		local active = Compose.formula(function(use)
			local classes = if env then use(env:get("interactionClasses")) else nil
			return use(enabled) and (use(focused) or (use(hovered) and classes ~= nil and classes.primary == "pointer"))
		end)
		local targetScale = Compose.formula(function(use)
			return if use(active) and (not env or use(env:get("motionPolicy")) ~= "reduced") then lift else 1
		end)
		local motion = Facet.runtime.spring(function(use)
			return use(targetScale)
		end, { period = 0.28, damping = 0.85 })
		local function scale(use)
			return if env and use(env:get("motionPolicy")) == "reduced" then 1 else math.clamp(use(motion), 1, lift)
		end
		local stroke = Compose.formula(function(use)
			return if use(active)
				then UI.strokeData({ color = "accent", thickness = "focusRing", transparency = 0 })
				else nil
		end)
		local artwork = UI.Image({
			id = "Artwork",
			image = spec.image,
			imageFraming = spec.imageFraming,
			scaleMode = "crop",
			width = { type = "percent", fraction = 1 / lift },
			height = { type = "aspect", ratio = ratio },
			alignH = "center",
			alignV = "center",
			scale = scale,
			stroke = stroke,
		})
		-- Padding clears the outside ring even at full lift. Root plain chrome
		-- avoids a second decorative control border around image and caption.
		local envelope = UI.ZStack({
			id = "ImageEnvelope",
			width = UI.fill(),
			padding = "s",
			children = {
				-- Size the image plane BEFORE adding border clearance. Applying
				-- the ratio to the padded box steals height from wide artwork.
				UI.aspectRatio(UI.Box({ id = "LiftSpace", width = UI.fill() }), ratio),
				artwork,
			},
		})
		if spec.subtitle ~= nil then
			table.insert(
				content,
				UI.Text({
					id = "Subtitle",
					text = spec.subtitle,
					textSize = "caption",
					role = "secondary",
					width = UI.fill(),
				})
			)
		end
		content = {
			UI.VStack({
				id = "ImageContent",
				width = UI.fill(),
				gap = "xs",
				children = {
					envelope,
					UI.VStack({ id = "Caption", width = UI.fill(), gap = "xs", children = content }),
				},
			}),
		}
	end
	-- The control's own pointer handling runs after the authored handler, and
	-- its answer decides whether the press is held.
	local function pointer(key: string, own: any): any
		local authored = spec[key]
		if authored == nil or own == nil then
			return authored or own
		end
		return function(...)
			authored(...)
			return own(...)
		end
	end
	local props: any = {
		id = id,
		label = spec.label or "",
		compactLabel = spec.compactLabel,
		icon = spec.icon,
		shape = spec.shape,
		textSize = spec.textSize,
		padding = spec.padding,
		enabled = enabled,
		role = spec.role,
		selected = spec.selected,
		help = spec.help,
		width = spec.width or (if imageForm or spec.row then UI.fill() else nil),
		surface = spec.surface or (if imageForm then "plain" else nil),
		focusVisual = if imageForm then "none" else nil,
		height = spec.height or (if spec.row then { type = "minMax", min = "targetSizes.minimum" } else nil),
		shrinkWeight = spec.shrinkWeight,
		focusable = spec.focusable,
		children = content,
		gap = spec.gap or "s",
		align = spec.align or "center",
		scale = popScale,
		onActivate = activate,
		onPointerDown = pointer(
			"onPointerDown",
			if repeating
				then function()
					return start("pointer")
				end
				else nil
		),
		onPointerUp = pointer(
			"onPointerUp",
			if repeating
				then function()
					stop()
				end
				else nil
		),
		onPointerCancel = pointer(
			"onPointerCancel",
			if repeating
				then function()
					suppressTap = false
					stop()
				end
				else nil
		),
		onPointerMove = pointer(
			"onPointerMove",
			if repeating
				then function(path, pos, rectOf)
					local r = rectOf(path)
					if not r or pos.x < r.x or pos.x > r.x + r.w or pos.y < r.y or pos.y > r.y + r.h then
						suppressTap = false
						stop()
					end
				end
				else nil
		),
	}
	for _, key in PASSTHROUGH do
		props[key] = spec[key]
	end
	local blueprint = UI.Button(props)
	blueprint = contribution.attach(blueprint, {
		actionKeys = actionKeys,
		syncGeometry = function(_, node)
			-- A re-mounted blueprint can receive a fresh handle when pooling is off
			-- or the theme changed its recycle key. Hover belongs to that handle.
			if node ~= rootNode then
				if hoverOff then
					hoverOff()
					hoverOff = nil
				end
				rootNode = node
				syncFocus()
			end
			attachHover()
			wireKeys()
			if hold ~= nil and not available() then
				stop()
			end
		end,
		bindController = if imageForm
			then function(c)
				controller = c
				attachHover()
			end
			else nil,
		bindFocusGraph = if imageForm
			then function(g, allowed)
				graph = g
				paintAllowed = allowed
				owner.watchStatic(g.focused, syncFocus)
				if allowed then
					owner.watchStatic(allowed, syncFocus)
				end
				syncFocus()
			end
			else nil,
		bindActionSystem = function(s)
			system = s
		end,
		bindInputScope = function(s)
			inputScope = s
			s.onDispose(function()
				if hoverOff then
					hoverOff()
					hoverOff = nil
				end
				if hovered then
					hovered:set(false)
				end
				for _, ctx in contexts do
					ctx.destroy()
				end
				table.clear(contexts)
				keysWired = false
				stop()
				if inputScope == s then
					inputScope = nil
				end
			end)
		end,
		focusMoved = function(path)
			if rootNode and path ~= rootNode.path then
				stop()
			end
		end,
	})
	local function dump()
		return {
			schema = "facet-button-dump/1",
			id = id,
			busy = selection.read(busy) == true,
			enabled = enabled:peek(),
			repeating = hold ~= nil,
			dialogAction = spec.dialogAction,
		}
	end
	return {
		blueprint = blueprint,
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	}
end
function button.build(Facet, core, spec)
	local parent = Compose.currentOwner()
	local owner = if parent then parent.createChild() else Compose.createOwner()
	local ok, result = pcall(Compose.withOwner, owner, function()
		return build(Facet, core, spec, owner)
	end)
	if not ok then
		owner.dispose()
		error(result, 0)
	end
	return result
end
return button
