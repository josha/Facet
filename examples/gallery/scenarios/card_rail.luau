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
-- THE PLATE'S OWN TERMS, named once because `cardHeight` below sums exactly
-- these and the blueprint spends exactly these — the row-height lesson's rule
-- that the arrangement and the extent are ONE decision.
local CARD_PADDING = 8
local CARD_ROW_GAP = 2
local NAME_SIZE = 14
local BADGE_SIZE = 12
-- The Screen's own frame, as a NUMBER rather than a spacing token, because the
-- viewport arithmetic below has to subtract it exactly. A token would be a
-- theme fact this file cannot read at build time.
local PADDING = 12
-- What the rail gives back to the world beyond its own frame: the engine's
-- scrollbar gutter plus a pixel of rounding slack. Over-reserving shortens the
-- rail; under-reserving paints it past the screen edge.
local RAIL_SLACK = 12

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

		-- PROBE-EXEMPT BEGIN: a HAND-DERIVED viewport, and a gap rather than a lesson.
		-- `newVirtualList.viewportExtent` is asserted REQUIRED with no self-measuring
		-- form, so this memo re-derives from raw env facts what the framework already
		-- has: it subtracts `coreSafeInsets`, the Screen's padding and a scrollbar
		-- guess by hand. The idiom a reader should copy does not exist yet
		-- (`viewportExtent = "auto"`, purity audit MOVE §4); this is the careful
		-- version of doing without it, not a pattern.
		-- THE RAIL'S WIDTH IS A LIVE NUMBER (see the header). `newVirtualList`
		-- takes a Readable<number> for `viewportExtent`, so a rotation re-derives
		-- the window in place with no reset and no remount.
		local viewportExtent = scope:own(core:memo(function(use)
			local vp: any = use(ctx.env:get("viewportRect"))
			local insets: any = use(ctx.env:get("coreSafeInsets"))
			local w = if type(vp) == "table" and type(vp.w) == "number" then vp.w else 800
			local left = if type(insets) == "table" and type(insets.left) == "number" then insets.left else 0
			local right = if type(insets) == "table" and type(insets.right) == "number" then insets.right else 0
			return math.clamp(math.floor(w - left - right - PADDING * 2 - RAIL_SLACK), 96, 1600)
		end))
		-- PROBE-EXEMPT END

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
			viewportExtent = viewportExtent,
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

		--[[ THE CARD'S OWN HEIGHT, DERIVED FROM THE SAME FACTS IT PAINTS WITH
			(O-21, 2026-08-15) — the `sponsor_list` row-height idiom, applied to the
			CROSS axis of a horizontal list.

			WHAT IT WAS: `RailPane` took `height = fill`, i.e. "whatever the three
			labels around it did not take, and it can never demand more". On a
			640x320 landscape at the largest text preference the three labels took
			all but 23px, the plate needed 84, and the rail's clip host cut the
			`Rally` badge 61px below its own window — where nothing scrolls it back,
			because the axis that scrolls here is x. `fill` is a promise the box will
			be big enough, and this box was not.

			The plate's height is not a mystery: it is its own padding, one 14pt line,
			its own 2px gap and one 12pt line, every term read from the live text
			facts so a text-size preference or a theme face moves the plate and the
			rail together. Declaring it is what lets the PAGE take the deficit
			instead — see the scroller below. ]]
		local cardHeight = scope:own(core:memo(function(use)
			local facts = Facet.text.facts({ env = ctx.env, use = use })
			local box = CARD_PADDING * 2
				+ Facet.text.lineBox({ facts = facts, size = NAME_SIZE, lines = 1 })
				+ CARD_ROW_GAP
				+ Facet.text.lineBox({ facts = facts, size = BADGE_SIZE, lines = 1 })
			--[[ ...PLUS WHAT THE THEME CARVES OUT OF THE PLATE. `surface = "raised"`
				classifies to the `panel` chrome slot, and a package whose panel art has
				a border reserves that border off the node's content box before anything
				inside it is measured (`layout_node.luau`, "a chrome inset is a request,
				not a right"). Measured 2026-08-15: under Compact Pointer the plate's
				own top inset was 16px against the authored 8, so a height summed from
				padding + two line boxes alone came out 12px short on EVERY card at the
				DEFAULT preference — the theme axis this fixture's first fix was blind
				to. `hasChromeInsets` is the snapshot's own answer to "is there anything
				to spend": every slot publishes an entry now, zero included. ]]
			local metrics: any = facts.metrics
			local chrome = if type(metrics) == "table"
					and metrics.hasChromeInsets == true
					and type(metrics.chromeInsets) == "table"
				then metrics.chromeInsets.panel
				else nil
			local chromeV = if type(chrome) == "table"
				then (tonumber(chrome.top) or 0) + (tonumber(chrome.bottom) or 0)
				else 0
			-- ...and the OUTSET, which is the same fact pointing the other way: art
			-- that bleeds past the plate is realised as a margin, so the plate itself
			-- is that much smaller inside the row the list gave it. Fantasy Ornate is
			-- the one shipped package that declares one (20px off the top), and
			-- without this term its cards came out 16px short at every preference.
			local bleed = if type(metrics) == "table" and type(metrics.chromeOutsets) == "table"
				then metrics.chromeOutsets.panel
				else nil
			local bleedV = if type(bleed) == "table"
				then (tonumber(bleed.top) or 0) + (tonumber(bleed.bottom) or 0)
				else 0
			-- ...and the rail's OWN gutter, which on a horizontal scroller comes off
			-- the bottom: the pane holds the list, the list holds a bar, and a plate
			-- sized to the pane would be exactly `scrollBarThickness` too tall (8px,
			-- measured). `RAIL_SLACK` is the same over-reserve this file already
			-- spends on the width, on the other axis and for the same reason — a
			-- slightly taller pane is empty space the page scrolls past, a slightly
			-- shorter one clips the badge.
			return { type = "fixed", px = math.ceil(box + chromeV + bleedV) + RAIL_SLACK }
		end))

		local screen = UI.Screen({
			id = "CardRail",
			padding = PADDING,
			gap = 6,
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
					gap = 6,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "control" }),
						UI.Text({ id = "Hint", text = COPY.hint, textSize = "caption", role = "secondary" }),
						-- the rail's cross extent is now the plate's own measured height
						-- (above) rather than the page's leftover
						UI.VStack({
							id = "RailPane",
							gap = 0,
							padding = 0,
							width = { type = "fill", weight = 1 },
							height = cardHeight,
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
