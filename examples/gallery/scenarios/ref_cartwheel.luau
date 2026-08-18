--!strict
-- Scenario 'ref_cartwheel': reference proof "Cartwheel" (RA-P2,
-- docs/plans/swiftui-reference-app-validation.md). THIN BY DESIGN: the proof
-- module owns its blueprints, fake services, steps and report; this file only
-- locates it through the runner-resolved folder (engine-free, path-free) and
-- hands its build straight through — the same delegation shape scenario
-- 'examples' uses for the tutorial examples.
return {
	keyboardFirst = true,
	title = "Reference proof: Cartwheel",
	ledgerRows = { "RA-P2" },
	build = function(ctx: any)
		local folder = ctx.referenceModules
		if folder == nil then
			error("ReplicatedStorage.FacetReference is not replicated (gallery.project.json maps examples/reference)")
		end
		local module = folder:FindFirstChild("p2_cartwheel")
		if module == nil then
			error("FacetReference.p2_cartwheel is missing")
		end
		local proof = require(module) :: any
		local built = proof.build(ctx.Facet, ctx.core, {
			env = ctx.env,
			actionSystem = ctx.actionSystem,
			presenter = ctx.presenter,
			adapter = ctx.adapter,
			facts = ctx.facts,
			themePackages = ctx.themePackages,
			stage = ctx.stage,
		})
		-- GENERIC KEYBOARD-ROW STEPS (device-matrix keyboard mode): every proof
		-- gets the armKeys/readKeys/focusOrder bracket the driver expects — raw
		-- input from the runner's telemetry seam, semantic actions from the
		-- presenter's own feedback bus. State/action drivers, labeled: never
		-- hardware-input evidence by themselves.
		built.steps = built.steps or {}
		if built.steps.armKeys == nil then
			local actionLog: { any } = {}
			local unsubscribe: any = nil
			built.steps.armKeys = function()
				ctx.telemetry.keyLog.arm()
				table.clear(actionLog)
				if unsubscribe == nil then
					unsubscribe = ctx.presenter.onFeedback(function(event: any)
						table.insert(actionLog, { type = event.type, path = event.path })
					end)
				end
				return { armed = true, focus = ctx.presenter.focus.focused:get() }
			end
			built.steps.readKeys = function()
				ctx.presenter.refresh()
				ctx.telemetry.step()
				return {
					rawInput = ctx.telemetry.keyLog.read(),
					actions = actionLog,
					focus = ctx.presenter.focus.focused:get(),
				}
			end
			built.steps.focusOrder = function(b: any)
				local handle = b and b.handle
				if handle == nil or handle.focusOrder == nil then
					return { ok = false }
				end
				local dump = handle.focusOrder()
				local traversal = {}
				for _, e in dump.traversal do
					table.insert(traversal, e.path)
				end
				return { scope = dump.scope, traversal = traversal }
			end
			built.steps.focusOn = function(_b: any, payload: string?)
				if payload == nil then
					return { ok = false }
				end
				local ok = ctx.presenter.focus.focusOn(payload)
				ctx.presenter.focus.setFocusOrigin("navigation")
				return { ok = ok }
			end
		end
		-- GENERIC THEME AXIS (RA-M3): install a reference package by module name
		-- through the same controller path the tutorial-examples scenario uses.
		-- Boot: the Facet_ThemePackage workspace attribute; live: step "theme:<name>".
		local installedTheme: any = nil
		local function installTheme(moduleName: string): any
			local controllerModule = if type(ctx.themeController) == "function" then ctx.themeController() else nil
			if controllerModule == nil then
				return { ok = false, reason = "theme controller unavailable" }
			end
			local package
			if moduleName == "neutral" or moduleName == "studio_neutral" then
				package = ctx.Facet.themes.neutralPackage()
			else
				local module = (ctx.themePackages or {})[moduleName]
				if module == nil then
					return { ok = false, reason = `no package module '{moduleName}'` }
				end
				-- a theme module exports a BUILDER; the compiled package comes
				-- from build(themes) (same call the examples scenario makes)
				package = (module :: any).build(ctx.Facet.themes)
			end
			if installedTheme ~= nil and installedTheme.uninstall ~= nil then
				pcall(installedTheme.uninstall)
				installedTheme = nil
			end
			local ok, err = pcall(function()
				installedTheme = controllerModule.install(ctx.adapter, package, { env = ctx.env, core = ctx.core })
			end)
			return { ok = ok, reason = if ok then nil else tostring(err), package = moduleName }
		end
		built.steps.theme = function(_b: any, payload: string?)
			if payload == nil then
				return { ok = false }
			end
			return installTheme(payload)
		end
		local bootTheme = ctx.attributes and ctx.attributes.themePackage
		if type(bootTheme) == "string" and bootTheme ~= "" then
			installTheme(bootTheme)
		end
		return built
	end,
}
