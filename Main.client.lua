--!strict
-- StarterPlayerScripts/Client/Main.client.lua
-- Bootstraps client listeners (MVP). UI comes later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local RemotesIndex = require(RemotesFolder:WaitForChild("RemotesIndex"))

-- Server -> Client
local RE_GameStateChanged = RemotesFolder:WaitForChild(RemotesIndex.RE_GameStateChanged) :: RemoteEvent
local RE_TimerSync = RemotesFolder:WaitForChild(RemotesIndex.RE_TimerSync) :: RemoteEvent
local RE_VoteOptions = RemotesFolder:WaitForChild(RemotesIndex.RE_VoteOptions) :: RemoteEvent
local RE_VoteUpdate = RemotesFolder:WaitForChild(RemotesIndex.RE_VoteUpdate) :: RemoteEvent
local RE_VoteResult = RemotesFolder:WaitForChild(RemotesIndex.RE_VoteResult) :: RemoteEvent

-- Client -> Server
local RE_SubmitVote = RemotesFolder:WaitForChild(RemotesIndex.RE_SubmitVote) :: RemoteEvent

RE_GameStateChanged.OnClientEvent:Connect(function(stateData)
	-- stateData: { state, endsAt?, round, selectedMap? }
	print("[Client] GameStateChanged:", stateData.state, "round", stateData.round)
end)

RE_TimerSync.OnClientEvent:Connect(function(payload)
	-- payload: { state, endsAt, round }
	print(("[Client] TimerSync: %s endsAt=%.2f round=%d"):format(payload.state, payload.endsAt, payload.round))
end)

RE_VoteOptions.OnClientEvent:Connect(function(payload)
	-- payload: { id, options, endsAt }
	print("[Client] VoteOptions:", payload.id, payload.options)

	-- TEMP: auto-vote randomly so you can test end-to-end without UI
	local options = payload.options
	if typeof(options) == "table" and #options > 0 then
		local pick = options[math.random(1, #options)]
		print("[Client] Auto-voting for:", pick)
		RE_SubmitVote:FireServer(payload.id, pick)
	end
end)

RE_VoteUpdate.OnClientEvent:Connect(function(payload)
	-- payload: { id, tally, endsAt, options }
	-- This will be used by UI later; printing is enough for now.
	print("[Client] VoteUpdate tally:", payload.tally)
end)

RE_VoteResult.OnClientEvent:Connect(function(payload)
	-- payload: { id, winner, tally }
	print("[Client] VoteResult winner:", payload.winner, "tally:", payload.tally)
end)

print("[Client] Booted for", player.Name)

local controllers = script.Parent:WaitForChild("Controllers")
local PlacementController = require(controllers:WaitForChild("PlacementController"))
PlacementController.Start()

