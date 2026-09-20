--!strict

local Children = require "../runtime/children"
local Admission = require "../collection/admission"
local Diagnostics = require "../diagnostics"
local FramePump = require "../collection/frame-pump"
local Host = require "../host"
local Support = require "./support"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"
local keyed = require "./keyed"

export type Status = {
	total: number,
	mounted: number,
	pending: number,
}

export type Options<V, K> = {
	from: keyed.Source<V>,
	key: ((value: V, index: number) -> K)?,
	render: (value: Types.Readable<V>, index: Types.Readable<number>, key: K) -> Host.Node,
	mountsPerFrame: number,
	priority: ((value: V, index: number) -> number)?,
	status: Types.Cell<Status>?,
}

local KNOWN_FIELDS: { [string]: true } = {
	from = true,
	key = true,
	render = true,
	mountsPerFrame = true,
	priority = true,
	status = true,
}

local function identity<V>(value: V, _index: number): any
	return value
end

local function mountBudget<V, K>(options: Options<V, K>): Children.Directive
	local settings = Support.optionsOf(options, "MountBudget", "from = ..., mountsPerFrame = ..., render = ...")
	Support.noUnknownFields(settings, "MountBudget", KNOWN_FIELDS)
	local source = Support.sourceOf(settings.from, "MountBudget", "from") :: Types.Body<{ V }>
	local render =
		Support.builderOf(settings.render, "MountBudget", "render") :: (Types.Readable<V>, Types.Readable<number>, K) -> Host.Node
	local keyOf: (value: V, index: number) -> K = if settings.key == nil
		then (identity :: any) :: (value: V, index: number) -> K
		else Support.builderOf(settings.key, "MountBudget", "key")
	local priority: ((value: V, index: number) -> number)? = if settings.priority == nil
		then nil
		else Support.builderOf(settings.priority, "MountBudget", "priority")
	local rawLimit = settings.mountsPerFrame
	if type(rawLimit) ~= "number" or rawLimit ~= rawLimit or rawLimit < 1 then
		Diagnostics.raise("mount-budget/invalid-limit", "MountBudget needs a positive mountsPerFrame", {
			actual = Diagnostics.describe(rawLimit),
			expected = "a positive number",
		})
	end
	local limit = math.max(1, math.floor(rawLimit))
	local status = if settings.status == nil then nil else Support.writableOf(settings.status, "MountBudget", "status")

	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "MountBudget"
		Support.mountPointOf(mountPoint, "MountBudget")
		local admitted: { [K]: boolean } = {}
		local selectedValues: { V } = {}
		local selected = cellModule.cell(selectedValues, function()
			return false
		end)
		local selectedKeys: { K } = {}
		local tick = cellModule.cell(0)
		local pump = FramePump(owner, mountPoint.host, tick, "MountBudget")
		local builtFor: { V }? = nil
		local keys: { K } = {}
		local queue: { number } = {}
		local priorities: { number } = {}
		local cursor = 1
		local prefix = false

		owner.watch(function(use)
			use(tick)
			local list = source(use)
			local changed = list ~= builtFor
			if changed then
				local present: { [K]: boolean } = {}
				table.clear(keys)
				table.clear(queue)
				table.clear(priorities)
				for index, value in list do
					local key = keyOf(value, index)
					if present[key] then
						Diagnostics.raise("structure/duplicate-key", "two MountBudget items share a key", {
							index = index,
							contract = "keys identify mounted items and must be unique",
						})
					end
					present[key] = true
					keys[index] = key
				end
				for key in admitted do
					if not present[key] then
						admitted[key] = nil
					end
				end
				local candidates: { number } = {}
				for index, value in list do
					local key = keys[index]
					if not admitted[key] then
						candidates[#candidates + 1] = index
						if priority ~= nil then
							local score = (priority :: (V, number) -> number)(value, index)
							if type(score) ~= "number" or score ~= score or math.abs(score) == math.huge then
								Diagnostics.raise(
									"mount-budget/invalid-priority",
									"MountBudget.priority returned an invalid score",
									{
										index = index,
										actual = Diagnostics.describe(score),
										expected = "a finite number",
									}
								)
							end
							priorities[index] = score
						end
					end
				end
				local ranked = Admission(#candidates, if priority == nil then nil else 0, function(a, b)
					local left, right = candidates[a], candidates[b]
					return if priorities[left] == priorities[right]
						then left < right
						else priorities[left] > priorities[right]
				end)
				if ranked.order == nil then
					queue = candidates
				else
					for _, at in ranked.order :: { number } do
						queue[#queue + 1] = candidates[at]
					end
				end
				cursor = 1
				builtFor = list
			end

			local added: { number } = {}
			for _ = 1, limit do
				local index = queue[cursor]
				if index == nil then
					break
				end
				cursor += 1
				admitted[keys[index]] = true
				added[#added + 1] = index
			end

			if not changed and priority == nil and prefix then
				for _, index in added do
					selectedValues[#selectedValues + 1] = list[index]
					selectedKeys[#selectedKeys + 1] = keys[index]
				end
			else
				table.clear(selectedValues)
				table.clear(selectedKeys)
				prefix = true
				local foundGap = false
				for index, value in list do
					local key = keys[index]
					if admitted[key] then
						selectedValues[#selectedValues + 1] = value
						selectedKeys[#selectedKeys + 1] = key
						if foundGap then
							prefix = false
						end
					else
						foundGap = true
					end
				end
			end
			selected:set(selectedValues)
			local pending = #list - #selectedValues
			if status ~= nil then
				status:set { total = #list, mounted = #selectedValues, pending = pending }
			end
			pump.update(pending > 0)
		end)

		local function selectedKey(_value: V, index: number): K
			return selectedKeys[index]
		end
		(keyed { from = selected, key = selectedKey, render = render })(mountPoint)
	end
end

return mountBudget
