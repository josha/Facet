--!strict
--[[ The whole client side of a Facet game, in one file.

	It does three things and nothing else: wait for the DataModel, stand a host
	up, and hand it to the screen's session. Every line is the documented public
	route — `docs/guide/03-getting-started.md` §3.4 is the chapter this file is
	the running version of.

	The lifetime lives in `screen.session` rather than here, because the teardown
	ORDER is the part worth getting right and the part a reader will copy. Keeping
	it in the module means the spec drives the same wiring instead of arranging
	its own.
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

local h = host.new()

--[[ Presents the screen, wires both ways out of it — the Close button and a
	timer — and owns every subscription on the screen's own scope. Pressing Close
	dismisses the surface, disposes the screen, and disposes the host, in that
	order. ]]
screen.session(Facet, h, { closeAfterSeconds = 120 })
