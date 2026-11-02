--!strict
--!native

local Diagnostics = require "../diagnostics"
local Dynamic = require "../dynamic"
local Evaluation = require "./evaluation"
local Graph = require "./graph"
local Nodes = require "./node"
local Types = require "./types"
local cellModule = require "./cell"
local stats = Evaluation.stats
local statsOn = stats.state
local validationState = Evaluation.validation

type Node = Types.Node
type Value<T> = Types.Value<T>
type Equals<T> = Types.Equals<T>
type Body<T> = Types.Body<T>

local CLEAN = Graph.CLEAN
local CHECK = Graph.CHECK
local DIRTY = Graph.DIRTY
local RETRY = Graph.RETRY
local RELEASED = 4
local clockState = Graph.clock
local use: Types.Use = Graph.use
local evaluationCache = Evaluation.cache
local detachers = Nodes.detachers

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
FORMULA.kind = 1
FORMULA.released = false
FORMULA.retry = false

function FORMULA.refresh(self: Node)
	local state = self.state
	if state == RELEASED then
		disposed()
	end
	if state == CLEAN then
		return
	end
	if state == CHECK then
		self.state = RETRY
		local moved = false
		for index = 1, #self do
			local edge = self[index]
			if edge ~= nil then
				local producer = edge[1]
				if producer ~= nil then
					local update = if producer.state ~= CLEAN then producer.refresh else nil
					if update ~= nil then
						update(producer)
					end
					if producer.version ~= edge.version then
						moved = true
						break
					end
				end
			end
		end
		if not moved then
			self.state = if self.state == RELEASED then RELEASED else CLEAN
			return
		end
	end

	self.state = if self.state == RELEASED then RELEASED else CLEAN
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
		ok, incoming = pcall(Evaluation.call, body, use)
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
		self.state = if self.released then RELEASED else RETRY
		error(incoming, 0)
	end
	local reads = self.reads or 0
	if #self > reads then
		Graph.trim(self, reads + 1)
	end
	self.reads = nil
	if self.state == RELEASED then
		disposed()
	end
	if statsOn.enabled then
		stats.bump "formulaRecomputations"
		statsOn.recorder.recompute(self)
	end

	local previousCache = self.cache
	local prior = self.value
	local equals = self.equals
	local unchanged = if equals == nil and not validationState.validating
		then prior == incoming
		else if equals == nil
			then Evaluation.call(cellModule.defaultEquals, prior, incoming)
			else previousCache ~= nil and Evaluation.call(cellModule.compare, equals, prior, incoming)
	if unchanged then
		if previousCache == nil then
			Dynamic.cache(self, incoming)
		end
		if statsOn.enabled then
			stats.bump "formulaRecomputationsSuppressed"
			statsOn.recorder.suppressedRecompute(self)
		end
		return
	end
	self.value = incoming
	if previousCache == nil then
		Dynamic.cache(self, incoming)
	end
	local version = clockState.now + 1
	clockState.now = version
	self.version = version
end

function FORMULA.peek<T>(self: Types.Cache<T>): T
	FORMULA.refresh(self)
	local cached = self.cache
	if cached == nil then
		return Nodes.readCached(self)
	end
	return cached.value
end

local function readOnly(_self: unknown): ()
	return Diagnostics.raise("reactive/read-only", "a formula cannot be set", {
		contract = "a formula derives its value from what it reads",
		fix = "set a cell the formula reads, or use a cell instead",
	})
end

FORMULA.set = readOnly
FORMULA.update = readOnly

Nodes.adopt(FORMULA)

local function dispose(self: Node)
	local detach = detachers[self]
	if detach then
		detachers[self] = nil
		detach()
	end
	self.state = RELEASED
	Graph.release(self)
	self.state = RELEASED
	self.body = nil
	self.cache = nil
	self.value = nil
	self.equals = nil
end

local function cutoff(self: Node)
	local node = self
	if self.released or self.first == nil then
		return
	end
	local before = self.version
	local ok = pcall(FORMULA.refresh, node)
	if not ok or self.version ~= before then
		Graph.markStale(self, Graph.DIRTY)
	end
end

function FORMULA.dispose<T>(self: Value<T>)
	dispose(Nodes.nodeOf(self))
end

local function formula<T>(body: Body<T>, equals: Equals<T>?): Value<T>
	local node: Types.NodeData<T> = {
		version = 0,
		state = DIRTY,
		body = body,
		refresh = FORMULA.refresh,
	}
	if equals ~= nil then
		node.equals = equals
		node.cutoff = cutoff
		node.kind = 2
	end
	return setmetatable(node, FORMULA)
end

return formula
