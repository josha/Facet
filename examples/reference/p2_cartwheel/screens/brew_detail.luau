--!strict
-- BREW DETAIL — the status machine and the countdown (spec §7).
--
-- New -> Brewing -> Done, one primary button, and a 60 s countdown that is a
-- SERVICE FACT rather than a view timer. That distinction is the whole point of
-- the screen: leaving and coming back re-reads the fact, so the countdown
-- survives navigation instead of restarting with the view that draws it.
--
-- ONE TIME FORM (invariant 2): a depleting textual M:SS plus a thin bar, and
-- because the text is derived from whole seconds it is already quantized — a
-- reduced-motion session keeps counting and drops nothing.
local data = require("../content/data")
local parts = require("./parts")
local strings = require("../content/strings")

local brew_detail = {}

function brew_detail.new(app: any): any
	local UI = app.UI
	local Compose = app.Compose
	local S = app.S
	local Facet = app.Facet
	local orders = app.services.orders

	local self: any = {}
	local openBrew = app.state.openBrew

	local brew = Compose.formula(function(use)
		use(orders.brews)
		return orders.byId(use(openBrew))
	end)

	local status = Compose.formula(function(use)
		local current = use(brew) :: any
		return if current == nil then "new" else current.status
	end)

	-- the live remaining-time fact: a memo over the DOMAIN clock and the brew
	-- record, so one advance moves every countdown on screen in one flush
	local remaining = Compose.formula(function(use)
		use(app.clock.nowSignal)
		use(orders.brews)
		local id = use(openBrew)
		return orders.remaining(id)
	end)
	self.remaining = remaining

	local counting = Compose.formula(function(use)
		return use(remaining) ~= nil
	end)
	local expired = Compose.formula(function(use)
		local left = use(remaining)
		return left ~= nil and left <= 0
	end)
	local countdownText = Compose.formula(function(use)
		local left = use(remaining)
		if left == nil then
			return ""
		end
		if left <= 0 then
			return S.t("detail.readyToFinish")
		end
		return S.t("detail.countdown", { clock = strings.countdown(left) })
	end)
	local countdownFraction = Compose.formula(function(use)
		local left = use(remaining)
		if left == nil then
			return 0
		end
		return math.clamp(left / orders.brewSeconds(), 0, 1)
	end)
	self.countdownText = countdownText

	-- at zero the chip swaps to the strong weight role — an emphasis the type
	-- ramp owns, not a second hue (invariant 1)
	local countdownWeight = Compose.formula(function(use)
		return if use(expired) then "strong" else "caption"
	end)

	local commandId = Compose.formula(function(use)
		return "brew:" .. tostring(use(openBrew))
	end)

	local pending = Compose.formula(function(use)
		return use(app.commands.status(use(commandId))) == "pending"
	end)

	-- The page is built per visit: a node belongs to the mount that made it.
	local function buildPage(): any
		local bar = UI.ProgressView("Countdown")({
			value = countdownFraction,
			min = 0,
			max = 1,
		})

		-- the command's own id follows the brew, so a rejection toast supersedes the
		-- previous one for the SAME subject instead of stacking

		local primaryLabel = Compose.formula(function(use)
			local state = use(status)
			if state == "new" then
				return S.t("detail.start")
			elseif state == "done" then
				return S.t("detail.collected")
			end
			return S.t("detail.finish")
		end)
		local primaryEnabled = Compose.formula(function(use)
			return use(status) ~= "done" and not use(pending)
		end)
		local isDone = Compose.formula(function(use)
			return use(status) == "done"
		end)

		local function primary()
			local id = openBrew:peek()
			if id == 0 then
				return
			end
			if status:peek() == "new" then
				app.actions.startBrew(id)
			else
				app.actions.collectBrews({ id })
			end
		end

		local titleText = Compose.formula(function(use)
			return S.t("detail.title", { id = use(openBrew) })
		end)
		local startedText = Compose.formula(function(use)
			local current = use(brew) :: any
			if current == nil then
				return ""
			end
			if current.startedAt ~= nil then
				return S.t("detail.started", { time = strings.countdown(use(app.clock.nowSignal) - current.startedAt) })
			end
			return S.t("detail.placed", { time = strings.clockTime(current.placedAt) })
		end)
		local statusLabel = Compose.formula(function(use)
			return S.t("status." .. use(status))
		end)
		local totalText = Compose.formula(function(use)
			local current = use(brew) :: any
			return if current == nil then "0" else tostring(current.bottles)
		end)

		local items = Compose.formula(function(use)
			local current = use(brew) :: any
			return if current == nil then {} else current.items
		end)

		local page = UI.ScrollView("BrewDetail")({
			axis = "y",
			gap = "m",
			padding = "m",
			width = UI.fill(),
			height = UI.fill(),

			UI.Text("Title")({ text = titleText, textSize = "title" }),
			parts.card(app, {
				id = "StatusCard",
				children = {
					UI.HStack("Row")({
						gap = "s",
						align = "center",

						parts.chip(app, "Status", statusLabel),
						UI.Text("Started")({ text = startedText, textSize = "caption", role = "secondary" }),
						app.when("WorkingWhen")({
							condition = pending,
							thenView = function()
								return parts.chip(app, "Working", S.t("detail.working"))
							end,
						}),
					}),
					-- THE COUNTDOWN, visible only while it is a fact
					app.when("CountdownWhen")({
						condition = counting,
						thenView = function()
							return UI.VStack("Clock")({
								gap = "xs",
								width = UI.fill(),

								UI.Text("Remaining")({
									text = countdownText,
									textSize = countdownWeight,
									role = "content",
								}),
								bar,
							})
						end,
					}),
				},
			}),
			parts.card(app, {
				id = "BottlesCard",
				children = {
					UI.Text("Heading")({ text = S.t("detail.bottles"), textSize = "heading" }),
					UI.VStack("Rows")({
						gap = "xs",
						width = UI.fill(),

						app.forEach("Items")({
							items = items,
							key = function(item)
								return item.potion
							end,
							row = function(item)
								local potion = data.potionById(item.potion)
								return UI.HStack("Item")({
									gap = "s",
									align = "center",
									width = UI.fill(),

									if potion ~= nil
										then parts.potionMark(app, "Mark", potion, "iconSizes.medium")
										else UI.Spacer("Mark")({}),
									UI.Text("Name")({
										text = if potion == nil then item.potion else potion.name,
										textSize = "body",
										lineLimit = 1,
										disclose = true,
									}),
									UI.Spacer("Gap")({ width = UI.fill() }),
									parts.badge(app, "Bottles", tostring(item.bottles)),
								})
							end,
						}),
					}),
					UI.HStack("Total")({
						gap = "s",
						align = "center",
						width = UI.fill(),

						UI.Text("Label")({ text = S.t("detail.totalBottles"), textSize = "label" }),
						UI.Spacer("Gap")({ width = UI.fill() }),
						parts.badge(app, "Count", totalText),
					}),
				},
			}),
			UI.HStack("Actions")({
				gap = "s",
				align = "center",
				width = UI.fill(),

				UI.Button("Primary")({
					label = primaryLabel,
					surface = "accent",
					enabled = primaryEnabled,
					onActivate = primary,
				}),
				-- disabled stays INSPECTABLE: the button says why
				app.when("DoneWhen")({
					condition = isDone,
					thenView = function()
						return UI.Text("DoneHint")({
							text = S.t("detail.collectedHint"),
							textSize = "caption",
							role = "secondary",
							lineLimit = 2,
							disclose = true,
						})
					end,
				}),
			}),
		})

		return page
	end

	self.view = buildPage

	function self.dump(): any
		return {
			brew = openBrew:peek(),
			status = status:peek(),
			remaining = remaining:peek(),
			countdown = countdownText:peek(),
			pending = pending:peek(),
		}
	end

	return self
end

return brew_detail
