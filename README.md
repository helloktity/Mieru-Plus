# Mieru-Plus

mieru 一键安装脚本，自动搭建 TCP 和 UDP 账号，生成官方配置和 Clash Meta / Mihomo 配置，并内置订阅服务（输出订阅链接，可被 Sub-Store 以 `remote` 方式订阅）。

---

## 特性

- 一键安装，全程无需手动填写配置
- 自动生成 **TCP 账号** 和 **UDP 账号** 各一个，端口随机
- 安装完成后直接输出客户端 JSON 配置和 Clash Meta / Mihomo 配置片段
- **内置订阅服务**：自动生成订阅链接，多格式输出（Clash 片段 / 完整配置 / base64 / URI / JSON）
- **兼容 Sub-Store `remote` 源**：让 Sub-Store 直接订阅本机，节点变更（`mieru regen`）自动生效，无需同步脚本写死内容
- **装完默认就有公网 HTTPS 订阅**：自动在 nginx 443 上反代，复用机器上现有证书，域名默认 `<IP>.sslip.io`，不需要买域名、不需要手工改 nginx
- **订阅可一键切换公网 / 本机**：`mieru sub public` / `mieru sub local`，切到公网后链接自动变成公网地址
- 自动配置防火墙（支持 ufw / iptables / firewalld）
- 支持 BBR 加速一键开启
- VPS 重启后服务自动恢复（systemd 托管）
- 支持 Debian / Ubuntu / CentOS / Rocky Linux

---

## 一键脚本

```bash
wget -O mieru-plus.sh https://raw.githubusercontent.com/helloktity/Mieru-Plus/main/mieru-plus.sh && chmod +x mieru-plus.sh && bash mieru-plus.sh
```

或

```bash
curl -fsSL -o mieru-plus.sh https://raw.githubusercontent.com/helloktity/Mieru-Plus/main/mieru-plus.sh && chmod +x mieru-plus.sh && bash mieru-plus.sh
```

> 只需执行一次。脚本会自动把自身注册为 `mieru` 命令，以后在任意目录输入 `mieru` 即可打开管理面板，无需重复下载。

---

## v2.2.0 更新日志

- **默认公网 HTTPS 订阅**：安装完自动生成 `/etc/nginx/conf.d/50-mieru-sub.conf`，在 **443** 上反代到
  `127.0.0.1` 的订阅服务，装完即有一个外部能直接用的 `https://<域名>/mieru/<token>/sub` 链接
- **域名自动推导**：默认 `<IP 横线形式>.sslip.io`（解析到该 IP，无需 DNS 配置）；也可 `mieru sub domain 你的域名` 指定
- **证书自动复用**：按「nginx 正在用的证书目录 → `/root/cert/domain` → `/root/cert/ip` → 常见路径」顺序挑选，
  用 `openssl -checkhost` 校验是否匹配域名；域名证书不匹配就退用 IP 证书（`https://<IP>/...` 同样可用）
- **端口智能回退**：443 空闲或被 nginx 自己占用就用 443；被别的程序占着则自动回退到 nginx 现有 HTTPS 端口
- **新增子命令**：`mieru sub nginx`（自动配置）/ `nginx-hint`（打印片段，手工贴）/ `nginx-off`（移除片段）/ `domain <名字>`
- **修复切换公网后链接不更新**：`mieru sub public` 之前只改监听地址，链接仍显示 `127.0.0.1`；现在自动换成公网地址，与 snell 脚本行为一致
- **卸载联动**：`mieru uninstall` 一并删除 nginx 片段并 reload
- **失败不干扰**：没有 nginx / 没有证书 / 端口冲突时只提示，Mieru 本体与订阅服务照常运行

---

## v2.1.0 更新日志

- **内置订阅服务**：新增 `mieru-subscription`（systemd 常驻），脚本自己对外提供订阅链接，不再依赖第三方面板
- **兼容 Sub-Store `remote` 源**：与 3x-ui 源一样，Sub-Store 用 URL 订阅，节点变更后由 Sub-Store 缓存周期自动拉取，无需在源里写死节点内容
- **多格式订阅输出**：Clash 片段（默认）/ 完整 Clash 配置 / base64 / 明文 URI / JSON，同一 URL 换 `target` 参数即可
- **菜单新增第 14 项**：订阅服务 / 订阅链接（1–13 编号与行为完全不变）
- **新增子命令**：`mieru sub [show|on|off|restart|status|check|store|nginx|token|server|port|public|local|menu]`
- **实时生效**：服务每次请求都读取 `/etc/mita/.credentials`，`mieru regen` 换端口/密码后订阅立即反映新凭据，无需重启
- **安装即启用**：安装流程末尾自动拉起订阅服务，启用失败只告警，不影响 Mieru 本体
- **导出多一份链接清单**：原 3 个导出文件不变，新增 `subscription.txt`
- **卸载联动清理**：`mieru uninstall` 一并移除订阅服务、unit、脚本与配置
- **纯增量改造**：原有 926 行全部保留（仅版本号变更），订阅为可选特性，`mieru sub off` 停用后回到 v2.0.0 行为

---

## v2.0.0 更新日志

- **运行即进菜单**：自动识别 `mita` 是否已安装，已安装时直接进入管理面板，不再每次执行都重装
- **注册 `mieru` 快捷命令**：首次以 root 运行后，自动复制自身到 `/usr/local/bin/mieru`
- **新增子命令**：`install / status / config / start / stop / restart / upgrade / regen / bbr / logs / export / backup / uninstall / link`
- **升级保留账号**：`mieru upgrade` 只更新 mita 程序，端口与凭据不变
- **重新生成账号**：一键随机更换端口 / 用户名 / 密码
- **配置导出与备份恢复**：客户端配置导出到 `/root/mieru-clients`，配置备份到 `/root/mieru-backup`
- **防火墙增强**：新增 firewalld 支持（原版仅 ufw / iptables）
- **稳定性修复**：移除 `set -e`，避免管道 SIGPIPE 导致脚本中途退出；下载增加重试；dpkg 失败自动补依赖

---

## 菜单说明

```
 ==================================================
   Mieru 管理面板 v2.2.0
   https://github.com/helloktity/Mieru-Plus
 ==================================================
 BBR 加速：  已启用
 服务状态：  运行中
 当前版本：  v3.28.0
 开机自启：  已开启
 --------------------------------------------------
 1.  查看节点信息 / 客户端配置
 2.  启动服务
 3.  停止服务
 4.  重启服务
 5.  设置开机自启
 6.  升级到最新版本（保留账号）
 7.  重新生成账号（换端口 / 换密码）
 8.  一键开启 BBR
 9.  查看日志
 10. 导出配置到文件
 11. 备份 / 恢复配置
 12. 重装 Mieru
 13. 卸载
 14. 订阅服务 / 订阅链接（Sub-Store remote）
 0.  退出
 ==================================================
```

| 选项 | 说明 |
|------|------|
| 1 | 查看当前节点信息、客户端 JSON 配置、Clash Meta 配置片段、mierus:// 导入链接、订阅链接 |
| 2 | 启动 mita 服务 |
| 3 | 停止 mita 服务 |
| 4 | 重启 mita 服务 |
| 5 | 设置 / 确认 systemd 开机自启 |
| 6 | 升级 mita 到最新版本，账号与端口保留 |
| 7 | 随机重新生成端口、用户名、密码（旧配置立即失效，需重新导入客户端；订阅链接不变，内容自动更新） |
| 8 | 一键开启 BBR 网络加速（需内核 4.9+） |
| 9 | 查看最近 200 行日志，或实时跟随（Ctrl+C 退出） |
| 10 | 导出客户端 JSON 与 Clash 配置文件到 `/root/mieru-clients` |
| 11 | 备份 `/etc/mita` 到 `/root/mieru-backup`，或从备份恢复 |
| 12 | 重装 Mieru（重置账号与端口） |
| 13 | 卸载 mita 及所有配置文件（含订阅服务） |
| 14 | 订阅服务子面板：查看链接、启停、重置 token、改端口、切公网/仅本机、自检、nginx 片段 |

### 子命令（非交互）

```bash
mieru status        # 查看版本 / 状态 / BBR / 自启
mieru config        # 输出节点信息与客户端配置
mieru upgrade       # 升级 mita（保留账号）
mieru regen         # 重新生成账号与端口
mieru start|stop|restart
mieru logs          # 最近 200 行日志
mieru export        # 导出配置文件到 /root/mieru-clients
mieru backup        # 备份配置到 /root/mieru-backup
mieru bbr           # 开启 BBR
mieru install --custom   # 安装并手动指定端口 / 账号
mieru uninstall     # 卸载
```

订阅服务（v2.1.0 新增）：

```bash
mieru sub              # 查看订阅链接（默认）
mieru sub on|off       # 启用 / 停用订阅服务
mieru sub restart      # 重启订阅服务
mieru sub status       # 服务状态 + 监听地址
mieru sub check        # 自检：逐个 target 请求本地端点
mieru sub store        # 打印 Sub-Store remote 源配置
mieru sub nginx        # 自动配置公网 HTTPS（nginx 443 + 现有证书）
mieru sub nginx-hint   # 只打印 location 片段，自己贴到已有站点
mieru sub nginx-off    # 移除自动生成的 nginx 片段
mieru sub domain <域名>  # 指定公网域名（默认 <IP>.sslip.io）
mieru sub token        # 重置 40 位 token（旧链接立即失效）
mieru sub server <addr>   # 指定订阅里输出的节点地址（IP 或域名）
mieru sub port <n>     # 修改订阅服务监听端口
mieru sub public       # 切到公网监听 0.0.0.0（链接自动换成公网地址）
mieru sub local        # 改回仅本机 127.0.0.1（同机 Sub-Store 够用）
mieru sub menu         # 进入订阅子面板
```

---

## 订阅服务

### 端点

服务默认监听 `127.0.0.1:13356`，路径含 40 位 token 做鉴权（错 token 返回 404）：

```
/<token>/sub                       Clash proxies 片段（默认，Sub-Store remote 源用这个）
/<token>/sub?target=clash          同上
/<token>/sub?target=clash-full     完整可用的 Clash 配置（直接导入 Verge / Mihomo）
/<token>/sub?target=base64         通用 base64 订阅（mierus:// 明文编码）
/<token>/sub?target=uri            明文 mierus:// 链接
/<token>/sub?target=json           JSON {proxies:[...]}
/<token>/clash.yaml                target=clash 的别名
/<token>/full.yaml                 target=clash-full 的别名
/<token>/base64.txt                target=base64 的别名
/<token>/health                    存活探测（返回 ok）
```

- 所有响应带 `Cache-Control: no-store`
- 多余 query（`noCache=true`、`target=ClashMeta` 等）会被安全忽略，所以 Sub-Store 和客户端可共用同一 URL
- 每次请求实时读 `/etc/mita/.credentials`，`mieru regen` 后订阅内容立即更新
- 节点名与输出风格对齐 Sub-Store 同步脚本（`Mieru-TCP-xxxxx` / `Mieru-UDP-xxxxx`），切换订阅方式不会导致节点重名

### 配置文件

`/etc/mita/.subscription`（600 权限）：

| 键 | 说明 | 默认 |
|---|---|---|
| `SUB_ENABLED` | 是否启用 | `1` |
| `SUB_TOKEN` | 40 位访问 token | 随机 |
| `SUB_PORT` | 监听端口 | `13356` |
| `SUB_BIND` | 监听地址 | `127.0.0.1` |
| `SUB_SERVER` | 订阅里输出的节点地址，留空则自动探测公网 IP | 自动 |

服务文件：`/usr/local/sbin/mieru-subscription`，unit：`/etc/systemd/system/mieru-subscription.service`。
实现只用 python3 标准库（`http.server` / `json` / `base64`），**无 pip 依赖**。

### 在 Sub-Store 中使用（remote 模式）

```bash
mieru sub store        # 直接打印下面这段配置
```

在 Sub-Store 里新增订阅源：

| 字段 | 值 |
|---|---|
| 类型 / source | `remote` |
| 名称 | `mieru`（自定义） |
| URL | `http://127.0.0.1:13356/<token>/sub?target=clash` |
| User-Agent | 任意（不做 UA 区分） |

要点：**不要**再往这个源里填 `content`（节点内容）。Sub-Store 的 remote 源如果残留旧 `content`，会优先用 content 里的旧凭据，表现为「订阅是新的、输出是旧的」。切换成 remote 后请清空该字段。

同机部署时用 `127.0.0.1` 即可，无需开放公网；Sub-Store 每次刷新都会重新请求，节点变更自动跟随。

### 公网访问

**默认已经配好**：安装时如果机器上有 nginx 和证书，脚本会自动在 443 上反代，直接给出

```
https://216-167-114-48.sslip.io/mieru/<token>/sub?target=clash
```

域名默认是 `<IP 横线形式>.sslip.io`，天然解析到本机 IP，不用买域名、不用改 DNS。
证书复用机器上已有的（域名证书优先，没有就退用 IP 证书），也不新申请。

想换域名或换端口：

```bash
mieru sub domain example.com    # 指定域名（证书要能匹配该域名）
mieru sub nginx 8443            # 指定 HTTPS 端口（默认 443）
mieru sub nginx                 # 重新生成片段（幂等，随时可重复执行）
mieru sub nginx-off             # 移除片段，订阅服务本身不受影响
```

没有 nginx，或者不想让脚本动 nginx 配置时，用两种方式之一：

```bash
# 方式一：直接监听公网（明文 HTTP，记得放行防火墙）
mieru sub public

# 方式二：只打印片段，自己贴进已有的 HTTPS server 块
mieru sub nginx-hint
```

片段形如：

```nginx
location /mieru/<token>/ {
  proxy_pass http://127.0.0.1:13356/<token>/;
  proxy_http_version 1.1;
  proxy_set_header Host $host;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_read_timeout 30s;
  add_header Cache-Control "no-store" always;
}
```

切到公网监听（`mieru sub public`）后，`mieru sub` 打印的链接会自动换成 `http://<公网地址>:<端口>/...`，
不用再手工替换 `127.0.0.1`。

---

## 安装效果示例

安装完成后自动输出：

```
 ========== 节点信息 ==========

 [账号 1 · TCP]
  服务器 : 1.2.3.4
  端口   : 38291
  协议   : TCP
  用户名 : tcp_ab3c9f2e
  密码   : Xk9mPqR2sLwN4vZj

 [账号 2 · UDP]
  服务器 : 1.2.3.4
  端口   : 22183
  协议   : UDP
  用户名 : udp_lxkjmxbv
  密码   : yGt8BvuxKr0Qufo8

 [客户端 JSON 配置 · TCP 账号]
{
  "profiles": [
    {
      "profileName": "mieru-tcp",
      "user": { "name": "tcp_ab3c9f2e", "password": "Xk9mPqR2sLwN4vZj" },
      "servers": [{
        "ipAddress": "1.2.3.4",
        "domainName": "",
        "portBindings": [{ "port": 38291, "protocol": "TCP" }]
      }],
      "mtu": 1375
    }
  ],
  "activeProfile": "mieru-tcp",
  "rpcPort": 8964,
  "socks5Port": 1080,
  "loggingLevel": "INFO"
}

 [客户端 JSON 配置 · UDP 账号]
{ ... }

 [Clash Meta / Mihomo 配置]
proxies:
  - name: mieru-tcp
    type: mieru
    server: 1.2.3.4
    port: 38291
    transport: tcp
    username: tcp_ab3c9f2e
    password: Xk9mPqR2sLwN4vZj

  - name: mieru-udp
    ...

 [订阅链接 · Sub-Store remote]
   http://127.0.0.1:13356/<token>/sub?target=clash          (Sub-Store 订阅源 / Clash 片段)
   http://127.0.0.1:13356/<token>/sub?target=clash-full     (完整 Clash 配置)
   http://127.0.0.1:13356/<token>/sub?target=base64         (通用 base64 订阅)
```

---

## 客户端使用

### 官方客户端

1. 从 [mieru releases](https://github.com/enfein/mieru/releases) 下载对应平台的客户端
2. 将安装输出的 JSON 配置保存为 `config.json`
3. 执行：
   ```bash
   mieru apply config config.json
   mieru start
   ```
4. 本地 SOCKS5 代理地址：`127.0.0.1:1080`，HTTP 代理：`127.0.0.1:8080`

### Clash Meta / Mihomo

两种方式：

- 手动：把输出的配置片段复制到 Clash 配置文件的 `proxies:` 部分
- 订阅：直接用 `…/sub?target=clash-full` 作为订阅地址导入，节点变动自动更新

支持的客户端：

**桌面端（Windows / macOS / Linux）**
- [Clash Verge Rev](https://www.clashverge.dev/)
- [Mihomo Party](https://mihomo.party/)

**Android**
- [ClashMetaForAndroid](https://github.com/MetaCubeX/ClashMetaForAndroid)
- [Karing](https://karing.app/)

**iOS**
- [ClashMi](https://clashmi.app/)
- [Karing](https://karing.app/)

---

## 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Debian 10+ / Ubuntu 20.04+ / CentOS 7+ / Rocky Linux 8+ |
| 架构 | x86_64 / aarch64 |
| 内存 | 128MB 以上 |
| 权限 | root |
| 可选 | `python3`（订阅服务用，主流发行版自带；缺失时仅订阅功能不可用） |

---

## 常用命令

```bash
# 查看服务状态
mita status

# 查看当前配置
mita describe config

# 查看日志
journalctl -u mita -f

# 手动启动 / 停止
mita start
mita stop

# 订阅服务日志 / 状态
journalctl -u mieru-subscription -n 50 --no-pager
systemctl status mieru-subscription
```

---

## 回滚

订阅是纯增量特性，关掉即回到 v2.0.0 行为（原有功能不受影响）：

```bash
mieru sub off
```

确认无用后可彻底移除：

```bash
systemctl disable --now mieru-subscription
rm -f /usr/local/sbin/mieru-subscription /etc/systemd/system/mieru-subscription.service /etc/mita/.subscription
systemctl daemon-reload
```

---

## 相关项目

- [mieru](https://github.com/enfein/mieru) — 本脚本所使用的代理核心
- [Sub-Store](https://github.com/sub-store-rs/sub-store) — 订阅管理，可用 `remote` 模式订阅本脚本
- [Sing-Box-Plus](https://github.com/Alvin9999-newpac/Sing-Box-Plus) — 同类一键脚本参考

---

## License

MIT
