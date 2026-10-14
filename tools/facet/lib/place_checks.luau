--!strict

local Files = require("./files")
local Lute = require("../../vendor/verify/src/lute")

export type Node = { class: string, properties: { [string]: string }, children: { [string]: Node } }

local RUN_CONTEXT_CLIENT = "2"

local PlaceChecks = {}

local function node(instance: Lute.ModelInstance): Node
	local properties: { [string]: string } = {}
	for name, property in instance.properties do
		properties[name] = property.value
	end
	local children: { [string]: Node } = {}
	for _, child in instance.children do
		if children[child.name] == nil then
			children[child.name] = node(child)
		end
	end
	return { class = instance.className, properties = properties, children = children }
end

function PlaceChecks.read(path: string): Node
	local children: { [string]: Node } = {}
	for _, instance in Lute.model.read(Files.read(path)) do
		children[instance.name] = node(instance)
	end
	return { class = "DataModel", properties = {}, children = children }
end

function PlaceChecks.find(root: Node, ...: string): Node?
	local current: Node? = root
	for _, name in { ... } do
		if current == nil then
			return nil
		end
		current = current.children[name]
	end
	return current
end

local function source(path: string): string
	return (string.gsub(Files.read(path), "\r\n", "\n"))
end

local function same(target: Node?, path: string): boolean
	return target ~= nil and (string.gsub(target.properties.Source or "", "\r\n", "\n")) == source(path)
end

function PlaceChecks.bootstrap(path: string): string?
	local place = PlaceChecks.read(path)
	local gallery = PlaceChecks.find(place, "ReplicatedStorage", "Gallery")
	local duplicate = PlaceChecks.find(place, "StarterPlayer", "StarterPlayerScripts", "Gallery")
	if
		gallery == nil
		or gallery.class ~= "Script"
		or gallery.properties.RunContext ~= RUN_CONTEXT_CLIENT
		or duplicate ~= nil
	then
		return `{path}: requires one ReplicatedStorage.Gallery Script with RunContext Client and no starter copy`
	end
	return nil
end

function PlaceChecks.app(path: string, folder: string, root: string): string?
	local place = PlaceChecks.read(path)
	local examples = `examples/{folder}`
	local bootstrap = PlaceChecks.find(place, "StarterPlayer", "StarterPlayerScripts", root)
	if bootstrap == nil or bootstrap.class ~= "LocalScript" or not same(bootstrap, `{examples}/main.client.luau`) then
		return `{path}: the client bootstrap differs from {examples}/main.client.luau`
	end
	local modules = PlaceChecks.find(place, "ReplicatedStorage", root)
	if modules == nil or modules.children.model == nil or modules.children.screens == nil then
		return `{path}: ReplicatedStorage.{root} lacks its model and screens modules`
	end
	for name, module in modules.children do
		if module.class ~= "ModuleScript" or not same(module, `{examples}/{name}.luau`) then
			return `{path}: ReplicatedStorage.{root}.{name} differs from {examples}/{name}.luau`
		end
	end
	local facet = PlaceChecks.find(place, "ReplicatedStorage", "Facet")
	if facet == nil or not same(facet, "src/init.luau") then
		return `{path}: ReplicatedStorage.Facet differs from src/init.luau`
	end
	local core = PlaceChecks.find(facet, "vendor", "compose", "core")
	if
		core == nil
		or core.children["focus-neighbor"] == nil
		or PlaceChecks.find(core, "structure", "tile-collection") == nil
	then
		return `{path}: the upstream Compose modules are missing`
	end
	if PlaceChecks.find(facet, "ui", "focus_beam") ~= nil then
		return `{path}: the removed ui/focus_beam module is still mounted`
	end
	return nil
end

return table.freeze(PlaceChecks)
