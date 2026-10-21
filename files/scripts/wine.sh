#!/usr/bin/env bash
#
# Wine + winetricks + protontricks — exécuter des applications Windows en natif.
#
# Vérifié dans les dépôts Fedora 44 :
#   wine         11.0       x86_64 — le paquet ne tire AUCUNE dépendance 32 bits
#                            (Wine 11 utilise le nouveau WoW64 : pas de multilib à installer)
#   winetricks   20260125   requires : cabextract, unzip, wget, wine-common, (kdialog|zenity)
#   protontricks 1.14.0     requires : winetricks, python3-vdf, python3-pillow
# Toutes ces dépendances viennent des dépôts Fedora : aucun dépôt tiers nécessaire.
#
# Note : c'est le wine amont de Fedora, pas wine-staging. Pour du staging,
# WineHQ publie un dépôt Fedora : https://dl.winehq.org/wine-builds/fedora/
set -ouex pipefail

### Les trois paquets (dnf résout seul cabextract / unzip / wget / vdf / pillow)
dnf5 -y install wine winetricks protontricks

### Contrôle : le build échoue plutôt que de livrer une image sans les outils
for p in wine winetricks protontricks; do
    rpm -q "$p" >/dev/null 2>&1 || { echo "ERREUR : paquet manquant -> $p"; exit 1; }
done
echo "wine / winetricks / protontricks : OK"
