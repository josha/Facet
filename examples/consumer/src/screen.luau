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
	local UI = Facet.View
	local closeAfterSeconds = (opts and opts.closeAfterSeconds) or 120
	local torn = false
	local handle
	local built: any = {} -- Commands/readbacks for the example's headless driver.
	local function dismiss()
		if handle then
			h.presenter.dismiss(handle)
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
	local Consumer = Facet.component(function(ui)
		local count, setCount = ui.state(0)
		local soundOn, setSoundOn = ui.state(true)
		local viewport = ui.env("viewportRect")
		built.count, built.setCount = count, setCount
		built.soundOn, built.setSoundOn = soundOn, setSoundOn
		-- External subscriptions use the same component lifetime. No second
		-- RunService connection: the host already drives the presenter's clock.
		local elapsed = 0
		ui.own(h.presenter.onTick(function(dt)
			elapsed += dt
			if elapsed >= closeAfterSeconds then
				teardown()
			end
		end))
		return UI.Screen({
			id = "Consumer",
			padding = "l",
			UI.VStack({
				id = "Panel",
				surface = "raised",
				padding = "m",
				gap = "s",
				UI.Text({ id = "Title", text = "Facet consumer", textSize = "title" }),
				UI.Text({
					id = "Blurb",
					text = "One component, local state, one theme. Press Bump and watch the count follow.",
				}),
				UI.VStack({
					id = "Readout",
					gap = "xs",
					UI.Text({
						id = "Count",
						tint = { role = "accent", blend = 1 },
						text = function()
							return if count() == 1 then "1 tap" else `{count()} taps`
						end,
					}),
					UI.Toggle({ id = "Sound", label = "Sound", value = soundOn, onChange = setSoundOn }),
				}),
				UI.AdaptiveStack({
					id = "Buttons",
					gap = "s",
					axis = function()
						return Facet.adaptive.axisFor(viewport().w)
					end,
					UI.Button({
						id = "Bump",
						label = "Bump",
						onActivate = function()
							setCount(function(n)
								return n + 1
							end)
						end,
					}),
					UI.Button({ id = "Close", label = "Close", onActivate = teardown }),
				}),
			}),
		})
	end)
	handle = h.presenter.present(Consumer({}))
	built.dispose = dismiss
	return {
		built = built,
		handle = handle,
		teardown = teardown,
		isTorn = function()
			return torn
		end,
	}
end

return screen
