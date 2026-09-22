--!strict
--[[ THE CHROME EVERY FIELD-SHAPED CONTROL WEARS, decided once: a label above, a
	required notation in it, accessories inside the plate, and ONE line beneath
	that is either the caller's hint or the error. INTERNAL: there is no public
	`Field` wrapper, because nothing outside `src/controls/` composes a field from
	parts.

	  label         the words above the field. Tapping them focuses the field.
	  requiredMark  "required" | "optional" — NOTATION ONLY. It never validates.
	  hint          the caller's sentence under the field, at rest.
	  errorText     the caller's sentence when something is wrong. Non-empty
	                REPLACES the hint, paints the danger role beside the status
	                mark and shakes nothing (`invalid` stays the shake trigger).
	  leading       a static blueprint inside the plate, before the editor.
	  trailing      a blueprint inside the plate, after the clear affordance.
	  controlSize   the shared local rung (`control_vocabulary`).
	  appearance    "standard" | "contrast" | "utility" — the plate's emphasis.
	  corners       the shared silhouette word.

	THE LABEL IS A TAP TARGET AND NOT A FOCUS STOP, and it reserves the touch
	floor in its own footprint: an expander grown behind a short label row would
	reach down into the field's own target. The words sit at the BOTTOM of that
	box, against the field.

	THE MESSAGE IS ONE NODE. Hint and error are the same line in the same place,
	so the field never moves when it goes wrong. ]]

local Compose = require("../vendor/compose/core")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local chromeSlots = require("../tokens/chrome_slots")
local themePackage = require("../themes/package")
local vocabulary = require("./control_vocabulary")

local field_chrome = {}

field_chrome.KEYS = table.freeze({
	"label",
	"requiredMark",
	"hint",
	"errorText",
	"leading",
	"trailing",
	"controlSize",
	"appearance",
	"corners",
})

--[[ THE FIELD FAMILY'S EMPHASIS WORDS, each painted through a surface every
	shipped package already paints: standard is the chip plate every field has
	always drawn, contrast the pressable control plate, utility no plate at all. ]]
field_chrome.APPEARANCES = table.freeze({ "standard", "contrast", "utility" })
local APPEARANCE_SET = guard.keySet(field_chrome.APPEARANCES)
local APPEARANCE_SURFACE: { [string]: string } = { standard = "chip", contrast = "control", utility = "plain" }

--[[ `optional` paints NOTHING on purpose: its notation is a WORD, Facet has no
	localization table, and an untranslated word beside a translated label is the
	defect the localization rule exists to stop. The caller's own `hint` carries
	it. `required` is one suffix IN the label string, so it wraps with the words
	and can never be cut or stranded on its own. ]]
field_chrome.MARKS = table.freeze({ "required", "optional" })
local MARK_SET = guard.keySet(field_chrome.MARKS)
local REQUIRED_SUFFIX = " *"

-- an error is never colour alone: the line carries the framework's status mark,
-- a NAME so a package paints its own art over the glyph
local ERROR_ICON = "status.error"
-- the mark's width is a FLOOR at the picture it asks for; its height hugs the
-- caption line, so the picture is exactly as tall as the words beside it
local MARK_WIDTH = table.freeze({ type = "minMax", min = "iconSizes.small" })

local function assertBlueprint(control: string, key: string, value: any)
	if value ~= nil and (type(value) ~= "table" or type((value :: any).class) ~= "string") then
		error(`Facet {control}: \`{key}\` must be a blueprint (got {typeof(value)})`, 0)
	end
end

-- every chrome key is checked before the control builds anything
function field_chrome.assertSpec(control: string, spec: any)
	local mark = spec.requiredMark
	if mark ~= nil and (type(mark) ~= "string" or not MARK_SET[mark]) then
		error(
			`Facet {control}: \`requiredMark\` must be {table.concat(field_chrome.MARKS, " | ")} `
				.. `(got {typeof(mark)} '{tostring(mark)}'). It is notation: it never validates.`,
			0
		)
	end
	for _, key in { "label", "hint", "errorText" } do
		local value = selection.read(spec[key])
		if value ~= nil and type(value) ~= "string" then
			error(`Facet {control}: \`{key}\` must be a string or a readable one (got {typeof(value)})`, 0)
		end
	end
	assertBlueprint(control, "leading", spec.leading)
	assertBlueprint(control, "trailing", spec.trailing)
	vocabulary.assertSize(control, spec.controlSize)
	vocabulary.assertAppearance(control, spec.appearance, field_chrome.APPEARANCES, APPEARANCE_SET)
	vocabulary.assertCorners(control, spec.corners)
end

--[[ new(opts) -> the chrome for one control. `opts`: UI, control (the name used
	in refusals), spec (read, never kept beyond the control) and internalMessage
	(a readable string the CONTROL owns — the numeric presentation's rejection
	line; the caller's `errorText` outranks it). Formulas are created under the
	control's active owner and die with it. ]]
function field_chrome.new(opts: any): any
	local UI, spec, control = opts.UI, opts.spec, opts.control
	local internal = opts.internalMessage
	local chrome: any = {}
	chrome.leading = spec.leading
	chrome.trailing = spec.trailing
	-- a bound word repaints the plate in place and is refused at the write when it
	-- leaves this family, keeping the last legal paint
	chrome.surface = vocabulary.derive(spec.appearance, function(word)
		vocabulary.assertAppearance(control, word, field_chrome.APPEARANCES, APPEARANCE_SET)
		return if type(word) == "string" then APPEARANCE_SURFACE[word] else "chip"
	end) or "chip"
	chrome.height = vocabulary.deriveSize(control, spec.controlSize, vocabulary.heightFor)
	chrome.padding = vocabulary.deriveSize(control, spec.controlSize, vocabulary.paddingFor)

	-- one line, three sources, one order: the caller's error, the control's own
	-- rejection, then the hint
	chrome.errorMessage = Compose.formula(function(use)
		local authored = selection.read(spec.errorText, use)
		if type(authored) == "string" and authored ~= "" then
			return authored
		end
		local own = if internal ~= nil then use(internal) else nil
		return if type(own) == "string" then own else ""
	end)
	chrome.hasError = Compose.formula(function(use)
		return use(chrome.errorMessage) ~= ""
	end)
	local message = Compose.formula(function(use)
		local failure = use(chrome.errorMessage)
		if failure ~= "" then
			return failure
		end
		local hint = selection.read(spec.hint, use)
		return if type(hint) == "string" then hint else ""
	end)

	-- a field with none of these keeps the exact tree it had before this module
	chrome.active = spec.label ~= nil
		or spec.hint ~= nil
		or spec.errorText ~= nil
		or internal ~= nil
		or spec.leading ~= nil
		or spec.trailing ~= nil
	chrome.hasAccessories = spec.leading ~= nil or spec.trailing ~= nil
	chrome.LABEL_ID = "Label"

	local function labelView(): any?
		if spec.label == nil then
			return nil
		end
		local words: any = spec.label
		if spec.requiredMark == "required" then
			words = if type(spec.label) == "string"
				then spec.label .. REQUIRED_SUFFIX
				else Compose.formula(function(use)
					local text = selection.read(spec.label, use)
					return (if type(text) == "string" then text else "") .. REQUIRED_SUFFIX
				end)
		end
		return UI.Button({
			id = chrome.LABEL_ID,
			label = spec.label,
			focusable = false,
			-- not a plate: a package that frames its controls would frame every label
			surface = "plain",
			padding = 0,
			width = UI.fill(),
			height = { type = "minMax", min = "targetSizes.minimum" },
			align = "end",
			children = {
				UI.Text({
					id = "Title",
					text = words,
					textSize = "label",
					width = UI.fill(),
					-- a label wraps; one unbreakable word stays reachable
					disclose = true,
				}),
			},
		})
	end

	-- declared once (a hint, an error or an internal line) the line stays mounted
	-- and merely hidden, so words can arrive without moving the field
	local function messageView(): any?
		if spec.hint == nil and spec.errorText == nil and internal == nil then
			return nil
		end
		local hidden = Compose.formula(function(use)
			return use(message) == ""
		end)
		local text = UI.Text({
			id = "Validation",
			text = message,
			textSize = "caption",
			width = UI.fill(),
			disclose = true,
			tint = Compose.formula(function(use)
				return if use(chrome.hasError) then { role = "danger", blend = 1 } else nil
			end),
			role = Compose.formula(function(use)
				return if use(chrome.hasError) then "content" else "secondary"
			end),
			hidden = hidden,
		})
		--[[ THE MARK MOUNTS ONLY DURING AN ERROR: a hidden node keeps its box and
			would indent every resting hint out of line with the plate above it. Its
			own danger tint publishes the lettering tag that paints the managed
			picture the message's colour (`sheet_model.STATUS_LETTERS`). ]]
		local function markView(): any
			return chromeSlots.attachHint(
				UI.Text({
					id = "MessageMark",
					text = themePackage.iconGlyph(ERROR_ICON) or "x!",
					textSize = "caption",
					textAlign = "center",
					lineLimit = 1,
					tint = { role = "danger", blend = 1 },
					width = MARK_WIDTH,
					height = UI.hug(),
				}),
				{ icon = ERROR_ICON, iconSize = "small" }
			)
		end
		return UI.HStack({
			id = "Message",
			gap = "xs",
			align = "start",
			width = UI.fill(),
			hidden = hidden,
			children = {
				UI.When({ id = "MarkWhen", condition = chrome.hasError, thenView = markView }),
				text,
			},
		})
	end

	-- the whole blueprint: the field row keeps its own id; with no furniture the
	-- row IS the control
	function chrome.wrap(fieldRow: any, id: string): any
		if not chrome.active then
			return fieldRow
		end
		local children: { any } = {}
		local label = labelView()
		if label ~= nil then
			table.insert(children, label)
		end
		table.insert(children, fieldRow)
		local line = messageView()
		if line ~= nil then
			table.insert(children, line)
		end
		return UI.VStack({ id = id, width = UI.fill(), gap = "xs", children = children })
	end

	function chrome.dumpInto(into: any)
		into.label = selection.read(spec.label)
		into.requiredMark = spec.requiredMark
		into.hint = selection.read(spec.hint)
		into.errorText = chrome.errorMessage:peek()
		into.hasError = chrome.hasError:peek()
		into.controlSize = selection.read(spec.controlSize)
		into.appearance = selection.read(spec.appearance)
		into.corners = spec.corners
		into.leading = spec.leading ~= nil
		into.trailing = spec.trailing ~= nil
	end

	return chrome
end

return field_chrome
