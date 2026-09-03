--!strict
--[[ ── THE TEXT-PREMEASUREMENT ROUND ─────────────────────────────────────────

	Lifted out of `render/renderer.luau` on 2026-09-03, BYTE-VERBATIM in its body,
	because that file's source-cap ledger row has named this block as its next seam
	since the geometry-facts split: *the TEXT-MEASUREMENT ROUND (`textInFlight`,
	`textMeasureCancels`, the collect/deliver/`learned` block inside `solveAndApply`,
	~4 KB) — it reads `adapter`, `env` and `stats`, so it costs a record the way
	`table.luau`'s `rowGesture` did, and is worth taking only by a round that needs
	the room.* Wicked-fast T7 adds 2,500-4,000 characters to a file with 1,480 of
	headroom, so the extraction PRECEDES the product change as its own commit —
	which is what that ledger's wording has demanded of every split this file has
	taken.

	WHAT IS HERE. The RENDERER's end of the premeasurement seam: one round per
	solve, asked at the point in the commit where this frame is already painted from
	the conservative estimate. The ENGINE end is `client/text_premeasure.luau` and
	the pure per-word store is `layout/text_metrics.luau`; neither moved, and the
	`final`/settle contract between them is unchanged here.

	WHY IT COULD LEAVE, in this repository's own terms. All three records the block
	owned are its own — `textInFlight`, `textMeasureCancels` and the reassigned
	scalar `disposed` are read nowhere else in the renderer, so THE STATE LEFT WITH
	THE CODE. The scalar takes the accessor move `tap_arm.luau` proved: `dispose()`
	is its only writer, and it is what the controller's teardown now calls instead of
	assigning. Three names cross by reference and none of them is reassigned
	(`adapter`, `env`, `stats`). `solveAndApply` is passed AT THE CALL, the way
	`layout/stack.luau` takes `place`: it is declared far below the line this record
	is built on, and the round re-enters it.
]]

local text_metrics = require("../layout/text_metrics")

local premeasure_round = {}

export type Deps = {
	-- the render target. Only `measureTextWidths` is read, and it is feature-
	-- detected: an adapter without the seam never starts a round at all
	adapter: any,
	-- the surface environment. `textMeasureEpoch` is the ONE key written here
	env: any,
	-- the controller's counter record. `textMeasureBatches` is incremented and
	-- `solves` is read as the one-solve-per-round guard
	stats: any,
}

export type PremeasureRound = {
	-- run one round for a finished solve's unsizeable words. `solveAndApply` is the
	-- re-solve the delivery owes when a width actually moved
	request: (textRequests: { any }, solveAndApply: () -> ()) -> (),
	-- is a round still outstanding? (`controller.textPending`)
	pending: () -> boolean,
	-- the ONE writer of this module's one mutable scalar
	dispose: () -> (),
}

function premeasure_round.new(deps: Deps): PremeasureRound
	local adapter = deps.adapter
	local env = deps.env
	local stats = deps.stats

	-- words handed to the adapter's premeasurement seam and not yet answered.
	-- Guards against asking twice while one round is in flight; a word that
	-- comes back (measured OR refused) is recorded in text_metrics and can
	-- never be requested again, so this set is the only loop guard needed.
	local textInFlight: { [string]: boolean } = {}
	-- the live premeasurement deliveries this surface has outstanding, cancelled on
	-- teardown so a late answer cannot reach a dismissed surface
	local textMeasureCancels: { () -> () } = {}
	local disposed = false

	--[[ ORDERING IS THE SAFETY PROPERTY, and it belongs to the CALL rather than to
		this function: the renderer asks only once the frame is fully painted from the
		conservative estimate, so the first frame is always the over-reserving
		fallback, never a guess waiting on an async answer, and the exact geometry
		lands one re-solve later. Batched per SOLVE over the whole tree's vocabulary —
		never per node. ]]
	local function request(textRequests: { any }, solveAndApply: () -> ())
		if adapter.measureTextWidths ~= nil and #textRequests > 0 and not disposed then
			local batch: { any } = {}
			for _, request in textRequests do
				local key = `{request.font}\0{request.size}\0{request.word}`
				if not textInFlight[key] then
					textInFlight[key] = true
					table.insert(batch, request)
				end
			end
			if #batch > 0 then
				stats.textMeasureBatches += 1
				-- `final` (default true) is the adapter saying "this batch is
				-- closed". An adapter that answers early with widths it does not
				-- yet trust — the Roblox one does, while the engine's boot window
				-- is still open — passes false, and the words stay in flight so a
				-- surface waiting for exact text keeps waiting.
				local cancelMeasure = adapter.measureTextWidths(batch, function(results: { any }, final: boolean?)
					local learned = false
					for _, entry in results do
						if type(entry) ~= "table" then
							continue
						end
						if final ~= false then
							textInFlight[`{entry.font}\0{entry.size}\0{entry.word}`] = nil
						end
						if type(entry.width) == "number" then
							-- an adapter may answer the SAME batch twice (the
							-- Roblox one re-reads once the session has settled and
							-- corrects the boot answer), so a re-solve is owed only
							-- when a width actually moved
							local previous = text_metrics.measuredWidth(entry.font, entry.size, entry.word)
							if text_metrics.setMeasured(entry.font, entry.size, entry.word, entry.width) then
								if previous ~= entry.width then
									learned = true
								end
							else
								-- a measurement this seam refuses is a measurement
								-- that could clip: keep the estimate, and do not
								-- ask for it again on every solve
								text_metrics.markUnmeasurable(entry.font, entry.size, entry.word)
							end
						else
							text_metrics.markUnmeasurable(entry.font, entry.size, entry.word)
						end
					end
					--[[ exactly one re-solve per answered round, and only when the
						round actually taught the measurer something.

						PUBLISH THE GENERATION FIRST (director 2026-08-04, the
						finish-screen size pop). The re-solve fixes the SOLVER's boxes,
						but a consumer memo that called `Facet.text.fit/.size/.measure`
						has no dependency on the exact-width store — it is plain data —
						so it evaluated once against the ESTIMATOR and nothing here
						invalidated it. Bumping `textMeasureEpoch` is that dependency:
						any memo that reads it re-derives once, on this frame, together
						with the solve rather than at some arbitrary later tick. Written
						before `solveAndApply` so the re-solve already sees the
						re-derived values instead of needing a third pass. ]]
					if learned and not disposed then
						--[[ ...AND THE WRITE MAY HAVE ALREADY SOLVED THIS SURFACE: the fact
							is a GEOMETRY KEY, so it reaches this surface too, and with no
							flush open it settles synchronously — the solve is done before
							`env:set` returns. The counter decides rather than the ordering.

							ONE SOLVE PER LEARNED ROUND ON EVERY ROUTE A SESSION TAKES, and
							the exception is stated rather than implied: an answer delivered
							INSIDE an open flush leaves the write in the core's `writeSet`,
							so the settle runs after this line and the round costs two — the
							inline solve here and the settle's. No shipped path does that
							(a premeasurement answer arrives from the engine on its own
							task, and the specs deliver from top level), which is why the
							counter is the guard rather than a flag: it is right on the
							route that exists and conservative on the one that does not.
							`tests/text_premeasure.spec.luau` pins the shipped number. ]]
						local solvesBefore = stats.solves
						-- `env:get` answers the FACT's signal, so the current value is one
						-- more `:get()` in (same shape as every other read in this file)
						env:set("textMeasureEpoch", ((env:get("textMeasureEpoch"):get() :: number?) or 0) + 1)
						if stats.solves == solvesBefore then
							solveAndApply()
						end
					end
				end)
				-- A BOOT-WINDOW BATCH ANSWERS TWICE, up to ~12 s apart.
				-- `disposed` already gates the re-solve; this stops the delivery
				-- itself, so a torn-down surface is not called back at all.
				if type(cancelMeasure) == "function" then
					table.insert(textMeasureCancels, cancelMeasure)
				end
			end
		end
	end

	return {
		request = request,
		pending = function(): boolean
			for _ in textInFlight do
				return true
			end
			return false
		end,
		-- a premeasurement round outlives the surface that asked for it (it is an
		-- async engine call): mark this round dead so a late answer neither re-solves
		-- nor writes into destroyed handles, and stop the deliveries themselves
		dispose = function()
			disposed = true
			for _, cancel in textMeasureCancels do
				cancel()
			end
			table.clear(textMeasureCancels)
		end,
	}
end

return premeasure_round
