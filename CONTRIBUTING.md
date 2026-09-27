# 参与贡献

先读 [NOTICE](NOTICE.md)：本仓库不含原版资源，也不接受原版资源。工作规则以 [AGENTS.md](AGENTS.md) 为准，项目现状只看 [docs/PROJECT.md](docs/PROJECT.md)。

## 1. 准备正版文件

1. 购买 Steam《幻世錄 重製版》（app 4030150），取得其中的 1998 年經典版目录 `GAME-PAK/`（含 `hsl.pak`、`movie.pak`、`hsl.exe`、`music/`）。`python3 tools/hsl_steam_classic.py fetch` 会打印只下这个目录的 DepotDownloader 命令，账号由你本人登录。
2. 把这份目录放在**仓库外**任意位置，或放进仓库里的 `legal-assets/`（`.gitignore` 只放行 `legal-assets/README.md`，其余内容不会被 Git 跟踪）。
3. 设置环境变量指向它：

   ```sh
   export HSL_ORIGINAL_DIR=/path/to/GAME-PAK    # 含 hsl.pak 的目录
   ```

   维护者做原作运行观测时另用 Wine 前缀（`WINEPREFIX`，原作在 `$WINEPREFIX/drive_c/hsl`）；普通贡献者不需要 Wine。
4. 运行 `tools/doctor.sh --original`，检查 Godot、Python、原版路径与 PAK 哈希。

注意：静态探针工具锁定的是维护者本机的 `hsl01.exe` 构建，Steam 版 `hsl.exe`（1.06）不是同一构建（[Steam 经典版证据](docs/evidence_packets/resource_inventory/steam_classic_edition.md)）。EXE 派生的规则数据以仓库里已公开的探针结果与运行记录为准，Steam 版能重建的是 PAK 派生资源。

## 2. 门禁口径

| 时机 | 命令 | 说明 |
| --- | --- | --- |
| 改动中 | `tools/lane_verify.sh affected <基线提交>` | 只跑改动命中的注册表检查、Python 测试与 Godot 套件；收尾跑一次即可 |
| 只改文档 | `python3 tools/hsl.py check docs` | 链接、索引与证据用语 |
| 合并前 | `tools/verify.sh` | 快门：全部检查＋Godot 套件，热导入缓存 |
| 阶段收口 | `tools/verify.sh --full`／`--deep` | 冷导入／加跑剧情 explorer 与整章自动对局 |

没有原版文件时，读原版的检查应当显式跳过并标明原因，不能静默通过（公开 CI 档仍在建设，见 [开源计划 §3](docs/OPEN_SOURCE_PLAN.md)）。测试只在两种情形下写：守住一条已照原版落地的规则，或复现一个真实回归（[AGENTS 测试政策](AGENTS.md)）。

## 3. 证据与用语

- 每条"像原版"的声明都要能追溯到资源、静态分析或原作运行观测；用语（resource-derived、static-derived、runtime-measured、provisional、remake-invented 等）见 [CONTEXT](CONTEXT.md)。
- 原版语义未知时标 provisional 并写明可替换的证据，不为推进而编造等价。
- `game/` 模块头部的来源字段由 `hsl check provenance` 强制，汇总在 [PROVENANCE](docs/PROVENANCE.md)。
- 截图、录像帧不进公开仓库；需要画面时用重制版截图（`python3 tools/oss_screenshots.py`），原版帧只写文字描述并注明"原版帧见私有档案"。

## 4. 协作（lane）规则要点

- 一项任务一条 lane，在独立 git worktree 里做；先写明玩家结果、写集（负责的文件）与验收条件，写集以外的文件不动。
- 任务书与报告按 [lane 任务书模板](docs/templates/lane_brief.md)：报告写提交号、验收结果行原样、边界与时间账。
- 每步单独提交，提交说明用中文写清"为什么"；不 push，不 destructive reset，不改他人正在认领的文件。
- 开工记 `date`，每步记起止时间；门禁只在收尾跑一次。

## 5. 不提交原版派生物

提交前确认暂存区里没有原版文件或由它们生成的东西：

```sh
git diff --cached --name-only --diff-filter=AM \
  | grep -E '^(content/(imported|generated|battles)/|legal-assets/.|original-assets/|asset-dumps/.)|\.(pak|exe|dll|sav|shp|wav|mov|mp4|avi|bik)$' \
  | grep -v -e '^legal-assets/README.md$' -e '^asset-dumps/README.md$' -e '^content/generated/hsl/remake_music/'
```

有输出就停下核对：`content/` 生成层由本地导入产生，不入公开仓库；重制配乐 `content/generated/hsl/remake_music/` 例外。截图同理——原版截图、录像帧、原版帧换色图都不提交。再用 [gitleaks](https://github.com/gitleaks/gitleaks) 扫一次密钥：`gitleaks protect --staged`。
