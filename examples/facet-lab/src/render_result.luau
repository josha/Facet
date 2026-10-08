--!strict

return function(errors: any, id: string, where: string, view: () -> any): any
	local node = view()
	if errors[id] then
		errors[id][where] = nil
	end
	return node
end
