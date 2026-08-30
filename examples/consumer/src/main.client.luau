--!strict
--[[ The whole client side of a Facet game, in one file.

	It does four things and nothing else: wait for the DataModel, stand a host up,
	present the screen, and tear both down when the player is finished. Every line
	is the documented public route — `docs/guide/03-getting-started.md` §3.4 is the
	chapter this file is the running version of.
]]

--[[ Require-by-string does NOT wait for replication, so a client that starts
	requiring before the DataModel has finished loading can fail on a child that
	simply has not arrived yet. `WaitForChild` covers only the top node. ]]
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Facet = require(ReplicatedStorage:WaitForChild("Facet"))
--[[ The client-only modules are deliberately NOT on the `Facet` table, so that
	server and shared code can require the library safely. `host` is the blessed
	bootstrap: it builds a core, an environment bound to the engine, a render
	target under PlayerGui, an input system and a presenter, and connects ONE
	PreRender that drives both halves of the frame. ]]
local host = require(ReplicatedStorage.Facet.client.host)
local screen = require(ReplicatedStorage:WaitForChild("FacetConsumerScreen"))

-- how long the screen stays up if nobody presses Close
local CLOSE_AFTER_SECONDS = 120

local h = host.new()
local built = screen.build(Facet, h.core, { env = h.env, presenter = h.presenter })

local handle = h.presenter.present(built.blueprint)

local torn = false
local function teardown()
	if torn then
		return
	end
	torn = true
	--[[ Three steps, in this order. `dismiss` retires the presented surface with
		its focus scope and its input context; `built.dispose` frees the signals,
		the memos and the adaptive conditions; `h.dispose` takes back the frame
		connection, the input system, the render target and the environment
		binding. Disposing the host while a surface is still presented leaves that
		surface's observers alive on the core. ]]
	h.presenter.dismiss(handle)
	built.dispose()
	h.dispose()
end

-- teardown route one: the Close button
h.core:observe(built.closed, function(value: boolean)
	if value then
		teardown()
	end
end)

--[[ Teardown route two: a timer. Per-frame work belongs on `presenter.onTick`,
	which runs after the motion step on the frame the host already drives — a
	second RunService connection is the thing to avoid. ]]
local elapsed = 0
h.presenter.onTick(function(dt: number)
	elapsed += dt
	if elapsed >= CLOSE_AFTER_SECONDS then
		teardown()
	end
end)
