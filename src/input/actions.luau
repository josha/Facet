--!strict
-- Input action pipeline (design §9.1/9.2, UI-INPUT-001/003/004): engine-free
-- model of contexts, typed actions, and bindings that mirrors the ENGINE
-- semantics measured in the 2026-07-19 Studio spike exactly:
--   * real device input resolves through context arbitration: highest-priority
--     enabled context bound to that device input wins; Sink=true consumes it;
--   * a Scriptable binding fires ITS action directly and BYPASSES arbitration
--     (spike T3) — same behavior here so headless tests cannot overclaim;
--   * a disabled/destroyed context never fires; firing an orphaned scriptable
--     binding is a silent no-op (spike T6a).
-- The Roblox adapter (client-only) maps this 1:1 onto InputContext/
-- InputAction/InputBinding; per ADR-0004 arbitration itself is re-verified
-- with real injected input at engine gates.

local actions = {}

export type ActionType = "Bool" | "Direction1D" | "Direction2D" | "ViewportPosition"

function actions.newSystem(core: any)
	local system = {}
	local contexts: { any } = {}

	local function newAction(context: any, name: string, actionType: ActionType)
		local action = {
			name = name,
			type = actionType,
			context = context,
			state = core:signal(if actionType == "Bool" then false else nil),
			pressedHandlers = {} :: { (any) -> () },
			releasedHandlers = {} :: { (any) -> () },
			bindings = {} :: { any },
		}

		-- THE HANDLER IS HANDED THE VALUE (api-architecture-consistency F-29).
		-- `_deliver` has always called `fn(value)`; the declared arity said
		-- otherwise, so the boolean a Bool action delivers was invisible to the
		-- type-checker and to the docs. Same class as `renderer` `onNodeTap`.
		function action.onPressed(fn: (value: any) -> ()): () -> ()
			table.insert(action.pressedHandlers, fn)
			return function()
				local i = table.find(action.pressedHandlers, fn)
				if i then
					table.remove(action.pressedHandlers, i)
				end
			end
		end

		function action.onReleased(fn: (value: any) -> ()): () -> ()
			table.insert(action.releasedHandlers, fn)
			return function()
				local i = table.find(action.releasedHandlers, fn)
				if i then
					table.remove(action.releasedHandlers, i)
				end
			end
		end

		-- internal: deliver a state update (deduplicated like the engine)
		function action._deliver(value: any)
			if not context.enabled or context.destroyed then
				return
			end
			local previous = action.state:get()
			if previous == value then
				return
			end
			action.state:set(value)
			if action.type == "Bool" then
				local handlers = if value == true then action.pressedHandlers else action.releasedHandlers
				for _, fn in table.clone(handlers) do
					fn(value)
				end
			end
		end

		-- binding: keyCode (arbitrated) | scriptable (direct) | uiButton tag.
		-- direction maps a key to a Direction1D value (engine composite keys).
		function action.bind(spec: {
			keyCode: string?,
			scriptable: boolean?,
			uiButton: string?,
			displayName: string?,
			direction: number?,
		})
			local binding = {
				action = action,
				keyCode = spec.keyCode,
				scriptable = spec.scriptable == true,
				uiButton = spec.uiButton,
				displayName = spec.displayName,
				direction = spec.direction,
			}
			table.insert(action.bindings, binding)
			-- scriptable test path: fires the action DIRECTLY (engine truth)
			function binding.fire(value: any)
				if binding.removed or action.context.destroyed then
					return -- silent no-op, spike T6a
				end
				action._deliver(value)
			end
			function binding.remove()
				binding.removed = true
				local i = table.find(action.bindings, binding)
				if i then
					table.remove(action.bindings, i)
				end
			end
			return binding
		end

		-- axis binding: an analog device axis (e.g. a thumbstick) drives a
		-- Direction1D action through a deadzone/threshold LATCH — crossing
		-- ±threshold emits ONE step; the axis must re-center BELOW the release
		-- threshold before it re-arms (no autorepeat storm). This is the
		-- headless AUTHORITY for D-pad-as-Thumbstick1 tolerance (matrix §D.5);
		-- the Roblox adapter realizes it against IAS as best the engine allows
		-- (roblox_input.luau) and the engine's own quantization is a Studio-drive
		-- rider. `component` picks x or y off a 2D axis; `invert` negates the sign.
		function action.bindAxis(spec: {
			axis: string,
			component: ("x" | "y")?,
			threshold: number?,
			releaseThreshold: number?,
			invert: boolean?,
		})
			local threshold = spec.threshold or 0.5
			local binding = {
				action = action,
				axis = spec.axis,
				component = spec.component or "y",
				threshold = threshold,
				releaseThreshold = spec.releaseThreshold or threshold * 0.7,
				invert = spec.invert == true,
				isAxis = true,
				armed = true, -- ready to fire on the next threshold crossing
			}
			table.insert(action.bindings, binding)
			-- process one axis sample; returns the value to deliver, or nil for
			-- "no state change" (held past threshold, or inside the hysteresis
			-- band). Mutates the latch (`armed`).
			function binding._sample(x: number, y: number): number?
				if binding.removed or action.context.destroyed then
					return nil
				end
				local v = if binding.component == "x" then x else y
				if binding.invert then
					v = -v
				end
				local mag = math.abs(v)
				if mag < binding.releaseThreshold then
					binding.armed = true -- re-centered: re-arm
					return 0 -- return the Direction1D to neutral
				elseif mag >= binding.threshold and binding.armed then
					binding.armed = false -- latch until re-centered
					return if v > 0 then 1 else -1
				end
				return nil -- hysteresis band or held: no delivery
			end
			function binding.remove()
				binding.removed = true
				local i = table.find(action.bindings, binding)
				if i then
					table.remove(action.bindings, i)
				end
			end
			return binding
		end

		-- preferred binding for hint display: first binding matching the
		-- preferred input kind; nil-tolerant per the spike (hints must cope)
		function action.preferredBinding(preferredInput: string): any
			for _, binding in action.bindings do
				if preferredInput == "Touch" and binding.uiButton ~= nil then
					return binding
				end
				if preferredInput ~= "Touch" and binding.keyCode ~= nil then
					return binding
				end
			end
			return nil
		end

		return action
	end

	-- context: { name, priority, sink } — enabled via property, not parenting
	function system.createContext(spec: { name: string, priority: number?, sink: boolean? })
		local context = {
			name = spec.name,
			priority = spec.priority or 1000,
			sink = spec.sink == true,
			enabled = true,
			destroyed = false,
			actions = {} :: { any },
		}
		function context.createAction(name: string, actionType: ActionType)
			local action = newAction(context, name, actionType)
			table.insert(context.actions, action)
			return action
		end
		function context.setEnabled(on: boolean)
			context.enabled = on
			if not on then
				-- engine resets action state when disabled (INFERRED: whether the
				-- engine also fires Released for a key held across a disable is
				-- undocumented; headless resets state without firing handlers)
				for _, action in context.actions do
					if action.type == "Bool" and action.state:get() == true then
						action.state:set(false)
					end
				end
			end
		end
		-- setSink: the ONLY sanctioned way to change Sink after creation. The
		-- headless model would tolerate a bare field write (arbitration re-reads
		-- context.sink), but the Roblox adapter arbitrates through the REAL
		-- InputContext.Sink property — a field write there is dead (platform
		-- verifier P1, 2026-07-21). Both systems expose the same seam.
		function context.setSink(on: boolean)
			context.sink = on
		end
		function context.destroy()
			context.destroyed = true
			context.enabled = false
			for _, action in context.actions do
				action.state:dispose()
				table.clear(action.pressedHandlers)
				table.clear(action.releasedHandlers)
			end
			local i = table.find(contexts, context)
			if i then
				table.remove(contexts, i)
			end
		end
		table.insert(contexts, context)
		return context
	end

	-- modifier state (Phase B, ADR-0008): shift and ctrl/cmd are tracked from
	-- the same device stream so Activate semantics can honor held modifiers
	local MODIFIER_GROUP: { [string]: string } = {
		LeftShift = "shift",
		RightShift = "shift",
		LeftControl = "toggle",
		RightControl = "toggle",
		LeftMeta = "toggle",
		RightMeta = "toggle",
	}
	local modifierKeysDown: { [string]: boolean } = {}

	function system.modifiers(): { shift: boolean, toggle: boolean }
		local state = { shift = false, toggle = false }
		for keyCode, down in modifierKeysDown do
			if down then
				state[MODIFIER_GROUP[keyCode]] = true
			end
		end
		return state
	end

	-- device input entry point (the arbitrated path): keyDown/keyUp resolve to
	-- the highest-priority enabled context bound to that key; Sink consumes.
	function system.deviceKey(keyCode: string, isDown: boolean)
		if MODIFIER_GROUP[keyCode] ~= nil then
			modifierKeysDown[keyCode] = isDown
		end
		local candidates = {}
		for _, context in contexts do
			if context.enabled and not context.destroyed then
				for _, action in context.actions do
					for _, binding in action.bindings do
						if binding.keyCode == keyCode then
							table.insert(candidates, { context = context, action = action, binding = binding })
						end
					end
				end
			end
		end
		table.sort(candidates, function(a, b)
			return a.context.priority > b.context.priority
		end)
		local consumedPriority: number? = nil
		for _, candidate in candidates do
			if consumedPriority ~= nil and candidate.context.priority < consumedPriority then
				break -- sunk by a higher-priority context
			end
			local value: any
			if candidate.action.type == "Bool" then
				value = isDown
			else
				-- Direction1D via composite key mapping; key-up returns to 0
				value = if isDown then candidate.binding.direction or 0 else 0
			end
			candidate.action._deliver(value)
			if candidate.context.sink then
				consumedPriority = candidate.context.priority
			end
		end
	end

	-- device AXIS entry point (the arbitrated analog path): drives every axis
	-- binding on `axisName` through its latch, in priority order, with the SAME
	-- Sink arbitration as deviceKey (a higher-priority sink context consumes the
	-- axis so lower screens never navigate while covered).
	function system.deviceAxis(axisName: string, x: number, y: number)
		local candidates = {}
		for _, context in contexts do
			if context.enabled and not context.destroyed then
				for _, action in context.actions do
					for _, binding in action.bindings do
						if binding.isAxis and binding.axis == axisName then
							table.insert(candidates, { context = context, action = action, binding = binding })
						end
					end
				end
			end
		end
		table.sort(candidates, function(a, b)
			return a.context.priority > b.context.priority
		end)
		local consumedPriority: number? = nil
		for _, candidate in candidates do
			if consumedPriority ~= nil and candidate.context.priority < consumedPriority then
				break -- sunk by a higher-priority context
			end
			local value = candidate.binding._sample(x, y)
			if value ~= nil then
				candidate.action._deliver(value)
			end
			if candidate.context.sink then
				consumedPriority = candidate.context.priority
			end
		end
	end

	return system
end

return actions
