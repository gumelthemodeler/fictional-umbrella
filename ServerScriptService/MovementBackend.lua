-- @ScriptType: Script
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ==========================================
-- Networking Setup
-- ==========================================
local MovementFolder = ReplicatedStorage:FindFirstChild("MovementEvents")
if not MovementFolder then
	MovementFolder = Instance.new("Folder")
	MovementFolder.Name = "MovementEvents"
	MovementFolder.Parent = ReplicatedStorage
end

local dashEvent = Instance.new("RemoteEvent")
dashEvent.Name = "DashEvent"
dashEvent.Parent = MovementFolder

local sprintEvent = Instance.new("RemoteEvent")
sprintEvent.Name = "SprintEvent"
sprintEvent.Parent = MovementFolder

local slideEvent = Instance.new("RemoteEvent")
slideEvent.Name = "SlideEvent"
slideEvent.Parent = MovementFolder

-- ==========================================
-- Server State Machine
-- ==========================================
local PlayerStates = {}
local MAX_STAMINA = 100
local DASH_COST = 25
local SLIDE_INIT_COST = 10 -- Cost to begin a slide (prevents spamming for free boosts)
local STAMINA_REGEN_RATE = 15 -- Per second

local function initializePlayer(player)
	PlayerStates[player] = {
		IsSprinting = false,
		IsDashing = false,
		IsSliding = false,
		Stamina = MAX_STAMINA,
		LastDashTime = 0
	}
end

Players.PlayerAdded:Connect(function(player)
	initializePlayer(player)

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.WalkSpeed = 16
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerStates[player] = nil
end)

-- ==========================================
-- Event Handlers
-- ==========================================

-- Handle Dash Requests
dashEvent.OnServerEvent:Connect(function(player, direction)
	local state = PlayerStates[player]
	if not state then return end

	local currentTime = os.clock()

	if currentTime - state.LastDashTime >= 1 and state.Stamina >= DASH_COST then
		state.Stamina = state.Stamina - DASH_COST
		state.LastDashTime = currentTime
		state.IsDashing = true

		task.delay(0.3, function()
			if PlayerStates[player] then
				PlayerStates[player].IsDashing = false
			end
		end)
	end
end)

-- Handle Sprint Requests
sprintEvent.OnServerEvent:Connect(function(player, isSprinting)
	local state = PlayerStates[player]
	if not state then return end

	-- Don't allow sprinting if currently sliding
	if state.IsSliding then return end

	state.IsSprinting = isSprinting

	local character = player.Character
	if character and character:FindFirstChild("Humanoid") then
		if isSprinting and state.Stamina > 0 then
			character.Humanoid.WalkSpeed = 24
		else
			character.Humanoid.WalkSpeed = 16
		end
	end
end)

-- Handle Slide Requests
slideEvent.OnServerEvent:Connect(function(player, isSliding)
	local state = PlayerStates[player]
	if not state then return end

	local character = player.Character
	if not character or not character:FindFirstChild("Humanoid") then return end

	if isSliding then
		-- Only allow slide if they have enough stamina for the initial burst
		if state.Stamina >= SLIDE_INIT_COST and not state.IsSliding then
			state.Stamina = state.Stamina - SLIDE_INIT_COST
			state.IsSliding = true
			state.IsSprinting = false -- Sliding overrides sprint

			-- Server raises the speed cap significantly so the client's momentum physics aren't rubberbanded
			character.Humanoid.WalkSpeed = 45 
		end
	else
		if state.IsSliding then
			state.IsSliding = false
			-- Return to walk speed, sprint requires a new input to resume
			character.Humanoid.WalkSpeed = 16
		end
	end
end)

-- ==========================================
-- Stamina Regeneration & Drain Loop
-- ==========================================
RunService.Heartbeat:Connect(function(deltaTime)
	for player, state in pairs(PlayerStates) do

		if state.IsSliding then
			-- Drain stamina rapidly while holding a slide
			state.Stamina = math.clamp(state.Stamina - (15 * deltaTime), 0, MAX_STAMINA)

			if state.Stamina <= 0 then
				state.IsSliding = false
				if player.Character and player.Character:FindFirstChild("Humanoid") then
					player.Character.Humanoid.WalkSpeed = 16
				end
			end

		elseif state.IsSprinting then
			-- Drain stamina normally while sprinting
			state.Stamina = math.clamp(state.Stamina - (10 * deltaTime), 0, MAX_STAMINA)

			if state.Stamina <= 0 then
				state.IsSprinting = false
				if player.Character and player.Character:FindFirstChild("Humanoid") then
					player.Character.Humanoid.WalkSpeed = 16
				end
			end

		elseif not state.IsDashing then
			-- Regenerate stamina if doing nothing strenuous
			if state.Stamina < MAX_STAMINA then
				state.Stamina = math.clamp(state.Stamina + (STAMINA_REGEN_RATE * deltaTime), 0, MAX_STAMINA)
			end
		end

	end
end)