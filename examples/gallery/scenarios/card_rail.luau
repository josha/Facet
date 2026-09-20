--!strict
-- Three horizontal shelves share Facet's adaptive card arrangement: one card
-- and a peek on mobile, multiple cards on desktop, fewer larger cards at a distance.
-- The outer page scrolls vertically; each shelf owns horizontal scroll and focus.

local CARD_COUNT = 400

--[[ THE CARD'S WIDTH IS AN ARRANGEMENT, NOT A NUMBER. `Facet.adaptive.cardsPerView`
	answers how many cards belong in view here — one card and a peek of the next
	on a compact touch phone, a multi-up rail on anything larger, fewer and larger
	at a distance — and the rail divides the width it has by that answer. There is
	no size branch in this file. ]]
-- the sliver of the next card a rail always shows: the affordance that there is more
local CARD_PEEK = 40
-- THE PLATE'S OWN TERMS. They used to be named here because `cardHeight` summed
-- exactly these to predict the rail's cross extent; `crossExtent = "hug"` asks
-- the solver instead, so what is left is what the blueprint actually SPENDS.
local CARD_PADDING = 8
local CARD_ROW_GAP = 2
local NAME_SIZE = 14
local BADGE_SIZE = 12
-- The Screen's own frame. It was a NUMBER rather than a spacing token because
-- the viewport arithmetic had to subtract it exactly; that arithmetic is gone,
-- and the constant survives only as the padding the Screen is given.
local PADDING = 12

local BADGES = { "Rally", "Drift", "Circuit", "Sprint", "Endurance" }

--[[ EVERY PLAYER-VISIBLE STRING ON THIS SURFACE, in one table, EXPORTED as the
	module's `copy` field.

	It is one table rather than literals in the tree for one reason: the
	localization case in `tests/examples_gallery.spec.luau` re-runs this whole
	fixture with every one of these strings put through a ~1.4x pseudo-localizing
	expansion, and a check that cannot reach the strings cannot make that claim.
	These three are `policy = "none"` text in the §15.3 sense — they MUST fit,
	wrapping if they have to, and never clip.

	The CARD's own two labels are deliberately not here. A card is a fixed-width
	plate in a rail, so its name and badge declare `lineLimit = 1`: a DECLARED
	truncation (§15.3 `policy = "truncate"`), which is the same ruling the
	row-actions tray reached for its icon-first actions. A fixed-width plate that
	reflowed instead would push the rail past its own cross-axis box. ]]
local COPY = {
	title = "Card rail — your racing collection",
	hint = "Browse each shelf sideways · Up/Down changes shelves · A or Return picks",
	selectedNone = "Selected: none yet — activate a card",
	selectedPrefix = "Selected: ",
	weekendTitle = "Weekend races",
	recommendedTitle = "Recommended for you",
}

return {
	title = "Card rail (horizontal VirtualList)",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI, Compose = ctx.UI, ctx.Compose
		local env = ctx.env

		local cards = {}
		for i = 1, CARD_COUNT do
			table.insert(cards, {
				id = `c{i}`,
				name = string.format("Livery %03d", i),
				badge = BADGES[(i - 1) % #BADGES + 1],
			})
		end
		local items = Compose.cell(cards)
		local lastSelected = Compose.cell(nil :: string?)

		-- The width the rail was actually given, read back from the solve. Until the
		-- first solve reports it, the viewport stands in.
		local measuredWidth = Compose.cell(nil :: number?)
		local measuredHeight = Compose.cell(nil :: number?)
		local railWidth = Compose.formula(function(use)
			return math.max(1, use(measuredWidth) or use(env:get("viewportRect")).w)
		end)
		-- One slot: the rail less the peek, divided by how many cards belong in view.
		-- The gutter between cards is the slot's own trailing padding, a theme step.
		local cardWidth = Compose.formula(function(use)
			local available = use(railWidth)
			local perView = Facet.adaptive.cardsPerView(available, {
				touchPrimary = use(env:get("interactionClasses")).primary == "touch",
				distanceProfile = use(env:get("distanceProfile")),
			})
			return math.max(1, math.floor((available - CARD_PEEK) / perView))
		end)

		local selectedLabel = Compose.formula(function(use)
			local key = use(lastSelected)
			if key == nil then
				return COPY.selectedNone
			end
			for _, card in use(items) :: { any } do
				if card.id == key then
					return `{COPY.selectedPrefix}{card.name} · {card.badge}`
				end
			end
			return `{COPY.selectedPrefix}{key}`
		end)

		-- `card` is a readable of the record the slot shows.
		local function Card(card: any)
			return UI.VStack("Slot")({
				width = UI.fill(),
				padding = { right = "s" },
				UI.VStack("Card")({
					surface = "raised",
					padding = CARD_PADDING,
					gap = CARD_ROW_GAP,
					width = UI.fill(),
					height = { type = "content" },
					UI.ZStack("Preview")({
						width = UI.fill(),
						height = { type = "aspect", ratio = 16 / 9 },
						padding = "m",
						alignH = "center",
						alignV = "center",
						UI.Box("Backdrop")({
							width = UI.fill(),
							height = UI.fill(),
							tint = { role = "accent", blend = 0.18 },
						}),
						UI.Path("Track")({
							width = UI.fill(),
							height = UI.fill(),
							points = Facet.pathShapes.ring({ radius = 0.36 }),
							thickness = 5,
							role = "accent",
						}),
					}),
					UI.Text("Name")({
						text = function(use)
							return use(card).name
						end,
						textSize = NAME_SIZE,
						lineLimit = 1,
					}),
					UI.Text("Badge")({
						text = function(use)
							return use(card).badge
						end,
						textSize = BADGE_SIZE,
						role = "secondary",
						lineLimit = 1,
					}),
				}),
			})
		end

		--[[ THE RAIL IS EXACTLY AS TALL AS ITS CARD. A horizontal list fills its
			cross axis, so something has to say how tall that is, and every term of
			the answer — the plate's padding, two live line boxes, the theme's chrome
			— is a fact the SOLVER holds. The pane therefore stacks the list over one
			hidden horizontal scroller that holds one card of the same width: the solver
			measures that card and the scrollbar band, the pane takes that solved
			height, and the list fills the pane. ]]
		local function Rail(id: string)
			return UI.ZStack(id .. "Pane")({
				width = UI.fill(),
				-- the probe's solved height, so the pane follows the card both ways
				height = function(use)
					local measured = use(measuredHeight)
					return if measured then { type = "fixed", px = measured } else UI.hug()
				end,
				UI.ScrollView("Sizer")({
					axis = "x",
					hidden = true,
					padding = 0,
					gap = 0,
					width = UI.fill(),
					UI.VStack("Probe")({
						width = function(use)
							return { type = "fixed", px = use(cardWidth) }
						end,
						Card(Compose.cell(cards[1])),
					}),
					-- as wide as the rail, so the sizer overflows exactly when the
					-- list does and reserves the same scrollbar band
					UI.Box("Run")({
						width = function(use)
							return { type = "fixed", px = use(railWidth) }
						end,
					}),
				}),
				UI.VirtualList(id)({
					axis = "x",
					rows = items,
					key = function(item: any)
						return item.id
					end,
					itemExtent = cardWidth,
					viewportExtent = "auto",
					overscan = 2,
					-- The cell receives the item; `ctx.current` follows its edits.
					cell = function(_, ctx: any)
						return Card(Compose.formula(ctx.current))
					end,
					onActivate = function(item: any)
						lastSelected:set(item.id)
					end,
				}),
			})
		end

		local function Example()
			return UI.Screen("CardRail")({
				padding = PADDING,
				gap = "tight",

				-- The rails own x and this page owns y: perpendicular, one owner
				-- each, so a thumb that drags down never reaches a rail's handler.
				UI.ScrollView("Page")({
					axis = "y",
					gap = "tight",
					width = UI.fill(),
					height = UI.fill(),
					UI.Text("Title")({ text = COPY.title, textSize = "control" }),
					UI.Text("Hint")({ text = COPY.hint, textSize = "caption", role = "secondary" }),
					Rail("Rail"),
					UI.Text("Selected")({ text = selectedLabel, textSize = 13 }),
					UI.Text("WeekendTitle")({ text = COPY.weekendTitle, textSize = "title" }),
					Rail("WeekendRail"),
					UI.Text("RecommendedTitle")({ text = COPY.recommendedTitle, textSize = "title" }),
					Rail("RecommendedRail"),
				}),
			})
		end

		return {
			screen = Example,
			present = {
				onGeometry = function(rectOf: (string) -> any)
					local pane = rectOf("/CardRail/Page/RailPane")
					if pane ~= nil and pane.w > 0 then
						measuredWidth:set(pane.w)
					end
					local sizer = rectOf("/CardRail/Page/RailPane/Sizer")
					if sizer ~= nil and sizer.h > 0 then
						measuredHeight:set(sizer.h)
					end
				end,
			},
			cardCount = CARD_COUNT,
			-- the gutter rides inside the slot, so slots tile the rail edge to edge
			cardGap = 0,
			itemExtent = function()
				return cardWidth:peek()
			end,
			steps = {
				pick = function(_built: any, payload: string?)
					lastSelected:set(payload or "c1")
					return lastSelected:peek()
				end,
			},
			report = function()
				return {
					axis = "x",
					shelves = 3,
					total = CARD_COUNT,
					itemExtent = cardWidth:peek(),
					selectedKey = lastSelected:peek(),
				}
			end,
			dispose = function() end,
		}
	end,
}
