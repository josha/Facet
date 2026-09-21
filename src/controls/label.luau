--!strict
-- An icon and title pair. The title remains its accessible name in every presentation.
local Compose = require("../vendor/compose/core")

local specGuard = require("../spec_guard")
local selection = require("../selection_model")
local chromeSlots = require("../tokens/chrome_slots")
local themePackage = require("../themes/package")

local label_control = {}

local specTypes = require("../spec_types/label")
export type Spec = specTypes.Spec

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
	specGuard.assertKnownKeys("UI.Label", spec, LABEL_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Label"
	local titleNow = selection.read(spec.title)
	if type(titleNow) ~= "string" or titleNow == "" then
		error(
			`Facet UI.Label('{id}'): \`title\` is required and must be non-empty — it is the semantic `
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
		error(`Facet UI.Label('{id}'): unknown presentation '{presentation}'. One of {table.concat(names, " | ")}.`, 0)
	end
	-- iconOnly DEGRADES to the title when there is no icon to show: an empty
	-- square is worse than a word (the fallback this construct exists for)
	local effective = presentation
	if spec.icon == nil and presentation ~= "titleOnly" then
		effective = "titleOnly"
	end

	if type(spec.icon) == "string" and string.match(spec.icon, "^%a[%w+.-]*://") == nil then
		assert(themePackage.isIconName(spec.icon), `Facet UI.Label('{id}'): unknown icon '{spec.icon}'.`)
	end

	local children: { any } = {}
	if effective ~= "titleOnly" then
		local size = spec.iconSize or "controlSizes.regular.iconSize"
		if type(spec.icon) == "string" and string.match(spec.icon, "^%a[%w+.-]*://") == nil then
			table.insert(
				children,
				chromeSlots.attachHint(
					UI.Text({
						id = "Icon",
						text = themePackage.iconGlyph(spec.icon) or "•",
						textSize = "control",
						textAlign = "center",
						-- A semantic glyph can grow with the text preference; package art fits its box.
						width = { type = "minMax", min = size },
						height = { type = "minMax", min = size },
					}),
					{ icon = spec.icon }
				)
			)
		else
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
	api.semanticText = Compose.formula(function(use)
		return selection.read(spec.title, use)
	end)

	function api.dump()
		local title = selection.read(spec.title)
		return {
			schema = "facet-label-dump/1",
			id = id,
			title = title,
			icon = spec.icon,
			requestedPresentation = presentation,
			effectivePresentation = effective,
			degradedToTitle = effective ~= presentation,
			semanticText = title,
		}
	end

	function api.dispose()
		api.semanticText:dispose()
	end

	return api
end

return label_control
