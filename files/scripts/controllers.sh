#!/usr/bin/env bash

# Manettes — xpadneo (Bluetooth Xbox avancé) + xone (dongle USB Xbox One/Series)
## FAIL-SOFT (comme mt7927) : add-on matériel dépendant de sources GitHub ;
## un échec n'abolit pas le build public. Le reste de l'image reste fail-fast.
## Les deux modules sont compilés clang contre le kernel CachyOS (ABI LTO).
## In-tree déjà présent : xpad (manettes filaires/BT basique) — ces drivers
## ajoutent rumble avancé (xpadneo) et le support du dongle sans fil (xone).
set -ouex pipefail

KERNEL_VERSION="$(rpm -q kernel-cachyos-lto --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
KBUILD="/usr/lib/modules/${KERNEL_VERSION}/build"

build_xpadneo() {
    set -euex pipefail

    dnf5 -y --refresh install git

    XPADNEO_VER="v0.10.4"
    XPADNEO_DIR="$(mktemp -d /tmp/xpadneo-XXXXXXXX)"
    git clone --depth 1 --branch "${XPADNEO_VER}" \
        https://github.com/atar-axis/xpadneo "${XPADNEO_DIR}"

    export CC=clang CXX=clang++ LD=ld.lld LLVM=1 LLVM_IAS=1
    make -C "${KBUILD}" M="${XPADNEO_DIR}/hid-xpadneo/src" modules
    unset CC CXX LD LLVM LLVM_IAS

    ## module -> updates/ (prend le pas sur le hid générique)
    make -C "${KBUILD}" M="${XPADNEO_DIR}/hid-xpadneo/src" modules_install \
        INSTALL_MOD_PATH= INSTALL_MOD_DIR=updates

    ## configs du projet (modprobe.d + udev rules)
    install -m 644 "${XPADNEO_DIR}/hid-xpadneo/etc-modprobe.d/"* /etc/modprobe.d/
    install -m 644 "${XPADNEO_DIR}/hid-xpadneo/etc-udev-rules.d/"* /etc/udev/rules.d/

    HID_XPADNEO_KO="$(find /usr/lib/modules/${KERNEL_VERSION}/updates -name 'hid-xpadneo.ko*' -print -quit)"
    [[ -n "${HID_XPADNEO_KO}" ]]
    depmod -a "${KERNEL_VERSION}"
    rm -rf "${XPADNEO_DIR}"
}

build_xone() {
    set -euex pipefail

    dnf5 -y --refresh install git cabextract

    ## Épinglé sur le commit « Fix compatibility with latest kernel » (2025-12).
    ## Fetch PAR SHA (GitHub accepte allowAnySHA1InWant) : un clone --depth 1
    ## ne contient que le tip — checkout d'un SHA plus ancien échouerait
    ## (« reference is not a tree ») et le fail-soft livrait l'image SANS xone
    ## silencieusement (bug 2026-10). Le tip actuel (3484f60) n'est qu'une
    ## note README postérieure au commit épinglé.
    XONE_SHA="a70a3c8b9591bde813e673f4cd1b16059d696774"
    XONE_DIR="$(mktemp -d /tmp/xone-XXXXXXXX)"
    git init -q "${XONE_DIR}"
    git -C "${XONE_DIR}" remote add origin https://github.com/medusalix/xone
    git -C "${XONE_DIR}" fetch -q --depth 1 origin "${XONE_SHA}"
    git -C "${XONE_DIR}" checkout -q FETCH_HEAD

    export CC=clang CXX=clang++ LD=ld.lld LLVM=1 LLVM_IAS=1
    make -C "${KBUILD}" M="${XONE_DIR}" modules
    unset CC CXX LD LLVM LLVM_IAS

    make -C "${KBUILD}" M="${XONE_DIR}" modules_install \
        INSTALL_MOD_PATH= INSTALL_MOD_DIR=updates
    install -m 644 "${XONE_DIR}/install/modprobe.conf" /etc/modprobe.d/xone.conf

    ## Firmware du dongle : téléchargé chez Microsoft au build (chaque
    ## builder récupère chez l'émetteur, rien n'est redistribué par le repo).
    ## --skip-disclaimer : acceptation des termes MS par le mainteneur.
    sh "${XONE_DIR}/install/firmware.sh" --skip-disclaimer
    [[ -f /usr/lib/firmware/xow_dongle.bin ]]

    XONE_KO="$(find /usr/lib/modules/${KERNEL_VERSION}/updates -name 'xone_dongle.ko*' -print -quit)"
    [[ -n "${XONE_KO}" ]]
    depmod -a "${KERNEL_VERSION}"
    rm -rf "${XONE_DIR}"
}

if build_xpadneo; then
    echo "xpadneo : module installé pour ${KERNEL_VERSION}"
else
    echo "AVERTISSEMENT : xpadneo non installé (source GitHub indisponible) — manettes BT en mode xpad standard" >&2
fi

if build_xone; then
    echo "xone : modules + firmware dongle installés pour ${KERNEL_VERSION}"
else
    echo "AVERTISSEMENT : xone non installé (source GitHub ou firmware MS indisponible) — dongle Xbox sans fil non supporté" >&2
fi

exit 0
