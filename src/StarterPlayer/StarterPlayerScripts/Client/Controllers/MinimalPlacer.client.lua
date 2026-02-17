--!strict
-- StarterPlayerScripts/Client/Controllers/MinimalPlacer.client.lua
-- MVP placement tester (no UI):
-- During BuildPhase, press E to place your first obstacle a few studs in front of you.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local RemotesIndex = require(RemotesFolder:WaitForChild("RemotesIndex"))

local RE_PlacementRemaining = RemotesFolder:WaitForChild(RemotesIndex.RE_PlacementRemaining) :: RemoteEvent

local RE_ObstacleHand = RemotesFolder:WaitForChild(RemotesIndex.RE_ObstacleHand) :: RemoteEvent
local RE_PlacementError = RemotesFolder:WaitForChild(RemotesIndex.RE_PlacementError) :: RemoteEvent
local RE_PlaceObstacle = RemotesFolder:WaitForChild(RemotesIndex.RE_PlaceObstacle) :: RemoteEvent
local RE_GameStateChanged = RemotesFolder:WaitForChild(RemotesIndex.RE_GameStateChanged) :: RemoteEvent

local currentHand: {string} = {}
local placementsRemaining = 0
local isBuildPhase = false

RE_PlacementRemaining.OnClientEvent:Connect(function(payload)
	placementsRemaining = payload.placementsRemaining or placementsRemaining
	print("[Placer] Remaining updated:", placementsRemaining)
end)


RE_GameStateChanged.OnClientEvent:Connect(function(stateData)
	isBuildPhase = (stateData.state == "BuildPhase")
end)

RE_ObstacleHand.OnClientEvent:Connect(function(payload)
	-- payload: { hand = {string}, placementsRemaining = number }
	currentHand = payload.hand or {}
	placementsRemaining = payload.placementsRemaining or 0
	print("[Placer] Got hand:", currentHand, "remaining:", placementsRemaining)
end)

RE_PlacementError.OnClientEvent:Connect(function(payload)
	print("[Placer] Placement error:", payload.message)
end)

local function getPlaceCFrame(): CFrame?
	local character = player.Character
	if not character then return nil end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return nil end

	-- Place 8 studs forward, on roughly the same Y (server will validate region)
	local pos = hrp.Position + hrp.CFrame.LookVector * 8
	local yaw = select(2, hrp.CFrame:ToEulerAnglesYXZ())
	return CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode ~= Enum.KeyCode.E then return end

	if not isBuildPhase then
		print("[Placer] Not in BuildPhase.")
		return
	end

	if placementsRemaining <= 0 then
		print("[Placer] No placements remaining.")
		return
	end

	local obstacleName = currentHand[1]
	if not obstacleName then
		print("[Placer] No obstacle in hand yet.")
		return
	end

	local cf = getPlaceCFrame()
	if not cf then return end

	print("[Placer] Placing:", obstacleName)
	RE_PlaceObstacle:FireServer(obstacleName, cf)


end)
