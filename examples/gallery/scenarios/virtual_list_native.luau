--!strict
-- Scenario 'virtual_list_native' (ledger row NS-A4): VirtualList windows over
-- a FULL-HEIGHT native canvas — 2,000 rows, ~14 mounted, engine scrollbar
-- proportional to the whole list, window sliding from the engine's
-- CanvasPosition via api.bindNativeScroll. Real wheel input drives the
-- engine; the framework only re-windows. keep-visible (focusKey) computes a
-- canvas target and writes controller.scrollTo. The list's own viewport
-- height is a live memo over the real screen (see below), not a constant, so
-- it always fits under the Title on any viewport including a short landscape
-- phone.

-- the cell's authored text size, in ONE place: the row's declared extent and the
-- text it has to hold are the same number by construction, which is the half of
-- the lying-extent class a helper cannot fix on its own
local ROW_TEXT_SIZE = 16

return {
	title = "VirtualList on the native canvas (NS-A4)",
	ledgerRows = { "NS-A4", "NS-A3" },
	build = function(ctx: any)
		local UI = ctx.LuauUI.UI
		local core = ctx.core
		local scope = core:scope("virtual-list-native")

		local items = {}
		for i = 1, 2000 do
			table.insert(items, { id = "r" .. i, label = "Row " .. i })
		end
		local rows = core:signal(items)

		-- THE WINDOW IS A LIVE NUMBER, not a build-time guess (overflow sweep,
		-- 2026-08-12). A fixed `viewportHeight = 360` painted past a 338px — and a
		-- 320px — landscape phone entirely, with nothing to scroll it: the Screen
		-- itself is only 338/320 tall before the framework even reserves its own
		-- chrome, so 360 alone could never fit. `newVirtualList` takes a
		-- Readable<number>, so this memo re-derives the window from the actual
		-- screen every solve — a rotation re-derives in place, no reset.
		--
		-- It reads the SAME facts the renderer reads (`viewportRect` and
		-- `coreSafeInsets`) rather than approximating their sum (lesson: "if you
		-- must reproduce a framework's arithmetic, reproduce its inputs, not its
		-- result"). `chrome` reserves the Screen's own 16px top/bottom padding, the
		-- 8px gap before the list, and a generous budget for the Title row at
		-- textSize 22 — generous on purpose, because over-reserving only shortens
		-- the list (which can never overflow), while under-reserving would squeeze
		-- the title instead.
		local viewportHeight = scope:own(core:memo(function(use)
			local vp: any = use(ctx.env:get("viewportRect"))
			local insets: any = use(ctx.env:get("coreSafeInsets"))
			local h = if type(vp) == "table" and type(vp.h) == "number" then vp.h else 640
			local top = if type(insets) == "table" and type(insets.top) == "number" then insets.top else 0
			local bottom = if type(insets) == "table" and type(insets.bottom) == "number" then insets.bottom else 0
			local chrome = 100
			return math.clamp(math.floor(h - top - bottom - chrome), 72, 600)
		end))

		--[[ THE ROW HEIGHT IS THE LINE BOX ITS CELL WILL MEASURE, not a constant
			(adopted 2026-08-15, docs/plans/variable-item-extents.md).

			WHAT IT WAS: `rowHeight = 36`. The cell is one `UI.Text` at textSize 16, and
			36 is right for exactly one configuration — Studio Neutral, near display,
			default preference. The overflow sweep carried a lying-extent waiver for it:
			on a console-class display at `preferredTextOffset` +14 the row MEASURES 46,
			because the ten-foot type floor multiplies the authored 16 by 1.5 and the
			engine then adds 14px on top. Ten rows of a windowed list, each painting 10px
			into its neighbour.

			IT STAYS A DECLARATION rather than moving to `itemExtent = "measured"`,
			deliberately: this scenario's whole subject is the ENGINE scrollbar being
			proportional to the full 2,000-row canvas (NS-A4), and measured mode makes
			the total canvas an estimate until every row has been seen — the one residual
			cost Stage 2 could not remove. A single-line row at a known authored size is
			also exactly the case a consumer really can predict. So it predicts, with the
			framework's own arithmetic instead of a hand copy of it. ]]
		local rowHeight = scope:own(core:memo(function(use)
			return ctx.LuauUI.text.lineBox({
				facts = ctx.LuauUI.text.facts({ env = ctx.env, use = use }),
				size = ROW_TEXT_SIZE,
				lines = 1,
			})
		end))

		local list = ctx.LuauUI.newVirtualList(ctx.LuauUI, core, {
			id = "VL",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = rowHeight,
			viewportHeight = viewportHeight,
			overscan = 2,
			cell = function(item: any)
				return UI.Text({ id = "Label", text = item.label, textSize = ROW_TEXT_SIZE })
			end,
		})

		local screen = UI.Screen({
			id = "VLNative",
			padding = 16,
			gap = 8,
			children = {
				UI.Text({ id = "Title", text = "VirtualList x2000 (native canvas)", textSize = 22 }),
				list.blueprint,
			},
		})

		local unbind: any = nil
		return {
			screen = screen,
			present = {},
			steps = {
				bind = function(built: any)
					unbind = list.bindNativeScroll(built.handle.controller)
					return list.scrollPath and list.scrollPath() or "bound"
				end,
				focusRow1500 = function()
					-- keep-visible: computes the canvas target and issues the ONE
					-- programmatic scroll write through the bound controller
					return list.focusKey("r1500")
				end,
				mountedCount = function()
					local n = 0
					for _ in list.debugWindow() do
						n += 1
					end
					return n
				end,
			},
			report = function()
				local n, keys = 0, {}
				for key in list.debugWindow() do
					n += 1
					table.insert(keys, key)
				end
				table.sort(keys)
				return {
					mounted = n,
					firstKeys = { keys[1], keys[2], keys[3] },
					scrollTop = list.scrollTop:get(),
				}
			end,
			dispose = function()
				if unbind then
					unbind()
				end
				scope:dispose()
			end,
		}
	end,
}
