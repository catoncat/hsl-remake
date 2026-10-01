# 浏览器版

用 Godot 的网页导出把重制版放进浏览器：核心包只带脚本、场景、标题和共用美术，每一关、每段影片、每首音乐是单独的资源包，进到那一关才下载，并缓存在浏览器里。它不是另一份游戏：同一套 `game/` 与 `content/`，只多一个按需下载资源包的 autoload（`game/web/PackManager.gd`）和几处「切场景前先等资源包挂好」的接缝。桌面上这个 autoload 不启用，所有切换照旧同步完成。

Checked: 2026-10-01

## 先读这一条

构建出来的网页和桌面版一样，带着从你本机原版数据导入的贴图、声音和数据（见 [NOTICE](../NOTICE.md)）。只能在你有权使用的范围里用：自己玩，或者放在私有存储、前面加一道密码门，给你信得过的人。不要放到公开的静态托管上。本仓库不提供也不托管任何构建产物。

## 构建

需要已经 `bootstrap` 过的检出（见 [README「运行」](../README.md#运行)）和 Godot 4.7.2（Web 模板的版本钉在这个版本）。

```sh
python3 tools/web_build.py fetch-templates   # 只取 Web 的两个模板：按 HTTP Range 读 .tpz，不下整包
python3 tools/web_build.py build             # 暂存 → 导出核心 → 构建全部资源包，产物在 ignored/web/dist/
python3 tools/web_build.py serve             # 本机 127.0.0.1:8060 试玩；--auth 用户名:密码 加一道门
```

- 暂存（`stage`）不改检出：把要导出的文件克隆到 `ignored/web/stage/`，只改克隆，并在这里瘦身——JSON 去空白、影片图集转有损 WebP、开发专用文件剔除。地图和精灵转有损会糊像素画，所以不转。
- `build --no-packs` 导出成一个大 `.pck`、不分包，用来对照；`list PCK` 列出一个 `.pck` 里各目录的条目数和字节数。
- 本机试玩用 `127.0.0.1` 就行；给别人用必须是 HTTPS，浏览器的一些接口只在安全上下文里开放。
- 需要 `boto3` 的只有下面的发布工具（`pip install boto3`），构建和试玩不要。

## 分包

`tools/web_packs.py plan` 扫暂存目录，按目录决定归属：

- 一关的 `battleNNN/` 树、关卡 JSON、种子、地形和宝箱表是 `level_NNN` 包；
- 影片图集和音效是 `movie_<名>` 包；除标题曲外，每首音乐是 `music_<名>` 包；
- 其余留在核心。

一个包依赖它的 JSON 里按 `res://` 路径提到的其他包：借用别关的地图、时间线播的音乐、剧情事件放的影片。指向另一个关卡文件的是交接，不是依赖。计划会检查：每个游戏文件要么在核心、要么只在一个包里；排除通配符恰好命中包内文件；依赖是闭合的。

`web_packs.py build` 在一次无头 Godot 里用 `PCKPacker` 打出全部包，命名为 `<id>-<sha8>.pck`，并写 `manifest.json`：每个包的文件、字节、sha256，组，关卡到组的对应，以及下一关的预取提示。`web_build.py build` 已经把这两步串好了。

运行时 `PackManager` 做这几件事：

- 进入战斗、剧情、城镇、大地图、影片或结局之前，先下载需要的包，校验字节数和 sha256，存进 `user://packs/`（浏览器里是 IndexedDB），再用 `load_resource_pack` 挂上。
- 已缓存的包在启动时就挂好，所以「戰場記錄」和回忆录能找到玩过的关。
- 进入一关后，按清单里的 `next` 在后台一次一个地预取可能交接到的下一关；玩家正在等的加载会取消用不上的预取。
- 场景里的 `ResourceLoader.exists` 守卫遇到缺文件会悄悄跳过，表现为没声音、没特效、没头像，所以每次切换都必须走 `after_scenario`／`after_groups`，不能直接 `change_scene_to_file`。

桌面上、也没有设 `HSL_WEB_PACKS_DIR` 时，管理器是关的，`then` 在同一次调用里执行。把 `HSL_WEB_PACKS_DIR` 指向一个已构建的包目录，可以不经网络试跑整条链路。

## 发布给别人玩

三个工具配套，配置写在 `ignored/web/deploy.json`（不入库，密钥也不写进去）：

```sh
python3 tools/web_deploy.py init --bucket 桶名 --region 地域 --credentials env   # 密钥放环境变量；--create 顺手建私有桶
python3 tools/web_deploy.py push --keep 3      # 增量上传一个版本，最后才切换 latest.json
python3 tools/web_deploy.py releases           # 另有 rollback 版本号、check
python3 tools/web_gate.py --users-file 账号文件   # 密码门（只用标准库）
python3 tools/web_server.py install --host 服务器别名 --ip 公网IP --caddy 二进制   # 在小服务器上装门和 HTTPS
```

- 存储是腾讯云 COS 的私有桶：页面和清单在 `releases/<版本>/`，每个 `.wasm`、`.pck` 按内容哈希只存一份在 `blobs/` 下。没变的引擎、核心或资源包不重传、不重存，浏览器里的缓存也不失效。`latest.json` 是唯一的开关，回滚只是把它指回旧版本。
- 门先验密码，页面和清单自己给，大文件一律 302 到带签名的 COS 链接，所以门所在机器的带宽无关紧要。门只该持有只读密钥。
- 引擎和核心的链接在一个固定的时间窗口里不变，对象带 `immutable`，回访的玩家不再下载。资源包每次给一小时有效的新链接，游戏自己把它们存进浏览器。
- `web_server.py` 用 Caddy 给裸 IP 申请 Let's Encrypt 的短期证书并自动续期，需要服务器的 80 和 443 对公网开放；它还管门的账号（`users`）、状态（`status`）和日志（`logs`）。
- 另一条现成的后端是 Cloudflare（下一节）；换成别的对象存储要改 `web_deploy.py` 和 `web_gate.py` 里 COS 的部分。

### 另一条后端：Cloudflare

同一套版本布局也可以放在 Cloudflare：私有的 R2 桶存文件，一个 Worker（`tools/web_cf_worker.js`）当密码门，把 R2 里的文件直接流式返回，没有跳转也没有签名链接。R2 不收出网流量费，免费额度和限制以官方说明为准。全程走 `wrangler` 的登录会话（`wrangler login` 一次），不需要也不存 API 令牌或 S3 密钥：

```sh
python3 tools/web_cf.py init --hostname 子域名      # 建私有桶和 KV，部署 Worker 与自定义域名；域名要在你的 Cloudflare 账号里
python3 tools/web_cf.py users import --host 服务器别名   # 把 COS 门的账号灌进 Worker；也可 users add 名字
python3 tools/web_cf.py push --keep 3
python3 tools/web_cf.py releases               # 另有 rollback 版本号、check、status、deploy
```

- `web_cf.py push` 和 `web_deploy.py push` 读同一个 `dist/`，两边都要更新就各跑一次。设 `HSL_CF_CHECK_AUTH=用户名:密码`，push 切换后会逐个文件经门核对大小，不符就把 `latest.json` 放回上一版。
- 门的行为和 `web_gate.py` 对齐：Basic 认证、同一地址输错 5 次封 5 分钟、只服务版本表里的路径、资源包 `no-store`。页面、清单、引擎和核心都带 ETag：回访只做一次条件请求，没变就回 304、不重新下载。这里不能像 COS 那样给引擎和核心 `immutable`，因为它们的网址在每个版本里都一样，长期缓存会让回访的玩家永远停在第一次下到的版本。
- 账号存在 Worker 的 `USERS` secret 里，secret 读不回来，所以 `users` 在 `ignored/web/cf-users` 留一份 0600 的副本来编辑。
- Cloudflare 的普通线路在大陆没有节点，大陆玩家的速度和稳定性取决于各自的线路，不像国内对象存储那样稳定。面向大陆玩家时，先用真实的网络测过，再决定它当主入口还是备用入口。

维护者自己那一套线上部署的现状、账号、费用和风险记在 `docs/internal/WEB_DEPLOY.md`（内部文档，不随公开导出）。

## 网页平台的坑

改 `game/` 里的音频总线、下载或 `user://` 存取时对照：

- 网页默认「采样播放」。对新建总线显式调用 `AudioServer.set_bus_send(i, "Master")` 会把主总线接进新总线并切断输出，整个游戏没声音，所以 `GameSettings._bus` 在网页上跳过它。
- `HTTPRequest.download_file` 在网页上不生效，`DirAccess.rename` 对 `user://` 也会失败：下载走 body 加 `FileAccess.store_buffer`。默认 64 KiB 的块把速度压到约 3.7 MB/s，改成 4 MiB。
- CDN 或反向代理压缩过的响应，浏览器已经解压，Godot 再解一次会报 `RESULT_BODY_DECOMPRESS_FAILED`，所以 `HTTPRequest.accept_gzip = false`。本地不压缩的服务测不出这个。
- `user://` 是 IndexedDB：存档和资源包缓存在同一处，清站点数据会一起丢；启动时整份读进内存，缓存目前没有上限。
- 浏览器没有系统字体，网页版固定用原版点阵字（`OriginalBitmapFont`）。
- 标题画面的「離開遊戲」在网页上改为重新加载页面，页面不能自己关闭。
- 无头浏览器测试：Playwright 的 `httpCredentials` 会关掉 HTTP 缓存，量缓存时让门跑在 127.0.0.1 上、用 `web_gate.py --no-auth-for-testing`；系统自带的 Chrome 无头模式在一些机器上会被杀，改用 Playwright 自带的 chromium-headless-shell。

## 还没做的

- 整章没有在浏览器里逐关走过。验证过的是从标题开始新故事、进到玩家第 1 场 · 棄卒（LEVEL051）的开场；后面的关、城镇、大地图和结局的网页路径没验证。验证用的是无头浏览器脚本，没有入库，门禁只守桌面行为不变。
- 声音只量到输出端有信号，没有人耳核对；Safari 和手机浏览器没试。
- 资源包缓存没有上限和淘汰，整章缓存会到数百 MB。
