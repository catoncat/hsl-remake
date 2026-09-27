# 第一战状态肖像

> evidence: resource-derived; static-derived: 0x4347f0 name-field reading, 0x407ec0 obj_Data5 install, 0x434d10 → 0x4477b0(+4) strip name verbatim; provisional: 306 ??? list labels shown by title (remake-invented) · status: record-only · tools: hsltools/assets/portraits.py, hsltools/data/actor_panels.py, hsltools/levels/battle.py · updated: 2026-09-26

Evidence: `resource-derived`。五张 120×144 肖像直接由 PLAYERS.TXT 的 `picture` 字段绑定到原始 PAK 内 SHP；保留原版人物像素、阵营底色与边框。

| Actor | SHP |
|---|---|
| 001 | SHAPE\FACE0000.SHP |
| 021 | SHAPE\FACE0021.SHP |
| 023 | SHAPE\FACE0023.SHP |
| 024 | SHAPE\FACE0024.SHP |
| 026 | SHAPE\FACE0026.SHP |

注意 001 不对应 FACE0001。面板名取 PLAYERS `name` 字段经 RESOURCE.TXT 解析（资源 id，或 resource.h 的 `name_N` 符号——玩家槽 001–009／020 即 `name_0`–`name_8`）；原版 `0x4347f0 player_name_text` 读的正是记录 +4 的同一 name id（static-derived，[原城镇转职](original_town_job_up.md)）。`name` 为公用占位 306（RESOURCE `???`）的行——无名士兵与怪物——在本表（列表标签：交付视图、队伍页、战败句）改显示其 `job_show_name`（重制显示选择，remake-invented）；身份栏姓名不用本表，见文末 2026-09-26 段。**2026-09-24 lane P1**：此前共享表对所有非玩家槽一律用 `job_show_name`，把有专名的 NPC 也显成稱號（064 克里夫→商人、053 克羅蒂→四魔將、025 法蘭克→帝國皇帝 等 10 行）；现按 `name` 字段判定，无硬编码名单（`hsltools/assets/portraits.py` `display_name`，manifest 记 `name_policy`）。此显示策略移除了状态页硬编码姓名表。**2026-09-24 lane R29**：同一策略叠加逐实例安装字——已放置对象的 `obj_Data5`（构造 `0x407ec0` 低字 → live +0x1c 稱號、高字 → +0x04 name）由 `hsltools/levels/battle.py install_title_name` 经 `display_name(row, names, defines, name_id, title_id)` 写进单位 `title`／`display_name`，`BattleVitals` 有单位键用之、否则用本表；17 关三名工人 062（行名 306）稱號显示 1235 搬運工人，6／7／901 关的 隊長 024 稱號 977 兵隊長。**2026-09-26 负责人决定**：身份栏（WINDOW10 悬停／切入／状态页）姓名照原版 `0x434d10` → `0x4477b0(+4)` 逐字印 +0x04 name id 的文字，306 行即使已知也印 `???`（2026-09-22 Wine 友军 一般兵、录屏 101 s；[身份栏包](original_identity_bar.md)）。`portraits.py panel_name` 是这条读法：`battle.py` 的单位 `display_name` 与 `actor_panels.json` 每行 `name` 都走它，`BattleVitals` 只读这两处；上面的稱號补名只留在本表的列表标签里。

```sh
python3 tools/hsl.py generate actor_portraits
python3 tools/hsl.py check actor_portraits
```

`content/imported/hsl/chapter01/portraits/manifest.json` 保存表文件、原始 SHP、PNG 哈希及名称。完整门禁包含资源绑定与 PNG 校验，运行时检查覆盖从玩家切换到法师/友军时的纹理选择和战斗状态不变。实际 640×480 状态页截图已核对，长职业名和玩家经验行均未溢出。

布局采用重制版左右分栏；这项交付证明使用原始肖像，不证明原版状态页位置、打开动画或完整属性已等价。无需原版安装即可运行产品及常规验证。

开场通过 STORY 的 actor token 选择头像；战中通过对白 speaker ID 选择头像，翻页时同步更新。战中正文按 40 字分段，回归检查拼接后等于原文。开场长台词、传令兵报告及撤退长文的实际页已截图验收；连续开场截图辅助流程在第二段停止输出并被主动结束，此次截图不作为完整开场连续操作验收。布局复用原有控件，移除了仅为无标题占位文本保留的位置分支，以及提示前的多余空行。

后续已完成连续开场验收：改用主动绘制取样，并将按键提交放到绘制回调之外；七段对白、可见标题和首次行动菜单均通过。见 `../runtime_observations/opening_continuity/README.md`。此结果补足上次辅助截图的证据缺口。
