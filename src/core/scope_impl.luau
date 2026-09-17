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
--     false in both directions: measured, it fires for a
--     scope with ZERO owners, which is exactly what the `double-dispose-detected`
--     conformance check asserts, and it does NOT fire for a scope literally owned
--     by two parents. That mattered because this header is deliberately the single
--     home of the wording, so reconciling code to it would have deleted a detector
--     two conformance checks depend on.
--   * CLEANUP ERROR — an owned cleanup THREW. The walk continues (quarantined):
--     one bad cleanup must not skip its siblings, leak the scope
--     counter, or retain released ownership entries.
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
		return setmetatable({ label = label, disposed = false }, Scope)
	end

	-- Ordered entries preserve reverse cleanup order without scanning or shifting
	-- siblings when a child retires. Storage follows live ownership, not churn.
	local function append(owner: any, resource: any): any
		local entry = { owner = owner, resource = resource, previous = owner.last }
		if owner.last ~= nil then
			owner.last.next = entry
		end
		owner.last = entry
		return entry
	end

	local function unlink(entry: any)
		local owner = entry.owner
		if owner == nil then
			return -- the parent's walk already removed this entry
		end
		if entry.previous ~= nil then
			entry.previous.next = entry.next
		end
		if entry.next ~= nil then
			entry.next.previous = entry.previous
		else
			owner.last = entry.previous
		end
		entry.owner = nil
		entry.resource = nil
		entry.previous = nil
		entry.next = nil
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
		append(self, resource)
		return resource
	end

	function Scope.use(self: any, resource: any): any
		-- borrowed: never disposed by this scope
		return resource
	end

	function Scope.child(self: any, label: string?): any
		-- same boundary `own` enforces: a child born into a
		-- disposed scope would never be cleaned up by anyone
		assert(not self.disposed, "cannot create a child of a disposed scope")
		local child = newScope(label)
		child.parentEntry = append(self, child)
		return child
	end

	function Scope.dispose(self: any)
		if self.disposed then
			note(`Facet: double disposal of scope '{self.label or "?"}' detected`)
			return
		end
		self.disposed = true
		if self.parentEntry ~= nil then
			unlink(self.parentEntry)
			self.parentEntry = nil
		end
		while self.last ~= nil do
			local entry = self.last
			local resource = entry.resource
			-- Pop before calling user code, then read the current tail again:
			-- a cleanup can dispose another child and unlink it during this walk.
			unlink(entry)
			-- QUARANTINED: a throwing cleanup must not abort the
			-- walk (its siblings still release) or leak the scope counter.
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
		counts.scopes -= 1
	end

	function Scope.isDisposed(self: any): boolean
		return self.disposed
	end

	return newScope
end

return scope_impl
