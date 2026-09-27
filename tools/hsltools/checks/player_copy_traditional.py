"""Player-visible copy is Traditional Chinese: no simplified character in any string a player can
read, judged by an explicit simplified→traditional difference table (SIMPLIFIED_TO_TRADITIONAL, plus
the short SIMPLIFIED_WORDS list for words like 游玩 whose characters are traditional on their own),
never by heuristics. The table lists only characters that are a simplification of a different
traditional form and are not themselves characters in traditional use (后／云／里／干／系／采／症／
伙／痴 … are deliberately absent: they read as traditional text); it is validated against the
original's own message corpus, which this check also scans (a hit there is a table defect).

Scope (explicit):
  game/**/*.gd      string literals on code lines — comment lines and developer-facing calls
                    (assert／push_error／push_warning／print／printerr／prints／print_debug／print_rich)
                    are not player copy
  game/**/*.tscn    every string value (scene text properties)
  content/battles/**/*.json, content/authored/**/*.json, content/imported/**/message_text_evidence.json,
  content/imported/hsl/story_corpus/scripts/*.json, content/imported/hsl/global/world_map/town_messages.json,
  content/imported/hsl/shared/panels/manifest.json, content/imported/hsl/global/title/manifest.json
                    values under the player-visible keys PLAYER_KEYS (title／name／name_text／display_name／
                    label／message_text／speaker_name／text) and every value under result_labels／
                    messages／speakers (authored dialogue tables, dead messages);
                    notes, comments, evidence prose and glyph transcriptions are developer fields

Registry task content:player_copy_traditional (family content, CheckTask, replaces=()).
PASS line: PLAYER_COPY_TRADITIONAL_PASS gd_files=N tscn_files=N json_files=N strings=N table=N words=N.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.registry import CheckFailed, Context

# simplified→traditional pairs, one difference each; the check reports the traditional form as the fix.
SIMPLIFIED_TO_TRADITIONAL_PAIRS = """
万萬 与與 专專 业業 丛叢 东東 丝絲 丢丟 两兩 严嚴 丧喪 个個 临臨 为為 丽麗 举舉 义義 乌烏 乐樂 乔喬 习習 乡鄉 书書 买買
乱亂 争爭 亏虧 亚亞 产產 亩畝 亲親 亵褻 亿億 仅僅 从從 仑侖 仓倉 仪儀 们們 价價 众眾 优優 会會 伞傘 伟偉 传傳 伤傷 伦倫
伪偽 体體 佣傭 佥僉 侠俠 侣侶 侥僥 侦偵 侧側 侨僑 侩儈 俩倆 俭儉 债債 倾傾 偿償 储儲 儿兒 兑兌 兰蘭 关關 兴興 养養 兽獸
内內 冈岡 册冊 写寫 军軍 农農 冯馮 冲衝 决決 况況 冻凍 净淨 凉涼 减減 凑湊 凛凜 凤鳳 凭憑 凯凱 击擊 凿鑿 刍芻 刘劉 则則
刚剛 创創 删刪 别別 刽劊 剂劑 剐剮 剑劍 剥剝 剧劇 劝勸 办辦 务務 动動 励勵 劲勁 劳勞 势勢 勋勳 匀勻 区區 医醫 华華 协協
单單 卖賣 卢盧 卤鹵 卧臥 卫衛 却卻 厅廳 历歷 厉厲 压壓 厌厭 厕廁 厢廂 厦廈 厨廚 厩廄 县縣 参參 双雙 发發 变變 叙敘 叠疊
叶葉 号號 叹嘆 吓嚇 吕呂 吗嗎 吨噸 听聽 启啟 吴吳 呕嘔 员員 呛嗆 呜嗚 咏詠 咸鹹 响響 哑啞 哗嘩 哟喲 唤喚 啬嗇 啮嚙 啸嘯
喷噴 嘘噓 嘱囑 嚣囂 团團 园園 围圍 国國 图圖 圆圓 圣聖 场場 坏壞 块塊 坚堅 坛壇 坝壩 坞塢 坟墳 坠墜 垄壟 垒壘 垦墾 垫墊
垲塏 堑塹 堕墮 墙牆 壮壯 声聲 壳殼 壶壺 处處 备備 复復 够夠 头頭 夹夾 夺奪 奋奮 奖獎 奥奧 妆妝 妇婦 妈媽 娄婁 娇嬌 娱娛
婴嬰 婶嬸 孙孫 学學 孪孿 宁寧 宝寶 实實 宠寵 审審 宪憲 宫宮 宽寬 宾賓 寝寢 对對 寻尋 导導 寿壽 将將 尔爾 尘塵 尝嘗 尧堯
尽盡 层層 屉屜 届屆 属屬 屡屢 屿嶼 岁歲 岂豈 岗崗 岛島 岭嶺 岿巋 峡峽 峦巒 崭嶄 巩鞏 币幣 帅帥 师師 帐帳 帜幟 带帶 帧幀
帮幫 幂冪 庄莊 庆慶 庐廬 库庫 应應 庙廟 庞龐 废廢 开開 异異 弃棄 张張 弥彌 弯彎 弹彈 强強 归歸 当當 录錄 彦彥 彻徹 径徑
忆憶 忏懺 忧憂 怀懷 态態 怂慫 怜憐 总總 恋戀 恳懇 恶惡 恼惱 悦悅 悬懸 悯憫 惊驚 惧懼 惩懲 惫憊 惭慚 惮憚 惯慣 愤憤 慑懾
懒懶 戋戔 戏戲 战戰 户戶 扑撲 执執 扩擴 扫掃 扬揚 扰擾 抚撫 抟摶 抡掄 抢搶 护護 报報 担擔 拟擬 拢攏 拣揀 拥擁 拦攔 拧擰
拨撥 择擇 挚摯 挛攣 挝撾 挞撻 挟挾 挠撓 挡擋 挣掙 挤擠 挥揮 捞撈 损損 捡撿 换換 捣搗 掳擄 掷擲 掸撣 揽攬 搁擱 搂摟 搅攪
携攜 摄攝 摆擺 摇搖 摈擯 摊攤 撑撐 撵攆 擞擻 攒攢 敌敵 敛斂 数數 斋齋 斩斬 断斷 无無 旧舊 时時 旷曠 昼晝 显顯 晋晉 晓曉
晕暈 暂暫 术術 机機 杀殺 杂雜 权權 条條 来來 杨楊 杰傑 极極 构構 枢樞 枣棗 枪槍 柜櫃 柠檸 栅柵 标標 栈棧 栋棟 栏欄 树樹
栖棲 样樣 档檔 桥橋 桨槳 桩樁 梦夢 检檢 椭橢 楼樓 槛檻 横橫 樱櫻 橱櫥 欢歡 欧歐 歼殲 残殘 殴毆 毁毀 毕畢 毙斃 毡氈 气氣
氢氫 汇匯 汉漢 汤湯 汹洶 沟溝 没沒 沥瀝 沦淪 沧滄 沩溈 沪滬 泞濘 泪淚 泻瀉 泼潑 泽澤 洁潔 洼窪 浅淺 浆漿 浇澆 浊濁 测測
济濟 浏瀏 浑渾 浓濃 涂塗 涛濤 涝澇 涟漣 涡渦 涣渙 涤滌 润潤 涧澗 涨漲 涩澀 渊淵 渍漬 渐漸 渔漁 渗滲 温溫 湾灣 湿濕 溃潰
溅濺 滚滾 滞滯 满滿 滤濾 滥濫 滦灤 滩灘 潍濰 潜潛 澜瀾 灭滅 灯燈 灵靈 灾災 灿燦 炉爐 点點 炼煉 炽熾 烁爍 烂爛 烃烴 烛燭
烟煙 烦煩 烧燒 烩燴 烫燙 烬燼 热熱 焕煥 爱愛 爷爺 牵牽 牺犧 犊犢 状狀 犹猶 狞獰 独獨 狭狹 狮獅 狰猙 狱獄 猎獵 猪豬 猫貓
献獻 獭獺 玛瑪 环環 现現 玺璽 珐琺 琐瑣 琼瓊 瑶瑤 瓮甕 电電 画畫 畅暢 畴疇 疖癤 疗療 疟瘧 疡瘍 疮瘡 疯瘋 痈癰 痉痙 痒癢
痪瘓 瘫癱 癣癬 皱皺 盏盞 盐鹽 监監 盖蓋 盗盜 盘盤 眯瞇 睁睜 瞒瞞 瞩矚 矫矯 矾礬 矿礦 码碼 砖磚 砚硯 砾礫 础礎 硕碩 确確
碍礙 碱鹼 礌礧 礼禮 祷禱 祸禍 禄祿 离離 秃禿 种種 积積 称稱 秸稭 秽穢 税稅 稳穩 穷窮 窃竊 窍竅 窑窯 窜竄 窝窩 窥窺 竖豎
竞競 笋筍 笔筆 笺箋 笼籠 筛篩 筹籌 签簽 简簡 箩籮 篓簍 篮籃 篱籬 类類 粤粵 粪糞 粮糧 紧緊 纠糾 红紅 纤纖 约約 级級 纪紀
纫紉 纬緯 纯純 纱紗 纲綱 纳納 纵縱 纶綸 纷紛 纸紙 纹紋 纺紡 纽紐 线線 练練 组組 绅紳 细細 织織 终終 绍紹 绎繹 经經 绑綁
绒絨 结結 绕繞 绘繪 给給 绚絢 络絡 绝絕 绞絞 统統 绢絹 绣繡 绥綏 绦絛 继繼 绩績 绪緒 续續 绰綽 绳繩 维維 绵綿 绷繃 绸綢
综綜 绽綻 绿綠 缀綴 缄緘 缅緬 缆纜 缉緝 缎緞 缓緩 缔締 缕縷 编編 缘緣 缚縛 缝縫 缠纏 缤繽 缦縵 缨纓 缩縮 缮繕 缴繳 缵纘
网網 罗羅 罚罰 罢罷 羡羨 翘翹 耸聳 耻恥 聂聶 聋聾 职職 联聯 聪聰 肃肅 肤膚 肾腎 肿腫 胀脹 胁脅 胆膽 胜勝 胶膠 脉脈 脏髒
脐臍 脑腦 脓膿 脚腳 脱脫 脸臉 腻膩 腾騰 舆輿 舰艦 舱艙 艰艱 艳艷 艺藝 节節 芜蕪 芦蘆 苇葦 苍蒼 苏蘇 茎莖 茧繭 荆荊 荚莢
荡蕩 荣榮 荤葷 荧熒 荫蔭 药藥 莱萊 莲蓮 获獲 莹瑩 萝蘿 萤螢 营營 萧蕭 萨薩 蒋蔣 蓝藍 蓟薊 蔷薔 蕴蘊 虏虜 虑慮 虚虛 虫蟲
虽雖 虾蝦 蚀蝕 蚁蟻 蚂螞 蚕蠶 蛊蠱 蛮蠻 蛰蟄 蜕蛻 蜗蝸 蝇蠅 蝎蠍 螨蟎 衅釁 衔銜 补補 衬襯 袄襖 袜襪 袭襲 装裝 裤褲 见見
观觀 规規 觅覓 视視 览覽 觉覺 触觸 誉譽 誊謄 计計 订訂 讣訃 认認 讥譏 讨討 让讓 讫訖 训訓 议議 讯訊 记記 讲講 讳諱 讶訝
许許 讹訛 论論 讼訟 讽諷 设設 访訪 诀訣 证證 评評 诅詛 识識 诈詐 诉訴 诊診 诌謅 词詞 译譯 试試 诗詩 诚誠 诛誅 话話 诞誕
诡詭 询詢 诣詣 该該 详詳 诫誡 诬誣 语語 误誤 诱誘 诲誨 说說 诵誦 请請 诸諸 诺諾 读讀 诽誹 课課 谁誰 调調 谅諒 谆諄 谈談
谊誼 谋謀 谍諜 谎謊 谐諧 谓謂 谚諺 谜謎 谢謝 谣謠 谤謗 谦謙 谨謹 谩謾 谬謬 谭譚 谰讕 谱譜 谴譴 贝貝 贞貞 负負 贡貢 财財
责責 贤賢 败敗 账賬 货貨 质質 贩販 贪貪 贫貧 贬貶 购購 贮貯 贯貫 贰貳 贱賤 贴貼 贵貴 贷貸 贸貿 费費 贺賀 贼賊 贾賈 贿賄
赁賃 赂賂 赃贓 资資 赊賒 赋賦 赌賭 赎贖 赏賞 赐賜 赔賠 赖賴 赘贅 赚賺 赛賽 赞贊 赠贈 赡贍 赢贏 赣贛 赵趙 赶趕 趋趨 跃躍
践踐 踊踴 踪蹤 蹿躥 躜躦 躯軀 车車 轧軋 轨軌 轩軒 转轉 轮輪 软軟 轰轟 轴軸 轻輕 载載 轿轎 较較 辅輔 辆輛 辈輩 辉輝 辊輥
辐輻 辑輯 输輸 辕轅 辖轄 辗輾 辙轍 辞辭 辩辯 辫辮 边邊 辽遼 达達 迁遷 过過 迈邁 运運 还還 这這 进進 远遠 违違 连連 迟遲
适適 选選 逊遜 递遞 逻邏 遗遺 遥遙 邓鄧 邮郵 邹鄒 邻鄰 郑鄭 郧鄖 郸鄲 酝醞 酱醬 酿釀 释釋 鉴鑒 针針 钉釘 钎釺 钒釩 钓釣
钙鈣 钝鈍 钞鈔 钟鐘 钠鈉 钢鋼 钥鑰 钦欽 钧鈞 钨鎢 钩鉤 钮鈕 钱錢 钳鉗 钵缽 钻鑽 钾鉀 铀鈾 铁鐵 铂鉑 铃鈴 铅鉛 铆鉚 铜銅
铝鋁 铡鐧 铣銑 铬鉻 铭銘 铰鉸 铱銥 银銀 铸鑄 铺鋪 链鏈 销銷 锁鎖 锄鋤 锅鍋 锈銹 锉銼 锌鋅 锐銳 锑銻 锗鍺 错錯 锚錨 锡錫
锣鑼 锤錘 锥錐 锦錦 锨鍁 锭錠 键鍵 锯鋸 锰錳 锹鍬 锻鍛 镀鍍 镁鎂 镇鎮 镊鑷 镍鎳 镐鎬 镑鎊 镘鏝 镜鏡 镣鐐 镭鐳 镰鐮 镶鑲
长長 门門 闪閃 闭閉 问問 闯闖 闰閏 闲閑 间間 闷悶 闸閘 闹鬧 闺閨 闻聞 闼闥 闽閩 阀閥 阁閣 阂閡 阅閱 阉閹 阎閻 阐闡 阑闌
阔闊 阖闔 队隊 阳陽 阴陰 阵陣 阶階 际際 陆陸 陇隴 陈陳 陕陝 陨隕 险險 随隨 隐隱 隶隸 难難 雏雛 雾霧 霉黴 静靜 韦韋 韧韌
韩韓 韵韻 页頁 顶頂 顷頃 项項 顺順 须須 顽頑 顾顧 顿頓 颂頌 预預 颅顱 领領 颇頗 颈頸 颉頡 颊頰 颍潁 颐頤 频頻 颓頹 题題
颛顓 颜顏 额額 颤顫 颧顴 风風 飘飄 飞飛 饥飢 饭飯 饮飲 饯餞 饰飾 饱飽 饲飼 饵餌 饶饒 饺餃 饿餓 馁餒 馅餡 馆館 馈饋 馏餾
馒饅 马馬 驭馭 驮馱 驯馴 驰馳 驱驅 驳駁 驴驢 驶駛 驹駒 驻駐 驼駝 驾駕 骂罵 骄驕 骆駱 骋騁 验驗 骏駿 骑騎 骗騙 骚騷 骡騾
骤驟 鱼魚 鲁魯 鲍鮑 鲜鮮 鲤鯉 鳃鰓 鳖鱉 鳞鱗 鸟鳥 鸡雞 鸣鳴 鸥鷗 鸦鴉 鸭鴨 鸯鴦 鸳鴛 鸵鴕 鸽鴿 鸿鴻 鹃鵑 鹅鵝 鹊鵲 鹏鵬
鹤鶴 鹰鷹 麦麥 黄黃 黾黽 齐齊 齿齒 龄齡 龋齲 龙龍 龚龔 龟龜
"""
SIMPLIFIED_TO_TRADITIONAL: dict[str, str] = {pair[0]: pair[1] for pair in SIMPLIFIED_TO_TRADITIONAL_PAIRS.split()}
# Simplified words spelled with characters that are themselves traditional characters (游 swims in
# traditional text; 遊 plays): the character table cannot see them, so the words are listed explicitly.
SIMPLIFIED_WORDS: dict[str, str] = {'游玩': '遊玩', '游戏': '遊戲', '游戲': '遊戲', '出游': '出遊', '周游': '周遊', '旅游': '旅遊'}

GD_ROOT = 'game'
JSON_GLOBS = ('content/battles/*.json', 'content/battles/levels/*.json', 'content/authored/**/*.json', 'content/imported/**/message_text_evidence.json',
              'content/imported/hsl/story_corpus/scripts/*.json', 'content/imported/hsl/global/world_map/town_messages.json',
              'content/imported/hsl/shared/panels/manifest.json', 'content/imported/hsl/global/title/manifest.json')
PLAYER_KEYS = ('title', 'name', 'name_text', 'display_name', 'label', 'message_text', 'speaker_name', 'text')
PLAYER_CONTAINERS = ('result_labels', 'messages', 'speakers')
STRING_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"|\'((?:[^\'\\]|\\.)*)\'')
DEVELOPER_CALL = re.compile(r'^(?:assert|push_error|push_warning|print|printerr|prints|print_debug|print_rich)\(')


def simplified_in(text: str) -> list[str]:
    """The distinct simplified characters and listed simplified words of `text`, first-seen order."""
    found = list(dict.fromkeys(char for char in text if char in SIMPLIFIED_TO_TRADITIONAL))
    found += [word for word in SIMPLIFIED_WORDS if word in text]
    return found


def fix_hint(bad: list[str]) -> str:
    return ' '.join(f'{item}→{SIMPLIFIED_TO_TRADITIONAL.get(item) or SIMPLIFIED_WORDS[item]}' for item in bad)


def gd_strings(text: str) -> list[tuple[int, str]]:
    """(line number, literal) for every string literal on a player-facing code line."""
    out: list[tuple[int, str]] = []
    for number, line in enumerate(text.split('\n'), 1):
        stripped = line.strip()
        if stripped.startswith('#') or DEVELOPER_CALL.match(stripped):
            continue
        for match in STRING_LITERAL.finditer(line):
            out.append((number, match.group(1) if match.group(1) is not None else match.group(2)))
    return out


def tscn_strings(text: str) -> list[tuple[int, str]]:
    return [(number, match.group(1)) for number, line in enumerate(text.split('\n'), 1)
            for match in re.finditer(r'"((?:[^"\\]|\\.)*)"', line)]


def json_player_strings(value, path: str = '', inside: bool = False) -> list[tuple[str, str]]:
    """(json path, string) for every value under a player-visible key or container."""
    out: list[tuple[str, str]] = []
    if isinstance(value, dict):
        for key, child in value.items():
            here = f'{path}/{key}' if path else key
            out.extend(json_player_strings(child, here, inside or key in PLAYER_CONTAINERS or key in PLAYER_KEYS))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            out.extend(json_player_strings(child, f'{path}/{index}', inside))
    elif isinstance(value, str) and inside:
        out.append((path, value))
    return out


def player_strings(root: Path, counts: dict[str, int] | None = None):
    """Yield (location, literal) for every player-visible string of the scope above; `counts`
    (when given) accumulates gd_files／tscn_files／json_files／strings. Shared with
    hsltools.checks.simplified_display, which checks the same strings' displayed form."""
    counts = counts if counts is not None else {}
    for key in ('gd_files', 'tscn_files', 'json_files', 'strings'):
        counts.setdefault(key, 0)
    for path in sorted((root / GD_ROOT).rglob('*.gd')):
        counts['gd_files'] += 1
        for number, literal in gd_strings(path.read_text()):
            counts['strings'] += 1
            yield f'{path.relative_to(root).as_posix()}:{number}', literal
    for path in sorted((root / GD_ROOT).rglob('*.tscn')):
        counts['tscn_files'] += 1
        for number, literal in tscn_strings(path.read_text()):
            counts['strings'] += 1
            yield f'{path.relative_to(root).as_posix()}:{number}', literal
    seen: set[Path] = set()
    for pattern in JSON_GLOBS:
        for path in sorted(root.glob(pattern)):
            if path in seen or not path.is_file():
                continue
            seen.add(path)
            counts['json_files'] += 1
            for json_path, literal in json_player_strings(json.loads(path.read_text())):
                counts['strings'] += 1
                yield f'{path.relative_to(root).as_posix()} {json_path}', literal


def scan(root: Path) -> tuple[list[str], dict[str, int]]:
    issues: list[str] = []
    counts: dict[str, int] = {}
    for location, literal in player_strings(root, counts):
        bad = simplified_in(literal)
        if bad:
            issues.append(f'{location}: simplified {fix_hint(bad)} in "{literal}"')
    return issues, counts


def check(root: Path) -> str:
    issues, counts = scan(root)
    if issues:
        raise ValueError(f'{len(issues)} player-visible string(s) carry simplified characters:\n  ' + '\n  '.join(issues))
    return (f'PLAYER_COPY_TRADITIONAL_PASS gd_files={counts["gd_files"]} tscn_files={counts["tscn_files"]} '
            f'json_files={counts["json_files"]} strings={counts["strings"]} table={len(SIMPLIFIED_TO_TRADITIONAL)} words={len(SIMPLIFIED_WORDS)}')


class PlayerCopyTraditionalTask(CheckTask):
    name = 'content:player_copy_traditional'
    family = 'content'
    inputs = ('game/', 'content/battles/', 'content/authored/', 'content/imported/')
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/checks/player_copy_traditional.py',)

    def check(self, ctx: Context) -> str:
        try:
            return check(ctx.root)
        except (ValueError, OSError, json.JSONDecodeError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error


def tasks() -> list[PlayerCopyTraditionalTask]:
    return [PlayerCopyTraditionalTask()]
