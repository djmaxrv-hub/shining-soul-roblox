--====================================================================
-- Shining Soul-type 3D ARPG for Roblox -- v3 (single-file server)
-- Paste this whole file into ONE Script in ServerScriptService.
-- Everything (map, enemies, tools, HUD, shop, waves) is built and
-- wired up at runtime by this script. No child scripts are used.
-- v2: damage numbers + hit flash, elite enemies, gear drops
--     (Armor / Power), DataStore saving.
-- v3: art pass -- modeled weapons (sword / staff / potion bottle),
--     slash arc + hit sparks + corpse bursts, modeled enemies
--     (bouncing slime, goblin, ribbed skeleton, crowned king),
--     designed town (plaza, paths, stalls, lamps, fence) and
--     dungeon (checkerboard floor, torches, props), dusk lighting.
--     Terrain: town is a fenced safe zone; the dungeon has two
--     healing CAMPFIRES (parts named "Campfire" under the Dungeon
--     folder), cover pillars / low walls, an entrance corridor
--     choke point, one LAVA pool (part named "LavaPool") that
--     burns players, and a raised platform with steps. A single
--     0.5s zone loop heals at campfires and burns in lava.
--====================================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local DataStoreService = game:GetService("DataStoreService")

-- DataStore (all access is pcall-wrapped: if API access is off in
-- Studio the game just runs with defaults and does not persist)
local saveStore = nil
pcall(function()
	saveStore = DataStoreService:GetDataStore("ShiningSoulV1")
end)
local saveReady = {} -- [player] = true once a load attempt succeeded

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
local MAX_ARMOR = 5
local ARMOR_PER_POINT = 0.08 -- each Armor point = 8% less damage taken
local POWER_PER_CRYSTAL = 3   -- each Power crystal = +3 permanent damage
local ELITE_CHANCE = 0.12

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

local function makeWedge(parent, name, size, cframe, color, material)
	local p = Instance.new("WedgePart")
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
-- Dusk mood: low warm sun, warm ambient so shadows stay readable,
-- light fog for depth. Brightness kept up so the town reads clearly.
Lighting.ClockTime = 17.8
Lighting.Brightness = 2.2
Lighting.Ambient = Color3.fromRGB(150, 110, 90)
Lighting.OutdoorAmbient = Color3.fromRGB(170, 130, 105)
Lighting.FogColor = Color3.fromRGB(232, 180, 140)
Lighting.FogStart = 180
Lighting.FogEnd = 420

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
	local door = makePart(g, "Door", Vector3.new(3, 5, 0.4), CFrame.new(x, 2.5, z + 6.1),
		Color3.fromRGB(55, 35, 20), Enum.Material.Wood)
	makePart(g, "DoorKnob", Vector3.new(0.35, 0.35, 0.2), CFrame.new(x + 1, 2.5, z + 6.35),
		Color3.fromRGB(255, 200, 80), Enum.Material.Metal).Shape = Enum.PartType.Ball
	-- warm glowing windows on the front wall (either side of the door)
	for _, wx in ipairs({-4, 4}) do
		local win = makePart(g, "Window", Vector3.new(2.2, 2.2, 0.25),
			CFrame.new(x + wx, 4.6, z + 6.1),
			Color3.fromRGB(255, 190, 90), Enum.Material.Neon)
		win.Name = "WindowGlow"
	end
	-- chimney with a cap
	makePart(g, "Chimney", Vector3.new(1.8, 4.5, 1.8), CFrame.new(x + 4.5, 12.5, z - 2),
		Color3.fromRGB(120, 110, 105), Enum.Material.Brick)
	makePart(g, "ChimneyCap", Vector3.new(2.4, 0.5, 2.4), CFrame.new(x + 4.5, 14.9, z - 2),
		Color3.fromRGB(90, 85, 80), Enum.Material.Slate)
	return door
end

local function buildTree(parent, x, z)
	makePart(parent, "Trunk", Vector3.new(1.6, 6, 1.6), CFrame.new(x, 3, z),
		Color3.fromRGB(100, 70, 40), Enum.Material.Wood)
	-- clustered foliage spheres instead of one blob
	local blobs = {
		{0, 9.5, 0, 7}, {-2.6, 8, 0.8, 4.6}, {2.6, 8.2, -0.6, 4.8},
		{0.4, 8.4, 2.6, 4.4}, {-0.8, 11.4, -0.4, 4.2},
	}
	for _, b in ipairs(blobs) do
		local leaf = makePart(parent, "Leaves", Vector3.new(b[4], b[4], b[4]),
			CFrame.new(x + b[1], b[2], z + b[3]),
			Color3.fromRGB(55, 135, 58), Enum.Material.Grass)
		leaf.Shape = Enum.PartType.Ball
	end
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
	-- circular stone plaza under the spawn area
	local plaza = makePart(town, "Plaza", Vector3.new(0.4, 48, 48),
		CFrame.new(TOWN_CENTER.X, 0.2, TOWN_CENTER.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(170, 165, 155), Enum.Material.Cobblestone)
	plaza.Shape = Enum.PartType.Cylinder
	local plazaTrim = makePart(town, "PlazaTrim", Vector3.new(0.25, 52, 52),
		CFrame.new(TOWN_CENTER.X, 0.12, TOWN_CENTER.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(130, 125, 118), Enum.Material.Slate)
	plazaTrim.Shape = Enum.PartType.Cylinder
	-- path strips: spawn -> portal (north), spawn -> shops (west)
	makePart(town, "PathToPortal", Vector3.new(7, 0.3, 52),
		CFrame.new(TOWN_CENTER.X, 0.15, TOWN_CENTER.Z - 22),
		Color3.fromRGB(160, 150, 135), Enum.Material.Cobblestone)
	makePart(town, "PathToShops", Vector3.new(30, 0.3, 6),
		CFrame.new(TOWN_CENTER.X - 12, 0.15, TOWN_CENTER.Z + 2),
		Color3.fromRGB(160, 150, 135), Enum.Material.Cobblestone)

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
	-- glowing orb crowning the fountain
	local orb = makePart(town, "FountainOrb", Vector3.new(2.2, 2.2, 2.2),
		CFrame.new(TOWN_CENTER.X, 6.2, TOWN_CENTER.Z),
		Color3.fromRGB(120, 220, 255), Enum.Material.Neon)
	orb.Shape = Enum.PartType.Ball
	local orbLight = Instance.new("PointLight")
	orbLight.Color = Color3.fromRGB(140, 220, 255)
	orbLight.Range = 30
	orbLight.Brightness = 2
	orbLight.Parent = orb

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
	buildTree(town, -58, TOWN_CENTER.Z - 30)
	buildTree(town, 58, TOWN_CENTER.Z + 30)
	buildTree(town, 40, TOWN_CENTER.Z + 44)

	-- SAFE ZONE boundary: wooden fence ring with a gate on the portal
	-- (north) side. The purple portal sits just outside the gate.
	local fenceMat = Enum.Material.Wood
	local fenceColor = Color3.fromRGB(110, 80, 50)
	local function fenceRun(x1, z1, x2, z2)
		local dx, dz = x2 - x1, z2 - z1
		local len = math.sqrt(dx * dx + dz * dz)
		local mid = CFrame.new((x1 + x2) / 2, 0, (z1 + z2) / 2)
		local cf = CFrame.lookAt(mid.Position, mid.Position + Vector3.new(dx, 0, dz))
		for _, ry in ipairs({1.1, 2.1}) do
			makePart(town, "FenceRail", Vector3.new(0.25, 0.35, len),
				cf * CFrame.new(0, ry, 0), fenceColor, fenceMat)
		end
		local posts = math.max(2, math.floor(len / 8) + 1)
		for i = 0, posts - 1 do
			local t = (posts == 1) and 0 or i / (posts - 1)
			makePart(town, "FencePost", Vector3.new(0.7, 3, 0.7),
				CFrame.new(x1 + dx * t, 1.5, z1 + dz * t), fenceColor, fenceMat)
		end
	end
	local FZ = TOWN_CENTER.Z
	fenceRun(-46, FZ - 46, -5.5, FZ - 46)  -- north, west of gate
	fenceRun(5.5, FZ - 46, 46, FZ - 46)    -- north, east of gate
	fenceRun(-46, FZ + 46, 46, FZ + 46)    -- south
	fenceRun(-46, FZ - 46, -46, FZ + 46)   -- west
	fenceRun(46, FZ - 46, 46, FZ + 46)     -- east
	-- gate posts + lintel
	for _, gx in ipairs({-5.5, 5.5}) do
		makePart(town, "GatePost", Vector3.new(1.2, 6, 1.2), CFrame.new(gx, 3, FZ - 46),
			Color3.fromRGB(90, 62, 38), fenceMat)
	end
	makePart(town, "GateBeam", Vector3.new(13.5, 1, 1), CFrame.new(0, 6.2, FZ - 46),
		Color3.fromRGB(90, 62, 38), fenceMat)

	-- lamp posts: pole + warm neon lamp + real light
	local lampSpots = { {7, FZ - 24}, {-20, FZ + 6}, {9, FZ + 20} }
	for _, s in ipairs(lampSpots) do
		makePart(town, "LampPole", Vector3.new(0.5, 6.5, 0.5), CFrame.new(s[1], 3.25, s[2]),
			Color3.fromRGB(45, 45, 55), Enum.Material.Metal)
		local lamp = makePart(town, "LampGlow", Vector3.new(1.5, 1.5, 1.5),
			CFrame.new(s[1], 7, s[2]), Color3.fromRGB(255, 205, 110), Enum.Material.Neon)
		lamp.Shape = Enum.PartType.Ball
		local ll = Instance.new("PointLight")
		ll.Color = Color3.fromRGB(255, 195, 110)
		ll.Range = 26
		ll.Brightness = 2
		ll.Parent = lamp
	end

	return town
end

-- Merchant stand + shop prompt anchor parts (prompts wired up later)
local potionStandPart = nil
local upgradeStandPart = nil

local function buildMerchant(town)
	local stand = Instance.new("Folder")
	stand.Name = "Merchant"
	stand.Parent = town

	-- One market stall: 4 posts, counter, sloped two-tone awning,
	-- hanging sign with SurfaceGui text. Front faces +Z (the plaza).
	local function buildStall(cx, cz, awningColor, stripeColor, signText)
		local g = Instance.new("Folder")
		g.Name = "Stall"
		g.Parent = stand
		for _, ox in ipairs({-5.5, 5.5}) do
			for _, oz in ipairs({-2.5, 3}) do
				makePart(g, "Post", Vector3.new(0.6, 8, 0.6),
					CFrame.new(cx + ox, 4, cz + oz),
					Color3.fromRGB(100, 70, 40), Enum.Material.Wood)
			end
		end
		makePart(g, "Counter", Vector3.new(12, 3, 2.6), CFrame.new(cx, 1.5, cz + 2.6),
			Color3.fromRGB(120, 85, 50), Enum.Material.Wood)
		makePart(g, "CounterTop", Vector3.new(12.6, 0.35, 3.2), CFrame.new(cx, 3.15, cz + 2.6),
			Color3.fromRGB(150, 110, 70), Enum.Material.Wood)
		-- awning: main sloped slab + a contrasting center stripe
		local tilt = CFrame.Angles(math.rad(-14), 0, 0)
		makePart(g, "Awning", Vector3.new(13.5, 0.35, 7.5),
			CFrame.new(cx, 8.6, cz + 0.2) * tilt, awningColor, Enum.Material.Fabric)
		makePart(g, "AwningStripe", Vector3.new(4, 0.4, 7.6),
			CFrame.new(cx, 8.65, cz + 0.2) * tilt, stripeColor, Enum.Material.Fabric)
		-- hanging sign
		local sign = makePart(g, "Sign", Vector3.new(9, 2.2, 0.3), CFrame.new(cx, 6.4, cz + 3.2),
			Color3.fromRGB(80, 55, 30), Enum.Material.Wood)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.Parent = sign
		local tl = makeLabel(gui, "SignText", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
			signText, 30, Color3.fromRGB(255, 230, 150))
		tl.TextXAlignment = Enum.TextXAlignment.Center
		return g
	end

	-- ITEM SHOP (potions) -- red/cream awning
	local itemStall = buildStall(-19, TOWN_CENTER.Z - 6,
		Color3.fromRGB(200, 60, 60), Color3.fromRGB(245, 235, 210), "ITEM SHOP")
	makePart(itemStall, "MerchantBody", Vector3.new(2.4, 3, 1.2),
		CFrame.new(-19, 4.5, TOWN_CENTER.Z - 8.5),
		Color3.fromRGB(60, 90, 200), Enum.Material.SmoothPlastic)
	local iHead = makePart(itemStall, "MerchantHead", Vector3.new(1.8, 1.8, 1.8),
		CFrame.new(-19, 7, TOWN_CENTER.Z - 8.5), Color3.fromRGB(240, 200, 160),
		Enum.Material.SmoothPlastic)
	iHead.Shape = Enum.PartType.Ball
	-- potion bottles on display
	for i, bx in ipairs({-22, -19, -16}) do
		local bottle = makePart(itemStall, "DisplayBottle", Vector3.new(1.2, 0.8, 0.8),
			CFrame.new(bx, 3.9, TOWN_CENTER.Z - 3.4) * CFrame.Angles(0, 0, math.rad(90)),
			(i == 2) and Color3.fromRGB(90, 255, 140) or Color3.fromRGB(255, 80, 110),
			Enum.Material.Neon)
		bottle.Shape = Enum.PartType.Cylinder
	end

	-- BLACKSMITH (sword upgrades) -- charcoal/orange awning + anvil
	local smithStall = buildStall(1, TOWN_CENTER.Z - 6,
		Color3.fromRGB(70, 70, 80), Color3.fromRGB(255, 140, 50), "BLACKSMITH")
	makePart(smithStall, "SmithBody", Vector3.new(2.4, 3, 1.2),
		CFrame.new(1, 4.5, TOWN_CENTER.Z - 8.5),
		Color3.fromRGB(120, 60, 40), Enum.Material.SmoothPlastic)
	local sHead = makePart(smithStall, "SmithHead", Vector3.new(1.8, 1.8, 1.8),
		CFrame.new(1, 7, TOWN_CENTER.Z - 8.5), Color3.fromRGB(225, 180, 140),
		Enum.Material.SmoothPlastic)
	sHead.Shape = Enum.PartType.Ball
	makePart(smithStall, "AnvilBase", Vector3.new(1.6, 1.4, 1.6),
		CFrame.new(4.5, 0.7, TOWN_CENTER.Z - 4.5),
		Color3.fromRGB(100, 70, 40), Enum.Material.Wood)
	makePart(smithStall, "Anvil", Vector3.new(2.6, 1, 1.1),
		CFrame.new(4.5, 1.9, TOWN_CENTER.Z - 4.5),
		Color3.fromRGB(70, 72, 80), Enum.Material.Metal)

	-- Shop prompt anchor parts (prompts wired up later in setupShop)
	potionStandPart = makePart(stand, "PotionStand", Vector3.new(3, 2, 3),
		CFrame.new(-19, 1, TOWN_CENTER.Z - 1), Color3.fromRGB(220, 60, 80), Enum.Material.SmoothPlastic)
	upgradeStandPart = makePart(stand, "UpgradeStand", Vector3.new(3, 2, 3),
		CFrame.new(1, 1, TOWN_CENTER.Z - 1), Color3.fromRGB(255, 190, 60), Enum.Material.SmoothPlastic)
end

-- Terrain registry used by the zone loop further below: campfire
-- center positions (heal) and the lava pool bounds (burn). The
-- matching visual parts are named "Campfire" / "LavaPool" and live
-- in the Dungeon folder.
local campfirePositions = {}
local LAVA_REL = Vector3.new(40, 0, -30) -- relative to DUNGEON_CENTER
local LAVA_HALF = 5

local function buildDungeon()
	local dg = Instance.new("Folder")
	dg.Name = "Dungeon"
	dg.Parent = mapFolder
	local cx, cz = DUNGEON_CENTER.X, DUNGEON_CENTER.Z
	local wallColor = Color3.fromRGB(90, 90, 100)
	local wallMat = Enum.Material.Slate

	-- base slab + checkerboard dark-stone tiles on top
	makePart(dg, "Floor", Vector3.new(DUNGEON_HALF_X * 2 + 10, 2, DUNGEON_HALF_Z * 2 + 10),
		CFrame.new(cx, -1, cz), Color3.fromRGB(30, 29, 38), Enum.Material.Slate)
	local tileA = Color3.fromRGB(56, 54, 66)
	local tileB = Color3.fromRGB(40, 39, 49)
	for ix = 0, 11 do
		for iz = 0, 9 do
			local tile = makePart(dg, "FloorTile", Vector3.new(9.9, 0.25, 9.9),
				CFrame.new(cx - 55 + ix * 10, 0.13, cz - 45 + iz * 10),
				((ix + iz) % 2 == 0) and tileA or tileB, Enum.Material.Slate)
			tile.TopSurface = Enum.SurfaceType.Smooth
		end
	end
	-- walls (height 12)
	makePart(dg, "WallN", Vector3.new(DUNGEON_HALF_X * 2 + 10, 12, 2),
		CFrame.new(cx, 6, cz - DUNGEON_HALF_Z - 1), wallColor, wallMat)
	makePart(dg, "WallS", Vector3.new(DUNGEON_HALF_X * 2 + 10, 12, 2),
		CFrame.new(cx, 6, cz + DUNGEON_HALF_Z + 1), wallColor, wallMat)
	makePart(dg, "WallW", Vector3.new(2, 12, DUNGEON_HALF_Z * 2 + 10),
		CFrame.new(cx - DUNGEON_HALF_X - 1, 6, cz), wallColor, wallMat)
	makePart(dg, "WallE", Vector3.new(2, 12, DUNGEON_HALF_Z * 2 + 10),
		CFrame.new(cx + DUNGEON_HALF_X + 1, 6, cz), wallColor, wallMat)
	-- decorative columns hugging the walls
	for _, px in ipairs({-44, -22, 22, 44}) do
		for _, pz in ipairs({-DUNGEON_HALF_Z + 2, DUNGEON_HALF_Z - 2}) do
			makePart(dg, "WallColumn", Vector3.new(3.4, 12, 3.4),
				CFrame.new(cx + px, 6, cz + pz), wallColor, wallMat)
		end
	end
	for _, pz in ipairs({-24, 0, 24}) do
		for _, px in ipairs({-DUNGEON_HALF_X + 2, DUNGEON_HALF_X - 2}) do
			makePart(dg, "WallColumn", Vector3.new(3.4, 12, 3.4),
				CFrame.new(cx + px, 6, cz + pz), wallColor, wallMat)
		end
	end
	-- interior pillars (existing set doubles as cover)
	for _, px in ipairs({-30, 0, 30}) do
		for _, pz in ipairs({-25, 15}) do
			makePart(dg, "Pillar", Vector3.new(4, 11, 4),
				CFrame.new(cx + px, 5.5, cz + pz), wallColor, wallMat)
			makePart(dg, "PillarCap", Vector3.new(5, 1, 5),
				CFrame.new(cx + px, 11.2, cz + pz),
				Color3.fromRGB(110, 110, 122), wallMat)
		end
	end
	-- torches with real light + particle flames
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
		local em = Instance.new("ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/fire_main.dds"
		em.Rate = 14
		em.Lifetime = NumberRange.new(0.35, 0.7)
		em.Speed = NumberRange.new(1.5, 3)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(1, 0) })
		em.Color = ColorSequence.new(Color3.fromRGB(255, 170, 70))
		em.LightEmission = 1
		em.Parent = flame
	end

	-- ENTRANCE ARCH over the return portal (south side)
	for _, ax in ipairs({-5.5, 5.5}) do
		makePart(dg, "ArchPost", Vector3.new(1.6, 11, 1.6), CFrame.new(cx + ax, 5.5, cz + 38),
			wallColor, wallMat)
	end
	makePart(dg, "ArchBeam", Vector3.new(13, 1.8, 2), CFrame.new(cx, 11.4, cz + 38),
		Color3.fromRGB(110, 110, 122), wallMat)

	-- CHOKE POINT: entrance corridor. Players teleport in at
	-- (0, ~, cz+36), inside this corridor; it opens at cz+28.
	for _, wx in ipairs({-5.5, 5.5}) do
		makePart(dg, "CorridorWall", Vector3.new(1.5, 7, 13), CFrame.new(cx + wx, 3.5, cz + 34),
			wallColor, wallMat)
		makePart(dg, "CorridorCap", Vector3.new(2.4, 0.8, 13), CFrame.new(cx + wx, 7.4, cz + 34),
			Color3.fromRGB(110, 110, 122), wallMat)
	end

	-- COVER / KITING terrain inside the arena (kept clear of the
	-- corridor, the boss spot at cz-10 and both campfires)
	makePart(dg, "CoverPillar", Vector3.new(3.5, 10, 3.5), CFrame.new(cx + 15, 5, cz - 18),
		wallColor, wallMat)
	makePart(dg, "CoverPillar", Vector3.new(3.5, 10, 3.5), CFrame.new(cx - 16, 5, cz + 2),
		wallColor, wallMat)
	makePart(dg, "LowWall", Vector3.new(11, 3, 1.6), CFrame.new(cx + 24, 1.5, cz + 8),
		Color3.fromRGB(100, 100, 112), wallMat)
	local lw = makePart(dg, "LowWall", Vector3.new(11, 3, 1.6), CFrame.new(cx - 26, 1.5, cz - 24),
		Color3.fromRGB(100, 100, 112), wallMat)
	lw.CFrame = CFrame.new(cx - 26, 1.5, cz - 24) * CFrame.Angles(0, math.rad(90), 0)

	-- RAISED PLATFORM (vantage spot) at the west edge + steps up
	makePart(dg, "Platform", Vector3.new(14, 4, 14), CFrame.new(cx - 46, 2, cz + 14),
		Color3.fromRGB(80, 78, 90), wallMat)
	makePart(dg, "PlatformTop", Vector3.new(15, 0.4, 15), CFrame.new(cx - 46, 4.2, cz + 14),
		Color3.fromRGB(100, 98, 110), wallMat)
	makePart(dg, "Step1", Vector3.new(3, 3, 10), CFrame.new(cx - 37.5, 1.5, cz + 14),
		Color3.fromRGB(88, 86, 98), wallMat)
	makePart(dg, "Step2", Vector3.new(3, 2, 10), CFrame.new(cx - 34.5, 1, cz + 14),
		Color3.fromRGB(88, 86, 98), wallMat)
	makePart(dg, "Step3", Vector3.new(3, 1, 10), CFrame.new(cx - 31.5, 0.5, cz + 14),
		Color3.fromRGB(88, 86, 98), wallMat)

	-- CAMPFIRES (safe spots): stone ring + logs + neon flame + light,
	-- flat ring marker shows the heal radius. One by the entrance,
	-- one mid-arena on the west side.
	local function buildCampfire(fx, fz)
		local g = Instance.new("Folder")
		g.Name = "CampfireSite"
		g.Parent = dg
		local ring = makePart(g, "CampfireRing", Vector3.new(0.3, 14.6, 14.6),
			CFrame.new(fx, 0.32, fz) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(90, 255, 170), Enum.Material.Neon)
		ring.Shape = Enum.PartType.Cylinder
		ring.Transparency = 0.78
		ring.CanCollide = false
		for i = 1, 8 do
			local a = (i / 8) * math.pi * 2
			local stone = makePart(g, "RingStone", Vector3.new(1.1, 0.9, 1.1),
				CFrame.new(fx + math.cos(a) * 2.6, 0.45, fz + math.sin(a) * 2.6),
				Color3.fromRGB(120, 118, 112), Enum.Material.Slate)
			stone.Shape = Enum.PartType.Ball
		end
		for i = 1, 3 do
			local a = (i / 3) * math.pi * 2
			local log = makePart(g, "Log", Vector3.new(3.2, 0.55, 0.55),
				CFrame.new(fx, 0.5, fz) * CFrame.Angles(math.rad(65), a, 0),
				Color3.fromRGB(95, 62, 35), Enum.Material.Wood)
			log.Shape = Enum.PartType.Cylinder
		end
		local flame = makePart(g, "Campfire", Vector3.new(1.8, 2.4, 1.8),
			CFrame.new(fx, 1.5, fz), Color3.fromRGB(255, 150, 60), Enum.Material.Neon)
		flame.Shape = Enum.PartType.Ball
		flame.CanCollide = false
		local fl = Instance.new("PointLight")
		fl.Color = Color3.fromRGB(255, 170, 90)
		fl.Range = 24
		fl.Brightness = 2.5
		fl.Parent = flame
		local em = Instance.new("ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/fire_main.dds"
		em.Rate = 20
		em.Lifetime = NumberRange.new(0.4, 0.9)
		em.Speed = NumberRange.new(2, 4)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1),
			NumberSequenceKeypoint.new(1, 0) })
		em.Color = ColorSequence.new(Color3.fromRGB(255, 180, 80))
		em.LightEmission = 1
		em.Parent = flame
		table.insert(campfirePositions, Vector3.new(fx, 0, fz))
	end
	buildCampfire(cx + 13, cz + 30)   -- just outside the entrance corridor
	buildCampfire(cx - 38, cz - 8)    -- mid-arena, west side

	-- LAVA POOL (danger zone) in the south-east corner: rim + the
	-- glowing pool itself. Named "LavaPool"; the zone loop burns
	-- players standing inside LAVA_REL +/- LAVA_HALF.
	local lavaX, lavaZ = cx + LAVA_REL.X, cz + LAVA_REL.Z
	makePart(dg, "LavaRim", Vector3.new(12.5, 0.6, 12.5), CFrame.new(lavaX, 0.3, lavaZ),
		Color3.fromRGB(45, 40, 42), Enum.Material.Slate)
	local lava = makePart(dg, "LavaPool", Vector3.new(10, 0.5, 10), CFrame.new(lavaX, 0.45, lavaZ),
		Color3.fromRGB(255, 90, 30), Enum.Material.Neon)
	lava.CanCollide = false
	local lavaLight = Instance.new("PointLight")
	lavaLight.Color = Color3.fromRGB(255, 120, 50)
	lavaLight.Range = 22
	lavaLight.Brightness = 2
	lavaLight.Parent = lava
	local lavaEm = Instance.new("ParticleEmitter")
	lavaEm.Texture = "rbxasset://textures/particles/fire_main.dds"
	lavaEm.Rate = 8
	lavaEm.Lifetime = NumberRange.new(0.6, 1.2)
	lavaEm.Speed = NumberRange.new(1, 2.5)
	lavaEm.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 0) })
	lavaEm.Color = ColorSequence.new(Color3.fromRGB(255, 140, 60))
	lavaEm.LightEmission = 1
	lavaEm.Parent = lava

	-- scattered props, kept out of the combat center
	local function rock(rx, rz, s)
		local r = makePart(dg, "Rock", Vector3.new(s, s * 0.7, s * 0.85),
			CFrame.new(cx + rx, s * 0.3, cz + rz) * CFrame.Angles(0, math.rad(rx * 7), 0),
			Color3.fromRGB(105, 103, 110), Enum.Material.Slate)
		r.Shape = Enum.PartType.Ball
	end
	rock(-48, -34, 3.4)
	rock(48, 22, 2.8)
	rock(-14, 37, 2.2)
	rock(30, 36, 2.6)
	local function bonePile(bx, bz)
		for i = 1, 3 do
			local bone = makePart(dg, "Bone", Vector3.new(0.35, 0.35, 2.6),
				CFrame.new(cx + bx, 0.45, cz + bz) * CFrame.Angles(0, math.rad(i * 55), 0),
				Color3.fromRGB(232, 228, 215), Enum.Material.SmoothPlastic)
			bone.Shape = Enum.PartType.Cylinder
		end
	end
	bonePile(28, -36)
	bonePile(-32, 27)
	local function crate(px, pz, py)
		makePart(dg, "Crate", Vector3.new(2.6, 2.6, 2.6), CFrame.new(cx + px, py, cz + pz),
			Color3.fromRGB(130, 95, 55), Enum.Material.Wood)
	end
	crate(50, -6, 1.3)
	crate(50, -6, 3.9)
	crate(47.5, -3.5, 1.3)
	local barrel = makePart(dg, "Barrel", Vector3.new(3.2, 2.2, 2.2),
		CFrame.new(cx - 50, 1.6, cz - 16) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(115, 80, 45), Enum.Material.Wood)
	barrel.Shape = Enum.PartType.Cylinder

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
	-- stone frame around the dungeon portal: 2 pillars + top beam
	local pz = TOWN_CENTER.Z - 48
	for _, px in ipairs({-4.6, 4.6}) do
		makePart(town, "PortalPillar", Vector3.new(1.8, 11, 1.8), CFrame.new(px, 5.5, pz),
			Color3.fromRGB(105, 100, 115), Enum.Material.Slate)
		local cap = makePart(town, "PortalPillarCap", Vector3.new(2.4, 2.4, 2.4),
			CFrame.new(px, 11.6, pz), Color3.fromRGB(170, 90, 255), Enum.Material.Neon)
		cap.Shape = Enum.PartType.Ball
	end
	makePart(town, "PortalBeam", Vector3.new(11.5, 1.6, 1.8), CFrame.new(0, 10.6, pz),
		Color3.fromRGB(105, 100, 115), Enum.Material.Slate)
	local pLight = Instance.new("PointLight")
	pLight.Color = Color3.fromRGB(180, 100, 255)
	pLight.Range = 28
	pLight.Brightness = 2.5
	pLight.Parent = portalToDungeon
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = 24
	sparkles.Lifetime = NumberRange.new(0.8, 1.6)
	sparkles.Speed = NumberRange.new(0.5, 1.5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 0) })
	sparkles.Color = ColorSequence.new(Color3.fromRGB(200, 130, 255))
	sparkles.LightEmission = 1
	sparkles.Parent = portalToDungeon

	portalToTown = makePart(dg, "PortalToTown", Vector3.new(7, 9, 1),
		CFrame.new(DUNGEON_CENTER.X, 4.5, DUNGEON_CENTER.Z + DUNGEON_HALF_Z - 3),
		Color3.fromRGB(60, 200, 255), Enum.Material.Neon)
	portalToTown.CanCollide = false
	portalToTown.Transparency = 0.25
	local tLight = Instance.new("PointLight")
	tLight.Color = Color3.fromRGB(110, 210, 255)
	tLight.Range = 24
	tLight.Brightness = 2
	tLight.Parent = portalToTown
	local tSparkles = sparkles:Clone()
	tSparkles.Color = ColorSequence.new(Color3.fromRGB(140, 220, 255))
	tSparkles.Parent = portalToTown
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
	frame.Size = UDim2.new(0, 240, 0, 182)
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
	makeLabel(frame, "ArmorLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 138), "Armor 0", 14,
		Color3.fromRGB(140, 190, 255))
	makeLabel(frame, "PowerLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 160), "Power +0", 14,
		Color3.fromRGB(255, 140, 255))

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
	local armor = getStat(player, "Stats", "Armor")
	local power = getStat(player, "Stats", "Power")
	if armor then panel.ArmorLabel.Text = "Armor " .. armor.Value .. " / " .. MAX_ARMOR end
	if power then panel.PowerLabel.Text = "Power +" .. power.Value .. " dmg" end
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

-- Enemy visuals. All parts are welded to the HumanoidRootPart with
-- WeldConstraints (see weldTo); the face looks toward -Z. Returns the
-- main body part (the slime's body is squash-animated by the AI loop).
local function buildEnemyVisual(model, root, kind, def)
	local s = def.scale
	local function add(name, size, offset, color, material, shape, extraCFrame)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then p.Shape = shape end
		p.CFrame = root.CFrame * CFrame.new(offset) * (extraCFrame or CFrame.new())
		p.Parent = model
		weldTo(p, root)
		return p
	end
	local boneWhite = def.bodyColor
	local boneHead = def.headColor

	if kind == "Slime" then
		local body = add("Body", Vector3.new(3 * s, 2.4 * s, 3 * s),
			Vector3.new(0, 0.3 * s, 0), def.bodyColor, nil, Enum.PartType.Ball)
		body.Transparency = 0.2
		-- glowing inner core
		local core = add("Core", Vector3.new(1.35 * s, 1.35 * s, 1.35 * s),
			Vector3.new(0, 0.3 * s, 0), Color3.fromRGB(190, 255, 170),
			Enum.Material.Neon, Enum.PartType.Ball)
		core.Transparency = 0.15
		-- eyes with white highlights
		for _, ex in ipairs({-0.55, 0.55}) do
			add("Eye", Vector3.new(0.36 * s, 0.44 * s, 0.2),
				Vector3.new(ex * s, 0.8 * s, -1.38 * s),
				Color3.fromRGB(15, 15, 15), Enum.Material.Neon, Enum.PartType.Ball)
			add("EyeShine", Vector3.new(0.13 * s, 0.13 * s, 0.08),
				Vector3.new((ex - 0.1) * s, 0.95 * s, -1.52 * s),
				Color3.fromRGB(255, 255, 255), Enum.Material.Neon, Enum.PartType.Ball)
		end
		return body
	end

	if kind == "Goblin" then
		for _, lx in ipairs({-0.5, 0.5}) do
			add("Leg", Vector3.new(0.55 * s, 1.1 * s, 0.55 * s),
				Vector3.new(lx * s, -1.05 * s, 0), def.bodyColor)
		end
		local body = add("Body", Vector3.new(2.2 * s, 2.2 * s, 1.2 * s),
			Vector3.new(0, 0.55 * s, 0), def.bodyColor)
		-- dark belt / loincloth band
		add("Belt", Vector3.new(2.35 * s, 0.55 * s, 1.35 * s),
			Vector3.new(0, -0.2 * s, 0), Color3.fromRGB(70, 48, 30), Enum.Material.Leather)
		for _, ax in ipairs({-1.35, 1.35}) do
			add("Arm", Vector3.new(0.5 * s, 1.9 * s, 0.5 * s),
				Vector3.new(ax * s, 0.45 * s, 0), def.bodyColor, nil, nil,
				CFrame.Angles(0, 0, math.rad(ax > 0 and -14 or 14)))
		end
		add("HeadVisual", Vector3.new(1.55 * s, 1.4 * s, 1.4 * s),
			Vector3.new(0, 2.35 * s, 0), def.headColor, nil, Enum.PartType.Ball)
		-- long pointy ears (wedges angled up/out)
		for _, ex in ipairs({-1, 1}) do
			local ear = Instance.new("WedgePart")
			ear.Name = "Ear"
			ear.Size = Vector3.new(1.5 * s, 0.55 * s, 0.3 * s)
			ear.Color = def.headColor
			ear.Material = Enum.Material.SmoothPlastic
			ear.CFrame = root.CFrame * CFrame.new(ex * 1.25 * s, 2.7 * s, 0)
				* CFrame.Angles(0, ex > 0 and math.rad(180) or 0, math.rad(ex * 18))
			ear.Parent = model
			weldTo(ear, root)
		end
		for _, ex in ipairs({-0.35, 0.35}) do
			add("Eye", Vector3.new(0.27 * s, 0.27 * s, 0.12),
				Vector3.new(ex * s, 2.45 * s, -0.68 * s),
				Color3.fromRGB(255, 220, 60), Enum.Material.Neon, Enum.PartType.Ball)
		end
		return body
	end

	-- Skeleton + SkeletonKing share the bone build
	for _, lx in ipairs({-0.5, 0.5}) do
		add("Leg", Vector3.new(0.45 * s, 1.7 * s, 0.45 * s),
			Vector3.new(lx * s, -1.15 * s, 0), boneWhite)
	end
	local torso = add("Body", Vector3.new(2 * s, 2.2 * s, 1 * s),
		Vector3.new(0, 0.55 * s, 0), boneWhite)
	-- rib bars across the chest (front = -Z)
	for i = 0, 2 do
		add("Rib", Vector3.new(2.15 * s, 0.3 * s, 0.22 * s),
			Vector3.new(0, (0.05 + i * 0.55) * s, -0.55 * s),
			Color3.fromRGB(205, 205, 195))
	end
	for _, ax in ipairs({-1.25, 1.25}) do
		add("Arm", Vector3.new(0.4 * s, 2 * s, 0.4 * s),
			Vector3.new(ax * s, 0.45 * s, 0), boneWhite, nil, nil,
			CFrame.Angles(0, 0, math.rad(ax > 0 and -8 or 8)))
	end
	-- skull with black eye sockets
	add("HeadVisual", Vector3.new(1.6 * s, 1.5 * s, 1.5 * s),
		Vector3.new(0, 2.4 * s, 0), boneHead, nil, Enum.PartType.Ball)
	add("Jaw", Vector3.new(1.05 * s, 0.45 * s, 1.05 * s),
		Vector3.new(0, 1.78 * s, -0.08 * s), boneHead)
	for _, ex in ipairs({-0.38, 0.38}) do
		add("EyeSocket", Vector3.new(0.36 * s, 0.42 * s, 0.2),
			Vector3.new(ex * s, 2.5 * s, -0.68 * s),
			Color3.fromRGB(8, 8, 10), nil, Enum.PartType.Ball)
	end
	if kind == "SkeletonKing" then
		-- gold crown: band + four spikes
		local crownY = 3.3 * s
		local band = add("Crown", Vector3.new(0.6 * s, 2.5 * s, 2.5 * s),
			Vector3.new(0, crownY, 0), Color3.fromRGB(255, 200, 60),
			Enum.Material.Metal, Enum.PartType.Cylinder,
			CFrame.Angles(0, 0, math.rad(90)))
		band.Name = "CrownBand"
		for i = 0, 3 do
			local a = i * math.pi / 2 + math.pi / 4
			add("CrownSpike", Vector3.new(0.34 * s, 0.8 * s, 0.34 * s),
				Vector3.new(math.cos(a) * 1.05 * s, (crownY + 0.55 * s), math.sin(a) * 1.05 * s),
				Color3.fromRGB(255, 200, 60), Enum.Material.Metal)
		end
		-- red cape hanging down the back (+Z)
		add("Cape", Vector3.new(2.5 * s, 3.6 * s, 0.25 * s),
			Vector3.new(0, 0.35 * s, 0.78 * s), Color3.fromRGB(170, 30, 40),
			Enum.Material.Fabric, nil, CFrame.Angles(math.rad(7), 0, 0))
	end
	return torso
end

local function makeHealthBar(model, root, displayName, scale)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.new(4, 0, 0.6, 0)
	gui.StudsOffset = Vector3.new(0, 2.4 * (scale or 1) + 1.5, 0)
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
local PICKUP_COLORS = {
	PotionPickup = Color3.fromRGB(255, 80, 110),
	HealOrb = Color3.fromRGB(90, 255, 140),
	ArmorPickup = Color3.fromRGB(110, 170, 255),
	PowerCrystal = Color3.fromRGB(255, 120, 255),
}

local function spawnPickup(kind, position)
	local p = Instance.new("Part")
	p.Name = kind
	p.Size = Vector3.new(1.4, 1.4, 1.4)
	p.Shape = Enum.PartType.Ball
	if kind == "ArmorPickup" then
		p.Shape = Enum.PartType.Block
		p.Size = Vector3.new(1.7, 1.7, 1.7)
	end
	p.Position = position + Vector3.new(math.random(-2, 2), 1, math.random(-2, 2))
	p.Anchored = true
	p.CanCollide = false
	p.Material = Enum.Material.Neon
	p.Color = PICKUP_COLORS[kind] or Color3.fromRGB(255, 255, 255)
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
		elseif kind == "ArmorPickup" then
			local armor = getStat(player, "Stats", "Armor")
			if armor and armor.Value < MAX_ARMOR then
				armor.Value = armor.Value + 1
				announce(player.Name .. " got Armor " .. armor.Value .. "!", 2)
			else
				addGold(player, 50) -- armor maxed: convert to gold
			end
		elseif kind == "PowerCrystal" then
			local power = getStat(player, "Stats", "Power")
			if power then
				power.Value = power.Value + POWER_PER_CRYSTAL
				announce(player.Name .. " got a Power Crystal (+" .. POWER_PER_CRYSTAL .. " dmg)!", 2)
			end
		else -- HealOrb
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
		-- guaranteed gear drop from elites and the boss:
		-- Armor while the killer still needs it, otherwise a Power crystal
		if data.isElite or data.isBoss then
			local armor = killer and getStat(killer, "Stats", "Armor")
			if armor and armor.Value < MAX_ARMOR then
				spawnPickup("ArmorPickup", root.Position)
			else
				spawnPickup("PowerCrystal", root.Position)
			end
		elseif math.random() < 0.05 then
			-- rare power crystal from normal enemies
			spawnPickup("PowerCrystal", root.Position)
		end
		local roll = math.random()
		if roll < 0.25 then
			spawnPickup("PotionPickup", root.Position)
		elseif roll < 0.45 then
			spawnPickup("HealOrb", root.Position)
		end
	end
end

-- Floating damage number above the enemy, floats up and fades (~0.7s)
local function spawnDamageNumber(root, amount)
	local gui = Instance.new("BillboardGui")
	gui.Name = "DamageNumber"
	gui.Size = UDim2.new(3, 0, 1, 0)
	gui.StudsOffset = Vector3.new(math.random(-8, 8) / 10, 4.6, 0)
	gui.AlwaysOnTop = true
	gui.Parent = root
	local label = makeLabel(gui, "Amount", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
		tostring(math.floor(amount + 0.5)), 20, Color3.fromRGB(255, 230, 120))
	label.TextXAlignment = Enum.TextXAlignment.Center
	task.spawn(function()
		local started = os.clock()
		while gui.Parent do
			local t = (os.clock() - started) / 0.7
			if t >= 1 then break end
			gui.StudsOffset = gui.StudsOffset + Vector3.new(0, 0.09, 0)
			label.TextTransparency = t
			label.TextStrokeTransparency = 0.4 + 0.6 * t
			task.wait(0.03)
		end
		gui:Destroy()
	end)
end

-- Brief white flash on the enemy's visual parts when hit
local function flashEnemy(model, data)
	if data.flashing then return end
	data.flashing = true
	local saved = {}
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			saved[part] = part.Color
			part.Color = Color3.fromRGB(255, 255, 255)
		end
	end
	task.delay(0.08, function()
		for part, color in pairs(saved) do
			if part and part.Parent then
				part.Color = color
			end
		end
		data.flashing = false
	end)
end

-- Small neon spark burst at the hit point (~0.3s, then gone)
local function spawnSparks(position)
	for _ = 1, 6 do
		local sp = Instance.new("Part")
		sp.Name = "HitSpark"
		sp.Size = Vector3.new(0.28, 0.28, 0.28)
		sp.Color = Color3.fromRGB(255, 225, 130)
		sp.Material = Enum.Material.Neon
		sp.CanCollide = false
		sp.Position = position
		sp.Parent = Workspace
		sp.AssemblyLinearVelocity = Vector3.new(
			math.random(-14, 14), math.random(4, 16), math.random(-14, 14))
		Debris:AddItem(sp, 0.35)
		task.spawn(function()
			local t0 = os.clock()
			while sp.Parent and os.clock() - t0 < 0.3 do
				sp.Transparency = (os.clock() - t0) / 0.3
				task.wait(0.03)
			end
			if sp.Parent then sp:Destroy() end
		end)
	end
end

local function damageEnemy(model, amount, attacker, knockbackDir)
	local data = enemies[model]
	if not data then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	if attacker then data.lastDamager = attacker.UserId end
	humanoid:TakeDamage(amount)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		spawnDamageNumber(root, amount)
		spawnSparks(root.Position + Vector3.new(0, 1, 0))
	end
	flashEnemy(model, data)
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
	-- elites: gold, tougher, hit harder, pay out triple (boss excluded)
	local isBoss = (kind == "SkeletonKing")
	local isElite = (not isBoss) and (math.random() < ELITE_CHANCE)
	local hpMult = isElite and 2.5 or 1
	local visualDef = def
	if isElite then
		visualDef = {
			scale = def.scale,
			bodyColor = Color3.fromRGB(255, 190, 60),
			headColor = Color3.fromRGB(255, 215, 110),
		}
	end
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
	humanoid.MaxHealth = math.floor(def.health * difficultyScale * hpMult)
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = def.speed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model
	model.PrimaryPart = root
	model.Parent = enemiesFolder
	local bodyPart = buildEnemyVisual(model, root, kind, visualDef)
	local displayName = kind
	if isBoss then
		displayName = "BOSS: Skeleton King"
	elseif isElite then
		displayName = "Elite " .. kind
	end
	makeHealthBar(model, root, displayName, def.scale)
	local rewardMult = isElite and 3 or 1
	local data = {
		kind = kind,
		damage = math.floor(def.damage * (0.8 + 0.2 * difficultyScale) * (isElite and 1.5 or 1)),
		speed = def.speed,
		xp = def.xp * rewardMult,
		gold = def.gold * rewardMult,
		lastAttack = 0,
		lastDamager = nil,
		isBoss = isBoss,
		isElite = isElite,
		flashing = false,
		bodyPart = bodyPart,
		baseBodySize = bodyPart and bodyPart.Size or nil,
		phase = math.random() * math.pi * 2,
	}
	enemies[model] = data
	humanoid.Died:Connect(function()
		onEnemyDeath(model, data) -- rewards/drops fire here, exactly once
		-- CORPSE BURST: unweld the visual parts, fling and fade them
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("WeldConstraint") then d:Destroy() end
		end
		local burstParts = {}
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("BasePart") then
				p.CanCollide = false
				if p ~= root then
					p.Anchored = false
					p.AssemblyLinearVelocity = Vector3.new(
						math.random(-7, 7), math.random(6, 13), math.random(-7, 7))
					p.AssemblyAngularVelocity = Vector3.new(
						math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
					table.insert(burstParts, p)
				end
			end
		end
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 0.4 do
				local a = (os.clock() - t0) / 0.4
				for _, p in ipairs(burstParts) do
					if p.Parent then p.Transparency = math.max(p.Transparency, a) end
				end
				task.wait(0.04)
			end
		end)
		task.wait(0.45)
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
				-- slime squash-and-stretch bounce
				if data.kind == "Slime" and data.bodyPart and data.baseBodySize then
					local bp = data.bodyPart
					if bp.Parent then
						local w = math.sin(os.clock() * 6 + data.phase)
						local bs = data.baseBodySize
						bp.Size = Vector3.new(
							bs.X * (1 - 0.07 * w), bs.Y * (1 + 0.16 * w), bs.Z * (1 - 0.07 * w))
					end
				end
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
							-- Armor: each point blocks 8% of incoming damage
							local armor = getStat(bestPlayer, "Stats", "Armor")
							local armorPoints = armor and math.clamp(armor.Value, 0, MAX_ARMOR) or 0
							local finalDamage = data.damage * (1 - ARMOR_PER_POINT * armorPoints)
							phum:TakeDamage(finalDamage)
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

-- Neon slash arc swept in front of the character on each swing
local function spawnSlashFX(hrp)
	local arc = Instance.new("Part")
	arc.Name = "SlashArc"
	arc.Size = Vector3.new(7, 0.18, 1.6)
	arc.Color = Color3.fromRGB(190, 240, 255)
	arc.Material = Enum.Material.Neon
	arc.Anchored = true
	arc.CanCollide = false
	arc.Transparency = 0.25
	arc.Parent = Workspace
	local base = CFrame.new(hrp.Position) * (hrp.CFrame - hrp.Position)
	task.spawn(function()
		local t0 = os.clock()
		while arc.Parent do
			local t = (os.clock() - t0) / 0.12
			if t >= 1 then break end
			arc.CFrame = base * CFrame.Angles(0, math.rad(-70 + 140 * t), 0)
				* CFrame.new(0, 1.2, -4.4)
			arc.Transparency = 0.25 + 0.75 * t
			task.wait(0.02)
		end
		arc:Destroy()
	end)
end

-- (Re)builds the sword's blade assembly for a tier: tinted steel
-- blade that grows with tier, wedge tip, and from tier 4 a neon
-- edge glow + light. Grip/guard/pommel are built once in createSword.
local function styleSword(tool, tier)
	tier = math.clamp(tier, 1, MAX_SWORD_TIER)
	tool.Name = "Sword (Tier " .. tier .. ")"
	local handle = tool:FindFirstChild("Handle")
	if not handle then return end
	for _, name in ipairs({ "Blade", "BladeTip", "EdgeGlow" }) do
		local old = tool:FindFirstChild(name)
		if old then old:Destroy() end
	end
	local color = TIER_COLORS[tier]
	local bladeLen = 2.2 + (tier - 1) * 0.35
	local function addPart(name, class, size, offset, pColor, material, rot)
		local p = Instance.new(class)
		p.Name = name
		p.Size = size
		p.Color = pColor
		p.Material = material or Enum.Material.Metal
		p.CFrame = handle.CFrame * CFrame.new(offset) * (rot or CFrame.new())
		p.Parent = tool
		weldTo(p, handle)
		return p
	end
	addPart("Blade", "Part", Vector3.new(0.14, bladeLen, 0.5),
		Vector3.new(0, 0.72 + bladeLen / 2, 0), color, Enum.Material.Metal)
	addPart("BladeTip", "WedgePart", Vector3.new(0.14, 0.65, 0.5),
		Vector3.new(0, 0.72 + bladeLen + 0.3, 0), color, Enum.Material.Metal,
		CFrame.Angles(math.rad(-90), 0, 0))
	if tier >= 4 then
		local edge = addPart("EdgeGlow", "Part", Vector3.new(0.2, bladeLen, 0.56),
			Vector3.new(0, 0.72 + bladeLen / 2, 0), color, Enum.Material.Neon)
		edge.Transparency = 0.35
		local gl = Instance.new("PointLight")
		gl.Color = color
		gl.Range = 10
		gl.Brightness = 1.6
		gl.Parent = edge
	end
end

local function createSword(player)
	local tool = Instance.new("Tool")
	tool.Name = "Sword (Tier 1)"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	-- modeled sword: leather grip (the Handle) + gold guard + pommel;
	-- the blade assembly comes from styleSword
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.34, 1.3, 0.34)
	handle.Color = Color3.fromRGB(60, 40, 25)
	handle.Material = Enum.Material.Leather
	handle.Parent = tool
	local guard = Instance.new("Part")
	guard.Name = "Guard"
	guard.Size = Vector3.new(0.3, 0.28, 1.35)
	guard.Color = Color3.fromRGB(255, 200, 80)
	guard.Material = Enum.Material.Metal
	guard.CFrame = handle.CFrame * CFrame.new(0, 0.72, 0)
	guard.Parent = tool
	weldTo(guard, handle)
	local pommel = Instance.new("Part")
	pommel.Name = "Pommel"
	pommel.Size = Vector3.new(0.5, 0.5, 0.5)
	pommel.Shape = Enum.PartType.Ball
	pommel.Color = Color3.fromRGB(255, 200, 80)
	pommel.Material = Enum.Material.Metal
	pommel.CFrame = handle.CFrame * CFrame.new(0, -0.82, 0)
	pommel.Parent = tool
	weldTo(pommel, handle)
	styleSword(tool, 1)
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
		local power = getStat(player, "Stats", "Power")
		local dmg = SWORD_BASE_DAMAGE
			+ ((level and level.Value or 1) - 1) * 2
			+ ((tier and tier.Value or 1) - 1) * 8
			+ (power and power.Value or 0)
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
		-- slash arc FX + a quick grip twist so the swing reads
		spawnSlashFX(hrp)
		local baseGrip = tool.Grip
		tool.Grip = baseGrip * CFrame.Angles(0, 0, math.rad(-75))
		task.delay(0.16, function()
			if tool.Parent then tool.Grip = baseGrip end
		end)
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
	-- modeled staff: wooden shaft (the Handle) + glowing orb on top
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.28, 3.6, 0.28)
	handle.Color = Color3.fromRGB(105, 72, 40)
	handle.Material = Enum.Material.Wood
	handle.Parent = tool
	local orb = Instance.new("Part")
	orb.Name = "Orb"
	orb.Size = Vector3.new(1.15, 1.15, 1.15)
	orb.Shape = Enum.PartType.Ball
	orb.Color = Color3.fromRGB(255, 130, 40)
	orb.Material = Enum.Material.Neon
	orb.CFrame = handle.CFrame * CFrame.new(0, 2.15, 0)
	orb.Parent = tool
	weldTo(orb, handle)
	local orbLight = Instance.new("PointLight")
	orbLight.Color = Color3.fromRGB(255, 150, 60)
	orbLight.Range = 9
	orbLight.Brightness = 1.5
	orbLight.Parent = orb
	local collar = Instance.new("Part")
	collar.Name = "Collar"
	collar.Size = Vector3.new(0.55, 0.35, 0.55)
	collar.Color = Color3.fromRGB(255, 200, 80)
	collar.Material = Enum.Material.Metal
	collar.CFrame = handle.CFrame * CFrame.new(0, 1.55, 0)
	collar.Parent = tool
	weldTo(collar, handle)
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
		local firePower = getStat(player, "Stats", "Power")
		local dmg = FIREBALL_BASE_DAMAGE + ((level and level.Value or 1) - 1) * 3
			+ (firePower and firePower.Value or 0)
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
	-- modeled bottle: round red glass body (the Handle) + neck + cork
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.85, 1.05, 0.85)
	handle.Shape = Enum.PartType.Ball
	handle.Color = Color3.fromRGB(255, 80, 110)
	handle.Material = Enum.Material.Glass
	handle.Transparency = 0.15
	handle.Parent = tool
	local neck = Instance.new("Part")
	neck.Name = "Neck"
	neck.Size = Vector3.new(0.55, 0.36, 0.36)
	neck.Shape = Enum.PartType.Cylinder
	neck.Color = Color3.fromRGB(255, 80, 110)
	neck.Material = Enum.Material.Glass
	neck.Transparency = 0.15
	neck.CFrame = handle.CFrame * CFrame.new(0, 0.72, 0) * CFrame.Angles(0, 0, math.rad(90))
	neck.Parent = tool
	weldTo(neck, handle)
	local cork = Instance.new("Part")
	cork.Name = "Cork"
	cork.Size = Vector3.new(0.36, 0.3, 0.36)
	cork.Color = Color3.fromRGB(196, 160, 110)
	cork.Material = Enum.Material.Wood
	cork.CFrame = handle.CFrame * CFrame.new(0, 1.05, 0)
	cork.Parent = tool
	weldTo(cork, handle)
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
	if not hasTool("Sword") then
		local sword = createSword(player)
		local tier = getStat(player, "Stats", "SwordTier")
		if tier then styleSword(sword, tier.Value) end
		sword.Parent = backpack
	end
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

--====================================================================
-- SAVING (DataStore "ShiningSoulV1")
--====================================================================
local SAVE_FIELDS = { "Level", "XP", "Gold" } -- leaderstats
local SAVE_STATS = { "Potions", "SwordTier", "Armor", "Power" } -- Stats

local function savePlayer(player)
	if not saveStore or not saveReady[player] then return end
	local data = {}
	for _, name in ipairs(SAVE_FIELDS) do
		local v = getStat(player, "leaderstats", name)
		if v then data[name] = v.Value end
	end
	for _, name in ipairs(SAVE_STATS) do
		local v = getStat(player, "Stats", name)
		if v then data[name] = v.Value end
	end
	local ok, err = pcall(function()
		saveStore:SetAsync("player_" .. player.UserId, data)
	end)
	if not ok then
		warn("[ShiningSoul] Save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

local function loadPlayer(player)
	if not saveStore then return end
	local ok, data = pcall(function()
		return saveStore:GetAsync("player_" .. player.UserId)
	end)
	if not ok then
		-- API access off / store unavailable: run with defaults, and do
		-- NOT mark save-ready so defaults never overwrite a real save.
		warn("[ShiningSoul] Load failed for " .. player.Name .. " (saving disabled this session)")
		return
	end
	saveReady[player] = true
	if type(data) ~= "table" then return end -- new player, keep defaults
	local function apply(folderName, name, value, minValue, maxValue)
		local v = getStat(player, folderName, name)
		if v and type(value) == "number" then
			v.Value = math.clamp(math.floor(value), minValue, maxValue)
		end
	end
	apply("leaderstats", "Level", data.Level, 1, 999)
	apply("leaderstats", "XP", data.XP, 0, 100000000)
	apply("leaderstats", "Gold", data.Gold, 0, 100000000)
	apply("Stats", "Potions", data.Potions, 0, 9999)
	apply("Stats", "SwordTier", data.SwordTier, 1, MAX_SWORD_TIER)
	apply("Stats", "Armor", data.Armor, 0, MAX_ARMOR)
	apply("Stats", "Power", data.Power, 0, 100000000)
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
	makeInt(stats, "Armor", 0)
	makeInt(stats, "Power", 0)
	stats.Parent = player

	-- Load saved progress BEFORE the character setup below reads Level
	loadPlayer(player)

	buildHUD(player)

	local backpack = player:WaitForChild("Backpack")
	local startSword = createSword(player)
	local loadedTier = getStat(player, "Stats", "SwordTier")
	if loadedTier then styleSword(startSword, loadedTier.Value) end
	startSword.Parent = backpack
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
	savePlayer(player)
	lastAction[player] = nil
	saveReady[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayer(player)
	end
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

-- ZONE LOOP (0.5s): campfires heal players standing within 7 studs
-- (+6 HP/tick, never above max; enemies get nothing), the lava pool
-- burns players standing in it (8 HP/tick).
task.spawn(function()
	local lavaCenter = DUNGEON_CENTER + LAVA_REL
	while true do
		task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local hrp = getHRP(character)
			local humanoid = getHumanoid(character)
			if hrp and humanoid and humanoid.Health > 0 then
				local pos = hrp.Position
				for _, firePos in ipairs(campfirePositions) do
					if horizontalDistance(pos, firePos) <= 7 and math.abs(pos.Y - firePos.Y) < 6 then
						humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 6)
						break
					end
				end
				if math.abs(pos.X - lavaCenter.X) <= LAVA_HALF
					and math.abs(pos.Z - lavaCenter.Z) <= LAVA_HALF
					and pos.Y < 4 then
					humanoid:TakeDamage(8)
				end
			end
		end
	end
end)

-- Autosave every 60 seconds
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			savePlayer(player)
		end
	end
end)

print("[ShiningSoul] v3 server started: art pass + terrain zones (campfires / lava) ready.")
