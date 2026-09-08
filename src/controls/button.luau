--!strict
local guard = require("../spec_guard")
local contract = require("../class_contract")
local selection = require("../selection_model")
local contribution = require("../input/contribution")
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
	if spec.shortcut then
		guard.assertKnownKeys("Button.shortcut", spec.shortcut, guard.keySet({ "keyCode", "modifiers" }), "shortcut")
		assert(
			type(spec.shortcut.keyCode) == "string" and spec.shortcut.keyCode ~= "",
			"Button: shortcut requires keyCode"
		)
		if spec.shortcut.modifiers ~= nil then
			guard.assertKnownKeys(
				"Button.shortcut",
				spec.shortcut.modifiers,
				guard.keySet({ "shift" }),
				"shortcut.modifiers"
			)
			assert(
				spec.shortcut.modifiers.shift == nil or type(spec.shortcut.modifiers.shift) == "boolean",
				"Button: shortcut shift modifier must be boolean"
			)
		end
		assert(
			spec.shortcut.keyCode ~= "Escape" and spec.shortcut.keyCode ~= "Tab",
			"Button: Escape and Tab retain engine and navigation ownership"
		)
	end
	local UI = Facet.UI
	local scope = core:scope("button")
	local id = spec.id or "Button"
	local disposed = false
	local rootNode, inputScope, system, clock
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
	local motionReady = scope:own(core:signal(false))
	local contexts = {}
	local keysWired = false
	local busy = scope:own(core:memo(function(use)
		return selection.read(spec.busy, use) == true
	end))
	local showProgress = scope:own(core:memo(function(use)
		return use(busy) and use(motionReady)
	end))
	local enabled = scope:own(core:memo(function(use)
		return contract.enabledIn(use, spec.enabled) and not use(busy)
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
		if not system or not inputScope or not rootNode or inputScope.priority() == 0 or keysWired then
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
	local children = spec.children or { UI.Text({ id = "Label", text = spec.label or "", textSize = "control" }) }
	local content = table.clone(children)
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
	local blueprint = UI.Button({
		id = id,
		label = spec.label or "",
		enabled = enabled,
		role = spec.role,
		width = spec.width,
		height = spec.height,
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
			rootNode = node
			wireKeys()
			if not available() then
				stop()
			end
		end,
		bindActionSystem = function(s)
			system = s
		end,
		bindInputScope = function(s)
			inputScope = s
			s.onDispose(function()
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
			motionReady:set(true)
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
			busy = busy:get(),
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
