#!/usr/bin/env bash

# OpenRazer — périphériques Razer (claviers, souris, tapis…)
## FAIL-SOFT (comme mt7927/controllers) : add-on matériel, source GitHub.
## kmods compilés clang contre le kernel CachyOS (les RPM/COPR Fedora
## ciblent le kernel stock : ABI incompatible — cf. caveat README).
## Daemon : installé via setup.py (PEP 668 ne bloque que pip, pas distutils) ;
## dépendances Python fournies par les dépôts Fedora.
set -ouex pipefail

KERNEL_VERSION="$(rpm -q kernel-cachyos-lto --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
KBUILD="/usr/lib/modules/${KERNEL_VERSION}/build"

build_razer() {
    set -euex pipefail

    dnf5 -y --refresh install git python3-daemonize python3-pyudev \
        python3-dbus python3-gobject3 python3-setproctitle python3-setuptools

    RAZER_VER="v3.12.4"
    RAZER_DIR="$(mktemp -d /tmp/openrazer-XXXXXXXX)"
    git clone --depth 1 --branch "${RAZER_VER}" \
        https://github.com/openrazer/openrazer "${RAZER_DIR}"

    export CC=clang CXX=clang++ LD=ld.lld LLVM=1 LLVM_IAS=1
    make -C "${RAZER_DIR}" driver KERNELDIR="${KBUILD}"
    unset CC CXX LD LLVM LLVM_IAS

    ## les 3 modules (razerkbd, razermouse, razorfire) -> updates/
    install -d "/usr/lib/modules/${KERNEL_VERSION}/updates"
    install -m 644 "${RAZER_DIR}"/driver/*.ko \
        "/usr/lib/modules/${KERNEL_VERSION}/updates/"
    depmod -a "${KERNEL_VERSION}"

    ## daemon + bibliothèque + udev + unité utilisateur systemd
    make -C "${RAZER_DIR}" udev_install
    make -C "${RAZER_DIR}" python_library_install
    make -C "${RAZER_DIR}" install-systemd
    make -C "${RAZER_DIR}" daemon_install

    command -v openrazer-daemon >/dev/null
    RAZER_KO="$(find /usr/lib/modules/${KERNEL_VERSION}/updates -name 'razer*.ko*' -print -quit)"
    [[ -n "${RAZER_KO}" ]]
    rm -rf "${RAZER_DIR}"
}

if build_razer; then
    echo "OpenRazer : modules + daemon installés pour ${KERNEL_VERSION}"
else
    echo "AVERTISSEMENT : OpenRazer non installé (source GitHub ou dépendance indisponible) — périphériques Razer sans daemon" >&2
fi

exit 0
