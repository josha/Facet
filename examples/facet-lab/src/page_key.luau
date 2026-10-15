--!strict

return function(item: { id: string, revision: number }): string
	return `{item.id}/{item.revision or 0}`
end
