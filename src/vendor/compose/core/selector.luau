--!strict

local Active = require "./ownership/active"
local Owner = require "./ownership/owner"
local Diagnostics = require "./diagnostics"
local Graph = require "./reactive/graph"
local NodeCast = require "./reactive/node"
local Types = require "./reactive/types"
local clock = require "./reactive/clock"

local makeProjection: (Types.Node, {}) -> Types.Value<boolean> = NodeCast.make

local PROJECTION = {}
PROJECTION.__index = PROJECTION

function PROJECTION.peek(node: Types.Node): unknown
	local refresh = node.refresh
	if refresh ~= nil then
		refresh(node)
	end
	return node.value
end

NodeCast.adopt(PROJECTION)

local function selector<K>(source: Types.ReadOnlyValue<K>): (K) -> Types.ReadOnlyValue<boolean>
	local owner = Active.current()
	if owner == nil then
		return Diagnostics.raise("selector/no-active-owner", "selector ran with no owner to hold it", {
			contract = "a selector and its projections live exactly as long as their creating owner",
			fix = "create the selector inside a component or Compose.withOwner(owner, ...)",
		})
	end
	local router: Types.Node = { state = Graph.DIRTY, reads = 0, retry = false, released = false }
	local readable: Types.ReadOnlyValue<K>? = source
	local projections: { [K]: Types.Node } = {}
	local nilProjection: Types.Node? = nil
	local current: K? = nil
	local failure: unknown = nil
	local failed = false
	local function requireLive()
		if router.released then
			Diagnostics.raise("reactive/disposed-selector", "a disposed selector cannot be read", {
				contract = "selector disposal permanently releases its source and projections",
				fix = "keep reads within the selector owner's lifetime",
			})
		end
	end
	local function projectionOf(key: K?): Types.Node?
		return if key == nil then nilProjection else projections[key]
	end
	local function publish(node: Types.Node?, value: boolean)
		if node ~= nil and node.value ~= value then
			node.value = value
			node.version = clock.next()
			Graph.markStale(node, Graph.DIRTY)
		end
	end
	local function update()
		requireLive()
		if router.state == Graph.CLEAN then
			return
		end
		router.state = Graph.CLEAN
		local ok, incoming = pcall(function(): K
			return Graph.evaluate(router, function(use: Types.Use): K
				return use(assert(readable))
			end, Graph.use)
		end)
		if not ok then
			failure, failed = incoming, true
			router.state = Graph.CLEAN
			router.retry = true
			for _, node in projections do
				Graph.markStale(node, Graph.DIRTY)
			end
			if nilProjection then
				Graph.markStale(nilProjection, Graph.DIRTY)
			end
			return
		end
		local recovering = failed
		if router.released then
			return
		end
		failure, failed = nil, false
		local previous = current
		current = incoming
		publish(projectionOf(previous), rawequal(previous, current))
		publish(projectionOf(current), true)
		if recovering then
			for _, node in projections do
				Graph.markStale(node, Graph.DIRTY)
			end
			if nilProjection then
				Graph.markStale(nilProjection, Graph.DIRTY)
			end
		end
	end
	router.invalidate = update
	local release = Owner.own(owner, function()
		Graph.release(router)
		table.clear(projections)
		readable = nil
		nilProjection = nil
		current = nil
		failure = nil
	end)
	local function refreshProjection(_node: Types.Node)
		update()
		if failed then
			error(failure, 0)
		end
	end
	update()
	if failed then
		local initialFailure = failure
		release()
		error(initialFailure, 0)
	end
	return function(key: K): Types.ReadOnlyValue<boolean>
		requireLive()
		local existing = projectionOf(key)
		if existing ~= nil then
			local value = makeProjection(existing, PROJECTION)
			return value
		end
		local node: Types.Node = { version = clock.next(), value = rawequal(current, key), refresh = refreshProjection }
		local value = makeProjection(node, PROJECTION)
		if key == nil then
			nilProjection = node
		else
			projections[key] = node
		end
		return value
	end
end

return selector
