--!strict
-- The pieces every Cartwheel screen is made of. One place, so a card is the
-- same card everywhere and a status chip cannot drift into two treatments.
--
-- EVERY NUMBER HERE IS A TOKEN. Sizes name theme metrics ("iconSizes.large",
-- "controlSizes.regular.height"), type names a role, spacing names a step — so
-- installing Fantasy Parchment moves the whole proof. The seven structural
-- numbers this proof owns are metric NAMES too now ("app.cartwheel.tileMin",
-- ADR-0042), declared once in `init.luau`, so the package has no layout literal
-- left at all.
local data = require("../content/data")

local parts = {}

-- a card: the raised plate every dashboard glance and every detail block sits on
function parts.card(app: any, spec: any): any
	local UI = app.UI
	local card = UI.VStack({
		id = spec.id,
		surface = "raised",
		padding = "m",
		gap = "s",
		width = spec.width or { type = "fill", weight = 1 },
		height = spec.height,
		align = spec.align,
		children = spec.children,
	})
	card = UI.corners(card, "panel")
	return UI.shadow(card, "raised")
end

-- a plain sub-plate (the Workbench preview box, a flavor block)
function parts.plate(app: any, spec: any): any
	local UI = app.UI
	local plate = UI.VStack({
		id = spec.id,
		surface = "base",
		padding = spec.padding or "s",
		gap = spec.gap or "xs",
		width = spec.width or { type = "fill", weight = 1 },
		height = spec.height,
		align = spec.align,
		children = spec.children,
	})
	return UI.corners(plate, "control")
end

-- THE POTION MARK. One picture, one identity hue, one ASCII fallback: the tint
-- is the `direct` form on purpose (spec §1 invariant 1 — hue is IDENTITY, and a
-- potion's colour IS game data, which is the one thing that channel is for).
function parts.potionMark(app: any, id: string, potion: any, size: string?): any
	local UI = app.UI
	local px = size or "iconSizes.large"
	return UI.Image({
		id = id,
		image = potion.mark.image,
		scaleMode = "fit",
		tint = { direct = potion.hue },
		width = { type = "fixed", px = px },
		height = { type = "fixed", px = px },
	})
end

-- THE DIAGONAL THUMB STACK (spec §5; capability ledger: Anchor fractional
-- offsets, the declared adaptation of the reference's custom Layout). Up to
-- three marks, back to front, each a third of the box further along the
-- diagonal — so a brew reads as a stack of bottles at tile size.
function parts.thumbStack(app: any, id: string, items: { any }, size: string?): any
	local UI = app.UI
	local box = size or "controlSizes.regular.height"
	local children: { any } = {}
	local offsets = { 0.3, 0.5, 0.7 }
	for index = 1, math.min(3, #items) do
		local potion = data.potionById(items[index].potion)
		if potion == nil then
			continue
		end
		children[index] = UI.Image({
			id = "Mark" .. index,
			image = potion.mark.image,
			scaleMode = "fit",
			tint = { direct = potion.hue },
			anchor = "topLeft",
			offsetX = { scale = offsets[index] - 0.3 },
			offsetY = { scale = offsets[index] - 0.3 },
			width = { type = "fixed", px = "iconSizes.medium" },
			height = { type = "fixed", px = "iconSizes.medium" },
		})
	end
	return UI.Anchor({
		id = id,
		width = { type = "fixed", px = box },
		height = { type = "fixed", px = box },
		children = children,
	})
end

-- a state chip. `chip` is the read-only surface a Text may wear, so a status
-- never borrows a control treatment and never spends a second hue (invariant 3).
function parts.chip(app: any, id: string, text: any, role: string?): any
	return app.UI.Text({
		id = id,
		text = text,
		textSize = "caption",
		surface = "chip",
		role = role,
		padding = "xs",
	})
end

-- a count. `badge` is the counter seal; the value is centred on it.
function parts.badge(app: any, id: string, text: any): any
	return app.UI.Text({
		id = id,
		text = text,
		textSize = "caption",
		surface = "badge",
		textAlign = "center",
		padding = "xs",
	})
end

-- A POLYLINE FOR `UI.Path`. `values` are 0..1 samples; the answer is normalized
-- control points with zero tangents (a straight run between samples), which is
-- the declared chart approximation — Path2D strokes and never fills.
function parts.polyline(values: { number }): { any }
	local count = #values
	local points: { any } = {}
	if count == 0 then
		return points
	end
	for index, value in values do
		local x = if count == 1 then 0.5 else (index - 1) / (count - 1)
		table.insert(points, {
			x = x,
			y = 1 - math.clamp(value, 0, 1),
			inX = 0,
			inY = 0,
			outX = 0,
			outY = 0,
		})
	end
	return points
end

-- the six attribute names, in their fixed order, translated
function parts.attributeName(app: any, axis: number): string
	return app.S.t("attr." .. (data.ATTRIBUTES :: any)[axis])
end

-- a heading row with a trailing chevron, as ONE button — the whole header IS
-- the target (spec §5), so a card never has a tap zone smaller than it looks.
-- It is a CONTENT button, so it declares no `compactLabel`: a button with
-- children draws no text of its own and the framework refuses one (its content
-- adapts through what is inside it instead).
function parts.cardHeaderButton(app: any, spec: any): any
	local UI = app.UI
	return UI.Button({
		id = spec.id,
		label = spec.label,
		onActivate = spec.onActivate,
		width = { type = "fill", weight = 1 },
		align = "center",
		gap = "s",
		children = {
			UI.Text({ id = "Title", text = spec.title, textSize = "heading" }),
			UI.Spacer({ id = "Gap", width = { type = "fill", weight = 1 } }),
			UI.Image({
				id = "Chevron",
				image = app.art.marks.chevronRight.image,
				scaleMode = "fit",
				tint = { role = "contentSecondary", blend = 1 },
				width = { type = "fixed", px = "iconSizes.small" },
				height = { type = "fixed", px = "iconSizes.small" },
			}),
		},
	})
end

-- an empty state. A list with nothing in it says so, in words.
function parts.empty(app: any, id: string, text: string): any
	return app.UI.Text({ id = id, text = text, textSize = "body", role = "secondary", padding = "m" })
end

return parts
