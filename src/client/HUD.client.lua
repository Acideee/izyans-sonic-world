-- Izyan's Sonic World - on-screen HUD: rings, Chaos Emerald tracker, quest, speed and announcements.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EmeraldFolder = workspace:WaitForChild("Map"):WaitForChild("Emeralds")

local player = Players.LocalPlayer
local FONT = Enum.Font.FredokaOne
local GOLD = Color3.fromRGB(255, 205, 40)
local NAVY = Color3.fromRGB(15, 25, 70)

local function new(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(0, 12) }, parent)
end

local function stroke(parent, color, thickness)
	return new("UIStroke", { Color = color or NAVY, Thickness = thickness or 2 }, parent)
end

local function label(props, parent)
	props.BackgroundTransparency = 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	local l = new("TextLabel", props, parent)
	new("UIStroke", { Color = NAVY, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	return l
end

local gui = new("ScreenGui", {
	Name = "SonicHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

---------------------------------------------------------------------------
-- Ring counter (top left)
---------------------------------------------------------------------------

local ringPanel = new("Frame", {
	Position = UDim2.new(0, 16, 0, 12),
	Size = UDim2.new(0, 190, 0, 64),
	BackgroundColor3 = Color3.fromRGB(20, 40, 120),
	BackgroundTransparency = 0.25,
}, gui)
corner(ringPanel, UDim.new(0, 32))
stroke(ringPanel, Color3.fromRGB(255, 255, 255), 2)

local ringIcon = new("Frame", {
	Position = UDim2.new(0, 12, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	Size = UDim2.new(0, 42, 0, 42),
	BackgroundTransparency = 1,
}, ringPanel)
corner(ringIcon, UDim.new(1, 0))
new("UIStroke", { Color = GOLD, Thickness = 7 }, ringIcon)

local ringText = label({
	Position = UDim2.new(0, 66, 0, 0),
	Size = UDim2.new(1, -76, 1, 0),
	Text = "0",
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = GOLD,
}, ringPanel)

---------------------------------------------------------------------------
-- Chaos Emerald tracker (top centre)
---------------------------------------------------------------------------

local emeraldBar = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.new(0, 7 * 46 + 20, 0, 58),
	BackgroundColor3 = Color3.fromRGB(10, 15, 40),
	BackgroundTransparency = 0.35,
}, gui)
corner(emeraldBar, UDim.new(0, 18))
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, emeraldBar)

local slots = {}
for i, info in ipairs(Config.Emeralds) do
	local slot = new("Frame", {
		LayoutOrder = i,
		Size = UDim2.new(0, 30, 0, 30),
		Rotation = 45,
		BackgroundColor3 = Color3.fromRGB(70, 70, 80),
		BackgroundTransparency = 0.3,
	}, emeraldBar)
	corner(slot, UDim.new(0, 5))
	local s = stroke(slot, Color3.fromRGB(140, 140, 150), 2)
	slots[info.Name] = { frame = slot, stroke = s, color = info.Color }
end

local questText = label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 72),
	Size = UDim2.new(0, 620, 0, 30),
	TextScaled = true,
	Text = "",
}, gui)

local distanceText = label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 102),
	Size = UDim2.new(0, 400, 0, 22),
	TextScaled = true,
	Text = "",
	TextColor3 = Color3.fromRGB(200, 230, 255),
}, gui)

---------------------------------------------------------------------------
-- Speed meter (top right)
---------------------------------------------------------------------------

local speedPanel = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 12),
	Size = UDim2.new(0, 200, 0, 46),
	BackgroundColor3 = Color3.fromRGB(10, 15, 40),
	BackgroundTransparency = 0.35,
}, gui)
corner(speedPanel, UDim.new(0, 14))
label({ Position = UDim2.new(0, 10, 0, 2), Size = UDim2.new(0, 70, 0, 18), Text = "SPEED", TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left }, speedPanel)
local speedTrack = new("Frame", {
	Position = UDim2.new(0, 10, 0, 24),
	Size = UDim2.new(1, -20, 0, 14),
	BackgroundColor3 = Color3.fromRGB(40, 45, 70),
}, speedPanel)
corner(speedTrack, UDim.new(1, 0))
local speedFill = new("Frame", {
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = Color3.fromRGB(60, 160, 255),
}, speedTrack)
corner(speedFill, UDim.new(1, 0))

---------------------------------------------------------------------------
-- Announcements, flash and the GO SUPER button
---------------------------------------------------------------------------

local announce = label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.32, 0),
	Size = UDim2.new(0.8, 0, 0, 70),
	TextScaled = true,
	Text = "",
	TextTransparency = 1,
}, gui)
local announceStroke = announce:FindFirstChildOfClass("UIStroke")

local flash = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1,
	ZIndex = 10,
}, gui)

local superButton = new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.72, 0),
	Size = UDim2.new(0, 260, 0, 70),
	BackgroundColor3 = GOLD,
	Text = "GO SUPER!",
	Font = FONT,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(120, 50, 0),
	Visible = false,
}, gui)
corner(superButton, UDim.new(0, 35))
stroke(superButton, Color3.new(1, 1, 1), 4)
superButton.Activated:Connect(function()
	Remotes.GoSuper:FireServer()
end)

local announceToken = 0
local function showAnnouncement(text, color, duration)
	announceToken += 1
	local token = announceToken
	announce.Text = text
	announce.TextColor3 = color or Color3.new(1, 1, 1)
	announce.TextTransparency = 0
	if announceStroke then
		announceStroke.Transparency = 0
	end
	announce.Size = UDim2.new(0.5, 0, 0, 40)
	TweenService:Create(announce, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.new(0.8, 0, 0, 70) }):Play()
	task.delay(duration or 2.5, function()
		if token == announceToken then
			TweenService:Create(announce, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			if announceStroke then
				TweenService:Create(announceStroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			end
		end
	end)
end

local function screenFlash(color)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 0.2
	TweenService:Create(flash, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
end

local function playSound(id, volume, pitch)
	if id and id ~= "" then
		local s = new("Sound", { SoundId = id, Volume = volume or 0.6, PlaybackSpeed = pitch or 1 }, SoundService)
		s:Play()
		task.delay(8, function()
			s:Destroy()
		end)
	end
end

---------------------------------------------------------------------------
-- Music
---------------------------------------------------------------------------

local music = new("Sound", { Name = "Music", Looped = true, Volume = 0.35, SoundId = Config.Sounds.Music }, SoundService)
local superMusic = new("Sound", { Name = "SuperMusic", Looped = true, Volume = 0.4, SoundId = Config.Sounds.SuperMusic }, SoundService)
if Config.Sounds.Music ~= "" then
	music:Play()
end

---------------------------------------------------------------------------
-- Keeping things up to date
---------------------------------------------------------------------------

local function collected()
	local set, count = {}, 0
	for name in string.gmatch(player:GetAttribute("Emeralds") or "", "[^,]+") do
		set[name] = true
		count += 1
	end
	return set, count
end

local function ringCount()
	local stats = player:FindFirstChild("leaderstats")
	local rings = stats and stats:FindFirstChild("Rings")
	return rings and rings.Value or 0
end

local function refreshEmeralds()
	local have = collected()
	for name, slot in pairs(slots) do
		if have[name] then
			slot.frame.BackgroundColor3 = slot.color
			slot.frame.BackgroundTransparency = 0
			slot.stroke.Color = Color3.new(1, 1, 1)
		else
			slot.frame.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
			slot.frame.BackgroundTransparency = 0.3
			slot.stroke.Color = Color3.fromRGB(140, 140, 150)
		end
	end
end

local function refreshQuest()
	local _, count = collected()
	local total = #Config.Emeralds
	local rings = ringCount()
	local super = player:GetAttribute("IsSuper")
	superButton.Visible = false
	if super then
		questText.Text = "SUPER SONIC! Hold jump to fly. Rings are running down!"
		questText.TextColor3 = GOLD
	elseif count < total then
		questText.Text = ("Find the 7 Chaos Emeralds! (%d/%d)  Follow the arrow!"):format(count, total)
		questText.TextColor3 = Color3.new(1, 1, 1)
	elseif rings < Config.Super.RingsNeeded then
		questText.Text = ("All 7 emeralds! Collect %d rings to go Super (%d/%d)"):format(Config.Super.RingsNeeded, rings, Config.Super.RingsNeeded)
		questText.TextColor3 = GOLD
	else
		questText.Text = "Press E or tap GO SUPER to become SUPER SONIC!"
		questText.TextColor3 = GOLD
		superButton.Visible = true
	end
end

local lastRings = 0
local function refreshRings()
	local value = ringCount()
	ringText.Text = tostring(value)
	if value > lastRings then
		ringIcon.Size = UDim2.new(0, 48, 0, 48)
		TweenService:Create(ringIcon, TweenInfo.new(0.2), { Size = UDim2.new(0, 42, 0, 42) }):Play()
	end
	-- Flash red when you have no rings, like the classic games.
	ringText.TextColor3 = value == 0 and Color3.fromRGB(255, 80, 80) or GOLD
	lastRings = value
	refreshQuest()
end

task.spawn(function()
	local stats = player:WaitForChild("leaderstats")
	local rings = stats:WaitForChild("Rings")
	rings.Changed:Connect(refreshRings)
	refreshRings()
end)

player:GetAttributeChangedSignal("Emeralds"):Connect(function()
	refreshEmeralds()
	refreshQuest()
end)
player:GetAttributeChangedSignal("IsSuper"):Connect(refreshQuest)
refreshEmeralds()
refreshQuest()

Remotes.Notify.OnClientEvent:Connect(function(kind, a, b)
	if kind == "Emerald" then
		local color = slots[a] and slots[a].color or Color3.new(1, 1, 1)
		showAnnouncement(("%s CHAOS EMERALD!  (%d/7)"):format(string.upper(a), b), color, 3)
		screenFlash(color)
		playSound(Config.Sounds.Emerald, 0.7)
		local slot = slots[a]
		if slot then
			slot.frame.Size = UDim2.new(0, 46, 0, 46)
			TweenService:Create(slot.frame, TweenInfo.new(0.6, Enum.EasingStyle.Elastic), { Size = UDim2.new(0, 30, 0, 30) }):Play()
		end
	elseif kind == "AllEmeralds" then
		task.delay(3, function()
			showAnnouncement("YOU HAVE ALL 7 CHAOS EMERALDS!", GOLD, 4)
			screenFlash(GOLD)
		end)
	elseif kind == "Super" then
		if a then
			showAnnouncement("SUPER SONIC!", GOLD, 3)
			screenFlash(GOLD)
			if Config.Sounds.SuperMusic ~= "" then
				music:Pause()
				superMusic:Play()
			end
		else
			showAnnouncement("Back to normal", Color3.fromRGB(120, 180, 255), 2)
			superMusic:Stop()
			if Config.Sounds.Music ~= "" then
				music:Resume()
			end
		end
	elseif kind == "Hurt" then
		showAnnouncement(a > 0 and ("Ouch! -%d rings"):format(a) or "Ouch!", Color3.fromRGB(255, 90, 90), 1.5)
		screenFlash(Color3.fromRGB(255, 60, 60))
	elseif kind == "Badnik" then
		showAnnouncement(("Robot smashed! +%d rings"):format(a), Color3.fromRGB(120, 255, 140), 1.5)
	elseif kind == "Message" then
		showAnnouncement(a, Color3.new(1, 1, 1), 2.5)
	end
end)

-- Speed bar, distance to the nearest emerald and the pulsing Super button.
RunService.RenderStepped:Connect(function()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local v = root.AssemblyLinearVelocity
	local horizontal = Vector3.new(v.X, 0, v.Z).Magnitude
	local super = player:GetAttribute("IsSuper")
	local fraction = math.clamp(horizontal / (super and Config.Super.BoostSpeed or Config.Movement.BoostSpeed), 0, 1)
	speedFill.Size = UDim2.new(fraction, 0, 1, 0)
	speedFill.BackgroundColor3 = super and GOLD or Color3.fromRGB(60, 160, 255):Lerp(Color3.fromRGB(255, 80, 200), fraction)

	local have = collected()
	local nearest, nearestName = math.huge, nil
	for _, model in ipairs(EmeraldFolder:GetChildren()) do
		local name = model:GetAttribute("EmeraldName")
		local pos = model:GetAttribute("BasePosition")
		if name and pos and not have[name] then
			local d = (pos - root.Position).Magnitude
			if d < nearest then
				nearest, nearestName = d, name
			end
		end
	end
	distanceText.Text = nearestName and ("%s emerald: %d m away"):format(nearestName, math.floor(nearest / 3.5)) or ""

	if superButton.Visible then
		local pulse = 1 + math.sin(os.clock() * 6) * 0.05
		superButton.Size = UDim2.new(0, 260 * pulse, 0, 70 * pulse)
	end
end)

---------------------------------------------------------------------------
-- Title splash
---------------------------------------------------------------------------

local splash = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(20, 60, 200),
	ZIndex = 20,
}, gui)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(40, 120, 255), Color3.fromRGB(10, 30, 120)),
	Rotation = 90,
}, splash)
local title = label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.new(0.85, 0, 0.18, 0),
	Text = Config.GameName,
	TextScaled = true,
	TextColor3 = GOLD,
	ZIndex = 21,
}, splash)
local subtitle = label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.6),
	Size = UDim2.new(0.7, 0, 0.06, 0),
	Text = "Run fast, grab rings, find the 7 Chaos Emeralds!",
	TextScaled = true,
	ZIndex = 21,
}, splash)

task.delay(2.8, function()
	local info = TweenInfo.new(0.8)
	TweenService:Create(splash, info, { BackgroundTransparency = 1 }):Play()
	for _, l in ipairs({ title, subtitle }) do
		TweenService:Create(l, info, { TextTransparency = 1 }):Play()
		local s = l:FindFirstChildOfClass("UIStroke")
		if s then
			TweenService:Create(s, info, { Transparency = 1 }):Play()
		end
	end
	task.wait(0.9)
	splash:Destroy()
	showAnnouncement("Follow the arrow to the Chaos Emeralds!", Color3.new(1, 1, 1), 3)
end)
