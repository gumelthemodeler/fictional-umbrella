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

local SFX = {
	Swing = 140192907374090,       -- Sound when you punch the air
	Hit = 139795256698131,         -- Heavy meat punch sound
	BarrageHit = 132802057233724,  -- Faster, lighter punch sound
	Block = 136811265205147,       -- Metallic or dull thud sound
	GuardBreak = 112313065306810   -- Glass shatter or massive boom 
}

local CombatFolder = ReplicatedStorage:WaitForChild("CombatEvents")
local M1Event = CombatFolder:WaitForChild("M1Event")
local BarrageEvent = CombatFolder:WaitForChild("BarrageEvent")
local BlockEvent = CombatFolder:WaitForChild("BlockEvent")
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
local isSprinting = false
local inputBuffered = false
local lastM1 = 0
local barrageTask = nil 

-- Base speeds
local WALK_SPEED = 16
local SPRINT_SPEED = 28
local targetSpeed = WALK_SPEED

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

	sound.Ended:Connect(function()
		att:Destroy()
	end)
	Debris:AddItem(att, 5)
end

local function screenShake()
	task.spawn(function()
		for i = 1, 4 do
			local offset = CFrame.Angles(math.rad(math.random(-2, 2)), math.rad(math.random(-2, 2)), 0)
			camera.CFrame = camera.CFrame * offset
			task.wait()
		end
	end)
end

-- ==========================================
-- Movement & Camera Fluidity System
-- ==========================================
local currentTilt = 0
RunService.RenderStepped:Connect(function(deltaTime)
	if not character or not rootPart or not humanoid then return end
	if humanoid.Health <= 0 then return end

	-- 1. SMOOTH MOMENTUM ACCELERATION
	-- Interpolate the WalkSpeed so you don't instantly snap to max speed
	if not character:GetAttribute("Stunned") and not isBlocking and not isBarraging then
		humanoid.WalkSpeed = humanoid.WalkSpeed + (targetSpeed - humanoid.WalkSpeed) * (10 * deltaTime)
	end

	-- 2. DYNAMIC FOV ZOOM
	-- Reads physical velocity. The faster you move (or lunge), the more the camera pulls back
	local flatVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
	local targetFOV = 70 + (flatVelocity * 0.45) -- Multiplier controls zoom intensity
	targetFOV = math.clamp(targetFOV, 70, 95)

	-- Only lerp FOV if we aren't hard-tweening it elsewhere
	camera.FieldOfView = camera.FieldOfView + (targetFOV - camera.FieldOfView) * (8 * deltaTime)

	-- 3. CAMERA STRAFE TILTING
	-- Reads player input to lean the camera left or right
	local moveVector = require(player.PlayerScripts.PlayerModule):GetControls():GetMoveVector()
	local targetTilt = 0

	if moveVector.X < -0.1 then
		targetTilt = 2.5 -- Lean Left
	elseif moveVector.X > 0.1 then
		targetTilt = -2.5 -- Lean Right
	end

	currentTilt = currentTilt + (targetTilt - currentTilt) * (8 * deltaTime)
	camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, math.rad(currentTilt))
end)

VFXEvent.OnClientEvent:Connect(function(vfxType, position, attacker)
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false

	local randomRotation = CFrame.Angles(
		math.rad(math.random(0, 360)),
		math.rad(math.random(0, 360)),
		math.rad(math.random(0, 360))
	)

	if attacker == player then
		local screenOffset = CFrame.new(math.random(-12, 12)/10, math.random(-12, 12)/10, -2.5)
		part.CFrame = camera.CFrame * screenOffset * randomRotation
	else
		part.CFrame = CFrame.new(position) * randomRotation
	end

	part.Parent = Workspace

	local att = Instance.new("Attachment", part)
	local emitter = Instance.new("ParticleEmitter", att)

	emitter.Texture = "rbxassetid://16910627138" 
	emitter.Enabled = false 
	emitter.LightEmission = 1

	emitter.SpreadAngle = Vector2.new(360, 360) 
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-300, 300) 
	emitter.Acceleration = Vector3.new(0, -30, 0) 

	emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0)})
	emitter.Speed = NumberRange.new(20, 50) 
	emitter.Drag = 6 
	emitter.Lifetime = NumberRange.new(0.15, 0.25) 

	if vfxType == "Hit" then
		emitter:Emit(4)
		playSound(SFX.Hit, position, 1, math.random(90, 110)/100)

	elseif vfxType == "BarrageHit" then
		emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0)})
		emitter:Emit(2)
		playSound(SFX.BarrageHit, position, 0.6, math.random(110, 130)/100)

	elseif vfxType == "Block" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(150, 200, 255))
		emitter:Emit(3)
		playSound(SFX.Block, position, 1, math.random(90, 110)/100)

	elseif vfxType == "GuardBreak" then
		emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0)})
		emitter:Emit(10)
		playSound(SFX.GuardBreak, position, 1.5, 1)
		screenShake()
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
			screenShake()
			M1Event:FireServer(hum, currentCombo) 

			local currentAnim = punchAnims[currentCombo]
			if currentAnim then currentAnim:AdjustSpeed(0) end

			-- Temporarily anchor for hitstop impact
			rootPart.Anchored = true 

			local pauseTime = (currentCombo == 3) and 0.12 or 0.08
			task.delay(pauseTime, function()
				if currentAnim then currentAnim:AdjustSpeed(1) end
				rootPart.Anchored = false
			end)

			break 
		end
	end

	if not hitSomeone then
		playSound(SFX.Swing, hitboxCFrame.Position, 0.8, math.random(90, 110)/100)
	end
end

local function stopBarrage()
	if not isBarraging then return end
	isBarraging = false

	if barrageTask then
		task.cancel(barrageTask)
		barrageTask = nil
	end

	if not isBlocking and not character:GetAttribute("Stunned") then 
		humanoid.WalkSpeed = isSprinting and SPRINT_SPEED or WALK_SPEED
	end

	barrageTrack:Stop(0)
	BarrageEvent:FireServer(false)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if character:GetAttribute("Stunned") then return end

	-- MOMENTUM SPRINT (Left Shift)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		isSprinting = true
		targetSpeed = SPRINT_SPEED
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isBarraging or isBlocking then return end

		if isAttacking then
			inputBuffered = true
			return 
		end

		local function triggerAttack()
			if tick() - lastM1 > 1.5 then combo = 1 end

			isAttacking = true
			inputBuffered = false
			lastM1 = tick()

			-- MOVEMENT LUNGE: Instead of slowing down completely, push the player forward
			-- This retains combat mobility and works beautifully with the FOV zoom
			local lookVector = rootPart.CFrame.LookVector
			local lungeForce = (combo == 3) and 65 or 40 -- Heavy finisher pushes you further
			rootPart.AssemblyLinearVelocity = Vector3.new(lookVector.X * lungeForce, rootPart.AssemblyLinearVelocity.Y, lookVector.Z * lungeForce)

			local currentTrack = punchAnims[combo]
			currentTrack:Play()

			local comboToCast = combo
			task.delay(0.15, function()
				castHitbox(comboToCast)
			end)

			combo = combo + 1
			if combo > 3 then 
				combo = 1 
				task.wait(0.5) 
			else
				task.wait(0.3) 
			end

			isAttacking = false

			if inputBuffered then
				triggerAttack()
			end
		end

		triggerAttack()

	elseif input.KeyCode == Enum.KeyCode.E then
		if isAttacking or isBlocking or isBarraging then return end

		isBarraging = true
		humanoid.WalkSpeed = 6 -- Move slightly faster during barrage to chase targets

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
	if input.KeyCode == Enum.KeyCode.LeftShift then
		isSprinting = false
		targetSpeed = WALK_SPEED

	elseif input.KeyCode == Enum.KeyCode.E then
		stopBarrage()

	elseif input.KeyCode == Enum.KeyCode.F and isBlocking then
		isBlocking = false
		if not isBarraging and not character:GetAttribute("Stunned") then 
			humanoid.WalkSpeed = isSprinting and SPRINT_SPEED or WALK_SPEED 
		end
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