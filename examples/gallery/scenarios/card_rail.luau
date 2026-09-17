--!strict
-- Three horizontal shelves share Facet's adaptive card arrangement: one card
-- and a peek on mobile, multiple cards on desktop, fewer larger cards at a distance.
-- The outer page scrolls vertically; each shelf owns horizontal scroll and focus.

local CARD_COUNT = 400
--[[ A CARD'S WIDTH IS NOT A CONSTANT ANY MORE (ADAPT-17, 2026-08-18). It used to
	be 132px — "wide enough for a two-line plate, narrow enough that a 320px phone
	still shows two whole cards and part of a third" — which is a sentence about
	one viewport, written by hand, and therefore wrong on every other one. The rail
	declares `itemExtent = "cards"` instead and the FRAMEWORK sizes the plate from
	how many should be in view here: one card and a peek of the next on a compact
	touch phone, a multi-up rail on anything larger. There is no size branch in
	this file, and that is the point of the declaration. ]]
local CARD_GAP = 8
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
		local UI = Facet.View
		local core = ctx.core
		local scope = core:scope("card-rail")

		local cards = {}
		for i = 1, CARD_COUNT do
			table.insert(cards, {
				id = `c{i}`,
				name = string.format("Livery %03d", i),
				badge = BADGES[(i - 1) % #BADGES + 1],
			})
		end
		local rows = scope:own(core:signal(cards))

		--[[ THE RAIL'S WIDTH IS NOT THIS FILE'S ARITHMETIC ANY MORE (purity audit §4,
			2026-08-22). What stood here was a memo that subtracted `coreSafeInsets`,
			the Screen's own padding and a scrollbar guess from the raw viewport — the
			careful version of doing without an idiom that did not exist. It exists
			now: `viewportExtent = "auto"` takes `fill` along the scroll axis and
			measures what the solver gave, so the three terms this file had to name,
			and the two constants it had to hold to name them, are gone. A rotation
			still re-derives the window in place with no reset and no remount, for the
			same reason it always did — the number is live. ]]

		local function makeRail(id)
			return Facet.Controls.VirtualList(core, {
				id = id,
				-- THE ONE FIELD THIS WHOLE FIXTURE EXISTS FOR
				axis = "x",
				rows = rows,
				key = function(item: any)
					return item.id
				end,
				--[[ THE CARD PARADIGM (ADAPT-17). `"cards"` is the axis-neutral extent
				form that answers "how big is one item" with an ARRANGEMENT instead of a
				number: the rail asks the space it actually got and the live interaction
				class, resolves one card per view (plus a peek) on a compact touch
				surface and a multi-up rail everywhere else, and turns `snap` on for
				the one-up case because a one-card view is a page. Nothing here
				declares a width, a breakpoint or a device. ]]
				itemExtent = "cards",
				cards = { peek = 40 },
				viewportExtent = "auto",
				--[[ ...AND THE CROSS AXIS COMES FROM THE CARD, NOT FROM THE PAGE (§4's
				other half). This rail used to be given a height this file summed by
				hand — the plate's padding, two live line boxes, the theme's chrome
				INSET off the panel slot, its chrome OUTSET, and a slack constant for
				the scrollbar gutter — because `fill` "is a promise the box will be big
				enough, and this box was not" on a 640x320 landscape at the largest
				text preference. Every one of those terms is something the SOLVER
				already knows about the card it is about to lay out, so `"hug"` asks it
				instead: the rail is exactly as tall as its card, and the page takes
				the deficit. ]]
				crossExtent = "hug",
				-- a gap is a gap on either axis: here it is the horizontal gutter
				-- between card slots, and the paradigm above spends it when it decides
				-- how wide one card is
				rowGap = CARD_GAP,
				overscan = 2,
				selection = "single",
				cell = function(item: any)
					return UI.VStack({
						id = "Card",
						surface = "raised",
						padding = CARD_PADDING,
						gap = CARD_ROW_GAP,
						width = UI.fill(),
						height = { type = "content" },

						UI.ZStack({
							id = "Preview",
							width = UI.fill(),
							height = { type = "aspect", ratio = 16 / 9 },
							padding = "m",
							alignH = "center",
							alignV = "center",

							UI.Box({
								id = "Backdrop",
								width = UI.fill(),
								height = UI.fill(),
								tint = { role = "accent", blend = 0.18 },
							}),
							UI.Path({
								id = "Track",
								width = UI.fill(),
								height = UI.fill(),
								points = Facet.pathShapes.ring({ radius = 0.36 }),
								thickness = 5,
								role = "accent",
							}),
						}),
						-- ONE LINE EACH, DECLARED (§15.3 `policy = "truncate"`; see the
						-- COPY note above, which is why neither of these strings is in
						-- that table). Every card in a rail is the same width, so
						-- a long name has nowhere to grow sideways and its only other
						-- option is to reflow — and a plate that grows a line taller
						-- than its neighbours is not a rail. Ellipsis is the contract
						-- here, exactly as it is for the row-actions tray's labels.
						UI.Text({ id = "Name", text = item.name, textSize = NAME_SIZE, lineLimit = 1 }),
						UI.Text({
							id = "Badge",
							text = item.badge,
							textSize = BADGE_SIZE,
							role = "secondary",
							lineLimit = 1,
						}),
					})
				end,
			})
		end
		local rail = makeRail("Rail")
		local weekendRail = makeRail("WeekendRail")
		local recommendedRail = makeRail("RecommendedRail")
		local rails = { rail, weekendRail, recommendedRail }

		local lastSelected = scope:own(core:signal(nil))
		for _, shelf in rails do
			scope:own(core:observe(shelf.selectedKey, function()
				lastSelected:set(shelf.selectedKey:get())
			end))
		end
		local selectedLabel = scope:own(core:memo(function(use)
			local key = use(lastSelected)
			if key == nil then
				return COPY.selectedNone
			end
			for _, card in use(rows) :: { any } do
				if card.id == key then
					return `{COPY.selectedPrefix}{card.name} · {card.badge}`
				end
			end
			return `{COPY.selectedPrefix}{key}`
		end))

		--[[ THE CARD'S OWN HEIGHT WAS ~45 LINES HERE, and its deletion is the point of
			`crossExtent = "hug"`. It summed the plate's padding, two live line boxes,
			the theme's chrome INSET off the `panel` slot, the chrome OUTSET Fantasy
			Ornate declares, and a `RAIL_SLACK` over-reserve for the engine's
			scrollbar gutter — five terms, each of which had to be discovered by a
			device round after the previous sum came out short (12px under Compact
			Pointer at the DEFAULT preference; 16px under Fantasy Ornate at every
			preference; 8px for the bar). Every one of them is a fact the SOLVER holds
			about the card it is about to lay out. The rail hugs now, and the page
			takes the deficit. ]]

		local screen = UI.Screen({
			id = "CardRail",
			padding = PADDING,
			gap = "tight",

			--[[ THE PAGE SCROLLS, AND THE AXIS IS WHY IT MAY (O-21). The rule this
					fixture family keeps — `variable_extents`, `scroll_host` — is that a
					page scroller must not nest inside the scroller the surface exists to
					prove, because a gesture with two owners has none. Here the rail owns
					x and this page owns y: perpendicular, one owner each, and a thumb
					that drags down never reaches the rail's own handler. It is the same
					call `async_images` took when it entered the picker: a surface a
					player can select does not get to overflow. ]]
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "tight",
				width = UI.fill(),
				height = UI.fill(),

				UI.Text({ id = "Title", text = COPY.title, textSize = "control" }),
				UI.Text({ id = "Hint", text = COPY.hint, textSize = "caption", role = "secondary" }),
				-- the rail's cross extent is the rail's own (`crossExtent = "hug"`),
				-- so the pane that holds it takes its content's height rather than
				-- a number this file computed for it
				UI.VStack({
					id = "RailPane",
					gap = 0,
					padding = 0,
					width = UI.fill(),
					height = { type = "content" },
					rail.blueprint,
				}),
				UI.Text({ id = "Selected", text = selectedLabel, textSize = 13 }),
				UI.Text({ id = "WeekendTitle", text = COPY.weekendTitle, textSize = "title" }),
				weekendRail.blueprint,
				UI.Text({ id = "RecommendedTitle", text = COPY.recommendedTitle, textSize = "title" }),
				recommendedRail.blueprint,
			}),
		})

		local unbindScroll: any = nil
		local unbindTick: any = nil

		local result: any = {
			screen = screen,
			present = {},
			-- published for the headless suite and for a reader: the rail itself,
			-- so a test asserts against the control's own window rather than
			-- re-deriving the arithmetic it already publishes
			rail = rail,
			rails = rails,
			cardCount = CARD_COUNT,
			-- THE CONTROL'S OWN NUMBER, for the same reason `report()` reads
			-- `viewportExtent` off the list rather than off this file's memo: the
			-- card width is resolved by the paradigm now, so a constant here would
			-- answer for a size nothing is using.
			itemExtent = function()
				return rail.dump().itemExtent
			end,

			steps = {
				-- keep-visible on the X axis: computes the canvas target and issues
				-- the ONE programmatic scroll write through the bound controller
				focusEnd = function()
					return rail.focusKey(`c{CARD_COUNT}`)
				end,
				focusStart = function()
					return rail.focusKey("c1")
				end,
				focusCard = function(_built: any, payload: string?)
					return rail.focusKey(payload or "c200")
				end,
				pick = function(_built: any, payload: string?)
					rail.select(payload or "c1")
					return rail.selectedKey:get()
				end,
				mountedCount = function()
					local n = 0
					for _ in rail.debugWindow() do
						n += 1
					end
					return n
				end,
			},

			report = function()
				local keys = {}
				for key in rail.debugWindow() do
					table.insert(keys, key)
				end
				table.sort(keys, function(a, b)
					return (tonumber(string.match(a, "c(%d+)")) or 0) < (tonumber(string.match(b, "c(%d+)")) or 0)
				end)
				return {
					axis = "x",
					shelves = #rails,
					mounted = #keys,
					total = CARD_COUNT,
					firstKeys = { keys[1], keys[2], keys[3] },
					-- `scrollTop` on a horizontal list mirrors CanvasPosition.X:
					-- the name predates the field and is public API
					scrollLeft = rail.scrollTop:get(),
					-- THE CONTROL'S OWN NUMBER, not this fixture's memo. Reading the
					-- memo would answer for the value that was DERIVED whether or not
					-- the list was ever handed it — so a rail wired to a constant
					-- would report a live width it is not using, and the check that
					-- the width tracks the viewport could not fail. Ask the list.
					viewportExtent = rail.dump().viewportExtent,
					focusedKey = rail.focusedKey:get(),
					selectedKey = rail.selectedKey:get(),
					bound = unbindScroll ~= nil,
				}
			end,

			dispose = function()
				if unbindTick ~= nil then
					unbindTick()
					unbindTick = nil
				end
				if unbindScroll ~= nil then
					unbindScroll()
					unbindScroll = nil
				end
				for _, shelf in rails do
					shelf.dispose()
				end
				scope:dispose()
			end,
		}

		-- SELF-WIRED, for host path 2 (see the header). `result.handle` is the
		-- field both hosts write right after `present`, so the first tick after
		-- the surface actually exists is the one that binds the mirror.
		unbindTick = ctx.presenter.onTick(function()
			if unbindScroll ~= nil or result.handle == nil then
				return
			end
			if rail.scrollPath() == nil then
				return
			end
			local unbinds = {}
			for _, shelf in rails do
				table.insert(unbinds, shelf.bindNativeScroll(result.handle.controller))
			end
			unbindScroll = function()
				for _, unbind in unbinds do
					unbind()
				end
			end
		end)

		return result
	end,
}
