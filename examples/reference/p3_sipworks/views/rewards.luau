--!strict
-- The Steam Stamps card (spec §9) — ONE blueprint, two dressings.
--
-- `compact = true` is the tab-section variant: full width, tighter gaps, small
-- seals, caption hidden. Everything else — the ten slots, the stamped/unstamped
-- FORM difference, the staggered pops, the clear-on-leave rule — is identical,
-- because a compact variant that re-implemented any of it would be a second
-- card to keep true.

local metrics = require("../content/metrics")
local artContent = require("../content/art")
local parts = require("./parts")
local rewardsService = require("../services/rewards")

local rewardsView = {}

function rewardsView.card(app: any, opts: any): any
	local UI = app.UI
	local core = app.core
	local i18n = app.services.i18n
	local rewards = app.services.rewards
	local compact = (opts or {}).compact == true
	local sealSize = if compact then metrics.sealCompact else metrics.seal
	-- A SEAL GROWS WITH THE READER. The cell is a fixed round token and its mark
	-- is drawn text, so at the largest text preference the glyph was taller than
	-- the box (the solver reported a 14px overflow). The box now composes the
	-- environment's own additive preferred-text reservation, exactly as a Table
	-- row does, instead of clipping a letter.
	local sealBox = app.own(core:memo(function(use)
		if app.env == nil then
			return metrics.fixed(sealSize)
		end
		local offset = math.max(0, use(app.env:get("preferredTextOffset")) or 0)
		-- ...and the ten-foot type scale, for the same reason: the mark is drawn
		-- text and the box has to hold it at whatever scale the seat distance asks
		local scale = math.max(1, use(app.env:get("typographyScale")) or 1)
		return metrics.fixed(math.ceil((sealSize + offset) * scale))
	end))

	local cells: { any } = {}
	for slot = 1, rewardsService.THRESHOLD do
		local index = slot
		local filled = app.own(core:memo(function(use)
			return use(rewards.earned) - use(rewards.spent) >= index
		end))
		-- the pop's own value: 0 while a newly-earned seal waits for its beat,
		-- 1 once it has landed. Bound to the mark's TINT, so the arrival is a
		-- fade the solver never sees (see the report's deviation note).
		local pop = app.state.sealPops[index]
		local markTint = app.own(core:memo(function(use)
			return { role = artContent.SEAL_ROLE, blend = use(pop) }
		end))
		table.insert(
			cells,
			UI.ZStack({
				id = "Cell" .. index,
				width = sealBox,
				height = sealBox,
				alignH = "center",
				alignV = "center",
				children = {
					-- the empty slot is a RING: unstamped and stamped differ in
					-- form, not only in colour
					UI.Box({
						id = "Ring",
						width = metrics.fill,
						height = metrics.fill,
						corners = UI.cornersData("pill"),
						stroke = UI.strokeData({}),
					}),
					UI.When({
						id = "Stamped" .. index,
						condition = filled,
						thenView = function()
							return UI.ZStack({
								id = "Seal",
								canvasGroup = true,
								width = metrics.fill,
								height = metrics.fill,
								alignH = "center",
								alignV = "center",
								children = {
									UI.Text({
										id = "Mark",
										text = artContent.SEAL_MARK,
										textSize = "title",
										textAlign = "center",
										tint = markTint,
									}),
								},
							})
						end,
					}),
				},
			})
		)
	end

	local children: { any } = {
		UI.Text({ id = "Title", text = app.text("rewards.title"), textSize = "heading" }),
		UI.Grid({
			id = "Seals",
			columns = 5,
			gap = if compact then "xs" else "s",
			itemSizing = "uniform",
			children = cells,
		}),
	}
	if not compact then
		table.insert(
			children,
			UI.Text({
				id = "Away",
				-- the plural fixture: zero / one / other, picked by the service
				text = app.text("rewards.away", function(use)
					local unspent = use(rewards.earned) - use(rewards.spent)
					local filledSlots = math.clamp(unspent, 0, rewardsService.THRESHOLD)
					return { n = rewardsService.THRESHOLD - filledSlots }
				end),
				role = "secondary",
				textSize = "caption",
				width = metrics.fill,
			})
		)
		table.insert(
			children,
			UI.Text({
				id = "Progress",
				text = app.text("rewards.progress", function(use)
					return { n = math.clamp(use(rewards.earned) - use(rewards.spent), 0, rewardsService.THRESHOLD) }
				end),
				role = "secondary",
				textSize = "caption",
			})
		)
	end

	return UI.VStack({
		id = (opts or {}).id or "RewardsCard",
		surface = "raised",
		corners = UI.cornersData("panel"),
		stroke = UI.strokeData({}),
		padding = if compact then "s" else "m",
		gap = if compact then "xs" else "s",
		align = "center",
		width = metrics.fill,
		children = children,
	})
end

-- the modal wrapper (the sidebar Pocket's presentation). The card itself sits
-- over the ambient steam backdrop; nothing on it is interactive except Done.
function rewardsView.modal(app: any): any
	local UI = app.UI
	return UI.Screen({
		id = "Rewards",
		padding = "m",
		children = {
			UI.ZStack({
				id = "Body",
				canvasGroup = true,
				width = metrics.fill,
				height = metrics.fill,
				alignH = "center",
				alignV = "center",
				children = {
					parts.steamBackdrop(app, "Steam"),
					-- an EXPLICIT box for the scroller, not `fill`: a filled
					-- scroller still measures its own content, so the card would
					-- have pushed the modal past the viewport at the largest text
					-- preference (measured at 640x320)
					UI.ScrollView({
						id = "PanelScroll",
						axis = "y",
						width = metrics.percentMax(0.92, metrics.cardW),
						height = metrics.percent(0.95),
						children = {
							UI.VStack({
								id = "Panel",
								gap = "m",
								align = "center",
								width = metrics.fill,
								children = {
									rewardsView.card(app, { compact = false }),
									UI.Button({
										id = "Done",
										label = app.text("common.done"),
										corners = UI.cornersData("pill"),
										onActivate = function()
											app.commands.dismissRewards()
										end,
									}),
								},
							}),
						},
					}),
				},
			}),
		},
	})
end

return rewardsView
