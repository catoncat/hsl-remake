# 毒魔箭：琥的 ST 范围绝技，伤害后独立施毒

> evidence: static-derived · status: live · functions: 0x40a7b0, 0x40aa80 · tools: hsltools/data/poison_arrow.py, hsltools/probes/poison_arrow.py · updated: 2026-09-27

## 结论

- 原版：毒魔箭（SPECIAL magicMIND／magicCode03）先按 special channel1 伤害公式与主命中结算，目标死亡不再施毒；存活且不免疫者做独立 proc6 毒命中（用主 hit_ratio 与命中补偿），毒次数 `2+rand(2)`，强度取另一次 proc0 数值的 30%；贡献＝实际伤害＋新增毒次数×10（static-derived；44 组数值完整返回、49 组应用前段）。
- 重制：纯 `PoisonArrowRules` 回传变更，共用 `SkillResolution` prepare／resolve，全部目标完成后一次扣 20ST、一次最终 EXP；PlayLoop 统一提交（static-derived）。
- 差异：多目标按稳定 roster 遍历是重制调度；`PoisonArrowPresentation` 的版面、粒子与时钟是重制演出（provisional）。

## 证据

**static-derived**（[original_poison_arrow.json](original_poison_arrow.json) 保存 SPECIAL／TYPE／EXE 身份与每组 RNG bounds／value）

| 范围 | 覆盖 |
| --- | --- |
| `0x40a7b0` special channel1 完整返回 ×44 | 伤害公式、主命中、精神系抗性、HP 上限 |
| `0x40aa80` 应用前段 ×49，止于 `0x40b831` | 死亡跳过、免疫、毒命中与主命中分离、毒合并保留其他旗标、重复施毒不把未增加的时间算贡献、HP1 |

**resource-derived**：`SPECIAL.TXT` magicMIND／magicCode03：`damage=30,45`、`hit_ratio=98`、`expend=1`（换成 20ST）、`range3CellThrust`、`effect_range=range1Cell`、`magicFun_Attack,magicFun_Poison`；初始取得来自 PLAYERS003 的 special_mind 声明（不是弓给的能力）。`hsltools/data/poison_arrow.py` 从 spec37／spec38 效果序列与 OBJ-ALL／PAK 解出 SP00_003、SP19（发射、投射、毒球）与 ATTACK09／SPECIAL6；`P003_201` 是肖像条，202 脸部小窗，203..206 手／拉弓小窗。

## 重制接线

- `PoisonArrowRules`：prepare 在支付或 RNG 前验证全部受影响目标；只对不同 actor 结算一次，大体型不重复中招；过程中不以中途升级重算后续目标。
- 禁魔不封 ST 绝技；麻痺、气力不足、失效目标完整拒绝；移动后仍按绝技自身范围，取消无费用；白光之翼只给新的整次行动，天劫双击不加倍支付或毒回调。
- `PoisonArrowPresentation`：原图分窗合成，地图上对受影响位置播投射／毒效果与实际伤害／状态文字，一次 release／impact（provisional：版面、轨迹、scale、混色、以 0.4 播放速率换算的时间）。
- 角色来源与实玩见 [original_ohm_village.md](original_ohm_village.md)。

## 复现

`python3 tools/hsl.py check poison_arrow`；`python3 tools/hsl.py check poison_arrow_data`。

## 边界

- 整次原施放、整场战斗与原墙钟未执行。
- 原全区对象遍历顺序未读，不由单目标前段推论。
- 毒的计时与毒伤见 [original_status_application.md](original_status_application.md)。
