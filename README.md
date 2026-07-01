[![lint](https://github.com/M1nt-Ch0c0/adeb/actions/workflows/lint.yml/badge.svg)](https://github.com/M1nt-Ch0c0/adeb/actions/workflows/lint.yml)
[![smoke](https://github.com/M1nt-Ch0c0/adeb/actions/workflows/smoke.yml/badge.svg)](https://github.com/M1nt-Ch0c0/adeb/actions/workflows/smoke.yml)

<!-- fork banner -->
> 📖 **中文文档 / Chinese docs:** [README.zh-CN.md](README.zh-CN.md)
>
> This is an **actively maintained fork** of the (now archived) original
> [joelagnel/adeb](https://github.com/joelagnel/adeb), brought up to date for
> current Debian and Android.
>
> **Main changes vs. upstream:**
> - **Debian bookworm (12)** instead of EOL buster; the removed
>   `qemu-debootstrap` is replaced by plain `debootstrap` + `qemu-user-static`.
> - **Python 3** everywhere — packages and the perf/BCC helper scripts.
> - **Unversioned LLVM/Clang** (was hardcoded LLVM 7); BCC builds against the
>   shared `libLLVM` (`ENABLE_LLVM_SHARED`) and fetches its git submodules.
> - **On-device fixes for modern Android**: restore the executable bit that
>   `adb push` strips, mount tracefs from `/sys/kernel/tracing` (kernel 6.x),
>   avoid unmount propagation to the device's real tracefs/bpffs, and make the
>   `_apt` AID_INET group fix Debian-release independent.
> - **New `--distro` / `--mirror` options**, prebuilt release images (so
>   `adeb prepare` can download instead of build) and a `release-artifacts.sh`
>   publisher; stale AOSP import files removed.
> - **Validated end-to-end on real hardware** (aarch64, kernel 6.12 / Android
>   16): the chroot boots, `apt` works, native `gcc`/`python3` compile, and
>   `bpftrace` attaches eBPF to the live kernel via BTF.
>
> This fork is **actively maintained and will keep being updated.** Issues and
> PRs are welcome.

adeb
--------

**adeb** (also known as **androdeb**) provides a powerful Linux shell
environment where one can run popular and mainstream Linux tracing, compiling,
editing and other development tools on an existing Android device. All the
commands typically available on a modern Linux system are supported in
adeb.

Usecases
--------
1. Powerful development environment with all tools ready to go (editors,
compilers, tracers, perl/python etc) for your on-device development.

2. No more cross-compiler needed: Because it comes with gcc and clang, one can
build target packages natively without needing to do any cross compilation. We even
ship git, and have support to run apt-get to get any missing development packages
from the web.

3. Using these one can run popular tools such as BCC that are difficult to run
in an Android environment due to lack of packages, dependencies and
cross-compilation needed for their operation. [Check BCC on Android using
adeb](https://github.com/joelagnel/adeb/blob/master/BCC.md) for more
information on that.

4. No more crippled tools: Its often a theme to build a static binary with
features disabled, because you couldn't cross-compile the feature's dependencies. One
classic example is perf. However, thanks to adeb, we can build perf natively
on device without having to cripple it.

Requirements for running
------------------------
Target:
An ARM64 android N or later device which has "adb root" supported. Typically
this is a build in a userdebug configuration. Device should have atleast 2 GB
free space in the data partition. If you would like to use other architectures,
see the [Other Architectures](https://github.com/joelagnel/adeb/blob/master/README.md#how-to-use-adeb-for-other-architectures-other-than-arm64) section.

You can also use ssh to run on non-android systems. The system must still be
rooted and has 2 GB of free space.

Notes on tracing (eBPF/BCC/bpftrace) support: adeb bind-mounts the kernel's
tracefs into the environment automatically, wherever the kernel exposes it
(modern kernels use `/sys/kernel/tracing`, older ones nested it under
`/sys/kernel/debug/tracing`). What actually runs then depends on the kernel:
* CO-RE tools (bpftrace, libbpf-based tools) work as long as the kernel was
  built with BTF (`/sys/kernel/btf/vmlinux` present) — true on most recent
  Android GKI kernels.
* Classic BCC python tools compile their programs at runtime and therefore need
  kernel headers. If the device kernel does not ship them
  (`CONFIG_IKHEADERS`/`/sys/kernel/kheaders.tar.xz`), those specific tools will
  report "Unable to find kernel headers"; prefer bpftrace/CO-RE tools there.

### Running without root (proot backend)
adeb has two backends for entering the Debian environment:

- **chroot (default, needs root)** — real `chroot` + bind mounts, native speed,
  full functionality including kernel tracing (eBPF/BCC/perf). Used when
  `adb root` (or `su`) is available.
- **proot (no root)** — [proot](https://proot-me.github.io/) uses `ptrace(2)`
  to emulate `chroot` and a fake root entirely in user space, so it runs on a
  stock, non-rooted device. You get a full Debian userland (apt, gcc/clang,
  python, git, editors, running normal programs), but **no kernel tracing**
  (eBPF/BCC/perf need real privileges the kernel won't grant under proot) and
  it is slower (every syscall goes through ptrace).

adeb auto-selects: if `adb root` fails it falls back to proot; use `--proot` to
force it. proot needs a static `proot` binary for the target arch, supplied
with `--proot-bin <path>` (e.g. the one from Termux's `pkg install proot`, or a
static build). Example:
```
adeb prepare --proot --build --proot-bin /path/to/proot-aarch64
adeb shell
```
The rootfs is installed unprivileged under `/data/local/tmp/adeb` and unpacked
*through* proot so device nodes and ownership are emulated. Note: in proot mode
`apt` archive-signature verification is relaxed (the sources are marked
`[trusted=yes]`), because apt's privilege-dropping keyring check does not work
under proot; the chroot backend keeps full verification.

Host:
A machine running recent Ubuntu or Debian, with 4GB of memory and 4GB free space.
Host needs the `debootstrap` and `qemu-user-static` packages. The old
`qemu-debootstrap` wrapper is no longer required: modern `debootstrap` bootstraps
a foreign architecture transparently as long as `qemu-user-static` (and its
binfmt handlers) are installed.
To install them on Debian/Ubuntu, run
`sudo apt-get install qemu-user-static binfmt-support debootstrap`.
On Arch Linux, run
`sudo pacman -S debootstrap qemu-user-static qemu-user-static-binfmt`.
Other distributions may work but they are not tested.

Quick Start Instructions
------------------------
* First clone this repository into adeb and cd into it.
```
cd adeb

# Add some short cuts:
sudo ln -s $(pwd)/adeb /usr/bin/adeb

# Cached image downloads result in a huge speed-up. These are automatic if you
# cloned the repository using git. However, if you downloaded the repository
# as a zip file (or you want to host images elsewere), you could set the
# ADEB_REPO_URL environment variable in your bashrc file.
# Disclaimer: Google is not liable for the below URL and this
#             is just an example.
export ADEB_REPO_URL="github.com/M1nt-Ch0c0/adeb/"
```

* Installing adeb onto your device:
First make sure device is connected to system
Then run, for the base image:
```
adeb prepare
```
The previous command only downloads and installs the base image.
Instead if you want to download and install the full image, do:
```
adeb prepare --full
```

* Now run adeb shell to enter your new environment!:
```
adeb shell
```

* Once done, hit `CTRL + D` and you will exit out of the shell.
To remove adeb from the device, run:
```
adeb remove
```
If you have multiple devices connected, please add `-s <serialnumber>`.
Serial numbers of all devices connected can be obtained by `adb devices`.

* To update an existing adeb clone on your host, run:
```
adeb git-pull
```

* To use ssh instead of adb to communicate with the target
```
adeb --ssh <uri> --sshpass <pass> <cmd>
```
If you use keys to authenticate then you can omit --sshpass option.
If you don't use keys you can still omit --sshpass option but you'd need to
keep an eye to enter the password at the right moments when prompted or it'll
timeout.

The first time you connect to the target make sure to ssh outside of adeb first
to add it to your known_hosts.


More advanced usage instructions
--------------------------------
### Build and prepare device with a custom rootfs locally:

The adeb fs will be prepared locally by downloading packages as needed:
```
adeb prepare --build
```
This is unlike the default behavior, where the adeb rootfs is itself pulled from the web.

If you wish to do a full build (that is locally prepare a rootfs with all packages, including bcc, then do):
```
adeb prepare --full --build
```

### Build/install a base image with BCC:
```
adeb prepare --bcc --build
```
Note: BCC is built from source.

### Extract the FS from the device, after its prepared:
```
adeb prepare --full --buildtar /path/
```
After device is prepared, it will extract the root fs from it
and store it as a tar archive at `/path/adeb-fs.tgz`. This
can be used later.

### Use a previously prepared adeb rootfs tar from local:
```
adeb prepare --archive /path/adeb-fs.tgz
```

### Build a standalone raw EXT4 image out of the FS:
```
adeb prepare --build-image /path/to/image.img
```
This can then be passed to Qemu as -hda. Note: This option doesn't need a
device connected.

### How to use adeb for other Architectures (other than ARM64)
By default adeb assumes the target Android device is based on ARM64
processor architecture. For other architectures, pass `--arch`. For example for
x86_64:
```
adeb prepare --arch amd64          # downloads the prebuilt amd64 image
adeb prepare --full --arch amd64   # downloads the prebuilt amd64 full image
adeb prepare --build --arch amd64  # or build it locally
```
Prebuilt **arm64 and amd64** images (base and full) are published automatically
by CI on each release — arm64 built on an arm64 runner, amd64 on an x86 runner
(see `.github/workflows/release.yml`). For any other architecture, pass
`--build` so adeb builds the rootfs locally instead of downloading.

### Continuous integration
- `lint` — shellcheck over all shell scripts.
- `smoke` — builds a base rootfs natively for amd64 and arm64 and chroots into
  it to verify it works.
- `release` — on a `v*` tag, builds base + full images for arm64 and amd64 on
  their native runners and publishes them to the tag's GitHub Release.

Triggers: `lint` and `smoke` run on pull requests and branch/master pushes but
skip docs-only (`**.md`) changes; `release` runs only on `v*` tags. So a
docs-only change runs nothing, a PR runs lint+smoke, and pushing a tag cuts a
release.

Maintainers can also build/publish images from a connected device with
`./release-artifacts.sh`.

Common Trouble shooting
-----------------
1. Installing g++ with `apt-get install g++` fails.

Solution: Run `adeb shell apt-get update` after the `adeb prepare` stage.

2. It's too slow to use debootstrap to create debian fs

Solution: Use a local mirror with the `--mirror` option (or the `DEBIAN_MIRROR`
environment variable). For example in China you could use:
```
adeb prepare --build --mirror https://mirror.tuna.tsinghua.edu.cn/debian
```
instead of the default official mirror http://deb.debian.org/debian .
