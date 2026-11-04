--!strict

return function(instance: Instance, tags: string | { string }, previous: { [string]: true }?): { [string]: true }
	local names = if type(tags) == "string" then { tags } else tags
	local nextTags: { [string]: true } = {}
	for _, name in names do
		assert(type(name) == "string", "Facet.tag: tags must contain strings")
		if (previous and previous[name]) or not instance:HasTag(name) then
			nextTags[name] = true
		end
	end
	for name in previous or {} do
		if not nextTags[name] then
			instance:RemoveTag(name)
		end
	end
	for name in nextTags do
		instance:AddTag(name)
	end
	return nextTags
end
