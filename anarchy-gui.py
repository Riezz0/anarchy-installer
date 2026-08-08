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

APP_ID = "com.anarchy.installer"
INSTALLER_SCRIPT = "/usr/local/bin/anarchy-installer.sh"
ENV_FILE = "/tmp/.anarchy_install_env"
TERMINAL_FONT = "JetBrains Mono 11"

STEPS = ["Welcome", "Drive", "User", "System", "Flatpaks", "Summary", "Install"]

KERNELS = ["linux", "linux-lts", "linux-zen", "linux-hardened"]
CPUS = ["intel-ucode", "amd-ucode"]
GPUS = ["mesa", "nvidia", "nvidia-lts", "nvidia-dkms",
         "xf86-video-intel", "vulkan-radeon", "vulkan-intel"]
AUDIO_OPTIONS = {"Pipewire": "pipewire", "Pulseaudio": "pulseaudio"}
AUR_HELPERS = ["yay", "paru", "pikaur", "none"]

FLATPAK_DEPS = [
    ("Adw-gtk3 Theme", "org.gtk.Gtk3theme.adw-gtk3"),
    ("Adw-gtk3-dark Theme", "org.gtk.Gtk3theme.adw-gtk3-dark"),
]
FLATPAK_APPS = [
    ("LocalSend",             "org.localsend.localsend_app",       True),
    ("Flatseal",              "com.github.tchx84.Flatseal",        True),
    ("RPCS3 (PS3 Emulator)",  "net.rpcs3.RPCS3",                  True),
    ("RetroArch",             "org.libretro.RetroArch",            True),
    ("sysd-manager",          "io.github.plrigaux.sysd-manager",   True),
    ("ProtonPlus",            "com.vysp3r.ProtonPlus",             True),
    ("OBS Studio",            "com.obsproject.Studio",             True),
    ("GIMP",                  "org.gimp.GIMP",                     False),
    ("Inkscape",              "org.inkscape.Inkscape",             False),
    ("VLC",                   "org.videolan.VLC",                  False),
    ("Discord",               "com.discordapp.Discord",            False),
    ("Lutris",                "net.lutris.Lutris",                 False),
    ("qbittorrent",           "org.qbittorrent.qBittorrent",      False),
    ("OnlyOffice",            "org.onlyoffice.desktopeditors",     False),
    ("Peek",                  "com.uploadedlobster.peek",          False),
    ("File Manager (Nautilus)","org.gnome.Nautilus",               False),
]


# ─── Pywal Theme ──────────────────────────────────────────────────────────────

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
        if not os.path.isfile(self.PYWAL_CACHE):
            return
        try:
            with open(self.PYWAL_CACHE) as f:
                lines = [l.strip() for l in f.readlines() if l.strip()]
            if len(lines) >= 8:
                self.colors["bg"]     = lines[0]
                self.colors["red"]    = lines[1]
                self.colors["green"]  = lines[2]
                self.colors["yellow"] = lines[3]
                self.colors["accent"] = lines[4]
                self.colors["mauve"]  = lines[5]
                self.colors["teal"]   = lines[6]
            if len(lines) >= 16:
                self.colors["fg"] = lines[15]
            self.colors["surface0"] = self._shade(self.colors["bg"], 1.12)
            self.colors["surface1"] = self._shade(self.colors["bg"], 1.25)
            self.colors["surface2"] = self._shade(self.colors["bg"], 1.4)
            self.colors["overlay"]  = self._shade(self.colors["fg"], 0.55)
            self.colors["subtext"]  = self._shade(self.colors["fg"], 0.72)
        except Exception:
            pass

    @staticmethod
    def _shade(hex_color, factor):
        h = hex_color.lstrip("#")
        r, g, b = (int(h[i:i+2], 16) for i in (0, 2, 4))
        return f"#{min(255, int(r*factor)):02x}{min(255, int(g*factor)):02x}{min(255, int(b*factor)):02x}"

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
        @define-color window_bg_color {c['bg']};
        @define-color window_fg_color {c['fg']};
        @define-color shade_color rgba(0,0,0,0.36);
        @define-color outlined_button_border_color {c['overlay']};
        @define-color switch_selected_bg_color {c['accent']};

        .anarchy-page {{
            padding: 32px;
        }}

        .anarchy-card {{
            background-color: {c['surface0']};
            border-radius: 16px;
            padding: 24px;
            border: 1px solid {c['surface1']};
        }}

        .anarchy-card-title {{
            font-size: 18px;
            font-weight: bold;
            color: {c['fg']};
        }}

        .anarchy-card-subtitle {{
            font-size: 13px;
            color: {c['subtext']};
        }}

        .anarchy-step-dot {{
            min-width: 12px;
            min-height: 12px;
            border-radius: 6px;
            background-color: {c['surface1']};
            margin: 4px;
        }}

        .anarchy-step-dot.active {{
            background-color: {c['accent']};
            min-width: 48px;
            border-radius: 6px;
        }}

        .anarchy-step-dot.completed {{
            background-color: {c['green']};
        }}

        .anarchy-step-label {{
            font-size: 12px;
            color: {c['subtext']};
            margin-top: 6px;
        }}

        .anarchy-step-label.active {{
            color: {c['accent']};
            font-weight: bold;
            font-size: 13px;
        }}

        .anarchy-status-row {{
            padding: 8px 12px;
            border-radius: 8px;
            background-color: {c['surface1']};
            margin: 4px 0;
        }}

        .anarchy-drive-row {{
            padding: 12px 16px;
            border-radius: 10px;
            background-color: {c['surface1']};
            margin: 4px 0;
            border: 2px solid transparent;
        }}

        .anarchy-drive-row:hover {{
            border-color: {c['overlay']};
        }}

        .anarchy-drive-row:selected {{
            border-color: {c['accent']};
            background-color: {c['surface2']};
        }}

        .anarchy-input {{
            border-radius: 8px;
            padding: 8px 12px;
            background-color: {c['surface1']};
            border: 1px solid {c['surface2']};
            color: {c['fg']};
            min-height: 24px;
        }}

        .anarchy-input:focus {{
            border-color: {c['accent']};
        }}

        .anarchy-section-title {{
            font-size: 13px;
            font-weight: bold;
            color: {c['subtext']};
            margin-top: 16px;
            margin-bottom: 4px;
        }}

        .anarchy-combo {{
            border-radius: 8px;
            padding: 4px 8px;
        }}

        .anarchy-gpu-check {{
            padding: 6px 12px;
            border-radius: 8px;
            background-color: {c['surface1']};
            margin: 2px;
        }}

        .anarchy-gpu-check:hover {{
            background-color: {c['surface2']};
        }}

        .anarchy-summary-box {{
            background-color: {c['surface0']};
            border-radius: 12px;
            padding: 20px;
            border: 1px solid {c['surface1']};
        }}

        .anarchy-summary-card {{
            background-color: {c['surface0']};
            border-radius: 12px;
            padding: 16px 20px;
            border: 1px solid {c['surface1']};
        }}

        .anarchy-summary-header {{
            font-size: 14px;
            font-weight: bold;
            color: {c['accent']};
            margin-bottom: 8px;
        }}

        .anarchy-summary-row {{
            font-size: 13px;
            color: {c['fg']};
            margin-bottom: 2px;
        }}

        .anarchy-summary-label {{
            color: {c['subtext']};
            font-weight: bold;
        }}

        .anarchy-summary-divider {{
            background-color: {c['surface1']};
            margin: 12px 0;
        }}

        .anarchy-terminal {{
            background-color: {c['bg']};
            border-radius: 12px;
            border: 1px solid {c['surface1']};
        }}

        .anarchy-warn {{
            padding: 12px 16px;
            border-radius: 8px;
            background-color: alpha({c['red']}, 0.1);
            border: 1px solid alpha({c['red']}, 0.3);
            color: {c['red']};
        }}

        .anarchy-success-banner {{
            padding: 24px;
            border-radius: 16px;
            background-color: alpha({c['green']}, 0.08);
            border: 1px solid alpha({c['green']}, 0.2);
        }}
        """

    def vte_palette(self):
        c = self.colors
        return [c["bg"], c["red"], c["green"], c["yellow"],
                c["accent"], c["mauve"], c["teal"], c["fg"],
                c["overlay"], c["red"], c["green"], c["yellow"],
                c["accent"], c["mauve"], c["teal"], c["fg"]]


# ─── Helpers ──────────────────────────────────────────────────────────────────

def list_drives():
    try:
        out = subprocess.check_output(
            ["lsblk", "-dpno", "NAME,SIZE,MODEL"],
            text=True, stderr=subprocess.DEVNULL).strip()
        drives = []
        for line in out.splitlines():
            parts = line.split(None, 2)
            if len(parts) >= 2:
                drives.append({"name": parts[0], "size": parts[1],
                               "model": parts[2] if len(parts) > 2 else ""})
        return drives
    except Exception:
        return []

def list_timezones():
    try:
        out = subprocess.check_output(
            ["timedatectl", "list-timezones"],
            text=True, stderr=subprocess.DEVNULL).strip()
        return out.splitlines()
    except Exception:
        return ["UTC"]

def has_internet():
    try:
        subprocess.run(["ping", "-c", "1", "-W", "2", "8.8.8.8"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        return True
    except Exception:
        return False

def is_efi():
    return os.path.isdir("/sys/firmware/efi")

def is_root():
    return os.geteuid() == 0


# ─── Step Indicator Widget ────────────────────────────────────────────────────

class StepIndicator(Gtk.Box):
    def __init__(self, theme):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL,
                         halign=Gtk.Align.FILL, spacing=0,
                         margin_top=20, margin_bottom=16,
                         margin_start=48, margin_end=48)
        self._theme = theme
        self._dots = []
        self._labels = []
        for i, name in enumerate(STEPS):
            col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL,
                          halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER,
                          spacing=8)
            col.set_hexpand(True)
            dot = Gtk.DrawingArea()
            dot.set_content_width(12)
            dot.set_content_height(12)
            dot.set_halign(Gtk.Align.CENTER)
            dot.set_draw_func(self._draw_dot, i)
            col.append(dot)
            lbl = Gtk.Label()
            lbl.set_markup(f'<span size="large" weight="bold">{name}</span>')
            lbl.set_halign(Gtk.Align.CENTER)
            lbl.set_xalign(0.5)
            lbl.add_css_class("anarchy-step-label")
            col.append(lbl)
            self.append(col)
            self._dots.append(dot)
            self._labels.append(lbl)
            self._dot_states = ["inactive"] * len(STEPS)

        self._dot_states[0] = "active"

    @staticmethod
    def _hex_to_rgb(hex_color):
        h = hex_color.lstrip("#")
        return tuple(int(h[i:i+2], 16) / 255.0 for i in (0, 2, 4))

    def _draw_dot(self, area, cr, width, height, idx):
        state = self._dot_states[idx] if idx < len(self._dot_states) else "inactive"
        c = self._theme.colors
        r, g, b = self._hex_to_rgb(c["accent"]) if state == "active" else \
                   self._hex_to_rgb(c["green"]) if state == "completed" else \
                   self._hex_to_rgb(c["overlay"])
        cr.set_source_rgb(r, g, b)
        if state == "active":
            pill_w, pill_h = 56, 12
            x, y = (width - pill_w) / 2, (height - pill_h) / 2
            radius = pill_h / 2
            cr.new_path()
            cr.move_to(x + radius, y)
            cr.line_to(x + pill_w - radius, y)
            cr.arc(x + pill_w - radius, y + radius, radius, -3.14159/2, 3.14159/2)
            cr.line_to(x + radius, y + pill_h)
            cr.arc(x + radius, y + radius, radius, 3.14159/2, -3.14159/2)
            cr.close_path()
            cr.fill()
        else:
            cr.new_path()
            cr.arc(width / 2, height / 2, 6, 0, 6.28318)
            cr.fill()

    def set_step(self, index):
        c = self._theme.colors
        self._dot_states = ["inactive"] * len(STEPS)
        for i in range(len(STEPS)):
            if i < index:
                self._dot_states[i] = "completed"
            elif i == index:
                self._dot_states[i] = "active"
        for i, lbl in enumerate(self._labels):
            name = STEPS[i]
            if i < index:
                lbl.set_markup(f'<span size="large" weight="bold" color="{c["green"]}">{name}</span>')
            elif i == index:
                lbl.set_markup(f'<span size="large" weight="bold" color="{c["accent"]}">{name}</span>')
            else:
                lbl.set_markup(f'<span size="large" weight="bold" color="{c["overlay"]}">{name}</span>')
        for i, dot in enumerate(self._dots):
            dot.set_content_width(56 if self._dot_states[i] == "active" else 12)
            dot.queue_draw()


# ─── Pages ────────────────────────────────────────────────────────────────────

class WelcomePage(Adw.NavigationPage):
    def __init__(self, theme):
        super().__init__()
        self._theme = theme
        self.set_title("Welcome")
        self.set_tag("welcome")

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL,
                        halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER,
                        spacing=8, margin_top=40, margin_bottom=40,
                        margin_start=60, margin_end=60)
        outer.add_css_class("anarchy-page")

        title = Gtk.Label()
        title.set_markup('<span size="xx-large" weight="bold">Anarchy Linux Installer</span>')
        title.add_css_class("title-1")
        outer.append(title)

        outer.append(Gtk.Separator(margin_top=16, margin_bottom=16))

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                        halign=Gtk.Align.CENTER)
        card.add_css_class("anarchy-card")
        card.set_size_request(360, -1)

        self.internet_status = Gtk.Label()
        self.efi_status = Gtk.Label()
        self.root_status = Gtk.Label()
        for lbl in [self.internet_status, self.efi_status, self.root_status]:
            lbl.set_halign(Gtk.Align.START)
            lbl.add_css_class("anarchy-status-row")
            card.append(lbl)

        outer.append(card)
        self.set_child(outer)

    def update_status(self):
        inet = has_internet()
        efi = is_efi()
        root = is_root()
        c = self._theme.colors
        ok_color = c["green"]
        warn_color = c["yellow"]
        err_color = c["red"]
        dim_color = c["subtext"]
        self.internet_status.set_markup(
            f'<span color="{ok_color}">&#10003;</span>  Internet: {"Connected" if inet else "No connection"}' if inet else
            f'<span color="{err_color}">&#10007;</span>  Internet: No connection')
        self.efi_status.set_markup(
            f'<span color="{ok_color}">&#10003;</span>  Boot: {"UEFI" if efi else "BIOS / Legacy"}' if efi else
            f'<span color="{warn_color}">&#9888;</span>  Boot: BIOS / Legacy')
        self.root_status.set_markup(
            f'<span color="{ok_color}">&#10003;</span>  User: {"Root" if root else "Normal (sudo at install)"}' if root else
            f'<span color="{dim_color}">&#9679;</span>  User: Normal (sudo at install)')
        return inet


class DrivePage(Adw.NavigationPage):
    def __init__(self):
        super().__init__()
        self.set_title("Drive")
        self.set_tag("drive")

        scroll = Gtk.ScrolledWindow()
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16,
                        margin_top=8, margin_bottom=8,
                        margin_start=32, margin_end=32)
        outer.add_css_class("anarchy-page")

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        card.add_css_class("anarchy-card")

        lbl = Gtk.Label()
        lbl.set_markup('<span size="large" weight="bold">Select Target Drive</span>')
        lbl.set_halign(Gtk.Align.START)
        card.append(lbl)

        warn = Gtk.Label()
        warn.set_markup('<span weight="bold">&#9888;  The selected drive will be completely wiped</span>')
        warn.set_halign(Gtk.Align.START)
        warn.add_css_class("anarchy-warn")
        card.append(warn)

        self.selected_drive = None
        self.drive_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        card.append(self.drive_box)

        self.info_label = Gtk.Label()
        self.info_label.set_halign(Gtk.Align.START)
        self.info_label.add_css_class("caption")
        self.info_label.add_css_class("dim-label")
        card.append(self.info_label)

        outer.append(card)
        scroll.set_child(outer)
        self.set_child(scroll)

    def _clear_box(self, box):
        child = box.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            box.remove(child)
            child = nxt

    def load_drives(self):
        self._clear_box(self.drive_box)
        self.selected_drive = None
        drives = list_drives()
        if not drives:
            lbl = Gtk.Label(label="No drives detected")
            lbl.add_css_class("error")
            self.drive_box.append(lbl)
            return

        first = None
        for d in drives:
            rb = Gtk.CheckButton(label=f"  {d['name']}    {d['size']}    {d['model']}")
            rb._drive_name = d["name"]
            rb.set_group(first)
            row = Gtk.Box()
            row.add_css_class("anarchy-drive-row")
            row.append(rb)
            if first is None:
                first = rb
                rb.set_active(True)
                self.selected_drive = d["name"]
            rb.connect("toggled", self._on_toggle, d["name"])
            self.drive_box.append(row)

        self.info_label.set_text(f"{len(drives)} drive(s) detected")

    def _on_toggle(self, button, name):
        if button.get_active():
            self.selected_drive = name


class UserPage(Adw.NavigationPage):
    def __init__(self):
        super().__init__()
        self.set_title("User")
        self.set_tag("user")

        scroll = Gtk.ScrolledWindow()
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16,
                        margin_top=8, margin_bottom=8,
                        margin_start=32, margin_end=32)
        outer.add_css_class("anarchy-page")

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        card.add_css_class("anarchy-card")

        lbl = Gtk.Label()
        lbl.set_markup('<span size="large" weight="bold">User Configuration</span>')
        lbl.set_halign(Gtk.Align.START)
        card.append(lbl)

        grid = Gtk.Grid(row_spacing=10, column_spacing=16, margin_top=12)
        grid.set_column_homogeneous(False)
        grid.set_column_spacing(20)

        row = 0
        for attr, label_text, is_password, placeholder in [
            ("root_pass", "Root Password", True, "Enter root password"),
            ("username", "Username", False, "e.g. john"),
            ("user_pass", "User Password", True, "Enter user password"),
            ("hostname", "Hostname", False, "e.g. archbox"),
        ]:
            lbl = Gtk.Label(label=label_text)
            lbl.set_halign(Gtk.Align.END)
            lbl.add_css_class("anarchy-section-title")
            grid.attach(lbl, 0, row, 1, 1)

            entry = Gtk.Entry()
            entry.set_hexpand(True)
            entry.set_placeholder_text(placeholder)
            entry.add_css_class("anarchy-input")
            if is_password:
                entry.set_visibility(False)
                entry.set_input_purpose(Gtk.InputPurpose.PASSWORD)
            grid.attach(entry, 1, row, 1, 1)
            setattr(self, attr, entry)
            row += 1

        lbl = Gtk.Label(label="Timezone")
        lbl.set_halign(Gtk.Align.END)
        lbl.add_css_class("anarchy-section-title")
        grid.attach(lbl, 0, row, 1, 1)

        self.tz_search = Gtk.SearchEntry(placeholder_text="Search timezones...")
        self.tz_search.set_hexpand(True)
        self.tz_search.add_css_class("anarchy-input")
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

        card.append(grid)
        outer.append(card)
        scroll.set_child(outer)
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
        self.filtered_tz = [z for z in self.all_timezones if query in z.lower()] if query else list(self.all_timezones)
        self._populate_tz(self.filtered_tz)

    def get_timezone(self):
        idx = self.tz_dropdown.get_selected()
        if idx < len(self.filtered_tz):
            return self.filtered_tz[idx]
        return "UTC"


class SystemPage(Adw.NavigationPage):
    def __init__(self):
        super().__init__()
        self.set_title("System")
        self.set_tag("system")

        scroll = Gtk.ScrolledWindow()
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16,
                        margin_top=8, margin_bottom=8,
                        margin_start=32, margin_end=32)
        outer.add_css_class("anarchy-page")

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        card.add_css_class("anarchy-card")

        lbl = Gtk.Label()
        lbl.set_markup('<span size="large" weight="bold">System Options</span>')
        lbl.set_halign(Gtk.Align.START)
        card.append(lbl)

        for section, attr_name, items in [
            ("Kernel", "kernel_row", KERNELS),
            ("CPU Microcode", "cpu_row", CPUS),
            ("Audio Server", "audio_row", list(AUDIO_OPTIONS.keys())),
            ("AUR Helper", "aur_row", AUR_HELPERS),
        ]:
            slbl = Gtk.Label(label=section)
            slbl.set_halign(Gtk.Align.START)
            slbl.add_css_class("anarchy-section-title")
            card.append(slbl)
            model = Gtk.StringList()
            for item in items:
                model.append(item)
            dd = Gtk.DropDown(model=model)
            dd.set_hexpand(True)
            card.append(dd)
            setattr(self, attr_name, dd)

        slbl = Gtk.Label(label="GPU Drivers")
        slbl.set_halign(Gtk.Align.START)
        slbl.add_css_class("anarchy-section-title")
        card.append(slbl)

        gpu_flow = Gtk.FlowBox()
        gpu_flow.set_selection_mode(Gtk.SelectionMode.NONE)
        gpu_flow.set_column_spacing(4)
        gpu_flow.set_row_spacing(4)
        self.gpu_checks = {}
        for g in GPUS:
            cb = Gtk.CheckButton(label=g)
            cb.add_css_class("anarchy-gpu-check")
            self.gpu_checks[g] = cb
            child = Gtk.FlowBoxChild()
            child.set_child(cb)
            gpu_flow.append(child)
        card.append(gpu_flow)

        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        sep.set_margin_top(8)
        sep.set_margin_bottom(8)
        card.append(sep)

        extras_lbl = Gtk.Label(label="Extras")
        extras_lbl.set_halign(Gtk.Align.START)
        extras_lbl.add_css_class("anarchy-section-title")
        card.append(extras_lbl)

        self.vscodium_check = Gtk.CheckButton(label="Install VSCodium + Wal Theme")
        self.vscodium_check.set_active(True)
        self.vscodium_check.add_css_class("anarchy-gpu-check")
        card.append(self.vscodium_check)

        outer.append(card)
        scroll.set_child(outer)
        self.set_child(scroll)

    def get_gpu_packages(self):
        selected = [g for g, cb in self.gpu_checks.items() if cb.get_active()]
        return " ".join(selected) if selected else "none"


class FlatpakPage(Adw.NavigationPage):
    def __init__(self):
        super().__init__()
        self.set_title("Flatpaks")
        self.set_tag("flatpak")

        scroll = Gtk.ScrolledWindow()
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16,
                        margin_top=8, margin_bottom=8,
                        margin_start=32, margin_end=32)
        outer.add_css_class("anarchy-page")

        card = Gtk.Box(orientation=Gtk.Orientation.PIPE, spacing=8)
        card.add_css_class("anarchy-card")
        card.set_orientation(Gtk.Orientation.VERTICAL)

        lbl = Gtk.Label()
        lbl.set_markup('<span size="large" weight="bold">Flatpak Applications</span>')
        lbl.set_halign(Gtk.Align.START)
        card.append(lbl)

        sub = Gtk.Label(label="Select additional applications to install via Flatpak.")
        sub.set_halign(Gtk.Align.START)
        sub.add_css_class("anarchy-section-title")
        card.append(sub)

        dep_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        dep_box.set_margin_top(8)
        dep_lbl = Gtk.Label()
        dep_lbl.set_markup('<span weight="bold" size="small">Always installed (dependencies):</span>')
        dep_lbl.set_halign(Gtk.Align.START)
        dep_box.append(dep_lbl)
        for name, appid in FLATPAK_DEPS:
            row = Gtk.Label(label=f"  {name}  ({appid})")
            row.set_halign(Gtk.Align.START)
            row.add_css_class("anarchy-summary-row")
            dep_box.append(row)
        card.append(dep_box)

        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        sep.set_margin_top(4)
        sep.set_margin_bottom(4)
        card.append(sep)

        self.checks = {}
        app_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        for name, appid, default in FLATPAK_APPS:
            cb = Gtk.CheckButton(label=name)
            cb.set_active(default)
            cb.add_css_class("anarchy-gpu-check")
            self.checks[appid] = cb
            app_box.append(cb)
        card.append(app_box)

        outer.append(card)
        scroll.set_child(outer)
        self.set_child(scroll)

    def get_selected(self):
        return [appid for appid, cb in self.checks.items() if cb.get_active()]


class SummaryPage(Adw.NavigationPage):
    def __init__(self):
        super().__init__()
        self.set_title("Summary")
        self.set_tag("summary")

        scroll = Gtk.ScrolledWindow()
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                        margin_top=8, margin_bottom=8,
                        margin_start=32, margin_end=32)
        outer.add_css_class("anarchy-page")

        lbl = Gtk.Label()
        lbl.set_markup('<span size="large" weight="bold">Installation Summary</span>')
        lbl.set_halign(Gtk.Align.START)
        outer.append(lbl)

        warn = Gtk.Label()
        warn.set_markup('<span weight="bold">&#9888;  This will WIPE the selected drive</span>')
        warn.set_halign(Gtk.Align.START)
        warn.add_css_class("anarchy-warn")
        outer.append(warn)

        self.section_user = self._make_section(outer)
        self.section_drive = self._make_section(outer)
        self.section_system = self._make_section(outer)

        self.labels_user = {}
        self.labels_drive = {}
        self.labels_system = {}

        scroll.set_child(outer)
        self.set_child(scroll)

    def _make_section(self, parent):
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        card.add_css_class("anarchy-summary-card")
        parent.append(card)
        return card

    def _make_row(self, card, key, label):
        row = Gtk.Label()
        row.set_halign(Gtk.Align.START)
        row.set_xalign(0)
        row.add_css_class("anarchy-summary-row")
        lbl = Gtk.Label(label=label)
        lbl.add_css_class("anarchy-summary-label")
        lbl.set_halign(Gtk.Align.START)
        card.append(lbl)
        card.append(row)
        return row

    def _set_section_header(self, card, text, icon):
        header = Gtk.Label()
        header.set_halign(Gtk.Align.START)
        header.set_xalign(0)
        header.set_markup(f'<span size="medium" weight="bold">{icon}  {text}</span>')
        header.add_css_class("anarchy-summary-header")
        card.append(header)

    def update_summary(self, data):
        efi_text = "UEFI" if data.get("is_efi") else "BIOS / Legacy"
        gpu = data.get("gpu_pkgs", "none")
        audio = data.get("audio", "pipewire")

        # Clear previous rows
        for section in [self.section_user, self.section_drive, self.section_system]:
            while section.get_first_child():
                section.remove(section.get_first_child())

        # ── User section ──
        self._set_section_header(self.section_user, "User", "\U0001f464")
        self._make_row(self.section_user, "user", "Username").set_text(data.get("username", "?"))
        self._make_row(self.section_user, "host", "Hostname").set_text(data.get("hostname", "?"))
        self._make_row(self.section_user, "tz", "Timezone").set_text(data.get("timezone", "?"))

        # ── Drive section ──
        self._set_section_header(self.section_drive, "Drive", "\U0001f4be")
        self._make_row(self.section_drive, "drive", "Target").set_text(data.get("drive", "?"))
        self._make_row(self.section_drive, "boot", "Boot Mode").set_text(efi_text)

        # ── System section ──
        self._set_section_header(self.section_system, "System", "\U0001f5a5")
        self._make_row(self.section_system, "kernel", "Kernel").set_text(data.get("kernel", "?"))
        self._make_row(self.section_system, "cpu", "CPU").set_text(data.get("cpu", "?"))
        self._make_row(self.section_system, "gpu", "GPU").set_text(gpu)
        self._make_row(self.section_system, "audio", "Audio").set_text(audio)
        self._make_row(self.section_system, "aur", "AUR Helper").set_text(data.get("aur", "?"))
        vsc = "Yes" if data.get("vscodium") else "No"
        self._make_row(self.section_system, "vsc", "VSCodium").set_text(vsc)
        flatpaks = data.get("flatpaks", [])
        fp_count = len(flatpaks)
        self._make_row(self.section_system, "fp", "Flatpaks").set_text(f"{fp_count} selected")


class InstallPage(Adw.NavigationPage):
    def __init__(self, theme):
        super().__init__()
        self._theme = theme
        self.set_title("Installing")
        self.set_tag("install")

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16,
                        margin_top=8, margin_bottom=8,
                        margin_start=32, margin_end=32)
        outer.add_css_class("anarchy-page")

        self.status_label = Gtk.Label()
        self.status_label.set_markup('<span size="x-large" weight="bold">Installing System...</span>')
        self.status_label.set_halign(Gtk.Align.START)
        outer.append(self.status_label)

        self.progress_bar = Gtk.ProgressBar()
        self.progress_bar.set_show_text(True)

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
            self.terminal.add_css_class("anarchy-terminal")

        term_scroll = Gtk.ScrolledWindow()
        term_scroll.set_child(self.terminal)
        term_scroll.set_vexpand(True)
        term_scroll.add_css_class("anarchy-terminal")
        outer.append(term_scroll)

        self.reboot_button = Gtk.Button(label="  Reboot System  ")
        self.reboot_button.add_css_class("suggested-action")
        self.reboot_button.set_visible(False)
        self.reboot_button.set_halign(Gtk.Align.CENTER)
        self.reboot_button.set_size_request(200, -1)
        self.reboot_button.connect("clicked", self._on_reboot)
        outer.append(self.reboot_button)

        self.set_child(outer)

        self._proc = None
        self._progress_len = 0
        self._term_buffer = ""
        self._ansi_partial = ""

    _ANSI_RE = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]|\x1b\].*?(?:\x07|\x1b\\)|\x1b[^[\]]')

    def _feed_text(self, text):
        if HAS_VTE:
            self.terminal.feed(GLib.Bytes(text.encode("utf-8", errors="replace")), -1)
            return
        text = self._ansi_partial + text
        self._ansi_partial = ""
        incomplete = text.rstrip('\x1b')
        if len(text) - len(incomplete) > 0:
            remainder = text[len(incomplete):]
            if remainder == '\x1b':
                self._ansi_partial = '\x1b'
        self._term_buffer += self._ANSI_RE.sub('', incomplete)
        self._process_term_buffer()

    def _process_term_buffer(self):
        buf = self.terminal.get_buffer()
        while self._term_buffer:
            cr = self._term_buffer.find('\r')
            nl = self._term_buffer.find('\n')
            if cr == -1 and nl == -1:
                break
            if cr != -1 and (nl == -1 or cr < nl):
                segment = self._term_buffer[:cr]
                self._term_buffer = self._term_buffer[cr + 1:]
                if self._progress_len > 0:
                    end = buf.get_end_iter()
                    start = end.copy()
                    start.backward_chars(self._progress_len)
                    buf.delete(start, end)
                if segment:
                    end = buf.get_end_iter()
                    buf.insert(end, segment, -1)
                    self._progress_len = len(segment)
                    m = re.search(r'(\d+)%', segment)
                    if m and self.progress_bar:
                        pct = int(m.group(1)) / 100.0
                        GLib.idle_add(self.progress_bar.set_fraction, pct)
                        GLib.idle_add(self.progress_bar.set_text, f"{m.group(1)}%")
                else:
                    self._progress_len = 0
            else:
                segment = self._term_buffer[:nl]
                self._term_buffer = self._term_buffer[nl + 1:]
                if self._progress_len > 0:
                    end = buf.get_end_iter()
                    start = end.copy()
                    start.backward_chars(self._progress_len)
                    buf.delete(start, end)
                    self._progress_len = 0
                end = buf.get_end_iter()
                buf.insert(end, segment + "\n", -1)
        self.terminal.scroll_mark_onscreen(buf.get_insert())

    def _flush_line(self):
        if HAS_VTE or not self._term_buffer:
            return
        buf = self.terminal.get_buffer()
        end = buf.get_end_iter()
        buf.insert(end, self._term_buffer, -1)
        self._term_buffer = ""
        self.terminal.scroll_mark_onscreen(buf.get_insert())

    def apply_vte_palette(self, palette):
        if not HAS_VTE:
            return
        colors = []
        for hx in palette:
            hx = hx.lstrip("#")
            colors.append(Vte.RGB(int(hx[0:2], 16)*257, int(hx[2:4], 16)*257, int(hx[4:6], 16)*257))
        self.terminal.set_colors(
            colors[7] if len(colors) > 7 else Vte.RGB(0xc000, 0xc000, 0xc000),
            Vte.RGB(0x1a00, 0x1b00, 0x2600), colors, len(colors))

    def start_install(self, env_data):
        self.progress_bar.set_fraction(0.0)
        self.progress_bar.set_text("Writing configuration...")
        self.status_label.set_markup('<span size="x-large" weight="bold">Installing System...</span>')

        env_lines = [
            f'TARGET_DRIVE="{env_data.get("drive", "")}"',
            f'NEW_USER="{env_data.get("username", "")}"',
            f'NEW_HOSTNAME="{env_data.get("hostname", "")}"',
            f'TIMEZONE="{env_data.get("timezone", "UTC")}"',
            f'KERNEL="{env_data.get("kernel", "linux")}"',
            f'CPU="{env_data.get("cpu", "amd-ucode")}"',
            f'GPU_PKGS="{env_data.get("gpu_pkgs", "")}"',
            f'AUDIO_PKGS="{env_data.get("audio_pkgs", "")}"',
            f'AUDIO="{env_data.get("audio", "pipewire")}"',
            f'AUR_HELPER="{env_data.get("aur", "none")}"',
            f'IS_EFI={str(env_data.get("is_efi", False)).lower()}',
            f'INSTALL_VSCODIUM={str(env_data.get("vscodium", False)).lower()}',
            f'FLATPAK_LIST="{",".join(env_data.get("flatpaks", []))}"',
        ]
        env_content = "\n".join(env_lines) + "\n"
        env_content += f'ROOT_PASS={env_data.get("root_pass", "")}\n'
        env_content += f'NEW_PASS={env_data.get("user_pass", "")}\n'
        try:
            with open(ENV_FILE, "w") as f:
                f.write(env_content)
            os.chmod(ENV_FILE, 0o600)
        except Exception as e:
            self.status_label.set_markup(
                f'<span size="x-large" weight="bold" foreground="{self._theme.colors["red"]}">Error: {e}</span>')
            return

        self.progress_bar.set_text("Starting installer...")
        self.progress_bar.pulse()

        cmd = [INSTALLER_SCRIPT, "--gui-env"] if os.geteuid() == 0 else ["sudo", INSTALLER_SCRIPT, "--gui-env"]

        self._proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, bufsize=0)
        os.set_blocking(self._proc.stdout.fileno(), False)
        GLib.timeout_add(30, self._poll_output)

    _PHASE_MARKERS = {
        "Partitioning":          (0.05, "Partitioning drive..."),
        "Formatting":            (0.10, "Formatting partitions..."),
        "Btrfs subvolumes":      (0.15, "Creating Btrfs subvolumes..."),
        "Cloning system":        (0.20, "Cloning system to target..."),
        "Configuring target":    (0.70, "Configuring target system..."),
        "Installing Kernel":     (0.72, "Installing kernel & packages..."),
        "Configuring Grub":      (0.78, "Configuring GRUB..."),
        "Creating Users":        (0.82, "Creating users..."),
        "Installing AUR":        (0.86, "Installing AUR helper..."),
        "Enabling Services":     (0.90, "Enabling services..."),
        "Cloning Dotfiles":      (0.92, "Cloning dotfiles..."),
        "Installing Fonts":      (0.94, "Installing fonts..."),
        "Configuring SDDM":     (0.96, "Configuring SDDM..."),
        "Configuration complete": (1.0, "Done"),
    }

    def _poll_output(self):
        if self._proc is None:
            return False
        ret = self._proc.poll()
        if ret is not None:
            remaining = self._proc.stdout.read()
            if remaining:
                self._feed_text(remaining.decode("utf-8", errors="replace"))
            self._on_finished(ret)
            return False
        chunk = b""
        try:
            while True:
                data = os.read(self._proc.stdout.fileno(), 65536)
                if not data:
                    break
                chunk += data
        except BlockingIOError:
            pass
        if chunk:
            decoded = chunk.decode("utf-8", errors="replace")
            self._feed_text(decoded)
            for marker, (frac, label) in self._PHASE_MARKERS.items():
                if marker in decoded:
                    GLib.idle_add(self.progress_bar.set_fraction, frac)
                    GLib.idle_add(self.progress_bar.set_text, label)
                    break
        return True

    def _on_finished(self, returncode):
        self._flush_line()
        if returncode == 0:
            self.status_label.set_markup(
                '<span size="x-large" weight="bold">Installation Complete!</span>')
            self.progress_bar.set_fraction(1.0)
            self.progress_bar.set_text("Done")
            self.reboot_button.set_visible(True)
            self._feed_text(
                "\n\n========================================\n"
                "  Anarchy Installation Has Completed\n"
                "  Please Press The Reboot Button To\n"
                "  Reboot The System\n"
                "========================================\n")
            if not HAS_VTE:
                def _scroll_to_end():
                    adj = self.terminal.get_vadjustment()
                    adj.set_value(adj.get_upper() - adj.get_page_size())
                    return False
                GLib.idle_add(_scroll_to_end)
        else:
            self.status_label.set_markup(
                f'<span size="x-large" weight="bold" foreground="{self._theme.colors["red"]}">'
                f'Installation Failed (exit code {returncode})</span>')
            self.progress_bar.set_text(f"Failed (exit {returncode})")

    def _on_reboot(self, button):
        try:
            subprocess.run(["systemctl", "reboot"], check=False)
        except Exception:
            pass


# ─── Main Application ────────────────────────────────────────────────────────

class AnarchyInstaller(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.theme = PywalTheme()
        self.config = {}
        self.step_index = 0
        self.connect("activate", self._on_activate)

    def _on_activate(self, app):
        self._css_provider = Gtk.CssProvider()
        self._css_provider.load_from_data(self.theme.css().encode("utf-8"))

        self.win = Adw.ApplicationWindow(application=app)
        self.win.set_title("Anarchy Linux Installer")
        self.win.set_default_size(860, 640)
        self.win.set_size_request(740, 520)

        self.nav = Adw.NavigationView()

        self.step_indicator = StepIndicator(self.theme)

        self.welcome_page = WelcomePage(self.theme)
        self.drive_page = DrivePage()
        self.user_page = UserPage()
        self.system_page = SystemPage()
        self.flatpak_page = FlatpakPage()
        self.summary_page = SummaryPage()
        self.install_page = InstallPage(self.theme)

        self.nav.add(self._wrap_page(self.welcome_page, self._make_welcome_toolbar()))
        self.nav.add(self._wrap_page(self.drive_page, self._make_drive_toolbar()))
        self.nav.add(self._wrap_page(self.user_page, self._make_user_toolbar()))
        self.nav.add(self._wrap_page(self.system_page, self._make_system_toolbar()))
        self.nav.add(self._wrap_page(self.flatpak_page, self._make_flatpak_toolbar()))
        self.nav.add(self._wrap_page(self.summary_page, self._make_summary_toolbar()))
        self.nav.add(self.install_page)

        self.welcome_page.update_status()
        self.drive_page.load_drives()

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.append(self.step_indicator)
        nav_wrap = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        nav_wrap.set_vexpand(True)
        nav_wrap.append(self.nav)
        outer.append(nav_wrap)
        self.win.set_content(outer)

        self.win.present()
        display = self.win.get_display()
        Gtk.StyleContext.add_provider_for_display(display, self._css_provider,
                                                   Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def _set_step(self, index):
        self.step_index = index
        self.step_indicator.set_step(index)

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

    def _make_nav_button(self, label, callback, css_class="flat"):
        btn = Gtk.Button(label=label)
        btn.add_css_class(css_class)
        btn.connect("clicked", callback)
        return btn

    def _make_header_bar(self, title_text, start_widget=None, end_widget=None):
        hb = Adw.HeaderBar()
        hb.set_title_widget(Adw.WindowTitle(title=title_text))
        if start_widget:
            hb.pack_start(start_widget)
        if end_widget:
            hb.pack_end(end_widget)
        return hb

    def _make_welcome_toolbar(self):
        hb = self._make_header_bar("Anarchy Linux Installer")
        hb.set_show_title(False)
        next_btn = self._make_nav_button("  Begin  ", self._on_welcome_next, "suggested-action")
        hb.pack_end(next_btn)
        return hb

    def _make_drive_toolbar(self):
        hb = self._make_header_bar("Drive Selection")
        hb.pack_start(self._make_nav_button("Back", self._on_back))
        hb.pack_end(self._make_nav_button("  Next  ", self._on_drive_next, "suggested-action"))
        return hb

    def _make_user_toolbar(self):
        hb = self._make_header_bar("User Configuration")
        hb.pack_start(self._make_nav_button("Back", self._on_back))
        hb.pack_end(self._make_nav_button("  Next  ", self._on_user_next, "suggested-action"))
        return hb

    def _make_system_toolbar(self):
        hb = self._make_header_bar("System Options")
        hb.pack_start(self._make_nav_button("Back", self._on_back))
        hb.pack_end(self._make_nav_button("  Next  ", self._on_system_next, "suggested-action"))
        return hb

    def _make_flatpak_toolbar(self):
        hb = self._make_header_bar("Flatpak Applications")
        hb.pack_start(self._make_nav_button("Back", self._on_back))
        hb.pack_end(self._make_nav_button("  Next  ", self._on_flatpak_next, "suggested-action"))
        return hb

    def _make_summary_toolbar(self):
        hb = self._make_header_bar("Summary")
        hb.pack_start(self._make_nav_button("Back", self._on_back))
        hb.pack_end(self._make_nav_button("  Install  ", self._on_install, "suggested-action"))
        return hb

    def _on_back(self, *args):
        self.nav.pop()
        self._set_step(max(0, self.step_index - 1))

    def _on_welcome_next(self, *args):
        if not self.welcome_page.update_status():
            self._show_error("No internet connection detected.\nPlease connect to the internet and try again.")
            return
        self._set_step(1)
        self.nav.push_by_tag("drive")

    def _on_drive_next(self, *args):
        if not self.drive_page.selected_drive:
            self._show_error("Please select a target drive.")
            return
        self.config["drive"] = self.drive_page.selected_drive
        self._set_step(2)
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

        self.config.update({"username": username, "hostname": hostname,
                            "root_pass": root_pass, "user_pass": user_pass,
                            "timezone": timezone})
        self._set_step(3)
        self.nav.push_by_tag("system")

    def _on_system_next(self, *args):
        sp = self.system_page
        audio_key = list(AUDIO_OPTIONS.keys())[sp.audio_row.get_selected()]
        audio_val = AUDIO_OPTIONS[audio_key]

        self.config.update({
            "kernel": KERNELS[sp.kernel_row.get_selected()],
            "cpu": CPUS[sp.cpu_row.get_selected()],
            "gpu_pkgs": sp.get_gpu_packages(),
            "audio": audio_val,
            "audio_pkgs": ("pipewire pipewire-pulse pipewire-alsa wireplumber"
                           if audio_val == "pipewire"
                           else "pulseaudio pulseaudio-alsa pulseaudio-bluetooth"),
            "aur": AUR_HELPERS[sp.aur_row.get_selected()],
            "is_efi": is_efi(),
            "vscodium": sp.vscodium_check.get_active(),
        })

        self.summary_page.update_summary(self.config)
        self._set_step(4)
        self.nav.push_by_tag("flatpak")

    def _on_flatpak_next(self, *args):
        self.config["flatpaks"] = self.flatpak_page.get_selected()
        self.summary_page.update_summary(self.config)
        self._set_step(5)
        self.nav.push_by_tag("summary")

    def _on_install(self, *args):
        dialog = Adw.AlertDialog(
            heading="Begin Installation?",
            body=f"This will WIPE {self.config.get('drive', '?')} and install Arch Linux.\nThis action cannot be undone.")
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("install", "Install")
        dialog.set_response_appearance("install", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.connect("response", self._on_install_confirm)
        dialog.present(self.win)

    def _on_install_confirm(self, dialog, response):
        if response == "install":
            self._set_step(6)
            self.nav.push(self.install_page)
            self.install_page.apply_vte_palette(self.theme.vte_palette())
            self.install_page.start_install(self.config)

    def _show_error(self, message):
        dialog = Adw.AlertDialog(heading="Validation Error", body=message)
        dialog.add_response("ok", "OK")
        dialog.present(self.win)


def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    app = AnarchyInstaller()
    return app.run(sys.argv)

if __name__ == "__main__":
    sys.exit(main())
