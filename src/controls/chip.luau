--!strict
-- Chip: a small toggleable tag/filter pill. Renders as ONE shipped primitive —
-- a rounded UI.Button whose `selected` surface reflects the owner-held
-- `selected` signal. Activate (pointer tap / click / keyboard Return / gamepad
-- ButtonA) flips `selected` and calls the optional `onToggle`.
--
-- THREE AXES (affordance matrix §A; UI-PARADIGM-001..003):
--   1. UI (layout)   — a single pill; the Button primitive sizes to its label
--                      and honours the ten-foot text/focus scaling for free.
--   2. INPUT (reach) — every input class reaches the same Activate verb: the
--                      presenter auto-dispatches a focus+Activate (Return/ButtonA)
--                      and a pointer/touch tap to the root contribution's
--                      handleActivate, which is the ONE flip site.
--   3. PARADIGM      — pointer: the free hover preview layer the renderer wires
--                      onto interactive Buttons when the pointer class is live;
--                      touch: the Button's 44px minHitSize floor; keyboard:
--                      focus ring + Navigate→Activate; gamepad: focus + A with a
--                      strengthened ten-foot focus profile at a Large display.
--
-- OWNERSHIP: `selected` is the CALLER's data model (it must outlive the control),
-- so the chip never creates it — it only reads and flips it. The control scope
-- owns nothing persistent here; dispose() = scope:dispose() and nothing else.

local contribution = require("../input/contribution")
local specGuard = require("../spec_guard")

local chip = {}

-- CLOSED SPEC (constitution §4; ARCH-1). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local CHIP_KEYS = specGuard.keySet({
	"id",
	"label",
	"onToggle",
	"selected",
})

function chip.build(Facet: any, core: any, spec: any)
	specGuard.assertKnownKeys("newChip", spec, CHIP_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Chip"
	local scope = core:scope("chip-" .. tostring(id))
	local selected = spec.selected -- owner-held Signal<boolean>
	-- AUTHORING IS STRICT: fail at BUILD, not at first render (ADR-0010,
	-- docs/extending/new-control.md §2). `selected` is required AND is the
	-- control's single mutation site, so a missing one used to surface as
	-- "attempt to index nil" on the user's first tap and a read-only Memo as
	-- "cannot set a memo" from deep inside core — both unattributable. Same
	-- check, same wording, as Stepper/Slider/Rating/Picker/DisclosureGroup/
	-- TextInput (CTRL-03).
	if type(selected) ~= "table" or (selected :: any).kind ~= "signal" then
		error(
			`Facet newChip('{id}'): \`selected\` must be a SETTABLE Signal<boolean> the caller owns `
				.. `(the control never creates it, because the selection must outlive the control)`,
			0
		)
	end
	local label = spec.label or ""

	-- the SINGLE Activate site: every input class routes here through the
	-- presenter's auto dispatch (never a direct callback in a consumer).
	local function toggle()
		local nextValue = not selected:get()
		selected:set(nextValue)
		if spec.onToggle ~= nil then
			spec.onToggle(nextValue)
		end
	end

	-- the pill: a focusable Button (44px hit floor, hover layer, focus ring all
	-- come from the primitive) whose `selected` BINDING_PROP reflects the signal
	-- with NO factory rerun. UI.corners gives the rounded ("pill") surface.
	local blueprint = UI.corners(
		UI.Button({
			id = id,
			label = label,
			selected = selected,
			-- honour the Button contract's minHitSize as a real layout floor (a chip
			-- is a touch target first) — the touch structural idiom. The FLOOR is a
			-- theme metric, so a theme with roomier targets grows the chip with it.
			height = { type = "minMax", min = "targetSizes.minimum" },
		}),
		"pill"
	)

	-- FOUR-INPUT STORY (ui_todo §0; ADR-0013): the presenter discovers this
	-- bundle on mount and composes the whole story with zero consumer opts. A
	-- chip owns NO in-flight state (no drag/grab/open edit), so only
	-- handleActivate is needed — Navigate/focus/geometry the presenter derives
	-- from the single focusable Button automatically.
	blueprint = contribution.attach(blueprint, {
		handleActivate = function(_path: string, _meta: any?): boolean
			toggle()
			return true
		end,
	})

	-- deterministic diagnostic summary (§10.2): the state a bug report needs.
	local function dump()
		return {
			schema = "facet-chip-dump/1",
			id = id,
			label = label,
			selected = selected:get(),
		}
	end

	return {
		blueprint = blueprint,
		dump = dump,
		dispose = function()
			scope:dispose()
		end,
	}
end

return chip
