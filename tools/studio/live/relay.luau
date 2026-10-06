--!strict
local HttpService = game:GetService("HttpService")
local storage = game:GetService("ReplicatedStorage")

local Verify = (require :: any)(storage:WaitForChild("FacetVerify"):WaitForChild("core"))
local relay = {}

function relay.start(base: string): string
	local event = storage:FindFirstChild("FacetLiveRelay") :: RemoteEvent?
	if event then
		event:Destroy()
	end
	local created = Instance.new("RemoteEvent")
	created.Name = "FacetLiveRelay"
	local parts: { [string]: { any } } = {}
	created.OnServerEvent:Connect(function(_, name: string, segment: any, dir: string?)
		local folder = if dir == "perf" or dir == "atlas" then dir else "live"
		if not string.match(name, "^[%w%-_]+$") then
			return
		end
		local list = parts[name] or {}
		parts[name] = list
		table.insert(list, segment)
		local text, problem = Verify.reassembleSegments(list)
		if not text then
			created:SetAttribute(name, tostring(problem))
			return
		end
		parts[name] = nil
		local ok, result = pcall(function()
			return HttpService:PostAsync(
				`{base}/save?dir={folder}&name={name}`,
				text,
				Enum.HttpContentType.ApplicationJson
			)
		end)
		created:SetAttribute(name, if ok then result else "failed: " .. tostring(result))
	end)
	created.Parent = storage
	return created:GetFullName()
end

return relay
