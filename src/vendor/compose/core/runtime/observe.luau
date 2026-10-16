--!strict

local Host = require "../host"
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local Cell = require "../reactive/cell"

local sharedResource = require "../async/shared"

return function(host: Host.Host, ownerOf: (string) -> Owner.Owner)
	local entries: { [Host.Node]: { [string]: sharedResource.Acquire<Types.Cell<unknown>> } } = {}
	return function(node: Host.Node, property: string): Types.Readable<unknown>
		ownerOf "observe"
		local observation = assert(host.observation, "Compose observe requires host.observation")
		local properties = entries[node]
		if properties == nil then
			properties = {}
			entries[node] = properties
		end
		local acquire: sharedResource.Acquire<Types.Cell<unknown>>? = properties[property]
		if acquire == nil then
			acquire = sharedResource(function()
				ownerOf("observe").own(function()
					properties[property] = nil
					if next(properties) == nil then
						entries[node] = nil
					end
				end)
				local value = Cell.cell(observation.readProperty(node, property))
				return value,
					observation.observeProperty(node, property, function()
						value:set(observation.readProperty(node, property))
					end)
			end)
			properties[property] = assert(acquire)
		end
		return assert(acquire)()
	end
end
