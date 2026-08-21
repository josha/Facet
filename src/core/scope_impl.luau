--!strict
-- Shared contract-Scope implementation (design §6.3) used by all core
-- candidates: explicit ownership (own/use/child), reverse-order idempotent
-- disposal, live scope counting. Owned resources may be functions (called on
-- dispose), tables with :dispose(), or child scopes.

local scope_impl = {}

-- `report` (optional): the core's diagnostic channel — whatever it does with a
-- `core:lastError()` string. Called for the two conditions this module detects:
--
--   * DOUBLE DISPOSAL — dispose() ran on an already-disposed scope. §6.3 requires
--     it detected while staying idempotent (no double-free). It fires when CODE
--     calls dispose() directly on an already-disposed handle — including a scope
--     with no owners at all. The parent's reverse walk instead skips an
--     already-disposed child SILENTLY, because a child disposed early (a retired
--     row, a completed exit) is ordinary ownership rather than the bug.
--     Verified 2026-07-28 by a fresh-context review.
--
--     The previous wording here — "fires only for a scope with TWO owners" — was
--     false in both directions : measured, it fires for a
--     scope with ZERO owners, which is exactly what the `double-dispose-detected`
--     conformance check asserts, and it does NOT fire for a scope literally owned
--     by two parents. That mattered because this header is deliberately the single
--     home of the wording, so reconciling code to it would have deleted a detector
--     two conformance checks depend on.
--   * CLEANUP ERROR — an owned cleanup THREW. The walk continues (quarantined):
--     one bad cleanup must not skip its siblings, leak the scope
--     counter, or strand the disposing flag.
--
-- THE WORDING LIVES HERE, with the semantics it describes (Step 5.5 cleanup
-- ledger C-07). All three core candidates used to format these two strings
-- themselves, identically, from two callbacks — three chances for the diagnostic
-- to drift away from the rule that produced it.
function scope_impl.factory(counts: { scopes: number } & { [string]: number }, report: ((string) -> ())?)
	local Scope = {}
	Scope.__index = Scope

	local function note(message: string)
		if report ~= nil then
			report(message)
		end
	end

	local function newScope(label: string?): any
		counts.scopes += 1
		return setmetatable({ label = label, owned = {}, disposed = false, parent = nil }, Scope)
	end

	-- OWNERSHIP MEANS RELEASABILITY (F-13). `own` used to insert whatever it was
	-- handed, and the dispose walk below falls through anything it cannot
	-- release — so `scope:own(thing)` over a table with no `dispose` read as
	-- correct, reviewed as correct, and did nothing at all. That is the
	-- accepted-but-ignored class, and it shipped inside the framework's own
	-- gallery scenario. Diagnosed HERE, at the call site where the mistake is,
	-- rather than never: a function, a child scope, and an object with a
	-- `dispose()` are the three things a scope can actually release. Non-tables
	-- other than functions (an engine connection, say) are unchanged — this
	-- module cannot rule on what it cannot inspect. Borrowing is still free:
	-- `scope:use(anything)` says "not mine to release" and always did.
	function Scope.own(self: any, resource: any): any
		assert(not self.disposed, "cannot own into a disposed scope")
		-- the same reads the dispose walk performs, so the two can never disagree
		-- about what is releasable (an inherited `dispose` off a class metatable
		-- counts for both)
		if type(resource) == "table" and getmetatable(resource) ~= Scope and (resource :: any).dispose == nil then
			local kind = (resource :: any).kind
			local named = if type(kind) == "string" then ` (kind '{kind}')` else ""
			error(
				`Facet scope: own() on scope '{self.label or "?"}' was handed a table with no dispose(){named} — a scope releases functions, child scopes, and objects with a dispose(). Own its release/unsubscribe FUNCTION instead, or do not own it (use scope:use() to borrow).`,
				0
			)
		end
		table.insert(self.owned, resource)
		return resource
	end

	function Scope.use(self: any, resource: any): any
		-- borrowed: never disposed by this scope
		return resource
	end

	function Scope.child(self: any, label: string?): any
		-- same boundary `own` enforces (verifier RR-6): a child born into a
		-- disposed scope would never be cleaned up by anyone
		assert(not self.disposed, "cannot create a child of a disposed scope")
		local child = newScope(label)
		child.parent = self
		table.insert(self.owned, child)
		return child
	end

	function Scope.dispose(self: any)
		if self.disposed then
			note(`Facet: double disposal of scope '{self.label or "?"}' detected`)
			return
		end
		self.disposed = true
		self.disposing = true
		for i = #self.owned, 1, -1 do
			local resource = self.owned[i]
			-- QUARANTINED (verifier RR-4): a throwing cleanup must not abort the
			-- walk (its siblings still release), must not leak the scope counter,
			-- and must not strand `disposing` — which would silently re-open the
			-- unbounded-owned-growth hole and make the NEXT dispose a false
			-- double-disposal report
			local ok, err = pcall(function()
				if type(resource) == "function" then
					resource()
				elseif type(resource) == "table" then
					if getmetatable(resource) == Scope then
						-- a child disposed EARLY (a retired row, a completed exit) is
						-- normal ownership, not the double-dispose bug the detector
						-- exists for — that bug is CODE calling dispose() twice on
						-- the same handle, which still trips the branch above
						if not resource.disposed then
							resource:dispose()
						end
					elseif resource.dispose ~= nil then
						resource:dispose()
					end
				end
			end)
			if not ok then
				note(`Facet: scope cleanup error in '{self.label or "?"}': {tostring(err)}`)
			end
		end
		self.owned = {}
		self.disposing = nil
		counts.scopes -= 1
		-- deregister from the parent so a long-lived scope with churning children
		-- (a ForEach under live re-sorts) does not grow its owned list without
		-- bound; skipped while the PARENT is mid-walk (it clears owned itself)
		local parent = self.parent
		self.parent = nil
		if parent ~= nil and not parent.disposed and parent.disposing ~= true then
			local index = table.find(parent.owned, self)
			if index ~= nil then
				table.remove(parent.owned, index)
			end
		end
	end

	function Scope.isDisposed(self: any): boolean
		return self.disposed
	end

	return newScope
end

return scope_impl
