# adeb 中文文档

> 📖 English: **[README.md](README.md)** · 🛠 进阶 / 开发者文档: **[docs/ADVANCED.zh-CN.md](docs/ADVANCED.zh-CN.md)**
>
> 原始项目 [joelagnel/adeb](https://github.com/joelagnel/adeb)（已 archive）的
> **活跃维护分支**，已针对当前 Debian（bookworm）与 Android 现代化，并持续更新。
> 相较原仓库的改动见[这里](docs/ADVANCED.zh-CN.md#相较原仓库的改动)。

**adeb**（又名 **androdeb**）在 Android 设备上提供一个完整的 Debian Linux shell
——编辑器、编译器（gcc/clang）、追踪器（perf/BCC/bpftrace）、python、git——并用
`apt` 获取其它一切。在设备上原生编译与追踪，无需交叉编译，也不用阉割静态二进制。

## 快速开始

```bash
git clone https://github.com/M1nt-Ch0c0/adeb && cd adeb
sudo ln -s "$(pwd)/adeb" /usr/bin/adeb    # 可选快捷方式

adeb prepare          # 在已连接设备上安装基础环境
adeb prepare --full   # 或安装完整镜像（编译器、追踪器、BCC）
adeb shell            # 进入；Ctrl-D 退出
adeb remove           # 从设备卸载
```

多设备加 `-s <序列号>`；非 Android 目标用 ssh：`adeb --ssh <uri> --sshpass <pass>`。

## 两个后端：root 与非 root

|                          | chroot（默认）        | proot（`--proot`）         |
| ------------------------ | --------------------- | -------------------------- |
| 需要 root                | 是（`adb root`/`su`） | **否**                     |
| 速度                     | 原生                  | 较慢（ptrace）             |
| 内核追踪（eBPF/BCC/perf）| ✅                    | ❌（仅用户态）             |
| 设备上位置               | `/data/androdeb`      | `/data/local/tmp/adeb`     |

有 root 时用 chroot，否则自动回退到 proot；用 `--proot` 强制。两者是**各自独立的
安装**（各需 `adeb prepare` 一次），且都在持久分区上，**重启不丢**。详见
[docs/ADVANCED.zh-CN.md § 后端](docs/ADVANCED.zh-CN.md#后端chroot-与-proot)。

## 预构建镜像

CI 每次发版会发布 **arm64** 和 **amd64** 的预构建 rootfs 镜像（基础 + 完整），所以
`adeb prepare [--full] [--arch amd64]` 是下载而非构建。其它架构加 `--build`。

## 运行要求

- **目标设备**：ARM64 Android（N 及以上），`/data` 至少 2 GB 空闲。只有 chroot 后端
  需要 root（`adb root`），proot 后端无需 root。
- **主机**（仅本地构建镜像时需要）：较新的 Ubuntu/Debian/Arch，装
  `debootstrap` + `qemu-user-static`，见
  [docs/ADVANCED.zh-CN.md § 本地构建](docs/ADVANCED.zh-CN.md#本地构建)。

## 更多

完整选项参考（`--build`、`--buildtar`、`--build-image`、`--archive`、`--distro`、
`--mirror`、`--proot-bin` 等）、后端/proot/apt 内部机制、内核追踪要求、CI/CD 流水线、
故障排查，都在 **[docs/ADVANCED.zh-CN.md](docs/ADVANCED.zh-CN.md)**。
BCC on Android 背景见 [BCC.md](BCC.md)。
