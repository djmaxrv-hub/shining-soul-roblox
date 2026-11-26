--====================================================================
-- Shining Soul-type 3D ARPG for Roblox -- v7 (single-file server)
-- Paste this whole file into ONE Script in ServerScriptService.
-- Everything (map, enemies, tools, HUD, shop, waves) is built and
-- wired up at runtime by this script. No child scripts are used.
-- v7: MEGA UPDATE. (0) Skill-cast fixes: choosing a class grants a
--     starter skill point + Skill 1 at Lv1, every cast rejection
--     toasts its reason, cooldowns respect Skill Haste. (A) AFFIX
--     system: gear rolls 0-4 affixes by rarity (crit, lifesteal,
--     attack speed, fire / frost / lightning damage with ignite /
--     slow / chain procs, execute, kill regen, haste...) plus a
--     UNIQUE effect on Legendaries; item names are built from their
--     affixes; the bag has an Inspect mode with a full detail box.
--     (B) Three 3-piece SETS (Inferno Lord / Frost Warden / Storm
--     Soul) with 2pc + 3pc bonuses. (C) Class identities: Warrior
--     uses RAGE and cleaves 3 enemies, Mage fires 3-bolt staff
--     bursts and refunds mana on kills, Archer has Deadeye crit +
--     longshot damage, Paladin builds Holy stacks and radiates a
--     healing aura. Skill SYNERGIES (D2): sibling skill levels
--     passively boost each skill +4%/level. (D) Visual overhaul:
--     per-class weapon silhouettes (greatsword / warhammer /
--     floating-crystal staff / curved bow + quiver), monster props
--     (goblin sword+shield, skeleton plate+sword, slime with an
--     inner skull), boss HP bar, soul orbs on kill, spawn poofs,
--     banners, braziers, dungeon crystals, global shadows + bloom.
--     D2 extras: elites roll ENCHANTMENTS (Fire / Lightning / Cold
--     / Extra Strong / Extra Fast) and bring 2-minion champion
--     packs in waves; affix bands scale with item level (wave);
--     NIGHTMARE difficulty unlocks at the gate after a boss clear
--     (HP x2.2, dmg x1.5, rewards x1.8, better drops).
-- v6: MONSTER SKILLS + BIGGER MAP. Every enemy type now has a real
--     attack pattern instead of walking into the player: Slimes hop
--     and do a telegraphed LEAP attack, Goblins wind up and DASH,
--     Skeletons KITE at range and shoot bone projectiles, Elites do
--     a telegraphed ground SLAM, and the Skeleton King has a big
--     slam, HP-threshold SUMMONS, a bone VOLLEY fan and an ENRAGE
--     below 30% HP. All enemy projectiles are physical parts moved
--     in a fast loop and can be dodged. MAP: the town is now a
--     designed NON-COMBAT hub (Class Mentor NPC that re-opens the
--     class panel, 3 training dummies that show damage numbers but
--     never die or pay out, a controls notice board, bench +
--     campfire corner, flower beds, street houses, bigger plaza);
--     a dressed FIELD (road, pond, fences, mid-field campfire,
--     leashed wandering slimes) connects the town gate to a stone
--     DUNGEON GATE ARCH -- walk through the arch to enter the
--     dungeon, and the dungeon return portal lands back at the
--     arch. A rock-mountain + tree ring bounds the whole world.
-- v5: CLASS system -- four Diablo-2-inspired classes (Warrior /
--     Mage / Archer / Paladin), each with its own tool loadout and
--     3 upgradable skills (levels 0-5). 1 skill point per level-up;
--     skill levels are stored PER CLASS, so switching class keeps
--     level + gear and restores that class's build. Cast from the
--     skill bar or the Q / E / R hotkeys (UIClient forwards keys).
-- v4: full EQUIPMENT system -- rarity gear drops (Common / Rare /
--     Epic / Legendary) from normal / elite / boss enemies, a bag +
--     equip UI (needs the one-time UIClient LocalScript, see the
--     README), worn visuals that change the character the moment an
--     item is equipped (helmet / chest plate / boots on the body,
--     rarity-styled sword in hand), combat SFX, and selectable
--     background music (Auto town/dungeon, Calm, Battle, Off).
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
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

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
-- v8 world layout (see MAP_DESIGN_V8.md): hub town in the south,
-- a river-crossed field in the middle, a room-based dungeon in
-- the north. All zone / spawn / teleport code derives from these.
local TOWN_CENTER = Vector3.new(0, 0, 170)
local DUNGEON_CENTER = Vector3.new(0, 0, -190)
local DUNGEON_HALF_X = 96
local DUNGEON_HALF_Z = 96
local DUNGEON_ENTRANCE = Vector3.new(0, 3, -104)

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
-- CLASSES (v5): base modifiers per class. Applied inside the
-- existing formulas: HP cap (maxHealthFor), sword / fireball / bow
-- damage, mana cap (maxManaFor), walk speed (applyGear), and the
-- enemy -> player damage path (Paladin's inherent reduction).
--====================================================================
local CLASS_IDS = { "Warrior", "Mage", "Archer", "Paladin" }
local CLASS_DEFS = {
	Warrior = { name = "Warrior", cn = "战士",
		hp = 1.4, melee = 1.25, spell = 1.0, ranged = 1.0, mana = 0.7, speed = 16, defRed = 0 },
	Mage = { name = "Mage", cn = "法师",
		hp = 0.75, melee = 1.0, spell = 1.4, ranged = 1.0, mana = 1.8, speed = 16, defRed = 0 },
	Archer = { name = "Archer", cn = "弓手",
		hp = 0.95, melee = 1.0, spell = 1.0, ranged = 1.3, mana = 1.0, speed = 17.5, defRed = 0 },
	Paladin = { name = "Paladin", cn = "圣骑士",
		hp = 1.2, melee = 1.05, spell = 1.0, ranged = 1.0, mana = 1.1, speed = 16, defRed = 0.05 },
}
local DEFAULT_MODS = { hp = 1, melee = 1, spell = 1, ranged = 1, mana = 1, speed = 16, defRed = 0 }

local function modsForClass(classId)
	return CLASS_DEFS[classId] or DEFAULT_MODS
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
-- SOUND EFFECTS (v4). Sounds are cloned per play so they can overlap;
-- parent them to a part for positional audio, or leave nil for a
-- flat SoundService play. A dead asset id just stays silent.
--====================================================================
local SFX_DEFS = {
	-- classic engine-bundled sword sounds (always available)
	Swing = { id = "rbxasset://sounds/swordslash.wav", volume = 0.45 },
	Equip = { id = "rbxasset://sounds/unsheath.wav", volume = 0.5 },
	-- public asset ids gathered from community sound lists
	Hit = { id = "rbxassetid://7122613461", volume = 0.55 },     -- katana slice
	Death = { id = "rbxassetid://621557962", volume = 0.6, speed = 0.7 }, -- kick thud
	Pickup = { id = "rbxassetid://131323304", volume = 0.5 },   -- coin collect
	Drink = { id = "rbxassetid://160745974", volume = 0.6 },    -- drink gulp
	LevelUp = { id = "rbxassetid://983016958", volume = 0.6 },  -- level-up jingle
	Hurt = { id = "rbxassetid://10209590", volume = 0.5, speed = 0.9 }, -- flesh hit
}

local function playSfx(name, atPart, jitter)
	local def = SFX_DEFS[name]
	if not def then return end
	local s = Instance.new("Sound")
	s.Name = "SFX_" .. name
	s.SoundId = def.id
	s.Volume = def.volume or 0.5
	local speed = def.speed or 1
	if jitter then
		speed = speed * (1 + (math.random() * 0.16 - 0.08))
	end
	s.PlaybackSpeed = speed
	s.Parent = atPart or SoundService
	s:Play()
	Debris:AddItem(s, 5)
end

-- Forward declarations: defined in the equipment section further
-- down, but referenced by earlier code (enemy death, level-ups).
local spawnGearDrop -- (position, rarityWeights, ilvlTier) -> spawns a gear drop
local spawnSetDrop -- (position, nightmare) -> spawns a SET piece drop (v7)
local spawnFieldSlime -- (homePosition) -> v6 field wildlife spawner
local showToast -- (player, text, seconds) -> HUD toast; defined in the HUD section (v8: forward-declared so addXP can toast skill points)
local maxHealthFor -- (player) -> max HP incl. level + helmet bonus
-- Class system (v5), defined in the class section further down:
local classDamageMul -- (player, "melee"|"spell"|"ranged") -> outgoing damage multiplier
local classIncomingMul -- (player) -> incoming damage multiplier (Paladin + War Cry)
local thornsReflectFor -- (player) -> fraction of enemy damage reflected (0 = off)
local maxManaFor -- (player) -> mana cap incl. class multiplier

--====================================================================
-- v7 SHARED STATE. The V7 table holds the whole v7 combat pipeline
-- (hit resolution, procs, gear aggregation, weapon styling, boss
-- bar, enchantments, difficulty) so the new code costs the main
-- chunk only a handful of locals (the 200-local limit is close).
-- Functions are assigned in the v7 section after the class system;
-- everything here is only *called* at runtime.
--====================================================================
local V7 = {}
local V8 = {}              -- v8 functions (charge attacks / pathfinding, assigned further down)
V8.charge = {}             -- [player] -> charge state while an attack is held              -- v7 functions (assigned further down)
local combatStats = {}     -- [player] -> aggregated combat stat table (applyGear -> V7.recompute)
local playerFx = {}        -- [player] -> { holy, shield, shieldCd, lastCombat, boomCd, strikeCd, slowUntil, wasSlowed, manaAcc }
local suppressElite = false -- true while spawning champion-pack minions (they never roll elite)
V7.difficulty = "Normal"   -- "Normal" | "Nightmare" (gate prompts set it)
V7.nightmareUnlocked = false -- session flag: set when a boss wave is cleared

--====================================================================
-- WORLD BUILDING
--====================================================================
-- Dusk mood: low warm sun, warm ambient so shadows stay readable,
-- light fog for depth. Brightness kept up so the town reads clearly.
Lighting.ClockTime = 13.6 -- v8: cheerful midday (was dusk 17.8)
Lighting.Brightness = 2.2
Lighting.Ambient = Color3.fromRGB(190, 190, 200)
Lighting.OutdoorAmbient = Color3.fromRGB(210, 210, 220)
Lighting.FogColor = Color3.fromRGB(198, 226, 246)
Lighting.FogStart = 180
Lighting.FogEnd = 420
-- v7: richer rendering -- real shadows + a gentle bloom so Neon
-- accents glow, slight color grade. pcall-wrapped: if a property
-- does not exist on this client version nothing breaks.
pcall(function()
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "ShiningBloom"
	bloom.Intensity = 0.55
	bloom.Size = 24
	bloom.Threshold = 1.1
	bloom.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "ShiningGrade"
	grade.Saturation = 0.08
	grade.Contrast = 0.05
	grade.Parent = Lighting
end)

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
	local topLeaf = nil
	for _, b in ipairs(blobs) do
		local leaf = makePart(parent, "Leaves", Vector3.new(b[4], b[4], b[4]),
			CFrame.new(x + b[1], b[2], z + b[3]),
			Color3.fromRGB(55, 135, 58), Enum.Material.Grass)
		leaf.Shape = Enum.PartType.Ball
		if not topLeaf or b[2] > 10 then topLeaf = leaf end
	end
	-- v7: drifting leaf motes around the canopy (falling-leaf feel)
	if topLeaf then
		local em = Instance.new("ParticleEmitter")
		em.Name = "LeafMotes"
		em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		em.Rate = 3
		em.Lifetime = NumberRange.new(2, 3.5)
		em.Speed = NumberRange.new(0.4, 0.9)
		em.SpreadAngle = Vector2.new(180, 180)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0) })
		em.Color = ColorSequence.new(Color3.fromRGB(120, 200, 110))
		em.LightEmission = 0.5
		em.Parent = topLeaf
	end
end

local townSpawnCFrame = CFrame.new(TOWN_CENTER.X, 3, TOWN_CENTER.Z + 18)

local function buildTown()
	local town = Instance.new("Folder")
	town.Name = "Town"
	town.Parent = mapFolder
	local TC = TOWN_CENTER

	-- ground: ONE continuous slab for the whole town (v8: no
	-- tiled / patchwork ground anywhere in the world)
	makePart(town, "Ground", Vector3.new(190, 2, 190),
		CFrame.new(TC.X, -1, TC.Z),
		Color3.fromRGB(116, 196, 96), Enum.Material.Grass)
	-- plaza: one big circular stone disc + ring trim
	local plaza = makePart(town, "Plaza", Vector3.new(0.4, 68, 68),
		CFrame.new(TC.X, 0.2, TC.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(170, 165, 155), Enum.Material.Cobblestone)
	plaza.Shape = Enum.PartType.Cylinder
	local plazaTrim = makePart(town, "PlazaTrim", Vector3.new(0.25, 75, 75),
		CFrame.new(TC.X, 0.12, TC.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(130, 125, 118), Enum.Material.Slate)
	plazaTrim.Shape = Enum.PartType.Cylinder
	-- main street: continuous cobble ribbons plaza -> north gate
	-- and plaza -> south houses / inn
	makePart(town, "MainStreetN", Vector3.new(10, 0.3, 54),
		CFrame.new(TC.X, 0.15, TC.Z - 56),
		Color3.fromRGB(160, 150, 135), Enum.Material.Cobblestone)
	makePart(town, "MainStreetS", Vector3.new(10, 0.3, 48),
		CFrame.new(TC.X, 0.15, TC.Z + 58),
		Color3.fromRGB(160, 150, 135), Enum.Material.Cobblestone)
	-- market street ribbon in front of the market row
	makePart(town, "MarketStreet", Vector3.new(76, 0.3, 8),
		CFrame.new(TC.X - 18, 0.15, TC.Z - 38),
		Color3.fromRGB(160, 150, 135), Enum.Material.Cobblestone)

	-- spawn pad (south side of the plaza)
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "TownSpawn"
	spawnPad.Size = Vector3.new(10, 1, 10)
	spawnPad.CFrame = CFrame.new(TC.X, 0.5, TC.Z + 18)
	spawnPad.Color = Color3.fromRGB(80, 200, 255)
	spawnPad.Material = Enum.Material.Neon
	spawnPad.Anchored = true
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	spawnPad.Parent = town

	-- fountain (cylinder basin + water + pillar + glowing orb)
	local basin = makePart(town, "FountainBasin", Vector3.new(12, 2, 12),
		CFrame.new(TC.X, 1, TC.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(150, 150, 150), Enum.Material.Marble)
	basin.Shape = Enum.PartType.Cylinder
	local water = makePart(town, "FountainWater", Vector3.new(10, 0.6, 10),
		CFrame.new(TC.X, 2, TC.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(70, 160, 255), Enum.Material.Glass)
	water.Shape = Enum.PartType.Cylinder
	water.Transparency = 0.35
	makePart(town, "FountainPillar", Vector3.new(2, 5, 2),
		CFrame.new(TC.X, 2.5, TC.Z),
		Color3.fromRGB(150, 150, 150), Enum.Material.Marble)
	local orb = makePart(town, "FountainOrb", Vector3.new(2.2, 2.2, 2.2),
		CFrame.new(TC.X, 6.2, TC.Z),
		Color3.fromRGB(120, 220, 255), Enum.Material.Neon)
	orb.Shape = Enum.PartType.Ball
	local orbLight = Instance.new("PointLight")
	orbLight.Color = Color3.fromRGB(140, 220, 255)
	orbLight.Range = 30
	orbLight.Brightness = 2
	orbLight.Parent = orb

	-- district buildings: NE house, W house, S houses row,
	-- the SMITHY (NE, dark walls) and the CLASS HALL (SE, violet)
	buildHouse(town, 66, TC.Z - 12, Color3.fromRGB(200, 180, 150))
	buildHouse(town, -70, TC.Z + 26, Color3.fromRGB(170, 190, 170))
	buildHouse(town, -52, TC.Z + 66, Color3.fromRGB(200, 170, 140))
	buildHouse(town, 64, TC.Z + 62, Color3.fromRGB(180, 160, 190))
	buildHouse(town, 54, TC.Z - 46, Color3.fromRGB(120, 118, 128)) -- smithy
	buildHouse(town, 56, TC.Z + 44, Color3.fromRGB(150, 130, 180)) -- class hall

	-- INN (south, on the main street): two-story-look building
	-- with a hanging sign, front facing the plaza (-Z)
	local inn = Instance.new("Folder")
	inn.Name = "Inn"
	inn.Parent = town
	makePart(inn, "InnBase", Vector3.new(18, 8, 13), CFrame.new(20, 4, TC.Z + 68),
		Color3.fromRGB(190, 165, 140), Enum.Material.Brick)
	makePart(inn, "InnUpper", Vector3.new(15, 6, 11), CFrame.new(20, 11, TC.Z + 68),
		Color3.fromRGB(205, 185, 155), Enum.Material.Brick)
	local innRoof = Instance.new("WedgePart")
	innRoof.Name = "InnRoof"
	innRoof.Size = Vector3.new(17, 5, 13)
	innRoof.CFrame = CFrame.new(20, 16.5, TC.Z + 68)
	innRoof.Color = Color3.fromRGB(140, 60, 50)
	innRoof.Material = Enum.Material.Slate
	innRoof.Anchored = true
	innRoof.Parent = inn
	makePart(inn, "InnDoor", Vector3.new(3, 5, 0.4), CFrame.new(20, 2.5, TC.Z + 61.4),
		Color3.fromRGB(55, 35, 20), Enum.Material.Wood)
	for _, wx in ipairs({-5, 5}) do
		for _, wy in ipairs({4.6, 11}) do
			local win = makePart(inn, "InnWindow", Vector3.new(2.2, 2.2, 0.25),
				CFrame.new(20 + wx, wy, TC.Z + 61.4),
				Color3.fromRGB(255, 190, 90), Enum.Material.Neon)
			win.Name = "WindowGlow"
		end
	end
	local innSign = makePart(inn, "InnSign", Vector3.new(7, 2, 0.3),
		CFrame.new(20, 6.8, TC.Z + 61.2), Color3.fromRGB(80, 55, 30), Enum.Material.Wood)
	local innGui = Instance.new("SurfaceGui")
	innGui.Face = Enum.NormalId.Back
	innGui.Parent = innSign
	local innText = makeLabel(innGui, "InnText", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
		"INN", 30, Color3.fromRGB(255, 230, 150))
	innText.TextXAlignment = Enum.TextXAlignment.Center

	-- smithy yard: forge with a glowing core + an anvil, in front
	-- of the smithy building (the upgrade stall is in the market)
	makePart(town, "ForgeBase", Vector3.new(3.4, 2.2, 3.4),
		CFrame.new(45, 1.1, TC.Z - 38), Color3.fromRGB(90, 88, 96), Enum.Material.Slate)
	local forgeCore = makePart(town, "ForgeCore", Vector3.new(2.2, 1.2, 2.2),
		CFrame.new(45, 2.8, TC.Z - 38), Color3.fromRGB(255, 120, 40), Enum.Material.Neon)
	local forgeLight = Instance.new("PointLight")
	forgeLight.Color = Color3.fromRGB(255, 140, 60)
	forgeLight.Range = 18
	forgeLight.Brightness = 2
	forgeLight.Parent = forgeCore
	makePart(town, "SmithAnvilBase", Vector3.new(1.6, 1.4, 1.6),
		CFrame.new(49, 0.7, TC.Z - 35), Color3.fromRGB(100, 70, 40), Enum.Material.Wood)
	makePart(town, "SmithAnvil", Vector3.new(2.6, 1, 1.1),
		CFrame.new(49, 1.9, TC.Z - 35), Color3.fromRGB(70, 72, 80), Enum.Material.Metal)

	-- trees inside the town edges
	buildTree(town, -30, TC.Z - 20)
	buildTree(town, 30, TC.Z - 20)
	buildTree(town, -88, TC.Z - 60)
	buildTree(town, 88, TC.Z - 60)
	buildTree(town, -88, TC.Z + 60)
	buildTree(town, 88, TC.Z + 60)
	buildTree(town, -40, TC.Z + 84)
	buildTree(town, 40, TC.Z + 84)
	buildTree(town, -88, TC.Z)
	buildTree(town, 88, TC.Z)

	-- SAFE ZONE boundary: fence ring with ONE gate on the north
	-- side (toward the field). Walls of houses close the rest.
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
	local FN, FS = TC.Z - 80, TC.Z + 80 -- fence north z=90, south z=250
	fenceRun(-80, FN, -7, FN)   -- north, west of gate
	fenceRun(7, FN, 80, FN)     -- north, east of gate
	fenceRun(-80, FS, 80, FS)   -- south
	fenceRun(-80, FN, -80, FS)  -- west
	fenceRun(80, FN, 80, FS)    -- east
	-- gate posts + lintel
	for _, gx in ipairs({-7, 7}) do
		makePart(town, "GatePost", Vector3.new(1.2, 6, 1.2), CFrame.new(gx, 3, FN),
			Color3.fromRGB(90, 62, 38), fenceMat)
	end
	makePart(town, "GateBeam", Vector3.new(16, 1, 1), CFrame.new(0, 6.2, FN),
		Color3.fromRGB(90, 62, 38), fenceMat)

	-- town banners flanking the gate (crimson west, azure east)
	for _, b in ipairs({ { -9.5, Color3.fromRGB(255, 120, 150) }, { 9.5, Color3.fromRGB(110, 180, 255) } }) do
		makePart(town, "BannerPole", Vector3.new(0.45, 10, 0.45),
			CFrame.new(b[1], 5, FN + 2), Color3.fromRGB(70, 50, 32), Enum.Material.Wood)
		makePart(town, "BannerBar", Vector3.new(3.4, 0.35, 0.35),
			CFrame.new(b[1], 9.6, FN + 2), Color3.fromRGB(70, 50, 32), Enum.Material.Wood)
		local cloth = makePart(town, "BannerCloth", Vector3.new(2.7, 4.4, 0.16),
			CFrame.new(b[1], 7.2, FN + 2) * CFrame.Angles(0, 0, math.rad(2)),
			b[2], Enum.Material.Fabric)
		cloth.CanCollide = false
		makePart(town, "BannerTrim", Vector3.new(2.7, 0.5, 0.2),
			CFrame.new(b[1], 5.15, FN + 2), Color3.fromRGB(255, 205, 80),
			Enum.Material.Fabric)
	end

	-- lamp posts along the main street + plaza edge
	local lampSpots = { {6, TC.Z - 66}, {-6, TC.Z - 66}, {30, TC.Z}, {-30, TC.Z},
		{6, TC.Z + 46}, {-6, TC.Z + 46} }
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

	-- v8: the market row sits in the NW district at z = TC-44,
	-- stalls facing +Z toward the plaza / market street
	-- ITEM SHOP (potions) -- red/cream awning
	local itemStall = buildStall(-38, TOWN_CENTER.Z - 44,
		Color3.fromRGB(200, 60, 60), Color3.fromRGB(245, 235, 210), "ITEM SHOP")
	makePart(itemStall, "MerchantBody", Vector3.new(2.4, 3, 1.2),
		CFrame.new(-38, 4.5, TOWN_CENTER.Z - 46.5),
		Color3.fromRGB(60, 90, 200), Enum.Material.SmoothPlastic)
	local iHead = makePart(itemStall, "MerchantHead", Vector3.new(1.8, 1.8, 1.8),
		CFrame.new(-38, 7, TOWN_CENTER.Z - 46.5), Color3.fromRGB(240, 200, 160),
		Enum.Material.SmoothPlastic)
	iHead.Shape = Enum.PartType.Ball
	-- potion bottles on display
	for i, bx in ipairs({-41, -38, -35}) do
		local bottle = makePart(itemStall, "DisplayBottle", Vector3.new(1.2, 0.8, 0.8),
			CFrame.new(bx, 3.9, TOWN_CENTER.Z - 41.4) * CFrame.Angles(0, 0, math.rad(90)),
			(i == 2) and Color3.fromRGB(90, 255, 140) or Color3.fromRGB(255, 80, 110),
			Enum.Material.Neon)
		bottle.Shape = Enum.PartType.Cylinder
	end

	-- BLACKSMITH (sword upgrades) -- charcoal/orange awning + anvil
	local smithStall = buildStall(-18, TOWN_CENTER.Z - 44,
		Color3.fromRGB(70, 70, 80), Color3.fromRGB(255, 140, 50), "BLACKSMITH")
	makePart(smithStall, "SmithBody", Vector3.new(2.4, 3, 1.2),
		CFrame.new(-18, 4.5, TOWN_CENTER.Z - 46.5),
		Color3.fromRGB(120, 60, 40), Enum.Material.SmoothPlastic)
	local sHead = makePart(smithStall, "SmithHead", Vector3.new(1.8, 1.8, 1.8),
		CFrame.new(-18, 7, TOWN_CENTER.Z - 46.5), Color3.fromRGB(225, 180, 140),
		Enum.Material.SmoothPlastic)
	sHead.Shape = Enum.PartType.Ball
	makePart(smithStall, "AnvilBase", Vector3.new(1.6, 1.4, 1.6),
		CFrame.new(-14.5, 0.7, TOWN_CENTER.Z - 42.5),
		Color3.fromRGB(100, 70, 40), Enum.Material.Wood)
	makePart(smithStall, "Anvil", Vector3.new(2.6, 1, 1.1),
		CFrame.new(-14.5, 1.9, TOWN_CENTER.Z - 42.5),
		Color3.fromRGB(70, 72, 80), Enum.Material.Metal)

	-- SUPPLIES (decorative third stall, completes the market row)
	local supplyStall = buildStall(2, TOWN_CENTER.Z - 44,
		Color3.fromRGB(50, 130, 120), Color3.fromRGB(245, 235, 210), "SUPPLIES")
	for _, c in ipairs({ {0, TOWN_CENTER.Z - 42.5, 1.3}, {0, TOWN_CENTER.Z - 42.5, 3.9},
		{3.4, TOWN_CENTER.Z - 41, 1.3} }) do
		makePart(supplyStall, "SupplyCrate", Vector3.new(2.6, 2.6, 2.6),
			CFrame.new(c[1], c[3], c[2]), Color3.fromRGB(130, 95, 55), Enum.Material.Wood)
	end
	local supplyBarrel = makePart(supplyStall, "SupplyBarrel", Vector3.new(3.2, 2.2, 2.2),
		CFrame.new(5.5, 1.6, TOWN_CENTER.Z - 45) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(115, 80, 45), Enum.Material.Wood)
	supplyBarrel.Shape = Enum.PartType.Cylinder

	-- Shop prompt anchor parts (prompts wired up later in setupShop)
	potionStandPart = makePart(stand, "PotionStand", Vector3.new(3, 2, 3),
		CFrame.new(-38, 1, TOWN_CENTER.Z - 39), Color3.fromRGB(220, 60, 80), Enum.Material.SmoothPlastic)
	upgradeStandPart = makePart(stand, "UpgradeStand", Vector3.new(3, 2, 3),
		CFrame.new(-18, 1, TOWN_CENTER.Z - 39), Color3.fromRGB(255, 190, 60), Enum.Material.SmoothPlastic)
end

-- Terrain registry used by the zone loop further below: campfire
-- center positions (heal) and the lava pool bounds (burn). The
-- matching visual parts are named "Campfire" / "LavaPool" and live
-- in the Dungeon folder.
local campfirePositions = {}
local LAVA_REL = Vector3.new(-74, 0, -3) -- relative to DUNGEON_CENTER (v8: inside the lava room)
local LAVA_HALF = 5

local function buildDungeon()
	local dg = Instance.new("Folder")
	dg.Name = "Dungeon"
	dg.Parent = mapFolder
	local cx, cz = DUNGEON_CENTER.X, DUNGEON_CENTER.Z
	local wallColor = Color3.fromRGB(90, 90, 100)
	local trimColor = Color3.fromRGB(112, 112, 124)
	local wallMat = Enum.Material.Brick

	-- v8: ONE continuous slate floor under the whole dungeon
	-- (the v7 checkerboard tile grid is gone). Rooms are authored
	-- on top of it; the voids between rooms are filled with solid
	-- rock mass so the dungeon reads as carved into stone.
	makePart(dg, "Floor", Vector3.new(210, 2, 210),
		CFrame.new(cx, -1, cz), Color3.fromRGB(34, 33, 44), Enum.Material.Slate)
	-- flat floor inlays: boss arena disc + hub disc
	local arenaDisc = makePart(dg, "ArenaDisc", Vector3.new(0.22, 62, 62),
		CFrame.new(cx, 0.11, cz - 80) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(50, 40, 48), Enum.Material.Slate)
	arenaDisc.Shape = Enum.PartType.Cylinder
	local hubDisc = makePart(dg, "HubDisc", Vector3.new(0.22, 30, 30),
		CFrame.new(cx, 0.11, cz - 2) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(44, 43, 54), Enum.Material.Slate)
	hubDisc.Shape = Enum.PartType.Cylinder

	-- wall helpers (room coords are RELATIVE to the dungeon
	-- center): a brick wall run + a lighter trim cap on top.
	-- Doorways are the gaps left between runs (all >= 14 wide).
	local function wallX(x1, x2, z)
		local len = math.abs(x2 - x1)
		makePart(dg, "Wall", Vector3.new(len, 12, 2),
			CFrame.new(cx + (x1 + x2) / 2, 6, cz + z), wallColor, wallMat)
		makePart(dg, "WallTrim", Vector3.new(len, 0.8, 2.8),
			CFrame.new(cx + (x1 + x2) / 2, 12.3, cz + z), trimColor, wallMat)
	end
	local function wallZ(z1, z2, x)
		local len = math.abs(z2 - z1)
		makePart(dg, "Wall", Vector3.new(2, 12, len),
			CFrame.new(cx + x, 6, cz + (z1 + z2) / 2), wallColor, wallMat)
		makePart(dg, "WallTrim", Vector3.new(2.8, 0.8, len),
			CFrame.new(cx + x, 12.3, cz + (z1 + z2) / 2), trimColor, wallMat)
	end
	-- solid rock mass filling a void rectangle between rooms
	local rockColor = Color3.fromRGB(52, 50, 60)
	local function fill(x1, x2, z1, z2)
		makePart(dg, "RockMass", Vector3.new(math.abs(x2 - x1), 12, math.abs(z2 - z1)),
			CFrame.new(cx + (x1 + x2) / 2, 6, cz + (z1 + z2) / 2),
			rockColor, Enum.Material.Slate)
	end

	-- ENTRANCE HALL (x -30..30, z 55..85): landing + return portal
	wallX(-30, 30, 85)
	wallX(-30, -7, 55) wallX(7, 30, 55)
	wallZ(55, 85, -30) wallZ(55, 85, 30)
	-- CORRIDOR A (x -7..7, z 8..55)
	wallZ(8, 55, -7) wallZ(8, 55, 7)
	-- HUB (x -20..20, z -12..8): the crossing room
	wallX(-20, -7, 8) wallX(7, 20, 8)
	wallX(-20, -7, -12) wallX(7, 20, -12)
	wallZ(-12, -7, -20) wallZ(7, 8, -20)
	wallZ(-12, -7, 20) wallZ(7, 8, 20)
	-- WEST CORRIDOR (x -56..-20, z -7..7)
	wallX(-56, -20, 7) wallX(-56, -20, -7)
	-- LAVA ROOM (x -92..-56, z -30..24)
	wallZ(-30, -7, -56) wallZ(7, 24, -56)
	wallZ(-30, 24, -92)
	wallX(-92, -56, -30) wallX(-92, -56, 24)
	-- EAST CORRIDOR (x 20..56, z -7..7)
	wallX(20, 56, 7) wallX(20, 56, -7)
	-- CRYSTAL ROOM (x 56..92, z -30..24)
	wallZ(-30, -7, 56) wallZ(7, 24, 56)
	wallZ(-30, 24, 92)
	wallX(56, 92, -30) wallX(56, 92, 24)
	-- NORTH CORRIDOR (x -7..7, z -58..-12)
	wallZ(-58, -12, -7) wallZ(-58, -12, 7)
	-- BOSS ARENA (x -42..42, z -100..-58)
	wallX(-42, -7, -58) wallX(7, 42, -58)
	wallX(-42, 42, -100)
	wallZ(-100, -58, -42) wallZ(-100, -58, 42)
	-- PERIMETER safety ring around the whole footprint
	wallX(-96, 96, 88) wallX(-96, 96, -104)
	wallZ(-104, 88, -96) wallZ(-104, 88, 96)
	-- ROCK MASS in the voids between rooms
	fill(-96, -30, 24, 88)    -- north-west mass
	fill(30, 96, 24, 88)      -- north-east mass
	fill(-56, -20, -30, -7)   -- below west corridor
	fill(20, 56, -30, -7)     -- below east corridor
	fill(-56, -20, 7, 55)     -- west of corridor A (upper)
	fill(20, 56, 7, 55)       -- east of corridor A (upper)
	fill(-30, -7, 8, 55)      -- beside corridor A, west
	fill(7, 30, 8, 55)        -- beside corridor A, east
	fill(-42, -7, -58, -12)   -- west of north corridor
	fill(7, 42, -58, -12)     -- east of north corridor
	fill(-96, -42, -104, -30) -- south-west mass
	fill(42, 96, -104, -30)   -- south-east mass

	-- pillars: entrance hall pair, hub pair, arena four
	for _, p in ipairs({ {-18, 70}, {18, 70}, {-15, -2}, {15, -2},
		{-30, -66}, {30, -66}, {-30, -92}, {30, -92} }) do
		makePart(dg, "Pillar", Vector3.new(4, 11, 4),
			CFrame.new(cx + p[1], 5.5, cz + p[2]), wallColor, wallMat)
		makePart(dg, "PillarCap", Vector3.new(5, 1, 5),
			CFrame.new(cx + p[1], 11.2, cz + p[2]), trimColor, wallMat)
	end

	-- torches with real light + particle flames (room coords)
	local torchSpots = {
		{-26, 60}, {26, 60},     -- entrance hall
		{-5, 30}, {5, 30},       -- corridor A
		{-16, 4}, {16, 4},       -- hub
		{-88, 20}, {-60, -26},   -- lava room
		{60, -26}, {88, 20},     -- crystal room
		{-5, -35}, {5, -35},     -- north corridor
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

	-- braziers in the boss arena (stand + bowl + flame + light)
	local function buildBrazier(bx, bz)
		makePart(dg, "BrazierStand", Vector3.new(1.1, 2.2, 1.1),
			CFrame.new(cx + bx, 1.1, cz + bz), Color3.fromRGB(70, 68, 78), Enum.Material.Slate)
		local bowl = makePart(dg, "BrazierBowl", Vector3.new(0.8, 2.6, 2.6),
			CFrame.new(cx + bx, 2.5, cz + bz) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(52, 50, 60), Enum.Material.Metal)
		bowl.Shape = Enum.PartType.Cylinder
		local flame = makePart(dg, "BrazierFlame", Vector3.new(1.5, 1.9, 1.5),
			CFrame.new(cx + bx, 3.6, cz + bz), Color3.fromRGB(255, 160, 50), Enum.Material.Neon)
		flame.Shape = Enum.PartType.Ball
		flame.CanCollide = false
		local bl = Instance.new("PointLight")
		bl.Color = Color3.fromRGB(255, 170, 80)
		bl.Range = 24
		bl.Brightness = 2.2
		bl.Parent = flame
		local em = Instance.new("ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/fire_main.dds"
		em.Rate = 16
		em.Lifetime = NumberRange.new(0.35, 0.7)
		em.Speed = NumberRange.new(1.5, 3)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(1, 0) })
		em.Color = ColorSequence.new(Color3.fromRGB(255, 170, 70))
		em.LightEmission = 1
		em.Parent = flame
	end
	buildBrazier(-24, -64) buildBrazier(24, -64)
	buildBrazier(-24, -94) buildBrazier(24, -94)

	-- THRONE backdrop on the arena's north wall + red banners
	makePart(dg, "ThronePlatform", Vector3.new(22, 1.5, 9),
		CFrame.new(cx, 0.75, cz - 94), trimColor, wallMat)
	makePart(dg, "ThroneSeat", Vector3.new(5, 3, 3),
		CFrame.new(cx, 3, cz - 96), Color3.fromRGB(40, 38, 48), wallMat)
	makePart(dg, "ThroneBack", Vector3.new(5, 10, 1.2),
		CFrame.new(cx, 8, cz - 97.5), Color3.fromRGB(40, 38, 48), wallMat)
	local throneGem = makePart(dg, "ThroneGem", Vector3.new(1.2, 1.2, 1.2),
		CFrame.new(cx, 11.5, cz - 97.5), Color3.fromRGB(255, 60, 70), Enum.Material.Neon)
	throneGem.Shape = Enum.PartType.Ball
	throneGem.CanCollide = false
	for _, bx in ipairs({-12, 12}) do
		makePart(dg, "ArenaBannerPole", Vector3.new(0.4, 9, 0.4),
			CFrame.new(cx + bx, 4.5, cz - 98.6), Color3.fromRGB(60, 45, 30), Enum.Material.Wood)
		local cloth = makePart(dg, "ArenaBanner", Vector3.new(3, 5.5, 0.16),
			CFrame.new(cx + bx, 5.8, cz - 98.6), Color3.fromRGB(232, 82, 98), Enum.Material.Fabric)
		cloth.CanCollide = false
	end

	-- glowing crystal clusters in the CRYSTAL ROOM (east chamber)
	for _, spot in ipairs({ { 84, 16, 170, 90, 255 }, { 84, -22, 90, 200, 255 },
		{ 64, -24, 90, 200, 255 } }) do
		local gx, gz = cx + spot[1], cz + spot[2]
		for i = 1, 3 do
			local cry = makePart(dg, "GlowCrystal",
				Vector3.new(1.1, 3.2 + i * 0.9, 1.1),
				CFrame.new(gx + (i - 2) * 1.3, 1.6 + i * 0.4, gz + ((i % 2) * 1.6 - 0.8))
					* CFrame.Angles(math.rad(10 * (i - 2)), math.rad(i * 40), math.rad(6)),
				Color3.fromRGB(spot[3], spot[4], spot[5]), Enum.Material.Neon)
			cry.CanCollide = false
		end
		local gl = Instance.new("PointLight")
		gl.Color = Color3.fromRGB(spot[3], spot[4], spot[5])
		gl.Range = 16
		gl.Brightness = 1.6
		local anchor = makePart(dg, "CrystalAnchor", Vector3.new(0.5, 0.5, 0.5),
			CFrame.new(gx, 0.4, gz), Color3.fromRGB(40, 40, 50), Enum.Material.Slate)
		anchor.Transparency = 1
		anchor.CanCollide = false
		gl.Parent = anchor
	end
	-- warm orange glow light in the LAVA ROOM (west chamber)
	local lavaGlowAnchor = makePart(dg, "LavaGlowAnchor", Vector3.new(0.5, 0.5, 0.5),
		CFrame.new(cx + LAVA_REL.X, 6, cz + LAVA_REL.Z),
		Color3.fromRGB(40, 40, 50), Enum.Material.Slate)
	lavaGlowAnchor.Transparency = 1
	lavaGlowAnchor.CanCollide = false
	local lavaGlow = Instance.new("PointLight")
	lavaGlow.Color = Color3.fromRGB(255, 130, 60)
	lavaGlow.Range = 34
	lavaGlow.Brightness = 1.8
	lavaGlow.Parent = lavaGlowAnchor

	-- ENTRANCE ARCH over the return portal (entrance hall, rel z 82)
	for _, ax in ipairs({-5.5, 5.5}) do
		makePart(dg, "ArchPost", Vector3.new(1.6, 11, 1.6), CFrame.new(cx + ax, 5.5, cz + 82),
			wallColor, wallMat)
	end
	makePart(dg, "ArchBeam", Vector3.new(13, 1.8, 2), CFrame.new(cx, 11.4, cz + 82),
		trimColor, wallMat)

	-- CAMPFIRES (safe spots): stone ring + logs + neon flame +
	-- light; positions register in campfirePositions for the zone
	-- loop. One in the entrance hall, one in the hub.
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
	buildCampfire(cx + 22, cz + 66)  -- entrance hall, SE corner
	buildCampfire(cx - 15, cz - 6)   -- hub, west side

	-- LAVA POOL (danger zone) inside the lava room: rim + the
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

	-- scattered props, kept out of doorways and spawn centers
	local function rock(rx, rz, s)
		local r = makePart(dg, "Rock", Vector3.new(s, s * 0.7, s * 0.85),
			CFrame.new(cx + rx, s * 0.3, cz + rz) * CFrame.Angles(0, math.rad(rx * 7), 0),
			Color3.fromRGB(105, 103, 110), Enum.Material.Slate)
		r.Shape = Enum.PartType.Ball
	end
	rock(-88, 18, 3.2)   -- lava room
	rock(-62, 20, 2.4)   -- lava room
	rock(88, -26, 2.6)   -- crystal room
	rock(-36, -64, 2.6)  -- arena corner
	local function bonePile(bx, bz)
		for i = 1, 3 do
			local bone = makePart(dg, "Bone", Vector3.new(0.35, 0.35, 2.6),
				CFrame.new(cx + bx, 0.45, cz + bz) * CFrame.Angles(0, math.rad(i * 55), 0),
				Color3.fromRGB(232, 228, 215), Enum.Material.SmoothPlastic)
			bone.Shape = Enum.PartType.Cylinder
		end
	end
	bonePile(14, -9)     -- hub corner
	bonePile(-34, -94)   -- arena corner
	local function crate(px, pz, py)
		makePart(dg, "Crate", Vector3.new(2.6, 2.6, 2.6), CFrame.new(cx + px, py, cz + pz),
			Color3.fromRGB(130, 95, 55), Enum.Material.Wood)
	end
	crate(88, 8, 1.3)    -- crystal room
	crate(88, 8, 3.9)
	crate(-24, 78, 1.3)  -- entrance hall corner
	local barrel = makePart(dg, "Barrel", Vector3.new(3.2, 2.2, 2.2),
		CFrame.new(cx - 89, 1.6, cz - 14) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(115, 80, 45), Enum.Material.Wood)
	barrel.Shape = Enum.PartType.Cylinder

	return dg
end

-- Portals (Touched handlers wired up later, after player logic exists)
local portalToDungeon = nil
local portalToTown = nil

local function buildPortals(town, dg)
	-- v6: the dungeon portal moved OUT of town to the stone DUNGEON
	-- GATE ARCH at the far end of the field (z = -84). Walking
	-- through the arch teleports into the dungeon, same as the old
	-- town pad did. (Parts are still parented to the town folder;
	-- folders here are purely organizational.)
	portalToDungeon = makePart(town, "PortalToDungeon", Vector3.new(8, 10, 1),
		CFrame.new(0, 5, -84),
		Color3.fromRGB(160, 60, 255), Enum.Material.Neon)
	portalToDungeon.CanCollide = false
	portalToDungeon.Transparency = 0.25
	-- the gate arch itself: two chunky stone pillars + beam + caps
	local pz = -84
	for _, px in ipairs({-5.6, 5.6}) do
		makePart(town, "GateArchPillar", Vector3.new(2.6, 13, 2.6), CFrame.new(px, 6.5, pz),
			Color3.fromRGB(100, 96, 110), Enum.Material.Slate)
		makePart(town, "GateArchBase", Vector3.new(3.6, 1.6, 3.6), CFrame.new(px, 0.8, pz),
			Color3.fromRGB(85, 82, 95), Enum.Material.Slate)
		local cap = makePart(town, "GateArchCap", Vector3.new(2.4, 2.4, 2.4),
			CFrame.new(px, 13.8, pz), Color3.fromRGB(170, 90, 255), Enum.Material.Neon)
		cap.Shape = Enum.PartType.Ball
	end
	makePart(town, "GateArchBeam", Vector3.new(14.5, 2, 2.6), CFrame.new(0, 12.4, pz),
		Color3.fromRGB(100, 96, 110), Enum.Material.Slate)
	-- v7: two burning braziers flank the dungeon gate (stone bowl
	-- + neon flame + real light + fire particles)
	for _, bx in ipairs({ -8.6, 8.6 }) do
		makePart(town, "BrazierStand", Vector3.new(1.1, 2.2, 1.1),
			CFrame.new(bx, 1.1, pz), Color3.fromRGB(70, 68, 78), Enum.Material.Slate)
		local bowl = makePart(town, "BrazierBowl", Vector3.new(0.8, 2.6, 2.6),
			CFrame.new(bx, 2.5, pz) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(52, 50, 60), Enum.Material.Metal)
		bowl.Shape = Enum.PartType.Cylinder
		local flame = makePart(town, "BrazierFlame", Vector3.new(1.5, 1.9, 1.5),
			CFrame.new(bx, 3.6, pz), Color3.fromRGB(255, 160, 50), Enum.Material.Neon)
		flame.Shape = Enum.PartType.Ball
		flame.CanCollide = false
		local bl = Instance.new("PointLight")
		bl.Color = Color3.fromRGB(255, 170, 80)
		bl.Range = 24
		bl.Brightness = 2.2
		bl.Parent = flame
		local em = Instance.new("ParticleEmitter")
		em.Texture = "rbxasset://textures/particles/fire_main.dds"
		em.Rate = 16
		em.Lifetime = NumberRange.new(0.35, 0.7)
		em.Speed = NumberRange.new(1.5, 3)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(1, 0) })
		em.Color = ColorSequence.new(Color3.fromRGB(255, 170, 70))
		em.LightEmission = 1
		em.Parent = flame
	end
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
		CFrame.new(DUNGEON_CENTER.X, 4.5, DUNGEON_CENTER.Z + 82), -- v8: entrance hall south wall (rel z 82)
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
-- v6 MAP EXPANSION: bigger world. The TOWN becomes a designed
-- NON-COMBAT hub (mentor, training dummies, notice board, social
-- corner, flower beds, street houses, bigger plaza); a dressed
-- FIELD (road, pond, fences, mid-field campfire) runs from the
-- town gate to the dungeon gate arch; a mountain ring bounds the
-- world. Travel loop: town -> field -> arch -> dungeon -> field.
--====================================================================
local mentorStandPart = nil

-- Campfire site builder (visual twin of the dungeon campfires in
-- buildDungeon; registers the position so the zone loop heals
-- players standing nearby -- the town social corner included).
local function buildCampfireSite(parent, fx, fz)
	local g = Instance.new("Folder")
	g.Name = "CampfireSite"
	g.Parent = parent
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

local function buildWorldV8()
	-- base ground under the whole world (top at y = -0.12, below
	-- the town / field / dungeon slabs so nothing z-fights)
	makePart(mapFolder, "WorldGround", Vector3.new(380, 2, 680),
		CFrame.new(0, -1.12, -10), Color3.fromRGB(106, 176, 86), Enum.Material.Grass)

	-- FIELD ground: ONE continuous plane, town gate (z=90) down
	-- past the dungeon walls. Top at y=-0.03, just under the
	-- town slab.
	makePart(mapFolder, "FieldGround", Vector3.new(300, 2, 196),
		CFrame.new(0, -1.03, -2), Color3.fromRGB(122, 202, 102), Enum.Material.Grass)
	-- the road: continuous ribbons town gate -> river -> arch,
	-- concrete with light stone edge trim
	local function roadSegment(cz, len)
		makePart(mapFolder, "FieldRoad", Vector3.new(8, 0.3, len),
			CFrame.new(0, 0.22, cz), Color3.fromRGB(150, 148, 142), Enum.Material.Concrete)
		for _, tx in ipairs({ -4.3, 4.3 }) do
			makePart(mapFolder, "RoadTrim", Vector3.new(0.6, 0.34, len),
				CFrame.new(tx, 0.23, cz), Color3.fromRGB(178, 172, 158), Enum.Material.Slate)
		end
	end
	roadSegment(41, 102)   -- town gate (z=92) to river bank (z=-10)
	roadSegment(-53, 58)   -- river bank (z=-24) to the arch (z=-82)

	-- THE RIVER: full-width water strip at z=-18 with stone
	-- banks; the ONLY crossing is the bridge at x=0 (D2-style
	-- chokepoint between the town half and the dungeon half)
	makePart(mapFolder, "RiverBed", Vector3.new(300, 0.2, 12.5),
		CFrame.new(0, -0.08, -18), Color3.fromRGB(46, 66, 84), Enum.Material.Slate)
	local river = makePart(mapFolder, "River", Vector3.new(300, 0.22, 10),
		CFrame.new(0, 0.04, -18), Color3.fromRGB(64, 140, 230), Enum.Material.Glass)
	river.Transparency = 0.35
	river.CanCollide = false
	for _, bz in ipairs({-12.2, -23.8}) do
		makePart(mapFolder, "RiverBank", Vector3.new(300, 0.35, 1.8),
			CFrame.new(0, 0.1, bz), Color3.fromRGB(150, 138, 110), Enum.Material.Sand)
	end
	task.spawn(function()
		while river.Parent do
			river.Transparency = 0.35 + 0.1 * math.sin(os.clock() * 0.6)
			task.wait(0.1)
		end
	end)
	-- the bridge: plank deck + rails + end ramps
	makePart(mapFolder, "BridgeDeck", Vector3.new(7.5, 0.5, 14),
		CFrame.new(0, 0.5, -18), Color3.fromRGB(120, 88, 52), Enum.Material.WoodPlanks)
	for _, rx in ipairs({-3.6, 3.6}) do
		makePart(mapFolder, "BridgeRail", Vector3.new(0.4, 1.1, 14),
			CFrame.new(rx, 1.3, -18), Color3.fromRGB(100, 72, 42), Enum.Material.Wood)
		for _, rz in ipairs({-23.5, -18, -12.5}) do
			makePart(mapFolder, "BridgePost", Vector3.new(0.55, 1.8, 0.55),
				CFrame.new(rx, 0.9, rz), Color3.fromRGB(100, 72, 42), Enum.Material.Wood)
		end
	end
	for _, rz in ipairs({-25.6, -10.4}) do
		local ramp = Instance.new("WedgePart")
		ramp.Name = "BridgeRamp"
		ramp.Size = Vector3.new(7.5, 0.75, 3.2)
		ramp.CFrame = CFrame.new(0, 0.37, rz) * CFrame.Angles(0, rz < -18 and math.pi or 0, 0)
		ramp.Color = Color3.fromRGB(120, 88, 52)
		ramp.Material = Enum.Material.WoodPlanks
		ramp.Anchored = true
		ramp.Parent = mapFolder
	end

	-- pond (west side): the slime camp's shore
	local rim = makePart(mapFolder, "PondRim", Vector3.new(0.5, 24, 24),
		CFrame.new(-52, 0.1, 34) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(125, 122, 115), Enum.Material.Slate)
	rim.Shape = Enum.PartType.Cylinder
	local pond = makePart(mapFolder, "Pond", Vector3.new(0.3, 21, 21),
		CFrame.new(-52, 0.3, 34) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(70, 160, 255), Enum.Material.Glass)
	pond.Shape = Enum.PartType.Cylinder
	pond.Transparency = 0.3
	pond.CanCollide = false
	task.spawn(function()
		while pond.Parent do
			pond.Transparency = 0.3 + 0.12 * math.sin(os.clock() * 0.7 + 2)
			task.wait(0.1)
		end
	end)
	for _, lp in ipairs({ {-58, 30}, {-47, 39}, {-50, 27} }) do
		local pad = makePart(mapFolder, "LilyPad", Vector3.new(0.18, 2.6, 2.6),
			CFrame.new(lp[1], 0.42, lp[2]) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(60, 150, 70), Enum.Material.SmoothPlastic)
		pad.Shape = Enum.PartType.Cylinder
		pad.CanCollide = false
	end

	-- split-rail fences flanking the road (with gaps to walk out)
	local fenceColor = Color3.fromRGB(110, 80, 50)
	local function fieldFence(x, z1, z2)
		local len = math.abs(z2 - z1)
		local midZ = (z1 + z2) / 2
		for _, ry in ipairs({1, 1.9}) do
			makePart(mapFolder, "FieldFenceRail", Vector3.new(0.25, 0.32, len),
				CFrame.new(x, ry, midZ), fenceColor, Enum.Material.Wood)
		end
		local posts = math.max(2, math.floor(len / 9) + 1)
		for i = 0, posts - 1 do
			local t = (posts == 1) and 0 or i / (posts - 1)
			makePart(mapFolder, "FieldFencePost", Vector3.new(0.6, 2.6, 0.6),
				CFrame.new(x, 1.3, z1 + (z2 - z1) * t), fenceColor, Enum.Material.Wood)
		end
	end
	fieldFence(-6.5, 88, 60)
	fieldFence(6.5, 88, 60)
	fieldFence(-6.5, 52, 22)
	fieldFence(6.5, 52, 22)
	fieldFence(-6.5, -34, -66)
	fieldFence(6.5, -34, -66)

	-- forests: three dense clusters + lone trees
	local forestSpots = {
		-- NE cluster
		{66, 44}, {78, 58}, {92, 40}, {104, 62}, {84, 78}, {116, 44}, {58, 70}, {100, 84}, {72, 26}, {120, 72},
		-- NW cluster
		{-70, 58}, {-86, 72}, {-100, 50}, {-116, 66}, {-92, 84}, {-78, 36}, {-124, 84}, {-62, 80},
		-- SW cluster (south of the river)
		{-66, -52}, {-80, -66}, {-94, -48}, {-108, -70}, {-58, -78},
		-- lone trees
		{30, -44}, {-30, 6}, {44, 12}, {-120, -20}, {128, -30},
	}
	for _, t in ipairs(forestSpots) do
		buildTree(mapFolder, t[1], t[2])
	end
	local function fieldRock(rx, rz, s)
		local r = makePart(mapFolder, "FieldRock", Vector3.new(s, s * 0.7, s * 0.85),
			CFrame.new(rx, s * 0.28, rz) * CFrame.Angles(0, math.rad(rx * 5), 0),
			Color3.fromRGB(108, 106, 112), Enum.Material.Slate)
		r.Shape = Enum.PartType.Ball
	end
	fieldRock(-14, -34, 3)
	fieldRock(20, -52, 2.4)
	fieldRock(-44, -8, 3.6)
	fieldRock(44, -70, 2.8)
	fieldRock(120, 10, 3.4)
	fieldRock(-128, 30, 3)

	-- wildflower dots over the field grass (capped; kept off the
	-- road, the river, the pond and both monster camps)
	local flowerPalette = {
		Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 215, 90),
		Color3.fromRGB(200, 150, 255), Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(255, 150, 90),
	}
	local placedFlowers = 0
	local flowerTries = 0
	while placedFlowers < 140 and flowerTries < 600 do -- v8 cute: more flowers
		flowerTries = flowerTries + 1
		local fx = math.random(-145, 145)
		local fz = math.random(-95, 88)
		local dxp, dzp = fx + 52, fz - 34
		local dxg, dzg = fx + 80, fz + 36
		local dxs, dzs = fx - 88, fz + 52
		local bad = math.abs(fx) < 7
			or (fz > -26 and fz < -10)
			or (dxp * dxp + dzp * dzp) < 170
			or (dxg * dxg + dzg * dzg) < 150
			or (dxs * dxs + dzs * dzs) < 180
		if not bad then
			local fl = makePart(mapFolder, "FieldFlower",
				Vector3.new(0.32, 0.32, 0.32), CFrame.new(fx, 0.35, fz),
				flowerPalette[math.random(1, #flowerPalette)], Enum.Material.Neon)
			fl.Shape = Enum.PartType.Ball
			fl.CanCollide = false
			placedFlowers = placedFlowers + 1
		end
	end

	-- GOBLIN TENT CAMP (west, south of the river): two lean-to
	-- tents, crates, a barrel, bones and a small prop fire
	local camp = Instance.new("Folder")
	camp.Name = "GoblinCamp"
	camp.Parent = mapFolder
	local function buildTent(tx, tz)
		local g = Instance.new("Folder")
		g.Name = "Tent"
		g.Parent = camp
		for _, s in ipairs({-1, 1}) do
			local side = makePart(g, "TentSide", Vector3.new(0.25, 4.6, 6.5),
				CFrame.new(tx + s * 1.35, 1.95, tz) * CFrame.Angles(0, 0, s * math.rad(52)),
				Color3.fromRGB(96, 104, 62), Enum.Material.Fabric)
			side.CanCollide = false
			makePart(g, "TentPole", Vector3.new(0.35, 3.6, 0.35),
				CFrame.new(tx + s * 2.6, 1.8, tz + 3), Color3.fromRGB(90, 62, 38), Enum.Material.Wood)
		end
		local back = makePart(g, "TentBack", Vector3.new(3.6, 3, 0.2),
			CFrame.new(tx, 1.5, tz - 3.1), Color3.fromRGB(84, 92, 56), Enum.Material.Fabric)
		back.CanCollide = false
	end
	buildTent(-86, -40)
	buildTent(-74, -30)
	for _, c in ipairs({ {-80, -44, 1.3}, {-80, -44, 3.9}, {-71, -38, 1.3} }) do
		makePart(camp, "CampCrate", Vector3.new(2.6, 2.6, 2.6),
			CFrame.new(c[1], c[3], c[2]), Color3.fromRGB(130, 95, 55), Enum.Material.Wood)
	end
	local campBarrel = makePart(camp, "CampBarrel", Vector3.new(3.2, 2.2, 2.2),
		CFrame.new(-90, 1.6, -30) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(115, 80, 45), Enum.Material.Wood)
	campBarrel.Shape = Enum.PartType.Cylinder
	for i = 1, 3 do
		local bone = makePart(camp, "CampBone", Vector3.new(0.35, 0.35, 2.6),
			CFrame.new(-77, 0.45, -47) * CFrame.Angles(0, math.rad(i * 55), 0),
			Color3.fromRGB(232, 228, 215), Enum.Material.SmoothPlastic)
		bone.Shape = Enum.PartType.Cylinder
	end
	local propFlame = makePart(camp, "CampPropFire", Vector3.new(1.4, 1.8, 1.4),
		CFrame.new(-80, 1.2, -36), Color3.fromRGB(255, 150, 60), Enum.Material.Neon)
	propFlame.Shape = Enum.PartType.Ball
	propFlame.CanCollide = false
	local propLight = Instance.new("PointLight")
	propLight.Color = Color3.fromRGB(255, 170, 90)
	propLight.Range = 16
	propLight.Brightness = 1.6
	propLight.Parent = propFlame

	-- RUINS (south-east): a ring of broken pillars + altar --
	-- the skeleton camp
	local ruins = Instance.new("Folder")
	ruins.Name = "Ruins"
	ruins.Parent = mapFolder
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2
		local px, pz = 88 + math.cos(a) * 10, -52 + math.sin(a) * 10
		local h = 2.2 + ((i * 37) % 4) * 1.1
		local pillar = makePart(ruins, "BrokenPillar", Vector3.new(2.2, h, 2.2),
			CFrame.new(px, h / 2, pz) * CFrame.Angles(math.rad((i % 3 - 1) * 4), 0, math.rad((i % 2) * 5)),
			Color3.fromRGB(128, 125, 118), Enum.Material.Slate)
		pillar.Name = "BrokenPillar"
		makePart(ruins, "PillarBase", Vector3.new(3, 0.8, 3),
			CFrame.new(px, 0.4, pz), Color3.fromRGB(112, 109, 104), Enum.Material.Slate)
	end
	makePart(ruins, "RuinAltar", Vector3.new(4.4, 1.2, 4.4),
		CFrame.new(88, 0.6, -52), Color3.fromRGB(120, 117, 110), Enum.Material.Slate)
	makePart(ruins, "RuinSlab", Vector3.new(3.4, 0.5, 3.4),
		CFrame.new(88, 1.45, -52) * CFrame.Angles(0, math.rad(24), 0),
		Color3.fromRGB(138, 135, 128), Enum.Material.Slate)
	for i = 1, 3 do
		local bone = makePart(ruins, "RuinBone", Vector3.new(0.35, 0.35, 2.6),
			CFrame.new(84, 0.45, -46) * CFrame.Angles(0, math.rad(i * 55 + 20), 0),
			Color3.fromRGB(232, 228, 215), Enum.Material.SmoothPlastic)
		bone.Shape = Enum.PartType.Cylinder
	end

	-- farmhouses flanking the road in the north field
	buildHouse(mapFolder, 34, 62, Color3.fromRGB(196, 178, 148))
	buildHouse(mapFolder, -40, 78, Color3.fromRGB(178, 188, 168))

	-- healing campfires: mid-field + near the dungeon gate
	buildCampfireSite(mapFolder, 26, -4)
	buildCampfireSite(mapFolder, -16, -72)

	-- WAYPOINT STONE by the spawn: pure decoration (the real
	-- dungeon entrance is the gate arch at the field's far end)
	local stone = makePart(mapFolder, "WaypointStone", Vector3.new(2.2, 5.2, 2.2),
		CFrame.new(10, 2.6, 196) * CFrame.Angles(math.rad(4), math.rad(20), 0),
		Color3.fromRGB(105, 102, 112), Enum.Material.Slate)
	local rune = makePart(mapFolder, "WaypointRune", Vector3.new(0.25, 3, 3),
		CFrame.new(10, 3.4, 194.6) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(170, 90, 255), Enum.Material.Neon)
	rune.Shape = Enum.PartType.Cylinder
	rune.CanCollide = false
	local runeLight = Instance.new("PointLight")
	runeLight.Color = Color3.fromRGB(180, 100, 255)
	runeLight.Range = 16
	runeLight.Brightness = 1.5
	runeLight.Parent = rune

	-- TOWN: Class Mentor on a podium in front of the CLASS HALL
	-- (SE district). The ProximityPrompt is wired in setupMentor().
	local podium = makePart(townFolder, "MentorPodium", Vector3.new(1, 9.5, 9.5),
		CFrame.new(42, 0.5, 206) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(150, 148, 142), Enum.Material.Marble)
	podium.Shape = Enum.PartType.Cylinder
	makePart(townFolder, "MentorBody", Vector3.new(2.2, 3.2, 1.1),
		CFrame.new(42, 2.6, 206), Color3.fromRGB(110, 60, 170), Enum.Material.SmoothPlastic)
	local mHead = makePart(townFolder, "MentorHead", Vector3.new(1.7, 1.7, 1.7),
		CFrame.new(42, 5, 206), Color3.fromRGB(240, 200, 160), Enum.Material.SmoothPlastic)
	mHead.Shape = Enum.PartType.Ball
	local mHat = makePart(townFolder, "MentorHat", Vector3.new(0.5, 2.6, 2.6),
		CFrame.new(42, 6.1, 206) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(80, 40, 130), Enum.Material.SmoothPlastic)
	mHat.Shape = Enum.PartType.Cylinder
	makePart(townFolder, "MentorStaff", Vector3.new(0.3, 6.4, 0.3),
		CFrame.new(43.6, 3.4, 206), Color3.fromRGB(100, 70, 40), Enum.Material.Wood)
	local mOrb = makePart(townFolder, "MentorOrb", Vector3.new(1, 1, 1),
		CFrame.new(43.6, 6.9, 206), Color3.fromRGB(150, 100, 255), Enum.Material.Neon)
	mOrb.Shape = Enum.PartType.Ball
	local nameGui = Instance.new("BillboardGui")
	nameGui.Name = "MentorName"
	nameGui.Size = UDim2.new(6, 0, 1, 0)
	nameGui.StudsOffset = Vector3.new(0, 2.2, 0)
	nameGui.AlwaysOnTop = true
	nameGui.Parent = mHead
	local nl = makeLabel(nameGui, "NameLabel", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
		"Class Mentor", 16, Color3.fromRGB(210, 170, 255))
	nl.TextXAlignment = Enum.TextXAlignment.Center
	mentorStandPart = makePart(townFolder, "MentorStand", Vector3.new(3, 2, 3),
		CFrame.new(42, 1, 201), Color3.fromRGB(255, 205, 80), Enum.Material.SmoothPlastic)

	-- TOWN: notice board by the north gate (v8 text: charge
	-- attacks + skill points are called out explicitly)
	for _, px in ipairs({-19, -7}) do
		makePart(townFolder, "BoardPost", Vector3.new(0.6, 5.5, 0.6),
			CFrame.new(px, 2.75, 97), Color3.fromRGB(100, 70, 40), Enum.Material.Wood)
	end
	local board = makePart(townFolder, "NoticeBoard", Vector3.new(13.5, 6, 0.4),
		CFrame.new(-13, 4.4, 97), Color3.fromRGB(120, 88, 52), Enum.Material.Wood)
	local bgui = Instance.new("SurfaceGui")
	bgui.Face = Enum.NormalId.Front
	bgui.Parent = board
	local bl = makeLabel(bgui, "BoardText", UDim2.fromScale(0.94, 0.92),
		UDim2.fromScale(0.03, 0.04),
		"HOW TO PLAY\nMove: WASD  |  Attack: click -- HOLD to CHARGE (0.7s / 1.5s tiers)\nSkills: Q  E  R  |  Skill Points: watch the HUD, spend them in Skills!\nDungeon: north gate -> field -> cross the bridge -> the purple arch", 20,
		Color3.fromRGB(255, 240, 200))
	bl.TextWrapped = true
	bl.TextXAlignment = Enum.TextXAlignment.Center
	bl.TextYAlignment = Enum.TextYAlignment.Top

	-- TOWN: bench + campfire social corner (west side, heals)
	buildCampfireSite(townFolder, -72, 168)
	makePart(townFolder, "BenchSeat", Vector3.new(6.5, 0.4, 1.9),
		CFrame.new(-72, 1.15, 174.5), Color3.fromRGB(115, 80, 48), Enum.Material.Wood)
	makePart(townFolder, "BenchBack", Vector3.new(6.5, 1.9, 0.35),
		CFrame.new(-72, 2.3, 175.5), Color3.fromRGB(115, 80, 48), Enum.Material.Wood)
	for _, bx in ipairs({-74.6, -69.4}) do
		makePart(townFolder, "BenchLeg", Vector3.new(0.5, 1.1, 1.7),
			CFrame.new(bx, 0.55, 174.5), Color3.fromRGB(90, 62, 38), Enum.Material.Wood)
	end

	-- TOWN: flower beds around the plaza
	local flowerColors = {
		Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 200, 70),
		Color3.fromRGB(190, 110, 255), Color3.fromRGB(255, 130, 60),
		Color3.fromRGB(120, 220, 255),
	}
	for _, spot in ipairs({ {16, 148}, {-16, 148}, {16, 192}, {-16, 192} }) do
		local fx, fz = spot[1], spot[2]
		makePart(townFolder, "Planter", Vector3.new(7.5, 1, 3.2),
			CFrame.new(fx, 0.5, fz), Color3.fromRGB(105, 74, 44), Enum.Material.Wood)
		makePart(townFolder, "PlanterSoil", Vector3.new(7, 0.3, 2.7),
			CFrame.new(fx, 1.05, fz), Color3.fromRGB(70, 50, 32), Enum.Material.Slate)
		for i = 1, 5 do
			local fl = makePart(townFolder, "Flower", Vector3.new(0.55, 0.55, 0.55),
				CFrame.new(fx - 3 + (i - 1) * 1.5, 1.45, fz + ((i % 2 == 0) and 0.6 or -0.6)),
				flowerColors[i], Enum.Material.Neon)
			fl.Shape = Enum.PartType.Ball
			fl.CanCollide = false
		end
	end

	-- TOWN: TRAINING YARD (SW district): a fenced yard with an
	-- east-side opening; the 3 dummies spawn inside it (bottom
	-- of the script)
	local yardColor = Color3.fromRGB(110, 80, 50)
	local function yardFence(x1, z1, x2, z2)
		local dx, dz = x2 - x1, z2 - z1
		local len = math.sqrt(dx * dx + dz * dz)
		local mid = CFrame.new((x1 + x2) / 2, 0, (z1 + z2) / 2)
		local cf = CFrame.lookAt(mid.Position, mid.Position + Vector3.new(dx, 0, dz))
		for _, ry in ipairs({1, 1.9}) do
			makePart(townFolder, "YardRail", Vector3.new(0.25, 0.32, len),
				cf * CFrame.new(0, ry, 0), yardColor, Enum.Material.Wood)
		end
		local posts = math.max(2, math.floor(len / 8) + 1)
		for i = 0, posts - 1 do
			local t = (posts == 1) and 0 or i / (posts - 1)
			makePart(townFolder, "YardPost", Vector3.new(0.6, 2.6, 0.6),
				CFrame.new(x1 + dx * t, 1.3, z1 + dz * t), yardColor, Enum.Material.Wood)
		end
	end
	yardFence(-68, 200, -38, 200)  -- north side
	yardFence(-68, 228, -38, 228)  -- south side
	yardFence(-68, 200, -68, 228)  -- west side
	yardFence(-38, 200, -38, 210)  -- east side, north of the opening
	yardFence(-38, 218, -38, 228)  -- east side, south of the opening

	-- WORLD BOUNDARY: rock mountains ringing the whole world
	-- rectangle, so the map reads as a place, not an endless plate
	local bi = 0
	local function boundaryRock(x, z)
		bi = bi + 1
		local s = 44 + (bi % 3) * 10
		local rock = makePart(mapFolder, "BoundaryRock",
			Vector3.new(s, s * 0.62, s * 0.9),
			CFrame.new(x, s * 0.16, z) * CFrame.Angles(0, math.rad(x + z), 0),
			Color3.fromRGB(96 + (bi % 3) * 6, 94 + (bi % 3) * 5, 104), Enum.Material.Slate)
		rock.Shape = Enum.PartType.Ball
	end
	for z = -300, 280, 29 do
		boundaryRock(-168, z)
		boundaryRock(168, z)
	end
	for x = -168, 168, 29 do
		boundaryRock(x, 292)
		boundaryRock(x, -318)
	end
	-- backdrop pines just inside the far corners
	buildTree(mapFolder, -150, -290)
	buildTree(mapFolder, 150, -290)
	buildTree(mapFolder, -150, 270)
	buildTree(mapFolder, 150, 270)
	buildTree(mapFolder, 0, -302)
	buildTree(mapFolder, 0, 278)
end
buildWorldV8()

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
	local gainedLevels = 0
	while xp.Value >= xpThreshold(level.Value) do
		xp.Value = xp.Value - xpThreshold(level.Value)
		level.Value = level.Value + 1
		gainedLevels = gainedLevels + 1
		local character = player.Character
		local humanoid = getHumanoid(character)
		if humanoid then
			humanoid.MaxHealth = maxHealthFor(player)
			humanoid.Health = humanoid.MaxHealth
		end
		playSfx("LevelUp", getHRP(character))
		announce(player.Name .. " reached Level " .. level.Value .. "!", 3)
	end
	-- v5: every level-up grants 1 skill point
	if gainedLevels > 0 then
		local sp = getStat(player, "Stats", "SkillPoints")
		if sp then sp.Value = sp.Value + gainedLevels end
		-- v8: shout about the new point(s) the moment they land
		showToast(player, "+" .. gainedLevels .. " Skill Point"
			.. (gainedLevels > 1 and "s" or "")
			.. " - open Skills to spend it!", 4)
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
	frame.Size = UDim2.new(0, 240, 0, 192)
	frame.Position = UDim2.new(0, 12, 0, 12)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = gui

	makeLabel(frame, "LevelLabel", UDim2.new(1, -12, 0, 24), UDim2.new(0, 8, 0, 4), "Level 1", 18)
	makeLabel(frame, "XPLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 27), "XP 0", 14,
		Color3.fromRGB(180, 220, 255))
	makeLabel(frame, "GoldLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 47), "Gold 0", 14,
		Color3.fromRGB(255, 215, 90))
	makeLabel(frame, "ManaLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 67), "Mana 100", 14,
		Color3.fromRGB(120, 180, 255))
	makeLabel(frame, "PotionLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 87), "Potions 3", 14,
		Color3.fromRGB(255, 140, 160))
	makeLabel(frame, "WaveLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 107), "", 14,
		Color3.fromRGB(200, 255, 200))
	makeLabel(frame, "ArmorLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 127), "Armor 0", 14,
		Color3.fromRGB(140, 190, 255))
	makeLabel(frame, "PowerLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 147), "Power +0", 14,
		Color3.fromRGB(255, 140, 255))
	-- v8: PERMANENT Skill Points line (players could not find
	-- their points in v7); turns gold while points are unspent
	makeLabel(frame, "SkillPtsLabel", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 167), "Skill Points: 0", 14,
		Color3.fromRGB(170, 170, 185))

	-- v8: CHARGE bar (bottom-center, above the skill bar): the
	-- fill scales with charge progress while an attack is held,
	-- and the bar hides again on release. Driven by the v8
	-- charge loop at the bottom of the script.
	local chargeBar = Instance.new("Frame")
	chargeBar.Name = "ChargeBar"
	chargeBar.Size = UDim2.new(0, 240, 0, 14)
	chargeBar.Position = UDim2.new(0.5, -120, 1, -108)
	chargeBar.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
	chargeBar.BackgroundTransparency = 0.25
	chargeBar.BorderSizePixel = 0
	chargeBar.Visible = false
	chargeBar.Parent = gui
	local chargeFill = Instance.new("Frame")
	chargeFill.Name = "Fill"
	chargeFill.Size = UDim2.fromScale(0, 1)
	chargeFill.BackgroundColor3 = Color3.fromRGB(140, 200, 255)
	chargeFill.BorderSizePixel = 0
	chargeFill.Parent = chargeBar
	local chargeText = makeLabel(chargeBar, "Text", UDim2.fromScale(1, 1),
		UDim2.fromScale(0, 0), "CHARGE", 10, Color3.fromRGB(255, 255, 255))
	chargeText.TextXAlignment = Enum.TextXAlignment.Center

	local banner = makeLabel(gui, "Banner", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 60), "", 30,
		Color3.fromRGB(255, 230, 120))
	banner.TextXAlignment = Enum.TextXAlignment.Center

	-- per-player toast line (pickups, bag messages), under the banner
	local toast = makeLabel(gui, "Toast", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 112), "", 19,
		Color3.fromRGB(255, 215, 120))
	toast.TextXAlignment = Enum.TextXAlignment.Center

	-- v7: BOSS HP bar (top-center), hidden unless a boss is alive;
	-- filled + labelled by V7.updateBossBar from the status loop
	local bossBar = Instance.new("Frame")
	bossBar.Name = "BossBar"
	bossBar.Size = UDim2.new(0, 430, 0, 28)
	bossBar.Position = UDim2.new(0.5, -215, 0, 10)
	bossBar.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
	bossBar.BackgroundTransparency = 0.2
	bossBar.BorderSizePixel = 0
	bossBar.Visible = false
	bossBar.Parent = gui
	local bossFill = Instance.new("Frame")
	bossFill.Name = "BossFill"
	bossFill.Size = UDim2.fromScale(1, 1)
	bossFill.BackgroundColor3 = Color3.fromRGB(205, 45, 55)
	bossFill.BorderSizePixel = 0
	bossFill.Parent = bossBar
	local bossName = makeLabel(bossBar, "BossName", UDim2.fromScale(1, 1),
		UDim2.fromScale(0, 0), "", 15, Color3.fromRGB(255, 255, 255))
	bossName.TextXAlignment = Enum.TextXAlignment.Center
	return gui
end

local toastToken = {} -- [player] = counter, guards the clear timer

showToast = function(player, text, seconds)
	local gui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("ShiningHUD")
	if not gui then return end
	local toast = gui:FindFirstChild("Toast")
	if not toast then return end
	toastToken[player] = (toastToken[player] or 0) + 1
	local token = toastToken[player]
	toast.Text = text
	task.delay(seconds or 3, function()
		if toastToken[player] == token and toast.Parent then
			toast.Text = ""
		end
	end)
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
	if level then
		local classVal = getStat(player, "Stats", "Class")
		local classSuffix = ""
		if classVal and classVal.Value ~= "" then
			classSuffix = " - " .. classVal.Value
		end
		panel.LevelLabel.Text = "Level " .. level.Value .. classSuffix
	end
	if xp and level then
		panel.XPLabel.Text = "XP " .. xp.Value .. " / " .. xpThreshold(level.Value)
	end
	if gold then panel.GoldLabel.Text = "Gold " .. gold.Value end
	-- v7: for Warriors the resource line becomes a red RAGE line
	local classVal2 = getStat(player, "Stats", "Class")
	if classVal2 and classVal2.Value == "Warrior" then
		local rage = getStat(player, "Stats", "Rage")
		panel.ManaLabel.Text = "RAGE " .. (rage and rage.Value or 0) .. " / 100"
		panel.ManaLabel.TextColor3 = Color3.fromRGB(255, 90, 60)
	elseif mana then
		panel.ManaLabel.Text = "Mana " .. mana.Value .. " / " .. maxManaFor(player)
		panel.ManaLabel.TextColor3 = Color3.fromRGB(120, 180, 255)
	end
	if potions then panel.PotionLabel.Text = "Potions " .. potions.Value end
	local armor = getStat(player, "Stats", "Armor")
	local power = getStat(player, "Stats", "Power")
	if armor then panel.ArmorLabel.Text = "Armor " .. armor.Value .. " / " .. MAX_ARMOR end
	if power then panel.PowerLabel.Text = "Power +" .. power.Value .. " dmg" end
	-- v8: skill points are always visible in the HUD; the line
	-- turns gold and the Skills button gains a "(!)" while the
	-- player has points waiting to be spent
	local spVal = getStat(player, "Stats", "SkillPoints")
	local spLabel = panel:FindFirstChild("SkillPtsLabel")
	if spVal and spLabel then
		spLabel.Text = "Skill Points: " .. spVal.Value
		spLabel.TextColor3 = spVal.Value > 0
			and Color3.fromRGB(255, 215, 90) or Color3.fromRGB(170, 170, 185)
	end
	local bagGui = player.PlayerGui:FindFirstChild("ShiningBag")
	local skillsBtn = bagGui and bagGui:FindFirstChild("SkillsButton")
	if skillsBtn and spVal then
		local want = spVal.Value > 0 and "Skills (!)" or "Skills"
		if skillsBtn.Text ~= want then skillsBtn.Text = want end
	end
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
		scale = 1, bodyColor = Color3.fromRGB(105, 236, 126), headColor = Color3.fromRGB(70, 220, 90),
	},
	Goblin = {
		health = 60, damage = 10, speed = 13, xp = 30, gold = 18,
		scale = 0.95, bodyColor = Color3.fromRGB(106, 182, 82), headColor = Color3.fromRGB(148, 218, 102),
	},
	Skeleton = {
		health = 85, damage = 14, speed = 11, xp = 45, gold = 26,
		scale = 1.05, bodyColor = Color3.fromRGB(225, 225, 215), headColor = Color3.fromRGB(240, 240, 230),
	},
	SkeletonKing = {
		health = 650, damage = 24, speed = 10, xp = 300, gold = 250,
		scale = 2.3, bodyColor = Color3.fromRGB(228, 226, 216), headColor = Color3.fromRGB(246, 242, 228),
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
		-- v7: glassy shell so the insides show through
		local body = add("Body", Vector3.new(3 * s, 2.4 * s, 3 * s),
			Vector3.new(0, 0.3 * s, 0), def.bodyColor,
			Enum.Material.Glass, Enum.PartType.Ball)
		body.Transparency = 0.2
		-- glowing inner core
		local core = add("Core", Vector3.new(1.35 * s, 1.35 * s, 1.35 * s),
			Vector3.new(0, 0.3 * s, 0), Color3.fromRGB(255, 244, 190),
			Enum.Material.Neon, Enum.PartType.Ball)
		core.Transparency = 0.15
		-- v8 CUTE: a glowing STAR core floats inside the slime
		-- (two crossed neon plates over the bright heart) -- the
		-- v7 swallowed skull is gone; kids' game now
		for _, ang in ipairs({ 0, 45 }) do
			add("StarCore", Vector3.new(1.5 * s, 0.44 * s, 0.16),
				Vector3.new(0, 0.3 * s, 0), Color3.fromRGB(255, 226, 92),
				Enum.Material.Neon, nil, CFrame.Angles(0, 0, math.rad(ang)))
		end
		local starLight = Instance.new("PointLight")
		starLight.Color = Color3.fromRGB(255, 230, 120)
		starLight.Range = 7
		starLight.Brightness = 1.3
		starLight.Parent = core
		-- v8 CUTE: BIG friendly eyes -- white ball, dark pupil,
		-- tiny shine dot
		for _, ex in ipairs({-0.52, 0.52}) do
			add("Eye", Vector3.new(0.58 * s, 0.58 * s, 0.3),
				Vector3.new(ex * s, 0.85 * s, -1.32 * s),
				Color3.fromRGB(255, 255, 255), nil, Enum.PartType.Ball)
			add("Pupil", Vector3.new(0.3 * s, 0.34 * s, 0.16),
				Vector3.new(ex * s, 0.82 * s, -1.55 * s),
				Color3.fromRGB(25, 22, 30), nil, Enum.PartType.Ball)
			add("EyeShine", Vector3.new(0.12 * s, 0.12 * s, 0.08),
				Vector3.new((ex - 0.11) * s, 0.98 * s, -1.66 * s),
				Color3.fromRGB(255, 255, 255), Enum.Material.Neon, Enum.PartType.Ball)
		end
		-- candy variant: about a third of slimes are pink
		if math.random() < 0.35 then
			body.Color = Color3.fromRGB(255, 150, 205)
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
		-- v8 CUTE: a cheerful orange tunic over the torso
		add("Tunic", Vector3.new(2.34 * s, 1.5 * s, 1.34 * s),
			Vector3.new(0, 0.62 * s, 0), Color3.fromRGB(255, 138, 61),
			Enum.Material.Fabric)
		for _, ax in ipairs({-1.35, 1.35}) do
			add("Arm", Vector3.new(0.5 * s, 1.9 * s, 0.5 * s),
				Vector3.new(ax * s, 0.45 * s, 0), def.bodyColor, nil, nil,
				CFrame.Angles(0, 0, math.rad(ax > 0 and -14 or 14)))
		end
		add("HeadVisual", Vector3.new(1.95 * s, 1.8 * s, 1.8 * s),
			Vector3.new(0, 2.5 * s, 0), def.headColor, nil, Enum.PartType.Ball)
		-- long pointy ears (wedges angled up/out)
		for _, ex in ipairs({-1, 1}) do
			local ear = Instance.new("WedgePart")
			ear.Name = "Ear"
			ear.Size = Vector3.new(1.7 * s, 0.6 * s, 0.32 * s)
			ear.Color = def.headColor
			ear.Material = Enum.Material.SmoothPlastic
			ear.CFrame = root.CFrame * CFrame.new(ex * 1.5 * s, 2.85 * s, 0)
				* CFrame.Angles(0, ex > 0 and math.rad(180) or 0, math.rad(ex * 18))
			ear.Parent = model
			weldTo(ear, root)
		end
		-- v8 CUTE: big round eyes (white + pupil) on the round head
		for _, ex in ipairs({-0.42, 0.42}) do
			add("Eye", Vector3.new(0.46 * s, 0.46 * s, 0.22),
				Vector3.new(ex * s, 2.58 * s, -0.82 * s),
				Color3.fromRGB(255, 255, 255), nil, Enum.PartType.Ball)
			add("Pupil", Vector3.new(0.22 * s, 0.26 * s, 0.12),
				Vector3.new(ex * s, 2.55 * s, -1.0 * s),
				Color3.fromRGB(25, 22, 30), nil, Enum.PartType.Ball)
		end
		-- v7 goblin kit: red headband, a crude sword in the right
		-- hand and a wooden shield strapped to the left arm
		add("Headband", Vector3.new(0.46 * s, 2.3 * s, 2.3 * s),
			Vector3.new(0, 2.78 * s, 0), Color3.fromRGB(240, 70, 80),
			Enum.Material.Fabric, Enum.PartType.Cylinder,
			CFrame.Angles(0, 0, math.rad(90)))
		add("CrudeBlade", Vector3.new(0.15 * s, 1.1 * s, 0.4 * s),
			Vector3.new(1.8 * s, -0.2 * s, -0.25 * s),
			Color3.fromRGB(150, 148, 140), Enum.Material.Metal, nil,
			CFrame.Angles(0, 0, math.rad(-24)))
		add("CrudeGuard", Vector3.new(0.22 * s, 0.2 * s, 0.95 * s),
			Vector3.new(1.62 * s, 0.38 * s, -0.25 * s),
			Color3.fromRGB(90, 62, 38), Enum.Material.Wood)
		add("Shield", Vector3.new(0.55 * s, 1.9 * s, 1.9 * s),
			Vector3.new(-1.78 * s, 0.45 * s, -0.15 * s),
			Color3.fromRGB(150, 105, 58), Enum.Material.Wood, Enum.PartType.Ball)
		add("ShieldBoss", Vector3.new(0.34 * s, 0.5 * s, 0.5 * s),
			Vector3.new(-1.95 * s, 0.45 * s, -0.15 * s),
			Color3.fromRGB(140, 140, 148), Enum.Material.Metal, Enum.PartType.Ball)
		return body
	end

	-- Skeleton + SkeletonKing share the bone build
	for _, lx in ipairs({-0.5, 0.5}) do
		add("Leg", Vector3.new(0.42 * s, 1.35 * s, 0.42 * s),
			Vector3.new(lx * s, -1.3 * s, 0), boneWhite)
	end
	local torso = add("Body", Vector3.new(1.75 * s, 1.95 * s, 0.95 * s),
		Vector3.new(0, 0.55 * s, 0), boneWhite)
	-- rib bars across the chest (front = -Z)
	for i = 0, 2 do
		add("Rib", Vector3.new(1.9 * s, 0.3 * s, 0.22 * s),
			Vector3.new(0, (0.05 + i * 0.55) * s, -0.55 * s),
			Color3.fromRGB(205, 205, 195))
	end
	for _, ax in ipairs({-1.12, 1.12}) do
		add("Arm", Vector3.new(0.38 * s, 1.7 * s, 0.38 * s),
			Vector3.new(ax * s, 0.45 * s, 0), boneWhite, nil, nil,
			CFrame.Angles(0, 0, math.rad(ax > 0 and -8 or 8)))
	end
	-- v7 skeleton kit: a tattered rusty chest plate over the ribs,
	-- one shoulder pad, and a rusty sword in the right hand
	add("ChestPlate", Vector3.new(1.85 * s, 1.5 * s, 0.26 * s),
		Vector3.new(0, 0.75 * s, -0.68 * s),
		Color3.fromRGB(122, 92, 70), Enum.Material.Metal)
	add("ShoulderPad", Vector3.new(1.0 * s, 0.5 * s, 1.2 * s),
		Vector3.new(-1.18 * s, 1.45 * s, 0),
		Color3.fromRGB(122, 92, 70), Enum.Material.Metal)
	add("RustyBlade", Vector3.new(0.14 * s, 1.35 * s, 0.38 * s),
		Vector3.new(1.6 * s, -0.3 * s, -0.25 * s),
		Color3.fromRGB(152, 130, 108), Enum.Material.Metal, nil,
		CFrame.Angles(0, 0, math.rad(-16)))
	add("RustyGuard", Vector3.new(0.2 * s, 0.18 * s, 0.9 * s),
		Vector3.new(1.45 * s, 0.42 * s, -0.25 * s),
		Color3.fromRGB(100, 84, 66), Enum.Material.Metal)
	-- skull with black eye sockets
	add("HeadVisual", Vector3.new(2.1 * s, 1.95 * s, 1.95 * s),
		Vector3.new(0, 2.55 * s, 0), boneHead, nil, Enum.PartType.Ball)
	add("Jaw", Vector3.new(0.95 * s, 0.4 * s, 0.95 * s),
		Vector3.new(0, 1.92 * s, -0.08 * s), boneHead)
	-- v8 CUTE: BIG round sockets with friendly glowing eyes
	for _, ex in ipairs({-0.45, 0.45}) do
		add("EyeSocket", Vector3.new(0.58 * s, 0.58 * s, 0.24),
			Vector3.new(ex * s, 2.62 * s, -0.85 * s),
			Color3.fromRGB(30, 28, 38), nil, Enum.PartType.Ball)
		add("EyeGlow", Vector3.new(0.3 * s, 0.3 * s, 0.14),
			Vector3.new(ex * s, 2.62 * s, -1.02 * s),
			Color3.fromRGB(120, 240, 255), Enum.Material.Neon, Enum.PartType.Ball)
	end
	if kind == "SkeletonKing" then
		-- v7: BIGGER gold crown: wider band + taller spikes
		local crownY = 3.35 * s
		local band = add("Crown", Vector3.new(0.75 * s, 3.3 * s, 3.3 * s),
			Vector3.new(0, crownY, 0), Color3.fromRGB(255, 200, 60),
			Enum.Material.Metal, Enum.PartType.Cylinder,
			CFrame.Angles(0, 0, math.rad(90)))
		band.Name = "CrownBand"
		for i = 0, 3 do
			local a = i * math.pi / 2 + math.pi / 4
			add("CrownSpike", Vector3.new(0.44 * s, 1.25 * s, 0.44 * s),
				Vector3.new(math.cos(a) * 1.35 * s, (crownY + 0.8 * s), math.sin(a) * 1.35 * s),
				Color3.fromRGB(255, 200, 60), Enum.Material.Metal)
			-- v8 CUTE: a round ball tip on every crown spike
			add("CrownTip", Vector3.new(0.52 * s, 0.52 * s, 0.52 * s),
				Vector3.new(math.cos(a) * 1.35 * s, (crownY + 1.5 * s), math.sin(a) * 1.35 * s),
				Color3.fromRGB(255, 214, 90), Enum.Material.Metal, Enum.PartType.Ball)
		end
		-- red cape hanging down the back (+Z), now in TWO segments
		-- (upper + lower) so it reads as layered cloth
		add("Cape", Vector3.new(2.5 * s, 3.6 * s, 0.25 * s),
			Vector3.new(0, 0.35 * s, 0.78 * s), Color3.fromRGB(226, 72, 96),
			Enum.Material.Fabric, nil, CFrame.Angles(math.rad(7), 0, 0))
		add("CapeLower", Vector3.new(2.3 * s, 2.4 * s, 0.22 * s),
			Vector3.new(0, -1.55 * s, 1.05 * s), Color3.fromRGB(200, 56, 80),
			Enum.Material.Fabric, nil, CFrame.Angles(math.rad(15), 0, 0))
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
		playSfx("Pickup", getHRP(character))
		p:Destroy()
	end)
end

local function onEnemyDeath(model, data)
	enemies[model] = nil
	-- v6: training dummies never pay out and never drop anything
	if data.isDummy then return end
	local killer = nil
	if data.lastDamager then
		killer = Players:GetPlayerByUserId(data.lastDamager)
	end
	-- v7 D2: Fire / Cold Enchanted elites detonate on death
	if data.enchant and V7.enchantDeath then
		V7.enchantDeath(model, data)
	end
	if killer then
		addXP(killer, data.xp)
		addGold(killer, data.gold)
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		-- v7: kill feel -- three soul orbs fly from the corpse to
		-- the killer over 0.4s, then vanish (pure visual)
		if killer and V7.soulOrbs then
			V7.soulOrbs(root.Position, killer)
		end
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
		-- EQUIPMENT drops (v4, v7): rarity odds scale with enemy
		-- rank; v7 adds ITEM LEVEL tiers (later waves roll higher
		-- in their bands, bosses roll the top band), SET pieces
		-- (boss 35% / elite 8% of gear drops) and Nightmare weight
		-- shifts (rarity up, set chance up, +1 ilvl tier)
		if spawnGearDrop then
			local tier = (currentWave >= 4) and 2 or 1
			if data.nightmare then tier = math.min(3, tier + 1) end
			if data.isBoss then
				tier = 3
				if spawnSetDrop and math.random() < (data.nightmare and 0.55 or 0.35) then
					spawnSetDrop(root.Position, data.nightmare)
				elseif data.nightmare then
					spawnGearDrop(root.Position,
						{ { "Epic", 40 }, { "Legendary", 60 } }, tier)
				else
					spawnGearDrop(root.Position,
						{ { "Epic", 70 }, { "Legendary", 30 } }, tier)
				end
			elseif data.isElite then
				if math.random() < 0.60 then
					if spawnSetDrop and math.random() < 0.08 then
						spawnSetDrop(root.Position, data.nightmare)
					else
						spawnGearDrop(root.Position,
							{ { "Rare", 60 }, { "Epic", 35 }, { "Legendary", 5 } }, tier)
					end
				end
			elseif math.random() < 0.08 then
				spawnGearDrop(root.Position, { { "Common", 70 }, { "Rare", 30 } }, tier)
			end
		end
		local roll = math.random()
		if roll < 0.25 then
			spawnPickup("PotionPickup", root.Position)
		elseif roll < 0.45 then
			spawnPickup("HealOrb", root.Position)
		end
	end
	-- v6: field wildlife respawns at its home point 10s later
	if data.isField and data.home then
		local home = data.home
		local kind = data.kind
		task.delay(10, function()
			V8.spawnFieldMonster(kind, home)
		end)
	end
end

-- Floating damage number above the enemy, floats up and fades (~0.7s)
-- v7: opts (optional) -- { crit = true } renders a big orange CRIT
-- number; { small = true, color = c } a smaller one (elemental
-- components, DoT ticks); { noNumber = true } skips the number.
local function spawnDamageNumber(root, amount, opts)
	if opts and opts.noNumber then return end
	local crit = opts and opts.crit
	-- v8: opts.big renders at crit size (charge T2 hits) without
	-- the "CRIT" prefix / crit color unless it really critted
	local big = crit or (opts and opts.big)
	local gui = Instance.new("BillboardGui")
	gui.Name = "DamageNumber"
	gui.Size = UDim2.new(3, 0, 1, 0)
	gui.StudsOffset = Vector3.new(math.random(-8, 8) / 10, 4.6 + ((opts and opts.yOff) or 0), 0)
	gui.AlwaysOnTop = true
	gui.Parent = root
	local label = makeLabel(gui, "Amount", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
		(crit and "CRIT " or "") .. tostring(math.floor(amount + 0.5)),
		big and 27 or ((opts and opts.small) and 14 or 20),
		(opts and opts.color) or (crit and Color3.fromRGB(255, 140, 40)
			or Color3.fromRGB(255, 230, 120)))
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

-- display (v7, optional): number options for spawnDamageNumber;
-- may also carry { elemAmount = n, elemColor = c } to show a second,
-- smaller elemental-component number under the main one.
local function damageEnemy(model, amount, attacker, knockbackDir, display)
	local data = enemies[model]
	if not data then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	if attacker then data.lastDamager = attacker.UserId end
	humanoid:TakeDamage(amount)
	-- v6: training dummies silently reset HP after every hit -- the
	-- damage number / flash / sparks still show, they just never die
	if data.isDummy then
		humanoid.Health = humanoid.MaxHealth
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		spawnDamageNumber(root, amount, display)
		if display and display.elemAmount and display.elemAmount >= 1 then
			spawnDamageNumber(root, display.elemAmount,
				{ small = true, color = display.elemColor, yOff = -1.3 })
		end
		spawnSparks(root.Position + Vector3.new(0, 1, 0))
		playSfx("Hit", root, true)
	end
	-- v7 D2: Lightning Enchanted elites zap their attacker on hit
	if data.enchant == "Lightning" and attacker and V7.lightningZap then
		V7.lightningZap(model, data, attacker)
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
	local isElite = (not isBoss) and not suppressElite and (math.random() < ELITE_CHANCE)
	-- v7 D2: elites roll one enchantment -- Fire / Lightning /
	-- Cold (death effects), Extra Strong (+60% damage), Extra
	-- Fast (+45% speed). The name prefix advertises it.
	local enchant = nil
	if isElite then
		local er = math.random()
		enchant = er < 0.2 and "Fire" or er < 0.4 and "Lightning" or er < 0.6 and "Cold"
			or er < 0.8 and "Strong" or "Fast"
	end
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
		displayName = (enchant and (enchant .. " Enchanted ") or "") .. "Elite " .. kind
	end
	makeHealthBar(model, root, displayName, def.scale)
	local rewardMult = isElite and 3 or 1
	local data = {
		kind = kind,
		damage = math.floor(def.damage * (0.8 + 0.2 * difficultyScale) * (isElite and 1.5 or 1)
			* (enchant == "Strong" and 1.6 or 1)),
		speed = def.speed * (enchant == "Fast" and 1.45 or 1),
		enchant = enchant, -- v7: nil | "Fire" | "Lightning" | "Cold" | "Strong" | "Fast"
		nightmare = false, -- v7: set by startWave on Nightmare difficulty
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
		-- v6: zone tag drives wave counting + leashing. "Dungeon"
		-- enemies count toward wave clear; "Field" wildlife and
		-- "Town" dummies never do.
		zone = "Dungeon",
		isDummy = false,
		isField = false,
		home = nil,
		summoned = false,
		-- v6 AI state machine (see the behavior section below)
		ai = {
			busy = false,          -- a dash / leap task owns movement
			touchCd = 0,           -- contact / melee damage cooldown
			leapNext = os.clock() + 2 + math.random() * 2,
			dashNext = os.clock() + 1.5 + math.random() * 1.5,
			strafeNext = 0,
			strafeUntil = 0,
			strafeDir = 1,
			recoverUntil = 0,
			shootNext = os.clock() + 1.2 + math.random(),
			slamNext = os.clock() + 4 + math.random() * 3,
			volleyNext = os.clock() + 3 + math.random() * 2,
			summoned66 = false,
			summoned33 = false,
			enraged = false,
		},
	}
	enemies[model] = data
	-- v7: elites wear a dark aura ring so a champion pack reads at
	-- a glance
	if isElite then
		local ring = Instance.new("Part")
		ring.Name = "EliteAura"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.25, 6.5 * def.scale, 6.5 * def.scale)
		ring.CFrame = root.CFrame * CFrame.new(0, -2.05, 0) * CFrame.Angles(0, 0, math.rad(90))
		ring.Color = Color3.fromRGB(90, 20, 130)
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.45
		ring.CanCollide = false
		ring.Parent = model
		weldTo(ring, root)
	end
	-- v7: spawn poof -- a dark smoke burst + the visual fades in
	-- over 0.3s instead of popping into existence
	do
		for _ = 1, 5 do
			local puff = Instance.new("Part")
			puff.Name = "SpawnSmoke"
			puff.Shape = Enum.PartType.Ball
			puff.Size = Vector3.new(1.4, 1.4, 1.4)
			puff.Color = Color3.fromRGB(45, 40, 55)
			puff.Material = Enum.Material.SmoothPlastic
			puff.CanCollide = false
			puff.Position = root.Position + Vector3.new(
				math.random(-15, 15) / 10, math.random(-5, 15) / 10, math.random(-15, 15) / 10)
			puff.Parent = Workspace
			puff.AssemblyLinearVelocity = Vector3.new(
				math.random(-4, 4), math.random(3, 7), math.random(-4, 4))
			Debris:AddItem(puff, 0.5)
		end
		local fadeParts = {}
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("BasePart") and p ~= root then
				fadeParts[p] = p.Transparency
				p.Transparency = 1
			end
		end
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 0.3 do
				local a = (os.clock() - t0) / 0.3
				for p, orig in pairs(fadeParts) do
					if p.Parent then p.Transparency = orig + (1 - orig) * (1 - a) end
				end
				task.wait(0.03)
			end
			for p, orig in pairs(fadeParts) do
				if p.Parent then p.Transparency = orig end
			end
		end)
	end
	humanoid.Died:Connect(function()
		local dRoot = model:FindFirstChild("HumanoidRootPart")
		if dRoot then playSfx("Death", dRoot) end
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
-- v6: TRAINING DUMMIES + FIELD WILDLIFE spawners
--====================================================================
-- A training dummy is an entry in the enemies table (so every
-- weapon / skill damage path works on it and shows damage numbers,
-- hit flash and sparks) flagged isDummy: damageEnemy tops its HP
-- back up after every hit, onEnemyDeath pays nothing, the AI loop
-- ignores it, and aliveEnemyCount never counts it.
local function spawnTrainingDummy(position)
	local model = Instance.new("Model")
	model.Name = "TrainingDummy"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(position.X, position.Y + 2.6, position.Z)
	root.Transparency = 1
	root.CanCollide = true
	root.Anchored = true
	root.Parent = model
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 100000
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model
	model.PrimaryPart = root
	model.Parent = enemiesFolder
	local function add(name, size, offset, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then p.Shape = shape end
		p.CFrame = root.CFrame * CFrame.new(offset)
		p.Anchored = true
		p.CanCollide = false
		p.Parent = model
		return p
	end
	local hay = Color3.fromRGB(216, 182, 92)
	-- round base + post + crossbar arms + stuffed body + head
	local base = add("Base", Vector3.new(0.5, 3.6, 3.6), Vector3.new(0, -2.35, 0),
		Color3.fromRGB(105, 100, 95), Enum.Material.Slate, Enum.PartType.Cylinder)
	base.CFrame = root.CFrame * CFrame.new(0, -2.35, 0) * CFrame.Angles(0, 0, math.rad(90))
	add("Post", Vector3.new(0.55, 3.4, 0.55), Vector3.new(0, -0.6, 0),
		Color3.fromRGB(100, 70, 40), Enum.Material.Wood)
	add("Crossbar", Vector3.new(3.6, 0.45, 0.45), Vector3.new(0, 0.75, 0),
		Color3.fromRGB(100, 70, 40), Enum.Material.Wood)
	local body = add("Body", Vector3.new(2.1, 2.6, 1.3), Vector3.new(0, 0.1, 0),
		hay, Enum.Material.Fabric)
	add("Belt", Vector3.new(2.25, 0.4, 1.45), Vector3.new(0, -0.7, 0),
		Color3.fromRGB(140, 60, 45), Enum.Material.Leather)
	add("HeadVisual", Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 2, 0),
		hay, Enum.Material.Fabric, Enum.PartType.Ball)
	for _, ex in ipairs({-0.3, 0.3}) do
		add("Eye", Vector3.new(0.18, 0.18, 0.1), Vector3.new(ex, 2.1, -0.66),
			Color3.fromRGB(20, 20, 20), Enum.Material.Neon, Enum.PartType.Ball)
	end
	local data = {
		kind = "Dummy",
		damage = 0,
		speed = 0,
		xp = 0,
		gold = 0,
		lastAttack = 0,
		lastDamager = nil,
		isBoss = false,
		isElite = false,
		flashing = false,
		bodyPart = body,
		baseBodySize = body.Size,
		phase = 0,
		zone = "Town",
		isDummy = true,
		isField = false,
		home = nil,
		summoned = false,
		ai = { busy = false, touchCd = 0 },
	}
	enemies[model] = data
	makeHealthBar(model, root, "Training Dummy", 1)
	return model
end

-- Field wildlife (v8: authored monster CAMPS): a normal enemy
-- (full XP/gold on death) tagged as Field zone so waves ignore
-- it; leashed to its camp home in the AI and respawned there.
V8.spawnFieldMonster = function(kind, homePosition)
	local model = spawnEnemy(kind, homePosition, 0.8)
	if model then
		local data = enemies[model]
		if data then
			data.zone = "Field"
			data.isField = true
			data.home = homePosition
		end
	end
	return model
end

spawnFieldSlime = function(homePosition)
	return V8.spawnFieldMonster("Slime", homePosition)
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
	-- v6: only dungeon-zone, non-dummy enemies gate wave progress
	-- (field wildlife and town dummies must never block a wave clear)
	local n = 0
	for _, data in pairs(enemies) do
		if not data.isDummy and data.zone ~= "Field" then
			n = n + 1
		end
	end
	return n
end

-- v8: wave spawns follow the authored room layout (coords are
-- relative to DUNGEON_CENTER; see MAP_DESIGN_V8.md). Waves 1-2
-- fill the entrance hall, wave 3 splits between the lava and
-- crystal chambers, wave 4 mixes hub + corridors + chambers,
-- boss waves (and their adds) spawn inside the boss arena.
local function dungeonSpawnPosition()
	local phase = currentWave % 5
	local r = math.random()
	local cz = DUNGEON_CENTER.Z
	if phase == 1 or phase == 2 then
		return Vector3.new(math.random(-24, 24), 0, cz + math.random(58, 80))
	elseif phase == 3 then
		if r < 0.5 then
			return Vector3.new(math.random(-88, -62), 0, cz + math.random(-26, 18))
		else
			return Vector3.new(math.random(62, 88), 0, cz + math.random(-26, 18))
		end
	elseif phase == 4 then
		if r < 0.3 then
			return Vector3.new(math.random(-16, 16), 0, cz + math.random(-9, 5))
		elseif r < 0.5 then
			return Vector3.new(math.random(-52, -26), 0, cz + math.random(-4, 4))
		elseif r < 0.7 then
			return Vector3.new(math.random(26, 52), 0, cz + math.random(-4, 4))
		elseif r < 0.85 then
			return Vector3.new(math.random(-88, -62), 0, cz + math.random(-26, 18))
		else
			return Vector3.new(math.random(62, 88), 0, cz + math.random(-26, 18))
		end
	else
		return Vector3.new(math.random(-34, 34), 0, cz + math.random(-94, -64))
	end
end

local function startWave(wave)
	waveActive = true
	currentWave = wave
	local scale = 1 + (wave - 1) * 0.12 + waveCycle * 0.35
	local isBossWave = (wave % 5 == 0)
	local nightmare = (V7.difficulty == "Nightmare")
	-- v7: per-spawn tuning -- Nightmare multipliers (HP x2.2,
	-- damage x1.5, XP/gold x1.8, flagged for better drops) and D2
	-- champion packs: a wave-spawned elite brings 2 normal minions
	-- of its own kind (minions can never roll elite themselves).
	local function tune(model)
		if not model then return end
		local d = enemies[model]
		if not d then return end
		if nightmare then
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.MaxHealth = math.floor(hum.MaxHealth * 2.2)
				hum.Health = hum.MaxHealth
				refreshHealthBar(model)
			end
			d.damage = math.floor(d.damage * 1.5)
			d.xp = math.floor(d.xp * 1.8)
			d.gold = math.floor(d.gold * 1.8)
			d.nightmare = true
		end
		if d.isElite and not d.isBoss then
			suppressElite = true
			for _ = 1, 2 do
				local minion = spawnEnemy(d.kind, dungeonSpawnPosition(), scale)
				if minion then tune(minion) end
			end
			suppressElite = false
		end
	end
	if isBossWave then
		-- v8: the boss spawns in the boss arena (rel z -80)
		tune(spawnEnemy("SkeletonKing", Vector3.new(DUNGEON_CENTER.X, 0, DUNGEON_CENTER.Z - 80), scale))
		for _ = 1, 3 do tune(spawnEnemy("Skeleton", dungeonSpawnPosition(), scale)) end
		announce("Wave " .. wave .. " -- BOSS!" .. (nightmare and " (NIGHTMARE)" or ""), 4)
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
			tune(spawnEnemy(kind, dungeonSpawnPosition(), scale))
		end
		announce("Wave " .. wave .. "!" .. (nightmare and " (NIGHTMARE)" or ""), 3)
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
					-- v7 D2: clearing a boss wave unlocks NIGHTMARE
					-- at the gate arch for the rest of the session
					if not V7.nightmareUnlocked then
						V7.nightmareUnlocked = true
						announce("BOSS DOWN! Bonus " .. bonus .. " gold. NIGHTMARE dungeon unlocked at the gate arch (key F)!", 6)
					else
						announce("BOSS DOWN! Bonus " .. bonus .. " gold. Dungeon grows stronger...", 5)
					end
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
-- ENEMY AI (v6): per-type behavior state machines. Enemies no
-- longer just walk into the player:
--   Slime    -- hopper; telegraphed LEAP attack every ~3.5s
--   Goblin   -- fast approach, wind-up + DASH strike, strafes
--   Skeleton -- ranged KITER, bone projectiles, weak melee + retreat
--   Elites   -- periodic telegraphed ground SLAM
--   Boss     -- big SLAM, HP-threshold SUMMONS, bone VOLLEY, ENRAGE
-- All enemy damage to players flows through damagePlayer() below,
-- so Armor points, chest %, class reduction and Thorns all apply
-- exactly as they did to the old contact hits. Telegraphs are flat
-- pulsing red discs: leave the disc before it detonates to dodge.
--====================================================================

-- NOTE: these helpers live in ONE table on purpose -- the main
-- chunk is close to Luau's 200-local-register limit.
local AI = { projectiles = {} }

-- Central enemy -> player damage path (extracted from the old
-- contact-hit code so every attack type shares it).
AI.damagePlayer = function(player, amount, sourceModel)
	local character = player and player.Character
	local phrp = getHRP(character)
	local phum = getHumanoid(character)
	if not phrp or not phum or phum.Health <= 0 then return end
	local armor = getStat(player, "Stats", "Armor")
	local armorPoints = armor and math.clamp(armor.Value, 0, MAX_ARMOR) or 0
	local gearDEF = getStat(player, "Stats", "GearDEF")
	local reduction = ARMOR_PER_POINT * armorPoints
		+ (gearDEF and gearDEF.Value or 0) / 100
	reduction = math.min(reduction, 0.75)
	local incoming = amount * (1 - reduction) * classIncomingMul(player)
	-- v7: Frost Warden 3pc frost shield soaks damage before HP
	local fx = playerFx[player]
	local cs = combatStats[player]
	if fx and fx.shield and fx.shield > 0 and incoming > 0 then
		local absorbed = math.min(fx.shield, incoming)
		fx.shield = fx.shield - absorbed
		incoming = incoming - absorbed
	end
	phum:TakeDamage(incoming)
	-- v8: a single hit costing more than 15% of MaxHP breaks a
	-- held charge (charging is exposed -- Shining Soul risk/reward)
	if incoming > phum.MaxHealth * 0.15 and V8.cancelCharge then
		V8.cancelCharge(player, true)
	end
	playSfx("Hurt", phrp, true)
	-- v7: Warriors build Rage when hit (+3); any hit refreshes
	-- the combat timer that gates Rage decay
	if fx then fx.lastCombat = os.clock() end
	local classVal = getStat(player, "Stats", "Class")
	if classVal and classVal.Value == "Warrior" then
		local rage = getStat(player, "Stats", "Rage")
		if rage then rage.Value = math.min(100, rage.Value + 3) end
	end
	-- v7: Frost Warden 3pc -- taking a hit can freeze the attacker
	-- for 0.8s and raise a fresh frost shield (12s cooldown)
	if sourceModel and cs and cs.frostGuard and fx then
		local now = os.clock()
		if now >= (fx.shieldCd or 0) and math.random() < 0.25 then
			fx.shieldCd = now + 12
			fx.shield = phum.MaxHealth * 0.15
			local sdata = enemies[sourceModel]
			if sdata then sdata.frozenUntil = now + 0.8 end
		end
	end
	-- Thorns Aura (v5): reflect a fraction of the attacker's own
	-- damage stat back at it (melee-range sources only).
	if sourceModel then
		local sdata = enemies[sourceModel]
		local reflect = thornsReflectFor(player)
		if sdata and reflect > 0 then
			damageEnemy(sourceModel, sdata.damage * reflect, player, nil)
		end
	end
end

-- Expanding shockwave ring used by slams (local twin of ringFX,
-- which is defined later in the file and out of scope here).
AI.slamRingFX = function(position, radius, color)
	local ring = Instance.new("Part")
	ring.Name = "SlamRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.35, 2, 2)
	ring.CFrame = CFrame.new(position.X, 0.45, position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.25
	ring.Anchored = true
	ring.CanCollide = false
	ring.Parent = Workspace
	task.spawn(function()
		local t0 = os.clock()
		while ring.Parent do
			local t = (os.clock() - t0) / 0.4
			if t >= 1 then break end
			local d = 2 + (radius * 2 - 2) * t
			ring.Size = Vector3.new(0.35, d, d)
			ring.Transparency = 0.25 + 0.75 * t
			task.wait(0.03)
		end
		ring:Destroy()
	end)
end

-- Telegraph disc: pulses red at `position` for `duration`, then
-- detonates -- every player still inside takes `amount` damage
-- from `sourceModel`. Fully avoidable by walking out.
AI.spawnTelegraph = function(position, radius, duration, amount, sourceModel)
	local disc = Instance.new("Part")
	disc.Name = "Telegraph"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.22, radius * 2, radius * 2)
	disc.CFrame = CFrame.new(position.X, 0.42, position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	disc.Color = Color3.fromRGB(255, 60, 50)
	disc.Material = Enum.Material.Neon
	disc.Transparency = 0.55
	disc.Anchored = true
	disc.CanCollide = false
	disc.Parent = Workspace
	task.spawn(function()
		local t0 = os.clock()
		while disc.Parent and os.clock() - t0 < duration do
			local pulse = 0.5 + 0.5 * math.sin(os.clock() * 14)
			disc.Transparency = 0.35 + 0.35 * pulse
			task.wait(0.04)
		end
		if disc.Parent then disc:Destroy() end
	end)
	task.delay(duration, function()
		AI.slamRingFX(position, radius, Color3.fromRGB(255, 90, 60))
		spawnSparks(position + Vector3.new(0, 1, 0))
		spawnSparks(position + Vector3.new(0, 2, 0))
		for _, player in ipairs(Players:GetPlayers()) do
			local phrp = getHRP(player.Character)
			local phum = getHumanoid(player.Character)
			if phrp and phum and phum.Health > 0 then
				if horizontalDistance(phrp.Position, position) <= radius
					and math.abs(phrp.Position.Y - position.Y) < 9 then
					AI.damagePlayer(player, amount, nil)
				end
			end
		end
	end)
end

--====================================================================
-- ENEMY PROJECTILES: physical parts stepped in a fast loop with
-- per-step distance checks (dodgeable, no tunneling at 0.05s steps)
--====================================================================

AI.spawnEnemyProjectile = function(fromPos, targetPos, speed, damage, sourceModel, color)
	local dir = targetPos - fromPos
	if dir.Magnitude < 0.1 then return end
	dir = dir.Unit
	local p = Instance.new("Part")
	p.Name = "EnemyProjectile"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(2.4, 0.38, 0.38)
	p.Color = color or Color3.fromRGB(240, 240, 230)
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CFrame = CFrame.lookAt(fromPos, fromPos + dir) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = Workspace
	table.insert(AI.projectiles, {
		part = p,
		vel = dir * speed,
		damage = damage,
		source = sourceModel,
		born = os.clock(),
		from = fromPos,
	})
end

AI.projectileLoop = function()
	while true do
		task.wait(0.05)
		for i = #AI.projectiles, 1, -1 do
			local pr = AI.projectiles[i]
			local part = pr.part
			local dead = false
			if not part or not part.Parent then
				dead = true
			else
				part.Position = part.Position + pr.vel * 0.05
				local pos = part.Position
				if os.clock() - pr.born > 3 or pos.Y < 0.2
					or horizontalDistance(pos, pr.from) > 75 then
					dead = true
				else
					for _, player in ipairs(Players:GetPlayers()) do
						local phrp = getHRP(player.Character)
						local phum = getHumanoid(player.Character)
						if phrp and phum and phum.Health > 0 then
							local d = (phrp.Position + Vector3.new(0, 1.5, 0) - pos).Magnitude
							if d < 3.2 then
								AI.damagePlayer(player, pr.damage, pr.source)
								dead = true
								break
							end
						end
					end
				end
				if dead then part:Destroy() end
			end
			if dead then table.remove(AI.projectiles, i) end
		end
	end
end

--====================================================================
-- BEHAVIOR HELPERS
--====================================================================
-- Nearest living player to `fromPos`. Field wildlife passes its
-- home + a leash radius so it only engages players near its home.
AI.nearestPlayer = function(fromPos, maxDist, anchorPos, anchorRadius)
	local bestPlayer, bestDist = nil, maxDist
	for _, player in ipairs(Players:GetPlayers()) do
		local phrp = getHRP(player.Character)
		local phum = getHumanoid(player.Character)
		if phrp and phum and phum.Health > 0 then
			if anchorPos and horizontalDistance(phrp.Position, anchorPos) > anchorRadius then
				-- player outside the leash anchor: not a target
			else
				local d = horizontalDistance(fromPos, phrp.Position)
				if d < bestDist then
					bestDist = d
					bestPlayer = player
				end
			end
		end
	end
	return bestPlayer, bestDist
end

AI.flatDir = function(fromPos, toPos)
	local d = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
	if d.Magnitude < 0.05 then return Vector3.new(0, 0, -1) end
	return d.Unit
end

--====================================================================
-- SLIME: hopper. Hops toward the player (hop velocity + the squash
-- system), contact damage only right after landing near the player
-- (0.8s gate), and a telegraphed LEAP every ~3.5s in range.
--====================================================================
AI.behaveSlime = function(model, data, root, humanoid, target, dist, now)
	local ai = data.ai
	local myPos = root.Position
	if target then
		local phrp = getHRP(target.Character)
		-- LEAP ATTACK: crouch telegraph, then arc onto the player
		if dist <= 17 and dist > 4 and now >= ai.leapNext and not ai.busy then
			ai.busy = true
			ai.leapNext = now + 3.5
			humanoid:MoveTo(myPos)
			-- crouch: squash the body flat for 0.4s
			if data.bodyPart and data.baseBodySize then
				local bp, bs = data.bodyPart, data.baseBodySize
				bp.Size = Vector3.new(bs.X * 1.25, bs.Y * 0.5, bs.Z * 1.25)
			end
			local targetPos = phrp.Position
			task.delay(0.4, function()
				if not model.Parent or not enemies[model] then return end
				local startPos = root.Position
				local dest = Vector3.new(targetPos.X, startPos.Y, targetPos.Z)
				local t0 = os.clock()
				local dur = 0.55
				task.spawn(function()
					while model.Parent and enemies[model] and os.clock() - t0 < dur do
						local t = (os.clock() - t0) / dur
						local pos = startPos:Lerp(dest, t)
						pos = pos + Vector3.new(0, math.sin(t * math.pi) * 6, 0)
						root.CFrame = CFrame.new(pos) * (root.CFrame - root.CFrame.Position)
						task.wait(0.03)
					end
					ai.busy = false
					if not model.Parent or not enemies[model] then return end
					-- landing: damage anyone within 4 studs, once
					for _, player in ipairs(Players:GetPlayers()) do
						local p2 = getHRP(player.Character)
						local h2 = getHumanoid(player.Character)
						if p2 and h2 and h2.Health > 0
							and horizontalDistance(p2.Position, dest) <= 4 then
							AI.damagePlayer(player, data.damage, model)
						end
					end
					ai.touchCd = now + 0.8
				end)
			end)
			return
		end
		if ai.busy then return end
		if dist > 4 then
			humanoid:MoveTo(phrp.Position)
			-- little hop while travelling (lands -> squash reads as a hop)
			if not ai.hopAt or now - ai.hopAt > 0.85 then
				ai.hopAt = now
				pcall(function()
					root.AssemblyLinearVelocity = Vector3.new(
						root.AssemblyLinearVelocity.X, 11, root.AssemblyLinearVelocity.Z)
				end)
			end
		else
			humanoid:MoveTo(myPos)
			-- contact damage, gated to once per 0.8s (no touch drain)
			if now >= ai.touchCd then
				ai.touchCd = now + 0.8
				AI.damagePlayer(target, data.damage, model)
			end
		end
	else
		if ai.busy then return end
		-- field slimes drift back home when nobody is near
		if data.isField and data.home
			and horizontalDistance(myPos, data.home) > 3 then
			humanoid:MoveTo(data.home)
		else
			humanoid:MoveTo(myPos)
		end
	end
end

--====================================================================
-- GOBLIN: dasher. Fast approach with occasional sideways strafes;
-- at 10-18 studs it winds up (flash + lean) and DASHES at the
-- player, then recovers slowly for 1s.
--====================================================================
AI.behaveGoblin = function(model, data, root, humanoid, target, dist, now)
	local ai = data.ai
	local myPos = root.Position
	if ai.busy then return end
	if not target then
		humanoid:MoveTo(myPos)
		return
	end
	local phrp = getHRP(target.Character)
	-- recovering from a dash: crawl at 40% speed
	if now < ai.recoverUntil then
		humanoid.WalkSpeed = data.speed * 0.4 * (ai.slowFactor or 1)
		humanoid:MoveTo(phrp.Position)
		return
	end
	-- DASH: wind-up then burst
	if dist >= 10 and dist <= 18 and now >= ai.dashNext then
		ai.busy = true
		ai.dashNext = now + 2.8 + math.random() * 1.2
		humanoid:MoveTo(myPos)
		flashEnemy(model, data) -- white flash telegraph
		local targetPos = phrp.Position
		task.delay(0.35, function()
			if not model.Parent or not enemies[model] then return end
			local startPos = root.Position
			local dest = Vector3.new(targetPos.X, startPos.Y, targetPos.Z)
			local dashDist = (dest - startPos).Magnitude
			local dur = math.max(0.18, dashDist / 65)
			local t0 = os.clock()
			task.spawn(function()
				while model.Parent and enemies[model] and os.clock() - t0 < dur do
					local t = (os.clock() - t0) / dur
					local pos = startPos:Lerp(dest, t)
					root.CFrame = CFrame.new(pos) * (root.CFrame - root.CFrame.Position)
					task.wait(0.03)
				end
				ai.busy = false
				ai.recoverUntil = os.clock() + 1
				if not model.Parent or not enemies[model] then return end
				local p2 = getHRP(target.Character)
				local h2 = getHumanoid(target.Character)
				if p2 and h2 and h2.Health > 0
					and horizontalDistance(p2.Position, dest) <= 4.5 then
					AI.damagePlayer(target, data.damage, model)
					ai.touchCd = os.clock() + 1
				end
			end)
		end)
		return
	end
	if dist > 4 then
		-- strafe sideways sometimes instead of running straight in
		if now >= ai.strafeNext then
			ai.strafeNext = now + 1.6
			if math.random() < 0.3 then
				ai.strafeUntil = now + 0.6
				ai.strafeDir = (math.random() < 0.5) and 1 or -1
			end
		end
		if now < ai.strafeUntil then
			local dir = AI.flatDir(myPos, phrp.Position)
			local side = Vector3.new(-dir.Z, 0, dir.X) * ai.strafeDir
			humanoid:MoveTo(phrp.Position + side * 9)
		else
			humanoid:MoveTo(phrp.Position)
		end
	else
		humanoid:MoveTo(myPos)
		if now >= ai.touchCd then
			ai.touchCd = now + 1
			AI.damagePlayer(target, data.damage, model)
		end
	end
end

--====================================================================
-- SKELETON: ranged kiter. Holds 22-30 studs, strafes slowly,
-- shoots a bone every 2.2s; weak melee + retreat up close.
--====================================================================
AI.behaveSkeleton = function(model, data, root, humanoid, target, dist, now)
	local ai = data.ai
	local myPos = root.Position
	if not target then
		humanoid:MoveTo(myPos)
		return
	end
	local phrp = getHRP(target.Character)
	local dir = AI.flatDir(myPos, phrp.Position)
	if dist < 6 then
		-- too close: weak swipe, then back off
		if now >= ai.touchCd then
			ai.touchCd = now + 1.1
			AI.damagePlayer(target, math.floor(data.damage * 0.6), model)
		end
		humanoid:MoveTo(myPos - dir * 12)
	elseif dist < 22 then
		humanoid:MoveTo(myPos - dir * 8) -- back away to range
	elseif dist > 30 then
		humanoid:MoveTo(phrp.Position) -- close in to range
	else
		-- in the pocket: slow sideways orbit
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local orbit = ((math.floor(now * 0.5 + data.phase) % 2) == 0) and 1 or -1
		humanoid:MoveTo(phrp.Position - dir * 26 + side * orbit * 7)
	end
	-- bone shot
	if dist <= 44 and now >= ai.shootNext then
		ai.shootNext = now + 2.2
		local from = myPos + Vector3.new(0, 3.2, 0)
		local to = phrp.Position + Vector3.new(0, 2.2, 0)
		AI.spawnEnemyProjectile(from, to, 55, math.floor(data.damage * 0.8), model)
	end
end

--====================================================================
-- BOSS (Skeleton King): chases + heavy melee, plus SLAM (r10),
-- SUMMONS at 66% / 33% HP (adds capped at 4, half rewards), bone
-- VOLLEY fan, and ENRAGE below 30% HP.
--====================================================================
AI.bossSummon = function(model, data, root)
	local adds = 0
	for _, d in pairs(enemies) do
		if d.summoned and not d.isDummy then adds = adds + 1 end
	end
	local want = math.random(2, 3)
	local spawned = 0
	for i = 1, want do
		if adds + spawned >= 4 then break end
		local kind = (i % 2 == 0) and "Slime" or "Skeleton"
		local side = (i % 2 == 0) and 6 or -6
		local m = spawnEnemy(kind, root.Position + Vector3.new(side, 0, 3), 1)
		if m then
			local d = enemies[m]
			if d then
				d.summoned = true
				d.xp = math.floor(d.xp * 0.5)
				d.gold = math.floor(d.gold * 0.5)
			end
			spawned = spawned + 1
			spawnSparks(root.Position + Vector3.new(side, 2, 3))
		end
	end
	if spawned > 0 then
		announce("The Skeleton King summons minions!", 3)
	end
end

AI.behaveBoss = function(model, data, root, humanoid, target, dist, now)
	local ai = data.ai
	local myPos = root.Position
	local frac = humanoid.Health / humanoid.MaxHealth
	-- summons at HP thresholds
	if not ai.summoned66 and frac <= 0.66 then
		ai.summoned66 = true
		AI.bossSummon(model, data, root)
	end
	if not ai.summoned33 and frac <= 0.33 then
		ai.summoned33 = true
		AI.bossSummon(model, data, root)
	end
	-- enrage below 30%
	if not ai.enraged and frac <= 0.30 then
		ai.enraged = true
		data.speed = data.speed * 1.4
		for _, p in ipairs(model:GetChildren()) do
			if p.Name == "EyeSocket" then
				p.Color = Color3.fromRGB(255, 40, 40)
				p.Material = Enum.Material.Neon
			end
		end
		local gui = root:FindFirstChild("HealthBar")
		if gui then
			local nl = gui:FindFirstChild("NameLabel")
			if nl then nl.Text = nl.Text .. " (Enraged)" end
		end
		announce("The Skeleton King is ENRAGED!", 3)
	end
	local cdMul = ai.enraged and 0.65 or 1
	if not target then
		humanoid:MoveTo(myPos)
		return
	end
	local phrp = getHRP(target.Character)
	-- SLAM on the target's position
	if dist <= 26 and now >= ai.slamNext then
		ai.slamNext = now + 7 * cdMul
		AI.spawnTelegraph(phrp.Position, 10, 1.0, math.floor(data.damage * 1.6), model)
	end
	-- bone VOLLEY: fan of 3
	if dist <= 46 and now >= ai.volleyNext then
		ai.volleyNext = now + 5 * cdMul
		local from = myPos + Vector3.new(0, 4.5, 0)
		local baseDir = AI.flatDir(myPos, phrp.Position)
		for _, yaw in ipairs({ -14, 0, 14 }) do
			local d = CFrame.Angles(0, math.rad(yaw), 0):VectorToWorldSpace(baseDir)
			AI.spawnEnemyProjectile(from, from + d * 30, 55,
				math.floor(data.damage * 0.7), model,
				Color3.fromRGB(255, 230, 180))
		end
	end
	-- chase + heavy melee
	if dist > 6 then
		humanoid:MoveTo(phrp.Position)
	else
		humanoid:MoveTo(myPos)
		if now >= ai.touchCd then
			ai.touchCd = now + 1.2
			AI.damagePlayer(target, data.damage, model)
		end
	end
end

--====================================================================
-- ELITE SLAM: any non-boss elite periodically telegraph-slams the
-- nearest player's position (r7, 0.7s warning, ~6s cooldown).
--====================================================================
AI.eliteSlamCheck = function(model, data, target, dist, now)
	local ai = data.ai
	if not target or dist > 20 or now < ai.slamNext then return end
	ai.slamNext = now + 6
	local phrp = getHRP(target.Character)
	if phrp then
		AI.spawnTelegraph(phrp.Position, 7, 0.7, math.floor(data.damage * 1.4), model)
	end
end

--====================================================================
-- MAIN AI LOOP (0.25s decisions; projectiles run in their own
-- 0.05s loop, started at the bottom of the file)
--====================================================================
local function aiLoop()
	while true do
		task.wait(0.25)
		local now = os.clock()
		for model, data in pairs(enemies) do
			local root = model:FindFirstChild("HumanoidRootPart")
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				if data.isDummy then
					-- dummies never act; HP is reset in damageEnemy
				else
					-- slime squash-and-stretch (suppressed mid-leap-
					-- crouch is fine: the leap task restores via Size)
					if data.kind == "Slime" and data.bodyPart and data.baseBodySize
						and not data.ai.busy then
						local bp = data.bodyPart
						if bp.Parent then
							local w = math.sin(now * 6 + data.phase)
							local bs = data.baseBodySize
							bp.Size = Vector3.new(
								bs.X * (1 - 0.07 * w), bs.Y * (1 + 0.16 * w), bs.Z * (1 - 0.07 * w))
						end
					end
					-- v7: goblin / skeleton idle "breathing" (subtle
					-- torso scale) so they do not stand like statues
					if (data.kind == "Goblin" or data.kind == "Skeleton")
						and data.bodyPart and data.baseBodySize and not data.ai.busy then
						local bp = data.bodyPart
						if bp.Parent then
							local w = math.sin(now * 2.2 + data.phase)
							local bs = data.baseBodySize
							bp.Size = Vector3.new(bs.X, bs.Y * (1 + 0.025 * w), bs.Z)
						end
					end
					-- Frost Nova slow (v5) + v7 freeze (full stop)
					local slowFactor = 1
					if data.slowUntil and now < data.slowUntil then
						slowFactor = data.slowFactor or 1
					end
					if data.frozenUntil and now < data.frozenUntil then
						slowFactor = 0
					end
					data.ai.slowFactor = slowFactor
					humanoid.WalkSpeed = data.speed * slowFactor
					-- target selection (field wildlife is leashed)
					local target, dist
					if data.isField and data.home then
						target, dist = AI.nearestPlayer(root.Position, 60, data.home, 26)
						if target and horizontalDistance(root.Position, data.home) > 20 then
							-- dragged too far from home: disengage
							target = nil
						end
					else
						target, dist = AI.nearestPlayer(root.Position, 90)
					end
					if data.isBoss then
						AI.behaveBoss(model, data, root, humanoid, target, dist or 999, now)
					elseif data.kind == "Slime" then
						AI.behaveSlime(model, data, root, humanoid, target, dist or 999, now)
					elseif data.kind == "Goblin" then
						AI.behaveGoblin(model, data, root, humanoid, target, dist or 999, now)
					elseif data.kind == "Skeleton" then
						AI.behaveSkeleton(model, data, root, humanoid, target, dist or 999, now)
					else
						humanoid:MoveTo(root.Position)
					end
					if data.isElite and not data.isBoss then
						AI.eliteSlamCheck(model, data, target, dist or 999, now)
					end
					-- v8: pathfinding fallback for dungeon enemies
					-- wedged on room walls (field camps sit on open
					-- ground inside a leash and never need it)
					if target and data.zone == "Dungeon" and not data.ai.busy
						and V8.pathMove then
						V8.pathMove(model, data, root, humanoid, target, dist or 999, now)
					end
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
	addPart("Blade", "Part", Vector3.new(0.2, bladeLen, 0.62),
		Vector3.new(0, 0.72 + bladeLen / 2, 0), color, Enum.Material.Metal)
	addPart("BladeTip", "WedgePart", Vector3.new(0.2, 0.6, 0.62),
		Vector3.new(0, 0.72 + bladeLen + 0.3, 0), color, Enum.Material.Metal,
		CFrame.Angles(math.rad(-90), 0, 0))
	if tier >= 4 then
		local edge = addPart("EdgeGlow", "Part", Vector3.new(0.26, bladeLen, 0.68),
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
		if not rec then return end
		-- v7: Attack Speed affix divides the swing cooldown
		-- (hard floor 0.25s so swings never become a blur)
		local cs = combatStats[player]
		local swordCd = math.max(0.25,
			SWORD_COOLDOWN / (1 + (cs and cs.atkSpeed or 0)))
		if (now - (rec.sword or 0)) < swordCd then return end
		rec.sword = now
		local character = player.Character
		local hrp = getHRP(character)
		if not hrp then return end
		local level = getStat(player, "leaderstats", "Level")
		local tier = getStat(player, "Stats", "SwordTier")
		local power = getStat(player, "Stats", "Power")
		local gearATK = getStat(player, "Stats", "GearATK")
		local dmg = SWORD_BASE_DAMAGE
			+ ((level and level.Value or 1) - 1) * 2
			+ ((tier and tier.Value or 1) - 1) * 8
			+ (power and power.Value or 0)
			+ (gearATK and gearATK.Value or 0)
		dmg = dmg * classDamageMul(player, "melee") -- v5 class + War Cry
		playSfx("Swing", hrp, true)
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
		-- v7 class identity: the swing still auto-locks and sweeps,
		-- but WHO it hits is class business now. WARRIOR cleaves up
		-- to 3 enemies with 100/70/50% falloff (nearest first);
		-- every other class hits only the nearest enemy. All hits
		-- flow through V7.hitEnemy (crit / elements / procs / rage
		-- gain / Paladin holy stacks live there).
		local classVal = getStat(player, "Stats", "Class")
		local classId = classVal and classVal.Value or ""
		local inRange = {}
		for model, _ in pairs(enemies) do
			local eroot = model:FindFirstChild("HumanoidRootPart")
			if eroot then
				local toEnemy = eroot.Position - hrp.Position
				local dist = horizontalDistance(hrp.Position, eroot.Position)
				if dist <= SWORD_RANGE + 1.5 and toEnemy.Magnitude > 0.1 then
					table.insert(inRange, { model = model, dist = dist, dir = toEnemy.Unit })
				end
			end
		end
		table.sort(inRange, function(a, b) return a.dist < b.dist end)
		local hitFn = V7.hitEnemy or damageEnemy
		if classId == "Warrior" then
			local falloff = { 1, 0.7, 0.5 }
			for i = 1, math.min(3, #inRange) do
				local h = inRange[i]
				hitFn(h.model, dmg * falloff[i], player, h.dir,
					{ source = "Sword", rage = true })
			end
		elseif inRange[1] then
			local h = inRange[1]
			hitFn(h.model, dmg, player, h.dir, { source = "Sword", rage = true })
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
	handle.Color = Color3.fromRGB(136, 96, 54)
	handle.Material = Enum.Material.Wood
	handle.Parent = tool
	-- v7: the staff crown is a FLOATING CRYSTAL (tall Neon gem +
	-- white core) that bobs and spins above the shaft instead of a
	-- welded ball. It is Anchored and re-positioned every frame
	-- from the handle; hidden while the tool sits in the Backpack.
	local orb = Instance.new("Part")
	orb.Name = "Crystal"
	orb.Size = Vector3.new(1.45, 2.0, 1.45) -- v8: bigger star crystal
	orb.Shape = Enum.PartType.Ball
	orb.Color = Color3.fromRGB(255, 120, 215)
	orb.Material = Enum.Material.Neon
	orb.CanCollide = false
	orb.Anchored = true
	orb.CFrame = handle.CFrame * CFrame.new(0, 2.15, 0)
	orb.Parent = tool
	local core = Instance.new("Part")
	core.Name = "CrystalCore"
	core.Size = Vector3.new(0.6, 1.0, 0.6)
	core.Shape = Enum.PartType.Ball
	core.Color = Color3.fromRGB(255, 240, 220)
	core.Material = Enum.Material.Neon
	core.CanCollide = false
	core.Anchored = true
	core.Parent = tool
	local orbLight = Instance.new("PointLight")
	orbLight.Color = Color3.fromRGB(255, 140, 220)
	orbLight.Range = 11
	orbLight.Brightness = 1.5
	orbLight.Parent = orb
	task.spawn(function()
		local t0 = os.clock()
		while tool.Parent do
			if tool.Parent:IsA("Model") then -- equipped on a character
				local t = os.clock() - t0
				local cf = handle.CFrame
					* CFrame.new(0, 2.15 + math.sin(t * 2) * 0.12, 0)
					* CFrame.Angles(t * 0.9, t * 1.7, 0)
				orb.Transparency = 0
				core.Transparency = 0
				orb.CFrame = cf
				core.CFrame = cf
			else
				orb.Transparency = 1
				core.Transparency = 1
			end
			task.wait(0.03)
		end
	end)
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
		if not rec then return end
		-- v7: Attack Speed affix divides the cast cooldown (0.25s floor)
		local cs = combatStats[player]
		local fireCd = math.max(0.25,
			FIREBALL_COOLDOWN / (1 + (cs and cs.atkSpeed or 0)))
		if (now - (rec.fire or 0)) < fireCd then return end
		local mana = getStat(player, "Stats", "Mana")
		if not mana or mana.Value < FIREBALL_COST then return end
		local character = player.Character
		local hrp = getHRP(character)
		if not hrp then return end
		rec.fire = now
		mana.Value = mana.Value - FIREBALL_COST
		local level = getStat(player, "leaderstats", "Level")
		local firePower = getStat(player, "Stats", "Power")
		local fireGearATK = getStat(player, "Stats", "GearATK")
		local dmg = FIREBALL_BASE_DAMAGE + ((level and level.Value or 1) - 1) * 3
			+ (firePower and firePower.Value or 0)
			+ (fireGearATK and fireGearATK.Value or 0)
		dmg = dmg * classDamageMul(player, "spell") -- v5 class modifier
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
		-- v7: one bolt = the projectile below. Mages fire a BURST
		-- of three (see the dispatch after this function).
		local function fireBolt(boltDmg)
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
				local hitFn = V7.hitEnemy or damageEnemy
				hitFn(model, boltDmg, player, hrp.CFrame.LookVector,
					{ source = "Staff", element = "Fire" })
				ball:Destroy()
			elseif hit and hit.Anchored then
				hitDone = true
				ball:Destroy()
			end
		end)
		end
		-- v7 Mage identity: a 3-round BURST of smaller bolts (0.09s
		-- apart, 45% damage each) -- a fast staccato rhythm instead
		-- of one slow fireball. Other classes fire the single bolt.
		local classVal = getStat(player, "Stats", "Class")
		if classVal and classVal.Value == "Mage" then
			for i = 0, 2 do
				task.delay(i * 0.09, function()
					if tool.Parent then fireBolt(dmg * 0.45) end
				end)
			end
		else
			fireBolt(dmg)
		end
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
		playSfx("Drink", getHRP(player.Character))
	end)
	return tool
end

--====================================================================
-- EQUIPMENT SYSTEM (v4): rarity gear, bag + equip UI, worn visuals,
-- selectable BGM. Per-player state lives server-side in gearState;
-- the client only forwards button clicks via UIEvent (see the
-- UIClient LocalScript) and plays the BGM track it is told to.
--====================================================================
local MAX_INVENTORY = 24
local GEAR_SLOTS = { "Weapon", "Helmet", "Chest", "Boots" }

local RARITIES = {
	Common = { color = Color3.fromRGB(235, 235, 235), gearColor = Color3.fromRGB(165, 165, 175) },
	Rare = { color = Color3.fromRGB(80, 160, 255), gearColor = Color3.fromRGB(85, 140, 215) },
	Epic = { color = Color3.fromRGB(190, 100, 255), gearColor = Color3.fromRGB(150, 90, 215) },
	Legendary = { color = Color3.fromRGB(255, 155, 40), gearColor = Color3.fromRGB(240, 165, 55) },
}

-- stat roll bands per slot + rarity (Weapon=ATK, Helmet=HP,
-- Chest=damage-reduction %, Boots=WalkSpeed)
local STAT_BANDS = {
	Weapon = { Common = { 4, 7 }, Rare = { 8, 13 }, Epic = { 14, 22 }, Legendary = { 23, 35 } },
	Helmet = { Common = { 10, 20 }, Rare = { 25, 45 }, Epic = { 50, 85 }, Legendary = { 90, 150 } },
	Chest = { Common = { 3, 5 }, Rare = { 6, 10 }, Epic = { 11, 16 }, Legendary = { 17, 24 } },
	Boots = { Common = { 1, 2 }, Rare = { 3, 4 }, Epic = { 5, 6 }, Legendary = { 7, 9 } },
}

local NAME_POOLS = {
	Weapon = {
		Common = { "Iron Sword", "Soldier's Blade", "Worn Saber", "Militia Sword" },
		Rare = { "Knight Blade", "Azure Edge", "Frostbrand", "Storm Saber" },
		Epic = { "Void Reaver", "Shadowfang", "Rune Greatblade", "Nightfall Edge" },
		Legendary = { "Sunfire Greatsword", "Dragonwrath Blade", "Kingsbane", "Blade of the Dawn" },
	},
	Helmet = {
		Common = { "Iron Cap", "Leather Hood", "Guard Helm", "Bronze Helm" },
		Rare = { "Knight Helm", "Sapphire Circlet", "Wolfguard Hood", "Azure Greathelm" },
		Epic = { "Void Crown", "Shadowveil Hood", "Runed Warhelm", "Nightlord Crown" },
		Legendary = { "Sunfire Crown", "Dragonlord Helm", "Crown of Kings", "Halo of Dawn" },
	},
	Chest = {
		Common = { "Iron Breastplate", "Leather Armor", "Chain Vest", "Bronze Cuirass" },
		Rare = { "Knight Plate", "Azure Mail", "Frostguard Plate", "Storm Cuirass" },
		Epic = { "Void Plate", "Shadowmail", "Rune Aegis Armor", "Nightfall Plate" },
		Legendary = { "Sunfire Aegis", "Dragonscale Armor", "Kingsguard Plate", "Dawnforged Armor" },
	},
	Boots = {
		Common = { "Iron Greaves", "Leather Boots", "Traveler Boots", "Bronze Sabatons" },
		Rare = { "Knight Greaves", "Azure Striders", "Swiftwind Boots", "Storm Sabatons" },
		Epic = { "Void Treads", "Shadowstep Boots", "Rune Striders", "Nightfall Greaves" },
		Legendary = { "Sunfire Sabatons", "Dragonflight Boots", "Kingswind Striders", "Dawnstrider Boots" },
	},
}

local gearState = {}   -- [player] = { inv = {item,...}, equipped = {slot=item} }
local bagOpen = {}     -- [player] = bool
local bagRefs = {}     -- [player] = { gui, button, panel }
local musicMode = {}   -- [player] = "Auto" | "Calm" | "Battle" | "Off"
local sentTrack = {}   -- [player] = last track key sent to the client
local lastMusicSent = {} -- [player] = os.clock() of last music send
local gearIdCounter = 0

-- v7: all affix/set tables + helpers live in ONE table local --
-- the main chunk is at the 200-local limit, so v7 gear code must
-- not spend a register per table.
local GEAR7 = {}

--====================================================================
-- v7 AFFIXES + SETS. Every rolled item carries affixes: a list of
-- { id = "CritChance", value = 9 }. Affix counts by rarity:
-- Common 0-1, Rare 1-2, Epic 2-3, Legendary 3-4 + one UNIQUE
-- effect. Values roll inside per-rarity bands, biased upward by
-- ITEM LEVEL tier (1 = early waves, 2 = wave 4+, 3 = bosses /
-- Nightmare). All affixes are functional: V7.recompute aggregates
-- them into combatStats and V7.hitEnemy consumes them.
--====================================================================
GEAR7.AFFIX = {
	CritChance = { label = "Crit Chance", unit = "%", prefix = "Deadly",
		bands = { Common = { 2, 4 }, Rare = { 4, 7 }, Epic = { 6, 10 }, Legendary = { 9, 15 } } },
	CritDamage = { label = "Crit Damage", unit = "%", suffix = "of Ruin",
		bands = { Common = { 10, 20 }, Rare = { 20, 35 }, Epic = { 30, 55 }, Legendary = { 45, 80 } } },
	Lifesteal = { label = "Lifesteal", unit = "%", prefix = "Vampiric",
		bands = { Common = { 1, 2 }, Rare = { 2, 4 }, Epic = { 3, 6 }, Legendary = { 5, 8 } } },
	AttackSpeed = { label = "Attack Speed", unit = "%", prefix = "Swift",
		bands = { Common = { 3, 6 }, Rare = { 5, 10 }, Epic = { 8, 14 }, Legendary = { 12, 20 } } },
	FireDamage = { label = "Fire Damage", unit = "", prefix = "Flaming",
		bands = { Common = { 2, 4 }, Rare = { 4, 8 }, Epic = { 7, 13 }, Legendary = { 11, 20 } } },
	FrostDamage = { label = "Frost Damage", unit = "", prefix = "Frozen",
		bands = { Common = { 2, 4 }, Rare = { 4, 8 }, Epic = { 7, 13 }, Legendary = { 11, 20 } } },
	LightningDamage = { label = "Lightning Damage", unit = "", prefix = "Storm",
		bands = { Common = { 2, 4 }, Rare = { 4, 8 }, Epic = { 7, 13 }, Legendary = { 11, 20 } } },
	Execute = { label = "Execute (vs <30% HP)", unit = "%", prefix = "Executioner's",
		bands = { Common = { 5, 10 }, Rare = { 8, 15 }, Epic = { 12, 22 }, Legendary = { 18, 30 } } },
	KillRegen = { label = "Heal on Kill", unit = " HP", suffix = "of the Phoenix",
		bands = { Common = { 3, 6 }, Rare = { 6, 12 }, Epic = { 10, 20 }, Legendary = { 16, 30 } } },
	Vitality = { label = "Vitality", unit = " HP", suffix = "of the Bear",
		bands = { Common = { 5, 15 }, Rare = { 15, 30 }, Epic = { 25, 50 }, Legendary = { 40, 80 } } },
	Bulwark = { label = "Damage Reduction", unit = "%", suffix = "of the Wall",
		bands = { Common = { 1, 2 }, Rare = { 2, 4 }, Epic = { 3, 5 }, Legendary = { 4, 7 } } },
	Swiftness = { label = "Move Speed", unit = "", suffix = "of the Wind",
		bands = { Common = { 1, 1 }, Rare = { 1, 2 }, Epic = { 2, 3 }, Legendary = { 3, 4 } } },
	SkillHaste = { label = "Skill Haste", unit = "%", suffix = "of the Sage",
		bands = { Common = { 2, 4 }, Rare = { 3, 6 }, Epic = { 5, 9 }, Legendary = { 7, 12 } } },
	ManaRegen = { label = "Mana Regen", unit = "/s", suffix = "of the Tide",
		bands = { Common = { 1, 1 }, Rare = { 1, 2 }, Epic = { 2, 3 }, Legendary = { 3, 4 } } },
}
GEAR7.AFFIX_POOL = { "CritChance", "CritDamage", "Lifesteal", "AttackSpeed",
	"FireDamage", "FrostDamage", "LightningDamage", "Execute", "KillRegen",
	"Vitality", "Bulwark", "Swiftness", "SkillHaste", "ManaRegen" }
GEAR7.AFFIX_COUNTS = { Common = { 0, 1 }, Rare = { 1, 2 }, Epic = { 2, 3 }, Legendary = { 3, 4 } }

GEAR7.UNIQUE = {
	Inferno = { name = "Inferno", guarantee = "FireDamage",
		desc = "Hits explode for AoE fire damage (1s CD)" },
	Stormlord = { name = "Stormlord", guarantee = "LightningDamage",
		desc = "Lightning chains reach +2 extra targets" },
	Vampiric = { name = "Vampiric", guarantee = "Lifesteal",
		desc = "Lifesteal doubled; kills heal +25 HP" },
	Frostbite = { name = "Frostbite", guarantee = "FrostDamage",
		desc = "Frost hits can freeze enemies solid for 0.6s" },
	Executioner = { name = "Executioner", guarantee = "CritChance",
		desc = "Crits vs enemies under 30% HP deal +150%" },
}
GEAR7.UNIQUE_POOL = { "Inferno", "Stormlord", "Vampiric", "Frostbite", "Executioner" }

GEAR7.SETS = {
	Inferno = { name = "Inferno Lord", element = "FireDamage", unique = "Inferno",
		color = Color3.fromRGB(255, 110, 40),
		pieces = { Weapon = "Inferno Lord's Greatblade", Helmet = "Inferno Lord's Crown",
			Chest = "Inferno Lord's Plate" } },
	Frost = { name = "Frost Warden", element = "FrostDamage", unique = "Frostbite",
		color = Color3.fromRGB(130, 210, 255),
		pieces = { Weapon = "Frost Warden's Scepter", Helmet = "Frost Warden's Crown",
			Chest = "Frost Warden's Plate" } },
	Storm = { name = "Storm Soul", element = "LightningDamage", unique = "Stormlord",
		color = Color3.fromRGB(255, 240, 150),
		pieces = { Weapon = "Storm Soul's Blade", Helmet = "Storm Soul's Crown",
			Chest = "Storm Soul's Plate" } },
}
GEAR7.SET_POOL = { "Inferno", "Frost", "Storm" }
GEAR7.SET_BONUS = {
	Inferno = { { pieces = 2, text = "2pc: +25% fire damage, ignite chance up" },
		{ pieces = 3, text = "3pc: your hits periodically erupt in fire" } },
	Frost = { { pieces = 2, text = "2pc: +20% Max HP, +25% frost damage" },
		{ pieces = 3, text = "3pc: hits taken can freeze the attacker + frost shield" } },
	Storm = { { pieces = 2, text = "2pc: +12% attack speed, +25% lightning damage" },
		{ pieces = 3, text = "3pc: crits call a lightning strike (2s CD)" } },
}

-- v7 bag UI state: Inspect mode + the detail box contents
local gearUi = { inspect = {}, text = {} }

local uiEvent = ReplicatedStorage:FindFirstChild("UIEvent")
if not uiEvent then
	uiEvent = Instance.new("RemoteEvent")
	uiEvent.Name = "UIEvent"
	uiEvent.Parent = ReplicatedStorage
end

local function darkOf(c)
	return Color3.new(c.R * 0.32, c.G * 0.32, c.B * 0.32)
end

local function statTextFor(item)
	if item.slot == "Weapon" then
		return "+" .. item.stat .. " ATK"
	elseif item.slot == "Helmet" then
		return "+" .. item.stat .. " HP"
	elseif item.slot == "Chest" then
		return "+" .. item.stat .. "% DEF"
	else
		return "+" .. item.stat .. " SPD"
	end
end

-- v7: how many pieces of a set the player currently has EQUIPPED
GEAR7.setPiecesEquipped = function(player, setId)
	local state = gearState[player]
	if not state then return 0 end
	local n = 0
	for _, slot in ipairs(GEAR_SLOTS) do
		local it = state.equipped[slot]
		if it and it.set == setId then n = n + 1 end
	end
	return n
end

-- v7: full multi-line item description for the bag detail box:
-- base stat, every affix, the unique effect, and set progress
-- with bonus lines marked active / inactive.
GEAR7.itemDetailText = function(player, item)
	local lines = { item.name }
	lines[#lines + 1] = item.rarity .. " " .. item.slot .. "  -  " .. statTextFor(item)
	if item.set and GEAR7.SETS[item.set] then
		local owned = GEAR7.setPiecesEquipped(player, item.set)
		lines[#lines + 1] = "Set: " .. GEAR7.SETS[item.set].name
			.. " (" .. owned .. "/3 equipped)"
	end
	for _, af in ipairs(item.affixes or {}) do
		local def = GEAR7.AFFIX[af.id]
		if def then
			lines[#lines + 1] = "  +" .. af.value .. def.unit .. " " .. def.label
		end
	end
	if item.unique and GEAR7.UNIQUE[item.unique] then
		lines[#lines + 1] = "UNIQUE " .. GEAR7.UNIQUE[item.unique].name
			.. ": " .. GEAR7.UNIQUE[item.unique].desc
	end
	if item.set and GEAR7.SET_BONUS[item.set] then
		local owned = GEAR7.setPiecesEquipped(player, item.set)
		for _, bt in ipairs(GEAR7.SET_BONUS[item.set]) do
			lines[#lines + 1] = (owned >= bt.pieces and "[ACTIVE] " or "[LOCKED] ") .. bt.text
		end
	end
	if #lines == 2 then
		lines[#lines + 1] = "  (no affixes)"
	end
	return table.concat(lines, "\n")
end

maxHealthFor = function(player)
	local level = getStat(player, "leaderstats", "Level")
	local hp = 100 + ((level and level.Value or 1) - 1) * 20
	local state = gearState[player]
	if state and state.equipped.Helmet then
		hp = hp + state.equipped.Helmet.stat
	end
	-- v7: Vitality affixes add flat MaxHP (aggregated by applyGear)
	local cs = combatStats[player]
	if cs then hp = hp + cs.vitality end
	-- v5: class HP multiplier applies to the whole pool
	local classVal = getStat(player, "Stats", "Class")
	hp = math.floor(hp * modsForClass(classVal and classVal.Value or "").hp)
	-- v7: Frost Warden 2pc -- +20% MaxHP
	if cs and cs.sets.Frost >= 2 then
		hp = math.floor(hp * 1.2)
	end
	return hp
end

-- Rarity styling for the held sword: colored blade that grows with
-- rarity, neon edge + light from Rare up, biggest for Legendary.
local WEAPON_STYLE = {
	Common = { color = Color3.fromRGB(208, 214, 230), len = 2.6, glow = false },
	Rare = { color = Color3.fromRGB(96, 182, 255), len = 3.0, glow = true },
	Epic = { color = Color3.fromRGB(208, 122, 255), len = 3.4, glow = true },
	Legendary = { color = Color3.fromRGB(255, 172, 46), len = 4.0, glow = true },
}

local function styleSwordRarity(tool, rarity)
	local st = WEAPON_STYLE[rarity] or WEAPON_STYLE.Common
	tool.Name = "Sword (" .. rarity .. ")"
	local handle = tool:FindFirstChild("Handle")
	if not handle then return end
	for _, name in ipairs({ "Blade", "BladeTip", "EdgeGlow" }) do
		local old = tool:FindFirstChild(name)
		if old then old:Destroy() end
	end
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
	addPart("Blade", "Part", Vector3.new(0.22, st.len, 0.66),
		Vector3.new(0, 0.72 + st.len / 2, 0), st.color, Enum.Material.Metal)
	addPart("BladeTip", "WedgePart", Vector3.new(0.22, 0.6, 0.66),
		Vector3.new(0, 0.72 + st.len + 0.3, 0), st.color, Enum.Material.Metal,
		CFrame.Angles(math.rad(-90), 0, 0))
	if st.glow then
		local edge = addPart("EdgeGlow", "Part", Vector3.new(0.28, st.len, 0.72),
			Vector3.new(0, 0.72 + st.len / 2, 0), st.color, Enum.Material.Neon)
		edge.Transparency = 0.35
		local gl = Instance.new("PointLight")
		gl.Color = st.color
		gl.Range = (rarity == "Legendary") and 15 or 10
		gl.Brightness = 1.8
		gl.Parent = edge
	end
end

-- The held sword always shows the equipped weapon's rarity; with no
-- weapon equipped it falls back to the blacksmith tier styling.
local function restylePlayerSword(player)
	local state = gearState[player]
	local weapon = state and state.equipped.Weapon
	local tier = getStat(player, "Stats", "SwordTier")
	local classVal = getStat(player, "Stats", "Class")
	local classId = classVal and classVal.Value or ""
	local function restyle(tool)
		-- v7: per-class silhouettes (greatsword / warhammer) with
		-- rarity + set-element coloring live in V7.styleWeapon
		if weapon and V7.styleWeapon then
			V7.styleWeapon(tool, { rarity = weapon.rarity, setId = weapon.set, classId = classId })
		elseif weapon then
			styleSwordRarity(tool, weapon.rarity)
		elseif tier then
			if V7.styleWeapon then
				V7.styleWeapon(tool, { tier = tier.Value, classId = classId })
			else
				styleSword(tool, tier.Value)
			end
		end
	end
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, t in ipairs(backpack:GetChildren()) do
			if t:IsA("Tool") and string.find(t.Name, "Sword", 1, true) then restyle(t) end
		end
	end
	if player.Character then
		for _, t in ipairs(player.Character:GetChildren()) do
			if t:IsA("Tool") and string.find(t.Name, "Sword", 1, true) then restyle(t) end
		end
	end
end

-- Worn gear visuals: helmet / chest plates / boots welded onto the
-- character in a "WornGear" model, rebuilt on every equip change.
local function weldGearPart(part, bodyPart)
	part.Anchored = false
	part.CanCollide = false
	part.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = bodyPart
	w.Part1 = part
	w.Parent = part
end

local function rebuildWornGear(player)
	local character = player.Character
	if not character then return end
	local old = character:FindFirstChild("WornGear")
	if old then old:Destroy() end
	local state = gearState[player]
	if not state then return end
	local eq = state.equipped
	-- v7: Archers always wear their quiver, even with no gear yet
	local classVal = getStat(player, "Stats", "Class")
	local isArcher = classVal and classVal.Value == "Archer"
	if not eq.Helmet and not eq.Chest and not eq.Boots and not isArcher then return end
	local model = Instance.new("Model")
	model.Name = "WornGear"
	model.Parent = character
	local function add(name, size, cframe, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.Metal
		if shape then p.Shape = shape end
		p.CFrame = cframe
		p.Parent = model
		return p
	end

	if eq.Helmet then
		local head = character:FindFirstChild("Head")
		if head then
			local c = RARITIES[eq.Helmet.rarity].gearColor
			local dome = add("HelmetDome", Vector3.new(1.75, 1.05, 1.75),
				head.CFrame * CFrame.new(0, 0.42, 0), c, Enum.Material.Metal, Enum.PartType.Ball)
			weldGearPart(dome, head)
			local brim = add("HelmetBrim", Vector3.new(0.3, 2.1, 2.1),
				head.CFrame * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)),
				c, Enum.Material.Metal, Enum.PartType.Cylinder)
			weldGearPart(brim, head)
			if eq.Helmet.rarity == "Legendary" then
				for i = -1, 1 do
					local spike = add("CrownSpike", Vector3.new(0.22, 0.7, 0.22),
						head.CFrame * CFrame.new(i * 0.45, 1.05, 0),
						RARITIES.Legendary.color, Enum.Material.Metal)
					weldGearPart(spike, head)
				end
				local gl = Instance.new("PointLight")
				gl.Color = RARITIES.Legendary.color
				gl.Range = 9
				gl.Brightness = 1.4
				gl.Parent = dome
			end
		end
	end

	if eq.Chest then
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if torso then
			-- v7: set chest pieces wear the set's element color
			local c = RARITIES[eq.Chest.rarity].gearColor
			if eq.Chest.set and GEAR7.SETS[eq.Chest.set] then
				c = GEAR7.SETS[eq.Chest.set].color
			end
			local halfDepth = torso.Size.Z / 2
			local front = add("ChestPlate", Vector3.new(1.9, 1.9, 0.22),
				torso.CFrame * CFrame.new(0, 0, -halfDepth - 0.12), c, Enum.Material.Metal)
			weldGearPart(front, torso)
			local back = add("BackPlate", Vector3.new(1.9, 1.9, 0.22),
				torso.CFrame * CFrame.new(0, 0, halfDepth + 0.12), c, Enum.Material.Metal)
			weldGearPart(back, torso)
			if eq.Chest.rarity ~= "Common" then
				local gem = add("ChestGem", Vector3.new(0.45, 0.45, 0.2),
					torso.CFrame * CFrame.new(0, 0.15, -halfDepth - 0.28),
					RARITIES[eq.Chest.rarity].color, Enum.Material.Neon, Enum.PartType.Ball)
				weldGearPart(gem, torso)
			end
		end
	end

	if eq.Boots then
		local c = RARITIES[eq.Boots.rarity].gearColor
		for _, names in ipairs({ { "LeftFoot", "Left Leg" }, { "RightFoot", "Right Leg" } }) do
			local foot = character:FindFirstChild(names[1]) or character:FindFirstChild(names[2])
			if foot then
				local boot = add("Boot", Vector3.new(0.95, 0.75, 1.35),
					foot.CFrame * CFrame.new(0, -foot.Size.Y / 2 + 0.32, -0.12),
					c, Enum.Material.Metal)
				weldGearPart(boot, foot)
			end
		end
	end

	-- v7: Archer quiver on the back (leather tube + 3 arrow shafts)
	if isArcher then
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if torso then
			local halfDepth = torso.Size.Z / 2
			local quiver = add("Quiver", Vector3.new(0.85, 1.9, 0.85),
				torso.CFrame * CFrame.new(0.55, 0.1, halfDepth + 0.45)
					* CFrame.Angles(math.rad(18), 0, math.rad(-12)),
				Color3.fromRGB(136, 96, 54), Enum.Material.Leather, Enum.PartType.Cylinder)
			weldGearPart(quiver, torso)
			for i = -1, 1 do
				local shaft = add("QuiverArrow", Vector3.new(0.09, 1.3, 0.09),
					torso.CFrame * CFrame.new(0.55 + i * 0.22, 1.15, halfDepth + 0.38),
					Color3.fromRGB(200, 170, 120), Enum.Material.Wood)
				weldGearPart(shaft, torso)
				local fletch = add("QuiverFletch", Vector3.new(0.3, 0.35, 0.06),
					torso.CFrame * CFrame.new(0.55 + i * 0.22, 1.75, halfDepth + 0.38),
					Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
				weldGearPart(fletch, torso)
			end
		end
	end
end

-- Recompute all gear-derived state: Stats bonuses, HP cap (keeping
-- the current HP ratio), walk speed, worn visuals, sword styling.
local function applyGear(player)
	local state = gearState[player]
	if not state then return end
	local eq = state.equipped
	-- v7: FIRST aggregate every affix + set bonus into
	-- combatStats[player]; MaxHP / DEF / speed below all read it
	if V7.recompute then V7.recompute(player) end
	local cs = combatStats[player]
	local atk = getStat(player, "Stats", "GearATK")
	if atk then atk.Value = eq.Weapon and eq.Weapon.stat or 0 end
	local def = getStat(player, "Stats", "GearDEF")
	-- v7: Bulwark affixes add % damage reduction on top of the chest
	if def then def.Value = (eq.Chest and eq.Chest.stat or 0) + (cs and cs.bulwark or 0) end
	local humanoid = getHumanoid(player.Character)
	if humanoid then
		local newMax = maxHealthFor(player)
		if humanoid.MaxHealth ~= newMax and humanoid.MaxHealth > 0 then
			local ratio = humanoid.Health / humanoid.MaxHealth
			humanoid.MaxHealth = newMax
			if humanoid.Health > 0 then
				humanoid.Health = math.clamp(ratio * newMax, 1, newMax)
			end
		end
		-- v5: class base speed (Archer 17.5) + equipped boots bonus
		-- v7: + Swiftness affixes
		local classVal = getStat(player, "Stats", "Class")
		local baseSpeed = modsForClass(classVal and classVal.Value or "").speed
		humanoid.WalkSpeed = baseSpeed + (eq.Boots and eq.Boots.stat or 0)
			+ (cs and cs.swiftness or 0)
	end
	rebuildWornGear(player)
	restylePlayerSword(player)
end

--====================================================================
-- BAG + EQUIP UI (server-built; clicks arrive via UIEvent)
--====================================================================
local function rebuildBagUI(player)
	local refs = bagRefs[player]
	local state = gearState[player]
	if not refs or not state then return end
	refs.button.Text = "Bag (" .. #state.inv .. ")"
	local panel = refs.panel
	panel.Visible = bagOpen[player] and true or false
	for _, child in ipairs(panel:GetChildren()) do
		child:Destroy()
	end

	makeLabel(panel, "Title", UDim2.new(1, -20, 0, 26), UDim2.new(0, 10, 0, 6),
		"INVENTORY", 18, Color3.fromRGB(255, 230, 160))

	-- v7: Inspect toggle -- while ON, clicking an item (bag or
	-- equipped) shows its full affix list in the detail box below
	-- instead of equipping / unequipping it
	local insp = Instance.new("TextButton")
	insp.Name = "InspectToggle"
	insp.Size = UDim2.new(0, 108, 0, 26)
	insp.Position = UDim2.new(0, 382, 0, 6)
	insp.Text = gearUi.inspect[player] and "Inspect: ON" or "Inspect: OFF"
	insp.Font = Enum.Font.GothamBold
	insp.TextSize = 12
	insp.TextColor3 = Color3.fromRGB(255, 255, 255)
	insp.BackgroundColor3 = gearUi.inspect[player]
		and Color3.fromRGB(70, 115, 60) or Color3.fromRGB(45, 45, 62)
	insp.BorderSizePixel = 0
	insp:SetAttribute("Act", "InspectMode")
	insp.Parent = panel

	-- v7: detail box (bottom of the panel): the last clicked
	-- item's full stats -- affixes, unique effect, set progress
	local detail = makeLabel(panel, "ItemDetail",
		UDim2.new(1, -20, 0, 78), UDim2.new(0, 10, 0, 414),
		gearUi.text[player]
			or "Click an item to equip it. Turn Inspect ON to read full affix lists without equipping.",
		12, Color3.fromRGB(215, 220, 235))
	detail.TextWrapped = true
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.TextXAlignment = Enum.TextXAlignment.Left

	-- music mode row
	makeLabel(panel, "MusicLabel", UDim2.new(0, 56, 0, 24), UDim2.new(0, 10, 0, 38),
		"Music:", 14, Color3.fromRGB(180, 200, 255))
	for i, mode in ipairs({ "Auto", "Calm", "Battle", "Off" }) do
		local b = Instance.new("TextButton")
		b.Name = "Music_" .. mode
		b.Size = UDim2.new(0, 66, 0, 24)
		b.Position = UDim2.new(0, 72 + (i - 1) * 72, 0, 38)
		b.Text = mode
		b.Font = Enum.Font.GothamBold
		b.TextSize = 13
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.BackgroundColor3 = (musicMode[player] == mode)
			and Color3.fromRGB(70, 115, 60) or Color3.fromRGB(45, 45, 62)
		b.BorderSizePixel = 0
		b:SetAttribute("Act", "Music")
		b:SetAttribute("Arg", mode)
		b.Parent = panel
	end

	-- equipped column (left): click a slot to unequip
	makeLabel(panel, "EqHeader", UDim2.new(0, 180, 0, 18), UDim2.new(0, 10, 0, 70),
		"EQUIPPED", 13, Color3.fromRGB(170, 170, 185))
	for i, slot in ipairs(GEAR_SLOTS) do
		local item = state.equipped[slot]
		local b = Instance.new("TextButton")
		b.Name = "Slot_" .. slot
		b.Size = UDim2.new(0, 180, 0, 52)
		b.Position = UDim2.new(0, 10, 0, 92 + (i - 1) * 58)
		b.Font = Enum.Font.Gotham
		b.TextSize = 12
		b.TextWrapped = true
		b.BorderSizePixel = 0
		if item then
			local rc = RARITIES[item.rarity].color
			b.Text = slot .. ": " .. item.name .. "\n" .. statTextFor(item)
			b.BackgroundColor3 = darkOf(rc)
			b.TextColor3 = rc
			local stroke = Instance.new("UIStroke")
			stroke.Color = rc
			stroke.Thickness = 2
			stroke.Parent = b
		else
			b.Text = slot .. ": Empty"
			b.BackgroundColor3 = Color3.fromRGB(35, 35, 46)
			b.TextColor3 = Color3.fromRGB(150, 150, 160)
		end
		b:SetAttribute("Act", "Unequip")
		b:SetAttribute("Arg", slot)
		b.Parent = panel
	end

	-- bag grid (right): 4 x 6, click an item to equip it
	makeLabel(panel, "BagHeader", UDim2.new(0, 280, 0, 18), UDim2.new(0, 206, 0, 70),
		"BAG (" .. #state.inv .. "/" .. MAX_INVENTORY .. ")", 13,
		Color3.fromRGB(170, 170, 185))
	for idx = 1, MAX_INVENTORY do
		local col = (idx - 1) % 4
		local row = math.floor((idx - 1) / 4)
		local x = 206 + col * 72
		local y = 92 + row * 52
		local item = state.inv[idx]
		if item then
			local rc = RARITIES[item.rarity].color
			local b = Instance.new("TextButton")
			b.Name = "Item_" .. item.id
			b.Size = UDim2.new(0, 66, 0, 46)
			b.Position = UDim2.new(0, x, 0, y)
			b.Text = item.name .. "\n" .. statTextFor(item)
			b.Font = Enum.Font.Gotham
			b.TextSize = 10
			b.TextWrapped = true
			b.BackgroundColor3 = darkOf(rc)
			b.TextColor3 = rc
			b.BorderSizePixel = 0
			local stroke = Instance.new("UIStroke")
			stroke.Color = rc
			stroke.Thickness = 2
			stroke.Parent = b
			b:SetAttribute("Act", "Equip")
			b:SetAttribute("Arg", item.id)
			b.Parent = panel
		else
			local f = Instance.new("Frame")
			f.Name = "EmptyCell"
			f.Size = UDim2.new(0, 66, 0, 46)
			f.Position = UDim2.new(0, x, 0, y)
			f.BackgroundColor3 = Color3.fromRGB(27, 27, 37)
			f.BorderSizePixel = 0
			f.Parent = panel
		end
	end
end

local function buildBagUI(player)
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShiningBag"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local button = Instance.new("TextButton")
	button.Name = "BagButton"
	button.Size = UDim2.new(0, 110, 0, 36)
	button.Position = UDim2.new(0, 12, 0, 206)
	button.Text = "Bag (0)"
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.BackgroundColor3 = Color3.fromRGB(32, 32, 48)
	button.BackgroundTransparency = 0.15
	button.BorderSizePixel = 0
	button:SetAttribute("Act", "ToggleBag")
	button.Parent = gui

	-- v5: Skills toggle sits next to the Bag button (its panel lives
	-- in the ShiningClass gui; clicks arrive via the same UIEvent)
	local skillsButton = Instance.new("TextButton")
	skillsButton.Name = "SkillsButton"
	skillsButton.Size = UDim2.new(0, 110, 0, 36)
	skillsButton.Position = UDim2.new(0, 130, 0, 206)
	skillsButton.Text = "Skills"
	skillsButton.Font = Enum.Font.GothamBold
	skillsButton.TextSize = 16
	skillsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	skillsButton.BackgroundColor3 = Color3.fromRGB(48, 38, 64)
	skillsButton.BackgroundTransparency = 0.15
	skillsButton.BorderSizePixel = 0
	skillsButton:SetAttribute("Act", "ToggleSkills")
	skillsButton.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "BagPanel"
	panel.Size = UDim2.new(0, 500, 0, 500)
	panel.Position = UDim2.new(0.5, -250, 0.5, -250)
	panel.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	bagRefs[player] = { gui = gui, button = button, skillsButton = skillsButton, panel = panel }
	rebuildBagUI(player)
end

local function equipItem(player, itemId)
	local state = gearState[player]
	if not state then return end
	for i, item in ipairs(state.inv) do
		if item.id == itemId then
			-- v7: the detail box always shows the last clicked
			-- item; in Inspect mode that is ALL the click does
			gearUi.text[player] = GEAR7.itemDetailText(player, item)
			if gearUi.inspect[player] then
				rebuildBagUI(player)
				return
			end
			table.remove(state.inv, i)
			local old = state.equipped[item.slot]
			if old then table.insert(state.inv, old) end
			state.equipped[item.slot] = item
			applyGear(player)
			rebuildBagUI(player)
			playSfx("Equip", getHRP(player.Character))
			showToast(player, "Equipped: " .. item.name, 2)
			return
		end
	end
end

local function unequipItem(player, slot)
	local state = gearState[player]
	if not state then return end
	local item = state.equipped[slot]
	if not item then return end
	-- v7: Inspect mode reads equipped items too
	if gearUi.inspect[player] then
		gearUi.text[player] = GEAR7.itemDetailText(player, item)
		rebuildBagUI(player)
		return
	end
	if #state.inv >= MAX_INVENTORY then
		showToast(player, "Bag full!", 2)
		return
	end
	state.equipped[slot] = nil
	table.insert(state.inv, item)
	applyGear(player)
	rebuildBagUI(player)
	playSfx("Equip", getHRP(player.Character))
end

--====================================================================
-- GEAR DROPS (called from onEnemyDeath via the forward declaration)
--====================================================================
local function rollRarityFromWeights(weights)
	local total = 0
	for _, w in ipairs(weights) do total = total + w[2] end
	local r = math.random(1, total)
	local acc = 0
	for _, w in ipairs(weights) do
		acc = acc + w[2]
		if r <= acc then return w[1] end
	end
	return weights[1][1]
end

-- v7: roll a value inside a { lo, hi } band. Item-level tier
-- biases the roll upward: tier 1 uniform, tier 2 upper 60%,
-- tier 3 top 30% with a small overflow (capped at band hi x1.15).
GEAR7.rollBandValue = function(band, tier)
	local lo, hi = band[1], band[2]
	local r = math.random()
	local v
	if tier and tier >= 3 then
		v = (lo + (hi - lo) * (0.7 + 0.3 * r)) * 1.1
	elseif tier and tier == 2 then
		v = lo + (hi - lo) * (0.4 + 0.6 * r)
	else
		v = lo + (hi - lo) * r
	end
	v = math.min(v, hi * 1.15)
	return math.max(1, math.floor(v + 0.5))
end

-- v7: roll the affix list for a rarity. guaranteeId (a set's
-- element affix, or a Legendary unique's matching affix) is
-- always included when given.
GEAR7.rollAffixes = function(rarity, tier, guaranteeId)
	local range = GEAR7.AFFIX_COUNTS[rarity]
	local count = math.random(range[1], range[2])
	local pool = {}
	for _, id in ipairs(GEAR7.AFFIX_POOL) do table.insert(pool, id) end
	local affixes = {}
	local function addAffix(id)
		for _, af in ipairs(affixes) do
			if af.id == id then return end
		end
		table.insert(affixes, { id = id, value = GEAR7.rollBandValue(GEAR7.AFFIX[id].bands[rarity], tier) })
	end
	if guaranteeId then addAffix(guaranteeId) end
	while #affixes < count and #pool > 0 do
		local idx = math.random(1, #pool)
		local id = table.remove(pool, idx)
		addAffix(id)
	end
	return affixes
end

-- v7: the item NAME is built from its affixes: [prefix from the
-- strongest combat affix] + base name + [of-suffix from a
-- secondary affix]. Set pieces keep their fixed set names.
GEAR7.buildItemName = function(baseName, rarity, affixes)
	local prefix, prefixScore = nil, -1
	local suffix = nil
	for _, af in ipairs(affixes) do
		local def = GEAR7.AFFIX[af.id]
		if def then
			if def.prefix then
				local band = def.bands[rarity]
				local score = af.value / band[2]
				if score > prefixScore then
					prefixScore = score
					prefix = def.prefix
				end
			elseif def.suffix and not suffix then
				suffix = def.suffix
			end
		end
	end
	local name = baseName
	if prefix then name = prefix .. " " .. name end
	if suffix then name = name .. " " .. suffix end
	return name
end

local function rollGearItem(rarity, tier)
	tier = tier or 1
	local slot = GEAR_SLOTS[math.random(1, #GEAR_SLOTS)]
	local band = STAT_BANDS[slot][rarity]
	local pool = NAME_POOLS[slot][rarity]
	-- Legendaries roll one UNIQUE effect, which also guarantees
	-- its matching affix is present
	local unique = nil
	local guarantee = nil
	if rarity == "Legendary" then
		unique = GEAR7.UNIQUE_POOL[math.random(1, #GEAR7.UNIQUE_POOL)]
		guarantee = GEAR7.UNIQUE[unique].guarantee
	end
	local affixes = GEAR7.rollAffixes(rarity, tier, guarantee)
	gearIdCounter = gearIdCounter + 1
	return {
		id = "g" .. gearIdCounter,
		slot = slot,
		rarity = rarity,
		name = GEAR7.buildItemName(pool[math.random(1, #pool)], rarity, affixes),
		stat = GEAR7.rollBandValue(band, tier),
		affixes = affixes,
		unique = unique,
	}
end

-- v7: a SET piece -- fixed name, Epic/Legendary only, guaranteed
-- element affix; Legendary set pieces carry the set's own unique
GEAR7.rollSetItem = function(rarity, tier)
	tier = tier or 3
	local setId = GEAR7.SET_POOL[math.random(1, #GEAR7.SET_POOL)]
	local setDef = GEAR7.SETS[setId]
	local slots = { "Weapon", "Helmet", "Chest" }
	local slot = slots[math.random(1, #slots)]
	local band = STAT_BANDS[slot][rarity]
	local affixes = GEAR7.rollAffixes(rarity, tier, setDef.element)
	gearIdCounter = gearIdCounter + 1
	return {
		id = "g" .. gearIdCounter,
		slot = slot,
		rarity = rarity,
		name = setDef.pieces[slot],
		stat = GEAR7.rollBandValue(band, tier),
		affixes = affixes,
		set = setId,
		unique = (rarity == "Legendary") and setDef.unique or nil,
	}
end

-- v7: the physical drop (pedestal + orb + pickup) for an
-- already-rolled item; shared by normal and set drops
GEAR7.spawnItemDrop = function(item, position)
	local rc = RARITIES[item.rarity].color
	-- ground the drop: the position passed in is an enemy root
	-- (~2 studs up), but the pedestal must sit on the floor (y = 0)
	local dropPos = Vector3.new(
		position.X + math.random(-2, 2), 0, position.Z + math.random(-2, 2))
	local model = Instance.new("Model")
	model.Name = "GearDrop"
	model.Parent = dropsFolder

	local base = Instance.new("Part")
	base.Name = "Pedestal"
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(0.5, 3.2, 3.2)
	base.CFrame = CFrame.new(dropPos.X, dropPos.Y + 0.25, dropPos.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	base.Color = Color3.fromRGB(52, 52, 62)
	base.Material = Enum.Material.Slate
	base.Anchored = true
	base.Parent = model

	local orb = Instance.new("Part")
	orb.Name = "GearOrb"
	orb.Shape = Enum.PartType.Ball
	local orbSize = (item.rarity == "Legendary") and 1.9 or 1.5
	orb.Size = Vector3.new(orbSize, orbSize, orbSize)
	orb.Position = dropPos + Vector3.new(0, 2.1, 0)
	orb.Color = rc
	orb.Material = Enum.Material.Neon
	orb.Anchored = true
	orb.CanCollide = false
	orb.Parent = model
	local light = Instance.new("PointLight")
	light.Color = rc
	light.Range = 13
	light.Brightness = 2.2
	light.Parent = orb

	local gui = Instance.new("BillboardGui")
	gui.Name = "ItemName"
	gui.Size = UDim2.new(5, 0, 1.1, 0)
	gui.StudsOffset = Vector3.new(0, 1.9, 0)
	gui.AlwaysOnTop = true
	gui.Parent = orb
	-- v7: set drops advertise their set under the item name
	local labelText = item.name
	if item.set and GEAR7.SETS[item.set] then
		labelText = item.name .. "\n[" .. GEAR7.SETS[item.set].name .. " set]"
	end
	local nameLabel = makeLabel(gui, "Name", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
		labelText, 15, rc)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center

	Debris:AddItem(model, 60)
	-- gentle bob while the drop waits
	local orbBaseY = orb.Position.Y
	task.spawn(function()
		while model.Parent do
			orb.Position = Vector3.new(dropPos.X,
				orbBaseY + math.sin(os.clock() * 2.2) * 0.25, dropPos.Z)
			task.wait(0.05)
		end
	end)

	local claimed = false
	orb.Touched:Connect(function(hit)
		if claimed then return end
		local character = hit and hit.Parent
		local humanoid = getHumanoid(character)
		if not humanoid or humanoid.Health <= 0 then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		local state = gearState[player]
		if not state then return end
		if #state.inv >= MAX_INVENTORY then
			showToast(player, "Bag full!", 2)
			return
		end
		claimed = true
		table.insert(state.inv, item)
		showToast(player, "Picked up: " .. item.name, 3)
		playSfx("Pickup", getHRP(character))
		rebuildBagUI(player)
		model:Destroy()
	end)
end

-- v7: normal gear drop -- rarity from weights, affixes rolled at
-- the given item-level tier
spawnGearDrop = function(position, weights, tier)
	GEAR7.spawnItemDrop(rollGearItem(rollRarityFromWeights(weights), tier or 1), position)
end

-- v7: SET piece drop -- Epic, or Legendary 30% of the time (50%
-- on Nightmare); always rolled at the top ilvl tier
spawnSetDrop = function(position, nightmare)
	local legendaryChance = nightmare and 0.5 or 0.3
	local rarity = (math.random() < legendaryChance) and "Legendary" or "Epic"
	GEAR7.spawnItemDrop(GEAR7.rollSetItem(rarity, 3), position)
end

--====================================================================
-- BACKGROUND MUSIC: server picks the track, client plays it.
-- Auto = Calm in town, Battle in the dungeon; fixed modes pin one
-- track everywhere; Off stops. Changes go out on UIEvent.
--====================================================================
local function zoneTrackFor(player)
	local hrp = getHRP(player.Character)
	if hrp and inDungeon(hrp.Position) then
		return "Battle"
	end
	return "Calm"
end

local function effectiveTrack(player)
	local mode = musicMode[player] or "Auto"
	if mode == "Off" then return nil end
	if mode == "Calm" then return "Calm" end
	if mode == "Battle" then return "Battle" end
	return zoneTrackFor(player)
end

local function sendMusic(player, force)
	local track = effectiveTrack(player)
	if force or sentTrack[player] ~= track then
		sentTrack[player] = track
		lastMusicSent[player] = os.clock()
		uiEvent:FireClient(player, "Music", track or "Off")
	end
end

local function setMusicMode(player, mode)
	if mode ~= "Auto" and mode ~= "Calm" and mode ~= "Battle" and mode ~= "Off" then
		return
	end
	musicMode[player] = mode
	rebuildBagUI(player)
	sendMusic(player)
end

uiEvent.OnServerEvent:Connect(function(player, act, arg)
	if type(act) ~= "string" then return end
	if act == "ToggleBag" then
		bagOpen[player] = not bagOpen[player]
		rebuildBagUI(player)
	elseif act == "Equip" then
		if type(arg) == "string" then equipItem(player, arg) end
	elseif act == "Unequip" then
		if type(arg) == "string" then unequipItem(player, arg) end
	elseif act == "InspectMode" then
		-- v7: bag Inspect toggle (see rebuildBagUI / equipItem)
		gearUi.inspect[player] = not gearUi.inspect[player]
		rebuildBagUI(player)
	elseif act == "Music" then
		if type(arg) == "string" then setMusicMode(player, arg) end
	end
end)

--====================================================================
-- CLASS + SKILL SYSTEM (v5)
-- Four Diablo-2-inspired classes. The class id lives in the Stats
-- StringValue "Class" ("" = not chosen). Skill levels are stored
-- PER CLASS in skillState (skills[classId] = {lv, lv, lv}), so
-- switching class keeps level + gear and restores that class's
-- build. 1 skill point per level-up (Stats "SkillPoints").
-- Casts arrive via UIEvent acts ChooseClass / ToggleClass /
-- ToggleSkills / SkillUp / CastSkill (buttons + Q/E/R hotkeys
-- forwarded by UIClient).
--====================================================================
local skillState = {} -- [player] = { skills={[classId]={0,0,0}}, cooldowns={}, thornsOn=false }
local buffs = {}      -- [player] = { dmgMul=, defRed=, expires= } (War Cry)
local classRefs = {}  -- [player] = { gui, panel, skillsPanel, classButtons }
local skillBarRefs = {} -- [player] = { buttons = {b1, b2, b3} }
local classPanelOpen = {} -- [player] = bool
local skillsOpen = {}     -- [player] = bool
local HOTKEYS = { "Q", "E", "R" }

local function getClassId(player)
	local classVal = getStat(player, "Stats", "Class")
	local cid = classVal and classVal.Value or ""
	if CLASS_DEFS[cid] then return cid end
	return ""
end

local function getSkillLevel(player, classId, idx)
	local st = skillState[player]
	if not st then return 0 end
	local arr = st.skills[classId]
	return arr and arr[idx] or 0
end

local function newSkillState()
	local skills = {}
	for _, cid in ipairs(CLASS_IDS) do
		skills[cid] = { 0, 0, 0 }
	end
	-- v7: freeGranted[classId] = true once the class's starter
	-- grant (Skill 1 at Lv1 + 1 skill point) has been given
	return { skills = skills, cooldowns = {}, thornsOn = false,
		freeGranted = {}, cdToastAt = 0 }
end

-- Outgoing damage multiplier: class modifier x active War Cry buff.
classDamageMul = function(player, kind)
	local mods = modsForClass(getClassId(player))
	local mul = mods[kind] or 1
	local b = buffs[player]
	if b and os.clock() < b.expires then
		mul = mul * b.dmgMul
	end
	return mul
end

-- Incoming damage multiplier: Paladin's inherent 5% reduction and
-- an active War Cry multiply into the armor/gear reduction.
classIncomingMul = function(player)
	local mods = modsForClass(getClassId(player))
	local mul = 1 - mods.defRed
	local b = buffs[player]
	if b and os.clock() < b.expires then
		mul = mul * (1 - b.defRed)
	end
	return mul
end

-- Thorns Aura: Lv1 reflects 10% of the attacker's damage stat,
-- +4% per extra level (Lv5 = 26%). 0 when off / not a Paladin.
thornsReflectFor = function(player)
	local st = skillState[player]
	if not st or not st.thornsOn then return 0 end
	if getClassId(player) ~= "Paladin" then return 0 end
	local lv = getSkillLevel(player, "Paladin", 3)
	if lv < 1 then return 0 end
	return 0.06 + 0.04 * lv
end

maxManaFor = function(player)
	return math.floor(MAX_MANA * modsForClass(getClassId(player)).mana)
end

-- Raw damage bases (BEFORE the class multiplier), mirroring the
-- sword / fireball tool formulas so skills scale with progression.
local function playerWeaponDamage(player)
	local level = getStat(player, "leaderstats", "Level")
	local tier = getStat(player, "Stats", "SwordTier")
	local power = getStat(player, "Stats", "Power")
	local gearATK = getStat(player, "Stats", "GearATK")
	return SWORD_BASE_DAMAGE
		+ ((level and level.Value or 1) - 1) * 2
		+ ((tier and tier.Value or 1) - 1) * 8
		+ (power and power.Value or 0)
		+ (gearATK and gearATK.Value or 0)
end

local function playerSpellDamage(player)
	local level = getStat(player, "leaderstats", "Level")
	local power = getStat(player, "Stats", "Power")
	local gearATK = getStat(player, "Stats", "GearATK")
	return FIREBALL_BASE_DAMAGE
		+ ((level and level.Value or 1) - 1) * 3
		+ (power and power.Value or 0)
		+ (gearATK and gearATK.Value or 0)
end

local function playerRangedDamage(player)
	local level = getStat(player, "leaderstats", "Level")
	local power = getStat(player, "Stats", "Power")
	local gearATK = getStat(player, "Stats", "GearATK")
	return 11
		+ ((level and level.Value or 1) - 1) * 2
		+ (power and power.Value or 0)
		+ (gearATK and gearATK.Value or 0)
end

--====================================================================
-- SKILL FX HELPERS
--====================================================================
-- Expanding flat neon ring on the ground (nova / heal / war cry...)
local function ringFX(position, radius, color, duration)
	duration = duration or 0.35
	local ring = Instance.new("Part")
	ring.Name = "SkillRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.35, 2, 2)
	ring.CFrame = CFrame.new(position.X, 0.4, position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.3
	ring.Anchored = true
	ring.CanCollide = false
	ring.Parent = Workspace
	task.spawn(function()
		local t0 = os.clock()
		while ring.Parent do
			local t = (os.clock() - t0) / duration
			if t >= 1 then break end
			local d = 2 + (radius * 2 - 2) * t
			ring.Size = Vector3.new(0.35, d, d)
			ring.Transparency = 0.3 + 0.7 * t
			task.wait(0.03)
		end
		ring:Destroy()
	end)
end

-- Colored spark burst (teleport / heal / meteor impact)
local function burstFX(position, color, count)
	for _ = 1, count or 8 do
		local sp = Instance.new("Part")
		sp.Name = "SkillSpark"
		sp.Size = Vector3.new(0.3, 0.3, 0.3)
		sp.Color = color
		sp.Material = Enum.Material.Neon
		sp.CanCollide = false
		sp.Position = position
		sp.Parent = Workspace
		sp.AssemblyLinearVelocity = Vector3.new(
			math.random(-10, 10), math.random(5, 14), math.random(-10, 10))
		Debris:AddItem(sp, 0.4)
		task.spawn(function()
			local t0 = os.clock()
			while sp.Parent and os.clock() - t0 < 0.35 do
				sp.Transparency = (os.clock() - t0) / 0.35
				task.wait(0.03)
			end
			if sp.Parent then sp:Destroy() end
		end)
	end
end

-- Ice-blue flash on slowed enemies (Frost Nova), mirrors flashEnemy
local function frostFlash(model, data)
	if data.frostFlashing then return end
	data.frostFlashing = true
	local saved = {}
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			saved[part] = part.Color
			part.Color = Color3.fromRGB(150, 215, 255)
		end
	end
	task.delay(0.3, function()
		for part, color in pairs(saved) do
			if part and part.Parent then
				part.Color = color
			end
		end
		data.frostFlashing = false
	end)
end

local function nearestEnemy(player, maxDist)
	local hrp = getHRP(player.Character)
	if not hrp then return nil end
	local best, bestDist = nil, maxDist
	for model, _ in pairs(enemies) do
		local eroot = model:FindFirstChild("HumanoidRootPart")
		if eroot then
			local d = horizontalDistance(hrp.Position, eroot.Position)
			if d < bestDist then
				bestDist = d
				best = model
			end
		end
	end
	return best
end

local function enemiesWithin(position, radius)
	local list = {}
	for model, _ in pairs(enemies) do
		local eroot = model:FindFirstChild("HumanoidRootPart")
		if eroot and horizontalDistance(position, eroot.Position) <= radius then
			table.insert(list, model)
		end
	end
	return list
end

--====================================================================
-- v7 CORE: D2 skill synergies, gear aggregation (applyGear ->
-- combatStats), the central hit pipeline V7.hitEnemy with crit /
-- elemental flats / on-hit procs, elite enchantment effects,
-- per-class weapon styling, the boss HP bar and the status loop.
--====================================================================
V7.ELEM_COLORS = {
	Fire = Color3.fromRGB(255, 120, 50),
	Frost = Color3.fromRGB(140, 210, 255),
	Lightning = Color3.fromRGB(255, 240, 150),
	Holy = Color3.fromRGB(255, 230, 150),
}

-- D2 synergies: SYNERGY[class][skill] = source skill index; each
-- level in the source passively adds +4% to the sibling skill.
V7.SYNERGY = {
	Warrior = { [1] = 3, [2] = 3 },   -- War Cry feeds Whirlwind + Charge
	Mage = { [1] = 2, [2] = 1 },      -- Frost Nova <-> Meteor feed each other
	Archer = { [1] = 2, [2] = 1, [3] = 1 }, -- Multishot <-> Piercing feed each other; Multishot feeds Arrow Rain
	Paladin = { [1] = 3, [2] = 1 },   -- Thorns feeds Blessed Hammer; Hammer feeds Heal
}

function V7.synergyMul(player, classId, idx)
	local src = V7.SYNERGY[classId] and V7.SYNERGY[classId][idx]
	if not src then return 1 end
	return 1 + 0.04 * getSkillLevel(player, classId, src)
end

-- Aggregate ALL equipped affixes + set bonuses into
-- combatStats[player]. Called by applyGear on every equip change.
function V7.recompute(player)
	local cs = {
		crit = 0.05, critDmg = 0.5, lifesteal = 0, atkSpeed = 0,
		fire = 0, frost = 0, lightning = 0, execute = 0, killRegen = 0,
		vitality = 0, bulwark = 0, swiftness = 0, haste = 0, manaRegen = 0,
		unique = nil, sets = { Inferno = 0, Frost = 0, Storm = 0 },
		fireMul = 1, frostMul = 1, lightningMul = 1,
		igniteChance = 0, freezeChance = 0, chainChance = 0, chainTargets = 2,
		frostGuard = false, stormStrike = false,
	}
	local state = gearState[player]
	if state then
		for _, slot in ipairs(GEAR_SLOTS) do
			local item = state.equipped[slot]
			if item then
				if item.set and cs.sets[item.set] ~= nil then
					cs.sets[item.set] = cs.sets[item.set] + 1
				end
				if item.unique and not cs.unique then
					cs.unique = item.unique
				end
				for _, af in ipairs(item.affixes or {}) do
					local v = af.value
					if af.id == "CritChance" then cs.crit = cs.crit + v / 100
					elseif af.id == "CritDamage" then cs.critDmg = cs.critDmg + v / 100
					elseif af.id == "Lifesteal" then cs.lifesteal = cs.lifesteal + v / 100
					elseif af.id == "AttackSpeed" then cs.atkSpeed = cs.atkSpeed + v / 100
					elseif af.id == "FireDamage" then cs.fire = cs.fire + v
					elseif af.id == "FrostDamage" then cs.frost = cs.frost + v
					elseif af.id == "LightningDamage" then cs.lightning = cs.lightning + v
					elseif af.id == "Execute" then cs.execute = cs.execute + v / 100
					elseif af.id == "KillRegen" then cs.killRegen = cs.killRegen + v
					elseif af.id == "Vitality" then cs.vitality = cs.vitality + v
					elseif af.id == "Bulwark" then cs.bulwark = cs.bulwark + v
					elseif af.id == "Swiftness" then cs.swiftness = cs.swiftness + v
					elseif af.id == "SkillHaste" then cs.haste = cs.haste + v / 100
					elseif af.id == "ManaRegen" then cs.manaRegen = cs.manaRegen + v
					end
				end
			end
		end
	end
	-- set bonuses fold into the same table
	if cs.sets.Inferno >= 2 then cs.fireMul = 1.25 end
	if cs.sets.Frost >= 2 then cs.frostMul = 1.25 end
	if cs.sets.Storm >= 2 then
		cs.lightningMul = 1.25
		cs.atkSpeed = cs.atkSpeed + 0.12
	end
	cs.frostGuard = cs.sets.Frost >= 3
	cs.stormStrike = cs.sets.Storm >= 3
	if cs.fire > 0 then
		cs.igniteChance = 0.25 + (cs.sets.Inferno >= 2 and 0.15 or 0)
	end
	if cs.frost > 0 and cs.unique == "Frostbite" then cs.freezeChance = 0.15 end
	if cs.lightning > 0 then cs.chainChance = 0.30 end
	if cs.unique == "Stormlord" then cs.chainTargets = 4 end
	-- caps: gear crit is capped at 45% so that even with the Archer
	-- Deadeye passive (+15%) the total can never pass 60%; skill
	-- haste capped at 30% so cooldowns stay meaningful
	cs.crit = math.min(cs.crit, 0.45)
	cs.haste = math.min(cs.haste, 0.30)
	combatStats[player] = cs
	return cs
end

-- Thin lightning tracer between two points (chain lightning,
-- enchantment zaps, storm strikes)
function V7.tracer(fromPos, toPos, color)
	local delta = toPos - fromPos
	local len = delta.Magnitude
	if len < 0.5 then return end
	local p = Instance.new("Part")
	p.Name = "ChainTracer"
	p.Size = Vector3.new(0.22, 0.22, len)
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CFrame = CFrame.lookAt(fromPos + delta / 2, toPos)
	p.Parent = Workspace
	Debris:AddItem(p, 0.18)
end

-- THE v7 hit pipeline. Every player -> enemy damage path (sword,
-- staff, bow, all 12 skills) flows through here:
--   base (x set element multiplier for elemental skills)
--   + elemental flats from gear (shown as a small colored number)
--   x Execute bonus vs <30% HP, x crit roll (CRIT number)
-- then on-hit procs: lifesteal, ignite DoT, frost slow / freeze,
-- chain lightning, Inferno eruptions, Storm strikes, kill rewards
-- (Kill Regen, Mage mana refund), Warrior rage gain, Paladin holy
-- stacks. opts: { element = "Fire"|"Frost"|"Lightning",
-- source = "Sword"|..., rage = true }
function V7.hitEnemy(model, base, attacker, knockbackDir, opts)
	opts = opts or {}
	local data = enemies[model]
	if not data then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then return end
	local cs = attacker and combatStats[attacker]
	local fx = attacker and playerFx[attacker]
	local hpBefore = hum.Health
	local hpFrac = hpBefore / math.max(1, hum.MaxHealth)
	local phys = base
	local elemPart, elemColor = 0, nil
	local crit = false
	if attacker and cs then
		local fire = cs.fire * cs.fireMul
		local frost = cs.frost * cs.frostMul
		local bolt = cs.lightning * cs.lightningMul
		elemPart = fire + frost + bolt
		if elemPart > 0 then
			local best, bestV = "Fire", fire
			if frost > bestV then best, bestV = "Frost", frost end
			if bolt > bestV then best = "Lightning" end
			elemColor = V7.ELEM_COLORS[best]
		end
		if opts.element == "Fire" then phys = phys * cs.fireMul
		elseif opts.element == "Frost" then phys = phys * cs.frostMul
		elseif opts.element == "Lightning" then phys = phys * cs.lightningMul end
		if hpFrac < 0.30 then phys = phys * (1 + cs.execute) end
		local critChance = cs.crit
		if getClassId(attacker) == "Archer" then critChance = critChance + 0.15 end
		if math.random() < math.min(critChance, 0.60) then
			crit = true
			local critMul = 1 + cs.critDmg
			if cs.unique == "Executioner" and hpFrac < 0.30 then
				critMul = critMul + 1.5
			end
			phys = phys * critMul
			elemPart = elemPart * critMul
		end
	end
	local dealt = phys + elemPart
	damageEnemy(model, dealt, attacker, knockbackDir, {
		crit = crit,
		big = opts.big, -- v8: charge T2 number size
		elemAmount = elemPart >= 1 and elemPart or nil,
		elemColor = elemColor,
	})
	if not attacker or not cs then return end
	if fx then fx.lastCombat = os.clock() end
	local aHum = getHumanoid(attacker.Character)
	local now = os.clock()
	-- lifesteal (Vampiric unique doubles it)
	if cs.lifesteal > 0 and aHum and aHum.Health > 0 then
		local ls = cs.lifesteal * (cs.unique == "Vampiric" and 2 or 1)
		aHum.Health = math.min(aHum.MaxHealth, aHum.Health + dealt * ls)
	end
	-- Warrior rage: +6 per sword hit landed
	if opts.rage and getClassId(attacker) == "Warrior" then
		local rage = getStat(attacker, "Stats", "Rage")
		if rage then rage.Value = math.min(100, rage.Value + 6) end
	end
	-- Paladin holy stacks: every 4th sword hit bursts holy light
	if opts.source == "Sword" and fx and getClassId(attacker) == "Paladin" then
		fx.holy = (fx.holy or 0) + 1
		if fx.holy >= 4 then
			fx.holy = 0
			local burstDmg = playerWeaponDamage(attacker) * 0.8
				* classDamageMul(attacker, "melee")
			local pos = root.Position
			ringFX(pos, 8, V7.ELEM_COLORS.Holy, 0.35)
			for _, m2 in ipairs(enemiesWithin(pos, 8)) do
				damageEnemy(m2, burstDmg, attacker, nil,
					{ small = true, color = V7.ELEM_COLORS.Holy })
			end
			if aHum and aHum.Health > 0 then
				aHum.Health = math.min(aHum.MaxHealth, aHum.Health + burstDmg * 0.25)
			end
		end
	end
	-- kill rewards (the Died event pays XP/gold separately)
	if hum.Health <= 0 and hpBefore > 0 then
		if aHum and aHum.Health > 0 then
			local heal = cs.killRegen + (cs.unique == "Vampiric" and 25 or 0)
			if heal > 0 then
				aHum.Health = math.min(aHum.MaxHealth, aHum.Health + heal)
			end
		end
		if getClassId(attacker) == "Mage" then
			local mana = getStat(attacker, "Stats", "Mana")
			if mana then
				mana.Value = math.min(maxManaFor(attacker), mana.Value + 8)
			end
		end
		return -- no procs on a corpse
	end
	-- ignite: fire hits can set the enemy burning (DoT in tickStatus)
	if cs.fire > 0 and math.random() < cs.igniteChance then
		data.ignite = {
			dps = 3 + cs.fire * cs.fireMul * 0.8,
			expires = now + 3,
			attacker = attacker,
		}
	end
	-- frost: every frost hit slows; Frostbite unique can freeze solid
	if cs.frost > 0 then
		if now >= (data.slowUntil or 0) then
			data.slowUntil = now + 1.2
			data.slowFactor = 0.7
		else
			data.slowUntil = math.max(data.slowUntil, now + 1.2)
			data.slowFactor = math.min(data.slowFactor or 1, 0.7)
		end
		if cs.freezeChance > 0 and math.random() < cs.freezeChance then
			data.frozenUntil = now + 0.6
			frostFlash(model, data)
		end
	end
	-- chain lightning: jumps to the nearest enemies for 40%
	if cs.lightning > 0 and math.random() < cs.chainChance then
		local pos = root.Position
		local near = {}
		for m2, _ in pairs(enemies) do
			if m2 ~= model then
				local r2 = m2:FindFirstChild("HumanoidRootPart")
				if r2 then
					local d = horizontalDistance(pos, r2.Position)
					if d <= 14 then
						table.insert(near, { model = m2, dist = d })
					end
				end
			end
		end
		table.sort(near, function(a, b) return a.dist < b.dist end)
		local from = pos
		for i = 1, math.min(cs.chainTargets, #near) do
			local r2 = near[i].model:FindFirstChild("HumanoidRootPart")
			if r2 then
				V7.tracer(from, r2.Position, V7.ELEM_COLORS.Lightning)
				damageEnemy(near[i].model, dealt * 0.4, attacker, nil,
					{ small = true, color = V7.ELEM_COLORS.Lightning })
				from = r2.Position
			end
		end
	end
	-- Inferno eruption: the Legendary unique (strong, 1s CD) or
	-- the Inferno Lord 3pc bonus (weaker, 2.5s CD)
	local boomFactor, boomCd = nil, 0
	if cs.unique == "Inferno" then boomFactor, boomCd = 0.5, 1
	elseif cs.sets.Inferno >= 3 then boomFactor, boomCd = 0.35, 2.5 end
	if boomFactor and fx and now >= (fx.boomCd or 0) then
		fx.boomCd = now + boomCd
		local pos = root.Position
		ringFX(pos, 7, V7.ELEM_COLORS.Fire, 0.35)
		burstFX(pos, V7.ELEM_COLORS.Fire, 8)
		for _, m2 in ipairs(enemiesWithin(pos, 7)) do
			if m2 ~= model then
				damageEnemy(m2, dealt * boomFactor, attacker, nil,
					{ small = true, color = V7.ELEM_COLORS.Fire })
			end
		end
	end
	-- Storm Soul 3pc: crits call a lightning strike (2s CD)
	if crit and cs.stormStrike and fx and now >= (fx.strikeCd or 0) then
		fx.strikeCd = now + 2
		local pos = root.Position
		local beam = Instance.new("Part")
		beam.Name = "StormStrike"
		beam.Size = Vector3.new(1.3, 30, 1.3)
		beam.Color = V7.ELEM_COLORS.Lightning
		beam.Material = Enum.Material.Neon
		beam.Anchored = true
		beam.CanCollide = false
		beam.Position = pos + Vector3.new(0, 15, 0)
		beam.Parent = Workspace
		Debris:AddItem(beam, 0.25)
		damageEnemy(model, dealt * 0.8, attacker, nil,
			{ small = true, color = V7.ELEM_COLORS.Lightning })
	end
end

-- D2 Lightning Enchanted: when hit, the elite zaps its attacker
-- with 3 quick bolts (2s internal cooldown). Called from
-- damageEnemy; damage goes through the normal player-damage path.
function V7.lightningZap(model, data, attacker)
	local now = os.clock()
	if now < (data.zapCd or 0) then return end
	data.zapCd = now + 2
	task.spawn(function()
		for _ = 1, 3 do
			local phrp = getHRP(attacker.Character)
			local r2 = model:FindFirstChild("HumanoidRootPart")
			if not phrp or not r2 then break end
			V7.tracer(r2.Position + Vector3.new(0, 2, 0),
				phrp.Position + Vector3.new(0, 1.5, 0), V7.ELEM_COLORS.Lightning)
			AI.damagePlayer(attacker, data.damage * 0.35, model)
			task.wait(0.09)
		end
	end)
end

-- D2 Fire / Cold Enchanted death effects, called from
-- onEnemyDeath. Fire: AoE explosion. Cold: frost nova that also
-- SLOWS the players it hits (handled in V7.tickStatus).
function V7.enchantDeath(model, data)
	if data.enchant ~= "Fire" and data.enchant ~= "Cold" then return end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local pos = root.Position
	if data.enchant == "Fire" then
		ringFX(pos, 8, V7.ELEM_COLORS.Fire, 0.4)
		burstFX(pos, V7.ELEM_COLORS.Fire, 10)
		for _, p in ipairs(Players:GetPlayers()) do
			local phrp = getHRP(p.Character)
			if phrp and horizontalDistance(pos, phrp.Position) <= 8 then
				AI.damagePlayer(p, data.damage * 1.3, model)
			end
		end
	else
		ringFX(pos, 9, V7.ELEM_COLORS.Frost, 0.4)
		burstFX(pos, V7.ELEM_COLORS.Frost, 10)
		for _, p in ipairs(Players:GetPlayers()) do
			local phrp = getHRP(p.Character)
			if phrp and horizontalDistance(pos, phrp.Position) <= 9 then
				AI.damagePlayer(p, data.damage * 1.0, model)
				local fx = playerFx[p]
				if fx then fx.slowUntil = os.clock() + 2 end
			end
		end
	end
end

-- Kill feel: 3 soul orbs fly from the corpse to the killer
function V7.soulOrbs(fromPos, killer)
	task.spawn(function()
		local orbs = {}
		for i = 1, 3 do
			local o = Instance.new("Part")
			o.Name = "SoulOrb"
			o.Shape = Enum.PartType.Ball
			o.Size = Vector3.new(0.55, 0.55, 0.55)
			o.Color = Color3.fromRGB(160, 220, 255)
			o.Material = Enum.Material.Neon
			o.Anchored = true
			o.CanCollide = false
			o.Position = fromPos + Vector3.new((i - 2) * 0.8, 1 + 0.3 * i, 0)
			o.Parent = Workspace
			table.insert(orbs, o)
		end
		local t0 = os.clock()
		while os.clock() - t0 < 0.4 do
			local t = (os.clock() - t0) / 0.4
			local target = getHRP(killer.Character)
			for i, o in ipairs(orbs) do
				if o.Parent and target then
					local start = fromPos + Vector3.new((i - 2) * 0.8, 1 + 0.3 * i, 0)
					o.Position = start:Lerp(target.Position + Vector3.new(0, 1.5, 0), t * t)
				end
			end
			task.wait(0.03)
		end
		for _, o in ipairs(orbs) do o:Destroy() end
	end)
end

-- v7 weapon styling: per-class silhouettes with rarity colors and
-- set-element glow. Warrior = broad greatsword with a fuller line;
-- Paladin = warhammer with spikes + holy gem; others keep the
-- longsword silhouette. opts: { rarity, setId, classId } or
-- { tier, classId } for the blacksmith fallback.
function V7.styleWeapon(tool, opts)
	local handle = tool:FindFirstChild("Handle")
	if not handle then return end
	for _, name in ipairs({ "Blade", "BladeTip", "EdgeGlow", "Fuller",
		"HammerHead", "HammerSpike", "HammerGem" }) do
		local old = tool:FindFirstChild(name)
		if old then old:Destroy() end
	end
	local color, len, glow, glowColor
	if opts.rarity then
		local st = WEAPON_STYLE[opts.rarity] or WEAPON_STYLE.Common
		color, len, glow = st.color, st.len, st.glow
		glowColor = st.color
		if opts.setId and GEAR7.SETS[opts.setId] then
			glowColor = GEAR7.SETS[opts.setId].color
		end
		tool.Name = "Sword (" .. opts.rarity .. ")"
	else
		local tier = math.clamp(opts.tier or 1, 1, MAX_SWORD_TIER)
		color = TIER_COLORS[tier]
		len = 2.2 + (tier - 1) * 0.35
		glow = tier >= 4
		glowColor = color
		tool.Name = "Sword (Tier " .. tier .. ")"
	end
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
	if opts.classId == "Paladin" then
		-- warhammer: blocky head, two side spikes, glowing top gem
		addPart("HammerHead", "Part", Vector3.new(1.85, 1.85, 1.85),
			Vector3.new(0, 0.72 + 0.95, 0), color, Enum.Material.Metal)
		for _, sgn in ipairs({ -1, 1 }) do
			addPart("HammerSpike", "Part", Vector3.new(0.7, 0.7, 0.7),
				Vector3.new(sgn * 1.18, 0.72 + 0.95, 0), color, Enum.Material.Metal,
				CFrame.Angles(0, 0, math.rad(45)))
		end
		local gem = addPart("HammerGem", "Part", Vector3.new(0.68, 0.68, 0.68),
			Vector3.new(0, 0.72 + 1.95, 0), glowColor, Enum.Material.Neon)
		gem.Shape = Enum.PartType.Ball
		if glow then
			local gl = Instance.new("PointLight")
			gl.Color = glowColor
			gl.Range = 11
			gl.Brightness = 1.8
			gl.Parent = gem
		end
	else
		local width = (opts.classId == "Warrior") and 0.95 or 0.68 -- v8: chunkier blades
		addPart("Blade", "Part", Vector3.new(0.22, len, width),
			Vector3.new(0, 0.72 + len / 2, 0), color, Enum.Material.Metal)
		addPart("BladeTip", "WedgePart", Vector3.new(0.22, 0.6, width),
			Vector3.new(0, 0.72 + len + 0.3, 0), color, Enum.Material.Metal,
			CFrame.Angles(math.rad(-90), 0, 0))
		-- fuller: the dark groove line down the blade's flat
		addPart("Fuller", "Part", Vector3.new(0.05, len * 0.7, 0.09),
			Vector3.new(0.1, 0.72 + len / 2, 0),
			Color3.fromRGB(96, 96, 116), Enum.Material.Metal)
		if glow then
			local edge = addPart("EdgeGlow", "Part", Vector3.new(0.22, len, width + 0.06),
				Vector3.new(0, 0.72 + len / 2, 0), glowColor, Enum.Material.Neon)
			edge.Transparency = 0.35
			local gl = Instance.new("PointLight")
			gl.Color = glowColor
			gl.Range = (opts.rarity == "Legendary") and 15 or 10
			gl.Brightness = 1.8
			gl.Parent = edge
		end
	end
end

-- Boss HP bar (top-center), refreshed by the status loop while a
-- boss is alive
function V7.updateBossBar(player)
	local playerGui = player:FindFirstChild("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild("ShiningHUD")
	local bar = gui and gui:FindFirstChild("BossBar")
	if not bar then return end
	for model, data in pairs(enemies) do
		if data.isBoss then
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				bar.Visible = true
				local fill = bar:FindFirstChild("BossFill")
				if fill then
					fill.Size = UDim2.fromScale(
						math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1), 1)
				end
				local label = bar:FindFirstChild("BossName")
				if label then
					label.Text = "BOSS: Skeleton King"
						.. (data.ai.enraged and " (ENRAGED)" or "")
						.. "   " .. math.ceil(hum.Health) .. " / " .. hum.MaxHealth
				end
				return
			end
		end
	end
	bar.Visible = false
end

-- 0.5s status tick (spawned with the other main loops): ignite
-- DoT ticks, boss bars, Cold-enchant player slows expiring.
function V7.tickStatus()
	local now = os.clock()
	for model, data in pairs(enemies) do
		if data.ignite then
			if now < data.ignite.expires then
				damageEnemy(model, data.ignite.dps * 0.5, data.ignite.attacker, nil,
					{ small = true, color = V7.ELEM_COLORS.Fire })
			else
				data.ignite = nil
			end
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		V7.updateBossBar(p)
		local fx = playerFx[p]
		if fx and fx.slowUntil then
			local hum = getHumanoid(p.Character)
			if hum then
				if now < fx.slowUntil then
					local classVal = getStat(p, "Stats", "Class")
					local base = modsForClass(classVal and classVal.Value or "").speed
					local st = gearState[p]
					local boots = (st and st.equipped.Boots) and st.equipped.Boots.stat or 0
					local cs = combatStats[p]
					hum.WalkSpeed = (base + boots + (cs and cs.swiftness or 0)) * 0.6
					fx.wasSlowed = true
				elseif fx.wasSlowed then
					fx.wasSlowed = false
					fx.slowUntil = nil
					applyGear(p)
				end
			end
		end
	end
end

--====================================================================
-- ARROWS + BOW (Archer tool; also used by Multishot)
--====================================================================
-- One glowing arrow, auto-aimed at targetModel (mild homing, like
-- the fireball). With pierce=true it flies straight and damages
-- every enemy it touches instead of dying on the first hit.
-- v7: opts (optional) is forwarded to V7.hitEnemy; Archer shots
-- that travel more than 30 studs deal +25% (longshot identity).
local function launchArrow(player, targetModel, yawDeg, dmg, pierce, opts)
	local character = player.Character
	local hrp = getHRP(character)
	if not hrp then return end
	local origin = hrp.Position + Vector3.new(0, 1.6, 0) + hrp.CFrame.LookVector * 2
	local dir = hrp.CFrame.LookVector
	local eroot = targetModel and targetModel:FindFirstChild("HumanoidRootPart")
	if eroot then
		local toT = (eroot.Position + Vector3.new(0, 1.2, 0)) - origin
		if toT.Magnitude > 0.1 then dir = toT.Unit end
	end
	if yawDeg and yawDeg ~= 0 then
		dir = CFrame.Angles(0, math.rad(yawDeg), 0) * dir
	end
	local arrow = Instance.new("Part")
	arrow.Name = "ArrowProjectile"
	arrow.Size = Vector3.new(0.15, 0.15, 2.3)
	arrow.Color = Color3.fromRGB(255, 240, 200)
	arrow.Material = Enum.Material.Neon
	arrow.CanCollide = false
	arrow.CFrame = CFrame.lookAt(origin, origin + dir)
	arrow.Parent = Workspace
	arrow.AssemblyLinearVelocity = dir * 115
	Debris:AddItem(arrow, 2)
	if targetModel and not pierce then
		task.spawn(function()
			local started = os.clock()
			while arrow.Parent and os.clock() - started < 2 do
				if not enemies[targetModel] then break end
				local er = targetModel:FindFirstChild("HumanoidRootPart")
				if not er then break end
				local toT = (er.Position + Vector3.new(0, 1.2, 0)) - arrow.Position
				if toT.Magnitude > 0.1 then
					arrow.AssemblyLinearVelocity = toT.Unit * 115
					arrow.CFrame = CFrame.lookAt(arrow.Position, arrow.Position + toT)
				end
				task.wait(0.03)
			end
		end)
	end
	local hitSet = {}
	local hitFn = V7.hitEnemy or damageEnemy
	arrow.Touched:Connect(function(hit)
		if not arrow.Parent then return end
		if hit and character and hit:IsDescendantOf(character) then return end
		local model = hit and hit.Parent
		if model and model.Parent == enemiesFolder and enemies[model] then
			-- v7 Archer longshot: measure the flight distance from
			-- the shot's origin to the victim
			local hitDmg = dmg
			local eroot2 = model:FindFirstChild("HumanoidRootPart")
			if eroot2 and getClassId(player) == "Archer"
				and horizontalDistance(origin, eroot2.Position) > 30 then
				hitDmg = dmg * 1.25
			end
			if pierce then
				if hitSet[model] then return end
				hitSet[model] = true
				hitFn(model, hitDmg, player, dir, opts)
			else
				hitFn(model, hitDmg, player, dir, opts)
				arrow:Destroy()
			end
		elseif hit and hit.Anchored and not pierce then
			arrow:Destroy()
		end
	end)
end

local BOW_COOLDOWN = 0.45
local BOW_RANGE = 70

local function createBowTool(player)
	local tool = Instance.new("Tool")
	tool.Name = "Bow"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	-- modeled bow: wooden grip (Handle), two angled arms, neon string
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 1.1, 0.3)
	handle.Color = Color3.fromRGB(136, 96, 54)
	handle.Material = Enum.Material.Wood
	handle.Parent = tool
	for _, sgn in ipairs({ -1, 1 }) do
		local arm = Instance.new("WedgePart")
		arm.Name = "BowArm"
		arm.Size = Vector3.new(0.22, 1.5, 0.34)
		arm.Color = Color3.fromRGB(152, 106, 56)
		arm.Material = Enum.Material.Wood
		arm.CFrame = handle.CFrame * CFrame.new(0, sgn * 1.15, 0.18)
			* CFrame.Angles(math.rad(sgn * 18), 0, 0)
		arm.Parent = tool
		weldTo(arm, handle)
		-- v7: second, more sharply angled limb segment + metal tip
		-- so the bow reads as a curved recurve, not two sticks
		local tip = Instance.new("WedgePart")
		tip.Name = "BowTip"
		tip.Size = Vector3.new(0.18, 1.1, 0.28)
		tip.Color = Color3.fromRGB(152, 106, 56)
		tip.Material = Enum.Material.Wood
		tip.CFrame = handle.CFrame * CFrame.new(0, sgn * 2.25, 0.42)
			* CFrame.Angles(math.rad(sgn * 42), 0, 0)
		tip.Parent = tool
		weldTo(tip, handle)
		local cap = Instance.new("Part")
		cap.Name = "BowCap"
		cap.Size = Vector3.new(0.24, 0.3, 0.32)
		cap.Color = Color3.fromRGB(200, 170, 90)
		cap.Material = Enum.Material.Metal
		cap.CFrame = handle.CFrame * CFrame.new(0, sgn * 2.8, 0.62)
			* CFrame.Angles(math.rad(sgn * 42), 0, 0)
		cap.Parent = tool
		weldTo(cap, handle)
	end
	local stringPart = Instance.new("Part")
	stringPart.Name = "String"
	stringPart.Size = Vector3.new(0.05, 5.4, 0.05)
	stringPart.Color = Color3.fromRGB(235, 235, 225)
	stringPart.Material = Enum.Material.Neon
	stringPart.CFrame = handle.CFrame * CFrame.new(0, 0, 0.6)
	stringPart.Parent = tool
	weldTo(stringPart, handle)
	tool.Activated:Connect(function()
		local now = os.clock()
		local rec = lastAction[player]
		if not rec then return end
		-- v7: Attack Speed affix divides the draw cooldown (0.25s floor)
		local cs = combatStats[player]
		local bowCd = math.max(0.25, BOW_COOLDOWN / (1 + (cs and cs.atkSpeed or 0)))
		if (now - (rec.bow or 0)) < bowCd then return end
		local hrp = getHRP(player.Character)
		if not hrp then return end
		rec.bow = now
		local target = nearestEnemy(player, BOW_RANGE)
		local dmg = playerRangedDamage(player) * classDamageMul(player, "ranged")
		launchArrow(player, target, 0, dmg, false, { source = "Bow" })
		playSfx("Swing", hrp, true)
	end)
	return tool
end

--====================================================================
-- CLASS TOOL LOADOUTS
--====================================================================
local KNOWN_TOOL_PREFIXES = { "Sword", "Fireball", "Drink Potion", "Bow" }

local function isLoadoutTool(tool)
	for _, p in ipairs(KNOWN_TOOL_PREFIXES) do
		if string.find(tool.Name, p, 1, true) then return true end
	end
	return false
end

local function removeAllTools(player)
	for _, container in ipairs({ player:FindFirstChild("Backpack"), player.Character }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and isLoadoutTool(item) then
					item:Destroy()
				end
			end
		end
	end
end

local function classLoadout(player)
	local cid = getClassId(player)
	if cid == "Warrior" or cid == "Paladin" then
		return { "Sword", "Drink Potion" }
	elseif cid == "Mage" then
		return { "Fireball", "Drink Potion" }
	elseif cid == "Archer" then
		return { "Bow", "Drink Potion" }
	end
	return { "Sword", "Fireball", "Drink Potion" } -- no class yet: v4 trio
end

local function createToolByPrefix(player, prefix)
	if prefix == "Sword" then return createSword(player) end
	if prefix == "Fireball" then return createFireballTool(player) end
	if prefix == "Bow" then return createBowTool(player) end
	if prefix == "Drink Potion" then return createPotionTool(player) end
	return nil
end

local function giveClassTools(player)
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end
	for _, prefix in ipairs(classLoadout(player)) do
		local t = createToolByPrefix(player, prefix)
		if t then t.Parent = backpack end
	end
	restylePlayerSword(player)
end

--====================================================================
-- SKILL IMPLEMENTATIONS (formulas in the comments; lv = 1..5)
--====================================================================
-- WARRIOR 1: Whirlwind -- (120% + 20%/lv) weapon dmg, radius 9
local function castWhirlwind(player, lv)
	local hrp = getHRP(player.Character)
	if not hrp then return end
	local dmg = playerWeaponDamage(player) * (1.2 + 0.2 * lv)
		* classDamageMul(player, "melee")
		* V7.synergyMul(player, "Warrior", 1) -- v7 D2 synergy (War Cry)
	local hitFn = V7.hitEnemy or damageEnemy
	for _, model in ipairs(enemiesWithin(hrp.Position, 9)) do
		local eroot = model:FindFirstChild("HumanoidRootPart")
		local dir = nil
		if eroot then
			local off = eroot.Position - hrp.Position
			if off.Magnitude > 0.1 then dir = off.Unit end
		end
		hitFn(model, dmg, player, dir, { source = "Skill" })
	end
	playSfx("Swing", hrp, true)
	spawnSlashFX(hrp)
	task.delay(0.1, function() if hrp.Parent then spawnSlashFX(hrp) end end)
	task.delay(0.2, function() if hrp.Parent then spawnSlashFX(hrp) end end)
	-- spin the character one full turn over 0.3s
	local startRot = hrp.CFrame - hrp.Position
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.3 do
			if not hrp.Parent then return end
			local t = (os.clock() - t0) / 0.3
			hrp.CFrame = CFrame.new(hrp.Position) * startRot
				* CFrame.Angles(0, math.rad(360 * t), 0)
			task.wait(0.03)
		end
		if hrp.Parent then
			hrp.CFrame = CFrame.new(hrp.Position) * startRot
		end
	end)
end

-- WARRIOR 2: Charge -- dash up to 16 studs, (100% + 25%/lv) weapon
-- dmg to every enemy passed through
local function castCharge(player, lv)
	local hrp = getHRP(player.Character)
	if not hrp then return end
	local target = nearestEnemy(player, 40)
	local dir = hrp.CFrame.LookVector
	local dist = 16
	if target then
		local eroot = target:FindFirstChild("HumanoidRootPart")
		if eroot then
			local off = Vector3.new(eroot.Position.X - hrp.Position.X, 0,
				eroot.Position.Z - hrp.Position.Z)
			if off.Magnitude > 0.1 then
				dir = off.Unit
				dist = math.clamp(off.Magnitude - 3, 2, 16)
			end
		end
	end
	hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + dir)
	local dmg = playerWeaponDamage(player) * (1.0 + 0.25 * lv)
		* classDamageMul(player, "melee")
		* V7.synergyMul(player, "Warrior", 2) -- v7 D2 synergy (War Cry)
	local hitFn = V7.hitEnemy or damageEnemy
	local startPos = hrp.Position
	local startRot = hrp.CFrame - hrp.Position
	local hitSet = {}
	playSfx("Swing", hrp, true)
	task.spawn(function()
		local t0 = os.clock()
		local dur = 0.18
		while os.clock() - t0 < dur do
			if not hrp.Parent then return end
			local t = (os.clock() - t0) / dur
			hrp.CFrame = CFrame.new(startPos + dir * (dist * t)) * startRot
			for _, model in ipairs(enemiesWithin(hrp.Position, 4)) do
				if not hitSet[model] then
					hitSet[model] = true
					hitFn(model, dmg, player, dir, { source = "Skill" })
				end
			end
			task.wait(0.02)
		end
	end)
end

-- WARRIOR 3: War Cry -- 10s self buff: +(15% + 3%/lv) damage,
-- +(10% + 2%/lv) damage reduction (read by the mul functions)
local function castWarCry(player, lv)
	buffs[player] = {
		dmgMul = 1 + (0.15 + 0.03 * lv),
		defRed = 0.10 + 0.02 * lv,
		expires = os.clock() + 10,
	}
	local hrp = getHRP(player.Character)
	if hrp then
		ringFX(hrp.Position, 8, Color3.fromRGB(255, 200, 80))
		playSfx("LevelUp", hrp)
	end
	showToast(player, "War Cry! +" .. math.floor((0.15 + 0.03 * lv) * 100)
		.. "% damage for 10s", 2)
end

-- MAGE 1: Frost Nova -- (60% + 15%/lv) spell dmg, radius 11, and
-- SLOW 50% for (2 + 0.3/lv) s (data.slowUntil / slowFactor, AI loop)
local function castFrostNova(player, lv)
	local hrp = getHRP(player.Character)
	if not hrp then return end
	local dmg = playerSpellDamage(player) * (0.6 + 0.15 * lv)
		* classDamageMul(player, "spell")
		* V7.synergyMul(player, "Mage", 1) -- v7 D2 synergy (Meteor)
	local slowTime = 2 + 0.3 * lv
	local hitFn = V7.hitEnemy or damageEnemy
	for _, model in ipairs(enemiesWithin(hrp.Position, 11)) do
		local data = enemies[model]
		if data then
			data.slowUntil = os.clock() + slowTime
			data.slowFactor = 0.5
			frostFlash(model, data)
		end
		hitFn(model, dmg, player, nil, { source = "Skill", element = "Frost" })
	end
	ringFX(hrp.Position, 11, Color3.fromRGB(130, 200, 255))
	playSfx("Hit", hrp, true)
end

-- MAGE 2: Meteor -- telegraph 0.8s at the target's position, then
-- (200% + 40%/lv) spell dmg in radius 9
local function castMeteor(player, lv, target)
	local eroot = target and target:FindFirstChild("HumanoidRootPart")
	if not eroot then return end
	local impactPos = Vector3.new(eroot.Position.X, 0, eroot.Position.Z)
	local tele = Instance.new("Part")
	tele.Name = "MeteorTelegraph"
	tele.Shape = Enum.PartType.Cylinder
	tele.Size = Vector3.new(0.3, 18, 18)
	tele.CFrame = CFrame.new(impactPos.X, 0.35, impactPos.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	tele.Color = Color3.fromRGB(255, 70, 50)
	tele.Material = Enum.Material.Neon
	tele.Transparency = 0.55
	tele.Anchored = true
	tele.CanCollide = false
	tele.Parent = Workspace
	Debris:AddItem(tele, 1)
	local rock = Instance.new("Part")
	rock.Name = "MeteorRock"
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.new(2.6, 2.6, 2.6)
	rock.Color = Color3.fromRGB(255, 140, 50)
	rock.Material = Enum.Material.Neon
	rock.CanCollide = false
	rock.Position = impactPos + Vector3.new(0, 24, 0)
	rock.Parent = Workspace
	local rl = Instance.new("PointLight")
	rl.Color = Color3.fromRGB(255, 150, 60)
	rl.Range = 16
	rl.Brightness = 2.5
	rl.Parent = rock
	rock.AssemblyLinearVelocity = Vector3.new(0, -30, 0)
	Debris:AddItem(rock, 0.85)
	task.delay(0.8, function()
		if tele.Parent then tele:Destroy() end
		local dmg = playerSpellDamage(player) * (2.0 + 0.4 * lv)
			* classDamageMul(player, "spell")
			* V7.synergyMul(player, "Mage", 2) -- v7 D2 synergy (Frost Nova)
		local hitFn = V7.hitEnemy or damageEnemy
		for _, model in ipairs(enemiesWithin(impactPos, 9)) do
			hitFn(model, dmg, player, nil, { source = "Skill", element = "Fire" })
		end
		ringFX(impactPos, 9, Color3.fromRGB(255, 130, 50))
		burstFX(impactPos + Vector3.new(0, 2, 0), Color3.fromRGB(255, 150, 60), 14)
		playSfx("Hit", getHRP(player.Character), true)
	end)
end

-- MAGE 3: Teleport -- blink 18 studs toward facing / nearest enemy,
-- clamped inside the dungeon walls when cast in the dungeon
local function castTeleport(player, lv)
	local hrp = getHRP(player.Character)
	if not hrp then return end
	local dir = hrp.CFrame.LookVector
	local target = nearestEnemy(player, 40)
	if target then
		local eroot = target:FindFirstChild("HumanoidRootPart")
		if eroot then
			local off = Vector3.new(eroot.Position.X - hrp.Position.X, 0,
				eroot.Position.Z - hrp.Position.Z)
			if off.Magnitude > 0.1 then dir = off.Unit end
		end
	end
	burstFX(hrp.Position + Vector3.new(0, 1.5, 0), Color3.fromRGB(170, 120, 255), 10)
	local newPos = hrp.Position + dir * 18
	if inDungeon(hrp.Position) then
		-- v8: clamp to the AUTHORED room extents, not the symmetric
		-- half extents -- the room chain spans rel x -92..92,
		-- z -100..85; landing past the entrance hall's south wall
		-- (rel +85) would put the player inside the rock fill
		newPos = Vector3.new(
			math.clamp(newPos.X, DUNGEON_CENTER.X - 90,
				DUNGEON_CENTER.X + 90),
			hrp.Position.Y,
			math.clamp(newPos.Z, DUNGEON_CENTER.Z - 97,
				DUNGEON_CENTER.Z + 82))
	end
	hrp.CFrame = CFrame.new(newPos) * (hrp.CFrame - hrp.Position)
	hrp.AssemblyLinearVelocity = Vector3.zero
	burstFX(newPos + Vector3.new(0, 1.5, 0), Color3.fromRGB(170, 120, 255), 10)
	playSfx("Equip", hrp)
end

-- ARCHER 1: Multishot -- (3 + 1 per 2 levels) arrows in a fan,
-- each 80% ranged dmg
local function castMultishot(player, lv, target)
	local count = 3 + math.floor(lv / 2)
	local dmg = playerRangedDamage(player) * 0.8
		* classDamageMul(player, "ranged")
		* V7.synergyMul(player, "Archer", 1) -- v7 D2 synergy (Piercing Shot)
	for i = 1, count do
		local offset = (i - (count + 1) / 2) * 7 -- degrees of fan spread
		launchArrow(player, target, offset, dmg, false, { source = "Skill" })
	end
	playSfx("Swing", getHRP(player.Character), true)
end

-- ARCHER 2: Piercing Shot -- hitscan line, (150% + 30%/lv) ranged
-- dmg to EVERY enemy within 3.5 studs of the shot line (60 long)
local function castPiercingShot(player, lv, target)
	local hrp = getHRP(player.Character)
	if not hrp then return end
	local origin = hrp.Position + Vector3.new(0, 1.6, 0)
	local dir = hrp.CFrame.LookVector
	local eroot = target and target:FindFirstChild("HumanoidRootPart")
	if eroot then
		local flat = Vector3.new(eroot.Position.X - origin.X, 0,
			eroot.Position.Z - origin.Z)
		if flat.Magnitude > 0.1 then dir = flat.Unit end
	end
	local dmg = playerRangedDamage(player) * (1.5 + 0.3 * lv)
		* classDamageMul(player, "ranged")
		* V7.synergyMul(player, "Archer", 2) -- v7 D2 synergy (Multishot)
	local hitFn = V7.hitEnemy or damageEnemy
	local LENGTH = 60
	for model, _ in pairs(enemies) do
		local er = model:FindFirstChild("HumanoidRootPart")
		if er then
			local rel = Vector3.new(er.Position.X - origin.X, 0,
				er.Position.Z - origin.Z)
			local along = rel:Dot(dir)
			if along > 0 and along < LENGTH then
				local closest = origin + dir * along
				if horizontalDistance(er.Position, closest) <= 3.5 then
					hitFn(model, dmg, player, dir, { source = "Skill" })
				end
			end
		end
	end
	local tracer = Instance.new("Part")
	tracer.Name = "PierceTracer"
	tracer.Size = Vector3.new(0.22, 0.22, LENGTH)
	tracer.Color = Color3.fromRGB(255, 240, 180)
	tracer.Material = Enum.Material.Neon
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CFrame = CFrame.lookAt(origin + dir * (LENGTH / 2), origin + dir * LENGTH)
	tracer.Parent = Workspace
	Debris:AddItem(tracer, 0.25)
	task.spawn(function()
		local t0 = os.clock()
		while tracer.Parent and os.clock() - t0 < 0.22 do
			tracer.Transparency = (os.clock() - t0) / 0.22
			task.wait(0.03)
		end
		if tracer.Parent then tracer:Destroy() end
	end)
	playSfx("Swing", hrp, true)
end

-- ARCHER 3: Arrow Rain -- telegraph ring, then 5 waves over 1.5s
-- on the target cluster (radius 10), each wave (40% + 10%/lv)
local function castArrowRain(player, lv, target)
	local eroot = target and target:FindFirstChild("HumanoidRootPart")
	if not eroot then return end
	local center = Vector3.new(eroot.Position.X, 0, eroot.Position.Z)
	ringFX(center, 10, Color3.fromRGB(255, 190, 90), 0.5)
	local dmg = playerRangedDamage(player) * (0.4 + 0.1 * lv)
		* classDamageMul(player, "ranged")
		* V7.synergyMul(player, "Archer", 3) -- v7 D2 synergy (Multishot)
	local hitFn = V7.hitEnemy or damageEnemy
	task.spawn(function()
		for _ = 1, 5 do
			for _ = 1, 7 do
				local a = Instance.new("Part")
				a.Name = "RainArrow"
				a.Size = Vector3.new(0.14, 0.14, 2)
				a.Color = Color3.fromRGB(255, 240, 200)
				a.Material = Enum.Material.Neon
				a.CanCollide = false
				a.Position = Vector3.new(
					center.X + math.random(-9, 9), center.Y + 20,
					center.Z + math.random(-9, 9))
				a.CFrame = CFrame.new(a.Position) * CFrame.Angles(math.rad(90), 0, 0)
				a.Parent = Workspace
				a.AssemblyLinearVelocity = Vector3.new(0, -55, 0)
				Debris:AddItem(a, 0.45)
			end
			for _, model in ipairs(enemiesWithin(center, 10)) do
				hitFn(model, dmg, player, nil, { source = "Skill" })
			end
			playSfx("Hit", getHRP(player.Character), true)
			task.wait(0.3)
		end
	end)
end

-- PALADIN 1: Blessed Hammer -- a hammer orbits the player for
-- (4 + 0.5/lv) s, hitting enemies it touches every 0.4s for
-- (70% + 15%/lv) weapon dmg
local function castBlessedHammer(player, lv)
	local hrp = getHRP(player.Character)
	if not hrp then return end
	local duration = 4 + 0.5 * lv
	local dmg = playerWeaponDamage(player) * (0.7 + 0.15 * lv)
		* classDamageMul(player, "melee")
		* V7.synergyMul(player, "Paladin", 1) -- v7 D2 synergy (Thorns Aura)
	local hitFn = V7.hitEnemy or damageEnemy
	local hammer = Instance.new("Part")
	hammer.Name = "BlessedHammer"
	hammer.Size = Vector3.new(1.1, 1.6, 1.1)
	hammer.Color = Color3.fromRGB(255, 215, 110)
	hammer.Material = Enum.Material.Neon
	hammer.CanCollide = false
	hammer.Anchored = true
	hammer.Position = hrp.Position + Vector3.new(5.5, 1.4, 0)
	hammer.Parent = Workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 215, 110)
	light.Range = 11
	light.Brightness = 2
	light.Parent = hammer
	playSfx("Swing", hrp, true)
	task.spawn(function()
		local t0 = os.clock()
		local lastHit = 0
		while os.clock() - t0 < duration do
			local h = getHRP(player.Character)
			if not h or not hammer.Parent then break end
			local ang = (os.clock() - t0) * 2.6
			local pos = h.Position + Vector3.new(
				math.cos(ang) * 5.5, 1.4, math.sin(ang) * 5.5)
			hammer.CFrame = CFrame.new(pos) * CFrame.Angles(0, -ang, math.rad(35))
			if os.clock() - lastHit >= 0.4 then
				lastHit = os.clock()
				for _, model in ipairs(enemiesWithin(pos, 3.2)) do
					hitFn(model, dmg, player, nil, { source = "Skill", element = "Holy" })
				end
			end
			task.wait(0.04)
		end
		hammer:Destroy()
	end)
end

-- PALADIN 2: Heal -- restore (25% + 5%/lv) MaxHP to self and every
-- ally within 14 studs
local function castHeal(player, lv)
	local hrp = getHRP(player.Character)
	if not hrp then return end
	local frac = (0.25 + 0.05 * lv)
		* V7.synergyMul(player, "Paladin", 2) -- v7 D2 synergy (Blessed Hammer)
	for _, p in ipairs(Players:GetPlayers()) do
		local hum = getHumanoid(p.Character)
		local phrp = getHRP(p.Character)
		if hum and phrp and hum.Health > 0
			and horizontalDistance(hrp.Position, phrp.Position) <= 14 then
			hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * frac)
			burstFX(phrp.Position + Vector3.new(0, 2, 0),
				Color3.fromRGB(110, 255, 150), 8)
		end
	end
	ringFX(hrp.Position, 14, Color3.fromRGB(110, 255, 150))
	playSfx("LevelUp", hrp)
end

-- Description helper: current-level text + next-level text
local function d2(curText, nextText, lv)
	if lv >= 5 then return curText .. " (MAX)" end
	if lv >= 1 then return curText .. "\nNext: " .. nextText end
	return nextText
end

-- Skill definitions: cd / mana are flat per cast; needsTarget =
-- max range for skills that require an enemy (validated BEFORE
-- mana + cooldown are charged). Thorns Aura is a toggle.
local SKILLS = {
	Warrior = {
		-- v7: Warrior skills spend RAGE (built by sword hits), not mana
		{ name = "Whirlwind", cd = 6, mana = 15, rage = 30, cast = castWhirlwind, desc = function(lv)
			return d2("Spin: " .. (120 + 20 * lv) .. "% weapon dmg to all enemies within 9",
				"Spin: " .. (120 + 20 * (lv + 1)) .. "% weapon dmg to all enemies within 9", lv)
		end },
		{ name = "Charge", cd = 8, mana = 10, rage = 20, cast = castCharge, desc = function(lv)
			return d2("Dash 16 studs: " .. (100 + 25 * lv) .. "% weapon dmg to enemies passed through",
				"Dash 16 studs: " .. (100 + 25 * (lv + 1)) .. "% weapon dmg to enemies passed through", lv)
		end },
		{ name = "War Cry", cd = 20, mana = 20, rage = 25, cast = castWarCry, desc = function(lv)
			return d2("Buff 10s: +" .. (15 + 3 * lv) .. "% damage, +" .. (10 + 2 * lv) .. "% defense",
				"Buff 10s: +" .. (15 + 3 * (lv + 1)) .. "% damage, +" .. (10 + 2 * (lv + 1)) .. "% defense", lv)
		end },
	},
	Mage = {
		{ name = "Frost Nova", cd = 9, mana = 25, cast = castFrostNova, desc = function(lv)
			return d2((60 + 15 * lv) .. "% spell dmg, radius 11, slow 50% for " .. (2 + 0.3 * lv) .. "s",
				(60 + 15 * (lv + 1)) .. "% spell dmg, radius 11, slow 50% for " .. (2 + 0.3 * (lv + 1)) .. "s", lv)
		end },
		{ name = "Meteor", cd = 12, mana = 35, needsTarget = 60, cast = castMeteor, desc = function(lv)
			return d2("After 0.8s: " .. (200 + 40 * lv) .. "% spell dmg in radius 9 at the target",
				"After 0.8s: " .. (200 + 40 * (lv + 1)) .. "% spell dmg in radius 9 at the target", lv)
		end },
		{ name = "Teleport", cd = 7, mana = 15, cast = castTeleport, desc = function(_)
			return "Blink 18 studs toward your facing (or the nearest enemy)."
		end },
	},
	Archer = {
		{ name = "Multishot", cd = 7, mana = 15, needsTarget = 70, cast = castMultishot, desc = function(lv)
			return d2("Fire " .. (3 + math.floor(lv / 2)) .. " arrows in a fan, 80% ranged dmg each",
				"Fire " .. (3 + math.floor((lv + 1) / 2)) .. " arrows in a fan, 80% ranged dmg each", lv)
		end },
		{ name = "Piercing Shot", cd = 9, mana = 20, needsTarget = 70, cast = castPiercingShot, desc = function(lv)
			return d2((150 + 30 * lv) .. "% ranged dmg to ALL enemies along the shot line",
				(150 + 30 * (lv + 1)) .. "% ranged dmg to ALL enemies along the shot line", lv)
		end },
		{ name = "Arrow Rain", cd = 14, mana = 30, needsTarget = 60, cast = castArrowRain, desc = function(lv)
			return d2("5 waves over 1.5s: " .. (40 + 10 * lv) .. "% ranged dmg each, radius 10",
				"5 waves over 1.5s: " .. (40 + 10 * (lv + 1)) .. "% ranged dmg each, radius 10", lv)
		end },
	},
	Paladin = {
		{ name = "Blessed Hammer", cd = 12, mana = 20, cast = castBlessedHammer, desc = function(lv)
			return d2("Orbiting hammer for " .. (4 + 0.5 * lv) .. "s: " .. (70 + 15 * lv) .. "% weapon dmg per hit",
				"Orbiting hammer for " .. (4 + 0.5 * (lv + 1)) .. "s: " .. (70 + 15 * (lv + 1)) .. "% weapon dmg per hit", lv)
		end },
		{ name = "Heal", cd = 15, mana = 25, cast = castHeal, desc = function(lv)
			return d2("Heal self + allies within 14 for " .. (25 + 5 * lv) .. "% of MaxHP",
				"Heal self + allies within 14 for " .. (25 + 5 * (lv + 1)) .. "% of MaxHP", lv)
		end },
		{ name = "Thorns Aura", cd = 0, mana = 0, toggle = true, desc = function(lv)
			return d2("Aura: reflect " .. (6 + 4 * lv) .. "% of enemy melee damage back",
				"Aura: reflect " .. (6 + 4 * (lv + 1)) .. "% of enemy melee damage back", lv)
				.. "\nToggle it from the skill bar / R key."
		end },
	},
}

-- Thorns Aura visual: a faint gold ring welded under the player,
-- rebuilt on toggle / respawn / class change.
local function refreshThornsAura(player)
	local character = player.Character
	if not character then return end
	local old = character:FindFirstChild("ThornsAura")
	if old then old:Destroy() end
	local st = skillState[player]
	if not st or not st.thornsOn then return end
	if getClassId(player) ~= "Paladin" then return end
	local hrp = getHRP(character)
	if not hrp then return end
	local ring = Instance.new("Part")
	ring.Name = "ThornsAura"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.25, 7, 7)
	ring.Color = Color3.fromRGB(255, 205, 90)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.65
	ring.CFrame = hrp.CFrame * CFrame.new(0, -2.7, 0)
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = character
	weldGearPart(ring, hrp)
end

--====================================================================
-- CLASS + SKILLS UI (server-built; clicks arrive via UIEvent)
--====================================================================
-- v7: each card LEADS with the class identity line so the four
-- classes read as four different games before you pick one
local CLASS_PITCH = {
	Warrior = "RAGE melee cleaver\nHP x1.4  Melee x1.25\nSword cleaves 3 foes;\nskills spend Rage, not mana",
	Mage = "Burst elemental caster\nSpell x1.4  Mana x1.8\nStaff fires 3-bolt bursts;\nkills refund 8 mana",
	Archer = "Long-range crit sniper\nRanged x1.3  Speed 17.5\n+15% crit (Deadeye);\nlongshots deal +25%",
	Paladin = "Holy tank-support\nHP x1.2  -5% dmg taken\nEvery 4th hit bursts holy\nlight; aura heals allies",
}

local function buildClassUI(player)
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShiningClass"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local classButton = Instance.new("TextButton")
	classButton.Name = "ClassButton"
	classButton.Size = UDim2.new(0, 110, 0, 36)
	classButton.Position = UDim2.new(0, 12, 0, 248)
	classButton.Text = "Class"
	classButton.Font = Enum.Font.GothamBold
	classButton.TextSize = 16
	classButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	classButton.BackgroundColor3 = Color3.fromRGB(64, 48, 32)
	classButton.BackgroundTransparency = 0.15
	classButton.BorderSizePixel = 0
	classButton:SetAttribute("Act", "ToggleClass")
	classButton.Parent = gui

	-- class select panel: 4 cards, click one to take that class
	local panel = Instance.new("Frame")
	panel.Name = "ClassPanel"
	panel.Size = UDim2.new(0, 620, 0, 380)
	panel.Position = UDim2.new(0.5, -310, 0.5, -190)
	panel.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	makeLabel(panel, "Title", UDim2.new(1, -20, 0, 30), UDim2.new(0, 10, 0, 8),
		"CHOOSE YOUR CLASS", 20, Color3.fromRGB(255, 230, 160))
	local classButtons = {}
	for i, cid in ipairs(CLASS_IDS) do
		local def = CLASS_DEFS[cid]
		local skillNames = {}
		for _, s in ipairs(SKILLS[cid]) do
			table.insert(skillNames, s.name)
		end
		local b = Instance.new("TextButton")
		b.Name = "Class_" .. cid
		b.Size = UDim2.new(0, 140, 0, 250)
		b.Position = UDim2.new(0, 14 + (i - 1) * 150, 0, 48)
		b.Font = Enum.Font.Gotham
		b.TextSize = 13
		b.TextWrapped = true
		b.TextYAlignment = Enum.TextYAlignment.Top
		b.Text = def.name .. " (" .. def.cn .. ")\n\n" .. CLASS_PITCH[cid]
			.. "\n\n-- Skills --\n" .. table.concat(skillNames, "\n")
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.BackgroundColor3 = Color3.fromRGB(38, 38, 54)
		b.BorderSizePixel = 0
		b:SetAttribute("Act", "ChooseClass")
		b:SetAttribute("Arg", cid)
		b.Parent = panel
		classButtons[cid] = b
	end
	local note = makeLabel(panel, "Note", UDim2.new(1, -20, 0, 40),
		UDim2.new(0, 10, 0, 312),
		"Changing class keeps your level, gold and gear.\nSkill levels are saved per class.",
		13, Color3.fromRGB(170, 170, 185))
	note.TextWrapped = true

	-- skills panel (contents rebuilt by refreshSkillsUI)
	local skillsPanel = Instance.new("Frame")
	skillsPanel.Name = "SkillsPanel"
	skillsPanel.Size = UDim2.new(0, 540, 0, 404)
	skillsPanel.Position = UDim2.new(0.5, -270, 0.5, -202)
	skillsPanel.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
	skillsPanel.BackgroundTransparency = 0.08
	skillsPanel.BorderSizePixel = 0
	skillsPanel.Visible = false
	skillsPanel.Parent = gui

	-- skill bar: 3 cast buttons, bottom center-right of the toolbar
	local bar = Instance.new("Frame")
	bar.Name = "SkillBar"
	bar.Size = UDim2.new(0, 306, 0, 62)
	bar.Position = UDim2.new(0.5, 130, 1, -76)
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local barButtons = {}
	for i = 1, 3 do
		local b = Instance.new("TextButton")
		b.Name = "Skill" .. i
		b.Size = UDim2.new(0, 98, 0, 62)
		b.Position = UDim2.new(0, (i - 1) * 104, 0, 0)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.TextWrapped = true
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.BackgroundColor3 = Color3.fromRGB(30, 30, 46)
		b.BackgroundTransparency = 0.15
		b.BorderSizePixel = 0
		b:SetAttribute("Act", "CastSkill")
		b:SetAttribute("Arg", tostring(i))
		b.Parent = bar
		barButtons[i] = b
	end

	classRefs[player] = {
		gui = gui, panel = panel, skillsPanel = skillsPanel,
		classButtons = classButtons,
	}
	skillBarRefs[player] = { buttons = barButtons }
end

local function skillBarText(player, i)
	local classId = getClassId(player)
	if classId == "" then return "No class" end
	local def = SKILLS[classId][i]
	if not def then return "" end
	local lv = getSkillLevel(player, classId, i)
	if def.toggle then
		local st = skillState[player]
		return def.name .. "\n" .. (st and st.thornsOn and "ON" or "OFF")
			.. " [" .. HOTKEYS[i] .. "]"
	end
	if lv < 1 then
		-- v7: say HOW to learn it, not just "Locked"
		return def.name .. "\nLv0 - open Skills to learn [" .. HOTKEYS[i] .. "]"
	end
	local st = skillState[player]
	local remain = 0
	if st then
		remain = (st.cooldowns[classId .. i] or 0) - os.clock()
	end
	if remain > 0 then
		return def.name .. "\n" .. math.ceil(remain) .. "s [" .. HOTKEYS[i] .. "]"
	end
	return def.name .. "\nLv " .. lv .. " [" .. HOTKEYS[i] .. "]"
end

local function updateSkillBar(player)
	local refs = skillBarRefs[player]
	if not refs then return end
	for i = 1, 3 do
		local b = refs.buttons[i]
		if b then b.Text = skillBarText(player, i) end
	end
end

-- v7: class passive / resource descriptions for the Skills panel
V7.CLASS_PASSIVE = {
	Warrior = "Resource: RAGE 0-100 (sword hits +6, taking hits +3, decays out of combat). Passive: sword cleaves up to 3 enemies.",
	Mage = "Resource: Mana. Passive: Arcane Flow -- kills refund 8 mana. Staff attacks fire 3-bolt bursts.",
	Archer = "Resource: Mana. Passive: Deadeye -- +15% crit chance; shots flying 30+ studs deal +25%.",
	Paladin = "Resource: Mana. Passive: Holy Aura -- you and allies within 14 studs regen 1 HP/s; every 4th sword hit bursts holy light.",
}

local function refreshSkillsUI(player)
	local refs = classRefs[player]
	if not refs then return end
	local panel = refs.skillsPanel
	panel.Visible = skillsOpen[player] and true or false
	for _, child in ipairs(panel:GetChildren()) do
		child:Destroy()
	end
	local classId = getClassId(player)
	local sp = getStat(player, "Stats", "SkillPoints")
	local points = sp and sp.Value or 0
	local title = "SKILLS"
	if classId ~= "" then
		title = title .. " - " .. CLASS_DEFS[classId].name
	end
	makeLabel(panel, "Title", UDim2.new(1, -20, 0, 26), UDim2.new(0, 10, 0, 6),
		title, 18, Color3.fromRGB(255, 230, 160))
	-- v7: the Points line also shows the class resource
	local pointsText = "Skill Points available: " .. points .. "  (earn 1 per level-up)"
	if classId == "Warrior" then
		local rage = getStat(player, "Stats", "Rage")
		pointsText = pointsText .. "    RAGE: " .. (rage and rage.Value or 0) .. "/100"
	elseif classId ~= "" then
		local mana = getStat(player, "Stats", "Mana")
		pointsText = pointsText .. "    Mana: " .. (mana and mana.Value or 0)
			.. "/" .. maxManaFor(player)
	end
	makeLabel(panel, "Points", UDim2.new(1, -20, 0, 22), UDim2.new(0, 10, 0, 34),
		pointsText, 14, Color3.fromRGB(180, 220, 255))
	if classId == "" then
		makeLabel(panel, "NoClass", UDim2.new(1, -20, 0, 30), UDim2.new(0, 10, 0, 80),
			"Choose a class first (Class button, left side).", 15,
			Color3.fromRGB(200, 200, 210))
		return
	end
	for i = 1, 3 do
		local def = SKILLS[classId][i]
		local lv = getSkillLevel(player, classId, i)
		local y = 64 + (i - 1) * 96
		local pips = string.rep("●", lv) .. string.rep("○", 5 - lv)
		makeLabel(panel, "SkillName" .. i, UDim2.new(1, -150, 0, 22),
			UDim2.new(0, 10, 0, y),
			def.name .. "   Lv " .. lv .. "/5  " .. pips, 15,
			Color3.fromRGB(255, 255, 255))
		local meta
		if def.toggle then
			meta = "Toggle aura - no cost, no cooldown - Hotkey " .. HOTKEYS[i]
		elseif classId == "Warrior" then
			meta = "CD " .. def.cd .. "s   Rage " .. (def.rage or 0)
				.. "   Hotkey " .. HOTKEYS[i]
		else
			meta = "CD " .. def.cd .. "s   Mana " .. def.mana
				.. "   Hotkey " .. HOTKEYS[i]
		end
		-- v7 D2: synergy line -- sibling levels passively boost
		-- this skill by +4% per level
		local synSrc = V7.SYNERGY[classId] and V7.SYNERGY[classId][i]
		if synSrc then
			meta = meta .. "   Synergy: +"
				.. (4 * getSkillLevel(player, classId, synSrc))
				.. "% from " .. SKILLS[classId][synSrc].name
		end
		makeLabel(panel, "SkillMeta" .. i, UDim2.new(1, -150, 0, 18),
			UDim2.new(0, 10, 0, y + 20), meta, 12,
			Color3.fromRGB(160, 175, 200))
		-- v8: CURRENT and NEXT effects on their own lines, so
		-- spending a point is an informed choice (v7 buried the
		-- current effect inside one wrapped paragraph). def.desc
		-- returns "current\nNext: ..." for lv >= 1, so the first
		-- line of desc(lv) is the current effect and the first
		-- line of desc(lv + 1) is the next level's effect.
		local function firstLine(text)
			return (string.split(text, "\n")[1]) or text
		end
		local curText = lv >= 1 and firstLine(def.desc(lv)) or "Not learned yet"
		local nextText = lv < 5 and firstLine(def.desc(lv + 1)) or "MAX LEVEL"
		makeLabel(panel, "SkillNow" .. i, UDim2.new(1, -150, 0, 18),
			UDim2.new(0, 10, 0, y + 38), "Now:  " .. curText, 12,
			Color3.fromRGB(200, 205, 215))
		makeLabel(panel, "SkillNext" .. i, UDim2.new(1, -150, 0, 18),
			UDim2.new(0, 10, 0, y + 56), "Next: " .. nextText, 12,
			Color3.fromRGB(140, 220, 150))
		local canUp = points > 0 and lv < 5
		local up = Instance.new("TextButton")
		up.Name = "SkillUp" .. i
		up.Size = UDim2.new(0, 64, 0, 56)
		up.Position = UDim2.new(1, -76, 0, y + 10)
		up.Text = "[ + ]"
		up.Font = Enum.Font.GothamBold
		up.TextSize = 18
		up.TextColor3 = Color3.fromRGB(255, 255, 255)
		up.BackgroundColor3 = canUp and Color3.fromRGB(60, 130, 60)
			or Color3.fromRGB(45, 45, 58)
		up.BorderSizePixel = 0
		up:SetAttribute("Act", "SkillUp")
		up:SetAttribute("Arg", tostring(i))
		up.Parent = panel
	end
	-- v7: the Hint line carries the class resource + passive text
	local hint = makeLabel(panel, "Hint", UDim2.new(1, -20, 0, 30), UDim2.new(0, 10, 0, 366),
		(V7.CLASS_PASSIVE[classId] or "") .. " Cast with Q / E / R or the skill bar.", 11,
		Color3.fromRGB(150, 150, 165))
	hint.TextWrapped = true
	hint.TextYAlignment = Enum.TextYAlignment.Top
end

local function refreshClassUI(player)
	local refs = classRefs[player]
	if not refs then return end
	refs.panel.Visible = classPanelOpen[player] and true or false
	local classId = getClassId(player)
	for cid, b in pairs(refs.classButtons) do
		if cid == classId then
			b.BackgroundColor3 = Color3.fromRGB(62, 105, 55)
		else
			b.BackgroundColor3 = Color3.fromRGB(38, 38, 54)
		end
	end
	refreshSkillsUI(player)
	updateSkillBar(player)
end

--====================================================================
-- CLASS ACTIONS
--====================================================================
-- v7 SKILL FIX (root cause): in v6 a fresh player had SkillPoints
-- = 0 and every skill at Lv0 -- points only ever came from
-- level-ups -- so pressing Q/E/R on a new character ALWAYS failed
-- with "not learned" and skills looked broken. Now the FIRST time
-- a class is chosen it grants 1 skill point AND auto-learns that
-- class's Skill 1: every class can cast something immediately.
local function grantClassStarter(player, classId)
	local st = skillState[player]
	if not st then return end
	st.freeGranted = st.freeGranted or {}
	if st.freeGranted[classId] then return end
	st.freeGranted[classId] = true
	if st.skills[classId][1] < 1 then
		st.skills[classId][1] = 1
	end
	local sp = getStat(player, "Stats", "SkillPoints")
	if sp then sp.Value = sp.Value + 1 end
	showToast(player, "Learned " .. SKILLS[classId][1].name .. "! +1 Skill Point", 3.5)
end

local function chooseClass(player, classId)
	if not CLASS_DEFS[classId] then return end
	local classVal = getStat(player, "Stats", "Class")
	if not classVal then return end
	classVal.Value = classId
	grantClassStarter(player, classId) -- v7: first pick of a class
	-- swap to the class's tool loadout (level + gear untouched)
	removeAllTools(player)
	giveClassTools(player)
	-- the new class may have a smaller mana pool: clamp
	local mana = getStat(player, "Stats", "Mana")
	if mana then mana.Value = math.min(mana.Value, maxManaFor(player)) end
	-- re-apply HP cap / walk speed / worn gear under the new mods
	applyGear(player)
	refreshThornsAura(player) -- aura ring only exists for Paladins
	classPanelOpen[player] = false
	refreshClassUI(player)
	playSfx("Equip", getHRP(player.Character))
	local def = CLASS_DEFS[classId]
	showToast(player, "Class: " .. def.name .. " (" .. def.cn .. ")", 3)
end

local function skillUp(player, idx)
	local classId = getClassId(player)
	if classId == "" then
		showToast(player, "Choose a class first!", 2)
		return
	end
	if idx < 1 or idx > 3 then return end
	local st = skillState[player]
	if not st then return end
	if st.skills[classId][idx] >= 5 then
		showToast(player, "Skill is already max level!", 2)
		return
	end
	local sp = getStat(player, "Stats", "SkillPoints")
	if not sp or sp.Value < 1 then
		showToast(player, "No skill points! Level up to earn more.", 2)
		return
	end
	st.skills[classId][idx] = st.skills[classId][idx] + 1
	sp.Value = sp.Value - 1
	playSfx("LevelUp", getHRP(player.Character))
	showToast(player, SKILLS[classId][idx].name .. " -> Lv "
		.. st.skills[classId][idx], 2)
	refreshClassUI(player)
end

local function castSkill(player, idx)
	local classId = getClassId(player)
	if classId == "" then
		showToast(player, "Choose a class first!", 2)
		return
	end
	local defs = SKILLS[classId]
	local def = defs and defs[idx]
	if not def then return end
	local st = skillState[player]
	if not st then return end
	local lv = getSkillLevel(player, classId, idx)
	-- Thorns Aura: a toggle, no mana / cooldown, still needs Lv >= 1
	if def.toggle then
		if lv < 1 then
			showToast(player, "Learn " .. def.name .. " first!", 2)
			return
		end
		st.thornsOn = not st.thornsOn
		refreshThornsAura(player)
		updateSkillBar(player)
		showToast(player, def.name .. (st.thornsOn and " ON" or " OFF"), 1.5)
		playSfx("Equip", getHRP(player.Character))
		return
	end
	if lv < 1 then
		showToast(player, "Skill not learned - open Skills to learn " .. def.name .. "!", 2.5)
		return
	end
	local now = os.clock()
	local cdKey = classId .. idx
	-- v7: Skill Haste (gear affix) shortens cooldowns; and a cast
	-- rejected by cooldown now SAYS so (v6 returned silently,
	-- which made skills feel broken)
	local cs = combatStats[player]
	local cdLen = def.cd * (1 - (cs and cs.haste or 0))
	if st.cooldowns[cdKey] and now < st.cooldowns[cdKey] then
		if now - (st.cdToastAt or 0) > 1 then
			st.cdToastAt = now
			showToast(player, def.name .. " cooldown: "
				.. math.ceil(st.cooldowns[cdKey] - now) .. "s", 1.2)
		end
		return
	end
	-- target-required skills validate BEFORE resources are spent
	local target = nil
	if def.needsTarget then
		target = nearestEnemy(player, def.needsTarget)
		if not target then
			showToast(player, "No target in range!", 2)
			return
		end
	end
	-- v7: Warriors pay RAGE, everyone else pays mana
	if classId == "Warrior" then
		local rage = getStat(player, "Stats", "Rage")
		local cost = def.rage or 0
		if not rage or rage.Value < cost then
			showToast(player, "Not enough rage! Land sword hits to build rage.", 2)
			return
		end
		rage.Value = rage.Value - cost
	else
		local mana = getStat(player, "Stats", "Mana")
		if not mana or mana.Value < def.mana then
			showToast(player, "Not enough mana!", 2)
			return
		end
		mana.Value = mana.Value - def.mana
	end
	st.cooldowns[cdKey] = now + cdLen
	def.cast(player, lv, target)
	updateSkillBar(player)
end

--====================================================================
-- v8 CHARGE ATTACKS (Shining Soul's signature mechanic) +
-- PATHFINDING fallback for dungeon enemies
--====================================================================
-- Input arrives from UIClient as UIEvent ("Charge", "Begin" /
-- "Release") while a weapon tool is equipped. The normal
-- Tool.Activated swing still fires on the initial press (the
-- wind-up, exactly like holding A in Shining Soul); holding
-- builds charge tiers (T1 at 0.7s, T2 at 1.5s) and releasing
-- unleashes the class charged attack through V7.hitEnemy, so
-- affixes / crit / elements all apply. While charging: WalkSpeed
-- x0.7, a growing Neon aura sphere at the feet (white-blue ->
-- gold -> orange-red, pulsing at T2) and the HUD charge bar
-- fills. A single hit costing more than 15% of MaxHP interrupts
-- the charge (AI.damagePlayer calls V8.cancelCharge). Release
-- cooldown: 1.2s.

V8.T1 = 0.7  -- charge tier 1 threshold (seconds held)
V8.T2 = 1.5  -- charge tier 2 (max) threshold
V8.CD = 1.2  -- release cooldown

V8.tierOf = function(st)
	local held = os.clock() - st.started
	if held >= V8.T2 then return 2 end
	if held >= V8.T1 then return 1 end
	return 0
end

V8.cleanupCharge = function(player)
	local st = V8.charge[player]
	if not st then return end
	V8.charge[player] = nil
	if st.aura and st.aura.Parent then st.aura:Destroy() end
	local hum = getHumanoid(player.Character)
	if hum and st.baseSpeed then
		hum.WalkSpeed = st.baseSpeed
	end
	local gui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("ShiningHUD")
	local bar = gui and gui:FindFirstChild("ChargeBar")
	if bar then bar.Visible = false end
end

function V8.cancelCharge(player, interrupted)
	if not V8.charge[player] then return end
	V8.cleanupCharge(player)
	if interrupted then
		showToast(player, "Charge interrupted!", 1.5)
	end
end

V8.equippedWeapon = function(player)
	local character = player.Character
	if not character then return nil end
	local tool = character:FindFirstChildOfClass("Tool")
	if tool and isLoadoutTool(tool) then return tool end
	return nil
end

function V8.chargeBegin(player)
	if V8.charge[player] then return end
	local character = player.Character
	local hum = getHumanoid(character)
	local hrp = getHRP(character)
	if not hum or not hrp or hum.Health <= 0 then return end
	if not V8.equippedWeapon(player) then return end
	-- aura: Neon sphere welded at the character's feet; the
	-- charge loop grows it and shifts its color per tier
	local aura = Instance.new("Part")
	aura.Name = "ChargeAura"
	aura.Shape = Enum.PartType.Ball
	aura.Size = Vector3.new(2.2, 2.2, 2.2)
	aura.Color = Color3.fromRGB(170, 220, 255)
	aura.Material = Enum.Material.Neon
	aura.Transparency = 0.45
	aura.CanCollide = false
	aura.CFrame = hrp.CFrame * CFrame.new(0, -2.4, 0)
	aura.Parent = character
	weldTo(aura, hrp)
	V8.charge[player] = {
		started = os.clock(),
		aura = aura,
		baseSpeed = hum.WalkSpeed,
	}
	hum.WalkSpeed = hum.WalkSpeed * 0.7
	local gui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("ShiningHUD")
	local bar = gui and gui:FindFirstChild("ChargeBar")
	if bar then
		bar.Visible = true
		local fill = bar:FindFirstChild("Fill")
		if fill then fill.Size = UDim2.fromScale(0, 1) end
	end
end

-- WARRIOR charged attack: a wide sword-wave shockwave that
-- travels forward 40 studs, hitting every enemy it passes
-- through (once each) for x2.2 (T1) / x3.2 (T2) weapon damage
V8.chargeWave = function(player, tier)
	local character = player.Character
	local hrp = getHRP(character)
	if not hrp then return end
	local dir = hrp.CFrame.LookVector
	local dmg = playerWeaponDamage(player) * classDamageMul(player, "melee")
		* (tier == 1 and 2.2 or 3.2)
	local wave = Instance.new("Part")
	wave.Name = "ChargeWave"
	wave.Size = Vector3.new(7, 3.4, 1)
	wave.Color = tier == 2 and Color3.fromRGB(255, 120, 50) or Color3.fromRGB(255, 205, 90)
	wave.Material = Enum.Material.Neon
	wave.Transparency = 0.2
	wave.CanCollide = false
	wave.Anchored = true
	wave.CFrame = CFrame.lookAt(hrp.Position + dir * 3 + Vector3.new(0, 0.5, 0),
		hrp.Position + dir * 13 + Vector3.new(0, 0.5, 0))
	wave.Parent = Workspace
	playSfx("Swing", hrp, true)
	local hitFn = V7.hitEnemy or damageEnemy
	local hitSet = {}
	task.spawn(function()
		local traveled = 0
		while wave.Parent and traveled < 40 do
			local step = 55 * 0.03
			traveled = traveled + step
			wave.CFrame = wave.CFrame + dir * step
			for model, _ in pairs(enemies) do
				if not hitSet[model] then
					local eroot = model:FindFirstChild("HumanoidRootPart")
					if eroot and horizontalDistance(wave.Position, eroot.Position) <= 4.6
						and math.abs(eroot.Position.Y - wave.Position.Y) < 7 then
						hitSet[model] = true
						hitFn(model, dmg, player, dir, { source = "Charge", big = tier == 2 })
					end
				end
			end
			task.wait(0.03)
		end
		if wave.Parent then wave:Destroy() end
	end)
end

-- PALADIN charged attack: holy ground slam around self,
-- r8 (T1) / r11 (T2), x2 / x3 weapon damage with knockback
V8.chargeSlam = function(player, tier)
	local hrp = getHRP(player.Character)
	if not hrp then return end
	local radius = tier == 1 and 8 or 11
	local dmg = playerWeaponDamage(player) * classDamageMul(player, "melee")
		* (tier == 1 and 2 or 3)
	local pos = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
	ringFX(pos, radius, Color3.fromRGB(255, 205, 90), 0.4)
	local disc = Instance.new("Part")
	disc.Name = "ChargeSlamDisc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.3, radius * 2, radius * 2)
	disc.CFrame = CFrame.new(hrp.Position.X, 0.4, hrp.Position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	disc.Color = Color3.fromRGB(255, 215, 110)
	disc.Material = Enum.Material.Neon
	disc.Transparency = 0.35
	disc.Anchored = true
	disc.CanCollide = false
	disc.Parent = Workspace
	Debris:AddItem(disc, 0.35)
	local hitFn = V7.hitEnemy or damageEnemy
	for _, model in ipairs(enemiesWithin(hrp.Position, radius)) do
		local eroot = model:FindFirstChild("HumanoidRootPart")
		local away = eroot and AI.flatDir(hrp.Position, eroot.Position) or nil
		hitFn(model, dmg, player, away, { source = "Charge", big = tier == 2 })
	end
	playSfx("Hit", hrp, true)
end

-- MAGE charged attack: one giant slow homing orb that explodes
-- for x2.4 (T1) / x3.6 (T2) fire spell damage in r7 / r10
V8.chargeOrb = function(player, tier)
	local character = player.Character
	local hrp = getHRP(character)
	if not hrp then return end
	local radius = tier == 1 and 7 or 10
	local dmg = playerSpellDamage(player) * classDamageMul(player, "spell")
		* (tier == 1 and 2.4 or 3.6)
	-- lock the nearest enemy within 80 (the staff's targeting)
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
	local size = tier == 1 and 3 or 4.2
	local orb = Instance.new("Part")
	orb.Name = "ChargeOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(size, size, size)
	orb.Color = Color3.fromRGB(255, 120, 215)
	orb.Material = Enum.Material.Neon
	orb.CanCollide = false
	orb.Position = hrp.Position + hrp.CFrame.LookVector * 4 + Vector3.new(0, 1.5, 0)
	orb.Parent = Workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 60)
	light.Range = 16
	light.Brightness = 2.5
	light.Parent = orb
	local aimDir = hrp.CFrame.LookVector
	if target then
		local eroot = target:FindFirstChild("HumanoidRootPart")
		if eroot then
			local toT = (eroot.Position + Vector3.new(0, 1.5, 0)) - orb.Position
			if toT.Magnitude > 0.1 then aimDir = toT.Unit end
		end
	end
	orb.AssemblyLinearVelocity = aimDir * 45
	playSfx("Swing", hrp, true)
	local hitFn = V7.hitEnemy or damageEnemy
	local exploded = false
	local function explode()
		if exploded then return end
		exploded = true
		local pos = orb.Position
		ringFX(Vector3.new(pos.X, 0, pos.Z), radius, Color3.fromRGB(255, 140, 50), 0.4)
		burstFX(pos, Color3.fromRGB(255, 140, 50), 10)
		for _, model in ipairs(enemiesWithin(pos, radius)) do
			hitFn(model, dmg, player, nil,
				{ source = "Charge", element = "Fire", big = tier == 2 })
		end
		if orb.Parent then orb:Destroy() end
	end
	if target then
		task.spawn(function()
			local started = os.clock()
			while orb.Parent and not exploded and os.clock() - started < 2.2 do
				if not enemies[target] then break end
				local eroot = target:FindFirstChild("HumanoidRootPart")
				if not eroot then break end
				local toT = (eroot.Position + Vector3.new(0, 1.5, 0)) - orb.Position
				if toT.Magnitude > 0.1 then
					orb.AssemblyLinearVelocity = toT.Unit * 45
				end
				task.wait(0.03)
			end
		end)
	end
	orb.Touched:Connect(function(hit)
		if exploded then return end
		if hit and character and hit:IsDescendantOf(character) then return end
		local model = hit and hit.Parent
		if model and model.Parent == enemiesFolder and enemies[model] then
			explode()
		elseif hit and hit.Anchored then
			explode()
		end
	end)
	task.delay(2.2, explode)
end

-- ARCHER charged attack: an instant piercing mega-arrow --
-- a 60-stud line, 4 wide, hitting EVERY enemy along it for
-- x2.2 (T1) / x3.4 (T2) ranged damage, with a fat tracer
V8.chargeArrow = function(player, tier)
	local hrp = getHRP(player.Character)
	if not hrp then return end
	local origin = hrp.Position + Vector3.new(0, 1.6, 0)
	local dir = hrp.CFrame.LookVector
	local target = nearestEnemy(player, 70)
	local eroot = target and target:FindFirstChild("HumanoidRootPart")
	if eroot then
		local flat = Vector3.new(eroot.Position.X - origin.X, 0,
			eroot.Position.Z - origin.Z)
		if flat.Magnitude > 0.1 then dir = flat.Unit end
	end
	local dmg = playerRangedDamage(player) * classDamageMul(player, "ranged")
		* (tier == 1 and 2.2 or 3.4)
	local hitFn = V7.hitEnemy or damageEnemy
	local LENGTH = 60
	for model, _ in pairs(enemies) do
		local er = model:FindFirstChild("HumanoidRootPart")
		if er then
			local rel = Vector3.new(er.Position.X - origin.X, 0,
				er.Position.Z - origin.Z)
			local along = rel:Dot(dir)
			if along > 0 and along < LENGTH then
				local closest = origin + dir * along
				if horizontalDistance(er.Position, closest) <= 4 then
					hitFn(model, dmg, player, dir, { source = "Charge", big = tier == 2 })
				end
			end
		end
	end
	local tracer = Instance.new("Part")
	tracer.Name = "ChargeTracer"
	tracer.Size = Vector3.new(0.55, 0.55, LENGTH)
	tracer.Color = Color3.fromRGB(255, 215, 110)
	tracer.Material = Enum.Material.Neon
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CFrame = CFrame.lookAt(origin + dir * (LENGTH / 2), origin + dir * LENGTH)
	tracer.Parent = Workspace
	Debris:AddItem(tracer, 0.3)
	playSfx("Swing", hrp, true)
end

function V8.chargeRelease(player)
	local st = V8.charge[player]
	if not st then return end
	local tier = V8.tierOf(st)
	V8.cleanupCharge(player)
	if tier < 1 then return end
	local rec = lastAction[player]
	local now = os.clock()
	if rec and (now - (rec.charge or 0)) < V8.CD then return end
	if rec then rec.charge = now end
	local classId = getClassId(player)
	if classId == "Paladin" then
		V8.chargeSlam(player, tier)
	elseif classId == "Mage" then
		V8.chargeOrb(player, tier)
	elseif classId == "Archer" then
		V8.chargeArrow(player, tier)
	else
		-- Warrior (and the classless starter kit): sword wave
		V8.chargeWave(player, tier)
	end
end

-- 0.1s loop while anyone is charging: grow / recolor the aura,
-- fill the HUD charge bar, and quietly cancel charges whose
-- owner died, respawned or swapped away from a weapon tool.
function V8.chargeLoop()
	while true do
		task.wait(0.1)
		for player, st in pairs(V8.charge) do
			local hum = getHumanoid(player.Character)
			local hrp = getHRP(player.Character)
			if not hum or not hrp or hum.Health <= 0 or not V8.equippedWeapon(player) then
				V8.cleanupCharge(player)
			else
				local held = os.clock() - st.started
				local tier = held >= V8.T2 and 2 or held >= V8.T1 and 1 or 0
				if st.aura and st.aura.Parent then
					local grow = tier == 2 and 4.6 or tier == 1 and 3.4 or 2.2 + held * 1.2
					if tier == 2 then
						grow = grow + math.sin(os.clock() * 18) * 0.35 -- T2 pulse
					end
					st.aura.Size = Vector3.new(grow, grow, grow)
					st.aura.Color = tier == 2 and Color3.fromRGB(255, 110, 45)
						or tier == 1 and Color3.fromRGB(255, 200, 70)
						or Color3.fromRGB(170, 220, 255)
				end
				local gui = player.PlayerGui and player.PlayerGui:FindFirstChild("ShiningHUD")
				local bar = gui and gui:FindFirstChild("ChargeBar")
				if bar then
					bar.Visible = true
					local fill = bar:FindFirstChild("Fill")
					if fill then
						fill.Size = UDim2.fromScale(math.min(held / V8.T2, 1), 1)
						fill.BackgroundColor3 = tier == 2 and Color3.fromRGB(255, 110, 45)
							or tier == 1 and Color3.fromRGB(255, 200, 70)
							or Color3.fromRGB(140, 200, 255)
					end
					local text = bar:FindFirstChild("Text")
					if text then
						text.Text = tier == 2 and "CHARGE MAX!"
							or tier == 1 and "CHARGE Lv1" or "CHARGE"
					end
				end
			end
		end
	end
end

--====================================================================
-- v8 PATHFINDING fallback: dungeon rooms have real walls, so a
-- dungeon enemy whose behavior MoveTo is wedged on a wall asks
-- PathfindingService for a route and follows its waypoints for
-- up to 3s. Called from aiLoop AFTER the behavior ran, so the
-- waypoint MoveTo overrides the behavior's straight-line one;
-- attacks, leaps and dashes are untouched.
--====================================================================
function V8.pathMove(model, data, root, humanoid, target, dist, now)
	local ai = data.ai
	-- displacement tracking between AI ticks (0.25s each)
	if ai.lastPos then
		local moved = horizontalDistance(root.Position, ai.lastPos)
		if moved < 0.75 and dist > 6 and (ai.slowFactor or 1) > 0 then
			ai.stuckFor = (ai.stuckFor or 0) + 0.25
		else
			ai.stuckFor = 0
		end
	end
	ai.lastPos = root.Position
	-- follow the active path, if any
	if ai.waypoints and now < (ai.pathUntil or 0) then
		local wp = ai.waypoints[ai.wpIndex or 1]
		if wp and horizontalDistance(root.Position, wp) < 3.5 then
			ai.wpIndex = (ai.wpIndex or 1) + 1
			wp = ai.waypoints[ai.wpIndex]
		end
		if wp then
			humanoid:MoveTo(wp)
			return
		end
		ai.waypoints = nil
	end
	-- stuck long enough: compute a fresh path (throttled to one
	-- compute per 1.5s per enemy, async so the AI loop never hitches)
	if (ai.stuckFor or 0) >= 1.2 and now >= (ai.pathNext or 0) then
		ai.stuckFor = 0
		ai.pathNext = now + 1.5
		local phrp = getHRP(target.Character)
		if not phrp then return end
		local dest = phrp.Position
		task.spawn(function()
			local path = nil
			local ok = pcall(function()
				path = PathfindingService:CreatePath({
					AgentRadius = 2, AgentHeight = 4, AgentCanJump = false,
				})
				path:ComputeAsync(root.Position, dest)
			end)
			if not ok or not path then return end
			if path.Status ~= Enum.PathStatus.Success then return end
			if not enemies[model] then return end
			local list = {}
			for i, w in ipairs(path:GetWaypoints()) do
				if i > 1 then table.insert(list, w.Position) end
			end
			if #list > 0 then
				ai.waypoints = list
				ai.wpIndex = 1
				ai.pathUntil = os.clock() + 3
			end
		end)
	end
end
uiEvent.OnServerEvent:Connect(function(player, act, arg)
	if type(act) ~= "string" then return end
	if act == "ToggleClass" then
		classPanelOpen[player] = not classPanelOpen[player]
		if classPanelOpen[player] then skillsOpen[player] = false end
		refreshClassUI(player)
	elseif act == "ChooseClass" then
		if type(arg) == "string" then chooseClass(player, arg) end
	elseif act == "ToggleSkills" then
		skillsOpen[player] = not skillsOpen[player]
		if skillsOpen[player] then classPanelOpen[player] = false end
		refreshClassUI(player)
	elseif act == "SkillUp" then
		local idx = tonumber(arg)
		if idx then skillUp(player, math.floor(idx)) end
	elseif act == "CastSkill" then
		local idx = tonumber(arg)
		if idx then castSkill(player, math.floor(idx)) end
	elseif act == "Charge" then
		-- v8: charge attacks (UIClient hold / release forwarding)
		if arg == "Begin" then
			V8.chargeBegin(player)
		elseif arg == "Release" then
			V8.chargeRelease(player)
		end
	end
end)

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
			-- restyle the sword (an equipped weapon's rarity style wins)
			restylePlayerSword(player)
			announce(player.Name .. " upgraded sword to Tier " .. tier.Value .. "!", 3)
		else
			announce("Need " .. price .. " gold to upgrade!", 2)
		end
	end)
end
setupShop()

-- v6: Class Mentor prompt. ProximityPrompts fire server-side, so
-- this needs NO UIClient change: it re-opens the class panel with
-- exactly the same state changes as the Class button.
local function setupMentor()
	if not mentorStandPart then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Change Class"
	prompt.ObjectText = "Class Mentor"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.Parent = mentorStandPart
	prompt.Triggered:Connect(function(player)
		classPanelOpen[player] = true
		skillsOpen[player] = false
		refreshClassUI(player)
	end)
end
setupMentor()

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
		sendMusic(player) -- zone changed: Auto music follows
	end)
end
-- v7: the gate arch no longer teleports on touch -- it offers a
-- difficulty CHOICE via two prompts (D2-style): E = Normal,
-- F = Nightmare. Nightmare is locked until a boss wave has been
-- cleared this session; picking it then sets the dungeon-wide
-- difficulty that startWave applies at spawn time (HP x2.2,
-- damage x1.5, XP/gold x1.8, better drops + set chances).
local function setupDungeonGate()
	if not portalToDungeon then return end
	local function enterDungeon(player, difficulty)
		if difficulty == "Nightmare" and not V7.nightmareUnlocked then
			showToast(player,
				"Nightmare is locked - clear a Wave 5 boss on Normal first!", 3)
			return
		end
		V7.difficulty = difficulty
		local character = player.Character
		local hrp = getHRP(character)
		if not hrp then return end
		hrp.CFrame = CFrame.new(DUNGEON_ENTRANCE + Vector3.new(0, 0, -12))
		hrp.AssemblyLinearVelocity = Vector3.zero
		sendMusic(player)
		showToast(player, difficulty == "Nightmare"
			and "NIGHTMARE dungeon! Stronger monsters, richer loot."
			or "Entered the dungeon (Normal).", 3)
	end
	local normalPrompt = Instance.new("ProximityPrompt")
	normalPrompt.ActionText = "Enter Dungeon (Normal)"
	normalPrompt.ObjectText = "Dungeon Gate"
	normalPrompt.HoldDuration = 0
	normalPrompt.MaxActivationDistance = 12
	normalPrompt.KeyboardKeyCode = Enum.KeyCode.E
	normalPrompt.Parent = portalToDungeon
	normalPrompt.Triggered:Connect(function(player)
		enterDungeon(player, "Normal")
	end)
	local nightmarePrompt = Instance.new("ProximityPrompt")
	nightmarePrompt.ActionText = "Enter Dungeon (NIGHTMARE)"
	nightmarePrompt.ObjectText = "Dungeon Gate"
	nightmarePrompt.HoldDuration = 0
	nightmarePrompt.MaxActivationDistance = 12
	nightmarePrompt.KeyboardKeyCode = Enum.KeyCode.F
	nightmarePrompt.Parent = portalToDungeon
	nightmarePrompt.Triggered:Connect(function(player)
		enterDungeon(player, "Nightmare")
	end)
end
setupDungeonGate()
-- v6: the dungeon return portal lands back at the field-side gate
-- arch (travel loop: town -> field -> dungeon -> field)
setupPortal(portalToTown, Vector3.new(0, 3, -74))

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
	-- v5: the loadout follows the chosen class. With a class set,
	-- tools outside the loadout are removed (class swaps stay
	-- clean); without a class the v4 trio (sword/staff/potion) is
	-- kept so new players can fight before choosing.
	local desired = classLoadout(player)
	local function isDesired(toolName)
		for _, prefix in ipairs(desired) do
			if string.find(toolName, prefix, 1, true) then return true end
		end
		return false
	end
	if getClassId(player) ~= "" then
		for _, container in ipairs({ backpack, character }) do
			if container then
				for _, item in ipairs(container:GetChildren()) do
					if item:IsA("Tool") and not isDesired(item.Name) then
						item:Destroy()
					end
				end
			end
		end
	end
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
	for _, prefix in ipairs(desired) do
		if not hasTool(prefix) then
			local tool = createToolByPrefix(player, prefix)
			if tool then tool.Parent = backpack end
		end
	end
	restylePlayerSword(player)
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.MaxHealth = maxHealthFor(player)
		humanoid.Health = humanoid.MaxHealth
	end
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if hrp then
		task.wait(0.2)
		hrp.CFrame = townSpawnCFrame
	end
	ensureTools(player)
	-- re-apply gear on the fresh character: HP cap, walk speed,
	-- worn visuals and the sword's rarity styling
	applyGear(player)
	-- v8: chibi proportions on every (re)spawn
	V8.applyChibi(character)
	-- v5: restore the Thorns Aura ring on the new character
	refreshThornsAura(player)
	sendMusic(player)
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
	-- equipment: plain serializable copies (ids are re-issued on load)
	local state = gearState[player]
	if state then
		local function copyItem(item)
			if not item then return nil end
			-- v7: affixes (id + rolled value), set id and the
			-- Legendary unique all persist -- an item rebuilds
			-- with IDENTICAL stats on load
			local affs = {}
			for _, af in ipairs(item.affixes or {}) do
				table.insert(affs, { id = af.id, value = af.value })
			end
			return {
				slot = item.slot, rarity = item.rarity,
				name = item.name, stat = item.stat,
				affixes = affs, set = item.set, unique = item.unique,
			}
		end
		local gearData = { inv = {}, equipped = {} }
		for _, item in ipairs(state.inv) do
			table.insert(gearData.inv, copyItem(item))
		end
		for slot, item in pairs(state.equipped) do
			gearData.equipped[slot] = copyItem(item)
		end
		data.Gear = gearData
	end
	-- v5: class id, skill points, per-class skill levels, thorns toggle
	local classVal = getStat(player, "Stats", "Class")
	if classVal then data.Class = classVal.Value end
	local spVal = getStat(player, "Stats", "SkillPoints")
	if spVal then data.SkillPoints = spVal.Value end
	local sState = skillState[player]
	if sState then
		local skillsData = {}
		for _, cid in ipairs(CLASS_IDS) do
			local arr = sState.skills[cid]
			skillsData[cid] = { arr[1], arr[2], arr[3] }
		end
		data.Skills = skillsData
		data.ThornsOn = sState.thornsOn
		data.FreeGranted = sState.freeGranted -- v7 starter grants
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
	-- equipment restore (validated against the slot/rarity tables)
	local state = gearState[player]
	if state and type(data.Gear) == "table" then
		local function revive(raw)
			if type(raw) ~= "table" then return nil end
			if not STAT_BANDS[raw.slot] or not RARITIES[raw.rarity] then return nil end
			if type(raw.name) ~= "string" or type(raw.stat) ~= "number" then return nil end
			local band = STAT_BANDS[raw.slot][raw.rarity]
			-- v7: rebuild affixes -- ids validated against the
			-- affix table, values clamped to the rarity band
			-- (x1.5 headroom for top ilvl-tier rolls)
			local affs = {}
			if type(raw.affixes) == "table" then
				for _, raf in ipairs(raw.affixes) do
					if type(raf) == "table" and GEAR7.AFFIX[raf.id]
						and type(raf.value) == "number" then
						local ab = GEAR7.AFFIX[raf.id].bands[raw.rarity]
						table.insert(affs, {
							id = raf.id,
							value = math.clamp(math.floor(raf.value), 1,
								math.ceil(ab[2] * 1.5)),
						})
					end
				end
			end
			gearIdCounter = gearIdCounter + 1
			return {
				id = "g" .. gearIdCounter,
				slot = raw.slot,
				rarity = raw.rarity,
				name = string.sub(raw.name, 1, 60),
				stat = math.clamp(math.floor(raw.stat), 1, band[2] * 2),
				affixes = affs,
				set = (type(raw.set) == "string" and GEAR7.SETS[raw.set]) and raw.set or nil,
				unique = (type(raw.unique) == "string" and GEAR7.UNIQUE[raw.unique]) and raw.unique or nil,
			}
		end
		if type(data.Gear.inv) == "table" then
			for _, raw in ipairs(data.Gear.inv) do
				local item = revive(raw)
				if item and #state.inv < MAX_INVENTORY then
					table.insert(state.inv, item)
				end
			end
		end
		if type(data.Gear.equipped) == "table" then
			for _, slot in ipairs(GEAR_SLOTS) do
				local item = revive(data.Gear.equipped[slot])
				if item and item.slot == slot then
					state.equipped[slot] = item
				end
			end
		end
	end
	-- v5: class + skill points + per-class skill levels (validated)
	if type(data.Class) == "string" and CLASS_DEFS[data.Class] then
		local classVal = getStat(player, "Stats", "Class")
		if classVal then classVal.Value = data.Class end
	end
	apply("Stats", "SkillPoints", data.SkillPoints, 0, 999)
	local sState = skillState[player]
	if sState and type(data.Skills) == "table" then
		for _, cid in ipairs(CLASS_IDS) do
			local arr = data.Skills[cid]
			if type(arr) == "table" then
				for i = 1, 3 do
					if type(arr[i]) == "number" then
						sState.skills[cid][i] =
							math.clamp(math.floor(arr[i]), 0, 5)
					end
				end
			end
		end
	end
	if sState and type(data.ThornsOn) == "boolean" then
		sState.thornsOn = data.ThornsOn
	end
	-- v7: which classes already received their starter grant
	if sState and type(data.FreeGranted) == "table" then
		sState.freeGranted = sState.freeGranted or {}
		for _, cid in ipairs(CLASS_IDS) do
			if data.FreeGranted[cid] == true then
				sState.freeGranted[cid] = true
			end
		end
	end
end

local function onPlayerAdded(player)
	lastAction[player] = { sword = 0, fire = 0, potion = 0, teleport = 0 }
	gearState[player] = { inv = {}, equipped = {} }
	playerFx[player] = {} -- v7: holy stacks, shields, proc cooldowns
	bagOpen[player] = false
	musicMode[player] = "Auto"
	-- v5 class state (loadPlayer fills skills from the save below)
	skillState[player] = newSkillState()
	buffs[player] = nil
	classPanelOpen[player] = false
	skillsOpen[player] = false

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
	makeInt(stats, "GearATK", 0)
	makeInt(stats, "GearDEF", 0)
	makeInt(stats, "SkillPoints", 0) -- v5: 1 per level-up
	makeInt(stats, "Rage", 0) -- v7: Warrior resource, 0-100 (session-only)
	local classValue = Instance.new("StringValue") -- v5: "" = no class
	classValue.Name = "Class"
	classValue.Value = ""
	classValue.Parent = stats
	stats.Parent = player

	-- Load saved progress BEFORE the character setup below reads Level
	loadPlayer(player)

	buildHUD(player)
	buildBagUI(player)
	-- v5: class select + skills UI; the select panel opens on join
	-- for players who have not chosen a class yet
	buildClassUI(player)
	classPanelOpen[player] = (getClassId(player) == "")
	refreshClassUI(player)

	-- v7 migration: a v6 save can hold a class with ALL skills at
	-- Lv0 and 0 skill points -- the exact "skills are broken"
	-- state. Grant the starter package once so they can cast.
	do
		local cid = getClassId(player)
		local st = skillState[player]
		local sp = getStat(player, "Stats", "SkillPoints")
		if cid ~= "" and st and not (st.freeGranted and st.freeGranted[cid])
			and getSkillLevel(player, cid, 1) == 0
			and getSkillLevel(player, cid, 2) == 0
			and getSkillLevel(player, cid, 3) == 0
			and (not sp or sp.Value == 0) then
			grantClassStarter(player, cid)
			refreshClassUI(player)
		end
	end

	local backpack = player:WaitForChild("Backpack")
	if getClassId(player) ~= "" then
		-- returning player with a class: hand out that class's loadout
		giveClassTools(player)
	else
		local startSword = createSword(player)
		startSword.Parent = backpack
		createFireballTool(player).Parent = backpack
		createPotionTool(player).Parent = backpack
	end
	-- restored gear (if any) takes effect: bonuses, sword styling,
	-- worn visuals (character may spawn a moment later; CharacterAdded
	-- re-applies everything then)
	applyGear(player)
	sendMusic(player, true)

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
	gearState[player] = nil
	combatStats[player] = nil -- v7
	playerFx[player] = nil -- v7
	gearUi.inspect[player] = nil -- v7
	gearUi.text[player] = nil -- v7
	bagOpen[player] = nil
	bagRefs[player] = nil
	musicMode[player] = nil
	sentTrack[player] = nil
	lastMusicSent[player] = nil
	toastToken[player] = nil
	skillState[player] = nil
	V8.charge[player] = nil -- v8
	buffs[player] = nil
	classRefs[player] = nil
	skillBarRefs[player] = nil
	classPanelOpen[player] = nil
	skillsOpen[player] = nil
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
			if mana then
				local cap = maxManaFor(player) -- v5: class mana pool
				if mana.Value < cap then
					mana.Value = math.min(cap, mana.Value + 4)
				end
				-- v7: Mana Regen affixes add on top (fractional
				-- amounts accumulate in playerFx.manaAcc)
				local cs = combatStats[player]
				local fx = playerFx[player]
				if cs and fx and cs.manaRegen > 0 and mana.Value < cap then
					fx.manaAcc = (fx.manaAcc or 0) + cs.manaRegen * 0.5
					local whole = math.floor(fx.manaAcc)
					if whole > 0 then
						fx.manaAcc = fx.manaAcc - whole
						mana.Value = math.min(cap, mana.Value + whole)
					end
				end
			end
			-- v7: Warrior rage decays out of combat (-3 per tick
			-- once 5s have passed since the last hit given/taken)
			if getClassId(player) == "Warrior" then
				local fx = playerFx[player]
				local rage = getStat(player, "Stats", "Rage")
				if rage and rage.Value > 0 and fx
					and os.clock() - (fx.lastCombat or 0) > 5 then
					rage.Value = math.max(0, rage.Value - 3)
				end
			end
			pcall(updateHUD, player)
		end
		-- v7: Paladin Holy Aura -- every Paladin radiates 1 HP/s
		-- (0.5 per tick) to self + allies within 14 studs
		for _, pal in ipairs(Players:GetPlayers()) do
			if getClassId(pal) == "Paladin" then
				local phrp = getHRP(pal.Character)
				if phrp then
					for _, p in ipairs(Players:GetPlayers()) do
						local hum = getHumanoid(p.Character)
						local phrp2 = getHRP(p.Character)
						if hum and phrp2 and hum.Health > 0
							and horizontalDistance(phrp.Position, phrp2.Position) <= 14 then
							hum.Health = math.min(hum.MaxHealth, hum.Health + 0.5)
						end
					end
				end
			end
		end
	end
end)

-- v7 STATUS LOOP (0.5s): ignite DoT ticks, boss HP bars,
-- Cold-enchant player slows
task.spawn(function()
	while true do
		task.wait(0.5)
		pcall(V7.tickStatus)
	end
end)
-- v6: training dummies on the town plaza (west side) + the four
-- leashed field slimes (they respawn at home via onEnemyDeath)
-- v8: dummies live in the fenced TRAINING YARD (SW district)
spawnTrainingDummy(Vector3.new(-60, 0, 208))
spawnTrainingDummy(Vector3.new(-53, 0, 216))
spawnTrainingDummy(Vector3.new(-46, 0, 208))
-- v8: the three authored field CAMPS (leashed, respawn at home)
-- slime pond camp (around the pond at (-52, 34))
V8.spawnFieldMonster("Slime", Vector3.new(-62, 0, 42))
V8.spawnFieldMonster("Slime", Vector3.new(-43, 0, 25))
V8.spawnFieldMonster("Slime", Vector3.new(-52, 0, 49))
-- goblin tent camp (west, south of the river)
V8.spawnFieldMonster("Goblin", Vector3.new(-84, 0, -33))
V8.spawnFieldMonster("Goblin", Vector3.new(-75, 0, -43))
V8.spawnFieldMonster("Goblin", Vector3.new(-80, 0, -27))
-- skeleton ruins camp (south-east ruins)
V8.spawnFieldMonster("Skeleton", Vector3.new(82, 0, -47))
V8.spawnFieldMonster("Skeleton", Vector3.new(94, 0, -58))
V8.spawnFieldMonster("Skeleton", Vector3.new(88, 0, -43))

task.spawn(aiLoop)
task.spawn(AI.projectileLoop) -- v6: enemy bone projectiles, 0.05s steps
task.spawn(waveLoop)
task.spawn(V8.chargeLoop)

-- v8 ART DIRECTION: cute chibi player proportions. R15 rigs
-- carry Humanoid scale NumberValues (HeadScale etc.); set them
-- when present and skip silently when not (R6 / partial rigs).
-- Big head, slightly shorter body = the kids-friendly look.
V8.applyChibi = function(character)
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local scales = {
		HeadScale = 1.35, HeightScale = 0.85, WidthScale = 1.0,
		BodyTypeScale = 0, ProportionScale = 0,
	}
	for name, value in pairs(scales) do
		local v = hum:FindFirstChild(name)
		if v and v:IsA("NumberValue") then
			pcall(function() v.Value = value end)
		end
	end
end -- v8: charge aura / bar upkeep (0.1s)

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

-- MUSIC LOOP (2s): Auto mode follows the player's zone; also forces
-- a re-send every ~14s so a client that loaded late still gets music.
task.spawn(function()
	while true do
		task.wait(2)
		for _, player in ipairs(Players:GetPlayers()) do
			local stale = (os.clock() - (lastMusicSent[player] or 0)) > 14
			pcall(sendMusic, player, stale)
		end
	end
end)

-- SKILL BAR LOOP (0.2s): cooldown countdown text on the skill bar
task.spawn(function()
	while true do
		task.wait(0.2)
		for _, player in ipairs(Players:GetPlayers()) do
			pcall(updateSkillBar, player)
		end
	end
end)

print("[ShiningSoul] v8 server started: charge attacks, skill-point visibility, redesigned authored world (town / river field / room-chain dungeon), cute chibi art direction. (v7 systems retained: affixes, sets, class identities, synergies, enchanted elites, Nightmare.)")
