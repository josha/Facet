--!strict

return function<T>(errors: { [string]: { [string]: string } }, id: string, where: string, view: () -> T): T
	local node = view()
	if errors[id] then
		errors[id][where] = nil
	end
	return node
end
