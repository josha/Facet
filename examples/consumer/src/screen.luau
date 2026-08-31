--!strict
--[[ THE FIVE-MINUTE SCREEN, as a module both halves of the example share.

	`main.client.luau` requires this through the instance tree and mounts it in
	Roblox. `tests/consumer_standalone.spec.luau` requires it by path and mounts
	it headlessly against the fake render target. One description, two hosts —
	which is what stops the example in the guide from drifting away from the
	library it is teaching.

	Everything here is the PUBLIC surface. `Facet` arrives as an argument rather
	than a require, because the two hosts reach the library by different routes;
	nothing else about the screen changes between them.

	Four things a first screen should show, and all four are here:

	  * SEMANTIC STATE, held by the caller. `count` and `soundOn` are signals this
	    module owns and the blueprint reads. Nothing important lives inside a
	    control.
	  * ADAPTATION WITH NO DEVICE BRANCH. The buttons stack in a column on a
	    compact phone and sit in a row on anything wider, because `axis` is bound
	    to `adaptive.conditions`. There is no device name anywhere in this file.
	  * THE PLAYER'S TEXT SIZE, RESPECTED BY DOING NOTHING. `Blurb` declares no
	    `textSize`, so it takes the body role and moves with the accessibility
	    text setting. A hard-coded pixel size is what breaks that.
	  * ONE SCOPE THAT OWNS EVERYTHING. `dispose` kills the scope, which frees
	    every signal, memo, and the eighteen memos `adaptive.conditions` builds.
]]

local screen = {}

export type Deps = {
	env: any,
	presenter: any?,
}

export type Built = {
	blueprint: any,
	-- the screen's own state, exposed so a host (or a spec) can read and drive it
	count: any,
	soundOn: any,
	closed: any,
	--[[ Hand a release function or a disposable object to the screen's own scope,
		so it dies when the screen does. `screen.session` below owns its two
		subscriptions this way. ]]
	own: (resource: any) -> any,
	dispose: () -> (),
}

export type SessionOpts = {
	closeAfterSeconds: number?,
}

export type Session = {
	built: Built,
	handle: any,
	teardown: () -> (),
	isTorn: () -> boolean,
}

-- the node paths the two hosts and the spec address, in one place so a rename
-- cannot leave a driver pressing a button that no longer exists
screen.PATHS = table.freeze({
	root = "/Consumer",
	title = "/Consumer/Panel/Title",
	blurb = "/Consumer/Panel/Blurb",
	count = "/Consumer/Panel/Readout/Count",
	sound = "/Consumer/Panel/Readout/Sound",
	buttons = "/Consumer/Panel/Buttons",
	bump = "/Consumer/Panel/Buttons/Bump",
	close = "/Consumer/Panel/Buttons/Close",
})

function screen.build(Facet: any, core: any, deps: Deps): Built
	local UI = Facet.UI
	local scope = core:scope("facet-consumer")

	--[[ The adaptive facts, owned by this screen's scope. `conditions` builds
		eighteen memos; a screen that rebuilds without owning them leaks eighteen
		every time. ]]
	local conditions = Facet.adaptive.conditions(core, deps.env, { scope = scope })

	local count = scope:own(core:signal(0))
	local soundOn = scope:own(core:signal(true))
	local closed = scope:own(core:signal(false))

	-- a memo derives the label from the count, so the label recomputes only when
	-- the count actually changes
	local countLabel = scope:own(core:memo(function(use)
		local taps = use(count)
		return if taps == 1 then "1 tap" else `{taps} taps`
	end))

	local blueprint = UI.Screen({
		id = "Consumer",
		padding = "l",
		children = {
			UI.VStack({
				id = "Panel",
				surface = "raised",
				padding = "m",
				gap = "s",
				children = {
					UI.Text({ id = "Title", text = "Facet consumer", textSize = "title" }),
					UI.Text({
						id = "Blurb",
						text = "One screen, one signal, one theme. Press Bump and watch the count follow.",
					}),
					UI.VStack({
						id = "Readout",
						gap = "xs",
						children = {
							-- the accent tint resolves against the ACTIVE theme, so a
							-- theme swap repaints it with no rebuild
							UI.Text({ id = "Count", text = countLabel, tint = { role = "accent", blend = 1 } }),
							UI.Toggle({ id = "Sound", label = "Sound", value = soundOn }),
						},
					}),
					UI.AdaptiveStack({
						id = "Buttons",
						axis = conditions.axis,
						gap = "s",
						children = {
							UI.Button({
								id = "Bump",
								label = "Bump",
								onActivate = function()
									count:set(count:get() + 1)
								end,
							}),
							UI.Button({
								id = "Close",
								label = "Close",
								onActivate = function()
									closed:set(true)
								end,
							}),
						},
					}),
				},
			}),
		},
	})

	return {
		blueprint = blueprint,
		count = count,
		soundOn = soundOn,
		closed = closed,
		own = function(resource: any): any
			return scope:own(resource)
		end,
		dispose = function()
			scope:dispose()
		end,
	}
end

--[[ THE WHOLE LIFETIME OF THE SCREEN, in one function, because the teardown
	ORDER is the part that is easy to get wrong and the part worth teaching.

	`main.client.luau` calls this and does nothing else. The spec calls it too,
	and drives the Close button through it — so the wiring a reader copies is the
	wiring that is under test, rather than a second arrangement the spec invented
	for itself.

	Two things this fixes, both of which were wrong when it was two loose blocks
	in the client script:

	  * THE SUBSCRIPTIONS ARE OWNED. `core:observe` and `presenter.onTick` each
	    return an unsubscribe function, and neither was ever called. Both now
	    belong to the screen's scope, so the same `dispose` that frees the signals
	    frees them.
	  * TEARDOWN IS RE-ENTRANT, AND THAT IS THE POINT. The observer that calls
	    `teardown` is released BY `teardown`, so the function runs while the thing
	    that called it is being disposed. That path works because each of the
	    three steps below is independently idempotent — measured, by removing the
	    `torn` flag and watching the suite stay green. The flag is therefore not
	    what makes it safe: it keeps a second call cheap, and it is what lets a
	    session answer `isTorn()` honestly.
]]
function screen.session(Facet: any, h: any, opts: SessionOpts?): Session
	local closeAfterSeconds = (opts and opts.closeAfterSeconds) or 120

	local built = screen.build(Facet, h.core, { env = h.env, presenter = h.presenter })
	local handle = h.presenter.present(built.blueprint)

	local torn = false
	local function teardown()
		if torn then
			return
		end
		torn = true
		--[[ Three steps, in this order. `dismiss` retires the presented surface
			with its focus scope and its input context; `built.dispose` frees the
			signals, the memos, the adaptive conditions and the two subscriptions
			below; `h.dispose` takes back the frame connection, the input system,
			the render target and the environment binding. Disposing the host while
			a surface is still presented leaves that surface's observers alive on
			the core. ]]
		h.presenter.dismiss(handle)
		built.dispose()
		h.dispose()
	end

	-- teardown route one: the Close button
	built.own(h.core:observe(built.closed, function(value: boolean)
		if value then
			teardown()
		end
	end))

	--[[ Teardown route two: a timer. Per-frame work belongs on
		`presenter.onTick`, which runs after the motion step on the frame the host
		already drives — a second RunService connection is the thing to avoid. ]]
	local elapsed = 0
	built.own(h.presenter.onTick(function(dt: number)
		elapsed += dt
		if elapsed >= closeAfterSeconds then
			teardown()
		end
	end))

	return {
		built = built,
		handle = handle,
		teardown = teardown,
		isTorn = function()
			return torn
		end,
	}
end

return screen
