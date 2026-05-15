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

-- ==========================================
-- True First Person Setup
-- ==========================================
player.CameraMode = Enum.CameraMode.Classic
player.CameraMaxZoomDistance = 0.5
player.CameraMinZoomDistance = 0.5

-- Loop to force visibility of arms/legs, while hiding head/torso
RunService.RenderStepped:Connect(function()
	if not character then return end

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			-- Hide the Head, RootPart, Accessories, AND Torsos (Catches both R6 and R15)
			if part.Name == "Head" or part.Name == "HumanoidRootPart" or part.Parent:IsA("Accessory") 
				or part.Name:match("Torso") then
				part.LocalTransparencyModifier = 1
			else
				-- Force Arms and Legs to stay visible even when zoomed in
				part.LocalTransparencyModifier = 0
			end
		end
	end
end)

-- ==========================================
-- Mouse Unlock (Hold Alt)
-- ==========================================
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
-- Animation Loading
-- ==========================================
local idleAnim = Instance.new("Animation")
idleAnim.AnimationId = "rbxassetid://74783453136208"

local sprintAnim = Instance.new("Animation")
sprintAnim.AnimationId = "rbxassetid://124651765736727"

local idleTrack = animator:LoadAnimation(idleAnim)
local sprintTrack = animator:LoadAnimation(sprintAnim)

-- CRITICAL: Overrides default Roblox walk cycles
idleTrack.Priority = Enum.AnimationPriority.Idle
sprintTrack.Priority = Enum.AnimationPriority.Movement

idleTrack:Play()

-- ==========================================
-- Movement System Setup
-- ==========================================
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

local isDashing = false
local dashCooldown = 1
local lastDash = 0

local attachment = Instance.new("Attachment")
attachment.Parent = rootPart

local linearVelocity = Instance.new("LinearVelocity")
linearVelocity.Attachment0 = attachment
linearVelocity.MaxForce = 100000
linearVelocity.VectorVelocity = Vector3.zero
linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
linearVelocity.Enabled = false
linearVelocity.Parent = rootPart

local function getDashDirection()
	local moveVector = require(player.PlayerScripts.PlayerModule):GetControls():GetMoveVector()

	if moveVector.Magnitude > 0 then
		local lookVector = camera.CFrame.LookVector
		local rightVector = camera.CFrame.RightVector
		local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
		local flatRight = Vector3.new(rightVector.X, 0, rightVector.Z).Unit
		return ((flatLook * -moveVector.Z) + (flatRight * moveVector.X)).Unit
	else
		local lookVector = camera.CFrame.LookVector
		return Vector3.new(-lookVector.X, 0, -lookVector.Z).Unit
	end
end

local function performDash()
	local currentTime = os.clock()
	if isDashing or (currentTime - lastDash < dashCooldown) then return end

	isDashing = true
	lastDash = currentTime

	local dashDir = getDashDirection()
	dashEvent:FireServer(dashDir)

	linearVelocity.VectorVelocity = dashDir * 60
	linearVelocity.Enabled = true

	local originalFOV = camera.FieldOfView
	TweenService:Create(camera, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {FieldOfView = originalFOV + 10}):Play()

	task.delay(0.2, function()
		linearVelocity.Enabled = false
		linearVelocity.VectorVelocity = Vector3.zero
		isDashing = false
		TweenService:Create(camera, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {FieldOfView = 70}):Play()
	end)
end

-- ==========================================
-- Input Handling
-- ==========================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.Q then
		performDash()
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		sprintEvent:FireServer(true)
		TweenService:Create(camera, TweenInfo.new(0.3), {FieldOfView = 80}):Play()
		if sprintTrack.Length > 0 then sprintTrack:Play() end
	elseif input.KeyCode == Enum.KeyCode.LeftAlt then
		isMouseUnlocked = true
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprintEvent:FireServer(false)
		TweenService:Create(camera, TweenInfo.new(0.3), {FieldOfView = 70}):Play()
		if sprintTrack.Length > 0 then sprintTrack:Stop() end
	elseif input.KeyCode == Enum.KeyCode.LeftAlt then
		isMouseUnlocked = false
	end
end)