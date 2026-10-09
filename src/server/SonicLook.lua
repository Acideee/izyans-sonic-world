-- Turns every player into a cartoon Sonic (and into golden Super Sonic).
--
-- The Sonic body is made of rounded parts listed in Shared/SonicModel.json.
-- Each part is welded onto a limb of the normal R15 skeleton, which is then made
-- invisible, so Roblox's running and jumping animations still move Sonic.
-- Edit the look with tools/make_sonic_model.py.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Model = require(Shared:WaitForChild("SonicModel"))

local SonicLook = {}

local GOLD = Config.Super.Color
local SMOOTH = Enum.Material.SmoothPlastic
local GLOSSY = { white = true, black = true, iris = true }

local function rgb(list)
	return Color3.fromRGB(list[1], list[2], list[3])
end

local function tintColor(tint, super)
	local list = (super and Model.superColors[tint]) or Model.colors[tint]
	return list and rgb(list) or Color3.new(1, 1, 1)
end

local function vec(list)
	return Vector3.new(list[1], list[2], list[3])
end

local function stripAvatar(character)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Destroy()
		end
	end
end

-- Build the cartoon body on an R15 skeleton. Returns false if the rig isn't R15.
local function buildCostume(character)
	if character:FindFirstChild("SonicCostume") then
		return true
	end
	if not character:FindFirstChild("UpperTorso") then
		return false
	end

	local costume = Instance.new("Folder")
	costume.Name = "SonicCostume"

	for _, piece in ipairs(Model.pieces) do
		local limb = character:FindFirstChild(piece.part)
		if limb and limb:IsA("BasePart") then
			local part = Instance.new("Part")
			part.Name = piece.name
			part.Size = vec(piece.size)
			if piece.shape == "sphere" then
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = part
			elseif piece.shape == "cylinder" then
				part.Shape = Enum.PartType.Cylinder
			end
			part.Material = SMOOTH
			part.Color = tintColor(piece.tint, false)
			part.Reflectance = GLOSSY[piece.tint] and 0.08 or 0
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.CastShadow = true
			part:SetAttribute("Tint", piece.tint)

			local rot = piece.rot
			local offset = CFrame.new(vec(piece.pos)) * CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
			part.CFrame = limb.CFrame * offset

			-- A Weld with a fixed offset (not a WeldConstraint) so the piece stays
			-- in the right place even if the limb is mid-animation right now.
			local weld = Instance.new("Weld")
			weld.Part0 = limb
			weld.Part1 = part
			weld.C0 = offset
			weld.Parent = part

			part.Parent = costume
		end
	end

	-- Hide the blocky skeleton and its face; only the cartoon Sonic shows.
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("BasePart") and item.Name ~= "HumanoidRootPart" then
			item.Transparency = 1
			for _, decal in ipairs(item:GetChildren()) do
				if decal:IsA("Decal") then
					decal.Transparency = 1
				end
			end
		end
	end

	costume.Parent = character
	return true
end

-- Fallback for R6 avatars: just colour the blocky body like Sonic.
local R6_COLORS = {
	Head = "blue",
	Torso = "blue",
	["Left Arm"] = "peach",
	["Right Arm"] = "peach",
	["Left Leg"] = "blue",
	["Right Leg"] = "blue",
}

local function paintR6(character, super)
	for name, tint in pairs(R6_COLORS) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = tintColor(tint, super)
			part.Material = SMOOTH
		end
	end
end

local function recolor(character, super)
	local costume = character:FindFirstChild("SonicCostume")
	if costume then
		for _, part in ipairs(costume:GetChildren()) do
			local tint = part:GetAttribute("Tint")
			if tint then
				part.Color = tintColor(tint, super)
			end
		end
	else
		paintR6(character, super)
	end
end

-- Safe to call more than once (e.g. when the avatar finishes loading late).
function SonicLook.apply(character, super)
	stripAvatar(character)
	if not buildCostume(character) then
		paintR6(character, super)
	end
	recolor(character, super)
end

function SonicLook.setSuper(character, on)
	recolor(character, on)
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
