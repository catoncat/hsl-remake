# HSL Remake

《幻世錄》（The Legend of Fancy Realm，1998）第一章的非官方 Godot 4 重制，目的是让你基于它改出自己心里的游戏：换素材、改规则、加关卡与角色，或者只是把原版第一章从标题玩到章末。规则按原版证据复刻，原版程序当裁判。本仓库不含任何原版资源，运行需自备正版（见 [NOTICE](NOTICE.md)）。

## 怎么跑

需要 Godot 4.x、Python 3（Pillow、NumPy），以及你自己的正版《幻世錄》：Steam《幻世錄 重製版》内含 1998 年經典版目录 `GAME-PAK/`。Windows 与 Linux 见 [CONTRIBUTING §6](CONTRIBUTING.md#6-windows-与-linux)。

```sh
export HSL_ORIGINAL_DIR=/path/to/GAME-PAK   # 含 hsl.pak 的正版目录，放在仓库外或 legal-assets/
tools/doctor.sh --original                  # 检查原版目录与关键文件是否在场
tools/play.sh                               # 先导入资源，再开游戏；导入失败直接报错
```

操作：左键选命令和目标，右键／Esc 取消；鼠标靠边或方向键卷动战场，Home 回到角色；对白点击或空格继续；Tab 开关「重製選項」，P 停格。跳到某一关：`tools/playtest.sh N` 装入第 N 个试玩存档格位（1–8），标题选「戰場記錄」进入。

## 你想做什么

| 想做 | 依次读 |
| --- | --- |
| **玩**：装好就玩、跳关、报问题、了解「重製選項」 | 上面「怎么跑」→ [PLAYTEST](docs/PLAYTEST.md) → [OPTIONS](docs/OPTIONS.md) → [PROJECT](docs/PROJECT.md)（现在能玩到哪、和原版还差什么） |
| **改游戏**：换素材、改规则、加关卡与角色、写续集、去掉原版依赖 | [MODDING](docs/MODDING.md) → [加关卡与角色逐步表](docs/MODDING_LEVELS.md) → [胜负脚本词表](docs/WINFAIL_TOKENS.md) → [OPTIONS](docs/OPTIONS.md) → [ARCHITECTURE](docs/ARCHITECTURE.md) |
| **贡献代码**：准备正版、门禁口径、不提交原版派生物、PR | [CONTRIBUTING](CONTRIBUTING.md) → [AGENTS](AGENTS.md)（代理的工作手册）→ [ARCHITECTURE](docs/ARCHITECTURE.md) → [测试路由](tests/README.md)／[工具说明](tools/README.md) → 证据用语 [CONTEXT](CONTEXT.md) |
| **研究原版**：资源、静态分析、运行观测与每个机制的证据等级 | [KNOWLEDGE_INDEX](docs/KNOWLEDGE_INDEX.md) → [机制矩阵](docs/MECHANICS_EVIDENCE_MATRIX.md) → [差异清单](docs/evidence_packets/static_reverse/parity_gap_inventory.md) |

全部文档的分工见 [docs/README](docs/README.md)。

## 现状

唯一的当前状态与下一步在 [docs/PROJECT.md](docs/PROJECT.md)，数字以它为准。

- 第一章 127 场战斗全部注册，剧情、城镇、大地图交接与三个结局接通，从标题「開始新故事」可一路玩到章末；续集示范关卡与两名新角色只靠写数据可玩。
- 目标是规则等价＋分布等价：敌人找谁、打谁、站哪、何时放法术的规矩与原版一样，随机选择在多种子下的比例与原版一致。原版程序在模拟器里当裁判；与原版的已知差异逐条登记在差异清单。
- 「重製選項」默认全部照原版，门禁与裁判只跑原版档。自动对局胜率低是原版难度不是回归；已合并的改动待玩家实玩验收。

## 怎么验证

```sh
python3 tools/hsl.py check --profile modder   # 改游戏的人：数据与生成物检查
tools/lane_verify.sh affected <基线提交>       # 改动中只跑命中的检查与套件
tools/verify.sh                               # 快门：全部注册表检查＋Godot 套件
tools/verify.sh --deep                        # 深门：再加剧情 explorer 与整章自动对局
```

检查由 `tools/hsl.py` 注册表按仓库数据枚举，`tools/hsl.py list` 看任务集；门禁口径见 [CONTRIBUTING §2](CONTRIBUTING.md#2-门禁口径)。自动门禁通过不代表画面与手感已和原版一致——视觉交给实玩。

## 许可

代码、工具、测试用 [MIT](LICENSE)；文档与重制配乐用 [CC BY 4.0](LICENSE-docs)。两者都不涉及原版的任何部分：《幻世錄》及其名称、角色、美术、音乐与商标归宇峻奧汀科技及相关权利人所有，本项目与权利人无关联。
