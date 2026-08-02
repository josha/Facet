--!strict
-- ============================================================================
-- Example 4 of the LuauUI tutorial: a confirmation dialog.
-- ============================================================================
--
-- WHAT THIS TEACHES  —  the presenter stack
--   * modal presentation — presenter.presentModal opens a screen ON TOP of the
--                          current one
--   * focus trap         — while the modal is open, keyboard/gamepad focus
--                          cannot leave it; navigation wraps inside
--   * cancel routing      — the gamepad B button dismisses the modal
--   * focus restoration  — dismissing the modal returns focus to the control
--                          that was focused before it opened
--
-- This is the first example that uses `deps` at runtime: the button's action
-- calls deps.presenter.presentModal to open the dialog.
--
-- deps used: presenter (see 01's header for the shared module shape).

local example = {}
example.title = "Confirmation Dialog"

function example.build(LuauUI: any, core: any, deps: any)
	local UI = LuauUI.UI
	local presenter = deps.presenter

	-- Records the outcome so the tutorial / tests can observe it.
	local result = core:signal("none") -- "none" | "confirmed" | "cancelled"

	-- Track the live modal handle so a button's own onActivate can dismiss it.
	local currentModal: any = nil

	-- The modal blueprint: a prompt and two buttons. It is presented lazily,
	-- only when the user asks to delete. Each button carries its APP SEMANTICS
	-- on its node onActivate: the presenter dispatches Activate (tap, or
	-- Return/A on the focused button) here with no consumer routing (ADR-0013).
	-- The gamepad B button / Cancel routing dismisses WITHOUT reaching these —
	-- the presenter handles that and restores focus on its own.
	-- A MODAL IS A SCRIM PLUS A PANEL, and it needs to LOOK like one.
	--
	-- This dialog had neither: the screen was transparent, so on a device the
	-- prompt and its two buttons floated loose over whatever was behind them with
	-- no boundary at all, and "Delete" — a destructive, irreversible action — sat
	-- unframed on top of the very screen it was about to change. Found on an
	-- iPhone 15 Pro; in Studio over a plain baseplate it had looked merely plain.
	--
	-- `scrim` dims what is behind so the dialog owns the screen; `raised` gives
	-- the card its edge; centring it says "this is the thing to answer".
	local dialog = UI.Screen({
		id = "ConfirmDialog",
		surface = "scrim",
		padding = 16,
		alignH = "center",
		alignV = "center",
		children = {
			UI.VStack({
				id = "Card",
				surface = "raised",
				padding = "m",
				gap = "s",
				children = {
					UI.Text({ id = "Prompt", text = "Delete this save? This cannot be undone.", textSize = 18 }),
					UI.Button({
						id = "Confirm",
						label = "Delete",
						onActivate = function()
							result:set("confirmed")
							presenter.dismiss(currentModal)
						end,
					}),
					UI.Button({
						id = "Cancel",
						label = "Cancel",
						onActivate = function()
							result:set("cancelled")
							presenter.dismiss(currentModal)
						end,
					}),
				},
			}),
		},
	})

	local function openDialog()
		currentModal = presenter.presentModal(dialog)
	end

	-- The base screen: a single destructive button whose node onActivate opens
	-- the dialog (again, dispatched by the presenter with no present() opts).
	local screen = UI.Screen({
		id = "DangerScreen",
		padding = 16,
		gap = 8,
		children = {
			UI.Text({ id = "Title", text = "Save Slot 1", textSize = 24 }),
			UI.Button({ id = "Delete", label = "Delete Save", onActivate = openDialog }),
		},
	})

	return {
		screen = screen,
		result = result, -- "none" | "confirmed" | "cancelled"
		openDialog = openDialog, -- open the modal directly (tutorial convenience)
	}
end

return example
