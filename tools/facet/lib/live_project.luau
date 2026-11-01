--!strict

local fs = require("@std/fs")
local process = require("@std/process")
local Json = require("./json")

type Node = Json.Object
export type Project = Json.Object

local function build(suites: { string }): Project
	local project = assert(Json.asObject(Json.decode(fs.readFileToString("examples/gallery.project.json"))))
	local tree = assert(Json.objectField(project, "tree"))
	local workspace = assert(Json.objectField(tree, "Workspace"))
	project.name = "Facet-Live"
	local revision = process.run({ "git", "rev-parse", "HEAD" })
	local status = process.run({ "git", "status", "--porcelain", "--untracked-files=no" })
	assert(revision.ok and status.ok, "cannot record the live build revision")
	workspace["$attributes"] = {
		Facet_Demos = fs.readFileToString("tools/studio/live/fixture_demos.json"),
		Facet_SourceStamp = string.gsub(revision.stdout, "%s+$", "") .. (if status.stdout == "" then "" else "+dirty"),
	}
	local storage = assert(Json.objectField(tree, "ReplicatedStorage"))
	storage.FacetLive = { ["$path"] = "../tools/studio/live" }
	storage.FacetVerify = { ["$path"] = "../tools/vendor/verify/src" }
	storage.FacetConsumerScreen = { ["$path"] = "consumer/src/screen.luau" }
	storage.Lab = {
		["$className"] = "Folder",
		drag_drop_demo = { ["$path"] = "facet-lab/src/drag_drop_demo.luau" },
		journal_demo = { ["$path"] = "facet-lab/src/journal_demo.luau" },
	}
	storage.LabThemes = { ["$path"] = "facet-lab/themes" }
	if table.find(suites, "lab") then
		storage.Lab = { ["$path"] = "facet-lab/src" }
		storage.FacetShowcase = {
			["$className"] = "Folder",
			screen = { ["$path"] = "gallery/client/screen.luau" },
			demo_picker = { ["$path"] = "gallery/client/demo_picker.luau" },
		}
	end
	local monitors: Node = { ["$className"] = "Folder" }
	for _, entry in fs.listDirectory("examples/virtual_monitors") do
		local name = string.match(entry.name, "^(.+)%.luau$")
		if name and not string.find(name, "%.client$") and not string.find(name, "%.verify$") then
			monitors[name] = { ["$path"] = "virtual_monitors/" .. entry.name }
		end
	end
	storage.VirtualMonitors = monitors
	return project
end

return { build = build }
