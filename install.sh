#!/bin/sh
# ============================================================
# Snell v1 ~ v6 多系统一键安装脚本
# ============================================================
# 支持发行版：
#   - Alpine Linux (musl + OpenRC, 需 gcompat 兼容层)
#   - Debian / Ubuntu / Raspbian (glibc + systemd)
#   - RHEL / CentOS / Rocky / AlmaLinux / Fedora / Amazon Linux / Oracle Linux (glibc + systemd)
#   - Arch Linux / Manjaro / Artix (glibc + systemd / OpenRC)
#   - openSUSE Leap / Tumbleweed / SLES (glibc + systemd)
#   - Void Linux (glibc + runit)
#
# Init 系统：systemd / OpenRC / runit
# 架构：amd64 (x86_64) / aarch64 (arm64)
#
# 用法：
#   ./install.sh
#   SNELL_VERSION=6.0.0rc2 ./install.sh
#   NONINTERACTIVE=1 SNELL_PORT=8388 ./install.sh
# ============================================================

set -eu

# ============================================================
# 已知最新版本映射表
# 数据来源：
#   - Surge 官方 release notes:
#     https://kb.nssurge.com/surge-knowledge-base/zh/release-notes/snell
#   - GitHub (v1):
#     https://github.com/surge-networks/snell/releases
#
# 格式：大版本号|具体版本号|下载源
# 下载源：nssurge（官方 CDN） / github（v1 历史 release）
# ============================================================
KNOWN_LATEST="
v1|1.1.1|github
v2|2.0.1|nssurge
v3|3.0.1|nssurge
v4|4.1.1|nssurge
v5|5.0.1|nssurge
v6|6.0.0rc2|nssurge
"

# ============================================================
# 默认值（用户回车即采用）
# ============================================================
DEFAULT_MAJOR="v6"
DEFAULT_PORT="6160"
DEFAULT_LISTEN="0.0.0.0"
DEFAULT_IPV6="true"
DEFAULT_OBFS="off"

# ============================================================
# 路径
# ============================================================
SNELL_BASE_DIR="/usr/local/snell"
SNELL_VERSIONS_DIR="${SNELL_BASE_DIR}/versions"
SNELL_CURRENT_LINK="${SNELL_BASE_DIR}/current"
SNELL_BIN_LINK="/usr/local/bin/snell-server"
SNELL_CONF_DIR="/etc/snell"
SNELL_CONF_FILE="${SNELL_CONF_DIR}/snell-server.conf"
SNELL_DOWNLOAD_HOST="https://dl.nssurge.com/snell"
SNELL_GITHUB_HOST="https://github.com/surge-networks/snell/releases/download"

# ============================================================
# 颜色日志
# ============================================================
if [ -t 1 ]; then
    C_INFO='\033[1;34m[INFO]\033[0m'
    C_OK='\033[1;32m[OK]\033[0m'
    C_WARN='\033[1;33m[WARN]\033[0m'
    C_ERR='\033[1;31m[ERROR]\033[0m'
    C_PROMPT='\033[1;36m[?]\033[0m'
else
    C_INFO='[INFO]'
    C_OK='[OK]'
    C_WARN='[WARN]'
    C_ERR='[ERROR]'
    C_PROMPT='[?]'
fi

log_info()   { printf "%b %s\n" "$C_INFO"   "$1"; }
log_ok()     { printf "%b %s\n" "$C_OK"     "$1"; }
log_warn()   { printf "%b %s\n" "$C_WARN"   "$1"; }
log_err()    { printf "%b %s\n" "$C_ERR"    "$1"; }
log_prompt() { printf "%b %s"   "$C_PROMPT" "$1"; }

# ============================================================
# 通用工具
# ============================================================
lookup_latest() {
    local major="$1"
    echo "$KNOWN_LATEST" | awk -F'|' -v m="$major" '$1==m {print $2; exit}'
}

lookup_source() {
    local major="$1"
    echo "$KNOWN_LATEST" | awk -F'|' -v m="$major" '$1==m {print $3; exit}'
}

is_interactive() {
    [ "${NONINTERACTIVE:-0}" != "1" ] && [ -t 0 ]
}

# ============================================================
# 1. 系统检测
# ============================================================
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_err "请使用 root 权限运行（su 或 sudo）"
        exit 1
    fi
}

detect_os() {
    if [ ! -f /etc/os-release ]; then
        log_err "无法识别系统（缺少 /etc/os-release）"
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_NAME="${PRETTY_NAME:-unknown}"
    OS_FAMILY=""

    case "$OS_ID" in
        alpine)            OS_FAMILY="alpine" ;;
        debian|ubuntu|raspbian|kubuntu)
                            OS_FAMILY="debian" ;;
        centos|rhel|rocky|almalinux|fedora|amzn|ol|virtuozzo)
                            OS_FAMILY="rhel" ;;
        arch|manjaro|artix) OS_FAMILY="arch" ;;
        opensuse*|sles)    OS_FAMILY="suse" ;;
        void)              OS_FAMILY="void" ;;
        *)
            # 退化到 ID_LIKE 推断
            case "${ID_LIKE:-}" in
                *debian*)    OS_FAMILY="debian" ;;
                *rhel*|*fedora*|*centos*) OS_FAMILY="rhel" ;;
                *arch*)      OS_FAMILY="arch" ;;
                *suse*)      OS_FAMILY="suse" ;;
                *alpine*)    OS_FAMILY="alpine" ;;
                *void*)      OS_FAMILY="void" ;;
                *)
                    log_err "不支持的系统: $OS_ID (ID_LIKE=${ID_LIKE:-})"
                    log_err "已支持: alpine / debian / rhel / arch / suse / void"
                    exit 1
                    ;;
            esac
            ;;
    esac

    log_info "系统: $OS_NAME"
    log_info "  ID=$OS_ID  FAMILY=$OS_FAMILY"
}

detect_arch() {
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  SNELL_ARCH="amd64"   ;;
        aarch64|arm64) SNELL_ARCH="aarch64" ;;
        *)
            log_err "不支持的架构: $arch (仅 amd64 / aarch64)"
            exit 1
            ;;
    esac
    log_info "架构: $arch → $SNELL_ARCH"
}

detect_init() {
    # 优先级：systemd > OpenRC > runit
    if [ -d /run/systemd/system ] || pidof systemd >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    elif [ -f /sbin/openrc-run ] && [ -d /etc/init.d ]; then
        INIT_SYSTEM="openrc"
    elif command -v sv >/dev/null 2>&1; then
        INIT_SYSTEM="runit"
    else
        INIT_SYSTEM="unknown"
    fi
    log_info "Init: $INIT_SYSTEM"
}

# ============================================================
# 2. 包管理抽象
# ============================================================
pkg_update() {
    case "$OS_FAMILY" in
        alpine) apk update >/dev/null ;;
        debian) apt-get update -qq ;;
        rhel)
            if command -v dnf >/dev/null 2>&1; then
                dnf -y makecache >/dev/null
            elif command -v yum >/dev/null 2>&1; then
                yum -y makecache >/dev/null
            fi
            ;;
        arch)  pacman -Sy --noconfirm >/dev/null ;;
        suse)  zypper --non-interactive refresh >/dev/null ;;
        void)  xbps-install -S >/dev/null ;;
        *) log_warn "未知系统家族: $OS_FAMILY"; return 1 ;;
    esac
}

pkg_install() {
    [ $# -eq 0 ] && return 0
    case "$OS_FAMILY" in
        alpine) apk add "$@" ;;
        debian) DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        rhel)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y "$@"
            elif command -v yum >/dev/null 2>&1; then
                yum install -y "$@"
            fi
            ;;
        arch)  pacman -S --noconfirm "$@" ;;
        suse)  zypper --non-interactive install "$@" ;;
        void)  xbps-install -y "$@" ;;
        *) log_err "未知系统家族: $OS_FAMILY"; return 1 ;;
    esac
}

install_deps() {
    log_info "安装依赖..."
    pkg_update

    # 通用依赖：下载与解压工具
    local common_deps="curl wget unzip"

    # 系统特定依赖
    local family_deps=""
    case "$OS_FAMILY" in
        alpine)
            # musl 需要 gcompat 兼容层运行 glibc 二进制
            family_deps="gcompat openrc"
            ;;
        *)
            # glibc 系统不需要兼容层；systemd 自带
            family_deps=""
            ;;
    esac

    # 非交互式询问是否安装基础工具
    if [ -z "${SKIP_DEPS_INSTALL:-}" ]; then
        if ! is_interactive; then
            log_info "非交互模式，自动安装依赖: $common_deps $family_deps"
            pkg_install $common_deps $family_deps
        else
            log_prompt "是否安装依赖 ($common_deps $family_deps)？[Y/n]: "
            read -r ans
            case "${ans:-Y}" in
                n|N|no|NO)
                    log_warn "跳过依赖安装，请确保 $common_deps $family_deps 已存在"
                    ;;
                *)
                    pkg_install $common_deps $family_deps
                    ;;
            esac
        fi
    fi
    log_ok "依赖检查完成"
}

# ============================================================
# 端口占用检测（ss → netstat → /proc/net/tcp 三级 fallback）
# ============================================================
# 全局变量：
#   PORT_PID — 占用端口的进程 PID（若可识别），调用后会被覆盖
# 返回值：
#   0 = 端口空闲
#   1 = 端口被占用（LISTEN 状态）
# ============================================================
check_port_in_use() {
    local port="$1"
    PORT_PID=""

    # ---- 第一层：ss（iproute2，主流 Linux 默认安装）----
    if command -v ss >/dev/null 2>&1; then
        # -t tcp, -l listen, -n numeric, -H no header, -p process
        local line
        line=$(ss -tlnHp "sport = :$port" 2>/dev/null | tail -n +2)
        if [ -n "$line" ]; then
            PORT_PID=$(echo "$line" | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)
            return 1
        fi
        return 0
    fi

    # ---- 第二层：netstat（net-tools，少数旧系统）----
    if command -v netstat >/dev/null 2>&1; then
        local line
        line=$(netstat -tlnp 2>/dev/null | grep -E "[:.]$port[[:space:]]")
        if [ -n "$line" ]; then
            PORT_PID=$(echo "$line" | awk '{
                for (i=1; i<=NF; i++) {
                    if ($i ~ /^[0-9]+\/[-_a-zA-Z0-9]+$/) {
                        split($i, a, "/")
                        print a[1]
                        exit
                    }
                }
            }')
            return 1
        fi
        return 0
    fi

    # ---- 第三层：直接读 /proc/net/tcp{,6}（任何 Linux 都有）----
    local hex_port
    hex_port=$(printf "%04X" "$port")
    local found=0
    for f in /proc/net/tcp /proc/net/tcp6; do
        [ -r "$f" ] || continue
        # 状态 0A = LISTEN；匹配第二列 local_port 结尾是 hex_port
        if awk -v hp=":$hex_port" 'NR>1 && $2 ~ hp"$" && $4 == "0A" { found=1; exit } END { exit !found }' "$f"; then
            found=1
            break
        fi
    done
    if [ "$found" = "1" ]; then
        # /proc/net/tcp 无法直接拿 PID（需要 netlink），置空
        return 1
    fi
    return 0
}

# 检测占用方是否是 snell-server 自身（升级 / 重启残留场景）
is_snell_self() {
    local pid="$1"
    [ -z "$pid" ] && return 1
    [ -r "/proc/$pid/comm" ] || return 1
    local comm
    comm=$(cat "/proc/$pid/comm" 2>/dev/null)
    [ "$comm" = "snell-server" ]
}

# ============================================================
# 3. 交互式选择版本
# ============================================================
choose_version() {
    if [ -n "${SNELL_VERSION:-}" ]; then
        CHOSEN_VERSION="$SNELL_VERSION"
        CHOSEN_MAJOR="v${CHOSEN_VERSION%%.*}"
        log_info "环境变量 SNELL_VERSION=${CHOSEN_VERSION}，跳过交互"
        return 0
    fi

    if ! is_interactive; then
        CHOSEN_MAJOR="$DEFAULT_MAJOR"
        CHOSEN_VERSION="$(lookup_latest "$DEFAULT_MAJOR")"
        log_info "非交互模式，使用默认 ${CHOSEN_MAJOR} / ${CHOSEN_VERSION}"
        return 0
    fi

    log_info "请选择要安装的 Snell 版本"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────┐"
    echo "  │  [1] v1.x.x    (legacy, GitHub releases)            │"
    echo "  │  [2] v2.x.x    (legacy)                            │"
    echo "  │  [3] v3.x.x    (legacy)                            │"
    echo "  │  [4] v4.x.x    (稳定旧版)                            │"
    echo "  │  [5] v5.x.x    (稳定旧版 + QUIC Proxy)              │"
    echo "  │  [6] v6.x.x    ★ 默认 (最新 / RC)                  │"
    echo "  │  [7] 自动选最新                                     │"
    echo "  │  [8] 自定义完整版本号                                │"
    echo "  └─────────────────────────────────────────────────────┘"
    echo ""
    log_prompt "请输入选项 [1-8, 直接回车 = 默认 6]: "
    read -r choice

    case "${choice:-6}" in
        1) CHOSEN_MAJOR="v1"; CHOSEN_VERSION="$(lookup_latest v1)" ;;
        2) CHOSEN_MAJOR="v2"; CHOSEN_VERSION="$(lookup_latest v2)" ;;
        3) CHOSEN_MAJOR="v3"; CHOSEN_VERSION="$(lookup_latest v3)" ;;
        4) CHOSEN_MAJOR="v4"; CHOSEN_VERSION="$(lookup_latest v4)" ;;
        5) CHOSEN_MAJOR="v5"; CHOSEN_VERSION="$(lookup_latest v5)" ;;
        6|7)
            CHOSEN_MAJOR="v6"
            CHOSEN_VERSION="$(lookup_latest v6)"
            log_info "已选择最新: v${CHOSEN_VERSION}"
            ;;
        8)
            log_prompt "请输入完整版本号 (如 6.0.0rc2): "
            read -r custom_ver
            if [ -z "$custom_ver" ]; then
                log_err "版本号不能为空"
                exit 1
            fi
            CHOSEN_VERSION="$custom_ver"
            CHOSEN_MAJOR="v${CHOSEN_VERSION%%.*}"
            ;;
        *)
            log_err "无效选项: $choice"
            exit 1
            ;;
    esac

    CHOSEN_SOURCE="${CHOSEN_SOURCE:-$(lookup_source "$CHOSEN_MAJOR")}"
    log_info "已选择: ${CHOSEN_MAJOR} / ${CHOSEN_VERSION}  (来源: ${CHOSEN_SOURCE})"
}

# ============================================================
# 4. 交互式选择配置
# ============================================================
choose_config() {
    log_info "请配置 Snell 服务参数（直接回车使用默认值）"
    echo ""

    if ! is_interactive; then
        CHOSEN_PORT="${SNELL_PORT:-$DEFAULT_PORT}"
        CHOSEN_LISTEN="${SNELL_LISTEN:-$DEFAULT_LISTEN}"
        CHOSEN_IPV6="${SNELL_IPV6:-$DEFAULT_IPV6}"
        CHOSEN_OBFS="${SNELL_OBFS:-$DEFAULT_OBFS}"
        log_info "非交互模式，使用全部默认值"

        # 非交互模式也做占用检测，被占用直接报错退出
        if ! check_port_in_use "$CHOSEN_PORT"; then
            if [ -n "${PORT_PID:-}" ] && is_snell_self "$PORT_PID"; then
                log_info "端口 $CHOSEN_PORT 已被 snell-server 自身占用（升级场景），忽略"
            else
                log_err "端口 $CHOSEN_PORT 已被占用（PID=${PORT_PID:-未知}）"
                log_err "非交互模式无法选其他端口，请通过 SNELL_PORT=<空闲端口> 重试"
                exit 1
            fi
        fi
        return 0
    fi

    # ----- 端口（含循环 + 冲突处理）-----
    while :; do
        log_prompt "监听端口 [默认 ${DEFAULT_PORT}]: "
        read -r port_input
        CHOSEN_PORT="${port_input:-$DEFAULT_PORT}"

        # 数字合法性
        case "$CHOSEN_PORT" in
            ''|*[!0-9]*)
                log_err "端口必须为数字: $CHOSEN_PORT"
                continue
                ;;
        esac
        if [ "$CHOSEN_PORT" -lt 1 ] || [ "$CHOSEN_PORT" -gt 65535 ]; then
            log_err "端口范围应为 1-65535: $CHOSEN_PORT"
            continue
        fi

        # 占用检测
        if check_port_in_use "$CHOSEN_PORT"; then
            break  # 端口空闲，OK
        fi

        # 端口被占用
        log_warn "端口 $CHOSEN_PORT 已被占用"
        if [ -n "${PORT_PID:-}" ]; then
            log_info "  占用方: PID=${PORT_PID}"
            if is_snell_self "$PORT_PID"; then
                log_info "  → snell-server 自身进程（升级 / 重启场景），忽略冲突"
                PORT_PID=""
                break
            fi
        else
            log_info "  （无法识别占用方 PID，可能缺少 ss/netstat 且 /proc/net 信息不足）"
        fi

        echo ""
        echo "  [1] 换一个端口"
        echo "  [2] 继续（snell 启动时将无法 bind 该端口）"
        echo "  [3] 退出安装"
        echo ""
        log_prompt "选择 [1/2/3, 默认 1]: "
        read -r conflict_choice
        case "${conflict_choice:-1}" in
            2) break ;;        # 用户坚持，继续
            3) exit 1 ;;        # 退出
            *) continue ;;      # 1 或默认 → 回到顶部重新询问
        esac
    done

    # 监听地址
    log_prompt "监听地址 [默认 ${DEFAULT_LISTEN}]: "
    read -r listen_input
    CHOSEN_LISTEN="${listen_input:-$DEFAULT_LISTEN}"

    # IPv6
    log_prompt "启用 IPv6? (true/false) [默认 ${DEFAULT_IPV6}]: "
    read -r ipv6_input
    case "${ipv6_input:-$DEFAULT_IPV6}" in
        true|false) CHOSEN_IPV6="${ipv6_input:-$DEFAULT_IPV6}" ;;
        *) log_err "IPv6 只能填 true 或 false: ${ipv6_input}"; exit 1 ;;
    esac

    # obfs（仅 v5+ 支持）
    case "$CHOSEN_MAJOR" in
        v5|v6|v7|v8)
            log_prompt "混淆模式 (off/tls/http) [默认 ${DEFAULT_OBFS}]: "
            read -r obfs_input
            case "${obfs_input:-$DEFAULT_OBFS}" in
                off|tls|http) CHOSEN_OBFS="${obfs_input:-$DEFAULT_OBFS}" ;;
                *) log_err "obfs 只能填 off / tls / http: ${obfs_input}"; exit 1 ;;
            esac
            ;;
        *)
            CHOSEN_OBFS=""
            log_info "${CHOSEN_MAJOR} 不支持 obfs 参数，跳过"
            ;;
    esac
}

# ============================================================
# 5. 下载并安装 Snell 二进制
# ============================================================
install_snell() {
    version="$CHOSEN_VERSION"
    arch="$SNELL_ARCH"
    version_dir="${SNELL_VERSIONS_DIR}/v${version}"
    zip_file="/tmp/snell-server-v${version}-linux-${arch}.zip"

    case "${CHOSEN_SOURCE}" in
        github)
            download_url="${SNELL_GITHUB_HOST}/v${version}/snell-server-v${version}-linux-${arch}.zip"
            ;;
        *)
            download_url="${SNELL_DOWNLOAD_HOST}/snell-server-v${version}-linux-${arch}.zip"
            ;;
    esac

    log_info "准备安装 Snell v${version} (${arch})"
    log_info "下载地址: ${download_url}"

    mkdir -p "${SNELL_VERSIONS_DIR}" "${version_dir}"

    if ! curl -fSL --retry 3 -o "${zip_file}" "${download_url}"; then
        log_err "下载失败: ${download_url}"
        log_err "请检查网络或确认版本号 ${version} 是否存在"
        exit 1
    fi

    log_info "解压到 ${version_dir}"
    unzip -oq "${zip_file}" -d "${version_dir}"
    chmod +x "${version_dir}/snell-server"
    rm -f "${zip_file}"

    # ★ current 符号链接自动指向最新安装版本
    log_info "更新 current 链接 -> ${version_dir}"
    ln -sfn "${version_dir}" "${SNELL_CURRENT_LINK}"
    ln -sfn "${SNELL_CURRENT_LINK}/snell-server" "${SNELL_BIN_LINK}"

    if [ ! -x "${SNELL_BIN_LINK}" ]; then
        log_err "可执行文件不可用: ${SNELL_BIN_LINK}"
        exit 1
    fi

    log_ok "Snell v${version} 安装完成"

    # 列出所有已安装版本
    if [ -d "${SNELL_VERSIONS_DIR}" ]; then
        log_info "已安装的所有版本:"
        current_target=$(readlink "${SNELL_CURRENT_LINK}" 2>/dev/null || echo "")
        for v in $(ls -1 "${SNELL_VERSIONS_DIR}" 2>/dev/null | sort); do
            marker=""
            if [ "${SNELL_VERSIONS_DIR}/$v" = "${current_target}" ]; then
                marker=" <-- current"
            fi
            printf "    %s%s\n" "$v" "$marker"
        done
    fi
}

# ============================================================
# 6. 生成 / 更新配置文件
# ============================================================
setup_config() {
    log_info "准备配置文件..."
    mkdir -p "${SNELL_CONF_DIR}"

    use_wizard=1
    if [ -f "${SNELL_CONF_FILE}" ]; then
        log_warn "配置文件已存在: ${SNELL_CONF_FILE}"
        if is_interactive; then
            log_prompt "是否重新生成? [y/N，回车保留现有]: "
            read -r regen
            case "$regen" in
                y|Y|yes|YES) use_wizard=1 ;;
                *)            use_wizard=0 ;;
            esac
        else
            log_info "非交互模式，保留现有配置"
            use_wizard=0
        fi
    fi

    if [ "$use_wizard" = "1" ]; then
        log_info "使用 snell-server --wizard 生成 PSK..."
        cd "${SNELL_CURRENT_LINK}"
        ./snell-server --wizard -c "${SNELL_CONF_FILE}"
        cd - >/dev/null
        log_ok "配置已生成"
    fi

    update_config

    log_info "当前配置:"
    echo "----------------------------------------"
    cat "${SNELL_CONF_FILE}"
    echo "----------------------------------------"
}

update_config() {
    listen_line="${CHOSEN_LISTEN}:${CHOSEN_PORT}"

    # v5+ 新格式: listen = ip:port
    if grep -q "^listen" "${SNELL_CONF_FILE}" 2>/dev/null; then
        sed -i "s|^listen = .*|listen = ${listen_line}|" "${SNELL_CONF_FILE}"
    fi

    # v1-v4 老格式: interface + port 分离
    if grep -q "^interface" "${SNELL_CONF_FILE}" 2>/dev/null; then
        sed -i "s|^interface = .*|interface = ${CHOSEN_LISTEN}|" "${SNELL_CONF_FILE}"
        sed -i "s|^port = .*|port = ${CHOSEN_PORT}|" "${SNELL_CONF_FILE}"
    fi

    # ipv6
    if grep -q "^ipv6" "${SNELL_CONF_FILE}" 2>/dev/null; then
        sed -i "s|^ipv6 = .*|ipv6 = ${CHOSEN_IPV6}|" "${SNELL_CONF_FILE}"
    else
        printf "ipv6 = %s\n" "${CHOSEN_IPV6}" >> "${SNELL_CONF_FILE}"
    fi

    # obfs（v5+）
    if [ -n "${CHOSEN_OBFS}" ]; then
        if grep -q "^obfs" "${SNELL_CONF_FILE}" 2>/dev/null; then
            sed -i "s|^obfs = .*|obfs = ${CHOSEN_OBFS}|" "${SNELL_CONF_FILE}"
        else
            printf "obfs = %s\n" "${CHOSEN_OBFS}" >> "${SNELL_CONF_FILE}"
        fi
    fi
}

# ============================================================
# 7. 服务管理（systemd / OpenRC / runit 抽象）
# ============================================================
service_unit_path() {
    case "$INIT_SYSTEM" in
        systemd) echo "/etc/systemd/system/snell-server.service" ;;
        openrc)  echo "/etc/init.d/snell-server" ;;
        runit)   echo "/etc/sv/snell-server/run" ;;
        *)       echo "" ;;
    esac
}

create_service_unit() {
    local target
    target=$(service_unit_path)
    if [ -z "$target" ]; then
        log_warn "未知 init 系统，跳过服务创建"
        return 1
    fi

    log_info "创建服务 ($INIT_SYSTEM): $target"

    case "$INIT_SYSTEM" in
        systemd)
            mkdir -p "$(dirname "$target")"
            cat > "$target" << 'EOF'
[Unit]
Description=Snell proxy server (Surge)
Documentation=https://kb.nssurge.com/surge-knowledge-base/zh/release-notes/snell
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
# 通过 current 符号链接调用最新版本（升级时无需修改 unit 文件）
ExecStart=/usr/local/snell/current/snell-server -c /etc/snell/snell-server.conf
Restart=on-failure
RestartSec=3
LimitNOFILE=65536

# 安全选项
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            ;;

        openrc)
            mkdir -p "$(dirname "$target")"
            cat > "$target" << 'EOF'
#!/sbin/openrc-run
name="snell-server"
description="Snell proxy server (Surge)"

# 通过 current 符号链接调用最新版本
command="/usr/local/snell/current/snell-server"
command_args="-c /etc/snell/snell-server.conf"
command_background="yes"
pidfile="/run/${name}.pid"

output_log="/var/log/${name}.log"
error_log="/var/log/${name}.err"

depend() {
    need net
    after firewall
}

reload() {
    ebegin "Reloading ${name}"
    start-stop-daemon --signal HUP --pidfile "${pidfile}"
    eend $?
}
EOF
            chmod +x "$target"
            ;;

        runit)
            mkdir -p "$(dirname "$target")"
            cat > "$target" << 'EOF'
#!/bin/sh
exec 2>&1
exec /usr/local/snell/current/snell-server -c /etc/snell/snell-server.conf
EOF
            chmod +x "$target"

            # log/run（如果 svlogd 可用）
            if command -v svlogd >/dev/null 2>&1; then
                mkdir -p /etc/sv/snell-server/log
                cat > /etc/sv/snell-server/log/run << 'EOF'
#!/bin/sh
exec svlogd -tt /var/log/snell-server
EOF
                chmod +x /etc/sv/snell-server/log/run
                mkdir -p /var/log/snell-server
            fi
            ;;
    esac

    log_ok "服务文件已创建"
}

enable_service() {
    case "$INIT_SYSTEM" in
        systemd)
            systemctl enable snell-server
            ;;
        openrc)
            rc-update add snell-server default
            ;;
        runit)
            mkdir -p /var/service
            ln -sf /etc/sv/snell-server /var/service/snell-server
            ;;
        *)
            log_warn "未知 init，跳过启用开机自启"
            return 1
            ;;
    esac
    log_ok "已启用开机自启"
}

service_is_active() {
    case "$INIT_SYSTEM" in
        systemd) systemctl is-active --quiet snell-server ;;
        openrc)  rc-service snell-server status >/dev/null 2>&1 ;;
        runit)   sv status snell-server 2>/dev/null | grep -q "^run:" ;;
        *)       return 1 ;;
    esac
}

service_action() {
    local action="$1"
    case "$INIT_SYSTEM" in
        systemd)
            systemctl "$action" snell-server
            ;;
        openrc)
            rc-service snell-server "$action"
            ;;
        runit)
            sv "$action" snell-server
            ;;
        *)
            log_warn "未知 init，跳过 $action"
            return 1
            ;;
    esac
}

service_status_text() {
    case "$INIT_SYSTEM" in
        systemd)
            systemctl status snell-server --no-pager -l 2>&1 || true
            ;;
        openrc)
            rc-service snell-server status 2>&1 || true
            ;;
        runit)
            sv status snell-server 2>&1 || true
            ;;
    esac
}

setup_service() {
    if [ "$INIT_SYSTEM" = "unknown" ]; then
        log_warn "未识别 init 系统，仅安装二进制，请手动配置服务"
        return 0
    fi
    create_service_unit
    enable_service

    # 启动或重启
    if service_is_active; then
        log_info "服务已在运行，重启以加载新版本..."
        service_action restart
    else
        log_info "启动服务..."
        service_action start
    fi

    log_ok "服务已配置"
}

# ============================================================
# 8. 总结
# ============================================================
show_summary() {
    echo ""
    echo "============================================"
    log_ok "Snell ${CHOSEN_MAJOR} / v${CHOSEN_VERSION} 安装完成！"
    echo "============================================"
    echo ""
    echo "  系统:       $OS_NAME"
    echo "  家族:       $OS_FAMILY"
    echo "  架构:       $SNELL_ARCH"
    echo "  Init:       $INIT_SYSTEM"
    echo "  版本:       ${CHOSEN_MAJOR} / v${CHOSEN_VERSION}"
    echo "  监听:       ${CHOSEN_LISTEN}:${CHOSEN_PORT}"
    echo "  IPv6:       ${CHOSEN_IPV6}"
    if [ -n "${CHOSEN_OBFS}" ]; then
        echo "  obfs:       ${CHOSEN_OBFS}"
    fi
    echo ""
    echo "  二进制:     ${SNELL_BIN_LINK}"
    echo "  当前版本:   ${SNELL_CURRENT_LINK} -> $(readlink ${SNELL_CURRENT_LINK})"
    echo "  历史版本:   ${SNELL_VERSIONS_DIR}/"
    echo "  配置文件:   ${SNELL_CONF_FILE}"
    echo ""
    echo "  常用命令:"
    case "$INIT_SYSTEM" in
        systemd)
            echo "    systemctl status snell-server      # 状态"
            echo "    systemctl restart snell-server     # 重启"
            echo "    systemctl stop snell-server        # 停止"
            echo "    journalctl -u snell-server -f      # 日志"
            ;;
        openrc)
            echo "    rc-service snell-server status     # 状态"
            echo "    rc-service snell-server restart    # 重启"
            echo "    rc-service snell-server stop       # 停止"
            echo "    cat /var/log/messages | grep snell # 日志"
            ;;
        runit)
            echo "    sv status snell-server             # 状态"
            echo "    sv restart snell-server            # 重启"
            echo "    sv stop snell-server               # 停止"
            echo "    tail -f /var/log/snell-server/current # 日志"
            ;;
    esac
    echo ""
    echo "  切换版本:"
    echo "    ./install.sh                                  # 重新选择"
    echo "    SNELL_VERSION=5.0.1 ./install.sh              # 直接指定"
    echo "    NONINTERACTIVE=1 SNELL_PORT=8388 ./install.sh # 全自动"
    echo ""
}

# ============================================================
# 主流程
# ============================================================
main() {
    check_root
    detect_os
    detect_arch
    detect_init
    install_deps
    choose_version
    choose_config
    install_snell
    setup_config
    setup_service

    echo ""
    log_info "服务状态:"
    service_status_text

    show_summary
}

main "$@"