#!/usr/bin/env python3
import subprocess
import sys
import os
import threading
import json

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, Gio, GLib, Pango

TOKYO_NIGHT = {
    "bg": "#1a1b26",
    "bg_dark": "#16161e",
    "bg_highlight": "#292e42",
    "fg": "#c0caf5",
    "muted": "#565f89",
    "blue": "#7aa2f7",
    "cyan": "#7dcfff",
    "green": "#9ece6a",
    "yellow": "#e0af68",
    "red": "#f7768e",
    "purple": "#bb9af7",
    "comment": "#565f89",
    "selection": "#33467c",
}


def _load_pywal_colors():
    colors_path = os.path.expanduser("~/.cache/wal/colors.json")
    try:
        with open(colors_path) as f:
            data = json.load(f)
        c = data["colors"]
        s = data["special"]
        return {
            "bg": c["color0"],
            "bg_dark": c["color8"],
            "bg_highlight": c["color0"],
            "fg": s["foreground"],
            "muted": c["color8"],
            "blue": c["color4"],
            "cyan": c["color6"],
            "green": c["color2"],
            "yellow": c["color3"],
            "red": c["color1"],
            "purple": c["color5"],
            "comment": c["color8"],
            "selection": c["color4"],
        }
    except (FileNotFoundError, KeyError, json.JSONDecodeError):
        return TOKYO_NIGHT


def _darken(hex_color, factor=0.3):
    hex_color = hex_color.lstrip("#")
    r, g, b = int(hex_color[:2], 16), int(hex_color[2:4], 16), int(hex_color[4:6], 16)
    r, g, b = int(r * (1 - factor)), int(g * (1 - factor)), int(b * (1 - factor))
    return f"#{r:02x}{g:02x}{b:02x}"


def _lighten(hex_color, factor=0.3):
    hex_color = hex_color.lstrip("#")
    r, g, b = int(hex_color[:2], 16), int(hex_color[2:4], 16), int(hex_color[4:6], 16)
    r = min(255, int(r + (255 - r) * factor))
    g = min(255, int(g + (255 - g) * factor))
    b = min(255, int(b + (255 - b) * factor))
    return f"#{r:02x}{g:02x}{b:02x}"


DEVNULL = dict(stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)

DEFAULT_FLATPAKS = {
    "org.localsend.localsend_app",
    "com.github.tchx84.Flatseal",
    "net.rpcs3.RPCS3",
    "org.libretro.RetroArch",
    "io.github.plrigaux.sysd-manager",
    "org.gtk.Gtk3theme.adw-gtk3",
    "org.gtk.Gtk3theme.adw-gtk3-dark",
}

FLATPAKS = [
    ("org.localsend.localsend_app", "LocalSend", "Share files across devices"),
    ("com.github.tchx84.Flatseal", "Flatseal", "Manage Flatpak permissions"),
    ("net.rpcs3.RPCS3", "RPCS3", "PlayStation 3 emulator"),
    ("org.libretro.RetroArch", "RetroArch", "Multi-system emulator frontend"),
    ("io.github.plrigaux.sysd-manager", "Systemd Manager", "Graphical systemd service manager"),
    ("org.gtk.Gtk3theme.adw-gtk3", "adw-gtk3", "GTK3 libadwaita theme"),
    ("org.gtk.Gtk3theme.adw-gtk3-dark", "adw-gtk3-dark", "GTK3 libadwaita dark theme"),
    ("com.obsproject.Studio", "OBS Studio", "Video recording and streaming"),
    ("org.videolan.VLC", "VLC", "Media player"),
    ("com.discordapp.Discord", "Discord", "Voice, video and text communication"),
    ("md.obsidian.Obsidian", "Obsidian", "Knowledge base and note-taking"),
    ("io.github.nickvision.money", "Denaro", "Personal finance manager"),
    ("com.github.tchx84.Games", "Games", "Play your games"),
    ("org.gimp.GIMP", "GIMP", "Image editor"),
    ("org.inkscape.Inkscape", "Inkscape", "Vector graphics editor"),
    ("com.spotify.Client", "Spotify", "Music streaming"),
    ("io.github.nickvision.parabolic", "Parabolic", "Video downloader"),
]


def _cmd_exists(cmd):
    return subprocess.run(["which", cmd], **DEVNULL).returncode == 0


def _make_progress_bar():
    bar = Gtk.ProgressBar()
    bar.set_show_text(True)
    bar.set_margin_start(12)
    bar.set_margin_end(12)
    bar.set_margin_bottom(8)
    bar.set_visible(False)
    return bar


class WelcomePage(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_valign(Gtk.Align.CENTER)
        self.set_halign(Gtk.Align.CENTER)
        self.set_vexpand(True)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        outer.set_halign(Gtk.Align.CENTER)
        outer.set_valign(Gtk.Align.CENTER)
        outer.set_margin_top(40)
        outer.set_margin_bottom(40)
        outer.set_margin_start(40)
        outer.set_margin_end(40)

        icon = Gtk.Image.new_from_icon_name("computer-symbolic")
        icon.set_pixel_size(96)
        icon.add_css_class("accent")
        outer.append(icon)

        spacer = Gtk.Box()
        spacer.set_size_request(-1, 24)
        outer.append(spacer)

        title = Gtk.Label(label="Welcome to Anarchy Linux")
        title.add_css_class("title-1")
        title.set_wrap(True)
        title.set_justify(Gtk.Justification.CENTER)
        outer.append(title)

        spacer2 = Gtk.Box()
        spacer2.set_size_request(-1, 12)
        outer.append(spacer2)

        subtitle = Gtk.Label(label="A minimal, rolling-release Arch-based distribution\ncrafted with a Tokyo Night aesthetic.")
        subtitle.add_css_class("body")
        subtitle.add_css_class("dim-label")
        subtitle.set_wrap(True)
        subtitle.set_justify(Gtk.Justification.CENTER)
        outer.append(subtitle)

        spacer3 = Gtk.Box()
        spacer3.set_size_request(-1, 32)
        outer.append(spacer3)

        info_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        info_box.set_halign(Gtk.Align.CENTER)

        for icon_name, label_text in [
            ("shield-symbolic", "Secure by default — no unnecessary services"),
            ("preferences-system-symbolic", "Minimal install — you choose what you need"),
            ("weather-clear-night-symbolic", "Beautiful Tokyo Night theming throughout"),
        ]:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            row.set_halign(Gtk.Align.CENTER)
            img = Gtk.Image.new_from_icon_name(icon_name)
            img.set_pixel_size(20)
            img.add_css_class("accent")
            row.append(img)
            lbl = Gtk.Label(label=label_text)
            lbl.add_css_class("body")
            lbl.add_css_class("dim-label")
            row.append(lbl)
            info_box.append(row)

        outer.append(info_box)

        spacer4 = Gtk.Box()
        spacer4.set_size_request(-1, 32)
        outer.append(spacer4)

        nav_label = Gtk.Label(label="Use the sidebar to navigate between setup pages.")
        nav_label.add_css_class("caption")
        nav_label.add_css_class("dim-label")
        nav_label.set_justify(Gtk.Justification.CENTER)
        outer.append(nav_label)

        self.append(outer)


class FlatpakPage(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_vexpand(True)

        top_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        top_box.set_margin_top(24)
        top_box.set_margin_start(24)
        top_box.set_margin_end(24)

        header_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        header_box.set_margin_bottom(16)

        title = Gtk.Label(label="Flatpak Applications")
        title.add_css_class("title-1")
        title.set_halign(Gtk.Align.START)
        header_box.append(title)

        desc = Gtk.Label(label="Select the applications you want to install from Flathub.")
        desc.add_css_class("body")
        desc.add_css_class("dim-label")
        desc.set_halign(Gtk.Align.START)
        desc.set_wrap(True)
        header_box.append(desc)

        top_box.append(header_box)

        self.status_label = Gtk.Label(label="Checking installed flatpaks...")
        self.status_label.add_css_class("caption")
        self.status_label.add_css_class("dim-label")
        self.status_label.set_halign(Gtk.Align.START)
        self.status_label.set_margin_bottom(8)
        top_box.append(self.status_label)

        self.progress_bar = _make_progress_bar()
        self.progress_bar.set_margin_bottom(12)
        top_box.append(self.progress_bar)

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        btn_box.set_halign(Gtk.Align.END)
        btn_box.set_margin_bottom(16)

        self.select_all_btn = Gtk.Button(label="Select All")
        self.select_all_btn.add_css_class("flat")
        self.select_all_btn.add_css_class("accent")
        self.select_all_btn.connect("clicked", self._select_all)
        self.select_all_btn.set_sensitive(False)
        btn_box.append(self.select_all_btn)

        self.unselect_all_btn = Gtk.Button(label="Unselect All")
        self.unselect_all_btn.add_css_class("flat")
        self.unselect_all_btn.connect("clicked", self._unselect_all)
        self.unselect_all_btn.set_sensitive(False)
        btn_box.append(self.unselect_all_btn)

        self.install_btn = Gtk.Button(label="Install Selected")
        self.install_btn.add_css_class("suggested-action")
        self.install_btn.connect("clicked", self._install)
        self.install_btn.set_sensitive(False)
        btn_box.append(self.install_btn)

        top_box.append(btn_box)

        self.append(top_box)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        list_content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        list_content.set_margin_start(24)
        list_content.set_margin_end(24)
        list_content.set_margin_bottom(24)

        self.checkboxes = []
        self.checkbox_rows = []
        list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        list_box.add_css_class("boxed-list")

        for app_id, name, description in FLATPAKS:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            row.set_margin_top(8)
            row.set_margin_bottom(8)
            row.set_margin_start(12)
            row.set_margin_end(12)

            check = Gtk.CheckButton()
            check.app_id = app_id
            check.set_active(False)
            self.checkboxes.append(check)

            text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            name_label = Gtk.Label(label=name)
            name_label.add_css_class("body")
            name_label.set_halign(Gtk.Align.START)
            name_label.set_wrap(True)
            text_box.append(name_label)

            desc_label = Gtk.Label(label=description)
            desc_label.add_css_class("caption")
            desc_label.add_css_class("dim-label")
            desc_label.set_halign(Gtk.Align.START)
            desc_label.set_wrap(True)
            text_box.append(desc_label)

            row.append(check)
            row.append(text_box)
            self.checkbox_rows.append((row, desc_label))
            list_box.append(row)

        list_content.append(list_box)

        spacer2 = Gtk.Box()
        spacer2.set_size_request(-1, 16)
        list_content.append(spacer2)

        startup_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        startup_box.set_margin_start(12)
        startup_box.set_margin_end(12)
        startup_box.set_margin_bottom(8)

        startup_label = Gtk.Label(label="Open welcome app on boot")
        startup_label.add_css_class("body")
        startup_label.set_halign(Gtk.Align.START)
        startup_label.set_hexpand(True)
        startup_box.append(startup_label)

        self.startup_switch = Gtk.Switch()
        self.startup_switch.set_active(self._get_startup_state())
        self.startup_switch.set_halign(Gtk.Align.END)
        self.startup_switch.connect("notify::active", self._on_startup_toggle)
        startup_box.append(self.startup_switch)

        list_content.append(startup_box)

        scroll.set_child(list_content)
        self.append(scroll)

        threading.Thread(target=self._detect_installed, daemon=True).start()

    def _detect_installed(self):
        result = subprocess.run(
            ["flatpak", "list", "--app", "--columns=application"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            text=True,
        )
        installed = set()
        for line in result.stdout.strip().splitlines():
            line = line.strip()
            if line:
                installed.add(line)

        GLib.idle_add(self._apply_installed_state, installed)

    def _apply_installed_state(self, installed):
        for i, (cb) in enumerate(self.checkboxes):
            is_installed = cb.app_id in installed
            if is_installed:
                cb.set_active(False)
                cb.set_sensitive(False)
                row, desc_label = self.checkbox_rows[i]
                row.add_css_class("dim-label")
                desc_label.set_text(f"{FLATPAKS[i][2]} — Installed")

        self.status_label.set_text("")
        self.select_all_btn.set_sensitive(True)
        self.unselect_all_btn.set_sensitive(True)
        self.install_btn.set_sensitive(True)

    def _select_all(self, btn):
        for cb in self.checkboxes:
            if cb.get_sensitive():
                cb.set_active(True)

    def _unselect_all(self, btn):
        for cb in self.checkboxes:
            if cb.get_sensitive():
                cb.set_active(False)

    def _get_startup_state(self):
        service_dir = os.path.expanduser("~/.config/systemd/user")
        service_file = os.path.join(service_dir, "anarchy-welcome.service")
        return os.path.exists(service_file)

    def _on_startup_toggle(self, switch, gparam):
        service_dir = os.path.expanduser("~/.config/systemd/user")
        service_file = os.path.join(service_dir, "anarchy-welcome.service")

        if switch.get_active():
            os.makedirs(service_dir, exist_ok=True)
            with open(service_file, "w") as f:
                f.write(
                    "[Unit]\n"
                    "Description=Anarchy Welcome App\n"
                    "After=graphical-session.target\n"
                    "\n"
                    "[Service]\n"
                    "Type=simple\n"
                    f"ExecStart=/usr/bin/python3 /usr/local/bin/anarchy-welcome\n"
                    "Restart=on-failure\n"
                    "\n"
                    "[Install]\n"
                    "WantedBy=default.target\n"
                )
            subprocess.run(["systemctl", "--user", "daemon-reload"], **DEVNULL)
            subprocess.run(["systemctl", "--user", "enable", "anarchy-welcome.service"], **DEVNULL)
        else:
            subprocess.run(["systemctl", "--user", "disable", "anarchy-welcome.service"], **DEVNULL)
            if os.path.exists(service_file):
                os.remove(service_file)
            subprocess.run(["systemctl", "--user", "daemon-reload"], **DEVNULL)

    def _install(self, btn):
        selected = [cb.app_id for cb in self.checkboxes if cb.get_active()]
        if not selected:
            self.status_label.set_text("No applications selected.")
            return

        self.install_btn.set_sensitive(False)
        self.select_all_btn.set_sensitive(False)
        self.unselect_all_btn.set_sensitive(False)
        total = len(selected)
        self.progress_bar.set_visible(True)
        self.progress_bar.set_fraction(0.0)
        self.status_label.set_text(f"Installing {total} application(s)...")

        def run_install():
            for i, app_id in enumerate(selected):
                GLib.idle_add(self.status_label.set_text, f"[{i + 1}/{total}] Installing {app_id}...")
                GLib.idle_add(self.progress_bar.set_fraction, i / total)
                try:
                    subprocess.run(
                        ["flatpak", "install", "-y", "flathub", app_id],
                        check=True,
                        **DEVNULL,
                    )
                except subprocess.CalledProcessError as e:
                    GLib.idle_add(self.status_label.set_text, f"Failed to install {app_id}: {e}")
                    GLib.idle_add(self._install_done_ui, False)
                    return
            GLib.idle_add(self.progress_bar.set_fraction, 1.0)
            GLib.idle_add(self.status_label.set_text, f"Successfully installed {total} application(s).")
            GLib.idle_add(self._install_done_ui, True)

        threading.Thread(target=run_install, daemon=True).start()

    def _install_done_ui(self, success):
        self.install_btn.set_sensitive(True)
        self.select_all_btn.set_sensitive(True)
        self.unselect_all_btn.set_sensitive(True)


class VSCodePage(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_vexpand(True)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        content.set_margin_top(24)
        content.set_margin_bottom(24)
        content.set_margin_start(24)
        content.set_margin_end(24)

        title = Gtk.Label(label="Theming & Appearance")
        title.add_css_class("title-1")
        title.set_halign(Gtk.Align.START)
        content.append(title)

        spacer = Gtk.Box()
        spacer.set_size_request(-1, 8)
        content.append(spacer)

        desc = Gtk.Label(label="Set up pywal theming for VS Code and Firefox.")
        desc.add_css_class("body")
        desc.add_css_class("dim-label")
        desc.set_halign(Gtk.Align.START)
        desc.set_wrap(True)
        content.append(desc)

        spacer2 = Gtk.Box()
        spacer2.set_size_request(-1, 24)
        content.append(spacer2)

        # VS Code section
        vscode_frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        vscode_frame.add_css_class("boxed-list")
        vscode_frame.set_margin_bottom(16)

        vscode_header = Gtk.Label(label="VS Code — Pywal Theme")
        vscode_header.add_css_class("heading")
        vscode_header.set_halign(Gtk.Align.START)
        vscode_header.set_margin_start(12)
        vscode_header.set_margin_top(12)
        vscode_frame.append(vscode_header)

        vscode_desc = Gtk.Label(
            label="Installs Code-OSS if needed, then sets up the wal-theme extension."
        )
        vscode_desc.add_css_class("caption")
        vscode_desc.add_css_class("dim-label")
        vscode_desc.set_halign(Gtk.Align.START)
        vscode_desc.set_margin_start(12)
        vscode_desc.set_wrap(True)
        vscode_frame.append(vscode_desc)

        content.append(vscode_frame)

        self.vscode_btn = Gtk.Button(label="Setup VS Code Theme")
        self.vscode_btn.add_css_class("suggested-action")
        self.vscode_btn.set_halign(Gtk.Align.START)
        self.vscode_btn.set_margin_start(12)
        self.vscode_btn.set_margin_bottom(8)
        self.vscode_btn.connect("clicked", self._setup_vscode)
        vscode_frame.append(self.vscode_btn)

        self.vscode_progress = _make_progress_bar()
        vscode_frame.append(self.vscode_progress)

        self.vscode_status = Gtk.Label(label="")
        self.vscode_status.add_css_class("caption")
        self.vscode_status.add_css_class("dim-label")
        self.vscode_status.set_halign(Gtk.Align.START)
        self.vscode_status.set_margin_start(12)
        self.vscode_status.set_margin_bottom(12)
        vscode_frame.append(self.vscode_status)

        spacer3 = Gtk.Box()
        spacer3.set_size_request(-1, 16)
        content.append(spacer3)

        # Firefox section
        firefox_frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        firefox_frame.add_css_class("boxed-list")

        firefox_header = Gtk.Label(label="Firefox Extensions")
        firefox_header.add_css_class("heading")
        firefox_header.set_halign(Gtk.Align.START)
        firefox_header.set_margin_start(12)
        firefox_header.set_margin_top(12)
        firefox_frame.append(firefox_header)

        firefox_desc = Gtk.Label(
            label="Install pywalfox for theming and Proton Pass for secure passwords."
        )
        firefox_desc.add_css_class("caption")
        firefox_desc.add_css_class("dim-label")
        firefox_desc.set_halign(Gtk.Align.START)
        firefox_desc.set_margin_start(12)
        firefox_desc.set_wrap(True)
        firefox_frame.append(firefox_desc)

        content.append(firefox_frame)

        self.firefox_btn = Gtk.Button(label="Setup Pywalfox")
        self.firefox_btn.add_css_class("suggested-action")
        self.firefox_btn.set_halign(Gtk.Align.START)
        self.firefox_btn.set_margin_start(12)
        self.firefox_btn.set_margin_bottom(8)
        self.firefox_btn.connect("clicked", self._setup_pywalfox)
        firefox_frame.append(self.firefox_btn)

        self.firefox_progress = _make_progress_bar()
        firefox_frame.append(self.firefox_progress)

        self.firefox_status = Gtk.Label(label="")
        self.firefox_status.add_css_class("caption")
        self.firefox_status.add_css_class("dim-label")
        self.firefox_status.set_halign(Gtk.Align.START)
        self.firefox_status.set_margin_start(12)
        self.firefox_status.set_margin_bottom(12)
        firefox_frame.append(self.firefox_status)

        proton_sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        proton_sep.set_margin_start(12)
        proton_sep.set_margin_end(12)
        firefox_frame.append(proton_sep)

        proton_btn = Gtk.Button(label="Install Proton Pass Extension")
        proton_btn.add_css_class("flat")
        proton_btn.add_css_class("accent")
        proton_btn.set_halign(Gtk.Align.START)
        proton_btn.set_margin_start(12)
        proton_btn.set_margin_bottom(8)
        proton_btn.connect("clicked", self._install_proton_pass)
        firefox_frame.append(proton_btn)

        self.proton_progress = _make_progress_bar()
        firefox_frame.append(self.proton_progress)

        self.proton_status = Gtk.Label(label="")
        self.proton_status.add_css_class("caption")
        self.proton_status.add_css_class("dim-label")
        self.proton_status.set_halign(Gtk.Align.START)
        self.proton_status.set_margin_start(12)
        self.proton_status.set_margin_bottom(12)
        firefox_frame.append(self.proton_status)

        spacer4 = Gtk.Box()
        spacer4.set_size_request(-1, 16)
        content.append(spacer4)

        # Pywal regenerate button
        gen_frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        gen_frame.add_css_class("boxed-list")

        gen_header = Gtk.Label(label="Regenerate Pywal Colors")
        gen_header.add_css_class("heading")
        gen_header.set_halign(Gtk.Align.START)
        gen_header.set_margin_start(12)
        gen_header.set_margin_top(12)
        gen_frame.append(gen_header)

        gen_desc = Gtk.Label(
            label="Re-apply your current pywal colors to all configured applications."
        )
        gen_desc.add_css_class("caption")
        gen_desc.add_css_class("dim-label")
        gen_desc.set_halign(Gtk.Align.START)
        gen_desc.set_margin_start(12)
        gen_desc.set_wrap(True)
        gen_frame.append(gen_desc)

        self.gen_btn = Gtk.Button(label="Regenerate Colors")
        self.gen_btn.add_css_class("flat")
        self.gen_btn.add_css_class("accent")
        self.gen_btn.set_halign(Gtk.Align.START)
        self.gen_btn.set_margin_start(12)
        self.gen_btn.set_margin_bottom(8)
        self.gen_btn.connect("clicked", self._regen_wal)
        gen_frame.append(self.gen_btn)

        self.gen_progress = _make_progress_bar()
        gen_frame.append(self.gen_progress)

        self.gen_status = Gtk.Label(label="")
        self.gen_status.add_css_class("caption")
        self.gen_status.add_css_class("dim-label")
        self.gen_status.set_halign(Gtk.Align.START)
        self.gen_status.set_margin_start(12)
        self.gen_status.set_margin_bottom(12)
        gen_frame.append(self.gen_status)

        content.append(gen_frame)

        scroll.set_child(content)
        self.append(scroll)

    def _setup_vscode(self, btn):
        self.vscode_btn.set_sensitive(False)
        self.vscode_progress.set_visible(True)
        self.vscode_progress.set_fraction(0.0)

        steps = [
            ("Checking for Code-OSS...", 0.0),
            ("Installing Code-OSS...", 0.2),
            ("Installing wal-theme extension...", 0.5),
            ("Writing settings.json...", 0.7),
            ("Applying pywal colors...", 0.9),
        ]

        def run():
            GLib.idle_add(self.vscode_status.set_text, steps[0][0])
            GLib.idle_add(self.vscode_progress.set_fraction, steps[0][1])

            code_cmd = None
            for cmd in ("code-oss", "code"):
                if _cmd_exists(cmd):
                    code_cmd = cmd
                    break

            if code_cmd is None:
                GLib.idle_add(self.vscode_status.set_text, steps[1][0])
                GLib.idle_add(self.vscode_progress.set_fraction, steps[1][1])
                try:
                    subprocess.run(
                        ["sudo", "pacman", "-Sy", "--noconfirm", "code"],
                        check=True,
                        **DEVNULL,
                    )
                    code_cmd = "code-oss" if _cmd_exists("code-oss") else "code"
                except subprocess.CalledProcessError:
                    GLib.idle_add(self.vscode_status.set_text, "Failed to install Code-OSS.")
                    GLib.idle_add(self._vscode_done_ui)
                    return

            GLib.idle_add(self.vscode_status.set_text, steps[2][0])
            GLib.idle_add(self.vscode_progress.set_fraction, steps[2][1])
            subprocess.run(
                [code_cmd, "--install-extension", "dlasagno.wal-theme", "--force"],
                **DEVNULL,
            )

            GLib.idle_add(self.vscode_status.set_text, steps[3][0])
            GLib.idle_add(self.vscode_progress.set_fraction, steps[3][1])
            settings_dir = os.path.expanduser("~/.config/Code - OSS/User")
            settings_file = os.path.join(settings_dir, "settings.json")
            os.makedirs(settings_dir, exist_ok=True)
            import json
            settings = {
                "workbench.colorTheme": "Wal",
                "wal.path": os.path.expanduser("~/.cache/wal/colors.json"),
            }
            with open(settings_file, "w") as f:
                json.dump(settings, f, indent=4)

            GLib.idle_add(self.vscode_status.set_text, steps[4][0])
            GLib.idle_add(self.vscode_progress.set_fraction, steps[4][1])
            subprocess.run(["wal", "-R"], **DEVNULL)

            GLib.idle_add(self.vscode_progress.set_fraction, 1.0)
            GLib.idle_add(self.vscode_status.set_text, "Done! VS Code theme configured.")
            GLib.idle_add(self._vscode_done_ui)

        threading.Thread(target=run, daemon=True).start()

    def _vscode_done_ui(self):
        self.vscode_btn.set_sensitive(True)

    def _setup_pywalfox(self, btn):
        self.firefox_btn.set_sensitive(False)
        self.firefox_progress.set_visible(True)
        self.firefox_progress.set_fraction(0.0)

        def run():
            GLib.idle_add(self.firefox_status.set_text, "Checking for pywalfox...")
            GLib.idle_add(self.firefox_progress.set_fraction, 0.0)

            if _cmd_exists("pywalfox"):
                GLib.idle_add(self.firefox_status.set_text, "pywalfox found, setting up...")
                GLib.idle_add(self.firefox_progress.set_fraction, 0.5)
            else:
                GLib.idle_add(self.firefox_status.set_text, "Installing pywalfox...")
                GLib.idle_add(self.firefox_progress.set_fraction, 0.2)
                installed = False
                for cmd in [
                    ["sudo", "pacman", "-S", "--noconfirm", "pywalfox"],
                    ["pip", "install", "--user", "pywalfox"],
                    ["pip", "install", "--break-system-packages", "pywalfox"],
                ]:
                    try:
                        subprocess.run(cmd, check=True, **DEVNULL)
                        installed = True
                        break
                    except (subprocess.CalledProcessError, FileNotFoundError):
                        continue
                if not installed:
                    GLib.idle_add(self.firefox_status.set_text, "Failed to install pywalfox.")
                    GLib.idle_add(self._firefox_done_ui)
                    return
                GLib.idle_add(self.firefox_progress.set_fraction, 0.5)

            GLib.idle_add(self.firefox_status.set_text, "Setting up browser native messaging...")
            GLib.idle_add(self.firefox_progress.set_fraction, 0.7)
            try:
                subprocess.run(["pywalfox", "install"], check=True, **DEVNULL)
                GLib.idle_add(self.firefox_progress.set_fraction, 1.0)
                GLib.idle_add(
                    self.firefox_status.set_text,
                    "Done! Enable the pywalfox theme in Firefox add-ons.",
                )
            except subprocess.CalledProcessError:
                GLib.idle_add(self.firefox_status.set_text, "Failed to setup pywalfox native messaging.")
            GLib.idle_add(self._firefox_done_ui)

        threading.Thread(target=run, daemon=True).start()

    def _firefox_done_ui(self):
        self.firefox_btn.set_sensitive(True)

    def _install_proton_pass(self, btn):
        self.proton_progress.set_visible(True)
        self.proton_progress.set_fraction(0.0)

        def run():
            GLib.idle_add(self.proton_status.set_text, "Installing Proton Pass extension...")
            GLib.idle_add(self.proton_progress.set_fraction, 0.3)

            firefox_cmd = None
            for cmd in ("firefox", "firefox-esr", "librewolf", "floorp"):
                if _cmd_exists(cmd):
                    firefox_cmd = cmd
                    break

            if firefox_cmd is None:
                GLib.idle_add(self.proton_status.set_text, "No Firefox-based browser found.")
                GLib.idle_add(self.proton_progress.set_fraction, 0.0)
                return

            GLib.idle_add(self.proton_progress.set_fraction, 0.5)
            try:
                subprocess.run(
                    [firefox_cmd, "--install-extension", "protonvpn.proton-pass"],
                    check=True,
                    **DEVNULL,
                )
                GLib.idle_add(self.proton_progress.set_fraction, 1.0)
                GLib.idle_add(self.proton_status.set_text, "Done! Proton Pass installed.")
            except subprocess.CalledProcessError:
                GLib.idle_add(self.proton_status.set_text, "Failed to install Proton Pass.")

        threading.Thread(target=run, daemon=True).start()

    def _regen_wal(self, btn):
        self.gen_btn.set_sensitive(False)
        self.gen_progress.set_visible(True)
        self.gen_progress.set_fraction(0.0)

        def run():
            GLib.idle_add(self.gen_status.set_text, "Regenerating colors...")
            GLib.idle_add(self.gen_progress.set_fraction, 0.5)
            subprocess.run(["wal", "-R"], **DEVNULL)
            GLib.idle_add(self.gen_progress.set_fraction, 1.0)
            GLib.idle_add(self.gen_status.set_text, "Colors regenerated.")
            GLib.idle_add(self._gen_done_ui)

        threading.Thread(target=run, daemon=True).start()

    def _gen_done_ui(self):
        self.gen_btn.set_sensitive(True)


class AnarchyWelcome(Adw.Application):
    def __init__(self):
        super().__init__(application_id="com.anarchy.welcome")
        self.connect("activate", self._on_activate)

    def _on_activate(self, app):
        self.win = Adw.ApplicationWindow(application=app)
        self.win.set_title("Anarchy Linux — Welcome")
        self.win.set_default_size(800, 600)

        self.css_provider = Gtk.CssProvider()
        self._apply_colors()

        Gtk.StyleContext.add_provider_for_display(
            self.win.get_display(),
            self.css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        self._start_color_watcher()

        toolbar_view = Adw.ToolbarView()

        header = Adw.HeaderBar()
        header.add_css_class("flat")
        toolbar_view.add_top_bar(header)

        split_view = Adw.NavigationSplitView()
        split_view.set_min_sidebar_width(200)
        split_view.set_max_sidebar_width(280)

        sidebar_page = Adw.NavigationPage(title="Pages")
        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        sidebar.set_margin_top(8)

        nav_items = [
            ("welcome-symbolic", "Welcome"),
            ("system-software-install-symbolic", "Flatpaks"),
            ("accessories-text-editor-symbolic", "Theming"),
        ]

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.stack.set_transition_duration(200)

        self.stack.add_named(WelcomePage(), "welcome")
        self.stack.add_named(FlatpakPage(), "flatpaks")
        self.stack.add_named(VSCodePage(), "devsetup")

        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        listbox.add_css_class("navigation-sidebar")

        for i, (icon, label) in enumerate(nav_items):
            row = Gtk.ListBoxRow()
            row._page_name = ["welcome", "flatpaks", "devsetup"][i]
            hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            hbox.set_margin_top(8)
            hbox.set_margin_bottom(8)
            hbox.set_margin_start(12)
            hbox.set_margin_end(12)
            img = Gtk.Image.new_from_icon_name(icon)
            img.set_pixel_size(20)
            hbox.append(img)
            lbl = Gtk.Label(label=label)
            lbl.set_halign(Gtk.Align.START)
            hbox.append(lbl)
            row.set_child(hbox)
            listbox.append(row)

        listbox.connect("row-selected", self._on_row_selected)
        sidebar.append(listbox)

        sidebar_page.set_child(sidebar)
        split_view.set_sidebar(sidebar_page)

        content_page = AnarchyNavigationPage(title="Content")
        content_page.set_child(self.stack)
        split_view.set_content(content_page)

        toolbar_view.set_content(split_view)
        self.win.set_content(toolbar_view)
        self.win.present()

        listbox.select_row(listbox.get_row_at_index(0))

    def _on_row_selected(self, listbox, row):
        if row is None:
            return
        self.stack.set_visible_child_name(row._page_name)

    def _apply_colors(self):
        colors = _load_pywal_colors()
        bg = colors["bg"]
        bg_dark = colors["bg_dark"]
        bg_highlight = _darken(bg, 0.15)
        fg = colors["fg"]
        accent = colors["blue"]

        self.css_provider.load_from_string(f"""
            @define-color bg_color {bg};
            @define-color fg_color {fg};
            @define-color accent_color {accent};
            @define-color window_bg_color {bg};
            @define-color window_fg_color {fg};
            @define-color headerbar_bg_color {bg_dark};
            @define-color headerbar_fg_color {fg};
            @define-color card_bg_color {bg_highlight};
            @define-color card_fg_color {fg};
            @define-color dialog_bg_color {bg_dark};
            @define-color dialog_fg_color {fg};
            @define-color sidebar_bg_color {bg_dark};
            @define-color sidebar_fg_color {fg};
            @define-color sidebar_shade_color rgba(0, 0, 0, 0.25);
            @define-color shade_color rgba(0, 0, 0, 0.25);
            @define-color view_bg_color {bg};
            @define-color view_fg_color {fg};
            @define-color warning_color {colors['yellow']};
            @define-color error_color {colors['red']};
            @define-color success_color {colors['green']};

            .title-1 {{
                font-weight: bold;
                font-size: 24px;
                color: {fg};
            }}

            .title-2 {{
                font-weight: bold;
                font-size: 18px;
                color: {fg};
            }}

            .heading {{
                font-weight: bold;
                font-size: 14px;
                color: {fg};
            }}

            .boxed-list {{
                border-radius: 12px;
                background-color: {bg_highlight};
            }}

            .accent {{
                color: {accent};
            }}

            .dim-label {{
                color: alpha({fg}, 0.5);
            }}

            .mono {{
                font-family: monospace;
                font-size: 11px;
            }}

            .navigation-sidebar {{
                background-color: {bg_dark};
            }}

            .navigation-sidebar row {{
                border-radius: 8px;
                margin: 2px 8px;
                padding: 4px 8px;
            }}

            .navigation-sidebar row:selected {{
                background-color: alpha({accent}, 0.2);
            }}

            progressbar {{
                color: {fg};
            }}

            progressbar trough {{
                background-color: alpha({accent}, 0.15);
                border-radius: 4px;
                min-height: 6px;
            }}
            progressbar progress {{
                background-color: {accent};
                border-radius: 4px;
                min-height: 6px;
            }}

            button.suggested-action {{
                background-color: {accent};
                color: {bg};
                border-radius: 8px;
                font-weight: bold;
            }}

            button.suggested-action:hover {{
                background-color: {_lighten(accent, 0.15)};
            }}

            button.flat {{
                border-radius: 8px;
            }}

            switch {{
                background-color: alpha({accent}, 0.3);
                border-radius: 16px;
            }}

            switch:checked {{
                background-color: {accent};
            }}

            checkbutton {{
                color: {fg};
            }}
        """)

    def _start_color_watcher(self):
        colors_path = os.path.expanduser("~/.cache/wal/colors.json")
        colors_dir = os.path.dirname(colors_path)
        colors_file = os.path.basename(colors_path)

        self._last_mtime = 0
        try:
            self._last_mtime = os.path.getmtime(colors_path)
        except OSError:
            pass

        self._file_monitor = Gio.File.new_for_path(colors_dir).monitor_directory(
            Gio.FileMonitorFlags.NONE, None
        )
        self._file_monitor.connect("changed", self._on_colors_changed)

    def _on_colors_changed(self, monitor, file, other_file, event):
        if event != Gio.FileMonitorEvent.CHANGES_DONE_HINT:
            return
        colors_path = os.path.expanduser("~/.cache/wal/colors.json")
        if file.get_path() != colors_path:
            return
        try:
            mtime = os.path.getmtime(colors_path)
            if mtime == self._last_mtime:
                return
            self._last_mtime = mtime
        except OSError:
            return
        GLib.idle_add(self._apply_colors)


class AnarchyNavigationPage(Adw.NavigationPage):
    pass


def main():
    app = AnarchyWelcome()
    app.run(sys.argv)


if __name__ == "__main__":
    main()
