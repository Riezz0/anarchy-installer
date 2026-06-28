#!/bin/bash

# --- Color Palette (Tokyo Night) ---
C_RED="#f7768e"      # color1
C_GREEN="#9ece6a"    # color2
C_YELLOW="#e0af68"   # color3
C_BLUE="#7aa2f7"     # color4
C_MAUVE="#bb9af7"    # color5
C_TEAL="#7dcfff"     # color6
C_WHITE="#c0caf5"    # color15 / special foreground
C_SUBTEXT="#a9b1d6"  # color7
C_BASE="#1a1b26"     # color0 / special background

# --- Helpers ---
header() {
    gum style \
        --foreground "$C_MAUVE" \
        --border double \
        --align center \
        --width 50 \
        --margin "1 2" \
        --padding "0 2" \
        "$1"
}

section() {
    gum style \
        --foreground "$C_BLUE" \
        --border rounded \
        --align left \
        --width 50 \
        --margin "0 1" \
        --padding "0 1" \
        "$1"
}

step() {
    gum style --foreground "$C_TEAL" --bold "  :: $1"
}

ok() {
    gum style --foreground "$C_GREEN" "  ✔ $1"
}

fail() {
    gum style --foreground "$C_RED" --bold "  ✘ $1"
}

info() {
    gum style --foreground "$C_SUBTEXT" "     $1"
}

# --- Post-Install Functions ---

configure_hyprmon() {
    echo ":: Configuring hyprmon display settings..."
    rm -f ~/.config/hypr/hyprmon.lua
    rm -f ~/.config/hypr/hyprland.lua.bak.*
    echo "     Launch hyprmon to setup display settings for this machine"
    echo "     Settings will be saved to ~/.config/hypr/hyprmon.lua"
    echo "  ✔ Hyprmon ready for configuration"
}

# --- 0. Safety Cleanup ---
umount -R /mnt &>/dev/null

# --- 1. Checks ---
if [[ $EUID -ne 0 ]]; then
    fail "Run with sudo!"
    exit 1
fi

echo
header "Anarchy Linux Install"
echo

step "Checking internet connection..."
if ! ping -c 1 8.8.8.8 &>/dev/null; then
    fail "Internet connection required."
    exit 1
fi
ok "Internet connected"
echo

# --- 2. Setup ---
TEST_MODE=false
[[ "$1" == "--test" ]] && TEST_MODE=true
IS_EFI=false
[[ -d "/sys/firmware/efi" ]] && IS_EFI=true

# --- 3. Drive Selection ---
section "Drive Selection"
echo
TARGET_DRIVE=$(lsblk -dpno NAME,SIZE | gum choose --header "Select target drive" | awk '{print $1}')
[ -z "$TARGET_DRIVE" ] && exit 1
if [[ $TARGET_DRIVE =~ [0-9]$ ]]; then P="p"; else P=""; fi
EFI_PART="${TARGET_DRIVE}${P}1"
ROOT_PART="${TARGET_DRIVE}${P}2"
ok "Selected: $TARGET_DRIVE"
echo

# --- 4. User Configuration ---
section "User Configuration"
echo

ROOT_PASS=""
while [[ -z "$ROOT_PASS" ]]; do ROOT_PASS=$(gum input --password --placeholder "Root password" --prompt " 🔑 "); done
ok "Root password set"

NEW_USER=""
while [[ -z "$NEW_USER" ]]; do NEW_USER=$(gum input --placeholder "Username" --prompt " 👤 "); done
ok "User: $NEW_USER"

NEW_PASS=""
while [[ -z "$NEW_PASS" ]]; do NEW_PASS=$(gum input --password --placeholder "User password" --prompt " 🔑 "); done
ok "User password set"

TIMEZONE=$(timedatectl list-timezones | gum filter --placeholder "Search timezone..." --prompt " 🌍 ")
[ -z "$TIMEZONE" ] && TIMEZONE="UTC"
ok "Timezone: $TIMEZONE"

NEW_HOSTNAME=""
while [[ -z "$NEW_HOSTNAME" ]]; do NEW_HOSTNAME=$(gum input --placeholder "Hostname" --prompt " 🖥️  "); done
ok "Hostname: $NEW_HOSTNAME"
echo

# --- 5. System Configuration ---
section "System Options"
echo

KERNEL=$(gum choose --header "Select Kernel" "linux" "linux-lts" "linux-zen" "linux-hardened")
ok "Kernel: $KERNEL"

CPU=$(gum choose --header "Select CPU Microcode" "intel-ucode" "amd-ucode")
ok "CPU: $CPU"

GPU_RAW=$(gum choose --no-limit --header "Select GPU Driver(s) (Space to select, Enter to confirm)" \
    "mesa" "nvidia" "nvidia-lts" "nvidia-dkms" "xf86-video-intel" "vulkan-radeon" "vulkan-intel" "none")
GPU_PKGS=$(echo "$GPU_RAW" | grep -v "^none$" | tr '\n' ' ')
ok "GPU: ${GPU_RAW:-none}"

AUDIO=$(gum choose --header "Select Audio Server" "pipewire" "pulseaudio")
if [ "$AUDIO" = "pipewire" ]; then
    AUDIO_PKGS="pipewire pipewire-pulse wireplumber"
else
    AUDIO_PKGS="pulseaudio pulseaudio-alsa pulseaudio-bluetooth"
fi
ok "Audio: $AUDIO"

AUR_HELPER=$(gum choose --header "Select AUR Helper" "yay" "paru" "pikaur" "none")
ok "AUR Helper: $AUR_HELPER"
echo

# --- 6. Summary ---
clear
header "Installation Summary"
echo
echo "  $(gum style --foreground "$C_SUBTEXT" "User:")      $(gum style --foreground "$C_WHITE" --bold "$NEW_USER")"
echo "  $(gum style --foreground "$C_SUBTEXT" "Hostname:")  $(gum style --foreground "$C_WHITE" --bold "$NEW_HOSTNAME")"
echo "  $(gum style --foreground "$C_SUBTEXT" "Timezone:")  $(gum style --foreground "$C_WHITE" "$TIMEZONE")"
echo
echo "  $(gum style --foreground "$C_SUBTEXT" "Drive:")     $(gum style --foreground "$C_YELLOW" --bold "$TARGET_DRIVE")"
echo "  $(gum style --foreground "$C_SUBTEXT" "Boot Mode:") $(gum style --foreground "$C_TEAL" "$([ "$IS_EFI" = true ] && echo "UEFI" || echo "BIOS")")"
echo
echo "  $(gum style --foreground "$C_SUBTEXT" "Kernel:")    $(gum style --foreground "$C_MAUVE" --bold "$KERNEL")"
echo "  $(gum style --foreground "$C_SUBTEXT" "AUR:")       $(gum style --foreground "$C_MAUVE" "$AUR_HELPER")"
echo
gum confirm --affirmative "Proceed" --negative "Abort" "  ⚠  This will WIPE $TARGET_DRIVE. Continue?" || exit 1
echo

set -e
# --- EXECUTION ---

# --- Step 1: Partitioning ---
step "Partitioning $TARGET_DRIVE..."
if [ "$TEST_MODE" = false ]; then
    sgdisk -Z $TARGET_DRIVE
    if [ "$IS_EFI" = true ]; then
        sgdisk -n 1:0:+512M -t 1:ef00 $TARGET_DRIVE
    else
        sgdisk -n 1:0:+1M -t 1:ef02 $TARGET_DRIVE
    fi
    sgdisk -n 2:0:0 -t 2:8300 $TARGET_DRIVE
    partprobe $TARGET_DRIVE
    sleep 2
    ok "Partitions created"
fi
echo

# --- Step 2: Formatting ---
step "Formatting partitions..."
if [ "$TEST_MODE" = false ]; then
    if [ "$IS_EFI" = true ]; then mkfs.vfat -F 32 "$EFI_PART"; fi
    mkfs.btrfs -L ARCH_ROOT -f "$ROOT_PART"
    ok "Filesystems formatted"
fi
echo

# --- Step 3: Btrfs Subvolumes ---
step "Creating Btrfs subvolumes..."
if [ "$TEST_MODE" = false ]; then
    mount "$ROOT_PART" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@log
    btrfs subvolume create /mnt/@pkg
    btrfs subvolume create /mnt/@.snapshots
    umount /mnt
    
    mount -o noatime,compress=zstd,subvol=@ "$ROOT_PART" /mnt
    mkdir -p /mnt/home /mnt/var/log /mnt/var/cache/pacman/pkg /mnt/.snapshots /mnt/boot

    mount -o noatime,compress=zstd,subvol=@home "$ROOT_PART" /mnt/home
    mount -o noatime,compress=zstd,subvol=@log "$ROOT_PART" /mnt/var/log
    mount -o noatime,compress=zstd,subvol=@pkg "$ROOT_PART" /mnt/var/cache/pacman/pkg
    mount -o noatime,compress=zstd,subvol=@.snapshots "$ROOT_PART" /mnt/.snapshots

    if [ "$IS_EFI" = true ]; then mount "$EFI_PART" /mnt/boot; fi
    ok "Subvolumes mounted"
fi
echo

# --- Step 4: Cloning System ---
step "Cloning system to target..."
if [ "$TEST_MODE" = false ]; then
    rsync -aAXhW --numeric-ids --info=progress2 \
        --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
        --exclude={"/var/cache/*","/var/log/*","/var/tmp/*"} \
        --exclude={"/usr/share/doc/*","/usr/share/man/*","/usr/share/info/*"} \
        --exclude={"/usr/lib/modules/*","/usr/lib/firmware/*"} \
        --exclude="/etc/pacman.d/gnupg/*" \
        --exclude="/root/*" \
        / /mnt/
    ok "System cloned"
fi
echo

# --- Step 5: Configuration (Chroot) ---
step "Configuring target system..."
if [ "$TEST_MODE" = false ]; then
    genfstab -U /mnt >> /mnt/etc/fstab
    cp --remove-destination /etc/resolv.conf /mnt/etc/resolv.conf

    partprobe $TARGET_DRIVE
    udevadm settle
    sleep 2
    ROOT_UUID=$(lsblk -no UUID $ROOT_PART)
    
    arch-chroot /mnt /bin/bash <<EOF
    set -e
    
    echo ":: Repairing cloned pacman database..."
    find /var/lib/pacman/local/ -type f -name "desc" -exec sed -i '/^%INSTALLED_DB%/,/^$/d' {} +

    pacman-key --init
    pacman-key --populate archlinux
    
    echo ":: Cleaning boot config..."
    pacman -Rns --noconfirm archiso 2>/dev/null || true
    rm -rf /etc/mkinitcpio.conf.d
    rm -f /etc/mkinitcpio.d/*.preset
    rm -f /boot/vmlinuz* /boot/initramfs*
    
    echo "MODULES=(btrfs)" > /etc/mkinitcpio.conf
    echo "BINARIES=()" >> /etc/mkinitcpio.conf
    echo "FILES=()" >> /etc/mkinitcpio.conf
    echo "HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)" >> /etc/mkinitcpio.conf
    
    echo ":: Removing Live User configs..."
    userdel -f -r liveuser 2>/dev/null || true
    rm -rf /etc/sddm.conf.d/*
    if [ -f /etc/sddm.conf ]; then
        sed -i '/Autologin/d' /etc/sddm.conf
        sed -i '/User=liveuser/d' /etc/sddm.conf
    fi

    rm -f /etc/sudoers.d/g_wheel
    rm -f /etc/sudoers.d/01_archiso
    
    echo ":: Installing Kernel, Drivers, and Core Packages..."
    pacman -Sy --noconfirm $KERNEL $CPU $GPU_PKGS $AUDIO_PKGS linux-firmware btrfs-progs grub $([ "$IS_EFI" = true ] && echo "efibootmgr")
    mkinitcpio -P

    echo ":: Configuring Grub..."
    if [ "$IS_EFI" = true ]; then
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
    else
        grub-install --target=i386-pc "$TARGET_DRIVE" --recheck
    fi
    
    sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"root=UUID=$ROOT_UUID rootflags=subvol=@ rw\"|" /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
    
    echo ":: Setting System Identity..."
    echo "$NEW_HOSTNAME" > /etc/hostname
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc

    echo ":: Creating Users..."
    echo "root:$ROOT_PASS" | chpasswd
    useradd -m -G wheel -s /bin/bash "$NEW_USER"
    echo "$NEW_USER:$NEW_PASS" | chpasswd
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

    if [ "$AUR_HELPER" != "none" ]; then
        echo ":: Installing AUR Helper: $AUR_HELPER"
        pacman -S --needed --noconfirm base-devel git
        
        # Build as the new user
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

    echo ":: Enabling Services..."    
    systemctl enable NetworkManager
    systemctl enable sddm

    echo ":: Cloning Dotfiles..."
    git clone https://github.com/Riezz0/anarchydots "/home/$NEW_USER/anarchydots"
    chown -R "$NEW_USER:users" "/home/$NEW_USER/anarchydots"

    echo ":: Stowing System Files..."
    cd "/home/$NEW_USER/anarchydots"

    stow_clean() {
        local pkg="$1"
        local target="${2:-/home/$NEW_USER}"
        # Dry-run stow to find conflicts, then delete the blocking real files
        stow -n -t "$target" "$pkg" 2>&1 | grep "existing target is neither" | awk '{print $NF}' | while read conflict; do
            rm -f "$target/$conflict"
        done
        stow -t "$target" "$pkg"
    }

    stow_clean scripts /usr/local
    stow_clean bg /usr/share

    echo ":: Stowing Dotfiles Packages..."
    PACKAGES=(
        cursors fastfetch gradience gtk3 gtk4 hyprland hypr-themes icons
        kitty kvantum neovim omz pypr pywal qt5 qt6 quickshell rofi
        themes wal xkb zsh
    )
    for pkg in "${PACKAGES[@]}"; do
        stow_clean "$pkg" || true
    done

    echo ":: Configuring SDDM..."
    cp -r "/home/$NEW_USER/anarchydots/sys/sddm/sddm.conf" "/etc/"
    cp -r "/home/$NEW_USER/anarchydots/sys/sddm/tokyo-night/" "/usr/share/sddm/themes/"

    echo ":: Configuring GRUB Theme..."
    cp -r "/home/$NEW_USER/anarchydots/sys/grub/grub" "/etc/default/"
    cp -r "/home/$NEW_USER/anarchydots/sys/grub/grub/tokyo-night" "/usr/share/grub/themes/"

    echo ":: Installing NCT6687D Driver..."
    git clone https://github.com/Fred78290/nct6687d "/home/$NEW_USER/mydots/nct6687d/"
    cd "/home/$NEW_USER/mydots/nct6687d/" && make dkms/install
    cp "/home/$NEW_USER/anarchydots/sys/no_nct6683.conf" /etc/modprobe.d/
    cp "/home/$NEW_USER/anarchydots/sys/nct6687.conf" /etc/modules-load.d/nct6687.conf

    echo ":: Enabling Additional Services..."
    modprobe nct6687
    grub-mkconfig -o /boot/grub/grub.cfg
    systemctl enable --now bluetooth
    systemctl enable --now coolercontrold.service
    chsh -s "$(which zsh)"
EOF
    umount -R /mnt
    ok "Configuration complete"
fi

echo
header "Installation Complete!"
echo

configure_hyprmon

if gum confirm "Do you want to reboot your system now?"; then
    reboot
fi
