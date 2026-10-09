-- Izyan's Sonic World - fast Sonic movement and pickups (runs on each player's device).
--
-- Controls
--   Move ............ WASD / thumbstick (you speed up the longer you run)
--   Jump ............ Space / A / jump button (you curl into a ball)
--   Jump in the air . homing attack the nearest robot, or air dash forward
--   Boost ........... Shift / X / BOOST button
--   Super Sonic ..... E / Y / SUPER button (needs 7 emeralds + 50 rings)
--   Super flight .... as Super Sonic, hold jump in the air to fly up

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Map = workspace:WaitForChild("Map")
local RingFolder = Map:WaitForChild("Rings")
local EmeraldFolder = Map:WaitForChild("Emeralds")
local BadnikFolder = Map:WaitForChild("Badniks")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local MOVE = Config.Movement
local SUPER = Config.Super
local BLUE = Color3.fromRGB(25, 75, 230)

local character, humanoid, root
local speed = MOVE.StartSpeed
local lastMoveDir = Vector3.zero
local boostTime, boostCooldown = 0, 0
local forcedDir, forcedTime = nil, 0
local airborne, airActionUsed = false, false
local takeoffTime, lastJumpRequest = 0, 0
local motion = nil -- scripted movement: { t, dur, velocity = function(t) -> Vector3, attack = bool }
local loopRide = nil
local hurtUntil = 0
local lastPos = nil
local springCooldown = {}
local recentlyHit = {}
local pendingRings = {}
local pendingEmeralds = {}
local ball, trail

---------------------------------------------------------------------------
-- Little helpers
---------------------------------------------------------------------------

local function isSuper()
	return player:GetAttribute("IsSuper") == true
end

local function playSound(id, volume, pitch)
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(6, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Distance from point p to the line segment a-b. Used so that you never
-- "skip over" a ring when running super fast.
local function segmentDistance(a, b, p)
	local ab = b - a
	local lenSq = ab:Dot(ab)
	if lenSq < 1e-6 then
		return (p - a).Magnitude
	end
	local t = math.clamp((p - a):Dot(ab) / lenSq, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

local function params()
	if isSuper() then
		return SUPER.StartSpeed, SUPER.MaxSpeed, SUPER.Acceleration, SUPER.JumpPower, SUPER.BoostSpeed
	end
	return MOVE.StartSpeed, MOVE.MaxSpeed, MOVE.Acceleration, MOVE.JumpPower, MOVE.BoostSpeed
end

local function isAttacking()
	return isSuper() or airborne or boostTime > 0 or (motion ~= nil and motion.attack)
end

---------------------------------------------------------------------------
-- Spin ball + speed trail
---------------------------------------------------------------------------

local function setBodyHidden(hidden)
	if not character then
		return
	end
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") and item ~= ball and not (ball and item:IsDescendantOf(ball)) then
			item.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

local function setBall(on)
	if on and not ball and root then
		local color = isSuper() and SUPER.Color or BLUE
		ball = Instance.new("Part")
		ball.Name = "SpinBall"
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(5, 5, 5)
		ball.Color = color
		ball.Material = isSuper() and Enum.Material.Neon or Enum.Material.SmoothPlastic
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		ball.Massless = true
		ball.CFrame = root.CFrame
		for i = 0, 1 do
			local band = Instance.new("Part")
			band.Shape = Enum.PartType.Cylinder
			band.Size = Vector3.new(0.6, 5.25, 5.25)
			band.Color = color:Lerp(Color3.new(1, 1, 1), 0.35)
			band.Material = ball.Material
			band.CanCollide = false
			band.CanQuery = false
			band.CanTouch = false
			band.Massless = true
			band.CFrame = ball.CFrame * CFrame.Angles(0, math.pi / 2 + i * 0.9, 0)
			local w = Instance.new("WeldConstraint")
			w.Part0 = ball
			w.Part1 = band
			w.Parent = band
			band.Parent = ball
		end
		local weld = Instance.new("Weld")
		weld.Name = "BallWeld"
		weld.Part0 = root
		weld.Part1 = ball
		weld.C0 = CFrame.new(0, -0.5, 0)
		weld.Parent = ball
		ball.Parent = character
	elseif not on and ball then
		ball:Destroy()
		ball = nil
		setBodyHidden(false)
	end
end

local function makeTrail()
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.2, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.6, 0)
	a1.Parent = root
	trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.Enabled = false
	trail.Parent = root
end

---------------------------------------------------------------------------
-- Scripted motions (springs, dashes, homing attack)
---------------------------------------------------------------------------

local function startMotion(dur, velocityFn, attack)
	if not root then
		return
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	motion = { t = 0, dur = dur, velocity = velocityFn, attack = attack }
end

-- Launch on an arc that peaks a little above `target` and lands right on it.
local function launchTo(target)
	local g = workspace.Gravity
	local from = root.Position
	local dy = target.Y - from.Y
	local apex = math.max(dy, 0) + 12
	local up = math.sqrt(2 * apex / g)
	local down = math.sqrt(2 * (apex - dy) / g)
	local total = up + down
	local horizontal = flat(target - from) / total
	local vy = g * up
	airborne = true
	airActionUsed = false
	takeoffTime = os.clock()
	setBall(true)
	startMotion(total, function(t)
		return horizontal + Vector3.new(0, vy - g * t, 0)
	end, true)
end

local function launchUp(power)
	local g = workspace.Gravity
	local carry = flat(root.AssemblyLinearVelocity)
	airborne = true
	airActionUsed = false
	takeoffTime = os.clock()
	setBall(true)
	startMotion(power / g, function(t)
		return carry + Vector3.new(0, power - g * t, 0)
	end, true)
end

local function findHomingTarget()
	local best, bestDist = nil, MOVE.HomingRange
	local facing = flat(root.CFrame.LookVector)
	for _, model in ipairs(BadnikFolder:GetChildren()) do
		local body = model.PrimaryPart
		if body and model:GetAttribute("Alive") then
			local offset = body.Position - root.Position
			local d = offset.Magnitude
			local f = flat(offset)
			local inFront = f.Magnitude < 4 or facing.Magnitude < 0.01 or f.Unit:Dot(facing.Unit) > 0.2
			if d < bestDist and offset.Y < 12 and inFront then
				best, bestDist = body, d
			end
		end
	end
	return best
end

local function airAction()
	local target = findHomingTarget()
	playSound(Config.Sounds.Boost, 0.6, 1.3)
	if target then
		startMotion(0.8, function()
			if not target:IsDescendantOf(workspace) then
				return Vector3.new(0, -20, 0)
			end
			return (target.Position - root.Position).Unit * MOVE.HomingSpeed
		end, true)
	else
		local dir = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.MoveDirection or flat(root.CFrame.LookVector).Unit
		local dashSpeed = isSuper() and MOVE.AirDashSpeed * 1.5 or MOVE.AirDashSpeed
		startMotion(0.3, function()
			return dir * dashSpeed + Vector3.new(0, 8, 0)
		end, true)
	end
end

---------------------------------------------------------------------------
-- Loop-de-loop ride
---------------------------------------------------------------------------

local function loopPose(ride)
	local cf, r = ride.cf, ride.radius
	local look, up, right = cf.LookVector, cf.UpVector, cf.RightVector
	local center = cf.Position + up * r
	local theta = ride.theta
	local radial = look * math.sin(theta) - up * math.cos(theta)
	local pos = center + radial * (r - 3) + right * ride.shift * (theta / (math.pi * 2))
	local forward = look * math.cos(theta) + up * math.sin(theta)
	return CFrame.lookAt(pos, pos + forward, -radial), forward
end

local function startLoop(model, entrySpeed)
	loopRide = {
		cf = model:GetAttribute("LoopCFrame"),
		radius = model:GetAttribute("Radius"),
		shift = model:GetAttribute("Shift"),
		theta = 0,
		speed = math.max(entrySpeed, 75),
	}
	motion = nil
	humanoid.PlatformStand = true
	playSound(Config.Sounds.Boost, 0.7, 0.9)
end

local function updateLoop(dt)
	loopRide.theta += loopRide.speed * dt / loopRide.radius
	if loopRide.theta >= math.pi * 2 then
		loopRide.theta = math.pi * 2
		local cf, forward = loopPose(loopRide)
		root.CFrame = CFrame.lookAt(cf.Position, cf.Position + forward)
		root.AssemblyLinearVelocity = forward * loopRide.speed
		speed = math.max(speed, loopRide.speed)
		humanoid.PlatformStand = false
		boostTime = 0.6
		loopRide = nil
		return
	end
	local cf, forward = loopPose(loopRide)
	root.CFrame = cf
	root.AssemblyLinearVelocity = forward * loopRide.speed
end

---------------------------------------------------------------------------
-- Pickups and gimmicks
---------------------------------------------------------------------------

local ringPitch, lastRingTime = 1, 0

local function collectedEmeralds()
	local set = {}
	for name in string.gmatch(player:GetAttribute("Emeralds") or "", "[^,]+") do
		set[name] = true
	end
	return set
end

local function checkRings(from, to)
	local radius = isSuper() and Config.Rings.SuperMagnetRadius or Config.Rings.CollectRadius
	local now = os.clock()
	for _, ring in ipairs(RingFolder:GetChildren()) do
		if ring.Transparency < 1 and ring:GetAttribute("Active") and (pendingRings[ring] or 0) < now then
			if segmentDistance(from, to, ring.Position) < radius then
				pendingRings[ring] = now + 1
				ring.Transparency = 1
				local inner = ring:FindFirstChild("Inner")
				if inner then
					inner.Transparency = 1
				end
				Remotes.CollectRing:FireServer(ring:GetAttribute("RingId"))
				-- Quick ring streaks sound higher, like the real games.
				ringPitch = (now - lastRingTime < 0.4) and math.min(ringPitch + 0.04, 1.5) or 1
				lastRingTime = now
				playSound(Config.Sounds.Ring, 0.35, ringPitch)
			end
		end
	end
end

local function checkEmeralds(from, to)
	local have = collectedEmeralds()
	local now = os.clock()
	for _, model in ipairs(EmeraldFolder:GetChildren()) do
		local name = model:GetAttribute("EmeraldName")
		if name and not have[name] and (pendingEmeralds[name] or 0) < now then
			if segmentDistance(from, to, model:GetAttribute("BasePosition")) < 7 then
				pendingEmeralds[name] = now + 2
				Remotes.CollectEmerald:FireServer(name)
			end
		end
	end
end

local function checkSprings()
	local now = os.clock()
	for _, pad in ipairs(CollectionService:GetTagged("Spring")) do
		local offset = root.Position - pad.Position
		if flat(offset).Magnitude < 4 and offset.Y > -1 and offset.Y < 6.5 and (springCooldown[pad] or 0) < now then
			springCooldown[pad] = now + 0.6
			playSound(Config.Sounds.Spring, 0.8, 1.6)
			local target = pad:GetAttribute("Target")
			if target then
				launchTo(target + Vector3.new(0, 3.5, 0))
			else
				launchUp(pad:GetAttribute("Power") or 120)
			end
			-- Squash-and-stretch on the spring pad.
			local home = pad.CFrame
			pad.CFrame = home * CFrame.new(-1.2, 0, 0)
			TweenService:Create(pad, TweenInfo.new(0.35, Enum.EasingStyle.Elastic), { CFrame = home }):Play()
			return
		end
	end
end

local function checkDashPads()
	local now = os.clock()
	for _, pad in ipairs(CollectionService:GetTagged("DashPad")) do
		local offset = pad.CFrame:PointToObjectSpace(root.Position)
		if math.abs(offset.X) < 5.5 and math.abs(offset.Z) < 6.5 and offset.Y > -1 and offset.Y < 6 and (springCooldown[pad] or 0) < now then
			springCooldown[pad] = now + 0.5
			local _, maxSpeed = params()
			forcedDir = flat(pad.CFrame.LookVector).Unit
			forcedTime = 0.5
			boostTime = math.max(boostTime, 1)
			speed = maxSpeed
			root.CFrame = CFrame.lookAt(root.Position, root.Position + forcedDir)
			playSound(Config.Sounds.Boost, 0.7, 1.1)
			return
		end
	end
end

local function checkLoops()
	local velocity = root.AssemblyLinearVelocity
	for _, model in ipairs(CollectionService:GetTagged("Loop")) do
		local cf = model:GetAttribute("LoopCFrame")
		if cf then
			local entry = cf.Position + cf.UpVector * 3
			if (root.Position - entry).Magnitude < 9 and velocity:Dot(cf.LookVector) > 25 then
				startLoop(model, flat(velocity).Magnitude)
				return
			end
		end
	end
end

local function checkBadniks()
	local now = os.clock()
	for _, model in ipairs(BadnikFolder:GetChildren()) do
		local body = model.PrimaryPart
		if body and model:GetAttribute("Alive") and (recentlyHit[model] or 0) < now then
			if (body.Position - root.Position).Magnitude < 5.5 then
				recentlyHit[model] = now + 1
				if isAttacking() then
					Remotes.BadnikHit:FireServer(model)
					playSound(Config.Sounds.Badnik, 0.8, 0.5)
					-- Bounce off, and allow another homing attack to chain robots.
					airActionUsed = false
					local carry = flat(root.AssemblyLinearVelocity) * 0.3
					airborne = true
					takeoffTime = now
					setBall(true)
					startMotion(0.25, function(t)
						return carry + Vector3.new(0, 70 - workspace.Gravity * t, 0)
					end, true)
				elseif now > hurtUntil then
					hurtUntil = now + 2
					Remotes.PlayerHurt:FireServer(model)
					playSound(Config.Sounds.Hurt, 0.7)
					local away = flat(root.Position - body.Position)
					away = away.Magnitude > 0.1 and away.Unit or -root.CFrame.LookVector
					speed = MOVE.StartSpeed
					startMotion(0.3, function()
						return away * 45 + Vector3.new(0, 35, 0)
					end, false)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Visual animation: spinning rings, floating emeralds, compass arrow
---------------------------------------------------------------------------

local arrow = Instance.new("Model")
arrow.Name = "EmeraldCompass"
local arrowParts = {}
do
	local function bar(size, cf)
		local p = Instance.new("Part")
		p.Size = size
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Parent = arrow
		table.insert(arrowParts, { part = p, offset = cf })
	end
	bar(Vector3.new(0.5, 0.3, 2.6), CFrame.new(0, 0, 0.4))
	for _, side in ipairs({ -1, 1 }) do
		local angle = math.rad(40) * side
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local tip = Vector3.new(0, 0, -1.2)
		bar(Vector3.new(0.5, 0.3, 2), CFrame.new(tip + dir * 1) * CFrame.Angles(0, angle, 0))
	end
	arrow.Parent = camera
end

local function nearestEmerald()
	local have = collectedEmeralds()
	local best, bestDist = nil, math.huge
	for _, model in ipairs(EmeraldFolder:GetChildren()) do
		local name = model:GetAttribute("EmeraldName")
		if name and not have[name] then
			local d = (model:GetAttribute("BasePosition") - root.Position).Magnitude
			if d < bestDist then
				best, bestDist = model, d
			end
		end
	end
	return best, bestDist
end

local TILT = CFrame.Angles(math.rad(45), 0, math.rad(45))

local function animateWorld(now)
	-- Spin every ring with one fast bulk move.
	local parts, cframes = {}, {}
	local spin = CFrame.Angles(0, now * 3, 0)
	for _, ring in ipairs(RingFolder:GetChildren()) do
		local cf = CFrame.new(ring.Position) * spin
		table.insert(parts, ring)
		table.insert(cframes, cf)
		local inner = ring:FindFirstChild("Inner")
		if inner then
			table.insert(parts, inner)
			table.insert(cframes, cf)
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	-- Float and spin the emeralds you still need; hide the ones you have.
	local have = collectedEmeralds()
	for _, model in ipairs(EmeraldFolder:GetChildren()) do
		local got = have[model:GetAttribute("EmeraldName")] == true
		local base = model:GetAttribute("BasePosition")
		for _, item in ipairs(model:GetDescendants()) do
			if item:IsA("BasePart") then
				item.LocalTransparencyModifier = got and 1 or 0
			elseif item:IsA("ParticleEmitter") or item:IsA("PointLight") then
				item.Enabled = not got
			end
		end
		if not got and base then
			local cf = CFrame.new(base + Vector3.new(0, math.sin(now * 2) * 0.6, 0)) * CFrame.Angles(0, now * 1.5, 0) * TILT
			local gem, core = model:FindFirstChild("Gem"), model:FindFirstChild("Core")
			if gem then
				gem.CFrame = cf
			end
			if core then
				core.CFrame = cf
			end
		end
	end

	-- Compass arrow above your head pointing to the nearest emerald.
	local target = nearestEmerald()
	if target and root then
		local color = target.Gem.Color
		local from = root.Position + Vector3.new(0, 5.5, 0)
		local to = target:GetAttribute("BasePosition")
		local dir = flat(to - from)
		if dir.Magnitude > 1 then
			local pivot = CFrame.lookAt(from, from + dir) * CFrame.new(0, math.sin(now * 4) * 0.2, -1.5)
			for _, info in ipairs(arrowParts) do
				info.part.CFrame = pivot * info.offset
				info.part.Color = color
				info.part.Transparency = 0.1
			end
		end
	else
		for _, info in ipairs(arrowParts) do
			info.part.Transparency = 1
		end
	end
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------

local function onBoost(_, inputState)
	if inputState ~= Enum.UserInputState.Begin or not humanoid or loopRide then
		return Enum.ContextActionResult.Pass
	end
	if boostCooldown <= 0 then
		local _, maxSpeed = params()
		boostTime = MOVE.BoostTime
		boostCooldown = MOVE.BoostCooldown
		speed = maxSpeed
		playSound(Config.Sounds.Boost, 0.8, 1)
		camera.FieldOfView += 8
	end
	return Enum.ContextActionResult.Sink
end

local function onSuper(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		Remotes.GoSuper:FireServer()
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("SonicBoost", onBoost, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonX)
ContextActionService:SetTitle("SonicBoost", "BOOST")
ContextActionService:SetPosition("SonicBoost", UDim2.new(1, -170, 1, -160))
ContextActionService:BindAction("SonicSuper", onSuper, true, Enum.KeyCode.E, Enum.KeyCode.ButtonY)
ContextActionService:SetTitle("SonicSuper", "SUPER")
ContextActionService:SetPosition("SonicSuper", UDim2.new(1, -95, 1, -230))

UserInputService.JumpRequest:Connect(function()
	local now = os.clock()
	local freshPress = now - lastJumpRequest > 0.15 -- ignore auto-repeat while held
	lastJumpRequest = now
	if not freshPress or not airborne or airActionUsed or loopRide or not root then
		return
	end
	if now - takeoffTime < 0.2 then
		return
	end
	airActionUsed = true
	airAction()
end)

---------------------------------------------------------------------------
-- Character setup
---------------------------------------------------------------------------

local function onCharacter(newCharacter)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	root = newCharacter:WaitForChild("HumanoidRootPart")
	speed = MOVE.StartSpeed
	motion, loopRide, ball = nil, nil, nil
	airborne, airActionUsed = false, false
	boostTime, boostCooldown = 0, 0
	lastPos = root.Position
	humanoid.UseJumpPower = true
	makeTrail()

	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			airborne = true
			airActionUsed = false
			takeoffTime = os.clock()
			setBall(true)
			playSound(Config.Sounds.Jump, 0.4, 1.2)
		elseif new == Enum.HumanoidStateType.Freefall then
			if not airborne then
				airborne = true
				takeoffTime = os.clock()
			end
		end
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- Turning Super off/on changes the ball colour next jump.
player:GetAttributeChangedSignal("IsSuper"):Connect(function()
	if ball then
		setBall(false)
		setBall(true)
	end
end)

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	if root then
		animateWorld(now)
	end
	if not (humanoid and root and humanoid.Health > 0) then
		return
	end

	local from = lastPos or root.Position

	if loopRide then
		updateLoop(dt)
	else
		local startSpeed, maxSpeed, accel, jumpPower, boostSpeed = params()
		humanoid.JumpPower = jumpPower

		-- Momentum: the longer you run, the faster you go.
		local moveDir = humanoid.MoveDirection
		if moveDir.Magnitude > 0.1 then
			if lastMoveDir.Magnitude > 0.1 and lastMoveDir:Dot(moveDir) < -0.2 then
				speed *= MOVE.TurnPenalty
			end
			speed = math.clamp(speed + accel * dt, startSpeed, maxSpeed)
			lastMoveDir = moveDir
		else
			speed = math.max(startSpeed, speed - MOVE.Deceleration * dt)
		end

		boostCooldown = math.max(0, boostCooldown - dt)
		forcedTime = math.max(0, forcedTime - dt)
		if forcedTime <= 0 then
			forcedDir = nil
		end
		humanoid.AutoRotate = forcedDir == nil

		if boostTime > 0 then
			boostTime -= dt
			humanoid.WalkSpeed = boostSpeed
			if not motion and not airborne then
				local dir = forcedDir
					or (moveDir.Magnitude > 0.1 and moveDir)
					or flat(root.CFrame.LookVector).Unit
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = dir * boostSpeed + Vector3.new(0, v.Y, 0)
			end
		else
			humanoid.WalkSpeed = speed
		end

		if motion then
			motion.t += dt
			if motion.t >= motion.dur then
				motion = nil
			else
				root.AssemblyLinearVelocity = motion.velocity(motion.t)
			end
		end

		-- Super Sonic can fly: hold jump while in the air.
		if isSuper() and airborne and not motion and humanoid.Jump and now - takeoffTime > 0.3 then
			local v = root.AssemblyLinearVelocity
			if root.Position.Y < 450 then
				root.AssemblyLinearVelocity = Vector3.new(v.X, SUPER.FlySpeed, v.Z)
			end
		end

		-- Back on the ground (or swimming): uncurl and reset air moves.
		if airborne and not motion and now - takeoffTime > 0.15 then
			local state = humanoid:GetState()
			if humanoid.FloorMaterial ~= Enum.Material.Air or state == Enum.HumanoidStateType.Swimming then
				airborne = false
				airActionUsed = false
				setBall(false)
			end
		end

		checkSprings()
		checkDashPads()
		if not motion then
			checkLoops()
		end
	end

	checkRings(from, root.Position)
	checkEmeralds(from, root.Position)
	checkBadniks()
	lastPos = root.Position

	-- Spin ball animation.
	if ball then
		setBodyHidden(true)
		local weld = ball:FindFirstChild("BallWeld")
		if weld then
			weld.C0 = CFrame.new(0, -0.5, 0) * CFrame.Angles(-now * 25, 0, 0)
		end
	end

	-- Camera widens and trail appears as you go faster.
	local horizontalSpeed = flat(root.AssemblyLinearVelocity).Magnitude
	local fast = math.clamp((horizontalSpeed - 30) / 100, 0, 1)
	local targetFov = 70 + fast * 28 + (isSuper() and 4 or 0)
	camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(1, dt * 5)
	if trail then
		local color = isSuper() and SUPER.Color or Color3.fromRGB(80, 160, 255)
		trail.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		trail.Enabled = horizontalSpeed > 55 or isSuper() or loopRide ~= nil
	end
end)
