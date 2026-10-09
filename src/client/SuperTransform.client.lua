-- Izyan's Sonic World - the Super Sonic transformation.
--
-- 1. Power up: Sonic lifts off the ground, looks up and pushes his arms down
--    while the 7 Chaos Emeralds circle him faster and faster.
-- 2. BAM! The emeralds rush into him, the screen flashes, a golden shockwave
--    blasts out and the camera shakes. The server turns him into Super Sonic
--    (golden aura and all) at that exact moment.
-- 3. He hovers in his Super pose for a moment, then you get control back.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local SUPER = Config.Super
local GOLD = SUPER.Color

local playing = false

local function sound(id, volume, pitch)
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 5)
end

local function easeOut(t)
	return 1 - (1 - t) ^ 3
end

---------------------------------------------------------------------------
-- Power-up pose: head up, arms pushed down and out, chest slightly back.
-- Works on any R15 rig (the built-in Sonic or an imported model) by working
-- out each joint's rotation from the rig itself.
---------------------------------------------------------------------------

local function rotationBetween(a, b)
	a, b = a.Unit, b.Unit
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-4 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(a:Dot(b), -1, 1)))
end

local function motor(character, partName, motorName)
	local part = character:FindFirstChild(partName)
	local m = part and part:FindFirstChild(motorName)
	return (m and m:IsA("Motor6D")) and m or nil
end

-- Returns { [Motor6D] = target Transform } for this character.
local function buildPose(character)
	local pose = {}
	local function tiltBack(m, degrees)
		if m then
			-- Rotating about the body's sideways axis tips the look direction up.
			local axis = m.C0:VectorToObjectSpace(Vector3.xAxis)
			pose[m] = CFrame.fromAxisAngle(axis, math.rad(degrees))
		end
	end
	tiltBack(motor(character, "Head", "Neck"), 30)
	tiltBack(motor(character, "UpperTorso", "Waist"), 8)

	for _, side in ipairs({ "Right", "Left" }) do
		local sign = side == "Right" and 1 or -1
		local shoulder = motor(character, side .. "UpperArm", side .. "Shoulder")
		local elbow = motor(character, side .. "LowerArm", side .. "Elbow")
		if shoulder and elbow then
			-- Which way the arm points at rest (T-pose or arms-down rigs alike),
			-- and where we want it: down by his sides, a little out and forward.
			local restDir = shoulder.C1:VectorToObjectSpace(elbow.C0.Position - shoulder.C1.Position)
			local wantDir = shoulder.C0:VectorToObjectSpace(Vector3.new(0.42 * sign, -0.9, -0.12))
			pose[shoulder] = rotationBetween(restDir, wantDir)
			pose[elbow] = CFrame.identity
		end
	end
	return pose
end

---------------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------------

local function makeEmeralds(folder)
	local gems = {}
	for i, info in ipairs(Config.Emeralds) do
		local gem = Instance.new("Part")
		gem.Name = "Emerald_" .. info.Name
		gem.Size = Vector3.new(1.1, 1.1, 1.1)
		gem.Color = info.Color
		gem.Material = Enum.Material.Neon
		gem.Anchored = true
		gem.CanCollide = false
		gem.CanQuery = false
		gem.CanTouch = false
		gem.CastShadow = false
		local light = Instance.new("PointLight")
		light.Color = info.Color
		light.Range = 8
		light.Brightness = 2
		light.Parent = gem
		gem.Parent = folder
		gems[i] = gem
	end
	return gems
end

local function shockwave(position)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.6, 2, 2)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Color = GOLD
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.2
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, 70, 70),
		Transparency = 1,
	}):Play()

	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(2, 2, 2)
	ball.Position = position
	ball.Color = Color3.fromRGB(255, 240, 170)
	ball.Material = Enum.Material.Neon
	ball.Transparency = 0.1
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CastShadow = false
	ball.Parent = workspace
	TweenService:Create(ball, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(22, 22, 22),
		Transparency = 1,
	}):Play()

	Debris:AddItem(ring, 1)
	Debris:AddItem(ball, 1)
end

local function flash()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SuperFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0
	frame.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	local t = TweenService:Create(frame, TweenInfo.new(0.6), { BackgroundTransparency = 1, BackgroundColor3 = GOLD })
	t:Play()
	Debris:AddItem(gui, 1)
end

---------------------------------------------------------------------------
-- The sequence
---------------------------------------------------------------------------

local function play(powerUpTime)
	if playing then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	playing = true
	player:SetAttribute("Cutscene", true) -- the movement script pauses while this is set

	local startCF = CFrame.new(root.Position) * (root.CFrame - root.Position)
	local peakCF = startCF + Vector3.new(0, SUPER.LiftHeight, 0)
	local hoverTime = SUPER.HoverTime
	local total = powerUpTime + hoverTime
	local folder = Instance.new("Folder")
	folder.Name = "SuperTransformFX"
	folder.Parent = workspace
	local gems = makeEmeralds(folder)
	local look = root.CFrame.LookVector
	local camStart = math.atan2(look.Z, look.X) -- start the camera in front of him
	local originalFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable

	local poses = {} -- [character] = pose table
	local paused = {} -- Animate scripts we switched off
	local banged = false
	local nextPing = 0
	local t0 = os.clock()

	local function holdCharacter(char)
		if poses[char] then
			return poses[char]
		end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = true
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					track:Stop(0.1)
				end
			end
		end
		local animate = char:FindFirstChild("Animate")
		if animate and not animate.Disabled then
			animate.Disabled = true
			paused[animate] = true
		end
		poses[char] = buildPose(char)
		return poses[char]
	end

	local connection
	local function finish(char)
		connection:Disconnect()
		folder:Destroy()
		for posedChar, pose in pairs(poses) do
			for m in pairs(pose) do
				if m.Parent then
					m.Transform = CFrame.identity
				end
			end
			if posedChar ~= char then
				poses[posedChar] = nil
			end
		end
		for animate in pairs(paused) do
			if animate.Parent then
				animate.Disabled = false
			end
		end
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = originalFov
		player:SetAttribute("Cutscene", false)
		playing = false
	end

	connection = RunService.Stepped:Connect(function()
		local t = os.clock() - t0
		local char = player.Character
		local r = char and char:FindFirstChild("HumanoidRootPart")
		if not r then
			if t > total + 2 then
				finish(char) -- he vanished (e.g. respawned): don't stay stuck
			end
			return
		end
		local pose = holdCharacter(char)

		-- Lift off and hover with a little bob; shake builds up while charging.
		local charge = math.clamp(t / powerUpTime, 0, 1)
		local cf = startCF:Lerp(peakCF, easeOut(charge))
		if banged then
			cf = peakCF + Vector3.new(0, math.sin((t - powerUpTime) * 4) * 0.25, 0)
		else
			local shake = 0.08 * charge
			cf = cf + Vector3.new(math.random() * shake - shake / 2, 0, math.random() * shake - shake / 2)
		end
		r.CFrame = cf
		r.AssemblyLinearVelocity = Vector3.zero
		r.AssemblyAngularVelocity = Vector3.zero

		-- Ease into the power-up pose.
		local blend = easeOut(math.clamp(t / 0.6, 0, 1))
		for m, target in pairs(pose) do
			if m.Parent then
				m.Transform = CFrame.identity:Lerp(target, blend)
			end
		end

		-- Chaos Emeralds circle him, speeding up, then rush in at the BAM.
		local center = cf.Position + Vector3.new(0, 0.5, 0)
		if not banged then
			local spin = t * (2 + 9 * charge * charge)
			local radius = 6 - 3.5 * charge ^ 4
			for i, gem in ipairs(gems) do
				local a = spin + (i / #gems) * math.pi * 2
				local height = math.sin(a * 2 + t * 3) * 0.6
				gem.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * radius, height, math.sin(a) * radius))
					* CFrame.Angles(t * 3, t * 4, math.rad(45))
				gem.Transparency = math.clamp(1 - t * 3, 0, 1)
			end
			-- Rising "charging" pings.
			if t >= nextPing then
				sound(Config.Sounds.PowerUp, 0.35, 0.8 + 1.2 * charge)
				nextPing = t + 0.22 - 0.16 * charge
			end
		end

		-- BAM!
		if not banged and t >= powerUpTime then
			banged = true
			for _, gem in ipairs(gems) do
				gem:Destroy()
			end
			flash()
			shockwave(center)
			sound(Config.Sounds.SuperBam, 1, 0.6)
			sound(Config.Sounds.Emerald, 0.6, 1.2)
			camera.FieldOfView = originalFov + 14
			TweenService:Create(camera, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { FieldOfView = originalFov }):Play()
		end

		-- Camera: low and close, circling slowly and looking up at him.
		local ca = camStart + t * 0.5
		local dist = 13 - 3 * charge
		local camPos = center + Vector3.new(math.cos(ca) * dist, -1.5, math.sin(ca) * dist)
		local camCF = CFrame.lookAt(camPos, center + Vector3.new(0, 1, 0))
		local since = t - powerUpTime
		if banged and since < 0.6 then
			local k = (0.6 - since) * 1.2
			camCF = camCF * CFrame.new(math.random() * k - k / 2, math.random() * k - k / 2, 0)
		end
		camera.CFrame = camCF

		-- Done: hand control back.
		if t >= total then
			finish(char)
		end
	end)
end

Remotes.Notify.OnClientEvent:Connect(function(kind, a)
	if kind == "PowerUp" then
		play(a or SUPER.PowerUpTime)
	end
end)
