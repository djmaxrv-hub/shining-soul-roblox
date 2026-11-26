# MAP DESIGN — v8 World Redesign

One authored, continuous world (no tiled patchwork): a hub town in the
south, a connected wilderness field with a river crossing in the
middle, and a room-based dungeon in the far north. Roughly 3x the
playable area of v7. North is -Z. All ground tops sit at y = 0; every
zone is ONE large continuous ground plane with authored detail on top
(paths are continuous ribbons, the plaza is a single stone disc).

## Research adopted (sources in README v8 section)

- **Shining Soul (GBA)**: game starts in a safe base-camp town
  (Prontis) with distinct service buildings (heal / weapon /
  accessory), then you leave town and travel to multi-room dungeons
  that end in a boss room. -> Our town has separate market row,
  smithy building, inn, class hall and training yard districts; the
  dungeon is a chain of rooms ending in a dedicated boss arena.
- **Diablo 2 Act 1**: Rogue Encampment (walled safe town, one gate)
  -> Blood Moor (open wilderness with monster camps) -> Cold Plains
  (waypoint + a second camp area) -> gated dungeon entrance. Zones
  are connected by roads/chokepoints, not teleports. -> Our field is
  crossed by ONE river with ONE bridge (a natural chokepoint and
  mid-field landmark), monster camps are authored clearings, and the
  only teleport is the dungeon gate itself (D2-style difficulty
  choice at the gate).
- Charge attacks and skill points are Shining Soul's signature:
  holding the attack button builds charge tiers, and every level-up
  grants a skill point the player spends deliberately. v8 surfaces
  both (see README).

## Layout (absolute coordinates)

### TOWN — center (0, 170), slab 190x190 (x -95..95, z 75..265), SAFE
Fence ring at x = +/-80, z = 90 (north) and z = 250 (south); the only
opening is the north gate at z = 90, x in [-7, 7] (posts + beam +
red/blue banners). A cobble main street runs plaza -> gate.

Districts:
- **Central plaza**: one stone disc r=34 at (0, 170) with ring trim,
  fountain at the center, spawn pad at (0, 188), flower beds at the
  four plaza corners, lamp posts.
- **Market row (NW)**, stalls at z = 126 facing the plaza:
  Item Shop (-38), Blacksmith (-18), Supplies (2, decorative).
  Shop prompt anchors sit in front of the first two stalls.
- **Smithy (NE)**: building at (54, 124) with chimney, anvil + forge
  glow outside at (46, 132).
- **Class hall (SE)**: building at (56, 214); Class Mentor podium at
  (42, 206), prompt stand at (42, 201).
- **Training yard (SW)**: fenced yard x -68..-38, z 200..228 with the
  3 training dummies.
- **Inn (S)**: two-story-look building at (20, 238) with INN sign;
  houses row at (-52, 236), (64, 232), (-70, 196), (66, 158).
- **Social corner (W)**: healing campfire at (-72, 168) + benches.
- **Notice board** by the gate at (-13, 97) (controls + charge +
  skill point hints).

### FIELD — plane 300x196 centered (0, -2) (x -150..150, z -100..96)
- **Road**: two continuous ribbons (with stone trim) from the town
  gate (0, 90) to the river, and from the river to the dungeon arch
  at (0, -84). Split-rail fences flank stretches of it.
- **River**: runs the full width at z = -18 (water strip 10 wide,
  recessed, stone banks). **One bridge** at x = 0 (plank deck + rails
  + ramps) is the only crossing.
- **Pond** at (-52, 34) with lily pads — slime camp shore.
- **Forests**: dense tree clusters NE (x 58..124, z 26..84), NW
  (x -124..-58, z 36..84) and SW (x -108..-58, z -78..-48).
- **Monster camps** (authored clearings; monsters are leashed to
  their camp and respawn there):
  - Slime pond camp: 3 slimes around the pond (-52, 34).
  - Goblin tent camp: 3 goblins at (-80, -36) — two tents, crates,
    barrel, bone pile, prop fire.
  - Skeleton ruins camp: 3 skeletons at (88, -52) — ring of broken
    pillars + altar in a ruins corner.
- **Healing campfires**: mid-field (26, -4) east of the road, and
  (-16, -72) near the dungeon gate.
- **Farmhouses** flanking the road at (34, 62) and (-40, 78).
- **Dungeon gate arch** at z = -84: stone pillars + beam + braziers +
  the purple portal part carrying the Normal (E) / Nightmare (F)
  difficulty prompts. Return portal lands at (0, -74).

### DUNGEON — center (0, -190), footprint 210x210 (x -105..105,
z -295..-85), one continuous slate floor; rooms are walled with
trim-capped brick walls (height 12, doorways >= 14 wide). The voids
between rooms are filled with solid rock mass, so the dungeon reads
as carved into stone. Coordinates below are relative to the center.

- **Entrance hall** (x -30..30, z 55..85): landing point (0, 74),
  return portal + arch on the south wall (0, 82), healing campfire
  in the SE corner (22, 66), 2 pillars, torches.
- **Corridor A** (x -7..7, z 8..55) -> **Hub** (x -20..20, z -12..8):
  crossing room with a second campfire (-15, -6), 2 pillars.
- **West corridor** (x -56..-20, z -7..7) -> **LAVA ROOM**
  (x -92..-56, z -30..24): lava pool at (-74, -3) (the "LavaPool"
  burn zone), orange glow, rocks.
- **East corridor** (x 20..56, z -7..7) -> **CRYSTAL ROOM**
  (x 56..92, z -30..24): glowing crystal clusters (purple + teal).
- **North corridor** (x -7..7, z -58..-12) from the hub ->
  **BOSS ARENA** (x -42..42, z -100..-58): round-feel room with 4
  pillars, 4 braziers, red banners, throne backdrop on the north
  wall; the Skeleton King spawns at (0, -80).

Wave spawn distribution follows the rooms: waves 1-2 entrance hall,
wave 3 split between lava + crystal chambers, wave 4 hub + corridors
+ chambers, boss waves in the arena (adds spawn in the arena too).
Champion-pack minions spawn next to their elite via the same table.

### Stuck handling
Dungeon rooms mean walls block straight-line AI movement. Enemies
track their own displacement per AI tick; a dungeon enemy that has a
target, is not mid-leap/dash, is not frozen, and has moved < 0.75
studs for ~1.2s asks PathfindingService for a path (throttled to one
compute per 1.5s per enemy) and follows its waypoints for up to 3s,
overriding the behavior's straight-line MoveTo. Field/town enemies
don't need it (open ground, leashes).

## Art direction (v8, applies to ALL future rounds)

**Cute / chibi / kids-friendly.** Bright, round, friendly — never
dark gritty realism. Concretely:

- **Players**: chibi proportions applied on every spawn (R15
  Humanoid scales: HeadScale 1.35, HeightScale 0.85, WidthScale
  1.0, BodyTypeScale 0, ProportionScale 0) — big head, short body.
- **Monsters**: rounded Ball-heavy construction and BIG friendly
  eyes (white + pupil for slime/goblin, big glowing round eyes for
  skeletons). Slimes are candy green (about a third spawn pink)
  with a glowing STAR core inside — no skulls, no gore. Goblins
  wear a cheerful orange tunic, carry a tiny wooden sword and a
  ROUND shield. Skeletons have an oversized round skull and a
  small body; the Skeleton King keeps his scale but gets a round
  golden crown with ball tips and a bright red cape.
- **Weapons**: chunky oversized proportions, brighter metal and
  stronger accent colors; the mage crystal is big and star-pink,
  the paladin hammer is extra chunky gold.
- **Palette**: cheerful midday lighting (ClockTime 13.6, bright
  ambient), brighter grass, 140 wildflowers, pastel banners in
  town; the dungeon stays moodier but colorful (teal crystals,
  warm braziers, bright arena banners).

## Coordinate constants (single source of truth in the script)
TOWN_CENTER (0,0,170) · DUNGEON_CENTER (0,0,-190) ·
DUNGEON_HALF_X 96 / DUNGEON_HALF_Z 96 (zone checks) ·
DUNGEON_ENTRANCE (0,3,-104) (gate teleports land 12 further north,
at rel z 74 in the entrance hall) · LAVA_REL (-74,0,-3), LAVA_HALF 5 ·
gate arch z = -84 · return landing (0,3,-74).
