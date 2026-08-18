--!strict
--[[ SKINNED-CONTROL ASSET ROOTS, ENUMERATED (MAINT-8d, 2026-08-17).

	`docs/extending/skinned-control.md` tells a contributor that `check_docs_cli`
	enforces their control's art, provenance and manifest. It did not: the checker
	hardcoded `assets/themes/ornate-gauge` and six filenames under it, so the
	promise held for the ONE worked example and a SECOND skinned control would
	have got zero mechanical protection — and nothing in the playbook told the
	author to go and edit the checker.

	THE MANIFEST IS THE REGISTRATION. Every asset root already ships an
	`upload-manifest.json`, and a CONTROL's manifest is distinguishable from a
	theme package's by construction: `"package": null` and a `"control"` name,
	because a control paints through the public `UI.Image` primitive rather than
	through a package's slots. That is not a convention invented here to make a
	checker possible — it is what `assets/themes/ornate-gauge/upload-manifest.json`
	already says, and why. So the roster is derived from the manifests, the
	expected files are derived from each manifest's own `assets` table, and adding
	a second skinned control registers it by shipping the manifest it owes anyway.
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local skinned_controls = {}

local THEME_ASSETS_DIR = "assets/themes"

export type Root = {
	dir: string,
	control: string,
	controlModule: string,
	manifestPath: string,
	-- every file the root must ship, derived from the manifest
	files: { string },
}

-- every asset root whose manifest declares a CONTROL rather than a package
function skinned_controls.roots(): { Root }
	local out: { Root } = {}
	for _, entry in fs.readDir(THEME_ASSETS_DIR) do
		local dir = `{THEME_ASSETS_DIR}/{entry}`
		local manifestPath = `{dir}/upload-manifest.json`
		if not fs.isDir(dir) or not fs.isFile(manifestPath) then
			continue
		end
		local ok, manifest = pcall(serde.decode, "json", fs.readFile(manifestPath))
		if not ok or type(manifest) ~= "table" then
			continue
		end
		local control = (manifest :: any).control
		if type(control) ~= "string" or (manifest :: any).package ~= nil then
			continue -- a theme package's art, governed by the package rules
		end
		local files: { string } = { manifestPath, `{dir}/provenance.md` }
		for _, asset in (manifest :: any).assets or {} do
			if type(asset) == "table" and type(asset.file) == "string" then
				table.insert(files, `{dir}/{asset.file}`)
			end
		end
		-- the generator: a skinned control's art must be reproducible, and the
		-- source directory is where every root in this repository keeps it
		local sourceDir = `{dir}/source`
		if fs.isDir(sourceDir) then
			for _, sourceEntry in fs.readDir(sourceDir) do
				if string.match(sourceEntry, "%.py$") ~= nil then
					table.insert(files, `{sourceDir}/{sourceEntry}`)
				end
			end
		end
		table.sort(files)
		table.insert(out, {
			dir = dir,
			control = control,
			controlModule = tostring((manifest :: any).controlModule),
			manifestPath = manifestPath,
			files = files,
		})
	end
	table.sort(out, function(a: Root, b: Root): boolean
		return a.dir < b.dir
	end)
	return out
end

-- every file every skinned-control root owes, as one flat list
function skinned_controls.files(): { string }
	local out: { string } = {}
	for _, root in skinned_controls.roots() do
		for _, file in root.files do
			table.insert(out, file)
		end
	end
	return out
end

-- which root a path belongs to, for a message that names the right owner
function skinned_controls.ownerOf(path: string): Root?
	for _, root in skinned_controls.roots() do
		if string.find(path, root.dir, 1, true) == 1 then
			return root
		end
	end
	return nil
end

return skinned_controls
