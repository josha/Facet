--!strict
-- Shared Sipworks pieces: the art plate, the FlipPlate recipe, the ambient
-- steam backdrop, and the two-line measured row. Every one of them is used by
-- BOTH entry flows, which is what makes the compact-link entry a different
-- SHELL rather than a second app (spec §11).

local dims = require("../content/dims")
local artContent = require("../content/art")

local parts = {}

-- ---------------------------------------------------------------------------
-- artPlate — the one picture seam (see content/art.luau for why it is a
-- monogram and not an asset id). Give an art entry an `image` and the same box
-- paints a cropped picture instead; nothing else in the proof changes.
-- ---------------------------------------------------------------------------

-- artPlate(app, kind, id, { width, height, id?, markSize? }) — both dimensions
-- are the caller's, because an art box is a LAYOUT decision (a row thumbnail, a
-- tile, a header, a full-bleed backdrop) and the plate itself has no opinion.
function parts.artPlate(app: any, kind: string, id: string, opts: any?): any
	local UI = app.UI
	local options = opts or {}
	local a = artContent.of(kind, id)
	local box = options.width or dims.fill
	local height = options.height or box
	local children: { any } = {
		UI.Box({
			id = "Plate",
			width = dims.fill,
			height = dims.fill,
			tint = { role = a.role, blend = a.blend },
			corners = UI.cornersData("control"),
			stroke = UI.strokeData({}),
		}),
	}
	if a.image ~= nil then
		table.insert(
			children,
			UI.Image({
				id = "Art",
				image = a.image,
				scaleMode = "crop",
				width = dims.fill,
				height = dims.fill,
				corners = UI.cornersData("control"),
			})
		)
	else
		table.insert(
			children,
			UI.Text({
				id = "Mark",
				text = a.mark,
				textSize = options.markSize or "heading",
				textAlign = "center",
				-- a monogram is DECORATIVE fixed content: one line, declared —
				-- its hug box can land exactly on the engine's text-bounds
				-- boundary (TextFits false at bounds == box), and the declared
				-- policy is what keeps that a non-finding on the device matrix
				lineLimit = 1,
			})
		)
	end
	return UI.ZStack({
		id = options.id or "Art",
		width = box,
		height = height,
		alignH = "center",
		alignV = "center",
		children = children,
	})
end

-- ---------------------------------------------------------------------------
-- FlipPlate (spec §12) — the declared width-collapse flip.
--
-- Roblox 2D GUI has no perspective transform (capability ledger §A), and the
-- public presentation channel's `scale` is UNIFORM — so the honest flip is the
-- one the ledger declares: the front face collapses its WIDTH through zero and
-- the back face opens out of it. One spring drives both; the faces swap
-- interactivity at the midpoint through `UI.When`, so the hidden face is
-- unmounted and can never be focused.
--
-- Under reduced motion the spring places instantly, so the swap happens on the
-- same frame with no travel — the parity is structural, not a branch.
-- ---------------------------------------------------------------------------

function parts.flipPlate(app: any, spec: any): any
	local UI = app.UI
	local core = app.core
	local progress = spec.progress

	local showBack = app.own(core:memo(function(use)
		return use(progress) >= 0.5
	end))
	local showFront = app.own(core:memo(function(use)
		return use(progress) < 0.5
	end))
	local frontWidth = app.own(core:memo(function(use)
		return dims.percent(math.max(0.02, 1 - 2 * use(progress)))
	end))
	local backWidth = app.own(core:memo(function(use)
		return dims.percent(math.max(0.02, 2 * use(progress) - 1))
	end))

	return UI.ZStack({
		id = spec.id,
		width = spec.width,
		height = spec.height,
		alignH = "center",
		alignV = "center",
		children = {
			UI.When({
				id = "Front",
				condition = showFront,
				thenView = function()
					return UI.ZStack({
						id = "FrontFace",
						width = frontWidth,
						height = dims.fill,
						alignH = "center",
						alignV = "center",
						children = { spec.front() },
					})
				end,
			}),
			UI.When({
				id = "Back",
				condition = showBack,
				thenView = function()
					return UI.ZStack({
						id = "BackFace",
						width = backWidth,
						height = dims.fill,
						alignH = "center",
						alignV = "center",
						children = { spec.back() },
					})
				end,
			}),
		},
	})
end

-- ---------------------------------------------------------------------------
-- The ambient steam backdrop (spec §12): eight wisps at SEEDED fractional
-- offsets inside an `Anchor`, each drifting on a `decay` spring bound straight
-- to its `offsetY` — an arrange-only prop, so a drifting wisp never re-measures
-- anything.
--
-- The ping-pong is armed ONLY under full motion. Under reduced motion a spring
-- places instantly and fires its settle on the same frame, so a re-target from
-- inside `onSettle` would recurse forever: the reduced form is the spec's own
-- ("stills: wisps placed at seeded rest positions"), and it is also the only
-- form that terminates.
-- ---------------------------------------------------------------------------

--[[ THE TWO §12 NUMBERS THAT ARE NOT DIMENSIONS (ADR-0042).

	A wisp COUNT is a loop bound and a wisp TRAVEL is a spring target — Luau
	numbers, not box dimensions, so neither can be spelled as a `px`. They are
	still declared in the proof's own `app.sip` namespace, because the spec lists
	them with the rest of §12 and one home is the point; `app.metric` reads them
	off the live snapshot instead of restating them here.

	AND THE LADDER LEAVES THEM ALONE, which is why their names read the way they
	do: `wispCount` and `wispTravelFraction` each end in a segment the ten-foot
	classification knows is not a length, so a television gets eight wisps drifting
	0.16 of the backdrop — not twelve drifting 0.24. ]]
function parts.steamBackdrop(app: any, id: string): any
	local UI = app.UI
	local wisps: { any } = {}
	local rng = app.seed
	local reduced = app.motionPolicy() == "reduced"
	for i = 1, app.metric("wispCount") do
		-- a tiny deterministic hash, so the drift is seeded and never random
		rng = (rng * 1103515245 + 12345) % 2147483648
		local x = 0.06 + ((rng // 97) % 88) / 100
		rng = (rng * 1103515245 + 12345) % 2147483648
		local rest = 0.1 + ((rng // 89) % 80) / 100
		local travel = app.metric("wispTravelFraction")

		local offset: any
		if reduced or app.clockMotion == nil then
			offset = { scale = rest }
		else
			local spring = app.own(app.clockMotion:spring(rest, "decay"))
			local up = true
			local function retarget()
				up = not up
				spring:setTarget(if up then rest - travel else rest)
			end
			spring:onSettle(retarget)
			retarget()
			offset = app.own(app.core:memo(function(use)
				return { scale = use(spring) }
			end))
		end

		table.insert(
			wisps,
			UI.Box({
				id = "Wisp" .. i,
				anchor = "topLeft",
				offsetX = { scale = x },
				offsetY = offset,
				width = dims.fixed("app.sip.wispSize"),
				height = dims.fixed("app.sip.wispSize"),
				corners = UI.cornersData("pill"),
				tint = { role = "contentSecondary", blend = 0.18 },
			})
		)
	end
	return UI.Anchor({ id = id, width = dims.fill, height = dims.fill, children = wisps })
end

-- ---------------------------------------------------------------------------
-- A measured fact row: label on the left, value on the right, both localized.
-- Used by the botanical card's facts face and by the recipe's ingredient list.
-- ---------------------------------------------------------------------------

function parts.factRow(app: any, id: string, label: any, value: any): any
	local UI = app.UI
	return UI.HStack({
		id = id,
		gap = "xs",
		align = "center",
		width = dims.fill,
		children = {
			UI.Text({
				id = "Label",
				text = label,
				textSize = "body",
				width = dims.fill,
				lineLimit = 2,
				disclose = true,
			}),
			UI.Text({ id = "Value", text = value, textSize = "numeral", textAlign = "end" }),
		},
	})
end

return parts
