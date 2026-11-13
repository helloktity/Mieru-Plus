#!/usr/bin/env bash
# ============================================================
#  Mieru 管理面板  v2.0.0
#  原始项目：https://github.com/Alvin9999-newpac/Mieru-Plus
#  内核项目：https://github.com/enfein/mieru
#
#  本版升级要点：
#   1. 运行即进菜单 —— 不再"每次执行都重装一遍"
#   2. 自动识别安装状态：已安装则直接进管理面板
#   3. 首次安装后自动注册 `mieru` 命令，以后终端里敲 mieru 即可
#   4. 支持子命令，方便脚本化/非交互调用
#   5. 新增：启动/停止/状态/升级/重生成账号/备份恢复/firewalld 放行
#  6. v2.1.0 新增：内置订阅服务，输出订阅链接（兼容 Sub-Store remote 源）
#  7. v2.2.0+ 装完默认自带公网 HTTPS 订阅：服务自己监听 IP + 独立端口，不依赖 nginx
#  8. v2.4.0 变更：公网由服务自己监听独立 HTTPS 端口（IP 证书），不依赖 nginx、不占 443
#     —— 原有功能全部保留，订阅为纯增量特性
# ============================================================

set -uo pipefail

SCRIPT_VERSION="v2.4.0"
MIERU_REPO="enfein/mieru"
UPSTREAM_REPO="Alvin9999-newpac/Mieru-Plus"

MITA_BIN="/usr/bin/mita"
CRED_FILE="/etc/mita/.credentials"
META_FILE="/etc/mita/.meta"
BACKUP_DIR="/root/mieru-backup"
EXPORT_DIR="/root/mieru-clients"
SELF_CMD="/usr/local/bin/mieru"

# v2.1.0 新增：内置订阅服务相关路径
SUB_CONF="/etc/mita/.subscription"
SUB_SVC="/usr/local/sbin/mieru-subscription"
SUB_UNIT="/etc/systemd/system/mieru-subscription.service"
SUB_UNIT_NAME="mieru-subscription"

# ──────────── 颜色 ────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; PLAIN='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; BOLD=''; PLAIN=''
fi

ok()   { echo -e " ${GREEN}[OK]${PLAIN}  $*"; }
warn() { echo -e " ${YELLOW}[!!]${PLAIN}  $*"; }
err()  { echo -e " ${RED}[ERR]${PLAIN} $*"; }
info() { echo -e " ${CYAN}--${PLAIN}   $*"; }
title(){ echo -e "\n${BOLD}${CYAN}$*${PLAIN}\n"; }

pause() {
  [[ -t 0 ]] || return 0
  echo
  read -rp " 按 Enter 返回主菜单..." _ || true
}

confirm() {
  local ans
  read -rp " $1 [y/N]: " ans || return 1
  [[ "${ans,,}" == "y" ]]
}

# ──────────── 基础检测 ────────────
need_root() {
  if [[ $EUID -ne 0 ]]; then
    err "需要 root 权限：sudo bash $0"
    exit 1
  fi
}

need_linux() {
  if [[ "$(uname -s)" != "Linux" && "${MIERU_ALLOW_NON_LINUX:-0}" != "1" ]]; then
    err "本脚本需在 Linux 服务器上运行（Debian/Ubuntu 或 CentOS/Rocky/RHEL）"
    echo  "     当前系统：$(uname -s)"
    echo  "     请先上传到 VPS，再执行：sudo bash mieru-plus.sh"
    exit 1
  fi
}

detect_system() {
  local arch; arch=$(uname -m)
  case "$arch" in
    x86_64|amd64)  DEB_ARCH="amd64"; RPM_ARCH="x86_64"  ;;
    aarch64|arm64) DEB_ARCH="arm64"; RPM_ARCH="aarch64" ;;
    *) err "不支持的架构：$arch"; return 1 ;;
  esac
  if   [[ -f /etc/debian_version ]];   then PKG_TYPE="deb"
  elif [[ -f /etc/redhat-release ]];   then PKG_TYPE="rpm"
  elif [[ -f /etc/alpine-release ]];   then err "Alpine 请使用 mita 官方手动安装方式"; return 1
  else err "仅支持 Debian/Ubuntu 与 CentOS/Rocky/RHEL"; return 1; fi
  return 0
}

# ──────────── 状态查询 ────────────
is_installed() { command -v mita &>/dev/null; }

get_version() {
  is_installed || { echo "未安装"; return; }
  local v=""
  if command -v dpkg &>/dev/null; then
    v=$(dpkg -l mita 2>/dev/null | awk '/^ii/{print $3}' | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  elif command -v rpm &>/dev/null; then
    v=$(rpm -q mita 2>/dev/null | sed 's/^mita-//; s/-[0-9]*\..*$//')
  fi
  [[ -n "$v" ]] && echo "v${v}" || echo "已安装"
}

get_status() {
  is_installed || { echo "未安装"; return; }
  if mita status 2>/dev/null | grep -qi "RUNNING"; then echo "运行中"; else echo "未运行"; fi
}

get_bbr() {
  local cc
  cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
  [[ "$cc" == "bbr" ]] && echo "已启用" || echo "未启用"
}

get_autostart() {
  is_installed || { echo "-"; return; }
  systemctl is-enabled mita &>/dev/null && echo "已开启" || echo "未开启"
}

get_ip() {
  local ip=""
  for u in "https://api.ipify.org" "https://ipv4.icanhazip.com" "https://ipinfo.io/ip"; do
    ip=$(curl -4 -fsS --max-time 4 "$u" 2>/dev/null | tr -d '[:space:]') && [[ -n "$ip" ]] && break
  done
  if [[ -z "$ip" ]]; then
    ip=$(curl -4 -fsS --max-time 4 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null | awk -F= '/^ip=/{print $2}')
  fi
  [[ -z "$ip" ]] && ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
  echo "${ip:-未知}"
}

get_latest_tag() {
  local tag=""
  tag=$(curl -fsSL --max-time 10 "https://api.github.com/repos/${MIERU_REPO}/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
  if [[ -z "$tag" ]]; then
    # API 被限流时退回 releases/latest 跳转地址
    tag=$(curl -fsSI --max-time 10 "https://github.com/${MIERU_REPO}/releases/latest" 2>/dev/null \
          | tr -d '\r' | awk -F'/tag/' '/^[Ll]ocation:/{print $2}' | head -1)
  fi
  echo "$tag"
}

# ──────────── 随机串 / 端口 ────────────
rand_str() {
  local n="${1:-12}" s=""
  s=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom 2>/dev/null | head -c "$n" || true)
  [[ -z "$s" ]] && s=$(openssl rand -hex "$n" 2>/dev/null | cut -c1-"$n")
  echo "$s"
}

rand_port() { echo $(( RANDOM % 40000 + 10000 )); }

# ──────────── 防火墙放行 ────────────
open_port() {
  local port=$1 proto=${2,,}
  [[ -z "$port" ]] && return 0

  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "${port}/${proto}" &>/dev/null && ok "ufw 已放行 ${port}/${proto}"
  fi

  if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
    firewall-cmd --permanent --add-port="${port}/${proto}" &>/dev/null
    firewall-cmd --reload &>/dev/null
    ok "firewalld 已放行 ${port}/${proto}"
  fi

  if command -v iptables &>/dev/null; then
    if ! iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
      iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null \
        && ok "iptables 已放行 ${port}/${proto}"
      command -v netfilter-persistent &>/dev/null && netfilter-persistent save &>/dev/null || true
    fi
  fi
}

# ──────────── 面板 ────────────
show_menu() {
  local VER STATUS BBR AUTO SC BC
  VER=$(get_version); STATUS=$(get_status); BBR=$(get_bbr); AUTO=$(get_autostart)
  [[ "$STATUS" == "运行中" ]] && SC="$GREEN" || SC="$RED"
  [[ "$BBR"    == "已启用" ]] && BC="$GREEN" || BC="$YELLOW"

  clear 2>/dev/null || true
  echo -e "${BOLD}${BLUE}"
  echo " =================================================="
  echo "   Mieru 管理面板 ${SCRIPT_VERSION}"
  echo "   ${UPSTREAM_REPO}"
  echo -e " ==================================================${PLAIN}"
  printf " %-12s ${BC}%s${PLAIN}\n"   "BBR 加速：" "$BBR"
  printf " %-12s ${SC}%s${PLAIN}\n"   "服务状态：" "$STATUS"
  printf " %-12s ${CYAN}%s${PLAIN}\n" "当前版本：" "$VER"
  if is_installed; then
    printf " %-12s ${CYAN}%s${PLAIN}\n" "开机自启：" "$AUTO"
  fi
  echo " --------------------------------------------------"

  if is_installed; then
    echo -e " ${BOLD}1.${PLAIN}  查看节点信息 / 客户端配置"
    echo -e " ${BOLD}2.${PLAIN}  启动服务"
    echo -e " ${BOLD}3.${PLAIN}  停止服务"
    echo -e " ${BOLD}4.${PLAIN}  重启服务"
    echo -e " ${BOLD}5.${PLAIN}  设置开机自启"
    echo -e " ${BOLD}6.${PLAIN}  升级到最新版本（保留账号）"
    echo -e " ${BOLD}7.${PLAIN}  重新生成账号（换端口 / 换密码）"
    echo -e " ${BOLD}8.${PLAIN}  一键开启 BBR"
    echo -e " ${BOLD}9.${PLAIN}  查看日志"
    echo -e " ${BOLD}10.${PLAIN} 导出配置到文件"
    echo -e " ${BOLD}11.${PLAIN} 备份 / 恢复配置"
    echo -e " ${BOLD}12.${PLAIN} 重装 Mieru"
    echo -e " ${BOLD}13.${PLAIN} 卸载"
    echo -e " ${BOLD}14.${PLAIN}  订阅服务 / 订阅链接（Sub-Store remote）"
  else
    echo -e " ${BOLD}1.${PLAIN}  安装 Mieru"
    echo -e " ${BOLD}2.${PLAIN}  一键开启 BBR"
    echo -e " ${BOLD}3.${PLAIN}  注册 mieru 快捷命令"
  fi
  echo -e " ${BOLD}0.${PLAIN}  退出"
  echo " =================================================="
  if is_command_linked; then
    echo -e " ${CYAN}提示：${PLAIN}已注册 mieru 命令，下次直接输入 ${BOLD}mieru${PLAIN} 打开面板"
  else
    echo -e " ${YELLOW}提示：${PLAIN}注册快捷命令后，以后只输入 ${BOLD}mieru${PLAIN} 即可，无需再执行 bash mieru-plus.sh"
  fi
  echo
}

main_menu() {
  local choice
  while true; do
    show_menu
    if ! read -rp " 请输入选项: " choice; then echo; return 0; fi
    if is_installed; then
      case "$choice" in
        1)  do_show        ;;
        2)  do_start       ;;
        3)  do_stop        ;;
        4)  do_restart     ;;
        5)  do_autostart   ;;
        6)  do_upgrade     ;;
        7)  do_regen       ;;
        8)  do_bbr         ;;
        9)  do_logs        ;;
        10) do_export      ;;
        11) do_backup      ;;
        12) do_install_menu ;;
        13) do_uninstall   ;;
        14) sub_menu       ;;
        0)  echo -e "\n 再见！\n"; exit 0 ;;
        *)  warn "无效选项"; sleep 1 ;;
      esac
    else
      case "$choice" in
        1) do_install_menu ;;
        2) do_bbr          ;;
        3) install_command ;;
        0) echo -e "\n 再见！\n"; exit 0 ;;
        *) warn "无效选项"; sleep 1 ;;
      esac
    fi
  done
}

# ──────────── 安装 ────────────
install_package() {
  # $1 = 目标版本号（不含 v），$2 = "upgrade" 时静默
  local ver=$1 quiet=${2:-}
  local TAG="v${ver}" PKG URL TMP RC=0

  [[ "$PKG_TYPE" == "deb" ]] \
    && PKG="mita_${ver}_${DEB_ARCH}.deb" \
    || PKG="mita-${ver}-1.${RPM_ARCH}.rpm"
  URL="https://github.com/${MIERU_REPO}/releases/download/${TAG}/${PKG}"

  TMP=$(mktemp -d)
  info "下载 ${PKG} ..."
  if ! curl -fL --progress-bar --retry 2 --connect-timeout 15 -o "${TMP}/${PKG}" "$URL"; then
    err "下载失败：$URL"
    rm -rf "$TMP"; return 1
  fi

  info "安装中..."
  if [[ "$PKG_TYPE" == "deb" ]]; then
    dpkg -i "${TMP}/${PKG}" >/dev/null 2>&1 || apt-get -f install -y >/dev/null 2>&1 || RC=1
  else
    rpm -Uvh --force "${TMP}/${PKG}" >/dev/null 2>&1 || RC=1
  fi
  rm -rf "$TMP"
  if [[ $RC -ne 0 ]]; then err "安装失败，请检查依赖（apt-get -f install）"; return 1; fi
  [[ -z "$quiet" ]] && ok "安装完成：$(get_version)"
  return 0
}

write_credentials() {
  local tu=$1 tp=$2 tport=$3 uu=$4 up=$5 uport=$6
  local CFG; CFG=$(mktemp)

  cat > "$CFG" <<EOF
{
  "portBindings": [
    { "port": ${tport}, "protocol": "TCP" },
    { "port": ${uport}, "protocol": "UDP" }
  ],
  "users": [
    { "name": "${tu}", "password": "${tp}" },
    { "name": "${uu}", "password": "${up}" }
  ],
  "loggingLevel": "INFO",
  "mtu": 1375
}
EOF

  if ! mita apply config "$CFG" >/dev/null 2>&1; then
    err "写入服务端配置失败"
    cat "$CFG"; rm -f "$CFG"; return 1
  fi
  rm -f "$CFG"

  mkdir -p /etc/mita
  cat > "$CRED_FILE" <<EOF
TCP_USER=${tu}
TCP_PASS=${tp}
TCP_PORT=${tport}
UDP_USER=${uu}
UDP_PASS=${up}
UDP_PORT=${uport}
EOF
  chmod 600 "$CRED_FILE"

  {
    echo "INSTALLED_AT=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "UPDATED_AT=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "PANEL_VERSION=${SCRIPT_VERSION}"
  } >> "$META_FILE"
  chmod 600 "$META_FILE" 2>/dev/null || true
  ok "服务端配置与凭据已写入"
  return 0
}

do_install() {
  local mode=${1:-auto}
  title "===== 安装 Mieru ====="
  need_root
  detect_system || { pause; return 1; }

  if is_installed && [[ "$mode" != "force" ]]; then
    warn "检测到已安装 Mieru：$(get_version)"
    confirm "重装会重置账号与端口，继续？" || { pause; return 0; }
  fi

  info "获取最新版本..."
  local TAG VER
  TAG=$(get_latest_tag)
  if [[ -z "$TAG" ]]; then
    warn "无法获取最新版本号，可手动输入（例如 3.23.0）"
    read -rp " 版本号: " VER || return 1
    [[ -z "$VER" ]] && { err "已取消"; pause; return 1; }
  else
    VER=${TAG#v}
    ok "最新版本：${TAG}"
  fi

  local tu tp tport uu up uport
  if [[ "$mode" == "custom" ]]; then
    echo
    echo " 直接回车使用随机值 / 默认端口"
    read -rp " TCP 端口: " tport;  tport=${tport:-$(rand_port)}
    read -rp " UDP 端口: " uport;  uport=${uport:-$(rand_port)}
    read -rp " TCP 用户名: " tu;  tu=${tu:-tcp_$(rand_str 8)}
    read -rp " TCP 密码: "   tp;  tp=${tp:-$(rand_str 16)}
    read -rp " UDP 用户名: " uu;  uu=${uu:-udp_$(rand_str 8)}
    read -rp " UDP 密码: "   up;  up=${up:-$(rand_str 16)}
    [[ "$tport" == "$uport" ]] && { err "TCP 与 UDP 端口不能相同"; pause; return 1; }
  else
    tport=$(rand_port); uport=$(rand_port)
    while [[ "$uport" == "$tport" ]]; do uport=$(rand_port); done
    tu="tcp_$(rand_str 8)"; tp="$(rand_str 16)"
    uu="udp_$(rand_str 8)"; up="$(rand_str 16)"
  fi

  install_package "$VER" || { pause; return 1; }
  [[ ! -x "$MITA_BIN" ]] && command -v mita >/dev/null

  write_credentials "$tu" "$tp" "$tport" "$uu" "$up" "$uport" || { pause; return 1; }

  open_port "$tport" TCP
  open_port "$uport" UDP

  systemctl enable mita >/dev/null 2>&1 || true
  mita start >/dev/null 2>&1 || true
  sleep 2
  ok "服务状态：$(get_status)"

  # 自动注册 mieru 命令，便于以后直接调出面板
  install_command quiet

  # v2.1.0 新增：安装完同时启用订阅服务（失败不影响 Mieru 本体）
  sub_enable || true
  # 顺手把公网 HTTPS 订阅也配好（有 IP 证书才生效，失败只提示，不影响本体）
  sub_tls_enable >/dev/null 2>&1 || warn "公网 HTTPS 未自动开启，可稍后执行：mieru sub public"

  _show_config
  pause
  return 0
}

do_install_menu() { do_install "${1:-auto}"; }

# ──────────── 节点信息 ────────────
_show_config() {
  if [[ ! -f "$CRED_FILE" ]]; then
    warn "未找到凭据文件（$CRED_FILE），请先安装或重新生成账号"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$CRED_FILE"
  local IP; IP=$(get_ip)

  echo -e "\n${BOLD}${GREEN} ========== 节点信息 ==========${PLAIN}\n"
  echo -e " ${BOLD}[账号 1 · TCP]${PLAIN}"
  echo   "   服务器 : ${IP}"
  echo   "   端口   : ${TCP_PORT}"
  echo   "   用户名 : ${TCP_USER}"
  echo   "   密码   : ${TCP_PASS}"
  echo
  echo -e " ${BOLD}[账号 2 · UDP]${PLAIN}"
  echo   "   服务器 : ${IP}"
  echo   "   端口   : ${UDP_PORT}"
  echo   "   用户名 : ${UDP_USER}"
  echo   "   密码   : ${UDP_PASS}"

  echo
  echo -e " ${BOLD}[客户端 JSON · TCP]${PLAIN}"
  cat <<EOF
{
  "profiles": [
    {
      "profileName": "mieru-tcp",
      "user": { "name": "${TCP_USER}", "password": "${TCP_PASS}" },
      "servers": [{
        "ipAddress": "${IP}",
        "domainName": "",
        "portBindings": [{ "port": ${TCP_PORT}, "protocol": "TCP" }]
      }],
      "mtu": 1375
    }
  ],
  "activeProfile": "mieru-tcp",
  "rpcPort": 8964,
  "socks5Port": 1080,
  "loggingLevel": "INFO"
}
EOF

  echo
  echo -e " ${BOLD}[客户端 JSON · UDP]${PLAIN}"
  cat <<EOF
{
  "profiles": [
    {
      "profileName": "mieru-udp",
      "user": { "name": "${UDP_USER}", "password": "${UDP_PASS}" },
      "servers": [{
        "ipAddress": "${IP}",
        "domainName": "",
        "portBindings": [{ "port": ${UDP_PORT}, "protocol": "UDP" }]
      }],
      "mtu": 1375
    }
  ],
  "activeProfile": "mieru-udp",
  "rpcPort": 8964,
  "socks5Port": 1080,
  "loggingLevel": "INFO"
}
EOF

  echo
  echo -e " ${BOLD}[Clash Meta / Mihomo]${PLAIN}"
  cat <<EOF
proxies:
  - name: mieru-tcp
    type: mieru
    server: ${IP}
    port: ${TCP_PORT}
    transport: tcp
    username: ${TCP_USER}
    password: ${TCP_PASS}

  - name: mieru-udp
    type: mieru
    server: ${IP}
    port: ${UDP_PORT}
    transport: udp
    username: ${UDP_USER}
    password: ${UDP_PASS}
EOF

  echo
  echo -e " ${BOLD}[导入链接]${PLAIN}（客户端支持 mierus:// 时可直接粘贴）"
  echo "   mierus://?profileName=mieru-tcp&user=${TCP_USER}&password=${TCP_PASS}&ipAddress=${IP}&port=${TCP_PORT}&protocol=TCP"
  echo "   mierus://?profileName=mieru-udp&user=${UDP_USER}&password=${UDP_PASS}&ipAddress=${IP}&port=${UDP_PORT}&protocol=UDP"
  # ── v2.1.0 新增：订阅链接（原有输出保持不变） ──
  if [[ -f "$SUB_CONF" ]]; then
    local SUB_L
    SUB_L="http://127.0.0.1:$(sub_get SUB_PORT)/$(sub_get SUB_TOKEN)"
    echo -e " ${BOLD}[订阅链接 · Sub-Store remote]${PLAIN}"
    echo "   ${SUB_L}/sub?target=clash          (Sub-Store 订阅源 / Clash 片段)"
    echo "   ${SUB_L}/sub?target=clash-full     (完整 Clash 配置)"
    echo "   ${SUB_L}/sub?target=base64         (通用 base64 订阅)"
    local PUB_L
    if PUB_L=$(sub_public_url); then
      echo "   公网 HTTPS：${PUB_L}/sub?target=clash"
    fi
    echo "   更多格式 / 公网链接 / 自检：mieru sub"
  fi
  echo -e "\n${BOLD}${GREEN} ==============================${PLAIN}\n"
  return 0
}

do_show() {
  title "===== 节点信息 & 客户端配置 ====="
  is_installed || { err "mita 未安装"; pause; return 1; }
  _show_config && pause
}

write_client_files() {
  # shellcheck source=/dev/null
  source "$CRED_FILE"
  local IP; IP=$(get_ip)
  mkdir -p "$EXPORT_DIR"

  cat > "${EXPORT_DIR}/mieru-tcp.json" <<EOF
{
  "profiles": [
    {
      "profileName": "mieru-tcp",
      "user": { "name": "${TCP_USER}", "password": "${TCP_PASS}" },
      "servers": [{
        "ipAddress": "${IP}",
        "domainName": "",
        "portBindings": [{ "port": ${TCP_PORT}, "protocol": "TCP" }]
      }],
      "mtu": 1375
    }
  ],
  "activeProfile": "mieru-tcp",
  "rpcPort": 8964,
  "socks5Port": 1080,
  "loggingLevel": "INFO"
}
EOF

  cat > "${EXPORT_DIR}/mieru-udp.json" <<EOF
{
  "profiles": [
    {
      "profileName": "mieru-udp",
      "user": { "name": "${UDP_USER}", "password": "${UDP_PASS}" },
      "servers": [{
        "ipAddress": "${IP}",
        "domainName": "",
        "portBindings": [{ "port": ${UDP_PORT}, "protocol": "UDP" }]
      }],
      "mtu": 1375
    }
  ],
  "activeProfile": "mieru-udp",
  "rpcPort": 8964,
  "socks5Port": 1080,
  "loggingLevel": "INFO"
}
EOF

  cat > "${EXPORT_DIR}/clash-mieru.yaml" <<EOF
proxies:
  - name: mieru-tcp
    type: mieru
    server: ${IP}
    port: ${TCP_PORT}
    transport: tcp
    username: ${TCP_USER}
    password: ${TCP_PASS}

  - name: mieru-udp
    type: mieru
    server: ${IP}
    port: ${UDP_PORT}
    transport: udp
    username: ${UDP_USER}
    password: ${UDP_PASS}
EOF

  # v2.1.0 新增：导出一份订阅链接清单（原有三个文件不变）
  if [[ -f "$SUB_CONF" ]]; then
    local SUB_L="http://127.0.0.1:$(sub_get SUB_PORT)/$(sub_get SUB_TOKEN)"
    cat > "${EXPORT_DIR}/subscription.txt" <<EOF
Mieru-Plus subscription links
Sub-Store remote : ${SUB_L}/sub?target=clash
Clash fragment   : ${SUB_L}/sub?target=clash
Clash full       : ${SUB_L}/sub?target=clash-full
Base64           : ${SUB_L}/sub?target=base64
URI plain        : ${SUB_L}/sub?target=uri
JSON             : ${SUB_L}/sub?target=json
Health           : ${SUB_L}/health
EOF
  fi
  chmod 600 "${EXPORT_DIR}"/* 2>/dev/null || true
  return 0
}

do_export() {
  title "===== 导出配置到文件 ====="
  [[ -f "$CRED_FILE" ]] || { err "未找到凭据文件"; pause; return 1; }
  write_client_files || { err "导出失败"; pause; return 1; }
  ok "已导出到 ${EXPORT_DIR}"
  ls -1 "$EXPORT_DIR"
  pause
}

do_export_cli() {
  [[ -f "$CRED_FILE" ]] || { err "未找到凭据文件"; exit 1; }
  write_client_files || exit 1
  ok "已导出到 ${EXPORT_DIR}"
  ls -1 "$EXPORT_DIR"
}

# ──────────── 服务控制 ────────────
do_start() {
  is_installed || { err "mita 未安装"; pause; return 1; }
  if [[ "$(get_status)" == "运行中" ]]; then ok "服务已在运行"; pause; return 0; fi
  mita start >/dev/null 2>&1 || true
  sleep 2
  ok "启动完成，状态：$(get_status)"
  pause
}

do_stop() {
  is_installed || { err "mita 未安装"; pause; return 1; }
  confirm "确认停止 Mieru 服务？" || { pause; return 0; }
  mita stop >/dev/null 2>&1 || true
  sleep 1
  ok "已停止，状态：$(get_status)"
  pause
}

do_restart() {
  is_installed || { err "mita 未安装"; pause; return 1; }
  mita stop >/dev/null 2>&1 || true
  sleep 1
  mita start >/dev/null 2>&1 || true
  sleep 2
  ok "重启完成，状态：$(get_status)"
  pause
}

do_autostart() {
  title "===== 开机自启 ====="
  is_installed || { err "mita 未安装"; pause; return 1; }
  if [[ "$(get_autostart)" == "已开启" ]]; then
    ok "开机自启已开启"
  else
    systemctl enable mita >/dev/null 2>&1 && ok "已设置开机自启：$(systemctl is-enabled mita 2>/dev/null)"
  fi
  pause
}

# ──────────── 升级 ────────────
do_upgrade() {
  title "===== 升级 Mieru ====="
  need_root
  is_installed || { err "mita 未安装，请先安装"; pause; return 1; }
  detect_system || { pause; return 1; }

  local cur latest
  cur=$(get_version); cur=${cur#v}
  latest=$(get_latest_tag)
  if [[ -z "$latest" ]]; then err "获取最新版本失败，请检查网络"; pause; return 1; fi

  info "当前版本：v${cur}    最新版本：${latest}"
  if [[ "v${cur}" == "$latest" ]]; then ok "已是最新版本，无需升级"; pause; return 0; fi

  confirm "升级到 ${latest}（账号与端口保留）？" || { pause; return 0; }
  install_package "${latest#v}" || { pause; return 1; }

  echo "UPDATED_AT=$(date '+%Y-%m-%d %H:%M:%S')" >> "$META_FILE"
  mita stop >/dev/null 2>&1 || true
  sleep 1
  mita start >/dev/null 2>&1 || true
  sleep 2
  ok "升级完成：$(get_version)  状态：$(get_status)"
  pause
}

# ──────────── 重新生成账号 ────────────
do_regen() {
  title "===== 重新生成账号 ====="
  need_root
  is_installed || { err "mita 未安装"; pause; return 1; }
  warn "将随机生成新的端口 / 用户名 / 密码，旧配置立即失效（客户端需重新导入）"
  confirm "继续？" || { pause; return 0; }

  local tu tp tport uu up uport
  tport=$(rand_port); uport=$(rand_port)
  while [[ "$uport" == "$tport" ]]; do uport=$(rand_port); done
  tu="tcp_$(rand_str 8)"; tp="$(rand_str 16)"
  uu="udp_$(rand_str 8)"; up="$(rand_str 16)"

  write_credentials "$tu" "$tp" "$tport" "$uu" "$up" "$uport" || { pause; return 1; }
  open_port "$tport" TCP
  open_port "$uport" UDP

  mita stop >/dev/null 2>&1 || true
  sleep 1
  mita start >/dev/null 2>&1 || true
  sleep 2
  ok "已重新生成，状态：$(get_status)"
  _show_config
  pause
}

# ──────────── BBR ────────────
do_bbr() {
  title "===== 开启 BBR ====="
  need_root
  if [[ "$(get_bbr)" == "已启用" ]]; then ok "BBR 已启用"; pause; return 0; fi

  local major minor
  major=$(uname -r | cut -d. -f1); minor=$(uname -r | cut -d. -f2)
  if [[ ${major:-0} -lt 4 ]] || { [[ ${major:-0} -eq 4 ]] && [[ ${minor:-0} -lt 9 ]]; }; then
    err "内核 $(uname -r) 版本过低，需 4.9+"; pause; return 1
  fi

  grep -qs "tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null \
    || echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
  modprobe tcp_bbr 2>/dev/null || true

  [[ -f /etc/sysctl.conf ]] || touch /etc/sysctl.conf
  grep -qs "net.core.default_qdisc=fq" /etc/sysctl.conf \
    || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  grep -qs "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf \
    || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1 || true

  ok "BBR 状态：$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
  pause
}

# ──────────── 日志 ────────────
do_logs() {
  title "===== 日志 ====="
  is_installed || { err "mita 未安装"; pause; return 1; }
  echo " 1) 最近 200 行   2) 实时跟随（Ctrl+C 退出）"
  local c
  read -rp " 选择 [1-2]: " c || return 0
  if [[ "$c" == "2" ]]; then
    journalctl -u mita -f --no-hostname -o cat
    pause
  else
    journalctl -u mita -n 200 --no-pager -o cat
    pause
  fi
}

# ──────────── 备份 / 恢复 ────────────
do_backup() {
  title "===== 备份 / 恢复 ====="
  need_root
  mkdir -p "$BACKUP_DIR"
  echo " 1) 备份当前配置   2) 从备份恢复   3) 返回"
  local c
  read -rp " 选择 [1-3]: " c || return 0
  case "$c" in
    1)
      local f="${BACKUP_DIR}/mieru-$(date +%Y%m%d-%H%M%S).tar.gz"
      if tar czf "$f" -C / etc/mita 2>/dev/null; then
        chmod 600 "$f"; ok "已备份：$f"
      else
        err "备份失败"
      fi
      ;;
    2)
      local list=()
      while IFS= read -r line; do list+=("$line"); done < <(ls -1t "${BACKUP_DIR}"/mieru-*.tar.gz 2>/dev/null)
      if [[ ${#list[@]} -eq 0 ]]; then warn "没有可用备份"; pause; return 0; fi
      local i=1
      for f in "${list[@]}"; do echo "  ${i}) $(basename "$f")"; i=$((i+1)); done
      local n; read -rp " 选择备份编号: " n || return 0
      [[ "$n" =~ ^[0-9]+$ ]] && [[ $n -ge 1 && $n -le ${#list[@]} ]] || { err "编号无效"; pause; return 1; }
      local src="${list[$((n-1))]}"
      confirm "用 $(basename "$src") 覆盖当前配置？" || { pause; return 0; }
      tar xzf "$src" -C / && ok "已恢复：$src，请重启服务使其生效"
      ;;
    *) : ;;
  esac
  pause
}

# ──────────── 卸载 ────────────
do_uninstall() {
  title "===== 卸载 Mieru ====="
  need_root
  is_installed || { warn "mita 未安装"; pause; return 0; }
  warn "将删除 mita 程序与 /etc/mita 下的全部配置（备份请先做）"
  confirm "确认卸载？" || { pause; return 0; }

  mita stop >/dev/null 2>&1 || true
  systemctl disable mita >/dev/null 2>&1 || true
  detect_system || true

  if [[ "${PKG_TYPE:-}" == "deb" ]] && command -v apt-get &>/dev/null; then
    apt-get remove -y mita >/dev/null 2>&1 || dpkg -r mita >/dev/null 2>&1 || true
  elif [[ "${PKG_TYPE:-}" == "rpm" ]] && command -v rpm &>/dev/null; then
    rpm -e mita >/dev/null 2>&1 || true
  fi

  sub_cleanup   # v2.1.0 新增：一并移除订阅服务
  rm -rf /etc/mita /var/lib/mita /var/log/mita 2>/dev/null || true
  rm -f "$SELF_CMD" 2>/dev/null || true
  ok "Mieru 已卸载"
  pause
}

# ──────────── 订阅服务（v2.1.0 纯增量新增，v2.2.0 加公网 HTTPS） ────────────
# 目标：让本脚本自己输出一个订阅 URL，Sub-Store 可以像 3x-ui 那样用
#       source=remote 订阅它，而不必由同步脚本写死 local content。
#   * 每次请求实时读取 /etc/mita/.credentials，执行 regen 后立刻生效
#   * 只用 python3 标准库，不需要 PyYAML / pip
#   * 响应带 no-store，避免 Sub-Store 缓存旧节点
#   * 默认仅监听 127.0.0.1（与同机 Sub-Store 通信），可切到公网或用 nginx 反代
sub_get() {
  local k=$1
  [[ -f "$SUB_CONF" ]] || { echo ""; return 1; }
  sed -n "s/^${k}=//p" "$SUB_CONF" | tail -1
}

sub_set() {
  local k=$1 v=$2
  sub_ensure_conf || return 1
  if grep -q "^${k}=" "$SUB_CONF" 2>/dev/null; then
    sed -i "s|^${k}=.*|${k}=${v}|" "$SUB_CONF"
  else
    echo "${k}=${v}" >> "$SUB_CONF"
  fi
  chmod 600 "$SUB_CONF"
}

sub_ensure_conf() {
  mkdir -p /etc/mita || return 1
  [[ -f "$SUB_CONF" ]] && return 0
  local token port ip used i
  token=$(rand_str 40)
  used="$(sed -n 's/^TCP_PORT=//p' "$CRED_FILE" 2>/dev/null) $(sed -n 's/^UDP_PORT=//p' "$CRED_FILE" 2>/dev/null)"
  port=$(rand_port)
  for i in $(seq 1 30); do
    [[ " $used " == *" $port "* ]] || break
    port=$(rand_port)
  done
  ip=$(get_ip)
  if [[ -z "$ip" || "$ip" == "未知" ]]; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi
  [[ -z "$ip" ]] && ip="127.0.0.1"
  cat > "$SUB_CONF" <<EOF
SUB_ENABLED=1
SUB_TOKEN=${token}
SUB_PORT=${port}
SUB_BIND=127.0.0.1
SUB_SERVER=${ip}
SUB_TLS_ENABLED=0
SUB_TLS_PORT=40331
SUB_CERT=
SUB_KEY=
SUB_PUBLIC=
SUB_CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')
EOF
  chmod 600 "$SUB_CONF"
  ok "已生成订阅配置：$SUB_CONF"
  return 0
}

sub_write_service() {
  mkdir -p /usr/local/sbin
  cat > "$SUB_SVC" <<'PYEOF'
#!/usr/bin/env python3
"""Mieru-Plus subscription endpoint.

Serves the current TCP/UDP Mieru accounts as a subscription so that Sub-Store
can consume it as a normal ``remote`` source (instead of a hand-maintained
``local`` source), and so that Clash Verge / Mihomo / Karing / Shadowrocket
users can import a plain URL.

Only the Python standard library is used on purpose: the service must run on a
minimal Debian/Ubuntu/CentOS box without pip packages.

Routes (TOKEN comes from /etc/mita/.subscription)::

    GET /<TOKEN>/sub                       Clash proxies fragment (default)
    GET /<TOKEN>/sub?target=clash          same as above
    GET /<TOKEN>/sub?target=clash-full     ready-to-use Clash config
    GET /<TOKEN>/sub?target=base64         base64 of mierus:// URI lines
    GET /<TOKEN>/sub?target=uri            plain mierus:// URI lines
    GET /<TOKEN>/sub?target=json           JSON {proxies: [...]}
    GET /<TOKEN>/clash.yaml                alias of target=clash
    GET /<TOKEN>/full.yaml                 alias of target=clash-full
    GET /<TOKEN>/base64.txt                alias of target=base64
    GET /<TOKEN>/health                    liveness probe

Every response is marked no-store, because Sub-Store (and proxy clients) must
always see freshly regenerated accounts. Unknown query parameters such as
``noCache=true`` or ``target=ClashMeta`` are ignored safely, which keeps the
URL usable both as a Sub-Store remote source and as a client import link.
"""

import base64
import json
import os
import pathlib
import re
import sys
import time
import ssl
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CRED_FILE = pathlib.Path(
    os.environ.get('MIERU_CRED_FILE', '/etc/mita/.credentials')
)
CONF_FILE = pathlib.Path(
    os.environ.get('MIERU_SUB_CONF', '/etc/mita/.subscription')
)

YAML_SPECIAL = re.compile(r"[:#\[\]{}&*!|>'\"%@`,]")
YAML_KEYWORDS = {
    'true', 'false', 'null', 'yes', 'no', 'on', 'off', '~', 'none',
}


def read_kv(path):
    result = {}
    try:
        text = path.read_text(encoding='utf-8')
    except OSError:
        return result
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        result[key.strip()] = value.strip()
    return result


def yaml_scalar(value):
    text = str(value)
    if (
        not text
        or YAML_SPECIAL.search(text)
        or text.lower() in YAML_KEYWORDS
        or text[0] in ' -?'
        or text[-1] in ' '
    ):
        return "'" + text.replace("'", "''") + "'"
    return text


def build_proxies():
    """Read credentials on every request so `mieru regen` is instantly live."""
    cred = read_kv(CRED_FILE)
    conf = read_kv(CONF_FILE)
    server = conf.get('SUB_SERVER') or ''
    if not server or server == '未知':
        server = '127.0.0.1'
    proxies = []
    for proto in ('TCP', 'UDP'):
        user = cred.get(proto + '_USER')
        password = cred.get(proto + '_PASS')
        port = cred.get(proto + '_PORT')
        if not (user and password and port and str(port).isdigit()):
            continue
        # Names mirror the ones produced by sub-store-automation, so switching
        # a collection from local to remote does not rename existing nodes.
        proxies.append({
            'name': 'Mieru-%s-%s' % (proto, port),
            'type': 'mieru',
            'server': server,
            'port': int(port),
            'transport': proto,
            'username': user,
            'password': password,
        })
    return proxies


def clash_fragment(proxies):
    lines = ['proxies:']
    for proxy in proxies:
        lines.append('- name: ' + yaml_scalar(proxy['name']))
        for key in ('type', 'server', 'port', 'transport', 'username', 'password'):
            lines.append('  %s: %s' % (key, yaml_scalar(proxy[key])))
    return '\n'.join(lines) + '\n'


def clash_full(proxies):
    names = [proxy['name'] for proxy in proxies]
    lines = [
        'mixed-port: 7890',
        'socks-port: 7891',
        'allow-lan: false',
        'mode: rule',
        'log-level: info',
        'external-controller: 127.0.0.1:9090',
        'geodata-mode: true',
        'unified-delay: true',
        'tcp-concurrent: true',
        '',
        clash_fragment(proxies).rstrip('\n'),
        '',
        'proxy-groups:',
        '- name: PROXY',
        '  type: select',
        '  proxies:',
    ]
    lines += ['    - ' + yaml_scalar(name) for name in names]
    lines += [
        '    - DIRECT',
        '',
        'rules:',
        '- MATCH,PROXY',
    ]
    return '\n'.join(lines) + '\n'


def uri_lines(proxies):
    lines = []
    for proxy in proxies:
        query = urllib.parse.urlencode({
            'profileName': proxy['name'],
            'user': proxy['username'],
            'password': proxy['password'],
            'ipAddress': proxy['server'],
            'port': proxy['port'],
            'protocol': proxy['transport'],
        })
        lines.append('mierus://?' + query)
    return '\n'.join(lines) + ('\n' if lines else '')


def render(proxies, target):
    if target in ('clash-full', 'full', 'config'):
        return clash_full(proxies), 'text/plain; charset=utf-8'
    if target in ('base64', 'b64', 'v2ray', 'general'):
        payload = base64.b64encode(uri_lines(proxies).encode('utf-8'))
        return payload.decode('ascii') + '\n', 'text/plain; charset=utf-8'
    if target in ('uri', 'raw', 'plain', 'mierus'):
        return uri_lines(proxies), 'text/plain; charset=utf-8'
    if target in ('json', 'js'):
        return (
            json.dumps({'proxies': proxies}, ensure_ascii=False, indent=2) + '\n',
            'application/json; charset=utf-8',
        )
    # default: Clash proxies fragment -- what Sub-Store parses best
    return clash_fragment(proxies), 'text/plain; charset=utf-8'


PATH_TARGETS = {
    'clash.yaml': 'clash',
    'full.yaml': 'clash-full',
    'base64.txt': 'base64',
    'uri.txt': 'uri',
    'json': 'json',
    'sub': '',
}


class Handler(BaseHTTPRequestHandler):
    server_version = 'MieruSub/1.0'
    protocol_version = 'HTTP/1.1'

    def log_message(self, fmt, *args):
        sys.stderr.write(
            '[%s] %s %s\n'
            % (time.strftime('%Y-%m-%d %H:%M:%S'), self.address_string(), fmt % args)
        )

    def _reply(self, status, body=b'', content_type='text/plain; charset=utf-8',
               head=False):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        if not head and body:
            self.wfile.write(body)

    def _authorized(self, parts, query, token):
        if not token:
            return False, parts
        if parts and parts[0] == token:
            return True, parts[1:]
        supplied = (query.get('token') or [''])[0]
        if supplied == token:
            return True, parts
        return False, parts

    def _serve(self, head=False):
        parsed = urllib.parse.urlparse(self.path)
        parts = [item for item in parsed.path.split('/') if item]
        query = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
        token = read_kv(CONF_FILE).get('SUB_TOKEN', '')
        allowed, rest = self._authorized(parts, query, token)
        if not allowed:
            self._reply(404, head=head)
            return

        tail = (rest[0] if rest else 'sub').lower()
        if tail == 'health':
            self._reply(200, b'ok\n', head=head)
            return
        if tail not in PATH_TARGETS:
            self._reply(404, head=head)
            return

        target = (query.get('target') or [''])[0].strip().lower()
        if not target:
            target = PATH_TARGETS.get(tail, '')
        proxies = build_proxies()
        text, content_type = render(proxies, target)
        self._reply(200, text.encode('utf-8'), content_type, head=head)

    def do_GET(self):
        try:
            self._serve(head=False)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:  # keep the service alive on a bad request
            sys.stderr.write('subscription error: %r\n' % (exc,))
            try:
                self._reply(500, b'error\n')
            except OSError:
                pass

    def do_HEAD(self):
        try:
            self._serve(head=True)
        except Exception as exc:
            sys.stderr.write('subscription error: %r\n' % (exc,))


class TLSServer(ThreadingHTTPServer):
    """独立的 HTTPS 监听。

    证书文件 mtime 变了会自动重载，所以 acme.sh 续期之后不用重启服务。
    非 TLS 的扫描流量会在握手阶段直接丢掉，不打印 traceback。
    """

    def __init__(self, addr, handler, cert, key):
        self.cert = cert
        self.key = key
        self._stamp = None
        self._ctx = None
        super().__init__(addr, handler)
        self._reload(force=True)

    def _reload(self, force=False):
        try:
            stamp = (os.path.getmtime(self.cert), os.path.getmtime(self.key))
        except OSError:
            return
        if not force and stamp == self._stamp:
            return
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        try:
            ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        except (AttributeError, ValueError):
            pass
        ctx.load_cert_chain(self.cert, self.key)
        self._ctx = ctx
        self._stamp = stamp

    def get_request(self):
        self._reload()
        sock, addr = super().get_request()
        return self._ctx.wrap_socket(sock, server_side=True), addr

    def handle_error(self, request, client_address):
        pass


def main():
    conf = read_kv(CONF_FILE)
    bind = os.environ.get('MIERU_SUB_BIND') or conf.get('SUB_BIND') or '127.0.0.1'
    if bind in ('0.0.0.0', '::', '*', ''):
        bind = '0.0.0.0'
    port = int(os.environ.get('MIERU_SUB_PORT') or conf.get('SUB_PORT') or '30999')
    server = ThreadingHTTPServer((bind, port), Handler)
    server.daemon_threads = True
    print('Mieru subscription listening on http://%s:%s/<token>/sub' % (bind, port), flush=True)

    tls_server = None
    if (conf.get('SUB_TLS_ENABLED') or '0').strip() == '1':
        tls_port = int((conf.get('SUB_TLS_PORT') or '0').strip() or 0)
        cert = (conf.get('SUB_CERT') or '').strip()
        key = (conf.get('SUB_KEY') or '').strip()
        if tls_port and os.path.isfile(cert) and os.path.isfile(key):
            try:
                tls_server = TLSServer(('0.0.0.0', tls_port), Handler, cert, key)
                tls_server.daemon_threads = True
                print('Mieru subscription listening on https://0.0.0.0:%s/<token>/sub' % tls_port, flush=True)
            except OSError as exc:
                sys.stderr.write('HTTPS listen on %s failed: %r\n' % (tls_port, exc))
                tls_server = None
        else:
            sys.stderr.write('HTTPS disabled: missing cert/key or port (%s / %s / %s)\n' % (tls_port, cert, key))

    if tls_server:
        threading.Thread(target=tls_server.serve_forever, daemon=True).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        if tls_server:
            tls_server.server_close()


if __name__ == '__main__':
    main()
PYEOF
  chmod 755 "$SUB_SVC"
}

sub_write_unit() {
  local pybin
  pybin=$(command -v python3)
  cat > "$SUB_UNIT" <<EOF
[Unit]
Description=Mieru-Plus Subscription Endpoint (Sub-Store remote source)
Documentation=https://github.com/helloktity/Mieru-Plus
After=network.target mita.service
Wants=mita.service

[Service]
Type=simple
ExecStart=${pybin} ${SUB_SVC}
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
# 证书常在 /root/cert 下，这里必须可读；用 read-only 而不是 true
ProtectHome=read-only
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$SUB_UNIT"
}

sub_enable() {
  need_root
  if ! command -v python3 >/dev/null 2>&1; then
    warn "未找到 python3，订阅服务不可用（Mieru 其余功能不受影响）"
    return 1
  fi
  sub_ensure_conf || return 1
  sub_write_service
  sub_write_unit
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now "$SUB_UNIT_NAME" >/dev/null 2>&1 || true
  sleep 1
  if systemctl is-active --quiet "$SUB_UNIT_NAME"; then
    ok "订阅服务已启动：$(sub_get SUB_BIND):$(sub_get SUB_PORT)"
    return 0
  fi
  warn "订阅服务启动失败，可执行 journalctl -u ${SUB_UNIT_NAME} -n 50 排查"
  return 1
}

sub_disable() {
  need_root
  systemctl disable --now "$SUB_UNIT_NAME" >/dev/null 2>&1 || true
  ok "订阅服务已停止（配置文件保留，可执行 mieru sub on 恢复）"
}

sub_restart() {
  need_root
  sub_write_service
  sub_write_unit
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart "$SUB_UNIT_NAME" >/dev/null 2>&1 || true
  sleep 1
  ok "订阅服务状态：$(systemctl is-active "$SUB_UNIT_NAME" 2>/dev/null || echo 未启动)"
}

sub_status() {
  echo "订阅服务：$(systemctl is-active "$SUB_UNIT_NAME" 2>/dev/null || echo 未启动)"
  echo "开机自启：$(systemctl is-enabled "$SUB_UNIT_NAME" 2>/dev/null || echo 未开启)"
  [[ -f "$SUB_CONF" ]] && {
    echo "监听地址：$(sub_get SUB_BIND):$(sub_get SUB_PORT)"
    echo "节点地址：$(sub_get SUB_SERVER)"
  }
  echo "配置文件：${SUB_CONF}"
}

sub_check() {
  [[ -f "$SUB_CONF" ]] || { err "订阅服务尚未启用，执行：mieru sub on"; return 1; }
  systemctl is-active --quiet "$SUB_UNIT_NAME" 2>/dev/null || {
    err "服务没在运行，先执行：mieru sub on"
    return 1
  }
  local token base url code count failed=0 tmp
  token=$(sub_get SUB_TOKEN)
  base="http://127.0.0.1:$(sub_get SUB_PORT)/${token}"
  tmp=$(mktemp)

  echo
  echo -e "${BOLD}${CYAN} 自检：$(sub_get SUB_BIND):$(sub_get SUB_PORT)${PLAIN}"
  for target in clash clash-full base64 uri json; do
    url="${base}/sub?target=${target}"
    code=$(curl -s -o "$tmp" -w '%{http_code}' --max-time 10 "$url" 2>/dev/null)
    case "$target" in
      clash|clash-full) count=$(awk '/^proxies:/{f=1;next} /^[a-zA-Z-]+:/{f=0} f&&/^- name:/{c++} END{print c+0}' "$tmp" 2>/dev/null) ;;
      *)                count="" ;;
    esac
    if [[ "$code" == "200" ]]; then
      if [[ -n "$count" ]]; then
        echo -e "  ${GREEN}[OK]${PLAIN}   ${target}   HTTP ${code}   ${count} 个节点"
      else
        echo -e "  ${GREEN}[OK]${PLAIN}   ${target}   HTTP ${code}"
      fi
    else
      echo -e "  ${RED}[FAIL]${PLAIN} ${target}   HTTP ${code}"
      failed=1
    fi
  done
  rm -f "$tmp"

  local health
  health=$(curl -s --max-time 5 "${base}/health" 2>/dev/null)
  if [[ "$health" == "ok" ]]; then
    echo -e "  ${GREEN}[OK]${PLAIN}   health    HTTP 200"
  else
    echo -e "  ${RED}[FAIL]${PLAIN} health    ${health:-无响应}"
    failed=1
  fi

  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$(sub_get SUB_PORT)/sub" 2>/dev/null)
  if [[ "$code" == "404" ]]; then
    echo -e "  ${GREEN}[OK]${PLAIN}   无 token  正确返回 404"
  else
    echo -e "  ${YELLOW}[!!]${PLAIN} 无 token  返回 ${code}（预期 404）"
  fi

  echo -e "\n${CYAN} 内容预览（密码已脱敏）：${PLAIN}"
  curl -fsS --max-time 5 "${base}/sub?target=clash" 2>/dev/null | sed 's/password: .*/password: ***/'
  return $failed
}

sub_links() {
  [[ -f "$SUB_CONF" ]] || { warn "订阅服务尚未启用，执行：mieru sub on"; return 1; }
  local token port bind server base label pub
  token=$(sub_get SUB_TOKEN)
  port=$(sub_get SUB_PORT)
  bind=$(sub_get SUB_BIND)
  server=$(sub_get SUB_SERVER)

  # 订阅服务默认只监听回环；公网由同一进程另开 HTTPS 端口（IP 证书），不发明文链接
  base="http://127.0.0.1:${port}/${token}"
  label="本机 · 回环不出网，Sub-Store 同机用"
  pub=$(sub_public_url 2>/dev/null) || pub=""

  echo
  echo -e "${BOLD}${CYAN} ========== 订阅链接 ==========${PLAIN}"
  echo " 服务状态 : $(systemctl is-active "$SUB_UNIT_NAME" 2>/dev/null || echo 未启动)   监听 : ${bind}:${port}   节点地址 : ${server}"

  if [[ -n "$pub" ]]; then
    echo
    echo -e " ${BOLD}[公网 HTTPS]${PLAIN}  外部客户端 / 其它机器上的 Sub-Store"
    echo "   ${pub}/sub?target=clash"
    echo "   ${pub}/sub?target=clash-full      (完整 Clash 配置)"
    echo "   ${pub}/sub?target=base64          (通用 base64)"
    echo "   ${pub}/sub?target=surge           (Surge)"
    echo "   ${pub}/health                     (存活探测)"
  fi

  echo
  echo -e " ${BOLD}[${label}]${PLAIN}"
  echo "   ${base}/sub?target=clash"
  echo "   ${base}/sub?target=clash-full      (完整 Clash 配置)"
  echo "   ${base}/sub?target=base64          (通用 base64)"
  echo "   ${base}/sub?target=uri             (明文 URI)"
  echo "   ${base}/sub?target=json            (JSON)"
  echo "   ${base}/health                     (存活探测)"

  echo
  if [[ -n "$pub" ]]; then
    info "公网经独立 HTTPS 端口对外；回环地址只给同机 Sub-Store"
  else
    warn "当前只有本机链接（外部不可用）"
    echo "   开公网 HTTPS：mieru sub public     关闭：mieru sub local"
  fi
  if [[ "$bind" != "127.0.0.1" ]]; then
    warn "检测到监听地址是 ${bind}（明文 HTTP 已不再使用），建议执行：mieru sub local"
  fi
  echo -e " ${YELLOW}链接等同凭据，别公开贴；泄露后 mieru sub token 重置${PLAIN}"
  echo -e "${BOLD}${CYAN} ================================${PLAIN}"
}

sub_store_hint() {
  [[ -f "$SUB_CONF" ]] || { err "订阅服务尚未启用，执行：mieru sub on"; return 1; }
  local base
  base="http://127.0.0.1:$(sub_get SUB_PORT)/$(sub_get SUB_TOKEN)"
  echo
  echo -e "${BOLD}${CYAN} Sub-Store 订阅源配置（source = remote）${PLAIN}"
  echo " 在 Sub-Store 中新建「订阅」，类型选远程 / remote，URL 填："
  echo "   ${base}/sub?target=clash"
  echo
  echo " 对应的 sub-store.json 条目："
  cat <<EOF
{
  "displayName": "Mieru · Running",
  "source": "remote",
  "url": "${base}/sub?target=clash",
  "process": [],
  "name": "autoscan-node-mieru"
}
EOF
  echo
  echo " 提示："
  echo "  * 节点名保持 Mieru-TCP-<端口> / Mieru-UDP-<端口>，切换后集合里名称不变"
  echo "  * 响应已带 Cache-Control: no-store；若 Sub-Store 仍缓存，下载链接加 &noCache=true"
  echo "  * 执行 mieru regen 换端口/密码后，本 URL 内容立即更新，无需改 Sub-Store"
  echo "  * URL 带 40 位随机 token，请勿公开分享；mieru sub token 可重新生成"
  echo
}

# 公网 HTTPS（服务自己监听独立端口，不碰 nginx / 443）
sub_tls_port_free() {   # <port> 无人监听 -> 0
  [ -n "$1" ] || return 1
  ! ss -lntH "sport = :$1" 2>/dev/null | grep -q .
}

# 输出 "cert|key"：优先能覆盖本机 IP 的证书
sub_pick_ip_cert() {
  local ip d c k x
  ip=$(sub_get SUB_SERVER)
  [ -n "$ip" ] || ip=$(get_ip)
  [ -n "$ip" ] && [ "$ip" != "未知" ] || ip=$(hostname -I 2>/dev/null | awk '{print $1}')

  local -a cands=()
  while IFS= read -r x; do
    [[ -n "$x" ]] && cands+=("$(dirname "$x")")
  done < <(nginx -T 2>/dev/null | awk '/ssl_certificate /{print $2}' | tr -d ';' | sort -u)
  cands+=(/root/cert/ip /root/cert/domain /etc/nginx/certs /etc/ssl/mieru /etc/pki/tls/mieru)

  if command -v openssl >/dev/null 2>&1; then
    for d in "${cands[@]}"; do
      c="$d/fullchain.pem"; k="$d/privkey.pem"
      [[ -f "$c" && -f "$k" ]] || continue
      if openssl x509 -in "$c" -noout -checkhost "$ip" 2>/dev/null | grep -q 'does match'; then
        echo "${c}|${k}"; return 0
      fi
    done
  fi
  for d in "${cands[@]}"; do
    c="$d/fullchain.pem"; k="$d/privkey.pem"
    [[ -f "$c" && -f "$k" ]] && { echo "${c}|${k}"; return 0; }
  done
  return 1
}

sub_tls_port_pick() {   # 默认 40331，被占就往后找
  local p base
  base=$(sub_get SUB_TLS_PORT)
  [[ -n "$base" ]] || base=40331
  for p in "$base" $(seq 40331 40360); do
    sub_tls_port_free "$p" && { echo "$p"; return 0; }
  done
  return 1
}

sub_tls_enable() {   # [port]
  sub_ensure_conf || return 1
  local picked cert key port code ip
  picked=$(sub_pick_ip_cert) || {
    err "没找到证书（fullchain.pem / privkey.pem），无法启用 HTTPS"
    info "先给本机 IP 签一张证书（acme.sh / certbot），再执行：mieru sub public"
    return 1
  }
  cert=${picked%%|*}; key=${picked#*|}
  ip=$(sub_get SUB_SERVER)

  port=${1:-$(sub_get SUB_TLS_PORT)}
  [[ -n "$port" ]] || port=40331
  if ! sub_tls_port_free "$port"; then
    port=$(sub_tls_port_pick) || { err "找不到可用端口"; return 1; }
    info "默认端口被占用，改用 ${port}"
  fi

  sub_set SUB_TLS_ENABLED 1
  sub_set SUB_TLS_PORT "$port"
  sub_set SUB_CERT "$cert"
  sub_set SUB_KEY "$key"
  sub_set SUB_BIND "127.0.0.1"
  open_port "$port" TCP >/dev/null 2>&1 || true
  sub_restart || return 1

  sleep 1
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 \
    "https://${ip}:${port}/$(sub_get SUB_TOKEN)/health" 2>/dev/null)
  if [[ "$code" == "200" ]]; then
    sub_set SUB_PUBLIC "https://${ip}:${port}/$(sub_get SUB_TOKEN)"
    ok "公网 HTTPS 已就绪：https://${ip}:${port}/<token>/sub?target=clash"
    info "证书 ${cert}，端口 ${port}（不占 443，与 nginx 无关）"
  else
    err "端口已监听但自检失败（HTTP ${code:-超时}）"
    info "排查：journalctl -u ${SUB_UNIT_NAME} -n 30"
    return 1
  fi
}

sub_tls_disable() {
  sub_ensure_conf || return 1
  sub_set SUB_TLS_ENABLED 0
  sub_set SUB_PUBLIC ""
  sub_restart >/dev/null 2>&1 || true
  ok "已关闭公网 HTTPS（订阅服务仍监听 127.0.0.1，同机 Sub-Store 照常可用）"
}

# 公网链接（有则打印，无则返回 1）
sub_public_url() {
  local pub
  pub=$(sub_get SUB_PUBLIC)
  [[ -n "$pub" ]] || return 1
  [[ "$(sub_get SUB_TLS_ENABLED)" == "1" ]] || return 1
  echo "$pub"
}

sub_cleanup() {
  systemctl disable --now "$SUB_UNIT_NAME" >/dev/null 2>&1 || true
  rm -f "$SUB_SVC" "$SUB_UNIT" "$SUB_CONF" 2>/dev/null || true
  rm -rf /var/www/mieru-sub 2>/dev/null || true
  systemctl daemon-reload >/dev/null 2>&1 || true
}

# ── 订阅动作：菜单与 CLI 共用（与 snell 脚本同一套结构） ──
sub_reset_token() {
  sub_ensure_conf || return 1
  sub_set SUB_TOKEN "$(rand_str 40)"
  ok "已重置 token（服务实时读取，无需重启）"
  info "旧链接立即失效；Sub-Store 若由同步脚本维护，下个周期会自动更新 URL"
  sub_links
}

sub_change_port() {
  sub_ensure_conf || return 1
  local new_port
  read -rp " 新的订阅端口（当前 $(sub_get SUB_PORT)）: " new_port || return 1
  [[ "$new_port" =~ ^[0-9]+$ ]] || { err "端口必须是数字"; return 1; }
  (( new_port >= 1 && new_port <= 65535 )) || { err "端口范围是 1-65535"; return 1; }
  sub_set SUB_PORT "$new_port"
  sub_restart || return 1
  sub_links
}

sub_change_server() {
  sub_ensure_conf || return 1
  local addr old
  old=$(sub_get SUB_SERVER)
  read -rp " 节点地址（本机公网 IP，当前 ${old:-未设置}）: " addr || return 1
  if [[ -z "$addr" ]]; then info "未修改"; return 0; fi
  sub_set SUB_SERVER "$addr"
  ok "节点地址已设为 ${addr}"
  # 公网开着的话，证书与链接都跟着新地址重建
  if [[ "$(sub_get SUB_TLS_ENABLED)" == "1" ]]; then
    sub_tls_enable && sub_links && return 0
  fi
  sub_links
}

sub_change_tls_port() {
  sub_ensure_conf || return 1
  local cur p
  cur=$(sub_get SUB_TLS_PORT)
  read -rp " 新的 HTTPS 端口（当前 ${cur:-40331}，回车不改）: " p || return 1
  [[ -n "$p" ]] || { info "未修改"; return 0; }
  [[ "$p" =~ ^[0-9]+$ ]] || { err "端口必须是数字"; return 1; }
  (( p >= 1 && p <= 65535 )) || { err "端口范围是 1-65535"; return 1; }
  sub_set SUB_TLS_PORT "$p"
  if [[ "$(sub_get SUB_TLS_ENABLED)" == "1" ]]; then
    sub_tls_enable "$p" || return 1
  else
    ok "HTTPS 端口已设为 ${p}（下次 mieru sub public 生效）"
  fi
  sub_links
}

# 公网订阅只走 HTTPS：订阅服务永久只监听回环，不再提供 0.0.0.0 明文监听
sub_do_public() {
  sub_tls_enable "${1:-}" || return 1
  sub_links
}

sub_do_local() {
  sub_tls_disable
  sub_links
}

sub_toggle_public() {
  sub_ensure_conf || return 1
  if [[ "$(sub_get SUB_TLS_ENABLED)" == "1" ]]; then
    sub_do_local
  else
    sub_do_public
  fi
}

sub_cli() {
  local action=${1:-show} arg=${2:-}
  case "$action" in
    show|"")          sub_links ;;
    on|enable|start)  sub_ensure_conf && sub_enable && sub_links ;;
    off|disable|stop) sub_disable ;;
    restart)          sub_restart ;;
    status)           sub_status ;;
    check|test)       sub_check ;;
    store|remote)     sub_store_hint ;;
    https|tls)        sub_tls_enable && sub_links ;;
    tls-off)          sub_tls_disable && sub_links ;;
    tls-port)
      if [[ -n "$arg" ]]; then
        [[ "$arg" =~ ^[0-9]+$ ]] || { err "用法：mieru sub tls-port <1-65535>"; return 1; }
        sub_set SUB_TLS_PORT "$arg"
        [[ "$(sub_get SUB_TLS_ENABLED)" == "1" ]] && sub_tls_enable "$arg"
        sub_links
      else
        sub_change_tls_port
      fi ;;
    token)            sub_reset_token ;;
    port)
      if [[ -n "$arg" ]]; then
        [[ "$arg" =~ ^[0-9]+$ ]] || { err "用法：mieru sub port <1-65535>"; return 1; }
        (( arg >= 1 && arg <= 65535 )) || { err "端口范围是 1-65535"; return 1; }
        sub_set SUB_PORT "$arg"
        sub_restart
        [[ "$(sub_get SUB_BIND)" != "127.0.0.1" ]] && open_port "$arg" TCP
        sub_links
      else
        sub_change_port
      fi ;;
    server)
      if [[ -n "$arg" ]]; then
        sub_set SUB_SERVER "$arg"
        ok "节点地址已设为 ${arg}（无需重启）"
      else
        sub_change_server
      fi ;;
    public)           sub_do_public ;;
    local|private)    sub_do_local ;;
    menu)             sub_menu ;;
    -h|--help|help)
      echo "用法：mieru sub [show|on|off|restart|status|check|store|https|tls-port [n]|token|port [n]|server [addr]|public|local|menu]" ;;
    *)
      err "未知订阅操作：${action}"
      echo "用法：mieru sub [show|on|off|restart|status|check|store|https|tls-port [n]|token|port [n]|server [addr]|public|local|menu]"
      return 1 ;;
  esac
}

sub_menu() {
  local choice
  while true; do
    echo
    echo -e "${BOLD}${CYAN} ========== 订阅服务（Sub-Store / Clash） ==========${PLAIN}"
    echo -e "  ${BOLD}1.${PLAIN}  查看订阅链接 / 启用服务"
    echo -e "  ${BOLD}2.${PLAIN}  停用服务"
    echo -e "  ${BOLD}3.${PLAIN}  重启服务"
    echo -e "  ${BOLD}4.${PLAIN}  服务状态"
    echo -e "  ${BOLD}5.${PLAIN}  自检（逐个目标请求一次）"
    echo -e "  ${BOLD}6.${PLAIN}  Sub-Store remote 源怎么填"
    echo -e "  ${BOLD}7.${PLAIN}  开公网 HTTPS（IP + 独立端口）"
    echo -e "  ${BOLD}8.${PLAIN}  重置 token"
    echo -e "  ${BOLD}9.${PLAIN}  修改订阅端口"
    echo -e "  ${BOLD}10.${PLAIN} 设置节点地址"
    echo -e "  ${BOLD}11.${PLAIN} 开 / 关公网 HTTPS（仅本机 ↔ 公网）"
    echo -e "  ${BOLD}12.${PLAIN} 修改 HTTPS 端口"
    echo -e "  ${BOLD}0.${PLAIN}  返回主菜单"
    if ! read -rp "  请选择: " choice; then return 0; fi
    case "$choice" in
      1)  sub_ensure_conf && sub_enable && sub_links ;;
      2)  sub_disable ;;
      3)  sub_restart ;;
      4)  sub_status ;;
      5)  sub_check ;;
      6)  sub_store_hint ;;
      7)  sub_tls_enable && sub_links ;;
      8)  sub_reset_token ;;
      9)  sub_change_port ;;
      10) sub_change_server ;;
      11) sub_toggle_public ;;
      12) sub_change_tls_port ;;
      0)  return 0 ;;
      *)  err "请输入正确的选项" ;;
    esac
    if ! read -rp "  按回车继续..." _; then return 0; fi
  done
}

# ──────────── 注册 mieru 命令 ────────────
install_command() {
  local quiet=${1:-}
  need_root

  if [[ ! -f "$0" ]]; then
    [[ -z "$quiet" ]] && warn "当前是从管道运行的（$0），无法自动注册命令。请先把脚本保存到本地再执行。"
    return 1
  fi

  if [[ "$(readlink -f "$0" 2>/dev/null || echo "$0")" == "$SELF_CMD" ]]; then
    [[ -z "$quiet" ]] && { ok "快捷命令已就绪：直接输入 mieru 打开面板"; }
    return 0
  fi

  if cp -f "$0" "$SELF_CMD" 2>/dev/null && chmod +x "$SELF_CMD"; then
    if [[ -z "$quiet" ]]; then
      ok "已注册命令：mieru"
      info "以后在任意目录直接输入 mieru 即可打开本面板，不必再执行 bash mieru-plus.sh"
    fi
    return 0
  fi

  err "注册失败（$SELF_CMD 不可写）"
  return 1
}

is_command_linked() {
  [[ -x "$SELF_CMD" ]]
}

# ──────────── 帮助 ────────────
usage() {
  cat <<EOF
 Mieru 管理面板 ${SCRIPT_VERSION}

 用法：
   bash $0                 打开交互菜单（推荐）
   mieru                   同上（安装后可用）
   bash $0 <子命令>        非交互执行

 子命令：
   install [--custom]   安装（--custom 手动指定端口/账号）
   status               查看状态
   config               输出节点信息与客户端配置
   start | stop | restart
   upgrade              升级到最新版本（保留账号）
   regen                重新生成账号与端口
   bbr                  开启 BBR
   logs                 最近日志
   export               导出配置文件到 ${EXPORT_DIR}
   backup               备份配置
   uninstall            卸载
   link                 注册 mieru 快捷命令
   sub                  查看订阅链接 / 订阅服务管理（v2.1.0 新增）
     sub on|off|restart|status|check
     sub store          打印 Sub-Store remote 源配置
     sub nginx          打印 nginx 反代片段（公网 HTTPS 订阅）
     sub token|server <addr>|port <n>|public|local|menu

 说明：安装后配置文件位于 /etc/mita，凭据在 ${CRED_FILE}（600 权限）。
       订阅配置在 ${SUB_CONF}（600 权限），服务名 ${SUB_UNIT_NAME}。
EOF
}

# ──────────── 入口 ────────────
main() {
  need_linux

  case "${1:-}" in
    "")            need_root; install_command quiet >/dev/null 2>&1 || true; main_menu ;;
    install)       shift; [[ "${1:-}" == "--custom" ]] && do_install custom || do_install force ;;
    status)
      echo "版本：$(get_version)"
      echo "状态：$(get_status)"
      echo "BBR ：$(get_bbr)"
      echo "自启：$(get_autostart)" ;;
    config)        need_root; _show_config ;;
    start)         need_root; mita start >/dev/null 2>&1; sleep 2; echo "状态：$(get_status)" ;;
    stop)          need_root; mita stop >/dev/null 2>&1; sleep 1; echo "状态：$(get_status)" ;;
    restart)       need_root; mita stop >/dev/null 2>&1; sleep 1; mita start >/dev/null 2>&1; sleep 2; echo "状态：$(get_status)" ;;
    upgrade)       need_root; do_upgrade_cli ;;
    regen)         need_root; do_regen_cli ;;
    bbr)           need_root; do_bbr_cli ;;
    logs)          need_root; is_installed || { err "mita 未安装"; exit 1; }; journalctl -u mita -n 200 --no-pager -o cat ;;
    export)        need_root; do_export_cli ;;
    backup)        need_root; mkdir -p "$BACKUP_DIR"; f="${BACKUP_DIR}/mieru-$(date +%Y%m%d-%H%M%S).tar.gz"; tar czf "$f" -C / etc/mita && echo "已备份：$f" ;;
    uninstall)     need_root; do_uninstall_cli ;;
    link)          install_command ;;
    sub|subscribe) shift; need_root; sub_cli "$@" ;;
    -h|--help|help) usage ;;
    *) err "未知参数：$1"; usage; exit 1 ;;
  esac
}

# 非交互版本（供子命令复用，避免 pause 卡住）
do_upgrade_cli() {
  is_installed || { err "mita 未安装"; exit 1; }
  detect_system || exit 1
  local cur latest
  cur=$(get_version); cur=${cur#v}
  latest=$(get_latest_tag)
  [[ -z "$latest" ]] && { err "获取最新版本失败"; exit 1; }
  if [[ "v${cur}" == "$latest" ]]; then ok "已是最新版本 v${cur}"; return 0; fi
  install_package "${latest#v}" || exit 1
  mita stop >/dev/null 2>&1 || true; sleep 1; mita start >/dev/null 2>&1 || true; sleep 2
  ok "升级完成：$(get_version)  状态：$(get_status)"
}

do_regen_cli() {
  is_installed || { err "mita 未安装"; exit 1; }
  local tport uport
  tport=$(rand_port); uport=$(rand_port); while [[ "$uport" == "$tport" ]]; do uport=$(rand_port); done
  write_credentials "tcp_$(rand_str 8)" "$(rand_str 16)" "$tport" "udp_$(rand_str 8)" "$(rand_str 16)" "$uport" || exit 1
  open_port "$tport" TCP; open_port "$uport" UDP
  mita stop >/dev/null 2>&1 || true; sleep 1; mita start >/dev/null 2>&1 || true; sleep 2
  echo "状态：$(get_status)"
  _show_config
}

do_bbr_cli() {
  local major minor
  major=$(uname -r | cut -d. -f1); minor=$(uname -r | cut -d. -f2)
  if [[ ${major:-0} -lt 4 ]] || { [[ ${major:-0} -eq 4 ]] && [[ ${minor:-0} -lt 9 ]]; }; then
    err "内核 $(uname -r) 低于 4.9，不支持 BBR"; exit 1
  fi
  grep -qs "tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null || echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
  modprobe tcp_bbr 2>/dev/null || true
  [[ -f /etc/sysctl.conf ]] || touch /etc/sysctl.conf
  grep -qs "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  grep -qs "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1 || true
  ok "BBR 状态：$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
}

do_uninstall_cli() {
  is_installed || { warn "mita 未安装"; return 0; }
  mita stop >/dev/null 2>&1 || true
  systemctl disable mita >/dev/null 2>&1 || true
  detect_system || true
  if [[ "${PKG_TYPE:-}" == "deb" ]] && command -v apt-get &>/dev/null; then
    apt-get remove -y mita >/dev/null 2>&1 || dpkg -r mita >/dev/null 2>&1 || true
  elif [[ "${PKG_TYPE:-}" == "rpm" ]]; then
    rpm -e mita >/dev/null 2>&1 || true
  fi
  sub_cleanup   # v2.1.0 新增：一并移除订阅服务
  rm -rf /etc/mita /var/lib/mita /var/log/mita /usr/local/bin/mieru 2>/dev/null || true
  ok "Mieru 已卸载"
}

main "$@"
