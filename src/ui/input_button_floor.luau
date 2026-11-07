--!strict
local Shared = require("./types")
local ComposeTypes = require("../vendor/compose/core")

local serial = 0
export type Bind = (
	GuiObject,
	boolean,
	{ read x: ComposeTypes.ReadOnlyValue<number>, read y: ComposeTypes.ReadOnlyValue<number> }
) -> ComposeTypes.ReadOnlyValue<boolean>
type Sheets = {
	available: ComposeTypes.Value<boolean>,
	revision: ComposeTypes.Value<number>,
	known: { [StyleSheet]: boolean },
	owner: ComposeTypes.Owner,
}
local sheets: { [ComposeTypes.Runtime]: Sheets } = setmetatable({}, { __mode = "k" })
local buttonFloor = {}

local function sheetsFor(runtime: ComposeTypes.Runtime, Compose: typeof(ComposeTypes)): Sheets
	local record = sheets[runtime]
	if record == nil then
		runtime:watch(function()
			local created: Sheets = {
				available = Compose.cell(false),
				revision = Compose.cell(0),
				known = setmetatable({}, { __mode = "k" }),
				owner = assert(Compose.currentOwner()),
			}
			sheets[runtime] = created
		end)
	end
	return assert(sheets[runtime])
end

function buttonFloor.register(runtime: ComposeTypes.Runtime, Compose: typeof(ComposeTypes), sheet: StyleSheet)
	local record = sheetsFor(runtime, Compose)
	record.known[sheet] = true
	record.available:set(true)
	record.revision:set(record.revision:peek() + 1)
	Compose.cleanup(function()
		record.known[sheet] = nil
		if not Compose.owner.isDisposed(record.owner) then
			record.available:set(next(record.known) ~= nil)
			record.revision:set(record.revision:peek() + 1)
		end
	end)
end

function buttonFloor.create(ctx: Shared.Context)
	local Compose, runtime, Host = ctx.Compose, ctx.runtime, ctx.Host
	local registered = sheetsFor(runtime, Compose)
	local resources: { [StyleSheet]: { [string]: ComposeTypes.AcquireSharedResource<string> } } = setmetatable(
		{},
		{ __mode = "k" }
	)
	local function acquire(sheet: StyleSheet, inline: boolean): string
		local key = if inline then "inline" else "hit"
		local variants = resources[sheet]
		if variants == nil then
			variants = {}
			resources[sheet] = variants
		end
		local resource = variants[key]
		if resource == nil then
			resource = Compose.createSharedResource(function(): (string, () -> ())
				serial += 1
				local tag = "facet-button-floor-" .. serial
				local root = Compose.createRootOwner(function()
					local rule = Host.StyleRule "ButtonTargetFloor" {}
					local floor = ctx.touchFloor()
					local minimum: number?, width: number?
					Compose.watch(function(use: ComposeTypes.Use)
						local nextFloor = floor(use)
						local nextWidth = if inline
							then math.min(nextFloor, ctx.metric("targetSizes.inline", use))
							else nextFloor
						if minimum == nextFloor and width == nextWidth then
							return
						end
						minimum, width = nextFloor, nextWidth
						if nextFloor > 0 then
							rule:SetProperties({
								MinSize = ctx.types.Vector2.new(nextWidth, nextFloor),
							})
						end
						rule.Selector = "."
							.. tag
							.. (if nextFloor > 0 then "" else "-inactive")
							.. "::UISizeConstraint"
					end)
					rule.Parent = sheet
				end, runtime.reactor)
				return tag, root.dispose
			end)
			variants[key] = resource
		end
		return resource()
	end
	local links: { [Instance]: ComposeTypes.AcquireSharedResource<ComposeTypes.ReadOnlyValue<StyleLink?>> } = setmetatable(
		{},
		{ __mode = "k" }
	)
	local function observeLinks(parent: Instance): ComposeTypes.ReadOnlyValue<StyleLink?>
		local resource = links[parent]
		if resource == nil then
			resource = Compose.createSharedResource(function(): (ComposeTypes.ReadOnlyValue<StyleLink?>, () -> ())
				local current = Compose.cell<<StyleLink?>>(parent:FindFirstChildWhichIsA("StyleLink") :: StyleLink?)
				local root = Compose.createRootOwner(function()
					local function changed(child: Instance)
						if child:IsA("StyleLink") then
							current:set(parent:FindFirstChildWhichIsA("StyleLink") :: StyleLink?)
						end
					end
					runtime.connect(parent, "ChildAdded", changed)
					runtime.connect(parent, "ChildRemoved", changed)
				end, runtime.reactor)
				return current, root.dispose
			end)
			links[parent] = resource
		end
		return resource()
	end
	local function bind(
		node: GuiObject,
		inline: boolean,
		extra: { read x: ComposeTypes.ReadOnlyValue<number>, read y: ComposeTypes.ReadOnlyValue<number> }
	): ComposeTypes.ReadOnlyValue<boolean>
		local moved = Compose.cell(0)
		local active = Compose.cell(false)
		runtime.connect(node, "AncestryChanged", function()
			moved:set(moved:peek() + 1)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			use(moved)
			local parent: Instance? = node
			local current: StyleLink? = nil
			while parent do
				current = use(observeLinks(parent))
				if current then
					break
				end
				parent = parent.Parent
			end
			if current == nil or use(extra.x) ~= 0 or use(extra.y) ~= 0 then
				active:set(false)
				return
			end
			local sheet = runtime.observe(current, "StyleSheet")
			Compose.watch(function(inner: ComposeTypes.Use)
				inner(registered.revision)
				local target = inner(sheet) :: StyleSheet?
				if target == nil or not registered.known[target] then
					active:set(false)
					return
				end
				local tag = acquire(target, inline)
				node:AddTag(tag)
				Compose.cleanup(function()
					node:RemoveTag(tag)
				end)
				active:set(true)
			end)
		end)
		return active
	end
	return bind, registered.available
end

return buttonFloor
