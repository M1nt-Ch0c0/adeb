# adeb 进阶参考

快速上手见 [README.zh-CN.md](../README.zh-CN.md)。English: [ADVANCED.md](ADVANCED.md)。

## 相较原仓库的改动

[joelagnel/adeb](https://github.com/joelagnel/adeb)（已 archive）的 fork：

- Debian bookworm（原 buster）；`debootstrap` + `qemu-user-static`（原已移除的
  `qemu-debootstrap`）。
- Python 3；不锁版本的 LLVM/Clang（原 LLVM 7）；BCC 链接共享库 libLLVM。
- 现代 Android 修复：恢复 `adb push` 丢失的可执行位；tracefs 取 `/sys/kernel/tracing`；
  非递归绑定，避免卸载时连带卸掉设备真实的 tracefs/bpffs；`_apt` 组修复不依赖 Debian 版本。
- 非 root 的 proot 后端。
- 新选项 `--distro`、`--mirror`、`--no-device`、`--proot`/`--proot-bin`；多架构预构建
  镜像；CI（lint/smoke/release）。

## 后端

|                          | chroot         | proot                  |
| ------------------------ | -------------- | ---------------------- |
| root                     | 需要           | 不需要                 |
| 机制                     | chroot + 绑定  | ptrace 模拟            |
| 速度                     | 原生           | 较慢                   |
| 内核追踪（eBPF/BCC/perf）| 支持           | 不支持                 |
| 安装目录                 | /data/androdeb | /data/local/tmp/adeb   |

`shell`/`prepare` 会执行 `adb root`：成功走 chroot，失败走 proot。`--proot` 强制
proot（userdebug 设备 `adb root` 会成功，所以需显式指定）。

> **提示：** `adb root` 只在 userdebug/eng 设备上成功；生产（user）设备会失败，
> adeb 因此退化到 proot，eBPF/BCC/perf 都不可用。如果你愿意给设备 root，用
> [Magisk](https://github.com/topjohnwu/Magisk) 或
> [KernelSU](https://github.com/tiann/KernelSU) root 后，配合 `--ssh` 以 root
> 身份连接（或用 root shell 类 app），就能保住 chroot 后端和内核追踪能力，而不
> 是退化到 proot。两者都没有集成进 adeb，这里只是提供一条 `adb root` 失败时拿到
> 真 root 的路径。
>
> | | Magisk | KernelSU |
> | --- | --- | --- |
> | 机制 | Systemless：打补丁到 boot 镜像，启动时叠加 `/system` | 内核态：由内核内组件授予 root（GKI 2.0 模块，或编译进自定义内核） |
> | 设备/内核要求 | 多数设备可用，只需能打补丁的 boot 镜像 | 需要兼容内核：官方 GKI 2.0（5.10+）、自编译内核（4.14+），或支持的 LKM 模块 |
> | 安装方式 | 用 Magisk app/CLI 打补丁 boot.img 再刷入 | 刷入/启动带 KernelSU 的内核，再用 app 管理 |
> | 模块生态 | 最大（1000+ 模块），最成熟 | 较小但在增长（300+ 模块），metamodule 架构 |
> | 对 adeb 的意义 | 设备兼容性最广——只是想要个 root shell 走 `--ssh` 的更稳妥默认选择 | 如果本来就在为 eBPF/BCC 自编译/刷自定义内核，顺手就是这条路 |
>
> 两者都只是给 adeb 提供一个能通过 `--ssh` 连上的 root shell；选哪个不影响进去
> 之后 chroot 后端能做什么。

两个后端安装在不同目录、不共享状态——chroot 的 rootfs 属 root，proot 读不了——所以
每个后端各 `adeb prepare` 一次。两个目录都在 `/data` 上，重启不丢。

### proot

[proot](https://proot-me.github.io/) 用 ptrace 模拟 chroot 和 root（`-0`），无需
root。它给不了真实内核权限，所以 eBPF/BCC/perf 不可用；ptrace 也有开销。

```bash
adeb prepare --proot --build --proot-bin /path/to/proot-<arch>
adeb shell
```

`--proot-bin` 是目标架构的静态 proot——来自 Termux（`pkg install proot`）、release
资产（`proot-arm64` / `proot-amd64`）或自行编译。rootfs 在 proot 内解包，以模拟设备
节点与硬链接。

proot 下 apt 的签名校验不可用（下载时掉权限读不了密钥环）。因此 proot rootfs 配置为
`APT::Sandbox::User "root"`、`_apt` 改回 `nogroup`、源标 `[trusted=yes]`：apt 可用，
但不校验归档签名。仅 proot 如此，chroot 后端仍正常校验。

## 追踪

tracefs 会从内核暴露的位置绑定挂载（`/sys/kernel/tracing`，旧内核为
`/sys/kernel/debug/tracing`）。需要 chroot 后端。

- bpftrace 和 libbpf CO-RE 工具需要内核 BTF（`/sys/kernel/btf/vmlinux`）。
- 经典 BCC python 工具需要内核头文件（`CONFIG_IKHEADERS` /
  `/sys/kernel/kheaders.tar.xz`）；没有则报 “Unable to find kernel headers”。

## 本地构建

主机：Ubuntu/Debian 或 Arch，装 `debootstrap` + `qemu-user-static`。

- Debian/Ubuntu：`sudo apt-get install qemu-user-static binfmt-support debootstrap`
- Arch：`sudo pacman -S debootstrap qemu-user-static qemu-user-static-binfmt`

构建本机同架构不用 qemu（CI 就是 amd64 在 x86、arm64 在 arm64 runner 上构建）。

## prepare 选项

| 选项                  | 含义 |
| --------------------- | ---- |
| （无）                | 下载并安装预构建基础镜像 |
| `--full`              | 完整镜像：编译器、编辑器、追踪器、BCC |
| `--build`             | 本地构建而非下载 |
| `--bcc`               | 从源码含 BCC（`--full` 已隐含） |
| `--buildtar <dir>`    | 另存 rootfs 到 `<dir>/androdeb-fs[-minimal][-<arch>].tgz.zip` |
| `--no-device`         | 配合 `--build --buildtar`：仅在主机构建，不碰设备 |
| `--build-image <img>` | 构建 raw EXT4 镜像（Qemu `-hda`）；无需设备 |
| `--archive <tar>`     | 安装已构建的 rootfs 压缩包 |
| `--arch <arch>`       | 目标架构（默认 `arm64`） |
| `--distro <name>`     | Debian 套件（默认 `bookworm`；环境变量 `DISTRO`） |
| `--mirror <url>`      | Debian 镜像（环境变量 `DEBIAN_MIRROR`） |
| `--proot`             | 非 root 的 proot 后端 |
| `--proot-bin <path>`  | 目标架构的静态 proot（隐含 `--proot`） |
| `--tempdir <dir>`     | 构建工作目录 |
| `-s`、`--device`      | adb 序列号 |

```bash
adeb prepare --build                 # 本地基础构建（chroot）
adeb prepare --full --build          # 本地完整构建（含 BCC）
adeb prepare --full --buildtar /out  # 构建并保留可复用压缩包
adeb prepare --archive /out/androdeb-fs.tgz
adeb prepare --build-image /tmp/adeb.img
```

## 其它架构

```bash
adeb prepare --arch amd64            # 预构建 amd64 镜像
adeb prepare --build --arch amd64    # 本地构建
```

预构建只有 arm64 与 amd64；其它架构需 `--build`。

## ssh

```bash
adeb --ssh user@host [--sshpass pass] <cmd>
```

目标须已 root。首次先在 adeb 外 ssh 一次以写入 `known_hosts`。

## CI

`.github/workflows/` 下：

- **lint** —— 对 shell 脚本跑 shellcheck。
- **smoke** —— 每架构原生构建基础 rootfs（amd64 在 `ubuntu-latest`、arm64 在
  `ubuntu-24.04-arm`）并 chroot 进去检查。
- **release** —— 打 `v*` tag 时，为 arm64 与 amd64 构建基础+完整镜像和静态 proot，
  发布到 release。
- **proot** —— 独立的静态 proot 构建。

lint/smoke 在 PR 与非 tag push 上运行，跳过纯 `**.md` 改动；release 在 tag 上运行。
`release-artifacts.sh` 从连接的设备构建并发布。

## 故障排查

- prepare 后 `apt-get install` 失败 → 先 `adeb shell apt-get update`。
- debootstrap 慢 → `--mirror <url>`（或 `DEBIAN_MIRROR`），如
  `https://mirror.tuna.tsinghua.edu.cn/debian`。
- `adeb shell '<含引号或 $() 的命令>'` 会弄乱参数（两个后端都如此）→ 写进脚本再跑。
