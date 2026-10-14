--!strict
local fs = require("@std/fs")
local process = require("@std/process")
local system = require("@std/system")
local Schema = require("../../tools/facet/lib/schema")

local Fixtures = {}

Fixtures.RICH = [==[
--!strict

local Facet = require(game.ReplicatedStorage.Facet)
local Compose = Facet.Compose

type Item = { id: string, name: string }
type Model = { title: Facet.Cell<string>, items: Facet.Cell<{ Item }>, open: Facet.Cell<boolean> }

return function(UI: Facet.Controls, model: Model): GuiObject
	local function close()
		model.open:set(false)
	end
	-- The panel lists the inventory.
	return UI.Screen "Root" {
		gap = "m",
		UI.VStack "Panel" {
			gap = "s", -- tight rows
			padding = { left = 16, right = 16 },
			width = "fill" :: "fill",
			-- The title follows the model.
			UI.Text "Title" {
				text = function(use)
					return use(model.title)
				end,
				textRole = "title" :: "title",
			},
			UI.HStack "Row" { gap = "s", UI.Text "Left" { text = "A" }, UI.Text "Right" { text = "B" } },
			UI.Divider {},
			Compose.keyed({
				from = model.items,
				key = function(item)
					return item.id
				end,
				render = function(item)
					return UI.Text "Item" {
						text = function(use)
							return use(item).name
						end,
					}
				end,
			}),
			UI.Text "Notes" {
				text = [[
First line
	Second line]],
				wrap = true,
			},
			UI.Button "Close" {
				label = "Close",
				Size = UDim2.fromOffset(120, 40),
				onActivate = close,
			},
		},
	}
end
]==]

Fixtures.SMALL = [==[
--!strict

local Facet = require(game.ReplicatedStorage.Facet)

return function(UI: Facet.Controls, model: { [string]: unknown }): GuiObject
	return UI.Screen "Screen" {
		gap = "m",
		UI.Text "Heading" {
			text = "Hello",
			textRole = "title" :: "title",
		},
		UI.Button "Go" {
			label = "Go",
		},
	}
end
]==]

Fixtures.HOST = [==[
--!strict

local Facet = require(game.ReplicatedStorage.Facet)

return function(UI: Facet.Controls, model: { [string]: unknown }): GuiObject
	local Host = Facet.Roblox.createRuntime().constructors
	return UI.Screen "Screen" {
		Host.Frame "Backdrop" {
			BackgroundTransparency = 1,
		},
	}
end
]==]

Fixtures.SPACES = table.concat({
	"--!strict",
	"",
	"return function(UI, model)",
	'    return UI.Screen "Screen" {',
	'        gap = "m",',
	'        UI.Text "Heading" {',
	'            text = "Hello",',
	"        },",
	"    }",
	"end",
	"",
}, "\n")

Fixtures.CRLF = (string.gsub(Fixtures.SMALL, "\n", "\r\n"))

local counter = 0

function Fixtures.root(): string
	return assert(Schema.findRoot(), "the tests run inside the Facet repository")
end

function Fixtures.schema(): Schema.Schema
	return Schema.load(Fixtures.root())
end

function Fixtures.read(relative: string): string
	return fs.readFileToString(Fixtures.root() .. "/" .. relative)
end

function Fixtures.directory(label: string): string
	counter += 1
	local base = string.gsub(tostring(system.tmpdir()), "\\", "/")
	local path = ("%s/facet-design-%s-%d-%d-%d"):format(base, label, process.pid(), os.time(), counter)
	fs.createDirectory(path, { makeParents = true })
	return path
end

function Fixtures.file(label: string, source: string, name: string?): string
	local directory = Fixtures.directory(label)
	local path = directory .. "/" .. (name or "View.luau")
	fs.writeStringToFile(path, source)
	return path
end

function Fixtures.remove(path: string)
	pcall(function()
		fs.removeDirectory(path, { recursive = true })
	end)
end

function Fixtures.stylua(source: string): (boolean, string)
	local directory = Fixtures.directory("stylua")
	local path = directory .. "/Check.luau"
	fs.writeStringToFile(path, source)
	local ok, result = pcall(function(): process.ProcessResult
		return process.run({ "stylua", "--check", "-f", Fixtures.root() .. "/stylua.toml", path })
	end)
	Fixtures.remove(directory)
	if not ok then
		return false, tostring(result)
	end
	local run = result :: process.ProcessResult
	return run.ok, run.stdout .. run.stderr
end

function Fixtures.walk(relative: string): { string }
	local found: { string } = {}
	local root = Fixtures.root()
	local function visit(path: string)
		local entries = fs.listDirectory(root .. "/" .. path)
		table.sort(entries, function(left: fs.DirectoryEntry, right: fs.DirectoryEntry): boolean
			return left.name < right.name
		end)
		for _, entry in entries do
			local child = path .. "/" .. entry.name
			if entry.type == "dir" then
				visit(child)
			elseif string.sub(entry.name, -5) == ".luau" then
				table.insert(found, child)
			end
		end
	end
	visit(relative)
	return found
end

return table.freeze(Fixtures)
