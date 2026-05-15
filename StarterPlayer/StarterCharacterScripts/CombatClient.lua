-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local animator = humanoid:WaitForChild("Animator")
local camera = Workspace.CurrentCamera

local DEBUG_HITBOXES = false 
local MAX_BARRAGE_DURATION = 3 
local SLAM_COOLDOWN = 6

local SFX = {
	Swing = 140192907374090,       
	Hit = 139795256698131,         
	BarrageHit = 132802057233724,  
	Block = 14081042148,       
	GuardBreak = 112313065306810,
	Dodge = 134184377306867, -- ADD DODGE ID
	Slam = 000000000   -- ADD SLAM ID
}

local CombatFolder = ReplicatedStorage:WaitForChild("CombatEvents")
local M1Event = CombatFolder:WaitForChild("M1Event")
local BarrageEvent = CombatFolder:WaitForChild("BarrageEvent")
local BlockEvent = CombatFolder:WaitForChild("BlockEvent")
local SlamEvent = CombatFolder:WaitForChild("SlamEvent")
local VFXEvent = CombatFolder:WaitForChild("VFXEvent")

local function loadTrack(id, priority)
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(id)
	local track = animator:LoadAnimation(anim)
	track.Priority = priority
	return track
end

local punchAnims = {
	loadTrack(108009811660864, Enum.AnimationPriority.Action), 
	loadTrack(135763891658649, Enum.AnimationPriority.Action), 
	loadTrack(75960080109635, Enum.AnimationPriority.Action)    
}

local barrageTrack = loadTrack(83255714793793, Enum.AnimationPriority.Action4)
local blockTrack = loadTrack(0000000000, Enum.AnimationPriority.Action) 

local combo = 1
local isAttacking = false
local isBarraging = false
local isBlocking = false
local inputBuffered = false
local lastM1 = 0
local barrageTask = nil 
local lastSlamTime = 0 -- Local cooldown tracker

local function playSound(soundId, position, volume, pitch)
	if soundId == 0 then return end 
	local att = Instance.new("Attachment")
	att.Position = position
	att.Parent = Workspace.Terrain
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Volume = volume or 1
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = att
	sound:Play()
	sound.Ended:Connect(function() att:Destroy() end)
	Debris:AddItem(att, 5)
end

local function screenShake(intensity)
	intensity = intensity or 0.4 
	task.spawn(function()
		for i = 1, 3 do 
			local rx = (math.random(-10, 10) / 10) * intensity
			local ry = (math.random(-10, 10) / 10) * intensity
			local offset = CFrame.Angles(math.rad(rx), math.rad(ry), 0)
			camera.CFrame = camera.CFrame * offset
			task.wait()
		end
	end)
end

VFXEvent.OnClientEvent:Connect(function(vfxType, position, attacker)
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = CFrame.new(position, camera.CFrame.Position) * CFrame.new(0, 0, -1)
	part.Parent = Workspace

	local att = Instance.new("Attachment", part)

	local hitmarker = Instance.new("ParticleEmitter", att)
	hitmarker.Texture = "rbxassetid://16910627138" 
	hitmarker.Enabled = false 
	hitmarker.LightEmission = 1
	hitmarker.ZOffset = 1 
	hitmarker.LockedToPart = true 
	hitmarker.Speed = NumberRange.new(0)
	hitmarker.Rotation = NumberRange.new(0, 360) 
	hitmarker.RotSpeed = NumberRange.new(0) 
	hitmarker.Lifetime = NumberRange.new(0.12, 0.15) 

	local sparks = Instance.new("ParticleEmitter", att)
	sparks.Texture = "rbxassetid://281983280"
	sparks.Enabled = false
	sparks.LightEmission = 1
	sparks.ZOffset = 0.5
	sparks.SpreadAngle = Vector2.new(360, 360)
	sparks.Speed = NumberRange.new(40, 75)
	sparks.Drag = 8
	sparks.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0)})
	sparks.Lifetime = NumberRange.new(0.15, 0.25)

	if vfxType == "Hit" then
		hitmarker.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.1, 2.5), NumberSequenceKeypoint.new(1, 0)
		})
		hitmarker:Emit(1) 
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 180, 80))
		sparks:Emit(4)
		playSound(SFX.Hit, position, 1, math.random(90, 110)/100)

	elseif vfxType == "BarrageHit" then
		hitmarker.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.1, 1.2), NumberSequenceKeypoint.new(1, 0)
		})
		hitmarker:Emit(1)
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 100))
		sparks:Emit(2)
		playSound(SFX.BarrageHit, position, 0.6, math.random(110, 130)/100)

	elseif vfxType == "Block" then
		hitmarker.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.1, 2), NumberSequenceKeypoint.new(1, 0)
		})
		hitmarker.Color = ColorSequence.new(Color3.fromRGB(150, 200, 255))
		hitmarker:Emit(1)
		sparks.Color = ColorSequence.new(Color3.fromRGB(100, 150, 255))
		sparks:Emit(3)
		playSound(SFX.Block, position, 1, math.random(90, 110)/100)

	elseif vfxType == "GuardBreak" then
		hitmarker.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.1, 4.5), NumberSequenceKeypoint.new(1, 0)
		})
		hitmarker:Emit(2)
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 100, 50))
		sparks.Speed = NumberRange.new(80, 120)
		sparks:Emit(12)
		playSound(SFX.GuardBreak, position, 1.5, 1)
		screenShake(2.5) 

	elseif vfxType == "Dodge" then
		sparks.Color = ColorSequence.new(Color3.fromRGB(150, 220, 255))
		sparks.Speed = NumberRange.new(20, 40)
		sparks:Emit(8)
		playSound(SFX.Dodge, position, 1.2, 1)

	elseif vfxType == "Slam" then
		part.CFrame = CFrame.new(position) * CFrame.Angles(math.pi/2, 0, 0) 
		hitmarker.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.1, 15), NumberSequenceKeypoint.new(1, 0)
		})
		hitmarker.Color = ColorSequence.new(Color3.fromRGB(255, 80, 0))
		hitmarker:Emit(3)

		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 100, 0))
		sparks.Speed = NumberRange.new(100, 150)
		sparks:Emit(30)

		playSound(SFX.Slam, position, 2, 0.8)
		screenShake(3.0) 
	end

	Debris:AddItem(part, 0.5)
end)

local function castHitbox(currentCombo)
	local hitboxCFrame = rootPart.CFrame * CFrame.new(0, 0, -3)
	local hitboxSize = (currentCombo == 3) and Vector3.new(5, 6, 5) or Vector3.new(4, 5, 4)

	if DEBUG_HITBOXES then
		local debugBox = Instance.new("Part")
		debugBox.Size = hitboxSize
		debugBox.CFrame = hitboxCFrame
		debugBox.Anchored = true
		debugBox.CanCollide = false
		debugBox.Transparency = 0.6
		debugBox.Color = Color3.fromRGB(255, 0, 0)
		debugBox.Material = Enum.Material.Neon
		debugBox.Parent = Workspace
		Debris:AddItem(debugBox, 0.15)
	end

	local params = OverlapParams.new()
	params.FilterDescendantsInstances = {character}
	params.FilterType = Enum.RaycastFilterType.Exclude

	local hits = Workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, params)
	local hitSomeone = false

	for _, p in ipairs(hits) do
		local hum = p.Parent:FindFirstChild("Humanoid")
		if hum and hum.Health > 0 then
			hitSomeone = true
			screenShake(currentCombo == 3 and 1.2 or 0.4) 
			M1Event:FireServer(hum, currentCombo) 

			local currentAnim = punchAnims[currentCombo]
			if currentAnim then currentAnim:AdjustSpeed(0) end
			rootPart.Anchored = true 

			local pauseTime = (currentCombo == 3) and 0.12 or 0.08
			task.delay(pauseTime, function()
				if currentAnim then currentAnim:AdjustSpeed(1) end
				rootPart.Anchored = false
			end)
			break 
		end
	end

	if not hitSomeone then playSound(SFX.Swing, hitboxCFrame.Position, 0.8, math.random(90, 110)/100) end
end

-- ==========================================
-- GROUND SLAM MECHANIC (WITH WEIGHT & STUN)
-- ==========================================
local function performGroundSlam()
	-- Cooldown Check
	if tick() - lastSlamTime < SLAM_COOLDOWN then return end
	lastSlamTime = tick()

	isAttacking = true

	-- Pre-Slam Visual: Camera aggressively tilts down
	TweenService:Create(humanoid, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CameraOffset = Vector3.new(0, -1, 0)}):Play()

	-- Shoot violently downward
	rootPart.AssemblyLinearVelocity = Vector3.new(0, -180, 0)

	local connection
	local timeout = tick()

	connection = RunService.Heartbeat:Connect(function()
		if humanoid:GetState() ~= Enum.HumanoidStateType.Freefall or tick() - timeout > 2 then
			connection:Disconnect()

			-- IMPACT WEIGHT: Hard anchor the character so they absorb the impact
			rootPart.Anchored = true

			-- Post-Slam Visual: Camera recoils heavily back up
			TweenService:Create(humanoid, TweenInfo.new(0.3, Enum.EasingStyle.Bounce), {CameraOffset = Vector3.new(0, 0, 0)}):Play()

			SlamEvent:FireServer()

			-- RECOVERY STUN: Prevent them from moving/attacking for 0.4s
			task.delay(0.2, function()
				rootPart.Anchored = false
				task.wait(0.4) -- The stun window before they can fight again
				isAttacking = false
			end)
		end
	end)
end

local function stopBarrage()
	if not isBarraging then return end
	isBarraging = false
	if barrageTask then task.cancel(barrageTask) barrageTask = nil end
	if not isBlocking and not character:GetAttribute("Stunned") then humanoid.WalkSpeed = 16 end
	barrageTrack:Stop(0)
	BarrageEvent:FireServer(false)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if character:GetAttribute("Stunned") then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isBarraging or isBlocking then return end

		if humanoid:GetState() == Enum.HumanoidStateType.Freefall and camera.CFrame.LookVector.Y < -0.6 then
			if not isAttacking then performGroundSlam() end
			return
		end

		if isAttacking then
			inputBuffered = true
			return 
		end

		local function triggerAttack()
			if tick() - lastM1 > 1.5 then combo = 1 end

			isAttacking = true
			inputBuffered = false
			lastM1 = tick()

			local lookVector = rootPart.CFrame.LookVector
			local lungeForce = (combo == 3) and 65 or 40 
			rootPart.AssemblyLinearVelocity = Vector3.new(lookVector.X * lungeForce, rootPart.AssemblyLinearVelocity.Y, lookVector.Z * lungeForce)

			local currentTrack = punchAnims[combo]
			currentTrack:Play()

			local comboToCast = combo
			task.delay(0.15, function() castHitbox(comboToCast) end)

			combo = combo + 1
			if combo > 3 then 
				combo = 1 
				task.wait(0.5) 
			else
				task.wait(0.3) 
			end

			isAttacking = false
			if inputBuffered then triggerAttack() end
		end

		triggerAttack()

	elseif input.KeyCode == Enum.KeyCode.E then
		if isAttacking or isBlocking or isBarraging then return end
		isBarraging = true
		humanoid.WalkSpeed = 6 
		barrageTrack.Looped = true
		barrageTrack:Play()
		BarrageEvent:FireServer(true)
		barrageTask = task.delay(MAX_BARRAGE_DURATION, function()
			barrageTask = nil
			stopBarrage()
		end)

	elseif input.KeyCode == Enum.KeyCode.F then
		if isAttacking or isBarraging then return end
		isBlocking = true
		humanoid.WalkSpeed = 8 
		if blockTrack.Length > 0 then blockTrack:Play() end
		BlockEvent:FireServer(true)
	end
end)

UserInputService.InputEnded:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.E then
		stopBarrage()
	elseif input.KeyCode == Enum.KeyCode.F and isBlocking then
		isBlocking = false
		if not isBarraging and not character:GetAttribute("Stunned") then humanoid.WalkSpeed = 16 end
		if blockTrack.Length > 0 then blockTrack:Stop(0) end
		BlockEvent:FireServer(false)
	end
end)

character:GetAttributeChangedSignal("Stunned"):Connect(function()
	if character:GetAttribute("Stunned") then
		isBlocking = false
		isAttacking = false
		stopBarrage() 
		if blockTrack.Length > 0 then blockTrack:Stop(0) end
		BlockEvent:FireServer(false)
	end
end)