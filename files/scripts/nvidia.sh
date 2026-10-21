#!/usr/bin/env bash

# NVIDIA drivers from RPMFusion (rpmfusion-nonfree), kernel modules built
# with clang against the CachyOS kernel.
#
# RPMFusion UNIQUEMENT : aucun dépôt tiers. C'est la même pile que l'image amd,
# ce qui supprime tout risque de conflit entre fournisseurs.
set -ouex pipefail

KERNEL_VERSION="$(rpm -q kernel-cachyos-lto --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"

### 1. RPMFusion free + nonfree : source unique pour cette image
### --refresh : les métadonnées dnf en cache (< 48h) peuvent référencer des
### versions de paquets que Fedora vient de retirer des miroirs (supplantées
### par une nouvelle version, ex: mesa) -> "All mirrors were tried". Forcer
### le refresh rend le build insensible à ce churn amont.
### Fallback : le rotateur mirrors.rpmfusion.org peut servir un miroir mort
### (ex: repos.eggycrew.com, NXDOMAIN le 2026-10-20) et dnf5 retente le même
### miroir sans en choisir un autre -> on retombe sur le serveur primaire
### download1.rpmfusion.org (pas de mirrorlist, indépendant de la rotation).
FEDORA="$(rpm -E %fedora)"
dnf5 -y --refresh install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA}.noarch.rpm" \
|| dnf5 -y install \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA}.noarch.rpm" \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA}.noarch.rpm"

### 2. akmods (requis par le contrôle de dépendances d'akmod-nvidia)
dnf5 -y install akmods

### 3. akmod-nvidia SANS son %post : le scriptlet (akmods-ostree-post) lance
###    akmodsbuild en root, qui refuse quand /var est modifiable et fait échouer
###    toute la transaction. Installé d'abord avec --noscripts, il enregistre
###    néanmoins ses Provides (nvidia-kmod, nvidia-kmod-common…) : l'installation
###    du userland ci-dessous ne le retirera donc pas avec son %post cassé.
DRIVER_VERSION="$(dnf5 repoquery --qf '%{VERSION}-%{RELEASE}\n' akmod-nvidia | sort -V | tail -n1)"
dnf5 -y download --destdir /tmp/nvidia-rpms "akmod-nvidia-${DRIVER_VERSION}"
rpm -i --noscripts --nodeps /tmp/nvidia-rpms/akmod-nvidia-*.rpm
rm -rf /tmp/nvidia-rpms

### 4. La base verrouille (versionlock) les paquets mesa, ce qui gêne
###    l'installation des variantes i686. On lève les verrous et on ne
###    re-verrouille que le kernel.
dnf5 versionlock clear || true
dnf5 versionlock add kernel-cachyos-lto kernel-cachyos-lto-devel || true

### 5. Userland NVIDIA (RPMFusion) — les variantes i686 sont requises par les
###    jeux 32 bits de Steam
dnf5 -y install \
    xorg-x11-drv-nvidia \
    xorg-x11-drv-nvidia-libs \
    xorg-x11-drv-nvidia-libs.i686 \
    xorg-x11-drv-nvidia-cuda \
    xorg-x11-drv-nvidia-cuda-libs \
    xorg-x11-drv-nvidia-cuda-libs.i686 \
    xorg-x11-drv-nvidia-power \
    nvidia-settings \
    nvidia-persistenced \
    nvidia-modprobe

### 5b. Bibliothèques i686 dont le userland NVIDIA a besoin
dnf5 -y install mesa-libEGL.i686 mesa-libGL.i686

### 6. Ajustements post-installation (identiques aux images ublue)
rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json
if [[ -f /usr/lib/dracut/dracut.conf.d/99-nvidia.conf ]]; then
    sed -i 's@omit_drivers@force_drivers@g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
    sed -i 's@ nvidia @ i915 amdgpu nvidia @g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
fi
systemctl enable nvidia-persistenced.service

### 7. Compilation des modules noyau avec rpmbuild en root : l'akmodsbuild
###    refuse root (contrôle [[ -w /var ]]) et le runuser d'akmods échoue en
###    conteneur (session PAM). Le SRPM de l'akmod fournit le spec et les
###    sources open-gpu-kernel-modules ; clang car le kernel CachyOS est
###    clang/LTO. rpmbuild ne crée pas son arborescence lui-même.
###
###    Dépendances de construction de la spec RPMFusion, qu'akmodsbuild
###    résoudrait seul mais que le rpmbuild direct doit avoir sous la main :
###      /usr/bin/pahole                  (BTF)
###      xorg-x11-drv-nvidia-kmodsrc      (sources open-gpu-kernel-modules)
dnf5 -y install pahole xorg-x11-drv-nvidia-kmodsrc

NVIDIA_BUILD="/tmp/nvidia-build"
mkdir -p "${NVIDIA_BUILD}"/{BUILD,SOURCES,SPECS,SRPMS,RPMS}

export CC=clang CXX=clang++ LD=ld.lld LLVM=1 LLVM_IAS=1
rpmbuild --rebuild --define "_topdir ${NVIDIA_BUILD}" --define "kernels ${KERNEL_VERSION}" /usr/src/akmods/nvidia-kmod.latest
unset CC CXX LD LLVM LLVM_IAS

find "${NVIDIA_BUILD}/RPMS" -type f -name '*.rpm' ! -name '*debuginfo*' -exec rpm -i {} \;
rm -rf "${NVIDIA_BUILD}"
depmod -a "${KERNEL_VERSION}"

### 8. Nettoyage du dépôt terra livré par la base : sa clé GPG en file:// est
###    absente de l'image, ce qui casse le depsolve de bootc-image-builder au
###    moment de fabriquer les images disque (ISO).
rm -f /etc/yum.repos.d/*terra* /etc/dnf/dnf5/repos.d/*terra* /usr/share/dnf5/repos.d/*terra*

### 9. Contrôle : le module noyau ET le userland doivent exister
NVIDIA_KO="$(find /usr/lib/modules/"${KERNEL_VERSION}" -name 'nvidia.ko*' -print -quit)"
if [[ -z "${NVIDIA_KO}" ]]; then
    cat /var/cache/akmods/nvidia/*.failed.log 2>/dev/null || true
    echo "ERREUR : nvidia.ko absent pour ${KERNEL_VERSION}"
    exit 1
fi
echo "nvidia (RPMFusion) : OK -> ${NVIDIA_KO}"

### 10. Contrôle userland : nvidia-smi et les paquets RPMFusion doivent être
###     présents ICI — un `remove` dnf dans un module ULTÉRIEUR (rocm.sh…) a
###     déjà cascadié leur suppression après ce point (bug 2026-10-13) ;
###     le garde-fou définitif est dans cleanup.sh, dernier step dnf.
command -v nvidia-smi >/dev/null 2>&1 || {
    echo "ERREUR : nvidia-smi absent (userland NVIDIA)"
    exit 1
}
rpm -q xorg-x11-drv-nvidia xorg-x11-drv-nvidia-libs \
      xorg-x11-drv-nvidia-cuda-libs >/dev/null 2>&1 || {
    echo "ERREUR : paquets userland NVIDIA absents"
    exit 1
}
echo "nvidia userland : OK (nvidia-smi, -nvidia, -libs, -cuda-libs)"
