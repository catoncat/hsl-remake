# 技能资源费用、门槛与扣除

> evidence: static-derived · status: live · functions: 0x408fe0, 0x409040, 0x409890, 0x409980, 0x40e240, 0x40e290 · tools: hsltools/probes/skill_cost.py, run_skill_resource_tests.gd · updated: 2026-09-13

Checked: 2026-09-13。机器证据见 [original_skill_resources.json](original_skill_resources.json)，复跑工具为 `tools/hsltools/probes/skill_cost.py`。本包恢复费用，不代替技能拥有权、目标阵营／状态资格、效果公式或AI决策树。

## 原始来源

原EXE SHA-256：`f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。工具已实际读取原PAK中 `@:\data\magic.txt`、`special.txt`、`item.txt`，原始哈希及tracked导入哈希分别保存在机器包。原包使用CRLF，导入表使用LF；SPECIAL还去掉了最后一个空行。校验只统一行尾及末尾LF，表内内容（含注释和空格）必须完全相同，不把规范化导入称为原始字节完全一致。

`0x44d571` 读取special段，记录经 `0x44d5f3/0x44d602` 登记到 `0x4c3920` 的类型／编号表；`0x44d699` 查找 `expend`，`0x44d6b3` 存到该记录 `+0x10`。Magic段从 `0x44d9d4` 开始，经 `0x44da60/0x44da6f` 登记到 `0x4c2ca0`；`0x44db06/0x44db20` 同样把expend存到 `+0x10`。机器包列出28段实际核对的字段、getter、门槛及扣费指令，未列字节的上下文地址为人工反汇编审阅。

Leonard当前氣刃斬仍由 `PLAYERS.special_other`、`mag-spc.h` 和 `SPECIAL magicOTHER/magicCode01` 关联，expend=1。源定义和已导入图片无需重新抽取；本批只替换此前尚未证明的费用解释。

## 费用与使用门槛

| 资源操作 | 原入口／字段 | 已确认行为 |
| --- | --- | --- |
| 魔法基础费用 | `0x409890`，Magic记录+0x10 | 返回原expend |
| 魔法是否足够 | `0x408fe0`，actor+0xe0 | 普通费用用expend；减耗位存在时用 `floor(expend/2)` 比较当前MP |
| 特殊技费用 | `0x409980`，Special记录+0x10 | 原指令 `lea x*5; shl 2`，费用为 `20×expend` |
| 特殊技是否足够 | `0x409040`，actor+0xe8 | 与同样的 `20×expend` 比较，等于门槛时允许 |
| MP减耗谓词 | `0x40e290→0x40e240` | 查询actor+0x18c的bit1，即掩码2 |

ITEM的 `mp_use_half` 在 `0x447ddf` 被读取，非零在 `0x447df4` 置掩码2，`0x4481b1` 写ITEM+0xa0。装备应用 `0x448709..0x448717` 将该effect word并入actor+0x18c。这是装备费用修饰位，不能混同禁用攻击的actor+0xa0掩码2或装备take_off的ITEM+0xa4掩码2。

## 扣费与原版差异

魔法实际执行 `0x442b99` 读基础cost，`0x442ba1` 查询减耗位；有该位时 `0x442bad..0x442bbc` 将费用除2后截断，并在结果为0时改为1。`0x442bc1..0x442bce` 从当前MP减去该值。**使用门槛未做最低1修正，扣费却做了**：expend=1、减耗=true、MP=0时，原门槛helper返回允许，扣费片段得到MP=-1。该结果已执行确认，不为统一代码而隐去。

特殊技玩家施放在 `0x44529e` 调费用getter，`0x4452af` 保存扣除后的ST；另一条执行路径 `0x441cf3/0x441d00` 使用相同getter扣ST。两条caller为static-derived，未执行完整特殊技函数，也没有据第二条地址单独宣称完整原AI路径已恢复。

当前产品选择：实际资源必须足以支付扣除额，禁止提交负MP/ST；此规则只在上述极小减耗费用边界强于原门槛，是明确重制策略。`native_required` 与实际 `amount` 分别保留，正常费用和可支付减耗费用按原结果执行。本包当时的固定5ST增长已由后续 [原气力证据](original_stamina.md)替换：168组完整函数正常返回支持攻击／受击差异、装备修饰及60上限。初始0仍是单独批准的重制选择，费用证据本身不证明初始化等价。

## 有界执行与独立对照

32组输入覆盖magic/special、expend0/1/3/6、减耗开关、门槛下1／恰好／上1（去重）。在合成对象、actor、类型表与记录上执行原getter和门槛函数，每组两次正常返回；magic gate内部的两个减耗helper也执行原指令，没有stub。getter/门槛调用最多512条指令，非白名单callee直接拒绝，actor内存不变。

魔法例另在寄存器准备好后从 `0x442ba9` 执行到 `0x442bcf`：EAX为该输入的减耗谓词，ESI为实际getter返回费用，ESP+0x14为actor指针。最多128条指令，仅MP字段允许改变。它是**执行过的内部代码块**，不是完整魔法函数正常返回；机器包 `full_spell_function_return=false` 防止混称。特殊技本批只执行getter／门槛，实际扣除caller用静态字节核对。

独立Python模型逐项比较输出，Godot规则再逐项对照已保存的原输出。全部原始EXE/PAK核对和32组执行本次已实际通过。首次PAK检查发现换行差异，确认没有表内差异后加入限定的规范化和篡改测试，没有放宽为仅比较部分字段。

## 产品接入与失败原子性

纯 `SkillResourceRules.amounts/quote` 接受来源expend、当前资源和只读装备catalog。原表可选 `mp_use_half` 被生成为明确布尔字段，quote从当前装备读取，不缓存第二套可变effect状态。尚未支持的其他被动装备仍按原catalog支持范围禁用，没有因为加入费用字段而解锁完整被动系统。

`BattlePlayLoop.can_use_special`、特殊技提交和法师AI费用筛选／提交共用quote。命中／落空都支付一次，取消、错误目标、旧确认或资源不足无扣除。收据保存实际before/amount/after，界面只读。场景中旧 `stamina_per_expend` 配置已移除，避免一份原常量同时受另一份配置影响；level52仅同步共享配置，不扩正式关卡。

缺失费用、负数、非整数、非有限资源、超出32位费用域、缺装备修饰数据都明确失败。初始化和AI公共入口检查必需费用数据；坏数据进入scenario_error并保留坐标／资源／队列，不默默改用普通攻击。真正的MP不足仍允许AI使用既有其他可用动作，这是资源选择而非缺数据fallback。

`run_skill_resource_tests.gd` 包含32例原结果对照、ST19/20边界、命中／落空、取消和重复请求、无效目标不使用RNG、非法字段、AI普通／减耗费用及坏数据不前进；原508项行动组合和核心／第一战回归继续保留。新测试曾因JSON数字拼接为`2.0`触发错误，已改为整数key；冷缓存失败先完成导入后重跑。可见夹具曾误用“必须enabled”的点击helper测试disabled按钮，改为真实坐标输入后通过，不放宽产品按钮门槛。

```sh
uv run --with unicorn==2.1.4 python3 tools/hsl.py generate skill_cost --exe $HSL_ORIGINAL_DIR/hsl01.exe
python3 -m unittest tools.test_hsl_native_skill_cost_probe tools.test_hsl_equipment_data -v
godot --headless --path . --script res://tests/run_skill_resource_tests.gd
```

不带EXE/PAK参数只检查保存证据与来源，不重新执行原函数。原例、代码块与来源校验进入完整门禁；真实Control边界验收见 [skill_resources/README.md](../runtime_observations/skill_resources/README.md)。完整技能拥有权、目标function-mask、状态条件、伤害／效果／随机顺序及AI策略仍继续研究。
