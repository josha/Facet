--!strict

local Block = require "../runtime/block"
local Children = require "../runtime/children"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Support = require "../structure/support"
local cellModule = require "../reactive/cell"

export type Builder = () -> Host.Node

export type Fallback = (failure: unknown, retry: () -> ()) -> Host.Node

local function boundary(builder: Builder, fallback: Fallback): Children.Directive
	if type(builder) ~= "function" or type(fallback) ~= "function" then
		Diagnostics.raise("async/boundary-needs-builders", "boundary expects a builder and a fallback", {
			expected = "boundary(function() ... end, function(failure, retry) ... end)",
		})
	end

	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "boundary"
		local failure = cellModule.cell(nil :: unknown)
		local attempt = cellModule.cell(1)

		local current: Block.Block? = nil

		local reported = false

		local function report(reason: unknown)
			if reported then
				return
			end
			reported = true
			failure:set(if reason ~= nil then reason else "unknown failure")
		end

		local function retry()
			reported = false
			failure:set(nil)
			attempt:update(function(previous: number): number
				return previous + 1
			end)
		end

		owner.watch(function(use)
			local reason = use(failure)

			use(attempt)

			local previous = current
			current = nil
			if previous ~= nil then
				previous.dispose()
			end

			if reason == nil then
				reported = false
				local child = owner.createChild()
				child.guardWith { report = report }

				local ok, blockOrError: any = pcall(Block.mountBlock, mountPoint, child, function(): { Host.Node }
					return { builder() }
				end, Block.nameOf(builder), 1)
				if ok then
					current = blockOrError :: Block.Block
				else
					child.dispose()
					report(blockOrError)
				end
				return
			end

			current = Block.mountBlock(mountPoint, owner, function(): { Host.Node }
				return { fallback(reason, retry) }
			end, Block.nameOf(fallback), 1)
		end)
	end
end

return boundary
