--!strict
--[[ Scenario 'card_rail' — THE SIDEWAYS VIRTUALIZER, as a surface you can hold.

	`newVirtualList` gained `axis = "x"` in SwiftUI-parity round 2
	(docs/plans/swiftui-parity-round2.md §2.3; game-director decision
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
	    `scenarios/virtual_list_native.luau` still covers, deliberately.

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
	     attribute `LuauUI_Scenario`): full ctx, `_G.LuauUIScenario` drives the
	     steps below by name, and the bootstrap ticks and refreshes every frame.
	  2. THE SHOWCASE DEMO PICKER (`examples/gallery/client/init.client.luau`,
	     `mountDemo`, `kind == "fixture"`): the MINIMAL ctx
	     `{LuauUI, core, env, actionSystem, presenter}` — no adapter, and NO step
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
-- A card's WIDTH (the main axis here). Wide enough for a two-line plate at the
-- shipped text sizes, narrow enough that the narrowest supported viewport
-- (320px, less its chrome) still shows two whole cards and part of a third —
-- a rail that shows exactly one card teaches nothing about windowing.
local ITEM_EXTENT = 132
local CARD_GAP = 8
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
		local LuauUI = ctx.LuauUI
		local UI = LuauUI.UI
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

		local rail = LuauUI.newVirtualList(LuauUI, core, {
			id = "Rail",
			-- THE ONE FIELD THIS WHOLE FIXTURE EXISTS FOR
			axis = "x",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			-- the axis-neutral names: on this list they mean WIDTH, and the
			-- deprecated `rowHeight`/`viewportHeight` spellings would be lies
			itemExtent = ITEM_EXTENT,
			viewportExtent = viewportExtent,
			-- a gap is a gap on either axis: here it is the horizontal gutter
			-- between card slots, and the card itself stays ITEM_EXTENT wide
			rowGap = CARD_GAP,
			overscan = 2,
			selection = "single",
			cell = function(item: any)
				return UI.VStack({
					id = "Card",
					surface = "raised",
					padding = 8,
					gap = 2,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						-- ONE LINE EACH, DECLARED (§15.3 `policy = "truncate"`; see the
						-- COPY note above, which is why neither of these strings is in
						-- that table). A card is ITEM_EXTENT wide on every viewport, so
						-- a long name has nowhere to grow sideways and its only other
						-- option is to reflow — and a plate that grows a line taller
						-- than its neighbours is not a rail. Ellipsis is the contract
						-- here, exactly as it is for the row-actions tray's labels.
						UI.Text({ id = "Name", text = item.name, textSize = 14, lineLimit = 1 }),
						UI.Text({
							id = "Badge",
							text = item.badge,
							textSize = 12,
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

		local screen = UI.Screen({
			id = "CardRail",
			padding = PADDING,
			gap = 6,
			children = {
				UI.Text({ id = "Title", text = COPY.title, textSize = 18 }),
				UI.Text({ id = "Hint", text = COPY.hint, textSize = 12, role = "secondary" }),
				-- THE RAIL FILLS WHAT IS LEFT. Its own height is the CROSS axis of a
				-- horizontal list, which fills its container by construction (a
				-- horizontal list refuses a `width`, because there the width IS the
				-- scroll axis) — so the box it gets is whatever the three labels
				-- around it did not take, and it can never demand more.
				UI.VStack({
					id = "RailPane",
					gap = 0,
					padding = 0,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = { rail.blueprint },
				}),
				UI.Text({ id = "Selected", text = selectedLabel, textSize = 13 }),
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
			itemExtent = ITEM_EXTENT,

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
