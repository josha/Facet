--!strict

local Block = require "../runtime/block"
local Children = require "../runtime/children"
local Host = require "../host"
local Support = require "./support"

export type Builder = () -> { Host.Node }

local function fragment(builder: Builder): Children.Directive
	local build = Support.builderOf(builder, "fragment", "builder") :: Builder
	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "fragment"
		Support.mountPointOf(mountPoint, "fragment")
		Block.mountBlock(mountPoint, owner, build, Block.nameOf(build), 1)
	end
end

return fragment
