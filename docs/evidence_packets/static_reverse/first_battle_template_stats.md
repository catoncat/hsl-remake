# 第一战模板属性函数探针

> evidence: static-derived; provisional: 合成初始化 · status: live · functions: 0x448420, 0x448840 · tools: hsl_native_stats_probe.py, hsltools/data/first_battle_formation.py · updated: 2026-09-08

Evidence: `static-derived`，合成初始化仍为 `provisional`。本结果不等于原作第一可操作帧，HP/MP/攻防/命中/速度已作为重制版基线接入；尚未包含 NPC 等级调整。

`tools/hsl_native_stats_probe.py` 在隔离 x86 仿真中执行指定 SHA256 的原版 EXE `0x448840`，加载 tracked PLAYERS、ITEM、TYPE 表中的五个第一战模板，分别计算空装备与初始装备结果。紧凑输出见同目录 `first_battle_template_stats.json`，含输入哈希。无需启动 Wine，也不会控制键盘鼠标。

复跑（Unicorn 仅为分析依赖）：

```sh
uv run --with unicorn==2.1.4 python tools/hsl_native_stats_probe.py --output ignored/native-stats/probe.json
cmp ignored/native-stats/probe.json docs/evidence_packets/static_reverse/first_battle_template_stats.json
```

| 模板 | HP | MP | 攻击 | 防御 | 速度 |
|---|---:|---:|---:|---:|---:|
| 001 雷欧纳德 | 30 | 0 | 54 | 43 | 14 |
| 021 敌步兵 | 22 | 0 | 45 | 30 | 15 |
| 023 友军步兵 | 29 | 0 | 45 | 36 | 14 |
| 024 友军重兵 | 43 | 0 | 52 | 61 | 12 |
| 026 敌法师 | 33 | 30 | 21 | 22 | 11 |

入口读取基础属性及职业，`0x448420` 累加装备，`0x44b62c`/`0x44b655` 加 HP/MP 模板附加值，`0x44b678` 计算升级门槛。`0x44b7b8..0x44b815` 合并六个已学魔法槽；全空时设置禁用 MP 标记并清零 MP。探针用非零哨兵模拟“有魔法”这一布尔条件，不声称恢复各法术的内部 ID。最初未初始化这个条件会错误得到法师 MP 0。

速度与既有独立静态推导的 14/15/14/12/11 一致；装备前后差值可用于核对装备字段绑定。这里只运行属性刷新，不运行原版资源 parser、NPC 等级调整、库存被动或异常状态。因此尤其不能把 NPC 表级别 1 的结果直接声明为关卡现场数值。HP/MP 已经通过两条实际主场景路线验证（坚守撤离、前出攻击并用药后撤离）；攻防与命中接入后再次完成两条路线；法术改用元素抗性减伤，气刃斩仍使用其原表伤害减物理防御，完整原版技能公式尚未确认。

探针限定 EXE 哈希、可执行地址范围与指令上限。没有新增游戏依赖或通用仿真框架；无值得额外删除验证的抽象层。

`tools/hsltools/data/first_battle_formation.py` 消费本包 JSON，先复核 PLAYERS/ITEM/TYPE 输入哈希，再生成各单位 hp/max_hp 和法师 initial_mp。游戏只读生成后的场景配置，不加载 EXE、不依赖 Unicorn。NPC 等级调整尚未接入，因此 provenance 保留 provisional，不声称现场原版数值。

攻防接入时删除了生成器中重复的职业/装备速度计算，改读同一探针 speed；`--check` 确认 12 个单位生成结果的速度及队形未改变。PLAYERS 的五类元素抗性以 TYPE.H 0..4（地/水/风/火/心）导入，缺省按零建模并限制 0..80；这项缺省处理沿用探针合成初始化边界，不冒充原版 parser 证据。

状态页现显示同一 PLAYERS 模板的非空装备槽，item_code 来自 *_equip，名称由 ITEM.name → RESOURCE 解析，生成至场景单位 equipment 字段。查看时读取 PlayLoop 单位，不建立 UI 装备副本；暂不提供换装。生成器 `--check` 同时验证槽位、代码、名称，运行时测试覆盖玩家武器/铠甲、切到法师木杖/护身符及查看不改变回合。实际截图已核对左侧装备列表与右侧属性无溢出。复用了既有导入路径和状态面板，没有可额外删除的抽象层。

NPC 等级选择后续已独立核对，见 `first_battle_level_selection.md`。（2026-09-25 更正："本战保留固定一级"的旧决定已被原出生调级取代——开战时每名 NPC 按 `0x40e870` 抽等级，录屏里的 023_2 L3 41/41 在其分布内，见[触发条件](original_auto_growth.md#开战调级的触发条件)。）本表仍是 1 级模板的刷新值，不是现场数值。
