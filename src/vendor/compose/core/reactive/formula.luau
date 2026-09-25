--!strict
--!native

local Graph = require "./graph"
local Diagnostics = require "../diagnostics"
local Types = require "./types"
local cellModule = require "./cell"
local clock = require "./clock"
local stats = require "./stats"
local statsOn = stats.state
local profile = require "./profile"
local userSpace = require "./userSpace"

type Formula<T> = Types.Formula<T>
type Equals<T> = Types.Equals<T>
type Body<T> = Types.Body<T>
type Edge = Graph.Edge
type Consumer = Graph.Consumer
type Producer = Graph.Producer

type FormulaNode = {
	version: number,
	subscribers: Edge?,
	lastSubscriber: Edge?,
	refresh: ((Producer) -> ()) | false,
	derived: boolean?,

	state: number,
	dependencies: { Edge },
	reads: number,
	enqueue: ((Consumer) -> ()) | false | nil,
	enqueueSettle: ((Consumer) -> ()) | false | nil,
	released: boolean,
	retry: boolean?,

	value: unknown,
	body: Body<unknown>?,
	compare: Equals<unknown> | false | nil,
}

local FORMULA = {}
FORMULA.__index = FORMULA
FORMULA.__isComposeReadable = true
FORMULA.derived = true

FORMULA.compare = false

local validationState = userSpace.state

local function requireLive(self: FormulaNode)
	if self.released then
		Diagnostics.raise("reactive/disposed-formula", "a disposed formula cannot be read", {
			contract = "formula disposal permanently releases its dependencies",
			fix = "keep reads within the formula lifetime, or create a new formula",
		})
	end
end

function FORMULA.dispose(self: FormulaNode)
	Graph.release(self)
	self.body = nil
	self.compare = nil
	self.value = nil
end

function FORMULA.refresh(producer: Producer)
	local self = producer :: FormulaNode
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
	local incoming = Graph.evaluate(self, FORMULA.invoke, self)
	requireLive(self)
	if statsOn.enabled then
		stats.bump "formulaRecomputations"
		profile.recompute(self)
	end

	local compare = self.compare
	local unchanged = if not compare and not validationState.validating
		then self.value == incoming
		else userSpace.call((compare or cellModule.defaultEquals) :: Equals<unknown>, self.value, incoming)
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

function FORMULA.invoke(self: FormulaNode): unknown
	return (self.body :: Body<unknown>)(Graph.use)
end

function FORMULA.peek(self: FormulaNode): unknown
	FORMULA.refresh(self)
	return self.value
end

local function formula<T>(body: Body<T>, equals: Equals<T>?): Formula<T>
	local self: FormulaNode = setmetatable({
		version = 0,
		subscribers = false,
		lastSubscriber = false,
		state = Graph.DIRTY,
		released = false,
		dependencies = {},
		reads = 0,
		value = false,
		body = body,
	}, FORMULA) :: any
	self.subscribers = nil
	self.lastSubscriber = nil
	self.value = nil
	if equals ~= nil then
		self.compare = equals :: Equals<unknown>
	end
	return (self :: any) :: Formula<T>
end

return formula
