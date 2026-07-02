# adeb — Advanced & developer guide

Detailed reference for adeb. For a quick start see the top-level
[README.md](../README.md). 中文版: [ADVANCED.zh-CN.md](ADVANCED.zh-CN.md).

- [Changes vs. upstream](#changes-vs-upstream)
- [Backends (chroot vs proot)](#backends)
- [Kernel tracing requirements](#kernel-tracing-requirements)
- [Building locally](#building-locally)
- [`prepare` option reference](#prepare-option-reference)
- [Other architectures](#other-architectures)
- [Using ssh instead of adb](#using-ssh-instead-of-adb)
- [CI/CD pipeline](#cicd-pipeline)
- [Troubleshooting](#troubleshooting)

## Changes vs. upstream

This is an actively maintained fork of the archived
[joelagnel/adeb](https://github.com/joelagnel/adeb):

- **Debian bookworm (12)** instead of EOL buster; the removed `qemu-debootstrap`
  is replaced by plain `debootstrap` + `qemu-user-static`.
- **Python 3** everywhere — packages and the perf/BCC helper scripts.
- **Unversioned LLVM/Clang** (was hardcoded LLVM 7); BCC builds against the
  shared `libLLVM` (`ENABLE_LLVM_SHARED`) and fetches its git submodules.
- **On-device fixes for modern Android**: restore the executable bit that
  `adb push` strips; mount tracefs from `/sys/kernel/tracing` (kernel 6.x);
  avoid unmount propagation that would tear down the device's real
  tracefs/bpffs; make the `_apt` AID_INET group fix Debian-release independent.
- **Non-root proot backend** (see below) so unrooted devices get a Debian
  userland.
- **New options** `--distro`, `--mirror`, `--no-device`, `--proot`/`--proot-bin`;
  prebuilt multi-arch release images; `release-artifacts.sh`; CI (lint/smoke/
  release); stale AOSP import files removed.
- **Validated end-to-end on real hardware** (aarch64, kernel 6.12 / Android 16):
  chroot boots, `apt` works, native `gcc`/`python3` compile, `bpftrace` attaches
  eBPF to the live kernel via BTF; and, unrooted, the proot backend runs a
  Debian userland with working `apt`.

## Backends

adeb has two ways to enter the Debian environment.

|                                | chroot (default)        | proot (`--proot`)                |
| ------------------------------ | ----------------------- | -------------------------------- |
| Needs root                     | yes (`adb root` / `su`) | **no**                           |
| Mechanism                      | real `chroot` + binds   | `ptrace(2)` path/uid emulation   |
| Speed                          | native                  | slower (every syscall traced)    |
| Kernel tracing (eBPF/BCC/perf) | ✅ full                 | ❌ userland only                 |
| On-device dir                  | `/data/androdeb`        | `/data/local/tmp/adeb`           |

**Auto-selection.** For `shell`/`prepare` without `--proot`, adeb runs
`adb root`; if that succeeds it uses chroot, otherwise it falls back to the proot
backend automatically. Pass `--proot` to force proot even where root is
available. (On a userdebug device `adb root` succeeds, so you must pass `--proot`
to exercise proot there.)

**Independent installs.** The two backends live in different directories and are
**not** shared — the chroot rootfs under `/data/androdeb` is root-owned and
unreadable to an unprivileged process, so proot cannot reuse it. Run
`adeb prepare` once per backend you want. Both locations are on the persistent
`/data` (f2fs) partition, so an installed environment **survives reboots** (it
just needs the device unlocked once after boot for file-based encryption). Note:
`/data/local/tmp` is persistent despite the "tmp" in its name.

### proot backend details

[proot](https://proot-me.github.io/) uses `ptrace` to intercept syscalls,
rewrite paths so the rootfs looks like `/`, and (`-0`) present a fake uid 0 so
`apt`/`dpkg` are happy — all without root. Limitations: no kernel tracing
(`bpf()`/`perf_event_open()` still hit the real kernel with your unprivileged
uid and are denied), and ptrace overhead makes it slower.

Usage:
```bash
# proot needs a static proot binary for the target arch (--proot-bin):
adeb prepare --proot --build --proot-bin /path/to/proot-aarch64
adeb shell
```
Get a proot binary from Termux (`pkg install proot`), from this project's
release assets (`proot-arm64` / `proot-amd64`, built from source by CI), or build
your own. The rootfs is installed unprivileged under `/data/local/tmp/adeb` and
unpacked **through** proot so device nodes (`mknod`), ownership (`chown`) and
hardlinks are emulated (a plain non-root `tar` cannot create them).

**apt trade-off under proot.** `apt` drops privileges to a sandbox user for
downloads and verifies archive signatures via `apt-key`/`gpgv`; under proot the
privilege drop yields an empty user and every keyring is ignored, so
verification cannot work. adeb therefore configures the proot rootfs at unpack
time to: restore `_apt`'s gid to `nogroup` (buildstrap sets it to the Android
`AID_INET` group 3003, which the chroot backend needs but which is invalid under
proot), set `APT::Sandbox::User "root"`, and mark the sources `[trusted=yes]`.
Net effect: `apt` works, at the cost of archive-signature verification **in the
proot environment only** — the chroot backend keeps full verification.

## Kernel tracing requirements

adeb bind-mounts the kernel's tracefs into the (chroot) environment wherever the
kernel exposes it — modern kernels use `/sys/kernel/tracing`, older ones nested
it under `/sys/kernel/debug/tracing`. What runs then depends on the kernel:

- **CO-RE tools** (bpftrace, libbpf-based tools) work if the kernel has BTF
  (`/sys/kernel/btf/vmlinux` present) — true on most recent Android GKI kernels.
- **Classic BCC python tools** compile their programs at runtime and need kernel
  headers. If the device kernel does not ship them (`CONFIG_IKHEADERS` /
  `/sys/kernel/kheaders.tar.xz`), those tools report "Unable to find kernel
  headers"; prefer bpftrace / CO-RE tools there.

Tracing is only available under the **chroot** backend (needs real privilege).

## Building locally

Only needed if you build images instead of downloading them. Host: recent
Ubuntu/Debian or Arch, ~4 GB RAM and free space, with `debootstrap` +
`qemu-user-static`. The old `qemu-debootstrap` wrapper is not required: modern
`debootstrap` bootstraps a foreign architecture as long as `qemu-user-static`
and its binfmt handlers are installed.

- Debian/Ubuntu: `sudo apt-get install qemu-user-static binfmt-support debootstrap`
- Arch: `sudo pacman -S debootstrap qemu-user-static qemu-user-static-binfmt`

Building the **native** architecture needs no qemu at all (this is what CI does:
amd64 on an x86 runner, arm64 on an arm64 runner).

## `prepare` option reference

```
adeb prepare [options]
```

| Option              | Meaning |
| ------------------- | ------- |
| (none)              | Download & install the prebuilt base image |
| `--full`            | Download/build the full image (compilers, editors, tracers, BCC) |
| `--build`           | Build the rootfs locally (download packages) instead of downloading a prebuilt image |
| `--bcc`             | Include BCC (built from source); implied by `--full` |
| `--buildtar <dir>`  | After preparing, also produce `<dir>/androdeb-fs[-minimal][-<arch>].tgz.zip` |
| `--no-device <..>`  | With `--build --buildtar`: build the tarball on the host only, no device (used by CI) |
| `--build-image <img>` | Build a standalone raw EXT4 image (for Qemu `-hda`); needs no device |
| `--archive <tar>`   | Install a previously built rootfs tarball |
| `--arch <arch>`     | Target architecture (default `arm64`; e.g. `amd64`) |
| `--distro <name>`   | Debian suite (default `bookworm`); also `DISTRO` env |
| `--mirror <url>`    | Debian mirror (default `deb.debian.org`); also `DEBIAN_MIRROR` env |
| `--proot`           | Use the non-root proot backend |
| `--proot-bin <path>`| Static proot binary for the target arch (implies `--proot`) |
| `--tempdir <dir>`   | Work directory for the build |
| `-s` / `--device`   | adb serial when multiple devices are connected |

Examples:
```bash
adeb prepare --build                    # local base build, chroot
adeb prepare --full --build             # local full build with BCC
adeb prepare --full --buildtar /out     # build and also save a reusable tarball
adeb prepare --archive /out/androdeb-fs.tgz
adeb prepare --build-image /tmp/adeb.img
```

## Other architectures

adeb assumes ARM64 by default. For others, pass `--arch`:
```bash
adeb prepare --arch amd64          # downloads the prebuilt amd64 image
adeb prepare --full --arch amd64   # prebuilt amd64 full image
adeb prepare --build --arch amd64  # or build locally
```
Prebuilt **arm64** and **amd64** images (base + full) are published per release
by CI. For any other architecture pass `--build`.

## Using ssh instead of adb

```bash
adeb --ssh <user@host> --sshpass <pass> <cmd>
```
With key auth omit `--sshpass`. The target must be rooted and have ≥ 2 GB free.
SSH to the host once outside adeb first, to add it to `known_hosts`.

## CI/CD pipeline

Workflows under `.github/workflows/`:

- **lint** — `shellcheck` (error severity) over every tracked bash/sh script.
- **smoke** — builds a base rootfs natively for amd64 (`ubuntu-latest`) and arm64
  (`ubuntu-24.04-arm`) and chroots in to verify it is a working bookworm of the
  right architecture.
- **release** — on a `v*` tag (or manual dispatch): builds base + full images for
  arm64 and amd64 on their native runners, builds a static `proot` from source
  (musl/Alpine) for each arch, and publishes them all to the tag's GitHub Release
  with the `gh` CLI.
- **proot** — standalone static-`proot`-from-source build (arm64 + amd64),
  uploaded as artifacts.

**Triggers.** `lint`/`smoke` run on pull requests and branch/master pushes but
skip docs-only (`**.md`) changes and tag pushes; `release` runs only on `v*`
tags. So: docs-only change → nothing; PR → lint+smoke; push to master →
lint+smoke; tag → release.

Maintainers can also build & publish images from a connected device with
`./release-artifacts.sh` (needs an `adb root` device and an authenticated `gh`).

## Troubleshooting

**`apt-get install g++` fails right after prepare.** Run `adeb shell apt-get
update` first.

**debootstrap is slow.** Use a local mirror via `--mirror` (or `DEBIAN_MIRROR`),
e.g. in China:
```bash
adeb prepare --build --mirror https://mirror.tuna.tsinghua.edu.cn/debian
```

**`adeb shell '<complex command with $() or quotes>'` drops arguments.** adeb
passes shell args through several quoting layers; complex one-liners can get
mangled (this affects both backends). Put the commands in a script and run that,
or use an interactive `adeb shell`.

**proot: `apt` shows GPG/"not signed" warnings.** Expected — signature
verification is intentionally relaxed under proot (see
[Backends → apt trade-off](#backends)); installs still work.
