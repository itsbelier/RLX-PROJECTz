--!strict
-- ServerScriptService/Server/Services/RemoteService
-- Creates RemoteEvents in ReplicatedStorage/Remotes if missing

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local RemotesIndex = require(RemotesFolder:WaitForChild("RemotesIndex"))

local RemoteService = {}

local function getOrCreateRemoteEvent(name: string): RemoteEvent
	local existing = RemotesFolder:FindFirstChild(name)
	if existing then
		return existing :: RemoteEvent
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = RemotesFolder
	return re
end

function RemoteService.Init()
	for _, remoteName in pairs(RemotesIndex) do
		getOrCreateRemoteEvent(remoteName)
	end
end

function RemoteService.GetEvent(name: string): RemoteEvent
	local re = RemotesFolder:WaitForChild(name)
	return re :: RemoteEvent
end

return RemoteService