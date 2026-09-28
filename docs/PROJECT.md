# HSL Remake — Current Project State

Checked: 2026-09-27

## 现状

在 Godot 4.x 中重制《幻世录》第一章。终点两个，按顺序：**① 第一章 127 场战斗像原版一样从标题玩到章末**（规则一致、节奏一致、画面手感经用户实玩认可）；**② 这套引擎能写续集**——没有原版数据可导入时，关卡／角色／技能／剧情只靠写数据就能跑。现在整章 127 场战斗、剧情／城镇／大地图交接与三个结局都已注册，从标题可走到章末；规则按"原版程序当裁判"逐项对齐（开局盘面全字段对拍、随机流照原版、AI 行动种类 127 关对拍无可确证的规则差异），演出与界面照原版录屏补齐；续集示范 龍脊隘口（LEVEL200）＋两名新角色只靠 `content/authored/` 数据可玩。机器人打关不等于玩家可通关，也不等于原版难度；**已合并项待用户实玩验收，验收前不算"已修好"**。旧战斗存档（v4）在新版本拒读。公开仓库 <https://github.com/catoncat/hsl-remake>（公开，三平台 CI 通过）。所有"像原版"的声明都要能追溯到资源、静态分析或原版运行实测（用语见 [CONTEXT](../CONTEXT.md)）。

## 进度尺

| 尺 | 最新值 | 从哪量 |
| --- | --- | --- |
| 和原版还差什么 | 107 条（2026-09-27） | [差异清单](evidence_packets/static_reverse/parity_gap_inventory.md)（`hsl check parity_inventory`）；汇报"还剩多少"按它 |
| 128 场自动对局 | win 20／fail 108／dead_end 0（2026-09-26）——伤害算法与敌方集火照原版、贪心机器人不躲，属难度不属回归 | `content/generated/hsl/development/autoplay/results.json`（深门重生成） |
| 整章播种走查 | 卡在 玩家第 3 场 · 逃出克萊恩城（LEVEL053），`game_clear=false` | `content/generated/hsl/development/autoplay/chapter.json` |
| 剧情可达 | explorer 走遍 22 段注册剧情、三个结局都到 GameClear；剧情可通不等于战斗可通 | 深门 `tests/run_story_mode_explorer_tests.gd` |
| 数据字段未消费 | 22／742（2026-09-22） | `hsl check field_coverage` |

逐关流转见[战役总览](evidence_packets/resource_inventory/campaign_overview.md)（生成物）；各系统的原版证据等级见[机制矩阵](MECHANICS_EVIDENCE_MATRIX.md)。

## 在跑

夜间自主编排（09-28 00:00–07:30）收 76 条 lane；白天（11:44 起至深夜）又合并发布约 49 条，差异清单 107→86 条。白天主要落地：128 场自动对局按最新规则重跑三轮，胜负变化逐场归因；反击方与攻方的击杀金钱各飘一份，不死防守方被致死一击站回后照原版不再反击、连击停；多段绝技逐击由对象程序驱动结算，命中才掷出的火花子对象补画，特效声音改按原生执行记录的 tick 播放、混音 9 通道；切入刀光 10 tick 满亮、32 tick 淡出后才切守方，守方按武器类的击中闪光补画，收尾过渡与续击交接逐 tick 对上；施法阴影只压桶 0x17 以下；法术受者条换原版小条与 24／24／40 tick 节拍、多受者逐人滑镜头出条、击杀 30 tick 后即开死亡演出；遮挡改为原版 32 px 行桶模型；地图物件放置读原版：组合物件链头子项补画（22／36 关瀑布与海面）、瀑布视差卷动、世界尺寸按地形行列、半透明按模板色、場景效果 开关照原版藏瀑布／建筑底／毒气烟；战斗五个面板按原版窗对象过程滑入滑出、压暗 0→8 级；对白擦出／上卷期间原版档不收确认，断行默认 38 字节硬断（专名保护归开关）；走步声按脚下地形选变体；19 个剧情特效对象与 37 关白光按原版命令程序演；獲得物品窗与装备持物窗照原版拿起即删格前收、放回落末尾、待领与商店列表用原版滚动条；用药范围照原版泛洪、AI 满血保留药槽、剧情用药不扣背包；設定選項 音量滑杆照原版混音器算式；谢幕状态单的復活次數 照原版计玩家倒下次数；城镇选人窗按转职位过滤；标题按住计时与淡出、镜头方向键与边缘叠加、Shift 两倍速等一并照原版。渲染验收驱动（第 1 场整场实跑）恢复通过；证据包体检两轮（95＋82 篇）。仍待实玩核对：以上凡标「未实玩」的可见变化，尤其施法阴影分层、面板滑动、法术受者条与逐人序列、遮挡顺序、多段绝技特写变长、37 关白光、22／36 关瀑布与海面。

<a id="next-steps"></a>

## 排队

1. 人工通关验收（含新做的状态页按钮排：上一位／下一位／道具／狀態／魔法／特殊技，与装备说明框悬停显示）：从标题打到 玩家第 3 场 · 逃出克萊恩城（LEVEL053）以后，按 [PLAYTEST](PLAYTEST.md) 格式回报，按类修。
2. 开源剩余：137 个不可再生文件（原版证据帧 104 张迁私有档案等）。

## 待拍板

- **用户**：上面"已合并待实玩验收"的各项，按 [PLAYTEST](PLAYTEST.md) 的格式回报。
- **负责人**：TOOLS 审计的 L7（研究工具挪 `tools/research/`）与 L8（删旧命令台账）；`hsl check --profile` 分层提议。

## 文档地图

- [README](../README.md) — 项目首页
- [docs/README](README.md) — 全部文档索引
- [MODDING](MODDING.md)、[MODDING_LEVELS](MODDING_LEVELS.md) — 改游戏
- [CONTRIBUTING](../CONTRIBUTING.md)、[ARCHITECTURE](ARCHITECTURE.md)、[AGENTS](../AGENTS.md) — 参与开发
- [KNOWLEDGE_INDEX](KNOWLEDGE_INDEX.md)、[MECHANICS_EVIDENCE_MATRIX](MECHANICS_EVIDENCE_MATRIX.md)、[BATTLE_NAMES](BATTLE_NAMES.md) — 查表

R1–R8 逐轮流水与合并回执在内部文档 `docs/internal/ROUNDS.md`（不随公开导出）。

<a id="validation"></a>

门禁口径：[CONTRIBUTING §2](../CONTRIBUTING.md) 的表为准，按改动选检查见[测试路由](../tests/README.md)；lane 与合并流程见 [AGENTS](../AGENTS.md)。
