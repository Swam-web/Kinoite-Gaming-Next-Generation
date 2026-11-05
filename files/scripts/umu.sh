#!/usr/bin/env bash
# umu-launcher — Unified launcher for Windows Games (umu-run)
## Permet de lancer les jeux Windows avec Proton hors Steam/Lutris/Heroic.
## RPM épinglé de la release officielle 1.4.4 (pas de COPR : 404) — le plus sûr.
## Les RPM du projet sont non signés : dnf5 par URL, fallback rpm -i --nosignature.
set -ouex pipefail

VERSION="1.4.4"
URL="https://github.com/Open-Wine-Components/umu-launcher/releases/download/${VERSION}/umu-launcher-${VERSION}.fc44.x86_64.rpm"

dnf5 -y install "$URL" || {
    curl -fsSL "$URL" -o /tmp/umu-launcher.rpm
    rpm -i --nosignature /tmp/umu-launcher.rpm
}

command -v umu-run >/dev/null && echo "umu-launcher : OK -> $(command -v umu-run)"
