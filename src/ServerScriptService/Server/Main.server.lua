--!strict
-- ServerScriptService/Server/Main.server.lua
-- Bootstraps server systems in the correct order

local ServerScriptService = game:GetService("ServerScriptService")
local ServerFolder = ServerScriptService:WaitForChild("Server")
local ServicesFolder = ServerFolder:WaitForChild("Services")

-- 1) Require and init RemoteService FIRST so RemoteEvents exist
local RemoteService = require(ServicesFolder:WaitForChild("RemoteService"))
RemoteService.Init()

local ObstacleService = require(ServicesFolder:WaitForChild("ObstacleService"))
local PlacementService = require(ServicesFolder:WaitForChild("PlacementService"))


PlacementService.Init()

-- 2) Now it is safe to require services that WaitForChild() remotes
local VoteService = require(ServicesFolder:WaitForChild("VoteService"))
local GameService = require(ServicesFolder:WaitForChild("GameService"))


VoteService.Init()
GameService.Start()


