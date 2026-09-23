--!strict
-- Existing passive-status recipes share one scrolling tab and one reset.
return {
	title = "Status",
	ledgerRows = {},
	build = function(ctx: any)
		local UI = ctx.UI
		local marks = require("./status_indicator").build(ctx)
		local badges = require("./badge").build(ctx)
		local notices = require("./notice").build(ctx)
		local function reset()
			marks.reset()
			badges.reset()
			notices.reset()
		end
		-- the safe root's window box, for the affixed banner's content consumer
		local bounds = ctx.Compose.cell({ x = 0, y = 0, w = 0, h = 0 })
		local function reserved(use: any): any
			local b = use(bounds)
			local inset = if b.w > 0
				then ctx.Facet.layout.hudInsets({ bounds = b, reservations = use(ctx.presenter.hudReservations) })
				else { top = 0, bottom = 0 }
			-- the top notice banner and the bottom snackbar strip both hold room
			return { top = inset.top, left = "m", right = "m", bottom = inset.bottom or 0 }
		end
		return {
			screen = function()
				return UI.Screen("StatusFamily")({
					surface = "base",
					padding = { top = "m", bottom = "m" },
					UI.ZStack("Safe")({
						width = UI.fill(),
						height = UI.fill(),
						UI.ScrollView("Content")({
							width = UI.fill(),
							height = UI.fill(),
							padding = reserved,
							UI.VStack("Recipes")({
								width = UI.fill(),
								gap = "l",
								UI.Button("Reset")({ label = "Reset status", onActivate = reset }),
								notices.section(),
								marks.section(),
								badges.section(),
							}),
						}),
						notices.affixed(),
					}),
				})
			end,
			present = {
				onGeometry = function(rectOf: any)
					local r, old = rectOf("/StatusFamily/Safe"), bounds:peek()
					if r and (r.x ~= old.x or r.y ~= old.y or r.w ~= old.w or r.h ~= old.h) then
						bounds:set(table.clone(r))
					end
				end,
			},
			reset = reset,
			steps = { reset = reset },
			report = function()
				local status, badge = marks.report(), badges.report()
				return if status and badge then { status = status, badge = badge } else nil
			end,
		}
	end,
}
