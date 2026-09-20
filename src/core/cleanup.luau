--!strict
-- Run every release step before reporting the first failure. Teardown cannot
-- depend on a second dispose call: owners mark themselves closed before release.
return function(steps: { () -> () })
	local failed = false
	local failure: any = nil
	for _, step in steps do
		local ok, err = pcall(step)
		if not ok and not failed then
			failed, failure = true, err
		end
	end
	if failed then
		error(failure, 0)
	end
end
