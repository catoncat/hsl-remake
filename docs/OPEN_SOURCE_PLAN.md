# 开源计划（OSSAUDIT，2026-09-26）

> 只读审计结果＋执行清单。基线 `pipeline-line` 62ad42f6（含 main db53fa45）。统计全部可复跑：`python3 tools/oss_audit_stats.py [REF] [--migration]`（[脚本](../tools/oss_audit_stats.py)，只读 `git ls-tree` 与注册表，不碰原版）。本文不是法律意见；商标／版权判断以用户或律师为准。

## 0. 结论

- **硬门槛成立**：tracked 21,209 个文件、789 MB（blob 字节），其中 **A 类（原版派生）19,297 个、732 MB，占 93%**，公开即分发原版资源。
- **A 类里 90% 的文件能由现有生成器从原版重建**；不能重建的主要是**原版运行截图／录像 868 个、397 MB**（证据包里，最大头），以及约 980 个"由非注册表脚本写出、未声明为输出"的文件（约 21 MB，补声明即可）和 73 个换色占位美术。
- **推荐方案甲**：新开公开仓库，只放 B＋处理后的 C，历史从零；现私有仓库原样保留为开发档案。理由见 §3。
- **要先定的一件事**：Steam 版的 `hsl.exe`（1.06）和我们锁定哈希的本机 `hsl01.exe` **不是同一个构建**（[Steam 经典版证据](evidence_packets/resource_inventory/steam_classic_edition.md)）。公开贡献者按 Steam 版能重建 PAK 派生资源，**但重建不了 EXE 派生的数据**（95 个工具文件锁定了 `hsl01.exe`）。所以 C 类里 EXE 探针结果（数值事实）公开与否，决定了公众能不能构建出可玩版本（§2.3、§7）。

## 1. 分类清单

口径：A＝原版派生，必须剥离；B＝重制自创；C＝灰区，逐项处理后才能公开。数字来自 `python3 tools/oss_audit_stats.py`（62ad42f6）；"生成器覆盖"是注册表任务（`tools/hsl.py`）声明的输出能覆盖的比例，§2 详述。

| 类别 | 子类 | 文件数 | MB | 生成器覆盖 |
| --- | --- | ---: | ---: | --- |
| A | 证据包里的原版截图／录像／渲染（png 835、jpg 21、mp4 13 等） | 870 | 397.4 | 2/870（0% MB） |
| A | `content/imported` 解码媒体（png 15,692、wav 476、原曲 ogg 18、片头片尾 webp 7） | 16,193 | 255.3 | 15,276/16,193（93% MB） |
| A | `content/imported` 原版文本／源码／JSON（STORY*.TXT、.H、PLAYERS.TXT、脚本 IR、剧情语料） | 1,518 | 35.2 | 1,483/1,518（93% MB） |
| A | `content/generated` 数据表（EXE／PAK 派生，含 `static/hsl01` 92 个 7.1 MB） | 419 | 24.8 | 389/419（90% MB） |
| A | `content/battles` 组装后的关卡数据（含原版对白） | 210 | 18.4 | 210/210（100%） |
| A | `content/authored/actors/102·103` 占位美术（**原版 003 号帧换色**，见其 `art.json`） | 73 | 0.9 | 0/73 |
| A | 原版存档与内存转储（`.SAV` 11、`PLAYERS_templates_runtime.bin` 1） | 12 | 0.1 | 9/12（只能从用户自己的存档复制） |
| A | 混在 A 目录里的手写 README（`content/imported/hsl`、`global`、`chapter01/source_texts`；`content/generated/hsl` 等） | 6 | 0.0 | 1/6 |
| B | `tools/`（含重制配乐合成器 `compose_*.py`） | 453 | 5.0 | — |
| B | `tests/` | 412 | 3.8 | — |
| B | `game/`（含 `.gd.uid`、`.tscn`、SystemFont 资源与自绘 `icon.svg`） | 383 | 2.1 | — |
| B | 重制配乐 `content/generated/hsl/remake_music`（14 首＋README，合成器生成，无第三方采样） | 15 | 9.1 | — |
| B | 文档、根文件、续作角色表、schema | 56 | 1.6 | — |
| B | `content/battles/levels/*.json`＋`campaign.json`（手写关卡档案） | 74 | 0.4 | — |
| B | 重制自动对局结果 | 4 | 0.1 | — |
| C | 证据包数据（运行 receipt、探针 packet、资源清单等 json／tsv／txt） | 211 | 32.0 | — |
| C | 证据包正文 md（可能引原版字串） | 269 | 2.3 | — |
| C | `docs/external/typesafe`（第三方文档镜像） | 35 | 0.5 | — |
| **合计** | | **21,209** | **789.0** | A 类整体：原版直读 16,928 ＋ 二次生成 442＝17,370/19,297 |

复核负责人数字（差异都是基线／口径不同，不是矛盾）：

- 文件数 21,164 → 21,209（基线前进）；包 656 MB → 本机 `git count-objects` 679 MiB（含所有分支）。
- `content/imported` 369 MB → **290.6 MB blob 字节**（369 应是 `du` 块占用），17,714 个文件。
- 原版存档不是 4 份，是 **11 份 `.SAV`**（`content/generated/hsl/development/original_saves` 9 份＋证据包 2 份）＋1 个 `.bin`。
- `static/hsl01` 92 个 7.1 MB ✓；原曲 18 首在 `content/imported/hsl/music` ✓。
- 原版来源实际是仓库外的 Wine 前缀（`hsltools.paths.ORIGINAL_ROOT`，可用 `WINEPREFIX` 覆盖）和 Steam 经典版目录（`HSL_STEAM_CLASSIC`）；`legal-assets/` 只有一份说明文件。
- 历史：2,129 个提交；**从没提交过 PAK／EXE**；历史里另有约 857 个 HEAD 已删的路径（`content/imported` 236、证据包 239、早期 `content/reference/first_battle/from_video_min1/*.png` 视频截帧等）——方案乙必须把它们也洗掉。

C 类里的具体风险（按量排）：

- **运行 receipt／探针 packet（211 个 32 MB）**：数值与地址为主，但含原版角色名、物品名、消息号。最大的是 `tactical_items/receipt.json` 3.5 MB、`original_campaign_actors.json` 2.3 MB（整张演员表的派生，接近 A）。
- **证据正文（269 个）**：整段反汇编极少（全仓只有 2 个文件共 10 行类汇编行：`original_skill_function_bits.md`、`original_special_element.md`）；主要风险是引用原版对白、脚本行和字形审读描述，需按"短引用"标准过一遍。
- **代码里的原版字节**：`tools/hsltools/evidence/action_state.py`、`give.py` 内嵌 5 段 70–80 字节的 `hsl01.exe` 机器码签名，用来确认 EXE 版本；风险低，可改为只存这段字节的 SHA-256。
- **`docs/external/typesafe`**：第三方文档镜像，无授权，公开仓库只留我们自己写的 `README.md`。

## 2. 可再生性

### 2.1 方法

每个注册表任务按类型判定：`PacketTask`、覆写了 `build` 的 `ScriptCheckTask`、自带 `generate` 的普通 `Task` 算"原版直读"（读 PAK／EXE／Steam 目录）；`GeneratedFilesTask` 算"二次生成"（由其他 tracked 输入渲染）；声明了 `*manifest*.json` 的导入器视为也拥有同目录的帧／音频。A 文件被这些任务的输出覆盖才算可再生。这是**声明层面**的覆盖，没有从空目录实跑过（§6 第 3 步补这一步）。

### 2.2 不可再生 → 迁移清单（1,931 个、419.9 MB）

| 组 | 文件数 | MB | 处置 |
| --- | ---: | ---: | --- |
| 证据包原版截图／录像（868） | 868 | 397.3 | **迁出**：私有证据档案（私有仓库或本机 bundle），公开文档里的图片链接改成文字描述＋档案编号 |
| `shared/shape_previews`（`tools/hsl_payload_inspector.py` 写出） | 292 | 10.9 | 注册成任务，或确认只是审读用而不进公开构建 |
| `battleNNN/actor_audio/*.wav`（`level_actors` 写在 `actor_audio.json` 旁，未声明） | 246 | 3.6 | 补进 `level_actors` 的 outputs |
| `shared/actor_walk_frames`（转职走行帧，`hsl_actor_walk_manifest.py`／job casts） | 331 | 1.9 | 注册成任务 |
| `static/hsl01` 中 16 个（`core_logic.json` 等，`hsl_exe_static_export.py`＋手工拷入） | 16 | 2.2 | 注册成任务；**只能从 `hsl01.exe` 重建**（§2.3） |
| `chapter01` 杂项 JSON（`audio_normalized.json` 等 17） | 17 | 1.8 | 注册成任务 |
| `content/authored/actors` 占位美术（原版帧换色） | 73 | 0.9 | 改成生成器：从导入的 003 号帧按 `art.json` 换色（色相 +180°）；或换真原创美术 |
| `section_title.png`（`levels/message_text` 写出，未声明） | 49 | 0.7 | 补进 `message_text_evidence_check` 的 outputs |
| `global/tables` `.H`／`.TXT`（`story_token_coverage` 等提升） | 17 | 0.3 | 补声明 |
| 证据包 `original_save_format` 的 2 份 `.SAV`＋1 份 `.bin` | 3 | 0.0 | 迁出到私有证据档案 |
| `content/generated/hsl/chapter01`、`static` 杂项 | 10 | 0.0 | 逐个补声明 |
| 手写 README（5） | 5 | 0.0 | 挪到 `docs/`（B），说明各层是什么、怎么生成 |

另：`content/generated/hsl/development/original_saves` 的 9 份 `.SAV` 虽有任务，但任务是**从用户自己打出来的存档复制**，新装的原版没有这些档——同样迁到私有档案；依赖它们的存档格式检查改成"本地有才跑"。

**截图替换（OSS2，用户 09-27 定：原版帧迁私有档案，文档图换重制画面）**：`python3 tools/oss_screenshots.py summary` 按链接分四类（`list --tsv` 出逐条清单）。当前 84 份 md 里 650 个媒体链接：

| 类 | 链接 | 处置 | 状态 |
| --- | ---: | --- | --- |
| remake（包头有 `tests/*.gd` 驱动或自述重制窗口化运行） | 530 | 保留，已是重制画面 | — |
| original-scene（原版画面状态，重制也有） | 67 | 用 `driver` 列的现有 capture 脚本补拍，`apply` 复制到 `docs/screenshots/remake/` 并改链接，原版帧只留文字 id（"原版帧见私有档案：`…`"） | 样板 9 张换掉 16 处；**待办 51 处**（多数在 `original_gameplay_reference` 03／06–11／15–18、`original_world_town` 03–17、`menus_ui`，`battle_0NN/original_*` 可直接改指同包重制图） |
| original-measure（接触表、逐帧动画序列、录像对照） | 47 | 公开文档改文字描述＋"原版帧见私有档案"，导出时变换 | 待办 |
| original-resource（原版影片帧、SHP 预览） | 6 | 同上；玩家可用自己的正版在本地重渲染 | 待办 |

改链接后相邻句子仍按原版帧描述（如"原录像…压缩样本"），全量替换时要逐句改写成重制画面的说法；`capture_town_review`、`capture_status_review`、`capture_battle_reward_review` 在 `pipeline-line` 4d4ecfa3 上跑失败（`capture_world_map_review` 前 6 张可用），补拍城镇／状态页前要先修驱动。

### 2.3 公众只有 Steam 版时能重建什么

| 来源 | Steam 版有没有 | 影响 |
| --- | --- | --- |
| `hsl.pak` 资源 | Steam `hsl-cn.pak` 与本机 `hsl.pak` 5,600 个成员中 5,599 个相同；差的 `shape\mark0100.shp` 仓库里没人用 | PAK 导入可行；但 `ORIGINAL_PAK` 固定读 `hsl.pak`，Steam 默认 `hsl.pak` 是另一套数据——需加 `HSL_ORIGINAL_PAK` 覆盖或在文档里要求指向 `hsl-cn.pak` |
| `movie.pak` | 逐字节相同 | 片头片尾可重建 |
| `music\NN.wav` | 只有 Steam 版有 | 原曲可重建（`music_import`） |
| `hsl01.exe`（EXE 探针、静态导出） | **没有**；Steam 是 `hsl.exe` 1.06，不同构建 | 探针 packet 与 `static/hsl01` 公众重建不了。若 C 类探针 packet（数值事实）随公开仓库发布，二次生成的 `content/generated` 表仍可由 PAK＋packet 重建；否则公众构建缺规则数据 |

## 3. 方案对比

**甲：新仓库只放 B（＋处理后的 C），历史从零。**
工作量：导出脚本（白名单复制）＋门禁拆分，约 1–1.5 天，和 §6 第 2–5 步基本相同；导出本身 1 小时。风险：低——新仓库里没有任何旧对象，不存在"漏洗一个历史路径"或"GitHub 仍按旧 SHA 能访问被删对象"的问题；作者邮箱 `<author e-mail>` 这类历史元数据也不会带出去。代价：公开仓库没有 2,129 个提交的历史与 blame（私有仓库保留，考古照旧）。对门禁：公开仓库里所有依赖原版的检查一开始就必须能"原版缺席时跳过"，第一天就逼出干净的公开门禁。

**乙：`git filter-repo` 重写现仓库历史剥离 A。**
工作量：要列全历史上所有 A 路径（含 857 个已删路径和改名）、C 类文件在历史中的每个未处理版本（改过的证据正文，旧版本仍含原文引用），重写 2,129 个提交后逐提交复核；再加与甲相同的门禁拆分。约 2–3 天，且复核很难做到完备。风险：高——漏一个路径就是公开分发；重写后在同一 GitHub 仓库强推，旧对象在 GitHub 端不会立即消失（PR 引用、缓存），需另开仓库或联系支持清理，那等于回到甲；所有现有工作树、`pipeline-line`／`presentation-line` 与在飞 lane 全部要重新克隆，打断并行开发。对门禁：同甲，外加历史里的每个提交都不再能复跑原门禁（生成物被删）。

**推荐甲。** 乙的唯一收益是保留公开历史，但这段历史本身就混着原版资源与未处理的引用，洗干净的成本和风险都高于它的价值；甲可与开发并行，私有仓库继续当开发主干和证据档案，公开仓库按发布节奏单向导出。

### 3.1 门禁要改的地方（"本地有原版才跑"）

| 检查 | 现状依赖 | 改法 |
| --- | --- | --- |
| `hsl check --all`（1,427 个任务） | **1,411 个**任务的 inputs／outputs 落在 `content/imported`／`generated`／`battles` | 按内容是否在场分两档：原版缺席时这些任务报 `SKIP original-absent`（不是 PASS，也不是静默跳过——与 AGENTS"必要输入缺失应明确失败"一致，公开 CI 显式声明这一档） |
| 生成物逐字节比对（PNG／WAV 哈希、988 个带 `sha256` 的导入 manifest） | 比对 tracked 输出 | 公开仓库 tracked 一份**只含路径＋SHA-256** 的 `content/MANIFEST.sha256`（哈希不是原版内容）；本地导入后比对这份清单 |
| `hsl check provenance` | `game/*.gd` 头部 162 行 provenance 引用 A 路径，检查文件存在 | 改为在清单里查路径 |
| `tools/hsl_docs_check.py` | 20 个 md 里 229 个链接指向 `content/`；84 个 md 里 647 个链接指向截图／录像 | `content/` 链接按清单解析；截图链接在导出时改写为文字＋档案编号 |
| Godot 套件 | 204 个测试脚本中 128 个、182 个 game 模块中 90 个读 A 路径 | 套件打"需原版"标记；公开 CI 只跑其余 76 个脚本 |
| Python 工具测试 | 139 个中 39 个读 A 路径 | 同上，`skipUnless(content present)` |
| `tools/verify.sh` 128 场自动对局 | 需 `content/battles` | 只在本地有原版时跑 |

## 4. 合规文件

**LICENSE（建议 MIT，代码／工具／测试）。** 依据：Godot 本体 MIT，生态惯例一致；工具可选依赖 unicorn 是 GPLv2（以其 COPYING 为准），MIT 代码调用它没有兼容问题，而 GPL-3 与 GPLv2-only 组件组合发布不兼容；项目价值在"让正版玩家自己构建"，GPL 的传染性在这里拦不住任何实际风险（没有原版资源谁也发不出可玩成品），反而增加权利人或其他移植合作的顾虑。若用户更看重"衍生版必须开源"，选 GPL-3.0-or-later 也可，但要先确认 unicorn 的许可版本。

**重制配乐与文档：CC BY 4.0。** 14 首重制曲由仓库里的 `tools/compose_*.py`（MIT）合成，README 已声明无第三方采样／旋律；音频用 CC BY 4.0 更符合惯例，文档散文同。用 [REUSE](https://reuse.software) 风格的一份路径→许可映射写清：`game/ tools/ tests/` MIT，`content/generated/hsl/remake_music/` 与 `docs/` CC BY 4.0，C 类保留文件单独标注"含原版短引用，按合理使用"。

**NOTICE 要点：**
- 本仓库不含《幻世錄》的程序、数据包、图像、声音、音乐、影片或文本；构建需要玩家自备正版。
- 《幻世錄》及其名称、角色、商标归奧汀科技（Odin）／宇峻奧汀（UserJoy）所有；本项目是非官方爱好者重制，与权利人无关联、未获授权或认可。
- 正版来源：Steam《幻世錄 重製版》（app 4030150）内含 1998 年经典版目录 `GAME-PAK/`；`python3 tools/hsl_steam_classic.py fetch` 只打印 DepotDownloader 命令，账号由玩家本人登录；本项目不提供任何下载。
- 逆向分析只用于互操作与规则复刻，仓库不含原版可执行代码，不提供、不讨论破解（已扫：全仓无 crack／免 CD／注册码类内容）。
- 第三方：Godot（MIT）、Pillow（HPND）、NumPy（BSD）、unicorn（GPLv2，可选）、FFmpeg（外部调用）。界面字体是 `SystemFont` 按名字引用系统字体（`game/assets/ui_font.tres`：PingFang SC、Microsoft YaHei、Noto Sans CJK SC 等），**不分发字体文件，无字体许可问题**。

**README 重写提纲**（现首段仍写"第一章第一战"，已过期）：
1. 一句话：《幻世錄》（1998）非官方 Godot 4 重制，规则按原版证据复刻；本仓库不含原版资源。
2. 现状：可玩范围（以 `docs/PROJECT.md` 为准，不在 README 写死数字）、截图用重制画面（导出时替换）。
3. 快速开始：买 Steam 版 → 取经典版目录 → `tools/doctor.sh --original` → 一条导入命令（§6 第 3 步新增）→ `tools/play.sh`。
4. 仓库结构：`game/`、`tools/`、`tests/`、`docs/`；`content/` 是本地生成、gitignore。
5. 证据方法：resource-derived／static-derived／runtime-measured 等用语一段，链到 `CONTEXT.md`。
6. 许可与 NOTICE；免责声明。

**CONTRIBUTING 提纲：**
1. 准备正版：Steam 经典版目录放在仓库外（`HSL_STEAM_CLASSIC`），或 Wine 前缀（`WINEPREFIX`）；**不要把任何原版文件或其派生物提交进仓库**（`.gitignore` 已拦 `legal-assets/`、`original-assets/`、`content/` 生成层）。
2. `tools/doctor.sh --original` 检查 Godot、Python、原版路径与 PAK 哈希；导入后比对 `content/MANIFEST.sha256`。
3. 开发门禁：公开 CI 档（无原版）与本地完整档（有原版）各跑什么。
4. 证据用语与 provenance 头部规则（链到 `AGENTS.md` 相应节）；截图不进公开仓库，只写描述。
5. 提交前运行密钥扫描（§5 的正则或 gitleaks）。

## 5. 清理项

| 项 | 现状（已核） | 处理 |
| --- | --- | --- |
| 个人路径（用户主目录绝对路径） | 10 个文件 11 行（`docs/collaboration/presentation.md`、8 个证据正文、`ohm_village/receipt.json`） | **OSS2 已改**：录屏写文件名＋"私有档案"，其余改 `~`／`ignored/` 相对路径 |
| Wine 前缀措辞 | 73 个文件写 Wine 前缀的固定目录名，168 个文件提到 Wine | **OSS2 已改**（`docs/`、`AGENTS.md`、`CONTEXT.md`、`legal-assets/README.md`）：原版文件路径写 `$HSL_ORIGINAL_DIR`，Wine 前缀写 `$WINEPREFIX`；`tools/` 代码里的默认值（`hsltools.paths` 等 10 个文件）归 OSS1。控制原版的工具（`hsl_original_control`、`run_original_hsl.sh`）标为维护者研究工具 |
| `CONTEXT.md` 关键词误报 | 敏感词只命中"序号"（索引，非序列号）与证据表里的"token"（脚本令牌）；无密钥、无破解内容 | 误报，无需改；提到的 `record.mp4` 是用户录像，已按 A 类随证据媒体迁出 |
| `game/assets/ui_font.tres` | `SystemFont`，只写字体名 | 无许可问题（§4） |
| 密钥 | 当前树 `git grep`：只有占位 `TYPESAFE_API_KEY="your-key-here"`；全历史 20,845 个唯一文本 blob 用 AWS／GitHub（ghp_、github_pat_）／Anthropic／OpenAI／Slack／Google API key／私钥头／`api_key=…` 正则扫描 **0 命中**；本机无 trufflehog／gitleaks | 方案甲下历史不外带；导出前用 gitleaks 再扫一次导出树 |
| 作者邮箱 | 历史里 `cat <<author e-mail>>` 4,040 次、`<本机用户名> <<author e-mail>>` 218 次 | 方案甲不外带；公开仓库用固定署名 |
| 内部协作文档 | `PARALLEL_WORK.md`、`docs/collaboration/`（0.35 MB）、`docs/LANE_TIMELOG.md`、`CLAUDE.md` 是内部接力记录 | 不导出，或导出精简版 AGENTS |
| 第三方文档镜像 | `docs/external/typesafe` 34 个镜像页 | **OSS2 已删**：只留项目自己写的 `README.md`（镜像页链接改指 docs.typesafe.ai，私人工具路径与密钥句柄已去掉）；`tools/hsltools/typesafe.py` 报错文案里的密钥工具名归 OSS1 |
| 代码内嵌 EXE 字节 | `action_state.py`、`give.py` 5 段签名 | 改存 SHA-256（可选） |

## 6. 建议时序（与开发并行）

| 步 | 内容 | 在哪做 | 预计 | 与开发的关系 |
| --- | --- | --- | --- | --- |
| 0 | 用户拍板 §7 四件事 | — | 0.5 h | 阻塞第 5、6 步 |
| 1 | 写 LICENSE／NOTICE／README／CONTRIBUTING 草稿 | 私有仓库，纯文档 | 1–2 h | 可随时插入，不碰规则 |
| 2 | 补生成器声明：§2.2 表里约 980 个"脚本写出、未声明"的文件注册成任务；占位美术改成换色生成器 | 私有仓库，tools/ | 4–6 h | 只碰 tools 与生成物声明，按函数认领，不冻结功能 lane |
| 3 | 从空目录自举：新增一条"从原版生成全部 content"的命令，空 `content/` 下实跑并与现 tracked 逐哈希比对；产出 `content/MANIFEST.sha256`；`HSL_ORIGINAL_PAK` 覆盖以支持 Steam `hsl-cn.pak` | 独立工作树 | 4–8 h | 只读原版，结果不改现有生成物 |
| 4 | 门禁分档：§3.1 表逐项实现（SKIP original-absent、清单解析链接与 provenance、测试打标记） | 私有仓库 | 3–5 h | 碰 verify 工具，按 AGENTS 走完整门禁一次 |
| 5 | C 类审读：证据正文短引用标准、receipt／packet 去留（取决于 §7-2）、个人路径、Wine 措辞、截图链接改写规则 | 导出脚本里做变换，不改私有仓库原文 | 2–4 h | 不影响开发 |
| 6 | 导出脚本（白名单＋变换），在无原版的干净克隆上跑公开门禁、gitleaks | 新目录 | 1–2 h | — |
| 7 | 建公开仓库、推送、设 license 字段与说明；私有仓库保持 private 作档案 | GitHub（用户授权后） | 0.5 h | — |

合计约 15–28 小时；第 1、2、5 步可交给不同 lane 并行，第 3 步是最大的不确定项（生成链从没在空目录跑过）。

## 7. 需要用户拍板

1. **方案**：甲（新仓库、历史从零，推荐）还是乙。
2. **C 类探针 packet 与运行 receipt 是否公开**：公开则 Steam 玩家能重建规则数据；不公开则公众构建缺 EXE 派生部分，除非把静态工具移植到 Steam `hsl.exe` 1.06（未评估，工作量大）。
3. **许可**：代码 MIT（推荐）或 GPL-3.0-or-later；重制配乐与文档 CC BY 4.0。
4. **截图证据**：迁到私有档案后，公开文档只留文字描述（推荐），还是保留少量重制画面截图替代。

## 8. 进度（OSS1 工具侧，2026-09-27）

用户 09-27 拍板：方案甲；探针结果与运行记录公开；代码 MIT、配乐与文档 CC BY 4.0；原版截图迁出（文档侧由 OSS2 做）。本节只记工具侧已落地的东西与实测数字。

**玩家流程（公开仓库）**：`HSL_ORIGINAL_DIR=<Steam 經典版 GAME-PAK> python3 tools/hsl.py generate <任务…>` 导入 → `python3 tools/hsl.py check original_derived_manifest` 逐条比对哈希。

| 项 | 落地 | 实测 |
| --- | --- | --- |
| 来源可覆盖 | `hsltools.paths`：`HSL_ORIGINAL_DIR`（默认 WINEPREFIX `drive_c/hsl`）、`HSL_ORIGINAL_PAK`（目录里有 `hsl-cn.pak` 时默认选它）；所选包不是 `<目录>/hsl.pak` 时 `ORIGINAL_ROOT` 换成符号链接视图 `ignored/original-view/hsl/`，现有导入器不改 | 858 个原版直读任务用 Steam `hsl-cn.pak` 重跑：551 ok、300 纯检查跳过、7 失败（3 个要 `hsl01.exe`、1 个要内存转储、3 个要 `ignored/` 导出）。与 tracked 不同的只有 `FONT15/FONT24.png` 与 `original_fonts.json` 里的哈希，本机 `hsl.pak` 重跑是同一字节：**是 tracked 图集过期，不是两个数据包的差别** |
| 原版缺席 SKIP | `hsltools.original_content`（唯一 A/B/C 分类，`oss_audit_stats` 也用它；在场＝导入的 `PLAYERS.TXT` 存在）；tracked 清单 `content/generated/hsl/original_derived_manifest.json`（19,317 条：路径＋SHA-256＋生成任务），注册任务 `original_derived_manifest` | 导出树（无 A 类）：`hsl check --all` → `SOURCE_CHECKS_SKIP original-absent tasks=1347 of=1431`＋其余 84 个 PASS；Python 单测 139 个文件 76 个 `SKIP original-absent`、62 个通过，只剩 `test_hsl_shell_var_braces`（导出目录还不是 git 仓库）；`verify.sh` 跳过 Godot 导入与套件；doctor 只剩"不是 git 仓库"一条 |
| 可再生实证 | 临时树删掉全部 A 类，用本机原版 `hsl generate` 1,254 个任务、多轮直到不动点 | 见下表 |
| 公开树装配 | `tools/oss_export.sh OUT [REF]`：只读已提交树，写 B＋处理后的 C，剔除 A、`docs/external/typesafe`、`legal-assets`、`asset-dumps`、`ignored`、`.claude`；`/Users/<名>`→`~`、作者邮箱改占位；`.gitignore` 加上挡住本地导入的规则；产出 `OSS_EXPORT_REPORT.md` | 写出 **1,883 个文件、51.2 MB**（B 1,401／C 482），剔除 19,354 个、733.7 MB，处理 13 个，残留个人路径／邮箱 0 |

**可再生实证**（A 类 19,317 个；新导入器的 PNG 编码与 tracked 的旧编码字节不同时，也按像素比对）：

| 结果 | 文件数 | 说明 |
| --- | ---: | --- |
| 重生成逐字节一致 | 15,400（79.7%） | |
| 像素一致、字节不同 | 809 | PNG 编码器差异；另有 229 个 JSON 不同，抽查都是其中嵌的 PNG 哈希或文件名大小写（`actor_audio.json` 的 `Attack01.WAV`：生成器沿用磁盘上已有文件的大小写） |
| 真不一致 | 2 | `FONT15/FONT24.png`：tracked 图集已过期（见上），临时树里字表又随未生成齐的内容变化 |
| 生成器缺失或失败 | 426 | `actor_magic_poses` 278 个（任务 ok 但没写到声明目录下）、`stat_magic` 47（`manifest.json` 没人写）、`level_actors` 60、`music_import` 19（缺 soundfile／numpy）、AI 频率／回放／开场快照要 `ignored/` 导出 |
| 没有生成器 | 1,506 | 证据截图／录像 774、`shared/shape_previews` 292、`battleNNN/section_title.png` 48 等 297、占位美术 73、`global/tables` 17、`static/hsl01` 16 |
| 只有纯检查任务 | 952 | `actor_walk_manifest` 698、`message_text_evidence_check` 150、`gameplay_reference` 81、`visual_evidence_index` 16、`actor_walk_contact_sheet` 7 |
| 原地改写的根 | 4 | `actor_walk_manifest.json`、`first_battle.json`、`gol_road_battle.json`、`priest_trial.json`：拥有它的任务读它再改写，从空目录起不来；这 4 个一缺，`level_actors` 12,556 个与全部 `level_battle` 都生成不出来 |

**迁移建议**（按收益排）：

1. 4 个原地改写的根拆成"手写底稿（B，移到 `content/authored/`）＋生成部分"，否则公开仓库从空目录起不来。
2. 原版表 `global/tables`（17）、`source_texts`（5）、`ui_resources.json` 注册成一个"原样导入"任务：按成员名比对，其中 5 个是 PAK 成员原文或只去掉 CR，`PLAYERS.TXT` 等其余要查导入时做过的变换。
3. `actor_walk_manifest`（698）、`message_text_evidence`（150）补生成路径（现在只有检查）；`shape_previews`（292）、`section_title.png`（48）、`actor_magic_poses` 声明补齐。
4. 清单对 PNG 改存解码后像素的哈希，或在私有仓库用现在的编码器统一重写一次——否则玩家新导入的 809 个 PNG 会被判"与清单不符"。
5. 证据截图／录像（774＋`gameplay_reference` 81＋`visual_evidence_index` 16）、原版存档 3 份按 §2.2 迁出，不生成。
6. 占位美术 73 个改成从导入的 003 号帧换色生成（§2.2）。

**维护代价**：清单跟着 A 类走，改了生成物的 lane 要顺手 `hsl generate original_derived_manifest`（一行一条，并行 lane 改不同文件能自动合并）。关卡任务表现在取磁盘目录与清单的并集，清单过期会多出任务而报错，不会静默少跑。

## 9. Windows／Linux 可移植性（WINPORT，2026-09-27）

目标用户是拿本仓库改自己游戏的人，多数在 Windows。本节记审计出的 macOS／本机假设和每条的处理；没有 Windows 真机，只做了静态改法与 CI 替身（`.github/workflows/portability.yml`，未真跑）。

**入口（不需要 bash）**：`python tools/hsl.py check|generate|doctor`、`python tools/verify_runner.py python-tests`、`powershell -ExecutionPolicy Bypass -File tools\play.ps1`、`tools\godot.ps1 GODOT_ARGS…`。`hsl.py` 与 `verify_runner.py` 在 Windows 自动以 `-X utf8` 重启（`PYTHONUTF8=1` 传给子进程），因为工具里大量 `read_text()`／`open()` 没写 `encoding=`，cp936／cp1252 下会读坏 UTF-8。

**原版目录探测**（`hsltools.paths.detect_original_dir`，`hsl.py doctor` 报出结果与来源）：

| 平台 | `HSL_ORIGINAL_DIR` 未设时 |
| --- | --- |
| Windows | Steam 根：注册表 `HKCU\Software\Valve\Steam\SteamPath`，再试 C:–F: 的 `Program Files (x86)\Steam`、`Program Files\Steam`、`Steam`、`SteamLibrary` |
| Linux | `~/.local/share/Steam`、`~/.steam/steam`、`~/.steam/root`、Flatpak `~/.var/app/com.valvesoftware.Steam/.local/share/Steam` |
| 以上两者 | 每个 Steam 根读 `steamapps/libraryfolders.vdf` 的全部库；库内按 `appmanifest_4030150.acf` 的 `installdir`（没有就扫 `steamapps/common/*/GAME-PAK/hsl-cn.pak`，不假设目录名）取 `GAME-PAK/`，要求有 `hsl-cn.pak` 或 `hsl.pak`。Proton 前缀不用找：經典版在应用目录里，不在 `compatdata` |
| macOS，及以上都找不到 | `$WINEPREFIX/drive_c/hsl`（默认 `~/.wine-hsl-original`），同改动前 |

探测到的 Steam 目录有 `music/` 时 `STEAM_CLASSIC_ROOT` 也跟随。`ignored/original-view/hsl/` 视图在 Windows 建符号链接被拒（非管理员、未开开发者模式）时，目录改 junction、文件改硬链接、跨卷再退为复制。

**审计清单**（「已改」＝本 lane 已提交；macOS 行为均不变）：

| # | 假设 | 位置 | 处理 |
| --- | --- | --- | --- |
| 1 | BSD `stat -f %m` 在前，GNU `stat -c %Y` 兜底：Linux 上 GNU `stat -f %m FILE` 先打印文件系统信息再失败，垃圾混进 mtime | `godot_cache_seed.sh`、`verify_slot.sh` | 已改：GNU 在前（BSD `stat -c` 报错无输出） |
| 2 | `/private/tmp` 只在 macOS 有 | `lane_merge.sh` 5 处、`verify_slot.sh` 2 处 | 已改：`/tmp`（macOS 上是同一目录的链接） |
| 3 | `/opt/homebrew/bin/{python3,godot,wine}` 写死 | `verify.sh`、`lane_verify.sh`、`oss_export.sh`、`hsl_capture.sh`、`run_original_hsl.sh`、doctor | 已改：存在就用，否则 PATH 上同名工具；环境变量优先不变 |
| 4 | `cp -c`（APFS clonefile） | `godot_cache_seed.sh` | 不改：已有 `cp -R` fallback（GNU `cp -c` 是 `--preserve=context`，失败也会落到 fallback） |
| 5 | `mktemp "${TMPDIR:-/tmp}/x.XXXXXX"`、`find -newercm`、`mktemp -d DIR/x.XXXXXX` | `godot.sh`、`play.sh`、`godot_cache_seed.sh` | 不改：GNU 同样支持 |
| 6 | zsh 专有语法 | tools/*.sh | 无：14 个脚本都是 `#!/usr/bin/env bash`，`bash -n` 通过 |
| 7 | 整条 bash 链（godot／play／doctor／verify） | Windows 无 bash | 已改：doctor 移到 Python（`doctor.sh` 成薄包装）；新 `play.ps1`、`godot.ps1`；`verify.sh`、`lane_*.sh` 仍要 bash（Git Bash／WSL），属维护者流程 |
| 8 | `ignored/original-view` 用 `symlink_to` | `hsltools/paths.py` | 已改：Windows 退为 junction／硬链接／复制 |
| 9 | 生成物里嵌 `str(Path)`，Windows 会写出反斜杠 | `assets/actor_audio.py`、`interface_audio.py`、`panel_assets.py` | 已改：`.as_posix()`（POSIX 逐字节不变） |
| 10 | 同上 | `data/attack_ranges.py`、`data/equipment.py` | 待改（OSS3 写集）；其余 f-string／`os.path` 形式未穷举。只在导入原版之后生效，原版缺席时这些任务是 SKIP |
| 11 | 默认 Wine 前缀 `~/.wine-hsl-original` | `hsltools/paths.py` | 已改：只作 macOS 与兜底默认，见上表 |
| 12 | `WINE_BIN` 默认 `/opt/homebrew/bin/wine`；探针 docstring 里 `uv run --python /opt/homebrew/bin/python3` | `hsl_runtime_probe.py`、`hsl_original_control.py`、`hsltools/probes/_*.py` 9 个 | 不改：原作运行观测是维护者的 macOS＋Wine 流程 |
| 13 | macOS 专用：`screencapture`、Swift helper、`cliclick` | `hsl_capture.sh`、`build_runtime_helpers.sh` | 不改；doctor 在 Windows／无 bash 时把路由语法记 INFO、`--original` 的 helper 检查只在 macOS |
| 14 | `/Users/` 字样 | `oss_export.sh`（脱敏规则本身）、`function_catalog.py`（泄漏检查）、测试夹具 | 不改：是检测规则，不是路径依赖 |
| 15 | 测试里的 bash／`.sh`／`os.symlink`／`/tmp`／`chmod` | 26 个 `tools/test_hsl_*.py` | 未改：Windows CI 首跑定清单（GitHub Windows runner 有 Git Bash、以管理员跑，多数应能过） |
| 16 | Godot 项目路径大小写 | 全部 tracked `.gd/.tscn/.tres/.json/.godot` 里的 `res://` 字面量 | 实测 35,994 处，只差大小写 0；拼接出来的路径未覆盖 |
| 17 | 换行与二进制 | `.gitattributes` | 已改：`* text=auto eol=lf`＋26 条二进制扩展名；原版逐字节源文本仍 binary，补漏 `ACTION.H`、`EXTRAS.H`（index 里 207 个 CRLF 文件全部 -text，不触发重归一化） |
| 18 | tracked 路径只差大小写 | 全仓 | 新检查任务 `case_collisions`：21,220 条路径 0 冲突 |
| 19 | 生成物 JSON 的大小写差（§8 表「229 个 JSON」里的 `Attack01.WAV`） | `assets/actor_audio.py` | 已改：查清是内容引用＋磁盘文件名同源——生成器沿用磁盘上已有拼写，没有就小写，结果随任务先后变，区分大小写的盘上会留两份。现在先取派生物清单里的 tracked 拼写，其次磁盘，最后小写 |

**CI 替身**：`portability.yml` 在 windows／ubuntu／macos-latest 上装 Python 3.12＋`requirements-dev.txt`、下载 Godot 4.7.2 headless，跑 `hsl.py doctor`、`hsl.py check --all`、`verify_runner.py python-tests`、Windows 上 `godot.ps1 --headless --version`、`compileall tools`、pwsh 解析 ps1、非 Windows `bash -n`。本机只做了 `actionlint`（0 报错）；另在 macOS 上对 `tools/oss_export.sh` 装配的公开树（`git init` 后）跑了同样三条：doctor 通过、`hsl check --all` → `SOURCE_CHECKS_SKIP original-absent tasks=1347 of=1432`、通过 85（OSS1 的 84＋`case_collisions`）；`verify_runner.py python-tests` → 139 个文件 76 个 SKIP original-absent、63 个通过（`PYTHON_UNIT_TESTS_SUMMARY files=139 tests=335 skipped_original_absent=76`）。

**没有真机验证的**：Windows 上的注册表探测、junction／硬链接 fallback、`play.ps1`／`godot.ps1`（本机无 pwsh，连语法都只交给 CI 的解析步骤）、UTF-8 重启、`hsl check`／单测在 Windows 路径分隔符下的结果；Linux 上的 Steam 库探测（只在 macOS 上用伪造的 `libraryfolders.vdf` 走过一遍）；GitHub Actions 整个工作流。
