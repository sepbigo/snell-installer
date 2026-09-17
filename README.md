# Snell v1~v6 Multi-Distro Installer

Snell v1 ~ v6 一键安装脚本，**自动适配主流 Linux 发行版**（systemd / OpenRC / runit 全 init 支持）。

> 原理：Snell 官方二进制是 glibc 动态链接，Alpine 是 musl libc。  
> 通过 `gcompat` 兼容层即可在 Alpine 上运行；其他 glibc 系统直接跑。

---

## ✨ 特性

- 🆕 **多发行版自适应**：自动识别系统并选择正确的包管理器
- 🆕 **多 Init 自适应**：systemd / OpenRC / runit 自动生成对应服务文件
- 🆕 **Alpine 兼容层**：musl 系统自动安装 `gcompat` + `openrc`
- 🆕 **端口占用检测**：自动识别已占用端口（ss → netstat → /proc/net/tcp 三级 fallback），升级场景自动识别 snell-server 自身
- 🆕 **交互式版本菜单**：v1 ~ v6 + 自动最新 + 自定义版本号
- 🆕 **交互式配置**：端口 / 监听 / IPv6 / obfs 一一询问，回车走默认
- ✅ **版本目录隔离** + `current` 符号链接自动指向最新版本
- ✅ 重复运行 = 升级 / 切换版本，配置可保留
- ✅ 支持 `NONINTERACTIVE=1` 全自动安装

---

## 🖥️ 支持的系统矩阵

| 系统家族 | 代表发行版 | 包管理 | Init | 兼容层 |
|---|---|---|---|---|
| **alpine** | Alpine Linux | `apk` | OpenRC | **gcompat** |
| **debian** | Debian / Ubuntu / Raspbian / Kubuntu | `apt` | systemd | — |
| **rhel** | RHEL / CentOS / Rocky / AlmaLinux / Fedora / Amazon Linux / Oracle Linux | `dnf`/`yum` | systemd | — |
| **arch** | Arch / Manjaro / Artix | `pacman` | systemd（Artix 用 OpenRC 自动适配）| — |
| **suse** | openSUSE Leap / Tumbleweed / SLES | `zypper` | systemd | — |
| **void** | Void Linux | `xbps` | runit | — |

**架构**：amd64 (x86_64) / aarch64 (arm64)

---

## 🚀 快速开始

### 交互式安装（推荐）

```sh
wget -O install.sh https://github.com/sepbigo/snell-installer/main/install.sh
chmod +x install.sh
./install.sh
```

运行后会依次提示：

```
[INFO] 系统: Ubuntu 24.04 LTS (ID=ubuntu, FAMILY=debian)
[INFO] 架构: x86_64 → amd64
[INFO] Init: systemd
[INFO] 安装依赖...

[INFO] 请选择要安装的 Snell 版本
  [1] v1.x.x    (legacy, GitHub releases)
  [2] v2.x.x    (legacy)
  [3] v3.x.x    (legacy)
  [4] v4.x.x    (稳定旧版)
  [5] v5.x.x    (稳定旧版 + QUIC Proxy)
  [6] v6.x.x    ★ 默认 (最新 / RC)
  [7] 自动选最新
  [8] 自定义完整版本号
[?] 请输入选项 [1-8, 直接回车 = 默认 6]:

[?] 监听端口 [默认 6160]:                ← 端口被占用时自动弹出冲突菜单
[?] 监听地址 [默认 0.0.0.0]:             ← 回车走默认
[?] 启用 IPv6? (true/false) [默认 true]:  ← 回车走默认
[?] 混淆模式 (off/tls/http) [默认 off]:   ← 仅 v5+询问
```

**所有提示直接回车走默认**，一路回车即可完成标准安装。

### 🛡 端口冲突处理

如果指定端口已被占用，脚本会自动检测（`ss` → `netstat` → `/proc/net/tcp` 三级 fallback）并给出菜单：

```
[WARN] 端口 6160 已被占用
  占用方: PID=12345
[?] 选择 [1/2/3, 默认 1]:
  [1] 换一个端口
  [2] 继续（snell 启动时将无法 bind 该端口）
  [3] 退出安装
```

**智能识别**：如果占用方是 `snell-server` 自身（升级 / 重启残留场景），脚本会自动跳过冲突提示。

### 指定版本安装

```sh
SNELL_VERSION=5.0.1 ./install.sh          # 装 v5.0.1
SNELL_VERSION=4.1.1 ./install.sh          # 装 v4.1.1
SNELL_VERSION=6.0.0rc2 ./install.sh       # 装 v6 RC2
```

### 完全静默安装（适合 CI/CD）

```sh
NONINTERACTIVE=1 \
  SNELL_VERSION=6.0.0rc2 \
  SNELL_PORT=8388 \
  ./install.sh
```

### 跳过依赖安装（用户自己管理）

```sh
SKIP_DEPS_INSTALL=1 NONINTERACTIVE=1 ./install.sh
```

---

## 🔧 环境变量速查

| 变量 | 说明 | 默认 |
|---|---|---|
| `SNELL_VERSION` | 指定具体版本号（跳过版本菜单） | 走交互或 v6 最新 |
| `SNELL_PORT` | 监听端口 | 6160 |
| `SNELL_LISTEN` | 监听地址 | 0.0.0.0 |
| `SNELL_IPV6` | IPv6 开关 | true |
| `SNELL_OBFS` | 混淆模式 (off/tls/http) | off |
| `NONINTERACTIVE` | 1 = 全自动，不提示 | 0 |
| `SKIP_DEPS_INSTALL` | 1 = 跳过依赖安装 | 0 |

---

## 📋 已知最新版本（脚本内置映射表）

| 大版本 | 最新版本 | 下载源 |
|---|---|---|
| v1 | 1.1.1 | GitHub releases |
| v2 | 2.0.1 | dl.nssurge.com |
| v3 | 3.0.1 | dl.nssurge.com |
| v4 | 4.1.1 | dl.nssurge.com |
| v5 | 5.0.1 | dl.nssurge.com |
| v6 | 6.0.0rc2 | dl.nssurge.com |

> Surge 官方发布新版本时，可编辑脚本顶部 `KNOWN_LATEST` 表更新。

---

## 📂 版本目录结构

```
/usr/local/snell/
├── versions/
│   ├── v5.0.1/snell-server
│   ├── v6.0.0rc/snell-server
│   └── v6.0.0rc2/snell-server      ← 再次运行 install.sh 装入
└── current -> versions/v6.0.0rc2/  ← 脚本每次都更新这个链接
        ↓
/usr/local/bin/snell-server -> /usr/local/snell/current/snell-server
        ↓
/etc/systemd/system/snell-server.service   (systemd)
/etc/init.d/snell-server                  (OpenRC)
/etc/sv/snell-server/run                  (runit)
```

**关键点**：三种 init 的服务文件 `ExecStart/command` 都固定指向 `/usr/local/snell/current/snell-server`，  
升级只需重跑 `install.sh`，`current` 自动指向新版本，重启服务即生效。

---

## 🛠 常用命令

脚本会自动选择适配当前系统的命令：

```sh
# systemd (Debian/Ubuntu/RHEL/Arch/openSUSE 等)
systemctl status snell-server
systemctl restart snell-server
systemctl stop snell-server
journalctl -u snell-server -f

# OpenRC (Alpine / Gentoo / Artix)
rc-service snell-server status
rc-service snell-server restart
rc-service snell-server stop
cat /var/log/messages | grep snell

# runit (Void)
sv status snell-server
sv restart snell-server
sv stop snell-server
tail -f /var/log/snell-server/current
```

---

## 📥 升级 / 降级 / 切换版本

```sh
# 升级到指定版本
SNELL_VERSION=6.0.0rc2 ./install.sh

# 切回旧版本（手动）
ln -sfn /usr/local/snell/versions/v6.0.0rc /usr/local/snell/current
systemctl restart snell-server    # 或对应 init 的重启命令

# 清理旧版本
rm -rf /usr/local/snell/versions/v6.0.0rc
```

---

## 🗑 卸载

```sh
chmod +x uninstall.sh
./uninstall.sh
```

脚本会自动检测 init 系统执行对应清理，并询问是否删除：
- 配置目录 `/etc/snell`
- 脚本安装的依赖（`gcompat` / `openrc` / `curl` / `wget` / `unzip`）

---

## 🧩 工作原理

1. **OS 识别**：读 `/etc/os-release` → 归类到 6 个家族之一
2. **Init 检测**：`/run/systemd/system` 存在 → systemd；`/sbin/openrc-run` 存在 → OpenRC；`sv` 存在 → runit
3. **包管理抽象**：`pkg_install`/`pkg_update` 函数按家族分发到 apk/apt/dnf/yum/pacman/zypper/xbps
4. **gcompat 兼容层**（仅 Alpine）：musl 注入 glibc 符号桩，让官方二进制可加载
5. **current 软链接**：把所有"指向最新版本"的逻辑收敛到一个符号链接
6. **配置兼容**：`snell-server --wizard` 生成 PSK，`sed` 同步 `listen`/`interface+port`/`ipv6`/`obfs`

---

## ⚠️ 注意事项

- Surge 官方 release notes: <https://kb.nssurge.com/surge-knowledge-base/zh/release-notes/snell>
- v1 走 GitHub releases (`surge-networks/snell`)，v2+ 走 `dl.nssurge.com` CDN
- `obfs` 参数仅 v5+ 支持
- 配置文件中的 PSK 请妥善保管，**切勿提交到公开仓库**
- Gentoo 不在内置支持列表（用 `emerge` 装 `wget unzip`，然后手动跑脚本其余部分）

---

## 📜 License

MIT
