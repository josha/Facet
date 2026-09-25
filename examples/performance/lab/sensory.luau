--!strict
return function(ctx)
	local Compose, Host, UI, T = ctx.Facet.Compose, ctx.Host, ctx.UI, ctx.types
	local enabled, readout = Compose.cell(false), Compose.cell("Haptics off; no effects constructed")
	local anchor = Host.Frame({ Size = T.UDim2.new(1, 0, 1, -80), Position = T.UDim2.fromOffset(0, 80) })
	local counters =
		{ enabled = false, built = 0, requests = 0, presses = 0, physicalOutputMeasured = false, arms = {} }
	local state = { counters = counters }
	function state.build()
		return Host.Frame({
			Size = T.UDim2.fromScale(1, 1),
			UI.Toggle "PerformanceHaptics" { label = "Request native haptics", value = enabled },
			UI.Text({ text = readout, Position = T.UDim2.fromOffset(0, 40), Size = T.UDim2.new(1, 0, 0, 40) }),
			anchor,
		})
	end
	function state.setEnabled(value)
		enabled:set(value)
	end
	function state.step()
		counters.enabled = enabled:peek()
		counters.built, counters.requests, counters.presses, counters.arms = 0, 0, 0, {}
		for _, name in { "undeclared", "undeclaredRepeat", "sharedEffect", "perLeafEffect" } do
			local arm = { rows = 120, pressesDriven = 0, effectsBuilt = 0, requests = 0 }
			local presses = {}
			local started = os.clock()
			local stop = ctx.runtime.mount(function()
				local function effect()
					arm.effectsBuilt += 1
					local node = Host.HapticEffect({ Type = T.Enum.HapticEffectType.UIClick })
					Compose.cleanup(function()
						node:Stop()
					end)
					return node
				end
				local shared = if counters.enabled and name == "sharedEffect" then effect() else nil
				local children =
					{ Size = T.UDim2.fromScale(1, 1), Host.UIGridLayout({ CellSize = T.UDim2.fromOffset(100, 40) }) }
				if shared then
					table.insert(children, shared)
				end
				for index = 1, 120 do
					local feedback = if counters.enabled and name == "perLeafEffect" then effect() else shared
					local function activate()
						arm.pressesDriven += 1
					end
					presses[index] = function()
						activate()
						if feedback then
							feedback:Play()
							arm.requests += 1
						end
					end
					local properties = {
						label = `Control {index}`,
						onActivate = activate,
						PressHapticEffect = if feedback then Compose.static(feedback) else nil,
					}
					if feedback and feedback ~= shared then
						table.insert(properties, feedback)
					end
					table.insert(children, UI.Button(properties))
				end
				return Host.ScrollingFrame(children)
			end, anchor)
			arm.mountMs = (os.clock() - started) * 1000
			started = os.clock()
			for index = 1, 8 do
				presses[index]()
			end
			arm.pressMs = (os.clock() - started) * 1000
			stop()
			counters.arms[name] = arm
			counters.built += arm.effectsBuilt
			counters.requests += arm.requests
			counters.presses += arm.pressesDriven
		end
		readout:set(
			`{counters.presses} presses · {counters.built} effects built · {counters.requests} playback requests · physical output unmeasured`
		)
	end
	return state
end
