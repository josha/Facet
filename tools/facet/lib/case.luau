--!strict

export type Case = {
	name: string,
	run: () -> string?,
}

export type Result = { name: string, failure: string? }

local Case = {}

function Case.run(build: (() -> { Case })?): { Result }
	local results: { Result } = {}
	if build == nil then
		return results
	end
	local built, cases = pcall(build)
	if not built then
		table.insert(results, { name = "cases", failure = "could not build cases: " .. tostring(cases) })
		return results
	end
	for _, case in cases :: { Case } do
		local ok, failure = pcall(case.run)
		if not ok then
			table.insert(results, { name = case.name, failure = "raised: " .. tostring(failure) })
		else
			table.insert(results, { name = case.name, failure = failure })
		end
	end
	return results
end

function Case.report(label: string, build: (() -> { Case })?): number
	local results = Case.run(build)
	local failed = 0
	for _, result in results do
		if result.failure ~= nil then
			failed += 1
			print(("  [FAIL] %s: %s"):format(result.name, result.failure))
		else
			print(("  [ ok ] %s"):format(result.name))
		end
	end
	if #results == 0 then
		print(("%s selftest: FAIL (no cases)"):format(label))
		return 1
	end
	print(("%s selftest: %s (%d cases)"):format(label, if failed == 0 then "PASS" else "FAIL", #results))
	return if failed == 0 then 0 else 1
end

function Case.expect(condition: boolean, message: string): string?
	if condition then
		return nil
	end
	return message
end

function Case.equal(actual: unknown, expected: unknown, label: string?): string?
	if actual == expected then
		return nil
	end
	return ("%sexpected %s, got %s"):format(if label then label .. ": " else "", tostring(expected), tostring(actual))
end

function Case.same(actual: { string }, expected: { string }, label: string?): string?
	local matches = #actual == #expected
	if matches then
		for index, value in expected do
			if actual[index] ~= value then
				matches = false
				break
			end
		end
	end
	if matches then
		return nil
	end
	local function show(list: { string }): string
		return if #list == 0 then "(nothing)" else table.concat(list, " | ")
	end
	return ("%sexpected %s, got %s"):format(if label then label .. ": " else "", show(expected), show(actual))
end

function Case.first(...: string?): string?
	for index = 1, select("#", ...) do
		local value = select(index, ...)
		if value ~= nil then
			return value
		end
	end
	return nil
end

return table.freeze(Case)
