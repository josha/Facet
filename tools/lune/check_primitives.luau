--!strict
--[[ PRIMITIVE-CLASS REGISTRATION CHECKER (MAINT-5, 2026-08-17).

	Adding a new blueprint PRIMITIVE — a class the adapter materialises, not a
	composite built out of existing ones — touches four registries that nothing
	compared:

	  1. `src/blueprint_schema.luau`      the class and its property declarations
	  2. `src/class_contract.luau`     its focus role, actions and hit floor
	  3. `CLASS_TO_INSTANCE`              the engine instance the live adapter creates
	     (`src/client/screen_target.luau`)
	  4. the adapter's own `create()` branch, on BOTH targets

	`docs/extending/new-control.md` defers the primitive case to
	`new-engine-feature.md`, which only describes the property/modifier path, so
	the whole class of change had no playbook AND no checker: a class could be
	declared in the schema and be invisible to conformance, or a mapping could
	outlive the class it names, and every suite stayed green.
	`docs/extending/new-primitive.md` is the playbook; this is the checker.

	THE FOUR RULES, each stated as the failure it prevents:

	  * a STALE MAPPING — `CLASS_TO_INSTANCE` names a class the schema no longer
	    declares, so an adapter keeps a branch for something that cannot exist;
	  * a GHOST CONTRACT — `class_contract.luau` declares a class the schema
	    does not, so a conformance row points at nothing;
	  * an UNREGISTERED PRIMITIVE — the schema declares a class with no contract
	    row, which is exactly how `Grip` (a focusable, pointer-handling control)
	    became invisible to every four-input rule;
	  * a MISSING create() BRANCH — a class no adapter can actually materialise.
	    Proved by DRIVING the headless target rather than by reading it: the
	    class is mounted and the adapter is asked for a handle.

	The live adapter cannot be required headlessly (engine globals at module
	scope), so `CLASS_TO_INSTANCE` is read as TEXT — the same instrument
	`tests/lib/adapter_source.luau` and `check_prop_parity` already use, and the
	parse FAILS LOUDLY when the table cannot be found rather than passing
	vacuously on an empty set.

	check(opts?) -> { ok, problems, counts }; `opts` injects synthetic drift for
	the checker's own mutation tests.
]]

local fs = require("@lune/fs")

local Facet = require("../../src") :: any
local controlContract = require("../../src/class_contract")
local mountLib = require("../../src/mount")
local environment = require("../../src/env/environment")
local rendererLib = require("../../src/render/renderer")
local fake_target = require("../../tests/lib/fake_target")

local UI = Facet.UI

local ADAPTER_SOURCE = "src/client/screen_target.luau"

local check_primitives = {}

export type Options = {
	-- pretend the live adapter maps this class (a stale-mapping mutation)
	extraMapping: string?,
	-- pretend the schema declares this class (an unregistered-primitive mutation)
	extraSchemaClass: string?,
	-- pretend the contract registry declares this class (a ghost-row mutation)
	extraContractClass: string?,
}

-- CLASS_TO_INSTANCE, read from the live adapter's source
function check_primitives.classToInstance(source: string): { [string]: string }
	local block = string.match(source, "local CLASS_TO_INSTANCE: {%s*%[string%]: string%s*} =%s*(%b{})")
	assert(
		block ~= nil,
		`check_primitives: {ADAPTER_SOURCE} declares no readable CLASS_TO_INSTANCE table — the mapping `
			.. `moved or was renamed; teach this reader about it rather than letting the check pass vacuously`
	)
	local out: { [string]: string } = {}
	for class, instance in string.gmatch(block :: string, '([%w_]+)%s*=%s*"([%w_]+)"') do
		out[class] = instance
	end
	assert(next(out) ~= nil, "check_primitives: CLASS_TO_INSTANCE parsed to an EMPTY table")
	return out
end

--[[ THE MINIMAL FORM OF EACH CLASS THAT DECLARES A REQUIRED PROP.

	The create() probe below has to BUILD one of each class, and a class with a
	required property cannot be built from `{ id = … }` alone. Listing the minimum
	here is not bookkeeping — it is the same declaration `docs/extending/new-
	primitive.md` step 3 asks an author to make ("what is the smallest legal
	instance of your class"), and a new primitive with a required prop and no
	entry here fails by name rather than by a confusing constructor error. ]]
local MINIMAL_PROPS: { [string]: { [string]: any } } = {
	Button = { label = "Probe" },
	Toggle = { label = "Probe" },
	Text = { text = "Probe" },
	Path = { points = { { x = 0, y = 0 }, { x = 1, y = 1 } } },
	Region = { group = "probe", rank = 1, children = { UI.Box({ id = "Form" }) } },
	Composition = {
		arrangements = { "column" },
		groups = { { id = "g", lane = "main", sizing = "fill" } },
		children = {
			UI.Region({ id = "R", group = "g", rank = 1, children = { UI.Box({ id = "Form" }) } }),
		},
	},
	ViewThatFits = { children = { UI.Box({ id = "Candidate" }) } },
}

-- can the headless target actually create this class? Mounts one node of it and
-- asks the adapter for its handle.
local function createsHandle(class: string): (boolean, string?)
	local core = Facet.newCore()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local ok, adapter = pcall(function()
		local constructor = (UI :: any)[class]
		local props: { [string]: any } = { id = "Probe" }
		for key, value in MINIMAL_PROPS[class] or {} do
			props[key] = value
		end
		local node = constructor(props)
		local root = mountLib.mount(core, UI.Screen({ id = "S", children = { node } }))
		local target = fake_target.new()
		local controller = rendererLib.attach(core, root, env, target, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local made = target.node("/S/Probe") ~= nil
		controller.dispose()
		root.dispose()
		return made
	end)
	if not ok then
		return false, tostring(adapter)
	end
	return adapter == true, nil
end

function check_primitives.check(opts: Options?): { ok: boolean, problems: { string }, counts: { [string]: number } }
	local options = opts or {}
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end

	local mapping = check_primitives.classToInstance(fs.readFile(ADAPTER_SOURCE))
	if options.extraMapping ~= nil then
		mapping[options.extraMapping] = "Frame"
	end

	local schemaClasses: { [string]: boolean } = {}
	for _, name in UI.schema.classNames() do
		schemaClasses[name] = true
	end
	if options.extraSchemaClass ~= nil then
		schemaClasses[options.extraSchemaClass] = true
	end

	local contractClasses: { [string]: boolean } = {}
	for name in controlContract.all() do
		contractClasses[name] = true
	end
	if options.extraContractClass ~= nil then
		contractClasses[options.extraContractClass] = true
	end

	-- 1. no stale mapping
	for class in mapping do
		if not schemaClasses[class] then
			problem(
				`{ADAPTER_SOURCE}'s CLASS_TO_INSTANCE maps '{class}', which the blueprint schema does not declare — `
					.. `a mapping outliving its class is a create() branch for something that cannot exist`
			)
		end
	end

	-- 2. no ghost contract row
	for class in contractClasses do
		if not schemaClasses[class] then
			problem(
				`src/class_contract.luau declares '{class}', which the blueprint schema does not — a conformance `
					.. `row pointing at nothing reads as coverage`
			)
		end
	end

	local materialised = 0
	for class in schemaClasses do
		local spec = UI.schema.forClass(class)
		local isStructural = spec ~= nil and spec.structural == true
		-- 3. every class is registered for conformance
		if not contractClasses[class] then
			problem(
				`blueprint class '{class}' has no row in src/class_contract.luau — an unregistered primitive is a `
					.. `primitive no four-input, paradigm or hit-floor rule can see (this is how Grip shipped unseen)`
			)
		end
		-- 4. every materialised class has a create() branch that works
		if not isStructural and (UI :: any)[class] ~= nil then
			materialised += 1
			local made, err = createsHandle(class)
			if not made then
				local because = if err ~= nil then ` ({err})` else ""
				problem(
					`blueprint class '{class}' does not reach a render-target handle{because} — either the create() `
						.. `branch is missing/refusing it, or it declares a required prop with no MINIMAL_PROPS entry `
						.. `in this checker (see docs/extending/new-primitive.md step 3)`
				)
			end
		end
	end

	local mapped = 0
	for _ in mapping do
		mapped += 1
	end
	local declared = 0
	for _ in schemaClasses do
		declared += 1
	end
	return {
		ok = #problems == 0,
		problems = problems,
		counts = { classes = declared, mapped = mapped, materialised = materialised },
	}
end

return check_primitives
