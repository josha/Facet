--!strict
-- Scenario 'authoring': Milestone 0 acceptance rows M0-A1 / M0-A4 in the REAL
-- running client (agent-execution-contract §3 E3).
--
-- The headless suite proves that the constructors raise. What it cannot prove
-- is that the SHIPPED library — the exact source replicated into a play
-- session — raises the same way, with the same message, before anything
-- reaches the adapter. This scenario mounts a valid screen and then, on
-- demand, attempts each documented authoring mistake through the same public
-- constructors a developer would call, reporting the raised message verbatim.
--
-- Every attempt is expected to FAIL. A step that returns `raised = false` is an
-- acceptance failure, not a passing test: it means an invalid screen built
-- successfully in the running client.

local ATTEMPTS: { { id: string, why: string, run: (any) -> any } } = {}

local function attempt(id: string, why: string, run: (any) -> any)
	table.insert(ATTEMPTS, { id = id, why = why, run = run })
end

attempt("unknownProp", "a misspelled property must not reach the node", function(ctx)
	return ctx.UI.Button("Bad")({ lable = "Save", onActivate = function() end })
end)

attempt("foreignProp", "a property borrowed from another control must be rejected", function(ctx)
	return ctx.UI.VStack("Bad")({ columns = 3 })
end)

attempt("wrongType", "a wrongly typed value must name the expected type", function(ctx)
	return ctx.UI.VStack("Bad")({ gap = "8" })
end)

attempt("bareNumberDim", "a bare number where a dimension belongs must be rejected", function(ctx)
	return ctx.UI.Box("Bad")({ width = 120 })
end)

attempt("missingRequired", "a missing required property must be named", function(ctx)
	return ctx.UI.Text("Bad")({})
end)

attempt("childrenOnLeaf", "children on a leaf must be rejected", function(ctx)
	return ctx.UI.Text("Bad")({ text = "x", ctx.UI.Box("c")({}) })
end)

attempt("signalOnStaticProp", "a cell on a mount-time-only prop must be rejected", function(ctx)
	return ctx.UI.Box("Bad")({ zIndex = ctx.Compose.cell(2) })
end)

attempt("deadPropColor", "Text.color never reached a render target and must be diagnosed", function(ctx)
	return ctx.UI.Text("Bad")({ text = "x", color = { r = 1, g = 0, b = 0 } })
end)

attempt("deadPropFont", "Text.font reached measure but never paint and must be diagnosed", function(ctx)
	return ctx.UI.Text("Bad")({ text = "x", font = "Gotham" })
end)

return {
	title = "Strict public authoring",
	ledgerRows = { "M0-A1", "M0-A4" },
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local results: { [string]: any } = {}
		local summary = Compose.cell("no attempts run")

		-- a VALID screen: strictness must not disturb ordinary authoring, and
		-- this is what the capture shows
		local function Example()
			return UI.Screen("AuthoringScreen")({
				padding = "m",
				gap = 10,

				UI.Text("Title")({ text = "Strict public authoring", textSize = 22 }),
				UI.Text("Summary")({ text = summary, textSize = "label" }),
				-- A horizontal ScrollView: the button's and toggle's hug-sized labels
				-- run past a narrow phone's width, and a ScrollView never clamps its
				-- scroll-axis content, so both stay the size authoring produced.
				UI.ScrollView("Row")({
					axis = "x",
					gap = "s",

					UI.Button("Valid")({ label = "Valid button", onActivate = function() end }),
					UI.Toggle("ValidToggle")({ label = "Valid toggle", value = Compose.cell(false) }),
				}),
				UI.Grid("ValidGrid")({
					-- NOT `"intrinsic"`: every cell here is `fill` width, and a fill child cannot
					-- express an intrinsic minimum (it measures to whatever it is offered), so the
					-- grid would fall back to ONE LANE and the thing this fixture demonstrates —
					-- fill cells occupying their derived columns — would have nothing to show.
					minColumnWidth = 90,
					gap = "tight",

					-- fill cells occupy their derived column (A-LV1)
					UI.Box("g1")({ surface = "raised", width = UI.fill(), height = { type = "fixed", px = 40 } }),
					UI.Box("g2")({ surface = "raised", width = UI.fill(), height = { type = "fixed", px = 40 } }),
					UI.Box("g3")({ surface = "raised", width = UI.fill(), height = { type = "fixed", px = 40 } }),
				}),
			})
		end

		local ctxForAttempts = { UI = UI, Compose = Compose }

		-- An attempt is a whole screen mounted through the application, which is
		-- where a developer's mistake surfaces. One that mounts is dismissed at once.
		local function mountAttempt(run: (any) -> any)
			local function component()
				return UI.Screen("AuthoringAttempt")({ run(ctxForAttempts) })
			end
			if ctx.app ~= nil then
				local close = ctx.app.mount(component)
				close()
			else
				ctx.presenter.dismiss(ctx.presenter.present(component))
			end
		end

		local function runAll()
			local raisedCount, builtCount = 0, 0
			for _, a in ATTEMPTS do
				local ok, err = pcall(mountAttempt, a.run)
				results[a.id] = {
					why = a.why,
					raised = not ok,
					message = if ok then nil else tostring(err),
				}
				if ok then
					builtCount += 1
				else
					raisedCount += 1
				end
			end
			summary:set(string.format("%d/%d invalid screens rejected at construction", raisedCount, #ATTEMPTS))
			return { attempts = #ATTEMPTS, raised = raisedCount, built = builtCount, results = results }
		end

		return {
			screen = Example,
			steps = {
				-- Each attempt calls a PUBLIC constructor in the running client;
				-- the failure is the framework's own boundary, not a test harness
				-- assertion. `built > 0` is an acceptance FAILURE.
				runAllAttempts = runAll,
			},
			report = function()
				return { attempts = results, summary = summary:peek() }
			end,
		}
	end,
}
