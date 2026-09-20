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
	local Compose = app.Compose
	local S = app.S

	local self: any = {}
	local brewId = Compose.cell(0)
	local corkIn = Compose.cell(false)
	local handle: any = nil
	local timeline: any = nil
	local dip = app.motionClock:spring(0, "object")
	Compose.cleanup(function()
		dip:dispose()
	end)
	self.corkIn = corkIn
	self.brewId = brewId

	local titleText = Compose.formula(function(use)
		return S.t("celebrate.title", { id = use(brewId) })
	end)
	local detailText = Compose.formula(function(use)
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
	-- geometry, so nothing here can cause a re-solve. DECLARED, not written
	-- (gap 16, framework-gaps-phase2): this used to be an `app.onTick` calling
	-- `setPresentationTransform` every frame — including every resting frame,
	-- where it wrote `nil` over and over. `offset` is now a reactive prop on
	-- every rendered class exactly like `scale`/`rotation` already were, so one
	-- memo over the spring is the whole binding — the same shape `dashboard.luau`'s
	-- neighbouring pulse already uses for `scale`. See that file's comment for
	-- the fuller "reach for the write only when there is no prop" argument;
	-- this is the site it was written FOR.
	local bottleOffset = Compose.formula(function(use)
		return { x = 0, y = use(dip) * 12 }
	end)

	local function view(): any
		local brew = app.services.orders.byId(brewId:peek())
		local potion = if brew ~= nil and brew.items[1] ~= nil then data.potionById(brew.items[1].potion) else nil
		return UI.Screen("CartwheelCelebration")({
			padding = "l",

			-- the surface transition FADES, and a fade needs a fade group: a
			-- `Screen` is not one, so the presenter looks for the root's single
			-- declared canvasGroup child and this is it
			UI.ZStack("Group")({
				canvasGroup = true,
				width = UI.fill(),
				height = UI.fill(),

				UI.VStack("Card")({
					gap = "m",
					align = "center",
					padding = "l",
					surface = "raised",

					-- the dip moves a wrapper: the Button owns no presentation offset
					UI.ZStack("BottleDip")({
						offset = bottleOffset,
						UI.Button("Bottle")({
							label = S.t("celebrate.title", { id = brewId:peek() }),
							gap = "xs",
							onActivate = function()
								-- an idempotent toy: activating the bottle re-toggles
								-- the cork and nothing else
								corkIn:set(not corkIn:peek())
							end,

							UI.ZStack("Art")({
								width = { type = "fixed", px = "controls.image.defaultSize" },
								height = { type = "fixed", px = "controls.image.defaultSize" },

								UI.Image("Glass")({
									image = app.art.marks.menu.image,
									scaleMode = "fit",
									tint = { role = "contentSecondary", blend = 0.8 },
									width = UI.fill(),
									height = UI.fill(),
								}),
								if potion ~= nil
									then parts.potionMark(app, "Potion", potion, "iconSizes.medium")
									else UI.Spacer("Potion")({}),
								app.when("CorkWhen")({
									condition = corkIn,
									thenView = function()
										return UI.ZStack("Cork")({
											canvasGroup = true,
											width = { type = "fixed", px = "iconSizes.small" },
											height = { type = "fixed", px = "iconSizes.small" },

											UI.Image("Mark")({
												image = app.art.marks.chevronDown.image,
												scaleMode = "fit",
												tint = { role = "accent", blend = 1 },
												width = UI.fill(),
												height = UI.fill(),
											}),
										})
									end,
									transition = {
										enter = "slide-down",
										fade = true,
										class = "container",
									},
								}),
							}),
						}),
					}),
					UI.Text("Title")({ text = titleText, textSize = "title", textAlign = "center" }),
					UI.Text("Detail")({
						text = detailText,
						textSize = "caption",
						role = "secondary",
						textAlign = "center",
					}),
					UI.Button("Done")({
						label = S.t("celebrate.done"),
						surface = "accent",
						onActivate = function()
							self.dismiss()
						end,
					}),
				}),
			}),
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
		handle = app.presentModal(function()
			return view()
		end, {
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
		return { open = handle ~= nil, brew = brewId:peek(), cork = corkIn:peek() }
	end

	return self
end

return celebration
