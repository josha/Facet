--!strict
local Compose = require("../vendor/compose/core")
local read = require("../selection_model").read
-- A filter pill borrows selection state and routes activation through Facet input.
-- It owns no reactive resources; disposal only disables its callback.

local contribution = require("../input/contribution")
local specGuard = require("../spec_guard")
local selection = require("../selection_model")
local vocabulary = require("./control_vocabulary")

local controlContract = require("../class_contract")
local chip = {}

-- CLOSED SPEC (constitution §4). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local CHIP_KEYS = specGuard.keySet({
	"enabled",
	"id",
	"label",
	"onToggle",
	"selected",
	"controlSize",
	"appearance",
	"corners",
	"leading",
	"trailing",
})

local APPEARANCES = { "standard", "utility" }
local APPEARANCE_SET = specGuard.keySet(APPEARANCES)

function chip.build(Facet: any, core: any, spec: any)
	specGuard.assertKnownKeys("UI.Chip", spec, CHIP_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Chip"
	local selected = spec.selected -- the caller's writable cell of a boolean
	-- AUTHORING IS STRICT: fail at BUILD, not at first render (docs/extending/new-control.md §2). `selected` is required AND is the
	-- control's single mutation site, so a missing one used to surface as
	-- "attempt to index nil" on the user's first tap and a read-only Memo as
	-- "cannot set a memo" from deep inside core — both unattributable. Same
	-- check, same wording, as Stepper/Slider/Rating/Picker/DisclosureGroup/
	-- TextInput.
	if not (Compose.isReadable(selected) and type(selected.set) == "function") then
		error(
			`Facet UI.Chip('{id}'): \`selected\` must be a writable Compose cell holding a boolean, owned by the caller `
				.. `(the control never creates it, because the selection must outlive the control)`,
			0
		)
	end
	local disposed = false
	local label = spec.label or ""
	--[[ THE SHARED LOCAL VOCABULARY (`control_vocabulary.luau`), validated before
		anything is built so a misspelled word names itself rather than painting the
		default forever. ]]
	vocabulary.assertSize("UI.Chip", spec.controlSize)
	vocabulary.assertAppearance("UI.Chip", spec.appearance, APPEARANCES, APPEARANCE_SET)
	vocabulary.assertCorners("UI.Chip", spec.corners)
	-- the rung's METRICS as names, so the solver re-resolves them on a theme swap
	-- (see the vocabulary module's header). Absent = the 44px floor this control
	-- has always declared.
	local sizedHeight = vocabulary.derive(spec.controlSize, vocabulary.heightFor)
	local sizedPadding = vocabulary.derive(spec.controlSize, vocabulary.paddingFor)

	-- the SINGLE Activate site: every input class routes here through the
	-- presenter's auto dispatch (never a direct callback in a consumer).
	local function toggle()
		if disposed or not controlContract.enabledNow(spec.enabled) then
			return
		end
		local nextValue = not read(selected)
		selected:set(nextValue)
		if spec.onToggle ~= nil then
			spec.onToggle(nextValue)
		end
	end

	-- the pill: a focusable Button (44px hit floor, hover layer, focus ring all
	-- come from the primitive) whose `selected` BINDING_PROP reflects the signal
	-- with NO factory rerun. UI.corners gives the rounded ("pill") surface.
	--[[ THE ACCESSORIES ARE ONE ROW INSIDE THE ONE ACTIVATION SURFACE. Present only
		when asked for: with neither, the chip stays exactly the label-only Button it
		has always been (the leaf draws the label itself, and a wrapper would change
		both the mounted paths and the measured box for every chip that shipped). ]]
	local accessories = spec.leading ~= nil or spec.trailing ~= nil
	local children: { any }? = nil
	if accessories then
		local row = {}
		if spec.leading ~= nil then
			table.insert(row, spec.leading)
		end
		table.insert(row, UI.Text({ id = "Label", text = label, textSize = "control" }))
		if spec.trailing ~= nil then
			table.insert(row, spec.trailing)
		end
		children = { UI.HStack({ id = "Content", gap = "s", align = "center", children = row }) }
	end
	local blueprint = UI.corners(
		UI.Button({
			id = id,
			label = label,
			selected = selected,
			enabled = spec.enabled,
			children = children,
			controlSize = spec.controlSize,
			appearance = spec.appearance,
			padding = sizedPadding,
			-- honour the Button contract's minHitSize as a real layout floor (a chip
			-- is a touch target first) — the touch structural idiom. The FLOOR is a
			-- theme metric, so a theme with roomier targets grows the chip with it.
			height = sizedHeight or { type = "minMax", min = "targetSizes.minimum" },
		}),
		vocabulary.cornerRadiusFor(spec.corners or "pill")
	)

	-- FOUR-INPUT STORY (ui_todo §0): the presenter discovers this
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
			selected = read(selected),
			enabled = controlContract.enabledNow(spec.enabled),
			controlSize = selection.read(spec.controlSize),
			appearance = selection.read(spec.appearance),
		}
	end

	local mounted = if spec.controlSize ~= nil
		then vocabulary.reserveTarget(UI, core, id, blueprint, nil)
		else blueprint
	return {
		blueprint = mounted,
		dump = dump,
		dispose = function()
			disposed = true
		end,
	}
end

return chip
