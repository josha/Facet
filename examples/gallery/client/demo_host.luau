--!strict
--[[ THE SHOWCASE'S DEMO CORE — one scope per demo, and the proxy that installs it.

	WHAT IT IS FOR. Ownership in this framework's core is EXPLICIT (`scope:own`);
	there is no ambient scope a signal joins by being created. The tutorial examples
	create signals and memos straight on the core they are handed and return no
	`dispose`, so dismissing their screens reclaimed the Instances and left their
	reactive state behind — after eight swaps, eight demos' worth of signals were
	still live on the shared core.

	The fix belongs to the HOST, not to the examples: the examples are what the
	guide walks through line by line, and a showcase requirement has no business
	changing them. They take the core as an argument, so the host hands them a
	PROXY whose allocating methods own into a per-demo scope. Disposing that scope
	reclaims everything the demo made, whatever it made it with.

	WHY IT IS A MODULE AND NOT A LOCAL IN `init.client.luau`. Because it is the one
	piece of the showcase's mount path that a headless spec can actually drive, and
	the day it stopped being drivable it broke two demos in a live session with a
	green suite behind it (2026-08-20): `sorted-entries` and `card-rail` both build
	an adaptive control, both controls ask the core they were built on for its
	environment, and a proxy is not the core it delegates to. Every headless spec
	built its own bare core, so the shipped host path had no coverage at all —
	`tests/gallery_demo_host.spec.luau` is that coverage, and it requires THIS
	module so it exercises the proxy the player actually gets rather than a copy of
	it that can drift.

	`init.client.luau` holds everything else about mounting a demo, because the
	rest of it is Instances, replicated folders and a live adapter.
]]

local demo_host = {}

--[[ scopedCore(core, scope) -> a core that owns what it allocates into `scope`.

	EVERY METHOD IS FORWARDED, and the five ALLOCATING ones additionally own their
	result into the demo's scope: `signal`, `memo`, `observe`, `effect`, `scope`.
	What those return is what leaks.

	THE PROXY IS THE CORE FOR EVERY OTHER PURPOSE, and that includes the facts the
	framework itself hangs on a core — an environment publishes itself against the
	core it was built on (`src/env/surface_env.luau`) so that an adaptive control
	built later can find it with no wiring. A proxy that hid that fact turned "the
	environment arrives by itself" into a construction error on the one host where
	a player is holding the thing. The framework reads that registration through a
	normal index for exactly this shape, so the delegation below is all it takes;
	nothing here republishes, because a second registration would be a second owner.
]]
function demo_host.scopedCore(core: any, scope: any): any
	-- Release the usual parent-first construction order. The fallback may also
	-- encounter an API that adopted an earlier scope; those duplicate releases
	-- are harmless after unmount, while ordinary double disposal remains an error.
	local children = {}
	local cleaning = false
	scope:own(function()
		cleaning = true
		local ok, err = pcall(function()
			for _, child in children do
				if not child:isDisposed() then
					child:dispose()
				end
			end
		end)
		cleaning = false
		table.clear(children)
		if not ok then
			error(err, 0)
		end
	end)
	return setmetatable({}, {
		__index = function(_, key: string)
			local value = (core :: any)[key]
			if type(value) ~= "function" then
				return value
			end
			-- the allocating surface: what these return is what leaks
			if key == "signal" or key == "memo" or key == "observe" or key == "effect" or key == "scope" then
				return function(_self, ...)
					local resource = value(core, ...)
					if key == "scope" then
						local dispose = resource.dispose
						resource.dispose = function(self)
							if not cleaning or not self:isDisposed() then
								dispose(self)
							end
						end
						table.insert(children, resource)
						return resource
					end
					return scope:own(resource)
				end
			end
			return function(_self, ...)
				return value(core, ...)
			end
		end,
	})
end

-- Retire the rendered tree before releasing the state and controls it reads.
-- The presenter keeps that tree alive through its exit transition.
function demo_host.ownLifetime(built: any, presenter: any, scope: any)
	local ownDispose = built.dispose
	local released = false
	local function release()
		if released then
			return
		end
		released = true
		if ownDispose then
			pcall(ownDispose)
		end
		scope:dispose()
	end
	local handle = built.handle
	local unwatch
	local function releaseWhenUnmounted()
		if handle == nil or handle.scope:isDisposed() then
			if unwatch then
				unwatch()
				unwatch = nil
			end
			release()
		end
	end
	built.dispose = function()
		if released then
			return
		end
		if handle and not handle.scope:isDisposed() then
			if unwatch == nil then
				unwatch = presenter.onTick(releaseWhenUnmounted)
			end
			presenter.dismiss(handle)
		end
		releaseWhenUnmounted()
	end
end

return demo_host
