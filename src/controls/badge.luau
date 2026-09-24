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
local contribution = require("../input/contribution")
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
	local UI, id, appearance =
		library.UI, spec.id or "Badge", if spec.appearance == nil then "standard" else spec.appearance
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
	assert(
		spec.name == nil or (type(spec.name) == "string" and spec.name ~= ""),
		"Facet Badge: name must be a nonempty string"
	)
	vocabulary.assertCorners("Badge", spec.corners)
	vocabulary.assertOver("Badge", spec.over)
	local facts = Compose.formula(function(use)
		local label, status, rung =
			selection.read(spec.label, use), selection.read(spec.status, use), selection.read(spec.controlSize, use)
		status = if status == nil then "neutral" else status
		assert(label == nil or type(label) == "string", "Facet Badge: label must be a string")
		assert(
			(label ~= nil and label ~= "") or (spec.icon ~= nil and spec.name ~= nil),
			"Facet Badge: an empty caption requires an icon and nonempty name"
		)
		assert(
			statusIndicator.STATUS_SET[status],
			"Facet Badge: status must be neutral | info | success | warning | error | accent"
		)
		vocabulary.assertSize("Badge", rung)
		return { label = label, status = status, controlSize = rung }
	end)
	local initial = facts:peek()
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
				{ id = "Mark", status = field("status"), controlSize = field("controlSize"), cutout = true }
			).blueprint
		)
	end
	local icon
	if spec.icon then
		-- One glyph host; the target owns its optional square picture and suppression.
		-- Width is a floor, not a square clamp: two-character fallback glyphs can grow.
		icon = chrome.attachHint(
			UI.Text({
				id = "Icon",
				text = themePackage.iconGlyph(spec.icon) or "",
				textSize = "caption",
				textAlign = "center",
				lineLimit = 1,
				tint = letterTint,
				width = { type = "minMax", min = "iconSizes.small" },
				height = UI.hug(),
			}),
			{ icon = spec.icon, iconSize = "small" }
		)
	end
	if icon and spec.iconPosition ~= "trailing" then
		table.insert(content, icon)
	end
	local function labelView()
		return UI.Text({
			id = "Label",
			text = field("label"),
			textSize = "caption",
			tint = letterTint,
			shrinkWeight = 1,
			disclose = true,
		})
	end
	if selection.isSource(spec.label) then
		table.insert(
			content,
			UI.When({
				id = "LabelContent",
				condition = function(use)
					local label = use(facts).label
					return label ~= nil and label ~= ""
				end,
				thenView = labelView,
			})
		)
	elseif initial.label ~= nil and initial.label ~= "" then
		table.insert(content, labelView())
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
--[[ THE COUNT SEAL, one builder for every host (owner ruling 2026-09-23, Badge
	placement A). A text row wears it as an inline trailing pill; a Button, icon
	button, Avatar or tab icon wears it on its corner (`badge.corner`). `value` is
	a string, a number (above 99 reads "99+"), `true` for a dot (the seal with no
	number), or a Readable of one; nil, false and "" paint nothing. ]]
function badge.countText(value: any): string
	if value == nil or value == false or value == true then
		return ""
	end
	if type(value) == "number" then
		return if value > 99 then "99+" else tostring(value)
	end
	return tostring(value)
end

function badge.seal(UI: any, id: string, value: any, offset: any?): any
	local live = type(value) == "function" or Compose.isReadable(value)
	local text = if live
		then function(use: Compose.Use): string
			return badge.countText(selection.read(value, use))
		end
		else badge.countText(value)
	local function shown(v: any): boolean
		return v == true or badge.countText(v) ~= ""
	end
	local hidden = if live
		then function(use: Compose.Use): boolean
			return not shown(selection.read(value, use))
		end
		else not shown(value)
	--[[ THE SEAL IS A PLATE AND THE NUMBER IS A NODE INSIDE IT (owner
			report 2026-09-12, `tests/badge_centering.spec.luau`).

			WHAT WAS REPORTED: the count sits off-centre in its circle.

			THE PLATE IS BIGGER THAN THE GLYPH, by two rules that both mean
			to be: `render/layout_node.luau` gives `surface = "badge"` an
			intrinsic MINIMUM on both axes (`controls.badge.minimum`, 20px in
			Facet Neutral) and the padding below adds a margin a side. So
			SOMETHING has to decide where the number sits in the slack, and
			while the plate and the glyph were ONE `UI.Text` nothing in Facet
			did: the horizontal answer came from `screen_target`'s create
			default for a text node (`TextXAlignment.Left`, which put the
			number 2.5px left of centre in Facet Neutral) and the vertical one
			from its `TextYAlignment.Center`. One of those two is wrong and
			neither is this control's.

			THEY WERE ALSO UNMEASURABLE. One node is one solved rect, so no
			headless test could ask where the number sat inside its seal — the
			first version of this fix pinned a DERIVED answer, which is a pin
			on a declaration and not on paint. A plate with a glyph inside it
			has two rects and the claim becomes a measurement: with the glyph
			a node of its own and the stack left to place it, it lands at the
			plate's top-left (dy -2.5 in Facet Neutral, -3 under Compact
			Pointer, -2.5 under Pixel Quest), and `alignH`/`alignV` are what
			put it in the middle — as this control's decision, on both axes,
			in a form the target can see.

			THE PADDING STAYS ON ONE AXIS, deliberately, and it is the one
			candidate this round measured and rejected. Making it uniform gives
			the glyph vertical breathing room it currently has none of at a
			raised text preference (Facet Neutral at +14: a 25x32 seal whose
			glyph clears its sides by 4px and its top and bottom by zero) — but
			it also costs the CIRCLE at the default preference, where the badge
			minimum is what makes the seal 20x20 and a vertical margin would
			make it 20x23. The seal the report was made against is round; a
			margin is not worth an egg. ]]
	return UI.ZStack({
		id = id,
		hidden = hidden,
		offset = offset,
		surface = "badge",
		padding = { left = "xs", right = "xs" },
		corners = UI.cornersData("pill"),
		children = {
			--[[ THE PLATE CARRIES `hidden`, THE NUMBER DOES NOT, and that is a
					cost decision as much as a tidiness one. `hidden` is not just a
					paint flag: the renderer publishes every authored-hidden path as
					an entry in `controller.hiddenRoots()`, and `focus_map.isHiddenPath`
					answers "is this path inside a subtree that does not paint" by
					SCANNING that set — once per node, in walks that run every frame
					(`presenter.disclosureTargetIn`, `help_plate.helpTargetIn`,
					`text_reveal`). A nested hidden node is never a root: `/…/Badge`
					is already a path prefix of `/…/Badge/Count`, so the second entry
					cannot change a single answer — it only makes every one of those
					scans longer.

					MEASURED (2026-09-13, `adaptive-navigation-images`): three unbadged
					tab options put 3 entries in `hiddenRoots`; declaring it on the
					glyph too put 6 there, and the per-frame disclosure walk went
					7.8→10.6 us and the help walk 11.8→17.5 us — +25% on the whole
					scene, for a duplicated declaration. One decision, one node. ]]
			UI.Text({
				id = "Count",
				text = text,
				textSize = "caption",
				textAlign = "center",
				alignH = "center",
				alignV = "center",
			}),
		},
	})
end

--[[ ...ON A HOST'S CORNER: top-right (top-left in rtl), centred on the corner so
	it sits half over the host. The host keeps its own box and hit target; the seal
	is a later layer (it paints above the host) moved by a paint-only `offset` of
	half its own measured size, so nothing it overhangs is laid out again. ]]
function badge.corner(UI: any, host: any, value: any, direction: string?): any
	local size = Compose.cell({ w = 0, h = 0 })
	local rtl = direction == "rtl"
	local seal = badge.seal(UI, "CornerBadge", value, function(use: Compose.Use): any
		local s = use(size)
		return { x = (if rtl then -s.w else s.w) / 2, y = -s.h / 2 }
	end)
	local wrapper = UI.ZStack({
		id = `{host.id or "Host"}+badge`,
		alignH = if rtl then "start" else "end",
		alignV = "start",
		children = { host, seal },
	})
	return contribution.attach(wrapper, {
		syncGeometry = function(rectOf: (string) -> any, node: any?)
			local r = if node ~= nil then rectOf(`{node.path}/CornerBadge`) else nil
			local now = size:peek()
			if r ~= nil and (r.w ~= now.w or r.h ~= now.h) then
				size:set({ w = r.w, h = r.h })
			end
		end,
	})
end

function badge.build(library: any, core: any, spec: Spec)
	local parent = Compose.currentOwner()
	local owner = if parent then parent.createChild() else core.owner.createChild()
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
