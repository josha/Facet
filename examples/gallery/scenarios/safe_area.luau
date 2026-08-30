--!strict
-- Scenario 'safe-area' (ledger row NS-A1): the deviceSafeContent root policy
-- clears CoreGui AND device (notch/home) insets from ONE authority — the
-- solver consumes env facts; the ScreenGui renders IgnoreGuiInset=true, so
-- the engine never applies a second inset.
--
-- Live path (desktop Studio): real facts from GuiService:GetInsetArea — core
-- top 58, device 0/0/0/0 → content top at window y=58.
-- Notch path: freezeEnv + the injectNotch step writes the synthetic
-- phoneNotchLandscape device insets (left/right 47, bottom 21) → the SAME
-- running screen re-solves with content inset from those edges too.
-- The Studio emulator cannot produce real notch insets (its camera
-- pre-excludes the notch), so the
-- synthetic step is the honest Studio-side driver; physical values are NS-P2.

return {
	title = "Safe-area authority (NS-A1)",
	ledgerRows = { "NS-A1" },
	build = function(ctx: any)
		local UI = ctx.Facet.UI

		local screen = UI.Screen({
			id = "SafeAreaScreen",
			padding = 0,
			gap = "xs",
			children = {
				UI.Text({ id = "TopEdge", text = "TOP-EDGE MARKER", textSize = "control" }),
				UI.Box({
					id = "Content",
					surface = "raised",
					height = UI.fill(),
				}),
				UI.Text({ id = "BottomEdge", text = "BOTTOM-EDGE MARKER", textSize = "control" }),
			},
		})

		return {
			screen = screen,
			present = { rootPolicy = "deviceSafeContent" },
			steps = {
				-- env-fact drivers (labeled: state seams, not hardware evidence)
				injectNotch = function()
					ctx.env:set("deviceSafeInsets", { top = 0, bottom = 21, left = 47, right = 47 })
					return ctx.env:get("deviceSafeInsets"):get()
				end,
				clearNotch = function()
					ctx.env:set("deviceSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
					return ctx.env:get("deviceSafeInsets"):get()
				end,
			},
			report = function()
				return {
					deviceSafeInsets = ctx.env:get("deviceSafeInsets"):get(),
					coreSafeInsets = ctx.env:get("coreSafeInsets"):get(),
				}
			end,
		}
	end,
}
