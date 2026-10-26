--!strict

local fs = require("@std/fs")
local process = require("@std/process")
local Loader = require("../../tests/lib/loader")

local Facet = Loader.new().require("src") :: typeof(require("../../src"))

local kit = Facet.design()
local library = kit.library({
	UI = {},
})

local function check(source: string): (boolean, string)
	local parsed, value = pcall(kit.Design.parse, source, library)
	if not parsed then
		return false, `custom code; the editor stops syncing: {value}`
	end
	local emitted = kit.Design.emit(value, library, { name = value.name })
	if emitted == source then
		return true, "design; the editor stays in sync"
	end
	local line = 1
	for index = 1, math.min(#source, #emitted) do
		if string.byte(source, index) ~= string.byte(emitted, index) then
			break
		elseif string.byte(source, index) == 10 then
			line += 1
		end
	end
	return false, `design, but the editor rewrites it from line {line} on its next edit`
end

local failed = 0
for index = 2, #process.args do
	local path = process.args[index]
	local ok, message = check(fs.readFileToString(path))
	print(`{path}: {message}`)
	if not ok then
		failed += 1
	end
end
process.exit(if failed == 0 then 0 else 1)
