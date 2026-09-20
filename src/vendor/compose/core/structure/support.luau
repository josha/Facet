--!strict

local Active = require "../ownership/active"
local Children = require "../runtime/children"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Nodes = require "../ownership/nodes"
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"

local function ownerFor(primitive: string): Owner.Owner
	local owner = Active.current()
	if owner == nil then
		Diagnostics.raise("structure/no-active-owner", ("%s ran outside a mount"):format(primitive), {
			contract = "structural primitives belong to the subtree that contains them",
			fix = "use it as a child inside a constructor call, or inside runtime.mount(component, target)",
		})
	end
	return owner :: Owner.Owner
end

local function mountPointOf(mountPoint: any, primitive: string): Children.MountPoint
	if type(mountPoint) == "table" and rawget(mountPoint :: any, "insert") ~= nil then
		return mountPoint :: Children.MountPoint
	end
	Diagnostics.raise(
		"structure/directive-needs-a-mount-point",
		("%s was called without a mount point"):format(primitive),
		{
			actual = Diagnostics.describe(mountPoint),
			expected = "a mount point, which the parent holding the directive supplies",
			contract = "a structural directive is a child, not a component: it is placed in a parent's "
				.. "children and handed a window on that parent's slot",
			fix = ("use %s as a child inside a constructor call -- Frame { ... } -- and pass the "):format(primitive)
				.. "component that returns that node to runtime.mount(component, target)",
		}
	)
	error("unreachable", 0)
end

local function writableOf(value: any, primitive: string, field: string): any
	if type(value) == "table" and type((value :: any).set) == "function" then
		return value
	end
	Diagnostics.raise(
		"structure/status-not-a-cell",
		("%s was given a %s it cannot write to"):format(primitive, field),
		{
			key = field,
			actual = Diagnostics.describe(value),
			expected = "a cell, created with Compose.cell(...)",
			contract = ("%s writes its report into the cell the caller names, so the caller can read it"):format(
				primitive
			),
			fix = ("create it once -- local %s = Compose.cell(nil) -- and pass that cell"):format(field),
		}
	)
	error("unreachable", 0)
end

local function sourceOf<T>(value: any, primitive: string, field: string): Types.Body<T>
	if cellModule.isReadable(value) then
		return function(use: Types.Use): T
			return use(value)
		end
	end
	if type(value) == "function" then
		return value
	end
	Diagnostics.raise("structure/source-not-readable", ("%s was given a %s it cannot read"):format(primitive, field), {
		primitive = primitive,
		field = field,
		actual = Diagnostics.describe(value),
		expected = "a cell, a formula, or a function taking `use`",
		fix = ("pass the cell itself -- %s = players -- or a body that reads one"):format(field),
	})
	error("unreachable", 0)
end

local function builderOf(value: any, primitive: string, field: string): any
	if type(value) == "function" then
		return value
	end
	Diagnostics.raise(
		"structure/builder-not-a-function",
		("%s was given a %s it cannot call"):format(primitive, field),
		{
			primitive = primitive,
			field = field,
			actual = Diagnostics.describe(value),
			expected = "a function returning a node, or a list of nodes",
		}
	)
	error("unreachable", 0)
end

local function mountBuilder(
	mountPoint: Children.MountPoint,
	parent: Owner.Owner,
	builder: () -> Host.Node | Children.Directive,
	primitive: string
): Types.Dispose
	local owner = parent.createChild()
	local ok, produced: any = pcall(Active.withOwner, owner, builder)
	if not ok then
		owner.dispose()
		error(produced, 0)
	end

	if type(produced) == "function" then
		local mounted, err: any = pcall(Active.withOwner, owner, function()
			(produced :: Children.Directive)(mountPoint)
		end)
		if not mounted then
			owner.dispose()
			error(err, 0)
		end
		return owner.dispose
	end

	local kind = type(produced)
	if kind ~= "table" and kind ~= "userdata" then
		owner.dispose()
		Diagnostics.raise(
			"mount/not-a-child",
			("a %s branch returned neither a node nor a directive"):format(primitive),
			{
				actual = Diagnostics.describe(produced),
				expected = "a node, or a directive such as fragment(...) or keyed(...)",
			}
		)
	end

	local inserted, err: any = pcall(mountPoint.insert, produced, 1)
	if not inserted then
		owner.dispose()
		error(err, 0)
	end
	owner.own(function()
		mountPoint.remove(produced)
		Nodes.forget(produced)
	end)
	return owner.dispose
end

local function optionsOf(value: any, primitive: string, fields: string): { [string]: any }
	if cellModule.isReadable(value) then
		Diagnostics.raise(
			"structure/options-not-a-table",
			("%s takes one table of named options, and was given a source"):format(primitive),
			{
				primitive = primitive,
				actual = "a cell or formula, passed positionally",
				expected = ("{ %s }"):format(fields),
				fix = ("write %s { %s } -- the arguments are named because they are not distinguishable"):format(
					primitive,
					fields
				),
			}
		)
	end
	if type(value) == "table" then
		return value
	end
	Diagnostics.raise("structure/options-not-a-table", ("%s takes one table of named options"):format(primitive), {
		primitive = primitive,
		actual = Diagnostics.describe(value),
		expected = ("{ %s }"):format(fields),
		fix = ("write %s { %s }"):format(primitive, fields),
	})
	error("unreachable", 0)
end

local function noUnknownFields(options: { [string]: any }, primitive: string, known: { [string]: true })
	for field in options do
		if known[field] == nil then
			local names: { string } = {}
			for name in known do
				table.insert(names, name)
			end
			table.sort(names)
			Diagnostics.raise(
				"structure/unknown-option",
				("%s was given an option it does not have"):format(primitive),
				{
					primitive = primitive,
					option = tostring(field),
					expected = table.concat(names, ", "),
				}
			)
		end
	end
end

return {
	ownerFor = ownerFor,
	mountPointOf = mountPointOf,
	writableOf = writableOf,
	mountBuilder = mountBuilder,
	sourceOf = sourceOf,
	builderOf = builderOf,
	optionsOf = optionsOf,
	noUnknownFields = noUnknownFields,
}
