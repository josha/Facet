--!strict

local contract = {}

contract.HEADER = table.concat({
	"local Facet = require(game.ReplicatedStorage.Facet)",
	"local Compose = Facet.Compose",
	"",
	"export type Row = { [string]: unknown }",
}, "\n")

contract.ROWS = table.concat({
	"local function rows(supplied: Facet.Readable<{ Row }>?, sample: { Row }): (Facet.Use) -> { Row }",
	"\treturn function(use: Facet.Use): { Row }",
	"\t\treturn if supplied then use(supplied) else sample",
	"\tend",
	"end",
}, "\n")

contract.SIGNATURE = "return function(UI: Facet.Controls, data: Data?): GuiObject"
contract.ROW = "Facet.Readable<Row>"
contract.COLUMNS = "{ Facet.TableColumn<Row, unknown> }"
contract.ACTIVATION = "(Row, unknown, InputObject?, number?) -> ()"
contract.HANDLER = "(Row) -> ()"
contract.SOURCE = "Facet.Readable<{ Row }>"

function contract.dataType(bindings: { [string]: string }, literal: (unknown) -> string): string
	local keys: { string } = {}
	for key in bindings do
		table.insert(keys, key)
	end
	table.sort(keys)
	if #keys == 0 then
		return "export type Data = {}"
	end
	local lines = { "export type Data = {" }
	for _, key in keys do
		local kind = bindings[key]
		local shape = if kind == "rows"
			then contract.SOURCE
			elseif kind == "activation" then "(" .. contract.ACTIVATION .. ")"
			else "(" .. contract.HANDLER .. ")"
		table.insert(lines, "\t[" .. literal(key) .. "]: " .. shape .. "?,")
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n")
end

return contract
