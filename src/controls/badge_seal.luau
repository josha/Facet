--!strict
-- The count seal and its corner placement (owner ruling 2026-09-23, Badge
-- placement A): internal to the controls that draw a count (menu rows, tab icons)
-- and to `UI.badged`. Not the `UI.Badge` caption control.
local Compose = require("../vendor/compose/core")
local selection = require("../selection_model")
local contribution = require("../input/contribution")

local badge = {}

--[[ THE COUNT SEAL, one builder for every host (owner ruling 2026-09-23, Badge
	placement A). A text row wears it as an inline trailing pill; a Button, icon
	button, Avatar or tab icon wears it on its corner (`badge.corner`). `value` is
	a string, a number (above 99 reads "99+"), `true` for a dot (the seal with a
	bullet), or a Readable of one; nil, false and "" paint nothing. ]]
function badge.countText(value: any): string
	if value == true then
		-- a bullet in the seal's own lettering: an empty seal is invisible wherever
		-- the badge fill sits close to the page (Facet Neutral's surfaceStrong)
		return "•"
	end
	if value == nil or value == false then
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
		return badge.countText(v) ~= ""
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

return badge
