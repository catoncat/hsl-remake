# 原作通关尾声独白 STORYOVER 的加载者（static-derived）

> evidence: static-derived · status: live · functions: 0x415730, 0x42cd10, 0x43e2a0, 0x44cce0, 0x45e307 · tools: hsltools/assets/title_assets.py · updated: 2026-09-26

## 结论

`DATA\STORYOVER.TXT`（緹娜／漢克斯十句、含 WALKSOUND 脚步声、以 actDeleteDarkScreen 收尾）由 **GameClear（level 998）的 BOSS 物件过程 `defProcClearBOSS`** 加载并执行，不是战败（GameOver，level 999）侧的脚本。此前 P-049 把它读作"战败尾声独白（level 999 GameOver 侧）"，该读法作废。

| 事实 | 证据 | 等级 |
| --- | --- | --- |
| 物件过程表位于 `.data` 0x477c2c，77 项，按 `PROCESS.DEF` 的 `defProc*` 编号索引 | 第 41 项 = 0x415730 = `defProcTreasureBox`（与已验证的宝箱过程一致）；第 74 项 = 0x42b6b0，`PROCESS.DEF` 中 `defProcClearBOSS = 74` | static-derived |
| `0x42b6b0` 是以 `[esi+0x8c]`（0..19）为状态的物件过程，跳转表 0x42b9c0 | 状态 3（0x42b775）：`0x43e2a0(0)` 取得物件后置 `[eax+0x94]=0x60006`、存全局 0x4c1d3c，随后 `push "DATA\STORYOVER.TXT"; call 0x42cd10; call 0x44cce0`（与关卡脚本相同的"取记录→装载脚本"两步） | static-derived |
| 状态 0／4 为倒计时（`[esi+0x94]` 递减到 0 再进下一状态），状态 1／9／13／19 以 `0x45e307(0x4e20,0x4e20,code,0)` 插入物件（code 0x1e／0x1f／0x14 等） | 线性反汇编（r2） | static-derived；插入物件的对应见 [原版配乐](original_music.md) §3.5（obj-998.obs：0x1e＝物件 30 OVER001、0x1f＝物件 31 OVER002、0x14＝物件 20 WORKTEAM） |
| GameOver 侧：`defProcGameOverBOSS = 58` → 0x42aea0、`defProcGameOverWord = 59` → 0x42afc0；`obj-999.obs` 只有 TITLE011 BOSS 与 TITLE012 Word 两个物件 | PROCESS.DEF、过程表、obj-999.obs | resource/static-derived |
| 全 EXE 只有一处引用 STORYOVER 字串（0x42b7a0） | `/x 3c784700` 唯一命中 | static-derived |

## 重制接入

`tools/hsltools/assets/title_assets.py` 把 STORYOVER（tracked 语料 `content/imported/hsl/story_corpus/scripts/STORYOVER.json`）编成 `manifest.game_clear_epilogue.steps`（delay／message／sound／reveal），并解码 `WAV\WALKSOUND.WAV` → `content/imported/hsl/global/title/walksound.wav`；`game/title/GameClearScreen.gd` 按状态顺序把它放在 Over001 与 Over002 两段之间（状态 1／3／9，见 [原版配乐](original_music.md) §3.5），以黑场＋共享对白板播放。回执见 [story_scene_endgame_previews](../runtime_observations/story_scene_endgame_previews/README.md)。

## 边界

- 先后关系按 [原版配乐](original_music.md) §3.5 的状态顺序：状态 1 插入物件 30（OVER001），状态 3 装载 STORYOVER，状态 9 插入物件 31（OVER002）。独白执行时 OverBG01／OVER001 是否仍在画面上、actDeleteDarkScreen 揭示的是什么，未由运行观测确认。
- actDelay 单位取重制开场协调器的 0.025 s；actMessage 是否等待按键、对白板与肖像均为重制读法。
- 状态机其余状态的语义（插入的物件码、等待条件）未逐项解读。
