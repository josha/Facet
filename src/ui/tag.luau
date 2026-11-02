--!strict
return function<N>(node: N & Instance, role: string): N & Instance
	node:AddTag("facet-" .. string.lower(role))
	return node
end
