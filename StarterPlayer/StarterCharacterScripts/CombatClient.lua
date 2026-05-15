-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local animator = humanoid:WaitForChild("Animator")
local camera = Workspace.CurrentCamera

local DEBUG_HITBOXES = false 
local MAX_BARRAGE_DURATION = 3 
local SLAM_COOLDOWN = 6
local HEAVY_COOLDOWN = 8

local SFX = {
	Swing = 140192907374090,       
	Hit = 139795256698131,         
	BarrageHit = 132802057233724,  
	Block = 14081042148,       
	GuardBreak = 112313065306810,
	Dodge = 134184377306867, 
	Slam = 000000000,
	Summon = 105835958131428, 
	TimeStop = 000000000, -- "ZA WARUDO"
	TimeResume = 000000000 -- Time resume clock tick
}

local CombatFolder = ReplicatedStorage:WaitForChild("CombatEvents")
local M1Event = CombatFolder:WaitForChild("M1Event")
local BarrageEvent = CombatFolder:WaitForChild("BarrageEvent")
local BlockEvent = CombatFolder:WaitForChild("BlockEvent")
local SlamEvent = CombatFolder:WaitForChild("SlamEvent")
local VFXEvent = CombatFolder:WaitForChild("VFXEvent")

local StandEvents = ReplicatedStorage:WaitForChild("StandEvents")
local SummonEvent = StandEvents:WaitForChild("SummonEvent")
local TimeStopEvent = StandEvents:WaitForChild("TimeStopEvent")

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

local standAnimator = nil
local standPunchAnims = {}
local standBarrageTrack = nil
local standHeavyTrack = nil

character:GetAttributeChangedSignal("StandSummoned"):Connect(function()
	if character:GetAttribute("StandSummoned") then
		local standName = character:GetAttribute("CurrentStand")
		local standModel = workspace:WaitForChild(player.Name .. "_" .. standName, 3)

		if standModel then
			local standHum = standModel:WaitForChild("Humanoid")
			standAnimator = standHum:WaitForChild("Animator")

			local function loadStandTrack(id, prio)
				local anim = Instance.new("Animation")
				anim.AnimationId = "rbxassetid://" .. tostring(id)
				local t = standAnimator:LoadAnimation(anim)
				t.Priority = prio
				return t
			end

			standPunchAnims = {
				loadStandTrack(0000000001, Enum.AnimationPriority.Action), 
				loadStandTrack(0000000002, Enum.AnimationPriority.Action), 
				loadStandTrack(0000000003, Enum.AnimationPriority.Action)  
			}
			standBarrageTrack = loadStandTrack(0000000004, Enum.AnimationPriority.Action4)
			standHeavyTrack = loadStandTrack(0000000005, Enum.AnimationPriority.Action4) -- Heavy Stand Punch
		end
	else
		standAnimator = nil
		standPunchAnims = {}
		standBarrageTrack = nil
		standHeavyTrack = nil
	end
end)

local combo = 1
local isAttacking = false
local isBarraging = false
local isBlocking = false
local inputBuffered = false
local lastM1 = 0
local barrageTask = nil 
local lastSlamTime = 0 
local lastHeavyTime = 0

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
	if vfxType == "TimeStop" then
		playSound(SFX.TimeStop, position, 2.5, 1)

		-- Massive Inversion Sphere
		local sphere = Instance.new("Part")
		sphere.Shape = Enum.PartType.Ball
		sphere.Material = Enum.Material.ForceField
		sphere.Color = Color3.fromRGB(150, 150, 255)
		sphere.Size = Vector3.new(1, 1, 1)
		sphere.Anchored = true
		sphere.CanCollide = false
		sphere.CFrame = CFrame.new(position)
		sphere.Parent = Workspace

		TweenService:Create(sphere, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(500, 500, 500), Transparency = 1
		}):Play()
		Debris:AddItem(sphere, 1)

		-- Screen Grayscale & Inversion setup
		local cc = Lighting:FindFirstChild("TimeStopCC") or Instance.new("ColorCorrectionEffect", Lighting)
		cc.Name = "TimeStopCC"
		TweenService:Create(cc, TweenInfo.new(0.5), {
			Saturation = -1, Contrast = 0.2, TintColor = Color3.fromRGB(180, 180, 255)
		}):Play()
		return

	elseif vfxType == "TimeResume" then
		playSound(SFX.TimeResume, position, 2, 1)
		local cc = Lighting:FindFirstChild("TimeStopCC")
		if cc then
			TweenService:Create(cc, TweenInfo.new(0.5), {
				Saturation = 0, Contrast = 0, TintColor = Color3.fromRGB(255, 255, 255)
			}):Play()
			task.delay(0.5, function() cc:Destroy() end)
		end
		return
	end

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

	elseif vfxType == "SummonAura" then
		hitmarker.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.1, 8), NumberSequenceKeypoint.new(1, 0)
		})
		hitmarker.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
		hitmarker:Emit(2)
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 255, 100))
		sparks.Speed = NumberRange.new(20, 60)
		sparks.Acceleration = Vector3.new(0, 50, 0) 
		sparks:Emit(25)
		playSound(SFX.Summon, position, 1.5, 1)
		screenShake(1.5)
	end

	Debris:AddItem(part, 0.5)
end)

local function castHitbox(currentCombo, isHeavy)
	local isStandOut = character:GetAttribute("StandSummoned")

	local forwardOffset = isStandOut and -5.5 or -3
	local hitboxCFrame = rootPart.CFrame * CFrame.new(0, 0, forwardOffset)

	local baseSize = isStandOut and Vector3.new(6, 7, 6) or Vector3.new(4, 5, 4)
	local hitboxSize = (currentCombo == 3 or isHeavy) and baseSize * 1.2 or baseSize

	local params = OverlapParams.new()
	params.FilterDescendantsInstances = {character}
	params.FilterType = Enum.RaycastFilterType.Exclude

	local hits = Workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, params)
	local hitSomeone = false

	for _, p in ipairs(hits) do
		local hum = p.Parent:FindFirstChild("Humanoid")
		if hum and hum.Health > 0 then
			hitSomeone = true
			screenShake((currentCombo == 3 or isHeavy) and 1.2 or 0.4) 

			-- Pass combo 3 logic if it's a Heavy attack to force the guard break/knockback
			M1Event:FireServer(hum, isHeavy and 3 or currentCombo) 

			local currentAnim = nil
			if isHeavy then currentAnim = standHeavyTrack
			elseif isStandOut then currentAnim = standPunchAnims[currentCombo]
			else currentAnim = punchAnims[currentCombo] end

			if currentAnim then currentAnim:AdjustSpeed(0) end
			rootPart.Anchored = true 

			local pauseTime = (currentCombo == 3 or isHeavy) and 0.12 or 0.08
			task.delay(pauseTime, function()
				if currentAnim then currentAnim:AdjustSpeed(1) end
				rootPart.Anchored = false
			end)
			break 
		end
	end

	if not hitSomeone then playSound(SFX.Swing, hitboxCFrame.Position, 0.8, math.random(90, 110)/100) end
end

local function stopBarrage()
	if not isBarraging then return end
	isBarraging = false
	if barrageTask then task.cancel(barrageTask) barrageTask = nil end
	if not isBlocking and not character:GetAttribute("Stunned") and not character:GetAttribute("TimeStopped") then humanoid.WalkSpeed = 16 end

	if character:GetAttribute("StandSummoned") and standBarrageTrack then standBarrageTrack:Stop(0)
	else barrageTrack:Stop(0) end

	BarrageEvent:FireServer(false)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if character:GetAttribute("Stunned") or character:GetAttribute("TimeStopped") then return end

	local isStandOut = character:GetAttribute("StandSummoned")

	if input.KeyCode == Enum.KeyCode.G then
		if isAttacking or isBlocking or isBarraging then return end
		SummonEvent:FireServer()
		if not isStandOut then VFXEvent:FireServer("SummonAura", rootPart.Position) end

	elseif input.KeyCode == Enum.KeyCode.Z then
		if isAttacking or isBlocking or isBarraging then return end
		if isStandOut and character:GetAttribute("CurrentStand") == "TheWorld" then
			TimeStopEvent:FireServer()
		end

	elseif input.KeyCode == Enum.KeyCode.R then
		if isAttacking or isBlocking or isBarraging or not isStandOut then return end
		if tick() - lastHeavyTime < HEAVY_COOLDOWN then return end
		lastHeavyTime = tick()

		isAttacking = true
		humanoid.WalkSpeed = 4
		if standHeavyTrack then standHeavyTrack:Play() end

		task.delay(0.25, function() castHitbox(nil, true) end)
		task.delay(0.6, function() 
			isAttacking = false 
			humanoid.WalkSpeed = 16 
		end)

	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
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

			local lookVector = rootPart.CFrame.LookVector
			local lungeForce = (combo == 3) and 65 or 40 
			rootPart.AssemblyLinearVelocity = Vector3.new(lookVector.X * lungeForce, rootPart.AssemblyLinearVelocity.Y, lookVector.Z * lungeForce)

			local currentTrack = (isStandOut and standPunchAnims[combo]) and standPunchAnims[combo] or punchAnims[combo]
			if currentTrack then currentTrack:Play() end

			local comboToCast = combo
			task.delay(0.15, function() castHitbox(comboToCast, false) end)

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

		local activeTrack = (isStandOut and standBarrageTrack) and standBarrageTrack or barrageTrack
		activeTrack.Looped = true
		activeTrack:Play()

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
		if not isBarraging and not character:GetAttribute("Stunned") and not character:GetAttribute("TimeStopped") then humanoid.WalkSpeed = 16 end
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