--!strict

local Types = require "./types"

export type History = {
	current: () -> Types.Document,
	commit: (Types.Document) -> (),
	undo: () -> boolean,
	redo: () -> boolean,
	canUndo: () -> boolean,
	canRedo: () -> boolean,
}

local LIMIT = 100

return function(initial: Types.Document): History
	local past: { Types.Document } = {}
	local future: { Types.Document } = {}
	local present = initial
	return {
		current = function(): Types.Document
			return present
		end,
		commit = function(nextValue: Types.Document)
			table.insert(past, present)
			if #past > LIMIT then
				table.remove(past, 1)
			end
			table.clear(future)
			present = nextValue
		end,
		undo = function(): boolean
			local previous = table.remove(past)
			if previous == nil then
				return false
			end
			table.insert(future, present)
			present = previous
			return true
		end,
		redo = function(): boolean
			local nextValue = table.remove(future)
			if nextValue == nil then
				return false
			end
			table.insert(past, present)
			present = nextValue
			return true
		end,
		canUndo = function(): boolean
			return #past > 0
		end,
		canRedo = function(): boolean
			return #future > 0
		end,
	}
end
