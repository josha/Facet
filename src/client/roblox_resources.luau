--!strict
-- Roblox resource transport (CLIENT-ONLY): the
-- adapter-owned transport the engine-free provider (src/async/resources.luau)
-- was designed for. Drains provider.pendingRequests() and fulfils each key
-- with ContentProvider:PreloadAsync, answering provider.complete/fail with the
-- request's GENERATION so the provider's stale-completion rejection governs.
--
-- HONEST CANCELLATION (corrections addendum §12; spike m10-preload.json):
-- PreloadAsync yields and exposes NO cancellation API. Releasing a Facet
-- handle (a) prevents queued-but-unstarted work from being dispatched (the
-- provider removes it from the pending window) and (b) makes any late
-- completion STALE (generation mismatch -> rejected, state never resurrects).
-- It CANNOT stop an in-flight engine fetch, and nothing here claims to.
--
-- Engine facts (spike, 2026-07-23): per-asset callback delivers
-- Enum.AssetFetchStatus.Success/Failure; ImageLabel.LoadingImageFailed does
-- NOT exist — per-image failure signals come from this transport's status.
--
-- A key is the content string itself (rbxassetid://, rbxthumb://, ...). The
-- completed value is the same string (ready-to-assign Image content), which
-- keeps the provider's cache/LRU semantics engine-free.

--[[ THE SERVICES ARE RESOLVED AT BIND, NOT AT REQUIRE, and the PRELOAD TARGET
	is one of them (2026-08-17).

	`PreloadAsync`'s typed signature is `{any}` and this passed it content
	STRINGS. Every official sample passes INSTANCES, and the difference is not
	cosmetic: an Instance names the property the engine should fetch for, which is
	what makes the per-asset callback's status meaningful for anything but a bare
	image id. So the adapter now builds the Instance — a throwaway `ImageLabel`
	carrying the key, destroyed with the request — and the public API does not
	move: a key is still the content string, and the completed value is still that
	same string (ready to assign), which is what keeps the provider's cache and
	LRU semantics engine-free.

	The services (and the enum value the status is compared against) come through
	one optional table so the transport can be DRIVEN headlessly. A client passes
	nothing. ]]
local function engineServices(): any
	return {
		contentProvider = game:GetService("ContentProvider"),
		run = game:GetService("RunService"),
		successStatus = Enum.AssetFetchStatus.Success,
		spawn = function(f: () -> ())
			task.spawn(f)
		end,
		newPreloadTarget = function(key: string): any
			local label = Instance.new("ImageLabel")
			label.Image = key
			return label
		end,
	}
end

local roblox_resources = {}

function roblox_resources.bind(provider: any, services: any?): () -> ()
	local svc = services or engineServices()
	local ContentProvider = svc.contentProvider
	local RunService = svc.run
	local SUCCESS = svc.successStatus
	local newPreloadTarget = svc.newPreloadTarget
	local spawn = svc.spawn
	local inFlight: { [string]: boolean } = {}
	local unbound = false

	local function dispatch(request: { key: string, generation: number })
		local key, generation = request.key, request.generation
		if inFlight[key] then
			return
		end
		inFlight[key] = true
		spawn(function()
			local finalStatus: any = nil
			local target = newPreloadTarget(key)
			local ok, err = pcall(function()
				ContentProvider:PreloadAsync({ target }, function(_contentId: string, status: any)
					finalStatus = status
				end)
			end)
			pcall(function()
				target:Destroy()
			end)
			inFlight[key] = nil
			if unbound then
				return -- provider may already be disposed; drop silently
			end
			if ok and finalStatus == SUCCESS then
				provider.complete(key, generation, key)
			else
				local message = if not ok then tostring(err) else "AssetFetchStatus." .. tostring(finalStatus)
				provider.fail(key, generation, message)
			end
		end)
	end

	-- drain on Heartbeat: pendingRequests() is the provider's bounded active
	-- window; keys already in flight are skipped (the provider keeps them
	-- pending until answered). A released-then-reacquired key gets a NEW
	-- generation; a still-in-flight engine fetch for it will complete with the
	-- OLD generation and be rejected as stale — by design.
	local heartbeat = RunService.Heartbeat:Connect(function()
		for _, request in provider.pendingRequests() do
			dispatch(request)
		end
	end)

	return function()
		unbound = true
		heartbeat:Disconnect()
	end
end

return roblox_resources
