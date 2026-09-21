--!strict
-- Passive caption and optional mark. Its own tinted leaf paints every plate;
-- the package's ornamented badge slot remains reserved for existing Text sites.
local Compose = require("../vendor/compose/core")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local vocabulary = require("./control_vocabulary")
local statusIndicator = require("./status_indicator")
local themePackage = require("../themes/package")
local chrome = require("../tokens/chrome_slots")
local specTypes = require("../spec_types/badge")
export type Spec = specTypes.Spec
local badge = {}
local KEYS = guard.keySet({
	"id",
	"label",
	"icon",
	"iconPosition",
	"status",
	"appearance",
	"corners",
	"controlSize",
	"over",
	"name",
})
local APPEARANCES = guard.keySet({ "standard", "status", "utility" })
local function build(library: any, core: any, spec: any, owner: any)
	guard.assertKnownKeys("UI.Badge", spec, KEYS, "spec")
	local UI, id, appearance = library.UI, spec.id or "Badge", spec.appearance or "standard"
	assert(APPEARANCES[appearance], "Facet Badge: appearance must be standard | status | utility")
	assert(
		spec.icon == nil or (type(spec.icon) == "string" and themePackage.isIconName(spec.icon)),
		"Facet Badge: icon must be a semantic icon name"
	)
	assert(
		spec.iconPosition == nil
			or (spec.icon ~= nil and (spec.iconPosition == "leading" or spec.iconPosition == "trailing")),
		"Facet Badge: iconPosition requires icon and must be leading | trailing"
	)
	vocabulary.assertCorners("Badge", spec.corners)
	vocabulary.assertOver("Badge", spec.over)
	local facts = Compose.formula(function(use)
		local label, status, rung =
			selection.read(spec.label, use),
			selection.read(spec.status, use) or "neutral",
			selection.read(spec.controlSize, use)
		assert(label == nil or type(label) == "string", "Facet Badge: label must be a string")
		assert(
			statusIndicator.STATUS_SET[status],
			"Facet Badge: status must be neutral | info | success | warning | error | accent"
		)
		vocabulary.assertSize("Badge", rung)
		return { label = label, status = status, controlSize = rung }
	end)
	local initial = facts:peek()
	local hasLabel = initial.label ~= nil and initial.label ~= ""
	assert(hasLabel or spec.icon ~= nil, "Facet Badge: supply a label, an icon, or both")
	assert(
		hasLabel or (type(spec.name) == "string" and spec.name ~= ""),
		"Facet Badge: an icon-only badge requires a nonempty name"
	)
	local function field(key)
		return function(use: Compose.Use): any
			return use(facts)[key]
		end
	end
	local plated = appearance ~= "utility"
	local function paintRoles(use: Compose.Use): (string?, string)
		if not plated then
			return nil, "contentSecondary"
		end
		if spec.over == "media" then
			return "surfaceStrong", "contentStrong"
		end
		local word = use(facts).status
		if word == "neutral" then
			return "control", "content"
		end
		return statusIndicator.paintRoles(word)
	end
	local function plateTint(use)
		local plate = paintRoles(use)
		return { role = plate, blend = 1 }
	end
	local function letterTint(use)
		local _, letters = paintRoles(use)
		return { role = letters, blend = 1 }
	end
	local content = {}
	if appearance == "status" then
		table.insert(
			content,
			statusIndicator.build(
				library,
				core,
				{ id = "Mark", status = field("status"), controlSize = field("controlSize") }
			).blueprint
		)
	end
	local icon
	if spec.icon then
		local wantsArt = Compose.formula(function(use)
			local _, letters = paintRoles(use)
			return letters == "content" or not plated
		end)
		local function iconBox(name, hidden)
			return UI.Text({
				id = name,
				text = themePackage.iconGlyph(spec.icon) or "",
				textSize = "caption",
				textAlign = "center",
				tint = letterTint,
				hidden = hidden,
				width = UI.hug(),
				height = UI.hug(),
			})
		end
		-- Hints are creation-time metadata. Keep both representations owned and
		-- switch actual visibility when a live plate needs another letter role.
		icon = UI.ZStack({
			id = "Icon",
			width = UI.hug(),
			height = UI.hug(),
			children = {
				chrome.attachHint(
					iconBox("Art", function(use)
						return not use(wantsArt)
					end),
					{ icon = spec.icon, iconSize = "small" }
				),
				iconBox("Glyph", wantsArt),
			},
		})
	end
	if icon and spec.iconPosition ~= "trailing" then
		table.insert(content, icon)
	end
	if hasLabel then
		table.insert(
			content,
			UI.Text({
				id = "Label",
				text = field("label"),
				textSize = "caption",
				tint = letterTint,
				shrinkWeight = 1,
				disclose = true,
			})
		)
	end
	if icon and spec.iconPosition == "trailing" then
		table.insert(content, icon)
	end
	local root = UI.HStack({
		id = id,
		gap = "xs",
		align = "center",
		padding = if plated then { left = "xs", right = "xs" } else nil,
		height = function(use)
			return { type = "minMax", min = vocabulary.metricPath(use(facts).controlSize or "compact", "iconSize") }
		end,
		children = content,
	})
	if plated then
		root = UI.background(
			root,
			UI.corners(
				UI.Box({ id = "Plate", tint = plateTint }),
				if spec.corners then vocabulary.cornerRadiusFor(spec.corners) else "pill"
			)
		)
	end
	local semantic = Compose.formula(function(use)
		local value = use(facts)
		local name = spec.name or value.label
		return if value.status == "neutral" then tostring(name) else `{name}, {value.status}`
	end)
	local function dump()
		local value = facts:peek()
		return {
			schema = "facet-badge-dump/1",
			id = id,
			label = value.label,
			status = value.status,
			controlSize = value.controlSize,
			icon = spec.icon,
			iconPosition = if spec.icon then spec.iconPosition or "leading" else nil,
			appearance = appearance,
			corners = spec.corners,
			over = spec.over,
			name = spec.name,
			semanticText = semantic:peek(),
		}
	end
	return { blueprint = root, dump = dump, semanticText = semantic, dispose = owner.dispose }
end
function badge.build(library: any, core: any, spec: Spec)
	local parent = Compose.currentOwner()
	local owner = if parent then parent.createChild() else Compose.createOwner(core.scene.reactor)
	local ok, result = pcall(Compose.withOwner, owner, function()
		return build(library, core, spec, owner)
	end)
	if not ok then
		owner.dispose()
		error(result, 0)
	end
	return result
end
return badge
