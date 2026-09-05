--!strict
--[[ ── AXIS 3: THE MEASURE STAMP ──────────────────────────────────────────────

	Lifted out of `render/renderer.luau` on 2026-09-05 (Plan C, T18-A) for the
	Source-write headroom the settle-closure work needs: that file was 195,709 with
	1,791 characters to the campaign's STOP line and the closure routing does not
	fit under it. The move is BEHAVIOUR-NEUTRAL by construction — the string this
	file builds is character-for-character the one the renderer built, in the same
	order, from the same locals — and `tests/measure_stamp_seam.spec.luau` is that
	mechanised.

	WHAT IT IS. One string naming every solve-wide input a stored measurement was
	taken under, and it is read in three places that must never disagree:

	  * `layout/measure_reuse`'s cross-solve store, which is DROPPED when it moves;
	  * `solver.luau:1612`'s node-resident serve (`node.mStamp == ctx.measureStamp`);
	  * `stack_measure.luau:136`'s container memo (`cmemo.mStamp == ctx.measureStamp`).

	It is built ONCE and handed to all three, which is why it was a local in the
	renderer and is a returned value here: `solver.measure` may answer a clean node
	from a tuple ON THE NODE, and that tuple outlives the store the stamp clears. The
	store and the tuple get the same answer to the same question, from the same
	string.

	THE TERM THIS FILE EXISTS TO BE ABLE TO CHANGE, booked rather than taken here.
	The last term is `text_metrics.epoch()` — a PROCESS-GLOBAL counter bumped by
	`calibrate`, `resetCalibration`, `setMeasured`, `markUnmeasurable` and
	`resetMeasured` alike. So ONE learned word moves this string, which drops the
	cross-solve store and fails `node.mStamp == ctx.measureStamp` for every node of
	every attached surface: a settled session pays a fully cold whole-tree re-solve
	per new damage number, score or timer readout. Measured live (T17, FacetBench
	§C15): `battle_hud L setState` 39.7 ms and `addItem-damage` 77.0 ms against 3.7 /
	4.0 headless, `lastMeasured == lastMeasureCalls == 14,2xx` on 5,109 nodes; and
	measured HEADLESS at 14,215 on the same workload, so the pin needs no Studio.

	THIS COMMIT CHANGES NOTHING. The string built below is character-for-character
	the one `renderer.luau` built, term for term and in the same order, and the seam
	spec pins that. The narrowing lands next, in the commit that also builds the
	index and the routing it needs — because the term's removal is worth exactly
	NOTHING on its own (`renderer.luau:2048-2067`: the settle re-solve reaches the
	solver with `solveOpts.reuse == nil`, so the store is cleared and no memo is
	consulted whatever this string says).

	THE ONE-WAY CLAIM. One require, `../layout/text_metrics`, which the renderer
	requires too and which requires nothing of `render/`. No `deps` record, no
	adapter, no upvalue of the host, no module-level mutable state: every input is an
	argument and the only by-reference values (`measureStore`, `metrics`) are ones
	this file passes straight through to `measure_reuse.restamp` without reading a
	field of either. Same shape as `render/dirty_closure`, one require heavier.
]]

local measure_reuse = require("../layout/measure_reuse")
local text_metrics = require("../layout/text_metrics")

local measure_stamp = {}

--[[ Build axis 3 and re-stamp the store with it, returning `(stamp, moved)`.

	THE STAMP IS TAKEN BEFORE THE REUSE DECISION and UNCONDITIONALLY, whether or not
	the measure cache is on: it is axis 3 of the store AND the solve root's own
	offer, and gating it made the renderer's structural refusal unfirable in the one
	arm that exists to make a divergence attributable (`render/structural_scope`, AND
	THE STAMP HAS TO BE TAKEN). Only `solveOpts.measures` is gated.

	`metrics` travels BESIDE the string rather than inside it: `tostring(metrics)`
	was an ADDRESS, and Luau reuses an address once its table is collected, so a
	snapshot allocated where the old one had been read as unchanged and the whole
	store was served to a solve measured under the other theme
	(`measure_reuse.Store.metrics`, and `tests/measure_reuse.spec.luau`'s AXIS 3
	case). Identity is the cheap and correct question.

	POSITIONAL rather than a record: this runs once per solve and a record would be
	one allocation per solve for nothing. ]]
function measure_stamp.take(
	store: any,
	metrics: any,
	vp: { w: number, h: number },
	insets: { top: number, bottom: number, left: number, right: number },
	rootPolicy: string,
	barReserve: number,
	band: { x: number, y: number, w: number, h: number }?,
	bandFullTop: boolean,
	measureScale: number,
	prefOffset: number
): (string, boolean)
	local stamp = `{vp.w}|{vp.h}|{insets.top}|{insets.bottom}|{insets.left}|{insets.right}|{rootPolicy}|{barReserve}`
		.. `|{if band ~= nil then `{band.x},{band.y},{band.w},{band.h}` else "-"}|{bandFullTop}`
		.. `|{measureScale}|{prefOffset}|{text_metrics.epoch()}`
	return stamp, measure_reuse.restamp(store, stamp, metrics)
end

return measure_stamp
