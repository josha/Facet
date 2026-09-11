--!strict
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
	"children",
	"enabled",
	"busy",
	"onActivate",
	"repeatDelay",
	"repeatInterval",
	"shortcut",
	"dialogAction",
	"role",
	"width",
	"height",
	"image",
	"imageAspectRatio",
	"imageFraming",
	"subtitle",
	"row",
})
function button.build(Facet, core, spec)
	guard.assertKnownKeys("Controls.Button", spec, KEYS, "spec")
	assert(type(spec.onActivate) == "function", "Button: onActivate must be a function")
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
		"Button.row cannot combine with children or image"
	)
	local imageForm = spec.image ~= nil
	assert(not imageForm or spec.children == nil, "Button.image and children are alternative content forms")
	assert(
		imageForm or (spec.subtitle == nil and spec.imageAspectRatio == nil and spec.imageFraming == nil),
		"Button.subtitle, imageAspectRatio and imageFraming require image"
	)
	assert(
		not imageForm or (type(selection.read(spec.label)) == "string" and selection.read(spec.label) ~= ""),
		"Button.image requires a nonempty label"
	)
	local ratio = spec.imageAspectRatio or 16 / 9
	assert(
		type(ratio) == "number" and ratio > 0 and ratio < math.huge,
		"Button.imageAspectRatio must be positive and finite"
	)
	local UI = Facet.UI
	local scope = core:scope("button")
	local id = spec.id or "Button"
	local disposed = false
	local rootNode, inputScope, system, clock
	local graph, paintAllowed, controller, hoverOff, bindImageMotion
	local env = if imageForm then surfaceEnv.find(core) else nil
	local focused = if imageForm then scope:own(core:signal(false)) else nil
	local hovered = if imageForm then scope:own(core:signal(false)) else nil
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
	local motionReady = if canBeBusy then scope:own(core:signal(false)) else nil
	local contexts = {}
	local keysWired = false
	local busy = spec.busy
	local showProgress = if canBeBusy
		then scope:own(core:memo(function(use)
			return selection.read(busy, use) == true and use(motionReady)
		end))
		else nil
	local enabled = scope:own(core:memo(function(use)
		return contract.enabledIn(use, spec.enabled) and selection.read(busy, use) ~= true
	end))
	local function available()
		return not disposed and enabled:get() and not contract.isDisabled(rootNode)
	end
	local function stop()
		hold = nil
		elapsed = 0
		hasRepeated = false
	end
	scope:own(function()
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
	scope:own(core:observe(enabled, function(on)
		if not on then
			stop()
		end
	end))
	local function activate(_, meta)
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
		spec.onActivate(meta)
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
						or not hold.state:get()
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
		scope:own(inputScope.onTick(tick))
		tick(0)
	end
	local function syncFocus()
		if focused then
			focused:set(
				rootNode ~= nil
					and graph ~= nil
					and graph.focused:get() == rootNode.path
					and (paintAllowed == nil or paintAllowed:get() ~= false)
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
	local children = spec.children or { UI.Text({ id = "Label", text = spec.label or "", textSize = "control" }) }
	local content = if spec.row
		then menuRecipe.semantic(UI, core, scope, spec.label, spec.row)
		else table.clone(children)
	if canBeBusy then
		table.insert(
			content,
			UI.When({
				id = "Busy",
				condition = showProgress,
				thenView = function(branchScope)
					local progress = Facet.Controls.ProgressView(
						core,
						{ id = "Progress", presentation = "spinner", scope = branchScope, motionClock = clock }
					)
					-- ProgressView normally fills a row. Inside a content-sized button,
					-- measure its intrinsic dots so the button reserves their full width.
					return UI.frame(progress.blueprint, { minWidth = 0 })
				end,
			})
		)
	end
	if imageForm then
		-- Reserve the maximum transform once; focus changes only paint. The same
		-- envelope works at any authored width, including responsive grid columns.
		local lift = 1.05
		local active = scope:own(core:memo(function(use)
			local classes = if env then use(env:get("interactionClasses")) else nil
			return use(enabled) and (use(focused) or (use(hovered) and classes ~= nil and classes.primary == "pointer"))
		end))
		local targetScale = scope:own(core:memo(function(use)
			return if use(active) and (not env or use(env:get("motionPolicy")) ~= "reduced") then lift else 1
		end))
		local scale = scope:own(core:signal(targetScale:get()))
		local liftMotion
		bindImageMotion = function()
			if liftMotion or not clock then
				return
			end
			-- Reuse the shared interruptible object spring. A scale needs tighter
			-- precision than pixel motion, or the terminal write visibly snaps.
			liftMotion = scope:own(clock:spring(scale:get(), "object", { eps = 0.00001 }))
			scope:own(core:observe(liftMotion, function()
				scale:set(math.clamp(liftMotion:get(), 1, lift))
			end))
		end
		scope:own(core:observe(targetScale, function(target)
			if liftMotion then
				liftMotion:setTarget(target)
			else
				scale:set(target)
			end
		end))
		local stroke = scope:own(core:memo(function(use)
			return if use(active)
				then UI.strokeData({ color = "accent", thickness = "focusRing", transparency = 0 })
				else nil
		end))
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
	local blueprint = UI.Button({
		id = id,
		label = spec.label or "",
		enabled = enabled,
		role = spec.role,
		width = spec.width or (if imageForm or spec.row then UI.fill() else nil),
		surface = if imageForm then "plain" else nil,
		focusVisual = if imageForm then "none" else nil,
		height = spec.height or (if spec.row then { type = "minMax", min = "targetSizes.minimum" } else nil),
		children = content,
		gap = "s",
		align = "center",
		onActivate = activate,
		onPointerDown = if repeating
			then function()
				return start("pointer")
			end
			else nil,
		onPointerUp = if repeating
			then function()
				stop()
			end
			else nil,
		onPointerCancel = if repeating
			then function()
				suppressTap = false
				stop()
			end
			else nil,
		onPointerMove = if repeating
			then function(path, pos, rectOf)
				local r = rectOf(path)
				if not r or pos.x < r.x or pos.x > r.x + r.w or pos.y < r.y or pos.y > r.y + r.h then
					suppressTap = false
					stop()
				end
			end
			else nil,
	})
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
				scope:own(core:observe(g.focused, syncFocus))
				if allowed then
					scope:own(core:observe(allowed, syncFocus))
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
		bindMotion = function(c)
			clock = c
			if bindImageMotion then
				bindImageMotion()
			end
			if motionReady then
				motionReady:set(true)
			end
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
			enabled = enabled:get(),
			repeating = hold ~= nil,
			dialogAction = spec.dialogAction,
		}
	end
	return {
		blueprint = blueprint,
		dump = dump,
		dispose = function()
			scope:dispose()
		end,
	}
end
return button
