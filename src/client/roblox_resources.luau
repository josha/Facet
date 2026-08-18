--!strict
-- Roblox resource transport (native-substrate NS-A13; CLIENT-ONLY): the
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

local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local roblox_resources = {}

function roblox_resources.bind(provider: any): () -> ()
	local inFlight: { [string]: boolean } = {}
	local unbound = false

	local function dispatch(request: { key: string, generation: number })
		local key, generation = request.key, request.generation
		if inFlight[key] then
			return
		end
		inFlight[key] = true
		task.spawn(function()
			local finalStatus: Enum.AssetFetchStatus? = nil
			local ok, err = pcall(function()
				ContentProvider:PreloadAsync({ key }, function(_contentId: string, status: Enum.AssetFetchStatus)
					finalStatus = status
				end)
			end)
			inFlight[key] = nil
			if unbound then
				return -- provider may already be disposed; drop silently
			end
			if ok and finalStatus == Enum.AssetFetchStatus.Success then
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
