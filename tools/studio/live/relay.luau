--!strict
local HttpService = game:GetService("HttpService")
local storage = game:GetService("ReplicatedStorage")

local relay = {}

function relay.start(base: string): string
	local event = storage:FindFirstChild("FacetLiveRelay") :: RemoteEvent?
	if event then
		event:Destroy()
	end
	local created = Instance.new("RemoteEvent")
	created.Name = "FacetLiveRelay"
	local parts: { [string]: { string } } = {}
	created.OnServerEvent:Connect(function(_, name: string, index: number, count: number, text: string, dir: string?)
		local folder = if dir == "perf" then "perf" else "live"
		if not string.match(name, "^[%w%-_]+$") then
			return
		end
		local list = parts[name] or {}
		parts[name] = list
		list[index] = text
		for position = 1, count do
			if list[position] == nil then
				return
			end
		end
		parts[name] = nil
		local ok, result = pcall(function()
			return HttpService:PostAsync(
				`{base}/save?dir={folder}&name={name}`,
				table.concat(list, "", 1, count),
				Enum.HttpContentType.ApplicationJson
			)
		end)
		created:SetAttribute(name, if ok then result else "failed: " .. tostring(result))
	end)
	created.Parent = storage
	return created:GetFullName()
end

return relay
