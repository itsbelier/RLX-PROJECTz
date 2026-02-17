--!strict
-- StarterPlayerScripts/Client/Controllers/PlacementController
-- GUI-based build placement with ghost preview + server-authoritative placement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local RemotesIndex = require(RemotesFolder:WaitForChild("RemotesIndex"))

local RE_GameStateChanged = RemotesFolder:WaitForChild(RemotesIndex.RE_GameStateChanged) :: RemoteEvent
local RE_TimerSync = RemotesFolder:WaitForChild(RemotesIndex.RE_TimerSync) :: RemoteEvent
local RE_ObstacleHand = RemotesFolder:WaitForChild(RemotesIndex.RE_ObstacleHand) :: RemoteEvent
local RE_PlacementRemaining = RemotesFolder:WaitForChild(RemotesIndex.RE_PlacementRemaining) :: RemoteEvent
local RE_PlacementError = RemotesFolder:WaitForChild(RemotesIndex.RE_PlacementError) :: RemoteEvent
local RE_PlaceObstacle = RemotesFolder:WaitForChild(RemotesIndex.RE_PlaceObstacle) :: RemoteEvent

-- Clients cannot read ServerStorage, so for previews/ghost we need client-accessible prefabs:
-- ReplicatedStorage/ObstaclePrefabsClient with ob1..ob5 inside.
local ClientPrefabsFolder = ReplicatedStorage:WaitForChild("ObstaclePrefabsClient")

type HandPayload = {
	hand: {string},
	placementsRemaining: number,
}

type PlacementRemainingPayload = {
	placementsRemaining: number,
}

local PlacementController = {}

-- Connections
local conns: {RBXScriptConnection} = {}
local previewConns: {RBXScriptConnection} = {}

-- UI refs
local gui: ScreenGui? = nil
local root: Frame? = nil
local cardsFrame: Frame? = nil
local cardTemplate: TextButton? = nil

local hoverPreview: Frame? = nil
local hoverVP: ViewportFrame? = nil
local hoverName: TextLabel? = nil

local stateLabel: TextLabel? = nil
local timerLabel: TextLabel? = nil
local remainingLabel: TextLabel? = nil
local allUsedBanner: TextLabel? = nil

-- State
local inBuild = false
local placementsRemaining = 0
local currentHand: {string} = {}
local selectedObstacle: string? = nil

-- Ghost
local ghostModel: Model? = nil
local ghostConn: RBXScriptConnection? = nil
local ghostDepth = 40
local yaw = 0.0
local pitch = 0.0
local roll = 0.0

-- ========= utilities =========

local function clamp(x: number, a: number, b: number): number
	if x < a then return a end
	if x > b then return b end
	return x
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%02d:%02d", m, s)
end

local function setGuiVisible(visible: boolean)
	if not gui or not root then
		return
	end

	gui.Enabled = visible
	root.Visible = visible

	if not visible and hoverPreview then
		hoverPreview.Visible = false
	end
end

local function clearPreviewConns()
	for _, c in ipairs(previewConns) do
		c:Disconnect()
	end
	previewConns = {}
end

local function clearCards()
	if not cardsFrame or not cardTemplate then return end

	for _, child in ipairs(cardsFrame:GetChildren()) do
		if child ~= cardTemplate and child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	clearPreviewConns()
end

-- ========= viewport previews =========

local function setupViewport(viewport: ViewportFrame, obstacleName: string): (Model?, Camera)
	viewport:ClearAllChildren()
	viewport.BackgroundTransparency = 1

	local vpCam = Instance.new("Camera")
	vpCam.Name = "ViewportCamera"
	vpCam.Parent = viewport
	viewport.CurrentCamera = vpCam

	local prefab = ClientPrefabsFolder:FindFirstChild(obstacleName)
	if not prefab then
		warn("[PlacementController] Missing client prefab:", obstacleName)
		return nil, vpCam
	end

	local clone = prefab:Clone()
	local model: Model?

	if clone:IsA("Model") then
		model = clone
	elseif clone:IsA("BasePart") then
		local m = Instance.new("Model")
		m.Name = "PreviewModel"
		clone.Parent = m
		model = m
	else
		model = nil
	end

	if model then
		model.Name = "PreviewModel"
		model.Parent = viewport
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
			end
		end
		model:PivotTo(CFrame.new())
	end

	return model, vpCam
end

local function frameModelInCamera(model: Model, cam: Camera)
	local cf, size = model:GetBoundingBox()
	local maxDim = math.max(size.X, size.Y, size.Z)
	local dist = maxDim * 1.8 + 2

	local center = cf.Position
	local lookFrom = center + Vector3.new(dist, dist * 0.6, dist)
	cam.CFrame = CFrame.new(lookFrom, center)
	cam.FieldOfView = 40
end

local function startRotatingPreview(model: Model)
	local angle = 0.0
	local conn = RunService.RenderStepped:Connect(function(dt)
		angle += dt * 0.8
		model:PivotTo(CFrame.Angles(0, angle, 0))
	end)
	table.insert(previewConns, conn)
end

local function setSelectedCard(card: TextButton, selected: boolean)
	local stroke = card:FindFirstChild("SelectedStroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Enabled = selected
	end
end

local function rebuildCards()
	if not cardsFrame or not cardTemplate then return end

	clearCards()

	for i, obstacleName in ipairs(currentHand) do
		local card = cardTemplate:Clone()
		card.Name = "Card" .. tostring(i)
		card.Visible = true
		card.Active = true
		card.AutoButtonColor = true

		local vp = card:FindFirstChild("Viewport") :: ViewportFrame
		local nameLabel = card:FindFirstChild("NameLabel") :: TextLabel
		nameLabel.Text = obstacleName

		local model, vpCam = setupViewport(vp, obstacleName)
		if model then
			frameModelInCamera(model, vpCam)
			startRotatingPreview(model)
		end

		card.MouseEnter:Connect(function()
			if not hoverPreview or not hoverVP or not hoverName then return end
			hoverPreview.Visible = true
			hoverName.Text = obstacleName

			local hm, hc = setupViewport(hoverVP, obstacleName)
			if hm then
				frameModelInCamera(hm, hc)
				startRotatingPreview(hm)
			end
		end)

		card.MouseLeave:Connect(function()
			if not hoverPreview or not hoverVP then return end
			hoverPreview.Visible = false
			hoverVP:ClearAllChildren()
		end)

		card.MouseButton1Click:Connect(function()
			selectedObstacle = obstacleName
			for _, c in ipairs(cardsFrame:GetChildren()) do
				if c:IsA("TextButton") and c ~= cardTemplate then
					setSelectedCard(c, c == card)
				end
			end
			-- reset orientation when switching (optional)
			yaw, pitch, roll = 0, 0, 0
		end)

		card.Parent = cardsFrame
	end

	-- default select first
	if #currentHand > 0 then
		selectedObstacle = currentHand[1]
		local firstCard = cardsFrame:FindFirstChild("Card1")
		if firstCard and firstCard:IsA("TextButton") then
			setSelectedCard(firstCard, true)
		end
	end
end

-- ========= ghost + validity =========

local function destroyGhost()
	if ghostConn then
		ghostConn:Disconnect()
		ghostConn = nil
	end
	if ghostModel then
		ghostModel:Destroy()
		ghostModel = nil
	end
end

local function makeGhost(obstacleName: string): Model?
	local prefab = ClientPrefabsFolder:FindFirstChild(obstacleName)
	if not prefab then
		warn("[PlacementController] Missing client prefab for ghost:", obstacleName)
		return nil
	end

	local clone = prefab:Clone()
	local model: Model

	if clone:IsA("Model") then
		model = clone
	elseif clone:IsA("BasePart") then
		model = Instance.new("Model")
		clone.Parent = model
	else
		return nil
	end

	model.Name = "Ghost_" .. obstacleName
	model.Parent = workspace

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Transparency = 0.6
		end
	end

	return model
end

local function getMouseRay(): Ray
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	return Ray.new(ray.Origin, ray.Direction * 1000)
end

local function computeGhostCFrame(): CFrame?
	local ray = getMouseRay()

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = { player.Character, ghostModel :: any }
	params.IgnoreWater = true

	local result = workspace:Raycast(ray.Origin, ray.Direction, params)

	local targetPos: Vector3
	if result then
		targetPos = result.Position
	else
		targetPos = ray.Origin + ray.Direction.Unit * ghostDepth
	end

	local rot = CFrame.Angles(pitch, yaw, roll)
	return CFrame.new(targetPos) * rot
end

local function getPartInCurrentMap(partName: string): BasePart?
	local currentMap = workspace:FindFirstChild("CurrentMap")
	if not currentMap then return nil end
	local inst = currentMap:FindFirstChild(partName, true)
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function pointInsidePart(part: BasePart, worldPoint: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(worldPoint)
	local half = part.Size * 0.5
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

local function isGhostPlacementValid(worldPoint: Vector3): boolean
	local bounds = getPartInCurrentMap("PlacementBounds")
	if bounds and not pointInsidePart(bounds, worldPoint) then
		return false
	end

	local noStart = getPartInCurrentMap("NoPlace_Start")
	if noStart and pointInsidePart(noStart, worldPoint) then
		return false
	end

	local noFinish = getPartInCurrentMap("NoPlace_Finish")
	if noFinish and pointInsidePart(noFinish, worldPoint) then
		return false
	end

	return true
end

local function setGhostValidVisual(valid: boolean)
	if not ghostModel then return end
	for _, d in ipairs(ghostModel:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = valid and 0.6 or 0.85
		end
	end
end

local function updateGhost()
	if not ghostModel then return end
	local cf = computeGhostCFrame()
	if not cf then return end

	ghostModel:PivotTo(cf)

	local ok = isGhostPlacementValid(cf.Position)
	setGhostValidVisual(ok)
end

local function ensureGhost()
	if not inBuild then
		destroyGhost()
		return
	end

	if placementsRemaining <= 0 or not selectedObstacle then
		destroyGhost()
		return
	end

	if not ghostModel or ghostModel.Name ~= ("Ghost_" .. selectedObstacle) then
		destroyGhost()
		ghostModel = makeGhost(selectedObstacle)
		if not ghostModel then return end

		ghostConn = RunService.RenderStepped:Connect(updateGhost)
	end
end

local function tryPlaceSelected()
	if not inBuild then return end
	if placementsRemaining <= 0 then return end
	if not selectedObstacle then return end
	if UserInputService:GetFocusedTextBox() then return end

	local cf = computeGhostCFrame()
	if not cf then return end

	if not isGhostPlacementValid(cf.Position) then
		return
	end

	RE_PlaceObstacle:FireServer(selectedObstacle, cf)
end

-- ========= input =========

local function onInputBegan(input: InputObject, gp: boolean)
	if gp then return end
	if UserInputService:GetFocusedTextBox() then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		tryPlaceSelected()
		return
	end

	-- Rotations
	if input.KeyCode == Enum.KeyCode.R then yaw += math.rad(10) end
	if input.KeyCode == Enum.KeyCode.T then yaw -= math.rad(10) end

	if input.KeyCode == Enum.KeyCode.F then pitch += math.rad(5) end
	if input.KeyCode == Enum.KeyCode.G then pitch -= math.rad(5) end

	if input.KeyCode == Enum.KeyCode.V then roll += math.rad(10) end
	if input.KeyCode == Enum.KeyCode.B then roll -= math.rad(10) end

	ensureGhost()
end

local function onInputChanged(input: InputObject, gp: boolean)
	if gp then return end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		ghostDepth = clamp(ghostDepth + (-input.Position.Z * 4), 5, 250)
	end
end

-- ========= init / start =========

local function initUI()
	local playerGui = player:WaitForChild("PlayerGui")
	print("[PlacementController] initUI starting. PlayerGui children:", #playerGui:GetChildren())

	gui = (playerGui:WaitForChild("BuildGui")) :: ScreenGui
	print("[PlacementController] Found BuildGui:", gui:GetFullName())

	root = gui:WaitForChild("Root") :: Frame
	cardsFrame = root:WaitForChild("Cards") :: Frame
	cardTemplate = cardsFrame:WaitForChild("CardTemplate") :: TextButton

	local topBar = root:WaitForChild("TopBar") :: Frame
	stateLabel = topBar:WaitForChild("StateLabel") :: TextLabel
	timerLabel = topBar:WaitForChild("TimerLabel") :: TextLabel
	remainingLabel = topBar:WaitForChild("RemainingLabel") :: TextLabel

	allUsedBanner = root:WaitForChild("AllUsedBanner") :: TextLabel

	hoverPreview = gui:WaitForChild("HoverPreview") :: Frame
	hoverVP = hoverPreview:WaitForChild("Viewport") :: ViewportFrame
	hoverName = hoverPreview:WaitForChild("NameLabel") :: TextLabel

	-- Hide template
	cardTemplate.Visible = false
	cardTemplate.Active = false

	stateLabel.Text = "BUILD PHASE"
	timerLabel.Text = "00:00"
	remainingLabel.Text = "Remaining: 0"
	allUsedBanner.Visible = false

	setGuiVisible(false)

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
end

function PlacementController.Start()
	initUI()

	-- Connect remotes AFTER UI exists
	table.insert(conns, RE_GameStateChanged.OnClientEvent:Connect(function(stateData)
		inBuild = (stateData.state == "BuildPhase")
		setGuiVisible(inBuild)

		if not inBuild then
			selectedObstacle = nil
			destroyGhost()
		end

		ensureGhost()
	end))

	table.insert(conns, RE_TimerSync.OnClientEvent:Connect(function(payload)
		if inBuild and payload.endsAt and timerLabel then
			timerLabel.Text = formatTime(payload.endsAt - os.clock())
		end
	end))

	table.insert(conns, RE_ObstacleHand.OnClientEvent:Connect(function(payload: HandPayload)
		currentHand = payload.hand or {}
		placementsRemaining = payload.placementsRemaining or 0

		if remainingLabel then
			remainingLabel.Text = ("Remaining: %d"):format(placementsRemaining)
		end
		if allUsedBanner then
			allUsedBanner.Visible = placementsRemaining <= 0
		end

		rebuildCards()
		ensureGhost()
	end))

	table.insert(conns, RE_PlacementRemaining.OnClientEvent:Connect(function(payload: PlacementRemainingPayload)
		placementsRemaining = payload.placementsRemaining or placementsRemaining

		if remainingLabel then
			remainingLabel.Text = ("Remaining: %d"):format(placementsRemaining)
		end
		if allUsedBanner then
			allUsedBanner.Visible = placementsRemaining <= 0
		end

		if placementsRemaining <= 0 then
			selectedObstacle = nil
			destroyGhost()
		end

		ensureGhost()
	end))

	table.insert(conns, RE_PlacementError.OnClientEvent:Connect(function(payload)
		warn("[PlacementController] Placement error:", payload.message)
	end))
end

return PlacementController
