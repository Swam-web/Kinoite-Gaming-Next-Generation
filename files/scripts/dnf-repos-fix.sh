#!/usr/bin/env bash
# dnf5 a déplacé les repos de distribution hors de /etc : ils vivent désormais
# dans /usr/share/dnf5/repos.d/ — et /etc/yum.repos.d/ est VIDE sur F45.
# Conséquence : les outils qui lisent l'ancien emplacement (depsolve anaconda
# de bootc-image-builder, entre autres) ne voient AUCUN repo -> "No match for
# argument" sur tous les paquets du manifest ISO.
# Fix : dupliquer les repos FEDORA vers /etc/yum.repos.d/ (jamais les repos de
# build — COPR/google-chrome/rpmfusion — que cleanup.sh désactive).
# Idempotent : cp -n n'écrase pas un fichier /etc existant.
set -ouex pipefail

mkdir -p /etc/yum.repos.d
cp -n /usr/share/dnf5/repos.d/fedora*.repo /etc/yum.repos.d/
echo "repos dnf5 -> /etc/yum.repos.d :"
ls -la /etc/yum.repos.d/
