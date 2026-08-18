--!strict
--[[ withAnimation — the presenter's headline animation verb, and its two
	diagnostics. Extracted verbatim from src/present/presenter.luau for Studio's
	200,000-character `Source` WRITE cap: over it a module silently stops
	live-syncing into an open session, so a live check against it tests the built
	place rather than the edits on disk
	(docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md).

	THE CAP WAS 519 CHARACTERS AWAY WHEN THIS MOVED. `presenter.luau` stood at
	199,481, having been deliberately left at 179,055 by the 2026-08-14 split with
	the note that "192,454 passes this check and is NOT a margin". It grew back.
	This is the fifth extraction from that file and it is the same recipe.

	WHY THIS IS THE SEAM, and it is the recipe rather than an eye for what looks
	separable. The test is: does the block read or WRITE a mutable upvalue of the
	`presenter.new` closure? Mechanised over the whole file, this block writes
	**zero** — every name it touches from the closure is read-only to it:

	  `core`         the reactive core, by reference
	  `presenter`    the presenter instance (`self`), for `refresh` at CALL time
	  `stack`        the presented handles, a by-reference table declared once at
	                 `presenter.new` and never rebound (only mutated)
	  `motionClock`  declared once from `presenterOpts.clock`, never rebound

	Its own two mutable upvalues — `animationProbeFired` and `inWithAnimation` —
	are declared here and referenced nowhere else in the file, so the state left
	with the code. That is the same score `catchers` and `text_reveal` came out on.

	A PREVIOUS SPLIT JUDGED THIS TOO ENTANGLED and said so in
	`tools/check_source_size.py`: "`withAnimation`, whose animation records and
	`inWithAnimation` re-entrancy flag are read by the commit path". Re-checked
	before moving, because a stale judgement is worth less than a fresh grep: the
	animation RECORDS live in the controllers (`handle.controller.armAnimation` /
	`disarmAnimation` / `animationRecordCount`), not in this file, and
	`inWithAnimation` has exactly two readers, both inside this block. The note was
	describing a coupling that the record-keeping's own move to the render layer
	had already dissolved.

	`new(ctx)` returns the four names `presenter.new` bound before the move, under
	those exact names, so not one call site changed.
]]

local motionClasses = require("../motion/classes")
local motionCurves = require("../motion/curves")

local with_animation = {}

function with_animation.new(ctx: any)
	local core = ctx.core
	local presenter = ctx.presenter
	local stack = ctx.stack
	local motionClock = ctx.motionClock
	local api = {}

	-- ===== withAnimation (docs/plans/swiftui-parity-round2.md §Phase 1) =======
	--
	-- `presenter.withAnimation("container", function() open:set(true) end)` — the
	-- layout lands exactly and instantly as it always did, and every node whose box
	-- MOVED is painted travelling from where it used to be, over one spring.
	--
	-- It is a PRESENTER method rather than a `UI.` modifier or a free function on
	-- `motion`, because it needs all three of the things only the presenter has:
	-- the motion clock it builds, the controller scopes that own the records, and
	-- `refresh` itself. The motion is DECORATIVE — the instant layout already
	-- carries every fact and the travel is pure continuity — which is what makes
	-- "no flight under reduced motion" the right policy rather than information
	-- deletion.
	--
	-- THE NESTING PROBE, built ONCE per presenter and reused. `Core` exposes no
	-- `inTransaction()` and its `txDepth` is private, so the nesting refusal cannot
	-- ask: it writes a scratch signal as the first act inside its own transaction
	-- and reads whether the observer has fired by the time that transaction
	-- returns. Observers fire post-flush, so "fired" means depth was zero.
	local animationProbe = core:signal(0)
	local animationProbeFired = false
	-- session-lifetime, like the presenter itself (it has no dispose); kept on self
	-- so the ownership is visible rather than implicit
	api.probeWatcher = core:observe(animationProbe, function()
		animationProbeFired = true
	end)

	--[[ RE-ENTRANCY, AND WHY IT IS ITS OWN REFUSAL RAISED FIRST (red-team R1,
	2026-08-13). Arming is presenter-wide and the disarm is a plain "off", not a
	counter: a nested call arms the very controllers the OUTER call armed and then
	disarms them on its way out, so by the time the outer call reaches its own
	armed `presenter.refresh()` the session is already gone. Measured before this
	flag: the outer's rect landed exactly (`rect.y` 200) while its paint never
	travelled (`presentedPosition.y` 200 where the flight should have started it
	at 100) and `animationRecordCount()` was 0 — the outer animation silently
	deleted by the inner one. Under a `pcall` around the inner call — which is
	exactly the shape `src/controls/row_actions.luau` uses for `action.onAction`
	— not even the inner refusal is visible, so the whole thing reads as "the
	animation just doesn't work".

	So the check runs BEFORE anything is armed, refreshed or mutated, and carries
	its own message: the old nesting refusal below is about an outer core
	TRANSACTION, which is a different situation with a different fix, and naming
	the wrong cause sent a reader looking for a transaction that does not exist. ]]
	local inWithAnimation = false

	function api.withAnimation(class: any, fn: () -> ())
		if inWithAnimation then
			error(
				"Facet presenter.withAnimation: called from inside another withAnimation call. "
					.. "Arming is presenter-wide and disarming is not counted, so the inner call would "
					.. "disarm the controllers the outer call armed and the OUTER animation would "
					.. "silently not happen (its layout still lands exactly; only the flight is lost). "
					.. "Nesting buys nothing anyway: one call already animates every consequence of "
					.. "everything its `fn` changes, over one spring. Make the change inside the outer "
					.. "`fn` directly. Nothing has been mutated by this call.",
				0
			)
		end
		--[[ ONE DIAL, TWO VOCABULARIES (ADR-0033). An unknown name AND an inline
		params table are both refused by the registries, with their did-you-mean and
		their registered lists. A motion class is a NAME here exactly as it is
		everywhere else in the framework — and so is a motion CURVE.

		WHY A CURVE IS ALLOWED TO DRIVE THIS, decided rather than defaulted. The
		flight is one progress value from 1 (the old place) to 0 (the solved place),
		read through `Readable<number>`; a tween value is that same handle with a
		different driver behind it, so "over exactly 300 ms, quad ease-out" — the
		shape every design handoff actually arrives in — needs no second mechanism.
		The one real difference is the interruption carry: a spring hands its
		velocity to the call that interrupts it, and a curve has no velocity to
		hand (its speed IS its shape), so `carriesVelocity` below turns that seam
		off rather than raising inside a commit. A curve-driven interruption still
		re-bases from the offset on screen, so it redirects without a jump; only the
		speed kinks, which is what a tween is. Refusing curves here would have left
		the framework's headline animation verb unable to speak the vocabulary the
		registry exists to hold — the asymmetry that becomes a defect later. ]]
		local isCurve = type(class) == "string" and motionCurves.isRegistered(class)
		if not isCurve then
			local resolved, err = pcall(motionClasses.resolve, class)
			if not resolved then
				local known = motionCurves.names()
				local also = if #known > 0
					then ` withAnimation also takes a registered motion CURVE name: {table.concat(known, ", ")}.`
					else ` withAnimation also takes a registered motion CURVE name (none registered yet — see motion.registerCurve).`
				error(tostring(err) .. also, 0)
			end
		end
		if type(fn) ~= "function" then
			error(`Facet presenter.withAnimation(class, fn): fn must be a function, got {typeof(fn)}`, 0)
		end
		-- THE UNARMED PRE-DRAIN, and it is load-bearing. `controller.refresh` opens
		-- by draining the WHOLE dirty queue, so without this the armed commit would
		-- also commit everything dirtied since the last frame — and a DISCRETE change
		-- that landed two milliseconds earlier (a network event, a timer, an async
		-- image resizing a label) would animate at its FULL delta. Usually a no-op
		-- solve, because nothing is dirty.
		presenter.refresh()
		-- REDUCED MOTION INSTALLS NO RECORDS AT ALL — an explicit branch, not
		-- "install and clear". Settle fires synchronously inside `setTarget` under
		-- reduced motion, so a clear that arrives after it would leave the node
		-- painted at the full stale offset forever. `fn` still runs, the transaction
		-- still commits, the layout is still exact; there is simply no flight.
		local armed: { any } = {}
		if not motionClock:isReduced() then
			-- one session per CALL. The spring is built lazily by whichever commit
			-- finds a root, so a call that moves nothing costs no motion value.
			local session = {
				newSpring = function()
					return if isCurve then motionClock:tween(1, class) else motionClock:spring(1, class)
				end,
				-- see the vocabulary note above: a curve has no velocity to seed, so
				-- the interruption carry is skipped rather than attempted
				carriesVelocity = not isCurve,
			}
			-- presenter-wide, because `refresh` carries no surface — safe precisely
			-- BECAUSE of the pre-drain: with the queue already empty, another surface
			-- has no pending changes to animate by accident
			for _, handle in stack do
				handle.controller.armAnimation(session)
				table.insert(armed, handle.controller)
			end
		end
		animationProbeFired = false
		inWithAnimation = true
		local ok, err = pcall(function()
			core:transaction(function()
				animationProbe:set(animationProbe:get() + 1)
				fn()
			end)
			-- THE ARMED COMMIT: exactly `fn`'s consequences, and the only commit in
			-- the framework that ever installs records. Skipped on a throw — a
			-- half-applied `fn` is committed by the next ordinary refresh, unarmed.
			presenter.refresh()
		end)
		-- the finally, on every path including a throw: a throwing `fn` must not
		-- latch an animation class on for the rest of the session, and the
		-- re-entrancy flag must not latch either or the presenter refuses forever
		inWithAnimation = false
		for _, ctrl in armed do
			ctrl.disarmAnimation()
		end
		if not ok then
			error(err, 0)
		end
		--[[ THE PROBE DID NOT FIRE, AND IT CANNOT TELL YOU WHY (red-team R2,
		2026-08-13). It fires from an observer, and observers fire post-flush, so
		"did not fire" means only "nothing flushed". TWO different situations
		produce that:

		  · an outer core TRANSACTION is open — `commit` is deferred to its close;
		  · a core COMMIT is in flight — `src/core/imperative.luau`'s `commit`
		    opens `if committing then return end`, so a transaction opened from an
		    observer, effect, memo settle or any handler dispatched DURING a commit
		    never flushes either. Reproduced from a plain `core:observe` handler.

		The probe cannot separate them, so the message names both rather than
		asserting the one that used to be assumed — it named a transaction that,
		in the commit case, is not open at all.

		AND THE HAZARD, because this refusal arrives LATE: `fn` already ran, inside
		the transaction above, so its mutation has landed. A caller that catches
		this (`pcall(action.onAction)` in src/controls/row_actions.luau is exactly
		that shape) sees "no animation" and must NOT retry the mutation — retrying
		applies it twice. ]]
		if not animationProbeFired then
			error(
				"Facet presenter.withAnimation: nothing flushed, so it could not force its own "
					.. "commit and no records were installed — the change landed instantly with no "
					.. "flight. Either an outer core transaction is still open, or this ran during a "
					.. "core commit (from an observer, an effect, or a settle/handler dispatched by "
					.. "one), where a nested transaction cannot flush either. WARNING: `fn` HAS "
					.. "already been applied — do not retry it, or the mutation lands twice. Call "
					.. "presenter.withAnimation(class, fn) from outside the transaction/commit "
					.. "instead, e.g. deferred to the next frame.",
				0
			)
		end
	end

	-- DIAGNOSTICS (design §Proof), not features. `animationRecordCount` is how many
	-- paths currently carry a `withAnimation` record — the proof that recording is
	-- roots-only and that settle cleans the channel; `commitCount` is how many
	-- commits the presented surfaces have made — the proof that each call forces
	-- its own, which a count of animation SETS would not have caught.
	function api.animationRecordCount(): number
		local n = 0
		for _, handle in stack do
			if handle.controller.animationRecordCount ~= nil then
				n += handle.controller.animationRecordCount()
			end
		end
		return n
	end

	function api.commitCount(): number
		local n = 0
		for _, handle in stack do
			if handle.controller.stats ~= nil then
				n += handle.controller.stats().solves
			end
		end
		return n
	end

	return api
end

return with_animation
