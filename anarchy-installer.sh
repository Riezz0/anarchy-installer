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

# --- 0. Safety Cleanup ---
umount -R /mnt &>/dev/null

# --- GUI Mode: skip TUI, source env vars ---
if [[ "${1:-}" == "--gui-env" ]]; then
    ENV_FILE="/tmp/.anarchy_install_env"
    [[ -f "$ENV_FILE" ]] || { echo "ERROR: $ENV_FILE not found"; exit 1; }
    source "$ENV_FILE"
    IS_EFI=false
    [[ -d "/sys/firmware/efi" ]] && IS_EFI=true
    if [[ "$TARGET_DRIVE" =~ [0-9]$ ]]; then P="p"; else P=""; fi
    EFI_PART="${TARGET_DRIVE}${P}1"
    ROOT_PART="${TARGET_DRIVE}${P}2"
    set -e
    echo "[GUI] Sourced config from $ENV_FILE"
    echo "[GUI] Drive: $TARGET_DRIVE | EFI: $IS_EFI | User: $NEW_USER"
    export GUI_MODE=1
else
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
    echo "  $(gum style --foreground "$C_SUBTEXT" "Drive:")     $(gum style --foreground "$C_YELLOW" --bold "$TARGET_DRIVE")"
    echo "  $(gum style --foreground "$C_SUBTEXT" "Boot Mode:") $(gum style --foreground "$C_TEAL" "$([ "$IS_EFI" = true ] && echo "UEFI" || echo "BIOS")")"
    echo
    echo "  $(gum style --foreground "$C_SUBTEXT" "Kernel:")    $(gum style --foreground "$C_MAUVE" --bold "$KERNEL")"
    echo "  $(gum style --foreground "$C_SUBTEXT" "AUR:")       $(gum style --foreground "$C_MAUVE" "$AUR_HELPER")"
    echo
    gum confirm --affirmative "Proceed" --negative "Abort" "  ⚠  This will WIPE $TARGET_DRIVE. Continue?" || exit 1
    echo

    set -e
fi
# --- EXECUTION ---

# --- Step 1: Partitioning ---
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

# --- Step 2: Formatting ---
step "Formatting partitions..."
if [ "$IS_EFI" = true ]; then mkfs.vfat -F 32 "$EFI_PART"; fi
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
genfstab -U /mnt >> /mnt/etc/fstab
cp --remove-destination /etc/resolv.conf /mnt/etc/resolv.conf

partprobe $TARGET_DRIVE
udevadm settle
sleep 2
ROOT_UUID=$(lsblk -no UUID $ROOT_PART)

# --- Write env vars to file (avoids heredoc expansion mangling passwords) ---
cat > /mnt/.install_env <<ENVEOF
TARGET_DRIVE="$TARGET_DRIVE"
IS_EFI=$IS_EFI
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
KERNEL_HEADERS="${KERNEL}-headers"
[[ "$KERNEL" == "linux" ]] && KERNEL_HEADERS="linux-headers"

if [ "$AUDIO" = "pipewire" ]; then
    pacman -Rns --noconfirm pulseaudio pulseaudio-bluetooth pulseaudio-zeroconf pulseaudio-alsa 2>/dev/null || true
else
    pacman -Rns --noconfirm pipewire pipewire-pulse pipewire-alsa pipewire-jack pipewire-zeroconf wireplumber 2>/dev/null || true
fi

pacman -Sy --noconfirm $KERNEL $KERNEL_HEADERS $CPU $GPU_PKGS $AUDIO_PKGS linux-firmware btrfs-progs grub $([ "$IS_EFI" = true ] && echo "efibootmgr")
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
printf '%s\n' "root:$ROOT_PASS" | chpasswd
useradd -m -G wheel -s /bin/bash "$NEW_USER"
printf '%s:%s\n' "$NEW_USER" "$NEW_PASS" | chpasswd
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

# --- Silent VSCodium Install ---
if [[ "${INSTALL_VSCODIUM:-false}" == "true" && "$AUR_HELPER" != "none" ]]; then
    sed -i 's/%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

    sudo -u "$NEW_USER" bash -c "
        $AUR_HELPER -S --noconfirm vscodium-bin >/dev/null 2>&1 || exit 0

        SETTINGS_DIR=\"\$HOME/.config/Code - OSS/User\"
        SETTINGS_FILE=\"\$SETTINGS_DIR/settings.json\"
        mkdir -p \"\$SETTINGS_DIR\"

        if command -v code-oss &>/dev/null; then
            code-oss --install-extension dlasagno.wal-theme --force >/dev/null 2>&1
        elif command -v code &>/dev/null; then
            code --install-extension dlasagno.wal-theme --force >/dev/null 2>&1
        fi

        cat > \"\$SETTINGS_FILE\" <<SETEOF
{
    \"workbench.colorTheme\": \"Wal\",
    \"wal.path\": \"\$HOME/.cache/wal/colors.json\"
}
SETEOF
    " || true

    sed -i 's/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
fi

# --- Silent Pywalfox + Firefox Theme ---
if [[ "${INSTALL_PYWALFOX:-true}" == "true" ]]; then
    pip install --break-system-packages pywalfox >/dev/null 2>&1 || true

    PYWALFOX_VER="2.10"
    PYWALFOX_XPI="/tmp/pywalfox.xpi"
    curl -sL "https://github.com/Frewen/pywalfox/releases/download/v${PYWALFOX_VER}/pywalfox.xpi" \
        -o "$PYWALFOX_XPI" 2>/dev/null || true

    FIREFOX_DIR="/home/$NEW_USER/.mozilla"
    NATIVE_HOST_DIR="$FIREFOX_DIR/native-messaging-hosts"
    mkdir -p "$NATIVE_HOST_DIR"

    PYWALFOX_BIN="$(command -v pywalfox 2>/dev/null || echo /usr/bin/pywalfox)"

    cat > "$NATIVE_HOST_DIR/pywalfox.json" <<NATEOF
{
    "name": "pywalfox",
    "description": "Pywalfox native messaging host",
    "path": "$PYWALFOX_BIN",
    "type": "stdio",
    "allowed_extensions": ["pywalfox@frewen.cz"]
}
NATEOF

    FIREFOX_CFG_DIR="/home/$NEW_USER/.mozilla/firefox"
    DIST_DIR="$FIREFOX_CFG_DIR/distribution"
    AUTOCONFIG_DIR="$DIST_DIR/autoconfig"
    mkdir -p "$AUTOCONFIG_DIR"

    cat > "$AUTOCONFIG_DIR/config-prefs.js" <<PREFEOF
pref("general.config.filename", "firefox.cfg");
pref("general.config.obscure_value", 0);
pref("general.config.sandbox_enabled", false);
PREFEOF

    cat > "$AUTOCONFIG_DIR/firefox.cfg" <<CFGEOF
// Pywalfox auto-install
try {
    const { Services } = ChromeUtils.import("resource://gre/modules/Services.jsm");
    const xr = Services.obs;

    function installXPI(path) {
        try {
            const file = Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
            file.initWithPath(path);
            if (file.exists()) {
                const ext = Cc["@mozilla.org/addons/addon-manager;1"]
                    .getService(Ci.amIAddonManager);
                AddonManager.installTemporaryAddon(file);
            }
        } catch(e) {}
    }

    const xpi = Services.dirsvc.get("TmpD", Ci.nsIFile);
    xpi.append("pywalfox.xpi");
    const xhr = Cc["@mozilla.org/xhr;1"].createInstance(Ci.nsIXMLHttpRequest);
    xhr.open("GET", "https://github.com/Frewen/pywalfox/releases/download/v${PYWALFOX_VER}/pywalfox.xpi", false);
    xhr.responseType = "arraybuffer";
    xhr.send();
    if (xhr.status === 200) {
        const stream = Cc["@mozilla.org/io/file-output-stream;1"]
            .createInstance(Ci.nsIFileOutputStream);
        stream.init(xpi, 0x04 | 0x08 | 0x20, 0o666, 0);
        stream.write(xhr.response);
        stream.close();
        AddonManager.installTemporaryAddon(xpi);
    }
} catch(e) {}
CFGEOF

    cat > "$FIREFOX_CFG_DIR/profiles.ini" <<PROFEOF
[Profile0]
Name=default
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
PROFEOF

    DEFAULT_PROFILE="$FIREFOX_CFG_DIR/default-release"
    mkdir -p "$DEFAULT_PROFILE"

    cat > "$DEFAULT_PROFILE/user.js" <<USEREOF
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
USEREOF

    if [[ -f "$PYWALFOX_XPI" ]]; then
        mkdir -p "$DEFAULT_PROFILE/extensions"
        cp "$PYWALFOX_XPI" "$DEFAULT_PROFILE/extensions/pywalfox@frewen.cz.xpi"
        rm -f "$PYWALFOX_XPI"
    fi

    chown -R "$NEW_USER:users" "$FIREFOX_DIR"
fi

# --- Flatpak Dependencies (always install) ---
FLATPAK_DEPS="org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark"

pacman -S --needed --noconfirm flatpak >/dev/null 2>&1 || true
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true

echo ":: Installing Flatpak dependencies..."
for app in $FLATPAK_DEPS; do
    flatpak install -y --noninteractive flathub "$app" >/dev/null 2>&1 || true
done

if [[ -n "${FLATPAK_LIST:-}" ]]; then
    echo ":: Installing selected Flatpak applications..."
    IFS=',' read -ra FP_APPS <<< "$FLATPAK_LIST"
    for app in "${FP_APPS[@]}"; do
        app=$(echo "$app" | xargs)
        [[ -z "$app" ]] && continue
        flatpak install -y --noninteractive flathub "$app" >/dev/null 2>&1 || true
    done
fi

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
if [[ "${GUI_MODE:-}" != "1" ]]; then
    info "Log in and run 'hyprmon' to configure your monitors."
else
    info "Monitor configuration will launch automatically on first login."
fi

if [[ "${GUI_MODE:-}" != "1" ]]; then
    if gum confirm "Do you want to reboot your system now?"; then
        reboot
    fi
fi
