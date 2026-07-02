[![lint](https://github.com/M1nt-Ch0c0/adeb/actions/workflows/lint.yml/badge.svg)](https://github.com/M1nt-Ch0c0/adeb/actions/workflows/lint.yml)
[![smoke](https://github.com/M1nt-Ch0c0/adeb/actions/workflows/smoke.yml/badge.svg)](https://github.com/M1nt-Ch0c0/adeb/actions/workflows/smoke.yml)

# adeb

> 📖 中文文档: **[README.zh-CN.md](README.zh-CN.md)** · 🛠 Advanced & developer docs: **[docs/ADVANCED.md](docs/ADVANCED.md)**
>
> Actively maintained fork of the archived
> [joelagnel/adeb](https://github.com/joelagnel/adeb), modernized for current
> Debian (bookworm) and Android — and still being updated. See
> [what changed vs. upstream](docs/ADVANCED.md#changes-vs-upstream).

**adeb** (aka **androdeb**) gives you a full Debian Linux shell on an Android
device — editors, compilers (gcc/clang), tracers (perf/BCC/bpftrace), python,
git — with `apt` to pull anything else. Build and trace natively on-device, no
cross-compilation, no crippled static binaries.

## Quick start

```bash
git clone https://github.com/M1nt-Ch0c0/adeb && cd adeb
sudo ln -s "$(pwd)/adeb" /usr/bin/adeb    # optional shortcut

adeb prepare          # install the base env on the connected device
adeb prepare --full   # ...or the full image (compilers, tracers, BCC)
adeb shell            # enter it;  Ctrl-D to exit
adeb remove           # uninstall from the device
```

Multiple devices: add `-s <serial>`. Non-Android target over ssh:
`adeb --ssh <uri> --sshpass <pass>`.

## Two backends: root vs non-root

|                              | chroot (default)      | proot (`--proot`)        |
| ---------------------------- | --------------------- | ------------------------ |
| Needs root                   | yes (`adb root`/`su`) | **no**                   |
| Speed                        | native                | slower (ptrace)          |
| Kernel tracing (eBPF/BCC/perf) | ✅                  | ❌ (userland only)       |
| On-device location           | `/data/androdeb`      | `/data/local/tmp/adeb`   |

adeb uses chroot when root is available and otherwise falls back to proot; force
it with `--proot`. The two are **independent installs** (each needs its own
`adeb prepare`) and both persist across reboots. Details in
[docs/ADVANCED.md § Backends](docs/ADVANCED.md#backends).

## Prebuilt images

Prebuilt **arm64** and **amd64** rootfs images (base + full) are published per
release by CI, so `adeb prepare [--full] [--arch amd64]` downloads instead of
building. For any other architecture, add `--build`.

## Requirements

- **Target:** ARM64 Android (N or later), ≥ 2 GB free in `/data`. Root
  (`adb root`) is needed only for the chroot backend; proot needs none.
- **Host** (only if building images locally): recent Ubuntu/Debian/Arch with
  `debootstrap` + `qemu-user-static` — see
  [docs/ADVANCED.md § Building locally](docs/ADVANCED.md#building-locally).

## More

Everything else — the full option reference (`--build`, `--buildtar`,
`--build-image`, `--archive`, `--distro`, `--mirror`, `--proot-bin`, …),
backend/proot/apt internals, kernel-tracing requirements, the CI/CD pipeline,
and troubleshooting — lives in **[docs/ADVANCED.md](docs/ADVANCED.md)**.
BCC-on-Android background: [BCC.md](BCC.md).
