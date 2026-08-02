#!/usr/bin/env python3
"""Anarchy Installer — GTK4 + libadwaita GUI Frontend"""

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib, GObject, Gio, Pango

import os
import subprocess
import re
import sys
import signal

HAS_VTE = False
try:
    gi.require_version("Vte", "2.91")
    from gi.repository import Vte
    HAS_VTE = True
except (ImportError, ValueError):
    pass

# ─── Constants ────────────────────────────────────────────────────────────────

APP_ID = "com.anarchy.installer"
INSTALLER_SCRIPT = "/usr/local/bin/anarchy-installer.sh"
ENV_FILE = "/tmp/.anarchy_install_env"
TERMINAL_FONT = "JetBrains Mono 11"

KERNELS = ["linux", "linux-lts", "linux-zen", "linux-hardened"]
CPUS = ["intel-ucode", "amd-ucode"]
GPUS = ["mesa", "nvidia", "nvidia-lts", "nvidia-dkms",
         "xf86-video-intel", "vulkan-radeon", "vulkan-intel"]
AUDIO_OPTIONS = {"Pipewire": "pipewire", "Pulseaudio": "pulseaudio"}
AUR_HELPERS = ["yay", "paru", "pikaur", "none"]


# ─── Pywal Theme Loader ──────────────────────────────────────────────────────

class PywalTheme:
    PYWAL_CACHE = os.path.expanduser("~/.cache/wal/colors")

    FALLBACK = {
        "bg": "#1a1b26", "fg": "#c0caf5", "accent": "#7aa2f7",
        "red": "#f7768e", "green": "#9ece6a", "yellow": "#e0af68",
        "mauve": "#bb9af7", "teal": "#7dcfff", "subtext": "#a9b1d6",
        "surface0": "#24283b", "surface1": "#414868", "overlay": "#565f89",
    }

    def __init__(self):
        self.colors = dict(self.FALLBACK)
        self._load()

    def _load(self):
        path = self.PYWAL_CACHE
        if not os.path.isfile(path):
            return
        try:
            with open(path) as f:
                lines = [l.strip() for l in f.readlines() if l.strip()]
            if len(lines) >= 8:
                self.colors["bg"]      = lines[0]
                self.colors["red"]     = lines[1]
                self.colors["green"]   = lines[2]
                self.colors["yellow"]  = lines[3]
                self.colors["accent"]  = lines[4]
                self.colors["mauve"]   = lines[5]
                self.colors["teal"]    = lines[6]
            if len(lines) >= 16:
                self.colors["fg"] = lines[15]
            self.colors["surface0"] = self._darken(self.colors["bg"], 1.15)
            self.colors["surface1"] = self._darken(self.colors["bg"], 1.3)
            self.colors["overlay"]  = self._darken(self.colors["fg"], 0.6)
            self.colors["subtext"]  = self._darken(self.colors["fg"], 0.75)
        except Exception:
            pass

    @staticmethod
    def _darken(hex_color, factor):
        hex_color = hex_color.lstrip("#")
        r, g, b = (int(hex_color[i:i+2], 16) for i in (0, 2, 4))
        r = min(255, int(r * factor))
        g = min(255, int(g * factor))
        b = min(255, int(b * factor))
        return f"#{r:02x}{g:02x}{b:02x}"

    def css(self):
        c = self.colors
        return f"""
        @define-color bg_color {c['bg']};
        @define-color fg_color {c['fg']};
        @define-color accent_color {c['accent']};
        @define-color error_color {c['red']};
        @define-color success_color {c['green']};
        @define-color warning_color {c['yellow']};
        @define-color view_bg_color {c['surface0']};
        @define-color headerbar_bg_color {c['surface0']};
        @define-color headerbar_fg_color {c['fg']};
        @define-color card_bg_color {c['surface0']};
        @define-color card_fg_color {c['fg']};
        @define-color dialog_bg_color {c['surface1']};
        @define-color popover_bg_color {c['surface1']};
        @define-color sidebar_bg_color {c['surface0']};
        @define-color sidebar_fg_color {c['subtext']};
        @define-color window_bg_color {c['bg']};
        @define-color window_fg_color {c['fg']};
        @define-color shade_color rgba(0,0,0,0.36);
        @define-color outlined_button_border_color {c['overlay']};
        @define-color switch_selected_bg_color {c['accent']};
        """

    def vte_palette(self):
        c = self.colors
        return [
            c["bg"], c["red"], c["green"], c["yellow"],
            c["accent"], c["mauve"], c["teal"], c["fg"],
            c["overlay"], c["red"], c["green"], c["yellow"],
            c["accent"], c["mauve"], c["teal"], c["fg"],
        ]


# ─── Helper: list block devices ──────────────────────────────────────────────

def list_drives():
    try:
        out = subprocess.check_output(
            ["lsblk", "-dpno", "NAME,SIZE,MODEL"],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
        drives = []
        for line in out.splitlines():
            parts = line.split(None, 2)
            if len(parts) >= 2:
                name = parts[0]
                size = parts[1]
                model = parts[2] if len(parts) > 2 else ""
                drives.append({"name": name, "size": size, "model": model})
        return drives
    except Exception:
        return []


def list_timezones():
    try:
        out = subprocess.check_output(
            ["timedatectl", "list-timezones"],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
        return out.splitlines()
    except Exception:
        return ["UTC"]


def has_internet():
    try:
        subprocess.run(
            ["ping", "-c", "1", "-W", "2", "8.8.8.8"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=5
        )
        return True
    except Exception:
        return False


def is_efi():
    return os.path.isdir("/sys/firmware/efi")


def is_root():
    return os.geteuid() == 0


# ─── Pages ────────────────────────────────────────────────────────────────────

class WelcomePage(Adw.NavigationPage):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title("Welcome")
        self.set_tag("welcome")

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL,
                       halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER,
                       spacing=24, margin_top=48, margin_bottom=48,
                       margin_start=48, margin_end=48)

        title = Gtk.Label()
        title.set_markup('<span size="xx-large" weight="bold">Anarchy Linux Installer</span>')
        title.add_css_class("title-1")
        box.append(title)

        subtitle = Gtk.Label(label="Configure and install your system")
        subtitle.add_css_class("subtitle")
        subtitle.add_css_class("dim-label")
        box.append(subtitle)

        # Status indicators
        self.internet_status = Gtk.Label()
        self.efi_status = Gtk.Label()
        self.root_status = Gtk.Label()
        for lbl in [self.internet_status, self.efi_status, self.root_status]:
            lbl.add_css_class("caption")
            lbl.add_css_class("dim-label")
            box.append(lbl)

        self.set_child(box)

    def update_status(self):
        inet = has_internet()
        efi = is_efi()
        root = is_root()
        self.internet_status.set_markup(
            f'{"✓" if inet else "✗"} Internet: {"Connected" if inet else "No connection"}')
        self.internet_status.add_css_class("success" if inet else "error")
        self.efi_status.set_markup(
            f'{"✓" if efi else "✗"} Boot mode: {"UEFI" if efi else "BIOS/Legacy"}')
        self.efi_status.add_css_class("success" if efi else "warning")
        self.root_status.set_markup(
            f'{"✓" if root else "✗"} Privileges: {"Root" if root else "Normal user (pkexec will elevate)"}')
        self.root_status.add_css_class("success" if root else "dim-label")
        return inet


class DrivePage(Adw.NavigationPage):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title("Drive")
        self.set_tag("drive")

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                        margin_top=24, margin_bottom=24,
                        margin_start=24, margin_end=24)

        header = Gtk.Label()
        header.set_markup('<span size="large" weight="bold">Select Target Drive</span>')
        header.set_halign(Gtk.Align.START)
        vbox.append(header)

        warn = Gtk.Label(label="WARNING: The selected drive will be completely wiped.")
        warn.add_css_class("caption")
        warn.add_css_class("error")
        warn.set_halign(Gtk.Align.START)
        vbox.append(warn)

        self.selected_drive = None
        self.radio_group = []

        self.drive_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        vbox.append(self.drive_box)

        self.info_label = Gtk.Label(label="")
        self.info_label.add_css_class("caption")
        self.info_label.add_css_class("dim-label")
        self.info_label.set_halign(Gtk.Align.START)
        vbox.append(self.info_label)

        self.set_child(vbox)

    def _clear_box(self, box):
        child = box.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            box.remove(child)
            child = nxt

    def load_drives(self):
        self._clear_box(self.drive_box)
        self.radio_group.clear()
        self.selected_drive = None

        drives = list_drives()
        if not drives:
            lbl = Gtk.Label(label="No drives found")
            lbl.add_css_class("error")
            self.drive_box.append(lbl)
            return

        first = None
        for d in drives:
            label = f"{d['name']}  —  {d['size']}  {d['model']}"
            rb = Gtk.CheckButton(label=label)
            rb._drive_name = d["name"]
            rb.set_group(first)
            if first is None:
                first = rb
                rb.set_active(True)
                self.selected_drive = d["name"]
            rb.connect("toggled", self._on_toggle, d["name"])
            self.drive_box.append(rb)
            self.radio_group.append(rb)

        self.info_label.set_text(f"{len(drives)} drive(s) detected")

    def _on_toggle(self, button, name):
        if button.get_active():
            self.selected_drive = name


class UserPage(Adw.NavigationPage):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title("User")
        self.set_tag("user")

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)

        grid = Gtk.Grid(row_spacing=12, column_spacing=12,
                         margin_top=24, margin_bottom=24,
                         margin_start=24, margin_end=24)
        grid.set_column_homogeneous(False)

        row = 0
        for attr, label_text, is_password in [
            ("root_pass", "Root Password", True),
            ("username", "Username", False),
            ("user_pass", "User Password", True),
            ("hostname", "Hostname", False),
        ]:
            lbl = Gtk.Label(label=label_text)
            lbl.set_halign(Gtk.Align.END)
            lbl.add_css_class("heading")
            grid.attach(lbl, 0, row, 1, 1)

            entry = Gtk.Entry()
            entry.set_hexpand(True)
            entry.set_placeholder_text(label_text)
            if is_password:
                entry.set_visibility(False)
                entry.set_input_purpose(Gtk.InputPurpose.PASSWORD)
            grid.attach(entry, 1, row, 1, 1)
            setattr(self, attr, entry)
            row += 1

        # Timezone
        lbl = Gtk.Label(label="Timezone")
        lbl.set_halign(Gtk.Align.END)
        lbl.add_css_class("heading")
        grid.attach(lbl, 0, row, 1, 1)

        self.tz_search = Gtk.SearchEntry(placeholder_text="Search timezones...")
        self.tz_search.set_hexpand(True)
        grid.attach(self.tz_search, 1, row, 1, 1)
        row += 1

        self.tz_liststore = Gtk.StringList()
        self.tz_dropdown = Gtk.DropDown(model=self.tz_liststore)
        self.tz_dropdown.set_hexpand(True)
        grid.attach(self.tz_dropdown, 1, row, 1, 1)

        self.all_timezones = list_timezones()
        self.filtered_tz = list(self.all_timezones)
        self._populate_tz(self.filtered_tz)

        self.tz_search.connect("search-changed", self._on_tz_search)

        scroll.set_child(grid)
        self.set_child(scroll)

    def _populate_tz(self, zones):
        self.tz_liststore = Gtk.StringList()
        for z in zones[:100]:
            self.tz_liststore.append(z)
        self.tz_dropdown.set_model(self.tz_liststore)
        if self.tz_liststore.get_n_items() > 0:
            self.tz_dropdown.set_selected(0)

    def _on_tz_search(self, entry):
        query = entry.get_text().lower()
        if not query:
            self.filtered_tz = list(self.all_timezones)
        else:
            self.filtered_tz = [z for z in self.all_timezones if query in z.lower()]
        self._populate_tz(self.filtered_tz)

    def get_timezone(self):
        idx = self.tz_dropdown.get_selected()
        if idx < len(self.filtered_tz):
            return self.filtered_tz[idx]
        return "UTC"


class SystemPage(Adw.NavigationPage):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title("System")
        self.set_tag("system")

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16,
                       margin_top=24, margin_bottom=24,
                       margin_start=24, margin_end=24)

        # Kernel
        box.append(self._section_label("Kernel"))
        self.kernel_row = self._combo_row(KERNELS)
        box.append(self.kernel_row)

        # CPU
        box.append(self._section_label("CPU Microcode"))
        self.cpu_row = self._combo_row(CPUS)
        box.append(self.cpu_row)

        # GPU
        box.append(self._section_label("GPU Drivers"))
        gpu_flow = Gtk.FlowBox()
        gpu_flow.set_selection_mode(Gtk.SelectionMode.NONE)
        gpu_flow.set_column_spacing(8)
        gpu_flow.set_row_spacing(8)
        self.gpu_checks = {}
        for g in GPUS:
            cb = Gtk.CheckButton(label=g)
            self.gpu_checks[g] = cb
            child = Gtk.FlowBoxChild()
            child.set_child(cb)
            gpu_flow.append(child)
        box.append(gpu_flow)

        # Audio
        box.append(self._section_label("Audio Server"))
        self.audio_row = self._combo_row(list(AUDIO_OPTIONS.keys()))
        box.append(self.audio_row)

        # AUR helper
        box.append(self._section_label("AUR Helper"))
        self.aur_row = self._combo_row(AUR_HELPERS)
        box.append(self.aur_row)

        scroll.set_child(box)
        self.set_child(scroll)

    @staticmethod
    def _section_label(text):
        lbl = Gtk.Label(label=text)
        lbl.set_halign(Gtk.Align.START)
        lbl.add_css_class("heading")
        return lbl

    @staticmethod
    def _combo_row(items):
        model = Gtk.StringList()
        for item in items:
            model.append(item)
        dd = Gtk.DropDown(model=model)
        dd.set_hexpand(True)
        return dd

    def get_gpu_packages(self):
        selected = [g for g, cb in self.gpu_checks.items() if cb.get_active()]
        if not selected:
            return "none"
        return " ".join(selected)


class SummaryPage(Adw.NavigationPage):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title("Summary")
        self.set_tag("summary")

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                        margin_top=24, margin_bottom=24,
                        margin_start=24, margin_end=24)

        header = Gtk.Label()
        header.set_markup('<span size="large" weight="bold">Installation Summary</span>')
        header.set_halign(Gtk.Align.START)
        vbox.append(header)

        warn = Gtk.Label()
        warn.set_markup('<span weight="bold">⚠ This will WIPE the selected drive.</span>')
        warn.add_css_class("error")
        warn.set_halign(Gtk.Align.START)
        vbox.append(warn)

        self.summary_label = Gtk.Label()
        self.summary_label.set_halign(Gtk.Align.START)
        self.summary_label.set_vexpand(True)
        self.summary_label.set_xalign(0)
        self.summary_label.set_wrap(True)
        self.summary_label.set_selectable(True)
        vbox.append(self.summary_label)

        self.set_child(vbox)

    def update_summary(self, data):
        efi_text = "UEFI" if data.get("is_efi") else "BIOS/Legacy"
        gpu = data.get("gpu_pkgs", "none")
        audio = data.get("audio", "pipewire")
        lines = [
            f'<b>User:</b>      {data.get("username", "?")}',
            f'<b>Hostname:</b>  {data.get("hostname", "?")}',
            f'<b>Timezone:</b>  {data.get("timezone", "?")}',
            '',
            f'<b>Drive:</b>     {data.get("drive", "?")}',
            f'<b>Boot Mode:</b> {efi_text}',
            '',
            f'<b>Kernel:</b>    {data.get("kernel", "?")}',
            f'<b>CPU:</b>       {data.get("cpu", "?")}',
            f'<b>GPU:</b>       {gpu}',
            f'<b>Audio:</b>     {audio}',
            f'<b>AUR:</b>       {data.get("aur", "?")}',
        ]
        self.summary_label.set_markup('\n'.join(lines))


class InstallPage(Adw.NavigationPage):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title("Installing")
        self.set_tag("install")

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                        margin_top=12, margin_start=12, margin_end=12, margin_bottom=12)

        self.status_label = Gtk.Label()
        self.status_label.set_markup('<span size="large" weight="bold">Installing...</span>')
        self.status_label.set_halign(Gtk.Align.START)
        vbox.append(self.status_label)

        self.progress_bar = Gtk.ProgressBar()
        self.progress_bar.set_show_text(True)
        self.progress_bar.set_text("Preparing...")
        vbox.append(self.progress_bar)

        if HAS_VTE:
            self.terminal = Vte.Terminal()
            self.terminal.set_font(Vte.FontDescription(TERMINAL_FONT))
            self.terminal.set_vexpand(True)
            self.terminal.set_hexpand(True)
            self.terminal.set_scrollbackLines(10000)
            self.terminal.set_mouse_autohide(True)
        else:
            self.terminal = Gtk.TextView()
            self.terminal.set_editable(False)
            self.terminal.set_cursor_visible(False)
            self.terminal.set_vexpand(True)
            self.terminal.set_hexpand(True)
            self.terminal.set_monospace(True)
            self.terminal.add_css_class("view")
            buf = self.terminal.get_buffer()
            tag = buf.create_tag("bold", weight=Pango.Weight.BOLD)
            tag_err = buf.create_tag("error", foreground="#f7768e")
            tag_ok = buf.create_tag("ok", foreground="#9ece6a")

        term_scroll = Gtk.ScrolledWindow()
        term_scroll.set_child(self.terminal)
        term_scroll.set_vexpand(True)
        vbox.append(term_scroll)

        self.reboot_button = Gtk.Button(label="Reboot")
        self.reboot_button.add_css_class("suggested-action")
        self.reboot_button.set_visible(False)
        self.reboot_button.connect("clicked", self._on_reboot)
        vbox.append(self.reboot_button)

        self.set_child(vbox)

        self._proc = None
        self._watch_id = None

    def _feed_text(self, text):
        if HAS_VTE:
            self.terminal.feed(GLib.Bytes(text.encode("utf-8", errors="replace")), -1)
        else:
            buf = self.terminal.get_buffer()
            end_iter = buf.get_end_iter()
            buf.insert(end_iter, text, -1)
            self.terminal.scroll_mark_onscreen(buf.get_insert())

    def apply_vte_palette(self, palette):
        if not HAS_VTE:
            return
        colors = []
        for hex_c in palette:
            hex_c = hex_c.lstrip("#")
            r = int(hex_c[0:2], 16) * 257
            g = int(hex_c[2:4], 16) * 257
            b = int(hex_c[4:6], 16) * 257
            colors.append(Vte.RGB(r, g, b))
        self.terminal.set_colors(
            colors[7] if len(colors) > 7 else Vte.RGB(0xc000, 0xc000, 0xc000),
            Vte.RGB(0x1a00, 0x1b00, 0x2600),
            colors, len(colors)
        )

    def start_install(self, env_data):
        self.progress_bar.set_fraction(0.0)
        self.progress_bar.set_text("Writing configuration...")
        self.status_label.set_markup(
            '<span size="large" weight="bold">Installing System...</span>')

        env_lines = []
        for k, v in env_data.items():
            env_lines.append(f'{k}="{v}"')
        env_content = "\n".join(env_lines) + "\n"
        try:
            with open(ENV_FILE, "w") as f:
                f.write(env_content)
            os.chmod(ENV_FILE, 0o600)
        except Exception as e:
            self.status_label.set_markup(
                f'<span size="large" weight="bold" foreground="#f7768e">Error: {e}</span>')
            return

        self.progress_bar.set_text("Starting installer...")
        self.progress_bar.pulse()

        root_pass = env_data.get("root_pass", "")
        if os.geteuid() == 0:
            cmd = [INSTALLER_SCRIPT, "--gui-env"]
        else:
            cmd = ["sudo", "-S", INSTALLER_SCRIPT, "--gui-env"]

        self._proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0
        )

        if os.geteuid() != 0 and root_pass:
            self._proc.stdin.write((root_pass + "\n").encode())
            self._proc.stdin.flush()
            self._proc.stdin.close()

        GLib.timeout_add(50, self._poll_output)

        self._check_done()

    def _poll_output(self):
        if self._proc is None:
            return False
        ret = self._proc.poll()
        if ret is not None:
            self._on_finished(ret)
            return False
        try:
            data = os.read(self._proc.stdout.fileno(), 4096)
            if data:
                text = data.decode("utf-8", errors="replace")
                self._feed_text(text)
                self.progress_bar.pulse()
        except (OSError, ValueError):
            pass
        return True

    def _on_finished(self, returncode):
        if returncode == 0:
            self.status_label.set_markup(
                '<span size="large" weight="bold">Installation Complete!</span>')
            self.progress_bar.set_fraction(1.0)
            self.progress_bar.set_text("Done")
            self.reboot_button.set_visible(True)
            self._feed_text("\n\n=== Installation Complete ===\n"
                            "Log in and run 'hyprmon' to configure your monitors.\n")
        else:
            self.status_label.set_markup(
                f'<span size="large" weight="bold" foreground="#f7768e">'
                f'Installation Failed (exit code {returncode})</span>')
            self.progress_bar.set_text(f"Failed (exit {returncode})")
            self._feed_text(f"\n=== Installation Failed (exit {returncode}) ===\n")

    def _on_reboot(self, button):
        try:
            subprocess.run(["systemctl", "reboot"], check=False)
        except Exception:
            pass


# ─── Main Application ────────────────────────────────────────────────────────

class AnarchyInstaller(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID,
                          flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.theme = PywalTheme()
        self.config = {}
        self.connect("activate", self._on_activate)

    def _on_activate(self, app):
        self._apply_theme()

        self.win = Adw.ApplicationWindow(application=app)
        self.win.set_title("Anarchy Linux Installer")
        self.win.set_default_size(800, 600)
        self.win.set_size_request(700, 500)

        self.nav = Adw.NavigationView()
        self.win.set_content(self.nav)

        # Create pages
        self.welcome_page = WelcomePage()
        self.drive_page = DrivePage()
        self.user_page = UserPage()
        self.system_page = SystemPage()
        self.summary_page = SummaryPage()
        self.install_page = InstallPage()

        # Wrap in NavigationPages with headers/toolbar
        self.nav.add(self._wrap_page(self.welcome_page, self._make_welcome_toolbar()))
        self.nav.add(self._wrap_page(self.drive_page, self._make_drive_toolbar()))
        self.nav.add(self._wrap_page(self.user_page, self._make_user_toolbar()))
        self.nav.add(self._wrap_page(self.system_page, self._make_system_toolbar()))
        self.nav.add(self._wrap_page(self.summary_page, self._make_summary_toolbar()))
        self.nav.add(self.install_page)

        self.welcome_page.update_status()
        self.drive_page.load_drives()

        self.win.present()
        self._apply_theme_to_display()

    def _apply_theme(self):
        self._css_provider = Gtk.CssProvider()
        self._css_provider.load_from_data(self.theme.css().encode("utf-8"))

    def _apply_theme_to_display(self):
        display = self.win.get_display()
        Gtk.StyleContext.add_provider_for_display(
            display,
            self._css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def _wrap_page(self, child, toolbar):
        page = Adw.NavigationPage()
        page.set_title(child.get_title())
        page.set_tag(child.get_tag())
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        vbox.append(toolbar)
        child.set_vexpand(True)
        vbox.append(child)
        page.set_child(vbox)
        return page

    # ── Toolbar builders ──────────────────────────────────────────────────

    def _make_nav_button(self, label, callback, css_class="flat"):
        btn = Gtk.Button(label=label)
        btn.add_css_class(css_class)
        btn.connect("clicked", callback)
        return btn

    def _make_header_bar(self, title_text, start_widget=None, end_widget=None):
        hb = Adw.HeaderBar()
        title_widget = Adw.WindowTitle(title=title_text)
        hb.set_title_widget(title_widget)
        if start_widget:
            hb.pack_start(start_widget)
        if end_widget:
            hb.pack_end(end_widget)
        return hb

    def _make_welcome_toolbar(self):
        hb = self._make_header_bar("Welcome")
        next_btn = self._make_nav_button("Begin", self._on_welcome_next, "suggested-action")
        hb.pack_end(next_btn)
        return hb

    def _make_drive_toolbar(self):
        hb = self._make_header_bar("Drive Selection")
        back_btn = self._make_nav_button("Back", self._on_back)
        next_btn = self._make_nav_button("Next", self._on_drive_next, "suggested-action")
        hb.pack_start(back_btn)
        hb.pack_end(next_btn)
        return hb

    def _make_user_toolbar(self):
        hb = self._make_header_bar("User Configuration")
        back_btn = self._make_nav_button("Back", self._on_back)
        next_btn = self._make_nav_button("Next", self._on_user_next, "suggested-action")
        hb.pack_start(back_btn)
        hb.pack_end(next_btn)
        return hb

    def _make_system_toolbar(self):
        hb = self._make_header_bar("System Options")
        back_btn = self._make_nav_button("Back", self._on_back)
        next_btn = self._make_nav_button("Next", self._on_system_next, "suggested-action")
        hb.pack_start(back_btn)
        hb.pack_end(next_btn)
        return hb

    def _make_summary_toolbar(self):
        hb = self._make_header_bar("Summary")
        back_btn = self._make_nav_button("Back", self._on_back)
        install_btn = self._make_nav_button("Install", self._on_install, "suggested-action")
        hb.pack_start(back_btn)
        hb.pack_end(install_btn)
        return hb

    # ── Navigation callbacks ──────────────────────────────────────────────

    def _on_back(self, *args):
        self.nav.pop()

    def _on_welcome_next(self, *args):
        inet = self.welcome_page.update_status()
        if not inet:
            self._show_error("No internet connection detected.\nPlease connect to the internet and try again.")
            return
        self.nav.push_by_tag("drive")

    def _on_drive_next(self, *args):
        drive = self.drive_page.selected_drive
        if not drive:
            self._show_error("Please select a target drive.")
            return
        self.config["drive"] = drive
        self.nav.push_by_tag("user")

    def _on_user_next(self, *args):
        up = self.user_page
        username = up.username.get_text().strip()
        hostname = up.hostname.get_text().strip()
        root_pass = up.root_pass.get_text().strip()
        user_pass = up.user_pass.get_text().strip()
        timezone = up.get_timezone()

        errors = []
        if not username:
            errors.append("Username is required")
        if not hostname:
            errors.append("Hostname is required")
        if not root_pass:
            errors.append("Root password is required")
        if not user_pass:
            errors.append("User password is required")
        if not re.match(r'^[a-z_][a-z0-9_-]*$', username):
            errors.append("Username must be lowercase alphanumeric with _ or -")
        if errors:
            self._show_error("\n".join(errors))
            return

        self.config.update({
            "username": username,
            "hostname": hostname,
            "root_pass": root_pass,
            "user_pass": user_pass,
            "timezone": timezone,
        })
        self.nav.push_by_tag("system")

    def _on_system_next(self, *args):
        sp = self.system_page
        kernel = KERNELS[sp.kernel_row.get_selected()]
        cpu = CPUS[sp.cpu_row.get_selected()]
        audio_key = list(AUDIO_OPTIONS.keys())[sp.audio_row.get_selected()]
        audio_val = AUDIO_OPTIONS[audio_key]
        aur = AUR_HELPERS[sp.aur_row.get_selected()]
        gpu_pkgs = sp.get_gpu_packages()

        if audio_val == "pipewire":
            audio_pkgs = "pipewire pipewire-pulse pipewire-alsa wireplumber"
        else:
            audio_pkgs = "pulseaudio pulseaudio-alsa pulseaudio-bluetooth"

        self.config.update({
            "kernel": kernel,
            "cpu": cpu,
            "gpu_pkgs": gpu_pkgs,
            "audio": audio_val,
            "audio_pkgs": audio_pkgs,
            "aur": aur,
            "is_efi": is_efi(),
        })

        self.summary_page.update_summary(self.config)
        self.nav.push_by_tag("summary")

    def _on_install(self, *args):
        dialog = Adw.AlertDialog(
            heading="Begin Installation?",
            body=f"This will WIPE {self.config.get('drive', '?')} and install Arch Linux.\nThis action cannot be undone.",
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("install", "Install")
        dialog.set_response_appearance("install", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.connect("response", self._on_install_confirm)
        dialog.present(self.win)

    def _on_install_confirm(self, dialog, response):
        if response == "install":
            self.nav.push(self.install_page)
            self.install_page.apply_vte_palette(self.theme.vte_palette())
            self.install_page.start_install(self.config)

    def _show_error(self, message):
        dialog = Adw.AlertDialog(
            heading="Validation Error",
            body=message,
        )
        dialog.add_response("ok", "OK")
        dialog.present(self.win)


# ─── Entry Point ──────────────────────────────────────────────────────────────

def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    app = AnarchyInstaller()
    return app.run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
