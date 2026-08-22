--!strict
-- Scenario 'selection_bridge' (ledger rows NS-A11/NS-A12): the passive base
-- screen keeps GuiService.SelectedObject nil; an OPTED-IN modal mirrors
-- Facet's logical focus to engine selection (Selectable flipped only while
-- mirrored), follows focus moves, exercises the measured native autoscroll
-- (focusing an off-view row inside the modal's ScrollView), and clears on
-- dismissal. Steps are logical-focus drivers (downstream action proof); real
-- pad arbitration is the physical row NS-P1.

return {
	title = "Engine-selection bridge (NS-A11/NS-A12)",
	ledgerRows = { "NS-A11", "NS-A12" },
	build = function(ctx: any)
		local UI = ctx.Facet.UI
		local pres = ctx.presenter

		local baseScreen = UI.Screen({
			id = "BridgeBase",
			-- THEME-OPT-OUT: the same 640x320-at-+14 squeeze as the gap below — measured at
			-- 6px past the box with `padding = "m"` under glossy-mobile.
			padding = 16,
			-- THEME-OPT-OUT: this base screen holds a title and a button with no scroller,
			-- and 640x320 landscape at +14 leaves it nothing spare. Measured on the theme's
			-- own step: `gap = "s"` costs 2px past the box under glossy-mobile. It waits on
			-- the fixture giving the page somewhere to go.
			gap = 8,
			children = {
				UI.Text({ id = "Title", text = "Selection bridge (base stays nil)", textSize = 22 }),
				UI.Button({ id = "Open", label = "Open modal" }),
			},
		})

		local modalHandle: any = nil
		local function openModal()
			local rows = {}
			for i = 1, 14 do
				table.insert(
					rows,
					UI.Button({
						id = "Row" .. i,
						label = "Choice " .. i,
						width = { type = "fixed", px = 220 },
						height = { type = "fixed", px = 36 },
					})
				)
			end
			local modal = UI.VStack({
				id = "BridgeModal",
				padding = 12,
				gap = "s",
				surface = "raised",
				active = true,
				width = { type = "fixed", px = 280 },
				children = {
					UI.Text({ id = "MTitle", text = "Pick one", textSize = "control" }),
					UI.ScrollView({
						id = "MList",
						height = { type = "fixed", px = 200 },
						width = { type = "fixed", px = 250 },
						padding = "xs",
						children = rows,
					}),
					UI.Button({ id = "Close", label = "Close" }),
				},
			})
			modalHandle = pres.presentModal(modal, { engineSelectionBridge = true })
			return true
		end

		return {
			screen = baseScreen,
			present = {},
			steps = {
				openModal = openModal,
				focusRow2 = function()
					pres.focus.focusOn("/BridgeModal/MList/Row2")
					return pres.focus.focused:get()
				end,
				focusRow12 = function()
					-- off-view row: measured native autoscroll should reveal it
					pres.focus.focusOn("/BridgeModal/MList/Row12")
					return pres.focus.focused:get()
				end,
				closeModal = function()
					if modalHandle ~= nil then
						pres.dismiss(modalHandle)
						modalHandle = nil
					end
					return true
				end,
			},
			report = function()
				return { focused = pres.focus.focused:get() }
			end,
		}
	end,
}
