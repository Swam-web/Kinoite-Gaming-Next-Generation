#!/usr/bin/env bash

# Nettoyage final
set -ouex pipefail

## Kernel modules are prebuilt, remove the build toolchain
dnf5 -y remove kernel-cachyos-lto-devel
dnf5 versionlock delete kernel-cachyos-lto-devel || true

## Do not ship the build repositories enabled on the final image
## (RPMFusion et le dépôt AMD ROCm restent activés : mises à jour des pilotes)
dnf5 -y copr disable bieszczaders/kernel-cachyos-lto
dnf5 -y copr disable bieszczaders/kernel-cachyos-addons

## Repos hérités d'anciens builds, s'ils existent encore :
##   terra : clé GPG file:// absente de l'image -> casse le depsolve de
##           bootc-image-builder au moment de fabriquer les ISOs
##   negativo17 : remplacé par RPMFusion (ancienne pile)
rm -f /etc/yum.repos.d/*terra* /etc/dnf/dnf5/repos.d/*terra* /usr/share/dnf5/repos.d/*terra*
rm -f /etc/yum.repos.d/negativo17-fedora-nvidia.repo /etc/yum.repos.d/negativo17-fedora-multimedia.repo

## Garde-fou FINAL : la pile GPU doit avoir survécu à TOUS les modules.
## Dernier step exécutant des transactions dnf — c'est ici qu'une cascade
## tardive doit être détectée, jamais silencieusement (cf. bug 2026-10-13 :
## rocm.sh avait emporté toute la pile NVIDIA après coup, CI vert quand même).
command -v nvidia-smi >/dev/null 2>&1 \
    || { echo "ERREUR : userland NVIDIA absent (cascade dnf postérieure à nvidia.sh ?)"; exit 1; }
find /usr/lib/modules/*/ -name 'nvidia.ko*' 2>/dev/null | grep -q . \
    || { echo "ERREUR : nvidia.ko absent (cascade dnf postérieure à nvidia.sh ?)"; exit 1; }
rpm -q xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda-libs >/dev/null 2>&1 \
    || { echo "ERREUR : paquets RPM NVIDIA absents"; exit 1; }
ls -d /opt/rocm* >/dev/null 2>&1 \
    || { echo "ERREUR : /opt/rocm* absent — la pile ROCm n'a pas survécu"; exit 1; }
echo "garde-fou GPU final (nvidia-smi, nvidia.ko, RPM, ROCm) : OK"
