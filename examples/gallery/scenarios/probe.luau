--!strict
-- PROBE-EXEMPT: this file is INSTRUMENT, not example — do not copy its shape.
-- Every number in it is written as a literal ON PURPOSE and is listed in
-- `PROBE_EXEMPT_FILES` in `tools/lune/check_theme_drift.luau` for that reason:
-- the geometry below IS the frozen baseline ledger row NS-A2 captures, so it has
-- to be immune to a theme swap by construction. An example spells the same
-- values `gap = "s"` / `textSize = "body"`, and the rest of this directory does.
--
-- Scenario 'probe': surface self-test (no ledger adoption row of its own).
-- Proves the verification surface itself: mount through the real presenter,
-- deterministic steps, env observation, instance/geometry export, reset.
-- Includes an overflowing ScrollView (sized `fill` so IT overflows but the
-- page never does) so the CURRENT (pre-adoption) scroll behavior is captured
-- as the frozen baseline for ledger row NS-A2 (contract §6 step 1: freeze a
-- baseline where behavior will be matched).

return {
	title = "Verification-surface probe",
	ledgerRows = { "NS-A2:baseline" },
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local counter = Compose.cell(0)
		local counterText = Compose.formula(function(use)
			return "count=" .. tostring(use(counter))
		end)
		local function bump()
			counter:set(counter:peek() + 1)
		end

		local function screen()
			-- `fill` so the ScrollView takes whatever is left of the page after
			-- Title/Counter/Bump. The 12 rows outgrow any share it gets, so it
			-- overflows ITS OWN box, the NS-A2 baseline this scenario freezes,
			-- at every viewport and never the page's.
			local scroll: { any } = { height = UI.fill() }
			for i = 1, 12 do
				table.insert(
					scroll,
					UI.Text("ProbeRow" .. i)({
						text = "Probe row " .. i,
						textSize = 16,
						height = { type = "fixed", px = 30 },
					})
				)
			end
			return UI.Screen("ProbeScreen")({
				padding = 16,
				gap = 8,

				UI.Text("Title")({ text = "Scenario probe", textSize = 22 }),
				UI.Text("Counter")({ text = counterText, textSize = 14 }),
				UI.Button("Bump")({ label = "Bump", onActivate = bump }),
				UI.ScrollView("ProbeScroll")(scroll),
			})
		end

		return {
			screen = screen,
			steps = {
				-- state/action drivers (labeled: NOT hardware-input evidence)
				bump = function()
					bump()
					return counter:peek()
				end,
			},
			report = function()
				return { counter = counter:peek() }
			end,
		}
	end,
}
