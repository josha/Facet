--!strict

local Owner = require "./owner"

local root = Owner.createOwner()

local function hold(dispose: () -> ()): () -> ()
	return root.own(dispose)
end

local function size(): number
	return root.size()
end

local function disposeAll()
	root.dispose()
	root = Owner.createOwner()
end

return {
	hold = hold,
	size = size,
	disposeAll = disposeAll,
}
