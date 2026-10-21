#!/usr/bin/env bash

# AMD ROCm : depot officiel + pile userland
## Fedora n'est pas une cible officielle d'AMD : ce sont les paquets RHEL 9
## qui sont utilises. Les depots AMD restent actives sur l'image finale pour
## que ROCm recoive les mises a jour.
## Aucun dkms : amdgpu est le pilote in-tree, fourni par le kernel (CachyOS
## compris) — le depot AMD ne propose qu'amdgpu-dkms, inutilisable sur bootc.
set -ouex pipefail

### Depot officiel AMD (ROCm) — EPINGLÉ sur 7.2.4 (dernière stable de la branche 7.2)
## latest/ suit la dernière publiée : une ROCm 8.x pourrait casser l'ABI userland
## (libhsa/OpenCL) au prochain dnf upgrade. Épinglé = on choisit QUAND monter.
## Bump : liste des versions sur https://repo.radeon.com/rocm/rhel9/
## (7.2.4 vérifiée 2026-10-12 : repodata 200 OK ; 7.2.3 dispo aussi)
cat > /etc/yum.repos.d/rocm.repo <<'EOF'
[rocm]
name=AMD ROCm
baseurl=https://repo.radeon.com/rocm/rhel9/7.2.4/main/
enabled=1
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
enabled_metadata=1
metadata_expire=6h
type=rpm-md
repo_gpgcheck=0
EOF

### /opt : NE PAS y toucher — géré par BlueBuild (optfix)
## pre_build remplace /opt par un lien vers /usr/lib/opt : les RPM rocm-*
## s'installent physiquement dans /usr/lib/opt/rocm-* et le post_build cree
## les symlinks tmpfiles /opt/rocm-* -> /usr/lib/opt/rocm-* pour le runtime.
## L'ancien hack `rm -f /opt && mkdir -p /opt` (utile pour le build.sh
## d'origine, ou /opt pointait vers /var/opt inexistant) est DÉLÉTÈRE ici :
## le post_build fait `rm -rf /opt` en fin de build et emportait toute la
## pile ROCm — le check ci-dessous passait, mais dans une image qui la
## perdait juste après (bug prouvé par analyse des couches OCI, 2026-10).

### ocl-icd : requis par rocm-opencl, a la place d'OpenCL-ICD-Loader
## L'ICD loader fourni par la base entre en conflit avec le Provide ocl-icd
## attendu par rocm-opencl. SWAP en TRANSACTION UNIQUE : ocl-icd fournit
## libOpenCL.so.1 des le debut de la transaction, donc dnf ne rencontre
## JAMAIS de dependance non satisfaite -> aucune cascade de suppression.
## (Un `remove` suivi d'un `install` ouvrait une fenetre sans fournisseur
## de libOpenCL.so.1 : dnf5 emportait xorg-x11-drv-nvidia-cuda-libs puis,
## en cascade, TOUTE la pile NVIDIA userland + le kmod — 722 whiteouts,
## nvidia-smi disparu de l'image publiée, bug 2026-10-13.)
## Fallback : si OpenCL-ICD-Loader est absent, simple install.
dnf5 -y swap OpenCL-ICD-Loader ocl-icd || dnf5 -y --refresh install ocl-icd

### Pile ROCm — MINIMALE pour le gaming
## HIP (rocm-hip-runtime, rocm-libs/rocBLAS…) = calcul GPU / IA (~5-6 Go),
## inutile aux jeux : ils passent par Vulkan/DXVK (mesa). Qui en a besoin :
##   rpm-ostree install rocm-hip-runtime rocm-libs
dnf5 -y install \
    rocm-core \
    rocm-opencl-runtime \
    rocm-smi

### Verification : on echoue ici plutot que de livrer une image sans ROCm
command -v rocm-smi >/dev/null 2>&1 || {
    echo "ERREUR : rocm-smi absent — la pile ROCm n'a pas ete installee"
    exit 1
}
ls -d /opt/rocm* >/dev/null 2>&1 || {
    echo "ERREUR : /opt/rocm* absent — les RPM rocm-* ne se sont pas installes"
    exit 1
}
echo "ROCm (minimal gaming) installe : $(ls -d /opt/rocm* | head -1)"
