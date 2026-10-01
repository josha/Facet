--!strict

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Facet = require(ReplicatedStorage:WaitForChild("Facet")) :: any
local showcase = require(ReplicatedStorage:WaitForChild("FacetShowcase"):WaitForChild("screen")) :: any
local lab_settings = require(script.Parent.lab_settings) :: any
local catalog = require(script.Parent.catalog) :: any
local browser = require(script.Parent.browser) :: any
local lab_audit = require(script.Parent.lab_audit) :: any
local Compose = Facet.Compose

pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local runtime = Facet.Roblox.createRuntime()

local modules = {}
for _, folder in { ReplicatedStorage:WaitForChild("FacetThemes"), ReplicatedStorage:WaitForChild("LabThemes") } do
	for _, module in folder:GetChildren() do
		table.insert(modules, module)
	end
end
local packages = showcase.themePackages(Facet.themes, modules, function(module)
	return require(module) :: any
end)
packages.Neutral = assert(Facet.themes.define(Facet.themes.neutralPackage()))

local lab: any
local owner = Compose.createRootOwner(function()
	local viewport = Facet.Roblox.createViewport(workspace.CurrentCamera)

	local ctx: any = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
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
	}
	showcase.configure(ctx)
	ctx.theme = Compose.cell(packages.foundation)
	ctx.themeMode = Compose.cell(packages.foundation.style.defaultTheme)
	ctx.themeName = Compose.cell("foundation")
	local settings = lab_settings.new(ctx, UserInputService)
	ctx.preview = showcase.preview

	local app = Facet.app({
		runtime = runtime,
		name = "Facet_Lab",
		theme = ctx.theme,
		motionLevel = ctx.motionPreference,

		environment = settings.environment,
		overlayParent = ctx.overlayParent,
		sheet = {
			theme = ctx.themeMode,
			preferredTransparency = settings.transparency,
			hover = settings.hover,
		},
		screen = { ZIndexBehavior = Enum.ZIndexBehavior.Sibling },
	})

	local backdrop = Facet.app({
		runtime = runtime,
		name = "Facet_LabBackdrop",
		theme = ctx.theme,
		sheet = { theme = ctx.themeMode },
		screen = { DisplayOrder = -1, IgnoreGuiInset = true, ScreenInsets = Enum.ScreenInsets.None },
	})
	Compose.cleanup(backdrop.dispose)
	backdrop.mount(function()
		local fill =
			runtime.constructors.Frame({ Name = "Backdrop", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 })
		fill:AddTag("facet-surface")
		return fill
	end)
	Compose.cleanup(app.dispose)
	ctx.UI = app.UI

	lab = browser.mount({
		Facet = Facet,
		app = app,
		ctx = ctx,
		settings = settings,
		catalog = catalog.build(app.UI),
	})
end, runtime.reactor)

local api = Instance.new("Folder")
api.Name = "FacetLabAPI"
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

	sweep = function(arg)
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

	probe = function(arg)
		local ids = if arg ~= nil and arg ~= "" then string.split(arg, ",") else lab.pageIds()
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
		local ids = if arg ~= nil and arg ~= "" then string.split(arg, ",") else lab.pageIds()
		return lab_audit(lab, playerGui, ids)
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
