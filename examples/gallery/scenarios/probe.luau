--!strict
-- Scenario 'probe': surface self-test (no ledger adoption row of its own).
-- Proves the verification surface itself: mount through the real presenter,
-- deterministic steps, env observation, instance/geometry export, reset.
-- Includes an overflowing ScrollView so the CURRENT (pre-adoption) scroll
-- behavior is captured as the frozen baseline for ledger row NS-A2
-- (contract §6 step 1: freeze a baseline where behavior will be matched).

return {
	title = "Verification-surface probe",
	ledgerRows = { "NS-A2:baseline" },
	build = function(ctx: any)
		local UI = ctx.LuauUI.UI
		local core = ctx.core
		local counter = core:signal(0)
		local counterText = core:memo(function(use)
			return "count=" .. tostring(use(counter))
		end)

		local rows = {}
		for i = 1, 12 do
			table.insert(
				rows,
				UI.Text({
					id = "ProbeRow" .. i,
					text = "Probe row " .. i,
					textSize = 16,
					height = { type = "fixed", px = 30 },
				})
			)
		end

		local screen = UI.Screen({
			id = "ProbeScreen",
			padding = 16,
			gap = 8,
			children = {
				UI.Text({ id = "Title", text = "Scenario probe", textSize = 22 }),
				UI.Text({ id = "Counter", text = counterText, textSize = 14 }),
				UI.Button({ id = "Bump", label = "Bump" }),
				UI.ScrollView({
					id = "ProbeScroll",
					height = { type = "fixed", px = 200 },
					children = rows,
				}),
			},
		})

		return {
			screen = screen,
			present = {
				onActivate = function(path: string)
					if path == "/ProbeScreen/Bump" then
						counter:set(counter:get() + 1)
					end
				end,
			},
			steps = {
				-- state/action drivers (labeled: NOT hardware-input evidence)
				bump = function()
					counter:set(counter:get() + 1)
					return counter:get()
				end,
			},
			report = function()
				return { counter = counter:get() }
			end,
		}
	end,
}
