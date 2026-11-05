--!strict

local AssistantSandbox = {}

function AssistantSandbox.prelude(roots: string): string
	return ([[
if SecurityCapabilities ~= nil then
	local capabilities = SecurityCapabilities.fromCurrent():Remove(Enum.SecurityCapability.Unassigned)
	for _, root in %s do
		if root:GetAttribute("FacetAssistantSandbox") ~= true then
			for _, node in root:GetDescendants() do
				if node:IsA("ModuleScript") then
					node.Capabilities = capabilities
					node.Sandboxed = true
				end
			end
			if root:IsA("ModuleScript") then
				root.Capabilities = capabilities
				root.Sandboxed = true
			end
			root:SetAttribute("FacetAssistantSandbox", true)
		end
	end
end]]):format(roots)
end

return table.freeze(AssistantSandbox)
