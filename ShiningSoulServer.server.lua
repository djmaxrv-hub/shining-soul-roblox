--====================================================================
-- Shining Soul-type 3D ARPG for Roblox -- v1 (single-file server)
-- Paste this whole file into ONE Script in ServerScriptService.
-- Everything (map, enemies, tools, HUD, shop, waves) is built and
-- wired up at runtime by this script. No child scripts are used.
--====================================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")

--====================================================================
-- CONFIG
--====================================================================
local TOWN_CENTER = Vector3.new(0, 0, 80)
local DUNGEON_CENTER = Vector3.new(0, 0, -110)
local DUNGEON_HALF_X = 55
local DUNGEON_HALF_Z = 42
local DUNGEON_ENTRANCE = Vector3.new(0, 3, -62)

local SWORD_BASE_DAMAGE = 12
local SWORD_RANGE = 9.5
local SWORD_COOLDOWN = 0.38
local FIREBALL_COST = 20
local FIREBALL_BASE_DAMAGE = 26
local FIREBALL_COOLDOWN = 0.6
local POTION_HEAL = 55
local POTION_PRICE = 30
local MAX_SWORD_TIER = 5
local MAX_MANA = 100

local function xpThreshold(level)
	return 40 + level * 30
end

local function swordUpgradePrice(tier)
	return 150 * tier
end

--====================================================================
-- SMALL HELPERS
--====================================================================
local function makePart(parent, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function makeLabel(parent, name, size, position, text, textSize, color)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = textSize
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	l.TextStrokeTransparency = 0.4
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function horizontalDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function getHRP(character)
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(character)
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

--====================================================================
-- WORLD BUILDING
--====================================================================
Lighting.ClockTime = 15.5
Lighting.Brightness = 2

local mapFolder = Instance.new("Folder")
mapFolder.Name = "ShiningMap"
mapFolder.Parent = Workspace

local enemiesFolder = Instance.new("Folder")
enemiesFolder.Name = "Enemies"
enemiesFolder.Parent = Workspace

local dropsFolder = Instance.new("Folder")
dropsFolder.Name = "Drops"
dropsFolder.Parent = Workspace

local function buildHouse(parent, x, z, wallColor)
	local g = Instance.new("Folder")
	g.Name = "House"
	g.Parent = parent
	makePart(g, "Walls", Vector3.new(14, 8, 12), CFrame.new(x, 4, z),
		wallColor, Enum.Material.Brick)
	local roof = Instance.new("WedgePart")
	roof.Name = "Roof"
	roof.Size = Vector3.new(16, 5, 14)
	roof.CFrame = CFrame.new(x, 10.5, z)
	roof.Color = Color3.fromRGB(140, 60, 50)
	roof.Material = Enum.Material.Slate
	roof.Anchored = true
	roof.Parent = g
	makePart(g, "Door", Vector3.new(3, 5, 0.4), CFrame.new(x, 2.5, z + 6.1),
		Color3.fromRGB(90, 60, 35), Enum.Material.Wood)
end

local function buildTree(parent, x, z)
	makePart(parent, "Trunk", Vector3.new(1.6, 6, 1.6), CFrame.new(x, 3, z),
		Color3.fromRGB(100, 70, 40), Enum.Material.Wood)
	local top = makePart(parent, "Leaves", Vector3.new(7, 7, 7), CFrame.new(x, 9, z),
		Color3.fromRGB(60, 140, 60), Enum.Material.Grass)
	top.Shape = Enum.PartType.Ball
end

local townSpawnCFrame = CFrame.new(TOWN_CENTER.X, 3, TOWN_CENTER.Z + 18)

local function buildTown()
	local town = Instance.new("Folder")
	town.Name = "Town"
	town.Parent = mapFolder

	-- ground
	makePart(town, "Ground", Vector3.new(150, 2, 150),
		CFrame.new(TOWN_CENTER.X, -1, TOWN_CENTER.Z),
		Color3.fromRGB(95, 160, 80), Enum.Material.Grass)
	-- plaza stones
	makePart(town, "Plaza", Vector3.new(46, 0.4, 46),
		CFrame.new(TOWN_CENTER.X, 0.2, TOWN_CENTER.Z),
		Color3.fromRGB(170, 165, 155), Enum.Material.Cobblestone)

	-- spawn pad
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "TownSpawn"
	spawnPad.Size = Vector3.new(10, 1, 10)
	spawnPad.CFrame = CFrame.new(TOWN_CENTER.X, 0.5, TOWN_CENTER.Z + 18)
	spawnPad.Color = Color3.fromRGB(80, 200, 255)
	spawnPad.Material = Enum.Material.Neon
	spawnPad.Anchored = true
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	spawnPad.Parent = town

	-- fountain (cylinder basin + water + pillar)
	local basin = makePart(town, "FountainBasin", Vector3.new(12, 2, 12),
		CFrame.new(TOWN_CENTER.X, 1, TOWN_CENTER.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(150, 150, 150), Enum.Material.Marble)
	basin.Shape = Enum.PartType.Cylinder
	local water = makePart(town, "FountainWater", Vector3.new(10, 0.6, 10),
		CFrame.new(TOWN_CENTER.X, 2, TOWN_CENTER.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(70, 160, 255), Enum.Material.Glass)
	water.Shape = Enum.PartType.Cylinder
	water.Transparency = 0.35
	makePart(town, "FountainPillar", Vector3.new(2, 5, 2),
		CFrame.new(TOWN_CENTER.X, 2.5, TOWN_CENTER.Z),
		Color3.fromRGB(150, 150, 150), Enum.Material.Marble)

	-- houses + trees
	buildHouse(town, -32, TOWN_CENTER.Z + 26, Color3.fromRGB(200, 180, 150))
	buildHouse(town, 32, TOWN_CENTER.Z + 26, Color3.fromRGB(180, 160, 190))
	buildHouse(town, -36, TOWN_CENTER.Z - 22, Color3.fromRGB(170, 190, 170))
	buildHouse(town, 36, TOWN_CENTER.Z - 22, Color3.fromRGB(200, 170, 140))
	buildTree(town, -18, TOWN_CENTER.Z + 34)
	buildTree(town, 18, TOWN_CENTER.Z + 34)
	buildTree(town, -52, TOWN_CENTER.Z + 4)
	buildTree(town, 52, TOWN_CENTER.Z + 4)
	buildTree(town, -14, TOWN_CENTER.Z - 34)
	buildTree(town, 14, TOWN_CENTER.Z - 34)

	return town
end

-- Merchant stand + shop prompt anchor parts (prompts wired up later)
local potionStandPart = nil
local upgradeStandPart = nil

local function buildMerchant(town)
	local stand = Instance.new("Folder")
	stand.Name = "Merchant"
	stand.Parent = town
	local mx, mz = -10, TOWN_CENTER.Z - 6

	makePart(stand, "Counter", Vector3.new(12, 3, 3), CFrame.new(mx, 1.5, mz),
		Color3.fromRGB(120, 85, 50), Enum.Material.Wood)
	makePart(stand, "Awning", Vector3.new(14, 0.4, 6), CFrame.new(mx, 7, mz),
		Color3.fromRGB(200, 60, 60), Enum.Material.Fabric)
	-- simple merchant dummy (anchored decorative parts)
	makePart(stand, "MerchantBody", Vector3.new(2.4, 3, 1.2), CFrame.new(mx, 4.5, mz - 2.5),
		Color3.fromRGB(60, 90, 200), Enum.Material.SmoothPlastic)
	local head = makePart(stand, "MerchantHead", Vector3.new(1.8, 1.8, 1.8),
		CFrame.new(mx, 7, mz - 2.5), Color3.fromRGB(240, 200, 160), Enum.Material.SmoothPlastic)
	head.Shape = Enum.PartType.Ball

	potionStandPart = makePart(stand, "PotionStand", Vector3.new(3, 2, 3),
		CFrame.new(mx - 4, 1, mz + 4), Color3.fromRGB(220, 60, 80), Enum.Material.SmoothPlastic)
	upgradeStandPart = makePart(stand, "UpgradeStand", Vector3.new(3, 2, 3),
		CFrame.new(mx + 4, 1, mz + 4), Color3.fromRGB(255, 190, 60), Enum.Material.SmoothPlastic)

	local sign = makePart(stand, "Sign", Vector3.new(10, 2.4, 0.3), CFrame.new(mx, 9.5, mz),
		Color3.fromRGB(90, 60, 35), Enum.Material.Wood)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = sign
	local tl = makeLabel(gui, "SignText", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
		"SHOP", 28, Color3.fromRGB(255, 230, 150))
	tl.TextXAlignment = Enum.TextXAlignment.Center
end

local function buildDungeon()
	local dg = Instance.new("Folder")
	dg.Name = "Dungeon"
	dg.Parent = mapFolder
	local cx, cz = DUNGEON_CENTER.X, DUNGEON_CENTER.Z
	local wallColor = Color3.fromRGB(90, 90, 100)
	local wallMat = Enum.Material.Slate

	makePart(dg, "Floor", Vector3.new(DUNGEON_HALF_X * 2 + 10, 2, DUNGEON_HALF_Z * 2 + 10),
		CFrame.new(cx, -1, cz), Color3.fromRGB(70, 68, 78), Enum.Material.Cobblestone)
	-- walls (height 12)
	makePart(dg, "WallN", Vector3.new(DUNGEON_HALF_X * 2 + 10, 12, 2),
		CFrame.new(cx, 6, cz - DUNGEON_HALF_Z - 1), wallColor, wallMat)
	makePart(dg, "WallS", Vector3.new(DUNGEON_HALF_X * 2 + 10, 12, 2),
		CFrame.new(cx, 6, cz + DUNGEON_HALF_Z + 1), wallColor, wallMat)
	makePart(dg, "WallW", Vector3.new(2, 12, DUNGEON_HALF_Z * 2 + 10),
		CFrame.new(cx - DUNGEON_HALF_X - 1, 6, cz), wallColor, wallMat)
	makePart(dg, "WallE", Vector3.new(2, 12, DUNGEON_HALF_Z * 2 + 10),
		CFrame.new(cx + DUNGEON_HALF_X + 1, 6, cz), wallColor, wallMat)
	-- pillars
	for _, px in ipairs({-30, 0, 30}) do
		for _, pz in ipairs({-25, 15}) do
			makePart(dg, "Pillar", Vector3.new(4, 11, 4),
				CFrame.new(cx + px, 5.5, cz + pz), wallColor, wallMat)
		end
	end
	-- torches with real light
	local torchSpots = {
		{-DUNGEON_HALF_X + 3, -DUNGEON_HALF_Z + 3}, {DUNGEON_HALF_X - 3, -DUNGEON_HALF_Z + 3},
		{-DUNGEON_HALF_X + 3, DUNGEON_HALF_Z - 3}, {DUNGEON_HALF_X - 3, DUNGEON_HALF_Z - 3},
		{0, -DUNGEON_HALF_Z + 3}, {0, DUNGEON_HALF_Z - 3},
	}
	for _, s in ipairs(torchSpots) do
		local tx, tz = cx + s[1], cz + s[2]
		makePart(dg, "TorchPole", Vector3.new(0.6, 5, 0.6), CFrame.new(tx, 2.5, tz),
			Color3.fromRGB(90, 60, 35), Enum.Material.Wood)
		local flame = makePart(dg, "TorchFlame", Vector3.new(1.4, 1.8, 1.4),
			CFrame.new(tx, 5.8, tz), Color3.fromRGB(255, 160, 50), Enum.Material.Neon)
		flame.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 80)
		light.Range = 26
		light.Brightness = 2
		light.Parent = flame
	end
	return dg
end

-- Portals (Touched handlers wired up later, after player logic exists)
local portalToDungeon = nil
local portalToTown = nil

local function buildPortals(town, dg)
	portalToDungeon = makePart(town, "PortalToDungeon", Vector3.new(7, 9, 1),
		CFrame.new(TOWN_CENTER.X, 4.5, TOWN_CENTER.Z - 48),
		Color3.fromRGB(160, 60, 255), Enum.Material.Neon)
	portalToDungeon.CanCollide = false
	portalToDungeon.Transparency = 0.25

	portalToTown = makePart(dg, "PortalToTown", Vector3.new(7, 9, 1),
		CFrame.new(DUNGEON_CENTER.X, 4.5, DUNGEON_CENTER.Z + DUNGEON_HALF_Z - 3),
		Color3.fromRGB(60, 200, 255), Enum.Material.Neon)
	portalToTown.CanCollide = false
	portalToTown.Transparency = 0.25
end

local townFolder = buildTown()
buildMerchant(townFolder)
local dungeonFolder = buildDungeon()
buildPortals(townFolder, dungeonFolder)

local function inDungeon(pos)
	return math.abs(pos.X - DUNGEON_CENTER.X) <= DUNGEON_HALF_X + 8
		and math.abs(pos.Z - DUNGEON_CENTER.Z) <= DUNGEON_HALF_Z + 8
end

--====================================================================
-- PLAYER DATA + HUD
--====================================================================
local lastAction = {}   -- [player] = {sword=0, fire=0, potion=0, teleport=0}
local announcement = ""
local announcementUntil = 0
local currentWave = 0
local waveStatus = "Enter the purple portal to start Wave 1!"

local function announce(text, seconds)
	announcement = text
	announcementUntil = os.clock() + (seconds or 3)
end

local function getStat(player, folderName, statName)
	local folder = player:FindFirstChild(folderName)
	if not folder then return nil end
	return folder:FindFirstChild(statName)
end

local function addXP(player, amount)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then return end
	local level = stats:FindFirstChild("Level")
	local xp = stats:FindFirstChild("XP")
	if not level or not xp then return end
	xp.Value = xp.Value + amount
	while xp.Value >= xpThreshold(level.Value) do
		xp.Value = xp.Value - xpThreshold(level.Value)
		level.Value = level.Value + 1
		local character = player.Character
		local humanoid = getHumanoid(character)
		if humanoid then
			humanoid.MaxHealth = 100 + (level.Value - 1) * 20
			humanoid.Health = humanoid.MaxHealth
		end
		announce(player.Name .. " reached Level " .. level.Value .. "!", 3)
	end
end

local function addGold(player, amount)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then return end
	local gold = stats:FindFirstChild("Gold")
	if gold then gold.Value = gold.Value + amount end
end

local function buildHUD(player)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShiningHUD"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Size = UDim2.new(0, 240, 0, 138)
	frame.Position = UDim2.new(0, 12, 0, 12)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = gui

	makeLabel(frame, "LevelLabel", UDim2.new(1, -12, 0, 24), UDim2.new(0, 8, 0, 4), "Level 1", 18)
	makeLabel(frame, "XPLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 28), "XP 0", 14,
		Color3.fromRGB(180, 220, 255))
	makeLabel(frame, "GoldLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 50), "Gold 0", 14,
		Color3.fromRGB(255, 215, 90))
	makeLabel(frame, "ManaLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 72), "Mana 100", 14,
		Color3.fromRGB(120, 180, 255))
	makeLabel(frame, "PotionLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 94), "Potions 3", 14,
		Color3.fromRGB(255, 140, 160))
	makeLabel(frame, "WaveLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 116), "", 14,
		Color3.fromRGB(200, 255, 200))

	local banner = makeLabel(gui, "Banner", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 60), "", 30,
		Color3.fromRGB(255, 230, 120))
	banner.TextXAlignment = Enum.TextXAlignment.Center
	return gui
end

local function updateHUD(player)
	local gui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("ShiningHUD")
	if not gui then return end
	local panel = gui:FindFirstChild("Panel")
	if not panel then return end
	local level = getStat(player, "leaderstats", "Level")
	local xp = getStat(player, "leaderstats", "XP")
	local gold = getStat(player, "leaderstats", "Gold")
	local mana = getStat(player, "Stats", "Mana")
	local potions = getStat(player, "Stats", "Potions")
	if level then panel.LevelLabel.Text = "Level " .. level.Value end
	if xp and level then
		panel.XPLabel.Text = "XP " .. xp.Value .. " / " .. xpThreshold(level.Value)
	end
	if gold then panel.GoldLabel.Text = "Gold " .. gold.Value end
	if mana then panel.ManaLabel.Text = "Mana " .. mana.Value .. " / " .. MAX_MANA end
	if potions then panel.PotionLabel.Text = "Potions " .. potions.Value end
	panel.WaveLabel.Text = waveStatus
	local banner = gui:FindFirstChild("Banner")
	if banner then
		banner.Text = (os.clock() < announcementUntil) and announcement or ""
	end
end

--====================================================================
-- ENEMIES (defined before tools: tools damage enemies)
--====================================================================
local ENEMY_TYPES = {
	Slime = {
		health = 35, damage = 6, speed = 9, xp = 18, gold = 10,
		scale = 1, bodyColor = Color3.fromRGB(70, 220, 90), headColor = Color3.fromRGB(70, 220, 90),
	},
	Goblin = {
		health = 60, damage = 10, speed = 13, xp = 30, gold = 18,
		scale = 0.95, bodyColor = Color3.fromRGB(90, 150, 60), headColor = Color3.fromRGB(120, 190, 80),
	},
	Skeleton = {
		health = 85, damage = 14, speed = 11, xp = 45, gold = 26,
		scale = 1.05, bodyColor = Color3.fromRGB(225, 225, 215), headColor = Color3.fromRGB(240, 240, 230),
	},
	SkeletonKing = {
		health = 650, damage = 24, speed = 10, xp = 300, gold = 250,
		scale = 2.3, bodyColor = Color3.fromRGB(200, 200, 190), headColor = Color3.fromRGB(255, 215, 90),
	},
}

local enemies = {} -- [model] = data table

local function weldTo(part, root)
	part.Anchored = false
	part.CanCollide = false
	part.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = part
	w.Parent = part
end

local function buildEnemyVisual(model, root, kind, def)
	local s = def.scale
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2.2 * s, 2.6 * s, 1.2 * s)
	body.Color = def.bodyColor
	body.Material = Enum.Material.SmoothPlastic
	body.CFrame = root.CFrame * CFrame.new(0, 0.4 * s, 0)
	body.Parent = model
	weldTo(body, root)
	if kind == "Slime" then
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.new(3 * s, 2.4 * s, 3 * s)
		body.Transparency = 0.2
	end
	local head = Instance.new("Part")
	head.Name = "HeadVisual"
	head.Size = Vector3.new(1.6 * s, 1.4 * s, 1.4 * s)
	head.Color = def.headColor
	head.Material = Enum.Material.SmoothPlastic
	head.CFrame = root.CFrame * CFrame.new(0, (2.4 * s), 0)
	head.Parent = model
	if kind ~= "Slime" then
		weldTo(head, root)
	else
		head:Destroy() -- slime is just a blob
	end
	-- eyes (front = -Z of root look direction is +Z for models; use -Z face)
	for _, ex in ipairs({-0.4, 0.4}) do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Size = Vector3.new(0.28 * s, 0.28 * s, 0.1)
		eye.Color = Color3.fromRGB(20, 20, 20)
		eye.Material = Enum.Material.Neon
		local yOff = (kind == "Slime") and (0.5 * s) or (2.5 * s)
		local zOff = (kind == "Slime") and (-1.45 * s) or (-0.75 * s)
		eye.CFrame = root.CFrame * CFrame.new(ex * s, yOff, zOff)
		eye.Parent = model
		weldTo(eye, root)
	end
end

local function makeHealthBar(model, root, displayName)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.new(4, 0, 0.6, 0)
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.AlwaysOnTop = true
	gui.Parent = root
	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.fromScale(1, 0.45)
	bg.Position = UDim2.fromScale(0, 0.55)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(70, 220, 80)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local nameLabel = makeLabel(gui, "NameLabel", UDim2.fromScale(1, 0.55), UDim2.fromScale(0, 0),
		displayName, 14, Color3.fromRGB(255, 255, 255))
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	return gui
end

local function refreshHealthBar(model)
	local data = enemies[model]
	if not data then return end
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return end
	local gui = root:FindFirstChild("HealthBar")
	if gui and gui:FindFirstChild("BG") and gui.BG:FindFirstChild("Fill") then
		local frac = 0
		if humanoid.MaxHealth > 0 then
			frac = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		end
		gui.BG.Fill.Size = UDim2.fromScale(frac, 1)
	end
end

--====================================================================
-- DROPS + ENEMY SPAWNING / DEATH
--====================================================================
local function spawnPickup(kind, position)
	local p = Instance.new("Part")
	p.Name = kind
	p.Size = Vector3.new(1.4, 1.4, 1.4)
	p.Shape = Enum.PartType.Ball
	p.Position = position + Vector3.new(0, 1, 0)
	p.Anchored = true
	p.CanCollide = false
	p.Material = Enum.Material.Neon
	p.Color = (kind == "PotionPickup") and Color3.fromRGB(255, 80, 110)
		or Color3.fromRGB(90, 255, 140)
	p.Parent = dropsFolder
	Debris:AddItem(p, 30)
	p.Touched:Connect(function(hit)
		local character = hit and hit.Parent
		local humanoid = getHumanoid(character)
		if not humanoid or humanoid.Health <= 0 then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		if kind == "PotionPickup" then
			local potions = getStat(player, "Stats", "Potions")
			if potions then potions.Value = potions.Value + 1 end
		else
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 35)
		end
		p:Destroy()
	end)
end

local function onEnemyDeath(model, data)
	enemies[model] = nil
	local killer = nil
	if data.lastDamager then
		killer = Players:GetPlayerByUserId(data.lastDamager)
	end
	if killer then
		addXP(killer, data.xp)
		addGold(killer, data.gold)
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		local roll = math.random()
		if roll < 0.25 then
			spawnPickup("PotionPickup", root.Position)
		elseif roll < 0.45 then
			spawnPickup("HealOrb", root.Position)
		end
	end
end

local function damageEnemy(model, amount, attacker, knockbackDir)
	local data = enemies[model]
	if not data then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	if attacker then data.lastDamager = attacker.UserId end
	humanoid:TakeDamage(amount)
	if knockbackDir then
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			pcall(function()
				root.AssemblyLinearVelocity = Vector3.new(
					knockbackDir.X * 26, 12, knockbackDir.Z * 26)
			end)
		end
	end
	refreshHealthBar(model)
end

local function spawnEnemy(kind, position, difficultyScale)
	local def = ENEMY_TYPES[kind]
	if not def then return nil end
	difficultyScale = difficultyScale or 1
	local model = Instance.new("Model")
	model.Name = kind
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(position.X, position.Y + 2.2, position.Z)
	root.Color = def.bodyColor
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = math.floor(def.health * difficultyScale)
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = def.speed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model
	model.PrimaryPart = root
	model.Parent = enemiesFolder
	buildEnemyVisual(model, root, kind, def)
	makeHealthBar(model, root, (kind == "SkeletonKing") and "BOSS: Skeleton King" or kind)
	local data = {
		kind = kind,
		damage = math.floor(def.damage * (0.8 + 0.2 * difficultyScale)),
		speed = def.speed,
		xp = def.xp,
		gold = def.gold,
		lastAttack = 0,
		lastDamager = nil,
		isBoss = (kind == "SkeletonKing"),
	}
	enemies[model] = data
	humanoid.Died:Connect(function()
		onEnemyDeath(model, data)
		task.wait(0.4)
		model:Destroy()
	end)
	refreshHealthBar(model)
	return model
end

--====================================================================
-- WAVE SYSTEM
--====================================================================
local waveActive = false
local waveCycle = 0 -- +1 every time wave 5 boss is cleared; scales difficulty

local function playersInDungeon()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local hrp = getHRP(player.Character)
		if hrp and inDungeon(hrp.Position) then
			table.insert(list, player)
		end
	end
	return list
end

local function aliveEnemyCount()
	local n = 0
	for _ in pairs(enemies) do n = n + 1 end
	return n
end

local function dungeonSpawnPosition()
	local x = DUNGEON_CENTER.X + math.random(-DUNGEON_HALF_X + 8, DUNGEON_HALF_X - 8)
	local z = DUNGEON_CENTER.Z + math.random(-DUNGEON_HALF_Z + 8, DUNGEON_HALF_Z - 14)
	return Vector3.new(x, 0, z)
end

local function startWave(wave)
	waveActive = true
	currentWave = wave
	local scale = 1 + (wave - 1) * 0.12 + waveCycle * 0.35
	local isBossWave = (wave % 5 == 0)
	if isBossWave then
		spawnEnemy("SkeletonKing", Vector3.new(DUNGEON_CENTER.X, 0, DUNGEON_CENTER.Z - 10), scale)
		for _ = 1, 3 do spawnEnemy("Skeleton", dungeonSpawnPosition(), scale) end
		announce("Wave " .. wave .. " -- BOSS!", 4)
	else
		local count = math.min(3 + wave * 2, 14)
		for i = 1, count do
			local kind = "Slime"
			local r = math.random()
			if wave >= 3 and r < 0.3 then
				kind = "Skeleton"
			elseif wave >= 2 and r < 0.65 then
				kind = "Goblin"
			end
			spawnEnemy(kind, dungeonSpawnPosition(), scale)
		end
		announce("Wave " .. wave .. "!", 3)
	end
	waveStatus = "Wave " .. wave .. " -- enemies left: " .. aliveEnemyCount()
end

local function waveLoop()
	while true do
		task.wait(0.5)
		local inside = playersInDungeon()
		if waveActive then
			local left = aliveEnemyCount()
			waveStatus = "Wave " .. currentWave .. " -- enemies left: " .. left
			if left <= 0 then
				waveActive = false
				local bonus = 20 + currentWave * 10
				for _, player in ipairs(inside) do
					addGold(player, bonus)
				end
				if currentWave % 5 == 0 then
					waveCycle = waveCycle + 1
					announce("BOSS DOWN! Bonus " .. bonus .. " gold. Dungeon grows stronger...", 5)
				else
					announce("Wave " .. currentWave .. " cleared! Bonus " .. bonus .. " gold.", 4)
				end
				currentWave = currentWave + 1
				waveStatus = "Next wave in 5s... (Wave " .. currentWave .. ")"
				task.wait(5)
			end
		else
			if #inside > 0 then
				if currentWave == 0 then currentWave = 1 end
				startWave(currentWave)
			else
				waveStatus = "Enter the purple portal to fight! (Next: Wave "
					.. math.max(currentWave, 1) .. ")"
			end
		end
	end
end

--====================================================================
-- ENEMY AI LOOP
--====================================================================
local function aiLoop()
	while true do
		task.wait(0.25)
		for model, data in pairs(enemies) do
			local root = model:FindFirstChild("HumanoidRootPart")
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				-- find nearest living player
				local bestPlayer, bestDist = nil, 90
				for _, player in ipairs(Players:GetPlayers()) do
					local phrp = getHRP(player.Character)
					local phum = getHumanoid(player.Character)
					if phrp and phum and phum.Health > 0 then
						local d = horizontalDistance(root.Position, phrp.Position)
						if d < bestDist then
							bestDist = d
							bestPlayer = player
						end
					end
				end
				if bestPlayer then
					local phrp = getHRP(bestPlayer.Character)
					local phum = getHumanoid(bestPlayer.Character)
					local reach = data.isBoss and 6 or 4
					if bestDist > reach then
						humanoid:MoveTo(phrp.Position)
					else
						humanoid:MoveTo(root.Position)
						local now = os.clock()
						if now - data.lastAttack >= 1.1 then
							data.lastAttack = now
							phum:TakeDamage(data.damage)
						end
					end
				else
					humanoid:MoveTo(root.Position)
				end
			end
		end
	end
end

--====================================================================
-- TOOLS (all Activated events connected here, centrally)
--====================================================================
local TIER_COLORS = {
	Color3.fromRGB(170, 170, 180),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(120, 255, 140),
	Color3.fromRGB(255, 190, 60),
	Color3.fromRGB(255, 90, 200),
}

local function styleSword(tool, tier)
	local handle = tool:FindFirstChild("Handle")
	if handle then
		handle.Color = TIER_COLORS[math.clamp(tier, 1, MAX_SWORD_TIER)]
	end
	tool.Name = "Sword (Tier " .. tier .. ")"
end

local function createSword(player)
	local tool = Instance.new("Tool")
	tool.Name = "Sword (Tier 1)"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 4.2, 0.9)
	handle.Color = TIER_COLORS[1]
	handle.Material = Enum.Material.Metal
	handle.Parent = tool
	tool.Activated:Connect(function()
		local now = os.clock()
		local rec = lastAction[player]
		if not rec or (now - (rec.sword or 0)) < SWORD_COOLDOWN then return end
		rec.sword = now
		local character = player.Character
		local hrp = getHRP(character)
		if not hrp then return end
		local level = getStat(player, "leaderstats", "Level")
		local tier = getStat(player, "Stats", "SwordTier")
		local dmg = SWORD_BASE_DAMAGE
			+ ((level and level.Value or 1) - 1) * 2
			+ ((tier and tier.Value or 1) - 1) * 8
		-- AUTO-LOCK: turn to face the nearest enemy and step into range,
		-- so a click always connects. No manual aiming, no facing check.
		local nearest, nearestDist = nil, 18
		for model, _ in pairs(enemies) do
			local eroot = model:FindFirstChild("HumanoidRootPart")
			if eroot then
				local d = horizontalDistance(hrp.Position, eroot.Position)
				if d < nearestDist then
					nearestDist = d
					nearest = model
				end
			end
		end
		if nearest then
			local eroot = nearest:FindFirstChild("HumanoidRootPart")
			if eroot then
				local flat = Vector3.new(eroot.Position.X, hrp.Position.Y, eroot.Position.Z)
				local offset = flat - hrp.Position
				if offset.Magnitude > 0.5 then
					hrp.CFrame = CFrame.lookAt(hrp.Position, flat)
					if nearestDist > SWORD_RANGE then
						hrp.CFrame = hrp.CFrame
							+ offset.Unit * math.min(nearestDist - SWORD_RANGE + 2, 6)
					end
				end
			end
		end
		-- Full 360-degree sweep around the player: anything in range is hit.
		for model, _ in pairs(enemies) do
			local eroot = model:FindFirstChild("HumanoidRootPart")
			if eroot then
				local toEnemy = eroot.Position - hrp.Position
				local dist = horizontalDistance(hrp.Position, eroot.Position)
				if dist <= SWORD_RANGE + 1.5 and toEnemy.Magnitude > 0.1 then
					damageEnemy(model, dmg, player, toEnemy.Unit)
				end
			end
		end
	end)
	return tool
end

local function createFireballTool(player)
	local tool = Instance.new("Tool")
	tool.Name = "Fireball (20 Mana)"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.8, 0.8, 2.4)
	handle.Color = Color3.fromRGB(255, 120, 40)
	handle.Material = Enum.Material.Neon
	handle.Parent = tool
	tool.Activated:Connect(function()
		local now = os.clock()
		local rec = lastAction[player]
		if not rec or (now - (rec.fire or 0)) < FIREBALL_COOLDOWN then return end
		local mana = getStat(player, "Stats", "Mana")
		if not mana or mana.Value < FIREBALL_COST then return end
		local character = player.Character
		local hrp = getHRP(character)
		if not hrp then return end
		rec.fire = now
		mana.Value = mana.Value - FIREBALL_COST
		local level = getStat(player, "leaderstats", "Level")
		local dmg = FIREBALL_BASE_DAMAGE + ((level and level.Value or 1) - 1) * 3
		-- AUTO-AIM: lock onto the nearest enemy in range. The fireball
		-- homes in on it, so the player never aims manually.
		local target, targetDist = nil, 80
		for model, _ in pairs(enemies) do
			local eroot = model:FindFirstChild("HumanoidRootPart")
			if eroot then
				local d = horizontalDistance(hrp.Position, eroot.Position)
				if d < targetDist then
					targetDist = d
					target = model
				end
			end
		end
		local ball = Instance.new("Part")
		ball.Name = "FireballProjectile"
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(1.4, 1.4, 1.4)
		ball.Color = Color3.fromRGB(255, 130, 40)
		ball.Material = Enum.Material.Neon
		ball.CanCollide = false
		ball.Position = hrp.Position + hrp.CFrame.LookVector * 4 + Vector3.new(0, 1, 0)
		ball.Parent = Workspace
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 150, 60)
		light.Range = 12
		light.Brightness = 2
		light.Parent = ball
		local aimDir = hrp.CFrame.LookVector
		if target then
			local eroot = target:FindFirstChild("HumanoidRootPart")
			if eroot then
				local toTarget = (eroot.Position + Vector3.new(0, 1.5, 0)) - ball.Position
				if toTarget.Magnitude > 0.1 then aimDir = toTarget.Unit end
			end
		end
		ball.AssemblyLinearVelocity = aimDir * 75
		Debris:AddItem(ball, 2.5)
		if target then
			task.spawn(function()
				local started = os.clock()
				while ball.Parent and os.clock() - started < 2.5 do
					if not enemies[target] then break end
					local eroot = target:FindFirstChild("HumanoidRootPart")
					if not eroot then break end
					local toTarget = (eroot.Position + Vector3.new(0, 1.5, 0)) - ball.Position
					if toTarget.Magnitude > 0.1 then
						ball.AssemblyLinearVelocity = toTarget.Unit * 75
					end
					task.wait(0.03)
				end
			end)
		end
		local hitDone = false
		ball.Touched:Connect(function(hit)
			if hitDone then return end
			if hit and character and hit:IsDescendantOf(character) then return end
			local model = hit and hit.Parent
			if model and model.Parent == enemiesFolder and enemies[model] then
				hitDone = true
				damageEnemy(model, dmg, player, hrp.CFrame.LookVector)
				ball:Destroy()
			elseif hit and hit.Anchored then
				hitDone = true
				ball:Destroy()
			end
		end)
	end)
	return tool
end

local function createPotionTool(player)
	local tool = Instance.new("Tool")
	tool.Name = "Drink Potion"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.7, 1.1, 0.7)
	handle.Color = Color3.fromRGB(255, 80, 110)
	handle.Material = Enum.Material.Glass
	handle.Parent = tool
	tool.Activated:Connect(function()
		local now = os.clock()
		local rec = lastAction[player]
		if not rec or (now - (rec.potion or 0)) < 0.8 then return end
		local potions = getStat(player, "Stats", "Potions")
		local humanoid = getHumanoid(player.Character)
		if not potions or not humanoid then return end
		if potions.Value <= 0 or humanoid.Health >= humanoid.MaxHealth then return end
		rec.potion = now
		potions.Value = potions.Value - 1
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + POTION_HEAL)
	end)
	return tool
end

--====================================================================
-- SHOP PROMPTS
--====================================================================
local function setupShop()
	local potionPrompt = Instance.new("ProximityPrompt")
	potionPrompt.ActionText = "Buy Potion (" .. POTION_PRICE .. " Gold)"
	potionPrompt.ObjectText = "Potion Shop"
	potionPrompt.HoldDuration = 0
	potionPrompt.MaxActivationDistance = 12
	potionPrompt.Parent = potionStandPart
	potionPrompt.Triggered:Connect(function(player)
		local gold = getStat(player, "leaderstats", "Gold")
		local potions = getStat(player, "Stats", "Potions")
		if gold and potions and gold.Value >= POTION_PRICE then
			gold.Value = gold.Value - POTION_PRICE
			potions.Value = potions.Value + 1
			announce(player.Name .. " bought a potion.", 2)
		else
			announce("Not enough gold for a potion!", 2)
		end
	end)

	local upgradePrompt = Instance.new("ProximityPrompt")
	upgradePrompt.ActionText = "Upgrade Sword"
	upgradePrompt.ObjectText = "Blacksmith"
	upgradePrompt.HoldDuration = 0
	upgradePrompt.MaxActivationDistance = 12
	upgradePrompt.Parent = upgradeStandPart
	upgradePrompt.Triggered:Connect(function(player)
		local tier = getStat(player, "Stats", "SwordTier")
		local gold = getStat(player, "leaderstats", "Gold")
		if not tier or not gold then return end
		if tier.Value >= MAX_SWORD_TIER then
			announce("Sword is already max tier!", 2)
			return
		end
		local price = swordUpgradePrice(tier.Value)
		upgradePrompt.ActionText = "Upgrade Sword (" .. price .. " Gold)"
		if gold.Value >= price then
			gold.Value = gold.Value - price
			tier.Value = tier.Value + 1
			-- restyle sword wherever it currently is
			local backpack = player:FindFirstChild("Backpack")
			if backpack then
				for _, t in ipairs(backpack:GetChildren()) do
					if t:IsA("Tool") and string.find(t.Name, "Sword") then styleSword(t, tier.Value) end
				end
			end
			if player.Character then
				for _, t in ipairs(player.Character:GetChildren()) do
					if t:IsA("Tool") and string.find(t.Name, "Sword") then styleSword(t, tier.Value) end
				end
			end
			announce(player.Name .. " upgraded sword to Tier " .. tier.Value .. "!", 3)
		else
			announce("Need " .. price .. " gold to upgrade!", 2)
		end
	end)
end
setupShop()

--====================================================================
-- PORTALS
--====================================================================
local function setupPortal(part, destination)
	part.Touched:Connect(function(hit)
		local character = hit and hit.Parent
		if not getHumanoid(character) then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		local rec = lastAction[player]
		local now = os.clock()
		if rec and (now - (rec.teleport or 0)) < 1.5 then return end
		if rec then rec.teleport = now end
		local hrp = getHRP(character)
		if hrp then
			hrp.CFrame = CFrame.new(destination)
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
	end)
end
setupPortal(portalToDungeon, DUNGEON_ENTRANCE + Vector3.new(0, 0, -12))
setupPortal(portalToTown, TOWN_CENTER + Vector3.new(0, 3, -30))

--====================================================================
-- PLAYER LIFECYCLE
--====================================================================
-- Tools must be (re)given AFTER the character spawns: tools put in the
-- Backpack during PlayerAdded can be wiped when the first spawn resets
-- the Backpack to StarterPack contents, and an equipped tool is lost
-- on death. ensureTools runs on every CharacterAdded and only creates
-- the tools that are actually missing.
local function ensureTools(player)
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end
	local character = player.Character
	local function hasTool(prefix)
		for _, container in ipairs({ backpack, character }) do
			if container then
				for _, item in ipairs(container:GetChildren()) do
					if item:IsA("Tool") and string.find(item.Name, prefix, 1, true) then
						return true
					end
				end
			end
		end
		return false
	end
	if not hasTool("Sword") then createSword(player).Parent = backpack end
	if not hasTool("Fireball") then createFireballTool(player).Parent = backpack end
	if not hasTool("Drink Potion") then createPotionTool(player).Parent = backpack end
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local level = getStat(player, "leaderstats", "Level")
	if humanoid and level then
		humanoid.MaxHealth = 100 + (level.Value - 1) * 20
		humanoid.Health = humanoid.MaxHealth
	end
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if hrp then
		task.wait(0.2)
		hrp.CFrame = townSpawnCFrame
	end
	ensureTools(player)
end

local function onPlayerAdded(player)
	lastAction[player] = { sword = 0, fire = 0, potion = 0, teleport = 0 }

	local function makeInt(parent, name, value)
		local v = Instance.new("IntValue")
		v.Name = name
		v.Value = value
		v.Parent = parent
		return v
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	makeInt(leaderstats, "Level", 1)
	makeInt(leaderstats, "XP", 0)
	makeInt(leaderstats, "Gold", 50)
	leaderstats.Parent = player

	local stats = Instance.new("Folder")
	stats.Name = "Stats"
	makeInt(stats, "Mana", MAX_MANA)
	makeInt(stats, "Potions", 3)
	makeInt(stats, "SwordTier", 1)
	stats.Parent = player

	buildHUD(player)

	local backpack = player:WaitForChild("Backpack")
	createSword(player).Parent = backpack
	createFireballTool(player).Parent = backpack
	createPotionTool(player).Parent = backpack

	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerRemoving:Connect(function(player)
	lastAction[player] = nil
end)

--====================================================================
-- MAIN LOOPS: mana regen + HUD refresh, enemy AI, waves
--====================================================================
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			local mana = getStat(player, "Stats", "Mana")
			if mana and mana.Value < MAX_MANA then
				mana.Value = math.min(MAX_MANA, mana.Value + 4)
			end
			pcall(updateHUD, player)
		end
	end
end)
task.spawn(aiLoop)
task.spawn(waveLoop)

print("[ShiningSoul] v1 server started: town + dungeon + waves ready.")
