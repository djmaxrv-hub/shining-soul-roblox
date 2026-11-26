# QA — v8 (charge attacks / skill-point visibility / world redesign / cute pass)

Scope note: **code-level verification only** (Luau compile + static
traces below). No Roblox Studio in this environment, so nothing here
was playtested; anything runtime-only is flagged as such.

## Compile gate
- `ShiningSoulServer.server.lua` (7,9xx lines): `luau-compile --binary` exit 0.
- `UIClient.client.lua` (with the new charge forwarder): exit 0.
- Chunk-local budget: the build hit Luau's 200-local limit once
  (SAVE_FIELDS allocation); resolved by folding all v8 charge
  constants/helpers into the `V8` table (no behavior change).

## 1. Charge attack chain (trace)
- Client: `UIClient.client.lua` InputBegan (MouseButton1 / Touch,
  `gameProcessedEvent` filtered) → `FireServer("Charge","Begin")`;
  InputEnded → `("Charge","Release")`; a local `chargeHeld` flag
  prevents duplicate Begins.
- Server router: `uiEvent.OnServerEvent` branch `act == "Charge"`
  (line ~7270) → `V8.chargeBegin` / `V8.chargeRelease`.
- Begin validation: player alive + a loadout Tool equipped
  (`V8.equippedWeapon` via `FindFirstChildOfClass("Tool")` +
  `isLoadoutTool`); otherwise the Begin is dropped silently.
- State: `V8.charge[player]` {since, aura, baseSpeed}; WalkSpeed
  ×0.7 on begin, restored by `V8.cleanupCharge` on release / death /
  unequip (the 0.1s `V8.chargeLoop` sweeps dead/unequipped states).
- Tiers: held ≥ 0.7s = T1, ≥ 1.5s = T2 (`V8.tierOf`). Release
  cooldown 1.2s (`lastAction.charge`).
- Release dispatch by class → `V8.chargeWave` (Warrior / no-class),
  `V8.chargeSlam` (Paladin), `V8.chargeOrb` (Mage),
  `V8.chargeArrow` (Archer). All four route damage through
  `V7.hitEnemy` with `{ source = "Charge", big = tier == 2 }`
  (4 call sites verified by grep), so affixes / crit / elements /
  sets apply and T2 numbers render big (the `big` flag was added to
  `spawnDamageNumber` and forwarded by `V7.hitEnemy`'s display opts).
- Interrupt: `AI.damagePlayer` calls `V8.cancelCharge` when a single
  hit exceeds 15% MaxHP → cleanup + "Charge interrupted!" toast.
- HUD: server-built `ChargeBar` (bottom-center) is shown/filled by
  `chargeLoop` only while that player charges; fill = held/1.5,
  gold at T1, red + "CHARGE MAX!" at T2.
- Name-collision check: Warrior skill 2 is also called "Charge"
  (v5, `castCharge`, reached via `CastSkill`) — a different path
  from the UIEvent charge attack; both coexist, no shared state.
- NOT playtested: aura feel, wave/orb/arrow hit registration at
  runtime, touch-device behavior (camera drags also send Begin —
  documented tradeoff in README).

## 2. Skill-point visibility (update points)
All four paths converge on the 0.5s `updateHUD` loop, which is the
single writer of the new UI:
- `SkillPtsLabel` (permanent HUD line, built in `buildHUD`) is set
  from `Stats.SkillPoints` every tick; gold when > 0.
- The bag's Skills button text flips between "Skills" and
  "Skills (!)" in the same tick (`bagRefs.skillsButton`).
- Level-up path: `addXP` toast now reads "+N Skill Point(s) - open
  Skills to spend it!" (4s) — verified at the call site.
- Panel: header "Skill Points available: N (earn 1 per level-up)";
  each row shows Lv x/5, **Now:** (current `def.desc(lv)` first
  line, or "Not learned yet") and **Next:** (`def.desc(lv+1)`, or
  "MAX LEVEL"); learn button enlarged to "[ + ]"; `skillUp`'s
  maxed / no-points reason toasts unchanged from v5.
- Join / class-change / learn all mutate the same Stats value, so
  the 0.5s tick covers them without extra wiring (traced, not
  playtested).

## 3. Map coordinate audit
Single source of truth at the top of the script: `TOWN_CENTER
(0,0,170)`, `DUNGEON_CENTER (0,0,-190)`, `DUNGEON_HALF_X/Z = 96`,
`DUNGEON_ENTRANCE (0,3,-104)`, `LAVA_REL (-74,0,-3)`, `LAVA_HALF 5`.
- Gate teleport: lands at `DUNGEON_ENTRANCE + (0,0,-12)` = rel
  z 74, inside the entrance hall (hall spans rel z 55..85). ✓
- Return portal destination (0,3,-74): on the field, south of the
  arch at z=-84. ✓ Return portal part sits at rel z 82 in the hall. ✓
- Campfires (heal reads parts named "Campfire"): dungeon entrance
  hall (rel 22,66) + hub (rel -15,-6) via the dungeon-local
  `buildCampfire`; field sites (26,-4) and (-16,-72) + town social
  corner via `buildCampfireSite`. ✓
- Lava: pool part and the damage zone both derive from
  `DUNGEON_CENTER + LAVA_REL` (rel -74,-3, inside the lava room
  x -92..-56 / z -30..24). ✓
- Wave spawns: `dungeonSpawnPosition` distributes by `wave % 5`
  across hall / chambers / hub+corridors / arena; boss at rel
  (0,-80) inside the arena (z -100..-58). ✓
- Field camps: `V8.spawnFieldMonster` with fixed homes — slimes
  (-62,42) (-43,25) (-52,49) around the pond (-52,34); goblins
  (-84,-33) (-75,-43) (-80,-27) at the tent camp (-80,-36);
  skeletons (82,-47) (94,-58) (88,-43) at the ruins (88,-52).
  Death respawn re-uses `data.kind` + `data.home`, so camps keep
  their species (the v6 all-slime respawn bug is gone). ✓
- Training dummies inside the fenced yard (-60,208) (-53,216)
  (-46,208). ✓ Shops: potion stand (-38, TC-39), upgrade stand
  (-18, TC-39) in front of the market-row stalls. ✓
- `castTeleport` clamp tightened to the authored extents
  (x ±90, z rel -97..+82) so a blink cannot land in the rock fill
  south of the entrance hall. ✓
- Zone checks (`inDungeon`, town safety, music) all read the same
  constants; no stale v6/v7 coordinates remain in spawn/teleport
  code paths (grep-audited).

## 4. Pathfinding fallback (trace)
- Call site: `aiLoop`, after behavior dispatch + elite slam check:
  only when `data.zone == "Dungeon"`, target exists, enemy not
  busy. `V8.pathMove` runs last in the tick, so a followed waypoint
  MoveTo overrides the behavior's straight-line MoveTo.
- Stuck detection: per-enemy displacement sampled each tick
  (`ai.lastPos`); < 0.75 studs in a tick while distance > 6 and not
  slowed accumulates `stuckFor`; ≥ 1.2s triggers a compute.
- Compute: `PathfindingService:CreatePath({AgentRadius=2,
  AgentHeight=4, AgentCanJump=false})` inside pcall in a spawned
  task, throttled per enemy (`ai.pathNext`, 1.5s); on Success the
  waypoints (first point skipped) are followed for up to 3s
  (`ai.pathUntil`), advancing within 3.5 studs.
- Failure modes are silent-safe: pcall failure or non-Success
  status just leaves the normal MoveTo behavior in charge.
- NOT playtested: actual in-room navigation quality in Studio.

## 5. Cute / chibi pass (trace)
- `V8.applyChibi` is called from `onCharacterAdded` on every spawn;
  it pcall-sets HeadScale 1.35 / HeightScale 0.85 / WidthScale 1.0 /
  BodyTypeScale 0 / ProportionScale 0 only when the NumberValue
  exists (R6-safe). Runtime visual result NOT verified (needs a
  real R15 avatar in Studio).
- Monster/weapon/palette changes are pure construction parameters
  inside `buildEnemyVisual`, `V7.styleWeapon`, `styleSword`,
  `styleSwordRarity`, `createFireballTool`, and the world builders;
  no AI/stat code paths were touched by the pass (diff-audited by
  replacement scope).
- Slime pink variant uses `math.random()` at build time (~35%);
  per-part color, so damage flash restore is unaffected.

## Known leftovers / honest limits
- No playtest: charge feel, pathfinding quality, chibi scaling on
  real avatars, and the dual-prompt gate presentation all need one
  Studio session to confirm.
- v7's unverified sound/BGM asset IDs are unchanged.
