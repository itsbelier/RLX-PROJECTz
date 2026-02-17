--!strict
-- ServerScriptService/Server/Services/ObstacleService
-- Chooses randomized obstacle options ("hand") for each player and tracks placements remaining.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ObstaclesFolder = Shared:WaitForChild("Obstacles")
local ObstaclesCatalog = require(ObstaclesFolder:WaitForChild("ObstaclesCatalog"))

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local RemotesIndex = require(RemotesFolder:WaitForChild("RemotesIndex"))

local RE_ObstacleHand = RemotesFolder:WaitForChild(RemotesIndex.RE_ObstacleHand) :: RemoteEvent

local ObstacleService = {}

local _handByUserId: {[number]: {string}} = {}
local _remainingByUserId: {[number]: number} = {}

local function shuffle(list: {string})
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function getPlacementsPerPlayer(playerCount: number): number
	-- Your design:
	-- 2-4 => 3 each
	-- 5-9 => 2 each (fills your missing “5” case)
	-- 10-12 => 1 each
	if playerCount <= 4 then return 3 end
	if playerCount <= 9 then return 2 end
	return 1
end

function ObstacleService.BeginBuildPhase()
	local allDefs = ObstaclesCatalog.GetAll()
	local allNames: {string} = {}
	for _, def in ipairs(allDefs) do
		table.insert(allNames, def.name)
	end

	local perPlayer = getPlacementsPerPlayer(#Players:GetPlayers())

	for _, player in ipairs(Players:GetPlayers()) do
		local choices = table.clone(allNames)
		shuffle(choices)

		-- Give 3 options (tweak later)
		local hand: {string} = {}
		for i = 1, math.min(3, #choices) do
			table.insert(hand, choices[i])
		end

		_handByUserId[player.UserId] = hand
		_remainingByUserId[player.UserId] = perPlayer

		RE_ObstacleHand:FireClient(player, {
			hand = hand,
			placementsRemaining = perPlayer,
		})
	end
end

function ObstacleService.GetHand(userId: number): {string}
	return _handByUserId[userId] or {}
end

function ObstacleService.GetRemaining(userId: number): number
	return _remainingByUserId[userId] or 0
end

function ObstacleService.ConsumePlacement(userId: number): boolean
	local r = _remainingByUserId[userId]
	if not r or r <= 0 then return false end
	_remainingByUserId[userId] = r - 1
	return true
end

function ObstacleService.ResetAll()
	_handByUserId = {}
	_remainingByUserId = {}
end

return ObstacleService
