#!/usr/bin/env bash

# Kernel CachyOS (clang LTO) remplaçant le kernel stock Fedora
## Shim the kernel-install scriptlets so dracut/rpm-ostree are not triggered
## during the build, following the Bazzite install-kernel-akmods pattern.
set -ouex pipefail

### Enable COPRs (CachyOS kernel + addons)
dnf5 -y copr enable bieszczaders/kernel-cachyos-lto
dnf5 -y copr enable bieszczaders/kernel-cachyos-addons

pushd /usr/lib/kernel/install.d
for script in 05-rpmostree.install 50-dracut.install; do
    if [[ -f "${script}" ]]; then
        mv "${script}" "${script}.bak"
        printf '%s\n' '#!/bin/sh' 'exit 0' > "${script}"
        chmod +x "${script}"
    fi
done
popd

## Remove the stock kernel and the kmods that were built for it
for pkg in kernel kernel{-core,-modules,-modules-core,-modules-extra,-tools-libs,-tools}; do
    if rpm -q "${pkg}" >/dev/null 2>&1; then
        rpm --erase "${pkg}" --nodeps
    fi
done
mapfile -t STOCK_KMODS < <(rpm -qa --qf '%{NAME}\n' | grep -E '^(kmod-|openrazer)' | grep -vE '^kmod-libs$' || true)
for pkg in "${STOCK_KMODS[@]}"; do
    rpm --erase "${pkg}" --nodeps
done
rm -rf /usr/lib/modules

## Remove the versionlock entries the base image left for the stock kernel
dnf5 versionlock delete kernel kernel-devel kernel-devel-matched kernel-core kernel-modules || true

## Install the CachyOS kernel and its headers
## (devel pulls clang/lld/make and provides kernel-devel-uname-r for module builds)
## --refresh : cf. nvidia.sh — métadonnées en cache vs versions retirées du COPR
dnf5 -y --refresh install kernel-cachyos-lto kernel-cachyos-lto-devel

## Lock the kernel packages so nothing replaces them during the rest of the build
dnf5 versionlock add kernel-cachyos-lto kernel-cachyos-lto-devel

KERNEL_VERSION="$(rpm -q kernel-cachyos-lto --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
echo "CachyOS kernel: ${KERNEL_VERSION}"

## Restore the kernel-install scriptlets
pushd /usr/lib/kernel/install.d
for script in 05-rpmostree.install 50-dracut.install; do
    if [[ -f "${script}.bak" ]]; then
        mv -f "${script}.bak" "${script}"
    fi
done
popd
