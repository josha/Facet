--!strict
-- Scenario 'virtual_list_native' (ledger row NS-A4): VirtualList windows over
-- a FULL-HEIGHT native canvas — 2,000 rows, ~14 mounted, engine scrollbar
-- proportional to the whole list, window sliding from the engine's
-- CanvasPosition via api.bindNativeScroll. Real wheel input drives the
-- engine; the framework only re-windows. keep-visible (focusKey) computes a
-- canvas target and writes controller.scrollTo.

return {
	title = "VirtualList on the native canvas (NS-A4)",
	ledgerRows = { "NS-A4", "NS-A3" },
	build = function(ctx: any)
		local UI = ctx.LuauUI.UI
		local core = ctx.core

		local items = {}
		for i = 1, 2000 do
			table.insert(items, { id = "r" .. i, label = "Row " .. i })
		end
		local rows = core:signal(items)

		local list = ctx.LuauUI.newVirtualList(ctx.LuauUI, core, {
			id = "VL",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = 36,
			viewportHeight = 360,
			overscan = 2,
			cell = function(item: any)
				return UI.Text({ id = "Label", text = item.label, textSize = 16 })
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
			end,
		}
	end,
}
