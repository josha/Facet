--!strict
--[[ Scenario 'card_rail' — THE SIDEWAYS VIRTUALIZER, as a surface you can hold.

	`newVirtualList` gained `axis = "x"` in parity round 2
	(docs/plans/parity-round2.md §2.3; game-director decision
	2026-08-12). The standing obligation is that every new public API appears in
	a gallery scenario the headless suite executes, and this is that scenario for
	the horizontal axis — 400 cards on ONE row, ~4 mounted, stepped Left/Right by
	a keyboard or a D-pad and flung sideways by a thumb.

	WHAT A VERTICAL LIST CANNOT SHOW, and therefore what this fixture is FOR:

	  · the scroll axis and the FOCUS axis agree. The list declares its own axis
	    to the focus graph, so Left/Right (and DPadLeft/DPadRight) step the rail
	    and Up/Down do nothing at all here — one focus map read one way
	    (constitution §9), never a second order;
	  · the canvas is full-WIDTH and the window is read off `CanvasPosition.X`.
	    `scrollTop` keeps its name and mirrors X (the name predates the field);
	  · the extents are named for the AXIS, not for "down": `itemExtent` is a
	    card's WIDTH here and `viewportExtent` is the rail's WIDTH. The
	    deprecated `rowHeight`/`viewportHeight` aliases would be lying names on
	    this list, so this fixture uses the canonical pair exclusively — a
	    vertical caller passing the old names is the case
	    `scenarios/virtual_list_native.luau` still covers, deliberately;
	  · and the CARD PARADIGM (ADAPT-17): `itemExtent = "cards"` makes this the
	    surface where "a swipeable one-up carousel on a phone, a multi-up rail on
	    a desktop" is a DECLARATION rather than a screen-level branch. Pick this
	    demo on a phone and one card fills the rail with the next one peeking;
	    pick it on a desktop and five sit side by side. Nothing in this file
	    knows which of those is happening.

	NO ROW ACTIONS HERE, AND THAT IS NOT AN OVERSIGHT. `rowActions` is REFUSED at
	construction on a horizontal list: a tray is opened by a sideways swipe, and
	on a sideways list a sideways swipe is already how the player scrolls. The
	fixture that demonstrates trays is `scenarios/row_actions.luau`, on the
	vertical axis where the two gestures are perpendicular.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT. `viewportExtent` is a live
	memo over the real screen — the same shape and the same reasoning as
	`virtual_list_native.luau`'s live window, which exists because a constant
	painted a rail past a 320px phone. It reads the facts the renderer reads
	(`viewportRect`, `coreSafeInsets`) rather than approximating their sum, and
	over-reserves on purpose: a shorter rail can never overflow, a longer one
	silently paints off the right edge where no main-axis diagnostic looks.

	TWO HOSTS MOUNT THIS FILE, AND ONLY ONE OF THEM RUNS STEPS.

	  1. THE SCENARIO RUNNER (`scenarios/runner.luau`, selected by the workspace
	     attribute `Facet_Scenario`): full ctx, `_G.FacetScenario` drives the
	     steps below by name, and the bootstrap ticks and refreshes every frame.
	  2. THE SHOWCASE DEMO PICKER (`examples/gallery/client/init.client.luau`,
	     `mountDemo`, `kind == "fixture"`): the MINIMAL ctx
	     `{Facet, core, env, actionSystem, presenter}` — no adapter, and NO step
	     ever runs. A player reaches this rail by picking "Card rail" from the
	     chip, and everything they can do to it must therefore work with no
	     scripted help at all.

	Path 2 is why the native-scroll mirror is bound off `presenter.onTick` below
	rather than from a `bind` step: the showcase's generic auto-bind loop runs
	only on the tutorial-EXAMPLE branch, so a fixture that waited to be bound
	would never mirror `CanvasPosition` and keep-visible would never scroll a
	focused card into view — for the one host where a real thumb is doing the
	scrolling. (`scenarios/row_actions.luau` learned this the same way.)
]]

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
	title = "Card rail — 400 cards, one row",
	hint = "Swipe sideways · Left/Right or D-pad steps · Return or A picks",
	selectedNone = "Selected: none yet — activate a card",
	selectedPrefix = "Selected: ",
}

return {
	title = "Card rail (horizontal VirtualList)",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
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

		local rail = Facet.Controls.VirtualList(core, {
			id = "Rail",
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
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
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
					},
				})
			end,
		})

		local selectedLabel = scope:own(core:memo(function(use)
			local key = use(rail.selectedKey)
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
			children = {
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
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "control" }),
						UI.Text({ id = "Hint", text = COPY.hint, textSize = "caption", role = "secondary" }),
						-- the rail's cross extent is the rail's own (`crossExtent = "hug"`),
						-- so the pane that holds it takes its content's height rather than
						-- a number this file computed for it
						UI.VStack({
							id = "RailPane",
							gap = 0,
							padding = 0,
							width = { type = "fill", weight = 1 },
							height = { type = "content" },
							children = { rail.blueprint },
						}),
						UI.Text({ id = "Selected", text = selectedLabel, textSize = 13 }),
					},
				}),
			},
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
				rail.dispose()
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
			unbindScroll = rail.bindNativeScroll(result.handle.controller)
		end)

		return result
	end,
}
