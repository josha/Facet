--!strict
--!native

local Block = require "../runtime/block"
local Children = require "../runtime/children"
local Host = require "../host"
local Support = require "./support"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"

export type Render<V> = (value: Types.Readable<V>, index: number) -> Host.Node

type Row<V> = {
	block: Block.Block,
	value: Types.Cell<V>,
}

local function indexes<V>(source: any, render: Render<V>): Children.Directive
	local from = Support.sourceOf(source, "indexes", "source") :: Types.Body<{ V }>
	local build = Support.builderOf(render, "indexes", "render") :: Render<V>
	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "indexes"
		Support.mountPointOf(mountPoint, "indexes")
		local rows: { Row<V> } = {}

		owner.own(function()
			table.clear(rows)
		end)

		owner.watch(function(use)
			local list = from(use)
			local wanted = #list

			for index = 1, wanted do
				local row = rows[index]
				if row ~= nil then
					row.value:set(list[index])
				else
					local value = cellModule.cell(list[index])
					local position = index
					local block = Block.mountBlock(mountPoint, owner, function(): { Host.Node }
						return { build(value, position) }
					end, "indexed row", nil)
					rows[index] = { block = block, value = value }
				end
			end

			for index = #rows, wanted + 1, -1 do
				rows[index].block.dispose()
				rows[index] = nil
			end
		end)
	end
end

return indexes
