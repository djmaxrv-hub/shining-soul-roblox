# QA_V7.md — v7 自检清单（代码级验证）

验证方式说明：本轮没有 Roblox 实机环境，以下全部为**代码级验证**——用 Luau 0.650 编译器编译 + grep 逐条追踪调用链。实机手感（动画、特效观感、数值体感）未验证，交付报告中已单独标注。

## 0. 编译与总量

- [x] `/tmp/luau-compile --binary` 退出码 **0**（7029 行）。中途撞过一次 200 局部寄存器上限（在 setupPortal 处），已按既有做法把 v7 装备表/函数折进单个 `GEAR7` 表、v7 战斗管线折进 `V7` 表后解决，终版编译通过。
- [x] 每个新函数 grep 验证「有定义、有调用」（见第 5 节）。

## 1. 技能释放链路（12 技能逐个追踪）

统一前段（12 个技能共用，grep 已验证）：

```
技能栏按钮 (Act="CastSkill", Arg=tostring(i)) ─┐
Q/E/R 热键 (UIClient: Q→"1" E→"2" R→"3",     ─┴→ UIEvent → 服务端 class 处理器
gameProcessedEvent 防聊天误触)                    (act=="CastSkill") → castSkill(player, idx)
→ 门禁: 无职业 toast / 技能未学 toast / 冷却 toast(带秒数, 技能急速已缩放)
  / needsTarget 无目标 toast / 资源不足 toast(战士怒气, 其余蓝量)
→ 扣资源 + 写冷却 → def.cast(player, lv, target)
```

| # | 技能 | cast 函数 | 效果落点（grep 行号以仓库版为准） | 协同 |
|---|---|---|---|---|
| 1 | Whirlwind 旋风斩 | castWhirlwind | enemiesWithin(9) → hitFn=V7.hitEnemy {source="Skill"} | ×synergyMul(Warrior,1) ← War Cry |
| 2 | Charge 冲锋 | castCharge | 位移循环内 enemiesWithin(4) → hitFn（hitSet 去重） | ×synergyMul(Warrior,2) ← War Cry |
| 3 | War Cry 战吼 | castWarCry | buffs[player] 写入，classDamageMul/classIncomingMul 读取 | —（它是协同源） |
| 4 | Frost Nova 冰霜新星 | castFrostNova | 先写 slowUntil/slowFactor，再 hitFn {element="Frost"} | ×synergyMul(Mage,1) ← Meteor |
| 5 | Meteor 陨石 | castMeteor | task.delay(0.8) 内 enemiesWithin(9) → hitFn {element="Fire"} | ×synergyMul(Mage,2) ← Frost Nova |
| 6 | Teleport 传送 | castTeleport | 位移 + inDungeon 钳制（无伤害） | — |
| 7 | Multishot 多重射击 | castMultishot | launchArrow(..., {source="Skill"}) → 箭 Touched → hitFn | ×synergyMul(Archer,1) ← Piercing |
| 8 | Piercing Shot 穿透箭 | castPiercingShot | 射线判定 → hitFn {source="Skill"} | ×synergyMul(Archer,2) ← Multishot |
| 9 | Arrow Rain 箭雨 | castArrowRain | 5 波 × enemiesWithin(10) → hitFn | ×synergyMul(Archer,3) ← Multishot |
| 10 | Blessed Hammer 祝福之锤 | castBlessedHammer | 轨道循环 0.4s 一跳 → hitFn {element="Holy"} | ×synergyMul(Paladin,1) ← Thorns |
| 11 | Heal 治疗 | castHeal | 14 码内全体玩家回血，回复量 ×synergyMul(Paladin,2) ← Blessed Hammer | （协同作用于回复量） |
| 12 | Thorns Aura 荆棘光环 | castSkill 内 toggle 分支 | st.thornsOn 翻转 → refreshThornsAura；反伤在 AI.damagePlayer（裸 damageEnemy，故意不走词条管线防递归） | —（它是协同源） |

技能放不了的根因修复验证：

- [x] `grantClassStarter`：chooseClass 首次选某职业 → 该职业 Skill 1 设为 Lv1 + SkillPoints +1；`st.freeGranted[classId]` 防重复领取；存档持久化（data.FreeGranted）。
- [x] v6 老存档迁移：onPlayerAdded 中若「有职业 + 三技能全 0 + 技能点 0 + 未领过」→ 自动补发 starter 包。
- [x] castSkill 冷却拒绝由 v6 的**静默 return** 改为 toast「<技能名> cooldown: Xs」（1 秒节流，st.cdToastAt）。
- [x] 其余拒绝全部有 toast：未学 / 无目标（"No target in range!"）/ 蓝不够 / 怒气不够（带获取提示）。
- [x] 技能栏未学文案：「Lv0 - open Skills to learn [Q]」。

## 2. 词条：聚合点与消费点（逐个）

聚合：`V7.recompute(player)`（applyGear 首行调用）遍历 4 个已穿戴件的 affixes 累加到 `combatStats[player]`。

| 词条 | 聚合字段 | 消费点 |
|---|---|---|
| CritChance | cs.crit（基础 0.05） | V7.hitEnemy 暴击 roll；聚合处钳制 ≤0.45 |
| CritDamage | cs.critDmg（基础 0.5） | hitEnemy critMul = 1 + cs.critDmg |
| Lifesteal | cs.lifesteal | hitEnemy 命中后按 dealt 回血（Vampiric ×2） |
| AttackSpeed | cs.atkSpeed | 剑/法杖/弓三个 handler 的冷却 = max(0.25, 基础/(1+atkSpeed))；Storm 2pc +0.12 也并入此字段 |
| FireDamage | cs.fire（×cs.fireMul 显示/计算） | hitEnemy 元素分量 + 点燃概率来源；Meteor 经 element="Fire" 吃 fireMul |
| FrostDamage | cs.frost | hitEnemy 元素分量 + 每次命中减速；Frost Nova 经 element="Frost" |
| LightningDamage | cs.lightning | hitEnemy 元素分量 + 30% 链电（基础 2 目标，Stormlord 4） |
| Execute | cs.execute | hitEnemy：目标 HP<30% 时 phys ×(1+execute) |
| KillRegen | cs.killRegen | hitEnemy 击杀检测（TakeDamage 前后血量）→ 回血（Vampiric 额外 +25） |
| Vitality | cs.vitality | maxHealthFor 加算（在职业倍率之前） |
| Bulwark | cs.bulwark | applyGear 写入 Stats.GearDEF（与胸甲 stat 相加）→ AI.damagePlayer 减伤（总上限 0.75 不变） |
| Swiftness | cs.swiftness | applyGear WalkSpeed = 职业基础 + 靴子 + swiftness；Cold 附魔减速恢复时也按此式重算 |
| SkillHaste | cs.haste（钳制 ≤0.30） | castSkill：cdLen = def.cd × (1 − haste) |
| ManaRegen | cs.manaRegen | 0.5s 主循环：小数累积 playerFx.manaAcc 后整点加蓝 |

传奇唯一特效消费点（全部在 hitEnemy，除注明外）：Inferno 爆炸（fx.boomCd 1s，范围伤害走裸 damageEnemy 不递归）、Stormlord（cs.chainTargets=4，聚合处）、Vampiric（吸血 ×2 + 击杀 +25）、Frostbite（cs.freezeChance=0.15 → data.frozenUntil，aiLoop 令 slowFactor=0）、Executioner（低血暴击 critMul +1.5）。

## 3. 套装：计算点

- 件数统计：`GEAR7.setPiecesEquipped(player, setId)`（tooltip 用）+ `V7.recompute` 内 cs.sets[setId] 计数（战斗用），两处同源（遍历 equipped.set）。
- 2pc：Inferno fireMul=1.25 + igniteChance 0.25→0.40（recompute）；Frost frostMul=1.25 + maxHealthFor 内 ×1.2；Storm atkSpeed+0.12 + lightningMul=1.25（recompute）。
- 3pc：Inferno 弱版爆发（hitEnemy，factor 0.35 / CD 2.5s）；Frost cs.frostGuard → AI.damagePlayer（25% 冻结攻击者 0.8s + 盾 = 15% MaxHP，CD 12s，盾在减伤前吸收）；Storm cs.stormStrike → hitEnemy 暴击触发（CD 2s，额外 80% + 光柱）。
- 掉落权重：onEnemyDeath — Boss 35%（噩梦 55%）走 spawnSetDrop（Epic 70% / 传奇 30%，噩梦传奇 50%），精英 gear 掉落中 8% 为套装件。
- tooltip：itemDetailText 输出 Set 名 + (n/3) + 两行 bonus 带 [ACTIVE]/[LOCKED]。

## 4. 存档往返字段（物品）

savePlayer.copyItem 写出：slot / rarity / name / stat / **affixes[{id, value}]** / **set** / **unique**。
loadPlayer.revive 校验重建：slot/rarity 对 STAT_BANDS/RARITIES 校验；affix id 对 GEAR7.AFFIX 校验、value 钳制到 [1, band 上限 ×1.5]；set 对 GEAR7.SETS 校验；unique 对 GEAR7.UNIQUE 校验；非法字段丢弃不报错。
另存：Skills（三职业等级）、ThornsOn、**FreeGranted**（starter 领取记录）。
Rage 为局内资源，不入存档（重进归零，符合设计）。

## 5. 新函数定义/调用配对（grep）

V7.synergyMul（9 个 cast 调用）/ V7.recompute（applyGear）/ V7.tracer（链电 + 附魔电击）/ V7.hitEnemy（剑、法杖、弓、7 个伤害技能经 hitFn 或 launchArrow opts）/ V7.lightningZap（damageEnemy 钩子）/ V7.enchantDeath（onEnemyDeath）/ V7.soulOrbs（onEnemyDeath）/ V7.styleWeapon（restylePlayerSword ×2 路径）/ V7.updateBossBar（tickStatus）/ V7.tickStatus（0.5s 状态循环 pcall）/ GEAR7.setPiecesEquipped、itemDetailText、rollBandValue、rollAffixes、buildItemName、rollSetItem、spawnItemDrop（均在装备链内互调）/ grantClassStarter（chooseClass + onPlayerAdded 迁移）/ setupDungeonGate（文件底部调用一次）。
裸 damageEnemy 残留点审计：仅剩荆棘反伤（故意）与 V7 内部二级伤害（链电/爆发/风暴打击/点燃跳伤，故意不递归触发词条）。

## 6. 怒气（Rage）路径

- 建值：onPlayerAdded makeInt(stats, "Rage", 0)。
- 获得：剑命中每敌 +6（hitEnemy opts.rage，仅 Warrior 生效，劈砍 3 敌最多 +18/挥）；受击 +3（AI.damagePlayer）。
- 消耗：castSkill Warrior 分支按 def.rage 扣（旋风 30 / 冲锋 20 / 战吼 25），不足 toast。
- 衰减：0.5s 主循环，脱战（fx.lastCombat 超 5s）每 tick −3。
- HUD：updateHUD 中 Warrior 时 ManaLabel 变红字 "RAGE x / 100"，切回其他职业恢复蓝字 Mana。
- 技能面板：refreshSkillsUI meta 行显示 Rage 消耗；Points 行显示当前 RAGE。

## 7. 平衡上限校验

- [x] 暴击率：聚合钳制 gear crit ≤ 45%，hitEnemy 内加 Deadeye 后再钳制 ≤ **60%**。
- [x] 减伤：AI.damagePlayer 原有 0.75 总上限未动（Bulwark 只是多了一个来源）。
- [x] 攻速：三个武器 handler 冷却下限 **0.25s**（math.max 强制）。
- [x] 技能急速钳制 ≤ 30%（recompute）。
- [x] 词条数值带：全部在 AFFIX_DEFS.bands 内滚动；ilvl tier 3 溢出上限 band×1.15（rollBandValue），存档读回钳制 band×1.5。
- [x] 噩梦数值：HP ×2.2 / 伤害 ×1.5 / XP·金币 ×1.8 均在 startWave.tune 单点施加；Boss 召唤的小怪不走 tune（保持原数值，已在报告中注明为简化）。

## 8. D2 追加项落点

- 协同：V7.SYNERGY 表 + synergyMul（9 处）+ 技能面板 Synergy 行。
- 附魔精英：spawnEnemy 掷 enchant（Fire/Lightning/Cold/Strong/Fast 均匀 20%）；Strong ×1.6 伤害、Fast ×1.45 移速在 data 生成处；Lightning 钩子在 damageEnemy；Fire/Cold 死亡效果在 V7.enchantDeath；名字前缀在 displayName。
- 冠军群：startWave.tune 中精英额外 spawn 2 只同类（suppressElite 保证小怪不再掷精英，无递归）。
- ilvl：onEnemyDeath 计算 tier（波次 ≥4 → 2，Boss → 3，噩梦 +1 封顶 3）→ spawnGearDrop(position, weights, tier) → rollBandValue 分 tier 偏置。
- 噩梦：waveLoop Boss 波次清空时置 V7.nightmareUnlocked；setupDungeonGate 双 ProximityPrompt（E 普通 / F 噩梦，未解锁 toast 拒绝）；难度为全地牢会话级（V7.difficulty），由进门者选择、在 spawn 时由 tune 施加。

## 9. 未实机验证项（诚实标注）

- 全部视觉（武器剪影、水晶法杖浮动、怪物道具、Boss 血条、地形装饰）只过了编译与坐标逻辑，未在 Studio 里看过实际效果。
- ProximityPrompt 双提示同挂一个 Part 时的 UI 呈现（E/F 两个键位）未实机确认；若客户端只显示一个，需改挂到拱门两侧柱子。
- 音效/BGM 的既有未验证音频 ID 问题与 v7 无关，未处理。
