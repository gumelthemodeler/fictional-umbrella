-- @ScriptType: Script
-- @ScriptType: Script
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MovementFolder = ReplicatedStorage:FindFirstChild("MovementEvents")
if not MovementFolder then
	MovementFolder = Instance.new("Folder")
	MovementFolder.Name = "MovementEvents"
	MovementFolder.Parent = ReplicatedStorage
end

local dashEvent = MovementFolder:FindFirstChild("DashEvent") or Instance.new("RemoteEvent", MovementFolder)
dashEvent.Name = "DashEvent"

local sprintEvent = MovementFolder:FindFirstChild("SprintEvent") or Instance.new("RemoteEvent", MovementFolder)
sprintEvent.Name = "SprintEvent"

local slideEvent = MovementFolder:FindFirstChild("SlideEvent") or Instance.new("RemoteEvent", MovementFolder)
slideEvent.Name = "SlideEvent"

local PlayerStates = {}
local MAX_STAMINA = 100
local DASH_COST = 25
local SLIDE_INIT_COST = 10 
local STAMINA_REGEN_RATE = 15 

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

dashEvent.OnServerEvent:Connect(function(player, direction)
	local state = PlayerStates[player]
	if not state then return end

	local currentTime = os.clock()

	if currentTime - state.LastDashTime >= 1 and state.Stamina >= DASH_COST then
		state.Stamina = state.Stamina - DASH_COST
		state.LastDashTime = currentTime
		state.IsDashing = true

		local char = player.Character
		if char then 
			char:SetAttribute("Invincible", true) 

			-- I-FRAME VISUAL HIGHLIGHT
			local highlight = Instance.new("Highlight")
			highlight.Name = "IFrameGlow"
			highlight.FillColor = Color3.fromRGB(0, 255, 255) -- Cyan glow
			highlight.FillTransparency = 0.4
			highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
			highlight.OutlineTransparency = 0.2
			highlight.Parent = char
		end

		task.delay(0.3, function()
			if PlayerStates[player] then
				PlayerStates[player].IsDashing = false
			end
			if char then 
				char:SetAttribute("Invincible", false) 
				local glow = char:FindFirstChild("IFrameGlow")
				if glow then glow:Destroy() end
			end
		end)
	end
end)

sprintEvent.OnServerEvent:Connect(function(player, isSprinting)
	local state = PlayerStates[player]
	if not state then return end
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

slideEvent.OnServerEvent:Connect(function(player, isSliding)
	local state = PlayerStates[player]
	if not state then return end

	local character = player.Character
	if not character or not character:FindFirstChild("Humanoid") then return end

	if isSliding then
		if state.Stamina >= SLIDE_INIT_COST and not state.IsSliding then
			state.Stamina = state.Stamina - SLIDE_INIT_COST
			state.IsSliding = true
			state.IsSprinting = false 
			character.Humanoid.WalkSpeed = 65 
		end
	else
		if state.IsSliding then
			state.IsSliding = false
			character.Humanoid.WalkSpeed = 16
		end
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	for player, state in pairs(PlayerStates) do
		if state.IsSliding then
			state.Stamina = math.clamp(state.Stamina - (15 * deltaTime), 0, MAX_STAMINA)
			if state.Stamina <= 0 then
				state.IsSliding = false
				if player.Character and player.Character:FindFirstChild("Humanoid") then
					player.Character.Humanoid.WalkSpeed = 16
				end
			end
		elseif state.IsSprinting then
			state.Stamina = math.clamp(state.Stamina - (10 * deltaTime), 0, MAX_STAMINA)
			if state.Stamina <= 0 then
				state.IsSprinting = false
				if player.Character and player.Character:FindFirstChild("Humanoid") then
					player.Character.Humanoid.WalkSpeed = 16
				end
			end
		elseif not state.IsDashing then
			if state.Stamina < MAX_STAMINA then
				state.Stamina = math.clamp(state.Stamina + (STAMINA_REGEN_RATE * deltaTime), 0, MAX_STAMINA)
			end
		end
	end
end)