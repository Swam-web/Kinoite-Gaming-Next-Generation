#!/usr/bin/env bash
#
# Codecs SYSTÈME universels — pour les applications *natives*
# (Plasma/KWin, Firefox RPM, VLC RPM, Kdenlive, mpv, Elisa…)
#
# Fusion des piles nvidia/amd :
#   - RPMFusion seule source tierce (ffmpeg, freeworld, libdvdcss)
#   - VA-API/Vulkan AMD/Intel : mesa « freeworld » (inerte sur NVIDIA,
#     qui utilise son propre ICD Vulkan + NVDEC)
#   - VA-API NVIDIA : pont NVDEC -> VA-API via libva-nvidia-driver
#
# Toutes les commandes viennent de la doc officielle RPMFusion (Howto/Multimedia).
set -ouex pipefail

FEDORA="$(rpm -E %fedora)"

### 1. Dépôts RPMFusion : free + nonfree (URLs officielles de la doc)
### --refresh : métadonnées en cache vs versions retirées des miroirs
### (ex: mesa supplantée -> "All mirrors were tried")
### Fallback download1 : miroir mort servi par le rotateur (eggycrew,
### 2026-10-20) — voir nvidia.sh pour le détail.
dnf5 -y --refresh install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA}.noarch.rpm" \
|| dnf5 -y install \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA}.noarch.rpm" \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA}.noarch.rpm"

### 1b. Dépôt tainted (nécessaire pour libdvdcss) : par NOM de paquet.
###     Il n'existe PAS d'URL « -release-tainted » dans free/ (404 vérifié en
###     build) ; le paquet est fourni par rpmfusion-free, activé juste au-dessus.
dnf5 -y install rpmfusion-free-release-tainted

### 2. openh264 vit dans un dépôt Fedora désactivé par défaut
dnf5 config-manager setopt fedora-cisco-openh264.enabled=1

### 3. ffmpeg complet (remplace le ffmpeg-free privé des codecs brevetés).
###    Après ce swap, libavcodec-freeworld est inutile et redondant (doc RPMFusion).
dnf5 -y swap ffmpeg-free ffmpeg --allowerasing

### 4. Compléments multimédia / GStreamer (commande officielle RPMFusion)
###    libheif-freeworld exclu : désynchronisé de Fedora (10/2026) — la 1.21.2
###    exige libheif = 1.21.2, la 1.23.6 exige libheif = 1.23.6 inexistant,
###    Fedora updates fournit 1.23.5 (via libheif-ffmpeg) → transaction sans
###    solution. Décodage HEIC couvert par ffmpeg ; à retirer quand RPMFusion
###    resynchronise sa 1.23.5.
dnf5 -y install @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin,libheif-freeworld

### 5. H.264 (openh264) + lecture des DVD chiffrés
dnf5 -y install gstreamer1-plugin-openh264 libdvdcss

### 6. Accélération matérielle — AMD/Intel (mesa « freeworld »)
###    Inerte sur NVIDIA : le driver propriétaire fournit son propre ICD Vulkan.
###    Durci 11/2026 : RPMFusion fige l'EVR exact (mesa-va-drivers-freeworld
###    exige mesa-filesystem = même version) ; un décalage Fedora/RPMFusion
###    (26.2.6 vs 26.2.5, 10/2026) rendait la transaction insoluble et bloquait
###    toute la build pour des paquets que cette image NVIDIA n'utilise pas.
###    -> best effort : avertissement au log, le build continue.
try_freeworld() {
    dnf5 -y "$@" || echo "AVERTISSEMENT : freeworld ignoré (décalage RPMFusion probable) -> $*"
}
try_freeworld install mesa-va-drivers-freeworld
dnf5 -y swap mesa-vulkan-drivers mesa-vulkan-drivers-freeworld \
    || echo "AVERTISSEMENT : swap mesa-vulkan-drivers-freeworld ignoré (décalage RPMFusion probable)"

### 7. Accélération matérielle — NVIDIA
###    Le pilote propriétaire ne fait pas de VA-API nativement : libva-nvidia-driver
###    fait le pont NVDEC/NVENC -> VA-API (paquet Fedora, aucun conflit possible).
dnf5 -y install libva-nvidia-driver

### 8. Pilotes vidéo 32 bits — requis par Steam pour les jeux 32 bits.
###    Le Flatpak Steam apporte son propre runtime 32 bits, mais PAS les pilotes
###    de l'hôte : sans ça, ni Vulkan ni GL ni VA-API en 32 bits.
###    (freeworld i686 : best effort, cf. étape 6 — inerte sur NVIDIA.)
dnf5 -y install mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 vulkan-loader.i686 libva.i686
try_freeworld install mesa-va-drivers-freeworld.i686
dnf5 -y install libva-nvidia-driver.i686
dnf5 -y swap mesa-vulkan-drivers.i686 mesa-vulkan-drivers-freeworld.i686 \
    || echo "AVERTISSEMENT : swap mesa-vulkan-drivers-freeworld.i686 ignoré (décalage RPMFusion probable)"

### 9. Contrôle : le build échoue plutôt que de livrer une image sans codecs.
###    Strict uniquement sur les ESSENTIELS (lecture, DVD, openh264, pont
###    NVIDIA, loaders 32 bits). Les variantes mesa « freeworld » restent
###    volontairement tolérantes : inertes sur NVIDIA, fragiles par conception
###    (EVR figé côté RPMFusion) — leur absence ne dégrade rien sur ce GPU.
for p in ffmpeg libdvdcss gstreamer1-plugin-openh264 \
         mesa-dri-drivers.i686 vulkan-loader.i686 libva.i686 \
         libva-nvidia-driver libva-nvidia-driver.i686; do
    rpm -q "$p" >/dev/null 2>&1 || { echo "ERREUR : paquet manquant -> $p"; exit 1; }
done
echo "codecs système universels (AMD freeworld + NVIDIA VA-API bridge) : OK"
