# HSL Remake — Current Project State

Checked: 2026-09-30

## 现状

在 Godot 4.x 中完整重制《幻世录》。终点两个，按顺序：**① 全部 127 场战斗像原版一样从标题玩到结局**（规则一致、节奏一致、画面手感经人工实玩认可）；**② 这套引擎能写续集**——没有原版数据可导入时，关卡／角色／技能／剧情只靠写数据就能跑。现在整章 127 场战斗、剧情／城镇／大地图交接与三个结局都已注册，从标题可走到章末；规则按"原版程序当裁判"逐项对齐（开局盘面全字段对拍、随机流照原版、AI 行动种类 127 关对拍无可确证的规则差异），演出与界面照原版录屏补齐；续集示范 龍脊隘口（LEVEL200）＋两名新角色只靠 `content/authored/` 数据可玩；公开导出只凭文档能从 `hsl bootstrap` 走到自制一关自动打赢。机器人打关不等于玩家可通关，也不等于原版难度；**已合并项待人工实玩验收，验收前不算"已修好"**。公开仓库 <https://github.com/catoncat/hsl-remake>（三平台 CI 通过）。另有浏览器版（Godot 网页导出，关卡与影片按需下载），已验证到从标题进玩家第 1 场，整章没有在浏览器里走过，见 [WEB](WEB.md)。所有"像原版"的声明都要能追溯到资源、静态分析或原版运行实测，怎么核对见 [METHOD](METHOD.md)。

## 进度尺

| 尺 | 最新值 | 从哪量 |
| --- | --- | --- |
| 和原版还差什么 | 88 条（2026-10-02） | [差异清单](evidence_packets/static_reverse/parity_gap_inventory.md)（`hsl check parity_inventory`），汇报"还剩多少"按它 |
| 128 场自动对局 | win 20／fail 108／dead_end 0（2026-09-29）；前瞻驾驭同种子 win 50／fail 76／dead_end 1，另 1 场限时未打完（2026-09-30）。是难度信号，不是原版平衡证据 | `content/generated/hsl/development/autoplay/results.json`；前瞻 `brain_sweep.json` |
| 整章播种走查 | 40 场走到通关（`game_clear=true`）：自然胜 19、强判胜 21，没有规则拒绝 | 实玩包生成日志（`tools/hsl_playtest_kit.py generate --force-win`，不入库） |
| 剧情可达 | explorer 走遍 22 段注册剧情，三个结局都到 GameClear | 深门 `tests/run_story_mode_explorer_tests.gd` |
| 数据字段未消费 | 22／742（2026-09-22） | `hsl check field_coverage` |

逐关流转见[战役总览](evidence_packets/resource_inventory/campaign_overview.md)（生成物）；各系统的原版证据等级见[机制矩阵](MECHANICS_EVIDENCE_MATRIX.md)。

<a id="next-steps"></a>

## 1.0 的条件

1. 从标题完整玩一遍整章，按 [PLAYTEST](PLAYTEST.md) 的格式回报看得见的差异，按类修完。
2. Windows 真机跑通：`tools\play.ps1` 从 bootstrap 到标题、打完一场。
3. 公开检出只凭文档可用——已达成：干净导出里从 `hsl bootstrap` 走到自制一关自动打赢；核对方法见 [METHOD](METHOD.md)，改游戏见 [MODDING](MODDING.md)。bootstrap 后仍缺的只是证据文件（原版帧、探针记录），不影响游戏。

<a id="待拍板"></a>另有两件工具整理待定，都不挡 1.0：研究工具是否挪进单独目录并删掉旧命令台账，`hsl check --profile` 是否再分层。

## 文档地图

- [README](../README.md) — 项目首页；[CHANGELOG](../CHANGELOG.md) 按日期记录每次发布
- [docs/README](README.md) — 全部文档索引
- [PLAYING](PLAYING.md)、[PLAYTEST](PLAYTEST.md)、[WEB](WEB.md) — 玩与试玩
- [MODDING](MODDING.md)、[MODDING_LEVELS](MODDING_LEVELS.md) — 改游戏
- [METHOD](METHOD.md)、[CONTRIBUTING](../CONTRIBUTING.md)、[ARCHITECTURE](ARCHITECTURE.md)、[AGENTS](../AGENTS.md) — 参与开发
- [KNOWLEDGE_INDEX](KNOWLEDGE_INDEX.md)、[MECHANICS_EVIDENCE_MATRIX](MECHANICS_EVIDENCE_MATRIX.md)、[BATTLE_NAMES](BATTLE_NAMES.md) — 查表

R1–R8 逐轮流水与合并回执在内部文档 `docs/internal/ROUNDS.md`（不随公开导出）。

<a id="validation"></a>

门禁口径：[CONTRIBUTING §2](../CONTRIBUTING.md) 的表为准，按改动选检查见[测试路由](../tests/README.md)；lane 与合并流程见 [AGENTS](../AGENTS.md)。
