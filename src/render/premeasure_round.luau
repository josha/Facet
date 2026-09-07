--!strict
--[[ ── THE TEXT-PREMEASUREMENT ROUND ─────────────────────────────────────────

	Lifted out of `render/renderer.luau` on 2026-09-03, BYTE-VERBATIM in its body.
	THE ARGUMENT IS NOT REPEATED HERE: this is the seam that file's source-cap ledger
	row has named by name since the geometry-facts split, and the row states the
	predicted price, what was measured instead, and why the split came first. Read
	`tools/lune/verify/data/source-cap-ledger.md` for the why and
	`tests/premeasure_round_seam.spec.luau` for the executable contract.

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
	-- the controller's counter record. `textMeasureBatches` is incremented,
	-- `textCollectTruncated` is published from the store's process counter, and
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

	--[[ words handed to the adapter's premeasurement seam and not yet answered.
		Guards against asking twice while one round is in flight; a word that
		comes back (measured OR refused) is recorded in text_metrics and can
		never be requested again, so this set is the only loop guard needed.

		TWO STATES, because "this surface asked" and "this surface has been
		answered" are different questions and the re-solve below turns on the
		second. `true` is asked-and-unanswered; `"answered"` is an EARLY answer
		(`final == false`, the engine's boot window) that this surface has already
		re-solved on, with the word still in flight so the settled re-read is not
		refused as a duplicate request. ]]
	local textInFlight: { [string]: boolean | string } = {}
	-- the live premeasurement deliveries this surface has outstanding, cancelled on
	-- teardown so a late answer cannot reach a dismissed surface
	local textMeasureCancels: { () -> () } = {}
	local disposed = false
	--[[ THIS SURFACE'S IDENTITY IN THE PROCESS-GLOBAL HELD-WORD QUEUE (RED-TEAM F5). A
		fresh table, never read for its contents: `layout/text_metrics`'s `overflow` had no
		surface identity at all, so `dispose` below could hand back this surface's share of
		the flight refcount and NOT its share of the queue — and the next surface's first
		collector spent its whole budget on a dead one's vocabulary. Declared here because
		the round is one per surface, which is exactly the granularity the queue was
		missing. ]]
	local overflowOwner = {}

	--[[ ORDERING IS THE SAFETY PROPERTY, and it belongs to the CALL rather than to
		this function: the renderer asks only once the frame is fully painted from the
		conservative estimate, so the first frame is always the over-reserving
		fallback, never a guess waiting on an async answer, and the exact geometry
		lands one re-solve later. Batched per SOLVE over the whole tree's vocabulary —
		never per node. ]]
	local function request(textRequests: { any }, solveAndApply: () -> ())
		--[[ THE COLLECTOR'S OWN SILENCE, PUBLISHED (Plan D, D3a). `layout/text_metrics`
			drops a word it has no budget for and says nothing, which is how a
			sixty-five-round boot drain was read as boxes moving for three rounds. This is
			the one seam that runs once per solve AND already holds both the store and the
			counter record, so the number crosses here rather than through a new require in
			`render/render_stats` — whose whole seam claim is that it requires nothing. It
			is a PROCESS total, because the collector is one per process. ]]
		stats.textCollectTruncated = text_metrics.collectTruncated()
		--[[ ...AND THIS SURFACE OWNS WHAT ITS SOLVE COULD NOT AFFORD TO ASK ABOUT
			(RED-TEAM F5). Unconditional, above the `measureTextWidths` feature test: a
			target with no premeasurement seam never answers a held word, which makes its
			tail MORE in need of an owner and not less. The claim is O(the keys this solve
			pushed), so a settled surface pays nothing. ]]
		text_metrics.claimOverflow(overflowOwner)
		if adapter.measureTextWidths ~= nil and #textRequests > 0 and not disposed then
			local batch: { any } = {}
			for _, request in textRequests do
				local key = `{request.font}\0{request.size}\0{request.word}`
				if not textInFlight[key] then
					textInFlight[key] = true
					--[[ ...AND THE PROCESS LEARNS THE WORD IS OUT (Plan D, D3a). The
						per-surface set above answers "may I ask?"; the refcount answers "is
						anyone waiting?", which is the question the COLLECTOR needs so an
						unanswered backlog stops re-spending its 1024-word budget on every
						solve. One `+1` per dispatch, and every clear below gives it back. ]]
					text_metrics.noteInFlight(key, 1)
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
					--[[ A LATE ANSWER AFTER DISPOSE IS NOT THIS ROUND'S TO COUNT (RED-TEAM
						C-6). `dispose` gives back one flight count per key it still holds and
						DELIBERATELY leaves the set standing (`pending()` reads it, and the seam
						spec has the case). The loop below then finds `state == true` for those
						same keys and decrements a SECOND time — driving another surface's
						in-flight word to zero while it is still waiting, which is the D3a
						pathology for one word.

						Both shipped adapters return a cancel token that is honoured
						(`screen_target` -> `text_premeasure.measure`, `fake_target` ->
						`forgetBatch`), so nothing in the tree reaches it today. The contract
						declares the token OPTIONAL (`target_contract.luau`: `-> (() -> ())?`),
						so a contract-legal adapter that returns nil, or a cancel the engine
						races, does — and `disposed` is already the flag every other late-answer
						effect in this callback is gated on. Checking it at the TOP is what makes
						the refcount agree with the set. ]]
					if disposed then
						return
					end
					local learned = false
					for _, entry in results do
						if type(entry) ~= "table" then
							continue
						end
						local key = `{entry.font}\0{entry.size}\0{entry.word}`
						--[[ THIS SURFACE ASKED, AND HAS NOT RE-SOLVED SINCE. A word in
							flight is a word THIS surface's last solve could not size, so
							it reserved the estimator's box; the answer is what pays for
							that, whatever any OTHER surface has learned in the meantime.

							THE STORE CANNOT ANSWER IT, and that was the defect. Two hosts
							— two cores, two environments, one process-global
							`layout/text_metrics` — that open cold in the same frame both
							ask for the same words. The first answer teaches the store; the
							second CONFIRMS a width the store already holds, so a
							`previous ~= width` test read `false` and the second surface
							never re-solved, painting the estimator's box for the life of
							the session (`tests/text_premeasure.spec.luau`, "...AND SO DOES
							A SECOND HOST"). `render/text_index`'s broadcast marks that
							surface's paths but a mark is passive: it is spent by the next
							solve, and nothing else was going to make one. ]]
						local state = textInFlight[key]
						local owedHere = state == true
						if final ~= false then
							--[[ ...AND THE REFCOUNT MOVES ONLY WHEN THE SET DOES. A delivery may
								name a key this surface never asked about (an adapter answering a
								batch twice, or answering more than it was asked); the write below
								is a no-op for such a key and the `-1` has to be too, or the
								process count would drift under a set it is supposed to mirror.
								An `"answered"` entry is still in flight and still holds its one:
								the settled re-read is owed, and THAT delivery is the release. ]]
							if state ~= nil then
								textInFlight[key] = nil
								text_metrics.noteInFlight(key, -1)
							end
						elseif owedHere then
							textInFlight[key] = "answered"
						end
						if type(entry.width) == "number" then
							-- an adapter may answer the SAME batch twice (the
							-- Roblox one re-reads once the session has settled and
							-- corrects the boot answer), so a re-solve is owed only
							-- when a width actually moved — or when this surface has
							-- not yet solved on the answer at all
							local previous = text_metrics.measuredWidth(entry.font, entry.size, entry.word)
							if text_metrics.setMeasured(entry.font, entry.size, entry.word, entry.width) then
								if previous ~= entry.width or owedHere then
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
			--[[ ...AND IT GIVES BACK WHAT IT STILL OWED (Plan D, D3a). The flight refcount
				is process-global and this surface's share of it dies here: a cancelled
				batch is never answered, so nothing else would ever decrement these. The
				SET is deliberately left standing — `pending()` reads it, and a disposed
				surface whose words were never answered still answers "yes" (the seam
				spec's own case). Guarded on `disposed` so a second `dispose` cannot
				double-decrement a count another surface is holding. ]]
			if not disposed then
				for key in textInFlight do
					text_metrics.noteInFlight(key, -1)
				end
				--[[ ...AND THE HELD TAIL TOO (RED-TEAM F5). Same argument one structure
					over: nothing else would ever give these back, and a word held for a
					label that will never be measured again is a request that can only ever
					spend a LIVE surface's budget. Inside the `disposed` guard for the same
					reason the refcount is — a second `dispose` must not reach a queue the
					next surface has since refilled. ]]
				text_metrics.forgetOverflow(overflowOwner)
			end
			disposed = true
			for _, cancel in textMeasureCancels do
				cancel()
			end
			table.clear(textMeasureCancels)
		end,
	}
end

return premeasure_round
