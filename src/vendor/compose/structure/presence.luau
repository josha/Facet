--!strict

local Active = require "../ownership/active"
local Block = require "../runtime/block"
local Children = require "../runtime/children"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Support = require "./support"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"

export type Phase = {
	exiting: Types.Readable<boolean>,
}

export type Builder = (phase: Phase) -> Host.Node | { Host.Node }

export type Exiting = {
	completed: Types.Readable<boolean>,
}

export type Options = {
	exit: (nodes: { Host.Node }) -> Exiting,
}

local KNOWN_FIELDS: { [string]: true } = { exit = true }

local function presence(condition: Types.Body<unknown>, builder: Builder, options: Options?): Children.Directive
	local exit: any = nil
	if options ~= nil then
		local settings = Support.optionsOf(options, "presence", "exit = ...")
		Support.noUnknownFields(settings, "presence", KNOWN_FIELDS)
		if settings.exit ~= nil then
			exit = Support.builderOf(settings.exit, "presence", "exit")
		end
	end
	local when = Support.sourceOf(condition, "presence", "condition") :: Types.Body<unknown>
	local build = Support.builderOf(builder, "presence", "builder") :: Builder

	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "presence"
		Support.mountPointOf(mountPoint, "presence")
		local exiting = cellModule.cell(false)
		local phase: Phase = { exiting = exiting }
		local current: Block.Block? = nil
		local shown: boolean? = nil
		local leaving: Block.Block? = nil
		local stopWatchingExit: (() -> ())? = nil

		local function forgetExit()
			local stop = stopWatchingExit
			if stop ~= nil then
				stopWatchingExit = nil
				stop()
			end
		end

		owner.own(function()
			forgetExit()
			local departing = leaving
			leaving = nil
			if departing ~= nil then
				departing.dispose()
			end
		end)

		owner.watch(function(use)
			local truthy = not not when(use)
			if truthy == shown then
				return
			end
			shown = truthy

			if truthy then
				forgetExit()
				exiting:set(false)
				local reclaimed = leaving
				if reclaimed ~= nil then
					leaving = nil
					current = reclaimed
					return
				end
				current = Block.mountBlock(mountPoint, owner, function(): { Host.Node }
					local produced: any = build(phase)
					if type(produced) == "table" and produced[1] ~= nil then
						return produced :: { Host.Node }
					end
					return { produced :: Host.Node }
				end, Block.nameOf(build), 1)
				return
			end

			local departing = current
			current = nil
			if departing == nil then
				return
			end
			if exit == nil then
				departing.dispose()
				return
			end

			leaving = departing
			exiting:set(true)
			local ok, running: any = pcall(Active.withOwner, owner, function()
				return exit(departing.nodes)
			end)
			if not ok then
				leaving = nil
				departing.dispose()
				Diagnostics.raise("structure/exit-failed", "a presence exit raised instead of returning", {
					detail = tostring(running),
					contract = "exit starts the departure and returns something with a completed readable",
					fix = "return a timeline, or omit exit to dispose immediately",
				})
				return
			end
			if type(running) ~= "table" or running.completed == nil then
				leaving = nil
				departing.dispose()
				Diagnostics.raise("structure/exit-not-completable", "a presence exit returned nothing that completes", {
					actual = Diagnostics.describe(running),
					expected = "a table with a `completed` readable, such as a timeline",
				})
				return
			end

			stopWatchingExit = owner.watch(function(watchUse)
				if not watchUse((running :: Exiting).completed) then
					return
				end
				local finished = leaving
				if finished == nil then
					return
				end
				leaving = nil
				forgetExit()
				finished.dispose()
			end)
		end)
	end
end

return presence
