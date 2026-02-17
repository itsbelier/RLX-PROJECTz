--!strict
-- ServerScriptService/Server/Services/MapService
-- Loads maps from ServerStorage/Maps into Workspace and teleports players.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MapsFolder = ServerStorage:WaitForChild("Maps")

local MapService = {}

local CURRENT_MAP_NAME = "CurrentMap"

local function getCurrentMap(): Instance?
	return Workspace:FindFirstChild(CURRENT_MAP_NAME)
end

local function clearCurrentMap()
	local existing = getCurrentMap()
	if existing then
		existing:Destroy()
	end
end

local function findRequiredPart(mapModel: Model, partName: string): BasePart
	local inst = mapModel:FindFirstChild(partName, true)
	if inst and inst:IsA("BasePart") then
		return inst
	end
	error(("[MapService] Map '%s' missing required BasePart '%s'"):format(mapModel.Name, partName))
end

local function randomPointInPart(area: BasePart): Vector3
	-- Random point within the XZ bounds of the part, placed above the top face.
	local cf = area.CFrame
	local size = area.Size

	local rx = (math.random() - 0.5) * size.X
	local rz = (math.random() - 0.5) * size.Z

	local topY = (size.Y * 0.5) + 4 -- 4 studs above the top surface
	local localOffset = Vector3.new(rx, topY, rz)

	return (cf * CFrame.new(localOffset)).Position
end

local function teleportCharacterTo(character: Model, position: Vector3)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end

	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	hrp.CFrame = CFrame.new(position, position + hrp.CFrame.LookVector)
end

-- Killzone hook:
-- - Only kills if isRoundActive() is true
-- - Does NOT kill players who already finished (isFinished(userId) == true)
local function hookKillzone(mapModel: Model, isRoundActive: () -> boolean, isFinished: (number) -> boolean)
	local killzone = mapModel:FindFirstChild("Killzone", true)
	if not (killzone and killzone:IsA("BasePart")) then
		-- Not required, but recommended on your maps
		return
	end

	killzone.Touched:Connect(function(hit)
		if not isRoundActive() then
			return
		end

		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end

		local player = Players:GetPlayerFromCharacter(character)
		if player then
			-- Quick improvement: don't kill someone who's already finished this round
			if isFinished(player.UserId) then
				return
			end
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end

		humanoid.Health = 0
	end)
end

-- Loads a map from ServerStorage/Maps into Workspace/CurrentMap.
-- isRoundActive: provided by GameService to gate killzone behavior
-- isFinished: provided by GameService to avoid killing players after they finished
function MapService.LoadMap(mapName: string, isRoundActive: () -> boolean, isFinished: (number) -> boolean): Model
	local template = MapsFolder:FindFirstChild(mapName)
	if not template or not template:IsA("Model") then
		error(("[MapService] Map '%s' not found in ServerStorage/Maps"):format(mapName))
	end

	clearCurrentMap()

	local clone = template:Clone()
	clone.Name = CURRENT_MAP_NAME
	clone.Parent = Workspace

	hookKillzone(clone, isRoundActive, isFinished)

	return clone
end

function MapService.TeleportAllToStartingArea(mapModel: Model)
	local startingArea = findRequiredPart(mapModel, "StartingArea")

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local pos = randomPointInPart(startingArea)
			teleportCharacterTo(character, pos)
		end
	end
end

function MapService.GetFinishLine(mapModel: Model): BasePart
	return findRequiredPart(mapModel, "FinishLine")
end

return MapService
