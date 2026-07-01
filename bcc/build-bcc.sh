#!/bin/bash
# This script should run within a bcc checkout
set -e

spath=$( cd "$(dirname "$0")" ; pwd -P )
cd $spath

# The tree is typically cloned on the host (as a normal user) and built here
# inside the chroot as root, which trips git's "dubious ownership" guard. Allow
# any repo so that any git operation the build performs does not abort.
git config --global --add safe.directory '*' 2>/dev/null || true

# Modern BCC only supports Python 3, so a single configure/build/install is
# enough (the old two-stage py2+py3 dance is gone). Let cmake pick the system
# compiler instead of pinning a specific clang version.
rm -rf build && mkdir -p build && cd build
# ENABLE_TESTS pulls in a zip-based test fixture (needs the `zip` tool) and the
# examples/tests are not shipped, so disable both: it avoids an extra build
# dependency and speeds up the build.
#
# ENABLE_LLVM_SHARED links against the LLVM/Clang shared libraries instead of
# the static component archives. Debian's llvm-*-dev does not ship every static
# component (e.g. libPolly.a), so a static link fails; linking the shared libLLVM
# avoids that and is also distro-version agnostic.
cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DPYTHON_CMD=python3 \
	-DENABLE_TESTS=OFF -DENABLE_EXAMPLES=OFF -DENABLE_LLVM_SHARED=1
make -j"$(nproc)"
make install
cd ..
rm -rf build
