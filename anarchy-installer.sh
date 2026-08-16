#!/bin/bash

# --- Tokyo Night UI ---
BG="#1a1b26"
FG="#c0caf5"
MUTED="#565f89"
BLUE="#7aa2f7"
CYAN="#7dcfff"
GREEN="#9ece6a"
YELLOW="#e0af68"
RED="#f7768e"
PURPLE="#bb9af7"

if [[ $EUID -ne 0 ]]; then
    printf '✖ Run this installer with sudo.\n' >&2
    exit 1
fi

if ! command -v gum &>/dev/null; then
    printf '✖ Gum is required for the installer UI. Install gum and try again.\n' >&2
    exit 1
fi

gum style --foreground "$FG" --background "$BG" "Tokyo Night UI enabled"

banner() {
    gum style --foreground "$PURPLE" --border double --border-foreground "$BLUE" --padding "0 2" --bold "$1"
}

info() {
    gum style --foreground "$CYAN" "  ◆ $*"
}

step() {
    gum style --foreground "$BLUE" --bold "  ➜ $*"
}

success() {
    gum style --foreground "$GREEN" "  ✓ $*"
}

warning() {
    gum style --foreground "$YELLOW" "  ⚠ $*"
}

error() {
    gum style --foreground "$RED" --bold "  ✖ $*"
}

# --- 0. Safety Cleanup ---
umount -R /mnt &>/dev/null

# --- 1. Checks ---
info "Checking internet..."
if ! ping -c 1 8.8.8.8 &>/dev/null; then
   error "Internet access is required."
   exit 1
fi
success "Internet connection available."

banner "$(figlet -f smslant 'Anarchy Arch Linux')"
gum style --foreground "$FG" --align center --width 70 \
    "This script will install Anarchy Arch Linux to your hard drive."
gum style --foreground "$MUTED" --align center --width 70 "◆ Tokyo Night installer ◆"

# --- 2. Setup ---
TEST_MODE=false
[[ "$1" == "--test" ]] && TEST_MODE=true
IS_EFI=false
[[ -d "/sys/firmware/efi" ]] && IS_EFI=true

# 3. Drive Selection
TARGET_DRIVE=$(lsblk -dpno NAME,SIZE | gum choose \
    --header "◆ Select the target drive" --header.foreground "$BLUE" \
    --cursor "➜ " --cursor.foreground "$PURPLE")
[ -z "$TARGET_DRIVE" ] && exit 1
TARGET_DRIVE=$(awk '{print $1}' <<< "$TARGET_DRIVE")
if [[ $TARGET_DRIVE =~ [0-9]$ ]]; then P="p"; else P=""; fi
EFI_PART="${TARGET_DRIVE}${P}1"
ROOT_PART="${TARGET_DRIVE}${P}2"

# 4. Input Validation
ROOT_PASS=""
while [[ -z "$ROOT_PASS" ]]; do
    ROOT_PASS=$(gum input --password --prompt "◆ " --prompt.foreground "$BLUE" --placeholder "Root password")
done
NEW_USER=""
while [[ -z "$NEW_USER" ]]; do
    NEW_USER=$(gum input --prompt "◆ " --prompt.foreground "$BLUE" --placeholder "Username")
done
NEW_PASS=""
while [[ -z "$NEW_PASS" ]]; do
    NEW_PASS=$(gum input --password --prompt "◆ " --prompt.foreground "$BLUE" --placeholder "User password")
done
TIMEZONE=$(timedatectl list-timezones | gum filter --placeholder "◆ Select timezone" --indicator "➜ " --indicator.foreground "$PURPLE")
[ -z "$TIMEZONE" ] && TIMEZONE="UTC"
NEW_HOSTNAME=""
while [[ -z "$NEW_HOSTNAME" ]]; do
    NEW_HOSTNAME=$(gum input --prompt "◆ " --prompt.foreground "$BLUE" --placeholder "Hostname")
done

AUDIO_CHOICE=$(gum choose \
    --header "◆ Select audio server" --header.foreground "$BLUE" \
    --cursor "➜ " --cursor.foreground "$PURPLE" \
    "PipeWire (recommended)" "PulseAudio")
case "$AUDIO_CHOICE" in
    "PipeWire"*) AUDIO_PACKAGES="pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber"; AUDIO_NAME="PipeWire" ;;
    "PulseAudio"*) AUDIO_PACKAGES="pulseaudio pulseaudio-alsa"; AUDIO_NAME="PulseAudio" ;;
    *) exit 1 ;;
esac

MICROCODE_CHOICE=$(gum choose \
    --header "◆ Select CPU microcode" --header.foreground "$BLUE" \
    --cursor "➜ " --cursor.foreground "$PURPLE" \
    "Intel microcode" "AMD microcode")
case "$MICROCODE_CHOICE" in
    "Intel"*) MICROCODE_PACKAGE="intel-ucode"; MICROCODE_NAME="Intel" ;;
    "AMD"*) MICROCODE_PACKAGE="amd-ucode"; MICROCODE_NAME="AMD" ;;
    *) exit 1 ;;
esac

GPU_CHOICE=$(gum choose \
    --header "◆ Select GPU driver" --header.foreground "$BLUE" \
    --cursor "➜ " --cursor.foreground "$PURPLE" \
    "NVIDIA" "AMD")
case "$GPU_CHOICE" in
    "NVIDIA") GPU_PACKAGES="nvidia nvidia-utils lib32-nvidia-utils"; GPU_NAME="NVIDIA" ;;
    "AMD") GPU_PACKAGES="mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon xf86-video-amdgpu"; GPU_NAME="AMD" ;;
    *) exit 1 ;;
esac

KERNEL_CHOICE=$(gum choose \
    --header "◆ Select Linux kernel" --header.foreground "$BLUE" \
    --cursor "➜ " --cursor.foreground "$PURPLE" \
    "linux (standard)" "linux-lts (long-term support)" \
    "linux-zen (performance)" "linux-hardened (security)")
case "$KERNEL_CHOICE" in
    "linux (standard)") KERNEL_PACKAGE="linux"; KERNEL_NAME="linux" ;;
    "linux-lts"*) KERNEL_PACKAGE="linux-lts"; KERNEL_NAME="linux-lts" ;;
    "linux-zen"*) KERNEL_PACKAGE="linux-zen"; KERNEL_NAME="linux-zen" ;;
    "linux-hardened"*) KERNEL_PACKAGE="linux-hardened"; KERNEL_NAME="linux-hardened" ;;
    *) exit 1 ;;
esac

AUR_HELPER=$(gum choose \
    --header "◆ Select AUR helper" --header.foreground "$BLUE" \
    --cursor "➜ " --cursor.foreground "$PURPLE" \
    "yay (recommended)" "paru" "pikaur")
case "$AUR_HELPER" in
    "yay"*) AUR_HELPER="yay" ;;
    "paru"*) AUR_HELPER="paru" ;;
    "pikaur"*) AUR_HELPER="pikaur" ;;
    *) exit 1 ;;
esac

DOTFILES="/home/$NEW_USER/anarchydots"

# 5. Summary
clear
banner "$(figlet -f smslant 'Summary')"
SUMMARY=$(printf '◆ User:      %s\n◆ Timezone:  %s\n◆ Hostname:  %s\n◆ Drive:     %s\n◆ Partition: %s\n◆ Boot Mode: %s' \
    "$NEW_USER" "$TIMEZONE" "$NEW_HOSTNAME" "$TARGET_DRIVE" "$ROOT_PART" \
    "$([ "$IS_EFI" = true ] && echo "UEFI" || echo "BIOS")")
SUMMARY=$(printf '%s\n◆ Audio:     %s\n◆ Microcode: %s\n◆ GPU:       %s' \
    "$SUMMARY" "$AUDIO_NAME" "$MICROCODE_NAME" "$GPU_NAME")
SUMMARY=$(printf '%s\n◆ Kernel:    %s\n◆ AUR:       %s' "$SUMMARY" "$KERNEL_NAME" "$AUR_HELPER")
gum style --foreground "$FG" --border rounded --border-foreground "$PURPLE" --padding "1 2" \
    "$SUMMARY"
gum confirm --affirmative "Wipe drive" --negative "Cancel" \
    --prompt.foreground "$YELLOW" "⚠ This will wipe $TARGET_DRIVE. Continue?" || exit 1

set -e 
# --- EXECUTION ---

step "Step 1/5: Partitioning..."
if [ "$TEST_MODE" = false ]; then
    sgdisk -Z $TARGET_DRIVE
    if [ "$IS_EFI" = true ]; then
        sgdisk -n 1:0:+512M -t 1:ef00 $TARGET_DRIVE
    else
        # BIOS FIX: Use relative alignment to prevent sector 34 error
        sgdisk -n 1:0:+1M -t 1:ef02 $TARGET_DRIVE
    fi
    sgdisk -n 2:0:0 -t 2:8300 $TARGET_DRIVE
    partprobe $TARGET_DRIVE
    sleep 2
fi

step "Step 2/5: Formatting..."
if [ "$TEST_MODE" = false ]; then
    if [ "$IS_EFI" = true ]; then mkfs.vfat -F 32 "$EFI_PART"; fi
    mkfs.btrfs -L ARCH_ROOT -f "$ROOT_PART"
fi

step "Step 3/5: Btrfs subvolumes..."
if [ "$TEST_MODE" = false ]; then

    info "Mounting root temporarily to create subvolumes..."
    mount "$ROOT_PART" /mnt
    
    info "Creating subvolumes..."
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@log
    btrfs subvolume create /mnt/@pkg
    btrfs subvolume create /mnt/@.snapshots

    info "Unmounting to remount with correct options..."
    umount /mnt
    
    info "Mounting root..."
    mount -o noatime,compress=zstd,subvol=@ "$ROOT_PART" /mnt

    info "Creating directories..."
    mkdir -p /mnt/home
    mkdir -p /mnt/var/log
    mkdir -p /mnt/var/cache/pacman/pkg
    mkdir -p /mnt/.snapshots
    mkdir -p /mnt/boot

    info "Mounting subvolumes..."
    mount -o noatime,compress=zstd,subvol=@home "$ROOT_PART" /mnt/home
    mount -o noatime,compress=zstd,subvol=@log "$ROOT_PART" /mnt/var/log
    mount -o noatime,compress=zstd,subvol=@pkg "$ROOT_PART" /mnt/var/cache/pacman/pkg
    mount -o noatime,compress=zstd,subvol=@.snapshots "$ROOT_PART" /mnt/.snapshots

    if [ "$IS_EFI" = true ]; then 
        info "Mounting EFI..."
        mount "$EFI_PART" /mnt/boot; 
    fi
fi

step "Step 4/5: Cloning system..."
if [ "$TEST_MODE" = false ]; then
    rsync -aAXhW --numeric-ids --info=progress2 \
        --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/home/*","/root/.cache/*","/var/tmp/*","/boot/*","/usr/lib/modules/*","/var/lib/pacman/sync/*","/usr/share/doc/*","/usr/share/man/*","/usr/share/info/*"} \
        --exclude="/var/cache/pacman/pkg/*" \
        --exclude="/var/log/*" \
        --exclude="/etc/pacman.d/gnupg/*" \
        / /mnt/
fi

step "Step 5/5: Configuration (chroot)..."
if [ "$TEST_MODE" = false ]; then
    genfstab -U /mnt >> /mnt/etc/fstab
    cp --remove-destination /etc/resolv.conf /mnt/etc/resolv.conf

    info "Waiting for UUID..."
    partprobe $TARGET_DRIVE
    udevadm settle
    sleep 2
    ROOT_UUID=$(lsblk -no UUID $ROOT_PART)
    if [ -z "$ROOT_UUID" ]; then sleep 3; ROOT_UUID=$(blkid -s UUID -o value $ROOT_PART); fi
    if [ -z "$ROOT_UUID" ]; then error "No UUID found."; exit 1; fi

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
    
    echo ":: Removing Live User and Autologin configs..."
    userdel -f -r liveuser || true
    rm -rf /etc/sddm.conf.d/*
    if [ -f /etc/sddm.conf ]; then
        sed -i '/Autologin/d' /etc/sddm.conf
        sed -i '/User=liveuser/d' /etc/sddm.conf
    fi

    rm -f /etc/sudoers.d/g_wheel
    rm -f /etc/sudoers.d/01_archiso
    
    echo ":: Installing Linux Packages..."
    pacman -Sy --noconfirm "$KERNEL_PACKAGE" "${KERNEL_PACKAGE}-headers" linux-firmware btrfs-progs grub sddm \
        git stow zsh dkms base-devel sudo \
        "$MICROCODE_PACKAGE" $AUDIO_PACKAGES $GPU_PACKAGES \
        $([ "$IS_EFI" = true ] && echo "efibootmgr")
    mkinitcpio -P

    echo ":: Installing Grub..."
    if [ "$IS_EFI" = true ]; then
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
    else
        grub-install --target=i386-pc "$TARGET_DRIVE" --recheck
    fi

    echo "Adding new user '$NEW_USER'..."
    useradd -m -G wheel -s /bin/bash "$NEW_USER"
    echo "$NEW_USER:$NEW_PASS" | chpasswd
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    
    git clone https://github.com/Riezz0/anarchydots "/home/$NEW_USER/anarchydots"
    chown -R "$NEW_USER:users" "/home/$NEW_USER/anarchydots"

    echo ":: Installing AUR helper ($AUR_HELPER)..."
    sudo -u "$NEW_USER" bash -c "
        cd /tmp
        git clone \"https://aur.archlinux.org/${AUR_HELPER}.git\"
        cd ${AUR_HELPER}
        makepkg -si --noconfirm
    "
    rm -rf "/tmp/$AUR_HELPER"

    echo ":: Installing GRUB Tokyo Night theme..."
    rm -f /etc/default/grub
    cp "$DOTFILES/sys/grub/grub" /etc/default/grub
    mkdir -p /usr/share/grub/themes
    cp -r "$DOTFILES/sys/grub/tokyo-night" /usr/share/grub/themes/
    sed -i "s|^GRUB_TOP_LEVEL=.*|GRUB_TOP_LEVEL='/boot/vmlinuz-$KERNEL_PACKAGE'|" /etc/default/grub
    sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"root=UUID=$ROOT_UUID rootflags=subvol=@ rw\"|" /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
    
    echo "Setting Hostname..."
    echo "$NEW_HOSTNAME" > /etc/hostname

    echo "Setting Timezone to $TIMEZONE..."
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc

    echo "Setting password for root..."
    echo "root:$ROOT_PASS" | chpasswd

    echo ":: Installing SDDM Tokyo Night theme..."
    rm -f /etc/sddm.conf
    cp -r "$DOTFILES/sys/sddm/anarchy-sddm" /usr/share/sddm/themes/
    cp "$DOTFILES/sys/sddm/sddm.conf" /etc/sddm.conf
    sudo mkdir -p /var/local/sddm-wallpaper
    sudo chown "$NEW_USER:sddm" /var/local/sddm-wallpaper
    sudo chmod 775 /var/local/sddm-wallpaper
    cp -r "$DOTFILES/sys/sddm/initial-setup/"* /var/local/sddm-wallpaper/
    sudo chown -R "$NEW_USER:sddm" /var/local/sddm-wallpaper
    sudo chmod -R u+rwX,g+rwX,o+rX /var/local/sddm-wallpaper
    chown -R "$NEW_USER:$NEW_USER" /usr/share/icons/default

    echo ":: Stowing Dotfiles Packages..."
    rm -rf "/home/$NEW_USER/.config"
    rm -rf "/home/$NEW_USER/.icons"
    rm -rf "/home/$NEW_USER/.themes"
    if [ -d "/home/$NEW_USER/.local/share/themes" ]; then
        cp -a "/home/$NEW_USER/.local/share/themes" /tmp/user_themes_backup
    fi
    rm -rf "/home/$NEW_USER/.local"
    if [ -d /tmp/user_themes_backup ]; then
        mkdir -p "/home/$NEW_USER/.local/share"
        mv /tmp/user_themes_backup "/home/$NEW_USER/.local/share/themes"
        chown -R "$NEW_USER:users" "/home/$NEW_USER/.local"
    fi
    rm -rf "/home/$NEW_USER/.oh-my-zsh"
    rm -rf "/home/$NEW_USER/.cache"
    rm -f "/home/$NEW_USER/.zshrc"
    cd "/home/$NEW_USER/anarchydots"
    rm -rf /usr/local/bin
    sudo mkdir -p /usr/local/
    sudo stow -t /usr/local scripts
    ls -la /usr/local/bin/ | head -5
    echo " ✓ Scripts stowed"
    sudo -u "$NEW_USER" stow --restow bg cursors fastfetch gradience gtk3 gtk4 hypr-themes hyprland icons kitty kvantum neovim omz pywal qt5 qt6 quickshell rofi themes wal xkb zsh -t "/home/$NEW_USER"
    sudo cp -r "/home/$NEW_USER/anarchydots/cursors/.local/share/icons/"* /usr/share/icons/

    echo ":: Configuring Nautilus terminal integration..."
    if command -v gsettings >/dev/null 2>&1 && command -v dbus-run-session >/dev/null 2>&1 \
        && gsettings list-schemas | grep -qx 'com.github.stunkymonkey.nautilus-open-any-terminal'; then
        su - "$NEW_USER" -c "nautilus -q" || true
        su - "$NEW_USER" -c "dbus-run-session -- gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty"
        su - "$NEW_USER" -c "dbus-run-session -- gsettings set com.github.stunkymonkey.nautilus-open-any-terminal keybindings '<Ctrl><Alt>t'"
        su - "$NEW_USER" -c "dbus-run-session -- gsettings set com.github.stunkymonkey.nautilus-open-any-terminal new-tab true"
        su - "$NEW_USER" -c "dbus-run-session -- gsettings set com.github.stunkymonkey.nautilus-open-any-terminal flatpak system"
    else
        echo "WARNING: Nautilus terminal integration is not installed; skipping GSettings setup."
    fi

    echo ":: Installing fonts..."
    install -d -o "$NEW_USER" -g "$NEW_USER" "/home/$NEW_USER/.local/share/fonts"
    cp -r "$DOTFILES/fonts/." "/home/$NEW_USER/.local/share/fonts/"

    echo ":: Installing NCT6687 hardware monitor support..."
    cp "$DOTFILES/sys/no_nct6683.conf" /etc/modprobe.d/no_nct6683.conf
    cp "$DOTFILES/sys/nct6687.conf" /etc/modules-load.d/nct6687.conf
    su - "$NEW_USER" -c "git clone https://github.com/Fred78290/nct6687d '$DOTFILES/nct6687d'"
    cd "$DOTFILES/nct6687d"
    TARGET_KERNEL_VERSION=""
    for kernel_dir in /usr/lib/modules/*; do
        if [ -d "\$kernel_dir/build" ]; then
            TARGET_KERNEL_VERSION="\${kernel_dir##*/}"
            break
        fi
    done
    if [ -z "\$TARGET_KERNEL_VERSION" ]; then
        echo "ERROR: Target kernel headers were not found."
        exit 1
    fi
    rm -rf dkms
    mkdir -p dkms
    cp dkms.conf Kbuild Makefile nct6687.c dkms/
    rm -rf /usr/src/nct6687d-1
    cp -rT dkms /usr/src/nct6687d-1
    DKMS_LOG="/var/lib/dkms/nct6687d/1/build/make.log"
    if ! dkms install nct6687d/1 -k "\$TARGET_KERNEL_VERSION"; then
        echo "ERROR: NCT6687D failed to build for kernel \$TARGET_KERNEL_VERSION."
        if [ -f "\$DKMS_LOG" ]; then
            echo "--- DKMS compiler log ---"
            cat "\$DKMS_LOG"
            echo "--- End DKMS compiler log ---"
        fi
        exit 1
    fi

    echo ":: Setting Zsh and Oh My Zsh as the login shell..."
    chsh -s /bin/zsh "$NEW_USER"

    echo "Enabling NetworkManager..."    
    systemctl enable NetworkManager

    echo "Enabling sddm..."    
    systemctl enable sddm

    if systemctl list-unit-files coolercontrold.service >/dev/null 2>&1; then
        echo "Enabling CoolerControl daemon..."
        sudo systemctl enable --now coolercontrold.service || true
    fi
EOF
    umount -R /mnt
fi

banner "$(figlet -f smslant 'Done!')"
success "Installation complete. Reboot and enjoy Anarchy Arch Linux!"
if gum confirm --affirmative "Reboot" --negative "Exit" \
    --prompt.foreground "$GREEN" "Reboot your system now?"; then
    reboot
fi
