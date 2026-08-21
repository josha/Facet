--!strict
-- Label: an icon + title pair with a semantic text fallback (docs/plans/
-- parity-next.md investment 7; acceptance row B-DSP1).
--
-- The point of the construct is the FALLBACK: when the icon cannot be shown —
-- no asset, or an icon-only presentation at a size where a glyph alone is
-- ambiguous — the title still carries the meaning. `semanticText` is always the
-- title, whatever the presentation, so an icon-only Label is never a control with
-- no accessible name. It is a READABLE (`:get()`), the shape ProgressView,
-- Stepper, Slider and Rating publish, so one readout layer serves all five.
--
-- NON-INTERACTIVE: a Label displays. Put it inside a Button (which now takes
-- content) when it needs to be pressable — that keeps ONE activation surface.

local specGuard = require("../spec_guard")

local label_control = {}

export type Spec = {
	id: string?,
	title: string, -- required: it IS the semantic text
	icon: string?, -- asset string; absent => title-only, no empty slot
	presentation: string?, -- "titleAndIcon" (default) | "titleOnly" | "iconOnly"
	-- each accepts a literal number (theme-independent) or a theme metric name
	iconSize: (number | string)?,
	textSize: (number | string)?,
	gap: (number | string)?,
}

local PRESENTATIONS: { [string]: boolean } = { titleAndIcon = true, titleOnly = true, iconOnly = true }

-- CLOSED SPEC (constitution §4). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local LABEL_KEYS = specGuard.keySet({
	"gap",
	"icon",
	"iconSize",
	"id",
	"presentation",
	"textSize",
	"title",
})

function label_control.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newLabel", spec, LABEL_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Label"
	local scope = core:scope("label-" .. tostring(id))
	if type(spec.title) ~= "string" or spec.title == "" then
		error(
			`Facet newLabel('{id}'): \`title\` is required and must be non-empty — it is the semantic `
				.. `text, so an icon-only Label without one would have no accessible name`,
			0
		)
	end
	local presentation = spec.presentation or "titleAndIcon"
	if not PRESENTATIONS[presentation] then
		local names = {}
		for k in PRESENTATIONS do
			table.insert(names, k)
		end
		table.sort(names)
		error(`Facet newLabel('{id}'): unknown presentation '{presentation}'. One of {table.concat(names, " | ")}.`, 0)
	end
	-- iconOnly DEGRADES to the title when there is no icon to show: an empty
	-- square is worse than a word (the fallback this construct exists for)
	local effective = presentation
	if spec.icon == nil and presentation ~= "titleOnly" then
		effective = "titleOnly"
	end

	local children: { any } = {}
	if effective ~= "titleOnly" then
		local size = spec.iconSize or "controlSizes.regular.iconSize"
		table.insert(
			children,
			UI.Image({
				id = "Icon",
				image = spec.icon,
				width = { type = "fixed", px = size },
				height = { type = "fixed", px = size },
			})
		)
	end
	if effective ~= "iconOnly" then
		-- CENTRED TEXT (director review 2026-07-24). The headless measurer
		-- deliberately over-reserves width — "Save changes" gets a 120px box for
		-- 81px of glyphs — and left-aligned text piles all of that slack on the
		-- right, so a Label whose BOX is perfectly centred still reads as sitting
		-- left of centre over the content beneath it. Centring splits the
		-- measurement error evenly, which is exactly the reasoning the adapter
		-- already applies to TextYAlignment.
		table.insert(
			children,
			UI.Text({ id = "Title", text = spec.title, textSize = spec.textSize or "body", textAlign = "center" })
		)
	end

	local api = {}
	api.blueprint = UI.HStack({
		id = id,
		gap = spec.gap or "controls.label.gap",
		align = "center",
		children = children,
	})
	-- always the title, whatever the presentation — and a READABLE, like the
	-- four siblings that publish one (ProgressView, Stepper, Slider, Rating), so
	-- an accessibility/readout layer can be written ONCE for the family
	-- The title is construction-fixed here, so this is a static memo:
	-- it is owned by the control scope and dies with dispose().
	api.semanticText = scope:own(core:memo(function()
		return spec.title
	end))

	function api.dump()
		return {
			schema = "facet-label-dump/1",
			id = id,
			title = spec.title,
			icon = spec.icon,
			requestedPresentation = presentation,
			effectivePresentation = effective,
			degradedToTitle = effective ~= presentation,
			semanticText = spec.title,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api
end

return label_control
