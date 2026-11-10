---
title: CFAPEX
date: 2026-11-10 17:09:06
tags:
---
CFAPEX 1.3 更新日志

更新范围：自定义优选 IP 支持一次保存 1000 条、GitHub Raw 列表拉取超时修复之后的改动。 

## 功能与兼容性

- 新增 **Trojan/WS** 和 **VLESS/XHTTP（stream-one）**，与原有 VLESS/WS 共存；Trojan 和 XHTTP 只在 TLS 端口下发，均支持 TCP。Trojan 可单独设置密码，两个新协议均可通过环境变量关闭。
- 概览保留四个订阅入口：VLESS/WS YAML、Trojan/WS YAML、通用订阅、VLESS/XHTTP YAML。通用入口可切换 URI 与 sing-box JSON；显式 JSON 地址避免 sing-box 桌面客户端因请求头未被识别而收到 URI。XHTTP 查询转为 sing-box JSON 时提供兼容的 VLESS/WS 节点。
- 参考 CFNext V3.0.2 的地区选择，将内置节点池从 234 条更新为 555 条去重地址；用户保存的自定义优选列表仍优先。修正“CF 移动优选”备注被误识别为国家代码的问题。
- Clash YAML 修复 `MATCH` 规则的代理组名称；默认选择组包含自动测速，最多抽样 24 条测速，全部节点仍可手动选择。增加 UDP/443 拒绝规则，让视频流量的 QUIC 请求回退 TCP。

## 转发与资源控制

- 自定义 Proxy IP 仅接管 Cloudflare IPv4 目标的 TLS 流量；候选需完成 TLS 首响应验证，失败时尝试同地区下一条，最终恢复原有出站。非 Cloudflare 目标沿用原有出站。
- 错误 VLESS UUID 与 Trojan 密码立即拒绝；未认证 WebSocket 首包上限降至 64 KiB。默认限制目标端口；WS/XHTTP 单连接最长 15 分钟，上行最多 64 MiB、下行最多 128 MiB。
- 修复无关请求也读取 KV 的问题：无关路径和无效订阅地址在读取前返回；同一 Worker 实例 10 秒内复用并合并 KV 读取，保存或还原后立即失效。面板停止每 15 秒自动轮询，重新显示时刷新状态。
- Worker 字符串及面板 HTML 使用运行时解码表交付，Workers 与 Pages 保持相同的单文件入口。代码混淆不会改变网络行为，也不能消除 Cloudflare 的滥用通报。

## 验证与待确认事项

- 本地 KV 计数：40 个无关请求从 40 次读取降为 **0 次**；同一时窗内 30 次订阅请求共读取 **3 次**。协议、Proxy IP、真实出站及实际 workerd 回归通过；Workers、Pages 和 ZIP 内入口逐字节一致。
- 内置节点抽样 21 条进行 TLS/WebSocket 握手，12 条返回 101。该结果不能证明移动网络下全部节点可用，也不能保证 4K 视频速度。sing-box 桌面程序实际导入及 Cloudflare 线上 KV 告警变化仍需部署后验证。


# CFAPEX
项目是可部署在 Cloudflare 上的代理面板，支持 VLESS/WS、Trojan/WS 和 VLESS/XHTTP。用户可在面板中管理优选 IP、按地区设置 Proxy IP、自定义真实出站和节点 UUID，并获取 Clash YAML、通用 URI 或 sing-box JSON 订阅。项目提供 KV 设置存储、订阅访问控制及短时读取缓存。
# CFAPEX  详细使用教程

CFAPEX 可部署为 Cloudflare Worker 或 Pages Advanced Mode。它提供网页面板、节点订阅和 VLESS/WS、Trojan/WS、VLESS/XHTTP 节点。以下步骤针对当前面板版主线；轻量版文件 `src/worker.js` 不适用。

## 一、准备文件与变量

部署时二选一：

| 平台 | 使用文件 |
|---|---|
| Cloudflare Workers | `dist/CFAPEX-worker.1.3.js`，完整复制为一个模块 Worker |
| Cloudflare Pages Advanced Mode | `dist/CFAPEX-Pages-1.3.zip`，其中只有根目录的 `_worker.js`；也可上传 `dist/pages-panel` 目录 |

必须设置环境变量 **`A`**：变量名就是大写字母 `A`，值由你设定，作为面板访问密码。建议使用较长的随机值，不必填写 UUID。代码会从 `A` 派生默认节点 UUID；之后也可以在面板“设置”页单独修改节点 UUID。

建议先在 Cloudflare 控制台的 **KV / KV Namespace** 页面创建一个专用命名空间（例如 `CFAPEX_CONFIG`），再以绑定名 **`K`** 绑定到该 Worker 或 Pages 项目。面板设置会存入此 KV；如果不绑定 `K`，设置只能保存在边缘缓存，缓存被回收后可能恢复默认。`K` 是绑定名称，不能只把 `K` 填成普通文本环境变量。请为 CFAPEX 使用专用 KV，因为“还原默认”会清空整个绑定命名空间。

其他可选变量：

| 名称 | 作用 |
|---|---|
| `TROJAN_PASSWORD` | 为 Trojan 设置独立密码；不设置时使用节点 UUID |
| `TROJAN=0` | 关闭 Trojan 下发及入站 |
| `XHTTP=0` | 关闭 VLESS/XHTTP 下发及入站 |
| `OUTBOUND_PORTS` | 用逗号列出允许访问的目标端口，最多 32 个；设置后取代默认端口列表 |
| `PROXYIP` | 旧部署方式的全局 Proxy IP，未设置面板地区 Proxy IP 时仍可沿用 |
| `HEALTH_PROBE=1` | 启用订阅触发的后台健康探测；默认关闭 |
| `MASK_HTML` / `MASK_URL` | 设置非面板路径的伪装页面内容或地址 |

默认允许的目标端口为 `80,443,2052,2053,2082,2083,2086,2087,2095,2096,8080,8443,8880`。自定义出站代理服务器自身的端口不受此列表限制。

## 二、部署到 Cloudflare

### 方式 A：Workers

1. 在 Cloudflare 控制台创建 Worker，打开代码编辑器。
2. 用 `dist/CFAPEX-worker（版本号）js` 的**全部内容**替换编辑器内容并部署。不要把 Pages ZIP 粘贴到 Worker 编辑器。
3. 在该 Worker 的“变量和机密”中新增 `A`，值填你的面板密码。可选变量按上表添加。
4. 如需持久保存设置，在“绑定 / Bindings”中添加 KV Namespace 绑定，名称填 `K`，选择为本项目准备的命名空间。
5. 保存设置并使新部署生效，然后记下 Worker 的访问域名。

### 方式 B：Pages Advanced Mode

1. 创建 Pages 项目并选择直接上传，将 `dist/CFAPEX-Pages（版本号）.zip` 作为项目文件上传；ZIP 根目录只有 `_worker.js`。如果使用目录上传，则选 `dist/pages-panel`。
2. 在 Pages 项目设置中新增环境变量 `A`。需要 KV 时，在 Pages 的绑定设置中添加名称为 `K` 的 KV Namespace 绑定。
3. 确认变量和绑定应用到实际使用的环境；设置变更后按 Cloudflare 控制台提示重新部署，再记下 Pages 域名。

升级现有部署时直接替换代码或重新上传 1.3 ZIP。沿用原 `A` 和原 `K` 可保留面板设置；若更换 `A`，面板路径、订阅令牌及默认派生 UUID 都会变化，客户端必须重新导入订阅。旧版 1.2 文件保留作历史版本，升级时请选择文件名含 **1.3** 的交付文件。

## 三、登录面板

假设部署域名为 `https://example.workers.dev`，且设置了 `A=你的密码`，在浏览器地址栏访问：

```text
https://example.workers.dev/你的密码
```

密码区分大小写。密码包含空格、中文、`/`、`?`、`#` 或 `%` 时，路径部分需要 URL 编码；最省事的做法是使用仅含字母、数字及安全符号的长随机值。不要把带密码的面板地址分享给他人。旧变量名 `U` 不再作为面板入口。

导航顺序为：**概览 / 节点列表 / 自定义优选 IP / 自定义 Proxy IP / 自定义出站 IP / 设置 / 关于**。页面右下角的“保存并生效”是所有设置共用的保存按钮。修改设置后，保存成功还需在客户端更新订阅并重连；已经建立的连接不会立即切换配置。

## 四、获取并导入订阅

进入“概览”，复制面板提供的独立 `/s/<令牌>` 订阅地址。它与 `/<A的值>` 面板地址不同；不要把面板地址直接当作客户端订阅。概览显示四个入口：

| 入口 | 下发内容 | 常见用途 |
|---|---|---|
| VLESS/WS | Clash YAML | 支持 VLESS/WS 的 Clash/Mihomo 客户端 |
| Trojan/WS | Clash YAML | 支持 Trojan/WS 的 Clash/Mihomo 客户端 |
| 通用 | 可切换“通用 URI”或“sing-box JSON” | v2rayN 可尝试 URI；sing-box 桌面版请选择 JSON |
| VLESS/XHTTP | Clash YAML | 客户端核心支持 XHTTP 时使用 |

sing-box 远程配置请选择通用入口中的 **“sing-box JSON”**，再复制随之更新的链接。该链接显式带 `?format=singbox`，不依赖客户端请求头识别。sing-box JSON 主要提供 VLESS/WS；XHTTP 专用查询转换为 JSON 时提供兼容的 VLESS/WS 节点。不要把 Clash YAML 直接当作 sing-box 原生 JSON 导入。

v2rayN 可先试“通用 URI”；如果客户端无法按订阅导入逐行 URI，可点击“复制全部节点链接”，从剪贴板导入。Clash/Mihomo 使用对应 YAML 地址。VLESS/XHTTP 是否可用取决于客户端核心对该传输方式的支持。

导入后执行一次**更新订阅**，选择 CFAPEX 节点并重连。检查节点时，SNI 与 WS Host 应为你的部署域名，不能是优选 IP；WS 路径由订阅自动生成。不要手工把面板密码路径填到 WS Path。

## 五、设置自定义优选 IP

“自定义优选 IP”控制**客户端连接的节点入口地址**，会写进订阅节点的服务器地址。可手填 IP、域名或 HTTP(S) 文本列表地址。例如：

```text
1.1.1.1:443#US
1.1.1.2,8443#JP
https://bestcf.pages.dev/random-region/CA/50.txt
```

示例只说明格式，不保证示例地址在你的网络中可用。未写端口默认 443；也支持中文逗号、CSV 风格、IPv6 方括号及多个列表地址混排。保存时服务端会取回列表、规范化节点并按“地址 + 端口”去重。单次最多保存 **1000 条有效且不重复的节点**，输入及合并文本最多 **262144 字符**；重复或无效行不计入有效节点数。远程来源任一失败时旧列表保留。

保存自定义列表后，订阅只使用该列表；需要重新使用内置节点池时，在此页选择恢复内置列表。1.3 内置快照有 555 条候选，地址可用性会随地区、运营商和时间变化，请在自己的网络上测试。移动网络可用性不能由本机 TLS 握手结果保证。

## 六、区分 Proxy IP 与真实出站 IP

这两项设置解决的问题不同：

| 设置 | 控制位置 | 是否直接成为订阅节点服务器地址 |
|---|---|---|
| 自定义优选 IP | 客户端到 Cloudflare 的入口 | 是 |
| 自定义 Proxy IP | Worker 转发 Cloudflare IPv4 TLS 目标时尝试的中继 | 否；地区信息体现在节点路径 |
| 自定义出站 IP | Worker 到目标的真实 TCP 出口代理 | 否 |

### 自定义 Proxy IP

在“自定义 Proxy IP”页按地区填写，多个地址用 `/` 或换行分隔：

```text
109.168.1.1,443 #JP/109.168.2.2,8443 #US
```

这些地址仅是格式示例。单项可省略地区标签；省略后作为通用候选。最多 100 条、16000 字符。保存后要更新订阅并重连，使节点使用带地区的 WS 路径。Worker 只对解析为 Cloudflare IPv4 的 TLS 目标尝试这些候选；握手失败会尝试下一条并回到原有出站。**在 `ip.sb` 查到的出口 IP 不保证等于填写的 Proxy IP**，不能仅以两者不同判断该功能失效。

### 自定义出站 IP

“自定义出站 IP”控制 Worker 的真实 TCP 出口，支持：

```text
socks5://user:pass@host:1080
http://user:pass@host:8080
https://user:pass@host:443
ss://...
host:port
```

裸 `host:port` 按 SOCKS5 处理；未填端口时默认 1080。SS 仅支持 `aes-128-gcm`、`aes-256-gcm`、`chacha20-ietf-poly1305` 三种 AEAD 方法，不支持插件或 SS2022。代理地址及凭据只用于 Worker 出站设置，不写入订阅节点字段。

“出站方式”默认是 `auto`：出站代理连接或握手失败时可回退直连。要核对真实出口，在测试期间选择 **“仅走出口（only）”**；该模式失败即报错，不回退直连。保存、更新订阅并重连后，用已确认走该节点的浏览器访问 IP 检测网站。验证完毕可按需要调整模式。

## 七、设置 UUID 与还原默认

“设置”页允许填写标准 UUID，作为节点协议认证 UUID；它独立于面板密码 `A`。留空并保存会恢复由 `A` 派生的默认 UUID。更改 UUID 后必须更新订阅并断开旧连接再重连。Trojan 未设置独立 `TROJAN_PASSWORD` 时也会使用节点 UUID 作为密码。

右下角“还原默认”会**直接清空当前绑定 `K` 中的全部数据**，不限于 CFAPEX 已知的键；面板会分批删除并显示进度。使用前确认 `K` 是 CFAPEX 专用命名空间。未绑定 K 时，它清理当前主机的相关边缘缓存。环境变量（包括 `A`）不会被这个按钮删除。

## 八、常见问题

| 现象 | 检查方法 |
|---|---|
| 打不开面板 | 确认环境变量名为 `A`、部署已生效、访问的是 `https://域名/<A的值>`；特殊字符要 URL 编码。 |
| 订阅导入失败 | 从概览重新复制独立订阅地址；sing-box 选择 JSON，Clash/Mihomo 选 YAML；确认客户端已更新订阅。 |
| 保存后节点未变化 | 检查是否绑定了 `K`，保存是否显示成功；更新订阅、断开旧连接并重连。不同 Cloudflare 接入点的 KV 更新可能有传播延迟，单实例读取还会复用最多 10 秒。 |
| 自定义优选 IP 保存失败 | 检查列表 URL 能否访问、是否超时，以及 1000 条、262144 字符和单来源 256 KiB 限制。远程来源任一失败时旧列表不会被覆盖。 |
| 节点延迟为 -1 | 检查优选入口 IP、端口、SNI、WS Host、WS Path 与客户端日志；在同一网络测试部署域名入口。若只在移动网络失败，需要该网络下的实际日志定位。 |
| Proxy IP 已保存但查 IP 未变 | 它不是必然的最终出口；确认节点地区、订阅和重连，再检查是否发生候选失败回退。若要固定测试真实出口，使用“自定义出站 IP”的 only 模式。 |
| KV 读取额度仍高 | 确认已部署 1.3 文件；查看是否有旧订阅客户端持续刷新、面板仍开在多个设备或大量有效订阅请求。无关路径在当前版本不读取 KV，面板也不再每 15 秒轮询。 |

当前代码通过本地语法、协议、设置、KV 读量及 workerd 回归；公网线路、移动网络、sing-box 桌面客户端的实际连接和 Cloudflare 线上额度，仍应以部署后的客户端及后台数据为准。
