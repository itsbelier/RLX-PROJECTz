--!strict
-- ReplicatedStorage/Shared/Constants/Timings
-- Centralized timers for the game loop

local Timings = {
	LobbyWaitSeconds = 5,
	MapVoteSeconds = 5,
	LoadingSeconds = 5,
	BuildSeconds = 5,
	RoundSeconds = 5,
	GameEndScoreboardSeconds = 5, -- how long to show results before return to lobby
	MaxRounds = 2,
}

return Timings