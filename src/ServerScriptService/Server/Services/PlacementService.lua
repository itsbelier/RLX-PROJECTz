--!strict
-- ServerScriptService/Server/Services/PlacementService
-- Server-authoritative placement of obstacles during BuildPhase.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local RemotesIndex = require(RemotesFolder:WaitForChild("RemotesIndex"))

local RE_PlaceObstacle = RemotesFolder:WaitForChild(RemotesIndex.RE_PlaceObstacle) :: RemoteEvent
local RE_PlacementError = RemotesFolder:WaitForChild(RemotesIndex.RE_PlacementError) :: RemoteEvent
local RE_ObstaclePlaced = RemotesFolder:WaitForChild(RemotesIndex.RE_ObstaclePlaced) :: RemoteEvent
local RE_PlacementRemaining = RemotesFolder:WaitForChild(RemotesIndex.RE_PlacementRemaining) :: RemoteEvent

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ObstaclesFolder = Shared:WaitForChild("Obstacles")
local ObstaclesCatalog = require(ObstaclesFolder:WaitForChild("ObstaclesCatalog"))

local ServicesFolder = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local ObstacleService = require(ServicesFolder:WaitForChild("ObstacleService"))

local PrefabsFolder = ServerStorage:WaitForChild("ObstaclePrefabs")

local PlacementService = {}

local _enabled = false
local _currentMap: Model? = nil
local _placedFolder: Folder? = nil

local function ensurePlacedFolder(mapModel: Model): Folder
	local f = mapModel:FindFirstChild("PlacedObstacles")
	if f and f:IsA("Folder") then
		return f
	end
	local newF = Instance.new("Folder")
	newF.Name = "PlacedObstacles"
	newF.Parent = mapModel
	return newF
end

local function pointInsidePart(part: BasePart, worldPoint: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(worldPoint)
	local half = part.Size * 0.5
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

local function withinPlacementBounds(mapModel: Model, worldPoint: Vector3): boolean
	local bounds = mapModel:FindFirstChild("PlacementBounds", true)
	if not (bounds and bounds:IsA("BasePart")) then
		-- Dev-friendly: allow if missing. For release, flip to "return false".
		warn("[PlacementService] PlacementBounds missing; allowing placement (DEV).")
		return true
	end
	return pointInsidePart(bounds, worldPoint)
end

local function insideNoPlace(mapModel: Model, worldPoint: Vector3): (boolean, string?)
	local noStart = mapModel:FindFirstChild("NoPlace_Start", true)
	if noStart and noStart:IsA("BasePart") and pointInsidePart(noStart, worldPoint) then
		return true, "Can't place near the start."
	end

	local noFinish = mapModel:FindFirstChild("NoPlace_Finish", true)
	if noFinish and noFinish:IsA("BasePart") and pointInsidePart(noFinish, worldPoint) then
		return true, "Can't place near the finish."
	end

	return false, nil
end

local function isInHand(userId: number, obstacleName: string): boolean
	local hand = ObstacleService.GetHand(userId)
	for _, n in ipairs(hand) do
		if n == obstacleName then
			return true
		end
	end
	return false
end

local function applyCFrameToInstance(inst: Instance, cf: CFrame)
	if inst:IsA("Model") then
		-- Prefer PrimaryPart; if absent, PivotTo still works on models with parts.
		inst:PivotTo(cf)
	elseif inst:IsA("BasePart") then
		inst.CFrame = cf
	end
end

function PlacementService.Enable(mapModel: Model)
	_enabled = true
	_currentMap = mapModel
	_placedFolder = ensurePlacedFolder(mapModel)
end

function PlacementService.Disable()
	_enabled = false
	_currentMap = nil
	_placedFolder = nil
end

function PlacementService.Init()
	RE_PlaceObstacle.OnServerEvent:Connect(function(player: Player, obstacleName: string, cf: CFrame)
		if not _enabled or not _currentMap or not _placedFolder then
			RE_PlacementError:FireClient(player, { message = "Placement is not currently enabled." })
			return
		end

		if typeof(obstacleName) ~= "string" or typeof(cf) ~= "CFrame" then
			RE_PlacementError:FireClient(player, { message = "Invalid placement payload." })
			return
		end

		-- Must exist in shared catalog
		if not ObstaclesCatalog.Exists(obstacleName) then
			RE_PlacementError:FireClient(player, { message = "Unknown obstacle." })
			return
		end

		-- Must be in this player's current hand
		if not isInHand(player.UserId, obstacleName) then
			RE_PlacementError:FireClient(player, { message = "You can't place that obstacle right now." })
			return
		end

		-- Must have placements remaining
		if ObstacleService.GetRemaining(player.UserId) <= 0 then
			RE_PlacementError:FireClient(player, { message = "No placements remaining." })
			return
		end

		local pos = cf.Position

		-- Must be within PlacementBounds
		if not withinPlacementBounds(_currentMap, pos) then
			RE_PlacementError:FireClient(player, { message = "Out of bounds." })
			return
		end

		-- Must not be in no-place zones
		local blocked, reason = insideNoPlace(_currentMap, pos)
		if blocked then
			RE_PlacementError:FireClient(player, { message = reason or "Can't place there." })
			return
		end

		-- Prefab must exist on server
		local prefab = PrefabsFolder:FindFirstChild(obstacleName)
		if not prefab then
			RE_PlacementError:FireClient(player, { message = "Prefab missing on server." })
			return
		end

		-- Consume placement only after ALL validation passed
		if not ObstacleService.ConsumePlacement(player.UserId) then
			RE_PlacementError:FireClient(player, { message = "No placements remaining." })
			return
		end

		-- Clone & position
		local clone = prefab:Clone()
		clone.Name = obstacleName .. "_" .. tostring(player.UserId) .. "_" .. tostring(math.random(1000, 9999))

		applyCFrameToInstance(clone, cf)

		clone.Parent = _placedFolder

		-- Broadcast for UI / future spectate sync
		RE_ObstaclePlaced:FireAllClients({
			obstacleName = obstacleName,
			cframe = cf,
			ownerUserId = player.UserId,
		})

		-- Sync remaining placements to this player
		local remaining = ObstacleService.GetRemaining(player.UserId)
		RE_PlacementRemaining:FireClient(player, { placementsRemaining = remaining })

		print(("[PlacementService] Placed %s for %s (remaining %d)"):format(obstacleName, player.Name, remaining))
	end)
end

return PlacementService
