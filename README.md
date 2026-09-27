# 幻世錄 重制版

用 Godot 4 重写的《幻世錄》（The Legend of Fancy Realm，1998）第一章。规则照原版程序逐项对齐：伤害、命中、敌人找谁打谁站哪、随机结果的分布，都拿原版程序在模拟器里当裁判验过；画面和演出照原版录像复刻。做它是为了让人能在这套引擎上改出自己的游戏——换素材、改数值、加关卡和角色，或者写一部续集。

仓库不含任何原版资源。运行需要你自己的正版《幻世錄》数据：Steam《幻世錄 重製版》自带 1998 年經典版目录 `GAME-PAK/`。

![标题画面](docs/screenshots/remake/title-framed.png)

## 现状

- 第一章 127 场战斗、剧情、城镇、大地图与三个结局全部接通，从标题可以一路玩到章末。
- 规则层与原版对拍：开局盘面全字段一致，敌方回合逐帧一致，AI 行动频率在多种子下没有可确证的差异。剩余差异逐条记在[差异清单](docs/evidence_packets/static_reverse/parity_gap_inventory.md)。
- 「重製選項」默认全部照原版，另有少量可选的体验改良（游戏内按 Tab）。
- 还没有经过完整的人工通关验收。机器人自动对局胜率低是原版难度，不是回归。

## 运行

需要 Godot 4.x 和 Python 3（Pillow、NumPy）。

```sh
export HSL_ORIGINAL_DIR=/path/to/GAME-PAK
tools/doctor.sh --original
tools/play.sh
```

第一次运行会从原版数据导入素材，之后直接开游戏。Windows 与 Linux 见 [CONTRIBUTING](CONTRIBUTING.md#6-windows-与-linux)。

## 文档

- [PLAYTEST](docs/PLAYTEST.md) — 跳到某一关试玩、回报问题
- [OPTIONS](docs/OPTIONS.md) — 重製選項各项与默认值
- [MODDING](docs/MODDING.md) — 换素材、改规则、去掉原版依赖
- [MODDING_LEVELS](docs/MODDING_LEVELS.md) — 加关卡、角色、职业、招式，写续集
- [WINFAIL_TOKENS](docs/WINFAIL_TOKENS.md) — 胜负脚本词表
- [ARCHITECTURE](docs/ARCHITECTURE.md) — 代码分层与模块地图
- [CONTRIBUTING](CONTRIBUTING.md) — 开发环境、测试、提交规范
- [证据包](docs/evidence_packets/README.md) — 原版逆向与实测记录，每个机制的证据等级
- [PROJECT](docs/PROJECT.md) — 当前进度与排队事项

## 许可

代码 [MIT](LICENSE)，文档与重制配乐 [CC BY 4.0](LICENSE-docs)。《幻世錄》及其名称、角色、美术、音乐归宇峻奧汀科技及相关权利人所有；本项目与权利人无关，不包含也不分发任何原版资源（见 [NOTICE](NOTICE.md)）。
