--!strict
--!native

local Diagnostics = require "../diagnostics"
local Evaluation = require "./evaluation"
local Graph = require "./graph"
local NodeCast = require "./node"
local Types = require "./types"
local cellModule = require "./cell"
local clock = require "./clock"
local stats = require "./stats"
local statsOn = stats.state
local userSpace = require "./userSpace"
local validationState = userSpace.state

type Node = Types.Node
type Value<T> = Types.Value<T>
type Equals<T> = Types.Equals<T>
type Body<T> = Types.Body<T>

local CLEAN = Graph.CLEAN
local CHECK = Graph.CHECK
local DIRTY = Graph.DIRTY
local clockState = clock.state
local use = Graph.use
local evaluationCache = Evaluation.cache
local detachers = NodeCast.detachers

local function disposed(): never
	return Diagnostics.raise("reactive/disposed-formula", "a disposed formula cannot be read", {
		contract = "formula disposal permanently releases its dependencies",
		fix = "keep reads within the formula lifetime, or create a new formula",
	})
end

local function none(_use: Types.Use): unknown
	return nil
end

local FORMULA = {}
FORMULA.__index = FORMULA

function FORMULA.refresh(self: Node)
	if self.released then
		disposed()
	end
	local state = self.state
	if state == CLEAN then
		return
	end
	if state == CHECK then
		self.state = DIRTY
		self.retry = true
		local moved = false
		for index = 1, #self do
			local edge = self[index]
			if edge ~= nil then
				local producer = edge[1]
				if producer ~= nil then
					local update = rawget((producer :: unknown) :: { [string]: unknown }, "refresh") :: ((Node) -> ())?
					if update ~= nil and (producer.state ~= CLEAN or producer.released) then
						update(producer)
					end
					if producer.version ~= edge.version then
						moved = true
						break
					end
				end
			end
		end
		self.retry = false
		if not moved then
			self.state = CLEAN
			return
		end
	end

	self.state = CLEAN
	local body = self.body or none
	local running = coroutine.running()
	local cached = if running == evaluationCache.thread then evaluationCache.frame else nil
	local current: Evaluation.Evaluation = if cached ~= nil then cached else Evaluation.frame()
	local previousConsumer, previousOrder = current.consumer, current.order
	if previousOrder == 0 then
		evaluationCache.active += 1
	end
	local order = evaluationCache.order + 1
	evaluationCache.order = order
	current.consumer = self
	current.order = order
	self.reads = 0
	local ok, incoming
	if validationState.validating then
		ok, incoming = pcall(userSpace.call, body, use)
	else
		ok, incoming = pcall(body, use)
	end
	current.consumer = previousConsumer
	current.order = previousOrder
	if previousOrder == 0 then
		evaluationCache.active -= 1
	end
	evaluationCache.thread = running
	evaluationCache.frame = current
	if not ok then
		self.state = DIRTY
		self.retry = true
		error(incoming, 0)
	end
	local reads = self.reads or 0
	if #self > reads then
		Graph.trim(self, reads + 1)
	end
	if self.released then
		disposed()
	end
	if statsOn.enabled then
		stats.bump "formulaRecomputations"
		statsOn.recorder.recompute(self)
	end

	local equals = rawget((self :: unknown) :: { [string]: unknown }, "equals") :: ((unknown, unknown) -> boolean)?
	local unchanged = if equals == nil and not validationState.validating
		then self.value == incoming
		else userSpace.call(equals or cellModule.defaultEquals, self.value, incoming)
	if unchanged then
		if statsOn.enabled then
			stats.bump "formulaRecomputationsSuppressed"
			statsOn.recorder.suppressedRecompute(self)
		end
		return
	end
	self.value = incoming
	local version = clockState.now + 1
	clockState.now = version
	self.version = version
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
	local detach = detachers[self]
	if detach then
		detachers[self] = nil
		detach()
	end
	Graph.release(self)
	self.body = nil
	self.equals = nil
	self.value = nil
end

NodeCast.adopt(FORMULA)

local function cutoff(self: Node)
	if self.released or self.first == nil then
		return
	end
	local before = self.version
	local ok = pcall(FORMULA.refresh, self)
	if not ok or self.version ~= before then
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
		refresh = FORMULA.refresh,
	}
	if equals ~= nil then
		node.equals = NodeCast.eraseEquals(equals)
		node.cutoff = cutoff
	end
	return NodeCast.make(node, FORMULA)
end

return formula
