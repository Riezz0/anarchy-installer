#!/usr/bin/env bash
# =============================================================================
#  ArchHypr Installer
#  Arch Linux + Hyprland (UWSM) + SDDM — Interactive gum-powered installer
# =============================================================================

set -euo pipefail

# ─── gum theme ───────────────────────────────────────────────────────────────
export GUM_CONFIRM_PROMPT_FOREGROUND="99"
export GUM_CONFIRM_SELECTED_FOREGROUND="0"
export GUM_CONFIRM_SELECTED_BACKGROUND="99"
export GUM_INPUT_CURSOR_FOREGROUND="99"
export GUM_INPUT_PROMPT_FOREGROUND="99"
export GUM_CHOOSE_CURSOR_FOREGROUND="99"
export GUM_CHOOSE_SELECTED_FOREGROUND="99"
export GUM_SPIN_SPINNER_FOREGROUND="99"
export GUM_FILTER_INDICATOR_FOREGROUND="99"
export GUM_FILTER_MATCH_FOREGROUND="226"
export GUM_FILTER_PROMPT_FOREGROUND="81"
export GUM_FILTER_SELECTED_INDICATOR_FOREGROUND="82"

# ─── ANSI colours ────────────────────────────────────────────────────────────
PURPLE="\033[38;5;99m"
CYAN="\033[38;5;81m"
GREEN="\033[38;5;82m"
RED="\033[38;5;196m"
YELLOW="\033[38;5;226m"
BOLD="\033[1m"
RESET="\033[0m"

# ─── UI helpers ──────────────────────────────────────────────────────────────
print_banner() {
  clear
  echo -e "${PURPLE}${BOLD}"
  cat << 'EOF'
  █████╗ ██████╗  ██████╗██╗  ██╗    ██╗  ██╗██╗   ██╗██████╗ ██████╗
 ██╔══██╗██╔══██╗██╔════╝██║  ██║    ██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗
 ███████║██████╔╝██║     ███████║    ███████║ ╚████╔╝ ██████╔╝██████╔╝
 ██╔══██║██╔══██╗██║     ██╔══██║    ██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗
 ██║  ██║██║  ██║╚██████╗██║  ██║    ██║  ██║   ██║   ██║     ██║  ██║
 ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝    ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝
EOF
  echo -e "${RESET}"
  gum style \
    --foreground 81 --border-foreground 99 --border rounded \
    --align center --width 72 --margin "0 2" --padding "1 4" \
    "Arch Linux  ·  Hyprland (UWSM)  ·  SDDM" \
    "" \
    "Interactive installer powered by gum"
  echo ""
}

log_step() {
  echo -e "\n${PURPLE}${BOLD}══════════════════════════════════════════════${RESET}"
  gum style --foreground 99 --bold " ▶  $1"
  echo -e "${PURPLE}${BOLD}══════════════════════════════════════════════${RESET}\n"
}

log_ok()   { echo -e "  ${GREEN}✔${RESET}  $1"; }
log_warn() { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
log_err()  { echo -e "  ${RED}✘${RESET}  $1"; }
log_info() { echo -e "  ${CYAN}·${RESET}  $1"; }

die() { log_err "$1"; exit 1; }

run_spin() {
  local title="$1"; shift
  gum spin --spinner dot --title "  $title" -- "$@"
}

require_root() {
  [[ $EUID -eq 0 ]] || die "Please run as root from the Arch ISO."
}

require_gum() {
  if ! command -v gum &>/dev/null; then
    echo -e "${YELLOW}Installing gum…${RESET}"
    pacman -Sy --noconfirm gum || die "Failed to install gum."
  fi
}

check_internet() {
  log_step "Internet Connectivity"
  ping -c 1 -W 3 archlinux.org &>/dev/null \
    && log_ok "Connected." \
    || die "No internet. Connect and re-run."
}

# ─── Pickers ─────────────────────────────────────────────────────────────────
pick_timezone() {
  log_step "Timezone"
  log_info "Select your region, then your city."
  echo ""

  local region
  region=$(find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type d \
    | sed 's|/usr/share/zoneinfo/||' | sort \
    | gum filter --placeholder "Type to search regions…" \
                 --prompt "  Region › " --height 16 \
                 --header "  ① Select region:")
  [[ -n "$region" ]] || die "No region selected."

  local city
  city=$(find "/usr/share/zoneinfo/$region" -mindepth 1 -maxdepth 2 \
    | sed "s|/usr/share/zoneinfo/$region/||" | sort \
    | gum filter --placeholder "Type to search cities…" \
                 --prompt "  City › " --height 16 \
                 --header "  ② Select city / zone:")
  [[ -n "$city" ]] || die "No city selected."

  TIMEZONE="${region}/${city}"
  [[ -f "/usr/share/zoneinfo/$TIMEZONE" ]] || die "Bad timezone: $TIMEZONE"
  log_ok "Timezone: ${BOLD}$TIMEZONE${RESET}"
}

pick_locale() {
  log_step "System Locale"
  log_info "Fuzzy-search the locale list (e.g. type 'en_ZA', 'UTF', 'ja_JP')."
  echo ""

  local locale_list
  if [[ -f /etc/locale.gen ]]; then
    locale_list=$(grep -E '^#?[a-z]' /etc/locale.gen \
      | sed 's/^#//' | awk '{print $1}' | sort -u)
  else
    locale_list=$(localectl list-locales 2>/dev/null || echo "en_US.UTF-8")
  fi

  LOCALE=$(echo "$locale_list" \
    | gum filter --placeholder "e.g. en_ZA.UTF-8…" \
                 --prompt "  Locale › " --height 16 \
                 --header "  Select system locale:")
  [[ -n "$LOCALE" ]] || die "No locale selected."
  log_ok "Locale: ${BOLD}$LOCALE${RESET}"
}

pick_keymap() {
  log_step "Console & Keyboard Layout"
  log_info "Sets TTY keymap."
  echo ""

  local keymaps
  keymaps=$(localectl list-keymaps 2>/dev/null \
    || find /usr/share/kbd/keymaps -name '*.map.gz' \
       | sed 's|.*/||;s|\.map\.gz$||' | sort)

  KEYMAP=$(echo "$keymaps" \
    | gum filter --placeholder "e.g. us, uk, de, za…" \
                 --prompt "  Console keymap › " --height 16 \
                 --header "  ① Select TTY / console keymap:")
  [[ -n "$KEYMAP" ]] || die "No keymap selected."
  log_ok "Console keymap: ${BOLD}$KEYMAP${RESET}"

  log_info "Select the X11/Wayland layout (configure in Hyprland later)."
  echo ""

  local x11_layouts
  x11_layouts=$(localectl list-x11-keymap-layouts 2>/dev/null \
    || printf "us\nuk\nde\nfr\nes\nit\npt\nru\nza\n")

  X11_LAYOUT=$(echo "$x11_layouts" \
    | gum filter --placeholder "e.g. us, gb, de, za…" \
                 --prompt "  Hyprland layout › " --height 16 \
                 --header "  ② Select X11/Wayland layout:")
  [[ -n "$X11_LAYOUT" ]] || X11_LAYOUT="$KEYMAP"
  log_ok "X11 layout: ${BOLD}$X11_LAYOUT${RESET}"

  log_info "Optional: keyboard variant (e.g. dvorak, intl). Leave blank for none."
  echo ""

  local variants
  variants=$(localectl list-x11-keymap-variants "$X11_LAYOUT" 2>/dev/null || echo "")

  if [[ -n "$variants" ]]; then
    X11_VARIANT=$(printf "(none)\n%s" "$variants" \
      | gum filter --placeholder "e.g. dvorak, intl…" \
                   --prompt "  Variant › " --height 14 \
                   --header "  ③ Select layout variant (optional):")
    [[ "$X11_VARIANT" == "(none)" ]] && X11_VARIANT=""
  else
    X11_VARIANT=""
  fi

  [[ -n "$X11_VARIANT" ]] \
    && log_ok "Variant: ${BOLD}$X11_VARIANT${RESET}" \
    || log_ok "Variant: (none)"
}

pick_kernel() {
  log_step "Kernel Selection"
  log_info "All kernels install alongside their headers."
  echo ""

  local choice
  choice=$(gum choose \
    --header "  Select Linux kernel:" \
    "linux          — default rolling kernel (recommended)" \
    "linux-lts      — long-term support, maximum stability" \
    "linux-zen      — tuned for desktop / gaming throughput" \
    "linux-hardened — security-hardened, stricter settings")

  KERNEL=$(echo "$choice" | awk '{print $1}')
  KERNEL_HEADERS="${KERNEL}-headers"
  log_ok "Kernel: ${BOLD}$KERNEL${RESET}"
}

pick_cpu() {
  log_step "CPU Microcode"
  log_info "Select the microcode driver for your processor."
  echo ""

  local choice
  choice=$(gum choose \
    --header "  Select CPU microcode:" \
    "amd-ucode   — for AMD processors" \
    "intel-ucode — for Intel processors" \
    "none        — for Virtual Machines / unsupported")

  CPU_UCODE=$(echo "$choice" | awk '{print $1}')
  [[ "$CPU_UCODE" == "none" ]] && CPU_UCODE=""
  log_ok "Microcode: ${BOLD}${CPU_UCODE:-none}${RESET}"
}

pick_audio() {
  log_step "Audio Backend"
  log_info "Select your preferred audio server."
  echo ""

  local choice
  choice=$(gum choose \
    --header "  Select Audio Server:" \
    "pipewire   — modern standard, excellent Wayland support" \
    "pulseaudio — classic, widely supported")

  AUDIO=$(echo "$choice" | awk '{print $1}')
  log_ok "Audio: ${BOLD}$AUDIO${RESET}"
}

# ─── Disk helpers ────────────────────────────────────────────────────────────
list_disks() {
  lsblk -dpno NAME,SIZE,MODEL | awk '{
    name=$1; size=$2; model=""
    for(i=3;i<=NF;i++) model=model (i>3?" ":"") $i
    printf "%s   %-8s  %s\n", name, size, model
  }'
}

# ─── Partitioning ────────────────────────────────────────────────────────────
partition_disk() {
  local disk="$1" swap_size="$2"
  log_step "Partitioning $disk"

  # ── Ensure disk isn't locked by live environment ──
  swapoff -a
  umount -qR /mnt 2>/dev/null || true

  # ── Unmount any mounted partitions on the target disk ──
  local mounted_parts
  mounted_parts=$(lsblk -lnpo NAME,MOUNTPOINT "$disk" 2>/dev/null \
    | awk '$2 != "" && $2 != "/" {print $1}')
  if [[ -n "$mounted_parts" ]]; then
    log_warn "Unmounting partitions on $disk…"
    echo "$mounted_parts" | while read -r part; do
      umount "$part" 2>/dev/null && log_ok "Unmounted $part" || true
    done
  fi

  wipefs -af  "$disk" >/dev/null
  sgdisk --zap-all "$disk" >/dev/null

  sgdisk -n1:0:+512M  -t1:ef00 -c1:"EFI System"  "$disk"
  if [[ "$swap_size" -gt 0 ]]; then
    sgdisk -n2:0:+"${swap_size}G" -t2:8200 -c2:"Linux swap" "$disk"
    sgdisk -n3:0:0                -t3:8300 -c3:"Linux root"  "$disk"
  else
    sgdisk -n2:0:0 -t2:8300 -c2:"Linux root" "$disk"
  fi

  partprobe "$disk"; sleep 1

  local pfx=""
  [[ "$disk" == *"nvme"* ]] && pfx="p"
  EFI_PART="${disk}${pfx}1"
  if [[ "$swap_size" -gt 0 ]]; then
    SWAP_PART="${disk}${pfx}2"
    ROOT_PART="${disk}${pfx}3"
  else
    SWAP_PART=""
    ROOT_PART="${disk}${pfx}2"
  fi
  log_ok "Partitions created  (EFI: $EFI_PART  Root: $ROOT_PART${SWAP_PART:+  Swap: $SWAP_PART})"
}

format_partitions() {
  local layout="$1"
  log_step "Formatting Partitions ($layout)"

  mkfs.fat -F32 -n "EFI" "$EFI_PART" >/dev/null
  log_ok "EFI  → FAT32  ($EFI_PART)"

  if [[ -n "$SWAP_PART" ]]; then
    mkswap -L "swap" "$SWAP_PART" >/dev/null
    swapon "$SWAP_PART"
    log_ok "Swap → active ($SWAP_PART)"
  fi

  if [[ "$layout" == "btrfs" ]]; then
    mkfs.btrfs -f -L "archroot" "$ROOT_PART" >/dev/null
    mount "$ROOT_PART" /mnt
    btrfs subvolume create /mnt/@          >/dev/null
    btrfs subvolume create /mnt/@home      >/dev/null
    btrfs subvolume create /mnt/@snapshots >/dev/null
    btrfs subvolume create /mnt/@var_log   >/dev/null
    umount /mnt
    local o="noatime,compress=zstd,space_cache=v2,subvol"
    mount -o "${o}=@"          "$ROOT_PART" /mnt
    mkdir -p /mnt/{home,.snapshots,var/log,boot/efi}
    mount -o "${o}=@home"      "$ROOT_PART" /mnt/home
    mount -o "${o}=@snapshots" "$ROOT_PART" /mnt/.snapshots
    mount -o "${o}=@var_log"   "$ROOT_PART" /mnt/var/log
    log_ok "Root → btrfs with subvolumes  (@  @home  @snapshots  @var_log)"
  else
    mkfs.ext4 -F -L "archroot" "$ROOT_PART" >/dev/null
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/{home,boot/efi}
    log_ok "Root → ext4  ($ROOT_PART)"
  fi

  mount "$EFI_PART" /mnt/boot/efi
  log_ok "EFI  → /mnt/boot/efi"
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  require_root
  require_gum
  print_banner

  gum confirm \
    "Welcome! This will install Arch Linux with Hyprland (UWSM) + SDDM.
All data on the chosen disk will be DESTROYED. Continue?" \
    || { echo "Aborted."; exit 0; }

  if gum confirm "Check internet connectivity before proceeding?"; then
    check_internet
  else
    log_warn "Skipping internet check."
  fi

  # ── Regional & Hardware ────────────────────────────────────────────────────
  pick_timezone
  pick_locale
  pick_keymap
  pick_kernel
  pick_cpu
  pick_audio

  # ── Identity ───────────────────────────────────────────────────────────────
  log_step "System Identity"

  HOSTNAME=$(gum input --placeholder "e.g. archbox" --prompt "  Hostname › ")
  [[ -n "$HOSTNAME" ]] || die "Hostname cannot be empty."
  log_ok "Hostname: ${BOLD}$HOSTNAME${RESET}"

  USERNAME=$(gum input --placeholder "e.g. alice"   --prompt "  Username › ")
  [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] \
    || die "Invalid username — lowercase, numbers, _ or - only."
  log_ok "Username: ${BOLD}$USERNAME${RESET}"

  ROOT_PASS=$(gum  input --password --placeholder "Root password"    --prompt "  Root password    › ")
  [[ -n "$ROOT_PASS" ]] || die "Root password cannot be empty."
  ROOT_PASS2=$(gum input --password --placeholder "Confirm"          --prompt "  Confirm root     › ")
  [[ "$ROOT_PASS" == "$ROOT_PASS2" ]] || die "Root passwords do not match."

  USER_PASS=$(gum  input --password --placeholder "User password"    --prompt "  User password    › ")
  [[ -n "$USER_PASS" ]] || die "User password cannot be empty."
  USER_PASS2=$(gum input --password --placeholder "Confirm"          --prompt "  Confirm user     › ")
  [[ "$USER_PASS" == "$USER_PASS2" ]] || die "User passwords do not match."

  # ── Disk ───────────────────────────────────────────────────────────────────
  log_step "Disk Selection"
  echo ""
  gum style --foreground 81 --bold "  Available block devices:"
  lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINT
  echo ""

  DISK=$(list_disks \
    | gum filter --placeholder "Type name or size to filter…" \
                 --prompt "  Disk › " --height 12 \
                 --header "  Select target disk (ALL DATA WILL BE ERASED):" \
    | awk '{print $1}')
  [[ -n "$DISK" ]] || die "No disk selected."
  log_ok "Target: ${BOLD}$DISK${RESET}"

  # ── Filesystem ─────────────────────────────────────────────────────────────
  log_step "Filesystem"
  FS=$(gum choose \
    --header "  Root filesystem:" \
    "btrfs  — recommended  (subvolumes, zstd, snapshots)" \
    "ext4   — classic      (simple, rock-solid)")
  FS=$(echo "$FS" | awk '{print $1}')
  log_ok "Filesystem: ${BOLD}$FS${RESET}"

  # ── Swap ───────────────────────────────────────────────────────────────────
  log_step "Swap"
  SWAP_SIZE=0
  if gum confirm "  Create a swap partition?"; then
    SWAP_SIZE=$(gum choose --header "  Swap size (GiB):" "2" "4" "8" "16" "32")
    log_ok "Swap: ${BOLD}${SWAP_SIZE} GiB${RESET}"
  else
    log_ok "Swap: none"
  fi

  # ── Bootloader ─────────────────────────────────────────────────────────────
  log_step "Bootloader"
  BOOTLOADER=$(gum choose \
    --header "  Select bootloader:" \
    "grub         — universal, dual-boot friendly" \
    "systemd-boot — minimal, fast, EFI-only")
  BOOTLOADER=$(echo "$BOOTLOADER" | awk '{print $1}')
  log_ok "Bootloader: ${BOLD}$BOOTLOADER${RESET}"

  # ── GPU ────────────────────────────────────────────────────────────────────
  log_step "GPU Driver"
  GPU=$(gum choose \
    --header "  Select GPU driver:" \
    "amd    — mesa + vulkan-radeon + libva-mesa-driver" \
    "intel  — mesa + vulkan-intel + intel-media-driver" \
    "nvidia — nvidia + nvidia-utils (proprietary)" \
    "vm     — open drivers only (VirtualBox / VMware)")
  GPU=$(echo "$GPU" | awk '{print $1}')
  log_ok "GPU: ${BOLD}$GPU${RESET}"

  # ── Extra packages ─────────────────────────────────────────────────────────
  log_step "Optional Packages"
  log_info "Space to toggle, Enter to confirm."
  echo ""

  EXTRA_PKGS=$(gum choose --no-limit \
    --header "  Select extra packages:" \
    "firefox" "chromium" \
    "kitty" "alacritty" "foot" \
    "neovim" "vim" "git" \
    "btop" "fastfetch" "htop" "ranger" \
    "thunar" "dolphin" \
    "mpv" "imv" \
    "zsh" "fish" "starship" \
    "bluez bluez-utils" \
    "cups cups-filters" \
    "noto-fonts noto-fonts-emoji" \
    "ttf-jetbrains-mono-nerd" "ttf-fira-code" \
    "flatpak" "libreoffice-still")
  log_ok "Extras: ${BOLD}${EXTRA_PKGS:-none}${RESET}"

  # ── Summary ────────────────────────────────────────────────────────────────
  echo ""
  gum style \
    --border rounded --border-foreground 99 \
    --padding "1 4" --margin "1 2" \
    "$(gum style --foreground 99 --bold '  Installation Summary')
$(gum style --foreground 81 '  ─────────────────────────────────────────────')
  Kernel        : $KERNEL
  Timezone      : $TIMEZONE
  Locale        : $LOCALE
  Console map   : $KEYMAP
  X11 layout    : $X11_LAYOUT${X11_VARIANT:+  (variant: $X11_VARIANT)}
  Hostname      : $HOSTNAME
  Username      : $USERNAME
  Disk          : $DISK
  Filesystem    : $FS
  Swap          : ${SWAP_SIZE}GiB
  Bootloader    : $BOOTLOADER
  CPU uCode     : ${CPU_UCODE:-none}
  Audio         : $AUDIO
  GPU           : $GPU"
  echo ""

  gum confirm \
    "$(gum style --foreground 196 --bold "⚠  ALL DATA ON $DISK WILL BE PERMANENTLY ERASED. Install now?")" \
    || { echo "Aborted."; exit 0; }

  # ════════════════════════════════════════════════════════════════════════════
  #  INSTALLATION
  # ════════════════════════════════════════════════════════════════════════════

  log_step "Preparing Live Environment"
  loadkeys "$KEYMAP"
  timedatectl set-ntp true
  log_ok "NTP synchronised."

  SKIP_REFLECTOR=false
  if gum confirm "Rank mirrors with reflector for faster downloads?"; then
    log_step "Optimising Mirrors"
    run_spin "Ranking mirrors by speed…" \
      reflector --latest 20 --protocol https --sort rate \
                --save /etc/pacman.d/mirrorlist
    log_ok "Mirrors updated."
  else
    log_warn "Skipping mirror optimisation."
    SKIP_REFLECTOR=true
  fi

  partition_disk "$DISK" "$SWAP_SIZE"
  format_partitions "$FS"

  # ── Package lists ──────────────────────────────────────────────────────────
  log_step "Installing Base System via pacstrap"

  BASE_PKGS=(
    base base-devel
    "$KERNEL" "${KERNEL_HEADERS}" linux-firmware
    networkmanager sudo nano vim
    efibootmgr dosfstools gptfdisk
  )
  "$SKIP_REFLECTOR" || BASE_PKGS+=(reflector)
  [[ "$FS" == "btrfs" ]] && BASE_PKGS+=(btrfs-progs)
  [[ -n "$CPU_UCODE" ]] && BASE_PKGS+=("$CPU_UCODE")

  case "$AUDIO" in
    pipewire)   AUDIO_PKGS=(pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber) ;;
    pulseaudio) AUDIO_PKGS=(pulseaudio pulseaudio-alsa pulseaudio-bluetooth) ;;
  esac

  case "$GPU" in
    amd)    GPU_PKGS=(mesa vulkan-radeon libva-mesa-driver xf86-video-amdgpu) ;;
    intel)  GPU_PKGS=(mesa vulkan-intel intel-media-driver xf86-video-intel) ;;
    nvidia) GPU_PKGS=(nvidia nvidia-utils nvidia-settings) ;;
    vm)     GPU_PKGS=(mesa xf86-video-vmware open-vm-tools) ;;
  esac

  # Hyprland via UWSM:
  HYPR_PKGS=(
    hyprland
    uwsm
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    sddm qt6-wayland qt5-wayland
    grim slurp                        
    wl-clipboard cliphist             
    polkit-gnome gnome-keyring libsecret
    pavucontrol pamixer brightnessctl
    noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd
    thunar gvfs tumbler ffmpegthumbnailer
    networkmanager nm-connection-editor
    xdg-user-dirs
    zip unzip p7zip wget curl
  )

  [[ "$BOOTLOADER" == "grub" ]] && BL_PKGS=(grub) || BL_PKGS=()

  # Build extras array
  EXTRA_ARR=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    read -ra words <<< "$line"
    EXTRA_ARR+=("${words[@]}")
  done <<< "$EXTRA_PKGS"

  ALL_PKGS=("${BASE_PKGS[@]}" "${GPU_PKGS[@]}" "${AUDIO_PKGS[@]}" "${HYPR_PKGS[@]}" "${BL_PKGS[@]}" "${EXTRA_ARR[@]}")
  readarray -t ALL_PKGS < <(printf '%s\n' "${ALL_PKGS[@]}" | sort -u)

  echo -e "${CYAN}Running pacstrap — this can take several minutes…${RESET}"
  pacstrap -K /mnt "${ALL_PKGS[@]}"
  log_ok "Base system installed."

  log_step "Generating fstab"
  genfstab -U /mnt >> /mnt/etc/fstab
  log_ok "fstab written."

  # ── Build chroot script ────────────────────────────────────────────────────
  log_step "Configuring Installed System (chroot)"

  mkdir -p /mnt/tmp
  cat > /mnt/tmp/arch-chroot-setup.sh << CHROOT_EOF
#!/usr/bin/env bash
set -euo pipefail

echo "── Timezone ─────────────────────────────────────────"
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

echo "── Locale ───────────────────────────────────────────"
if grep -q "^#${LOCALE}" /etc/locale.gen; then
  sed -i "s|^#${LOCALE}|${LOCALE}|" /etc/locale.gen
else
  echo "${LOCALE} UTF-8" >> /etc/locale.gen
fi
locale-gen
echo "LANG=${LOCALE}"   >  /etc/locale.conf
echo "LC_ALL=${LOCALE}" >> /etc/locale.conf

echo "── Console keymap ───────────────────────────────────"
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

echo "── Hostname ─────────────────────────────────────────"
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts << HOSTSEOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTSEOF

echo "── Initramfs ────────────────────────────────────────"
mkinitcpio -P

echo "── Bootloader ───────────────────────────────────────"
if [[ "${BOOTLOADER}" == "grub" ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot/efi \
               --bootloader-id=ARCH --recheck
  sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=3/' /etc/default/grub
  grub-mkconfig -o /boot/grub/grub.cfg
else
  bootctl install
  cat > /boot/loader/loader.conf << LEOF
default arch.conf
timeout 3
console-mode max
editor no
LEOF
  ROOT_UUID=\$(blkid -s UUID -o value ${ROOT_PART})
  cat > /boot/loader/entries/arch.conf << LEOF
title   Arch Linux (${KERNEL})
linux   /vmlinuz-${KERNEL}
initrd  /initramfs-${KERNEL}.img
options root=UUID=\$ROOT_UUID rw quiet splash loglevel=3
LEOF
  cat > /boot/loader/entries/arch-fallback.conf << LEOF
title   Arch Linux (${KERNEL} fallback)
linux   /vmlinuz-${KERNEL}
initrd  /initramfs-${KERNEL}-fallback.img
options root=UUID=\$ROOT_UUID rw
LEOF
fi

echo "── Passwords & user ─────────────────────────────────"
echo "root:${ROOT_PASS}" | chpasswd
useradd -m -G wheel,audio,video,storage,optical,network,input -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${USER_PASS}" | chpasswd
xdg-user-dirs-update --force 2>/dev/null || true

echo "── Sudo ─────────────────────────────────────────────"
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL$/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "── Services ─────────────────────────────────────────"
systemctl enable NetworkManager
systemctl enable sddm
[[ "${GPU}" == "vm" ]] && systemctl enable vmtoolsd 2>/dev/null || true

# ── SDDM — launch Hyprland through UWSM ─────────────────────────────────────
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/default.conf << SEOF
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
SessionDir=/usr/share/wayland-sessions
CompositorCommand=uwsm start hyprland-uwsm.desktop
SEOF

echo "Chroot setup complete."
CHROOT_EOF

  chmod +x /mnt/tmp/arch-chroot-setup.sh
  arch-chroot /mnt /tmp/arch-chroot-setup.sh
  rm -f /mnt/tmp/arch-chroot-setup.sh
  log_ok "System configured."

  # ── Unmount ────────────────────────────────────────────────────────────────
  log_step "Finalising"
  run_spin "Syncing filesystems…" sync
  umount -R /mnt
  [[ -n "$SWAP_PART" ]] && swapoff "$SWAP_PART" 2>/dev/null || true
  log_ok "Filesystems unmounted cleanly."

  # ── Done ───────────────────────────────────────────────────────────────────
  echo ""
  gum style \
    --border double --border-foreground 82 \
    --padding "1 5" --margin "1 2" --align center \
    "$(gum style --foreground 82 --bold '✔  Installation Complete!')" \
    "" \
    "Arch Linux + Hyprland (UWSM) + SDDM is ready." \
    "" \
    "  Kernel    : ${KERNEL}" \
    "  User      : ${USERNAME}  @  ${HOSTNAME}" \
    "  Timezone  : ${TIMEZONE}" \
    "  Locale    : ${LOCALE}" \
    "  Disk      : ${DISK}  [${FS}]" \
    "" \
    "$(gum style --foreground 226 '  Remove installation media and reboot.')"
  echo ""

  gum confirm "  Reboot now?" \
    && reboot \
    || echo -e "\n  ${CYAN}Type 'reboot' when ready.${RESET}\n"
}

main "$@"
