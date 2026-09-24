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
local rowKeys = require("./row_actions")
local chip = {}

-- the live paths of removable tags, which removal hands the ring between
local REMOVABLE: { [string]: boolean } = {}

-- CLOSED SPEC (constitution §4). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local CHIP_KEYS = specGuard.keySet({
	"animation",
	"enabled",
	"id",
	"label",
	"onToggle",
	"onRemove",
	"editing",
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

	--[[ REMOVAL IS EDIT MODE. A tag selects; while the
		caller's `editing` holds true it shows a trailing close mark INSIDE its one
		plate, and activating it anywhere — or Delete/Backspace while it holds the
		ring — removes it. The mark is not a second stop or target. A remove-only
		token (no `selected`) is always editing. After a removal the ring goes to
		the next removable tag, then the previous one, then the caller's fallback. ]]
	local editingSource = spec.editing
	assert(editingSource == nil or removable, "UI.Chip.editing requires onRemove")
	if removable and selected ~= nil and editingSource == nil then
		error(
			`Facet UI.Chip('{id}'): a selectable chip with \`onRemove\` removes in edit mode; `
				.. `supply \`editing\` (a readable boolean the caller owns)`,
			0
		)
	end
	local function editingNow(use: any?): boolean
		return removable and (editingSource == nil or read(editingSource, use) == true)
	end
	local removeLabel = spec.removeLabel or `Remove {label}`
	local owner = Compose.currentOwner()
	local chipPath = Compose.cell(nil :: string?)
	local focusGraph: any = nil
	local actionSystem: any = nil
	local keys: any = nil
	local pendingFocus: any = nil
	local function releaseFocus()
		local target = pendingFocus
		pendingFocus = nil
		local path = chipPath:peek()
		REMOVABLE[path or ""] = nil
		-- A caller may retain a rejected/delayed request. Disposal must not
		-- reclaim focus after the player has moved to another command.
		if target ~= nil and focusGraph ~= nil and path ~= nil and focusGraph.focused:peek() == path then
			focusGraph.remove(path)
			focusGraph.focusOn(target)
		end
	end

	local function nextRemoveStop(): string?
		local path = chipPath:peek()
		local map = if focusGraph ~= nil then focusGraph.focusMap() else nil
		local traversal = if type(map) == "table" then map.traversal else nil
		if path == nil or type(traversal) ~= "table" then
			return nil
		end
		local mine: number? = nil
		for index, entry in traversal do
			if (entry.path or entry.id) == path then
				mine = index
				break
			end
		end
		if mine == nil then
			return nil
		end
		local function removableAt(index: number): string?
			local entry = traversal[index]
			local found = if entry == nil then nil else (entry.path or entry.id)
			return if type(found) == "string" and found ~= path and REMOVABLE[found] then found else nil
		end
		for index = mine + 1, #traversal do
			local found = removableAt(index)
			if found ~= nil then
				return found
			end
		end
		for index = mine - 1, 1, -1 do
			local found = removableAt(index)
			if found ~= nil then
				return found
			end
		end
		return nil
	end

	local function remove()
		if disposed or not controlContract.enabledNow(spec.enabled) or not editingNow() then
			return
		end
		pendingFocus = nextRemoveStop() or selection.read(spec.removeFocusFallback);
		(spec.onRemove :: any)()
	end

	-- Delete/Backspace — the row engine's own keys — only while THIS tag is
	-- editing and holds the ring, so nothing else on the screen loses them
	local watching = false
	local function watchKeys()
		if watching or owner == nil or focusGraph == nil or actionSystem == nil or not removable then
			return
		end
		watching = true
		owner.watch(function(use)
			local path = use(chipPath)
			local on = path ~= nil and use(focusGraph.focused) == path and editingNow(use)
			if on and keys == nil then
				keys = actionSystem.createContext({
					name = `ChipKeys-{id}`,
					priority = rowKeys.ROW_KEY_PRIORITY,
					sink = true,
				})
				local delete = keys.createAction("ChipRemove", "Bool")
				for _, binding in rowKeys.ROW_KEYS.delete do
					delete.bind(binding)
				end
				delete.onPressed(remove)
				owner.own(function()
					keys.destroy()
				end)
			end
			if keys ~= nil then
				keys.setEnabled(on)
			end
		end)
	end

	-- the pill: a focusable Button (44px hit floor, hover layer, focus ring all
	-- come from the primitive) whose `selected` BINDING_PROP reflects the signal
	-- with NO factory rerun. UI.corners gives the rounded ("pill") surface.
	--[[ THE ACCESSORIES ARE ONE ROW INSIDE THE ONE ACTIVATION SURFACE. Present only
		when asked for: with neither, the chip stays exactly the label-only Button it
		has always been (the leaf draws the label itself, and a wrapper would change
		both the mounted paths and the measured box for every chip that shipped). ]]
	local chromeSlots = require("../tokens/chrome_slots")
	local accessories = spec.leading ~= nil or spec.trailing ~= nil or removable
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
		if removable then
			-- the close mark, inside this one plate and never its own target
			table.insert(
				row,
				UI.When({
					id = "RemoveWhen",
					condition = Compose.formula(function(use)
						return editingNow(use)
					end),
					thenView = function()
						return chromeSlots.attachHint(
							UI.Text({ id = "Remove", text = themePackage.iconGlyph("close"), textSize = "control" }),
							{ icon = "close", iconSize = "small" }
						)
					end,
				})
			)
		end
		children = { UI.HStack({ id = "Content", gap = "s", align = "center", children = row }) }
	end
	local appearance = vocabulary.deriveAppearance("UI.Chip", spec.appearance, APPEARANCES, APPEARANCE_SET)
	-- honour the Button contract's minHitSize as a real layout floor (a chip
	-- is a touch target first) — the touch structural idiom. The FLOOR is a
	-- theme metric, so a theme with roomier targets grows the chip with it.
	local plateHeight = sizedHeight or { type = "minMax", min = "targetSizes.minimum" }
	local radius = vocabulary.cornerRadiusFor(spec.corners or "pill")
	local blueprint = UI.corners(
		chromeSlots.attachHint(
			UI.Button({
				id = id,
				label = if editingSource ~= nil
					then Compose.formula(function(use)
						return if editingNow(use) then removeLabel else label
					end)
					elseif removable and selected == nil then removeLabel
					else label,
				selected = selected,
				enabled = spec.enabled,
				children = children,
				animation = spec.animation,
				controlSize = spec.controlSize,
				appearance = appearance,
				padding = sizedPadding,
				height = plateHeight,
			}),
			{ selectionMark = true }
		),
		radius
	)

	blueprint = contribution.attach(blueprint, {
		handleActivate = function(_path: string, _meta: any?): boolean
			if editingNow() then
				remove()
			else
				toggle()
			end
			return true
		end,

		bindFocusGraph = function(graph: any)
			focusGraph = graph
			watchKeys()
		end,

		bindActionSystem = function(system: any)
			actionSystem = system
			watchKeys()
		end,

		syncGeometry = function(_rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil and removable and chipPath:peek() == nil then
				REMOVABLE[rootNode.path] = true
				chipPath:set(rootNode.path)
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
			editing = editingNow(),
			removeLabel = if removable then removeLabel else nil,
			enabled = controlContract.enabledNow(spec.enabled),
			controlSize = selection.read(spec.controlSize),
			appearance = selection.read(spec.appearance),
		}
	end

	return {
		blueprint = vocabulary.reserveTarget(UI, core, id, blueprint, nil),
		dump = dump,
		dispose = function()
			disposed = true
			releaseFocus()
		end,
	}
end

return chip
