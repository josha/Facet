--!strict
local Types = require("./types")
local chain = require("./scroll_chain")
local scrollLock = {}

type Hold = { count: number, saved: boolean, watch: RBXScriptConnection }

local holds: { [ScrollingFrame]: Hold } = setmetatable({}, { __mode = "k" })
local owned: { [ScrollingFrame]: boolean } = setmetatable({}, { __mode = "k" })

local function take(frame: ScrollingFrame)
	local current = holds[frame]
	if current then
		current.count += 1
		return
	end
	local created: Hold = {
		count = 1,
		saved = frame.ScrollingEnabled,
		watch = frame:GetPropertyChangedSignal("ScrollingEnabled"):Connect(function()
			local held = holds[frame]
			if held and frame.ScrollingEnabled then
				held.saved = true
				frame.ScrollingEnabled = false
			end
		end),
	}
	holds[frame] = created
	if created.saved then
		frame.ScrollingEnabled = false
	end
end

local function give(frame: ScrollingFrame)
	local current = holds[frame]
	if current == nil then
		return
	end
	current.count -= 1
	if current.count == 0 then
		holds[frame] = nil
		current.watch:Disconnect()
		if frame.ScrollingEnabled ~= current.saved then
			frame.ScrollingEnabled = current.saved
		end
	end
end

function scrollLock.own(frame: ScrollingFrame, ctx: Types.Context?)
	owned[frame] = true
	if ctx then
		chain(ctx, frame, function(candidate: ScrollingFrame): boolean
			return owned[candidate] == true
		end, function(exhausted: ScrollingFrame): () -> ()
			take(exhausted)
			return function()
				give(exhausted)
			end
		end)
	end
end

local function holdAncestors(node: Instance, ownedOnly: boolean): () -> ()
	local held: { ScrollingFrame } = {}
	local at = node.Parent
	while at do
		if at:IsA("ScrollingFrame") and (not ownedOnly or owned[at]) then
			take(at)
			table.insert(held, at)
		end
		at = at.Parent
	end
	return function()
		for _, frame in held do
			give(frame)
		end
		table.clear(held)
	end
end

function scrollLock.holdOwnedAncestors(node: Instance): () -> ()
	return holdAncestors(node, true)
end

function scrollLock.holdAncestors(node: Instance): () -> ()
	return holdAncestors(node, false)
end

return scrollLock
