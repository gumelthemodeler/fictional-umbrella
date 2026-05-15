-- @ScriptType: Script
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local CombatFolder = ReplicatedStorage:FindFirstChild("CombatEvents")
if not CombatFolder then
	CombatFolder = Instance.new("Folder")
	CombatFolder.Name = "CombatEvents"
	CombatFolder.Parent = ReplicatedStorage
end

local M1Event = CombatFolder:FindFirstChild("M1Event") or Instance.new("RemoteEvent", CombatFolder)
M1Event.Name = "M1Event"
local BarrageEvent = CombatFolder:FindFirstChild("BarrageEvent") or Instance.new("RemoteEvent", CombatFolder)
BarrageEvent.Name = "BarrageEvent"
local BlockEvent = CombatFolder:FindFirstChild("BlockEvent") or Instance.new("RemoteEvent", CombatFolder)
BlockEvent.Name = "BlockEvent"
local VFXEvent = CombatFolder:FindFirstChild("VFXEvent") or Instance.new("RemoteEvent", CombatFolder)
VFXEvent.Name = "VFXEvent"

local M1_DAMAGE = 5
local BARRAGE_DAMAGE = 0.5
local MAX_DIST = 12
local MAX_BARRAGE_DURATION = 3 

local activeBarrages = {}
local blockingPlayers = {}

local function applyStun(char, duration)
	char:SetAttribute("Stunned", true)
	local hum = char:FindFirstChild("Humanoid")
	if hum then hum.WalkSpeed = 2 end

	task.delay(duration, function()
		if char:GetAttribute("Stunned") then
			char:SetAttribute("Stunned", false)
			if hum then hum.WalkSpeed = 16 end
		end
	end)
end

local function applyKnockback(targetRoot, attackerRoot)
	local direction = (targetRoot.Position - attackerRoot.Position).Unit
	local launchVector = Vector3.new(direction.X, 0.5, direction.Z).Unit
	targetRoot.AssemblyLinearVelocity = launchVector * 65
end

BlockEvent.OnServerEvent:Connect(function(player, isBlocking)
	if isBlocking then
		blockingPlayers[player] = true
	else
		blockingPlayers[player] = nil
	end
end)

M1Event.OnServerEvent:Connect(function(player, targetHum, comboNumber)
	local char = player.Character
	if not char or char:GetAttribute("Stunned") then return end 
	if not targetHum or not targetHum.Parent then return end

	local root = char:FindFirstChild("HumanoidRootPart")
	local targetRoot = targetHum.Parent:FindFirstChild("HumanoidRootPart")
	local targetPlayer = Players:GetPlayerFromCharacter(targetHum.Parent)

	if root and targetRoot then
		local dist = (root.Position - targetRoot.Position).Magnitude
		if dist <= MAX_DIST then
			local targetChest = targetHum.Parent:FindFirstChild("Torso") or targetHum.Parent:FindFirstChild("UpperTorso") or targetRoot
			local hitPos = targetChest.Position + Vector3.new(math.random(-8, 8)/10, math.random(-8, 8)/10, math.random(-8, 8)/10)

			if targetPlayer and blockingPlayers[targetPlayer] then
				if comboNumber == 3 then
					blockingPlayers[targetPlayer] = nil
					applyStun(targetHum.Parent, 1.5) 
					VFXEvent:FireAllClients("GuardBreak", hitPos, player)
				else
					VFXEvent:FireAllClients("Block", hitPos, player)
				end
			else
				targetHum:TakeDamage(M1_DAMAGE)
				applyStun(targetHum.Parent, 0.6) 

				if comboNumber == 3 then
					applyKnockback(targetRoot, root)
				end

				VFXEvent:FireAllClients("Hit", hitPos, player)
			end
		end
	end
end)

BarrageEvent.OnServerEvent:Connect(function(player, state)
	local char = player.Character
	if char and char:GetAttribute("Stunned") then return end

	if state then 
		activeBarrages[player] = tick() 
	else 
		activeBarrages[player] = nil 
	end
end)

RunService.Heartbeat:Connect(function()
	local currentTime = tick()

	for player, startTime in pairs(activeBarrages) do
		if currentTime - startTime > (MAX_BARRAGE_DURATION + 0.2) then
			activeBarrages[player] = nil
			continue
		end

		local char = player.Character
		if char and char:GetAttribute("Stunned") then
			activeBarrages[player] = nil
			continue
		end

		if char and char:FindFirstChild("HumanoidRootPart") then
			local root = char.HumanoidRootPart
			local params = OverlapParams.new()
			params.FilterDescendantsInstances = {char}
			params.FilterType = Enum.RaycastFilterType.Exclude

			local hits = workspace:GetPartBoundsInBox(root.CFrame * CFrame.new(0, 0, -4), Vector3.new(6, 6, 8), params)
			local validated = {}

			for _, p in ipairs(hits) do
				local hum = p.Parent:FindFirstChild("Humanoid")
				if hum and not validated[hum] and hum.Health > 0 then
					validated[hum] = true

					local targetPlayer = Players:GetPlayerFromCharacter(hum.Parent)
					if not (targetPlayer and blockingPlayers[targetPlayer]) then
						hum:TakeDamage(BARRAGE_DAMAGE)
						applyStun(hum.Parent, 0.3) 

						local targetChest = hum.Parent:FindFirstChild("Torso") or hum.Parent:FindFirstChild("UpperTorso") or hum.Parent:FindFirstChild("HumanoidRootPart")
						if targetChest then
							local hitPos = targetChest.Position + Vector3.new(math.random(-18, 18)/10, math.random(-25, 25)/10, math.random(-18, 18)/10)
							VFXEvent:FireAllClients("BarrageHit", hitPos, player)
						end
					end
				end
			end
		else
			activeBarrages[player] = nil
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	activeBarrages[player] = nil
	blockingPlayers[player] = nil
end)
