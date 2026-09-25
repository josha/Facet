--!strict

local chat = {}

function chat.new(Compose: any)
	local messages = Compose.cell({})
	local draft = Compose.cell("")
	local streaming = Compose.cell(false)
	local active = Compose.cell(nil)
	local feedback = Compose.cell({})
	local completed = Compose.cell(0)

	local streamedChars, totalChars = Compose.cell(0), Compose.cell(0)
	local serial, elapsed, cursor = 0, 0, 0
	local response, activeId = "", nil
	local disposed = false
	local function append(role, content)
		serial += 1
		local id = serial
		messages:update(function(current)
			local nextMessages = table.clone(current)
			table.insert(nextMessages, { id = id, role = role, content = content })
			return nextMessages
		end)
		return id
	end
	local function reply(prompt)
		local lower = string.lower(prompt)
		if string.find(lower, "build", 1, true) or string.find(lower, "code", 1, true) then
			return "Try a small co-op world with one shared goal: restore an abandoned rooftop garden.\n\nPlayers can explore for seeds, build paths, and unlock new areas together. Start with one garden and three plants so the first session feels complete.\n\nWould you like to plan the world or the first few minutes of play?"
		elseif
			string.find(lower, "game", 1, true)
			or string.find(lower, "play", 1, true)
			or string.find(lower, "friend", 1, true)
			or string.find(lower, "co-op", 1, true)
		then
			return "Try Afterlight if you want exploration, Circuit for a quick race, or Terrarium for something slower.\n\nAfterlight has floating islands and short puzzles. Circuit is about finding a faster line. Terrarium lets you build a garden with friends.\n\nAre you playing solo or with a group?"
		end
		return "Let's narrow it down. What are you trying to make, and what's the main thing you want someone to be able to do?\n\nA useful starting point is one clear action, a visible result, and an easy way to go back. We can work through the details from there."
	end
	local function stop()
		activeId = nil
		active:set(nil)
		streaming:set(false)
		streamedChars:set(0)
		totalChars:set(0)
	end
	local function remove(id)
		if id == activeId then
			stop()
		end
		local removed, at
		messages:update(function(current)
			local kept = {}
			for index, message in current do
				if message.id ~= id then
					table.insert(kept, message)
				else
					removed, at = message, index
				end
			end
			return kept
		end)
		return removed, at
	end
	local function restore(message, index)
		messages:update(function(current)
			for _, item in current do
				if item.id == message.id then
					return current
				end
			end
			local nextMessages = table.clone(current)
			table.insert(nextMessages, math.clamp(index, 1, #nextMessages + 1), message)
			return nextMessages
		end)
	end
	local function clear()
		stop()
		messages:set({})
	end
	local function send()
		if disposed or streaming:peek() then
			return false
		end
		local prompt = draft:peek():match("^%s*(.-)%s*$")
		if prompt == "" then
			return false
		end
		do
			append("user", prompt)
			response = reply(prompt)
			activeId = append("assistant", "")
			active:set(activeId)
			draft:set("")
			elapsed, cursor = 0, 0
			totalChars:set(#response)
			streamedChars:set(0)
			streaming:set(true)
		end
		return true
	end
	local function retry(id)
		if disposed then
			return false
		end
		local list, prompt = messages:peek(), nil
		for index, item in list do
			if item.id == id and item.role == "assistant" then
				for back = index - 1, 1, -1 do
					if list[back].role == "user" then
						prompt = list[back].content
						break
					end
				end
				break
			end
		end
		if prompt == nil then
			return false
		end
		stop()
		response = reply(prompt)
		activeId = id
		active:set(id)
		messages:update(function(current)
			local nextMessages = table.clone(current)
			for i, item in nextMessages do
				if item.id == id then
					nextMessages[i] = { id = item.id, role = item.role, content = "" }
				end
			end
			return nextMessages
		end)
		feedback:update(function(current)
			local nextFeedback = table.clone(current)
			nextFeedback[id] = nil
			return nextFeedback
		end)
		elapsed, cursor = 0, 0
		totalChars:set(#response)
		streamedChars:set(0)
		streaming:set(true)
		return true
	end
	local function edit(id)
		local list = messages:peek()
		for index, item in list do
			if item.id == id and item.role == "user" then
				stop()
				draft:set(item.content)
				messages:set(table.move(list, 1, index - 1, 1, {}))
				return true
			end
		end
		return false
	end
	local function rate(id, value)
		feedback:update(function(current)
			local nextFeedback = table.clone(current)
			nextFeedback[id] = if value == "none" or nextFeedback[id] == value then nil else value
			return nextFeedback
		end)
	end
	local function step(dt)
		if disposed or activeId == nil or dt <= 0 then
			return
		end
		elapsed += math.min(dt, 0.1)
		local nextCursor = math.min(#response, math.floor(math.max(0, elapsed - 0.2) * 105))
		if nextCursor == cursor then
			return
		end
		cursor = nextCursor
		streamedChars:set(cursor)
		messages:update(function(current)
			local nextMessages = table.clone(current)
			for i, item in nextMessages do
				if item.id == activeId then
					nextMessages[i] = { id = item.id, role = item.role, content = response:sub(1, cursor) }
					break
				end
			end
			return nextMessages
		end)
		if cursor == #response then
			stop()
			completed:set(completed:peek() + 1)
		end
	end
	return {
		messages = messages,
		draft = draft,
		streaming = streaming,
		active = active,
		feedback = feedback,
		completed = completed,
		restore = restore,
		retry = retry,
		edit = edit,
		rate = rate,
		streamedChars = streamedChars,
		totalChars = totalChars,
		send = send,
		remove = remove,
		clear = clear,
		stop = stop,
		step = step,
		dispose = function()
			disposed = true
			stop()
		end,
	}
end

return chat
