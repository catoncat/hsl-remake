# 参与贡献

先读 [NOTICE](NOTICE.md)：本仓库不含原版资源，也不接受原版资源。本页写给人；用代理（Claude Code、Codex 等）干活时，代理照 [AGENTS.md](AGENTS.md) 这份工作手册做。项目现状只看 [docs/PROJECT.md](docs/PROJECT.md)。

## 1. 准备正版文件

1. 购买 Steam《幻世錄 重製版》（app 4030150），取得其中的 1998 年經典版目录 `GAME-PAK/`（含 `hsl.pak`、`movie.pak`、`hsl.exe`、`music/`）。`python3 tools/hsl_steam_classic.py fetch` 会打印只下这个目录的 DepotDownloader 命令，账号由你本人登录。
2. 把这份目录放在**仓库外**任意位置，或放进仓库里的 `legal-assets/`（`.gitignore` 只放行 `legal-assets/README.md`，其余内容不会被 Git 跟踪）。
3. 设置环境变量指向它：

   ```sh
   export HSL_ORIGINAL_DIR=/path/to/GAME-PAK    # 含 hsl.pak 的目录
   ```

   Windows 与 Linux 上用 Steam 装了《幻世錄 重製版》的，可以不设：工具会在各个 Steam 库里找 `GAME-PAK/`（见 §6）。维护者做原作运行观测时另用 Wine 前缀（`WINEPREFIX`，原作在 `$WINEPREFIX/drive_c/hsl`）；普通贡献者不需要 Wine。
4. 运行 `python3 tools/hsl.py doctor`（`tools/doctor.sh` 同义），检查 Godot、Python，并报出用的是哪个原版目录、为什么选它；`--original` 另查维护者的 Wine 原作环境与采样 helper（macOS）。
5. 运行 `python3 tools/hsl.py bootstrap`，从这份目录生成游戏要用的原版派生文件（可中断、可重跑，已有的不动；`tools/play.sh`／`tools\play.ps1` 发现缺了也会先跑它）。用法、末行各字段、它生成不了的几份文件和 `doctor` 之后那条预期的 WARN 见 [MODDING §2](docs/MODDING.md#2-跑起来)。生成的文件都被 `.gitignore` 挡住，跑完 `git status` 应当是空的（§5）。
6. 不开窗口导入资源、自动打一场（Windows 换成 `tools\godot.ps1`，见 §6）：`tools/godot.sh --headless --import`，然后 `HSL_AUTOPLAY_LEVELS=51 tools/godot.sh --headless --fixed-fps 60 --script res://tests/run_autoplay_sweep_tests.gd`（玩家第 1 场 · 棄卒（LEVEL051），输出 `AUTOPLAY level=51 outcome=…`）。

注意：静态探针工具锁定的是维护者本机的 `hsl01.exe` 构建，Steam 版 `hsl.exe`（1.06）不是同一构建（[Steam 经典版证据](docs/evidence_packets/resource_inventory/steam_classic_edition.md)）。EXE 派生的规则数据以仓库里已公开的探针结果与运行记录为准，Steam 版能重建的是 PAK 派生资源。

## 2. 门禁口径

| 时机 | 命令 | 说明 |
| --- | --- | --- |
| 改动中 | `tools/lane_verify.sh affected <基线提交>` | 只跑改动命中的注册表检查、Python 测试与 Godot 套件；收尾跑一次即可 |
| 只改文档 | `python3 tools/hsl.py check docs` | 链接、索引与证据用语 |
| 合并前 | `tools/verify.sh` | 快门：全部检查＋Godot 套件，热导入缓存 |
| 阶段收口 | `tools/verify.sh --full`／`--deep` | 冷导入／加跑剧情 explorer 与整章自动对局 |

没有原版文件时，读原版的检查应当显式跳过并标明原因，不能静默通过；公开 CI（`.github/workflows/portability.yml`，Windows／Linux／macOS）就按这个口径跑 doctor、`hsl check --all` 与 Python 单测。`hsl check --all` 等于 `--profile=maintainer`，改动涉及原版等价或证据流程时以它为准；只动自己游戏数据时可先跑 `--profile=modder`（它会打印一行被跳过的 parity／maintainer 任务数）。测试只在两种情形下写：守住一条已照原版落地的规则，或复现一个真实回归（[AGENTS 测试政策](AGENTS.md)）。

## 3. 证据与用语

- 每条"像原版"的声明都要能追溯到资源、静态分析或原作运行观测；用语（resource-derived、static-derived、runtime-measured、provisional、remake-invented 等）见 [CONTEXT](CONTEXT.md)。
- 原版语义未知时标 provisional 并写明可替换的证据，不为推进而编造等价。
- `game/` 模块头部的来源字段由 `hsl check provenance` 强制，汇总在 [PROVENANCE](docs/PROVENANCE.md)。
- 截图、录像帧不进公开仓库；需要画面时用重制版截图（`python3 tools/oss_screenshots.py`），原版帧只写文字描述并注明"原版帧见私有档案"。

## 4. 提交与 PR

- 一个 PR 做一件事：开头写清玩家能看到什么变化、改了哪些文件、怎么验收；和原版有关的改动附证据（§3）。
- 提交说明写清"为什么"，每个可独立验证的步骤单独提交；附上 §2 门禁的结果行原样（例如 `LANE_AFFECTED_PASS …`）。
- 只改和这件事有关的文件；顺手发现的问题另开 issue 或 PR。
- 测试按 [AGENTS 测试政策](AGENTS.md)：只在守住原版事实或复现真实回归时写。

## 5. 不提交原版派生物

`.gitignore` 挡住 bootstrap 写出的全部原版派生文件：`content/` 生成层、写进 `content/authored/actors/` 的示范角色换色图，以及原版派生文件清单里 `content/` 之外的每一条（`docs/evidence_packets/` 下的原版录像帧与记录）。提交前（`git add` 之后）再跑一次：

```sh
python3 tools/hsl.py check oss_guard
```

它把 `git ls-files` 与 `git status` 里未被忽略的文件逐条对照清单（`content/generated/hsl/original_derived_manifest.json`），另查 `content/imported|generated|battles/`、原版容器与音视频后缀（`content/authored/` 除外）和 `legal-assets/` 等存放原版的目录，其余图片、音视频按内容比对（像素或字节与清单某条相同即算，纯色图除外，改名挪到 `docs/`、`content/authored/` 也拦）；任何一条被跟踪或未被忽略就 FAIL 并列出路径，按提示 `git rm --cached` 或补忽略规则。重制配乐 `content/generated/hsl/remake_music/` 不算原版派生；从原版程序读出的五份规则数据（`hsltools.original_content.PUBLISHED_EXE_DATA`，见 [NOTICE](NOTICE.md)）是公开发布的例外（C 类，清单仍记哈希）。两者改了都照常提交。截图同理——原版截图、录像帧、原版帧换色图都不提交。公开 CI 每次推送也跑这条检查。再用 [gitleaks](https://github.com/gitleaks/gitleaks) 扫一次密钥：`gitleaks protect --staged`。

## 6. Windows 与 Linux

- **不需要 bash 的入口**：`python tools\hsl.py doctor|check|generate`、`python tools\verify_runner.py python-tests`；玩和跑 Godot 用 PowerShell：`powershell -ExecutionPolicy Bypass -File tools\play.ps1`、`tools\godot.ps1 --headless --import`。`play.ps1` 在缺原版派生文件时先跑 `hsl.py bootstrap`，在缺 `.godot\imported` 或 bootstrap 生成了新文件时先导入；生成了新图片／声音后设 `$env:HSL_FORCE_IMPORT=1` 再跑一次。PowerShell 会吞掉裸 `--`，给 Godot 的用户参数写在 `++` 后面。
- **Godot**：装 4.7，`godot` 在 PATH 上，或设 `GODOT_BIN` 指向 `Godot_v4.7.x-stable_win64_console.exe`（console 版才会把输出打到终端）。
- **Python**：3.10 以上，依赖装进虚拟环境：`python -m venv .venv`，激活（Windows `.venv\Scripts\Activate.ps1`，macOS／Linux `. .venv/bin/activate`）后 `pip install -r requirements-dev.txt`；Homebrew、Debian 等的系统 Python 不允许全局安装。`hsl.py`、`verify_runner.py` 在 Windows 自动进 UTF-8 模式；直接跑别的 `tools\*.py` 时先设 `$env:PYTHONUTF8=1`。
- **原版目录**：`HSL_ORIGINAL_DIR` 未设时，Windows 读注册表 `HKCU\Software\Valve\Steam\SteamPath` 并试 C:–F: 常见 Steam 目录，Linux 查 `~/.local/share/Steam`、`~/.steam`、Flatpak Steam；每个 Steam 库按 app 4030150 的 `installdir` 找 `GAME-PAK/`。`doctor` 会打印找到的目录或查过的库。
- **符号链接**：选中的包不叫 `hsl.pak`（Steam 目录默认选 `hsl-cn.pak`）时，工具在 `ignored\original-view\hsl\` 建视图；没有符号链接权限时自动改用 junction／硬链接（跨盘则复制）。
- **仍要 bash 的**：`tools/verify.sh`、`tools/lane_verify.sh`、`tools/lane_merge.sh` 等维护者门禁（Git Bash 或 WSL 下跑），以及只在 macOS 上有意义的原作采样（`hsl_capture.sh`、Swift helper）。
- **换行与大小写**：`.gitattributes` 统一 LF，不要用 `core.autocrlf` 覆盖；新增文件名不要只靠大小写区分（`hsl check case_collisions` 会拦）。
- 这些入口还没有 Windows 真机验证，遇到问题请附 `python tools\hsl.py doctor` 的输出。
