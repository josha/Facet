--!strict

local Children = require "../runtime/children"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Owner = require "../ownership/owner"
local Support = require "../structure/support"
local Types = require "../reactive/types"
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
		local initial: unknown = nil
		local failure: Types.Value<unknown> = cellModule.cell(initial)
		local attempt = cellModule.cell(1)

		local current: (() -> ())? = nil

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

		Owner.watch(owner, function(use)
			local reason = use(failure)

			use(attempt)

			local previous = current
			current = nil
			if previous ~= nil then
				previous()
			end

			if reason == nil then
				reported = false
				local child = Owner.createChild(owner)
				Owner.guardWith(child, { report = report })

				local ok, block = pcall(Support.mountBuilder, mountPoint, child, builder, "boundary")
				if ok then
					current = Owner.disposer(child)
				else
					Owner.dispose(child)
					report(block)
				end
				return
			end

			current = Support.mountBuilder(mountPoint, owner, function()
				return fallback(reason, retry)
			end, "boundary")
		end)
	end
end

return boundary
