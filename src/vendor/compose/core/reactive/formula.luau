--!strict
--!native

local Diagnostics = require "../diagnostics"
local Graph = require "./graph"
local NodeCast = require "./node"
local Types = require "./types"
local cellModule = require "./cell"
local clock = require "./clock"
local profile = require "./profile"
local stats = require "./stats"
local statsOn = stats.state
local userSpace = require "./userSpace"
local validationState = userSpace.state

type Node = Types.Node
type Value<T> = Types.Value<T>
type Equals<T> = Types.Equals<T>
type Body<T> = Types.Body<T>

local function requireLive(node: Node)
	if node.released then
		Diagnostics.raise("reactive/disposed-formula", "a disposed formula cannot be read", {
			contract = "formula disposal permanently releases its dependencies",
			fix = "keep reads within the formula lifetime, or create a new formula",
		})
	end
end

local function invoke(node: Node): unknown
	local body = node.body
	return if body then body(Graph.use) else nil
end

local FORMULA = {}
FORMULA.__index = FORMULA

function FORMULA.refresh(self: Node)
	requireLive(self)
	local state = self.state
	if state == Graph.CLEAN then
		return
	end
	if state == Graph.CHECK then
		self.state = Graph.DIRTY
		self.retry = true
		local moved = Graph.dependenciesMoved(self)
		self.retry = false
		if not moved then
			self.state = Graph.CLEAN
			return
		end
	end

	self.state = Graph.CLEAN
	local incoming = Graph.evaluate(self, invoke, self)
	requireLive(self)
	if statsOn.enabled then
		stats.bump "formulaRecomputations"
		profile.recompute(self)
	end

	local equals = self.equals
	local unchanged = if equals == nil and not validationState.validating
		then self.value == incoming
		else userSpace.call(equals or cellModule.defaultEquals, self.value, incoming)
	if unchanged then
		if statsOn.enabled then
			stats.bump "formulaRecomputationsSuppressed"
			profile.suppressedRecompute(self)
		end
		return
	end
	self.value = incoming
	self.version = clock.next()
end

function FORMULA.peek(self: Node): unknown
	FORMULA.refresh(self)
	return self.value
end

local function readOnly(_self: Node): ()
	Diagnostics.raise("reactive/read-only", "a formula cannot be set", {
		contract = "a formula derives its value from what it reads",
		fix = "set a cell the formula reads, or use a cell instead",
	})
end

FORMULA.set = readOnly
FORMULA.update = readOnly

function FORMULA.dispose(self: Node)
	local detach = self.release
	if detach then
		self.release = nil
		detach()
	end
	Graph.release(self)
	self.body = nil
	self.equals = nil
	self.value = nil
end

NodeCast.adopt(FORMULA)

local function settle(self: Node)
	local announced = self.announced
	self.announced = nil
	if self.released or self.first == nil then
		return
	end
	local ok = pcall(FORMULA.refresh, self)
	if not ok or self.version ~= announced then
		Graph.markStale(self, Graph.DIRTY)
	end
end

local function formula<T>(body: Body<T>, equals: Equals<T>?): Value<T>
	local node: Node = {
		version = 0,
		value = nil,
		first = nil,
		state = Graph.DIRTY,
		reads = 0,
		released = false,
		retry = false,
		body = body,
	}
	if equals ~= nil then
		node.equals = NodeCast.eraseEquals(equals)
		node.invalidate = settle
	end
	return NodeCast.make(node, FORMULA)
end

return formula
