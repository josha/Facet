--!strict
-- PLAZA — the engine-content hero (spec §13).
--
-- `UI.Stage` is the new engine-content leaf: Facet owns the box, the frame, the
-- WorldModel, the Camera and the lifecycle; the PROOF owns what is in it. A
-- proof module is engine-free, so it cannot build a Part — it declares the
-- diorama as DATA (`stageContent`, returned from build) and the scenario runner,
-- which is the one engine-side seam, materializes it through the public handle.
--
-- THE FALLBACK IS NOT OPTIONAL. `controller.stageHost(path)` answers nil on any
-- adapter without the seam (a billboard target, an engine with no ViewportFrame,
-- a headless twin), and an empty reserved box explains nothing. So the proof
-- PROBES the seam and, when it answers nil, paints the declared plate: plaza
-- key-art, a wash, and a sentence. `tests/reference/cartwheel_spec.luau` pins
-- exactly that, with an adapter whose stage seam is absent.
local data = require("../content/data")
local parts = require("./parts")

local plaza = {}

function plaza.new(app: any): any
	local UI = app.UI
	local core = app.core
	local S = app.S
	local ambient = app.services.ambient
	local stats = app.services.stats

	local self: any = {}

	-- "unknown" until the seam has been asked, so the fallback plate appears
	-- because the host is ABSENT and never because it has not been asked yet
	local stageState = core:signal("unknown")
	self.stageState = stageState

	local current = core:memo(function(use)
		local section = use(app.state.section)
		local id = string.match(section, "^plaza:(.+)$")
		return data.plazaById(id or "willowmere") or (data.plazas :: any)[2]
	end)
	self.current = current

	local plazaName = core:memo(function(use)
		return (use(current) :: any).name
	end)
	local pitchName = core:memo(function(use)
		return (use(current) :: any).pitch
	end)
	local chargeText = core:memo(function(use)
		local entry = ambient.forPlaza((use(current) :: any).id)
		return S.t("plaza.charge", { percent = math.floor((1 - entry.cloud / 100) * 100) })
	end)
	local cloudText = core:memo(function(use)
		local entry = ambient.forPlaza((use(current) :: any).id)
		return S.t("plaza.cloud", { percent = entry.cloud })
	end)
	local seasonalText = core:memo(function(use)
		use(stats.version)
		local top = stats.topFive("today")[1]
		return S.t("plaza.seasonal", { potion = if top == nil then "" else top.potion.name })
	end)
	local stockText = core:memo(function(use)
		local entry = ambient.forPlaza((use(current) :: any).id)
		return S.t("plaza.stock", { bottles = 12 + entry.cloud })
	end)
	local noHost = core:memo(function(use)
		return use(stageState) == "absent"
	end)

	-- THE PROBE. It runs on the presenter's own tick (the one sanctioned frame
	-- source outside the motion clock), only while this section is actually
	-- MOUNTED, and only while the answer is still unknown — so a settled screen
	-- pays nothing for it and "the node is not on screen" can never be mistaken
	-- for "this adapter has no stage seam".
	local onPlaza = core:memo(function(use)
		return string.match(use(app.state.section), "^plaza:") ~= nil
	end)

	-- THE ORBIT. The camera is the proof's (Facet owns the box and the frame; the
	-- content and how it is looked at are ours), so it is driven here, through the
	-- public handle, on the same tick everything else in this proof rides. Long
	-- period, eased pitch, deterministic start angle — and REDUCED MOTION PARKS
	-- IT at the declared framing rather than dropping the picture.
	local host: any = nil
	local ORBIT_PERIOD = 48
	local ORBIT_RADIUS = 21
	local function framing(now: number): any
		local angle = if app.reducedMotion:get() then 0 else (now / ORBIT_PERIOD) * 2 * math.pi
		local pitch = 9 + (if app.reducedMotion:get() then 0 else math.sin(now / (ORBIT_PERIOD * 0.5)) * 2)
		return {
			position = {
				x = math.sin(angle + 0.72) * ORBIT_RADIUS,
				y = pitch,
				z = math.cos(angle + 0.72) * ORBIT_RADIUS,
			},
			lookAt = { x = 0, y = 1.5, z = 0 },
			fov = 42,
		}
	end
	self.framing = framing

	app.onTick(function()
		if not onPlaza:get() then
			return
		end
		local controller = app.controller()
		if controller == nil or controller.stageHost == nil then
			return
		end
		if stageState:get() == "unknown" then
			host = controller.stageHost(app.paths.stage)
			stageState:set(if host == nil then "absent" else "present")
		end
		if host == nil then
			return
		end
		-- a parked orbit still writes ONE framing (the declared one) and then
		-- nothing more, so reduced motion costs a frame rather than a branch in
		-- the view
		if app.reducedMotion:get() and self.parked then
			return
		end
		self.parked = app.reducedMotion:get()
		host.setCamera(framing(app.clock.now()))
	end)

	-- leaving the section unmounts the Stage with its host, so the answer goes
	-- back to unknown and is asked again on the next visit
	local unsubscribe = core:observe(onPlaza, function(on: boolean)
		if not on then
			stageState:set("unknown")
			host = nil
			self.parked = false
		end
	end)

	function self.resetProbe()
		stageState:set("unknown")
	end

	local fallbackPlate = UI.ZStack({
		id = "Fallback",
		canvasGroup = true,
		width = UI.fill(),
		height = UI.fill(),
		alignH = "center",
		alignV = "center",
		children = {
			UI.gradient(
				UI.Image({
					id = "KeyArt",
					image = app.art.marks.menu.image,
					scaleMode = "crop",
					tint = { role = "contentSecondary", blend = 0.7 },
					width = UI.fill(),
					height = UI.fill(),
				}),
				{ colors = { "surfaceStrong", "surface" }, rotation = 90 }
			),
			UI.Text({
				id = "Note",
				text = S.t("plaza.fallback"),
				textSize = "caption",
				role = "secondary",
				textAlign = "center",
				lineLimit = 2,
			}),
		},
	})

	local hero = UI.ZStack({
		id = "Hero",
		width = UI.fill(),
		height = { type = "fixed", px = "app.cartwheel.previewMin" },
		children = {
			-- the reserved box itself: it paints its own plate whether or not a
			-- scene ever arrives, so the layout is identical in both worlds
			UI.corners(
				UI.Stage({
					id = "Stage",
					surface = "raised",
					width = UI.fill(),
					height = UI.fill(),
				}),
				"panel"
			),
			UI.When({
				id = "FallbackWhen",
				condition = noHost,
				thenView = function()
					return fallbackPlate
				end,
				transition = { enter = "fade", class = "container" },
			}),
		},
	})

	local page = UI.ScrollView({
		id = "Plaza",
		axis = "y",
		gap = "m",
		padding = "m",
		width = UI.fill(),
		height = UI.fill(),
		children = {
			-- plaza and pitch names are identity text: they may truncate, but only
			-- with a way back to the whole string (spec §19 disclose ledger)
			UI.Text({ id = "Title", text = plazaName, textSize = "title", lineLimit = 2, disclose = true }),
			hero,
			parts.card(app, {
				id = "Pitch",
				children = {
					UI.Text({ id = "Name", text = pitchName, textSize = "heading", lineLimit = 2, disclose = true }),
					UI.Text({
						id = "Recommended",
						text = S.t("plaza.recommended"),
						textSize = "caption",
						role = "secondary",
					}),
					--[[ THIS WAS A `ViewThatFits` LADDER: three candidate summaries,
						richest first (Full = 3 chips, Two = 2, One = 1), and the framework
						measured and picked. Two things were wrong with it, and
						`HStack{ wrap = true }` (parity round 3) fixes both.

						(1) IT DROPPED FACTS TO FIT. Narrowing the card deleted "Trending",
						then "Popular". A summary chip is a fact ABOUT THE PLAZA, not chrome
						— the honest narrow form is the same three chips on two lines, which
						is exactly what a wrap gives.

						(2) IT WROTE THE CHIPS THREE TIMES, so `Charge` existed at THREE
						published paths and the two losers sat permanently at a ZERO rect.
						MEASURED 2026-08-13 before deleting: `Summary/Two/Charge` and
						`Summary/One/Charge` were both 8x0 at 733x313, 1024x768 and
						1440x900 — every viewport this section is reachable on. The ladder
						NEVER ONCE chose them, so they were dead weight and a trap besides:
						a fixture asserting "a node named Charge carries this text" is
						satisfied by a loser at h=0, which is exactly how `06_tile_game`'s
						readouts moved off their published paths past a green suite. One
						wrapping row publishes each chip at ONE path.

					NO `align` HERE, THOUGH THE LADDER'S CANDIDATES ALL CARRIED
						`align = "center"`. On the inner candidate it was a no-op (chips are
						one height). Promoted onto the container the ladder used to be, it
						becomes load-bearing TWICE: it places the block of lines on the
						wrap's cross axis, AND the parent `Pitch` VStack reads a child's own
						`align` as that child's cross placement — so keeping it slid the
						whole row 80px right, off the card's leading edge (measured
						1440x900: x 270 -> 350). Dropped, and the row stays where it was. ]]
					UI.HStack({
						id = "Summary",
						wrap = true,
						gap = "xs",
						children = {
							parts.chip(app, "Charge", chargeText),
							parts.chip(app, "Popular", S.t("plaza.popular")),
							parts.chip(app, "Trending", S.t("plaza.trending")),
						},
					}),
				},
			}),
			parts.plate(app, {
				id = "Flavor",
				gap = "xs",
				children = {
					UI.Text({ id = "Cloud", text = cloudText, textSize = "body" }),
					UI.Text({ id = "Seasonal", text = seasonalText, textSize = "body" }),
					UI.Text({ id = "Stock", text = stockText, textSize = "body" }),
				},
			}),
		},
	})

	function self.view(): any
		return page
	end

	function self.dump(): any
		local entry = ambient.forPlaza((current:get() :: any).id)
		return {
			plaza = (current:get() :: any).id,
			stage = stageState:get(),
			recommended = ambient.recommendedPlaza().id,
			damp = entry.damp,
		}
	end

	function self.dispose()
		unsubscribe()
		onPlaza:dispose()
		noHost:dispose()
		stockText:dispose()
		seasonalText:dispose()
		cloudText:dispose()
		chargeText:dispose()
		pitchName:dispose()
		plazaName:dispose()
		current:dispose()
		stageState:dispose()
	end

	return self
end

return plaza
