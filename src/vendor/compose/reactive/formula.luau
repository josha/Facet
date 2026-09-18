--!strict
--!native

local Graph = require "./graph"
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

local FORMULA = {}
FORMULA.__index = FORMULA
FORMULA.__isComposeReadable = true
FORMULA.derived = true

FORMULA.compare = false :: any

local validationState = userSpace.state

function FORMULA.refresh(self: any)
	local state = self.state
	if state == Graph.CLEAN then
		return
	end

	if state == Graph.CHECK then
		if not Graph.dependenciesMoved(self) then
			self.state = Graph.CLEAN
			return
		end
		self.state = Graph.DIRTY
	end

	self.state = Graph.CLEAN
	local incoming = Graph.evaluate(self, FORMULA.invoke, self)
	if statsOn.enabled then
		stats.bump "formulaRecomputations"
		profile.recompute(self)
	end

	local compare = self.compare
	local unchanged = if not compare and not validationState.validating
		then self.value == incoming
		else userSpace.call(compare or cellModule.defaultEquals, self.value, incoming)
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

function FORMULA.invoke(self: any): any
	return self.body(Graph.use)
end

function FORMULA.peek(self: any): any
	FORMULA.refresh(self)
	return self.value
end

local function formula<T>(body: Body<T>, equals: Equals<T>?): Formula<T>
	local self: any = setmetatable({
		version = 0,
		subscribers = false :: any,
		lastSubscriber = false :: any,
		state = Graph.DIRTY,
		dependencies = {},
		reads = 0,
		value = false :: any,
		body = body,
	}, FORMULA)
	self.subscribers = nil
	self.lastSubscriber = nil
	self.value = nil
	if equals ~= nil then
		self.compare = equals
	end
	return (self :: any) :: Formula<T>
end

return formula
