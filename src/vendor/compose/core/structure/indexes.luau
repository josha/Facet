--!strict
--!native

local StructureTypes = require "./types"
local Owners = require "../ownership/owner"
local Block = require "../runtime/block"
local Children = require "../runtime/children"
local Host = require "../host"
local Support = require "./support"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"

export type Render<V> = StructureTypes.IndexedRender<V>

type Row<V> = {
	owner: Owners.Owner,
	value: Types.Value<V>,
}

local function indexes<V>(source: Types.Source<{ V }>, render: Render<V>): Children.Directive
	local from: Types.Body<{ V }> = Support.sourceOf(source, "indexes", "source")
	local build: Render<V> = Support.builderOf(render, "indexes", "render")
	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "indexes"
		Support.mountPointOf(mountPoint, "indexes")
		local rows: { Row<V> } = {}
		local items: { V } = {}

		Owners.own(owner, function()
			table.clear(rows)
			table.clear(items)
		end)

		Owners.watch(owner, function(use)
			local list = from(use)
			local wanted = #list

			for index = 1, wanted do
				local row = rows[index]
				local item = list[index]
				if row ~= nil then
					if items[index] ~= item then
						items[index] = item
						row.value:set(item)
					end
				else
					local value = cellModule.cell(item)
					local position = index
					local block = Block.mountBlock(mountPoint, owner, function(): { Host.Node }
						return { build(value, position) }
					end, "indexed row", nil)
					rows[index] = { owner = block.owner, value = value }
					items[index] = item
				end
			end

			for index = #rows, wanted + 1, -1 do
				Owners.dispose(rows[index].owner)
				rows[index] = nil
				items[index] = nil
			end
		end)
	end
end

return indexes
