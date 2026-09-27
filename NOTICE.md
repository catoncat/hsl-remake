# NOTICE

<!-- 本声明针对公开导出树（tools/oss_export.sh 导出的树）。私有开发档案仍含原版派生物，不对外分发。 -->

## 不含原版

本仓库不含《幻世錄》（The Legend of Fancy Realm，1998）的任何原版资源、程序或其派生文件：没有可执行文件、数据包（PAK）、图像、声音、音乐（含原版 18 首曲目）、影片、剧本文本或存档，也没有由它们解码、转换、换色或截取得到的文件。原版截图与录像帧留在维护者的私有档案，公开文档里的画面换成重制版截图或文字描述。

要运行或构建本项目，玩家需自备正版：Steam《幻世錄 重製版》（app 4030150）内含 1998 年經典版目录 `GAME-PAK/`。本项目只提供从你本机这份正版导入资源的工具（路径由 `HSL_ORIGINAL_DIR` 指定，见 [CONTRIBUTING](CONTRIBUTING.md)），不提供、不链接任何原版文件的下载；`python3 tools/hsl_steam_classic.py fetch` 只打印 DepotDownloader 命令，Steam 账号由玩家本人登录。

## 权利归属

《幻世錄》及其名称、角色、美术、音乐与商标归宇峻奧汀科技（UserJoy Technology）及相关权利人所有。本项目是非官方的爱好者重制，与权利人无关联，未获其授权或认可。

## 逆向分析

`docs/` 下的逆向分析文档（静态分析、运行观测、探针结果与运行记录）是为互操作与规则复刻所做的研究成果：记录的是数值、地址、规则与结论，不含原版可执行代码。对原版名称或讯息文字的引用只到说明规则所需的长度。本项目不提供、不讨论任何破解、免 CD 或注册码类内容。

## 许可

- 代码、工具、测试：MIT，见 [LICENSE](LICENSE)。
- 文档与重制配乐（`content/generated/hsl/remake_music/`，由仓库内 `tools/compose_*.py` 合成、无第三方采样）：CC BY 4.0，见 [LICENSE-docs](LICENSE-docs)。
- 以上许可都不涉及原版的任何部分。

## 第三方

| 组件 | 用途 | 许可 |
| --- | --- | --- |
| Godot Engine 4.x | 游戏引擎（不随仓库分发） | MIT |
| Pillow | 资源导入与图像检查 | HPND |
| NumPy | 数值工具 | BSD-3-Clause |
| unicorn | 可选：原版裁判（CPU 模拟） | GPLv2（以其 COPYING 为准） |
| FFmpeg | 可选：外部调用做音视频转换 | LGPL／GPL（外部程序，不随仓库分发） |

界面字体经 `game/assets/ui_font.tres` 的 `SystemFont` 按名字引用系统字体（PingFang SC、Microsoft YaHei、Noto Sans CJK SC 等），仓库不分发字体文件。

## 关于文档截图

公开文档里的截图全部来自本重制程序的画面。画面中的人物立绘、精灵与界面美术仍是《幻世錄》的原版素材（由玩家自备的正版文件在本地导入后绘制），这里只作少量示意，不提供任何可复用的素材文件；如权利人提出要求，我们会移除相应图片。
