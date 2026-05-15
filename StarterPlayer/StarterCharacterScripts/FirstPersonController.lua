-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = Workspace.CurrentCamera
local animator = humanoid:WaitForChild("Animator")

player.CameraMode = Enum.CameraMode.Classic
player.CameraMaxZoomDistance = 0.5
player.CameraMinZoomDistance = 0.5

RunService.RenderStepped:Connect(function()
	if not character then return end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			if part.Name == "Head" or part.Name == "HumanoidRootPart" or part.Parent:IsA("Accessory") 
				or part.Name:match("Torso") then
				part.LocalTransparencyModifier = 1
			else
				part.LocalTransparencyModifier = 0
			end
		end
	end
end)

local isMouseUnlocked = false
RunService.RenderStepped:Connect(function()
	if isMouseUnlocked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
end)

-- ==========================================
-- Load Animations
-- ==========================================
local sprintAnim = Instance.new("Animation")
sprintAnim.AnimationId = "rbxassetid://124651765736727"
local sprintTrack = animator:LoadAnimation(sprintAnim)
sprintTrack.Priority = Enum.AnimationPriority.Movement

local slideAnim = Instance.new("Animation")
slideAnim.AnimationId = "rbxassetid://136273104090828" -- YOUR SLIDE ID
local slideTrack = animator:LoadAnimation(slideAnim)
slideTrack.Priority = Enum.AnimationPriority.Action 

-- ==========================================
-- DIRECTIONAL DASH ANIMATIONS (Replace IDs)
-- ==========================================

local function loadDashTrack(id)
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(id)
	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action3
	return track
end

local dashTracks = {
	F = loadDashTrack(92332496356968), -- Forward Dash
	B = loadDashTrack(80312135198613), -- Backward Dash
	L = loadDashTrack(130115019904122), -- Left Dash
	R = loadDashTrack(134848342051959)  -- Right Dash
}
-- Ensure Dash overrides everything
for _, track in pairs(dashTracks) do track.Priority = Enum.AnimationPriority.Action3 end

local MovementFolder = ReplicatedStorage:WaitForChild("MovementEvents")
local dashEvent = MovementFolder:WaitForChild("DashEvent")
local sprintEvent = MovementFolder:WaitForChild("SprintEvent")
local slideEvent = MovementFolder:WaitForChild("SlideEvent")

local isSprinting = false
local isSliding = false
local isDashing = false
local isWallRunning = false
local wallNormal = Vector3.zero
local wallRunSide = "None"

local currentSpeed = 16
local baseSpeed = 16
local sprintSpeed = 28
local absoluteMaxSpeed = 100 

local rootAttachment = rootPart:FindFirstChild("RootAttachment") or Instance.new("Attachment", rootPart)
rootAttachment.Name = "RootAttachment"

local dashVelocity = rootPart:FindFirstChild("DashVelocity") or Instance.new("LinearVelocity")
dashVelocity.Name = "DashVelocity"
dashVelocity.Attachment0 = rootAttachment
dashVelocity.MaxForce = 100000
dashVelocity.VectorVelocity = Vector3.zero
dashVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
dashVelocity.Enabled = false
dashVelocity.Parent = rootPart

local slideVelocity = rootPart:FindFirstChild("SlideVelocity") or Instance.new("LinearVelocity")
slideVelocity.Name = "SlideVelocity"
slideVelocity.Attachment0 = rootAttachment
slideVelocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
slideVelocity.MaxAxesForce = Vector3.new(100000, 0, 100000) 
slideVelocity.VectorVelocity = Vector3.zero
slideVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
slideVelocity.Enabled = false
slideVelocity.Parent = rootPart

local antiGravityForce = rootPart:FindFirstChild("AntiGravityForce") or Instance.new("VectorForce")
antiGravityForce.Name = "AntiGravityForce"
antiGravityForce.Attachment0 = rootAttachment
antiGravityForce.Force = Vector3.zero
antiGravityForce.RelativeTo = Enum.ActuatorRelativeTo.World
antiGravityForce.Parent = rootPart

local function stopSlide(keepMomentum)
	if not isSliding then return end
	isSliding = false
	slideVelocity.Enabled = false
	slideEvent:FireServer(false)

	if slideTrack.IsPlaying then slideTrack:Stop(0.2) end
	TweenService:Create(humanoid, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {CameraOffset = Vector3.new(0, 0, 0)}):Play()

	if not keepMomentum then
		local vel = rootPart.AssemblyLinearVelocity
		local flatVel = Vector3.new(vel.X, 0, vel.Z)
		if flatVel.Magnitude > sprintSpeed then
			rootPart.AssemblyLinearVelocity = Vector3.new(vel.X * 0.3, vel.Y, vel.Z * 0.3)
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	if humanoid.Health <= 0 then return end
	local state = humanoid:GetState()
	local flatVel = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude

	if state == Enum.HumanoidStateType.Freefall and isSprinting then
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {character}

		local rightRay = workspace:Raycast(rootPart.Position, rootPart.CFrame.RightVector * 2.5, rayParams)
		local leftRay = workspace:Raycast(rootPart.Position, -rootPart.CFrame.RightVector * 2.5, rayParams)

		if rightRay or leftRay then
			isWallRunning = true
			wallNormal = rightRay and rightRay.Normal or leftRay.Normal
			wallRunSide = rightRay and "Right" or "Left"
			antiGravityForce.Force = Vector3.new(0, workspace.Gravity * character:GetMass() * 0.9, 0)
			local vel = rootPart.AssemblyLinearVelocity
			if vel.Y < -8 then rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, -8, vel.Z) end
		else
			isWallRunning = false
			antiGravityForce.Force = Vector3.zero
			wallRunSide = "None"
		end
	else
		isWallRunning = false
		antiGravityForce.Force = Vector3.zero
		wallRunSide = "None"
	end

	if isSliding then
		humanoid.WalkSpeed = 0 
		if slideVelocity.Enabled then
			local currentVel = slideVelocity.VectorVelocity
			if currentVel.Magnitude > 0 then
				local newMag = math.max(currentVel.Magnitude - (45 * dt), 0)
				local lookDir = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z).Unit
				local newDir = currentVel.Unit:Lerp(lookDir, 3 * dt).Unit

				slideVelocity.VectorVelocity = newDir * newMag
				if newMag < 12 then stopSlide(false) end
			end
		end
	else
		if state == Enum.HumanoidStateType.Freefall then
			humanoid.WalkSpeed = math.max(baseSpeed, flatVel)
		elseif isSprinting then
			currentSpeed = math.min(currentSpeed + (12 * dt), sprintSpeed)
			humanoid.WalkSpeed = currentSpeed
		else
			currentSpeed = math.max(currentSpeed - (35 * dt), baseSpeed)
			humanoid.WalkSpeed = currentSpeed
		end
	end
end)

local currentTilt = 0
RunService.RenderStepped:Connect(function(dt)
	if humanoid.Health <= 0 then return end

	local flatVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
	local targetFOV = 70 + (flatVelocity * 0.35) 
	targetFOV = math.clamp(targetFOV, 70, 110)
	camera.FieldOfView = camera.FieldOfView + (targetFOV - camera.FieldOfView) * (10 * dt)

	local targetTilt = 0
	if isWallRunning then
		targetTilt = (wallRunSide == "Right") and -15 or 15
	elseif isSliding then
		targetTilt = 0
	else
		local moveVector = require(player.PlayerScripts.PlayerModule):GetControls():GetMoveVector()
		if moveVector.X < -0.1 then targetTilt = 3.5
		elseif moveVector.X > 0.1 then targetTilt = -3.5 end
	end

	currentTilt = currentTilt + (targetTilt - currentTilt) * (10 * dt)
	camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, math.rad(currentTilt))
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		isSprinting = true
		sprintEvent:FireServer(true)
		if sprintTrack.Length > 0 then sprintTrack:Play() end

	elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
		if humanoid:GetState() == Enum.HumanoidStateType.Running or humanoid:GetState() == Enum.HumanoidStateType.RunningNoPhysics then
			isSliding = true
			slideEvent:FireServer(true)

			if sprintTrack.IsPlaying then sprintTrack:Stop(0.1) end
			if slideTrack.Length > 0 then slideTrack:Play() end
			TweenService:Create(humanoid, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CameraOffset = Vector3.new(0, -2, 0)}):Play()

			local currentFlatSpeed = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
			local initSpeed = math.min(currentFlatSpeed + 35, absoluteMaxSpeed)
			local lookVector = camera.CFrame.LookVector
			local slideDir = Vector3.new(lookVector.X, 0, lookVector.Z).Unit

			slideVelocity.VectorVelocity = slideDir * initSpeed
			slideVelocity.Enabled = true
		end

	elseif input.KeyCode == Enum.KeyCode.Space then
		if isWallRunning then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			local jumpDir = (wallNormal + Vector3.new(0, 1.2, 0)).Unit
			rootPart.AssemblyLinearVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z) 
			rootPart:ApplyImpulse(jumpDir * character:GetMass() * 65)

		elseif isSliding then
			local jumpSpeed = slideVelocity.VectorVelocity.Magnitude
			local jumpDir = slideVelocity.VectorVelocity.Unit

			stopSlide(true) 
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			rootPart.AssemblyLinearVelocity = Vector3.new(jumpDir.X * jumpSpeed, 50, jumpDir.Z * jumpSpeed)
		end

	elseif input.KeyCode == Enum.KeyCode.Q then
		if isDashing then return end
		isDashing = true

		local moveVector = require(player.PlayerScripts.PlayerModule):GetControls():GetMoveVector()
		local dashDir = Vector3.zero

		-- DYNAMIC DIRECTIONAL ANIMATION SELECTOR
		local trackToPlay = dashTracks.F -- Default forward

		if moveVector.Magnitude > 0 then
			local lookVector = camera.CFrame.LookVector
			local rightVector = camera.CFrame.RightVector
			local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
			local flatRight = Vector3.new(rightVector.X, 0, rightVector.Z).Unit
			dashDir = ((flatLook * -moveVector.Z) + (flatRight * moveVector.X)).Unit

			-- Select Animation based on raw input vector
			if math.abs(moveVector.X) > math.abs(moveVector.Z) then
				trackToPlay = moveVector.X < 0 and dashTracks.L or dashTracks.R
			else
				trackToPlay = moveVector.Z > 0 and dashTracks.B or dashTracks.F
			end
		else
			dashDir = Vector3.new(-camera.CFrame.LookVector.X, 0, -camera.CFrame.LookVector.Z).Unit
		end

		-- Play the specific directional animation
		trackToPlay:Play(0.1)

		dashEvent:FireServer(dashDir)
		dashVelocity.VectorVelocity = dashDir * 85
		dashVelocity.Enabled = true

		task.delay(0.2, function()
			dashVelocity.Enabled = false
			dashVelocity.VectorVelocity = Vector3.zero
			isDashing = false
		end)

	elseif input.KeyCode == Enum.KeyCode.LeftAlt then
		isMouseUnlocked = true
	end
end)

UserInputService.InputEnded:Connect(function(input, gp)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		isSprinting = false
		sprintEvent:FireServer(false)
		if sprintTrack.IsPlaying then sprintTrack:Stop() end
	elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
		stopSlide(false)
	elseif input.KeyCode == Enum.KeyCode.LeftAlt then
		isMouseUnlocked = false
	end
end)