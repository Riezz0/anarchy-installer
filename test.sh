#!/usr/bin/env bash
# ==============================================================================
# INTEGRATED STRICTLY OFFLINE ARCH LINUX INSTALLER
# ==============================================================================
# This script runs entirely offline inside your custom Arch Linux Live ISO environment.
# It provisions disks, formats partitions, and performs an offline pacstrap
# using the local repository integrated into the ISO image.
# ==============================================================================
set -e

# --- 1. LOCAL STORAGE PATH CHECK ---
# This path points to the package database and archives baked into the ISO image
LOCAL_REPO_DIR="/opt/arch-offline-repo"

if [ ! -d "$LOCAL_REPO_DIR" ] || [ ! -f "$LOCAL_REPO_DIR/offline_repo.db.tar.zst" ]; then
    echo "❌ Error: Built-in local repository or database index not found at $LOCAL_REPO_DIR"
    echo "Please ensure you have populated this directory with your .pkg.tar.zst files"
    echo "and ran 'repo-add ./offline_repo.db.tar.zst ./*.pkg.tar.zst' before compiling the ISO."
    exit 1
fi

# --- 2. INTERACTIVE TARGET DRIVE SELECTION ---
echo "=================================================="
echo "          AVAILABLE STORAGE DRIVES                "
echo "=================================================="
lsblk -dno NAME,SIZE,MODEL | grep -v "loop"
echo "=================================================="
echo ""

while true; do
    read -rp "Enter the disk name to install Arch onto (e.g., sda, nvme0n1): " DISK_NAME
    DISK="/dev/$DISK_NAME"
    if [ -b "$DISK" ]; then
        break
    fi
    echo "❌ Invalid block device. Please pick a drive listed above."
done

# Condition partition naming conventions dynamically based on disk interface type
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

# --- 3. CONFIGURATION VARIABLES ---
HOSTNAME="arch-zen-hyprland"
TIMEZONE="UTC"
KEYMAP="us"

# --- 4. SAFETY DESTRUCTION CONFIRMATION ---
echo ""
echo "⚠️  CRITICAL WARNING: This process will completely wipe $DISK."
read -rp "Are you absolutely certain you want to proceed? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Installation aborted by user request."
    exit 1
fi

# --- 5. AUTOMATED DISK LAYOUT & PARTITIONING (UEFI/GPT) ---
echo "==> Wiping and partitioning target drive $DISK..."
sgdisk --clear "$DISK"
sgdisk --new=1:0:+512M --typecode=1:ef00 --change-name=1:"EFI" "$DISK"
sgdisk --new=2:0:0      --typecode=2:8300 --change-name=2:"ROOT" "$DISK"

# Allow the kernel a brief moment to process the newly created partition partition boundaries
sleep 2

echo "==> Formatting filesystems..."
mkfs.vfat -F 32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"

echo "==> Mounting system file paths..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi

# --- 6. STANDALONE PACMAN REPOSITORY EMULATION ---
echo "==> Constructing strict offline isolation pacman configuration..."
cp /etc/pacman.conf /tmp/pacman-offline.conf

# Strip out external mirror networks and enforce your local offline_repo stack database link
cat <<EOF >> /tmp/pacman-offline.conf

[offline_repo]
SigLevel = Optional TrustAll
Server = file://$LOCAL_REPO_DIR
EOF

# --- 7. OFFLINE PACSTRAP PROVISIONING ---
echo "==> Executing offline pacstrap configuration sequence..."
# All target names match lowercase naming specifications inside core databases
pacstrap -C /tmp/pacman-offline.conf -K /mnt \
    base linux-zen linux-zen-headers linux-firmware grub efibootmgr networkmanager nano \
    sddm uwsm hyprland kitty waybar dunst rofi-wayland mesa pipewire pipewire-pulse wireplumber xorg-xwayland

# --- 8. MOUNT DESCRIPTORS CONFIGURATION ---
echo "==> Generating physical filesystem map (/etc/fstab)..."
genfstab -U /mnt >> /mnt/etc/fstab

# --- 9. INTERNAL SYSTEM INJECTION CONFIGURATION (CHROOT Execution Layout) ---
echo "==> Executing internal environment setup via arch-chroot..."
cat <<CHROOT_EOF | arch-chroot /mnt

# Dynamic Localization Setup
echo "LANG=en_US.UTF-8" > /etc/locale.gen
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Loopback System Network Mapping Definitions
echo "$HOSTNAME" > /etc/hostname
cat <<NET_EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
NET_EOF

# Activate Target Core Systemdaemons
systemctl enable NetworkManager
systemctl enable sddm

# Compile Standalone Platform System Bootloader (GRUB handles Zen out-of-the-box)
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

# Define baseline root configuration token pass (Change instantly post boot)
echo "root:root" | chpasswd

CHROOT_EOF

# --- 10. CLEAN TERMINATION SEQUENCE ---
echo "==> Dismounting layout nodes..."
umount -R /mnt

echo "======================================================================"
echo " 🎉 SUCCESS! Strict offline system deployment completed successfully."
echo " Power down the device, extract your installation image, and reboot."
echo " Log in using user 'root' and pass 'root', then configure 'passwd'."
echo "======================================================================"

