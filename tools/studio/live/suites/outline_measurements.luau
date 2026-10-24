--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type NumberCell = typeof(require("@repo/tools/typecheck/aliases").NumberCell)
type NumberMapCell = typeof(require("@repo/tools/typecheck/aliases").NumberMapCell)
type OutlineSpec = typeof(require("@repo/tools/typecheck/aliases").OutlineMeasurementSpec)
type OutlineRecord = { id: string, children: { OutlineRecord }? }

type Context = {
	mount: (
		build: (FacetControls, RobloxHost, ComposeModule) -> unknown,
		options: { size: Vector2, frames: number }
	) -> Instance,
	settle: (number) -> (),
	check: (string, boolean, unknown?) -> (),
	near: (string, number, number, number?) -> (),
}

local function run(t: Context)
	local setExternal: ({ [string]: number }) -> () = function()
		error("the outline is not mounted")
	end
	local setMinimum: (number) -> () = function()
		error("the outline is not mounted")
	end
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
		local initial: { [string]: number } = { child = 90 }
		local external: NumberMapCell = Compose.cell(initial)
		local minimum: NumberCell = Compose.cell(20)
		setExternal = function(value)
			external:set(value)
		end
		setMinimum = function(value)
			minimum:set(value)
		end
		local records: { OutlineRecord } = { { id = "folder", children = { { id = "child" } } } }
		local spec: OutlineSpec = {
			Name = "MeasuredOutline",
			from = records,
			key = "id",
			children = "children",
			expanded = Compose.cell({ folder = true }),
			mode = "all",
			itemSize = minimum,
			measure = true,
			measured = external,
			render = function(): Frame
				return Host.Frame({ Size = UDim2.fromOffset(100, 35) })
			end,
		}
		return UI.Outline(spec)
	end, { size = Vector2.new(600, 400), frames = 20 })
	local root = assert(stage:FindFirstChild("MeasuredOutline", true))
	local row = assert(root:FindFirstChild("child", true))
	local content = assert(row:FindFirstChild("Content"))
	local observed = assert(row:FindFirstChild("OutlineRow", true))
	assert(content:IsA("GuiObject") and observed:IsA("GuiObject"))
	t.near("external measurements set native content height", content.AbsoluteSize.Y, 90, 0.5)
	setExternal({ child = 0 })
	t.settle(8)
	t.near("a zero override keeps the authored minimum height", content.Size.Y.Offset, 20, 0.5)
	t.check("native layout respects the minimum height", content.AbsoluteSize.Y >= 20)
	setExternal({})
	t.settle(8)
	t.near(
		"native measured height supplies the fallback",
		content.AbsoluteSize.Y,
		math.max(20, observed.AbsoluteSize.Y),
		0.5
	)
	setMinimum(80)
	t.settle(8)
	t.near(
		"minimum updates reach native content geometry",
		content.AbsoluteSize.Y,
		math.max(80, observed.AbsoluteSize.Y),
		0.5
	)
	setExternal({ child = 100 })
	t.settle(8)
	t.near("external updates reach native content geometry", content.AbsoluteSize.Y, 100, 0.5)
	t.check("measurement updates retain the mounted row", root:FindFirstChild("child", true) == row)
end

return { { id = "outline-measured-content-keeps-native-height-and-row-identity", contracts = {}, run = run } }
