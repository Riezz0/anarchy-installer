#!/bin/bash

# --- Colors ---
RED="#f38ba8"
GREEN="#a6e3a1"
YELLOW="#f9e2af"
BLUE="#89b4fa"
MAUVE="#cba6f7"
TEAL="#94e2d5"
PEACH="#fab387"
OVERLAY1="#6c7086"
SURFACE2="#585b70"
TEXT="#cdd6f4"
BASE="#1e1e2e"
MANTLE="#181825"
CRUST="#11111b"

# --- Helpers ---
info()    { gum style --foreground "$BLUE" " :: $1"; }
success() { gum style --foreground "$GREEN" " :: $1"; }
warn()    { gum style --foreground "$YELLOW" " :: $1"; }
error()   { gum style --foreground "$RED" --bold " ✗ $1"; }
step()    { gum style --foreground "$MAUVE" --bold "── $1 ──"; }

header() {
    gum style \
        --foreground "$MAUVE" \
        --border double \
        --align center \
        --width 56 \
        --padding "0 2" \
        "$1"
}

banner() {
    echo
    figlet -f smslant "$1"
    echo
}

# --- 0. Safety Cleanup ---
umount -R /mnt &>/dev/null

# --- 1. Checks ---
if [[ $EUID -ne 0 ]]; then
    error "Run with sudo!"
    exit 1
fi

info "Checking internet connection..."
if ! ping -c 1 8.8.8.8 &>/dev/null; then
    error "Internet connection required."
    exit 1
fi
success "Internet connection verified."

banner "ML4W OS Install"

gum style \
    --foreground "$TEXT" \
    --align center \
    --width 56 \
    "This script will install ML4W OS" \
    "to your hard drive."
echo

# --- 2. Setup ---
TEST_MODE=false
[[ "$1" == "--test" ]] && TEST_MODE=true
IS_EFI=false
[[ -d "/sys/firmware/efi" ]] && IS_EFI=true

if [ "$TEST_MODE" = true ]; then
    warn "Running in TEST MODE — disk operations will be skipped."
    echo
fi

# 3. Drive Selection
step "Drive Selection"
TARGET_DRIVE=$(lsblk -dpno NAME,SIZE | gum choose --header "Select target drive" | awk '{print $1}')
[ -z "$TARGET_DRIVE" ] && exit 1
if [[ $TARGET_DRIVE =~ [0-9]$ ]]; then P="p"; else P=""; fi
EFI_PART="${TARGET_DRIVE}${P}1"
ROOT_PART="${TARGET_DRIVE}${P}2"

# 4. Input Validation
step "System Configuration"
ROOT_PASS=""
while [[ -z "$ROOT_PASS" ]]; do ROOT_PASS=$(gum input --password --placeholder "Root Password"); done
NEW_USER=""
while [[ -z "$NEW_USER" ]]; do NEW_USER=$(gum input --placeholder "Username"); done
NEW_PASS=""
while [[ -z "$NEW_PASS" ]]; do NEW_PASS=$(gum input --password --placeholder "User Password"); done
TIMEZONE=$(timedatectl list-timezones | gum filter --placeholder "Select Timezone")
[ -z "$TIMEZONE" ] && TIMEZONE="UTC"
NEW_HOSTNAME=""
while [[ -z "$NEW_HOSTNAME" ]]; do NEW_HOSTNAME=$(gum input --placeholder "Hostname"); done

# 5. Hardware Selection
step "Hardware Selection"

# Kernel
KERNEL=$(gum choose \
    --header "Select kernel" \
    --selected "linux" \
    "linux" "linux-lts" "linux-zen" "linux-hardened")

# CPU Microcode
CPU_MICROCODE=$(gum choose \
    --header "Select CPU microcode" \
    --selected "amd-ucode" \
    "amd-ucode" "intel-ucode")

# GPU Drivers (multi-select)
mapfile -t GPU_DRIVERS < <(gum choose \
    --header "Select GPU driver(s) (space to select, enter to confirm)" \
    --no-limit \
    "mesa (open-source)" \
    "nvidia (proprietary)" \
    "nvidia-open (open-source NVIDIA)" \
    "xf86-video-amdgpu" \
    "xf86-video-intel" \
    "xf86-video-nouveau" \
    "virtualbox-guest-utils" \
    "open-vm-tools")

# Map display names to package names
GPU_PKGS=""
for gpu in "${GPU_DRIVERS[@]}"; do
    case "$gpu" in
        "mesa (open-source)")          GPU_PKGS+=" mesa " ;;
        "nvidia (proprietary)")        GPU_PKGS+=" nvidia nvidia-utils " ;;
        "nvidia-open (open-source NVIDIA)") GPU_PKGS+=" nvidia-open nvidia-utils " ;;
        "xf86-video-amdgpu")           GPU_PKGS+=" xf86-video-amdgpu " ;;
        "xf86-video-intel")            GPU_PKGS+=" xf86-video-intel " ;;
        "xf86-video-nouveau")          GPU_PKGS+=" xf86-video-nouveau " ;;
        "virtualbox-guest-utils")      GPU_PKGS+=" virtualbox-guest-utils " ;;
        "open-vm-tools")               GPU_PKGS+=" open-vm-tools " ;;
    esac
done
GPU_PKGS=$(echo "$GPU_PKGS" | xargs)  # trim whitespace

if [ ${#GPU_DRIVERS[@]} -eq 0 ]; then
    GPU_DISPLAY="none"
else
    GPU_DISPLAY="${GPU_DRIVERS[*]}"
fi

# 6. Summary
clear
banner "Summary"

gum style \
    --border double \
    --align left \
    --width 56 \
    --padding "1 2" \
    --margin "0 2" \
    "$(gum style --foreground "$GREEN"  "  User:       $NEW_USER")
$(gum style --foreground "$BLUE"   "  Timezone:   $TIMEZONE")
$(gum style --foreground "$MAUVE"  "  Hostname:   $NEW_HOSTNAME")
$(gum style --foreground "$PEACH"  "  Drive:      $TARGET_DRIVE")
$(gum style --foreground "$YELLOW" "  Partition:  $ROOT_PART")
$(gum style --foreground "$TEAL"   "  Boot Mode:  $([ "$IS_EFI" = true ] && echo "UEFI" || echo "BIOS")")
$(gum style --foreground "$RED"    "  Kernel:     $KERNEL")
$(gum style --foreground "$BLUE"   "  CPU:        $CPU_MICROCODE")
$(gum style --foreground "$MAUVE"  "  GPU:        $GPU_DISPLAY")"

echo
gum confirm --affirmative "Proceed" --negative "Abort" \
    "$(gum style --foreground "$RED" --bold "WARNING: This will ERASE $TARGET_DRIVE. Continue?")" || exit 1

set -e

# --- Execution Banner ---
banner "Installing"

# --- Step 1: Partitioning ---
step "1/6  Partitioning $TARGET_DRIVE"
if [ "$TEST_MODE" = false ]; then
    gum spin --spinner dot --title "Wiping disk..." -- sgdisk -Z $TARGET_DRIVE
    if [ "$IS_EFI" = true ]; then
        gum spin --spinner dot --title "Creating EFI partition..." -- \
            sgdisk -n 1:0:+512M -t 1:ef00 $TARGET_DRIVE
    else
        gum spin --spinner dot --title "Creating BIOS partition..." -- \
            sgdisk -n 1:0:+1M -t 1:ef02 $TARGET_DRIVE
    fi
    gum spin --spinner dot --title "Creating root partition..." -- \
        sgdisk -n 2:0:0 -t 2:8300 $TARGET_DRIVE
    gum spin --spinner dot --title "Probing partitions..." -- partprobe $TARGET_DRIVE
    sleep 1
    success "Disk partitioned."
fi
echo

# --- Step 2: Formatting ---
step "2/6  Formatting"
if [ "$TEST_MODE" = false ]; then
    if [ "$IS_EFI" = true ]; then
        gum spin --spinner dot --title "Formatting EFI (FAT32)..." -- mkfs.vfat -F 32 "$EFI_PART"
    fi
    gum spin --spinner dot --title "Formatting root (Btrfs)..." -- mkfs.btrfs -L ARCH_ROOT -f "$ROOT_PART"
    success "Filesystems created."
fi
echo

# --- Step 3: Btrfs Subvolumes ---
step "3/6  Btrfs Subvolumes"
if [ "$TEST_MODE" = false ]; then
    info "Mounting root temporarily..."
    mount "$ROOT_PART" /mnt

    gum spin --spinner dot --title "Creating subvolumes..." -- bash -c '
        btrfs subvolume create /mnt/@
        btrfs subvolume create /mnt/@home
        btrfs subvolume create /mnt/@log
        btrfs subvolume create /mnt/@pkg
        btrfs subvolume create /mnt/@.snapshots
    '

    info "Remounting with correct options..."
    umount /mnt
    mount -o noatime,compress=zstd,subvol=@ "$ROOT_PART" /mnt

    info "Creating directory structure..."
    mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot}

    info "Mounting subvolumes..."
    mount -o noatime,compress=zstd,subvol=@home "$ROOT_PART" /mnt/home
    mount -o noatime,compress=zstd,subvol=@log "$ROOT_PART" /mnt/var/log
    mount -o noatime,compress=zstd,subvol=@pkg "$ROOT_PART" /mnt/var/cache/pacman/pkg
    mount -o noatime,compress=zstd,subvol=@.snapshots "$ROOT_PART" /mnt/.snapshots

    if [ "$IS_EFI" = true ]; then
        info "Mounting EFI partition..."
        mount "$EFI_PART" /mnt/boot
    fi
    success "Subvolumes configured."
fi
echo

# --- Step 4: Cloning System ---
step "4/6  Cloning System"
if [ "$TEST_MODE" = false ]; then
    rsync -aAXhW --numeric-ids --info=progress2 \
        --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
        --exclude="/var/cache/pacman/pkg/*" \
        --exclude="/var/log/*" \
        --exclude="/etc/pacman.d/gnupg/*" \
        / /mnt/
    success "System cloned to target."
fi
echo

# --- Step 5: Local Repository Setup ---
step "5/6  Local Repository"
if [ "$TEST_MODE" = false ]; then
    LOCAL_REPO_SRC="/root/local-repo/x86_64"
    LOCAL_REPO_DST="/mnt/root/local-repo/x86_64"

    if [ -d "$LOCAL_REPO_SRC" ]; then
        info "Copying local repo packages to target..."
        mkdir -p "$LOCAL_REPO_DST"
        cp "$LOCAL_REPO_SRC"/*.pkg.tar.zst "$LOCAL_REPO_DST/"

        gum spin --spinner dot --title "Generating repo database..." -- \
            bash -c "cd '$LOCAL_REPO_DST' && repo-add local-repo.db.tar.gz *.pkg.tar.zst && rm -f local-repo.db local-repo.files && mv local-repo.db.tar.gz local-repo.db && mv local-repo.files.tar.gz local-repo.files"
        success "Local repository ready."
    else
        warn "Local repo not found at $LOCAL_REPO_SRC — skipping."
    fi
fi
echo

# --- Step 7: Configuration (Chroot) ---
step "6/6  System Configuration"
if [ "$TEST_MODE" = false ]; then
    genfstab -U /mnt >> /mnt/etc/fstab
    cp --remove-destination /etc/resolv.conf /mnt/etc/resolv.conf

    info "Resolving root UUID..."
    partprobe $TARGET_DRIVE
    udevadm settle
    sleep 2
    ROOT_UUID=$(lsblk -no UUID $ROOT_PART)
    if [ -z "$ROOT_UUID" ]; then sleep 3; ROOT_UUID=$(blkid -s UUID -o value $ROOT_PART); fi
    if [ -z "$ROOT_UUID" ]; then error "No UUID found for $ROOT_PART"; exit 1; fi
    success "UUID resolved: $ROOT_UUID"

    info "Entering chroot to configure system..."
    arch-chroot /mnt /bin/bash <<EOF
    set -e
    pacman-key --init
    pacman-key --populate archlinux

    echo ":: Cleaning boot config..."
    pacman -Rns --noconfirm archiso || true
    rm -rf /etc/mkinitcpio.conf.d
    rm -f /etc/mkinitcpio.d/*.preset
    rm -f /boot/vmlinuz* /boot/initramfs*

    echo "MODULES=(btrfs)" > /etc/mkinitcpio.conf
    echo "BINARIES=()" >> /etc/mkinitcpio.conf
    echo "FILES=()" >> /etc/mkinitcpio.conf
    echo "HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)" >> /etc/mkinitcpio.conf

    echo ":: Removing live user and autologin configs..."
    userdel -f -r liveuser || true
    rm -rf /etc/sddm.conf.d/*
    if [ -f /etc/sddm.conf ]; then
        sed -i '/Autologin/d' /etc/sddm.conf
        sed -i '/User=liveuser/d' /etc/sddm.conf
    fi
    rm -f /etc/sudoers.d/g_wheel
    rm -f /etc/sudoers.d/01_archiso

    echo ":: Adding local repository..."
    sed -i '/\[local-repo\]/,/Server = .*/d' /etc/pacman.conf
    cat >> /etc/pacman.conf <<REPO

[local-repo]
SigLevel = Optional TrustAll
Server = file:///root/local-repo/x86_64
REPO

    echo ":: Installing Linux kernel, firmware, and drivers..."
    pacman -Sy --noconfirm \
        "$KERNEL" \
        linux-firmware \
        "$CPU_MICROCODE" \
        btrfs-progs \
        grub \
        $GPU_PKGS \
        $([ "$IS_EFI" = true ] && echo "efibootmgr")
    mkinitcpio -P

    echo ":: Installing system packages..."
    pacman -S --noconfirm --needed \
        hypridle hyprlock pyprland nwg-displays nwg-look \
        kitty rofi xfce-polkit swaync awww gradience-git \
        ttf-font-awesome \
        pipewire-audio pipewire-pulse wireplumber vlc \
        blueman bluez bluez-utils \
        qt5-graphicaleffects qt5-imageformats qt5-multimedia \
        qt5-quickcontrols qt5-quickcontrols2 qt5-styleplugins qt5-svg \
        qt6 qt6-base qt6-declarative qt6-imageformats qt6-multimedia qt6-svg \
        eza neovim oh-my-zsh-git \
        zsh-autocomplete zsh-autosuggestions zsh-autoswitch-virtualenv-git \
        zsh-fast-syntax-highlighting zsh-syntax-highlighting \
        plymouth goverlay-git vkbasalt python-pywal16

    echo ":: Installing GRUB..."
    if [ "$IS_EFI" = true ]; then
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
    else
        grub-install --target=i386-pc "$TARGET_DRIVE" --recheck
    fi
    sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"root=UUID=$ROOT_UUID rootflags=subvol=@ rw\"|" /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg

    echo "Setting hostname to $NEW_HOSTNAME..."
    echo "$NEW_HOSTNAME" > /etc/hostname

    echo "Setting timezone to $TIMEZONE..."
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc

    echo "Setting root password..."
    echo "root:$ROOT_PASS" | chpasswd

    echo "Creating user '$NEW_USER'..."
    useradd -m -G wheel -s /bin/bash "$NEW_USER"
    echo "$NEW_USER:$NEW_PASS" | chpasswd
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

    echo "Enabling services..."
    systemctl enable NetworkManager
    systemctl enable sddm
EOF
    umount -R /mnt
    success "System configured."
fi

# --- Completion ---
banner "Done!"
gum style \
    --foreground "$GREEN" \
    --align center \
    --width 56 \
    "Installation complete!" \
    "Reboot and enjoy ML4W OS."
echo

if gum confirm --affirmative "Reboot" --negative "Stay" "Reboot now?"; then
    gum style --foreground "$YELLOW" --bold " :: Rebooting in 3 seconds..."
    sleep 3
    reboot
fi
