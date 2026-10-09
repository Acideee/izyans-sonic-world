-- Izyan's Sonic World - tuning values shared by the server and the client.
-- Change numbers here to make the game faster, slower, easier or harder.

local Config = {}

Config.GameName = "Izyan's Sonic World"

-- Set to true only if an imported model runs backwards in game: the game will
-- then turn its body around. The models in models/ already face the right way.
Config.TurnImportedModelsAround = false

Config.Movement = {
	StartSpeed = 30, -- speed the moment you start running
	MaxSpeed = 85, -- top running speed (Roblox default walk speed is 16!)
	Acceleration = 26, -- speed gained per second while holding a direction
	Deceleration = 90, -- speed lost per second after letting go
	TurnPenalty = 0.6, -- fraction of speed kept when you turn all the way around
	JumpPower = 65,
	BoostSpeed = 130,
	BoostTime = 1.1,
	BoostCooldown = 1.8,
	AirDashSpeed = 110,
	HomingRange = 70,
	HomingSpeed = 150,
}

Config.Super = {
	RingsNeeded = 50,
	StartSpeed = 60,
	MaxSpeed = 140,
	Acceleration = 60,
	JumpPower = 95,
	BoostSpeed = 200,
	FlySpeed = 55, -- hold jump in the air to fly upwards
	RingDrainPerSecond = 1,
	Color = Color3.fromRGB(255, 214, 40),
	-- The transformation: power up while lifting off, then BAM!, then hover.
	PowerUpTime = 1.8,
	HoverTime = 1.0,
	LiftHeight = 6,
}

Config.Rings = {
	RespawnTime = 25,
	CollectRadius = 5.5,
	SuperMagnetRadius = 14,
	BadnikReward = 5,
	HurtLoss = 10,
}

-- The seven Chaos Emeralds, in the order they appear on the HUD.
Config.Emeralds = {
	{ Name = "Green", Color = Color3.fromRGB(40, 235, 90) },
	{ Name = "Red", Color = Color3.fromRGB(255, 45, 60) },
	{ Name = "Blue", Color = Color3.fromRGB(45, 115, 255) },
	{ Name = "Yellow", Color = Color3.fromRGB(255, 225, 40) },
	{ Name = "Cyan", Color = Color3.fromRGB(70, 235, 255) },
	{ Name = "Purple", Color = Color3.fromRGB(185, 75, 255) },
	{ Name = "White", Color = Color3.fromRGB(240, 245, 255) },
}

-- Built-in Roblox sounds. Swap in your own audio ids ("rbxassetid://123")
-- from the Creator Store if you like. Leave Music empty for no music.
Config.Sounds = {
	Ring = "rbxasset://sounds/electronicpingshort.wav",
	Jump = "rbxasset://sounds/action_jump.mp3",
	Boost = "rbxasset://sounds/action_jump.mp3",
	Spring = "rbxasset://sounds/action_jump.mp3",
	Emerald = "rbxasset://sounds/victory.wav",
	Hurt = "rbxasset://sounds/uuhhh.mp3",
	Badnik = "rbxasset://sounds/electronicpingshort.wav",
	PowerUp = "rbxasset://sounds/electronicpingshort.wav", -- plays faster and higher while charging
	SuperBam = "rbxasset://sounds/action_jump.mp3",
	Music = "",
	SuperMusic = "",
}

return Config
