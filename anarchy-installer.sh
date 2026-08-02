#!/bin/bash
set -euo pipefail

# ============================================================
#  Anarchy Linux Installer
#  Arch Linux + Hyprland (UWSM) + SDDM
#  Full offline install via local pacman repo
# ============================================================

INSTALLER_VERSION="1.0.0"
SETTLE_DELAY=2

# ------------------------------------------------------------
#  Colors (Tokyo Night)
# ------------------------------------------------------------
C_MAUVE="\e[38;2;187;154;247m"
C_BLUE="\e[38;2;122;162;247m"
C_TEAL="\e[38;2;125;207;255m"
C_GREEN="\e[38;2;158;206;106m"
C_RED="\e[38;2;247;118;142m"
C_SUBTEXT="\e[38;2;169;177;214m"
C_WHITE="\e[38;2;192;202;245m"
C_YELLOW="\e[38;2;224;175;104m"
C_RESET="\e[0m"

info()    { echo -e "${C_TEAL}::${C_RESET} $1"; }
success() { echo -e "${C_GREEN}::${C_RESET} $1"; }
error()   { echo -e "${C_RED}::${C_RESET} $1"; }
fatal()   { error "$1"; exit 1; }

header() {
    gum style \
        --border double \
        --align center \
        --foreground "$C_BLUE" \
        --border-foreground "$C_BLUE" \
        "$1"
}

# ------------------------------------------------------------
#  Header
# ------------------------------------------------------------
clear
gum style \
    --border double \
    --align center \
    --foreground "$C_MAUVE" \
    --border-foreground "$C_MAUVE" \
    "Anarchy Linux Install" "v${INSTALLER_VERSION}"

# ------------------------------------------------------------
#  Pre-flight Checks
# ------------------------------------------------------------
echo
info "Running pre-flight checks..."

umount -R /mnt &>/dev/null || true

[[ $EUID -eq 0 ]] || fatal "This script must be run as root."

if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
    success "Internet connection detected."
else
    echo -e "${C_YELLOW}No internet connection detected. Continuing with offline install from local repo.${C_RESET}"
fi

IS_EFI=false
[[ -d "/sys/firmware/efi" ]] && IS_EFI=true

# ------------------------------------------------------------
#  Drive Selection
# ------------------------------------------------------------
echo
header "Drive Selection"

TARGET_DRIVE=$(lsblk -dpno NAME,SIZE | gum choose --header "Select target drive" | awk '{print $1}')
[[ -n "$TARGET_DRIVE" ]] || fatal "No drive selected."

if [[ "$TARGET_DRIVE" =~ [0-9]$ ]]; then
    EFI_PART="${TARGET_DRIVE}p1"
    ROOT_PART="${TARGET_DRIVE}p2"
else
    EFI_PART="${TARGET_DRIVE}1"
    ROOT_PART="${TARGET_DRIVE}2"
fi

# ------------------------------------------------------------
#  User Information
# ------------------------------------------------------------
echo
header "User Information"

prompt_nonempty() {
    local result=""
    while [[ -z "$result" ]]; do
        result=$(gum input --placeholder "$1" --prompt " $2 ")
    done
    echo "$result"
}

ROOT_PASS=$(prompt_nonempty "Root password" " ")
NEW_USER=$(prompt_nonempty "Username" " ")
NEW_PASS=$(prompt_nonempty "User password" " ")

TIMEZONE=$(timedatectl list-timezones | gum filter --placeholder "Search timezone..." --prompt " Timezone: ")
TIMEZONE=${TIMEZONE:-UTC}

NEW_HOSTNAME=$(prompt_nonempty "Hostname" " ")

# ------------------------------------------------------------
#  System Configuration
# ------------------------------------------------------------
echo
header "System Configuration"

KERNEL=$(gum choose --header "Select Kernel" "linux" "linux-lts" "linux-zen" "linux-hardened")
[[ -n "$KERNEL" ]] || fatal "No kernel selected."

if [[ "$KERNEL" == "linux" ]]; then
    KERNEL_HEADERS="linux-headers"
else
    KERNEL_HEADERS="${KERNEL}-headers"
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    CPU=$(gum choose --header "Select CPU Microcode" "intel-ucode" "amd-ucode")
else
    CPU="none"
fi

GPU_RAW=$(gum choose --no-limit --header "Select GPU Driver(s)..." \
    "mesa" "nvidia" "nvidia-lts" "nvidia-dkms" \
    "xf86-video-intel" "vulkan-radeon" "vulkan-intel" "none")
GPU_PKGS=$(echo "$GPU_RAW" | grep -v '^none$' | tr '\n' ' ')

AUDIO=$(gum choose --header "Select Audio Server" "pipewire" "pulseaudio")
if [[ "$AUDIO" == "pipewire" ]]; then
    AUDIO_PKGS="pipewire pipewire-pulse pipewire-alsa wireplumber"
else
    AUDIO_PKGS="pulseaudio pulseaudio-alsa pulseaudio-bluetooth"
fi

AUR_HELPER=$(gum choose --header "Select AUR Helper" "yay" "paru" "pikaur" "none")

# ------------------------------------------------------------
#  Summary
# ------------------------------------------------------------
clear
gum style \
    --border double \
    --align center \
    --foreground "$C_MAUVE" \
    --border-foreground "$C_MAUVE" \
    "Review & Confirm"

echo
echo -e "  ${C_BLUE}Username:${C_RESET}      $NEW_USER"
echo -e "  ${C_BLUE}Hostname:${C_RESET}      $NEW_HOSTNAME"
echo -e "  ${C_BLUE}Timezone:${C_RESET}      $TIMEZONE"
echo -e "  ${C_BLUE}Target:${C_RESET}        ${C_YELLOW}$TARGET_DRIVE${C_RESET}"
echo -e "  ${C_BLUE}Boot Mode:${C_RESET}     $([ "$IS_EFI" = true ] && echo "UEFI" || echo "BIOS")"
echo -e "  ${C_BLUE}Kernel:${C_RESET}        $KERNEL"
echo -e "  ${C_BLUE}CPU:${C_RESET}           $CPU"
echo -e "  ${C_BLUE}GPU:${C_RESET}           ${GPU_PKGS:-none}"
echo -e "  ${C_BLUE}Audio:${C_RESET}         $AUDIO"
echo -e "  ${C_BLUE}AUR Helper:${C_RESET}    $AUR_HELPER"
echo

if ! gum confirm --affirmative "Proceed" --negative "Abort" "This will WIPE $TARGET_DRIVE. Continue?"; then
    fatal "Installation aborted."
fi

# ============================================================
#  EXECUTION
# ============================================================
set -e

cleanup() {
    error "Script failed. Cleaning up..."
    umount -Rlf /mnt 2>/dev/null || true
}
trap cleanup ERR

# ------------------------------------------------------------
#  Partitioning
# ------------------------------------------------------------
info "Partitioning $TARGET_DRIVE..."

swapoff "$TARGET_DRIVE"* 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
for part in $(lsblk -rno NAME "$TARGET_DRIVE" | tail -n +2); do
    umount "/dev/$part" 2>/dev/null || true
done

sgdisk -Z "$TARGET_DRIVE" &>/dev/null

if [[ "$IS_EFI" == true ]]; then
    sgdisk -n 1:0:+512M -t 1:ef00 "$TARGET_DRIVE"
else
    sgdisk -n 1:0:+1M -t 1:ef02 "$TARGET_DRIVE"
fi
sgdisk -n 2:0:0 -t 2:8300 "$TARGET_DRIVE"

partprobe "$TARGET_DRIVE"
sleep "$SETTLE_DELAY"

# ------------------------------------------------------------
#  Filesystems
# ------------------------------------------------------------
info "Formatting partitions..."

if [[ "$IS_EFI" == true ]]; then
    mkfs.vfat -F 32 "$EFI_PART"
fi
mkfs.btrfs -L ARCH_ROOT -f "$ROOT_PART"

# ------------------------------------------------------------
#  Btrfs Subvolumes
# ------------------------------------------------------------
info "Creating btrfs subvolumes..."

mount "$ROOT_PART" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@.snapshots

umount -R /mnt

OPTS="noatime,compress=zstd"
mount -o "subvol=@" "$ROOT_PART" /mnt
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot}

mount -o "subvol=@home" "$ROOT_PART" /mnt/home
mount -o "subvol=@log" "$ROOT_PART" /mnt/var/log
mount -o "subvol=@pkg" "$ROOT_PART" /mnt/var/cache/pacman/pkg
mount -o "subvol=@.snapshots" "$ROOT_PART" /mnt/.snapshots

if [[ "$IS_EFI" == true ]]; then
    mount "$EFI_PART" /mnt/boot
fi

# ------------------------------------------------------------
#  Local Repo & Pacman Configuration
# ------------------------------------------------------------
info "Configuring pacman for local repo..."

# Check a few common locations where the repo might live on the ISO
if [[ -d "/repo" ]]; then
    REPO_SRC="/repo"
elif [[ -d "$(dirname "$0")/repo" ]]; then
    REPO_SRC="$(dirname "$0")/repo"
elif [[ -d "./repo" ]]; then
    REPO_SRC="./repo"
else
    fatal "Local repo not found. Cannot proceed with offline install."
fi

ORIG_CONF="/etc/pacman.conf"
cp "$ORIG_CONF" "${ORIG_CONF}.bak"

sed -i '/\[anarchy-repo\]/,/^$/d' "$ORIG_CONF"

sed -i '/^\[core\]/i \
[anarchy-repo]\nSigLevel = Optional TrustAll\nServer = file:///'"$REPO_SRC"'/x86_64\n' "$ORIG_CONF"

pacman -Sy

# ------------------------------------------------------------
#  Pacstrap
# ------------------------------------------------------------
info "Installing base system with pacstrap..."

PACKAGES=(
    base
    "$KERNEL" "$KERNEL_HEADERS"
    linux-firmware
    btrfs-progs
    grub
    networkmanager
    sddm
    gum
    git
    sudo
    zsh
    rsync
    stow
    arch-update
    hyprland
    uwsm
    xdg-desktop-portal-hyprland
    xdg-utils
    xdg-user-dirs
    polkit
    qt5-wayland
    qt6-wayland
    xorg-xwayland
    kitty
    neovim
    nautilus
    rofi
    hypridle
    hyprlock
    hyprmon-bin
    hyprpicker
    pyprland
    oh-my-zsh-git
    gradience-git
    goverlay-git
    nwg-displays
    nwg-look
    kvantum-qt6-git
    adw-gtk-theme-git
    eza
    blueman
    bluez
    bluez-utils
    swaync
    vesktop-bin
    vencord-bin
    inter-font
    ttf-jetbrains-mono-nerd
    ttf-font-awesome
    otf-font-awesome
    python-pywal16
    python-pywalfox
    python-gobject
    python-cssutils
    python-libsass
    python-anyascii
    python-material-color-utilities
    python-yapsy-git
    awww
    wlsunset
    grim-git
    slurp-git
    wf-recorder-git
    vkbasalt
    xfce-polkit
    zsh-autocomplete
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-fast-syntax-highlighting
    zsh-autoswitch-virtualenv-git
    qt5-graphicaleffects
    qt5-imageformats
    qt5-multimedia
    qt5-quickcontrols
    qt5-quickcontrols2
    qt5-styleplugins
    qt5-svg
    qt6-base
    qt6-declarative
    qt6-imageformats
    qt6-multimedia
    qt6-svg
    gtk2
    mesa-utils
    nautilus-admin-gtk4
    nautilus-open-any-terminal-git
    coolercontrol
    coolercontrold
    plymouth
    vlc
    vlc-plugins-all
    xdg-terminal-exec
)

[[ "$CPU" != "none" ]] && PACKAGES+=("$CPU")
[[ -n "$GPU_PKGS" ]] && PACKAGES+=($GPU_PKGS)
PACKAGES+=($AUDIO_PKGS)

if [[ "$IS_EFI" == true ]]; then
    PACKAGES+=(efibootmgr)
fi

pacstrap -K -C /etc/pacman.conf /mnt "${PACKAGES[@]}"

# Restore original pacman.conf on ISO
cp "$ORIG_CONF.bak" "$ORIG_CONF" 2>/dev/null || true

# ------------------------------------------------------------
#  Fstab
# ------------------------------------------------------------
info "Generating fstab..."

genfstab -U /mnt >> /mnt/etc/fstab

# ------------------------------------------------------------
#  Chroot Configuration
# ------------------------------------------------------------
info "Configuring system in chroot..."

cp -r "$REPO_SRC" /mnt/repo

ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

printf 'ROOT_PASS=%s\n' "$ROOT_PASS" >> /mnt/.install_env
printf 'NEW_USER=%s\n' "$NEW_USER" >> /mnt/.install_env
printf 'NEW_PASS=%s\n' "$NEW_PASS" >> /mnt/.install_env
printf 'TIMEZONE=%s\n' "$TIMEZONE" >> /mnt/.install_env
printf 'NEW_HOSTNAME=%s\n' "$NEW_HOSTNAME" >> /mnt/.install_env
printf 'ROOT_UUID=%s\n' "$ROOT_UUID" >> /mnt/.install_env
printf 'IS_EFI=%s\n' "$IS_EFI" >> /mnt/.install_env
printf 'TARGET_DRIVE=%s\n' "$TARGET_DRIVE" >> /mnt/.install_env
printf 'AUR_HELPER=%s\n' "$AUR_HELPER" >> /mnt/.install_env

arch-chroot /mnt /bin/bash <<'CHEOF'
set -e
source /.install_env

# Keyring
pacman-key --init
pacman-key --populate archlinux

# Hostname
echo "$NEW_HOSTNAME" > /etc/hostname

# Timezone
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

# Locale
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Users
printf '%s\n' "root:$ROOT_PASS" | chpasswd
useradd -m -G wheel -s /bin/zsh "$NEW_USER"
printf '%s:%s\n' "$NEW_USER" "$NEW_PASS" | chpasswd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# GRUB
if [[ "$IS_EFI" == "true" ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
else
    grub-install --target=i386-pc "$TARGET_DRIVE" --recheck
fi

sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"root=UUID=$ROOT_UUID rootflags=subvol=@ rw\"|" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# AUR Helper
if [[ "$AUR_HELPER" != "none" ]]; then
    pacman -S --needed --noconfirm base-devel git
    sudo -u "$NEW_USER" bash -c "
        cd /home/$NEW_USER
        case '$AUR_HELPER' in
            yay) git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin ;;
            paru) git clone https://aur.archlinux.org/paru-bin.git && cd paru-bin ;;
            pikaur) git clone https://aur.archlinux.org/pikaur.git && cd pikaur ;;
        esac
        makepkg -si --noconfirm
        cd ..
        rm -rf *build* *bin*
    "
fi

# Services
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable bluetooth 2>/dev/null || true
systemctl enable coolercontrold.service 2>/dev/null || true

# Arch-Update tray
sudo -u "$NEW_USER" arch-update --tray --enable 2>/dev/null || true

# Local repo on target (for future installs)
cp -r /repo /var/cache/anarchy-repo
cat >> /etc/pacman.conf <<REPO

[anarchy-repo]
SigLevel = Optional TrustAll
Server = file:///var/cache/anarchy-repo
REPO

# Dotfiles
DOTFILES_DIR="/home/$NEW_USER/anarchydots"
git clone https://github.com/Riezz0/anarchydots "$DOTFILES_DIR"
chown -R "$NEW_USER:users" "$DOTFILES_DIR"

# Clean before stow
rm -rf "/home/$NEW_USER/.config"
rm -rf "/home/$NEW_USER/.icons"
rm -rf "/home/$NEW_USER/.themes"
rm -rf "/home/$NEW_USER/.oh-my-zsh"
rm -rf "/home/$NEW_USER/.cache"
rm -f "/home/$NEW_USER/.zshrc"

if [ -d "/home/$NEW_USER/.local/share/themes" ]; then
    cp -a "/home/$NEW_USER/.local/share/themes" "/tmp/user_themes_backup"
fi
rm -rf "/home/$NEW_USER/.local"
if [ -d "/tmp/user_themes_backup" ]; then
    mkdir -p "/home/$NEW_USER/.local/share"
    mv "/tmp/user_themes_backup" "/home/$NEW_USER/.local/share/themes"
fi

# Stow
cd "$DOTFILES_DIR"
sudo stow -t /usr/local scripts 2>/dev/null || true
sudo -u "$NEW_USER" stow --restow \
    bg cursors fastfetch gradience gtk3 gtk4 hypr-themes hyprland \
    icons kitty kvantum neovim omz pypr pywal qt5 qt6 quickshell \
    rofi themes wal xkb zsh \
    -t "/home/$NEW_USER"

# Fonts
mkdir -p "/home/$NEW_USER/.local/share/fonts/"
cp -r "$DOTFILES_DIR/fonts/." "/home/$NEW_USER/.local/share/fonts/"
chown -R "$NEW_USER:users" "/home/$NEW_USER/.local"
fc-cache -fv

# SDDM
cp "$DOTFILES_DIR/sys/sddm/sddm.conf" /etc/
cp -r "$DOTFILES_DIR/sys/sddm/anarchy-sddm/" /usr/share/sddm/themes/
mkdir -p /var/local/sddm-wallpaper
chown "$NEW_USER:sddm" /var/local/sddm-wallpaper
chmod 775 /var/local/sddm-wallpaper

# GRUB theme
cp -r "$DOTFILES_DIR/sys/grub/grub" /etc/default/
cp -r "$DOTFILES_DIR/sys/grub/tokyo-night" /usr/share/grub/themes/
grub-mkconfig -o /boot/grub/grub.cfg

# Cleanup
rm -f /.install_env
CHEOF

# ------------------------------------------------------------
#  Cleanup
# ------------------------------------------------------------
rm -f /mnt/.install_env
umount -Rlf /mnt

echo
gum style \
    --border double \
    --align center \
    --foreground "$C_GREEN" \
    --border-foreground "$C_GREEN" \
    "Installation Complete!"

echo
info "Log in and run 'hyprmon' to configure your monitors."

if gum confirm "Do you want to reboot your system now?"; then
    reboot
fi
