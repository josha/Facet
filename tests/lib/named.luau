--!strict
return function<P>(name: string, props: P): P
	local copy = table.clone((props :: unknown) :: { [unknown]: unknown })
	assert(copy.Name == nil, "named props already have a Name")
	copy.Name = name
	return (copy :: unknown) :: P
end
