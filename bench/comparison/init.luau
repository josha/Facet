--!strict

local Types = require("@self/types")

local all: { Types.Workload } = {}
for _, group in
	{
		require("@self/readouts"),
		require("@self/collections"),
		require("@self/inputs"),
		require("@self/surfaces"),
		require("@self/screens"),
	}
do
	for _, workload in group do
		table.insert(all, workload)
	end
end

return all
