--!strict
-- Compose owns cells, formulas, watches, direct bindings, batching and scheduling.
-- Facet retains explicit readable disposal, diagnostics and layout settling.
local Compose = require("../vendor/compose")
-- The pinned graph seam supplies explicit formula disposal, absent from the
-- public formula API. Facet keeps no duplicate dependency graph or work queue.
local Graph = require("../vendor/compose/reactive/graph")
local contract = require("./contract")
local profile = require("./profile")
local scope_impl = require("./scope_impl")
local tracking = require("./tracking")
local FEEDBACK_ROUND_CAP = 100
local function equal(a: any, b: any): boolean
	return a == b or (a ~= a and b ~= b)
end
local function noop() end
local factory =
	{ name = "compose", claims = { dynamicDependencies = true, cycleDetection = true, writeDuringMemoError = true } }

function factory.new(opts: { warn: ((string) -> ())? }?): any
	local counts = { signals = 0, memos = 0, observers = 0, effects = 0, scopes = 0, settles = 0 }
	local emitWarn = if opts and opts.warn then opts.warn else warn
	local lastError: string? = nil
	local reactor = Compose.reactor()
	local watches = Compose.createOwner(reactor)
	local evalStack, settles = {}, {}
	local revision, sequence = 0, 0
	local writing, running, depth = 0, 0, 0
	local flushing = false
	local flush: () -> ()
	local function fail(message: string)
		if message ~= lastError then
			emitWarn(`Facet: quarantined - {message}`)
		end
		lastError = message
	end
	local newScope = scope_impl.factory(counts, fail, reactor)
	local function name(node: any): string
		if node.name == nil then
			node.name = `{node.kind}#{node.seq}`
			if node.compute then
				local source, line = debug.info(node.compute, "sl")
				node.name = `{node.kind}@{string.match(source, "[^/]+$") or source}:{line}`
			end
		end
		return node.name
	end
	local function frozen(node: any)
		if node.frozenBy then
			local source = node.frozenBy
			node.frozenBy = nil
			fail(
				`Facet: '{name(node)}' can no longer update — '{source}', which it was subscribed to, was disposed while this node was still live; it will answer this value forever`
			)
		end
	end
	local function checkCycle(node: any)
		if node.evaluating then
			local path = {}
			for _, entry in evalStack do
				table.insert(path, name(entry))
			end
			table.insert(path, name(node))
			error(`Facet cycle: {table.concat(path, " -> ")}`, 0)
		end
	end
	local function use(node: any): any
		node = node._node or node
		if node.disposed then
			return node.value
		end
		checkCycle(node)
		local value = Graph.use(node)
		frozen(node)
		return value
	end
	local function comparison(eq: any): any
		if eq == nil then
			return equal
		end
		return function(a, b)
			local ok, value = pcall(eq, a, b)
			if not ok then
				fail(`Facet: equality callback error quarantined: {tostring(value)}`)
			end
			return ok and value == true
		end
	end
	local function invoke(body: any, tracked: boolean, ...: any): (boolean, any)
		running += 1
		local ok, value = tracking.run(if tracked then use else nil, body, ...)
		running -= 1
		return ok, value
	end
	local function compactSettles()
		local live = 0
		for _, record in settles do
			if not record.disposed then
				live += 1
				settles[live] = record
			end
		end
		for i = #settles, live + 1, -1 do
			settles[i] = nil
		end
	end
	flush = function()
		if flushing or writing > 0 or running > 0 or depth > 0 then
			return
		end
		flushing = true
		local ok, err = pcall(profile.span, "react", function()
			reactor:settle()
			local passes = 0
			local writes = {}
			while #settles > 0 do
				local writer = nil
				for i = 1, #settles do
					local record = settles[i]
					if not record.disposed and not record.quarantined then
						local before = revision
						local success, failure = pcall(reactor.batch, reactor, record.fn)
						if not success then
							fail(tostring(failure))
						end
						if revision ~= before then
							writer = record
							writes[record] = (writes[record] or 0) + 1
							break
						end
					end
				end
				if writer == nil then
					break
				end
				passes += 1
				if passes >= FEEDBACK_ROUND_CAP then
					if writes[writer] > 1 then
						writer.quarantined = true
					end
					fail(
						`Facet: flush exceeded the {FEEDBACK_ROUND_CAP}-round iteration cap — '{name(writer)}' is QUARANTINED until it is re-registered`
					)
					break
				end
			end
		end)
		flushing = false
		compactSettles()
		if not ok then
			fail(tostring(err))
		end
	end
	local function readable(node: any, kind: string): any
		sequence += 1
		node.kind, node.seq, node.disposed = kind, sequence, false
		node._node = node
		node._read = function(scope)
			return if scope then scope(node) else node:get()
		end
		function node.get(self)
			if self.disposed then
				return self.value
			end
			if self.evaluating then
				local ok, err = pcall(checkCycle, self)
				if not ok then
					fail(tostring(err))
				end
				return self.value
			end
			if self.refresh then
				self:refresh()
			end
			frozen(self)
			return self.value
		end
		function node.dispose(self)
			if self.disposed then
				return
			end
			self.disposed = true
			if self.observers then
				for stop in self.observers do
					stop()
				end
			end
			if kind == "memo" then
				Graph.release(self)
				self.body, self.compute = nil, nil
			end
			local edge = self.subscribers
			while edge do
				local following = edge[Graph.NEXT]
				local consumer = edge[Graph.CONSUMER]
				Graph.detach(edge)
				local at = table.find(consumer.dependencies, edge)
				if at then
					table.remove(consumer.dependencies, at)
				end
				if consumer.kind == "memo" and #consumer.dependencies == 0 then
					consumer.frozenBy = name(self)
				end
				edge = following
			end
			counts[if kind == "signal" then "signals" else "memos"] -= 1
		end
		return node
	end
	local core: any = { name = "compose" }
	function core.signal(_self, initial: any, eq: any): any
		counts.signals += 1
		local node = Compose.cell(
			if type(initial) == "function"
				then function()
					return initial
				end
				else initial,
			comparison(eq)
		)
		node:peek()
		local set = node.set
		readable(node, "signal")
		function node.set(self, value)
			if #evalStack > 0 then
				error("Facet: writing state during memo evaluation is an error", 0)
			end
			if self.disposed then
				return
			end
			local before = self.version
			writing += 1
			local ok, err = pcall(set, self, value)
			writing -= 1
			if self.version ~= before then
				revision += 1
			end
			if not ok then
				fail(tostring(err))
			end
			flush()
		end
		return node
	end
	function core.memo(_self, compute: any, eq: any): any
		counts.memos += 1
		local node: any
		node = Compose.formula(function()
			node.evaluating = true
			table.insert(evalStack, node)
			local ok, value = invoke(compute, true, use)
			table.remove(evalStack)
			node.evaluating = false
			if not ok then
				error(value, 0)
			end
			return value
		end, comparison(eq))
		node.compute = compute
		local refresh = node.refresh
		function node.refresh(self)
			if self.disposed or self.state == Graph.CLEAN then
				return
			end
			local ok, err = pcall(refresh, self)
			if not ok then
				fail(tostring(err))
				if #self.dependencies == 0 then
					self.state = Graph.DIRTY
				end
			end
		end
		return readable(node, "memo")
	end
	function core.observe(_self, source: any, onChange: any): () -> ()
		source = source._node or source
		if source.disposed then
			return noop
		end
		local lastSeen = source:get()
		local ready, disposed = false, false
		local stop = watches.watchStatic(source, function(value)
			if ready and not source.compare(lastSeen, value) then
				lastSeen = value
				local ok, err = invoke(onChange, false, value)
				if not ok then
					fail(tostring(err))
				end
			end
		end)
		ready = true
		counts.observers += 1
		if source.observers == nil then
			source.observers = {}
		end
		local unsubscribe: () -> ()
		unsubscribe = function()
			if disposed then
				return
			end
			disposed = true
			stop()
			source.observers[unsubscribe] = nil
			counts.observers -= 1
		end
		source.observers[unsubscribe] = true
		return unsubscribe
	end
	function core.effect(_self, body: any): () -> ()
		counts.effects += 1
		local disposed = false
		local stop = watches.watch(function()
			local ok, err = invoke(body, true, use)
			if not ok then
				fail(tostring(err))
			end
		end)
		flush()
		return function()
			if disposed then
				return
			end
			disposed = true
			stop()
			counts.effects -= 1
		end
	end
	function core.settle(_self, run: any): () -> ()
		counts.settles += 1
		local record = { fn = run, compute = run, kind = "settle", disposed = false }
		table.insert(settles, record)
		return function()
			if record.disposed then
				return
			end
			record.disposed = true
			counts.settles -= 1
			if not flushing then
				compactSettles()
			end
		end
	end
	function core.transaction(_self, body: any)
		depth += 1
		local ok, err = pcall(profile.span, "mutate", function()
			reactor:batch(body)
		end)
		depth -= 1
		flush()
		if not ok then
			error(err, 0)
		end
	end
	function core.flush(_self)
		flush()
	end
	function core.scope(_self, label: string?): any
		return newScope(label)
	end
	function core.counters(_self)
		return table.clone(counts)
	end
	function core.lastError(_self)
		return lastError
	end
	return core
end

return factory :: contract.CoreFactory
