--!strict
-- One component runs unchanged in Studio and the headless consumer spec.
-- Local state and subscriptions retire when the presented screen is dismissed.
local screen = {}

screen.PATHS = table.freeze({
	root = "/Consumer",
	title = "/Consumer/Panel/Title",
	blurb = "/Consumer/Panel/Blurb",
	count = "/Consumer/Panel/Readout/Count",
	sound = "/Consumer/Panel/Readout/Sound",
	buttons = "/Consumer/Panel/Buttons",
	bump = "/Consumer/Panel/Buttons/Bump",
	close = "/Consumer/Panel/Buttons/Close",
})

function screen.session(Facet: any, h: any, opts: { closeAfterSeconds: number? }?)
	local UI, Compose = h.controls, Facet.Compose
	local closeAfterSeconds = (opts and opts.closeAfterSeconds) or 120
	local torn = false
	local close, node
	local built: any = {} -- Commands/readbacks for the example's headless driver.
	local function dismiss()
		if close then
			close()
		end
	end
	local function teardown()
		if torn then
			return
		end
		torn = true
		dismiss()
		h.dispose()
	end
	local function Consumer()
		local count = Compose.cell(0)
		local soundOn = Compose.cell(true)
		local viewport = h.environment:get("viewportRect")
		built.count, built.setCount = function()
			return count:peek()
		end, function(value)
			count:set(value)
		end
		built.soundOn, built.setSoundOn =
			function()
				return soundOn:peek()
			end, function(value)
				soundOn:set(value)
			end
		-- External subscriptions use the same component lifetime. No second
		-- RunService connection: the host already drives the presenter's clock.
		local elapsed = 0
		Compose.cleanup(h.onFrame(function(dt)
			elapsed += dt
			if elapsed >= closeAfterSeconds then
				teardown()
			end
		end))
		return UI.Screen("Consumer")({
			padding = "l",
			UI.VStack("Panel")({
				surface = "raised",
				padding = "m",
				gap = "s",
				UI.Text("Title")({ text = "Facet consumer", textSize = "title" }),
				UI.Text("Blurb")({
					text = "One component, local state, one theme. Press Bump and watch the count follow.",
				}),
				UI.VStack("Readout")({
					gap = "xs",
					UI.Text("Count")({
						tint = { role = "accent", blend = 1 },
						text = function(use)
							return if use(count) == 1 then "1 tap" else `{use(count)} taps`
						end,
					}),
					UI.Toggle("Sound")({ label = "Sound", value = soundOn }),
				}),
				UI.AdaptiveStack("Buttons")({
					gap = "s",
					axis = function(use)
						return Facet.adaptive.axisFor(use(viewport).w)
					end,
					UI.Button("Bump")({
						label = "Bump",
						onActivate = function()
							count:update(function(n)
								return n + 1
							end)
						end,
					}),
					UI.Button("Close")({ label = "Close", onActivate = teardown }),
				}),
			}),
		})
	end
	close, node = h.mount(Consumer)
	built.dispose = dismiss
	return {
		built = built,
		node = node,
		teardown = teardown,
		isTorn = function()
			return torn
		end,
	}
end

return screen
