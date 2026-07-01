#!/bin/bash
# This is run in the bcc directory of the chroot

cd bcc-master
rm -rf build && mkdir -p build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=./future-usr -DPYTHON_CMD=python3
make -j"$(nproc)"
make install
