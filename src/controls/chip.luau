--!strict
local Compose = require("../vendor/compose/core")
local read = require("../selection_model").read
-- A filter pill borrows selection state and routes activation through Facet input.
-- Removal transfers focus when the owning keyed row is disposed.

local contribution = require("../input/contribution")
local specGuard = require("../spec_guard")
local selection = require("../selection_model")
local vocabulary = require("./control_vocabulary")
local themePackage = require("../themes/package")

local controlContract = require("../class_contract")
local chip = {}

-- CLOSED SPEC (constitution §4). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local CHIP_KEYS = specGuard.keySet({
	"animation",
	"enabled",
	"id",
	"label",
	"onToggle",
	"onRemove",
	"removeLabel",
	"removeFocusFallback",
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
	local removable = spec.onRemove ~= nil
	assert(not removable or type(spec.onRemove) == "function", "UI.Chip.onRemove must be a function")
	assert(
		removable or (spec.removeLabel == nil and spec.removeFocusFallback == nil),
		"UI.Chip remove options require onRemove"
	)
	local selected = spec.selected -- the caller's writable cell of a boolean
	-- AUTHORING IS STRICT: fail at BUILD, not at first render (docs/extending/new-control.md §2). `selected` is required AND is the
	-- control's single mutation site, so a missing one used to surface as
	-- "attempt to index nil" on the user's first tap and a read-only Memo as
	-- "cannot set a memo" from deep inside core — both unattributable. Same
	-- check, same wording, as Stepper/Slider/Rating/Picker/DisclosureGroup/
	-- TextInput.
	if removable and selected == nil then
		assert(spec.onToggle == nil, "UI.Chip.onToggle requires selected; a remove-only token body is inert")
	elseif not selection.isWritable(selected) then
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
	local sizedHeight = vocabulary.deriveSize("UI.Chip", spec.controlSize, vocabulary.heightFor)
	local sizedPadding = vocabulary.deriveSize("UI.Chip", spec.controlSize, vocabulary.paddingFor)

	-- the SINGLE Activate site: every input class routes here through the
	-- presenter's auto dispatch (never a direct callback in a consumer).
	local function toggle()
		if disposed or not controlContract.enabledNow(spec.enabled) or selected == nil then
			return
		end
		local nextValue = not read(selected)
		selected:set(nextValue)
		if spec.onToggle ~= nil then
			spec.onToggle(nextValue)
		end
	end

	local REMOVE_ID = "Remove"
	local focusGraph: any = nil
	local removePath: string? = nil
	local pendingFocus: any = nil
	local function releaseFocus()
		local target = pendingFocus
		pendingFocus = nil
		-- A caller may retain a rejected/delayed request. Disposal must not
		-- reclaim focus after the player has moved to another command.
		if target ~= nil and focusGraph ~= nil and focusGraph.focused:peek() == removePath then
			if removePath ~= nil then
				focusGraph.remove(removePath)
			end
			focusGraph.focusOn(target)
		end
	end

	local function nextRemoveStop(): string?
		if focusGraph == nil or removePath == nil then
			return nil
		end
		local map = focusGraph.focusMap()
		local traversal = if type(map) == "table" then map.traversal else nil
		if type(traversal) ~= "table" then
			return nil
		end
		local suffix = "/" .. REMOVE_ID
		local mine: number? = nil
		for index, entry in traversal do
			if entry.path == removePath or entry.id == removePath then
				mine = index
				break
			end
		end
		if mine == nil then
			return nil
		end
		local function pathAt(index: number): string?
			local entry = traversal[index]
			local path = if entry == nil then nil else (entry.path or entry.id)
			if type(path) == "string" and path ~= removePath and string.sub(path, -#suffix) == suffix then
				return path
			end
			return nil
		end
		for index = mine + 1, #traversal do
			local found = pathAt(index)
			if found ~= nil then
				return found
			end
		end
		for index = mine - 1, 1, -1 do
			local found = pathAt(index)
			if found ~= nil then
				return found
			end
		end
		return nil
	end

	local function remove()
		if disposed or not controlContract.enabledNow(spec.enabled) or not removable then
			return
		end

		pendingFocus = nextRemoveStop() or selection.read(spec.removeFocusFallback);
		(spec.onRemove :: any)()
	end

	-- the pill: a focusable Button (44px hit floor, hover layer, focus ring all
	-- come from the primitive) whose `selected` BINDING_PROP reflects the signal
	-- with NO factory rerun. UI.corners gives the rounded ("pill") surface.
	--[[ THE ACCESSORIES ARE ONE ROW INSIDE THE ONE ACTIVATION SURFACE. Present only
		when asked for: with neither, the chip stays exactly the label-only Button it
		has always been (the leaf draws the label itself, and a wrapper would change
		both the mounted paths and the measured box for every chip that shipped). ]]
	local chromeSlots = require("../tokens/chrome_slots")
	local accessories = spec.leading ~= nil or spec.trailing ~= nil
	local children: { any }? = nil
	if accessories then
		local row = {}
		if spec.leading ~= nil then
			table.insert(row, spec.leading)
		end
		table.insert(
			row,
			chromeSlots.attachHint(
				UI.Text({ id = "Label", text = label, textSize = "control" }),
				{ contentOwnerDepth = 2 }
			)
		)
		if spec.trailing ~= nil then
			table.insert(row, spec.trailing)
		end
		children = { UI.HStack({ id = "Content", gap = "s", align = "center", children = row }) }
	end
	local appearance = vocabulary.deriveAppearance("UI.Chip", spec.appearance, APPEARANCES, APPEARANCE_SET)
	-- honour the Button contract's minHitSize as a real layout floor (a chip
	-- is a touch target first) — the touch structural idiom. The FLOOR is a
	-- theme metric, so a theme with roomier targets grows the chip with it.
	local plateHeight = sizedHeight or { type = "minMax", min = "targetSizes.minimum" }
	local radius = vocabulary.cornerRadiusFor(spec.corners or "pill")
	--[[ A REMOVABLE CHIP IS ONE PILL OF TWO TARGETS (owner report 2026-09-22): the
		body and a trailing close segment, each at least the hit floor wide, joined
		with complementary corners so the pair reads as one pill (the input-chip /
		token-field pattern) while their targets stay disjoint. The body gives its
		trailing inset to the segment, which centres the glyph in its own floor. ]]
	local floor = if removable then vocabulary.hitFloor(core, id) else nil
	-- the rung's (or the button's) vertical inset on both plates, so they stand
	-- the same height; horizontal inset only where the plate needs it
	local function inset(keepLeft: boolean): any
		local function sides(rungSides: any): any
			local pad = "controls.button.padding"
			local p = rungSides or { left = pad, right = pad, top = pad, bottom = pad }
			return { left = if keepLeft then p.left else 0, right = 0, top = p.top, bottom = p.bottom }
		end
		return if spec.controlSize == nil
			then sides(nil)
			else vocabulary.deriveSize("UI.Chip", spec.controlSize, function(rung)
				return sides(vocabulary.paddingFor(rung))
			end)
	end
	local bodyPadding = if removable then inset(true) else sizedPadding
	local blueprint = UI.corners(
		UI.Button({
			id = id,
			label = label,
			selected = selected,
			focusable = if removable and selected == nil then false else nil,
			enabled = spec.enabled,
			children = children,
			animation = spec.animation,
			controlSize = spec.controlSize,
			appearance = appearance,
			padding = bodyPadding,
			width = floor,
			height = plateHeight,
		}),
		if removable and radius ~= 0 then { topLeft = radius, bottomLeft = radius } else radius
	)

	if removable then
		local removeButton = UI.corners(
			UI.Button({
				id = REMOVE_ID,
				label = spec.removeLabel or `Remove {label}`,
				-- the glyph is the content, so the label is the accessible name only
				children = {
					UI.Spacer({ id = "BeforeMark" }),
					chromeSlots.attachHint(
						UI.Text({
							id = "Mark",
							text = themePackage.iconGlyph("close"),
							textSize = "control",
							textAlign = "center",
						}),
						-- the small art square, so the segment stands no taller than the body
						{ icon = "close", iconSize = "small", contentOwnerDepth = 1 }
					),
					UI.Spacer({ id = "AfterMark" }),
				},
				selected = selected,
				enabled = spec.enabled,
				appearance = appearance,
				padding = inset(false),
				width = floor,
				height = plateHeight,
			}),
			if radius ~= 0 then { topRight = radius, bottomRight = radius } else radius
		)

		blueprint = UI.HStack({
			id = `{id}+token`,
			gap = 0,
			align = "center",
			children = { vocabulary.reserveTarget(UI, core, id, blueprint, nil), removeButton },
		})
	end

	blueprint = contribution.attach(blueprint, {
		handleActivate = function(path: string, _meta: any?): boolean
			local isRemove = if removePath ~= nil
				then path == removePath
				else string.sub(path, -#REMOVE_ID - 1) == "/" .. REMOVE_ID
			if removable and isRemove then
				removePath = path
				remove()
				return true
			end
			toggle()
			return true
		end,

		bindFocusGraph = function(graph: any)
			focusGraph = graph
		end,

		syncGeometry = function(_rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil and removePath == nil and removable then
				for _, child in rootNode.children or {} do
					if child.id == REMOVE_ID then
						removePath = child.path
					end
				end
			end
		end,
	})

	-- deterministic diagnostic summary (§10.2): the state a bug report needs.
	local function dump()
		return {
			schema = "facet-chip-dump/1",
			id = id,
			label = label,
			selected = if selected ~= nil then read(selected) else nil,
			removable = removable,
			removeLabel = if removable then (spec.removeLabel or `Remove {label}`) else nil,
			enabled = controlContract.enabledNow(spec.enabled),
			controlSize = selection.read(spec.controlSize),
			appearance = selection.read(spec.appearance),
		}
	end

	local mounted = if not removable then vocabulary.reserveTarget(UI, core, id, blueprint, nil) else blueprint
	return {
		blueprint = mounted,
		dump = dump,
		dispose = function()
			disposed = true
			releaseFocus()
		end,
	}
end

return chip
