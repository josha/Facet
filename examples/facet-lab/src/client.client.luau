--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
type FacetModule = typeof(require("@repo/tools/typecheck/aliases").FacetModule)
type ExampleContext = typeof(require("@repo/examples/types").Context)
type Readable<T> = { peek: (Readable<T>) -> T }
type ThemeModule = typeof(require("@repo/examples/types").ThemeModule)
local loadTheme: (ModuleScript) -> ThemeModule = require

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Facet: FacetModule = require(ReplicatedStorage:WaitForChild("Facet"))
local showcase = require(ReplicatedStorage:WaitForChild("FacetShowcase"):WaitForChild("screen"))
local lab_settings = require(script.Parent.lab_settings)
local catalog = require(script.Parent.catalog)
local browser = require(script.Parent.browser)
local lab_audit = require(script.Parent.lab_audit)
local lab_sweep = require(script.Parent.lab_sweep)
local buildCatalog = (
	catalog.build :: unknown
) :: (typeof(require("@repo/tools/typecheck/aliases").Controls)) -> browser.CatalogData
local runSweep: (unknown, PlayerGui, { string }, unknown) -> unknown = lab_sweep.run
local Compose: ComposeModule = Facet.Compose

pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
assert(playerGui:IsA("PlayerGui"))
local runtime: ComposeRuntime = Facet.Roblox.createRuntime()

local modules = {}
for _, folder in { ReplicatedStorage:WaitForChild("FacetThemes"), ReplicatedStorage:WaitForChild("LabThemes") } do
	for _, module in folder:GetChildren() do
		table.insert(modules, module)
	end
end
local packages = showcase.themePackages(Facet.themes, modules, loadTheme)
local neutral = Facet.themes.define(Facet.themes.neutralPackage())
packages.Neutral = assert(neutral)

local lab = (nil :: unknown) :: typeof(browser.mount(nil :: never))
local owner = Compose.createRootOwner(function()
	local createViewport = (
		Facet.Roblox.createViewport :: unknown
	) :: (Camera) -> Readable<{ width: number, height: number }>
	local viewport = createViewport(assert(workspace.CurrentCamera))

	local ctx = (
		{
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			viewport = viewport,
			guiService = GuiService,
			runService = game:GetService("RunService"),
			worldTarget = workspace,
			inputTarget = playerGui,
			packages = packages,
			types = {
				UDim = UDim,
				UDim2 = UDim2,
				Vector2 = Vector2,
				Color3 = Color3,
				Vector3 = Vector3,
				CFrame = CFrame,
				Path2DControlPoint = Path2DControlPoint,
				FloatCurveKey = FloatCurveKey,
				Rect = Rect,
				NumberSequence = NumberSequence,
				NumberSequenceKeypoint = NumberSequenceKeypoint,
				ColorSequence = ColorSequence,
				ColorSequenceKeypoint = ColorSequenceKeypoint,
				Enum = Enum,
			},
		} :: unknown
	) :: ExampleContext
	showcase.configure(ctx)
	local sceneVisible = Compose.cell(false)
	ctx.sceneVisible = sceneVisible
	ctx.theme = Compose.cell(packages.foundation)
	ctx.themeMode = Compose.cell(packages.foundation.style.defaultTheme)
	ctx.themeName = Compose.cell("foundation")
	local settings = lab_settings.new((ctx :: unknown) :: lab_settings.Context, UserInputService)

	local appOptions: typeof(require("@repo/tools/typecheck/aliases").AppOptions) = {
		runtime = runtime,
		name = "Facet_Lab",
		theme = ctx.theme,
		motionLevel = ctx.motionPreference,
		buttonGuides = settings.buttonGuides,

		environment = settings.environment,
		overlayParent = ctx.overlayParent,
		sheet = {
			theme = ctx.themeMode,
			preferredTransparency = settings.transparency,
			hover = settings.hover,
		},
		screen = { ZIndexBehavior = Enum.ZIndexBehavior.Sibling },
	}
	local app = Facet.app(appOptions)

	local backdrop = Facet.app({
		runtime = runtime,
		name = "Facet_LabBackdrop",
		theme = ctx.theme,
		sheet = { theme = ctx.themeMode },
		screen = { DisplayOrder = -1, IgnoreGuiInset = true, ScreenInsets = Enum.ScreenInsets.None },
	})
	Compose.cleanup(backdrop.dispose)
	backdrop.mount(function()
		local fill = ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
			Name = "Backdrop",
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
			BackgroundTransparency = function(use: <T>(Readable<T>) -> T)
				return if use(sceneVisible) then 1 else 0
			end,
		})
		fill:AddTag("facet-surface")
		return fill
	end)
	Compose.cleanup(app.dispose)
	ctx.UI = app.UI

	local browserContext = (ctx :: unknown) :: browser.Context
	browserContext.preview = showcase.preview
	local controls = (app.UI :: unknown) :: typeof(require("@repo/tools/typecheck/aliases").Controls)
	local catalogData = buildCatalog(controls)
	local browserOptions: browser.MountOpts = {
		Facet = Facet,
		app = app,
		ctx = browserContext,
		settings = settings,
		catalog = catalogData,
	}
	lab = browser.mount(browserOptions)
end, runtime.reactor)

local api = Instance.new("Folder")
api.Name = "FacetLabAPI"
local sweepJob: any = nil
local function answer(value: any): string
	return HttpService:JSONEncode(value)
end
local handlers: { [string]: (string?) -> string } = {
	pages = function()
		return answer(lab.pageIds())
	end,
	open = function(arg)
		return answer(lab.open(tostring(arg)))
	end,
	section = function(arg)
		return answer(lab.section(tostring(arg)))
	end,
	top = function(arg)
		lab.state.top:set(tostring(arg))
		return answer({ top = lab.state.top:peek() })
	end,
	report = function()
		return answer(lab.report())
	end,
	configure = function(arg)
		return answer(lab.configure(tostring(arg)))
	end,
	themes = function()
		return answer(lab.themes())
	end,
	theme = function(arg)
		return answer(lab.setTheme(tostring(arg)))
	end,
	preview = function(arg)
		return answer(lab.settings.set("platform", tostring(arg)))
	end,
	orientation = function(arg)
		return answer(lab.settings.set("orientation", tostring(arg)))
	end,
	distance = function(arg)
		return answer(lab.settings.set("distance", tostring(arg)))
	end,
	motion = function(arg)
		return answer(lab.settings.set("motion", tostring(arg)))
	end,
	transparency = function(arg)
		return answer(lab.settings.set("transparency", tostring(arg)))
	end,
	hover = function(arg)
		return answer(lab.settings.set("hover", tostring(arg)))
	end,
	input = function(arg)
		return answer(lab.settings.set("input", tostring(arg)))
	end,
	text = function(arg)
		return answer(lab.settings.set("text", tostring(arg)))
	end,
	reset = function()
		lab.settings.reset()
		return answer(lab.settings.status())
	end,
	status = function()
		return answer(lab.settings.status())
	end,

	mountSweep = function(arg)
		local out = {}
		local current: any = nil
		local logged = game:GetService("LogService").MessageOut:Connect(function(message, kind)
			if current and (kind == Enum.MessageType.MessageWarning or kind == Enum.MessageType.MessageError) then
				current.console = current.console or {}
				if #current.console < 3 then
					table.insert(current.console, string.sub(message, 1, 200))
				end
			end
		end)
		for _, id in lab.pageIds() do
			local row: any = {}
			current = row
			local ok, err = pcall(lab.open, id)
			row.open = if ok then true else string.sub(tostring(err), 1, 200)
			if arg == "examples" then
				pcall(lab.section, "examples")
			end
			task.wait(0.15)
			local report = lab.report()
			row.refusals = 0
			for where, message in report.errors do
				row.refusals += 1
				row.firstRefusal = row.firstRefusal or `{where}: {message}`
			end

			if table.find(report.missing, id) then
				row.refusals += 1
				row.firstRefusal = "no lab page (catalog PAGE_DATA)"
			end
			out[id] = row
		end
		task.wait(0.2)
		logged:Disconnect()
		return answer(out)
	end,
	sweep = function(arg)
		if sweepJob and sweepJob.running then
			return answer({ running = true, pages = sweepJob.completed })
		end
		local ids: { string } = if arg ~= nil and arg ~= "" then string.split(arg, ",") else lab.pageIds()
		sweepJob = { running = true, completed = {}, current = nil }
		local job = sweepJob
		task.spawn(function()
			local ok, result = pcall(runSweep, lab, playerGui, ids, {
				runtime = runtime,
				inputPriority = Facet.inputPriority.aboveFacet,
				progress = function(row, complete)
					job.current = row.id
					if complete then
						job.completed[row.id] = row
					end
				end,
			})
			job.running = false
			if ok then
				job.result = result
			else
				job.error = tostring(result)
			end
		end)
		return answer({ running = true, ids = ids })
	end,
	sweepReport = function(arg)
		local job = sweepJob or { running = false, completed = {} }
		local rows = {}
		local ids: { string } = if arg ~= nil and arg ~= "" then string.split(arg, ",") else lab.pageIds()
		for _, id in ids do
			rows[id] = job.completed[id]
		end
		return answer({ running = job.running, current = job.current, completed = rows, error = job.error })
	end,

	probe = function(arg)
		local ids: { string } = if arg ~= nil and arg ~= "" then string.split(arg, ",") else lab.pageIds()
		local out = {}
		for _, id in ids do
			lab.open(id)
			task.wait(0.1)
			local refused = lab.probe()
			if #refused > 0 then
				table.insert(out, `{id}:\n  {table.concat(refused, "\n  ")}`)
			end
		end
		return table.concat(out, "\n")
	end,

	audit = function(arg)
		local ids: { string } = if arg ~= nil and arg ~= "" then string.split(arg, ",") else lab.pageIds()
		return lab_audit({
			open = lab.open,
			report = function()
				return { errors = lab.report().errors }
			end,
		}, playerGui, ids)
	end,
}
for name, impl in handlers do
	local bf = Instance.new("BindableFunction")
	bf.Name = name
	bf.OnInvoke = impl
	bf.Parent = api
end
api.Parent = workspace
workspace:SetAttribute("FacetLabReady", true)
print(
	`[FacetLab] Facet {Facet.VERSION} — {#lab.pageIds()} pages, {#lab.themes().entries} theme packages, build {workspace:GetAttribute(
		"Facet_Build"
	)}`
)
script.Destroying:Connect(function()
	owner.dispose()
	runtime:dispose()
end)
