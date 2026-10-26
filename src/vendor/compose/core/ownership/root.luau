--!strict

local Owner = require "./owner"

local root = Owner.createOwner()

local function hold(dispose: () -> ()): () -> ()
	return Owner.own(root, dispose)
end

local function size(): number
	return Owner.size(root)
end

local function disposeAll()
	Owner.dispose(root)
	root = Owner.createOwner()
end

return {
	hold = hold,
	size = size,
	disposeAll = disposeAll,
}
