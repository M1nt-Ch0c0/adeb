# adeb 中文文档

> 📖 **English docs:** [README.md](README.md)
>
> 本仓库是原始项目 [joelagnel/adeb](https://github.com/joelagnel/adeb)（现已 archive）的
> **活跃维护分支**，已针对当前的 Debian 与 Android 版本做了现代化改造。
>
> **相较原仓库的主要改动：**
> - **Debian bookworm (12)** 取代已 EOL 的 buster；用 `debootstrap` + `qemu-user-static`
>   取代已被移除的 `qemu-debootstrap`。
> - **全面 Python 3**：包列表与 perf/BCC 辅助脚本都迁移到 Python 3。
> - **不锁定 LLVM/Clang 版本**（原来硬编码 LLVM 7）；BCC 改为链接共享库
>   `libLLVM`（`ENABLE_LLVM_SHARED`），并拉取其 git 子模块。
> - **现代 Android 真机适配修复**：恢复 `adb push` 丢失的可执行位；从
>   `/sys/kernel/tracing` 挂载 tracefs（内核 6.x）；避免卸载时传播到设备真实的
>   tracefs/bpffs；`_apt` 的 AID_INET 用户组修复改为不依赖 Debian 版本。
> - **新增 `--distro` / `--mirror` 选项**、预构建镜像（让 `adeb prepare` 可直接下载而非
>   本地构建），以及发布脚本 `release-artifacts.sh`；清理了 AOSP 导入残留文件。
> - **真机端到端验证**（aarch64，内核 6.12 / Android 16）：chroot 可启动、`apt` 可联网、
>   原生 `gcc`/`python3` 可编译、`bpftrace` 经 BTF 对活内核挂载 eBPF。
>
> 本分支会**持续维护与更新**，欢迎提 Issue 和 PR。

---

## 简介

**adeb**（又名 **androdeb**）在现有 Android 设备上提供一个强大的 Linux shell 环境，
让你可以运行主流的 Linux 追踪、编译、编辑等开发工具。现代 Linux 上常见的命令，
在 adeb 里基本都能用。

## 使用场景

1. **开箱即用的开发环境**：编辑器、编译器、追踪器、perl/python 等一应俱全，
   适合在设备上做开发。

2. **无需交叉编译**：自带 gcc 和 clang，可以在设备上原生编译目标包，不必做交叉编译。
   还内置 git，并支持用 apt-get 从网络获取缺失的开发包。

3. **运行 BCC 等高门槛工具**：这类工具因缺包、依赖复杂、需要交叉编译，在原生 Android
   环境里很难跑起来。详见 [在 Android 上用 adeb 跑 BCC](BCC.md)。

4. **不再阉割工具**：以往为了规避交叉编译依赖，常把工具编成功能残缺的静态二进制
   （典型如 perf）。借助 adeb，可以在设备上原生构建功能完整的 perf。

## 运行要求

**目标设备（Target）：**
ARM64 的 Android N 及以上、且支持 `adb root` 的设备（通常是 userdebug 配置）。
data 分区至少 2GB 空闲。其它架构见下文「其它架构」。

也可以用 ssh 在非 Android 系统上运行，同样需要 root 且有 2GB 空闲空间。

**关于追踪（eBPF/BCC/bpftrace）支持：**
adeb 会自动把内核的 tracefs 绑定挂载进环境，无论内核把它暴露在哪里
（现代内核用 `/sys/kernel/tracing`，旧内核嵌在 `/sys/kernel/debug/tracing`）。
具体能跑什么取决于内核：
- **CO-RE 类工具**（bpftrace、基于 libbpf 的工具）只要内核带 BTF
  （存在 `/sys/kernel/btf/vmlinux`）即可运行——大多数较新的 Android GKI 内核都满足。
- **经典 BCC 的 Python 工具**在运行时编译程序，因此需要内核头文件。若设备内核未提供
  （`CONFIG_IKHEADERS` / `/sys/kernel/kheaders.tar.xz`），这些工具会报
  “Unable to find kernel headers”；此时请优先使用 bpftrace / CO-RE 工具。

### 无 root 运行（proot 后端）
adeb 有两种进入 Debian 环境的后端：

- **chroot（默认，需 root）**：真正的 `chroot` + 绑定挂载，原生速度、功能完整
  （含内核追踪 eBPF/BCC/perf）。当 `adb root`（或 `su`）可用时使用。
- **proot（无需 root）**：[proot](https://proot-me.github.io/) 用 `ptrace(2)`
  在用户态模拟 `chroot` 和假 root，因此**未 root 的设备也能跑**。你能得到完整的
  Debian 用户态(apt、gcc/clang、python、git、编辑器、跑普通程序），但**没有内核
  追踪**(eBPF/BCC/perf 需要真实内核权限，proot 给不了），且更慢（每个系统调用都过
  ptrace）。

adeb 会自动选择：`adb root` 失败时回退到 proot；用 `--proot` 强制。proot 需要目标
架构的静态 `proot` 二进制,用 `--proot-bin <路径>` 提供（如 Termux 的
`pkg install proot`，或自行静态编译）：
```
adeb prepare --proot --build --proot-bin /path/to/proot-aarch64
adeb shell
```
rootfs 会以非 root 身份安装到 `/data/local/tmp/adeb`，并**在 proot 内**解包以模拟
设备节点与属主。

**主机（Host）：**
一台较新的 Ubuntu/Debian，4GB 内存、4GB 空闲空间。需要 `debootstrap` 和
`qemu-user-static` 包。已不再需要旧的 `qemu-debootstrap` 包装器：只要装了
`qemu-user-static`（及其 binfmt handler），现代 `debootstrap` 就能透明地引导外架构。
- Debian/Ubuntu：`sudo apt-get install qemu-user-static binfmt-support debootstrap`
- Arch Linux：`sudo pacman -S debootstrap qemu-user-static qemu-user-static-binfmt`

其它发行版可能也能用，但未经测试。

## 快速开始

先把本仓库克隆到 adeb 目录并进入：

```bash
cd adeb

# 加个快捷方式：
sudo ln -s $(pwd)/adeb /usr/bin/adeb

# 缓存镜像下载能大幅提速。用 git 克隆时会自动缓存；若你是下载的 zip
# （或想把镜像托管到别处），可以在 bashrc 里设置 ADEB_REPO_URL 环境变量。
export ADEB_REPO_URL="github.com/M1nt-Ch0c0/adeb/"
```

安装到设备（先确保设备已连接）：

```bash
adeb prepare          # 下载并安装基础镜像
adeb prepare --full   # 下载并安装完整镜像（含编译器、编辑器、追踪器等）
```

进入环境：

```bash
adeb shell
```

完成后按 `CTRL + D` 退出。从设备移除：

```bash
adeb remove
```

若连了多台设备，加 `-s <序列号>`（序列号可用 `adb devices` 查看）。

更新本机上的 adeb 克隆：

```bash
adeb git-pull
```

用 ssh 代替 adb 与目标通信：

```bash
adeb --ssh <uri> --sshpass <pass> <cmd>
```

用密钥认证时可省略 `--sshpass`。首次连接目标前，请先在 adeb 之外 ssh 一次以把主机加入
known_hosts。

## 进阶用法

**本地构建并用自定义 rootfs 准备设备**（按需下载包在本地构建，而非从网络拉现成 rootfs）：

```bash
adeb prepare --build
```

**完整构建**（本地构建含全部包，包括 BCC）：

```bash
adeb prepare --full --build
```

**构建含 BCC 的基础镜像**（BCC 从源码构建）：

```bash
adeb prepare --bcc --build
```

**从已准备好的设备中提取 rootfs 打包**：

```bash
adeb prepare --full --buildtar /path/
```

会把 rootfs 提取为 `/path/adeb-fs.tgz`，供以后复用。

**使用本地已有的 rootfs 归档**：

```bash
adeb prepare --archive /path/adeb-fs.tgz
```

**构建独立的 raw EXT4 镜像**（可作为 Qemu 的 `-hda`，此选项无需连接设备）：

```bash
adeb prepare --build-image /path/to/image.img
```

## 其它架构（非 ARM64）

默认假设目标设备是 ARM64。其它架构用 `--arch` 指定，例如 x86_64：

```bash
adeb prepare --arch amd64          # 下载预构建 amd64 镜像
adeb prepare --full --arch amd64   # 下载预构建 amd64 完整镜像
adeb prepare --build --arch amd64  # 或本地构建
```

**arm64 与 amd64** 的预构建镜像（基础版和完整版）由 CI 在每次发版时自动构建并发布
——arm64 在 arm64 runner 上构建、amd64 在 x86 runner 上构建
（见 `.github/workflows/release.yml`）。其它架构请带 `--build` 让 adeb 本地构建。

## 持续集成（CI）

- `lint`：对所有 shell 脚本跑 shellcheck。
- `smoke`：分别在 amd64 与 arm64 上原生构建基础 rootfs 并 chroot 验证可用。
- `release`：打 `v*` tag 时，在各自原生 runner 上构建 arm64/amd64 的基础+完整镜像，
  并发布到该 tag 的 GitHub Release。

## 常见问题

**1. `apt-get install g++` 失败**

先在 `adeb prepare` 之后运行 `adeb shell apt-get update`。

**2. debootstrap 构建 Debian fs 太慢**

用 `--mirror` 选项（或 `DEBIAN_MIRROR` 环境变量）指定本地镜像。例如国内可用清华源：

```bash
adeb prepare --build --mirror https://mirror.tuna.tsinghua.edu.cn/debian
```

替代默认的官方源 http://deb.debian.org/debian 。

## 发布预构建镜像

维护者可用仓库根目录的 `release-artifacts.sh` 构建基础/完整镜像并发布为 GitHub Release
资源，之后 `adeb prepare` / `adeb prepare --full` 即可直接下载而非本地构建。需要连接一台
`adb root` 设备，并已通过 `gh` 登录：

```bash
./release-artifacts.sh
```
