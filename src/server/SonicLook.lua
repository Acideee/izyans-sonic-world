-- Turns every player into a cartoon Sonic (and into golden Super Sonic).
--
-- The Sonic body is made of rounded parts listed in Shared/SonicModel.json.
-- Each part is welded onto a limb of the normal R15 skeleton, which is then made
-- invisible, so Roblox's running and jumping animations still move Sonic.
-- Edit the look with tools/make_sonic_model.py.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
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
local function costumeIntact(costume)
	for _, part in ipairs(costume:GetChildren()) do
		local weld = part:FindFirstChildOfClass("Weld")
		if not (weld and weld.Part0 and weld.Part0.Parent == costume.Parent) then
			return false
		end
	end
	return true
end

local function buildCostume(character)
	local existing = character:FindFirstChild("SonicCostume")
	if existing then
		if costumeIntact(existing) then
			return true
		end
		existing:Destroy() -- body parts were replaced after we dressed him: rebuild
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
	print(("[SonicLook] Sonic body built for %s (%d pieces)"):format(character.Name, #costume:GetChildren()))
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

-- True when you've imported your own Sonic model as StarterPlayer.StarterCharacter.
-- Then the game uses that model exactly as it is.
local function usesImportedModel()
	return StarterPlayer:FindFirstChild("StarterCharacter") ~= nil
end

-- Turn an imported model's body 180° around its root, so it faces the way
-- it runs. Only done once per character.
function SonicLook.fixFacing(character)
	if not Config.TurnImportedModelsAround or character:GetAttribute("FacingFixed") then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, joint in ipairs(character:GetDescendants()) do
		if joint:IsA("Motor6D") and joint.Part0 == root then
			joint.C0 = joint.C0 * CFrame.Angles(0, math.pi, 0)
			character:SetAttribute("FacingFixed", true)
			print("[SonicLook] Turned " .. character.Name .. " around to face forwards")
			return
		end
	end
	warn("[SonicLook] Couldn't find the root joint to turn " .. character.Name .. " around")
end

-- Safe to call more than once (e.g. when the avatar finishes loading late).
function SonicLook.apply(character, super)
	if usesImportedModel() then
		SonicLook.fixFacing(character)
		return
	end
	stripAvatar(character)
	if not buildCostume(character) then
		local parts = {}
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(parts, child.Name)
			end
		end
		warn("[SonicLook] No R15 body found, colouring instead. Parts: " .. table.concat(parts, ", "))
		paintR6(character, super)
	end
	recolor(character, super)
end

-- `isSuperModel` is true when the character was swapped for an imported Super
-- Sonic model, which is already gold, so it only gets the sparkles and light.
function SonicLook.setSuper(character, on, isSuperModel)
	if not usesImportedModel() then
		recolor(character, on)
	end
	local glow = character:FindFirstChild("SuperGlow")
	if glow then
		glow:Destroy()
	end
	if on then
		-- Golden outline around him. An imported blue Sonic (with no Super model
		-- to swap to) is also tinted gold, since textures can't be recoloured.
		local highlight = Instance.new("Highlight")
		highlight.Name = "SuperGlow"
		highlight.FillColor = GOLD
		highlight.FillTransparency = (usesImportedModel() and not isSuperModel) and 0.35 or 1
		highlight.OutlineColor = Color3.fromRGB(255, 225, 90)
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = character
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, name in ipairs({ "SuperLight", "SuperSparkles", "SuperAuraShell" }) do
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

	-- The golden aura: soft flames rising all around his body, from an
	-- invisible body-sized shell welded to him.
	local shell = Instance.new("Part")
	shell.Name = "SuperAuraShell"
	shell.Size = Vector3.new(3.2, 5.6, 3.2)
	shell.Transparency = 1
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.Massless = true
	shell.CFrame = root.CFrame * CFrame.new(0, 0.3, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = shell
	weld.Parent = shell
	shell.Parent = root

	local aura = Instance.new("ParticleEmitter")
	aura.Name = "SuperAura"
	aura.Texture = "rbxasset://textures/particles/fire_main.dds"
	aura.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 210)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 215, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 160, 20)),
	})
	aura.LightEmission = 1
	aura.LightInfluence = 0
	aura.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(0.5, 2.4),
		NumberSequenceKeypoint.new(1, 0.4),
	})
	aura.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	aura.Shape = Enum.ParticleEmitterShape.Cylinder
	aura.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	aura.Acceleration = Vector3.new(0, 6, 0)
	aura.Speed = NumberRange.new(1, 3)
	aura.Lifetime = NumberRange.new(0.5, 0.9)
	aura.Rate = 70
	aura.LockedToPart = true
	aura.Parent = shell
end

return SonicLook
