--!strict

return function(item: any): string
	return `{item.id}/{item.revision or 0}`
end
