# adeb

English: [README.md](README.md) · 进阶文档: [docs/ADVANCED.zh-CN.md](docs/ADVANCED.zh-CN.md)

[joelagnel/adeb](https://github.com/joelagnel/adeb)（已 archive）的维护分支，更新到
Debian bookworm 与当前 Android。

adeb 通过 adb 在 Android 设备上跑一个 Debian 用户态——chroot（或 proot），带 apt、
gcc/clang、perf/BCC/bpftrace、python、git。在设备上原生编译与追踪，不用交叉编译。

## 快速开始

```bash
git clone https://github.com/M1nt-Ch0c0/adeb && cd adeb
sudo ln -s "$(pwd)/adeb" /usr/bin/adeb    # 可选

adeb prepare          # 在已连接设备上安装基础环境
adeb prepare --full   # 或完整镜像（编译器、追踪器、BCC）
adeb shell            # 进入；Ctrl-D 退出
adeb remove           # 卸载
```

`-s <序列号>` 选设备；`--ssh <uri> [--sshpass <pass>]` 连非 Android 主机。

## 后端

|                          | chroot         | proot                  |
| ------------------------ | -------------- | ---------------------- |
| root                     | 需要           | 不需要                 |
| 速度                     | 原生           | 较慢（ptrace）         |
| 内核追踪（eBPF/BCC/perf）| 支持           | 不支持                 |
| 安装目录                 | /data/androdeb | /data/local/tmp/adeb   |

默认 chroot；`adb root` 失败时回退 proot，`--proot` 可强制。两者是各自独立的安装。
详见 [docs/ADVANCED.zh-CN.md](docs/ADVANCED.zh-CN.md#后端)。

## 预构建镜像

CI 每次发版发布 arm64 与 amd64 镜像（基础 + 完整），所以
`adeb prepare [--full] [--arch amd64]` 是下载。其它架构需 `--build`。

## 运行要求

目标：ARM64 Android N+，`/data` 有 2 GB 空闲。主机（仅本地构建时）：`debootstrap` +
`qemu-user-static`。

选项参考与内部机制见 [docs/ADVANCED.zh-CN.md](docs/ADVANCED.zh-CN.md)。
BCC 背景见 [BCC.md](BCC.md)。
