--!strict
-- Scenario 'examples': the seven TUTORIAL EXAMPLES, inside the verification
-- surface (roadmap Step 10, docs/plans/example-quality-pass.md).
--
-- WHY THIS EXISTS. Until this stage the seven examples were reachable only
-- through the gallery bootstrap's `LuauUI_Example` attribute, which mounts them
-- and stamps two workspace attributes and nothing else. Every other stage's
-- evidence rides `_G.LuauUIScenario` / `workspace.LuauUIScenarioAPI` —
-- `report`/`step`/`reset`/`setEnv`/`freezeEnv` — and the five-view device matrix
-- driver (`tools/studio/device_matrix.luau`) reads that API and nothing else. So
-- the examples were structurally outside the matrix: not because a rule excluded
-- them, but because there was no handle to hold them by.
--
-- This scenario is that handle. It owns NO UI of its own: it builds one tutorial
-- example, verbatim, through the same `(LuauUI, core, deps)` contract the
-- bootstrap uses, and hands the runner exactly what the bootstrap would have
-- presented. What it adds is the DRIVE surface the matrix needs — select an
-- example, swap the theme package, read back what is mounted — so the same
-- automation that proves a Sponsor fixture can prove a tutorial.
--
-- TWO BUILD SHAPES, one rule (docs/guide/04-tutorial-examples.md): examples 1–4
-- return `{ screen, present }` for the caller to present; the game examples 5–7
-- present THEMSELVES and return `{ handle }`. The runner already reads that rule
-- (`if built.screen ~= nil and built.handle == nil then present`), so passing
-- both fields straight through is enough — a self-presenting example arrives with
-- its handle set and is not mounted twice.
--
-- Select before Play with the workspace attribute `LuauUI_Example` (1..7), or at
-- runtime with `step("select", <n>)`. The theme package is `LuauUI_ThemePackage`
-- before Play, or `step("theme", "<moduleName>")` at runtime.

local MODULES = {
	"01_temperature_converter",
	"02_playlist_table",
	"03_settings_sync",
	"04_confirm_dialog",
	"05_word_game",
	"06_tile_game",
	"07_match3",
}

return {
	title = "Tutorial examples (Step 10)",
	ledgerRows = { "EQ-1", "EQ-3", "EQ-5", "EQ-6", "EQ-14", "EQ-16" },
	build = function(ctx: any)
		-- The example modules replicate as ModuleScripts under
		-- ReplicatedStorage.LuauUIExamples, exactly like the reference theme
		-- packages under LuauUIThemes. Resolving them is RUNNER-SHAPED work — an
		-- instance path — but this module has no other way to reach them and the
		-- runner has no reason to know about tutorials, so it happens here and
		-- degrades loudly rather than mounting nothing.
		local folder = ctx.exampleModules
		if folder == nil then
			local ok, found = pcall(function()
				return game:GetService("ReplicatedStorage"):FindFirstChild("LuauUIExamples")
			end)
			folder = if ok then found else nil
		end

		local selected = 1
		local flagged = ctx.flags and ctx.flags.example
		if type(flagged) == "number" and MODULES[flagged] ~= nil then
			selected = flagged
		end

		local current: any = nil
		local currentName = ""
		local mountError: string? = nil

		local function disposeCurrent()
			if current == nil then
				return
			end
			if current.dispose ~= nil then
				pcall(current.dispose)
			end
			if current.handle ~= nil and ctx.presenter.dismiss ~= nil then
				pcall(function()
					ctx.presenter.dismiss(current.handle)
				end)
			end
			current = nil
		end

		local function buildExample(index: number)
			disposeCurrent()
			mountError = nil
			local name = MODULES[index]
			if name == nil then
				mountError = `no tutorial example {tostring(index)} (1..{#MODULES})`
				return
			end
			currentName = name
			if folder == nil then
				mountError = "ReplicatedStorage.LuauUIExamples is not present"
				return
			end
			local module = folder:FindFirstChild(name)
			if module == nil then
				mountError = `LuauUIExamples.{name} is missing`
				return
			end
			local ok, built = pcall(function()
				local example = require(module) :: any
				return example.build(ctx.LuauUI, ctx.core, {
					env = ctx.env,
					actionSystem = ctx.actionSystem,
					presenter = ctx.presenter,
					adapter = ctx.adapter,
				})
			end)
			if not ok then
				mountError = tostring(built)
				return
			end
			current = built
			selected = index
			-- 1–4 hand back a screen for the caller; 5–7 present themselves. A
			-- re-select happens AFTER the runner's initial mount, so this module
			-- has to do the presenting the runner would otherwise have done.
			if current.screen ~= nil and current.handle == nil then
				current.handle = ctx.presenter.present(current.screen, current.present)
			end
		end

		buildExample(selected)

		-- the theme controller is late-bound by the runner and may be absent; a
		-- swap that cannot happen says so rather than reporting success
		-- ONE CONTROLLER AT A TIME, AND THIS SCENARIO OWNS IT (found live
		-- 2026-08-06). `theme_controller.install` REFUSES a second controller on an
		-- environment that already has one — "the ThemeSnapshot rides the single
		-- 'themeMetrics' fact — the two would overwrite each other" — and returns a
		-- reason rather than throwing. A swap loop that ignored that installed
		-- Fantasy Parchment once and then silently kept it for every later request,
		-- including the restore: the capture pair read `ornate / ornate` and called
		-- it a swap. So the live controller is held here and UNINSTALLED before the
		-- next install, and every swap reports the refusal it got.
		local installed: any = nil
		local function uninstallCurrent()
			if installed == nil then
				return
			end
			pcall(function()
				installed.uninstall()
			end)
			installed = nil
		end

		-- "neutral" is not a module and never was: Studio Neutral is the built-in
		-- package the library ships with, so restoring it means installing
		-- `themes.neutralPackage()` rather than looking for a file. Naming it here
		-- is what makes a capture pair — ornate, then back — a single drive.
		local function swapPackage(moduleName: string): any
			local packages = ctx.themePackages or {}
			if moduleName == "neutral" or moduleName == "studio-neutral" or moduleName == "studio_neutral" then
				local controllerModule = if type(ctx.themeController) == "function" then ctx.themeController() else nil
				if controllerModule == nil then
					return { ok = false, reason = "theme controller unavailable" }
				end
				uninstallCurrent()
				local ok, err = pcall(function()
					installed = controllerModule.install(
						ctx.adapter,
						ctx.LuauUI.themes.neutralPackage(),
						{ env = ctx.env, core = ctx.core }
					)
				end)
				return { ok = ok, reason = if ok then nil else tostring(err), package = "neutral" }
			end
			local module = packages[moduleName]
			if module == nil then
				local known = {}
				for key in packages do
					table.insert(known, key)
				end
				table.sort(known)
				return { ok = false, reason = `no package module '{moduleName}'`, known = known }
			end
			local controllerModule = if type(ctx.themeController) == "function" then ctx.themeController() else nil
			if controllerModule == nil then
				return { ok = false, reason = "theme controller unavailable" }
			end
			-- POSITIONAL, not a bag: `theme_controller.install(adapter, package, opts)`.
			-- Handing it one options table put the adapter where the package belongs
			-- and it refused with "expected a package compiled by themes.define" —
			-- the assert doing its job on a caller that had guessed the signature.
			uninstallCurrent()
			local ok, err = pcall(function()
				local package = (module :: any).build(ctx.LuauUI.themes)
				installed = controllerModule.install(ctx.adapter, package, { env = ctx.env, core = ctx.core })
			end)
			return { ok = ok, reason = if ok then nil else tostring(err), package = moduleName }
		end

		return {
			-- passed straight through: the runner presents a screen only when the
			-- example did not present itself
			screen = if current ~= nil then current.screen else nil,
			present = if current ~= nil then current.present else nil,
			handle = if current ~= nil then current.handle else nil,

			-- STATE/ACTION DRIVERS. None of these is hardware-input evidence and the
			-- runner labels them as such; the native rows are driven through
			-- VirtualInput by the matrix driver against the geometry `report` exports.
			--
			-- THE SIGNATURE IS `(built, payload)`. The runner calls a step as
			-- `fn(session.built, payload)` and the BindableFunction carries ONE
			-- string, so a parameterized step arrives as `"name:payload"` and the
			-- payload is a STRING. A step written as `function(arg)` silently
			-- receives the built table instead — which reads as "select was given a
			-- table" long after the mistake.
			steps = {
				select = function(_built: any, payload: string?)
					local index = tonumber(payload) or 0
					buildExample(math.floor(index))
					return { example = selected, module = currentName, error = mountError }
				end,
				next = function()
					buildExample(if selected >= #MODULES then 1 else selected + 1)
					return { example = selected, module = currentName, error = mountError }
				end,
				theme = function(_built: any, payload: string?)
					return swapPackage(tostring(payload))
				end,
				list = function()
					return MODULES
				end,
			},

			report = function()
				local title: string? = nil
				if current ~= nil then
					local ok, value = pcall(function()
						return current.title
					end)
					title = if ok and type(value) == "string" then value else nil
				end
				return {
					example = selected,
					module = currentName,
					title = title,
					mounted = current ~= nil,
					-- a self-presenting example versus one the caller presents:
					-- recorded because it decides whether the runner mounted it
					selfPresenting = current ~= nil and current.screen == nil,
					error = mountError,
					modules = MODULES,
				}
			end,

			dispose = function()
				uninstallCurrent()
				disposeCurrent()
			end,
		}
	end,
}
