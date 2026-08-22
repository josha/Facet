--!strict
-- Scenario 'preferred_text' (ledger rows NS-A9/NS-A10; Step 8.5 LT-2/LT-9):
-- preferred text is applied EXACTLY ONCE (the engine paints the preference;
-- Facet reserves via the measure seam only), and a preference change reflows
-- the mounted tree in place.
--
-- Two distinct drivers, never conflated (LT-10):
--   * the injected steps below drive the RESERVATION fact
--     (`preferredTextOffset` 0/4/10/14 — the measured per-preference constants,
--     probe artifact preference-probe.json) through the frozen env seam, for
--     repeatable layout coverage;
--   * the REAL read-only player setting is drivable only through the
--     in-experience Roblox menu (Settings > Text size) — the Step 8.5 probe
--     drove it with OS-level clicks and proved the change signal; a live
--     session may re-run that path with this scenario mounted to watch the
--     real adapter push the same fact.
--
-- The screen is deliberately compact-hostile: long unbroken names, long
-- localized strings, a wrap-capped identity row, a scrolling form, and a
-- ViewThatFits CTA band that must reflow to its column candidate before any
-- label may shrink or truncate.

return {
	title = "Preferred text: exact-once seam + large-text reflow (NS-A9/NS-A10, LT-2/LT-9)",
	ledgerRows = { "NS-A9", "NS-A10", "LT-2", "LT-9" },
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core

		local volume = core:signal(40)
		local nickname = core:signal("racer")

		local field = Facet.Controls.TextInput(core, {
			id = "Nickname",
			value = nickname,
			placeholder = "Nickname",
		})
		local slider = Facet.Controls.Slider(core, {
			id = "Volume",
			value = volume,
			min = 0,
			max = 100,
			step = 1,
		})

		local corpus = {
			{ id = "Short", text = "Save" },
			{ id = "Long", text = "The quick brown fox jumps over the lazy dog near the river bank" },
			{ id = "CJK", text = "こんにちは世界、これはテストです" },
			{ id = "Mixed", text = "Lap 3/7 — 01:23.456 (best)" },
			{ id = "GermanCompound", text = "Geschwindigkeitsbegrenzungsanzeige aktivieren" },
			{ id = "LongName", text = "Maximiliana-Wilhelmina Rennfahrerin-Steuerbord" },
		}
		local corpusChildren = {}
		for _, entry in corpus do
			table.insert(
				corpusChildren,
				UI.Text({
					id = entry.id,
					text = entry.text,
					textSize = "control",
					width = { type = "fixed", px = 300 },
				})
			)
		end

		-- THE CONTAINING REGION SCROLLS (overflow ladder rung 2). The first cut
		-- of this fixture stacked everything on the bare Screen, and the
		-- landscape row at Largest pushed the CTA band past 339px of height —
		-- essential actions clipped off-screen with no path to them, which is
		-- the exact defect class this stage exists to remove. The document
		-- region is the scrollable unit; the ladder's rung 1 (the CTA band's
		-- own row->column reflow) still happens inside it.
		local screen = UI.Screen({
			id = "PrefText",
			padding = "m",
			gap = 10,
			children = {
				UI.Text({ id = "Title", text = "Preferred-text corpus", textSize = 22 }),
				UI.ScrollView({
					id = "Doc",
					height = { type = "fill", weight = 1 },
					children = {
						UI.VStack({
							id = "DocRows",
							gap = 10,
							children = {
								-- a wrap-capped identity line: at Largest it must ellipsize inside
								-- its own box (never paint through a neighbour), and `disclose`
								-- makes the full value reachable — the live hover/long-press plate
								-- is drivable against THIS node (LT-6 full-value access, E3)
								UI.Text({
									id = "Identity",
									text = "Bartholomew 'The Unstoppable Thunderbolt' Maximilian III",
									textSize = "body",
									lineLimit = 1,
									disclose = true,
									width = { type = "fixed", px = 220 },
								}),
								-- the scrolling FORM region: live control state + scroll position
								-- must survive a hot preference change (LT-2)
								UI.ScrollView({
									id = "Form",
									height = { type = "fixed", px = 180 },
									children = {
										UI.VStack({
											id = "FormRows",
											gap = "s",
											children = (function()
												local rows = {}
												table.insert(rows, field.blueprint)
												table.insert(rows, slider.blueprint)
												for _, child in corpusChildren do
													table.insert(rows, child)
												end
												return rows
											end)(),
										}),
									},
								}),
								-- the CTA band: reflow FIRST (row -> column candidate); labels are
								-- actions and may never truncate (overflow order rung 1)
								UI.ViewThatFits({
									id = "CtaBand",
									children = {
										UI.HStack({
											id = "CtaRow",
											gap = "s",
											children = {
												UI.Button({ id = "AcceptRow", label = "Accept the invitation" }),
												UI.Button({ id = "DeclineRow", label = "Politely decline for now" }),
											},
										}),
										UI.VStack({
											id = "CtaColumn",
											gap = "s",
											children = {
												UI.Button({ id = "AcceptCol", label = "Accept the invitation" }),
												UI.Button({ id = "DeclineCol", label = "Politely decline for now" }),
											},
										}),
									},
								}),
							},
						}),
					},
				}),
			},
		})

		-- the four measured per-preference constants (probe artifact); the enum
		-- names key the steps so a Studio driver can request a preference by name
		local MEASURED = { Medium = 0, Large = 4, Larger = 10, Largest = 14 }

		local function setOffset(name: string): any
			ctx.env:set("preferredTextOffset", MEASURED[name])
			return { preference = name, offset = ctx.env:get("preferredTextOffset"):get() }
		end

		return {
			screen = screen,
			present = {},
			steps = {
				-- engine calibration: measure real font metrics, tighten the
				-- estimator, and re-present so the next solve uses them
				calibrate = function()
					return ctx.runTextCalibration()
				end,
				-- reservation-fact drivers, one per preference value
				prefMedium = function()
					return setOffset("Medium")
				end,
				prefLarge = function()
					return setOffset("Large")
				end,
				prefLarger = function()
					return setOffset("Larger")
				end,
				prefLargest = function()
					return setOffset("Largest")
				end,
				-- the LT-2 hot cycle in one step: seed live state, swing the
				-- offset both ways, and report what survived
				hotSwap = function()
					volume:set(73)
					local before = ctx.env:get("preferredTextOffset"):get()
					setOffset("Largest")
					setOffset("Medium")
					return { before = before, volumeAfter = volume:get() }
				end,
				-- DISCLOSURE engagement seams (LT-6 full-value access, E3 slice).
				-- These drive the presenter's documented engine-adapter seams —
				-- the same calls the live adapter's hover/long-press zones make —
				-- so everything DOWNSTREAM of engagement (dwell, the plate's real
				-- Instances, dismissal) is proven live. Raw pointer/touch delivery
				-- itself stays a physical/human row: Studio cannot synthesize
				-- mouse MOVEMENT (the engine reads hardware deltas directly).
				discloseHover = function()
					ctx.presenter._discloseHover("/PrefText/Doc/DocRows/Identity")
					return ctx.presenter.disclosure()
				end,
				discloseRelease = function()
					ctx.presenter._discloseHover(nil)
					return ctx.presenter.disclosure()
				end,
				discloseLongPress = function()
					ctx.presenter._discloseLongPress("/PrefText/Doc/DocRows/Identity")
					return ctx.presenter.disclosure()
				end,
				-- legacy multiplier-seam step kept for NS-A9 continuity (the
				-- multiplier is the INJECTABLE seam; the live path leaves it at 1)
				injectLargestPref = function()
					ctx.env:set("preferredTextSize", 1.45)
					return ctx.env:get("preferredTextSize"):get()
				end,
				resetPref = function()
					ctx.env:set("preferredTextSize", 1)
					ctx.env:set("preferredTextOffset", 0)
					return true
				end,
			},
			report = function()
				return {
					corpusIds = { "Short", "Long", "CJK", "Mixed", "GermanCompound", "LongName" },
					offset = ctx.env:get("preferredTextOffset"):get(),
					measuredConstants = MEASURED,
					volume = volume:get(),
				}
			end,
		}
	end,
}
