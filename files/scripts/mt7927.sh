#!/usr/bin/env bash

# MediaTek MT7927 WiFi + MT6639 Bluetooth
## Out-of-tree patched modules from jetm/mediatek-mt7927-dkms, prebuilt
## in the image against the CachyOS kernel (dkms does not work on bootc).
set -ouex pipefail

KERNEL_VERSION="$(rpm -q kernel-cachyos-lto --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"

dnf5 -y install patch

MT7927_VERSION="2.16-1"
MT7927_DIR="$(mktemp -d /tmp/mt7927-XXXXXXXX)"
curl -sL -f -o "${MT7927_DIR}/src.tar.gz" \
    "https://github.com/jetm/mediatek-mt7927-dkms/archive/refs/tags/v${MT7927_VERSION}.tar.gz"
tar -xzf "${MT7927_DIR}/src.tar.gz" -C "${MT7927_DIR}" --strip-components=1

make -C "${MT7927_DIR}" download
make -C "${MT7927_DIR}" sources

## Build with clang (the CachyOS kernel is clang/LTO)
export CC=clang CXX=clang++ LD=ld.lld LLVM=1 LLVM_IAS=1
make -C "/usr/lib/modules/${KERNEL_VERSION}/build" M="${MT7927_DIR}/_build/mt76" modules
make -C "/usr/lib/modules/${KERNEL_VERSION}/build" M="${MT7927_DIR}/_build/bluetooth" modules
unset CC CXX LD LLVM LLVM_IAS

## Install the modules (updates/ shadows the in-tree ones)
make -C "/usr/lib/modules/${KERNEL_VERSION}/build" M="${MT7927_DIR}/_build/mt76" modules_install INSTALL_MOD_PATH= INSTALL_MOD_DIR=updates
make -C "/usr/lib/modules/${KERNEL_VERSION}/build" M="${MT7927_DIR}/_build/bluetooth" modules_install INSTALL_MOD_PATH= INSTALL_MOD_DIR=updates

MT7925_KO="$(find /usr/lib/modules/"${KERNEL_VERSION}"/updates -name 'mt7925e.ko*' -print -quit)"
if [[ -z "${MT7925_KO}" ]]; then
    exit 1
fi
depmod -a "${KERNEL_VERSION}"

## Bluetooth firmware blob (ours to ship: linux-firmware does not have it yet)
install -Dm644 "${MT7927_DIR}/_build/firmware/BT_RAM_CODE_MT6639_2_1_hdr.bin" \
    /usr/lib/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin

rm -rf "${MT7927_DIR}"
