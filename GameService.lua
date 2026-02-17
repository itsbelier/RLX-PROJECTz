--!strict
-- ServerScriptService/Server/Services/GameService
-- Match state machine (MVP). Voting/Maps/Placement will plug into this.


local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = Shared:WaitForChild("Enums")
local Constants = Shared:WaitForChild("Constants")

local ServicesFolder = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local VoteService = require(ServicesFolder:WaitForChild("VoteService"))
local MapService = require(ServicesFolder:WaitForChild("MapService"))

local GameState = require(Enums:WaitForChild("GameState"))
local Timings = require(Constants:WaitForChild("Timings"))
local Scoring = require(Constants:WaitForChild("Scoring"))

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local RemotesIndex = require(RemotesFolder:WaitForChild("RemotesIndex"))

local ObstacleService = require(ServicesFolder:WaitForChild("ObstacleService"))
local PlacementService = require(ServicesFolder:WaitForChild("PlacementService"))


local function getEvent(name: string): RemoteEvent
	return RemotesFolder:WaitForChild(name) :: RemoteEvent
end

local RE_GameStateChanged = getEvent(RemotesIndex.RE_GameStateChanged)
local RE_TimerSync = getEvent(RemotesIndex.RE_TimerSync)

export type StateData = {
	state: string,
	endsAt: number?,
	round: number,
	selectedMap: string?,
}

local GameService = {}

local _running = false
local _state: StateData = {
	state = GameState.LobbyWaiting,
	endsAt = nil,
	round = 0,
	selectedMap = nil,
}

-- Current map
local _currentMapModel: Model? = nil

-- Scoring
local _scoreByUserId: {[number]: number} = {}
local _finishedThisRound: {[number]: boolean} = {}
local _firstFinisherUserId: number? = nil
local _finishConn: RBXScriptConnection? = nil

-- Death handling: stay dead until next cycle
local _roundActive = false
local _pendingRespawn: {[number]: boolean} = {}
local _deathConns: {[number]: RBXScriptConnection} = {}

-- Ensure default behavior outside rounds
Players.CharacterAutoLoads = true

local function playerCount(): number
	return #Players:GetPlayers()
end

local function broadcastState()
	RE_GameStateChanged:FireAllClients(_state)
end

local function broadcastTimer(endsAt: number)
	RE_TimerSync:FireAllClients({
		state = _state.state,
		endsAt = endsAt,
		round = _state.round,
	})
end

local function setState(newState: string, durationSeconds: number?)
	_state.state = newState
	if durationSeconds then
		_state.endsAt = os.clock() + durationSeconds
	else
		_state.endsAt = nil
	end

	print(("[GameService] State -> %s (round %d)"):format(_state.state, _state.round))
	broadcastState()
	if _state.endsAt then
		broadcastTimer(_state.endsAt)
	end
end

local function waitUntil(predicate: () -> boolean, timeoutSeconds: number?): boolean
	local start = os.clock()
	while true do
		if predicate() then
			return true
		end
		if timeoutSeconds and (os.clock() - start) >= timeoutSeconds then
			return false
		end
		task.wait(0.25)
	end
end

local function waitForMinimumPlayers(minPlayers: number)
	print(("[GameService] Waiting for at least %d players..."):format(minPlayers))
	waitUntil(function()
		return playerCount() >= minPlayers
	end, nil)
end

-- Score helpers
local function getScore(userId: number): number
	return _scoreByUserId[userId] or 0
end

local function addScore(userId: number, amount: number)
	_scoreByUserId[userId] = getScore(userId) + amount
end

-- Finish handling
local function disconnectFinish()
	if _finishConn then
		_finishConn:Disconnect()
		_finishConn = nil
	end
end

local function hookFinishLine(finishLine: BasePart)
	disconnectFinish()

	_finishedThisRound = {}
	_firstFinisherUserId = nil

	_finishConn = finishLine.Touched:Connect(function(hit)
		if not _roundActive then
			return -- Only count finishes during RoundRun
		end

		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end

		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		local userId = player.UserId
		if _finishedThisRound[userId] then
			return
		end

		_finishedThisRound[userId] = true

		-- Award points
		addScore(userId, Scoring.FinishPoints)

		if not _firstFinisherUserId then
			_firstFinisherUserId = userId
			if Scoring.FirstFinishBonus > 0 then
				addScore(userId, Scoring.FirstFinishBonus)
			end
			print(("[GameService] FIRST finish: %s (+%d +%d) total=%d"):format(
				player.Name,
				Scoring.FinishPoints,
				Scoring.FirstFinishBonus,
				getScore(userId)
				))
		else
			print(("[GameService] Finish: %s (+%d) total=%d"):format(
				player.Name,
				Scoring.FinishPoints,
				getScore(userId)
				))
		end
	end)
end

-- Death handling
local function disconnectDeathHooks()
	for userId, conn in pairs(_deathConns) do
		conn:Disconnect()
		_deathConns[userId] = nil
	end
end

local function hookDeathsForCurrentPlayers()
	disconnectDeathHooks()

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				_deathConns[player.UserId] = humanoid.Died:Connect(function()
					if _roundActive then
						_pendingRespawn[player.UserId] = true
						print("[GameService] Player died during round:", player.Name)
					end
				end)
			end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		if _roundActive then
			task.wait(0.1)
			hookDeathsForCurrentPlayers()
		end
	end)
end)

-- Game loop steps
local function runLobbyWaiting()
	setState(GameState.LobbyWaiting, Timings.LobbyWaitSeconds)

	local ok = waitUntil(function()
		return playerCount() >= 1 and os.clock() >= (_state.endsAt :: number)
	end, Timings.LobbyWaitSeconds + 5)

	if not ok then
		return
	end
end

local function runMapVote()
	setState(GameState.MapVote, Timings.MapVoteSeconds)
	local winner = VoteService.RunMapVote(Timings.MapVoteSeconds, 3)
	print("[GameService] Map vote winner:", winner)
	_state.selectedMap = winner
end

local function runLoading()
	setState(GameState.Loading, Timings.LoadingSeconds)

	local selected = _state.selectedMap
	if not selected then
		warn("[GameService] No selected map; defaulting to IndustrialMap")
		selected = "IndustrialMap"
		_state.selectedMap = selected
	end

	_currentMapModel = MapService.LoadMap(selected,
		function() return _roundActive end,
		function(userId: number) return _finishedThisRound[userId] == true end
	)


	MapService.TeleportAllToStartingArea(_currentMapModel)

	task.wait(Timings.LoadingSeconds)
end

local function respawnPendingPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		if _pendingRespawn[player.UserId] then
			player:LoadCharacter()
		end
	end

	task.wait(0.25)

	if _currentMapModel then
		MapService.TeleportAllToStartingArea(_currentMapModel)
	end

	_pendingRespawn = {}
end

local function runBuildPhase()
	setState(GameState.BuildPhase, Timings.BuildSeconds)

	-- Reset everyone to start for building
	if _currentMapModel then
		MapService.TeleportAllToStartingArea(_currentMapModel)
	end

	-- Respawn anyone who died last round and bring them to start
	respawnPendingPlayers()

	-- START BUILD: generate hands + enable server placement
	ObstacleService.BeginBuildPhase()
	if _currentMapModel then
		PlacementService.Enable(_currentMapModel)
	end

	task.wait(Timings.BuildSeconds)

	-- END BUILD: disable placement
	PlacementService.Disable()
end


local function runRound()
	setState(GameState.RoundRun, Timings.RoundSeconds)

	_roundActive = true
	_pendingRespawn = {}

	-- Disable automatic respawns during the round
	Players.CharacterAutoLoads = false

	-- Teleport all living players to start at round start
	if _currentMapModel then
		MapService.TeleportAllToStartingArea(_currentMapModel)
	end

	-- Hook death listeners and finish line for this round
	hookDeathsForCurrentPlayers()

	if _currentMapModel then
		local finish = MapService.GetFinishLine(_currentMapModel)
		hookFinishLine(finish)
	else
		warn("[GameService] No current map model during RoundRun.")
	end

	local endsAt = _state.endsAt :: number
	while os.clock() < endsAt do
		-- NEW: End early if everyone is either finished OR dead
		local players = Players:GetPlayers()
		local allDone = true

		for _, p in ipairs(players) do
			local userId = p.UserId
			local finished = _finishedThisRound[userId] == true
			local dead = _pendingRespawn[userId] == true

			if not finished and not dead then
				allDone = false
				break
			end
		end

		if allDone and #players > 0 then
			print("[GameService] All players finished or died. Ending round.")
			break
		end

		task.wait(0.25)
	end

	-- Round cleanup
	_roundActive = false
	disconnectFinish()
	disconnectDeathHooks()

	-- Re-enable respawns after round ends (but we still respawn at BuildPhase boundary)
	Players.CharacterAutoLoads = true
end

local function runRoundEnd()
	setState(GameState.RoundEnd, 3)
	task.wait(3)
end

local function runGameEnd()
	setState(GameState.GameEnd, Timings.GameEndScoreboardSeconds)
	task.wait(Timings.GameEndScoreboardSeconds)
end

local function getLeader(): (Player?, number)
	local bestPlayer: Player? = nil
	local bestScore = -1
	for _, p in ipairs(Players:GetPlayers()) do
		local s = getScore(p.UserId)
		if s > bestScore then
			bestScore = s
			bestPlayer = p
		end
	end
	return bestPlayer, bestScore
end

function GameService.Start()
	if _running then return end
	_running = true

	while _running do
		_state.round = 0
		_state.selectedMap = nil

		waitForMinimumPlayers(1)
		runLobbyWaiting()

		-- Vote ONCE per match, load ONCE per match
		runMapVote()
		runLoading()

		for roundNumber = 1, Timings.MaxRounds do
			_state.round = roundNumber

			runBuildPhase()
			runRound()

			local leader, best = getLeader()
			if leader and best >= Scoring.TargetScore then
				print("[GameService] Winner reached target:", leader.Name, best)
				break
			end

			runRoundEnd()
		end

		runGameEnd()
	end
end

return GameService
