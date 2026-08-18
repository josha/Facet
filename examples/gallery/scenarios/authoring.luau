--!strict
-- Scenario 'authoring': Milestone 0 acceptance rows M0-A1 / M0-A4 in the REAL
-- running client (agent-execution-contract §3 E3).
--
-- The headless suite proves that `blueprint.make` raises. What it cannot prove
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

attempt("unknownProp", "a misspelled property must not freeze into the node", function(ctx)
	return ctx.UI.Button({ id = "Bad", lable = "Save" })
end)

attempt("foreignProp", "a property borrowed from another control must be rejected", function(ctx)
	return ctx.UI.VStack({ id = "Bad", columns = 3 })
end)

attempt("wrongType", "a wrongly typed value must name the expected type", function(ctx)
	return ctx.UI.VStack({ id = "Bad", gap = "8" })
end)

attempt("bareNumberDim", "a bare number where a dimension belongs must be rejected", function(ctx)
	return ctx.UI.Box({ id = "Bad", width = 120 })
end)

attempt("missingRequired", "a missing required property must be named", function(ctx)
	return ctx.UI.Text({ id = "Bad" })
end)

attempt("childrenOnLeaf", "children on a leaf must be rejected", function(ctx)
	return ctx.UI.Text({ id = "Bad", text = "x", children = { ctx.UI.Box({ id = "c" }) } })
end)

attempt("signalOnStaticProp", "a Signal on a mount-time-only prop must be rejected", function(ctx)
	return ctx.UI.ScrollView({ id = "Bad", axis = ctx.core:signal("x") })
end)

attempt("deadPropColor", "Text.color never reached a render target and must be diagnosed", function(ctx)
	return ctx.UI.Text({ id = "Bad", text = "x", color = { r = 1, g = 0, b = 0 } })
end)

attempt("deadPropFont", "Text.font reached measure but never paint and must be diagnosed", function(ctx)
	return ctx.UI.Text({ id = "Bad", text = "x", font = "Gotham" })
end)

return {
	title = "Strict public authoring",
	ledgerRows = { "M0-A1", "M0-A4" },
	build = function(ctx: any)
		local UI = ctx.Facet.UI
		local core = ctx.core
		local results: { [string]: any } = {}
		local summary = core:signal("no attempts run")

		-- a VALID screen: strictness must not disturb ordinary authoring, and
		-- this is what the capture shows
		local screen = UI.Screen({
			id = "AuthoringScreen",
			padding = 16,
			gap = 10,
			children = {
				UI.Text({ id = "Title", text = "Strict public authoring", textSize = 22 }),
				UI.Text({ id = "Summary", text = summary, textSize = 14 }),
				-- A horizontal ScrollView rather than the original HStack (overflow
				-- sweep, 2026-08-12): the button's and toggle's own hug-sized labels
				-- ran 43-82px past a narrow phone's width with nothing to move them.
				-- Neither control has a natural width safe to guess (localization can
				-- widen either label ~1.4x), so a ScrollView — which never clamps its
				-- scroll-axis content — keeps both exactly the size authoring produced
				-- rather than risking a Grid squeezing one control's label to fit a
				-- derived column.
				UI.ScrollView({
					id = "Row",
					axis = "x",
					gap = 8,
					children = {
						UI.Button({ id = "Valid", label = "Valid button" }),
						UI.Toggle({ id = "ValidToggle", label = "Valid toggle", value = core:signal(false) }),
					},
				}),
				UI.Grid({
					id = "ValidGrid",
					minColumnWidth = 90,
					gap = 6,
					children = {
						-- fill cells occupy their derived column (A-LV1). Before the
						-- solver fix these rendered at the right column origins with
						-- ZERO width, which is how the defect was found live.
						UI.Box({
							id = "g1",
							surface = "raised",
							width = { type = "fill", weight = 1 },
							height = { type = "fixed", px = 40 },
						}),
						UI.Box({
							id = "g2",
							surface = "raised",
							width = { type = "fill", weight = 1 },
							height = { type = "fixed", px = 40 },
						}),
						UI.Box({
							id = "g3",
							surface = "raised",
							width = { type = "fill", weight = 1 },
							height = { type = "fixed", px = 40 },
						}),
					},
				}),
			},
		})

		local ctxForAttempts = { UI = UI, core = core }

		local function runAll()
			local raisedCount, builtCount = 0, 0
			for _, a in ATTEMPTS do
				local ok, err = pcall(a.run, ctxForAttempts)
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
			screen = screen,
			steps = {
				-- Each attempt calls a PUBLIC constructor in the running client;
				-- the failure is the framework's own boundary, not a test harness
				-- assertion. `built > 0` is an acceptance FAILURE.
				runAllAttempts = runAll,
			},
			report = function()
				return { attempts = results, summary = summary:get() }
			end,
		}
	end,
}
