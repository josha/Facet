--!strict
-- Stepper: a labelled value with discrete decrement/increment affordances
-- (docs/plans/swiftui-parity-next.md investment 4; acceptance rows B-VAL1/B-VAL3).
-- Composed from shipped primitives — an HStack of a label, a value readout, and
-- two Buttons — over the SHARED value model (src/controls/value_model.luau), so
-- bounds, stepping, rounding and formatting are the same arithmetic a Slider uses.
--
-- THREE AXES (affordance matrix §A; UI-PARADIGM-001..003):
--   1. UI (layout)   — one HStack row; both buttons carry the Button contract's
--                      44px floor, which the renderer now ENFORCES in hit
--                      geometry (B-BTN3), so the row is a touch target at any
--                      visual density.
--   2. INPUT (reach) — pointer/touch reach the two Buttons; keyboard and gamepad
--                      reach the SAME arithmetic through the focus-gated Adjust
--                      verb, so no input class needs a different code path.
--   3. PARADIGM      — pointer: hover preview on the buttons (free from the
--                      primitive); touch: the enforced hit floor; keyboard:
--                      focus ring then Adjust (Comma/Period) on the focused row;
--                      gamepad: focus then Adjust (L1/R1) with a ten-foot focus
--                      profile. The Adjust binding is DYNAMIC — bound only while
--                      focus sits on this control — so a screen containing a
--                      Stepper never shadows gameplay bumper keys (ADR-0013).
--      hotSwitch     — a Stepper holds NO in-flight state (each press is atomic),
--                      so there is nothing to CARRY or CANCEL on a live class flip.
--
-- OWNERSHIP: `value` is the CALLER's Signal (it must outlive the control), so the
-- Stepper never creates it — it reads and writes it through the shared model.

local chrome_slots = require("../tokens/chrome_slots")
local controlContract = require("./contract")
local contribution = require("../input/contribution")
local themePackage = require("../themes/package")
local value_model = require("./value_model")
local specGuard = require("../spec_guard")

-- THE +/- GLYPHS (ADR-0020 R4). Requested by MEANING and drawn as the
-- framework's ASCII-safe characters. The decrement used to be U+2212, the MINUS
-- SIGN — the same class of hazard as the disclosure caret's geometric triangle,
-- and one the framework has already been bitten by twice (text_input's U+2715
-- clear button rendered as tofu on a live device). A package that ships glyph
-- art paints it OVER these characters; a package that does not leaves them.
local DECREMENT = themePackage.iconGlyph("decrement") or "-"
local INCREMENT = themePackage.iconGlyph("increment") or "+"

local stepper = {}

export type Spec = {
	id: string?,
	label: string?,
	value: any, -- owner-held Signal<number>
	min: number,
	max: number,
	step: number?, -- defaults to 1 (a Stepper is discrete by definition)
	format: ((value: number) -> string)?,
	enabled: any?, -- boolean | Readable<boolean>
	onChange: ((value: number) -> ())?,
}

-- CLOSED SPEC (constitution §4; ARCH-1). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local STEPPER_KEYS = specGuard.keySet({
	"enabled",
	"format",
	"id",
	"label",
	"max",
	"min",
	"onChange",
	"step",
	"value",
})

function stepper.build(LuauUI: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newStepper", spec, STEPPER_KEYS, "spec")
	local UI = LuauUI.UI
	local id = spec.id or "Stepper"
	local scope = core:scope("stepper-" .. tostring(id))
	local value = spec.value
	-- a read-only Memo has kind "memo" and a :set that asserts, so a bare
	-- "settable" duck-type check would pass and then blow up on the first press —
	-- reject it at BUILD, exactly as TextInput does (ARCH-TI-1)
	if type(value) ~= "table" or (value :: any).kind ~= "signal" then
		error(
			`LuauUI newStepper('{id}'): \`value\` must be a SETTABLE Signal<number> the caller owns `
				.. `(the control never creates it, because the value must outlive the control)`,
			0
		)
	end
	local model = value_model.new({
		min = spec.min,
		max = spec.max,
		step = spec.step or 1,
		format = spec.format,
	})

	-- one enabled test, consulted by EVERY input path. `enabled` gates the whole
	-- control, so a disabled Stepper must refuse the Adjust verb too — gating only
	-- the buttons would leave it fully operable by keyboard and gamepad, which is
	-- the same defect B-BTN4 found on Button.
	-- the contract's one reading of `enabled` (a one-shot read: never subscribes)
	local function isEnabled(): boolean
		return controlContract.enabledNow(spec.enabled)
	end

	-- the ONE mutation site: every input class routes here.
	local function apply(next_: number)
		if not isEnabled() then
			return false
		end
		local resolved = model.quantize(next_)
		if resolved == value:get() then
			return false
		end
		value:set(resolved)
		if spec.onChange ~= nil then
			spec.onChange(resolved)
		end
		return true
	end

	local function adjust(direction: number): boolean
		return apply(model.stepped(value:get(), direction))
	end

	local readout = scope:own(core:memo(function(use)
		return model.format(use(value))
	end))
	-- semantic value text (B-VAL1): the value IN ITS RANGE, so a ten-foot readout
	-- or an assistive layer never gets a bare number with no context
	local semantic = scope:own(core:memo(function(use)
		return model.semanticText(use(value))
	end))

	local decEnabled = scope:own(core:memo(function(use)
		if not controlContract.enabledIn(use, spec.enabled) then
			return false
		end
		return not model.atMin(use(value))
	end))
	local incEnabled = scope:own(core:memo(function(use)
		if not controlContract.enabledIn(use, spec.enabled) then
			return false
		end
		return not model.atMax(use(value))
	end))

	local root = UI.HStack({
		id = id,
		gap = "s",
		align = "center",
		children = {
			UI.Text({ id = "Label", text = spec.label or "", textSize = "body" }),
			UI.Spacer({}),
			-- the two buttons carry `enabled` from the bounds, so at a bound the
			-- affordance is disabled rather than silently doing nothing (B-VAL3)
			-- SQUARE targets (director review 2026-07-24): the floor was on height
			-- only, so a "-"/"+" sized itself 36 wide against a 44 tall box and read
			-- as an oddly tall sliver. A touch target is a target on both axes.
			-- THE GLYPH PLATE (ADR-0020 R3). A +/- affordance is a Button, so every
			-- package skins it through the `control` recipe today; a package that
			-- wants a carved stepper plate instead declares `stepperPlate`, and
			-- `chrome_slots.resolveSlot` falls this hint back to `control` for every
			-- package that does not — a v2 slot must never UN-skin a v1 theme.
			--
			-- ...and the GLYPH is a SEMANTIC ICON REQUEST (ADR-0020 R4, landed in
			-- P4 on the seam P3 named). The button's own text is the framework's
			-- ASCII character, so the affordance is legible under every theme; the
			-- `icon` name beside it lets a package that ships +/- art have the
			-- adapter paint the picture over it. A control never names an asset.
			chrome_slots.attachHint(
				UI.Button({
					id = "Dec",
					label = DECREMENT,
					enabled = decEnabled,
					width = { type = "minMax", min = "targetSizes.minimum" },
					height = { type = "minMax", min = "targetSizes.minimum" },
				}),
				{ slot = "stepperPlate", icon = "decrement" }
			),
			-- The readout is CENTRED and holds a STABLE width. Content-width left-
			-- aligned text put the glyphs 1px off the gap's centre, and worse, the
			-- box grew with the number — stepping 9 -> 10 shoved the "+" button
			-- sideways under the player's finger (director review 2026-07-24).
			UI.Text({
				id = "Value",
				text = readout,
				textSize = "body",
				textAlign = "center",
				width = { type = "minMax", min = "controls.stepper.valueMinWidth" },
			}),
			chrome_slots.attachHint(
				UI.Button({
					id = "Inc",
					label = INCREMENT,
					enabled = incEnabled,
					width = { type = "minMax", min = "targetSizes.minimum" },
					height = { type = "minMax", min = "targetSizes.minimum" },
				}),
				{ slot = "stepperPlate", icon = "increment" }
			),
		},
	})

	local rootPath: string? = nil

	local built = contribution.attach(root, {
		-- ONE activation site per button. The inner Buttons carry NO onActivate:
		-- the presenter dispatches to the node's own handler FIRST and then to the
		-- longest-prefix contribution, so declaring both would double-fire.
		handleActivate = function(path: string): boolean
			if string.sub(path, -4) == "/Dec" then
				adjust(-1)
				return true
			elseif string.sub(path, -4) == "/Inc" then
				adjust(1)
				return true
			end
			return false
		end,
		-- focus-gated Adjust (ADR-0013): the whole row is an adjust target, so
		-- keyboard Comma/Period and gamepad L1/R1 reach the same arithmetic while
		-- focus is anywhere inside this control — and are UNBOUND otherwise.
		-- `rootNode` is THIS CONTROL's mounted root, so "every Button below here"
		-- means the two stepper buttons. It used to be handed the screen root,
		-- which made the same sentence mean every button on the screen (found
		-- live 2026-08-02; the presenter now passes the contribution's own node).
		adjustTargets = function(rootNode: any): { [string]: boolean }
			local out: { [string]: boolean } = {}
			rootPath = rootNode.path
			local function walk(node: any)
				if node.class == "Button" then
					out[node.path] = true
				end
				for _, child in node.children or {} do
					walk(child)
				end
			end
			walk(rootNode)
			return out
		end,
		-- NO `adjustAxis` (director playtest 2026-08-03). A stepper's two buttons
		-- are ordinary focus stops and ACTIVATING one is the whole interaction —
		-- focus Dec, press Space, the value goes down. Claiming Left/Right here
		-- would take the arrows away from navigating between the two buttons to do
		-- the same job twice, and on a screen with an avatar underneath it would
		-- take them from the camera for nothing. Comma/Period and L1/R1 stay bound
		-- while focus is inside the control, which is the gamepad/keyboard shortcut
		-- for the same arithmetic without the contention.
		handleAdjust = function(_path: string, direction: number): boolean
			return adjust(direction)
		end,
	})

	local api = {}
	api.blueprint = built
	api.model = model
	api.semanticText = semantic

	function api.dump()
		local v = value:get()
		return {
			schema = "luauui-stepper-dump/1",
			id = id,
			value = v,
			formatted = model.format(v),
			semanticText = model.semanticText(v),
			min = model.min,
			max = model.max,
			step = model.step,
			atMin = model.atMin(v),
			atMax = model.atMax(v),
			rootPath = rootPath,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api
end

return stepper
