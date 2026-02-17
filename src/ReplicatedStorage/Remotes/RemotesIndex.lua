--!strict
-- ReplicatedStorage/Remotes/RemotesIndex

local RemotesIndex = {
	-- Server -> Client
	RE_GameStateChanged = "RE_GameStateChanged",
	RE_TimerSync = "RE_TimerSync",

	RE_VoteOptions = "RE_VoteOptions",
	RE_VoteUpdate = "RE_VoteUpdate",
	RE_VoteResult = "RE_VoteResult",

	RE_ObstacleHand = "RE_ObstacleHand",
	RE_PlacementError = "RE_PlacementError",
	RE_ObstaclePlaced = "RE_ObstaclePlaced",
	RE_PlacementRemaining = "RE_PlacementRemaining",

	-- Client -> Server
	RE_SubmitVote = "RE_SubmitVote",
	RE_RequestObstacleHand = "RE_RequestObstacleHand",
	RE_PlaceObstacle = "RE_PlaceObstacle",


}

return RemotesIndex