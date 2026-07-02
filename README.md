[![lint](https://github.com/M1nt-Ch0c0/adeb/actions/workflows/lint.yml/badge.svg)](https://github.com/M1nt-Ch0c0/adeb/actions/workflows/lint.yml)
[![smoke](https://github.com/M1nt-Ch0c0/adeb/actions/workflows/smoke.yml/badge.svg)](https://github.com/M1nt-Ch0c0/adeb/actions/workflows/smoke.yml)

# adeb

中文: [README.zh-CN.md](README.zh-CN.md) · Advanced docs: [docs/ADVANCED.md](docs/ADVANCED.md)

Maintained fork of [joelagnel/adeb](https://github.com/joelagnel/adeb)
(archived), updated for Debian bookworm and current Android.

adeb runs a Debian userland on an Android device over adb — a chroot (or proot)
with apt, gcc/clang, perf/BCC/bpftrace, python and git. Compile and trace
on-device instead of cross-compiling.

## Quick start

```bash
git clone https://github.com/M1nt-Ch0c0/adeb && cd adeb
sudo ln -s "$(pwd)/adeb" /usr/bin/adeb    # optional

adeb prepare          # install the base env on the connected device
adeb prepare --full   # or the full image (compilers, tracers, BCC)
adeb shell            # enter; Ctrl-D to exit
adeb remove           # uninstall
```

`-s <serial>` picks a device; `--ssh <uri> [--sshpass <pass>]` targets a
non-Android host.

## Backends

|                                | chroot         | proot                  |
| ------------------------------ | -------------- | ---------------------- |
| root                           | required       | not required           |
| speed                          | native         | slower (ptrace)        |
| kernel tracing (eBPF/BCC/perf) | yes            | no                     |
| install dir                    | /data/androdeb | /data/local/tmp/adeb   |

chroot is the default; adeb falls back to proot when `adb root` fails, and
`--proot` forces it. The two are separate installs. See
[docs/ADVANCED.md](docs/ADVANCED.md#backends).

## Prebuilt images

CI publishes arm64 and amd64 images (base and full) per release, so
`adeb prepare [--full] [--arch amd64]` downloads them. Other architectures need
`--build`.

## Requirements

Target: ARM64 Android N+ with 2 GB free in `/data`. Host (only for local
builds): `debootstrap` + `qemu-user-static`.

Option reference and internals: [docs/ADVANCED.md](docs/ADVANCED.md).
BCC background: [BCC.md](BCC.md).
