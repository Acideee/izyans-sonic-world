-- Builds the whole open world from code when the server starts:
-- terrain, lighting, scenery, rings, Chaos Emeralds, springs, dash pads and the loop.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local World = {}
World.rings = {} -- [ringId] = ring part
World.badnikRoutes = {} -- { {a = Vector3, b = Vector3}, ... }
World.spawnPosition = Vector3.new(0, 1, 0)

local terrain = workspace.Terrain
local M = Enum.Material
local rng = Random.new(2024)
local folders: { [string]: Folder } = {}

local COLORS = {
	grassLight = Color3.fromRGB(125, 220, 75),
	grassDark = Color3.fromRGB(80, 180, 50),
	checkerA = Color3.fromRGB(240, 150, 40),
	checkerB = Color3.fromRGB(130, 72, 30),
	blue = Color3.fromRGB(30, 90, 235),
	gold = Color3.fromRGB(255, 196, 30),
	darkGold = Color3.fromRGB(205, 130, 10),
	wood = Color3.fromRGB(150, 100, 55),
	white = Color3.fromRGB(245, 245, 245),
	red = Color3.fromRGB(225, 40, 45),
	road = Color3.fromRGB(60, 62, 72),
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function part(props, parent)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	if props.Size then
		p.Size = props.Size
	end
	for key, value in pairs(props) do
		if key ~= "ClassName" and key ~= "Shape" and key ~= "Size" then
			p[key] = value
		end
	end
	p.Parent = parent
	return p
end

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { terrain }

-- Height of the ground (or water surface) at x, z.
local function groundY(x, z)
	local hit = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), terrainOnly)
	return hit and hit.Position.Y or 0
end

local function onGround(x, z, lift)
	return Vector3.new(x, groundY(x, z) + (lift or 0), z)
end

local function safeLookAt(from, to)
	local dir = to - from
	local up = math.abs(dir.Unit.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis
	return CFrame.lookAt(from, to, up)
end

-- A cylinder stretched between two points.
local function cylinderBetween(a, b, diameter, props, parent)
	local len = (b - a).Magnitude
	if len < 0.05 then
		return nil
	end
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(len, diameter, diameter)
	props.CFrame = safeLookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
	return part(props, parent)
end

-- A flat slab stretched between two points (used for palm leaves).
local function slabBetween(a, b, width, thickness, props, parent)
	local len = (b - a).Magnitude
	props.Size = Vector3.new(width, thickness, len)
	props.CFrame = safeLookAt((a + b) / 2, b)
	return part(props, parent)
end

local function verticalCylinderCFrame(position)
	return CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
end

-- Zones that random scenery should stay out of.
local keepClear = {}
local function clearCircle(x, z, r)
	table.insert(keepClear, { kind = "circle", x = x, z = z, r = r })
end
local function clearRect(x1, z1, x2, z2)
	table.insert(keepClear, { kind = "rect", x1 = x1, z1 = z1, x2 = x2, z2 = z2 })
end
local function isClear(x, z)
	for _, zone in ipairs(keepClear) do
		if zone.kind == "circle" then
			if (x - zone.x) ^ 2 + (z - zone.z) ^ 2 < zone.r ^ 2 then
				return false
			end
		elseif x > zone.x1 and x < zone.x2 and z > zone.z1 and z < zone.z2 then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Lighting: bright, saturated, sunny "Green Hill" look
---------------------------------------------------------------------------

local function setupLighting()
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("Clouds") then
			child:Destroy()
		end
	end

	Lighting.ClockTime = 14.5
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 3
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2
	Lighting.Ambient = Color3.fromRGB(95, 105, 135)
	Lighting.OutdoorAmbient = Color3.fromRGB(145, 155, 180)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.27
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(200, 228, 255)
	atmosphere.Decay = Color3.fromRGB(110, 160, 225)
	atmosphere.Glare = 0.35
	atmosphere.Haze = 1.1
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.StarCount = 0
	sky.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.5
	bloom.Parent = Lighting

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Intensity = 0.07
	sunRays.Spread = 0.7
	sunRays.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Saturation = 0.25
	color.Contrast = 0.08
	color.Brightness = 0.02
	color.Parent = Lighting

	terrain.WaterColor = Color3.fromRGB(25, 145, 205)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.5
	terrain.WaterWaveSize = 0.15
	terrain.WaterWaveSpeed = 12
	terrain:SetMaterialColor(M.Grass, Color3.fromRGB(80, 195, 60))
	terrain:SetMaterialColor(M.Sand, Color3.fromRGB(240, 215, 140))
	terrain:SetMaterialColor(M.Rock, Color3.fromRGB(170, 115, 70))
	terrain:SetMaterialColor(M.Sandstone, Color3.fromRGB(215, 140, 80))
	terrain:SetMaterialColor(M.Ground, Color3.fromRGB(135, 85, 45))
end

---------------------------------------------------------------------------
-- Terrain
---------------------------------------------------------------------------

local LAKE = Vector3.new(380, 0, 60)
local MOUNTAIN = Vector3.new(-420, 0, -320)
local CANYON = Vector3.new(-420, 0, 380)
local SKY = Vector3.new(330, 0, -470)
local TOWER = Vector3.new(-160, 0, 180)
local ISLET = Vector3.new(0, 0, 960)
local LOOP_START = Vector3.new(0, 0, -200)

local HILLS = {
	{ -180, -60, 60 },
	{ 180, -120, 50 },
	{ -250, 120, 70 },
	{ 120, 220, 55 },
	{ -80, -420, 65 },
	{ 560, -200, 70 },
	{ -650, 0, 80 },
	{ 650, 280, 65 },
	{ 200, -650, 60 },
	{ -640, -660, 70 },
	{ 620, -640, 60 },
	{ -700, 230, 55 },
	{ 300, 640, 50 },
	{ -300, 600, 45 },
}

local function buildTerrain()
	terrain:Clear()

	-- Ocean all around the island.
	terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(2400, 12, 2400), M.Water)
	terrain:FillBlock(CFrame.new(0, -18, 0), Vector3.new(2400, 8, 2400), M.Sand)

	-- The island: a sandy shore and a big grassy field on top.
	terrain:FillBlock(CFrame.new(0, -12, 0), Vector3.new(1700, 22, 1700), M.Sand)
	terrain:FillBlock(CFrame.new(0, -12, 0), Vector3.new(1600, 24, 1600), M.Grass)

	-- Beach on the south side.
	terrain:FillBlock(CFrame.new(0, -12, 720), Vector3.new(1600, 24, 160), M.Sand)

	-- Rolling green hills.
	for _, hill in ipairs(HILLS) do
		local r = hill[3]
		terrain:FillBall(Vector3.new(hill[1], -r * 0.55, hill[2]), r, M.Grass)
	end

	-- Big brown mountain with a grassy top (Red emerald on the peak).
	terrain:FillBall(Vector3.new(MOUNTAIN.X, -70, MOUNTAIN.Z), 180, M.Rock)
	terrain:FillBall(Vector3.new(MOUNTAIN.X, 80, MOUNTAIN.Z), 40, M.Grass)

	-- Lake with an island in the middle (Blue emerald).
	terrain:FillCylinder(CFrame.new(LAKE.X, -5, LAKE.Z), 10, 150, M.Sand)
	terrain:FillCylinder(CFrame.new(LAKE.X, -8, LAKE.Z), 16, 130, M.Air)
	terrain:FillCylinder(CFrame.new(LAKE.X, -18, LAKE.Z), 4, 130, M.Sand)
	terrain:FillCylinder(CFrame.new(LAKE.X, -9, LAKE.Z), 14, 130, M.Water)
	terrain:FillCylinder(CFrame.new(LAKE.X, -6, LAKE.Z), 16, 28, M.Sand)
	terrain:FillCylinder(CFrame.new(LAKE.X, 1, LAKE.Z), 2, 22, M.Grass)

	-- Desert canyon with tall mesas (Yellow emerald on the middle mesa).
	terrain:FillBlock(CFrame.new(CANYON.X, -10, CANYON.Z), Vector3.new(300, 20, 300), M.Sand)
	terrain:FillCylinder(CFrame.new(CANYON.X, 35, CANYON.Z), 70, 30, M.Sandstone)
	local mesas = {
		{ -90, -80, 18, 50 },
		{ 80, -60, 22, 40 },
		{ -70, 90, 15, 60 },
		{ 95, 85, 20, 35 },
		{ 0, 120, 12, 45 },
		{ -120, 10, 14, 30 },
	}
	for _, m in ipairs(mesas) do
		terrain:FillCylinder(
			CFrame.new(CANYON.X + m[1], m[4] / 2, CANYON.Z + m[2]),
			m[4],
			m[3],
			rng:NextNumber() > 0.5 and M.Sandstone or M.Rock
		)
	end

	-- Rocky islet out at sea (Cyan emerald).
	terrain:FillCylinder(CFrame.new(ISLET.X, -6, ISLET.Z), 16, 24, M.Rock)
	terrain:FillCylinder(CFrame.new(ISLET.X, 1, ISLET.Z), 2, 20, M.Grass)
end

---------------------------------------------------------------------------
-- Scenery
---------------------------------------------------------------------------

local function palmTree(base, height)
	local model = Instance.new("Model")
	model.Name = "PalmTree"
	local lean = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * rng:NextNumber(2, 6)
	local prev = base - Vector3.new(0, 1, 0)
	local top
	for i = 1, 7 do
		local t = i / 7
		local p = base + Vector3.new(0, height * t, 0) + lean * (t * t)
		cylinderBetween(prev, p, 2.1 - t * 0.6, {
			Color = i % 2 == 0 and Color3.fromRGB(160, 110, 60) or Color3.fromRGB(135, 90, 45),
			Material = M.Wood,
		}, model)
		prev = p
		top = p
	end
	local leafCount = 8
	for i = 1, leafCount do
		local a = (i / leafCount) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local mid = top + dir * 6 + Vector3.new(0, 1.2, 0)
		local tip = mid + dir * 5 + Vector3.new(0, -3.5, 0)
		local green = i % 2 == 0 and Color3.fromRGB(60, 170, 50) or Color3.fromRGB(85, 200, 60)
		slabBetween(top, mid, 2.6, 0.3, { Color = green, Material = M.Grass, CanCollide = false }, model)
		slabBetween(mid, tip, 2.0, 0.3, { Color = green, Material = M.Grass, CanCollide = false }, model)
	end
	for i = 1, 3 do
		local a = i * 2.1
		part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.3, 1.3, 1.3),
			Position = top + Vector3.new(math.cos(a) * 0.9, -1, math.sin(a) * 0.9),
			Color = Color3.fromRGB(95, 60, 30),
		}, model)
	end
	model.Parent = folders.Scenery
end

local function sunflower(base)
	local model = Instance.new("Model")
	model.Name = "Sunflower"
	local height = rng:NextNumber(6, 9)
	local top = base + Vector3.new(0, height, 0)
	cylinderBetween(base - Vector3.new(0, 0.5, 0), top, 0.5, { Color = Color3.fromRGB(60, 160, 50), CanCollide = false }, model)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local face = CFrame.new(top) * CFrame.Angles(0, yaw, 0)
	-- Petals: two overlapping yellow discs, offset to look like a star.
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 4.4, 4.4), CFrame = face, Color = Color3.fromRGB(255, 215, 0), CanCollide = false }, model)
	part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.45, 1.8, 4.8),
		CFrame = face * CFrame.Angles(math.pi / 4, 0, 0),
		Color = Color3.fromRGB(255, 190, 0),
		CanCollide = false,
	}, model)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 2, 2), CFrame = face, Color = Color3.fromRGB(110, 60, 20), CanCollide = false }, model)
	for _, side in ipairs({ -1, 1 }) do
		local leafBase = base + Vector3.new(0, height * 0.45, 0)
		local dir = (face.RightVector * side)
		slabBetween(leafBase, leafBase + dir * 2.5 + Vector3.new(0, 0.8, 0), 1.2, 0.2, { Color = Color3.fromRGB(70, 175, 55), CanCollide = false }, model)
	end
	model.Parent = folders.Scenery
end

-- Green Hill style checkered totem pole.
local function totem(base, layers)
	local model = Instance.new("Model")
	model.Name = "CheckerTotem"
	local yaw = rng:NextNumber(0, math.pi * 2)
	for i = 0, layers - 1 do
		part({
			Size = Vector3.new(5, 5, 5),
			CFrame = CFrame.new(base + Vector3.new(0, 2.5 + i * 5, 0)) * CFrame.Angles(0, yaw + i * 0.15, 0),
			Color = i % 2 == 0 and COLORS.checkerA or COLORS.checkerB,
			Material = M.SmoothPlastic,
		}, model)
	end
	-- Little wings on top, like the classic totems.
	local topY = layers * 5 + 1.5
	for _, side in ipairs({ -1, 1 }) do
		part({
			ClassName = "WedgePart",
			Size = Vector3.new(0.8, 3, 4),
			CFrame = CFrame.new(base + Vector3.new(0, topY, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.new(side * 3, 0, 0) * CFrame.Angles(0, side * math.pi / 2, 0),
			Color = COLORS.blue,
		}, model)
	end
	model.Parent = folders.Scenery
end

local function rock(base)
	terrain:FillBall(base, rng:NextNumber(3, 7), M.Rock)
end

local function cloud(center)
	local model = Instance.new("Model")
	model.Name = "Cloud"
	for _ = 1, rng:NextInteger(4, 7) do
		local size = rng:NextNumber(18, 34)
		part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size, size),
			Position = center + Vector3.new(rng:NextNumber(-25, 25), rng:NextNumber(-4, 6), rng:NextNumber(-12, 12)),
			Color = Color3.fromRGB(255, 255, 255),
			Material = M.SmoothPlastic,
			Transparency = 0.12,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}, model)
	end
	model.Parent = folders.Scenery
end

local function checkerTiles(center, tilesX, tilesZ, tileSize, colorA, colorB, parent, y)
	for ix = 0, tilesX - 1 do
		for iz = 0, tilesZ - 1 do
			local x = center.X + (ix - (tilesX - 1) / 2) * tileSize
			local z = center.Z + (iz - (tilesZ - 1) / 2) * tileSize
			part({
				Size = Vector3.new(tileSize, 1, tileSize),
				Position = Vector3.new(x, (y or center.Y) - 0.5, z),
				Color = (ix + iz) % 2 == 0 and colorA or colorB,
				Material = M.SmoothPlastic,
			}, parent)
		end
	end
end

-- Floating island platform: grassy top with a brown checkered underside.
local function floatingPlatform(topCenter, diameter)
	local model = Instance.new("Model")
	model.Name = "FloatingIsland"
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, diameter, diameter), CFrame = verticalCylinderCFrame(topCenter - Vector3.new(0, 1, 0)), Color = COLORS.grassLight, Material = M.Grass }, model)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, diameter - 2, diameter - 2), CFrame = verticalCylinderCFrame(topCenter - Vector3.new(0, 4.5, 0)), Color = COLORS.checkerA }, model)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, diameter - 6, diameter - 6), CFrame = verticalCylinderCFrame(topCenter - Vector3.new(0, 9.5, 0)), Color = COLORS.checkerB }, model)
	model.Parent = folders.Scenery
	return model
end

local function welcomeSign()
	local model = Instance.new("Model")
	model.Name = "WelcomeSign"
	local z = -60
	for _, x in ipairs({ -22, 22 }) do
		for i = 0, 4 do
			part({
				Size = Vector3.new(4, 4, 4),
				Position = Vector3.new(x, 2 + i * 4, z),
				Color = i % 2 == 0 and COLORS.checkerA or COLORS.checkerB,
			}, model)
		end
	end
	local board = part({
		Size = Vector3.new(50, 10, 1.5),
		CFrame = CFrame.new(0, 24, z) * CFrame.Angles(0, math.pi, 0),
		Color = COLORS.blue,
		Material = M.SmoothPlastic,
	}, model)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(1000, 200)
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = Config.GameName
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 220, 40)
		label.TextStrokeColor3 = Color3.fromRGB(20, 20, 60)
		label.TextStrokeTransparency = 0
		label.Parent = gui
	end
	model.Parent = folders.Scenery
end

---------------------------------------------------------------------------
-- Rings (the gold coins)
---------------------------------------------------------------------------

local nextRingId = 0
local function ring(position)
	nextRingId += 1
	local outer = part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, 3.2, 3.2),
		CFrame = CFrame.new(position),
		Color = COLORS.gold,
		Material = M.Neon,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, nil)
	part({
		Name = "Inner",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 1.9, 1.9),
		CFrame = CFrame.new(position),
		Color = COLORS.darkGold,
		Material = M.Metal,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, outer)
	outer:SetAttribute("RingId", nextRingId)
	outer:SetAttribute("Active", true)
	outer.Parent = folders.Rings
	World.rings[nextRingId] = outer
end

local RING_LIFT = 3.5

-- A straight trail of rings. followGround makes it hug the hills.
local function ringLine(a, b, count, followGround)
	for i = 0, count - 1 do
		local p = a:Lerp(b, count == 1 and 0 or i / (count - 1))
		if followGround then
			p = onGround(p.X, p.Z, RING_LIFT)
		end
		ring(p)
	end
end

local function ringArc(a, b, height, count)
	for i = 0, count - 1 do
		local t = i / (count - 1)
		ring(a:Lerp(b, t) + Vector3.new(0, height * 4 * t * (1 - t), 0))
	end
end

local function ringCircle(center, radius, count, followGround)
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local p = center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
		if followGround then
			p = onGround(p.X, p.Z, RING_LIFT)
		end
		ring(p)
	end
end

---------------------------------------------------------------------------
-- Gimmicks: springs, dash pads, loop-de-loop
---------------------------------------------------------------------------

-- A spring sitting on `pos`. If `target` is given it launches you there,
-- otherwise it bounces you straight up.
local function spring(pos, target)
	local model = Instance.new("Model")
	model.Name = "Spring"
	part({ Size = Vector3.new(9, 1, 9), Position = pos + Vector3.new(0, -0.4, 0), Color = COLORS.checkerB }, model)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 6.5, 6.5), CFrame = verticalCylinderCFrame(pos + Vector3.new(0, 0.7, 0)), Color = COLORS.red }, model)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 3.6, 3.6), CFrame = verticalCylinderCFrame(pos + Vector3.new(0, 2.3, 0)), Color = Color3.fromRGB(170, 170, 180), Material = M.Metal }, model)
	local pad = part({
		Name = "SpringPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 6, 6),
		CFrame = verticalCylinderCFrame(pos + Vector3.new(0, 3.6, 0)),
		Color = Color3.fromRGB(255, 215, 0),
		Material = M.Neon,
	}, model)
	if target then
		pad:SetAttribute("Target", target)
	else
		pad:SetAttribute("Power", 120)
	end
	CollectionService:AddTag(pad, "Spring")
	model.Parent = folders.Gimmicks
	return pad
end

-- Dash panel: zooms you in direction `dir`.
local function dashPad(surface, dir)
	local cf = CFrame.lookAt(surface + Vector3.new(0, 0.2, 0), surface + Vector3.new(0, 0.2, 0) + dir)
	local model = Instance.new("Model")
	model.Name = "DashPad"
	local pad = part({ Name = "DashPad", Size = Vector3.new(9, 0.4, 11), CFrame = cf, Color = Color3.fromRGB(255, 200, 0), Material = M.Neon }, model)
	for _, tipZ in ipairs({ -3.5, 1 }) do
		for _, side in ipairs({ -1, 1 }) do
			local angle = math.rad(40) * side
			local dirLocal = Vector3.new(math.sin(angle), 0, math.cos(angle))
			local center = Vector3.new(0, 0.25, tipZ) + dirLocal * 2
			part({
				Size = Vector3.new(0.7, 0.2, 4),
				CFrame = cf * CFrame.new(center) * CFrame.Angles(0, angle, 0),
				Color = COLORS.red,
				Material = M.Neon,
				CanCollide = false,
			}, model)
		end
	end
	pad:SetAttribute("Speed", 140)
	CollectionService:AddTag(pad, "DashPad")
	model.Parent = folders.Gimmicks
end

-- Loop-de-loop. `entry` is the bottom point where you run in, facing `dir`.
local function loopDeLoop(entry, dir, radius)
	local shift = 16
	local cf = CFrame.lookAt(entry, entry + dir)
	local look, up, right = cf.LookVector, cf.UpVector, cf.RightVector
	local center = entry + up * radius
	local model = Instance.new("Model")
	model.Name = "Loop"
	local segments = 40
	local segLength = (2 * math.pi * (radius + 1)) / segments
	for i = 0, segments - 1 do
		local theta = (i + 0.5) / segments * math.pi * 2
		local radial = look * math.sin(theta) - up * math.cos(theta)
		local pos = center + radial * (radius + 1) + right * shift * (theta / (math.pi * 2))
		local forward = look * math.cos(theta) + up * math.sin(theta)
		part({
			Size = Vector3.new(12, 2, segLength * 1.15),
			CFrame = CFrame.lookAt(pos, pos + forward, -radial),
			Color = i % 2 == 0 and COLORS.blue or Color3.fromRGB(255, 210, 40),
			Material = M.SmoothPlastic,
			CanCollide = false,
		}, model)
	end
	model:SetAttribute("LoopCFrame", cf)
	model:SetAttribute("Radius", radius)
	model:SetAttribute("Shift", shift)
	CollectionService:AddTag(model, "Loop")
	model.Parent = folders.Gimmicks

	-- Rings that you grab while you ride around the loop.
	for i = 1, 18 do
		local theta = (i / 19) * math.pi * 2
		local radial = look * math.sin(theta) - up * math.cos(theta)
		ring(center + radial * (radius - 3) + right * shift * (theta / (math.pi * 2)))
	end
end

---------------------------------------------------------------------------
-- Chaos Emeralds
---------------------------------------------------------------------------

local function emerald(name, color, position)
	local model = Instance.new("Model")
	model.Name = "Emerald_" .. name
	local tilt = CFrame.Angles(math.rad(45), 0, math.rad(45))
	local gem = part({
		Name = "Gem",
		Size = Vector3.new(3, 3, 3),
		CFrame = CFrame.new(position) * tilt,
		Color = color,
		Material = M.Glass,
		Transparency = 0.15,
		Reflectance = 0.25,
		CanCollide = false,
	}, model)
	local core = part({
		Name = "Core",
		Size = Vector3.new(1.8, 1.8, 1.8),
		CFrame = CFrame.new(position) * tilt,
		Color = color,
		Material = M.Neon,
		CanCollide = false,
	}, model)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Brightness = 4
	light.Parent = core

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(color)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Rate = 14
	sparkles.Lifetime = NumberRange.new(0.8, 1.5)
	sparkles.Speed = NumberRange.new(2, 5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = gem

	-- Tall glowing beam so you can see the emerald from far away.
	part({
		Name = "Beacon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(400, 2.5, 2.5),
		CFrame = verticalCylinderCFrame(position + Vector3.new(0, 203, 0)),
		Color = color,
		Material = M.Neon,
		Transparency = 0.65,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	}, model)

	model.PrimaryPart = gem
	model:SetAttribute("EmeraldName", name)
	model:SetAttribute("BasePosition", position)
	model.Parent = folders.Emeralds
end

---------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------

local emeraldSpots = {}

local function buildStart()
	clearCircle(0, 0, 90)
	checkerTiles(Vector3.new(0, 0.6, 0), 9, 9, 8, COLORS.grassLight, COLORS.grassDark, folders.Scenery)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Start"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 1.1, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = COLORS.blue
	spawn.Material = M.Neon
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folders.Scenery
	World.spawnPosition = spawn.Position

	welcomeSign()
	ringCircle(Vector3.new(0, 0, 0), 22, 14, true)
	for _, corner in ipairs({ Vector3.new(30, 0, 30), Vector3.new(-30, 0, 30), Vector3.new(30, 0, -30), Vector3.new(-30, 0, -30) }) do
		totem(onGround(corner.X, corner.Z), 4)
	end
end

local function buildLoopZone()
	clearRect(-45, -330, 45, -20)
	ringLine(Vector3.new(0, 0, -40), Vector3.new(0, 0, -150), 12, true)
	dashPad(Vector3.new(0, groundY(0, -165), -165), Vector3.new(0, 0, -1))
	loopDeLoop(Vector3.new(LOOP_START.X, groundY(0, -200) + 0.05, LOOP_START.Z - 60), Vector3.new(0, 0, -1), 28)
	ringLine(Vector3.new(16, 0, -275), Vector3.new(16, 0, -420), 10, true)
end

local function buildSkyIslands()
	clearCircle(SKY.X, SKY.Z, 100)
	local platforms = {}
	for i = 1, 6 do
		local a = i * 1.05
		table.insert(platforms, Vector3.new(SKY.X + math.cos(a) * 55, 20 + i * 24, SKY.Z + math.sin(a) * 55))
	end
	local summit = Vector3.new(SKY.X, 20 + 7 * 24, SKY.Z)

	local first = onGround(SKY.X + 95, SKY.Z)
	spring(first, platforms[1])
	ringLine(Vector3.new(40, 0, -40), Vector3.new(first.X - 8, 0, first.Z + 8), 26, true)

	for i, top in ipairs(platforms) do
		floatingPlatform(top, 24)
		local nextTop = platforms[i + 1] or summit
		local toward = Vector3.new(nextTop.X - top.X, 0, nextTop.Z - top.Z).Unit
		spring(top + toward * 7, nextTop)
		ringCircle(top + Vector3.new(0, RING_LIFT, 0), 8, 5, false)
	end

	floatingPlatform(summit, 44)
	ringCircle(summit + Vector3.new(0, RING_LIFT, 0), 16, 12, false)
	totem(summit + Vector3.new(14, 0, 14), 3)
	totem(summit + Vector3.new(-14, 0, -14), 3)
	emeraldSpots.Green = summit + Vector3.new(0, 4, 0)
end

local function buildMountain()
	clearCircle(MOUNTAIN.X, MOUNTAIN.Z, 195)
	local base = onGround(MOUNTAIN.X, MOUNTAIN.Z + 185)
	local midway = onGround(MOUNTAIN.X, MOUNTAIN.Z + 100)
	local peak = onGround(MOUNTAIN.X, MOUNTAIN.Z)
	spring(base, midway + Vector3.new(0, 1, 0))
	spring(midway + Vector3.new(0, 1, 0), peak + Vector3.new(0, 1, 8))
	ringLine(Vector3.new(-40, 0, -30), Vector3.new(base.X + 6, 0, base.Z + 12), 22, true)
	ringCircle(peak, 16, 10, true)
	-- Rings spiralling around the mountain for anyone who climbs it on foot.
	for i = 1, 30 do
		local a = i * 0.42
		local d = 175 - i * 3.6
		local x, z = MOUNTAIN.X + math.cos(a) * d, MOUNTAIN.Z + math.sin(a) * d
		ring(onGround(x, z, RING_LIFT))
	end
	emeraldSpots.Red = peak + Vector3.new(0, 4, 0)
end

local function buildLake()
	clearCircle(LAKE.X, LAKE.Z, 160)
	ringLine(Vector3.new(40, 0, 10), Vector3.new(215, 0, 55), 14, true)
	-- Lily pads to hop across.
	local padY = -1.6
	for i = 0, 5 do
		local x = LAKE.X - 128 + i * 18
		part({
			Name = "LilyPad",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, 10, 10),
			CFrame = verticalCylinderCFrame(Vector3.new(x, padY, LAKE.Z + (i % 2 == 0 and 3 or -3))),
			Color = Color3.fromRGB(70, 175, 70),
			Material = M.Grass,
		}, folders.Scenery)
		ring(Vector3.new(x, padY + 5, LAKE.Z + (i % 2 == 0 and 3 or -3)))
	end
	spring(onGround(LAKE.X - 165, LAKE.Z - 30), Vector3.new(LAKE.X - 6, 2, LAKE.Z - 6))
	palmTree(Vector3.new(LAKE.X + 10, 2, LAKE.Z + 10), 22)
	palmTree(Vector3.new(LAKE.X - 12, 2, LAKE.Z + 8), 18)
	ringCircle(Vector3.new(LAKE.X, 2 + RING_LIFT, LAKE.Z), 14, 10, false)
	emeraldSpots.Blue = onGround(LAKE.X, LAKE.Z, 4)
end

local function buildCanyon()
	clearCircle(CANYON.X, CANYON.Z, 165)
	local mesaTop = onGround(CANYON.X, CANYON.Z)
	spring(onGround(CANYON.X, CANYON.Z + 48), mesaTop + Vector3.new(0, 1, 6))
	ringLine(Vector3.new(-40, 0, 40), Vector3.new(CANYON.X + 10, 0, CANYON.Z + 60), 24, true)
	ringCircle(mesaTop + Vector3.new(0, RING_LIFT, 0), 18, 10, false)
	for _ = 1, 6 do
		local x = CANYON.X + rng:NextNumber(-130, 130)
		local z = CANYON.Z + rng:NextNumber(-130, 130)
		if (Vector2.new(x, z) - Vector2.new(CANYON.X, CANYON.Z)).Magnitude > 45 then
			ringCircle(Vector3.new(x, 0, z), 7, 6, true)
		end
	end
	emeraldSpots.Yellow = mesaTop + Vector3.new(0, 4, 0)
end

local function buildTower()
	clearCircle(TOWER.X, TOWER.Z, 30)
	local base = onGround(TOWER.X, TOWER.Z)
	local model = Instance.new("Model")
	model.Name = "CheckerTower"
	for layer = 0, 15 do
		for ix = 0, 1 do
			for iz = 0, 1 do
				part({
					Size = Vector3.new(5, 5, 5),
					Position = base + Vector3.new(-2.5 + ix * 5, 2.5 + layer * 5, -2.5 + iz * 5),
					Color = (ix + iz + layer) % 2 == 0 and COLORS.checkerA or COLORS.checkerB,
				}, model)
			end
		end
	end
	local topY = base.Y + 80
	part({ Size = Vector3.new(18, 2, 18), Position = Vector3.new(TOWER.X, topY + 1, TOWER.Z), Color = COLORS.grassLight, Material = M.Grass }, model)
	model.Parent = folders.Scenery
	spring(onGround(TOWER.X, TOWER.Z + 22), Vector3.new(TOWER.X, topY + 2, TOWER.Z + 3))
	ringLine(Vector3.new(-25, 0, 40), Vector3.new(TOWER.X + 5, 0, TOWER.Z + 25), 10, true)
	ringCircle(Vector3.new(TOWER.X, topY + 2 + RING_LIFT, TOWER.Z), 6, 6, false)
	emeraldSpots.Purple = Vector3.new(TOWER.X, topY + 6, TOWER.Z)
end

local function buildSpeedway()
	clearRect(90, 395, 790, 465)
	local z = 430
	local startX, endX = 120, 620
	local length = endX - startX
	local midX = (startX + endX) / 2
	part({ Name = "Road", Size = Vector3.new(length, 1, 26), Position = Vector3.new(midX, 0.5, z), Color = COLORS.road, Material = M.Asphalt }, folders.Scenery)
	for _, side in ipairs({ -1, 1 }) do
		part({ Size = Vector3.new(length, 1.2, 1.5), Position = Vector3.new(midX, 0.6, z + side * 12.5), Color = Color3.fromRGB(255, 210, 40), Material = M.SmoothPlastic }, folders.Scenery)
	end
	for x = startX + 10, endX - 10, 24 do
		part({ Size = Vector3.new(10, 1.1, 1), Position = Vector3.new(x, 0.55, z), Color = COLORS.white, Material = M.SmoothPlastic, CanCollide = false }, folders.Scenery)
	end
	for x = startX + 40, endX - 60, 110 do
		dashPad(Vector3.new(x, 1, z), Vector3.xAxis)
	end
	for _, lane in ipairs({ -7, 0, 7 }) do
		ringLine(Vector3.new(startX + 20, 1 + RING_LIFT, z + lane), Vector3.new(endX - 30, 1 + RING_LIFT, z + lane), 18, false)
	end
	ringLine(Vector3.new(40, 0, 40), Vector3.new(startX - 5, 0, z - 5), 18, true)

	-- Goal: a ramp-spring that throws you up to a floating checkered platform.
	local goal = Vector3.new(735, 50, z)
	spring(Vector3.new(endX + 10, 1, z), goal)
	checkerTiles(goal, 4, 4, 6, COLORS.checkerA, COLORS.checkerB, folders.Scenery, goal.Y)
	ringArc(Vector3.new(endX + 10, 6, z), goal + Vector3.new(0, 4, 0), 30, 9)
	emeraldSpots.White = goal + Vector3.new(0, 4, 0)
end

local function buildBeach()
	clearRect(-12, 770, 12, 945)
	ringLine(Vector3.new(-500, 0, 700), Vector3.new(500, 0, 700), 40, true)
	ringLine(Vector3.new(0, 0, 60), Vector3.new(0, 0, 640), 30, true)
	-- Wooden pier out to the rocky islet.
	local pierStart, pierEnd = 775, 942
	part({ Name = "Pier", Size = Vector3.new(10, 1, pierEnd - pierStart), Position = Vector3.new(0, 1, (pierStart + pierEnd) / 2), Color = COLORS.wood, Material = M.WoodPlanks }, folders.Scenery)
	for zPost = pierStart + 5, pierEnd - 5, 20 do
		for _, side in ipairs({ -4.5, 4.5 }) do
			cylinderBetween(Vector3.new(side, -14, zPost), Vector3.new(side, 3, zPost), 1, { Color = COLORS.checkerB, Material = M.Wood }, folders.Scenery)
		end
	end
	ringLine(Vector3.new(0, 1.5 + RING_LIFT, pierStart + 10), Vector3.new(0, 1.5 + RING_LIFT, pierEnd - 10), 12, false)
	palmTree(Vector3.new(ISLET.X + 10, 2, ISLET.Z + 8), 20)
	ringCircle(Vector3.new(ISLET.X, 2 + RING_LIFT, ISLET.Z), 12, 8, false)
	emeraldSpots.Cyan = onGround(ISLET.X, ISLET.Z, 4)

	for _ = 1, 22 do
		local x = rng:NextNumber(-720, 720)
		local zz = rng:NextNumber(735, 790)
		if math.abs(x) > 20 then
			palmTree(onGround(x, zz), rng:NextNumber(18, 26))
		end
	end
end

local function buildBadnikRoutes()
	local routes = {
		{ -60, -80, -60, -140 },
		{ 80, -60, 140, -60 },
		{ 200, 150, 260, 190 },
		{ -200, -150, -260, -200 },
		{ -300, 250, -350, 300 },
		{ 300, 410, 300, 450 },
		{ 450, 410, 450, 450 },
		{ 100, 600, -100, 600 },
		{ 450, -300, 520, -300 },
		{ -500, 100, -560, 160 },
		{ 600, 0, 600, -80 },
		{ -100, 330, -40, 380 },
		{ 250, -250, 250, -330 },
	}
	for _, r in ipairs(routes) do
		table.insert(World.badnikRoutes, { a = onGround(r[1], r[2]), b = onGround(r[3], r[4]) })
	end
end

local function scatterScenery()
	local placed = 0
	local attempts = 0
	while placed < 140 and attempts < 2000 do
		attempts += 1
		local x, z = rng:NextNumber(-760, 760), rng:NextNumber(-760, 620)
		if isClear(x, z) then
			local y = groundY(x, z)
			if y > 0.3 then
				local roll = rng:NextNumber()
				local base = Vector3.new(x, y, z)
				if roll < 0.35 then
					palmTree(base, rng:NextNumber(18, 30))
				elseif roll < 0.7 then
					sunflower(base)
				elseif roll < 0.85 then
					totem(base, rng:NextInteger(3, 6))
				else
					rock(base)
				end
				placed += 1
			end
		end
	end

	-- Ring clusters and ring arcs over the hills.
	for i, hill in ipairs(HILLS) do
		local x, z = hill[1], hill[2]
		if isClear(x, z) then
			if i % 2 == 0 then
				ringCircle(Vector3.new(x, 0, z), 9, 8, true)
			else
				local top = onGround(x, z, RING_LIFT)
				ringArc(top - Vector3.new(25, 0, 0), top + Vector3.new(25, 0, 0), 12, 9)
			end
		end
	end

	for _ = 1, 22 do
		cloud(Vector3.new(rng:NextNumber(-900, 900), rng:NextNumber(230, 320), rng:NextNumber(-900, 900)))
	end

	-- Invisible walls so nobody runs off into the endless sea.
	local edge = 1150
	for _, wall in ipairs({
		{ Vector3.new(edge, 300, 0), Vector3.new(4, 700, edge * 2) },
		{ Vector3.new(-edge, 300, 0), Vector3.new(4, 700, edge * 2) },
		{ Vector3.new(0, 300, edge), Vector3.new(edge * 2, 700, 4) },
		{ Vector3.new(0, 300, -edge), Vector3.new(edge * 2, 700, 4) },
	}) do
		part({ Name = "Boundary", Position = wall[1], Size = wall[2], Transparency = 1, CanQuery = false }, folders.Scenery)
	end
end

---------------------------------------------------------------------------

function World.build()
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	local map = Instance.new("Folder")
	map.Name = "Map"
	for _, name in ipairs({ "Scenery", "Rings", "Emeralds", "Gimmicks", "Badniks" }) do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = map
		folders[name] = f
	end

	setupLighting()
	buildTerrain()

	buildStart()
	buildLoopZone()
	buildSkyIslands()
	buildMountain()
	buildLake()
	buildCanyon()
	buildTower()
	buildSpeedway()
	buildBeach()
	buildBadnikRoutes()
	scatterScenery()

	for _, info in ipairs(Config.Emeralds) do
		local spot = emeraldSpots[info.Name]
		if spot then
			emerald(info.Name, info.Color, spot)
		else
			warn("No spot for emerald " .. info.Name)
		end
	end

	World.badnikFolder = folders.Badniks
	map.Parent = workspace
	print(("[%s] World built: %d rings, %d emeralds"):format(Config.GameName, nextRingId, #folders.Emeralds:GetChildren()))
end

return World
