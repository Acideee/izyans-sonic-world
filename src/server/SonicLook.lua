-- Turns any player's avatar into a blue hedgehog (and into golden Super Sonic).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SonicLook = {}

local BLUE = Color3.fromRGB(25, 75, 230)
local PEACH = Color3.fromRGB(245, 200, 150)
local WHITE = Color3.fromRGB(250, 250, 250)
local RED = Color3.fromRGB(220, 30, 40)
local GOLD = Config.Super.Color

-- Works for both R15 and R6 avatars.
local PART_COLORS = {
	Head = BLUE,
	UpperTorso = BLUE,
	LowerTorso = BLUE,
	Torso = BLUE,
	LeftUpperArm = PEACH,
	LeftLowerArm = PEACH,
	RightUpperArm = PEACH,
	RightLowerArm = PEACH,
	["Left Arm"] = PEACH,
	["Right Arm"] = PEACH,
	LeftHand = WHITE,
	RightHand = WHITE,
	LeftUpperLeg = BLUE,
	LeftLowerLeg = BLUE,
	RightUpperLeg = BLUE,
	RightLowerLeg = BLUE,
	["Left Leg"] = BLUE,
	["Right Leg"] = BLUE,
	LeftFoot = RED,
	RightFoot = RED,
}

-- Quills: {height on head, how far they droop, sideways angle}
local QUILLS = {
	{ 0.35, 0.12, 0 },
	{ 0.05, 0.38, 0 },
	{ -0.28, 0.65, 0 },
	{ 0.2, 0.28, 0.4 },
	{ 0.2, 0.28, -0.4 },
	{ -0.1, 0.5, 0.35 },
	{ -0.1, 0.5, -0.35 },
}

local function stripAvatar(character)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Destroy()
		end
	end
end

local function weldTo(part, target)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = target
	weld.Part1 = part
	weld.Parent = part
end

local function addQuills(character)
	local head = character:FindFirstChild("Head")
	if not head or character:FindFirstChild("SonicQuills") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "SonicQuills"
	local size = head.Size
	local s = math.max(size.Y, 1)
	local length = 1.9 * s

	for _, q in ipairs(QUILLS) do
		local droop, side = q[2], q[3]
		-- Direction the quill points in head space (+Z is the back of the head).
		local dir = Vector3.new(math.sin(side), -math.sin(droop), math.cos(droop) * math.cos(side)).Unit
		local attach = Vector3.new(0, q[1] * size.Y, size.Z * 0.25)
		local center = attach + dir * (length / 2)
		local quill = Instance.new("WedgePart")
		quill.Name = "Quill"
		quill.Size = Vector3.new(0.35 * s, 0.75 * s, length)
		-- A WedgePart tapers towards its front (-Z), so point the front along `dir`.
		quill.CFrame = head.CFrame * CFrame.lookAt(center, center + dir)
		quill.Color = BLUE
		quill.Material = Enum.Material.SmoothPlastic
		quill.CanCollide = false
		quill.CanQuery = false
		quill.CanTouch = false
		quill.Massless = true
		weldTo(quill, head)
		quill.Parent = folder
	end

	local muzzle = Instance.new("Part")
	muzzle.Name = "Muzzle"
	muzzle.Shape = Enum.PartType.Ball
	muzzle.Size = Vector3.new(0.55, 0.55, 0.55) * s
	muzzle.CFrame = head.CFrame * CFrame.new(0, -0.22 * size.Y, -size.Z * 0.42)
	muzzle.Color = PEACH
	muzzle.Material = Enum.Material.SmoothPlastic
	muzzle.CanCollide = false
	muzzle.CanQuery = false
	muzzle.CanTouch = false
	muzzle.Massless = true
	weldTo(muzzle, head)
	muzzle.Parent = folder

	folder.Parent = character
end

local function paint(character, super)
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") then
			local base = PART_COLORS[item.Name]
			if item.Name == "Quill" then
				base = BLUE
			end
			if base then
				item.Color = (super and base == BLUE) and GOLD or base
				item.Material = super and Enum.Material.Neon or Enum.Material.SmoothPlastic
				if item:IsA("MeshPart") then
					pcall(function()
						item.TextureID = "" -- remove avatar skin textures so the colours show
					end)
				end
			end
		end
	end
end

-- Safe to call more than once (e.g. when the avatar finishes loading late).
function SonicLook.apply(character, super)
	stripAvatar(character)
	addQuills(character)
	paint(character, super)
end

function SonicLook.setSuper(character, on)
	paint(character, on)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, name in ipairs({ "SuperLight", "SuperSparkles" }) do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	if not on then
		return
	end

	local light = Instance.new("PointLight")
	light.Name = "SuperLight"
	light.Color = GOLD
	light.Range = 22
	light.Brightness = 3
	light.Parent = root

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "SuperSparkles"
	sparkle.Color = ColorSequence.new(GOLD, Color3.fromRGB(255, 255, 200))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Rate = 40
	sparkle.Lifetime = NumberRange.new(0.5, 1)
	sparkle.Speed = NumberRange.new(3, 7)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Parent = root
end

return SonicLook
