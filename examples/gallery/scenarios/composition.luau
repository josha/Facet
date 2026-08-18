--!strict
-- Scenario 'composition' (ADR-0023; ledger row OWN-D45): DECLARED-CONTENT
-- ADAPTIVE COMPOSITION, on screen.
--
-- ONE declaration of thirteen ranked regions, each with a richest and a
-- minimum-viable form. There is no device branch, no viewport threshold and no
-- per-orientation tree — the arrangement, the per-region form and the drop set
-- all come out of the box the composition receives.
--
-- Twelve of the regions ride LANES; the thirteenth (`Recap`) rides a SPANNING
-- ROW — a group that declares `span = "above"` instead of a lane affinity and is
-- therefore the composition's full width, in the same place, in every
-- arrangement (2026-07-31). `emptyRecap` / `fillRecap` show the band costing
-- nothing when its content is absent.
--
-- The fixture drives that box directly rather than the viewport, which is the
-- honest way to prove the promise: `UI.Composition` is CONTAINER-relative, so
-- the same screen must resolve differently inside a smaller pane on an
-- unchanged display. The five named steps are the device matrix's offers
-- (compact portrait, phone landscape, tablet, desktop, ten-foot), `flipOffer`
-- is the live axis flip, and every one of them is a re-solve: `bump` proves the
-- owner state survives it, and the runner's counters prove nothing rebuilt.
--
-- Every string here is the framework's own placeholder copy. This fixture
-- belongs to Facet, not to a game.
--
-- THE SCREEN BODY SCROLLS. The offer bar and the offer frame live inside a
-- `UI.ScrollView` (`Body`) rather than directly under the screen, because the
-- offer frame's own height is the device profile being simulated and can
-- exceed what a short landscape phone actually has to give the real screen —
-- see the note beside `Body` below.

local OFFERS: { [string]: { w: number, h: number } } = {
	compactPortrait = { w = 360, h = 740 },
	phoneLandscape = { w = 733, h = 313 },
	tablet = { w = 1024, h = 768 },
	desktop = { w = 1400, h = 900 },
	tenFoot = { w = 1708, h = 960 },
}

return {
	title = "Declared-content adaptive composition (ADR-0023)",
	ledgerRows = { "OWN-D45" },
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("composition-scenario")
		-- the height half of the adaptive facts rides here too: the offer frame
		-- never asks for more than the display actually has
		local conditions = Facet.adaptive.conditions(core, ctx.env, { scope = scope })

		-- OWNER STATE. It must survive every arrangement change; that is the
		-- whole "re-solve, never rebuild" promise, and `bump` is how the driver
		-- checks it without reading a counter.
		local visits = core:signal(0)
		local offerName = core:signal("phoneLandscape")
		-- the transient the reserved region holds a box for
		local celebrating = core:signal(true)
		local hasCallout = core:signal(true)
		-- the SPANNING caption's content: a band that is there or is not (2026-07-31)
		local hasRecap = core:signal(true)

		local function offerDim(axis: string)
			return scope:own(core:memo(function(use)
				local want = OFFERS[use(offerName)] or OFFERS.phoneLandscape
				local have = if axis == "w" then use(conditions.viewportWidth) else use(conditions.viewportHeight)
				local px = if axis == "w" then want.w else want.h
				if have > 0 then
					px = math.min(px, have)
				end
				return { type = "fixed", px = px }
			end))
		end

		local function line(id: string, text: string, size: number)
			return UI.Text({ id = id, text = text, textSize = size, lineLimit = 2 })
		end
		local function plate(id: string, h: number, label: string, size: number)
			return UI.ZStack({
				id = id,
				surface = "raised",
				height = { type = "fixed", px = h },
				width = { type = "fill", weight = 1 },
				children = { UI.Text({ id = id .. "Label", text = label, textSize = size, textAlign = "center" }) },
			})
		end

		-- ---- the field: the ONE region allowed to scroll ------------------
		local rows = {}
		for i = 1, 14 do
			table.insert(
				rows,
				UI.HStack({
					id = `Row{i}`,
					gap = 8,
					width = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = `RowRank{i}`, text = tostring(i), textSize = 14 }),
						UI.Box({
							id = `RowMark{i}`,
							surface = "chip",
							width = { type = "fixed", px = 18 },
							height = { type = "fixed", px = 18 },
						}),
						UI.Text({ id = `RowName{i}`, text = `Entry {i}`, textSize = 14, lineLimit = 1 }),
					},
				})
			)
		end
		local field = UI.ScrollView({
			id = "FieldScroll",
			axis = "y",
			gap = 4,
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = rows,
		})

		local composition = UI.Composition({
			id = "Summary",
			-- richest first; the LAST is the declared fallback
			arrangements = { "threeLane", "twoLane", "column" },
			laneGap = "m",
			groupGap = "s",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			groups = {
				-- THE SPANNING ROW (2026-07-31): `span` instead of a lane affinity, so
				-- this band is the composition's full width, directly under the
				-- masthead, in EVERY arrangement — no lane can absorb it and no
				-- arrangement can drop it into a column
				{ id = "caption", span = "above" },
				-- the masthead travels with the ceremony when the lanes split, so it
				-- has a home in every arrangement without a fourth lane
				{ id = "masthead", lane = "lead", sizing = "hug", place = "start" },
				{ id = "ceremony", lane = "lead", sizing = "hug", place = "center" },
				{ id = "field", lane = "main", sizing = "fill", weight = 1, minWidth = 240 },
				{ id = "next", lane = "trail", sizing = "hug", place = 0.66 },
			},
			-- REGIONS ARE DECLARED IN READING ORDER; `rank` is adaptation priority
			-- only, and the two are deliberately independent
			children = {
				UI.Region({
					id = "Recap",
					group = "caption",
					-- it steps down and drops by rank exactly like a lane region: the
					-- span is about WHERE the row is, not about what it is worth
					rank = 5,
					-- the short form keeps the drama score and drops the lead changes and the
					-- recoveries, so two facts leave the screen with it
					recover = "overflow",
					floor = { lines = 1 },
					children = {
						UI.When({
							id = "RecapFull",
							condition = hasRecap,
							thenView = function()
								return line("RecapTwoLine", "6 lead changes · 2 recoveries · Drama 41", 16)
							end,
						}),
						UI.When({
							id = "RecapShort",
							condition = hasRecap,
							thenView = function()
								return line("RecapOneLine", "Drama 41", 14)
							end,
						}),
					},
				}),
				UI.Region({
					id = "Countdown",
					group = "masthead",
					rank = 2,
					-- "Next round in 12" -> "12": fewer words, the same fact
					recover = "none",
					floor = { lines = 1 },
					children = { line("CountdownFull", "Next round in 12", 18), line("CountdownShort", "12", 18) },
				}),
				UI.Region({
					id = "BankChip",
					group = "masthead",
					rank = 5,
					-- the short form drops the "+80" delta, and a dropped chip drops the balance
					recover = "overflow",
					mayDrop = true,
					children = { line("BankFull", "Balance 1,240  +80", 14), line("BankShort", "1,240", 14) },
				}),
				UI.Region({
					id = "Headline",
					group = "ceremony",
					rank = 3,
					-- the same word on a smaller plate
					recover = "none",
					floor = { lines = 1 },
					children = { plate("HeadlinePlate", 96, "SECOND", 30), line("HeadlineChip", "SECOND", 16) },
				}),
				UI.Region({
					id = "Celebration",
					group = "ceremony",
					rank = 4,
					-- "+320 points" either way — a plate becomes a line
					recover = "none",
					-- the FLOOR is the reserved box: it holds when the transient rests,
					-- so nothing under a thumb moves when the piece finishes
					reserved = true,
					floor = { targets = 2 },
					children = {
						UI.When({
							id = "CelebrationFull",
							condition = celebrating,
							thenView = function()
								return plate("CelebrationPiece", 88, "+320 points", 20)
							end,
						}),
						UI.When({
							id = "CelebrationCompact",
							condition = celebrating,
							thenView = function()
								return line("CelebrationLine", "+320 points", 16)
							end,
						}),
					},
				}),
				UI.Region({
					id = "Callout",
					group = "ceremony",
					rank = 7,
					-- "by four tenths" is the margin, and the short form does not carry it
					recover = "overflow",
					mayDrop = true,
					children = {
						UI.When({
							id = "CalloutFull",
							condition = hasCallout,
							thenView = function()
								return line("CalloutTwoLine", "You beat your rival by four tenths", 16)
							end,
						}),
						UI.When({
							id = "CalloutShort",
							condition = hasCallout,
							thenView = function()
								return line("CalloutOneLine", "Rival beaten", 14)
							end,
						}),
					},
				}),
				UI.Region({
					id = "FieldHead",
					group = "field",
					rank = 4,
					-- "Final order — 14 entries" -> "Order": the entry count goes
					recover = "overflow",
					floor = { lines = 1 },
					children = {
						line("FieldHeadFull", "Final order — 14 entries", 16),
						line("FieldHeadShort", "Order", 14),
					},
				}),
				UI.Region({
					id = "Field",
					group = "field",
					rank = 2,
					sizing = "fill",
					-- THE one scroll region on the surface; a second is refused at
					-- construction, not resolved around
					mayScroll = true,
					floor = { lines = 2 },
					children = { field },
				}),
				UI.Region({
					id = "Sponsors",
					group = "next",
					rank = 6,
					-- "3 backers" names none of them
					recover = "overflow",
					mayDrop = true,
					children = {
						UI.VStack({
							id = "SponsorsFull",
							gap = 4,
							children = {
								line("SponsorsHead", "BACKED BY", 12),
								line("SponsorsList", "Aurora · Kestrel · Vale", 14),
							},
						}),
						line("SponsorsLine", "3 backers", 12),
					},
				}),
				UI.Region({
					id = "Bait",
					group = "next",
					rank = 8,
					-- the short form drops what the win unlocks
					recover = "overflow",
					mayDrop = true,
					children = {
						line("BaitTwoLine", "Unlock the next tier with one more win", 14),
						line("BaitOneLine", "One more win", 14),
					},
				}),
				UI.Region({
					id = "Tease",
					group = "next",
					rank = 9,
					-- a droppable region can never claim "none" — dropping shows nothing
					recover = "overflow",
					mayDrop = true,
					children = {
						line("TeaseTwoLine", "Coming next: the night circuit", 14),
						line("TeaseOneLine", "Night circuit", 14),
					},
				}),
				UI.Region({
					id = "Badge",
					group = "next",
					rank = 10,
					mayDrop = true,
					children = { line("BadgeLine", "Streak x3", 12) },
				}),
				UI.Region({
					id = "Actions",
					group = "next",
					rank = 1,
					-- the same two buttons, in a column instead of a row
					recover = "none",
					floor = { targets = 2 },
					children = {
						UI.HStack({
							id = "ActionsRow",
							gap = 8,
							children = {
								UI.Button({
									id = "Again",
									label = "Play again",
									height = { type = "minMax", min = 44 },
								}),
								UI.Button({ id = "Leave", label = "Leave", height = { type = "minMax", min = 44 } }),
							},
						}),
						UI.VStack({
							id = "ActionsColumn",
							gap = 6,
							align = "stretch",
							children = {
								UI.Button({
									id = "Again",
									label = "Play again",
									height = { type = "minMax", min = 44 },
								}),
								UI.Button({ id = "Leave", label = "Leave", height = { type = "minMax", min = 44 } }),
							},
						}),
					},
				}),
			},
		})

		-- THE BODY SCROLLS (BodyScroll precedent, adaptive_controls.luau). The offer
		-- frame is deliberately sized to whichever device profile is selected —
		-- that IS the demo, "the composition adapts to a box, not to the viewport"
		-- — so on a short landscape phone the frame can be taller than the real
		-- screen has to give it (found live by the overflow sweep at 705x338 and
		-- 640x320: the phoneLandscape/tablet/desktop/tenFoot offers are all taller
		-- than those two device profiles' own chrome-reserved height). A
		-- `UI.ScrollView` gives the frame somewhere to go instead of painting past
		-- the screen; the OfferFrame's horizontal centering (an `align = "center"`
		-- a scroll region's cross axis does not read — a scroller pins content to
		-- its start edge, deliberately, so a drag always has a heading) is not
		-- worth a second wrapper node on a dev fixture nothing else depends on, so
		-- the frame now sits left-aligned inside the scrollable body.
		local screen = UI.Screen({
			id = "CompositionScreen",
			padding = 12,
			children = {
				UI.ScrollView({
					id = "Body",
					axis = "y",
					gap = 8,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						-- THE BAR WRAPS (O-21, 2026-08-15). Label + the resolved offer
						-- name + `visits N` measure past a 320px phone row from +4
						-- upward, and with nothing shrinkable in it the row painted
						-- `visits 0` 93px off the right screen edge at +10 and 159px at
						-- +14 — the readout this whole fixture is about. A wrap keeps
						-- every one of the three readable; the Spacer still pushes the
						-- count to the end of whatever line it lands on.
						UI.HStack({
							id = "OfferBar",
							wrap = true,
							gap = 8,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "OfferLabel", text = "Offer", textSize = 14 }),
								UI.Text({ id = "OfferName", text = offerName, textSize = 14 }),
								UI.Spacer({}),
								UI.Text({
									id = "Visits",
									text = core:memo(function(use)
										return `visits {use(visits)}`
									end),
									textSize = 14,
								}),
							},
						}),
						-- THE OFFER FRAME. The composition adapts to THIS box, not to the
						-- viewport — which is what makes the same screen resolve
						-- differently inside a pane on an unchanged display.
						UI.VStack({
							id = "OfferFrame",
							surface = "base",
							width = offerDim("w"),
							height = offerDim("h"),
							children = { composition },
						}),
					},
				}),
			},
		})

		local function setOffer(name: string)
			return function()
				offerName:set(name)
				return name
			end
		end

		return {
			screen = screen,
			dispose = function()
				scope:dispose()
			end,
			steps = {
				-- the five-view device matrix, as OFFERS (state drivers, not input)
				compactPortrait = setOffer("compactPortrait"),
				phoneLandscape = setOffer("phoneLandscape"),
				tablet = setOffer("tablet"),
				desktop = setOffer("desktop"),
				tenFoot = setOffer("tenFoot"),
				-- the live axis flip: the same offer, rotated
				flipOffer = function()
					local now = offerName:get()
					local flipped = if now == "compactPortrait" then "phoneLandscape" else "compactPortrait"
					offerName:set(flipped)
					return flipped
				end,
				-- the reserved region's transient finishing and returning: the box
				-- must not move under a thumb either way
				restCelebration = function()
					celebrating:set(false)
					return false
				end,
				wakeCelebration = function()
					celebrating:set(true)
					return true
				end,
				-- an empty region is ABSENT, and its space goes to the field
				emptyCallout = function()
					hasCallout:set(false)
					return false
				end,
				fillCallout = function()
					hasCallout:set(true)
					return true
				end,
				-- the SPANNING band, present and absent: it is a full-width row above
				-- the lanes in every arrangement, and an empty one costs nothing
				emptyRecap = function()
					hasRecap:set(false)
					return false
				end,
				fillRecap = function()
					hasRecap:set(true)
					return true
				end,
				-- owner state that must survive every arrangement change
				bump = function()
					visits:set(visits:get() + 1)
					return visits:get()
				end,
			},
			report = function()
				return {
					offer = offerName:get(),
					visits = visits:get(),
					celebrating = celebrating:get(),
					hasCallout = hasCallout:get(),
					hasRecap = hasRecap:get(),
					-- the resolution itself: WHICH arrangement, WHICH form per region,
					-- and the rule every richer candidate broke
					resolution = if ctx.composition ~= nil
						then ctx.composition("/CompositionScreen/Body/OfferFrame/Summary")
						else nil,
				}
			end,
		}
	end,
}
