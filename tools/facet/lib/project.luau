--!strict

local Files = require("./files")

local Project = {}

function Project.report(): string
	local lines = {
		"Project: " .. Files.cwd(),
		"Discovery uses Facet's file walker; rg and Git are optional. Do not assume this project is a Git checkout.",
		"Read application contracts before editing. Packages/, tools/ and docs/ are dependencies.",
	}
	for _, name in { "default.project.json", "rokit.toml", "README.md", "TEAM_NOTES.md" } do
		if Files.isFile(name) then
			table.insert(lines, name)
		end
	end
	local files = Files.walk("src", { skip = { vendor = true } })
	for index, file in files do
		if index > 60 then
			table.insert(lines, `{#files - 60} more application files; narrow with project <directory>.`)
			break
		end
		table.insert(lines, "src/" .. file)
	end
	return table.concat(lines, "\n")
end

return table.freeze(Project)
