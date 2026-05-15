-- @ScriptType: Script
-- @ScriptType: Script
-- Name: StandServer
-- Parent: ServerScriptService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

-- ==========================================
-- GHOST PHYSICS SETUP
-- ==========================================
-- Create a collision group for Stands so they NEVER collide with anything
pcall(function()
	PhysicsService:RegisterCollisionGroup("StandGroup")
	PhysicsService:CollisionGroupSetCollidable("StandGroup", "Default", false)
	PhysicsService:CollisionGroupSetCollidable("StandGroup", "StandGroup", false)
end)

local StandEvents = ReplicatedStorage:FindFirstChild("StandEvents")
if not StandEvents then
	StandEvents = Instance.new("Folder")
	StandEvents.Name = "StandEvents"
	StandEvents.Parent = ReplicatedStorage
end

local SummonEvent = StandEvents:FindFirstChild("SummonEvent") or Instance.new("RemoteEvent", StandEvents)
SummonEvent.Name = "SummonEvent"

local TimeStopEvent = StandEvents:FindFirstChild("TimeStopEvent") or Instance.new("RemoteEvent", StandEvents)
TimeStopEvent.Name = "TimeStopEvent"

local StandModels = ReplicatedStorage:WaitForChild("Stands"):WaitForChild("Models")
local ActiveStands = {}

local TS_COOLDOWN = 30
local TS_DURATION = 5
local lastTS = {}
local isTimeStopped = false

local function despawnStand(player)
	if ActiveStands[player] then
		ActiveStands[player]:Destroy()
		ActiveStands[player] = nil
		player:SetAttribute("StandSummoned", false)
	end
end

local function summonStand(player, standName)
	local char = player.Character
	if not char or char:GetAttribute("Stunned") or char:GetAttribute("TimeStopped") then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	if ActiveStands[player] then
		despawnStand(player)
		return
	end

	local standPrefab = StandModels:FindFirstChild(standName)
	if not standPrefab then warn("Stand model not found: " .. standName) return end

	local stand = standPrefab:Clone()
	stand.Name = player.Name .. "_" .. standName

	-- Paralyze the Humanoid's physics calculations so it doesn't drag the player
	local standHum = stand:FindFirstChildOfClass("Humanoid")
	if standHum then
		standHum.PlatformStand = true
		standHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		-- If EvaluateStateMachine exists (newer Studio versions), disable it to save massive performance
		pcall(function() standHum.EvaluateStateMachine = false end)
	end

	-- Completely strip all physics presence from the Stand parts
	for _, part in ipairs(stand:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false 
			part.CanQuery = false
			part.Massless = true
			part.Anchored = false
			part.CustomPhysicalProperties = PhysicalProperties.new(0.0001, 0, 0, 0, 0)

			pcall(function()
				part.CollisionGroup = "StandGroup"
			end)
		end
	end

	local standRoot = stand:FindFirstChild("HumanoidRootPart")
	if standRoot then
		local weld = Instance.new("Weld")
		weld.Name = "StandWeld"
		weld.Part0 = root
		weld.Part1 = standRoot
		weld.C0 = CFrame.new(1.5, 0.5, 2)
		weld.Parent = standRoot
	end

	stand.Parent = workspace
	ActiveStands[player] = stand

	player:SetAttribute("CurrentStand", standName)
	player:SetAttribute("StandSummoned", true)
end

SummonEvent.OnServerEvent:Connect(function(player)
	summonStand(player, "TheWorld")
end)

-- GLOBAL TIME STOP LOGIC
TimeStopEvent.OnServerEvent:Connect(function(player)
	local char = player.Character
	if not char or char:GetAttribute("Stunned") or char:GetAttribute("TimeStopped") then return end
	if not player:GetAttribute("StandSummoned") or player:GetAttribute("CurrentStand") ~= "TheWorld" then return end

	if isTimeStopped then return end 

	local currentTime = tick()
	if currentTime - (lastTS[player] or 0) < TS_COOLDOWN then return end
	lastTS[player] = currentTime

	isTimeStopped = true

	local CombatFolder = ReplicatedStorage:FindFirstChild("CombatEvents")
	local VFXEvent = CombatFolder and CombatFolder:FindFirstChild("VFXEvent")
	if VFXEvent then
		VFXEvent:FireAllClients("TimeStop", char.PrimaryPart.Position, player)
	end

	local frozenPlayers = {}

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Character then
			local targetChar = other.Character
			local root = targetChar:FindFirstChild("HumanoidRootPart")
			local hum = targetChar:FindFirstChildOfClass("Humanoid")

			if root and hum then
				root.Anchored = true
				targetChar:SetAttribute("TimeStopped", true)
				table.insert(frozenPlayers, targetChar)

				local animator = hum:FindFirstChild("Animator")
				if animator then
					for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
						track:AdjustSpeed(0)
					end
				end
			end
		end
	end

	task.wait(TS_DURATION)

	-- TIME RESUME
	for _, targetChar in ipairs(frozenPlayers) do
		if targetChar and targetChar.Parent then
			local root = targetChar:FindFirstChild("HumanoidRootPart")
			local hum = targetChar:FindFirstChildOfClass("Humanoid")

			if root then root.Anchored = false end
			targetChar:SetAttribute("TimeStopped", false)

			if hum then
				local animator = hum:FindFirstChild("Animator")
				if animator then
					for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
						track:AdjustSpeed(1)
					end
				end
			end
		end
	end

	isTimeStopped = false

	if VFXEvent then
		VFXEvent:FireAllClients("TimeResume", char.PrimaryPart.Position, player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	despawnStand(player)
end)