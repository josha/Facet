--!strict
--[[ row_actions_coordinator — at most ONE row open per shared list surface.

	WHAT THIS IS. `Facet.newRowActionsCoordinator`, whole. It is a registry of
	exactly one thing — the currently-open row's own API table — behind three
	closures, and it shares nothing with the row engine it coordinates: it calls
	`_close()`/`_closeMenu()` on rows through their PUBLIC handle and never reads
	a single one of `buildEngine`'s upvalues.

	PUBLIC INTERFACE: `new(core) -> { claim, release, bindScroll }`.
	`row_actions.luau` re-exports it as `row_actions.newCoordinator`, which
	`src/init.luau` publishes as `newRowActionsCoordinator` — the export shape is
	unchanged, byte for byte.

	DEPENDS ON: nothing. No require at all.

	WHY IT IS ITS OWN FILE (2026-08-14). A PUBLIC export living inside another
	module's private body is the clearest seam there was, and `row_actions.luau`
	had to shed periphery to get back under the 200,000-char `Script.Source`
	WRITE cap that Rojo live-sync assigns through
	(docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md,
	tools/check_source_size.py). ]]

local row_actions_coordinator = {}

-- PUBLIC API (`Facet.newRowActionsCoordinator`, director decision
-- 2026-08-09): at most one row open per shared list surface. A VStack/
-- ScrollView list builds its own and passes it to every wrapped row's
-- `coordinator` spec key; Table (Task 10) does the identical wiring for its
-- own `rowActions` rows automatically. Standalone `newRowActions` use with no
-- coordinator stays valid — every claim/release call in `buildEngine`
-- (row_actions.luau) is already guarded on `coordinator ~= nil`, so an instance
-- with none only ever manages itself, byte-identical to Tasks 3-6.
--
-- IDENTITY. The row instance IS its own handle here — the exact table
-- `buildEngine` (row_actions.luau) returns (`api` in that function, the same
-- object a caller already holds) — never a second wrapper/id scheme
-- `claim`/`release` would have to keep in sync with the real one.
--
-- `core` is accepted (not `_core`) for the same construction signature every
-- other `new*` factory in this module family uses, though nothing here reads
-- it today: the registry is three closures over one plain local, not
-- reactive state — there is nothing here a caller could usefully `core:observe`.
function row_actions_coordinator.new(core: any): any
	local claimed: any = nil -- the currently-open row instance's own API table, or nil

	-- called from a row (see `open`/`onPointerMove`'s axis-lock crossing in
	-- `buildEngine`, row_actions.luau): closes whatever OTHER row is currently
	-- claimed via ITS OWN `_close` — spring-animated, or an instant snap under reduced
	-- motion / no bound motion clock, `close`'s existing behavior, entirely
	-- unchanged by going through the coordinator — then claims `instance`.
	-- Re-claiming the row that is already claimed is a harmless no-op past the
	-- identity check.
	--
	-- REDTEAM FIX (item 7, MAJOR, cross-row half): `_close()` alone only
	-- ever closed the claimed-away row's TRAY. Its MENU (independent state
	-- — `buildEngine` (row_actions.luau)'s own comment above `local menuOpen`) is a
	-- SEPARATE popup that a row can have open with no tray revealed at all,
	-- so a sibling row beginning a horizontal gesture (claiming here) used
	-- to leave the previously-open row's menu — and its `transientScope`
	-- focus trap — stranded, armed on a row the player was no longer
	-- looking at. `_closeMenu()` runs unconditionally alongside `_close()`
	-- for the identical reason: idempotent (a no-op via `menuOpen:set(false)`
	-- on a row whose menu was never open), so this never has to ask first.
	local function claim(instance: any)
		if claimed ~= nil and claimed ~= instance then
			-- captured BEFORE calling `_close()`: `close()` itself calls
			-- `coordinator.release(api)` (row_actions.build), which mutates
			-- THIS SAME `claimed` upvalue back to `nil` as a side effect —
			-- reading `claimed` again afterward would already be nil.
			local previous = claimed
			previous._close()
			previous._closeMenu()
		end
		claimed = instance
	end

	-- called from a row's own `close()`/`dispose()`. Idempotent BY DESIGN: a
	-- row that was never claimed (it settled back to closed without ever
	-- crossing the axis lock, say) releases unconditionally on every close and
	-- on dispose without first checking whether it actually holds the claim.
	local function release(instance: any)
		if claimed == instance then
			claimed = nil
		end
	end

	-- ANY scroll movement closes the open row — no distance/velocity
	-- threshold, matching iOS. A thin pass-through onto
	-- `controller.observeScroll` (table.luau:2178's own native-scroll-mirror
	-- call, the shipped precedent for a control binding this after present());
	-- returns the same unsubscribe `observeScroll` itself returns, so the
	-- consumer that called `bindScroll` owns tearing it down (present-time
	-- wiring, same shape as `Table.bindNativeScroll`).
	local function bindScroll(controller: any, path: string): () -> ()
		return controller.observeScroll(path, function()
			if claimed ~= nil then
				claimed._close()
			end
		end)
	end

	return {
		claim = claim,
		release = release,
		bindScroll = bindScroll,
	}
end

return row_actions_coordinator
