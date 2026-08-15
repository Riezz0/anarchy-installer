#!/bin/bash

# Trap errors so the window doesn't just close
trap 'echo "ERROR on line $LINENO: $BASH_COMMAND"; read -p "Press Enter to exit..."' ERR

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

# --- 0. Safety Cleanup ---
umount -R /mnt &>/dev/null || true

# --- Helper: Check if we're running from a disk ---
get_boot_disk() {
    local root_dev
    root_dev=$(findmnt -n -o SOURCE / 2>/dev/null | head -1)
    if [ -n "$root_dev" ]; then
        lsblk -rno PKNAME "$root_dev" 2>/dev/null | head -1
    fi
}

# --- 1. Checks ---
if [[ $EUID -ne 0 ]]; then
    echo "Error: Run with sudo!"
    read -p "Press Enter to exit..."
    exit 1
fi

echo
header "Anarchy Linux Install"
echo

step "Checking internet connection..."
if ! ping -c 1 8.8.8.8 &>/dev/null; then
    if ! ping -c 1 1.1.1.1 &>/dev/null; then
        fail "Internet connection required."
        read -p "Press Enter to exit..."
        exit 1
    fi
fi
ok "Internet connected"
echo

# --- 2. Setup ---
IS_EFI=false
[[ -d "/sys/firmware/efi" ]] && IS_EFI=true

# --- 3. Drive Selection ---
section "Drive Selection"
echo
TARGET_DISK=$(lsblk -dpno NAME,SIZE,MODEL | grep -v -E '/(zram|loop|dm-|ram|sr|fd)[0-9]*' | gum choose --header "Select target drive" | awk '{print $1}')
[ -z "$TARGET_DISK" ] && exit 1

# Safety check: don't install to the disk we're running from
BOOT_DISK=$(get_boot_disk)
if [ -n "$BOOT_DISK" ] && [ "$(basename "$TARGET_DISK")" == "$BOOT_DISK" ]; then
    fail "Cannot install to the disk you're currently running from!"
    exit 1
fi

echo "  Selected disk: $(gum style --foreground "$C_TEAL" "$TARGET_DISK")"
echo

INSTALL_MODE=$(gum choose --header "Installation Type" "Erase entire disk" "Install on existing partition")
if [ "$INSTALL_MODE" == "Erase entire disk" ]; then
    INSTALL_MODE="erase"
    TARGET_DRIVE="$TARGET_DISK"
    if [[ "$TARGET_DRIVE" =~ [0-9]$ ]]; then P="p"; else P=""; fi
    if [ "$IS_EFI" = true ]; then EFI_PART="${TARGET_DRIVE}${P}1"; fi
    ROOT_PART="${TARGET_DRIVE}${P}2"
    ok "Selected: $TARGET_DRIVE (will be wiped)"
else
    INSTALL_MODE="partition"
    TARGET_DRIVE="$TARGET_DISK"
    ROOT_PART=$(lsblk -rno NAME,SIZE,FSTYPE "$TARGET_DISK" | awk '$3 != "swap" && $3 != "" {print $1, $2, $3}' | gum choose --header "Select root partition on $TARGET_DISK" | awk '{print $1}')
    [ -z "$ROOT_PART" ] && exit 1
    ROOT_PART="/dev/$ROOT_PART"

    if [ "$IS_EFI" = true ]; then
        EFI_RAW=$(lsblk -rno NAME,FSTYPE "$TARGET_DISK" | awk '$2 == "vfat" {print $1; exit}')
        if [ -n "$EFI_RAW" ]; then
            EFI_PART="/dev/$EFI_RAW"
            # Check for other Linux installations on this disk
            OTHER_LINUX_COUNT=$(lsblk -rno NAME,TYPE,FSTYPE "$TARGET_DISK" | awk '$2 == "part" && $3 == "linux filesystem" {print $1}' | grep -cv "$(basename "$ROOT_PART")" 2>/dev/null || echo "0")
            if [ "$OTHER_LINUX_COUNT" -gt 0 ]; then
                echo
                gum style --foreground "$C_YELLOW" --bold "  ⚠  WARNING: This disk has other Linux partitions."
                gum style --foreground "$C_SUBTEXT" "     The EFI partition ($EFI_PART) will be shared with other installations."
                gum style --foreground "$C_SUBTEXT" "     Other kernels/initramfs files on the EFI partition will be preserved."
                gum confirm --affirmative "Continue" --negative "Abort" "     Continue with shared EFI?" || exit 1
                echo
            fi
        else
            fail "No FAT32 EFI partition found on $TARGET_DISK. Create one first."
            exit 1
        fi
    fi
    ok "Selected: $ROOT_PART"
fi
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
    AUDIO_PKGS="pipewire pipewire-pulse pipewire-alsa wireplumber"
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
if [ "$INSTALL_MODE" == "erase" ]; then
    echo "  $(gum style --foreground "$C_SUBTEXT" "Drive:")     $(gum style --foreground "$C_YELLOW" --bold "$TARGET_DRIVE")"
else
    echo "  $(gum style --foreground "$C_SUBTEXT" "Root:")      $(gum style --foreground "$C_YELLOW" --bold "$ROOT_PART")"
    echo "  $(gum style --foreground "$C_SUBTEXT" "Disk:")      $(gum style --foreground "$C_SUBTEXT" "$TARGET_DRIVE")"
fi
echo "  $(gum style --foreground "$C_SUBTEXT" "Boot Mode:") $(gum style --foreground "$C_TEAL" "$([ "$IS_EFI" = true ] && echo "UEFI" || echo "BIOS")")"
echo
echo "  $(gum style --foreground "$C_SUBTEXT" "Kernel:")    $(gum style --foreground "$C_MAUVE" --bold "$KERNEL")"
echo "  $(gum style --foreground "$C_SUBTEXT" "AUR:")       $(gum style --foreground "$C_MAUVE" "$AUR_HELPER")"
echo
if [ "$INSTALL_MODE" == "erase" ]; then
    gum confirm --affirmative "Proceed" --negative "Abort" "  ⚠  This will WIPE $TARGET_DRIVE. Continue?" || exit 1
else
    gum confirm --affirmative "Proceed" --negative "Abort" "  ⚠  This will FORMAT $ROOT_PART. Continue?" || exit 1
fi
echo

set -e

# --- EXECUTION ---

# --- Step 1: Partitioning ---
if [ "$INSTALL_MODE" == "erase" ]; then
    step "Partitioning $TARGET_DRIVE..."
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
    echo
fi

# --- Step 2: Formatting ---
step "Formatting partitions..."
if [ "$INSTALL_MODE" == "erase" ]; then
    if [ "$IS_EFI" = true ]; then mkfs.vfat -F 32 "$EFI_PART"; fi
fi
mkfs.btrfs -L ARCH_ROOT -f "$ROOT_PART"
ok "Filesystems formatted"
echo

# --- Step 3: Btrfs Subvolumes ---
step "Creating Btrfs subvolumes..."
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
echo

# --- Step 4: Cloning System ---
step "Cloning system to target..."
rsync -aAXhW --numeric-ids --info=progress2 \
    --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
    --exclude={"/var/cache/*","/var/log/*","/var/tmp/*"} \
    --exclude={"/usr/share/doc/*","/usr/share/man/*","/usr/share/info/*"} \
    --exclude={"/usr/lib/modules/*","/usr/lib/firmware/*"} \
    --exclude="/etc/pacman.d/gnupg/*" \
    --exclude="/root/*" \
    / /mnt/
ok "System cloned"
echo

# --- Step 5: Configuration (Chroot) ---
step "Configuring target system..."
# Replace fstab instead of appending to avoid duplicates from cloned system
genfstab -U /mnt > /mnt/etc/fstab
cp --remove-destination /etc/resolv.conf /mnt/etc/resolv.conf

partprobe $TARGET_DRIVE
udevadm settle
sleep 2
ROOT_UUID=$(lsblk -no UUID $ROOT_PART)

# --- Write env vars to file (avoids heredoc expansion mangling passwords) ---
cat > /mnt/.install_env <<ENVEOF
TARGET_DRIVE="$TARGET_DRIVE"
IS_EFI=$IS_EFI
INSTALL_MODE=$INSTALL_MODE
ROOT_UUID="$ROOT_UUID"
KERNEL="$KERNEL"
CPU="$CPU"
GPU_PKGS="$GPU_PKGS"
AUDIO_PKGS="$AUDIO_PKGS"
AUR_HELPER="$AUR_HELPER"
NEW_USER="$NEW_USER"
TIMEZONE="$TIMEZONE"
NEW_HOSTNAME="$NEW_HOSTNAME"
ENVEOF
printf 'ROOT_PASS=%s\n' "$ROOT_PASS" >> /mnt/.install_env
printf 'NEW_PASS=%s\n' "$NEW_PASS" >> /mnt/.install_env

# Write AUR_HELPER to a file so the inner bash can source it (quoted heredoc can't expand)
echo "AUR_HELPER=$AUR_HELPER" > /mnt/.aur_helper_env

arch-chroot /mnt /bin/bash <<'CHEOF'
set -e
source /.install_env
source /.aur_helper_env

echo ":: Repairing cloned pacman database..."
find /var/lib/pacman/local/ -type f -name "desc" -exec sed -i '/^%INSTALLED_DB%/,/^$/d' {} +

pacman-key --init
pacman-key --populate archlinux

echo ":: Cleaning boot config..."
pacman -Rns --noconfirm archiso 2>/dev/null || true
rm -rf /etc/mkinitcpio.conf.d
rm -f /etc/mkinitcpio.d/*.preset

# In partition mode, only remove files for the selected kernel to preserve other installations
# In erase mode, we can safely remove everything since we created the partition
if [ "$INSTALL_MODE" == "erase" ]; then
    rm -f /boot/vmlinuz* /boot/initramfs*
else
    rm -f /boot/vmlinuz-$KERNEL* /boot/initramfs-$KERNEL*
fi

INITRAMFS_MODULES="btrfs amdgpu i915"
if [[ "$GPU_PKGS" == *nvidia* ]]; then
    INITRAMFS_MODULES+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm"
fi
echo "MODULES=($INITRAMFS_MODULES)" > /etc/mkinitcpio.conf
echo "BINARIES=()" >> /etc/mkinitcpio.conf
echo "FILES=()" >> /etc/mkinitcpio.conf
echo "HOOKS=(base udev autodetect modconf kms microcode keyboard keymap consolefont block filesystems fsck)" >> /etc/mkinitcpio.conf

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
KERNEL_HEADERS="${KERNEL}-headers"
[[ "$KERNEL" == "linux" ]] && KERNEL_HEADERS="linux-headers"

if [ "$AUDIO" = "pipewire" ]; then
    pacman -Rns --noconfirm pulseaudio pulseaudio-bluetooth pulseaudio-zeroconf pulseaudio-alsa 2>/dev/null || true
else
    pacman -Rns --noconfirm pipewire pipewire-pulse pipewire-alsa pipewire-jack pipewire-zeroconf wireplumber 2>/dev/null || true
fi

pacman -Syu --noconfirm $KERNEL $KERNEL_HEADERS $CPU $GPU_PKGS $AUDIO_PKGS linux-firmware btrfs-progs grub $([ "$IS_EFI" = true ] && echo "efibootmgr")
mkinitcpio -P

echo ":: Adding Anarchy Repository..."
# Import repo key (don't fail installation if repo setup fails)
if curl -sL https://raw.githubusercontent.com/Riezz0/anarchy-repo/main/x86_64/anarchy-repo.key | pacman-key --add - 2>/dev/null; then
    pacman-key --lsign-key "anarchy-repo" 2>/dev/null || true

    # Add repo to pacman.conf if not already present
    if ! grep -q "anarchy-repo" /etc/pacman.conf; then
        echo "" >> /etc/pacman.conf
        echo "[anarchy-repo]" >> /etc/pacman.conf
        echo "SigLevel = Optional TrustAll" >> /etc/pacman.conf
        echo "Server = https://raw.githubusercontent.com/Riezz0/anarchy-repo/main/x86_64" >> /etc/pacman.conf
    fi

    # Sync and install anarchy-welcome
    pacman -Sy --noconfirm 2>/dev/null || true
    pacman -S --noconfirm anarchy-welcome || echo "WARN: anarchy-welcome install failed (will be available after first boot)"
else
    echo "WARN: Could not fetch anarchy-repo key (network issue). Skipping repo setup."
fi

echo ":: Configuring Grub..."
if [ "$IS_EFI" = true ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
else
    if [ "$INSTALL_MODE" == "erase" ]; then
        # In erase mode, safe to install to the whole disk MBR
        grub-install --target=i386-pc "$TARGET_DRIVE" --recheck
    else
        # In partition mode, install to the partition to avoid overwriting other OS bootloaders
        grub-install --target=i386-pc "$ROOT_PART" --recheck
    fi
fi

sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"root=UUID=$ROOT_UUID rootflags=subvol=@ rw\"|" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

echo ":: Setting System Identity..."
echo "$NEW_HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo ":: Creating Users..."
printf '%s\n' "root:$ROOT_PASS" | chpasswd
useradd -m -G wheel -s /bin/bash "$NEW_USER"
printf '%s:%s\n' "$NEW_USER:$NEW_PASS" | chpasswd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

if [ "$AUR_HELPER" != "none" ]; then
    echo ":: Installing AUR Helper: $AUR_HELPER"
    pacman -S --needed --noconfirm base-devel git

    # Temporarily enable NOPASSWD for wheel so makepkg -si can run pacman
    sed -i 's/%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

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

    # Revert to password-based sudo
    sed -i 's/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
fi

echo ":: Creating git directory..."
mkdir -p "/home/$NEW_USER/git"
chown -R "$NEW_USER:users" "/home/$NEW_USER/git"

echo ":: Enabling Services..."
systemctl enable NetworkManager
systemctl enable sddm

echo ":: Cloning Dotfiles..."
git clone https://github.com/Riezz0/anarchydots "/home/$NEW_USER/anarchydots"
chown -R "$NEW_USER:users" "/home/$NEW_USER/anarchydots"

echo ":: Stowing Dotfiles Packages..."
rm -rf "/home/$NEW_USER/.config"
rm -rf "/home/$NEW_USER/.icons"
rm -rf "/home/$NEW_USER/.themes"
if [ -d "/home/$NEW_USER/.local/share/themes" ]; then
    cp -a "/home/$NEW_USER/.local/share/themes" "/tmp/user_themes_backup"
fi
rm -rf "/home/$NEW_USER/.local"
if [ -d "/tmp/user_themes_backup" ]; then
    mkdir -p "/home/$NEW_USER/.local/share"
    mv "/tmp/user_themes_backup" "/home/$NEW_USER/.local/share/themes"
    chown -R "$NEW_USER:users" "/home/$NEW_USER/.local"
fi
rm -rf "/home/$NEW_USER/.oh-my-zsh"
rm -rf "/home/$NEW_USER/.cache"
rm -f "/home/$NEW_USER/.zshrc"

cd "/home/$NEW_USER/anarchydots"
rm -rf /usr/local/bin

#1
sudo mkdir -p /usr/local/
#2
sudo stow -t /usr/local scripts
ls -la /usr/local/bin/ | head -5
echo "  ✔ Scripts stowed"
sudo -u "$NEW_USER" stow --restow bg cursors fastfetch gradience gtk3 gtk4 hypr-themes hyprland icons kitty kvantum neovim omz pypr pywal qt5 qt6 quickshell rofi themes wal xkb zsh -t "/home/$NEW_USER"
echo ":: Installing Fonts..."
mkdir -p "/home/$NEW_USER/.local/share/fonts/"
cp -r "/home/$NEW_USER/anarchydots/fonts/." "/home/$NEW_USER/.local/share/fonts/"
fc-cache -fv

echo ":: Configuring SDDM..."
cp -r "/home/$NEW_USER/anarchydots/sys/sddm/sddm.conf" "/etc/"
cp -r "/home/$NEW_USER/anarchydots/sys/sddm/anarchy-sddm/" "/usr/share/sddm/themes/"

# One-time setup (run with sudo)
mkdir -p /var/local/sddm-wallpaper
cp -r /home/"$NEW_USER"/anarchydots/sys/sddm/initial-setup/* /var/local/sddm-wallpaper/
chown -R "$NEW_USER:sddm" /var/local/sddm-wallpaper
chmod -R 775 /var/local/sddm-wallpaper

echo ":: Configuring GRUB Theme..."
cp -r "/home/$NEW_USER/anarchydots/sys/grub/grub" "/etc/default/"
cp -r "/home/$NEW_USER/anarchydots/sys/grub/tokyo-night" "/usr/share/grub/themes/"

echo ":: Enabling Additional Services..."
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable bluetooth 2>/dev/null || true
systemctl enable coolercontrold.service 2>/dev/null || true
sudo -u "$NEW_USER" arch-update --tray --enable
chsh -s /bin/zsh "$NEW_USER"
chsh -s /bin/zsh root

echo ":: Setting up first-boot monitor config..."
AUTOSTART_DIR="/home/$NEW_USER/.config/autostart"
LOCALBIN_DIR="/home/$NEW_USER/.local/bin"
mkdir -p "$AUTOSTART_DIR"
mkdir -p "$LOCALBIN_DIR"

cat > "$LOCALBIN_DIR/hyprmon-once.sh" <<'HYPREOF'
#!/bin/bash
hyprmon
rm -f "$HOME/.config/autostart/hyprmon-firstboot.desktop"
HYPREOF
chmod +x "$LOCALBIN_DIR/hyprmon-once.sh"

cat > "$AUTOSTART_DIR/hyprmon-firstboot.desktop" <<DESKTOPEOF
[Desktop Entry]
Type=Application
Name=Monitor Setup
Comment=Configure your monitors on first boot
Exec=$LOCALBIN_DIR/hyprmon-once.sh
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
DESKTOPEOF

chown -R "$NEW_USER:users" "$LOCALBIN_DIR"
chown -R "$NEW_USER:users" "$AUTOSTART_DIR"

rm -f /.install_env
rm -f /.aur_helper_env
CHEOF
umount -R /mnt
ok "Configuration complete"

echo
header "Installation Complete!"
echo
info "Log in and run 'hyprmon' to configure your monitors."
echo
if gum confirm "Do you want to reboot your system now?"; then
    reboot
fi
