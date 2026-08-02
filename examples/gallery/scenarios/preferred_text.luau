--!strict
-- Scenario 'preferred_text' (ledger rows NS-A9/NS-A10): preferred text is
-- applied EXACTLY ONCE (engine paints the preference; LuauUI reserves via the
-- measure seam only), and engine calibration tightens the estimator's
-- over-reserve without under-reserving across a Latin/wrap/CJK/unknown-font
-- corpus. The live pref sweep (Large/Larger/Largest) is not script-drivable
-- (GuiService.PreferredTextSize is read-only) — the injectLargestPref step
-- drives the RESERVATION fact through the frozen env seam; the engine-side
-- sweep stays in the review packet.

return {
	title = "Preferred text + calibration (NS-A9/NS-A10)",
	ledgerRows = { "NS-A9", "NS-A10" },
	build = function(ctx: any)
		local UI = ctx.LuauUI.UI

		local corpus = {
			{ id = "Short", text = "Save" },
			{ id = "Long", text = "The quick brown fox jumps over the lazy dog near the river bank" },
			{ id = "CJK", text = "こんにちは世界、これはテストです" },
			{ id = "Mixed", text = "Lap 3/7 — 01:23.456 (best)" },
		}
		local children = { UI.Text({ id = "Title", text = "Preferred-text corpus", textSize = 22 }) }
		for _, entry in corpus do
			table.insert(
				children,
				UI.Text({
					id = entry.id,
					text = entry.text,
					textSize = 18,
					width = { type = "fixed", px = 360 },
				})
			)
		end

		local screen = UI.Screen({ id = "PrefText", padding = 16, gap = 10, children = children })

		return {
			screen = screen,
			present = {},
			steps = {
				-- engine calibration: measure real font metrics, tighten the
				-- estimator, and re-present so the next solve uses them
				calibrate = function()
					return ctx.runTextCalibration()
				end,
				-- reservation-fact driver (env seam; engine pref not writable)
				injectLargestPref = function()
					ctx.env:set("preferredTextSize", 1.45)
					return ctx.env:get("preferredTextSize"):get()
				end,
				resetPref = function()
					ctx.env:set("preferredTextSize", 1)
					return true
				end,
			},
			report = function()
				return { corpusIds = { "Short", "Long", "CJK", "Mixed" } }
			end,
		}
	end,
}
