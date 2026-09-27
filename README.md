# HSL Remake

《幻世錄》（The Legend of Fancy Realm，1998）第一章的非官方 Godot 4 重制。规则按原版证据复刻，原版程序当裁判；本仓库不含任何原版资源，运行需自备正版（见 [NOTICE](NOTICE.md)）。

## 现状

第八轮「原版当裁判」收口中。唯一的当前状态与下一步在 [docs/PROJECT.md](docs/PROJECT.md)，这里只写概貌，数字以它为准。

- **覆盖范围**：第一章 127 场战斗全部注册，剧情、城镇、大地图交接与三个结局接通；从标题「開始新故事」可一路玩下去，读档、宝箱、转职、升级加点、战利品都在正式路径上。机器剧情 explorer 能从第一关走到通关画面。
- **目标定义**：规则等价＋分布等价——敌人找谁、打谁、站哪、何时放法术的规矩与原版一样；随机选择要求多种子下的比例与原版一致，不追逐次抽取一致。用户指出的"和原版不一样"是线索，查清原版后照原版做（原版有 bug 除外）。
- **原版裁判**：在 CPU 模拟器里跑整个原版程序当裁判——敌人回合逐帧对照（`hsl check enemy_turn`）、交锋伤害逐值对拍、开局盘面逐字段对拍、AI 行动频率多种子对照；裁判管规则类差异，重制与原版的已知差异逐条登记在[差异清单](docs/evidence_packets/static_reverse/parity_gap_inventory.md)。
- **选项系统**：默认全部照原版；「重製選項」页（任何画面按 Tab）提供少量讲得清的体验改良，预设「原版／舒適／自定」。门禁与裁判只跑原版档（[OPTIONS](docs/OPTIONS.md)）。
- **已知缺口**：自动对局胜率低是原版难度（敌方按原版集火、机器人不躲），不是回归；剧情可通不等于战斗可通，也不等于已经过人工难度验收（[PLAYTEST](docs/PLAYTEST.md)）；原版全局随机流不与原版同步，部分演出时刻与字形仍是估计；第二章与终章战斗本体未接。

## 怎么跑

需要 Godot 4.x、Python 3（Pillow、NumPy），以及你自己的正版《幻世錄》：Steam《幻世錄 重製版》内含 1998 年經典版目录 `GAME-PAK/`。

```sh
export HSL_ORIGINAL_DIR=/path/to/GAME-PAK   # 含 hsl.pak 的正版目录，放在仓库外或 legal-assets/
tools/doctor.sh --original                  # 检查原版目录与关键文件是否在场
tools/play.sh                               # 先检查资源导入，再开游戏；导入失败直接报错
```

从空仓库一键导入原版资源的命令正在建设（[开源计划 §6](docs/OPEN_SOURCE_PLAN.md)）；准备细节见 [CONTRIBUTING](CONTRIBUTING.md)。

操作：左键选命令和目标，右键／Esc 取消；鼠标靠边或方向键卷动战场，Home 回到角色；对白点击或空格继续；Tab 开关「重製選項」，P 停格。人工验收某一关用 `tools/playtest.sh N`（独立存档直进第 N 关）。

## 怎么验证

```sh
tools/verify.sh           # 快门：全部注册表检查＋Godot 套件（热导入缓存）
tools/verify.sh --full    # 全门：先删导入缓存，证明冷克隆可导入
tools/verify.sh --deep    # 深门：再加剧情 explorer 与整章自动对局
tools/lane_verify.sh affected <基线提交>   # 改动中只跑命中的检查与套件
python3 tools/hsl.py check docs           # 只改文档时
```

检查由 `tools/hsl.py` 注册表按仓库数据枚举，`tools/hsl.py list` 看任务集；按改动选检查见[测试路由](tests/README.md)与[工具说明](tools/README.md)。自动门禁通过不代表画面与手感已和原版一致——视觉交给实玩。

维护者做原作运行观测时另用 Wine 前缀（`$WINEPREFIX`）和 `tools/hsl_original_control.py`，这是研究工具，普通贡献者不需要。

## 文档地图

| 想知道 | 读 |
| --- | --- |
| 项目做到哪、下一步 | [PROJECT](docs/PROJECT.md) |
| 全部文档怎么分工 | [文档地图](docs/README.md) |
| 工作规则（人与代理共用） | [AGENTS](AGENTS.md)、[CONTRIBUTING](CONTRIBUTING.md) |
| 代码分层、状态所有者、改哪里 | [ARCHITECTURE](docs/ARCHITECTURE.md) |
| 原版资源、静态分析与观测资料在哪 | [KNOWLEDGE_INDEX](docs/KNOWLEDGE_INDEX.md) |
| 每个机制的证据等级 | [机制矩阵](docs/MECHANICS_EVIDENCE_MATRIX.md)、证据用语 [CONTEXT](CONTEXT.md) |
| 加关卡、换配乐、写续集数据 | [EXTENDING](docs/EXTENDING.md)、[AUTHORING](docs/AUTHORING.md) |
| 开源计划与合规 | [OPEN_SOURCE_PLAN](docs/OPEN_SOURCE_PLAN.md)、[NOTICE](NOTICE.md) |

## 许可

代码、工具、测试用 [MIT](LICENSE)；文档与重制配乐用 [CC BY 4.0](LICENSE-docs)。两者都不涉及原版的任何部分：《幻世錄》及其名称、角色、美术、音乐与商标归宇峻奧汀科技及相关权利人所有，本项目与权利人无关联。
