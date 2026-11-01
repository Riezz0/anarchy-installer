#!/usr/bin/env bash
# ==============================================================================
# INTEGRATED STRICTLY OFFLINE ARCH LINUX INSTALLER (UEFI ONLY)
# ==============================================================================
# This script runs 100% offline. It forces pacman to ignore the internet
# and install everything directly out of the built-in repository folder.
# ==============================================================================
set -e

# --- 1. LOCAL STORAGE PATH CHECK ---
LOCAL_REPO_DIR="/opt/arch-offline-repo"

if [ ! -d "$LOCAL_REPO_DIR" ] || [ ! -f "$LOCAL_REPO_DIR/offline_repo.db" ]; then
    echo "❌ Error: Built-in repository or database index not found at $LOCAL_REPO_DIR"
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

# --- 4. DESTRUCTION CONFIRMATION ---
echo ""
echo "⚠️  CRITICAL WARNING: This process will completely wipe $DISK."
read -rp "Are you absolutely certain you want to proceed? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Installation aborted by user."
    exit 1
fi

# --- 5. AUTOMATED UEFI/GPT DISK LAYOUT ---
echo "==> Wiping and partitioning target drive $DISK..."
sgdisk --clear "$DISK"
sgdisk --new=1:0:+512M --typecode=1:ef00 --change-name=1:"EFI" "$DISK"
sgdisk --new=2:0:0      --typecode=2:8300 --change-name=2:"ROOT" "$DISK"

sleep 2

echo "==> Formatting filesystems..."
mkfs.vfat -F 32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"

echo "==> Mounting system filesystems..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi

# --- 6. CONFIGURE STRICT OFFLINE PACMAN EMULATION ---
echo "==> Structuring strict offline repository isolation..."
# Start with a clean configuration file that drops all mirror setups
cat <<EOF > /tmp/pacman-offline.conf
[options]
Architecture = auto
SigLevel = Optional TrustAll
LocalFileSigLevel = Optional

[offline_repo]
SigLevel = Optional TrustAll
Server = file://$LOCAL_REPO_DIR
EOF

# --- 7. STRICTLY OFFLINE PACSTRAP TARGET SEQUENCE ---
echo "==> Executing pure offline pacstrap deployment..."
# This command will ONLY look at your local /opt folder
pacstrap -C /tmp/pacman-offline.conf -K /mnt \
    base linux-zen linux-zen-headers linux-firmware grub efibootmgr networkmanager nano sudo \
    sddm uwsm hyprland kitty waybar dunst rofi-wayland mesa pipewire pipewire-audio wireplumber xorg-xwayland

# --- 8. MOUNT DESCRIPTORS MAPPING ---
echo "==> Generating filesystem boundary tracking table (/etc/fstab)..."
genfstab -U /mnt >> /mnt/etc/fstab

# --- 9. INTERNAL SYSTEM PROVISIONING (CHROOT) ---
echo "==> Entering chroot environment for internal personalization..."
cat <<CHROOT_EOF | arch-chroot /mnt

# Setup localization and clocks
echo "LANG=en_US.UTF-8" > /etc/locale.gen
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Loopback system network definitions
echo "$HOSTNAME" > /etc/hostname
cat <<NET_EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
NET_EOF

# Activate background system utilities
systemctl enable NetworkManager
systemctl enable sddm

# Compile standalone UEFI bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

# Define fallback root profile authentication credentials
echo "root:root" | chpasswd

CHROOT_EOF

# --- 10. RECOVERY CLEANUP TERMINATION ---
echo "==> Safely unmounting storage arrays..."
umount -R /mnt

echo "======================================================================"
echo " 🎉 SUCCESS! Strict offline system installation complete."
echo " Power down the device, extract your live USB, and reboot."
echo "======================================================================"

