--!strict
-- ============================================================================
-- Example 1 of the LuauUI tutorial: a temperature converter.
-- ============================================================================
--
-- WHAT THIS TEACHES
--   * state          — holding values in reactive "signals"
--   * bindings       — a "memo" that derives a display string, bound to a Text
--   * text entry     — a real UI.TextInput, and its TWO edit modes:
--                        - LIVE   (onChange): a Celsius preview that tracks
--                                 every keystroke as you type
--                        - COMMIT (onCommit): the final Result, which updates
--                                 ONLY when you press Enter or leave the field
--
-- The user types degrees Fahrenheit into a numeric field. A live preview shows
-- the Celsius value as they type; the committed Result updates only when the
-- edit is finished. The field is the PRIMARY (and only) input affordance —
-- earlier tutorial builds used stepper buttons because there was no editable
-- text-box control; now that UI.TextInput ships, the field replaces them.
--
-- ----------------------------------------------------------------------------
-- HOW EVERY EXAMPLE IN THIS FOLDER IS SHAPED
--   Each module returns:  { title = "...", build = function(LuauUI, core, deps) }
--   `deps` is always the same four-field table:
--       { env, actionSystem, presenter, adapter }
--   This example uses `env` (keyboard-occlusion keep-visible) and `actionSystem`
--   (the text-entry sinking context) by handing them to the TextInput. `build`
--   returns { screen = <Blueprint>, present = <presenter opts>, ...handles };
--   the caller presents it with: presenter.present(built.screen, built.present)
-- ----------------------------------------------------------------------------

local example = {}
example.title = "Temperature Converter"

-- NUMERIC GRAMMAR (documented, tested) --------------------------------------
-- The field accepts only text that could be part of a number: an optional
-- leading '-', digits, and at most one '.'. The pattern also accepts the
-- in-progress states a user passes THROUGH while typing ("", "-", ".", "-.")
-- so the field never blocks a keystroke on the way to a valid number. It
-- rejects letters, '+', and a second '.'. `validate` returns the accepted
-- text, or nil to reject the edit (the value is left unchanged).
local function acceptNumeric(proposed: string): string?
	if string.match(proposed, "^%-?%d*%.?%d*$") ~= nil then
		return proposed
	end
	return nil
end

local function toCelsius(f: number): number
	return (f - 32) * 5 / 9
end

function example.build(LuauUI: any, core: any, deps: any)
	local UI = LuauUI.UI

	-- STATE ------------------------------------------------------------------
	-- The field's contents are TEXT (owner-held, per §10.5: state that must
	-- outlive the control belongs to the caller). It starts empty so the
	-- placeholder guides the first keystroke.
	local fahrenheitText = core:signal("")
	-- The LIVE preview value: nil until the text parses to a number. Written
	-- by onChange, so it tracks every accepted keystroke.
	local liveCelsius = core:signal(nil :: number?)
	-- The COMMITTED result: nil = "nothing committed yet". Written by onCommit,
	-- so it changes only when the user finishes the edit (Enter / focus loss).
	local celsius = core:signal(nil :: number?)

	-- BINDINGS ---------------------------------------------------------------
	-- Two memos turn the two Celsius values into their display strings. Each
	-- recomputes only when the value it reads changes, and is bound to a Text
	-- by being passed as the `text` prop — so a change repaints just that label.
	local previewLabel = core:memo(function(use)
		local c = use(liveCelsius)
		if c == nil then
			return "Preview: —"
		end
		return string.format("Preview: %g °C  (live, as you type)", c)
	end)
	local resultLabel = core:memo(function(use)
		local c = use(celsius)
		if c == nil then
			return "Result: —"
		end
		return string.format("Result: %g °C", c)
	end)

	-- THE FIELD --------------------------------------------------------------
	-- A real single-line text field. `value` is our owner-held text signal;
	-- the two callbacks are the whole lesson:
	--   onChange — LIVE mode: fires on every accepted edit while typing. We
	--              parse and update `liveCelsius`, which repaints the preview.
	--   onCommit — COMMIT mode: fires on Enter ("enter") or focus loss
	--              ("focusLost"). We parse and update `celsius`, which repaints
	--              the Result. Nothing commits until the edit is finished.
	-- keyboardType is a DECLARED INTENT for the engine adapter (a hint it may
	-- honor where a numeric keyboard exists — it is never a guarantee); the
	-- validate hook is what actually enforces numeric input everywhere.
	local field = LuauUI.newTextInput(LuauUI, core, {
		id = "Fahrenheit",
		value = fahrenheitText,
		placeholder = "e.g. 212",
		keyboardType = "numeric",
		validate = acceptNumeric,
		onChange = function(text: string)
			local n = tonumber(text)
			liveCelsius:set(if n ~= nil then toCelsius(n) else nil)
		end,
		onCommit = function(text: string, _reason: "enter" | "focusLost")
			local n = tonumber(text)
			celsius:set(if n ~= nil then toCelsius(n) else nil)
		end,
		env = deps and deps.env,
		actionSystem = deps and deps.actionSystem,
	})

	-- CLEAR: the deterministic way back to the starting state. Without it the only
	-- route out of a typed value was select-all-and-delete, which is not a lesson
	-- and not discoverable (example-quality-pass play audit, 2026-08-06).
	local function clear()
		fahrenheitText:set("")
		liveCelsius:set(nil)
		celsius:set(nil)
	end

	-- THE SCREEN -------------------------------------------------------------
	-- STYLE AUTHORITY: `textSize` names a typography ROLE and the spacing names a
	-- step, so a theme package moves both. The px numbers that used to sit here
	-- (24/14/16/20, padding 16, gap 8) were the same under every package, which is
	-- exactly what made the example immune to the theme picker mounted beside it.
	--
	-- `surface = "base"` because the tutorial is a SCREEN, not loose text over
	-- whatever 3D world the place happens to have: on the gallery's baseplate the
	-- secondary prompt was the least legible thing on it.
	local screen = UI.Screen({
		id = "TempConverter",
		surface = "base",
		padding = "m",
		children = {
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "s",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.Text({ id = "Title", text = "Fahrenheit → Celsius", textSize = "title" }),
					UI.Text({
						id = "Prompt",
						text = "Enter a temperature in °F:",
						textSize = "label",
						role = "secondary",
					}),
					field.blueprint,
					-- LIVE: recomputes on every keystroke (onChange)
					UI.Text({ id = "Preview", text = previewLabel, textSize = "body", role = "secondary" }),
					-- COMMITTED: recomputes only when the edit is finished (onCommit)
					UI.Text({ id = "Result", text = resultLabel, textSize = "heading" }),
					UI.Button({ id = "Clear", label = "Clear", onActivate = clear }),
				},
			}),
		},
	})

	-- PRESENTER WIRING -------------------------------------------------------
	-- None. Mounting the TextInput is enough: the control attaches an input
	-- contribution to its root node, and the presenter auto-composes the field's
	-- whole four-input story from it (ADR-0013) — Activate routes into the field
	-- (a tap, or Return/ButtonA on the focused field, enters edit mode), the
	-- keyboard-occlusion geometry + keep-visible offset are fed automatically,
	-- and the action system is bound so entering edit raises the field's own
	-- high-priority sinking context that swallows arrows/D-pad while typing. This
	-- example therefore passes NO present() opts.

	return {
		screen = screen,
		-- handles the tutorial / tests reach for:
		fahrenheitText = fahrenheitText, -- the field's editable text (owner-held)
		liveCelsius = liveCelsius, -- the live preview value (onChange)
		celsius = celsius, -- the committed result (onCommit)
		resultLabel = resultLabel, -- the bound committed display string
		field = field, -- the TextInput control (api.editing, etc.)
		clear = clear, -- the Clear button's command (back to the starting state)
		clearPath = "/TempConverter/Page/Clear",
		dispose = function()
			field.dispose()
			fahrenheitText:dispose()
			liveCelsius:dispose()
			celsius:dispose()
		end,
	}
end

return example
