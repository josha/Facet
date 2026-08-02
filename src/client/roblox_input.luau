--!strict
-- Roblox Input Action System adapter (design §9.1; CLIENT-ONLY): implements
-- the same action-system interface as src/input/actions.luau over real
-- InputContext/InputAction/InputBinding instances, so the presenter runs
-- unchanged on either. Engine facts from the 2026-07-19 spike are honored:
--   * scriptable bindings need Type=Scriptable and Fire() drives the action
--     directly (bypasses arbitration) — same as the headless model;
--   * arbitration (priority/Sink) is the ENGINE's job here — this adapter
--     never re-implements it (ADR-0004 split harness);
--   * InputAction:Fire()/GetState() are deprecated — never used.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local roblox_input = {}

function roblox_input.newSystem(core: any)
	local host = Players.LocalPlayer:WaitForChild("PlayerScripts")
	local system = {}

	-- modifier state (Phase B parity with the headless system): read live from
	-- the device so Activate meta carries held shift / ctrl / cmd
	function system.modifiers(): { shift: boolean, toggle: boolean }
		local function down(keyCode: Enum.KeyCode): boolean
			return UserInputService:IsKeyDown(keyCode)
		end
		return {
			shift = down(Enum.KeyCode.LeftShift) or down(Enum.KeyCode.RightShift),
			toggle = down(Enum.KeyCode.LeftControl)
				or down(Enum.KeyCode.RightControl)
				or down(Enum.KeyCode.LeftMeta)
				or down(Enum.KeyCode.RightMeta),
		}
	end

	function system.createContext(spec: { name: string, priority: number?, sink: boolean? })
		local contextInstance = Instance.new("InputContext")
		contextInstance.Name = spec.name
		contextInstance.Priority = spec.priority or 1000
		contextInstance.Sink = spec.sink == true
		contextInstance.Parent = host

		local context = {
			name = spec.name,
			priority = contextInstance.Priority,
			sink = contextInstance.Sink,
			enabled = true,
			destroyed = false,
			actions = {} :: { any },
			instance = contextInstance,
		}

		function context.createAction(name: string, actionType: string)
			local actionInstance = Instance.new("InputAction")
			actionInstance.Name = name
			actionInstance.Type = (Enum.InputActionType :: any)[actionType]
			actionInstance.Parent = contextInstance

			local action = {
				name = name,
				type = actionType,
				context = context,
				state = core:signal(if actionType == "Bool" then false else 0),
				bindings = {} :: { any },
				instance = actionInstance,
				connections = {} :: { RBXScriptConnection },
				pressedHandlers = {} :: { (any) -> () },
				releasedHandlers = {} :: { (any) -> () },
			}
			table.insert(
				action.connections,
				actionInstance.StateChanged:Connect(function(value)
					action.state:set(value)
				end)
			)
			table.insert(
				action.connections,
				actionInstance.Pressed:Connect(function()
					for _, fn in table.clone(action.pressedHandlers) do
						fn(true)
					end
				end)
			)
			table.insert(
				action.connections,
				actionInstance.Released:Connect(function()
					for _, fn in table.clone(action.releasedHandlers) do
						fn(false)
					end
				end)
			)

			function action.onPressed(fn: (any) -> ()): () -> ()
				table.insert(action.pressedHandlers, fn)
				return function()
					local i = table.find(action.pressedHandlers, fn)
					if i then
						table.remove(action.pressedHandlers, i)
					end
				end
			end
			function action.onReleased(fn: (any) -> ()): () -> ()
				table.insert(action.releasedHandlers, fn)
				return function()
					local i = table.find(action.releasedHandlers, fn)
					if i then
						table.remove(action.releasedHandlers, i)
					end
				end
			end

			function action.bind(spec2: {
				keyCode: string?,
				scriptable: boolean?,
				uiButton: any?,
				displayName: string?,
				direction: number?,
			})
				local bindingInstance = Instance.new("InputBinding")
				if spec2.scriptable then
					bindingInstance.Type = Enum.InputBindingType.Scriptable
				elseif spec2.keyCode then
					-- Direction1D composite keys map through Up/Down (engine
					-- composite properties); plain Bool uses KeyCode.
					-- ENGINE TRUTH (verified live 2026-07-19, Place1 probe): the
					-- composite slots are named by AXIS SIGN — a key in the `Up`
					-- slot emits +1, a key in `Down` emits -1 — NOT by which
					-- arrow key they hold. Our bind spec's `direction` IS the
					-- axis sign the action must emit, so direction>0 -> Up slot.
					if action.type == "Direction1D" and spec2.direction ~= nil then
						if spec2.direction > 0 then
							(bindingInstance :: any).Up = (Enum.KeyCode :: any)[spec2.keyCode]
						else
							(bindingInstance :: any).Down = (Enum.KeyCode :: any)[spec2.keyCode]
						end
					else
						bindingInstance.KeyCode = (Enum.KeyCode :: any)[spec2.keyCode]
					end
				end
				if spec2.uiButton ~= nil then
					(bindingInstance :: any).UIButton = spec2.uiButton
				end
				if spec2.displayName ~= nil then
					bindingInstance.DisplayName = spec2.displayName
				end
				bindingInstance.Parent = actionInstance

				local binding = {
					action = action,
					keyCode = spec2.keyCode,
					scriptable = spec2.scriptable == true,
					uiButton = spec2.uiButton,
					displayName = spec2.displayName,
					direction = spec2.direction,
					instance = bindingInstance,
				}
				function binding.fire(value: any)
					if binding.removed or context.destroyed then
						return
					end
					-- engine truth: only Scriptable bindings may Fire
					pcall(function()
						bindingInstance:Fire(value)
					end)
				end
				function binding.remove()
					binding.removed = true
					bindingInstance:Destroy()
					local i = table.find(action.bindings, binding)
					if i then
						table.remove(action.bindings, i)
					end
				end
				table.insert(action.bindings, binding)
				return binding
			end

			-- axis binding (matrix §D.5, UI-PARADIGM-003): the headless system
			-- (src/input/actions.luau) owns the AUTHORITATIVE deadzone/re-center
			-- LATCH. Engine realization (platform verification 2026-07-21): the
			-- DOCUMENTED analog surface is `InputBinding.KeyCode = Thumbstick1`
			-- on a **Direction2D** action — the Direction1D composite slots do
			-- NOT accept an analog axis (Left/Right do not even apply to
			-- Direction1D; create.roblox.com/docs/input/input-action-system). So
			-- each axis binding creates a COMPANION Direction2D action in the
			-- same context (inherits enable/priority/sink), and a client-side
			-- latch mirroring the headless one converts the analog stream into
			-- the same discrete presses the composite D-pad path produces.
			--   STUDIO-DRIVE / PHYSICAL RIDER: real analog delivery (and the
			--   DevForum-reported IAS Thumbstick1 binding bug) are UNVERIFIABLE
			--   headlessly/synthetically in Studio (docs/lessons/synthetic-
			--   gamepad-unreachable.md). Confirm on a real console/detected pad.
			function action.bindAxis(spec2: {
				axis: string,
				component: ("x" | "y")?,
				threshold: number?,
				releaseThreshold: number?,
				invert: boolean?,
			})
				local component = spec2.component or "y"
				local threshold = spec2.threshold or 0.5
				local releaseThreshold = spec2.releaseThreshold or threshold * 0.7
				local invert = spec2.invert == true

				local axisAction: any = Instance.new("InputAction")
				axisAction.Name = `{action.name}__axis_{component}`
				axisAction.Type = Enum.InputActionType.Direction2D
				axisAction.Parent = contextInstance
				local bindingInstance = Instance.new("InputBinding")
				pcall(function()
					bindingInstance.KeyCode = (Enum.KeyCode :: any)[spec2.axis]
				end)
				bindingInstance.Parent = axisAction

				-- latch: one discrete step per threshold crossing; the stick must
				-- re-center below releaseThreshold before the next step re-arms
				local latched = 0
				local stateConn = axisAction.StateChanged:Connect(function(value)
					local sample = if typeof(value) == "Vector2"
						then (if component == "x" then value.X else value.Y)
						else 0
					if component == "y" then
						sample = -sample -- engine +Y is up; screen direction is +down
					end
					if invert then
						sample = -sample
					end
					local dir = if sample >= threshold then 1 elseif sample <= -threshold then -1 else 0
					if dir ~= 0 and latched == 0 then
						latched = dir
						action.state:set(dir)
						for _, fn in table.clone(action.pressedHandlers) do
							fn(true)
						end
						action.state:set(0)
						for _, fn in table.clone(action.releasedHandlers) do
							fn(false)
						end
					elseif latched ~= 0 and math.abs(sample) <= releaseThreshold then
						latched = 0
					end
				end)
				table.insert(action.connections, stateConn)

				local binding = {
					action = action,
					axis = spec2.axis,
					component = component,
					threshold = threshold,
					releaseThreshold = releaseThreshold,
					invert = invert,
					isAxis = true,
					instance = bindingInstance,
					axisInstance = axisAction,
				}
				function binding.remove()
					binding.removed = true
					stateConn:Disconnect()
					local ci = table.find(action.connections, stateConn)
					if ci then
						table.remove(action.connections, ci)
					end
					axisAction:Destroy() -- destroys its binding child too
					local i = table.find(action.bindings, binding)
					if i then
						table.remove(action.bindings, i)
					end
				end
				table.insert(action.bindings, binding)
				return binding
			end

			function action.preferredBinding(preferredInput: string): any
				-- engine PreferredBinding when available; nil-tolerant fallback
				local enginePreferred = actionInstance.PreferredBinding
				if enginePreferred ~= nil then
					for _, binding in action.bindings do
						if binding.instance == enginePreferred then
							return binding
						end
					end
				end
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

			table.insert(context.actions, action)
			return action
		end

		function context.setEnabled(on: boolean)
			context.enabled = on
			contextInstance.Enabled = on
		end

		-- setSink: runtime Sink changes MUST reach the engine instance — the
		-- responder model raises Sink on engage() and lowers it on resign()
		-- (ADR-0014); a bare context.sink field write never reaches
		-- InputContext.Sink (platform verifier P1, 2026-07-21)
		function context.setSink(on: boolean)
			context.sink = on
			contextInstance.Sink = on
		end

		function context.destroy()
			context.destroyed = true
			context.enabled = false
			for _, action in context.actions do
				for _, connection in action.connections do
					connection:Disconnect()
				end
				action.state:dispose()
				table.clear(action.pressedHandlers)
				table.clear(action.releasedHandlers)
			end
			contextInstance:Destroy()
		end

		return context
	end

	return system
end

return roblox_input
