--!strict

local document = require("./document")

local history = {}

function history.new(initial: document.Document): any
	local current = document.copy(document.validate(initial))
	local selected = current.root.id
	local past, future = {}, {}
	local function snapshot()
		return { document = document.copy(current), selected = selected }
	end
	local function restore(value)
		current, selected = value.document, value.selected
	end
	return {
		current = function()
			return document.copy(current), selected
		end,
		select = function(id)
			assert(document.find(current.root, id))
			selected = id
		end,
		commit = function(nextValue, nextSelected)
			document.validate(nextValue)
			assert(document.find(nextValue.root, nextSelected or selected), "Selection does not exist")
			table.insert(past, snapshot())
			if #past > 100 then
				table.remove(past, 1)
			end
			future = {}
			current, selected = document.copy(nextValue), nextSelected or selected
		end,
		undo = function()
			if #past == 0 then
				return false
			end
			table.insert(future, snapshot())
			restore(assert(table.remove(past)))
			return true
		end,
		redo = function()
			if #future == 0 then
				return false
			end
			table.insert(past, snapshot())
			restore(assert(table.remove(future)))
			return true
		end,
		canUndo = function()
			return #past > 0
		end,
		canRedo = function()
			return #future > 0
		end,
	}
end

return history
