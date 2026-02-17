--!strict
-- ServerScriptService/Server/Services/VoteService
-- Runs a server-authoritative map vote and returns the winning map name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local RemotesIndex = require(RemotesFolder:WaitForChild("RemotesIndex"))

local RE_VoteOptions = RemotesFolder:WaitForChild(RemotesIndex.RE_VoteOptions) :: RemoteEvent
local RE_VoteUpdate = RemotesFolder:WaitForChild(RemotesIndex.RE_VoteUpdate) :: RemoteEvent
local RE_VoteResult = RemotesFolder:WaitForChild(RemotesIndex.RE_VoteResult) :: RemoteEvent
local RE_SubmitVote = RemotesFolder:WaitForChild(RemotesIndex.RE_SubmitVote) :: RemoteEvent

local MapsFolder = ServerStorage:WaitForChild("Maps")

type VoteSession = {
	id: string,
	options: {string},
	votesByUserId: {[number]: string},
	tally: {[string]: number},
	endsAt: number,
	active: boolean,
}

local VoteService = {}

local currentSession: VoteSession? = nil

local function now(): number
	return os.clock()
end

local function makeId(): string
	return tostring(math.floor(os.clock() * 1000)) .. "_" .. tostring(math.random(100000, 999999))
end

local function getAllMapNames(): {string}
	local names: {string} = {}
	for _, child in ipairs(MapsFolder:GetChildren()) do
		if child:IsA("Model") then
			table.insert(names, child.Name)
		end
	end
	return names
end

local function pickRandomUnique(list: {string}, count: number): {string}
	local copy: {string} = {}
	for _, v in ipairs(list) do table.insert(copy, v) end

	-- Fisher-Yates shuffle
	for i = #copy, 2, -1 do
		local j = math.random(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end

	local out: {string} = {}
	for i = 1, math.min(count, #copy) do
		table.insert(out, copy[i])
	end
	return out
end

local function broadcastTally(session: VoteSession)
	-- Send tallies to everyone so UI can update live
	RE_VoteUpdate:FireAllClients({
		id = session.id,
		tally = session.tally,
		endsAt = session.endsAt,
		options = session.options,
	})
end

local function computeWinner(session: VoteSession): string
	-- Highest votes wins; ties -> random among tied
	local best = -1
	local tied: {string} = {}

	for _, name in ipairs(session.options) do
		local votes = session.tally[name] or 0
		if votes > best then
			best = votes
			tied = { name }
		elseif votes == best then
			table.insert(tied, name)
		end
	end

	-- If nobody voted, best will be 0; still pick randomly among all
	if #tied == 0 then
		return session.options[1]
	end
	return tied[math.random(1, #tied)]
end

function VoteService.Init()
	RE_SubmitVote.OnServerEvent:Connect(function(player: Player, sessionId: string, voteMapName: string)
		local session = currentSession
		if not session then return end
		if not session.active then return end
		if session.id ~= sessionId then return end
		if now() > session.endsAt then return end

		-- Validate option exists
		local valid = false
		for _, opt in ipairs(session.options) do
			if opt == voteMapName then
				valid = true
				break
			end
		end
		if not valid then return end

		local userId = player.UserId
		local previous = session.votesByUserId[userId]
		if previous == voteMapName then
			return -- no change
		end

		-- Remove previous vote
		if previous then
			session.tally[previous] = math.max(0, (session.tally[previous] or 0) - 1)
		end

		-- Apply new vote
		session.votesByUserId[userId] = voteMapName
		session.tally[voteMapName] = (session.tally[voteMapName] or 0) + 1

		broadcastTally(session)
	end)
end

-- Runs a vote and returns the winning map name.
function VoteService.RunMapVote(durationSeconds: number, optionCount: number): string
	local allMaps = getAllMapNames()
	if #allMaps == 0 then
		warn("[VoteService] No maps found in ServerStorage/Maps. Returning 'nil-map'.")
		return "NO_MAPS"
	end

	local options = pickRandomUnique(allMaps, math.max(1, optionCount))
	local session: VoteSession = {
		id = makeId(),
		options = options,
		votesByUserId = {},
		tally = {},
		endsAt = now() + durationSeconds,
		active = true,
	}

	-- Init tally entries
	for _, opt in ipairs(options) do
		session.tally[opt] = 0
	end

	currentSession = session

	-- Send options to clients
	RE_VoteOptions:FireAllClients({
		id = session.id,
		options = session.options,
		endsAt = session.endsAt,
	})

	-- Initial tally broadcast
	broadcastTally(session)

	-- Wait for vote to end
	while now() < session.endsAt do
		task.wait(0.25)
	end

	session.active = false
	local winner = computeWinner(session)

	RE_VoteResult:FireAllClients({
		id = session.id,
		winner = winner,
		tally = session.tally,
	})

	return winner
end

return VoteService
