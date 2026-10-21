#!/usr/bin/env bash
#
# Optimisations réactivité/légèreté — les « 4 points » :
#   1. Baloo (indexeur Plasma) masqué pour tous les utilisateurs
#   2. irqbalance retiré (station de jeu : le kernel gère seul les IRQ)
#   3. Discover retiré (Bazaar est fourni pour les flatpaks)
#   4. KWin gaming + compression btrfs : via files/system
#      (etc/xdg/kwinrc, swam-btrfs-compress.service) et packages.yml
#      (cups/avahi en socket-activation)
set -ouex pipefail

### Baloo : masque system-wide les unités utilisateur de l'indexeur
## Le symlink vers /dev/null = masque systemd, vaut pour tous les users.
## (le réglage « Indexing-Enabled » est par utilisateur : inutilisable au build)
ln -sf /dev/null /etc/systemd/user/kde-baloo.service
ln -sf /dev/null /etc/systemd/user/baloo.service

### irqbalance : le scheduler kernel + sched_ext (scx_lavd) suffisent
dnf5 -y remove irqbalance || true

### Discover : retiré du socle (plasma-discover-notifier avec lui).
## Bazaar (default-flatpaks) couvre l'installation des applications ;
## les mises à jour système passent par bootc.
dnf5 -y remove plasma-discover plasma-discover-notifier || true

echo "tuning (baloo off, irqbalance off, discover off) : OK"
