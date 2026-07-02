# adeb —— 进阶 / 开发者指南

adeb 的详细参考。快速上手见 [README.zh-CN.md](../README.zh-CN.md)。
English: [ADVANCED.md](ADVANCED.md)。

- [相较原仓库的改动](#相较原仓库的改动)
- [后端（chroot 与 proot）](#后端chroot-与-proot)
- [内核追踪要求](#内核追踪要求)
- [本地构建](#本地构建)
- [`prepare` 选项参考](#prepare-选项参考)
- [其它架构](#其它架构)
- [用 ssh 代替 adb](#用-ssh-代替-adb)
- [CI/CD 流水线](#cicd-流水线)
- [故障排查](#故障排查)

## 相较原仓库的改动

本仓库是 [joelagnel/adeb](https://github.com/joelagnel/adeb)（已 archive）的活跃维护分支：

- **Debian bookworm (12)** 取代已 EOL 的 buster；用 `debootstrap` +
  `qemu-user-static` 取代已移除的 `qemu-debootstrap`。
- **全面 Python 3**：包列表与 perf/BCC 辅助脚本。
- **不锁定 LLVM/Clang**（原来硬编码 LLVM 7）；BCC 链接共享库 `libLLVM`
  （`ENABLE_LLVM_SHARED`）并拉取其 git 子模块。
- **现代 Android 真机修复**：恢复 `adb push` 丢失的可执行位；从
  `/sys/kernel/tracing` 挂载 tracefs（内核 6.x）；避免卸载传播卸掉设备真实的
  tracefs/bpffs；`_apt` 的 AID_INET 组修复改为不依赖 Debian 版本。
- **非 root 的 proot 后端**（见下），让未 root 的设备也能用 Debian 用户态。
- **新增选项** `--distro`、`--mirror`、`--no-device`、`--proot`/`--proot-bin`；
  多架构预构建镜像；`release-artifacts.sh`；CI（lint/smoke/release）；清理 AOSP 残留。
- **真机端到端验证**（aarch64，内核 6.12 / Android 16）：chroot 启动、`apt` 可用、
  原生 `gcc`/`python3` 可编译、`bpftrace` 经 BTF 对活内核挂 eBPF；非 root 下 proot
  后端跑通 Debian 用户态且 `apt` 可用。

## 后端（chroot 与 proot）

adeb 有两种进入 Debian 环境的方式。

|                          | chroot（默认）          | proot（`--proot`）              |
| ------------------------ | ----------------------- | ------------------------------- |
| 需要 root                | 是（`adb root`/`su`）   | **否**                          |
| 机制                     | 真 `chroot` + 绑定挂载  | `ptrace(2)` 路径/uid 模拟       |
| 速度                     | 原生                    | 较慢（每个 syscall 都被跟踪）   |
| 内核追踪（eBPF/BCC/perf）| ✅ 完整                 | ❌ 仅用户态                     |
| 设备上目录               | `/data/androdeb`        | `/data/local/tmp/adeb`          |

**自动选择**：`shell`/`prepare` 不带 `--proot` 时，adeb 先执行 `adb root`，成功则用
chroot，失败则**自动回退到 proot**。带 `--proot` 可强制 proot。（userdebug 设备
`adb root` 会成功，所以在这类设备上要显式 `--proot` 才走 proot。）

**各自独立安装**：两个后端在不同目录、**不共享**——`/data/androdeb` 下的 chroot
rootfs 属 root、非特权进程读不了，proot 无法复用它。想用哪个后端就各 `adeb prepare`
一次。两个位置都在持久化的 `/data`（f2fs）分区上，所以装好的环境**重启不丢**（只是
开机后需解锁一次手机以挂载 FBE 加密存储）。注意：`/data/local/tmp` 虽名为 "tmp"，
实为持久目录。

### proot 后端细节

[proot](https://proot-me.github.io/) 用 `ptrace` 拦截系统调用、改写路径让 rootfs
呈现为 `/`，并用 `-0` 谎报 uid 0 让 `apt`/`dpkg` 满意——全程无需 root。局限：没有
内核追踪（`bpf()`/`perf_event_open()` 仍以真实非特权 uid 打到内核而被拒），且 ptrace
有开销、更慢。

用法：
```bash
# proot 需要目标架构的静态 proot 二进制（--proot-bin）：
adeb prepare --proot --build --proot-bin /path/to/proot-aarch64
adeb shell
```
proot 二进制可来自 Termux（`pkg install proot`）、本项目 release 资产
（`proot-arm64` / `proot-amd64`，CI 从源码编译），或自行编译。rootfs 以非 root 身份
安装到 `/data/local/tmp/adeb`，并**在 proot 内**解包，以模拟设备节点（`mknod`）、
属主（`chown`）和硬链接（非 root 的 `tar` 无法创建它们）。

**proot 下的 apt 取舍**：`apt` 下载时会掉权限到 sandbox 用户，并用 `apt-key`/`gpgv`
校验归档签名；在 proot 下掉权限得到空用户名，所有密钥环被忽略，校验无法工作。因此
adeb 在解包时对 proot rootfs 做三处调整：把 `_apt` 的 gid 恢复为 `nogroup`
（buildstrap 为 chroot 后端把它设成 Android `AID_INET` 组 3003，proot 下无效）、设
`APT::Sandbox::User "root"`、把源标记为 `[trusted=yes]`。效果：`apt` 可用，代价是
**仅 proot 环境**放弃归档签名校验——chroot 后端仍保留完整校验。

## 内核追踪要求

adeb 会把内核 tracefs 绑定挂载进（chroot）环境，无论内核暴露在哪——现代内核用
`/sys/kernel/tracing`，旧内核嵌在 `/sys/kernel/debug/tracing`。能跑什么取决于内核：

- **CO-RE 工具**（bpftrace、基于 libbpf 的工具）只要内核带 BTF
  （存在 `/sys/kernel/btf/vmlinux`）即可——多数较新 Android GKI 内核满足。
- **经典 BCC python 工具**运行时编译，需要内核头文件。若设备内核未提供
  （`CONFIG_IKHEADERS` / `/sys/kernel/kheaders.tar.xz`）会报 “Unable to find kernel
  headers”；此时优先用 bpftrace / CO-RE 工具。

追踪仅在 **chroot** 后端可用（需要真实权限）。

## 本地构建

仅在你选择本地构建镜像（而非下载）时需要。主机：较新的 Ubuntu/Debian 或 Arch，约
4 GB 内存与空闲空间，装 `debootstrap` + `qemu-user-static`。已不需要旧的
`qemu-debootstrap`：只要装了 `qemu-user-static` 及其 binfmt handler，现代
`debootstrap` 就能引导外架构。

- Debian/Ubuntu：`sudo apt-get install qemu-user-static binfmt-support debootstrap`
- Arch：`sudo pacman -S debootstrap qemu-user-static qemu-user-static-binfmt`

构建**本机同架构**完全不需要 qemu（CI 就是这么做的：amd64 在 x86 runner、arm64 在
arm64 runner）。

## `prepare` 选项参考

| 选项                  | 含义 |
| --------------------- | ---- |
| （无）                | 下载并安装预构建基础镜像 |
| `--full`              | 下载/构建完整镜像（编译器、编辑器、追踪器、BCC） |
| `--build`             | 本地构建 rootfs（联网下包）而非下载预构建镜像 |
| `--bcc`              | 包含从源码构建的 BCC；`--full` 已隐含 |
| `--buildtar <dir>`    | 准备后额外产出 `<dir>/androdeb-fs[-minimal][-<arch>].tgz.zip` |
| `--no-device`         | 配合 `--build --buildtar`：仅在主机打包、不碰设备（CI 用） |
| `--build-image <img>` | 构建独立 raw EXT4 镜像（供 Qemu `-hda`）；无需设备 |
| `--archive <tar>`     | 安装此前构建好的 rootfs 压缩包 |
| `--arch <arch>`       | 目标架构（默认 `arm64`，如 `amd64`） |
| `--distro <name>`     | Debian 套件（默认 `bookworm`）；亦可用 `DISTRO` 环境变量 |
| `--mirror <url>`      | Debian 镜像（默认 `deb.debian.org`）；亦可用 `DEBIAN_MIRROR` |
| `--proot`             | 使用非 root 的 proot 后端 |
| `--proot-bin <path>`  | 目标架构的静态 proot 二进制（隐含 `--proot`） |
| `--tempdir <dir>`     | 构建工作目录 |
| `-s` / `--device`     | 多设备时指定 adb 序列号 |

示例：
```bash
adeb prepare --build                    # 本地基础构建，chroot
adeb prepare --full --build             # 本地完整构建（含 BCC）
adeb prepare --full --buildtar /out     # 构建并另存可复用压缩包
adeb prepare --archive /out/androdeb-fs.tgz
adeb prepare --build-image /tmp/adeb.img
```

## 其它架构

默认假设 ARM64。其它架构用 `--arch`：
```bash
adeb prepare --arch amd64          # 下载预构建 amd64 镜像
adeb prepare --full --arch amd64   # 预构建 amd64 完整镜像
adeb prepare --build --arch amd64  # 或本地构建
```
CI 每次发版发布 **arm64** 与 **amd64** 镜像（基础 + 完整）。其它架构请带 `--build`。

## 用 ssh 代替 adb

```bash
adeb --ssh <user@host> --sshpass <pass> <cmd>
```
用密钥认证时省略 `--sshpass`。目标须已 root 且有 ≥ 2 GB 空闲。首次先在 adeb 之外 ssh
一次以加入 `known_hosts`。

## CI/CD 流水线

`.github/workflows/` 下：

- **lint** —— 对所有 bash/sh 脚本跑 `shellcheck`（error 级）。
- **smoke** —— 在 amd64（`ubuntu-latest`）与 arm64（`ubuntu-24.04-arm`）上原生构建
  基础 rootfs 并 chroot 进去验证是正确架构的 bookworm。
- **release** —— 打 `v*` tag（或手动 dispatch）时：在各自原生 runner 上构建 arm64/
  amd64 的基础 + 完整镜像，从源码（musl/Alpine）编译各架构静态 `proot`，并用 `gh`
  全部发布到该 tag 的 GitHub Release。
- **proot** —— 独立的“从源码编译静态 proot”（arm64 + amd64），作为 artifact 上传。

**触发规则**：`lint`/`smoke` 在 PR 与分支/master push 时运行，但跳过纯 `**.md` 改动
和 tag push；`release` 仅在 `v*` tag 上运行。即：纯文档改动 → 什么都不跑；PR →
lint+smoke；push 到 master → lint+smoke；打 tag → release。

维护者也可用 `./release-artifacts.sh` 从连接的设备构建并发布镜像（需 `adb root` 设备
和已登录的 `gh`）。

## 故障排查

**prepare 后 `apt-get install g++` 失败**：先 `adeb shell apt-get update`。

**debootstrap 太慢**：用 `--mirror`（或 `DEBIAN_MIRROR`）指定本地镜像，如国内：
```bash
adeb prepare --build --mirror https://mirror.tuna.tsinghua.edu.cn/debian
```

**`adeb shell '<含 $() 或引号的复杂命令>'` 丢参数**：adeb 会把命令穿过多层引号转义，
复杂一行命令可能被弄乱（两个后端都如此）。把命令写进脚本再跑，或用交互式
`adeb shell`。

**proot 下 `apt` 出现 GPG / “未签名” 警告**：符合预期——proot 下有意放宽签名校验
（见[后端 → apt 取舍](#后端chroot-与-proot)），安装仍可正常进行。
