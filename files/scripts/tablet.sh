#!/usr/bin/env bash

# OpenTabletDriver — tablettes graphiques (Wacom, XP-Pen, Huion…)
## FAIL-SOFT (comme mt7927/controllers) : add-on matériel.
## Userland PUR (aucun kmod — pas de souci d'ABI) : RPM officiel du projet
## + runtime .NET depuis les dépôts Fedora. Daemon en service utilisateur.
set -ouex pipefail

build_tablet() {
    set -euex pipefail

    OTD_VER="0.6.7"
    dnf5 -y --refresh install dotnet-runtime-8.0
    dnf5 -y install "https://github.com/OpenTabletDriver/OpenTabletDriver/releases/download/v${OTD_VER}/opentabletdriver-${OTD_VER}-1.x86_64.rpm"

    ## vérifications : paquet + règles udev + unité utilisateur systemd
    rpm -q "opentabletdriver-${OTD_VER}-1" >/dev/null 2>&1 \
        || rpm -q opentabletdriver >/dev/null 2>&1
    ls /usr/lib/udev/rules.d/*opentabletdriver* >/dev/null 2>&1 \
        || ls /etc/udev/rules.d/*opentabletdriver* >/dev/null 2>&1
}

if build_tablet; then
    echo "OpenTabletDriver : installé (v${OTD_VER})"
else
    echo "AVERTISSEMENT : OpenTabletDriver non installé (release GitHub indisponible) — tablettes graphiques sans driver dédié" >&2
fi

exit 0
