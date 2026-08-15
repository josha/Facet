--!strict
-- Property-parity checker (swiftui-parity-next.md Milestone 0, investment 1;
-- acceptance row M0-A3). The public schema is the single source of truth for
-- what a `UI.*` constructor accepts. Six OTHER views of the same property have
-- to agree with it, and before this checker they could drift silently:
--
--   1. dirty classification   a reactive prop with a paint/semantics dirty
--                             class must actually be re-applied by the
--                             renderer's refresh loop. This is the exact bug
--                             that made reactive `surface`/`role`/`active`
--                             schedule work the adapter dropped.
--   2. render authority       every prop the renderer writes needs a declared
--                             authority in render/authority.luau, matching the
--                             schema's channel.
--   3. adapter binding        every "binding" / "style" prop must be handled by
--                             the real engine adapter's setProp switch.
--   4. layout consumption     every "layout" prop must be read by the
--                             renderer's layout-node builder or the solver.
--   5. handler wiring         every "handler" prop must be wired to an adapter
--                             seam by the renderer.
--   6. documentation + types  every non-deprecated prop must appear in the
--                             class's docs/reference/api.md entry, and the
--                             exported `<Class>Spec` type must carry exactly
--                             the schema's field set.
--
--   7. binding-prop CLASS restriction
--                             the renderer's private `BINDING_PROP_CLASSES`
--                             allowlist ("this binding prop is emitted only by
--                             these classes") must agree with the per-class
--                             authority manifest: every restricted class must
--                             declare the prop as `binding`, and no class
--                             OUTSIDE the restriction may.
--
-- check(opts?) -> { ok, problems, counts }. CLI: this file, run directly.

local fs = require("@lune/fs")

local schema = require("../../src/blueprint_schema")
local authority = require("../../src/render/authority")
local renderer = require("../../src/render/renderer")

local checker = {}

local SRC_BLUEPRINT = "src/blueprint.luau"
-- THE RENDERER AS ONE TEXT. The views below ask "does the renderer read
-- `props.<name>`?" and "what does its BINDING_PROP_CLASSES allowlist say?" — both
-- are questions about the renderer MODULE FAMILY, and the measure seam (which is
-- where nearly every layout prop is read) left for `render/layout_node.luau` in
-- the 200k `Source` write-cap split. Reading only the first file would have made
-- 38 layout props look unread. ADD A PART WHENEVER MORE OF THE RENDERER MOVES OUT.
local SRC_RENDERER_PARTS =
	{ "src/render/renderer.luau", "src/render/layout_node.luau", "src/render/presentation_channel.luau" }
local SRC_RENDERER = SRC_RENDERER_PARTS[1]
-- THE SOLVER AS ONE TEXT, for the same reason and by the same rule: the layout
-- channel asks "does the solver read `node.<name>`/`child.<name>`?", and the
-- 200k `Source` write-cap split moved three blocks of it out — the placement-prop
-- audit, the main-axis shrink pass and the whole grid. `layoutPriority` is read
-- ONLY in `shrink.luau` now, and `columns`/`minColumnWidth`/`itemSizing` ONLY in
-- `grid.luau`, so a solver-only read would already be answering about a file that
-- no longer holds the code. ADD A PART WHENEVER MORE OF THE SOLVER MOVES OUT.
local SRC_SOLVER_PARTS = {
	"src/layout/solver.luau",
	"src/layout/placement_audit.luau",
	"src/layout/shrink.luau",
	"src/layout/grid.luau",
}
local SRC_SOLVER = SRC_SOLVER_PARTS[1]
local SRC_ADAPTER = "src/client/screen_target.luau"
local DOCS_API = "docs/reference/api.md"

-- Props the renderer re-applies through a DEDICATED seam rather than the
-- generic binding/style write. Each entry names the seam so the exemption is a
-- decision on the record, not a hole.
local DEDICATED_PAINT_SEAMS: { [string]: string } = {
	-- typographyScale/preferred-text seam: applyTextScale rewrites every scaled
	-- size inside solveAndApply so measure and paint always agree.
	textSize = "renderer applyTextScale (scaled-text seam)",
	-- the AUTHORED PRESENTATION triple (ADR-0026): `refresh` collects the touched
	-- paths, re-reads each off the live tree and recomposes through the ONE
	-- presentation write site. Deliberately neither a binding nor a style prop —
	-- neither reaches `adapter.setProp` under its own name at all, which is what
	-- makes it a second TERM in the presentation channel rather than a second
	-- WRITER of its engine properties. The `presentation` branch below pins both
	-- halves of that claim.
	opacity = "renderer readAuthoredPresentation + pushPresentationPaint (ADR-0026)",
	scale = "renderer readAuthoredPresentation + pushPresentationPaint (ADR-0026)",
	rotation = "renderer readAuthoredPresentation + pushPresentationPaint (ADR-0026)",
}

-- Props consumed by the PRESENTER (focus graph / control contract) rather than
-- by a render write. They legitimately have no adapter side.
local PRESENTER_CHANNELS: { [string]: boolean } = { semantic = true, structural = true }

-- authority manifest key for a schema prop, where the two names differ
local AUTHORITY_ALIAS: { [string]: string } = { label = "text" }

-- ===== tiny Luau type-expression reader ====================================
-- Enough to answer "which field names does this exported spec type carry?":
-- an expression is an `&` chain (at depth 0) of alias names and inline records;
-- a record's fields are the identifiers followed by `:` at brace depth 1.

local function splitTopLevelIntersection(expr: string): { string }
	local parts: { string } = {}
	local depth = 0
	local start = 1
	local i = 1
	while i <= #expr do
		local c = string.sub(expr, i, i)
		if c == "{" or c == "(" or c == "<" then
			depth += 1
		elseif c == "}" or c == ")" or c == ">" then
			-- `->` is not a closing angle bracket
			if not (c == ">" and string.sub(expr, i - 1, i - 1) == "-") then
				depth -= 1
			end
		elseif c == "&" and depth == 0 then
			table.insert(parts, string.sub(expr, start, i - 1))
			start = i + 1
		end
		i += 1
	end
	table.insert(parts, string.sub(expr, start))
	return parts
end

local function recordFields(record: string): { string }
	local fields: { string } = {}
	local depth = 0
	local i = 1
	local pendingIdent: string? = nil
	local identStart: number? = nil
	while i <= #record do
		local c = string.sub(record, i, i)
		if c == "{" or c == "(" then
			depth += 1
			pendingIdent, identStart = nil, nil
		elseif c == "<" then
			depth += 1
			pendingIdent, identStart = nil, nil
		elseif c == "}" or c == ")" then
			depth -= 1
			pendingIdent, identStart = nil, nil
		elseif c == ">" then
			if string.sub(record, i - 1, i - 1) ~= "-" then
				depth -= 1
			end
			pendingIdent, identStart = nil, nil
		elseif depth == 1 and string.match(c, "[%a_]") ~= nil and identStart == nil then
			identStart = i
		elseif identStart ~= nil and string.match(c, "[%w_]") == nil then
			pendingIdent = string.sub(record, identStart :: number, i - 1)
			identStart = nil
			-- skip whitespace to find the separator
			local j = i
			while j <= #record and string.match(string.sub(record, j, j), "%s") ~= nil do
				j += 1
			end
			if depth == 1 and string.sub(record, j, j) == ":" then
				table.insert(fields, pendingIdent :: string)
			end
			pendingIdent = nil
			-- re-examine this character as a potential delimiter
			continue
		end
		i += 1
	end
	return fields
end

-- name -> expression, for every `export type` in the source. A type body ends
-- at the first newline where brace depth is back to zero, which covers both a
-- one-line alias and a multi-line record.
local function exportedTypes(source: string): { [string]: string }
	local out: { [string]: string } = {}
	local init = 1
	while true do
		local s, e, name = string.find(source, "export type ([%w_]+)[%w_<>,%s]*=", init)
		if s == nil then
			break
		end
		local from = (e :: number) + 1
		local depth = 0
		local i = from
		local sawContent = false
		while i <= #source do
			local c = string.sub(source, i, i)
			if c == "{" then
				depth += 1
				sawContent = true
			elseif c == "}" then
				depth -= 1
			elseif c == "\n" then
				if depth <= 0 and sawContent then
					break
				end
			elseif string.match(c, "%S") ~= nil then
				sawContent = true
			end
			i += 1
		end
		out[name :: string] = string.sub(source, from, i - 1)
		init = i
	end
	return out
end

local function fieldsOfType(
	types: { [string]: string },
	name: string,
	seen: { [string]: boolean }?
): { [string]: boolean }
	local visited = seen or {}
	local out: { [string]: boolean } = {}
	if visited[name] then
		return out
	end
	visited[name] = true
	local expr = types[name]
	if expr == nil then
		return out
	end
	for _, part in splitTopLevelIntersection(expr) do
		local trimmed = string.match(part, "^%s*(.-)%s*$") :: string
		if string.sub(trimmed, 1, 1) == "{" then
			for _, f in recordFields(trimmed) do
				out[f] = true
			end
		else
			local alias = string.match(trimmed, "^([%w_]+)$")
			if alias ~= nil and types[alias] ~= nil then
				for f in fieldsOfType(types, alias, visited) do
					out[f] = true
				end
			end
		end
	end
	return out
end

-- ===== the check ===========================================================

export type Options = {
	-- synthetic drift for the checker's own tests
	dropDocsFor: string?, -- "Class.prop"
	dropBindingProp: string?,
	-- view 7: inject a bogus `BINDING_PROP_CLASSES` entry, "prop=Class"
	bindingPropClass: string?,
}

-- ===== view 7 source reader ================================================
-- `BINDING_PROP_CLASSES` is a PRIVATE local in the renderer (it is not part of
-- the public `LuauUI.renderer` surface and should not become part of it just to
-- be checkable), so it is read from source — the same way views 3/4/5 read the
-- adapter, the solver and the renderer's own wiring.
local function sortedKeysOf(set: { [string]: boolean }): { string }
	local out: { string } = {}
	for name in set do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

local function bindingPropClasses(rendererSource: string): { [string]: { [string]: boolean } }
	local block = string.match(rendererSource, "local BINDING_PROP_CLASSES[^\n]-=%s*(%b{})")
	if block == nil then
		return {}
	end
	local out: { [string]: { [string]: boolean } } = {}
	for prop, classes in string.gmatch(block, "([%w_]+)%s*=%s*(%b{})") do
		local set: { [string]: boolean } = {}
		for class in string.gmatch(classes, "([%w_]+)%s*=%s*true") do
			set[class] = true
		end
		out[prop] = set
	end
	return out
end

function checker.check(opts: Options?)
	local options = opts or {}
	local problems: { string } = {}
	local function problem(msg: string)
		table.insert(problems, msg)
	end

	local blueprintSource = fs.readFile(SRC_BLUEPRINT)
	local rendererParts: { string } = {}
	for _, path in SRC_RENDERER_PARTS do
		table.insert(rendererParts, fs.readFile(path))
	end
	-- joined by a newline so no two files' lines ever merge into one
	local rendererSource = table.concat(rendererParts, "\n")
	local solverParts: { string } = {}
	for _, path in SRC_SOLVER_PARTS do
		table.insert(solverParts, fs.readFile(path))
	end
	local solverSource = table.concat(solverParts, "\n")
	local adapterSource = fs.readFile(SRC_ADAPTER)
	local docsSource = fs.readFile(DOCS_API)

	local bindingProps = table.clone(renderer.BINDING_PROPS)
	if options.dropBindingProp ~= nil then
		bindingProps[options.dropBindingProp] = nil
	end
	local styleProps = renderer.STYLE_PROPS
	local types = exportedTypes(blueprintSource)

	-- the api.md entry for a class: from the heading that names it (headings may
	-- cover a pair, e.g. "### `VStack` / `HStack`") to the next `### `
	local function docsSectionFor(class: string): string?
		local init = 1
		while true do
			local s = string.find(docsSource, "### ", init, true)
			if s == nil then
				return nil
			end
			local lineEnd = string.find(docsSource, "\n", s, true) or #docsSource
			local heading = string.sub(docsSource, s, lineEnd)
			if string.find(heading, "`" .. class .. "`", 1, true) ~= nil then
				local e = string.find(docsSource, "\n### ", s + 1, true) or #docsSource
				return string.sub(docsSource, s, e)
			end
			init = lineEnd + 1
		end
	end

	-- the shared box/container props are documented once under `### UI`
	local sharedSection = docsSectionFor("UI") or ""
	for _, prop in schema.sharedPropNames() do
		if string.find(sharedSection, prop, 1, true) == nil then
			problem(
				`shared property '{prop}' is not documented in the \`### UI\` section of {DOCS_API} `
					.. `(shared box/container props are documented once, not per class)`
			)
		end
	end

	local counts = { classes = 0, props = 0, deprecated = 0, typedFields = 0 }

	for _, class in schema.classNames() do
		counts.classes += 1
		local classSpec = schema.forClass(class) :: any
		local docsSection = docsSectionFor(class)
		if docsSection == nil and not classSpec.structural then
			problem(`class {class} has no \`### \\\`{class}\\\`\` entry in {DOCS_API}`)
		end

		-- exported spec type must exist and match the schema field set
		local typeName = class .. "Spec"
		local typeFields = fieldsOfType(types, typeName)
		if next(typeFields) == nil then
			problem(
				`class {class} has no usable exported spec type \`{typeName}\` in {SRC_BLUEPRINT} `
					.. `(public constructor boundaries must not be bare \`any\`)`
			)
		else
			if not typeFields.id then
				problem(`{typeName} is missing the \`id\` field`)
			end
			if classSpec.container and not typeFields.children then
				problem(`{typeName} is a container type but declares no \`children\` field`)
			end
			for prop, propSpec in classSpec.props do
				if propSpec.deprecated == nil then
					if not typeFields[prop] then
						problem(
							`{typeName} is missing field '{prop}' declared by the schema `
								.. `(exported types and the runtime schema must agree)`
						)
					end
				elseif typeFields[prop] then
					problem(`{typeName} declares field '{prop}', which the schema diagnoses as unsupported`)
				end
			end
			for field in typeFields do
				if field ~= "id" and field ~= "children" and classSpec.props[field] == nil then
					problem(`{typeName} declares field '{field}', which no schema property backs`)
				end
				counts.typedFields += 1
			end
		end

		for prop, propSpec in classSpec.props do
			counts.props += 1
			local where = `{class}.{prop}`

			if propSpec.deprecated ~= nil then
				counts.deprecated += 1
				local d = propSpec.deprecated
				if d.since == "" or d.removeNoEarlierThan == "" or d.replacement == "" then
					problem(`{where}: deprecation entry is missing a required ADR-0011 field`)
				end
				-- a diagnosed prop must NOT still be wired anywhere
				if bindingProps[prop] and prop ~= "text" and prop ~= "label" then
					problem(`{where} is diagnosed as unsupported but is still a renderer binding prop`)
				end
				continue
			end

			-- 1. reactive props that repaint must survive the refresh loop
			if propSpec.dirty ~= nil then
				local repaints = false
				for _, cls in propSpec.dirty do
					if cls == "paint" or cls == "semantics" then
						repaints = true
					end
				end
				if repaints and not (bindingProps[prop] or styleProps[prop] or DEDICATED_PAINT_SEAMS[prop]) then
					problem(
						`{where} dirties paint/semantics but the renderer refresh loop cannot re-apply it `
							.. `(not a BINDING_PROP, not a STYLE_PROP, and no dedicated seam) — a reactive `
							.. `value would schedule work the adapter drops`
					)
				end
				if propSpec.reactive ~= true then
					problem(`{where} declares dirty classes but is not marked reactive`)
				end
			elseif propSpec.reactive then
				problem(`{where} is reactive but declares no dirty classes — a change would schedule nothing`)
			end

			-- 2/3. channel-specific wiring
			if propSpec.channel == "binding" then
				local key = AUTHORITY_ALIAS[prop] or prop
				local owner = authority.authorityFor(class, key)
				if owner ~= "binding" then
					problem(
						`{where} is a binding prop but render/authority.luau declares its authority as `
							.. `{tostring(owner)} (expected "binding"; manifest key '{key}')`
					)
				end
				if not bindingProps[prop] then
					problem(`{where} is a binding prop but is missing from the renderer's BINDING_PROPS`)
				end
				if string.find(adapterSource, `prop == "{prop}"`, 1, true) == nil then
					problem(`{where} is a binding prop but the engine adapter ({SRC_ADAPTER}) never handles it`)
				end
			elseif propSpec.channel == "style" then
				local owner = authority.authorityFor(class, prop)
				if owner ~= "style" then
					problem(
						`{where} is a style prop but render/authority.luau declares its authority as {tostring(owner)}`
					)
				end
				if not styleProps[prop] then
					problem(`{where} is a style prop but is missing from the renderer's STYLE_PROPS`)
				end
				if string.find(adapterSource, `prop == "{prop}"`, 1, true) == nil then
					problem(`{where} is a style prop but the engine adapter ({SRC_ADAPTER}) never handles it`)
				end
			elseif propSpec.channel == "layout" then
				local readByRenderer = string.find(rendererSource, `props.{prop}`, 1, true) ~= nil
				local readBySolver = string.find(solverSource, `node.{prop}`, 1, true) ~= nil
					or string.find(solverSource, `child.{prop}`, 1, true) ~= nil
				if not (readByRenderer or readBySolver) then
					problem(
						`{where} is a layout prop but neither the renderer's layout-node builder nor the `
							.. `solver reads it — it would be frozen into the node and ignored`
					)
				end
			elseif propSpec.channel == "handler" then
				if string.find(rendererSource, `props.{prop}`, 1, true) == nil then
					problem(`{where} is a handler prop but the renderer never wires it to an adapter seam`)
				end
			elseif propSpec.channel == "presentation" then
				-- ADR-0026: BOTH halves of "a second term, not a second writer".
				-- (a) the renderer must actually read it off the node...
				if string.find(rendererSource, `props.{prop}`, 1, true) == nil then
					problem(
						`{where} is a presentation prop but the renderer never reads it — it would be `
							.. `frozen into the node and ignored`
					)
				end
				-- (b) ...and no adapter may handle it under its own name, because the
				-- ONLY thing that may reach the engine is the composed presentation
				-- write. An adapter branch for it would be exactly the second writer
				-- the authority manifest exists to prevent.
				if string.find(adapterSource, `prop == "{prop}"`, 1, true) ~= nil then
					problem(
						`{where} is a presentation prop but {SRC_ADAPTER} handles it as its own `
							.. `adapter prop — that is a SECOND WRITER for an engine property the `
							.. `presentation authority owns (ADR-0026 Decision 1)`
					)
				end
			elseif not PRESENTER_CHANNELS[propSpec.channel] then
				problem(`{where} declares unknown channel '{propSpec.channel}'`)
			end

			-- 6. documentation (class-specific props only; shared props above)
			if docsSection ~= nil and not propSpec.shared then
				local documented = string.find(docsSection, prop, 1, true) ~= nil
				if options.dropDocsFor == where then
					documented = false -- synthetic drift for the checker's own spec
				end
				if not documented then
					problem(`{where} is not mentioned in the {DOCS_API} entry for {class}`)
				end
			end
		end
	end

	-- reverse direction: no renderer binding prop without a public schema prop
	local schemaProps: { [string]: boolean } = {}
	for _, class in schema.classNames() do
		for prop in (schema.forClass(class) :: any).props do
			schemaProps[prop] = true
		end
	end
	for prop in bindingProps do
		if not schemaProps[prop] then
			problem(`renderer BINDING_PROPS declares '{prop}', which no public schema property backs`)
		end
	end
	for prop in styleProps do
		if not schemaProps[prop] then
			problem(`renderer STYLE_PROPS declares '{prop}', which no public schema property backs`)
		end
	end

	-- ===== 7. BINDING_PROP_CLASSES vs the authority manifest (ARCH-8) =========
	-- "Which class emits this binding prop" is now written down twice: the
	-- renderer's private allowlist and authority.luau's per-class manifest. The
	-- F-19/BP-F12 defect (`thickness` dispatched as a binding write for Divider,
	-- which consumes it in the SOLVER and never sees an adapter) is exactly what
	-- the two disagreeing looks like, and nothing derived one from the other — so
	-- the same defect could return silently. This view makes them agree.
	local manifest = authority.manifest()
	local restrictions = bindingPropClasses(rendererSource)
	if options.bindingPropClass ~= nil then
		local prop, class = string.match(options.bindingPropClass, "^([%w_]+)=([%w_]+)$")
		if prop ~= nil then
			restrictions[prop :: string] = { [class :: string] = true }
		end
	end
	if next(restrictions) == nil then
		problem(
			`{SRC_RENDERER} declares no readable BINDING_PROP_CLASSES table — view 7 would pass vacuously `
				.. `(the allowlist moved or was renamed; teach this reader about it)`
		)
	end
	for prop, only in restrictions do
		if not bindingProps[prop] then
			problem(`renderer BINDING_PROP_CLASSES restricts '{prop}', which is not a BINDING_PROPS prop at all`)
		end
		-- (a) every RESTRICTED class must declare the prop as `binding`
		for class in only do
			local declared = authority.authorityFor(class, prop)
			if declared ~= "binding" then
				problem(
					`renderer BINDING_PROP_CLASSES says {class} emits '{prop}' as a binding, but `
						.. `render/authority.luau declares {class}.{prop} as '{declared or "nothing"}'`
				)
			end
		end
		-- (b) ...and no class OUTSIDE the restriction may declare it as a binding.
		-- `common` is checked too: a shared binding entry would make the
		-- restriction a lie for every class at once.
		for class, props in manifest do
			if only[class] or props[prop] ~= "binding" then
				continue
			end
			problem(
				`render/authority.luau declares {class}.{prop} as a binding, but the renderer's `
					.. `BINDING_PROP_CLASSES restricts '{prop}' to {table.concat(sortedKeysOf(only), ", ")} — `
					.. `{class} would be authorized to write a prop the renderer never emits for it`
			)
		end
	end

	return { ok = #problems == 0, problems = problems, counts = counts }
end

return checker
