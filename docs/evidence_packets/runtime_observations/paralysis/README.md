# 麻痺入口、解围与恢复：实际输入验收

> evidence: runtime-measured · status: live · tools: capture_paralysis_review.gd, run_paralysis_tests.gd · updated: 2026-09-18

SR-059基于`a8d9ae3`，在原WRD、美术、职业资格和正常时钟下，通过真实鼠标／键盘运行14条具名路线。原指令结论见[麻痺证据](../../static_reverse/original_paralysis.md)，本包[receipt.json](receipt.json)分别保存实际路线、进程退出码、耗时、截图哈希及明确夹具设置。

## 已走通的体验链

| 路线 | 实际覆盖 |
| --- | --- |
| enemy_skip、player_skip | 实际地靈縛使敌人失去行动；玩家麻痺时自动跳过，白光之翼不重复授予；正常队列轮转、毒伤／自动回魔／血转MP／到期依次反馈，下次正常行动恢复控制 |
| player_cure、ai_cure | 玩家移动用精靈石，AI无MP／禁魔时移动用真实道具解围；清麻痺保留禁魔，受救队友恢复正常动作与独立第二行动；解除文字结束前没有后继菜单 |
| support_bound | 移动治疗恢复HP但保留三种状态，第二行动驱毒仅清毒；病患仍跳过一次并独立递减麻痺／禁魔，支援贡献照常发EXP |
| immunity、axe_growth | 虹之首飾实际装备／取消／卸下改变后续免疫；霸邪天煌按源重装职业资格装备，击杀及升级后保持当前防护；防护不治疗已有状态 |
| mixed_area、detour | 移动后选择空格中心，一次付款、范围中分别免疫／麻痺，实际贡献升级；原地形绕路后施放，预算与落点共用当前规则 |
| ai_bind | AI移动施加地靈縛后耗尽MP，第二行动重新决定普通双击；三次实际impact依次完成，麻痺目标不能反击，后继只在完整收尾后出现 |
| resume_skip | F5保存待进入的麻痺槽，走过一次跳过后F9恢复，再次实际推进得到相同状态／队列／资源；旧法术／EXP／提示不重播 |
| victory、defeat、escape | 第一行动麻痺贡献升级、第二行动首击清敌；麻痺者被致命攻击时不反击；到期后正常移动撤离。三终态均保存恢复并实际按钮重开，不补末尾资源或剩余次数 |

正式第一战不增加地靈縛、精靈石或防护装备。受控法师／重装兵、当前HP／MP、源属性增量、伤害边界用1HP目标、源技能授予和状态成功率100均为验收夹具；原概率40已单独通过原指令对拍。脚本没有替换伤害／EXP／RNG／AI结果，也没有加速时钟或修改地形。保存写到`ignored/paralysis-review`专用文件。

## 已检查图证

[原地系局部施法](enemy_skip-impact-0.png)、[跳过行动](player_skip-skip-2-leonard.png)、[到期](player_skip-tail-2-4.png)展示施加→入口→恢复。[防护装备预览](immunity-equip-211-accessory1.png)、[混合范围](mixed_area-impact-0.png)、[实际职业成长](axe_growth-growth.png)覆盖来源与派生联动。

[治疗后只驱毒](support_bound-impact-1.png)、[玩家精靈石](player_cure-cure-item.png)、[AI精靈石](ai_cure-cure-item.png)分别验证正向反馈和解除边界。[AI第二行动的末击](ai_bind-impact-0-3.png)与回执中的三个impact一致。终态为[胜利](victory-result.png)、[败北](defeat-result.png)、[撤离](escape-result.png)。十三张原尺寸图片均已查看；它们不证明原粒子轨迹／混合或精确时钟等价。

## 本轮发现和修复

新入口最初只校验资源字段，非法装备槽可能在跳过时未被拦住；现入口先执行完整只读资格校验，失败不提前改状态或推进队列。已有到达位置满足终态时，原关卡按已提交位置判断；已改为在跳过尾部之前冻结结果，避免先扣毒伤或被动恢复。

补拍精靈石暴露了真实表现回归：没有资源尾部的用药原先遗漏在共用busy条件之外，解除文字期间后继菜单会提前出现。该失败进程退出1，不采纳为最终图证；修复共用输入／结果／剧情门禁后，玩家及AI两条补拍进程均退出0，并新增无资源尾部、有限释放和旧sequence不重放的回归。

支援纯规则测试曾漏掉场景实际执行的演出完成后`finish_exhausted_action`边界，已补齐；未改产品成即时发第二行动。旧毒／禁魔样例新增明确健康麻痺字段，旧原指令包仍只对它本来记录的字段对拍。初始化把已验证的JSON数值转换为整数，避免未变化的0.0与后续整数状态产生表示差异；缺字段仍拒绝。

五组成功渲染进程均取回退出0。早期成功路线中，玩家／AI道具和AI第二行动分别由后续更强观察替换；机器回执同时保留各组原完成范围和最终采用范围，不反向升级早期观察。当前14条路线的关键规则／资源／终态证据与已提交旧战斗链分别记录。

```sh
# 内建屏编号需现场核对；本次为0。
tools/godot.sh --screen 0 --script res://tests/capture_paralysis_review.gd
tools/godot.sh --headless --script res://tests/run_paralysis_tests.gd
tools/verify.sh
```

最终完整门禁结果以本批真实日志及提交说明为准。原完整高位dispatcher、全部wake／死亡回调、其他异常及多格占地仍单列边界；不能用本批实玩或测试绿推导它们完成。
