--!strict
-- Scenario 'keyboard_navigation': the roadmap Step 8 desktop keyboard fixture
-- (docs/plans/desktop-keyboard-navigation.md; acceptance row DK-17).
--
-- ONE screen carrying every surface the plan names — a form, a scrollable list,
-- a TextInput, a Slider and a Stepper — plus a modal a step opens. Raw
-- Tab/Shift+Tab/Space/Return/arrow events are driven into it with VirtualInput
-- by tools/studio/device_matrix.luau's `keyboard` mode; this module is the
-- OBSERVATION half: it presents its own surface so it can subscribe to the
-- semantic actions themselves, and its report pairs, per press:
--
--   raw input  (the runner's keyLog: UserInputType/KeyCode/gameProcessed)
--   semantic action  (Traverse / Activate / Adjust / Navigate, with direction)
--   focus      (the path before and after)
--   scroll     (the list host's live CanvasPosition)
--   state      (the slider/stepper values, the field's text and editing flag)
--   responder  (the surface's own responder readable)
--   lifecycle  (surface depth, context enabled/sink, live keyboard bindings)
--
-- A screenshot of this fixture is not evidence on its own; the pairing is.
--
-- THE SCREEN BODY SCROLLS: the field/actions/slider/stepper/list column lives
-- inside a `UI.ScrollView` (`Body`) below, one path segment deeper than the
-- screen itself — every surface this module names (Volume, Count, List, Name,
-- Actions/Save, Actions/Reset) now resolves under `/KbdNav/Body/...`.

return {
	title = "Desktop keyboard focus chain",
	ledgerRows = { "DK-17" },
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core

		local fieldValue = core:signal("racer")
		local commits = core:signal(0)
		local volume = core:signal(0.5)
		local count = core:signal(3)
		local saved = core:signal(0)

		local field = Facet.Controls.TextInput(core, {
			id = "Name",
			value = fieldValue,
			placeholder = "Name",
			onCommit = function()
				commits:set(commits:get() + 1)
			end,
		})
		local slider = Facet.Controls.Slider(core, {
			id = "Volume",
			value = volume,
			min = 0,
			max = 1,
			step = 0.1,
		})
		local stepper = Facet.Controls.Stepper(core, {
			id = "Count",
			value = count,
			min = 0,
			max = 10,
			step = 1,
		})

		local rows = {}
		for i = 1, 12 do
			table.insert(
				rows,
				UI.Button({
					id = "Row" .. i,
					label = "Row " .. i,
					--[[ A FLOOR, NOT A BOX (wave TEN-FOOT, 2026-08-20). This was a
						literal `fixed 36`, which is Studio Neutral's compact rung spelled
						as a number — so it neither followed a denser package down nor the
						ten-foot ladder up, and at distance the scaled button padding
						(12 -> 18, twice) filled the 36px row exactly and left the label
						nowhere to draw. A row is "at least a compact control, and taller
						if its own label needs it", which is what this says. ]]
					height = { type = "minMax", min = "controlSizes.compact.height" },
				})
			)
		end

		-- THE SCREEN BODY SCROLLS (BodyScroll precedent, adaptive_controls.luau).
		-- The field, the actions row, the slider, the stepper and the 150px row
		-- list are content-sized in total, and on a short landscape phone their
		-- sum already exceeds the box the screen offers before `List` even gets
		-- to scroll ITS OWN twelve rows — found live by the overflow sweep at
		-- 705x338 and 640x320 (221px/239px over). `List` keeps its own inner
		-- ScrollView unchanged (it is the DK-17 plan's own scrollable-list
		-- surface); this only gives the PAGE a second, outer place to go.
		local screen = UI.Screen({
			id = "KbdNav",
			-- THEME-OPT-OUT: the page's own gutter is what leaves this screen 242px of
			-- usable width on a 320px phone, and the Actions row below is already recorded
			-- in the overflow ledger as 145px too wide there at +14. `padding = "m"` under
			-- glossy-touch narrows it further and measured 149px. The gutter waits on the
			-- row it squeezes.
			padding = 16,
			children = {
				UI.ScrollView({
					id = "Body",
					axis = "y",
					gap = 10,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = "Desktop keyboard focus chain", textSize = 22 }),
						field.blueprint,
						-- an HStack of two focusables is what engages the LAYOUT group
						-- derivation, so this fixture is a GROUPED screen — the case
						-- where Left/Right used to belong permanently to NavigateH
						UI.HStack({
							id = "Actions",
							-- THEME-OPT-OUT: same standing as the page padding above — this two-button row
							-- is already 145px past a 320x640 phone at +14 in the overflow ledger, and
							-- `gap = "s"` under glossy-touch measured 151px. A theme step cannot fix a row
							-- that does not fit; it can only make the recorded number worse.
							gap = 8,
							children = {
								UI.Button({ id = "Save", label = "Save" }),
								UI.Button({ id = "Reset", label = "Reset" }),
							},
						}),
						slider.blueprint,
						stepper.blueprint,
						UI.ScrollView({
							id = "List",
							height = { type = "fixed", px = 150 },
							children = rows,
						}),
					},
				}),
			},
		})

		-- keyboard navigation is OPT-IN (director playtest 2026-08-03) and this is
		-- the fixture for it, so it asks. Turning it on also makes this surface
		-- SINK, which is the half the playtest was about: with the UI focused, the
		-- avatar underneath must stop hearing Space and the arrows.
		--
		-- ...and it is PASSIVE (director playtest 2026-08-03 round 3: "there's no
		-- way to unfocus"). This fixture sits over a live world with an avatar in
		-- it, which is the shape `responder = "passive"` exists for: the surface
		-- binds nothing and sinks nothing until the player touches it, engages on
		-- that first tap, and resigns — handing Tab, Space and the arrows straight
		-- back — on a tap outside itself.
		--
		-- Presented engaged-open (the default) it could never let go: a plain
		-- screen is not `currentExclusive`, so it gets no outside-tap catcher, and
		-- `resign()` is a no-op for it. With `keyboardNavigation` also forcing the
		-- sink, the fixture held the keyboard permanently.
		local handle = ctx.presenter.present(screen, { keyboardNavigation = true, responder = "passive" })

		-- ---- the traces -----------------------------------------------------
		local actionLog: { any } = {}
		local focusLog: { any } = {}
		local modalHandle: any = nil
		local characterCounts = { jump = 0, move = 0 }
		local characterConns: { any }? = nil

		local function focusNow(): string?
			return ctx.presenter.focus.focused:get()
		end

		local function note(action: string, detail: any)
			table.insert(actionLog, {
				n = #actionLog + 1,
				action = action,
				detail = detail,
				focus = focusNow(),
				at = os.clock(),
			})
		end

		-- the semantic actions, straight off the surface's own InputContext, so
		-- the trace says which VERB a key resolved to rather than only what moved
		handle.actions.traverse.onPressed(function()
			local mods = if ctx.actionSystem.modifiers ~= nil then ctx.actionSystem.modifiers() else nil
			note("Traverse", { shift = mods and mods.shift, focusBefore = focusNow() })
		end)
		handle.actions.activate.onPressed(function()
			note("Activate", { focusBefore = focusNow() })
		end)
		core:observe(handle.actions.adjust.state, function(dir)
			if dir == 1 or dir == -1 then
				note("Adjust", { direction = dir })
			end
		end)
		core:observe(handle.actions.navigate.state, function(dir)
			if dir == 1 or dir == -1 then
				note("Navigate", { axis = "vertical", direction = dir })
			end
		end)
		core:observe(ctx.presenter.focus.focused, function(path)
			table.insert(focusLog, { n = #focusLog + 1, path = path, at = os.clock() })
		end)
		ctx.presenter.onFeedback(function(event)
			if event.type == "activate" then
				note("activate-effect", { path = event.path })
			end
		end)

		local function scrollState(): any
			local inst = ctx.instanceAt("/KbdNav/Body/List")
			if inst == nil or not inst:IsA("ScrollingFrame") then
				return { available = false }
			end
			return {
				available = true,
				canvasPosition = { x = inst.CanvasPosition.X, y = inst.CanvasPosition.Y },
				canvasSize = { x = inst.AbsoluteCanvasSize.X, y = inst.AbsoluteCanvasSize.Y },
				windowSize = { x = inst.AbsoluteWindowSize.X, y = inst.AbsoluteWindowSize.Y },
			}
		end

		-- WHICH KEYS THIS SURFACE ACTUALLY OWNS RIGHT NOW. Reading the bindings
		-- off the live actions is the only honest answer to "did the hot-plug
		-- leave a sink behind" — an absent binding is the claim, so it has to be
		-- read, not asserted.
		local function boundKeys(): any
			local out: { [string]: { string } } = {}
			for name, action in handle.actions do
				local keys: { string } = {}
				for _, binding in action.bindings do
					if binding.keyCode ~= nil then
						table.insert(keys, binding.keyCode)
					elseif binding.isAxis then
						table.insert(keys, "axis:" .. tostring(binding.axis))
					end
				end
				table.sort(keys)
				out[name] = keys
			end
			return out
		end

		return {
			screen = screen,
			handle = handle,
			steps = {
				-- state/action drivers (labeled: NOT hardware-input evidence)
				armKeys = function()
					ctx.telemetry.keyLog.arm()
					table.clear(actionLog)
					table.clear(focusLog)
					return { armed = true, focus = focusNow(), bound = boundKeys() }
				end,
				readKeys = function()
					ctx.presenter.refresh()
					ctx.telemetry.step()
					return {
						rawInput = ctx.telemetry.keyLog.read(),
						actions = actionLog,
						focusLog = focusLog,
						focus = focusNow(),
						scroll = scrollState(),
						bound = boundKeys(),
					}
				end,
				-- THE RESOLVED FOCUS CHAIN, live (stage traversal-document-order,
				-- rows TD-13/TD-14). Both readings as the running presenter reports
				-- them, so a Studio row can compare the order Tab ACTUALLY walks
				-- against the order the framework SAYS it will — the two are computed
				-- by different code paths, and a session that only recorded the focus
				-- log could not tell a wrong order from a wrong dump.
				focusOrder = function()
					ctx.presenter.refresh()
					local dump = handle.focusOrder()
					local traversal, navigation = {}, {}
					for _, e in dump.traversal do
						table.insert(traversal, { path = e.path, priority = e.priority, eligible = e.eligible })
					end
					for _, g in dump.navigation do
						local order = {}
						for _, p in g.order do
							table.insert(order, p)
						end
						table.insert(navigation, { name = g.name, axis = g.axis, order = order })
					end
					return {
						schema = dump.schema,
						scope = dump.scope,
						ranked = dump.ranked,
						traversalWrap = dump.traversalWrap,
						traversal = traversal,
						navigation = navigation,
					}
				end,
				-- focus the named path directly, so a row can start from a known
				-- place without tabbing there first (labeled: a STATE driver)
				focusOn = function(_self, payload: string?)
					if payload == nil then
						return { ok = false }
					end
					local ok = ctx.presenter.focus.focusOn(payload)
					ctx.presenter.focus.setFocusOrigin("navigation")
					return { ok = ok, focus = focusNow() }
				end,
				openModal = function()
					if modalHandle ~= nil then
						return { open = true, focus = focusNow() }
					end
					modalHandle = ctx.presenter.presentModal(UI.Screen({
						id = "KbdModal",
						padding = 20,
						gap = "s",
						width = { type = "fixed", px = 320 },
						height = { type = "fixed", px = 180 },
						children = {
							UI.Text({ id = "MTitle", text = "Confirm", textSize = "heading" }),
							UI.Button({ id = "Ok", label = "OK" }),
							UI.Button({ id = "Nope", label = "Cancel" }),
						},
					}))
					ctx.presenter.refresh()
					return { open = true, focus = focusNow(), depth = ctx.presenter.depth() }
				end,
				closeModal = function()
					if modalHandle == nil then
						return { open = false }
					end
					ctx.presenter.dismiss(modalHandle)
					modalHandle = nil
					ctx.presenter.refresh()
					return { open = false, focus = focusNow(), depth = ctx.presenter.depth() }
				end,
				-- SINK ARBITRATION (director playtest 2026-08-03). The surface's own
				-- Sink, toggled through the sanctioned seam, so "does a sinking
				-- surface still receive its own keys, and does the character stop
				-- receiving them" is measured on the ONE surface whose VirtualInput
				-- delivery is already proven reliable — ad-hoc probe presenters gave
				-- inconsistent answers and are not trustworthy here.
				setSink = function(_self, payload: string?)
					local want = payload == "true"
					handle.context.setSink(want)
					return { sink = handle.context.sink, priority = handle.context.priority }
				end,
				-- what the ENGINE's own character actions saw, counted from the
				-- PlayerModule's real InputActions rather than a stand-in
				armCharacter = function()
					characterCounts.jump = 0
					characterCounts.move = 0
					if characterConns == nil then
						characterConns = {}
						local ok = pcall(function()
							local cc = game:GetService("StarterPlayer").PlayerModule.InputContexts.CharacterContext
							local jump = cc:FindFirstChild("JumpAction")
							local move = cc:FindFirstChild("MoveAction")
							if jump ~= nil then
								table.insert(
									characterConns,
									jump.Pressed:Connect(function()
										characterCounts.jump += 1
									end)
								)
							end
							if move ~= nil then
								table.insert(
									characterConns,
									move.StateChanged:Connect(function(v)
										if typeof(v) == "Vector2" and v.Magnitude > 0.1 then
											characterCounts.move += 1
										end
									end)
								)
							end
						end)
						if not ok then
							characterConns = nil
							return { available = false }
						end
					end
					return { available = true, jump = 0, move = 0 }
				end,
				readCharacter = function()
					return { jump = characterCounts.jump, move = characterCounts.move }
				end,
				-- HOT-PLUG (DK-13): drop and restore the keyboard capability fact
				-- and read back which keys the surface holds either side of it
				keyboardOff = function()
					ctx.env:set("capabilities", { keyboard = false, mouse = true, touch = true, gamepad = false })
					return { bound = boundKeys(), classes = ctx.env:get("interactionClasses"):get() }
				end,
				keyboardOn = function()
					ctx.env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = false })
					return { bound = boundKeys(), classes = ctx.env:get("interactionClasses"):get() }
				end,
			},
			report = function()
				return {
					focus = focusNow(),
					focusVisible = ctx.presenter.focus.focusVisible:get(),
					responder = handle.responder:get(),
					depth = ctx.presenter.depth(),
					modalOpen = modalHandle ~= nil,
					bound = boundKeys(),
					scroll = scrollState(),
					state = {
						field = fieldValue:get(),
						editing = field.dump().editing,
						commits = commits:get(),
						volume = volume:get(),
						count = count:get(),
						saved = saved:get(),
					},
					actions = actionLog,
					focusLog = focusLog,
					rawInput = ctx.telemetry.keyLog.read(),
					lifecycle = {
						contextEnabled = handle.context.enabled,
						contextSink = handle.context.sink,
						contextPriority = handle.context.priority,
					},
				}
			end,
		}
	end,
}
