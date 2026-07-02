# adeb — advanced reference

Quick start: [README.md](../README.md). 中文: [ADVANCED.zh-CN.md](ADVANCED.zh-CN.md).

## Changes vs. upstream

Fork of the archived [joelagnel/adeb](https://github.com/joelagnel/adeb):

- Debian bookworm (was buster); `debootstrap` + `qemu-user-static` (was the
  removed `qemu-debootstrap`).
- Python 3; unversioned LLVM/Clang (was LLVM 7); BCC linked against shared
  libLLVM.
- Modern-Android fixes: restore the exec bit `adb push` drops; tracefs at
  `/sys/kernel/tracing`; non-recursive binds so teardown can't unmount the
  device's real tracefs/bpffs; release-independent `_apt` group fix.
- Non-root proot backend.
- New options `--distro`, `--mirror`, `--no-device`, `--proot`/`--proot-bin`;
  multi-arch prebuilt images; CI (lint/smoke/release).

## Backends

|                                | chroot         | proot                  |
| ------------------------------ | -------------- | ---------------------- |
| root                           | required       | not required           |
| mechanism                      | chroot + binds | ptrace emulation       |
| speed                          | native         | slower                 |
| kernel tracing (eBPF/BCC/perf) | yes            | no                     |
| install dir                    | /data/androdeb | /data/local/tmp/adeb   |

`shell`/`prepare` run `adb root`: success selects chroot, failure selects proot.
`--proot` forces proot (needed on userdebug devices, where `adb root` succeeds).

The backends install to different directories and don't share state — the chroot
rootfs is root-owned and unreadable to proot — so run `adeb prepare` once per
backend. Both directories are on `/data` and survive reboots.

### proot

[proot](https://proot-me.github.io/) emulates chroot and root (`-0`) with
ptrace, needing no root. It can't grant real kernel privileges, so
eBPF/BCC/perf don't work, and ptrace adds overhead.

```bash
adeb prepare --proot --build --proot-bin /path/to/proot-<arch>
adeb shell
```

`--proot-bin` is a static proot for the target arch — from Termux
(`pkg install proot`), the release assets (`proot-arm64` / `proot-amd64`), or
your own build. The rootfs is unpacked through proot so device nodes and
hardlinks are emulated.

apt signature verification does not work under proot (the download privilege
drop can't read the keyrings). The proot rootfs is therefore configured with
`APT::Sandbox::User "root"`, `_apt` moved back to `nogroup`, and `[trusted=yes]`
sources: apt works, archive signatures are not verified. proot only — the chroot
backend verifies normally.

## Tracing

tracefs is bind-mounted from wherever the kernel exposes it
(`/sys/kernel/tracing`, or `/sys/kernel/debug/tracing` on older kernels).
Requires the chroot backend.

- bpftrace and libbpf CO-RE tools need kernel BTF (`/sys/kernel/btf/vmlinux`).
- Classic BCC python tools need kernel headers (`CONFIG_IKHEADERS` /
  `/sys/kernel/kheaders.tar.xz`); without them they fail with "Unable to find
  kernel headers".

## Building locally

Host: Ubuntu/Debian or Arch with `debootstrap` + `qemu-user-static`.

- Debian/Ubuntu: `sudo apt-get install qemu-user-static binfmt-support debootstrap`
- Arch: `sudo pacman -S debootstrap qemu-user-static qemu-user-static-binfmt`

Native-arch builds don't use qemu (CI builds amd64 on x86 and arm64 on arm64
runners).

## prepare options

| Option                | Meaning |
| --------------------- | ------- |
| (none)                | Download and install the prebuilt base image |
| `--full`              | Full image: compilers, editors, tracers, BCC |
| `--build`             | Build locally instead of downloading |
| `--bcc`               | Include BCC from source (implied by `--full`) |
| `--buildtar <dir>`    | Also write the rootfs to `<dir>/androdeb-fs[-minimal][-<arch>].tgz.zip` |
| `--no-device`         | With `--build --buildtar`: build on the host only, no device |
| `--build-image <img>` | Build a raw EXT4 image (Qemu `-hda`); no device |
| `--archive <tar>`     | Install a prebuilt rootfs tarball |
| `--arch <arch>`       | Target arch (default `arm64`) |
| `--distro <name>`     | Debian suite (default `bookworm`; env `DISTRO`) |
| `--mirror <url>`      | Debian mirror (env `DEBIAN_MIRROR`) |
| `--proot`             | Non-root proot backend |
| `--proot-bin <path>`  | Static proot for the target arch (implies `--proot`) |
| `--tempdir <dir>`     | Build work directory |
| `-s`, `--device`      | adb serial |

```bash
adeb prepare --build                 # local base build (chroot)
adeb prepare --full --build          # local full build with BCC
adeb prepare --full --buildtar /out  # build and keep a reusable tarball
adeb prepare --archive /out/androdeb-fs.tgz
adeb prepare --build-image /tmp/adeb.img
```

## Other architectures

```bash
adeb prepare --arch amd64            # prebuilt amd64 image
adeb prepare --build --arch amd64    # build locally
```

Prebuilt arm64 and amd64 images ship per release; any other arch needs
`--build`.

## ssh

```bash
adeb --ssh user@host [--sshpass pass] <cmd>
```

The target must be rooted. ssh to it once outside adeb first to populate
`known_hosts`.

## CI

Workflows in `.github/workflows/`:

- **lint** — shellcheck over the shell scripts.
- **smoke** — build a base rootfs natively per arch (amd64 on `ubuntu-latest`,
  arm64 on `ubuntu-24.04-arm`) and chroot in to check it.
- **release** — on a `v*` tag: build base + full images and a static proot for
  arm64 and amd64, publish them to the release.
- **proot** — standalone static-proot build.

lint/smoke run on PRs and non-tag pushes and skip `**.md`-only changes; release
runs on tags. `release-artifacts.sh` builds and publishes from a connected
device.

## Troubleshooting

- `apt-get install` fails right after prepare → `adeb shell apt-get update`
  first.
- debootstrap is slow → `--mirror <url>` (or `DEBIAN_MIRROR`), e.g.
  `https://mirror.tuna.tsinghua.edu.cn/debian`.
- `adeb shell '<command with quotes or $()>'` mangles arguments (both backends)
  → put it in a script.
