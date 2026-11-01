--!strict

local Children = require "../runtime/children"
local Block = Children.block
local Host = require "../host"
local Support = require "./support"

export type Builder = () -> { read [number]: Host.Node }

local function fragment(builder: Builder): Children.Directive
	local build: Builder = Support.builderOf(builder, "fragment", "builder")
	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "fragment"
		Support.mountPointOf(mountPoint, "fragment")
		Block.mountBlock(mountPoint, owner, build, Block.nameOf(build), 1)
	end
end

return fragment
