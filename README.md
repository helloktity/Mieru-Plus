# Mieru-Plus

mieru 一键安装脚本，自动搭建 TCP 和 UDP 账号，生成官方配置和 Clash Meta / Mihomo 配置。

---

## 特性

- 一键安装，全程无需手动填写配置
- 自动生成 **TCP 账号** 和 **UDP 账号** 各一个，端口随机
- 安装完成后直接输出客户端 JSON 配置和 Clash Meta / Mihomo 配置片段
- 自动配置防火墙（支持 ufw / iptables）
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
   Mieru 管理面板 v2.0.0
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
 0.  退出
 ==================================================
```

| 选项 | 说明 |
|------|------|
| 1 | 查看当前节点信息、客户端 JSON 配置、Clash Meta 配置片段、mierus:// 导入链接 |
| 2 | 启动 mita 服务 |
| 3 | 停止 mita 服务 |
| 4 | 重启 mita 服务 |
| 5 | 设置 / 确认 systemd 开机自启 |
| 6 | 升级 mita 到最新版本，账号与端口保留 |
| 7 | 随机重新生成端口、用户名、密码（旧配置立即失效，需重新导入客户端） |
| 8 | 一键开启 BBR 网络加速（需内核 4.9+） |
| 9 | 查看最近 200 行日志，或实时跟随（Ctrl+C 退出） |
| 10 | 导出客户端 JSON 与 Clash 配置文件到 `/root/mieru-clients` |
| 11 | 备份 `/etc/mita` 到 `/root/mieru-backup`，或从备份恢复 |
| 12 | 重装 Mieru（重置账号与端口） |
| 13 | 卸载 mita 及所有配置文件 |

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

将输出的配置片段复制到 Clash 配置文件的 `proxies:` 部分即可。

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
```

---

## 相关项目

- [mieru](https://github.com/enfein/mieru) — 本脚本所使用的代理核心
- [Sing-Box-Plus](https://github.com/Alvin9999-newpac/Sing-Box-Plus) — 同类一键脚本参考

---

## License

MIT
