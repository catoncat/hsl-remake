# 绝技对象的命令程序：objcomd.txt 解释器 0x4051d0 的运动指令与逐 tick 原指令执行

> evidence: static-derived: 0x4051d0 defProcObjectMove 解释器（跳表 0x406bc8）、积分器 0x42fcb0、生成器 0x401390／0x401480／0x401560、ANIMAL 随机／等距／环形插入（op 19／23–29）的读法与原指令执行，角度环 op 20 的逐实例初值与 無想冥殺 三个环的逐实例执行，op 21／22 的初值读法，剧情对象与命中趟轨迹; provisional: objcomd.txt 字布局、种子变体、首个插入点之外的出屏判定、objmLoopCheckSmallerY 的特写镜头、未读清的 5 处、繩子 engRANGE 裁切、多段绝技首段结算前的命中字、op 28 基点是否含击退第一步、其余角度环／龙卷列的重制几何 · status: live · functions: 0x401390, 0x401480, 0x401560, 0x401600, 0x401730, 0x401990, 0x4038a0, 0x403989, 0x4039c4, 0x403a0a, 0x403a50, 0x403aaa, 0x403ad7, 0x403b25, 0x403b73, 0x403bc1, 0x403be2, 0x403c3b, 0x403ddb, 0x4047c7, 0x4050a0, 0x405140, 0x4051d0, 0x406eb0, 0x42f8c0, 0x42fab0, 0x42fae0, 0x42fc60, 0x42fcb0, 0x45e575, 0x45e5a6, 0x45e5d9, 0x45e80d, 0x45e9bc, 0x45ea2b, 0x45eb9d, 0x45ebdc, 0x45f5f7 · tools: hsltools/probes/effect_motion.py, hsltools/probes/objcomd_motion.py, run_skill_effect_script_tests.gd · updated: 2026-09-29

## 结论

- 原版绝技特写里的对象（global.obs `obj_Process_Code = defProcObjectMove`，过程槽 37 → `0x4051d0`）每 tick 先由积分器 `0x42fcb0` 按 `+0x88` 标志位移动（速度＋角度、加减速、绕圈、点移），再解释 obj_Data7 选中的 objcomd.txt 命令程序；角度 256 一圈（0 向右、64 向下），速度／半径／缩放均 16.16（static-derived）。
- 同一程序的多个实例只靠共享 RNG 流错开：生成器 `0x401390` 的折叠偏移与累加延迟（每只比前一只晚 rand(delay)＋1）、objmRandomDelay、随机角／速／帧；另有全局「上一随机角」`0x4c1414` 防重复；没有按实例序号的字段（static-derived）。
- 60 行绝技脚本引用的 221 个 defProcObjectMove 对象全部经原指令逐 tick 执行，连同抛出的子对象写进 `content/generated/hsl/skills/objcomd_motion.json`（509 棵变体树）；重制 `SkillEffectScriptPlayer`、`PoisonArrowPresentation`、`MoonDancePresentation` 按它画（static-derived）。
- ANIMAL 的随机插入 op 19／23／27／28 走 `0x401390`（累加 rand(delay)+1），op 24／29 走 `0x401480`（固定步长），op 23／24／29 的首只 `+0xae` = base delay；子对象首次调用先把 `+0xae` 减一再与 0 比（`0x405294`），`+0xae` = d 的对象晚 max(d−1, 0) tick 开跑；op 25 走无随机的 `0x401560`，op 26 按 cos／sin 表排成一圈并让出一 tick；op 27／28／29 命中才插，op 28 以守方对象自身为基点。重制照此放置与排时（static-derived）。
- 剧情脚本插入的 defProcObjectMove 对象（12 关 19 个）走同一解释器，与绝技对象合计 240 个写进同一 JSON；重制 `StoryEffectObjects` 按轨迹逐 tick 画（static-derived）。
- 命中才掷出的子对象另跑命中趟（17 个对象两趟不同，写进 `hit_variants`），重制按该击结算的命中／落空选趟；多段绝技每个 op 72 各结算一段，对象按它读 `[0x4c1418]` 那一 tick 已结算的最后一段选趟（static-derived，守方先于对象跑，见「命中趟」）。
- ANIMAL op 20 aniInsertAngleObject（`0x401600`）在同一点建 n 只，第 k 只 `+0xae` = delay＋k·step、移动角与绕圈角 = k·256/n、速度与半径 0，n>0 时 SHP 帧 `+0x30` 加 k；探针对 無想冥殺 的三个环（Special06_03／05／06）逐实例跑原指令，写进 `patterns`，重制逐实例画（含命中趟火花）、按实例放声（static-derived）。
- 差异：随机样本用至多 4 个种子变体代替共享流、出屏判定按首个插入点、其余角度环（妖華紅蓮舞 op 20、op 21）与龙卷列（op 22）仍用重制几何、objcomd.txt 字布局（provisional，见边界）。

## 证据

EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`，r2 反汇编阅读＋unicorn 在合成对象上执行原指令，未运行原程序。

### 执行顺序与单位（static-derived）

- 单位：角度 0..255 一整圈（0=+x 向右，64=+y 向下，128=左，192=上；cos 表 `0x4a35fc`、sin 表 `0x4a39fc`，16.16）。速度、半径、缩放、步长均 16.16（0x10000 = 1 px/帧或 1 倍）。
- 「续」= `jmp 0x405df1`，本帧接着执行下一条；「让」= 写回 `+0xa4` 后 `jmp 0x406381`，本帧结束（尾段仍跑淡变／帧动画／缩放／残影）。
- 每帧顺序：插入延迟 → 积分器 `0x42fcb0` → 相位分派（相位≠0 只跑等待检查，本帧不解释新命令；等待满足时 `0x406377` 清相位，下一帧才执行后续命令）→ 解释 → 尾段 `0x406381`。
- 插入首帧（`0x405213`）：程序第一条若是 71 则计数并跳过；若是 2（objmRandomDelay）则 base＋rand(range) 并入 `+0xae` 插入延迟并跳过。延迟期间直接返回（不积分、不解释）。延迟到期调 `0x42fab0`：`+0x88` 清零，**基点 `+0x92／+0x90` = 当前 x／y（创建点）**。
- opcode > 0x4f：写回指针并让（空操作）。objmShowHitResultNoWait 只出现在 objcomd.txt 的注释行，不计。
- `0x4051d0` 入口先查 `0x4c1404` bit 0（场景拆除）即销毁自己：没有出口的程序由特写结束收走。

### 命令表：objcomd.txt 实际用到的操作码（static-derived）

| 操作码（号，handler） | 参数 | 读法 |
|---|---|---|
| objmOver（0，0x405e0e） | — | 相位 99，淡出至 0 后销毁（`0x405e0e`）。让 |
| objmDelay（1，0x405e53） | n | 相位 1，+0xa0=n，逐帧减到 ≤0 清相位；与下一条相隔 n+1 帧。让 |
| objmRandomDelay（2，0x405e7e） | base, range | +0xa0=base+rand(range)，相位 1。让。若是程序首条则在插入时并入插入延迟 |
| objmThrowRandomObject（5，0x4053df） | code, dx, dy, xr, yr, delay, num | 调 `0x401390(x+dx, y+dy, code, xr, yr, 0, delay, num)`（x/y 为本对象世界坐标）。续 |
| objmThrowHitRandomObject（6，0x405424） | 同 5 | 仅当 `[0x4c1418] < [0x4c6f58]`（命中）才调 0x401390（同上）；未命中不抽随机。续 |
| objmThrowHitRandomObjectFixDelay（7，0x405485） | code, dx, dy, xr, yr, baseDelay, step, num（实读 8 参，头文件注释少写一个） | 命中才调 `0x401480(x+dx, y+dy, code, xr, yr, baseDelay, step, num)`。续 |
| objmThrowRandomObjectFixDelay（9，0x405527） | code, dx, dy, xr, yr, baseDelay, step, num | 无条件调 0x401480（同上）。续 |
| 〃 生成器 0x401390 | — | 每只：dx=rand(xr)，若 dx>xr/2 则 dx=xr/2−dx（近似对称 ±xr/2）；dy 同理用 yr；`0x45e307(x+dx, y+dy, code)`；子 +0xae=累计延迟 d，d 初值 baseDelay，每只后 d += rand(delay)+1。每只 3 次 rand；子对象按创建顺序用 0x45e485 串链 |
| 〃 生成器 0x401480 | — | 同上但 d 每只加固定 step，每只 2 次 rand |
| objmSetAddSpeed（10，0x40556f） | step, max | 0x42fb50：+0x34=step，+0x84=max；+0x88 置 0x8，清 0x1070（点移/减速/X/Y 加速）。积分器每帧 speed=min(speed+step, max) 并重算速度向量。续 |
| objmSetSubSpeed（11，0x405591） | step, min | 0x42fb80：同上，置 0x10、清 0x1068；每帧 speed=max(speed−step, min)。续 |
| objmSetAddYSpeed（13，0x4055d5） | step, 界 | 0x42fbe0：置 0x40、清 0x1038；每帧 vy(+0x48) += step，step≥0 时上限夹到界，step<0 时下限夹到界（直接改速度向量，不动 +0x38/+0x3c）。续 |
| objmSetStopSpeed（14，0x4055f7） | — | 0x42f880(obj,0)：+0x38=0，并清 +0x88 bit0（基点停止随速度移动；加减速位不清）。续 |
| objmAddRandomSpeed（15，0x405d3b） | r | speed(+0x38) += rand(r)，经 0x42f880 写入（非 0 不改 bit0），0x42f940 重算速度向量。续 |
| objmSetSpeed（16，0x4059fb） | angle, speed | 0x42fae0：+0x88 置 bit0；angle≠−1 写 +0x3c，speed≠−1 写 +0x38；0x45eb9d 算 vx=cos·speed>>16→+0x40，vy→+0x48，清小数累加 +0x44/+0x4c。续 |
| objmSetRoundMove（17，0x405606） | angle, radius, step | 0x42fc60：+0x88 置 0x100；+0x94=radius，+0x98=angle，+0x9a=step，+0x50/+0x52 位移清零。angle=−1 时取全局 0x4c1410 旧值，并把 0x4c1410 在 0/128 间翻转（相继实例交替 0°/180°）。续 |
| objmSetRoundMoveFlag（18，0x40564e） | — | 0x42fc60(obj,−1,−1,−1)：只置 0x100、清 XY 位移，保留半径/角/角步。续 |
| objmSetRoundXYShift（19，0x405662） | xs, ys | 0x42f8c0：+0x52=xs，+0x50=ys；绕圈偏移 dx>>=xs、dy>>=ys（>31 则该轴为 0，成直线）。续 |
| objmSetRoundPos（20，0x405684） | angle, radius | 0x42f960(obj, radius, angle)：置 0x100；非 −1 才写 +0x94/+0x98；**立即**把 x/y 定为 基点+极坐标偏移（带位移）。续 |
| objmSetRoundRadiusStep（21，0x4056a6） | step | 0x42fb30：+0x9c=step，置 0x200。续 |
| objmSetRandomInvAngle（22，0x405af0） | — | a=rng&0xff（0x458c10 原始数）；若 \|a−[0x4c1414]\|<6（线性差，不绕圈）则 a=a+128；[0x4c1414]=a；写移动角 +0x3c 并重算速度向量（0x42f8a0+0x42f940）。续 |
| objmSetRandomInvAngleShape（23，0x405b35） | n | a 同上但阈值 256/n；[0x4c1414]=a；**只改帧**：+0x30=+0x32+min(a/(256/n), n−1)，不动移动角。n=0 时帧=首帧。续 |
| objmSetAngleShape（24，0x405bbd） | n | 取绕圈角 +0x98（0x42fa50），k=angle/(256/n)；+0x30=+0x32，暂把 +0x7c 置 0 后调 0x45e575 k 次再还原（+0x7e≠0 时只保证走第一步，未读清）。续 |
| objmSetRoundRandomInvAngle（25，0x405c2f） | — | a 同 22（阈值 6，写 0x4c1414），写绕圈角 +0x98（0x42f8e0）。续 |
| objmAddRoundAngleStep（26，0x4056be） | d | 0x42f920：+0x9a=max(0, +0x9a(无符号字)+d)。续 |
| objmSetRandomRadius（27，0x4056d6） | base, range, s1, s2 | r=rand(range，0 当 0x10000)；+0x94=base+r；+0x9a=s1+((r/((range/\|s2−s1\|)>>16))>>16)（≈按 r 在 s1→s2 线性插值）。不置 0x100。续 |
| objmSetAngleRange（28，0x405c7e） | r1, r2 | a=(r1+rand(\|r2−r1\|))&0xff；[0x4c1414]=a；写移动角 +0x3c 并重算速度向量。续 |
| objmMapAngleRange（29，0x405cc4） | r1, r2 | c=当前移动角；若 r2≥256 且 c<128 则 c+=256；c 在 [r1,r2] 内不变，否则 c=(r1+(r2−r1)·(c&0xff)/256)&0xff；写回并重算速度向量。无随机。续 |
| objmSetPointMove（30，0x4061b7） | x, y, 阈值, 最大步 | 目标 x=(x==−1? 本对象 +4 : x+镜头 0x4c091c)，y 同理（0x4c0920）；0x42fc10：+0x86=tx，+0x84=ty，+0x36=阈值，+0x34=最大步（字）；置 0x1000，清 0x78。**让** |
| objmRandomNextShape（32，0x405ed0） | — | k=rand(+0x7a 总帧数)，调 0x45e5a6（循环前进一帧）k 次。让 |
| objmSetShape（33，0x405f11） | disp | +0x32 += disp，+0x30=+0x32（首帧永久后移）；+0x78=+0x7a，+0x7c=+0x7e（帧计数复位）。让 |
| objmRandomShape（34，0x405759） | — | +0x30=+0x32+rand(+0x7a)。续 |
| objmProcNextShape（35，0x405775） | total, delay | +0xa2=1（单次播放）；total>0 写 +0x78/+0x7a，delay>0 写 +0x7c/+0x7e（−1 保留对象定义值）。**续** |
| objmProcNextShapeDelete（36，0x405f44） | total, delay | 相位 98（空等），+0xa2=4：单次播放完毕 → 置混合位、级 16、+0x68=0x20002、相位 99 → 每 2 帧级 −1，到 0 销毁（约 32 帧）。让 |
| objmNextShapeInvDelete（37，0x405f6f） | total, delay | 同 36，但 +0xa2=5 用 0x45e5d9（反向/往返步进，未读清细节）。让 |
| objmCircleProcNextShape（38，0x405f9e） | total, delay | +0xa2=2：0x45e5a6 循环播放（到尾减 +0x7a 回首帧）。让 |
| objmCircleNextShapeInv（39，0x405ff2） | total, delay | +0xa2=3：0x45e5d9 循环（+0x7d 方向字节，往返/反向，未读清）。让 |
| objmCircleProcNextShapeStep（40，0x406046） | — | 相位 40：每帧调 0x45e5a6，等帧号变化（前进一帧）后清相位。让 |
| 〃 帧步进 0x45e575 | — | +0x7c 减 1，<0 时重装 +0x7e、帧+1、剩余 +0x78 减 1；剩余到 0 停在末帧并返回 1。即每 delay+1 帧走一格 |
| objmStopZoom（42，0x4057be） | — | +0x10（X 缩放步）、+0x18（Y 缩放步）、+0x1c（缩放效果）清零。续 |
| objmSetZoomEffect（43，0x4057cc） | lv | 标志 0x8000000；+0x1c=lv<<16（低字计数、高字上限 lv）；缩放为 0 的轴置 1.0；+0x5c/+0x60=基准缩放。尾段每帧计数+1，超过 lv 跳到 −lv（锯齿），z=基准+计数·(1/128)，下限 1/64。续 |
| objmZoomOutIn（44，0x405810） | start, step | 标志 0x8000000；start≠−1 则 zx=zy=start；+0x10=+0x18=step。尾段：step>0 每帧 z+=step，z>8.0 且 step<16.0 时 step+=0x4000（加速）；step<0 每帧 z+=step，结果 ≤0 则不写（停在最后正值）。续 |
| objmXZoomOutIn（45，0x405842） | start, step | 只 X：start≠−1 写 zx，zy 为 0 则置 1.0，+0x10=step。续 |
| objmYZoomOutIn（46，0x40587a） | start, step | 只 Y：写 zy，zx 为 0 置 1.0，+0x18=step。续 |
| objmInsertShadowDelay（49，0x405940） | lv, fade, gap | +0x6c=(lv<<16)+fade（lv bit31→高字 bit15），+0x74=gap\|gap<<16。尾段每 gap 帧在本帧积分前的位置、用本帧开始时的帧号生成残影对象（code 0x191）：复制 +0xc、置混合位、级=min(lv&0xff, 本对象级)、bit15→子 +0x94=1、子 +0x90=fade。残影对象自身行为未读。续 |
| objmInsertShadowChange（50，0x405987） | lv, fade | 同上但 +0x74=0：仅在本帧帧号变化时生成。续 |
| objmPlaySound（51）/PlayHitSound（52） | id | 放声（52 仅命中才放，见对象声音包）。续 |
| objmWaitSpeedBelow（53，0x4060f2） | v | 相位 53，+0xa8=v；每帧 speed(+0x38)≤v 时放行。让 |
| objmWaitOutScreen（55，0x406209） | — | 相位 55；每帧 0x405140≠0（x 或 y 出 640×480，含 SHP 尺寸）放行。让 |
| objmWaitSmallerX（56，0x4060f2） | x | 每帧 (x−镜头x)≤arg 放行（屏幕坐标）。让 |
| objmWaitLargerY（59，0x4060f2） | y | 每帧 (y−镜头y)≥arg 放行。让 |
| objmWaitSmallerZoom（60，0x406119） | z | zx≤z 或 zy≤z 即放行。让 |
| objmWaitLargerZoom（61，0x4060cb） | z | zx≥z 或 zy≥z 即放行。让 |
| objmWaitRadiusBelow（62，0x4060f2） | r | 半径 +0x94≤r 放行。让 |
| objmWaitRadiusAbove（63，0x406119） | r | 半径 +0x94≥r 放行。让 |
| objmWaitFadeOut（64，0x406209） | — | 等级 +0x28==16（即 67 的「淡现」完成）。让 |
| objmWaitShapeEnd（65，0x406140） | — | 等 +0xa2==0（35 单次播放结束）。让 |
| objmWaitPointMove（66，0x406209） | — | 等 +0x88 bit 0x1000 清除（点移到达）。让 |
| objmFadeOut（67，0x405a1d） | d | **命名与直觉相反：淡现**。置混合位（无加/减色则置 0x4000000 加色位），级=0，目标 +0x68=16，+0x70=d\|d<<16。尾段每 d 帧级+1，到 16 停（有加/减色位时清混合位）。续 |
| objmFadeOutLevel（68，0x405a69） | d, max | 同 67 但目标级=max。续 |
| objmFadeIn（69，0x406157） | d | **淡出并销毁**：相位 99，置混合位，级为 0 则置 16，+0x68=d\|d<<16；每 d 帧级−1，到 0 销毁（0x45e3ed）。让（程序实际终止） |
| objmSetData（70，0x405aba） | lv | +0x28=lv；lv==16 且有加/减色位则清混合位，否则置混合位。续 |
| objmInitMultiHitData（71）/SetMultiHitData（72） | — | 多段结算计数（见对象声音包）。续 |
| objmBGScroll（73，0x406220） | w, h, d | 相位 73；取帧尺寸（0x4606a9）存 +0x14/+0x16/+0xa8/+0xaa；+0xa0=d（≥1）；+0xae/+0xac=w/h 向上取整到帧尺寸倍数（0 则 640/480）。相位处理 0x40658f：x/y 相对镜头越界就按平铺尺寸回绕，基点同步；+0xa0 减到 0 后按相位 99 方式每 2 帧级−1 淡出销毁。让 |
| objmSaveCommandPos（74，0x405d86） | — | +0x14=指向下一条命令的指针。续 |
| objmLoopCheckOutScreen（75，0x405d8b） | — | 0x405140==0（仍在屏内）且 +0x14≠0 → 指针跳回保存点；否则顺延。随后**本帧继续解释**，循环体必须含让出命令 |
| objmLoopCheckSmallerY（76，0x405da3） | y | 世界 y（不减镜头）>arg 且有保存点则跳回；y≤arg 顺延。续 |
| objmLoop（77，0x405db3） | — | 有保存点则无条件跳回。续 |
| objmLoopCounter（78，0x405dbe） | n | 计数 +0x56：为 0 时置 n 并跳回（n=0 则不跳）；否则减 1，>0 跳回，到 0 清零顺延。回跳 n 次，循环体共执行 n+1 遍。续 |
| objmDragonWaveMove（79，0x406321） | angle, throwDelay, changeDelay | 相位 79；+0x14=angle，+0x5c=throwDelay，+0x60=changeDelay\|<<16。相位处理 0x4066d6：每 throwDelay 帧 `0x401390(x,y,+0x54+1,0,0,0,0,1)` 放一只子对象并按 +0x16 偏移子首帧；每 changeDelay 帧按 +0x16 在帧序列中来回扫并改移动角（±0x40/n 步），出屏（0x405140≠0）即销毁。细节未读清。让 |

### 积分器 0x42fcb0（+0x88 标志位，static-derived）

每帧先把 x/y 清零，最后 x=基点 +0x92（字）+ 绕圈偏移，y=基点 +0x90 + 偏移。基点即创建点（0x42fab0 初始化），随速度/点移累加。

| 位 | 设置者 | 每帧更新 |
|---|---|---|
| 0x1 | SetSpeed（0x42fae0）；StopSpeed 清 | 末尾 0x45ebdc：基点 += (vx+小数累加)>>16、(vy+…)>>16，小数存 +0x44/+0x4c 低字 |
| 0x2 | objcomd 不设 | 移动角 += (byte)+0x3e |
| 0x4 | objcomd 不设 | speed += +0x34（无夹），重算速度向量 |
| 0x1000 | SetPointMove | 0x45e80d(基点, 目标 +0x86/+0x84, 阈值 +0x36, 最大步 +0x34)：两轴距离都 ≤阈值则吸附到目标、清 0x1000；否则每轴步 = clamp((目标−基点)>>1, ±最大步)（先匀速后对半缓入）。此位存在时跳过 0x8/0x10/0x20/0x40 |
| 0x8 | SetAddSpeed | speed=min(speed+step,max)（0x45eb75），重算速度向量 |
| 0x10 | SetSubSpeed | speed=max(speed−step,min)（0x45eb89），重算 |
| 0x20 / 0x40 | SetAddX/YSpeed | vx(+0x40)/vy(+0x48) += step，按 step 符号夹到 +0x84 |
| 0x80 | objcomd 不设 | 追踪 +0x2c 号目标（表 0x4c34c0）：按 +0x3e 步转向；目标不存在则**销毁自身** |
| 0x100 | SetRoundMove/RoundPos/RoundMoveFlag | 0x45e9bc：偏移 = (cos/sin[+0x98]·半径 +0x94)>>32（用旧角），再按 +0x52/+0x50 右移；然后 +0x98 = (角+角步 +0x9a)&0xff |
| 0x200 | SetRoundRadiusStep | 半径 += +0x9c；结果 ≤0 时（步<0 则半径置 0）清 0x200 |

淡变（+0x70/+0x68，尾段 0x406381）与缩放（尾段 0x4068e3，对象标志 0x1000000 时跳过）不在积分器内，见表一 67/68/69/43/44。

销毁时机：相位 99（Over、FadeIn、36/37 帧放完）级减到 0；BGScroll 计数完后淡到 0；DragonWave 出屏；积分器 0x80 目标丢失；场景拆除 0x4c1404 bit0。**普通对象出屏不自动销毁**，靠 WaitOutScreen/LoopCheckOutScreen 之后的 Over/FadeIn（程序末尾是否由编译器补 0，未读清）。

### 圆心、目标点与多实例相位（static-derived）

- 绕圈圆心 = 基点 +0x92/+0x90，即对象自己的创建点（插入延迟结束时锁定），若同时有速度（bit0）或点移则圆心随之移动。
- 点移目标 = 参数+镜头（屏幕坐标转世界），−1 表示取对象当前 x/y。
- 多实例错开只来自：共享 RNG 流（0x458c80/0x458c10）的抽取（生成器的位置/延迟、RandomDelay、各随机角/速/帧/半径）；全局 0x4c1414「上一随机角」防重复（差 <6 或 <256/n 则翻 180°）；0x4c1410 让 SetRoundMove angle=−1 的相继实例交替 0/128。没有按实例序号的字段（生成器只串链 0x45e485，不写序号）。

### 原指令执行（static-derived）

`hsltools/probes/objcomd_motion.py` 复用效果对象探针（[效果对象运动包](original_effect_motion.md)）的机器与帧模型：过程表放行槽 37（`0x4051d0`）与抛出物用的槽 38（`0x4050a0`，淡出计数到 0 销毁），已审阅代码加入 `0x401390..0x401559`（两个生成器）、`0x4050a0..0x4051c6`（槽 38 与出屏判定 `0x405140`）、`0x4051d0..0x406bc8`（解释器）、`0x42f880..0x42ffe7`（运动设置与积分器）。命令程序按 objcomd.txt 逐 token 一字写进合成表 `[0x4c1b74]`。每个对象在它在脚本里的首个插入点创建（`0x405140` 按 640×480 与 SHP 尺寸判定出屏，结果依赖绝对位置），记录每帧相对创建点的位置、SHP 成员、eng* 模式、层级与缩放。

- 221 个对象全部跑完，没有停在未审阅代码；4 个对象（Special06_01／13_06／14_01／15_01）在 600 帧内没有出口，标 `open_ended`，重制随特写结束。
- 用到随机的程序跑 4 个种子，结果与种子 0 相同的只留一份：共 509 棵变体树。

读回（`OBJCOMD_ARROW_READBACK`，毒魔箭箭矢 obj_Special19_01，命令 17 `objmDelay 20 · objmSetSpeed 128,0x00200000 · objmDelay 10 · objmWaitOutScreen`）：创建帧不画，第 1..21 帧停在 (680,160)，第 22 帧起每帧 x −32（t22 = 648、t32 = 328、t33 = 296），与手算逐帧一致；`check objcomd_motion` 对整条轨迹逐样本比对这个模型。月花圓舞 花瓣（命令 10 `objmSetSpeed 80,0x00080000`）首步 (−4, +7)，手算 8·(cos, sin)(80/256 圈) = (−3.1, +7.4)，差在 16.16 取整。

### 剧情对象（static-derived）

剧情脚本插入的 `defProcObjectMove` 对象（各关 map_objects 的 script_objects，12 关 19 个）走同一解释器。探针用本关 obj-0xx.obs 模板（`obj_Mode`／`obj_Zoom*`／`obj_Data9` 照写，OBJ-0xx.H 解析对象符号）在原点创建，逐 tick 执行 obj_Data7 选中的程序；程序 5 带 objmRandomDelay，跑 4 个种子。键名 `符号@关号`，37 关两条保留裸符号。

| 程序 | objcomd.txt | 对象（关） | 原指令轨迹 |
| --- | --- | --- | --- |
| 5 | objmRandomShape · objmRandomDelay 8 12 · objmFadeIn 2 | 閃電 AIR14_01／AIR14_05（010）、消失岩石 39_ROCK002（039，模板 obj_Data9 0x00020000） | 不动；閃電 模板 engZOOM 2.0 倍，整幅加色 8–14 tick（4 个种子），再加 engMIX 16→1 每 2 tick 一级，tick 41–47 删除；消失岩石 无缩放，tick 2 起画，同样加色后 32 tick 淡出，tick 42–48 删除 |
| 7 | objmZoomOutIn 0x400 0x2000 · objmWaitLargerZoom 0x120000 · objmFadeIn 2 | 光環 EAR32_01（010，模板 engADDCOLOR_MIX、obj_Data 6） | 不动；缩放 0.2656 起加速放大，过 18 倍即淡出（删除前 68 倍）；全程 engZOOM｜engADDCOLOR｜engMIX，级数 6 保持 74 tick，再 5→1 每 2 tick 一级，tick 85 删除 |
| 13 | objmZoomOutIn 0x1000 0x800 · objmWaitLargerZoom 0x30000 | 白光圈（080）、黑光圈（080，模板 engSUBCOLOR） | 不动；缩放 0.125 起每 tick +0.03125，到 3 倍后淡出 32 tick（16→1 每 2 tick），tick 127 删除；白光圈加色，黑光圈减色 |
| 21 | objmZoomOutIn 0x1000 0x3000 · objmWaitLargerZoom 0x10000 | 白光（022、028、037、059、076、077、079）、白光2（079） | 同 [37 关白光](original_level37_tokens.md)：0.4375 起每 tick +0.1875，加色 5 tick 后淡出，tick 38 删除；79 关白光贴图 AIR16_01，轨迹相同 |
| 62 | objmZoomOutIn 0x1000 0x1000 · objmWaitLargerZoom 0x18000 · objmStopZoom · objmSetZoomEffect 4 · objmDelay 80 · objmFadeIn 3 | 白光2（037、059） | 同 37 关白光2，tick 153 删除 |
| 149 | objmRandomShape · objmSetSpeed 186 0x40000 · objmSetAddYSpeed 0x6000 0x80000 · objmDelay 32 · objmSetStopSpeed · objmFadeIn 2 | 徽章 AIR06_04（058，obj_ReadShape 1） | 向左上抛出再下落（tick 1 (−1,−4)，最高 −19，落到 (−20,+79) 停下）；加色，停下后 32 tick 淡出，tick 65 删除 |
| 150 | objmSetSpeed 64 0x40000 · objmDelay 64 · objmSetStopSpeed · objmDelay 160 · objmFadeIn 2 | 繩子 53_ROPE001（053，模板 engRANGE） | 每 tick 向下 4 px，tick 65 停在 +260；再停 160 tick 后加色淡出 32 tick，tick 258 删除 |
| 151 | objmZoomOutIn 0x1000 0x1000 · objmWaitLargerZoom 0x40000 · objmFadeIn 3 | 白光（013，obj_Story_Level_WhiteScreen） | 不动；0.1875 起每 tick +0.0625，加色 63 tick 后淡出 48 tick（16→1 每 3 tick），tick 112 删除 |

17 条新轨迹全部在 600 帧内删除，没有停在未审阅代码；原 221 条绝技对象与 37 关两条的轨迹、members 前 511 项不变。

### 命中趟（static-derived）

命中才掷出的子对象（`0x405434`／`0x405495`）与 objmPlayHitSound 同样比较命中判定 `[0x4c1418]` 与命中率 `[0x4c6f58]`（[对象声音包](original_effect_object_sounds.md)）。探针对每个保留的种子变体再跑一趟 `[0x4c1418]=0 < [0x4c6f58]=1`，与落空趟不同时写进 `hit_variants`（同种子、同变体序号）与 `hit_frames`；命中趟在全部落空趟之后编码，新 SHP 成员接在 `members` 表尾，落空趟 `variants` 与原 members 逐字节不变。

240 个对象里 17 个两趟不同，每个都是主对象轨迹不变、落空趟的实例全部原样出现在命中趟里，只多出命中才掷出的子对象（多出的 14 个 SHP 由 `skill_effects` 导入）：

| 绝技（命令行） | 对象 | 命中趟多出 | 帧数 落空→命中 |
| --- | --- | --- | --- |
| 慌雨斬（magicCode01／05） | Special04_02、62_02 | 25 个子对象（代码 482／483） | 60→105 |
| 慌雨斬（magicCode01／05） | Special04_03、62_03 | 51 个（482／483） | 60→141 |
| 無想冥殺（magicCode03） | Special06_06 | 10 个（462／642） | 186→206 |
| 星辰落牙破（magicCode04） | Special24_02 | 24 个（548） | 63→85 |
| 殘影亂斬（magicCode15／31） | Special30_01..04、56_01..04 | 24 个（401／560／561） | 50→78 |
| 殘影亂斬（magicCode15／31） | Special30_05、56_05 | 38 个（560／561） | 42→71 |
| 血之宴（magicCode26） | Special50_01 | 1 个（621） | 35→54 |

多段绝技（守方 `aniProcessHitMissMulti`）每个 op 72 经 `0x4047e9` 结算一段、各写一次 `[0x4c1418]`（先清 0，本段无变化改 200），带 op 72 的主对象都由不看命中的插入放出，命中趟不改段数；帧循环 `0x45f5f7` 先跑守方（planeEffect3）再跑这些对象（planeEffect4 或同 plane 链尾），所以对象在 tick t 读到的是 t 及以前最后结算的一段；读字在程序第一个命中声那一帧（抛子对象紧接在它之前）。多数对象 op 72 后 2 帧读字、守方空闲时下一 tick 就结算，读到本段；守方正忙（殘影亂斬 的 Special30_03 在上一段 3 tick 节拍内）时读到上一段。慌雨斬 与 無想冥殺 的 4 个种子变体各有命中趟；殘影亂斬 的 Special30_01..04 在命中趟里子对象出现顺序与落空趟不同（命中火花先建），落空趟的淡出子对象（401）仍在。

多段绝技的判定读法：`aniProcessHitMissMulti`（`0x4047c7`）等 `0x4c6f68` 非零才减一并落入单击结算体 `0x4047e9`，结算体每次先写 `[0x4c1418]=0`（`0x404803`），本段没有造成 HP／MP 变化（`0x4c6f74`／`0x4c6f78` 与 ebp 均为 0）时改写 200（`0x4048d6`）——命中判定每段改写一次，命中率 `0x4c6f58` 只由守方插入 `0x406eb0` 写一次。

### ANIMAL 随机插入（static-derived）

ANIMAL 解释器 `0x4038a0` 在 `0x40397c` 按字节表 `0x404f48[op]` 取下标、跳 `0x404ee8[下标]`。脚本 x／y 是屏幕点，除 op 28 外都先加镜头 `[0x4c091c]`／`[0x4c0920]`。下表的对象都在执行那一 tick 由 `0x45e307` 建出，出现时刻挂在子对象的插入延迟 `+0xae` 上（换算见表后「开跑时刻」）：

| op（处理体） | 参数 | 读法 |
|---|---|---|
| 19 aniInsertRandomObject（`0x403aaa`） | code, x, y, xr, yr, delay, num | 转入 `0x403c17`，无条件在 `0x403c2b` 调 `0x401390(x, y, code, xr, yr, 0, delay, num)`。续 |
| 23 aniInsertRandomObjectDelay（`0x403b25`） | code, x, y, xr, yr, base, delay, num | 无条件调 `0x401390(x, y, code, xr, yr, base, delay, num)`。续 |
| 24 aniInsertRandomObjectFixDelay（`0x403b73`） | 同 23 | 无条件调 `0x401480(x, y, code, xr, yr, base, delay, num)`。续 |
| 25 aniInsertDistanceObjectFixDelay（`0x403ad7`） | code, x, y, xdisp, ydisp, base, delay, num | 无条件调 `0x401560(x, y, code, xdisp, ydisp, base, delay, num)`。续 |
| 26 aniInsertRoundRandomObject（`0x403ddb`） | code, x, y, radius, xshr, yshr, delay, angle, num | 不调生成器，见下。执行完写回指针并让出（`0x403e90` → `0x404ba6`），下一条指令在下一 tick 执行 |
| 27 aniInsertHitRandomObject（`0x403bc1`） | 同 19 | 仅当 `[0x4c1418] < 解释器对象 +0xa6`（字，`0x403c0f`）才调 `0x401390(…, 0, delay, num)`；未命中不抽随机。续 |
| 28 aniInsertHitRandomObjectDisp（`0x403be2`） | code, xdisp, ydisp, xr, yr, delay, num | 基点 = 守方解释器对象自身的 `+4`／`+8` 加位移，不加镜头；命中条件与调用同 27。续 |
| 29 aniInsertHitRandomObjectFixDelay（`0x403c3b`） | 同 23 | 命中条件同 27（`0x403c6e`），命中才调 `0x401480(…, base, delay, num)`。续 |

- 生成器 `0x401390`：num=0 直接返回。每只 dx=rand(xr)，大于 xr/2（向零截断）则 dx=xr/2−dx，即折进 (−xr/2, xr/2]；dy 同理用 yr；建对象后子 `+0xae` = 累计延迟 d。d 初值为第 6 参 base，每只之后 d += rand(delay)+1（`0x401455` `lea ebp, [eax+ebp+1]`）。每只 3 次 rand（dx、dy、延迟），建对象失败也照抽照加。
- 生成器 `0x401480`：偏移同上，子 `+0xae` = d，d 初值 base，每只之后 d += delay（`0x40153a`，固定步长）。每只 2 次 rand。
- 生成器 `0x401560`：无随机。第 k 只（从 0 数）在 (x＋k·xdisp, y＋k·ydisp)，`+0xae` = base＋k·delay。
- op 26：个数 n，n=0 当 1，n<0 不建。角度 16.16（256 一圈）从 angle<<16 起，每只加 0x1000000/n（`idiv`）。`0x45ea2b` 取表下标 (角>>16)&0xff，偏移 = 表项符号 × ((|表项|×radius)>>16>>16)（cos 表 `0x4a35fc`、sin 表 `0x4a39fc`，radius 为 16.16）；x 偏移再算术右移 xshr、y 偏移右移 yshr（`0x403e30`／`0x403e3b`，为 0 不移）。第 k 只 `+0xae` = k·delay。名字里有 Random，处理体里没有 rand。
- 开跑时刻：`0x45e353` 建对象时置 `+0x80` 的初始化位，子对象首次被调用走 defProcObjectMove `0x4051d0` 的初始化分支：程序首字为 op 71 时 `0x40524d` 计数（不再看 op 2），首字为 op 2 objmRandomDelay 时 `0x40525b..0x405287` 把 a＋rand(b) 加进 `+0xae`；随后 `0x405294` 先把 `+0xae` 减一、`0x40529b` 再与 0 比，大于 0 置 `0x10000000` 返回、以后每次调用同样先减后比，小于等于 0 就在同一次调用里接着跑程序。所以 `+0xae` = d 的对象从首次调用起晚 max(d−1, 0) tick 开跑：0 与 1 同在首次调用；`0x401390` 的第 k≥1 只（d ≥ 1）晚 d−1，op 23／24／29 的第一只晚 max(base−1, 0)，op 25／26 的第 k 只同理。首字为 op 2 的程序原生轨迹里已含 max(r,1)−1 的等待，与 d 合并为 max(d＋r,1)−1；这些插入放的对象程序都不以 op 2 开头（objcomd 只有程序 66 如此）。
- 60 行绝技脚本里：op 23 出现 48 次、24 出现 67 次、25 出现 5 次、26 出现 2 次（萬息秘孔術 两圈各 16 只，radius 0x00c60000／0x00f60000，yshr 2，delay 3）、28 出现 5 次（都在月花圓舞）、29 出现 11 次。月花圓舞的 64 片花瓣（op 19，延迟 6）约 220 tick 陆续落下，不是一次撒出。

r2（`hsl01.exe`）：`pd 30 @ 0x4051d0; pd 40 @ 0x405230; pd 8 @ 0x45e353`（首次调用与先减后比），`pxw 0x60 @ 0x404ee8; pxw 0x24 @ 0x404f48`（跳表与字节表），`pd 30 @ 0x403aaa`、`pd 70 @ 0x403b25`（op 19／25／23／24）、`pd 45 @ 0x403bc1`（op 27／28 与 `0x403c2b`）、`pd 30 @ 0x403c3b`（op 29）、`pd 70 @ 0x403ddb`（op 26）、`pd 40 @ 0x45ea2b`、`pd 62 @ 0x401390; pd 22 @ 0x401422`、`pd 56 @ 0x401480; pd 24 @ 0x401506`、`pd 70 @ 0x401560`。

### 角度环与龙卷列：op 20／21／22 的逐实例初值（static-derived）

三者都在执行那一 tick 建完全部实例、不让出（跳回 `0x403968`），x／y 先加镜头。

| op（处理体 → 插入器） | 参数 | 读法 |
|---|---|---|
| 20 aniInsertAngleObject（`0x4039c4` → `0x401600`） | code, x, y, n, delay, step | n=0 不建；n<0 取 −n 并记负号。角步 = 0x1000000/n（16.16，`0x401637`）。第 k 只由 `0x45e307(x, y, code, 0)` 建在同一点，`0x45e485` 串链，`+0xae` = delay＋k·step（`0x401690`）；未记负号时 SHP 帧 `+0x30` 加 k（`0x4016a4`）；角 a = (k·角步>>16)&0xff，`0x42fae0(obj, a, 0)` 写移动角 `+0x3c`、速度 `+0x38` = 0，`0x42fc60(obj, 0, a, 0)` 写绕圈半径 `+0x94` = 0、角 `+0x98` = a、角步 `+0x9a` = 0。没有 rand |
| 21 aniInsertAngleObjectMakeShape（`0x403a0a` → `0x401730`） | 同 20 | n=0 或造型缓存数 `[0x4c6f6c]` ≥ 5 时整条一只都不建（`0x401755`／`0x40175b`）。角步 = 0x1000000/n（`0x40176e` 直接 `idiv`，没有 op 20 的取反与负号，n<0 不处理）。第 k 只 `0x45e307(x, y, code, 0)` 建；只有首只（`0x4017bf` 查标志、`0x4017cb` 置 1）进造型分支：先按源帧 `+0x30` 在缓存表 `0x4c6f80..0x4c6fa8` 查（`0x4017a2`–`0x4017b8`），没有才 `0x460541(n)` 取 n 个槽并登记（`0x4017fb`／`0x401802`），经 `0x4602d4` 解出源图，用 `0x45f141` 一次旋转出 n 张（角步 256/n，`0x401842`；循环 `0x401858`–`0x4018a1`），`0x457c20`／`0x45f4b9` 收尾、缓存数加一；其后各只走 `0x4018c6`。`0x45f141` 用 cos／sin 表 `0x4a35fc`／`0x4a39fc` 做单位旋转（`0x45f15e`／`0x45f165`），没有缩放。每只 `0x45e485` 串链，`+0xae` = delay＋k·step（`0x4018f2`），`+0x30` = 槽基址＋k（赋值，`0x401912`），`+0x32` = 槽基址（`0x401916`），然后 `0x42fae0(obj, a, 0)`，a = (k·角步>>16)&0xff。不调 `0x42fc60` |
| 22 aniInsertTornadoObject（`0x403a50` → `0x401990`） | code, x, y, y 步长, 半径, 半径步长, 起始角, 角步, 起始缩放, 缩放步长, n | n=0 不建。每只 `0x45e307(x, y, code, 0)` 建、`0x45e485` 串链，抽 rand（`0x458c80`，`0x45e5a6` 定帧）；`0x42fc60(obj, 半径, 角, 角步)`（`0x401a2f`）写绕圈半径 `+0x94`、角 `+0x98`、角步 `+0x9a`；`0x42f8c0(obj, 0, 0x20)`（`0x401a39`）写 `+0x52` = 0、`+0x50` = 0x20（同 objmSetRoundXYShift(0, 32)：绕圈偏移只剩水平分量）；起始缩放非零时写 `+0x20`／`+0x24` = 缩放并置 `+0` 位 0x8000000（`0x401a41`–`0x401a5f`），起始缩放为 0 则全列不写。逐只递增：缩放 += 缩放步长、下限 0x800（`0x401a51`–`0x401a63`，仅起始缩放非零时）；角 = (角＋角步)&0xff（`0x401a70`／`0x401a74`）；半径 += 半径步长、下限 0x10000（`0x401a72`–`0x401a86`）；y += y 步长（`0x401a8b`–`0x401a99`）；建失败的那只不递增（`0x4019da`）。不写 `+0xae`（没有延迟） |

角度与速度的真正取值在对象自己的 objcomd 程序里：程序按预置的 `+0x3c`／`+0x98` 设速度或绕圈半径（無想冥殺 的 Special06_06 由 `objmSetRoundPos` 自设半径 170 px）。

原指令执行：`objcomd_motion.py` 的 `PATTERN_ROWS` 目前只含 無想冥殺（`special:magicOTHER:magicCode03`），已审阅代码加入 `0x401600..0x401708`；每条 op 20 插入按脚本原字以 `op:code,x,y,n,delay,step` 为键，镜头 (0,0)、从插入点直接调 `0x401600`，逐 tick 跑到全部实例结束，按建出次序把每只拆成一个变体写进 `patterns`（与 `objects` 同列式：`variants`／`sounds`／`multi_hit`，命中趟不同时另有 `hit_variants`／`hit_frames`）。n 只共用一条 RNG 流（种子 0），`+0xae` 的等待已在轨迹里。三个键：Special06_03（n=−32）、06_05（n=−8）、06_06（n=8），共 48 只；06_06 的 8 只各在命中趟多出火花子对象。240 个 `objects` 逐字节不变；新增的 SHP 成员 `MAGIC\SP06_013.SHP` 来自 Special06_03 落空趟（n=−32）的 objmRandomShape——32 只共用一条流时抽到它（06_06 的帧 +k 被 objmSetAngleShape 覆盖，不产生新成员），接在 `members` 表尾。改前 06_03／06_05 两个环（n<0）一只都不画（旧几何按 n 循环，负数为空），现在按原生 |n| 只画出 32＋8 只。

r2（`hsl01.exe`）：`pxw 0x60 @ 0x404ee8; px 0x24 @ 0x404f48`（op 20／21／22 的下标）、`pd 90 @ 0x4039c4`（三个处理体）、`pd 80 @ 0x401600`、`pd 175 @ 0x401730`、`pd 20 @ 0x45f141`、`pd 150 @ 0x401990`、`pd 8 @ 0x42f8c0`、`pd 30 @ 0x42fc60`、`pd 30 @ 0x42fae0`。

## 重制接线

- `game/battle/scene/ObjcomdMotion.gd` 读 `objcomd_motion.json`（与 `EffectObjectMotion` 同列式，`sprites_at` 共用）。
- `SkillEffectScriptPlayer._finish_timeline`：有轨迹的普通插入（原 `static`／`fly`）改为 `native`，从插入 tick 起逐帧画整棵树，位置 = 插入点＋轨迹偏移；同一对象的重复插入轮流取种子变体；`open_ended` 对象到片段结束。角度环（aniInsertAngleObject*）有 `patterns` 行时（`ObjcomdMotion.pattern_key(op, 前 6 字)`）逐实例建原生事件（`track` = 键、`variant` = 实例序号），帧数、轨迹、声音、多段数都按该实例取，落在插入 cursor 上（`+0xae` 已在轨迹里）；没有行的角度环与龙卷列（aniInsertTornadoObject）保留原几何。`_insert_spawner` 按 `0x401390`／`0x401480` 放置 op 19／23／24／27／28／29（base delay、累加或固定步长），各插入的 `+0xae` 经 `_insert_delay`（max(d−1, 0)）换成开跑 tick，`_insert_pattern` 按 `0x401560` 放 op 25，`_insert_round` 按 `0x403ddb`／`0x45ea2b` 放 op 26 并让下一条指令晚 1 tick；op 28 编译时以中性锚点＋aniSetXYDisp 为基点，`_place_on_defender` 在播放时按插入 tick 的守方精灵位置（`_defender_point`：双页 480、击退／闪避）平移。
- 命中趟：`ObjcomdMotion.track／frames／sprites_at` 的 `hit` 取 `hit_variants`；`SkillEffectScriptPlayer` 的原生插入按片段 `timeline.hit`（结算收据 `strike.hit`）选用，落空不画命中才掷出的子对象。
- `PoisonArrowPresentation`：箭矢与命中火花走原生轨迹；受方段画在地图上，舞台偏移（相对舞台目标中心 (320,160)）按精灵缩放缩小——构图是重制的。
- `MoonDancePresentation`：64 片花瓣与每脉冲一个爆点走原生轨迹，放置按 `0x401390`；爆点基点取守方精灵锚点。
- `StoryEffectObjects`：剧情 `defProcObjectMove` 对象（`native_track` 按 `符号@关号` 与本关 obj-0xx.obs、对象代码、obj_Data7 取轨迹）每次插入建一个 `TrackSprite`，第 n tick 取轨迹第 n 帧的位移、缩放、加色／减色与 `level/16` 权重，轨迹结束自删；重复插入轮流取种子变体；深度按 obj_Plane（`ActorRuntime.fixed_plane_depth`）；engRANGE（繩子）只画插入线以下的部分。没有轨迹的对象（无原版数据的新关）退回按 obj_Data7 淡出的闪光／加色读法。
- provenance 写法：`static-derived content/generated/hsl/skills/objcomd_motion.json`、`static-derived docs/evidence_packets/static_reverse/original_objcomd_programs.md`。

## 复现

`python3 tools/hsl.py check objcomd_motion`（重生成需原作与 unicorn：`python3 tools/hsl.py generate objcomd_motion`）。

## 重生成差异

effect_motion 为效果对象补镜头与震屏模型后（`REVIEWED` 新增 `0x415d20`、`0x43bf30`、`0x46be92..0x46bf36`、`0x46163a`，Machine 初始化把镜头写成以施法者为中心的 (ORIGIN−(320,192)) = (0,48)，每帧镜头 += 震屏累加），本包整包重跑时有 19 个绝技对象的轨迹变了。逐个把镜头改回 (0,0)、其余模型不变重跑，19 个全部回到旧轨迹；这 19 个对象都没有震屏，新纳入的区间本身不改任何读数。成因只有镜头起点：

- aniInsertObject `0x403989` 建对象时把脚本点加上镜头（`add eax, [0x4c091c]`，`add ecx, [0x4c0920]`），出屏测试 `0x405140` 再减回镜头——SPECIAL 脚本点是屏幕点，屏幕上的轨迹与镜头无关。镜头 (0,48) 而对象仍放在世界脚本点，等于把插入点在屏幕上移 48 px，出屏／回绕提前或推后，随后的随机抽取整体错位。
- 受影响的都是有出屏等待、出屏回绕或屏幕坐标阈值的程序：06_02、08_04、08_08、12_02、13_06、15_03、17_04、17_06、23_01、32_01、33_01、39_01、41_01、42_01、45_05、48_01、52_16、53_01、58_01（均为 `obj_SpecialNN_MM`）。表现为出屏淡出提前或推后（首个不同实例的寿命差 2～44 tick，如 06_02 死于 tick 193→159、08_04 112→150、48_01 的散布从 27 只变 8 只）或回绕 y 差 960（13_06 tick 260、45_05 tick 86）。

结论：新轨迹不是更完整的原指令执行，不采用。探针的 SPECIAL 根改为镜头 (0,0) 运行（等价于按 `0x403989` 把镜头加到脚本点再减回），剧情对象仍用 effect_motion 的居中镜头。重跑结果 `OBJCOMD_MOTION_NATIVE_PASS objects=240 open_ended=4 variants=537 executed_now=True`，240 个对象与旧包逐字节相同，只有 `reviewed` 表头从 17 段变为 21 段。

## 边界

- **随机样本**：原版每个实例从同一条 RNG 流抽取，重制用至多 4 个固定种子的变体轮流代替；插入偏移与延迟由片段的表现 RNG 抽取。不证明逐实例与某次原版运行相同。
- **出屏与位置**：每个对象只在脚本首个插入点跑一次，其它插入点（随机散布、多次插入）平移同一条轨迹；出屏判定按镜头 (0,0)、640×480（脚本点是屏幕点，见「重生成差异」）。objmLoopCheckSmallerY 比世界 y、不减镜头，特写时的真实镜头未读，这一条按镜头 (0,0) 取值（provisional）。特写舞台在重制是 640×320，花瓣等在 y > 320 的部分画在舞台外。
- **未复用轨迹的插入**：只有 無想冥殺 的三个角度环走原生轨迹；妖華紅蓮舞 的 op 20 环、op 21 的环与 op 22 龙卷列仍是重制读法（provisional）。op 21 的旋转造型缓存（`0x4602d4`／`0x45f141` 内部只读了调用链）与 op 22 的 rand 次序未跑原指令。無想冥殺 的 n 只按种子 0 的共享流跑一次，不随片段种子变化。
- **随机插入的命中与基点**：op 27／29 比较 `[0x4c1418]` 与解释器对象 `+0xa6`，重制按整次命中（与 op 27 现状同）；op 28 的基点取重制守方精灵在插入 tick 的位置。原版 aniProcessHitMiss 结算后经 `0x404ba6` 让出（结算体 `0x40492e`／`0x404950` 已写击退速度 `+0x9c` = 0xe0000），op 28 在结算的下一 tick 才执行，击退已起步；重制把 op 28 编在与结算同一 cursor 上，这一 tick 取到的击退位移是 0，只剩同一 tick 尾段是否已积分一步未读（provisional）。原版 aniSetXYDisp 累加进 `+4`／`+8`（`0x403ce5`），重制是覆盖，op 28 编译基点与 `_defender_point` 又分别取编译时与最终的 xy_disp；用 op 28 的只有月花圓舞，脚本里没有 aniSetXYDisp，当前不触发。原版 aniDelay 倒数完还会再让出一次（`0x403dbb`／`0x404584`，实走 n+1 tick），重制 cursor += n；月花圓舞实时路径 MoonDancePresentation.spawn 也按 wait 直排、未经 max(d−1, 0) 换算，均未改。
- **字布局**：objcomd.txt 的装载器未读，"每 token 一字、块尾补 objmOver" 是 provisional；221 个对象全部正常结束或进入等待，未见越界读。
- **未读清**：`0x45e5d9` 反向／往返帧步进（op 37／39）、objmDragonWaveMove 细节、objmSetAngleShape 帧延迟非 0 时、残影对象 0x191 自身行为、编译器是否在程序末尾补 0；这些在原指令执行里照跑，只是表中读法不全。
- **剧情对象**：每个对象只在探针原点跑一次，不等出屏的程序与落点无关；繩子 的 engRANGE 绘制未读，重制按插入线裁切（provisional）；雨（mapobjDropRain）与 mapobjFlash 是 defProcStandObject 过程，不在本包。
- **命中趟**：多段绝技按读字 tick 已结算的段选趟（见[对象声音包](original_effect_object_sounds.md)§边界「多段结算时刻」）；首段结算前 `[0x4c1418]` 是整次的掷骰，重制取整次命中（provisional）。無想冥殺 的 Special06_06 由 aniInsertAngleObject 插入，8 只按 `patterns` 的命中趟画出命中火花。命中趟比落空趟长的对象仍在攻方收页／拆场处截断。
- **声音排程**：`command_sounds` 仍按 objmDelay 之和排（[对象声音包](original_effect_object_sounds.md)），未切到原生执行记下的声音时刻。
