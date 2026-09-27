# 麻痺：施加、新行动入口跳过、解除与防护

> evidence: resource-derived; static-derived · status: live · functions: 0x40aa80, 0x40b910, 0x40c230, 0x448840 · tools: hsltools/assets/paralysis_assets.py, hsltools/probes/paralysis.py, run_support_magic_tests.gd · updated: 2026-09-27

## 结论

- 原版：麻痺（flags 含 4）者在 phase 0 的新行动入口被跳过（玩家 `0x443996`、AI `0x43f47b`）；地靈縛施加 2 或 3 次、累计上限 9，每次实际增加的计时 ×10 作为贡献；`0x40b910` 按行动递减到期清除；精靈石（item 效果 `0x20000000`）清麻痺；装备 `avoid_paralysis` 与固有 `no_paralyze` 防止后续麻痺但不治疗已有（static-derived）。
- 重制：`ActionEntryRules` 只读判定入口资格，麻痺时产生一次 `paralysis_skip` 收据并只走一次现有行动尾部，绕过白光之翼额外行动查询；`StatusEffectRules` 管三类 counter（static-derived）。
- 差异：高位状态机其余分支、wake 回调与死亡 handler 未恢复；施法粒子、混色与显示时钟是重制编排（provisional）。

## 证据

**static-derived**（Unicorn 合成内存，EXE 只读、callee 不替换；结果见 [original_paralysis.json](original_paralysis.json)）

| 入口／字段 | 行为 | 执行范围 |
| --- | --- | --- |
| 玩家 `0x443996`、AI `0x43f47b` | 引擎启用、flags 含 4 且对象 phase 为 0 时跳过新行动；玩家跳 phase `0x10003`，AI 跳 `0x640001`；其他 phase 不截断 | 96 组前段，止于下游尾部前 |
| `0x40aa80` 地系 05 | 独立状态命中、2 或 3 次、上限 9；增加的计时 ×10 为贡献 | 72 组前段到 `0x40b831` |
| `0x40b910` | 毒、麻痺、禁魔分别递减低字，到期清 flag 与 counter | 36 组正常返回 |
| `0x40a30c` | item 效果 `0x20000000` 清 flag4 与 actor+0x3c | 12 组前段止于 `0x40a31f` |
| `0x40c230` | 按八槽顺序找第一个匹配异常的恢复道具，返回 1-based 位置，非药品跳过 | 30 组正常返回，无 RNG、无写入 |
| `0x448840` 与装备应用 | 清旧 working 值，当前装备与非空槽映射的固有能力合并防麻痺，不清已有麻痺 | 24 组 ×2 = 48 正常返回 |

入口前段只改对象 phase，没有执行毒伤、资源恢复、队列推进或额外行动 latch；已知下游 caller 说明它绕过额外行动查询。

**resource-derived**：地靈縛 `magic:magicEARTH:magicCode05`，主／状态命中 40、MP16、数值 12..36、`magicFun_Paralysis=4`，施法 `range3CellCircle`、效果 `range1Cell`；状态施加用独立 proc6，魔法主命中饰品不提高状态成功率；免疫 `0x4000000` 或全状态保护 `0x80` 时不抽样、不扣 HP、无贡献。源角色 052／056／060 声明该技能。精靈石 248 只解麻痺；虹之首飾 211 与霸邪天煌 31 防麻痺（31 受重装职业限制）；`avoid_paralysis` 是装备主效果 `0x4000000`，固有 `no_paralyze` 先映射 capability `0x800`。全状态药 251 只在源扫描样例出现。`hsltools/assets/paralysis_assets.py` 导出地系对象 8 帧与 UPGROUND01／BOMB0006 两个声音。

## 重制接线

- `game/sim/ActionEntryRules.gd`：只读入口资格，先做完整数据校验与终态检查；当前可控角色麻痺时不开菜单，转入有界自动动作入口，毒伤→HP／MP 回复→血转 MP→到期反馈各一次；到期不赠送当前槽的新行动。
- `StatusEffectRules`：麻痺 counter 0..9，JSON 初始化先验证再转整数；独立存档配置由 `source_resource_tail_v3` 等识别。
- 反击门禁拒绝麻痺者反击；受支持的伤害不自行清麻痺，死亡清状态并释放单格占用。
- AI 以同侧异常目标扫描、类别选择与首个匹配道具槽组合可达相邻位置用药；旧意图在移动、扣物或 RNG 前拒绝（provisional：地图收益与路径组合为重制适配）。
- 到达／败北条件已满足时在状态与资源尾部之前冻结结果。
- `ParalysisMagicPresentation`：前摇、脚点投影、释放／命中各一次；入场显示「麻痺 · 無法行動」，到期／用药显示「麻痺解除」；无资源尾部的用药数字也纳入输入阻塞（provisional：粒子、烟雾、100 tick/s 换算）。

## 复现

`python3 tools/hsl.py check paralysis`；`python3 tools/hsl.py check paralysis_assets`；重制侧 `tools/godot.sh --headless --script tests/run_support_magic_tests.gd`。14 条实际输入回执（`runtime_observations/paralysis/receipt.json`）驱动已退役，回执为历史记录。

## 边界

- 完整高位状态 dispatcher、全部 wake／死亡回调未恢复。
- 命中附带状态的其他来源、弱化／增益与复活不在本包。
- 全状态防护道具的其他效果未开放。
- 大型占地的全空间合同见 [original_large_actor.md](original_large_actor.md)。
