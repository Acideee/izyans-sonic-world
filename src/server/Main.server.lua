-- Izyan's Sonic World - server entry point.
-- Builds the world, then handles rings, Chaos Emeralds, Badniks and Super Sonic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local World = require(script.Parent.WorldBuilder)
local SonicLook = require(script.Parent.SonicLook)
local Badniks = require(script.Parent.Badniks)

-- Don't spawn anyone until the world exists.
Players.CharacterAutoLoads = false

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local CollectRing = remote("CollectRing")
local CollectEmerald = remote("CollectEmerald")
local GoSuper = remote("GoSuper")
local BadnikHit = remote("BadnikHit")
local PlayerHurt = remote("PlayerHurt")
local Notify = remote("Notify")
remotes.Parent = ReplicatedStorage

World.build()
Badniks.start(World.badnikRoutes, World.badnikFolder)

local MAX_REACH = 30 -- how far (studs) the server allows a pickup to be from the player
local VALID_EMERALDS = {}
for _, info in ipairs(Config.Emeralds) do
	VALID_EMERALDS[info.Name] = true
end

local state = {} -- [player] = { emeralds = {Name = true}, count = 0, lastHurt = 0 }

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function ringsValue(player)
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild("Rings")
end

local function addRings(player, amount)
	local rings = ringsValue(player)
	if rings then
		rings.Value = math.max(0, rings.Value + amount)
	end
end

-- Swap the player's character for a copy of `template`, keeping where they are
-- and how fast they're going. Used to change into an imported Super Sonic model.
local function swapCharacter(player, template)
	local old = player.Character
	local oldRoot = old and old:FindFirstChild("HumanoidRootPart")
	if not (template and oldRoot) then
		return false
	end
	local new = template:Clone()
	new.Name = player.Name
	new:SetAttribute("SuperSwap", true) -- tells CharacterAdded this isn't a respawn
	local animate = old:FindFirstChild("Animate")
	if animate and not new:FindFirstChild("Animate") then
		animate:Clone().Parent = new
	end
	if new.PrimaryPart then
		new:PivotTo(oldRoot.CFrame)
	else
		new:PivotTo(old:GetPivot())
	end
	SonicLook.fixFacing(new)
	local velocity = oldRoot.AssemblyLinearVelocity
	player.Character = new
	new.Parent = workspace
	local root = new:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = velocity
	end
	old:Destroy()
	return true
end

-- If you put an imported Super Sonic model in ServerStorage named
-- "SuperSonicCharacter" (see README), going Super swaps to it and back.
local function superModel()
	return ServerStorage:FindFirstChild("SuperSonicCharacter")
end

local function setSuper(player, on)
	if player:GetAttribute("IsSuper") == on then
		return
	end
	player:SetAttribute("IsSuper", on)
	local swapped = false
	if superModel() then
		local template = on and superModel() or StarterPlayer:FindFirstChild("StarterCharacter")
		swapped = swapCharacter(player, template)
	end
	if player.Character then
		SonicLook.setSuper(player.Character, on, swapped)
	end
	Notify:FireClient(player, "Super", on)
end

local function setRingActive(ring, active)
	ring:SetAttribute("Active", active)
	local t = active and 0 or 1
	ring.Transparency = t
	local inner = ring:FindFirstChild("Inner")
	if inner then
		inner.Transparency = t
	end
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

local function onPlayerAdded(player)
	state[player] = { emeralds = {}, count = 0, lastHurt = 0 }

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local rings = Instance.new("IntValue")
	rings.Name = "Rings"
	rings.Parent = stats
	local emeralds = Instance.new("IntValue")
	emeralds.Name = "Emeralds"
	emeralds.Parent = stats
	stats.Parent = player

	player:SetAttribute("Emeralds", "")
	player:SetAttribute("IsSuper", false)

	player.CharacterAdded:Connect(function(character)
		if character:GetAttribute("SuperSwap") then
			return -- changing into or out of the Super Sonic model, not a respawn
		end
		-- Respawning ends Super form.
		player:SetAttribute("IsSuper", false)
		-- Wait until Roblox has finished building the body before dressing it,
		-- then check again shortly after in case body parts were swapped out.
		character:WaitForChild("Humanoid", 10)
		local waited = 0
		while not player:HasAppearanceLoaded() and waited < 5 do
			waited += task.wait(0.1)
		end
		character:WaitForChild("UpperTorso", 5)
		for _, delay in ipairs({ 0, 1, 3 }) do
			task.wait(delay)
			if character.Parent then
				SonicLook.apply(character, player:GetAttribute("IsSuper"))
			end
		end
	end)
	-- Re-apply once the player's own avatar has finished loading over the top.
	player.CharacterAppearanceLoaded:Connect(function(character)
		SonicLook.apply(character, player:GetAttribute("IsSuper"))
	end)

	player:LoadCharacter()
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerRemoving:Connect(function(player)
	state[player] = nil
end)
Players.CharacterAutoLoads = true

---------------------------------------------------------------------------
-- Rings
---------------------------------------------------------------------------

CollectRing.OnServerEvent:Connect(function(player, ringId)
	if typeof(ringId) ~= "number" then
		return
	end
	local ring = World.rings[ringId]
	local root = rootOf(player)
	if not ring or not root or ring:GetAttribute("Active") ~= true then
		return
	end
	if (root.Position - ring.Position).Magnitude > MAX_REACH then
		return
	end
	setRingActive(ring, false)
	addRings(player, 1)
	task.delay(Config.Rings.RespawnTime, function()
		setRingActive(ring, true)
	end)
end)

---------------------------------------------------------------------------
-- Chaos Emeralds
---------------------------------------------------------------------------

CollectEmerald.OnServerEvent:Connect(function(player, name)
	local data = state[player]
	if not data or typeof(name) ~= "string" or not VALID_EMERALDS[name] or data.emeralds[name] then
		return
	end
	local model = workspace.Map.Emeralds:FindFirstChild("Emerald_" .. name)
	local root = rootOf(player)
	if not model or not root then
		return
	end
	if (root.Position - model:GetAttribute("BasePosition")).Magnitude > MAX_REACH then
		return
	end

	data.emeralds[name] = true
	data.count += 1
	local names = {}
	for _, info in ipairs(Config.Emeralds) do
		if data.emeralds[info.Name] then
			table.insert(names, info.Name)
		end
	end
	player:SetAttribute("Emeralds", table.concat(names, ","))
	player.leaderstats.Emeralds.Value = data.count
	addRings(player, 10)
	Notify:FireClient(player, "Emerald", name, data.count)
	if data.count == #Config.Emeralds then
		Notify:FireClient(player, "AllEmeralds")
	end
end)

---------------------------------------------------------------------------
-- Super Sonic
---------------------------------------------------------------------------

GoSuper.OnServerEvent:Connect(function(player)
	local data = state[player]
	local rings = ringsValue(player)
	if not data or not rings or not player.Character then
		return
	end
	if player:GetAttribute("IsSuper") then
		setSuper(player, false)
		return
	end
	if data.count < #Config.Emeralds then
		Notify:FireClient(player, "Message", "Find all 7 Chaos Emeralds first!")
		return
	end
	if rings.Value < Config.Super.RingsNeeded then
		Notify:FireClient(player, "Message", ("You need %d rings to go Super!"):format(Config.Super.RingsNeeded))
		return
	end
	if player:GetAttribute("PoweringUp") then
		return
	end
	-- Power up first (the client plays the lift-off and emeralds), then BAM!
	player:SetAttribute("PoweringUp", true)
	Notify:FireClient(player, "PowerUp", Config.Super.PowerUpTime)
	task.delay(Config.Super.PowerUpTime, function()
		player:SetAttribute("PoweringUp", false)
		if player.Parent and player.Character then
			setSuper(player, true)
		end
	end)
end)

-- Super form slowly uses up rings, just like in the real games.
task.spawn(function()
	while true do
		task.wait(1 / Config.Super.RingDrainPerSecond)
		for player in pairs(state) do
			if player:GetAttribute("IsSuper") then
				local rings = ringsValue(player)
				if not rings or rings.Value <= 0 then
					setSuper(player, false)
				else
					rings.Value -= 1
				end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Badniks
---------------------------------------------------------------------------

local function closeTo(player, model)
	local root = rootOf(player)
	return root and (root.Position - model:GetPivot().Position).Magnitude < MAX_REACH
end

BadnikHit.OnServerEvent:Connect(function(player, model)
	if not Badniks.isAlive(model) or not closeTo(player, model) then
		return
	end
	if Badniks.destroy(model) then
		addRings(player, Config.Rings.BadnikReward)
		Notify:FireClient(player, "Badnik", Config.Rings.BadnikReward)
	end
end)

PlayerHurt.OnServerEvent:Connect(function(player, model)
	local data = state[player]
	if not data or player:GetAttribute("IsSuper") then
		return
	end
	if not Badniks.isAlive(model) or not closeTo(player, model) then
		return
	end
	if os.clock() - data.lastHurt < 2 then
		return
	end
	data.lastHurt = os.clock()
	local rings = ringsValue(player)
	local lost = rings and math.min(rings.Value, Config.Rings.HurtLoss) or 0
	addRings(player, -lost)
	Notify:FireClient(player, "Hurt", lost)
end)
