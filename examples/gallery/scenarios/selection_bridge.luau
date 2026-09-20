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
		local UI = ctx.UI
		local app = ctx.app
		local pres = ctx.presenter

		local closeModal: (() -> ())? = nil
		local function openModal()
			local function modal()
				local list = {
					height = { type = "fixed", px = 200 },
					width = { type = "fixed", px = 250 },
					padding = "xs",
				} :: { [any]: any }
				for i = 1, 14 do
					table.insert(
						list,
						UI.Button("Row" .. i)({
							label = "Choice " .. i,
							width = { type = "fixed", px = 220 },
							height = { type = "fixed", px = 36 },
							onActivate = function() end,
						})
					)
				end
				return UI.VStack("BridgeModal")({
					padding = 12,
					gap = "s",
					surface = "raised",
					active = true,
					width = { type = "fixed", px = 280 },

					UI.Text("MTitle")({ text = "Pick one", textSize = "control" }),
					UI.ScrollView("MList")(list),
					UI.Button("Close")({
						label = "Close",
						onActivate = function()
							if closeModal ~= nil then
								closeModal()
								closeModal = nil
							end
						end,
					}),
				})
			end
			closeModal = app.presentModal(modal, { engineSelectionBridge = true })
			return true
		end

		local function baseScreen()
			return UI.Screen("BridgeBase")({
				-- THEME-OPT-OUT: the same 640x320-at-+14 squeeze as the gap below — measured at
				-- 6px past the box with `padding = "m"` under glossy-mobile.
				padding = 16,
				-- THEME-OPT-OUT: this base screen holds a title and a button with no scroller,
				-- and 640x320 landscape at +14 leaves it nothing spare. Measured on the theme's
				-- own step: `gap = "s"` costs 2px past the box under glossy-mobile. It waits on
				-- the fixture giving the page somewhere to go.
				gap = 8,

				UI.Text("Title")({ text = "Selection bridge (base stays nil)", textSize = 22 }),
				UI.Button("Open")({ label = "Open modal", onActivate = openModal }),
			})
		end

		return {
			screen = baseScreen,
			present = {},
			steps = {
				openModal = openModal,
				focusRow2 = function()
					pres.focus.focusOn("/BridgeModal/MList/Row2")
					return pres.focus.focused:peek()
				end,
				focusRow12 = function()
					-- off-view row: measured native autoscroll should reveal it
					pres.focus.focusOn("/BridgeModal/MList/Row12")
					return pres.focus.focused:peek()
				end,
				closeModal = function()
					if closeModal ~= nil then
						closeModal()
						closeModal = nil
					end
					return true
				end,
			},
			report = function()
				return { focused = pres.focus.focused:peek() }
			end,
		}
	end,
}
