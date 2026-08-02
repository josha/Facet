--!strict
-- ProgressView: determinate linear progress (docs/plans/swiftui-parity-next.md
-- investment 7; acceptance row B-DSP1). A track with a filled portion, over the
-- SHARED value model, so its clamping and formatting are the same arithmetic
-- Slider and Stepper use.
--
-- NON-INTERACTIVE by design: progress reports, it does not accept input. It has
-- no focus role and no semantic action, and it declares that explicitly rather
-- than being silently absent from conformance.
--
-- Paint is style-owned, and since ADR-0020 R3 it is owned through the BAR FAMILY
-- rather than through borrowed public surfaces. The track used to declare
-- `surface = "control"` and the fill `surface = "accent"`, which subscribed both
-- to treatments meant for buttons and panels: an ornate package stretched a
-- BUTTON plate across the track, and a panel gradient's alpha made the fill
-- see-through — the same defect the slider's rail and thumb had, one control
-- down (the Step 3.5 progress-Bar cosmetic deferral). They now DECLARE their
-- slots on the blueprint's internal meta channel, exactly as the Slider does, so
-- `barTrack` / `barFill` are their whole paint identity: solid `luau-slot-*`
-- rules when no package skins them, and a package's own track/fill/cap/centre
-- art when one does.

local chrome_slots = require("../tokens/chrome_slots")
local value_model = require("./value_model")

local progress_view = {}

-- theme metrics (ADR-0019 §2), resolved on every solve
local TRACK_HEIGHT = "controls.progress.trackHeight"
-- even, so an even track centres exactly; see the note on the row below
local ROW_MIN_HEIGHT = "controls.progress.rowMinHeight"

export type Spec = {
	id: string?,
	label: string?,
	value: any, -- number | Readable<number>
	min: number?, -- default 0
	max: number?, -- default 1
	format: ((value: number) -> string)?,
	showValue: boolean?, -- render the formatted value beside the bar
	height: number?,
}

function progress_view.build(LuauUI: any, core: any, spec: Spec)
	local UI = LuauUI.UI
	local id = spec.id or "Progress"
	local scope = core:scope("progress-" .. tostring(id))
	local model = value_model.new({
		min = spec.min or 0,
		max = if spec.max ~= nil then spec.max else 1,
		format = spec.format,
	})
	local isReadable = type(spec.value) == "table" and (spec.value :: any).get ~= nil
	local function read(use: any?): number
		if isReadable then
			return if use ~= nil then use(spec.value) else (spec.value :: any):get()
		end
		return spec.value :: number
	end

	-- the filled portion is a PERCENT dim, so the bar reflows with its container
	-- without the control recomputing pixels on every resize
	local fillDim = scope:own(core:memo(function(use)
		return { type = "percent", fraction = model.fraction(read(use)) }
	end))
	local readout = scope:own(core:memo(function(use)
		return model.format(read(use))
	end))
	local semantic = scope:own(core:memo(function(use)
		return model.semanticText(read(use))
	end))

	local bar = chrome_slots.attachHint(
		UI.ZStack({
			id = "Bar",
			width = { type = "fill", weight = 1 },
			height = { type = "fixed", px = spec.height or TRACK_HEIGHT },
			children = {
				-- THE FILL IS THE CLIP WINDOW (ADR-0020 R3, probe rs-m4). The solver
				-- keeps sizing this node to the percent — that is what a flat bar's
				-- accent block IS — and a package that skins the bar has the adapter
				-- parent a ClipsDescendants window over it holding a FULL-TRACK-size
				-- image. So the art never re-derives its nine-patch as the value
				-- moves, and the geometry stays exactly where it was: solver-owned.
				chrome_slots.attachHint(
					UI.Box({
						id = "Fill",
						alignH = "start",
						width = fillDim,
						height = { type = "fill", weight = 1 },
					}),
					{ slot = "barFill" }
				),
			},
		}),
		{ slot = "barTrack" }
	)

	local children: { any } = {}
	if spec.label ~= nil then
		table.insert(children, UI.Text({ id = "Label", text = spec.label, textSize = "label" }))
	end
	table.insert(children, bar)
	if spec.showValue == true then
		table.insert(children, UI.Text({ id = "Value", text = readout, textSize = "label" }))
	end

	local api = {}
	-- ROW HEIGHT IS EVEN ON PURPOSE (director review 2026-07-24). The track is an
	-- even 6px; the row's content height came out of the text measure as 17, and an
	-- even bar cannot be pixel-centred in an odd row — alignOffset floors, so the
	-- bar sat half a logical pixel high, which is a full pixel on a 2x display and
	-- the director saw it twice. Flooring an even row instead removes the parity
	-- mismatch by construction rather than moving the error to the other side.
	api.blueprint = UI.HStack({
		id = id,
		gap = "s",
		align = "center",
		width = { type = "fill", weight = 1 },
		height = { type = "minMax", min = ROW_MIN_HEIGHT },
		children = children,
	})
	api.model = model
	api.semanticText = semantic

	function api.dump()
		local v = read(nil)
		return {
			schema = "luauui-progress-dump/1",
			id = id,
			value = v,
			fraction = model.fraction(v),
			formatted = model.format(v),
			semanticText = model.semanticText(v),
			min = model.min,
			max = model.max,
			showValue = spec.showValue == true,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api
end

return progress_view
