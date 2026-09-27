# 脚本等待与守备唤醒：实际可玩验收

> evidence: runtime-measured · status: live · tools: capture_script_wait_review.gd, run_script_wait_tests.gd · updated: 2026-09-18

SR-070在`36437b42cf9cb349df0370974c41d5d32ff99288`基线上接续。原指令见[VM／AI等待合同](../../static_reverse/original_script_wait.md)，本页为Godot正常时钟、640×480内建屏0的实际控件路线。[机器回执](receipt.json)逐次保存PID、真实进程退出码、有效路线、等待／AI／交锋／资源与保存记录、12张人工查看过的图片及哈希。

## 已完成的17条路线

| 路线 | 实际覆盖 |
| --- | --- |
| opening | 原STORY052和原阵容／技能未改。四名守卫创建时均等待2；按正常队列各自先行动一次，首次Leonard菜单时剩余1。开场音画完成、实际F5/F9后倒数一致 |
| guard、double_guard | 两次完整回合与两次独立行动的等待倒数，0次之后重新选动作，守候提示与菜单分隔，保存不重新设置等待 |
| wounded、silenced、paralyzed | 受伤或禁魔状态唤醒，麻痺先走行动入口跳过、下一周期再判断；这些远距位置被源地形隔开，实际保留无有效动作退路，没有穿墙或虚构目标 |
| ai_chain | 近处受伤法师清等待，第一次使用自己拥有的風刃并耗尽8MP，第二次重新选择、移动到合法站位后普通攻击／反击；末次资源／状态尾部一次提交 |
| event、mage、support | 普通双击／反击与两次行动、毒／禁魔并存；同一事件重复设置覆盖旧值，实际换装后移动施法／治疗，MP和支援EXP一次结算，事件后保存恢复 |
| sync、depart | 短动作指定对象已停、无关对象仍在长走时继续对白；当前对象走出后等待结束，再触发同模板第二实例离场。F9后不出现幽灵、旧实例占格或重复剧情 |
| kill、victory、defeat、escape | 击杀后继续战斗并分配成长；清敌、主角倒下、到达撤离格后待机三种终态；结果脚本设置与同步先完成，终态冻结后F5/F9和实际重开按钮通过 |
| carry | 撤离后经独立一次性carry进入实际新场景，保留相符队员成长／装备等字段，新场景等待来源和事件游标从自己的配置开始；新场景再次F5/F9通过 |

除opening外均为明确的开发夹具：沿源051地形及004／006／002／026角色资源，指定初始HP／MP、装备、状态、AI概率和event901。没有把这些夹具赠予写进正式关卡。回合内攻击、换装、移动、施法、等待、成长、保存、恢复、重开均使用现有按钮和目标格，不直接修改结算结果或替换随机抽样。

## 已检查画面

[守候倒数](guard-count.png)与[正式第二战](source-opening-guard.png)取已经提交的剩余次数；后者也记录了“开始时2、第一次实际行动后1”的时点。[指定对象同步](specified-object-dialogue.png)的静帧配合运行时断言确认另一角色仍在运动。[移动風刃](moved-wind-target.png)、[移动治疗](moved-healing-target.png)展示当前技能范围和对象信息，[离场后恢复](departed-restored.png)确认旧人物不残留。

[持续战斗的成长分配](ongoing-growth.png)与[末敌击杀的EXP／升级提示](terminal-experience.png)分别验收：终态继续保留五个待分配点，不能强行打开一个新的战术成长操作。[清敌结果](victory.png)、[败北结果](defeat.png)、[撤离结果](escape.png)都在对应脚本结束后显示。[跨场景恢复](new-scene-restored.png)展示新阵容与自己的控制状态。守候0.55秒、脚本步速／镜头与既有音效时钟仍为重制参数。

## 进程边界与修正

`render-guards.log`五条和`render-events.log`五条均整次退出0。`render-outcomes-final.log`在完成ai_chain、kill后，旧断言错误要求胜利也弹出分配面板，进程退出1；只采纳此前两条具名结果。改为终态保留待分配点后，`render-close.log`完成victory、defeat、escape及各自保存／按钮重开，但后续开场断言忽略了守卫已经执行过的首次队列行动，进程退出1；仅采纳此前三条。最后`render-opening-carry.log`以正确时间点完成opening、carry，两条整次退出0。

更早的AI断言把普通攻击限定为不移动，而真实第二行动先走入攻击范围；修正为同时验证合法位置和物理交锋收据。headless对象同步场景曾在断言全部通过后遗留音频引用，按既有释放协议等待引用消失再退出；这一诊断失败没有被写成PASS。所有失败与有效范围都保留在回执，最终完整门禁必须另取真实退出结果。

旧存档缺少新等待来源签名时明确拒绝，原文件保留。本批不把任意动画中的存档、原格式迁移、整个原VM／AI dispatcher、全局随机流或世界／story-only同步写成等价。源setter对负DWORD的行为只保留为原指令样例，Godot依现有可玩域拒绝0..10000之外的输入。

```sh
tools/godot.sh --headless --script res://tests/run_script_wait_tests.gd
tools/godot.sh --screen 0 --script res://tests/capture_script_wait_review.gd
tools/verify.sh
```

上述实玩入口只写`ignored/script-wait-review/`的截图与隔离存档。末次完整门禁和提交号以本批提交说明及协作收口为准。
