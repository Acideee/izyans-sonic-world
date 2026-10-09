-- Simple Motobug-style robots that patrol back and forth.
-- Jump on them, homing-attack them or boost into them to free the little bird inside!

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Badniks = {}

local RESPAWN_TIME = 30
local PATROL_SPEED = 12

local active = {} -- { model, a, b, t, dir }

local function makePart(props, parent)
	local p = Instance.new("Part")
	if props.Shape then
		p.Shape = props.Shape
	end
	for key, value in pairs(props) do
		if key ~= "Shape" then
			p[key] = value
		end
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = parent
	return p
end

-- Built around the origin facing -Z, then moved into place with PivotTo.
local function buildMotobug()
	local model = Instance.new("Model")
	model.Name = "Motobug"
	local body = makePart({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4.6, 4.6, 4.6),
		CFrame = CFrame.new(0, 3.2, 0),
		Color = Color3.fromRGB(220, 30, 35),
		Material = Enum.Material.SmoothPlastic,
	}, model)
	makePart({
		Name = "Stripe",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4.8, 3.2, 3.2),
		CFrame = CFrame.new(0, 3.2, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Color = Color3.fromRGB(30, 30, 35),
	}, model)
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.3, 1.3, 1.3),
			CFrame = CFrame.new(side * 0.8, 4, -2),
			Color = Color3.fromRGB(255, 255, 255),
		}, model)
		makePart({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.6, 0.6, 0.6),
			CFrame = CFrame.new(side * 0.8, 4, -2.55),
			Color = Color3.fromRGB(10, 10, 10),
		}, model)
		makePart({
			Size = Vector3.new(0.2, 2, 0.2),
			CFrame = CFrame.new(side * 0.7, 5.8, -0.8) * CFrame.Angles(math.rad(-25), 0, math.rad(-15 * side)),
			Color = Color3.fromRGB(60, 60, 60),
		}, model)
	end
	makePart({
		Name = "Wheel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 2.2, 2.2),
		CFrame = CFrame.new(0, 1.1, 0),
		Color = Color3.fromRGB(70, 70, 80),
		Material = Enum.Material.Metal,
	}, model)
	model.PrimaryPart = body
	body.PivotOffset = CFrame.new(0, -3.2, 0) -- pivot sits on the ground under the wheel
	model:SetAttribute("Alive", true)
	CollectionService:AddTag(model, "Badnik")
	return model
end

local function burst(position)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Position = position
	holder.Parent = workspace

	local fx = Instance.new("ParticleEmitter")
	fx.Color = ColorSequence.new(Color3.fromRGB(255, 180, 40), Color3.fromRGB(255, 80, 20))
	fx.LightEmission = 1
	fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	fx.Lifetime = NumberRange.new(0.3, 0.6)
	fx.Speed = NumberRange.new(15, 30)
	fx.SpreadAngle = Vector2.new(180, 180)
	fx.Rate = 0
	fx.Parent = holder
	fx:Emit(35)

	-- The little bird that was trapped inside flies away.
	local bird = Instance.new("Part")
	bird.Shape = Enum.PartType.Ball
	bird.Size = Vector3.new(1.2, 1.2, 1.2)
	bird.Color = Color3.fromRGB(80, 170, 255)
	bird.Material = Enum.Material.Neon
	bird.Anchored = true
	bird.CanCollide = false
	bird.CanQuery = false
	bird.Position = position
	bird.Parent = workspace
	TweenService:Create(bird, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Position = position + Vector3.new(math.random(-8, 8), 25, math.random(-8, 8)),
		Transparency = 1,
	}):Play()

	Debris:AddItem(holder, 1.5)
	Debris:AddItem(bird, 2.1)
end

function Badniks.start(routes, folder)
	for _, route in ipairs(routes) do
		local model = buildMotobug()
		model:PivotTo(CFrame.lookAt(route.a, route.b))
		model.Parent = folder
		table.insert(active, {
			model = model,
			folder = folder,
			a = route.a,
			b = route.b,
			length = math.max((route.b - route.a).Magnitude, 1),
			t = math.random(),
			dir = 1,
		})
	end

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, bot in ipairs(active) do
			if bot.model.Parent then
				bot.t += bot.dir * dt * PATROL_SPEED / bot.length
				if bot.t >= 1 then
					bot.t, bot.dir = 1, -1
				elseif bot.t <= 0 then
					bot.t, bot.dir = 0, 1
				end
				local pos = bot.a:Lerp(bot.b, bot.t) + Vector3.new(0, math.abs(math.sin(now * 8)) * 0.3, 0)
				local facing = bot.dir == 1 and (bot.b - bot.a) or (bot.a - bot.b)
				facing = Vector3.new(facing.X, 0, facing.Z)
				if facing.Magnitude > 0.01 then
					bot.model:PivotTo(CFrame.lookAt(pos, pos + facing))
				end
			end
		end
	end)
end

-- Returns true if this robot was alive and is now destroyed.
function Badniks.destroy(model)
	for _, bot in ipairs(active) do
		if bot.model == model and model.Parent and model:GetAttribute("Alive") then
			model:SetAttribute("Alive", false)
			burst(model:GetPivot().Position + Vector3.new(0, 3, 0))
			model.Parent = nil
			task.delay(RESPAWN_TIME, function()
				model:SetAttribute("Alive", true)
				model.Parent = bot.folder
			end)
			return true
		end
	end
	return false
end

function Badniks.isAlive(model)
	return typeof(model) == "Instance" and model:IsA("Model") and model.Parent ~= nil and model:GetAttribute("Alive") == true
end

return Badniks
