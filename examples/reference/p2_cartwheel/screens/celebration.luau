--!strict
-- THE COMPLETION CELEBRATION (spec §7) — a modal with a SCRIPTED sequence, so
-- the beats have one owner and one interrupt story.
--
-- What is deliberately NOT here: the reference's "rate this app" moment. An App
-- Store review prompt is host-OS behavior (responsibility ledger), so it is a
-- ledger row and not a fixture — the proof claims no parity for it and does not
-- simulate one.
local data = require("../content/data")
local parts = require("./parts")
local strings = require("../content/strings")

local celebration = {}

function celebration.new(app: any): any
	local UI = app.UI
	local core = app.core
	local S = app.S

	local self: any = {}
	local brewId = core:signal(0)
	local corkIn = core:signal(false)
	local handle: any = nil
	local timeline: any = nil
	local dip = app.motionClock:spring(0, "object")
	self.corkIn = corkIn
	self.brewId = brewId

	local titleText = core:memo(function(use)
		return S.t("celebrate.title", { id = use(brewId) })
	end)
	local detailText = core:memo(function(use)
		local brew = app.services.orders.byId(use(brewId))
		if brew == nil then
			return ""
		end
		return S.t("celebrate.detail", {
			bottles = brew.bottles,
			time = strings.clockTime(brew.doneAt or brew.placedAt),
		})
	end)

	-- the dip rides the PRESENTATION channel: a motion never writes solver
	-- geometry, so nothing here can cause a re-solve
	app.onTick(function()
		local controller = app.modalController()
		if controller == nil then
			return
		end
		local amount = dip:get()
		if math.abs(amount) <= 0.001 then
			controller.setPresentationTransform("/CartwheelCelebration/Group/Card/Bottle", nil)
		else
			controller.setPresentationTransform("/CartwheelCelebration/Group/Card/Bottle", { x = 0, y = amount * 12 })
		end
	end)

	local function view(): any
		local brew = app.services.orders.byId(brewId:get())
		local potion = if brew ~= nil and brew.items[1] ~= nil then data.potionById(brew.items[1].potion) else nil
		return UI.Screen({
			id = "CartwheelCelebration",
			padding = "l",
			children = {
				-- the surface transition FADES, and a fade needs a fade group: a
				-- `Screen` is not one, so the presenter looks for the root's single
				-- declared canvasGroup child and this is it
				UI.ZStack({
					id = "Group",
					canvasGroup = true,
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.VStack({
							id = "Card",
							gap = "m",
							align = "center",
							padding = "l",
							surface = "raised",
							children = {
								UI.Button({
									id = "Bottle",
									label = S.t("celebrate.title", { id = brewId:get() }),
									gap = "xs",
									align = "center",
									onActivate = function()
										-- an idempotent toy: activating the bottle re-toggles
										-- the cork and nothing else
										corkIn:set(not corkIn:get())
									end,
									children = {
										UI.ZStack({
											id = "Art",
											width = { type = "fixed", px = "controls.image.defaultSize" },
											height = { type = "fixed", px = "controls.image.defaultSize" },
											children = {
												UI.Image({
													id = "Glass",
													image = app.art.marks.menu.image,
													scaleMode = "fit",
													tint = { role = "contentSecondary", blend = 0.8 },
													width = UI.fill(),
													height = UI.fill(),
												}),
												if potion ~= nil
													then parts.potionMark(app, "Potion", potion, "iconSizes.medium")
													else UI.Spacer({ id = "Potion" }),
												UI.When({
													id = "CorkWhen",
													condition = corkIn,
													thenView = function()
														return UI.ZStack({
															id = "Cork",
															canvasGroup = true,
															width = { type = "fixed", px = "iconSizes.small" },
															height = { type = "fixed", px = "iconSizes.small" },
															children = {
																UI.Image({
																	id = "Mark",
																	image = app.art.marks.chevronDown.image,
																	scaleMode = "fit",
																	tint = { role = "accent", blend = 1 },
																	width = UI.fill(),
																	height = UI.fill(),
																}),
															},
														})
													end,
													transition = {
														enter = "slide-down",
														fade = true,
														class = "container",
													},
												}),
											},
										}),
									},
								}),
								UI.Text({ id = "Title", text = titleText, textSize = "title", textAlign = "center" }),
								UI.Text({
									id = "Detail",
									text = detailText,
									textSize = "caption",
									role = "secondary",
									textAlign = "center",
								}),
								UI.Button({
									id = "Done",
									label = S.t("celebrate.done"),
									surface = "accent",
									onActivate = function()
										self.dismiss()
									end,
								}),
							},
						}),
					},
				}),
			},
		})
	end

	-- open(id): present the modal and run the scripted beats. Reduced motion
	-- fires every beat immediately, in order, and `onDone("reduced")` — nothing
	-- is dropped, which is why `celebrate` is emitted from the same place in
	-- both modes.
	function self.open(id: number)
		if handle ~= nil then
			self.dismiss()
		end
		brewId:set(id)
		corkIn:set(false)
		dip:snap(0)
		handle = app.presenter.presentModal(view(), {
			outsideTapCancel = true,
			initialFocus = "Done",
			transition = { enter = "materialize", fade = true, class = "container" },
		})
		app.setModalController(handle.controller)
		timeline = app.motionClock:timeline({
			beats = {
				{
					at = 0.75,
					run = function()
						corkIn:set(true)
					end,
					terminal = function()
						corkIn:set(true)
					end,
				},
				{
					at = 1.05,
					run = function()
						dip:setTarget(1)
					end,
					terminal = function()
						dip:snap(0)
					end,
				},
				{
					at = 1.2,
					run = function()
						dip:setTarget(0)
					end,
					terminal = function()
						dip:snap(0)
					end,
				},
			},
			onDone = function(reason: string)
				app.presenter.emitFeedback({ type = "celebrate", context = { brew = id, reason = reason } })
			end,
		})
	end

	function self.isOpen(): boolean
		return handle ~= nil
	end

	function self.dismiss()
		if handle == nil then
			return
		end
		-- mid-sequence dismissal runs every remaining TERMINAL, so nothing is
		-- left half-painted; it deliberately does not play the remaining content
		if timeline ~= nil and not timeline:isDone() then
			timeline:interrupt()
		end
		timeline = nil
		app.presenter.dismiss(handle)
		handle = nil
		app.setModalController(nil)
	end

	function self.dump(): any
		return { open = handle ~= nil, brew = brewId:get(), cork = corkIn:get() }
	end

	function self.dispose()
		self.dismiss()
		dip:dispose()
		detailText:dispose()
		titleText:dispose()
		corkIn:dispose()
		brewId:dispose()
	end

	return self
end

return celebration
