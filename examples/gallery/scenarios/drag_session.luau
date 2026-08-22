--!strict
-- Scenario 'drag_session' (ledger rows NS-A5/NS-A6): native UIDragDetector
-- acquisition (CustomOffset — the renderer keeps Position authority) feeding
-- the PURE drag-session model: payload, legal/illegal targets, enter/leave,
-- drop commit, cancellation. The Sponsor-shaped case: drag the card onto one
-- of two rows; the third target rejects the payload (accepts=false).
-- Fallback A/B (NS-I2): set workspace attribute Facet_ForceDragFallback=true
-- and the same scenario wires the raw pointer-capture seam instead.
-- Touch-gesture connection (NS-A6) is wired on the card; FIRING requires real
-- touch (NS-P2) — the connection + normalization contract is headless-proven.

return {
	title = "Native drag session (NS-A5/NS-A6)",
	ledgerRows = { "NS-A5", "NS-A6", "NS-I2" },
	build = function(ctx: any)
		local UI = ctx.Facet.UI
		local core = ctx.core

		local status = core:signal("idle")
		local statusText = core:memo(function(use)
			return "drag: " .. use(status)
		end)
		local hoverTarget = core:signal("")
		local hoverText = core:memo(function(use)
			local h = use(hoverTarget)
			return if h == "" then "over: none" else "over: " .. h
		end)

		local screen = UI.Screen({
			id = "DragLab",
			padding = "m",
			-- 8, not 10 (2026-08-12): the `Board` below is a horizontal scroller, and
			-- since the scrollbar reserve became policy-independent that scroller hugs
			-- 8px taller — the height the engine actually charges for its bar. At the
			-- narrowest landscape (640x320, under the showcase picker's 120px strip)
			-- this page had 7px of slack, so it went 1px over and the overflow sweep
			-- said so. The room comes out of the inter-row gap, which is the cheapest
			-- pixel on a four-row lab page; nothing here is a token.
			gap = "s",
			children = {
				UI.Text({ id = "Title", text = "Drag session lab", textSize = 22 }),
				UI.Text({ id = "Status", text = statusText, textSize = "label" }),
				UI.Text({ id = "Hover", text = hoverText, textSize = "label" }),
				-- The board's four fixed-width slots (Card + three targets, ~640px
				-- with gaps) never fit a phone's width and must stay side by side —
				-- the drag targets' geometry is meaningless if they wrap or shrink.
				-- A horizontal ScrollView keeps them all reachable instead of letting
				-- the row paint past the screen edge (overflow sweep, 2026-08-12).
				UI.ScrollView({
					id = "Board",
					axis = "x",
					gap = "m",
					children = {
						UI.Box({
							id = "Card",
							surface = "control",
							width = { type = "fixed", px = 110 },
							height = { type = "fixed", px = 70 },
						}),
						UI.Box({
							id = "RowA",
							surface = "raised",
							width = { type = "fixed", px = 160 },
							height = { type = "fixed", px = 70 },
						}),
						UI.Box({
							id = "RowB",
							surface = "raised",
							width = { type = "fixed", px = 160 },
							height = { type = "fixed", px = 70 },
						}),
						UI.Box({
							id = "Locked",
							surface = "base",
							width = { type = "fixed", px = 160 },
							height = { type = "fixed", px = 70 },
						}),
					},
				}),
			},
		})

		local session: any = nil
		local trace: { string } = {}
		-- the FULL normalized gesture payloads (NS-A6 / SEAM-3): a Studio drive on a
		-- real touch device reads these to prove positions/scale/state actually
		-- arrived, not merely that a gesture kind fired
		local gestures: { any } = {}
		local wired = "none"

		local function targetsFromGeometry(rectOf: (string) -> any)
			local function t(id: string, accepts: boolean)
				local r = rectOf("/DragLab/Board/" .. id)
				return {
					id = id,
					rect = r and { x = r.x, y = r.y, w = r.w, h = r.h } or { x = 0, y = 0, w = 0, h = 0 },
					accepts = function(_payload)
						return accepts
					end,
				}
			end
			return { t("RowA", true), t("RowB", true), t("Locked", false) }
		end

		local function beginSession(rectOf: (string) -> any)
			session = ctx.Facet.newDragSession({
				payload = { kind = "sponsor-card", id = 7 },
				source = "/DragLab/Board/Card",
				targets = targetsFromGeometry(rectOf),
				onEnter = function(id)
					hoverTarget:set(id)
					table.insert(trace, "enter:" .. id)
				end,
				onLeave = function(id)
					hoverTarget:set("")
					table.insert(trace, "leave:" .. id)
				end,
			})
			status:set("dragging")
		end

		return {
			screen = screen,
			present = {},
			-- the runner hands us the presenter handle after build; wireDrag is a
			-- step so evidence can distinguish native vs fallback wiring
			steps = {
				wireDrag = function(built: any)
					local controller = built.handle.controller
					local adapter = ctx.adapter
					local cardInstance = adapter.getInstance and adapter.getInstance("/DragLab/Board/Card")
					local handlers = {
						onStart = function(pos: any)
							beginSession(controller.rectOf)
							session:update(pos.x, pos.y)
						end,
						onContinue = function(pos: any, _delta: any)
							if session then
								session:update(pos.x, pos.y)
							end
						end,
						onEnd = function(pos: any)
							if session then
								local result = session:drop(pos.x, pos.y)
								status:set(result.kind .. (result.targetId and (":" .. result.targetId) or ""))
								table.insert(trace, "drop:" .. result.kind .. ":" .. tostring(result.targetId))
								session = nil
								hoverTarget:set("")
							end
						end,
					}
					local forceFallback = ctx.flags.forceDragFallback == true
					local detach = nil
					if not forceFallback and adapter.setDragDetector ~= nil and cardInstance ~= nil then
						detach =
							adapter.setDragDetector({ instance = cardInstance, path = "/DragLab/Board/Card" }, handlers)
					end
					if detach ~= nil then
						wired = "native-dragdetector"
					else
						-- fallback: raw pointer-capture seam (ADR-0008)
						wired = "pointer-fallback"
						adapter.setPointerHandlers({ instance = cardInstance, path = "/DragLab/Board/Card" }, {
							-- the raw seam passes ONE {x,y,pointerType} table
							-- (window space; ADR-0008 capture contract)
							down = function(pos: any)
								handlers.onStart({ x = pos.x, y = pos.y })
								return true
							end,
							move = function(pos: any)
								handlers.onContinue({ x = pos.x, y = pos.y }, { x = 0, y = 0 })
							end,
							up = function(pos: any)
								handlers.onEnd({ x = pos.x, y = pos.y })
							end,
							cancel = function()
								if session then
									session:cancel("interrupted")
									status:set("cancelled")
									session = nil
								end
							end,
						})
					end
					-- NS-A6 connection: normalized touch gestures reach a pure sink.
					-- The recorder keeps the WHOLE payload, not just the kind: `kind`
					-- survived the SEAM-3 named-key defect while positions, state,
					-- scale, rotation, translation and velocity were all dropped, so a
					-- kind-only trace could never have caught it. A Studio drive on a
					-- touch device reads `gestures` and sees real numbers or nothing.
					if adapter.setTouchGestureHandlers ~= nil and cardInstance ~= nil then
						adapter.setTouchGestureHandlers(
							{ instance = cardInstance, path = "/DragLab/Board/Card" },
							function(gesture)
								local first = (gesture.positions or {})[1]
								table.insert(gestures, {
									kind = gesture.kind,
									state = gesture.state,
									positionCount = #(gesture.positions or {}),
									firstPosition = if first ~= nil then { x = first.x, y = first.y } else nil,
									totalTranslation = gesture.totalTranslation,
									velocity = gesture.velocity,
									scale = gesture.scale,
									rotation = gesture.rotation,
									direction = gesture.direction,
								})
								table.insert(
									trace,
									"touch:"
										.. tostring(gesture.kind)
										.. ":"
										.. tostring(gesture.state)
										.. ":n="
										.. tostring(#(gesture.positions or {}))
								)
							end
						)
					end
					return wired
				end,
				cancelDrag = function()
					if session then
						session:cancel("scripted")
						status:set("cancelled")
						session = nil
						hoverTarget:set("")
						return "cancelled"
					end
					return "no-session"
				end,
			},
			report = function()
				return {
					status = status:get(),
					hover = hoverTarget:get(),
					wired = wired,
					trace = trace,
					gestures = gestures,
				}
			end,
		}
	end,
}
